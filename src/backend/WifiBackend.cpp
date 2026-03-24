#include "WifiBackend.h"

#include <QDebug>
#include <QProcess>
#include <QTimer>

#include <algorithm>

WifiBackend::WifiBackend(QObject *parent)
    : QObject(parent)
    , m_wifiTimer(new QTimer(this))
{
    fetchSavedWifiList();
    initWifiEnabled();

    m_wifiTimer->setInterval(5000);
    connect(m_wifiTimer, &QTimer::timeout, this, &WifiBackend::scanWifiNetworks);

    if (m_wifiEnabled) {
        scanWifiNetworks();
        m_wifiTimer->start();
    }
}

QVariantList WifiBackend::wifiList() const
{
    return m_wifiList;
}

bool WifiBackend::wifiEnabled() const
{
    return m_wifiEnabled;
}

QVariantMap WifiBackend::currentWifiDetails() const
{
    return m_currentWifiDetails;
}

void WifiBackend::setNetworkInterfaces(const QVariantList &interfaces)
{
    m_netInterfaces = interfaces;
}

void WifiBackend::setWifiEnabled(bool enable)
{
    if (m_wifiEnabled == enable) {
        return;
    }

    QProcess *proc = new QProcess(this);
    const QString state = enable ? "on" : "off";

    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            [this, proc, enable](int exitCode, QProcess::ExitStatus) {
        const bool success = (exitCode == 0);
        if (success) {
            m_wifiEnabled = enable;
            if (enable) {
                fetchSavedWifiList();
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

        const QString errorMsg = success ? QString() : QString::fromUtf8(proc->readAllStandardError());
        emit wifiOperationResult("toggle", success, errorMsg);

        proc->deleteLater();
    });

    proc->start("nmcli", QStringList() << "radio" << "wifi" << state);
}

void WifiBackend::connectToWifi(const QString &ssid, const QString &password)
{
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
        const bool success = (exitCode == 0);
        const QString output = QString::fromUtf8(proc->readAllStandardOutput());
        const QString error = QString::fromUtf8(proc->readAllStandardError());

        if (success) {
            fetchSavedWifiList();
            scanWifiNetworks();
        }

        emit wifiOperationResult("connect", success, success ? output : error);
        proc->deleteLater();
    });

    proc->start("nmcli", args);
}

void WifiBackend::disconnectFromWifi(const QString &ssid)
{
    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            [this, proc](int exitCode, QProcess::ExitStatus) {
        const bool success = (exitCode == 0);
        if (success) {
            scanWifiNetworks();
        }

        emit wifiOperationResult("disconnect", success, QString::fromUtf8(proc->readAllStandardError()));
        proc->deleteLater();
    });

    proc->start("nmcli", QStringList() << "connection" << "down" << "id" << ssid);
}

void WifiBackend::forgetNetwork(const QString &ssid)
{
    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            [this, proc, ssid](int exitCode, QProcess::ExitStatus) {
        const bool success = (exitCode == 0);
        if (success) {
            m_savedSsids.removeAll(ssid);
            scanWifiNetworks();
        }

        emit wifiOperationResult("forget", success, QString::fromUtf8(proc->readAllStandardError()));
        proc->deleteLater();
    });

    proc->start("nmcli", QStringList() << "connection" << "delete" << "id" << ssid);
}

void WifiBackend::setAutoConnect(const QString &ssid, bool autoConnect)
{
    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            [proc](int exitCode, QProcess::ExitStatus) {
        if (exitCode != 0) {
            qDebug() << "Failed to set auto-connect:" << proc->readAllStandardError();
        }

        proc->deleteLater();
    });

    const QString value = autoConnect ? "yes" : "no";
    proc->start("nmcli", QStringList()
                             << "connection" << "modify" << "id" << ssid
                             << "connection.autoconnect" << value);

    fetchSavedWifiList();
}

