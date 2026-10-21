#include "micinput.h"

#include <SDL.h>

namespace
{
    class SdlInput : public MicInput
    {
    public:
        ~SdlInput() override
        {
            if (m_DeviceId != 0) {
                SDL_CloseAudioDevice(m_DeviceId);
            }
            if (m_AudioInitialized) {
                SDL_QuitSubSystem(SDL_INIT_AUDIO);
            }
        }

        bool open(const QString& deviceName, Callback callback, QString* error, bool* fellBack) override
        {
            *fellBack = false;
            if (SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
                *error = QString::fromUtf8(SDL_GetError());
                return false;
            }
            m_AudioInitialized = true;
            m_Callback = std::move(callback);

            SDL_AudioSpec desired = {};
            desired.freq = kSampleRate;
            desired.format = AUDIO_S16SYS;
            desired.channels = 1;
            desired.samples = 960;
            desired.callback = &SdlInput::audioCallback;
            desired.userdata = this;

            const QByteArray name = deviceName.toUtf8();
            m_DeviceId = SDL_OpenAudioDevice(name.isEmpty() ? nullptr : name.constData(), 1, &desired, &m_Spec, 0);
            if (m_DeviceId == 0 && !name.isEmpty()) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "SDL_OpenAudioDevice() failed for requested microphone '%s': %s. Falling back to default input device.",
                            name.constData(), SDL_GetError());
                m_DeviceId = SDL_OpenAudioDevice(nullptr, 1, &desired, &m_Spec, 0);
                *fellBack = m_DeviceId != 0;
            }
            if (m_DeviceId == 0) {
                *error = QString::fromUtf8(SDL_GetError());
                return false;
            }
            if (m_Spec.freq != kSampleRate || m_Spec.channels != 1 || m_Spec.format != AUDIO_S16SYS) {
                *error = QString("unsupported format: %1 Hz, %2 channels, format 0x%3")
                             .arg(m_Spec.freq).arg(m_Spec.channels).arg(m_Spec.format, 0, 16);
                return false;
            }
            m_Name = (name.isEmpty() || *fellBack) ? QString("<default>") : deviceName;
            return true;
        }

        void setRunning(bool running) override
        {
            if (m_DeviceId != 0) {
                SDL_PauseAudioDevice(m_DeviceId, running ? 0 : 1);
            }
        }

        QString describe() const override
        {
            return QString("SDL: %1 (%2 Hz, %3 ch, %4 sample callbacks)")
                .arg(m_Name).arg(m_Spec.freq).arg(m_Spec.channels).arg(m_Spec.samples);
        }

    private:
        static void audioCallback(void* userdata, Uint8* stream, int len)
        {
            auto* self = static_cast<SdlInput*>(userdata);
            if (stream != nullptr && len > 0) {
                self->m_Callback(reinterpret_cast<const int16_t*>(stream), len / (int)sizeof(int16_t));
            }
        }

        SDL_AudioDeviceID m_DeviceId = 0;
        SDL_AudioSpec m_Spec = {};
        bool m_AudioInitialized = false;
        Callback m_Callback;
        QString m_Name;
    };
}

std::unique_ptr<MicInput> SdlMicInput::create()
{
    return std::make_unique<SdlInput>();
}

QStringList SdlMicInput::deviceNames()
{
    const bool audioWasInitialized = SDL_WasInit(SDL_INIT_AUDIO) != 0;
    if (!audioWasInitialized && SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Failed to initialize SDL audio for microphone enumeration: %s", SDL_GetError());
        return {};
    }

    QStringList devices;
    const int deviceCount = SDL_GetNumAudioDevices(SDL_TRUE);
    for (int i = 0; i < deviceCount; ++i) {
        const char* name = SDL_GetAudioDeviceName(i, SDL_TRUE);
        if (name != nullptr && *name != '\0' && !devices.contains(QString::fromUtf8(name))) {
            devices.append(QString::fromUtf8(name));
        }
    }

    if (!audioWasInitialized) {
        SDL_QuitSubSystem(SDL_INIT_AUDIO);
    }
    return devices;
}

#ifndef Q_OS_DARWIN
std::unique_ptr<MicInput> MicInput::create()
{
    return SdlMicInput::create();
}

QStringList MicInput::deviceNames()
{
    return SdlMicInput::deviceNames();
}
#endif
