-- Client-side script for the wanted system
local QBCore, ESX = nil, nil
local PlayerData = {}
local isWanted = false
local wantedReason = ""
local wantedBlip = nil
local wantedTimer = 0
local isRaided = false
local raidBlip = nil
local isJailed = false
local jailTime = 0
local onlinePlayers = {}

-- Framework detection and initialization
CreateThread(function()
    if GetResourceState(Config.QBCoreGetCoreObject) ~= 'missing' then
        QBCore = exports[Config.QBCoreGetCoreObject]:GetCoreObject()

        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
            PlayerData = QBCore.Functions.GetPlayerData()
        end)

        RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
            PlayerData.job = JobInfo
        end)

        PlayerData = QBCore.Functions.GetPlayerData()
    elseif GetResourceState(Config.ESXgetSharedObject) ~= 'missing' then
        ESX = exports[Config.ESXgetSharedObject]:getSharedObject()

        RegisterNetEvent('esx:playerLoaded', function(xPlayer)
            PlayerData = xPlayer
        end)

        RegisterNetEvent('esx:setJob', function(job)
            PlayerData.job = job
        end)

        PlayerData = ESX.GetPlayerData()
    end
end)

-- Check if player has the required job
local function hasRequiredJob()
    if not PlayerData or not PlayerData.job then return false end

    return Config.JobLock[PlayerData.job.name] ~= nil
end

-- Function to get online players for dropdown
local function GetOnlinePlayers()
    TriggerServerEvent('flake_wanted:server:getOnlinePlayers')

    -- Wait for the response
    local timeout = 0
    while #onlinePlayers == 0 and timeout < 50 do
        Wait(10)
        timeout = timeout + 1
    end

    return onlinePlayers
end

-- Event to receive online players from server
RegisterNetEvent('flake_wanted:client:receiveOnlinePlayers', function(players)
    onlinePlayers = players
end)

-- Register command to open warrant menu
RegisterCommand(Config.WarrantMenuCommand, function()
    if not hasRequiredJob() then
        Config.Notify("You don't have permission to use this command.", "error")
        return
    end

    -- Get online players first
    GetOnlinePlayers()

    -- Create a context menu with options
    lib.registerContext({
        id = 'warrant_menu',
        title = 'Wanted System',
        options = {
            {
                title = 'Issue Warrant',
                description = 'Issue a warrant for a player',
                icon = 'handcuffs',
                onSelect = function()
                    -- Refresh player list
                    GetOnlinePlayers()

                    local input = lib.inputDialog('Issue Warrant', {
                        {type = 'select', label = 'Select Player', options = onlinePlayers, description = 'Select a player from the list', required = true},
                        {type = 'input', label = 'Reason', description = 'Enter the reason for the warrant', required = true}
                    })

                    if not input then return end

                    local targetId = input[1]
                    local reason = input[2]

                    -- We'll let the server handle getting the mugshot from the target player
                    -- This ensures we're getting the correct player's mugshot
                    TriggerServerEvent('flake_wanted:server:setWanted', targetId, reason)
                end
            },
            {
                title = 'Jail Announcement',
                description = 'Make a public announcement about a jailed person',
                icon = 'bullhorn',
                onSelect = function()
                    -- Refresh player list
                    GetOnlinePlayers()

                    local input = lib.inputDialog('Jail Announcement', {
                        {type = 'select', label = 'Select Player', options = onlinePlayers, description = 'Select a player from the list', required = true},
                        {type = 'number', label = 'Time (months)', description = 'Enter jail time in months', required = true},
                        {type = 'input', label = 'Reason', description = 'Enter the reason for jailing', required = true}
                    })

                    if not input then return end

                    local targetId = input[1]
                    local time = input[2]
                    local reason = input[3]

                    -- We'll let the server handle getting the mugshot from the target player
                    -- This ensures we're getting the correct player's mugshot
                    TriggerServerEvent('flake_wanted:server:announceJail', targetId, time, reason)
                end
            }
        }
    })

    lib.showContext('warrant_menu')
end, false)

-- Register command for raids
RegisterCommand(Config.RaidCommand, function()
    if not hasRequiredJob() then
        Config.Notify("You don't have permission to use this command.", "error")
        return
    end

    OpenRaidMenu()
end, false)

