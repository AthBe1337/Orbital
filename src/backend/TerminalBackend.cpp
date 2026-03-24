#include "TerminalBackend.h"
#include "TerminalLineModel.h"

#include <QClipboard>
#include <QColor>
#include <QFileInfo>
#include <QGuiApplication>
#include <QSettings>
#include <QSocketNotifier>
#include <QTimer>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstring>

#include <fcntl.h>
#include <pty.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>

namespace {

constexpr int kTabWidth = 8;
constexpr char kEsc = 0x1b;
constexpr int kDefaultFontPixelSize = 15;
constexpr int kMinFontPixelSize = 12;
constexpr int kMaxFontPixelSize = 22;

struct TerminalStyle
{
    QColor foreground = QColor(QStringLiteral("#ECEFF4"));
    QColor background = QColor(QStringLiteral("#121212"));
    bool defaultForeground = true;
    bool defaultBackground = true;
    bool bold = false;
    bool underline = false;
    bool inverse = false;

    bool operator==(const TerminalStyle &other) const
    {
        return foreground == other.foreground &&
               background == other.background &&
               defaultForeground == other.defaultForeground &&
               defaultBackground == other.defaultBackground &&
               bold == other.bold &&
               underline == other.underline &&
               inverse == other.inverse;
    }
};

struct TerminalCell
{
    QString text = QStringLiteral(" ");
    TerminalStyle style;
};

using TerminalRow = QVector<TerminalCell>;

TerminalStyle defaultStyle()
{
    return TerminalStyle{};
}

TerminalCell blankCell()
{
    TerminalCell cell;
    cell.text = QStringLiteral(" ");
    cell.style = defaultStyle();
    return cell;
}

TerminalRow blankRow(int columns)
{
    TerminalRow row;
    row.resize(columns);
    std::fill(row.begin(), row.end(), blankCell());
    return row;
}

bool isDisplayCell(const TerminalCell &cell)
{
    return cell.text != QStringLiteral(" ") ||
           !cell.style.defaultForeground ||
           !cell.style.defaultBackground ||
           cell.style.bold ||
           cell.style.underline ||
           cell.style.inverse;
}

QString encodeHtmlText(const QString &text)
{
    QString escaped = text.toHtmlEscaped();
    escaped.replace(QStringLiteral(" "), QStringLiteral("&nbsp;"));
    return escaped;
}

QChar mapDecSpecialGraphics(QChar character)
{
    switch (character.unicode()) {
    case '`':
        return QChar(0x25C6);
    case 'a':
        return QChar(0x2592);
    case 'f':
        return QChar(0x00B0);
    case 'g':
        return QChar(0x00B1);
    case 'h':
        return QChar(0x2424);
    case 'i':
        return QChar(0x240B);
    case 'j':
        return QChar(0x2518);
    case 'k':
        return QChar(0x2510);
    case 'l':
        return QChar(0x250C);
    case 'm':
        return QChar(0x2514);
    case 'n':
        return QChar(0x253C);
    case 'o':
        return QChar(0x23BA);
    case 'p':
        return QChar(0x23BB);
    case 'q':
        return QChar(0x2500);
    case 'r':
        return QChar(0x23BC);
    case 's':
        return QChar(0x23BD);
    case 't':
        return QChar(0x251C);
    case 'u':
        return QChar(0x2524);
    case 'v':
        return QChar(0x2534);
    case 'w':
        return QChar(0x252C);
    case 'x':
        return QChar(0x2502);
    case 'y':
        return QChar(0x2264);
    case 'z':
        return QChar(0x2265);
    case '{':
        return QChar(0x03C0);
    case '|':
        return QChar(0x2260);
    case '}':
        return QChar(0x00A3);
    case '~':
        return QChar(0x00B7);
    default:
        return character;
    }
}

QColor colorFromIndex(int index)
{
    static const std::array<QColor, 16> basicColors = {
        QColor(QStringLiteral("#121212")),
        QColor(QStringLiteral("#BF616A")),
        QColor(QStringLiteral("#A3BE8C")),
        QColor(QStringLiteral("#EBCB8B")),
        QColor(QStringLiteral("#81A1C1")),
        QColor(QStringLiteral("#B48EAD")),
        QColor(QStringLiteral("#88C0D0")),
        QColor(QStringLiteral("#E5E9F0")),
        QColor(QStringLiteral("#4C566A")),
        QColor(QStringLiteral("#BF616A")),
        QColor(QStringLiteral("#A3BE8C")),
        QColor(QStringLiteral("#EBCB8B")),
        QColor(QStringLiteral("#81A1C1")),
        QColor(QStringLiteral("#B48EAD")),
        QColor(QStringLiteral("#8FBCBB")),
        QColor(QStringLiteral("#ECEFF4"))
    };

    if (index >= 0 && index < static_cast<int>(basicColors.size())) {
        return basicColors[static_cast<std::size_t>(index)];
    }

    if (index >= 16 && index <= 231) {
        const int cubeIndex = index - 16;
        const int r = cubeIndex / 36;
        const int g = (cubeIndex / 6) % 6;
        const int b = cubeIndex % 6;
        const auto value = [](int component) {
            return component == 0 ? 0 : 55 + component * 40;
        };
        return QColor(value(r), value(g), value(b));
    }

    if (index >= 232 && index <= 255) {
        const int gray = 8 + (index - 232) * 10;
        return QColor(gray, gray, gray);
    }

    return QColor(QStringLiteral("#ECEFF4"));
}

QString styleToCss(const TerminalStyle &style, bool cursorCell)
{
    QColor foreground = style.defaultForeground ? QColor(QStringLiteral("#ECEFF4")) : style.foreground;
    QColor background = style.defaultBackground ? QColor(QStringLiteral("#121212")) : style.background;

    if (style.inverse) {
        std::swap(foreground, background);
    }

    if (cursorCell) {
        std::swap(foreground, background);
        if (background == QColor(QStringLiteral("#121212"))) {
            background = QColor(QStringLiteral("#88C0D0"));
        }
    }

    QString css = QStringLiteral("color:%1;background-color:%2;")
                      .arg(foreground.name(QColor::HexRgb), background.name(QColor::HexRgb));

    if (style.bold || cursorCell) {
        css += QStringLiteral("font-weight:600;");
    }

    if (style.underline) {
        css += QStringLiteral("text-decoration:underline;");
    }

    return css;
}

int controlCodeForCharacter(QChar character)
{
    const ushort unicode = character.toUpper().unicode();
    if (unicode >= 'A' && unicode <= 'Z') {
        return unicode - '@';
    }

    switch (unicode) {
    case ' ':
        return 0;
    case '[':
        return 27;
    case '\\':
        return 28;
    case ']':
        return 29;
    case '^':
        return 30;
    case '_':
    case '/':
        return 31;
    default:
        return -1;
    }
}

QByteArray keySequenceForKey(int key)
{
    switch (key) {
    case Qt::Key_Return:
    case Qt::Key_Enter:
        return QByteArray("\r");
    case Qt::Key_Backspace:
        return QByteArray(1, 0x7f);
    case Qt::Key_Tab:
        return QByteArray("\t");
    case Qt::Key_Escape:
        return QByteArray(1, kEsc);
    case Qt::Key_Left:
        return QByteArray("\x1b[D");
    case Qt::Key_Right:
        return QByteArray("\x1b[C");
    case Qt::Key_Up:
        return QByteArray("\x1b[A");
    case Qt::Key_Down:
        return QByteArray("\x1b[B");
    case Qt::Key_Home:
        return QByteArray("\x1b[H");
    case Qt::Key_End:
        return QByteArray("\x1b[F");
    case Qt::Key_Delete:
        return QByteArray("\x1b[3~");
    case Qt::Key_PageUp:
        return QByteArray("\x1b[5~");
    case Qt::Key_PageDown:
        return QByteArray("\x1b[6~");
    case Qt::Key_Insert:
        return QByteArray("\x1b[2~");
    default:
        return {};
    }
}

QList<int> parseCsiParams(const QString &body)
{
    const QStringList parts = body.split(';');
    QList<int> values;
    values.reserve(parts.size());

    for (const QString &part : parts) {
        if (part.isEmpty()) {
            values.append(-1);
        } else {
            bool ok = false;
            const int value = part.toInt(&ok);
            values.append(ok ? value : -1);
        }
    }

    if (values.isEmpty()) {
        values.append(-1);
    }

    return values;
}

} // namespace

