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
└── herald-util.lua              ← shared utilities (announcement wrappers, position helpers, pin settings)

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

- `announce_death(msg)` — red, pauses game (death of tracked individual or position holder)
- `announce_appointment(msg)` — yellow, pauses (new position holder)
- `announce_vacated(msg)` — white, no pause (living HF left a position)
- `announce_info(msg)` — cyan, no pause (debug/informational)

**Position helpers**:

- `name_str(field)` — normalises a position name field to a plain Lua string or `nil`; handles both `stl-string` and `string[]` layouts
- `get_pos_name(entity, pos_id, hf_sex)` — returns gendered (or neutral) position title; checks `entity.positions.own` first, falls back to `entity.entity_raw.positions`

**HF / entity helpers**:

- `is_alive(hf)` — true when `hf.died_year == -1 and hf.died_seconds == -1`
- `get_race_name(hf)` — creature species name string for an HF
- `get_entity_race_name(entity)` — same for a historical entity

**Table utilities**:

- `deepcopy(t)` — recursive deep copy of any Lua value

**Pin settings** (defined here to avoid circular deps — handlers must not reqscript herald-main):

- `INDIVIDUAL_SETTINGS_KEYS` — ordered list: `{ 'relationships', 'death', 'combat', 'legendary', 'positions', 'migration' }`
- `CIVILISATION_SETTINGS_KEYS` — ordered list: `{ 'positions', 'diplomacy', 'warfare', 'raids', 'theft', 'kidnappings' }`
- `default_pin_settings()` — returns defaults table (all `true`) for individual pins
- `default_civ_pin_settings()` — returns defaults table (all `true`) for civ pins
- `merge_pin_settings(saved)` / `merge_civ_pin_settings(saved)` — merges saved booleans over defaults; ignores unknown keys

**Standalone inspection** (when run directly from the DFHack console):

```
herald-util inspect [TYPENAME]
```

Prints all fields of the first matching event collection via `printall`. Defaults to `DUEL`. Running without `inspect` lists valid type names.

### Debug Output

When `DEBUG = true`, handlers emit verbose trace lines covering:

- Untracked HFs/civs: `"is not tracked, skipping"`
- Duplicate suppression: `"already announced, skipping"`
- Announcement fired: `"firing announcement … (setting is ON)"`
- Announcement suppressed: `"announcement suppressed … (setting is OFF)"`

### Event History (GUI)

`herald-event-history.lua` contains the event-display subsystem used by the EventHistory popup
(Ctrl-E). It is required by `herald-gui.lua` as `local ev_hist = dfhack.reqscript('herald-event-history')`.

Exports (non-local at module scope):

- **`HF_FIELDS`** — ordered list of scalar HF ID field names (e.g. `victim_hf`, `attacker_general_hf`).
  Fallback for unknown event types in `get_hf_events` and `herald-cache`.
- **`TYPE_HF_FIELDS`** — `{ [event_type_int] = {field, ...} }` dispatch table mapping event types
  to 1-4 relevant HF fields. Reduces `safe_get` calls from ~28 to 1-4 for known types.
  Used by `herald-cache` and `get_hf_events`.
- **`safe_get(obj, field)`** — pcall-guarded field accessor; used by event describers and
  `herald-cache`.
- **`event_will_be_shown(ev)`** — calls the describer with `focal=-1`; returns false if the result
  is nil. Used by `herald-cache` to exclude noise events from counts.
- **`open_event_history(hf_id, hf_name)`** — opens (or raises) the EventHistory popup. Uses
  `widgets.FilteredList` with `search_key` for text search/filtering across events. Multi-line
  events share the same `search_key` so they filter as a group. Called via
  `ev_hist.open_event_history(...)` from `FiguresPanel` and `PinnedPanel`.

Internal (local) components:

- **`EVENT_DESCRIBE`** — `{ [event_type_int] = fn(ev, focal_hf_id) -> string }`. Populated in a
  `do` block via `add(type_name, fn)`, which silently skips unknown type names (handles DFHack
  version differences). Describers return verb-first text when focal matches a participant;
  return `nil` to suppress the event entirely.
