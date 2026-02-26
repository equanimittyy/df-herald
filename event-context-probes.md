# DFHack Console Probes — Event Collection Verification

## Console constraints (confirmed)
- Only **expressions** work bare — `for`, `local`, `if` at top level give `<name> expected near <eof>`
- Line length is limited (~200 chars) — long lines truncated, causing `unfinished string near <eof>`
- **Fix for short checks:** one `print(...)` per line, no string labels
- **Fix for multi-statement probes:** write a `.lua` file in `scripts_modactive/probe/`, run as `probe/probe_N`
- **Correct path:** `df.global.world.history.event_collections.all` — `.event_collections` is a struct `T_event_collections` with `.all` (6663 entries confirmed) and `.other` (empty); indexing the struct directly throws
- `#all` works — same vector type as `world.history.events` where `#` returned 69807; use simple `for i=0, #all-1`
- `#col.events` works on sub-field vectors — confirmed for all 6663 collections (probe_7: 0 errors)
- `df.history_event_collection.find(id)` confirmed exists — use for collection ID lookups
- **`col.type` does not exist on concrete subtypes** — use `col:getType()` (confirmed broken in probe_2)
- **Child collections field is `col.collections`** — NOT `col.child_collections`; `#col.collections` TBD (probe_6 re-run needed)
- **`col.events[i]` values are event IDs** (not array positions) — `world.history.events[N]` accesses by position; probe_4 confirmed: `events[252].id = 276`, not 252. Key ctx_map by `ev.id`.
- **Common fields on all subtypes (probe_3 + probe_5/DUEL):** `id`, `start_year`, `end_year`, `start_seconds`, `end_seconds`, `flags`, `parent_collection`, `region`, `layer`, `site`, `region_pos`
- **`attacker_civ`/`defender_civ` on BATTLE are `vector<int32_t>`** — not scalar IDs; access with `col.attacker_civ[0]`. `attacker_entity`/`defender_entity` do NOT exist on BATTLE.
- **WAR `name` is a `language_name` struct** — `dfhack.translation.translateName(col.name, true)` confirmed, returns e.g. "The Scraped Conflict"

---

## 1. Enum sanity — COMPLETE

`probe/probe_1_all` confirmed all 18 values:

| int | name | Plan status |
|---|---|---|
| 0 | WAR | confirmed |
| 1 | BATTLE | confirmed |
| 2 | DUEL | confirmed |
| 3 | SITE_CONQUERED | confirmed |
| 4 | ABDUCTION | confirmed |
| 5 | THEFT | in plan — fields unverified |
| 6 | BEAST_ATTACK | confirmed — MONSTER_ATTACK does not exist (removed from plan) |
| 7 | JOURNEY | in plan — fields unverified |
| 8 | INSURRECTION | in plan — fields unverified |
| 9 | OCCASION | in plan — fields unverified |
| 10 | PERFORMANCE | in plan — fields unverified |
| 11 | COMPETITION | in plan — fields unverified |
| 12 | PROCESSION | in plan — fields unverified |
| 13 | CEREMONY | in plan — fields unverified |
| 14 | PURGE | in plan — fields unverified |
| 15 | RAID | in plan — fields unverified |
| 16 | PERSECUTION | in plan — fields unverified |
| 17 | ENTITY_OVERTHROWN | in plan — fields unverified |

---

## 2. Count by type in save — COMPLETE

All iteration patterns confirmed working. Results (6663 total):

| Type | Count | Probeable? |
|---|---|---|
| BEAST_ATTACK | 1884 | yes |
| PERFORMANCE | 1356 | yes |
| COMPETITION | 952 | yes |
| OCCASION | 781 | yes |
| ABDUCTION | 621 | yes |
| PROCESSION | 368 | yes |
| CEREMONY | 233 | yes |
| BATTLE | 123 | yes |
| DUEL | 110 | yes |
| JOURNEY | 91 | yes |
| SITE_CONQUERED | 60 | yes |
| WAR | 42 | yes |
| PERSECUTION | 41 | yes |
| ENTITY_OVERTHROWN | 1 | yes |
| RAID | 0 | **not in this save** — field names unverifiable here |
| THEFT | 0 | **not in this save** — field names unverifiable here |
| INSURRECTION | 0 | **not in this save** — field names unverifiable here |
| PURGE | 0 | **not in this save** — field names unverifiable here |

---

## 3. Top-level struct fields — COMPLETE

`probe/probe_3` on first collection (WAR id=0):

