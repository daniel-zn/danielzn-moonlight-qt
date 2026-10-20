#include "microphonecapture.h"
#include "micpermission.h"

#include <algorithm>
#include <chrono>
#include <Limelight.h>

MicrophoneCapture::MicrophoneCapture(QObject* parent)
    : QObject(parent)
    , m_DeviceId(0)
    , m_ObtainedSpec({})
    , m_Encoder(nullptr)
    , m_Streaming(false)
    , m_StopEncoderThread(false)
    , m_Initialized(false)
    , m_AudioSubsystemInitialized(false)
    , m_SendFailures(0)
    , m_Enabled(false)
    , m_FirstPacketLogged(false)
    , m_NoiseSuppression(false)
    , m_CapturedSamples(0)
    , m_HeardSignal(false)
{
}

MicrophoneCapture::~MicrophoneCapture()
{
    stop();

    m_StopEncoderThread.store(true, std::memory_order_release);
    m_BufferCondition.notify_all();
    if (m_EncoderThread.joinable()) {
        m_EncoderThread.join();
    }

    if (m_DeviceId != 0) {
        SDL_CloseAudioDevice(m_DeviceId);
        m_DeviceId = 0;
    }

    if (m_AudioSubsystemInitialized) {
        SDL_QuitSubSystem(SDL_INIT_AUDIO);
    }

    if (m_Encoder != nullptr) {
        opus_encoder_destroy(m_Encoder);
        m_Encoder = nullptr;
    }
}

bool MicrophoneCapture::initialize(const std::string& deviceName)
{
    if (m_Initialized) {
        return true;
    }

    // Don't pop a permission prompt over the stream. The Settings page asks
    // when the user turns microphone streaming on.
    if (MicPermission::status() != MicPermission::Status::Granted) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Microphone access hasn't been granted to Moonlight; streaming without the microphone");
        return false;
    }

    if (SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "SDL_InitSubSystem(SDL_INIT_AUDIO) failed for microphone capture: %s",
                    SDL_GetError());
        return false;
    }
    m_AudioSubsystemInitialized = true;

    int opusError = OPUS_OK;
    m_Encoder = opus_encoder_create(kSampleRate, kChannels, OPUS_APPLICATION_VOIP, &opusError);
    if (m_Encoder == nullptr || opusError != OPUS_OK) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "opus_encoder_create() failed for microphone capture: %s",
                    opus_strerror(opusError));
        return false;
    }

    opus_encoder_ctl(m_Encoder, OPUS_SET_BITRATE(kBitrate));
    opus_encoder_ctl(m_Encoder, OPUS_SET_VBR(1));
    opus_encoder_ctl(m_Encoder, OPUS_SET_COMPLEXITY(10));
    opus_encoder_ctl(m_Encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
    opus_encoder_ctl(m_Encoder, OPUS_SET_LSB_DEPTH(16));
    opus_encoder_ctl(m_Encoder, OPUS_SET_DTX(0));
    opus_encoder_ctl(m_Encoder, OPUS_SET_INBAND_FEC(1));
    opus_encoder_ctl(m_Encoder, OPUS_SET_PACKET_LOSS_PERC(5));
    opus_encoder_ctl(m_Encoder, OPUS_SET_EXPERT_FRAME_DURATION(OPUS_FRAMESIZE_20_MS));

    SDL_AudioSpec desired = {};
    desired.freq = kSampleRate;
    desired.format = AUDIO_S16SYS;
    desired.channels = kChannels;
    desired.samples = kFrameSize;
    desired.callback = &MicrophoneCapture::audioCallback;
    desired.userdata = this;

    const char* selectedDevice = deviceName.empty() ? nullptr : deviceName.c_str();
    m_DeviceId = SDL_OpenAudioDevice(selectedDevice, 1, &desired, &m_ObtainedSpec, 0);
    if (m_DeviceId == 0 && selectedDevice != nullptr) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "SDL_OpenAudioDevice() failed for requested microphone '%s': %s. Falling back to default input device.",
                    selectedDevice,
                    SDL_GetError());
        m_DeviceId = SDL_OpenAudioDevice(nullptr, 1, &desired, &m_ObtainedSpec, 0);
    }

    if (m_DeviceId == 0) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "SDL_OpenAudioDevice() failed for microphone capture: %s",
                    SDL_GetError());
        return false;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Microphone capture device: %s (%d Hz, %d channels, format 0x%x, %d sample callback target)",
                selectedDevice != nullptr ? selectedDevice : "<default>",
                m_ObtainedSpec.freq,
                m_ObtainedSpec.channels,
                m_ObtainedSpec.format,
                m_ObtainedSpec.samples);

    if (m_ObtainedSpec.freq != kSampleRate ||
            m_ObtainedSpec.channels != kChannels ||
            m_ObtainedSpec.format != AUDIO_S16SYS) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Microphone capture format mismatch: got %d Hz, %d channels, format 0x%x",
                    m_ObtainedSpec.freq,
                    m_ObtainedSpec.channels,
                    m_ObtainedSpec.format);
        return false;
    }

    if (m_ObtainedSpec.samples != kFrameSize) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Microphone capture backend is delivering %d-sample callbacks; outgoing Opus packets will be paced at %d-sample (%d ms) intervals",
                    m_ObtainedSpec.samples,
                    kFrameSize,
                    (kFrameSize * 1000) / kSampleRate);
    }

    SDL_PauseAudioDevice(m_DeviceId, 1);
    if (m_NoiseSuppression) {
        m_NoiseFilter = std::make_unique<MicNoiseFilter>();
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Microphone noise suppression %s", m_NoiseFilter ? "enabled" : "disabled");
    m_SampleBuffer.reserve(kFrameSize * 4);
    m_StopEncoderThread.store(false, std::memory_order_release);
    m_EncoderThread = std::thread(&MicrophoneCapture::encoderLoop, this);
    m_Initialized = true;
    return true;
}

