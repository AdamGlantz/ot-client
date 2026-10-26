-- Only the 7.72 spells (spells772.lua, from the game server) in the client:
-- the action bar's spell list, the spell list window and the recognition of
-- spell words in chat all read SpellInfo.Default. The client ships a
-- modern spell list; each 7.72 spell takes its icon and cooldown group from
-- the modern spell of the same name (or "<name> Rune") or words.

local applied = false

local function modernSpells()
    local byName, byWords = {}, {}
    for name, spell in pairs(SpellInfo.Default) do
        byName[name:lower()] = spell
        if spell.words then
            byWords[spell.words:lower()] = spell
        end
    end
    return byName, byWords
end

function applyClassicSpells()
    if applied or not SpellInfo or not SpellInfo.Default then
        return
    end
    local byName, byWords = modernSpells()
    local spells = {}
    for index, entry in ipairs(SPELLS_772) do
        local modern = byName[entry.name:lower()] or byName[(entry.name .. ' Rune'):lower()] or
            byWords[entry.words] or {}
        spells[entry.name] = {
            id = modern.id or (1000 + index),
            name = entry.name,
            words = entry.words,
            type = entry.type,
            -- 7.x spells need a magic level, not a character level
            level = 1,
            maglevel = entry.maglevel,
            mana = entry.mana,
            soul = entry.soul,
            icon = modern.icon or '',
            clientId = modern.clientId or 0,
            group = modern.group or { [entry.type == 'Conjure' and 3 or 1] = 2000 },
            needTarget = modern.needTarget or false,
            parameter = entry.parameter,
            range = modern.range or -1,
            exhaustion = 1000,
            premium = false,
            vocations = entry.vocations,
            special = false,
            source = modern.source or 0,
        }
    end
    -- in place: modules keep references to these tables
    for name in pairs(SpellInfo.Default) do
        SpellInfo.Default[name] = nil
    end
    for name, spell in pairs(spells) do
        SpellInfo.Default[name] = spell
    end
    applied = true
end
