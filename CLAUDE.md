# Dwarf Fortress Herald

DFHack mod (Lua, v50+ Steam) that scans world history for significant events and notifies the player in-game.

## Tech Stack

- Dwarf Fortress Steam (v50.xx) + DFHack (latest stable)
- Language: Lua
- Ref: DFHack Modding Guide (https://docs.dfhack.org/)

## File Structure

```
scripts_modactive/
├── onLoad.init                  ← auto-enables the mod on world load
├── herald-main.lua              ← event loop, dispatcher; add new event types here
├── herald-gui.lua               ← settings UI: tabbed window (Pinned / Historical Figures / Civilisations)
├── herald-event-history.lua     ← Event History popup subsystem (event collection, describers, UI)
├── herald-cache.lua             ← persistent event cache (HF event counts + IDs, delta processing)
├── herald-ind-death.lua         ← HIST_FIGURE_DIED + poll handler for pinned individuals [Individuals]
├── herald-world-leaders.lua     ← poll-based world leader tracking [Civilisations]
├── herald-util.lua              ← shared utilities (announcement wrappers, position helpers, pin settings)
└── herald-probe.lua             ← debug utility for inspecting live DF data (requires debug mode)

scripts_modinstalled/
├── herald-button.lua            ← DFHack overlay widget; adds Herald button to the main DF screen
└── herald-logo.png              ← 64×36 px sprite sheet (two 32×36 states: normal | hover)
```

Each event type lives in its own `herald-<type>.lua` module. Event-driven handlers export
`check(event, dprint)` and register in `get_handlers()`. Poll-based handlers export
`check(dprint)` + `reset()` and register in `get_world_handlers()`.

## Handler Categories

- **Individuals** — two sub-modes:
  - _Event-driven_ (in-fort): called per matching `df.history_event_type.*` event via the
    incremental scan. Interface: `check(event, dprint)`. Registered in `get_handlers()`.
  - _Poll-based_ (off-screen): called each scan cycle; checks HF state directly for deaths.
    Interface: `check(dprint)` + `reset()`. Registered in `get_world_handlers()`.
- **Civilisations** (poll-based): called each cycle regardless of events; snapshots civ-level
  state and detects changes by comparing to the previous cycle.
  Interface: `check(dprint)` + `reset()`. Registered in `get_world_handlers()`.

Poll-based handlers are necessary because `df.global.world.history.events` is **unreliable**
for out-of-fort changes — the game may set `hf.died_year`/`hf.died_seconds` directly without
generating a `HIST_FIGURE_DIED` event.

## Module Requirements

Every handler script **must** have, in order:

1. `--@ module=true` — required for `dfhack.reqscript`; omitting throws "Cannot be used as a module".
2. A `--[====[` docblock ending with "Not intended for direct use."

`dfhack.reqscript` returns the script's **environment table** — export functions at module scope
(no `local`, no wrapper table):

- Correct: `function check(event, dprint) ... end`
- Wrong: `local M = {}; function M.check(...) end; return M` — `check` is never in the env

Each handler runs in its **own isolated environment**, so naming exports `check` in every handler
is safe — each is a separate object accessed via its handler reference. `herald-main.lua` uses
`--@ enable=true` (user-facing); all handler modules use `--@ module=true` only.

## Architecture

### Event Loop

- Poll via `dfhack.timeout(tick_interval, 'ticks', callback)`
  - Default: 1,200 ticks (1 dwarf day); minimum: 600 ticks (half a day)
  - Set via `herald-main interval`; persisted in `dfhack-config/herald.json` as `tick_interval`
- `onStateChange`: start on `SC_MAP_LOADED`, stop on `SC_MAP_UNLOADED`
- `last_event_id` tracks position in `df.global.world.history.events` to avoid duplicates
- `dfhack.timeout` fires **once only** — `scan_events` must reschedule at the end; any early
  return permanently kills the loop
- Timers in `'ticks'` mode are auto-cancelled by DFHack on world unload

### History Event Scanning

- Iterate events from `last_event_id + 1` (incremental; never re-scan from 0)
- Dispatch by `event:getType()` vs `df.history_event_type.*`; handlers apply their own filters
- Keep event checks in separate scripts, one per event type — never embed in the scan loop
- Out-of-fort deaths may not generate a history event; poll HF state directly for reliability

Implemented event checks:

- Death: `df.history_event_type.HIST_FIGURE_DIED`; victim field: `event.victim_hf` (hf id)

### Civilisation-Level Polling

Runs alongside the event scan each cycle via `scan_world_state(dprint)`:

1. `get_world_handlers()` — lazy-init map of string keys to poll-based handler modules
2. `scan_world_state(dprint)` — iterates all world handlers, calling `handler.check(dprint)`
3. On cleanup, `handler.reset()` clears snapshot state

`herald-world-leaders.lua` snapshots `{ [entity_id] = { [assignment_id] = { hf_id, pos_name,
civ_name } } }` each cycle to detect position holder deaths and new appointments.

### herald-util.lua

Shared utility module required by all other herald scripts. All exports are non-local at module scope.

**Announcement wrappers** (use these — never call `dfhack.gui.showAnnouncement` directly):

- `announce_death(msg)` — red, pauses game
- `announce_appointment(msg)` — yellow, pauses
- `announce_vacated(msg)` — white, no pause
- `announce_info(msg)` — cyan, no pause

**Position helpers**:

- `name_str(field)` — normalises a position name field to a plain Lua string or `nil`
- `get_pos_name(entity, pos_id, hf_sex)` — returns gendered (or neutral) position title

**HF / entity helpers**: `is_alive(hf)`, `get_race_name(hf)`, `get_entity_race_name(entity)`

**Table utilities**: `deepcopy(t)` — recursive deep copy

**Pin settings** (defined here to avoid circular deps):

- `INDIVIDUAL_SETTINGS_KEYS` — `{ 'relationships', 'death', 'combat', 'legendary', 'positions', 'migration' }`
- `CIVILISATION_SETTINGS_KEYS` — `{ 'positions', 'diplomacy', 'warfare', 'raids', 'theft', 'kidnappings' }`
- `default_pin_settings()` / `default_civ_pin_settings()` — returns defaults table (all `true`)
- `merge_pin_settings(saved)` / `merge_civ_pin_settings(saved)` — merges saved booleans over defaults

### Debug Output

When `DEBUG = true`, handlers emit verbose trace lines covering:

- Untracked HFs/civs: `"is not tracked, skipping"`
- Duplicate suppression: `"already announced, skipping"`
- Announcement fired: `"firing announcement … (setting is ON)"`
- Announcement suppressed: `"announcement suppressed … (setting is OFF)"`

### Event History, Cache, GUI & Config

Detailed documentation for these subsystems is in separate files — read on demand:

- **`docs/event-history.md`** — Event History popup exports, internals, collection context, civ event history
- **`docs/gui-and-config.md`** — Event cache exports/lifecycle, GUI tabs/hotkeys, global config schema, per-save persistence, overlay button
- **`docs/df-api-reference.md`** — DF API critical conventions, global data paths, HF/entity/position structs, per-event-type fields, relationship events, event collections (per-type key fields table), world sites, entity populations

## DFHack Console Debugging

- **Viewscreen focus string**: `lua printall(dfhack.gui.getCurFocus())`
- **Struct fields**: `lua printall(<object>)`
- **herald-probe**: edit `herald-probe.lua`, then `herald-main debug true` + `herald-main probe`

## Rules

- Use graphics-compatible UI only (no legacy text-mode)
- Guard with `dfhack.isMapLoaded()` before scanning
- Never re-scan from event ID 0; always incremental
- Keep UI (`herald-gui.lua`) separate from logic (`herald-main.lua`)
- Keep event history subsystem (`herald-event-history.lua`) separate from the main settings UI (`herald-gui.lua`)
- Use `DEBUG` (not `debug`) — `debug` shadows Lua's built-in, making
  `debug = debug or false` always truthy and permanently enabling debug output
- Do not use em-dashes (`—`) in any string printed to the user (announcements,
  debug output, or console `print`); DF cannot render them. Use `-` instead.
- Create comments where appropriate, ensure they are logical, human-readable and are as lean as possible to minimise token usage and clutter.
- When making changes to the codebase, update this CLAUDE.md file (and relevant docs/ files) to reflect any new or changed architecture, exports, data structures, patterns, or conventions. Keep documentation accurate and in sync with the code.

## Future (on request only)

- Adventure mode handler category
- Legendary citizen tracking (notable deeds of fort-born figures)
- War progress summaries (casualty totals after battles)
