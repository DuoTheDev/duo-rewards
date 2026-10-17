local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================================
-- STREAM TRACKING: Twitch (Helix) + Kick (official API, unofficial fallback)
-- ============================================================================

local TWITCH_TOKEN_URL    = 'https://id.twitch.tv/oauth2/token'
local TWITCH_STREAMS_URL  = 'https://api.twitch.tv/helix/streams'
local KICK_TOKEN_URL      = 'https://id.kick.com/oauth/token'
local KICK_CHANNELS_URL   = 'https://api.kick.com/public/v1/channels'
local KICK_UNOFFICIAL_URL = 'https://kick.com/api/v2/channels/'

local TOKEN_RETRY_SECONDS = 60 -- do not hammer a token endpoint after a failure

-- ============================================================================
-- HTTP HELPERS
-- ============================================================================

local function UrlEncode(str)
    return (tostring(str):gsub('[^%w%-_%.~]', function(c)
        return ('%%%02X'):format(string.byte(c))
    end))
end

--- Synchronous HTTP request. Must be called from a coroutine (threads, callbacks, event handlers).
local function HttpAwait(url, method, body, headers)
    local p = promise.new()
    PerformHttpRequest(url, function(status, text)
        p:resolve({ status = tonumber(status) or 0, body = text or '' })
    end, method or 'GET', body or '', headers or {})
    return Citizen.Await(p)
end

local function DecodeJson(text)
    local ok, data = pcall(json.decode, text)
    if ok and type(data) == 'table' then return data end
    return nil
end

local function HasKeyword(title)
    local keyword = string.lower(Config.StreamKeyword or '')
    if keyword == '' then return false end
    return string.find(string.lower(title or ''), keyword, 1, true) ~= nil
end

-- ============================================================================
-- TWITCH
-- ============================================================================

local twitchAuth = { token = nil, expiresAt = 0, lastFailure = 0 }

local function TwitchCredentials()
    local cfg = Config.Twitch or {}
    return GetSecret(cfg.clientId, 'duo_rewards_twitch_client_id'),
           GetSecret(cfg.clientSecret, 'duo_rewards_twitch_client_secret'),
           GetSecret(cfg.accessToken, 'duo_rewards_twitch_access_token')
end

--- Returns a valid Twitch app access token, generating / refreshing it when needed.
local function GetTwitchToken(forceRefresh)
    local clientId, clientSecret, manualToken = TwitchCredentials()
    if not clientId then return nil end

    -- No secret: the admin supplied a token by hand and we cannot refresh it
    if not clientSecret then
        if forceRefresh then
            if os.time() - twitchAuth.lastFailure > TOKEN_RETRY_SECONDS then
                twitchAuth.lastFailure = os.time()
                print('[duo-rewards] Twitch rejected the manual access token. Generate a new one, or set Config.Twitch.clientSecret so tokens refresh automatically.')
            end
            return nil
        end
        return manualToken
    end

    if not forceRefresh and twitchAuth.token and os.time() < twitchAuth.expiresAt then
        return twitchAuth.token
    end
    if os.time() - twitchAuth.lastFailure < TOKEN_RETRY_SECONDS then return nil end

    local body = ('client_id=%s&client_secret=%s&grant_type=client_credentials'):format(UrlEncode(clientId), UrlEncode(clientSecret))
    local res = HttpAwait(TWITCH_TOKEN_URL, 'POST', body, { ['Content-Type'] = 'application/x-www-form-urlencoded' })
    local data = res.status == 200 and DecodeJson(res.body) or nil

    if data and data.access_token then
        twitchAuth.token = data.access_token
        twitchAuth.expiresAt = os.time() + math.max(300, (tonumber(data.expires_in) or 3600) - 300) -- refresh 5 min early
        Debug('Twitch app access token acquired (expires in %s seconds)', tostring(data.expires_in))
        return twitchAuth.token
    end

    twitchAuth.lastFailure = os.time()
    print(('[duo-rewards] Could not obtain a Twitch app access token (HTTP %d). Check Config.Twitch.clientId / clientSecret.'):format(res.status))
    return nil
