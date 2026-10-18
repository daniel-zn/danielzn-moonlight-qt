#include "quitduringstream.h"

#include "gui/nativechrome.h"

#include <QCoreApplication>
#include <QEvent>

#include <SDL.h>

QuitDuringStream::QuitDuringStream(std::function<void(bool)> endSession)
    : m_EndSession(std::move(endSession))
{
    QCoreApplication::instance()->installEventFilter(this);
    NativeChrome::setQuitEndsSession(true);
}

QuitDuringStream::~QuitDuringStream()
{
    NativeChrome::setQuitEndsSession(false);
    QCoreApplication::instance()->removeEventFilter(this);
}

bool QuitDuringStream::eventFilter(QObject* watched, QEvent* event)
{
    if (watched == QCoreApplication::instance() && event->type() == QEvent::Quit) {
        bool quitArtemis = NativeChrome::isQuitFromOutside();
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    quitArtemis ? "Quit requested from outside while streaming: ending the session, then quitting"
                                : "Quit requested while streaming: ending the session only");
        m_EndSession(quitArtemis);

        // Decline the immediate termination: the stream shuts down cleanly first
        event->ignore();
        return true;
    }
    return false;
}
