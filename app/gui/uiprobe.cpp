#include "uiprobe.h"

#include <QCoreApplication>
#include <QDir>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>

#include "nativechrome.h"

#ifdef Q_OS_DARWIN
#include "streaming/quitduringstream.h"
#endif

UiProbe::UiProbe(QQuickWindow* window, const QString& outDir)
    : QObject(window),
      m_Window(window),
      m_OutDir(outDir),
      m_Log(QDir(outDir).filePath("probe.log"))
{
    QDir().mkpath(outDir);
    m_Log.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text);
}

void UiProbe::startIfRequested(QQmlApplicationEngine* engine)
{
    const QString script = qEnvironmentVariable("MOONLIGHT_UI_PROBE");
    if (script.isEmpty() || engine->rootObjects().isEmpty()) {
        return;
    }

    auto* window = qobject_cast<QQuickWindow*>(engine->rootObjects().first());
    if (window == nullptr) {
        return;
    }

    QString outDir = qEnvironmentVariable("MOONLIGHT_UI_PROBE_OUT");
    if (outDir.isEmpty()) {
        outDir = QDir::currentPath();
    }

    auto* probe = new UiProbe(window, outDir);
    QQmlContext* windowContext = qmlContext(window);
    auto* context = new QQmlContext(windowContext, probe);
    context->setContextProperty("uiProbe", probe);

    // A script that never finishes still ends the run
    const int timeoutSeconds = qEnvironmentVariableIsSet("MOONLIGHT_UI_PROBE_TIMEOUT") ?
                                   qEnvironmentVariableIntValue("MOONLIGHT_UI_PROBE_TIMEOUT") : 120;
    QTimer::singleShot(timeoutSeconds * 1000, probe, [probe, timeoutSeconds]() {
        probe->log(QString("timed out after %1 s").arg(timeoutSeconds));
        probe->finish(3);
    });

    QQmlComponent component(engine, QUrl::fromLocalFile(script), QQmlComponent::PreferSynchronous);
    QObject* object = component.isReady() ? component.create(context) : nullptr;
    if (object == nullptr) {
        probe->log("Couldn't load the probe script " + script + ": " +
                   (component.isError() ? component.errorString() : QStringLiteral("not ready")));
        probe->finish(2);
        return;
    }
    object->setParent(probe);
    if (auto* item = qobject_cast<QQuickItem*>(object)) {
        item->setParentItem(window->contentItem());
    }
    QObject::connect(qApp, &QCoreApplication::aboutToQuit, probe, [probe]() { probe->log("Artemis is quitting"); });
    probe->log("Probe started: " + script);
}

bool UiProbe::shot(const QString& name)
{
    // A plain file name, kept inside the output folder
    if (name.isEmpty() || name.contains('/') || name.contains('\\') || name.startsWith('.')) {
        log("shot " + name + ": FAILED (not a plain file name)");
        return false;
    }

    bool saved = m_Window->grabWindow().save(QDir(m_OutDir).filePath(name + ".png"));
    log(QString("shot %1: %2").arg(name, saved ? "saved" : "FAILED"));
    return saved;
}

void UiProbe::log(const QString& line)
{
    qInfo().noquote() << "UI probe:" << line;
    if (m_Log.isOpen()) {
        m_Log.write(line.toUtf8() + '\n');
        m_Log.flush();
    }
}

void UiProbe::finish(int exitCode)
{
    log(QString("finish %1").arg(exitCode));
    // Let the current event finish first
    QTimer::singleShot(0, qApp, [exitCode]() { QCoreApplication::exit(exitCode); });
}

void UiProbe::simulateStream(bool active)
{
#ifdef Q_OS_DARWIN
    if (active && m_StreamQuit == nullptr) {
        m_StreamQuit = new QuitDuringStream([this](bool quitArtemis) {
            log(QString("session teardown: end the session%1, leave the host's app running")
                    .arg(quitArtemis ? ", then quit Artemis" : " only"));
            // The session ends after this event, as the stream's loop finishes
            QTimer::singleShot(0, this, [this, quitArtemis]() {
                simulateStream(false);
                if (quitArtemis) {
                    QCoreApplication::quit();
                }
            });
        });
        log("stream: started");
    }
    else if (!active && m_StreamQuit != nullptr) {
        delete m_StreamQuit;
        m_StreamQuit = nullptr;
        log("stream: ended");
    }
#else
    Q_UNUSED(active)
#endif
}

void UiProbe::openPlainWindow(const QString& title)
{
    auto* plain = new QQuickWindow();
    plain->setTitle(title);
    plain->setColor(m_Window->color().alpha() > 0 ? m_Window->color() : QColor(Qt::black));
    plain->resize(640, 360);
    plain->setPosition(m_Window->position() + QPoint(60, 60));
    plain->show();
    NativeChrome::useInterfaceFontForTitle(plain);
    m_Windows.append(plain);
    log("plain window: " + title);
}

void UiProbe::closeWindows()
{
    qDeleteAll(m_Windows);
    m_Windows.clear();
}
