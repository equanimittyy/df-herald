--@ module=true

--[====[
herald-probe
============
Tags: dev

Debug utility for inspecting live DF data. Edit the probe code below as needed,
then run via: herald probe
Requires debug mode: herald debug true

Not intended for direct use.
]====]

local main = dfhack.reqscript('herald')

if not main.DEBUG then
    dfhack.printerr('[Herald] Probe requires debug mode. Enable with: herald debug true')
    return
end

-- ============================================================
-- PROBE: TOPICAGREEMENT events
--        Scan world history for alliance/agreement events
--        (TOPICAGREEMENT_CONCLUDED, TOPICAGREEMENT_MADE,
--        TOPICAGREEMENT_REJECTED) to verify the civ-diplomacy
--        handler can detect them.
-- ============================================================

local util = dfhack.reqscript('herald-util')

print('=== START PROBE: TOPICAGREEMENT events ===')
print('')

local T = df.history_event_type
local target_types = {}
if T.TOPICAGREEMENT_CONCLUDED then target_types[T.TOPICAGREEMENT_CONCLUDED] = 'CONCLUDED' end
if T.TOPICAGREEMENT_MADE      then target_types[T.TOPICAGREEMENT_MADE]      = 'MADE' end
if T.TOPICAGREEMENT_REJECTED  then target_types[T.TOPICAGREEMENT_REJECTED]  = 'REJECTED' end

if not next(target_types) then
    print('ERROR: no TOPICAGREEMENT event types found in this DF version')
    print('=== END PROBE ===')
    return
end

print('Registered event types:')
for et, label in pairs(target_types) do
    print(('  %s = %s'):format(label, tostring(et)))
end
print('')

local ok_ev, events = pcall(function() return df.global.world.history.events end)
if not ok_ev or not events then
    print('ERROR: cannot access world.history.events')
    print('=== END PROBE ===')
    return
end

local found = 0
local MAX_SHOW = 20

for i = 0, #events - 1 do
    local ok2, ev = pcall(function() return events[i] end)
    if not ok2 or not ev then goto next_ev end

    local ok3, ev_type = pcall(function() return ev:getType() end)
    if not ok3 then goto next_ev end

    local label = target_types[ev_type]
    if not label then goto next_ev end

    found = found + 1
    if found <= MAX_SHOW then
        local src = util.safe_get(ev, 'source') or -1
        local dst = util.safe_get(ev, 'destination') or -1
        local topic = util.safe_get(ev, 'topic')
        local result = util.safe_get(ev, 'result')

        -- Entity names
        local src_name = 'unknown'
        if src >= 0 then
            local ent = df.historical_entity.find(src)
            if ent then
                local n = dfhack.translation.translateName(ent.name, true)
                if n and n ~= '' then src_name = n end
            end
        end
        local dst_name = 'unknown'
        if dst >= 0 then
            local ent = df.historical_entity.find(dst)
            if ent then
                local n = dfhack.translation.translateName(ent.name, true)
                if n and n ~= '' then dst_name = n end
            end
        end

        print(('--- [%d] TOPICAGREEMENT_%s (event idx %d, id %d) ---'):format(
            found, label, i, ev.id))
        print(('  source:      %d (%s)'):format(src, src_name))
        print(('  destination: %d (%s)'):format(dst, dst_name))
        if topic ~= nil then print(('  topic:       %s'):format(tostring(topic))) end
        if result ~= nil then print(('  result:      %s'):format(tostring(result))) end

        -- Dump all fields via printall
        print('  [printall]:')
        local lines = {}
        local old_print = print
        print = function(s) table.insert(lines, s) end
        pcall(function() printall(ev) end)
        print = old_print
        for _, line in ipairs(lines) do
            old_print('    ' .. tostring(line))
        end
        print('')
    end

    ::next_ev::
end

if found == 0 then
    print('No TOPICAGREEMENT events found in world history.')
elseif found > MAX_SHOW then
    print(('... and %d more (showing first %d)'):format(found - MAX_SHOW, MAX_SHOW))
end
print(('Total TOPICAGREEMENT events: %d'):format(found))

print('')
print('=== END PROBE ===')