-- Register command to end raids
RegisterCommand(Config.EndRaidCommand, function()
    if not hasRequiredJob() then
        Config.Notify("You don't have permission to use this command.", "error")
        return
    end

    local input = lib.inputDialog('End Raid', {
        {type = 'input', label = 'Location', description = 'Enter the location of the raid to end', required = true}
    })

    if not input then return end

    local location = input[1]

    TriggerServerEvent('flake_wanted:server:endRaid', location)
end, false)

-- We only use the wm command for both warrant and jail announcements

-- We now use a combined police menu instead of separate menus

-- Function to open the raid menu
function OpenRaidMenu()
    local input = lib.inputDialog('Raid System', {
        {type = 'input', label = 'Location', description = 'Enter the location being raided', required = true},
        {type = 'input', label = 'Reason', description = 'Enter the reason for the raid', required = true}
    })

    if not input then return end

    local location = input[1]
    local reason = input[2]

    TriggerServerEvent('flake_wanted:server:setRaid', location, reason)
end

-- We only use the wm command for both warrant and jail announcements

-- Create a blip for the wanted player
function CreateWantedBlip(coords, name)
    if wantedBlip then
        RemoveBlip(wantedBlip)
    end

    wantedBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(wantedBlip, Config.Blip.sprite)
    SetBlipColour(wantedBlip, Config.Blip.color)
    SetBlipScale(wantedBlip, Config.Blip.scale)
    SetBlipAsShortRange(wantedBlip, false)
    BeginTextCommandSetBlipName("STRING")

    -- Use the name if provided, otherwise use generic "Wanted Person"
    local blipName = "Wanted Person"
    if name and name ~= "" then
        blipName = "Wanted Person: " .. name
    end

    AddTextComponentString(blipName)
    EndTextCommandSetBlipName(wantedBlip)
end

-- No longer creating blips for raids

-- Event for setting player as wanted
RegisterNetEvent('flake_wanted:client:setWanted', function(reason, duration, firstName, lastName, mugshot)
    isWanted = true
    wantedReason = reason
    wantedTimer = duration * 60 -- Convert minutes to seconds

    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)

    -- Show notification
    Config.Notify("You are now wanted by the police: " .. reason, "error")

    -- Play sound
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'wanted', 0.5)

    -- Create blip for police
    TriggerServerEvent('flake_wanted:server:updateWantedBlip', coords)

    -- If firstName and lastName weren't provided, get them from the player data
    if not firstName or not lastName then
        firstName, lastName = "Unknown", "Suspect"
        if QBCore then
            local playerData = QBCore.Functions.GetPlayerData()
            firstName = playerData.charinfo.firstname
            lastName = playerData.charinfo.lastname
        elseif ESX then
            local playerData = ESX.GetPlayerData()
            -- ESX might store names differently, adjust as needed
            firstName = playerData.firstName or "Unknown"
            lastName = playerData.lastName or "Suspect"
        end
    end

    -- If no mugshot was provided, try to get one
    if not mugshot or mugshot == "" then
        -- Get mugshot of the local player
        mugshot = exports.MugShotBase64:GetMugShotBase64(PlayerPedId(), false)
    end

    -- Show UI using the existing NUI system
    SendNUIMessage({
        type = "showmug",
        kind = "wanted",
        mug = mugshot,
        data = {
            firstName = firstName,
            lastName = lastName,
            reason = reason
        }
    })

    -- Start timer
    CreateThread(function()
        while isWanted and wantedTimer > 0 do
            Wait(1000)
            wantedTimer = wantedTimer - 1

            if wantedTimer <= 0 then
                isWanted = false
                TriggerServerEvent('flake_wanted:server:removeWanted')

                Config.Notify("You are no longer wanted.", "success")
                break
            end
        end
    end)
end)

-- Event for removing wanted status
RegisterNetEvent('flake_wanted:client:removeWanted', function()
    isWanted = false
    wantedReason = ""
    wantedTimer = 0

    -- Remove blip if it exists (in case the player is also a police officer)
    if wantedBlip then
        RemoveBlip(wantedBlip)
        wantedBlip = nil
    end

    Config.Notify("You are no longer wanted.", "success")
end)

-- Event for removing wanted blip for police officers
RegisterNetEvent('flake_wanted:client:removeWantedBlip', function()
    if wantedBlip then
        RemoveBlip(wantedBlip)
        wantedBlip = nil
    end
end)

