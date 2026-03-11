# Dwarf Fortress Herald

DFHack mod (Lua, v50+ Steam) - scans world history for significant events and notifies the player in-game.

**Stack:** Dwarf Fortress Steam (v50.xx) + DFHack (latest stable), Lua. Ref: https://docs.dfhack.org/

## File Structure

```
scripts_modactive/
  onLoad.init              ← auto-enables mod on world load
  herald.lua               ← event loop, dispatcher, CLI (the only visible command)
  herald-gui.lua           ← settings UI (Recent / Pinned / Historical Figures / Civilisations / Artifacts)
  herald-event-history.lua ← Event History popup subsystem (describers, collection context)
  herald-cache.lua         ← persistent event cache (HF/civ/artifact event counts + IDs, delta processing)
  herald-util.lua          ← shared utilities (announcements, recent history, position helpers, pin settings)
  herald-probe.lua         ← debug utility for inspecting live DF data
  herald-handler-contract.lua ← handler contract factory (no-op defaults for all handler fields)
  herald-pins.lua            ← shared pinned-HF state (persistence, get/set, settings)
  herald-civ-pins.lua        ← shared pinned-civ state (persistence, get/set, settings)
  herald-handlers/
    herald-ind-death.lua          ← HIST_FIGURE_DIED + BODY_ABUSED(victim) + poll for pinned individuals
    herald-ind-combat.lua         ← event-driven (combat, site attacks, overthrows, body abuse) + poll (fort kills)
    herald-ind-skills.lua         ← poll-based legendary skill detection for pinned individuals
    herald-ind-positions.lua      ← poll-based position appointment/vacation tracking for pinned individuals
    herald-ind-migration.lua      ← event-driven (world relocation) + poll (fort arrival/departure)
    herald-ind-relationships.lua  ← event-driven relationship events (marriage, apprentice, deity, intrigue)
    herald-ind-artifacts.lua      ← event-driven artifact/written work tracking for pinned individuals
    herald-world-leaders.lua      ← poll-based world leader tracking [Civilisations]
    herald-world-diplomacy.lua    ← hybrid event+poll diplomacy and warfare [Civilisations]
    herald-world-rampages.lua     ← poll-based beast attack tracking [Civilisations]
    herald-world-espionage.lua    ← poll-based espionage (theft, abduction) [Civilisations]

scripts_modinstalled/
  herald-button.lua        ← DFHack overlay widgets (Herald button + alert on main screen)
  herald-logo.png          ← 64x36 px sprite sheet (two 32x36 states: normal | hover)
```

Each handler in its own `herald-<type>.lua` under `herald-handlers/`. Handlers call `contract.apply(_ENV)` at the bottom and override contract fields they need. `herald.lua` registers handler paths in `handler_paths` and auto-wires based on exported fields.

## Handlers

- **Individuals (death)** - event-driven (HIST_FIGURE_DIED, BODY_ABUSED victim) + poll (off-screen death detection).
- **Individuals (combat)** - event-driven (combat, site attacks, overthrows, body abuse) + poll (fort-level kills via hf.info.kills baseline).
- **Individuals (skills)** - poll-based; detects legendary skill achievement.
- **Individuals (positions)** - poll-based; detects position appointments/vacations via entity_links.
- **Individuals (migration)** - event-driven (world relocation) + poll (fort arrival/departure via units.active).
- **Individuals (relationships)** - event-driven only; marriage, divorce, apprenticeship, deity worship, intrigue.
- **Civilisations (leaders)** - poll-based only; snapshots civ state each cycle, detects changes by diff.
- **Civilisations (diplomacy)** - hybrid event+poll; peace/agreements/tribute (event-driven) + WAR/BATTLE/RAID collections (poll-based) + site takeover/destruction/new leadership (event-driven).
- **Individuals (artifacts)** - event-driven; artifact creation, storage, claiming, theft, written works by pinned HFs.
- **Civilisations (rampages)** - poll-based; detects new BEAST_ATTACK collections targeting pinned civ sites.
- **Civilisations (espionage)** - poll-based; detects new THEFT/ABDUCTION collections involving pinned civs.

## Module Requirements

1. `--@ module=true` at top (required for `dfhack.reqscript`; omitting throws "Cannot be used as a module")
2. `--[====[` docblock ending with "Not intended for direct use."
3. Exports at module scope (no `local`, no wrapper table) - `dfhack.reqscript` returns the env table
4. Each handler has its own isolated env, so `check` in every handler is safe
5. `herald.lua` uses `--@ enable=true`; all others use `--@ module=true` only

## Architecture

**Event loop:** `dfhack.timeout(tick_interval, 'ticks', cb)` - default 1200 ticks (1 dwarf day), min 600. Fires once only - `scan_events` must reschedule; early return kills the loop. Ticks-mode timers auto-cancelled on unload.

