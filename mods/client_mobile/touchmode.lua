-- Touch or desktop layout: chosen automatically from the device, or forced
-- by the player (an iPad with a keyboard and trackpad, a touchscreen
-- laptop). A top menu button on the login screen and Options > Misc offer
-- Automatic / Touch / Desktop; the choice is kept on this device and the
-- client reloads with it (the layout is decided at start-up).

local MODE_NAMES = { [0] = 'Automatic', [1] = 'Touch', [2] = 'Desktop' }

local modeButton
local modeMenu

function setTouchMode(mode)
    if mode == g_platform.getTouchMode() then
        return
    end
    g_settings.save()
    g_platform.setTouchMode(mode)
end

function getTouchModeNames()
    return MODE_NAMES
end

local function openModeMenu()
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
    local pos = modeButton:getPosition()
    modeMenu:display({ x = pos.x, y = pos.y + modeButton:getHeight() })
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
    local current = g_platform.isMobile() and 'touch' or 'desktop'
    modeButton = modules.client_topmenu.addTopRightToggleButton('touchModeButton',
        tr('Layout: %s (change)', tr(current == 'touch' and 'Touch' or 'Desktop')),
        '/mods/client_mobile/images/touch_mode', openModeMenu)
end

function terminateTouchMode()
    if modeMenu then
        modeMenu:destroy()
    end
    if modeButton then
        modeButton:destroy()
        modeButton = nil
    end
end
