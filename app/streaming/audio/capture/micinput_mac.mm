#include "micinput.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudio.h>

#include <QDebug>

#include <Block.h>

#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <vector>

// The microphone on macOS through AVFoundation. AVCaptureAudioDataOutput converts whatever rate
// the input runs at (Bluetooth headsets switching profiles included) to 48 kHz 16-bit with the
// input's own channels, which are mixed down to mono here: a microphone on the second channel of
// an interface is heard too (SDL kept only the first). Without a named input it follows the system
// default input; a named input that's unplugged falls back to the default until it's back. (Manual retain/release, like the
// rest of the app's Objective-C++.)

class MacInput;

@interface ArtemisMicReceiver : NSObject <AVCaptureAudioDataOutputSampleBufferDelegate>
{
@public
    MacInput* owner;
}
@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static NSArray<AVCaptureDevice*>* audioDevices()
{
    // devicesWithMediaType: lists every input (built-in, USB, Bluetooth, virtual) on every macOS
    // Artemis supports; its replacement needs the per-release device types
    return [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
}
#pragma clang diagnostic pop

static AVCaptureDevice* systemDefaultInput()
{
    AudioObjectPropertyAddress addr = { kAudioHardwarePropertyDefaultInputDevice,
                                        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioDeviceID deviceId = kAudioObjectUnknown;
    UInt32 size = sizeof(deviceId);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, nullptr, &size, &deviceId) == noErr &&
            deviceId != kAudioObjectUnknown) {
        CFStringRef uid = nullptr;
        size = sizeof(uid);
        addr.mSelector = kAudioDevicePropertyDeviceUID;
        if (AudioObjectGetPropertyData(deviceId, &addr, 0, nullptr, &size, &uid) == noErr && uid != nullptr) {
            AVCaptureDevice* device = [AVCaptureDevice deviceWithUniqueID:(__bridge NSString*)uid];
            CFRelease(uid);
            if (device != nil) {
                return device;
            }
        }
    }
    return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
}

// The input's channel count from CoreAudio (an AVCaptureDevice's uniqueID is its CoreAudio UID); 0 if unknown
static UInt32 inputChannels(AVCaptureDevice* device)
{
    CFStringRef uid = (__bridge CFStringRef)device.uniqueID;
    AudioDeviceID deviceId = kAudioObjectUnknown;
    AudioValueTranslation translation = { &uid, sizeof(uid), &deviceId, sizeof(deviceId) };
    AudioObjectPropertyAddress addr = { kAudioHardwarePropertyDeviceForUID,
                                        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    UInt32 size = sizeof(translation);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, nullptr, &size, &translation) != noErr ||
            deviceId == kAudioObjectUnknown) {
        return 0;
    }

    addr = { kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeInput, kAudioObjectPropertyElementMain };
    if (AudioObjectGetPropertyDataSize(deviceId, &addr, 0, nullptr, &size) != noErr || size == 0) {
        return 0;
    }
    std::vector<uint8_t> storage(size);
    auto* buffers = reinterpret_cast<AudioBufferList*>(storage.data());
    if (AudioObjectGetPropertyData(deviceId, &addr, 0, nullptr, &size, buffers) != noErr) {
        return 0;
    }
    UInt32 channels = 0;
    for (UInt32 i = 0; i < buffers->mNumberBuffers; ++i) {
        channels += buffers->mBuffers[i].mNumberChannels;
    }
    return channels;
}

static AVCaptureDevice* inputNamed(const QString& name)
{
    for (AVCaptureDevice* device in audioDevices()) {
        if (QString::fromNSString(device.localizedName) == name) {
            return device;
        }
    }
    return nil;
}

class MacInput : public MicInput
{
public:
    MacInput()
    {
        m_Control = dispatch_queue_create("com.moonlight-stream.Moonlight.mic", DISPATCH_QUEUE_SERIAL);
        m_Data = dispatch_queue_create("com.moonlight-stream.Moonlight.mic-data", DISPATCH_QUEUE_SERIAL);
        m_Receiver = [[ArtemisMicReceiver alloc] init];
        m_Receiver->owner = this;
    }

