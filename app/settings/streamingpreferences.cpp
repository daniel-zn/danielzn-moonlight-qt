#include "streamingpreferences.h"
#include "SDL_compat.h"
#include "utils.h"
#include "streaming/audio/capture/micpermission.h"

#include <QSettings>
#include <QTranslator>
#include <QCoreApplication>
#include <QLocale>
#include <QReadWriteLock>
#include <QTimer>
#include <QDateTime>
#include <QtMath>
#include <QRegularExpression>
#include <QHash>

#include <QtDebug>

#define SER_STREAMSETTINGS "streamsettings"
#define SER_WIDTH "width"
#define SER_HEIGHT "height"
#define SER_FPS "fps"
#define SER_BITRATE "bitrate"
#define SER_UNLOCK_BITRATE "unlockbitrate"
#define SER_AUTOADJUSTBITRATE "autoadjustbitrate"
#define SER_FULLSCREEN "fullscreen"
#define SER_VSYNC "vsync"
#define SER_GAMEOPTS "gameopts"
#define SER_HOSTAUDIO "hostaudio"
#define SER_MULTICONT "multicontroller"
#define SER_AUDIOCFG "audiocfg"
#define SER_VIDEOCFG "videocfg"
#define SER_HDR "hdr"
#define SER_YUV444 "yuv444"
#define SER_VIDEODEC "videodec"
#define SER_WINDOWMODE "windowmode"
#define SER_MDNS "mdns"
#define SER_QUITAPPAFTER "quitAppAfter"
#define SER_ABSMOUSEMODE "mouseacceleration"
#define SER_ABSTOUCHMODE "abstouchmode"
#define SER_STARTWINDOWED "startwindowed"
#define SER_FRAMEPACING "framepacing"
#define SER_CONNWARNINGS "connwarnings"
#define SER_CONFWARNINGS "confwarnings"
#define SER_UIDISPLAYMODE "uidisplaymode"
#define SER_RICHPRESENCE "richpresence"
#define SER_GAMEPADMOUSE "gamepadmouse"
#define SER_DEFAULTVER "defaultver"
#define SER_PACKETSIZE "packetsize"
#define SER_DETECTNETBLOCKING "detectnetblocking"
#define SER_SHOWPERFOVERLAY "showperfoverlay"
#define SER_ENABLEMICROPHONE "enablemicrophone"
#define SER_MICROPHONEDEVICE "microphonedevice"
#define SER_MICNOISESUPPRESSION "micnoisesuppression"
#define SER_SWAPMOUSEBUTTONS "swapmousebuttons"
#define SER_MUTEONFOCUSLOSS "muteonfocusloss"
#define SER_BACKGROUNDGAMEPAD "backgroundgamepad"
#define SER_REVERSESCROLL "reversescroll"
#define SER_SWAPFACEBUTTONS "swapfacebuttons"
#define SER_CAPTURESYSKEYS "capturesyskeys"
#define SER_KEEPAWAKE "keepawake"
#define SER_LANGUAGE "language"
#define SER_RENDERER "renderer"

#define CURRENT_DEFAULT_VER 2

static StreamingPreferences* s_GlobalPrefs;

Q_GLOBAL_STATIC(QReadWriteLock, s_GlobalPrefsLock)

