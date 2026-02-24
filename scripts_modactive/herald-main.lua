-- herald-main.lua
-- Event loop and dispatcher for Dwarf Fortress Herald.
-- Loaded automatically via scripts_modactive/onLoad.init.

--@ module=true
--@ enable=true

--[====[
herald-main
===========

Tags: fort | gameplay

Command: "herald-main"

  Scans world history for significant events and notifies the player in-game.

Announces leader deaths, succession changes, and other notable events as they
happen, without requiring the player to check the legends screen.


Usage
-----

   enable herald-main
   disable herald-main
   herald-main debug [true|false]


Commands
--------

"enable herald-main"
   Start watching for events (done automatically on world load).

"disable herald-main"
   Stop watching for events.

"herald-main debug [true|false]"
   Toggle debug output on/off, or set it explicitly. Omit the argument to
   flip the current state. Debug lines appear in both the DFHack console
   and the in-game announcements log (highlighted in cyan), covering loop
   timing, handler registration, handler dispatch, and per-handler event
   details (e.g. leader-death resolution).


Examples
--------

"herald-main debug"
   Toggle debug output (flip current state).

"herald-main debug true"
   Force debug output on.

"herald-main debug false"
   Force debug output off.

]====]

local GLOBAL_KEY    = 'df_herald'
local TICK_INTERVAL = 1200    -- 1 dwarf day in unpaused ticks

local last_event_id = -1      -- ID of last processed event; -1 = uninitialised
local scan_timer_id = nil     -- handle returned by dfhack.timeout
enabled = enabled or false    -- top-level var; DFHack enable/disable convention

-- Debug flag. Controlled via the launcher or console:
--   herald-main debug [true|false]
-- Named DEBUG (not debug) to avoid shadowing Lua's built-in debug library.
DEBUG = DEBUG or false

-- Internal helper: prints a formatted debug line when DEBUG=true.
-- Outputs to both the DFHack console and the in-game announcements log.
-- Passed to handler.check(ev, dprint) so handlers share the same flag.
local function dprint(fmt, ...)
    if not DEBUG then return end
    local msg = ('[Herald DEBUG] ' .. fmt):format(...)
    print(msg)
    if dfhack.isMapLoaded() then
        dfhack.gui.showAnnouncement(msg, COLOR_LIGHTCYAN)
    end
end

function isEnabled()
    return enabled
end

-- Map event type enum → handler module. Add new handlers here as new event
-- types are implemented (e.g. herald-battle.lua, herald-artifact.lua).
-- Fort handlers: check(event, dprint) — called once per matching event.
local handlers -- initialised lazily after world load so enums are available

local function get_handlers()
    if handlers then return handlers end
    handlers = {
        [df.history_event_type.HIST_FIGURE_DIED] = dfhack.reqscript('herald-fort-death'),
    }
    dprint('Handlers registered:')
    dprint('  HIST_FIGURE_DIED -> herald-fort-death')
    return handlers
end

-- World handlers: check(dprint) — called once per scan cycle; manage own state.
-- Also export reset() which is called on world unload.
local world_handlers -- initialised lazily

local function get_world_handlers()
    if world_handlers then return world_handlers end
    world_handlers = {
        leaders = dfhack.reqscript('herald-world-leaders'),
    }
    dprint('World handlers registered:')
    dprint('  leaders -> herald-world-leaders')
    return world_handlers
end

local function scan_world_state(dprint)
    local wh = get_world_handlers()
    for key, handler in pairs(wh) do
        dprint('scan_world_state: calling handler "%s"', key)
        handler.check(dprint)
    end
end

local function scan_events()
    if not dfhack.isMapLoaded() then return end

    dprint('Loop triggered at tick %d; scanning from event id %d',
        df.global.cur_year_tick, last_event_id + 1)

    local events = df.global.world.history.events
    local h = get_handlers()
    local scanned = 0
    for i = last_event_id + 1, #events - 1 do
        local ev      = events[i]
        local ev_type = ev:getType()
        local handler = h[ev_type]
        if handler then
            dprint('Handler fired: event id=%d type=%s -> herald-fort-death', i, tostring(ev_type))
            handler.check(ev, dprint)
        end
        last_event_id = i
        scanned = scanned + 1
    end
    dprint('Loop complete; scanned %d event(s), last_event_id=%d', scanned, last_event_id)

    scan_world_state(dprint)

    scan_timer_id = dfhack.timeout(TICK_INTERVAL, 'ticks', scan_events)
end

local function init_scan()
    if enabled then return end  -- guard against double-init
    last_event_id = #df.global.world.history.events - 1  -- watermark: skip old history
    enabled = true
    dprint('init_scan: watermark set to event id %d', last_event_id)
    scan_timer_id = dfhack.timeout(TICK_INTERVAL, 'ticks', scan_events)
end

local function cleanup()
    -- 'ticks' timers are auto-cancelled on world unload; nil out the handle anyway
    dprint('cleanup: world unloaded, resetting state')
    scan_timer_id = nil
    last_event_id = -1
    enabled = false
    handlers = nil  -- reset so enums are re-resolved on next load
    if world_handlers then
        for key, handler in pairs(world_handlers) do
            dprint('cleanup: resetting world handler "%s"', key)
            handler.reset()
        end
        world_handlers = nil
    end
end

dfhack.onStateChange[GLOBAL_KEY] = function(sc)
    if sc == SC_MAP_LOADED then
        init_scan()
    elseif sc == SC_MAP_UNLOADED then
        cleanup()
    end
end

-- onLoad.init fires after SC_MAP_LOADED, so bootstrap immediately if map is already up
if dfhack.isMapLoaded() then
    init_scan()
end

-- Handle direct invocation: "herald-main debug [true|false]"
local args = {...}
if args[1] == 'debug' then
    if args[2] == 'true' or args[2] == 'on' then
        DEBUG = true
    elseif args[2] == 'false' or args[2] == 'off' then
        DEBUG = false
    else
        DEBUG = not DEBUG
    end
    print('[Herald] Debug ' .. (DEBUG and 'enabled' or 'disabled'))
end