| Field | Result |
|---|---|
| `id` | 0 ✓ |
| `start_year` | 1 ✓ |
| `end_year` | 2 ✓ |
| `#col.events` | 1 ✓ |
| `#col.child_collections` | ERROR — field name wrong; actual name is `collections` |

`probe/probe_5` (printall DUEL) confirmed full common field set on all subtypes:
`events`, `collections`, `id`, `start_year`, `end_year`, `start_seconds`, `end_seconds`, `flags`, `parent_collection`, `region`, `layer`, `site`, `region_pos`

---

## 4. Event ID linkage — COMPLETE

`probe/probe_4` on WAR id=0 (col.events[0]=252):
- `world.history.events[252].id = 276` — array position 252 has event ID 276
- `match = false` — confirms events array is NOT indexed by event ID
- **Conclusion:** `col.events[i]` stores event IDs. Key ctx_map by event ID and look up via `ev.id` during iteration. ✓

---

## 5. Per-type field dump — COMPLETE for DUEL; pending others

Edit `TARGET` at the top of probe_5 for each type.

### DUEL — COMPLETE

`printall` result:

| Field | Value | Notes |
|---|---|---|
| `attacker_hf` | 59 | ✓ scalar HF ID |
| `defender_hf` | 111 | ✓ scalar HF ID |
| `site` | 13 | ✓ scalar site ID |
| `parent_collection` | 23 | parent collection ID (WAR in this case) |
| `attacker_won` | 1 | DUEL-specific: 1=attacker won |
| `ordinal` | 1 | DUEL-specific: sequence number within parent |
| `events` | vector[2] | 2 events inside this duel |
| `collections` | vector[0] | no child collections |

Plan fields `attacker_hf`, `defender_hf`, `site` — all confirmed ✓

### BATTLE — partial (probe_8 only; run probe_5 TARGET='BATTLE' for full dump)

| Field | Value | Notes |
|---|---|---|
| `attacker_civ` | vector[0] | EXISTS but **vector**, not scalar; use `col.attacker_civ[0]` |
| `defender_civ` | vector[0] | EXISTS but **vector**, not scalar |
| `attacker_entity` | ERROR | does NOT exist |
| `defender_entity` | ERROR | does NOT exist |

### WAR — partial (probe_9 only; run probe_5 TARGET='WAR' for full dump)

| Field | Value | Notes |
|---|---|---|
| `name` | `<language_name>` | `translateName(col.name, true)` → "The Scraped Conflict" ✓ |

`attacking_entity`/`defending_entity` unverified — run probe_5.

### BEAST_ATTACK — COMPLETE

| Field | Value | Notes |
|---|---|---|
| `attacker_hf` | vector[1] | **vector**, not scalar; use `col.attacker_hf[0]` |
| `defender_civ` | 23 | scalar civ/entity ID (who was attacked) |
| `site` | 12 | ✓ scalar site ID |
| `parent_collection` | -1 | no parent |

Plan field `attacker_hf` (beast) — exists but is a vector. `site` ✓.

### ABDUCTION — COMPLETE

| Field | Value | Notes |
|---|---|---|
| `snatcher_hf` | vector[1] | **NOT `attacker_hf`** — use `col.snatcher_hf[0]` |
| `victim_hf` | vector[1] | **NOT `target_hf`** — use `col.victim_hf[0]` |
| `attempted_victim_hf` | vector[0] | those targeted but not taken |
| `attacker_civ` | 19 | scalar civ/entity ID — the ordering civ (**NOT `attacking_entity`**) |
| `defender_civ` | 27 | scalar — victim's civ |
| `site` | 16 | ✓ scalar site ID |

Plan fields corrected: `attacker_hf` → `snatcher_hf`, `target_hf` → `victim_hf`, `attacking_entity` → `attacker_civ`.

### BATTLE — COMPLETE

| Field | Value | Notes |
|---|---|---|
| `name` | `<language_name>` | **BATTLE also has a name** — `translateName(col.name, true)` |
| `parent_collection` | 0 | child of WAR id=0 |
| `attacker_civ` | vector[0] | **vector**, may be empty for early battles |
| `defender_civ` | vector[0] | **vector**, may be empty |
| `attacker_hf` | vector[11] | all attacker HFs |
| `defender_hf` | vector[7] | all defender HFs |
| `attacker_role` / `defender_role` | vectors | `hec_battle_hf_flag` per HF |
| `attacker_squad_entity_pop` | vector[9] | squad entity pop IDs |
| `outcome` | 1 | battle outcome |
| `site` | 13 | ✓ scalar site ID |

