--@ module=true

--[====[
herald-event-history
====================
Tags: fort | gameplay

  Event history subsystem for the Herald mod. Provides world-history event collection, description formatting, and the Event History 
  popup screen for historical figures.

  Opened via Ctrl-E from the Pinned or Historical Figures tabs in herald-gui.

Not intended for direct use.
]====]

local gui     = require('gui')
local widgets = require('gui.widgets')
local util    = dfhack.reqscript('herald-util')

local event_history_view = nil  -- prevents double-open

-- HF reference field names checked when counting / finding events per HF.
-- Field names verified against df-structures/df.history-events.xml:
--   hfid              = CHANGE_HF_STATE, CHANGE_HF_JOB
--   histfig           = ADD/REMOVE_HF_ENTITY_LINK, ADD_HF_SITE_LINK
--   hf / hf_target    = ADD/REMOVE_HF_HF_LINK
--   doer / target     = HF_DOES_INTERACTION
--   victim_hf, slayer_hf = HIST_FIGURE_DIED
--   snatcher / target = HIST_FIGURE_ABDUCTED
--   attacker_hf       = HF_ATTACKED_SITE, HF_DESTROYED_SITE (df-struct name='attacker_hf')
--   attacker_general_hf, defender_general_hf = WAR_FIELD_BATTLE, WAR_ATTACKED_SITE
--   histfig1, histfig2 / hfid1, hfid2 = HFS_FORMED_REPUTATION_RELATIONSHIP
--   corruptor_hf, target_hf = HFS_FORMED_INTRIGUE_RELATIONSHIP
--   seeker_hf, target_hf = HF_RELATIONSHIP_DENIED
--   changee, changer  = CHANGE_CREATURE_TYPE
--   woundee_hfid, wounder_hfid = HIST_FIGURE_WOUNDED
--   builder_hf        = CREATED_SITE, CREATED_STRUCTURE (df-struct name='builder_hf')
--   creator_hfid      = ARTIFACT_CREATED (df-struct name='creator_hfid')
--   woundee / wounder = HF_WOUNDED (df-struct name='woundee', name='wounder')
--   maker             = MASTERPIECE_CREATED_*
-- Others (builder, figure, etc.) kept for unmapped types.
-- Note: competitor_hf / winner_hf (COMPETITION) are vectors handled separately.
HF_FIELDS = {
    'victim_hf', 'slayer_hf',
    'hf', 'hf_target', 'hf_1', 'hf_2',
    'hfid',
    'histfig', 'histfig1', 'histfig2',
    'hfid1', 'hfid2',  -- alternate names for reputation relationship fields
    'seeker_hf', 'target_hf',  -- HF_RELATIONSHIP_DENIED + HFS_FORMED_INTRIGUE_RELATIONSHIP
    'doer', 'target',
    'snatcher',
    'attacker_hf',
    'attacker_general_hf', 'defender_general_hf',
    'corruptor_hf',
    'changee', 'changer',
    'woundee', 'wounder',
    'builder_hf',
    'creator_hfid',
    'maker', 'builder', 'figure', 'member', 'initiator_hf', 'mover_hf', 'moved_hf',
}

-- DFHack's __index raises an error (not nil) when accessing a field that doesn't
-- exist on a typed DF struct. Event subtypes have different fields, so direct
-- access like ev.victim_hf will crash on non-DIED events. Use safe_get for any
-- field that may not exist on the event's concrete subtype.
function safe_get(obj, field)
    local ok, val = pcall(function() return obj[field] end)
    return ok and val or nil
end

-- Name / text helpers ---------------------------------------------------------
-- Returns the translated name of an HF, capitalised. Returns nil if unnamed.
local function hf_name_by_id(hf_id)
    if not hf_id or hf_id < 0 then return nil end
    local hf = df.historical_figure.find(hf_id)
    if not hf then return nil end
    local n = dfhack.translation.translateName(hf.name, true)
    if n == '' then return nil end
    return n:sub(1,1):upper() .. n:sub(2)
end

local function ent_name_by_id(entity_id)
    if not entity_id or entity_id < 0 then return nil end
    local ent = df.historical_entity.find(entity_id)
    if not ent then return nil end
    local n = dfhack.translation.translateName(ent.name, true)
    return n ~= '' and n or nil
end

