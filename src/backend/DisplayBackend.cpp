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

#include <cerrno>
#include <cstring>

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

QStringList parsePathList(const QString &combined)
{
    QStringList paths;
    for (const QString &p : combined.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
        const QString trimmed = p.trimmed();
        if (!trimmed.isEmpty() && !paths.contains(trimmed)) {
            paths.append(trimmed);
        }
    }
    return paths;
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
    const QString rawPower = environmentOrFallback("ORBITAL_POWER_KEY_PATH",
                                                   QString::fromLatin1(kDefaultPowerKeyPath));
    m_powerKeyPaths = parsePathList(rawPower);

    const QString rawVolume = environmentOrFallback("ORBITAL_VOLUME_KEY_PATH", rawPower);
    m_volumeKeyPaths = parsePathList(rawVolume);

    findBacklightPath();
    initDrmPanel();
    initPowerKeyMonitor();
    initVolumeKeyMonitor();
}

DisplayBackend::~DisplayBackend()
{
    for (int fd : m_powerInputFds) {
        if (fd >= 0) {
            close(fd);
        }
    }

    for (int fd : m_volumeInputFds) {
        if (fd >= 0) {
            close(fd);
        }
    }

    if (m_drmFd >= 0) {
        close(m_drmFd);
    }

    if (m_drmMasterFd >= 0) {
        close(m_drmMasterFd);
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

void DisplayBackend::onPowerInputEvent(int fd)
{
    struct input_event ev;
    while (read(fd, &ev, sizeof(ev)) > 0) {
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
    m_longPressTimer = new QTimer(this);
    m_longPressTimer->setSingleShot(true);
    m_longPressTimer->setInterval(1500);

    connect(m_longPressTimer, &QTimer::timeout, this, []() {
        qDebug() << "Manual Long Press Detected (1.5s)! Exiting...";
        QCoreApplication::exit(42);
    });

    for (const QString &path : m_powerKeyPaths) {
        const int fd = open(path.toStdString().c_str(), O_RDONLY | O_NONBLOCK);
        if (fd < 0) {
            qWarning() << "Failed to open power key input device:" << path
                       << "Check permissions (sudo or udev)!";
            continue;
        }

        auto *notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
        connect(notifier, &QSocketNotifier::activated, this, [this, fd]() {
            onPowerInputEvent(fd);
        });

        m_powerInputFds.append(fd);
        m_powerNotifiers.append(notifier);

        qDebug() << "Listening for Power Key on" << path;
    }
}

void DisplayBackend::onVolumeInputEvent(int fd)
{
    struct input_event ev;
    while (read(fd, &ev, sizeof(ev)) > 0) {
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
    for (const QString &path : m_volumeKeyPaths) {
        const int fd = open(path.toStdString().c_str(), O_RDONLY | O_NONBLOCK);
        if (fd < 0) {
            qWarning() << "Failed to open volume key input device:" << path
                       << "Check permissions (sudo or udev)!";
            continue;
        }

        auto *notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
        connect(notifier, &QSocketNotifier::activated, this, [this, fd]() {
            onVolumeInputEvent(fd);
        });

        m_volumeInputFds.append(fd);
        m_volumeNotifiers.append(notifier);

        qDebug() << "Listening for Volume Keys on" << path;
    }
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
        setDpms(DRM_MODE_DPMS_ON);

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

        if (!Backend::writeTextFile(m_touchInhibitPath, "0")) {
            qDebug() << "Failed to write to" << m_touchInhibitPath;
        }
    } else {
        qDebug() << "Screen OFF";
        if (!Backend::writeTextFile(blPowerPath, "1")) {
            qDebug() << "Failed to write to" << blPowerPath;
        }

        if (!Backend::writeTextFile(m_touchInhibitPath, "1")) {
            qDebug() << "Failed to write to" << m_touchInhibitPath;
        }

        setDpms(DRM_MODE_DPMS_OFF);
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

void DisplayBackend::initDrmPanel()
{
    const QByteArray envDev = qgetenv("ORBITAL_DRM_DEVICE").trimmed();
    if (!envDev.isEmpty()) {
        tryOpenDrmDevice(QString::fromLocal8Bit(envDev));
        return;
    }

    QDir driDir("/dev/dri");
    const QStringList cards = driDir.entryList({"card*"}, QDir::System);
    for (const QString &name : cards) {
        tryOpenDrmDevice(driDir.filePath(name));
        if (m_drmConnectorId != 0) {
            return;
        }
    }

    qDebug() << "No DPMS-capable DRM connector found on any card";
}

void DisplayBackend::tryOpenDrmDevice(const QString &drmDev)
{
    m_drmFd = open(drmDev.toStdString().c_str(), O_RDWR | O_NONBLOCK);
    if (m_drmFd < 0) {
        qDebug() << "Cannot open DRM device:" << drmDev << "-" << strerror(errno);
        return;
    }

    drmModeRes *res = drmModeGetResources(m_drmFd);
    if (!res) {
        qDebug() << "Cannot get DRM resources from" << drmDev;
        close(m_drmFd);
        m_drmFd = -1;
        return;
    }

    for (int i = 0; i < res->count_connectors; i++) {
        drmModeConnector *conn = drmModeGetConnector(m_drmFd, res->connectors[i]);
        if (!conn) {
            continue;
        }

        if (conn->connection != DRM_MODE_CONNECTED) {
            drmModeFreeConnector(conn);
            continue;
        }

        for (int j = 0; j < conn->count_props; j++) {
            drmModePropertyRes *prop = drmModeGetProperty(m_drmFd, conn->props[j]);
            if (!prop) {
                continue;
            }

            if (std::strcmp(prop->name, "DPMS") == 0) {
                m_drmConnectorId = conn->connector_id;
                m_drmDpmsPropId = prop->prop_id;
                drmModeFreeProperty(prop);
                drmModeFreeConnector(conn);
                drmModeFreeResources(res);

                m_drmMasterFd = findDrmMasterFd(drmDev);
                if (m_drmMasterFd >= 0) {
                    qDebug() << "DRM panel DPMS control ready on" << drmDev
                             << "connector" << m_drmConnectorId;
                } else {
                    qDebug() << "DRM connector found on" << drmDev
                             << "but no master fd - DPMS will fail";
                }
                return;
            }

            drmModeFreeProperty(prop);
        }

        drmModeFreeConnector(conn);
    }

    drmModeFreeResources(res);
    close(m_drmFd);
    m_drmFd = -1;
    m_drmConnectorId = 0;
    m_drmDpmsPropId = 0;
}

int DisplayBackend::findDrmMasterFd(const QString &drmDevPath)
{
    QDir fdDir("/proc/self/fd");
    const QStringList entries = fdDir.entryList(QDir::Files | QDir::NoDotAndDotDot);

    for (const QString &entry : entries) {
        const QString linkPath = fdDir.filePath(entry);
        char buf[256];
        const ssize_t len = readlink(linkPath.toStdString().c_str(), buf, sizeof(buf) - 1);
        if (len < 0) {
            continue;
        }
        buf[len] = '\0';

        if (drmDevPath == QString::fromLocal8Bit(buf)) {
            bool ok = false;
            const int fd = entry.toInt(&ok);
            if (ok && fd != m_drmFd) {
                const int dupFd = dup(fd);
                if (dupFd >= 0) {
                    qDebug() << "Found DRM master fd:" << fd << "(dup:" << dupFd << ")";
                    return dupFd;
                }
            }
        }
    }

    return -1;
}

void DisplayBackend::setDpms(int mode)
{
    const int fd = (m_drmMasterFd >= 0) ? m_drmMasterFd : m_drmFd;
    if (fd < 0 || m_drmConnectorId == 0 || m_drmDpmsPropId == 0) {
        return;
    }

    const int ret = drmModeConnectorSetProperty(fd, m_drmConnectorId,
                                                 m_drmDpmsPropId, mode);
    if (ret < 0) {
        qDebug() << "Failed to set DPMS to" << mode << "errno:" << errno;
    }
}