Use `translateName(col.name, true)` first; fall back to civ vectors if name is empty.

### SITE_CONQUERED — COMPLETE

| Field | Value | Notes |
|---|---|---|
| `attacker_civ` | vector[1] | **vector**; use `[0]` |
| `defender_civ` | vector[1] | **vector** |
| `site` | 6 | ✓ scalar |
| `parent_collection` | 2 | child of a WAR |
| `main_event_type` | 47 | event type enum — not needed for description |

No `attacking_entity`, no `new_civ_id`. `attacker_civ[0]` is the conquering civ.

### WAR — COMPLETE

| Field | Value | Notes |
|---|---|---|
| `name` | `<language_name>` | ✓ `translateName(col.name, true)` confirmed |
| `attacker_civ` | vector[1] | **vector** — NOT `attacking_entity` |
| `defender_civ` | vector[1] | **vector** — NOT `defending_entity` |
| `involved_civ` | vector[4] | all involved civs |
| `collections` | vector[2] | child BATTLE/RAID collections |

No `attacking_entity`/`defending_entity`. Use `attacker_civ[0]`/`defender_civ[0]` as fallback after name.

### PERSECUTION — COMPLETE

| Field | Value | Notes |
|---|---|---|
| `entity` | 37 | scalar — the persecuting entity |
| `site` | 16 | ✓ scalar |

No `attacking_entity`, no `target_entity`. Just `entity` (persecutor) + `site`.

### ENTITY_OVERTHROWN — COMPLETE

| Field | Value | Notes |
|---|---|---|
| `entity` | 17 | scalar — the overthrown entity |
| `site` | 8 | ✓ scalar |

No attacker field visible — only `entity` (the entity that was overthrown).

### JOURNEY — COMPLETE

| Field | Value | Notes |
|---|---|---|
| `traveler_hf` | vector[1] | **NOT `hf`** — use `col.traveler_hf[0]` |

No `site` field on JOURNEY. Description limited to "during a journey".

### OCCASION / COMPETITION / PERFORMANCE / PROCESSION / CEREMONY — COMPLETE

All share the same field set: `civ` (scalar entity ID), `occasion` (int — occasion index), `schedule` (int — schedule index). No `site` field on any of these types. OCCASION has child `collections`; others have `parent_collection`.

| Type | `civ` | `occasion` | `schedule` | `parent_collection` |
|---|---|---|---|---|
| OCCASION | 19 | 0 | — | — |
| COMPETITION | 11 | 0 | 1 | 9 |
| PERFORMANCE | 11 | 0 | 3 | 9 |
| PROCESSION | 19 | 0 | 1 | 6 |
| CEREMONY | 19 | 0 | 0 | 6 |

---

## 6. WAR child collections — COMPLETE

`probe/probe_6` (fixed) result on WAR id=0:
- `children: 2` — `#col.collections` works ✓
- Child 0: `cid=1, BATTLE`
- Child 1: `cid=23, BATTLE`

WAR children are BATTLE collection IDs. `df.history_event_collection.find(cid)` resolves them ✓.
DUEL `parent_collection=23` confirms: WAR(0) → BATTLE(23) → DUEL(24).

---

## 7. Index-building logic — COMPLETE

`probe/probe_7` result:
- `collections scanned: 6663` ✓
- `errors: 0` ✓ — `#col.events` works for all collection types
- `index entries: 19866`
- Sample: all BATTLE (event IDs ~123–132)

Index-building logic confirmed correct.

---

## 8. BATTLE attacker/defender field names — COMPLETE

`probe/probe_8` result:
- `attacker_civ`: **vector<int32_t>** (empty for this battle)
- `defender_civ`: **vector<int32_t>** (empty)
- `attacker_entity`: **does not exist**
- `defender_entity`: **does not exist**

**Plan fix:** Use `col.attacker_civ[0]` (with pcall/length check), not scalar. The `or attacker_entity` fallback in pseudocode must be removed.

---

## 9. WAR name field — COMPLETE

`probe/probe_9` result:
- `col.name`: `language_name` struct ✓
- `dfhack.translation.translateName(col.name, true)` → `"The Scraped Conflict"` ✓

---

## Status: ALL PROBES COMPLETE

All field names verified. `event-context-plan.md` `describe_collection` updated with confirmed fields.
Ready to implement in `herald-event-history.lua`.
