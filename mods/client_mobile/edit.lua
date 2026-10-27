-- Edit mode for the touch layout: the pieces around the game view (health
-- and mana bars, chat button, hotbar grid, joystick, containers, docks)
-- can be moved and sized. While editing each piece gets a frame: one finger
-- drags it, - and + make it smaller or bigger (70% to 160%), Reset puts that
-- piece back; some can also be stretched by the corner. Pieces snap to the
-- screen edges, the game view and each other.
--
-- Positions and sizes are saved per character and separately for portrait
-- and landscape (positions as fractions of the screen), and applied on top
-- of the default layout (so "Reset" just forgets them).

local SETTINGS_NODE = 'client_mobile_layouts'
local SNAP_DISTANCE = 12
local MIN_SIZE = 36
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.7, 1.6, 0.1

-- Movable pieces: how each can be resized (nil: move only)
local PIECES = {
    { key = 'stats', resize = 'width', minWidth = 100 },
    { key = 'chat', resize = 'square', maxSize = 96 },
    { key = 'grid', resize = 'width', minWidth = 52 },
    { key = 'joystick' },
    { key = 'containers' },
    -- docks of pinned panels (pins.lua): a list's height (how many rows)
    -- changes, a fixed panel only moves
    { key = 'dock1', dock = 1 },
    { key = 'dock2', dock = 2 },
    { key = 'dock3', dock = 3 },
}

-- How a piece can be resized: by the corner (nil: not at all), and whether
-- - and + apply. Pieces are never stretched out of their shape: the bars and
-- the hotbar take more width, the chat button stays square, a list panel
-- shows more rows.
local function resizeMode(piece)
    if piece.dock then
        return dockKind(piece.dock) == 'list' and 'height' or nil
    end
    return piece.resize
end

local function canScale(piece)
    return not piece.dock or dockKind(piece.dock) == 'list'
end

local editing = false
local frames = {}
local selected -- the piece whose - + Reset buttons are shown
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
    -- right away: a phone browser may close the tab without warning
    g_settings.save()
end

-- The lowest a piece may reach: the top of the toolbar
local function bottomLimit()
    local r = root():getRect()
    local toolbar = root():getChildById('mobileToolbar')
    if toolbar and toolbar:isVisible() then
        return math.min(r.y + r.height, toolbar:getY())
    end
    return r.y + r.height
end

-- A piece's size when the player has not changed it: set by the layout
-- (a joystick in a narrow column is drawn smaller to fit it)
pieceDefaultScales = {}

-- The size of a piece (+ and -), 1 when not changed
function getPieceScale(key)
    local entry = savedPieces()[key]
    return entry and tonumber(entry.s) or pieceDefaultScales[key] or 1
end

-- The size a widget had before any scaling (kept on the widget)
local function base(widget)
    if not widget.baseGeometry then
        widget.baseGeometry = {
            width = widget:getWidth(), height = widget:getHeight(),
            left = widget:getMarginLeft(), right = widget:getMarginRight(),
            top = widget:getMarginTop(), bottom = widget:getMarginBottom(),
        }
    end
    return widget.baseGeometry
end

function getPieceBaseSize(widget)
    return base(widget)
end

local function scaleBox(widget, scale, keepWidth)
    local b = base(widget)
    if keepWidth then
        widget:setHeight(math.floor(b.height * scale))
    else
        widget:setSize({ width = math.floor(b.width * scale), height = math.floor(b.height * scale) })
    end
    widget:setMarginLeft(math.floor(b.left * scale))
    widget:setMarginRight(math.floor(b.right * scale))
    widget:setMarginTop(math.floor(b.top * scale))
    widget:setMarginBottom(math.floor(b.bottom * scale))
end

-- How + and - change each piece (the hotbar reads its scale when it lays
-- out its slots)
local SCALERS = {
    joystick = function(widget, scale)
        local b = base(widget)
        widget:setSize({ width = math.floor(b.width * scale), height = math.floor(b.height * scale) })
        -- the pad's picture is drawn in a fixed square (image-rect)
        widget:setImageRect({ x = math.floor(12 * scale), y = 0,
            width = math.floor(150 * scale), height = math.floor(150 * scale) })
        if widget.pointer then
            scaleBox(widget.pointer, scale)
        end
        -- the D-pad arrows follow the pad's size by themselves
    end,
    shortcuts = function(widget, scale)
        local b = base(widget)
        widget:setSize({ width = math.floor(b.width * scale), height = math.floor(b.height * scale) })
        local icons = widget:getChildById('shortcutIcons')
        for _, action in ipairs(icons and icons:getChildren() or {}) do
            scaleBox(action, scale)
            if action.image then
                scaleBox(action.image, scale)
            end
        end
    end,
    -- (only their size: the layout places them, with margins)
    stats = function(widget, scale)
        widget:setHeight(math.floor(base(widget).height * scale))
        for _, bar in ipairs(widget:getChildren()) do
            bar:setHeight(math.floor(base(bar).height * scale))
        end
    end,
    chat = function(widget, scale)
        local b = base(widget)
        widget:setSize({ width = math.floor(b.width * scale), height = math.floor(b.height * scale) })
        if widget.icon then
            local size = math.floor(28 * scale)
            widget.icon:setSize({ width = size, height = size })
        end
    end,
}
-- List docks: - and + show fewer or more rows (the panels' contents cannot
-- be drawn bigger, so their width stays)
for index = 1, 3 do
    SCALERS['dock' .. index] = function(widget, scale)
        if dockKind(index) == 'list' and widget.scaledBy ~= scale then
            widget.scaledBy = scale
            widget:setHeight(math.floor(DOCK_HEIGHT * scale))
            fitDocks()
        end
    end
