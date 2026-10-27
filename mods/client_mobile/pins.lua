-- Pinned panels for the touch layout (ot-client#23). A long press on a
-- toolbar button (equipment, map, skills, battle, VIP, containers) pins its
-- panel on the screen: its windows move into a dock that stays open over the
-- game view instead of opening one at a time in the side panel. Docks are
-- pieces of the layout editor (moved, resized by the corner, - and +).
-- Another long press unpins it; a tap on a pinned panel's button hides or
-- shows its dock.
--
-- The docks are the desktop side panels the touch layout does not show
-- (window containers, so containers and the other windows work in them as
-- usual). Pins are saved per character; a dock's place and size with the
-- other pieces (per character and orientation).

local PINS_SETTING = 'client_mobile_pins'
DOCK_IDS = { 'gameLeftPanel', 'gameLeftExtraPanel', 'gameRightExtraPanel' }
DOCK_WIDTH, DOCK_HEIGHT = 176, 220

local hiddenDocks = {} -- dock index -> true while hidden with its button

local function rootPanel()
    return modules.game_interface.getRootPanel()
end

local function characterPins()
    local name = g_game.getCharacterName()
    if not name or name == '' then
        return nil
    end
    local all = g_settings.getNode(PINS_SETTING) or {}
    all[name] = all[name] or {}
    return all, all[name]
end

-- The pinned tabs by dock: { [1] = 'battle', [3] = 'bag' }
function pinnedTabs()
    local _, pins = characterPins()
    local result = {}
    for index = 1, #DOCK_IDS do
        local tab = pins and pins['dock' .. index]
        if tab and tab ~= '' then
            result[index] = tab
        end
    end
    return result
end

function dockOfTab(tabId)
    for index, tab in pairs(pinnedTabs()) do
        if tab == tabId then
            return index
        end
    end
end

function dockWidget(index)
    return rootPanel():recursiveGetChildById(DOCK_IDS[index])
end

function isDockInUse(widgetId)
    for index, _ in pairs(pinnedTabs()) do
        if DOCK_IDS[index] == widgetId then
            return true
        end
    end
    return false
end

-- Long press on a toolbar button: pins its panel in a free dock, or unpins
function togglePin(tabId)
    local all, pins = characterPins()
    if not all then
        return
    end
    local current = dockOfTab(tabId)
    if current then
        pins['dock' .. current] = ''
        hiddenDocks[current] = nil
    else
        local free
        for index = 1, #DOCK_IDS do
            if not pinnedTabs()[index] then
                free = index
                break
            end
        end
        if not free then
            modules.game_textmessage.displayFailureMessage(tr('At most %d panels can be pinned.', #DOCK_IDS))
            return
        end
        pins['dock' .. free] = tabId
    end
    g_settings.setNode(PINS_SETTING, all)
    g_settings.save()
    relayout()
end

-- A tap on a pinned panel's button hides or shows its dock
function toggleDock(tabId)
    local index = dockOfTab(tabId)
    if index then
        hiddenDocks[index] = not hiddenDocks[index] or nil
    end
end

function isDockHidden(tabId)
    local index = dockOfTab(tabId)
    return index and hiddenDocks[index] or false
end

-- The windows in a dock share its height (the desktop way closes the ones
-- that do not fit)
local function shareHeight(dock)
    local windows, fixed = {}, 0
    for _, child in ipairs(dock:getChildren()) do
        if child:isVisible() then
            local minimize = child:getClassName() == 'UIMiniWindow' and child:getChildById('minimizeButton')
            local minimized = minimize and minimize:isOn()
            if child:getClassName() == 'UIMiniWindow' and child:isResizeable() and not minimized then
                table.insert(windows, child)
            else
                fixed = fixed + child:getHeight()
            end
        end
    end
    if #windows == 0 then
        return
    end
    local free = dock:getHeight() - dock:getPaddingTop() - dock:getPaddingBottom() - fixed
    local each = math.floor(free / #windows)
    for _, window in ipairs(windows) do
        window:setHeight(math.max(window:getMinimumHeight(), each))
    end
end

-- Puts each pinned panel's widgets in its dock and everything else out of
-- the docks. owns(tabId, widget) says whether a widget belongs to a tab;
-- sidePanel and mainPanel are where unpinned widgets go back to.
function applyPins(owns, sidePanel, mainPanel)
    local pins = pinnedTabs()
    -- the game view is drawn centred in the map widget (15x11 tiles)
    local map = modules.game_interface.getMapPanel():getRect()
    local viewWidth = math.min(map.width, math.floor(map.height * 15 / 11))
    local viewLeft = map.x + math.floor((map.width - viewWidth) / 2)
    for index, id in ipairs(DOCK_IDS) do
        local dock = dockWidget(index)
        local tab = pins[index]
        if dock then
            dock.ignoreFillAll = true
            -- widgets that do not belong here go back to the side panels
            for _, child in ipairs(dock:getChildren()) do
                if not tab or not owns(tab, child) then
                    if child.mobileHome == 'main' then
                        child.mobileHome = nil
                        if child:getClassName() == 'UIMiniWindow' then
                            child:setParent(mainPanel, true)
                        else
                            child:setParent(mainPanel)
                        end
                        mainPanel:moveChildToIndex(child, math.min(child.mobileHomeIndex or 1, mainPanel:getChildCount()))
                    elseif child:getClassName() == 'UIMiniWindow' then
                        child:setParent(sidePanel, true)
                    else
                        sidePanel:addChild(child)
                    end
                end
            end
            if tab then
                for _, panel in ipairs({ sidePanel, mainPanel }) do
                    for index2, child in ipairs(panel:getChildren()) do
                        if owns(tab, child) then
                            if panel == mainPanel then
                                child.mobileHome = 'main'
                                child.mobileHomeIndex = index2
                            end
                            if child:getClassName() == 'UIMiniWindow' then
                                child:setParent(dock, true)
                            else
                                child:setParent(dock)
                            end
                            child:setVisible(true)
                            if child.panelHeight then
                                child:setHeight(child.panelHeight)
                            end
                        end
                    end
                end
                -- (the side panel style shows and hides it with its on state)
                dock:setOn(not hiddenDocks[index])
                dock:setVisible(not hiddenDocks[index])
                -- a first place over the game view; the editor's saved place
                -- wins (applied after this at each layout)
                if not dock.mobilePlaced then
                    dock.mobilePlaced = true
                    dock:breakAnchors()
                    dock:setSize({ width = DOCK_WIDTH, height = DOCK_HEIGHT })
                    dock:setPosition({ x = viewLeft + 8 + (index - 1) * (DOCK_WIDTH + 8), y = map.y + 8 })
                end
                dock:raise()
            else
                dock.mobilePlaced = nil
                dock:setOn(false)
                dock:setVisible(false)
            end
        end
    end
end

-- After the docks got their final size
function fitDocks()
    for index, _ in pairs(pinnedTabs()) do
        local dock = dockWidget(index)
        if dock and dock:isVisible() then
            shareHeight(dock)
        end
    end
end

function resetHiddenDocks()
    hiddenDocks = {}
end
