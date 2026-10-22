-- Targeting and general special actions for action bar buttons: attack the
-- nearest/furthest/healthiest/weakest monster or player, cycle targets,
-- stop attacking, change coins, and crosshair actions (use, look or open
-- the context menu on whatever is clicked or tapped next).

-- Creatures on the player's floor within the visible 15x11 area
local VIEW_RANGE_X = 7
local VIEW_RANGE_Y = 5

-- Shields of the player's own party members (everything else is not in it)
local PARTY_SHIELDS = {
    [ShieldBlue] = true, [ShieldYellow] = true,
    [ShieldBlueSharedExp] = true, [ShieldYellowSharedExp] = true,
    [ShieldBlueNoSharedExpBlink] = true, [ShieldYellowNoSharedExpBlink] = true,
    [ShieldBlueNoSharedExp] = true, [ShieldYellowNoSharedExp] = true,
}

local GOLD_COIN = 3031
local PLATINUM_COIN = 3035

local function isPartyMember(creature)
    return PARTY_SHIELDS[creature:getShield()] == true
end

local function distanceTo(player, creature)
    local a, b = player:getPosition(), creature:getPosition()
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Visible creatures matching filter, nearest first (ties by id, so cycling
-- keeps a stable order)
local function findCandidates(filter)
    local player = g_game.getLocalPlayer()
    if not player then
        return {}
    end
    local candidates = {}
    for _, creature in ipairs(g_map.getSpectatorsInRange(player:getPosition(), false, VIEW_RANGE_X, VIEW_RANGE_Y)) do
        if creature ~= player and not creature:isDead() and creature:getHealthPercent() > 0 and filter(creature) then
            table.insert(candidates, { creature = creature, distance = distanceTo(player, creature) })
        end
    end
    table.sort(candidates, function(a, b)
        if a.distance ~= b.distance then
            return a.distance < b.distance
        end
        return a.creature:getId() < b.creature:getId()
    end)
    return candidates
end

local function isMonster(creature)
    return creature:isMonster()
end

-- Players outside the party; cycling players includes party members too
local function isOtherPlayer(creature)
    return creature:isPlayer() and not isPartyMember(creature)
end

local function isAnyOtherPlayer(creature)
    return creature:isPlayer()
end

local function isSkulled(creature)
    local skull = creature:getSkull()
    return isOtherPlayer(creature) and skull ~= SkullNone and skull ~= SkullGreen
end

local function hasYellowSkull(creature)
    return isOtherPlayer(creature) and creature:getSkull() == SkullYellow
end

local function attack(candidate)
    if not candidate then
        return
    end
    -- g_game.attack on the current target cancels the attack
    local current = g_game.getAttackingCreature()
    if current and current:getId() == candidate.creature:getId() then
        return
    end
    g_game.attack(candidate.creature)
end

local function nearest(filter)
    attack(findCandidates(filter)[1])
end

