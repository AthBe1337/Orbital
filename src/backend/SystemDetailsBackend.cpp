#include "SystemDetailsBackend.h"

#include "SystemHelpers.h"

#include <QDir>
#include <QFile>
#include <QNetworkAddressEntry>
#include <QNetworkInterface>
#include <QTextStream>
#include <QTimer>

#include <algorithm>
#include <cmath>

#include <unistd.h>

namespace {

constexpr int kRefreshIntervalMs = 2000;
constexpr int kTopProcessLimit = 10;

struct CpuFrequencySample
{
    int core = 0;
    bool online = true;
    double freqMHz = 0.0;
    QString displayFreq;
    QString color;
};

struct RankedProcess
{
    int pid = 0;
    QString name;
    double cpuPercent = 0.0;
    double memPercent = 0.0;
    qint64 rssBytes = 0;
};

struct ThermalSample
{
    QString key;
    QString name;
    double tempC = 0.0;
    QString color;
};

bool numericName(const QString &text)
{
    if (text.isEmpty()) {
        return false;
    }

    for (const QChar ch : text) {
        if (!ch.isDigit()) {
            return false;
        }
    }

    return true;
}

QString formatUptimeString(double seconds)
{
    const qint64 totalSeconds = static_cast<qint64>(std::max(0.0, seconds));
    const qint64 days = totalSeconds / 86400;
    const qint64 hours = (totalSeconds % 86400) / 3600;
    const qint64 minutes = (totalSeconds % 3600) / 60;

    QStringList parts;
    if (days > 0) {
        parts.append(QStringLiteral("%1d").arg(days));
    }

    if (hours > 0 || !parts.isEmpty()) {
        parts.append(QStringLiteral("%1h").arg(hours));
    }

    parts.append(QStringLiteral("%1m").arg(minutes));
    return parts.join(QLatin1Char(' '));
}

QString addressFamilyLabel(QAbstractSocket::NetworkLayerProtocol protocol)
{
    switch (protocol) {
    case QAbstractSocket::IPv4Protocol:
        return QStringLiteral("IPv4");
    case QAbstractSocket::IPv6Protocol:
        return QStringLiteral("IPv6");
    default:
        return QStringLiteral("IP");
    }
}

QString cpuFrequencyColor(double ratio, bool online)
{
    if (!online) {
        return QStringLiteral("#666666");
    }

    if (ratio >= 0.85) {
        return QStringLiteral("#FF7043");
    }

    if (ratio >= 0.55) {
        return QStringLiteral("#FFB020");
    }

    return QStringLiteral("#42A5F5");
}

QString thermalColorForName(const QString &name)
{
    const QString lower = name.toLower();
    if (lower.contains(QStringLiteral("cpu"))) {
        return QStringLiteral("#7FB59A");
    }

    if (lower.contains(QStringLiteral("gpu"))) {
        return QStringLiteral("#A893CC");
    }

    if (lower.contains(QStringLiteral("mem")) || lower.contains(QStringLiteral("ebi"))) {
        return QStringLiteral("#7FAACC");
    }

    if (lower.contains(QStringLiteral("wlan")) || lower.contains(QStringLiteral("modem"))
        || lower.contains(QStringLiteral("q6"))) {
        return QStringLiteral("#7FB7B5");
    }

    if (lower.contains(QStringLiteral("camera")) || lower.contains(QStringLiteral("video"))) {
        return QStringLiteral("#C7A784");
    }

    if (lower.contains(QStringLiteral("charger")) || lower.contains(QStringLiteral("battery"))
        || lower.contains(QStringLiteral("pm"))) {
        return QStringLiteral("#CBB07E");
    }

    return QStringLiteral("#B9A98E");
}

} // namespace

SystemDetailsBackend::SystemDetailsBackend(QObject *parent)
    : QObject(parent)
    , m_timer(new QTimer(this))
{
    m_timer->setInterval(kRefreshIntervalMs);
    connect(m_timer, &QTimer::timeout, this, &SystemDetailsBackend::refresh);

    const long pageSize = ::sysconf(_SC_PAGESIZE);
    if (pageSize > 0) {
        m_pageSizeBytes = pageSize;
    }
}

bool SystemDetailsBackend::active() const
{
    return m_active;
}

