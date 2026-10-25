-- The 7.92 protocol never tells the client the character's vocation; the
-- server sends it to the browser client in an extended opcode at login and
-- after a promotion (jakoblindell/ot-server, sendVocation). With it the
-- action bars grey out spells the character cannot cast.

local VOCATION_OPCODE = 100

-- Server vocation id -> the client's (Knight 1, Paladin 2, Sorcerer 3,
-- Druid 4; promoted + 10)
local CLIENT_VOCATIONS = {
    [1] = 3, [2] = 4, [3] = 2, [4] = 1,     -- sorcerer, druid, paladin, knight
    [5] = 13, [6] = 14, [7] = 12, [8] = 11, -- master sorcerer, elder druid, royal paladin, elite knight
}

local function onVocation(protocol, opcode, buffer)
    local player = g_game.getLocalPlayer()
    local id = tonumber(buffer)
    if player and id then
        player:setVocation(CLIENT_VOCATIONS[id] or 0)
    end
end

function init()
    ProtocolGame.registerExtendedOpcode(VOCATION_OPCODE, onVocation)
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(VOCATION_OPCODE)
end
