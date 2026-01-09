#ifndef SYSTEMMONITOR_H
#define SYSTEMMONITOR_H

#include <QObject>
#include <QTimer>
#include <QFile>
#include <QTextStream>
#include <QVariant>
#include <QDebug>

class SystemMonitor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double cpuTotal READ cpuTotal NOTIFY statsChanged)
    Q_PROPERTY(QVariantList cpuCores READ cpuCores NOTIFY statsChanged)
    Q_PROPERTY(double memPercent READ memPercent NOTIFY statsChanged)
    Q_PROPERTY(QString memDetail READ memDetail NOTIFY statsChanged)

public:
    explicit SystemMonitor(QObject *parent = nullptr) : QObject(parent) {
        // 初始化 cpu 数据容器
        m_prevTotal.resize(9); // 1个总计 + 8个核心
        m_prevIdle.resize(9);
        m_prevTotal.fill(0);
        m_prevIdle.fill(0);

        connect(&m_timer, &QTimer::timeout, this, &SystemMonitor::updateStats);
        m_timer.start(1000);
        updateStats();
    }

    double cpuTotal() const { return m_cpuTotal; }
    QVariantList cpuCores() const { return m_cpuCores; }
    double memPercent() const { return m_memPercent; }
    QString memDetail() const { return m_memDetail; }

signals:
    void statsChanged();

private slots:
    void updateStats() {
        readMemInfo();
        readCpuInfo();
        emit statsChanged();
    }

private:
    void readMemInfo() {
        QFile file("/proc/meminfo");
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return;

        QTextStream in(&file);
        long total = 0, available = 0;
        
        // 【哨兵模式】死循环读取，直到 readLine 返回 null
        while (true) {
            QString line = in.readLine();
            if (line.isNull()) break; // 哨兵：读到末尾
            
            // 简单的字符串包含判断，比 split 更快
            if (line.startsWith("MemTotal:")) 
                total = parseValue(line);
            else if (line.startsWith("MemAvailable:")) 
                available = parseValue(line);
        }
        
        if (total > 0) {
            long used = total - available;
            m_memPercent = (double)used / total; // 0.0 - 1.0
            m_memDetail = QString("%1 / %2 GB").arg(QString::number(used / 1024.0 / 1024.0, 'f', 1))
                                               .arg(QString::number(total / 1024.0 / 1024.0, 'f', 1));
        }
    }

    void readCpuInfo() {
        QFile file("/proc/stat");
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return;

        QTextStream in(&file);
        QVariantList coresList;
        int coreIndex = 0; // 0=Total, 1=Cpu0, 2=Cpu1...

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

                // 计算差值
                long diffTotal = total - m_prevTotal[coreIndex];
                long diffIdle = idle - m_prevIdle[coreIndex];
                
                double usage = 0.0;
                if (diffTotal > 0) {
                    usage = (double)(diffTotal - diffIdle) / diffTotal;
                }

                // 保存状态
                m_prevTotal[coreIndex] = total;
                m_prevIdle[coreIndex] = idle;

                if (coreIndex == 0) {
                    m_cpuTotal = usage;
                } else {
                    coresList.append(usage); // 添加单个核心数据
                }

                coreIndex++;
                if (coreIndex > 8) break; // 8核 CPU (Snapdragon 845) + Total
            }
        }
        m_cpuCores = coresList;
    }

    long parseValue(const QString &line) {
        // 提取行中的数字部分: "MemTotal:  7726568 kB" -> 7726568
        QString clean = line.simplified();
        QStringList parts = clean.split(' ');
        if (parts.size() >= 2) return parts[1].toLong();
        return 0;
    }

    QTimer m_timer;
    double m_cpuTotal = 0.0;
    QVariantList m_cpuCores;
    double m_memPercent = 0.0;
    QString m_memDetail = "";
    
    // 简单的历史状态记录
    QVector<long> m_prevTotal;
    QVector<long> m_prevIdle;
};

#endif