#pragma once

#include <QObject>

class QSocketNotifier;
class QTimer;
class TerminalLineModel;

class TerminalBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QObject* lineModel READ lineModel CONSTANT)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusChanged)
    Q_PROPERTY(int columns READ columns NOTIFY sizeChanged)
    Q_PROPERTY(int rows READ rows NOTIFY sizeChanged)
    Q_PROPERTY(int cursorRow READ cursorRow NOTIFY cursorChanged)
    Q_PROPERTY(int cursorColumn READ cursorColumn NOTIFY cursorChanged)
    Q_PROPERTY(int fontPixelSize READ fontPixelSize WRITE setFontPixelSize NOTIFY fontPixelSizeChanged)
    Q_PROPERTY(int minFontPixelSize READ minFontPixelSize CONSTANT)
    Q_PROPERTY(int maxFontPixelSize READ maxFontPixelSize CONSTANT)

public:
    explicit TerminalBackend(QObject *parent = nullptr);
    ~TerminalBackend() override;

    QObject *lineModel() const;
    bool running() const;
    bool connected() const;
    QString title() const;
    QString statusText() const;
    int columns() const;
    int rows() const;
    int cursorRow() const;
    int cursorColumn() const;
    int fontPixelSize() const;
    int minFontPixelSize() const;
    int maxFontPixelSize() const;
    void setFontPixelSize(int fontPixelSize);

    Q_INVOKABLE void sendText(const QString &text);
    Q_INVOKABLE void sendCharacter(const QString &text, int modifiers = 0);
    Q_INVOKABLE void sendKey(int key, int modifiers = 0);
    Q_INVOKABLE void resizeTerminal(int columns, int rows);
    Q_INVOKABLE void resetTerminal();
    Q_INVOKABLE void clearTerminal();
    Q_INVOKABLE void clearScrollback();
    Q_INVOKABLE void copySelection(int startRow, int startCol, int endRow, int endCol);
    Q_INVOKABLE void pasteFromClipboard();

signals:
    void screenChanged();
    void runningChanged();
    void connectedChanged();
    void titleChanged();
    void statusChanged();
    void sizeChanged();
    void cursorChanged();
    void fontPixelSizeChanged();

private slots:
    void handleReadyRead();
    void pollChildStatus();

private:
    struct TerminalStyleState;
    void startSession();
    void stopSession(bool restart = false);
    void updateStateAfterChildExit(int exitStatus);
    void processBytes(const QByteArray &data);
    void writeBytes(const QByteArray &bytes);
    void rebuildLinesCache();
    void clearActiveScreen(bool clearScrollback = false);
    void markScreenDirty();

    void handleUtf8Byte(unsigned char byte);
    void flushPendingUtf8();
    void putText(const QString &text);
    void putCharacter(const QString &text);
    void lineFeed();
    void reverseIndex();
    void carriageReturn();
    void backspace();
    void tab();
    void saveCursor();
    void restoreCursor();
    void resetParserState();
    void resetScreenState();
    void setTitle(const QString &title);

    void handleCsiSequence(const QByteArray &sequence);
    void handleOscSequence(const QByteArray &sequence);
    void applySgrParameters(const QList<int> &params);
    void setPrivateMode(int mode, bool enabled);

    QString resolveShellPath() const;
    QString selectionText(int startRow, int startCol, int endRow, int endCol) const;

    struct ScreenState;
    ScreenState *m_mainScreen = nullptr;
    ScreenState *m_altScreen = nullptr;
    TerminalStyleState *m_styleState = nullptr;
    TerminalLineModel *m_lineModel = nullptr;

    QSocketNotifier *m_notifier = nullptr;
    QTimer *m_pollTimer = nullptr;

    int m_masterFd = -1;
    qint64 m_childPid = -1;
    int m_columns = 80;
    int m_rows = 24;
    int m_cursorRow = 0;
    int m_cursorColumn = 0;
    int m_maxScrollback = 2000;
    int m_expectedUtf8Bytes = 0;
    int m_savedMainCursorRow = 0;
    int m_savedMainCursorColumn = 0;
    int m_fontPixelSize = 15;

    bool m_running = false;
    bool m_connected = false;
    bool m_useAlternateScreen = false;
    bool m_linesDirty = true;
    bool m_bracketedPasteMode = false;

    QByteArray m_csiBuffer;
    QByteArray m_oscBuffer;
    QByteArray m_utf8Buffer;
    char m_charsetTarget = 0;
    QString m_title = QStringLiteral("Terminal");
    QString m_statusText = QStringLiteral("Starting shell...");
    bool m_g0SpecialGraphics = false;
    bool m_g1SpecialGraphics = false;
    bool m_shiftOut = false;

    enum class ParserState {
        Normal,
        Escape,
        Charset,
        Csi,
        Osc,
        OscEscape
    };

    ParserState m_parserState = ParserState::Normal;
};
