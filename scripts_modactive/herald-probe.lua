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
-- PROBE: job_skill enum - determine integer value of PLANT
--        and dump first 30 enum entries to confirm ordering.
-- ============================================================

print('=== START PROBE: job_skill enum PLANT value ===')
print('')

-- 1. Direct lookup of PLANT and farming-adjacent names
print('--- 1. Direct lookup: PLANT and related names ---')
local candidates = {'PLANT', 'GROWER', 'PLANT_GATHER', 'HERBALIST', 'FARMING', 'GROWING'}
for _, cname in ipairs(candidates) do
    local ok, val = pcall(function() return df.job_skill[cname] end)
    if ok and val ~= nil then
        local caption = '?'
        pcall(function()
            local attrs = df.job_skill.attrs[val]
            if attrs then caption = tostring(attrs.caption or '?') end
        end)
        print(('  df.job_skill["%s"] = %d  caption="%s"'):format(cname, val, caption))
    else
        print(('  df.job_skill["%s"] = nil/not found'):format(cname))
    end
end
print('')

-- 2. Dump first 30 enum entries (int -> name) to see ordering
print('--- 2. job_skill entries 0..29 ---')
for i = 0, 29 do
    local ok, name = pcall(function() return df.job_skill[i] end)
    local caption = ''
    pcall(function()
        local attrs = df.job_skill.attrs[i]
        if attrs then caption = ' caption="' .. tostring(attrs.caption or '') .. '"' end
    end)
    if ok and name then
        print(('  [%d] %s%s'):format(i, name, caption))
    else
        print(('  [%d] (no entry)'):format(i))
    end
end
print('')

print('=== END PROBE ===')
