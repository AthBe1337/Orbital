#pragma once

#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>

#include <xf86drm.h>
#include <xf86drmMode.h>

class QSocketNotifier;
class QTimer;

class DisplayBackend : public QObject
{
    Q_OBJECT
    // Auto screen-off idle timeout in seconds. 0 = never (power key only).
    // Persisted via QSettings (display/screenOffTimeoutSec); default 120.
    Q_PROPERTY(int screenOffTimeoutSec READ screenOffTimeoutSec WRITE setScreenOffTimeoutSec NOTIFY screenOffTimeoutChanged)

public:
    explicit DisplayBackend(QObject *parent = nullptr);
    ~DisplayBackend() override;

    int brightness() const;
    bool isScreenOn() const;
    QString screenOffMethod() const;
    void setScreenOffMethod(const QString &method);
    int screenOffTimeoutSec() const;
    void setScreenOffTimeoutSec(int seconds);

public slots:
    void setBrightness(int percent);
    // Reset the idle countdown (any user activity should call this).
    void poke();

signals:
    void brightnessChanged();
    void screenStateChanged();
    void screenOffMethodChanged();
    void screenOffTimeoutChanged();
    void volumeKeyEvent(QString key, int value);
    void screenshotRequested();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private slots:
    void onPowerInputEvent(int fd);
    void onVolumeInputEvent(int fd);
    void onIdleTimeout();

private:
    void initPowerKeyMonitor();
    void initVolumeKeyMonitor();
    void toggleScreen();
    void wakeScreen();
    void scheduleIdleTimer();
    // Show/hide all Qt windows to fully stop/restart the render loop
    // when the screen is off/on (saves GPU + vsync wakeups).
    void setWindowsVisible(bool visible);
    void findBacklightPath();
    void readBrightness();
    void initDrmPanel();
    void tryOpenDrmDevice(const QString &drmDev);
    int findDrmMasterFd(const QString &drmDevPath);
    void setDpms(int mode);

    QString m_backlightPath;
    QString m_touchInhibitPath;
    QStringList m_powerKeyPaths;
    QStringList m_volumeKeyPaths;
    int m_maxBrightness = 0;
    int m_brightnessPercent = 50;

    QList<int> m_powerInputFds;
    QList<int> m_volumeInputFds;
    QList<QSocketNotifier *> m_powerNotifiers;
    QList<QSocketNotifier *> m_volumeNotifiers;
    bool m_isScreenOn = true;
    QTimer *m_longPressTimer = nullptr;
    QTimer *m_idleTimer = nullptr;
    int m_screenOffTimeoutSec = 120;
    bool m_volumeUpPressed = false;
    bool m_volumeDownPressed = false;
    bool m_screenshotComboTriggered = false;

    int m_drmFd = -1;
    int m_drmMasterFd = -1;
    uint32_t m_drmConnectorId = 0;
    uint32_t m_drmDpmsPropId = 0;

    QString m_screenOffMethod;
};
