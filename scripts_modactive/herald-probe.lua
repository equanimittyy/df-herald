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
-- PROBE: artifact_record, artifact events, written_content
--
-- Goal: map the fields needed to implement herald-ind-artifacts.
-- Steps:
--   1. Enumerate all artifact_record instances; dump fields of first sample
--   2. Check if artifact_record has a creator HF field (for reverse lookup)
--   3. Explore written_content struct fields
--   4. Find sample events of each artifact type in world history
--   5. Dump actual fields on each sample event to verify df-api-reference
--   6. Check global artifact vectors / lookup paths
-- ============================================================

local util = dfhack.reqscript('herald-util')
local safe_get = util.safe_get

print('=== START PROBE: ARTIFACTS ===')
print('')

-- Helper: translate a name or return fallback
local function name_or(obj, fallback)
    if not obj then return fallback end
    local ok, n = pcall(function() return dfhack.translation.translateName(obj.name, true) end)
    return (ok and n and n ~= '') and n or fallback
end

-- Helper: print all accessible fields on a DF struct
local function dump_fields(obj, label, indent)
    indent = indent or '  '
    print(label .. ':')
    local ok = pcall(function() printall(obj) end)
    if not ok then print(indent .. '(printall failed)') end
end

-- ================================================================
-- SECTION 1: artifact_record struct
-- ================================================================
print('[1] artifact_record struct exploration')
print('---------------------------------------')

-- Try global artifact vectors
local ARTIFACT_PATHS = {
    'df.global.world.artifacts.all',
    'df.global.world.artifacts',
}

local artifacts_vec = nil
local artifacts_path = nil

