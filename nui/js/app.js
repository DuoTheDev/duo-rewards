/* ============================================================================
   duo-rewards — NUI
   ============================================================================ */

const app = document.getElementById('app');

// State
let profile = null;
let leaderboard = {};
let activeLbTab = 'stream';
let referralStats = null;
let trackingStatus = null;
let configData = null;
let previousValues = {};
let careClaimSecondsLeft = 0;
let countdownInterval = null;
let activityData = {};
let rewardHistory = [];
let lbPlayerCache = {};

const resourceName = (typeof GetParentResourceName !== 'undefined') ? GetParentResourceName() : 'duo-rewards';

// ============================================================================
// NUI MESSAGE HANDLER
// ============================================================================

window.addEventListener('message', function (event) {
    const msg = event.data || {};
    switch (msg.action) {
        case 'open':
            app.classList.remove('hidden');
            startCountdownTick();
            break;
        case 'close':
            app.classList.add('hidden');
            stopCountdownTick();
            break;
        case 'setConfig':
            configData = msg.data || {};
            applyConfig();
            renderRewardTrackers();
            break;
        case 'setProfile':
            profile = msg.data;
            renderHeader();
            renderStreamTab();
            renderRewardTrackers();
            break;
        case 'setLeaderboard':
            leaderboard = msg.data || {};
            renderLeaderboard();
            break;
        case 'setReferralStats':
            referralStats = msg.data;
            renderReferrals();
            renderRewardTrackers();
            break;
        case 'setTrackingStatus':
            trackingStatus = msg.data;
            renderTrackingStatus();
            break;
        case 'setActivity':
            activityData = msg.data || {};
            renderActivityGrid();
            break;
        case 'setRewardHistory':
            rewardHistory = msg.data || [];
            renderRewardHistory();
            break;
    }
});

// ============================================================================
// CLOSE ON ESCAPE
// ============================================================================

document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') closePanel();
});

// ============================================================================
// TABS
// ============================================================================

document.querySelectorAll('.tab').forEach(function (tab) {
    tab.addEventListener('click', function () {
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
        tab.classList.add('active');
        document.getElementById('tab-' + tab.getAttribute('data-tab')).classList.add('active');
    });
});

// ============================================================================
// HELPERS
// ============================================================================

function formatTime(minutes) {
    if (!minutes || minutes <= 0) return '0h 00m';
    var h = Math.floor(minutes / 60);
    var m = minutes % 60;
    return h + 'h ' + (m < 10 ? '0' : '') + m + 'm';
}

function formatMoney(amount) {
    if (!amount) return '$0';
    return '$' + amount.toLocaleString();
}

function formatItems(items) {
    if (!items || items.length === 0) return '';
    return items.map(function (i) {
        return i.count + 'x ' + (i.label || i.name);
    }).join(', ');
}

function formatRewardPrize(reward) {
    var parts = [];
    if (reward.money && reward.money > 0) parts.push(formatMoney(reward.money));
    var itemStr = formatItems(reward.items);
    if (itemStr) parts.push(itemStr);
    return parts.join(' + ') || 'None';
}

function nuiCallback(name, data) {
    return fetch('https://' + resourceName + '/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {}),
    }).then(r => r.json());
}

/** Escapes text for use inside HTML content AND attribute values. */
function escapeHtml(text) {
    return String(text == null ? '' : text)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function setVisible(el, visible) {
    if (!el) return;
    if (visible) el.classList.remove('hidden');
    else el.classList.add('hidden');
}

function closePanel() {
    app.classList.add('hidden');
    stopCountdownTick();
    nuiCallback('close').catch(function () {});
}

function showToast(message, type) {
    const existing = document.querySelector('.toast');
    if (existing) existing.remove();

    const toast = document.createElement('div');
    toast.className = 'toast ' + (type || 'success');
    toast.textContent = message;
    document.body.appendChild(toast);

    requestAnimationFrame(() => toast.classList.add('show'));
    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 250);
    }, 2500);
}

/** Animate a stat value change */
function updateStat(id, newValue) {
    const el = document.getElementById(id);
    if (!el) return;
    const old = previousValues[id];
    el.textContent = newValue;
    if (old !== undefined && old !== newValue) {
        el.classList.remove('value-updated');
        void el.offsetWidth; // force reflow
        el.classList.add('value-updated');
    }
    previousValues[id] = newValue;
}

