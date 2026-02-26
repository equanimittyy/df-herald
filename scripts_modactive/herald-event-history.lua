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

-- DFHack's __index raises on absent fields for typed structs; use pcall.
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
        local LT     = df.histfig_entity_link_type
        if ltype == LT.POSITION then
            local hf    = hf_id and df.historical_figure.find(hf_id)
            local pos_n = pos_name_for(civ_id, pos_id, hf and hf.sex or -1)
            if pos_n then return 'Became ' .. pos_n .. ' of ' .. ent_n end
        elseif ltype == LT.PRISONER then
            return 'Was imprisoned by ' .. ent_n
        elseif ltype == LT.SLAVE then
            return 'Was enslaved by ' .. ent_n
        elseif ltype == LT.ENEMY then
            return 'Became an enemy of ' .. ent_n
        elseif ltype == LT.MEMBER or ltype == LT.SQUAD then
            return 'Became a member of ' .. ent_n
        elseif ltype == LT.FORMER_MEMBER then
            return 'Became a former member of ' .. ent_n
        end
        local lname = ltype and LT[ltype]
        return 'Joined ' .. ent_n .. (lname and ' (' .. title_case(lname) .. ')' or '')
    end)

    add('REMOVE_HF_ENTITY_LINK', function(ev, focal)
        local hf_id  = safe_get(ev, 'histfig')
        local civ_id = safe_get(ev, 'civ')
        local ltype  = safe_get(ev, 'link_type')
        local pos_id = safe_get(ev, 'position_id')
        local ent_n  = ent_name_by_id(civ_id) or 'an entity'
        local LT     = df.histfig_entity_link_type
        if ltype == LT.POSITION or ltype == LT.SQUAD then
            local hf    = hf_id and df.historical_figure.find(hf_id)
            local pos_n = pos_name_for(civ_id, pos_id, hf and hf.sex or -1)
            if pos_n then return 'Stopped being ' .. pos_n .. ' of ' .. ent_n end
        elseif ltype == LT.PRISONER then
            return 'Escaped from the prisons of ' .. ent_n
        elseif ltype == LT.SLAVE then
            return 'Fled from ' .. ent_n
        elseif ltype == LT.ENEMY then
            return 'Stopped being an enemy of ' .. ent_n
        end
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
        return 'stored an artifact' .. (site_n and (' in ' .. site_n) or '')
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

    -- competitor_hf / winner_hf are stl-vectors; iterated in get_hf_events.
    add('COMPETITION', function(ev, focal)
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        local loc    = site_n and (' in ' .. site_n) or ''
        local ok_w, wlist = pcall(function() return ev.winner_hf end)
        if ok_w and wlist then
            local ok_n, n = pcall(function() return #wlist end)
            if ok_n then
                for i = 0, n - 1 do
                    local ok2, v = pcall(function() return wlist[i] end)
                    if ok2 and v == focal then
                        return 'Won a competition' .. loc
                    end
                end
            end
        end
        local ok_c, clist = pcall(function() return ev.competitor_hf end)
        if ok_c and clist then
            local ok_n, n = pcall(function() return #clist end)
            if ok_n then
                for i = 0, n - 1 do
                    local ok2, v = pcall(function() return clist[i] end)
                    if ok2 and v == focal then
                        return 'Competed in a competition' .. loc
                    end
                end
            end
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
        local loc     = site_n and (' on ' .. site_n) or ' on a site'
        if focal == att_hf then
            local vs = def_civ and (' against ' .. def_civ) or ''
            return 'Attacked' .. loc .. vs
        end
        local att = hf_name_by_id(att_hf) or 'someone'
        return att .. ' attacked' .. loc
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
        return 'Created an artifact' .. loc
    end)

    add('CREATED_SITE', function(ev, focal)
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        if site_n then return 'Constructed ' .. site_n end
        return 'Constructed a settlement'
    end)

    local function created_structure_fn(ev, focal)
        local site_n = site_name_by_id(safe_get(ev, 'site'))
        local loc    = site_n and (' in ' .. site_n) or ''
        return 'Constructed a structure' .. loc
    end
    add('CREATED_BUILDING',  created_structure_fn)
    add('CREATED_STRUCTURE', created_structure_fn)
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
local function format_event(ev, focal_hf_id)
    -- Synthetic relationship events from world.history.relationship_events.
    if type(ev) == 'table' then
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
    return ('In the year %s, %s'):format(year, desc:sub(1,1):lower() .. desc:sub(2))
end

-- Returns true if any element of a stl-vector field on ev equals hf_id.
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
local _TYPE_HF_FIELDS = {}
do
    local function map(name, fields)
        local v = df.history_event_type[name]
        if v ~= nil then _TYPE_HF_FIELDS[v] = fields end
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
end

-- TODO: battle participation events are not yet showing in HF event history.
-- The two approaches below (BATTLE_TYPES vector check and contextual WAR_FIELD_BATTLE
-- aggregation) are implemented but not confirmed working; needs in-game verification.
local function get_hf_events(hf_id)
    local results      = {}
    local battle_index = {}  -- { ['site:year'] = { ev, ... } }
    local added_ids    = {}  -- event.id -> true; prevents duplicates

    -- Single pass: collect direct HF events and build WAR_FIELD_BATTLE index.
    for _, ev in ipairs(df.global.world.history.events) do
        local ev_type = ev:getType()

        -- Battle index for contextual aggregation (step 2).
        if _WAR_BATTLE_TYPE and ev_type == _WAR_BATTLE_TYPE then
            local site = safe_get(ev, 'site')
            local year = safe_get(ev, 'year')
            if site and site >= 0 and year and year >= 0 then
                local key = site .. ':' .. year
                if not battle_index[key] then battle_index[key] = {} end
                table.insert(battle_index[key], ev)
            end
        end

        -- HF matching: vector check for battle/competition, scalar dispatch for others.
        if _BATTLE_TYPES[ev_type] then
            -- HF_SIMPLE_BATTLE_EVENT: participants in group1/group2 vectors.
            if vec_has(ev, 'group1', hf_id) or vec_has(ev, 'group2', hf_id) then
                added_ids[ev.id] = true
                table.insert(results, ev)
            end
        elseif _COMP_TYPE and ev_type == _COMP_TYPE then
            -- COMPETITION: competitor_hf and winner_hf are vectors.
            if vec_has(ev, 'competitor_hf', hf_id) or vec_has(ev, 'winner_hf', hf_id) then
                added_ids[ev.id] = true
                table.insert(results, ev)
            end
        else
            -- Scalar check: use type-specific fields if known, full HF_FIELDS otherwise.
            local fields = _TYPE_HF_FIELDS[ev_type] or HF_FIELDS
            for _, field in ipairs(fields) do
                if safe_get(ev, field) == hf_id then
                    added_ids[ev.id] = true
                    table.insert(results, ev)
                    break
                end
            end
        end
    end

    -- Step 2: contextual WAR_FIELD_BATTLE aggregation.
    -- If a direct HF event (death, abduction, etc.) shares site+year with a battle,
    -- include the battle. Only iterates direct results to avoid chaining.
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
    table.sort(results, function(a, b)
        local ya, yb = (a.year or -1), (b.year or -1)
        if ya ~= yb then return ya < yb end
        local sa = safe_get(a, 'seconds') or -1
        local sb = safe_get(b, 'seconds') or -1
        if sa ~= sb then return sa < sb end
        local ia = safe_get(a, 'id') or -1
        local ib = safe_get(b, 'id') or -1
        return ia < ib
    end)
    return results
end

-- EventHistory popup ----------------------------------------------------------

local EventHistoryWindow = defclass(EventHistoryWindow, widgets.Window)
EventHistoryWindow.ATTRS {
    frame_title = 'Event History',
    frame       = { w = 76, h = 38 },
    resizable   = false,
    hf_id       = DEFAULT_NIL,
    hf_name     = DEFAULT_NIL,
}

function EventHistoryWindow:init()
    local hf_name = self.hf_name or '?'
    self.frame_title = 'Event History: ' .. hf_name

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

    local events = get_hf_events(self.hf_id)
    local event_choices = {}
    for _, ev in ipairs(events) do
        local formatted = format_event(ev, self.hf_id)
        if formatted then
            local lines = wrap_text(formatted)
            table.insert(event_choices, { text = lines[1] })
            for i = 2, #lines do
                table.insert(event_choices, { text = '    ' .. lines[i] })
            end
        end
    end
    if #event_choices == 0 then
        table.insert(event_choices, { text = 'No events found.' })
    end

    -- Always dump events to the DFHack console when the popup opens (not gated by DEBUG).
    -- Useful for mapping new event types; PROBE_FIELDS lists all known scalar fields.
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
    print(('[Herald] EventHistory: %s (hf_id=%d) - %d event(s)'):format(
        hf_name, self.hf_id or -1, #events))
    for _, ev in ipairs(events) do
        local yr  = (ev.year and ev.year ~= -1) and tostring(ev.year) or '???'
        local fmt = format_event(ev, self.hf_id)
        if type(ev) == 'table' then
            local rtype = ev.rel_type
            local rname = rtype and rtype >= 0
                and (df.vague_relationship_type[rtype] or tostring(rtype)):lower():gsub('_', ' ')
                or '?'
            print(('  [yr%s] RELATIONSHIP(%s) -> %s'):format(yr, rname, fmt or '(omitted)'))
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

    self:addviews{
        widgets.Label{
            frame = { t = 0, l = 1 },
            text  = {
                { text = 'Showing events for: ', pen = COLOR_GREY },
                { text = hf_name,               pen = COLOR_GREEN },
            },
        },
        widgets.List{
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
    focus_path = 'herald/event-history',
    hf_id      = DEFAULT_NIL,
    hf_name    = DEFAULT_NIL,
}

function EventHistoryScreen:init()
    self:addviews{
        EventHistoryWindow{
            hf_id   = self.hf_id,
            hf_name = self.hf_name,
        },
    }
end

function EventHistoryScreen:onDismiss()
    event_history_view = nil
end

-- Exported: opens the Event History popup for hf_id.
-- If a window is already open for the same HF, raises it; if for a different HF, replaces it.
function open_event_history(hf_id, hf_name)
    if event_history_view then
        if event_history_view.hf_id == hf_id then
            event_history_view:raise()
            return
        end
        event_history_view:dismiss()
        event_history_view = nil
    end
    event_history_view = EventHistoryScreen{ hf_id = hf_id, hf_name = hf_name }:show()
end
