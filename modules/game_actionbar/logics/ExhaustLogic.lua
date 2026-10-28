-- /*=============================================
-- =   Server exhaust (7.x): hotbar cooldowns    =
-- =============================================*/
-- 7.92 has no cooldown messages, so our server sends them as extended
-- opcode 106 (JSON):
--   {"kind":"groups","spells":{"exura":"healing",...},"runes":{"3155":"attack",...}}
--     at login: the exhaust group of each spell (by words) and rune (by item id)
--   {"kind":"spell","group":"attack","ms":2000}
--     a cast: every spell and rune of that group is blocked for `ms`
--   {"kind":"item","ms":1000}
--     an item use: every item slot is blocked for `ms` (the next-action delay)

local EXHAUST_OPCODE = 106
local READY_FLASH_MS = 400

local exhaustGroups = { spells = {}, runes = {} }
local exhaustUntil = {} -- [group name or "item"] = g_clock.millis() when it ends

local itemUseTypes = {
    [UseTypes["Use"]] = true,
    [UseTypes["UseOnYourself"]] = true,
    [UseTypes["UseOnTarget"]] = true,
    [UseTypes["SelectUseTarget"]] = true,
    [UseTypes["UseAtCursorPosition"]] = true
}

-- The group of the spell a chat text casts: the longest spell words it starts
-- with ('exiva "name' is exiva)
local function spellGroupOfText(text)
    if not text then
        return nil
    end
    text = text:lower()
    local group, length = nil, 0
    for words, spellGroup in pairs(exhaustGroups.spells) do
        if #words > length and text:sub(1, #words) == words then
            local rest = text:sub(#words + 1, #words + 1)
            if rest == '' or rest == ' ' then
                group, length = spellGroup, #words
            end
        end
    end
    return group
end

-- What blocks an action: the spell group of a cast, and for an item use the
-- item delay plus, for a rune, its spell group
local function exhaustKeys(chatText, itemId, actionType)
    local keys = {}
    if chatText then
        keys[#keys + 1] = spellGroupOfText(chatText)
    elseif itemId and itemId > 0 and itemUseTypes[actionType] then
        keys[#keys + 1] = 'item'
        keys[#keys + 1] = exhaustGroups.runes[tostring(itemId)]
    end
    return keys
end

local function remainingFor(keys)
    local now = g_clock.millis()
    local remaining = 0
    for _, key in ipairs(keys) do
        remaining = math.max(remaining, (exhaustUntil[key] or 0) - now)
    end
    return remaining
end

-- The exhaust left on an action (a multi-action entry: chatText / useObject)
function getServerExhaustRemaining(action)
    if not action then
        return 0
    end
    local useType = action["useType"]
    if type(useType) == 'string' then
        useType = UseTypes[useType]
    end
    useType = useType or UseTypes["Use"]
    return remainingFor(exhaustKeys(action["chatText"], action["useObject"], useType))
end

local function buttonExhaustRemaining(button)
    local cache = button.cache
    if not cache then
        return 0
    end
    local chatText = cache.actionType == UseTypes["chatText"] and cache.param or nil
    return remainingFor(exhaustKeys(chatText, cache.itemId, cache.actionType))
end

-- Shows the exhaust left on a button (none: nothing changes); a longer
-- cooldown already showing is kept
function applyServerExhaust(button)
    if not button or button:isDestroyed() or not button.cooldown then
        return
    end
    local showProgress = modules.client_options.getOption("graphicalCooldown")
    local showTime = modules.client_options.getOption("cooldownSecond")
    if not showProgress and not showTime then
        return
    end

    local remaining = buttonExhaustRemaining(button)
    if remaining <= 0 then
        return
    end
    local cooldown = button.cooldown
    if cooldown:getDuration() - cooldown:getTimeElapsed() >= remaining then
        return
    end

    updateCooldown(button, remaining)
    -- seconds only for cooldowns over a second
    cooldown:showTime(showTime and remaining > 1000)
    if button.cache.removeCooldownEvent then
        removeEvent(button.cache.removeCooldownEvent)
    end
    button.cache.removeCooldownEvent = scheduleEvent(function()
        if button:isDestroyed() then
            return
        end
        removeCooldown(button)
        button.cooldown:flash(READY_FLASH_MS)
    end, remaining)
end

local function onExhaust(key, ms)
    exhaustUntil[key] = g_clock.millis() + ms
    for _, actionbar in pairs(activeActionBars) do
        for _, button in pairs(actionbar.tabBar:getChildren()) do
            local cache = button.cache
            if cache and cache.multiActions and not table.empty(cache.multiActions) then
                updateMultiButtonState(button)
                scheduleMultiActionCooldownEvent(button, 'exhaust_' .. key, ms)
            end
            applyServerExhaust(button)
        end
    end
end

local function onExhaustMessage(protocol, opcode, data)
    if type(data) ~= 'table' then
        return
    end
    if data.kind == 'groups' then
        exhaustGroups = { spells = data.spells or {}, runes = data.runes or {} }
    elseif data.kind == 'spell' and data.group and tonumber(data.ms) then
        onExhaust(data.group, tonumber(data.ms))
    elseif data.kind == 'item' and tonumber(data.ms) then
        onExhaust('item', tonumber(data.ms))
    end
end

function registerServerExhaust()
    ProtocolGame.registerExtendedJSONOpcode(EXHAUST_OPCODE, onExhaustMessage)
end

function resetServerExhaust()
    exhaustGroups = { spells = {}, runes = {} }
    exhaustUntil = {}
end

function unregisterServerExhaust()
    ProtocolGame.unregisterExtendedJSONOpcode(EXHAUST_OPCODE)
    resetServerExhaust()
end
