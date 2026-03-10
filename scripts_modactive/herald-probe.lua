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
-- PROBE: historical_figure.info.skills structure
--
-- Goal: determine the actual field layout.
-- Hypothesis: parallel vectors (skills=job_skill IDs, points=experience).
-- Null hypothesis: objects with .id and .rating (like unit soul skills).
--
-- Steps:
--   1. Find any HF that has skills data (info and info.skills not nil)
--   2. printall() the skills sub-struct to see all field names
--   3. Check element type: is skills[0] a number or a userdata object?
--   4. If parallel vectors: print skills[i] and points[i] for first 5
--   5. Try to derive a skill rating: compare points values to known
--      legendary threshold (5400 xp = Legendary per DF skill tables)
-- ============================================================

print('=== START PROBE: HF INFO SKILLS ===')
print('')

-- Step 1: find an HF with skills populated -------------------------
local figures = df.global.world.history.figures
print(('Total historical figures: %d'):format(#figures))
print('')

local sample_hf = nil
local sample_idx = 0

for i = 0, math.min(#figures - 1, 2000) do
    local ok, hf = pcall(function() return figures[i] end)
    if not ok or not hf then goto next end
    local ok2, info = pcall(function() return hf.info end)
    if not ok2 or not info then goto next end
    local ok3, skills_block = pcall(function() return info.skills end)
    if not ok3 or not skills_block then goto next end
    -- Check there is at least one skills entry
    local ok4, skills_vec = pcall(function() return skills_block.skills end)
    if not ok4 or not skills_vec then goto next end
    local ok5, sz = pcall(function() return #skills_vec end)
    if not ok5 or not sz or sz == 0 then goto next end
    sample_hf = hf
    sample_idx = i
    break
    ::next::
end

if not sample_hf then
    print('ERROR: no HF with info.skills found in first 2000 figures')
    print('=== END PROBE ===')
    return
end

local hf_name = '?'
local ok_n, n = pcall(function()
    return dfhack.translation.translateName(sample_hf.name, true)
end)
if ok_n and n and n ~= '' then hf_name = n end

print(('Found HF at index %d: %s (id=%d)'):format(sample_idx, hf_name, sample_hf.id))
print('')

-- Step 2: printall() the skills sub-struct -------------------------
print('[1] printall(hf.info.skills):')
local ok_pa, skills_block = pcall(function() return sample_hf.info.skills end)
if ok_pa and skills_block then
    printall(skills_block)
else
    print('  ERROR: could not access info.skills')
end
print('')

-- Step 3: check element type of skills vector ----------------------
print('[2] Checking element type of info.skills.skills[0]:')
local ok_sv, skills_vec = pcall(function() return sample_hf.info.skills.skills end)
if ok_sv and skills_vec then
    print(('  #skills_vec = %d'):format(#skills_vec))
    local ok_e, elem = pcall(function() return skills_vec[0] end)
    if ok_e and elem ~= nil then
        print(('  type(skills_vec[0]) = %s'):format(type(elem)))
        print(('  tostring(skills_vec[0]) = %s'):format(tostring(elem)))
        -- If it's userdata, try printall
        if type(elem) == 'userdata' then
            print('  printall(skills_vec[0]):')
            printall(elem)
        end
    else
        print('  Could not access skills_vec[0]')
    end
else
    print('  ERROR: could not access info.skills.skills')
end
print('')

-- Step 4: enumerate all named sub-fields ---------------------------
print('[3] Probing all known field names on info.skills:')
local CANDIDATE_FIELDS = {
    'skills', 'points', 'skill_ids', 'skill_levels', 'ratings',
    'experience', 'xp', 'level', 'levels', 'unk_0', 'unk_20', 'unk_30',
}
local found_fields = {}
for _, fname in ipairs(CANDIDATE_FIELDS) do
    local ok_f, v = pcall(function() return sample_hf.info.skills[fname] end)
    if ok_f and v ~= nil then
        local sz_str = ''
        if type(v) == 'userdata' then
            local ok_sz, sz = pcall(function() return #v end)
            if ok_sz then sz_str = (' [size=%d]'):format(sz) end
        end
        print(('  skills.%s = %s (%s)%s'):format(fname, tostring(v), type(v), sz_str))
        table.insert(found_fields, fname)
    end
end
print('')

-- Step 5: if parallel vectors, dump first 5 entries ---------------
local ok_sv2, sv2 = pcall(function() return sample_hf.info.skills.skills end)
local ok_pv, pv  = pcall(function() return sample_hf.info.skills.points end)

if ok_sv2 and sv2 and ok_pv and pv then
    print('[4] First 5 entries of parallel vectors (skills / points):')
    local limit = math.min(#sv2 - 1, 4)
    for i = 0, limit do
        local ok_s, sid = pcall(function() return sv2[i] end)
        local ok_p, pts = pcall(function() return pv[i] end)
        local skill_name = '?'
        if ok_s and sid ~= nil then
            local ok_sn, sn = pcall(function()
                return df.job_skill.attrs[sid].caption
            end)
            if ok_sn and sn then skill_name = sn end
        end
        print(('  [%d] skill_id=%s (%s) points=%s'):format(
            i,
            ok_s and tostring(sid) or 'ERR',
            skill_name,
            ok_p and tostring(pts) or 'ERR'
        ))
    end
    print('')

    -- Compute approximate ratings from experience points.
    -- DF skill experience thresholds (cumulative from level 0):
    -- Novice=500, Adequate=900, Competent=1500, Skilled=2400, Proficient=3800,
    -- Expert=5900, Professional=8900, Accomplished=13400, Expert2=19900,
    -- Master=28900, High Master=41400, Grand Master=56400,
    -- Legendary=73900, Legendary+1=..., etc.
    -- OR simpler: rating = floor(points / some_divisor)?
    -- The rating field on unit_skill is 0-20; Legendary=15.
    -- At Legendary, typical total xp ~= 73900 for many skills.
    -- Just print raw points; user/probe runner can interpret.
    print('  (Points are raw experience; Legendary threshold ~73900 for many skills)')
    print('  (Or points may be the 0-20 rating directly - check raw values above)')
end

-- Step 6: also try printall on a different sub-field name ----------
print('[5] Checking for unk_* or other unexplored fields via _field iteration:')
local ok_sk, sk = pcall(function() return sample_hf.info.skills end)
if ok_sk and sk then
    -- Try iterating pairs (only works for tables, not userdata, but try)
    local ok_iter = pcall(function()
        for k, v in pairs(sk) do
            print(('  pair: %s = %s'):format(tostring(k), tostring(v)))
        end
    end)
    if not ok_iter then
        print('  (pairs() failed on userdata - expected)')
    end
end
print('')

-- Step 7: compare to unit soul skills for the same HF (if on-map) -
print('[6] Checking if sample HF has an on-map unit with soul skills for comparison:')
local found_unit = nil
for _, u in ipairs(df.global.world.units.active) do
    local ok_hfid, hfid = pcall(function() return u.hist_figure_id end)
    if ok_hfid and hfid == sample_hf.id then
        found_unit = u
        break
    end
end
if found_unit then
    print('  Found on-map unit. Comparing soul skills vs HF skills...')
    local ok_soul, soul = pcall(function() return found_unit.status.current_soul end)
    if ok_soul and soul then
        local ok_usk, usk = pcall(function() return soul.skills end)
        if ok_usk and usk and #usk > 0 then
            print(('  Unit soul has %d skills. First 5:'):format(#usk))
            for i = 0, math.min(#usk - 1, 4) do
                local ok_s, s = pcall(function() return usk[i] end)
                if ok_s and s then
                    local ok_sn, sn = pcall(function()
                        return df.job_skill.attrs[s.id].caption
                    end)
                    print(('    [%d] id=%s (%s) rating=%s xp=%s'):format(
                        i, tostring(s.id),
                        (ok_sn and sn) and sn or '?',
                        tostring(s.rating),
                        tostring(s.experience)
                    ))
                end
            end
        end
    end
else
    print('  Sample HF is not on the active unit list (off-map). Cannot compare soul skills.')
    print('  That is fine - the parallel vector probe above is the key finding.')
end
print('')

print('=== END PROBE ===')
