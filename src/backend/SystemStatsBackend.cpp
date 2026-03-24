#include "SystemStatsBackend.h"

#include "SystemHelpers.h"

#include <QDir>
#include <QFile>
#include <QNetworkAddressEntry>
#include <QNetworkInterface>
#include <QStorageInfo>
#include <QTextStream>
#include <QThread>

SystemStatsBackend::SystemStatsBackend(QObject *parent)
    : QObject(parent)
{
    int coreCount = QThread::idealThreadCount();
    if (coreCount < 1) {
        coreCount = 1;
    }

    m_prevTotal.resize(coreCount + 1);
    m_prevIdle.resize(coreCount + 1);
    m_prevTotal.fill(0);
    m_prevIdle.fill(0);

    for (int i = 0; i < 60; ++i) {
        m_cpuHistory.append(0.0);
        m_memHistory.append(0.0);
        m_netRxHistory.append(0.0);
        m_netTxHistory.append(0.0);
    }
}

void SystemStatsBackend::update()
{
    readMemInfo();
    readCpuInfo();
    readDiskInfo();
    readBatteryInfo();
    appendHistory(m_cpuHistory, m_cpuTotal * 100.0);
    appendHistory(m_memHistory, m_memPercent * 100.0);
    readNetworkInfo();
    readNetworkInterfaceDetails();
    emit statsUpdated();
}

double SystemStatsBackend::cpuTotal() const
{
    return m_cpuTotal;
}

QVariantList SystemStatsBackend::cpuCores() const
{
    return m_cpuCores;
}

double SystemStatsBackend::memPercent() const
{
    return m_memPercent;
}

QString SystemStatsBackend::memDetail() const
{
    return m_memDetail;
}

double SystemStatsBackend::diskPercent() const
{
    return m_diskPercent;
}

QString SystemStatsBackend::diskRootUsage() const
{
    return m_diskRootUsage;
}

QVariantList SystemStatsBackend::diskPartitions() const
{
    return m_diskPartitions;
}

int SystemStatsBackend::batPercent() const
{
    return m_batPercent;
}

QString SystemStatsBackend::batState() const
{
    return m_batState;
}

QVariantMap SystemStatsBackend::batDetails() const
{
    return m_batDetails;
}

QVariantList SystemStatsBackend::cpuHistory() const
{
    return m_cpuHistory;
}

QVariantList SystemStatsBackend::memHistory() const
{
    return m_memHistory;
}

QVariantList SystemStatsBackend::netRxHistory() const
{
    return m_netRxHistory;
}

QVariantList SystemStatsBackend::netTxHistory() const
{
    return m_netTxHistory;
}

QString SystemStatsBackend::netRxSpeed() const
{
    return m_netRxSpeed;
}

QString SystemStatsBackend::netTxSpeed() const
{
    return m_netTxSpeed;
}

QVariantList SystemStatsBackend::netInterfaces() const
{
    return m_netInterfaces;
}

void SystemStatsBackend::appendHistory(QVariantList &list, double newValue)
{
    if (list.size() >= 60) {
        list.removeFirst();
    }

    list.append(newValue);
}

void SystemStatsBackend::readMemInfo()
{
    QFile file("/proc/meminfo");
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return;
    }

    QTextStream in(&file);
    long total = 0;
    long available = 0;

    while (true) {
        const QString line = in.readLine();
        if (line.isNull()) {
            break;
        }

        if (line.startsWith("MemTotal:")) {
            total = parseMemValue(line);
        } else if (line.startsWith("MemAvailable:")) {
            available = parseMemValue(line);
        }
    }

    if (total > 0) {
        const long used = total - available;
        m_memPercent = static_cast<double>(used) / total;
        m_memDetail = QString("%1 / %2 GB")
                          .arg(QString::number(used / 1024.0 / 1024.0, 'f', 1))
                          .arg(QString::number(total / 1024.0 / 1024.0, 'f', 1));
    }
}

long SystemStatsBackend::parseMemValue(const QString &line) const
{
    const QStringList parts = line.simplified().split(' ');
    if (parts.size() >= 2) {
        return parts[1].toLong();
    }

    return 0;
}

void SystemStatsBackend::readCpuInfo()
{
    QFile file("/proc/stat");
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return;
    }

    QTextStream in(&file);
    QVariantList coresList;
    int coreIndex = 0;

    while (true) {
        const QString line = in.readLine();
        if (line.isNull()) {
            break;
        }

        if (!line.startsWith("cpu")) {
            break;
        }

        if (coreIndex >= m_prevTotal.size()) {
            break;
        }

        const QStringList parts = line.simplified().split(' ');
        if (parts.size() < 5) {
            continue;
        }

        const long user = parts[1].toLong();
        const long nice = parts[2].toLong();
        const long system = parts[3].toLong();
        const long idle = parts[4].toLong();
        const long total = user + nice + system + idle;

        const long diffTotal = total - m_prevTotal[coreIndex];
        const long diffIdle = idle - m_prevIdle[coreIndex];

        double usage = 0.0;
        if (diffTotal > 0) {
            usage = static_cast<double>(diffTotal - diffIdle) / diffTotal;
        }

        m_prevTotal[coreIndex] = total;
        m_prevIdle[coreIndex] = idle;

        if (coreIndex == 0) {
            m_cpuTotal = usage;
        } else {
            coresList.append(usage);
        }

        ++coreIndex;
    }

    m_cpuCores = coresList;
}