namespace {
#ifdef Q_OS_DARWIN
    // Artemis is a screen-sharing app for the user's own PC, so on macOS its English text
    // talks about apps and sessions rather than games and streams. Keyed by
    // "<context>|<source text>" where a short word means something else elsewhere.
    const QHash<QString, QString>& artemisWording()
    {
        static const QHash<QString, QString> wording = {
            { "MacMenuBar|Game", "App" },
            { "MacMenuBar|Launch", "Connect" },
            { "MacAppRow|Running", "Active" },
            { "AppView|Quit", "Stop" },
            { "End Game on PC…", "Stop…" },
            { "Launch Automatically When Opening PC", "Connect Automatically When Opening PC" },
            { "Launch Game", "Connect" },
            { "Resume Game", "Resume" },
            { "Quit Game", "Stop" },
            { "Direct Launch", "Connect Automatically" },
            { "Launch this app immediately when the host is selected, bypassing the app selection grid.",
              "Connect to this app as soon as the PC is opened, skipping the app list." },
            { "Hide this game from the app grid. To access hidden games, right-click on the host and choose %1.",
              "Hide this app from the list. To see hidden apps, right-click the PC and choose %1." },
            // AppView fills %2 with the PC's name; elsewhere the PC isn't known
            { "AppView|Are you sure you want to quit %1? Any unsaved progress will be lost.",
              "Stop %1 on %2? Unsaved work in it will be lost." },
            { "Are you sure you want to quit %1? Any unsaved progress will be lost.",
              "Stop %1 on the PC? Unsaved work in it will be lost." },
            { "Quitting %1...", "Stopping %1…" },
            { "Quitting app...", "Stopping the app…" },
            { "Quitting app failed, reason: %1", "Stopping the app failed: %1" },
            { "Starting %1...", "Connecting to %1…" },
            { "Resuming %1...", "Resuming %1…" },
            { "Starting %1 failed: Error %2", "Connecting to %1 failed: Error %2" },
            { "Running Game ID: %1", "Active App ID: %1" },
            { "The running game wasn't started by this PC. ", "The active app wasn't started by this PC. " },
            { "You cannot pair while a previous session is still running on the host PC. Quit any running games or reboot the host PC, then try pairing again.",
              "You can't pair while a session is still active on the host PC. End it or restart the host PC, then try pairing again." },
            { "Game Controllers", "Controllers" },
            { "Optimize game settings for streaming", "Optimize app settings for the session" },
            { "Quit app on host PC after ending stream", "Close the app on the PC when the session ends" },
            { "This will close the app or game you are streaming when you end your stream. You will lose any unsaved progress!",
              "Ending the session closes the app on the PC. Unsaved work in it will be lost." },
            { "Mute audio stream when Moonlight is not the active window", "Mute the session when Moonlight isn't the active window" },
            { "Mutes Moonlight's audio when you Alt+Tab out of the stream or click on a different window.",
              "Mutes the session's audio when you switch to another app or window." },
            { "Optimize mouse for remote desktop instead of games", "Optimize mouse for remote desktop" },
            { "This enables seamless mouse control without capturing the client's mouse cursor. It is ideal for remote desktop usage but will not work in most games.",
              "Moves the pointer in and out of the session without capturing it. Best for desktop work; apps that need a captured mouse, like games, won't work with it." },
            { "Only enable this option when streaming a game that doesn't support gamepads being connected after startup.",
              "Only turn this on for an app that doesn't notice gamepads connected after it starts." },
            { "Good for streaming desktop and text-heavy games, but not recommended for fast-paced games.",
              "Good for desktop work and text, but not recommended for fast motion." },
            { "This unlocks extremely high video bitrates for use with Sunshine hosts. It should only be used when streaming over an Ethernet LAN connection.",
              "This unlocks extremely high video bitrates for use with Sunshine hosts. Only use it over an Ethernet LAN connection." },
            { "The stream will be HDR-capable, but some games may require an HDR monitor on your host PC to enable HDR mode.",
              "The session will be HDR-capable, but some apps may need an HDR monitor on your host PC to turn on HDR." },
            { "HDR streaming is not supported on this PC.", "HDR sessions aren't supported on this PC." },
            { "Resolutions that are not supported by your client or host PC may cause streaming errors.",
              "Resolutions that your Mac or host PC doesn't support may cause errors in the session." },
            { "Something went wrong on your host PC when starting the stream.", "Something went wrong on your host PC when starting the session." },
            { "Unable to initialize video decoder. Please check your streaming settings and try again.",
              "Unable to initialize video decoder. Please check your video settings and try again." },
        };
        return wording;
    }

    // Wording the table doesn't list word for word
    QString artemisRewording(QString text)
    {
        static const QList<QPair<QRegularExpression, QString>> rules = {
            { QRegularExpression("\\bgaming PC\\b"), "PC" },
            { QRegularExpression("\\bGames\\b"), "Apps" },
            { QRegularExpression("\\bgames\\b"), "apps" },
            { QRegularExpression("\\bGame\\b"), "App" },
            { QRegularExpression("\\bgame\\b"), "app" },
            { QRegularExpression("\\bstreaming performance\\b"), "performance" },
            { QRegularExpression("\\b(while|when) streaming\\b"), "during a session" },
            { QRegularExpression("\\bto stream from\\b"), "to connect to" },
            { QRegularExpression("\\bStreaming over the Internet\\b"), "Connecting over the Internet" },
            { QRegularExpression("\\bstream over the Internet\\b"), "connect over the Internet" },
            { QRegularExpression("\\bfor HDR streaming\\b"), "for HDR" },
            { QRegularExpression("\\bHDR streaming\\b"), "HDR sessions" },
            { QRegularExpression("\\bYUV 4:4:4 streaming\\b"), "YUV 4:4:4 video" },
            { QRegularExpression("\\bstreaming video resolutions\\b"), "video resolutions" },
            { QRegularExpression("\\bfor 4K streaming\\b"), "for 4K" },
        };
        const QString original = text;
        for (const auto& rule : rules) {
            text.replace(rule.first, rule.second);
        }
        return text == original ? QString() : text;
    }

    // The macOS app is named Artemis and talks about apps and sessions. Its strings keep
    // the upstream wording in the source so every translation still matches; this
    // translator, queried before the language one, rewords English text (text the language
    // has no translation for) and renames the app in all of it. Names of upstream
    // Moonlight resources (its setup guide, help and Internet Hosting Tool) stay as they are.
    class AppNameTranslator : public QTranslator
    {
    public:
        QString translate(const char* context, const char* sourceText,
                          const char* disambiguation, int n) const override
        {
            if (sourceText == nullptr) {
                return QString();
            }

            QString text = language != nullptr ? language->translate(context, sourceText, disambiguation, n) : QString();
            if (text.isNull()) {
                const QString source = QString::fromUtf8(sourceText);
                const auto& wording = artemisWording();
                text = wording.value(QString::fromUtf8(context) + '|' + source,
                                     wording.value(source));
                if (text.isNull()) {
                    text = artemisRewording(source);
                }
                if (text.isNull() && !source.contains("Moonlight")) {
                    return QString();
                }
                if (text.isNull()) {
                    text = source;
                }
            }
            else if (strstr(sourceText, "Moonlight") == nullptr) {
                return QString();
            }

            static const QRegularExpression appName(
                "\\bMoonlight\\b(?! (Internet Hosting Tool|Setup Guide|help))");
            return text.replace(appName, QStringLiteral("Artemis"));
        }

        bool isEmpty() const override
        {
            return false;
        }

        const QTranslator* language = nullptr;
    };
#endif

