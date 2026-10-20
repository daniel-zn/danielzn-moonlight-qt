# Moonlight PC

[Moonlight PC](https://moonlight-stream.org) is an open source PC client for NVIDIA GameStream and [Sunshine](https://github.com/LizardByte/Sunshine).

Moonlight also has mobile versions for [Android](https://github.com/moonlight-stream/moonlight-android) and [iOS](https://github.com/moonlight-stream/moonlight-ios).

You can follow development on our [Discord server](https://moonlight-stream.org/discord) and help translate Moonlight into your language on [Weblate](https://hosted.weblate.org/projects/moonlight/moonlight-qt/).

 [![Build](https://img.shields.io/github/actions/workflow/status/moonlight-stream/moonlight-qt/build.yml?branch=master)](https://github.com/moonlight-stream/moonlight-qt/actions/workflows/build.yml?query=branch%3Amaster)
 [![Downloads](https://img.shields.io/github/downloads/moonlight-stream/moonlight-qt/total)](https://github.com/moonlight-stream/moonlight-qt/releases)
 [![Translation Status](https://hosted.weblate.org/widgets/moonlight/-/moonlight-qt/svg-badge.svg)](https://hosted.weblate.org/projects/moonlight/moonlight-qt/)

## About this fork

> [!NOTE]
> This is a personal fork (`daniel-zn/danielzn-moonlight-qt`, default branch `main`) made to pair with
> [daniel-zn/danielzn-Apollo](https://github.com/daniel-zn/danielzn-Apollo). It doesn't follow upstream updates.

**On macOS the app is named Artemis** (`Artemis.app`, `Artemis.dmg`). It pairs with the iPhone app Artemis
([daniel-zn/danielzn-moonlight-ios](https://github.com/daniel-zn/danielzn-moonlight-ios)) and with Apollo hosts from
[daniel-zn/danielzn-Apollo](https://github.com/daniel-zn/danielzn-Apollo). It isn't affiliated with or endorsed by
the Moonlight project, or by the Artemis Android client. The Windows and Linux builds keep the name Moonlight.

- Updating from the Moonlight-named Mac build keeps everything: the bundle identifier stays
  `com.moonlight-stream.Moonlight` and the settings names stay those of Moonlight, so saved PCs, pairing certificates,
  settings and the window position carry over. Delete the old `Moonlight.app` after installing `Artemis.app`: with
  the same bundle identifier, macOS may open the old app instead.
- **The signature changed in October 2026, so macOS may need the microphone allowed again.** Builds before
  2026-10-17 were signed with an Apple Development certificate; releases since are Developer ID signed. macOS
  remembers microphone permission per signature, so the first time the new app uses the microphone macOS asks
  again (Local Network access too). If System Settings > Privacy & Security > Microphone shows Artemis switched on
  but Artemis says macOS blocks it, the switch belongs to the old signature: switch it off and on, or reset it in
  Terminal with `tccutil reset Microphone com.moonlight-stream.Moonlight`, then reopen Artemis and allow the
  microphone. (Artemis can't reset it itself: macOS keeps the old answer for a running app until it restarts.)
- The interface strings keep saying Moonlight in the source, so every translation still matches; on macOS a
  translator (`settings/streamingpreferences.cpp`) puts Artemis in their place. Names of upstream resources stay:
  the Help menu's Moonlight Setup Guide (it opens Moonlight's wiki), "the Moonlight help" and the Moonlight Internet
  Hosting Tool. Log files, crash dumps and command-line help also still say Moonlight.
- **Artemis is a screen-sharing app, so its macOS wording talks about apps and sessions**, not games and streams
  (the same words as the iPhone app): Apps, Connect, Active, Stop, Hidden apps, Controllers. The same
  translator rewords the English text on macOS only; other languages and the Windows and Linux builds keep
  upstream's wording.
- **The macOS interface font is Orbix** (Barry Shawn, Besign Foundry; SIL Open Font License 1.1, in `app/res/fonts`
  with its license, bundled in `Artemis.app/Contents/Resources/fonts`). Digits come from the system font, as in the
  iPhone app (Orbix's 1 reads as a 7): the app registers a copy of the font, in memory only, whose character map
  leaves out 0–9. Characters Orbix doesn't have (`:` `;` `(` `)` `+` `%` `…` and other symbols) come from the system
  font too. Window titles (Computers, Settings, a PC's name, and a session's window when it isn't full screen) are
  Orbix as well: the app hides AppKit's title and draws its own in the same place. The menu bar, the toolbar
  buttons, right-click menus, the About panel, permission prompts and the stream's statistics overlay keep the
  system's fonts.

What it adds on top of upstream Moonlight:

- **Microphone passthrough to the host.** The app captures your microphone and sends it to an Apollo host
  from [daniel-zn/danielzn-Apollo](https://github.com/daniel-zn/danielzn-Apollo), which plays it into
  `Microphone (Steam Streaming Microphone)` on the PC for games and voice chat.
  - Audio goes as 20 ms Opus frames over UDP, encrypted and authenticated with AES-GCM under the session key.
    The host advertises support with `a=x-apollo-mic:2`, so normal streaming to any other host is unaffected.
  - Settings > Audio Settings (Audio & Microphone on macOS): **Enable microphone streaming**, the input device, **Noise suppression**
    (macOS only: RNNoise plus a gate that mutes between words), and **Test microphone** with a level meter.
  - On macOS, turning the microphone on, **Test microphone** or a session with the microphone on asks for
    microphone permission (macOS's own prompt) if you haven't decided yet. If macOS blocks the microphone, a
    native alert says so, with **Open Privacy Settings** and **Cancel**. If the microphone can't be opened or
    sends only digital silence (a muted or unused input, or macOS blocking it), another alert says so, with
    **Open Privacy Settings**, **Open Sound Settings** and **Cancel**. They appear when you turn the microphone
    on or test it, and at most once per launch for sessions (before the session connects; for silence, after the
    session's window closes).
- **Native macOS look** (macOS only; Windows and Linux keep upstream's Material look, apart from tooltips now
  wrapping at 400 px as upstream intended):
  - A native toolbar with SF Symbols in the title bar, drawn on Liquid Glass on macOS 26 and later.
  - A translucent glass window and native macOS controls that follow light/dark mode and the accent color.
  - A compact window with lists instead of tiles: PCs with their status, and apps with a small artwork
    thumbnail and Resume/Stop on an active app.
  - Lists work like Finder: click selects, double-click (or Return) opens. Double-clicking a PC opens its apps,
    pairs it, or, if it's asleep, sends Wake-on-LAN and shows "Waking up…". Double-clicking an app connects to it
    or resumes it.
  - A real menu bar (Computer, App, Go, Help) with every action and its shortcut (⌘N add, ⌘O open, ⌘I info,
    ⌘R connect, ⌘[ back, ⌘, settings), and native right-click menus.
  - SF Symbol icons and rounded dialogs whose buttons say what they do (Remove, Stop, Add, Rename).
  - Settings laid out like System Settings: a sidebar of sections (Video & Display, Audio & Microphone,
    Keyboard & Mouse, Controllers, Host PC, General, Advanced), one section at a time.
    The window grows while Settings is open and returns to its size afterwards.
  - ⌘Q during a session disconnects and brings back the Artemis window, like closing the session's window; the
    app menu's Quit item reads Disconnect meanwhile. Dock ▸ Quit, logout and shutdown end the session and quit
    the app. Neither ends the app on the PC (Apollo keeps its virtual display).
  - Mac app conventions: the window reopens where you left it, About Artemis and Settings… are in the
    app menu, a Window menu has Minimize (⌘M) and Zoom, and pairing shows the PIN large.
- **Build changes:**
  - `qmake -r CONFIG+=ui_probe` builds in a UI self-test hook (`app/gui/uiprobe.*`, off in normal builds): with
    `MOONLIGHT_UI_PROBE=<script.qml>` the app runs that script, which can drive the UI, save window screenshots
    and quit, so the macOS UI can be checked without anyone at the screen.
  - `moonlight-common-c` (with the microphone protocol) is included directly instead of as a submodule.
  - macOS: a microphone usage description and audio-input entitlement. DMGs built without a signing identity are
    ad-hoc signed as a whole, so macOS can remember the microphone and Local Network permissions. Released DMGs are
    signed with a Developer ID (hardened runtime), notarized and stapled.

The microphone protocol isn't compatible with other microphone forks (logabell's, ApolloVibe, moonlight-mic).

## Features
 - Hardware accelerated video decoding on Windows, Mac, and Linux
 - H.264, HEVC, and AV1 codec support (AV1 requires Sunshine and a supported host GPU)
 - YUV 4:4:4 support (Sunshine only)
 - HDR streaming support
 - 7.1 surround sound audio support
 - 10-point multitouch support (Sunshine only)
 - Gamepad support with force feedback and motion controls for up to 16 players
 - Support for both pointer capture (for games) and direct mouse control (for remote desktop)
 - Support for passing system-wide keyboard shortcuts like Alt+Tab to the host
 
## Downloads
- [Windows, macOS, and Steam Link](https://github.com/moonlight-stream/moonlight-qt/releases)
- [Snap (for Ubuntu-based Linux distros)](https://snapcraft.io/moonlight)
- [Flatpak (for other Linux distros)](https://flathub.org/apps/details/com.moonlight_stream.Moonlight)
- [AppImage](https://github.com/moonlight-stream/moonlight-qt/releases)
- [Raspberry Pi 4 and 5](https://github.com/moonlight-stream/moonlight-docs/wiki/Installing-Moonlight-Qt-on-Raspberry-Pi-4)
- [Generic ARM 32-bit and 64-bit Debian packages](https://github.com/moonlight-stream/moonlight-docs/wiki/Installing-Moonlight-Qt-on-ARM%E2%80%90based-Single-Board-Computers) (not for Raspberry Pi)
- [Experimental RISC-V Debian packages](https://github.com/moonlight-stream/moonlight-docs/wiki/Installing-Moonlight-Qt-on-RISC%E2%80%90V-Single-Board-Computers)
- [NVIDIA Jetson and Nintendo Switch (Ubuntu L4T)](https://github.com/moonlight-stream/moonlight-docs/wiki/Installing-Moonlight-Qt-on-Linux4Tegra-(L4T)-Ubuntu)

### Nightly Builds
- [Downloads](https://nightly.link/moonlight-stream/moonlight-qt/workflows/build/master)

#### Special Thanks

[![Hosted By: Cloudsmith](https://img.shields.io/badge/OSS%20hosting%20by-cloudsmith-blue?logo=cloudsmith&style=flat-square)](https://cloudsmith.com)

Hosting for Moonlight's Debian and L4T package repositories is graciously provided for free by [Cloudsmith](https://cloudsmith.com).

## Building

### Windows Build Requirements
* Qt 6.11 SDK or later (earlier versions may work but are not officially supported)
* [Visual Studio 2026](https://visualstudio.microsoft.com/downloads/) (Community edition is fine)
* Select **MSVC** option during Qt installation. MinGW is not supported.
* [7-Zip](https://www.7-zip.org/) (only if building installers for non-development PCs)
* Graphics Tools (only if running debug builds)
  * Install "Graphics Tools" in the Optional Features page of the Windows Settings app.
  * Alternatively, run `dism /online /add-capability /capabilityname:Tools.Graphics.DirectX~~~~0.0.1.0` and reboot.

### macOS Build Requirements
* Qt 6.11 SDK or later (earlier versions may work but are not officially supported)
* Xcode 15 or later (earlier versions may work but are not officially supported)
* [create-dmg](https://github.com/sindresorhus/create-dmg) (only if building DMGs for use on non-development Macs)

### Linux/Unix Build Requirements
* Qt 6 is recommended, but Qt 5.12 or later is also supported (replace `qmake6` with `qmake` when using Qt 5).
* GCC or Clang
* FFmpeg 4.0 or later
* Install the required packages:
  * Debian/Ubuntu:
    * Base Requirements: `libegl1-mesa-dev libgl1-mesa-dev libopus-dev libsdl2-dev libsdl2-ttf-dev libssl-dev libavcodec-dev libavformat-dev libswscale-dev libva-dev libvdpau-dev libxkbcommon-dev wayland-protocols libdrm-dev`
    * Qt 6 (Recommended): `qt6-base-dev qt6-declarative-dev libqt6svg6-dev qt6-wayland qml6-module-qtquick-controls qml6-module-qtquick-templates qml6-module-qtquick-layouts qml6-module-qtqml-workerscript qml6-module-qtquick-window qml6-module-qtquick`
    * Qt 5: `qtbase5-dev qt5-qmake qtdeclarative5-dev qtquickcontrols2-5-dev qml-module-qtquick-controls2 qml-module-qtquick-layouts qml-module-qtquick-window2 qml-module-qtquick2 qtwayland5`
  * RedHat/Fedora (RPM Fusion repo required):
    * Base Requirements: `openssl-devel SDL2-devel SDL2_ttf-devel ffmpeg-devel libva-devel libvdpau-devel opus-devel pulseaudio-libs-devel alsa-lib-devel libdrm-devel`
    * Qt 6 (Recommended): `qt6-qtsvg-devel qt6-qtdeclarative-devel`
    * Qt 5: `qt5-qtsvg-devel qt5-qtquickcontrols2-devel`
* Building the Vulkan renderer requires a `libplacebo-dev`/`libplacebo-devel` version of at least v7.349.0 and FFmpeg 6.1 or later.

### Steam Link Build Requirements
* [Steam Link SDK](https://github.com/ValveSoftware/steamlink-sdk) cloned on your build system
* STEAMLINK_SDK_PATH environment variable set to the Steam Link SDK path

**Steam Link Hardware Limitations**  
Moonlight builds for Steam Link are subject to hardware limitations of the Steam Link device:
* Maximum resolution: **1080p (1920x1080)**
* Maximum framerate: **60 FPS**
* Maximum video bitrate: **40 Mbps**
* **HDR streaming is not supported** on the original hardware

### Docker containers
If you want to use Docker for building, look at [this repo](https://github.com/cgutman/moonlight-packaging) containing canonical containers
for different architectures, which handle building deps and extra linking for you.

### Build Setup Steps
1. Install the latest Qt SDK (and optionally, the Qt Creator IDE) from https://www.qt.io/download
    * You can install Qt via Homebrew on macOS, but you will need to use `brew install qt --with-debug` to be able to create debug builds of Moonlight.
    * You may also use your Linux distro's package manager for the Qt SDK as long as the packages are Qt 5.12 or later.
    * This step is not required for building on Steam Link, because the Steam Link SDK includes Qt 5.14.
2. Download submodules and dependencies
    * Run `git submodule update --init --recursive` from within `moonlight-qt/`.
    * On Windows and macOS, you must also run `setup-deps.ps1` (Windows) or `setup-deps.py` (macOS).
    * Perform these steps each time you pull new changes from the Git repository.
3. Open the project in Qt Creator or build from qmake on the command line.
    * To build a binary for use on non-development machines, use the scripts in the `scripts` folder.
        * For Windows builds, use `scripts\build-arch.bat` and `scripts\generate-bundle.bat`. Execute these scripts from the root of the repository within a Qt command prompt. Ensure  7-Zip binary directory is on your `%PATH%`.
        * For macOS builds, use `scripts/generate-dmg.sh`. Execute this script from the root of the repository and ensure Qt's `bin` folder is in your `$PATH`.
        * For Steam Link builds, run `scripts/build-steamlink-app.sh` from the root of the repository.
    * To build from the command line for development use on macOS or Linux, run `qmake6 moonlight-qt.pro` then `make debug` or `make release`.
        * The final binary will be placed in `app/moonlight`.
    * To create an embedded build for a single-purpose device, use `qmake6 "CONFIG+=embedded" moonlight-qt.pro` and build normally.
        * This build will lack windowed mode, Discord/Help links, and other features that don't make sense on an embedded device.
        * For platforms with poor GPU performance, add `"CONFIG+=gpuslow"` to prefer direct KMSDRM rendering over GL/Vulkan renderers. Direct KMSDRM rendering can use dedicated YUV/RGB conversion and scaling hardware rather than slower GPU shaders for these operations.

## Contribute
1. Fork us
2. Write code
3. Send Pull Requests

Check out our [website](https://moonlight-stream.org) for project links and information.
