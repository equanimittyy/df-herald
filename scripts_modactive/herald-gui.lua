--@ module=true

--[====[
herald-gui
==========
Tags: fort | gameplay

  Settings UI for the Herald mod. Tabbed window for managing pinned historical
  figures and civilisations, configuring per-pin announcements, and browsing
  world-history event logs.

  Open with:

    herald-main gui

  Navigation
  ----------
  Ctrl-T     Cycle tabs forward / backward
  Ctrl-J              Open the DFHack Journal
  Escape              Close the window

  Tab 1 - Pinned
  --------------
  Left pane: pinned individuals or civilisations (Ctrl-I to toggle view).
  Right pane: per-pin announcement toggles; changes are saved immediately.
  Categories marked "*" are not yet implemented.

  Ctrl-I              Toggle between Individuals and Civilisations view
  Ctrl-E              Open event history for the selected individual
  Enter               Unpin the selected entry

  Tab 2 - Historical Figures
  --------------------------
  Searchable list of all historical figures. Columns: Name, Race, Civ, Status,
  Events. Detail pane shows ID, race, alive/dead status, civ, and positions.

  Type to search      Filter by name, race, or civilisation
  Enter               Pin or unpin the selected figure
  Ctrl-E              Open event history for the selected figure
  Ctrl-P              Toggle "Pinned only" filter
  Ctrl-D              Toggle "Show dead" filter

  Tab 3 - Civilisations
  ---------------------
  Searchable list of all civilisation-level entities.
  Columns: Name, Race, Sites, Pop (alive HF members).

  Type to search      Filter by name or race
  Enter               Pin or unpin the selected civilisation
  Ctrl-P              Toggle "Pinned only" filter

  Event History Popup
  -------------------
  Chronological list of world-history events involving a figure. Opened via
  Ctrl-E from the Pinned or Historical Figures tab. Also dumps the event list
  to the DFHack console for debugging.

Not intended for direct use.
]====]

local gui       = require('gui')
local widgets   = require('gui.widgets')
local ind_death = dfhack.reqscript('herald-ind-death')
local wld_leaders = dfhack.reqscript('herald-world-leaders')

view = nil                  -- module-level; prevents double-open
local event_history_view = nil  -- prevents double-open for the event history popup
local open_event_history        -- forward declaration; defined near EventHistoryScreen

-- Helpers ----------------------------------------------------------------------

local function get_race_name(hf)
    if not hf or hf.race < 0 then return '?' end
    local cr = df.creature_raw.find(hf.race)
    if not cr then return '?' end
    return cr.name[0] or '?'
end

local function get_entity_race_name(entity)
    if not entity or entity.race < 0 then return '?' end
    local cr = df.creature_raw.find(entity.race)
    if not cr then return '?' end
    return cr.name[0] or '?'
end

local function get_civ_name(hf)
    for _, link in ipairs(hf.entity_links) do
        if link:getType() == df.histfig_entity_link_type.MEMBER then
            local ent = df.historical_entity.find(link.entity_id)
            if ent and ent.type == df.historical_entity_type.Civilization then
                return dfhack.translation.translateName(ent.name, true)
            end
        end
    end
    return ''
end

-- Normalises a position name field: entity_position_raw uses string[] (name[0]),
-- entity_position (entity.positions.own) uses plain stl-string.
local function name_str(field)
    if not field then return nil end
    if type(field) == 'string' then return field ~= '' and field or nil end
    local s = field[0]
    return (s and s ~= '') and s or nil
end

-- Returns the name of the SiteGovernment entity the hf is a member of, or nil.
local function get_site_gov(hf)
    for _, link in ipairs(hf.entity_links) do
        if link:getType() == df.histfig_entity_link_type.MEMBER then
            local ent = df.historical_entity.find(link.entity_id)
            if ent and ent.type == df.historical_entity_type.SiteGovernment then
                return dfhack.translation.translateName(ent.name, true)
            end
        end
    end
    return nil
end

-- Returns { {pos_name, civ_name}, ... } for all position links of hf.
local function get_positions(hf)
    local results = {}
    for _, link in ipairs(hf.entity_links) do
        if link:getType() == df.histfig_entity_link_type.POSITION then
            local entity = df.historical_entity.find(link.entity_id)
            if entity then
                local civ_name = dfhack.translation.translateName(entity.name, true)
                for _, asgn in ipairs(entity.positions.assignments) do
                    if asgn.histfig2 == hf.id then
                        local pos_id   = asgn.position_id
                        local pos_name = nil
                        -- entity.positions.own is entity-specific; check it first so that
                        -- nomadic/special groups show their actual title (e.g. "leader")
                        -- rather than the generic one from the shared entity_raw ("king").
                        if entity.positions and entity.positions.own then
                            for _, pos in ipairs(entity.positions.own) do
                                if pos.id == pos_id then
                                    local gendered = hf.sex == 1
                                        and name_str(pos.name_male)
                                        or  name_str(pos.name_female)
                                    pos_name = gendered or name_str(pos.name)
                                    break
                                end
                            end
                        end
                        if not pos_name and entity.entity_raw then
                            for _, pos in ipairs(entity.entity_raw.positions) do
                                if pos.id == pos_id then
                                    local gendered = hf.sex == 1
                                        and name_str(pos.name_male)
                                        or  name_str(pos.name_female)
                                    pos_name = gendered or name_str(pos.name)
                                    break
                                end
                            end
                        end
                        table.insert(results, { pos_name = pos_name, civ_name = civ_name })
                    end
                end
            end
        end
    end
    return results
