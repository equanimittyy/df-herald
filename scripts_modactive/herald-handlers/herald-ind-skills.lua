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
local function read_hf_skills(hf)
    local ok, skills = pcall(function() return hf.info.skills.skills end)
    if not ok or not skills then return nil end
    local snap = {}
    for i = 0, #skills - 1 do
        local s = skills[i]
        if s then snap[s.id] = s.rating end
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
                util.announce_appointment(('%s has become legendary in %s!'):format(name, sname))
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
    local ok, active = pcall(function() return df.global.world.units.active end)
    if not ok or not active then return end

    local pinned = pins.get_pinned()
    local pinned_count = 0
    for _, s in pairs(pinned) do
        if legendary_enabled(s) then pinned_count = pinned_count + 1 end
    end
    dprint('ind-skills.poll: scanning %d active units, %d legendary-tracked HFs', #active, pinned_count)
    local seen_on_map = {}

    -- On-map units
    for i = 0, #active - 1 do
        local unit = active[i]
        if not unit then goto continue end
        local ok_hf, hf_id = pcall(function() return unit.hist_figure_id end)
        if not ok_hf or not hf_id or hf_id < 0 then goto continue end
        if not pinned[hf_id] or not legendary_enabled(pinned[hf_id]) then goto continue end

        seen_on_map[hf_id] = true
        local new_snap = read_unit_skills(unit)
        if new_snap then
            diff_and_store(hf_id, new_snap, dprint)
        end

        ::continue::
    end

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

function init(dprint)
    skill_snapshots = {}
    dprint('ind-skills: handler initialised')
end

function reset()
    skill_snapshots = {}
end

function check_poll(dprint)
    handle_poll(dprint)
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