void SystemDetailsBackend::setActive(bool active)
{
    if (m_active == active) {
        return;
    }

    m_active = active;
    if (m_active) {
        resetSamplingState();
        refresh();
        m_timer->start();
        QTimer::singleShot(350, this, [this]() {
            if (m_active) {
                refresh();
            }
        });
    } else {
        m_timer->stop();
    }

    emit activeChanged();
}

QString SystemDetailsBackend::hostname() const
{
    return m_hostname;
}

QString SystemDetailsBackend::uptime() const
{
    return m_uptime;
}

QString SystemDetailsBackend::primaryIp() const
{
    return m_primaryIp;
}

QVariantList SystemDetailsBackend::ipAddresses() const
{
    return m_ipAddresses;
}

QVariantList SystemDetailsBackend::cpuFrequencies() const
{
    return m_cpuFrequencies;
}

QVariantList SystemDetailsBackend::topProcesses() const
{
    return m_topProcesses;
}

QVariantList SystemDetailsBackend::thermalSensors() const
{
    return m_thermalSensors;
}

int SystemDetailsBackend::topProcessLimit() const
{
    return kTopProcessLimit;
}

void SystemDetailsBackend::refreshNow()
{
    refresh();
}

void SystemDetailsBackend::refresh()
{
    readOverview();
    readCpuFrequencies();
    readTopProcesses();
    readThermalSensors();
    emit dataChanged();
}

void SystemDetailsBackend::resetSamplingState()
{
    m_prevProcessCpuTimes.clear();
    m_prevTotalCpuTime = 0;
    m_topProcesses.clear();
    m_thermalSensors.clear();
}

void SystemDetailsBackend::readOverview()
{
    QString nextHostname = Backend::readTextFile(QStringLiteral("/proc/sys/kernel/hostname"));
    if (nextHostname.isEmpty()) {
        nextHostname = QStringLiteral("Unknown");
    }
    m_hostname = nextHostname;

    const QString uptimeRaw = Backend::readTextFile(QStringLiteral("/proc/uptime"));
    const QStringList uptimeParts = uptimeRaw.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    if (!uptimeParts.isEmpty()) {
        m_uptime = formatUptimeString(uptimeParts.first().toDouble());
    } else {
        m_uptime = QStringLiteral("--");
    }

    QVariantList addresses;
    QString primaryAddress;
    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &interface : interfaces) {
        if (!interface.isValid() || !interface.flags().testFlag(QNetworkInterface::IsUp)
            || !interface.flags().testFlag(QNetworkInterface::IsRunning)
            || interface.flags().testFlag(QNetworkInterface::IsLoopBack)) {
            continue;
        }

        for (const QNetworkAddressEntry &entry : interface.addressEntries()) {
            const QHostAddress ip = entry.ip();
            if (ip.isNull() || ip.isLoopback() || ip.isMulticast()) {
                continue;
            }

            const auto protocol = ip.protocol();
            if (protocol != QAbstractSocket::IPv4Protocol && protocol != QAbstractSocket::IPv6Protocol) {
                continue;
            }

            const QString addressText = ip.toString();
            QVariantMap item;
            item[QStringLiteral("interface")] = interface.name();
            item[QStringLiteral("address")] = addressText;
            item[QStringLiteral("family")] = addressFamilyLabel(protocol);
            addresses.append(item);

            if (protocol == QAbstractSocket::IPv4Protocol && primaryAddress.isEmpty()) {
                primaryAddress = addressText;
            } else if (primaryAddress.isEmpty()) {
                primaryAddress = addressText;
            }
        }
    }

    m_ipAddresses = addresses;
    m_primaryIp = primaryAddress.isEmpty() ? QStringLiteral("--") : primaryAddress;
}

