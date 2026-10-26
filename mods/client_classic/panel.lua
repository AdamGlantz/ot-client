-- Classic right-hand panel (desktop only), as in the classic OTClient:
-- the inventory with the combat modes beside it (attack, balanced and
-- defense; stand, chase and secure mode), Stop, Options and Logout under
-- them, and a row of Skills, Battle, VIP and More.. buttons under the
-- inventory in place of the icon buttons panel. The inventory module keeps
-- working on its own widgets; this only moves them and hides extras.

local GAP = 3
local BUTTON_HEIGHT = 18
local ROW_HEIGHT = BUTTON_HEIGHT + 6
local INVENTORY_HEIGHT = 172
-- the interface's smooth font, clearer than the 8 px cipsoft pixel font
local PANEL_FONT = 'verdana-11px-antialised'

-- Inventory widgets the classic panel does not use
local HIDDEN_INVENTORY = { 'blessings', 'purseButton', 'expert',
    'whiteDoveBox', 'whiteHandBox', 'yellowHandBox', 'redFistBox' }

local function questLog()
    local controller = modules.game_questlog.questLogController
    if controller and controller.ui and controller.ui:isVisible() then
        controller.ui:hide()
    else
        modules.game_questlog.show()
    end
end

-- The row under the inventory; "mirror" is the icon button whose on/off
-- state (its window open or closed) the text button shows
local ROW_BUTTONS = {
    { id = 'skills', text = 'Skills', mirror = 'skillsButton',
      action = function() modules.game_skills.toggle() end },
    { id = 'battle', text = 'Battle', mirror = 'battleButton',
      action = function() modules.game_battle.toggle() end },
    { id = 'vip', text = 'VIP', mirror = 'vipListButton',
      action = function() modules.game_viplist.toggle() end },
    { id = 'more', text = 'More..' },
}

local MORE_MENU = {
    { 'Quest Log', questLog },
    { 'Outfit', function() g_game.requestOutfit() end },
    { 'Hotkeys', function() modules.game_hotkeys.toggle() end,
      available = function() return modules.game_hotkeys and modules.game_hotkeys.toggle end },
}

local mirrorEvent
local buttonRow

local function place(widget, anchors, margins)
    widget:breakAnchors()
    for _, anchor in ipairs(anchors) do
        widget:addAnchor(anchor[1], anchor[2], anchor[3])
    end
    widget:setMarginTop(margins and margins.top or 0)
    widget:setMarginLeft(margins and margins.left or 0)
    widget:setMarginRight(margins and margins.right or 0)
    widget:setMarginBottom(margins and margins.bottom or 0)
end

local function showMoreMenu(button)
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
    for _, entry in ipairs(MORE_MENU) do
        if not entry.available or entry.available() then
            menu:addOption(tr(entry[1]), entry[2])
        end
    end
    local pos = button:getPosition()
    menu:display({ x = pos.x, y = pos.y + button:getHeight() })
end

local function setInventory(ui)
    for _, id in ipairs(HIDDEN_INVENTORY) do
        local widget = ui:getChildById(id)
        if widget then
            widget:setVisible(false)
        end
    end

    -- Secure mode as a 20x20 hand in the third row, beside defense
    ui.pvp:mergeStyle({
        ['image-source'] = '/images/game/combatmodes/safefight',
        ['image-clip'] = '0 0 20 20',
        size = '20 20',
        ['$checked'] = { ['image-clip'] = '0 20 20 20' },
    })
    ui.pvp:setTooltip(tr('Secure mode'))
    place(ui.pvp, {
        { AnchorTop, 'defense', AnchorTop },
        { AnchorLeft, 'standPosture', AnchorLeft },
    })

    -- Stop, Options and Logout under the combat modes
    if not ui:getChildById('classicOptions') then
        for _, entry in ipairs({
            { 'classicOptions', 'Options', function() modules.client_options.toggle() end },
            { 'classicLogout', 'Logout', function() modules.game_interface.tryLogout() end },
        }) do
            local button = g_ui.createWidget('Button', ui)
            button:setId(entry[1])
            button:setText(tr(entry[2]))
            button.onClick = entry[3]
        end
    end
    local previous = 'defense'
    for _, id in ipairs({ 'stop', 'classicOptions', 'classicLogout' }) do
        local button = ui:getChildById(id)
        button:setHeight(BUTTON_HEIGHT)
        button:setFont(PANEL_FONT)
        place(button, {
            { AnchorTop, previous, AnchorBottom },
            { AnchorLeft, 'attack', AnchorLeft },
            { AnchorRight, 'standPosture', AnchorRight },
        }, { top = previous == 'defense' and 6 or GAP })
        previous = id
    end

    -- Conditions (poisoned, haste, ...) along the bottom, under the inventory
    place(ui.icons, {
        { AnchorLeft, 'amulet', AnchorLeft },
        { AnchorRight, 'backpack', AnchorRight },
        { AnchorBottom, 'parent', AnchorBottom },
    }, { bottom = 4 })
    ui.icons:setHeight(18)
