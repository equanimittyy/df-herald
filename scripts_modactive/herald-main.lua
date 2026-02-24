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
   herald-main interval


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

]====]

local GLOBAL_KEY       = 'df_herald'
local CONFIG_PATH      = 'dfhack-config/herald.json'
local MIN_INTERVAL     = 600   -- half a dwarf day
local DEFAULT_INTERVAL = 1200  -- 1 dwarf day

local json    = require('json')
local gui     = require('gui')
local widgets = require('gui.widgets')

local last_event_id = -1      -- ID of last processed event; -1 = uninitialised
local scan_timer_id = nil     -- handle returned by dfhack.timeout
enabled = enabled or false    -- top-level var; DFHack enable/disable convention

-- Named DEBUG (not debug) to avoid shadowing Lua's built-in debug library.
DEBUG = DEBUG or false

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
        return interval, data.debug == true
    end
    return DEFAULT_INTERVAL, false
end

local function save_config()
    local ok, err = pcall(function()
        local f = assert(io.open(CONFIG_PATH, 'w'))
        f:write(json.encode({ tick_interval = tick_interval, debug = DEBUG }))
        f:close()
    end)
    if not ok then
        dfhack.printerr('[Herald] Failed to save config: ' .. tostring(err))
    end
end

do
    local saved_interval, saved_debug = load_config()
    tick_interval = tick_interval or saved_interval
    DEBUG = DEBUG or saved_debug
end

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

-- Interval editor dialog -------------------------------------------------------

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

-- Event loop -------------------------------------------------------------------

-- add new event-type handlers here (e.g. herald-battle.lua)
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

    scan_timer_id = dfhack.timeout(tick_interval, 'ticks', scan_events)
end

local function init_scan()
    if enabled then return end  -- guard against double-init
    last_event_id = #df.global.world.history.events - 1  -- watermark: skip old history
    enabled = true
    dprint('init_scan: watermark set to event id %d', last_event_id)
    scan_timer_id = dfhack.timeout(tick_interval, 'ticks', scan_events)
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

-- Handle direct invocation: "herald-main debug [true|false]" / "herald-main interval"
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
end
