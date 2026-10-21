#include "micpermission.h"

#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>

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

void MicPermission::openPrivacySettings()
{
    // The System Preferences URL still opens the matching System Settings page on macOS 13 and later
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"]];
}
