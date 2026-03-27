#include "LedBackend.h"

#include "SystemHelpers.h"

#include <algorithm>
#include <QDir>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSet>
#include <QStringList>
#include <QVariantMap>

namespace {

constexpr auto kLedClassPath = "/sys/class/leds";

struct ModePreset
{
    const char *id;
    const char *label;
    const char *trigger;
};

QList<ModePreset> modePresets()
{
    return {
        { "manual", "Manual", "none" },
        { "solid", "Always On", "default-on" },
        { "heartbeat", "Heartbeat", "heartbeat" },
        { "activity", "Activity", "activity" },
        { "timer", "Timer", "timer" },
        { "oneshot", "One Shot", "oneshot" },
        { "pattern", "Pattern", "pattern" },
        { "panic", "Panic", "panic" }
    };
}

int clampPercent(int percent)
{
    return qBound(0, percent, 100);
}

int toPercent(int value, int maxValue)
{
    if (maxValue <= 0) {
        return 0;
    }

    return qBound(0, qRound(static_cast<double>(value) / maxValue * 100.0), 100);
}

int percentToValue(int percent, int maxValue)
{
    if (maxValue <= 0) {
        return 0;
    }

    const int boundedPercent = clampPercent(percent);
    int value = qRound(static_cast<double>(boundedPercent) / 100.0 * maxValue);
    if (boundedPercent > 0 && value == 0) {
        value = 1;
    }

    return qBound(0, value, maxValue);
}

int microsecondsToMilliseconds(int microseconds)
{
    if (microseconds <= 0) {
        return 0;
    }

    return qMax(1, qRound(static_cast<double>(microseconds) / 1000.0));
}

int millisecondsToMicroseconds(int milliseconds, int maxMicroseconds)
{
    if (milliseconds <= 0 || maxMicroseconds <= 0) {
        return 0;
    }

    int value = milliseconds * 1000;
    if (value == 0) {
        value = 1;
    }

    return qBound(0, value, maxMicroseconds);
}

QString normalizeTrigger(const QString &token)
{
    QString trigger = token.trimmed();
    if (trigger.startsWith('[') && trigger.endsWith(']')) {
        trigger = trigger.mid(1, trigger.size() - 2);
    }

    return trigger;
}

QString activeTriggerFromValue(const QString &value)
{
    const QStringList tokens = value.split(' ', Qt::SkipEmptyParts);
    for (const QString &token : tokens) {
        if (token.startsWith('[') && token.endsWith(']')) {
            return normalizeTrigger(token);
        }
    }

    return {};
}

QStringList triggerListFromValue(const QString &value)
{
    QStringList triggers;
    const QStringList tokens = value.split(' ', Qt::SkipEmptyParts);
    for (const QString &token : tokens) {
        const QString trigger = normalizeTrigger(token);
        if (!trigger.isEmpty()) {
            triggers.append(trigger);
        }
    }

    return triggers;
}

QString displayNameForLed(const QString &name)
{
    QString displayName = name;
    displayName.replace(':', ' ');
    displayName.replace('-', ' ');

    const QStringList parts = displayName.split(' ', Qt::SkipEmptyParts);
    QStringList normalizedParts;
    for (const QString &part : parts) {
        QString normalized = part.toLower();
        if (!normalized.isEmpty()) {
            normalized[0] = normalized[0].toUpper();
        }
        normalizedParts.append(normalized);
    }

    return normalizedParts.join(' ');
}

QSet<QString> setFromList(const QStringList &list)
{
    QSet<QString> set;
    for (const QString &item : list) {
        set.insert(item);
    }

    return set;
}

bool shouldExposeDynamicTrigger(const QString &trigger)
{
    if (trigger.isEmpty()) {
        return false;
    }

    if (trigger.startsWith(QStringLiteral("kbd-"))) {
        return false;
    }

    static const QRegularExpression cpuIndexPattern(QStringLiteral("^cpu\\d+$"));
    static const QRegularExpression rfkillIndexPattern(QStringLiteral("^rfkill\\d+$"));
    return !cpuIndexPattern.match(trigger).hasMatch()
        && !rfkillIndexPattern.match(trigger).hasMatch();
}

QString displayLabelForTrigger(const QString &trigger)
{
    if (trigger == QStringLiteral("none")) {
        return QStringLiteral("Manual");
    }

    if (trigger == QStringLiteral("default-on")) {
        return QStringLiteral("Always On");
    }

    if (trigger == QStringLiteral("oneshot")) {
        return QStringLiteral("One Shot");
    }

    QString label = trigger;
    label.replace(':', ' ');
    label.replace('_', ' ');
    label.replace('-', ' ');

    const QStringList parts = label.split(' ', Qt::SkipEmptyParts);
    QStringList normalizedParts;
    for (const QString &part : parts) {
        QString normalized = part.toLower();
        if (!normalized.isEmpty()) {
            normalized[0] = normalized[0].toUpper();
        }
        normalizedParts.append(normalized);
    }

    return normalizedParts.join(' ');
}

} // namespace