void SystemDetailsBackend::readCpuFrequencies()
{
    struct CpuEntry {
        int core = 0;
        CpuFrequencySample sample;
    };

    QVector<CpuEntry> entries;
    const QDir cpuDir(QStringLiteral("/sys/devices/system/cpu"));
    const QStringList cpuEntries = cpuDir.entryList(QStringList() << QStringLiteral("cpu[0-9]*"),
                                                    QDir::Dirs | QDir::NoDotAndDotDot,
                                                    QDir::Name);
    entries.reserve(cpuEntries.size());

    for (const QString &entryName : cpuEntries) {
        const QString coreText = entryName.mid(3);
        bool ok = false;
        const int core = coreText.toInt(&ok);
        if (!ok) {
            continue;
        }

        const QString cpuPath = cpuDir.filePath(entryName);
        const QString onlineText = Backend::readTextFile(cpuPath + QStringLiteral("/online"));
        const bool online = onlineText.isEmpty() || onlineText != QStringLiteral("0");

        qint64 currentKhz = Backend::readTextFile(cpuPath + QStringLiteral("/cpufreq/scaling_cur_freq")).toLongLong();
        if (currentKhz <= 0) {
            currentKhz = Backend::readTextFile(cpuPath + QStringLiteral("/cpufreq/cpuinfo_cur_freq")).toLongLong();
        }

        qint64 maxKhz = Backend::readTextFile(cpuPath + QStringLiteral("/cpufreq/scaling_max_freq")).toLongLong();
        if (maxKhz <= 0) {
            maxKhz = Backend::readTextFile(cpuPath + QStringLiteral("/cpufreq/cpuinfo_max_freq")).toLongLong();
        }

        CpuFrequencySample sample;
        sample.core = core;
        sample.online = online;
        sample.freqMHz = currentKhz > 0 ? currentKhz / 1000.0 : 0.0;
        sample.displayFreq = online
                                 ? (currentKhz > 0
                                        ? QStringLiteral("%1 MHz").arg(static_cast<int>(sample.freqMHz + 0.5))
                                        : QStringLiteral("--"))
                                 : QStringLiteral("Offline");
        const double ratio = (currentKhz > 0 && maxKhz > 0) ? (static_cast<double>(currentKhz) / maxKhz) : 0.0;
        sample.color = cpuFrequencyColor(ratio, online);
        entries.append({core, sample});
    }

    std::sort(entries.begin(), entries.end(), [](const CpuEntry &left, const CpuEntry &right) {
        return left.core < right.core;
    });

    QVariantList frequencies;
    for (const CpuEntry &entry : entries) {
        QVariantMap map;
        map[QStringLiteral("core")] = entry.sample.core;
        map[QStringLiteral("label")] = QStringLiteral("Core %1").arg(entry.sample.core);
        map[QStringLiteral("freqMHz")] = entry.sample.freqMHz;
        map[QStringLiteral("displayFreq")] = entry.sample.displayFreq;
        map[QStringLiteral("online")] = entry.sample.online;
        map[QStringLiteral("color")] = entry.sample.color;
        frequencies.append(map);
    }

    m_cpuFrequencies = frequencies;
}

void SystemDetailsBackend::readTopProcesses()
{
    if (m_totalMemoryKb <= 0) {
        m_totalMemoryKb = readTotalMemoryKb();
    }

    const quint64 totalCpuTime = readTotalCpuTime();
    const double totalCpuDiff = totalCpuTime >= m_prevTotalCpuTime
                                    ? static_cast<double>(totalCpuTime - m_prevTotalCpuTime)
                                    : 0.0;

    QVector<RankedProcess> ranked;
    QHash<int, quint64> processTimes;

    const QDir procDir(QStringLiteral("/proc"));
    const QStringList procEntries = procDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    ranked.reserve(procEntries.size());

    for (const QString &entryName : procEntries) {
        if (!numericName(entryName)) {
            continue;
        }

        ProcessSample sample;
        if (!readProcessSample(entryName, sample)) {
            continue;
        }

        processTimes.insert(sample.pid, sample.totalCpuTime);

        RankedProcess process;
        process.pid = sample.pid;
        process.name = sample.name;
        process.rssBytes = sample.rssBytes;
        process.memPercent = m_totalMemoryKb > 0
                                 ? (sample.rssBytes / 1024.0) * 100.0 / m_totalMemoryKb
                                 : 0.0;

        if (totalCpuDiff > 0.0) {
            const quint64 previousProcessTime = m_prevProcessCpuTimes.value(sample.pid, sample.totalCpuTime);
            const quint64 processDiff = sample.totalCpuTime >= previousProcessTime
                                            ? (sample.totalCpuTime - previousProcessTime)
                                            : 0;
            process.cpuPercent = static_cast<double>(processDiff) * 100.0 / totalCpuDiff;
        }

        ranked.append(process);
    }

    std::sort(ranked.begin(), ranked.end(), [](const RankedProcess &left, const RankedProcess &right) {
        if (std::abs(left.cpuPercent - right.cpuPercent) > 0.05) {
            return left.cpuPercent > right.cpuPercent;
        }

        if (left.rssBytes != right.rssBytes) {
            return left.rssBytes > right.rssBytes;
        }

        return left.pid < right.pid;
    });

    QVariantList topProcesses;
    const int count = std::min(kTopProcessLimit, static_cast<int>(ranked.size()));
    topProcesses.reserve(count);
    for (int index = 0; index < count; ++index) {
        const RankedProcess &process = ranked.at(index);
        QVariantMap map;
        map[QStringLiteral("pid")] = process.pid;
        map[QStringLiteral("name")] = process.name;
        map[QStringLiteral("cpuPercent")] = process.cpuPercent;
        map[QStringLiteral("displayCpu")] =
            QStringLiteral("%1%").arg(QString::number(process.cpuPercent, 'f', process.cpuPercent >= 10.0 ? 0 : 1));
        map[QStringLiteral("memoryPercent")] = process.memPercent;
        map[QStringLiteral("displayMemory")] = Backend::formatSize(process.rssBytes);
        topProcesses.append(map);
    }

    m_topProcesses = topProcesses;
    m_prevProcessCpuTimes = processTimes;
    m_prevTotalCpuTime = totalCpuTime;
}

