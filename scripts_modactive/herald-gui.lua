--@ module=true

--[====[
herald-gui
==========
Tags: fort | gameplay

  Settings UI for the Herald mod: tabbed window with figure tracking and announcement toggles.

Not intended for direct use.
]====]

local gui       = require('gui')
local widgets   = require('gui.widgets')
local ind_death = dfhack.reqscript('herald-ind-death')

view = nil  -- module-level; prevents double-open

-- Helpers ----------------------------------------------------------------------

local function get_race_name(hf)
    if not hf or hf.race < 0 then return '?' end
    local cr = df.creature_raw.find(hf.race)
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
                        if entity.entity_raw then
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
                        if not pos_name and entity.positions and entity.positions.own then
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
                        table.insert(results, { pos_name = pos_name, civ_name = civ_name })
                    end
                end
            end
        end
    end
    return results
end

-- Build the choice list for the Figures FilteredList.
-- Column widths: Name=22, Race=12, Civ=25, Status=remaining
local function build_choices(show_dead, show_pinned_only)
    local choices = {}
    local pinned = ind_death.get_pinned()
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
        local civ_col  = civ_full:sub(1, 24)

        local status_token
        if is_dead then
            status_token = { text = 'dead',   pen = COLOR_RED }
        else
            status_token = { text = is_pinned and 'pinned' or '', pen = COLOR_GREEN }
        end

        local search_key = (name .. ' ' .. race .. ' ' .. civ_full):lower()

        table.insert(choices, {
            text       = {
                { text = ('%-22s'):format(name_col), pen = is_dead and COLOR_GREY or nil },
                { text = ('%-12s'):format(race_col), pen = COLOR_GREY },
                { text = ('%-25s'):format(civ_col),  pen = COLOR_GREY },
                status_token,
            },
            search_key = search_key,
            hf_id      = hf.id,
            hf         = hf,
            is_dead    = is_dead,
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
                { text = ('%-25s'):format('Civ'),    pen = COLOR_GREY },
                { text = 'Status',                   pen = COLOR_GREY },
            },
        },
        widgets.FilteredList{
            view_id   = 'fig_list',
            frame     = { t = 1, b = 13, l = 1, r = 1 },
            on_select = function(idx, choice) self:update_detail(choice) end,
        },
        widgets.Label{
            frame = { t = 30, l = 0, r = 0, h = 1 },
            text  = { { text = string.rep('\xc4', 74), pen = COLOR_GREY } },
        },
        widgets.List{
            view_id   = 'detail_panel',
            frame     = { t = 31, b = 2, l = 1, r = 1 },
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
            view_id     = 'toggle_pinned_btn',
            frame       = { b = 1, l = 1 },
            key         = 'CUSTOM_CTRL_P',
            label       = function()
                return 'Pinned only: ' .. (self.show_pinned_only and 'Yes' or 'No ')
            end,
            auto_width  = true,
        },
        widgets.HotkeyLabel{
            view_id     = 'toggle_dead_btn',
            frame       = { b = 1, l = 35 },
            key         = 'CUSTOM_CTRL_D',
            label       = function()
                return 'Show dead: ' .. (self.show_dead and 'Yes' or 'No ')
            end,
            auto_width  = true,
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
    self.view_type = 'individuals'

    local main = dfhack.reqscript('herald-main')
    local ann   = main.get_announcements()

    -- Helper to build a list of ToggleHotkeyLabel widgets for an announcement category
    local function make_toggle_views(entries, category)
        local views = {}
        for i, entry in ipairs(entries) do
            local e = entry  -- capture loop variable
            local display_label = e.impl and e.label or (e.label .. ' *')
            local initial = ann[category][e.key]
            table.insert(views, widgets.ToggleHotkeyLabel{
                frame          = { t = i - 1, h = 1, l = 0, r = 0 },
                label          = display_label,
                initial_option = initial and 1 or 2,
                on_change      = e.impl and function(new_val)
                    local a = dfhack.reqscript('herald-main').get_announcements()
                    a[category][e.key] = new_val
                    dfhack.reqscript('herald-main').save_announcements(a)
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
    ann_ind:addviews(make_toggle_views(INDIVIDUALS_ANN, 'individuals'))

    -- Announcement panel for civilisations (hidden initially)
    local ann_civ = widgets.Panel{
        view_id = 'ann_panel_civilisations',
        frame   = { t = 3, b = 1, l = 50, r = 1 },
        visible = false,
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
            on_select = function() end,
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
        widgets.Label{
            frame = { b = 0, l = 20 },
            text  = { { text = '* = not yet implemented', pen = COLOR_GREY } },
        },
    }

    self:refresh_pinned_list()
end

function PinnedPanel:on_type_change(new_val)
    local is_ind = (new_val == 'Individuals')
    self.view_type = is_ind and 'individuals' or 'civilisations'
    self.subviews.ann_panel_individuals.visible  = is_ind
    self.subviews.ann_panel_civilisations.visible = not is_ind
    self:refresh_pinned_list()
end

function PinnedPanel:refresh_pinned_list()
    local choices = {}
    if self.view_type == 'individuals' then
        local pinned = ind_death.get_pinned()
        -- Collect pinned HFs
        local hf_list = {}
        for hf_id in pairs(pinned) do
            local hf = df.historical_figure.find(hf_id)
            if hf then table.insert(hf_list, hf) end
        end
        -- Sort alphabetically
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
                hf_id = hf.id,
            })
        end
        if #choices == 0 then
            table.insert(choices, { text = { { text = 'No pinned individuals', pen = COLOR_GREY } } })
        end
    else
        table.insert(choices, { text = { { text = 'No pinned civilisations', pen = COLOR_GREY } } })
    end
    self.subviews.pinned_list:setChoices(choices)
end

function PinnedPanel:unpin_selected()
    if self.view_type ~= 'individuals' then return end
    local _, choice = self.subviews.pinned_list:getSelected()
    if not choice or not choice.hf_id then return end
    ind_death.set_pinned(choice.hf_id, nil)
    self:refresh_pinned_list()
    self.parent_view.subviews.figures_panel:refresh_list()
end

-- CivisationsPanel (placeholder) -----------------------------------------------

local CivisationsPanel = defclass(CivisationsPanel, widgets.Panel)
CivisationsPanel.ATTRS {
    frame = { t = 2, b = 1 },
}

function CivisationsPanel:init()
    self:addviews{
        widgets.Label{
            frame = { t = 2, l = 2 },
            text  = 'Civilisation tracking',
        },
        widgets.Label{
            frame = { t = 3, l = 2 },
            text  = { { text = 'Coming soon.', pen = COLOR_GREY } },
        },
    }
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
            key_back     = 'CUSTOM_CTRL_Y',
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
    -- Route Ctrl-D and Ctrl-P to figures panel only when on tab 2
    if self.cur_tab == 2 then
        if keys.CUSTOM_CTRL_D or keys.CUSTOM_CTRL_P then
            return self.subviews.figures_panel:onInput(keys)
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
