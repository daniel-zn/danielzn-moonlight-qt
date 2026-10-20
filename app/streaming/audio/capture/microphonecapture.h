#pragma once

#include <QObject>
#include <atomic>
#include <array>
#include <memory>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <SDL.h>
#include <opus.h>

#include "micnoisefilter.h"

class MicrophoneCapture : public QObject
{
    Q_OBJECT

public:
    explicit MicrophoneCapture(QObject* parent = nullptr);
    ~MicrophoneCapture() override;

    bool initialize(const std::string& deviceName = {});
    bool start();
    void stop();

    void setEnabled(bool enabled);
    // Call before initialize()
    void setNoiseSuppression(bool enabled);

    // True when at least 3 seconds were captured and every sample was exactly zero:
    // how macOS hands over a microphone it blocks
    bool heardOnlySilence() const;

private:
    static void audioCallback(void* userdata, Uint8* stream, int len);
    void handleAudioData(const Uint8* stream, int len);
    void clearBufferedSamples();
    void encoderLoop();

    SDL_AudioDeviceID m_DeviceId;
    SDL_AudioSpec m_ObtainedSpec;
    OpusEncoder* m_Encoder;
    std::vector<opus_int16> m_SampleBuffer;
    std::array<unsigned char, 1400> m_EncodedPacket;
    std::atomic_bool m_Streaming;
    std::atomic_bool m_StopEncoderThread;
    bool m_Initialized;
    bool m_AudioSubsystemInitialized;
    int m_SendFailures;
    bool m_Enabled;
    bool m_FirstPacketLogged;
    bool m_NoiseSuppression;
    std::atomic<int64_t> m_CapturedSamples;  // Since the device opened, before noise suppression
    std::atomic_bool m_HeardSignal;
    std::unique_ptr<MicNoiseFilter> m_NoiseFilter;  // Encoder thread only
    std::mutex m_BufferMutex;
    std::condition_variable m_BufferCondition;
    std::thread m_EncoderThread;

    static constexpr int kSampleRate = 48000;
    static constexpr int kChannels = 1;
    static constexpr int kFrameSize = 960;
    static_assert(kFrameSize % MicNoiseFilter::kBlockSize == 0, "frames must hold whole filter blocks");
    static constexpr int kBitrate = 64000;
};
