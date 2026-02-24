--@ module=true

--[====[
herald-fort-death
=================

Tags: fort | gameplay

  Fort handler for "df.history_event_type.HIST_FIGURE_DIED" events.

Detects when a historical figure who held a leadership position has died and
fires an in-game announcement. Reliable for in-fort deaths only — out-of-fort
deaths may not generate this event; see herald-world-leaders for those.
Not intended for direct use.

]====]

local function get_leader_info(hf_id, dprint)
    local hf = df.historical_figure.find(hf_id)
    if not hf then
        dprint('death: no HF found for id %d', hf_id)
        return nil, nil
    end

    dprint('death: checking HF "%s" (id %d) for leader links',
        dfhack.translation.translateName(hf.name, true), hf_id)

    for _, link in ipairs(hf.entity_links) do
        if link:getType() == df.histfig_entity_link_type.POSITION then
            local entity = df.historical_entity.find(link.entity_id)
            if entity then
                dprint('death: found POSITION link to entity "%s"',
                    dfhack.translation.translateName(entity.name, true))
                for _, assignment in ipairs(entity.position_assignments) do
                    if assignment.histfig2 == hf_id then
                        for _, pos in ipairs(entity.positions) do
                            if pos.id == assignment.id then
                                dprint('death: matched position "%s"',
                                    dfhack.translation.translateName(pos.name, true))
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

function check(event, dprint)
    dprint = dprint or function() end

    local hf_id = event.victim_hf
    dprint('death.check: HIST_FIGURE_DIED victim hf_id=%d', hf_id)

    local entity, pos_name = get_leader_info(hf_id, dprint)
    if not entity then
        dprint('death.check: victim %d was not a leader; skipping announcement', hf_id)
        return
    end

    local hf       = df.historical_figure.find(hf_id)
    local hf_name   = dfhack.translation.translateName(hf.name, true)
    local civ_name  = dfhack.translation.translateName(entity.name, true)
    local pos_str   = dfhack.translation.translateName(pos_name, true)

    dprint('death.check: announcing death of %s, %s of %s',
        hf_name, pos_str, civ_name)

    dfhack.gui.showAnnouncement(
        ('[Herald] %s, %s of %s, has died.'):format(hf_name, pos_str, civ_name),
        COLOR_RED, true   -- pause = true for high-importance event
    )
end
