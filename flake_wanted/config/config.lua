Config = {}
Config.Debug = false

Config.QBCoreGetCoreObject = 'qb-core'
Config.ESXgetSharedObject = 'es_extended'

Config.WarrantMenuCommand = 'wm'
Config.RaidCommand = 'raid'
Config.EndRaidCommand = 'endraid'

Config.Duration = 3 -- In minutes

Config.JobLock = {
  police = true,
  --fib    = true,
  --sheriff = true,
  --lspd = true,
  -- Add any other jobs as needed
}

Config.Blip = {
  sprite = 458,
  color = 1,
  scale = 1.2,
  playernames = true,
}

Config.UseDatabase = true  -- false = won't save to database | true = will save to database

-- Sound file names from InteractSound/client/html/sounds/
-- Available files: bellring, cell, this_is_the_lspd, freeze_lspd,
--   shoot_to_kill, give_yourself_up, cant_hide_boi, iphonetext, etc.
Config.Sounds = {
    wanted = 'bellring',         -- Played when a warrant is issued
    jailed = 'cell',             -- Played during a jail announcement
    raid   = 'this_is_the_lspd' -- Played when a raid starts
}
