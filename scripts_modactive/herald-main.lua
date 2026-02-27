--@ module=true
--@ enable=true

--[====[
herald-main
===========

Tags: fort | gameplay

Command: "herald-main"

  Scans world history for significant events and notifies the player in-game.

Announces leader deaths, succession changes, and other notable events as they happen, without requiring the player to check the legends screen.


Usage
-----

   enable herald-main
   disable herald-main
   herald-main debug [true|false]
   herald-main interval
   herald-main gui
   herald-main button
   herald-main cache-rebuild

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

"herald-main interval"
   Open a dialog to set the scan interval in ticks (minimum 600, half a
   dwarf day). The value is saved to dfhack-config/herald.json and takes
   effect on the next scan cycle.

"herald-main gui"
   Open the Herald settings window (requires a loaded world).

"herald-main button"
   Toggle the Herald overlay button on or off. Persisted by DFHack's overlay
   system so the preference survives restarts.

"herald-main cache-rebuild"
   Invalidate the event cache and instruct the user to reopen the Herald GUI
   to trigger a full rebuild. Use if the cache appears stale or corrupted.

"herald-main test"
   Fire one sample announcement of each style (death, appointment, vacated,
   info) so you can preview colours and pause behaviour in-game.


Examples
--------

"herald-main debug"
   Toggle debug output (flip current state).

"herald-main debug true"
   Force debug output on.

"herald-main debug false"
   Force debug output off.

"herald-main interval"
   Open the interval editor.

"herald-main gui"
   Open the settings UI.

]====]

local GLOBAL_KEY       = 'df_herald'
local CONFIG_PATH      = 'dfhack-config/herald.json'
local MIN_INTERVAL     = 600   -- half a dwarf day
local DEFAULT_INTERVAL = 1200  -- 1 dwarf day

local json    = require('json')
local gui     = require('gui')
local widgets = require('gui.widgets')
local util    = dfhack.reqscript('herald-util')

-- Scan state; reset on each world load.
-- NOTE: last_event_id is actually an array INDEX into df.global.world.history.events,
-- not an event ID. Events are indexed by position (0-based), not by their .id field.
-- The name is historical. It tracks how far we've scanned so far.
local last_event_id = -1      -- array index of last processed event; -1 = uninitialised
local scan_timer_id = nil     -- handle returned by dfhack.timeout
enabled = enabled or false    -- top-level var; DFHack enable/disable convention

-- Named DEBUG (not debug) to avoid shadowing Lua's built-in debug library.
DEBUG = DEBUG or false

-- Global announcement feature flags (distinct from per-pin settings).
-- These control whether an event category is tracked at all.
local DEFAULT_ANNOUNCEMENTS = {
    individuals   = { relationships = true, death = true, combat = true,
                      legendary = true, positions = true, migration = true },
    civilisations = { positions = true, diplomacy = true, warfare = true,
                      raids = true, theft = true, kidnappings = true },
}

-- Merges saved announcement config over defaults; fills any missing keys.
local function merge_announcements(saved)
    local result = util.deepcopy(DEFAULT_ANNOUNCEMENTS)
    if type(saved) ~= 'table' then return result end
    for cat, defaults in pairs(DEFAULT_ANNOUNCEMENTS) do
        if type(saved[cat]) == 'table' then
            for key in pairs(defaults) do
                if type(saved[cat][key]) == 'boolean' then
                    result[cat][key] = saved[cat][key]
                end
            end
        end
    end
    return result
end

-- Config persistence ----------------------------------------------------------

-- Reads dfhack-config/herald.json; returns (interval, debug, announcements).
-- Falls back to defaults on any read/parse failure.
local function load_config()
    local ok, data = pcall(function()
        local f = assert(io.open(CONFIG_PATH, 'r'))
        local s = f:read('*a'); f:close()
        return json.decode(s)
    end)
    if ok and type(data) == 'table' then
        local interval = type(data.tick_interval) == 'number'
            and math.max(MIN_INTERVAL, math.floor(data.tick_interval))
            or  DEFAULT_INTERVAL
        return interval, data.debug == true, merge_announcements(data.announcements)
    end
    return DEFAULT_INTERVAL, false, util.deepcopy(DEFAULT_ANNOUNCEMENTS)
end

-- Writes current tick_interval, DEBUG, and announcements to herald.json.
local function save_config()
    local ok, err = pcall(function()
        local f = assert(io.open(CONFIG_PATH, 'w'))
        f:write(json.encode({
            tick_interval = tick_interval,
            debug         = DEBUG,
            announcements = announcements,
        }))
        f:close()
    end)
    if not ok then
        dfhack.printerr('[Herald] Failed to save config: ' .. tostring(err))
    end
end

-- Boot-time config load. The `or` guards keep values set by a prior load of this
-- script in the same DFHack session (DFHack caches reqscript environments).
do
    local saved_interval, saved_debug, saved_ann = load_config()
    tick_interval = tick_interval or saved_interval
    DEBUG         = DEBUG or saved_debug
    announcements = announcements or saved_ann
