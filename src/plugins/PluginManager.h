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

public:
    explicit PluginManager(QObject *parent = nullptr);

    void addRoot(const QUrl &root);
    void scan();

    QVariantList pluginsVariant() const;

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
