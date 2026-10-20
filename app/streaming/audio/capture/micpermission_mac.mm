#include "micpermission.h"

#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>

#include <QCoreApplication>
#include <QDebug>
#include <QPointer>

MicPermission::Status MicPermission::status()
{
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]) {
    case AVAuthorizationStatusAuthorized:
        return Status::Granted;
    case AVAuthorizationStatusNotDetermined:
        return Status::Undetermined;
    default:
        return Status::Denied;
    }
}

void MicPermission::request(QObject* context, std::function<void(bool granted)> callback)
{
    QPointer<QObject> guard(context);
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
        // AVFoundation calls back on an arbitrary queue
        if (guard) {
            QMetaObject::invokeMethod(guard, [callback, granted]() { callback(granted); }, Qt::QueuedConnection);
        }
    }];
}

namespace
{
    QString tr(const char* text)
    {
        return QCoreApplication::translate("MicPermission", text);
    }

    // The System Preferences URLs still open the matching System Settings pages on macOS 13 and later
    void openSettings(NSString* url)
    {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
    }

    void showAlert(MicPermission::Problem problem, const QString& detail)
    {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        if (problem == MicPermission::Problem::Denied) {
            alert.messageText = tr("Moonlight can't use your microphone").toNSString();
            alert.informativeText = tr("macOS is blocking Moonlight from the microphone. Turn Moonlight on in "
                                       "Privacy & Security > Microphone.\n\n"
                                       "If it's already on, that permission may belong to an older version of "
                                       "Moonlight: switch it off and on again, or remove Moonlight from the list "
                                       "and open Moonlight again.").toNSString();
        }
        else {
            alert.messageText = tr("Moonlight hears nothing from your microphone").toNSString();
            // detail may start with a device label such as "the system default input"
            QString sentence = detail;
            if (!sentence.isEmpty()) {
                sentence[0] = sentence[0].toUpper();
            }
            alert.informativeText = (sentence + "\n\n" +
                                     tr("Check that it's the input you want and that it isn't muted (Sound > Input). "
                                        "If other apps hear it, macOS may be blocking Moonlight: check "
                                        "Privacy & Security > Microphone.")).toNSString();
        }
        [alert addButtonWithTitle:tr("Open Privacy Settings").toNSString()];
        if (problem == MicPermission::Problem::NoSound) {
            [alert addButtonWithTitle:tr("Open Sound Settings").toNSString()];
        }
        [alert addButtonWithTitle:tr("Cancel").toNSString()];

        [NSApp activateIgnoringOtherApps:YES];
        const NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            openSettings(@"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone");
        }
        else if (response == NSAlertSecondButtonReturn && problem == MicPermission::Problem::NoSound) {
            openSettings(@"x-apple.systempreferences:com.apple.preference.sound?input");
        }
    }
}

void MicPermission::explain(Problem problem, const QString& detail, std::function<void()> then)
{
    qInfo() << "Explaining the microphone problem:" << (problem == Problem::Denied ? "denied" : "no sound") << detail;

    // Out of whatever called this (a QML handler, a timer), so the alert's modal loop doesn't run inside it
    QMetaObject::invokeMethod(qApp, [problem, detail, then]() {
        showAlert(problem, detail);
        if (then) {
            then();
        }
    }, Qt::QueuedConnection);
}
