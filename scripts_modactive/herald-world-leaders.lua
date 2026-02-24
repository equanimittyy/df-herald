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

-- Returns the position title for an assignment, using the gendered form if available.
-- Searches entity_raw.positions by pos.id == pos_id (string[], [0]=singular).
-- Note: some entity types (e.g. EVIL/PLAINS) have empty entity_raw.positions — their
-- position names appear to be generated via the language system, not stored as plain strings.
-- In those cases this returns nil and the caller falls back to generic announcement text.
local function get_pos_name(entity_raw, pos_id, hf)
    if not entity_raw or not pos_id then return nil end
    for _, pos in ipairs(entity_raw.positions) do
        if pos.id == pos_id then
            local gendered = (hf.sex == 1) and pos.name_male[0] or pos.name_female[0]
            return (gendered and gendered ~= '') and gendered or pos.name[0]
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

local function fmt_succession(new_name, prev_name, pos_name, civ_name)
    if pos_name then
        return ('[Herald] %s has succeeded %s as %s of %s.'):format(new_name, prev_name, pos_name, civ_name)
    end
    return ('[Herald] %s has succeeded %s as a position holder of %s.'):format(new_name, prev_name, civ_name)
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
        if #entity.positions.assignments == 0 then goto continue_entity end

        local entity_id  = entity.id
        local civ_name   = dfhack.translation.translateName(entity.name, true)
        local entity_raw = entity.entity_raw

        dprint('world-leaders: civ "%s" has %d assignments', civ_name, #entity.positions.assignments)

        for _, assignment in ipairs(entity.positions.assignments) do
            local hf_id = assignment.histfig2
            if hf_id == -1 then goto continue_assignment end

            local hf = df.historical_figure.find(hf_id)
            if not hf then goto continue_assignment end

            local pos_id   = assignment.position_id
            local pos_name = get_pos_name(entity_raw, pos_id, hf)

            dprint('world-leaders:   hf=%s pos=%s alive=%s',
                dfhack.translation.translateName(hf.name, true), tostring(pos_name), tostring(is_alive(hf)))

            if is_alive(hf) then
                if not new_snapshot[entity_id] then
                    new_snapshot[entity_id] = {}
                end
                new_snapshot[entity_id][pos_id] = {
                    hf_id    = hf_id,
                    pos_name = pos_name,
                    civ_name = civ_name,
                }
            end

            local prev_entity = tracked_leaders[entity_id]
            if prev_entity then
                local prev = prev_entity[pos_id]
                if prev then
                    if not is_alive(hf) and prev.hf_id == hf_id then
                        local hf_name = dfhack.translation.translateName(hf.name, true)
                        dprint('world-leaders: death detected: %s, %s of %s', hf_name, tostring(pos_name), civ_name)
                        dfhack.gui.showAnnouncement(fmt_death(hf_name, pos_name, civ_name), COLOR_RED, true)
                    elseif is_alive(hf) and prev.hf_id ~= hf_id then
                        local new_name  = dfhack.translation.translateName(hf.name, true)
                        local prev_hf   = df.historical_figure.find(prev.hf_id)
                        local prev_name = prev_hf
                            and dfhack.translation.translateName(prev_hf.name, true)
                            or  ('HF#' .. tostring(prev.hf_id))
                        dprint('world-leaders: succession: %s -> %s, %s of %s', prev_name, new_name, tostring(pos_name), civ_name)
                        dfhack.gui.showAnnouncement(fmt_succession(new_name, prev_name, pos_name, civ_name), COLOR_YELLOW, true)
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
