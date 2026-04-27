local QBCore, ESX = nil, nil
local PlayerData = {}
local isWanted = false
local wantedReason = ""
local wantedTimer = 0
local wantedBlips = {}    -- key: targetServerId (int), value: blip handle
local wantedTracking = {} -- key: targetServerId (int), value: true (controls live tracking thread)
local isJailed = false
local onlinePlayers = {}

-- Framework detection
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

local function hasRequiredJob()
    if not PlayerData or not PlayerData.job then return false end
    return Config.JobLock[PlayerData.job.name] ~= nil
end

local function GetOnlinePlayers()
    onlinePlayers = {}
    TriggerServerEvent('flake_wanted:server:getOnlinePlayers')
    local timeout = 0
    while #onlinePlayers == 0 and timeout < 50 do
        Wait(10)
        timeout = timeout + 1
    end
    return onlinePlayers
end

RegisterNetEvent('flake_wanted:client:receiveOnlinePlayers', function(players)
    onlinePlayers = players
end)

-- Server-sent notifications
RegisterNetEvent('flake_wanted:client:notify', function(message, notifType)
    Config.Notify(message, notifType or "inform")
end)

-- ============================================================
-- BLIP MANAGEMENT
-- Creates a blip once, then a local thread updates its coords
-- every 100ms using the player's entity (smooth live tracking).
-- The server also broadcasts coords every 1s as a fallback for
-- when the wanted player is outside streaming range.
-- ============================================================

local function CreateWantedBlipTracking(targetId, coords, name)
    if wantedBlips[targetId] then
        -- Blip exists; just update coords (server fallback path)
        SetBlipCoords(wantedBlips[targetId], coords.x, coords.y, coords.z)
        return
    end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, Config.Blip.sprite)
    SetBlipColour(blip, Config.Blip.color)
    SetBlipScale(blip, Config.Blip.scale)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Wanted: " .. (name ~= "" and name or "Unknown Suspect"))
    EndTextCommandSetBlipName(blip)
    wantedBlips[targetId] = blip
    wantedTracking[targetId] = true

    -- Local high-frequency tracking using entity position when in range
    CreateThread(function()
        while wantedTracking[targetId] do
            Wait(100)
            local localPlayer = GetPlayerFromServerId(targetId)
            if localPlayer ~= -1 then
                local ped = GetPlayerPed(localPlayer)
                if ped ~= 0 and DoesEntityExist(ped) then
                    local c = GetEntityCoords(ped)
                    if wantedBlips[targetId] then
                        SetBlipCoords(wantedBlips[targetId], c.x, c.y, c.z)
                    end
                end
            end
        end
    end)
end

local function RemoveWantedBlipTracking(targetId)
    wantedTracking[targetId] = nil
    if wantedBlips[targetId] then
        RemoveBlip(wantedBlips[targetId])
        wantedBlips[targetId] = nil
    end
end

-- ============================================================
-- COMMANDS
-- ============================================================

RegisterCommand(Config.WarrantMenuCommand, function()
    if not hasRequiredJob() then
        Config.Notify("You don't have permission to use this command.", "error")
        return
    end

    GetOnlinePlayers()

    lib.registerContext({
        id = 'warrant_menu',
        title = 'Wanted System',
        options = {
            {
                title = 'Issue Warrant',
                description = 'Mark a player as wanted',
                icon = 'handcuffs',
                onSelect = function()
                    GetOnlinePlayers()
                    local input = lib.inputDialog('Issue Warrant', {
                        {type = 'select', label = 'Select Player', options = onlinePlayers, required = true},
                        {type = 'input',  label = 'Reason',        required = true}
                    })
                    if not input then return end
                    TriggerServerEvent('flake_wanted:server:setWanted', input[1], input[2])
                end
            },
            {
                title = 'Remove Warrant',
                description = 'Remove a wanted status from a player',
                icon = 'ban',
                onSelect = function()
                    GetOnlinePlayers()
                    local input = lib.inputDialog('Remove Warrant', {
                        {type = 'select', label = 'Select Player', options = onlinePlayers, required = true}
                    })
                    if not input then return end
                    TriggerServerEvent('flake_wanted:server:removeWanted', input[1])
                end
            },
            {
                title = 'Jail Player',
                description = 'Jail a player and broadcast the sentence',
                icon = 'building-columns',
                onSelect = function()
                    GetOnlinePlayers()
                    local input = lib.inputDialog('Jail Player', {
                        {type = 'select', label = 'Select Player',        options = onlinePlayers, required = true},
                        {type = 'number', label = 'Jail Time (minutes)',  required = true},
                        {type = 'input',  label = 'Reason',               required = true}
                    })
                    if not input then return end
                    TriggerServerEvent('flake_wanted:server:jailPlayer', input[1], input[2], input[3])
                end
            }
        }
    })

    lib.showContext('warrant_menu')
end, false)

