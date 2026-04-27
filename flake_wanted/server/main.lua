local QBCore, ESX = nil, nil
local wantedPlayers = {} -- key: server player ID (int), value: { reason, officer, firstName, lastName, time }

CreateThread(function()
    if GetResourceState(Config.QBCoreGetCoreObject) ~= 'missing' then
        QBCore = exports[Config.QBCoreGetCoreObject]:GetCoreObject()
    elseif GetResourceState(Config.ESXgetSharedObject) ~= 'missing' then
        ESX = exports[Config.ESXgetSharedObject]:getSharedObject()
    end
end)

-- Returns firstName, lastName for a connected player
local function GetCharacterName(source)
    if QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player and Player.PlayerData and Player.PlayerData.charinfo then
            return Player.PlayerData.charinfo.firstname, Player.PlayerData.charinfo.lastname
        end
    elseif ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local full = xPlayer.getName() or ""
            local parts = {}
            for p in full:gmatch("%S+") do parts[#parts + 1] = p end
            if #parts >= 2 then return parts[1], parts[2] end
            return full, ""
        end
    end
    -- Fallback: split the native player name
    local raw = GetPlayerName(source) or "Unknown"
    local parts = {}
    for p in raw:gmatch("%S+") do parts[#parts + 1] = p end
    if #parts >= 2 then return parts[1], parts[2] end
    return raw, "Player"
end

local function GetFullName(source)
    local f, l = GetCharacterName(source)
    return (f or "") .. " " .. (l or "")
end

local function hasRequiredJob(source)
    if QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player and Config.JobLock[Player.PlayerData.job.name] then return true end
    elseif ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer and Config.JobLock[xPlayer.getJob().name] then return true end
    end
    return false
end

local function ForEachPolice(cb)
    for _, pid in ipairs(GetPlayers()) do
        local playerId = tonumber(pid)
        if hasRequiredJob(playerId) then cb(playerId) end
    end
end

-- ============================================================
-- DATABASE
-- ============================================================

CreateThread(function()
    if Config.UseDatabase then
        MySQL.query([[
            CREATE TABLE IF NOT EXISTS `wanted_records` (
                `id`        int(11)      NOT NULL AUTO_INCREMENT,
                `officer`   varchar(50)  DEFAULT NULL,
                `target`    varchar(50)  DEFAULT NULL,
                `reason`    text         DEFAULT NULL,
                `action`    varchar(50)  DEFAULT NULL,
                `timestamp` timestamp    NOT NULL DEFAULT current_timestamp(),
                PRIMARY KEY (`id`)
            )
        ]])
    end
end)

local function SaveRecord(officer, target, reason, action)
    if Config.UseDatabase then
        MySQL.insert('INSERT INTO wanted_records (officer, target, reason, action) VALUES (?, ?, ?, ?)', {
            officer, target, reason, action
        })
    end
    LogWantedAction(officer, target, reason, action)
end

-- ============================================================
-- SERVER-SIDE POSITION BROADCAST
-- Reads wanted players' ped coords directly on the server and
-- pushes them to all online police every second.  This is the
-- fallback for when the wanted player is outside the officer's
-- streaming range; the client's own 100ms thread handles
-- in-range live tracking without any server involvement.
-- ============================================================

CreateThread(function()
    while true do
        Wait(1000)
        for targetId, data in pairs(wantedPlayers) do
            if GetPlayerEndpoint(targetId) then
                local ped = GetPlayerPed(targetId)
                local coords = GetEntityCoords(ped)
                ForEachPolice(function(pid)
                    TriggerClientEvent('flake_wanted:client:updateWantedBlip', pid, targetId, coords, data.firstName, data.lastName)
                end)
            else
                -- Player disconnected mid-warrant; clean up
                wantedPlayers[targetId] = nil
            end
        end
    end
end)

-- ============================================================
-- WANTED EVENTS
-- ============================================================

RegisterNetEvent('flake_wanted:server:setWanted', function(targetId, reason)
    local source = source
    if not hasRequiredJob(source) then
        TriggerClientEvent('flake_wanted:client:notify', source, "You don't have permission.", "error")
        return
    end

    local targetPlayer = tonumber(targetId)
    if not targetPlayer or not GetPlayerEndpoint(targetPlayer) then
        TriggerClientEvent('flake_wanted:client:notify', source, "Player not found.", "error")
        return
    end

    local officerName             = GetFullName(source)
    local targetName              = GetFullName(targetPlayer)
    local firstName, lastName     = GetCharacterName(targetPlayer)

    wantedPlayers[targetPlayer] = {
        reason    = reason,
        officer   = officerName,
        firstName = firstName,
        lastName  = lastName,
        time      = os.time()
    }

    -- Ask target to capture and return their mugshot; the rest of the
    -- flow continues in flake_wanted:server:receiveMugshot
    TriggerClientEvent('flake_wanted:client:getMugshot', targetPlayer, reason, officerName)

    ForEachPolice(function(pid)
        TriggerClientEvent('flake_wanted:client:notify', pid, targetName .. " is now wanted for: " .. reason, "inform")
    end)

    SaveRecord(officerName, targetName, reason, "Wanted")
end)

RegisterNetEvent('flake_wanted:server:removeWanted', function(targetId)
    local source = source
    local targetPlayer

    if targetId then
        -- Officer explicitly removing a warrant
        if not hasRequiredJob(source) then
            TriggerClientEvent('flake_wanted:client:notify', source, "You don't have permission.", "error")
            return
        end
        targetPlayer = tonumber(targetId)
        if not targetPlayer then
            TriggerClientEvent('flake_wanted:client:notify', source, "Invalid player.", "error")
            return
        end
    else
        -- Wanted timer expired on the client; source == the wanted player
        targetPlayer = source
    end

    if wantedPlayers[targetPlayer] then
        local officerName = GetFullName(source)
        local targetName  = GetFullName(targetPlayer)

        wantedPlayers[targetPlayer] = nil

        TriggerClientEvent('flake_wanted:client:removeWanted', targetPlayer)

        ForEachPolice(function(pid)
            TriggerClientEvent('flake_wanted:client:removeWantedBlip', pid, targetPlayer)
            TriggerClientEvent('flake_wanted:client:notify', pid, targetName .. " is no longer wanted.", "inform")
        end)

        if targetId then
            SaveRecord(officerName, targetName, "N/A", "Wanted Removed")
        end
    else
        if targetId then
            TriggerClientEvent('flake_wanted:client:notify', source, "That player is not currently wanted.", "error")
        end
    end
end)

-- Receives the mugshot from the target; finalises the wanted broadcast
RegisterNetEvent('flake_wanted:server:receiveMugshot', function(reason, officerName, mugshot)
    local source      = source
    local targetPlayer = source
    local firstName, lastName = GetCharacterName(targetPlayer)

    TriggerClientEvent('flake_wanted:client:setWanted', targetPlayer, reason, Config.Duration, firstName, lastName, mugshot)

    ForEachPolice(function(pid)
        if pid ~= targetPlayer then
            TriggerClientEvent('flake_wanted:client:showWantedBroadcast', pid, firstName, lastName, reason, mugshot)
        end
    end)
end)

-- ============================================================
-- JAIL EVENTS
-- ============================================================

RegisterNetEvent('flake_wanted:server:jailPlayer', function(targetId, time, reason)
    local source = source
    if not hasRequiredJob(source) then
        TriggerClientEvent('flake_wanted:client:notify', source, "You don't have permission.", "error")
        return
    end

    local targetPlayer = tonumber(targetId)
    if not targetPlayer or not GetPlayerEndpoint(targetPlayer) then
        TriggerClientEvent('flake_wanted:client:notify', source, "Player not found.", "error")
        return
    end

    local officerName = GetFullName(source)
    local targetName  = GetFullName(targetPlayer)
    local jailMinutes = tonumber(time) or 10

    -- Remove any active warrant for this player
    if wantedPlayers[targetPlayer] then
        wantedPlayers[targetPlayer] = nil
        TriggerClientEvent('flake_wanted:client:removeWanted', targetPlayer)
        ForEachPolice(function(pid)
            TriggerClientEvent('flake_wanted:client:removeWantedBlip', pid, targetPlayer)
        end)
    end

    -- Jail via tk_jail (server-side export; no job check needed here)
    exports.tk_jail:jail(tostring(targetPlayer), jailMinutes, 'jail', nil, true, reason)

    -- Ask target to capture mugshot so the announcement can play
    TriggerClientEvent('flake_wanted:client:getJailMugshot', targetPlayer, jailMinutes, reason, officerName)

    TriggerClientEvent('flake_wanted:client:notify', source, targetName .. " jailed for " .. jailMinutes .. " minutes.", "success")

    LogJailAction(officerName, targetName, jailMinutes, reason)
    SaveRecord(officerName, targetName, reason, "Jailed for " .. jailMinutes .. " minutes")
end)

-- Receives mugshot from the jailed player; broadcasts the jail announcement
RegisterNetEvent('flake_wanted:server:receiveJailMugshot', function(time, reason, officerName, mugshot)
    local source      = source
    local targetPlayer = source
    local firstName, lastName = GetCharacterName(targetPlayer)

    for _, pid in ipairs(GetPlayers()) do
        TriggerClientEvent('flake_wanted:client:showJailAnnouncement', tonumber(pid), firstName, lastName, time, reason, mugshot)
    end
end)

-- ============================================================
-- RAID EVENTS
-- ============================================================

RegisterNetEvent('flake_wanted:server:setRaid', function(location, reason)
    local source = source
    if not hasRequiredJob(source) then
        TriggerClientEvent('flake_wanted:client:notify', source, "You don't have permission.", "error")
        return
    end

    local officerName = GetFullName(source)

    for _, pid in ipairs(GetPlayers()) do
        TriggerClientEvent('flake_wanted:client:showRaidUI', tonumber(pid), location, reason)
    end

    ForEachPolice(function(pid)
        TriggerClientEvent('flake_wanted:client:notify', pid, "Raid in progress at " .. location .. ". Reason: " .. reason, "inform")
    end)

    LogRaidAction(officerName, location, reason)
    SaveRecord(officerName, location, reason, "Raid")
end)

RegisterNetEvent('flake_wanted:server:endRaid', function(location)
    local source = source
    if not hasRequiredJob(source) then
        TriggerClientEvent('flake_wanted:client:notify', source, "You don't have permission.", "error")
        return
    end

    local officerName = GetFullName(source)

    for _, pid in ipairs(GetPlayers()) do
        TriggerClientEvent('flake_wanted:client:showRaidEndUI', tonumber(pid), location)
    end

    ForEachPolice(function(pid)
        TriggerClientEvent('flake_wanted:client:notify', pid, "Raid at " .. location .. " has ended.", "inform")
    end)

    SaveRecord(officerName, location, "N/A", "Raid Ended")
end)

-- ============================================================
-- MISC
-- ============================================================

-- Clean up blips for all police when a wanted player disconnects
AddEventHandler('playerDropped', function()
    local source = source
    if wantedPlayers[source] then
        wantedPlayers[source] = nil
        ForEachPolice(function(pid)
            TriggerClientEvent('flake_wanted:client:removeWantedBlip', pid, source)
        end)
    end
end)

RegisterCommand('wantedlist', function(source, args)
    if not hasRequiredJob(source) then
        TriggerClientEvent('flake_wanted:client:notify', source, "You don't have permission.", "error")
        return
    end

    local list     = "Current Wanted Players:\n"
    local hasEntry = false

    for playerId, data in pairs(wantedPlayers) do
        if GetPlayerEndpoint(playerId) then
            local elapsed   = os.difftime(os.time(), data.time)
            local remaining = math.max(0, (Config.Duration * 60) - elapsed)
            local m         = math.floor(remaining / 60)
            local s         = math.floor(remaining % 60)
            list     = list .. data.firstName .. " " .. data.lastName ..
                       " (ID: " .. playerId .. ") - " .. data.reason ..
                       " - " .. m .. "m " .. s .. "s\n"
            hasEntry = true
        end
    end

    if not hasEntry then list = "No players are currently wanted." end

    TriggerClientEvent('chat:addMessage', source, {
        color     = {255, 255, 0},
        multiline = true,
        args      = {"WANTED LIST", list}
    })
end, false)

RegisterNetEvent('flake_wanted:server:getOnlinePlayers', function()
    local source  = source
    local players = {}

    for _, pid in ipairs(GetPlayers()) do
        local id              = tonumber(pid)
        local firstName, lastName = GetCharacterName(id)
        players[#players + 1] = {
            value = id,
            label = firstName .. " " .. lastName .. " (ID: " .. id .. ")"
        }
    end

    TriggerClientEvent('flake_wanted:client:receiveOnlinePlayers', source, players)
end)

-- Exported function for external resources (e.g. tk_jail callbacks)
function AnnounceJail(target, time, reason, officer)
    local targetPlayer = tonumber(target)
    if not targetPlayer or not GetPlayerEndpoint(targetPlayer) then return false end

    local officerName = officer or "System"
    local targetName  = GetFullName(targetPlayer)

    exports.tk_jail:jail(tostring(targetPlayer), time, 'jail', nil, true, reason)
    TriggerClientEvent('flake_wanted:client:getJailMugshot', targetPlayer, time, reason, officerName)
    LogJailAction(officerName, targetName, time, reason)
    SaveRecord(officerName, targetName, reason, "Jailed for " .. time .. " minutes")

    return true
end
