--@ module=true

--[====[
herald-world-diplomacy
======================

Tags: dev

  Hybrid event+poll handler for civilisation diplomacy and warfare.

Event-driven: peace acceptances/rejections and topic agreements between
pinned civs (gated by diplomacy setting).
Poll-based: detects new WAR, BATTLE, and SITE_CONQUERED collections
involving pinned civs (gated by warfare setting).
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local world_leaders = dfhack.reqscript('herald-handlers/herald-world-leaders')

-- Dedup set keyed by event.id; cleared each poll cycle.
local announced_diplo = {}

-- Collection IDs already seen; persistent until world unload.
local known_collections = {}

-- Lazy entity_population.id -> civ_id map; cleared on reset.
local entpop_to_civ = nil

-- Helpers ---------------------------------------------------------------------

local function build_entpop_map()
    entpop_to_civ = {}
    for _, ep in ipairs(df.global.world.entity_populations) do
        local cid = util.safe_get(ep, 'civ_id')
        if cid and cid >= 0 then entpop_to_civ[ep.id] = cid end
    end
end

local function get_entpop_map()
    if not entpop_to_civ then build_entpop_map() end
    return entpop_to_civ
end

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
    local pinned_civs = world_leaders.get_pinned_civs()
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
    }
    for _, entry in ipairs(map) do
        if entry[1] then dispatch[entry[1]] = entry[2] end
    end
end

-- Collection polling (warfare) ------------------------------------------------

-- Collection type enum cache.
local CT = {}
do
    for _, name in ipairs({'WAR', 'BATTLE', 'SITE_CONQUERED'}) do
        local ok, v = pcall(function()
            return df.history_event_collection_type[name]
        end)
        if ok and v ~= nil then CT[name] = v end
    end
end

-- Check if any entity_population in a squad vector belongs to civ_id.
local function entpop_vec_has_civ(col, field, civ_id, ep_map)
    local ok_v, vec = pcall(function() return col[field] end)
    if not ok_v or not vec then return false end
    local ok_n, n = pcall(function() return #vec end)
    if not ok_n then return false end
    for i = 0, n - 1 do
        local ok2, epid = pcall(function() return vec[i] end)
        if ok2 and ep_map[epid] == civ_id then return true end
    end
    return false
end

-- Check direct civ vectors (attacker_civ/defender_civ) for a pinned civ.
-- Returns (pinned_id, other_id, settings, is_attacker) or nil.
local function check_direct_civ_vecs(col, att_field, def_field)
    local pinned_civs = world_leaders.get_pinned_civs()
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

-- Get the parent WAR collection's name for a battle/site_conquered.
local function parent_war_name(col)
    local ok, pid = pcall(function() return col.parent_collection end)
    if not ok or not pid or pid < 0 then return nil end
    local ok2, all = pcall(function()
        return df.global.world.history.event_collections.all
    end)
    if not ok2 or not all then return nil end
    -- Search for the parent collection by ID
    for i = 0, #all - 1 do
        local ok3, parent = pcall(function() return all[i] end)
        if ok3 and parent and parent.id == pid then
            return col_name(parent)
        end
    end
    return nil
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
    local pinned_civs = world_leaders.get_pinned_civs()
    local ep_map = get_entpop_map()

    -- BATTLE uses squad entity_pop vectors, not direct civ vectors
    local focal_id, focal_settings, is_attacker
    for civ_id, settings in pairs(pinned_civs) do
        if settings.warfare then
            if entpop_vec_has_civ(col, 'attacker_squad_entity_pop', civ_id, ep_map) then
                focal_id, focal_settings, is_attacker = civ_id, settings, true
                break
            end
            if entpop_vec_has_civ(col, 'defender_squad_entity_pops', civ_id, ep_map) then
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

local function handle_site_conquered_collection(col, dprint)
    local pinned_id, opp_id, settings, is_attacker =
        check_direct_civ_vecs(col, 'attacker_civ', 'defender_civ')
    if not pinned_id or not settings.warfare then return end

    local ok_s, site_id = pcall(function() return col.site end)
    local site_str = (ok_s and site_id and site_id >= 0)
        and util.site_name(site_id) or 'a site'

    local msg
    if is_attacker then
        msg = ('%s conquered %s from %s!'):format(
            ent_name(pinned_id), site_str, ent_name(opp_id))
    else
        msg = ('%s conquered by %s!'):format(site_str, ent_name(opp_id))
    end

    dprint('world-diplomacy: SITE_CONQUERED collection %d - %s', col.id, msg)
    util.announce_war(msg)
end

-- Scan all collections for new WAR/BATTLE/SITE_CONQUERED.
local function scan_collections(dprint)
    if not CT.WAR and not CT.BATTLE and not CT.SITE_CONQUERED then return end

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
        elseif ct == CT.SITE_CONQUERED then
            known_collections[col.id] = true
            new_count = new_count + 1
            handle_site_conquered_collection(col, dprint)
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
            if ok3 and (ct == CT.WAR or ct == CT.BATTLE or ct == CT.SITE_CONQUERED) then
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
    known_collections = {}
    entpop_to_civ = nil
    baseline_collections(dprint)
    dprint('world-diplomacy: handler initialised')
end

function reset()
    announced_diplo = {}
    known_collections = {}
    entpop_to_civ = nil
end

function check_event(ev, dprint)
    local handler = dispatch[ev:getType()]
    if handler then
        handler(ev, dprint)
    end
end

function check_poll(dprint)
    announced_diplo = {}
    scan_collections(dprint)
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
