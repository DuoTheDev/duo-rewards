local QBCore = exports['qb-core']:GetCoreObject()
local isOpen = false
local CloseLoyaltyPanel -- forward declaration (used by OpenLoyaltyPanel)

-- ============================================================================
-- DATA
-- ============================================================================

local function FetchAllData()
    QBCore.Functions.TriggerCallback('loyalty:server:getProfile', function(profile)
        SendNUIMessage({ action = 'setProfile', data = profile })
    end)
    QBCore.Functions.TriggerCallback('loyalty:server:getLeaderboard', function(leaderboard)
        SendNUIMessage({ action = 'setLeaderboard', data = leaderboard })
    end)
    QBCore.Functions.TriggerCallback('loyalty:server:getReferralStats', function(stats)
        SendNUIMessage({ action = 'setReferralStats', data = stats })
    end)
    QBCore.Functions.TriggerCallback('loyalty:server:getTrackingStatus', function(status)
        SendNUIMessage({ action = 'setTrackingStatus', data = status })
    end)
    QBCore.Functions.TriggerCallback('loyalty:server:getRewardHistory', function(history)
        SendNUIMessage({ action = 'setRewardHistory', data = history })
    end)
    QBCore.Functions.TriggerCallback('loyalty:server:getActivity', function(activity)
        SendNUIMessage({ action = 'setActivity', data = activity })
    end)
end

local function BuildConfigPayload()
    return {
        panelTitle             = Config.PanelTitle,
        footerText             = Config.FooterText,
        streamKeyword          = Config.StreamKeyword,
        pollInterval           = Config.PollIntervalMinutes,
        twitchEnabled          = Config.Twitch and Config.Twitch.enabled ~= false,
        kickEnabled            = Config.Kick and Config.Kick.enabled ~= false,
        carePackage            = Config.ReferralCarePackage,
        maxPlaytime            = Config.MaxPlaytimeToRedeem,
        claimDelayMins         = Config.ReferralClaimDelayMins,
        codeMinLength          = Config.ReferralCodeMinLength,
        codeMaxLength          = math.min(20, Config.ReferralCodeMaxLength or 12),
        streamReward           = Config.StreamReward,
        playtimeReward         = Config.PlaytimeReward,
        referralReward         = Config.ReferralReward,
        referralPlaytimeReward = Config.ReferralPlaytimeReward,
    }
end

-- ============================================================================
-- OPEN / CLOSE
-- ============================================================================

local function OpenLoyaltyPanel()
    if isOpen then return end
    local playerData = QBCore.Functions.GetPlayerData()
    if not playerData or not playerData.citizenid then return end -- not logged into a character yet

    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'setConfig', data = BuildConfigPayload() })
    SendNUIMessage({ action = 'open' })
    FetchAllData()

    -- Live refresh while open
    CreateThread(function()
        while isOpen do
            Wait((Config.LiveRefreshSeconds or 10) * 1000)
            if isOpen then FetchAllData() end
        end
    end)

    -- Safety net: ESC is also handled inside the NUI, this guarantees focus is released
    CreateThread(function()
        while isOpen do
            Wait(0)
            if IsDisabledControlJustPressed(0, 200) then -- ESC
                CloseLoyaltyPanel()
            end
        end
    end)
end

CloseLoyaltyPanel = function()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- ============================================================================
-- COMMAND / KEYBIND
-- ============================================================================

RegisterCommand(Config.OpenCommand, function()
    if isOpen then
        CloseLoyaltyPanel()
    else
        OpenLoyaltyPanel()
    end
end, false)

TriggerEvent('chat:addSuggestion', '/' .. Config.OpenCommand, 'Open the rewards panel')
RegisterKeyMapping(Config.OpenCommand, 'Open the rewards panel', 'keyboard', Config.OpenKey or '')

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    CloseLoyaltyPanel()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    isOpen = false
    SetNuiFocus(false, false)
end)

-- ============================================================================
-- NUI CALLBACKS
-- ============================================================================

RegisterNUICallback('close', function(_, cb)
    CloseLoyaltyPanel()
    cb('ok')
end)

RegisterNUICallback('refreshData', function(_, cb)
    FetchAllData()
    cb('ok')
end)

--- Forwards a NUI action to a server callback and refreshes the panel on success.
local function ForwardToServer(nuiName, serverCallback, getArg)
    RegisterNUICallback(nuiName, function(data, cb)
        QBCore.Functions.TriggerCallback(serverCallback, function(result)
            result = result or { success = false, message = 'No response from server.' }
            cb(result)
            if result.success then FetchAllData() end
        end, getArg and getArg(data or {}) or nil)
    end)
end

ForwardToServer('linkTwitch',        'loyalty:server:linkTwitch',        function(d) return d.username end)
ForwardToServer('unlinkTwitch',      'loyalty:server:unlinkTwitch')
ForwardToServer('linkKick',          'loyalty:server:linkKick',          function(d) return d.username end)
ForwardToServer('unlinkKick',        'loyalty:server:unlinkKick')
ForwardToServer('redeemCode',        'loyalty:server:redeemCode',        function(d) return d.code end)
ForwardToServer('editReferralCode',  'loyalty:server:editReferralCode',  function(d) return d.code or '' end)
ForwardToServer('setAvatar',         'loyalty:server:setAvatar',         function(d) return d.url or '' end)
ForwardToServer('claimCarePackage',  'loyalty:server:claimCarePackage')

RegisterNUICallback('watchStream', function(data, cb)
    data = data or {}
    QBCore.Functions.TriggerCallback('loyalty:server:logWatchStream', function() end, {
        username = data.username,
        url      = data.url,
    })
    cb('ok')
end)
