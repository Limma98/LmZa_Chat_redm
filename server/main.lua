-- LmZa_Chat · server/main.lua

local users = {}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function checkSpam(src, message)
    local now = GetGameTimer()  -- monotonic ms (wall-clock, unlike os.clock)

    if not users[src] then
        users[src] = { time = now, lastMessage = '' }
        return false
    end

    local blocked = false

    if (now - users[src].time) < Config.SpamCooldownMs then
        blocked = true
    end

    if message == users[src].lastMessage then
        blocked = true
    end

    users[src].lastMessage = message
    users[src].time        = now

    return blocked
end

local function timestamp()
    return os.date('%I:%M %p')
end

-- ─── Global chat ─────────────────────────────────────────────────────────────

RegisterNetEvent('LmZa_Chat:sendMessage')
AddEventHandler('LmZa_Chat:sendMessage', function(message)
    local src  = source
    local name = GetPlayerName(src)
    if not name or name == '' then return end

    message = message:match('^%s*(.-)%s*$')
    if message == '' then return end
    if #message > Config.MaxMessageLength then
        message = message:sub(1, Config.MaxMessageLength)
    end

    if checkSpam(src, message) then
        TriggerClientEvent('LmZa_Chat:systemMessage', src, 'Slow down, partner.')
        return
    end

    local ts = timestamp()
    TriggerClientEvent('LmZa_Chat:receiveMessage', -1, name, message, ts)
    print(string.format('[LmZa_Chat] GLOBAL %s (%s): %s', name, src, message))
end)

-- ─── /me — server validates then fires back to the sender's client only ───────
-- The sender's client is responsible for rendering 3D text locally and
-- broadcasting a proximity TriggerClientEvent to nearby players.
-- We keep server involved only for spam-check + authoritative player name.

RegisterNetEvent('LmZa_Chat:sendMe')
AddEventHandler('LmZa_Chat:sendMe', function(action)
    local src  = source
    local name = GetPlayerName(src)
    if not name or name == '' then return end

    action = action:match('^%s*(.-)%s*$')
    if action == '' then return end
    if #action > Config.MaxMessageLength then
        action = action:sub(1, Config.MaxMessageLength)
    end

    if checkSpam(src, action) then
        TriggerClientEvent('LmZa_Chat:systemMessage', src, 'Slow down, partner.')
        return
    end

    -- Tell ALL clients about this /me so each one can decide locally
    -- whether the source player is within range and render 3D text if so.
    TriggerClientEvent('LmZa_Chat:showMe', -1, src, name, action)
    print(string.format('[LmZa_Chat] ME %s (%s): %s', name, src, action))
end)

-- ─── Cleanup ─────────────────────────────────────────────────────────────────

AddEventHandler('playerDropped', function()
    users[source] = nil
end)
