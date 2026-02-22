# Dwarf Fortress Herald

DFHack mod (Lua, v50+ Steam) that scans world history for significant events and notifies the player in-game.

## Tech Stack

- Dwarf Fortress Steam (v50.xx) + DFHack (latest stable)
- Language: Lua
- Ref: DFHack Modding Guide (https://docs.dfhack.org/)

## File Structure

```
scripts_modactive/
├── onLoad.init       ← auto-enables the mod when a world loads (no user action needed)
└── herald-main.lua   ← event loop, scanning logic, and notifications
```

## Architecture

### Event Loop

- Poll every 8,400 ticks (1 dwarf week) via `dfhack.timeout(8400, 'ticks', callback)`
- Handle `onStateChange`: start on `SC_MAP_LOADED`, stop on `SC_MAP_UNLOADED`
- Track `last_event_id` from `df.global.world.history.events` to avoid duplicates
- Timers in `'ticks'` mode are auto-cancelled by DFHack on world unload

### World Scanning

- Iterate `df.global.world.history.events` from `last_event_id + 1` only (incremental)
- Filter by player's parent entity or user-tracked civs/entities
- Check event type via `event:getType()` vs `df.history_event_type.*` enum values

**Event Checks** (Keep this code seperate to the event and scanning loop, one script per event check)

- Death events: `df.history_event_type.HIST_FIGURE_DIED`; victim field: `event.victim_hf` (integer hf id)

### Notifications

- Announcement: `dfhack.gui.showAnnouncement`
- Modal popup: `gui.MessageWindow` for high-importance events

### Settings & Persistence

- UI: `require('gui')`, `require('gui.widgets')`
- Settings screen: toggle categories (War, Diplomacy, Artifacts, Beasts) + tracked civs list
- Global config: `dfhack-config/herald.json`
- Per-save config: `dfhack.persistent.get` / `dfhack.persistent.save`

## Key API Paths

- Ticks: `df.global.cur_year_tick`
- Events: `df.global.world.history.events`
- Entities: `df.global.world.entities.all`
- Historical figure: `df.historical_figure.find(hf_id)`
- HF entity links: `hf.entity_links[i].type` / `.entity_id`; link type enum: `df.histfig_entity_link_type.POSITION`
- Entity resolution: `df.historical_entity.find(entity_id)`
- Position assignments: `entity.position_assignments[i].histfig2` / `.id`
- Position name: `entity.positions[i].name`
- Name translation: `dfhack.TranslateName(name_obj, true)`
- Player civ id: `df.global.plotinfo.civ_id`

## Rules

- Use graphics-compatible UI only (no legacy text-mode)
- Always guard with `dfhack.isMapLoaded()` before scanning
- Never re-scan from event ID 0; always incremental
- Keep UI (`herald-gui.lua`) separate from logic (`herald-main.lua`)

## Future (on request only)

- Adventure mode support
- Legendary citizen tracking (notable deeds of fort-born figures)
- War progress summaries (casualty totals after battles)
