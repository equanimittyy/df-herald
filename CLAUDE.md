# Dwarf Fortress Herald

DFHack mod (Lua, v50+ Steam) - scans world history for significant events and notifies the player in-game.

**Stack:** Dwarf Fortress Steam (v50.xx) + DFHack (latest stable), Lua. Ref: https://docs.dfhack.org/

## File Structure

```
scripts_modactive/
  onLoad.init              ← auto-enables mod on world load
  herald-main.lua          ← event loop, dispatcher; add new event types here
  herald-gui.lua           ← settings UI (Recent / Pinned / Historical Figures / Civilisations)
  herald-event-history.lua ← Event History popup subsystem (describers, collection context)
  herald-cache.lua         ← persistent event cache (HF event counts + IDs, delta processing)
  herald-ind-death.lua     ← HIST_FIGURE_DIED + poll handler for pinned individuals
  herald-world-leaders.lua ← poll-based world leader tracking [Civilisations]
  herald-util.lua          ← shared utilities (announcements, recent history, position helpers, pin settings)
  herald-probe.lua         ← debug utility for inspecting live DF data

scripts_modinstalled/
  herald-button.lua        ← DFHack overlay widgets (Herald button + alert on main screen)
  herald-logo.png          ← 64x36 px sprite sheet (two 32x36 states: normal | hover)
```

Each event type in its own `herald-<type>.lua`. Event-driven: `check(event, dprint)` via `get_handlers()`. Poll-based: `check(dprint)` + `reset()` via `get_world_handlers()`.

## Handlers

- **Individuals** - event-driven (in-fort, per `df.history_event_type.*`) and poll-based (off-screen, checks HF state directly for deaths since the game may skip generating events).
- **Civilisations** - poll-based only; snapshots civ state each cycle, detects changes by diff.

## Module Requirements

1. `--@ module=true` at top (required for `dfhack.reqscript`; omitting throws "Cannot be used as a module")
2. `--[====[` docblock ending with "Not intended for direct use."
3. Exports at module scope (no `local`, no wrapper table) - `dfhack.reqscript` returns the env table
4. Each handler has its own isolated env, so `check` in every handler is safe
5. `herald-main.lua` uses `--@ enable=true`; all others use `--@ module=true` only

## Architecture

**Event loop:** `dfhack.timeout(tick_interval, 'ticks', cb)` - default 1200 ticks (1 dwarf day), min 600. Fires once only - `scan_events` must reschedule; early return kills the loop. `onStateChange`: start on `SC_MAP_LOADED`, stop on `SC_MAP_UNLOADED`. Ticks-mode timers auto-cancelled on unload.

**Event scanning:** Incremental from `last_event_id + 1` (never re-scan from 0). Dispatch by `event:getType()`. Keep checks in separate scripts per event type. Implemented: `HIST_FIGURE_DIED` (`event.victim_hf`).

**Civ polling:** `scan_world_state(dprint)` calls all `get_world_handlers()` each cycle. `herald-world-leaders.lua` snapshots `{ [entity_id] = { [assignment_id] = { hf_id, pos_name, civ_name } } }` to detect deaths/appointments.

### herald-util.lua

Shared module, all exports non-local at module scope.

- **Announcements** (use these, never `dfhack.gui.showAnnouncement` directly): `announce_death` (red, pause), `announce_appointment` (yellow, pause), `announce_vacated` (white), `announce_info` (cyan). Each also pushes to the recent ring buffer.
- **Recent history:** `RECENT_PERSIST_KEY`, `MAX_RECENT=10`, `has_unread` (exported bool). `load_recent()`/`save_recent()`/`reset_recent()`/`get_recent_announcements()`/`clear_unread()`
- **Position helpers:** `name_str(field)` normalises stl-string/string[] to string; `get_pos_name(entity, pos_id, hf_sex)` returns gendered title
- **HF/entity:** `is_alive(hf)`, `get_race_name(hf)`, `get_entity_race_name(entity)`, `deepcopy(t)`
- **Pin settings** (here to avoid circular deps): `INDIVIDUAL_SETTINGS_KEYS` = `{relationships, death, combat, legendary, positions, migration}`, `CIVILISATION_SETTINGS_KEYS` = `{positions, diplomacy, warfare, raids, theft, kidnappings}`, `default_pin_settings()`/`default_civ_pin_settings()` (all true), `merge_pin_settings(saved)`/`merge_civ_pin_settings(saved)`

### Detailed Docs (read on demand)

- **`docs/df-api-reference.md`** — DF API conventions, structs, event fields, collections, world sites
- **`docs/event-history.md`** — Event History popup exports/internals, collection context, civ events
- **`docs/gui-and-config.md`** — Cache, GUI tabs/hotkeys, config schema, persistence, overlay button

## DFHack Console Debugging

- Focus string: `lua printall(dfhack.gui.getCurFocus())`
- Struct fields: `lua printall(<object>)`
- herald-probe: edit `herald-probe.lua`, then `herald-main debug true` + `herald-main probe`

## Rules

- Graphics-compatible UI only (no legacy text-mode)
- Guard with `dfhack.isMapLoaded()` before scanning
- Never re-scan from event ID 0; always incremental
- Keep UI/logic/event-history in separate files
- Use `DEBUG` not `debug` (`debug` shadows Lua built-in, always truthy)
- No em-dashes in printed strings; DF can't render them. Use `-`
- Comments: lean, logical, human-readable
- Update CLAUDE.md + relevant docs/ files when changing architecture/exports/conventions
- **Docs hygiene:** CLAUDE.md and docs/ must stay compact. No prose, no repetition, no examples that duplicate what the code shows. Use terse reference style (signatures, key names, one-line descriptions). If a section grows beyond its current density, refactor or split to a docs/ file and link it. Every line must earn its place - if removing it wouldn't cause a mistake, remove it.

## Future (on request only)

- Adventure mode handler category
- Legendary citizen tracking
- War progress summaries