struct TerminalBackend::ScreenState
{
    QVector<TerminalRow> rows;
    QVector<TerminalRow> scrollback;
    int cursorRow = 0;
    int cursorColumn = 0;
    int savedCursorRow = 0;
    int savedCursorColumn = 0;
    int scrollTop = 0;
    int scrollBottom = 0;
    bool cursorVisible = true;
    bool pendingWrap = false;
};

struct TerminalBackend::TerminalStyleState
{
    TerminalStyle currentStyle = defaultStyle();
};

TerminalBackend::TerminalBackend(QObject *parent)
    : QObject(parent)
    , m_mainScreen(new ScreenState)
    , m_altScreen(new ScreenState)
    , m_styleState(new TerminalStyleState)
    , m_lineModel(new TerminalLineModel(this))
    , m_pollTimer(new QTimer(this))
{
    QSettings settings;
    m_fontPixelSize = std::clamp(settings.value(QStringLiteral("terminal/fontPixelSize"),
                                                kDefaultFontPixelSize).toInt(),
                                 kMinFontPixelSize, kMaxFontPixelSize);

    m_pollTimer->setInterval(500);
    connect(m_pollTimer, &QTimer::timeout, this, &TerminalBackend::pollChildStatus);

    resetScreenState();
    startSession();
}

TerminalBackend::~TerminalBackend()
{
    stopSession();
    delete m_mainScreen;
    delete m_altScreen;
    delete m_styleState;
}

QObject *TerminalBackend::lineModel() const
{
    return m_lineModel;
}

bool TerminalBackend::running() const
{
    return m_running;
}

bool TerminalBackend::connected() const
{
    return m_connected;
}

QString TerminalBackend::title() const
{
    return m_title;
}

QString TerminalBackend::statusText() const
{
    return m_statusText;
}

int TerminalBackend::columns() const
{
    return m_columns;
}

int TerminalBackend::rows() const
{
    return m_rows;
}

int TerminalBackend::cursorRow() const
{
    return m_cursorRow;
}

int TerminalBackend::cursorColumn() const
{
    return m_cursorColumn;
}

int TerminalBackend::fontPixelSize() const
{
    return m_fontPixelSize;
}

int TerminalBackend::minFontPixelSize() const
{
    return kMinFontPixelSize;
}

int TerminalBackend::maxFontPixelSize() const
{
    return kMaxFontPixelSize;
}

void TerminalBackend::setFontPixelSize(int fontPixelSize)
{
    const int clampedFontSize = std::clamp(fontPixelSize, kMinFontPixelSize, kMaxFontPixelSize);
    if (m_fontPixelSize == clampedFontSize) {
        return;
    }

    m_fontPixelSize = clampedFontSize;
    QSettings settings;
    settings.setValue(QStringLiteral("terminal/fontPixelSize"), m_fontPixelSize);
    emit fontPixelSizeChanged();
}

void TerminalBackend::sendText(const QString &text)
{
    if (!m_running || text.isEmpty()) {
        return;
    }

    writeBytes(text.toUtf8());
}

void TerminalBackend::sendCharacter(const QString &text, int modifiers)
{
    if (!m_running || text.isEmpty()) {
        return;
    }

    QByteArray bytes;
    if (modifiers & Qt::AltModifier) {
        bytes.append(kEsc);
    }

    if (modifiers & Qt::ControlModifier) {
        for (const QChar character : text) {
            const int controlCode = controlCodeForCharacter(character);
            if (controlCode >= 0) {
                bytes.append(static_cast<char>(controlCode));
            }
        }
    } else {
        bytes.append(text.toUtf8());
    }

    if (!bytes.isEmpty()) {
        writeBytes(bytes);
    }
}

