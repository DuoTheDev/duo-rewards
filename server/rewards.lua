local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================================
-- ADMIN COMMANDS (QBCore permission: admin)
-- ============================================================================

local function AdminTag(source)
    if source == 0 then return 'Console' end
    local adminData = ConnectedPlayers[source]
    return DiscordPlayerTag(adminData and adminData.citizenid or nil, source)
end

--- Resolves a command argument to a loaded player. Accepts a server ID or a citizenid.
local function ResolveTarget(arg)
    local targetSource = tonumber(arg)
    if targetSource then
        local data = ConnectedPlayers[targetSource]
        if data then return targetSource, data.citizenid end
        return nil
    end
    if arg and arg ~= '' then
        local src = FindSourceByCitizenId(arg)
        if src then return src, arg end
        -- Offline player: allow citizenid-based actions where supported
        local exists = MySQL.scalar.await('SELECT COUNT(*) FROM loyalty_profiles WHERE citizenid = ?', { arg })
        if exists and exists > 0 then return nil, arg end
    end
    return nil
end

local function FormatHours(minutes)
    minutes = tonumber(minutes) or 0
    return ('%d hrs %d min'):format(math.floor(minutes / 60), minutes % 60)
end

--- /loyaltyreset — Reset "this period" stream minutes for everyone
QBCore.Commands.Add('loyaltyreset', 'Reset the current-period stream minutes for all players.', {}, false, function(source)
    MySQL.update.await('UPDATE loyalty_profiles SET current_period_minutes = 0')
    Notify(source, 'Period stream minutes have been reset for all players.', 'primary')

    DiscordLog('adminAction', 'Admin: Period Minutes Reset', {
        { name = 'Admin', value = AdminTag(source), inline = true },
        { name = 'Action', value = 'Reset all current_period_minutes to 0', inline = false },
    }, 'warning')
end, 'admin')

--- /loyaltystats [id] — View a player's loyalty profile
QBCore.Commands.Add('loyaltystats', "View a player's loyalty profile.", {
    { name = 'id', help = 'Server ID of the player (leave empty for yourself)' },
}, false, function(source, args)
    local targetSource = tonumber(args[1]) or source
    local targetData = ConnectedPlayers[targetSource]
    if not targetData then
        Notify(source, 'Player not found or not loaded.', 'error')
        return
    end

    local profile = MySQL.single.await('SELECT * FROM loyalty_profiles WHERE citizenid = ?', { targetData.citizenid })
    if not profile then
        Notify(source, 'No loyalty profile found for this player.', 'error')
        return
    end

    local lines = {
        ('^5[Loyalty Stats] ^0%s'):format(DiscordPlayerTag(targetData.citizenid, targetSource)),
        ('^3Twitch: ^0%s'):format(profile.twitch_username or 'Not linked'),
        ('^3Kick: ^0%s'):format(profile.kick_username or 'Not linked'),
        ('^3Referral Code: ^0%s'):format(profile.referral_code or '?'),
        ('^3Referred By: ^0%s'):format(profile.referred_by or 'Nobody'),
        ('^3Stream Time (Period): ^0%s'):format(FormatHours(profile.current_period_minutes)),
        ('^3Stream Time (Total): ^0%s'):format(FormatHours(profile.total_stream_minutes)),
        ('^3Playtime: ^0%s'):format(FormatHours(profile.playtime_minutes)),
        ('^3Total Referrals: ^0%d'):format(profile.total_referrals or 0),
        ('^3Referral Playtime Earned: ^0%s'):format(FormatHours(profile.referral_playtime_earned)),
        ('^3Care Package: ^0%s'):format((profile.care_package_claimed == 1 or profile.care_package_claimed == true) and 'Claimed' or 'Not claimed'),
    }

    for _, line in ipairs(lines) do
        if source == 0 then
            print(line)
        else
            TriggerClientEvent('chat:addMessage', source, { args = { line } })
        end
    end

    DiscordLog('adminAction', 'Admin: Viewed Player Stats', {
        { name = 'Admin', value = AdminTag(source), inline = true },
        { name = 'Target', value = DiscordPlayerTag(targetData.citizenid, targetSource), inline = true },
    }, 'info')
end, 'admin')

--- /loyaltycatchup [id] — Grant any missed milestone rewards to a player
QBCore.Commands.Add('loyaltycatchup', 'Grant missed milestone rewards to a player.', {
    { name = 'id', help = 'Server ID of the player' },
}, true, function(source, args)
    local targetSource = tonumber(args[1])
    local targetData = targetSource and ConnectedPlayers[targetSource]
    if not targetData then
        Notify(source, 'Player not found or not loaded.', 'error')
        return
    end

    local granted = CatchUpRewards(targetSource, targetData.citizenid)
    Notify(source, ('Catch-up processed for ID %d: %d missed reward(s) granted.'):format(targetSource, granted), 'success')

    DiscordLog('adminAction', 'Admin: Reward Catch-Up', {
        { name = 'Admin', value = AdminTag(source), inline = true },
        { name = 'Target', value = DiscordPlayerTag(targetData.citizenid, targetSource), inline = true },
        { name = 'Granted', value = tostring(granted), inline = true },
    }, 'warning')
end, 'admin')

--- /loyaltyunlink [id|citizenid] [twitch|kick] — Unlink a streaming account from a player
QBCore.Commands.Add('loyaltyunlink', "Unlink a player's Twitch or Kick account.", {
    { name = 'id', help = 'Server ID or citizenid of the player' },
    { name = 'platform', help = 'twitch or kick' },
}, true, function(source, args)
    local platform = string.lower(args[2] or '')
    if platform ~= 'twitch' and platform ~= 'kick' then
        Notify(source, 'Usage: /loyaltyunlink [id|citizenid] [twitch|kick]', 'error')
        return
    end

    local targetSource, citizenid = ResolveTarget(args[1])
    if not citizenid then
        Notify(source, 'Player not found.', 'error')
        return
    end

    local column = platform == 'twitch' and 'twitch_username' or 'kick_username'
    local previous = MySQL.scalar.await(('SELECT %s FROM loyalty_profiles WHERE citizenid = ?'):format(column), { citizenid })
    if not previous then
        Notify(source, ('That player has no %s account linked.'):format(platform), 'error')
        return
    end

    MySQL.update.await(('UPDATE loyalty_profiles SET %s = NULL WHERE citizenid = ?'):format(column), { citizenid })
    LiveStreamers[citizenid] = nil
    InvalidateTrackingCache(citizenid)

    Notify(source, ('Unlinked %s account "%s" from %s.'):format(platform, previous, citizenid), 'success')
    if targetSource then
        Notify(targetSource, ('An admin unlinked your %s account.'):format(platform), 'warning')
    end

    DiscordLog('adminAction', 'Admin: Account Unlinked', {
        { name = 'Admin', value = AdminTag(source), inline = true },
        { name = 'Target', value = DiscordPlayerTag(citizenid, targetSource), inline = true },
        { name = 'Platform', value = platform .. ' (' .. previous .. ')', inline = true },
    }, 'warning')
end, 'admin')
