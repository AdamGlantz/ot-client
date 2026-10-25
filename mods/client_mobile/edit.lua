-- Edit mode for the touch layout: the pieces around the game view (health
-- and mana bars, chat button, hotbar grid, joystick, look/use/attack/follow)
-- can be moved, and some resized. While editing each piece gets a frame:
-- one finger drags it, the corner resizes it. Pieces snap to the screen
-- edges, the game view and each other.
--
-- Positions are saved per character and separately for portrait and
-- landscape, as fractions of the screen, and applied on top of the default
-- layout (so "Reset" just forgets them).

local SETTINGS_NODE = 'client_mobile_layouts'
local SNAP_DISTANCE = 12
local MIN_SIZE = 36

-- Movable pieces: how each can be resized (nil: move only)
local PIECES = {
    { key = 'stats', resize = 'width', minWidth = 100 },
    { key = 'chat', resize = 'square', maxSize = 96 },
    { key = 'grid', resize = 'width', minWidth = 52 },
    { key = 'joystick' },
    { key = 'shortcuts' },
}

local editing = false
local frames = {}
local editBar

local function root()
    return modules.game_interface.getRootPanel()
end

local function orientation()
    local r = root()
    return r:getHeight() > r:getWidth() and 'portrait' or 'landscape'
end

local function characterLayouts()
    local name = g_game.getCharacterName()
    if not name or name == '' then
        return nil
    end
    local all = g_settings.getNode(SETTINGS_NODE) or {}
    all[name] = all[name] or {}
    return all, all[name]
end

local function savedPieces()
    local _, layouts = characterLayouts()
    return layouts and layouts[orientation()] or {}
end

local function savePiece(key, entry)
    local all, layouts = characterLayouts()
    if not all then
        return
    end
    local current = orientation()
    layouts[current] = layouts[current] or {}
    layouts[current][key] = entry
    g_settings.setNode(SETTINGS_NODE, all)
end

-- Moves a piece to a saved position (fractions of the screen) and size
local function placePiece(piece, widget, entry)
    local r = root():getRect()
    if entry.w and piece.resize == 'width' then
        if piece.key == 'grid' then
            resizeActionGrid(math.floor(entry.w * r.width))
        else
            widget:setWidth(math.max(piece.minWidth or MIN_SIZE, math.floor(entry.w * r.width)))
        end
    elseif entry.w and piece.resize == 'square' then
        local size = math.max(MIN_SIZE, math.min(piece.maxSize, math.floor(entry.w * r.width)))
        widget:setSize({ width = size, height = size })
    end
    widget:breakAnchors()
    local x = r.x + math.floor(entry.x * r.width)
    local y = r.y + math.floor(entry.y * r.height)
    -- keep it on the screen
    x = math.max(r.x, math.min(x, r.x + r.width - widget:getWidth()))
    y = math.max(r.y, math.min(y, r.y + r.height - widget:getHeight()))
    widget:setPosition({ x = x, y = y })
end

-- Called at the end of the touch layout: saved positions win over the
-- default ones
function applySavedLayout()
    local widgets = getMovableWidgets()
    local saved = savedPieces()
    for _, piece in ipairs(PIECES) do
        local widget = widgets[piece.key]
        if widget and saved[piece.key] then
            placePiece(piece, widget, saved[piece.key])
        end
    end
    -- the bars' fill follows their width
    refreshStats()
    if editing then
        updateFrames()
    end
end

-- Edges a piece snaps to: the screen, the game view and the other pieces
local function snapLines(except)
    local r = root():getRect()
    local xs, ys = { r.x, r.x + r.width }, { r.y, r.y + r.height }
    local function add(rect)
        table.insert(xs, rect.x)
        table.insert(xs, rect.x + rect.width)
        table.insert(ys, rect.y)
        table.insert(ys, rect.y + rect.height)
    end
    add(modules.game_interface.getMapPanel():getRect())
    local toolbar = root():getChildById('mobileToolbar')
    if toolbar then
        table.insert(ys, toolbar:getY())
    end
    for key, widget in pairs(getMovableWidgets()) do
        if key ~= except and widget:isVisible() then
            add(widget:getRect())
        end
    end
    return xs, ys
end

