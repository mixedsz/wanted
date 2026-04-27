-- Server-side script for the wanted system
local QBCore, ESX = nil, nil
local wantedPlayers = {}
local raidedPlayers = {}

-- Framework detection and initialization
CreateThread(function()
    if GetResourceState(Config.QBCoreGetCoreObject) ~= 'missing' then
        QBCore = exports[Config.QBCoreGetCoreObject]:GetCoreObject()
    elseif GetResourceState(Config.ESXgetSharedObject) ~= 'missing' then
        ESX = exports[Config.ESXgetSharedObject]:getSharedObject()
    end
end)

-- Function to get player name based on framework
local function GetPlayerName(source)
    if QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            return Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
        end
    elseif ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer.getName()
        end
    end
    return GetPlayerName(source) -- Fallback to native function
end

-- Function to check if player has the required job
local function hasRequiredJob(source)
    if QBCore then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player and Config.JobLock[Player.PlayerData.job.name] then
            return true
        end
    elseif ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer and Config.JobLock[xPlayer.getJob().name] then
            return true
        end
    end
    return false
end

-- Initialize database if enabled
CreateThread(function()
    if Config.UseDatabase then
        MySQL.query([[
            CREATE TABLE IF NOT EXISTS `wanted_records` (
                `id` int(11) NOT NULL AUTO_INCREMENT,
                `officer` varchar(50) DEFAULT NULL,
                `target` varchar(50) DEFAULT NULL,
                `reason` text DEFAULT NULL,
                `action` varchar(50) DEFAULT NULL,
                `timestamp` timestamp NOT NULL DEFAULT current_timestamp(),
                PRIMARY KEY (`id`)
            )
        ]])
    end
end)

-- Function to save record to database
local function SaveRecord(officer, target, reason, action)
    if Config.UseDatabase then
        MySQL.insert('INSERT INTO wanted_records (officer, target, reason, action) VALUES (?, ?, ?, ?)', {
            officer, target, reason, action
        })
    end

    -- Log the action
    LogWantedAction(officer, target, reason, action)
end

-- Event for setting a player as wanted
RegisterNetEvent('flake_wanted:server:setWanted', function(targetId, reason)
    local source = source

    if not hasRequiredJob(source) then
        TriggerClientEvent('flake_wanted:client:notify', source, "You don't have permission to use this command.", "error")
        return
    end

    local targetPlayer = tonumber(targetId)
    if not targetPlayer or not GetPlayerEndpoint(targetPlayer) then
        TriggerClientEvent('flake_wanted:client:notify', source, "Invalid player ID.", "error")
        return
    end

    local officerName = GetPlayerName(source)
    local targetName = GetPlayerName(targetPlayer)

    -- Set player as wanted
    wantedPlayers[targetPlayer] = {
        reason = reason,
        officer = officerName,
        time = os.time()
    }

    -- Request the mugshot from the target player
    TriggerClientEvent('flake_wanted:client:getMugshot', targetPlayer, reason, officerName)

    -- Get first and last name for the UI
    local firstName, lastName = "Unknown", "Suspect"
    if QBCore then
        local Player = QBCore.Functions.GetPlayer(targetPlayer)
        if Player then
            firstName = Player.PlayerData.charinfo.firstname
            lastName = Player.PlayerData.charinfo.lastname
        end
    elseif ESX then
        local xPlayer = ESX.GetPlayerFromId(targetPlayer)
        if xPlayer then
            -- ESX might store names differently, adjust as needed
            local fullName = xPlayer.getName() or "Unknown Suspect"
            local nameParts = {}
            for part in fullName:gmatch("%S+") do
                table.insert(nameParts, part)
            end
            if #nameParts >= 2 then
                firstName = nameParts[1]
                lastName = nameParts[2]
            else
                firstName = fullName
                lastName = ""
            end
        end
    end

    -- The actual setting of wanted status will be handled by the client's response with the mugshot
    -- Notify all police immediately
    for _, playerId in ipairs(GetPlayers()) do
        if hasRequiredJob(tonumber(playerId)) then
            TriggerClientEvent('flake_wanted:client:notify', tonumber(playerId), targetName .. " is now wanted for: " .. reason, "inform")
        end
    end

    -- Save to database
    SaveRecord(officerName, targetName, reason, "Wanted")
end)

