# Dwarf Fortress Herald

DFHack mod (Lua, v50+ Steam) that scans world history for significant events and notifies the player in-game.

## Tech Stack

- Dwarf Fortress Steam (v50.xx) + DFHack (latest stable)
- Language: Lua
- Ref: DFHack Modding Guide (https://docs.dfhack.org/)

## File Structure

```
scripts_modactive/
├── onLoad.init              ← auto-enables the mod when a world loads (no user action needed)
├── herald-main.lua          ← event loop, dispatcher; add new event types here
├── herald-fort-death.lua    ← HIST_FIGURE_DIED handler (leader detection + announcement) [Individuals]
└── herald-world-leaders.lua ← poll-based world leader tracking (died_year check) [Civilisations]
```

Each event type lives in its own `herald-<type>.lua` module. Event-driven Individual handlers export
`check(event, dprint)` and are registered in `get_handlers()`. Poll-based Individual and Civilisation
handlers export `check(dprint)` and `reset()`, registered in `get_world_handlers()`.

## Handler Categories

- **Individuals**: tracks events for specific historical figures. Uses two sub-modes:
  - *Event-driven* (in-fort / on-screen): called once per matching `df.history_event_type.*` event
    via the incremental scan. Interface: `check(event, dprint)`. Registered in `get_handlers()`.
  - *Poll-based* (off-screen): called once per scan cycle; snapshots HF state and detects changes
    (e.g. `hf.died_year ~= -1`). Interface: `check(dprint)` + `reset()`. Registered in
    `get_world_handlers()`.
- **Civilisations** (poll-based): called once per scan cycle regardless of events. Tracks civ-level
  state (leaders, succession, etc.). Manages its own state snapshot and detects changes by comparing
  to previous cycle. Interface: `check(dprint)` + `reset()`. Registered in `get_world_handlers()`.

Event-driven Individual handlers are reliable for in-fort occurrences. Poll-based handlers (both
Individual off-screen and Civilisation) are needed because `df.global.world.history.events` is
**unreliable** for out-of-fort changes: the game may set `hf.died_year`/`hf.died_seconds` directly
without generating a `HIST_FIGURE_DIED` event.

Every handler script **must** have, in order:

1. `--@ module=true` — required for `dfhack.reqscript`; omitting it throws "Cannot be used
   as a module" and breaks the event loop.
2. A `--[====[` docblock — same format as `herald-main`, but with no Usage/Commands/Examples
   sections and ending with "Not intended for direct use."

`dfhack.reqscript` returns the script's **environment table**, not any explicit `return`
value. Export functions by defining them at module scope (no `local`, no wrapper table):

- Correct: `function check(event, dprint) ... end`
- Wrong: `local M = {}; function M.check(...) end; return M` — `check` is never in the env

Each handler runs in its **own isolated environment**, so naming the export `check` in every
handler is safe — `herald-death`'s `check` and `herald-battle`'s `check` are separate
objects accessed via their respective handler references (`h[ev_type].check`).

`herald-main.lua` additionally has `--@ enable=true` because it is user-facing (supports
`enable`/`disable`). Handler modules use `--@ module=true` only.

## Architecture

### Event Loop

- Poll on a user-configurable tick interval via `dfhack.timeout(tick_interval, 'ticks', callback)`
  - Default: 1,200 ticks (1 dwarf day); minimum: 600 ticks (half a dwarf day)
  - Set via `herald-main interval`; persisted in `dfhack-config/herald.json` as `tick_interval`
- Handle `onStateChange`: start on `SC_MAP_LOADED`, stop on `SC_MAP_UNLOADED`
- Track `last_event_id` from `df.global.world.history.events` to avoid duplicates
- Timers in `'ticks'` mode are auto-cancelled by DFHack on world unload
- `dfhack.timeout` fires **once only**; `scan_events` must reschedule itself at the end.
  Any error or early return before the rescheduling line permanently kills the loop.

### History Event Scanning

- Iterate `df.global.world.history.events` from `last_event_id + 1` only (incremental)
- Filter by player's parent entity or user-tracked civs/entities
- Check event type via `event:getType()` vs `df.history_event_type.*` enum values

**Event Scope / Reliability**: history events are unreliable for out-of-fort occurrences.
World events (raids, battles) can still generate entries, but out-of-fort deaths may bypass
event generation entirely — the game may only set `hf.died_year`/`hf.died_seconds`. Polling
HF state directly is more reliable for civilisation-level tracking.

**Event Checks** (Keep this code separate to the event and scanning loop, one script per event check)

- Death events: `df.history_event_type.HIST_FIGURE_DIED`; victim field: `event.victim_hf` (integer hf id)

### Civilisation-Level Polling

Runs alongside the event scan each tick cycle. Civilisation handlers snapshot current state and
compare against the previous cycle to detect changes:

1. `get_world_handlers()` — lazy-init table mapping string keys to civilisation handler modules.
2. `scan_world_state(dprint)` — iterates civilisation handlers, calling `handler.check(dprint)`.
3. Called at the end of `scan_events()`, sharing the same configurable tick interval.
4. On cleanup, `handler.reset()` is called on each civilisation handler to clear snapshot state.

`herald-world-leaders.lua` uses this approach: it snapshots `{ [entity_id] = { [pos_id] = { hf_id,
pos_name, civ_name } } }` each cycle and checks `hf.died_year ~= -1` to detect leader deaths that
may have occurred without generating a `HIST_FIGURE_DIED` event.

### Notifications

- Announcement: `dfhack.gui.showAnnouncement`
- Modal popup: `gui.MessageWindow` for high-importance events

### Settings & Persistence

- UI: `require('gui')`, `require('gui.widgets')`
- Settings screen:
  - Tracked civs lists with nested with toggle categories (Succession, War, Diplomacy, Artifacts, Beasts, Site raids) + untracked civ search list
  - Tracked figures list (Death, Marraige, Children, Legendary, Artifacts) + untracked figure search list
- Global config: `dfhack-config/herald.json`
- Per-save config: `dfhack.persistent.get` / `dfhack.persistent.save`

## Key API Paths

- Ticks: `df.global.cur_year_tick`
- Events: `df.global.world.history.events`
- Entities: `df.global.world.entities.all`
- Historical figure: `df.historical_figure.find(hf_id)`
- HF entity links: `hf.entity_links[i].type` / `.entity_id`; link type enum: `df.histfig_entity_link_type.POSITION`
- Entity resolution: `df.historical_entity.find(entity_id)`
- Position assignments: `entity.positions.assignments[i]` — fields: `.id` (sequential assignment counter), `.histfig2` (HF holder), `.position_id` (position type ID)
- Position definitions — two sources, must check both:
  - `entity.entity_raw.positions` — vector of `entity_position_raw`; used by most civ types (PLAINS, etc.); name fields are `string[]`: `pos.name[0]`, `pos.name_male[0]`, `pos.name_female[0]` (singular). **Empty for EVIL/PLAINS and similar entity types.**
  - `entity.positions.own` — vector of `entity_position`; instance-level positions used by EVIL/PLAINS and other types whose `entity_raw.positions` is empty; name fields are plain `stl-string`: `pos.name`, `pos.name_male`, `pos.name_female`. Search `pos.id == assignment.position_id` in both vectors; `own` is the fallback.
- HF sex: `hf.sex` — `1`=male, `0`=female; use for gendered position name selection
- HF alive check: `hf.died_year` / `hf.died_seconds` — both `-1` when alive; any other value means dead
- Name translation: `dfhack.translation.translateName(name_obj, true)` (renamed from `dfhack.TranslateName` in v50.15+)
- Player civ id: `df.global.plotinfo.civ_id`

## Rules

- Use graphics-compatible UI only (no legacy text-mode)
- Always guard with `dfhack.isMapLoaded()` before scanning
- Never re-scan from event ID 0; always incremental
- Keep UI (`herald-gui.lua`) separate from logic (`herald-main.lua`)
- Use `DEBUG` (not `debug`) for the debug flag — `debug` shadows Lua's built-in debug library,
  making `debug = debug or false` always truthy and permanently enabling debug output

## Future (on request only)

- Adventure mode handler category
- Legendary citizen tracking (notable deeds of fort-born figures)
- War progress summaries (casualty totals after battles)
