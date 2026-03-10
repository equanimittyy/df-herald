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
-- PROBE: THEFT and ABDUCTION collections
--        1. Scan all event collections for THEFT/ABDUCTION types.
--        2. Dump fields of each found collection.
--        3. Also scan for ITEM_STOLEN events to cross-reference.
-- ============================================================

print('=== START PROBE: THEFT/ABDUCTION COLLECTIONS ===')
print('')

local CT = {}
for _, name in ipairs({'THEFT', 'ABDUCTION'}) do
    local ok, v = pcall(function()
        return df.history_event_collection_type[name]
    end)
    if ok and v ~= nil then
        CT[name] = v
        print(('Collection type %s = %d'):format(name, v))
    else
        print(('Collection type %s: NOT FOUND in this DF version'):format(name))
    end
end
print('')

-- Scan all collections
local ok_all, all = pcall(function()
    return df.global.world.history.event_collections.all
end)
if not ok_all or not all then
    print('ERROR: cannot access world.history.event_collections.all')
    print('=== END PROBE ===')
    return
end

print(('Total collections in world: %d'):format(#all))
print('')

local theft_count = 0
local abduction_count = 0
local MAX_SHOW = 10

for i = 0, #all - 1 do
    local ok2, col = pcall(function() return all[i] end)
    if not ok2 or not col then goto next_col end

    local ok3, ct = pcall(function() return col:getType() end)
    if not ok3 then goto next_col end

    local is_theft = (ct == CT.THEFT)
    local is_abduction = (ct == CT.ABDUCTION)
    if not is_theft and not is_abduction then goto next_col end

    local count = is_theft and theft_count or abduction_count
    if is_theft then theft_count = theft_count + 1 else abduction_count = abduction_count + 1 end

    if count < MAX_SHOW then
        local label = is_theft and 'THEFT' or 'ABDUCTION'
        local ok_yr, yr = pcall(function() return col.year end)
        print(('--- [%s #%d] collection id=%d, year=%s ---'):format(
            label, count + 1, col.id, ok_yr and tostring(yr) or '?'))

        -- printall
        print('  [printall]:')
        local lines = {}
        local old_print = print
        print = function(s) table.insert(lines, s) end
        pcall(function() printall(col) end)
        print = old_print
        for _, line in ipairs(lines) do
            old_print('    ' .. tostring(line))
        end

        -- Probe specific fields
        print('  [field probe]:')
        local probe_fields = {
            'site', 'attacker_civ', 'attacking_entity', 'defender_civ',
            'entity', 'parent_collection',
        }
        for _, fname in ipairs(probe_fields) do
            local ok_f, fval = pcall(function() return col[fname] end)
            if ok_f and fval ~= nil then
                old_print(('    col.%s = %s'):format(fname, tostring(fval)))
            end
        end

        -- Probe vector fields
        local vec_fields = {
            'victim_hf', 'snatcher_hf', 'events',
        }
        for _, fname in ipairs(vec_fields) do
            local ok_v, vec = pcall(function() return col[fname] end)
            if ok_v and vec then
                local ok_n, n = pcall(function() return #vec end)
                if ok_n then
                    local items = {}
                    for j = 0, math.min(n - 1, 4) do
                        local ok_j, v = pcall(function() return vec[j] end)
                        if ok_j then table.insert(items, tostring(v)) end
                    end
                    local suffix = n > 5 and (' ... +' .. (n - 5) .. ' more') or ''
                    old_print(('    col.%s [%d]: {%s}%s'):format(
                        fname, n, table.concat(items, ', '), suffix))
                end
            end
        end

        -- Resolve site name if available
        local ok_site, site_id = pcall(function() return col.site end)
        if ok_site and site_id and site_id >= 0 then
            local site = df.world_site.find(site_id)
            if site then
                local name = dfhack.translation.translateName(site.name, true)
                old_print(('    -> site name: %s'):format(name or '?'))
            end
        end

        print('')
    end

    ::next_col::
end

print(('THEFT collections found: %d'):format(theft_count))
print(('ABDUCTION collections found: %d'):format(abduction_count))
print('')

-- Also count ITEM_STOLEN events for cross-reference
local T = df.history_event_type
local stolen_type = T.ITEM_STOLEN
if stolen_type then
    local ok_ev, events = pcall(function() return df.global.world.history.events end)
    if ok_ev and events then
        local stolen_count = 0
        for i = 0, #events - 1 do
            local ok4, ev = pcall(function() return events[i] end)
            if ok4 and ev then
                local ok5, et = pcall(function() return ev:getType() end)
                if ok5 and et == stolen_type then
                    stolen_count = stolen_count + 1
                end
            end
        end
        print(('ITEM_STOLEN events found: %d'):format(stolen_count))
    end
else
    print('ITEM_STOLEN event type: NOT FOUND')
end

local abducted_type = T.HIST_FIGURE_ABDUCTED or T.HF_ABDUCTED
if abducted_type then
    local ok_ev, events = pcall(function() return df.global.world.history.events end)
    if ok_ev and events then
        local abd_count = 0
        for i = 0, #events - 1 do
            local ok4, ev = pcall(function() return events[i] end)
            if ok4 and ev then
                local ok5, et = pcall(function() return ev:getType() end)
                if ok5 and et == abducted_type then
                    abd_count = abd_count + 1
                end
            end
        end
        print(('HIST_FIGURE_ABDUCTED events found: %d'):format(abd_count))
    end
else
    print('HIST_FIGURE_ABDUCTED/HF_ABDUCTED event type: NOT FOUND')
end

print('')
print('=== END PROBE ===')
