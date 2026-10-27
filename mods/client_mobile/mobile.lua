-- Touch layout for phones and tablets (mobile mode only).
--
-- The game view fills the screen and keeps its 15x11 tiles. Everything else
-- is a separate piece placed around it:
--   - a toolbar along the bottom that opens one panel at a time (equipment,
--     map, skills, battle, VIP, open containers) and the top menu
--   - health and mana bars
--   - the first action bar as a grid of twelve buttons
--   - a chat button that opens the console over the game view
-- The panels are the existing windows (inventory, minimap, skill window and
-- so on), shown and hidden in place, so their modules keep working as usual.

local TOOLBAR_HEIGHT = 44
local GRID_CELL = 44
local GRID_SPACING = 4
local ROUND_SLOT = '/mods/client_mobile/images/slot_round'
local ROUND_SLOT_PRESSED = '/mods/client_mobile/images/slot_round_pressed'

-- Toolbar entries, left to right. A panel entry shows the widgets of one side
-- panel whose id is listed (or starts with a listed prefix).
local TABS = {
    { id = 'menu', icon = '/images/topbuttons/options', tooltip = 'Menu' },
    { id = 'equipment', icon = '/images/game/slots/body', tooltip = 'Equipment', panel = 'main', ids = { 'maininventorypanel' } },
    { id = 'map', icon = '/images/topbuttons/minimap', tooltip = 'Map', panel = 'main', ids = { 'mainmappanel' } },
    { id = 'skills', icon = '/images/topbuttons/skills', tooltip = 'Skills', panel = 'right', ids = { 'skillWindow' } },
    { id = 'battle', icon = '/images/topbuttons/battle', tooltip = 'Battle', panel = 'right', prefixes = { 'battleWindow' } },
    { id = 'vip', icon = '/images/topbuttons/viplist', tooltip = 'VIP', panel = 'right', ids = { 'vipWindow' } },
    -- the containers window (client_containers)
    { id = 'bag', icon = '/images/game/slots/back', tooltip = 'Containers', action = function()
        if modules.client_containers and modules.client_containers.toggle then
            modules.client_containers.toggle()
        end
    end },
}

-- Desktop pieces the touch layout replaces or has no room for
local HIDDEN_WIDGETS = {
    'gameLeftPanel', 'gameLeftExtraPanel', 'gameRightExtraPanel',
    'gameLeftActionPanel', 'gameRightActionPanel', 'lockLeftPanel', 'lockRightPanel', 'lockPanel',
    'gameBottomCooldownPanel', 'bottomSplitter', 'gameTopPanel', 'gameBottomStatsBarPanel',
    'gameSelectLeftColumn', 'gameSelectRightColumn', 'gameSelectRightExtraColumn', 'gameSelectLeftExtraColumn',
    'leftIncreaseSidePanels', 'leftDecreaseSidePanels', 'rightIncreaseSidePanels', 'rightDecreaseSidePanels',
}

