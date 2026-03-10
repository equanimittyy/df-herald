--@ module=true

--[====[
herald-ind-combat
=================

Tags: dev

  Hybrid event+poll handler for pinned individual combat events.

Event-driven: fires when a pinned HF is involved in battles, wounds,
site attacks/destructions, field battles, overthrows, or body abuse
(world history events).
Poll: detects fort-level kills by pinned HFs via hf.info.kills baseline.
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local pins = dfhack.reqscript('herald-pins')

-- Dedup set keyed by event.id; prevents duplicate announcements for
-- the same event when multiple pinned HFs are involved.
local announced_combat = {}

-- Fort-level kill tracking: baseline kill counts per hf_id.
-- { [hf_id] = last_seen_kill_count }
local kill_baselines = {}

-- Helpers ---------------------------------------------------------------------

local function hf_name(hf_id)
    return util.hf_name(hf_id)
end

local site_name = util.site_name

-- Returns true if the settings table has combat announcements enabled.
local function combat_enabled(settings)
    return settings and settings.combat
end

-- Fires a combat announcement if not already announced for this event.
local function fire(ev_id, msg, dprint)
    if announced_combat[ev_id] then
        dprint('ind-combat: event %d already announced, skipping', ev_id)
        return
    end
    announced_combat[ev_id] = true
    util.announce_combat(msg)
end

-- Event handlers by type ------------------------------------------------------

local function handle_simple_battle(ev, dprint)
    local pinned = pins.get_pinned()
    local group1 = ev.group1_hfid
    local group2 = ev.group2_hfid
    -- Check both sides
    for i = 0, #group1 - 1 do
        local hf_id = group1[i]
        if pinned[hf_id] and combat_enabled(pinned[hf_id]) then
            local other = #group2 > 0 and hf_name(group2[0]) or nil
            local msg = other
                and ('%s fought with %s.'):format(hf_name(hf_id), other)
                or  ('%s was involved in a battle.'):format(hf_name(hf_id))
            fire(ev.id, msg, dprint)
            return
        end
    end
    for i = 0, #group2 - 1 do
        local hf_id = group2[i]
        if pinned[hf_id] and combat_enabled(pinned[hf_id]) then
            local other = #group1 > 0 and hf_name(group1[0]) or nil
            local msg = other
                and ('%s fought with %s.'):format(hf_name(hf_id), other)
                or  ('%s was involved in a battle.'):format(hf_name(hf_id))
            fire(ev.id, msg, dprint)
            return
        end
    end
end

local function handle_wounded(ev, dprint)
    local pinned = pins.get_pinned()
    -- Field names vary by alias; use safe_get for robustness.
    local woundee = util.safe_get(ev, 'woundee_hfid') or util.safe_get(ev, 'woundee') or -1
    local wounder = util.safe_get(ev, 'wounder_hfid') or util.safe_get(ev, 'wounder') or -1
    if pinned[woundee] and combat_enabled(pinned[woundee]) then
        fire(ev.id, ('%s was wounded.'):format(hf_name(woundee)), dprint)
    elseif pinned[wounder] and combat_enabled(pinned[wounder]) then
        fire(ev.id, ('%s wounded %s.'):format(hf_name(wounder), hf_name(woundee)), dprint)
    end
end

local function handle_attacked_site(ev, dprint)
    local pinned = pins.get_pinned()
    local attacker = util.safe_get(ev, 'attacker_hf') or -1
    if pinned[attacker] and combat_enabled(pinned[attacker]) then
        local site = site_name(util.safe_get(ev, 'site') or util.safe_get(ev, 'target_site_id') or -1)
        fire(ev.id, ('%s attacked %s.'):format(hf_name(attacker), site), dprint)
    end
end

local function handle_destroyed_site(ev, dprint)
    local pinned = pins.get_pinned()
    local attacker = util.safe_get(ev, 'attacker_hf') or -1
    if pinned[attacker] and combat_enabled(pinned[attacker]) then
        local site = site_name(util.safe_get(ev, 'site') or util.safe_get(ev, 'target_site_id') or -1)
        fire(ev.id, ('%s destroyed %s.'):format(hf_name(attacker), site), dprint)
    end
end

local function handle_war_field_battle(ev, dprint)
    local pinned = pins.get_pinned()
    local att_gen = util.safe_get(ev, 'attacker_general_hf') or -1
    local def_gen = util.safe_get(ev, 'defender_general_hf') or -1
    if pinned[att_gen] and combat_enabled(pinned[att_gen]) then
        fire(ev.id, ('%s led forces in battle.'):format(hf_name(att_gen)), dprint)
    elseif pinned[def_gen] and combat_enabled(pinned[def_gen]) then
        fire(ev.id, ('%s led forces in battle.'):format(hf_name(def_gen)), dprint)
    end
end

local function handle_war_attacked_site(ev, dprint)
    local pinned = pins.get_pinned()
    local att_gen = util.safe_get(ev, 'attacker_general_hf') or -1
    local def_gen = util.safe_get(ev, 'defender_general_hf') or -1
    local att_hf  = util.safe_get(ev, 'attacker_hf') or -1
    local site_id = util.safe_get(ev, 'site') or util.safe_get(ev, 'target_site_id') or -1
    if pinned[att_gen] and combat_enabled(pinned[att_gen]) then
        fire(ev.id, ('%s led an attack on %s.'):format(hf_name(att_gen), site_name(site_id)), dprint)
    elseif pinned[att_hf] and combat_enabled(pinned[att_hf]) then
        fire(ev.id, ('%s led an attack on %s.'):format(hf_name(att_hf), site_name(site_id)), dprint)
    elseif pinned[def_gen] and combat_enabled(pinned[def_gen]) then
        fire(ev.id, ('%s defended %s.'):format(hf_name(def_gen), site_name(site_id)), dprint)
    end
end

local function handle_body_abused(ev, dprint)
    -- Only announce if the pinned HF is the abuser (histfig field).
    -- Victim path (pinned HF in bodies vec) is handled by ind-death.
    local pinned = pins.get_pinned()
    local abuser = util.safe_get(ev, 'histfig') or -1
    if pinned[abuser] and combat_enabled(pinned[abuser]) then
        fire(ev.id, ('%s desecrated a corpse.'):format(hf_name(abuser)), dprint)
    end
end

local function handle_hf_died_as_kill(ev, dprint)
    -- Announce when a pinned HF is the slayer (not the victim - that's ind-death).
    local pinned = pins.get_pinned()
    local slayer = util.safe_get(ev, 'slayer_hf') or -1
    if slayer < 0 then return end
    if not pinned[slayer] or not combat_enabled(pinned[slayer]) then return end
    local victim = util.safe_get(ev, 'victim_hf') or -1
    local victim_name = victim >= 0 and hf_name(victim) or 'an unknown foe'
    fire(ev.id, ('%s has slain %s!'):format(hf_name(slayer), victim_name), dprint)
end

local function handle_entity_overthrown(ev, dprint)
    local pinned = pins.get_pinned()
    local overthrown = util.safe_get(ev, 'overthrown_hf') or -1
    local taker      = util.safe_get(ev, 'position_taker_hf') or -1
    local instigator = util.safe_get(ev, 'instigator_hf') or -1
    if pinned[overthrown] and combat_enabled(pinned[overthrown]) then
        fire(ev.id, ('%s was overthrown.'):format(hf_name(overthrown)), dprint)
    elseif pinned[taker] and combat_enabled(pinned[taker]) then
        fire(ev.id, ('%s seized power.'):format(hf_name(taker)), dprint)
    elseif pinned[instigator] and combat_enabled(pinned[instigator]) then
        fire(ev.id, ('%s instigated an overthrow.'):format(hf_name(instigator)), dprint)
    end
end

-- Dispatch table keyed by history_event_type enum value.
local dispatch = {}

local function register_dispatch()
    local T = df.history_event_type
    local map = {
        {T.HF_SIMPLE_BATTLE_EVENT,         handle_simple_battle},
        {T.HIST_FIGURE_SIMPLE_BATTLE_EVENT, handle_simple_battle},
        {T.HIST_FIGURE_WOUNDED,             handle_wounded},
        {T.HF_WOUNDED,                      handle_wounded},
        {T.HF_ATTACKED_SITE,                handle_attacked_site},
        {T.HF_DESTROYED_SITE,               handle_destroyed_site},
        {T.WAR_FIELD_BATTLE,                handle_war_field_battle},
        {T.WAR_ATTACKED_SITE,               handle_war_attacked_site},
        {T.BODY_ABUSED,                     handle_body_abused},
        {T.ENTITY_OVERTHROWN,               handle_entity_overthrown},
        {T.HIST_FIGURE_DIED,                handle_hf_died_as_kill},
    }
    for _, entry in ipairs(map) do
        if entry[1] then dispatch[entry[1]] = entry[2] end
    end
end

-- Fort-level poll: detect kills by pinned HFs on the active map -------------

-- Builds { [race_id] = count } from the parallel killed_race/killed_count vectors.
local function build_kill_snapshot(kills)
    local snap = {}
    local ok_kr, kr = pcall(function() return kills.killed_race end)
    local ok_kc, kc = pcall(function() return kills.killed_count end)
    if not ok_kr or not kr or not ok_kc or not kc then return snap end
    for i = 0, #kr - 1 do
        local race_id = kr[i]
        local ok_n, n = pcall(function() return kc[i] end)
        if ok_n and n and race_id then
            snap[race_id] = (snap[race_id] or 0) + n
        end
    end
    return snap
end

-- Returns singular, plural names for a creature race ID.
local function race_names(race_id)
    local ok, cr = pcall(function() return df.global.world.raws.creatures.all[race_id] end)
    if not ok or not cr then return nil, nil end
    local ok_s, singular = pcall(function() return cr.name[0] end)
    local ok_p, plural   = pcall(function() return cr.name[1] end)
    return (ok_s and singular and singular ~= '') and singular or nil,
           (ok_p and plural and plural ~= '') and plural or nil
end

local function handle_poll(dprint)
    local pinned = pins.get_pinned()

    util.for_each_pinned_unit(pinned, function(unit, hf_id, settings)
        if not combat_enabled(settings) then return end

        local hf = df.historical_figure.find(hf_id)
        if not hf then return end

        local ok_kills, kills = pcall(function() return hf.info and hf.info.kills end)
        if not ok_kills or not kills then return end

        local snap = build_kill_snapshot(kills)
        local base = kill_baselines[hf_id]
        if not base then
            kill_baselines[hf_id] = snap
            return
        end

        -- Diff per-race counts
        for race_id, new_count in pairs(snap) do
            local old_count = base[race_id] or 0
            local delta = new_count - old_count
            if delta > 0 then
                local name = hf_name(hf_id)
                local singular, plural = race_names(race_id)
                local msg
                if delta == 1 then
                    msg = ('%s has claimed the life of a %s!'):format(
                        name, singular or 'foe')
                else
                    msg = ('%s has claimed the lives of %d %s!'):format(
                        name, delta, plural or singular or 'foes')
                end
                dprint('ind-combat.poll: KILL by %s (hf %d, +%d %s)',
                    name, hf_id, delta, singular or '?')
                util.announce_combat(msg)
            end
        end

        kill_baselines[hf_id] = snap
    end)

    -- Prune baselines for HFs no longer pinned
    for hfid in pairs(kill_baselines) do
        if not pinned[hfid] then kill_baselines[hfid] = nil end
    end
end

-- Contract fields -------------------------------------------------------------

-- Build event_types list; some enums may not exist in all DF versions,
-- so we filter nils.
local function build_event_types()
    local T = df.history_event_type
    local candidates = {
        T.HF_SIMPLE_BATTLE_EVENT,
        T.HIST_FIGURE_SIMPLE_BATTLE_EVENT,
        T.HIST_FIGURE_WOUNDED,
        T.HF_WOUNDED,
        T.HF_ATTACKED_SITE,
        T.HF_DESTROYED_SITE,
        T.WAR_FIELD_BATTLE,
        T.WAR_ATTACKED_SITE,
        T.BODY_ABUSED,
        T.ENTITY_OVERTHROWN,
        T.HIST_FIGURE_DIED,
    }
    local result = {}
    for _, et in ipairs(candidates) do
        if et then table.insert(result, et) end
    end
    return result
end

event_types = build_event_types()
polls = true

-- Set kill baselines immediately at map load so kills during the
-- init-to-first-poll gap aren't missed.  nil kills = 0 kills.
local function set_initial_baselines(dprint)
    util.for_each_pinned_unit(pins.get_pinned(), function(unit, hf_id, settings)
        if not combat_enabled(settings) then return end
        local hf = df.historical_figure.find(hf_id)
        if not hf then return end
        local ok_kills, kills = pcall(function() return hf.info and hf.info.kills end)
        if ok_kills and kills then
            kill_baselines[hf_id] = build_kill_snapshot(kills)
            dprint('ind-combat.init: baseline for hf %d (from kills)', hf_id)
        else
            kill_baselines[hf_id] = {}
            dprint('ind-combat.init: baseline for hf %d (empty, kills nil)', hf_id)
        end
    end)
end

function init(dprint)
    register_dispatch()
    announced_combat = {}
    kill_baselines = {}
    set_initial_baselines(dprint)
    dprint('ind-combat: handler initialised')
end

function reset()
    announced_combat = {}
    kill_baselines = {}
end

function check_event(ev, dprint)
    local handler = dispatch[ev:getType()]
    if handler then
        handler(ev, dprint)
    end
end

function check_poll(dprint)
    handle_poll(dprint)
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
