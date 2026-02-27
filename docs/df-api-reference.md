# DF API Reference

## Critical Conventions

- **0-indexed vectors.** `#vec` = count. Iterate `for i = 0, #vec - 1` or `ipairs(vec)`. Never `vec[1]`.
- **`:getType()` not `.type`.** Events, entity links, collections all use virtual dispatch. `.type` errors/returns nil.
- **`__index` raises on absent fields.** Use `pcall`/`safe_get(obj, field)` for uncertain fields.
- **`-1` = none/unset.** HF IDs, entity IDs, `died_year`, `histfig2`, site IDs. Check `>= 0` before use.
- **Two string formats.** `stl-string` (plain) vs `string[]` (0-indexed). Use `herald-util.name_str()`.
- **`language_name` needs translation.** `dfhack.translation.translateName(obj.name, true)` for English.

## Global Data Paths

| Path | Type |
|---|---|
| `df.global.cur_year_tick` | current tick |
| `df.global.plotinfo.civ_id` | player civ |
| `df.global.world.entities.all` | all `historical_entity` |
| `df.global.world.history.figures` | all `historical_figure` |
| `df.global.world.history.events` | all events (indexed by **position**, NOT event ID) |
| `df.history_event.find(id)` | event by ID (slow; avoid in loops) |
| `df.global.world.history.relationship_events` | block store (see below) |
| `df.global.world.world_data.sites` | all `world_site` |
| `df.global.world.entity_populations` | non-HF racial groups |

## Historical Figure

```
hf = df.historical_figure.find(hf_id)
hf.id, hf.name (language_name), hf.sex (1=M, 0=F), hf.race (creature race ID)
hf.died_year, hf.died_seconds  -- both -1 if alive (use herald-util.is_alive)
hf.entity_links                -- vector of histfig_entity_link
```

**Entity links:** `link:getType()` returns `histfig_entity_link_type` (MEMBER, POSITION, etc.).
`link.entity_id` = the entity. NOT `link.type`, NOT `link.link_type`.

## Historical Entity

```
entity = df.historical_entity.find(entity_id)
entity.id, entity.name (language_name), entity.type (Civilization, SiteGovernment, etc.)
entity.race, entity.positions, entity.histfig_ids (pcall-guard), entity.entity_raw (may be nil)
```

## Positions

Two name sources (check in order):
1. `entity.positions.own` — `entity_position` with stl-string: `pos.name`, `pos.name_male`, `pos.name_female`. **Empty for EVIL/PLAINS.**
2. `entity.entity_raw.positions` — `entity_position_raw` with `string[]`: `pos.name[0]`, etc. Fallback.

Use `herald-util.get_pos_name(entity, pos_id, hf_sex)`.

**Assignments:** `asgn = entity.positions.assignments[i]`
- `asgn.id` (stable key), `asgn.position_id`, `asgn.histfig2` (holder HF ID, -1 if vacant)
- NOT `asgn.histfig`, NOT `asgn.hf_id`, NOT `asgn.holder`

## History Events

Indexed by **array position**, NOT by `.id`. IDs are non-contiguous.

```
ev.id, ev:getType(), ev.year, ev.seconds
-- NOT ev.type, NOT events[event_id]
```

**Per-type fields** (use `safe_get` when uncertain; full mapping in `TYPE_HF_FIELDS`):

