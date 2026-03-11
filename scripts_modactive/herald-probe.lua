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
-- PROBE: ARTIFACT_LOST full field dump
-- ============================================================

local util = dfhack.reqscript('herald-util')
local safe_get = util.safe_get

print('=== START PROBE: ARTIFACT_LOST DETAIL ===')
print('')

local LOST_TYPE = df.history_event_type['ARTIFACT_LOST']
if not LOST_TYPE then
    print('ARTIFACT_LOST not in enum')
    return
end

local events = df.global.world.history.events
local total = #events
local count = 0

for i = 0, total - 1 do
    local ok, ev = pcall(function() return events[i] end)
    if not ok or not ev then goto next_ev end
    local ok_t, etype = pcall(function() return ev:getType() end)
    if not ok_t or etype ~= LOST_TYPE then goto next_ev end

    count = count + 1

    local art_id = safe_get(ev, 'artifact') or -1
    local site_id = safe_get(ev, 'site')
    local subregion = safe_get(ev, 'subregion')
    local feature_layer = safe_get(ev, 'feature_layer')
    local yr = safe_get(ev, 'year') or '?'

    -- Try common fields that might exist
    local hf_id = safe_get(ev, 'histfig')
    local entity_id = safe_get(ev, 'entity')
    local last_owner = safe_get(ev, 'last_owner')
    local last_holder = safe_get(ev, 'last_holder')

    -- Artifact name
    local art_name = '?'
    if art_id >= 0 then
        local ok_a, art = pcall(function() return df.artifact_record.find(art_id) end)
        if ok_a and art then
            local ok_n, n = pcall(function() return dfhack.translation.translateName(art.name, true) end)
            if ok_n and n and n ~= '' then art_name = n end
        end
    end

    -- Site name
    local site_name = (site_id and site_id >= 0) and util.site_name(site_id) or nil

    print(('  [%d] ev.id=%d year=%s art=%d (%s)'):format(
        count, ev.id, tostring(yr), art_id, art_name))
    print(('       site=%s (%s)  subregion=%s  feature_layer=%s'):format(
        tostring(site_id), site_name or 'nil',
        tostring(subregion), tostring(feature_layer)))
    print(('       histfig=%s  entity=%s  last_owner=%s  last_holder=%s'):format(
        tostring(hf_id), tostring(entity_id),
        tostring(last_owner), tostring(last_holder)))

    -- Full printall for first 5
    if count <= 5 then
        print('       full event printall:')
        pcall(function() printall(ev) end)
    end

    print('')

    if count >= 20 then
        print('  ... (capped at 20)')
        break
    end
    ::next_ev::
end

print(('Total ARTIFACT_LOST events: %d (showing %d)'):format(
    count, math.min(count, 20)))

print('')
print('=== END PROBE ===')
