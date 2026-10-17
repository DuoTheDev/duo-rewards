local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================================
-- SHARED STATE (globals used across the server files)
-- ============================================================================

-- Connected players with a loaded character: ConnectedPlayers[source] = { citizenid, license }
ConnectedPlayers = {}

-- Players currently live with the keyword in their title (maintained by server/twitch.lua):
-- LiveStreamers[citizenid] = { viewer_count, username, platform }
LiveStreamers = {}

-- ============================================================================
-- HELPERS
-- ============================================================================

function Debug(fmt, ...)
    if not Config.Debug then return end
    print(('[duo-rewards] ' .. fmt):format(...))
end

--- Reads a secret from config.lua, falling back to a server convar (see the top of config.lua).
function GetSecret(configValue, convarName)
    if configValue and configValue ~= '' then return configValue end
    local value = GetConvar(convarName, '')
    if value ~= '' then return value end
    return nil
end

--- Notify a player using the configured notification system (Config.Notify).
---@param source number
---@param message string
---@param nType string|nil 'primary' | 'success' | 'error' | 'warning'
function Notify(source, message, nType)
    if not source then return end
    if source == 0 then print('[duo-rewards] ' .. message) return end
    nType = nType or 'primary'
    if Config.Notify == 'ox' then
        local map = { primary = 'inform', success = 'success', error = 'error', warning = 'warning' }
        TriggerClientEvent('ox_lib:notify', source, { description = message, type = map[nType] or 'inform' })
    else
        TriggerClientEvent('QBCore:Notify', source, message, nType)
    end
end

