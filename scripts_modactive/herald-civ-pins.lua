--@ module=true

--[====[
herald-civ-pins
================

Tags: dev

  Shared pinned-civ state for Herald handlers. Owns the pinned_civ_ids
  table and persistence; world-leaders and world-diplomacy reqscript this.

Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')

local PERSIST_KEY = 'herald_pinned_civ_ids'

-- { [entity_id] = settings_table }
-- Absent key = not pinned. The settings table is truthy, so `if pinned[id]` still works.
local pinned_civ_ids = {}

-- Persistence -----------------------------------------------------------------

function save_pinned()
    local pins = {}
    for id, settings in pairs(pinned_civ_ids) do
        table.insert(pins, { id = id, settings = settings })
    end
    dfhack.persistent.saveSiteData(PERSIST_KEY, { pins = pins })
end

function load_pinned()
    local data = dfhack.persistent.getSiteData(PERSIST_KEY, {})
    pinned_civ_ids = {}
    if type(data.pins) == 'table' then
        for _, entry in ipairs(data.pins) do
            if type(entry.id) == 'number' and df.historical_entity.find(entry.id) then
                pinned_civ_ids[entry.id] = util.merge_civ_pin_settings(entry.settings)
            end
        end
    end
end

-- Pin management --------------------------------------------------------------

function get_pinned()
    return pinned_civ_ids
end

-- Pins (true) or unpins (nil/false) a civilisation; persists immediately.
function set_pinned(entity_id, value)
    if value then
        pinned_civ_ids[entity_id] = util.default_civ_pin_settings()
    else
        pinned_civ_ids[entity_id] = nil
    end
    save_pinned()
end

-- Returns the per-civ settings table for entity_id, or nil if not pinned.
function get_pin_settings(entity_id)
    return pinned_civ_ids[entity_id]
end

-- Updates one announcement key for a pinned civ and persists.
function set_pin_setting(entity_id, key, value)
    if pinned_civ_ids[entity_id] then
        pinned_civ_ids[entity_id][key] = value
        save_pinned()
    end
end

function reset()
    pinned_civ_ids = {}
end
