--#Notifications
Config.Notifications = 'ox'  -- 'ox' | 'mythic' | 'custom'

Config.Notify = function(message, type)
    if Config.Notifications == 'ox' then
        lib.notify({
            title = 'Wanted',
            description = message,
            type = type,
            position = 'top',
            duration = 5000
        })
    elseif Config.Notifications == 'mythic' then
        exports["mythic_notify"]:SendAlert(type, message, 5000)
    elseif Config.Notifications == 'custom' then
        --enter your code
    end
end