void TerminalBackend::sendKey(int key, int modifiers)
{
    if (!m_running) {
        return;
    }

    if (modifiers & Qt::ControlModifier) {
        if (key >= Qt::Key_A && key <= Qt::Key_Z) {
            QByteArray bytes;
            if (modifiers & Qt::AltModifier) {
                bytes.append(kEsc);
            }
            bytes.append(static_cast<char>(key - Qt::Key_A + 1));
            writeBytes(bytes);
            return;
        }

        switch (key) {
        case Qt::Key_Space:
        case Qt::Key_BracketLeft:
        case Qt::Key_Backslash:
        case Qt::Key_BracketRight:
        case Qt::Key_AsciiCircum:
        case Qt::Key_Underscore: {
            QByteArray bytes;
            if (modifiers & Qt::AltModifier) {
                bytes.append(kEsc);
            }
            const int controlCode = controlCodeForCharacter(QChar(static_cast<char16_t>(key)));
            if (controlCode >= 0) {
                bytes.append(static_cast<char>(controlCode));
                writeBytes(bytes);
            }
            return;
        }
        default:
            break;
        }
    }

    QByteArray sequence = keySequenceForKey(key);
    if (sequence.isEmpty()) {
        sendCharacter(QString(QChar(static_cast<char16_t>(key))), modifiers);
        return;
    }

    if (modifiers & Qt::AltModifier) {
        sequence.prepend(kEsc);
    }

    writeBytes(sequence);
}

void TerminalBackend::resizeTerminal(int columns, int rows)
{
    columns = std::max(20, columns);
    rows = std::max(8, rows);

    if (m_columns == columns && m_rows == rows) {
        return;
    }

    auto resizeScreen = [this, columns, rows](ScreenState *screen, bool preserveScrollback) {
        auto appendScrollbackRow = [this, screen, preserveScrollback](const TerminalRow &row) {
            if (!preserveScrollback) {
                return;
            }

            screen->scrollback.append(row);
            if (screen->scrollback.size() > m_maxScrollback) {
                screen->scrollback.removeFirst();
            }
        };

        const int oldRows = screen->rows.size();
        for (TerminalRow &row : screen->rows) {
            if (row.size() < columns) {
                const int missing = columns - row.size();
                for (int i = 0; i < missing; ++i) {
                    row.append(blankCell());
                }
            } else if (row.size() > columns) {
                row.resize(columns);
            }
        }

        if (oldRows < rows) {
            for (int i = 0; i < rows - oldRows; ++i) {
                screen->rows.append(blankRow(columns));
            }
        } else if (oldRows > rows) {
            while (screen->rows.size() > rows) {
                appendScrollbackRow(screen->rows.takeFirst());
            }
        }

        if (screen->rows.isEmpty()) {
            for (int i = 0; i < rows; ++i) {
                screen->rows.append(blankRow(columns));
            }
        }

        screen->cursorRow = std::clamp(screen->cursorRow, 0, rows - 1);
        screen->cursorColumn = std::clamp(screen->cursorColumn, 0, columns - 1);
        screen->savedCursorRow = std::clamp(screen->savedCursorRow, 0, rows - 1);
        screen->savedCursorColumn = std::clamp(screen->savedCursorColumn, 0, columns - 1);
        screen->scrollTop = std::clamp(screen->scrollTop, 0, rows - 1);
        screen->scrollBottom = std::clamp(screen->scrollBottom, screen->scrollTop, rows - 1);
        screen->pendingWrap = false;
    };

    m_columns = columns;
    m_rows = rows;
    resizeScreen(m_mainScreen, true);
    resizeScreen(m_altScreen, false);

    if (m_masterFd >= 0) {
        struct winsize size;
        size.ws_col = static_cast<unsigned short>(m_columns);
        size.ws_row = static_cast<unsigned short>(m_rows);
        size.ws_xpixel = 0;
        size.ws_ypixel = 0;
        ioctl(m_masterFd, TIOCSWINSZ, &size);
        if (m_childPid > 0) {
            kill(static_cast<pid_t>(m_childPid), SIGWINCH);
        }
    }

    markScreenDirty();
    emit sizeChanged();
}

void TerminalBackend::resetTerminal()
{
    stopSession(true);
}

void TerminalBackend::clearTerminal()
{
    clearActiveScreen(true);
    markScreenDirty();
}

void TerminalBackend::clearScrollback()
{
    m_mainScreen->scrollback.clear();
    m_altScreen->scrollback.clear();
    markScreenDirty();
}

void TerminalBackend::copySelection(int startRow, int startCol, int endRow, int endCol)
{
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard) {
        return;
    }

    clipboard->setText(selectionText(startRow, startCol, endRow, endCol));
}

void TerminalBackend::pasteFromClipboard()
{
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (!clipboard) {
        return;
    }

    QString text = clipboard->text();
    if (text.isEmpty()) {
        return;
    }

    text.replace(QStringLiteral("\r\n"), QStringLiteral("\n"));
    text.replace(QChar('\r'), QChar('\n'));

    QByteArray bytes;
    if (m_bracketedPasteMode) {
        bytes += QByteArrayLiteral("\x1b[200~");
        bytes += text.toUtf8();
        bytes += QByteArrayLiteral("\x1b[201~");
    } else {
        if (text.contains(QChar('\n'))) {
            while (text.endsWith(QChar('\n'))) {
                text.chop(1);
            }
        }
        bytes = text.toUtf8();
    }

    writeBytes(bytes);
}

void TerminalBackend::handleReadyRead()
{
    if (m_masterFd < 0) {
        return;
    }

    QByteArray bytes;
    char buffer[4096];

    while (true) {
        const ssize_t readCount = ::read(m_masterFd, buffer, sizeof(buffer));
        if (readCount > 0) {
            bytes.append(buffer, static_cast<int>(readCount));
            continue;
        }

        if (readCount == 0) {
            break;
        }

        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            break;
        }

        if (errno == EIO) {
            break;
        }

        break;
    }

    if (!bytes.isEmpty()) {
        processBytes(bytes);
        markScreenDirty();
    }

    pollChildStatus();
}

void TerminalBackend::pollChildStatus()
{
    if (m_childPid <= 0) {
        return;
    }

    int status = 0;
    const pid_t result = waitpid(static_cast<pid_t>(m_childPid), &status, WNOHANG);
    if (result <= 0) {
        return;
    }

    m_childPid = -1;
    updateStateAfterChildExit(status);
}