end

--- Returns { [login] = { title, viewer_count, game_name } } for the channels in `logins` that are live,
--- or nil when the Twitch API could not be reached.
function FetchTwitchStreams(logins)
    local result = {}
    if not (Config.Twitch and Config.Twitch.enabled) or #logins == 0 then return result end

    local clientId = TwitchCredentials()
    local token = GetTwitchToken(false)
    if not clientId or not token then return nil end

    local params = { 'first=100' }
    for _, login in ipairs(logins) do
        params[#params + 1] = 'user_login=' .. UrlEncode(login)
    end
    local url = TWITCH_STREAMS_URL .. '?' .. table.concat(params, '&')

    local function request(tok)
        return HttpAwait(url, 'GET', '', { ['Client-ID'] = clientId, ['Authorization'] = 'Bearer ' .. tok })
    end

    local res = request(token)
    if res.status == 401 then
        token = GetTwitchToken(true)
        if not token then return nil end
        res = request(token)
    end

    if res.status ~= 200 then
        print(('[duo-rewards] Twitch API error: HTTP %d'):format(res.status))
        return nil
    end

    local data = DecodeJson(res.body)
    if not data or type(data.data) ~= 'table' then
        print('[duo-rewards] Twitch API error: unexpected response body')
        return nil
    end

    for _, stream in ipairs(data.data) do
        if stream.type == 'live' and stream.user_login then
            result[string.lower(stream.user_login)] = {
                title        = stream.title or '',
                viewer_count = tonumber(stream.viewer_count) or 0,
                game_name    = stream.game_name or '',
            }
        end
    end
    return result
end

-- ============================================================================
-- KICK
-- ============================================================================

local kickAuth = { token = nil, expiresAt = 0, lastFailure = 0 }

local function KickCredentials()
    local cfg = Config.Kick or {}
    return GetSecret(cfg.clientId, 'duo_rewards_kick_client_id'),
           GetSecret(cfg.clientSecret, 'duo_rewards_kick_client_secret')
end

local function GetKickToken(forceRefresh)
    local clientId, clientSecret = KickCredentials()
    if not clientId or not clientSecret then return nil end

    if not forceRefresh and kickAuth.token and os.time() < kickAuth.expiresAt then
        return kickAuth.token
    end
    if os.time() - kickAuth.lastFailure < TOKEN_RETRY_SECONDS then return nil end

    local body = ('grant_type=client_credentials&client_id=%s&client_secret=%s'):format(UrlEncode(clientId), UrlEncode(clientSecret))
    local res = HttpAwait(KICK_TOKEN_URL, 'POST', body, { ['Content-Type'] = 'application/x-www-form-urlencoded' })
    local data = res.status == 200 and DecodeJson(res.body) or nil

    if data and data.access_token then
        kickAuth.token = data.access_token
        kickAuth.expiresAt = os.time() + math.max(300, (tonumber(data.expires_in) or 3600) - 300)
        Debug('Kick app access token acquired (expires in %s seconds)', tostring(data.expires_in))
        return kickAuth.token
    end

    kickAuth.lastFailure = os.time()
    print(('[duo-rewards] Could not obtain a Kick app access token (HTTP %d). Check Config.Kick.clientId / clientSecret.'):format(res.status))
    return nil
end

--- Official API: up to 50 slugs per request.
local function FetchKickOfficial(slugs)
    local result = {}
    local token = GetKickToken(false)
    if not token then return nil end

    local function request(batch, tok)
        local params = {}
        for _, slug in ipairs(batch) do params[#params + 1] = 'slug=' .. UrlEncode(slug) end
        return HttpAwait(KICK_CHANNELS_URL .. '?' .. table.concat(params, '&'), 'GET', '', {
            ['Authorization'] = 'Bearer ' .. tok,
            ['Accept']        = 'application/json',
        })
    end

    local function consume(res)
        local data = DecodeJson(res.body)
        if not data or type(data.data) ~= 'table' then return false end
        for _, channel in ipairs(data.data) do
            local stream = channel.stream
            if channel.slug and type(stream) == 'table' and stream.is_live then
                result[string.lower(channel.slug)] = {
                    title        = channel.stream_title or '',
                    viewer_count = tonumber(stream.viewer_count) or 0,
                }
            end
        end
        return true
    end

    for i = 1, #slugs, 50 do
        local batch = { table.unpack(slugs, i, math.min(i + 49, #slugs)) }
        local res = request(batch, token)
        if res.status == 401 then
            token = GetKickToken(true)
            if not token then return nil end
            res = request(batch, token)
        end

        if res.status == 200 then
            if not consume(res) then
                print('[duo-rewards] Kick API error: unexpected response body')
                return nil
            end
        elseif res.status == 400 and #batch > 1 then
            -- Multi-slug query rejected: fall back to one request per channel
            for _, slug in ipairs(batch) do
                local single = request({ slug }, token)
                if single.status == 200 then consume(single) end
                Wait(250)
            end
        else
            print(('[duo-rewards] Kick API error: HTTP %d'):format(res.status))
            return nil
        end
    end
    return result
end

--- Unofficial website endpoint (no credentials). One request per channel; often blocked by Cloudflare.
local function FetchKickUnofficial(slugs)
    local result = {}
    for i, slug in ipairs(slugs) do
        local res = HttpAwait(KICK_UNOFFICIAL_URL .. UrlEncode(slug), 'GET', '', { ['Accept'] = 'application/json' })
        if res.status == 200 then
            local data = DecodeJson(res.body)
            local ls = data and data.livestream
            if type(ls) == 'table' and ls.is_live then
                result[string.lower(slug)] = {
                    title        = ls.session_title or '',
                    viewer_count = tonumber(ls.viewer_count) or 0,
                }
            end
        elseif res.status ~= 404 then
            Debug('Kick unofficial endpoint returned HTTP %d for %s', res.status, slug)
        end
        if i < #slugs then Wait(500) end
    end
    return result
end

--- Returns { [slug] = { title, viewer_count } } for the channels in `slugs` that are live,
--- or nil when the Kick API could not be reached.
function FetchKickStreams(slugs)
    if not (Config.Kick and Config.Kick.enabled) or #slugs == 0 then return {} end
    local clientId, clientSecret = KickCredentials()
    if clientId and clientSecret then
        return FetchKickOfficial(slugs)
    end
    if Config.Kick.useUnofficialFallback then
        return FetchKickUnofficial(slugs)
    end
    return {}
end

-- ============================================================================
-- LIVE STATUS (shared by the panel banner, link/join checks and the poll loop)
-- ============================================================================

--- Checks one player's channels right now.
---@return table { tracking = true, platform, viewer_count, username } or { tracking = false, reason }
local function GetLiveStatus(twitchName, kickName)
    local sawLive, sawError = false, false

    if twitchName then
        local login = string.lower(twitchName)
        local live = FetchTwitchStreams({ login })
        if live == nil then
            sawError = true
        elseif live[login] then
            if HasKeyword(live[login].title) then
                return { tracking = true, platform = 'twitch', viewer_count = live[login].viewer_count, username = login }
            end
            sawLive = true
        end
    end

    if kickName then
        local slug = string.lower(kickName)
        local live = FetchKickStreams({ slug })
        if live == nil then
            sawError = true
        elseif live[slug] then
            if HasKeyword(live[slug].title) then
                return { tracking = true, platform = 'kick', viewer_count = live[slug].viewer_count, username = slug }
            end
            sawLive = true
        end
    end

    if sawLive then return { tracking = false, reason = 'missing_keyword' } end
    if sawError then return { tracking = false, reason = 'api_error' } end
    return { tracking = false, reason = 'not_live' }
end

-- Per-player cache so an open panel does not hit the APIs every refresh
local trackingCache = {} -- [citizenid] = { result, expires }

function InvalidateTrackingCache(citizenid)
    trackingCache[citizenid] = nil
end

local function CacheStatus(citizenid, status)
    local ttl = math.max(10, Config.TrackingStatusCacheSeconds or 60)
    trackingCache[citizenid] = { result = status, expires = os.time() + ttl }
end

--- Called when a player loads in or links an account: marks them live immediately if they already are.
function RefreshLiveStatus(citizenid, twitchName, kickName)
    if not twitchName and not kickName then return end
    local status = GetLiveStatus(twitchName, kickName)
    if status.tracking and FindSourceByCitizenId(citizenid) then
        LiveStreamers[citizenid] = { viewer_count = status.viewer_count, username = status.username, platform = status.platform }
    end
    CacheStatus(citizenid, status)
end

QBCore.Functions.CreateCallback('loyalty:server:getTrackingStatus', function(source, cb)
    local playerData = ConnectedPlayers[source]
    if not playerData then cb({ tracking = false }) return end

    local profile = MySQL.single.await(
        'SELECT twitch_username, kick_username FROM loyalty_profiles WHERE citizenid = ?',
        { playerData.citizenid }
    )
    local twitchName = profile and Config.Twitch and Config.Twitch.enabled and profile.twitch_username or nil
    local kickName = profile and Config.Kick and Config.Kick.enabled and profile.kick_username or nil
    if not twitchName and not kickName then
        cb({ tracking = false, reason = 'no_platform_linked' })
        return
    end

    local cached = trackingCache[playerData.citizenid]
    if cached and os.time() < cached.expires then
        cb(cached.result)
        return
    end

    local status = GetLiveStatus(twitchName, kickName)
    CacheStatus(playerData.citizenid, status)
    cb(status)
end)

-- ============================================================================
-- POLLING
-- ============================================================================

local function PollStreams()
    if (Config.StreamKeyword or '') == '' then return end
    local minutes = math.max(1, math.floor(tonumber(Config.PollIntervalMinutes) or 5))

    -- Only players who are actually in the server can earn stream time
    local connected = {}
    for _, data in pairs(ConnectedPlayers) do connected[data.citizenid] = true end
    if next(connected) == nil then LiveStreamers = {} return end

    local rows = MySQL.query.await(
        'SELECT citizenid, twitch_username, kick_username FROM loyalty_profiles WHERE twitch_username IS NOT NULL OR kick_username IS NOT NULL'
    ) or {}

    local twitchLogins, twitchOwner = {}, {}
    local kickSlugs, kickOwner = {}, {}
    for _, row in ipairs(rows) do
        if connected[row.citizenid] then
            if row.twitch_username then
                local login = string.lower(row.twitch_username)
                twitchLogins[#twitchLogins + 1] = login
                twitchOwner[login] = row.citizenid
            end
            if row.kick_username then
                local slug = string.lower(row.kick_username)
                kickSlugs[#kickSlugs + 1] = slug
                kickOwner[slug] = row.citizenid
            end
        end
    end
    if #twitchLogins == 0 and #kickSlugs == 0 then LiveStreamers = {} return end

    local newLive, handled = {}, {}

    local function Credit(citizenid, platform, username, stream)
        if handled[citizenid] then return end          -- already credited on the other platform this poll
        if not HasKeyword(stream.title) then return end
        handled[citizenid] = true
        newLive[citizenid] = { viewer_count = stream.viewer_count, username = username, platform = platform }

        -- Never credit twice within one interval (e.g. after a quick resource restart)
        local sinceLast = MySQL.scalar.await(
            "SELECT TIMESTAMPDIFF(SECOND, MAX(created_at), NOW()) FROM loyalty_events WHERE citizenid = ? AND event_type = 'stream_tick'",
            { citizenid }
        )
        if sinceLast and sinceLast < (minutes * 60 - 30) then return end

        local oldTotal = MySQL.scalar.await('SELECT total_stream_minutes FROM loyalty_profiles WHERE citizenid = ?', { citizenid }) or 0
        MySQL.update.await(
            'UPDATE loyalty_profiles SET total_stream_minutes = total_stream_minutes + ?, current_period_minutes = current_period_minutes + ? WHERE citizenid = ?',
            { minutes, minutes, citizenid }
        )
        MySQL.insert(
            'INSERT INTO loyalty_events (citizenid, event_type, value) VALUES (?, ?, ?)',
            { citizenid, 'stream_tick', ('%d minutes [%s] (title: %s)'):format(minutes, platform, string.sub(stream.title or '', 1, 100)) }
        )

        local platformLabel = platform == 'kick' and 'Kick' or 'Twitch'
        local src = FindSourceByCitizenId(citizenid)
        if src and Config.NotifyOnStreamTick then
            Notify(src, ('Stream tracked on %s! +%d minutes'):format(platformLabel, minutes), 'success')
        end

        CheckIntervalReward(citizenid, oldTotal, oldTotal + minutes, Config.StreamReward, src, 'Streaming')

        DiscordLog('streamTracked', 'Stream Time Credited', {
            { name = 'Player', value = DiscordPlayerTag(citizenid, src), inline = true },
            { name = 'Platform', value = platformLabel .. ' (' .. username .. ')', inline = true },
            { name = 'Minutes', value = '+' .. minutes, inline = true },
            { name = 'Total', value = (oldTotal + minutes) .. ' min', inline = true },
            { name = 'Viewers', value = tostring(stream.viewer_count or 0), inline = true },
        }, 'purple')
    end

    -- Twitch: up to 100 logins per request
    for i = 1, #twitchLogins, 100 do
        local batch = { table.unpack(twitchLogins, i, math.min(i + 99, #twitchLogins)) }
        local live = FetchTwitchStreams(batch)
        if live then
            for login, stream in pairs(live) do
                if twitchOwner[login] then Credit(twitchOwner[login], 'twitch', login, stream) end
            end
        end
        if i + 100 <= #twitchLogins then Wait(500) end
    end

    -- Kick
    if #kickSlugs > 0 then
        local live = FetchKickStreams(kickSlugs)
        if live then
            for slug, stream in pairs(live) do
                if kickOwner[slug] then Credit(kickOwner[slug], 'kick', slug, stream) end
            end
        end
    end

    LiveStreamers = newLive
end

CreateThread(function()
    Wait(5000)

    -- Surface credential problems at startup instead of on the first poll
    local twitchId, twitchSecret, twitchManual = TwitchCredentials()
    if Config.Twitch and Config.Twitch.enabled then
        if not twitchId or (not twitchSecret and not twitchManual) then
            print('[duo-rewards] Twitch tracking is enabled but Config.Twitch.clientId + clientSecret are not set. Twitch streams will not be tracked.')
        elseif twitchSecret then
            GetTwitchToken(false)
        end
    end

    local kickId, kickSecret = KickCredentials()
    if Config.Kick and Config.Kick.enabled then
        if kickId and kickSecret then
            GetKickToken(false)
        elseif Config.Kick.useUnofficialFallback then
            print('[duo-rewards] Kick: no API credentials set, using the unofficial endpoint (may be rate limited or blocked). See README.')
        else
            print('[duo-rewards] Kick tracking is enabled but Config.Kick.clientId + clientSecret are not set. Kick streams will not be tracked.')
        end
    end

    while true do
        local ok, err = pcall(PollStreams)
        if not ok then
            print(('[duo-rewards] Stream polling error: %s'):format(tostring(err)))
        end
        trackingCache = {}
        Wait(math.max(1, tonumber(Config.PollIntervalMinutes) or 5) * 60 * 1000)
    end
end)
