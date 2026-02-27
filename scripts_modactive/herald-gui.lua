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
  Ctrl-T              Cycle tabs
  Ctrl-J              Open the DFHack Journal
  Escape              Close the window

  Tab 1 - Pinned
  --------------
  Left pane: pinned individuals or civilisations (Ctrl-I to toggle view).
  Right pane: per-pin announcement toggles; changes are saved immediately.

  Categories marked "*" are not yet implemented.

  Ctrl-I              Toggle between Individuals and Civilisations view
  Ctrl-E              Open event history for the selected entry (HF or civ)
  Enter               Unpin the selected entry

  Tab 2 - Historical Figures
  --------------------------
  Searchable list of all historical figures. 
  Detail pane shows ID, race, alive/dead status, civ, and positions.

  Columns: Name, Race, Civ, Status, Events. 

  Type to search      Filter by name, race, or civilisation
  Enter               Pin or unpin the selected figure
  Ctrl-E              Open event history for the selected figure
  Ctrl-P              Toggle "Pinned only" filter
  Ctrl-D              Toggle "Show dead" filter

  Tab 3 - Civilisations
  ---------------------
  Searchable list of all civilisation-level entities.
  Columns: Name, Race, Sites, Pop.

  Type to search      Filter by name or race
  Enter               Pin or unpin the selected civilisation
  Ctrl-E              Open event history for the selected civilisation
  Ctrl-P              Toggle "Pinned only" filter

  Event History Popup
  -------------------
  Chronological list of world-history events involving a figure. Opened via Ctrl-E from the Pinned or Historical Figures tab. 
  Also dumps the event list to the DFHack console for debugging.

Not intended for direct use.
]====]

local gui         = require('gui')
local widgets     = require('gui.widgets')
local util        = dfhack.reqscript('herald-util')
local ind_death   = dfhack.reqscript('herald-ind-death')
local wld_leaders = dfhack.reqscript('herald-world-leaders')
local ev_hist     = dfhack.reqscript('herald-event-history')
local cache       = dfhack.reqscript('herald-cache')

view = nil  -- module-level; prevents double-open

-- HF / entity helpers ----------------------------------------------------------

-- Returns the translated name of the first Civilisation the HF is a member of.
-- Entity links use virtual dispatch: link:getType() not link.type.
-- link.entity_id gives the referenced entity; resolve via df.historical_entity.find().
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

-- Returns { {pos_name, civ_name}, ... } for all POSITION entity links of an HF.
-- asgn.histfig2 is the HF ID of the current position holder (-1 if vacant).
-- asgn.position_id references pos.id in entity.positions.own / entity.entity_raw.positions.
local function get_positions(hf)
    local results = {}
    for _, link in ipairs(hf.entity_links) do
        if link:getType() == df.histfig_entity_link_type.POSITION then
            local entity = df.historical_entity.find(link.entity_id)
            if entity then
                local civ_name = dfhack.translation.translateName(entity.name, true)
                for _, asgn in ipairs(entity.positions.assignments) do
                    if asgn.histfig2 == hf.id then
                        local pos_name = util.get_pos_name(entity, asgn.position_id, hf.sex)
                        table.insert(results, { pos_name = pos_name, civ_name = civ_name })
                    end
                end
            end
        end
    end
    return results
end

-- Event counts for the "Events" column. Delegates to herald-cache.
local function build_hf_event_counts()
    return cache.get_all_hf_event_counts()
end

-- List builders ---------------------------------------------------------------

-- Builds choice rows for the Figures tab FilteredList.
-- Each row carries hf_id, hf, is_dead, display_name for downstream use.
-- Column widths: Name=22, Race=12, Civ=20, Status=7, Events=remaining.
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
        local race     = util.get_race_name(hf)
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

