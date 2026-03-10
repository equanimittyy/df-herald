# Handler Suite Review Findings

Full review run 2026-03-10 against all 7 handlers + orchestration + util modules.
Updated 2026-03-10 after combat simplification, init-baseline fixes, `for_each_pinned_unit` decoupling, and batch fixes.

## High Priority

| # | Issue | Category | Status | Location |
|---|---|---|---|---|
| 1 | ~~`kill_baselines` not pruned on unpin~~ | Robustness | FIXED | Prunes against `pinned` each poll cycle |
| 2 | ~~`build_hf_snapshot` partial failure replaces full snapshot~~ | Robustness | FIXED | Returns nil,false on error; poll preserves previous snapshot |
| 3 | ~~`world-leaders` walks `entity.positions.assignments` without pcall~~ | Robustness | FIXED | pcall guard added in check_poll and init baseline |
| 4 | `world-leaders` owns civ pin state (dual handler+persistence identity); GUI directly imports handler path | Coupling | Open | `world-leaders.lua`, `herald-gui.lua:17` |

## Medium Priority

| # | Issue | Category | Status | Location |
|---|---|---|---|---|
| 5 | `herald-event-history` back-references orchestrator for `DEBUG` flag (cyclic dependency) | Coupling | Open | `herald-event-history.lua:2719` |
| 6 | ~~`ind-skills` borrows `announce_appointment` (yellow) for legendary skill events~~ | Coupling | FIXED | New `announce_legendary` (light green) in util |
| 7 | `ind-death`/`ind-combat` share implicit role split over `HIST_FIGURE_DIED` + `BODY_ABUSED` | Coupling | Open (by design) | combat=slayer side, death=victim side |
| 8 | Unbounded dedup set growth in combat/migration/relationships (cleared only on unload) | Robustness | Open | all event-driven handlers |
| 9 | ~~`ind-death` double `df.historical_figure.find()` call without local cache~~ | Robustness | FIXED | Cached in local `hf` |

## Low Priority

| # | Issue | Category | Status | Location |
|---|---|---|---|---|
| 10 | `dispatch` tables populated only in `init()`, silent miss if `check_event` called before | Robustness | Open | combat, migration, relationships |
| 11 | ~~`push_recent` accesses `df.global.cur_year` without map-loaded guard~~ | Robustness | FIXED | Guarded with `dfhack.isMapLoaded()` |
| 12 | ~~`world-leaders` `pinned_civ_ids` not cleared in `reset()`~~ | Robustness | FIXED | Added to `reset()` |
| 13 | `ind-positions` and `world-leaders` duplicate position snapshot/diff logic | Coupling | Open | both files |
| 14 | ~~`ind-combat` poll handler (240 lines) inlines 4 distinct detection concerns~~ | Coupling | FIXED | Stripped to kills-only (~90 lines) |
| 15 | `cleanup()` resets non-handler modules by name (no registry) | Coupling | Open | `herald.lua:449-453` |
| 16 | ~~Redundant `hf_name` wrappers in combat and migration handlers~~ | Dead code | FIXED | Replaced with direct `local hf_name = util.hf_name` |
| 17 | ~~`has_unread` exported from util but never consumed~~ | Dead code | FALSE POSITIVE | Consumed by `herald-button.lua:229` |
| 18 | ~~CLAUDE.md handler list stale (lists 3 handlers, 7 exist)~~ | Dead code/docs | FIXED | Updated to list all 7 handlers |