/** Avatar <img> tags carry data-initial; when the image fails to load, show the initial instead. */
document.addEventListener('error', function (e) {
    var img = e.target;
    if (img && img.tagName === 'IMG' && img.hasAttribute('data-initial') && img.parentElement) {
        img.parentElement.textContent = img.getAttribute('data-initial');
    }
}, true);

function avatarImg(url, initial) {
    return '<img src="' + escapeHtml(url) + '" data-initial="' + escapeHtml(initial) + '" alt="" '
        + 'style="width:100%;height:100%;object-fit:cover;border-radius:50%">';
}

// ============================================================================
// CONFIG
// ============================================================================

function applyConfig() {
    if (!configData) return;

    if (configData.panelTitle) {
        document.getElementById('brand-text').textContent = configData.panelTitle;
    }
    var footer = document.getElementById('footer-credit');
    if (footer) footer.textContent = configData.footerText || '';

    if (configData.streamKeyword) {
        document.getElementById('keyword-display').textContent = configData.streamKeyword;
    }

    var maxLen = parseInt(configData.codeMaxLength, 10) || 12;
    document.getElementById('input-custom-code').setAttribute('maxlength', maxLen);

    setVisible(document.getElementById('twitch-card'), configData.twitchEnabled !== false);
    setVisible(document.getElementById('kick-card'), configData.kickEnabled !== false);
}

// ============================================================================
// HEADER
// ============================================================================

function renderHeader() {
    if (!profile) return;

    var avatarImgEl = document.getElementById('avatar-img');
    var avatarInitial = document.getElementById('avatar-initial');
    if (profile.avatar_url) {
        avatarImgEl.src = profile.avatar_url;
        avatarImgEl.classList.remove('hidden');
        avatarInitial.classList.add('hidden');
    } else {
        avatarImgEl.classList.add('hidden');
        avatarInitial.classList.remove('hidden');
        var name = profile.char_name || profile.twitch_username || profile.kick_username || '?';
        avatarInitial.textContent = name.charAt(0).toUpperCase();
    }

    var nameEl = document.getElementById('profile-name');
    if (nameEl) nameEl.textContent = profile.char_name || profile.twitch_username || profile.kick_username || '';
}

// ============================================================================
// STREAM TAB
// ============================================================================

function renderStreamTab() {
    if (!profile) return;

    setVisible(document.getElementById('twitch-linked'), !!profile.twitch_username);
    setVisible(document.getElementById('twitch-unlinked'), !profile.twitch_username);
    if (profile.twitch_username) {
        document.getElementById('twitch-name').textContent = profile.twitch_username;
    }

    setVisible(document.getElementById('kick-linked'), !!profile.kick_username);
    setVisible(document.getElementById('kick-unlinked'), !profile.kick_username);
    if (profile.kick_username) {
        document.getElementById('kick-name').textContent = profile.kick_username;
    }

    updateStat('period-time', formatTime(profile.current_period_minutes));
    updateStat('total-time', formatTime(profile.total_stream_minutes));
    updateStat('lb-rank', profile.leaderboard_rank ? '#' + profile.leaderboard_rank : '#—');
    updateStat('playtime', formatTime(profile.playtime_minutes));
}

function renderTrackingStatus() {
    if (!trackingStatus) return;

    const dot = document.getElementById('tracking-dot');
    const text = document.getElementById('tracking-text');
    const badge = document.getElementById('live-badge');

    dot.className = 'tracking-dot';
    badge.classList.add('hidden');

    if (trackingStatus.tracking) {
        dot.classList.add('active');
        var platformLabel = trackingStatus.platform === 'kick' ? 'Kick' : 'Twitch';
        text.textContent = 'Tracking Active (' + platformLabel + ')'
            + (trackingStatus.viewer_count ? ' — ' + trackingStatus.viewer_count + ' viewers' : '');
        badge.classList.remove('hidden');
    } else if (trackingStatus.reason === 'no_platform_linked') {
        text.textContent = 'Link your Twitch or Kick account to start tracking';
    } else if (trackingStatus.reason === 'missing_keyword') {
        dot.classList.add('warning');
        text.textContent = 'Live — missing keyword in stream title';
    } else if (trackingStatus.reason === 'not_live') {
        text.textContent = 'Not tracking — stream offline';
    } else if (trackingStatus.reason === 'api_error') {
        dot.classList.add('warning');
        text.textContent = 'Tracking unavailable — stream API error';
    } else {
        text.textContent = 'Not tracking';
    }
}

// ============================================================================
// ACTIVITY GRID
// ============================================================================

