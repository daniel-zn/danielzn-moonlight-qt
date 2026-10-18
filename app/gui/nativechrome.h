#pragma once

#include <QByteArray>
#include <QObject>
#include <QString>
#include <QStringList>

class QQuickWindow;
class QQmlEngine;
class QWindow;

// Native window chrome for platforms that have it (macOS): a system toolbar
// with SF Symbol buttons and a translucent Liquid Glass window background.
// Elsewhere `enabled` is false and QML keeps drawing its own toolbar.
class NativeChrome : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool enabled READ isEnabled CONSTANT)
    Q_PROPERTY(bool canGoBack READ canGoBack WRITE setCanGoBack NOTIFY canGoBackChanged)
    Q_PROPERTY(bool showAddPc READ showAddPc WRITE setShowAddPc NOTIFY showAddPcChanged)
    Q_PROPERTY(bool showHelp READ showHelp WRITE setShowHelp NOTIFY showHelpChanged)
    Q_PROPERTY(bool showSettings READ showSettings WRITE setShowSettings NOTIFY showSettingsChanged)
    // Settings is showing: the gear is drawn filled, and clicking it closes Settings
    Q_PROPERTY(bool settingsOpen READ settingsOpen WRITE setSettingsOpen NOTIFY settingsOpenChanged)
    Q_PROPERTY(QString updateText READ updateText WRITE setUpdateText NOTIFY updateTextChanged)

public:
    explicit NativeChrome(QObject* parent = nullptr);
    ~NativeChrome() override;

    // Also registers the "sfsymbol" image provider where supported
    static void registerTypes(QQmlEngine* engine);

    bool isEnabled() const;

    bool canGoBack() const { return m_CanGoBack; }
    void setCanGoBack(bool canGoBack);
    bool showAddPc() const { return m_ShowAddPc; }
    void setShowAddPc(bool show);
    bool showHelp() const { return m_ShowHelp; }
    void setShowHelp(bool show);
    bool showSettings() const { return m_ShowSettings; }
    void setShowSettings(bool show);
    bool settingsOpen() const { return m_SettingsOpen; }
    void setSettingsOpen(bool open);
    QString updateText() const { return m_UpdateText; }
    void setUpdateText(const QString& text);

    // Installs the toolbar and glass background on the window
    Q_INVOKABLE void attach(QQuickWindow* window);

    // Moves and resizes the window (its content area, in Qt's coordinates). On macOS it can
    // animate like a native window; the call returns when the animation has finished.
    Q_INVOKABLE void setWindowGeometry(QQuickWindow* window, qreal x, qreal y, qreal width, qreal height, bool animate);

    // Remembers the window's size and position between launches (macOS autosave; it's on
    // from attach()). Settings turns it off while it has the window enlarged; turning it
    // back on saves the window's current frame.
    Q_INVOKABLE void setRememberWindowFrame(QQuickWindow* window, bool remember);

    // The standard About panel (name, icon, version from Info.plist)
    Q_INVOKABLE void showAboutPanel();

    // The application menu's items as "title|enabled" strings, for UI self-tests
    Q_INVOKABLE QStringList appMenuItems() const;

    // Image URL for an SF Symbol drawn in the given color, for Image.source
    Q_INVOKABLE QString symbol(const QString& name, const QColor& color) const;

    // The interface font's data (Orbix without its digits, as main.cpp gives Qt), for the
    // window titles AppKit would otherwise draw in the system font. Call before attach().
    static void setInterfaceFontData(const QByteArray& data);

    // Shows a window's title in the interface font: for a plain window without NativeChrome's
    // toolbar (the stream window). Takes an NSWindow*.
    static void useInterfaceFontForTitle(void* nativeWindow);
    static void useInterfaceFontForTitle(QWindow* window);

    // While a stream runs, Cmd+Q ends only the session: the app menu's Quit item reads
    // Disconnect meanwhile (Artemis wording: the app on the PC keeps running)
    static void setQuitEndsSession(bool endsSession);

    // Whether the quit being handled came from outside the app (Dock > Quit, logout,
    // restart, shutdown) rather than from Cmd+Q or the app menu
    static bool isQuitFromOutside();

    // For UI self-tests: chooses the app menu's Quit item as a click would, or sends this
    // app the Quit Apple Event that Dock > Quit sends
    Q_INVOKABLE void triggerQuitMenuItem();
    Q_INVOKABLE void sendQuitAppleEvent();

signals:
    void canGoBackChanged();
    void showAddPcChanged();
    void showHelpChanged();
    void showSettingsChanged();
    void settingsOpenChanged();
    void updateTextChanged();

    void backClicked();
    void addPcClicked();
    void helpClicked();
    void settingsClicked();
    void updateClicked();

private:
    void updateToolbar();

    bool m_CanGoBack = false;
    bool m_ShowAddPc = false;
    bool m_ShowHelp = false;
    bool m_ShowSettings = true;
    bool m_SettingsOpen = false;
    QString m_UpdateText;
    void* m_Native = nullptr;  // Platform state (the toolbar delegate on macOS)
};