void TerminalBackend::startSession()
{
    resetScreenState();

    const QString shellPath = resolveShellPath();
    const QByteArray shellBytes = shellPath.toLocal8Bit();
    const QByteArray shellName = QFileInfo(shellPath).fileName().toLocal8Bit();
    const QByteArray homeEnv = qEnvironmentVariable("HOME", QStringLiteral("/root")).toLocal8Bit();
    const QByteArray userEnv = qEnvironmentVariable("USER", QStringLiteral("root")).toLocal8Bit();
    const QByteArray langEnv = qEnvironmentVariable("LANG", QStringLiteral("C.UTF-8")).toLocal8Bit();

    struct winsize size;
    size.ws_col = static_cast<unsigned short>(m_columns);
    size.ws_row = static_cast<unsigned short>(m_rows);
    size.ws_xpixel = 0;
    size.ws_ypixel = 0;

    int masterFd = -1;
    const pid_t childPid = forkpty(&masterFd, nullptr, nullptr, &size);
    if (childPid < 0) {
        m_statusText = QStringLiteral("Failed to start shell: %1")
                           .arg(QString::fromLocal8Bit(std::strerror(errno)));
        emit statusChanged();
        return;
    }

    if (childPid == 0) {
        ::setenv("TERM", "xterm-256color", 1);
        ::setenv("COLORTERM", "truecolor", 1);
        ::setenv("SHELL", shellBytes.constData(), 1);
        ::setenv("HOME", homeEnv.constData(), 1);
        ::setenv("USER", userEnv.constData(), 1);
        ::setenv("LOGNAME", userEnv.constData(), 1);
        ::setenv("LANG", langEnv.constData(), 1);

        if (::chdir("/root") != 0) {
            ::chdir("/");
        }

        ::execl(shellBytes.constData(), shellName.constData(), "-i", static_cast<char *>(nullptr));
        _exit(127);
    }

    m_masterFd = masterFd;
    m_childPid = childPid;

    const int flags = fcntl(m_masterFd, F_GETFL);
    if (flags >= 0) {
        fcntl(m_masterFd, F_SETFL, flags | O_NONBLOCK);
    }

    if (m_notifier) {
        m_notifier->deleteLater();
    }

    m_notifier = new QSocketNotifier(m_masterFd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &TerminalBackend::handleReadyRead);

    m_running = true;
    m_connected = true;
    m_statusText = QStringLiteral("%1 shell is running")
                       .arg(QString::fromLocal8Bit(userEnv));
    setTitle(QFileInfo(shellPath).fileName());
    m_pollTimer->start();

    emit runningChanged();
    emit connectedChanged();
    emit statusChanged();
    markScreenDirty();
}

void TerminalBackend::stopSession(bool restart)
{
    m_pollTimer->stop();

    if (m_notifier) {
        m_notifier->deleteLater();
        m_notifier = nullptr;
    }

    if (m_masterFd >= 0) {
        ::close(m_masterFd);
        m_masterFd = -1;
    }

    if (m_childPid > 0) {
        ::kill(static_cast<pid_t>(m_childPid), SIGHUP);

        int status = 0;
        bool exited = false;
        for (int attempt = 0; attempt < 10; ++attempt) {
            const pid_t result = waitpid(static_cast<pid_t>(m_childPid), &status, WNOHANG);
            if (result == static_cast<pid_t>(m_childPid)) {
                exited = true;
                break;
            }

            usleep(25000);
        }

        if (!exited) {
            ::kill(static_cast<pid_t>(m_childPid), SIGKILL);
            waitpid(static_cast<pid_t>(m_childPid), &status, 0);
        }
    }

    m_childPid = -1;
    m_running = false;
    m_connected = false;
    emit runningChanged();
    emit connectedChanged();

    if (restart) {
        startSession();
    } else {
        m_statusText = QStringLiteral("Shell stopped");
        emit statusChanged();
    }
}

void TerminalBackend::updateStateAfterChildExit(int exitStatus)
{
    if (m_notifier) {
        m_notifier->deleteLater();
        m_notifier = nullptr;
    }

    if (m_masterFd >= 0) {
        ::close(m_masterFd);
        m_masterFd = -1;
    }

    m_pollTimer->stop();
    m_running = false;
    m_connected = false;

    if (WIFEXITED(exitStatus)) {
        m_statusText = QStringLiteral("Shell exited (%1)").arg(WEXITSTATUS(exitStatus));
    } else if (WIFSIGNALED(exitStatus)) {
        m_statusText = QStringLiteral("Shell terminated by signal %1").arg(WTERMSIG(exitStatus));
    } else {
        m_statusText = QStringLiteral("Shell disconnected");
    }

    emit runningChanged();
    emit connectedChanged();
    emit statusChanged();
}

void TerminalBackend::processBytes(const QByteArray &data)
{
    for (const unsigned char byte : data) {
        switch (m_parserState) {
        case ParserState::Normal:
            if (m_expectedUtf8Bytes > 0 || byte >= 0x80) {
                handleUtf8Byte(byte);
                break;
            }

            switch (byte) {
            case 0x00:
            case '\a':
                break;
            case 0x0e:
                m_shiftOut = true;
                break;
            case 0x0f:
                m_shiftOut = false;
                break;
            case '\b':
                backspace();
                break;
            case '\t':
                tab();
                break;
            case '\n':
                lineFeed();
                break;
            case '\r':
                carriageReturn();
                break;
            case 0x0c:
                clearActiveScreen(false);
                break;
            case kEsc:
                flushPendingUtf8();
                m_parserState = ParserState::Escape;
                break;
            default:
                if (byte >= 0x20) {
                    putCharacter(QString(QChar(byte)));
                }
                break;
            }
            break;
        case ParserState::Escape:
            if (byte == '[') {
                m_csiBuffer.clear();
                m_parserState = ParserState::Csi;
            } else if (byte == ']') {
                m_oscBuffer.clear();
                m_parserState = ParserState::Osc;
            } else if (byte == '(' || byte == ')') {
                m_charsetTarget = static_cast<char>(byte);
                m_parserState = ParserState::Charset;
            } else {
                switch (byte) {
                case '7':
                    saveCursor();
                    break;
                case '8':
                    restoreCursor();
                    break;
                case 'D':
                    lineFeed();
                    break;
                case 'E':
                    lineFeed();
                    carriageReturn();
                    break;
                case 'M':
                    reverseIndex();
                    break;
                case 'c':
                    resetScreenState();
                    break;
                default:
                    break;
                }
                m_parserState = ParserState::Normal;
            }
            break;
        case ParserState::Charset: {
            const bool specialGraphics = byte == '0';
            if (m_charsetTarget == '(') {
                m_g0SpecialGraphics = specialGraphics;
            } else if (m_charsetTarget == ')') {
                m_g1SpecialGraphics = specialGraphics;
            }
            m_charsetTarget = 0;
            m_parserState = ParserState::Normal;
            break;
        }
        case ParserState::Csi:
            m_csiBuffer.append(static_cast<char>(byte));
            if (byte >= 0x40 && byte <= 0x7e) {
                handleCsiSequence(m_csiBuffer);
                m_csiBuffer.clear();
                m_parserState = ParserState::Normal;
            }
            break;
        case ParserState::Osc:
            if (byte == '\a') {
                handleOscSequence(m_oscBuffer);
                m_oscBuffer.clear();
                m_parserState = ParserState::Normal;
            } else if (byte == kEsc) {
                m_parserState = ParserState::OscEscape;
            } else {
                m_oscBuffer.append(static_cast<char>(byte));
            }
            break;
        case ParserState::OscEscape:
            if (byte == '\\') {
                handleOscSequence(m_oscBuffer);
                m_oscBuffer.clear();
                m_parserState = ParserState::Normal;
            } else {
                m_oscBuffer.append(kEsc);
                m_oscBuffer.append(static_cast<char>(byte));
                m_parserState = ParserState::Osc;
            }
            break;
        }
    }

    flushPendingUtf8();
}

