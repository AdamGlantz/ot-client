-- The hunt analyzer's bookkeeping (ot-client#29): one hunting session's
-- experience, kills, loot and supplies, worked out from what a 7.92 server
-- sends:
--   experience  changes in the player's experience
--   kills/drops the "Loot of a rat: 4 gold coins, cheese." message the killer
--               gets for each kill
--   looted      items that leave a container on the ground (a corpse) and
--               arrive in one the player carries
--   supplies    rune charges and fluids used up in carried containers, and
--               ammunition used from the ammo slot (not moves: an item that
--               turns up elsewhere in the player's containers soon after)
-- Prices come from the item data (client_itemdata: what NPCs pay and ask)
-- and the player's own prices.

local CUSTOM_PRICES = 'client_hunt_prices'
local MOVE_WINDOW = 1500 -- ms in which a removal and an addition are one move

session = nil

local pendingFromGround = {} -- items taken from a corpse, not yet arrived
local pendingUsed = {} -- supplies that went down, unless they were moved
local knownRunes = {} -- ids seen losing charges

local function add(map, key, count)
    map[key] = (map[key] or 0) + count
end

-- Items -----------------------------------------------------------------------

-- An item's key: its id, or "id:fluid" for a vial with something in it
function itemKey(item)
    if item:isFluidContainer() and item:getSubType() > 0 then
        return item:getId() .. ':' .. item:getSubType()
    end
    return tostring(item:getId())
end

local function customPrices()
    return g_settings.getNode(CUSTOM_PRICES) or {}
end

function setCustomPrice(key, price)
    local all = customPrices()
    all[key] = price
    g_settings.setNode(CUSTOM_PRICES, all)
    g_settings.save()
end

function hasCustomPrice(key)
    return customPrices()[key] ~= nil
end

local function itemData()
    return modules.client_itemdata
end

-- The id and the fluid of a key ("2874:10")
local function splitKey(key)
    local id, fluid = key:match('^(%d+):(%d+)$')
    if id then
        return tonumber(id), tonumber(fluid)
    end
    return tonumber(key), nil
end

-- What one is worth: the player's price, else the most an NPC pays (loot)
-- or the least one asks (supplies)
function itemPrice(key, supply)
    local custom = customPrices()[key]
    if custom then
        return tonumber(custom) or 0
    end
    local lib = itemData()
    local id, fluid = splitKey(key)
    if not lib or not id then
        return 0
    end
    local entry = fluid and lib.getFluid(id, fluid) or lib.getItem(id)
    if not entry then
        return 0
    end
    local best = supply and entry.buy and entry.buy[1] or entry.sell and entry.sell[1]
    return best and best[2] or 0
end

FLUID_NAMES = { [1] = 'water', [2] = 'blood', [3] = 'beer', [4] = 'slime', [5] = 'lemonade', [6] = 'milk',
    [7] = 'manafluid', [10] = 'manafluid', [11] = 'lifefluid', [13] = 'urine', [15] = 'wine', [19] = 'mud',
    [21] = 'oil', [26] = 'rum', [27] = 'fruit juice', [28] = 'coconut milk' }

function itemName(key)
    local name = key:match('^name:(.+)')
    if name then
        return name
    end
    local id, fluid = splitKey(key)
    local entry = id and itemData() and itemData().getItem(id)
    if not entry then
        return tr('item %s', key)
    end
    if fluid then
        return entry.n .. ' (' .. (FLUID_NAMES[fluid] or tr('fluid')) .. ')'
    end
    return entry.n
end

-- Loot counted by name before the item data arrived
local function resolveNames()
    if not session or not itemData() then
        return
    end
    for _, map in ipairs({ session.dropped, session.looted }) do
        for key, count in pairs(map) do
            local name = key:match('^name:(.+)')
            local id = name and itemData().findByName(name)
            if id then
                map[key] = nil
                add(map, tostring(id), count)
            end
        end
    end
    if onTrackerChange then
        onTrackerChange()
    end
end

-- Session ---------------------------------------------------------------------

local function newSession()
    return {
        state = 'idle', -- idle (waiting for the first kill), tracking, paused
        started = nil, -- os.time() of the first event
        elapsed = 0, -- seconds tracked before the current stretch
        stretchStart = nil, -- g_clock.seconds() when tracking (re)started
        xp = 0, kills = {}, dropped = {}, looted = {}, supplies = {},
        onlyLooted = true, -- loot = what you picked up, not what dropped
    }
end

function resetSession()
    session = newSession()
    pendingFromGround, pendingUsed = {}, {}
end

function sessionSeconds()
    if not session then
        return 0
    end
    local running = session.state == 'tracking' and session.stretchStart and (g_clock.seconds() - session.stretchStart) or 0
    return session.elapsed + running
end

local function startIfIdle()
    if session.state == 'idle' then
        session.state = 'tracking'
        session.started = os.time()
        session.stretchStart = g_clock.seconds()
    end
    return session.state == 'tracking'
end

function pauseSession()
    if session.state == 'tracking' then
        session.elapsed = sessionSeconds()
        session.stretchStart = nil
        session.state = 'paused'
    elseif session.state == 'paused' then
        session.stretchStart = g_clock.seconds()
        session.state = 'tracking'
    end
end

local function changed()
    if onTrackerChange then
        onTrackerChange()
    end
end


-- Totals for the panel and the report
function totals()
    local hours = math.max(sessionSeconds(), 1) / 3600
    local kills, loot, gold, supplies = 0, 0, 0, 0
    for _, count in pairs(session.kills) do
        kills = kills + count
    end
    local lootMap = session.onlyLooted and session.looted or session.dropped
    for key, count in pairs(lootMap) do
        local value = itemPrice(key) * count
        loot = loot + value
        if key == '3031' or key == '3035' or key == '3043' then
            gold = gold + value
        end
    end
    for key, count in pairs(session.supplies) do
        supplies = supplies + itemPrice(key, true) * count
    end
    return {
        seconds = sessionSeconds(), hours = hours, xp = session.xp, xpPerHour = math.floor(session.xp / hours),
        kills = kills, killsPerHour = math.floor(kills / hours), loot = loot, gold = gold,
        lootPerHour = math.floor(loot / hours), supplies = supplies, profit = loot - supplies,
    }
end

-- Experience -------------------------------------------------------------------

local function onExperienceChange(player, value, oldValue)
    -- (the first value on login arrives as a change from 0)
    if not session or not oldValue or oldValue <= 0 or value <= oldValue then
        return
    end
    if startIfIdle() then
        session.xp = session.xp + (value - oldValue)
        changed()
    end
end

-- Experience a level needs (7.x formula)
function experienceForLevel(level)
    level = level - 1
    return math.floor((50 * level ^ 3 - 150 * level ^ 2 + 400 * level) / 3)
end

-- Kills and drops ---------------------------------------------------------------

local function parseLootItem(text)
    local count, name = text:match('^(%d+) (.+)$')
    if not count then
        name = text
        count = 1
    end
    local id = itemData() and itemData().findByName(name)
    return id and tostring(id) or ('name:' .. name:lower():gsub('^an? ', '')), tonumber(count)
end

local function onTextMessage(mode, text)
    if not session then
        return
    end
    local monster, items = text:match('^Loot of (.-): (.+)$')
    if not monster then
        return
    end
    if not startIfIdle() then
        return
    end
    monster = monster:gsub('^an? ', ''):gsub('^the ', '')
    add(session.kills, monster, 1)
    items = items:gsub('%.$', '')
    if items ~= 'nothing' then
        for part in items:gmatch('[^,]+') do
            local key, count = parseLootItem((part:gsub('^%s+', ''):gsub('%s+$', '')))
            add(session.dropped, key, count)
        end
    end
    changed()
end

-- Looting and supplies ----------------------------------------------------------

local function isCarried(container)
    local item = container:getContainerItem()
    local position = item and item:getPosition()
    return position and position.x == 65535
end

local function now()
    return g_clock.millis()
end

local function expire(list)
    local t = now()
    for index = #list, 1, -1 do
        if t - list[index].time > MOVE_WINDOW then
            table.remove(list, index)
        end
    end
end

-- Something arrived in the player's containers: from a corpse it is loot;
-- a supply that went down just before was only moved
local function arrived(key, count)
    expire(pendingFromGround)
    for index, pending in ipairs(pendingFromGround) do
        if pending.key == key then
            local taken = math.min(count, pending.count)
            if session.state == 'tracking' then
                add(session.looted, key, taken)
                changed()
            end
            pending.count = pending.count - taken
            if pending.count <= 0 then
                table.remove(pendingFromGround, index)
            end
            return
        end
    end
    for index, pending in ipairs(pendingUsed) do
        if pending.key == key then
            table.remove(pendingUsed, index)
            return
        end
    end
end

-- A supply went down: counted as used unless it turns up in another of the
-- player's containers (a move) within the move window
local function wentDown(key, count)
    if session.state ~= 'tracking' then
        return
    end
    local entry = { key = key, count = count, time = now() }
    table.insert(pendingUsed, entry)
    scheduleEvent(function()
        for index, pending in ipairs(pendingUsed) do
            if pending == entry then
                table.remove(pendingUsed, index)
                if session and session.state == 'tracking' then
                    add(session.supplies, key, count)
                    changed()
                end
                return
            end
        end
    end, MOVE_WINDOW)
end

local function countOf(item)
    return item:isStackable() and item:getCount() or 1
end

local function onAddItem(container, slot, item)
    if session and item and isCarried(container) then
        arrived(itemKey(item), countOf(item))
    end
end

local function onRemoveItem(container, slot, item)
    if not session or not item then
        return
    end
    if not isCarried(container) then
        table.insert(pendingFromGround, { key = itemKey(item), count = countOf(item), time = now() })
    elseif knownRunes[item:getId()] and item:getCountOrSubType() <= 1 then
        -- a rune's last charge
        wentDown(itemKey(item), 1)
    end
end

local function onUpdateItem(container, slot, item, oldItem)
    if not session or not item or not oldItem or item:getId() ~= oldItem:getId() then
        return
    end
    if not isCarried(container) then
        -- part of a stack taken from a corpse
        local taken = countOf(oldItem) - countOf(item)
        if taken > 0 then
            table.insert(pendingFromGround, { key = itemKey(oldItem), count = taken, time = now() })
        end
        return
    end
    if item:isFluidContainer() then
        -- a vial emptied
        if oldItem:getSubType() > 0 and item:getSubType() == 0 then
            wentDown(itemKey(oldItem), 1)
        end
    elseif item:isStackable() then
        local delta = item:getCount() - oldItem:getCount()
        if delta > 0 then
            arrived(itemKey(item), delta)
        end
    else
        -- charges used (runes)
        local used = oldItem:getCountOrSubType() - item:getCountOrSubType()
        if used > 0 then
            knownRunes[item:getId()] = true
            wentDown(itemKey(item), used)
        end
    end
end

local function onInventoryChange(player, slot, item, oldItem)
    if not session or slot ~= InventorySlotAmmo or not oldItem then
        return
    end
    -- arrows and bolts shot
    if not item or item:getId() == oldItem:getId() then
        local used = countOf(oldItem) - (item and countOf(item) or 0)
        if used > 0 then
            wentDown(itemKey(oldItem), used)
        end
    end
end

-- Kept per character across logins
local SESSION_SETTING = 'client_hunt_session'

local function saveSession()
    local name = g_game.getCharacterName()
    if not session or not name or name == '' then
        return
    end
    local all = g_settings.getNode(SESSION_SETTING) or {}
    local copy = {}
    for key, value in pairs(session) do
        copy[key] = value
    end
    copy.elapsed = sessionSeconds()
    copy.stretchStart = nil
    if copy.state == 'tracking' then
        copy.state = 'paused'
    end
    all[name] = copy
    g_settings.setNode(SESSION_SETTING, all)
    g_settings.save()
end

local function loadSession()
    local all = g_settings.getNode(SESSION_SETTING) or {}
    local saved = all[g_game.getCharacterName()]
    resetSession()
    if type(saved) == 'table' then
        for key, value in pairs(saved) do
            session[key] = value
        end
        -- (a hunt carries on where it was after a relog)
        if session.state == 'paused' and session.resumeOnLogin then
            session.stretchStart = g_clock.seconds()
            session.state = 'tracking'
        end
    end
end

function trackerGameStart()
    loadSession()
    session.resumeOnLogin = nil
end

function trackerGameEnd()
    if session then
        session.resumeOnLogin = session.state == 'tracking'
    end
    saveSession()
    session = nil
end

function initTracker()
    if itemData() then
        itemData().onReady(resolveNames)
    end
    connect(LocalPlayer, { onExperienceChange = onExperienceChange, onInventoryChange = onInventoryChange })
    connect(g_game, { onTextMessage = onTextMessage })
    connect(Container, { onAddItem = onAddItem, onRemoveItem = onRemoveItem, onUpdateItem = onUpdateItem })
end

function terminateTracker()
    disconnect(LocalPlayer, { onExperienceChange = onExperienceChange, onInventoryChange = onInventoryChange })
    disconnect(g_game, { onTextMessage = onTextMessage })
    disconnect(Container, { onAddItem = onAddItem, onRemoveItem = onRemoveItem, onUpdateItem = onUpdateItem })
end