    QString kMicrophoneDeniedText()
    {
        return QCoreApplication::translate("StreamingPreferences",
                                           "Moonlight isn't allowed to use the microphone. Turn it on in System Settings > Privacy & Security > Microphone.");
    }
}

StreamingPreferences::StreamingPreferences(QQmlEngine *qmlEngine)
    : m_QmlEngine(qmlEngine)
    , m_MicrophoneMonitorDeviceId(0)
    , m_MicrophoneMonitorSpec({})
    , m_MicrophoneMonitorTimer(new QTimer(this))
    , m_PendingMicrophonePeak(0)
    , m_MicrophoneCallbackCount(0)
    , m_MicrophoneSignalEverSeen(false)
    , m_MicrophoneMonitorStartMs(0)
    , m_MicrophoneMonitorLevel(0.0)
    , m_MicrophoneMonitorActive(false)
    , m_MicrophonePermissionRequestPending(false)
    , m_MicrophoneMonitorSignalDetected(false)
    , m_MicrophoneMonitorHoldsAudio(false)
{
    m_MicrophoneMonitorStatus = tr("Press Test microphone and speak to check your input.");
    m_MicrophoneMonitorTimer->setInterval(50);
    connect(m_MicrophoneMonitorTimer, &QTimer::timeout, this, &StreamingPreferences::updateMicrophoneMonitorState);
    reload();
}

StreamingPreferences::~StreamingPreferences()
{
    stopMicrophoneMonitor();
}

StreamingPreferences* StreamingPreferences::get(QQmlEngine *qmlEngine)
{
    {
        QReadLocker readGuard(s_GlobalPrefsLock);

        // If we have a preference object and it's associated with a QML engine or
        // if the caller didn't specify a QML engine, return the existing object.
        if (s_GlobalPrefs && (s_GlobalPrefs->m_QmlEngine || !qmlEngine)) {
            // The lifetime logic here relies on the QML engine also being a singleton.
            Q_ASSERT(!qmlEngine || s_GlobalPrefs->m_QmlEngine == qmlEngine);
            return s_GlobalPrefs;
        }
    }

    {
        QWriteLocker writeGuard(s_GlobalPrefsLock);

        // If we already have an preference object but the QML engine is now available,
        // associate the QML engine with the preferences.
        if (s_GlobalPrefs) {
            if (!s_GlobalPrefs->m_QmlEngine) {
                s_GlobalPrefs->m_QmlEngine = qmlEngine;
            }
            else {
                // We could reach this codepath if another thread raced with us
                // and created the object while we were outside the pref lock.
                Q_ASSERT(!qmlEngine || s_GlobalPrefs->m_QmlEngine == qmlEngine);
            }
        }
        else {
            s_GlobalPrefs = new StreamingPreferences(qmlEngine);
        }

        return s_GlobalPrefs;
    }
}