function renderActivityGrid() {
    var grid = document.getElementById('activity-grid-stream');
    var monthsEl = document.getElementById('activity-months');
    if (!grid) return;

    var today = new Date();
    var monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    // 84 days including today, aligned to the Sunday that starts the first week
    var start = new Date(today);
    start.setDate(start.getDate() - 83);
    start.setDate(start.getDate() - start.getDay());

    var cells = [];
    var d = new Date(start);
    while (d <= today) {
        var key = d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
        cells.push({ date: key, month: d.getMonth(), day: d.getDate(), dow: d.getDay() });
        d.setDate(d.getDate() + 1);
    }
    while (cells.length % 7 !== 0) {
        cells.push({ date: '', month: -1, dow: cells.length % 7, empty: true });
    }

    var totalWeeks = cells.length / 7;

    if (monthsEl) {
        var monthHtml = '<span class="activity-day-spacer"></span>';
        var lastMonth = -1;
        for (var w = 0; w < totalWeeks; w++) {
            var firstCell = cells[w * 7];
            if (firstCell && firstCell.month !== lastMonth && firstCell.month >= 0) {
                monthHtml += '<span class="activity-month-label">' + monthNames[firstCell.month] + '</span>';
                lastMonth = firstCell.month;
            } else {
                monthHtml += '<span class="activity-month-label"></span>';
            }
        }
        monthsEl.innerHTML = monthHtml;
    }

    var maxVal = 0;
    for (var k in activityData) {
        if (activityData[k] > maxVal) maxVal = activityData[k];
    }

    var minutesPerTick = (configData && configData.pollInterval) ? configData.pollInterval : 5;
    var html = '';
    for (var c = 0; c < cells.length; c++) {
        var cell = cells[c];
        if (cell.empty) {
            html += '<div class="activity-cell empty"></div>';
            continue;
        }
        var val = activityData[cell.date] || 0;
        var level = 0;
        if (maxVal > 0 && val > 0) {
            var pct = val / maxVal;
            if (pct > 0.75) level = 4;
            else if (pct > 0.5) level = 3;
            else if (pct > 0.25) level = 2;
            else level = 1;
        }
        html += '<div class="activity-cell level-' + level + '" title="' + cell.date + ': ' + (val * minutesPerTick) + ' min streamed"></div>';
    }

    grid.innerHTML = html;
}

// ============================================================================
// REFERRALS TAB
// ============================================================================

function renderReferrals() {
    if (!referralStats) return;

    document.getElementById('my-referral-code').textContent = referralStats.referral_code || '--------';
    updateStat('referral-count', referralStats.total_referrals || 0);

    var itemsEl = document.getElementById('referral-items');
    var earnedParts = [];
    if (referralStats.money_earned > 0) earnedParts.push(formatMoney(referralStats.money_earned));
    if (referralStats.items_earned && referralStats.items_earned.length > 0) {
        earnedParts.push(formatItems(referralStats.items_earned));
    }
    itemsEl.textContent = earnedParts.length ? earnedParts.join(' + ') : 'None';

    setVisible(document.getElementById('btn-edit-code'), !referralStats.code_edited);

    // Don't reset the view while the user is editing their code
    var editPane = document.getElementById('referral-code-edit');
    if (!editPane.classList.contains('active-editing')) {
        document.getElementById('referral-code-display').classList.remove('hidden');
        editPane.classList.add('hidden');
    }

    if (referralStats.referred_by) {
        setVisible(document.getElementById('redeem-available'), false);
        setVisible(document.getElementById('redeem-used'), true);
        document.getElementById('referred-by-code').textContent = referralStats.referred_by;

        var pending = document.getElementById('care-package-pending');
        var ready = document.getElementById('care-package-ready');
        var claimed = document.getElementById('care-package-claimed');

        if (referralStats.care_package_claimed) {
            careClaimSecondsLeft = 0;
            setVisible(pending, false);
            setVisible(ready, false);
            setVisible(claimed, true);
        } else if (referralStats.claim_seconds_left > 0) {
            careClaimSecondsLeft = referralStats.claim_seconds_left;
            setVisible(pending, true);
            setVisible(ready, false);
            setVisible(claimed, false);
            renderCareClaimCountdown();
        } else {
            careClaimSecondsLeft = 0;
            setVisible(pending, false);
            setVisible(ready, true);
            setVisible(claimed, false);
            document.getElementById('btn-claim-care').disabled = false;
        }
    } else {
        setVisible(document.getElementById('redeem-available'), true);
        setVisible(document.getElementById('redeem-used'), false);
    }
}