RegisterCommand(Config.RaidCommand, function()
    if not hasRequiredJob() then
        Config.Notify("You don't have permission to use this command.", "error")
        return
    end

    local input = lib.inputDialog('Start Raid', {
        {type = 'input', label = 'Location', required = true},
        {type = 'input', label = 'Reason',   required = true}
    })

    if not input then return end
    TriggerServerEvent('flake_wanted:server:setRaid', input[1], input[2])
end, false)

RegisterCommand(Config.EndRaidCommand, function()
    if not hasRequiredJob() then
        Config.Notify("You don't have permission to use this command.", "error")
        return
    end

    local input = lib.inputDialog('End Raid', {
        {type = 'input', label = 'Location', required = true}
    })

    if not input then return end
    TriggerServerEvent('flake_wanted:server:endRaid', input[1])
end, false)

-- ============================================================
-- WANTED EVENTS
-- ============================================================

RegisterNetEvent('flake_wanted:client:setWanted', function(reason, duration, firstName, lastName, mugshot)
    isWanted = true
    wantedReason = reason
    wantedTimer = duration * 60

    Config.Notify("You are now wanted by the police for: " .. reason, "error")
    TriggerServerEvent('InteractSound_SV:PlayOnSource', Config.Sounds.wanted, 0.7)

    SendNUIMessage({
        type = "showmug",
        kind = "wanted",
        mug  = mugshot or "",
        data = { firstName = firstName, lastName = lastName, reason = reason }
    })

    -- Countdown; when it hits zero the client self-removes
    CreateThread(function()
        while isWanted and wantedTimer > 0 do
            Wait(1000)
            wantedTimer = wantedTimer - 1
            if wantedTimer <= 0 then
                isWanted = false
                TriggerServerEvent('flake_wanted:server:removeWanted')
            end
        end
    end)
end)

RegisterNetEvent('flake_wanted:client:removeWanted', function()
    isWanted = false
    wantedReason = ""
    wantedTimer = 0
    Config.Notify("You are no longer wanted.", "success")
end)

-- Server tells police to remove a specific player's blip
RegisterNetEvent('flake_wanted:client:removeWantedBlip', function(targetId)
    if hasRequiredJob() then
        RemoveWantedBlipTracking(targetId)
    end
end)

-- Target player captures their own mugshot and sends it back
RegisterNetEvent('flake_wanted:client:getMugshot', function(reason, officerName)
    local mugshot = exports.MugShotBase64:GetMugShotBase64(PlayerPedId(), false)
    TriggerServerEvent('flake_wanted:server:receiveMugshot', reason, officerName, mugshot)
end)

-- Police clients see the wanted broadcast UI
RegisterNetEvent('flake_wanted:client:showWantedBroadcast', function(firstName, lastName, reason, mugshot)
    TriggerServerEvent('InteractSound_SV:PlayOnSource', Config.Sounds.wanted, 0.5)
    SendNUIMessage({
        type = "showmug",
        kind = "wanted",
        mug  = mugshot or "",
        data = { firstName = firstName, lastName = lastName, reason = reason }
    })
end)

-- Server sends position every 1s; used as fallback when entity is out of range
RegisterNetEvent('flake_wanted:client:updateWantedBlip', function(targetId, coords, firstName, lastName)
    if not hasRequiredJob() then return end
    CreateWantedBlipTracking(targetId, coords, firstName .. " " .. lastName)
end)

-- ============================================================
-- RAID EVENTS
-- ============================================================

RegisterNetEvent('flake_wanted:client:showRaidUI', function(location, reason)
    TriggerServerEvent('InteractSound_SV:PlayOnSource', Config.Sounds.raid, 0.5)
    SendNUIMessage({
        type = "showmug",
        kind = "raid",
        data = { reason = "POLICE ARE RAIDING " .. location:upper() .. "\nREASON: " .. reason:upper() }
    })
end)

RegisterNetEvent('flake_wanted:client:showRaidEndUI', function(location)
    SendNUIMessage({
        type = "showmug",
        kind = "raid",
        data = { reason = "POLICE RAID AT " .. location:upper() .. " HAS ENDED" }
    })
end)

-- ============================================================
-- JAIL EVENTS
-- ============================================================

RegisterNetEvent('flake_wanted:client:getJailMugshot', function(time, reason, officerName)
    local mugshot = exports.MugShotBase64:GetMugShotBase64(PlayerPedId(), false)
    TriggerServerEvent('flake_wanted:server:receiveJailMugshot', time, reason, officerName, mugshot)
end)

RegisterNetEvent('flake_wanted:client:showJailAnnouncement', function(firstName, lastName, time, reason, mugshot)
    TriggerServerEvent('InteractSound_SV:PlayOnSource', Config.Sounds.jailed, 0.5)
    SendNUIMessage({
        type = "showmug",
        kind = "jailed",
        mug  = mugshot or "",
        data = { firstName = firstName, lastName = lastName, reason = reason, amount = time }
    })
end)

RegisterNUICallback('close', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)
