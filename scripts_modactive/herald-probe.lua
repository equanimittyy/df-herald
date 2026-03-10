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
-- PROBE: MASTERPIECE_CREATED vs ARTIFACT_CREATED event types
--   1. Check which MASTERPIECE_CREATED_* enum values exist
--   2. Check which ARTIFACT_* enum values exist
--   3. Count how many of each appear in world history
--   4. Dump fields of first found event for each type
-- ============================================================

print('=== START PROBE: MASTERPIECE + ARTIFACT EVENT TYPES ===')
print('')

local T = df.history_event_type

-- 1. Check enum values exist
print('[1] MASTERPIECE_CREATED_* enum values:')
local masterpiece_types = {
    'MASTERPIECE_CREATED_ITEM',
    'MASTERPIECE_CREATED_ENGRAVING',
    'MASTERPIECE_CREATED_FOOD',
    'MASTERPIECE_CREATED_DYE_ITEM',
    'MASTERPIECE_CREATED_ARCH_CONSTRUCT',
    'MASTERPIECE_CREATED_ARCH_DESIGN',
    'MASTERPIECE_CREATED_ITEM_IMPROVEMENT',
    'MASTERPIECE_LOST',
}
local active_masterpiece = {}
for _, name in ipairs(masterpiece_types) do
    local ok, v = pcall(function() return T[name] end)
    if ok and v ~= nil then
        print(('  %s = %d [EXISTS]'):format(name, v))
        active_masterpiece[v] = name
    else
        print(('  %s : NOT IN ENUM (removed or DF<50)'):format(name))
    end
end
print('')

print('[2] ARTIFACT_* enum values:')
local artifact_types = {
    'ARTIFACT_CREATED',
    'ARTIFACT_STORED',
    'ARTIFACT_POSSESSED',
    'ARTIFACT_GIVEN',
    'ARTIFACT_CLAIM_FORMED',
    'ARTIFACT_LOST',
    'ARTIFACT_FOUND',
    'ARTIFACT_RECOVERED',
    'ARTIFACT_DROPPED',
    'ARTIFACT_HIDDEN',
}
local active_artifact = {}
for _, name in ipairs(artifact_types) do
    local ok, v = pcall(function() return T[name] end)
    if ok and v ~= nil then
        print(('  %s = %d [EXISTS]'):format(name, v))
        active_artifact[v] = name
    else
        print(('  %s : NOT IN ENUM'):format(name))
    end
end
print('')

-- 2. Count occurrences in world history
print('[3] Scanning world history events...')
local ok_ev, events = pcall(function() return df.global.world.history.events end)
if not ok_ev or not events then
    print('ERROR: cannot access world history events')
    print('=== END PROBE ===')
    return
end

local total = #events
print(('  Total events in world: %d'):format(total))

local mp_counts = {}
local art_counts = {}
local mp_first = {}
local art_first = {}

for i = 0, total - 1 do
    local ok_e, ev = pcall(function() return events[i] end)
    if not ok_e or not ev then goto continue end

    local ok_t, et = pcall(function() return ev:getType() end)
    if not ok_t then goto continue end

    if active_masterpiece[et] then
        mp_counts[et] = (mp_counts[et] or 0) + 1
        if not mp_first[et] then mp_first[et] = ev end
    end

    if active_artifact[et] then
        art_counts[et] = (art_counts[et] or 0) + 1
        if not art_first[et] then art_first[et] = ev end
    end

    ::continue::
end

print('')
print('  MASTERPIECE event counts:')
for et, name in pairs(active_masterpiece) do
    local c = mp_counts[et] or 0
    print(('    %s: %d events'):format(name, c))
end

print('')
print('  ARTIFACT event counts:')
for et, name in pairs(active_artifact) do
    local c = art_counts[et] or 0
    print(('    %s: %d events'):format(name, c))
end

-- 3. Field dump for first found events
print('')
print('[4] Field dump - first MASTERPIECE_CREATED_ITEM event (if any):')
local mp_item_type_ok, mp_item_type = pcall(function() return T.MASTERPIECE_CREATED_ITEM end)
if mp_item_type_ok and mp_item_type and mp_first[mp_item_type] then
    local ev = mp_first[mp_item_type]
    print(('  Event id=%d year=%d'):format(ev.id, ev.year))
    -- Probe the shared base fields
    local base_fields = {'maker', 'maker_entity', 'site', 'skill_at_time'}
    for _, f in ipairs(base_fields) do
        local ok_f, v = pcall(function() return ev[f] end)
        print(('  ev.%s = %s (%s)'):format(f, ok_f and tostring(v) or 'ERROR', ok_f and type(v) or 'err'))
    end
    -- Subtype-specific fields
    local item_fields = {'item_type', 'item_subtype', 'mat_type', 'mat_index'}
    for _, f in ipairs(item_fields) do
        local ok_f, v = pcall(function() return ev[f] end)
        print(('  ev.%s = %s (%s)'):format(f, ok_f and tostring(v) or 'ERROR', ok_f and type(v) or 'err'))
    end
    -- Resolve maker HF name
    local ok_m, m = pcall(function() return ev.maker end)
    if ok_m and m and m >= 0 then
        local hf = df.historical_figure.find(m)
        if hf then
            local n = dfhack.translation.translateName(hf.name, true)
            print(('  -> maker HF name: %s (id=%d)'):format(n or '?', m))
        end
    end
else
    print('  No MASTERPIECE_CREATED_ITEM events found in this world (or enum missing)')
end

print('')
print('[5] Field dump - first ARTIFACT_CREATED event (if any):')
local art_type_ok, art_type = pcall(function() return T.ARTIFACT_CREATED end)
if art_type_ok and art_type and art_first[art_type] then
    local ev = art_first[art_type]
    print(('  Event id=%d year=%d'):format(ev.id, ev.year))
    -- Probe all plausible fields
    local art_fields = {
        'artifact_id', 'artifact_record', 'hfid', 'creator_hfid',
        'unit_id', 'site', 'flags2', 'circumstance', 'reason'
    }
    for _, f in ipairs(art_fields) do
        local ok_f, v = pcall(function() return ev[f] end)
        print(('  ev.%s = %s (%s)'):format(f, ok_f and tostring(v) or 'ERROR/MISSING', ok_f and type(v) or 'err'))
    end
    -- Try printall
    print('  [printall]:')
    local lines = {}
    local old_print = print
    print = function(s) table.insert(lines, s) end
    pcall(function() printall(ev) end)
    print = old_print
    for _, line in ipairs(lines) do
        old_print('    ' .. tostring(line))
    end
else
    print('  No ARTIFACT_CREATED events found in this world (or enum missing)')
end

print('')
print('[6] Field dump - first MASTERPIECE_CREATED_ENGRAVING event (if any):')
local eng_type_ok, eng_type = pcall(function() return T.MASTERPIECE_CREATED_ENGRAVING end)
if eng_type_ok and eng_type and mp_first[eng_type] then
    local ev = mp_first[eng_type]
    print(('  Event id=%d year=%d'):format(ev.id, ev.year))
    local base_fields = {'maker', 'maker_entity', 'site', 'skill_at_time'}
    for _, f in ipairs(base_fields) do
        local ok_f, v = pcall(function() return ev[f] end)
        print(('  ev.%s = %s'):format(f, ok_f and tostring(v) or 'ERROR'))
    end
else
    print('  No MASTERPIECE_CREATED_ENGRAVING events (or enum missing)')
end

print('')
print('=== END PROBE ===')
