-- herald-main.lua
-- Event loop and dispatcher for Dwarf Fortress Herald.
-- Loaded automatically via scripts_modactive/onLoad.init.

local GLOBAL_KEY    = 'df_herald'
local TICK_INTERVAL = 1200    -- 1 dwarf day in unpaused ticks

local last_event_id = -1      -- ID of last processed event; -1 = uninitialised
local scan_timer_id = nil     -- handle returned by dfhack.timeout
enabled = enabled or false    -- top-level var; DFHack enable/disable convention

function isEnabled()
    return enabled
end

-- Map event type enum → handler module. Add new handlers here as new event
-- types are implemented (e.g. herald-battle.lua, herald-artifact.lua).
local handlers -- initialised lazily after world load so enums are available

local function get_handlers()
    if handlers then return handlers end
    handlers = {
        [df.history_event_type.HIST_FIGURE_DIED] = dfhack.reqscript('herald-death'),
    }
    return handlers
end

local function scan_events()
    if not dfhack.isMapLoaded() then return end

    local events = df.global.world.history.events
    local h = get_handlers()
    for i = last_event_id + 1, #events - 1 do
        local ev      = events[i]
        local handler = h[ev:getType()]
        if handler then handler.check(ev) end
        last_event_id = i
    end

    scan_timer_id = dfhack.timeout(TICK_INTERVAL, 'ticks', scan_events)
end

local function init_scan()
    if enabled then return end  -- guard against double-init
    last_event_id = #df.global.world.history.events - 1  -- watermark: skip old history
    enabled = true
    scan_timer_id = dfhack.timeout(TICK_INTERVAL, 'ticks', scan_events)
end

local function cleanup()
    -- 'ticks' timers are auto-cancelled on world unload; nil out the handle anyway
    scan_timer_id = nil
    last_event_id = -1
    enabled = false
    handlers = nil  -- reset so enums are re-resolved on next load
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
