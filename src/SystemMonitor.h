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
#include <QNetworkInterface>
#include <QSocketNotifier>
#include <QGuiApplication>
#include <QProcess>

#include <linux/input.h>
#include <fcntl.h>
#include <unistd.h>
#include <iostream>

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
    Q_PROPERTY(int brightness READ brightness WRITE setBrightness NOTIFY brightnessChanged)
    Q_PROPERTY(QVariantList netInterfaces READ netInterfaces NOTIFY statsChanged)
    
    Q_PROPERTY(bool isScreenOn READ isScreenOn NOTIFY screenStateChanged)

    // WiFi 列表属性
    Q_PROPERTY(QVariantList wifiList READ wifiList NOTIFY wifiListChanged)
    // WiFi 开关状态
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled WRITE setWifiEnabled NOTIFY wifiEnabledChanged)

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

        // 1. 先找到背光路径
        findBacklightPath();

        // 2. 初始化电源键监听
        initPowerKeyMonitor();

        m_wifiTimer = new QTimer(this);
        getWifiEnabled(); // 立即更新状态
        // 设置间隔 5000ms (5秒)
        m_wifiTimer->setInterval(5000); 
        connect(m_wifiTimer, &QTimer::timeout, this, &SystemMonitor::scanWifiNetworks);

        // 2. 程序启动立即扫描一次，并启动定时器
        if (m_wifiEnabled) {
            scanWifiNetworks();
            m_wifiTimer->start();
        }

        connect(&m_timer, &QTimer::timeout, this, &SystemMonitor::updateStats);
        m_timer.start(1000);
        QTimer::singleShot(0, this, &SystemMonitor::updateStats);
    }

    // --- Getters ---
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
    QVariantList netInterfaces() const { return m_netInterfaces; }
    bool isScreenOn() const { return m_isScreenOn; }
    QVariantList wifiList() const { return m_wifiList; }
    bool wifiEnabled() const { return m_wifiEnabled; }

    // 控制 WiFi 开关
    void setWifiEnabled(bool enable) {
        if (m_wifiEnabled == enable) return;
        m_wifiEnabled = enable;
        
        QProcess::startDetached("nmcli", QStringList() << "radio" << "wifi" << (enable ? "on" : "off"));
        
        if (enable) {
            scanWifiNetworks(); // 立即扫一次
            m_wifiTimer->start(); // 开启轮询
        } else {
            m_wifiTimer->stop(); // 关闭轮询
            m_wifiList.clear();
            emit wifiListChanged();
        }
        emit wifiEnabledChanged();
    }

    // 供 QML 调用：连接 WiFi
    Q_INVOKABLE void connectToWifi(const QString &ssid, const QString &password) {
        qDebug() << "Connecting to" << ssid;
        QProcess *proc = new QProcess(this);
        
        QStringList args;
        args << "dev" << "wifi" << "connect" << ssid;
        if (!password.isEmpty()) {
            args << "password" << password;
        }
        
        connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                [this, proc, ssid](int exitCode, QProcess::ExitStatus) {
            if (exitCode == 0) {
                qDebug() << "Connected to" << ssid;
                // 连接成功后刷新列表（获取新的 connected 状态）
                scanWifiNetworks(); 
            } else {
                qDebug() << "Failed to connect. Error:" << proc->readAllStandardError();
            }
            proc->deleteLater();
        });
        
        proc->start("nmcli", args);
    }

    // 供 QML 调用：扫描网络
    Q_INVOKABLE void scanWifiNetworks() {
        if (!m_wifiEnabled) return;

        QProcess *proc = new QProcess(this);
        // 使用 -t (terse) 模式，-f 指定字段: SSID, 信号强度(Bars), 安全性, 是否当前连接(*)
        // 命令: nmcli -t -f SSID,BARS,SECURITY,IN-USE dev wifi list
        QStringList args;
        args << "-t" << "-f" << "SSID,BARS,SECURITY,IN-USE" << "dev" << "wifi" << "list";

        connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                [this, proc](int exitCode, QProcess::ExitStatus) {
            if (exitCode == 0) {
                QString output = proc->readAllStandardOutput();
                parseWifiOutput(output);
            }
            proc->deleteLater();
        });
        
        proc->start("nmcli", args);
    }

    void setBrightness(int percent) {
        if (percent < 0) percent = 0;
        if (percent > 100) percent = 100;
        
        // 即使 percent 没变，如果屏幕刚被点亮，也需要重新写入硬件
        bool needWrite = (m_brightnessPercent != percent);
        m_brightnessPercent = percent;
        
        if (!m_backlightPath.isEmpty() && m_maxBrightness > 0) {
            // 确保屏幕是开启状态 (bl_power = 0)
            if (!m_isScreenOn) {
                // 如果在熄屏状态下调整亮度，是否要自动亮屏？通常不需要，除非用户明确操作。
                // 这里我们只更新变量，不写硬件，除非屏幕是亮的。
                emit brightnessChanged();
                return; 
            }

            int actualVal = (int)((double)percent / 100.0 * m_maxBrightness);
            // 某些驱动写入 0 会导致黑屏，设为 1 保证最低可见度
            if (actualVal == 0 && percent > 0) actualVal = 1;
            
            writeSysFile(m_backlightPath + "/brightness", QString::number(actualVal));
        }

        if (needWrite) emit brightnessChanged();
    }

    Q_INVOKABLE void systemCmd(const QString &cmd) {
        if (cmd == "reboot") QProcess::execute("reboot");
        if (cmd == "poweroff") QProcess::execute("poweroff");
    }