- **`article(s)`** — returns `"a <s>"` or `"an <s>"` based on first letter.
- **`title_case(s)`** — converts `ALL_CAPS_ENUM_NAME` to `"All Caps Enum Name"`.
- **`artifact_name_by_id(art_id)`** — resolves an artifact ID to its translated name and item
  description (material + type, e.g. "copper sword"). Returns `(name_or_nil, item_desc_or_nil)`.
  pcall-guarded, returns nil on failure.
- **`building_name_at_site(site_id, structure_id)`** — resolves a structure within a site to its
  translated building name by scanning `site.buildings`. pcall-guarded.
- **`get_hf_events(hf_id)`** — event collection for the popup. Uses `herald-cache` event IDs
  when available (O(n) lookups per HF); falls back to full world scan if cache not ready.
  Relationship events always scanned from block store. Contextual `WAR_FIELD_BATTLE`
  aggregation only runs in fallback path. Also builds and returns a `ctx_map`
  (event_id -> best collection) via `build_event_to_collection()`.
  Returns `(results, ctx_map)`.
  **Note:** battle participation via contextual aggregation is implemented but unconfirmed —
  see the TODO comment above `get_hf_events`.
- **`format_event(ev, focal_hf_id, ctx_map)`** — renders `"In the year NNN, ..."` using
  `EVENT_DESCRIBE` or `clean_enum_name` fallback. When `ctx_map` is provided and the event
  type is in `CTX_TYPES`, appends a collection context suffix (e.g. "as part of a duel
  between X and Y") via `describe_collection`.
- **`BATTLE_TYPES` set pattern** — used in both `get_hf_events` and `build_hf_event_counts` to
  resolve `HF_SIMPLE_BATTLE_EVENT` / `HIST_FIGURE_SIMPLE_BATTLE_EVENT` across DFHack versions.
  Always use a set (`{ [v] = true }`) not a single value with `or`.

**Event collection context** (local to `herald-event-history.lua`):

- **`COLLECTION_PRIORITY`** — `{ [collection_type_int] = priority }` mapping. Lower number =
  more specific context. DUEL(1) > BEAST_ATTACK(2) > ... > CEREMONY(13).
- **`build_event_to_collection()`** — scans `event_collections.all` once, builds
  `{ [event_id] = best_collection }` keeping highest-priority collection per event.
  Called once per popup open inside `get_hf_events`.
- **`describe_collection(col, skip_site)`** — returns human-readable context suffix string
  (e.g. "during The Scraped Conflict") for 13+ collection types. `skip_site=true` omits site
  info to avoid duplication with the base description. All field access pcall-guarded.
  Unverified types (RAID, THEFT, INSURRECTION, PURGE) use safe_get fallback chains.
- **`CTX_TYPES`** — `{ [event_type_int] = fn(ev)->bool }` table of event types that receive
  collection context. The function returns true when site should be skipped in the suffix.
  Covers 11 event type names (8 distinct types accounting for version aliases).

### Event Cache (`herald-cache.lua`)

Persistent cache layer that maps events to HF IDs. Eliminates the O(n \* 28) pcall scan
on every GUI open by caching results in the save file via `dfhack.persistent.saveSiteData`.

**Persist key:** `herald_event_cache`

**Exports (non-local at module scope):**

- `cache_ready` — boolean; true once loaded/built
- `building` — boolean; true during full build
- `load_cache()` — read from persistence, validate watermark
- `save_cache()` — write to persistence
- `invalidate_cache()` — clear all, force rebuild
- `build_full(on_done)` — full scan of all events; calls `on_done()` when complete
- `build_delta()` — incremental from watermark; returns count of new events
- `needs_build()` — true if cache is empty/invalid
- `get_all_hf_event_counts()` — `{ [hf_id] = count }` (events + relationships merged)
- `get_hf_event_ids(hf_id)` — sorted event ID list for Event History popup
- `get_hf_total_count(hf_id)` — events + relationships for a single HF
- `reset()` — cleanup on world unload

**Dependencies:** Requires `herald-event-history` only (for `HF_FIELDS`, `TYPE_HF_FIELDS`,
`safe_get`, `event_will_be_shown`). Does NOT require `herald-main` or any handler module.

**Lifecycle:** `load_cache()` called in `herald-main.init_scan()`; `reset()` called in
`herald-main.cleanup()`. GUI calls `build_delta()` on open, or shows a warning dialog
and calls `build_full()` if cache is not ready.

**CLI:** `herald-main cache-rebuild` invalidates the cache; next GUI open triggers rebuild.

### Settings & Persistence

Settings screen (`herald-gui.lua`): 3-tab window — Ctrl-T to cycle tabs. Footer always shows
Ctrl-J (open DFHack Journal), Ctrl-C (refresh cache), and Escape (close).

- **Pinned** (tab 1): left list of pinned individuals or civs; Ctrl-I toggles Individuals/
  Civilisations view. Right panel shows per-pin announcement toggles (unimplemented categories
  marked `*`). Ctrl-E opens Event History. Enter unpins the selection.
- **Historical Figures** (tab 2): Name/Race/Civ/Status/Events list with detail panel. Enter to
  pin/unpin; Ctrl-E event history; Ctrl-D show-dead; Ctrl-P pinned-only.
- **Civilisations** (tab 3): full civ list. Enter to pin/unpin; Ctrl-P pinned-only.

**Global config** (`dfhack-config/herald.json`):

```json
{
  "tick_interval": 1200,
  "debug": false,
  "announcements": {
    "individuals": {
      "relationships": true,
      "death": true,
      "combat": true,
      "legendary": true,
      "positions": true,
      "migration": true
    },
    "civilisations": {
      "positions": true,
      "diplomacy": true,
      "warfare": true,
      "raids": true,
      "theft": true,
      "kidnappings": true
    }
  }
}
```

**Per-save config** (`dfhack.persistent.getSiteData/saveSiteData`):

- Individuals: key `herald_pinned_hf_ids`; settings keys: `relationships`, `death`, `combat`, `legendary`, `positions`, `migration`
- Civilisations: key `herald_pinned_civ_ids`; settings keys: `positions`, `diplomacy`, `warfare`, `raids`, `theft`, `kidnappings`
- Schema: `{ "pins": [ { "id": <int>, "settings": { <key>: <bool>, ... } } ] }`
- All defaults are `true`; old saves with missing keys are filled by `merge_pin_settings` / `merge_civ_pin_settings` in herald-util

### Overlay Button

`herald-button.lua` lives in `scripts_modinstalled/` and is auto-loaded by DFHack via the mod
install mechanism (not `onLoad.init`). It registers `OVERLAY_WIDGETS = { button = HeraldButton }`.

- `HeraldButton` extends `overlay.OverlayWidget`; default position `{x=10, y=1}`, shown on
  `'dwarfmode'`, frame `{w=4, h=3}`.
- On click it runs `dfhack.run_command('herald-main', 'gui')`.
- Logo loaded from `herald-logo.png` (same directory as the script) via
  `dfhack.textures.loadTileset(path, 8, 12, true)` — 8×12 px/tile, 4 cols × 3 rows per state.
  Left half of the PNG = normal state; right half = hover/highlighted state.
- If the PNG fails to load, falls back to a plain `widgets.TextButton` labelled "Herald".

## DFHack Console Debugging

When the correct field name, struct layout, or viewscreen path is unknown, use the DFHack
console to inspect live game data rather than guessing or searching documentation:

- **Viewscreen focus string** (run while target screen is active):
  `lua printall(dfhack.gui.getCurFocus())`
  → e.g. `'world/NORMAL'` means viewscreen entry `'world/'`; `'dwarfmode'` prefix-matches all dwarfmode sub-screens.
- **Struct fields** (inspect any live object):
  `lua printall(<object>)` — e.g. `lua printall(df.global.world.entity_populations[0])`
- **Overlay viewscreens confirmed**:
  - Fort mode (all sub-screens): `'dwarfmode'` (prefix match; `'dwarfmode/'` is redundant)
  - World map (fort mode overworld): `'world/'`

## DF API Reference

### Critical Conventions (Read First)

**DF vectors are 0-indexed.** All DF data vectors use 0-based indexing. `#vec` returns the
element count. Always iterate `for i = 0, #vec - 1 do ... vec[i] ... end`, or use
`ipairs(vec)` which DFHack adapts to 0-based. Never assume `vec[1]` is the first element.

**Virtual methods, not `.type` fields.** DFHack typed structs use virtual dispatch. Always call
`:getType()` to read the type discriminator. Direct `.type` field access does NOT exist on most
concrete subtypes and will error or return nil. Applies to: events (`ev:getType()`), entity
links (`link:getType()`), event collections (`col:getType()`).

**DFHack's `__index` raises on absent fields.** Accessing a field that doesn't exist on a typed
DF struct throws an error (not nil). Use `pcall` / `safe_get(obj, field)` when the field might
not exist on a given event subtype or across DFHack versions.

**Sentinel value `-1` means "none/unset".** HF IDs, entity IDs, `died_year`, `died_seconds`,
`histfig2`, site IDs, etc. all use `-1` to mean absent/unset. Always check `>= 0` before using
as a valid reference. Never treat `-1` as a valid lookup key.

**String fields come in two formats.** DF stores names as either:

- `stl-string`: plain Lua string (e.g. `pos.name` in `entity.positions.own`)
- `string[]`: 0-indexed array (e.g. `pos.name[0]` in `entity.entity_raw.positions`,
  `cr.name[0]` in creature_raw)

Use `herald-util.name_str(field)` to normalise either format to a plain string or nil.

**`language_name` structs must be translated.** Entity, HF, and site names are `language_name`
structs, not plain strings. Always call `dfhack.translation.translateName(obj.name, true)` to
get the English translation. The second arg `true` = "in English" (vs the DF language).

### Global Data Paths

- **Ticks:** `df.global.cur_year_tick`
- **Player civ:** `df.global.plotinfo.civ_id`
- **All entities:** `df.global.world.entities.all` (vector of `historical_entity`)
- **All HFs:** `df.global.world.history.figures` (vector of `historical_figure`)
- **All events:** `df.global.world.history.events` (vector; indexed by **position**, NOT by event ID)
- **Event by ID:** `df.history_event.find(id)` (slow linear search; avoid in loops)
- **Relationship events:** `df.global.world.history.relationship_events` (block store; see below)
- **World sites:** `df.global.world.world_data.sites` (vector of `world_site`)
- **Entity populations:** `df.global.world.entity_populations` (vector; non-HF racial groups)

### Historical Figure (HF) Struct

```
hf = df.historical_figure.find(hf_id)
hf.id             -- unique ID (int)
hf.name           -- language_name struct (use translateName)
hf.sex            -- 1 = male, 0 = female
hf.race           -- creature race ID (int); lookup: df.creature_raw.find(hf.race).name[0]
hf.died_year      -- -1 if alive, else year of death
hf.died_seconds   -- -1 if alive, else timestamp of death
hf.entity_links   -- vector of histfig_entity_link (see Entity Links below)
```

**Alive check:** `hf.died_year == -1 and hf.died_seconds == -1` (use `herald-util.is_alive(hf)`)

### HF Entity Links

Each link is a polymorphic struct. Field access rules:

```
link = hf.entity_links[i]
link:getType()     -- returns histfig_entity_link_type enum (MEMBER, POSITION, etc.)
link.entity_id     -- the entity this link refers to

-- WRONG: link.type         -- field does NOT exist on concrete subtypes
-- WRONG: link.link_type    -- not a field
```

Link type enum: `df.histfig_entity_link_type.MEMBER`, `.POSITION`, etc.

### Historical Entity Struct

```
entity = df.historical_entity.find(entity_id)
entity.id          -- unique ID (int)
entity.name        -- language_name struct
entity.type        -- df.historical_entity_type (Civilization, SiteGovernment, etc.)
entity.race        -- creature race ID (int)
entity.positions   -- T_positions sub-struct (see below)
entity.histfig_ids -- vector of HF IDs that are/were members (pcall-guard; may vary by type)
entity.entity_raw  -- entity_raw (template data; may be nil)
```

### Position System

**Two sources for position names** (check both in order):

1. `entity.positions.own` - `entity_position` objects with plain stl-string name fields:
   `pos.name`, `pos.name_male`, `pos.name_female`. Preferred source.
   **Empty for EVIL/PLAINS entity types.**

2. `entity.entity_raw.positions` - `entity_position_raw` objects with `string[]` name fields:
   `pos.name[0]`, `pos.name_male[0]`, `pos.name_female[0]`. Fallback for EVIL/PLAINS.

Use `herald-util.get_pos_name(entity, pos_id, hf_sex)` which handles both sources.

**Position assignments:**

```
asgn = entity.positions.assignments[i]
asgn.id           -- assignment ID (stable across cycles; used as snapshot key)
asgn.position_id  -- references pos.id in entity.positions.own / entity.entity_raw.positions
asgn.histfig2     -- HF ID of the current holder (-1 if vacant)

-- WRONG: asgn.histfig      -- not the holder field
-- WRONG: asgn.hf_id        -- not a field
-- WRONG: asgn.holder       -- not a field
```

### History Events

Events are indexed by **array position** in `df.global.world.history.events`, NOT by their `.id`
field. Event IDs are non-contiguous; always use `df.history_event.find(id)` for ID-based lookup
outside of sequential scans.

```
ev = events[i]
ev.id              -- unique event ID (int; NOT equal to array index)
ev:getType()       -- returns df.history_event_type enum
ev.year            -- year the event occurred
ev.seconds         -- timestamp within the year

-- WRONG: ev.type            -- not a field; use :getType()
-- WRONG: events[event_id]   -- events are NOT indexed by ID
```

**Per-event-type fields** (field names vary by event subtype):

- `HIST_FIGURE_DIED`: `ev.victim_hf`, `ev.slayer_hf`, `ev.death_cause`, `ev.site`
- `HF_SIMPLE_BATTLE_EVENT`: `ev.group1` (vector), `ev.group2` (vector), `ev.subtype`
- `COMPETITION`: `ev.competitor_hf` (vector), `ev.winner_hf` (vector)
- `CHANGE_HF_STATE`: `ev.hfid`, `ev.state`, `ev.substate`, `ev.reason`, `ev.site`
- `CHANGE_HF_JOB`: `ev.hfid`, `ev.old_job`, `ev.new_job`, `ev.site`
- `ADD_HF_ENTITY_LINK`: `ev.histfig`, `ev.civ`, `ev.link_type`, `ev.position_id`
- `HF_DOES_INTERACTION`: `ev.doer`, `ev.target`, `ev.interaction_action`
- `HIST_FIGURE_ABDUCTED`: `ev.snatcher`, `ev.target`
- `MASTERPIECE_CREATED_*`: `ev.maker`, `ev.maker_entity`, `ev.item_type`, `ev.item_subtype`
- `ARTIFACT_CREATED`: `ev.creator_hfid`
- `ARTIFACT_STORED`: `ev.histfig`, `ev.artifact_id` (or `artifact_record`), `ev.site`
- `ARTIFACT_CLAIM_FORMED`: `ev.artifact`, `ev.histfig`, `ev.entity`, `ev.claim_type`
- `ITEM_STOLEN`: `ev.histfig`, `ev.item_type`, `ev.mattype`, `ev.matindex`, `ev.entity`, `ev.site`
- `ASSUME_IDENTITY`: `ev.trickster`, `ev.identity`, `ev.target`
- `GAMBLE`: `ev.hf`, `ev.site`, `ev.structure`, `ev.account_before`, `ev.account_after`
- `ENTITY_CREATED`: `ev.entity`, `ev.site`, `ev.structure`, `ev.creator_hfid`
- `FAILED_INTRIGUE_CORRUPTION`: `ev.corruptor_hf`, `ev.target_hf`, `ev.site`
- `HF_ACT_ON_BUILDING`: `ev.histfig`, `ev.action` (0=profaned, 2=prayed), `ev.site`, `ev.structure`
- `CREATED_SITE`/`CREATED_STRUCTURE`: `ev.builder_hf`

For a full mapping see `TYPE_HF_FIELDS` in `herald-event-history.lua`. When the field name is
uncertain, always use `safe_get(ev, field)` (pcall-guarded) rather than direct access.

**DFHack version aliases:** Some event types have multiple names across versions:

- `HF_SIMPLE_BATTLE_EVENT` / `HIST_FIGURE_SIMPLE_BATTLE_EVENT` - always check both

### Relationship Events (Block Store)

`df.global.world.history.relationship_events` is NOT a simple vector - it's a block store with
a different access pattern:

```
rel_evs = df.global.world.history.relationship_events
block = rel_evs[block_idx]
block.next_element             -- number of valid entries in this block
block.source_hf[k]            -- parallel array: source HF ID
block.target_hf[k]            -- parallel array: target HF ID
block.relationship[k]         -- parallel array: relationship type enum
block.year[k]                 -- parallel array: year of relationship event
```

Iterate: outer loop over blocks `0..#rel_evs-1`, inner loop `0..block.next_element-1`.
All field accesses should be pcall-guarded as the struct layout varies across DFHack versions.

### Event Collections

```
all = df.global.world.history.event_collections.all   -- ALWAYS index .all, never the struct itself
col = all[i]
col:getType()                  -- df.history_event_collection_type enum
col.events[j]                  -- stores EVENT IDs (not array positions); match against ev.id
col.collections                -- child collection IDs (NOT .child_collections)
col.parent_collection          -- parent collection ID; WAR->BATTLE->DUEL nesting
col.name                       -- language_name (WAR and BATTLE only)

-- WRONG: col.type             -- use :getType()
-- WRONG: col.child_collections -- field is named .collections
-- WRONG: event_collections[i] -- must go through .all
```

**Collection by ID:** `df.history_event_collection.find(id)`

**Per-type key fields** (probe-verified, 250yr save):

| Type | Key fields | Notes |
|---|---|---|
| DUEL | `attacker_hf` scalar, `defender_hf` scalar, `site` scalar | |
| BEAST_ATTACK | `attacker_hf` **vector** `[0]`, `site` scalar | |
| ABDUCTION | `snatcher_hf`/`victim_hf` **vectors**, `attacker_civ` scalar, `site` | NOT `attacker_hf`/`target_hf` |
| BATTLE | `name`, `attacker_civ`/`defender_civ` **vectors**, `site` scalar | `attacker_civ` may be empty |
| SITE_CONQUERED | `attacker_civ`/`defender_civ` **vectors**, `site` scalar | no `new_civ_id` |
| WAR | `name`, `attacker_civ`/`defender_civ` **vectors** | no `site` |
| PERSECUTION | `entity` scalar (persecutor), `site` scalar | |
| ENTITY_OVERTHROWN | `entity` scalar (overthrown), `site` scalar | |
| JOURNEY | `traveler_hf` **vector**, no `site` | |
| OCCASION/COMPETITION/PERFORMANCE/PROCESSION/CEREMONY | `civ` scalar, no `site` | |
| RAID/THEFT/INSURRECTION/PURGE | unverified (absent from test save) | use `safe_get` guards |

Civ/entity fields use `attacker_civ`/`defender_civ` naming (NOT `attacking_entity`/`defending_entity`)
across all collection types.

### World Sites

```
site = df.global.world.world_data.sites[i]
site.civ_id        -- original owning civ (may be stale after conquest)
site.cur_owner_id  -- current owner entity ID (may be a SiteGovernment, not a Civ)
site.name          -- language_name struct
```

`cur_owner_id` may point to a SiteGovernment. `build_civ_choices()` in `herald-gui.lua` resolves
SiteGovernments to parent Civilizations via 5-tier fallback:

1. `cur_owner_id` is directly a Civilization
2. SiteGov -> position holder HF (`positions.assignments[].histfig2`) -> MEMBER link -> Civ
3. SiteGov -> `histfig_ids` members -> MEMBER/FORMER_MEMBER link -> Civ (catches vacant positions)
4. SITE_CONQUERED event collections -> `attacker_civ[0]` (most recent conquest wins)
5. `site.civ_id` (original/founding civ; last resort, may be stale after conquest)

### Entity Populations

```
ep = df.global.world.entity_populations[i]
ep.civ_id          -- parent civilisation entity ID
ep.races           -- vector of creature race IDs (parallel to ep.counts)
ep.counts          -- vector of population counts (0-indexed; NO count_min field)
```

Sum `ep.counts[j]` across all entries matching a civ_id for total population.

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
- When making changes to the codebase, update this CLAUDE.md file to reflect any new or changed architecture, exports, data structures, patterns, or conventions. Keep documentation accurate and in sync with the code. Try to keep documentation as lean and neat as possible.

## Future (on request only)

- Adventure mode handler category
- Legendary citizen tracking (notable deeds of fort-born figures)
- War progress summaries (casualty totals after battles)