- `HIST_FIGURE_DIED`: `victim_hf`, `slayer_hf`, `death_cause`, `site`
- `HF_SIMPLE_BATTLE_EVENT` (alias `HIST_FIGURE_SIMPLE_BATTLE_EVENT`): `group1`/`group2` (vectors), `subtype`
- `COMPETITION`: `competitor_hf`/`winner_hf` (vectors)
- `CHANGE_HF_STATE`: `hfid`, `state`, `substate`, `reason`, `site`
- `CHANGE_HF_JOB`: `hfid`, `old_job`, `new_job`, `site`
- `ADD_HF_ENTITY_LINK`: `histfig`, `civ`, `link_type`, `position_id`
- `HF_DOES_INTERACTION`: `doer`, `target`, `interaction_action`
- `HIST_FIGURE_ABDUCTED`: `snatcher`, `target`
- `MASTERPIECE_CREATED_*`: `maker`, `maker_entity`, `item_type`, `item_subtype`
- `ARTIFACT_CREATED`: `creator_hfid`
- `ARTIFACT_STORED`: `histfig`, `artifact_id` (or `artifact_record`), `site`
- `ARTIFACT_CLAIM_FORMED`: `artifact`, `histfig`, `entity`, `claim_type`
- `ITEM_STOLEN`: `histfig`, `item_type`, `mattype`, `matindex`, `entity`, `site`
- `ASSUME_IDENTITY`: `trickster`, `identity`, `target`
- `GAMBLE`: `hf`, `site`, `structure`, `account_before`, `account_after`
- `ENTITY_CREATED`: `entity`, `site`, `structure`, `creator_hfid`
- `FAILED_INTRIGUE_CORRUPTION`: `corruptor_hf`, `target_hf`, `site`
- `HF_ACT_ON_BUILDING`: `histfig`, `action` (0=profaned, 2=prayed), `site`, `structure`
- `CREATED_SITE`/`CREATED_STRUCTURE`: `builder_hf`
- `WAR_PEACE_ACCEPTED`/`REJECTED`: `source`, `destination`, `topic` (entity IDs; no HF fields)
- `TOPICAGREEMENT_CONCLUDED`/`MADE`/`REJECTED`: `source`, `destination` (entity IDs)
- `BODY_ABUSED`: `histfig` (abuser), `bodies` (vec of victim HF IDs), `abuse_type` (0=impaled..5=animated), `site`
- `WRITTEN_CONTENT_COMPOSED`: `histfig`, `content` (written_content ID), `site`
- `HF_CONFRONTED`: `target`, `situation`, `reasons` (vec; 0=ageless, 1=murder), `site`
- `ARTIFACT_POSSESSED`: `histfig`, `artifact`, `site`
- `HF_GAINS_SECRET_GOAL`: `histfig`, `goal` (goal_type enum 0-14)
- `HF_LEARNS_SECRET`: `student`, `teacher` (HF/-1), `artifact`, `interaction`
- `ENTITY_OVERTHROWN`: `overthrown_hf`, `position_taker_hf`, `instigator_hf`, `conspirator_hfs` (vec), `entity`, `position_profile_id`, `site`
- `HIST_FIGURE_REVIVED`: `histfig` (revived), `actor_hfid` (reviver), `interaction`, `site`, `region`
- `AGREEMENT_FORMED`: `agreement_id` (no entity/HF fields)

## Relationship Events (Block Store)

NOT a vector. Iterate blocks `0..#rel_evs-1`, inner `0..block.next_element-1`. pcall-guard all access.

```
block = df.global.world.history.relationship_events[block_idx]
block.next_element, block.source_hf[k], block.target_hf[k], block.relationship[k], block.year[k]
```

## Event Collections

```
col = df.global.world.history.event_collections.all[i]  -- MUST use .all
col:getType(), col.events[j] (event IDs), col.collections (child IDs), col.parent_collection, col.name
-- NOT col.type, NOT col.child_collections, NOT event_collections[i]
```

**By ID:** `df.history_event_collection.find(id)`

**Per-type fields** (probe-verified):

| Type | Key fields | Notes |
|---|---|---|
| DUEL | `attacker_hf`/`defender_hf` scalar, `site` | |
| BEAST_ATTACK | `attacker_hf` **vec**`[0]`, `site` | |
| ABDUCTION | `snatcher_hf`/`victim_hf` **vecs**, `attacker_civ`, `site` | NOT `attacker_hf`/`target_hf` |
| BATTLE | `name`, `site`, `attacker_squad_entity_pop`/`defender_squad_entity_pops` **vecs**, `attacker_squad_deaths`/`defender_squad_deaths` **vecs**, `attacker_hf`/`defender_hf` **vecs** | `attacker_civ`/`defender_civ` always empty; use entity_pop->`civ_id` |
| SITE_CONQUERED | `attacker_civ`/`defender_civ` **vecs**, `site` | |
| WAR | `name`, `attacker_civ`/`defender_civ` **vecs** | no `site` |
| PERSECUTION | `entity` scalar, `site` | |
| ENTITY_OVERTHROWN | `entity` scalar, `site` | |
| JOURNEY | `traveler_hf` **vec** | no `site` |
| OCCASION/COMPETITION/PERFORMANCE/PROCESSION/CEREMONY | `civ` scalar | no `site`; resolve from events |
| RAID/THEFT/INSURRECTION/PURGE | unverified | use `safe_get` |

Field naming: `attacker_civ`/`defender_civ` (NOT `attacking_entity`/`defending_entity`).

## World Sites

```
site = df.global.world.world_data.sites[i]
site.civ_id (original owner, may be stale), site.cur_owner_id (may be SiteGovernment), site.name
```

SiteGov-to-Civ resolution in `build_civ_choices()` (5-tier fallback):
1. `cur_owner_id` is Civ directly
2. SiteGov position holder HF -> MEMBER link -> Civ
3. SiteGov `histfig_ids` -> MEMBER/FORMER_MEMBER -> Civ
4. SITE_CONQUERED collections -> `attacker_civ[0]`
5. `site.civ_id` (last resort)

## Entity Populations

```
ep = df.global.world.entity_populations[i]
ep.civ_id, ep.races (vec), ep.counts (vec, parallel to races; NO count_min)
```
