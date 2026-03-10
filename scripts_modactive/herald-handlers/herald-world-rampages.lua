--@ module=true

--[====[
herald-world-rampages
=====================

Tags: dev

  Poll-based handler for civilisation beast attack events.

Detects new BEAST_ATTACK collections targeting pinned civ sites.
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local civ_pins = dfhack.reqscript('herald-civ-pins')

-- Collection IDs already seen; persistent until world unload.
local known_collections = {}

-- Helpers -------------------------------------------------------------------

local function ent_name(entity_id)
    if not entity_id or entity_id < 0 then return 'an unknown civilisation' end
    local entity = df.historical_entity.find(entity_id)
    if not entity then return 'entity ' .. entity_id end
    local name = dfhack.translation.translateName(entity.name, true)
    return (name and name ~= '') and name or ('entity ' .. entity_id)
end

-- Collection type enum cache.
local CT = {}
do
    local ok, v = pcall(function()
        return df.history_event_collection_type.BEAST_ATTACK
    end)
    if ok and v ~= nil then CT.BEAST_ATTACK = v end
end

-- Collection handling -------------------------------------------------------

local function handle_beast_attack(col, dprint)
    local pinned_civs = civ_pins.get_pinned()

    -- Resolve site owner to check against pinned civs
    local site_id = util.safe_get(col, 'site')
    if not site_id or site_id < 0 then return end

    local owner_civ = util.site_owner_civ(site_id)
    if not owner_civ or not pinned_civs[owner_civ] then return end
    if not pinned_civs[owner_civ].rampages then return end

    local site_str = util.site_name(site_id) or 'a site'
    local msg = ('Beast attack reported at %s!'):format(site_str)
    dprint('world-rampages: BEAST_ATTACK collection %d - %s', col.id, msg)
    util.announce_rampage(msg)
end

-- Scan all collections for new BEAST_ATTACK.
local function scan_collections(dprint)
    if not CT.BEAST_ATTACK then return end

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

        if ct == CT.BEAST_ATTACK then
            known_collections[col.id] = true
            new_count = new_count + 1
            handle_beast_attack(col, dprint)
        end

        ::continue::
    end

    if new_count > 0 then
        dprint('world-rampages: scan_collections found %d new collection(s)', new_count)
    end
end

-- Contract fields -----------------------------------------------------------

polls = true

-- Baseline all existing collections at map load.
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
            if ok3 and ct == CT.BEAST_ATTACK then
                known_collections[col.id] = true
                count = count + 1
            end
        end
    end
    dprint('world-rampages.init: baseline %d existing collections', count)
end

function init(dprint)
    known_collections = {}
    baseline_collections(dprint)
    dprint('world-rampages: handler initialised')
end

function reset()
    known_collections = {}
end

function check_poll(dprint)
    scan_collections(dprint)
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
