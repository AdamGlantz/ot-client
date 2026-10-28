/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "uiprogressrect.h"

#include "framework/graphics/drawpoolmanager.h"
#include <framework/core/clock.h>
#include <framework/core/eventdispatcher.h>

#include "framework/otml/otmlnode.h"

namespace
{
    constexpr int PROGRESS_UPDATE_INTERVAL = 100; // milliseconds
    constexpr int FLASH_UPDATE_INTERVAL = 30; // milliseconds
    constexpr float PIE_STEP_PERCENT = 2.5f; // one triangle per 9 degrees at most
}

UIProgressRect::~UIProgressRect()
{
    stop();
    if (m_flashEvent) {
        m_flashEvent->cancel();
        m_flashEvent = nullptr;
    }
}

void UIProgressRect::drawSelf(const DrawPoolType drawPane)
{
    if (drawPane != DrawPoolType::FOREGROUND)
        return;

    // todo: check +1 to right/bottom
    // todo: add smooth
    const auto& drawRect = getPaddingRect();

    if (m_showProgress && m_round) {
        // the dark part is what is left (reversed: what is done)
        if (m_percentReverse)
            drawPie(0.f, m_percent, m_backgroundColor);
        else
            drawPie(m_percent, 100.f, m_backgroundColor);
    } else if (m_showProgress) {
        if (m_percentReverse) {
            // Sector 1: 0% - 12.5% (12.5)
            if (m_percent >= 12.5) {
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.topRight() + Point(1, 0), drawRect.topCenter(), m_backgroundColor);
            } else if (m_percent > 0) {
                const auto& var = Point(m_percent * (drawRect.right() - drawRect.horizontalCenter()) / 12.5, 0);
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.topCenter() + var, drawRect.topCenter(), m_backgroundColor);
            }

            // Sector 2: 12.5% - 37.5% (25)
            if (m_percent >= 37.5) {
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.bottomRight() + Point(1), drawRect.topRight() + Point(1, 0), m_backgroundColor);
            } else if (m_percent > 12.5) {
                const auto& var = Point(0, (m_percent - 12.5) * (drawRect.bottom() - drawRect.top()) / 25.0);
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.topRight() + var + Point(1, 0), drawRect.topRight() + Point(1, 0), m_backgroundColor);
            }

            // Sector 3: 37.5% - 62.5% (25)
            if (m_percent >= 62.5) {
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.bottomLeft() + Point(0, 1), drawRect.bottomRight() + Point(1), m_backgroundColor);
            } else if (m_percent > 37.5) {
                const auto& var = Point((m_percent - 37.5) * (drawRect.right() - drawRect.left()) / 25.0, 0);
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.bottomRight() - var + Point(1), drawRect.bottomRight() + Point(1), m_backgroundColor);
            }

            // Sector 4: 62.5% - 87.5% (25)
            if (m_percent >= 87.5) {
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.topLeft(), drawRect.bottomLeft() + Point(0, 1), m_backgroundColor);
            } else if (m_percent > 62.5) {
                const auto& var = Point(0, (m_percent - 62.5) * (drawRect.bottom() - drawRect.top()) / 25.0);
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.bottomLeft() - var + Point(0, 1), drawRect.bottomLeft() + Point(0, 1), m_backgroundColor);
            }

            // Sector 5: 87.5% - 100% (12.5)
            if (m_percent >= 100) {
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.topCenter(), drawRect.topLeft(), m_backgroundColor);
            } else if (m_percent > 87.5) {
                const auto& var = Point((m_percent - 87.5) * (drawRect.horizontalCenter() - drawRect.left()) / 12.5, 0);
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.topLeft() + var, drawRect.topLeft(), m_backgroundColor);
            }
        } else {
            // 0% - 12.5% (12.5)
            // triangle from top center, to top right (var x)
            if (m_percent < 12.5) {
                const auto& var = Point(std::max<int>(m_percent - 0.0, 0.0) * (drawRect.right() - drawRect.horizontalCenter()) / 12.5, 0);
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.topRight() + Point(1, 0), drawRect.topCenter() + var, m_backgroundColor);
            }

            // 12.5% - 37.5% (25)
            // triangle from top right to bottom right (var y)
            if (m_percent < 37.5) {
                const auto& var = Point(0, std::max<int>(m_percent - 12.5, 0.0) * (drawRect.bottom() - drawRect.top()) / 25.0);
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.bottomRight() + Point(1), drawRect.topRight() + var + Point(1, 0), m_backgroundColor);
            }

            // 37.5% - 62.5% (25)
            // triangle from bottom right to bottom left (var x)
            if (m_percent < 62.5) {
                const auto& var = Point(std::max<int>(m_percent - 37.5, 0.0) * (drawRect.right() - drawRect.left()) / 25.0, 0);
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.bottomLeft() + Point(0, 1), drawRect.bottomRight() - var + Point(1), m_backgroundColor);
            }

            // 62.5% - 87.5% (25)
            // triangle from bottom left to top left
            if (m_percent < 87.5) {
                const auto& var = Point(0, std::max<int>(m_percent - 62.5, 0.0) * (drawRect.bottom() - drawRect.top()) / 25.0);
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.topLeft(), drawRect.bottomLeft() - var + Point(0, 1), m_backgroundColor);
            }

            // 87.5% - 100% (12.5)
            // triangle from top left to top center
            if (m_percent < 100) {
                const auto& var = Point(std::max<int>(m_percent - 87.5, 0.0) * (drawRect.horizontalCenter() - drawRect.left()) / 12.5, 0);
                g_drawPool.addFilledTriangle(drawRect.center(), drawRect.topCenter(), drawRect.topLeft() + var, m_backgroundColor);
            }
        }
    }

    if (m_flashDuration > 0) {
        const auto elapsed = g_clock.millis() - m_flashStart;
        if (elapsed < static_cast<ticks_t>(m_flashDuration)) {
            const Color color(m_flashColor, m_flashColor.aF() * (1.f - static_cast<float>(elapsed) / m_flashDuration));
            if (m_round)
                drawPie(0.f, 100.f, color);
            else
                g_drawPool.addFilledRect(drawRect, color);
        }
    }

    drawImage(m_rect);
    drawBorder(m_rect);
    drawIcon(m_rect);
    drawText(m_rect);
}

