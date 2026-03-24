#pragma once

#include <QAbstractListModel>
#include <QStringList>

class TerminalLineModel : public QAbstractListModel
{
    Q_OBJECT

public:
    enum Role {
        HtmlRole = Qt::UserRole + 1
    };

    explicit TerminalLineModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void replaceLines(const QStringList &lines);

private:
    QStringList m_lines;
};
