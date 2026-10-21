#pragma once

#include <QObject>
#include <QString>

#include <functional>

// Operating system permission to record from the microphone. Only macOS
// gates this; elsewhere access is always reported as granted. Artemis never shows
// its own alerts about it: macOS asks once, and Settings shows a status line.
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

    // Opens Privacy & Security > Microphone in System Settings (macOS only)
    void openPrivacySettings();
}
