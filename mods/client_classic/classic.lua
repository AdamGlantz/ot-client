-- Classic look for the 7.x era servers this client is shipped with.
--
-- Hides modern extras (login screen news panels, Discord/YouTube counters,
-- store button, health/mana arcs, the top stats bars, minimap layer slider,
-- rose and clock) without unloading their modules, since other modules call
-- into them. Trims the first action bar to twelve slots for F1-F12 (bound by
-- the defaults in client_classic_theme). Option defaults are applied once per
-- profile, so players can change them afterwards in the options window.

-- Each set of defaults is applied once; add a new set instead of changing an
-- applied one, so existing profiles pick up only the new settings.
local DEFAULTS = {
    {
        key = 'client_classic_defaults_applied',
        options = {
            classicControl = true,                -- left click walks/uses, right click looks/uses
            floatingEffect = false,
            enableHighlightMouseTarget = false,
            showLeftPanel = false,                -- one column on the right, as in 7.x
            showLeftExtraPanel = false,
            showRightExtraPanel = false,
        },
        apply = function()
            local circles = modules.game_healthcircle
            if circles and circles.setHealthCircle then
                circles.setHealthCircle(false)
                circles.setManaCircle(false)
            end
        end,
    },
    {
        key = 'client_classic_defaults_2',
        options = {
            -- Keep some light at night; with none, torches wash the map yellow
            ambientLight = 30,
        },
        apply = function()
            local statsBar = modules.game_interface and modules.game_interface.StatsBar
            if statsBar and statsBar.updateStatsBarOption then
                statsBar.updateStatsBarOption('hide', 'hide')
            end
        end,
    },
    {
        key = 'client_classic_defaults_3',
        options = {
            -- 7.x draws the floor below at full brightness, not shaded
            shadowFloorIntensity = 0,
        },
        apply = function() end,
    },
    {
        key = 'client_classic_defaults_4',
        options = {
            -- no square marking the tile under the mouse in 7.x
            crosshair = 'disabled',
        },
        apply = function() end,
    },
}

local ACTION_BAR_SLOTS = 12
local HIDDEN_TOP_MENU_WIDGETS = { 'topLeftOnlinePlayers', 'topLeftDiscord', 'topLeftYoutube',
    -- no sound on 7.x servers (see HIDDEN_CATEGORIES)
    'audioButton', 'soundDebugButton' }
local HIDDEN_MINIMAP_WIDGETS = { 'layersPanel', 'rosePanel', 'fullMap' }

-- Options that do nothing on a 7.x server or in the browser, by options
-- panel. The options keep their values; only the controls are hidden.
local HIDDEN_OPTIONS = {
    generalPanel = {
        'showPing',          -- the client measures ping from protocol 9.53 on
        { 'lootControlMode', mode = 'widget' }, -- quick looting (12.x); shares the mouse control row
    },
    interface = {
        'showSpellGroupCooldowns', -- spell group cooldowns arrived in 8.7
        'showInfoBanner',          -- modern event banners
        'frames',                  -- loot value frames (market prices)
        'showExpiryInInvetory',    -- item expiry/charges display (modern)
        'showExpiryInContainers',
        'showExpiryOnUnusedItems',
        'crosshair',         -- off (client_classic_defaults_4); not a 7.x thing
    },
    interfaceHUD = {
        'displayHarmony',    -- monk vocation (14.x)
        'rightJoystick',     -- touch layout places the joystick itself
    },
    graphicsPanel = {
        'fullscreen',        -- no effect in the browser (it has its own)
        { 'vsync', mode = 'stacked' }, -- the browser always syncs to the display
        'asyncTxtLoading',   -- technical setting with no visible effect
    },
    graphicsEffectsPanel = {
        'GameEffectSource',  -- per-source effect opacity needs 12.x effects
    },
    misc = {
        'autoChaseOverride', -- duplicate of the one in Controls
    },
    miscHelp = {
        'wikiButton',        -- links to the upstream project's wiki (with Info)
        -- English only for now; the other languages stay installed
        { 'changeLanguageButton', mode = 'widget' },
    },
}
-- 7.x servers send no sounds and the client ships none
local HIDDEN_CATEGORIES = { 'Sound' }

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

    -- Floating particles over the login background
    local particles = rootWidget:recursiveGetChildById('particles')
    if particles then
        particles:setVisible(false)
    end
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

-- 7.x minimap: the map with zoom and floor buttons only
local function setClassicMinimap()
    local controller = modules.game_minimap and modules.game_minimap.mapController
    local ui = controller and controller.ui
    if not ui then
        return
    end
    for _, id in ipairs(HIDDEN_MINIMAP_WIDGETS) do
        local widget = ui:recursiveGetChildById(id)
        if widget then
            widget:setVisible(false)
        end
    end

    -- The map takes the panel's width, with the minimap's own controls on
    -- it: Center at the top left, floor and zoom buttons at the bottom right
    for _, id in ipairs({ 'zoomIn', 'zoomOut' }) do
        local button = ui:getChildById(id)
        if button then
            button:setVisible(false)
        end
    end
    local border = ui:getChildById('minimapBorder')
    if border then
        border:addAnchor(AnchorRight, 'parent', AnchorRight)
        border:setMarginRight(7)
    end

    local minimap = border and border:getChildById('minimap')
    if minimap then
        for _, id in ipairs({ 'floorUpButton', 'floorDownButton', 'zoomInButton', 'zoomOutButton', 'resetButton' }) do
            local button = minimap:getChildById(id)
            if button then
                button:setVisible(true)
            end
        end
    end