end

local function applyScale(piece, widget, scale)
    if piece.key == 'grid' then
        relayout()
    elseif SCALERS[piece.key] then
        SCALERS[piece.key](widget, scale)
    end
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
    elseif entry.h and resizeMode(piece) == 'height' then
        widget:setHeight(math.max(80, math.floor(entry.h * r.height)))
    elseif entry.w and piece.resize == 'square' then
        local size = math.max(MIN_SIZE, math.min(piece.maxSize, math.floor(entry.w * r.width)))
        widget:setSize({ width = size, height = size })
    end
    widget:breakAnchors()
    local x = r.x + math.floor(entry.x * r.width)
    local y = r.y + math.floor(entry.y * r.height)
    -- keep it on the screen and off the game view
    x = math.max(r.x, math.min(x, r.x + r.width - widget:getWidth()))
    y = math.max(r.y, math.min(y, bottomLimit() - widget:getHeight()))
    x, y = keepOffGameView(x, y, widget:getWidth(), widget:getHeight())
    widget:setPosition({ x = x, y = y })
end

-- Called at the end of the touch layout: saved positions win over the
-- default ones
function applySavedLayout()
    local widgets = getMovableWidgets()
    local saved = savedPieces()
    for _, piece in ipairs(PIECES) do
        local widget = widgets[piece.key]
        if widget and SCALERS[piece.key] then
            SCALERS[piece.key](widget, getPieceScale(piece.key))
        end
        if widget and saved[piece.key] and saved[piece.key].x then
            placePiece(piece, widget, saved[piece.key])
        end
    end
    -- the bars' fill follows their width
    refreshStats()
    if editing then
        updateFrames()
        -- again once anchored pieces have their new place
        addEvent(function()
            if editing then
                updateFrames()
            end
        end)
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
        s = getPieceScale(piece.key),
    }
    if piece.resize then
        entry.w = widget:getWidth() / r.width
    end
    if resizeMode(piece) == 'height' then
        entry.h = widget:getHeight() / r.height
    end
    savePiece(piece.key, entry)
end

-- + and -: a step bigger or smaller, keeping the piece where it is (moved
-- back onto the screen if it grows past the edge)
local function changeScale(piece, widget, delta)
    local scale = math.floor((getPieceScale(piece.key) + delta) * 10 + 0.5) / 10
    scale = math.max(SCALE_MIN, math.min(SCALE_MAX, scale))
    -- it grows and shrinks around its centre
    local centre = { x = widget:getX() + widget:getWidth() / 2, y = widget:getY() + widget:getHeight() / 2 }
    local all, layouts = characterLayouts()
    if not all then
        return
    end
    local current = orientation()
    layouts[current] = layouts[current] or {}
    local entry = layouts[current][piece.key] or {}
    entry.s = scale
    layouts[current][piece.key] = entry
    g_settings.setNode(SETTINGS_NODE, all)
    g_settings.save()

    applyScale(piece, widget, scale)
    if piece.key ~= 'grid' then
        -- on the screen and above the toolbar
        local r = root():getRect()
        local bottom = bottomLimit()
        widget:breakAnchors()
        local x = math.max(r.x, math.min(math.floor(centre.x - widget:getWidth() / 2), r.x + r.width - widget:getWidth()))
        local y = math.max(r.y, math.min(math.floor(centre.y - widget:getHeight() / 2), bottom - widget:getHeight()))
        x, y = keepOffGameView(x, y, widget:getWidth(), widget:getHeight())
        widget:setPosition({ x = x, y = y })
        storePiece(piece, widget)
        if piece.key == 'stats' then
            refreshStats()
        end
    end
    updateFrames()
end

-- Reset on a piece: forgets its place and size
local function resetPiece(piece)
    savePiece(piece.key, nil)
    relayout()
end