signals:
    void statsChanged();
    void brightnessChanged();
    void screenStateChanged();
    void wifiListChanged();
    void wifiEnabledChanged();

private slots:
    void updateStats() {
        readMemInfo();
        readCpuInfo();
        readDiskInfo();
        readBatteryInfo();
        updateHistory(m_cpuHistory, m_cpuTotal * 100.0);
        updateHistory(m_memHistory, m_memPercent * 100.0);
        readNetworkInfo();
        // 实时亮度更新通常不需要 polling，除非系统自动亮度在变
        // readBrightness(); 
        readNetworkInterfaceDetails();
        emit statsChanged();
    }

    // 处理输入事件
    void onInputEvent() {
        struct input_event ev;
        while (read(m_inputFd, &ev, sizeof(ev)) > 0) {
            if (ev.type == EV_KEY) {
                if (ev.code == KEY_POWER) { 
                    
                    if (ev.value == 1) { 
                        // [按下]
                        // 启动定时器，开始倒计时
                        qDebug() << "Key Down: Timer Started";
                        m_longPressTimer->start();
                    } 
                    else if (ev.value == 0) { 
                        // [抬起]
                        if (m_longPressTimer->isActive()) {
                            // 定时器还在跑，说明还没到 1.5秒 -> 【短按】
                            m_longPressTimer->stop();
                            qDebug() << "Short Press Detected. Toggling Screen...";
                            toggleScreen();
                        } else {
                            // 定时器已经停了（超时了），说明刚才已经触发过长按逻辑了
                            // 这里直接忽略抬起动作
                            qDebug() << "Release ignored (Long press already handled).";
                        }
                    }
                    // 完全忽略 ev.value == 2
                }
            }
        }
    }