LedBackend::LedBackend(QObject *parent)
    : QObject(parent)
{
    reload();
}

QVariantList LedBackend::leds() const
{
    QVariantList list;
    list.reserve(m_leds.size());

    for (const LedInfo &led : m_leds) {
        QVariantMap item;
        item.insert(QStringLiteral("name"), led.name);
        item.insert(QStringLiteral("displayName"), led.displayName);
        item.insert(QStringLiteral("brightness"), toPercent(led.brightness, led.maxBrightness));
        item.insert(QStringLiteral("flashBrightness"), toPercent(led.flashBrightness, led.maxFlashBrightness));
        item.insert(QStringLiteral("flashTimeoutMs"), microsecondsToMilliseconds(led.flashTimeoutUs));
        item.insert(QStringLiteral("trigger"), led.activeTrigger);
        item.insert(QStringLiteral("supportsFlash"), led.supportsFlash);
        list.append(item);
    }

    return list;
}

bool LedBackend::hasLeds() const
{
    return !m_leds.isEmpty();
}

bool LedBackend::supportsFlash() const
{
    for (const LedInfo &led : m_leds) {
        if (led.supportsFlash) {
            return true;
        }
    }

    return false;
}

int LedBackend::allLedBrightness() const
{
    if (m_leds.isEmpty()) {
        return 0;
    }

    int total = 0;
    for (const LedInfo &led : m_leds) {
        total += toPercent(led.brightness, led.maxBrightness);
    }

    return qRound(static_cast<double>(total) / m_leds.size());
}

int LedBackend::allLedFlashBrightness() const
{
    int count = 0;
    int total = 0;
    for (const LedInfo &led : m_leds) {
        if (!led.supportsFlash) {
            continue;
        }

        total += toPercent(led.flashBrightness, led.maxFlashBrightness);
        ++count;
    }

    if (count == 0) {
        return 0;
    }

    return qRound(static_cast<double>(total) / count);
}

int LedBackend::allLedFlashTimeoutMs() const
{
    int count = 0;
    int total = 0;
    for (const LedInfo &led : m_leds) {
        if (!led.supportsFlash) {
            continue;
        }

        total += microsecondsToMilliseconds(led.flashTimeoutUs);
        ++count;
    }

    if (count == 0) {
        return 0;
    }

    return qRound(static_cast<double>(total) / count);
}

int LedBackend::maxLedFlashTimeoutMs() const
{
    int maxValue = 0;
    for (const LedInfo &led : m_leds) {
        maxValue = qMax(maxValue, microsecondsToMilliseconds(led.maxFlashTimeoutUs));
    }

    return maxValue;
}