local function furthest(filter)
    local candidates = findCandidates(filter)
    attack(candidates[#candidates])
end

-- Highest or lowest health percent, nearest first among equals
local function byHealth(filter, highest)
    local best
    for _, candidate in ipairs(findCandidates(filter)) do
        local health = candidate.creature:getHealthPercent()
        if not best or (highest and health > best.creature:getHealthPercent()) or
            (not highest and health < best.creature:getHealthPercent()) then
            best = candidate
        end
    end
    attack(best)
end

-- The next candidate after the current target, nearest first, wrapping around
local function cycle(filter)
    local candidates = findCandidates(filter)
    if #candidates == 0 then
        return
    end
    local current = g_game.getAttackingCreature()
    local nextIndex = 1
    if current then
        for i, candidate in ipairs(candidates) do
            if candidate.creature:getId() == current:getId() then
                nextIndex = i % #candidates + 1
                break
            end
        end
    end
    attack(candidates[nextIndex])
end

local function followNearestPlayer()
    local candidate = findCandidates(isOtherPlayer)[1]
    if candidate then
        g_game.follow(candidate.creature)
    end
end

-- Uses the first full stack (100) of gold or platinum coins in the open
-- containers; the server changes it to the next coin
local function convertCurrency()
    for _, container in pairs(g_game.getContainers()) do
        for _, item in ipairs(container:getItems()) do
            local id = item:getId()
            if (id == GOLD_COIN or id == PLATINUM_COIN) and item:getCount() == 100 then
                g_game.use(item)
                return
            end
        end
    end
    modules.game_textmessage.displayFailureMessage(tr('No stack of 100 coins in your open containers.'))
end

-- Crosshair actions: the next click (or tap) chooses what to use, look at or
-- open the context menu for. A widget of our own grabs it, so this does not
-- interfere with "use with" crosshairs.
local crosshairGrabber
local crosshairAction

local function cancelCrosshair()
    if not crosshairAction then
        return
    end
    crosshairAction = nil
    if crosshairGrabber then
        crosshairGrabber:ungrabMouse()
    end
    g_mouse.popCursor('target')
end

local function thingsAt(clickedWidget, mousePosition)
    local className = clickedWidget:getClassName()
    if className == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
            return tile:getTopLookThing(), tile:getTopUseThing(), tile:getTopCreature()
        end
    elseif className == 'UIItem' and not clickedWidget:isVirtual() then
        local item = clickedWidget:getItem()
        return item, item, nil
    elseif className == 'UICreatureButton' then
        local creature = clickedWidget:getCreature()
        return creature, creature, creature
    end
end

local function onCrosshairRelease(self, mousePosition, mouseButton)
    local action = crosshairAction
    cancelCrosshair()
    if mouseButton ~= MouseLeftButton or not action then
        return true
    end
    local root = modules.game_interface.getRootPanel()
    local clickedWidget = root:recursiveGetChildByPos(mousePosition, false)
    if not clickedWidget then
        return true
    end
    local lookThing, useThing, creature = thingsAt(clickedWidget, mousePosition)
    if action == 'use' and useThing then
        g_game.use(useThing)
    elseif action == 'look' and (creature or lookThing) then
        g_game.look(creature or lookThing)
    elseif action == 'menu' and (lookThing or useThing or creature) then
        modules.game_interface.createThingMenu(mousePosition, lookThing, useThing, creature)
    end
    return true
end

local function startCrosshair(action)
    -- The same button again cancels
    if crosshairAction == action then
        cancelCrosshair()
        return
    end
    cancelCrosshair()
    if g_ui.isMouseGrabbed() then
        return
    end
    if not crosshairGrabber then
        crosshairGrabber = g_ui.createWidget('UIWidget', rootWidget)
        crosshairGrabber:setVisible(false)
        crosshairGrabber:setFocusable(false)
        crosshairGrabber.onMouseRelease = onCrosshairRelease
    end
    crosshairAction = action
    crosshairGrabber:grabMouse()
    g_mouse.pushCursor('target')
end

-- Special action id -> function
TargetActionHandlers = {
    attackNearestMonster = function() nearest(isMonster) end,
    attackFurthestMonster = function() furthest(isMonster) end,
    attackHighestHpMonster = function() byHealth(isMonster, true) end,
    attackLowestHpMonster = function() byHealth(isMonster, false) end,
    cycleMonster = function() cycle(isMonster) end,
    attackNearestPlayer = function() nearest(isOtherPlayer) end,
    attackFurthestPlayer = function() furthest(isOtherPlayer) end,
    attackHighestHpPlayer = function() byHealth(isOtherPlayer, true) end,
    attackLowestHpPlayer = function() byHealth(isOtherPlayer, false) end,
    cyclePlayer = function() cycle(isAnyOtherPlayer) end,
    followNearestPlayer = followNearestPlayer,
    attackSkulled = function() cycle(isSkulled) end,
    attackYellowSkull = function() cycle(hasYellowSkull) end,
    attackNonParty = function() cycle(isOtherPlayer) end,
    stopAttack = function() g_game.cancelAttackAndFollow() end,
    convertCurrency = convertCurrency,
    useAtCrosshair = function() startCrosshair('use') end,
    lookAtCrosshair = function() startCrosshair('look') end,
    contextMenuAtCrosshair = function() startCrosshair('menu') end,
}

function terminateTargetActions()
    cancelCrosshair()
    if crosshairGrabber then
        crosshairGrabber:destroy()
        crosshairGrabber = nil
    end
end
