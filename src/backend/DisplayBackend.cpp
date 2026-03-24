#include "DisplayBackend.h"

#include "SystemHelpers.h"

#include <QCoreApplication>
#include <QDir>
#include <QDebug>
#include <QSocketNotifier>
#include <QTimer>

#include <fcntl.h>
#include <linux/input.h>
#include <unistd.h>

DisplayBackend::DisplayBackend(QObject *parent)
    : QObject(parent)
{
    findBacklightPath();
    initPowerKeyMonitor();
}

DisplayBackend::~DisplayBackend()
{
    if (m_inputFd >= 0) {
        close(m_inputFd);
    }
}

int DisplayBackend::brightness() const
{
    return m_brightnessPercent;
}

bool DisplayBackend::isScreenOn() const
{
    return m_isScreenOn;
}

void DisplayBackend::setBrightness(int percent)
{
    if (percent < 0) {
        percent = 0;
    }

    if (percent > 100) {
        percent = 100;
    }

    const bool needWrite = (m_brightnessPercent != percent);
    m_brightnessPercent = percent;

    if (!m_backlightPath.isEmpty() && m_maxBrightness > 0) {
        if (!m_isScreenOn) {
            emit brightnessChanged();
            return;
        }

        int actualVal = static_cast<int>(static_cast<double>(percent) / 100.0 * m_maxBrightness);
        if (actualVal == 0 && percent > 0) {
            actualVal = 1;
        }

        if (!Backend::writeTextFile(m_backlightPath + "/brightness", QString::number(actualVal))) {
            qDebug() << "Failed to write to" << m_backlightPath + "/brightness";
        }
    }

    if (needWrite) {
        emit brightnessChanged();
    }
}

void DisplayBackend::onInputEvent()
{
    struct input_event ev;
    while (read(m_inputFd, &ev, sizeof(ev)) > 0) {
        if (ev.type != EV_KEY || ev.code != KEY_POWER) {
            continue;
        }

        if (ev.value == 1) {
            qDebug() << "Key Down: Timer Started";
            m_longPressTimer->start();
        } else if (ev.value == 0) {
            if (m_longPressTimer->isActive()) {
                m_longPressTimer->stop();
                qDebug() << "Short Press Detected. Toggling Screen...";
                toggleScreen();
            } else {
                qDebug() << "Release ignored (Long press already handled).";
            }
        }
    }
}

void DisplayBackend::initPowerKeyMonitor()
{
    const QString devPath = "/dev/input/event0";
    m_inputFd = open(devPath.toStdString().c_str(), O_RDONLY | O_NONBLOCK);

    if (m_inputFd < 0) {
        qWarning() << "Failed to open input device:" << devPath
                   << "Check permissions (sudo or udev)!";
        return;
    }

    m_longPressTimer = new QTimer(this);
    m_longPressTimer->setSingleShot(true);
    m_longPressTimer->setInterval(1500);

    connect(m_longPressTimer, &QTimer::timeout, this, []() {
        qDebug() << "Manual Long Press Detected (1.5s)! Exiting...";
        QCoreApplication::exit(42);
    });

    m_notifier = new QSocketNotifier(m_inputFd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &DisplayBackend::onInputEvent);

    qDebug() << "Listening for Power Key on" << devPath;
}

void DisplayBackend::toggleScreen()
{
    m_isScreenOn = !m_isScreenOn;

    if (m_backlightPath.isEmpty()) {
        return;
    }

    const QString blPowerPath = m_backlightPath + "/bl_power";

    if (m_isScreenOn) {
        qDebug() << "Screen ON";
        if (!Backend::writeTextFile(m_touchInhibitPath, "0")) {
            qDebug() << "Failed to write to" << m_touchInhibitPath;
        }

        if (!Backend::writeTextFile(blPowerPath, "0")) {
            qDebug() << "Failed to write to" << blPowerPath;
        }

        int actualVal = static_cast<int>(static_cast<double>(m_brightnessPercent) / 100.0 * m_maxBrightness);
        if (actualVal == 0) {
            actualVal = 1;
        }

        if (!Backend::writeTextFile(m_backlightPath + "/brightness", QString::number(actualVal))) {
            qDebug() << "Failed to write to" << m_backlightPath + "/brightness";
        }
    } else {
        qDebug() << "Screen OFF";
        if (!Backend::writeTextFile(blPowerPath, "1")) {
            qDebug() << "Failed to write to" << blPowerPath;
        }

        if (!Backend::writeTextFile(m_touchInhibitPath, "1")) {
            qDebug() << "Failed to write to" << m_touchInhibitPath;
        }
    }

    emit screenStateChanged();
}

void DisplayBackend::findBacklightPath()
{
    QDir dir("/sys/class/backlight/");
    const QStringList entries = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    if (entries.isEmpty()) {
        return;
    }

    m_backlightPath = dir.filePath(entries.first());
    m_maxBrightness = Backend::readTextFile(m_backlightPath + "/max_brightness").toInt();
    readBrightness();
}

void DisplayBackend::readBrightness()
{
    if (m_backlightPath.isEmpty() || m_maxBrightness <= 0) {
        return;
    }

    const int currentVal = Backend::readTextFile(m_backlightPath + "/brightness").toInt();
    const int percent = static_cast<int>(static_cast<double>(currentVal) / m_maxBrightness * 100.0);
    if (percent != m_brightnessPercent) {
        m_brightnessPercent = percent;
        emit brightnessChanged();
    }
}