// ============================================================================
// LEADERBOARD TAB
// ============================================================================

function getDisplayName(row) {
    return row.char_name || row.twitch_username || row.kick_username || (String(row.citizenid || '').substring(0, 8) + '...');
}

var TWITCH_ICON = '<svg class="twitch-icon" viewBox="0 0 24 24" fill="currentColor" width="12" height="12"><path d="M11.571 4.714h1.715v5.143H11.57zm4.715 0H18v5.143h-1.714zM6 0L1.714 4.286v15.428h5.143V24l4.286-4.286h3.428L22.286 12V0zm14.571 11.143l-3.428 3.428h-3.429l-3 3v-3H6.857V1.714h13.714Z"/></svg>';
var KICK_ICON = '<svg class="kick-icon" viewBox="0 0 24 24" fill="currentColor" width="12" height="12"><path d="M1.2 2.4h5.4v6.6L12 2.4h6.6l-6.6 7.8L18.6 21.6H12l-5.4-7.2v7.2H1.2z"/></svg>';

function getPlatformBadges(row) {
    var badges = '';
    if (row.twitch_username) {
        badges += ' <span class="twitch-badge" title="' + escapeHtml(row.twitch_username) + '">' + TWITCH_ICON + escapeHtml(row.twitch_username) + '</span>';
    }
    if (row.kick_username) {
        badges += ' <span class="kick-badge" title="' + escapeHtml(row.kick_username) + '">' + KICK_ICON + escapeHtml(row.kick_username) + '</span>';
    }
    return badges;
}

function getMetric(row, tab) {
    if (tab === 'stream') return { val: formatTime(row.total_stream_minutes), label: 'Stream' };
    if (tab === 'playtime') return { val: formatTime(row.playtime_minutes), label: 'Playtime' };
    if (tab === 'referrals') return { val: (row.total_referrals || 0).toString(), label: 'Referrals' };
    return { val: '—', label: '' };
}

function buildPodiumCard(row, pos, isSelf, tab) {
    var name = getDisplayName(row);
    var metric = getMetric(row, tab);
    var medalColors = { 1: '#ffd700', 2: '#c0c0c0', 3: '#cd7f32' };
    var medalIcons = { 1: '&#9733;', 2: '&#9734;', 3: '&#9734;' };
    var sizeClass = pos === 1 ? 'lb-podium-first' : '';
    var initial = (name.charAt(0) || '?').toUpperCase();

    var platformLines = '';
    if (row.twitch_username) {
        platformLines += '<div class="lb-podium-twitch">' + TWITCH_ICON + ' ' + escapeHtml(row.twitch_username) + '</div>';
    }
    if (row.kick_username) {
        platformLines += '<div class="lb-podium-kick">' + KICK_ICON + ' ' + escapeHtml(row.kick_username) + '</div>';
    }

    var livePlatform = row.live_platform || 'twitch';
    var kickClass = livePlatform === 'kick' ? ' kick' : '';
    var liveBadge = row.is_live ? '<div class="lb-live-badge podium' + kickClass + '">LIVE</div>' : '';

    return '<div class="lb-podium-card ' + sizeClass + (isSelf ? ' lb-row-self' : '') + '" data-cid="' + escapeHtml(row.citizenid) + '">'
        + '<div class="lb-podium-medal" style="color:' + medalColors[pos] + '">' + medalIcons[pos] + '</div>'
        + '<div class="lb-podium-avatar' + (row.is_live ? ' lb-avatar-live' + kickClass : '') + '" style="border-color:' + medalColors[pos] + '">'
        + (row.avatar_url ? avatarImg(row.avatar_url, initial) : escapeHtml(initial))
        + '</div>'
        + liveBadge
        + '<div class="lb-podium-name">' + escapeHtml(name) + '</div>'
        + platformLines
        + '<div class="lb-podium-stat">'
        + '<span class="lb-podium-val">' + metric.val + '</span>'
        + '<span class="lb-podium-lbl">' + metric.label + '</span>'
        + '</div>'
        + '</div>';
}

