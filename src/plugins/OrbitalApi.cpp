#include "OrbitalApi.h"

#include "../SystemMonitor.h"

#include <QDebug>
#include <QFile>
#include <QProcess>
#include <QSettings>
#include <QTextStream>

#include <memory>

OrbitalApi::OrbitalApi(SystemMonitor *systemMonitor, const QString &pluginId, QObject *parent)
    : QObject(parent)
    , m_systemMonitor(systemMonitor)
    , m_pluginId(pluginId)
{
}

QObject *OrbitalApi::systemMonitor() const
{
    return m_systemMonitor;
}

void OrbitalApi::run(const QString &program, const QStringList &args, const QJSValue &callback)
{
    auto *proc = new QProcess(this);
    proc->setProgram(program);
    proc->setArguments(args);

    // QJSValue isn't copyable in lambdas as const&; capture by value-then-move.
    // Guard against both finished and errorOccurred firing — only the first
    // wins, the loser becomes a no-op.
    auto fired = std::make_shared<bool>(false);

    QObject::connect(proc, &QProcess::finished, this,
                     [callback, proc, fired](int exitCode, QProcess::ExitStatus) {
                         if (*fired) {
                             proc->deleteLater();
                             return;
                         }
                         *fired = true;

                         QJSValue cb = callback;
                         if (cb.isCallable()) {
                             QJSValueList jsArgs;
                             jsArgs << QJSValue(exitCode);
                             jsArgs << QJSValue(QString::fromUtf8(proc->readAllStandardOutput()));
                             jsArgs << QJSValue(QString::fromUtf8(proc->readAllStandardError()));
                             cb.call(jsArgs);
                         }
                         proc->deleteLater();
                     });

    QObject::connect(proc, &QProcess::errorOccurred, this,
                     [callback, proc, fired](QProcess::ProcessError err) {
                         if (*fired) {
                             return;
                         }
                         *fired = true;

                         QJSValue cb = callback;
                         if (cb.isCallable()) {
                             QJSValueList jsArgs;
                             jsArgs << QJSValue(-1);
                             jsArgs << QJSValue(QString());
                             jsArgs << QJSValue(QStringLiteral("QProcess error: %1").arg(static_cast<int>(err)));
                             cb.call(jsArgs);
                         }
                         proc->deleteLater();
                     });

    proc->start();
}

int OrbitalApi::spawn(const QString &program,
                      const QStringList &args,
                      const QJSValue &onChunk,
                      const QJSValue &onExit)
{
    auto *proc = new QProcess(this);
    proc->setProgram(program);
    proc->setArguments(args);
    // Merge stderr so callers see prompts and warnings inline with stdout.
    proc->setProcessChannelMode(QProcess::MergedChannels);

    const int procId = m_nextProcId++;
    m_processes.insert(procId, proc);

    QObject::connect(proc, &QProcess::readyRead, this,
                     [proc, onChunk]() {
                         const QByteArray data = proc->readAll();
                         if (data.isEmpty()) return;
                         QJSValue cb = onChunk;
                         if (cb.isCallable()) {
                             QJSValueList args;
                             args << QJSValue(QString::fromUtf8(data));
                             cb.call(args);
                         }
                     });

    auto fired = std::make_shared<bool>(false);
    auto finish = [this, procId, proc, onExit, fired](int exitCode) {
        if (*fired) {
            proc->deleteLater();
            return;
        }
        *fired = true;
        m_processes.remove(procId);
        QJSValue cb = onExit;
        if (cb.isCallable()) {
            QJSValueList args;
            args << QJSValue(exitCode);
            cb.call(args);
        }
        proc->deleteLater();
    };

    QObject::connect(proc, &QProcess::finished, this,
                     [finish](int exitCode, QProcess::ExitStatus) { finish(exitCode); });
    QObject::connect(proc, &QProcess::errorOccurred, this,
                     [finish](QProcess::ProcessError) { finish(-1); });

    proc->start();
    return procId;
}

bool OrbitalApi::writeStdin(int procId, const QString &text)
{
    QProcess *proc = m_processes.value(procId);
    if (!proc) return false;
    return proc->write(text.toUtf8()) >= 0;
}

void OrbitalApi::killProc(int procId)
{
    QProcess *proc = m_processes.value(procId);
    if (!proc) return;
    proc->terminate();
    if (!proc->waitForFinished(500)) {
        proc->kill();
    }
}

QString OrbitalApi::readFile(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "OrbitalApi[" << m_pluginId << "]: readFile failed:" << path << f.errorString();
        return QString();
    }
    return QString::fromUtf8(f.readAll());
}

bool OrbitalApi::writeFile(const QString &path, const QString &content)
{
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        qWarning() << "OrbitalApi[" << m_pluginId << "]: writeFile failed:" << path << f.errorString();
        return false;
    }
    const QByteArray bytes = content.toUtf8();
    return f.write(bytes) == bytes.size();
}

void OrbitalApi::toast(const QString &message)
{
    emit toastRequested(message);
}

void OrbitalApi::pushPage(const QUrl &qmlUrl, const QVariantMap &props)
{
    emit pageRequested(qmlUrl, props);
}

void OrbitalApi::popPage()
{
    emit popRequested();
}

QVariant OrbitalApi::settingValue(const QString &key, const QVariant &defaultValue)
{
    QSettings settings;
    return settings.value(scopedSettingKey(key), defaultValue);
}

void OrbitalApi::setSettingValue(const QString &key, const QVariant &value)
{
    QSettings settings;
    settings.setValue(scopedSettingKey(key), value);
}

QString OrbitalApi::scopedSettingKey(const QString &key) const
{
    return QStringLiteral("plugins/%1/%2").arg(m_pluginId, key);
}

void OrbitalApi::registerExports(const QJSValue &exports)
{
    if (m_systemMonitor) {
        m_systemMonitor->registerPluginExports(m_pluginId, exports);
    }
}

QJSValue OrbitalApi::pluginExports(const QString &pluginId)
{
    if (m_systemMonitor) {
        return m_systemMonitor->pluginExports(pluginId);
    }
    return QJSValue();
}
