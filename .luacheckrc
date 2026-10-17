-- luacheck configuration (run in CI, see .github/workflows/ci.yml)
std = 'lua54'
max_line_length = false
unused_args = false
ignore = {
    '4', -- shadowing warnings (FiveM code commonly shadows `source`)
}

-- Globals this resource defines and shares across its own files
globals = {
    'Config',
    'ConnectedPlayers', 'LiveStreamers',
    -- server/main.lua
    'Debug', 'GetSecret', 'Notify', 'GetPlayerLicense', 'FindSourceByCitizenId', 'FormatItemList',
    'GetCharacterName', 'DiscordLog', 'DiscordPlayerTag', 'GivePlayerMoney', 'QueuePendingItems',
    'GivePlayerItems', 'DeliverItems', 'CheckIntervalReward', 'DeliverPendingRewards', 'CatchUpRewards',
    -- server/twitch.lua
    'FetchTwitchStreams', 'FetchKickStreams', 'InvalidateTrackingCache', 'RefreshLiveStatus',
}

-- FiveM / library globals
read_globals = {
    'exports', 'MySQL', 'json', 'promise', 'Citizen', 'source',
    'CreateThread', 'Wait', 'PerformHttpRequest', 'GetConvar',
    'RegisterNetEvent', 'AddEventHandler', 'TriggerEvent', 'TriggerClientEvent',
    'GetPlayerIdentifiers', 'GetCurrentResourceName', 'GetResourceMetadata',
    'RegisterCommand', 'RegisterKeyMapping', 'SetNuiFocus', 'SendNUIMessage', 'RegisterNUICallback',
    'IsDisabledControlJustPressed',
}

exclude_files = { 'node_modules/**' }
