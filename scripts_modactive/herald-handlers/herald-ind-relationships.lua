--@ module=true

--[====[
herald-ind-relationships
========================

Tags: dev

  Event-driven handler for pinned individual relationship events.

Fires announcements when a pinned HF forms or loses personal bonds
(marriage, romance, apprenticeship, deity worship, etc.) via world
history events.
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local pins = dfhack.reqscript('herald-pins')

-- Dedup set keyed by event.id; prevents duplicate announcements for
-- the same event when multiple pinned HFs are involved.
local announced_rels = {}

-- Helpers ---------------------------------------------------------------------

local function title_case(s)
    if not s then return '' end
    return s:lower():gsub('_', ' '):gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end)
end

-- Returns true if the settings table has relationship announcements enabled.
local function relationships_enabled(settings)
    return settings and settings.relationships
end

local function other_name(hf_id)
    return hf_id >= 0 and util.hf_name(hf_id) or 'an unknown figure'
end

-- Fires a relationship announcement if not already announced for this event.
local function fire(ev_id, msg, dprint)
    if announced_rels[ev_id] then
        dprint('ind-relationships: event %d already announced, skipping', ev_id)
        return
    end
    announced_rels[ev_id] = true
    util.announce_relationship(msg)
end

-- Event handlers by type ------------------------------------------------------

local function handle_add_hf_hf_link(ev, dprint)
    local pinned    = pins.get_pinned()
    local hf_id     = util.safe_get(ev, 'hf') or -1
    local target_id = util.safe_get(ev, 'hf_target') or -1
    local ltype     = util.safe_get(ev, 'type')
    local LT        = df.histfig_hf_link_type

    -- Check which side is pinned
    local focal_id, oid
    if pinned[hf_id] and relationships_enabled(pinned[hf_id]) then
        focal_id, oid = hf_id, target_id
    elseif pinned[target_id] and relationships_enabled(pinned[target_id]) then
        focal_id, oid = target_id, hf_id
    else
        return
    end

    local focal_is_hf = (focal_id == hf_id)
    local name  = util.hf_name(focal_id)
    local other = other_name(oid)
    local msg

    if LT and ltype then
        if ltype == LT.SPOUSE then
            msg = ('%s married %s.'):format(name, other)
        elseif ltype == LT.LOVER then
            msg = ('%s became romantically involved with %s.'):format(name, other)
        elseif ltype == LT.MASTER then
            if focal_is_hf then
                msg = ('%s became the master of %s.'):format(name, other)
            else
                msg = ('%s began an apprenticeship under %s.'):format(name, other)
            end
        elseif ltype == LT.APPRENTICE then
            if focal_is_hf then
                msg = ('%s began an apprenticeship under %s.'):format(name, other)
            else
                msg = ('%s became the master of %s.'):format(name, other)
            end
        elseif ltype == LT.DEITY then
            if focal_is_hf then
                msg = ('%s began worshipping %s.'):format(name, other)
            else
                msg = ('%s received the worship of %s.'):format(name, other)
            end
        elseif ltype == LT.PRISONER then
            if focal_is_hf then
                msg = ('%s imprisoned %s.'):format(name, other)
            else
                msg = ('%s was imprisoned by %s.'):format(name, other)
            end
        end
    end

    if not msg then
        local lname = LT and ltype and LT[ltype]
        local label = lname and title_case(lname) or 'Linked'
        msg = ('%s: %s with %s.'):format(name, label, other)
    end

    fire(ev.id, msg, dprint)
end

local function handle_remove_hf_hf_link(ev, dprint)
    local pinned    = pins.get_pinned()
    local hf_id     = util.safe_get(ev, 'hf') or -1
    local target_id = util.safe_get(ev, 'hf_target') or -1
    local ltype     = util.safe_get(ev, 'type')
    local LT        = df.histfig_hf_link_type

    local focal_id, oid
    if pinned[hf_id] and relationships_enabled(pinned[hf_id]) then
        focal_id, oid = hf_id, target_id
    elseif pinned[target_id] and relationships_enabled(pinned[target_id]) then
        focal_id, oid = target_id, hf_id
    else
        return
    end

    local focal_is_hf = (focal_id == hf_id)
    local name  = util.hf_name(focal_id)
    local other = other_name(oid)
    local msg

    if LT and ltype then
        if ltype == LT.FORMER_SPOUSE then
            msg = ('%s divorced %s.'):format(name, other)
        elseif ltype == LT.FORMER_MASTER then
            if focal_is_hf then
                msg = ('%s ceased being the master of %s.'):format(name, other)
            else
                msg = ('%s ceased being the apprentice of %s.'):format(name, other)
            end
        elseif ltype == LT.FORMER_APPRENTICE then
            if focal_is_hf then
                msg = ('%s ceased being the apprentice of %s.'):format(name, other)
            else
                msg = ('%s ceased being the master of %s.'):format(name, other)
            end
        elseif ltype == LT.DEITY then
            if focal_is_hf then
                msg = ('%s ceased worshipping %s.'):format(name, other)
            else
                msg = ('%s lost the worship of %s.'):format(name, other)
            end
        end
    end

    if not msg then
        msg = ('%s: relationship ended with %s.'):format(name, other)
    end

    fire(ev.id, msg, dprint)
end

local function handle_reputation_relationship(ev, dprint)
    local pinned = pins.get_pinned()
    local hf1 = util.safe_get(ev, 'histfig1') or util.safe_get(ev, 'hfid1') or -1
    local hf2 = util.safe_get(ev, 'histfig2') or util.safe_get(ev, 'hfid2') or -1

    local focal_id, oid
    if pinned[hf1] and relationships_enabled(pinned[hf1]) then
        focal_id, oid = hf1, hf2
    elseif pinned[hf2] and relationships_enabled(pinned[hf2]) then
        focal_id, oid = hf2, hf1
    else
        return
    end

    fire(ev.id, ('%s formed a reputation bond with %s.'):format(
        util.hf_name(focal_id), other_name(oid)), dprint)
end

local function handle_relationship_denied(ev, dprint)
    local pinned    = pins.get_pinned()
    local seeker_id = util.safe_get(ev, 'seeker_hf') or -1
    local target_id = util.safe_get(ev, 'target_hf') or -1
    local rtype     = util.safe_get(ev, 'type')

    local RNAME_MAP = {
        Apprentice = 'an apprenticeship', Master = 'a mentorship',
        Lover = 'a romantic relationship', Spouse = 'a marriage',
        Deity = 'a worship bond', Pet = 'a pet bond',
        Prisoner = 'a captivity',
    }
    local raw = rtype and df.unit_relationship_type and df.unit_relationship_type[rtype]
    local rname = (raw and RNAME_MAP[raw]) or ('a ' .. (raw or 'unknown'):lower():gsub('_', ' ') .. ' relationship')

    if pinned[seeker_id] and relationships_enabled(pinned[seeker_id]) then
        fire(ev.id, ('%s was denied %s with %s.'):format(
            util.hf_name(seeker_id), rname, other_name(target_id)), dprint)
    elseif pinned[target_id] and relationships_enabled(pinned[target_id]) then
        fire(ev.id, ('%s denied %s sought by %s.'):format(
            util.hf_name(target_id), rname, other_name(seeker_id)), dprint)
    end
end

local function handle_intrigue_relationship(ev, dprint)
    local pinned       = pins.get_pinned()
    local corruptor_id = util.safe_get(ev, 'corruptor_hf') or -1
    local target_id    = util.safe_get(ev, 'target_hf') or -1

    if pinned[corruptor_id] and relationships_enabled(pinned[corruptor_id]) then
        fire(ev.id, ('%s drew %s into an intrigue.'):format(
            util.hf_name(corruptor_id), other_name(target_id)), dprint)
    elseif pinned[target_id] and relationships_enabled(pinned[target_id]) then
        fire(ev.id, ('%s was drawn into an intrigue by %s.'):format(
            util.hf_name(target_id), other_name(corruptor_id)), dprint)
    end
end

-- Dispatch table keyed by history_event_type enum value.
local dispatch = {}

local function register_dispatch()
    local T = df.history_event_type
    local map = {
        {T.ADD_HF_HF_LINK,                      handle_add_hf_hf_link},
        {T.REMOVE_HF_HF_LINK,                   handle_remove_hf_hf_link},
        {T.HFS_FORMED_REPUTATION_RELATIONSHIP,   handle_reputation_relationship},
        {T.HF_RELATIONSHIP_DENIED,               handle_relationship_denied},
        {T.HFS_FORMED_INTRIGUE_RELATIONSHIP,     handle_intrigue_relationship},
    }
    for _, entry in ipairs(map) do
        if entry[1] then dispatch[entry[1]] = entry[2] end
    end
end

-- Contract fields -------------------------------------------------------------

local function build_event_types()
    local T = df.history_event_type
    local candidates = {
        T.ADD_HF_HF_LINK,
        T.REMOVE_HF_HF_LINK,
        T.HFS_FORMED_REPUTATION_RELATIONSHIP,
        T.HF_RELATIONSHIP_DENIED,
        T.HFS_FORMED_INTRIGUE_RELATIONSHIP,
    }
    local result = {}
    for _, et in ipairs(candidates) do
        if et then table.insert(result, et) end
    end
    return result
end

event_types = build_event_types()
polls = true

function init(dprint)
    register_dispatch()
    announced_rels = {}
    dprint('ind-relationships: handler initialised')
end

function reset()
    announced_rels = {}
end

function check_event(ev, dprint)
    local handler = dispatch[ev:getType()]
    if handler then
        handler(ev, dprint)
    end
end

function check_poll()
    announced_rels = {}
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
