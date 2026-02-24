-- herald-world-leaders.lua
-- Poll-based world leader tracking for the Herald mod.
-- Loaded by herald-main.lua via dfhack.reqscript.

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
-- Holds the snapshot from the previous scan cycle.
local tracked_leaders = {}

-- Returns true if hf is currently alive.
local function is_alive(hf)
    return hf.died_year == -1 and hf.died_seconds == -1
end

-- dprint is injected by herald-main so all debug output shares the same flag.
function check(dprint)
    dprint = dprint or function() end

    dprint('world-leaders.check: scanning entity position assignments')

    local new_snapshot = {}

    for _, entity in ipairs(df.global.world.entities.all) do
        -- Only track civilisation-layer entities; guilds, religions, animal herds, etc.
        -- are irrelevant to wars, raids, and succession tracking.
        if entity.type ~= df.historical_entity_type.Civilization then goto continue_entity end
        if #entity.position_assignments == 0 then goto continue_entity end

        local entity_id = entity.id
        local civ_name  = dfhack.translation.translateName(entity.name, true)

        for _, assignment in ipairs(entity.position_assignments) do
            local hf_id = assignment.histfig2
            if hf_id == -1 then goto continue_assignment end

            local hf = df.historical_figure.find(hf_id)
            if not hf then goto continue_assignment end

            -- Resolve position name from entity.positions by matching pos.id == assignment.id
            local pos_name = nil
            for _, pos in ipairs(entity.positions) do
                if pos.id == assignment.id then
                    pos_name = dfhack.translation.translateName(pos.name, true)
                    break
                end
            end
            if not pos_name then goto continue_assignment end

            local pos_id = assignment.id

            -- Build the new snapshot entry (alive leaders only)
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

            -- Compare against previous snapshot
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

    -- Replace old snapshot with the new one (alive holders only)
    tracked_leaders = new_snapshot
    dprint('world-leaders.check: snapshot updated, %d entities tracked',
        (function() local n=0 for _ in pairs(tracked_leaders) do n=n+1 end return n end)())
end

-- Called by herald-main on world unload to clear stale snapshot state.
function reset()
    tracked_leaders = {}
end