-- Event for removing wanted status
RegisterNetEvent('flake_wanted:server:removeWanted', function(targetId)
    local source = source
    local targetPlayer = targetId

    if targetId then
        -- Admin or police is removing wanted status
        if not hasRequiredJob(source) then
            TriggerClientEvent('flake_wanted:client:notify', source, "You don't have permission to use this command.", "error")
            return
        end

        targetPlayer = tonumber(targetId)
        if not targetPlayer or not GetPlayerEndpoint(targetPlayer) then
            TriggerClientEvent('flake_wanted:client:notify', source, "Invalid player ID.", "error")
            return
        end
    else
        -- Player's wanted status expired
        targetPlayer = source
    end

    if wantedPlayers[targetPlayer] then
        local officerName = GetPlayerName(source)
        local targetName = GetPlayerName(targetPlayer)

        -- Remove wanted status
        wantedPlayers[targetPlayer] = nil

        -- Trigger client event for the player
        TriggerClientEvent('flake_wanted:client:removeWanted', targetPlayer)

        -- Notify all police officers to remove the blip
        for _, playerId in ipairs(GetPlayers()) do
            if hasRequiredJob(tonumber(playerId)) then
                TriggerClientEvent('flake_wanted:client:removeWantedBlip', tonumber(playerId))
            end
        end

        -- Save to database if removed by officer
        if targetId then
            SaveRecord(officerName, targetName, "N/A", "Wanted Removed")
        end
    end
end)

-- Event for updating wanted player blip
RegisterNetEvent('flake_wanted:server:updateWantedBlip', function(coords)
    local source = source

    if wantedPlayers[source] then
        -- Get player name for the blip
        local firstName, lastName = "Unknown", "Suspect"
        if QBCore then
            local Player = QBCore.Functions.GetPlayer(source)
            if Player and Player.PlayerData and Player.PlayerData.charinfo then
                firstName = Player.PlayerData.charinfo.firstname
                lastName = Player.PlayerData.charinfo.lastname
            end
        elseif ESX then
            local xPlayer = ESX.GetPlayerFromId(source)
            if xPlayer then
                -- ESX might store names differently, adjust as needed
                firstName = xPlayer.get('firstName') or "Unknown"
                lastName = xPlayer.get('lastName') or "Suspect"
            end
        end

        -- Broadcast to all police
        for _, playerId in ipairs(GetPlayers()) do
            if hasRequiredJob(tonumber(playerId)) then
                TriggerClientEvent('flake_wanted:client:updateWantedBlip', tonumber(playerId), coords, firstName, lastName)
            end
        end
    end
end)

-- Event for setting a raid
RegisterNetEvent('flake_wanted:server:setRaid', function(location, reason)
    local source = source

    if not hasRequiredJob(source) then
        TriggerClientEvent('flake_wanted:client:notify', source, "You don't have permission to use this command.", "error")
        return
    end

    local officerName = GetPlayerName(source)

    -- Notify all police
    for _, playerId in ipairs(GetPlayers()) do
        if hasRequiredJob(tonumber(playerId)) then
            TriggerClientEvent('flake_wanted:client:notify', tonumber(playerId), "Raid in progress at " .. location .. ". Reason: " .. reason, "inform")
        end
    end

    -- Send UI notification to all players
    for _, playerId in ipairs(GetPlayers()) do
        TriggerClientEvent('flake_wanted:client:showRaidUI', tonumber(playerId), location, reason)
    end

    -- Log the raid
    LogRaidAction(officerName, location, reason)

    -- Save to database
    SaveRecord(officerName, location, reason, "Raid")
end)

-- Event for ending a raid
RegisterNetEvent('flake_wanted:server:endRaid', function(location)
    local source = source

    if not hasRequiredJob(source) then
        TriggerClientEvent('flake_wanted:client:notify', source, "You don't have permission to use this command.", "error")
        return
    end

    local officerName = GetPlayerName(source)

    -- Notify all police
    for _, playerId in ipairs(GetPlayers()) do
        if hasRequiredJob(tonumber(playerId)) then
            TriggerClientEvent('flake_wanted:client:notify', tonumber(playerId), "Raid at " .. location .. " has ended.", "inform")
        end
    end

    -- Send UI notification to all players
    for _, playerId in ipairs(GetPlayers()) do
        TriggerClientEvent('flake_wanted:client:showRaidEndUI', tonumber(playerId), location)
    end

    -- Save to database
    SaveRecord(officerName, location, "N/A", "Raid Ended")
end)

-- No longer using raid blips

-- Function to announce jail (exported)
function AnnounceJail(target, time, reason, officer)
    local targetPlayer = tonumber(target)
    if not targetPlayer or not GetPlayerEndpoint(targetPlayer) then return false end

    local officerName = officer or "System"
    local targetName = GetPlayerName(targetPlayer)

    -- Trigger client event
    TriggerClientEvent('flake_wanted:client:jailNotification', targetPlayer, time, reason)

    -- Log the jail
    LogJailAction(officerName, targetName, time, reason)

    -- Save to database
    SaveRecord(officerName, targetName, reason, "Jailed for " .. time .. " minutes")

    -- Announce to all players
    TriggerClientEvent('chat:addMessage', -1, {
        color = {255, 0, 0},
        multiline = true,
        args = {"JAIL ALERT", targetName .. " has been jailed for " .. time .. " minutes. Reason: " .. reason}
    })

    return true
