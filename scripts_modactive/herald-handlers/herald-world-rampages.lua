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

-- High-water mark: all collections at or below this ID existed at map load.
local baseline_max_id = -1
-- Collections seen since load (only new ones go here).
local known_collections = {}

-- Helpers -------------------------------------------------------------------

-- Collection type enum cache.
local CT = {}
do
    for _, name in ipairs({'BEAST_ATTACK'}) do
        local ok, v = pcall(function()
            return df.history_event_collection_type[name]
        end)
        if ok and v ~= nil then CT[name] = v end
    end
end

-- Collection handling -------------------------------------------------------

local function handle_beast_attack(col, dprint)
    local pinned_civs = civ_pins.get_pinned()

    -- Defender: direct field, fallback to site owner
    local def_civ = util.safe_get(col, 'defender_civ')
    if def_civ and def_civ < 0 then def_civ = nil end
    local site_id = util.safe_get(col, 'site')
    if not def_civ then
        def_civ = site_id and util.site_owner_civ(site_id) or nil
    end
    if not def_civ or not pinned_civs[def_civ] then return end
    if not pinned_civs[def_civ].rampages then return end

    local site_str = (site_id and site_id >= 0)
        and util.site_name(site_id) or 'a site'

    -- Resolve beast name from attacker_hf vector
    local beast_str = 'A beast'
    local ok_ahf, ahf = pcall(function() return col.attacker_hf end)
    if ok_ahf and ahf and #ahf > 0 then
        local hf_id = ahf[0]
        if hf_id and hf_id >= 0 then
            local hf = df.historical_figure.find(hf_id)
            if hf then
                local name = dfhack.translation.translateName(hf.name, true)
                if name and name ~= '' then
                    beast_str = name
                else
                    local race = util.get_race_name(hf)
                    local article = race:match('^[aeiouAEIOU]') and 'An ' or 'A '
                    beast_str = article .. race
                end
            end
        end
    end

    local msg = ('%s rampaged at %s!'):format(beast_str, site_str)
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

        -- Skip everything at or below the baseline
        if col.id <= baseline_max_id then goto continue end
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

-- Record the highest BEAST_ATTACK collection ID at map load.
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
                if col.id > baseline_max_id then baseline_max_id = col.id end
                count = count + 1
            end
        end
    end
    dprint('world-rampages.init: baseline %d existing collections (max_id=%d)', count, baseline_max_id)
end

function init(dprint)
    baseline_max_id = -1
    known_collections = {}
    baseline_collections(dprint)
    dprint('world-rampages: handler initialised')
end

function reset()
    baseline_max_id = -1
    known_collections = {}
end

function check_poll(dprint)
    scan_collections(dprint)
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