function buildLeaderboardRow(row, pos, isSelf, tab) {
    var name = getDisplayName(row);
    var metric = getMetric(row, tab);
    var initial = (name.charAt(0) || '?').toUpperCase();

    var livePlatform = row.live_platform || 'twitch';
    var kickClass = livePlatform === 'kick' ? ' kick' : '';
    var liveBadge = row.is_live ? ' <span class="lb-live-badge' + kickClass + '">LIVE</span>' : '';

    return '<div class="lb-row ' + (isSelf ? 'lb-row-self' : '') + '" data-cid="' + escapeHtml(row.citizenid) + '">'
        + '<div class="lb-pos">#' + pos + '</div>'
        + '<div class="lb-avatar' + (row.is_live ? ' lb-avatar-live' + kickClass : '') + '">'
        + (row.avatar_url ? avatarImg(row.avatar_url, initial) : escapeHtml(initial))
        + '</div>'
        + '<div class="lb-info">'
        + '<div class="lb-name">' + escapeHtml(name) + (isSelf ? ' <span class="you-tag">(You)</span>' : '') + liveBadge + getPlatformBadges(row) + '</div>'
        + '</div>'
        + '<div class="lb-xp">'
        + '<div class="lb-xp-val">' + metric.val + '</div>'
        + '<div class="lb-xp-label">' + metric.label + '</div>'
        + '</div>'
        + '</div>';
}

function renderLeaderboard() {
    var body = document.getElementById('leaderboard-body');
    var playerSection = document.getElementById('lb-player-row');
    var myCid = profile ? profile.citizenid : null;

    var entries = (leaderboard && leaderboard[activeLbTab]) || [];

    if (entries.length === 0) {
        body.innerHTML = '<div class="lb-empty">No data yet</div>';
        playerSection.classList.add('hidden');
        return;
    }

    lbPlayerCache = {};
    for (var e = 0; e < entries.length; e++) {
        lbPlayerCache[entries[e].citizenid] = entries[e];
    }

    var html = '';
    var playerInList = false;

    if (entries.length >= 3) {
        html += '<div class="lb-podium">';
        html += buildPodiumCard(entries[1], 2, entries[1].citizenid === myCid, activeLbTab);
        html += buildPodiumCard(entries[0], 1, entries[0].citizenid === myCid, activeLbTab);
        html += buildPodiumCard(entries[2], 3, entries[2].citizenid === myCid, activeLbTab);
        html += '</div>';
    }

    var startIdx = entries.length >= 3 ? 3 : 0;
    if (startIdx < entries.length) {
        html += '<div class="lb-list">';
        for (var i = startIdx; i < entries.length; i++) {
            html += buildLeaderboardRow(entries[i], i + 1, entries[i].citizenid === myCid, activeLbTab);
        }
        html += '</div>';
    }

    for (var j = 0; j < entries.length; j++) {
        if (entries[j].citizenid === myCid) playerInList = true;
    }

    body.innerHTML = html;

    // Show the player's own position below the list if they are not in it
    var myRank = leaderboard.myRanks && leaderboard.myRanks[activeLbTab];
    if (myCid && !playerInList && profile && myRank) {
        var selfRow = {
            citizenid: myCid,
            twitch_username: profile.twitch_username,
            kick_username: profile.kick_username,
            char_name: profile.char_name,
            avatar_url: profile.avatar_url,
            total_stream_minutes: profile.total_stream_minutes || 0,
            playtime_minutes: profile.playtime_minutes || 0,
            total_referrals: (referralStats && referralStats.total_referrals) || profile.total_referrals || 0,
        };
        lbPlayerCache[myCid] = selfRow;
        playerSection.classList.remove('hidden');
        playerSection.innerHTML = '<div class="lb-divider"><span>Your Position</span></div>'
            + buildLeaderboardRow(selfRow, myRank, true, activeLbTab);
    } else {
        playerSection.classList.add('hidden');
    }
}

// ============================================================================
// REWARDS TAB
// ============================================================================

function renderTracker(key, reward, current, unitLabel, remainingSuffix) {
    if (!reward || !(reward.interval > 0)) {
        setVisible(document.getElementById('reward-tracker-' + key), false);
        return;
    }
    setVisible(document.getElementById('reward-tracker-' + key), true);

    var interval = reward.interval;
    var into = (current || 0) % interval;
    var left = interval - into;
    var pct = Math.round((into / interval) * 100);

    document.getElementById('reward-' + key + '-sub').textContent = 'Every ' + interval + ' ' + unitLabel;
    document.getElementById('reward-' + key + '-prize').textContent = formatRewardPrize(reward);
    document.getElementById('reward-' + key + '-fill').style.width = pct + '%';
    document.getElementById('reward-' + key + '-remaining').textContent = left + ' ' + remainingSuffix;
}

