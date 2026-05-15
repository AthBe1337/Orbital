#pragma once

#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantMap>

struct PluginInfo
{
    QString id;
    QString name;
    QString version;
    QString description;
    QUrl iconUrl;
    QUrl pageUrl;
    QUrl rowUrl;
    QUrl pluginDir;
    QStringList dependencies;
    bool enabled = true;
    bool available = true;
    QStringList missingDependencies;

    QVariantMap toVariantMap() const
    {
        return {
            {QStringLiteral("id"), id},
            {QStringLiteral("name"), name},
            {QStringLiteral("version"), version},
            {QStringLiteral("description"), description},
            {QStringLiteral("iconUrl"), iconUrl},
            {QStringLiteral("pageUrl"), pageUrl},
            {QStringLiteral("rowUrl"), rowUrl},
            {QStringLiteral("pluginDir"), pluginDir},
            {QStringLiteral("dependencies"), dependencies},
            {QStringLiteral("enabled"), enabled},
            {QStringLiteral("available"), available},
            {QStringLiteral("missingDependencies"), missingDependencies},
            {QStringLiteral("effectivelyEnabled"), enabled && available},
        };
    }
};
