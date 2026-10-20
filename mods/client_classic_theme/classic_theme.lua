-- Puts theme/ in front of the client's own files, so any file placed there
-- under the same path (images/..., modules/.../*.json and so on) is used
-- instead. Loads before the client modules (autoload priority 90) so the
-- interface is built from the replaced files.

local THEME_DIR = '/mods/client_classic_theme/theme'

local mountedPath

function init()
    local realDir = g_resources.getRealDir(THEME_DIR)
    if not realDir or realDir == '' then
        g_logger.error('client_classic_theme: theme folder not found')
        return
    end
    mountedPath = realDir:gsub('/+$', '') .. THEME_DIR
    if not g_resources.addSearchPath(mountedPath, true) then
        g_logger.error('client_classic_theme: unable to mount ' .. mountedPath)
        mountedPath = nil
    end
end

function terminate()
    if mountedPath then
        g_resources.removeSearchPath(mountedPath)
        mountedPath = nil
    end
end