function renderRewardTrackers() {
    if (!profile || !configData) return;

    renderTracker('stream', configData.streamReward, profile.total_stream_minutes, 'min streamed', 'min to go');
    renderTracker('playtime', configData.playtimeReward, profile.playtime_minutes, 'min played', 'min to go');
    renderTracker('refplaytime', configData.referralPlaytimeReward, profile.referral_playtime_earned, 'min your referrals play', 'min to go');

    var referrals = (referralStats && referralStats.total_referrals) || profile.total_referrals || 0;
    renderTracker('referral', configData.referralReward, referrals, 'referrals', 'more needed');
}

function renderRewardHistory() {
    var container = document.getElementById('reward-history');
    if (!container) return;

    if (!rewardHistory || rewardHistory.length === 0) {
        container.innerHTML = '<div class="lb-empty">No rewards yet</div>';
        return;
    }

    var iconMap = {
        'level_up': '&#9733;',
        'care_package': '&#127873;',
        'referral_reward': '&#127381;',
        'leaderboard_reward': '&#127942;',
    };
    var colorMap = {
        'level_up': 'var(--accent-bright)',
        'care_package': 'var(--green)',
        'referral_reward': 'var(--gold)',
        'leaderboard_reward': '#f472b6',
    };

    var html = '';
    rewardHistory.forEach(function (ev) {
        var icon = iconMap[ev.event_type] || '&#9679;';
        var color = colorMap[ev.event_type] || 'var(--text-muted)';
        html += '<div class="reward-history-row">'
            + '<div class="reward-history-icon" style="color:' + color + '">' + icon + '</div>'
            + '<div class="reward-history-info">'
            + '<div class="reward-history-text">' + escapeHtml(ev.value || '') + '</div>'
            + '<div class="reward-history-date">' + escapeHtml(ev.created_at || '') + '</div>'
            + '</div>'
            + '</div>';
    });

    container.innerHTML = html;
}

// ============================================================================
// COUNTDOWN TIMERS
// ============================================================================

function pad(n) { return n < 10 ? '0' + n : '' + n; }

function formatCountdown(seconds) {
    if (seconds <= 0) return '00:00';
    var h = Math.floor(seconds / 3600);
    var m = Math.floor((seconds % 3600) / 60);
    var s = seconds % 60;
    if (h > 0) return h + ':' + pad(m) + ':' + pad(s);
    return m + ':' + pad(s);
}

function renderCareClaimCountdown() {
    var el = document.getElementById('care-claim-timer');
    if (el) el.textContent = formatCountdown(careClaimSecondsLeft);
}

function startCountdownTick() {
    stopCountdownTick();
    countdownInterval = setInterval(function () {
        if (careClaimSecondsLeft > 0) {
            careClaimSecondsLeft--;
            renderCareClaimCountdown();
            if (careClaimSecondsLeft <= 0) {
                setVisible(document.getElementById('care-package-pending'), false);
                setVisible(document.getElementById('care-package-ready'), true);
            }
        }
    }, 1000);
}

function stopCountdownTick() {
    if (countdownInterval) {
        clearInterval(countdownInterval);
        countdownInterval = null;
    }
}

// ============================================================================
// EVENT HANDLERS
// ============================================================================

document.getElementById('btn-close').addEventListener('click', closePanel);

/** Wires a button to a NUI callback; disables it while the request is in flight. */
function bindAction(buttonId, callbackName, getPayload, onResult) {
    var btn = document.getElementById(buttonId);
    btn.addEventListener('click', function () {
        var payload = getPayload ? getPayload() : {};
        if (payload === null) return; // validation failed
        btn.disabled = true;
        nuiCallback(callbackName, payload).then(function (result) {
            btn.disabled = false;
            result = result || {};
            if (onResult) onResult(result);
            else showToast(result.message || (result.success ? 'Done.' : 'Failed.'), result.success ? 'success' : 'error');
        }).catch(function () {
            btn.disabled = false;
            showToast('Request failed.', 'error');
        });
    });
}

function bindEnter(inputId, buttonId) {
    document.getElementById(inputId).addEventListener('keydown', function (e) {
        if (e.key === 'Enter') { e.preventDefault(); document.getElementById(buttonId).click(); }
    });
}

// Avatar modal
document.getElementById('profile-avatar').addEventListener('click', function () {
    document.getElementById('avatar-modal').classList.remove('hidden');
    document.getElementById('input-avatar-url').value = (profile && profile.avatar_url) || '';
    document.getElementById('avatar-preview-wrap').classList.add('hidden');
});

