-- herald-main.lua
-- Event loop and site-leader death notifications for Dwarf Fortress Herald.
-- Loaded automatically via scripts_modactive/onLoad.init.

local GLOBAL_KEY    = 'df_herald'
local TICK_INTERVAL = 8400    -- 1 dwarf week in unpaused ticks

local last_event_id = -1      -- ID of last processed event; -1 = uninitialised
local scan_timer_id = nil     -- handle returned by dfhack.timeout
enabled = enabled or false    -- top-level var; DFHack enable/disable convention

function isEnabled()
    return enabled
end

-- Returns (entity, position_name) if hf_id holds any position in a civ entity,
-- or nil, nil otherwise.
local function get_leader_info(hf_id)
    local hf = df.historical_figure.find(hf_id)
    if not hf then return nil, nil end

    for _, link in ipairs(hf.entity_links) do
        if link:getType() == df.histfig_entity_link_type.POSITION then
            local entity = df.historical_entity.find(link.entity_id)
            if entity then
                for _, assignment in ipairs(entity.position_assignments) do
                    if assignment.histfig2 == hf_id then
                        for _, pos in ipairs(entity.positions) do
                            if pos.id == assignment.id then
                                return entity, pos.name
                            end
                        end
                    end
                end
            end
        end
    end

    return nil, nil
end

local function handle_death_event(event)
    local hf_id = event.victim_hf
    local entity, pos_name = get_leader_info(hf_id)
    if not entity then return end

    local hf      = df.historical_figure.find(hf_id)
    local hf_name  = dfhack.TranslateName(hf.name, true)
    local civ_name = dfhack.TranslateName(entity.name, true)

    dfhack.gui.showAnnouncement(
        ('[Herald] %s, %s of %s, has died.'):format(hf_name, pos_name, civ_name),
        COLOR_RED, true   -- pause = true for high-importance event
    )
end

local function scan_events()
    if not dfhack.isMapLoaded() then return end

    local events = df.global.world.history.events
    for i = last_event_id + 1, #events - 1 do
        local ev = events[i]
        if ev:getType() == df.history_event_type.HIST_FIGURE_DIED then
            handle_death_event(ev)
        end
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