end

-- Exported so herald-gui can read/write the global announcement flags.
function get_announcements()
    return announcements
end

function save_announcements(new_ann)
    announcements = new_ann
    save_config()
end

-- Prints to console and (if map loaded) shows a cyan announcement.
-- Only active when DEBUG = true.
local function dprint(fmt, ...)
    if not DEBUG then return end
    local msg = ('[Herald DEBUG] ' .. fmt):format(...)
    print(msg)
    if dfhack.isMapLoaded() then
        util.announce_info(msg)
    end
end

function isEnabled()
    return enabled
end

-- Interval editor dialog ------------------------------------------------------

local IntervalEditor = defclass(IntervalEditor, widgets.Window)
IntervalEditor.ATTRS {
    frame_title = 'Herald: Scan Interval',
    frame       = { w = 44, h = 9 },
    resizable   = false,
}

function IntervalEditor:init()
    self:addviews{
        widgets.Label{
            frame = { t = 0, l = 1 },
            text  = 'Scan interval in ticks (min 600):',
        },
        widgets.EditField{
            view_id = 'input',
            frame   = { t = 2, l = 1, w = 10 },
            text    = tostring(tick_interval),
            on_char = function(ch) return ch:match('%d') ~= nil end,
        },
        widgets.Label{
            frame = { t = 3, l = 1 },
            text  = { {text = '600=half-day  1200=day  8400=week', pen = COLOR_GREY} },
        },
        widgets.Label{
            view_id = 'error_msg',
            frame   = { t = 4, l = 1 },
            text    = '',
        },
        widgets.HotkeyLabel{
            frame       = { b = 0, l = 1 },
            key         = 'SELECT',
            label       = 'Apply',
            auto_width  = true,
            on_activate = function() self:apply() end,
        },
        widgets.HotkeyLabel{
            frame       = { b = 0, r = 1 },
            key         = 'LEAVESCREEN',
            label       = 'Cancel',
            auto_width  = true,
            on_activate = function() self.parent_view:dismiss() end,
        },
    }
end

function IntervalEditor:apply()
    local val = tonumber(self.subviews.input.text)
    if not val or val < MIN_INTERVAL then
        self.subviews.error_msg.text = {text = 'Must be >= 600', pen = COLOR_RED}
        return
    end
    tick_interval = math.floor(val)
    save_config()
    dprint('tick_interval updated to %d', tick_interval)
    self.parent_view:dismiss()
end

local IntervalScreen = defclass(IntervalScreen, gui.ZScreen)
IntervalScreen.ATTRS {
    focus_path = 'herald/interval',
}

function IntervalScreen:init()
    self:addviews{ IntervalEditor{} }
end

function IntervalScreen:onDismiss()
    view = nil
end

-- Event loop ------------------------------------------------------------------
-- Handlers are initialised lazily (after world load) so DF enums are available.
-- To add a new event type: create herald-<type>.lua and register it in get_handlers().
-- To add a new poll-based tracker: register it in get_world_handlers().

local handlers       -- event-driven: { [event_type_enum] = handler_module }
local world_handlers -- poll-based:   { [key_string] = handler_module }

local function get_handlers()
    if handlers then return handlers end
    handlers = {
        [df.history_event_type.HIST_FIGURE_DIED] = dfhack.reqscript('herald-ind-death'),
    }
    dprint('Handlers registered:')
    dprint('  HIST_FIGURE_DIED -> herald-ind-death')
    return handlers
end

local function get_world_handlers()
    if world_handlers then return world_handlers end
    world_handlers = {
        leaders     = dfhack.reqscript('herald-world-leaders'),
        individuals = dfhack.reqscript('herald-ind-death'),
    }
    dprint('World handlers registered:')
    dprint('  leaders -> herald-world-leaders')
    dprint('  individuals -> herald-ind-death')
    return world_handlers
end

-- Calls check(dprint) on every poll-based world handler.
local function scan_world_state(dprint)
    local wh = get_world_handlers()
    for key, handler in pairs(wh) do
        dprint('scan_world_state: calling handler "%s"', key)
        handler.check(dprint)
    end
end

