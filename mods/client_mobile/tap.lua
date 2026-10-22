-- One tap on the game view does the obvious thing (touch layout, when no
-- look/use/attack/follow mode is selected):
--   - a monster: attack it (tapping the current target keeps it)
--   - an NPC: say "hi" when close, otherwise walk to it
--   - a player: look at them
--   - a container (corpse, chest), something used like a ladder, or
--     whatever blocks the tile (doors, levers): open or use it
--   - anything else: walk there
-- Creatures count as tapped within about half a tile of the finger, since
-- they are often between tiles while walking. Sliding the finger to another
-- tile before lifting it cancels the tap.

local TOLERANCE = 0.45 -- tiles
-- Points sampled around the finger, nearest first
local SAMPLES = {
    { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
    { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 },
}
local NPC_TALK_RANGE = 3

local pressPosition

local function tileSize(map)
    local dimension = map:getVisibleDimension()
    return math.min(map:getWidth() / dimension.width, map:getHeight() / dimension.height)
end

local function creatureOn(map, point)
    local tile = map:getTile(point)
    local creature = tile and tile:getTopCreature()
    if creature and creature ~= g_game.getLocalPlayer() then
        return creature
    end
end

local function creatureNear(map, point)
    local offset = tileSize(map) * TOLERANCE
    for _, sample in ipairs(SAMPLES) do
        local creature = creatureOn(map, { x = point.x + sample[1] * offset, y = point.y + sample[2] * offset })
        if creature then
            return creature
        end
    end
end

local function samePosition(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

-- Returns true when the creature tap was handled
local function tapCreature(creature)
    if creature:isNpc() then
        local playerPos = g_game.getLocalPlayer():getPosition()
        local npcPos = creature:getPosition()
        if playerPos.z == npcPos.z and
            math.max(math.abs(playerPos.x - npcPos.x), math.abs(playerPos.y - npcPos.y)) <= NPC_TALK_RANGE then
            g_game.talk('hi')
            return true
        end
        return false -- walk to it
    elseif creature:isPlayer() then
        g_game.look(creature)
        return true
    end
    -- g_game.attack on the current target would cancel the attack
    local target = g_game.getAttackingCreature()
    if not target or target:getId() ~= creature:getId() then
        g_game.attack(creature)
    end
    return true
end

local function interactive(thing, tile)
    if not thing or thing:isGround() or thing:isCreature() then
        return false
    end
    return thing:isContainer() or thing:isForceUse() or (tile and not tile:isWalkable() and thing:isNotMoveable())
end

-- Called by game_interface for a left click/tap on the game view in mobile
-- mode with no look/use/attack/follow mode selected. Returns true when the
-- tap was handled; false lets the client walk to the tile.
function onGameViewTap(map, mousePosition, useThing)
    local position = map:getPosition(mousePosition)
    local pressed = pressPosition
    pressPosition = nil
    if pressed and not samePosition(map:getPosition(pressed), position) then
        return true -- slid off the tile: cancelled
    end

    local creature = creatureOn(map, mousePosition)
    if creature then
        return tapCreature(creature)
    end

    local tile = map:getTile(mousePosition)
    if interactive(useThing, tile) then
        if useThing:isContainer() then
            g_game.open(useThing)
        else
            g_game.use(useThing)
        end
        return true
    end

    creature = creatureNear(map, mousePosition)
    if creature then
        return tapCreature(creature)
    end
    return false
end

-- Attack and follow modes also take a creature within reach of the finger
function findCreatureAtTap(map, mousePosition)
    return creatureOn(map, mousePosition) or creatureNear(map, mousePosition)
end

local function onMapPress(map, mousePosition, mouseButton)
    if mouseButton == MouseLeftButton then
        pressPosition = mousePosition
    end
end

function initTap()
    local map = modules.game_interface.getMapPanel()
    connect(map, { onMousePress = onMapPress })
    modules.game_interface.MobileTapHandler = onGameViewTap
    modules.game_interface.MobileCreatureAtTap = findCreatureAtTap
end

function terminateTap()
    local map = modules.game_interface.getMapPanel()
    disconnect(map, { onMousePress = onMapPress })
    modules.game_interface.MobileTapHandler = nil
    modules.game_interface.MobileCreatureAtTap = nil
end
