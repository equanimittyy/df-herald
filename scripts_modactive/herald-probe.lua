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
-- PROBE: WAR_SITE_TRIBUTE_FORCED event struct field names
--        1. Check if the event type exists in this DF version.
--        2. Find any event of that type in world history.
--        3. printall() the first found event to list every field.
--        4. Also check neighbour WAR_* event types for comparison.
-- ============================================================

print('=== START PROBE: WAR_SITE_TRIBUTE_FORCED ===')
print('')

local T = df.history_event_type

-- Step 1: confirm the type exists and print its numeric value.
local tribute_type = T['WAR_SITE_TRIBUTE_FORCED']
if tribute_type == nil then
    print('WARNING: df.history_event_type["WAR_SITE_TRIBUTE_FORCED"] is nil in this DF version.')
    print('It may not exist or may have a different name.')
    print('')
    print('Dumping all history_event_type enum values with "WAR" in name:')
    for k, v in pairs(T) do
        if type(k) == 'string' and k:find('WAR') then
            print(('  %s = %s'):format(k, tostring(v)))
        end
    end
    print('')
    print('=== END PROBE ===')
    return
end

print(('WAR_SITE_TRIBUTE_FORCED type value = %d'):format(tribute_type))
print('')

-- Step 2: scan world history for any event of this type.
local ok_ev, events = pcall(function() return df.global.world.history.events end)
if not ok_ev or not events then
    print('ERROR: cannot access world.history.events')
    print('=== END PROBE ===')
    return
end

print(('Total events in world history: %d'):format(#events))
print('Scanning for WAR_SITE_TRIBUTE_FORCED events...')
print('')

local found = 0
local MAX_SHOW = 5

for i = 0, #events - 1 do
    local ok2, ev = pcall(function() return events[i] end)
    if not ok2 or not ev then goto next_ev end

    local ok3, ev_type = pcall(function() return ev:getType() end)
    if not ok3 then goto next_ev end

    if ev_type ~= tribute_type then goto next_ev end

    found = found + 1
    if found <= MAX_SHOW then
        print(('--- [%d] WAR_SITE_TRIBUTE_FORCED (array pos %d, id %d, year %s) ---'):format(
            found, i, ev.id or -1, tostring(ev.year)))

        -- Dump all fields via printall.
        print('  [printall output]:')
        local lines = {}
        local old_print = print
        print = function(s) table.insert(lines, s) end
        pcall(function() printall(ev) end)
        print = old_print
        for _, line in ipairs(lines) do
            old_print('    ' .. tostring(line))
        end

        -- Explicitly probe likely field names to confirm which are valid.
        print('  [field probe]:')
        local probe_fields = {
            -- Civ fields: DF war events typically use a_civ/d_civ or attacker_civ/defender_civ.
            'a_civ', 'd_civ',
            'attacker_civ', 'defender_civ',
            'entity', 'civ', 'entity_id',
            -- Site field.
            'site', 'site_id', 'target_site_id',
            -- Season/period fields.
            'season', 'season_ticks',
            -- Tribute flags or amount.
            'tribute_flags', 'tribute', 'amount',
            -- HF fields common in war events.
            'attacker_hf', 'defender_hf',
            'attacker_general_hf', 'defender_general_hf',
            -- Generic.
            'histfig', 'hfid', 'year', 'seconds',
        }
        for _, fname in ipairs(probe_fields) do
            local ok_f, fval = pcall(function() return ev[fname] end)
            if ok_f and fval ~= nil then
                print(('    ev.%s = %s'):format(fname, tostring(fval)))
            end
        end
        print('')
    end

    ::next_ev::
end

if found == 0 then
    print('No WAR_SITE_TRIBUTE_FORCED events found in world history.')
    print('(World may not have generated this event type. Try a world with more history.)')
elseif found > MAX_SHOW then
    print(('... and %d more (showing first %d)'):format(found - MAX_SHOW, MAX_SHOW))
end
print(('Total WAR_SITE_TRIBUTE_FORCED events: %d'):format(found))

print('')
print('=== END PROBE ===')