document.getElementById('btn-cancel-avatar').addEventListener('click', function () {
    document.getElementById('avatar-modal').classList.add('hidden');
});

document.getElementById('input-avatar-url').addEventListener('input', function () {
    var url = this.value.trim();
    var preview = document.getElementById('avatar-preview-wrap');
    var img = document.getElementById('avatar-preview-img');
    if (url && /^https:\/\/.+/.test(url)) {
        img.onload = function () { preview.classList.remove('hidden'); };
        img.onerror = function () { preview.classList.add('hidden'); };
        img.src = url;
    } else {
        preview.classList.add('hidden');
    }
});

bindAction('btn-save-avatar', 'setAvatar', function () {
    return { url: document.getElementById('input-avatar-url').value.trim() };
}, function (result) {
    showToast(result.message || (result.success ? 'Avatar updated!' : 'Failed.'), result.success ? 'success' : 'error');
    if (result.success) document.getElementById('avatar-modal').classList.add('hidden');
});

bindAction('btn-remove-avatar', 'setAvatar', function () {
    return { url: '' };
}, function (result) {
    showToast(result.message || (result.success ? 'Avatar removed.' : 'Failed.'), result.success ? 'success' : 'error');
    if (result.success) document.getElementById('avatar-modal').classList.add('hidden');
});

// Twitch / Kick linking
bindAction('btn-link', 'linkTwitch', function () {
    var username = document.getElementById('input-twitch').value.trim();
    return username ? { username: username } : null;
}, function (result) {
    if (result.success) document.getElementById('input-twitch').value = '';
    showToast(result.message || (result.success ? 'Linked!' : 'Failed to link.'), result.success ? 'success' : 'error');
});
bindAction('btn-unlink', 'unlinkTwitch');
bindEnter('input-twitch', 'btn-link');

bindAction('btn-link-kick', 'linkKick', function () {
    var username = document.getElementById('input-kick').value.trim();
    return username ? { username: username } : null;
}, function (result) {
    if (result.success) document.getElementById('input-kick').value = '';
    showToast(result.message || (result.success ? 'Linked!' : 'Failed to link.'), result.success ? 'success' : 'error');
});
bindAction('btn-unlink-kick', 'unlinkKick');
bindEnter('input-kick', 'btn-link-kick');

// Referral code editing
document.getElementById('btn-edit-code').addEventListener('click', function () {
    if (referralStats && referralStats.code_edited) {
        showToast('Your code has already been customised. Contact server staff if you need it changed.', 'error');
        return;
    }
    document.getElementById('referral-code-display').classList.add('hidden');
    var editPane = document.getElementById('referral-code-edit');
    editPane.classList.remove('hidden');
    editPane.classList.add('active-editing');
    document.getElementById('input-custom-code').value = '';
    document.getElementById('input-custom-code').focus();
});

document.getElementById('btn-cancel-code').addEventListener('click', function () {
    document.getElementById('referral-code-display').classList.remove('hidden');
    var editPane = document.getElementById('referral-code-edit');
    editPane.classList.add('hidden');
    editPane.classList.remove('active-editing');
});

bindAction('btn-save-code', 'editReferralCode', function () {
    var code = document.getElementById('input-custom-code').value.trim().toUpperCase();
    return code ? { code: code } : null;
}, function (result) {
    document.getElementById('referral-code-edit').classList.remove('active-editing');
    showToast(result.message || (result.success ? 'Saved.' : 'Failed.'), result.success ? 'success' : 'error');
});
bindEnter('input-custom-code', 'btn-save-code');

document.getElementById('btn-copy-code').addEventListener('click', function () {
    const code = document.getElementById('my-referral-code').textContent;
    if (!code || code === '--------') return;
    const ta = document.createElement('textarea');
    ta.value = code;
    ta.style.cssText = 'position:fixed;opacity:0';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); showToast('Copied!', 'success'); }
    catch (e) { showToast('Code: ' + code, 'error'); }
    document.body.removeChild(ta);
});

// Redeem / claim
bindAction('btn-redeem', 'redeemCode', function () {
    var code = document.getElementById('input-referral').value.trim().toUpperCase();
    return code ? { code: code } : null;
}, function (result) {
    if (result.success) document.getElementById('input-referral').value = '';
    showToast(result.message || (result.success ? 'Redeemed!' : 'Failed.'), result.success ? 'success' : 'error');
});
bindEnter('input-referral', 'btn-redeem');

