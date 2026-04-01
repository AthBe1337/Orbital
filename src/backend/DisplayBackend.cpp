#include "DisplayBackend.h"

#include "SystemHelpers.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QDir>
#include <QDebug>
#include <QSocketNotifier>
#include <QTimer>

#include <fcntl.h>
#include <linux/input.h>
#include <unistd.h>

namespace {

constexpr auto kDefaultPowerKeyPath = "/dev/input/event0";
constexpr auto kDefaultTouchInhibitPath =
    "/sys/devices/platform/soc@0/ac0000.geniqup/a90000.i2c/i2c-12/12-0020/rmi4-00/input/input5/inhibited";

QString environmentOrFallback(const char *name, const QString &fallback)
{
    const QByteArray value = qgetenv(name).trimmed();
    if (value.isEmpty()) {
        return fallback;
    }

    return QString::fromLocal8Bit(value);
}

QString volumeKeyName(unsigned short keyCode)
{
    switch (keyCode) {
    case KEY_VOLUMEUP:
        return QStringLiteral("up");
    case KEY_VOLUMEDOWN:
        return QStringLiteral("down");
    default:
        return QStringLiteral("unknown");
    }
}

} // namespace

DisplayBackend::DisplayBackend(QObject *parent)
    : QObject(parent)
{
    m_touchInhibitPath = environmentOrFallback("ORBITAL_TOUCH_INHIBIT_PATH",
                                               QString::fromLatin1(kDefaultTouchInhibitPath));
    m_powerKeyPath = environmentOrFallback("ORBITAL_POWER_KEY_PATH",
                                           QString::fromLatin1(kDefaultPowerKeyPath));
    m_volumeKeyPath = environmentOrFallback("ORBITAL_VOLUME_KEY_PATH", m_powerKeyPath);

    findBacklightPath();
    initPowerKeyMonitor();
    initVolumeKeyMonitor();
}

DisplayBackend::~DisplayBackend()
{
    if (m_powerInputFd >= 0) {
        close(m_powerInputFd);
    }

    if (m_volumeInputFd >= 0) {
        close(m_volumeInputFd);
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

void DisplayBackend::onPowerInputEvent()
{
    struct input_event ev;
    while (read(m_powerInputFd, &ev, sizeof(ev)) > 0) {
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
    m_powerInputFd = open(m_powerKeyPath.toStdString().c_str(), O_RDONLY | O_NONBLOCK);

    if (m_powerInputFd < 0) {
        qWarning() << "Failed to open power key input device:" << m_powerKeyPath
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

    m_powerNotifier = new QSocketNotifier(m_powerInputFd, QSocketNotifier::Read, this);
    connect(m_powerNotifier, &QSocketNotifier::activated, this, &DisplayBackend::onPowerInputEvent);

    qDebug() << "Listening for Power Key on" << m_powerKeyPath;
}

void DisplayBackend::onVolumeInputEvent()
{
    struct input_event ev;
    while (read(m_volumeInputFd, &ev, sizeof(ev)) > 0) {
        if (ev.type != EV_KEY) {
            continue;
        }

        if (ev.code != KEY_VOLUMEUP && ev.code != KEY_VOLUMEDOWN) {
            continue;
        }

        const QString key = volumeKeyName(ev.code);
        qDebug() << "Volume key event:" << key << "value:" << ev.value;
        emit volumeKeyEvent(key, ev.value);

        if (ev.value == 2) {
            continue;
        }

        if (ev.code == KEY_VOLUMEUP) {
            m_volumeUpPressed = (ev.value == 1);
        } else if (ev.code == KEY_VOLUMEDOWN) {
            m_volumeDownPressed = (ev.value == 1);
        }

        if (ev.value == 1 && m_volumeUpPressed && m_volumeDownPressed
            && !m_screenshotComboTriggered && m_isScreenOn) {
            m_screenshotComboTriggered = true;
            qDebug() << "Volume combo detected. Requesting screenshot.";
            emit screenshotRequested();
        }

        if (!m_volumeUpPressed && !m_volumeDownPressed) {
            m_screenshotComboTriggered = false;
        }
    }
}

void DisplayBackend::initVolumeKeyMonitor()
{
    m_volumeInputFd = open(m_volumeKeyPath.toStdString().c_str(), O_RDONLY | O_NONBLOCK);

    if (m_volumeInputFd < 0) {
        qWarning() << "Failed to open volume key input device:" << m_volumeKeyPath
                   << "Check permissions (sudo or udev)!";
        return;
    }

    m_volumeNotifier = new QSocketNotifier(m_volumeInputFd, QSocketNotifier::Read, this);
    connect(m_volumeNotifier, &QSocketNotifier::activated, this, &DisplayBackend::onVolumeInputEvent);

    qDebug() << "Listening for Volume Keys on" << m_volumeKeyPath;
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
