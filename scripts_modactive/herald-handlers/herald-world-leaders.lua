--@ module=true

--[====[
herald-world-leaders
====================

Tags: dev

  Tracks world leadership positions by polling HF state each scan cycle.

Detects leader deaths and appointments that may not generate a
HIST_FIGURE_DIED history event (e.g. out-of-fort deaths where the game
sets hf.died_year/hf.died_seconds directly). Snapshots all entity
position holders each cycle and compares against the previous snapshot.
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local civ_pins = dfhack.reqscript('herald-civ-pins')

-- Snapshot of active position holders per civ; rebuilt each scan cycle to
-- detect deaths and new appointments by comparing against the previous cycle.
-- Schema: { [entity_id] = { [assignment_id] = { hf_id, pos_name, civ_name } } }
local tracked_leaders = {}

-- Announcement formatting -----------------------------------------------------
-- pos_name may be nil when util.get_pos_name can't resolve a title; the
-- fallback messages still name the civ so the player has useful context.

local function fmt_death(hf_name, pos_name, civ_name)
    if pos_name then
        return ('%s, %s of %s, has died.'):format(hf_name, pos_name, civ_name)
    end
    return ('%s of %s, a position holder, has died.'):format(hf_name, civ_name)
end

local function fmt_appointment(hf_name, pos_name, civ_name)
    if pos_name then
        return ('%s has been appointed %s of %s.'):format(hf_name, pos_name, civ_name)
    end
    return ('%s has been appointed to a position in %s.'):format(hf_name, civ_name)
end

local function fmt_vacated(hf_name, pos_name, civ_name)
    if pos_name then
        return ('%s is no longer %s of %s.'):format(hf_name, pos_name, civ_name)
    end
    return ('%s is no longer a position holder in %s.'):format(hf_name, civ_name)
end

-- Poll handler ----------------------------------------------------------------
-- Called every scan cycle. Walks pinned civs, compares current position
-- assignments against the previous snapshot, and fires announcements
-- when a pinned civ gains or loses a position holder.

function check_poll(dprint)
    dprint('world-leaders.check_poll: scanning pinned entity position assignments')

    local new_snapshot = {}
    local dbg_civs = 0

    for entity_id, pin_settings in pairs(civ_pins.get_pinned()) do
        local entity = df.historical_entity.find(entity_id)
        if not entity then goto continue_entity end
        dbg_civs = dbg_civs + 1

        local ok_asgn, assignments = pcall(function() return entity.positions.assignments end)
        if not ok_asgn or not assignments or #assignments == 0 then
            goto continue_entity
        end

        local announce_positions = pin_settings.positions
        local prev_entity = tracked_leaders[entity_id]
        local civ_name  -- deferred until first live holder

        for _, assignment in ipairs(assignments) do
            local hf_id = assignment.histfig2
            if hf_id == -1 then goto continue_assignment end

            local hf = df.historical_figure.find(hf_id)
            if not hf then goto continue_assignment end

            local prev = prev_entity and prev_entity[assignment.id]

            if not util.is_alive(hf) then
                -- Death: was tracked alive last cycle, now dead
                if prev and prev.hf_id == hf_id and announce_positions then
                    local hf_name = dfhack.translation.translateName(hf.name, true)
                    dprint('world-leaders: death detected for %s (%s of %s)',
                        hf_name, tostring(prev.pos_name), prev.civ_name)
                    util.announce_death(fmt_death(hf_name, prev.pos_name, prev.civ_name))
                end
            else
                -- Carry forward pos_name for unchanged holders; resolve only on change
                local pos_name
                local is_new = not prev or prev.hf_id ~= hf_id
                if is_new then
                    pos_name = util.get_pos_name(entity, assignment.position_id, hf.sex)
                else
                    pos_name = prev.pos_name
                end

                if not civ_name then
                    civ_name = dfhack.translation.translateName(entity.name, true)
                    if not civ_name or civ_name == '' then civ_name = tostring(entity_id) end
                end

                if not new_snapshot[entity_id] then
                    new_snapshot[entity_id] = {}
                end
                new_snapshot[entity_id][assignment.id] = {
                    hf_id    = hf_id,
                    pos_name = pos_name,
                    civ_name = civ_name,
                }

                -- New appointment: entity was tracked before but this slot is new/changed
                if is_new and prev_entity then
                    if announce_positions then
                        local hf_name = dfhack.translation.translateName(hf.name, true)
                        dprint('world-leaders: appointment for %s (%s of %s)',
                            hf_name, tostring(pos_name), civ_name)
                        util.announce_appointment(fmt_appointment(hf_name, pos_name, civ_name))
                    else
                        dprint('world-leaders: appointment for hf %d - suppressed (positions OFF)', hf_id)
                    end
                end
            end

            ::continue_assignment::
        end

        ::continue_entity::
    end

    -- Detect vacated positions: was in previous snapshot, alive, but gone or replaced.
    -- Uses cached pos_name/civ_name from previous snapshot to avoid re-resolving.
    for entity_id, prev_assignments in pairs(tracked_leaders) do
        local pin_settings = civ_pins.get_pinned()[entity_id]
        if not pin_settings or not pin_settings.positions then
            goto continue_vacate_entity
        end

        for assignment_id, prev in pairs(prev_assignments) do
            local new_assign = new_snapshot[entity_id] and new_snapshot[entity_id][assignment_id]
            if not new_assign or new_assign.hf_id ~= prev.hf_id then
                local old_hf = df.historical_figure.find(prev.hf_id)
                if old_hf and util.is_alive(old_hf) then
                    local hf_name = dfhack.translation.translateName(old_hf.name, true)
                    dprint('world-leaders: vacated for %s (%s of %s)',
                        hf_name, tostring(prev.pos_name), prev.civ_name)
                    util.announce_vacated(fmt_vacated(hf_name, prev.pos_name, prev.civ_name))
                end
            end
        end

        ::continue_vacate_entity::
    end

    tracked_leaders = new_snapshot
    dprint('world-leaders.check_poll: civs=%d', dbg_civs)
end

-- Handler contract -------------------------------------------------------------

polls = true

-- Set leader baselines immediately at map load.
local function set_initial_baselines(dprint)
    for entity_id, _ in pairs(civ_pins.get_pinned()) do
        local entity = df.historical_entity.find(entity_id)
        if not entity then goto next_civ end
        local ok_asgn, assignments = pcall(function() return entity.positions.assignments end)
        if not ok_asgn or not assignments then goto next_civ end
        local civ_name = dfhack.translation.translateName(entity.name, true)
        local snap = {}
        for _, assignment in ipairs(assignments) do
            local hf_id = assignment.histfig2
            if hf_id == -1 then goto next_asgn end
            local hf = df.historical_figure.find(hf_id)
            if not hf or not util.is_alive(hf) then goto next_asgn end
            snap[assignment.id] = {
                hf_id    = hf_id,
                pos_name = util.get_pos_name(entity, assignment.position_id, hf.sex),
                civ_name = civ_name,
            }
            ::next_asgn::
        end
        tracked_leaders[entity_id] = snap
        local n = 0
        for _ in pairs(snap) do n = n + 1 end
        dprint('world-leaders.init: baseline for entity %d (%s): %d leaders', entity_id, civ_name or '?', n)
        ::next_civ::
    end
end

function init(dprint)
    civ_pins.load_pinned()
    set_initial_baselines(dprint)
    dprint('world-leaders: handler initialised')
end

function reset()
    tracked_leaders = {}
    civ_pins.reset()
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
