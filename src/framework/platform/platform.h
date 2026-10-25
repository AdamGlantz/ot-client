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
    bool isMobile() {
#ifndef __EMSCRIPTEN__
        return m_device.type == Mobile;
#else
        return MAIN_THREAD_EM_ASM_INT({
            return (/iphone|ipod|ipad|android/i).test(navigator.userAgent);
        }) == 1;
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
    // Installing the web client as an app (window.otclientApp, set by the
    // deployment's page, keeps the browser's install prompt):
    // 0 not possible, 1 the browser can install it (installApp shows its
    // prompt), 2 manual (iOS: Share > Add to Home Screen), 3 running as an
    // installed app
    int getAppInstallState() {
#ifndef __EMSCRIPTEN__
        return 0;
#else
        return MAIN_THREAD_EM_ASM_INT({
            if (window.matchMedia('(display-mode: standalone)').matches ||
                window.matchMedia('(display-mode: fullscreen)').matches || navigator.standalone)
                return 3;
            var app = window.otclientApp;
            if (!app) return 0;
            if (app.prompt) return 1;
            var ios = /iphone|ipad|ipod/i.test(navigator.userAgent) ||
                      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
            return ios ? 2 : 0;
        });
#endif
    }
    void installApp() {
#ifdef __EMSCRIPTEN__
        MAIN_THREAD_ASYNC_EM_ASM({
            var app = window.otclientApp;
            if (app && app.install) app.install();
        });
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
