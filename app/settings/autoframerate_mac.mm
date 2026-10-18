#include "autoframerate.h"

#include <QScreen>

#import <AppKit/AppKit.h>

namespace AutoFrameRate
{

// NSScreen's maximumFramesPerSecond is the top of a ProMotion or variable refresh
// range (QScreen::refreshRate can report the current rate instead). The NSScreen
// is the one whose bounds match the QScreen's geometry: both are in points with
// the origin at the top left of the main display.
double maximumRefreshRate(QScreen* screen)
{
    if (screen == nullptr) {
        return 0;
    }

    double qtRate = screen->refreshRate();
    QRect geometry = screen->geometry();
    for (NSScreen* nsScreen in [NSScreen screens]) {
        NSNumber* number = nsScreen.deviceDescription[@"NSScreenNumber"];
        if (number == nil) {
            continue;
        }

        CGRect bounds = CGDisplayBounds((CGDirectDisplayID)number.unsignedIntValue);
        if (qRound(bounds.origin.x) == geometry.x() && qRound(bounds.origin.y) == geometry.y() &&
                qRound(bounds.size.width) == geometry.width() && qRound(bounds.size.height) == geometry.height()) {
            return highestReading(qtRate, (double)nsScreen.maximumFramesPerSecond);
        }
    }

    return qtRate;
}

}
