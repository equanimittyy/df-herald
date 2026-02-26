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

local util = dfhack.reqscript('herald-util')

local PERSIST_CIVS_KEY = 'herald_pinned_civ_ids'

-- { [entity_id] = settings_table }; absent key = not pinned.
local pinned_civ_ids = {}

-- Snapshot of active position holders per civ; rebuilt each scan cycle to
-- detect deaths and new appointments by comparing against the previous cycle.
-- Schema: { [entity_id] = { [assignment_id] = { hf_id, pos_name, civ_name } } }
local tracked_leaders = {}

-- Persistence -----------------------------------------------------------------

local function save_pinned_civs()
    local pins = {}
    for id, settings in pairs(pinned_civ_ids) do
        table.insert(pins, { id = id, settings = settings })
    end
    dfhack.persistent.saveSiteData(PERSIST_CIVS_KEY, { pins = pins })
end

-- Announcement formatting -----------------------------------------------------
-- pos_name may be nil when util.get_pos_name can't resolve a title; the
-- fallback messages still name the civ so the player has useful context.

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

-- Poll handler ----------------------------------------------------------------
-- Called every scan cycle. Walks pinned civs, compares current position
-- assignments against the previous snapshot, and fires announcements
-- when a pinned civ gains or loses a position holder.

function check(dprint)
    dprint = dprint or function() end

    dprint('world-leaders.check: scanning pinned entity position assignments')

    local new_snapshot = {}
    local dbg_civs = 0

    -- Iterate only pinned civs; look up each entity directly instead of scanning all entities.
    for entity_id, pin_settings in pairs(pinned_civ_ids) do
        local entity = df.historical_entity.find(entity_id)
        if not entity then
            dprint('world-leaders: entity_id=%d not found, skipping', entity_id)
            goto continue_entity
        end
        dbg_civs = dbg_civs + 1

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
            local pos_name = util.get_pos_name(entity, pos_id, hf.sex)

            dprint('world-leaders:   hf=%s pos=%s alive=%s',
                dfhack.translation.translateName(hf.name, true), tostring(pos_name), tostring(util.is_alive(hf)))

            local prev_entity  = tracked_leaders[entity_id]
            local prev         = prev_entity and prev_entity[assignment.id]

            if not util.is_alive(hf) then
                if prev and prev.hf_id == hf_id then
                    local hf_name = dfhack.translation.translateName(hf.name, true)
                    if announce_positions then
                        dprint('world-leaders: death detected for %s (%s of %s) - firing announcement (positions ON)',
                            hf_name, tostring(pos_name), civ_name)
                        dfhack.gui.showAnnouncement(fmt_death(hf_name, pos_name, civ_name), COLOR_RED, true)
                    else
                        dprint('world-leaders: death detected for %s (%s of %s) - announcement suppressed (positions OFF)',
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
                        dprint('world-leaders: appointment detected for %s (%s of %s) - firing announcement (positions ON)',
                            hf_name, tostring(pos_name), civ_name)
                        dfhack.gui.showAnnouncement(fmt_appointment(hf_name, pos_name, civ_name), COLOR_YELLOW, true)
                    else
                        dprint('world-leaders: appointment detected for %s (%s of %s) - announcement suppressed (positions OFF)',
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

-- Public interface ------------------------------------------------------------

-- Loads pinned civs from persistence; drops stale entity entries.
function load_pinned_civs()
    local data = dfhack.persistent.getSiteData(PERSIST_CIVS_KEY, {})
    pinned_civ_ids = {}
    if type(data.pins) == 'table' then
        for _, entry in ipairs(data.pins) do
            if type(entry.id) == 'number' and df.historical_entity.find(entry.id) then
                pinned_civ_ids[entry.id] = util.merge_civ_pin_settings(entry.settings)
            end
        end
    end
end

-- Returns the full pinned civ map: { [entity_id] = settings_table }.
function get_pinned_civs()
    return pinned_civ_ids
end

-- Pins (truthy value) or unpins (nil/false) a civilisation.
function set_pinned_civ(entity_id, value)
    if value then
        pinned_civ_ids[entity_id] = util.default_civ_pin_settings()
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

-- Clears per-session snapshot on world unload (pinned list is reloaded on next load).
function reset()
    tracked_leaders = {}
end