-- Interface scale for the screen's shorter side, applied once per profile so
-- it can still be changed in the options: phones 1x, small tablets 1.5x,
-- large tablets 2x (the client's own mobile default is 1.5x everywhere)
local SCALE_KEY = 'client_mobile_scale_applied'
local function applyDefaultScale()
    if g_settings.getBoolean(SCALE_KEY) then
        return
    end
    local options = modules.client_options
    if not options or not options.setOption then
        return
    end
    local shortSide = math.min(g_window.getWidth(), g_window.getHeight())
    -- hudScale option value v gives a scale of max(v / 2 + 0.5, 1)
    local value = shortSide >= 800 and 3 or shortSide >= 600 and 2 or 0
    options.setOption('hudScale', value, true)
    g_settings.set(SCALE_KEY, true)
    g_settings.save()
end

local toolbar, stats, chatButton, editLayoutButton
local presetRow -- the P (hotbar preset) and pencil buttons
local currentTab
local chatVisible = false
local menuVisible = false

local function gameInterface()
    return modules.game_interface
end

local function findTab(id)
    for _, tab in ipairs(TABS) do
        if tab.id == id then
            return tab
        end
    end
end

local function tabOwns(tab, widget)
    local id = widget:getId()
    for _, wanted in ipairs(tab.ids or {}) do
        if id == wanted then
            return true
        end
    end
    for _, prefix in ipairs(tab.prefixes or {}) do
        if id:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function anyTabOwns(widget)
    for _, tab in ipairs(TABS) do
        if tab.panel and tabOwns(tab, widget) then
            return true
        end
    end
    return false
end

-- Mini windows that open in a left side panel (containers remember the
-- panel they were last in) move to the right one, the only side panel this
-- layout shows
local function moveLeftWindowsRight()
    local gi = gameInterface()
    local root = gi.getRootPanel()
    for _, id in ipairs(DOCK_IDS) do
        local panel = root:recursiveGetChildById(id)
        -- (docks of pinned panels keep their windows, pins.lua)
        if panel and not isDockInUse(id) then
            for _, child in ipairs(panel:getChildren()) do
                -- (pinned widgets from the top panel go back there, pins.lua)
                if child:getClassName() == 'UIMiniWindow' and child.mobileHome ~= 'main' then
                    child:setParent(gi.getRightPanel(), true)
                end
            end
        end
    end
end

-- The equipment slots touch, like the containers window (compact, see
-- docs/design-language.md): the stock inventory spaces them 3 px apart
local EQUIPMENT_GAPS = {
    top = { 'sword', 'ring', 'soulPanel', 'armor', 'legs', 'boots', 'shield', 'tools', 'capacityPanel' },
    left = { 'helmet', 'backpack' },
}
local EQUIPMENT_SAVED = 3 * 3
local function compactEquipment()
    local inventory = gameInterface().getMainRightPanel():recursiveGetChildById('maininventorypanel')
    local slots = inventory and inventory:getChildById('onPanel')
    if not slots or inventory.compact then
        return
    end
    inventory.compact = true
    for _, id in ipairs(EQUIPMENT_GAPS.top) do
        local widget = slots:getChildById(id)
        if widget then
            widget:setMarginTop(0)
        end
    end
    for _, id in ipairs(EQUIPMENT_GAPS.left) do
        local widget = slots:getChildById(id)
        if widget then
            widget:setMarginLeft(0)
        end
    end
    if inventory.panelHeight then
        inventory.panelHeight = inventory.panelHeight - EQUIPMENT_SAVED
    end
end

-- Shows the side panel widgets of the selected tab and hides the other tab
-- widgets. Windows that belong to no tab (trade, spell list...) are left as
-- they are, and keep the right panel visible while they are open.
local function applyTab()
    local gi = gameInterface()
    local mainPanel = gi.getMainRightPanel()
    local rightPanel = gi.getRightPanel()
    -- a pinned panel is shown in its dock, not in the side panel
    if currentTab and dockOfTab(currentTab) then
        currentTab = nil
    end
    local tab = currentTab and findTab(currentTab)
    moveLeftWindowsRight()
    applyPins(function(tabId, widget)
        local pinned = findTab(tabId)
        return pinned and tabOwns(pinned, widget) or false
    end, rightPanel, mainPanel)

    local mainHeight = 0
    for _, child in ipairs(mainPanel:getChildren()) do
        local show = tab and tab.panel == 'main' and tabOwns(tab, child) or false
        child:setVisible(show)
        -- The mobile view mode collapses this panel and its widgets
        if show and child.panelHeight then
            child:setHeight(child.panelHeight)
        end
        if show then
            mainHeight = mainHeight + child:getHeight() + child:getMarginTop() + child:getMarginBottom()
        end
    end
    mainPanel:setVisible(mainHeight > 0)
    mainPanel:setHeight(mainHeight)

    local otherWindowsOpen = false
    for _, child in ipairs(rightPanel:getChildren()) do
        if anyTabOwns(child) then
            child:setVisible(tab and tab.panel == 'right' and tabOwns(tab, child) or false)
        elseif child:isVisible() then
            otherWindowsOpen = true
        end
    end
    rightPanel:setVisible((tab and tab.panel == 'right') or otherWindowsOpen)
    if rightPanel.fitAll then
        rightPanel:fitAll()
    end

    for _, button in ipairs(toolbar.buttons:getChildren()) do
        local id = button:getId()
        local pinned = dockOfTab(id) ~= nil
        button:setChecked(id == currentTab or (id == 'menu' and menuVisible) or (pinned and not isDockHidden(id)))
        button:setOn(pinned)
    end
end

-- The top menu (options, logout and the other menu buttons) is hidden
-- unless opened from the toolbar
local function setMenuVisible(visible)
    menuVisible = visible
    local topMenu = modules.client_topmenu
    if not topMenu or not topMenu.getTopMenu then
        return
    end
    if topMenu.getTopMenu():isVisible() == visible then
        return
    end
    if visible then
        topMenu.show()
    else
        topMenu.hide()
    end
end

-- The desktop top menu with every option (the hub's "All options")
function showTopMenu()
    setMenuVisible(true)
    applyTab()
end

function selectTab(id)
    local entry = findTab(id)
    if entry and entry.action then
        entry.action()
        return
    end
    if id == 'menu' then
        -- the menu button opens the hub (hub.lua); a second tap closes the
        -- hub or the desktop menu
        if menuVisible then
            setMenuVisible(false)
        elseif isHubOpen() then
            closeHub()
        else
            openHub()
        end
        applyTab()
        return
    end
    -- A pinned panel's button hides or shows its dock
    if dockOfTab(id) then
        toggleDock(id)
        applyTab()
        return
    end
    -- Tapping the open panel's button closes it
    currentTab = currentTab ~= id and id or nil
    applyTab()
end

-- Unread badge on the chat button: what players, NPCs and channels say
-- while the chat is closed (not monsters, spells or the player's own words)
local COUNTED_MODES = {}
for _, mode in ipairs({ 'Say', 'Whisper', 'Yell', 'PrivateFrom', 'PrivateTo', 'Channel', 'ChannelHighlight', 'NpcFrom',
                        'GamemasterBroadcast', 'GamemasterChannel', 'GamemasterPrivateFrom', 'GamemasterPrivateTo',
                        'Party', 'Guild' }) do
    if MessageModes[mode] then
        COUNTED_MODES[MessageModes[mode]] = true
    end
end
-- (7.x servers use one code for private messages both ways, which the
-- client reads as "to"; the player's own messages are skipped anyway)
local PRIVATE_MODES = {
    [MessageModes.PrivateFrom] = true, [MessageModes.PrivateTo] = true,
    [MessageModes.GamemasterPrivateFrom] = true, [MessageModes.GamemasterPrivateTo] = true,
}
local unread, unreadPrivate = 0, false

local function updateChatBadge()
    if not chatButton then
        return
    end
    local badge = chatButton:getChildById('badge')
    badge:setVisible(unread > 0)
    badge:setText(unread > 99 and '99+' or tostring(unread))
    -- private messages stand out
    badge:setImageColor(unreadPrivate and '#9b3fd6' or '#d23030')
end

local function onTalk(name, level, mode)
    if chatVisible or not COUNTED_MODES[mode] then
        return
    end
    local player = g_game.getLocalPlayer()
    if player and name == player:getName() then
        return
    end
    unread = unread + 1
    unreadPrivate = unreadPrivate or PRIVATE_MODES[mode] == true
    updateChatBadge()
end

local function setChatVisible(visible)
    chatVisible = visible
    if visible then
        unread, unreadPrivate = 0, false
        updateChatBadge()
    end
    gameInterface().getBottomPanel():setVisible(visible)
    chatButton:setChecked(visible)
    -- The joystick and look/use/attack/follow would cover the console
    for _, name in ipairs({ 'game_joystick', 'game_shortcuts' }) do
        local module = modules[name]
        if module and module.show and module.hide then
            if visible then
                module.hide()
            else
                module.show()
            end
        end
    end
    if visible then
        gameInterface().getBottomPanel():raise()
        chatButton:raise()
    end
end

local function updateStats()
    local player = g_game.getLocalPlayer()
    if not player or not stats then
        return
    end
    local function set(bar, value, max)
        local width = bar:getWidth() - 2
        bar.fill:setWidth(max > 0 and math.floor(width * math.min(value, max) / max) or 0)
        bar.text:setText(value .. ' / ' .. max)
    end
    set(stats.health, player:getHealth(), player:getMaxHealth())
    set(stats.mana, player:getMana(), player:getMaxMana())
end

-- The first action bar becomes a grid (four columns) beside the game view
-- Round touch buttons: the slot frame becomes a circle and the item, spell
-- or action icon sits in its middle
local function makeRound(button)
    if button.mobileRound then
        return
    end
    button.mobileRound = true
    button:mergeStyle({
        ['image-source'] = ROUND_SLOT,
        ['$pressed'] = { ['image-source'] = ROUND_SLOT_PRESSED },
    })
    button:setImageSource(ROUND_SLOT)
    local item = button.item or button:getChildById('item')
    if item then
        -- The square slot frame of the item widget is replaced by the circle
        item:mergeStyle({ ['$on'] = { ['image-source'] = '' }, ['$!on'] = { ['image-source'] = '' } })
        item:setImageSource('')
        item:breakAnchors()
        item:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
        item:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        item:setSize({ width = 34, height = 34 })
    end
end

local PRESET_ROW_HEIGHT = 34

-- An action bar as a grid of round buttons showing `slots` slots, `cell`
-- pixels each (GRID_CELL by default)
local function gridBar(bar, columns, slots, cell)
    cell = cell or GRID_CELL
    local tabBar = bar.tabBar
    if not tabBar.mobileGrid then
        tabBar.mobileGrid = true
        bar.showAllButtons = true
        local layout = UIGridLayout.create(tabBar)
        layout:setCellSize({ width = GRID_CELL, height = GRID_CELL })
        layout:setCellSpacing(GRID_SPACING)
        tabBar:setLayout(layout)
        tabBar:breakAnchors()
        tabBar:fill('parent')
        tabBar:setMargin(3)
        bar:setImageSource('')
        for _, id in ipairs({ 'prevPanel', 'nextPanel' }) do
            local slider = bar:getChildById(id)
            if slider then
                slider:setVisible(false)
            end
        end
    end
    tabBar:getLayout():setNumColumns(columns)
    tabBar:getLayout():setCellSize({ width = cell, height = cell })
    bar.gridSlots = slots
    -- Empty slots are placeholders until shown: make the shown ones real
    -- buttons first, so they get the round look too
    for index = 1, slots do
        local button = tabBar:getChildByIndex(index)
        if button and not button.item then
            modules.game_actionbar.updateButton(button)
        end
    end
    local iconSize = math.min(34, cell - 8)
    for _, button in ipairs(tabBar:getChildren()) do
        if button.item then
            makeRound(button)
            button.item:setSize({ width = iconSize, height = iconSize })
        end
    end
    local rows = math.max(1, math.ceil(slots / columns))
    local height = rows * (cell + GRID_SPACING) - GRID_SPACING + 6
    -- The bar style sets its height whenever it is switched on
    bar:mergeStyle({ ['$on'] = { height = height } })
    bar:setHeight(height)
    return height
end

-- The hotbar beside (landscape) or below (portrait) the game view: the extra
-- 3-slot rows on top and the main hotbar (action bar 1) below them, with as
-- many columns as fit the width and no more rows than fit the height.
-- Returns its width.
local function setActionGrid(availableWidth, availableHeight)
    local actionBars = modules.game_actionbar and modules.game_actionbar.actionBars
    local bar = actionBars and actionBars[1]
    if not bar or not bar.tabBar then
        return 0
    end
    local settings = hotbarSettings()
    -- Slot size: + and - in the layout editor
    local cell = math.floor(GRID_CELL * getPieceScale('grid'))
    local step = cell + GRID_SPACING
    local columns = math.max(2, math.min(6, math.floor((availableWidth - 6 + GRID_SPACING) / step)))
    local gridWidth = columns * step - GRID_SPACING + 6
    -- The extra rows always show their 3 slots, smaller when the grid is
    -- only two wide
    local extraCell = math.min(cell, math.floor((gridWidth - 6 + GRID_SPACING) / 3) - GRID_SPACING)
    local panel = bar:getParent()
    local used = 0

    -- Extra hotbars: bars 2 and 3, 3 slots each, above the main one
    for index, n in ipairs({ 2, 3 }) do
        local extra = actionBars[n]
        local wanted = (n == 2 and settings.extra1) or (n == 3 and settings.extra2)
        if extra and extra.tabBar then
            if wanted then
                if not extra.mobileShown then
                    -- Shown here only; the desktop setting stays as it was
                    modules.game_actionbar.setupActionBar(n)
                    extra.mobileShown = true
                end
                extra:setVisible(true)
                extra:setOn(true)
                modules.game_actionbar.addActiveActionBar(extra)
                used = used + gridBar(extra, 3, 3, extraCell) + 4
                panel:moveChildToIndex(extra, index)
            elseif extra.mobileShown then
                extra.mobileShown = nil
                extra:setVisible(false)
                extra:setOn(false)
                modules.game_actionbar.removeActiveActionBar(extra)
            end
        end
    end
    panel:moveChildToIndex(bar, #panel:getChildren())

    local rowsThatFit = math.max(1, math.floor((availableHeight - used - 6 + GRID_SPACING) / step))
    local slots = math.min(settings.slots, #bar.tabBar:getChildren(), columns * rowsThatFit)
    gridBar(bar, columns, slots, cell)
    return gridWidth
end

local function layout()
    local gi = gameInterface()
    local root = gi.getRootPanel()
    if not toolbar or not root then
        return
    end
    local width, height = root:getWidth(), root:getHeight()
    local portrait = height > width

    if not menuVisible then
        setMenuVisible(false)
    end

    for _, id in ipairs(HIDDEN_WIDGETS) do
        local widget = root:getChildById(id)
        if widget and not isDockInUse(id) then
            widget:setVisible(false)
        end
    end

    -- Game view: full width, above the toolbar (landscape) or centred
    -- vertically between the top and the toolbar (portrait), leaving room
    -- above and below it
    local map = gi.getMapPanel()
    map:breakAnchors()
    map:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    map:addAnchor(AnchorRight, 'parent', AnchorRight)
    map:addAnchor(AnchorTop, 'parent', AnchorTop)
    map:setMargin(0)
    -- Always the whole 15x11 view, scaled to fit (the mobile default crops it)
    map:setKeepAspectRatio(true)
    map:setLimitVisibleRange(false)
    map:setZoom(11)
    map:setVisibleDimension({ width = 15, height = 11 })
    local mapHeight
    if portrait then
        mapHeight = math.floor(width * 11 / 15)
        map:setHeight(mapHeight)
        map:setMarginTop(math.max(0, math.floor((height - TOOLBAR_HEIGHT - mapHeight) / 2)))
    else
        map:addAnchor(AnchorBottom, 'mobileToolbar', AnchorTop)
        mapHeight = height - TOOLBAR_HEIGHT
    end
    -- Free space on each side of the game view in landscape
    local side = portrait and width or math.max(0, math.floor((width - mapHeight * 15 / 11) / 2))

    stats:breakAnchors()
    if portrait then
        stats:addAnchor(AnchorTop, 'parent', AnchorTop)
        stats:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        stats:addAnchor(AnchorRight, 'parent', AnchorRight)
        stats:setMarginTop(8)
        stats:setMarginLeft(8)
        stats:setMarginRight(8)
    else
        stats:addAnchor(AnchorTop, 'parent', AnchorTop)
        stats:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        stats:setWidth(math.max(120, math.min(200, side - 12)))
        stats:setMarginTop(6)
        stats:setMarginLeft(6)
    end
    updateStats()

    -- Joystick (bottom left) and look/use/attack/follow (bottom right) sit
    -- above the toolbar
    local keypad = modules.game_joystick and modules.game_joystick.getPanel and modules.game_joystick.getPanel()
    local shortcuts = modules.game_shortcuts and modules.game_shortcuts.getPanel and modules.game_shortcuts.getPanel()
    -- (anchored again each time: the layout editor moves them by position,
    -- and a reset puts them back here)
    if keypad then
        keypad:breakAnchors()
        keypad:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        keypad:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        keypad:setMarginBottom(TOOLBAR_HEIGHT)
    end
    if shortcuts then
        shortcuts:breakAnchors()
        shortcuts:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        shortcuts:addAnchor(AnchorRight, 'parent', AnchorRight)
        shortcuts:setMarginBottom(TOOLBAR_HEIGHT)
    end
    local keypadHeight = keypad and keypad:getHeight() or 150
    local shortcutsHeight = shortcuts and shortcuts:getHeight() or 150

    -- Action grid: landscape on the right above look/use/attack/follow;
    -- portrait above the game view, beside the chat button
    local actionPanel = root:getChildById('gameBottomActionPanel')
    if actionPanel then
        -- Height left for it: landscape from the top of the screen down to
        -- look/use/attack/follow, below the P and pencil buttons; portrait
        -- between the health and mana bars and the game view
        local gridHeight
        if portrait then
            local above = math.floor((height - TOOLBAR_HEIGHT - mapHeight) / 2)
            gridHeight = above - 8 - stats:getHeight() - 8 - 4
        else
            gridHeight = height - TOOLBAR_HEIGHT - shortcutsHeight - 6 - PRESET_ROW_HEIGHT - 8
        end
        local gridWidth = setActionGrid(portrait and (width - 12 - 70 - 48) or (side - 6), gridHeight)
        actionPanel:breakAnchors()
        actionPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
        actionPanel:setMarginRight(6)
        if portrait then
            actionPanel:addAnchor(AnchorTop, 'mobileStats', AnchorBottom)
            actionPanel:setMarginTop(8)
        else
            actionPanel:addAnchor(AnchorBottom, 'mobileToolbar', AnchorTop)
            actionPanel:setMarginBottom(shortcutsHeight + 6)
        end
        actionPanel:setWidth(gridWidth)

        -- P (presets) and the pencil: above the hotbar in landscape, in a
        -- column to its left in portrait
        if not presetRow then
            presetRow = createHotbarPresetRow(root, actionPanel)
        end
        presetRow:breakAnchors()
        if portrait then
            presetRow:setLayout(UIVerticalLayout.create(presetRow))
            presetRow:getLayout():setSpacing(4)
            presetRow:setSize({ width = 40, height = 64 })
            presetRow:addAnchor(AnchorTop, actionPanel:getId(), AnchorTop)
            presetRow:addAnchor(AnchorRight, actionPanel:getId(), AnchorLeft)
            presetRow:setMarginRight(6)
            presetRow:setMarginBottom(0)
        else
            presetRow:setLayout(UIHorizontalLayout.create(presetRow))
            presetRow:getLayout():setSpacing(4)
            presetRow:setSize({ width = 84, height = 30 })
            presetRow:addAnchor(AnchorBottom, actionPanel:getId(), AnchorTop)
            presetRow:addAnchor(AnchorRight, actionPanel:getId(), AnchorRight)
            presetRow:setMarginBottom(4)
            presetRow:setMarginRight(0)
        end
        presetRow:raise()
        actionPanel:setVisible(true)
        actionPanel:raise()
        if modules.game_actionbar.updateVisibleWidgets then
            modules.game_actionbar.updateVisibleWidgets()
        end
    end

    -- Chat button below the health and mana bars; the console opens over the
    -- game view
    chatButton:breakAnchors()
    chatButton:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    chatButton:addAnchor(AnchorTop, 'mobileStats', AnchorBottom)
    chatButton:setMarginLeft(12)
    chatButton:setMarginTop(10)

    local console = gi.getBottomPanel()
    console:breakAnchors()
    console:addAnchor(AnchorBottom, 'mobileToolbar', AnchorTop)
    console:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    console:addAnchor(AnchorRight, 'parent', AnchorRight)
    console:setMargin(0)
    console:setHeight(math.floor((height - TOOLBAR_HEIGHT) * (portrait and 0.4 or 0.5)))
    console:setVisible(chatVisible)

    -- Side panels open over the game view, on the right
    local mainPanel = gi.getMainRightPanel()
    local rightPanel = gi.getRightPanel()
    mainPanel:breakAnchors()
    mainPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    mainPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
    mainPanel:setMargin(0)
    rightPanel:breakAnchors()
    rightPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    rightPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
    rightPanel:addAnchor(AnchorBottom, 'mobileToolbar', AnchorTop)
    rightPanel:setMargin(0)
    -- solid: the view mode draws side panels see-through, and these open
    -- over the game and the hotbar
    mainPanel:setImageColor('white')
    rightPanel:setImageColor('white')
    compactEquipment()

    applyTab()
    mainPanel:raise()
    rightPanel:raise()
    if chatVisible then
        console:raise()
    end
    chatButton:raise()
    toolbar:raise()
    -- the containers window (client_containers): in portrait below the game
    -- view, on the toolbar; in landscape top left
    local containers = modules.client_containers and modules.client_containers.getWindow()
    if containers then
        containers:breakAnchors()
        if portrait then
            -- (its parent is the whole screen: clear of the toolbar)
            containers:addAnchor(AnchorRight, 'parent', AnchorRight)
            containers:addAnchor(AnchorBottom, 'parent', AnchorBottom)
            containers:setMarginRight(4)
            containers:setMarginBottom(TOOLBAR_HEIGHT + 4)
        else
            containers:setMargin(0)
            containers:setPosition({ x = 4, y = 4 })
        end
        containers:raise()
    end

    -- Positions the player chose in edit mode (edit.lua)
    applySavedLayout()
    fitDocks()
end

function relayout()
    layout()
end

-- The pieces edit mode can move, by name
function getMovableWidgets()
    local root = gameInterface().getRootPanel()
    local widgets = { stats = stats, chat = chatButton }
    widgets.grid = root and root:getChildById('gameBottomActionPanel')
    widgets.joystick = modules.game_joystick and modules.game_joystick.getPanel and modules.game_joystick.getPanel()
    widgets.shortcuts = modules.game_shortcuts and modules.game_shortcuts.getPanel and modules.game_shortcuts.getPanel()
    widgets.containers = modules.client_containers and modules.client_containers.getWindow
        and modules.client_containers.getWindow()
    -- docks of pinned panels (pins.lua)
    for index, _ in pairs(pinnedTabs()) do
        local dock = dockWidget(index)
        if dock and dock:isVisible() then
            widgets['dock' .. index] = dock
        end
    end
    return widgets
end

-- The hotbar grid at a new width (as many columns as fit)
function resizeActionGrid(width)
    local actionPanel = gameInterface().getRootPanel():getChildById('gameBottomActionPanel')
    if not actionPanel then
        return
    end
    actionPanel:setWidth(setActionGrid(width))
    if modules.game_actionbar.updateVisibleWidgets then
        modules.game_actionbar.updateVisibleWidgets()
    end
end

function refreshStats()
    updateStats()
end

-- Edit mode needs the pieces in view: no menu, panel or chat over them
function onEditLayoutChange(active)
    if editLayoutButton then
        editLayoutButton:setOn(active)
    end
    if active then
        setMenuVisible(false)
        currentTab = nil
        applyTab()
        setChatVisible(false)
    end
end

local function onGameEnd()
    stopEditLayout()
    setHotbarEditing(false)
end

local function onGameStart()
    setMenuVisible(false)
    if modules.game_actionbar then
        modules.game_actionbar.ActionBarAssignSheet = openHotbarSheet
    end
    -- The console module adds its own chat toggles over the game view
    if modules.game_console and modules.game_console.destroyButtonChat then
        modules.game_console.destroyButtonChat()
    end
    setChatVisible(false)
    -- Presets and hotbar settings are per character
    refreshHotbarPresetRow()
    unread, unreadPrivate = 0, false
    updateChatBadge()
    -- The other modules lay themselves out on game start as well (the
    -- action bar rebuilds its buttons a little later)
    scheduleEvent(layout, 200)
    scheduleEvent(layout, 800)
end


function init()
    initTouchMode()
    if not g_platform.isMobile() then
        return
    end
    applyDefaultScale()
    g_ui.importStyle('mobile')
    g_ui.importStyle('hotbar_sheet')
    g_ui.importStyle('hub')
    initTap()
    -- Long press on a hotbar slot opens the touch sheet instead of the menu
    if modules.game_actionbar then
        modules.game_actionbar.ActionBarAssignSheet = openHotbarSheet
    end
    local root = gameInterface().getRootPanel()

    toolbar = g_ui.createWidget('MobileToolbar', root)
    toolbar:setId('mobileToolbar')
    toolbar:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    toolbar:addAnchor(AnchorRight, 'parent', AnchorRight)
    toolbar:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    toolbar:setHeight(TOOLBAR_HEIGHT)
    for _, tab in ipairs(TABS) do
        local button = g_ui.createWidget('MobileToolbarButton', toolbar.buttons)
        button:setId(tab.id)
        button:setIcon(tab.icon)
        button:setTooltip(tr(tab.tooltip))
        button.onClick = function()
            selectTab(tab.id)
        end
        -- A long press pins the panel on the screen (pins.lua)
        if tab.panel then
            button.onMouseRelease = function(widget, pos, mouseButton)
                if mouseButton == MouseRightButton and widget:containsPoint(pos) then
                    togglePin(tab.id)
                    return true
                end
                return false
            end
        end
    end

    stats = g_ui.createWidget('MobileStats', root)
    stats:setId('mobileStats')

    chatButton = g_ui.createWidget('MobileChatButton', root)
    chatButton:setId('mobileChatButton')
    chatButton.onClick = function()
        setChatVisible(not chatVisible)
    end

    -- In the menu (top menu): move and resize the pieces of this layout
    editLayoutButton = modules.client_topmenu.addTopRightToggleButton('mobileEditLayoutButton',
        tr('Edit layout'), '/mods/client_mobile/images/edit_layout', toggleEditLayout)

    connect(root, { onGeometryChange = layout })
    connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onTalk = onTalk })
    connect(LocalPlayer, { onHealthChange = updateStats, onManaChange = updateStats })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    terminateTouchMode()
    if not toolbar then
        return
    end
    local root = gameInterface().getRootPanel()
    disconnect(root, { onGeometryChange = layout })
    disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd, onTalk = onTalk })
    stopEditLayout()
    if editLayoutButton then
        editLayoutButton:destroy()
        editLayoutButton = nil
    end
    disconnect(LocalPlayer, { onHealthChange = updateStats, onManaChange = updateStats })
    if modules.game_actionbar then
        modules.game_actionbar.ActionBarAssignSheet = nil
    end
    closeHotbarSheet()
    closeHub()
    destroyHotbarPresetRow()
    presetRow = nil
    terminateTap()
    toolbar:destroy()
    stats:destroy()
    chatButton:destroy()
    toolbar, stats, chatButton = nil, nil, nil
end