end

-- First action bar: twelve slots (F1-F12), centred under the map
local ACTION_BAR_SLOT_WIDTH = 36

local function centerActionBar(bar)
    local panel = bar:getParent()
    if not panel then
        return
    end
    local arrows = (bar.prevPanel and bar.prevPanel:getWidth() or 0) + (bar.nextPanel and bar.nextPanel:getWidth() or 0)
    local width = ACTION_BAR_SLOTS * ACTION_BAR_SLOT_WIDTH + arrows + 8
    -- The panel stacks its bars in a vertical box that stretches them to its
    -- full width; equal side margins centre the bar inside it
    local margin = math.max(0, math.floor((panel:getWidth() - width) / 2))
    if bar:getMarginLeft() ~= margin then
        bar:setMarginLeft(margin)
        bar:setMarginRight(margin)
    end
end

local function setClassicActionBar()
    local actionBars = modules.game_actionbar and modules.game_actionbar.actionBars
    local bar = actionBars and actionBars[1]
    if not bar or not bar.tabBar then
        return
    end
    local buttons = bar.tabBar:getChildren()
    for i = #buttons, ACTION_BAR_SLOTS + 1, -1 do
        buttons[i]:destroy()
    end
    -- In mobile mode client_mobile places the bar
    if g_platform.isMobile() then
        return
    end

    centerActionBar(bar)
    local panel = bar:getParent()
    if panel then
        -- The side panels' stone frame on both sides of the bar
        panel:setImageSource('/images/ui/2pixel_up_frame_borderimage')
        panel:setImageBorder(4)
    end
    if panel and not panel.classicCentering then
        panel.classicCentering = true
        connect(panel, { onGeometryChange = function() centerActionBar(bar) end })
    end
end

local function hideUnusedOptions()
    local options = modules.client_options
    if not options or not options.hideOption then
        return
    end
    for panelName, ids in pairs(HIDDEN_OPTIONS) do
        for _, entry in ipairs(ids) do
            if type(entry) == 'table' then
                options.hideOption(panelName, entry[1], entry.mode)
            else
                options.hideOption(panelName, entry)
            end
        end
    end
    for _, category in ipairs(HIDDEN_CATEGORIES) do
        options.hideCategory(category)
    end
end

local function applyDefaults()
    local options = modules.client_options
    for _, set in ipairs(DEFAULTS) do
        if not g_settings.getBoolean(set.key) then
            if options and options.setOption then
                for key, value in pairs(set.options) do
                    options.setOption(key, value, true)
                end
            end
            set.apply()
            g_settings.set(set.key, true)
        end
    end
    g_settings.save()
end

-- 7.x servers send no sounds; the client's own (button clicks, ...) stay
-- off as well, every start (the Sound settings are hidden)
local function muteSounds()
    local options = modules.client_options
    if options and options.setOption then
        options.setOption('soundMaster', 0, true)
    end
    if g_sounds and g_sounds.setAudioEnabled then
        g_sounds.setAudioEnabled(false)
    end
end

local function onGameStart()
    setStoreButtonVisible(false)
    muteSounds()
    -- The feature list was rebuilt for the client version since the option was applied
    local options = modules.client_options
    if options and options.getOption and options.getOption('blueNpcNames') then
        g_game.enableFeature(GameBlueNpcNameColor)
    end
    applyDefaults()
    -- The action bars and minimap set themselves up on game start as well
    scheduleEvent(function()
        setClassicMinimap()
        setClassicActionBar()
        setClassicPanel()
    end, 100)
end

-- The browser client logs in with an account name: the server reads it as
-- text on WebSocket connections (7.92 desktop clients send a number)
local function onClientVersionChange()
    if g_platform.isBrowser() then
        g_game.enableFeature(GameAccountNames)
    end
end

function init()
    -- The Hotkeys window pre-creates empty F1-F12 entries for new profiles,
    -- which would claim the keys before the action bar can bind them
    if modules.game_hotkeys and modules.game_hotkeys.setDefaultComboKeys then
        modules.game_hotkeys.setDefaultComboKeys({})
    end
    hideLoginExtras()
    muteSounds()
    applyClassicSpells()
    initCorpseShine()
    setTopMenuWidgetsVisible(false)
    hideUnusedOptions()
    connect(g_game, { onGameStart = onGameStart, onClientVersionChange = onClientVersionChange })
    if g_game.getClientVersion() > 0 then
        onClientVersionChange()
    end
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart, onClientVersionChange = onClientVersionChange })
    stopClassicPanel()
    terminateCorpseShine()
    restoreLoginExtras()
    setTopMenuWidgetsVisible(true)
    setStoreButtonVisible(true)
end
