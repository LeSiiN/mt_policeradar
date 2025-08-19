fx_version 'cerulean'
author 'Marttins | MT Scripts edited by LeSiiN'
description 'Simples Radar script'
lua54 'yes'
game 'gta5'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'config.lua'
}

client_scripts {
    'client.lua',
    '@qbx_core/modules/playerdata.lua',
}

server_script {
    '@qbx_core/modules/lib.lua',
	'server.lua'
}

ui_page 'web/build/index.html'

files {
    'locales/*',
	'web/build/index.html',
	'web/build/**/*',
    'web/assets/**/*',
}