-- Try .all first (newer DF), then plain .artifacts
local ok1, a1 = pcall(function() return df.global.world.artifacts.all end)
if ok1 and a1 then
    local ok_n, n = pcall(function() return #a1 end)
    if ok_n and n and n > 0 then
        artifacts_vec = a1
        artifacts_path = 'df.global.world.artifacts.all'
    end
end
if not artifacts_vec then
    local ok2, a2 = pcall(function() return df.global.world.artifacts end)
    if ok2 and a2 then
        local ok_n, n = pcall(function() return #a2 end)
        if ok_n and n and n > 0 then
            artifacts_vec = a2
            artifacts_path = 'df.global.world.artifacts'
        end
    end
end

if not artifacts_vec then
    print('  WARNING: no global artifacts vector found. Trying df.artifact_record.find...')
    -- Try finding by ID 0..100
    for test_id = 0, 100 do
        local ok, art = pcall(function() return df.artifact_record.find(test_id) end)
        if ok and art then
            print(('  Found artifact by find(%d)'):format(test_id))
            artifacts_vec = { art }
            artifacts_path = 'df.artifact_record.find()'
            break
        end
    end
end

if artifacts_vec then
    local count = 0
    pcall(function() count = #artifacts_vec end)
    print(('  Artifact source: %s (%d entries)'):format(artifacts_path, count))
else
    print('  ERROR: could not find any artifacts in the world')
    print('=== END PROBE ===')
    return
end
print('')

-- Grab first artifact and dump its fields
local sample_art = nil
local ok_sa, sa = pcall(function() return artifacts_vec[0] end)
if ok_sa and sa then sample_art = sa end

if sample_art then
    print('[1a] printall(artifact_record):')
    dump_fields(sample_art, '  Fields')
    print('')

    -- Probe specific field candidates
    print('[1b] Probing specific field candidates:')
    local ART_FIELDS = {
        'id', 'name', 'item', 'flags', 'abs_tile_x', 'abs_tile_y',
        'holder_hf', 'creator_hf', 'creator_hfid', 'maker', 'maker_hf',
        'site', 'site_id', 'holder', 'owner_hf', 'owner_hist_figure_id',
        'storage_site_id', 'loss_region',
        'anon_1', 'anon_2', 'anon_3', 'anon_4', 'anon_5',
        'unk_1', 'unk_2', 'unk_3', 'unk_4',
    }
    for _, fname in ipairs(ART_FIELDS) do
        local ok_f, v = pcall(function() return sample_art[fname] end)
        if ok_f and v ~= nil then
            print(('    .%s = %s (%s)'):format(fname, tostring(v), type(v)))
        end
    end
    print('')

    -- Try to get the artifact name
    local art_name = name_or(sample_art, '(unnamed)')
    print(('  Sample artifact: id=%d name="%s"'):format(
        safe_get(sample_art, 'id') or -1, art_name))

    -- Explore the .item sub-object
    local ok_item, item = pcall(function() return sample_art.item end)
    if ok_item and item then
        print('')
        print('[1c] artifact.item sub-object:')
        dump_fields(item, '  item fields')
        -- Item type
        local ok_t, itype = pcall(function() return item:getType() end)
        if ok_t then
            local type_name = df.item_type and df.item_type[itype] or '?'
            print(('    :getType() = %s (%s)'):format(tostring(itype), tostring(type_name)))
        end
        -- Material
        local ok_m, mt = pcall(function() return item:getActualMaterial() end)
        local ok_mi, mi = pcall(function() return item:getActualMaterialIndex() end)
        if ok_m and ok_mi and mt >= 0 then
            local ok_d, info = pcall(function() return dfhack.matinfo.decode(mt, mi) end)
            if ok_d and info then
                local ok_s, s = pcall(function() return info:toString() end)
                if ok_s then print(('    material = %s'):format(s)) end
            end
        end
    else
        print('  artifact.item: not accessible')
    end
    print('')
else
    print('  WARNING: could not access artifacts_vec[0]')
end

-- ================================================================
-- SECTION 2: Enumerate a few artifacts to check creator HF pattern
-- ================================================================
print('[2] Checking multiple artifacts for creator/holder fields')
print('----------------------------------------------------------')

local limit = math.min(9, (pcall(function() return #artifacts_vec - 1 end) and #artifacts_vec - 1 or 0))
for i = 0, limit do
    local ok, art = pcall(function() return artifacts_vec[i] end)
    if not ok or not art then goto next_art end
    local art_id = safe_get(art, 'id') or i
    local art_name = name_or(art, '?')
    local holder = safe_get(art, 'holder_hf') or safe_get(art, 'holder')
    local creator = safe_get(art, 'creator_hf') or safe_get(art, 'creator_hfid')
    local site = safe_get(art, 'site') or safe_get(art, 'site_id')
    print(('  [%d] id=%d name="%s" holder=%s creator=%s site=%s'):format(
        i, art_id, art_name,
        tostring(holder), tostring(creator), tostring(site)))
    ::next_art::
end
print('')

-- ================================================================
-- SECTION 3: written_content struct
-- ================================================================
print('[3] written_content struct')
print('---------------------------')

local wc_vec = nil
local ok_wc, wv = pcall(function() return df.global.world.written_contents.all end)
if ok_wc and wv then
    local ok_n, n = pcall(function() return #wv end)
    if ok_n and n and n > 0 then
        wc_vec = wv
        print(('  Source: df.global.world.written_contents.all (%d entries)'):format(n))
    end
end
if not wc_vec then
    local ok_wc2, wv2 = pcall(function() return df.global.world.written_contents end)
    if ok_wc2 and wv2 then
        local ok_n, n = pcall(function() return #wv2 end)
        if ok_n and n and n > 0 then
            wc_vec = wv2
            print(('  Source: df.global.world.written_contents (%d entries)'):format(n))
        end
    end
end

if wc_vec then
    local sample_wc = nil
    local ok_s, sw = pcall(function() return wc_vec[0] end)
    if ok_s and sw then sample_wc = sw end

    if sample_wc then
        print('')
        print('[3a] printall(written_content):')
        dump_fields(sample_wc, '  Fields')
        print('')

        -- Probe specific fields
        print('[3b] Specific fields:')
        local WC_FIELDS = {
            'id', 'title', 'page_start', 'page_end',
            'author', 'author_hf', 'author_hfid', 'histfig',
            'type', 'style', 'form', 'form_id',
            'poetic_form', 'musical_form', 'dance_form',
            'subject', 'subject_id', 'reference_id',
            'anon_1', 'anon_2',
        }
        for _, fname in ipairs(WC_FIELDS) do
            local ok_f, v = pcall(function() return sample_wc[fname] end)
            if ok_f and v ~= nil then
                print(('    .%s = %s (%s)'):format(fname, tostring(v), type(v)))
            end
        end
        print('')

        -- Show a few written contents with titles
        print('[3c] First 10 written contents:')
        local wc_limit = math.min(9, #wc_vec - 1)
        for i = 0, wc_limit do
            local ok_w, wc = pcall(function() return wc_vec[i] end)
            if not ok_w or not wc then goto next_wc end
            local wc_id = safe_get(wc, 'id') or i
            local title = safe_get(wc, 'title') or '(no title)'
            local author = safe_get(wc, 'author') or safe_get(wc, 'author_hf') or safe_get(wc, 'author_hfid') or -1
            local author_name = '?'
            if type(author) == 'number' and author >= 0 then
                author_name = util.hf_name(author)
            end
            print(('    [%d] id=%d title="%s" author=%s (%s)'):format(
                i, wc_id, tostring(title), tostring(author), author_name))
            ::next_wc::
        end
    else
        print('  WARNING: could not access wc_vec[0]')
    end
else
    print('  No written_content vector found')
end
print('')

-- ================================================================
-- SECTION 4: Find sample artifact events in world history
-- ================================================================
print('[4] Scanning world events for artifact-related types')
print('-----------------------------------------------------')

local TARGET_TYPES = {
    'ARTIFACT_CREATED', 'ARTIFACT_STORED', 'ARTIFACT_POSSESSED',
    'ARTIFACT_CLAIM_FORMED', 'ITEM_STOLEN', 'WRITTEN_CONTENT_COMPOSED',
}

-- Build lookup set
local target_set = {}
for _, tname in ipairs(TARGET_TYPES) do
    local ok, val = pcall(function() return df.history_event_type[tname] end)
    if ok and val then
        target_set[val] = tname
        print(('  Type enum: %s = %d'):format(tname, val))
    else
        print(('  WARNING: type %s not in enum'):format(tname))
    end
end
print('')

-- Scan events (from the end, since artifact events tend to be later)
local events = df.global.world.history.events
local total_events = #events
print(('  Total events: %d'):format(total_events))

local found_samples = {}  -- type_name -> event
local found_count = 0
local needed = 0
for _ in pairs(target_set) do needed = needed + 1 end

-- Scan backwards from end for efficiency
for i = total_events - 1, math.max(0, total_events - 5000), -1 do
    if found_count >= needed then break end
    local ok, ev = pcall(function() return events[i] end)
    if not ok or not ev then goto next_ev end
    local ok_t, etype = pcall(function() return ev:getType() end)
    if not ok_t then goto next_ev end
    local tname = target_set[etype]
    if tname and not found_samples[tname] then
        found_samples[tname] = ev
        found_count = found_count + 1
    end
    ::next_ev::
end

print(('  Found %d/%d target event types in last 5000 events'):format(found_count, needed))
print('')

-- ================================================================
-- SECTION 5: Dump fields on each found event
-- ================================================================
print('[5] Detailed field dump per artifact event type')
print('-------------------------------------------------')

for _, tname in ipairs(TARGET_TYPES) do
    local ev = found_samples[tname]
    if not ev then
        print(('  %s: NOT FOUND'):format(tname))
        print('')
        goto next_type
    end

    print(('  %s (id=%d, year=%s):'):format(tname, ev.id, tostring(safe_get(ev, 'year'))))
    dump_fields(ev, '    printall')

    -- Probe known + candidate fields per type
    local FIELDS_BY_TYPE = {
        ARTIFACT_CREATED = {
            'creator_hfid', 'creator_hf', 'histfig', 'hfid',
            'artifact_id', 'artifact_record', 'artifact', 'item',
            'site', 'unit_id', 'name_only',
        },
        ARTIFACT_STORED = {
            'histfig', 'hfid', 'artifact', 'artifact_id', 'artifact_record',
            'site', 'unit_id',
        },
        ARTIFACT_POSSESSED = {
            'histfig', 'hfid', 'artifact', 'artifact_id', 'artifact_record',
            'site', 'unit_id',
        },
        ARTIFACT_CLAIM_FORMED = {
            'histfig', 'hfid', 'artifact', 'artifact_id',
            'entity', 'claim_type', 'position_profile',
        },
        ITEM_STOLEN = {
            'histfig', 'hfid', 'item_type', 'item_subtype', 'item',
            'mattype', 'matindex', 'entity', 'site', 'structure',
        },
        WRITTEN_CONTENT_COMPOSED = {
            'histfig', 'hfid', 'content', 'wc_id', 'site', 'reason', 'circumstance',
        },
    }

    local fields = FIELDS_BY_TYPE[tname] or {}
    for _, fname in ipairs(fields) do
        local ok_f, v = pcall(function() return ev[fname] end)
        if ok_f and v ~= nil then
            print(('      .%s = %s (%s)'):format(fname, tostring(v), type(v)))
        end
    end

    -- For ARTIFACT_CREATED/STORED/POSSESSED: resolve the artifact name
    if tname:find('ARTIFACT') then
        local art_id = safe_get(ev, 'artifact_id') or safe_get(ev, 'artifact_record') or safe_get(ev, 'artifact')
        if art_id and art_id >= 0 then
            local ok_a, art = pcall(function() return df.artifact_record.find(art_id) end)
            if ok_a and art then
                local aname = name_or(art, '(unnamed)')
                print(('      -> artifact name: "%s"'):format(aname))
            end
        end
    end

    -- For WRITTEN_CONTENT_COMPOSED: resolve the written content
    if tname == 'WRITTEN_CONTENT_COMPOSED' then
        local wc_id = safe_get(ev, 'content')
        if wc_id and wc_id >= 0 then
            local ok_w, wc = pcall(function() return df.written_content.find(wc_id) end)
            if ok_w and wc then
                local title = safe_get(wc, 'title') or '(no title)'
                print(('      -> written content title: "%s"'):format(title))
            end
        end
    end

    -- For any HF field: resolve the name
    local hf_id = safe_get(ev, 'creator_hfid') or safe_get(ev, 'histfig') or safe_get(ev, 'hfid')
    if hf_id and hf_id >= 0 then
        print(('      -> HF name: "%s"'):format(util.hf_name(hf_id)))
    end

    print('')
    ::next_type::
end

-- ================================================================
-- SECTION 6: Count artifact events by type across all history
-- ================================================================
print('[6] Artifact event type distribution (full scan)')
print('--------------------------------------------------')

local type_counts = {}
for _, tname in ipairs(TARGET_TYPES) do type_counts[tname] = 0 end

for i = 0, total_events - 1 do
    local ok, ev = pcall(function() return events[i] end)
    if not ok or not ev then goto next_count end
    local ok_t, etype = pcall(function() return ev:getType() end)
    if not ok_t then goto next_count end
    local tname = target_set[etype]
    if tname then type_counts[tname] = type_counts[tname] + 1 end
    ::next_count::
end

for _, tname in ipairs(TARGET_TYPES) do
    print(('  %s: %d events'):format(tname, type_counts[tname]))
end
print('')

print('=== END PROBE ===')
