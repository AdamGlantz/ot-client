-- "Install app" button in the top menu for the web client. It shows when
-- the page can be installed as an app (the deployment's page provides the
-- manifest and keeps the browser's install prompt) and the client is not
-- already running as one. Chrome and Edge show their install prompt; on
-- iOS, Safari has no prompt, so the button explains Share > Add to Home
-- Screen.

local STATE_PROMPT = 1
local STATE_MANUAL = 2

local installButton
local checkEvent
local infoBox

local function onClick()
    local state = g_platform.getAppInstallState()
    if state == STATE_PROMPT then
        g_platform.installApp()
    elseif state == STATE_MANUAL and not infoBox then
        infoBox = displayInfoBox(tr('Install app'),
            tr('Tap the Share button in Safari, then "Add to Home Screen".\nThe game then starts from its own icon, without the browser bar.'))
        infoBox.onOk = function()
            infoBox = nil
        end
    end
end

-- The browser offers installing some time after the page loads (and stops
-- once the app is installed), so the button follows the state
local function update()
    local state = g_platform.getAppInstallState()
    installButton:setVisible(state == STATE_PROMPT or state == STATE_MANUAL)
end

function init()
    installButton = modules.client_topmenu.addTopRightToggleButton('installAppButton', tr('Install app'),
        '/images/topbuttons/install', onClick)
    installButton:setVisible(false)
    update()
    checkEvent = cycleEvent(update, 2000)
end

function terminate()
    if checkEvent then
        removeEvent(checkEvent)
        checkEvent = nil
    end
    if infoBox then
        infoBox:destroy()
        infoBox = nil
    end
    if installButton then
        installButton:destroy()
        installButton = nil
    end
end
