# GUI, Config & Cache

## Event Cache (`herald-cache.lua`)

Persistent cache layer that maps events to HF IDs. Eliminates the O(n * 28) pcall scan
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
- `get_civ_event_ids(civ_id)` — position/entity event IDs for a civ
- `get_civ_collection_ids(civ_id)` — collection IDs involving a civ
- `get_civ_total_count(civ_id)` — total events + collections for a civ
- `reset()` — cleanup on world unload

**Dependencies:** Requires `herald-event-history` only (for `HF_FIELDS`, `TYPE_HF_FIELDS`,
`safe_get`, `event_will_be_shown`, `civ_matches_collection`). Does NOT require `herald-main`
or any handler module.

**Lifecycle:** `load_cache()` called in `herald-main.init_scan()`; `reset()` called in
`herald-main.cleanup()`. GUI calls `build_delta()` on open, or shows a warning dialog
and calls `build_full()` if cache is not ready.

**CLI:** `herald-main cache-rebuild` invalidates the cache; next GUI open triggers rebuild.

## Settings & Persistence

Settings screen (`herald-gui.lua`): 3-tab window - Ctrl-T to cycle tabs. Footer always shows
Ctrl-J (open DFHack Journal), Ctrl-C (refresh cache), and Escape (close).

- **Pinned** (tab 1): left list of pinned individuals or civs; Ctrl-I toggles Individuals/
  Civilisations view. Right panel shows per-pin announcement toggles (unimplemented categories
  marked `*`). Ctrl-E opens Event History (HF or civ depending on view). Enter unpins the selection.
- **Historical Figures** (tab 2): Name/Race/Civ/Status/Events list with detail panel. Enter to
  pin/unpin; Ctrl-E event history; Ctrl-D show-dead; Ctrl-P pinned-only.
- **Civilisations** (tab 3): full civ list. Enter to pin/unpin; Ctrl-E event history; Ctrl-P
  pinned-only.

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

## Overlay Button

`herald-button.lua` lives in `scripts_modinstalled/` and is auto-loaded by DFHack via the mod
install mechanism (not `onLoad.init`). It registers `OVERLAY_WIDGETS = { button = HeraldButton }`.

- `HeraldButton` extends `overlay.OverlayWidget`; default position `{x=10, y=1}`, shown on
  `'dwarfmode'`, frame `{w=4, h=3}`.
- On click it runs `dfhack.run_command('herald-main', 'gui')`.
- Logo loaded from `herald-logo.png` (same directory as the script) via
  `dfhack.textures.loadTileset(path, 8, 12, true)` - 8x12 px/tile, 4 cols x 3 rows per state.
  Left half of the PNG = normal state; right half = hover/highlighted state.
- If the PNG fails to load, falls back to a plain `widgets.TextButton` labelled "Herald".