function GetPlayerLicense(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.sub(id, 1, 8) == 'license:' then
            return id
        end
    end
    return nil
end

function FindSourceByCitizenId(citizenid)
    for src, data in pairs(ConnectedPlayers) do
        if data.citizenid == citizenid then return src end
    end
    return nil
end

--- "2x Bandage, 1x Water" (optionally multiplied)
function FormatItemList(items, multiplier)
    local parts = {}
    for _, item in ipairs(items or {}) do
        parts[#parts + 1] = ((item.count or 0) * (multiplier or 1)) .. 'x ' .. (item.label or item.name)
    end
    return table.concat(parts, ', ')
end

--- Character name of an online player, or from the database for offline players.
function GetCharacterName(citizenid, source)
    local Player = (source and QBCore.Functions.GetPlayer(source)) or (citizenid and QBCore.Functions.GetPlayerByCitizenId(citizenid))
    local info = Player and Player.PlayerData and Player.PlayerData.charinfo
    if not info and citizenid then
        local raw = MySQL.scalar.await('SELECT charinfo FROM players WHERE citizenid = ?', { citizenid })
        if raw then
            local ok, decoded = pcall(json.decode, raw)
            if ok then info = decoded end
        end
    end
    if type(info) ~= 'table' then return nil end
    local name = ((info.firstname or '') .. ' ' .. (info.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return nil end
    return name
end

-- ============================================================================
-- DISCORD WEBHOOK LOGGING
-- ============================================================================

local colorMap = {
    info    = 5793266,
    success = 2067276,
    warning = 16763904,
    error   = 14495300,
    purple  = 9146614,
    gold    = 16499720,
}

function DiscordLog(logType, title, fields, color)
    local webhook = GetSecret(Config.DiscordWebhook, 'duo_rewards_discord_webhook')
    if not webhook then return end
    if Config.DiscordLogs and Config.DiscordLogs[logType] == false then return end

    local payload = {
        username = Config.DiscordBotName or 'duo-rewards',
        embeds   = { {
            title     = title,
            color     = colorMap[color or 'info'] or colorMap.info,
            fields    = fields,
            footer    = { text = 'duo-rewards' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    }
    if Config.DiscordBotAvatar and Config.DiscordBotAvatar ~= '' then
        payload.avatar_url = Config.DiscordBotAvatar
    end

    PerformHttpRequest(webhook, function(status)
        if status ~= 200 and status ~= 204 then
            Debug('Discord webhook returned HTTP %s', tostring(status))
        end
    end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

function DiscordPlayerTag(citizenid, source)
    local tag = citizenid or 'unknown'
    local name = citizenid and GetCharacterName(citizenid, source)
    if name then tag = name .. ' (' .. tag .. ')' end
    if source then tag = tag .. (' [ID: %d]'):format(source) end
    return tag
end

-- ============================================================================
-- REFERRAL CODE GENERATION
-- ============================================================================

local function GenerateReferralCode()
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' -- no 0/O or 1/I to avoid confusion
    local code = ''
    for _ = 1, 8 do
        local idx = math.random(1, #chars)
        code = code .. string.sub(chars, idx, idx)
    end
    return code
end

local function GenerateUniqueReferralCode()
    for _ = 1, 20 do
        local code = GenerateReferralCode()
        local existing = MySQL.scalar.await('SELECT COUNT(*) FROM loyalty_profiles WHERE referral_code = ?', { code })
        if existing == 0 then
            return code
        end
    end
    return GenerateReferralCode() .. string.sub(tostring(os.time()), -2)
end

-- ============================================================================
-- MONEY & ITEMS
-- ============================================================================

--- Adds money to a player, online or offline.
---@param citizenid string
---@param amount number
---@param source number|nil
---@param moneyType string|nil defaults to Config.RewardMoneyType
---@param reason string|nil
function GivePlayerMoney(citizenid, amount, source, moneyType, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    moneyType = moneyType or Config.RewardMoneyType or 'bank'
    reason = reason or 'duo-rewards'

    local Player = (source and QBCore.Functions.GetPlayer(source)) or QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if Player then
        Player.Functions.AddMoney(moneyType, amount, reason)
        return
    end

    -- Offline: update the stored money JSON directly
    local path = '$.' .. moneyType
    MySQL.update(
        'UPDATE players SET money = JSON_SET(money, ?, COALESCE(JSON_EXTRACT(money, ?), 0) + ?) WHERE citizenid = ?',
        { path, path, amount, citizenid }
    )
end

--- Queues items for delivery the next time the player loads in.
function QueuePendingItems(citizenid, items, reason)
    if not items or #items == 0 then return end
    MySQL.insert(
        'INSERT INTO loyalty_pending_rewards (citizenid, items, reason) VALUES (?, ?, ?)',
        { citizenid, json.encode(items), reason or 'reward' }
    )
end

--- Gives items to an online player.
---@return table failed items that could NOT be added (empty when everything was given)
function GivePlayerItems(source, items)
    local failed = {}
    if not items or #items == 0 then return failed end
    for _, item in ipairs(items) do
        local count = tonumber(item.count) or 0
        if item.name and count > 0 then
            local ok = exports.ox_inventory:AddItem(source, item.name, count)
            if not ok then
                failed[#failed + 1] = { name = item.name, label = item.label, count = count }
            end
        end
    end
    return failed
end

--- Gives items to a player if online, queueing anything that does not fit. Queues everything if offline.
function DeliverItems(citizenid, source, items, reason)
    if not items or #items == 0 then return end
    if not source then
        QueuePendingItems(citizenid, items, reason)
        return
    end
    local failed = GivePlayerItems(source, items)
    if #failed > 0 then
        QueuePendingItems(citizenid, failed, reason)
        Notify(source, 'Some rewards did not fit in your inventory. They will be delivered next time you log in.', 'warning')
    end
end

-- ============================================================================
-- INTERVAL REWARDS
-- ============================================================================

--- Pays out rewards when `newVal` crosses one or more multiples of rewardConfig.interval.
---@param citizenid string
---@param oldVal number  previous value (minutes, count, ...)
---@param newVal number  new value after the increment
---@param rewardConfig table  { interval, money, items }
---@param source number|nil  player source if online
---@param label string  'Streaming' | 'Playtime' | 'Referrals' | 'Referral playtime' (also used by CatchUpRewards)
function CheckIntervalReward(citizenid, oldVal, newVal, rewardConfig, source, label)
    if not rewardConfig or not rewardConfig.interval or rewardConfig.interval <= 0 then return end

    local oldCount = math.floor(oldVal / rewardConfig.interval)
    local newCount = math.floor(newVal / rewardConfig.interval)
    if newCount <= oldCount then return end

    local times = newCount - oldCount
    local money = tonumber(rewardConfig.money) or 0
    local totalMoney = money * times
    local items = rewardConfig.items or {}

    if totalMoney > 0 then
        GivePlayerMoney(citizenid, totalMoney, source)
    end
    for _ = 1, times do
        DeliverItems(citizenid, source, items, label .. ' milestone reward')
    end

    local perItemStr = FormatItemList(items)

    if source then
        local parts = { label .. ' milestone!' }
        if totalMoney > 0 then parts[#parts + 1] = '+$' .. totalMoney end
        if perItemStr ~= '' then parts[#parts + 1] = '+' .. perItemStr end
        Notify(source, table.concat(parts, ' '), 'success')
    end

    -- One history row per milestone. CatchUpRewards counts these rows, so keep the "<label> reward" prefix.
    local valueParts = { label .. ' reward' }
    if money > 0 then valueParts[#valueParts + 1] = '$' .. money end
    if perItemStr ~= '' then valueParts[#valueParts + 1] = perItemStr end
    local value = table.concat(valueParts, ' — ')
    for _ = 1, times do
        MySQL.insert(
            'INSERT INTO loyalty_events (citizenid, event_type, value) VALUES (?, ?, ?)',
            { citizenid, 'referral_reward', value }
        )
    end

    DiscordLog('rewardMilestone', 'Reward Milestone Reached', {
        { name = 'Player', value = DiscordPlayerTag(citizenid, source), inline = true },
        { name = 'Type', value = label, inline = true },
        { name = 'Times', value = times .. 'x', inline = true },
        { name = 'Money', value = '$' .. totalMoney, inline = true },
        { name = 'Items', value = #items > 0 and FormatItemList(items, times) or 'None', inline = true },
        { name = 'Online', value = source and 'Yes' or 'No (queued)', inline = true },
    }, 'gold')
end

-- ============================================================================
-- PENDING (OFFLINE) REWARD DELIVERY
-- ============================================================================

function DeliverPendingRewards(source, citizenid)
    local pending = MySQL.query.await(
        'SELECT id, items FROM loyalty_pending_rewards WHERE citizenid = ? ORDER BY id ASC',
        { citizenid }
    )
    if not pending or #pending == 0 then return end

    local delivered, kept = 0, 0
    for _, row in ipairs(pending) do
        local ok, items = pcall(json.decode, row.items)
        if ok and type(items) == 'table' then
            local failed = GivePlayerItems(source, items)
            if #failed == 0 then
                MySQL.update('DELETE FROM loyalty_pending_rewards WHERE id = ?', { row.id })
                delivered = delivered + 1
            else
                -- Keep only what is still owed
                MySQL.update('UPDATE loyalty_pending_rewards SET items = ? WHERE id = ?', { json.encode(failed), row.id })
                kept = kept + 1
            end
        else
            -- Corrupt row; drop it so it does not block forever
            MySQL.update('DELETE FROM loyalty_pending_rewards WHERE id = ?', { row.id })
        end
    end

    if delivered > 0 then
        Notify(source, ('You received %d reward(s) earned while you were offline!'):format(delivered), 'success')
        DiscordLog('pendingDelivery', 'Pending Rewards Delivered', {
            { name = 'Player', value = DiscordPlayerTag(citizenid, source), inline = true },
            { name = 'Rewards', value = tostring(delivered), inline = true },
            { name = 'Still queued', value = tostring(kept), inline = true },
        }, 'success')
    end
    if kept > 0 then
        Notify(source, 'Some pending rewards did not fit in your inventory. Make room and relog to receive them.', 'warning')
    end
end

-- ============================================================================
-- RETROACTIVE REWARD CATCH-UP (admin command)
-- ============================================================================

function CatchUpRewards(source, citizenid)
    local profile = MySQL.single.await(
        'SELECT total_stream_minutes, playtime_minutes, total_referrals, referral_playtime_earned FROM loyalty_profiles WHERE citizenid = ?',
        { citizenid }
    )
    if not profile then return 0 end

    -- Count rewards already paid, per label
    local existingRewards = MySQL.query.await(
        "SELECT value, COUNT(*) AS cnt FROM loyalty_events WHERE citizenid = ? AND event_type = 'referral_reward' GROUP BY value",
        { citizenid }
    )
    local rewardCounts = {}
    for _, row in ipairs(existingRewards or {}) do
        if row.value then
            local label = row.value:match('^(.-)%s*—') or row.value
            label = label:gsub('%s+$', '')
            rewardCounts[label] = (rewardCounts[label] or 0) + (row.cnt or 0)
        end
    end

    local checks = {
        { val = profile.total_stream_minutes or 0,     config = Config.StreamReward,           label = 'Streaming' },
        { val = profile.playtime_minutes or 0,         config = Config.PlaytimeReward,         label = 'Playtime' },
        { val = profile.total_referrals or 0,          config = Config.ReferralReward,         label = 'Referrals' },
        { val = profile.referral_playtime_earned or 0, config = Config.ReferralPlaytimeReward, label = 'Referral playtime' },
    }

    local totalCatchUp = 0
    for _, check in ipairs(checks) do
        local cfg = check.config
        if cfg and cfg.interval and cfg.interval > 0 then
            local expected = math.floor(check.val / cfg.interval)
            local actual = rewardCounts[check.label .. ' reward'] or 0
            local owed = expected - actual
            if owed > 0 then
                -- Reuse the normal payout path so history rows and notifications stay consistent
                CheckIntervalReward(citizenid, 0, owed * cfg.interval, cfg, source, check.label)
                totalCatchUp = totalCatchUp + owed
            end
        end
    end

    if totalCatchUp > 0 then
        Notify(source, ('You received %d missed reward(s)!'):format(totalCatchUp), 'success')
    end
    return totalCatchUp
end

-- ============================================================================
-- PLAYER CONNECT / DISCONNECT
-- ============================================================================

local function InitializePlayer(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    -- Character swap: forget the previous character's live state
    local previous = ConnectedPlayers[source]
    if previous then LiveStreamers[previous.citizenid] = nil end

    local citizenid = Player.PlayerData.citizenid
    local license = GetPlayerLicense(source)
    if not license then
        print(('[duo-rewards] WARNING: no license identifier for source %d, player will not be tracked'):format(source))
        return
    end

    local profile = MySQL.single.await(
        'SELECT id, twitch_username, kick_username FROM loyalty_profiles WHERE citizenid = ?',
        { citizenid }
    )
    if not profile then
        local code = GenerateUniqueReferralCode()
        MySQL.insert.await(
            'INSERT INTO loyalty_profiles (citizenid, license, referral_code) VALUES (?, ?, ?)',
            { citizenid, license, code }
        )
        Debug('Created loyalty profile for %s (code: %s)', citizenid, code)
    else
        MySQL.update.await('UPDATE loyalty_profiles SET license = ? WHERE id = ?', { license, profile.id })
    end

    -- The player may have logged out / swapped character while we were waiting on the database
    local current = QBCore.Functions.GetPlayer(source)
    if not current or current.PlayerData.citizenid ~= citizenid then return end

    ConnectedPlayers[source] = { citizenid = citizenid, license = license }

    DiscordLog('playerJoin', 'Player Loaded', {
        { name = 'Player', value = DiscordPlayerTag(citizenid, source), inline = true },
        { name = 'New Profile', value = profile and 'No' or 'Yes', inline = true },
    }, 'info')

    DeliverPendingRewards(source, citizenid)

    -- Pick up a stream that is already live now instead of waiting for the next poll
    if profile and (profile.twitch_username or profile.kick_username) then
        CreateThread(function()
            RefreshLiveStatus(citizenid, profile.twitch_username, profile.kick_username)
        end)
    end
end

local function ForgetPlayer(source)
    local data = ConnectedPlayers[source]
    if data then LiveStreamers[data.citizenid] = nil end
    ConnectedPlayers[source] = nil
end

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    InitializePlayer(source)
end)

RegisterNetEvent('QBCore:Server:OnPlayerUnload', function()
    ForgetPlayer(source)
end)

AddEventHandler('playerDropped', function()
    ForgetPlayer(source)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    Wait(2000)
    for _, Player in pairs(QBCore.Functions.GetQBPlayers()) do
        InitializePlayer(Player.PlayerData.source)
    end
end)

-- ============================================================================
-- PLAYTIME TRACKING
-- ============================================================================

CreateThread(function()
    local tickSeconds = math.max(60, tonumber(Config.PlaytimeTickSeconds) or 60)
    local minutesPerTick = math.floor(tickSeconds / 60)
    local referralCfg = Config.ReferralPlaytimeReward
    local trackReferrers = referralCfg and referralCfg.interval and referralCfg.interval > 0

    while true do
        Wait(tickSeconds * 1000)

        -- Snapshot: ConnectedPlayers changes while we yield on database calls
        local snapshot = {}
        for src, data in pairs(ConnectedPlayers) do
            snapshot[#snapshot + 1] = { src = src, citizenid = data.citizenid }
        end

        for _, p in ipairs(snapshot) do
            local still = ConnectedPlayers[p.src]
            if still and still.citizenid == p.citizenid then
                local row = MySQL.single.await(
                    'SELECT playtime_minutes, referred_by FROM loyalty_profiles WHERE citizenid = ?',
                    { p.citizenid }
                )
                if row then
                    local oldPlaytime = row.playtime_minutes or 0
                    MySQL.update(
                        'UPDATE loyalty_profiles SET playtime_minutes = playtime_minutes + ? WHERE citizenid = ?',
                        { minutesPerTick, p.citizenid }
                    )
                    CheckIntervalReward(p.citizenid, oldPlaytime, oldPlaytime + minutesPerTick, Config.PlaytimeReward, p.src, 'Playtime')

                    -- Credit the referrer for this player's playtime
                    if trackReferrers and row.referred_by and row.referred_by ~= '' then
                        local referrer = MySQL.single.await(
                            'SELECT citizenid, referral_playtime_earned FROM loyalty_profiles WHERE referral_code = ?',
                            { row.referred_by }
                        )
                        if referrer then
                            local oldEarned = referrer.referral_playtime_earned or 0
                            MySQL.update(
                                'UPDATE loyalty_profiles SET referral_playtime_earned = referral_playtime_earned + ? WHERE citizenid = ?',
                                { minutesPerTick, referrer.citizenid }
                            )
                            CheckIntervalReward(referrer.citizenid, oldEarned, oldEarned + minutesPerTick, referralCfg,
                                FindSourceByCitizenId(referrer.citizenid), 'Referral playtime')
                        end
                    end
                end
            end
        end
    end
end)

-- ============================================================================
-- CALLBACKS: PROFILE / ACTIVITY / LEADERBOARD
-- ============================================================================

local PROFILE_COLUMNS = 'citizenid, twitch_username, kick_username, referral_code, referred_by, total_stream_minutes, '
    .. 'current_period_minutes, total_referrals, playtime_minutes, referral_playtime_earned, avatar_url, created_at'

QBCore.Functions.CreateCallback('loyalty:server:getProfile', function(source, cb)
    local playerData = ConnectedPlayers[source]
    if not playerData then cb(nil) return end

    local profile = MySQL.single.await(
        'SELECT ' .. PROFILE_COLUMNS .. ' FROM loyalty_profiles WHERE citizenid = ?',
        { playerData.citizenid }
    )
    if not profile then cb(nil) return end

    profile.leaderboard_rank = MySQL.scalar.await(
        'SELECT COUNT(*) + 1 FROM loyalty_profiles WHERE current_period_minutes > (SELECT current_period_minutes FROM loyalty_profiles WHERE citizenid = ?)',
        { playerData.citizenid }
    ) or 0
    profile.char_name = GetCharacterName(playerData.citizenid, source)

    cb(profile)
end)

QBCore.Functions.CreateCallback('loyalty:server:getActivity', function(source, cb)
    local playerData = ConnectedPlayers[source]
    if not playerData then cb({}) return end

    -- Stream ticks per day for the last 84 days (12 weeks)
    local rows = MySQL.query.await(
        "SELECT DATE_FORMAT(created_at, '%Y-%m-%d') AS day, COUNT(*) AS ticks FROM loyalty_events "
        .. "WHERE citizenid = ? AND event_type = 'stream_tick' AND created_at >= DATE_SUB(CURDATE(), INTERVAL 84 DAY) "
        .. 'GROUP BY day ORDER BY day ASC',
        { playerData.citizenid }
    )

    local result = {}
    for _, row in ipairs(rows or {}) do
        result[row.day] = row.ticks or 0
    end
    cb(result)
end)

local function ParseCharNames(rows)
    for _, row in ipairs(rows or {}) do
        if row.charinfo then
            local ok, info = pcall(json.decode, row.charinfo)
            if ok and type(info) == 'table' then
                row.char_name = ((info.firstname or '') .. ' ' .. (info.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
            end
        end
        row.charinfo = nil
    end
    return rows or {}
end

--- Copies rows and tags the ones that are currently live (cached rows must not be mutated).
local function WithLiveFlags(rows)
    local showLive = Config.ShowLiveOnLeaderboard ~= false
    local out = {}
    for i, row in ipairs(rows) do
        local copy = {}
        for k, v in pairs(row) do copy[k] = v end
        local live = showLive and LiveStreamers[row.citizenid] or nil
        if live then
            copy.is_live = true
            copy.viewer_count = live.viewer_count
            copy.live_platform = live.platform or 'twitch'
        end
        out[i] = copy
    end
    return out
end

local leaderboardCache = { at = 0, data = nil }

local function LoadLeaderboards()
    local lbMax = Config.LeaderboardMax or 15
    local cols = 'lp.citizenid, lp.twitch_username, lp.kick_username, lp.total_stream_minutes, lp.playtime_minutes, '
        .. 'lp.total_referrals, lp.avatar_url, p.charinfo'
    local from = ' FROM loyalty_profiles lp LEFT JOIN players p '
        .. 'ON p.citizenid COLLATE utf8mb4_general_ci = lp.citizenid COLLATE utf8mb4_general_ci '

    -- Stream board: top streamers plus anyone live right now (so new streamers show up immediately)
    local liveCids = {}
    if Config.ShowLiveOnLeaderboard ~= false then
        for cid in pairs(LiveStreamers) do liveCids[#liveCids + 1] = cid end
    end

    local where = 'WHERE (lp.total_stream_minutes > 0'
    local params = {}
    if #liveCids > 0 then
        where = where .. ' OR lp.citizenid IN (' .. string.rep('?', #liveCids, ',') .. ')'
        for _, cid in ipairs(liveCids) do params[#params + 1] = cid end
    end
    where = where .. ') ORDER BY lp.total_stream_minutes DESC LIMIT ?'
    params[#params + 1] = lbMax

    return {
        stream    = ParseCharNames(MySQL.query.await('SELECT ' .. cols .. from .. where, params)),
        playtime  = ParseCharNames(MySQL.query.await('SELECT ' .. cols .. from .. 'WHERE lp.playtime_minutes > 0 ORDER BY lp.playtime_minutes DESC LIMIT ?', { lbMax })),
        referrals = ParseCharNames(MySQL.query.await('SELECT ' .. cols .. from .. 'WHERE lp.total_referrals > 0 ORDER BY lp.total_referrals DESC LIMIT ?', { lbMax })),
    }
end

QBCore.Functions.CreateCallback('loyalty:server:getLeaderboard', function(source, cb)
    local playerData = ConnectedPlayers[source]
    local myCid = playerData and playerData.citizenid or nil

    -- Lists are shared by every open panel, so cache them for one refresh interval
    local ttl = math.max(5, Config.LiveRefreshSeconds or 10)
    if not leaderboardCache.data or os.time() - leaderboardCache.at >= ttl then
        leaderboardCache.data = LoadLeaderboards()
        leaderboardCache.at = os.time()
    end
    local lists = leaderboardCache.data

    local myRanks = {}
    if myCid then
        myRanks.stream = MySQL.scalar.await(
            'SELECT COUNT(*) + 1 FROM loyalty_profiles WHERE total_stream_minutes > (SELECT COALESCE(total_stream_minutes, 0) FROM loyalty_profiles WHERE citizenid = ?)',
            { myCid }
        ) or 0
        myRanks.playtime = MySQL.scalar.await(
            'SELECT COUNT(*) + 1 FROM loyalty_profiles WHERE playtime_minutes > (SELECT COALESCE(playtime_minutes, 0) FROM loyalty_profiles WHERE citizenid = ?)',
            { myCid }
        ) or 0
        myRanks.referrals = MySQL.scalar.await(
            'SELECT COUNT(*) + 1 FROM loyalty_profiles WHERE total_referrals > (SELECT COALESCE(total_referrals, 0) FROM loyalty_profiles WHERE citizenid = ?)',
            { myCid }
        ) or 0
    end

    cb({
        stream    = WithLiveFlags(lists.stream),
        playtime  = WithLiveFlags(lists.playtime),
        referrals = WithLiveFlags(lists.referrals),
        myRanks   = myRanks,
    })
end)

-- ============================================================================
-- CALLBACKS: REFERRAL STATS
-- ============================================================================

QBCore.Functions.CreateCallback('loyalty:server:getReferralStats', function(source, cb)
    local playerData = ConnectedPlayers[source]
    if not playerData then cb(nil) return end

    local profile = MySQL.single.await(
        'SELECT referral_code, total_referrals, referred_by, referral_redeemed_at, care_package_claimed, referral_code_edited, referral_playtime_earned, '
        .. 'GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), DATE_ADD(referral_redeemed_at, INTERVAL ? MINUTE))) AS claim_seconds_left '
        .. 'FROM loyalty_profiles WHERE citizenid = ?',
        { Config.ReferralClaimDelayMins or 0, playerData.citizenid }
    )
    if not profile then cb(nil) return end

    local referrals = MySQL.query.await(
        'SELECT redeemed_by_citizenid, created_at FROM referral_uses WHERE referrer_citizenid = ? ORDER BY created_at DESC',
        { playerData.citizenid }
    )

    local totalReferrals = profile.total_referrals or 0
    local money = totalReferrals * (Config.ReferrerRewardPerUse or 0)
    local itemsEarned = {}

    local function addMilestones(cfg, value)
        if not cfg or not cfg.interval or cfg.interval <= 0 then return end
        local milestones = math.floor((value or 0) / cfg.interval)
        if milestones <= 0 then return end
        money = money + milestones * (cfg.money or 0)
        for _, item in ipairs(cfg.items or {}) do
            local key = item.label or item.name
            itemsEarned[key] = (itemsEarned[key] or 0) + (item.count or 0) * milestones
        end
    end
    addMilestones(Config.ReferralReward, totalReferrals)
    addMilestones(Config.ReferralPlaytimeReward, profile.referral_playtime_earned)

    local itemsList = {}
    for label, count in pairs(itemsEarned) do
        itemsList[#itemsList + 1] = { label = label, count = count }
    end

    local claimed = profile.care_package_claimed == 1 or profile.care_package_claimed == true
    local claimSecondsLeft = 0
    if profile.referred_by and profile.referred_by ~= '' and not claimed then
        claimSecondsLeft = tonumber(profile.claim_seconds_left) or 0
    end

    cb({
        referral_code        = profile.referral_code,
        total_referrals      = totalReferrals,
        referred_by          = profile.referred_by,
        referrals_list       = referrals or {},
        money_earned         = money,
        items_earned         = itemsList,
        care_package_claimed = claimed,
        claim_seconds_left   = claimSecondsLeft,
        code_edited          = profile.referral_code_edited == 1 or profile.referral_code_edited == true,
    })
end)

-- ============================================================================
-- CALLBACKS: TWITCH / KICK ACCOUNT LINKING
-- ============================================================================

--- Normalises "@Name", "https://twitch.tv/Name/" etc. to "name"
local function NormaliseUsername(input)
    local name = string.lower(tostring(input or ''))
    name = name:gsub('%s', ''):gsub('^https?://[^/]+/', ''):gsub('^@', ''):gsub('/.*$', '')
    return name
end

local function LinkPlatform(source, cb, platform, column, rawName, pattern, minLen, maxLen)
    local playerData = ConnectedPlayers[source]
    if not playerData then cb({ success = false, message = 'Player data not found.' }) return end

    local username = NormaliseUsername(rawName)
    if username == '' then
        cb({ success = false, message = ('Please enter a valid %s username.'):format(platform) })
        return
    end
    if not username:match(pattern) or #username < minLen or #username > maxLen then
        cb({ success = false, message = ('Invalid %s username format.'):format(platform) })
        return
    end

    -- One channel per account: block if another license already linked this name
    local existing = MySQL.scalar.await(
        ('SELECT COUNT(*) FROM loyalty_profiles WHERE %s = ? AND license != ?'):format(column),
        { username, playerData.license }
    )
    if existing and existing > 0 then
        cb({ success = false, message = ('This %s username is already linked to another player.'):format(platform) })
        return
    end

    MySQL.update.await(
        ('UPDATE loyalty_profiles SET %s = ? WHERE citizenid = ?'):format(column),
        { username, playerData.citizenid }
    )
    cb({ success = true, message = ('%s account linked successfully!'):format(platform) })

    InvalidateTrackingCache(playerData.citizenid)
    CreateThread(function()
        if platform == 'Twitch' then
            RefreshLiveStatus(playerData.citizenid, username, nil)
        else
            RefreshLiveStatus(playerData.citizenid, nil, username)
        end
    end)

    DiscordLog('twitchLink', platform .. ' Account Linked', {
        { name = 'Player', value = DiscordPlayerTag(playerData.citizenid, source), inline = true },
        { name = platform, value = username, inline = true },
    }, platform == 'Twitch' and 'purple' or 'success')
end

local function UnlinkPlatform(source, cb, platform, column)
    local playerData = ConnectedPlayers[source]
    if not playerData then cb({ success = false, message = 'Player data not found.' }) return end

    MySQL.update.await(
        ('UPDATE loyalty_profiles SET %s = NULL WHERE citizenid = ?'):format(column),
        { playerData.citizenid }
    )
    LiveStreamers[playerData.citizenid] = nil
    InvalidateTrackingCache(playerData.citizenid)
    cb({ success = true, message = platform .. ' account unlinked.' })

    DiscordLog('twitchLink', platform .. ' Account Unlinked', {
        { name = 'Player', value = DiscordPlayerTag(playerData.citizenid, source), inline = true },
    }, 'warning')
end

QBCore.Functions.CreateCallback('loyalty:server:linkTwitch', function(source, cb, username)
    LinkPlatform(source, cb, 'Twitch', 'twitch_username', username, '^[a-z0-9_]+$', 3, 25)
end)

QBCore.Functions.CreateCallback('loyalty:server:unlinkTwitch', function(source, cb)
    UnlinkPlatform(source, cb, 'Twitch', 'twitch_username')
end)

QBCore.Functions.CreateCallback('loyalty:server:linkKick', function(source, cb, username)
    LinkPlatform(source, cb, 'Kick', 'kick_username', username, '^[a-z0-9_%-]+$', 3, 25)
end)

QBCore.Functions.CreateCallback('loyalty:server:unlinkKick', function(source, cb)
    UnlinkPlatform(source, cb, 'Kick', 'kick_username')
end)

-- ============================================================================
-- CALLBACKS: REWARD HISTORY / AVATAR / MISC
-- ============================================================================

QBCore.Functions.CreateCallback('loyalty:server:getRewardHistory', function(source, cb)
    local playerData = ConnectedPlayers[source]
    if not playerData then cb({}) return end

    local events = MySQL.query.await(
        "SELECT event_type, value, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS created_at FROM loyalty_events "
        .. "WHERE citizenid = ? AND event_type IN ('leaderboard_reward', 'care_package', 'referral_reward', 'level_up') "
        .. 'ORDER BY created_at DESC, id DESC LIMIT 50',
        { playerData.citizenid }
    )
    cb(events or {})
end)

-- Strict allow-list: https, then only characters that are valid in a URL. Quotes, angle
-- brackets and whitespace are rejected so the value can never break out of an attribute.
local AVATAR_URL_PATTERN = '^https://[%w%-%.]+[%w%-%._~:/%?#%[%]@!%$&%(%)%*%+,;=%%]*$'

QBCore.Functions.CreateCallback('loyalty:server:setAvatar', function(source, cb, avatarUrl)
    local playerData = ConnectedPlayers[source]
    if not playerData then cb({ success = false, message = 'Player data not found.' }) return end

    avatarUrl = tostring(avatarUrl or ''):gsub('%s', '')
    if avatarUrl ~= '' then
        if #avatarUrl > 500 then
            cb({ success = false, message = 'URL is too long (max 500 characters).' })
            return
        end
        if not avatarUrl:match('^https://') then
            cb({ success = false, message = 'URL must start with https://' })
            return
        end
        if not avatarUrl:match(AVATAR_URL_PATTERN) then
            cb({ success = false, message = 'Invalid URL.' })
            return
        end
    else
        avatarUrl = nil
    end

    MySQL.update.await('UPDATE loyalty_profiles SET avatar_url = ? WHERE citizenid = ?', { avatarUrl, playerData.citizenid })
    leaderboardCache.at = 0 -- show the new avatar on the next leaderboard refresh
    cb({ success = true, message = avatarUrl and 'Avatar updated!' or 'Avatar removed.' })

    DiscordLog('avatarChanged', avatarUrl and 'Avatar Updated' or 'Avatar Removed', {
        { name = 'Player', value = DiscordPlayerTag(playerData.citizenid, source), inline = true },
        { name = 'URL', value = avatarUrl or 'Removed', inline = false },
    }, 'info')
end)

QBCore.Functions.CreateCallback('loyalty:server:logWatchStream', function(source, cb, data)
    local playerData = ConnectedPlayers[source]
    data = type(data) == 'table' and data or {}
    DiscordLog('watchStream', 'Player Clicked Watch Stream', {
        { name = 'Player', value = DiscordPlayerTag(playerData and playerData.citizenid or nil, source), inline = true },
        { name = 'Watching', value = tostring(data.username or '?'), inline = true },
        { name = 'URL', value = tostring(data.url or '?'), inline = false },
    }, 'purple')
    cb('ok')
end)

QBCore.Functions.CreateCallback('loyalty:server:editReferralCode', function(source, cb, newCode)
    local playerData = ConnectedPlayers[source]
    if not playerData then cb({ success = false, message = 'Player data not found.' }) return end

    local profile = MySQL.single.await(
        'SELECT referral_code, referral_code_edited FROM loyalty_profiles WHERE citizenid = ?',
        { playerData.citizenid }
    )
    if not profile then cb({ success = false, message = 'Profile not found.' }) return end

    if profile.referral_code_edited == 1 or profile.referral_code_edited == true then
        cb({ success = false, message = 'You have already customised your referral code.' })
        return
    end

    newCode = string.upper(tostring(newCode or '')):gsub('%s', '')
    if newCode == '' then cb({ success = false, message = 'Please enter a code.' }) return end

    local minLen = math.max(1, Config.ReferralCodeMinLength or 3)
    local maxLen = math.min(20, Config.ReferralCodeMaxLength or 12)

    if not newCode:match('^[A-Z0-9]+$') then
        cb({ success = false, message = 'Code can only contain letters and numbers.' })
        return
    end
    if #newCode < minLen or #newCode > maxLen then
        cb({ success = false, message = ('Code must be %d-%d characters.'):format(minLen, maxLen) })
        return
    end

    local taken = MySQL.scalar.await(
        'SELECT COUNT(*) FROM loyalty_profiles WHERE referral_code = ? AND citizenid != ?',
        { newCode, playerData.citizenid }
    )
    if taken and taken > 0 then
        cb({ success = false, message = 'This code is already taken.' })
        return
    end

    local oldCode = profile.referral_code
    MySQL.update.await(
        'UPDATE loyalty_profiles SET referral_code = ?, referral_code_edited = 1 WHERE citizenid = ?',
        { newCode, playerData.citizenid }
    )
    -- Keep references from players who were referred with the old code
    if oldCode then
        MySQL.update('UPDATE loyalty_profiles SET referred_by = ? WHERE referred_by = ?', { newCode, oldCode })
        MySQL.update('UPDATE referral_uses SET code_used = ? WHERE code_used = ?', { newCode, oldCode })
    end

    cb({ success = true, message = 'Referral code changed to ' .. newCode .. '!' })

    DiscordLog('referralCodeEdited', 'Referral Code Changed', {
        { name = 'Player', value = DiscordPlayerTag(playerData.citizenid, source), inline = true },
        { name = 'Old Code', value = oldCode or '?', inline = true },
        { name = 'New Code', value = newCode, inline = true },
    }, 'info')
end)

-- ============================================================================
-- EXPORTS (for other resources)
-- ============================================================================

--- exports['duo-rewards']:GetProfile(citizenid) -> table|nil
exports('GetProfile', function(citizenid)
    if not citizenid then return nil end
    return MySQL.single.await(
        'SELECT ' .. PROFILE_COLUMNS .. ', care_package_claimed FROM loyalty_profiles WHERE citizenid = ?',
        { citizenid }
    )
end)

--- exports['duo-rewards']:IsPlayerLive(citizenid) -> boolean, { viewer_count, username, platform }|nil
exports('IsPlayerLive', function(citizenid)
    local live = LiveStreamers[citizenid]
    return live ~= nil, live
end)

--- exports['duo-rewards']:GetLiveStreamers() -> { [citizenid] = { viewer_count, username, platform } }
exports('GetLiveStreamers', function()
    return LiveStreamers
end)