QVariantList LedBackend::modeOptions() const
{
    QVariantList list;
    if (m_leds.isEmpty()) {
        return list;
    }

    QSet<QString> commonTriggers = setFromList(m_leds.first().triggers);
    for (qsizetype index = 1; index < m_leds.size(); ++index) {
        commonTriggers.intersect(setFromList(m_leds.at(index).triggers));
    }

    QSet<QString> addedTriggers;
    for (const ModePreset &preset : modePresets()) {
        const QString trigger = QString::fromLatin1(preset.trigger);
        if (!commonTriggers.contains(trigger)) {
            continue;
        }

        QVariantMap item;
        item.insert(QStringLiteral("id"), QString::fromLatin1(preset.id));
        item.insert(QStringLiteral("label"), QString::fromLatin1(preset.label));
        item.insert(QStringLiteral("trigger"), trigger);
        list.append(item);
        addedTriggers.insert(trigger);
    }

    QStringList dynamicTriggers = commonTriggers.values();
    std::sort(dynamicTriggers.begin(), dynamicTriggers.end());

    for (const QString &trigger : dynamicTriggers) {
        if (addedTriggers.contains(trigger) || !shouldExposeDynamicTrigger(trigger)) {
            continue;
        }

        QVariantMap item;
        item.insert(QStringLiteral("id"), QStringLiteral("trigger:%1").arg(trigger));
        item.insert(QStringLiteral("label"), displayLabelForTrigger(trigger));
        item.insert(QStringLiteral("trigger"), trigger);
        list.append(item);
    }

    return list;
}

QString LedBackend::currentMode() const
{
    if (m_leds.isEmpty()) {
        return {};
    }

    const QString activeTrigger = m_leds.first().activeTrigger;
    for (qsizetype index = 1; index < m_leds.size(); ++index) {
        if (m_leds.at(index).activeTrigger != activeTrigger) {
            return QStringLiteral("custom");
        }
    }

    const QVariantList options = modeOptions();
    for (const QVariant &optionValue : options) {
        const QVariantMap option = optionValue.toMap();
        if (option.value(QStringLiteral("trigger")).toString() == activeTrigger) {
            return option.value(QStringLiteral("id")).toString();
        }
    }

    return QStringLiteral("custom");
}

void LedBackend::refresh()
{
    reload();
}

void LedBackend::setAllLedBrightness(int percent)
{
    bool changed = false;
    for (LedInfo &led : m_leds) {
        if (!ensureManualMode(led)) {
            continue;
        }

        changed = writeBrightness(led, percent) || changed;
    }

    if (changed) {
        reload();
    }
}

void LedBackend::setLedBrightness(const QString &name, int percent)
{
    LedInfo *led = findLed(name);
    if (!led) {
        return;
    }

    if (!ensureManualMode(*led)) {
        return;
    }

    if (writeBrightness(*led, percent)) {
        reload();
    }
}

void LedBackend::setAllLedFlashBrightness(int percent)
{
    bool changed = false;
    for (LedInfo &led : m_leds) {
        changed = writeFlashBrightness(led, percent) || changed;
    }

    if (changed) {
        reload();
    }
}

void LedBackend::setAllLedFlashTimeoutMs(int milliseconds)
{
    bool changed = false;
    for (LedInfo &led : m_leds) {
        changed = writeFlashTimeoutMs(led, milliseconds) || changed;
    }

    if (changed) {
        reload();
    }
}

void LedBackend::setMode(const QString &modeId)
{
    QString trigger;
    const QVariantList options = modeOptions();
    for (const QVariant &optionValue : options) {
        const QVariantMap option = optionValue.toMap();
        if (option.value(QStringLiteral("id")).toString() == modeId) {
            trigger = option.value(QStringLiteral("trigger")).toString();
            break;
        }
    }

    if (trigger.isEmpty()) {
        return;
    }

    bool changed = false;
    for (LedInfo &led : m_leds) {
        changed = writeTrigger(led, trigger) || changed;
    }

    if (changed) {
        reload();
    }
}

