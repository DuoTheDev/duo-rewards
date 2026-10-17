local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================================
-- REFERRAL CODE REDEMPTION
-- ============================================================================

--- Anti-abuse checks. Returns nil when the player may redeem, otherwise a message explaining why not.
local function GetIneligibilityReason(license, profile)
    -- Any character on this account already redeemed a code?
    local used = MySQL.scalar.await('SELECT COUNT(*) FROM referral_uses WHERE redeemed_by_license = ?', { license }) or 0
    if used > 0 then
        return 'A referral code has already been redeemed on this account.'
    end

    if profile.referred_by and profile.referred_by ~= '' then
        return 'You have already used a referral code.'
    end

    -- More than one character on the account: not a new player
    if Config.ReferralBlockMultiCharacter then
        local characters = MySQL.scalar.await('SELECT COUNT(*) FROM loyalty_profiles WHERE license = ?', { license }) or 0
        if characters > 1 then
            return 'Referral codes can only be redeemed by new players.'
        end
    end

    -- Too much playtime across all characters
    local maxPlaytime = Config.MaxPlaytimeToRedeem or 0
    if maxPlaytime > 0 then
        local playtime = MySQL.scalar.await('SELECT COALESCE(SUM(playtime_minutes), 0) FROM loyalty_profiles WHERE license = ?', { license }) or 0
        if playtime >= maxPlaytime then
            return ('Too much playtime to use a referral code (max %s minutes).'):format(maxPlaytime)
        end
    end

    -- Account too old, measured from the first loyalty profile created on this license
    local maxAge = Config.MaxAccountAgeDays or 0
    if maxAge > 0 then
        local ageDays = MySQL.scalar.await('SELECT TIMESTAMPDIFF(DAY, MIN(created_at), NOW()) FROM loyalty_profiles WHERE license = ?', { license }) or 0
        if ageDays > maxAge then
            return ('Your account is too old to use a referral code (max %s days).'):format(maxAge)
        end
    end

    return nil
end

QBCore.Functions.CreateCallback('loyalty:server:redeemCode', function(source, cb, code)
    local playerData = ConnectedPlayers[source]
    if not playerData then cb({ success = false, message = 'Player data not found.' }) return end

    local citizenid, license = playerData.citizenid, playerData.license

    code = string.upper(tostring(code or '')):gsub('%s', '')
    if code == '' then
        cb({ success = false, message = 'Please enter a referral code.' })
        return
    end
    if not code:match('^[A-Z0-9]+$') or #code > 20 then
        cb({ success = false, message = 'Invalid referral code.' })
        return
    end

    local profile = MySQL.single.await('SELECT referred_by FROM loyalty_profiles WHERE citizenid = ?', { citizenid })
    if not profile then
        cb({ success = false, message = 'Profile not found.' })
        return
    end

    local reason = GetIneligibilityReason(license, profile)
    if reason then
        cb({ success = false, message = reason })
        return
    end

    local referrer = MySQL.single.await(
        'SELECT citizenid, license, total_referrals FROM loyalty_profiles WHERE referral_code = ?',
        { code }
    )
    if not referrer then
        cb({ success = false, message = 'Invalid referral code.' })
        return
    end
    if referrer.license == license then
        cb({ success = false, message = "You can't use your own referral code." })
        return
    end

    -- Record the use first: the UNIQUE key on redeemed_by_license makes this atomic,
    -- so spamming the button cannot redeem twice.
    local insertId = MySQL.insert.await(
        'INSERT INTO referral_uses (code_used, redeemed_by_citizenid, redeemed_by_license, referrer_citizenid) VALUES (?, ?, ?, ?)',
        { code, citizenid, license, referrer.citizenid }
    )
    if not insertId then
        cb({ success = false, message = 'A referral code has already been redeemed on this account.' })
        return
    end

    MySQL.update.await(
        'UPDATE loyalty_profiles SET referred_by = ?, referral_redeemed_at = NOW() WHERE citizenid = ?',
        { code, citizenid }
    )
    MySQL.update.await(
        'UPDATE loyalty_profiles SET total_referrals = total_referrals + 1 WHERE citizenid = ?',
        { referrer.citizenid }
    )
    local newTotal = (referrer.total_referrals or 0) + 1

    -- Pay the referrer
    local reward = Config.ReferrerRewardPerUse or 0
    local referrerSrc = FindSourceByCitizenId(referrer.citizenid)
    if reward > 0 then
        GivePlayerMoney(referrer.citizenid, reward, referrerSrc, nil, 'referral')
    end
    if referrerSrc then
        if reward > 0 then
            Notify(referrerSrc, ('Someone used your referral code! +$%s'):format(reward), 'success')
        else
            Notify(referrerSrc, 'Someone used your referral code!', 'success')
        end
    end
    CheckIntervalReward(referrer.citizenid, newTotal - 1, newTotal, Config.ReferralReward, referrerSrc, 'Referrals')

    MySQL.insert('INSERT INTO loyalty_events (citizenid, event_type, value) VALUES (?, ?, ?)',
        { citizenid, 'care_package', ('Used referral code %s'):format(code) })
    MySQL.insert('INSERT INTO loyalty_events (citizenid, event_type, value) VALUES (?, ?, ?)',
        { referrer.citizenid, 'referral_used', ('Code used by %s — +$%s'):format(citizenid, reward) })

    local delayMins = Config.ReferralClaimDelayMins or 0
    local message = delayMins > 0
        and ('Referral code redeemed! Care package claimable in %s minutes.'):format(delayMins)
        or 'Referral code redeemed! Your care package is ready to claim.'
    cb({ success = true, message = message })

    DiscordLog('referralRedeemed', 'Referral Code Redeemed', {
        { name = 'Redeemer', value = DiscordPlayerTag(citizenid, source), inline = true },
        { name = 'Code Used', value = code, inline = true },
        { name = 'Referrer', value = DiscordPlayerTag(referrer.citizenid, referrerSrc), inline = true },
        { name = 'Referrer Earned', value = '$' .. tostring(reward), inline = true },
        { name = 'Total Referrals', value = tostring(newTotal), inline = true },
    }, 'success')
end)