**Lifecycle:** `world_initialized` flag distinguishes adventure-mode map transitions from full game loads. `SC_MAP_LOADED` with `world_initialized=false` -> `init_scan()` (full init); with `true` -> `resume_scan()` (lightweight). `SC_MAP_UNLOADED` -> `pause_scan()` (lightweight). `SC_WORLD_UNLOADED` -> `cleanup()` (full reset, clears `world_initialized`). `pause_scan` invalidates unit/entpop caches and dismisses event history; `resume_scan` calls `on_resume` on all handlers and restarts the timer. `last_event_id` is preserved across travel so events during transit are caught.

**Event scanning:** Incremental from `last_event_id + 1` (never re-scan from 0). Dispatch by `event:getType()` through `event_map`. Keep checks in separate scripts per event type.

**Handler contract** (`herald-handler-contract.lua`): `apply(env)` installs no-op defaults for `event_types`, `polls`, `init`, `reset`, `on_resume`, `check_event`, `check_poll`. Handlers override what they need; `herald.lua` iterates without nil checks. `on_resume(dprint)` is called after adventure-mode map transitions for lightweight re-baselining (only `herald-ind-migration` overrides it currently). To add a handler: create the script, add its path to `handler_paths` in `herald.lua`, export contract fields, call `contract.apply(_ENV)` at the bottom.

**Civ polling:** `scan_world_state(dprint)` calls `check_poll` on all handlers where `polls` is truthy. `herald-world-leaders.lua` snapshots `{ [entity_id] = { [assignment_id] = { hf_id, pos_name, civ_name } } }` to detect deaths/appointments.

### herald-util.lua

Shared module, all exports non-local at module scope.

- **Announcements** (use these, never `dfhack.gui.showAnnouncement` directly): `announce_death` (red), `announce_combat` (light red), `announce_appointment` (yellow), `announce_vacated` (white), `announce_info` (cyan), `announce_migration` (green), `announce_relationship` (light magenta), `announce_legendary` (light green), `announce_espionage` (magenta), `announce_artifact` (yellow), `announce_rampage` (magenta). Push to recent ring buffer only (no DF announcement bar); alert overlay notifies the player.
- **Unit iteration:** `for_each_pinned_unit(pinned, callback)` — walks `units.active`, yields `(unit, hf_id, settings)` per pinned HF. Used by handler init baselines and polls.
- **Recent history:** `RECENT_PERSIST_KEY`, `MAX_RECENT=20`, `has_unread` (exported bool). `load_recent()`/`save_recent()`/`reset_recent()`/`get_recent_announcements()`/`clear_unread()`
- **Position helpers:** `name_str(field)` normalises stl-string/string[] to string; `get_pos_name(entity, pos_id, hf_sex)` returns gendered title
- **HF/entity:** `ent_name(entity_id)`, `hf_name(hf_id)`, `is_alive(hf)`, `get_race_name(hf)`, `get_entity_race_name(entity)`, `deepcopy(t)`, `safe_get(obj, field)`
- **Artifact item:** `resolve_item_type_material(item)` -> `(type_s, mat_s, is_written)` — shared subtype-aware item resolution (books/scrolls blanked)
- **Site helpers:** `site_name(site_id)` returns translated site name; `site_owner_civ(site_id)` resolves site -> owning Civilization via SiteGov entity_links, falls back to `civ_id`
- **Entity population:** `get_entpop_to_civ()` (lazy cached map), `entpop_vec_has_civ(col, field, civ_id, ep_map)`, `reset_entpop_cache()`
- **Pin settings** (here to avoid circular deps): `INDIVIDUAL_SETTINGS_KEYS` = `{relationships, death, combat, artifacts, legendary, positions, migration}`, `CIVILISATION_SETTINGS_KEYS` = `{positions, diplomacy, warfare, rampages, espionage}`, `default_pin_settings()`/`default_civ_pin_settings()` (all true), `merge_pin_settings(saved)`/`merge_civ_pin_settings(saved)`

### Detailed Docs (read on demand)

- **`docs/df-api-reference.md`** — DF API conventions, structs, event fields, collections, world sites
- **`docs/event-history.md`** — Event History popup exports/internals, collection context, civ events
- **`docs/gui-and-config.md`** — Cache, GUI tabs/hotkeys, config schema, persistence, overlay button

## DFHack Console Debugging

- Focus string: `lua printall(dfhack.gui.getCurFocus())`
- Struct fields: `lua printall(<object>)`
- herald-probe: edit `herald-probe.lua`, then `herald debug true` + `herald probe`

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

## Agents (`.claude/agents/`)

After completing a substantive code editing task (not minor one-line fixes), prompt the user to run review agents. If accepted, run all three in parallel. When all complete, present a single unified summary - not three separate reports. Deduplicate overlapping findings, group by file or theme, and keep it concise.

- **coupling-reviewer** (sonnet) — dependency direction, module boundaries, reqscript coupling, single responsibility
- **dead-code-finder** (haiku) — unused exports, redundant logic, stale code
- **robustness-reviewer** (sonnet) — DF struct safety, tick cycle resilience, save/load lifecycle, nil propagation, unbounded growth

## Future (on request only)

(none currently)
