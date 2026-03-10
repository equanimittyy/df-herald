--@ module=true

--[====[
herald-ind-migration
====================

Tags: dev

  Hybrid event+poll handler for pinned individual migration events.

Fires announcements when a pinned HF relocates (world-level events) or
arrives at the player's fortress (fort-level poll).
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local pins = dfhack.reqscript('herald-pins')

-- Dedup set keyed by event.id; prevents duplicate announcements.
local announced_migrations = {}

-- Fort-level tracking: { [hf_id] = 'present' | 'absent' }
local seen_on_map = {}

-- Helpers ---------------------------------------------------------------------

local function hf_name(hf_id)
    return util.hf_name(hf_id)
end

local site_name = util.site_name

local function migration_enabled(settings)
    return settings and settings.migration
end

-- Fires a migration announcement if not already announced for this event.
local function fire(ev_id, msg, dprint)
    if announced_migrations[ev_id] then
        dprint('ind-migration: event %d already announced, skipping', ev_id)
        return
    end
    announced_migrations[ev_id] = true
    util.announce_migration(msg)
end

-- Event handlers --------------------------------------------------------------

local function handle_change_hf_state(ev, dprint)
    local pinned = pins.get_pinned()
    local hf_id = util.safe_get(ev, 'hfid') or -1
    if hf_id < 0 then return end
    if not pinned[hf_id] or not migration_enabled(pinned[hf_id]) then return end

    local state    = util.safe_get(ev, 'state')
    local substate = util.safe_get(ev, 'substate')
    local site_id  = util.safe_get(ev, 'site')
    local reason   = util.safe_get(ev, 'reason')
    local loc      = site_name(site_id)
    local name     = hf_name(hf_id)

    -- Integer fallback for state enum (enum lookup often unavailable)
    local sname
    local state_int = state ~= nil and tonumber(state)
    if state_int and state_int >= 0 then
        for _, epath in ipairs({'hang_around_location_type', 'histfig_state'}) do
            local ok, en = pcall(function() return df[epath] end)
            if ok and en then
                local n = en[state_int]
                if n then sname = n; break end
            end
        end
        if not sname then
            local STATE_INT = {
                [0]='VISITING', [1]='SETTLED', [2]='WANDERING',
                [3]='REFUGEE',
            }
            sname = STATE_INT[state_int]
        end
    end

    if not sname then return end

    if sname == 'SETTLED' then
        -- Check substates for specific messages
        if substate == 45 then
            fire(ev.id, ('%s has fled to %s.'):format(name, loc), dprint)
            return
        elseif substate == 46 or substate == 47 then
            fire(ev.id, ('%s moved to study in %s.'):format(name, loc), dprint)
            return
        end
        -- Reason suffix
        local sfx = ''
        if reason ~= nil then
            local rname = df.history_event_reason and df.history_event_reason[reason]
            if rname == 'FLIGHT' then sfx = ' in order to flee'
            elseif rname == 'SCHOLARSHIP' then sfx = ' to pursue scholarship'
            elseif rname == 'EXILED_AFTER_CONVICTION' then sfx = ' after being exiled'
            end
        end
        fire(ev.id, ('%s has settled in %s%s.'):format(name, loc, sfx), dprint)
    elseif sname == 'WANDERING' then
        fire(ev.id, ('%s began wandering.'):format(name), dprint)
    elseif sname == 'REFUGEE' then
        fire(ev.id, ('%s became a refugee in %s.'):format(name, loc), dprint)
    end
    -- VISITING is too noisy; skip it
end

local function handle_add_site_link(ev, dprint)
    local pinned = pins.get_pinned()
    local hf_id = util.safe_get(ev, 'histfig') or -1
    if hf_id < 0 then return end
    if not pinned[hf_id] or not migration_enabled(pinned[hf_id]) then return end

    local site_id = util.safe_get(ev, 'site')
    local ltype   = util.safe_get(ev, 'link_type')
    local loc     = site_name(site_id)
    local name    = hf_name(hf_id)

    local LST = df.histfig_site_link_type
    local msg
    if LST then
        if ltype == LST.LAIR then
            msg = ('%s made %s their lair.'):format(name, loc)
        elseif ltype == LST.HANGOUT then
            msg = ('%s made %s their hangout.'):format(name, loc)
        elseif ltype == LST.HOME_SITE_BUILDING or ltype == LST.HOME_SITE_ABSTRACT_BUILDING then
            msg = ('%s moved to %s.'):format(name, loc)
        elseif ltype == LST.OCCUPATION then
            msg = ('%s took up occupation at %s.'):format(name, loc)
        end
    end
    if not msg then
        msg = ('%s established connection at %s.'):format(name, loc)
    end
    fire(ev.id, msg, dprint)
end

local function handle_remove_site_link(ev, dprint)
    local pinned = pins.get_pinned()
    local hf_id = util.safe_get(ev, 'histfig') or -1
    if hf_id < 0 then return end
    if not pinned[hf_id] or not migration_enabled(pinned[hf_id]) then return end

    local site_id = util.safe_get(ev, 'site')
    local ltype   = util.safe_get(ev, 'link_type')
    local loc     = site_name(site_id)
    local name    = hf_name(hf_id)

    local LST = df.histfig_site_link_type
    local msg
    if LST then
        if ltype == LST.LAIR then
            msg = ('%s abandoned %s as their lair.'):format(name, loc)
        elseif ltype == LST.HANGOUT then
            msg = ('%s left %s as their hangout.'):format(name, loc)
        elseif ltype == LST.HOME_SITE_BUILDING or ltype == LST.HOME_SITE_ABSTRACT_BUILDING then
            msg = ('%s left their home at %s.'):format(name, loc)
        elseif ltype == LST.OCCUPATION then
            msg = ('%s left their occupation at %s.'):format(name, loc)
        end
    end
    if not msg then
        msg = ('%s lost connection to %s.'):format(name, loc)
    end
    fire(ev.id, msg, dprint)
end

-- Dispatch table keyed by history_event_type enum value.
local dispatch = {}

local function register_dispatch()
    local T = df.history_event_type
    local map = {
        {T.CHANGE_HF_STATE,      handle_change_hf_state},
        {T.ADD_HF_SITE_LINK,     handle_add_site_link},
        {T.REMOVE_HF_SITE_LINK,  handle_remove_site_link},
    }
    for _, entry in ipairs(map) do
        if entry[1] then dispatch[entry[1]] = entry[2] end
    end
end

local function build_event_types()
    local T = df.history_event_type
    local candidates = {
        T.CHANGE_HF_STATE,
        T.ADD_HF_SITE_LINK,
        T.REMOVE_HF_SITE_LINK,
    }
    local result = {}
    for _, et in ipairs(candidates) do
        if et then table.insert(result, et) end
    end
    return result
end

-- Fort-level poll: detect pinned HFs arriving/leaving the map ----------------

local function handle_poll(dprint)
    local ok, active = pcall(function() return df.global.world.units.active end)
    if not ok or not active then return end

    local pinned = pins.get_pinned()

    -- Build set of pinned HFs currently on the active list
    local on_map = {}
    for i = 0, #active - 1 do
        local unit = active[i]
        if not unit then goto continue end
        local ok_hf, hf_id = pcall(function() return unit.hist_figure_id end)
        if not ok_hf or not hf_id or hf_id < 0 then goto continue end
        if pinned[hf_id] and migration_enabled(pinned[hf_id]) then
            on_map[hf_id] = true
        end
        ::continue::
    end

    -- Check for arrivals and departures
    for hf_id, settings in pairs(pinned) do
        if not migration_enabled(settings) then goto next_hf end

        local prev = seen_on_map[hf_id]
        local now  = on_map[hf_id]

        if now then
            if not prev then
                -- First observation: set baseline silently
                seen_on_map[hf_id] = 'present'
                dprint('ind-migration.poll: hf %d baseline set to present', hf_id)
            elseif prev == 'absent' then
                -- Returned after being absent
                seen_on_map[hf_id] = 'present'
                local name = hf_name(hf_id)
                util.announce_migration(('%s has arrived at the fortress.'):format(name))
                dprint('ind-migration.poll: hf %d (%s) arrived', hf_id, name)
            end
        else
            if prev == 'present' then
                -- Was here, now gone
                seen_on_map[hf_id] = 'absent'
                local name = hf_name(hf_id)
                util.announce_migration(('%s has left the fortress.'):format(name))
                dprint('ind-migration.poll: hf %d (%s) departed', hf_id, name)
            end
        end

        ::next_hf::
    end

    -- Prune entries for HFs no longer pinned
    for hf_id in pairs(seen_on_map) do
        if not pinned[hf_id] then
            seen_on_map[hf_id] = nil
        end
    end
end

-- Contract fields -------------------------------------------------------------

event_types = build_event_types()
polls = true

function init(dprint)
    register_dispatch()
    announced_migrations = {}
    seen_on_map = {}
    dprint('ind-migration: handler initialised')
end

function reset()
    announced_migrations = {}
    seen_on_map = {}
end

function check_event(ev, dprint)
    local handler = dispatch[ev:getType()]
    if handler then
        handler(ev, dprint)
    end
end

function check_poll(dprint)
    handle_poll(dprint)
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
