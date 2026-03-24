#pragma once

#include <QFile>
#include <QString>
#include <QTextStream>
#include <QtGlobal>

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
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        return false;
    }

    QTextStream out(&file);
    out << value;
    return true;
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

} // namespace Backend
