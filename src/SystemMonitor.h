#ifndef SYSTEMMONITOR_H
#define SYSTEMMONITOR_H

#include <QObject>
#include <QTimer>
#include <QFile>
#include <QTextStream>
#include <QVariant>
#include <QStorageInfo>
#include <QDirIterator>
#include <QDebug>

class SystemMonitor : public QObject
{
    Q_OBJECT
    // CPU & Memory
    Q_PROPERTY(double cpuTotal READ cpuTotal NOTIFY statsChanged)
    Q_PROPERTY(QVariantList cpuCores READ cpuCores NOTIFY statsChanged)
    Q_PROPERTY(double memPercent READ memPercent NOTIFY statsChanged)
    Q_PROPERTY(QString memDetail READ memDetail NOTIFY statsChanged)
    
    // Disk
    Q_PROPERTY(double diskPercent READ diskPercent NOTIFY statsChanged)
    Q_PROPERTY(QString diskRootUsage READ diskRootUsage NOTIFY statsChanged)
    Q_PROPERTY(QVariantList diskPartitions READ diskPartitions NOTIFY statsChanged)

    // Battery
    Q_PROPERTY(int batPercent READ batPercent NOTIFY statsChanged)
    Q_PROPERTY(QString batState READ batState NOTIFY statsChanged) // Discharging, Charging...
    Q_PROPERTY(QVariantMap batDetails READ batDetails NOTIFY statsChanged) // Voltage, Temp, Health...

public:
    explicit SystemMonitor(QObject *parent = nullptr) : QObject(parent) {
        // 初始化 CPU 缓存
        m_prevTotal.resize(9); 
        m_prevIdle.resize(9);
        m_prevTotal.fill(0);
        m_prevIdle.fill(0);

        connect(&m_timer, &QTimer::timeout, this, &SystemMonitor::updateStats);
        m_timer.start(1000);
        // 先手动触发一次，避免启动时数据为空
        QTimer::singleShot(0, this, &SystemMonitor::updateStats);
    }

    // Getters
    double cpuTotal() const { return m_cpuTotal; }
    QVariantList cpuCores() const { return m_cpuCores; }
    double memPercent() const { return m_memPercent; }
    QString memDetail() const { return m_memDetail; }
    double diskPercent() const { return m_diskPercent; }
    QString diskRootUsage() const { return m_diskRootUsage; }
    QVariantList diskPartitions() const { return m_diskPartitions; }
    int batPercent() const { return m_batPercent; }
    QString batState() const { return m_batState; }
    QVariantMap batDetails() const { return m_batDetails; }

signals:
    void statsChanged();

private slots:
    void updateStats() {
        readMemInfo();
        readCpuInfo();
        readDiskInfo();
        readBatteryInfo();
        emit statsChanged();
    }

private:
    // --- CPU & Mem (保持之前的逻辑，略) ---
    void readMemInfo() {
        QFile file("/proc/meminfo");
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return;
        QTextStream in(&file);
        long total = 0, available = 0;
        while (true) {
            QString line = in.readLine();
            if (line.isNull()) break;
            if (line.startsWith("MemTotal:")) total = parseMemValue(line);
            else if (line.startsWith("MemAvailable:")) available = parseMemValue(line);
        }
        if (total > 0) {
            long used = total - available;
            m_memPercent = (double)used / total;
            m_memDetail = QString("%1 / %2 GB").arg(QString::number(used / 1024.0 / 1024.0, 'f', 1))
                                               .arg(QString::number(total / 1024.0 / 1024.0, 'f', 1));
        }
    }
    
    long parseMemValue(const QString &line) {
        QStringList parts = line.simplified().split(' ');
        if (parts.size() >= 2) return parts[1].toLong();
        return 0;
    }

    void readCpuInfo() {
         QFile file("/proc/stat");
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return;
        QTextStream in(&file);
        QVariantList coresList;
        int coreIndex = 0;
        while (true) {
            QString line = in.readLine();
            if (line.isNull()) break;
            if (line.startsWith("cpu")) {
                QStringList parts = line.simplified().split(' ');
                if (parts.size() < 5) continue;
                long user = parts[1].toLong();
                long nice = parts[2].toLong();
                long system = parts[3].toLong();
                long idle = parts[4].toLong();
                long total = user + nice + system + idle;
                long diffTotal = total - m_prevTotal[coreIndex];
                long diffIdle = idle - m_prevIdle[coreIndex];
                double usage = (diffTotal > 0) ? (double)(diffTotal - diffIdle) / diffTotal : 0.0;
                
                m_prevTotal[coreIndex] = total;
                m_prevIdle[coreIndex] = idle;
                if (coreIndex == 0) m_cpuTotal = usage;
                else coresList.append(usage);
                coreIndex++;
                if (coreIndex > 8) break;
            }
        }
        m_cpuCores = coresList;
    }

