# Dwarf Fortress Herald

DFHack mod (Lua, v50+ Steam) that scans world history for significant events and notifies the player in-game.

## Tech Stack

- Dwarf Fortress Steam (v50.xx) + DFHack (latest stable)
- Language: Lua
- Ref: DFHack Modding Guide

## Architecture

### Event Loop

- Poll every 8,400 ticks (1 dwarf week) via `dfhack.timeout(8400, 'ticks', callback)`
- Handle `onStateChange`: start on `SC_MAP_LOADED`, stop on `SC_MAP_UNLOADED`
- Track `last_event_id` from `df.global.world.history.events` to avoid duplicates

### World Scanning

- Iterate `df.global.world.history.events` from `last_event_id + 1` only (incremental)
- Filter by player's parent entity or user-tracked civs
- Event types: `histevent_site_conqueredst`, `histevent_artifact_storedst`, `histevent_war_field_battlest`, etc.

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

## Rules

- Use graphics-compatible UI only (no legacy text-mode)
- Always guard with `dfhack.isMapLoaded()` before scanning
- Never re-scan from event ID 0; always incremental
- Keep UI (`herald-gui.lua`) separate from logic (`herald-main.lua`)

## Future (on request only)

- Adventure mode support
- Legendary citizen tracking (notable deeds of fort-born figures)
- War progress summaries (casualty totals after battles)
