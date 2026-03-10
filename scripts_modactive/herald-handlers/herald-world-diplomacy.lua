--@ module=true

--[====[
herald-world-diplomacy
======================

Tags: dev

  Hybrid event+poll handler for civilisation diplomacy and warfare.

Event-driven: peace/agreements (diplomacy), tribute/takeover/destruction/
new leadership (warfare).
Poll-based: detects new WAR, BATTLE, RAID collections involving pinned
civs (warfare).
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local civ_pins = dfhack.reqscript('herald-civ-pins')

-- Dedup set keyed by event.id; cleared each poll cycle.
local announced_diplo = {}

-- Conquest dedup: keyed by "att_civ:site_id". When a detailed conquest event
-- (NEW_LEADER or DESTROYED) fires, it records here so TAKEN_OVER is suppressed.
local conquest_announced = {}

-- Collection IDs already seen; persistent until world unload.
local known_collections = {}

-- Helpers ---------------------------------------------------------------------

-- Translated entity name, or numeric fallback.
local function ent_name(entity_id)
    if not entity_id or entity_id < 0 then return 'an unknown civilisation' end
    local entity = df.historical_entity.find(entity_id)
    if not entity then return 'entity ' .. entity_id end
    local name = dfhack.translation.translateName(entity.name, true)
    return (name and name ~= '') and name or ('entity ' .. entity_id)
end

-- Returns (pinned_entity_id, other_entity_id, settings) if either src or dst
-- is a pinned civ, nil otherwise.
local function find_pinned_party(src, dst)
    local pinned_civs = civ_pins.get_pinned()
    if pinned_civs[src] then return src, dst, pinned_civs[src] end
    if pinned_civs[dst] then return dst, src, pinned_civs[dst] end
    return nil
end

-- Fires a diplomacy announcement if not already announced for this event.
local function fire_diplo(ev_id, msg, dprint)
    if announced_diplo[ev_id] then
        dprint('world-diplomacy: event %d already announced, skipping', ev_id)
        return
    end
    announced_diplo[ev_id] = true
    util.announce_diplomacy(msg)
end

-- Event handlers (diplomacy) --------------------------------------------------

local function handle_peace_accepted(ev, dprint)
    local src = util.safe_get(ev, 'source') or -1
    local dst = util.safe_get(ev, 'destination') or -1
    local pinned_id, other_id, settings = find_pinned_party(src, dst)
    if not pinned_id or not settings.diplomacy then return end
    fire_diplo(ev.id, ('%s has accepted peace with %s.'):format(
        ent_name(pinned_id), ent_name(other_id)), dprint)
end

local function handle_peace_rejected(ev, dprint)
    local src = util.safe_get(ev, 'source') or -1
    local dst = util.safe_get(ev, 'destination') or -1
    local pinned_id, other_id, settings = find_pinned_party(src, dst)
    if not pinned_id or not settings.diplomacy then return end
    if pinned_id == src then
        fire_diplo(ev.id, ('%s sought peace with %s - rejected.'):format(
            ent_name(pinned_id), ent_name(other_id)), dprint)
    else
        fire_diplo(ev.id, ('%s rejected peace sought by %s.'):format(
            ent_name(pinned_id), ent_name(other_id)), dprint)
    end
end

local function handle_agreement_concluded(ev, dprint)
    local src = util.safe_get(ev, 'source') or -1
    local dst = util.safe_get(ev, 'destination') or -1
    local pinned_id, other_id, settings = find_pinned_party(src, dst)
    if not pinned_id or not settings.diplomacy then return end
    fire_diplo(ev.id, ('%s concluded an agreement with %s.'):format(
        ent_name(pinned_id), ent_name(other_id)), dprint)
end

local function handle_agreement_made(ev, dprint)
    local src = util.safe_get(ev, 'source') or -1
    local dst = util.safe_get(ev, 'destination') or -1
    local pinned_id, other_id, settings = find_pinned_party(src, dst)
    if not pinned_id or not settings.diplomacy then return end
    fire_diplo(ev.id, ('%s formed an agreement with %s.'):format(
        ent_name(pinned_id), ent_name(other_id)), dprint)
end

local function handle_agreement_rejected(ev, dprint)
    local src = util.safe_get(ev, 'source') or -1
    local dst = util.safe_get(ev, 'destination') or -1
    local pinned_id, other_id, settings = find_pinned_party(src, dst)
    if not pinned_id or not settings.diplomacy then return end
    if pinned_id == src then
        fire_diplo(ev.id, ('%s proposed an agreement to %s - rejected.'):format(
            ent_name(pinned_id), ent_name(other_id)), dprint)
    else
        fire_diplo(ev.id, ('%s rejected an agreement proposed by %s.'):format(
            ent_name(pinned_id), ent_name(other_id)), dprint)
    end
end

-- Event handlers (warfare) ----------------------------------------------------

local function handle_tribute_forced(ev, dprint)
    -- Unverified struct; field names inferred from sibling war events
    local att = util.safe_get(ev, 'attacker_civ') or util.safe_get(ev, 'a_civ') or -1
    local def = util.safe_get(ev, 'defender_civ') or util.safe_get(ev, 'd_civ') or -1
    local pinned_id, other_id, settings = find_pinned_party(att, def)
    if not pinned_id or not settings.warfare then return end

    local site_id = util.safe_get(ev, 'site') or util.safe_get(ev, 'site_id')
    local site_str = site_id and site_id >= 0 and util.site_name(site_id)

    local msg
    if pinned_id == att then
        msg = ('%s forced tribute on %s'):format(ent_name(pinned_id), ent_name(other_id))
    else
        msg = ('%s was forced to pay tribute to %s'):format(ent_name(pinned_id), ent_name(other_id))
    end
    if site_str then msg = msg .. ' at ' .. site_str end
    msg = msg .. '.'

    dprint('world-diplomacy: tribute forced event %d - %s', ev.id, msg)
    util.announce_war(msg)
end

-- Helpers shared by conquest handlers.
local function conquest_key(att, site_id)
    return tostring(att) .. ':' .. tostring(site_id or -1)
end

local function resolve_leaders(ev)
    local leaders = util.safe_get(ev, 'new_leaders')
    if not leaders then return nil end
    local ok, n = pcall(function() return #leaders end)
    if not ok or n == 0 then return nil end
    local names = {}
    for i = 0, n - 1 do
        local ok2, hf_id = pcall(function() return leaders[i] end)
        if ok2 and hf_id and hf_id >= 0 then
            table.insert(names, util.hf_name(hf_id))
        end
    end
    return #names > 0 and table.concat(names, ', ') or nil
end

-- Most detail: conquered + installed new leadership.
local function handle_site_new_leader(ev, dprint)
    local att = util.safe_get(ev, 'attacker_civ') or -1
    local def = util.safe_get(ev, 'defender_civ') or util.safe_get(ev, 'site_civ') or -1
    local pinned_id, other_id, settings = find_pinned_party(att, def)
    if not pinned_id or not settings.warfare then return end

    local site_id = util.safe_get(ev, 'site')
    local site_str = site_id and site_id >= 0 and util.site_name(site_id)
    conquest_announced[conquest_key(att, site_id)] = true

    local leader_str = resolve_leaders(ev)
    local msg
    if pinned_id == att then
        msg = ('%s conquered %s and installed new leadership'):format(
            ent_name(pinned_id), site_str or 'a site')
    else
        msg = ('%s was conquered by %s who installed new leadership'):format(
            site_str or 'a site', ent_name(other_id))
    end
    if leader_str then msg = msg .. ': ' .. leader_str end
    msg = msg .. '.'

    dprint('world-diplomacy: site new leader event %d - %s', ev.id, msg)
    util.announce_war(msg)
end

-- Most detail: conquered + destroyed.
local function handle_site_destroyed(ev, dprint)
    local att = util.safe_get(ev, 'attacker_civ') or -1
    local def = util.safe_get(ev, 'defender_civ') or util.safe_get(ev, 'site_civ') or -1
    local pinned_id, other_id, settings = find_pinned_party(att, def)
    if not pinned_id or not settings.warfare then return end

    local site_id = util.safe_get(ev, 'site')
    local site_str = site_id and site_id >= 0 and util.site_name(site_id)
    conquest_announced[conquest_key(att, site_id)] = true

    local msg
    if pinned_id == att then
        msg = ('%s conquered and destroyed %s!'):format(
            ent_name(pinned_id), site_str or 'a site')
    else
        msg = ('%s was conquered and destroyed by %s!'):format(
            site_str or 'a site', ent_name(other_id))
    end

    dprint('world-diplomacy: site destroyed event %d - %s', ev.id, msg)
    util.announce_war(msg)
end

-- Fallback: plain conquest (suppressed if NEW_LEADER or DESTROYED already fired).
local function handle_site_taken_over(ev, dprint)
    local att = util.safe_get(ev, 'attacker_civ') or -1
    local def = util.safe_get(ev, 'defender_civ') or util.safe_get(ev, 'site_civ') or -1
    local pinned_id, other_id, settings = find_pinned_party(att, def)
    if not pinned_id or not settings.warfare then return end

    local site_id = util.safe_get(ev, 'site')
    if conquest_announced[conquest_key(att, site_id)] then
        dprint('world-diplomacy: site taken over event %d suppressed (detailed event already fired)', ev.id)
        return
    end

    local site_str = site_id and site_id >= 0 and util.site_name(site_id)
    local msg
    if pinned_id == att then
        msg = ('%s conquered %s from %s.'):format(
            ent_name(pinned_id), site_str or 'a site', ent_name(other_id))
    else
        msg = ('%s was conquered by %s.'):format(
            site_str or 'a site', ent_name(other_id))
    end

    dprint('world-diplomacy: site taken over event %d - %s', ev.id, msg)
    util.announce_war(msg)
end

-- Dispatch table keyed by history_event_type enum value.
local dispatch = {}

local function register_dispatch()
    local T = df.history_event_type
    local map = {
        {T.WAR_PEACE_ACCEPTED,          handle_peace_accepted},
        {T.WAR_PEACE_REJECTED,          handle_peace_rejected},
        {T.TOPICAGREEMENT_CONCLUDED,    handle_agreement_concluded},
        {T.TOPICAGREEMENT_MADE,         handle_agreement_made},
        {T.TOPICAGREEMENT_REJECTED,     handle_agreement_rejected},
        {T.WAR_SITE_TRIBUTE_FORCED,     handle_tribute_forced},
        {T.WAR_SITE_TAKEN_OVER,         handle_site_taken_over},
        {T.WAR_SITE_NEW_LEADER,         handle_site_new_leader},
        {T.WAR_DESTROYED_SITE,          handle_site_destroyed},
    }
    for _, entry in ipairs(map) do
        if entry[1] then dispatch[entry[1]] = entry[2] end
    end
end

-- Collection polling (warfare) ------------------------------------------------

-- Collection type enum cache.
local CT = {}
do
    for _, name in ipairs({'WAR', 'BATTLE', 'RAID'}) do
        local ok, v = pcall(function()
            return df.history_event_collection_type[name]
        end)
        if ok and v ~= nil then CT[name] = v end
    end
end

-- Check direct civ vectors (attacker_civ/defender_civ) for a pinned civ.
-- Returns (pinned_id, other_id, settings, is_attacker) or nil.
local function check_direct_civ_vecs(col, att_field, def_field)
    local pinned_civs = civ_pins.get_pinned()
    local ok_a, att_vec = pcall(function() return col[att_field] end)
    local ok_d, def_vec = pcall(function() return col[def_field] end)

    -- Check attacker side
    if ok_a and att_vec then
        local ok_n, n = pcall(function() return #att_vec end)
        if ok_n then
            for i = 0, n - 1 do
                local ok2, cid = pcall(function() return att_vec[i] end)
                if ok2 and pinned_civs[cid] then
                    -- Resolve opponent from defender side
                    local opp_id = -1
                    if ok_d and def_vec then
                        local ok3, m = pcall(function() return #def_vec end)
                        if ok3 and m > 0 then
                            local ok4, did = pcall(function() return def_vec[0] end)
                            if ok4 then opp_id = did end
                        end
                    end
                    return cid, opp_id, pinned_civs[cid], true
                end
            end
        end
    end

    -- Check defender side
    if ok_d and def_vec then
        local ok_n, n = pcall(function() return #def_vec end)
        if ok_n then
            for i = 0, n - 1 do
                local ok2, cid = pcall(function() return def_vec[i] end)
                if ok2 and pinned_civs[cid] then
                    -- Resolve opponent from attacker side
                    local opp_id = -1
                    if ok_a and att_vec then
                        local ok3, m = pcall(function() return #att_vec end)
                        if ok3 and m > 0 then
                            local ok4, aid = pcall(function() return att_vec[0] end)
                            if ok4 then opp_id = aid end
                        end
                    end
                    return cid, opp_id, pinned_civs[cid], false
                end
            end
        end
    end

    return nil
end

-- Sum a squad deaths vector.
local function sum_squad_vec(col, field)
    local ok_v, vec = pcall(function() return col[field] end)
    if not ok_v or not vec then return 0 end
    local ok_n, n = pcall(function() return #vec end)
    if not ok_n then return 0 end
    local total = 0
    for i = 0, n - 1 do
        local ok2, v = pcall(function() return vec[i] end)
        if ok2 and v > 0 then total = total + v end
    end
    return total
end

-- Translated collection name, or nil.
local function col_name(col)
    local ok, name = pcall(function()
        return dfhack.translation.translateName(col.name, true)
    end)
    return (ok and name and name ~= '') and name or nil
end

-- Get the parent WAR collection's name for a battle/raid.
local function parent_war_name(col)
    local ok, pid = pcall(function() return col.parent_collection end)
    if not ok or not pid or pid < 0 then return nil end
    local parent = df.history_event_collection.find(pid)
    if not parent then return nil end
    return col_name(parent)
end

local function handle_war_collection(col, dprint)
    local pinned_id, opp_id, settings, is_attacker =
        check_direct_civ_vecs(col, 'attacker_civ', 'defender_civ')
    if not pinned_id or not settings.warfare then return end

    local war_name = col_name(col)
    local msg
    if is_attacker then
        msg = ('%s has declared war on %s'):format(
            ent_name(pinned_id), ent_name(opp_id))
    else
        msg = ('%s has been attacked by %s'):format(
            ent_name(pinned_id), ent_name(opp_id))
    end
    if war_name then msg = msg .. ' - ' .. war_name .. '!' else msg = msg .. '!' end

    dprint('world-diplomacy: WAR collection %d - %s', col.id, msg)
    util.announce_war(msg)
end

local function handle_battle_collection(col, dprint)
    local pinned_civs = civ_pins.get_pinned()
    local ep_map = util.get_entpop_to_civ()

    -- BATTLE uses squad entity_pop vectors, not direct civ vectors
    local focal_id, focal_settings, is_attacker
    for civ_id, settings in pairs(pinned_civs) do
        if settings.warfare then
            if util.entpop_vec_has_civ(col, 'attacker_squad_entity_pop', civ_id, ep_map) then
                focal_id, focal_settings, is_attacker = civ_id, settings, true
                break
            end
            if util.entpop_vec_has_civ(col, 'defender_squad_entity_pops', civ_id, ep_map) then
                focal_id, focal_settings, is_attacker = civ_id, settings, false
                break
            end
        end
    end
    if not focal_id then return end

    -- Casualty counts
    local att_deaths = sum_squad_vec(col, 'attacker_squad_deaths')
    local def_deaths = sum_squad_vec(col, 'defender_squad_deaths')
    local killed = is_attacker and def_deaths or att_deaths
    local lost   = is_attacker and att_deaths or def_deaths

    -- Resolve opponent from opposite side
    local opp_field = is_attacker and 'defender_squad_entity_pops' or 'attacker_squad_entity_pop'
    local opp_name
    local ok_v, vec = pcall(function() return col[opp_field] end)
    if ok_v and vec then
        local ok_n, n = pcall(function() return #vec end)
        if ok_n and n > 0 then
            local ok2, epid = pcall(function() return vec[0] end)
            if ok2 then
                local opp_civ_id = ep_map[epid]
                if opp_civ_id then opp_name = ent_name(opp_civ_id) end
            end
        end
    end
    opp_name = opp_name or 'unknown forces'

    -- Site name
    local site_str
    local ok_s, site_id = pcall(function() return col.site end)
    if ok_s and site_id and site_id >= 0 then
        site_str = util.site_name(site_id)
    end

    -- Build message
    local msg = 'Battle'
    if site_str then msg = msg .. ' at ' .. site_str end
    msg = msg .. (' - %s vs %s (killed %d, lost %d)'):format(
        ent_name(focal_id), opp_name, killed, lost)

    local war = parent_war_name(col)
    if war then msg = msg .. ' - part of ' .. war end

    dprint('world-diplomacy: BATTLE collection %d - %s', col.id, msg)
    util.announce_war(msg)
end

local function handle_raid_collection(col, dprint)
    local pinned_civs = civ_pins.get_pinned()
    -- RAID uses a scalar attacking_entity (or attacker_civ fallback)
    local ok_ae, att_eid = pcall(function() return col.attacking_entity end)
    if not ok_ae or not att_eid or att_eid < 0 then
        local ok2, v = pcall(function() return col.attacker_civ end)
        if ok2 and v and v >= 0 then att_eid = v else att_eid = nil end
    end

    local ok_s, site_id = pcall(function() return col.site end)
    local def_civ = (ok_s and site_id) and util.site_owner_civ(site_id) or nil
    local site_str = (ok_s and site_id and site_id >= 0)
        and util.site_name(site_id) or 'a site'

    -- Check attacker side
    if att_eid and pinned_civs[att_eid] and pinned_civs[att_eid].warfare then
        local base = ('%s raided %s'):format(ent_name(att_eid), site_str)
        local war = parent_war_name(col)
        local msg = base .. (war and (' - part of ' .. war) or '') .. '!'
        dprint('world-diplomacy: RAID collection %d (attacker) - %s', col.id, msg)
        util.announce_war(msg)
        return
    end

    -- Check defender side via site ownership
    if def_civ and pinned_civs[def_civ] and pinned_civs[def_civ].warfare then
        local by = att_eid and (' by ' .. ent_name(att_eid)) or ''
        local base = ('%s was raided%s'):format(site_str, by)
        local war = parent_war_name(col)
        local msg = base .. (war and (' - part of ' .. war) or '') .. '!'
        dprint('world-diplomacy: RAID collection %d (defender) - %s', col.id, msg)
        util.announce_war(msg)
    end
end

-- Scan all collections for new WAR/BATTLE/RAID.
local function scan_collections(dprint)
    if not CT.WAR and not CT.BATTLE and not CT.RAID then return end

    local ok_all, all = pcall(function()
        return df.global.world.history.event_collections.all
    end)
    if not ok_all or not all then return end

    local new_count = 0
    for i = 0, #all - 1 do
        local ok2, col = pcall(function() return all[i] end)
        if not ok2 or not col then goto continue end

        if known_collections[col.id] then goto continue end

        local ok3, ct = pcall(function() return col:getType() end)
        if not ok3 then goto continue end

        if ct == CT.WAR then
            known_collections[col.id] = true
            new_count = new_count + 1
            handle_war_collection(col, dprint)
        elseif ct == CT.BATTLE then
            known_collections[col.id] = true
            new_count = new_count + 1
            handle_battle_collection(col, dprint)
        elseif ct == CT.RAID then
            known_collections[col.id] = true
            new_count = new_count + 1
            handle_raid_collection(col, dprint)
        end

        ::continue::
    end

    if new_count > 0 then
        dprint('world-diplomacy: scan_collections found %d new collection(s)', new_count)
    end
end

-- Contract fields -------------------------------------------------------------

local function build_event_types()
    local T = df.history_event_type
    local candidates = {
        T.WAR_PEACE_ACCEPTED,
        T.WAR_PEACE_REJECTED,
        T.TOPICAGREEMENT_CONCLUDED,
        T.TOPICAGREEMENT_MADE,
        T.TOPICAGREEMENT_REJECTED,
        T.WAR_SITE_TRIBUTE_FORCED,
        T.WAR_SITE_TAKEN_OVER,
        T.WAR_SITE_NEW_LEADER,
        T.WAR_DESTROYED_SITE,
    }
    local result = {}
    for _, et in ipairs(candidates) do
        if et then table.insert(result, et) end
    end
    return result
end

event_types = build_event_types()
polls = true

-- Baseline all existing collections at map load to prevent false positives.
local function baseline_collections(dprint)
    local ok_all, all = pcall(function()
        return df.global.world.history.event_collections.all
    end)
    if not ok_all or not all then return end

    local count = 0
    for i = 0, #all - 1 do
        local ok2, col = pcall(function() return all[i] end)
        if ok2 and col then
            local ok3, ct = pcall(function() return col:getType() end)
            if ok3 and (ct == CT.WAR or ct == CT.BATTLE or ct == CT.RAID) then
                known_collections[col.id] = true
                count = count + 1
            end
        end
    end
    dprint('world-diplomacy.init: baseline %d existing collections', count)
end

function init(dprint)
    register_dispatch()
    announced_diplo = {}
    conquest_announced = {}
    known_collections = {}
    baseline_collections(dprint)
    dprint('world-diplomacy: handler initialised')
end

function reset()
    announced_diplo = {}
    conquest_announced = {}
    known_collections = {}
end

function check_event(ev, dprint)
    local handler = dispatch[ev:getType()]
    if handler then
        handler(ev, dprint)
    end
end

function check_poll(dprint)
    announced_diplo = {}
    conquest_announced = {}
    scan_collections(dprint)
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