-- Main scan loop: processes new history events then runs all world-state polls.
-- Must reschedule itself at the end; dfhack.timeout fires once only.
-- Any early return would permanently kill the loop, so only return after rescheduling.
local function scan_events()
    if not dfhack.isMapLoaded() then return end

    dprint('Loop triggered at tick %d; scanning from event id %d',
        df.global.cur_year_tick, last_event_id + 1)

    -- events is a 0-indexed DF vector; #events gives count, events[i] is positional.
    -- ev:getType() is a virtual method - NEVER use ev.type (doesn't exist on subtypes).
    local events = df.global.world.history.events
    local h = get_handlers()
    local scanned = 0
    for i = last_event_id + 1, #events - 1 do
        local ev      = events[i]
        local ev_type = ev:getType()
        local handler = h[ev_type]
        if handler then
            dprint('Handler fired: event id=%d type=%s', i, tostring(ev_type))
            handler.check(ev, dprint)
        end
        last_event_id = i
        scanned = scanned + 1
    end
    dprint('Loop complete; scanned %d event(s), last_event_id=%d', scanned, last_event_id)

    scan_world_state(dprint)

    scan_timer_id = dfhack.timeout(tick_interval, 'ticks', scan_events)
end

-- Watermarks last_event_id to the current end of the events array so only future
-- events are processed, then loads pinned data and starts the scan timer.
local function init_scan()
    if enabled then return end  -- guard against double-init
    last_event_id = #df.global.world.history.events - 1  -- skip all pre-existing history
    enabled = true
    dprint('init_scan: watermark set to event id %d', last_event_id)
    dfhack.reqscript('herald-ind-death').load_pinned()
    dprint('init_scan: pinned HF list loaded')
    dfhack.reqscript('herald-world-leaders').load_pinned_civs()
    dprint('init_scan: pinned civ list loaded')
    dfhack.reqscript('herald-cache').load_cache()
    dprint('init_scan: event cache loaded (ready=%s)',
        tostring(dfhack.reqscript('herald-cache').cache_ready))
    scan_timer_id = dfhack.timeout(tick_interval, 'ticks', scan_events)
end

-- Resets all scan state; called on world unload.
-- 'ticks' timers are auto-cancelled by DFHack on unload; nil the handle anyway.
local function cleanup()
    dprint('cleanup: world unloaded, resetting state')
    scan_timer_id = nil
    last_event_id = -1
    enabled = false
    handlers = nil  -- nil forces re-resolution of enums on next load
    if world_handlers then
        for key, handler in pairs(world_handlers) do
            dprint('cleanup: resetting world handler "%s"', key)
            handler.reset()
        end
        world_handlers = nil
    end
    dfhack.reqscript('herald-cache').reset()
    dprint('cleanup: event cache reset')
    dfhack.reqscript('herald-event-history').reset_civ_caches()
    dprint('cleanup: civ caches reset')
end

-- Lifecycle hooks -------------------------------------------------------------

dfhack.onStateChange[GLOBAL_KEY] = function(sc)
    if sc == SC_MAP_LOADED then
        init_scan()
    elseif sc == SC_MAP_UNLOADED then
        cleanup()
    end
end

-- onLoad.init fires after SC_MAP_LOADED; bootstrap immediately if already in a fort.
if dfhack.isMapLoaded() then
    init_scan()
end

-- CLI argument handling -------------------------------------------------------
-- "herald-main debug [true|false]" / "herald-main interval" / "herald-main gui"

local args = {...}
if args[1] == 'debug' then
    if args[2] == 'true' or args[2] == 'on' then
        DEBUG = true
    elseif args[2] == 'false' or args[2] == 'off' then
        DEBUG = false
    else
        DEBUG = not DEBUG
    end
    save_config()
    print('[Herald] Debug ' .. (DEBUG and 'enabled' or 'disabled'))
elseif args[1] == 'interval' then
    view = view and view:raise() or IntervalScreen{}:show()
elseif args[1] == 'gui' then
    if not dfhack.isMapLoaded() then
        dfhack.printerr('[Herald] A fort must be loaded to open the settings UI.')
    else
        dfhack.reqscript('herald-gui').open_gui()
    end
elseif args[1] == 'test' then
    if not dfhack.isMapLoaded() then
        dfhack.printerr('[Herald] A fort must be loaded to test announcements.')
    else
        util.announce_death('[Herald] TEST - Death announcement (red, pauses)')
        util.announce_appointment('[Herald] TEST - Appointment announcement (yellow, pauses)')
        util.announce_vacated('[Herald] TEST - Vacated announcement (white, no pause)')
        util.announce_info('[Herald] TEST - Info announcement (cyan, no pause)')
        print('[Herald] Test announcements fired.')
    end
elseif args[1] == 'cache-rebuild' then
    if not dfhack.isMapLoaded() then
        dfhack.printerr('[Herald] A fort must be loaded to rebuild the cache.')
    else
        dfhack.reqscript('herald-cache').invalidate_cache()
        print('[Herald] Cache cleared. Reopen the Herald GUI to rebuild.')
    end
elseif args[1] == 'button' then
    -- Read current enabled state from DFHack's overlay config, then toggle.
    local WIDGET_ID = 'herald-button.button'
    local currently_enabled = true
    local ok, data = pcall(function()
        local f = assert(io.open('dfhack-config/overlay.json', 'r'))
        local s = f:read('*a'); f:close()
        return json.decode(s)
    end)
    if ok and type(data) == 'table' then
        local entry = data[WIDGET_ID]
        if type(entry) == 'table' and type(entry.enabled) == 'boolean' then
            currently_enabled = entry.enabled
        end
    end
    if currently_enabled then
        dfhack.run_command('overlay', 'disable', WIDGET_ID)
        print('[Herald] Button hidden. Run "herald-main button" again to show it.')
    else
        dfhack.run_command('overlay', 'enable', WIDGET_ID)
        print('[Herald] Button shown.')
    end
end
