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
-- PROBE: herald-ind-artifacts handler verification
--
-- Tests each event type the handler covers by finding real
-- events in world history and running them through the handler's
-- name resolution and message formatting logic.
-- ============================================================

local util = dfhack.reqscript('herald-util')
local pins = dfhack.reqscript('herald-pins')
local safe_get = util.safe_get

print('=== START PROBE: ARTIFACT HANDLER VERIFICATION ===')
print('')

-- Helper: translate a name or return fallback
local function name_or(obj, fallback)
    if not obj then return fallback end
    local ok, n = pcall(function() return dfhack.translation.translateName(obj.name, true) end)
    return (ok and n and n ~= '') and n or fallback
end

-- ================================================================
-- SECTION 1: Check pinned HFs and their artifact settings
-- ================================================================
print('[1] Pinned HF artifact settings')
print('---------------------------------')

local pinned = pins.get_pinned()
local pin_count = 0
for hf_id, settings in pairs(pinned) do
    pin_count = pin_count + 1
    local art_on = settings and settings.artifacts
    print(('  HF %d (%s) - artifacts: %s'):format(
        hf_id, util.hf_name(hf_id), tostring(art_on)))
end
if pin_count == 0 then
    print('  No pinned HFs. Pin some HFs to test event matching.')
end
print('')

-- ================================================================
-- SECTION 2: Test get_artifact_label on real artifacts
-- ================================================================
print('[2] Artifact label resolution (first 10 artifacts)')
print('----------------------------------------------------')