// A clockwise slice of the circle that fits the padding rect, 0% at the top
void UIProgressRect::drawPie(const float fromPercent, const float toPercent, const Color& color) const
{
    if (toPercent <= fromPercent)
        return;

    const auto& rect = getPaddingRect();
    const float cx = rect.left() + rect.width() / 2.f;
    const float cy = rect.top() + rect.height() / 2.f;
    const float radius = std::min(rect.width(), rect.height()) / 2.f;
    const auto pointAt = [&](const float percent) {
        const float angle = percent * 2.f * Fw::pi / 100.f;
        return Point(std::lround(cx + radius * std::sin(angle)), std::lround(cy - radius * std::cos(angle)));
    };

    const Point center(std::lround(cx), std::lround(cy));
    const int steps = std::max<int>(1, std::ceil((toPercent - fromPercent) / PIE_STEP_PERCENT));
    Point previous = pointAt(fromPercent);
    for (int i = 1; i <= steps; ++i) {
        const Point next = pointAt(fromPercent + (toPercent - fromPercent) * i / steps);
        g_drawPool.addFilledTriangle(center, previous, next, color);
        previous = next;
    }
}

void UIProgressRect::setRound(const bool round)
{
    if (m_round == round)
        return;

    m_round = round;
    repaint();
}

void UIProgressRect::flash(const uint32_t duration)
{
    m_flashStart = g_clock.millis();
    m_flashDuration = duration;
    if (!m_flashEvent)
        scheduleFlashRepaint();
    repaint();
}

void UIProgressRect::scheduleFlashRepaint()
{
    auto self = static_self_cast<UIProgressRect>();
    m_flashEvent = g_dispatcher.scheduleEvent([self] {
        self->m_flashEvent = nullptr;
        self->repaint();
        if (g_clock.millis() - self->m_flashStart < static_cast<ticks_t>(self->m_flashDuration))
            self->scheduleFlashRepaint();
        else
            self->m_flashDuration = 0;
    }, FLASH_UPDATE_INTERVAL);
}

void UIProgressRect::setPercent(float percent)
{
    percent = std::clamp<float>(percent, 0.f, 100.f);
    if (m_percent == percent)
        return;

    m_percent = percent;
    repaint();
}

