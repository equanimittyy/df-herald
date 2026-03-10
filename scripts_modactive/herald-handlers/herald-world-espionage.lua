--@ module=true

--[====[
herald-world-espionage
======================

Tags: dev

  Poll-based handler for civilisation espionage (theft and abduction).

Detects new THEFT and ABDUCTION collections involving pinned civs.
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local civ_pins = dfhack.reqscript('herald-civ-pins')

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

    local thief_civ = util.safe_get(col, 'thief_civ')
    if thief_civ and thief_civ < 0 then thief_civ = nil end
    local victim_civ = util.safe_get(col, 'victim_civ')
    if victim_civ and victim_civ < 0 then victim_civ = nil end

    local site_id = util.safe_get(col, 'site')
    local site_str = (site_id and site_id >= 0)
        and util.site_name(site_id) or 'a site'

    -- Check thief side
    if thief_civ and pinned_civs[thief_civ] and pinned_civs[thief_civ].espionage then
        local msg = ('%s carried out theft from %s!'):format(ent_name(thief_civ), site_str)
        dprint('world-espionage: THEFT collection %d (thief) - %s', col.id, msg)
        util.announce_espionage(msg)
        return
    end

    -- Check victim side
    if victim_civ and pinned_civs[victim_civ] and pinned_civs[victim_civ].espionage then
        local by = thief_civ and (' by ' .. ent_name(thief_civ)) or ''
        local msg = ('%s was robbed%s!'):format(site_str, by)
        dprint('world-espionage: THEFT collection %d (victim) - %s', col.id, msg)
        util.announce_espionage(msg)
    end
end

local function handle_abduction_collection(col, dprint)
    local pinned_civs = civ_pins.get_pinned()

    -- Attacker: scalar attacker_civ
    local att_civ = util.safe_get(col, 'attacker_civ')
    if att_civ and att_civ < 0 then att_civ = nil end

    -- Defender: direct field, fallback to site owner
    local def_civ = util.safe_get(col, 'defender_civ')
    if def_civ and def_civ < 0 then def_civ = nil end
    local site_id = util.safe_get(col, 'site')
    if not def_civ then
        def_civ = site_id and util.site_owner_civ(site_id) or nil
    end
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
    known_collections = {}
    baseline_collections(dprint)
    dprint('world-espionage: handler initialised')
end

function reset()
    known_collections = {}
end

function check_poll(dprint)
    scan_collections(dprint)
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