local function snap(value, size, lines)
    for _, line in ipairs(lines) do
        if math.abs(value - line) <= SNAP_DISTANCE then
            return line
        end
        if math.abs(value + size - line) <= SNAP_DISTANCE then
            return line - size
        end
    end
    return value
end

local function storePiece(piece, widget)
    local r = root():getRect()
    local entry = {
        x = (widget:getX() - r.x) / r.width,
        y = (widget:getY() - r.y) / r.height,
    }
    if piece.resize then
        entry.w = widget:getWidth() / r.width
    end
    savePiece(piece.key, entry)
end

function updateFrames()
    local widgets = getMovableWidgets()
    for _, piece in ipairs(PIECES) do
        local frame, widget = frames[piece.key], widgets[piece.key]
        if frame and widget then
            frame:setVisible(widget:isVisible())
            frame:setRect(widget:getRect())
            frame:raise()
        end
    end
    if editBar then
        editBar:raise()
    end
end

local function createFrame(piece, widget)
    local frame = g_ui.createWidget('MobileEditFrame', rootWidget)
    frame:setRect(widget:getRect())

    -- Drag the whole frame to move the piece
    frame.onDragEnter = function(self, mousePos)
        self.grab = { x = mousePos.x - widget:getX(), y = mousePos.y - widget:getY() }
        return true
    end
    frame.onDragMove = function(self, mousePos)
        local r = root():getRect()
        local xs, ys = snapLines(piece.key)
        local x = snap(mousePos.x - self.grab.x, widget:getWidth(), xs)
        local y = snap(mousePos.y - self.grab.y, widget:getHeight(), ys)
        x = math.max(r.x, math.min(x, r.x + r.width - widget:getWidth()))
        y = math.max(r.y, math.min(y, r.y + r.height - widget:getHeight()))
        widget:breakAnchors()
        widget:setPosition({ x = x, y = y })
        self:setRect(widget:getRect())
        return true
    end
    frame.onDragLeave = function()
        storePiece(piece, widget)
        return true
    end

    -- The corner resizes
    local corner = frame:getChildById('resize')
    corner:setVisible(piece.resize ~= nil)
    corner.onDragEnter = function()
        return true
    end
    corner.onDragMove = function(self, mousePos)
        local width = math.max(piece.minWidth or MIN_SIZE, mousePos.x - widget:getX())
        width = math.min(width, root():getX() + root():getWidth() - widget:getX())
        widget:breakAnchors()
        local position = widget:getPosition()
        if piece.key == 'grid' then
            resizeActionGrid(width)
        elseif piece.resize == 'square' then
            local size = math.min(piece.maxSize, math.max(MIN_SIZE, width))
            widget:setSize({ width = size, height = size })
        else
            widget:setWidth(width)
            refreshStats()
        end
        widget:setPosition(position)
        frame:setRect(widget:getRect())
        return true
    end
    corner.onDragLeave = function()
        storePiece(piece, widget)
        return true
    end
    return frame
end

local function destroyFrames()
    for key, frame in pairs(frames) do
        frame:destroy()
        frames[key] = nil
    end
    if editBar then
        editBar:destroy()
        editBar = nil
    end
end

function isEditingLayout()
    return editing
end

function stopEditLayout()
    if not editing then
        return
    end
    editing = false
    destroyFrames()
    g_settings.save()
    if onEditLayoutChange then
        onEditLayoutChange(false)
    end
end

function resetLayout()
    local all, layouts = characterLayouts()
    if all then
        layouts[orientation()] = nil
        g_settings.setNode(SETTINGS_NODE, all)
    end
    relayout()
end

function startEditLayout()
    if editing or not g_game.isOnline() then
        return
    end
    editing = true
    local widgets = getMovableWidgets()
    for _, piece in ipairs(PIECES) do
        if widgets[piece.key] then
            frames[piece.key] = createFrame(piece, widgets[piece.key])
        end
    end
    editBar = g_ui.createWidget('MobileEditBar', rootWidget)
    editBar:getChildById('reset').onClick = resetLayout
    editBar:getChildById('done').onClick = stopEditLayout
    updateFrames()
    if onEditLayoutChange then
        onEditLayoutChange(true)
    end
end

function toggleEditLayout()
    if editing then
        stopEditLayout()
    else
        startEditLayout()
    end
end
