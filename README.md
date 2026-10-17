<div align="center">

# duo-rewards

**Twitch & Kick stream tracking, referrals, interval rewards and leaderboards for QBCore. One `/rewards` panel.**

[![Release](https://img.shields.io/github/v/release/DuoTheDev/duo-rewards?style=flat-square&color=8b5cf6)](https://github.com/DuoTheDev/duo-rewards/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/DuoTheDev/duo-rewards/total?style=flat-square&color=22c55e)](https://github.com/DuoTheDev/duo-rewards/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/DuoTheDev/duo-rewards/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/DuoTheDev/duo-rewards/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/DuoTheDev/duo-rewards?style=flat-square)](LICENSE)
[![Framework](https://img.shields.io/badge/framework-QBCore-ef4444?style=flat-square)](https://github.com/qbcore-framework/qb-core)
[![Inventory](https://img.shields.io/badge/inventory-ox__inventory-3b82f6?style=flat-square)](https://github.com/overextended/ox_inventory)
[![Lua](https://img.shields.io/badge/lua-5.4-2c2d72?style=flat-square)](https://www.lua.org/)

[Features](#features) · [Installation](#installation) · [Twitch setup](#twitch-setup) · [Kick setup](#kick-setup) · [Configuration](#configuration) · [Commands](#commands) · [How it works](#how-it-works) · [FAQ](#faq--troubleshooting)

</div>

---

## Features

| | |
|---|---|
| 📺 **Stream tracking** | Players link a Twitch and/or Kick channel. While they are **in your server**, **live**, and have your **keyword in the stream title**, they earn stream minutes. Twitch and Kick API tokens are generated and refreshed automatically. |
| 🤝 **Referral system** | Every player gets a referral code (customisable once). New players redeem a code, wait a configurable delay, then claim a care package. Referrers earn cash per redemption and bonuses for referral milestones and for the playtime of the people they referred. Built-in anti-abuse rules (one redemption per account, playtime and account-age limits, multi-character check). |
| 🎁 **Interval rewards** | "Every X minutes streamed / played / every X referrals → money + items". Items that do not fit, or are earned while offline, are queued and delivered on next login. An admin catch-up command re-pays anything missed. |
| 🏆 **Leaderboards** | Stream time, playtime and referrals, with a podium for the top three, live badges, viewer counts, click-to-preview player cards and a **Watch** button that opens the stream. |
| 📊 **Activity & history** | GitHub-style 12-week streaming heatmap and a reward history per player. |
| 🖼️ **Profiles** | Custom avatar URL per player, shown on the leaderboards. |
| 🔔 **Discord logging** | Rich embeds for every important event, each one can be toggled. |
| 🔐 **Secrets stay private** | All API keys and the webhook can be supplied through server convars instead of `config.lua`. |

## Requirements

| Dependency | Notes |
|---|---|
| [qb-core](https://github.com/qbcore-framework/qb-core) | Player data, money, notifications, admin permissions |
| [oxmysql](https://github.com/overextended/oxmysql) | Database |
| [ox_inventory](https://github.com/overextended/ox_inventory) | Item rewards |
| MySQL 5.7+ / MariaDB 10.2.7+ | JSON functions are used for offline money payouts |
| [ox_lib](https://github.com/overextended/ox_lib) *(optional)* | Only if you set `Config.Notify = 'ox'` |

## Installation

1. **Download** the [latest release](https://github.com/DuoTheDev/duo-rewards/releases/latest) and extract it into your `resources` folder. The folder **must** be named `duo-rewards`.
2. **Import the database schema**: run [`sql/install.sql`](sql/install.sql) against your QBCore database (HeidiSQL, phpMyAdmin, or the CLI):
   ```bash
   mysql -u root -p your_database < resources/duo-rewards/sql/install.sql
   ```
3. **Add it to `server.cfg`**, after your dependencies:
   ```cfg
   ensure qb-core
   ensure oxmysql
   ensure ox_inventory
   ensure duo-rewards
   ```
4. **Configure** [`config.lua`](config.lua): set `Config.StreamKeyword`, your rewards, and the reward items (ox_inventory item names).
5. **Add your API credentials** (see [Twitch setup](#twitch-setup) and [Kick setup](#kick-setup)). Either paste them into `config.lua`, or keep them out of the file entirely with convars in `server.cfg`:
   ```cfg
   set duo_rewards_twitch_client_id     "xxxxxxxx"
   set duo_rewards_twitch_client_secret "xxxxxxxx"
   set duo_rewards_kick_client_id       "xxxxxxxx"
   set duo_rewards_kick_client_secret   "xxxxxxxx"
   set duo_rewards_discord_webhook      "https://discord.com/api/webhooks/..."
   ```
   Use `set`, not `setr`, so the values are never sent to clients. A value in `config.lua` takes priority over a convar.
6. Restart the server. Players open the panel with `/rewards` (configurable) or a keybind they set under **Settings → Key Bindings → FiveM**.

## Twitch setup

1. Go to the [Twitch Developer Console](https://dev.twitch.tv/console/apps) and click **Register Your Application**.
2. **Name**: anything. **OAuth Redirect URLs**: `http://localhost` (required by Twitch but never used; the resource uses the server-to-server *client credentials* flow). **Category**: *Application Integration*.
3. Open the app, copy the **Client ID**, then click **New Secret** and copy the **Client Secret**.
4. Put both in `Config.Twitch` (or the convars above).

That's it. The resource requests an *App Access Token* on startup and refreshes it automatically before it expires, so you never have to touch tokens by hand.

> **Manual token (not recommended)**: if you really do not want the secret on the server, you can generate an App Access Token yourself and put it in `Config.Twitch.accessToken` with the secret left empty. These tokens expire after about 60 days and the console will tell you when Twitch rejects it.

## Kick setup

Kick has an official API with the same client-credentials flow:

1. Log in to Kick, open **Settings → Developer** (https://kick.com/settings/developer) and create an app.
2. Copy the **Client ID** and **Client Secret** into `Config.Kick` (or the convars).

Without credentials the resource falls back to Kick's unofficial website endpoint (`kick.com/api/v2/channels/<name>`). It works without a key, but it is rate limited and is frequently blocked by Cloudflare, so Kick tracking may silently stop working. Set `Config.Kick.useUnofficialFallback = false` if you would rather disable Kick than rely on it, or `Config.Kick.enabled = false` to hide Kick from the panel completely.

## Configuration

Everything lives in [`config.lua`](config.lua) and is commented. The important bits:

<details>
<summary><strong>General</strong></summary>

| Setting | Default | Description |
|---|---|---|
| `PanelTitle` | `'REWARDS'` | Title in the panel header |
| `FooterText` | `'Made by Duo'` | Footer text (`''` to hide) |
| `OpenCommand` | `'rewards'` | Chat command that toggles the panel |
| `OpenKey` | `''` | Default keybind (e.g. `'F7'`). Players can rebind it in their FiveM settings |
| `Notify` | `'qb'` | `'qb'` for QBCore notifications, `'ox'` for ox_lib |
| `Debug` | `false` | Verbose console logging |

</details>

<details>
<summary><strong>Stream tracking</strong></summary>

| Setting | Default | Description |
|---|---|---|
| `StreamKeyword` | `'MyServer RP'` | Must appear in the stream title (case-insensitive) |
| `PollIntervalMinutes` | `5` | How often Twitch/Kick are polled. Each poll credits this many minutes |
| `NotifyOnStreamTick` | `true` | Notify the player each time minutes are credited |
| `TrackingStatusCacheSeconds` | `60` | How long the panel's "Tracking Active" check is cached per player |
| `Twitch.enabled` / `clientId` / `clientSecret` / `accessToken` | | See [Twitch setup](#twitch-setup) |
| `Kick.enabled` / `clientId` / `clientSecret` / `useUnofficialFallback` | | See [Kick setup](#kick-setup) |

</details>

<details>
<summary><strong>Rewards</strong></summary>

Every reward block has the same shape:

```lua
Config.StreamReward = {
    interval = 60,                                   -- every 60 minutes streamed...
    money    = 500,                                  -- ...pay $500 (0 = none)
    items    = { { name = 'bandage', label = 'Bandage', count = 2 } },  -- ...and give these items ({} = none)
}
```

| Block | Counts |
|---|---|
| `StreamReward` | Minutes streamed with the keyword |
| `PlaytimeReward` | Minutes online with a loaded character |
| `ReferralReward` | Successful referrals |
| `ReferralPlaytimeReward` | Combined minutes played by everyone you referred |

`RewardMoneyType` (`'bank'` or `'cash'`) controls where interval-reward money and referrer payouts go. Set `interval = 0` to disable a block.

</details>

<details>
<summary><strong>Referrals</strong></summary>

| Setting | Default | Description |
|---|---|---|
| `ReferralCarePackage` | `$5,000` cash + items | What a new player receives when they claim |
| `ReferrerRewardPerUse` | `2500` | Paid to the referrer on every redemption |
| `ReferralClaimDelayMins` | `60` | Minutes the new player must wait before claiming (`0` = instant) |
| `ReferralCodeMinLength` / `MaxLength` | `3` / `12` | Limits for custom codes (hard cap 20) |
| `MaxPlaytimeToRedeem` | `120` | Players with more total playtime (all characters) cannot redeem. `0` disables |
| `MaxAccountAgeDays` | `7` | Players whose first profile is older than this cannot redeem. `0` disables |
| `ReferralBlockMultiCharacter` | `true` | Accounts with more than one character cannot redeem |

</details>

<details>
<summary><strong>Leaderboard, UI and Discord</strong></summary>

| Setting | Default | Description |
|---|---|---|
| `LeaderboardMax` | `15` | Rows per leaderboard |
| `LiveRefreshSeconds` | `10` | Panel auto-refresh interval while open |
| `DiscordWebhook` | `''` | Webhook URL (`''` disables logging) |
| `DiscordBotName` / `DiscordBotAvatar` | | Webhook display name and avatar |
| `DiscordLogs.*` | mostly `true` | Toggle each event type individually |

</details>

## Commands

### Players

| Command | Description |
|---|---|
| `/rewards` | Open / close the panel (name set by `Config.OpenCommand`) |

### Admins (QBCore `admin` permission)

| Command | Description |
|---|---|
| `/loyaltystats [id]` | Print a player's profile to chat (yourself if no ID) |
| `/loyaltyreset` | Reset everyone's "this period" stream minutes (all-time totals are untouched) |
| `/loyaltycatchup [id]` | Re-pay any interval rewards a player should have received but did not (e.g. after changing intervals) |
| `/loyaltyunlink [id or citizenid] [twitch\|kick]` | Remove a linked channel from a player, works for offline players by citizenid |

## How it works

<details>
<summary><strong>Stream tracking</strong></summary>

* Every `PollIntervalMinutes` the server collects the linked channels of **connected** players and queries Twitch (100 channels per request) and Kick (50 per request with the official API).
* A channel counts when it is live **and** the title contains `StreamKeyword`. The player is credited `PollIntervalMinutes` minutes, a `stream_tick` event is stored (this feeds the heatmap), and interval rewards are checked.
* A player live on both platforms is credited once per poll. A guard on the last tick timestamp prevents double credit after a quick resource restart.
* When a player joins or links a channel, their status is checked immediately so they appear as live right away.
* "This period" minutes are a separate counter you can reset with `/loyaltyreset`, handy for monthly contests.

</details>

<details>
<summary><strong>Referrals</strong></summary>

1. A new player enters a code in the **Referrals** tab. The server checks all anti-abuse rules (see configuration), then records the use. The `referral_uses` table has a unique key per account, so a code can only ever be redeemed once per license even if the button is spammed.
2. The referrer is paid `ReferrerRewardPerUse` immediately and their referral count goes up (which can trigger `ReferralReward`).
3. After `ReferralClaimDelayMins` the new player can claim the care package from the panel. Claims are also guarded against double clicks.
4. From then on, every minute the referred player spends online is added to the referrer's "referral playtime", which pays out `ReferralPlaytimeReward`.

If a player customises their code, everyone who was referred with the old code is updated automatically.

</details>

<details>
<summary><strong>Reward delivery</strong></summary>

* Money is added with `Player.Functions.AddMoney`, or written directly to the `players` table for offline players.
* Items are added with `ox_inventory:AddItem`. If the player is offline, or an item does not fit, it goes to `loyalty_pending_rewards` and is delivered the next time they load in. If it still does not fit, it stays queued.
* Every milestone writes a row to `loyalty_events`. `/loyaltycatchup` compares those rows with what the player's totals say they should have received and pays the difference.

</details>

<details>
<summary><strong>Database tables</strong></summary>

| Table | Purpose |
|---|---|
| `loyalty_profiles` | One row per character: linked channels, referral code, counters, avatar |
| `loyalty_events` | History: stream ticks, rewards, referrals, care packages |
| `referral_uses` | One row per redeemed code (unique per account) |
| `loyalty_pending_rewards` | Items waiting to be delivered |

The resource also reads `players.charinfo` (names) and updates `players.money` for offline payouts.

</details>

## Exports

```lua
-- Full profile row for a character, or nil
local profile = exports['duo-rewards']:GetProfile(citizenid)

-- Is this character live with the keyword right now? Returns boolean, { viewer_count, username, platform }
local live, info = exports['duo-rewards']:IsPlayerLive(citizenid)

-- { [citizenid] = { viewer_count, username, platform } }
local streamers = exports['duo-rewards']:GetLiveStreamers()
```

## FAQ / Troubleshooting

**"Twitch tracking is enabled but clientId + clientSecret are not set"**
Add your Twitch credentials to `config.lua` or as convars. Twitch tracking is off until you do.

**"Could not obtain a Twitch app access token (HTTP 400/403)"**
The client ID or secret is wrong, or the secret was regenerated in the Twitch console. Copy them again.

**The panel says "Live — missing keyword in stream title"**
The channel is live but the title does not contain `Config.StreamKeyword`. The check is case-insensitive but the keyword must appear exactly.

**Kick never shows as live**
Without Kick API credentials the unofficial endpoint is used and Cloudflare often blocks it (you will see HTTP 403 with `Config.Debug = true`). Create a Kick developer app and add the credentials.

**A player linked someone else's Twitch/Kick name**
Linking is not verified against the platform, it is first-come-first-served per username. Use `/loyaltyunlink` to free the name, then the real owner can link it. Because stream time also requires the keyword in the title *and* being in your server, impersonating a channel does not earn anything on its own.

**Items are not given / "Could not give item"**
The item name must exist in ox_inventory's item list. Items that do not fit are queued and delivered later.

**Nothing shows in the panel**
The player must be fully loaded into a character. Check the F8 console for NUI errors and the server console for `[duo-rewards]` messages.

## Upgrading from 1.0.x

* `config.lua` was reorganised: Twitch credentials moved to `Config.Twitch`, Kick settings are new under `Config.Kick`, and several options were added. Copy your old values into the new file rather than overwriting it.
* The database schema only gained two indexes, see the bottom of [`sql/install.sql`](sql/install.sql).
* A server-specific eligibility check was replaced by the configurable account-age rule.

See [CHANGELOG.md](CHANGELOG.md) for the full list of changes.

## Known limitations

* QBCore + ox_inventory only. ESX / qbx are not supported.
* Channel linking is not verified via OAuth (see FAQ).
* Playtime is credited in whole minutes per tick, so `PlaytimeTickSeconds` should stay at `60`.
* The panel loads the *Inter* font from Google Fonts; without internet access on the client it falls back to the system font.

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first; CI runs `luacheck` and a JavaScript syntax check on every push.

## License

[MIT](LICENSE) © Duo Development