end

-- Event for client notifications
RegisterNetEvent('flake_wanted:client:notify', function(message, type)
    local source = source
    TriggerClientEvent('flake_wanted:client:notify', source, message, type)
end)

-- Event for announcing a warrant without actually setting a player as wanted
RegisterNetEvent('flake_wanted:server:announceWarrant', function(firstName, lastName, reason, mugshot)
    local source = source

    if not hasRequiredJob(source) then
        TriggerClientEvent('flake_wanted:client:notify', source, "You don't have permission to use this command.", "error")
        return
    end

    local officerName = GetPlayerName(source)

    -- Log the announcement
    LogWantedAction(officerName, firstName .. " " .. lastName, reason, "Warrant Announcement")

    -- Broadcast to all players
    for _, playerId in ipairs(GetPlayers()) do
        TriggerClientEvent('flake_wanted:client:showWantedBroadcast', tonumber(playerId), firstName, lastName, reason, mugshot)
    end

    -- Save to database
    SaveRecord(officerName, firstName .. " " .. lastName, reason, "Warrant Announcement")
end)

-- Event to receive mugshot from target player and complete the wanted process
RegisterNetEvent('flake_wanted:server:receiveMugshot', function(reason, officerName, mugshot)
    local source = source
    local targetPlayer = source
    local targetName = GetPlayerName(targetPlayer)

    -- Get first and last name for the UI
    local firstName, lastName = "Unknown", "Suspect"
    if QBCore then
        local Player = QBCore.Functions.GetPlayer(targetPlayer)
        if Player and Player.PlayerData and Player.PlayerData.charinfo then
            firstName = Player.PlayerData.charinfo.firstname
            lastName = Player.PlayerData.charinfo.lastname
        end
    elseif ESX then
        local xPlayer = ESX.GetPlayerFromId(targetPlayer)
        if xPlayer then
            -- ESX might store names differently, adjust as needed
            firstName = xPlayer.get('firstName') or "Unknown"
            lastName = xPlayer.get('lastName') or "Suspect"
        end
    else
        -- Fallback to splitting player name
        local fullName = targetName or "Unknown Suspect"
        local nameParts = {}
        for part in fullName:gmatch("%S+") do
            table.insert(nameParts, part)
        end
        if #nameParts >= 2 then
            firstName = nameParts[1]
            lastName = nameParts[2]
        else
            firstName = fullName
            lastName = ""
        end
    end

    -- Trigger client event for the wanted player
    TriggerClientEvent('flake_wanted:client:setWanted', targetPlayer, reason, Config.Duration, firstName, lastName, mugshot)

    -- Broadcast wanted notification to all players
    for _, playerId in ipairs(GetPlayers()) do
        if tonumber(playerId) ~= targetPlayer then -- Don't send to the wanted player (they already got it)
            TriggerClientEvent('flake_wanted:client:showWantedBroadcast', tonumber(playerId), firstName, lastName, reason, mugshot)
        end
    end
end)

-- Event for announcing a jail sentence without actually jailing a player
RegisterNetEvent('flake_wanted:server:announceJail', function(targetId, time, reason)
    local source = source

    if not hasRequiredJob(source) then
        TriggerClientEvent('flake_wanted:client:notify', source, "You don't have permission to use this command.", "error")
        return
    end

    local officerName = GetPlayerName(source)
    local targetPlayer = tonumber(targetId)

    if not targetPlayer or not GetPlayerEndpoint(targetPlayer) then
        TriggerClientEvent('flake_wanted:client:notify', source, "Invalid player ID.", "error")
        return
    end

    local targetName = GetPlayerName(targetPlayer)

    -- Request the mugshot from the target player
    TriggerClientEvent('flake_wanted:client:getJailMugshot', targetPlayer, time, reason, officerName)

    -- Get first and last name for the UI
    local firstName, lastName = "Unknown", "Prisoner"
    if QBCore then
        local Player = QBCore.Functions.GetPlayer(targetPlayer)
        if Player then
            firstName = Player.PlayerData.charinfo.firstname
            lastName = Player.PlayerData.charinfo.lastname
        end
    elseif ESX then
        local xPlayer = ESX.GetPlayerFromId(targetPlayer)
        if xPlayer then
            -- ESX might store names differently, adjust as needed
            local fullName = xPlayer.getName() or "Unknown Prisoner"
            local nameParts = {}
            for part in fullName:gmatch("%S+") do
                table.insert(nameParts, part)
            end
            if #nameParts >= 2 then
                firstName = nameParts[1]
                lastName = nameParts[2]
            else
                firstName = fullName
                lastName = ""
            end
        end
    else
        -- If no framework is detected, use the player name
        local fullName = targetName or "Unknown Prisoner"
        local nameParts = {}
        for part in fullName:gmatch("%S+") do
            table.insert(nameParts, part)
        end
        if #nameParts >= 2 then
            firstName = nameParts[1]
            lastName = nameParts[2]
        else
            firstName = fullName
            lastName = ""
        end
    end

    -- Log the announcement
    LogJailAction(officerName, targetName, time, reason)

    -- Save to database
    SaveRecord(officerName, targetName, reason, "Jail Announcement for " .. time .. " months")
end)