end

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
local HF_FIELDS = {
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
local function safe_get(obj, field)
    local ok, val = pcall(function() return obj[field] end)
    return ok and val or nil
end

-- Cached event counts: { [hf_id] = count }. Built once per module load.
local hf_event_counts_cache = nil
-- Forward declaration; assigned after EVENT_DESCRIBE is populated.
local event_will_be_shown

local function build_hf_event_counts()
    if hf_event_counts_cache then return hf_event_counts_cache end
    local counts = {}
    local BATTLE_TYPES = {}
    for _, name in ipairs({'HF_SIMPLE_BATTLE_EVENT', 'HIST_FIGURE_SIMPLE_BATTLE_EVENT'}) do
        local v = df.history_event_type[name]
        if v ~= nil then BATTLE_TYPES[v] = true end
    end
    local COMP_TYPE = df.history_event_type['COMPETITION']

    local function count_vec(ev, field, seen)
        local ok, vec = pcall(function() return ev[field] end)
        if not ok or not vec then return end
        local ok2, n = pcall(function() return #vec end)
        if not ok2 then return end
        for i = 0, n - 1 do
            local ok3, v = pcall(function() return vec[i] end)
            if ok3 and type(v) == 'number' and v >= 0 and not seen[v] then
                seen[v] = true
                counts[v] = (counts[v] or 0) + 1
            end
        end
    end

    for _, ev in ipairs(df.global.world.history.events) do
        if event_will_be_shown and not event_will_be_shown(ev) then goto skip_ev end
        local seen = {}
        for _, field in ipairs(HF_FIELDS) do
            local val = safe_get(ev, field)
            if type(val) == 'number' and val >= 0 and not seen[val] then
                seen[val] = true
                counts[val] = (counts[val] or 0) + 1
            end
        end
        -- HF_SIMPLE_BATTLE_EVENT: participants in group1/group2 vectors.
        if BATTLE_TYPES[ev:getType()] then
            count_vec(ev, 'group1', seen)
            count_vec(ev, 'group2', seen)
        end
        -- COMPETITION: competitor_hf and winner_hf vectors.
        if COMP_TYPE and ev:getType() == COMP_TYPE then
            count_vec(ev, 'competitor_hf', seen)
            count_vec(ev, 'winner_hf', seen)
        end
        ::skip_ev::
    end
    -- Also count vague relationship events; these live in a separate block store,
    -- not in world.history.events (hence why they appear in legends_plus.xml only).
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
                local ok_s, src = pcall(function() return block.source_hf[k] end)
                local ok_t, tgt = pcall(function() return block.target_hf[k] end)
                if ok_s and type(src) == 'number' and src >= 0 then
                    counts[src] = (counts[src] or 0) + 1
                end
                if ok_t and type(tgt) == 'number' and tgt >= 0 then
                    counts[tgt] = (counts[tgt] or 0) + 1
                end
            end
        end
    end
    hf_event_counts_cache = counts
    return counts
end

-- Build the choice list for the Figures FilteredList.
-- Column widths: Name=22, Race=12, Civ=20, Status=7, Events=remaining
local function build_choices(show_dead, show_pinned_only)
    local choices = {}
    local pinned = ind_death.get_pinned()
    local event_counts = build_hf_event_counts()
    for _, hf in ipairs(df.global.world.history.figures) do
        local is_dead = hf.died_year ~= -1
        if is_dead and not show_dead then goto continue end
        if show_pinned_only and not pinned[hf.id] then goto continue end

        local name     = dfhack.translation.translateName(hf.name, true)
        if name == '' then name = '(unnamed)' end
        local race     = get_race_name(hf)
        if race == '?' then race = 'Unknown' end
        local civ_full = get_civ_name(hf)
        local is_pinned = pinned[hf.id]

        local name_col = name:sub(1, 22)
        local race_col = race:sub(1, 12)
        local civ_col  = civ_full:sub(1, 20)

        local status_token
        if is_dead then
            status_token = { text = ('%-7s'):format('dead'),   pen = COLOR_RED }
        else
            status_token = { text = ('%-7s'):format(is_pinned and 'pinned' or ''), pen = COLOR_GREEN }
        end

        local ev_count   = event_counts[hf.id] or 0
        local search_key = (name .. ' ' .. race .. ' ' .. civ_full):lower()

        table.insert(choices, {
            text       = {
                { text = ('%-22s'):format(name_col), pen = is_dead and COLOR_GREY or nil },
                { text = ('%-12s'):format(race_col), pen = COLOR_GREY },
                { text = ('%-20s'):format(civ_col),  pen = COLOR_GREY },
                status_token,
                { text = tostring(ev_count),         pen = COLOR_GREY },
            },
            search_key   = search_key,
            hf_id        = hf.id,
            hf           = hf,
            is_dead      = is_dead,
            display_name = name,
        })

        ::continue::
    end
    return choices
end

-- Build the choice list for the Civilisations FilteredList.
-- Column widths: Name=26, Race=13, Sites=6, Pop=6, Status=remaining
local function build_civ_choices(show_pinned_only)
    -- Single pass: count alive HF members per entity
    local alive_counts = {}
    for _, hf in ipairs(df.global.world.history.figures) do
        if hf.died_year == -1 then
            for _, link in ipairs(hf.entity_links) do
                if link:getType() == df.histfig_entity_link_type.MEMBER then
                    local eid = link.entity_id
                    alive_counts[eid] = (alive_counts[eid] or 0) + 1
                end
            end
        end
    end

    local choices = {}
    local pinned = wld_leaders.get_pinned_civs()
    for _, entity in ipairs(df.global.world.entities.all) do
        if entity.type ~= df.historical_entity_type.Civilization then goto continue end

        local entity_id = entity.id
        local is_pinned = pinned[entity_id]
        if show_pinned_only and not is_pinned then goto continue end

        local name = dfhack.translation.translateName(entity.name, true)
        if name == '' then goto continue end

        local race = get_entity_race_name(entity)
        if race == '?' then race = 'Unknown' end

        local site_count = entity.site_links and #entity.site_links or 0
        local pop_count  = alive_counts[entity_id] or 0

        local status_token = is_pinned
            and { text = 'pinned', pen = COLOR_GREEN }
            or  { text = '',       pen = nil }

        table.insert(choices, {
            text = {
                { text = ('%-26s'):format(name:sub(1, 26)), pen = nil },
                { text = ('%-13s'):format(race:sub(1, 12)), pen = COLOR_GREY },
                { text = ('%5d '):format(site_count),       pen = COLOR_GREY },
                { text = ('%5d '):format(pop_count),        pen = COLOR_GREY },
                status_token,
            },
            search_key   = (name .. ' ' .. race):lower(),
            entity_id    = entity_id,
            entity       = entity,
            display_name = name,
        })

        ::continue::
    end
    return choices
end

-- FiguresPanel -----------------------------------------------------------------

local FiguresPanel = defclass(FiguresPanel, widgets.Panel)
FiguresPanel.ATTRS {
    frame = { t = 2, b = 1 },
}

function FiguresPanel:init()
    self.show_dead       = false
    self.show_pinned_only = false

    self:addviews{
        widgets.Label{
            frame = { t = 0, l = 1 },
            text  = {
                { text = ('%-22s'):format('Name'),   pen = COLOR_GREY },
                { text = ('%-12s'):format('Race'),   pen = COLOR_GREY },
                { text = ('%-20s'):format('Civ'),    pen = COLOR_GREY },
                { text = ('%-7s'):format('Status'),  pen = COLOR_GREY },
                { text = 'Events',                   pen = COLOR_GREY },
            },
        },
        widgets.FilteredList{
            view_id   = 'fig_list',
            frame     = { t = 1, b = 13, l = 1, r = 1 },
            on_select = function(idx, choice) self:update_detail(choice) end,
        },
        widgets.Label{
            frame = { t = 27, l = 0, r = 0, h = 1 },
            text  = { { text = string.rep('\xc4', 74), pen = COLOR_GREY } },
        },
        widgets.List{
            view_id   = 'detail_panel',
            frame     = { t = 28, b = 2, l = 1, r = 1 },
            on_select = function() end,
        },
        widgets.HotkeyLabel{
            frame       = { b = 0, l = 1 },
            key         = 'SELECT',
            label       = 'Pin/Unpin',
            auto_width  = true,
            on_activate = function()
                local fl = self.subviews.fig_list
                local idx, choice = fl:getSelected()
                if choice then self:toggle_pinned(choice) end
            end,
        },
        widgets.HotkeyLabel{
            frame       = { b = 0, l = 22 },
            key         = 'CUSTOM_CTRL_E',
            label       = 'Event History',
            auto_width  = true,
            on_activate = function()
                local _, choice = self.subviews.fig_list:getSelected()
                if choice then open_event_history(choice.hf_id, choice.display_name) end
            end,
        },
        widgets.HotkeyLabel{
            view_id     = 'toggle_pinned_btn',
            frame       = { b = 1, l = 1 },
            key         = 'CUSTOM_CTRL_P',
            label       = function()
                return 'Pinned only: ' .. (self.show_pinned_only and 'Yes' or 'No ')
            end,
            auto_width  = true,
            on_activate = function() self:toggle_pinned_only() end,
        },
        widgets.HotkeyLabel{
            view_id     = 'toggle_dead_btn',
            frame       = { b = 1, l = 35 },
            key         = 'CUSTOM_CTRL_D',
            label       = function()
                return 'Show dead: ' .. (self.show_dead and 'Yes' or 'No ')
            end,
            auto_width  = true,
            on_activate = function() self:toggle_dead() end,
        },
    }

    self:refresh_list()

    local fl  = self.subviews.fig_list
    local pan = self
    local _orig_ofc = fl.onFilterChange
    fl.onFilterChange = function(this, text, pos)
        _orig_ofc(this, text, pos)
        local _, choice = this:getSelected()
        pan:update_detail(choice)
    end
end

function FiguresPanel:onInput(keys)
    if keys.CUSTOM_CTRL_E then
        local _, choice = self.subviews.fig_list:getSelected()
        if choice then open_event_history(choice.hf_id, choice.display_name) end
        return true
    end
    if keys.CUSTOM_CTRL_D then
        self:toggle_dead()
        return true
    end
    if keys.CUSTOM_CTRL_P then
        self:toggle_pinned_only()
        return true
    end
    if self.subviews.fig_list:onInput(keys) then return true end
    return FiguresPanel.super.onInput(self, keys)
end

function FiguresPanel:refresh_list()
    local choices = build_choices(self.show_dead, self.show_pinned_only)
    self.subviews.fig_list:setChoices(choices)
    local _, choice = self.subviews.fig_list:getSelected()
    self:update_detail(choice)
end

function FiguresPanel:update_detail(choice)
    if not choice then
        self.subviews.detail_panel:setChoices({})
        return
    end

    local hf      = choice.hf
    local hf_id   = choice.hf_id
    local pinned  = ind_death.get_pinned()
    local name    = dfhack.translation.translateName(hf.name, true)
    if name == '' then name = '(unnamed)' end
    local race    = get_race_name(hf)
    if race == '?' then race = 'Unknown' end
    local civ       = get_civ_name(hf)
    local gov       = get_site_gov(hf)
    local is_pinned = pinned[hf_id] and 'Yes' or 'No'
    local alive     = hf.died_year == -1 and 'Alive' or 'Dead'

    local rows = {
        { text = {
            { text = 'ID: ',        pen = COLOR_GREY },
            { text = tostring(hf_id) },
            { text = '   Race: ',   pen = COLOR_GREY },
            { text = race },
            { text = '   Status: ', pen = COLOR_GREY },
            { text = alive, pen = hf.died_year == -1 and COLOR_GREEN or COLOR_RED },
        }},
        { text = {
            { text = 'Pinned: ', pen = COLOR_GREY },
            { text = is_pinned, pen = pinned[hf_id] and COLOR_GREEN or COLOR_WHITE },
        }},
        { text = {
            { text = 'Civ: ',     pen = COLOR_GREY },
            { text = civ ~= '' and civ or 'None' },
        }},
        { text = {
            { text = 'Site Gov: ', pen = COLOR_GREY },
            { text = gov or 'None' },
        }},
        { text = { { text = 'Positions:', pen = COLOR_GREY } } },
    }

    local positions = get_positions(hf)
    if #positions == 0 then
        table.insert(rows, { text = { { text = '  None', pen = COLOR_GREY } } })
    else
        for _, p in ipairs(positions) do
            local label = '  ' .. (p.pos_name or '(unnamed)') .. ' of ' .. p.civ_name
            table.insert(rows, { text = { { text = label } } })
        end
    end

    self.subviews.detail_panel:setChoices(rows)
end

function FiguresPanel:toggle_pinned(choice)
    if not choice then return end
    local hf_id    = choice.hf_id
    local pinned   = ind_death.get_pinned()
    local now_pinned = not pinned[hf_id]
    ind_death.set_pinned(hf_id, now_pinned or nil)
    local name = dfhack.translation.translateName(choice.hf.name, true)
    if name == '' then name = '(unnamed)' end
    print(('[Herald] %s (id %d) is %s pinned.'):format(
        name, hf_id, now_pinned and 'now' or 'no longer'))
    self:update_detail(choice)
    local fl = self.subviews.fig_list
    local filter_text = fl.edit.text
    self:refresh_list()
    fl:setFilter(filter_text)
    self.parent_view.subviews.pinned_panel:refresh_pinned_list()
end

function FiguresPanel:toggle_dead()
    self.show_dead = not self.show_dead
    self:refresh_list()
end

function FiguresPanel:toggle_pinned_only()
    self.show_pinned_only = not self.show_pinned_only
    self:refresh_list()
end

-- PinnedPanel ------------------------------------------------------------------

local INDIVIDUALS_ANN = {
    { key = 'death',     label = 'Death',     impl = true  },
    { key = 'marriage',  label = 'Marriage',  impl = false },
    { key = 'children',  label = 'Children',  impl = false },
    { key = 'migration', label = 'Migration', impl = false },
    { key = 'legendary', label = 'Legendary', impl = false },
    { key = 'combat',    label = 'Combat',    impl = false },
}

local CIVILISATIONS_ANN = {
    { key = 'positions',   label = 'Positions',   impl = true  },
    { key = 'diplomacy',   label = 'Diplomacy',   impl = false },
    { key = 'raids',       label = 'Raids',       impl = false },
    { key = 'theft',       label = 'Theft',       impl = false },
    { key = 'kidnappings', label = 'Kidnappings', impl = false },
    { key = 'armies',      label = 'Armies',      impl = false },
}

local PinnedPanel = defclass(PinnedPanel, widgets.Panel)
PinnedPanel.ATTRS {
    frame = { t = 2, b = 1 },
}

function PinnedPanel:init()
    -- 'individuals' or 'civilisations'
    self.view_type  = 'individuals'
    self.selected_id = nil  -- hf_id or entity_id of currently selected pin

    -- Builds ToggleHotkeyLabel widgets for an announcement category.
    -- on_change writes the new value to the selected pin's settings.
    local function make_toggle_views(entries, category)
        local views = {}
        for i, entry in ipairs(entries) do
            local e = entry  -- capture loop variable
            local display_label = e.impl and e.label or (e.label .. ' *')
            table.insert(views, widgets.ToggleHotkeyLabel{
                view_id        = 'toggle_' .. e.key,
                frame          = { t = i, h = 1, l = 0, r = 0 },
                label          = display_label,
                initial_option = 2,  -- off until a pin is selected
                on_change      = e.impl and function(new_val)
                    if not self.selected_id then return end
                    if self.view_type == 'individuals' then
                        ind_death.set_pin_setting(self.selected_id, e.key, new_val)
                    else
                        wld_leaders.set_civ_pin_setting(self.selected_id, e.key, new_val)
                    end
                end or function() end,
            })
        end
        return views
    end

    -- Announcement panel for individuals (visible by default)
    local ann_ind = widgets.Panel{
        view_id = 'ann_panel_individuals',
        frame   = { t = 3, b = 1, l = 50, r = 1 },
        visible = true,
    }
    ann_ind:addviews{
        widgets.Label{
            view_id = 'pin_name_label_ind',
            frame   = { t = 0, h = 1, l = 0, r = 0 },
            text    = { { text = '(none selected)', pen = COLOR_GREY } },
        },
    }
    ann_ind:addviews(make_toggle_views(INDIVIDUALS_ANN, 'individuals'))

    -- Announcement panel for civilisations (hidden initially)
    local ann_civ = widgets.Panel{
        view_id = 'ann_panel_civilisations',
        frame   = { t = 3, b = 1, l = 50, r = 1 },
        visible = false,
    }
    ann_civ:addviews{
        widgets.Label{
            view_id = 'pin_name_label_civ',
            frame   = { t = 0, h = 1, l = 0, r = 0 },
            text    = { { text = '(none selected)', pen = COLOR_GREY } },
        },
    }
    ann_civ:addviews(make_toggle_views(CIVILISATIONS_ANN, 'civilisations'))

    self:addviews{
        -- Type toggle
        widgets.CycleHotkeyLabel{
            view_id = 'type_toggle',
            frame   = { t = 0, l = 1 },
            key     = 'CUSTOM_CTRL_I',
            label   = 'View: ',
            options = { 'Individuals', 'Civilisations' },
            on_change = function(new_val)
                self:on_type_change(new_val)
            end,
        },
        -- Column headers
        widgets.Label{
            view_id = 'list_header',
            frame   = { t = 1, l = 1, r = 25 },
            text    = {
                { text = ('%-20s'):format('Name'),  pen = COLOR_GREY },
                { text = ('%-12s'):format('Race'),  pen = COLOR_GREY },
                { text = 'Status',                  pen = COLOR_GREY },
            },
        },
        widgets.Label{
            frame = { t = 1, l = 50 },
            text  = { { text = 'Announcements', pen = COLOR_GREY } },
        },
        -- Full-width separator
        widgets.Label{
            frame = { t = 2, l = 0, r = 0, h = 1 },
            text  = { { text = string.rep('\xc4', 74), pen = COLOR_GREY } },
        },
        -- Pinned figure / civ list
        widgets.List{
            view_id   = 'pinned_list',
            frame     = { t = 3, b = 1, l = 1, r = 25 },
            on_select = function(idx, choice) self:on_pin_select(idx, choice) end,
        },
        -- Announcement panels
        ann_ind,
        ann_civ,
        -- Footer
        widgets.HotkeyLabel{
            frame       = { b = 0, l = 1 },
            key         = 'SELECT',
            label       = 'Unpin',
            auto_width  = true,
            on_activate = function() self:unpin_selected() end,
        },
        widgets.HotkeyLabel{
            view_id     = 'event_history_btn',
            frame       = { b = 0, l = 22 },
            key         = 'CUSTOM_CTRL_E',
            label       = 'Event History',
            auto_width  = true,
            visible     = true,   -- individuals mode is the default
            on_activate = function()
                local _, choice = self.subviews.pinned_list:getSelected()
                if choice and choice.hf_id then
                    open_event_history(choice.hf_id, choice.display_name)
                end
            end,
        },
        widgets.Label{
            frame = { b = 0, l = 48 },
            text  = { { text = '* = not yet implemented', pen = COLOR_GREY } },
        },
    }

    self:refresh_pinned_list()
end

function PinnedPanel:onInput(keys)
    if keys.CUSTOM_CTRL_E and self.view_type == 'individuals' then
        local _, choice = self.subviews.pinned_list:getSelected()
        if choice and choice.hf_id then
            open_event_history(choice.hf_id, choice.display_name)
        end
        return true
    end
    return PinnedPanel.super.onInput(self, keys)
end

-- Called when the user navigates the pinned list.
function PinnedPanel:on_pin_select(idx, choice)
    if not choice then
        self.selected_id = nil
        self:_update_right_panel(nil, nil)
        return
    end
    if self.view_type == 'individuals' then
        self.selected_id = choice.hf_id
    else
        self.selected_id = choice.entity_id
    end
    self:_update_right_panel(choice.display_name, self.selected_id)
end

-- Updates the name label and toggle option_idx values for the active ann panel.
function PinnedPanel:_update_right_panel(name, pin_id)
    local is_ind   = (self.view_type == 'individuals')
    local label_id = is_ind and 'pin_name_label_ind' or 'pin_name_label_civ'
    local panel_id = is_ind and 'ann_panel_individuals' or 'ann_panel_civilisations'
    local panel    = self.subviews[panel_id]
    local entries  = is_ind and INDIVIDUALS_ANN or CIVILISATIONS_ANN

    -- Update name label (must use setText to invalidate the render cache)
    panel.subviews[label_id]:setText(
        name and { { text = name, pen = COLOR_GREEN } }
             or  { { text = '(none selected)', pen = COLOR_GREY } }
    )

    -- Update toggle option_idx values
    local settings = nil
    if pin_id then
        settings = is_ind and ind_death.get_pin_settings(pin_id)
                           or wld_leaders.get_civ_pin_settings(pin_id)
    end
    for _, e in ipairs(entries) do
        local t = panel.subviews['toggle_' .. e.key]
        if t then
            t.option_idx = (settings and settings[e.key] == true) and 1 or 2
        end
    end
end

function PinnedPanel:on_type_change(new_val)
    local is_ind = (new_val == 'Individuals')
    self.view_type = is_ind and 'individuals' or 'civilisations'
    self.subviews.ann_panel_individuals.visible   = is_ind
    self.subviews.ann_panel_civilisations.visible = not is_ind
    self.subviews.event_history_btn.visible       = is_ind

    -- Update column header to match view type
    local list_header = self.subviews.list_header
    if is_ind then
        list_header:setText({
            { text = ('%-20s'):format('Name'),  pen = COLOR_GREY },
            { text = ('%-12s'):format('Race'),  pen = COLOR_GREY },
            { text = 'Status',                  pen = COLOR_GREY },
        })
    else
        list_header:setText({
            { text = ('%-30s'):format('Name'),  pen = COLOR_GREY },
            { text = 'Race',                    pen = COLOR_GREY },
        })
    end

    -- refresh_pinned_list auto-selects first item and calls _update_right_panel
    self:refresh_pinned_list()
end

function PinnedPanel:refresh_pinned_list()
    local choices = {}
    if self.view_type == 'individuals' then
        local pinned = ind_death.get_pinned()
        local hf_list = {}
        for hf_id in pairs(pinned) do
            local hf = df.historical_figure.find(hf_id)
            if hf then table.insert(hf_list, hf) end
        end
        table.sort(hf_list, function(a, b)
            local na = dfhack.translation.translateName(a.name, true)
            local nb = dfhack.translation.translateName(b.name, true)
            return na < nb
        end)
        for _, hf in ipairs(hf_list) do
            local is_dead = hf.died_year ~= -1
            local name    = dfhack.translation.translateName(hf.name, true)
            if name == '' then name = '(unnamed)' end
            local race    = get_race_name(hf)
            if race == '?' then race = 'Unknown' end
            local status_token = is_dead
                and { text = 'dead', pen = COLOR_RED }
                or  { text = '',     pen = COLOR_GREEN }
            table.insert(choices, {
                text = {
                    { text = ('%-20s'):format(name:sub(1,20)), pen = is_dead and COLOR_GREY or nil },
                    { text = ('%-12s'):format(race:sub(1,12)), pen = COLOR_GREY },
                    status_token,
                },
                hf_id        = hf.id,
                display_name = name,
            })
        end
        if #choices == 0 then
            table.insert(choices, { text = { { text = 'No pinned individuals', pen = COLOR_GREY } } })
        end
    else
        local pinned_civs = wld_leaders.get_pinned_civs()
        local civ_list = {}
        for entity_id in pairs(pinned_civs) do
            local entity = df.historical_entity.find(entity_id)
            if entity then
                local name = dfhack.translation.translateName(entity.name, true)
                if name == '' then name = '(unnamed)' end
                table.insert(civ_list, { entity_id = entity_id, name = name, entity = entity })
            end
        end
        table.sort(civ_list, function(a, b) return a.name < b.name end)
        for _, civ in ipairs(civ_list) do
            local race = get_entity_race_name(civ.entity)
            if race == '?' then race = 'Unknown' end
            table.insert(choices, {
                text = {
                    { text = ('%-30s'):format(civ.name:sub(1, 30)), pen = nil },
                    { text = ('%-16s'):format(race:sub(1, 16)),      pen = COLOR_GREY },
                },
                entity_id    = civ.entity_id,
                display_name = civ.name,
            })
        end
        if #choices == 0 then
            table.insert(choices, { text = { { text = 'No pinned civilisations', pen = COLOR_GREY } } })
        end
    end

    self.subviews.pinned_list:setChoices(choices)

    -- Auto-select first real item and populate the right panel
    local first = choices[1]
    local valid = first and (first.hf_id or first.entity_id)
    if valid then
        self.subviews.pinned_list:setSelected(1)
        self:on_pin_select(1, first)
    else
        self.selected_id = nil
        self:_update_right_panel(nil, nil)
    end
end

function PinnedPanel:unpin_selected()
    local _, choice = self.subviews.pinned_list:getSelected()
    if not choice then return end
    if self.view_type == 'individuals' then
        if not choice.hf_id then return end
        ind_death.set_pinned(choice.hf_id, nil)
        self.parent_view.subviews.figures_panel:refresh_list()
    else
        if not choice.entity_id then return end
        wld_leaders.set_pinned_civ(choice.entity_id, nil)
        self.parent_view.subviews.civs_panel:refresh_list()
    end
    self:refresh_pinned_list()
end

-- CivisationsPanel -------------------------------------------------------------

local CivisationsPanel = defclass(CivisationsPanel, widgets.Panel)
CivisationsPanel.ATTRS {
    frame = { t = 2, b = 1 },
}

function CivisationsPanel:init()
    self.show_pinned_only = false

    self:addviews{
        widgets.Label{
            frame = { t = 0, l = 1 },
            text  = {
                { text = ('%-26s'):format('Name'),  pen = COLOR_GREY },
                { text = ('%-13s'):format('Race'),  pen = COLOR_GREY },
                { text = ('%-6s'):format('Sites'),  pen = COLOR_GREY },
                { text = ('%-6s'):format('Pop'),    pen = COLOR_GREY },
                { text = 'Status',                  pen = COLOR_GREY },
            },
        },
        widgets.FilteredList{
            view_id   = 'civ_list',
            frame     = { t = 1, b = 2, l = 1, r = 1 },
            on_select = function(idx, choice) end,
        },
        widgets.HotkeyLabel{
            frame       = { b = 0, l = 1 },
            key         = 'SELECT',
            label       = 'Pin/Unpin',
            auto_width  = true,
            on_activate = function()
                local fl = self.subviews.civ_list
                local idx, choice = fl:getSelected()
                if choice and choice.entity_id then self:toggle_pinned(choice) end
            end,
        },
        widgets.HotkeyLabel{
            view_id     = 'toggle_pinned_btn',
            frame       = { b = 1, l = 1 },
            key         = 'CUSTOM_CTRL_P',
            label       = function()
                return 'Pinned only: ' .. (self.show_pinned_only and 'Yes' or 'No ')
            end,
            auto_width  = true,
            on_activate = function() self:toggle_pinned_only() end,
        },
    }

    self:refresh_list()
end

function CivisationsPanel:onInput(keys)
    if keys.CUSTOM_CTRL_P then
        self:toggle_pinned_only()
        return true
    end
    if self.subviews.civ_list:onInput(keys) then return true end
    return CivisationsPanel.super.onInput(self, keys)
end

function CivisationsPanel:refresh_list()
    local choices = build_civ_choices(self.show_pinned_only)
    self.subviews.civ_list:setChoices(choices)
end

function CivisationsPanel:toggle_pinned(choice)
    if not choice then return end
    local entity_id = choice.entity_id
    local pinned    = wld_leaders.get_pinned_civs()
    local is_pinned = pinned[entity_id]
    wld_leaders.set_pinned_civ(entity_id, not is_pinned)
    local name = choice.display_name or '?'
    print(('[Herald] %s (id %d) is %s pinned.'):format(
        name, entity_id, not is_pinned and 'now' or 'no longer'))
    local fl = self.subviews.civ_list
    local filter_text = fl.edit.text
    self:refresh_list()
    fl:setFilter(filter_text)
    self.parent_view.subviews.pinned_panel:refresh_pinned_list()
end

function CivisationsPanel:toggle_pinned_only()
    self.show_pinned_only = not self.show_pinned_only
    self:refresh_list()
end

-- Event History helpers --------------------------------------------------------

-- Name helpers used by event describers.
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

-- Look up a position name from an entity + position_id, respecting HF sex.
-- Reuses the same two-source logic as get_positions().
local function pos_name_for(entity_id, position_id, hf_sex)
    if not entity_id or entity_id < 0 then return nil end
    if not position_id or position_id < 0 then return nil end
    local entity = df.historical_entity.find(entity_id)
    if not entity then return nil end
    local function pick(pos)
        local g = hf_sex == 1 and name_str(pos.name_male) or name_str(pos.name_female)
        return g or name_str(pos.name)
    end
    if entity.positions and entity.positions.own then
        for _, pos in ipairs(entity.positions.own) do
            if pos.id == position_id then return pick(pos) end
        end
    end
    if entity.entity_raw then
        for _, pos in ipairs(entity.entity_raw.positions) do
            if pos.id == position_id then return pick(pos) end
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

-- Per-type describers: { [event_type_int] = function(ev, focal_hf_id) -> string }
-- Each describer is called inside pcall; return nil to fall back to enum name.
-- Event description templates adapted from LegendsViewer-Next by Kromtec et al.
-- https://github.com/Kromtec/LegendsViewer-Next  (MIT License)
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
    add('HF_ABDUCTED',         hf_abducted_fn)
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
    add('CREATED_BUILDING',   created_structure_fn)
    add('CREATED_STRUCTURE',  created_structure_fn)
end

-- Assigned here so build_hf_event_counts (defined earlier) can use it.
-- Returns true if this event will produce visible text; false if it would be omitted.
event_will_be_shown = function(ev)
    local ev_type   = ev:getType()
    local describer = EVENT_DESCRIBE[ev_type]
    if not describer then return true end  -- no describer → fallback text, always shown
    local ok, result = pcall(describer, ev, -1)
    return ok and result ~= nil
end

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

-- TODO: battle participation events are not yet showing in HF event history.
-- The two approaches below (BATTLE_TYPES vector check and contextual WAR_FIELD_BATTLE
-- aggregation) are implemented but not confirmed working; needs in-game verification.
local function get_hf_events(hf_id)
    local results = {}
    -- Set of enum integers for simple battle events; covers both DFHack naming variants.
    local BATTLE_TYPES = {}
    for _, name in ipairs({'HF_SIMPLE_BATTLE_EVENT', 'HIST_FIGURE_SIMPLE_BATTLE_EVENT'}) do
        local v = df.history_event_type[name]
        if v ~= nil then BATTLE_TYPES[v] = true end
    end
    local COMP_TYPE       = df.history_event_type['COMPETITION']
    local WAR_BATTLE_TYPE = df.history_event_type['WAR_FIELD_BATTLE']

    -- Single pass: collect direct HF events and build a WAR_FIELD_BATTLE index by
    -- site+year. The index is used in step 2 (contextual aggregation) below.
    local battle_index = {}  -- { ['site:year'] = { ev, ... } }
    local added_ids    = {}  -- event.id -> true; prevents duplicates
    for _, ev in ipairs(df.global.world.history.events) do
        if WAR_BATTLE_TYPE and ev:getType() == WAR_BATTLE_TYPE then
            local site = safe_get(ev, 'site')
            local year = safe_get(ev, 'year')
            if site and site >= 0 and year and year >= 0 then
                local key = site .. ':' .. year
                if not battle_index[key] then battle_index[key] = {} end
                table.insert(battle_index[key], ev)
            end
        end

        local found = false
        for _, field in ipairs(HF_FIELDS) do
            if safe_get(ev, field) == hf_id then
                added_ids[ev.id] = true
                table.insert(results, ev)
                found = true
                break
            end
        end
        -- HF_SIMPLE_BATTLE_EVENT: participants are in group1/group2 vectors, not scalars.
        if not found and BATTLE_TYPES[ev:getType()] then
            if vec_has(ev, 'group1', hf_id) or vec_has(ev, 'group2', hf_id) then
                added_ids[ev.id] = true
                table.insert(results, ev)
                found = true
            end
        end
        -- COMPETITION: competitor_hf and winner_hf are vectors.
        if not found and COMP_TYPE and ev:getType() == COMP_TYPE then
            if vec_has(ev, 'competitor_hf', hf_id) or vec_has(ev, 'winner_hf', hf_id) then
                added_ids[ev.id] = true
                table.insert(results, ev)
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
                local ok_s, src = pcall(function() return block.source_hf[k] end)
                local ok_t, tgt = pcall(function() return block.target_hf[k] end)
                if (ok_s and src == hf_id) or (ok_t and tgt == hf_id) then
                    local ok_rt, rtype = pcall(function() return block.relationship[k] end)
                    local ok_yr, yr    = pcall(function() return block.year[k] end)
                    table.insert(results, {
                        _relationship = true,
                        year          = ok_yr and yr or -1,
                        source_hf     = ok_s and src or -1,
                        target_hf     = ok_t and tgt or -1,
                        rel_type      = ok_rt and rtype or -1,
                    })
                end
            end
        end
    end
    table.sort(results, function(a, b) return (a.year or -1) < (b.year or -1) end)
    return results
end

-- EventHistoryWindow -----------------------------------------------------------

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

    -- Debug: dump event list to DFHack console whenever the popup opens.
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

open_event_history = function(hf_id, hf_name)
    event_history_view = event_history_view
        and event_history_view:raise()
        or  EventHistoryScreen{ hf_id = hf_id, hf_name = hf_name }:show()
end

-- HeraldWindow -----------------------------------------------------------------

local HeraldWindow = defclass(HeraldWindow, widgets.Window)
HeraldWindow.ATTRS {
    frame_title = 'Herald: Settings',
    frame       = { w = 76, h = 45 },
    resizable   = false,
}

function HeraldWindow:init()
    self.cur_tab = 1

    local pinned_panel = PinnedPanel{
        view_id = 'pinned_panel',
        visible = true,
    }
    local figures_panel = FiguresPanel{
        view_id = 'figures_panel',
        visible = false,
    }
    local civs_panel = CivisationsPanel{
        view_id = 'civs_panel',
        visible = false,
    }

    self:addviews{
        widgets.TabBar{
            frame  = { t = 0, l = 0 },
            labels = { 'Pinned', 'Historical Figures', 'Civilisations' },
            key          = 'CUSTOM_CTRL_T',
            get_cur_page = function() return self.cur_tab end,
            on_select    = function(idx) self:switch_tab(idx) end,
        },
        pinned_panel,
        figures_panel,
        civs_panel,
        widgets.HotkeyLabel{
            frame       = { b = 0, l = 1 },
            key         = 'CUSTOM_CTRL_J',
            label       = 'Journal',
            auto_width  = true,
            on_activate = function() dfhack.run_command('gui/journal') end,
        },
        widgets.HotkeyLabel{
            frame      = { b = 0, l = 20 },
            key        = 'CUSTOM_CTRL_T',
            label      = 'Cycle tabs',
            auto_width = true,
        },
        widgets.HotkeyLabel{
            frame       = { b = 0, r = 1 },
            key         = 'LEAVESCREEN',
            label       = 'Close',
            auto_width  = true,
            on_activate = function() self.parent_view:dismiss() end,
        },
    }
end

function HeraldWindow:switch_tab(idx)
    self.cur_tab = idx
    self.subviews.pinned_panel.visible  = (idx == 1)
    self.subviews.figures_panel.visible = (idx == 2)
    self.subviews.civs_panel.visible    = (idx == 3)
end

function HeraldWindow:onInput(keys)
    -- Debounce Ctrl-T: DFHack queues all pending key events and flushes them
    -- synchronously in one tick. Rapid Ctrl-T spam fires switch_tab dozens of
    -- times per tick, each triggering postUpdateLayout on large FilteredLists
    -- and overwhelming DF. Swallow presses that arrive faster than 150 ms.
    if keys.CUSTOM_CTRL_T then
        local now = os.clock()
        if self._last_tab_t and (now - self._last_tab_t) < 0.15 then
            return true
        end
        self._last_tab_t = now
    end
    -- Route Ctrl-E to pinned panel (individuals) when on tab 1
    if self.cur_tab == 1 then
        if keys.CUSTOM_CTRL_E then
            return self.subviews.pinned_panel:onInput(keys)
        end
    end
    -- Route Ctrl-D, Ctrl-P, and Ctrl-E to figures panel only when on tab 2
    if self.cur_tab == 2 then
        if keys.CUSTOM_CTRL_D or keys.CUSTOM_CTRL_P or keys.CUSTOM_CTRL_E then
            return self.subviews.figures_panel:onInput(keys)
        end
    end
    -- Route Ctrl-P to civs panel when on tab 3
    if self.cur_tab == 3 then
        if keys.CUSTOM_CTRL_P then
            return self.subviews.civs_panel:onInput(keys)
        end
    end
    return HeraldWindow.super.onInput(self, keys)
end

-- Screen + open_gui ------------------------------------------------------------

local HeraldGuiScreen = defclass(HeraldGuiScreen, gui.ZScreen)
HeraldGuiScreen.ATTRS {
    focus_path = 'herald/gui',
}

function HeraldGuiScreen:init()
    self:addviews{ HeraldWindow{} }
end

function HeraldGuiScreen:onDismiss()
    view = nil
end

function open_gui()
    view = view and view:raise() or HeraldGuiScreen{}:show()
end
