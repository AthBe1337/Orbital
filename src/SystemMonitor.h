#ifndef SYSTEMMONITOR_H
#define SYSTEMMONITOR_H

#include <QObject>
#include <QTimer>
#include <QFile>
#include <QTextStream>
#include <QVariant>
#include <QStorageInfo>
#include <QDirIterator>
#include <QThread>
#include <QDebug>
#include <QVariantList>

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
    // 网络历史
    Q_PROPERTY(QVariantList netRxHistory READ netRxHistory NOTIFY statsChanged)
    Q_PROPERTY(QVariantList netTxHistory READ netTxHistory NOTIFY statsChanged)
    // 实时网速字符串
    Q_PROPERTY(QString netRxSpeed READ netRxSpeed NOTIFY statsChanged)
    Q_PROPERTY(QString netTxSpeed READ netTxSpeed NOTIFY statsChanged)
    Q_PROPERTY(int brightness READ brightness WRITE setBrightness NOTIFY brightnessChanged)

public:
    explicit SystemMonitor(QObject *parent = nullptr) : QObject(parent) {
        int coreCount = QThread::idealThreadCount();
        if (coreCount < 1) coreCount = 1;
        
        m_prevTotal.resize(coreCount + 1);
        m_prevIdle.resize(coreCount + 1);
        m_prevTotal.fill(0);
        m_prevIdle.fill(0);

        for(int i=0; i<60; ++i) {
            m_cpuHistory.append(0.0);
            m_memHistory.append(0.0);
            m_netRxHistory.append(0.0);
            m_netTxHistory.append(0.0);
        }

        findBacklightPath();

        connect(&m_timer, &QTimer::timeout, this, &SystemMonitor::updateStats);
        m_timer.start(1000);
        QTimer::singleShot(0, this, &SystemMonitor::updateStats);
    }

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
    QVariantList cpuHistory() const { return m_cpuHistory; }
    QVariantList memHistory() const { return m_memHistory; }
    QVariantList netRxHistory() const { return m_netRxHistory; }
    QVariantList netTxHistory() const { return m_netTxHistory; }
    QString netRxSpeed() const { return m_netRxSpeed; }
    QString netTxSpeed() const { return m_netTxSpeed; }
    int brightness() const { return m_brightnessPercent; }

    void setBrightness(int percent) {
        if (percent < 0) percent = 0;
        if (percent > 100) percent = 100;
        
        if (m_brightnessPercent == percent) return;

        m_brightnessPercent = percent;
        
        if (!m_backlightPath.isEmpty() && m_maxBrightness > 0) {
            // 计算实际数值 (例如 max=255, 50% -> 127)
            int actualVal = (int)((double)percent / 100.0 * m_maxBrightness);
            // 写入系统文件
            writeSysFile(m_backlightPath + "/brightness", QString::number(actualVal));
        }

        emit brightnessChanged();
    }

signals:
    void statsChanged();
    void brightnessChanged();

private slots:
    void updateStats() {
        readMemInfo();
        readCpuInfo();
        readDiskInfo();
        readBatteryInfo();
        updateHistory(m_cpuHistory, m_cpuTotal * 100.0);
        updateHistory(m_memHistory, m_memPercent * 100.0);
        readNetworkInfo();
        // readBrightness();
        emit statsChanged();
    }

