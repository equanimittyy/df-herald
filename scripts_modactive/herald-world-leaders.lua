--@ module=true

--[====[
herald-world-leaders
====================

Tags: fort | gameplay

  Tracks world leadership positions by polling HF state each scan cycle.

Detects leader deaths and appointments that may not generate a
HIST_FIGURE_DIED history event (e.g. out-of-fort deaths where the game
sets hf.died_year/hf.died_seconds directly). Snapshots all entity
position holders each cycle and compares against the previous snapshot.
Not intended for direct use.

]====]

local PERSIST_CIVS_KEY = 'herald_pinned_civ_ids'

-- { [entity_id] = { positions=bool, diplomacy=bool, raids=bool,
--                   theft=bool, kidnappings=bool, armies=bool } }
-- Absent key = not pinned.
local pinned_civ_ids = {}

-- tracked_leaders: { [entity_id] = { [assignment_id] = { hf_id, pos_name, civ_name } } }
local tracked_leaders = {}

local CIV_SETTINGS_KEYS = { 'positions', 'diplomacy', 'raids', 'theft', 'kidnappings', 'armies' }

-- Hardcoded defaults match DEFAULT_ANNOUNCEMENTS in herald-main.lua.
-- Not using reqscript('herald-main') here to avoid circular dep at load time.
local function default_civ_pin_settings()
    return {
        positions   = true,
        diplomacy   = false,
        raids       = false,
        theft       = false,
        kidnappings = false,
        armies      = false,
    }
end

-- Merges a saved settings table with current defaults; fills missing keys.
local function merge_civ_pin_settings(saved)
    local defaults = default_civ_pin_settings()
    if type(saved) ~= 'table' then return defaults end
    for _, k in ipairs(CIV_SETTINGS_KEYS) do
        if type(saved[k]) == 'boolean' then
            defaults[k] = saved[k]
        end
    end
    return defaults
end

local function save_pinned_civs()
    local pins = {}
    for id, settings in pairs(pinned_civ_ids) do
        table.insert(pins, { id = id, settings = settings })
    end
    dfhack.persistent.saveSiteData(PERSIST_CIVS_KEY, { pins = pins })
end

local function is_alive(hf)
    return hf.died_year == -1 and hf.died_seconds == -1
end

-- Normalises a position name field: entity_position_raw uses string[] (name[0]),
-- entity_position (entity.positions.own) uses plain stl-string.
local function name_str(field)
    if not field then return nil end
    if type(field) == 'string' then return field ~= '' and field or nil end
    local s = field[0]
    return (s and s ~= '') and s or nil
end

-- Returns the gendered (or neutral) position title for an assignment.
-- Tries entity_raw.positions first; falls back to entity.positions.own for EVIL/PLAINS
-- civs whose entity_raw carries no positions.
local function get_pos_name(entity, pos_id, hf)
    if not entity or pos_id == nil then return nil end

    local entity_raw = entity.entity_raw
    if entity_raw then
        for _, pos in ipairs(entity_raw.positions) do
            if pos.id == pos_id then
                local gendered = hf.sex == 1 and name_str(pos.name_male) or name_str(pos.name_female)
                return gendered or name_str(pos.name)
            end
        end
    end

    local own = entity.positions and entity.positions.own
    if own then
        for _, pos in ipairs(own) do
            if pos.id == pos_id then
                local gendered = hf.sex == 1 and name_str(pos.name_male) or name_str(pos.name_female)
                return gendered or name_str(pos.name)
            end
        end
    end

    return nil
end

-- Formats an announcement string, omitting the position clause when pos_name is nil.
local function fmt_death(hf_name, pos_name, civ_name)
    if pos_name then
        return ('[Herald] %s, %s of %s, has died.'):format(hf_name, pos_name, civ_name)
    end
    return ('[Herald] %s of %s, a position holder, has died.'):format(hf_name, civ_name)
end

local function fmt_appointment(hf_name, pos_name, civ_name)
    if pos_name then
        return ('[Herald] %s has been appointed %s of %s.'):format(hf_name, pos_name, civ_name)
    end
    return ('[Herald] %s has been appointed to a position in %s.'):format(hf_name, civ_name)
end

