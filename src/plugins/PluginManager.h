#pragma once

#include "PluginInfo.h"

#include <QList>
#include <QObject>
#include <QUrl>
#include <QVariantList>

class PluginManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList plugins READ pluginsVariant NOTIFY pluginsChanged)
    Q_PROPERTY(QVariantList allPlugins READ allPluginsVariant NOTIFY pluginsChanged)

public:
    explicit PluginManager(QObject *parent = nullptr);

    void addRoot(const QUrl &root);
    void scan();

    QVariantList pluginsVariant() const;
    QVariantList allPluginsVariant() const;

    Q_INVOKABLE void setEnabled(const QString &id, bool enabled);
    Q_INVOKABLE bool isEnabled(const QString &id) const;

signals:
    void pluginsChanged();

private:
    void scanRoot(const QUrl &root);
    bool parseManifest(const QUrl &pluginDirUrl, PluginInfo &out) const;
    void recomputeAvailability();
    static QString urlToFsPath(const QUrl &url);
    static QUrl joinUrl(const QUrl &base, const QString &child);

    QList<QUrl> m_roots;
    QList<PluginInfo> m_plugins;
};