void TerminalBackend::writeBytes(const QByteArray &bytes)
{
    if (m_masterFd < 0 || bytes.isEmpty()) {
        return;
    }

    qsizetype written = 0;
    while (written < bytes.size()) {
        const ssize_t result = ::write(m_masterFd, bytes.constData() + written, bytes.size() - written);
        if (result < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        written += result;
    }
}

void TerminalBackend::rebuildLinesCache()
{
    if (!m_linesDirty) {
        return;
    }

    ScreenState *screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
    QStringList renderedLines;
    renderedLines.reserve(screen->scrollback.size() + screen->rows.size());

    auto appendRows = [this, screen, &renderedLines](const QVector<TerminalRow> &rows, bool includeCursor) {
        for (int rowIndex = 0; rowIndex < rows.size(); ++rowIndex) {
            const TerminalRow &row = rows[rowIndex];
            const bool isCursorRow = includeCursor && screen->cursorVisible && rowIndex == screen->cursorRow;
            int lastUsedColumn = -1;

            for (int column = 0; column < row.size(); ++column) {
                if (isDisplayCell(row[column])) {
                    lastUsedColumn = column;
                }
            }

            if (isCursorRow) {
                lastUsedColumn = std::max(lastUsedColumn, std::min(screen->cursorColumn, m_columns - 1));
            }

            if (lastUsedColumn < 0) {
                renderedLines.append(QStringLiteral("&nbsp;"));
                continue;
            }

            QString html;
            int column = 0;
            while (column <= lastUsedColumn && column < row.size()) {
                const bool cursorCell = isCursorRow && column == screen->cursorColumn;
                const TerminalStyle style = row[column].style;
                QString text = row[column].text;
                ++column;

                while (column <= lastUsedColumn && column < row.size()) {
                    const bool nextCursorCell = isCursorRow && column == screen->cursorColumn;
                    if (row[column].style == style && nextCursorCell == cursorCell) {
                        text += row[column].text;
                        ++column;
                    } else {
                        break;
                    }
                }

                html += QStringLiteral("<span style=\"%1\">%2</span>")
                            .arg(styleToCss(style, cursorCell), encodeHtmlText(text));
            }

            renderedLines.append(html.isEmpty() ? QStringLiteral("&nbsp;") : html);
        }
    };

    if (!m_useAlternateScreen) {
        appendRows(screen->scrollback, false);
    }
    appendRows(screen->rows, true);

    m_lineModel->replaceLines(renderedLines);
    m_cursorRow = (m_useAlternateScreen ? 0 : screen->scrollback.size()) + screen->cursorRow;
    m_cursorColumn = screen->cursorColumn;
    m_linesDirty = false;

    emit cursorChanged();
    emit screenChanged();
}

void TerminalBackend::clearActiveScreen(bool clearScrollback)
{
    ScreenState *screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
    screen->rows.clear();
    for (int row = 0; row < m_rows; ++row) {
        screen->rows.append(blankRow(m_columns));
    }

    if (clearScrollback) {
        screen->scrollback.clear();
    }

    screen->cursorRow = 0;
    screen->cursorColumn = 0;
    screen->pendingWrap = false;
}

void TerminalBackend::markScreenDirty()
{
    m_linesDirty = true;
    rebuildLinesCache();
}

void TerminalBackend::handleUtf8Byte(unsigned char byte)
{
    auto resetUtf8State = [this]() {
        m_utf8Buffer.clear();
        m_expectedUtf8Bytes = 0;
    };

    if (m_utf8Buffer.isEmpty()) {
        if ((byte & 0xe0) == 0xc0) {
            m_expectedUtf8Bytes = 2;
        } else if ((byte & 0xf0) == 0xe0) {
            m_expectedUtf8Bytes = 3;
        } else if ((byte & 0xf8) == 0xf0) {
            m_expectedUtf8Bytes = 4;
        } else {
            putCharacter(QString(QChar(0xfffd)));
            resetUtf8State();
            return;
        }
    }

    m_utf8Buffer.append(static_cast<char>(byte));
    if (m_utf8Buffer.size() < m_expectedUtf8Bytes) {
        return;
    }

    const QString decoded = QString::fromUtf8(m_utf8Buffer);
    if (decoded.isEmpty()) {
        putCharacter(QString(QChar(0xfffd)));
    } else {
        putText(decoded);
    }

    resetUtf8State();
}

void TerminalBackend::flushPendingUtf8()
{
    if (m_utf8Buffer.isEmpty()) {
        return;
    }

    const QString decoded = QString::fromUtf8(m_utf8Buffer);
    if (!decoded.isEmpty()) {
        putText(decoded);
    }
    m_utf8Buffer.clear();
    m_expectedUtf8Bytes = 0;
}

void TerminalBackend::putText(const QString &text)
{
    for (const QChar character : text) {
        putCharacter(QString(character));
    }
}

void TerminalBackend::putCharacter(const QString &text)
{
    ScreenState *screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
    if (screen->pendingWrap) {
        lineFeed();
        carriageReturn();
        screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
        screen->pendingWrap = false;
    }

    const bool specialGraphics = m_shiftOut ? m_g1SpecialGraphics : m_g0SpecialGraphics;
    QString renderedText = text;
    if (specialGraphics && !renderedText.isEmpty()) {
        renderedText[0] = mapDecSpecialGraphics(renderedText[0]);
    }

    TerminalCell &cell = screen->rows[screen->cursorRow][screen->cursorColumn];
    cell.text = renderedText;
    cell.style = m_styleState->currentStyle;

    if (screen->cursorColumn >= m_columns - 1) {
        screen->cursorColumn = m_columns - 1;
        screen->pendingWrap = true;
    } else {
        ++screen->cursorColumn;
        screen->pendingWrap = false;
    }
}

void TerminalBackend::lineFeed()
{
    ScreenState *screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
    screen->pendingWrap = false;

    if (!m_useAlternateScreen) {
        if (screen->cursorRow >= m_rows - 1) {
            screen->scrollback.append(screen->rows.takeFirst());
            if (screen->scrollback.size() > m_maxScrollback) {
                screen->scrollback.removeFirst();
            }
            screen->rows.append(blankRow(m_columns));
            screen->cursorRow = m_rows - 1;
        } else {
            ++screen->cursorRow;
        }
        return;
    }

    if (screen->cursorRow == screen->scrollBottom) {
        screen->rows.removeAt(screen->scrollTop);
        screen->rows.insert(screen->scrollBottom, blankRow(m_columns));
        return;
    }

    if (screen->cursorRow < m_rows - 1) {
        ++screen->cursorRow;
    }
}

void TerminalBackend::reverseIndex()
{
    ScreenState *screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
    screen->pendingWrap = false;

    if (!m_useAlternateScreen) {
        if (screen->cursorRow > 0) {
            --screen->cursorRow;
        } else {
            screen->scrollback.prepend(blankRow(m_columns));
            if (screen->scrollback.size() > m_maxScrollback) {
                screen->scrollback.removeLast();
            }
        }
        return;
    }

    if (screen->cursorRow == screen->scrollTop) {
        screen->rows.removeAt(screen->scrollBottom);
        screen->rows.insert(screen->scrollTop, blankRow(m_columns));
    } else if (screen->cursorRow > 0) {
        --screen->cursorRow;
    }
}

void TerminalBackend::carriageReturn()
{
    ScreenState *screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
    screen->cursorColumn = 0;
    screen->pendingWrap = false;
}

void TerminalBackend::backspace()
{
    ScreenState *screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
    screen->cursorColumn = std::max(0, screen->cursorColumn - 1);
    screen->pendingWrap = false;
}

void TerminalBackend::tab()
{
    ScreenState *screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
    const int nextTabStop = ((screen->cursorColumn / kTabWidth) + 1) * kTabWidth;
    screen->cursorColumn = std::min(nextTabStop, m_columns - 1);
    screen->pendingWrap = false;
}

void TerminalBackend::saveCursor()
{
    ScreenState *screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
    screen->savedCursorRow = screen->cursorRow;
    screen->savedCursorColumn = screen->cursorColumn;
}

void TerminalBackend::restoreCursor()
{
    ScreenState *screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
    screen->cursorRow = std::clamp(screen->savedCursorRow, 0, m_rows - 1);
    screen->cursorColumn = std::clamp(screen->savedCursorColumn, 0, m_columns - 1);
}

void TerminalBackend::resetParserState()
{
    m_parserState = ParserState::Normal;
    m_csiBuffer.clear();
    m_oscBuffer.clear();
    m_utf8Buffer.clear();
    m_expectedUtf8Bytes = 0;
    m_charsetTarget = 0;
}

void TerminalBackend::resetScreenState()
{
    auto resetScreen = [this](ScreenState *screen) {
        screen->rows.clear();
        screen->scrollback.clear();
        for (int row = 0; row < m_rows; ++row) {
            screen->rows.append(blankRow(m_columns));
        }
        screen->cursorRow = 0;
        screen->cursorColumn = 0;
        screen->savedCursorRow = 0;
        screen->savedCursorColumn = 0;
        screen->scrollTop = 0;
        screen->scrollBottom = m_rows - 1;
        screen->cursorVisible = true;
        screen->pendingWrap = false;
    };

    resetScreen(m_mainScreen);
    resetScreen(m_altScreen);
    m_useAlternateScreen = false;
    m_styleState->currentStyle = defaultStyle();
    resetParserState();
    m_g0SpecialGraphics = false;
    m_g1SpecialGraphics = false;
    m_shiftOut = false;
    m_savedMainCursorRow = 0;
    m_savedMainCursorColumn = 0;
    m_bracketedPasteMode = false;
    m_linesDirty = true;
}

void TerminalBackend::setTitle(const QString &title)
{
    const QString effectiveTitle = title.isEmpty() ? QStringLiteral("Terminal") : title;
    if (m_title == effectiveTitle) {
        return;
    }

    m_title = effectiveTitle;
    emit titleChanged();
}

void TerminalBackend::handleCsiSequence(const QByteArray &sequence)
{
    if (sequence.isEmpty()) {
        return;
    }

    ScreenState *screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
    const QChar final = QChar::fromLatin1(sequence.back());
    QString body = QString::fromLatin1(sequence.left(sequence.size() - 1));
    const bool privateMode = body.startsWith('?');
    if (privateMode) {
        body.remove(0, 1);
    }

    const QList<int> params = parseCsiParams(body);
    auto paramValue = [&params](int index, int defaultValue) {
        if (index < 0 || index >= params.size() || params[index] < 0) {
            return defaultValue;
        }
        return params[index];
    };

    switch (final.unicode()) {
    case 'A':
        screen->cursorRow = std::max(0, screen->cursorRow - paramValue(0, 1));
        screen->pendingWrap = false;
        break;
    case 'B':
        screen->cursorRow = std::min(m_rows - 1, screen->cursorRow + paramValue(0, 1));
        screen->pendingWrap = false;
        break;
    case 'C':
        screen->cursorColumn = std::min(m_columns - 1, screen->cursorColumn + paramValue(0, 1));
        screen->pendingWrap = false;
        break;
    case 'D':
        screen->cursorColumn = std::max(0, screen->cursorColumn - paramValue(0, 1));
        screen->pendingWrap = false;
        break;
    case 'E':
        screen->cursorRow = std::min(m_rows - 1, screen->cursorRow + paramValue(0, 1));
        screen->cursorColumn = 0;
        screen->pendingWrap = false;
        break;
    case 'F':
        screen->cursorRow = std::max(0, screen->cursorRow - paramValue(0, 1));
        screen->cursorColumn = 0;
        screen->pendingWrap = false;
        break;
    case 'G':
        screen->cursorColumn = std::clamp(paramValue(0, 1) - 1, 0, m_columns - 1);
        screen->pendingWrap = false;
        break;
    case 'H':
    case 'f':
        screen->cursorRow = std::clamp(paramValue(0, 1) - 1, 0, m_rows - 1);
        screen->cursorColumn = std::clamp(paramValue(1, 1) - 1, 0, m_columns - 1);
        screen->pendingWrap = false;
        break;
    case 'a':
        screen->cursorColumn = std::min(m_columns - 1, screen->cursorColumn + paramValue(0, 1));
        screen->pendingWrap = false;
        break;
    case 'd':
        screen->cursorRow = std::clamp(paramValue(0, 1) - 1, 0, m_rows - 1);
        screen->pendingWrap = false;
        break;
    case 'e':
        screen->cursorRow = std::min(m_rows - 1, screen->cursorRow + paramValue(0, 1));
        screen->pendingWrap = false;
        break;
    case '`':
        screen->cursorColumn = std::clamp(paramValue(0, 1) - 1, 0, m_columns - 1);
        screen->pendingWrap = false;
        break;
    case 'J': {
        const int mode = paramValue(0, 0);
        if (mode == 2 || mode == 3) {
            const int cursorRow = screen->cursorRow;
            const int cursorColumn = screen->cursorColumn;
            clearActiveScreen(mode == 3);
            screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
            screen->cursorRow = cursorRow;
            screen->cursorColumn = cursorColumn;
        } else {
            const int startRow = mode == 1 ? 0 : screen->cursorRow;
            const int endRow = mode == 1 ? screen->cursorRow : m_rows - 1;
            for (int row = startRow; row <= endRow; ++row) {
                int startCol = 0;
                int endCol = m_columns - 1;
                if (row == screen->cursorRow) {
                    if (mode == 0) {
                        startCol = screen->cursorColumn;
                    } else if (mode == 1) {
                        endCol = screen->cursorColumn;
                    }
                }
                for (int col = startCol; col <= endCol; ++col) {
                    screen->rows[row][col] = blankCell();
                }
            }
        }
        screen->pendingWrap = false;
        break;
    }
    case 'K': {
        const int mode = paramValue(0, 0);
        int startCol = 0;
        int endCol = m_columns - 1;
        if (mode == 0) {
            startCol = screen->cursorColumn;
        } else if (mode == 1) {
            endCol = screen->cursorColumn;
        }
        for (int col = startCol; col <= endCol; ++col) {
            screen->rows[screen->cursorRow][col] = blankCell();
        }
        screen->pendingWrap = false;
        break;
    }
    case 'L': {
        const int count = std::max(1, paramValue(0, 1));
        for (int i = 0; i < count; ++i) {
            screen->rows.insert(screen->cursorRow, blankRow(m_columns));
            screen->rows.removeAt(screen->scrollBottom + 1);
        }
        screen->pendingWrap = false;
        break;
    }
    case 'M': {
        const int count = std::max(1, paramValue(0, 1));
        for (int i = 0; i < count; ++i) {
            screen->rows.removeAt(screen->cursorRow);
            screen->rows.insert(screen->scrollBottom, blankRow(m_columns));
        }
        screen->pendingWrap = false;
        break;
    }
    case '@': {
        const int count = std::max(1, paramValue(0, 1));
        TerminalRow &row = screen->rows[screen->cursorRow];
        for (int i = 0; i < count; ++i) {
            row.insert(screen->cursorColumn, blankCell());
            row.removeLast();
        }
        screen->pendingWrap = false;
        break;
    }
    case 'P': {
        const int count = std::max(1, paramValue(0, 1));
        TerminalRow &row = screen->rows[screen->cursorRow];
        for (int i = 0; i < count; ++i) {
            row.removeAt(screen->cursorColumn);
            row.append(blankCell());
        }
        screen->pendingWrap = false;
        break;
    }
    case 'S': {
        const int count = std::max(1, paramValue(0, 1));
        for (int i = 0; i < count; ++i) {
            if (!screen->rows.isEmpty() && screen->scrollTop <= screen->scrollBottom) {
                const bool fullScreenRegion = screen->scrollTop == 0 && screen->scrollBottom == m_rows - 1;
                if (!m_useAlternateScreen && fullScreenRegion) {
                    screen->scrollback.append(screen->rows.takeFirst());
                    if (screen->scrollback.size() > m_maxScrollback) {
                        screen->scrollback.removeFirst();
                    }
                    screen->rows.append(blankRow(m_columns));
                } else {
                    screen->rows.removeAt(screen->scrollTop);
                    screen->rows.insert(screen->scrollBottom, blankRow(m_columns));
                }
            }
        }
        screen->pendingWrap = false;
        break;
    }
    case 'T': {
        const int count = std::max(1, paramValue(0, 1));
        for (int i = 0; i < count; ++i) {
            screen->rows.removeAt(screen->scrollBottom);
            screen->rows.insert(screen->scrollTop, blankRow(m_columns));
        }
        screen->pendingWrap = false;
        break;
    }
    case 'X': {
        const int count = std::max(1, paramValue(0, 1));
        for (int i = 0; i < count && screen->cursorColumn + i < m_columns; ++i) {
            screen->rows[screen->cursorRow][screen->cursorColumn + i] = blankCell();
        }
        screen->pendingWrap = false;
        break;
    }
    case 'r': {
        if (m_useAlternateScreen) {
            const int top = std::clamp(paramValue(0, 1) - 1, 0, m_rows - 1);
            const int bottom = std::clamp(paramValue(1, m_rows) - 1, 0, m_rows - 1);
            if (top < bottom) {
                screen->scrollTop = top;
                screen->scrollBottom = bottom;
            } else {
                screen->scrollTop = 0;
                screen->scrollBottom = m_rows - 1;
            }
        } else {
            screen->scrollTop = 0;
            screen->scrollBottom = m_rows - 1;
        }
        screen->cursorRow = 0;
        screen->cursorColumn = 0;
        screen->pendingWrap = false;
        break;
    }
    case 'm':
        applySgrParameters(params);
        break;
    case 's':
        saveCursor();
        break;
    case 'u':
        restoreCursor();
        break;
    case 'h':
    case 'l':
        if (privateMode) {
            for (const int mode : params) {
                if (mode > 0) {
                    setPrivateMode(mode, final == QLatin1Char('h'));
                }
            }
        }
        break;
    default:
        break;
    }
}

void TerminalBackend::handleOscSequence(const QByteArray &sequence)
{
    const QString osc = QString::fromUtf8(sequence);
    const int separator = osc.indexOf(';');
    if (separator < 0) {
        return;
    }

    const QString key = osc.left(separator);
    const QString value = osc.mid(separator + 1);
    if (key == QStringLiteral("0") || key == QStringLiteral("2")) {
        setTitle(value);
    }
}

void TerminalBackend::applySgrParameters(const QList<int> &params)
{
    auto applyColor = [&params](int &index, bool &isDefault, QColor &color) {
        if (index + 1 >= params.size()) {
            return;
        }

        if (params[index + 1] == 5 && index + 2 < params.size()) {
            color = colorFromIndex(params[index + 2]);
            isDefault = false;
            index += 2;
        } else if (params[index + 1] == 2 && index + 4 < params.size()) {
            color = QColor(params[index + 2], params[index + 3], params[index + 4]);
            isDefault = false;
            index += 4;
        }
    };

    if (params.size() == 1 && params[0] < 0) {
        m_styleState->currentStyle = defaultStyle();
        return;
    }

    for (int index = 0; index < params.size(); ++index) {
        const int value = params[index] < 0 ? 0 : params[index];
        switch (value) {
        case 0:
            m_styleState->currentStyle = defaultStyle();
            break;
        case 1:
            m_styleState->currentStyle.bold = true;
            break;
        case 4:
            m_styleState->currentStyle.underline = true;
            break;
        case 22:
            m_styleState->currentStyle.bold = false;
            break;
        case 24:
            m_styleState->currentStyle.underline = false;
            break;
        case 7:
            m_styleState->currentStyle.inverse = true;
            break;
        case 27:
            m_styleState->currentStyle.inverse = false;
            break;
        case 39:
            m_styleState->currentStyle.foreground = defaultStyle().foreground;
            m_styleState->currentStyle.defaultForeground = true;
            break;
        case 49:
            m_styleState->currentStyle.background = defaultStyle().background;
            m_styleState->currentStyle.defaultBackground = true;
            break;
        default:
            if (value >= 30 && value <= 37) {
                m_styleState->currentStyle.foreground = colorFromIndex(value - 30);
                m_styleState->currentStyle.defaultForeground = false;
            } else if (value >= 90 && value <= 97) {
                m_styleState->currentStyle.foreground = colorFromIndex(value - 90 + 8);
                m_styleState->currentStyle.defaultForeground = false;
            } else if (value >= 40 && value <= 47) {
                m_styleState->currentStyle.background = colorFromIndex(value - 40);
                m_styleState->currentStyle.defaultBackground = false;
            } else if (value >= 100 && value <= 107) {
                m_styleState->currentStyle.background = colorFromIndex(value - 100 + 8);
                m_styleState->currentStyle.defaultBackground = false;
            } else if (value == 38) {
                applyColor(index, m_styleState->currentStyle.defaultForeground,
                           m_styleState->currentStyle.foreground);
            } else if (value == 48) {
                applyColor(index, m_styleState->currentStyle.defaultBackground,
                           m_styleState->currentStyle.background);
            }
            break;
        }
    }
}

void TerminalBackend::setPrivateMode(int mode, bool enabled)
{
    ScreenState *screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
    switch (mode) {
    case 25:
        screen->cursorVisible = enabled;
        break;
    case 2004:
        m_bracketedPasteMode = enabled;
        break;
    case 1049:
        if (enabled) {
            m_savedMainCursorRow = m_mainScreen->cursorRow;
            m_savedMainCursorColumn = m_mainScreen->cursorColumn;
            m_useAlternateScreen = true;
            clearActiveScreen(false);
            m_altScreen->savedCursorRow = 0;
            m_altScreen->savedCursorColumn = 0;
        } else {
            m_useAlternateScreen = false;
            m_mainScreen->cursorRow = std::clamp(m_savedMainCursorRow, 0, m_rows - 1);
            m_mainScreen->cursorColumn = std::clamp(m_savedMainCursorColumn, 0, m_columns - 1);
        }
        break;
    default:
        break;
    }
}

QString TerminalBackend::resolveShellPath() const
{
    const QString envShell = qEnvironmentVariable("SHELL");
    if (!envShell.isEmpty() && QFileInfo::exists(envShell)) {
        return envShell;
    }

    if (QFileInfo::exists(QStringLiteral("/bin/bash"))) {
        return QStringLiteral("/bin/bash");
    }

    return QStringLiteral("/bin/sh");
}

QString TerminalBackend::selectionText(int startRow, int startCol, int endRow, int endCol) const
{
    ScreenState *screen = m_useAlternateScreen ? m_altScreen : m_mainScreen;
    QVector<TerminalRow> allRows = screen->scrollback;
    allRows += screen->rows;

    if (allRows.isEmpty()) {
        return {};
    }

    const int maxRow = static_cast<int>(allRows.size()) - 1;
    startRow = std::clamp(startRow, 0, maxRow);
    endRow = std::clamp(endRow, 0, maxRow);

    if (startRow > endRow || (startRow == endRow && startCol > endCol)) {
        std::swap(startRow, endRow);
        std::swap(startCol, endCol);
    }

    QStringList copiedLines;
    for (int rowIndex = startRow; rowIndex <= endRow; ++rowIndex) {
        const TerminalRow &row = allRows[rowIndex];
        const int rowSize = static_cast<int>(row.size());
        int from = rowIndex == startRow ? std::max(0, startCol) : 0;
        int to = rowIndex == endRow ? std::min(endCol, rowSize) : rowSize;
        if (from >= to) {
            copiedLines.append(QString());
            continue;
        }

        QString text;
        for (int column = from; column < to; ++column) {
            text += row[column].text;
        }

        while (text.endsWith(QLatin1Char(' '))) {
            text.chop(1);
        }
        copiedLines.append(text);
    }

    return copiedLines.join(QLatin1Char('\n'));
}
