#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

class SystemStatsBackend : public QObject
{
    Q_OBJECT

public:
    explicit SystemStatsBackend(QObject *parent = nullptr);

    void update();

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
    QVariantList netInterfaces() const;

signals:
    void statsUpdated();

private:
    void appendHistory(QVariantList &list, double newValue);
    void readMemInfo();
    long parseMemValue(const QString &line) const;
    void readCpuInfo();
    void readDiskInfo();
    void readBatteryInfo();
    void readNetworkInfo();
    void readNetworkInterfaceDetails();

    double m_cpuTotal = 0;
    QVariantList m_cpuCores;
    double m_memPercent = 0;
    QString m_memDetail;
    double m_diskPercent = 0;
    QString m_diskRootUsage;
    QVariantList m_diskPartitions;
    int m_batPercent = 0;
    QString m_batState = "Unknown";
    QVariantMap m_batDetails;

    QVector<long> m_prevTotal;
    QVector<long> m_prevIdle;
    quint64 m_prevTotalRx = 0;
    quint64 m_prevTotalTx = 0;

    QVariantList m_cpuHistory;
    QVariantList m_memHistory;
    QVariantList m_netRxHistory;
    QVariantList m_netTxHistory;
    QString m_netRxSpeed = "0 B/s";
    QString m_netTxSpeed = "0 B/s";
    QVariantList m_netInterfaces;
    QString m_batteryPath;
};