-- ============================================================================
-- CARE PACKAGE CLAIM (after the delay)
-- ============================================================================

QBCore.Functions.CreateCallback('loyalty:server:claimCarePackage', function(source, cb)
    local playerData = ConnectedPlayers[source]
    if not playerData then cb({ success = false, message = 'Player data not found.' }) return end

    local profile = MySQL.single.await(
        'SELECT referred_by, referral_redeemed_at, care_package_claimed, '
        .. 'GREATEST(0, TIMESTAMPDIFF(SECOND, NOW(), DATE_ADD(referral_redeemed_at, INTERVAL ? MINUTE))) AS seconds_left '
        .. 'FROM loyalty_profiles WHERE citizenid = ?',
        { Config.ReferralClaimDelayMins or 0, playerData.citizenid }
    )

    if not profile or not profile.referred_by or profile.referred_by == '' then
        cb({ success = false, message = 'You have not used a referral code.' })
        return
    end
    if profile.care_package_claimed == 1 or profile.care_package_claimed == true then
        cb({ success = false, message = 'You have already claimed your care package.' })
        return
    end
    if not profile.referral_redeemed_at then
        cb({ success = false, message = 'Redemption time not found.' })
        return
    end

    local remaining = tonumber(profile.seconds_left) or 0
    if remaining > 0 then
        cb({ success = false, message = ('Care package not ready yet. %d minute(s) remaining.'):format(math.ceil(remaining / 60)) })
        return
    end

    -- Mark as claimed first so a double click cannot claim twice
    local affected = MySQL.update.await(
        'UPDATE loyalty_profiles SET care_package_claimed = 1 WHERE citizenid = ? AND care_package_claimed = 0',
        { playerData.citizenid }
    )
    if (affected or 0) == 0 then
        cb({ success = false, message = 'You have already claimed your care package.' })
        return
    end

    local pkg = Config.ReferralCarePackage or {}
    local money = tonumber(pkg.money) or 0
    if money > 0 then
        GivePlayerMoney(playerData.citizenid, money, source, pkg.moneyType or 'cash', 'referral-care-package')
    end
    DeliverItems(playerData.citizenid, source, pkg.items or {}, 'Referral care package')

    local itemStr = FormatItemList(pkg.items or {})
    MySQL.insert('INSERT INTO loyalty_events (citizenid, event_type, value) VALUES (?, ?, ?)',
        { playerData.citizenid, 'care_package', ('Claimed care package — $%s %s'):format(money, itemStr ~= '' and ('+ ' .. itemStr) or '') })

    cb({ success = true, message = 'Care package claimed! Check your inventory.' })

    DiscordLog('carePackageClaimed', 'Care Package Claimed', {
        { name = 'Player', value = DiscordPlayerTag(playerData.citizenid, source), inline = true },
        { name = 'Money', value = '$' .. tostring(money), inline = true },
        { name = 'Items', value = itemStr ~= '' and itemStr or 'None', inline = false },
    }, 'success')
end)