    ~MacInput() override
    {
        if (m_DefaultListener != nil) {
            AudioObjectPropertyAddress addr = { kAudioHardwarePropertyDefaultInputDevice,
                                                kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
            AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &addr, m_Control, m_DefaultListener);
            Block_release(m_DefaultListener);
        }
        for (id observer : m_Observers) {
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            [observer release];
        }
        dispatch_sync(m_Control, ^{
            m_Closed = true;
            *m_Alive = false;
            [m_Session stopRunning];
            [m_Output setSampleBufferDelegate:nil queue:nil];
        });
        // Let a buffer already being delivered finish before this object goes away
        dispatch_sync(m_Data, ^{});
        [m_Input release];
        [m_Device release];
        [m_Output release];
        [m_Session release];
        [m_Receiver release];
        dispatch_release(m_Data);
        dispatch_release(m_Control);
    }

    bool open(const QString& deviceName, Callback callback, QString* error, bool* fellBack) override
    {
        m_Callback = std::move(callback);
        m_WantedName = deviceName;
        *fellBack = false;

        AVCaptureDevice* device = nil;
        if (!deviceName.isEmpty()) {
            device = inputNamed(deviceName);
            if (device == nil) {
                qWarning() << "Microphone" << deviceName << "isn't connected; using the system default input";
                *fellBack = true;
            }
        }
        if (device == nil) {
            device = systemDefaultInput();
        }
        if (device == nil) {
            *error = QStringLiteral("no microphone is connected");
            return false;
        }

        __block bool ok = false;
        __block QString failure;
        dispatch_sync(m_Control, ^{
            m_Session = [[AVCaptureSession alloc] init];
            m_Output = [[AVCaptureAudioDataOutput alloc] init];
            [m_Output setSampleBufferDelegate:m_Receiver queue:m_Data];
            if (![m_Session canAddOutput:m_Output]) {
                failure = QStringLiteral("the capture session refused the audio output");
                return;
            }
            [m_Session addOutput:m_Output];
            ok = useDevice(device, &failure);
            if (!ok && !deviceName.isEmpty() && !*fellBack) {
                // The named input is there but won't open: the default stands in
                AVCaptureDevice* fallback = systemDefaultInput();
                if (fallback != nil && ![fallback.uniqueID isEqualToString:device.uniqueID]) {
                    ok = useDevice(fallback, &failure);
                    *fellBack = ok;
                }
            }
        });
        if (!ok) {
            *error = failure;
            return false;
        }

        // Follow the system default input (and come back to a named one when it's plugged in again)
        AudioObjectPropertyAddress addr = { kAudioHardwarePropertyDefaultInputDevice,
                                            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        m_DefaultListener = Block_copy(^(UInt32, const AudioObjectPropertyAddress*) {
            if (!m_Closed && (m_WantedName.isEmpty() || m_FollowingDefault)) {
                AVCaptureDevice* next = systemDefaultInput();
                if (next != nil && ![next.uniqueID isEqualToString:m_Device.uniqueID]) {
                    qInfo() << "Microphone: the system default input is now" << QString::fromNSString(next.localizedName);
                    QString ignored;
                    useDevice(next, &ignored);
                }
            }
        });
        AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &addr, m_Control, m_DefaultListener);

        NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
        m_Observers.push_back([[center addObserverForName:AVCaptureDeviceWasDisconnectedNotification object:nil queue:nil
                                              usingBlock:^(NSNotification* note) {
            dispatch_async(m_Control, ^{
                if (!m_Closed && [((AVCaptureDevice*)note.object).uniqueID isEqualToString:m_Device.uniqueID]) {
                    qWarning() << "Microphone" << QString::fromNSString(m_Device.localizedName)
                               << "was disconnected; using the system default input";
                    AVCaptureDevice* next = systemDefaultInput();
                    QString ignored;
                    if (next != nil && useDevice(next, &ignored)) {
                        m_FollowingDefault = !m_WantedName.isEmpty();
                    }
                }
            });
        }] retain]);
        m_Observers.push_back([[center addObserverForName:AVCaptureDeviceWasConnectedNotification object:nil queue:nil
                                              usingBlock:^(NSNotification* note) {
            AVCaptureDevice* device = note.object;
            dispatch_async(m_Control, ^{
                if (!m_Closed && m_FollowingDefault && [device hasMediaType:AVMediaTypeAudio] &&
                        QString::fromNSString(device.localizedName) == m_WantedName) {
                    qInfo() << "Microphone" << m_WantedName << "is back";
                    QString ignored;
                    if (useDevice(device, &ignored)) {
                        m_FollowingDefault = false;
                    }
                }
            });
        }] retain]);
        m_Observers.push_back([[center addObserverForName:AVCaptureSessionRuntimeErrorNotification object:m_Session queue:nil
                                              usingBlock:^(NSNotification* note) {
            NSError* err = note.userInfo[AVCaptureSessionErrorKey];
            qWarning() << "Microphone capture error:" << QString::fromNSString(err.localizedDescription);
            // Start again a moment later (the device may be reconfiguring), unless this is gone by then
            std::shared_ptr<bool> alive = m_Alive;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), m_Control, ^{
                if (*alive && m_Running && !m_Session.running) {
                    [m_Session startRunning];
                }
            });
        }] retain]);

        m_FollowingDefault = *fellBack;
        return true;
    }

    void setRunning(bool running) override
    {
        dispatch_async(m_Control, ^{
            m_Running = running;
            if (m_Closed) {
                return;
            }
            if (running && !m_Session.running) {
                [m_Session startRunning];
            }
            else if (!running && m_Session.running) {
                [m_Session stopRunning];
            }
        });
    }

    QString describe() const override
    {
        __block QString text;
        dispatch_sync(m_Control, ^{
            text = QString("AVFoundation: %1%2").arg(m_DeviceName, m_FollowingDefault || m_WantedName.isEmpty() ? " (the system default input)" : "");
        });
        return text;
    }

    // On the data queue
    void deliver(CMSampleBufferRef buffer)
    {
        CMAudioFormatDescriptionRef format = CMSampleBufferGetFormatDescription(buffer);
        const AudioStreamBasicDescription* asbd = format ? CMAudioFormatDescriptionGetStreamBasicDescription(format) : nullptr;
        if (asbd == nullptr) {
            return;
        }
        if (!m_FormatLogged.exchange(true)) {
            qInfo() << "Microphone delivers" << asbd->mSampleRate << "Hz," << asbd->mChannelsPerFrame << "channel(s),"
                    << asbd->mBitsPerChannel << "bit" << ((asbd->mFormatFlags & kAudioFormatFlagIsFloat) ? "float" : "integer");
        }

        AudioBufferList list;
        CMBlockBufferRef block = nullptr;
        if (CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(buffer, nullptr, &list, sizeof(list), nullptr, nullptr,
                                                                    kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                                                                    &block) != noErr) {
            return;
        }

        const AudioBuffer& audio = list.mBuffers[0];
        const bool isFloat = (asbd->mFormatFlags & kAudioFormatFlagIsFloat) != 0;
        const UInt32 channels = asbd->mChannelsPerFrame > 0 ? asbd->mChannelsPerFrame : 1;
        if (!isFloat && asbd->mBitsPerChannel == 16 && channels == 1) {
            m_Callback(static_cast<const int16_t*>(audio.mData), (int)(audio.mDataByteSize / sizeof(int16_t)));
        }
        else if (list.mNumberBuffers == 1 && (isFloat ? asbd->mBitsPerChannel == 32 : asbd->mBitsPerChannel == 16)) {
            // Mix the channels down to mono: the average of the channels carrying anything in this
            // buffer, so an unused (digitally silent) channel doesn't halve the microphone
            const UInt32 frames = audio.mDataByteSize / (asbd->mBitsPerChannel / 8) / channels;
            auto sample = [&](UInt32 i, UInt32 c) {
                return isFloat ? static_cast<const float*>(audio.mData)[i * channels + c] * 32767.f
                               : (float)static_cast<const int16_t*>(audio.mData)[i * channels + c];
            };
            UInt32 active = 0;
            uint64_t activeMask = 0;
            for (UInt32 c = 0; c < channels && c < 64; ++c) {
                for (UInt32 i = 0; i < frames; ++i) {
                    if (sample(i, c) != 0) {
                        activeMask |= 1ull << c;
                        active++;
                        break;
                    }
                }
            }
            m_Converted.resize(frames);
            for (UInt32 i = 0; i < frames; ++i) {
                float sum = 0;
                for (UInt32 c = 0; c < channels && c < 64; ++c) {
                    if (activeMask & (1ull << c)) {
                        sum += sample(i, c);
                    }
                }
                m_Converted[i] = (int16_t)std::max(-32768.f, std::min(32767.f, active > 0 ? sum / active : 0.f));
            }
            m_Callback(m_Converted.data(), (int)frames);
        }
        CFRelease(block);
    }