private:
    void initPowerKeyMonitor() {
        QString devPath = "/dev/input/event0"; 
        
        m_inputFd = open(devPath.toStdString().c_str(), O_RDONLY | O_NONBLOCK);
        
        if (m_inputFd < 0) {
            qWarning() << "Failed to open input device:" << devPath << "Check permissions (sudo or udev)!";
            return;
        }

        m_longPressTimer = new QTimer(this);
        m_longPressTimer->setSingleShot(true);
        // 设置长按触发时间 (1.5秒)
        m_longPressTimer->setInterval(1500); 

        // 定时器超时 = 长按触发
        connect(m_longPressTimer, &QTimer::timeout, this, [this](){
            qDebug() << "Manual Long Press Detected (1.5s)! Exiting...";
            // 执行退出，外部脚本捕获 42 后重启
            qApp->exit(42);
        });

        // 使用 QSocketNotifier 监听，这样不会阻塞 UI 线程
        m_notifier = new QSocketNotifier(m_inputFd, QSocketNotifier::Read, this);
        connect(m_notifier, &QSocketNotifier::activated, this, &SystemMonitor::onInputEvent);
        
        qDebug() << "Listening for Power Key on" << devPath;
    }

    void toggleScreen() {
        m_isScreenOn = !m_isScreenOn;
        
        if (m_backlightPath.isEmpty()) return;

        // bl_power 文件: 0 = 开启, 1 = 关闭 (低功耗模式)
        // 这个文件通常和 brightness 在同一个目录下
        QString blPowerPath = m_backlightPath + "/bl_power";

        if (m_isScreenOn) {
            // --- 亮屏逻辑 ---
            qDebug() << "Screen ON";
            writeSysFile(TOUCH_INHIBIT_PATH, "0");
            // 1. 解除低功耗模式
            writeSysFile(blPowerPath, "0");
            
            // 2. 恢复亮度 (写入之前的亮度值)
            // 某些驱动在 bl_power=1 时会丢弃亮度值，所以唤醒时需要重写一遍
            int actualVal = (int)((double)m_brightnessPercent / 100.0 * m_maxBrightness);
            if (actualVal == 0) actualVal = 1; // 防止黑屏
            writeSysFile(m_backlightPath + "/brightness", QString::number(actualVal));
        } else {
            qDebug() << "Screen OFF";
            // 使用 bl_power 关闭是最彻底的，它会切断背光供电
            writeSysFile(blPowerPath, "1");

            writeSysFile(TOUCH_INHIBIT_PATH, "1");
            
            // 如果 bl_power 不起作用 (某些驱动不支持)，作为备选方案将亮度设为 0
            // writeSysFile(m_backlightPath + "/brightness", "0");
        }
        
        emit screenStateChanged();
    }

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

    void readNetworkInfo() {
        QFile file("/proc/net/dev");
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return;

        QTextStream in(&file);
        in.readLine(); 
        in.readLine();

        unsigned long long totalRx = 0;
        unsigned long long totalTx = 0;

        while (!in.atEnd()) {
            QString line = in.readLine().simplified();
            QStringList parts = line.split(' ');
            if (parts.size() < 10) continue;

            QString iface = parts[0];
            if (iface.startsWith("lo") || iface.startsWith("tun") || iface.startsWith("bond")) continue;

            QStringList cleanParts;
            for (const QString &p : parts) {
                 if (p.contains(":") && p.length() > 1) {
                     QStringList sub = p.split(":");
                     if (!sub[0].isEmpty()) cleanParts.append(sub[0] + ":");
                     if (sub.size() > 1 && !sub[1].isEmpty()) cleanParts.append(sub[1]);
                 } else {
                     cleanParts.append(p);
                 }
            }

            if (cleanParts.size() > 9) {
                totalRx += cleanParts[1].toULongLong();
                totalTx += cleanParts[9].toULongLong();
            }
        }

        if (m_prevTotalRx > 0) {
            unsigned long long diffRx = (totalRx >= m_prevTotalRx) ? (totalRx - m_prevTotalRx) : 0;
            unsigned long long diffTx = (totalTx >= m_prevTotalTx) ? (totalTx - m_prevTotalTx) : 0;

            double rxKB = diffRx / 1024.0;
            double txKB = diffTx / 1024.0;
            
            updateHistory(m_netRxHistory, rxKB);
            updateHistory(m_netTxHistory, txKB);

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

    void readNetworkInterfaceDetails() {
        QVariantList list;
        const auto interfaces = QNetworkInterface::allInterfaces();

        for (const QNetworkInterface &interface : interfaces) {
            if (!interface.isValid()) continue;

            QVariantMap map;
            map["name"] = interface.name();
            map["mac"] = interface.hardwareAddress();
            
            bool isUp = interface.flags().testFlag(QNetworkInterface::IsUp);
            bool isRunning = interface.flags().testFlag(QNetworkInterface::IsRunning);
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
            m_backlightPath = dir.filePath(entries.first());
            QString maxStr = readSysFile(m_backlightPath + "/max_brightness");
            m_maxBrightness = maxStr.toInt();
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

    // 解析 nmcli 输出
    void parseWifiOutput(const QString &output) {
        QVariantList newList;
        QStringList lines = output.split('\n', Qt::SkipEmptyParts);
        QStringList seenSsids;

        for (const QString &line : lines) {
            
            int lastSep = line.lastIndexOf(':'); // IN-USE separator
            if (lastSep == -1) continue;
            QString inUseStr = line.mid(lastSep + 1);
            
            int secSep = line.lastIndexOf(':', lastSep - 1); // Security separator
            if (secSep == -1) continue;
            QString security = line.mid(secSep + 1, lastSep - secSep - 1);
            
            int barSep = line.lastIndexOf(':', secSep - 1); // Bars separator
            if (barSep == -1) continue;
            QString bars = line.mid(barSep + 1, secSep - barSep - 1);
            
            QString ssid = line.left(barSep);
            
            // 简单去重 (nmcli 会显示同一 SSID 的多个频段)
            if (ssid.isEmpty() || seenSsids.contains(ssid)) continue;
            seenSsids.append(ssid);

            QVariantMap wifi;
            wifi["ssid"] = ssid;
            wifi["level"] = bars; // nmcli 直接给出的图形条
            wifi["secured"] = !security.isEmpty();
            wifi["connected"] = (inUseStr == "*");

            QString formattedSecurity = security.split(' ', Qt::SkipEmptyParts).join(" / ");
            wifi["securityType"] = formattedSecurity;
            
            // 把已连接的放在最前面
            if (wifi["connected"].toBool()) {
                newList.prepend(wifi);
            } else {
                newList.append(wifi);
            }
        }
        
        m_wifiList = newList;
        emit wifiListChanged();
    }

    Q_INVOKABLE void getWifiEnabled() {
        QProcess proc;
        proc.start("nmcli", QStringList() << "radio" << "wifi");
        proc.waitForFinished();
        QString output = proc.readAllStandardOutput().trimmed();
        m_wifiEnabled = (output == "enabled");
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
    QVariantList m_netInterfaces;
    
    QString m_backlightPath;
    int m_maxBrightness = 0;
    int m_brightnessPercent = 50;
    
    int m_inputFd = -1;
    QSocketNotifier *m_notifier = nullptr;
    bool m_isScreenOn = true;
    bool m_longPressTriggered = false;
    QTimer *m_longPressTimer = nullptr;

    const QString TOUCH_INHIBIT_PATH = "/sys/devices/platform/soc@0/ac0000.geniqup/a90000.i2c/i2c-12/12-0020/rmi4-00/input/input5/inhibited";

    QVariantList m_wifiList;
    bool m_wifiEnabled = true;

    QTimer *m_wifiTimer = nullptr;
};
#endif // SYSTEMMONITOR_H