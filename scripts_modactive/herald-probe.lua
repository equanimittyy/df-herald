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
-- PROBE: ARTIFACT_CLAIM_FORMED detail
-- ============================================================

local util = dfhack.reqscript('herald-util')
local safe_get = util.safe_get

print('=== START PROBE: ARTIFACT_CLAIM_FORMED DETAIL ===')
print('')

local CLAIM_TYPE = df.history_event_type['ARTIFACT_CLAIM_FORMED']
if not CLAIM_TYPE then
    print('ARTIFACT_CLAIM_FORMED not in enum')
    return
end

local events = df.global.world.history.events
local total = #events
local count = 0

for i = 0, total - 1 do
    local ok, ev = pcall(function() return events[i] end)
    if not ok or not ev then goto next_ev end
    local ok_t, etype = pcall(function() return ev:getType() end)
    if not ok_t or etype ~= CLAIM_TYPE then goto next_ev end

    count = count + 1

    -- Basic fields
    local art_id = safe_get(ev, 'artifact') or -1
    local hf_id = safe_get(ev, 'histfig')
    local entity_id = safe_get(ev, 'entity')
    local yr = safe_get(ev, 'year') or '?'

    -- Artifact name
    local art_name = '?'
    if art_id >= 0 then
        local ok_a, art = pcall(function() return df.artifact_record.find(art_id) end)
        if ok_a and art then
            local ok_n, n = pcall(function() return dfhack.translation.translateName(art.name, true) end)
            if ok_n and n and n ~= '' then art_name = n end
        end
    end

    -- HF name
    local hf_name = (hf_id and hf_id >= 0) and util.hf_name(hf_id) or nil

    -- Entity name
    local ent_name = (entity_id and entity_id >= 0) and util.ent_name(entity_id) or nil

    -- Claim type / reason / circumstance fields
    local claim_type = safe_get(ev, 'claim_type')
    local position_profile = safe_get(ev, 'position_profile')

    -- Reason substruct
    local reason_type, reason_data
    local ok_r, reason = pcall(function() return ev.reason end)
    if ok_r and reason then
        reason_type = safe_get(reason, 'type')
        reason_data = safe_get(reason, 'data')
    end

    -- Circumstance substruct
    local circ_type
    local ok_c, circ = pcall(function() return ev.circumstance end)
    if ok_c and circ then
        circ_type = safe_get(circ, 'type')
    end

    print(('  [%d] ev.id=%d year=%s art=%d (%s)'):format(
        count, ev.id, tostring(yr), art_id, art_name))
    print(('       hf=%s (%s)  entity=%s (%s)'):format(
        tostring(hf_id), hf_name or 'nil',
        tostring(entity_id), ent_name or 'nil'))
    print(('       claim_type=%s  position_profile=%s'):format(
        tostring(claim_type), tostring(position_profile)))
    print(('       reason.type=%s  circ.type=%s'):format(
        tostring(reason_type), tostring(circ_type)))

    -- Full printall on reason and circumstance for first 5
    if count <= 5 then
        if ok_r and reason then
            print('       reason printall:')
            pcall(function() printall(reason) end)
        end
        if ok_c and circ then
            print('       circumstance printall:')
            pcall(function() printall(circ) end)
        end
    end

    -- Full event printall for first 3
    if count <= 3 then
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

print(('Total ARTIFACT_CLAIM_FORMED events: %d (showing %d)'):format(
    count, math.min(count, 20)))

print('')
print('=== END PROBE ===')