function check(dprint)
    dprint = dprint or function() end

    dprint('world-leaders.check: scanning entity position assignments')

    local new_snapshot = {}
    local dbg_civs = 0

    for _, entity in ipairs(df.global.world.entities.all) do
        -- Only track civilisation-layer entities; guilds, religions, animal herds, etc.
        -- are irrelevant to wars, raids, and succession tracking.
        if entity.type ~= df.historical_entity_type.Civilization then goto continue_entity end
        dbg_civs = dbg_civs + 1

        local entity_id  = entity.id
        local pin_settings = pinned_civ_ids[entity_id]
        -- Skip unpinned civs — only pinned civs fire announcements.
        if not pin_settings then
            dprint('world-leaders: entity_id=%d is not tracked, skipping', entity_id)
            goto continue_entity
        end

        if #entity.positions.assignments == 0 then
            dprint('world-leaders: entity_id=%d has no assignments, skipping', entity_id)
            goto continue_entity
        end

        local civ_name           = dfhack.translation.translateName(entity.name, true)
        local announce_positions = pin_settings.positions

        dprint('world-leaders: civ "%s" has %d assignments', civ_name, #entity.positions.assignments)

        for _, assignment in ipairs(entity.positions.assignments) do
            local hf_id = assignment.histfig2
            if hf_id == -1 then goto continue_assignment end

            local hf = df.historical_figure.find(hf_id)
            if not hf then goto continue_assignment end

            local pos_id   = assignment.position_id
            local pos_name = get_pos_name(entity, pos_id, hf)

            dprint('world-leaders:   hf=%s pos=%s alive=%s',
                dfhack.translation.translateName(hf.name, true), tostring(pos_name), tostring(is_alive(hf)))

            local prev_entity  = tracked_leaders[entity_id]
            local prev         = prev_entity and prev_entity[assignment.id]

            if not is_alive(hf) then
                if prev and prev.hf_id == hf_id then
                    local hf_name = dfhack.translation.translateName(hf.name, true)
                    if announce_positions then
                        dprint('world-leaders: death detected for %s (%s of %s) — firing announcement (positions ON)',
                            hf_name, tostring(pos_name), civ_name)
                        dfhack.gui.showAnnouncement(fmt_death(hf_name, pos_name, civ_name), COLOR_RED, true)
                    else
                        dprint('world-leaders: death detected for %s (%s of %s) — announcement suppressed (positions OFF)',
                            hf_name, tostring(pos_name), civ_name)
                    end
                end
            else
                if not new_snapshot[entity_id] then
                    new_snapshot[entity_id] = {}
                end
                new_snapshot[entity_id][assignment.id] = {
                    hf_id    = hf_id,
                    pos_name = pos_name,
                    civ_name = civ_name,
                }

                if prev_entity and (prev == nil or prev.hf_id ~= hf_id) then
                    local hf_name = dfhack.translation.translateName(hf.name, true)
                    if announce_positions then
                        dprint('world-leaders: appointment detected for %s (%s of %s) — firing announcement (positions ON)',
                            hf_name, tostring(pos_name), civ_name)
                        dfhack.gui.showAnnouncement(fmt_appointment(hf_name, pos_name, civ_name), COLOR_YELLOW, true)
                    else
                        dprint('world-leaders: appointment detected for %s (%s of %s) — announcement suppressed (positions OFF)',
                            hf_name, tostring(pos_name), civ_name)
                    end
                end
            end

            ::continue_assignment::
        end

        ::continue_entity::
    end

    tracked_leaders = new_snapshot
    dprint('world-leaders.check: civs=%d tracked=%d',
        dbg_civs,
        (function() local n=0 for _ in pairs(tracked_leaders) do n=n+1 end return n end)())
end

-- Loads pinned civ list from per-save persistence.
-- Drops entries where the entity no longer exists in the world.
function load_pinned_civs()
    local data = dfhack.persistent.getSiteData(PERSIST_CIVS_KEY, {})
    pinned_civ_ids = {}
    if type(data.pins) == 'table' then
        for _, entry in ipairs(data.pins) do
            if type(entry.id) == 'number' and df.historical_entity.find(entry.id) then
                pinned_civ_ids[entry.id] = merge_civ_pin_settings(entry.settings)
            end
        end
    end
end

-- Returns the full pinned civ map: { [entity_id] = settings_table }.
function get_pinned_civs()
    return pinned_civ_ids
end

-- Pins or unpins a civilisation. value=true pins (inits default settings);
-- value=false/nil unpins.
function set_pinned_civ(entity_id, value)
    if value then
        pinned_civ_ids[entity_id] = default_civ_pin_settings()
    else
        pinned_civ_ids[entity_id] = nil
    end
    save_pinned_civs()
end

-- Returns the per-civ settings table for entity_id, or nil if not pinned.
function get_civ_pin_settings(entity_id)
    return pinned_civ_ids[entity_id]
end

-- Updates one announcement key for a pinned civ and persists.
function set_civ_pin_setting(entity_id, key, value)
    if pinned_civ_ids[entity_id] then
        pinned_civ_ids[entity_id][key] = value
        save_pinned_civs()
    end
end

function reset()
    tracked_leaders = {}
    -- pinned_civ_ids is per-save config; reloaded by load_pinned_civs() on SC_MAP_LOADED
end
