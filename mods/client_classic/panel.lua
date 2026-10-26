-- Classic right-hand status panel (desktop only): health and mana bars with
-- the numbers inside, the inventory as a 3x4 grid with soul and capacity,
-- the combat and chase modes in one column, and a column of text buttons in
-- place of the icon buttons panel. The inventory and health modules keep
-- working on their own widgets; this only moves them and hides extras.

local PANEL_WIDTH = 212
local MARGIN = 7
local GAP = 3
local BUTTON_HEIGHT = 18
local BAR_HEIGHT = 14

-- Text buttons: label, action, and the icon button whose on/off state it shows
local BUTTONS = {
    { id = 'stats', text = 'Stats', mirror = 'skillsButton',
      action = function() modules.game_skills.toggle() end },
    { id = 'battle', text = 'Battle', mirror = 'battleButton',
      action = function() modules.game_battle.toggle() end },
    { id = 'quests', text = 'Quests', mirror = 'questLogButton',
      action = function()
          local controller = modules.game_questlog.questLogController
          if controller and controller.ui and controller.ui:isVisible() then
              controller.ui:hide()
          else
              modules.game_questlog.show()
          end
      end },
    { id = 'outfit', text = 'Outfit',
      action = function() g_game.requestOutfit() end },
    { id = 'friends', text = 'Friends', mirror = 'vipListButton',
      action = function() modules.game_viplist.toggle() end },
    { id = 'settings', text = 'Settings', mirror = 'optionsMainButton',
      action = function() modules.client_options.toggle() end },
    { id = 'logout', text = 'Logout',
      action = function() modules.game_interface.tryLogout() end },
}

-- Inventory widgets the classic panel does not use
local HIDDEN_INVENTORY = { 'changeSize', 'blessings', 'purseButton', 'expert', 'pvp', 'stop',
    'whiteDoveBox', 'whiteHandBox', 'yellowHandBox', 'redFistBox' }

local mirrorEvent
local buttonsPanel

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

local function setBars()
    local ui = modules.game_healthinfo and modules.game_healthinfo.healthManaController
        and modules.game_healthinfo.healthManaController.ui
    if not ui then
        return
    end
    ui.panelHeight = 2 * (BAR_HEIGHT + 4) + 2
    ui:setHeight(ui.panelHeight)
    for _, id in ipairs({ 'health', 'mana' }) do
        local row = ui:getChildById(id)
        if row then
            row.icon:setVisible(false)
            place(row.total, {
                { AnchorLeft, 'parent', AnchorLeft },
                { AnchorRight, 'parent', AnchorRight },
                { AnchorVerticalCenter, 'parent', AnchorVerticalCenter },
            }, { left = MARGIN, right = MARGIN })
            row.total:setHeight(BAR_HEIGHT)
            row.current:setHeight(BAR_HEIGHT)
            place(row.text, {
                { AnchorLeft, 'total', AnchorLeft },
                { AnchorRight, 'total', AnchorRight },
                { AnchorVerticalCenter, 'total', AnchorVerticalCenter },
            })
            row.text:setTextAlign(AlignCenter)
            row.text:setFont('Verdana Bold-11px-outline')
            row.text:setColor('#ffffff')
            row.text:raise()
        end
    end
end

-- "current/maximum" in the bars, after the health module wrote its number
local function updateBarTexts()
    local player = g_game.getLocalPlayer()
    local ui = modules.game_healthinfo and modules.game_healthinfo.healthManaController
        and modules.game_healthinfo.healthManaController.ui
    if not player or not ui then
        return
    end
    local function fill(row, value, maximum)
        row.text:setText(string.format('%d/%d', value, maximum))
        -- The bars are wider than the module's layout, so the fill is set here too
        local width = row.total:getWidth()
        row.current:setWidth(maximum > 0 and math.max(1, math.floor(width * value / maximum)) or 0)
    end
    fill(ui.health, player:getHealth(), player:getMaxHealth())
    fill(ui.mana, player:getMana(), player:getMaxMana())
end

