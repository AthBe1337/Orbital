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

#include <algorithm>

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
    // 当前连接的 WiFi 详细信息 (IP, MAC 等)
    Q_PROPERTY(QVariantMap currentWifiDetails READ currentWifiDetails NOTIFY currentWifiDetailsChanged)

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
        fetchSavedWifiList();
        initWifiEnabled(); // 立即更新状态
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
    QVariantMap currentWifiDetails() const { return m_currentWifiDetails; }

    // 控制 WiFi 开关
    void setWifiEnabled(bool enable) {
        if (m_wifiEnabled == enable) return;
        
        QProcess *proc = new QProcess(this);
        QString state = enable ? "on" : "off";
        
        connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                [this, proc, enable](int exitCode, QProcess::ExitStatus) {
            bool success = (exitCode == 0);
            if (success) {
                m_wifiEnabled = enable;
                if (enable) {
                    fetchSavedWifiList(); // 开启时更新一下已保存列表
                    scanWifiNetworks();
                    m_wifiTimer->start();
                } else {
                    m_wifiTimer->stop();
                    m_wifiList.clear();
                    m_currentWifiDetails.clear();
                    emit wifiListChanged();
                    emit currentWifiDetailsChanged();
                }
                emit wifiEnabledChanged();
            }
            
            QString errorMsg = success ? "" : proc->readAllStandardError();
            // 发送操作结果信号: 操作名, 成功否, 错误信息
            emit wifiOperationResult("toggle", success, errorMsg);
            
            proc->deleteLater();
        });

        proc->start("nmcli", QStringList() << "radio" << "wifi" << state);
    }

    // 连接 WiFi
    Q_INVOKABLE void connectToWifi(const QString &ssid, const QString &password) {
        if (!m_wifiEnabled) {
            emit wifiOperationResult("connect", false, "WiFi is disabled");
            return;
        }

        QProcess *proc = new QProcess(this);
        QStringList args;
        args << "dev" << "wifi" << "connect" << ssid;
        if (!password.isEmpty()) {
            args << "password" << password;
        }
        
        connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                [this, proc, ssid](int exitCode, QProcess::ExitStatus) {
            bool success = (exitCode == 0);
            QString output = proc->readAllStandardOutput();
            QString error = proc->readAllStandardError();
            
            if (success) {
                // 连接成功，立即更新已保存列表(因为新连接的会被系统保存)
                fetchSavedWifiList();
                scanWifiNetworks(); 
            }
            
            emit wifiOperationResult("connect", success, success ? output : error);
            proc->deleteLater();
        });
        
        proc->start("nmcli", args);
    }

    // 断开连接
    Q_INVOKABLE void disconnectFromWifi(const QString &ssid) {
        QProcess *proc = new QProcess(this);
        // 通常断开连接可以使用 connection down
        connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                [this, proc](int exitCode, QProcess::ExitStatus) {
            bool success = (exitCode == 0);
            if (success) scanWifiNetworks(); // 刷新状态
            emit wifiOperationResult("disconnect", success, proc->readAllStandardError());
            proc->deleteLater();
        });
        
        // 尝试关闭指定的连接 ID
        proc->start("nmcli", QStringList() << "connection" << "down" << "id" << ssid);
    }

    // 忘记/删除网络
    Q_INVOKABLE void forgetNetwork(const QString &ssid) {
        QProcess *proc = new QProcess(this);
        connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                [this, proc, ssid](int exitCode, QProcess::ExitStatus) {
            bool success = (exitCode == 0);
            if (success) {
                // 更新内部已保存列表
                m_savedSsids.removeAll(ssid); 
                scanWifiNetworks(); // 刷新前端显示
            }
            emit wifiOperationResult("forget", success, proc->readAllStandardError());
            proc->deleteLater();
        });
        
        proc->start("nmcli", QStringList() << "connection" << "delete" << "id" << ssid);
    }

    // 设置自动连接
    Q_INVOKABLE void setAutoConnect(const QString &ssid, bool autoConnect) {
        QProcess *proc = new QProcess(this);
        connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                [this, proc](int exitCode, QProcess::ExitStatus) {
             // 这里通常不需要给用户反馈，默默执行即可，或者 debug log
             if (exitCode != 0) qDebug() << "Failed to set auto-connect:" << proc->readAllStandardError();
             proc->deleteLater();
        });

        QString val = autoConnect ? "yes" : "no";
        proc->start("nmcli", QStringList() << "connection" << "modify" << "id" << ssid << "connection.autoconnect" << val);

        fetchSavedWifiList(); // 修改后立即更新已保存列表状态，确保前端显示正确的自动连接状态
    }

    // 扫描网络
    Q_INVOKABLE void scanWifiNetworks() {
        if (!m_wifiEnabled) return;
        
        // 每次扫描前，最好确保存储的列表是最新的（虽然不用太频繁，但为了一致性）
        // 这里的 fetchSavedWifiList 为了不阻塞，可以不做全量调用，或者放在解析前
        // 鉴于 nmcli connection show 很快，我们在 start 之前先同步调用一下，或者异步链式调用
        // 为了简单起见，我们假设 saved list 变化不频繁，只在 init 和 connect/forget 成功时更新
        
        QProcess *proc = new QProcess(this);
        QStringList args;
        // 字段: SSID, 数值信号强度, 安全性, 是否当前连接(*), 频道
        args << "-t" << "-f" << "SSID,SIGNAL,SECURITY,IN-USE,CHAN" << "dev" << "wifi" << "list";

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
    void currentWifiDetailsChanged();
    // 操作结果信号：operation (connect/disconnect/forget/toggle), success, message
    void wifiOperationResult(QString operation, bool success, QString message);

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
        readNetworkInterfaceDetails();
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
        QVariantList connectedList;
        QVariantList savedList;
        QVariantList otherList;
        QStringList lines = output.split('\n', Qt::SkipEmptyParts);
        QStringList seenSsids;

        auto strengthValue = [](const QVariant &item) {
            QVariantMap m = item.toMap();
            bool ok = false;
            int numeric = m.value("level").toInt(&ok);
            return ok ? numeric : 0;
        };

        for (const QString &line : lines) {
            int chanSep = line.lastIndexOf(':'); // CHAN separator
            if (chanSep == -1) continue;
            int inUseSep = line.lastIndexOf(':', chanSep - 1); // IN-USE separator
            if (inUseSep == -1) continue;
            QString inUseStr = line.mid(inUseSep + 1, chanSep - inUseSep - 1);

            int secSep = line.lastIndexOf(':', inUseSep - 1); // Security separator
            if (secSep == -1) continue;
            QString security = line.mid(secSep + 1, inUseSep - secSep - 1);

            int sigSep = line.lastIndexOf(':', secSep - 1); // SIGNAL separator
            if (sigSep == -1) continue;
            QString signal = line.mid(sigSep + 1, secSep - sigSep - 1);

            QString ssid = line.left(sigSep);

            // 简单去重 (nmcli 会显示同一 SSID 的多个频段)
            if (ssid.isEmpty() || seenSsids.contains(ssid)) continue;
            seenSsids.append(ssid);

            QVariantMap wifi;
            wifi["ssid"] = ssid;
            bool sigOk = false;
            int signalVal = signal.toInt(&sigOk);
            wifi["level"] = sigOk ? signalVal : 0; // 使用 SIGNAL 数值
            wifi["secured"] = !security.isEmpty();
            wifi["connected"] = (inUseStr == "*");

            QString formattedSecurity = security.split(' ', Qt::SkipEmptyParts).join(" / ");
            wifi["securityType"] = formattedSecurity;

            wifi["isSaved"] = m_savedSsids.contains(ssid);
            wifi["autoConnect"] = m_savedAutoConnect.contains(ssid);

            if (wifi["connected"].toBool()) {
                m_currentWifiDetails = wifi;
                for (const QVariant &v : m_netInterfaces) {
                    QVariantMap iface = v.toMap();
                    if (iface["name"].toString().startsWith("wlan") || iface["name"].toString().startsWith("wl")) {
                        m_currentWifiDetails["ip"] = iface["ips"].toList().value(0, "").toString();
                        m_currentWifiDetails["mac"] = iface["mac"].toString();
                        break;
                    }
                }
                emit currentWifiDetailsChanged();
                connectedList.append(wifi);
            } else if (wifi["isSaved"].toBool()) {
                savedList.append(wifi);
            } else {
                otherList.append(wifi);
            }
        }

        auto sortByStrengthDesc = [&strengthValue](QVariantList &list) {
            std::sort(list.begin(), list.end(), [&strengthValue](const QVariant &a, const QVariant &b) {
                return strengthValue(a) > strengthValue(b);
            });
        };

        sortByStrengthDesc(savedList);
        sortByStrengthDesc(otherList);

        QVariantList newList;
        newList.append(connectedList);
        newList.append(savedList);
        newList.append(otherList);

        m_wifiList = newList;
        emit wifiListChanged();
    }

    Q_INVOKABLE void initWifiEnabled() {
        QProcess proc;
        proc.start("nmcli", QStringList() << "radio" << "wifi");
        proc.waitForFinished();
        QString output = proc.readAllStandardOutput().trimmed();
        m_wifiEnabled = (output == "enabled");
    }

    void fetchSavedWifiList() {
        QProcess proc;
        // 列出类型为 wifi 的连接名称
        proc.start("nmcli", QStringList() << "-t" << "-f" << "NAME,TYPE,AUTOCONNECT" << "connection" << "show");
        proc.waitForFinished(1000); // 同步等待，最大1秒，避免阻塞太久
        
        if (proc.exitCode() == 0) {
            QString output = proc.readAllStandardOutput();
            QStringList lines = output.split('\n', Qt::SkipEmptyParts);
            
            m_savedSsids.clear();
            m_savedAutoConnect.clear();
            
            for (const QString &line : lines) {
                QStringList parts = line.split(':');
                if (parts.size() >= 3) {
                    QString name = parts[0];
                    QString type = parts[1];
                    QString autoConn = parts[2];
                    
                    if (type == "802-11-wireless") {
                        m_savedSsids.append(name);
                        if (autoConn == "yes") m_savedAutoConnect.insert(name);
                    }
                }
            }
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
    QStringList m_savedSsids; // 已保存的 SSID 列表
    QSet<QString> m_savedAutoConnect; // 记录哪些是自动连接的
    QVariantMap m_currentWifiDetails; // 当前连接详情
};
#endif // SYSTEMMONITOR_H