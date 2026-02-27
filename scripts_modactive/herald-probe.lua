--@ module=true

--[====[
herald-probe
============
Debug utility for inspecting live DF data. Edit the probe code below as needed,
then run via: herald-main probe
Requires debug mode: herald-main debug true

Not intended for direct use.
]====]

local main = dfhack.reqscript('herald-main')

if not main.DEBUG then
    dfhack.printerr('[Herald] Probe requires debug mode. Enable with: herald-main debug true')
    return
end

print('=== START PROBE ===')

-- Dump all body_abuse_method_type enum values.
print('body_abuse_method_type enum:')
for k, v in ipairs(df.body_abuse_method_type) do
    print('  [' .. k .. '] = ' .. tostring(v))
end

print('=== END PROBE ===')
