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

print('=== START PROBE: HF-HF Link Types (Worship) ===')

-- 1. Dump histfig_hf_link_type enum
print('')
print('--- histfig_hf_link_type enum ---')
local ok, LT = pcall(function() return df.histfig_hf_link_type end)
if ok and LT then
    for i = 0, 30 do
        local name = LT[i]
        if name then
            print(('  %2d = %s'):format(i, name))
        end
    end
else
    print('  NOT FOUND')
end

-- 2. Scan world history for ADD/REMOVE_HF_HF_LINK events, show DEITY ones
print('')
print('--- ADD/REMOVE_HF_HF_LINK events (first 20 DEITY matches) ---')
local events = df.global.world.history.events
local ET = df.history_event_type
local add_type = ET.ADD_HF_HF_LINK
local rem_type = ET.REMOVE_HF_HF_LINK
local count = 0
local max_show = 20

-- also collect all distinct link types seen across all HF-HF events
local seen_types = {}

for i = #events - 1, 0, -1 do
    local ev = events[i]
    local etype = ev:getType()
    if etype == add_type or etype == rem_type then
        local ltype = ev.type
        local ltype_name = LT and LT[ltype] or tostring(ltype)
        seen_types[ltype_name] = (seen_types[ltype_name] or 0) + 1

        -- show DEITY-related events
        if LT and (ltype_name == 'DEITY' or ltype_name == 'FORMER_DEITY') then
            if count < max_show then
                local ename = ET[etype]
                local yr = ev.year
                local hf = ev.hf
                local tgt = ev.hf_target
                -- resolve names
                local hf_obj = df.historical_figure.find(hf)
                local tgt_obj = df.historical_figure.find(tgt)
                local hf_name = hf_obj and dfhack.translation.translateName(hf_obj.name, true) or '?'
                local tgt_name = tgt_obj and dfhack.translation.translateName(tgt_obj.name, true) or '?'
                print(('  [yr%d] %s type=%s(%d)'):format(yr, ename, ltype_name, ltype))
                print(('         hf=%d (%s)  hf_target=%d (%s)'):format(hf, hf_name, tgt, tgt_name))
                -- check if target is a deity
                if tgt_obj then
                    local flags = tgt_obj.flags
                    local is_deity = flags and flags.deity
                    local is_force = flags and flags.force
                    print(('         target flags: deity=%s force=%s'):format(
                        tostring(is_deity), tostring(is_force)))
                end
                count = count + 1
            end
        end
    end
end

print('')
print(('--- All HF-HF link types seen (across %d events scanned) ---'):format(#events))
for name, c in pairs(seen_types) do
    print(('  %-25s count=%d'):format(name, c))
end

-- 3. Check a live HF's links for deity references
print('')
print('--- Sample HF deity links (first 5 HFs with deity links) ---')
local hf_count = 0
for i = #df.global.world.history.figures - 1, 0, -1 do
    if hf_count >= 5 then break end
    local hf = df.global.world.history.figures[i]
    if hf and hf.histfig_links then
        for j = 0, #hf.histfig_links - 1 do
            local link = hf.histfig_links[j]
            local cname = link._type and tostring(link._type) or '?'
            if cname:find('Deity') or cname:find('deity') then
                local hf_name = dfhack.translation.translateName(hf.name, true)
                print(('  HF %d (%s) link[%d]: %s'):format(hf.id, hf_name, j, cname))
                printall(link)
                hf_count = hf_count + 1
                break
            end
        end
    end
end

print('')
print('=== END PROBE ===')
