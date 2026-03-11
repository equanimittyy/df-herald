--@ module=true

--[====[
herald-ind-death
================

Tags: dev

  Dual-mode handler for pinned individual deaths.

Fires announcements when a pinned historical figure dies. Registered in
both the event-driven path (HIST_FIGURE_DIED) for in-fort deaths and the
poll-based path for off-screen deaths where the game may set hf.died_year
directly without generating a history event.
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local pins = dfhack.reqscript('herald-pins')

-- HF IDs announced this session; prevents double-fire when both event and poll paths fire.
local announced_deaths = {}  -- set: { [hf_id] = true }

-- Announcement ----------------------------------------------------------------

-- Fires (or suppresses) a death announcement based on the pin's death setting.
-- Always marks hf_id in announced_deaths so the other path doesn't re-fire.
local function announce_death(hf_id, dprint)
    local settings = pins.get_pinned()[hf_id]
    local hf = df.historical_figure.find(hf_id)
    local name = hf and dfhack.translation.translateName(hf.name, true) or tostring(hf_id)
    if not (settings and settings.death) then
        dprint('ind-death: announcement suppressed for %s (id %d) - death setting is OFF', name, hf_id)
        announced_deaths[hf_id] = true
        return
    end
    -- Mark before the nil guard so a cleaned-up HF struct doesn't cause
    -- repeated nil-lookups on every poll tick.
    announced_deaths[hf_id] = true
    dprint('ind-death: firing announcement for %s (id %d) - death setting is ON', name, hf_id)
    util.announce_death(('%s has died.'):format(name))
end

-- Event handler (in-fort path) ------------------------------------------------
-- Called by herald when a HIST_FIGURE_DIED event is dispatched.

local function handle_event(event, dprint)
    -- HIST_FIGURE_DIED event: victim_hf is the HF ID of the deceased (not pcall-guarded
    -- because this handler only receives events of the correct type from the dispatcher).
    local hf_id = event.victim_hf
    dprint('ind-death.event: HIST_FIGURE_DIED victim hf_id=%d', hf_id)
    if not pins.get_pinned()[hf_id] then
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
    for hf_id in pairs(pins.get_pinned()) do
        if not announced_deaths[hf_id] then
            local hf = df.historical_figure.find(hf_id)
            if hf and not util.is_alive(hf) then
                dprint('ind-death.poll: detected death of tracked hf_id=%d', hf_id)
                announce_death(hf_id, dprint)
            end
        end
    end
end

-- BODY_ABUSED victim handler --------------------------------------------------
-- When a pinned HF's corpse appears in the bodies vector, announce as
-- death-adjacent (red, gated by death setting). The abuser path is
-- handled by ind-combat.

local function handle_body_abused(ev, dprint)
    local bodies = util.safe_get(ev, 'bodies')
    if not bodies then return end
    local pinned = pins.get_pinned()
    for i = 0, #bodies - 1 do
        local ok_b, body = pcall(function() return bodies[i] end)
        if not ok_b or not body then goto next_body end
        local victim_hf = util.safe_get(body, 'histfig_id')
            or util.safe_get(body, 'hfid')
            or util.safe_get(body, 'histfig')
        if victim_hf and pinned[victim_hf] then
            local settings = pinned[victim_hf]
            if settings and settings.death then
                local hf = df.historical_figure.find(victim_hf)
                local name = hf
                    and dfhack.translation.translateName(hf.name, true)
                    or tostring(victim_hf)
                util.announce_death(("%s's corpse was desecrated."):format(name))
            end
            return
        end
        ::next_body::
    end
end

-- Public interface ------------------------------------------------------------

-- Event-driven path: called by herald for HIST_FIGURE_DIED / BODY_ABUSED events.
function check_event(event, dprint)
    if event:getType() == df.history_event_type.BODY_ABUSED then
        handle_body_abused(event, dprint)
    else
        handle_event(event, dprint)
    end
end

-- Poll-based path: called each scan cycle by herald.
function check_poll(dprint)
    handle_poll(dprint)
end

-- Handler contract -------------------------------------------------------------

event_types = { df.history_event_type.HIST_FIGURE_DIED, df.history_event_type.BODY_ABUSED }
polls = true

function init(dprint)
    dprint('ind-death: handler initialised')
end

function reset()
    announced_deaths = {}
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
