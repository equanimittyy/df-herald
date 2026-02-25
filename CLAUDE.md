# Dwarf Fortress Herald

DFHack mod (Lua, v50+ Steam) that scans world history for significant events and notifies the player in-game.

## Tech Stack

- Dwarf Fortress Steam (v50.xx) + DFHack (latest stable)
- Language: Lua
- Ref: DFHack Modding Guide (https://docs.dfhack.org/)

## File Structure

```
scripts_modactive/
├── onLoad.init              ← auto-enables the mod on world load
├── herald-main.lua          ← event loop, dispatcher; add new event types here
├── herald-gui.lua           ← settings UI: tabbed window (Pinned / Historical Figures / Civilisations)
├── herald-ind-death.lua     ← HIST_FIGURE_DIED + poll handler for pinned individuals [Individuals]
└── herald-world-leaders.lua ← poll-based world leader tracking [Civilisations]
```

Each event type lives in its own `herald-<type>.lua` module. Event-driven handlers export
`check(event, dprint)` and register in `get_handlers()`. Poll-based handlers export
`check(dprint)` + `reset()` and register in `get_world_handlers()`.

## Handler Categories

- **Individuals** — two sub-modes:
  - *Event-driven* (in-fort): called per matching `df.history_event_type.*` event via the
    incremental scan. Interface: `check(event, dprint)`. Registered in `get_handlers()`.
  - *Poll-based* (off-screen): called each scan cycle; checks HF state directly for deaths.
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

### Debug Output

When `DEBUG = true`, handlers emit verbose trace lines covering:
- Untracked HFs/civs: `"is not tracked, skipping"`
- Duplicate suppression: `"already announced, skipping"`
- Announcement fired: `"firing announcement … (setting is ON)"`
- Announcement suppressed: `"announcement suppressed … (setting is OFF)"`

### Settings & Persistence

Settings screen (`herald-gui.lua`): 3-tab window — Ctrl-T / Ctrl-Y to navigate.

- **Pinned** (tab 1): left list of pinned individuals or civs; Ctrl-I toggles Individuals/
  Civilisations view. Right panel shows per-pin announcement toggles (unimplemented categories
  marked `*`). Enter unpins the selection.
- **Historical Figures** (tab 2): Name/Race/Civ/Status list with detail panel. Enter to
  pin/unpin; Ctrl-D show-dead; Ctrl-P pinned-only.
- **Civilisations** (tab 3): full civ list. Enter to pin/unpin; Ctrl-P pinned-only.

**Global config** (`dfhack-config/herald.json`):
```json
{ "tick_interval": 1200, "debug": false,
  "announcements": {
    "individuals":   { "death": true, "marriage": false, "children": false,
                       "migration": false, "legendary": false, "combat": false },
    "civilisations": { "positions": true, "diplomacy": false, "raids": false,
                       "theft": false, "kidnappings": false, "armies": false }
  }
}
```

**Per-save config** (`dfhack.persistent.getSiteData/saveSiteData`):
- Individuals: key `herald_pinned_hf_ids`
- Civilisations: key `herald_pinned_civ_ids`
- Schema: `{ "pins": [ { "id": <int>, "settings": { <key>: <bool>, ... } } ] }`

## Key API Paths

- Ticks: `df.global.cur_year_tick`
- Events: `df.global.world.history.events`
- Entities: `df.global.world.entities.all`
- Historical figure: `df.historical_figure.find(hf_id)`
- HF entity links: `hf.entity_links[i]:getType()` / `.entity_id`; link type enum:
  `df.histfig_entity_link_type.POSITION` — use `:getType()` (virtual method), NOT `.type`
  (not a field on concrete subtypes like `histfig_entity_link_memberst`)
- Entity resolution: `df.historical_entity.find(entity_id)`
- Position assignments: `entity.positions.assignments[i]` — `.id`, `.histfig2` (HF holder),
  `.position_id`
- Position names — two sources, check both:
  - `entity.entity_raw.positions` — `entity_position_raw`; name fields `string[]`:
    `pos.name[0]`, `pos.name_male[0]`, `pos.name_female[0]`. **Empty for EVIL/PLAINS types.**
  - `entity.positions.own` — `entity_position`; name fields plain `stl-string`: `pos.name`,
    `pos.name_male`, `pos.name_female`. Fallback for EVIL/PLAINS.
- HF sex: `hf.sex` — `1`=male, `0`=female; use for gendered position name selection
- HF alive: `hf.died_year == -1 and hf.died_seconds == -1`
- Name translation: `dfhack.translation.translateName(name_obj, true)`
- Player civ: `df.global.plotinfo.civ_id`
- Announcements: `dfhack.gui.showAnnouncement(msg, color, pause)`

## Rules

- Use graphics-compatible UI only (no legacy text-mode)
- Guard with `dfhack.isMapLoaded()` before scanning
- Never re-scan from event ID 0; always incremental
- Keep UI (`herald-gui.lua`) separate from logic (`herald-main.lua`)
- Use `DEBUG` (not `debug`) — `debug` shadows Lua's built-in, making
  `debug = debug or false` always truthy and permanently enabling debug output

## Future (on request only)

- Adventure mode handler category
- Legendary citizen tracking (notable deeds of fort-born figures)
- War progress summaries (casualty totals after battles)
