--@ module=true

--[====[
herald-ind-death
================

Tags: fort | gameplay

  Dual-mode handler for tracked individual deaths.

Fires announcements when a tracked historical figure dies. Registered in
both the event-driven path (HIST_FIGURE_DIED) for in-fort deaths and the
poll-based path for off-screen deaths where the game may set hf.died_year
directly without generating a history event.
Not intended for direct use.

]====]

local PERSIST_KEY = 'herald_tracked_hf_ids'

local tracked_hf_ids = {}   -- set: { [hf_id] = true }

-- HF IDs already announced this session (prevents event+poll double-fire)
local announced_deaths = {}  -- set: { [hf_id] = true }

local function announce_death(hf_id, dprint)
    local hf = df.historical_figure.find(hf_id)
    if not hf then
        dprint('ind-death: no HF found for id %d', hf_id)
        return
    end
    local name = dfhack.translation.translateName(hf.name, true)
    dprint('ind-death: announcing death of %s (id %d)', name, hf_id)
    dfhack.gui.showAnnouncement(('[Herald] %s has died.'):format(name), COLOR_RED, true)
    announced_deaths[hf_id] = true
end

local function handle_event(event, dprint)
    dprint = dprint or function() end
    local hf_id = event.victim_hf
    dprint('ind-death.event: HIST_FIGURE_DIED victim hf_id=%d', hf_id)
    if tracked_hf_ids[hf_id] and not announced_deaths[hf_id] then
        announce_death(hf_id, dprint)
    end
end

local function handle_poll(dprint)
    dprint = dprint or function() end
    for hf_id in pairs(tracked_hf_ids) do
        if not announced_deaths[hf_id] then
            local hf = df.historical_figure.find(hf_id)
            if hf and hf.died_year ~= -1 then
                dprint('ind-death.poll: detected death of hf_id=%d via died_year', hf_id)
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

function load_tracked()
    local data = dfhack.persistent.getSiteData(PERSIST_KEY, {})
    tracked_hf_ids = {}
    if type(data.ids) == 'table' then
        for _, id in ipairs(data.ids) do tracked_hf_ids[id] = true end
    end
end

function save_tracked()
    local ids = {}
    for id in pairs(tracked_hf_ids) do table.insert(ids, id) end
    dfhack.persistent.saveSiteData(PERSIST_KEY, { ids = ids })
end

function get_tracked()
    return tracked_hf_ids
end

function set_tracked(hf_id, value)
    tracked_hf_ids[hf_id] = value or nil
    save_tracked()
end

function reset()
    announced_deaths = {}
    -- tracked_hf_ids is per-save config; reloaded by load_tracked() on SC_MAP_LOADED
end
