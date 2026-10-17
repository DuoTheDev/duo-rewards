-- ============================================================================
-- duo-rewards — Database schema
-- Run this against your QBCore database before starting the resource.
-- Safe to re-run: every statement uses IF NOT EXISTS.
-- The resource also reads the QBCore `players` table (charinfo, money).
-- ============================================================================

CREATE TABLE IF NOT EXISTS `loyalty_profiles` (
    `id`                       INT          AUTO_INCREMENT PRIMARY KEY,
    `citizenid`                VARCHAR(50)  NOT NULL,
    `license`                  VARCHAR(100) NOT NULL,
    `twitch_username`          VARCHAR(100) DEFAULT NULL,
    `kick_username`            VARCHAR(100) DEFAULT NULL,
    `referral_code`            VARCHAR(20)  NOT NULL,
    `referred_by`              VARCHAR(20)  DEFAULT NULL,
    `total_stream_minutes`     INT          DEFAULT 0,
    `current_period_minutes`   INT          DEFAULT 0,
    `total_referrals`          INT          DEFAULT 0,
    `playtime_minutes`         INT          DEFAULT 0,
    `xp`                       INT          DEFAULT 0,      -- unused, kept for upgrades from 1.0.x
    `level`                    INT          DEFAULT 1,      -- unused, kept for upgrades from 1.0.x
    `referral_redeemed_at`     TIMESTAMP    NULL DEFAULT NULL,
    `care_package_claimed`     TINYINT(1)   DEFAULT 0,
    `avatar_url`               VARCHAR(500) DEFAULT NULL,
    `referral_playtime_earned` INT          DEFAULT 0,
    `referral_code_edited`     TINYINT(1)   DEFAULT 0,
    `created_at`               TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_license`         (`license`),
    INDEX `idx_twitch_username` (`twitch_username`),
    INDEX `idx_kick_username`   (`kick_username`),
    UNIQUE KEY `uk_referral_code` (`referral_code`),
    UNIQUE KEY `uk_citizenid`     (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- History of everything that happened to a profile (stream ticks, rewards, referrals)
CREATE TABLE IF NOT EXISTS `loyalty_events` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid`  VARCHAR(50)  NOT NULL,
    `event_type` ENUM('stream_tick', 'referral_used', 'referral_reward', 'leaderboard_reward', 'care_package', 'level_up') NOT NULL,
    `value`      VARCHAR(255) DEFAULT NULL,
    `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_citizenid`  (`citizenid`),
    INDEX `idx_event_type` (`event_type`),
    INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- One row per redeemed referral code. The UNIQUE key enforces one redemption per account (license).
CREATE TABLE IF NOT EXISTS `referral_uses` (
    `id`                    INT AUTO_INCREMENT PRIMARY KEY,
    `code_used`             VARCHAR(20)  NOT NULL,
    `redeemed_by_citizenid` VARCHAR(50)  NOT NULL,
    `redeemed_by_license`   VARCHAR(100) NOT NULL,
    `referrer_citizenid`    VARCHAR(50)  NOT NULL,
    `created_at`            TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_redeemed_license` (`redeemed_by_license`),
    INDEX `idx_code_used` (`code_used`),
    INDEX `idx_referrer`  (`referrer_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Items earned while offline (or that did not fit in the inventory), delivered on next login
CREATE TABLE IF NOT EXISTS `loyalty_pending_rewards` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid`  VARCHAR(50)  NOT NULL,
    `items`      JSON         NOT NULL,
    `reason`     VARCHAR(255) DEFAULT NULL,
    `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- UPGRADING FROM 1.0.x
-- The 1.1.0 schema is identical except for two new indexes. Run these only if
-- you installed an earlier version (errors about duplicate keys can be ignored):
--
-- ALTER TABLE `loyalty_profiles` ADD INDEX `idx_kick_username` (`kick_username`);
-- ALTER TABLE `loyalty_events`   ADD INDEX `idx_created_at`    (`created_at`);
--
-- If your install predates the Kick / offline-reward features, also run:
--
-- ALTER TABLE `loyalty_profiles` ADD COLUMN `kick_username` VARCHAR(100) DEFAULT NULL AFTER `twitch_username`;
-- ALTER TABLE `loyalty_profiles` ADD COLUMN `referral_redeemed_at` TIMESTAMP NULL DEFAULT NULL AFTER `level`;
-- ALTER TABLE `loyalty_profiles` ADD COLUMN `care_package_claimed` TINYINT(1) DEFAULT 0 AFTER `referral_redeemed_at`;
-- ALTER TABLE `loyalty_profiles` ADD COLUMN `avatar_url` VARCHAR(500) DEFAULT NULL;
-- ALTER TABLE `loyalty_profiles` ADD COLUMN `referral_playtime_earned` INT DEFAULT 0;
-- ALTER TABLE `loyalty_profiles` ADD COLUMN `referral_code_edited` TINYINT(1) DEFAULT 0;
-- (and create `loyalty_pending_rewards` with the statement above)
-- ============================================================================
