-- Classic look for the 7.x era servers this client is shipped with.
--
-- Hides modern extras (login screen news panels, Discord/YouTube counters,
-- store button, health/mana arcs) without unloading their modules, since other
-- modules call into them. Option defaults are applied once per profile, so
-- players can change them afterwards in the options window.

local DEFAULTS_APPLIED_KEY = 'client_classic_defaults_applied'

-- Options as in client_options/data_options.lua
local CLASSIC_OPTIONS = {
    classicControl = true,                -- left click walks/uses, right click looks/uses
    floatingEffect = false,
    enableHighlightMouseTarget = false,
    showLeftPanel = false,                -- one column on the right, as in 7.x
    showLeftExtraPanel = false,
    showRightExtraPanel = false,
}

local HIDDEN_TOP_MENU_WIDGETS = { 'topLeftOnlinePlayers', 'topLeftDiscord', 'topLeftYoutube' }

local originalBottomMenuShow

local function hideLoginExtras()
    local bottomMenu = modules.client_bottommenu
    if not bottomMenu or not g_modules.getModule('client_bottommenu'):isLoaded() then
        return
    end
    -- entergame shows the panel again whenever the login window appears
    originalBottomMenuShow = originalBottomMenuShow or bottomMenu.show
    bottomMenu.show = function() end
    bottomMenu.hide()
end

local function restoreLoginExtras()
    local bottomMenu = modules.client_bottommenu
    if bottomMenu and originalBottomMenuShow then
        bottomMenu.show = originalBottomMenuShow
        originalBottomMenuShow = nil
    end
end

local function setTopMenuWidgetsVisible(visible)
    local topMenu = modules.client_topmenu and modules.client_topmenu.getTopMenu and modules.client_topmenu.getTopMenu()
    if not topMenu then
        return
    end
    for _, id in ipairs(HIDDEN_TOP_MENU_WIDGETS) do
        local widget = topMenu:recursiveGetChildById(id)
        if widget then
            widget:setVisible(visible)
        end
    end
end

local function setStoreButtonVisible(visible)
    local panel = modules.game_mainpanel and modules.game_mainpanel.optionsController
        and modules.game_mainpanel.optionsController.ui
    local button = panel and panel:recursiveGetChildById('Store shop')
    if button then
        button:setVisible(visible)
    end
end

local function applyDefaultsOnce()
    if g_settings.getBoolean(DEFAULTS_APPLIED_KEY) then
        return
    end

    local options = modules.client_options
    if options and options.setOption then
        for key, value in pairs(CLASSIC_OPTIONS) do
            options.setOption(key, value, true)
        end
    end

    local circles = modules.game_healthcircle
    if circles and circles.setHealthCircle then
        circles.setHealthCircle(false)
        circles.setManaCircle(false)
    end

    g_settings.set(DEFAULTS_APPLIED_KEY, true)
    g_settings.save()
end

local function onGameStart()
    setStoreButtonVisible(false)
    applyDefaultsOnce()
end

function init()
    hideLoginExtras()
    setTopMenuWidgetsVisible(false)
    connect(g_game, { onGameStart = onGameStart })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart })
    restoreLoginExtras()
    setTopMenuWidgetsVisible(true)
    setStoreButtonVisible(true)
end
