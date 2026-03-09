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
-- PROBE: Unit kill counter via HF info.kills
-- Goal: verify field paths for per-unit kill data
--   hf.info.kills -> historical_kills struct
--   .events       -> vector of event IDs (HF death events where this HF was slayer)
--   .killed_race  -> vector of int16 (creature_raw index, parallel to killed_count)
--   .killed_caste -> vector of int16 (parallel)
--   .killed_count -> vector of int32 (kill count per race slot)
--   .killed_site  -> vector of site IDs
--   .killed_region/.killed_underground_region -> location vecs
--   .killed_undead -> bitfield vec
-- Also: HIST_FIGURE_DIED event fields including slayer_hf
-- ============================================================

print('=== START PROBE: unit kill counter via hf.info.kills ===')
print('')

-- ----------------------------------------------------------------
-- 1. Find a unit with a non-trivial kill record
--    Try: find any HF who appears as slayer_hf in recent HIST_FIGURE_DIED events
-- ----------------------------------------------------------------
print('--- 1. Scan HIST_FIGURE_DIED events for slayer_hf ---')
local events = df.global.world.history.events
local n_events = #events
local sample_slayer_hf_id = -1
local sample_victim_hf_id = -1
local count_died = 0

-- Walk backwards through last 500 events
local start_i = math.max(0, n_events - 500)
for i = n_events - 1, start_i, -1 do
    local ev = events[i]
    if not ev then goto cont_ev end
    local ok_t, t = pcall(function() return ev:getType() end)
    if not ok_t then goto cont_ev end
    if df.history_event_type[t] == 'HIST_FIGURE_DIED' then
        count_died = count_died + 1
        local ok_s, sid = pcall(function() return ev.slayer_hf end)
        local ok_v, vid = pcall(function() return ev.victim_hf end)
        if ok_s and sid and sid >= 0 and sample_slayer_hf_id < 0 then
            sample_slayer_hf_id = sid
            sample_victim_hf_id = (ok_v and vid) or -1
            -- Dump all fields of this event
            print(('  Sample HIST_FIGURE_DIED event[%d] id=%d:'):format(i, ev.id))
            pcall(function()
                for k, v in pairs(ev) do
                    print(('    %s = %s'):format(tostring(k), tostring(v)))
                end
            end)
        end
        if count_died >= 20 then break end
    end
    ::cont_ev::
end
print(('  Found %d HIST_FIGURE_DIED events in last 500. Sample slayer_hf=%d victim_hf=%d'):format(
    count_died, sample_slayer_hf_id, sample_victim_hf_id))
print('')

