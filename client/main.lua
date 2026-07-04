-- LmZa_Chat · client/main.lua

local chatInputActive = false
local chatLoaded      = false

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function getTimestamp()
    local _, _, _, hour, minute = GetPosixTime()
    local meridiem = 'AM'
    if hour >= 12 then
        meridiem = 'PM'
        if hour > 12 then hour = hour - 12 end
    end
    if hour == 0 then hour = 12 end
    return string.format('%d:%02d %s', hour, minute, meridiem)
end

local function sendToNUI(data)
    SendNUIMessage(data)
end

-- ─── Receive global chat messages ────────────────────────────────────────────

RegisterNetEvent('LmZa_Chat:receiveMessage')
AddEventHandler('LmZa_Chat:receiveMessage', function(name, message, timestamp)
    sendToNUI({
        type      = 'ON_MESSAGE',
        name      = name,
        message   = message,
        timestamp = timestamp or getTimestamp(),
        isSelf    = (name == GetPlayerName(PlayerId()))
    })
end)

RegisterNetEvent('LmZa_Chat:systemMessage')
AddEventHandler('LmZa_Chat:systemMessage', function(message)
    sendToNUI({
        type      = 'ON_SYSTEM',
        message   = message,
        timestamp = getTimestamp()
    })
end)

-- ─── /me — 3D floating text, proximity only ──────────────────────────────────

-- labelLen avoids recomputing #label on every frame inside the draw loop.
local function Draw3DText(label, labelLen, x, y, z, dist, alpha)
    local onScreen, px, py = GetScreenCoordFromWorldCoord(x, y, z)
    if not onScreen then return end

    if dist < 0.5 then dist = 0.5 end
    local textScale = math.min((1 / dist) * 0.18, 0.35)

    local lineW = (labelLen * textScale * 0.007) + 0.006
    local lineH = 0.0015
    local lineY = py + textScale * 0.055
    DrawRect(px, lineY, lineW, lineH, 200, 120, 30, math.floor(alpha * 0.85))

    SetTextCentre(1)
    SetTextScale(textScale, textScale)
    SetTextFontForCurrentCommand(7)
    SetTextColor(201, 185, 154, alpha)
    SetTextDropshadow(1, 0, 0, 0, 160)
    DisplayText(CreateVarString(10, 'LITERAL_STRING', label), px, py)
end

RegisterNetEvent('LmZa_Chat:showMe')
AddEventHandler('LmZa_Chat:showMe', function(srcPlayer, name, action)
    CreateThread(function()
        local targetPed = GetPlayerPed(GetPlayerFromServerId(srcPlayer))
        if not DoesEntityExist(targetPed) then return end

        local myCoords  = GetEntityCoords(PlayerPedId())
        local tgtCoords = GetEntityCoords(targetPed)
        if #(myCoords - tgtCoords) > Config.MeRange then return end

        -- Precompute once — neither changes during the draw loop
        local labelUpper = string.upper(action)
        local labelLen   = #action
        local endTime    = GetGameTimer() + Config.MeDurationMs
        local offsetZ    = Config.MeOffsetZ

        local now = GetGameTimer()
        while now < endTime do
            if not DoesEntityExist(targetPed) then break end

            local coords = GetEntityCoords(targetPed)
            local myPos  = GetEntityCoords(PlayerPedId())
            local dist   = #(myPos - coords)

            if dist > Config.MeRange then break end

            local remaining = endTime - now
            local alpha = remaining < 1000 and math.floor((remaining / 1000) * 255) or 255

            Draw3DText(labelUpper, labelLen, coords.x, coords.y, coords.z + offsetZ, dist, alpha)
            Wait(0)
            now = GetGameTimer()
        end
    end)
end)

-- ─── Suggestions ─────────────────────────────────────────────────────────────

RegisterNetEvent('chat:addSuggestion')
RegisterNetEvent('chat:addSuggestions')
RegisterNetEvent('chat:removeSuggestion')

