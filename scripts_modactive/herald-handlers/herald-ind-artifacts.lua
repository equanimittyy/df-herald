--@ module=true

--[====[
herald-ind-artifacts
====================

Tags: dev

  Event-driven handler for pinned individual artifact and written work events.

Fires when a pinned HF creates an artifact, claims/stores/loses one,
or composes a written work.
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local pins = dfhack.reqscript('herald-pins')

-- Helpers -------------------------------------------------------------------

local function artifacts_enabled(settings)
    return settings and settings.artifacts
end

-- Returns a display label for an artifact: translated name, material+type, or fallback.
local function get_artifact_label(art_id)
    if not art_id or art_id < 0 then return 'an artifact' end
    local ok, art = pcall(function() return df.artifact_record.find(art_id) end)
    if not ok or not art then return 'an artifact' end
    local ok2, n = pcall(function() return dfhack.translation.translateName(art.name, true) end)
    if ok2 and n and n ~= '' then return 'the artifact ' .. n end
    -- Try material + item type
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
            return 'a ' .. mat_s .. ' ' .. tostring(type_s):lower() .. ' artifact'
        elseif type_s then
            return 'a ' .. tostring(type_s):lower() .. ' artifact'
        end
    end
    return 'an artifact'
end

-- Returns title string or nil if unresolvable.
local function get_written_title(wc_id)
    if not wc_id or wc_id < 0 then return nil end
    local ok, wc = pcall(function() return df.written_content.find(wc_id) end)
    if not ok or not wc then return nil end
    local ok2, t = pcall(function() return wc.title end)
    if ok2 and t and t ~= '' then return t end
    return nil
end

-- Event handlers ------------------------------------------------------------

local function handle_artifact_created(ev, dprint)
    local pinned = pins.get_pinned()
    local hf_id = util.safe_get(ev, 'creator_hfid') or -1
    local settings = pinned[hf_id]
    if not artifacts_enabled(settings) then return end

    local art_id = util.safe_get(ev, 'artifact_id') or -1
    local site_id = util.safe_get(ev, 'site') or -1
    local label = get_artifact_label(art_id)
    local name = util.hf_name(hf_id)

    if site_id >= 0 then
        util.announce_artifact(('%s created %s in %s.'):format(name, label, util.site_name(site_id)))
    else
        util.announce_artifact(('%s created %s.'):format(name, label))
    end
end

local function handle_artifact_stored(ev, dprint)
    local pinned = pins.get_pinned()
    local hf_id = util.safe_get(ev, 'histfig') or -1
    local settings = pinned[hf_id]
    if not artifacts_enabled(settings) then return end

    local art_id = util.safe_get(ev, 'artifact_id') or -1
    local site_id = util.safe_get(ev, 'site') or -1
    local label = get_artifact_label(art_id)
    local name = util.hf_name(hf_id)

    if site_id >= 0 then
        util.announce_artifact(('%s stored %s in %s.'):format(name, label, util.site_name(site_id)))
    else
        util.announce_artifact(('%s stored %s.'):format(name, label))
    end
end

local function handle_artifact_possessed(ev, dprint)
    local pinned = pins.get_pinned()
    local hf_id = util.safe_get(ev, 'histfig') or -1
    local settings = pinned[hf_id]
    if not artifacts_enabled(settings) then return end

    local art_id = util.safe_get(ev, 'artifact_id') or -1
    local site_id = util.safe_get(ev, 'site') or -1
    local label = get_artifact_label(art_id)
    local name = util.hf_name(hf_id)

    if site_id >= 0 then
        util.announce_artifact(('%s claimed %s in %s.'):format(name, label, util.site_name(site_id)))
    else
        util.announce_artifact(('%s claimed %s.'):format(name, label))
    end
end

local function handle_artifact_claim_formed(ev, dprint)
    local pinned = pins.get_pinned()
    local hf_id = util.safe_get(ev, 'histfig') or -1
    local settings = pinned[hf_id]
    if not artifacts_enabled(settings) then return end

    local art_id = util.safe_get(ev, 'artifact_id') or -1
    local entity_id = util.safe_get(ev, 'entity') or -1
    local label = get_artifact_label(art_id)
    local name = util.hf_name(hf_id)

    if entity_id >= 0 then
        util.announce_artifact(('%s formed a claim on %s on behalf of %s.'):format(
            name, label, util.ent_name(entity_id)))
    else
        util.announce_artifact(('%s formed a claim on %s.'):format(name, label))
    end
end

local function handle_written_content_composed(ev, dprint)
    local pinned = pins.get_pinned()
    local hf_id = util.safe_get(ev, 'histfig') or -1
    local settings = pinned[hf_id]
    if not artifacts_enabled(settings) then return end

    local wc_id = util.safe_get(ev, 'wc') or util.safe_get(ev, 'wc_id') or -1
    local site_id = util.safe_get(ev, 'site') or -1
    local title = get_written_title(wc_id)
    local name = util.hf_name(hf_id)
    local work = title and ('"%s"'):format(title) or 'a written work'

    if site_id >= 0 then
        util.announce_artifact(('%s composed %s in %s.'):format(name, work, util.site_name(site_id)))
    else
        util.announce_artifact(('%s composed %s.'):format(name, work))
    end
end

-- Dispatch table keyed by history_event_type enum value.
local dispatch = {}

local function register_dispatch()
    local T = df.history_event_type
    local map = {
        {T.ARTIFACT_CREATED,            handle_artifact_created},
        {T.ARTIFACT_STORED,             handle_artifact_stored},
        {T.ARTIFACT_POSSESSED,          handle_artifact_possessed},
        {T.ARTIFACT_CLAIM_FORMED,       handle_artifact_claim_formed},
        {T.WRITTEN_CONTENT_COMPOSED,    handle_written_content_composed},
    }
    for _, entry in ipairs(map) do
        if entry[1] then dispatch[entry[1]] = entry[2] end
    end
end

-- Contract fields -----------------------------------------------------------

local function build_event_types()
    local T = df.history_event_type
    local candidates = {
        T.ARTIFACT_CREATED,
        T.ARTIFACT_STORED,
        T.ARTIFACT_POSSESSED,
        T.ARTIFACT_CLAIM_FORMED,
        T.WRITTEN_CONTENT_COMPOSED,
    }
    local result = {}
    for _, et in ipairs(candidates) do
        if et then table.insert(result, et) end
    end
    return result
end

event_types = build_event_types()

function init(dprint)
    register_dispatch()
    dprint('ind-artifacts: handler initialised')
end

function reset()
    -- no state to clear; event-driven only, no dedup needed (incremental scan)
end

function check_event(ev, dprint)
    local handler = dispatch[ev:getType()]
    if handler then
        handler(ev, dprint)
    end
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