-- Event to get mugshot from the target player
RegisterNetEvent('flake_wanted:client:getMugshot', function(reason, officerName)
    -- Get mugshot of the local player (this is the target player)
    local mugshot = exports.MugShotBase64:GetMugShotBase64(PlayerPedId(), false)

    -- Send the mugshot back to the server
    TriggerServerEvent('flake_wanted:server:receiveMugshot', reason, officerName, mugshot)
end)

-- Event for showing wanted broadcast to other players
RegisterNetEvent('flake_wanted:client:showWantedBroadcast', function(firstName, lastName, reason, mugshot)
    -- Play sound
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'wanted', 0.3)

    -- Show UI using the existing NUI system
    SendNUIMessage({
        type = "showmug",
        kind = "wanted",
        mug = mugshot,
        data = {
            firstName = firstName,
            lastName = lastName,
            reason = reason
        }
    })
end)

-- Event for updating wanted blip
RegisterNetEvent('flake_wanted:client:updateWantedBlip', function(coords, firstName, lastName)
    if hasRequiredJob() then
        local name = ""
        if firstName and lastName then
            name = firstName .. " " .. lastName
        end
        CreateWantedBlip(coords, name)
    end
end)

-- Event for showing raid UI to all players
RegisterNetEvent('flake_wanted:client:showRaidUI', function(location, reason)
    -- Play sound
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'raid', 0.5)

    -- Show UI using the existing NUI system
    SendNUIMessage({
        type = "showmug",
        kind = "raid",
        data = {
            reason = "POLICE ARE RAIDING " .. location:upper() .. "\nREASON: " .. reason:upper()
        }
    })
end)

-- Event for showing raid end UI to all players
RegisterNetEvent('flake_wanted:client:showRaidEndUI', function(location)
    -- Play sound
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'raid', 0.5)

    -- Show UI using the existing NUI system
    SendNUIMessage({
        type = "showmug",
        kind = "raid",
        data = {
            reason = "POLICE RAID AT " .. location:upper() .. " HAS ENDED"
        }
    })
end)

-- No longer using raid blips

-- Event for jail notification
RegisterNetEvent('flake_wanted:client:jailNotification', function(time, reason)
    isJailed = true
    jailTime = time

    Config.Notify("You have been jailed for " .. time .. " minutes. Reason: " .. reason, "error")

    -- Play sound
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'jailed', 0.5)

    -- Get player name
    local firstName, lastName = "Unknown", "Prisoner"
    if QBCore then
        local playerData = QBCore.Functions.GetPlayerData()
        firstName = playerData.charinfo.firstname
        lastName = playerData.charinfo.lastname
    elseif ESX then
        local playerData = ESX.GetPlayerData()
        -- ESX might store names differently, adjust as needed
        firstName = playerData.firstName or "Unknown"
        lastName = playerData.lastName or "Prisoner"
    end

    -- Get mugshot of the local player
    local mugshot = exports.MugShotBase64:GetMugShotBase64(PlayerPedId(), false)

    -- Show UI using the existing NUI system
    SendNUIMessage({
        type = "showmug",
        kind = "jailed",
        mug = mugshot,
        data = {
            firstName = firstName,
            lastName = lastName,
            reason = reason,
            amount = time
        }
    })
end)

-- NUI Callback for closing UI
RegisterNUICallback('close', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Event to get jail mugshot from the target player
RegisterNetEvent('flake_wanted:client:getJailMugshot', function(time, reason, officerName)
    -- Get mugshot of the local player (this is the target player)
    local mugshot = exports.MugShotBase64:GetMugShotBase64(PlayerPedId(), false)

    -- Send the mugshot back to the server
    TriggerServerEvent('flake_wanted:server:receiveJailMugshot', time, reason, officerName, mugshot)
end)

-- Event for showing jail announcement to all players
RegisterNetEvent('flake_wanted:client:showJailAnnouncement', function(firstName, lastName, time, reason, mugshot)
    -- Play sound
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'jailed', 0.3)

    -- Show UI using the existing NUI system
    SendNUIMessage({
        type = "showmug",
        kind = "jailed",
        mug = mugshot,
        data = {
            firstName = firstName,
            lastName = lastName,
            reason = reason,
            amount = time
        }
    })
end)

-- Update player position for wanted blip
CreateThread(function()
    while true do
        Wait(5000)

        if isWanted then
            local playerPed = PlayerPedId()
            local coords = GetEntityCoords(playerPed)

            TriggerServerEvent('flake_wanted:server:updateWantedBlip', coords)
        end
    end
end)