void SystemStatsBackend::readDiskInfo()
{
    QVariantList partitions;

    for (const QStorageInfo &storage : QStorageInfo::mountedVolumes()) {
        if (!storage.isValid() || !storage.isReady()) {
            continue;
        }

        const QString fsType = QString::fromUtf8(storage.fileSystemType());
        if (fsType.contains("tmpfs") || fsType.contains("proc") ||
            fsType.contains("sysfs") || fsType.contains("overlay") ||
            storage.bytesTotal() == 0) {
            continue;
        }

        const double total = storage.bytesTotal();
        const double avail = storage.bytesAvailable();
        const double used = total - avail;
        const double percent = total > 0 ? (used / total) : 0.0;

        QVariantMap part;
        part["device"] = QString::fromUtf8(storage.device());
        part["mount"] = storage.rootPath();
        part["type"] = fsType;
        part["size"] = Backend::formatSize(total);
        part["used"] = Backend::formatSize(used);
        part["percent"] = percent;
        partitions.append(part);

        if (storage.rootPath() == "/") {
            m_diskPercent = percent;
            m_diskRootUsage = Backend::formatSize(used) + " / " + Backend::formatSize(total);
        }
    }

    m_diskPartitions = partitions;
}

void SystemStatsBackend::readBatteryInfo()
{
    if (m_batteryPath.isEmpty()) {
        QDir dir("/sys/class/power_supply/");
        const QStringList entries = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &entry : entries) {
            const QString type = Backend::readTextFile(dir.filePath(entry) + "/type");
            if (type.trimmed() == "Battery") {
                m_batteryPath = dir.filePath(entry);
                break;
            }
        }
    }

    if (m_batteryPath.isEmpty()) {
        m_batState = "No Battery";
        return;
    }

    const long capacity = Backend::readTextFile(m_batteryPath + "/capacity").toLong();
    const QString status = Backend::readTextFile(m_batteryPath + "/status").trimmed();
    const long voltageUv = Backend::readTextFile(m_batteryPath + "/voltage_now").toLong();
    const long tempDeci = Backend::readTextFile(m_batteryPath + "/temp").toLong();
    long energyFull = Backend::readTextFile(m_batteryPath + "/energy_full").toLong();
    if (energyFull == 0) {
        energyFull = Backend::readTextFile(m_batteryPath + "/charge_full").toLong();
    }

    long energyDesign = Backend::readTextFile(m_batteryPath + "/energy_full_design").toLong();
    if (energyDesign == 0) {
        energyDesign = Backend::readTextFile(m_batteryPath + "/charge_full_design").toLong();
    }

    m_batPercent = capacity;
    m_batState = status;

    QVariantMap details;
    details["Voltage"] = QString::number(voltageUv / 1000000.0, 'f', 2) + " V";
    details["Temperature"] = QString::number(tempDeci / 10.0, 'f', 1) + " °C";

    if (energyDesign > 0) {
        const double health = static_cast<double>(energyFull) / energyDesign * 100.0;
        details["Health"] = QString::number(health, 'f', 1) + "%";
        details["Design Cap"] = QString::number(energyDesign / 1000) + " Wh/Ah";
        details["Full Cap"] = QString::number(energyFull / 1000) + " Wh/Ah";
    } else {
        details["Health"] = "Unknown";
    }

    details["Path"] = m_batteryPath;
    m_batDetails = details;
}

void SystemStatsBackend::readNetworkInfo()
{
    QFile file("/proc/net/dev");
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return;
    }

    QTextStream in(&file);
    in.readLine();
    in.readLine();

    quint64 totalRx = 0;
    quint64 totalTx = 0;

    while (!in.atEnd()) {
        const QString line = in.readLine().simplified();
        const QStringList parts = line.split(' ');
        if (parts.size() < 10) {
            continue;
        }

        const QString iface = parts[0];
        if (iface.startsWith("lo") || iface.startsWith("tun") || iface.startsWith("bond")) {
            continue;
        }

        QStringList cleanParts;
        for (const QString &part : parts) {
            if (part.contains(":") && part.length() > 1) {
                const QStringList splitParts = part.split(":");
                if (!splitParts[0].isEmpty()) {
                    cleanParts.append(splitParts[0] + ":");
                }

                if (splitParts.size() > 1 && !splitParts[1].isEmpty()) {
                    cleanParts.append(splitParts[1]);
                }
            } else {
                cleanParts.append(part);
            }
        }

        if (cleanParts.size() > 9) {
            totalRx += cleanParts[1].toULongLong();
            totalTx += cleanParts[9].toULongLong();
        }
    }

    if (m_prevTotalRx > 0) {
        const quint64 diffRx = totalRx >= m_prevTotalRx ? (totalRx - m_prevTotalRx) : 0;
        const quint64 diffTx = totalTx >= m_prevTotalTx ? (totalTx - m_prevTotalTx) : 0;

        appendHistory(m_netRxHistory, diffRx / 1024.0);
        appendHistory(m_netTxHistory, diffTx / 1024.0);

        m_netRxSpeed = Backend::formatSpeed(diffRx);
        m_netTxSpeed = Backend::formatSpeed(diffTx);
    }

    m_prevTotalRx = totalRx;
    m_prevTotalTx = totalTx;
}

void SystemStatsBackend::readNetworkInterfaceDetails()
{
    QVariantList list;
    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();

    for (const QNetworkInterface &interface : interfaces) {
        if (!interface.isValid()) {
            continue;
        }

        QVariantMap map;
        map["name"] = interface.name();
        map["mac"] = interface.hardwareAddress();

        const bool isUp = interface.flags().testFlag(QNetworkInterface::IsUp);
        const bool isRunning = interface.flags().testFlag(QNetworkInterface::IsRunning);
        map["state"] = (isUp && isRunning) ? "UP" : "DOWN";

        QStringList ipList;
        for (const QNetworkAddressEntry &entry : interface.addressEntries()) {
            ipList.append(entry.ip().toString());
        }

        map["ips"] = ipList;
        list.append(map);
    }

    m_netInterfaces = list;
}
