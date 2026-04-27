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
