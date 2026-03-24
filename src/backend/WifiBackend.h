#pragma once

#include <QObject>
#include <QSet>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class QTimer;

class WifiBackend : public QObject
{
    Q_OBJECT

public:
    explicit WifiBackend(QObject *parent = nullptr);

    QVariantList wifiList() const;
    bool wifiEnabled() const;
    QVariantMap currentWifiDetails() const;
    void setNetworkInterfaces(const QVariantList &interfaces);

public slots:
    void setWifiEnabled(bool enable);
    void connectToWifi(const QString &ssid, const QString &password);
    void disconnectFromWifi(const QString &ssid);
    void forgetNetwork(const QString &ssid);
    void setAutoConnect(const QString &ssid, bool autoConnect);
    void scanWifiNetworks();

signals:
    void wifiListChanged();
    void wifiEnabledChanged();
    void currentWifiDetailsChanged();
    void wifiOperationResult(QString operation, bool success, QString message);

private:
    void parseWifiOutput(const QString &output);
    void initWifiEnabled();
    void fetchSavedWifiList();

    QVariantList m_wifiList;
    bool m_wifiEnabled = true;
    QTimer *m_wifiTimer = nullptr;
    QStringList m_savedSsids;
    QSet<QString> m_savedAutoConnect;
    QVariantMap m_currentWifiDetails;
    QVariantList m_netInterfaces;
};
