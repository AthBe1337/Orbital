#pragma once

#include <QObject>
#include <QVariantList>
#include <QList>
#include <QString>
#include <QStringList>

class LedBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList leds READ leds NOTIFY stateChanged)
    Q_PROPERTY(bool hasLeds READ hasLeds NOTIFY stateChanged)
    Q_PROPERTY(bool supportsFlash READ supportsFlash NOTIFY stateChanged)
    Q_PROPERTY(int allLedBrightness READ allLedBrightness NOTIFY stateChanged)
    Q_PROPERTY(int allLedFlashBrightness READ allLedFlashBrightness NOTIFY stateChanged)
    Q_PROPERTY(int allLedFlashTimeoutMs READ allLedFlashTimeoutMs NOTIFY stateChanged)
    Q_PROPERTY(int maxLedFlashTimeoutMs READ maxLedFlashTimeoutMs NOTIFY stateChanged)
    Q_PROPERTY(QVariantList modeOptions READ modeOptions NOTIFY stateChanged)
    Q_PROPERTY(QString currentMode READ currentMode NOTIFY stateChanged)

public:
    explicit LedBackend(QObject *parent = nullptr);

    QVariantList leds() const;
    bool hasLeds() const;
    bool supportsFlash() const;
    int allLedBrightness() const;
    int allLedFlashBrightness() const;
    int allLedFlashTimeoutMs() const;
    int maxLedFlashTimeoutMs() const;
    QVariantList modeOptions() const;
    QString currentMode() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setAllLedBrightness(int percent);
    Q_INVOKABLE void setLedBrightness(const QString &name, int percent);
    Q_INVOKABLE void setAllLedFlashBrightness(int percent);
    Q_INVOKABLE void setAllLedFlashTimeoutMs(int milliseconds);
    Q_INVOKABLE void setMode(const QString &modeId);
    Q_INVOKABLE void flashAllLeds();
    Q_INVOKABLE void flashLed(const QString &name);

signals:
    void stateChanged();

private:
    struct LedInfo {
        QString name;
        QString displayName;
        QString path;
        int brightness = 0;
        int maxBrightness = 0;
        int flashBrightness = 0;
        int maxFlashBrightness = 0;
        int flashTimeoutUs = 0;
        int maxFlashTimeoutUs = 0;
        bool supportsFlash = false;
        QString activeTrigger;
        QStringList triggers;
    };

    QList<LedInfo> m_leds;

    LedInfo *findLed(const QString &name);
    void reload();
    bool writeTrigger(LedInfo &led, const QString &trigger);
    bool ensureManualMode(LedInfo &led);
    bool writeBrightness(LedInfo &led, int percent);
    bool writeFlashBrightness(LedInfo &led, int percent);
    bool writeFlashTimeoutMs(LedInfo &led, int milliseconds);
    bool writeFlashStrobe(LedInfo &led);
};
