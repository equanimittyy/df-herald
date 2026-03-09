--@ module=true

--[====[
herald-ind-combat
=================

Tags: dev

  Event-driven handler for pinned individual combat events.

Fires announcements when a pinned HF is involved in battles, wounds,
site attacks/destructions, field battles, overthrows, or body abuse (as abuser).
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local pins = dfhack.reqscript('herald-pins')

-- Dedup set keyed by event.id; prevents duplicate announcements for
-- the same event when multiple pinned HFs are involved.
local announced_combat = {}

-- Fort-level combat tracking: baseline combat report counts per unit id.
-- { [unit_id] = last_seen_combat_count }
local combat_baselines = {}

-- Fort-level kill tracking: baseline kill counts per hf_id.
-- { [hf_id] = last_seen_kill_count }
local kill_baselines = {}

-- Fort-level wound tracking: baseline wound counts per unit id.
-- { [unit_id] = last_seen_wound_count }
local wound_baselines = {}

-- Helpers ---------------------------------------------------------------------

local function hf_name(hf_id)
    local hf = df.historical_figure.find(hf_id)
    return hf and dfhack.translation.translateName(hf.name, true) or tostring(hf_id)
end

local function site_name(site_id)
    if site_id < 0 then return 'an unknown site' end
    local site = df.world_site.find(site_id)
    if not site then return 'an unknown site' end
    local name = dfhack.translation.translateName(site.name, true)
    return (name and name ~= '') and name or ('site ' .. site_id)
end

-- Returns true if the settings table has combat announcements enabled.
local function combat_enabled(settings)
    return settings and settings.combat
end

-- Best-effort extraction of opponent name from the latest combat report.
-- Pattern: "The X verbs the Y..." - won't match all DF report formats.
local function parse_combatant(combat_log, count, hf_name_str)
    if count < 1 then return nil end
    local rep_id = combat_log[count - 1]
    if not rep_id then return nil end
    local ok_rep, rep = pcall(function() return df.report.find(rep_id) end)
    if not ok_rep or not rep then return nil end
    local ok_txt, txt = pcall(function() return rep.text end)
    if not ok_txt or not txt or txt == '' then return nil end
    local subj, obj = txt:match('^The (.+) %a+ the (.+)[,!.]')
    if not subj or not obj then return nil end
    local name_lower = hf_name_str:lower()
    if subj:lower():find(name_lower, 1, true) then
        return obj
    elseif obj:lower():find(name_lower, 1, true) then
        return subj
    end
    return nil
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

-- Fort-level poll: detect new combat reports on pinned HFs' units -----------

local function handle_poll(dprint)
    local ok, active = pcall(function() return df.global.world.units.active end)
    if not ok or not active then return end

    local pinned = pins.get_pinned()
    local pinned_count = 0
    for _ in pairs(pinned) do pinned_count = pinned_count + 1 end
    dprint('ind-combat.poll: scanning %d active units, %d pinned HFs', #active, pinned_count)

    local matched = 0
    for i = 0, #active - 1 do
        local unit = active[i]
        if not unit then goto continue end

        local ok_hf, hf_id = pcall(function() return unit.hist_figure_id end)
        if not ok_hf or not hf_id or hf_id < 0 then goto continue end
        if not pinned[hf_id] then goto continue end
        if not combat_enabled(pinned[hf_id]) then
            dprint('ind-combat.poll: hf %d pinned but combat disabled', hf_id)
            goto continue
        end
        matched = matched + 1

        -- Read combat report count
        local ok_log, combat_log = pcall(function() return unit.reports.log.Combat end)
        if not ok_log or not combat_log then goto continue end
        local count = #combat_log

        local combat_base = combat_baselines[unit.id]
        if not combat_base then
            -- First time seeing this unit; set baseline, don't announce
            combat_baselines[unit.id] = count
            goto continue
        end

        -- Capture old baseline before updating (used by wound-inflicted check)
        local old_combat_base = combat_base
        local has_new_reports = count > combat_base
        if has_new_reports then
            combat_baselines[unit.id] = count
        end

        -- 1. New combat engagement
        if has_new_reports then
            local name = hf_name(hf_id)
            local opponent = parse_combatant(combat_log, count, name)

            local msg
            if opponent then
                msg = ('%s is under attack by %s!'):format(name, opponent)
            else
                msg = ('%s is under attack!'):format(name)
            end
            dprint('ind-combat.poll: %s (unit %d, hf %d, %d new reports)',
                name, unit.id, hf_id, count - old_combat_base)
            util.announce_combat(msg)
        end

        -- 2. Pinned HF received wounds
        local ok_wounds, wounds = pcall(function() return unit.body.wounds end)
        if ok_wounds and wounds then
            local wound_count = #wounds
            local wound_base = wound_baselines[unit.id]
            if not wound_base then
                wound_baselines[unit.id] = wound_count
            elseif wound_count > wound_base then
                local name = hf_name(hf_id)
                wound_baselines[unit.id] = wound_count

                -- Try to identify attacker from the latest combat report
                local attacker = nil
                if ok_log and combat_log and #combat_log > 0 then
                    local rep_id = combat_log[#combat_log - 1]
                    if rep_id then
                        local ok_rep, rep = pcall(function() return df.report.find(rep_id) end)
                        if ok_rep and rep then
                            local ok_txt, txt = pcall(function() return rep.text end)
                            if ok_txt and txt and txt ~= '' then
                                local subj, obj = txt:match('^The (.+) %a+ the (.+)[,!.]')
                                if subj and obj and obj:lower():find(name:lower(), 1, true) then
                                    attacker = subj
                                end
                            end
                        end
                    end
                end

                local msg
                if attacker then
                    msg = ('%s has been wounded by %s!'):format(name, attacker)
                else
                    msg = ('%s has been wounded!'):format(name)
                end
                dprint('ind-combat.poll: %s wounded (unit %d, hf %d)', name, unit.id, hf_id)
                util.announce_combat(msg)
            end
        end

        -- 3. Pinned HF inflicted wounds on someone
        if has_new_reports then
            local name = hf_name(hf_id)
            local name_lower = name:lower()
            local wound_verbs = { 'tearing', 'bruising', 'fracturing',
                'shattering', 'breaking', 'severing', 'piercing',
                'gouging', 'smashing', 'denting', 'opening' }
            local announced_wound = false
            for ri = old_combat_base, count - 1 do
                if announced_wound then break end
                local rid = combat_log[ri]
                if not rid then goto next_rep end
                local ok_r, r = pcall(function() return df.report.find(rid) end)
                if not ok_r or not r then goto next_rep end
                local ok_t, txt = pcall(function() return r.text end)
                if not ok_t or not txt or txt == '' then goto next_rep end
                -- Check if pinned HF is the attacker and report describes a wound
                local subj, obj = txt:match('^The (.+) %a+ the (.+)[,!.]')
                if subj and obj and subj:lower():find(name_lower, 1, true) then
                    for _, verb in ipairs(wound_verbs) do
                        if txt:lower():find(verb, 1, true) then
                            local victim = obj:match('^(.-)%s+in%s+the') or obj
                            util.announce_combat(('%s has wounded %s!'):format(name, victim))
                            dprint('ind-combat.poll: %s wounded %s (unit %d, hf %d)',
                                name, victim, unit.id, hf_id)
                            announced_wound = true
                            break
                        end
                    end
                end
                ::next_rep::
            end
            -- Fallback: wound verbs found but couldn't parse victim
            if not announced_wound then
                for ri = old_combat_base, count - 1 do
                    if announced_wound then break end
                    local rid = combat_log[ri]
                    if not rid then goto next_rep2 end
                    local ok_r, r = pcall(function() return df.report.find(rid) end)
                    if not ok_r or not r then goto next_rep2 end
                    local ok_t, txt = pcall(function() return r.text end)
                    if not ok_t or not txt then goto next_rep2 end
                    for _, verb in ipairs(wound_verbs) do
                        if txt:lower():find(verb, 1, true) then
                            util.announce_combat(('%s has wounded a foe!'):format(name))
                            announced_wound = true
                            break
                        end
                    end
                    ::next_rep2::
                end
            end
        end

        -- Check fort-level kill count via hf.info.kills
        local hf = df.historical_figure.find(hf_id)
        if hf then
            local ok_kills, kills = pcall(function() return hf.info and hf.info.kills end)
            if ok_kills and kills then
                local ok_ev, ev_vec = pcall(function() return kills.events end)
                local ok_kc, kc_vec = pcall(function() return kills.killed_count end)
                local total = 0
                if ok_ev and ev_vec then total = total + #ev_vec end
                if ok_kc and kc_vec then
                    for ki = 0, #kc_vec - 1 do
                        local ok_n, n = pcall(function() return kc_vec[ki] end)
                        if ok_n and n then total = total + n end
                    end
                end

                local kill_base = kill_baselines[hf_id]
                if not kill_base then
                    kill_baselines[hf_id] = total
                elseif total > kill_base then
                    local name = hf_name(hf_id)
                    local new_kills = total - kill_base
                    kill_baselines[hf_id] = total

                    -- Try to get victim name from the latest kills.events entry
                    local victim_name = nil
                    if ok_ev and ev_vec and #ev_vec > 0 then
                        local last_ev_id = ev_vec[#ev_vec - 1]
                        local ok_de, de = pcall(function() return df.history_event.find(last_ev_id) end)
                        if ok_de and de then
                            local ok_vid, vid = pcall(function() return de.victim_hf end)
                            if ok_vid and vid and vid >= 0 then
                                victim_name = hf_name(vid)
                            end
                        end
                    end

                    -- Fallback: creature race name from killed_race vector
                    local creature_name = nil
                    if not victim_name then
                        local ok_kr, kr_vec = pcall(function() return kills.killed_race end)
                        if ok_kr and kr_vec and #kr_vec > 0 then
                            local race_id = kr_vec[#kr_vec - 1]
                            if race_id and race_id >= 0 then
                                local ok_rn, rn = pcall(function()
                                    return df.global.world.raws.creatures.all[race_id].name[0]
                                end)
                                if ok_rn and rn and rn ~= '' then
                                    creature_name = rn
                                end
                            end
                        end
                    end

                    local msg
                    if victim_name then
                        msg = ('%s has claimed the life of %s!'):format(name, victim_name)
                    elseif creature_name then
                        msg = ('%s has claimed the life of a %s!'):format(name, creature_name)
                    else
                        msg = ('%s has claimed a life!'):format(name)
                    end
                    dprint('ind-combat.poll: kill by %s (hf %d, %d new kill%s)',
                        name, hf_id, new_kills, new_kills > 1 and 's' or '')
                    util.announce_combat(msg)
                end
            end
        end

        ::continue::
    end

    -- Prune baselines for units no longer on the active list
    local active_ids = {}
    for i = 0, #active - 1 do
        local u = active[i]
        if u then active_ids[u.id] = true end
    end
    for uid in pairs(combat_baselines) do
        if not active_ids[uid] then combat_baselines[uid] = nil end
    end
    for uid in pairs(wound_baselines) do
        if not active_ids[uid] then wound_baselines[uid] = nil end
    end

    dprint('ind-combat.poll: matched %d pinned unit(s) on map', matched)
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

function init(dprint)
    register_dispatch()
    pins.load_pinned()
    combat_baselines = {}
    kill_baselines = {}
    wound_baselines = {}
    dprint('ind-combat: handler initialised')
end

function reset()
    announced_combat = {}
    combat_baselines = {}
    kill_baselines = {}
    wound_baselines = {}
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
