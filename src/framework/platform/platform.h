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

#pragma once

#include <framework/core/inputevent.h>
#include <framework/global.h>

#include "staticdata.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#endif

class Platform
{
public:

    void init(std::vector<std::string>& args);
    void processArgs(std::vector<std::string>& args);
    bool spawnProcess(std::string process, const std::vector<std::string>& args);
    int getProcessId();
    bool isProcessRunning(std::string_view name);
    bool killProcess(std::string_view name);
    std::string getTempPath();
    std::string getCurrentDir();
    bool copyFile(std::string from, std::string to);
    bool fileExists(std::string file);
    bool removeFile(std::string file);
    ticks_t getFileModificationTime(std::string file);
    bool openUrl(std::string url, bool now = false);
    bool openDir(std::string path, bool now = false);
    std::string getCPUName();
    double getTotalSystemMemory();
    double getMemoryUsage();
    std::string getOSName();
    Device getDevice() { return m_device; }
    void setDevice(const Device device) { m_device = device; }
    bool isDesktop() { return m_device.type == Desktop; }
    // Browser: the touch layout is used on phones and tablets, chosen from
    // the user agent and the device (a touch screen without a precise
    // pointer: iPadOS Safari calls itself a Mac). The player can force it
    // with setTouchMode. Decided once: changing it reloads the page.
    bool isMobile() {
#ifndef __EMSCRIPTEN__
        return m_device.type == Mobile;
#else
        static const bool mobile = MAIN_THREAD_EM_ASM_INT({
            var mode = null;
            try { mode = localStorage.getItem('otclient-touch-mode'); } catch (e) {}
            if (mode === 'touch') return 1;
            if (mode === 'desktop') return 0;
            if ((/iphone|ipod|ipad|android/i).test(navigator.userAgent)) return 1;
            var touchOnly = navigator.maxTouchPoints > 0 &&
                window.matchMedia('(pointer: coarse)').matches &&
                !window.matchMedia('(any-pointer: fine)').matches;
            return touchOnly ? 1 : 0;
        }) == 1;
        return mobile;
#endif
    }
    // 0 automatic, 1 touch, 2 desktop (browser only)
    int getTouchMode() {
#ifndef __EMSCRIPTEN__
        return 0;
#else
        return MAIN_THREAD_EM_ASM_INT({
            var mode = null;
            try { mode = localStorage.getItem('otclient-touch-mode'); } catch (e) {}
            return mode === 'touch' ? 1 : mode === 'desktop' ? 2 : 0;
        });
#endif
    }
    // Stores the choice on this device and reloads the client with it
    void setTouchMode(int mode) {
#ifdef __EMSCRIPTEN__
        MAIN_THREAD_ASYNC_EM_ASM({
            try {
                if ($0 === 1) localStorage.setItem('otclient-touch-mode', 'touch');
                else if ($0 === 2) localStorage.setItem('otclient-touch-mode', 'desktop');
                else localStorage.removeItem('otclient-touch-mode');
            } catch (e) {}
            location.reload();
        }, mode);
#else
        (void)mode;
#endif
    }
    // Browser only (always true elsewhere): navigator.onLine, and whether the
    // page is shown (not a background tab or a minimized window)
    bool isNetworkOnline() {
#ifndef __EMSCRIPTEN__
        return true;
#else
        return MAIN_THREAD_EM_ASM_INT({ return navigator.onLine ? 1 : 0; }) == 1;
#endif
    }
    bool isPageVisible() {
#ifndef __EMSCRIPTEN__
        return true;
#else
        return MAIN_THREAD_EM_ASM_INT({ return document.visibilityState === 'visible' ? 1 : 0; }) == 1;
#endif
    }
    bool isBrowser() { return m_device.type == Browser; }
    bool isConsole() { return m_device.type == Console; }
    // A yes/no setting from the web page (window.otclientConfig[key], set by
    // the deployment): 1 yes, 0 no, -1 not set (and always -1 outside the browser)
    int getBrowserConfigFlag(const std::string& key) {
#ifndef __EMSCRIPTEN__
        (void)key;
        return -1;
#else
        return MAIN_THREAD_EM_ASM_INT({
            var config = window.otclientConfig;
            var value = config ? config[UTF8ToString($0)] : undefined;
            if (value === undefined || value === null) return -1;
            return (value === true || value === 1 || value === 'true' || value === 'on') ? 1 : 0;
        }, key.c_str());
#endif
    }
    std::string getDeviceShortName(DeviceType type = DeviceUnknown);
    std::string getOsShortName(OperatingSystem os = OsUnknown);
    std::string traceback(std::string_view where, int level = 1, int maxDepth = 32);
    void addKeyListener(std::function<void(const InputEvent&)> /*listener*/) {}

    static DeviceType getDeviceTypeByName(std::string shortName);
    static OperatingSystem getOsByName(std::string shortName);

private:
    Device m_device{ Device(Desktop, Windows) };

    static std::unordered_map<DeviceType, std::string> m_deviceShortNames;
    static std::unordered_map<OperatingSystem, std::string> m_osShortNames;
};

extern Platform g_platform;
