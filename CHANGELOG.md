# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-10-17

First public release.

### Added
- Automatic Twitch app-access-token generation and refresh (client credentials flow). Manual tokens still work as a fallback.
- Official Kick API support (client credentials) with batched channel lookups; the unofficial endpoint remains as an optional fallback.
- Secrets can be supplied through server convars (`duo_rewards_*`) instead of `config.lua`.
- `Config.MaxAccountAgeDays` is now enforced (it existed but was never checked).
- `Config.ReferralBlockMultiCharacter`, `Config.NotifyOnStreamTick`, `Config.TrackingStatusCacheSeconds`, `Config.RewardMoneyType`, `Config.ReferralCarePackage.moneyType`, `Config.PanelTitle`, `Config.FooterText`, `Config.OpenKey`, `Config.Notify` (QBCore or ox_lib notifications).
- `/loyaltyunlink` admin command (works for offline players by citizenid).
- Server exports: `GetProfile`, `IsPlayerLive`, `GetLiveStreamers`.
- Key mapping for the open command (bindable in FiveM settings) and a chat suggestion.
- Rewards that do not fit in the inventory are queued instead of lost; queued rewards that still do not fit stay queued.
- Per-player cache for the panel's tracking-status check and a shared cache for leaderboard queries.
- CI (luacheck + JS syntax + secret scan) and tag-triggered GitHub releases.

### Changed
- Twitch/Kick polling is now sequential, so a player live on both platforms is credited exactly once per poll.
- Twitch requests include `first=100`; previously only 20 streams per request were returned.
- Playtime loop snapshots the player list before yielding to the database (iterating a table that is modified while yielding is undefined behaviour in Lua).
- `/loyaltycatchup` reuses the normal payout path, so catch-up rewards create the same history rows and notifications.
- Referral redemption and care-package claims are atomic (unique key / conditional update) to prevent double payouts from spam clicks.
- Profile callback no longer returns the full row (license is not sent to the client).
- Referral codes no longer use the characters `0`, `O`, `1` and `I`.
- Dead leveling / XP / milestone styles removed from the NUI stylesheet.

### Fixed
- Client script called `CloseLoyaltyPanel` before it was defined (`local function` declared later), which errored when ESC was pressed through the game control.
- Stored XSS: avatar URLs and other values were inserted into HTML attributes without escaping quotes, and avatar images used inline `onerror` handlers. Attribute values are now fully escaped, avatar URLs are validated against a strict allow-list, and inline handlers were removed.
- "Watch" clicks were logged with the wrong field, so Discord always showed `?`.
- Referral input allowed only 10 characters although codes can be up to 12 (now 20).
- Activity heatmap tooltips assumed a 5-minute poll interval.
- Countdown timer kept running after the panel was closed through ESC.
- Discord webhook was sent an empty `avatar_url`.
- Offline money payouts could write `NULL` when the money column lacked the key.

### Removed
- Server-specific referral eligibility check (replaced by `Config.MaxAccountAgeDays`).
- Hardcoded server branding and credentials from the config and UI.

## [1.0.0]

Internal release.

[1.1.0]: https://github.com/DuoTheDev/duo-rewards/releases/tag/v1.1.0
