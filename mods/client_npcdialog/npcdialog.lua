-- Tap-to-talk NPC dialog. The server (extended opcode 103, JSON) describes
-- the NPC the player talks to after each answer: what it said, the keywords
-- in it, whether it asked a yes/no question, and its shop and travel offers
-- as this player gets them. Buttons say the words for the player (the NPC's
-- own rules do the trading); after a shop or travel choice the NPC's
-- "Do you want...?" is answered "yes" automatically. Typing still works.

local NPC_DIALOG_OPCODE = 103
local TEXT_COLOR = '#e8e8e8'
local KEYWORD_COLOR = '#f0d070'
local AUTO_YES_TIMEOUT = 4000

local window
local dialog -- the last message from the server
local view = 'talk' -- 'talk', 'trade' or 'travel'
local tradeTab = 'buy'
local selected -- the chosen offer (shop or travel)
local autoYesUntil = 0

local function say(text)
    if g_game.isOnline() then
        g_game.talk(text)
    end
end

local function shortGold(value)
    if value >= 10000 and value % 1000 == 0 then
        return (value / 1000) .. 'k'
    end
    return tostring(value)
end

-- "{text, #color}" segments with the keywords in gold
local function coloredAnswer(text, keywords)
    text = text:gsub('[{}]', '')
    local lower = text:lower()
    local marks = {}
    for _, keyword in ipairs(keywords) do
        -- the first time it stands as a whole word
        local from, to = 0, 0
        repeat
            from, to = lower:find(keyword:lower(), to + 1, true)
        until not from or ((from == 1 or not lower:sub(from - 1, from - 1):match('%a')) and not lower:sub(to + 1, to + 1):match('%a'))
        if from then
            table.insert(marks, { from = from, to = to })
        end
    end
    table.sort(marks, function(a, b) return a.from < b.from end)
    local out, at = '', 1
    for _, mark in ipairs(marks) do
        if mark.from >= at then
            if mark.from > at then
                out = out .. '{' .. text:sub(at, mark.from - 1) .. ', ' .. TEXT_COLOR .. '}'
            end
            out = out .. '{' .. text:sub(mark.from, mark.to) .. ', ' .. KEYWORD_COLOR .. '}'
            at = mark.to + 1
        end
    end
    if at <= #text then
        out = out .. '{' .. text:sub(at) .. ', ' .. TEXT_COLOR .. '}'
    end
    return out
end

local function fitWindow()
    addEvent(function()
        if window then
            local content = window:getChildById('content')
            window:setHeight(content:getHeight() + window:getPaddingTop() + window:getPaddingBottom() + 4)
        end
    end)
end

local function addButton(parent, text, onClick, on)
    local button = g_ui.createWidget('NpcDialogButton', parent)
    button:setText(text)
    button:setOn(on == true)
    button.onClick = onClick
    return button
end

local render

local function setView(name)
    view = name
    selected = nil
    render()
end

local function offerAmount()
    local chosen = window:recursiveGetChildById('chosen')
    local scroll = chosen:getChildById('amount')
    return scroll:isVisible() and scroll:getValue() or 1
end

local function updateChosen()
    local chosen = window:recursiveGetChildById('chosen')
    chosen:setVisible(selected ~= nil and view == 'trade')
    if not selected or view ~= 'trade' then
        return
    end
    chosen:getChildById('item'):setItemId(selected.item)
    chosen:getChildById('name'):setText(selected.name)
    local weight = selected.weight and selected.weight > 0 and string.format(', %.2f oz', selected.weight / 100) or ''
    chosen:getChildById('each'):setText(string.format('%d gold each%s', selected.price, weight))
    local amount = offerAmount()
    chosen:getChildById('total'):setText(string.format('%s: %d gold', tr('Total'), selected.price * amount))
end

local function confirm()
    if not selected then
        return
    end
    local words = selected.words
    if view == 'trade' then
        local amount = offerAmount()
        if amount > 1 then
            -- the NPC's amount rules: "5 torch", "sell 5 rope"
            if tradeTab == 'sell' then
                words = 'sell ' .. amount .. ' ' .. words:gsub('^sell ', '')
            else
                words = amount .. ' ' .. words
            end
        end
    end
    autoYesUntil = g_clock.millis() + AUTO_YES_TIMEOUT
    say(words)
end