void StreamingPreferences::reload()
{
    QSettings settings;

    int defaultVer = settings.value(SER_DEFAULTVER, 0).toInt();

#ifdef Q_OS_DARWIN
    recommendedFullScreenMode = WindowMode::WM_FULLSCREEN_DESKTOP;
#else
    // Wayland doesn't support modesetting, so use fullscreen desktop mode
    // unless we have a slow GPU (which can take advantage of wp_viewporter
    // to reduce GPU load with lower resolution video streams).
    if (WMUtils::isRunningWayland() && !WMUtils::isGpuSlow()) {
        recommendedFullScreenMode = WindowMode::WM_FULLSCREEN_DESKTOP;
    }
    else {
        recommendedFullScreenMode = WindowMode::WM_FULLSCREEN;
    }
#endif

    width = settings.value(SER_WIDTH, 1280).toInt();
    height = settings.value(SER_HEIGHT, 720).toInt();
    fps = settings.value(SER_FPS, 60).toInt();
    enableYUV444 = settings.value(SER_YUV444, false).toBool();
    bitrateKbps = settings.value(SER_BITRATE, getDefaultBitrate(width, height, fps, enableYUV444)).toInt();
    unlockBitrate = settings.value(SER_UNLOCK_BITRATE, false).toBool();
    autoAdjustBitrate = settings.value(SER_AUTOADJUSTBITRATE, true).toBool();
    enableVsync = settings.value(SER_VSYNC, true).toBool();
    gameOptimizations = settings.value(SER_GAMEOPTS, true).toBool();
    playAudioOnHost = settings.value(SER_HOSTAUDIO, false).toBool();
    multiController = settings.value(SER_MULTICONT, true).toBool();
    enableMdns = settings.value(SER_MDNS, true).toBool();
    quitAppAfter = settings.value(SER_QUITAPPAFTER, false).toBool();
    absoluteMouseMode = settings.value(SER_ABSMOUSEMODE, false).toBool();
    absoluteTouchMode = settings.value(SER_ABSTOUCHMODE, true).toBool();
    framePacing = settings.value(SER_FRAMEPACING, false).toBool();
    connectionWarnings = settings.value(SER_CONNWARNINGS, true).toBool();
    configurationWarnings = settings.value(SER_CONFWARNINGS, true).toBool();
    richPresence = settings.value(SER_RICHPRESENCE, true).toBool();
    gamepadMouse = settings.value(SER_GAMEPADMOUSE, true).toBool();
    detectNetworkBlocking = settings.value(SER_DETECTNETBLOCKING, true).toBool();
    showPerformanceOverlay = settings.value(SER_SHOWPERFOVERLAY, false).toBool();
    enableMicrophone = settings.value(SER_ENABLEMICROPHONE, false).toBool();
    microphoneDevice = settings.value(SER_MICROPHONEDEVICE, "").toString();
    micNoiseSuppression = settings.value(SER_MICNOISESUPPRESSION, true).toBool();
    packetSize = settings.value(SER_PACKETSIZE, 0).toInt();
    swapMouseButtons = settings.value(SER_SWAPMOUSEBUTTONS, false).toBool();
    muteOnFocusLoss = settings.value(SER_MUTEONFOCUSLOSS, false).toBool();
    backgroundGamepad = settings.value(SER_BACKGROUNDGAMEPAD, false).toBool();
    reverseScrollDirection = settings.value(SER_REVERSESCROLL, false).toBool();
    swapFaceButtons = settings.value(SER_SWAPFACEBUTTONS, false).toBool();
    keepAwake = settings.value(SER_KEEPAWAKE, true).toBool();
    enableHdr = settings.value(SER_HDR, false).toBool();
    captureSysKeysMode = static_cast<CaptureSysKeysMode>(settings.value(SER_CAPTURESYSKEYS,
                                                         static_cast<int>(CaptureSysKeysMode::CSK_OFF)).toInt());
    audioConfig = static_cast<AudioConfig>(settings.value(SER_AUDIOCFG,
                                                  static_cast<int>(AudioConfig::AC_STEREO)).toInt());
    videoCodecConfig = static_cast<VideoCodecConfig>(settings.value(SER_VIDEOCFG,
                                                  static_cast<int>(VideoCodecConfig::VCC_AUTO)).toInt());
    videoDecoderSelection = static_cast<VideoDecoderSelection>(settings.value(SER_VIDEODEC,
                                                  static_cast<int>(VideoDecoderSelection::VDS_AUTO)).toInt());
    rendererSelection = static_cast<RendererSelection>(settings.value(SER_RENDERER,
                                                  static_cast<int>(RendererSelection::RS_AUTO)).toInt());
    windowMode = static_cast<WindowMode>(settings.value(SER_WINDOWMODE,
                                                        // Try to load from the old preference value too
                                                        static_cast<int>(settings.value(SER_FULLSCREEN, true).toBool() ?
                                                                             recommendedFullScreenMode : WindowMode::WM_WINDOWED)).toInt());
    uiDisplayMode = static_cast<UIDisplayMode>(settings.value(SER_UIDISPLAYMODE,
                                               static_cast<int>(settings.value(SER_STARTWINDOWED, true).toBool() ? UIDisplayMode::UI_WINDOWED
                                                                                                                 : UIDisplayMode::UI_MAXIMIZED)).toInt());
    language = static_cast<Language>(settings.value(SER_LANGUAGE,
                                                    static_cast<int>(Language::LANG_AUTO)).toInt());


    // Perform default settings updates as required based on last default version
    if (defaultVer < 1) {
#ifdef Q_OS_DARWIN
        // Update window mode setting on macOS from full-screen (old default) to borderless windowed (new default)
        if (windowMode == WindowMode::WM_FULLSCREEN) {
            windowMode = WindowMode::WM_FULLSCREEN_DESKTOP;
        }
#endif
    }
    if (defaultVer < 2) {
        if (windowMode == WindowMode::WM_FULLSCREEN && WMUtils::isRunningWayland()) {
            windowMode = WindowMode::WM_FULLSCREEN_DESKTOP;
        }
    }

    // Fixup VCC value to the new settings format with codec and HDR separate
    if (videoCodecConfig == VCC_FORCE_HEVC_HDR_DEPRECATED) {
        videoCodecConfig = VCC_AUTO;
        enableHdr = true;
    }
}

bool StreamingPreferences::retranslate()
{
    static QTranslator* translator = nullptr;

#if QT_VERSION < QT_VERSION_CHECK(5, 10, 0)
    if (m_QmlEngine != nullptr) {
        // Dynamic retranslation is not supported until Qt 5.10
        return false;
    }
#endif

#ifdef Q_OS_DARWIN
    // Take the app name translator out before the language translator it reads goes away
    static AppNameTranslator* appNameTranslator = new AppNameTranslator();
    QCoreApplication::removeTranslator(appNameTranslator);
    appNameTranslator->language = nullptr;
#endif

    QTranslator* newTranslator = new QTranslator();
    QString languageSuffix = getSuffixFromLanguage(language);

    // Remove the old translator, even if we can't load a new one.
    // Otherwise we'll be stuck with the old translated values instead
    // of defaulting to English.
    if (translator != nullptr) {
        QCoreApplication::removeTranslator(translator);
        delete translator;
        translator = nullptr;
    }

    if (newTranslator->load(QString(":/languages/qml_") + languageSuffix)) {
        qInfo() << "Successfully loaded translation for" << languageSuffix;

        translator = newTranslator;
        QCoreApplication::installTranslator(translator);
    }
    else {
        qInfo() << "No translation available for" << languageSuffix;
        delete newTranslator;
    }

#ifdef Q_OS_DARWIN
    // Reinstall the app name translator so it's queried before the language one
    appNameTranslator->language = translator;
    QCoreApplication::installTranslator(appNameTranslator);
#endif

    if (m_QmlEngine != nullptr) {
#if QT_VERSION >= QT_VERSION_CHECK(5, 10, 0)
        // This is a dynamic retranslation from the settings page.
        // We have to kick the QML engine into reloading our text.
        m_QmlEngine->retranslate();
#else
        // Unreachable below Qt 5.10 due to the check above
        Q_ASSERT(false);
#endif
    }
    else {
        // This is a translation from a non-QML context, which means
        // it is probably app startup. There's nothing to refresh.
    }

    return true;
}