-- ----------------------------------------------------------------
-- 2. Inspect hf.info.kills for the sample slayer
-- ----------------------------------------------------------------
print('--- 2. hf.info.kills struct for slayer_hf ---')
if sample_slayer_hf_id >= 0 then
    local hf = df.historical_figure.find(sample_slayer_hf_id)
    if not hf then
        print('  hf not found')
    else
        local hf_name = '?'
        pcall(function() hf_name = dfhack.translation.translateName(hf.name, true) end)
        print(('  HF id=%d name="%s"'):format(sample_slayer_hf_id, hf_name))

        -- hf.info
        local ok_info, info = pcall(function() return hf.info end)
        if not ok_info or not info then
            print('  hf.info: nil or error - kills not populated for this HF')
        else
            print('  hf.info fields:')
            pcall(function()
                for k, v in pairs(info) do
                    print(('    info.%s = %s'):format(tostring(k), tostring(v)))
                end
            end)

            -- hf.info.kills
            local ok_k, kills = pcall(function() return info.kills end)
            if not ok_k or not kills then
                print('  hf.info.kills: nil (this HF has no kill profile)')
            else
                print('  hf.info.kills fields:')
                pcall(function()
                    for k, v in pairs(kills) do
                        print(('    kills.%s = %s'):format(tostring(k), tostring(v)))
                    end
                end)

                -- killed_count (aggregated by race)
                local ok_kc, kc = pcall(function() return kills.killed_count end)
                if ok_kc and kc then
                    local total = 0
                    for j = 0, #kc - 1 do
                        local ok_n, n = pcall(function() return kc[j] end)
                        if ok_n and n then total = total + n end
                    end
                    print(('  kills.killed_count: #=%d, total=%d'):format(#kc, total))
                    -- Print first 5 race/count pairs
                    local ok_kr, kr = pcall(function() return kills.killed_race end)
                    for j = 0, math.min(#kc - 1, 4) do
                        local ok_n, n = pcall(function() return kc[j] end)
                        local race_id = -1
                        if ok_kr and kr then
                            local ok_r, r = pcall(function() return kr[j] end)
                            if ok_r then race_id = r end
                        end
                        local race_name = '?'
                        if race_id >= 0 then
                            local ok_rn, rn = pcall(function()
                                return df.global.world.raws.creatures.all[race_id].name[0]
                            end)
                            if ok_rn then race_name = rn end
                        end
                        print(('    [%d] race_id=%d (%s) count=%s'):format(
                            j, race_id, race_name,
                            ok_n and tostring(n) or '?'))
                    end
                end

                -- events vector (HF death events where this HF was slayer)
                local ok_ev, ev_ids = pcall(function() return kills.events end)
                if ok_ev and ev_ids then
                    print(('  kills.events: #=%d'):format(#ev_ids))
                    for j = 0, math.min(#ev_ids - 1, 3) do
                        local ok_eid, eid = pcall(function() return ev_ids[j] end)
                        if ok_eid and eid then
                            print(('    events[%d] = event_id %d'):format(j, eid))
                            local ok_de, de = pcall(function() return df.history_event.find(eid) end)
                            if ok_de and de then
                                local ok_tt, tt = pcall(function()
                                    return df.history_event_type[de:getType()]
                                end)
                                local ok_vhf, vhf = pcall(function() return de.victim_hf end)
                                print(('      type=%s victim_hf=%s'):format(
                                    ok_tt and tt or '?',
                                    ok_vhf and tostring(vhf) or '?'))
                            end
                        end
                    end
                end
            end
        end
    end
else
    print('  No HIST_FIGURE_DIED events with slayer_hf found in last 500 events.')
    print('  Trying: find any HF with info.kills populated...')
    -- Brute force scan first 50 HFs
    local figs = df.global.world.history.figures
    local found = 0
    for i = 0, math.min(#figs - 1, 200) do
        if found >= 1 then break end
        local hf = figs[i]
        if not hf then goto cont_hf end
        local ok_k, k = pcall(function() return hf.info and hf.info.kills end)
        if ok_k and k then
            local ok_kc, kc = pcall(function() return k.killed_count end)
            if ok_kc and kc and #kc > 0 then
                found = found + 1
                local hf_name = '?'
                pcall(function() hf_name = dfhack.translation.translateName(hf.name, true) end)
                print(('  HF id=%d name="%s" has kills.killed_count #=%d'):format(
                    hf.id, hf_name, #kc))
                -- Show kills fields
                for k2, v2 in pairs(k) do
                    print(('    kills.%s = %s'):format(tostring(k2), tostring(v2)))
                end
            end
        end
        ::cont_hf::
    end
    if found == 0 then
        print('  No HF with kills found in first 200 HFs. May need a more developed world.')
    end
end
print('')

-- ----------------------------------------------------------------
-- 3. Verify: use dfhack.units.getKillCount() if available
-- ----------------------------------------------------------------
print('--- 3. dfhack.units.getKillCount check ---')
local ok_gkc = pcall(function()
    local fn = dfhack.units.getKillCount
    if fn then
        print('  dfhack.units.getKillCount exists')
        local active = df.global.world.units.active
        local found_any = false
        for i = 0, math.min(#active - 1, 30) do
            local u = active[i]
            if u then
                local ok_kn, kn = pcall(fn, u)
                if ok_kn and kn and kn > 0 then
                    local uname = '?'
                    pcall(function() uname = dfhack.translation.translateName(u.name, true) end)
                    print(('  unit id=%d name="%s" getKillCount=%d'):format(u.id, uname, kn))
                    found_any = true
                    break
                end
            end
        end
        if not found_any then print('  No active unit with kills > 0 in first 30.') end
    else
        print('  dfhack.units.getKillCount: not available in this DFHack version')
    end
end)
if not ok_gkc then print('  dfhack.units.getKillCount: error on access') end
print('')

print('=== END PROBE ===')
