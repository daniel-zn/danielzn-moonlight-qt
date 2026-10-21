#pragma once

#include <QString>
#include <QStringList>

#include <cstdint>
#include <functional>
#include <memory>

// A microphone delivering 48 kHz mono 16-bit samples, for the stream (MicrophoneCapture) and
// the Test microphone meter. On macOS it's AVFoundation (AVCaptureSession), which follows the
// default input when it changes and survives device and format changes; elsewhere it's SDL.
// ARTEMIS_MIC_BACKEND=sdl picks SDL on macOS too (for comparing the two).
class MicInput
{
public:
    static constexpr int kSampleRate = 48000;

    // Runs on an audio thread with any number of samples
    using Callback = std::function<void(const int16_t* samples, int count)>;

    static std::unique_ptr<MicInput> create();

    // The inputs to choose from (names as the Settings page saves them)
    static QStringList deviceNames();

    virtual ~MicInput() = default;

    // deviceName empty: the system default input. A named input that can't be opened falls back to
    // the default (fellBack). False, with error, when no input could be opened. Delivery starts paused.
    virtual bool open(const QString& deviceName, Callback callback, QString* error, bool* fellBack) = 0;
    virtual void setRunning(bool running) = 0;

    // For the log: the backend and the input it's reading now
    virtual QString describe() const = 0;
};

// The SDL backend (used directly by MicInput::create() outside macOS)
namespace SdlMicInput
{
    std::unique_ptr<MicInput> create();
    QStringList deviceNames();
}
