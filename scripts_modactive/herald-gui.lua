--@ module=true

--[====[
herald-gui
==========
Tags: fort | gameplay

  Settings UI for the Herald mod: browse and track historical figures.

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
-- Match assignments by histfig2 == hf.id (the HF holder field on the assignment).
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
                        -- Try entity_raw.positions first
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
                        -- Fallback: entity.positions.own
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

-- Build the choice list for the FilteredList.
-- Column widths: Name=22, Race=12, Civ=25, Status=remaining
local function build_choices(show_dead, show_tracked_only)
    local choices = {}
    local tracked = ind_death.get_tracked()
    for _, hf in ipairs(df.global.world.history.figures) do
        local is_dead = hf.died_year ~= -1
        if is_dead and not show_dead then goto continue end
        if show_tracked_only and not tracked[hf.id] then goto continue end

        local name     = dfhack.translation.translateName(hf.name, true)
        if name == '' then name = '(unnamed)' end
        local race     = get_race_name(hf)
        if race == '?' then race = 'Unknown' end
        local civ_full = get_civ_name(hf)   -- full name for search
        local is_tracked = tracked[hf.id]

        local name_col = name:sub(1, 22)
        local race_col = race:sub(1, 12)
        local civ_col  = civ_full:sub(1, 24)

        local status_token
        if is_dead then
            status_token = { text = 'dead', pen = COLOR_RED }
        else
            status_token = { text = is_tracked and 'tracked' or '', pen = COLOR_GREEN }
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

-- HeraldFiguresWindow ----------------------------------------------------------

local HeraldFiguresWindow = defclass(HeraldFiguresWindow, widgets.Window)
HeraldFiguresWindow.ATTRS {
    frame_title = 'Herald: Figure Tracking',
    frame       = { w = 76, h = 45 },
    resizable   = false,
}

function HeraldFiguresWindow:init()
    self.show_dead         = false
    self.show_tracked_only = false

    self:addviews{
        -- Column header (matches data column widths: name=22, race=12, civ=25)
        widgets.Label{
            frame = { t = 0, l = 1 },
            text  = {
                { text = ('%-22s'):format('Name'),   pen = COLOR_GREY },
                { text = ('%-12s'):format('Race'),   pen = COLOR_GREY },
                { text = ('%-25s'):format('Civ'),    pen = COLOR_GREY },
                { text = 'Status',                   pen = COLOR_GREY },
            },
        },
        -- Figure list; on_submit removed so clicking a row does NOT track/untrack
        widgets.FilteredList{
            view_id   = 'fig_list',
            frame     = { t = 1, b = 13, l = 1, r = 1 },
            on_select = function(idx, choice) self:update_detail(choice) end,
        },
        -- Separator
        widgets.Label{
            frame = { t = 32, l = 0, r = 0, h = 1 },
            text  = { { text = string.rep('\xc4', 74), pen = COLOR_GREY } },
        },
        -- Detail panel (scrollable list, one row per field/position)
        widgets.List{
            view_id   = 'detail_panel',
            frame     = { t = 33, b = 2, l = 1, r = 1 },
            on_select = function() end,
        },
        -- Footer hotkeys
        widgets.HotkeyLabel{
            frame       = { b = 0, l = 1 },
            key         = 'SELECT',
            label       = 'Track/Untrack',
            auto_width  = true,
            on_activate = function()
                local fl = self.subviews.fig_list
                local idx, choice = fl:getSelected()
                if choice then self:toggle_tracking(choice) end
            end,
        },
        widgets.HotkeyLabel{
            view_id     = 'toggle_tracked_btn',
            frame       = { b = 1, l = 1 },
            key         = 'CUSTOM_CTRL_T',
            label       = function()
                return 'Tracked only: ' .. (self.show_tracked_only and 'Yes' or 'No ')
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
        widgets.HotkeyLabel{
            frame       = { b = 0, r = 1 },
            key         = 'LEAVESCREEN',
            label       = 'Close',
            auto_width  = true,
            on_activate = function() self.parent_view:dismiss() end,
        },
    }

    self:refresh_list()

    -- Override onFilterChange so the detail panel updates on every filter change.
    -- on_select alone misfires when the list returns from "no matches" with the same
    -- selected index; onFilterChange runs after the list updates, so getSelected() is reliable.
    local fl  = self.subviews.fig_list
    local win = self
    local _orig_ofc = fl.onFilterChange   -- captures class method via __index
    fl.onFilterChange = function(this, text, pos)
        _orig_ofc(this, text, pos)
        local _, choice = this:getSelected()
        win:update_detail(choice)
    end
end

-- Intercept keys before children can swallow them.
function HeraldFiguresWindow:onInput(keys)
    if keys.CUSTOM_CTRL_D then
        self:toggle_dead()
        return true
    end
    if keys.CUSTOM_CTRL_T then
        self:toggle_tracked_only()
        return true
    end
    -- Route input through fig_list first for keyboard navigation; it returns false
    -- for anything it doesn't handle (hotkeys, detail-panel clicks), falling through to super.
    if self.subviews.fig_list:onInput(keys) then return true end
    return HeraldFiguresWindow.super.onInput(self, keys)
end

function HeraldFiguresWindow:refresh_list()
    local choices = build_choices(self.show_dead, self.show_tracked_only)
    self.subviews.fig_list:setChoices(choices)
    -- Populate detail panel from whatever is now selected (first item on open,
    -- preserved selection after a toggle-dead refresh).
    local _, choice = self.subviews.fig_list:getSelected()
    self:update_detail(choice)
end

function HeraldFiguresWindow:update_detail(choice)
    if not choice then
        self.subviews.detail_panel:setChoices({})
        return
    end

    local hf      = choice.hf
    local hf_id   = choice.hf_id
    local tracked = ind_death.get_tracked()
    local name    = dfhack.translation.translateName(hf.name, true)
    if name == '' then name = '(unnamed)' end
    local race    = get_race_name(hf)
    if race == '?' then race = 'Unknown' end
    local civ = get_civ_name(hf)
    local gov = get_site_gov(hf)
    local is_tracked = tracked[hf_id] and 'Yes' or 'No'
    local alive   = hf.died_year == -1 and 'Alive' or 'Dead'

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
            { text = 'Tracked: ', pen = COLOR_GREY },
            { text = is_tracked, pen = tracked[hf_id] and COLOR_GREEN or COLOR_WHITE },
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

function HeraldFiguresWindow:toggle_tracking(choice)
    if not choice then return end
    local hf_id   = choice.hf_id
    local tracked = ind_death.get_tracked()
    local now_tracked = not tracked[hf_id]
    ind_death.set_tracked(hf_id, now_tracked or nil)
    local name = dfhack.translation.translateName(choice.hf.name, true)
    if name == '' then name = '(unnamed)' end
    print(('[Herald] %s (id %d) is %s tracked.'):format(
        name, hf_id, now_tracked and 'now' or 'no longer'))
    self:update_detail(choice)
    -- Rebuild list to update status column
    local fl = self.subviews.fig_list
    local filter_text = fl.edit.text
    self:refresh_list()
    fl:setFilter(filter_text)
end

function HeraldFiguresWindow:toggle_dead()
    self.show_dead = not self.show_dead
    self:refresh_list()
end

function HeraldFiguresWindow:toggle_tracked_only()
    self.show_tracked_only = not self.show_tracked_only
    self:refresh_list()
end

-- Screen + open_gui ------------------------------------------------------------

local HeraldGuiScreen = defclass(HeraldGuiScreen, gui.ZScreen)
HeraldGuiScreen.ATTRS {
    focus_path = 'herald/gui',
}

function HeraldGuiScreen:init()
    self:addviews{ HeraldFiguresWindow{} }
end

function HeraldGuiScreen:onDismiss()
    view = nil
end

function open_gui()
    view = view and view:raise() or HeraldGuiScreen{}:show()
end
