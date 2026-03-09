--@ module=true

--[====[
herald-pins
============

Tags: dev

  Shared pinned-HF state for Herald handlers. Owns the pinned_hf_ids
  table and persistence; both ind-death and ind-combat reqscript this.

Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')

local PERSIST_KEY = 'herald_pinned_hf_ids'

-- { [hf_id] = settings_table }
-- Absent key = not pinned. The settings table is truthy, so `if pinned[hf_id]` still works.
local pinned_hf_ids = {}

-- Persistence -----------------------------------------------------------------

function load_pinned()
    local data = dfhack.persistent.getSiteData(PERSIST_KEY, {})
    pinned_hf_ids = {}
    if type(data.pins) == 'table' then
        for _, entry in ipairs(data.pins) do
            if type(entry.id) == 'number' then
                pinned_hf_ids[entry.id] = util.merge_pin_settings(entry.settings)
            end
        end
    end
end

function save_pinned()
    local pins = {}
    for id, settings in pairs(pinned_hf_ids) do
        table.insert(pins, { id = id, settings = settings })
    end
    dfhack.persistent.saveSiteData(PERSIST_KEY, { pins = pins })
end

-- Pin management --------------------------------------------------------------

function get_pinned()
    return pinned_hf_ids
end

-- Pins (true) or unpins (nil/false) an HF; persists immediately.
function set_pinned(hf_id, value)
    if value then
        pinned_hf_ids[hf_id] = util.default_pin_settings()
    else
        pinned_hf_ids[hf_id] = nil
    end
    save_pinned()
end

-- Returns the per-pin settings table for hf_id, or nil if not pinned.
function get_pin_settings(hf_id)
    return pinned_hf_ids[hf_id]
end

-- Updates one announcement key for a pinned HF and persists.
function set_pin_setting(hf_id, key, value)
    if pinned_hf_ids[hf_id] then
        pinned_hf_ids[hf_id][key] = value
        save_pinned()
    end
end
