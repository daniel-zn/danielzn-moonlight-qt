#include "autoframerate.h"

#include <QScreen>
#include <QWindow>
#include <QtMath>

namespace AutoFrameRate
{

int fromRefreshRate(double hz)
{
    static const int k_StandardRates[] = { 30, 48, 50, 60, 72, 75, 85, 90, 100, 120, 144, 165,
                                           170, 175, 180, 200, 240, 280, 300, 360, 480 };

    if (!(hz > 0)) {
        return 60;
    }

    for (int rate : k_StandardRates) {
        if (qAbs(hz - rate) <= rate * 0.02) {
            return rate;
        }
    }

    return qBound(30, qRound(hz), 480);
}

double highestReading(double qtRate, double appKitMaximum)
{
    return qMax(qMax(qtRate, appKitMaximum), 0.0);
}

#ifndef Q_OS_DARWIN
double maximumRefreshRate(QScreen* screen)
{
    return screen != nullptr ? screen->refreshRate() : 0;
}
#endif

int forWindow(QWindow* window)
{
    QScreen* screen = window != nullptr ? window->screen() : nullptr;
    return fromRefreshRate(maximumRefreshRate(screen));
}

}
