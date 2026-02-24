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

local function get_civ_display(hf)
    return get_civ_name(hf):sub(1, 20)
end

-- Normalises a position name field: entity_position_raw uses string[] (name[0]),
-- entity_position (entity.positions.own) uses plain stl-string.
local function name_str(field)
    if not field then return nil end
    if type(field) == 'string' then return field ~= '' and field or nil end
    local s = field[0]
    return (s and s ~= '') and s or nil
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
                    if asgn.id == link.link_id then
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
local function build_choices(show_dead)
    local choices = {}
    local tracked = ind_death.get_tracked()
    for _, hf in ipairs(df.global.world.history.figures) do
        local is_dead = hf.died_year ~= -1
        if is_dead and not show_dead then goto continue end

        local name     = dfhack.translation.translateName(hf.name, true)
        if name == '' then name = '(unnamed)' end
        local race     = get_race_name(hf)
        if race == '?' then race = 'Unknown' end
        local civ_disp = get_civ_display(hf)
        local is_tracked = tracked[hf.id]

        -- Pad columns: name=22, race=12, civ=20
        local name_col = name:sub(1, 21)
        local race_col = race:sub(1, 11)
        local civ_col  = civ_disp:sub(1, 19)

        local status_token
        if is_dead then
            status_token = { text = 'dead', pen = COLOR_RED }
        else
            status_token = { text = is_tracked and 'tracked' or '', pen = COLOR_GREEN }
        end

        local search_key = (name .. ' ' .. race .. ' ' .. civ_disp):lower()

        table.insert(choices, {
            text       = {
                { text = ('%-22s'):format(name_col), pen = is_dead and COLOR_GREY or nil },
                { text = ('%-12s'):format(race_col), pen = COLOR_GREY },
                { text = ('%-20s'):format(civ_col),  pen = COLOR_GREY },
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
    frame       = { w = 76, h = 38 },
    resizable   = false,
}

function HeraldFiguresWindow:init()
    self.show_dead = false

    self:addviews{
        -- Column header
        widgets.Label{
            frame = { t = 0, l = 1 },
            text  = {
                { text = ('%-28s'):format('Name'),   pen = COLOR_GREY },
                { text = ('%-12s'):format('Race'),   pen = COLOR_GREY },
                { text = ('%-12s'):format('Civ'),    pen = COLOR_GREY },
                { text = 'Status',                   pen = COLOR_GREY },
            },
        },
        -- Figure list
        widgets.FilteredList{
            view_id   = 'fig_list',
            frame     = { t = 1, b = 13, l = 1, r = 1 },
            on_select = function(idx, choice) self:update_detail(choice) end,
            on_submit = function(idx, choice) self:toggle_tracking(choice) end,
        },
        -- Separator
        widgets.Label{
            frame = { t = 25, l = 0, r = 0, h = 1 },
            text  = { { text = string.rep('\xc4', 74), pen = COLOR_GREY } },
        },
        -- Detail panel
        widgets.Label{
            view_id = 'detail_panel',
            frame   = { t = 26, b = 3, l = 1, r = 1 },
            text    = {},
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
            view_id     = 'toggle_dead_btn',
            frame       = { b = 0, l = 20 },
            key         = 'CUSTOM_D',
            label       = 'Show dead: No',
            auto_width  = true,
            on_activate = function() self:toggle_dead() end,
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
end

function HeraldFiguresWindow:refresh_list()
    local choices = build_choices(self.show_dead)
    self.subviews.fig_list:setChoices(choices)
    self.subviews.detail_panel:setText({})
end

function HeraldFiguresWindow:update_detail(choice)
    if not choice then
        self.subviews.detail_panel:setText({})
        return
    end

    local hf      = choice.hf
    local hf_id   = choice.hf_id
    local tracked = ind_death.get_tracked()
    local name    = dfhack.translation.translateName(hf.name, true)
    if name == '' then name = '(unnamed)' end
    local race    = get_race_name(hf)
    local civ     = get_civ_name(hf)
    local is_tracked = tracked[hf_id] and 'Yes' or 'No'
    local alive   = hf.died_year == -1 and 'Alive' or 'Dead'

    local lines = {
        { text = 'ID: ',      pen = COLOR_GREY },
        { text = tostring(hf_id) },
        { text = '   Race: ', pen = COLOR_GREY },
        { text = race },
        { text = '   Status: ', pen = COLOR_GREY },
        { text = alive, pen = hf.died_year == -1 and COLOR_GREEN or COLOR_RED },
        NEWLINE,
        { text = 'Tracked: ', pen = COLOR_GREY },
        { text = is_tracked, pen = tracked[hf_id] and COLOR_GREEN or COLOR_WHITE },
        NEWLINE,
        { text = 'Civ: ', pen = COLOR_GREY },
        { text = civ ~= '' and civ or '(none)' },
        NEWLINE,
    }

    local positions = get_positions(hf)
    if #positions == 0 then
        table.insert(lines, { text = 'Positions: ', pen = COLOR_GREY })
        table.insert(lines, { text = '(none)' })
        table.insert(lines, NEWLINE)
    else
        table.insert(lines, { text = 'Positions:', pen = COLOR_GREY })
        table.insert(lines, NEWLINE)
        local max_show = 4
        for i, p in ipairs(positions) do
            if i > max_show then
                table.insert(lines, { text = '  (more...)', pen = COLOR_GREY })
                table.insert(lines, NEWLINE)
                break
            end
            local pos_label = p.pos_name or '(unnamed position)'
            table.insert(lines, { text = '  ' .. pos_label .. ' of ' .. p.civ_name })
            table.insert(lines, NEWLINE)
        end
    end

    self.subviews.detail_panel:setText(lines)
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
    -- Refresh detail and list
    self:update_detail(choice)
    -- Rebuild list to update status column
    local fl = self.subviews.fig_list
    local filter_text = fl.edit.text
    self:refresh_list()
    fl:setFilter(filter_text)
end

function HeraldFiguresWindow:toggle_dead()
    self.show_dead = not self.show_dead
    local btn = self.subviews.toggle_dead_btn
    btn.label = 'Show dead: ' .. (self.show_dead and 'Yes' or 'No')
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
