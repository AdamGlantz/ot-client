local shortcutsWindow
local shortcuts
local shortcutIcons

function init()
  if not g_platform.isMobile() then return end

  shortcutsWindow = g_ui.displayUI('shortcuts')
  shortcuts = shortcutsWindow.shortcuts
  shortcutIcons = shortcuts.shortcutIcons

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd 
  })
  
  setupShortcuts()
end

function terminate()
  if not g_platform.isMobile() then return end

  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd 
  })

  shortcutsWindow:destroy()
  shortcutsWindow = nil
end

function onGameStart()
  shortcuts:show()
end

function onGameEnd()
  shortcuts:hide()
end

function hide()
  shortcutsWindow:hide()
end

function show()
  shortcutsWindow:show()
end

function setupShortcuts()
  if not g_platform.isMobile() then return end
  for _, widget in ipairs(shortcutIcons:getChildren()) do
    widget.image:setChecked(false)
    widget.lastClicked = 0
    widget.onClick = function()
      if widget.image:isChecked() then
        widget.image:setChecked(false)
        return
      end
      resetShortcuts()
      widget.image:setChecked(true)
      widget.lastClicked = g_clock.millis()
    end
  end
end

function resetShortcuts()
  for _, widget in ipairs(shortcutIcons:getChildren()) do
    widget.image:setChecked(false)
    widget.lastClicked = 0
  end
end

-- Arms a mode from elsewhere (a hotbar action): the next tap on the game
-- attacks, follows, looks or uses; the same one again disarms it
local HINTS = {
  attack = 'Tap a creature to attack it.', follow = 'Tap a creature to follow it.',
  look = 'Tap something to look at it.', use = 'Tap something to use it.',
}
function setShortcut(id)
  local widget = shortcutIcons and shortcutIcons:getChildById(id)
  if not widget then return end
  local armed = widget.image:isChecked()
  resetShortcuts()
  if not armed then
    widget.image:setChecked(true)
    widget.lastClicked = g_clock.millis()
    if modules.game_textmessage then
      modules.game_textmessage.displayStatusMessage(tr(HINTS[id]))
    end
  end
end

function getShortcut()
  for _, widget in ipairs(shortcutIcons:getChildren()) do
    if widget.image:isChecked() then
      return widget:getId()
    end
  end
  return ""
end

function getPanel()
  return shortcuts
end