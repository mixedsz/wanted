local webhookUrl = ''  -- Add your Discord webhook URL here if you want to use Discord logging

-- Function to send logs to Discord
local function SendToDiscord(name, message, color)
    if webhookUrl == '' then return end

    local embed = {
        {
            ["color"] = color or 16711680,
            ["title"] = "**".. name .."**",
            ["description"] = message,
            ["footer"] = {
                ["text"] = "Flake Wanted System • " .. os.date("%x %X %p"),
            },
        }
    }

    PerformHttpRequest(webhookUrl, function(err, text, headers) end, 'POST', json.encode({embeds = embed}), { ['Content-Type'] = 'application/json' })
end

-- Export the logging function for use in other files
function LogWantedAction(officer, target, reason, action)
    local message = string.format("Officer: %s | Target: %s | Reason: %s | Action: %s", officer, target, reason, action)
    -- Only send to Discord, no console prints
    SendToDiscord("Wanted System", message, 65280)
end

-- Function to log jail actions
function LogJailAction(officer, target, time, reason)
    local message = string.format("Officer: %s | Prisoner: %s | Time: %s minutes | Reason: %s", officer, target, time, reason)
    -- Only send to Discord, no console prints
    SendToDiscord("Jail System", message, 16776960)
end

-- Function to log raid actions
function LogRaidAction(officer, location, reason)
    local message = string.format("Officer: %s | Location: %s | Reason: %s", officer, location, reason)
    -- Only send to Discord, no console prints
    SendToDiscord("Raid System", message, 16711680)
end
