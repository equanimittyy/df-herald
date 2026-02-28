--@ module=true
--[====[
herald-button
=============
Overlay widget that adds a Herald button to the main DF screen.
Not intended for direct use.
]====]

local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')

-- The PNG is 64x36 with two 32x36 states side by side: left = normal, right = hover.
-- At 8x12 px/tile: 8 total columns, 3 rows. Each state occupies 4 columns.
local TILE_W        = 8
local TILE_H        = 12
local LOGO_COLS     = 4   -- tiles per state
local LOGO_ROWS     = 3
local PNG_COLS      = 8   -- total tile columns across the full PNG

-- SCRIPT_PATH is not set for overlay modules; derive directory from source info.
local _DIR = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or ''

local logo_state  = 'unloaded'  -- 'unloaded' | 'ok' | 'failed'
local normal_pens = nil
local hover_pens  = nil

local function load_logo_pens()
    if logo_state == 'ok'     then return normal_pens, hover_pens end
    if logo_state == 'failed' then return nil end
    local path = _DIR .. 'herald-logo.png'
    local ok, handles = pcall(dfhack.textures.loadTileset, path, TILE_W, TILE_H, true)
    if not ok or not handles or #handles == 0 then
        logo_state = 'failed'
        return nil
    end
    normal_pens, hover_pens = {}, {}
    for row = 0, LOGO_ROWS - 1 do
        for col = 0, LOGO_COLS - 1 do
            local ni = row * PNG_COLS + col + 1
            local hi = row * PNG_COLS + LOGO_COLS + col + 1
            normal_pens[#normal_pens + 1] =
                dfhack.pen.parse{tile=dfhack.textures.getTexposByHandle(handles[ni]), ch=32}
            hover_pens[#hover_pens + 1] =
                dfhack.pen.parse{tile=dfhack.textures.getTexposByHandle(handles[hi]), ch=32}
        end
    end
    logo_state = 'ok'
    return normal_pens, hover_pens
end

local LogoButton = defclass(LogoButton, widgets.Panel)
LogoButton.ATTRS{
    normal_pens = DEFAULT_NIL,
    hover_pens  = DEFAULT_NIL,
    on_click    = DEFAULT_NIL,
}

function LogoButton:onRenderBody(dc)
    local hovered = self:getMousePos() ~= nil
    local pens = (hovered and self.hover_pens) or self.normal_pens
    for row = 0, LOGO_ROWS - 1 do
        for col = 0, LOGO_COLS - 1 do
            dc:seek(col, row):char(32, pens[row * LOGO_COLS + col + 1])
        end
    end
end

function LogoButton:onInput(keys)
    if keys._MOUSE_L and self:getMousePos() then
        if self.on_click then self.on_click() end
        return true
    end
    return LogoButton.super.onInput(self, keys)
end

HeraldButton = defclass(HeraldButton, overlay.OverlayWidget)

HeraldButton.ATTRS{
    default_pos     = {x=10, y=1},
    default_enabled = true,
    viewscreens     = {'dwarfmode', 'dwarfmode/', 'world/'},
    frame           = {w=LOGO_COLS, h=LOGO_ROWS},
}

function HeraldButton:init()
    local np, hp = load_logo_pens()
    if np then
        self:addviews{
            LogoButton{
                frame       = {l=0, t=0, w=LOGO_COLS, h=LOGO_ROWS},
                normal_pens = np,
                hover_pens  = hp,
                on_click    = function() dfhack.run_command('herald-main', 'gui') end,
            }
        }
    else
        self:addviews{
            widgets.TextButton{
                frame       = {l=0, t=0},
                label       = 'Herald',
                on_activate = function() dfhack.run_command('herald-main', 'gui') end,
            }
        }
    end
end

-- HeraldAlert -----------------------------------------------------------------
-- Appears when there are unread Herald announcements; disappears on click.

local ALERT_COLS = 12  -- tiles per state
local ALERT_ROWS = 2
local ALERT_PNG_COLS = 24  -- total tile columns across the full PNG (two 12-col states)

local alert_state      = 'unloaded'
local alert_normal     = nil
local alert_hover      = nil

local function load_alert_pens()
    if alert_state == 'ok'     then return alert_normal, alert_hover end
    if alert_state == 'failed' then return nil end
    local path = _DIR .. 'herald-alert.png'
    local ok, handles = pcall(dfhack.textures.loadTileset, path, TILE_W, TILE_H, true)
    if not ok or not handles or #handles == 0 then
        alert_state = 'failed'
        return nil
    end
    alert_normal, alert_hover = {}, {}
    for row = 0, ALERT_ROWS - 1 do
        for col = 0, ALERT_COLS - 1 do
            local ni = row * ALERT_PNG_COLS + col + 1
            local hi = row * ALERT_PNG_COLS + ALERT_COLS + col + 1
            alert_normal[#alert_normal + 1] =
                dfhack.pen.parse{tile=dfhack.textures.getTexposByHandle(handles[ni]), ch=32}
            alert_hover[#alert_hover + 1] =
                dfhack.pen.parse{tile=dfhack.textures.getTexposByHandle(handles[hi]), ch=32}
        end
    end
    alert_state = 'ok'
    return alert_normal, alert_hover
end

local AlertButton = defclass(AlertButton, widgets.Panel)
AlertButton.ATTRS{
    normal_pens = DEFAULT_NIL,
    hover_pens  = DEFAULT_NIL,
    on_click    = DEFAULT_NIL,
    cols        = ALERT_COLS,
    rows        = ALERT_ROWS,
}

function AlertButton:onRenderBody(dc)
    local hovered = self:getMousePos() ~= nil
    local pens = (hovered and self.hover_pens) or self.normal_pens
    for row = 0, self.rows - 1 do
        for col = 0, self.cols - 1 do
            dc:seek(col, row):char(32, pens[row * self.cols + col + 1])
        end
    end
end

function AlertButton:onInput(keys)
    if keys._MOUSE_L and self:getMousePos() then
        if self.on_click then self.on_click() end
        return true
    end
    return AlertButton.super.onInput(self, keys)
end

HeraldAlert = defclass(HeraldAlert, overlay.OverlayWidget)

HeraldAlert.ATTRS{
    default_pos     = {x=1, y=5},
    default_enabled = true,
    viewscreens     = {'dwarfmode', 'dwarfmode/', 'world/'},
    frame           = {w=ALERT_COLS, h=ALERT_ROWS},  -- 12x2 tiles = 96x24 px per state; PNG = 192x24 px
}

function HeraldAlert:init()
    self._use_png = false
    local np, hp = load_alert_pens()
    if np then
        self._use_png = true
        self:addviews{
            AlertButton{
                frame       = {l=0, t=0, w=ALERT_COLS, h=ALERT_ROWS},
                normal_pens = np,
                hover_pens  = hp,
                on_click    = function() self:on_alert_click() end,
            }
        }
    else
        self:addviews{
            widgets.TextButton{
                frame       = {l=0, t=0},
                label       = '! Herald',
                on_activate = function() self:on_alert_click() end,
            }
        }
    end
end

function HeraldAlert:on_alert_click()
    local util = dfhack.reqscript('herald-util')
    util.clear_unread()
    dfhack.run_command('herald-main', 'gui', 'recent')
end

function HeraldAlert:render(dc)
    if not dfhack.isMapLoaded() then return end
    local util = dfhack.reqscript('herald-util')
    if not util.has_unread then return end
    HeraldAlert.super.render(self, dc)
end

OVERLAY_WIDGETS = { button = HeraldButton, alert = HeraldAlert }
