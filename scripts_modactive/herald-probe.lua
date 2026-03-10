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
-- PROBE: BEAST_ATTACK collection struct fields
--   1. Find first BEAST_ATTACK collection in world history
--   2. printall() to see all fields
--   3. Probe specific suspected fields: attacker_hf (vec), site,
--      defender_civ, region, layer, region_pos
--   4. If attacker_hf[0] resolves to an HF, print its name + race
-- ============================================================

print('=== START PROBE: BEAST_ATTACK COLLECTION ===')
print('')

local ok_CT, BA_TYPE = pcall(function()
    return df.history_event_collection_type.BEAST_ATTACK
end)
if not ok_CT or BA_TYPE == nil then
    print('ERROR: BEAST_ATTACK not in history_event_collection_type enum')
    print('=== END PROBE ===')
    return
end
print(('BEAST_ATTACK enum value = %d'):format(BA_TYPE))
print('')

local ok_all, all = pcall(function()
    return df.global.world.history.event_collections.all
end)
if not ok_all or not all then
    print('ERROR: cannot access event_collections.all')
    print('=== END PROBE ===')
    return
end

print(('Total collections in world: %d'):format(#all))

-- Find first BEAST_ATTACK and count them
local first_ba = nil
local ba_count = 0
for i = 0, #all - 1 do
    local ok_c, col = pcall(function() return all[i] end)
    if not ok_c or not col then goto continue end
    local ok_t, ct = pcall(function() return col:getType() end)
    if ok_t and ct == BA_TYPE then
        ba_count = ba_count + 1
        if not first_ba then first_ba = col end
    end
    ::continue::
end

print(('BEAST_ATTACK collections found: %d'):format(ba_count))
print('')

if not first_ba then
    print('No BEAST_ATTACK collections in this world - nothing to probe.')
    print('=== END PROBE ===')
    return
end

print(('Probing collection id=%d'):format(first_ba.id))
print('')

-- printall dump
print('[1] printall(col):')
printall(first_ba)
print('')

-- Probe specific fields from XML/search research:
-- attacker_hf (vec of int32 HF IDs), site (int32), defender_civ (int32 entity ID),
-- region (int32), layer (int32), region_pos (coord2d compound)
print('[2] Specific field probe:')
local fields = {
    'site', 'defender_civ', 'region', 'layer',
}
for _, f in ipairs(fields) do
    local ok_f, v = pcall(function() return first_ba[f] end)
    print(('  col.%s = %s (%s)'):format(f, ok_f and tostring(v) or 'ERROR/ABSENT', ok_f and type(v) or 'err'))
end

-- attacker_hf is a vector - probe specially
print('')
print('[3] attacker_hf vector:')
local ok_ahf, ahf = pcall(function() return first_ba.attacker_hf end)
if not ok_ahf or not ahf then
    print('  attacker_hf: ERROR or absent')
else
    print(('  attacker_hf: type=%s, #=%s'):format(type(ahf), tostring(#ahf)))
    for i = 0, math.min(#ahf - 1, 4) do
        local ok_v, v = pcall(function() return ahf[i] end)
        local hf_name = '?'
        if ok_v and v and v >= 0 then
            local hf = df.historical_figure.find(v)
            if hf then
                local n = dfhack.translation.translateName(hf.name, true)
                local race = hf.race
                local race_name = '?'
                local ok_r, robj = pcall(function() return df.global.world.raws.creatures.all[race] end)
                if ok_r and robj then
                    local ok_rn, rn = pcall(function() return robj.creature_id end)
                    if ok_rn then race_name = rn end
                end
                hf_name = ('%s (hf_id=%d, race=%s)'):format(n or '?', v, race_name)
            else
                hf_name = ('hf_id=%d (not found)'):format(v)
            end
        elseif ok_v then
            hf_name = ('value=%s'):format(tostring(v))
        else
            hf_name = 'ERROR'
        end
        print(('  attacker_hf[%d] = %s'):format(i, hf_name))
    end
end

-- region_pos compound
print('')
print('[4] region_pos compound:')
local ok_rp, rp = pcall(function() return first_ba.region_pos end)
if not ok_rp or not rp then
    print('  region_pos: ERROR or absent')
else
    print(('  region_pos type=%s'):format(type(rp)))
    local ok_x, rx = pcall(function() return rp.x end)
    local ok_y, ry = pcall(function() return rp.y end)
    print(('  region_pos.x=%s, y=%s'):format(
        ok_x and tostring(rx) or 'err',
        ok_y and tostring(ry) or 'err'
    ))
end

-- Also check base collection fields
print('')
print('[5] Base collection fields (events, collections, parent):')
local ok_ev, ev_vec = pcall(function() return first_ba.events end)
print(('  events vec: ok=%s, #=%s'):format(tostring(ok_ev), ok_ev and tostring(#ev_vec) or 'err'))
local ok_ch, ch_vec = pcall(function() return first_ba.collections end)
print(('  collections vec: ok=%s, #=%s'):format(tostring(ok_ch), ok_ch and tostring(#ch_vec) or 'err'))
local ok_par, par = pcall(function() return first_ba.parent_collection end)
print(('  parent_collection: ok=%s, val=%s'):format(tostring(ok_par), ok_par and tostring(par) or 'err'))

-- Sample a few more beast attacks to see if defender_civ varies
print('')
print('[6] Sample first 5 BEAST_ATTACK collections - attacker + site:')
local shown = 0
for i = 0, #all - 1 do
    if shown >= 5 then break end
    local ok_c, col = pcall(function() return all[i] end)
    if not ok_c or not col then goto continue2 end
    local ok_t, ct = pcall(function() return col:getType() end)
    if not ok_t or ct ~= BA_TYPE then goto continue2 end

    shown = shown + 1
    local ok_s, sv = pcall(function() return col.site end)
    local ok_dc, dv = pcall(function() return col.defender_civ end)
    local ok_ahf2, ahf2 = pcall(function() return col.attacker_hf end)
    local beast_id = (ok_ahf2 and #ahf2 > 0) and ahf2[0] or -1
    local beast_name = '?'
    if beast_id >= 0 then
        local hf = df.historical_figure.find(beast_id)
        if hf then
            beast_name = dfhack.translation.translateName(hf.name, true) or '?'
        end
    end
    print(('  col.id=%d site=%s defender_civ=%s beast=%s (hf=%d)'):format(
        col.id,
        ok_s and tostring(sv) or 'err',
        ok_dc and tostring(dv) or 'err',
        beast_name, beast_id
    ))
    ::continue2::
end

print('')
print('=== END PROBE ===')
