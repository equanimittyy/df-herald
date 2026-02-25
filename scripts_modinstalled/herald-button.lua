--@ module=true
--[====[
herald-button
=============
Overlay widget that adds a Herald button to the main DF screen.
Not intended for direct use.
]====]

local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')

HeraldButton = defclass(HeraldButton, overlay.OverlayWidget)

HeraldButton.ATTRS{
    default_pos     = {x=10, y=1},
    default_enabled = true,
    viewscreens     = {'dwarfmode'},
    frame           = {w=8, h=1},
}

function HeraldButton:init()
    self:addviews{
        widgets.TextButton{
            frame       = {l=0, t=0},
            label       = 'Herald',
            on_activate = function() dfhack.run_command('herald-main', 'gui') end,
        }
    }
end

OVERLAY_WIDGETS = { button = HeraldButton }
