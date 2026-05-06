#pragma once

#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>

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
    void volumeKeyEvent(QString key, int value);
    void screenshotRequested();

private slots:
    void onPowerInputEvent(int fd);
    void onVolumeInputEvent(int fd);

private:
    void initPowerKeyMonitor();
    void initVolumeKeyMonitor();
    void toggleScreen();
    void findBacklightPath();
    void readBrightness();

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
    bool m_volumeUpPressed = false;
    bool m_volumeDownPressed = false;
    bool m_screenshotComboTriggered = false;
};