void WifiBackend::scanWifiNetworks()
{
    if (!m_wifiEnabled) {
        return;
    }

    QProcess *proc = new QProcess(this);
    const QStringList args =
        QStringList() << "-t" << "-f" << "SSID,SIGNAL,SECURITY,IN-USE,CHAN"
                      << "dev" << "wifi" << "list";

    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            [this, proc](int exitCode, QProcess::ExitStatus) {
        if (exitCode == 0) {
            parseWifiOutput(QString::fromUtf8(proc->readAllStandardOutput()));
        }

        proc->deleteLater();
    });

    proc->start("nmcli", args);
}

void WifiBackend::parseWifiOutput(const QString &output)
{
    QVariantList connectedList;
    QVariantList savedList;
    QVariantList otherList;
    const QStringList lines = output.split('\n', Qt::SkipEmptyParts);
    QStringList seenSsids;

    auto strengthValue = [](const QVariant &item) {
        const QVariantMap map = item.toMap();
        bool ok = false;
        const int numeric = map.value("level").toInt(&ok);
        return ok ? numeric : 0;
    };

    for (const QString &line : lines) {
        const int chanSep = line.lastIndexOf(':');
        if (chanSep == -1) {
            continue;
        }

        const int inUseSep = line.lastIndexOf(':', chanSep - 1);
        if (inUseSep == -1) {
            continue;
        }

        const QString inUseStr = line.mid(inUseSep + 1, chanSep - inUseSep - 1);

        const int secSep = line.lastIndexOf(':', inUseSep - 1);
        if (secSep == -1) {
            continue;
        }

        const QString security = line.mid(secSep + 1, inUseSep - secSep - 1);

        const int sigSep = line.lastIndexOf(':', secSep - 1);
        if (sigSep == -1) {
            continue;
        }

        const QString signal = line.mid(sigSep + 1, secSep - sigSep - 1);
        const QString ssid = line.left(sigSep);

        if (ssid.isEmpty() || seenSsids.contains(ssid)) {
            continue;
        }

        seenSsids.append(ssid);

        QVariantMap wifi;
        wifi["ssid"] = ssid;

        bool sigOk = false;
        const int signalVal = signal.toInt(&sigOk);
        wifi["level"] = sigOk ? signalVal : 0;
        wifi["secured"] = !security.isEmpty();
        wifi["connected"] = (inUseStr == "*");
        wifi["securityType"] = security.split(' ', Qt::SkipEmptyParts).join(" / ");
        wifi["isSaved"] = m_savedSsids.contains(ssid);
        wifi["autoConnect"] = m_savedAutoConnect.contains(ssid);

        if (wifi["connected"].toBool()) {
            m_currentWifiDetails = wifi;
            for (const QVariant &value : m_netInterfaces) {
                const QVariantMap iface = value.toMap();
                const QString name = iface.value("name").toString();
                if (name.startsWith("wlan") || name.startsWith("wl")) {
                    m_currentWifiDetails["ip"] = iface.value("ips").toList().value(0, "").toString();
                    m_currentWifiDetails["mac"] = iface.value("mac").toString();
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

void WifiBackend::initWifiEnabled()
{
    QProcess proc;
    proc.start("nmcli", QStringList() << "radio" << "wifi");
    proc.waitForFinished();
    m_wifiEnabled = (QString::fromUtf8(proc.readAllStandardOutput()).trimmed() == "enabled");
}

void WifiBackend::fetchSavedWifiList()
{
    QProcess proc;
    proc.start("nmcli", QStringList() << "-t" << "-f" << "NAME,TYPE,AUTOCONNECT"
                                      << "connection" << "show");
    proc.waitForFinished(1000);

    if (proc.exitCode() != 0) {
        return;
    }

    const QString output = QString::fromUtf8(proc.readAllStandardOutput());
    const QStringList lines = output.split('\n', Qt::SkipEmptyParts);

    m_savedSsids.clear();
    m_savedAutoConnect.clear();

    for (const QString &line : lines) {
        const QStringList parts = line.split(':');
        if (parts.size() < 3) {
            continue;
        }

        const QString name = parts[0];
        const QString type = parts[1];
        const QString autoConn = parts[2];

        if (type == "802-11-wireless") {
            m_savedSsids.append(name);
            if (autoConn == "yes") {
                m_savedAutoConnect.insert(name);
            }
        }
    }
}
