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
                for _, assignment in ipairs(entity.positions.assignments) do
                    if assignment.histfig2 == hf_id then
                        local pos_name = get_pos_name(entity, assignment.position_id, hf)
                        dprint('death: matched position "%s"', tostring(pos_name))
                        return entity, pos_name
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
    local hf_name  = dfhack.translation.translateName(hf.name, true)
    local civ_name = dfhack.translation.translateName(entity.name, true)

    dprint('death.check: announcing death of %s, %s of %s', hf_name, tostring(pos_name), civ_name)

    local msg
    if pos_name then
        msg = ('[Herald] %s, %s of %s, has died.'):format(hf_name, pos_name, civ_name)
    else
        msg = ('[Herald] %s of %s, a position holder, has died.'):format(hf_name, civ_name)
    end

    dfhack.gui.showAnnouncement(msg, COLOR_RED, true)
end
