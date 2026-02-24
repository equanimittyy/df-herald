--@ module=true

--[====[
herald-world-leaders
====================

Tags: fort | gameplay

  Tracks world leadership positions by polling HF state each scan cycle.

Detects leader deaths and succession changes that may not generate a
HIST_FIGURE_DIED history event (e.g. out-of-fort deaths where the game
sets hf.died_year/hf.died_seconds directly). Snapshots all entity
position holders each cycle and compares against the previous snapshot.
Not intended for direct use.

]====]

-- tracked_leaders: { [entity_id] = { [pos_id] = { hf_id, pos_name, civ_name } } }
local tracked_leaders = {}

local function is_alive(hf)
    return hf.died_year == -1 and hf.died_seconds == -1
end

function check(dprint)
    dprint = dprint or function() end

    dprint('world-leaders.check: scanning entity position assignments')

    local new_snapshot = {}
    local dbg_civs, dbg_with_assignments = 0, 0

    for _, entity in ipairs(df.global.world.entities.all) do
        -- Only track civilisation-layer entities; guilds, religions, animal herds, etc.
        -- are irrelevant to wars, raids, and succession tracking.
        if entity.type ~= df.historical_entity_type.Civilization then goto continue_entity end
        dbg_civs = dbg_civs + 1
        if #entity.positions.assignments == 0 then goto continue_entity end
        dbg_with_assignments = dbg_with_assignments + 1

        local entity_id = entity.id
        local civ_name  = dfhack.translation.translateName(entity.name, true)
        dprint('world-leaders: civ "%s" has %d assignments', civ_name, #entity.positions.assignments)

        for _, assignment in ipairs(entity.positions.assignments) do
            dprint('world-leaders:   assignment id=%d histfig=%d histfig2=%d',
                assignment.id, assignment.histfig or -999, assignment.histfig2 or -999)
            local hf_id = assignment.histfig2
            if hf_id == -1 then goto continue_assignment end

            local hf = df.historical_figure.find(hf_id)
            if not hf then goto continue_assignment end

            -- Position definitions live in entity.entity_raw, indexed by assignment.id
            local pos_name = nil
            local entity_raw = entity.entity_raw

            -- Look up position name: search entity_raw.positions for pos.id == assignment.position_id
            local pos_name = nil
            local pos_id   = assignment.position_id
            if entity_raw and pos_id then
                for _, pos in ipairs(entity_raw.positions) do
                    if pos.id == pos_id then
                        pos_name = pos.name[0]  -- string[], [0]=singular [1]=plural
                        break
                    end
                end
            end
            if not pos_name then
                dprint('world-leaders: no pos_name for entity %d position_id=%s', entity_id, tostring(pos_id))
            end

            if is_alive(hf) then
                if not new_snapshot[entity_id] then
                    new_snapshot[entity_id] = {}
                end
                new_snapshot[entity_id][pos_id] = {
                    hf_id    = hf_id,
                    pos_name = pos_name,
                    civ_name = civ_name,
                }
                dprint('world-leaders: alive leader %s, %s of %s',
                    dfhack.translation.translateName(hf.name, true), pos_name, civ_name)
            end

            local prev_entity = tracked_leaders[entity_id]
            if prev_entity then
                local prev = prev_entity[pos_id]
                if prev then
                    if not is_alive(hf) and prev.hf_id == hf_id then
                        -- Same person, now dead — leader died
                        local hf_name = dfhack.translation.translateName(hf.name, true)
                        dprint('world-leaders: death detected: %s, %s of %s',
                            hf_name, pos_name, civ_name)
                        dfhack.gui.showAnnouncement(
                            ('[Herald] %s, %s of %s, has died.'):format(
                                hf_name, pos_name, civ_name),
                            COLOR_RED, true
                        )
                    elseif is_alive(hf) and prev.hf_id ~= hf_id then
                        -- Different person now holds the position — succession
                        local new_name  = dfhack.translation.translateName(hf.name, true)
                        local prev_hf   = df.historical_figure.find(prev.hf_id)
                        local prev_name = prev_hf
                            and dfhack.translation.translateName(prev_hf.name, true)
                            or  ('HF#' .. tostring(prev.hf_id))
                        dprint('world-leaders: succession detected: %s -> %s, %s of %s',
                            prev_name, new_name, pos_name, civ_name)
                        dfhack.gui.showAnnouncement(
                            ('[Herald] %s has succeeded %s as %s of %s.'):format(
                                new_name, prev_name, pos_name, civ_name),
                            COLOR_YELLOW, true
                        )
                    end
                end
            end

            ::continue_assignment::
        end

        ::continue_entity::
    end

    tracked_leaders = new_snapshot
    dprint('world-leaders.check: civs=%d with_assignments=%d tracked=%d',
        dbg_civs, dbg_with_assignments,
        (function() local n=0 for _ in pairs(tracked_leaders) do n=n+1 end return n end)())
    dprint('world-leaders.check: done')
end

function reset()
    tracked_leaders = {}
end
