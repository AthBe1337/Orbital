#include "SystemMonitor.h"

#include "backend/DisplayBackend.h"
#include "backend/LedBackend.h"
#include "backend/SystemDetailsBackend.h"
#include "backend/SystemHelpers.h"
#include "backend/SystemStatsBackend.h"
#include "backend/WifiBackend.h"

#include <QProcess>
#include <QTimer>

SystemMonitor::SystemMonitor(QObject *parent)
    : QObject(parent)
    , m_statsBackend(new SystemStatsBackend(this))
    , m_displayBackend(new DisplayBackend(this))
    , m_ledBackend(new LedBackend(this))
    , m_systemDetailsBackend(new SystemDetailsBackend(this))
    , m_wifiBackend(new WifiBackend(this))
    , m_timer(new QTimer(this))
{
    connect(m_statsBackend, &SystemStatsBackend::statsUpdated, this, [this]() {
        m_wifiBackend->setNetworkInterfaces(m_statsBackend->netInterfaces());
        emit statsChanged();
    });

    connect(m_displayBackend, &DisplayBackend::brightnessChanged,
            this, &SystemMonitor::brightnessChanged);
    connect(m_displayBackend, &DisplayBackend::screenStateChanged,
            this, &SystemMonitor::screenStateChanged);
    connect(m_displayBackend, &DisplayBackend::volumeKeyEvent,
            this, &SystemMonitor::volumeKeyEvent);
    connect(m_displayBackend, &DisplayBackend::screenshotRequested,
            this, &SystemMonitor::screenshotRequested);

    connect(m_wifiBackend, &WifiBackend::wifiListChanged,
            this, &SystemMonitor::wifiListChanged);
    connect(m_wifiBackend, &WifiBackend::wifiEnabledChanged,
            this, &SystemMonitor::wifiEnabledChanged);
    connect(m_wifiBackend, &WifiBackend::currentWifiDetailsChanged,
            this, &SystemMonitor::currentWifiDetailsChanged);
    connect(m_wifiBackend, &WifiBackend::wifiOperationResult,
            this, &SystemMonitor::wifiOperationResult);

    connect(m_timer, &QTimer::timeout, this, &SystemMonitor::refreshStats);
    m_timer->start(1000);
    QTimer::singleShot(0, this, &SystemMonitor::refreshStats);
}

double SystemMonitor::cpuTotal() const
{
    return m_statsBackend->cpuTotal();
}

QVariantList SystemMonitor::cpuCores() const
{
    return m_statsBackend->cpuCores();
}

double SystemMonitor::memPercent() const
{
    return m_statsBackend->memPercent();
}

QString SystemMonitor::memDetail() const
{
    return m_statsBackend->memDetail();
}

double SystemMonitor::diskPercent() const
{
    return m_statsBackend->diskPercent();
}

QString SystemMonitor::diskRootUsage() const
{
    return m_statsBackend->diskRootUsage();
}

QVariantList SystemMonitor::diskPartitions() const
{
    return m_statsBackend->diskPartitions();
}

int SystemMonitor::batPercent() const
{
    return m_statsBackend->batPercent();
}

QString SystemMonitor::batState() const
{
    return m_statsBackend->batState();
}

QVariantMap SystemMonitor::batDetails() const
{
    return m_statsBackend->batDetails();
}

QVariantList SystemMonitor::cpuHistory() const
{
    return m_statsBackend->cpuHistory();
}

QVariantList SystemMonitor::memHistory() const
{
    return m_statsBackend->memHistory();
}

QVariantList SystemMonitor::netRxHistory() const
{
    return m_statsBackend->netRxHistory();
}

QVariantList SystemMonitor::netTxHistory() const
{
    return m_statsBackend->netTxHistory();
}

QString SystemMonitor::netRxSpeed() const
{
    return m_statsBackend->netRxSpeed();
}

QString SystemMonitor::netTxSpeed() const
{
    return m_statsBackend->netTxSpeed();
}

QString SystemMonitor::loadAverage() const
{
    return m_statsBackend->loadAverage();
}

int SystemMonitor::brightness() const
{
    return m_displayBackend->brightness();
}

QVariantList SystemMonitor::netInterfaces() const
{
    return m_statsBackend->netInterfaces();
}

bool SystemMonitor::isScreenOn() const
{
    return m_displayBackend->isScreenOn();
}

QVariantList SystemMonitor::wifiList() const
{
    return m_wifiBackend->wifiList();
}

bool SystemMonitor::wifiEnabled() const
{
    return m_wifiBackend->wifiEnabled();
}

QVariantMap SystemMonitor::currentWifiDetails() const
{
    return m_wifiBackend->currentWifiDetails();
}

QString SystemMonitor::osVersion() const
{
    return Backend::readOsVersion();
}

QString SystemMonitor::kernelVersion() const
{
    return Backend::readKernelVersion();
}

QObject *SystemMonitor::ledBackend() const
{
    return m_ledBackend;
}

QObject *SystemMonitor::systemDetailsBackend() const
{
    return m_systemDetailsBackend;
}

void SystemMonitor::setWifiEnabled(bool enable)
{
    m_wifiBackend->setWifiEnabled(enable);
}

void SystemMonitor::setBrightness(int percent)
{
    m_displayBackend->setBrightness(percent);
}

void SystemMonitor::connectToWifi(const QString &ssid, const QString &password)
{
    m_wifiBackend->connectToWifi(ssid, password);
}

void SystemMonitor::disconnectFromWifi(const QString &ssid)
{
    m_wifiBackend->disconnectFromWifi(ssid);
}

void SystemMonitor::forgetNetwork(const QString &ssid)
{
    m_wifiBackend->forgetNetwork(ssid);
}

void SystemMonitor::setAutoConnect(const QString &ssid, bool autoConnect)
{
    m_wifiBackend->setAutoConnect(ssid, autoConnect);
}

void SystemMonitor::scanWifiNetworks()
{
    m_wifiBackend->scanWifiNetworks();
}

QString SystemMonitor::nextScreenshotPath() const
{
    return Backend::nextScreenshotFilePath();
}

void SystemMonitor::systemCmd(const QString &cmd)
{
    if (cmd == "reboot") {
        QProcess::execute("reboot");
    }

    if (cmd == "poweroff") {
        QProcess::execute("poweroff");
    }
}

void SystemMonitor::refreshStats()
{
    m_statsBackend->update();
}
