-- herald-death.lua
-- Handles df.history_event_type.HIST_FIGURE_DIED events.
-- Loaded by herald-main.lua via dfhack.reqscript.

local M = {}

-- Returns (entity, position_name) if hf_id held any position in a civ entity,
-- or nil, nil otherwise.
local function get_leader_info(hf_id)
    local hf = df.historical_figure.find(hf_id)
    if not hf then return nil, nil end

    for _, link in ipairs(hf.entity_links) do
        if link:getType() == df.histfig_entity_link_type.POSITION then
            local entity = df.historical_entity.find(link.entity_id)
            if entity then
                for _, assignment in ipairs(entity.position_assignments) do
                    if assignment.histfig2 == hf_id then
                        for _, pos in ipairs(entity.positions) do
                            if pos.id == assignment.id then
                                return entity, pos.name
                            end
                        end
                    end
                end
            end
        end
    end

    return nil, nil
end

function M.check(event)
    local hf_id = event.victim_hf
    local entity, pos_name = get_leader_info(hf_id)
    if not entity then return end

    local hf       = df.historical_figure.find(hf_id)
    local hf_name  = dfhack.TranslateName(hf.name, true)
    local civ_name = dfhack.TranslateName(entity.name, true)

    dfhack.gui.showAnnouncement(
        ('[Herald] %s, %s of %s, has died.'):format(hf_name, pos_name, civ_name),
        COLOR_RED, true   -- pause = true for high-importance event
    )
end

return M
