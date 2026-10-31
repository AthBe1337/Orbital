#pragma once

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QString>
#include <QTextStream>
#include <QtGlobal>

#include <pwd.h>
#include <sys/types.h>

namespace Backend {

inline QString readTextFile(const QString &path)
{
    QFile file(path);
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString::fromUtf8(file.readAll()).trimmed();
    }

    return {};
}

inline bool writeTextFile(const QString &path, const QString &value)
{
    QFile file(path);
    if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream out(&file);
        out << value;
        out.flush();
        if (out.status() == QTextStream::Ok) {
            return true;
        }
    }

    QProcess process;
    process.start(QStringLiteral("/usr/bin/sudo"),
                  QStringList{QStringLiteral("-n"), QStringLiteral("/usr/bin/tee"), path});
    if (!process.waitForStarted(1000)) {
        return false;
    }

    process.write(value.toUtf8());
    process.closeWriteChannel();
    if (!process.waitForFinished(3000)) {
        process.kill();
        process.waitForFinished();
        return false;
    }

    return process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
}

inline QString formatSize(qint64 bytes)
{
    if (bytes < 1024) {
        return QString::number(bytes) + " B";
    }

    if (bytes < 1024 * 1024) {
        return QString::number(bytes / 1024.0, 'f', 1) + " KB";
    }

    if (bytes < 1024 * 1024 * 1024) {
        return QString::number(bytes / 1024.0 / 1024.0, 'f', 1) + " MB";
    }

    return QString::number(bytes / 1024.0 / 1024.0 / 1024.0, 'f', 1) + " GB";
}

inline QString formatSpeed(quint64 bytes)
{
    if (bytes < 1024) {
        return QString::number(bytes) + " B/s";
    }

    if (bytes < 1024 * 1024) {
        return QString::number(bytes / 1024.0, 'f', 1) + " KB/s";
    }

    if (bytes < 1024 * 1024 * 1024) {
        return QString::number(bytes / 1024.0 / 1024.0, 'f', 1) + " MB/s";
    }

    return QString::number(bytes / 1024.0 / 1024.0 / 1024.0, 'f', 1) + " GB/s";
}

inline QString readOsVersion()
{
    const QString content = readTextFile("/etc/os-release");
    const QStringList lines = content.split('\n');

    for (const QString &line : lines) {
        if (line.startsWith("PRETTY_NAME=")) {
            QString name = line.mid(12);
            return name.replace("\"", "");
        }
    }

    for (const QString &line : lines) {
        if (line.startsWith("NAME=")) {
            QString name = line.mid(5);
            return name.replace("\"", "");
        }
    }

    return "Linux System";
}

inline QString readKernelVersion()
{
    const QString release = readTextFile("/proc/sys/kernel/osrelease");
    if (!release.isEmpty()) {
        return "Linux " + release;
    }

    const QString version = readTextFile("/proc/version");
    if (!version.isEmpty()) {
        const int detailsIndex = version.indexOf(" (");
        if (detailsIndex > 0) {
            return version.left(detailsIndex);
        }

        const QStringList parts = version.split(' ', Qt::SkipEmptyParts);
        if (parts.size() >= 3 && parts.at(0) == "Linux" && parts.at(1) == "version") {
            return "Linux " + parts.at(2);
        }

        return version;
    }

    return "Unknown Kernel";
}

inline QString readEnvironmentValue(const char *name)
{
    return QString::fromLocal8Bit(qgetenv(name)).trimmed();
}

inline QString homePathForUserName(const QString &userName)
{
    if (userName.isEmpty()) {
        return {};
    }

    const QByteArray localName = userName.toLocal8Bit();
    passwd *entry = getpwnam(localName.constData());
    if (entry && entry->pw_dir) {
        return QString::fromLocal8Bit(entry->pw_dir);
    }

    const QString fallback = QDir(QStringLiteral("/home")).filePath(userName);
    if (QFileInfo::exists(fallback)) {
        return fallback;
    }

    return {};
}

inline QString homePathForUidEnv(const char *name)
{
    bool ok = false;
    const uint uidValue = readEnvironmentValue(name).toUInt(&ok);
    if (!ok) {
        return {};
    }

    passwd *entry = getpwuid(static_cast<uid_t>(uidValue));
    if (!entry || !entry->pw_dir) {
        return {};
    }

    return QString::fromLocal8Bit(entry->pw_dir);
}

inline QString preferredUserHomePath()
{
    const QString sudoUserHome = homePathForUserName(readEnvironmentValue("SUDO_USER"));
    if (!sudoUserHome.isEmpty()) {
        return sudoUserHome;
    }

    const QString pkexecUserHome = homePathForUserName(readEnvironmentValue("PKEXEC_USER"));
    if (!pkexecUserHome.isEmpty()) {
        return pkexecUserHome;
    }

    const QString sudoUidHome = homePathForUidEnv("SUDO_UID");
    if (!sudoUidHome.isEmpty()) {
        return sudoUidHome;
    }

    const QString pkexecUidHome = homePathForUidEnv("PKEXEC_UID");
    if (!pkexecUidHome.isEmpty()) {
        return pkexecUidHome;
    }

    const QString currentHome = QDir::homePath();
    if (!currentHome.isEmpty() && currentHome != QStringLiteral("/root")) {
        return currentHome;
    }

    const QFileInfoList homeEntries = QDir(QStringLiteral("/home"))
                                          .entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    if (homeEntries.size() == 1) {
        return homeEntries.constFirst().absoluteFilePath();
    }

    for (const QFileInfo &entry : homeEntries) {
        if (QFileInfo(entry.absoluteFilePath() + QStringLiteral("/Pictures")).exists()) {
            return entry.absoluteFilePath();
        }
    }

    return currentHome;
}

inline QString screenshotDirectory()
{
    const QString configuredDir = readEnvironmentValue("ORBITAL_SCREENSHOT_DIR");
    if (!configuredDir.isEmpty()) {
        return QDir::cleanPath(configuredDir);
    }

    QString baseHome = preferredUserHomePath();
    if (baseHome.isEmpty()) {
        baseHome = QDir::homePath();
    }
    if (baseHome.isEmpty()) {
        baseHome = QDir::currentPath();
    }

    return QDir::cleanPath(baseHome + QStringLiteral("/Pictures/Orbital/Screenshots"));
}

inline QString nextScreenshotFilePath()
{
    const QString dirPath = screenshotDirectory();
    if (dirPath.isEmpty()) {
        return {};
    }

    QDir dir;
    if (!dir.mkpath(dirPath)) {
        return {};
    }

    const QString fileName = QStringLiteral("Orbital_%1.png")
                                 .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd_HH-mm-ss-zzz")));
    return QDir(dirPath).filePath(fileName);
}

} // namespace Backend