private:
    // On the control queue
    bool useDevice(AVCaptureDevice* device, QString* failure)
    {
        NSError* err = nil;
        AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&err];
        if (input == nil) {
            *failure = QString::fromNSString(err.localizedDescription);
            qWarning() << "Microphone: couldn't open" << QString::fromNSString(device.localizedName) << ":" << *failure;
            return false;
        }
        // 48 kHz 16-bit, as many channels as the input has (mixed down in deliver())
        UInt32 channels = inputChannels(device);
        for (AVCaptureInputPort* port in channels == 0 ? input.ports : @[]) {
            const AudioStreamBasicDescription* asbd = port.formatDescription ?
                CMAudioFormatDescriptionGetStreamBasicDescription(port.formatDescription) : nullptr;
            if (asbd != nullptr && [port.mediaType isEqualToString:AVMediaTypeAudio]) {
                channels = asbd->mChannelsPerFrame;
                break;
            }
        }
        channels = std::max<UInt32>(1, channels);
        NSMutableDictionary* settings = [NSMutableDictionary dictionaryWithDictionary:@{
            AVFormatIDKey: @(kAudioFormatLinearPCM),
            AVSampleRateKey: @(kSampleRate),
            AVNumberOfChannelsKey: @(channels),
            AVLinearPCMBitDepthKey: @16,
            AVLinearPCMIsFloatKey: @NO,
            AVLinearPCMIsBigEndianKey: @NO,
            AVLinearPCMIsNonInterleaved: @NO,
        }];
        if (channels > 2) {
            AudioChannelLayout layout = {};
            layout.mChannelLayoutTag = kAudioChannelLayoutTag_DiscreteInOrder | channels;
            settings[AVChannelLayoutKey] = [NSData dataWithBytes:&layout length:sizeof(layout)];
        }

        [m_Session beginConfiguration];
        @try {
            m_Output.audioSettings = settings;
        }
        @catch (NSException* e) {
            qWarning() << "Microphone: AVFoundation refused" << channels << "channels ("
                       << QString::fromNSString(e.reason) << "); asking for mono";
            settings[AVNumberOfChannelsKey] = @1;
            [settings removeObjectForKey:AVChannelLayoutKey];
            m_Output.audioSettings = settings;
        }
        if (m_Input != nil) {
            [m_Session removeInput:m_Input];
        }
        if (![m_Session canAddInput:input]) {
            if (m_Input != nil) {
                [m_Session addInput:m_Input];
            }
            [m_Session commitConfiguration];
            *failure = QStringLiteral("the capture session refused %1").arg(QString::fromNSString(device.localizedName));
            return false;
        }
        [m_Session addInput:input];
        [m_Session commitConfiguration];
        [m_Input release];
        m_Input = [input retain];
        [m_Device release];
        m_Device = [device retain];
        m_DeviceName = QString::fromNSString(device.localizedName);
        m_FormatLogged = false;
        qInfo() << "Microphone input:" << m_DeviceName << "(" << channels << "channel(s) )";
        return true;
    }

    dispatch_queue_t m_Control;
    dispatch_queue_t m_Data;
    ArtemisMicReceiver* m_Receiver;
    AVCaptureSession* m_Session = nil;
    AVCaptureAudioDataOutput* m_Output = nil;
    AVCaptureDeviceInput* m_Input = nil;
    AVCaptureDevice* m_Device = nil;
    AudioObjectPropertyListenerBlock m_DefaultListener = nil;
    std::vector<id> m_Observers;
    Callback m_Callback;
    QString m_WantedName;
    QString m_DeviceName;
    bool m_FollowingDefault = false;  // a named input is missing, so the default stands in
    bool m_Running = false;
    bool m_Closed = false;
    std::shared_ptr<bool> m_Alive = std::make_shared<bool>(true);  // Control queue only
    std::atomic_bool m_FormatLogged { false };
    std::vector<int16_t> m_Converted;  // Data queue only
};

@implementation ArtemisMicReceiver
- (void)captureOutput:(AVCaptureOutput*)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection*)connection
{
    (void)output;
    (void)connection;
    owner->deliver(sampleBuffer);
}
@end

static bool useSdl()
{
    const char* backend = getenv("ARTEMIS_MIC_BACKEND");
    return backend != nullptr && strcmp(backend, "sdl") == 0;
}

std::unique_ptr<MicInput> MicInput::create()
{
    if (useSdl()) {
        return SdlMicInput::create();
    }
    return std::make_unique<MacInput>();
}

QStringList MicInput::deviceNames()
{
    if (useSdl()) {
        return SdlMicInput::deviceNames();
    }
    QStringList names;
    for (AVCaptureDevice* device in audioDevices()) {
        const QString name = QString::fromNSString(device.localizedName);
        if (!name.isEmpty() && !names.contains(name)) {
            names.append(name);
        }
    }
    return names;
}