-- Event to receive jail mugshot from target player and complete the jail announcement process
RegisterNetEvent('flake_wanted:server:receiveJailMugshot', function(time, reason, officerName, mugshot)
    local source = source
    local targetPlayer = source
    local targetName = GetPlayerName(targetPlayer)

    -- Get first and last name for the UI
    local firstName, lastName = "Unknown", "Prisoner"
    if QBCore then
        local Player = QBCore.Functions.GetPlayer(targetPlayer)
        if Player and Player.PlayerData and Player.PlayerData.charinfo then
            firstName = Player.PlayerData.charinfo.firstname
            lastName = Player.PlayerData.charinfo.lastname
        end
    elseif ESX then
        local xPlayer = ESX.GetPlayerFromId(targetPlayer)
        if xPlayer then
            -- ESX might store names differently, adjust as needed
            firstName = xPlayer.get('firstName') or "Unknown"
            lastName = xPlayer.get('lastName') or "Prisoner"
        end
    else
        -- Fallback to splitting player name
        local fullName = targetName or "Unknown Prisoner"
        local nameParts = {}
        for part in fullName:gmatch("%S+") do
            table.insert(nameParts, part)
        end
        if #nameParts >= 2 then
            firstName = nameParts[1]
            lastName = nameParts[2]
        else
            firstName = fullName
            lastName = ""
        end
    end

    -- Broadcast to all players
    for _, playerId in ipairs(GetPlayers()) do
        TriggerClientEvent('flake_wanted:client:showJailAnnouncement', tonumber(playerId), firstName, lastName, time, reason, mugshot)
    end
end)

-- Command to check wanted players
RegisterCommand('wantedlist', function(source, args, rawCommand)
    if not hasRequiredJob(source) then
        TriggerClientEvent('flake_wanted:client:notify', source, "You don't have permission to use this command.", "error")
        return
    end

    local wantedList = "Current Wanted Players:\n"
    local hasWanted = false

    for playerId, data in pairs(wantedPlayers) do
        if GetPlayerEndpoint(playerId) then
            local playerName = GetPlayerName(playerId)
            local elapsedTime = os.difftime(os.time(), data.time)
            local remainingTime = math.max(0, (Config.Duration * 60) - elapsedTime)
            local minutes = math.floor(remainingTime / 60)
            local seconds = math.floor(remainingTime % 60)

            wantedList = wantedList .. playerName .. " (ID: " .. playerId .. ") - Reason: " .. data.reason .. " - Time Remaining: " .. minutes .. "m " .. seconds .. "s\n"
            hasWanted = true
        end
    end

    if not hasWanted then
        wantedList = "No players are currently wanted."
    end

    TriggerClientEvent('chat:addMessage', source, {
        color = {255, 255, 0},
        multiline = true,
        args = {"WANTED LIST", wantedList}
    })
end, false)

-- Event to get online players for dropdown selection
RegisterNetEvent('flake_wanted:server:getOnlinePlayers', function()
    local source = source
    local players = {}

    for _, playerId in ipairs(GetPlayers()) do
        local id = tonumber(playerId)
        local playerName = GetPlayerName(id)

        -- Get first and last name for better display
        local firstName, lastName = "Unknown", "Player"
        if QBCore then
            local Player = QBCore.Functions.GetPlayer(id)
            if Player and Player.PlayerData and Player.PlayerData.charinfo then
                firstName = Player.PlayerData.charinfo.firstname
                lastName = Player.PlayerData.charinfo.lastname
                playerName = firstName .. " " .. lastName
            end
        elseif ESX then
            local xPlayer = ESX.GetPlayerFromId(id)
            if xPlayer then
                -- ESX might store names differently, adjust as needed
                local fullName = xPlayer.getName() or playerName
                local nameParts = {}
                for part in fullName:gmatch("%S+") do
                    table.insert(nameParts, part)
                end
                if #nameParts >= 2 then
                    firstName = nameParts[1]
                    lastName = nameParts[2]
                    playerName = firstName .. " " .. lastName
                end
            end
        end

        table.insert(players, {
            value = id,
            label = playerName .. " (ID: " .. id .. ")"
        })
    end

    TriggerClientEvent('flake_wanted:client:receiveOnlinePlayers', source, players)
end)
