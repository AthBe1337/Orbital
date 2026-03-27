#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

class QTimer;
class DisplayBackend;
class LedBackend;
class SystemDetailsBackend;
class SystemStatsBackend;
class WifiBackend;

class SystemMonitor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double cpuTotal READ cpuTotal NOTIFY statsChanged)
    Q_PROPERTY(QVariantList cpuCores READ cpuCores NOTIFY statsChanged)
    Q_PROPERTY(double memPercent READ memPercent NOTIFY statsChanged)
    Q_PROPERTY(QString memDetail READ memDetail NOTIFY statsChanged)
    Q_PROPERTY(double diskPercent READ diskPercent NOTIFY statsChanged)
    Q_PROPERTY(QString diskRootUsage READ diskRootUsage NOTIFY statsChanged)
    Q_PROPERTY(QVariantList diskPartitions READ diskPartitions NOTIFY statsChanged)
    Q_PROPERTY(int batPercent READ batPercent NOTIFY statsChanged)
    Q_PROPERTY(QString batState READ batState NOTIFY statsChanged)
    Q_PROPERTY(QVariantMap batDetails READ batDetails NOTIFY statsChanged)
    Q_PROPERTY(QVariantList cpuHistory READ cpuHistory NOTIFY statsChanged)
    Q_PROPERTY(QVariantList memHistory READ memHistory NOTIFY statsChanged)
    Q_PROPERTY(QVariantList netRxHistory READ netRxHistory NOTIFY statsChanged)
    Q_PROPERTY(QVariantList netTxHistory READ netTxHistory NOTIFY statsChanged)
    Q_PROPERTY(QString netRxSpeed READ netRxSpeed NOTIFY statsChanged)
    Q_PROPERTY(QString netTxSpeed READ netTxSpeed NOTIFY statsChanged)
    Q_PROPERTY(QString loadAverage READ loadAverage NOTIFY statsChanged)
    Q_PROPERTY(int brightness READ brightness WRITE setBrightness NOTIFY brightnessChanged)
    Q_PROPERTY(QVariantList netInterfaces READ netInterfaces NOTIFY statsChanged)
    Q_PROPERTY(bool isScreenOn READ isScreenOn NOTIFY screenStateChanged)
    Q_PROPERTY(QVariantList wifiList READ wifiList NOTIFY wifiListChanged)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled WRITE setWifiEnabled NOTIFY wifiEnabledChanged)
    Q_PROPERTY(QVariantMap currentWifiDetails READ currentWifiDetails NOTIFY currentWifiDetailsChanged)
    Q_PROPERTY(QString osVersion READ osVersion CONSTANT)
    Q_PROPERTY(QString kernelVersion READ kernelVersion CONSTANT)
    Q_PROPERTY(QObject* ledBackend READ ledBackend CONSTANT)
    Q_PROPERTY(QObject* systemDetailsBackend READ systemDetailsBackend CONSTANT)

public:
    explicit SystemMonitor(QObject *parent = nullptr);

    double cpuTotal() const;
    QVariantList cpuCores() const;
    double memPercent() const;
    QString memDetail() const;
    double diskPercent() const;
    QString diskRootUsage() const;
    QVariantList diskPartitions() const;
    int batPercent() const;
    QString batState() const;
    QVariantMap batDetails() const;
    QVariantList cpuHistory() const;
    QVariantList memHistory() const;
    QVariantList netRxHistory() const;
    QVariantList netTxHistory() const;
    QString netRxSpeed() const;
    QString netTxSpeed() const;
    QString loadAverage() const;
    int brightness() const;
    QVariantList netInterfaces() const;
    bool isScreenOn() const;
    QVariantList wifiList() const;
    bool wifiEnabled() const;
    QVariantMap currentWifiDetails() const;
    QString osVersion() const;
    QString kernelVersion() const;
    QObject *ledBackend() const;
    QObject *systemDetailsBackend() const;

    void setWifiEnabled(bool enable);
    void setBrightness(int percent);

    Q_INVOKABLE void connectToWifi(const QString &ssid, const QString &password);
    Q_INVOKABLE void disconnectFromWifi(const QString &ssid);
    Q_INVOKABLE void forgetNetwork(const QString &ssid);
    Q_INVOKABLE void setAutoConnect(const QString &ssid, bool autoConnect);
    Q_INVOKABLE void scanWifiNetworks();
    Q_INVOKABLE QString nextScreenshotPath() const;
    Q_INVOKABLE void systemCmd(const QString &cmd);

signals:
    void statsChanged();
    void brightnessChanged();
    void screenStateChanged();
    void wifiListChanged();
    void wifiEnabledChanged();
    void currentWifiDetailsChanged();
    void wifiOperationResult(QString operation, bool success, QString message);
    void volumeKeyEvent(QString key, int value);
    void screenshotRequested();

private slots:
    void refreshStats();

private:
    SystemStatsBackend *m_statsBackend = nullptr;
    DisplayBackend *m_displayBackend = nullptr;
    LedBackend *m_ledBackend = nullptr;
    SystemDetailsBackend *m_systemDetailsBackend = nullptr;
    WifiBackend *m_wifiBackend = nullptr;
    QTimer *m_timer = nullptr;
};