void SystemDetailsBackend::readThermalSensors()
{
    struct RawThermalEntry {
        QString key;
        QString name;
        double tempC = 0.0;
    };

    auto tempToCelsius = [](qint64 tempRaw) {
        return std::abs(tempRaw) >= 1000 ? (tempRaw / 1000.0) : static_cast<double>(tempRaw);
    };

    QVector<RawThermalEntry> rawEntries;
    QHash<QString, int> nameCounts;

    const QDir hwmonDir(QStringLiteral("/sys/class/hwmon"));
    const QStringList hwmonEntries = hwmonDir.entryList(QStringList() << QStringLiteral("hwmon*"),
                                                        QDir::Dirs | QDir::NoDotAndDotDot,
                                                        QDir::Name);
    rawEntries.reserve(hwmonEntries.size());

    for (const QString &entryName : hwmonEntries) {
        const QString hwmonPath = hwmonDir.filePath(entryName);
        const QString baseName = Backend::readTextFile(hwmonPath + QStringLiteral("/name")).trimmed();
        if (baseName.isEmpty()) {
            continue;
        }

        const QDir sensorDir(hwmonPath);
        const QStringList tempInputs = sensorDir.entryList(QStringList() << QStringLiteral("temp*_input"),
                                                           QDir::Files,
                                                           QDir::Name);
        for (const QString &tempInput : tempInputs) {
            const qint64 tempRaw = Backend::readTextFile(sensorDir.filePath(tempInput)).toLongLong();
            if (tempRaw <= 0) {
                continue;
            }

            const double tempC = tempToCelsius(tempRaw);
            if (tempC <= 0.0) {
                continue;
            }

            QString displayName = baseName;
            const QString sensorIndex = tempInput.mid(4, tempInput.size() - 10);
            const QString label = Backend::readTextFile(sensorDir.filePath(QStringLiteral("temp%1_label").arg(sensorIndex))).trimmed();
            if (!label.isEmpty()) {
                displayName = QStringLiteral("%1 / %2").arg(baseName, label);
            }

            rawEntries.append({QStringLiteral("%1:%2").arg(entryName, tempInput), displayName, tempC});
            nameCounts[displayName] += 1;
        }
    }

    if (rawEntries.isEmpty()) {
        const QDir thermalDir(QStringLiteral("/sys/class/thermal"));
        const QStringList thermalEntries = thermalDir.entryList(QStringList() << QStringLiteral("thermal_zone*"),
                                                                QDir::Dirs | QDir::NoDotAndDotDot,
                                                                QDir::Name);
        rawEntries.reserve(thermalEntries.size());

        for (const QString &entryName : thermalEntries) {
            const QString zonePath = thermalDir.filePath(entryName);
            const QString type = Backend::readTextFile(zonePath + QStringLiteral("/type")).trimmed();
            const qint64 tempRaw = Backend::readTextFile(zonePath + QStringLiteral("/temp")).toLongLong();
            if (type.isEmpty() || tempRaw <= 0) {
                continue;
            }

            const double tempC = tempToCelsius(tempRaw);
            if (tempC <= 0.0) {
                continue;
            }

            rawEntries.append({entryName, type, tempC});
            nameCounts[type] += 1;
        }
    }

    QVector<ThermalSample> sensors;
    sensors.reserve(rawEntries.size());
    for (const RawThermalEntry &entry : rawEntries) {
        QString displayName = entry.name;
        if (nameCounts.value(entry.name) > 1) {
            displayName = QStringLiteral("%1 (%2)").arg(entry.name, entry.key);
        }

        sensors.append({entry.key, displayName, entry.tempC, thermalColorForName(entry.name)});
    }

    std::sort(sensors.begin(), sensors.end(), [](const ThermalSample &left, const ThermalSample &right) {
        return left.name < right.name;
    });

    QVariantList thermalSensors;
    thermalSensors.reserve(sensors.size());

    for (const ThermalSample &sensor : sensors) {
        QVariantMap map;
        map[QStringLiteral("key")] = sensor.key;
        map[QStringLiteral("name")] = sensor.name;
        map[QStringLiteral("tempC")] = sensor.tempC;
        map[QStringLiteral("displayTemp")] = QStringLiteral("%1 °C").arg(QString::number(sensor.tempC, 'f', 1));
        map[QStringLiteral("color")] = sensor.color;
        thermalSensors.append(map);
    }

    m_thermalSensors = thermalSensors;
}

