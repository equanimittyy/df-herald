-- DFHack Lua environment: df/dfhack/etc. are injected at runtime.
-- Module exports are non-local top-level variables (dfhack.reqscript convention).

std = "lua52"
allow_defined_top = true
max_line_length = 120

-- Module exports are consumed cross-file via dfhack.reqscript;
-- luacheck can't see cross-file usage, so suppress unused-global warnings.
ignore = {"131"}

read_globals = {
    "df",
    "defclass",
    "DEFAULT_NIL",
    "COLOR_BLACK", "COLOR_BLUE", "COLOR_GREEN", "COLOR_CYAN",
    "COLOR_RED", "COLOR_MAGENTA", "COLOR_BROWN", "COLOR_GREY",
    "COLOR_DARKGREY", "COLOR_LIGHTBLUE", "COLOR_LIGHTGREEN", "COLOR_LIGHTCYAN",
    "COLOR_LIGHTRED", "COLOR_LIGHTMAGENTA", "COLOR_YELLOW", "COLOR_WHITE",
    "SC_MAP_LOADED", "SC_MAP_UNLOADED",
    "printall",
}

globals = {
    "dfhack",
    "enabled",
    "view",
    "OVERLAY_WIDGETS",
}
