--@ module=true

--[====[
herald-ind-positions
====================

Tags: dev

  Poll-based handler for pinned individual position tracking.

Detects position appointments and vacations for pinned HFs by walking
entity_links each cycle and comparing against the previous snapshot.
Covers both civ-level (King, General) and fort-level (Mayor, Manager)
positions via POSITION entity links.
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local pins = dfhack.reqscript('herald-pins')

-- { [hf_id] = { ["entity_id:assignment_id"] = { entity_id, assignment_id, pos_name, civ_name } } }
local position_snapshots = {}

-- Announcement formatting -----------------------------------------------------

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
    return ('%s no longer holds a position in %s.'):format(hf_name, civ_name)
end

-- Builds current position snapshot for a single HF by walking entity_links.
-- Returns snap, ok.  On partial failure returns nil, false so callers can
-- preserve the previous snapshot instead of replacing with incomplete data.
local function build_hf_snapshot(hf)
    local ok_links, links = pcall(function() return hf.entity_links end)
    if not ok_links or not links then return nil, false end

    local snap = {}
    local ok = pcall(function()
        for _, link in ipairs(links) do
            local ltype = link:getType()
            if ltype ~= df.histfig_entity_link_type.POSITION then
                goto next_link
            end
            local entity = df.historical_entity.find(link.entity_id)
            if not entity then goto next_link end

            local assignments = entity.positions.assignments
            if not assignments then goto next_link end

            local civ_name = dfhack.translation.translateName(entity.name, true)
            if not civ_name or civ_name == '' then civ_name = tostring(link.entity_id) end

            for _, asgn in ipairs(assignments) do
                if asgn.histfig2 == -1 then goto next_asgn end
                if asgn.histfig2 == hf.id then
                    local key = link.entity_id .. ':' .. asgn.id
                    snap[key] = {
                        entity_id     = link.entity_id,
                        assignment_id = asgn.id,
                        pos_name      = util.get_pos_name(entity, asgn.position_id, hf.sex),
                        civ_name      = civ_name,
                    }
                end
                ::next_asgn::
            end

            ::next_link::
        end
    end)
    return ok and snap or nil, ok
end

-- Poll handler ----------------------------------------------------------------

local function handle_poll(dprint)
    local pinned = pins.get_pinned()
    local new_snapshots = {}
    local dbg_tracked = 0

    for hf_id, settings in pairs(pinned) do
        local hf = df.historical_figure.find(hf_id)
        if not hf or not util.is_alive(hf) then goto next_hf end

        local current, snap_ok = build_hf_snapshot(hf)
        if not snap_ok then
            -- Partial failure; preserve previous snapshot to avoid false vacated
            new_snapshots[hf_id] = position_snapshots[hf_id]
            goto next_hf
        end
        new_snapshots[hf_id] = current
        dbg_tracked = dbg_tracked + 1

        local prev = position_snapshots[hf_id]
        if not prev then
            -- First observation: baseline silently
            local n = 0
            for _ in pairs(current) do n = n + 1 end
            dprint('ind-positions: baseline for hf %d: %d positions', hf_id, n)
            goto next_hf
        end

        local hf_name = dfhack.translation.translateName(hf.name, true) or ('HF ' .. hf_id)

        -- Detect new appointments
        for key, entry in pairs(current) do
            if not prev[key] then
                if settings and settings.positions then
                    dprint('ind-positions: appointment for %s (%s of %s)',
                        hf_name, tostring(entry.pos_name), entry.civ_name)
                    util.announce_appointment(fmt_appointment(hf_name, entry.pos_name, entry.civ_name))
                else
                    dprint('ind-positions: appointment for %s (%s of %s) - suppressed (positions OFF)',
                        hf_name, tostring(entry.pos_name), entry.civ_name)
                end
            end
        end

        -- Detect vacated positions
        for key, entry in pairs(prev) do
            if not current[key] then
                if settings and settings.positions then
                    dprint('ind-positions: vacated for %s (%s of %s)',
                        hf_name, tostring(entry.pos_name), entry.civ_name)
                    util.announce_vacated(fmt_vacated(hf_name, entry.pos_name, entry.civ_name))
                else
                    dprint('ind-positions: vacated for %s (%s of %s) - suppressed (positions OFF)',
                        hf_name, tostring(entry.pos_name), entry.civ_name)
                end
            end
        end

        ::next_hf::
    end

    position_snapshots = new_snapshots
    dprint('ind-positions.poll: tracked %d pinned HFs', dbg_tracked)
end

-- Contract fields -------------------------------------------------------------

polls = true

-- Set position baselines immediately at map load.
local function set_initial_baselines(dprint)
    local pinned = pins.get_pinned()
    for hf_id, _ in pairs(pinned) do
        local hf = df.historical_figure.find(hf_id)
        if not hf or not util.is_alive(hf) then goto next_hf end
        local snap, snap_ok = build_hf_snapshot(hf)
        if not snap_ok then goto next_hf end
        position_snapshots[hf_id] = snap
        local n = 0
        for _ in pairs(snap) do n = n + 1 end
        dprint('ind-positions.init: baseline for hf %d: %d positions', hf_id, n)
        ::next_hf::
    end
end

function init(dprint)
    position_snapshots = {}
    set_initial_baselines(dprint)
    dprint('ind-positions: handler initialised')
end

function reset()
    position_snapshots = {}
end

function check_poll(dprint)
    handle_poll(dprint)
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
