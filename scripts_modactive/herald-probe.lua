--@ module=true

--[====[
herald-probe
============
Debug utility for inspecting live DF data. Edit the probe code below as needed,
then run via: herald-main probe
Requires debug mode: herald-main debug true

Not intended for direct use.
]====]

local main = dfhack.reqscript('herald-main')

if not main.DEBUG then
    dfhack.printerr('[Herald] Probe requires debug mode. Enable with: herald-main debug true')
    return
end

print('=== START PROBE ===')

-- Find HIST_FIGURE_REVIVED events and dump fields.
local t = df.history_event_type.HIST_FIGURE_REVIVED
    or df.history_event_type.HF_REVIVED
if not t then
    print('HIST_FIGURE_REVIVED / HF_REVIVED not found in enum')
else
    print('Event type int: ' .. tostring(t))
    local evs = df.global.world.history.events
    local count = 0
    for i = #evs - 1, 0, -1 do
        local e = evs[i]
        if e:getType() == t then
            print(('--- event id=%d year=%d'):format(e.id, e.year))
            printall(e)
            count = count + 1
            if count >= 2 then break end
        end
    end
    print('Found ' .. count .. ' events')
end

print('=== END PROBE ===')
