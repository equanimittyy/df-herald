--@ module=true

--[====[
herald-ind-skills
=================

Tags: dev

  Poll-based handler for pinned individual skill tracking.

Fires announcements when a pinned HF reaches Legendary skill level.
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local pins = dfhack.reqscript('herald-pins')

local LEGENDARY = 15

-- DF cumulative XP thresholds per rating level.
-- Index = rating (0-based), value = minimum cumulative XP for that level.
local XP_THRESHOLDS = {
    [0]=0, 500, 1100, 1800, 2800, 4300, 6500, 9600, 14000, 20000,
    28600, 40200, 55200, 73900, 97500, 128000,  -- 15 = Legendary
}

-- Converts raw cumulative XP to a skill rating (0-20).
local function xp_to_rating(xp)
    if not xp or xp < 0 then return 0 end
    local rating = 0
    for r = #XP_THRESHOLDS, 0, -1 do
        if xp >= XP_THRESHOLDS[r] then
            rating = r
            break
        end
    end
    return rating
end

-- { [hf_id] = { [skill_id] = rating } }
-- Absent key = first observation (baseline); present = diff-ready.
local skill_snapshots = {}

-- Helpers ---------------------------------------------------------------------

local function skill_name(skill_id)
    local ok, caption = pcall(function()
        return df.job_skill.attrs[skill_id].caption
    end)
    return (ok and caption and caption ~= '') and caption or ('skill ' .. tostring(skill_id))
end

local function legendary_enabled(settings)
    return settings and settings.legendary
end

-- Reads skills from a unit's current_soul, returns { [skill_id] = rating } or nil.
local function read_unit_skills(unit)
    local ok, soul = pcall(function() return unit.status.current_soul end)
    if not ok or not soul then return nil end
    local ok2, skills = pcall(function() return soul.skills end)
    if not ok2 or not skills then return nil end
    local snap = {}
    for i = 0, #skills - 1 do
        local s = skills[i]
        if s then snap[s.id] = s.rating end
    end
    if not next(snap) then return nil end
    return snap
end

-- Reads skills from an off-map HF struct, returns { [skill_id] = rating } or nil.
-- HF skills are parallel vectors: info.skills.skills (job_skill IDs) and
-- info.skills.points (cumulative XP). Convert XP to rating via thresholds.
local function read_hf_skills(hf)
    local ok_s, skill_ids = pcall(function() return hf.info.skills.skills end)
    if not ok_s or not skill_ids or #skill_ids == 0 then return nil end
    local ok_p, points = pcall(function() return hf.info.skills.points end)
    if not ok_p or not points then return nil end
    local snap = {}
    for i = 0, #skill_ids - 1 do
        local sid = skill_ids[i]
        local xp  = points[i]
        if sid then snap[sid] = xp_to_rating(xp) end
    end
    if not next(snap) then return nil end
    return snap
end

-- Compares old and new snapshots, announces any new legendary skills.
local function diff_skills(hf_id, old_snap, new_snap, dprint)
    if not old_snap or not new_snap then return end
    for skill_id, new_rating in pairs(new_snap) do
        if new_rating >= LEGENDARY then
            local old_rating = old_snap[skill_id]
            if old_rating == nil or old_rating < LEGENDARY then
                local name = util.hf_name(hf_id)
                local sname = skill_name(skill_id)
                dprint('ind-skills: %s (hf %d) became legendary in %s (old=%s new=%s)',
                    name, hf_id, sname, tostring(old_rating), tostring(new_rating))
                util.announce_legendary(('%s has become legendary in %s!'):format(name, sname))
            end
        end
    end
end

-- Stores a snapshot for an HF; diffs on second+ observation.
local function diff_and_store(hf_id, new_snap, dprint)
    local old_snap = skill_snapshots[hf_id]
    if not old_snap then
        local total, leg = 0, 0
        for _, r in pairs(new_snap) do
            total = total + 1
            if r >= LEGENDARY then leg = leg + 1 end
        end
        dprint('ind-skills: baseline for hf %d: %d skills, %d already legendary', hf_id, total, leg)
    else
        diff_skills(hf_id, old_snap, new_snap, dprint)
    end
    skill_snapshots[hf_id] = new_snap
end

-- Poll handler ----------------------------------------------------------------

local function handle_poll(dprint)
    local pinned = pins.get_pinned()
    local seen_on_map = {}

    -- On-map units
    util.for_each_pinned_unit(pinned, function(unit, hf_id, settings)
        if not legendary_enabled(settings) then return end
        seen_on_map[hf_id] = true
        local new_snap = read_unit_skills(unit)
        if new_snap then
            diff_and_store(hf_id, new_snap, dprint)
        end
    end)

    -- Off-map pinned HFs
    for hf_id, settings in pairs(pinned) do
        if seen_on_map[hf_id] then goto next_hf end
        if not legendary_enabled(settings) then goto next_hf end

        local hf = df.historical_figure.find(hf_id)
        if not hf then goto next_hf end

        local new_snap = read_hf_skills(hf)
        if new_snap then
            diff_and_store(hf_id, new_snap, dprint)
        end

        ::next_hf::
    end

    -- Prune unpinned or legendary-disabled HFs from snapshots
    for hf_id in pairs(skill_snapshots) do
        local s = pinned[hf_id]
        if not s or not legendary_enabled(s) then
            skill_snapshots[hf_id] = nil
        end
    end
end

-- Contract fields -------------------------------------------------------------

polls = true

-- Set skill baselines immediately at map load for consistency with other handlers.
local function set_initial_baselines(dprint)
    util.for_each_pinned_unit(pins.get_pinned(), function(unit, hf_id, settings)
        if not legendary_enabled(settings) then return end
        local snap = read_unit_skills(unit)
        if snap then
            skill_snapshots[hf_id] = snap
            local total, leg = 0, 0
            for _, r in pairs(snap) do
                total = total + 1
                if r >= LEGENDARY then leg = leg + 1 end
            end
            dprint('ind-skills.init: baseline for hf %d: %d skills, %d legendary', hf_id, total, leg)
        end
    end)
end

function init(dprint)
    skill_snapshots = {}
    set_initial_baselines(dprint)
    dprint('ind-skills: handler initialised')
end

function reset()
    skill_snapshots = {}
end

function check_poll(dprint)
    handle_poll(dprint)
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
