#pragma once

#include <QHash>
#include <QJSValue>
#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantMap>

class QProcess;
class SystemMonitor;

class OrbitalApi : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QObject *systemMonitor READ systemMonitor CONSTANT)
    Q_PROPERTY(QString pluginId READ pluginId CONSTANT)

public:
    OrbitalApi(SystemMonitor *systemMonitor, const QString &pluginId, QObject *parent = nullptr);

    QObject *systemMonitor() const;
    QString pluginId() const { return m_pluginId; }

    Q_INVOKABLE void run(const QString &program,
                         const QStringList &args,
                         const QJSValue &callback);

    // Long-lived subprocess with bidirectional IO. onChunk is invoked with
    // (text) for each chunk written to stdout/stderr (merged). onExit is
    // invoked with (exitCode) when the process finishes. Returns a process
    // id usable with writeStdin/killProc, or -1 on failure.
    Q_INVOKABLE int spawn(const QString &program,
                          const QStringList &args,
                          const QJSValue &onChunk,
                          const QJSValue &onExit);
    Q_INVOKABLE bool writeStdin(int procId, const QString &text);
    Q_INVOKABLE void killProc(int procId);

    Q_INVOKABLE QString readFile(const QString &path);
    Q_INVOKABLE bool writeFile(const QString &path, const QString &content);

    Q_INVOKABLE void toast(const QString &message);
    Q_INVOKABLE void pushPage(const QUrl &qmlUrl, const QVariantMap &props = {});
    Q_INVOKABLE void popPage();

    Q_INVOKABLE QVariant settingValue(const QString &key, const QVariant &defaultValue = {});
    Q_INVOKABLE void setSettingValue(const QString &key, const QVariant &value);

signals:
    void toastRequested(QString message);
    void pageRequested(QUrl url, QVariantMap props);
    void popRequested();

private:
    QString scopedSettingKey(const QString &key) const;

    SystemMonitor *m_systemMonitor;
    QString m_pluginId;

    int m_nextProcId = 1;
    QHash<int, QProcess *> m_processes;
};
