# To-do list:

Note:
Need to try fix up the UI first, needs to be as accurate as possible as I imagine users will use this screen the most to explore the history of their world.

## Fixes

- ~~Site count fixes~~

## Changes

- ~~Optimisation: caching the loaded data in the user's save file and then applying delta processing when scanning for new events~~
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

- MAJOR: Add an event window for civilisations (you can re-use the existing one)
  - Need to track: Positions, Diplomacy, Warfare (so wars that have started and battles), Raids, Theft, Kidnappings
    NOTE: There is a similar context type "WAR" that contains a number of related battles within it
