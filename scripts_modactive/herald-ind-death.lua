--@ module=true

--[====[
herald-ind-death
================

Tags: fort | gameplay

  Dual-mode handler for pinned individual deaths.

Fires announcements when a pinned historical figure dies. Registered in
both the event-driven path (HIST_FIGURE_DIED) for in-fort deaths and the
poll-based path for off-screen deaths where the game may set hf.died_year
directly without generating a history event.
Not intended for direct use.

]====]

local PERSIST_KEY = 'herald_pinned_hf_ids'

-- { [hf_id] = { death=bool, marriage=bool, children=bool,
--               migration=bool, legendary=bool, combat=bool } }
-- Absent key = not pinned; settings table is truthy so `if pinned[hf_id]` still works.
local pinned_hf_ids = {}

-- HF IDs already announced this session (prevents event+poll double-fire)
local announced_deaths = {}  -- set: { [hf_id] = true }

local SETTINGS_KEYS = { 'death', 'marriage', 'children', 'migration', 'legendary', 'combat' }

-- Hardcoded defaults match DEFAULT_ANNOUNCEMENTS in herald-main.lua.
-- Not using reqscript('herald-main') here to avoid circular dep at load time.
local function default_pin_settings()
    return {
        death     = true,
        marriage  = false,
        children  = false,
        migration = false,
        legendary = false,
        combat    = false,
    }
end

-- Merges a saved settings table with current defaults; fills missing keys.
local function merge_pin_settings(saved)
    local defaults = default_pin_settings()
    if type(saved) ~= 'table' then return defaults end
    for _, k in ipairs(SETTINGS_KEYS) do
        if type(saved[k]) == 'boolean' then
            defaults[k] = saved[k]
        end
    end
    return defaults
end

local function announce_death(hf_id, dprint)
    local settings = pinned_hf_ids[hf_id]
    local hf = df.historical_figure.find(hf_id)
    local name = hf and dfhack.translation.translateName(hf.name, true) or tostring(hf_id)
    if not (settings and settings.death) then
        dprint('ind-death: announcement suppressed for %s (id %d) — death setting is OFF', name, hf_id)
        announced_deaths[hf_id] = true  -- mark seen, suppress repeat
        return
    end
    if not hf then
        dprint('ind-death: no HF found for id %d', hf_id)
        return
    end
    dprint('ind-death: firing announcement for %s (id %d) — death setting is ON', name, hf_id)
    dfhack.gui.showAnnouncement(('[Herald] %s has died.'):format(name), COLOR_RED, true)
    announced_deaths[hf_id] = true
end

local function handle_event(event, dprint)
    dprint = dprint or function() end
    local hf_id = event.victim_hf
    dprint('ind-death.event: HIST_FIGURE_DIED victim hf_id=%d', hf_id)
    if not pinned_hf_ids[hf_id] then
        dprint('ind-death.event: hf_id=%d is not tracked, skipping', hf_id)
        return
    end
    if announced_deaths[hf_id] then
        dprint('ind-death.event: hf_id=%d already announced, skipping', hf_id)
        return
    end
    dprint('ind-death.event: hf_id=%d is tracked, checking settings', hf_id)
    announce_death(hf_id, dprint)
end

local function handle_poll(dprint)
    dprint = dprint or function() end
    for hf_id in pairs(pinned_hf_ids) do
        if not announced_deaths[hf_id] then
            local hf = df.historical_figure.find(hf_id)
            if hf and hf.died_year ~= -1 then
                dprint('ind-death.poll: detected death of tracked hf_id=%d via died_year, checking settings', hf_id)
                announce_death(hf_id, dprint)
            end
        end
    end
end

function check(event_or_dprint, dprint_or_nil)
    if dprint_or_nil ~= nil then
        -- event mode: called as check(event, dprint)
        handle_event(event_or_dprint, dprint_or_nil)
    else
        -- poll mode: called as check(dprint)
        handle_poll(event_or_dprint)
    end
end

function load_pinned()
    local data = dfhack.persistent.getSiteData(PERSIST_KEY, {})
    pinned_hf_ids = {}
    if type(data.pins) == 'table' then
        for _, entry in ipairs(data.pins) do
            if type(entry.id) == 'number' then
                pinned_hf_ids[entry.id] = merge_pin_settings(entry.settings)
            end
        end
    end
end

function save_pinned()
    local pins = {}
    for id, settings in pairs(pinned_hf_ids) do
        table.insert(pins, { id = id, settings = settings })
    end
    dfhack.persistent.saveSiteData(PERSIST_KEY, { pins = pins })
end

function get_pinned()
    return pinned_hf_ids
end

function set_pinned(hf_id, value)
    if value then
        pinned_hf_ids[hf_id] = default_pin_settings()
    else
        pinned_hf_ids[hf_id] = nil
    end
    save_pinned()
end

-- Returns the per-pin settings table for hf_id, or nil if not pinned.
function get_pin_settings(hf_id)
    return pinned_hf_ids[hf_id]
end

-- Updates one announcement key for a pinned HF and persists.
function set_pin_setting(hf_id, key, value)
    if pinned_hf_ids[hf_id] then
        pinned_hf_ids[hf_id][key] = value
        save_pinned()
    end
end

function reset()
    announced_deaths = {}
    -- pinned_hf_ids is per-save config; reloaded by load_pinned() on SC_MAP_LOADED
end
