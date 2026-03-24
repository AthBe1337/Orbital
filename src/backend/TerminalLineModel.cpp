#include "TerminalLineModel.h"

TerminalLineModel::TerminalLineModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int TerminalLineModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }

    return m_lines.size();
}

QVariant TerminalLineModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_lines.size()) {
        return {};
    }

    if (role == HtmlRole || role == Qt::DisplayRole) {
        return m_lines.at(index.row());
    }

    return {};
}

QHash<int, QByteArray> TerminalLineModel::roleNames() const
{
    return {
        { HtmlRole, "html" }
    };
}

void TerminalLineModel::replaceLines(const QStringList &lines)
{
    if (m_lines == lines) {
        return;
    }

    int prefix = 0;
    while (prefix < m_lines.size() && prefix < lines.size() && m_lines.at(prefix) == lines.at(prefix)) {
        ++prefix;
    }

    int oldSuffix = m_lines.size() - 1;
    int newSuffix = lines.size() - 1;
    while (oldSuffix >= prefix && newSuffix >= prefix && m_lines.at(oldSuffix) == lines.at(newSuffix)) {
        --oldSuffix;
        --newSuffix;
    }

    const int oldMiddleCount = std::max(0, oldSuffix - prefix + 1);
    const int newMiddleCount = std::max(0, newSuffix - prefix + 1);

    if (oldMiddleCount > 0 && newMiddleCount > 0 && oldMiddleCount == newMiddleCount) {
        for (int index = 0; index < oldMiddleCount; ++index) {
            m_lines[prefix + index] = lines.at(prefix + index);
        }
        emit dataChanged(createIndex(prefix, 0),
                         createIndex(prefix + oldMiddleCount - 1, 0),
                         { HtmlRole, Qt::DisplayRole });
        return;
    }

    if (oldMiddleCount > 0) {
        beginRemoveRows(QModelIndex(), prefix, prefix + oldMiddleCount - 1);
        for (int index = 0; index < oldMiddleCount; ++index) {
            m_lines.removeAt(prefix);
        }
        endRemoveRows();
    }

    if (newMiddleCount > 0) {
        beginInsertRows(QModelIndex(), prefix, prefix + newMiddleCount - 1);
        for (int index = 0; index < newMiddleCount; ++index) {
            m_lines.insert(prefix + index, lines.at(prefix + index));
        }
        endInsertRows();
    }
}
