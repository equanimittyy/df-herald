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

-- Edit probe code below as needed.
local evs = df.global.world.history.events
local count = 0
for i = 0, #evs - 1 do
    local e = evs[i]
    if e:getType() == df.history_event_type.BODY_ABUSED then
        local hf = e.histfig
        local in_bodies = false
        for j = 0, #e.bodies - 1 do
            if e.bodies[j] == 177 then in_bodies = true end
        end
        if hf == 177 or in_bodies then
            print(('--- event id=%d year=%d'):format(e.id, e.year))
            print('  histfig=' .. e.histfig)
            print('  abuse_type=' .. tostring(e.abuse_type))
            print('  site=' .. tostring(e.site) .. '  region=' .. tostring(e.region))
            for j = 0, #e.bodies - 1 do
                print('  bodies[' .. j .. ']=' .. e.bodies[j])
            end
            count = count + 1
            if count >= 5 then break end
        end
    end
end
print(('[Herald] Found %d event(s)'):format(count))

print('=== END PROBE ===')