-- The - + Reset buttons go above the piece, or below it when there is no
-- room above, kept on the screen
function placeSizeBar(frame, piece)
    local bar = frame.sizeBar
    local r = root():getRect()
    local x = math.max(r.x, math.min(frame:getX(), r.x + r.width - bar:getWidth()))
    local y = frame:getY() - bar:getHeight() - 4
    if y < r.y then
        y = frame:getY() + frame:getHeight() + 4
    end
    bar:setPosition({ x = x, y = y })
    bar:getChildById('size'):setText(math.floor(getPieceScale(piece.key) * 100 + 0.5) .. '%')
    -- a fixed panel only moves: just Reset
    local scalable = canScale(piece)
    for _, id in ipairs({ 'smaller', 'size', 'bigger' }) do
        bar:getChildById(id):setVisible(scalable)
    end
end

function updateFrames()
    local widgets = getMovableWidgets()
    for _, piece in ipairs(PIECES) do
        local frame, widget = frames[piece.key], widgets[piece.key]
        if frame and widget then
            frame:setVisible(widget:isVisible())
            frame:setRect(widget:getRect())
            frame:raise()
            frame.sizeBar:setVisible(widget:isVisible() and selected == piece.key)
            frame:setOn(selected == piece.key)
            placeSizeBar(frame, piece)
            frame.sizeBar:raise()
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
    -- Tapping or dragging a piece selects it: its - + Reset buttons show
    frame.onMousePress = function()
        if selected ~= piece.key then
            selected = piece.key
            updateFrames()
        end
        return false
    end
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
        y = math.max(r.y, math.min(y, bottomLimit() - widget:getHeight()))
        -- never onto the game view: it slides along its edge instead
        x, y = keepOffGameView(x, y, widget:getWidth(), widget:getHeight())
        widget:breakAnchors()
        widget:setPosition({ x = x, y = y })
        self:setRect(widget:getRect())
        placeSizeBar(self, piece)
        return true
    end
    frame.onDragLeave = function()
        storePiece(piece, widget)
        return true
    end

    local sizeBar = g_ui.createWidget('MobileEditSizeBar', rootWidget)
    frame.sizeBar = sizeBar
    sizeBar:getChildById('smaller').onClick = function()
        changeScale(piece, getMovableWidgets()[piece.key] or widget, -SCALE_STEP)
    end
    sizeBar:getChildById('bigger').onClick = function()
        changeScale(piece, getMovableWidgets()[piece.key] or widget, SCALE_STEP)
    end
    sizeBar:getChildById('reset').onClick = function()
        resetPiece(piece)
    end

    -- The corner resizes
    local corner = frame:getChildById('resize')
    corner:setVisible(resizeMode(piece) ~= nil)
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
        elseif resizeMode(piece) == 'height' then
            local height = math.max(80, mousePos.y - widget:getY())
            widget:setHeight(math.min(height, bottomLimit() - widget:getY()))
            fitDocks()
        elseif piece.resize == 'square' then
            local size = math.min(piece.maxSize, math.max(MIN_SIZE, width))
            widget:setSize({ width = size, height = size })
        else
            widget:setWidth(width)
            refreshStats()
        end
        widget:setPosition(position)
        frame:setRect(widget:getRect())
        placeSizeBar(frame, piece)
        return true
    end
    corner.onDragLeave = function()
        -- grown into the game view: moved out of it
        local x, y = keepOffGameView(widget:getX(), widget:getY(), widget:getWidth(), widget:getHeight())
        widget:setPosition({ x = x, y = y })
        frame:setRect(widget:getRect())
        storePiece(piece, widget)
        return true
    end
    return frame
end

local function destroyFrames()
    for key, frame in pairs(frames) do
        frame.sizeBar:destroy()
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
    selected = nil
    destroyFrames()
    g_settings.save()
    if onEditLayoutChange then
        onEditLayoutChange(false)
    end
end

-- Reset UI: every piece back to its default place and size, in both
-- orientations, and no panels pinned (hotbar slots and presets stay)
local resetBox

function resetLayout()
    local all, layouts = characterLayouts()
    if all then
        local name = g_game.getCharacterName()
        all[name] = nil
        g_settings.setNode(SETTINGS_NODE, all)
    end
    resetPins()
    g_settings.save()
    if editing then
        stopEditLayout()
        startEditLayout()
    end
    relayout()
end

function confirmResetLayout()
    if resetBox or not g_game.isOnline() then
        return
    end
    local function done()
        if resetBox then
            resetBox:destroy()
            resetBox = nil
        end
    end
    resetBox = displayGeneralBox(tr('Reset UI'), tr('Do you want to reset the UI to default values?'), {
        { text = tr('Yes'), callback = function() done(); resetLayout() end },
        { text = tr('No'), callback = done },
    }, function() done(); resetLayout() end, done)
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
    editBar:getChildById('reset').onClick = confirmResetLayout
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
