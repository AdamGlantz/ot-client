-- Touch or desktop layout: chosen automatically from the device, or forced
-- by the player (an iPad with a keyboard and trackpad, a touchscreen
-- laptop). A button on the login window, one in the top menu and Options >
-- Misc offer Automatic / Touch / Desktop; the choice is kept on this device
-- and the client reloads with it (the layout is decided at start-up).

local MODE_NAMES = { [0] = 'Automatic', [1] = 'Touch', [2] = 'Desktop' }
-- set by the touch layout when it picked a larger interface scale itself
local SCALE_KEY = 'client_mobile_scale_applied'

local modeButton
local loginButton
local modeMenu

function setTouchMode(mode)
    if mode == g_platform.getTouchMode() then
        return
    end
    -- The desktop layout at the scale the touch layout chose does not fit a
    -- small screen; the touch layout picks its scale again when it is back
    if mode == 2 and g_settings.getBoolean(SCALE_KEY) and modules.client_options then
        modules.client_options.setOption('hudScale', 0, true)
        g_settings.set(SCALE_KEY, false)
    end
    g_settings.save()
    g_platform.setTouchMode(mode)
end

function getTouchModeNames()
    return MODE_NAMES
end

local function openModeMenu(anchor)
    if modeMenu then
        modeMenu:destroy()
    end
    modeMenu = g_ui.createWidget('PopupMenu')
    modeMenu:setGameMenu(false)
    local current = g_platform.getTouchMode()
    for mode = 0, 2 do
        local label = tr(MODE_NAMES[mode]) .. (mode == current and '  *' or '')
        modeMenu:addOption(label, function()
            setTouchMode(mode)
        end)
    end
    modeMenu.onDestroy = function()
        modeMenu = nil
    end
    local pos = anchor:getPosition()
    modeMenu:display({ x = pos.x, y = pos.y + anchor:getHeight() })
end

local function layoutName()
    return tr(g_platform.isMobile() and 'Touch' or 'Desktop')
end

-- The Layout choice in Options > Misc
local function setupOptions()
    local options = modules.client_options
    local panel = options and options.getPanel and options.getPanel('misc')
    local row = panel and panel:recursiveGetChildById('touchModePanel')
    if not row then
        return
    end
    local box = row:getChildById('touchModeBox')
    box:clearOptions()
    for mode = 0, 2 do
        box:addOption(tr(MODE_NAMES[mode]), mode)
    end
    box:setCurrentOptionByData(g_platform.getTouchMode(), true)
    box.onOptionChange = function(widget, text, mode)
        setTouchMode(mode)
    end
    row:setVisible(true)
end

function initTouchMode()
    if not g_platform.isBrowser() then
        return
    end
    setupOptions()
    modeButton = modules.client_topmenu.addTopRightToggleButton('touchModeButton',
        tr('Layout: %s (change)', layoutName()), '/mods/client_mobile/images/touch_mode', function()
            openModeMenu(modeButton)
        end)

    -- On the login window too: the top menu may not fit a small screen
    local enterGame = rootWidget:recursiveGetChildById('enterGame')
    if enterGame then
        loginButton = g_ui.createWidget('QtButton', enterGame)
        loginButton:setId('touchModeLoginButton')
        loginButton:setText(tr('Layout: %s', layoutName()))
        loginButton:setSize({ width = 109, height = 20 })
        loginButton:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        loginButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        loginButton.onClick = function()
            openModeMenu(loginButton)
        end
    end
end

function terminateTouchMode()
    if modeMenu then
        modeMenu:destroy()
    end
    if modeButton then
        modeButton:destroy()
        modeButton = nil
    end
    if loginButton then
        loginButton:destroy()
        loginButton = nil
    end
end