local function refreshSuggestions()
    if not GetRegisteredCommands then return end
    local suggestions = {}
    for _, cmd in ipairs(GetRegisteredCommands()) do
        if IsAceAllowed(('command.%s'):format(cmd.name)) then
            suggestions[#suggestions+1] = { name = '/' .. cmd.name, help = cmd.description or '' }
        end
    end
    sendToNUI({ type = 'ON_SUGGESTIONS', suggestions = suggestions })
end

AddEventHandler('chat:addSuggestion', function(name, help, params)
    sendToNUI({
        type       = 'ON_SUGGESTION_ADD',
        suggestion = { name = name, help = help or '', params = params or {} }
    })
end)

AddEventHandler('chat:addSuggestions', function(list)
    for _, s in ipairs(list) do
        sendToNUI({
            type       = 'ON_SUGGESTION_ADD',
            suggestion = { name = s.name, help = s.help or '', params = s.params or {} }
        })
    end
end)

AddEventHandler('chat:removeSuggestion', function(name)
    sendToNUI({ type = 'ON_SUGGESTION_REMOVE', name = name })
end)

AddEventHandler('onClientResourceStart', function()
    Wait(500)
    refreshSuggestions()
end)

-- ─── NUI Callbacks ───────────────────────────────────────────────────────────

RegisterNUICallback('loaded', function(data, cb)
    chatLoaded = true
    cb('ok')
    sendToNUI({
        type        = 'ON_CONFIG',
        fadeTimeout = Config.FadeTimeoutMs,
        maxMessages = Config.MaxMessages,
        historySize = Config.HistorySize,
    })
    refreshSuggestions()
end)

RegisterNUICallback('chatResult', function(data, cb)
    chatInputActive = false
    SetNuiFocus(false)

    if not data.canceled and data.message and data.message ~= '' then
        local msg = data.message:match('^%s*(.-)%s*$')
        if msg ~= '' then
            if msg:sub(1, 1) == '/' then
                ExecuteCommand(msg:sub(2))
            else
                TriggerServerEvent('LmZa_Chat:sendMessage', msg)
            end
        end
    end

    cb('ok')
end)

-- ─── Key detection ───────────────────────────────────────────────────────────

Citizen.CreateThread(function()
    SetTextChatEnabled(false)
    SetNuiFocus(false)

    while true do
        if chatInputActive then
            -- Chat is open — NUI owns the keyboard, nothing to poll
            Wait(250)
        else
            Wait(0)
            if IsControlJustPressed(0, `INPUT_MP_TEXT_CHAT_ALL`) then
                chatInputActive = true
                sendToNUI({ type = 'ON_OPEN' })
                -- Wait for key release before focusing NUI so T doesn't type into the input
                repeat Wait(0) until not IsControlPressed(0, `INPUT_MP_TEXT_CHAT_ALL`)
                SetNuiFocus(true)
            end
        end
    end
end)

-- ─── Resource cleanup on stop ────────────────────────────────────────────────

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        SetNuiFocus(false)
        SetTextChatEnabled(true)
    end
end)

-- ─── Commands ────────────────────────────────────────────────────────────────

-- /clear
RegisterCommand('clear', function()
    sendToNUI({ type = 'ON_CLEAR' })
    SetTimeout(50, function()
        sendToNUI({ type = 'ON_SYSTEM', message = 'Chat cleared.', timestamp = getTimestamp() })
    end)
end, false)

-- /me  — no chat entry; purely 3D world text
RegisterCommand(Config.MeCommand, function(source, args)
    local action = table.concat(args, ' '):match('^%s*(.-)%s*$')
    if action == '' then return end
    TriggerServerEvent('LmZa_Chat:sendMe', action)
end, false)

-- ─── Auto-clear ──────────────────────────────────────────────────────────────

if Config.AutoClearMins and Config.AutoClearMins > 0 then
    CreateThread(function()
        while true do
            Wait(Config.AutoClearMins * 60 * 1000)
            sendToNUI({ type = 'ON_CLEAR' })
            SetTimeout(50, function()
                sendToNUI({ type = 'ON_SYSTEM', message = 'Chat auto-cleared.', timestamp = getTimestamp() })
            end)
        end
    end)
end
