# To-do list:

## Fixes

- ~~Settings button should show on map menu of fort-mode~~
- ~~Check if civilisation number of sites and population is correct (site number is confirmed wrong, and pop number tracks Historical Figures but I want to try track the ACTUAL population including non-essential entities)~~
- ~~Trying to open the event window for a hf whilst having the event window of another hf open doesn't change the window to the new individual and displays the other hf's events until the window is closed~~

## Changes

- ~~Refactor main code to make herald-util.lua~~
- ~~Add neat human readable comments to code so it's easier to follow~~

- ~~Announcements should be restructured(in order, top to bottom):~~
  - ~~Individuals: Relationships, Death, Combat, Legendary, Positions, Migration~~
  - ~~Civilisations: Positions, Diplomacy, Warfare, Raids, Theft, Kidnappings~~
    ~~The default for all announcements is ON instead of OFF~~
- Change event window for:
  - CREATED_BUILDING: specify building name
  - ARTIFACT_CREATED: specify artifact name
  - ARTIFACT_STORED: specify artifact name
  - COMPETITION: specify who the other participants are
  - CREATE_ENTITY_POSITION: specify the position name
  - HIST_FIGURE_SIMPLE_BATTLE_EVENT + hf wounded + hfdied: increase the granularity of the context of WHY two figures were fighting (key contexts types include duel, beast attack (rampage), raids and battle)
    IMPORTANT: How the structure of this works is that these context types have any number of events within them that are the HIST_FIGURE_SIMPLE_BATTLE_EVENT as well as the hf wounded and hfdied event keys. Basically these contexts are lists that contain x number of events within them.
    For example:
    - dwarf A attacked dwarf B (HIST_FIGURE_SIMPLE_BATTLE_EVENT) as part of the DUEL of dwarf A against dwarf B (context DUEL)

    - monster A wounded dwarf C (hf wounded) as part of the rampage of monster A against example_site (context beast attack)
      monster A killed dwarf D (hf wounded) as part of the rampage of monster A against example_site (still same context beast attack)

    - dwarf E killed dwarf F (hf died) in the battle of example_battle(context battle)

    There is more context available in these lists such as the location, which would be good to bring through.

    Overall, the idea is to make as many references to other characters/proper names as possible to give the player a sense of a connected world instead of "made an artifact" or "fought x/y"

- ~~Make herald-button have a toggle "hide/show button" in the DFHack launcher~~
- MAJOR: Add an event window for civilisations (you can re-use the existing one)
  - Need to track: Positions, Diplomacy, Warfare (so wars that have started and battles), Raids, Theft, Kidnappings
    NOTE: There is a similar context type "WAR" that contains a number of related battles within it
