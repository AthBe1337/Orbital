#pragma once

#include <QObject>
#include <QString>

class QSocketNotifier;
class QTimer;

class DisplayBackend : public QObject
{
    Q_OBJECT

public:
    explicit DisplayBackend(QObject *parent = nullptr);
    ~DisplayBackend() override;

    int brightness() const;
    bool isScreenOn() const;

public slots:
    void setBrightness(int percent);

signals:
    void brightnessChanged();
    void screenStateChanged();

private slots:
    void onInputEvent();

private:
    void initPowerKeyMonitor();
    void toggleScreen();
    void findBacklightPath();
    void readBrightness();

    QString m_backlightPath;
    int m_maxBrightness = 0;
    int m_brightnessPercent = 50;

    int m_inputFd = -1;
    QSocketNotifier *m_notifier = nullptr;
    bool m_isScreenOn = true;
    QTimer *m_longPressTimer = nullptr;
    const QString m_touchInhibitPath =
        "/sys/devices/platform/soc@0/ac0000.geniqup/a90000.i2c/i2c-12/12-0020/rmi4-00/input/input5/inhibited";
};