private:
    void updateHistory(QVariantList &list, double newValue) {
        if (list.size() >= 60) {
            list.removeFirst();
        }
        list.append(newValue);
    }

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
                if (coreIndex >= m_prevTotal.size()) break;

                QStringList parts = line.simplified().split(' ');
                if (parts.size() < 5) continue;

                long user = parts[1].toLong();
                long nice = parts[2].toLong();
                long system = parts[3].toLong();
                long idle = parts[4].toLong();
                long total = user + nice + system + idle;

                long diffTotal = total - m_prevTotal[coreIndex];
                long diffIdle = idle - m_prevIdle[coreIndex];
                
                double usage = 0.0;
                if (diffTotal > 0) {
                    usage = (double)(diffTotal - diffIdle) / diffTotal;
                }

                m_prevTotal[coreIndex] = total;
                m_prevIdle[coreIndex] = idle;

                if (coreIndex == 0) {
                    m_cpuTotal = usage;
                } else {
                    coresList.append(usage);
                }

                coreIndex++;
            } else {
                break;
            }
        }
        m_cpuCores = coresList;
    }

    void readDiskInfo() {
        QVariantList partitions;
        for (const QStorageInfo &storage : QStorageInfo::mountedVolumes()) {
            if (!storage.isValid() || !storage.isReady()) continue;
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
            part["device"] = storage.device();
            part["mount"] = storage.rootPath();
            part["type"] = fsType;
            part["size"] = formatSize(total);
            part["used"] = formatSize(used);
            part["percent"] = percent;
            partitions.append(part);
            if (storage.rootPath() == "/") {
                m_diskPercent = percent;
                m_diskRootUsage = formatSize(used) + " / " + formatSize(total);
            }
        }
        m_diskPartitions = partitions;
    }

    void readBatteryInfo() {
        static QString batteryPath;
        if (batteryPath.isEmpty()) {
            QDir dir("/sys/class/power_supply/");
            QStringList entries = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
            for (const QString &entry : entries) {
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
        long capacity = readSysFile(batteryPath + "/capacity").toLong();
        QString status = readSysFile(batteryPath + "/status").trimmed();
        long voltage_uv = readSysFile(batteryPath + "/voltage_now").toLong();
        long temp_deci = readSysFile(batteryPath + "/temp").toLong();
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
            details["Design Cap"] = QString::number(energy_design / 1000) + " Wh/Ah";
            details["Full Cap"] = QString::number(energy_full / 1000) + " Wh/Ah";
        } else {
            details["Health"] = "Unknown";
        }
        details["Path"] = batteryPath;
        m_batDetails = details;
    }

    // --- 网络监控逻辑 ---
    void readNetworkInfo() {
        QFile file("/proc/net/dev");
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return;

        QTextStream in(&file);
        // 跳过前两行表头
        in.readLine(); 
        in.readLine();

        unsigned long long totalRx = 0;
        unsigned long long totalTx = 0;

        while (!in.atEnd()) {
            QString line = in.readLine().simplified();
            QStringList parts = line.split(' ');
            if (parts.size() < 10) continue;

            QString iface = parts[0];
            // 【过滤逻辑】排除 lo, tun, bond 等非物理流量
            if (iface.startsWith("lo") || iface.startsWith("tun") || iface.startsWith("bond")) continue;

            // /proc/net/dev 格式: interface: rx_bytes ... tx_bytes ...
            // 注意: sometimes "eth0:" is one part, sometimes "eth0" ":" are separate. simplified() helps.
            // parts[0] is "wlan0:", parts[1] is rx_bytes.
            // But if space is missing "wlan0:123", we need careful parsing.
            // Qt split(' ') on simplified string handles "wlan0: 123" -> ["wlan0:", "123"]
            
            // 处理粘连情况 "wlan0:123" vs "wlan0: 123"
            QString name = parts[0];
            unsigned long long rx = 0;
            unsigned long long tx = 0;
            
            // 简单处理：如果 parts[1] 是数字，通常就是 rx_bytes
            // Tx bytes 通常在第 9 列 (索引8，如果没粘连)
            // 这是一个简化解析，对于标准 Linux 内核通常有效
            // 稳健解析：
            QStringList cleanParts;
            for (const QString &p : parts) {
                 // 有些行可能是 "wlan0:3434"，需要拆分
                 if (p.contains(":") && p.length() > 1) {
                     QStringList sub = p.split(":");
                     if (!sub[0].isEmpty()) cleanParts.append(sub[0] + ":");
                     if (sub.size() > 1 && !sub[1].isEmpty()) cleanParts.append(sub[1]);
                 } else {
                     cleanParts.append(p);
                 }
            }

            if (cleanParts.size() > 9) {
                rx = cleanParts[1].toULongLong();
                tx = cleanParts[9].toULongLong();
                totalRx += rx;
                totalTx += tx;
            }
        }

        // 计算瞬时速度 (Bytes per second)
        // 第一次运行时 prev 为 0，速度会巨大，忽略第一次
        if (m_prevTotalRx > 0) {
            unsigned long long diffRx = (totalRx >= m_prevTotalRx) ? (totalRx - m_prevTotalRx) : 0;
            unsigned long long diffTx = (totalTx >= m_prevTotalTx) ? (totalTx - m_prevTotalTx) : 0;

            // 转为 KB/s 存入历史图表
            double rxKB = diffRx / 1024.0;
            double txKB = diffTx / 1024.0;
            
            updateHistory(m_netRxHistory, rxKB);
            updateHistory(m_netTxHistory, txKB);

            // 格式化显示文本 (动态单位 B/s, KB/s, MB/s)
            m_netRxSpeed = formatSpeed(diffRx);
            m_netTxSpeed = formatSpeed(diffTx);
        }

        m_prevTotalRx = totalRx;
        m_prevTotalTx = totalTx;
    }

    QString formatSpeed(unsigned long long bytes) {
        if (bytes < 1024) return QString::number(bytes) + " B/s";
        if (bytes < 1024 * 1024) return QString::number(bytes / 1024.0, 'f', 1) + " KB/s";
        if (bytes < 1024 * 1024 * 1024) return QString::number(bytes / 1024.0 / 1024.0, 'f', 1) + " MB/s";
        return QString::number(bytes / 1024.0 / 1024.0 / 1024.0, 'f', 1) + " GB/s";
    }

    QString readSysFile(const QString &path) {
        QFile file(path);
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            return QString(file.readAll()).trimmed();
        }
        return "";
    }

    void writeSysFile(const QString &path, const QString &value) {
        QFile file(path);
        if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream out(&file);
            out << value;
        } else {
            qDebug() << "Failed to write to" << path;
        }
    }

    QString formatSize(qint64 bytes) {
        if (bytes < 1024) return QString::number(bytes) + " B";
        if (bytes < 1024 * 1024) return QString::number(bytes / 1024.0, 'f', 1) + " KB";
        if (bytes < 1024 * 1024 * 1024) return QString::number(bytes / 1024.0 / 1024.0, 'f', 1) + " MB";
        return QString::number(bytes / 1024.0 / 1024.0 / 1024.0, 'f', 1) + " GB";
    }

    void findBacklightPath() {
        QDir dir("/sys/class/backlight/");
        QStringList entries = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        if (!entries.isEmpty()) {
            // 通常使用第一个找到的设备
            m_backlightPath = dir.filePath(entries.first());
            
            // 读取最大亮度
            QString maxStr = readSysFile(m_backlightPath + "/max_brightness");
            m_maxBrightness = maxStr.toInt();
            
            // 读取当前亮度以初始化 UI
            readBrightness();
        }
    }

    void readBrightness() {
        if (m_backlightPath.isEmpty() || m_maxBrightness <= 0) return;
        
        QString curStr = readSysFile(m_backlightPath + "/brightness");
        int currentVal = curStr.toInt();
        
        int percent = (int)((double)currentVal / m_maxBrightness * 100.0);
        if (percent != m_brightnessPercent) {
            m_brightnessPercent = percent;
            emit brightnessChanged();
        }
    }

    QTimer m_timer;
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
    unsigned long long m_prevTotalRx = 0;
    unsigned long long m_prevTotalTx = 0;

    QVariantList m_cpuHistory;
    QVariantList m_memHistory;
    QVariantList m_netRxHistory;
    QVariantList m_netTxHistory;
    QString m_netRxSpeed = "0 B/s";
    QString m_netTxSpeed = "0 B/s";
    QString m_backlightPath;
    int m_maxBrightness = 0;
    int m_brightnessPercent = 50; // 默认值
};
#endif // SYSTEMMONITOR_H