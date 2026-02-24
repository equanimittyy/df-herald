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

-- tracked_leaders: { [entity_id] = { [assignment_id] = { hf_id, pos_name, civ_name } } }
local tracked_leaders = {}

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

    local ann = dfhack.reqscript('herald-main').get_announcements()
    local announce_positions = ann and ann.civilisations and ann.civilisations.positions

    dprint('world-leaders.check: scanning entity position assignments')

    local new_snapshot = {}
    local dbg_civs = 0

    for _, entity in ipairs(df.global.world.entities.all) do
        -- Only track civilisation-layer entities; guilds, religions, animal herds, etc.
        -- are irrelevant to wars, raids, and succession tracking.
        if entity.type ~= df.historical_entity_type.Civilization then goto continue_entity end
        dbg_civs = dbg_civs + 1
        if #entity.positions.assignments == 0 then goto continue_entity end

        local entity_id = entity.id
        local civ_name  = dfhack.translation.translateName(entity.name, true)

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
                    dprint('world-leaders: death detected: %s, %s of %s', hf_name, tostring(pos_name), civ_name)
                    if announce_positions then
                        dfhack.gui.showAnnouncement(fmt_death(hf_name, pos_name, civ_name), COLOR_RED, true)
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
                    dprint('world-leaders: appointment: %s as %s of %s', hf_name, tostring(pos_name), civ_name)
                    if announce_positions then
                        dfhack.gui.showAnnouncement(fmt_appointment(hf_name, pos_name, civ_name), COLOR_YELLOW, true)
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

function reset()
    tracked_leaders = {}
end
