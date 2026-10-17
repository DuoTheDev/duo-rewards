--[[
    duo-rewards — Configuration
    ---------------------------------------------------------------------------
    Everything below can be changed freely. Restart the resource after editing.

    SECRETS (Twitch / Kick API keys, Discord webhook)
    You can paste them into this file, OR leave the fields empty and set them as
    convars in server.cfg so they never end up in git or a public repository:

        set duo_rewards_twitch_client_id     "xxxxxxxx"
        set duo_rewards_twitch_client_secret "xxxxxxxx"
        set duo_rewards_twitch_access_token  "xxxxxxxx"   -- optional, see Config.Twitch
        set duo_rewards_kick_client_id       "xxxxxxxx"
        set duo_rewards_kick_client_secret   "xxxxxxxx"
        set duo_rewards_discord_webhook      "https://discord.com/api/webhooks/..."

    A value in this file wins when both are set. Use `set`, NOT `setr`, so the
    values are never replicated to clients.
]]

Config = {}

-- ============================================================================
-- GENERAL
-- ============================================================================
Config.PanelTitle  = 'REWARDS'      -- Text shown in the panel header
Config.FooterText  = 'Made by Duo'  -- Text shown in the panel footer ('' to hide)
Config.OpenCommand = 'rewards'      -- Chat command that toggles the panel
Config.OpenKey     = ''             -- Default keybind, e.g. 'F7'. '' = no default key. Players can always bind it in Settings > Key Bindings > FiveM
Config.Notify      = 'qb'           -- 'qb' = QBCore:Notify, 'ox' = ox_lib notifications
Config.Debug       = false          -- Verbose server console logging

-- ============================================================================
-- STREAM TRACKING
-- ============================================================================
-- A player earns stream minutes while ALL of the following are true:
--   1. They are connected to the server with a loaded character
--   2. Their linked Twitch or Kick channel is live
--   3. The stream title contains Config.StreamKeyword (case-insensitive)
Config.StreamKeyword              = 'MyServer RP' -- Keyword that must appear in the stream title
Config.PollIntervalMinutes        = 5             -- How often to poll Twitch/Kick. Each poll credits this many minutes
Config.NotifyOnStreamTick         = true          -- Notify the player every time stream minutes are credited
Config.TrackingStatusCacheSeconds = 60            -- How long the "Tracking Active" banner result is cached per player (limits API calls)

Config.Twitch = {
    enabled      = true,
    clientId     = '',   -- Create an app at https://dev.twitch.tv/console/apps
    clientSecret = '',   -- Recommended. App access tokens are generated and refreshed automatically
    accessToken  = '',   -- Optional manual App Access Token. Only used when clientSecret is empty (these expire after ~60 days)
}

Config.Kick = {
    enabled      = true,
    clientId     = '',   -- Create an app at https://kick.com/settings/developer (official Kick API, recommended)
    clientSecret = '',
    -- Without clientId/clientSecret the resource falls back to Kick's unofficial
    -- website endpoint. It needs no credentials, but is rate limited and is often
    -- blocked by Cloudflare. Set to false to disable the fallback entirely.
    useUnofficialFallback = true,
}

-- ============================================================================
-- PLAYTIME
-- ============================================================================
Config.PlaytimeTickSeconds = 60  -- Playtime is credited in whole minutes. Keep this at 60 (or a multiple of 60)

-- ============================================================================
-- INTERVAL REWARDS
-- ============================================================================
-- Each block: every `interval` units the player receives `money` + `items`.
-- Set interval = 0 to disable a reward. Items use ox_inventory item names.
-- If the player is offline, or their inventory is full, items are queued and
-- delivered the next time they load in.
Config.RewardMoneyType = 'bank'  -- 'bank' or 'cash': account used for interval reward money and referrer payouts

-- Every X minutes streamed
Config.StreamReward = {
    interval = 60,
    money    = 500,
    items    = { { name = 'bandage', label = 'Bandage', count = 2 } },
}

-- Every X minutes of playtime
Config.PlaytimeReward = {
    interval = 120,
    money    = 250,
    items    = {},
}

-- Every X successful referrals
Config.ReferralReward = {
    interval = 5,
    money    = 10000,
    items    = { { name = 'armour', label = 'Body Armour', count = 1 } },
}

-- Every X minutes that the players you referred spend on the server (combined)
Config.ReferralPlaytimeReward = {
    interval = 600,
    money    = 1000,
    items    = {},
}

-- ============================================================================
-- REFERRALS
-- ============================================================================
-- New players redeem someone's referral code, wait `ReferralClaimDelayMins`,
-- then claim a care package. The referrer is paid instantly per redemption.
Config.ReferralCarePackage = {
    money     = 5000,
    moneyType = 'cash',
    items = {
        { name = 'bandage',  label = 'Bandage',  count = 5 },
        { name = 'water',    label = 'Water',    count = 5 },
        { name = 'lockpick', label = 'Lockpick', count = 1 },
    },
}

Config.ReferrerRewardPerUse   = 2500 -- Money the referrer receives per redemption (Config.RewardMoneyType)
Config.ReferralClaimDelayMins = 60   -- Minutes the new player must wait before claiming the care package (0 = instant)

Config.ReferralCodeMinLength  = 3    -- Custom code length limits (players may customise their code once)
Config.ReferralCodeMaxLength  = 12   -- Hard cap is 20

-- Eligibility rules for redeeming a code (anti-abuse). 0 / false disables a rule.
Config.MaxPlaytimeToRedeem         = 120  -- Max total playtime (minutes, all characters) to still count as a new player
Config.MaxAccountAgeDays           = 7    -- Max days since the account's first loyalty profile was created
Config.ReferralBlockMultiCharacter = true -- Block redemption if the account already has more than one character

-- ============================================================================
-- LEADERBOARD / UI
-- ============================================================================
Config.LeaderboardMax     = 15  -- Max players shown on each leaderboard
Config.LiveRefreshSeconds = 10  -- How often the panel refreshes its data while open

-- ============================================================================
-- DISCORD LOGGING
-- ============================================================================
Config.DiscordWebhook   = ''              -- Webhook URL ('' disables logging). Can also be set via convar, see top of file
Config.DiscordBotName   = 'Duo Rewards'
Config.DiscordBotAvatar = ''              -- Optional avatar image URL

-- Which events to log (set false to disable)
Config.DiscordLogs = {
    playerJoin         = false, -- Player loaded with a loyalty profile
    twitchLink         = true,  -- Linked / unlinked a Twitch or Kick account
    streamTracked      = true,  -- Stream minutes credited
    referralRedeemed   = true,  -- Someone redeemed a referral code
    referralCodeEdited = true,  -- Player customised their referral code
    carePackageClaimed = true,  -- Care package claimed
    rewardMilestone    = true,  -- Interval reward earned (stream / playtime / referrals)
    avatarChanged      = true,  -- Player changed their avatar
    adminAction        = true,  -- Admin commands used
    pendingDelivery    = true,  -- Queued rewards delivered on connect
    watchStream        = true,  -- Player clicked "Watch" on someone's stream
}