-- Like ent_name_by_id but resolves SiteGovernments to their parent Civilisation.
-- skip_civ_id: exclude this civ from resolution (avoids "conquered X from itself").
local function civ_name_by_id(entity_id, skip_civ_id)
    if not entity_id or entity_id < 0 then return nil end
    local ent = df.historical_entity.find(entity_id)
    if not ent then return nil end
    -- If already a Civilization, return its name directly.
    local ok_t, etype = pcall(function() return ent.type end)
    if ok_t and etype == df.historical_entity_type.Civilization then
        local n = dfhack.translation.translateName(ent.name, true)
        return n ~= '' and n or nil
    end
    -- SiteGovernment: find parent civ via members' links, skipping skip_civ_id.
    if ok_t and etype == df.historical_entity_type.SiteGovernment then
        -- Check an HF's entity links for a parent Civilization (not skip_civ_id).
        local function find_parent_civ(hf)
            if not hf then return nil end
            for _, link in ipairs(hf.entity_links) do
                local lt = link:getType()
                if lt == df.histfig_entity_link_type.MEMBER
                    or lt == df.histfig_entity_link_type.FORMER_MEMBER then
                    local parent = df.historical_entity.find(link.entity_id)
                    if parent and parent.type == df.historical_entity_type.Civilization
                        and link.entity_id ~= skip_civ_id then
                        local n = dfhack.translation.translateName(parent.name, true)
                        if n ~= '' then return n end
                    end
                end
            end
            return nil
        end
        -- Tier 1: position holders.
        local ok_a, asgns = pcall(function() return ent.positions.assignments end)
        if ok_a and asgns then
            for i = 0, #asgns - 1 do
                local hf_id = safe_get(asgns[i], 'histfig2')
                if hf_id and hf_id >= 0 then
                    local n = find_parent_civ(df.historical_figure.find(hf_id))
                    if n then return n end
                end
            end
        end
        -- Tier 2: entity members.
        local ok_h, hfids = pcall(function() return ent.histfig_ids end)
        if ok_h and hfids then
            local ok_n, cnt = pcall(function() return #hfids end)
            if ok_n then
                for i = 0, cnt - 1 do
                    local n = find_parent_civ(df.historical_figure.find(hfids[i]))
                    if n then return n end
                end
            end
        end
    end
    -- Fallback: return the entity's own name.
    local n = dfhack.translation.translateName(ent.name, true)
    return n ~= '' and n or nil
end

local function site_name_by_id(site_id)
    if not site_id or site_id < 0 then return nil end
    local ok, site = pcall(function() return df.world_site.find(site_id) end)
    if not ok or not site then return nil end
    local n = dfhack.translation.translateName(site.name, true)
    return n ~= '' and n or nil
end

-- Returns "a <s>" or "an <s>" depending on the first letter of s.
local function article(s)
    if not s then return '' end
    return (s:match('^[AaEeIiOoUu]') and 'an ' or 'a ') .. s
end

local function creature_name(race_id)
    if not race_id or race_id < 0 then return nil end
    local ok, raw = pcall(function() return df.creature_raw.find(race_id) end)
    if not ok or not raw then return nil end
    local ok2, n = pcall(function() return raw.name[0] end)
    if not ok2 or not n or n == '' then return nil end
    return n:sub(1,1):upper() .. n:sub(2):lower()
end

-- Look up a position name from an entity_id + position_id, respecting HF sex.
-- Delegates to util.get_pos_name after resolving the entity object.
local function pos_name_for(entity_id, position_id, hf_sex)
    if not entity_id or entity_id < 0 then return nil end
    if not position_id or position_id < 0 then return nil end
    local entity = df.historical_entity.find(entity_id)
    if not entity then return nil end
    return util.get_pos_name(entity, position_id, hf_sex)
end

-- Resolve an artifact ID to its translated name and item description.
-- Returns (name_or_nil, item_desc_or_nil).
-- item_desc is e.g. "copper sword", "porcelain slab" (material + type, lowercase).
local function artifact_name_by_id(art_id)
    if not art_id or art_id < 0 then return nil, nil end
    local ok, art = pcall(function() return df.artifact_record.find(art_id) end)
    if not ok or not art then return nil, nil end
    local ok2, n = pcall(function() return dfhack.translation.translateName(art.name, true) end)
    local name = (ok2 and n and n ~= '') and n or nil
    -- Resolve item type + material from art.item.
    local item_desc
    local ok3, item = pcall(function() return art.item end)
    if ok3 and item then
        local ok4, itype = pcall(function() return item:getType() end)
        local type_s = ok4 and itype and df.item_type and df.item_type[itype]
        local mat_s
        local ok5, mt = pcall(function() return item:getActualMaterial() end)
        local ok6, mi = pcall(function() return item:getActualMaterialIndex() end)
        if ok5 and ok6 and mt >= 0 then
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
    return name, item_desc
end

-- Resolve a structure within a site to its translated building name, or nil.
local function building_name_at_site(site_id, structure_id)
    if not site_id or site_id < 0 or not structure_id or structure_id < 0 then return nil end
    local site = df.world_site.find(site_id)
    if not site then return nil end
    local ok, buildings = pcall(function() return site.buildings end)
    if not ok or not buildings then return nil end
    for i = 0, #buildings - 1 do
        local b = buildings[i]
        if b.id == structure_id then
            local ok2, n = pcall(function() return dfhack.translation.translateName(b.name, true) end)
            if ok2 and n and n ~= '' then return n end
            return nil
        end
    end
    return nil
end

-- Convert an ALL_CAPS_ENUM_NAME to "All Caps Enum Name".
local function title_case(s)
    return (s:lower():gsub('_', ' '):gsub('(%a)([%w]*)', function(a, b)
        return a:upper() .. b
    end))
end

-- Strip noisy DF prefixes from a raw enum name and produce lowercase words.
-- e.g. "HIST_FIGURE_ABDUCTED" -> "abducted"
--      "CHANGE_HF_STATE"      -> "changed state"
--      "HF_LEARNS_SECRET"     -> "learns secret"
--      "ADD_HF_SITE_LINK"     -> "gained site link"
local function clean_enum_name(s)
    if type(s) ~= 'string' then return tostring(s) end
    s = s:gsub('^HIST_FIGURE_', '')
         :gsub('^CHANGE_HF_',   'changed ')
         :gsub('^ADD_HF_',      'gained ')
         :gsub('^REMOVE_HF_',   'lost ')
         :gsub('^HF_',          '')
    return s:lower():gsub('_', ' ')
end

-- Per-type describers ---------------------------------------------------------
-- EVENT_DESCRIBE: { [event_type_int] = fn(ev, focal_hf_id) -> string }
-- focal_hf_id makes descriptions relative to one figure ("Slew X" vs "Slain by Y").
-- Each fn is called inside pcall; return nil to suppress the event from the list.
-- Adapted from LegendsViewer-Next by Kromtec et al. (MIT License)
-- https://github.com/Kromtec/LegendsViewer-Next
local EVENT_DESCRIBE = {}
do
    local function add(type_name, fn)
        local v = df.history_event_type[type_name]
        if v ~= nil then EVENT_DESCRIBE[v] = fn end
    end

    -- Death causes that can logically take a "by [slayer]" suffix.
    local SLAYABLE_CAUSES = {
        STRUCK=true, MURDERED=true, DRAGONFIRE=true, SHOT=true,
        BURNED=true, FIRE=true, TRAP=true, CAVEIN=true, CRUSHED=true,
        CRUSHEDBYADRAWBRIDGE=true, SLAUGHTERED=true,
    }

    local DEATH_CAUSE_TEXT = {
        OLD_AGE              = 'died of old age',
        STRUCK               = 'was struck down',
        MURDERED             = 'was murdered',
        DRAGONFIRE           = 'was burned in dragon fire',
        SHOT                 = 'was shot and killed',
        BURNED               = 'was burned to death',
        FIRE                 = 'was burned to death',
        THIRST               = 'died of thirst',
        SUFFOCATED           = 'suffocated',
        AIR                  = 'suffocated',
        BLED                 = 'bled to death',
        BLOOD                = 'bled to death',
        COLD                 = 'froze to death',
        DROWNED              = 'drowned',
        DROWN                = 'drowned',
        INFECTION            = 'died of infection',
        TRAP                 = 'was killed by a trap',
        CAVEIN               = 'was crushed in a cave-in',
        CRUSHED              = 'was crushed in a cave-in',
        CRUSHEDBYADRAWBRIDGE = 'was crushed by a drawbridge',
        SLAUGHTERED          = 'was slaughtered',
    }

    add('HIST_FIGURE_DIED', function(ev, focal)
        local victim_id  = safe_get(ev, 'victim_hf')
        local slayer_id  = safe_get(ev, 'slayer_hf')
        local cause_int  = safe_get(ev, 'death_cause')
        local site_n     = site_name_by_id(safe_get(ev, 'site'))
        local site_sfx   = site_n and (' in ' .. site_n) or ''
        local cause_name = cause_int ~= nil and df.death_cause and df.death_cause[cause_int]
        local cause_text = cause_name and DEATH_CAUSE_TEXT[cause_name]
        local slayable   = cause_name and SLAYABLE_CAUSES[cause_name]
        local has_slayer = slayer_id and slayer_id >= 0
        if focal == victim_id then
            if cause_text then
                if slayable and has_slayer then
                    return cause_text .. ' by ' ..
                        (hf_name_by_id(slayer_id) or 'unknown') .. site_sfx
                end
                return cause_text .. site_sfx
            end
            if has_slayer then
                return 'Slain by ' .. (hf_name_by_id(slayer_id) or 'unknown') .. site_sfx
            end
            return 'Died' .. site_sfx
        elseif focal == slayer_id then
            return 'Slew ' .. (hf_name_by_id(victim_id) or 'someone') .. site_sfx
        else
            local v = hf_name_by_id(victim_id) or 'someone'
            if cause_text then
                if slayable and has_slayer then
                    return v .. ' ' .. cause_text .. ' by ' ..
                        (hf_name_by_id(slayer_id) or 'unknown') .. site_sfx
                end
                return v .. ' ' .. cause_text .. site_sfx
            end
            if has_slayer then
                return v .. ' slain by ' .. (hf_name_by_id(slayer_id) or 'unknown') .. site_sfx
            end
            return v .. ' died' .. site_sfx
        end
    end)

    add('ADD_HF_ENTITY_LINK', function(ev, focal)
        local hf_id  = safe_get(ev, 'histfig')
        local civ_id = safe_get(ev, 'civ')
        local ltype  = safe_get(ev, 'link_type')
        local pos_id = safe_get(ev, 'position_id')
        local ent_n  = ent_name_by_id(civ_id) or 'an entity'
        local hf_n   = hf_name_by_id(hf_id) or 'someone'
        local LT     = df.histfig_entity_link_type
        -- Civ-focal perspective: name the HF who gained the link.
        local civ_focal = (focal == civ_id)
        if ltype == LT.POSITION then
            local hf    = hf_id and df.historical_figure.find(hf_id)
            local pos_n = pos_name_for(civ_id, pos_id, hf and hf.sex or -1)
            if pos_n then
                if civ_focal then return hf_n .. ' became ' .. pos_n end
                return 'Became ' .. pos_n .. ' of ' .. ent_n
            end
        elseif ltype == LT.PRISONER then
            if civ_focal then return hf_n .. ' was imprisoned' end
            return 'Was imprisoned by ' .. ent_n
        elseif ltype == LT.SLAVE then
            if civ_focal then return hf_n .. ' was enslaved' end
            return 'Was enslaved by ' .. ent_n
        elseif ltype == LT.ENEMY then
            if civ_focal then return hf_n .. ' became an enemy' end
            return 'Became an enemy of ' .. ent_n
        elseif ltype == LT.MEMBER or ltype == LT.SQUAD then
            if civ_focal then return hf_n .. ' joined' end
            return 'Became a member of ' .. ent_n
        elseif ltype == LT.FORMER_MEMBER then
            if civ_focal then return hf_n .. ' became a former member' end
            return 'Became a former member of ' .. ent_n
        end
        local lname = ltype and LT[ltype]
        if civ_focal then return hf_n .. ' joined' .. (lname and ' (' .. title_case(lname) .. ')' or '') end
        return 'Joined ' .. ent_n .. (lname and ' (' .. title_case(lname) .. ')' or '')
    end)

    add('REMOVE_HF_ENTITY_LINK', function(ev, focal)
        local hf_id  = safe_get(ev, 'histfig')
        local civ_id = safe_get(ev, 'civ')
        local ltype  = safe_get(ev, 'link_type')
        local pos_id = safe_get(ev, 'position_id')
        local ent_n  = ent_name_by_id(civ_id) or 'an entity'
        local hf_n   = hf_name_by_id(hf_id) or 'someone'
        local LT     = df.histfig_entity_link_type
        local civ_focal = (focal == civ_id)
        if ltype == LT.POSITION or ltype == LT.SQUAD then
            local hf    = hf_id and df.historical_figure.find(hf_id)
            local pos_n = pos_name_for(civ_id, pos_id, hf and hf.sex or -1)
            if pos_n then
                if civ_focal then return hf_n .. ' stopped being ' .. pos_n end
                return 'Stopped being ' .. pos_n .. ' of ' .. ent_n
            end
        elseif ltype == LT.PRISONER then
            if civ_focal then return hf_n .. ' escaped from prison' end
            return 'Escaped from the prisons of ' .. ent_n
        elseif ltype == LT.SLAVE then
            if civ_focal then return hf_n .. ' fled from slavery' end
            return 'Fled from ' .. ent_n
        elseif ltype == LT.ENEMY then
            if civ_focal then return hf_n .. ' stopped being an enemy' end
            return 'Stopped being an enemy of ' .. ent_n
        end
        if civ_focal then return hf_n .. ' left' end
        return 'Left ' .. ent_n
    end)

    add('CHANGE_HF_JOB', function(ev, focal)
        local old_job  = safe_get(ev, 'old_job')
        local new_job  = safe_get(ev, 'new_job')
        local site_n   = site_name_by_id(safe_get(ev, 'site'))
        local site_sfx = site_n and (' in ' .. site_n) or ''
        local function is_standard(job)
            if job == nil then return true end
            local name = df.profession and df.profession[job]
            if name == nil then return true end
            name = name:upper()
            return name == 'NONE' or name == 'STANDARD' or name == 'PEASANT' or name == 'CHILD' or name == 'BABY'
        end
        local function job_name(job)
            local name = df.profession and df.profession[job]
            return name and title_case(name) or nil
        end
        local old_std = is_standard(old_job)
        local new_std = is_standard(new_job)
        if not old_std and not new_std then
            return 'Gave up being ' .. article(job_name(old_job)) ..
                ' to become ' .. article(job_name(new_job)) .. site_sfx
        elseif not new_std then
            return 'Became ' .. article(job_name(new_job)) .. site_sfx
        elseif not old_std then
            return 'Stopped being ' .. article(job_name(old_job)) .. site_sfx
        else
            return 'Became a peasant' .. site_sfx
        end
    end)

    add('ADD_HF_HF_LINK', function(ev, focal)
        local hf_id     = safe_get(ev, 'hf')
        local target_id = safe_get(ev, 'hf_target')
        local ltype     = safe_get(ev, 'type')
        local LT        = df.histfig_hf_link_type
        if not LT then
            local other_id = (focal == hf_id) and target_id or hf_id
            return 'Linked with ' .. (hf_name_by_id(other_id) or 'someone')
        end
        local focal_is_hf = (focal == hf_id)
        local other_id    = focal_is_hf and target_id or hf_id
        local other       = hf_name_by_id(other_id) or 'someone'
        if ltype == LT.SPOUSE then
            return 'Married ' .. other
        elseif ltype == LT.LOVER then
            return 'Became romantically involved with ' .. other
        elseif ltype == LT.APPRENTICE then
            if focal_is_hf then
                return 'Became the master of ' .. other
            else
                return 'Began an apprenticeship under ' .. other
            end
        elseif ltype == LT.MASTER then
            if focal_is_hf then
                return 'Became the master of ' .. other
            else
                return 'Began an apprenticeship under ' .. other
            end
        elseif ltype == LT.DEITY then
            if focal_is_hf then
                return 'Received the worship of ' .. other
            else
                return 'Began worshipping ' .. other
            end
        elseif ltype == LT.PRISONER then
            if focal_is_hf then
                return 'Imprisoned ' .. other
            else
                return 'Was imprisoned by ' .. other
            end
        end
        local lname = ltype and LT[ltype]
        return (lname and title_case(lname) or 'Linked') .. ' with ' .. other
    end)

    add('REMOVE_HF_HF_LINK', function(ev, focal)
        local hf_id     = safe_get(ev, 'hf')
        local target_id = safe_get(ev, 'hf_target')
        local ltype     = safe_get(ev, 'type')
        local LT        = df.histfig_hf_link_type
        local focal_is_hf = (focal == hf_id)
        local other_id    = focal_is_hf and target_id or hf_id
        local other       = hf_name_by_id(other_id) or 'someone'
        if LT then
            if ltype == LT.FORMER_SPOUSE then
                return 'Divorced ' .. other
            elseif ltype == LT.FORMER_APPRENTICE then
                if focal_is_hf then
                    return 'Ceased being the master of ' .. other
                else
                    return 'Ceased being the apprentice of ' .. other
                end
            elseif ltype == LT.FORMER_MASTER then
                if focal_is_hf then
                    return 'Ceased being the master of ' .. other
                else
                    return 'Ceased being the apprentice of ' .. other
                end
            end
        end
        return 'Relationship ended with ' .. other
    end)

    add('CHANGE_HF_STATE', function(ev, focal)
        local state    = safe_get(ev, 'state')
        local substate = safe_get(ev, 'substate')
        local site_id  = safe_get(ev, 'site')
        local mood     = safe_get(ev, 'mood')
        local reason   = safe_get(ev, 'reason')
        local site_n   = site_name_by_id(site_id)
        local loc      = site_n or 'unknown location'

        local function reason_sfx()
            if reason == nil then return '' end
            local rname = df.history_event_reason and df.history_event_reason[reason]
            if rname == 'FLIGHT' then return ' in order to flee'
            elseif rname == 'SCHOLARSHIP' then return ' to pursue scholarship'
            elseif rname == 'FAILED_MOOD' then return ' after failing to create an artifact'
            elseif rname == 'EXILED_AFTER_CONVICTION' then return ' after being exiled'
            end
            return ''
        end

        -- Try several potential DFHack enum paths for this field.
        local sname
        if state ~= nil and state >= 0 then
            for _, epath in ipairs({'hang_around_location_type', 'histfig_state'}) do
                local ok, en = pcall(function() return df[epath] end)
                if ok and en then
                    local n = en[state]
                    if n then sname = n; break end
                end
            end
            -- Integer fallback (values from DF data; enum lookup often unavailable)
            if not sname then
                local STATE_INT = {
                    [0]='VISITING', [1]='SETTLED',  [2]='WANDERING',
                    [3]='REFUGEE',  [4]='SNATCHER', [5]='THIEF',
                    [6]='SCOUTING', [7]='HUNTING',
                }
                sname = STATE_INT[state]
            end
        end

        if sname then
            if sname == 'VISITING' then
                if not site_n then return 'Began wandering' end
                return 'visited ' .. site_n
            elseif sname == 'SETTLED' then
                if substate == 45 then
                    return 'Fled to ' .. loc
                elseif substate == 46 or substate == 47 then
                    return 'Moved to study in ' .. loc
                end
                return 'Settled in ' .. loc .. reason_sfx()
            elseif sname == 'WANDERING' then
                return 'Began wandering ' .. loc
            elseif sname == 'REFUGEE' then
                return 'Became a refugee in ' .. loc
            elseif sname == 'SNATCHER' then
                return 'Became a snatcher in ' .. loc
            elseif sname == 'THIEF' then
                return 'Became a thief in ' .. loc
            elseif sname == 'SCOUTING' then
                return 'Began scouting ' .. loc
            elseif sname == 'HUNTING' then
                return 'Began hunting great beasts in ' .. loc
            else
                return title_case(sname) .. ' in ' .. loc
            end
        end

        if mood ~= nil then
            local mname = df.mood_type and df.mood_type[mood]
            local MOOD_TEXT = {
                FEY        = 'Was taken by a fey mood',
                SECRETIVE  = 'Withdrew from society',
                POSSESSED  = 'Was possessed',
                FELL       = 'Was taken by a fell mood',
                MACABRE    = 'Began to skulk and brood',
                BERSERK    = 'Went berserk',
                MELANCHOLY = 'Was stricken by melancholy',
            }
            local mt = mname and MOOD_TEXT[mname]
            if mt then return mt .. reason_sfx() end
        end

        -- Return nil; falls back to enum name display.
        return nil
    end)

    add('ADD_HF_SITE_LINK', function(ev, focal)
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        local ltype  = safe_get(ev, 'link_type')
        local loc    = site_n or 'a site'
        local LST    = df.histfig_site_link_type
        if LST then
            if ltype == LST.LAIR then
                return 'Made ' .. loc .. ' their lair'
            elseif ltype == LST.HANGOUT then
                return 'Made ' .. loc .. ' their hangout'
            elseif ltype == LST.HOME_SITE_BUILDING or ltype == LST.HOME_SITE_ABSTRACT_BUILDING then
                return 'Made ' .. loc .. ' their home'
            elseif ltype == LST.OCCUPATION then
                return 'Took up occupation at ' .. loc
            end
        end
        local lname = ltype and LST and LST[ltype]
        return 'Established connection at ' .. loc .. (lname and ' (' .. title_case(lname) .. ')' or '')
    end)

    add('REMOVE_HF_SITE_LINK', function(ev, focal)
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        local ltype  = safe_get(ev, 'link_type')
        local loc    = site_n or 'a site'
        local LST    = df.histfig_site_link_type
        if LST then
            if ltype == LST.LAIR then
                return 'Abandoned ' .. loc .. ' as their lair'
            elseif ltype == LST.HANGOUT then
                return 'Left ' .. loc .. ' as their hangout'
            elseif ltype == LST.HOME_SITE_BUILDING or ltype == LST.HOME_SITE_ABSTRACT_BUILDING then
                return 'Left their home at ' .. loc
            elseif ltype == LST.OCCUPATION then
                return 'Left their occupation at ' .. loc
            end
        end
        return 'Lost connection to ' .. loc
    end)

    local function hf_simple_battle_fn(ev, focal)
        local subtype = safe_get(ev, 'subtype')
        local ok1, hf1_id = pcall(function() return ev.group1[0] end)
        local ok2, hf2_id = pcall(function() return ev.group2[0] end)
        if not ok1 then hf1_id = nil end
        if not ok2 then hf2_id = nil end
        local BT    = df.history_event_hf_simple_battle_event_type
        local sname = BT and BT[subtype]

        -- Verb-first so format_event's first-char lowercase doesn't corrupt a name.
        local in_g1 = hf1_id ~= nil and focal == hf1_id
        local in_g2 = hf2_id ~= nil and focal == hf2_id
        if in_g1 or in_g2 then
            local other = hf_name_by_id(in_g1 and hf2_id or hf1_id) or 'someone'
            if sname == 'ATTACKED' then
                return in_g1 and ('Attacked ' .. other) or ('Was attacked by ' .. other)
            elseif sname == 'SCUFFLE' then
                return 'Fought with ' .. other
            elseif sname == 'CONFRONTED' then
                return in_g1 and ('Confronted ' .. other) or ('Was confronted by ' .. other)
            elseif sname == 'HAPPENED_UPON' then
                return in_g1 and ('Came upon ' .. other) or ('Was happened upon by ' .. other)
            elseif sname == 'AMBUSHED' then
                return in_g1 and ('Ambushed ' .. other) or ('Was ambushed by ' .. other)
            elseif sname == 'CORNERED' then
                return in_g1 and ('Cornered ' .. other) or ('Was cornered by ' .. other)
            elseif sname == 'SURPRISED' then
                return in_g1 and ('Surprised ' .. other) or ('Was surprised by ' .. other)
            elseif sname == 'GOT_INTO_A_BRAWL' then
                return 'Got into a brawl with ' .. other
            elseif sname == 'SUBDUED' then
                return in_g1 and ('Subdued ' .. other) or ('Was subdued by ' .. other)
            elseif sname == 'HF2_LOST_AFTER_RECEIVING_WOUNDS' then
                if in_g1 then return 'Prevailed; ' .. other .. ' escaped wounded' end
                return 'Escaped wounded from ' .. other
            elseif sname == 'HF2_LOST_AFTER_GIVING_WOUNDS' then
                if in_g1 then return 'Prevailed despite wounds from ' .. other end
                return 'Was forced to retreat after wounding ' .. other
            elseif sname == 'HF2_LOST_AFTER_MUTUAL_WOUNDS' then
                if in_g1 then return 'Eventually prevailed; ' .. other .. ' escaped' end
                return 'Escaped after a mutual battle with ' .. other
            end
            return 'Fought with ' .. other
        end

        -- Non-focal fallback (used by event_will_be_shown with focal=-1).
        local hf1 = hf_name_by_id(hf1_id) or 'someone'
        local hf2 = hf_name_by_id(hf2_id) or 'someone'
        if sname == 'ATTACKED' then
            return hf1 .. ' attacked ' .. hf2
        elseif sname == 'SUBDUED' then
            return hf1 .. ' subdued ' .. hf2
        end
        return hf1 .. ' and ' .. hf2 .. ' were in a battle'
    end
    add('HF_SIMPLE_BATTLE_EVENT',         hf_simple_battle_fn)
    add('HIST_FIGURE_SIMPLE_BATTLE_EVENT', hf_simple_battle_fn)

    local function hf_abducted_fn(ev, focal)
        local snatcher_id = safe_get(ev, 'snatcher')  -- df-structures: 'snatcher' not 'snatcher_hf'
        local target_id   = safe_get(ev, 'target')    -- df-structures: 'target' not 'target_hf'
        local site_n      = site_name_by_id(safe_get(ev, 'site'))
        local site_sfx    = site_n and (' from ' .. site_n) or ''
        local snatcher    = hf_name_by_id(snatcher_id) or 'someone'
        local target      = hf_name_by_id(target_id) or 'someone'
        if focal == snatcher_id then
            return 'Abducted ' .. target .. site_sfx
        elseif focal == target_id then
            return 'Abducted by ' .. snatcher .. site_sfx
        end
        return snatcher .. ' abducted ' .. target .. site_sfx
    end
    add('HF_ABDUCTED',          hf_abducted_fn)
    add('HIST_FIGURE_ABDUCTED', hf_abducted_fn)

    add('HF_DOES_INTERACTION', function(ev, focal)
        local doer_id   = safe_get(ev, 'doer')
        local target_id = safe_get(ev, 'target')
        local doer      = hf_name_by_id(doer_id) or 'someone'
        local target    = hf_name_by_id(target_id) or 'someone'
        local iaction   = safe_get(ev, 'interaction_action')
        if type(iaction) == 'string' and iaction ~= '' then
            local ia_lower = iaction:lower()
            if ia_lower:find('bit') and ia_lower:find('passing on') then
                if focal == doer_id then
                    return 'Bit ' .. target .. ', passing on the curse'
                elseif focal == target_id then
                    return 'Bitten by ' .. doer .. ', curse passed on'
                end
                return doer .. ' bit ' .. target .. ', passing on the curse'
            elseif ia_lower:find('cursed to assume the form') then
                if focal == doer_id then
                    return 'Cursed ' .. target .. ' to assume a beast form'
                elseif focal == target_id then
                    return 'Cursed by ' .. doer .. ' to assume a beast form'
                end
                return doer .. ' cursed ' .. target .. ' to assume a beast form'
            end
            if focal == doer_id then
                return 'Performed an interaction on ' .. target
            elseif focal == target_id then
                return 'Was targeted by an interaction from ' .. doer
            end
            return doer .. ' performed an interaction on ' .. target
        end
        if focal == doer_id then
            return 'Interacted with ' .. target
        else
            return 'Targeted by ' .. doer
        end
    end)

    add('MASTERPIECE_CREATED_ITEM', function(ev, focal)
        local itype  = safe_get(ev, 'item_subtype') or safe_get(ev, 'item_type')
        local iname  = itype and df.item_type and df.item_type[itype]
        local ent_n  = ent_name_by_id(safe_get(ev, 'maker_entity'))
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        local result = 'Created a masterful' .. (iname and (' ' .. title_case(iname)) or ' item')
        if ent_n then result = result .. ' for ' .. ent_n end
        if site_n then result = result .. ' in ' .. site_n end
        return result
    end)

    add('ARTIFACT_STORED', function(ev, focal)
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        local art_id = safe_get(ev, 'artifact_id') or safe_get(ev, 'artifact_record')
        local art_n, art_desc = artifact_name_by_id(art_id)
        local what
        if art_n and art_desc then
            what = art_n .. ', ' .. article(art_desc)
        elseif art_n then
            what = 'the artifact ' .. art_n
        else
            what = 'an artifact'
        end
        return 'Stored ' .. what .. (site_n and (' in ' .. site_n) or '')
    end)

    add('CREATE_ENTITY_POSITION', function(ev, focal)
        local civ_id = safe_get(ev, 'civ') or safe_get(ev, 'entity_id')
        local pos_id = safe_get(ev, 'position_id') or safe_get(ev, 'assignment_id')
        local ent_n  = ent_name_by_id(civ_id) or 'an entity'
        local pos_n  = civ_id and pos_id and pos_name_for(civ_id, pos_id, -1)
        if pos_n then
            return 'established the position of ' .. pos_n .. ' in ' .. ent_n
        end
        return 'established a new position in ' .. ent_n
    end)

    add('ASSUME_IDENTITY', function(ev, focal)
        -- Fields: trickster (HF ID), identity (identity ID), target (-1 if none).
        -- df.identity: impersonated_hf = real HF being impersonated (-1 if fictitious),
        --              histfig_id = the trickster's own HF ID (NOT the impersonated person),
        --              name = the fake name used.
        local ident_id = safe_get(ev, 'identity')
        if ident_id and ident_id >= 0 then
            local ok, identity = pcall(function() return df.identity.find(ident_id) end)
            if ok and identity then
                -- Check if impersonating a real HF.
                local imp_id = safe_get(identity, 'impersonated_hf')
                if imp_id and imp_id >= 0 then
                    local n = hf_name_by_id(imp_id)
                    if n then return 'Assumed the identity of ' .. n end
                end
                -- Fictitious identity - use the fake name.
                local ok2, n = pcall(function()
                    return dfhack.translation.translateName(identity.name, true)
                end)
                if ok2 and n and n ~= '' then
                    return 'Assumed the identity "' .. n .. '"'
                end
            end
        end
        return 'Assumed an identity'
    end)

    add('ITEM_STOLEN', function(ev, focal)
        -- Fields: item_type, mattype, matindex, entity, histfig, site. item is always -1.
        local itype  = safe_get(ev, 'item_type')
        local iname  = itype and itype >= 0 and df.item_type and df.item_type[itype]
        local type_s = iname and title_case(tostring(iname)):lower() or nil
        -- Resolve material via mattype/matindex.
        local mat_s
        local mt = safe_get(ev, 'mattype')
        local mi = safe_get(ev, 'matindex')
        if mt and mt >= 0 then
            local ok, info = pcall(function() return dfhack.matinfo.decode(mt, mi or -1) end)
            if ok and info then
                local ok2, s = pcall(function() return info:toString() end)
                if ok2 and s and s ~= '' then mat_s = s:lower() end
            end
        end
        -- "a copper sword" / "a sword" / "an item"
        local what
        if mat_s and type_s then
            what = article(mat_s .. ' ' .. type_s)
        elseif type_s then
            what = article(type_s)
        else
            what = 'an item'
        end
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        local ent_n  = ent_name_by_id(safe_get(ev, 'entity'))
        local thief  = hf_name_by_id(safe_get(ev, 'histfig'))
        local loc    = site_n and (' in ' .. site_n) or ''
        local from   = ent_n and (' from ' .. ent_n) or ''
        if focal == safe_get(ev, 'histfig') then
            return 'Stole ' .. what .. from .. loc
        end
        local who = thief or 'Someone'
        return who .. ' stole ' .. what .. from .. loc
    end)

    add('ARTIFACT_CLAIM_FORMED', function(ev, focal)
        -- Fields: artifact (ID), histfig, entity, claim_type, position_profile.
        local art_n, art_desc = artifact_name_by_id(safe_get(ev, 'artifact'))
        local what
        if art_n and art_desc then
            what = 'a claim on ' .. art_n .. ', ' .. article(art_desc)
        elseif art_n then
            what = 'a claim on ' .. art_n
        else
            what = 'an artifact claim'
        end
        local ent_n = ent_name_by_id(safe_get(ev, 'entity'))
        if ent_n then what = what .. ' for ' .. ent_n end
        return 'Formed ' .. what
    end)

    add('GAMBLE', function(ev, focal)
        -- Fields: hf, site, structure, account_before, account_after.
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        local bld_n  = building_name_at_site(safe_get(ev, 'site'), safe_get(ev, 'structure'))
        local loc    = bld_n and ('at ' .. bld_n) or nil
        if site_n then loc = (loc and (loc .. ' in ') or 'in ') .. site_n end
        local before = safe_get(ev, 'account_before') or 0
        local after  = safe_get(ev, 'account_after') or 0
        local result = after > before and ' and won' or after < before and ' and lost' or ''
        return 'Gambled ' .. (loc or '') .. result
    end)

    add('ENTITY_CREATED', function(ev, focal)
        -- Fields: entity, site, structure, creator_hfid.
        local ent_id   = safe_get(ev, 'entity')
        local ent_n    = ent_name_by_id(ent_id)
        local site_n   = site_name_by_id(safe_get(ev, 'site'))
        local loc      = site_n and (' in ' .. site_n) or ''
        local what     = ent_n and (' ' .. ent_n) or ' an entity'
        local creator  = safe_get(ev, 'creator_hfid')
        -- Civ-focal: "Founded [by creator]"
        if focal == ent_id then
            if creator and creator >= 0 then
                local who = hf_name_by_id(creator) or 'Someone'
                return 'Founded by ' .. who .. loc
            end
            return 'Founded' .. loc
        end
        if creator and creator >= 0 and focal == creator then
            return 'Founded' .. what .. loc
        elseif creator and creator >= 0 then
            local who = hf_name_by_id(creator) or 'Someone'
            return who .. ' founded' .. what .. loc
        end
        return 'Founded' .. what .. loc
    end)

    add('FAILED_INTRIGUE_CORRUPTION', function(ev, focal)
        -- Fields: corruptor_hf, target_hf, corruptor_identity, target_identity, site.
        local corr_id = safe_get(ev, 'corruptor_hf')
        local tgt_id  = safe_get(ev, 'target_hf')
        local site_n  = site_name_by_id(safe_get(ev, 'site'))
        local loc     = site_n and (' in ' .. site_n) or ''
        if focal == corr_id then
            local tgt = hf_name_by_id(tgt_id) or 'someone'
            return 'Failed to corrupt ' .. tgt .. loc
        elseif focal == tgt_id then
            local corr = hf_name_by_id(corr_id) or 'Someone'
            return corr .. ' failed to corrupt them' .. loc
        end
        local corr = hf_name_by_id(corr_id) or 'Someone'
        local tgt  = hf_name_by_id(tgt_id) or 'someone'
        return corr .. ' failed to corrupt ' .. tgt .. loc
    end)

    add('HF_ACT_ON_BUILDING', function(ev, focal)
        -- Fields: action (enum int), histfig, site, structure.
        -- Known action values: 0=profaned, 2=prayed at (both observed on TEMPLE buildings).
        local ACT_VERBS = { [0] = 'Profaned', [2] = 'Prayed at' }
        local act    = safe_get(ev, 'action')
        local verb   = act and ACT_VERBS[act] or 'Visited'
        local bld_n  = building_name_at_site(safe_get(ev, 'site'), safe_get(ev, 'structure'))
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        if bld_n and site_n then
            return verb .. ' ' .. bld_n .. ' in ' .. site_n
        elseif bld_n then
            return verb .. ' ' .. bld_n
        elseif site_n then
            return verb .. ' a building in ' .. site_n
        end
        return verb .. ' a building'
    end)

    -- competitor_hf / winner_hf are stl-vectors; iterated in get_hf_events.
    add('COMPETITION', function(ev, focal)
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        local loc    = site_n and (' in ' .. site_n) or ''
        -- Collect all unique participants excluding focal (from both lists).
        local others, seen = {}, {}
        local function collect(field)
            local ok, list = pcall(function() return ev[field] end)
            if not ok or not list then return end
            local ok_n, n = pcall(function() return #list end)
            if not ok_n then return end
            for i = 0, n - 1 do
                local ok2, v = pcall(function() return list[i] end)
                if ok2 and v ~= focal and not seen[v] then
                    seen[v] = true
                    table.insert(others, v)
                end
            end
        end
        collect('competitor_hf')
        collect('winner_hf')
        local function participants_sfx()
            if #others == 0 then return '' end
            local MAX_NAMES = 3
            local names = {}
            for i = 1, math.min(#others, MAX_NAMES) do
                table.insert(names, hf_name_by_id(others[i]) or 'someone')
            end
            local remaining = #others - MAX_NAMES
            local text = ' against ' .. table.concat(names, ', ')
            if remaining > 0 then
                text = text .. ' and ' .. remaining .. ' other' .. (remaining > 1 and 's' or '')
            end
            return text
        end
        -- Check if focal is a winner.
        local ok_w, wlist = pcall(function() return ev.winner_hf end)
        if ok_w and wlist then
            local ok_n, n = pcall(function() return #wlist end)
            if ok_n then
                for i = 0, n - 1 do
                    local ok2, v = pcall(function() return wlist[i] end)
                    if ok2 and v == focal then
                        return 'Won a competition' .. participants_sfx() .. loc
                    end
                end
            end
        end
        -- Check if focal is a competitor.
        if seen[focal] or (function()
            local ok_c, clist = pcall(function() return ev.competitor_hf end)
            if not ok_c or not clist then return false end
            local ok_n, n = pcall(function() return #clist end)
            if not ok_n then return false end
            for i = 0, n - 1 do
                local ok2, v = pcall(function() return clist[i] end)
                if ok2 and v == focal then return true end
            end
            return false
        end)() then
            return 'Competed in a competition' .. participants_sfx() .. loc
        end
        return 'A competition was held' .. loc
    end)

    add('WAR_FIELD_BATTLE', function(ev, focal)
        local att_hf  = safe_get(ev, 'attacker_general_hf')
        local def_hf  = safe_get(ev, 'defender_general_hf')
        local att_civ = ent_name_by_id(safe_get(ev, 'attacker_civ'))
        local def_civ = ent_name_by_id(safe_get(ev, 'defender_civ'))
        local site_n  = site_name_by_id(safe_get(ev, 'site'))
        local loc     = site_n and (' at ' .. site_n) or ''
        if focal == att_hf then
            local vs = def_civ and (' against ' .. def_civ) or ''
            return 'Led forces in battle' .. vs .. loc
        elseif focal == def_hf then
            local vs = att_civ and (' against ' .. att_civ) or ''
            return 'Defended in battle' .. vs .. loc
        end
        local att = hf_name_by_id(att_hf) or att_civ or 'unknown'
        local def = hf_name_by_id(def_hf) or def_civ or 'unknown'
        return att .. ' battled ' .. def .. loc
    end)

    add('WAR_ATTACKED_SITE', function(ev, focal)
        local att_hf  = safe_get(ev, 'attacker_general_hf')
        local def_hf  = safe_get(ev, 'defender_general_hf')
        local att_civ = ent_name_by_id(safe_get(ev, 'attacker_civ'))
        local def_civ = ent_name_by_id(safe_get(ev, 'defender_civ'))
        local site_n  = site_name_by_id(safe_get(ev, 'site'))
        local loc     = site_n and (' on ' .. site_n) or ' on a site'
        if focal == att_hf then
            local vs = def_civ and (' against ' .. def_civ) or ''
            return 'Led an attack' .. vs .. loc
        elseif focal == def_hf then
            local vs = att_civ and (' against ' .. att_civ) or ''
            return 'Defended' .. loc .. (vs ~= '' and vs or '')
        end
        local att = hf_name_by_id(att_hf) or att_civ or 'unknown'
        return att .. ' attacked' .. loc
    end)

    add('HF_ATTACKED_SITE', function(ev, focal)
        local att_hf  = safe_get(ev, 'attacker_hf')
        local def_civ = ent_name_by_id(safe_get(ev, 'defender_civ'))
        local site_n  = site_name_by_id(safe_get(ev, 'site'))
        local loc     = site_n or 'a site'
        local vs      = def_civ and (', defended by ' .. def_civ) or ''
        if focal == att_hf then
            return 'Attacked ' .. loc .. vs
        end
        local att = hf_name_by_id(att_hf) or 'someone'
        return att .. ' attacked ' .. loc .. vs
    end)

    add('HF_DESTROYED_SITE', function(ev, focal)
        local att_hf = safe_get(ev, 'attacker_hf')
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        local loc    = site_n and (' ' .. site_n) or ' a site'
        if focal == att_hf then
            return 'Destroyed' .. loc
        end
        local att = hf_name_by_id(att_hf) or 'someone'
        return att .. ' destroyed' .. loc
    end)

    -- histfig1/histfig2 may also appear as hfid1/hfid2 in older DFHack builds.
    add('HFS_FORMED_REPUTATION_RELATIONSHIP', function(ev, focal)
        local hf1   = safe_get(ev, 'histfig1') or safe_get(ev, 'hfid1')
        local hf2   = safe_get(ev, 'histfig2') or safe_get(ev, 'hfid2')
        local other = hf_name_by_id((focal == hf1) and hf2 or hf1) or 'someone'
        return 'Formed a relationship with ' .. other
    end)

    add('HF_RELATIONSHIP_DENIED', function(ev, focal)
        local seeker_id = safe_get(ev, 'seeker_hf')
        local target_id = safe_get(ev, 'target_hf')
        local rtype     = safe_get(ev, 'type')
        local rname     = rtype and (df.unit_relationship_type[rtype] or 'unknown')
                            or 'unknown'
        rname = rname:lower():gsub('_', ' ')
        if focal == seeker_id then
            local other = hf_name_by_id(target_id) or 'someone'
            return 'Was denied a ' .. rname .. ' relationship with ' .. other
        elseif focal == target_id then
            local other = hf_name_by_id(seeker_id) or 'someone'
            return 'Denied a ' .. rname .. ' relationship sought by ' .. other
        end
        local seeker = hf_name_by_id(seeker_id) or 'someone'
        local target = hf_name_by_id(target_id) or 'someone'
        return seeker .. ' was denied a ' .. rname .. ' relationship with ' .. target
    end)

    add('HFS_FORMED_INTRIGUE_RELATIONSHIP', function(ev, focal)
        local corruptor = safe_get(ev, 'corruptor_hf')
        local target    = safe_get(ev, 'target_hf')
        local other     = hf_name_by_id((focal == corruptor) and target or corruptor) or 'someone'
        if focal == corruptor then
            return 'Drew ' .. other .. ' into an intrigue'
        else
            return 'Was drawn into an intrigue by ' .. other
        end
    end)

    add('CHANGE_CREATURE_TYPE', function(ev, focal)
        local changee_id = safe_get(ev, 'changee')
        local changer_id = safe_get(ev, 'changer')
        local old_n      = creature_name(safe_get(ev, 'old_race')) or 'unknown creature'
        local new_n      = creature_name(safe_get(ev, 'new_race')) or 'unknown creature'
        local has_changer = changer_id and changer_id >= 0
        if focal == changee_id then
            local by_sfx = has_changer
                and (' by ' .. (hf_name_by_id(changer_id) or 'someone')) or ''
            return 'Transformed from ' .. article(old_n) .. ' into ' .. article(new_n) .. by_sfx
        elseif focal == changer_id then
            local changee = hf_name_by_id(changee_id) or 'someone'
            return 'Transformed ' .. changee .. ' from ' .. article(old_n) ..
                ' into ' .. article(new_n)
        end
        local changee = hf_name_by_id(changee_id) or 'someone'
        return changee .. ' transformed from ' .. article(old_n) .. ' into ' .. article(new_n)
    end)

    local function hf_wounded_fn(ev, focal)
        local woundee_id = safe_get(ev, 'woundee')  -- df-struct name='woundee'
        local wounder_id = safe_get(ev, 'wounder')  -- df-struct name='wounder'
        local site_n     = site_name_by_id(safe_get(ev, 'site'))
        local loc        = site_n and (' in ' .. site_n) or ''
        if focal == woundee_id then
            local by_sfx = (wounder_id and wounder_id >= 0)
                and (' by ' .. (hf_name_by_id(wounder_id) or 'someone')) or ''
            return 'Was wounded' .. by_sfx .. loc
        elseif focal == wounder_id then
            return 'Wounded ' .. (hf_name_by_id(woundee_id) or 'someone') .. loc
        end
        local woundee = hf_name_by_id(woundee_id) or 'someone'
        local wounder = hf_name_by_id(wounder_id) or 'someone'
        return woundee .. ' was wounded by ' .. wounder .. loc
    end
    add('HIST_FIGURE_WOUNDED', hf_wounded_fn)
    add('HF_WOUNDED',          hf_wounded_fn)

    add('ARTIFACT_CREATED', function(ev, focal)
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        local loc    = site_n and (' in ' .. site_n) or ''
        local art_id = safe_get(ev, 'artifact_id') or safe_get(ev, 'artifact_record')
        local art_n, art_desc = artifact_name_by_id(art_id)
        local what
        if art_n and art_desc then
            what = art_n .. ', ' .. article(art_desc)
        elseif art_n then
            what = 'the artifact ' .. art_n
        else
            what = 'an artifact'
        end
        return 'Created ' .. what .. loc
    end)

    add('CREATED_SITE', function(ev, focal)
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        if site_n then return 'Constructed ' .. site_n end
        return 'Constructed a settlement'
    end)

    local function created_structure_fn(ev, focal)
        local site_id = safe_get(ev, 'site')
        local site_n  = site_name_by_id(site_id)
        local loc     = site_n and (' in ' .. site_n) or ''
        local str_id  = safe_get(ev, 'structure')
        local bname   = building_name_at_site(site_id, str_id)
        if bname then return 'Constructed ' .. bname .. loc end
        return 'Constructed a structure' .. loc
    end
    add('CREATED_BUILDING',  created_structure_fn)
    add('CREATED_STRUCTURE', created_structure_fn)
end

-- Event collection context --------------------------------------------------
-- Maps collection type enums to priority (lower = more specific context).
local COLLECTION_PRIORITY = {}
do
    local P = {
        DUEL=1, BEAST_ATTACK=2, ABDUCTION=3, PURGE=4, THEFT=5,
        BATTLE=6, INSURRECTION=6, RAID=7, PERSECUTION=8,
        SITE_CONQUERED=9, ENTITY_OVERTHROWN=9, WAR=10,
        JOURNEY=11, COMPETITION=12, PERFORMANCE=12,
        OCCASION=12, PROCESSION=13, CEREMONY=13,
    }
    for name, pri in pairs(P) do
        local ok, v = pcall(function()
            return df.history_event_collection_type[name]
        end)
        if ok and v ~= nil then COLLECTION_PRIORITY[v] = pri end
    end
end

-- Scan all event collections and build { [event_id] = best_collection } map.
-- Keeps the highest-priority (lowest number) collection per event.
local function build_event_to_collection()
    local ok_all, all = pcall(function()
        return df.global.world.history.event_collections.all
    end)
    if not ok_all or not all then return {} end
    local ctx_map = {}
    for ci = 0, #all - 1 do
        local col = all[ci]
        local pri = COLLECTION_PRIORITY[col:getType()] or 99
        local ok_n, n = pcall(function() return #col.events end)
        if ok_n then
            for j = 0, n - 1 do
                local eid = col.events[j]
                local existing = ctx_map[eid]
                if existing then
                    local ex_pri = COLLECTION_PRIORITY[existing:getType()] or 99
                    if pri < ex_pri then ctx_map[eid] = col end
                else
                    ctx_map[eid] = col
                end
            end
        end
    end
    return ctx_map
end

-- Returns a human-readable context suffix for a collection, or nil.
-- skip_site=true avoids duplicating site info already in the base description.
local function describe_collection(col, skip_site)
    if not col then return nil end
    local ok, ctype = pcall(function()
        return df.history_event_collection_type[col:getType()]
    end)
    if not ok or not ctype then return nil end

    if ctype == 'DUEL' then
        local a    = hf_name_by_id(safe_get(col, 'attacker_hf')) or 'someone'
        local d    = hf_name_by_id(safe_get(col, 'defender_hf')) or 'someone'
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local loc  = site and (' at ' .. site) or ''
        return 'as part of a duel between ' .. a .. ' and ' .. d .. loc

    elseif ctype == 'BEAST_ATTACK' then
        -- attacker_hf is a vector (confirmed via probe)
        local ok_b, bv = pcall(function() return col.attacker_hf end)
        local beast = (ok_b and #bv > 0) and hf_name_by_id(bv[0]) or 'a beast'
        local site  = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local loc   = site and (' on ' .. site) or ''
        return 'during the rampage' .. loc .. ' by ' .. beast

    elseif ctype == 'ABDUCTION' then
        -- snatcher_hf/victim_hf are vectors; attacker_civ is scalar
        local ok_v, vv = pcall(function() return col.victim_hf end)
        local victim = (ok_v and #vv > 0) and hf_name_by_id(vv[0]) or 'someone'
        local civ    = ent_name_by_id(safe_get(col, 'attacker_civ'))
        local site   = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local loc    = site and (' from ' .. site) or ''
        local by     = civ and (', ordered by ' .. civ) or ''
        return 'as part of the abduction of ' .. victim .. loc .. by

    elseif ctype == 'BATTLE' then
        -- name is language_name; attacker_civ/defender_civ are vectors (may be empty)
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local ok_n, bname = pcall(function()
            return dfhack.translation.translateName(col.name, true)
        end)
        if ok_n and bname and bname ~= '' then
            local loc = site and (' at ' .. site) or ''
            return 'during ' .. bname .. loc
        end
        local ok_ac, acv = pcall(function() return col.attacker_civ end)
        local ok_dc, dcv = pcall(function() return col.defender_civ end)
        local ac = (ok_ac and #acv > 0) and ent_name_by_id(acv[0]) or nil
        local dc = (ok_dc and #dcv > 0) and ent_name_by_id(dcv[0]) or nil
        local loc = site and (' at ' .. site) or ''
        if ac and dc then
            return 'during the battle' .. loc .. ' between ' .. ac .. ' and ' .. dc
        end
        return 'during a battle' .. loc

    elseif ctype == 'RAID' then
        -- Unverified (0 instances in test save); field names guarded with safe_get
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local ac   = ent_name_by_id(safe_get(col, 'attacking_entity'))
        local loc  = site and (' on ' .. site) or ''
        local by   = ac and (' by ' .. ac) or ''
        return 'during a raid' .. loc .. by

    elseif ctype == 'SITE_CONQUERED' then
        -- attacker_civ/defender_civ are vectors
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local ok_ac, acv = pcall(function() return col.attacker_civ end)
        local ac = (ok_ac and #acv > 0) and ent_name_by_id(acv[0]) or nil
        local loc = site and (' of ' .. site) or ''
        local by  = ac and (' by ' .. ac) or ''
        return 'during the conquest' .. loc .. by

    elseif ctype == 'WAR' then
        -- name is language_name; attacker_civ/defender_civ are vectors
        local ok_n, war_name = pcall(function()
            return dfhack.translation.translateName(col.name, true)
        end)
        if ok_n and war_name and war_name ~= '' then
            return 'during ' .. war_name
        end
        local ok_ac, acv = pcall(function() return col.attacker_civ end)
        local ok_dc, dcv = pcall(function() return col.defender_civ end)
        local ac = (ok_ac and #acv > 0) and ent_name_by_id(acv[0]) or nil
        local dc = (ok_dc and #dcv > 0) and ent_name_by_id(dcv[0]) or nil
        if ac and dc then
            return 'as part of the war between ' .. ac .. ' and ' .. dc
        end
        return nil

    elseif ctype == 'PERSECUTION' then
        -- entity is scalar (persecutor); site is scalar
        local ent  = ent_name_by_id(safe_get(col, 'entity'))
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local by   = ent and (' by ' .. ent) or ''
        local loc  = site and (' at ' .. site) or ''
        return 'during a persecution' .. by .. loc

    elseif ctype == 'ENTITY_OVERTHROWN' then
        -- entity is scalar (overthrown entity); site is scalar
        local ent  = ent_name_by_id(safe_get(col, 'entity'))
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local of_  = ent and (' of ' .. ent) or ''
        local loc  = site and (' at ' .. site) or ''
        return 'during the overthrow' .. of_ .. loc

    elseif ctype == 'JOURNEY' then
        return 'during a journey'

    elseif ctype == 'OCCASION' or ctype == 'COMPETITION' or ctype == 'PERFORMANCE'
        or ctype == 'PROCESSION' or ctype == 'CEREMONY' then
        -- civ is scalar entity ID; no site field
        local labels = {
            OCCASION='a gathering', COMPETITION='a competition',
            PERFORMANCE='a performance', PROCESSION='a procession',
            CEREMONY='a ceremony',
        }
        local civ = ent_name_by_id(safe_get(col, 'civ'))
        local by  = civ and (' by ' .. civ) or ''
        return 'during ' .. labels[ctype] .. by

    elseif ctype == 'THEFT' then
        -- Unverified (0 instances in test save)
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local ac   = ent_name_by_id(safe_get(col, 'attacking_entity'))
        local loc  = site and (' from ' .. site) or ''
        local by   = ac and (' by ' .. ac) or ''
        return 'during a theft' .. loc .. by

    elseif ctype == 'INSURRECTION' then
        -- Unverified (0 instances in test save)
        local ent  = ent_name_by_id(safe_get(col, 'target_entity'))
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local vs   = ent and (' against ' .. ent) or ''
        local loc  = site and (' at ' .. site) or ''
        return 'during an insurrection' .. vs .. loc

    elseif ctype == 'PURGE' then
        -- Unverified (0 instances in test save)
        local ent  = ent_name_by_id(safe_get(col, 'entity'))
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local of_  = ent and (' of ' .. ent) or ''
        local loc  = site and (' at ' .. site) or ''
        return 'during the purge' .. of_ .. loc
    end

    return nil
end

-- Civ event history helpers ----------------------------------------------------

-- Returns true if a collection involves the given civ_id as attacker, defender,
-- or participant. pcall-guarded for version safety.
function civ_matches_collection(col, civ_id)
    if not col or not civ_id then return false end
    local ok, ctype = pcall(function()
        return df.history_event_collection_type[col:getType()]
    end)
    if not ok or not ctype then return false end

    -- Check a scalar field for civ_id match.
    local function scalar_match(field)
        local v = safe_get(col, field)
        return v and v == civ_id
    end

    -- Check a vector field for civ_id match.
    local function vec_match(field)
        local ok_v, vec = pcall(function() return col[field] end)
        if not ok_v or not vec then return false end
        local ok_n, n = pcall(function() return #vec end)
        if not ok_n then return false end
        for i = 0, n - 1 do
            local ok2, v = pcall(function() return vec[i] end)
            if ok2 and v == civ_id then return true end
        end
        return false
    end

    if ctype == 'WAR' or ctype == 'BATTLE' or ctype == 'SITE_CONQUERED' then
        return vec_match('attacker_civ') or vec_match('defender_civ')
    elseif ctype == 'RAID' or ctype == 'THEFT' then
        return scalar_match('attacking_entity') or scalar_match('attacker_civ')
    elseif ctype == 'ABDUCTION' then
        return scalar_match('attacker_civ')
    elseif ctype == 'ENTITY_OVERTHROWN' or ctype == 'PERSECUTION' or ctype == 'PURGE' then
        return scalar_match('entity')
    elseif ctype == 'INSURRECTION' then
        return scalar_match('target_entity')
    elseif ctype == 'OCCASION' or ctype == 'COMPETITION' or ctype == 'PERFORMANCE'
        or ctype == 'PROCESSION' or ctype == 'CEREMONY' then
        return scalar_match('civ')
    end
    return false
end

-- Returns a civ-perspective description for a collection entry (no year prefix).
-- focal_civ_id determines perspective (attacker vs defender).
-- Resolve site name from a collection's first event (fallback when the
-- collection type has no direct site field, e.g. OCCASION sub-collections).
local function site_from_collection_events(col)
    local ok_evs, evs = pcall(function() return col.events end)
    if not ok_evs or not evs then return nil end
    local ok_n, n = pcall(function() return #evs end)
    if not ok_n or n < 1 then return nil end
    local ev = df.history_event.find(evs[0])
    if not ev then return nil end
    return site_name_by_id(safe_get(ev, 'site'))
end

local function format_collection_entry(col, focal_civ_id)
    if not col then return 'Unknown event' end
    local ok, ctype = pcall(function()
        return df.history_event_collection_type[col:getType()]
    end)
    if not ok or not ctype then return 'Unknown event' end

    -- Helper: get translated collection name.
    local function col_name()
        local ok_n, n = pcall(function()
            return dfhack.translation.translateName(col.name, true)
        end)
        return (ok_n and n and n ~= '') and n or nil
    end

    -- Helper: get opponent civ name from attacker/defender vectors.
    local function opponent_from_vecs()
        local ok_ac, acv = pcall(function() return col.attacker_civ end)
        local ok_dc, dcv = pcall(function() return col.defender_civ end)
        local is_attacker = false
        if ok_ac and acv then
            local ok_n, n = pcall(function() return #acv end)
            if ok_n then
                for i = 0, n - 1 do
                    local ok2, v = pcall(function() return acv[i] end)
                    if ok2 and v == focal_civ_id then is_attacker = true; break end
                end
            end
        end
        local opp_vec = is_attacker and dcv or acv
        local ok_ov = is_attacker and ok_dc or ok_ac
        local opp_name
        if ok_ov and opp_vec then
            local ok_n, n = pcall(function() return #opp_vec end)
            if ok_n and n > 0 then
                opp_name = civ_name_by_id(opp_vec[0], focal_civ_id)
            end
        end
        return opp_name, is_attacker
    end

    if ctype == 'WAR' then
        local name = col_name()
        local opp, is_att = opponent_from_vecs()
        if name then
            local vs = opp and (' - war with ' .. opp) or ''
            return name .. vs
        end
        if opp then
            return is_att and ('declared war on ' .. opp)
                           or (opp .. ' declared war')
        end
        return 'war'

    elseif ctype == 'BATTLE' then
        local name = col_name()
        local site = site_name_by_id(safe_get(col, 'site'))
        local opp, _ = opponent_from_vecs()
        local loc = site and (' at ' .. site) or ''
        local vs  = opp and (' - against ' .. opp) or ''
        if name then return name .. loc .. vs end
        return 'battle' .. loc .. vs

    elseif ctype == 'SITE_CONQUERED' then
        local site = site_name_by_id(safe_get(col, 'site'))
        local opp, is_att = opponent_from_vecs()
        local loc = site or 'a site'
        if is_att then
            local from = opp and (' from ' .. opp) or ''
            return 'conquered ' .. loc .. from
        else
            local by = opp and (' by ' .. opp) or ''
            return loc .. ' was conquered' .. by
        end

    elseif ctype == 'RAID' then
        local site = site_name_by_id(safe_get(col, 'site'))
        local ac   = safe_get(col, 'attacking_entity') or safe_get(col, 'attacker_civ')
        local is_att = (ac == focal_civ_id)
        local loc  = site or 'a site'
        if is_att then
            return 'raided ' .. loc
        else
            local by = ac and ent_name_by_id(ac)
            return (by or 'Unknown') .. ' raided ' .. loc
        end

    elseif ctype == 'THEFT' then
        local site = site_name_by_id(safe_get(col, 'site'))
        local ac   = safe_get(col, 'attacking_entity') or safe_get(col, 'attacker_civ')
        local is_att = (ac == focal_civ_id)
        local loc  = site or 'a site'
        if is_att then
            return 'committed theft from ' .. loc
        else
            local by = ac and ent_name_by_id(ac)
            return (by or 'Unknown') .. ' committed theft from ' .. loc
        end

    elseif ctype == 'ABDUCTION' then
        local ok_v, vv = pcall(function() return col.victim_hf end)
        local victim = (ok_v and #vv > 0) and hf_name_by_id(vv[0]) or 'someone'
        local site = site_name_by_id(safe_get(col, 'site'))
        local loc  = site and (' from ' .. site) or ''
        return 'abduction of ' .. victim .. loc

    elseif ctype == 'ENTITY_OVERTHROWN' then
        local ent  = ent_name_by_id(safe_get(col, 'entity'))
        local site = site_name_by_id(safe_get(col, 'site'))
        local of_  = ent and (' of ' .. ent) or ''
        local loc  = site and (' at ' .. site) or ''
        return 'overthrow' .. of_ .. loc

    elseif ctype == 'PERSECUTION' then
        local ent  = ent_name_by_id(safe_get(col, 'entity'))
        local site = site_name_by_id(safe_get(col, 'site'))
        local by   = ent and (' by ' .. ent) or ''
        local loc  = site and (' at ' .. site) or ''
        return 'persecution' .. by .. loc

    elseif ctype == 'INSURRECTION' then
        local ent  = ent_name_by_id(safe_get(col, 'target_entity'))
        local site = site_name_by_id(safe_get(col, 'site'))
        local vs   = ent and (' against ' .. ent) or ''
        local loc  = site and (' at ' .. site) or ''
        return 'insurrection' .. vs .. loc

    elseif ctype == 'PURGE' then
        local ent  = ent_name_by_id(safe_get(col, 'entity'))
        local site = site_name_by_id(safe_get(col, 'site'))
        local of_  = ent and (' of ' .. ent) or ''
        local loc  = site and (' at ' .. site) or ''
        return 'purge' .. of_ .. loc

    elseif ctype == 'OCCASION' then
        -- OCCASION has no occasion_id or site field; try collection name,
        -- then resolve site from own events or first child collection's events.
        local name = col_name()
        local site = site_from_collection_events(col)
        if not site then
            -- Try first child collection's events for site.
            local ok_ch, children = pcall(function() return col.collections end)
            if ok_ch and children then
                local ok_n, n = pcall(function() return #children end)
                if ok_n and n > 0 then
                    local child = df.history_event_collection.find(children[0])
                    if child then site = site_from_collection_events(child) end
                end
            end
        end
        local desc = name and ('hosted ' .. name) or 'hosted a gathering'
        if site then desc = desc .. ' at ' .. site end
        return desc

    elseif ctype == 'COMPETITION' or ctype == 'PERFORMANCE'
        or ctype == 'PROCESSION' or ctype == 'CEREMONY' then
        local labels = {
            COMPETITION='held a competition',
            PERFORMANCE='held a performance',
            PROCESSION='held a procession',
            CEREMONY='held a ceremony',
        }
        -- No direct site field on these collection types; resolve from events.
        local site = site_from_collection_events(col)
        local desc = labels[ctype] or title_case(ctype)
        if site then desc = desc .. ' at ' .. site end
        return desc
    end

    local tc = title_case(ctype)
    return tc:sub(1,1):lower() .. tc:sub(2)
end

-- Event types that receive collection context appended to their description.
-- Value is a function(ev) -> boolean: true = skip site in context suffix.
local CTX_TYPES = {}
do
    local function add_ctx(type_name, skip_site_fn)
        local v = df.history_event_type[type_name]
        if v ~= nil then CTX_TYPES[v] = skip_site_fn end
    end
    local function has_site(ev)
        return site_name_by_id(safe_get(ev, 'site')) ~= nil
    end
    local function always_true() return true end
    local function always_false() return false end
    add_ctx('HF_SIMPLE_BATTLE_EVENT',         always_false)
    add_ctx('HIST_FIGURE_SIMPLE_BATTLE_EVENT', always_false)
    add_ctx('HIST_FIGURE_WOUNDED',             has_site)
    add_ctx('HF_WOUNDED',                      has_site)
    add_ctx('HIST_FIGURE_DIED',                has_site)
    add_ctx('HF_ABDUCTED',                     has_site)
    add_ctx('HIST_FIGURE_ABDUCTED',            has_site)
    add_ctx('HF_ATTACKED_SITE',                always_true)
    add_ctx('HF_DESTROYED_SITE',               always_true)
    add_ctx('WAR_ATTACKED_SITE',               always_true)
    add_ctx('WAR_FIELD_BATTLE',                has_site)
end

-- Exported: returns true if this event will produce visible text.
-- Used by herald-gui's build_hf_event_counts to exclude noise events from counts.
function event_will_be_shown(ev)
    local ev_type   = ev:getType()
    local describer = EVENT_DESCRIBE[ev_type]
    if not describer then return true end  -- no describer -> fallback text, always shown
    local ok, result = pcall(describer, ev, -1)
    return ok and result ~= nil
end

-- Event formatting and collection ---------------------------------------------

-- format_event: returns "In the year NNN, Description" for the popup list.
-- focal_hf_id contextualises text (e.g. "Slew X" vs "Slain by Y").
-- ctx_map (optional): { [event_id] = collection } for appending collection context.
-- civ_mode: when true, skips first-char lowercasing (civ-focal descriptions start
--           with HF names, not verbs).
local function format_event(ev, focal_hf_id, ctx_map, civ_mode)
    -- Synthetic entries from plain Lua tables (collections and relationships).
    if type(ev) == 'table' then
        -- Collection-level entries (civ event history).
        if ev._collection then
            local yr = (ev.year and ev.year ~= -1) and tostring(ev.year) or '???'
            local desc = format_collection_entry(ev.col, ev.civ_id)
            return ('In the year %s, %s'):format(yr, desc)
        end
        -- Relationship events from world.history.relationship_events.
        local yr    = (ev.year and ev.year ~= -1) and tostring(ev.year) or '???'
        local rtype = ev.rel_type
        local rname = rtype and rtype >= 0
            and (df.vague_relationship_type[rtype] or 'unknown'):lower():gsub('_', ' ')
            or 'unknown'
        local other_id = (focal_hf_id == ev.source_hf) and ev.target_hf or ev.source_hf
        local other    = hf_name_by_id(other_id) or 'someone'
        if rname:sub(1, 6) == 'former' then
            local what = rname:sub(8)  -- strip "former "
            return ('In the year %s, ended a %s relationship with %s'):format(yr, what, other)
        end
        return ('In the year %s, formed a %s bond with %s'):format(yr, rname, other)
    end
    local year    = (ev.year and ev.year ~= -1) and tostring(ev.year) or '???'
    local ev_type = ev:getType()
    local desc
    local describer = EVENT_DESCRIBE[ev_type]
    if describer then
        local ok, result = pcall(describer, ev, focal_hf_id)
        if ok then
            if result then
                -- Append collection context for qualifying event types.
                if ctx_map then
                    local col = ctx_map[ev.id]
                    local skip_fn = col and CTX_TYPES[ev_type]
                    if skip_fn then
                        local ctx = describe_collection(col, skip_fn(ev))
                        if ctx then result = result .. ', ' .. ctx end
                    end
                end
                desc = result
            else
                return nil  -- describer explicitly said: omit this event
            end
        end
        -- pcall error: fall through to clean_enum_name fallback
    end
    -- Fallback: reverse-lookup enum name and clean it up (only for events with no describer).
    if not desc then
        local raw = df.history_event_type[ev_type]
        desc = raw and clean_enum_name(raw) or tostring(ev_type)
    end
    -- HF mode: lowercase first char (verb-first: "Became king" -> "became king").
    -- Civ mode: keep as-is (name-first: "Imush became king" stays capitalised).
    if not civ_mode then
        desc = desc:sub(1,1):lower() .. desc:sub(2)
    end
    return ('In the year %s, %s'):format(year, desc)
end

-- Returns true if any element of a DF vector field on ev equals hf_id.
-- Triple-pcall pattern: (1) field may not exist on this event subtype,
-- (2) #vec may fail if not a real vector, (3) vec[i] may fail on bad index.
-- Used for battle events (group1/group2) and competition events (competitor_hf/winner_hf).
local function vec_has(ev, field, hf_id)
    local ok, vec = pcall(function() return ev[field] end)
    if not ok or not vec then return false end
    local ok2, n = pcall(function() return #vec end)
    if not ok2 then return false end
    for i = 0, n - 1 do
        local ok3, v = pcall(function() return vec[i] end)
        if ok3 and v == hf_id then return true end
    end
    return false
end

-- Shared sort comparator: order events by year, seconds, id.
local function event_sort_cmp(a, b)
    local ya, yb = (a.year or -1), (b.year or -1)
    if ya ~= yb then return ya < yb end
    local sa = safe_get(a, 'seconds') or -1
    local sb = safe_get(b, 'seconds') or -1
    if sa ~= sb then return sa < sb end
    local ia = safe_get(a, 'id') or -1
    local ib = safe_get(b, 'id') or -1
    return ia < ib
end

-- Pre-compute event-type integers once at module load.
local _BATTLE_TYPES = {}
for _, name in ipairs({'HF_SIMPLE_BATTLE_EVENT', 'HIST_FIGURE_SIMPLE_BATTLE_EVENT'}) do
    local v = df.history_event_type[name]
    if v ~= nil then _BATTLE_TYPES[v] = true end
end
local _COMP_TYPE       = df.history_event_type['COMPETITION']
local _WAR_BATTLE_TYPE = df.history_event_type['WAR_FIELD_BATTLE']

-- Dispatch table: event type integer -> scalar HF field names to check.
-- Reduces safe_get calls per event from ~28 to 1-4 for known types.
-- Types with vector HF fields (BATTLE_TYPES, COMPETITION) are handled separately.
-- Unknown types fall back to full HF_FIELDS scan.
TYPE_HF_FIELDS = {}
do
    local function map(name, fields)
        local v = df.history_event_type[name]
        if v ~= nil then TYPE_HF_FIELDS[v] = fields end
    end
    map('HIST_FIGURE_DIED',    {'victim_hf', 'slayer_hf'})
    map('CHANGE_HF_STATE',     {'hfid'})
    map('CHANGE_HF_JOB',       {'hfid'})
    map('ADD_HF_ENTITY_LINK',  {'histfig'})
    map('REMOVE_HF_ENTITY_LINK', {'histfig'})
    map('ADD_HF_SITE_LINK',    {'histfig'})
    map('REMOVE_HF_SITE_LINK', {'histfig'})
    map('ADD_HF_HF_LINK',      {'hf', 'hf_target'})
    map('REMOVE_HF_HF_LINK',   {'hf', 'hf_target'})
    map('HF_DOES_INTERACTION',  {'doer', 'target'})
    map('HF_ABDUCTED',          {'snatcher', 'target'})
    map('HIST_FIGURE_ABDUCTED', {'snatcher', 'target'})
    map('HF_ATTACKED_SITE',    {'attacker_hf'})
    map('HF_DESTROYED_SITE',   {'attacker_hf'})
    map('HFS_FORMED_REPUTATION_RELATIONSHIP', {'histfig1', 'histfig2', 'hfid1', 'hfid2'})
    map('HFS_FORMED_INTRIGUE_RELATIONSHIP',   {'corruptor_hf', 'target_hf'})
    map('HF_RELATIONSHIP_DENIED', {'seeker_hf', 'target_hf'})
    map('CHANGE_CREATURE_TYPE',   {'changee', 'changer'})
    map('HIST_FIGURE_WOUNDED',    {'woundee_hfid', 'wounder_hfid'})
    map('HF_WOUNDED',             {'woundee', 'wounder'})
    map('CREATED_SITE',           {'builder_hf'})
    map('CREATED_BUILDING',       {'builder_hf'})
    map('CREATED_STRUCTURE',      {'builder_hf'})
    map('ARTIFACT_CREATED',       {'creator_hfid'})
    map('WAR_FIELD_BATTLE',       {'attacker_general_hf', 'defender_general_hf'})
    map('WAR_ATTACKED_SITE',      {'attacker_general_hf', 'defender_general_hf', 'attacker_hf'})
    map('MASTERPIECE_CREATED_ITEM', {'maker', 'hfid'})
    map('ARTIFACT_STORED',          {'histfig', 'hfid', 'maker'})
    map('CREATE_ENTITY_POSITION',   {'histfig', 'hfid'})
    map('ITEM_STOLEN',               {'histfig'})
    map('ASSUME_IDENTITY',           {'trickster'})
    map('ARTIFACT_CLAIM_FORMED',     {'histfig', 'hfid'})
    map('GAMBLE',                     {'hf'})
    map('ENTITY_CREATED',            {'creator_hfid'})
    map('FAILED_INTRIGUE_CORRUPTION', {'corruptor_hf', 'target_hf'})
    map('HF_ACT_ON_BUILDING',        {'histfig'})
end

-- Civ event collection ---------------------------------------------------------

-- Pre-compute event type integers for civ position events.
local _ADD_HF_ENTITY_LINK    = df.history_event_type['ADD_HF_ENTITY_LINK']
local _REMOVE_HF_ENTITY_LINK = df.history_event_type['REMOVE_HF_ENTITY_LINK']
local _ENTITY_CREATED        = df.history_event_type['ENTITY_CREATED']

-- Helper: resolves a collection ID to a synthetic _collection entry.
local function col_to_entry(col, civ_id)
    local yr = safe_get(col, 'start_year')
    if not yr or yr < 0 then
        local ok_e, eid = pcall(function() return col.events[0] end)
        if ok_e and eid then
            local ev = df.history_event.find(eid)
            if ev then yr = ev.year end
        end
    end
    return { _collection = true, year = yr or -1, col = col, civ_id = civ_id }
end

-- Fast path: use cached civ event/collection IDs.
local function get_civ_events_cached(civ_id)
    local cache = dfhack.reqscript('herald-cache')
    local ev_ids  = cache.get_civ_event_ids(civ_id)
    local col_ids = cache.get_civ_collection_ids(civ_id)
    if not ev_ids and not col_ids then return nil end

    local results = {}

    -- Resolve cached collection IDs to collection objects.
    if col_ids then
        for _, col_id in ipairs(col_ids) do
            local col = df.history_event_collection.find(col_id)
            if col then
                table.insert(results, col_to_entry(col, civ_id))
            end
        end
    end

    -- Resolve cached event IDs to event objects.
    if ev_ids then
        for _, ev_id in ipairs(ev_ids) do
            local ev = df.history_event.find(ev_id)
            if ev then table.insert(results, ev) end
        end
    end

    return results
end

-- Collects events relevant to a civilisation: collection-level summaries for
-- warfare/raids/theft/kidnappings, plus individual position-change events.
-- Uses cache when available; falls back to full scan.
-- Returns (results, ctx_map) matching get_hf_events signature.
local function get_civ_events(civ_id)
    -- Try cached path first.
    local results = get_civ_events_cached(civ_id)

    if not results then
        -- Full scan fallback.
        results = {}

        -- Phase A: scan collections for civ involvement.
        local ok_all, all = pcall(function()
            return df.global.world.history.event_collections.all
        end)
        if ok_all and all then
            for ci = 0, #all - 1 do
                local col = all[ci]
                if civ_matches_collection(col, civ_id) then
                    table.insert(results, col_to_entry(col, civ_id))
                end
            end
        end

        -- Phase B: scan events for position changes and entity creation.
        local LT_POS = df.histfig_entity_link_type and df.histfig_entity_link_type.POSITION
        for _, ev in ipairs(df.global.world.history.events) do
            local ev_type = ev:getType()
            if (_ADD_HF_ENTITY_LINK and ev_type == _ADD_HF_ENTITY_LINK)
                or (_REMOVE_HF_ENTITY_LINK and ev_type == _REMOVE_HF_ENTITY_LINK) then
                local ev_civ = safe_get(ev, 'civ')
                if ev_civ == civ_id then
                    local ltype = safe_get(ev, 'link_type')
                    if LT_POS and ltype == LT_POS then
                        table.insert(results, ev)
                    end
                end
            elseif _ENTITY_CREATED and ev_type == _ENTITY_CREATED then
                if safe_get(ev, 'entity') == civ_id then
                    table.insert(results, ev)
                end
            end
        end
    end

    table.sort(results, event_sort_cmp)
    local ctx_map = build_event_to_collection()
    return results, ctx_map
end

-- HF event collection ----------------------------------------------------------

-- TODO: battle participation events are not yet showing in HF event history.
-- The two approaches below (BATTLE_TYPES vector check and contextual WAR_FIELD_BATTLE
-- aggregation) are implemented but not confirmed working; needs in-game verification.

-- Fast path: look up cached event IDs and resolve to event objects.
-- Falls back to full scan if cache not ready.
local function get_hf_events_cached(hf_id)
    local cache = dfhack.reqscript('herald-cache')
    local id_list = cache.get_hf_event_ids(hf_id)
    if not id_list then return nil end  -- cache miss -> full scan

    local results   = {}
    local added_ids = {}
    for _, ev_id in ipairs(id_list) do
        local ev = df.history_event.find(ev_id)
        if ev then
            added_ids[ev_id] = true
            table.insert(results, ev)
        end
    end
    return results, added_ids
end

local function get_hf_events(hf_id)
    -- Try cached path first.
    local results, added_ids = get_hf_events_cached(hf_id)
    if not results then
        -- Full scan fallback.
        results    = {}
        added_ids  = {}
        local battle_index = {}

        for _, ev in ipairs(df.global.world.history.events) do
            local ev_type = ev:getType()

            if _WAR_BATTLE_TYPE and ev_type == _WAR_BATTLE_TYPE then
                local site = safe_get(ev, 'site')
                local year = safe_get(ev, 'year')
                if site and site >= 0 and year and year >= 0 then
                    local key = site .. ':' .. year
                    if not battle_index[key] then battle_index[key] = {} end
                    table.insert(battle_index[key], ev)
                end
            end

            if _BATTLE_TYPES[ev_type] then
                if vec_has(ev, 'group1', hf_id) or vec_has(ev, 'group2', hf_id) then
                    added_ids[ev.id] = true
                    table.insert(results, ev)
                end
            elseif _COMP_TYPE and ev_type == _COMP_TYPE then
                if vec_has(ev, 'competitor_hf', hf_id) or vec_has(ev, 'winner_hf', hf_id) then
                    added_ids[ev.id] = true
                    table.insert(results, ev)
                end
            else
                local fields = TYPE_HF_FIELDS[ev_type] or HF_FIELDS
                for _, field in ipairs(fields) do
                    if safe_get(ev, field) == hf_id then
                        added_ids[ev.id] = true
                        table.insert(results, ev)
                        break
                    end
                end
            end
        end

        -- Contextual WAR_FIELD_BATTLE aggregation.
        local direct_count = #results
        for i = 1, direct_count do
            local ev   = results[i]
            local site = safe_get(ev, 'site')
            local year = safe_get(ev, 'year')
            if site and site >= 0 and year and year >= 0 then
                local battles = battle_index[site .. ':' .. year]
                if battles then
                    for _, bev in ipairs(battles) do
                        if not added_ids[bev.id] then
                            added_ids[bev.id] = true
                            table.insert(results, bev)
                        end
                    end
                end
            end
        end
    end
    -- Vague relationship events are in a separate block store; not in world.history.events.
    -- Each block has parallel arrays indexed 0..next_element-1.
    local ok_re, rel_evs = pcall(function()
        return df.global.world.history.relationship_events
    end)
    if ok_re and rel_evs then
        for i = 0, #rel_evs - 1 do
            local ok_b, block = pcall(function() return rel_evs[i] end)
            if not ok_b then break end
            local ok_ne, ne = pcall(function() return block.next_element end)
            if not ok_ne then break end
            for k = 0, ne - 1 do
                -- One pcall covers all four parallel array reads for this element.
                local ok, src, tgt, rtype, yr = pcall(function()
                    return block.source_hf[k], block.target_hf[k],
                           block.relationship[k], block.year[k]
                end)
                if not ok then break end
                if src == hf_id or tgt == hf_id then
                    table.insert(results, {
                        _relationship = true,
                        year      = yr    or -1,
                        source_hf = src   or -1,
                        target_hf = tgt   or -1,
                        rel_type  = rtype or -1,
                    })
                end
            end
        end
    end
    table.sort(results, event_sort_cmp)
    local ctx_map = build_event_to_collection()
    return results, ctx_map
end

-- EventHistory popup ----------------------------------------------------------

local EventHistoryWindow = defclass(EventHistoryWindow, widgets.Window)
EventHistoryWindow.ATTRS {
    frame_title = 'Event History',
    frame       = { w = 76, h = 38 },
    resizable   = false,
    hf_id       = DEFAULT_NIL,
    hf_name     = DEFAULT_NIL,
    entity_id   = DEFAULT_NIL,
    entity_name = DEFAULT_NIL,
}

function EventHistoryWindow:init()
    local is_civ       = (self.entity_id ~= nil)
    local display_name = is_civ and (self.entity_name or '?') or (self.hf_name or '?')
    self.frame_title   = 'Event History: ' .. display_name

    -- w=76, 1-char border each side = 74 interior, l=1 r=1 list padding = 72,
    -- minus 1 for the list cursor glyph = 71 safe width.
    local WRAP_WIDTH = 68
    local function wrap_text(text)
        if #text <= WRAP_WIDTH then return {text} end
        local lines, cur = {}, ''
        for word in text:gmatch('%S+') do
            local candidate = cur == '' and word or (cur .. ' ' .. word)
            if #candidate <= WRAP_WIDTH then
                cur = candidate
            else
                if cur ~= '' then table.insert(lines, cur) end
                cur = word
            end
        end
        if cur ~= '' then table.insert(lines, cur) end
        return #lines > 0 and lines or {text}
    end

    local events, ctx_map
    local focal
    if is_civ then
        events, ctx_map = get_civ_events(self.entity_id)
        focal = self.entity_id  -- civ ID as focal for civ-perspective describers
    else
        events, ctx_map = get_hf_events(self.hf_id)
        focal = self.hf_id
    end

    local event_choices = {}
    for _, ev in ipairs(events) do
        local formatted = format_event(ev, focal, ctx_map, is_civ)
        if formatted then
            local lines = wrap_text(formatted)
            -- All lines for one event share the same search_key so they filter as a group.
            table.insert(event_choices, { text = lines[1], search_key = formatted })
            for i = 2, #lines do
                table.insert(event_choices, { text = '    ' .. lines[i], search_key = formatted })
            end
            table.insert(event_choices, { text = '', search_key = formatted })
        end
    end
    if #event_choices == 0 then
        table.insert(event_choices, { text = 'No events found.' })
    end

    if is_civ then
        print(('[Herald] EventHistory: %s (entity_id=%d) - %d event(s)'):format(
            display_name, self.entity_id or -1, #events))
    else
        print(('[Herald] EventHistory: %s (hf_id=%d) - %d event(s)'):format(
            display_name, self.hf_id or -1, #events))
    end
    -- Detailed per-event dump; gated behind DEBUG.
    if dfhack.reqscript('herald-main').DEBUG then
        local PROBE_FIELDS = {
            'state', 'substate', 'mood', 'reason',
            'site', 'region', 'structure',
            'link_type', 'death_cause',
            'old_job', 'new_job',
            'civ', 'entity_id', 'entity',
            'attacker_civ', 'defender_civ',
            'attacker_general_hf', 'defender_general_hf',
            'position_id', 'assignment_id',
            'artifact_id', 'artifact_record',
            'histfig', 'histfig1', 'histfig2', 'hfid', 'hfid1', 'hfid2',
            'hf', 'hf_target', 'victim_hf', 'slayer_hf',
            'doer', 'target', 'snatcher',
            'seeker_hf',
            'corruptor_hf',
            'changee', 'changer', 'old_race', 'new_race',
            'woundee', 'wounder',
            'builder_hf', 'creator_hfid',
            'maker', 'maker_entity', 'item_type', 'item_subtype',
        }
        for _, ev in ipairs(events) do
            local yr  = (ev.year and ev.year ~= -1) and tostring(ev.year) or '???'
            local fmt = format_event(ev, focal, ctx_map, is_civ)
            if type(ev) == 'table' then
                if ev._collection then
                    -- Collection entry (civ mode).
                    local ok, ctype = pcall(function()
                        return df.history_event_collection_type[ev.col:getType()]
                    end)
                    local ctype_s = (ok and ctype) or '?'
                    local col_id  = safe_get(ev.col, 'id') or '?'
                    print(('  [yr%s] COLLECTION(%s, id=%s) -> %s'):format(
                        yr, ctype_s, tostring(col_id), fmt or '(omitted)'))
                elseif ev._relationship then
                    -- Relationship entry (HF mode).
                    local rtype = ev.rel_type
                    local rname = rtype and rtype >= 0
                        and (df.vague_relationship_type[rtype] or tostring(rtype)):lower():gsub('_', ' ')
                        or '?'
                    print(('  [yr%s] RELATIONSHIP(%s) -> %s'):format(yr, rname, fmt or '(omitted)'))
                end
            else
                local raw = df.history_event_type[ev:getType()] or tostring(ev:getType())
                print(('  [yr%s] %s -> %s'):format(yr, raw, fmt or '(omitted)'))
                local parts = {}
                for _, field in ipairs(PROBE_FIELDS) do
                    local val = safe_get(ev, field)
                    if val ~= nil and val ~= -1 then
                        table.insert(parts, field .. '=' .. tostring(val))
                    end
                end
                if #parts > 0 then
                    print('    fields: ' .. table.concat(parts, ', '))
                end
            end
        end
    end

    self:addviews{
        widgets.Label{
            frame = { t = 0, l = 1 },
            text  = {
                { text = 'Showing events for: ', pen = COLOR_GREY },
                { text = display_name,           pen = COLOR_GREEN },
            },
        },
        widgets.FilteredList{
            view_id   = 'event_list',
            frame     = { t = 2, b = 2, l = 1, r = 1 },
            on_select = function() end,
        },
        widgets.HotkeyLabel{
            frame       = { b = 0, r = 1 },
            key         = 'LEAVESCREEN',
            label       = 'Close',
            auto_width  = true,
            on_activate = function() self.parent_view:dismiss() end,
        },
    }

    self.subviews.event_list:setChoices(event_choices)
end

local EventHistoryScreen = defclass(EventHistoryScreen, gui.ZScreen)
EventHistoryScreen.ATTRS {
    focus_path  = 'herald/event-history',
    hf_id       = DEFAULT_NIL,
    hf_name     = DEFAULT_NIL,
    entity_id   = DEFAULT_NIL,
    entity_name = DEFAULT_NIL,
}

function EventHistoryScreen:init()
    self:addviews{
        EventHistoryWindow{
            hf_id       = self.hf_id,
            hf_name     = self.hf_name,
            entity_id   = self.entity_id,
            entity_name = self.entity_name,
        },
    }
end

function EventHistoryScreen:onDismiss()
    event_history_view = nil
end

-- Exported: opens the Event History popup for an HF.
-- Singleton: same HF raises, different HF/civ replaces.
function open_event_history(hf_id, hf_name)
    if event_history_view then
        if event_history_view.hf_id == hf_id and not event_history_view.entity_id then
            event_history_view:raise()
            return
        end
        event_history_view:dismiss()
        event_history_view = nil
    end
    event_history_view = EventHistoryScreen{ hf_id = hf_id, hf_name = hf_name }:show()
end

-- Exported: opens the Event History popup for a civilisation.
-- Singleton: same entity raises, different entity/HF replaces.
function open_civ_event_history(entity_id, entity_name)
    if event_history_view then
        if event_history_view.entity_id == entity_id then
            event_history_view:raise()
            return
        end
        event_history_view:dismiss()
        event_history_view = nil
    end
    event_history_view = EventHistoryScreen{
        entity_id = entity_id, entity_name = entity_name,
    }:show()
end