local artifacts_vec = nil
local ok1, a1 = pcall(function() return df.global.world.artifacts.all end)
if ok1 and a1 then
    local ok_n, n = pcall(function() return #a1 end)
    if ok_n and n and n > 0 then artifacts_vec = a1 end
end

if artifacts_vec then
    local art_handler = dfhack.reqscript('herald-handlers/herald-ind-artifacts')
    local limit = math.min(9, #artifacts_vec - 1)
    for i = 0, limit do
        local ok, art = pcall(function() return artifacts_vec[i] end)
        if ok and art then
            local art_id = safe_get(art, 'id') or i
            -- Replicate get_artifact_label logic inline to show each tier
            local translated = name_or(art, nil)
            local item_desc = nil
            local ok3, item = pcall(function() return art.item end)
            if ok3 and item then
                local ok4, itype = pcall(function() return item:getType() end)
                local type_s = ok4 and itype and df.item_type and df.item_type[itype]
                local mat_s
                local ok5, mt = pcall(function() return item:getActualMaterial() end)
                local ok6, mi = pcall(function() return item:getActualMaterialIndex() end)
                if ok5 and ok6 and mt and mt >= 0 then
                    local ok7, info = pcall(function() return dfhack.matinfo.decode(mt, mi) end)
                    if ok7 and info then
                        local ok8, s = pcall(function() return info:toString() end)
                        if ok8 and s and s ~= '' then mat_s = s:lower() end
                    end
                end
                if mat_s and type_s then
                    item_desc = mat_s .. ' ' .. tostring(type_s):lower()
                elseif type_s then
                    item_desc = tostring(type_s):lower()
                end
            end

            local label
            if translated then
                label = 'the artifact ' .. translated
            elseif item_desc then
                label = 'a ' .. item_desc .. ' artifact'
            else
                label = 'an artifact'
            end

            print(('  [%d] id=%d -> "%s"'):format(i, art_id, label))
            if translated then print(('       (name: %s, item: %s)'):format(translated, item_desc or 'n/a')) end
        end
    end
else
    print('  No artifacts found in world')
end
print('')

-- ================================================================
-- SECTION 3: Test get_written_title on real written content
-- ================================================================
print('[3] Written content title resolution (first 10)')
print('--------------------------------------------------')

local wc_vec = nil
local ok_wc, wv = pcall(function() return df.global.world.written_contents.all end)
if ok_wc and wv then
    local ok_n, n = pcall(function() return #wv end)
    if ok_n and n and n > 0 then wc_vec = wv end
end

if wc_vec then
    local limit = math.min(9, #wc_vec - 1)
    for i = 0, limit do
        local ok, wc = pcall(function() return wc_vec[i] end)
        if ok and wc then
            local wc_id = safe_get(wc, 'id') or i
            local title = safe_get(wc, 'title')
            local has_title = title and title ~= ''
            local display = has_title and ('"' .. title .. '"') or 'a written work'
            print(('  [%d] id=%d -> %s'):format(i, wc_id, display))
        end
    end
else
    print('  No written content found in world')
end
print('')

-- ================================================================
-- SECTION 4: Raw field dump on sample events (field discovery)
-- ================================================================
print('[4] Raw field dump per event type')
print('-----------------------------------')

local PROBE_TYPES = {
    'ARTIFACT_CREATED', 'ARTIFACT_STORED', 'ARTIFACT_POSSESSED',
    'ARTIFACT_CLAIM_FORMED', 'WRITTEN_CONTENT_COMPOSED',
}

local CANDIDATE_FIELDS = {
    'creator_hfid', 'histfig', 'hfid', 'hf',
    'artifact_id', 'artifact', 'item', 'item_id',
    'site', 'site_id', 'entity', 'entity_id',
    'wc', 'wc_id', 'content', 'written_content_id',
    'reason', 'circumstance', 'claim_type', 'position_profile',
    'mattype', 'matindex', 'item_type', 'item_subtype',
    'unit_id', 'name_only', 'structure',
}

-- Find one sample per type
local probe_set = {}
for _, tname in ipairs(PROBE_TYPES) do
    local ok, val = pcall(function() return df.history_event_type[tname] end)
    if ok and val then probe_set[val] = tname end
end

local probe_events = df.global.world.history.events
local probe_total = #probe_events
local probe_samples = {}
local probe_found = 0
local probe_needed = 0
for _ in pairs(probe_set) do probe_needed = probe_needed + 1 end

for i = probe_total - 1, math.max(0, probe_total - 10000), -1 do
    if probe_found >= probe_needed then break end
    local ok, ev = pcall(function() return probe_events[i] end)
    if not ok or not ev then goto next_probe end
    local ok_t, etype = pcall(function() return ev:getType() end)
    if not ok_t then goto next_probe end
    local tname = probe_set[etype]
    if tname and not probe_samples[tname] then
        probe_samples[tname] = ev
        probe_found = probe_found + 1
    end
    ::next_probe::
end

for _, tname in ipairs(PROBE_TYPES) do
    local ev = probe_samples[tname]
    if not ev then
        print(('  %s: NO SAMPLE'):format(tname))
    else
        print(('  %s (ev.id=%d):'):format(tname, ev.id))
        print('    printall:')
        pcall(function() printall(ev) end)
        print('    candidate fields:')
        for _, fname in ipairs(CANDIDATE_FIELDS) do
            local ok_f, v = pcall(function() return ev[fname] end)
            if ok_f and v ~= nil then
                print(('      .%s = %s (%s)'):format(fname, tostring(v), type(v)))
            end
        end
    end
    print('')
end

-- ================================================================
-- SECTION 5: Simulated handler dispatch for each event type
-- ================================================================
print('[5] Simulated handler dispatch on real events')
print('------------------------------------------------')

local EVENT_TYPES = {
    {'ARTIFACT_CREATED',            'creator_hfid'},
    {'ARTIFACT_STORED',             'histfig'},
    {'ARTIFACT_POSSESSED',          'histfig'},
    {'ARTIFACT_CLAIM_FORMED',       'histfig'},
    {'WRITTEN_CONTENT_COMPOSED',    'histfig'},
}

local events = df.global.world.history.events
local total_events = #events

-- Build target set
local target_set = {}
for _, entry in ipairs(EVENT_TYPES) do
    local tname, hf_field = entry[1], entry[2]
    local ok, val = pcall(function() return df.history_event_type[tname] end)
    if ok and val then
        target_set[val] = {name = tname, hf_field = hf_field}
    end
end

-- Find one sample of each type (scan backwards for speed)
local samples = {}
local found = 0
local needed = 0
for _ in pairs(target_set) do needed = needed + 1 end

for i = total_events - 1, math.max(0, total_events - 10000), -1 do
    if found >= needed then break end
    local ok, ev = pcall(function() return events[i] end)
    if not ok or not ev then goto next_ev end
    local ok_t, etype = pcall(function() return ev:getType() end)
    if not ok_t then goto next_ev end
    local info = target_set[etype]
    if info and not samples[info.name] then
        samples[info.name] = ev
        found = found + 1
    end
    ::next_ev::
end

print(('  Found %d/%d event types in last 10000 events'):format(found, needed))
print('')

for _, entry in ipairs(EVENT_TYPES) do
    local tname, hf_field = entry[1], entry[2]
    local ev = samples[tname]
    if not ev then
        print(('  %s: NO SAMPLE FOUND'):format(tname))
        print('')
        goto next_type
    end

    local hf_id = safe_get(ev, hf_field) or -1
    local hf = hf_id >= 0 and util.hf_name(hf_id) or '(unknown)'
    local is_pinned = pinned[hf_id] and true or false
    local site_id = safe_get(ev, 'site') or -1
    local site = site_id >= 0 and util.site_name(site_id) or '(no site)'

    print(('  %s (ev.id=%d, year=%s):'):format(tname, ev.id, tostring(safe_get(ev, 'year'))))
    print(('    HF: %d (%s) pinned=%s'):format(hf_id, hf, tostring(is_pinned)))
    print(('    Site: %d (%s)'):format(site_id, site))

    -- Type-specific details and simulated message
    if tname == 'ARTIFACT_CREATED' or tname == 'ARTIFACT_STORED'
        or tname == 'ARTIFACT_POSSESSED' then
        -- CREATED uses 'artifact_id'; STORED/POSSESSED use 'artifact'
        local art_id = safe_get(ev, 'artifact_id') or safe_get(ev, 'artifact') or -1
        local art_name = '(not found)'
        if art_id >= 0 then
            local ok_a, art = pcall(function() return df.artifact_record.find(art_id) end)
            if ok_a and art then art_name = name_or(art, '(unnamed)') end
        end
        print(('    Artifact: %d (%s)'):format(art_id, art_name))

        local verb = tname == 'ARTIFACT_CREATED' and 'created'
            or tname == 'ARTIFACT_STORED' and 'stored'
            or 'claimed'
        -- Simulate the announcement
        if art_id >= 0 then
            -- Inline label resolution
            local label = 'an artifact'
            if art_name ~= '(unnamed)' and art_name ~= '(not found)' then
                label = 'the artifact ' .. art_name
            end
            local msg
            if site_id >= 0 then
                msg = ('%s %s %s in %s.'):format(hf, verb, label, site)
            else
                msg = ('%s %s %s.'):format(hf, verb, label)
            end
            print(('    -> MSG: %s'):format(msg))
        end

    elseif tname == 'ARTIFACT_CLAIM_FORMED' then
        local art_id = safe_get(ev, 'artifact') or -1
        local entity_id = safe_get(ev, 'entity') or -1
        local art_name = '(not found)'
        if art_id >= 0 then
            local ok_a, art = pcall(function() return df.artifact_record.find(art_id) end)
            if ok_a and art then art_name = name_or(art, '(unnamed)') end
        end
        print(('    Artifact: %d (%s)'):format(art_id, art_name))
        print(('    Entity: %d (%s)'):format(entity_id,
            entity_id >= 0 and util.ent_name(entity_id) or '(none)'))

        local label = (art_name ~= '(unnamed)' and art_name ~= '(not found)')
            and ('the artifact ' .. art_name) or 'an artifact'
        local msg
        if entity_id >= 0 then
            msg = ('%s formed a claim on %s on behalf of %s.'):format(
                hf, label, util.ent_name(entity_id))
        else
            msg = ('%s formed a claim on %s.'):format(hf, label)
        end
        print(('    -> MSG: %s'):format(msg))

    elseif tname == 'WRITTEN_CONTENT_COMPOSED' then
        local wc_id = safe_get(ev, 'content') or -1
        local title = nil
        if wc_id >= 0 then
            local ok_w, wc = pcall(function() return df.written_content.find(wc_id) end)
            if ok_w and wc then
                local ok2, t = pcall(function() return wc.title end)
                if ok2 and t and t ~= '' then title = t end
            end
        end
        local work = title and ('"' .. title .. '"') or 'a written work'
        print(('    Written content: %d (title: %s)'):format(wc_id, work))

        local msg
        if site_id >= 0 then
            msg = ('%s composed %s in %s.'):format(hf, work, site)
        else
            msg = ('%s composed %s.'):format(hf, work)
        end
        print(('    -> MSG: %s'):format(msg))
    end

    print('')
    ::next_type::
end

-- ================================================================
-- SECTION 6: Event type distribution
-- ================================================================
print('[6] Artifact event counts (full history)')
print('------------------------------------------')

local type_counts = {}
for _, entry in ipairs(EVENT_TYPES) do type_counts[entry[1]] = 0 end

for i = 0, total_events - 1 do
    local ok, ev = pcall(function() return events[i] end)
    if not ok or not ev then goto next_count end
    local ok_t, etype = pcall(function() return ev:getType() end)
    if not ok_t then goto next_count end
    local info = target_set[etype]
    if info then type_counts[info.name] = type_counts[info.name] + 1 end
    ::next_count::
end

for _, entry in ipairs(EVENT_TYPES) do
    print(('  %s: %d'):format(entry[1], type_counts[entry[1]]))
end
print('')

-- ================================================================
-- SECTION 7: Check for pinned HF matches in recent artifact events
-- ================================================================
print('[7] Pinned HF matches in last 5000 events')
print('--------------------------------------------')

if pin_count == 0 then
    print('  No pinned HFs - skipping')
else
    local matches = 0
    for i = total_events - 1, math.max(0, total_events - 5000), -1 do
        local ok, ev = pcall(function() return events[i] end)
        if not ok or not ev then goto next_match end
        local ok_t, etype = pcall(function() return ev:getType() end)
        if not ok_t then goto next_match end
        local info = target_set[etype]
        if not info then goto next_match end

        local hf_id = safe_get(ev, info.hf_field) or -1
        if pinned[hf_id] then
            matches = matches + 1
            local settings = pinned[hf_id]
            local art_on = settings and settings.artifacts
            print(('  ev.id=%d %s HF=%d (%s) artifacts=%s'):format(
                ev.id, info.name, hf_id, util.hf_name(hf_id), tostring(art_on)))
            if matches >= 20 then
                print('  ... (capped at 20)')
                break
            end
        end
        ::next_match::
    end
    if matches == 0 then
        print('  No artifact events found for pinned HFs in last 5000 events')
    end
end
print('')

print('=== END PROBE ===')
