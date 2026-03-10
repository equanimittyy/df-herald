--@ module=true

--[====[
herald-world-espionage
======================

Tags: dev

  Hybrid event+poll handler for civilisation espionage (theft and abduction).

Event-driven: ITEM_STOLEN, HIST_FIGURE_ABDUCTED/HF_ABDUCTED.
Poll-based: detects new THEFT, ABDUCTION collections involving pinned civs.
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local civ_pins = dfhack.reqscript('herald-civ-pins')

-- Dedup set keyed by event.id; cleared each poll cycle.
local announced_espionage = {}

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

-- Walk an HF's entity_links MEMBER links; return (civ_id, settings) if any
-- link matches a pinned civ. HFs have no civ_id field; must use entity_links.
local function hf_member_of_pinned(hf_id, pinned_civs)
    if not hf_id or hf_id < 0 then return nil end
    local hf = df.historical_figure.find(hf_id)
    if not hf then return nil end
    local ok, links = pcall(function() return hf.entity_links end)
    if not ok or not links then return nil end
    for i = 0, #links - 1 do
        local ok2, link = pcall(function() return links[i] end)
        if not ok2 or not link then goto continue end
        local ok3, lt = pcall(function() return link:getType() end)
        if not ok3 or lt ~= df.histfig_entity_link_type.MEMBER then goto continue end
        local ok4, eid = pcall(function() return link.entity_id end)
        if not ok4 or not eid or eid < 0 then goto continue end
        -- Check if the entity itself is a pinned civ
        if pinned_civs[eid] then return eid, pinned_civs[eid] end
        -- Check if its parent civ is pinned (entity may be a SiteGov)
        local ent = df.historical_entity.find(eid)
        if ent then
            local ok5, elinks = pcall(function() return ent.entity_links end)
            if ok5 and elinks then
                for j = 0, #elinks - 1 do
                    local ok6, elink = pcall(function() return elinks[j] end)
                    if ok6 and elink then
                        local ok7, tid = pcall(function() return elink.target end)
                        if ok7 and tid and pinned_civs[tid] then
                            return tid, pinned_civs[tid]
                        end
                    end
                end
            end
        end
        ::continue::
    end
    return nil
end

-- Fire an espionage announcement if not already announced for this event.
local function fire_espionage(ev_id, msg, dprint)
    if announced_espionage[ev_id] then
        dprint('world-espionage: event %d already announced, skipping', ev_id)
        return
    end
    announced_espionage[ev_id] = true
    util.announce_espionage(msg)
end

-- Event handlers --------------------------------------------------------------

local function handle_item_stolen(ev, dprint)
    local pinned_civs = civ_pins.get_pinned()
    local entity_id = util.safe_get(ev, 'entity') or -1
    local histfig = util.safe_get(ev, 'histfig') or -1
    local site_id = util.safe_get(ev, 'site') or -1
    local site_str = site_id >= 0 and util.site_name(site_id) or 'an unknown location'

    -- Defender side: victim entity directly pinned, or site owner pinned
    local def_civ, def_settings
    if entity_id >= 0 and pinned_civs[entity_id] then
        def_civ, def_settings = entity_id, pinned_civs[entity_id]
    else
        local owner = util.site_owner_civ(site_id)
        if owner and pinned_civs[owner] then
            def_civ, def_settings = owner, pinned_civs[owner]
        end
    end
    if def_civ and def_settings and def_settings.espionage then
        local msg = ('Theft reported in %s - %s was robbed!'):format(
            site_str, ent_name(def_civ))
        dprint('world-espionage: item_stolen event %d (defender) - %s', ev.id, msg)
        fire_espionage(ev.id, msg, dprint)
    end

    -- Attacker side: thief HF is member of a pinned civ
    local att_civ, att_settings = hf_member_of_pinned(histfig, pinned_civs)
    if att_civ and att_settings and att_settings.espionage then
        local msg = ('%s agents committed theft in %s!'):format(
            ent_name(att_civ), site_str)
        dprint('world-espionage: item_stolen event %d (attacker) - %s', ev.id, msg)
        fire_espionage(ev.id, msg, dprint)
    end
end

local function handle_abducted(ev, dprint)
    local pinned_civs = civ_pins.get_pinned()
    local target_hf = util.safe_get(ev, 'target') or -1
    local snatcher_hf = util.safe_get(ev, 'snatcher') or -1
    local site_id = util.safe_get(ev, 'site') or -1
    local site_str = site_id >= 0 and util.site_name(site_id) or 'an unknown location'
    local victim_name = target_hf >= 0 and util.hf_name(target_hf) or 'someone'

    -- Defender side: victim HF is member of a pinned civ, or site owner is pinned
    local def_civ, def_settings = hf_member_of_pinned(target_hf, pinned_civs)
    if not def_civ then
        local owner = util.site_owner_civ(site_id)
        if owner and pinned_civs[owner] then
            def_civ, def_settings = owner, pinned_civs[owner]
        end
    end
    if def_civ and def_settings and def_settings.espionage then
        local msg = ('%s was abducted from %s!'):format(victim_name, site_str)
        dprint('world-espionage: abducted event %d (defender) - %s', ev.id, msg)
        fire_espionage(ev.id, msg, dprint)
    end

    -- Attacker side: snatcher HF is member of a pinned civ
    local att_civ, att_settings = hf_member_of_pinned(snatcher_hf, pinned_civs)
    if att_civ and att_settings and att_settings.espionage then
        local msg = ('%s agents abducted %s from %s!'):format(
            ent_name(att_civ), victim_name, site_str)
        dprint('world-espionage: abducted event %d (attacker) - %s', ev.id, msg)
        fire_espionage(ev.id, msg, dprint)
    end
end

-- Dispatch table keyed by history_event_type enum value.
local dispatch = {}

local function register_dispatch()
    local T = df.history_event_type
    local map = {
        {T.ITEM_STOLEN, handle_item_stolen},
    }
    -- HIST_FIGURE_ABDUCTED or HF_ABDUCTED (name varies by DFHack version)
    local abducted_type = T.HIST_FIGURE_ABDUCTED or T.HF_ABDUCTED
    if abducted_type then
        table.insert(map, {abducted_type, handle_abducted})
    end
    for _, entry in ipairs(map) do
        if entry[1] then dispatch[entry[1]] = entry[2] end
    end
end

-- Collection polling ----------------------------------------------------------

-- Collection type enum cache.
local CT = {}
do
    for _, name in ipairs({'THEFT', 'ABDUCTION'}) do
        local ok, v = pcall(function()
            return df.history_event_collection_type[name]
        end)
        if ok and v ~= nil then CT[name] = v end
    end
end

local function handle_theft_collection(col, dprint)
    local pinned_civs = civ_pins.get_pinned()

    -- Attacker: scalar attacking_entity or attacker_civ
    local ok_ae, att_eid = pcall(function() return col.attacking_entity end)
    if not ok_ae or not att_eid or att_eid < 0 then
        local ok2, v = pcall(function() return col.attacker_civ end)
        if ok2 and v and v >= 0 then att_eid = v else att_eid = nil end
    end

    -- Defender: site owner
    local ok_s, site_id = pcall(function() return col.site end)
    local def_civ = (ok_s and site_id) and util.site_owner_civ(site_id) or nil
    local site_str = (ok_s and site_id and site_id >= 0)
        and util.site_name(site_id) or 'a site'

    -- Check attacker side
    if att_eid and pinned_civs[att_eid] and pinned_civs[att_eid].espionage then
        local msg = ('%s committed theft from %s!'):format(ent_name(att_eid), site_str)
        dprint('world-espionage: THEFT collection %d (attacker) - %s', col.id, msg)
        util.announce_espionage(msg)
        return
    end

    -- Check defender side via site ownership
    if def_civ and pinned_civs[def_civ] and pinned_civs[def_civ].espionage then
        local by = att_eid and (' by ' .. ent_name(att_eid)) or ''
        local msg = ('%s was robbed%s!'):format(site_str, by)
        dprint('world-espionage: THEFT collection %d (defender) - %s', col.id, msg)
        util.announce_espionage(msg)
    end
end

local function handle_abduction_collection(col, dprint)
    local pinned_civs = civ_pins.get_pinned()

    -- Attacker: scalar attacker_civ
    local att_civ = util.safe_get(col, 'attacker_civ')
    if att_civ and att_civ < 0 then att_civ = nil end

    -- Defender: site owner
    local site_id = util.safe_get(col, 'site')
    local def_civ = site_id and util.site_owner_civ(site_id) or nil
    local site_str = (site_id and site_id >= 0)
        and util.site_name(site_id) or 'a site'

    -- Victim name from victim_hf vector
    local victim_name
    local ok_v, vv = pcall(function() return col.victim_hf end)
    if ok_v and vv and #vv > 0 then
        local ok2, hf_id = pcall(function() return vv[0] end)
        if ok2 and hf_id and hf_id >= 0 then
            victim_name = util.hf_name(hf_id)
        end
    end

    -- Check attacker side
    if att_civ and pinned_civs[att_civ] and pinned_civs[att_civ].espionage then
        local msg = ('%s carried out abductions from %s!'):format(
            ent_name(att_civ), site_str)
        dprint('world-espionage: ABDUCTION collection %d (attacker) - %s', col.id, msg)
        util.announce_espionage(msg)
        return
    end

    -- Check defender side via site ownership
    if def_civ and pinned_civs[def_civ] and pinned_civs[def_civ].espionage then
        local msg
        if victim_name then
            msg = ('%s was abducted from %s!'):format(victim_name, site_str)
        else
            msg = ('Abductions reported at %s!'):format(site_str)
        end
        dprint('world-espionage: ABDUCTION collection %d (defender) - %s', col.id, msg)
        util.announce_espionage(msg)
    end
end

-- Scan all collections for new THEFT/ABDUCTION.
local function scan_collections(dprint)
    if not CT.THEFT and not CT.ABDUCTION then return end

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

        if ct == CT.THEFT then
            known_collections[col.id] = true
            new_count = new_count + 1
            handle_theft_collection(col, dprint)
        elseif ct == CT.ABDUCTION then
            known_collections[col.id] = true
            new_count = new_count + 1
            handle_abduction_collection(col, dprint)
        end

        ::continue::
    end

    if new_count > 0 then
        dprint('world-espionage: scan_collections found %d new collection(s)', new_count)
    end
end

-- Contract fields -------------------------------------------------------------

local function build_event_types()
    local T = df.history_event_type
    local result = {}
    if T.ITEM_STOLEN then table.insert(result, T.ITEM_STOLEN) end
    if T.HIST_FIGURE_ABDUCTED then
        table.insert(result, T.HIST_FIGURE_ABDUCTED)
    elseif T.HF_ABDUCTED then
        table.insert(result, T.HF_ABDUCTED)
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
            if ok3 and (ct == CT.THEFT or ct == CT.ABDUCTION) then
                known_collections[col.id] = true
                count = count + 1
            end
        end
    end
    dprint('world-espionage.init: baseline %d existing collections', count)
end

function init(dprint)
    register_dispatch()
    announced_espionage = {}
    known_collections = {}
    baseline_collections(dprint)
    dprint('world-espionage: handler initialised')
end

function reset()
    announced_espionage = {}
    known_collections = {}
end

function check_event(ev, dprint)
    local handler = dispatch[ev:getType()]
    if handler then
        handler(ev, dprint)
    end
end

function check_poll(dprint)
    announced_espionage = {}
    scan_collections(dprint)
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