QString StreamingPreferences::getSuffixFromLanguage(StreamingPreferences::Language lang)
{
    switch (lang)
    {
    case LANG_DE:
        return "de";
    case LANG_EN:
        return "en";
    case LANG_FR:
        return "fr";
    case LANG_ZH_CN:
        return "zh_CN";
    case LANG_NB_NO:
        return "nb_NO";
    case LANG_RU:
        return "ru";
    case LANG_ES:
        return "es";
    case LANG_JA:
        return "ja";
    case LANG_VI:
        return "vi";
    case LANG_TH:
        return "th";
    case LANG_KO:
        return "ko";
    case LANG_HU:
        return "hu";
    case LANG_NL:
        return "nl";
    case LANG_SV:
        return "sv";
    case LANG_TR:
        return "tr";
    case LANG_UK:
        return "uk";
    case LANG_ZH_TW:
        return "zh_TW";
    case LANG_PT:
        return "pt";
    case LANG_PT_BR:
        return "pt_BR";
    case LANG_EL:
        return "el";
    case LANG_IT:
        return "it";
    case LANG_HI:
        return "hi";
    case LANG_PL:
        return "pl";
    case LANG_CS:
        return "cs";
    case LANG_HE:
        return "he";
    case LANG_CKB:
        return "ckb";
    case LANG_LT:
        return "lt";
    case LANG_ET:
        return "et";
    case LANG_BG:
        return "bg";
    case LANG_EO:
        return "eo";
    case LANG_TA:
        return "ta";
    case LANG_AUTO:
    default:
        return QLocale::system().name();
    }
}

void StreamingPreferences::save()
{
    QSettings settings;

    settings.setValue(SER_WIDTH, width);
    settings.setValue(SER_HEIGHT, height);
    settings.setValue(SER_FPS, fps);
    settings.setValue(SER_BITRATE, bitrateKbps);
    settings.setValue(SER_UNLOCK_BITRATE, unlockBitrate);
    settings.setValue(SER_AUTOADJUSTBITRATE, autoAdjustBitrate);
    settings.setValue(SER_VSYNC, enableVsync);
    settings.setValue(SER_GAMEOPTS, gameOptimizations);
    settings.setValue(SER_HOSTAUDIO, playAudioOnHost);
    settings.setValue(SER_MULTICONT, multiController);
    settings.setValue(SER_MDNS, enableMdns);
    settings.setValue(SER_QUITAPPAFTER, quitAppAfter);
    settings.setValue(SER_ABSMOUSEMODE, absoluteMouseMode);
    settings.setValue(SER_ABSTOUCHMODE, absoluteTouchMode);
    settings.setValue(SER_FRAMEPACING, framePacing);
    settings.setValue(SER_CONNWARNINGS, connectionWarnings);
    settings.setValue(SER_CONFWARNINGS, configurationWarnings);
    settings.setValue(SER_RICHPRESENCE, richPresence);
    settings.setValue(SER_GAMEPADMOUSE, gamepadMouse);
    settings.setValue(SER_PACKETSIZE, packetSize);
    settings.setValue(SER_DETECTNETBLOCKING, detectNetworkBlocking);
    settings.setValue(SER_SHOWPERFOVERLAY, showPerformanceOverlay);
    settings.setValue(SER_ENABLEMICROPHONE, enableMicrophone);
    settings.setValue(SER_MICROPHONEDEVICE, microphoneDevice);
    settings.setValue(SER_MICNOISESUPPRESSION, micNoiseSuppression);
    settings.setValue(SER_AUDIOCFG, static_cast<int>(audioConfig));
    settings.setValue(SER_HDR, enableHdr);
    settings.setValue(SER_YUV444, enableYUV444);
    settings.setValue(SER_VIDEOCFG, static_cast<int>(videoCodecConfig));
    settings.setValue(SER_VIDEODEC, static_cast<int>(videoDecoderSelection));
    settings.setValue(SER_RENDERER, static_cast<int>(rendererSelection));
    settings.setValue(SER_WINDOWMODE, static_cast<int>(windowMode));
    settings.setValue(SER_UIDISPLAYMODE, static_cast<int>(uiDisplayMode));
    settings.setValue(SER_LANGUAGE, static_cast<int>(language));
    settings.setValue(SER_DEFAULTVER, CURRENT_DEFAULT_VER);
    settings.setValue(SER_SWAPMOUSEBUTTONS, swapMouseButtons);
    settings.setValue(SER_MUTEONFOCUSLOSS, muteOnFocusLoss);
    settings.setValue(SER_BACKGROUNDGAMEPAD, backgroundGamepad);
    settings.setValue(SER_REVERSESCROLL, reverseScrollDirection);
    settings.setValue(SER_SWAPFACEBUTTONS, swapFaceButtons);
    settings.setValue(SER_CAPTURESYSKEYS, captureSysKeysMode);
    settings.setValue(SER_KEEPAWAKE, keepAwake);
}

QStringList StreamingPreferences::microphoneDevices() const
{
    return m_MicrophoneDevices;
}

double StreamingPreferences::microphoneMonitorLevel() const
{
    return m_MicrophoneMonitorLevel;
}

QString StreamingPreferences::microphoneMonitorStatus() const
{
    return m_MicrophoneMonitorStatus;
}

