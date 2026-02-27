--@ module=true

--[====[
herald-util
===========
Tags: fort | gameplay

  Shared utility functions for the Herald mod. Used by herald-main,
  herald-ind-death, herald-world-leaders, herald-gui, and
  herald-event-history to avoid code duplication.

Not intended for direct use.
]====]

-- Announcement helpers --------------------------------------------------------
-- Centralised wrappers so callers don't hardcode colours or pause flags.

-- Death of a tracked individual or position holder (red, pauses game).
function announce_death(msg)
    dfhack.gui.showAnnouncement(msg, COLOR_RED, true)
end

-- New appointment to a position (yellow, pauses game).
function announce_appointment(msg)
    dfhack.gui.showAnnouncement(msg, COLOR_YELLOW, true)
end

-- Position vacated by a living HF (white, no pause).
function announce_vacated(msg)
    dfhack.gui.showAnnouncement(msg, COLOR_WHITE, false)
end

-- General informational message (cyan, no pause).
function announce_info(msg)
    dfhack.gui.showAnnouncement(msg, COLOR_LIGHTCYAN, false)
end

-- Position name helpers -------------------------------------------------------
-- DF stores position names in two different formats depending on the source:
--   entity.positions.own      -> plain stl-string  (pos.name is a Lua string)
--   entity.entity_raw.positions -> string array    (pos.name[0])
-- name_str normalises either into a plain Lua string, or nil if empty.

function name_str(field)
    if not field then return nil end
    if type(field) == 'string' then return field ~= '' and field or nil end
    local s = field[0]
    return (s and s ~= '') and s or nil
end

-- Returns the gendered (or neutral) position title for a given position ID.
-- hf_sex: 1 = male, 0 = female (hf.sex).
-- Checks entity.positions.own first because it carries entity-specific titles
-- (e.g. "leader" for nomadic groups). Falls back to entity_raw.positions for
-- entity types like EVIL/PLAINS that leave the own list empty.
function get_pos_name(entity, pos_id, hf_sex)
    if not entity or pos_id == nil then return nil end

    local own = entity.positions and entity.positions.own
    if own then
        for _, pos in ipairs(own) do
            if pos.id == pos_id then
                local gendered = hf_sex == 1 and name_str(pos.name_male)
                                              or  name_str(pos.name_female)
                local result = gendered or name_str(pos.name)
                if result then return result end
                break  -- matched but all name fields empty; fall through
            end
        end
    end

    local entity_raw = entity.entity_raw
    if entity_raw then
        for _, pos in ipairs(entity_raw.positions) do
            if pos.id == pos_id then
                local gendered = hf_sex == 1 and name_str(pos.name_male)
                                              or  name_str(pos.name_female)
                return gendered or name_str(pos.name)
            end
        end
    end

    return nil
end

-- HF / entity helpers ---------------------------------------------------------

-- An HF is alive when neither died_year nor died_seconds has been set.
-- The game may set these directly without generating a HIST_FIGURE_DIED event,
-- which is why poll-based handlers check these fields directly.
function is_alive(hf)
    return hf.died_year == -1 and hf.died_seconds == -1
end

-- Returns the creature species name for an HF (e.g. "dwarf", "elf").
function get_race_name(hf)
    if not hf or hf.race < 0 then return '?' end
    local cr = df.creature_raw.find(hf.race)
    if not cr then return '?' end
    return cr.name[0] or '?'
end

-- Same as get_race_name but accepts a historical entity instead of an HF.
function get_entity_race_name(entity)
    if not entity or entity.race < 0 then return '?' end
    local cr = df.creature_raw.find(entity.race)
    if not cr then return '?' end
    return cr.name[0] or '?'
end

-- Table utilities -------------------------------------------------------------

-- Returns a deep copy of any Lua value (tables are copied recursively).
function deepcopy(t)
    if type(t) ~= 'table' then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = deepcopy(v) end
    return copy
end

-- Pin settings ----------------------------------------------------------------
-- Default settings are defined here (not in herald-main) so handler modules
-- can call default_pin_settings() / default_civ_pin_settings() without
-- reqscript-ing herald-main, which would create a circular dependency.

-- Ordered key lists; used when merging a saved settings table over defaults.
INDIVIDUAL_SETTINGS_KEYS    = { 'relationships', 'death', 'combat', 'legendary', 'positions', 'migration' }
CIVILISATION_SETTINGS_KEYS  = { 'positions', 'diplomacy', 'warfare', 'raids', 'theft', 'kidnappings' }

function default_pin_settings()
    return {
        relationships = true,
        death         = true,
        combat        = true,
        legendary     = true,
        positions     = true,
        migration     = true,
    }
end

function default_civ_pin_settings()
    return {
        positions   = true,
        diplomacy   = true,
        warfare     = true,
        raids       = true,
        theft       = true,
        kidnappings = true,
    }
end

-- Merges a saved settings table over a defaults table; fills any missing keys.
-- Only boolean values from saved are accepted; unknown keys are silently ignored.
local function merge_settings(saved, keys, defaults)
    if type(saved) ~= 'table' then return defaults end
    for _, k in ipairs(keys) do
        if type(saved[k]) == 'boolean' then
            defaults[k] = saved[k]
        end
    end
    return defaults
end

function merge_pin_settings(saved)
    return merge_settings(saved, INDIVIDUAL_SETTINGS_KEYS, default_pin_settings())
end

function merge_civ_pin_settings(saved)
    return merge_settings(saved, CIVILISATION_SETTINGS_KEYS, default_civ_pin_settings())
end