-- Builds choice rows for the Civilisations tab FilteredList.
-- Sites: counted from world_data.sites via 5-tier cur_owner_id resolution:
--   1. cur_owner_id is directly a Civilization
--   2. SiteGov -> position holder HF -> MEMBER link -> Civ
--   3. SiteGov -> histfig_ids members -> MEMBER/FORMER_MEMBER link -> Civ
--   4. SITE_CONQUERED event collections -> attacker_civ[0] (most recent conquest)
--   5. site.civ_id (original/founding civ; last resort)
-- Population: summed from world.entity_populations (global non-HF racial group list).
-- Column widths: Name=26, Race=13, Sites=6, Pop=6, Status=remaining.
local function build_civ_choices(show_pinned_only)
    -- Build civ_set: Civilization entity IDs for fast O(1) lookup.
    local civ_set = {}
    for _, entity in ipairs(df.global.world.entities.all) do
        if entity.type == df.historical_entity_type.Civilization then
            civ_set[entity.id] = true
        end
    end

    -- Site count: 5-tier resolution from cur_owner_id to parent Civilization.
    local site_counts = {}
    local ok_wd, world_sites = pcall(function() return df.global.world.world_data.sites end)
    if ok_wd and world_sites then
        local sg_to_civ = {}
        local to_resolve = {}
        -- Collect unique non-Civ owner IDs that need resolving.
        for _, site in ipairs(world_sites) do
            local owner = site.cur_owner_id
            if type(owner) == 'number' and owner >= 0
               and not civ_set[owner] and not to_resolve[owner] then
                to_resolve[owner] = true
            end
        end

        -- Tier 2: resolve SiteGov -> position holder HF -> MEMBER link -> Civ.
        for owner_id in pairs(to_resolve) do
            local ok_ent, ent = pcall(df.historical_entity.find, owner_id)
            if not ok_ent or not ent then goto ue_cont end
            local ok_asgns, asgns = pcall(function() return ent.positions.assignments end)
            if not ok_asgns or not asgns then goto ue_cont end
            for _, asgn in ipairs(asgns) do
                local hf_id = asgn.histfig2
                if not (type(hf_id) == 'number' and hf_id >= 0) then goto asgn_cont end
                local hf = df.historical_figure.find(hf_id)
                if not hf then goto asgn_cont end
                for _, link in ipairs(hf.entity_links) do
                    if link:getType() == df.histfig_entity_link_type.MEMBER
                       and civ_set[link.entity_id] then
                        sg_to_civ[owner_id] = link.entity_id
                        break
                    end
                end
                if sg_to_civ[owner_id] then break end
                ::asgn_cont::
            end
            ::ue_cont::
        end

        -- Tier 3: SiteGov -> histfig_ids members -> MEMBER/FORMER_MEMBER link -> Civ.
        -- Catches SiteGovernments where all positions are vacant but entity still has
        -- members on record (dead HFs retain their entity links).
        local LT = df.histfig_entity_link_type
        for owner_id in pairs(to_resolve) do
            if sg_to_civ[owner_id] then goto t3_cont end
            local ok_ent, ent = pcall(df.historical_entity.find, owner_id)
            if not ok_ent or not ent then goto t3_cont end
            local ok_hfids, hfids = pcall(function() return ent.histfig_ids end)
            if not ok_hfids or not hfids then goto t3_cont end
            for _, hf_id in ipairs(hfids) do
                if not (type(hf_id) == 'number' and hf_id >= 0) then goto t3_hf end
                local hf = df.historical_figure.find(hf_id)
                if not hf then goto t3_hf end
                for _, link in ipairs(hf.entity_links) do
                    local lt = link:getType()
                    if (lt == LT.MEMBER or lt == LT.FORMER_MEMBER)
                       and civ_set[link.entity_id] then
                        sg_to_civ[owner_id] = link.entity_id
                        break
                    end
                end
                if sg_to_civ[owner_id] then break end
                ::t3_hf::
            end
            ::t3_cont::
        end

        -- Tier 4: SITE_CONQUERED event collections -> attacker_civ[0].
        -- Build site_conqueror map: iterate forward so latest conquest wins.
        local site_conqueror = {}
        local ok_cols, cols = pcall(function()
            return df.global.world.history.event_collections.all
        end)
        if ok_cols and cols then
            local SC_TYPE = df.history_event_collection_type.SITE_CONQUERED
            for _, col in ipairs(cols) do
                local ok_t, ctype = pcall(function() return col:getType() end)
                if not ok_t or ctype ~= SC_TYPE then goto t4_col end
                local ok_s, site_id = pcall(function() return col.site end)
                if not ok_s or not (type(site_id) == 'number' and site_id >= 0) then
                    goto t4_col
                end
                local ok_ac, acv = pcall(function() return col.attacker_civ end)
                if ok_ac and acv and #acv > 0 then
                    local ac_id = acv[0]
                    if type(ac_id) == 'number' and ac_id >= 0 and civ_set[ac_id] then
                        site_conqueror[site_id] = ac_id
                    end
                end
                ::t4_col::
            end
        end

        -- Count sites per civ: Tier 1 (direct civ) -> Tier 2/3 (sg_to_civ) ->
        -- Tier 4 (site_conqueror) -> Tier 5 (site.civ_id as last resort).
        for _, site in ipairs(world_sites) do
            local owner = site.cur_owner_id
            if not (type(owner) == 'number' and owner >= 0) then goto sc_cont end
            local cid = (civ_set[owner] and owner)
                        or sg_to_civ[owner]
                        or site_conqueror[site.id]
            -- Tier 5: fall back to site.civ_id (original/founding civ).
            if not cid then
                local orig = site.civ_id
                if type(orig) == 'number' and orig >= 0 and civ_set[orig] then
                    cid = orig
                end
            end
            if cid then
                site_counts[cid] = (site_counts[cid] or 0) + 1
            end
            ::sc_cont::
        end
    end

    -- Population: global entity_populations list. Each entry has parallel 0-indexed
    -- DF vectors races/counts; sum counts[i] across all entries for a civ.
    -- Note: no count_min field exists on this struct (verified via printall).
    local pop_counts = {}
    local ok_ep, ep_list = pcall(function() return df.global.world.entity_populations end)
    if ok_ep and ep_list then
        for _, ep in ipairs(ep_list) do
            local cid = ep.civ_id
            if type(cid) == 'number' and cid >= 0 then
                local counts = ep.counts
                if counts then
                    for i = 0, #counts - 1 do
                        local cnt = counts[i]
                        if type(cnt) == 'number' and cnt > 0 then
                            pop_counts[cid] = (pop_counts[cid] or 0) + cnt
                        end
                    end
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

        local race = util.get_entity_race_name(entity)
        if race == '?' then race = 'Unknown' end

        local site_count = site_counts[entity_id] or 0
        local pop_count  = pop_counts[entity_id] or 0

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
    self.show_dead        = false
    self.show_pinned_only = false
    self._loaded          = false  -- set true in switch_tab on first visit

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
                if choice then ev_hist.open_event_history(choice.hf_id, choice.display_name) end
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

    -- refresh_list() is intentionally NOT called here; data loads on first tab visit.

    -- Patch onFilterChange so the detail panel refreshes when the user types
    -- in the search box (the default callback only updates the list, not the detail).
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
        if choice then ev_hist.open_event_history(choice.hf_id, choice.display_name) end
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
    local race    = util.get_race_name(hf)
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
    self.parent_view:on_pin_changed(now_pinned and 'individual_pinned' or 'individual_unpinned')
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
    { key = 'relationships', label = 'Relationships', caption = 'HF bonds',  impl = false },
    { key = 'death',         label = 'Death',         caption = 'Pinned HF dies',       impl = true  },
    { key = 'combat',        label = 'Combat',        caption = 'Battles, duels etc.',      impl = false },
    { key = 'legendary',     label = 'Legendary',     caption = 'Attained Legendary',     impl = false },
    { key = 'positions',     label = 'Positions',     caption = 'Title gained/lost',    impl = false },
    { key = 'migration',     label = 'Migration',     caption = 'Moves settlement',     impl = false },
}