bool MicrophoneCapture::start()
{
    if (!m_Enabled || !m_Initialized || m_DeviceId == 0 || !LiIsMicrophoneStreamActive()) {
        return false;
    }

    clearBufferedSamples();
    m_FirstPacketLogged = false;
    m_Streaming.store(true, std::memory_order_release);
    m_BufferCondition.notify_all();
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Microphone capture streaming started; negotiated mic stream is active");
    SDL_PauseAudioDevice(m_DeviceId, 0);
    return true;
}

void MicrophoneCapture::stop()
{
    if (m_DeviceId != 0) {
        SDL_PauseAudioDevice(m_DeviceId, 1);
    }

    m_Streaming.store(false, std::memory_order_release);
    clearBufferedSamples();
    m_BufferCondition.notify_all();
}

bool MicrophoneCapture::heardOnlySilence() const
{
    return !m_HeardSignal.load(std::memory_order_relaxed) &&
           m_CapturedSamples.load(std::memory_order_relaxed) >= (int64_t)kSampleRate * kChannels * 3;
}

void MicrophoneCapture::setNoiseSuppression(bool enabled)
{
    m_NoiseSuppression = enabled;
}

void MicrophoneCapture::setEnabled(bool enabled)
{
    m_Enabled = enabled;
    if (!m_Enabled) {
        stop();
    }
}

void MicrophoneCapture::audioCallback(void* userdata, Uint8* stream, int len)
{
    auto* capture = static_cast<MicrophoneCapture*>(userdata);
    if (capture != nullptr) {
        capture->handleAudioData(stream, len);
    }
}

void MicrophoneCapture::handleAudioData(const Uint8* stream, int len)
{
    if (!m_Streaming.load(std::memory_order_acquire) || stream == nullptr || len <= 0) {
        return;
    }

    const auto* inputSamples = reinterpret_cast<const opus_int16*>(stream);
    const int sampleCount = len / (int)sizeof(opus_int16);

    m_CapturedSamples.fetch_add(sampleCount, std::memory_order_relaxed);
    if (!m_HeardSignal.load(std::memory_order_relaxed) &&
            std::any_of(inputSamples, inputSamples + sampleCount, [](opus_int16 sample) { return sample != 0; })) {
        m_HeardSignal.store(true, std::memory_order_relaxed);
    }

    {
        std::lock_guard lock(m_BufferMutex);
        m_SampleBuffer.insert(m_SampleBuffer.end(), inputSamples, inputSamples + sampleCount);
        constexpr size_t maxBufferedSamples = kFrameSize * 12;
        if (m_SampleBuffer.size() > maxBufferedSamples) {
            const auto trimSamples = m_SampleBuffer.size() - maxBufferedSamples;
            m_SampleBuffer.erase(m_SampleBuffer.begin(), m_SampleBuffer.begin() + trimSamples);
        }
    }
    m_BufferCondition.notify_one();
}

void MicrophoneCapture::encoderLoop()
{
    std::vector<opus_int16> frame(kFrameSize);

    // Frames go out as soon as they're captured. Pacing them to one per 20 ms would keep any
    // backlog (after a stall, or from a mic clock running slightly fast) as permanent delay;
    // the host's jitter buffer smooths the bursts instead.

    for (;;) {
        {
            std::unique_lock lock(m_BufferMutex);
            m_BufferCondition.wait(lock, [this] {
                return m_StopEncoderThread.load(std::memory_order_acquire) ||
                       (m_Streaming.load(std::memory_order_acquire) && m_SampleBuffer.size() >= (size_t)kFrameSize);
            });

            if (m_StopEncoderThread.load(std::memory_order_acquire)) {
                break;
            }

            if (!m_Streaming.load(std::memory_order_acquire) || m_SampleBuffer.size() < (size_t)kFrameSize) {
                continue;
            }

            std::copy_n(m_SampleBuffer.begin(), kFrameSize, frame.begin());
            m_SampleBuffer.erase(m_SampleBuffer.begin(), m_SampleBuffer.begin() + kFrameSize);
        }

        if (m_NoiseFilter) {
            m_NoiseFilter->process(frame.data(), kFrameSize);
        }

        int encodedBytes = opus_encode(m_Encoder,
                                       frame.data(),
                                       kFrameSize,
                                       m_EncodedPacket.data(),
                                       (opus_int32)m_EncodedPacket.size());
        if (encodedBytes <= 0) {
            continue;
        }

        int sendResult = LiSendMicrophoneOpusDataEx(m_EncodedPacket.data(), encodedBytes, kFrameSize);
        if (sendResult >= 0 && !m_FirstPacketLogged) {
            m_FirstPacketLogged = true;
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                        "Sent first client microphone packet (%d bytes Opus)",
                        encodedBytes);
        }
        else if (sendResult < 0) {
            // Log the first failure and then every 5 seconds' worth of packets
            if (m_SendFailures++ % 250 == 0) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "Sending microphone audio failed (%d times so far)",
                            m_SendFailures);
            }
        }
    }
}

void MicrophoneCapture::clearBufferedSamples()
{
    {
        std::lock_guard lock(m_BufferMutex);
        m_SampleBuffer.clear();
    }
}
