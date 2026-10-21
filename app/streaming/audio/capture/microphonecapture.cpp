#include "microphonecapture.h"
#include "micpermission.h"

#include <algorithm>
#include <chrono>
#include <Limelight.h>
#include <SDL.h>

MicrophoneCapture::MicrophoneCapture(QObject* parent)
    : QObject(parent)
    , m_Encoder(nullptr)
    , m_Streaming(false)
    , m_StopEncoderThread(false)
    , m_Initialized(false)
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

    m_Input.reset();

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

    // Never a permission prompt over the stream: Session::start() asked before connecting
    if (MicPermission::status() != MicPermission::Status::Granted) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Microphone access hasn't been granted to Moonlight; streaming without the microphone");
        return false;
    }

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

    m_Input = MicInput::create();
    QString error;
    bool fellBack = false;
    if (!m_Input->open(QString::fromStdString(deviceName),
                       [this](const int16_t* samples, int count) { handleAudioData(samples, count); },
                       &error, &fellBack)) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Couldn't open the microphone for capture: %s",
                    error.toUtf8().constData());
        m_Input.reset();
        return false;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Microphone capture device: %s%s",
                m_Input->describe().toUtf8().constData(),
                fellBack ? " (the chosen input isn't available)" : "");

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
    if (!m_Enabled || !m_Initialized || !m_Input || !LiIsMicrophoneStreamActive()) {
        return false;
    }

    clearBufferedSamples();
    m_FirstPacketLogged = false;
    m_Streaming.store(true, std::memory_order_release);
    m_BufferCondition.notify_all();
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Microphone capture streaming started; negotiated mic stream is active");
    m_Input->setRunning(true);
    return true;
}

void MicrophoneCapture::stop()
{
    if (m_Input) {
        m_Input->setRunning(false);
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

void MicrophoneCapture::handleAudioData(const int16_t* inputSamples, int sampleCount)
{
    if (!m_Streaming.load(std::memory_order_acquire) || inputSamples == nullptr || sampleCount <= 0) {
        return;
    }

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