bool StreamingPreferences::microphoneMonitorSignalDetected() const
{
    return m_MicrophoneMonitorSignalDetected;
}

void StreamingPreferences::refreshMicrophoneDevices()
{
    const bool audioWasInitialized = SDL_WasInit(SDL_INIT_AUDIO) != 0;
    if (!audioWasInitialized && SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
        qWarning() << "Failed to initialize SDL audio for microphone enumeration:" << SDL_GetError();
        return;
    }

    QStringList devices;
    const int deviceCount = SDL_GetNumAudioDevices(SDL_TRUE);
    for (int i = 0; i < deviceCount; ++i) {
        const char* name = SDL_GetAudioDeviceName(i, SDL_TRUE);
        if (name == nullptr || *name == '\0') {
            continue;
        }

        const QString deviceName = QString::fromUtf8(name);
        if (!devices.contains(deviceName)) {
            devices.append(deviceName);
        }
    }

    qInfo() << "Microphone inputs:" << devices;

    if (!microphoneDevice.isEmpty() && !devices.contains(microphoneDevice)) {
        devices.prepend(microphoneDevice);
    }

    if (!audioWasInitialized) {
        SDL_QuitSubSystem(SDL_INIT_AUDIO);
    }

    if (devices != m_MicrophoneDevices) {
        m_MicrophoneDevices = devices;
        emit microphoneDevicesChanged();
    }
}

void StreamingPreferences::setMicrophoneMonitorActive(bool active)
{
    if (m_MicrophoneMonitorActive == active) {
        if (active) {
            refreshMicrophoneMonitor();
        }
        return;
    }

    m_MicrophoneMonitorActive = active;
    emit microphoneTestRunningChanged();
    if (active) {
        startMicrophoneMonitor();
    }
    else {
        stopMicrophoneMonitor(tr("Press Test microphone and speak to check your input."));
    }
}

void StreamingPreferences::requestMicrophonePermission()
{
    switch (MicPermission::status()) {
    case MicPermission::Status::Granted:
        return;
    case MicPermission::Status::Denied:
        setMicrophoneMonitorStatus(kMicrophoneDeniedText());
        return;
    case MicPermission::Status::Undetermined:
        if (!m_MicrophonePermissionRequestPending) {
            m_MicrophonePermissionRequestPending = true;
            MicPermission::request(this, [this](bool granted) {
                m_MicrophonePermissionRequestPending = false;
                if (!granted) {
                    setMicrophoneMonitorStatus(kMicrophoneDeniedText());
                }
                refreshMicrophoneMonitor();
            });
        }
        return;
    }
}

bool StreamingPreferences::microphoneTestRunning() const
{
    return m_MicrophoneMonitorActive;
}

void StreamingPreferences::refreshMicrophoneMonitor()
{
    if (!m_MicrophoneMonitorActive) {
        return;
    }

    if (!enableMicrophone) {
        setMicrophoneMonitorActive(false);
        return;
    }

    stopMicrophoneMonitor(tr("Press Test microphone and speak to check your input."));
    startMicrophoneMonitor();
}

void StreamingPreferences::microphoneMonitorCallback(void* userdata, Uint8* stream, int len)
{
    auto* prefs = static_cast<StreamingPreferences*>(userdata);
    if (prefs != nullptr) {
        prefs->processMicrophoneMonitorData(stream, len);
    }
}

