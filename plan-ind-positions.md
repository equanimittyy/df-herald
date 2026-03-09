# Plan: Position Tracking for Pinned Individuals

## Context

Pinned individuals already have a `positions` setting key defined in `INDIVIDUAL_SETTINGS_KEYS` and `default_pin_settings()`, but no handler implements it. The GUI shows it with `impl = false` (line 545). The goal is to track position changes (civ-level: King, General; fort-level: Mayor, Manager) for pinned HFs and announce them.

## Approach: Poll-based handler

Create `herald-ind-positions.lua` — a **poll-only** handler that snapshots each pinned HF's current positions every cycle and diffs against the previous snapshot.

**Why poll-based (not event-driven):**
- Fort-level positions (player-assigned via nobility screen) may not generate `ADD_HF_ENTITY_LINK` history events
- Poll catches both fort and civ positions uniformly with one mechanism
- Matches the proven `herald-world-leaders.lua` pattern
- 1-cycle delay (default 1 dwarf day) is acceptable

**Position reading approach:** Reuse the pattern from `herald-gui.lua:56-73` (`get_positions()`): iterate `hf.entity_links` for `POSITION` type, look up entity, scan `entity.positions.assignments` for `asgn.histfig2 == hf.id`, resolve name via `util.get_pos_name()`.

**Deduplication with world-leaders:** Not needed. If a civ is pinned AND an HF in that civ is pinned, both handlers fire. User opted into both; they can toggle `positions` off on either.

## Files to Modify

### 1. NEW: `scripts_modactive/herald-handlers/herald-ind-positions.lua`

**Snapshot schema:**
```
{ [hf_id] = { [entity_id..':'..assignment_id] = { entity_id, assignment_id, pos_name, civ_name } } }
```

**Algorithm (check_poll):**
1. For each pinned HF with `settings.positions` enabled and `is_alive(hf)`:
   - Build current position snapshot via entity_links + assignments
   - If previous snapshot exists for this HF: diff to find new keys (appointments) and announce
   - If no previous snapshot: set baseline silently (no announcements)
   - Store new snapshot
2. For each HF in previous snapshot that's still pinned + alive:
   - Diff to find removed keys (vacated positions) and announce
3. Atomic swap: `position_snapshots = new_snapshots`

**Announcements:**
- New position: `util.announce_appointment("{Name} has been appointed {pos} of {civ}.")` (yellow)
- Lost position: `util.announce_vacated("{Name} is no longer {pos} of {civ}.")` (white)
- Fallback when pos_name is nil: `"...appointed to a position in {civ}"` / `"...no longer holds a position in {civ}"`

**Lifecycle:**
- `init()`: clear `position_snapshots = {}`
- `reset()`: clear `position_snapshots = {}`
- `polls = true`, no `event_types`

**Contract:** Call `contract.apply(_ENV)` at bottom (same as all handlers).

### 2. EDIT: `scripts_modactive/herald.lua` (~line 312)

Add `'herald-handlers/herald-ind-positions'` to `handler_paths`:
```lua
local handler_paths = {
    'herald-handlers/herald-ind-death',
    'herald-handlers/herald-ind-combat',
    'herald-handlers/herald-ind-skills',
    'herald-handlers/herald-ind-positions',   -- NEW
    'herald-handlers/herald-world-leaders',
}
```

### 3. EDIT: `scripts_modactive/herald-gui.lua` (line 545)

Flip `impl = false` to `impl = true`:
```lua
{ key = 'positions', label = 'Positions', caption = 'Title gained/lost', impl = true },
```

## Edge Cases Handled

- **First cycle after load/pin:** baseline set silently, no false announcements
- **HF unpinned then re-pinned:** snapshot pruned on unpin, re-baselined on re-pin
- **Dead HF:** skipped via `is_alive()` guard; no false "vacated" when game cleans up links
- **Stale POSITION link (no matching assignment):** inner loop simply doesn't match; correct behavior
- **Nil pos_name:** fallback announcement text names the entity for context
- **Save/load:** `init()` clears snapshots; first poll re-baselines

## Verification

1. Pin an HF who currently holds a position → next poll cycle should baseline silently (no announcement)
2. Assign a pinned HF to a fort position via nobility screen → next cycle should announce appointment
3. Remove a pinned HF from a fort position → next cycle should announce vacated
4. Toggle `positions` OFF on a pinned HF → announcements should stop
5. `herald debug true` → verify dprint output shows baseline counts and detection messages