local function renderTrade()
    local trade = window:recursiveGetChildById('trade')
    local offers = trade:getChildById('offers')
    offers:destroyChildren()
    local list = (dialog[tradeTab] or {})
    trade:recursiveGetChildById('buyTab'):setOn(tradeTab == 'buy')
    trade:recursiveGetChildById('buyTab'):setEnabled(#(dialog.buy or {}) > 0)
    trade:recursiveGetChildById('sellTab'):setOn(tradeTab == 'sell')
    trade:recursiveGetChildById('sellTab'):setEnabled(#(dialog.sell or {}) > 0)
    for _, offer in ipairs(list) do
        local cell = g_ui.createWidget('NpcOfferCell', offers)
        cell:getChildById('item'):setItemId(offer.item)
        cell:getChildById('price'):setText(shortGold(offer.price))
        cell:setTooltip(string.format('%s: %d gold', offer.name, offer.price))
        cell:setOn(selected == offer)
        cell.onClick = function()
            selected = offer
            local scroll = window:recursiveGetChildById('chosen'):getChildById('amount')
            scroll:setVisible(offer.amounts == true)
            scroll:setValue(1)
            render()
        end
    end
    updateChosen()
end

local function renderTravel()
    local travel = window:recursiveGetChildById('travel')
    travel:destroyChildren()
    for _, offer in ipairs(dialog.travel or {}) do
        local row = g_ui.createWidget('NpcTravelRow', travel)
        row:getChildById('name'):setText(offer.name)
        row:getChildById('price'):setText(string.format('%d gold', offer.price))
        row:setOn(selected == offer)
        row.onClick = function()
            selected = offer
            render()
        end
    end
end

render = function()
    if not window or not dialog then
        return
    end
    window:setText(dialog.npc)
    local answer = window:recursiveGetChildById('answer')
    answer:setColoredText(coloredAnswer(dialog.text or '', dialog.keywords or {}))

    local buttons = window:recursiveGetChildById('buttons')
    buttons:destroyChildren()
    if view == 'talk' then
        if dialog.question then
            addButton(buttons, tr('Yes'), function() say('yes') end, true)
            addButton(buttons, tr('No'), function() say('no') end)
        end
        for _, keyword in ipairs(dialog.keywords or {}) do
            addButton(buttons, keyword, function() say(keyword) end)
        end
        if #(dialog.buy or {}) + #(dialog.sell or {}) > 0 then
            addButton(buttons, tr('Trade'), function()
                tradeTab = #(dialog.buy or {}) > 0 and 'buy' or 'sell'
                setView('trade')
            end, true)
        end
        if #(dialog.travel or {}) > 0 then
            addButton(buttons, tr('Travel'), function() setView('travel') end, true)
        end
        addButton(buttons, tr('Bye'), function() say('bye') end)
    end
    buttons:setVisible(#buttons:getChildren() > 0)

    window:recursiveGetChildById('trade'):setVisible(view == 'trade')
    window:recursiveGetChildById('travel'):setVisible(view == 'travel')
    if view == 'trade' then
        renderTrade()
    elseif view == 'travel' then
        renderTravel()
    end
    local confirmButton = window:recursiveGetChildById('confirm')
    confirmButton:setVisible(view ~= 'talk')
    confirmButton:setEnabled(selected ~= nil)
    window:recursiveGetChildById('back'):setVisible(view ~= 'talk')
    window:recursiveGetChildById('actions'):setVisible(view ~= 'talk')
    fitWindow()
end

local function onDialog(protocol, opcode, buffer)
    local ok, data = pcall(json.decode, buffer)
    if not ok or type(data) ~= 'table' then
        return
    end
    if data.close then
        if dialog and dialog.id == data.id then
            close()
        end
        return
    end
    -- A shop or travel choice was just made: answer the NPC's question
    if data.question and autoYesUntil > g_clock.millis() then
        autoYesUntil = 0
        say('yes')
        return
    end
    autoYesUntil = 0
    local sameNpc = dialog and dialog.id == data.id
    dialog = data
    if not sameNpc then
        view = 'talk'
        selected = nil
    elseif view == 'trade' or view == 'travel' then
        -- after a purchase, the shop stays open with the same choice
        local list = view == 'travel' and (data.travel or {}) or (data[tradeTab] or {})
        local still
        for _, offer in ipairs(list) do
            if selected and offer.words == selected.words then
                still = offer
            end
        end
        selected = still
    end
    render()
    window:show()
    window:raise()
end

function close()
    if window then
        window:hide()
    end
    dialog = nil
    view = 'talk'
    selected = nil
end

function init()
    g_ui.importStyle('npcdialog')
    window = g_ui.createWidget('NpcDialogWindow', rootWidget)
    window:hide()

    local trade = window:recursiveGetChildById('trade')
    trade:recursiveGetChildById('buyTab').onClick = function() tradeTab = 'buy'; selected = nil; render() end
    trade:recursiveGetChildById('sellTab').onClick = function() tradeTab = 'sell'; selected = nil; render() end
    trade:recursiveGetChildById('amount').onValueChange = function() updateChosen() end
    window:recursiveGetChildById('confirm').onClick = confirm
    window:recursiveGetChildById('back').onClick = function() setView('talk') end

    ProtocolGame.registerExtendedOpcode(NPC_DIALOG_OPCODE, onDialog)
    connect(g_game, { onGameEnd = close })
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(NPC_DIALOG_OPCODE)
    disconnect(g_game, { onGameEnd = close })
    if window then
        window:destroy()
        window = nil
    end
end
