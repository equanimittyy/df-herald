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

-- Find ENTITY_OVERTHROWN collections and dump fields + child events.
local ct_val = df.history_event_collection_type.ENTITY_OVERTHROWN
print('ENTITY_OVERTHROWN collection type int: ' .. tostring(ct_val))

local cols = df.global.world.history.event_collections.all
local count = 0
for i = 0, #cols - 1 do
    local col = cols[i]
    if col:getType() == ct_val then
        print(('--- collection id=%d'):format(col.id))
        printall(col)
        -- Show child events.
        print('  events (' .. #col.events .. '):')
        for j = 0, math.min(#col.events - 1, 4) do
            local ev = df.history_event.find(col.events[j])
            if ev then
                local etype = df.history_event_type[ev:getType()]
                print(('    ev id=%d type=%s year=%d'):format(ev.id, tostring(etype), ev.year))
                printall(ev)
            end
        end
        -- Show child collections.
        if #col.collections > 0 then
            print('  child collections (' .. #col.collections .. '):')
            for j = 0, math.min(#col.collections - 1, 2) do
                local child = df.history_event_collection.find(col.collections[j])
                if child then
                    local ctype = df.history_event_collection_type[child:getType()]
                    print(('    col id=%d type=%s'):format(child.id, tostring(ctype)))
                end
            end
        end
        count = count + 1
        if count >= 2 then break end
    end
end
print('Found ' .. count .. ' ENTITY_OVERTHROWN collections')

print('=== END PROBE ===')