local CIVILISATIONS_ANN = {
    { key = 'positions',   label = 'Positions',   caption = 'Leader changes',   impl = true  },
    { key = 'diplomacy',   label = 'Diplomacy',   caption = 'Alliances & pacts', impl = false },
    { key = 'warfare',     label = 'Warfare',     caption = 'Wars & armies',   impl = false },
    { key = 'raids',       label = 'Raids',       caption = 'Raids on sites',   impl = false },
    { key = 'theft',       label = 'Theft',       caption = 'Artifacts stolen', impl = false },
    { key = 'kidnappings', label = 'Kidnappings', caption = 'Abductions',      impl = false },
}

local PinnedPanel = defclass(PinnedPanel, widgets.Panel)
PinnedPanel.ATTRS {
    frame = { t = 2, b = 1 },
}

function PinnedPanel:init()
    -- 'individuals' or 'civilisations'
    self.view_type  = 'individuals'
    self.selected_id = nil  -- hf_id or entity_id of currently selected pin

    -- Builds one ToggleHotkeyLabel per entry for a pin's announcement settings.
    -- Unimplemented categories get a " *" suffix and a no-op on_change.
    -- `local e = entry` is necessary to correctly capture each loop iteration.
    local function make_toggle_views(entries, category)
        local views = {}
        for i, entry in ipairs(entries) do
            local e   = entry  -- capture each loop variable by value
            local row = (i - 1) * 3 + 1  -- 3 rows per entry: toggle + caption + blank
            local display_label = e.impl and e.label or (e.label .. ' *')
            table.insert(views, widgets.ToggleHotkeyLabel{
                view_id        = 'toggle_' .. e.key,
                frame          = { t = row, h = 1, l = 0, r = 0 },
                label          = display_label,
                initial_option = 1,  -- starts ON; overridden when a pin is selected
                on_change      = e.impl and function(new_val)
                    if not self.selected_id then return end
                    if self.view_type == 'individuals' then
                        ind_death.set_pin_setting(self.selected_id, e.key, new_val)
                    else
                        wld_leaders.set_civ_pin_setting(self.selected_id, e.key, new_val)
                    end
                end or function() end,
            })
            table.insert(views, widgets.Label{
                frame = { t = row + 1, h = 1, l = 2, r = 0 },
                text  = { { text = e.caption, pen = COLOR_GREY } },
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
                if not choice then return end
                if self.view_type == 'individuals' and choice.hf_id then
                    ev_hist.open_event_history(choice.hf_id, choice.display_name)
                elseif self.view_type == 'civilisations' and choice.entity_id then
                    ev_hist.open_civ_event_history(choice.entity_id, choice.display_name)
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
    if keys.CUSTOM_CTRL_E then
        local _, choice = self.subviews.pinned_list:getSelected()
        if choice then
            if self.view_type == 'individuals' and choice.hf_id then
                ev_hist.open_event_history(choice.hf_id, choice.display_name)
            elseif self.view_type == 'civilisations' and choice.entity_id then
                ev_hist.open_civ_event_history(choice.entity_id, choice.display_name)
            end
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
            local race    = util.get_race_name(hf)
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
            local race = util.get_entity_race_name(civ.entity)
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
    else
        if not choice.entity_id then return end
        wld_leaders.set_pinned_civ(choice.entity_id, nil)
    end
    self:refresh_pinned_list()
    local change_type = self.view_type == 'individuals'
        and 'individual_unpinned' or 'civ_unpinned'
    self.parent_view:on_pin_changed(change_type)
end

-- CivisationsPanel -------------------------------------------------------------

local CivisationsPanel = defclass(CivisationsPanel, widgets.Panel)
CivisationsPanel.ATTRS {
    frame = { t = 2, b = 1 },
}

function CivisationsPanel:init()
    self.show_pinned_only = false
    self._loaded          = false  -- set true in switch_tab on first visit

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
            frame       = { b = 0, l = 22 },
            key         = 'CUSTOM_CTRL_E',
            label       = 'Event History',
            auto_width  = true,
            on_activate = function()
                local _, choice = self.subviews.civ_list:getSelected()
                if choice and choice.entity_id then
                    ev_hist.open_civ_event_history(choice.entity_id, choice.display_name)
                end
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

    -- refresh_list() is intentionally NOT called here; data loads on first tab visit.
end

function CivisationsPanel:onInput(keys)
    if keys.CUSTOM_CTRL_E then
        local _, choice = self.subviews.civ_list:getSelected()
        if choice and choice.entity_id then
            ev_hist.open_civ_event_history(choice.entity_id, choice.display_name)
        end
        return true
    end
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
    local now_pinned = not is_pinned
    wld_leaders.set_pinned_civ(entity_id, now_pinned)
    local name = choice.display_name or '?'
    print(('[Herald] %s (id %d) is %s pinned.'):format(
        name, entity_id, now_pinned and 'now' or 'no longer'))
    local fl = self.subviews.civ_list
    local filter_text = fl.edit.text
    self:refresh_list()
    fl:setFilter(filter_text)
    self.parent_view:on_pin_changed(now_pinned and 'civ_pinned' or 'civ_unpinned')
end

function CivisationsPanel:toggle_pinned_only()
    self.show_pinned_only = not self.show_pinned_only
    self:refresh_list()
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

    -- All three panels are created upfront so layout works correctly.
    -- FiguresPanel and CivisationsPanel skip refresh_list() in init() and load
    -- their data lazily on first tab visit (see switch_tab / _loaded flag).
    self:addviews{
        widgets.TabBar{
            frame  = { t = 0, l = 0 },
            labels = { 'Pinned', 'Historical Figures', 'Civilisations' },
            key          = 'CUSTOM_CTRL_T',
            get_cur_page = function() return self.cur_tab end,
            on_select    = function(idx) self:switch_tab(idx) end,
        },
        PinnedPanel{    view_id = 'pinned_panel',  visible = true  },
        FiguresPanel{   view_id = 'figures_panel', visible = false },
        CivisationsPanel{ view_id = 'civs_panel',  visible = false },
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
            frame       = { b = 0, l = 42 },
            key         = 'CUSTOM_CTRL_C',
            label       = 'Refresh',
            auto_width  = true,
            on_activate = function() self:refresh_cache() end,
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

    -- Load data on first visit — deferred from init() to avoid the expensive
    -- build_hf_event_counts() / build_civ_choices() scans at GUI open time.
    if idx == 2 and not self.subviews.figures_panel._loaded then
        self.subviews.figures_panel._loaded = true
        self.subviews.figures_panel:refresh_list()
    end
    if idx == 3 and not self.subviews.civs_panel._loaded then
        self.subviews.civs_panel._loaded = true
        self.subviews.civs_panel:refresh_list()
    end
end

-- Ctrl-C: delta-process new events and refresh the active panel.
function HeraldWindow:refresh_cache()
    local n = cache.build_delta()
    print(('[Herald] Cache refreshed - %d new event(s) processed'):format(n))
    -- Refresh whichever panel is active.
    if self.cur_tab == 1 then
        self.subviews.pinned_panel:refresh_pinned_list()
    elseif self.cur_tab == 2 and self.subviews.figures_panel._loaded then
        self.subviews.figures_panel:refresh_list()
    elseif self.cur_tab == 3 and self.subviews.civs_panel._loaded then
        self.subviews.civs_panel:refresh_list()
    end
end

-- Centralised cross-panel refresh after a pin change.
-- change_type: 'individual_pinned', 'individual_unpinned',
--              'civ_pinned', 'civ_unpinned'
function HeraldWindow:on_pin_changed(change_type)
    if change_type == 'individual_pinned' or change_type == 'individual_unpinned' then
        self.subviews.pinned_panel:refresh_pinned_list()
        if self.subviews.figures_panel._loaded then
            self.subviews.figures_panel:refresh_list()
        end
    elseif change_type == 'civ_pinned' or change_type == 'civ_unpinned' then
        self.subviews.pinned_panel:refresh_pinned_list()
        if self.subviews.civs_panel._loaded then
            self.subviews.civs_panel:refresh_list()
        end
    end
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
    -- Ctrl-C: refresh cache (handled at window level, applies to all tabs).
    if keys.CUSTOM_CTRL_C then
        self:refresh_cache()
        return true
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
    -- Route Ctrl-P and Ctrl-E to civs panel when on tab 3
    if self.cur_tab == 3 then
        if keys.CUSTOM_CTRL_P or keys.CUSTOM_CTRL_E then
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

-- First-time cache build warning dialog.
local CacheBuildWindow = defclass(CacheBuildWindow, widgets.Window)
CacheBuildWindow.ATTRS {
    frame_title = 'Herald: First-Time Setup',
    frame       = { w = 52, h = 12 },
    resizable   = false,
}

function CacheBuildWindow:init()
    self:addviews{
        widgets.Label{
            frame = { t = 0, l = 1, r = 1 },
            text  = {
                'Herald needs to scan world history to build\n',
                'an event cache. This only happens once per\n',
                'save and may briefly freeze the game.\n',
                '\n',
                { text = 'Proceed?', pen = COLOR_YELLOW },
            },
        },
        widgets.HotkeyLabel{
            frame       = { b = 0, l = 1 },
            key         = 'SELECT',
            label       = 'Build Now',
            auto_width  = true,
            on_activate = function()
                self.parent_view:dismiss()
                local n = cache.build_full()
                print(('[Herald] Cache built - %d event(s) processed'):format(n))
                view = HeraldGuiScreen{}:show()
            end,
        },
        widgets.HotkeyLabel{
            frame       = { b = 0, r = 1 },
            key         = 'LEAVESCREEN',
            label       = 'Cancel',
            auto_width  = true,
            on_activate = function() self.parent_view:dismiss() end,
        },
    }
end

local CacheBuildWarning = defclass(CacheBuildWarning, gui.ZScreen)
CacheBuildWarning.ATTRS {
    focus_path = 'herald/cache-warning',
}

function CacheBuildWarning:init()
    self:addviews{ CacheBuildWindow{} }
end

function open_gui()
    if view then
        view:raise()
        return
    end
    if cache.needs_build() then
        CacheBuildWarning{}:show()
        return
    end
    -- Cache is ready; delta-process new events then open.
    cache.build_delta()
    view = HeraldGuiScreen{}:show()
end