end

-- The Skills / Battle / VIP / More.. row, as its own part of the main panel
-- right under the inventory
local function setButtonRow(mainPanel, inventory)
    if buttonRow then
        return
    end
    buttonRow = g_ui.createWidget('UIWidget')
    buttonRow:setId('classicButtonRow')
    buttonRow.panelHeight = ROW_HEIGHT
    buttonRow:setHeight(ROW_HEIGHT)
    mainPanel:insertChild(mainPanel:getChildIndex(inventory) + 1, buttonRow)
    for _, entry in ipairs(ROW_BUTTONS) do
        local button = g_ui.createWidget('Button', buttonRow)
        button:setId(entry.id)
        button:setText(tr(entry.text))
        button:setHeight(BUTTON_HEIGHT)
        button:setFont(PANEL_FONT)
        button.onClick = entry.action or showMoreMenu
    end
    -- Equal widths across the row
    local function layout()
        local buttons = buttonRow:getChildren()
        local each = math.floor((buttonRow:getWidth() - 16 - (#buttons - 1) * GAP) / #buttons)
        for index, button in ipairs(buttons) do
            button:setWidth(each)
            place(button, {
                { AnchorTop, 'parent', AnchorTop },
                { AnchorLeft, 'parent', AnchorLeft },
            }, { top = 2, left = 8 + (index - 1) * (each + GAP) })
        end
    end
    buttonRow.onGeometryChange = layout
    layout()
end

local function mirrorButtonStates()
    if not buttonRow then
        return
    end
    local options = modules.game_mainpanel and modules.game_mainpanel.optionsController
        and modules.game_mainpanel.optionsController.ui
    if not options then
        return
    end
    for _, entry in ipairs(ROW_BUTTONS) do
        if entry.mirror then
            local source = options:recursiveGetChildById(entry.mirror)
            local button = buttonRow:getChildById(entry.id)
            if source and button and button:isOn() ~= source:isOn() then
                button:setOn(source:isOn())
                -- the pressed look alone is hard to tell apart
                button:setColor(source:isOn() and '#f0d070' or '#dfdfdf')
            end
        end
    end
end

function setClassicPanel()
    if g_platform.isMobile() then
        return
    end
    local inventory = modules.game_inventory and modules.game_inventory.inventoryController
        and modules.game_inventory.inventoryController.ui
    local options = modules.game_mainpanel and modules.game_mainpanel.optionsController
        and modules.game_mainpanel.optionsController.ui
    if not inventory or not options then
        return
    end

    options:setVisible(false)
    -- A little taller than the standard panel, for the conditions row
    inventory:mergeStyle({ ['&panelHeight'] = INVENTORY_HEIGHT, height = INVENTORY_HEIGHT })
    if inventory:isOn() then
        inventory.panelHeight = INVENTORY_HEIGHT
    end
    setInventory(inventory.onPanel)
    setButtonRow(modules.game_interface.getMainRightPanel(), inventory)
    modules.game_mainpanel.reloadMainPanelSizes()

    if not mirrorEvent then
        mirrorEvent = cycleEvent(mirrorButtonStates, 250)
    end
end

function stopClassicPanel()
    if mirrorEvent then
        removeEvent(mirrorEvent)
        mirrorEvent = nil
    end
    if buttonRow then
        buttonRow:destroy()
        buttonRow = nil
    end
end