bool StreamingPreferences::startMicrophoneMonitor()
{
    // Only touch the microphone when the user wants it streamed; opening it is
    // what makes macOS ask for permission.
    if (!enableMicrophone) {
        setMicrophoneMonitorStatus(tr("Enable microphone streaming to preview your microphone"));
        return false;
    }

    switch (MicPermission::status()) {
    case MicPermission::Status::Granted:
        break;
    case MicPermission::Status::Denied:
        setMicrophoneMonitorStatus(kMicrophoneDeniedText());
        return false;
    case MicPermission::Status::Undetermined:
        setMicrophoneMonitorStatus(tr("Waiting for microphone permission"));
        if (!m_MicrophonePermissionRequestPending) {
            m_MicrophonePermissionRequestPending = true;
            MicPermission::request(this, [this](bool) {
                m_MicrophonePermissionRequestPending = false;
                refreshMicrophoneMonitor();
            });
        }
        return false;
    }

    // A hard failure ends the test, so the button doesn't keep saying it's running
    auto failTest = [this](const QString& status) {
        stopMicrophoneMonitor(status);
        if (m_MicrophoneMonitorActive) {
            m_MicrophoneMonitorActive = false;
            emit microphoneTestRunningChanged();
        }
        return false;
    };

    // Hold a reference on SDL audio only while the test runs (stopMicrophoneMonitor drops it)
    if (!m_MicrophoneMonitorHoldsAudio) {
        if (SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
            return failTest(tr("Microphone preview unavailable: SDL audio init failed"));
        }
        m_MicrophoneMonitorHoldsAudio = true;
    }

    SDL_AudioSpec desired = {};
    desired.freq = 48000;
    desired.format = AUDIO_S16SYS;
    desired.channels = 1;
    desired.samples = 960;
    desired.callback = &StreamingPreferences::microphoneMonitorCallback;
    desired.userdata = this;

    const QByteArray deviceNameUtf8 = microphoneDevice.toUtf8();
    const char* selectedDevice = deviceNameUtf8.isEmpty() ? nullptr : deviceNameUtf8.constData();
    bool fellBackToDefault = false;

    m_MicrophoneMonitorDeviceId = SDL_OpenAudioDevice(selectedDevice, SDL_TRUE, &desired, &m_MicrophoneMonitorSpec, 0);
    if (m_MicrophoneMonitorDeviceId == 0 && selectedDevice != nullptr) {
        m_MicrophoneMonitorDeviceId = SDL_OpenAudioDevice(nullptr, SDL_TRUE, &desired, &m_MicrophoneMonitorSpec, 0);
        if (m_MicrophoneMonitorDeviceId != 0) {
            fellBackToDefault = true;
        }
    }

    if (m_MicrophoneMonitorDeviceId == 0) {
        qWarning() << "Microphone test couldn't open" << microphoneDevice << ":" << SDL_GetError();
        return failTest(tr("Couldn't open the microphone: %1").arg(QString::fromUtf8(SDL_GetError())));
    }

    if (m_MicrophoneMonitorSpec.freq != desired.freq ||
            m_MicrophoneMonitorSpec.channels != desired.channels ||
            m_MicrophoneMonitorSpec.format != desired.format) {
        return failTest(tr("Microphone preview unavailable: the input device does not support 48 kHz mono 16-bit capture"));
    }

    m_PendingMicrophonePeak.store(0, std::memory_order_release);
    if (m_MicrophoneMonitorLevel != 0.0) {
        m_MicrophoneMonitorLevel = 0.0;
        emit microphoneMonitorLevelChanged();
    }
    if (m_MicrophoneMonitorSignalDetected) {
        m_MicrophoneMonitorSignalDetected = false;
        emit microphoneMonitorSignalDetectedChanged();
    }

    m_MicrophoneMonitorDeviceLabel = (selectedDevice == nullptr || fellBackToDefault) ?
                                         tr("the system default input") : microphoneDevice;
    m_MicrophoneCallbackCount.store(0, std::memory_order_release);
    m_MicrophoneSignalEverSeen = false;
    m_MicrophoneMonitorStartMs = QDateTime::currentMSecsSinceEpoch();

    qInfo() << "Microphone test opened" << m_MicrophoneMonitorDeviceLabel
            << "requested:" << microphoneDevice << "fell back:" << fellBackToDefault
            << "spec:" << m_MicrophoneMonitorSpec.freq << "Hz" << m_MicrophoneMonitorSpec.channels << "ch"
            << m_MicrophoneMonitorSpec.samples << "samples";

    if (fellBackToDefault) {
        setMicrophoneMonitorStatus(tr("Couldn't open %1, listening to the system default input instead. Speak now.").arg(microphoneDevice));
    }
    else {
        setMicrophoneMonitorStatus(tr("Listening to %1. Speak now.").arg(m_MicrophoneMonitorDeviceLabel));
    }

    // Preview what the host will hear
    m_MicrophoneMonitorPending.clear();
    m_MicrophoneMonitorFilter.reset(micNoiseSuppression ? new MicNoiseFilter() : nullptr);

    m_MicrophoneMonitorTimer->start();
    SDL_PauseAudioDevice(m_MicrophoneMonitorDeviceId, 0);
    return true;
}

void StreamingPreferences::stopMicrophoneMonitor(const QString& status)
{
    if (m_MicrophoneMonitorTimer->isActive()) {
        m_MicrophoneMonitorTimer->stop();
    }

    if (m_MicrophoneMonitorDeviceId != 0) {
        SDL_PauseAudioDevice(m_MicrophoneMonitorDeviceId, 1);
        SDL_CloseAudioDevice(m_MicrophoneMonitorDeviceId);
        m_MicrophoneMonitorDeviceId = 0;
    }
    m_MicrophoneMonitorFilter.reset();

    if (m_MicrophoneMonitorHoldsAudio) {
        SDL_QuitSubSystem(SDL_INIT_AUDIO);
        m_MicrophoneMonitorHoldsAudio = false;
    }

    m_PendingMicrophonePeak.store(0, std::memory_order_release);
    if (m_MicrophoneMonitorLevel != 0.0) {
        m_MicrophoneMonitorLevel = 0.0;
        emit microphoneMonitorLevelChanged();
    }
    if (m_MicrophoneMonitorSignalDetected) {
        m_MicrophoneMonitorSignalDetected = false;
        emit microphoneMonitorSignalDetectedChanged();
    }
    if (!status.isNull()) {
        setMicrophoneMonitorStatus(status);
    }
}

void StreamingPreferences::processMicrophoneMonitorData(const Uint8* stream, int len)
{
    if (stream == nullptr || len <= 0) {
        return;
    }

    m_MicrophoneCallbackCount.fetch_add(1, std::memory_order_relaxed);

    const auto* samples = reinterpret_cast<const qint16*>(stream);
    const int sampleCount = len / static_cast<int>(sizeof(qint16));
    int peak = 0;
    auto measure = [&peak](const qint16* block, int count) {
        for (int i = 0; i < count; ++i) {
            const int sample = block[i] < 0 ? -block[i] : block[i];
            peak = qMax(peak, sample);
        }
    };

    if (m_MicrophoneMonitorFilter) {
        // The filter works in fixed blocks; carry any remainder to the next callback
        m_MicrophoneMonitorPending.insert(m_MicrophoneMonitorPending.end(), samples, samples + sampleCount);
        size_t filtered = 0;
        while (m_MicrophoneMonitorPending.size() - filtered >= MicNoiseFilter::kBlockSize) {
            int16_t* block = m_MicrophoneMonitorPending.data() + filtered;
            m_MicrophoneMonitorFilter->process(block, MicNoiseFilter::kBlockSize);
            measure(block, MicNoiseFilter::kBlockSize);
            filtered += MicNoiseFilter::kBlockSize;
        }
        m_MicrophoneMonitorPending.erase(m_MicrophoneMonitorPending.begin(), m_MicrophoneMonitorPending.begin() + filtered);
    }
    else {
        measure(samples, sampleCount);
    }

    int currentPeak = m_PendingMicrophonePeak.load(std::memory_order_acquire);
    while (peak > currentPeak &&
           !m_PendingMicrophonePeak.compare_exchange_weak(currentPeak, peak, std::memory_order_release, std::memory_order_acquire)) {
    }
}