    // --- Disk Info ---
    void readDiskInfo() {
        QVariantList partitions;
        
        // 获取所有挂载点
        for (const QStorageInfo &storage : QStorageInfo::mountedVolumes()) {
            if (!storage.isValid() || !storage.isReady()) continue;
            
            // 过滤逻辑：只显示物理分区，过滤 tmpfs, proc, sys, overlay 等
            QString fsType = storage.fileSystemType();
            if (fsType.contains("tmpfs") || fsType.contains("proc") || 
                fsType.contains("sysfs") || fsType.contains("overlay") || 
                storage.bytesTotal() == 0) {
                continue;
            }

            double total = storage.bytesTotal();
            double avail = storage.bytesAvailable();
            double used = total - avail;
            double percent = (total > 0) ? (used / total) : 0.0;

            QVariantMap part;
            part["device"] = storage.device(); // e.g., /dev/sda1
            part["mount"] = storage.rootPath(); // e.g., /
            part["type"] = fsType;
            part["size"] = formatSize(total);
            part["used"] = formatSize(used);
            part["percent"] = percent;
            part["percentStr"] = QString::number(percent * 100, 'f', 0) + "%";
            
            partitions.append(part);

            // 专门记录根目录用于主页卡片显示
            if (storage.rootPath() == "/") {
                m_diskPercent = percent;
                m_diskRootUsage = formatSize(used) + " / " + formatSize(total);
            }
        }
        m_diskPartitions = partitions;
    }

    // --- Battery Info ---
    void readBatteryInfo() {
        // 自动寻找电池路径，通常是 BAT0 或 battery_xxx
        static QString batteryPath;
        if (batteryPath.isEmpty()) {
            QDir dir("/sys/class/power_supply/");
            QStringList entries = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
            for (const QString &entry : entries) {
                // 读取 type 文件确认是不是 Battery
                QString type = readSysFile(dir.filePath(entry) + "/type");
                if (type.trimmed() == "Battery") {
                    batteryPath = dir.filePath(entry);
                    break;
                }
            }
        }

        if (batteryPath.isEmpty()) {
            m_batState = "No Battery";
            return;
        }

        // 读取关键信息
        long capacity = readSysFile(batteryPath + "/capacity").toLong();
        QString status = readSysFile(batteryPath + "/status").trimmed();
        long voltage_uv = readSysFile(batteryPath + "/voltage_now").toLong();
        long temp_deci = readSysFile(batteryPath + "/temp").toLong(); // 0.1 度
        
        // 计算健康度 (Energy 或 Charge)
        long energy_full = readSysFile(batteryPath + "/energy_full").toLong();
        if (energy_full == 0) energy_full = readSysFile(batteryPath + "/charge_full").toLong();
        
        long energy_design = readSysFile(batteryPath + "/energy_full_design").toLong();
        if (energy_design == 0) energy_design = readSysFile(batteryPath + "/charge_full_design").toLong();

        m_batPercent = capacity;
        m_batState = status;

        QVariantMap details;
        details["Voltage"] = QString::number(voltage_uv / 1000000.0, 'f', 2) + " V";
        details["Temperature"] = QString::number(temp_deci / 10.0, 'f', 1) + " °C";
        
        if (energy_design > 0) {
            double health = (double)energy_full / energy_design * 100.0;
            details["Health"] = QString::number(health, 'f', 1) + "%";
            details["Design Cap"] = QString::number(energy_design / 1000) + " Wh/Ah"; // 单位稍微模糊一点，因为有些是uAh有些是uWh
            details["Full Cap"] = QString::number(energy_full / 1000) + " Wh/Ah";
        } else {
            details["Health"] = "Unknown";
        }
        details["Path"] = batteryPath; // Debug用

        m_batDetails = details;
    }

    // 辅助：读取 sysfs 单行文件
    QString readSysFile(const QString &path) {
        QFile file(path);
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            return QString(file.readAll()).trimmed();
        }
        return "";
    }

    // 辅助：格式化字节
    QString formatSize(qint64 bytes) {
        if (bytes < 1024) return QString::number(bytes) + " B";
        if (bytes < 1024 * 1024) return QString::number(bytes / 1024.0, 'f', 1) + " KB";
        if (bytes < 1024 * 1024 * 1024) return QString::number(bytes / 1024.0 / 1024.0, 'f', 1) + " MB";
        return QString::number(bytes / 1024.0 / 1024.0 / 1024.0, 'f', 1) + " GB";
    }

    QTimer m_timer;
    // Data Members
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
};
#endif