qint64 SystemDetailsBackend::readTotalMemoryKb() const
{
    QFile memInfo(QStringLiteral("/proc/meminfo"));
    if (!memInfo.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return 0;
    }

    QTextStream stream(&memInfo);
    while (!stream.atEnd()) {
        const QString line = stream.readLine();
        if (!line.startsWith(QStringLiteral("MemTotal:"))) {
            continue;
        }

        const QStringList parts = line.simplified().split(QLatin1Char(' '));
        if (parts.size() >= 2) {
            return parts.at(1).toLongLong();
        }
    }

    return 0;
}

quint64 SystemDetailsBackend::readTotalCpuTime() const
{
    QFile statFile(QStringLiteral("/proc/stat"));
    if (!statFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return 0;
    }

    const QString firstLine = QString::fromUtf8(statFile.readLine()).simplified();
    const QStringList parts = firstLine.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    if (parts.size() < 2 || parts.first() != QStringLiteral("cpu")) {
        return 0;
    }

    quint64 total = 0;
    for (int index = 1; index < parts.size(); ++index) {
        total += parts.at(index).toULongLong();
    }

    return total;
}

bool SystemDetailsBackend::readProcessSample(const QString &pidText, ProcessSample &sample) const
{
    QFile statFile(QStringLiteral("/proc/%1/stat").arg(pidText));
    if (!statFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return false;
    }

    const QString statLine = QString::fromUtf8(statFile.readLine()).trimmed();
    const int openParen = statLine.indexOf(QLatin1Char('('));
    const int closeParen = statLine.lastIndexOf(QLatin1Char(')'));
    if (openParen < 0 || closeParen <= openParen) {
        return false;
    }

    const QString name = statLine.mid(openParen + 1, closeParen - openParen - 1);
    const QString remainder = statLine.mid(closeParen + 2);
    const QStringList fields = remainder.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    if (fields.size() < 22 || fields.first() == QStringLiteral("Z")) {
        return false;
    }

    bool okPid = false;
    const int pid = pidText.toInt(&okPid);
    if (!okPid) {
        return false;
    }

    bool okUser = false;
    bool okSystem = false;
    bool okRss = false;
    const quint64 userTime = fields.at(11).toULongLong(&okUser);
    const quint64 systemTime = fields.at(12).toULongLong(&okSystem);
    const qint64 rssPages = fields.at(21).toLongLong(&okRss);
    if (!okUser || !okSystem || !okRss) {
        return false;
    }

    sample.pid = pid;
    sample.name = name.isEmpty() ? QStringLiteral("unknown") : name;
    sample.totalCpuTime = userTime + systemTime;
    sample.rssBytes = std::max<qint64>(0, rssPages) * m_pageSizeBytes;
    return true;
}
