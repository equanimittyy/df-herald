# Dwarf Fortress Herald

A DFHack mod for Dwarf Fortress Steam (v50+) that scans world history for significant events and notifies the player in-game.

## What it does

Herald monitors the world while you play, alerting you when notable events happen - even off-screen. Track the deaths of historical figures, follow leadership changes across civilizations, and stay informed about the world beyond your fortress walls.

### Features

- **Individual tracking** - Pin historical figures and get notified about their deaths, combat, relationships, positions, and more
- **Civilisation tracking** - Pin civilisations to follow leadership changes, diplomacy, warfare, raids, theft, and kidnappings
- **Event History popup** - Browse collected events with context
- **Overlay button** - Quick access from the main game screen
- **Configurable settings** - Toggle notification categories per pinned figure or civilisation

## Requirements

- Dwarf Fortress Steam (v50.xx)
- [DFHack](https://docs.dfhack.org/) (latest stable)

## Installation

Subscribe via Steam Workshop, or copy the mod folder into your Dwarf Fortress `mods/` directory. Enable the mod in the DF mod manager before generating/loading a world.

Herald auto-enables when a world is loaded and disables when unloaded.

## Usage

Herald runs automatically in the background once enabled. Use the **Herald button** (overlay on the main screen) or the **settings GUI** to pin historical figures and civilisations you want to track.

Console commands:

```
herald-main enable    # manually enable
herald-main disable   # manually disable
herald-main debug true/false  # toggle debug output
```

## Author

**equanimity**
