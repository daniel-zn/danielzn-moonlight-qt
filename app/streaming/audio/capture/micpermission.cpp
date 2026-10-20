#include "micpermission.h"

#include <QCoreApplication>

// Non-macOS platforms don't gate microphone access at the OS level
MicPermission::Status MicPermission::status()
{
    return Status::Granted;
}

void MicPermission::request(QObject* context, std::function<void(bool granted)> callback)
{
    QMetaObject::invokeMethod(context, [callback]() { callback(true); }, Qt::QueuedConnection);
}

void MicPermission::explain(Problem, const QString&, std::function<void()> then)
{
    if (then) {
        QMetaObject::invokeMethod(qApp, then, Qt::QueuedConnection);
    }
}