void StreamingPreferences::updateMicrophoneMonitorState()
{
    const int peak = m_PendingMicrophonePeak.exchange(0, std::memory_order_acq_rel);
    const double instantaneousLevel = qBound(0.0, peak / 32767.0, 1.0);
    const double nextLevel = qMax(instantaneousLevel, m_MicrophoneMonitorLevel * 0.72);

    if (!qFuzzyCompare(nextLevel + 1.0, m_MicrophoneMonitorLevel + 1.0)) {
        m_MicrophoneMonitorLevel = nextLevel;
        emit microphoneMonitorLevelChanged();
    }

    const bool signalDetected = nextLevel >= 0.02;
    if (signalDetected != m_MicrophoneMonitorSignalDetected) {
        m_MicrophoneMonitorSignalDetected = signalDetected;
        emit microphoneMonitorSignalDetectedChanged();
    }

    if (peak > 0 && !m_MicrophoneSignalEverSeen) {
        m_MicrophoneSignalEverSeen = true;
        qInfo() << "Microphone test is receiving audio from" << m_MicrophoneMonitorDeviceLabel;
        setMicrophoneMonitorStatus(tr("Listening to %1.").arg(m_MicrophoneMonitorDeviceLabel));
    }

    // Explain the two ways a test can stay flat
    const qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - m_MicrophoneMonitorStartMs;
    if (!m_MicrophoneSignalEverSeen && elapsed > 3000) {
        const int callbacks = m_MicrophoneCallbackCount.load(std::memory_order_acquire);
        const QString status = callbacks == 0 ?
            tr("No audio is arriving from %1. Check that it's connected, or pick another input.").arg(m_MicrophoneMonitorDeviceLabel) :
#ifdef Q_OS_DARWIN
            tr("%1 is only sending silence. If other apps hear it, macOS is probably blocking Moonlight: turn it on in System Settings > Privacy & Security > Microphone.").arg(m_MicrophoneMonitorDeviceLabel);
#else
            tr("%1 is only sending silence. Check that it isn't muted.").arg(m_MicrophoneMonitorDeviceLabel);
#endif
        if (status != m_MicrophoneMonitorStatus) {
            qWarning() << "Microphone test:" << callbacks << "callbacks, all silent, after" << elapsed << "ms";
            setMicrophoneMonitorStatus(status);
        }
    }
}

void StreamingPreferences::setMicrophoneMonitorStatus(const QString& status)
{
    if (m_MicrophoneMonitorStatus != status) {
        m_MicrophoneMonitorStatus = status;
        emit microphoneMonitorStatusChanged();
    }
}

int StreamingPreferences::getDefaultBitrate(int width, int height, int fps, bool yuv444)
{
    // Don't scale bitrate linearly beyond 60 FPS. It's definitely not a linear
    // bitrate increase for frame rate once we get to values that high.
    float frameRateFactor = (fps <= 60 ? fps : (qSqrt(fps / 60.f) * 60.f)) / 30.f;

    // TODO: Collect some empirical data to see if these defaults make sense.
    // We're just using the values that the Shield used, as we have for years.
    static const struct resTable {
        int pixels;
        int factor;
    } resTable[] {
        { 640 * 360, 1 },
        { 854 * 480, 2 },
        { 1280 * 720, 5 },
        { 1920 * 1080, 10 },
        { 2560 * 1440, 20 },
        { 3840 * 2160, 40 },
        { -1, -1 },
    };

    // Calculate the resolution factor by linear interpolation of the resolution table
    float resolutionFactor;
    int pixels = width * height;
    for (int i = 0;; i++) {
        if (pixels == resTable[i].pixels) {
            // We can bail immediately for exact matches
            resolutionFactor = resTable[i].factor;
            break;
        }
        else if (pixels < resTable[i].pixels) {
            if (i == 0) {
                // Never go below the lowest resolution entry
                resolutionFactor = resTable[i].factor;
            }
            else {
                // Interpolate between the entry greater than the chosen resolution (i) and the entry less than the chosen resolution (i-1)
                resolutionFactor = ((float)(pixels - resTable[i-1].pixels) / (resTable[i].pixels - resTable[i-1].pixels)) * (resTable[i].factor - resTable[i-1].factor) + resTable[i-1].factor;
            }
            break;
        }
        else if (resTable[i].pixels == -1) {
            // Never go above the highest resolution entry
            resolutionFactor = resTable[i-1].factor;
            break;
        }
    }

    if (yuv444) {
        // This is rough estimation based on the fact that 4:4:4 doubles the amount of raw YUV data compared to 4:2:0
        resolutionFactor *= 2;
    }

    return qRound(resolutionFactor * frameRateFactor) * 1000;
}
