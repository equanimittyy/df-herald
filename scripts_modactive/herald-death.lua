-- herald-death.lua
-- Handles df.history_event_type.HIST_FIGURE_DIED events.
-- Loaded by herald-main.lua via dfhack.reqscript.

--@ module=true

local M = {}

-- Returns (entity, position_name) if hf_id held any position in a civ entity,
-- or nil, nil otherwise.
local function get_leader_info(hf_id, dprint)
    local hf = df.historical_figure.find(hf_id)
    if not hf then
        dprint('death: no HF found for id %d', hf_id)
        return nil, nil
    end

    dprint('death: checking HF "%s" (id %d) for leader links',
        dfhack.TranslateName(hf.name, true), hf_id)

    for _, link in ipairs(hf.entity_links) do
        if link:getType() == df.histfig_entity_link_type.POSITION then
            local entity = df.historical_entity.find(link.entity_id)
            if entity then
                dprint('death: found POSITION link to entity "%s"',
                    dfhack.TranslateName(entity.name, true))
                for _, assignment in ipairs(entity.position_assignments) do
                    if assignment.histfig2 == hf_id then
                        for _, pos in ipairs(entity.positions) do
                            if pos.id == assignment.id then
                                dprint('death: matched position "%s"',
                                    dfhack.TranslateName(pos.name, true))
                                return entity, pos.name
                            end
                        end
                    end
                end
            end
        end
    end

    dprint('death: HF %d held no tracked leader position', hf_id)
    return nil, nil
end

-- dprint is injected by herald-main so all debug output shares the same flag.
function M.check(event, dprint)
    dprint = dprint or function() end  -- safe default when called without debug arg

    local hf_id = event.victim_hf
    dprint('death.check: HIST_FIGURE_DIED victim hf_id=%d', hf_id)

    local entity, pos_name = get_leader_info(hf_id, dprint)
    if not entity then
        dprint('death.check: victim %d was not a leader; skipping announcement', hf_id)
        return
    end

    local hf       = df.historical_figure.find(hf_id)
    local hf_name  = dfhack.TranslateName(hf.name, true)
    local civ_name = dfhack.TranslateName(entity.name, true)

    dprint('death.check: announcing death of %s, %s of %s',
        hf_name, dfhack.TranslateName(pos_name, true), civ_name)

    dfhack.gui.showAnnouncement(
        ('[Herald] %s, %s of %s, has died.'):format(hf_name, pos_name, civ_name),
        COLOR_RED, true   -- pause = true for high-importance event
    )
end

return M
