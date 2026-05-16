#include "PluginManager.h"

#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSet>

namespace {

bool isValidId(const QString &id)
{
    static const QRegularExpression rx(QStringLiteral("^[a-z][a-z0-9-]*$"));
    return rx.match(id).hasMatch();
}

} // namespace

PluginManager::PluginManager(QObject *parent)
    : QObject(parent)
{
}

void PluginManager::addRoot(const QUrl &root)
{
    if (!m_roots.contains(root)) {
        m_roots.append(root);
    }
}

void PluginManager::scan()
{
    m_plugins.clear();
    for (const QUrl &root : m_roots) {
        scanRoot(root);
    }
    recomputeAvailability();
    emit pluginsChanged();
}

QVariantList PluginManager::pluginsVariant() const
{
    QVariantList out;
    out.reserve(m_plugins.size());
    for (const PluginInfo &p : m_plugins) {
        if (p.available) {
            out.append(p.toVariantMap());
        }
    }
    return out;
}

void PluginManager::scanRoot(const QUrl &root)
{
    const QString rootPath = urlToFsPath(root);
    QDir rootDir(rootPath);
    if (!rootDir.exists()) {
        qDebug() << "PluginManager: root not found:" << rootPath;
        return;
    }

    const QStringList entries = rootDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &entry : entries) {
        const QUrl pluginDir = joinUrl(root, entry);
        PluginInfo info;
        if (!parseManifest(pluginDir, info)) {
            continue;
        }

        info.pluginDir = pluginDir;
        m_plugins.append(info);
        qDebug().noquote() << "PluginManager: loaded" << info.id
                           << "v" + info.version
                           << "from" << pluginDir.toString();
    }
}

bool PluginManager::parseManifest(const QUrl &pluginDirUrl, PluginInfo &out) const
{
    const QString dirPath = urlToFsPath(pluginDirUrl);
    const QString manifestPath = dirPath + QStringLiteral("/manifest.json");

    QFile mf(manifestPath);
    if (!mf.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return false;
    }

    QJsonParseError err{};
    const QJsonDocument doc = QJsonDocument::fromJson(mf.readAll(), &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        qWarning() << "PluginManager: invalid manifest at" << manifestPath << "-" << err.errorString();
        return false;
    }

    const QJsonObject obj = doc.object();
    out.id = obj.value(QStringLiteral("id")).toString();
    out.name = obj.value(QStringLiteral("name")).toString();
    out.version = obj.value(QStringLiteral("version")).toString();
    out.description = obj.value(QStringLiteral("description")).toString();

    const QString pageRel = obj.value(QStringLiteral("page")).toString();
    if (out.id.isEmpty() || out.name.isEmpty() || out.version.isEmpty() || pageRel.isEmpty()) {
        qWarning() << "PluginManager: manifest missing required fields:" << manifestPath;
        return false;
    }

    if (!isValidId(out.id)) {
        qWarning() << "PluginManager: invalid plugin id (must match [a-z][a-z0-9-]*):" << out.id;
        return false;
    }

    out.pageUrl = joinUrl(pluginDirUrl, pageRel);

    const QString rowRel = obj.value(QStringLiteral("row")).toString();
    if (!rowRel.isEmpty()) {
        out.rowUrl = joinUrl(pluginDirUrl, rowRel);
    }

    const QString iconRel = obj.value(QStringLiteral("icon")).toString();
    if (!iconRel.isEmpty()) {
        out.iconUrl = joinUrl(pluginDirUrl, iconRel);
    }

    const QString serviceRel = obj.value(QStringLiteral("service")).toString();
    if (!serviceRel.isEmpty()) {
        out.serviceUrl = joinUrl(pluginDirUrl, serviceRel);
    }

    const QJsonValue deps = obj.value(QStringLiteral("dependencies"));
    if (deps.isArray()) {
        for (const QJsonValue &v : deps.toArray()) {
            const QString depId = v.toString();
            if (!depId.isEmpty() && !out.dependencies.contains(depId)) {
                out.dependencies.append(depId);
            }
        }
    }

    return true;
}

void PluginManager::recomputeAvailability()
{
    QSet<QString> known;
    for (const PluginInfo &p : m_plugins) {
        known.insert(p.id);
    }

    for (PluginInfo &p : m_plugins) {
        p.available = false;
        p.missingDependencies.clear();
        for (const QString &dep : p.dependencies) {
            if (!known.contains(dep)) {
                p.missingDependencies.append(dep);
            }
        }
    }

    // Fixed point: a plugin becomes available when no missing deps and every
    // declared dep is itself already available. Cycles end stuck unavailable.
    bool changed = true;
    while (changed) {
        changed = false;
        for (PluginInfo &p : m_plugins) {
            if (p.available || !p.missingDependencies.isEmpty()) {
                continue;
            }

            bool depsOk = true;
            for (const QString &dep : p.dependencies) {
                bool ok = false;
                for (const PluginInfo &q : m_plugins) {
                    if (q.id == dep && q.available) {
                        ok = true;
                        break;
                    }
                }
                if (!ok) {
                    depsOk = false;
                    break;
                }
            }

            if (depsOk) {
                p.available = true;
                changed = true;
            }
        }
    }

    for (const PluginInfo &p : m_plugins) {
        if (!p.missingDependencies.isEmpty()) {
            qWarning().noquote() << "PluginManager:" << p.id
                                 << "has missing dependencies:"
                                 << p.missingDependencies.join(QStringLiteral(", "));
        } else if (!p.available) {
            qWarning().noquote() << "PluginManager:" << p.id
                                 << "unavailable (cyclic dependency)";
        }
    }
}

QString PluginManager::urlToFsPath(const QUrl &url)
{
    if (url.scheme() == QLatin1String("qrc")) {
        return QStringLiteral(":") + url.path();
    }
    if (url.isLocalFile()) {
        return url.toLocalFile();
    }
    return url.toString();
}

QUrl PluginManager::joinUrl(const QUrl &base, const QString &child)
{
    QString path = base.path();
    if (!path.endsWith(QLatin1Char('/'))) {
        path += QLatin1Char('/');
    }
    path += child;

    QUrl out = base;
    out.setPath(path);
    return out;
}
