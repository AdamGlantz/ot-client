-- Saving battery:
--   - Low power mode (Options > Graphics, off by default): 30 frames per
--     second, no antialiasing or floor fading, effect optimisation on. The
--     player's own values for these options stay saved and come back when
--     it is switched off.
--   - While the page is hidden (another tab, a minimised window, the phone's
--     screen off) the client draws 5 frames per second: nothing is seen,
--     and the game keeps running (the connection stays up).

local LOW_POWER_FPS = 30
local HIDDEN_FPS = 5
-- Options low power mode overrides while it is on
local OVERRIDDEN = { 'backgroundFrameRate', 'antialiasingMode', 'floorFading', 'forceEffectOptimization', 'optimizeFps' }

local lowPower = false
local pageHidden = false
local checkEvent

local function option(key)
    return modules.client_options.getOption(key)
end

-- The frame rate limit the options ask for (0: none)
local function optionFps()
    local value = option('backgroundFrameRate') or 0
    return (value <= 0 or value >= 501) and 0 or value
end

local function applyFps()
    if pageHidden then
        g_app.setMaxFps(HIDDEN_FPS)
    elseif lowPower then
        local fps = optionFps()
        g_app.setMaxFps((fps == 0 or fps > LOW_POWER_FPS) and LOW_POWER_FPS or fps)
    else
        g_app.setMaxFps(optionFps())
    end
end

function setLowPower(enabled)
    if enabled == lowPower then
        return
    end
    lowPower = enabled
    local map = modules.game_interface and modules.game_interface.getMapPanel()
    if enabled then
        if map then
            map:setAntiAliasingMode(0)
            map:setFloorFading(0)
        end
        g_app.forceEffectOptimization(true)
        g_app.optimize(true)
    else
        -- the player's own values again
        for _, key in ipairs(OVERRIDDEN) do
            modules.client_options.setOption(key, option(key), true)
        end
    end
    applyFps()
end

local function checkPage()
    local hidden = not g_platform.isPageVisible()
    if hidden ~= pageHidden then
        pageHidden = hidden
        applyFps()
    end
end

function init()
    if modules.client_options.getOption('lowPowerMode') then
        setLowPower(true)
    end
    -- The map is set up when the game starts; apply again then
    connect(g_game, { onGameStart = onGameStart })
    if g_platform.isBrowser() then
        checkEvent = cycleEvent(checkPage, 500)
    end
end

function onGameStart()
    if lowPower then
        lowPower = false
        setLowPower(true)
    end
end

function terminate()
    disconnect(g_game, { onGameStart = onGameStart })
    if checkEvent then
        removeEvent(checkEvent)
        checkEvent = nil
    end
    if lowPower then
        setLowPower(false)
    end
end
