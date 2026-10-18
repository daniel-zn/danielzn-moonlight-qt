#pragma once

class QScreen;
class QWindow;

// Auto frame rate (macOS): each session asks the host for the refresh rate of the
// display the Artemis window is on, so the host's virtual display follows it.
namespace AutoFrameRate
{
    // Rounds a display's refresh rate to the frame rate to request: a standard
    // rate when it's within 2% (59.94 -> 60, 119.88 -> 120, 143.9 -> 144),
    // otherwise the nearest whole number, from 30 up to 480 (the command line's
    // limit). An unknown rate (0 or less) gives 60.
    int fromRefreshRate(double hz);

    // A screen's refresh rate from Qt's reading (can be the current rate of a
    // ProMotion or variable refresh display) and AppKit's maximum (0 if unknown):
    // the higher one.
    double highestReading(double qtRate, double appKitMaximum);

    // The highest refresh rate of a screen in Hz (the maximum for ProMotion and
    // variable refresh displays), or 0 if unknown.
    double maximumRefreshRate(QScreen* screen);

    // The frame rate to request for a session started from this window: the
    // screen it's on (where the stream window opens). 60 without a screen.
    int forWindow(QWindow* window);
}