void UIProgressRect::stop()
{
    if (m_updateEvent) {
        m_updateEvent->cancel();
        m_updateEvent = nullptr;
    }

    if (m_running) {
        m_timeElapsed = std::min<uint32_t>(m_timeElapsed, m_duration);
        m_running = false;
    }
}

void UIProgressRect::setDuration(uint32_t duration)
{
    m_duration = duration;
}

void UIProgressRect::start()
{
    stop();

    if (m_duration == 0) {
        setPercent(100);
        if (m_showTime)
            setText("");
        callLuaField("onProgressUpdate", m_percent, 0, 0);
        callLuaField("onProgressFinish");
        return;
    }

    m_running = true;
    m_startTime = g_clock.millis();
    m_timeElapsed = 0;

    setPercent(0);

    if (m_showTime)
        setText("");

    updateProgress();
}

void UIProgressRect::showTime(const bool showTime)
{
    if (m_showTime == showTime)
        return;

    m_showTime = showTime;
    if (!m_showTime)
        setText("");
    else if (m_running)
        updateProgressText(std::max<int32_t>(static_cast<int32_t>(m_duration) - static_cast<int32_t>(m_timeElapsed), 0));
}

void UIProgressRect::showProgress(const bool showProgress)
{
    if (m_showProgress == showProgress)
        return;

    m_showProgress = showProgress;
    repaint();
}

uint32_t UIProgressRect::getTimeElapsed()
{
    if (m_running)
        return std::min<uint32_t>(static_cast<uint32_t>(std::max<int64_t>(g_clock.millis() - m_startTime, 0)), m_duration);

    return (std::min)(m_timeElapsed, m_duration);
}

void UIProgressRect::setPercentReverse(bool percentReverse)
{
	if (m_percentReverse == percentReverse)
		return;

    m_percentReverse = percentReverse;
    repaint();
}


void UIProgressRect::onStyleApply(const std::string_view styleName, const OTMLNodePtr& styleNode)
{
    UIWidget::onStyleApply(styleName, styleNode);

    for (const auto& node : styleNode->children()) {
        if (node->tag() == "percent")
            setPercent(node->value<float>());
        else if (node->tag() == "duration")
            setDuration(node->value<int>());
        else if (node->tag() == "show-time")
            showTime(node->value<bool>());
        else if (node->tag() == "show-progress")
            showProgress(node->value<bool>());
        else if (node->tag() == "percent-reverse")
            setPercentReverse(node->value<bool>());
        else if (node->tag() == "round")
            setRound(node->value<bool>());
        else if (node->tag() == "flash-color")
            setFlashColor(node->value<Color>());
    }
}

void UIProgressRect::scheduleNextUpdate()
{
    auto self = static_self_cast<UIProgressRect>();
    m_updateEvent = g_dispatcher.scheduleEvent([self] {
        self->m_updateEvent = nullptr;
        self->updateProgress();
    }, PROGRESS_UPDATE_INTERVAL);
}

void UIProgressRect::updateProgress()
{
    if (!m_running)
        return;

    const auto now = g_clock.millis();
    m_timeElapsed = std::min<uint32_t>(static_cast<uint32_t>(std::max<int64_t>(now - m_startTime, 0)), m_duration);

    const float percent = m_duration > 0 ? (static_cast<float>(m_timeElapsed) * 100.f) / m_duration : 100.f;
    setPercent(percent);

    const int32_t remainingMs = std::max<int32_t>(static_cast<int32_t>(m_duration) - static_cast<int32_t>(m_timeElapsed), 0);
    if (m_showTime)
        updateProgressText(static_cast<uint32_t>(remainingMs));

    callLuaField("onProgressUpdate", m_percent, (std::max)(remainingMs, 0), m_timeElapsed);

    if (m_timeElapsed >= m_duration) {
        stop();
        callLuaField("onProgressFinish");
        return;
    }

    scheduleNextUpdate();
}

void UIProgressRect::updateProgressText(const uint32_t remainingTimeMs)
{
    if (!m_showTime)
        return;

    if (remainingTimeMs == 0) {
        setText("");
        return;
    }

    const float seconds = std::round(static_cast<float>(remainingTimeMs)) / 1000.f;
    if (seconds >= 10.f)
        setText(fmt::format("{:.0f}s", seconds));
    else if (seconds >= 1.f)
        setText(fmt::format("{:.1f}s", seconds));
    else
        setText(fmt::format("{:.2f}s", seconds));
}
