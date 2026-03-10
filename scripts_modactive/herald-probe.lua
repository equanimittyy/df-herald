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
-- PROBE: hf.info.kills structure
--        Dump kill tracking data for all pinned HFs on the
--        active list to verify kill count detection works.
-- ============================================================

local util = dfhack.reqscript('herald-util')
local pins = dfhack.reqscript('herald-pins')

print('=== START PROBE: hf.info.kills ===')
print('')

local ok, active = pcall(function() return df.global.world.units.active end)
if not ok or not active then
    print('ERROR: no active units')
    print('=== END PROBE ===')
    return
end

local pinned = pins.get_pinned()
local found = 0

for i = 0, #active - 1 do
    local unit = active[i]
    if not unit then goto next_unit end
    local ok_hf, hf_id = pcall(function() return unit.hist_figure_id end)
    if not ok_hf or not hf_id or hf_id < 0 then goto next_unit end
    if not pinned[hf_id] then goto next_unit end

    local name = util.hf_name(hf_id)
    print(('--- Pinned HF: %s (hf %d, unit %d) ---'):format(name, hf_id, unit.id))

    local hf = df.historical_figure.find(hf_id)
    if not hf then
        print('  ERROR: historical_figure.find returned nil')
        print('')
        goto next_unit
    end

    -- Check hf.info existence
    local ok_info, info = pcall(function() return hf.info end)
    if not ok_info or not info then
        print('  hf.info: nil or inaccessible')
        print('')
        goto next_unit
    end

    -- Check hf.info.kills existence
    local ok_kills, kills = pcall(function() return info.kills end)
    if not ok_kills or not kills then
        print('  hf.info.kills: nil or inaccessible')
        print('')
        goto next_unit
    end

    print('  hf.info.kills exists')

    -- Dump top-level kills fields
    print('  [printall hf.info.kills]:')
    local lines = {}
    local old_print = print
    print = function(s) table.insert(lines, s) end
    pcall(function() printall(kills) end)
    print = old_print
    for _, line in ipairs(lines) do
        old_print('    ' .. tostring(line))
    end
    print('')

    -- kills.events (vector of history event IDs for HF kills)
    local ok_ev, ev_vec = pcall(function() return kills.events end)
    if ok_ev and ev_vec then
        print(('  kills.events count: %d'):format(#ev_vec))
        for ei = 0, math.min(#ev_vec - 1, 4) do
            local ev_id = ev_vec[ei]
            print(('    [%d] event_id=%s'):format(ei, tostring(ev_id)))
            -- Try to resolve victim from event
            local ok_de, de = pcall(function() return df.history_event.find(ev_id) end)
            if ok_de and de then
                local ok_vid, vid = pcall(function() return de.victim_hf end)
                local ok_sid, sid = pcall(function() return de.slayer_hf end)
                print(('         victim_hf=%s, slayer_hf=%s'):format(
                    ok_vid and tostring(vid) or '?',
                    ok_sid and tostring(sid) or '?'))
                if ok_vid and vid and vid >= 0 then
                    print(('         victim name: %s'):format(util.hf_name(vid)))
                end
            else
                print('         event not found')
            end
        end
        if #ev_vec > 5 then
            print(('    ... (%d more)'):format(#ev_vec - 5))
        end
    else
        print('  kills.events: nil or inaccessible')
    end
    print('')

    -- kills.killed_race (vector of race IDs)
    local ok_kr, kr_vec = pcall(function() return kills.killed_race end)
    if ok_kr and kr_vec then
        print(('  kills.killed_race count: %d'):format(#kr_vec))
        for ki = 0, math.min(#kr_vec - 1, 9) do
            local race_id = kr_vec[ki]
            local race_name = '?'
            if race_id and race_id >= 0 then
                local ok_rn, rn = pcall(function()
                    return df.global.world.raws.creatures.all[race_id].name[0]
                end)
                if ok_rn and rn then race_name = rn end
            end
            print(('    [%d] race_id=%s (%s)'):format(ki, tostring(race_id), race_name))
        end
        if #kr_vec > 10 then
            print(('    ... (%d more)'):format(#kr_vec - 10))
        end
    else
        print('  kills.killed_race: nil or inaccessible')
    end
    print('')

    -- kills.killed_caste (vector of caste IDs)
    local ok_kc_c, kc_c_vec = pcall(function() return kills.killed_caste end)
    if ok_kc_c and kc_c_vec then
        print(('  kills.killed_caste count: %d'):format(#kc_c_vec))
    else
        print('  kills.killed_caste: nil or inaccessible')
    end

    -- kills.killed_count (vector of kill counts per race/caste combo)
    local ok_kc, kc_vec = pcall(function() return kills.killed_count end)
    if ok_kc and kc_vec then
        print(('  kills.killed_count count: %d'):format(#kc_vec))
        local total_from_count = 0
        for ki = 0, #kc_vec - 1 do
            local ok_n, n = pcall(function() return kc_vec[ki] end)
            if ok_n and n then
                total_from_count = total_from_count + n
                -- Show race name alongside count
                local race_name = '?'
                if ok_kr and kr_vec and ki < #kr_vec then
                    local race_id = kr_vec[ki]
                    if race_id and race_id >= 0 then
                        local ok_rn, rn = pcall(function()
                            return df.global.world.raws.creatures.all[race_id].name[0]
                        end)
                        if ok_rn and rn then race_name = rn end
                    end
                end
                print(('    [%d] count=%d (%s)'):format(ki, n, race_name))
            end
        end
        print(('  TOTAL from killed_count: %d'):format(total_from_count))
    else
        print('  kills.killed_count: nil or inaccessible')
    end
    print('')

    -- Summary totals
    local ev_total = (ok_ev and ev_vec) and #ev_vec or 0
    local kc_total = 0
    if ok_kc and kc_vec then
        for ki = 0, #kc_vec - 1 do
            local ok_n, n = pcall(function() return kc_vec[ki] end)
            if ok_n and n then kc_total = kc_total + n end
        end
    end
    print(('  SUMMARY: events=%d, killed_count_total=%d, combined=%d'):format(
        ev_total, kc_total, ev_total + kc_total))
    print('')

    found = found + 1
    ::next_unit::
end

if found == 0 then
    print('No pinned HFs found on the active list.')
else
    print(('Probed %d pinned HF(s).'):format(found))
end

print('=== END PROBE ===')
