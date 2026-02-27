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

local util = dfhack.reqscript('herald-util')

local PERSIST_KEY = 'herald_pinned_hf_ids'

-- { [hf_id] = settings_table }
-- Absent key = not pinned. The settings table is truthy, so `if pinned[hf_id]` still works.
local pinned_hf_ids = {}

-- HF IDs announced this session; prevents double-fire when both event and poll paths fire.
local announced_deaths = {}  -- set: { [hf_id] = true }

-- Announcement ----------------------------------------------------------------

-- Fires (or suppresses) a death announcement based on the pin's death setting.
-- Always marks hf_id in announced_deaths so the other path doesn't re-fire.
local function announce_death(hf_id, dprint)
    local settings = pinned_hf_ids[hf_id]
    local hf = df.historical_figure.find(hf_id)
    local name = hf and dfhack.translation.translateName(hf.name, true) or tostring(hf_id)
    if not (settings and settings.death) then
        dprint('ind-death: announcement suppressed for %s (id %d) - death setting is OFF', name, hf_id)
        announced_deaths[hf_id] = true
        return
    end
    if not hf then
        dprint('ind-death: no HF found for id %d', hf_id)
        return
    end
    dprint('ind-death: firing announcement for %s (id %d) - death setting is ON', name, hf_id)
    util.announce_death(('[Herald] %s has died.'):format(name))
    announced_deaths[hf_id] = true
end

-- Event handler (in-fort path) ------------------------------------------------
-- Called by herald-main when a HIST_FIGURE_DIED event is dispatched.

local function handle_event(event, dprint)
    dprint = dprint or function() end
    -- HIST_FIGURE_DIED event: victim_hf is the HF ID of the deceased (not pcall-guarded
    -- because this handler only receives events of the correct type from the dispatcher).
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

-- Poll handler (off-screen path) ----------------------------------------------
-- Called each scan cycle. Catches deaths the game applies directly to hf.died_year
-- without emitting a history event (common for off-screen/out-of-fort deaths).

local function handle_poll(dprint)
    dprint = dprint or function() end
    for hf_id in pairs(pinned_hf_ids) do
        if not announced_deaths[hf_id] then
            local hf = df.historical_figure.find(hf_id)
            if hf and not util.is_alive(hf) then
                dprint('ind-death.poll: detected death of tracked hf_id=%d', hf_id)
                announce_death(hf_id, dprint)
            end
        end
    end
end

-- Public interface ------------------------------------------------------------

-- Dispatches to event or poll path depending on call signature:
--   check(event, dprint)  -> event-driven (HIST_FIGURE_DIED)
--   check(dprint)         -> poll-based (each scan cycle)
function check(event_or_dprint, dprint_or_nil)
    if dprint_or_nil ~= nil then
        handle_event(event_or_dprint, dprint_or_nil)
    else
        handle_poll(event_or_dprint)
    end
end

-- Persistence -----------------------------------------------------------------

function load_pinned()
    local data = dfhack.persistent.getSiteData(PERSIST_KEY, {})
    pinned_hf_ids = {}
    if type(data.pins) == 'table' then
        for _, entry in ipairs(data.pins) do
            if type(entry.id) == 'number' then
                pinned_hf_ids[entry.id] = util.merge_pin_settings(entry.settings)
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

-- Pin management --------------------------------------------------------------

function get_pinned()
    return pinned_hf_ids
end

-- Pins (true) or unpins (nil/false) an HF; persists immediately.
function set_pinned(hf_id, value)
    if value then
        pinned_hf_ids[hf_id] = util.default_pin_settings()
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

-- Clears per-session state on world unload (pinned list is reloaded on next load).
function reset()
    announced_deaths = {}
end
