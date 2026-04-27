fx_version 'bodacious'
game 'gta5'

author 'Flake'
description 'Wanted Script'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
	'config/*.lua',
}

client_scripts {
	'client/*.lua',
}

server_scripts {
	'@oxmysql/lib/MySQL.lua',
	'logs.lua',
	'server/*.lua',
}

files({
	'web/index.html',
	'web/*.png',
})

ui_page("web/index.html")

dependencies {
	'MugShotBase64',
	'InteractSound'
}

server_exports {
    'AnnounceJail'
}

escrow_ignore {
    'config/*.lua',
	'logs.lua',
}

dependency '/assetpacks'