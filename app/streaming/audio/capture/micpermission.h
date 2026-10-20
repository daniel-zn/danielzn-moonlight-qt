#pragma once

#include <QObject>
#include <QString>

#include <functional>

// Operating system permission to record from the microphone. Only macOS
// gates this; elsewhere access is always reported as granted.
namespace MicPermission
{
    enum class Status {
        Granted,
        Denied,
        Undetermined,
    };

    Status status();

    // Shows the system prompt if the user hasn't decided yet. The callback
    // runs on the thread that owns context (usually the GUI thread) unless
    // context is destroyed first.
    void request(QObject* context, std::function<void(bool granted)> callback);

    enum class Problem {
        Denied,   // macOS reports the microphone as blocked for this app
        NoSound,  // the microphone couldn't be opened, or sent only digital silence
    };

    // macOS only: explains the problem in an alert, with Open Privacy Settings (and, for NoSound,
    // Open Sound Settings) and Cancel. detail is the first sentence for NoSound (which input,
    // what happened). Shown once control is back in the event loop; call it on the GUI thread,
    // after something the user did with the microphone. then (if given) runs once it's closed.
    void explain(Problem problem, const QString& detail = QString(), std::function<void()> then = nullptr);
}
