#include "nativechrome.h"

#include <QColor>
#include <QQmlEngine>
#include <QQuickWindow>

// Platforms without native chrome: QML keeps its own toolbar and icons

NativeChrome::NativeChrome(QObject* parent)
    : QObject(parent)
{
}

NativeChrome::~NativeChrome() = default;

void NativeChrome::registerTypes(QQmlEngine*)
{
    qmlRegisterSingletonType<NativeChrome>("NativeChrome", 1, 0, "NativeChrome",
                                           [](QQmlEngine*, QJSEngine*) -> QObject* {
                                               return new NativeChrome();
                                           });
}

bool NativeChrome::isEnabled() const
{
    return false;
}

void NativeChrome::attach(QQuickWindow*)
{
}

void NativeChrome::setWindowGeometry(QQuickWindow* window, qreal x, qreal y, qreal width, qreal height, bool)
{
    if (window != nullptr) {
        window->setGeometry(qRound(x), qRound(y), qRound(width), qRound(height));
    }
}

void NativeChrome::setRememberWindowFrame(QQuickWindow*, bool)
{
}

void NativeChrome::showAboutPanel()
{
}

QStringList NativeChrome::appMenuItems() const
{
    return QStringList();
}

QString NativeChrome::symbol(const QString&, const QColor&) const
{
    return QString();
}

void NativeChrome::setInterfaceFontData(const QByteArray&)
{
}

void NativeChrome::useInterfaceFontForTitle(void*)
{
}

void NativeChrome::useInterfaceFontForTitle(QWindow*)
{
}

void NativeChrome::setQuitEndsSession(bool)
{
}

bool NativeChrome::isQuitFromOutside()
{
    return false;
}

void NativeChrome::triggerQuitMenuItem()
{
}

void NativeChrome::sendQuitAppleEvent()
{
}

void NativeChrome::updateToolbar()
{
}
