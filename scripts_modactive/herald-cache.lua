--@ module=true

--[====[
herald-cache
============
Tags: fort | gameplay

  Persistent event cache for the Herald mod. Caches event-to-HF mappings in
  the save file so the expensive full scan only runs once per save. Subsequent
  opens delta-process only new events.

  Required by herald-gui and herald-event-history. Do not require herald-main,
  herald-ind-death, or herald-world-leaders (avoids circular deps).

Not intended for direct use.
]====]

local json = require('json')

local PERSIST_KEY = 'herald_event_cache'
local CACHE_VERSION = 1

-- Module state -----------------------------------------------------------------

cache_ready = false   -- true once loaded/built
building    = false   -- true during build

-- Internal cache tables (nil when not loaded).
local hf_event_counts = nil   -- { [hf_id] = count }
local hf_event_ids    = nil   -- { [hf_id] = {id, ...} }
local hf_rel_counts   = nil   -- { [hf_id] = count }
-- Civ cache tables.
local civ_event_ids      = nil   -- { [civ_id] = {ev_id, ...} } position/entity events
local civ_collection_ids = nil   -- { [civ_id] = {col_id, ...} } collection IDs
local civ_event_counts   = nil   -- { [civ_id] = count } total (events + collections)
-- Watermark: tracks how far into the events array we've cached.
-- last_cached_event_idx is an array INDEX into df.global.world.history.events (0-based),
-- last_cached_event_id is the .id field of that event (used to validate the watermark
-- hasn't shifted, e.g. after a different save is loaded).
local last_cached_event_idx = -1
local last_cached_event_id  = -1
-- Relationship event watermarks (block store has different structure from regular events).
local rel_blocks_scanned    = 0
local rel_last_block_ne     = 0
-- Collection watermark.
local last_cached_collection_idx = -1

-- Lazy-loaded dependency (inside function bodies, not at module scope).
local function get_ev_hist()
    return dfhack.reqscript('herald-event-history')
end

-- Debug printer; reads herald-main.DEBUG lazily to avoid circular dep.
local function dprint(fmt, ...)
    local ok, main = pcall(dfhack.reqscript, 'herald-main')
    if not ok or not main.DEBUG then return end
    local msg = ('[Herald Cache] ' .. fmt):format(...)
    print(msg)
end

-- Persistence ------------------------------------------------------------------

function load_cache()
    dprint('load_cache: reading from persistence key "%s"', PERSIST_KEY)
    cache_ready = false
    hf_event_counts = nil
    hf_event_ids    = nil
    hf_rel_counts   = nil
    civ_event_ids      = nil
    civ_collection_ids = nil
    civ_event_counts   = nil
    last_cached_event_idx = -1
    last_cached_event_id  = -1
    rel_blocks_scanned    = 0
    rel_last_block_ne     = 0
    last_cached_collection_idx = -1

    local ok, site_data = pcall(dfhack.persistent.getSiteData, PERSIST_KEY)
    if not ok or type(site_data) ~= 'table' then
        dprint('load_cache: no saved data found, cache empty')
        return
    end
    if site_data.version ~= CACHE_VERSION then
        dprint('load_cache: version mismatch (saved=%s, expected=%d), discarding',
            tostring(site_data.version), CACHE_VERSION)
        return
    end

    -- Validate watermark: the event at the stored index must have the stored id.
    local stored_idx = tonumber(site_data.last_cached_event_idx) or -1
    local stored_id  = tonumber(site_data.last_cached_event_id)  or -1
    if stored_idx >= 0 then
        local events = df.global.world.history.events
        if stored_idx >= #events then
            dprint('load_cache: watermark idx %d >= event count %d, discarding',
                stored_idx, #events)
            return
        end
        if events[stored_idx].id ~= stored_id then
            dprint('load_cache: watermark id mismatch (stored=%d, actual=%d), discarding',
                stored_id, events[stored_idx].id)
            return
        end
    end

    -- Restore string-keyed JSON tables to integer-keyed Lua tables.
    local function restore_counts(tbl)
        if type(tbl) ~= 'table' then return {} end
        local out = {}
        for k, v in pairs(tbl) do
            local nk = tonumber(k)
            if nk and type(v) == 'number' then out[nk] = v end
        end
        return out
    end
    local function restore_id_lists(tbl)
        if type(tbl) ~= 'table' then return {} end
        local out = {}
        for k, v in pairs(tbl) do
            local nk = tonumber(k)
            if nk and type(v) == 'table' then out[nk] = v end
        end
        return out
    end

    hf_event_counts = restore_counts(site_data.hf_event_counts)
    hf_event_ids    = restore_id_lists(site_data.hf_event_ids)
    hf_rel_counts   = restore_counts(site_data.hf_rel_counts)
    civ_event_ids      = restore_id_lists(site_data.civ_event_ids)
    civ_collection_ids = restore_id_lists(site_data.civ_collection_ids)
    civ_event_counts   = restore_counts(site_data.civ_event_counts)
    last_cached_event_idx = stored_idx
    last_cached_event_id  = stored_id
    rel_blocks_scanned    = tonumber(site_data.rel_blocks_scanned) or 0
    rel_last_block_ne     = tonumber(site_data.rel_last_block_ne)  or 0
    last_cached_collection_idx = tonumber(site_data.last_cached_collection_idx) or -1
    cache_ready = true

    -- Count unique HFs/civs in cache for the summary.
    local hf_count = 0
    for _ in pairs(hf_event_counts) do hf_count = hf_count + 1 end
    local civ_count = 0
    for _ in pairs(civ_event_counts) do civ_count = civ_count + 1 end
    dprint('load_cache: restored - watermark idx=%d id=%d, %d HFs, %d civs, rel_blocks=%d, col_idx=%d',
        stored_idx, stored_id, hf_count, civ_count, rel_blocks_scanned, last_cached_collection_idx)
end

function save_cache()
    if not hf_event_counts then
        dprint('save_cache: nothing to save (no data)')
        return
    end
    dprint('save_cache: writing to persistence, watermark idx=%d id=%d',
        last_cached_event_idx, last_cached_event_id)

    -- JSON requires string keys; Lua integer keys (hf_id -> count) would be lost
    -- during encode/decode. Convert to string keys for storage, restore on load.
    local function stringify_keys(tbl)
        local out = {}
        for k, v in pairs(tbl) do out[tostring(k)] = v end
        return out
    end

    local data = {
        version               = CACHE_VERSION,
        last_cached_event_idx = last_cached_event_idx,
        last_cached_event_id  = last_cached_event_id,
        rel_blocks_scanned    = rel_blocks_scanned,
        rel_last_block_ne     = rel_last_block_ne,
        last_cached_collection_idx = last_cached_collection_idx,
        hf_event_counts       = stringify_keys(hf_event_counts),
        hf_event_ids          = stringify_keys(hf_event_ids),
        hf_rel_counts         = stringify_keys(hf_rel_counts),
        civ_event_ids         = stringify_keys(civ_event_ids or {}),
        civ_collection_ids    = stringify_keys(civ_collection_ids or {}),
        civ_event_counts      = stringify_keys(civ_event_counts or {}),
    }
    pcall(dfhack.persistent.saveSiteData, PERSIST_KEY, data)
end

function invalidate_cache()
    dprint('invalidate_cache: clearing all cached data')
    cache_ready = false
    hf_event_counts = nil
    hf_event_ids    = nil
    hf_rel_counts   = nil
    civ_event_ids      = nil
    civ_collection_ids = nil
    civ_event_counts   = nil
    last_cached_event_idx = -1
    last_cached_event_id  = -1
    rel_blocks_scanned    = 0
    rel_last_block_ne     = 0
    last_cached_collection_idx = -1
    pcall(dfhack.persistent.saveSiteData, PERSIST_KEY, {})
end

function needs_build()
    return not cache_ready
end

-- Core scan logic --------------------------------------------------------------

-- Module-scope enum lookups (computed once at load time).
local BATTLE_TYPES = {}
for _, name in ipairs({'HF_SIMPLE_BATTLE_EVENT', 'HIST_FIGURE_SIMPLE_BATTLE_EVENT'}) do
    local v = df.history_event_type[name]
    if v ~= nil then BATTLE_TYPES[v] = true end
end
local COMP_TYPE = df.history_event_type['COMPETITION']
local BODY_ABUSED_TYPE = df.history_event_type['BODY_ABUSED']

-- Civ-relevant event types.
local ADD_HF_ENTITY_LINK_TYPE    = df.history_event_type['ADD_HF_ENTITY_LINK']
local REMOVE_HF_ENTITY_LINK_TYPE = df.history_event_type['REMOVE_HF_ENTITY_LINK']
local ENTITY_CREATED_TYPE        = df.history_event_type['ENTITY_CREATED']
local LT_POSITION = df.histfig_entity_link_type and df.histfig_entity_link_type.POSITION

-- Peace/agreement event types (civ-level diplomacy).
-- Actual DF names: WAR_PEACE_*, TOPICAGREEMENT_* (probe-confirmed).
local PEACE_TYPES = {}
for _, name in ipairs({'WAR_PEACE_ACCEPTED', 'WAR_PEACE_REJECTED',
                       'TOPICAGREEMENT_CONCLUDED', 'TOPICAGREEMENT_MADE',
                       'TOPICAGREEMENT_REJECTED'}) do
    local v = df.history_event_type[name]
    if v ~= nil then PEACE_TYPES[v] = true end
end

-- Processes a single event: updates hf_event_counts, hf_event_ids,
-- and civ_event_ids/civ_event_counts for position/entity events.
-- Returns nothing; mutates tables in place.
local function process_event(ev, ev_hist)
    if not ev_hist.event_will_be_shown(ev) then return end

    local ev_type = ev:getType()
    local ev_id   = ev.id
    local seen    = {}

    -- Scalar HF fields (type-dispatched for speed).
    local fields = ev_hist.TYPE_HF_FIELDS[ev_type] or ev_hist.HF_FIELDS
    for _, field in ipairs(fields) do
        local val = ev_hist.safe_get(ev, field)
        if type(val) == 'number' and val >= 0 and not seen[val] then
            seen[val] = true
            hf_event_counts[val] = (hf_event_counts[val] or 0) + 1
            if not hf_event_ids[val] then hf_event_ids[val] = {} end
            table.insert(hf_event_ids[val], ev_id)
        end
    end

    -- Vector fields for battle events.
    if BATTLE_TYPES[ev_type] then
        for _, vec_field in ipairs({'group1', 'group2'}) do
            local ok, vec = pcall(function() return ev[vec_field] end)
            if ok and vec then
                local ok2, n = pcall(function() return #vec end)
                if ok2 then
                    for i = 0, n - 1 do
                        local ok3, v = pcall(function() return vec[i] end)
                        if ok3 and type(v) == 'number' and v >= 0 and not seen[v] then
                            seen[v] = true
                            hf_event_counts[v] = (hf_event_counts[v] or 0) + 1
                            if not hf_event_ids[v] then hf_event_ids[v] = {} end
                            table.insert(hf_event_ids[v], ev_id)
                        end
                    end
                end
            end
        end
    end

    -- Vector fields for competition events.
    if COMP_TYPE and ev_type == COMP_TYPE then
        for _, vec_field in ipairs({'competitor_hf', 'winner_hf'}) do
            local ok, vec = pcall(function() return ev[vec_field] end)
            if ok and vec then
                local ok2, n = pcall(function() return #vec end)
                if ok2 then
                    for i = 0, n - 1 do
                        local ok3, v = pcall(function() return vec[i] end)
                        if ok3 and type(v) == 'number' and v >= 0 and not seen[v] then
                            seen[v] = true
                            hf_event_counts[v] = (hf_event_counts[v] or 0) + 1
                            if not hf_event_ids[v] then hf_event_ids[v] = {} end
                            table.insert(hf_event_ids[v], ev_id)
                        end
                    end
                end
            end
        end
    end

    -- Vector field for body abuse events (victim HF IDs in 'bodies').
    if BODY_ABUSED_TYPE and ev_type == BODY_ABUSED_TYPE then
        local ok, vec = pcall(function() return ev.bodies end)
        if ok and vec then
            local ok2, n = pcall(function() return #vec end)
            if ok2 then
                for i = 0, n - 1 do
                    local ok3, v = pcall(function() return vec[i] end)
                    if ok3 and type(v) == 'number' and v >= 0 and not seen[v] then
                        seen[v] = true
                        hf_event_counts[v] = (hf_event_counts[v] or 0) + 1
                        if not hf_event_ids[v] then hf_event_ids[v] = {} end
                        table.insert(hf_event_ids[v], ev_id)
                    end
                end
            end
        end
    end

    -- Civ position events: ADD/REMOVE_HF_ENTITY_LINK with POSITION link_type.
    if (ADD_HF_ENTITY_LINK_TYPE and ev_type == ADD_HF_ENTITY_LINK_TYPE)
        or (REMOVE_HF_ENTITY_LINK_TYPE and ev_type == REMOVE_HF_ENTITY_LINK_TYPE) then
        local civ_id = ev_hist.safe_get(ev, 'civ')
        local ltype  = ev_hist.safe_get(ev, 'link_type')
        if civ_id and civ_id >= 0 and LT_POSITION and ltype == LT_POSITION then
            if not civ_event_ids[civ_id] then civ_event_ids[civ_id] = {} end
            table.insert(civ_event_ids[civ_id], ev_id)
            civ_event_counts[civ_id] = (civ_event_counts[civ_id] or 0) + 1
        end
    end

    -- Entity creation events.
    if ENTITY_CREATED_TYPE and ev_type == ENTITY_CREATED_TYPE then
        local ent_id = ev_hist.safe_get(ev, 'entity')
        if ent_id and ent_id >= 0 then
            if not civ_event_ids[ent_id] then civ_event_ids[ent_id] = {} end
            table.insert(civ_event_ids[ent_id], ev_id)
            civ_event_counts[ent_id] = (civ_event_counts[ent_id] or 0) + 1
        end
    end

    -- Peace/agreement events: cache for both source and destination civs.
    if PEACE_TYPES[ev_type] then
        for _, field in ipairs({'source', 'destination'}) do
            local eid = ev_hist.safe_get(ev, field)
            if eid and eid >= 0 then
                if not civ_event_ids[eid] then civ_event_ids[eid] = {} end
                table.insert(civ_event_ids[eid], ev_id)
                civ_event_counts[eid] = (civ_event_counts[eid] or 0) + 1
            end
        end
    end
end

-- Scans relationship event blocks from the given watermark.
local function scan_rel_events(from_block, from_ne)
    local ok_re, rel_evs = pcall(function()
        return df.global.world.history.relationship_events
    end)
    if not ok_re or not rel_evs then return end

    local n_blocks = #rel_evs
    for i = from_block, n_blocks - 1 do
        local ok_b, block = pcall(function() return rel_evs[i] end)
        if not ok_b then break end
        local ok_ne, ne = pcall(function() return block.next_element end)
        if not ok_ne then break end

        local start_k = (i == from_block) and from_ne or 0
        for k = start_k, ne - 1 do
            local ok, src, tgt = pcall(function()
                return block.source_hf[k], block.target_hf[k]
            end)
            if not ok then break end
            if type(src) == 'number' and src >= 0 then
                hf_rel_counts[src] = (hf_rel_counts[src] or 0) + 1
            end
            if type(tgt) == 'number' and tgt >= 0 then
                hf_rel_counts[tgt] = (hf_rel_counts[tgt] or 0) + 1
            end
        end

        rel_blocks_scanned = i
        rel_last_block_ne  = ne
    end
    -- If no blocks exist yet, keep watermarks at initial values.
    if n_blocks > 0 then
        rel_blocks_scanned = n_blocks - 1
        local ok_b, block = pcall(function() return rel_evs[n_blocks - 1] end)
        if ok_b then
            local ok_ne, ne = pcall(function() return block.next_element end)
            if ok_ne then rel_last_block_ne = ne end
        end
    end
end

-- Scans event collections from the given watermark for civ associations.
-- Uses civ_matches_collection from herald-event-history to check each collection
-- against every civ it involves, storing collection IDs per civ.
local function scan_collections(from_idx, ev_hist)
    local ok_all, all = pcall(function()
        return df.global.world.history.event_collections.all
    end)
    if not ok_all or not all then return end

    local n = #all
    dprint('scan_collections: scanning from idx %d, total collections=%d', from_idx + 1, n)

    -- Build civ_set: all Civilization entity IDs.
    local civ_set = {}
    for _, entity in ipairs(df.global.world.entities.all) do
        if entity.type == df.historical_entity_type.Civilization then
            civ_set[entity.id] = true
        end
    end

    for ci = from_idx + 1, n - 1 do
        local col = all[ci]
        for civ_id in pairs(civ_set) do
            if ev_hist.civ_matches_collection(col, civ_id) then
                local col_id = col.id
                if not civ_collection_ids[civ_id] then civ_collection_ids[civ_id] = {} end
                table.insert(civ_collection_ids[civ_id], col_id)
                civ_event_counts[civ_id] = (civ_event_counts[civ_id] or 0) + 1
            end
        end
    end

    if n > 0 then
        last_cached_collection_idx = n - 1
    end
end

-- Full build: scans all events from scratch.
function build_full(on_done)
    dprint('build_full: starting full cache build')
    building = true
    cache_ready = false
    hf_event_counts = {}
    hf_event_ids    = {}
    hf_rel_counts   = {}
    civ_event_ids      = {}
    civ_collection_ids = {}
    civ_event_counts   = {}
    last_cached_event_idx = -1
    last_cached_event_id  = -1
    rel_blocks_scanned    = 0
    rel_last_block_ne     = 0
    last_cached_collection_idx = -1

    local ev_hist = get_ev_hist()
    local events  = df.global.world.history.events
    local n       = #events
    dprint('build_full: scanning %d event(s)', n)

    for i = 0, n - 1 do
        process_event(events[i], ev_hist)
    end

    if n > 0 then
        last_cached_event_idx = n - 1
        last_cached_event_id  = events[n - 1].id
    end

    dprint('build_full: scanning relationship event blocks')
    scan_rel_events(0, 0)

    dprint('build_full: scanning event collections for civ associations')
    scan_collections(-1, ev_hist)

    cache_ready = true
    building    = false
    save_cache()

    local hf_count = 0
    for _ in pairs(hf_event_counts) do hf_count = hf_count + 1 end
    local civ_count = 0
    for _ in pairs(civ_event_counts) do civ_count = civ_count + 1 end
    dprint('build_full: complete - %d event(s), %d HFs, %d civs, watermark idx=%d id=%d',
        n, hf_count, civ_count, last_cached_event_idx, last_cached_event_id)

    if on_done then on_done() end
    return n
end

-- Delta build: processes only events added since last watermark.
-- Returns the number of new events processed.
function build_delta()
    if not cache_ready then
        dprint('build_delta: cache not ready, skipping')
        return 0
    end

    local ev_hist = get_ev_hist()
    local events  = df.global.world.history.events
    local n       = #events
    local start_idx = last_cached_event_idx + 1
    local count = 0

    dprint('build_delta: checking from idx %d, total events=%d', start_idx, n)

    -- Validate watermark.
    if last_cached_event_idx >= 0 and last_cached_event_idx < n then
        if events[last_cached_event_idx].id ~= last_cached_event_id then
            dprint('build_delta: watermark id mismatch (expected=%d, actual=%d), invalidating',
                last_cached_event_id, events[last_cached_event_idx].id)
            invalidate_cache()
            return 0
        end
    end

    for i = start_idx, n - 1 do
        process_event(events[i], ev_hist)
        count = count + 1
    end

    if n > 0 then
        last_cached_event_idx = n - 1
        last_cached_event_id  = events[n - 1].id
    end

    -- Delta scan relationship events from last watermark.
    scan_rel_events(rel_blocks_scanned, rel_last_block_ne)

    -- Delta scan collections from last watermark.
    -- Ensure civ tables exist (may be nil if loaded from an older cache version).
    if not civ_event_ids then civ_event_ids = {} end
    if not civ_collection_ids then civ_collection_ids = {} end
    if not civ_event_counts then civ_event_counts = {} end
    scan_collections(last_cached_collection_idx, ev_hist)

    if count > 0 then
        dprint('build_delta: processed %d new event(s), watermark now idx=%d id=%d',
            count, last_cached_event_idx, last_cached_event_id)
        save_cache()
    else
        dprint('build_delta: no new events')
    end
    return count
end

-- Accessors --------------------------------------------------------------------

function get_all_hf_event_counts()
    if not cache_ready then return {} end
    -- Merge event counts + relationship counts for total.
    local merged = {}
    for hf_id, c in pairs(hf_event_counts) do
        merged[hf_id] = c + (hf_rel_counts[hf_id] or 0)
    end
    -- Include HFs that only appear in relationship events.
    for hf_id, c in pairs(hf_rel_counts) do
        if not merged[hf_id] then merged[hf_id] = c end
    end
    return merged
end

function get_hf_event_ids(hf_id)
    if not cache_ready then
        dprint('get_hf_event_ids: cache not ready, returning nil for hf %d', hf_id)
        return nil
    end
    local ids = hf_event_ids[hf_id]
    dprint('get_hf_event_ids: hf %d - %s',
        hf_id, ids and (tostring(#ids) .. ' event(s) cached') or 'no events found')
    return ids
end

function get_hf_total_count(hf_id)
    if not cache_ready then return 0 end
    return (hf_event_counts[hf_id] or 0) + (hf_rel_counts[hf_id] or 0)
end

-- Civ accessors ---------------------------------------------------------------

function get_civ_event_ids(civ_id)
    if not cache_ready or not civ_event_ids then return nil end
    return civ_event_ids[civ_id]
end

function get_civ_collection_ids(civ_id)
    if not cache_ready or not civ_collection_ids then return nil end
    return civ_collection_ids[civ_id]
end

function get_civ_total_count(civ_id)
    if not cache_ready or not civ_event_counts then return 0 end
    return civ_event_counts[civ_id] or 0
end

-- Cleanup ----------------------------------------------------------------------

function reset()
    dprint('reset: clearing all cache state')
    cache_ready = false
    building    = false
    hf_event_counts = nil
    hf_event_ids    = nil
    hf_rel_counts   = nil
    civ_event_ids      = nil
    civ_collection_ids = nil
    civ_event_counts   = nil
    last_cached_event_idx = -1
    last_cached_event_id  = -1
    rel_blocks_scanned    = 0
    rel_last_block_ne     = 0
    last_cached_collection_idx = -1
end
