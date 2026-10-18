#pragma once

#include <QObject>

#include <functional>

// macOS: while a stream runs, the session's SDL loop owns the main thread, so a request to
// quit (Cmd+Q, Artemis > Quit, Dock > Quit, logout) would sit in Qt's queue until the stream
// ended on its own. While this object exists it catches that request and declines the
// immediate quit, calling endSession instead: with quitArtemis false for Cmd+Q and the menu
// (only the session ends, and Artemis comes back), true for a quit from outside the app
// (the stream ends, then Artemis quits). Declining means a logout or shutdown started
// mid-stream is cancelled once, while Artemis exits. The app menu's Quit item reads
// Disconnect meanwhile (the app on the PC keeps running).
class QuitDuringStream : public QObject
{
public:
    explicit QuitDuringStream(std::function<void(bool quitArtemis)> endSession);
    ~QuitDuringStream() override;

protected:
    bool eventFilter(QObject* watched, QEvent* event) override;

private:
    std::function<void(bool)> m_EndSession;
};