void LedBackend::flashAllLeds()
{
    bool changed = false;
    for (LedInfo &led : m_leds) {
        if (!ensureManualMode(led)) {
            continue;
        }

        changed = writeFlashStrobe(led) || changed;
    }

    if (changed) {
        reload();
    }
}

void LedBackend::flashLed(const QString &name)
{
    LedInfo *led = findLed(name);
    if (!led) {
        return;
    }

    if (!ensureManualMode(*led)) {
        return;
    }

    if (writeFlashStrobe(*led)) {
        reload();
    }
}

LedBackend::LedInfo *LedBackend::findLed(const QString &name)
{
    for (LedInfo &led : m_leds) {
        if (led.name == name) {
            return &led;
        }
    }

    return nullptr;
}

void LedBackend::reload()
{
    QList<LedInfo> updatedLeds;

    QDir dir(QString::fromLatin1(kLedClassPath));
    const QFileInfoList ledInfos = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QFileInfo &info : ledInfos) {
        LedInfo led;
        led.name = info.fileName();
        led.displayName = displayNameForLed(led.name);
        led.path = info.filePath();
        led.maxBrightness = Backend::readTextFile(led.path + "/max_brightness").toInt();
        led.brightness = Backend::readTextFile(led.path + "/brightness").toInt();
        led.maxFlashBrightness = Backend::readTextFile(led.path + "/max_flash_brightness").toInt();
        led.flashBrightness = Backend::readTextFile(led.path + "/flash_brightness").toInt();
        led.maxFlashTimeoutUs = Backend::readTextFile(led.path + "/max_flash_timeout").toInt();
        led.flashTimeoutUs = Backend::readTextFile(led.path + "/flash_timeout").toInt();
        led.supportsFlash = QFileInfo::exists(led.path + "/flash_strobe")
            && QFileInfo::exists(led.path + "/flash_brightness")
            && QFileInfo::exists(led.path + "/flash_timeout");

        const QString triggerValue = Backend::readTextFile(led.path + "/trigger");
        led.activeTrigger = activeTriggerFromValue(triggerValue);
        led.triggers = triggerListFromValue(triggerValue);

        updatedLeds.append(led);
    }

    m_leds = updatedLeds;
    emit stateChanged();
}

bool LedBackend::writeTrigger(LedInfo &led, const QString &trigger)
{
    if (!led.triggers.contains(trigger)) {
        return false;
    }

    return Backend::writeTextFile(led.path + "/trigger", trigger);
}

bool LedBackend::ensureManualMode(LedInfo &led)
{
    if (led.activeTrigger == QStringLiteral("none")) {
        return true;
    }

    return writeTrigger(led, QStringLiteral("none"));
}

bool LedBackend::writeBrightness(LedInfo &led, int percent)
{
    if (led.maxBrightness <= 0) {
        return false;
    }

    return Backend::writeTextFile(led.path + "/brightness",
                                  QString::number(percentToValue(percent, led.maxBrightness)));
}

bool LedBackend::writeFlashBrightness(LedInfo &led, int percent)
{
    if (!led.supportsFlash || led.maxFlashBrightness <= 0) {
        return false;
    }

    return Backend::writeTextFile(led.path + "/flash_brightness",
                                  QString::number(percentToValue(percent, led.maxFlashBrightness)));
}

bool LedBackend::writeFlashTimeoutMs(LedInfo &led, int milliseconds)
{
    if (!led.supportsFlash || led.maxFlashTimeoutUs <= 0) {
        return false;
    }

    return Backend::writeTextFile(led.path + "/flash_timeout",
                                  QString::number(millisecondsToMicroseconds(milliseconds, led.maxFlashTimeoutUs)));
}

bool LedBackend::writeFlashStrobe(LedInfo &led)
{
    if (!led.supportsFlash) {
        return false;
    }

    return Backend::writeTextFile(led.path + "/flash_strobe", QStringLiteral("1"));
}
