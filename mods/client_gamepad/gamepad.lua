-- Game controller in the browser (ot-client#17). The left stick or the
-- D-pad walks, like the touch joystick (one step at a time, as a held arrow
-- key); the other buttons use slots of the main hotbar, as their hotkeys do
-- (held, they repeat at the hotkey rate).
--
-- The engine reads the first connected controller with the browser Gamepad
-- API (g_platform.getGamepadButtons / getGamepadStick, standard mapping).
-- Options > Controls > Game controller: "Bind..." chooses the slot of each
-- button; the choice is kept on this device.

local BINDINGS_SETTING = 'gamepadBindings'
local POLL_INTERVAL = 25
local STICK_DEAD_ZONE = 0.45

-- Standard mapping: the buttons that can use a slot, and the D-pad
local BUTTONS = {
    { id = 0, name = 'A (bottom)' },
    { id = 1, name = 'B (right)' },
    { id = 2, name = 'X (left)' },
    { id = 3, name = 'Y (top)' },
    { id = 4, name = 'Left bumper' },
    { id = 5, name = 'Right bumper' },
    { id = 6, name = 'Left trigger' },
    { id = 7, name = 'Right trigger' },
    { id = 8, name = 'Back / Select' },
    { id = 9, name = 'Start' },
    { id = 10, name = 'Left stick press' },
    { id = 11, name = 'Right stick press' },
}
local DEFAULT_BINDINGS = { [0] = 1, [1] = 2, [2] = 3, [3] = 4, [4] = 5, [5] = 6, [6] = 7, [7] = 8, [10] = 9, [11] = 10 }
local MAX_SLOT = 12
local DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT = 12, 13, 14, 15
-- Directions by 45 degree sector, clockwise from east
local SECTORS = { Directions.East, Directions.SouthEast, Directions.South, Directions.SouthWest,
    Directions.West, Directions.NorthWest, Directions.North, Directions.NorthEast }

local pollEvent
local lastButtons = 0
local walking = false
local connected = false
local bindings
local bindWindow

local function pressed(bits, button)
    return bit.band(bits, bit.lshift(1, button)) ~= 0
end

local function loadBindings()
    bindings = {}
    local saved = g_settings.getNode(BINDINGS_SETTING)
    for _, button in ipairs(BUTTONS) do
        local slot
        if saved and saved[tostring(button.id)] ~= nil then
            slot = tonumber(saved[tostring(button.id)]) or 0
        else
            slot = DEFAULT_BINDINGS[button.id] or 0
        end
        bindings[button.id] = slot
    end
end

local function saveBindings()
    local node = {}
    for id, slot in pairs(bindings) do
        node[tostring(id)] = slot
    end
    g_settings.setNode(BINDINGS_SETTING, node)
    g_settings.save()
end

-- The walking direction from the D-pad, else from the left stick
local function direction(bits)
    local up, down = pressed(bits, DPAD_UP), pressed(bits, DPAD_DOWN)
    local left, right = pressed(bits, DPAD_LEFT), pressed(bits, DPAD_RIGHT)
    if up or down or left or right then
        local y = (down and 1 or 0) - (up and 1 or 0)
        local x = (right and 1 or 0) - (left and 1 or 0)
        if x ~= 0 or y ~= 0 then
            return SECTORS[math.floor(math.atan2(y, x) / (math.pi / 4) + 0.5) % 8 + 1]
        end
    end
    local stick = g_platform.getGamepadStick()
    local x = (math.floor(stick / 256) - 128) / 127
    local y = (stick % 256 - 128) / 127
    if math.sqrt(x * x + y * y) < STICK_DEAD_ZONE then
        return nil
    end
    return SECTORS[math.floor(math.atan2(y, x) / (math.pi / 4) + 0.5) % 8 + 1]
end

local function slotButton(slot)
    local actionbar = modules.game_actionbar
    local bar = actionbar and actionbar.actionBars and actionbar.actionBars[1]
    return bar and bar.tabBar:getChildById('1.' .. slot)
end

local function useSlot(slot, repeated)
    local button = slotButton(slot)
    if button and button.item then
        -- As its hotkey: the first press acts at once, holding repeats
        modules.game_actionbar.onExecuteAction(button, repeated)
    end
end

local function refreshBindWindow(bits)
    if not bindWindow then
        return
    end
    bindWindow.status:setText(bits >= 0 and
        tr('Controller connected. Press a button to find it in the list.') or
        tr('No controller found. Connect one and press any of its buttons (browsers only report a controller after that).'))
    for _, row in ipairs(bindWindow.rows:getChildren()) do
        row:setOn(bits >= 0 and pressed(bits, row.buttonId))
    end
end

local function poll()
    local bits = g_platform.getGamepadButtons()
    refreshBindWindow(bits)
    if bits < 0 then
        if connected then
            connected = false
            if walking then
                walking = false
                controllerWalk(nil)
            end
        end
        lastButtons = 0
        return
    end
    connected = true
    -- Not while the bind window is open or the player types
    if bindWindow or not g_game.isOnline() then
        lastButtons = bits
        return
    end

    local dir = direction(bits)
    if dir then
        walking = true
        controllerWalk(dir)
    elseif walking then
        walking = false
        controllerWalk(nil)
    end

    for id, slot in pairs(bindings) do
        if slot > 0 and pressed(bits, id) then
            useSlot(slot, pressed(lastButtons, id))
        end
    end
    lastButtons = bits
end

-- Bind window --------------------------------------------------------------

local function slotText(slot)
    return slot > 0 and tr('Hotbar slot %d', slot) or tr('Nothing')
end

function openBindWindow()
    if bindWindow then
        bindWindow:raise()
        bindWindow:focus()
        return
    end
    bindWindow = g_ui.createWidget('GamepadBindWindow', rootWidget)
    for _, button in ipairs(BUTTONS) do
        local row = g_ui.createWidget('GamepadBindRow', bindWindow.rows)
        row.buttonId = button.id
        row.name:setText(tr(button.name))
        row.slot:setText(slotText(bindings[button.id]))
        row.slot:setTooltip(tr('Tap to choose the next slot'))
        row.slot.onClick = function()
            bindings[button.id] = (bindings[button.id] + 1) % (MAX_SLOT + 1)
            row.slot:setText(slotText(bindings[button.id]))
            saveBindings()
        end
    end
    refreshBindWindow(g_platform.getGamepadButtons())
    bindWindow:raise()
    bindWindow:focus()
end

function closeBindWindow()
    if bindWindow then
        bindWindow:destroy()
        bindWindow = nil
    end
end

function resetBindings()
    g_settings.remove(BINDINGS_SETTING)
    g_settings.save()
    loadBindings()
    if bindWindow then
        closeBindWindow()
        openBindWindow()
    end
end

-- The Game controller row in Options > Controls
local function setupOptions()
    local options = modules.client_options
    local panel = options and options.getPanel and options.getPanel('generalPanel')
    local row = panel and panel:recursiveGetChildById('gamepadPanel')
    if not row then
        return
    end
    row:getChildById('gamepadBindButton').onClick = openBindWindow
    row:setHeight(30)
    row:setVisible(true)
end

local function startPolling()
    if not pollEvent then
        pollEvent = cycleEvent(poll, POLL_INTERVAL)
    end
end

local function stopPolling()
    if pollEvent then
        removeEvent(pollEvent)
        pollEvent = nil
    end
    if walking then
        walking = false
        controllerWalk(nil)
    end
    lastButtons = 0
end

function init()
    -- The engine reads controllers through the browser only
    if not g_platform.isBrowser() or not g_platform.getGamepadButtons then
        return
    end
    g_ui.importStyle('gamepad')
    loadBindings()
    setupOptions()
    connect(g_game, { onGameStart = startPolling, onGameEnd = stopPolling })
    if g_game.isOnline() then
        startPolling()
    end
end

function terminate()
    if not bindings then
        return
    end
    disconnect(g_game, { onGameStart = startPolling, onGameEnd = stopPolling })
    stopPolling()
    closeBindWindow()
end