bindAction('btn-claim-care', 'claimCarePackage', null, function (result) {
    if (result.success) {
        showToast(result.message || 'Care package claimed!', 'success');
        setVisible(document.getElementById('care-package-ready'), false);
        setVisible(document.getElementById('care-package-claimed'), true);
        if (referralStats) referralStats.care_package_claimed = true;
    } else {
        showToast(result.message || 'Not ready yet.', 'error');
    }
});

// Leaderboard sub-tabs
document.querySelectorAll('.lb-subtab').forEach(function (btn) {
    btn.addEventListener('click', function () {
        document.querySelectorAll('.lb-subtab').forEach(function (b) { b.classList.remove('active'); });
        btn.classList.add('active');
        activeLbTab = btn.getAttribute('data-lb');
        renderLeaderboard();
    });
});

// ============================================================================
// PLAYER PREVIEW
// ============================================================================

function showPlayerPreview(cid) {
    var player = lbPlayerCache[cid];
    if (!player) return;

    var modal = document.getElementById('player-preview');
    var name = getDisplayName(player);
    var initial = (name.charAt(0) || '?').toUpperCase();

    var avatarImgEl = document.getElementById('preview-avatar-img');
    var avatarInitial = document.getElementById('preview-avatar-initial');
    if (player.avatar_url) {
        avatarImgEl.src = player.avatar_url;
        avatarImgEl.classList.remove('hidden');
        avatarInitial.classList.add('hidden');
    } else {
        avatarImgEl.classList.add('hidden');
        avatarInitial.classList.remove('hidden');
        avatarInitial.textContent = initial;
    }

    document.getElementById('preview-name').textContent = name;

    setVisible(document.getElementById('preview-twitch'), !!player.twitch_username);
    if (player.twitch_username) document.getElementById('preview-twitch-name').textContent = player.twitch_username;

    setVisible(document.getElementById('preview-kick'), !!player.kick_username);
    if (player.kick_username) document.getElementById('preview-kick-name').textContent = player.kick_username;

    // Live status + Watch button
    var liveEl = document.getElementById('preview-live');
    var watchBtn = document.getElementById('btn-watch-stream');
    var livePlatform = player.live_platform || 'twitch';
    var liveUsername = livePlatform === 'kick' ? player.kick_username : player.twitch_username;

    if (player.is_live && liveUsername) {
        liveEl.classList.remove('hidden');
        var kickClass = livePlatform === 'kick' ? ' kick' : '';
        document.getElementById('preview-live-dot').className = 'preview-live-dot' + kickClass;
        var liveLabel = document.getElementById('preview-live-label');
        liveLabel.className = 'preview-live-text' + kickClass;
        liveLabel.textContent = 'LIVE ON ' + livePlatform.toUpperCase();
        document.getElementById('preview-viewers').textContent = (player.viewer_count || 0) + ' viewers';
        watchBtn.classList.remove('hidden');
        watchBtn.setAttribute('data-username', liveUsername);
        watchBtn.setAttribute('data-url', (livePlatform === 'kick' ? 'https://kick.com/' : 'https://twitch.tv/') + encodeURIComponent(liveUsername));
    } else {
        liveEl.classList.add('hidden');
        watchBtn.classList.add('hidden');
    }

    document.getElementById('preview-stream').textContent = formatTime(player.total_stream_minutes);
    document.getElementById('preview-playtime').textContent = formatTime(player.playtime_minutes);
    document.getElementById('preview-referrals').textContent = player.total_referrals || 0;

    modal.classList.remove('hidden');
}

function closePlayerPreview() {
    document.getElementById('player-preview').classList.add('hidden');
}

document.getElementById('btn-close-preview').addEventListener('click', closePlayerPreview);

document.getElementById('btn-watch-stream').addEventListener('click', function (e) {
    e.stopPropagation();
    var url = this.getAttribute('data-url');
    if (!url) return;
    nuiCallback('watchStream', { url: url, username: this.getAttribute('data-username') || '' }).catch(function () {});
    if (typeof window.invokeNative === 'function') {
        window.invokeNative('openUrl', url);
    }
});

document.getElementById('player-preview').addEventListener('click', function (e) {
    if (e.target === this) closePlayerPreview();
});

function onLeaderboardClick(e) {
    var target = e.target.closest('[data-cid]');
    if (target) showPlayerPreview(target.getAttribute('data-cid'));
}
document.getElementById('leaderboard-body').addEventListener('click', onLeaderboardClick);
document.getElementById('lb-player-row').addEventListener('click', onLeaderboardClick);