local function setInventory(panel)
    local ui = panel.onPanel
    for _, id in ipairs(HIDDEN_INVENTORY) do
        local widget = ui:getChildById(id)
        if widget then
            widget:setVisible(false)
        end
    end

    -- 3x4 grid: amulet helmet backpack / weapon armor shield /
    -- ring legs ammo / soul boots capacity
    local grid = {
        { 'amulet', 'helmet', 'backpack' },
        { 'sword', 'armor', 'shield' },
        { 'ring', 'legs', 'tools' },
        { 'soulPanel', 'boots', 'capacityPanel' },
    }
    local slot = ui.helmet:getWidth()
    for row, ids in ipairs(grid) do
        for column, id in ipairs(ids) do
            local widget = ui:getChildById(id)
            widget:setSize({ width = slot, height = slot })
            place(widget, {
                { AnchorTop, 'parent', AnchorTop },
                { AnchorLeft, 'parent', AnchorLeft },
            }, { top = MARGIN - 1 + (row - 1) * (slot + GAP), left = MARGIN + (column - 1) * (slot + GAP) })
        end
    end

    -- Combat modes, then chase modes, in one column right of the grid
    local column = { { 'attack', 0 }, { 'balanced', GAP }, { 'defense', GAP }, { 'standPosture', 8 }, { 'followPosture', GAP } }
    local top = MARGIN - 1
    for _, entry in ipairs(column) do
        local widget = ui:getChildById(entry[1])
        top = top + entry[2]
        place(widget, {
            { AnchorTop, 'parent', AnchorTop },
            { AnchorLeft, 'backpack', AnchorRight },
        }, { top = top, left = 5 })
        top = top + widget:getHeight()
    end

    -- Conditions (poisoned, haste, ...) under the grid
    local gridBottom = MARGIN - 1 + 4 * slot + 3 * GAP
    place(ui.icons, {
        { AnchorTop, 'parent', AnchorTop },
        { AnchorLeft, 'parent', AnchorLeft },
        { AnchorRight, 'backpack', AnchorRight },
    }, { top = gridBottom + GAP, left = MARGIN })
    ui.icons:setHeight(18)

    -- Text buttons in the last column
    if not buttonsPanel then
        buttonsPanel = g_ui.createWidget('UIWidget', ui)
        buttonsPanel:setId('classicButtons')
        buttonsPanel:setPhantom(true)
        for _, entry in ipairs(BUTTONS) do
            local button = g_ui.createWidget('Button', buttonsPanel)
            button:setId(entry.id)
            button:setText(entry.text)
            button:setHeight(BUTTON_HEIGHT)
            button.onClick = entry.action
        end
        buttonsPanel:setLayout(UIVerticalLayout.create(buttonsPanel))
        buttonsPanel:getLayout():setSpacing(GAP)
    end
    place(buttonsPanel, {
        { AnchorTop, 'parent', AnchorTop },
        { AnchorLeft, 'attack', AnchorRight },
        { AnchorRight, 'parent', AnchorRight },
        { AnchorBottom, 'parent', AnchorBottom },
    }, { top = MARGIN - 1, left = 5, right = MARGIN, bottom = MARGIN })

    local height = math.max(gridBottom + GAP + 18, MARGIN - 1 + #BUTTONS * (BUTTON_HEIGHT + GAP) - GAP) + MARGIN
    panel.panelHeight = height
    panel:setHeight(height)
end

local function mirrorButtonStates()
    if not buttonsPanel then
        return
    end
    local options = modules.game_mainpanel and modules.game_mainpanel.optionsController
        and modules.game_mainpanel.optionsController.ui
    if not options then
        return
    end
    for _, entry in ipairs(BUTTONS) do
        if entry.mirror then
            local source = options:recursiveGetChildById(entry.mirror)
            local button = buttonsPanel:getChildById(entry.id)
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

    -- The minimised inventory has no room for the classic layout
    if g_settings.getBoolean('mainpanel_shrink_inventory') and modules.game_inventory.changeInventorySize then
        modules.game_inventory.changeInventorySize()
    end

    for _, panel in ipairs({ modules.game_interface.getRightPanel(), modules.game_interface.getMainRightPanel() }) do
        panel:setWidth(PANEL_WIDTH)
    end

    options:setVisible(false)
    setBars()
    -- after the new layout is applied, when the bars have their width
    addEvent(updateBarTexts)
    setInventory(inventory)
    modules.game_mainpanel.reloadMainPanelSizes()

    if not mirrorEvent then
        mirrorEvent = cycleEvent(mirrorButtonStates, 250)
    end
end

-- After the health module's own handler, which writes the bare number
function onClassicPanelStats()
    if buttonsPanel then
        addEvent(updateBarTexts)
    end
end

function stopClassicPanel()
    if mirrorEvent then
        removeEvent(mirrorEvent)
        mirrorEvent = nil
    end
end
