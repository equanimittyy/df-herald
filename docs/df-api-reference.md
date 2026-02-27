# DF API Reference

## Critical Conventions (Read First)

**DF vectors are 0-indexed.** All DF data vectors use 0-based indexing. `#vec` returns the
element count. Always iterate `for i = 0, #vec - 1 do ... vec[i] ... end`, or use
`ipairs(vec)` which DFHack adapts to 0-based. Never assume `vec[1]` is the first element.

**Virtual methods, not `.type` fields.** DFHack typed structs use virtual dispatch. Always call
`:getType()` to read the type discriminator. Direct `.type` field access does NOT exist on most
concrete subtypes and will error or return nil. Applies to: events (`ev:getType()`), entity
links (`link:getType()`), event collections (`col:getType()`).

**DFHack's `__index` raises on absent fields.** Accessing a field that doesn't exist on a typed
DF struct throws an error (not nil). Use `pcall` / `safe_get(obj, field)` when the field might
not exist on a given event subtype or across DFHack versions.

**Sentinel value `-1` means "none/unset".** HF IDs, entity IDs, `died_year`, `died_seconds`,
`histfig2`, site IDs, etc. all use `-1` to mean absent/unset. Always check `>= 0` before using
as a valid reference. Never treat `-1` as a valid lookup key.

**String fields come in two formats.** DF stores names as either:

- `stl-string`: plain Lua string (e.g. `pos.name` in `entity.positions.own`)
- `string[]`: 0-indexed array (e.g. `pos.name[0]` in `entity.entity_raw.positions`,
  `cr.name[0]` in creature_raw)

Use `herald-util.name_str(field)` to normalise either format to a plain string or nil.

**`language_name` structs must be translated.** Entity, HF, and site names are `language_name`
structs, not plain strings. Always call `dfhack.translation.translateName(obj.name, true)` to
get the English translation. The second arg `true` = "in English" (vs the DF language).

## Global Data Paths

- **Ticks:** `df.global.cur_year_tick`
- **Player civ:** `df.global.plotinfo.civ_id`
- **All entities:** `df.global.world.entities.all` (vector of `historical_entity`)
- **All HFs:** `df.global.world.history.figures` (vector of `historical_figure`)
- **All events:** `df.global.world.history.events` (vector; indexed by **position**, NOT by event ID)
- **Event by ID:** `df.history_event.find(id)` (slow linear search; avoid in loops)
- **Relationship events:** `df.global.world.history.relationship_events` (block store; see below)
- **World sites:** `df.global.world.world_data.sites` (vector of `world_site`)
- **Entity populations:** `df.global.world.entity_populations` (vector; non-HF racial groups)

## Historical Figure (HF) Struct

```
hf = df.historical_figure.find(hf_id)
hf.id             -- unique ID (int)
hf.name           -- language_name struct (use translateName)
hf.sex            -- 1 = male, 0 = female
hf.race           -- creature race ID (int); lookup: df.creature_raw.find(hf.race).name[0]
hf.died_year      -- -1 if alive, else year of death
hf.died_seconds   -- -1 if alive, else timestamp of death
hf.entity_links   -- vector of histfig_entity_link (see Entity Links below)
```

**Alive check:** `hf.died_year == -1 and hf.died_seconds == -1` (use `herald-util.is_alive(hf)`)

## HF Entity Links

Each link is a polymorphic struct. Field access rules:

```
link = hf.entity_links[i]
link:getType()     -- returns histfig_entity_link_type enum (MEMBER, POSITION, etc.)
link.entity_id     -- the entity this link refers to

-- WRONG: link.type         -- field does NOT exist on concrete subtypes
-- WRONG: link.link_type    -- not a field
```

Link type enum: `df.histfig_entity_link_type.MEMBER`, `.POSITION`, etc.

## Historical Entity Struct

```
entity = df.historical_entity.find(entity_id)
entity.id          -- unique ID (int)
entity.name        -- language_name struct
entity.type        -- df.historical_entity_type (Civilization, SiteGovernment, etc.)
entity.race        -- creature race ID (int)
entity.positions   -- T_positions sub-struct (see below)
entity.histfig_ids -- vector of HF IDs that are/were members (pcall-guard; may vary by type)
entity.entity_raw  -- entity_raw (template data; may be nil)
```

## Position System

**Two sources for position names** (check both in order):

1. `entity.positions.own` - `entity_position` objects with plain stl-string name fields:
   `pos.name`, `pos.name_male`, `pos.name_female`. Preferred source.
   **Empty for EVIL/PLAINS entity types.**

2. `entity.entity_raw.positions` - `entity_position_raw` objects with `string[]` name fields:
   `pos.name[0]`, `pos.name_male[0]`, `pos.name_female[0]`. Fallback for EVIL/PLAINS.

Use `herald-util.get_pos_name(entity, pos_id, hf_sex)` which handles both sources.

**Position assignments:**

```
asgn = entity.positions.assignments[i]
asgn.id           -- assignment ID (stable across cycles; used as snapshot key)
asgn.position_id  -- references pos.id in entity.positions.own / entity.entity_raw.positions
asgn.histfig2     -- HF ID of the current holder (-1 if vacant)

-- WRONG: asgn.histfig      -- not the holder field
-- WRONG: asgn.hf_id        -- not a field
-- WRONG: asgn.holder       -- not a field
```

## History Events

Events are indexed by **array position** in `df.global.world.history.events`, NOT by their `.id`
field. Event IDs are non-contiguous; always use `df.history_event.find(id)` for ID-based lookup
outside of sequential scans.

```
ev = events[i]
ev.id              -- unique event ID (int; NOT equal to array index)
ev:getType()       -- returns df.history_event_type enum
ev.year            -- year the event occurred
ev.seconds         -- timestamp within the year

-- WRONG: ev.type            -- not a field; use :getType()
-- WRONG: events[event_id]   -- events are NOT indexed by ID
```

**Per-event-type fields** (field names vary by event subtype):

- `HIST_FIGURE_DIED`: `ev.victim_hf`, `ev.slayer_hf`, `ev.death_cause`, `ev.site`
- `HF_SIMPLE_BATTLE_EVENT`: `ev.group1` (vector), `ev.group2` (vector), `ev.subtype`
- `COMPETITION`: `ev.competitor_hf` (vector), `ev.winner_hf` (vector)
- `CHANGE_HF_STATE`: `ev.hfid`, `ev.state`, `ev.substate`, `ev.reason`, `ev.site`
- `CHANGE_HF_JOB`: `ev.hfid`, `ev.old_job`, `ev.new_job`, `ev.site`
- `ADD_HF_ENTITY_LINK`: `ev.histfig`, `ev.civ`, `ev.link_type`, `ev.position_id`
- `HF_DOES_INTERACTION`: `ev.doer`, `ev.target`, `ev.interaction_action`
- `HIST_FIGURE_ABDUCTED`: `ev.snatcher`, `ev.target`
- `MASTERPIECE_CREATED_*`: `ev.maker`, `ev.maker_entity`, `ev.item_type`, `ev.item_subtype`
- `ARTIFACT_CREATED`: `ev.creator_hfid`
- `ARTIFACT_STORED`: `ev.histfig`, `ev.artifact_id` (or `artifact_record`), `ev.site`
- `ARTIFACT_CLAIM_FORMED`: `ev.artifact`, `ev.histfig`, `ev.entity`, `ev.claim_type`
- `ITEM_STOLEN`: `ev.histfig`, `ev.item_type`, `ev.mattype`, `ev.matindex`, `ev.entity`, `ev.site`
- `ASSUME_IDENTITY`: `ev.trickster`, `ev.identity`, `ev.target`
- `GAMBLE`: `ev.hf`, `ev.site`, `ev.structure`, `ev.account_before`, `ev.account_after`
- `ENTITY_CREATED`: `ev.entity`, `ev.site`, `ev.structure`, `ev.creator_hfid`
- `FAILED_INTRIGUE_CORRUPTION`: `ev.corruptor_hf`, `ev.target_hf`, `ev.site`
- `HF_ACT_ON_BUILDING`: `ev.histfig`, `ev.action` (0=profaned, 2=prayed), `ev.site`, `ev.structure`
- `CREATED_SITE`/`CREATED_STRUCTURE`: `ev.builder_hf`
- `WAR_PEACE_ACCEPTED`/`WAR_PEACE_REJECTED`: `ev.source`, `ev.destination`, `ev.topic` (entity IDs; civ-level, no HF fields)
- `TOPICAGREEMENT_CONCLUDED`/`TOPICAGREEMENT_MADE`/`TOPICAGREEMENT_REJECTED`: `ev.source`, `ev.destination` (entity IDs; assumed same layout)
- `BODY_ABUSED`: `ev.histfig` (abuser), `ev.bodies` (vector of victim HF IDs), `ev.abuse_type` (`body_abuse_method_type` enum: 0=impaled, 1=piled, 2=flayed, 3=hung, 4=mutilated, 5=animated), `ev.site`, `ev.region`
- `WRITTEN_CONTENT_COMPOSED`: `ev.histfig` (author), `ev.content` (written_content ID; use `df.written_content.find(id).title`), `ev.site`
- `HF_CONFRONTED`: `ev.target` (confronted HF), `ev.situation`, `ev.reasons` (vector; 0=ageless, 1=murder), `ev.site`
- `ARTIFACT_POSSESSED`: `ev.histfig`, `ev.artifact` (artifact_record ID), `ev.site`
- `HF_GAINS_SECRET_GOAL`: `ev.histfig`, `ev.goal` (`goal_type` enum: 0-14, see describer)
- `HF_LEARNS_SECRET`: `ev.student` (learner HF), `ev.teacher` (HF or -1), `ev.artifact` (artifact ID), `ev.interaction` (interaction ID; name via `df.interaction.find(id).str` `[IS_NAME:...]` tag)
- `ENTITY_OVERTHROWN`: `ev.overthrown_hf`, `ev.position_taker_hf`, `ev.instigator_hf`, `ev.conspirator_hfs` (vector), `ev.entity`, `ev.position_profile_id`, `ev.site`
- `HIST_FIGURE_REVIVED`: `ev.histfig` (revived HF), `ev.actor_hfid` (reviver HF), `ev.interaction`, `ev.site`, `ev.region`
- `AGREEMENT_FORMED`: `ev.agreement_id` (no entity fields; not included in civ event history)

For a full mapping see `TYPE_HF_FIELDS` in `herald-event-history.lua`. When the field name is
uncertain, always use `safe_get(ev, field)` (pcall-guarded) rather than direct access.

**DFHack version aliases:** Some event types have multiple names across versions:

- `HF_SIMPLE_BATTLE_EVENT` / `HIST_FIGURE_SIMPLE_BATTLE_EVENT` - always check both

## Relationship Events (Block Store)

`df.global.world.history.relationship_events` is NOT a simple vector - it's a block store with
a different access pattern:

```
rel_evs = df.global.world.history.relationship_events
block = rel_evs[block_idx]
block.next_element             -- number of valid entries in this block
block.source_hf[k]            -- parallel array: source HF ID
block.target_hf[k]            -- parallel array: target HF ID
block.relationship[k]         -- parallel array: relationship type enum
block.year[k]                 -- parallel array: year of relationship event
```

Iterate: outer loop over blocks `0..#rel_evs-1`, inner loop `0..block.next_element-1`.
All field accesses should be pcall-guarded as the struct layout varies across DFHack versions.

## Event Collections

```
all = df.global.world.history.event_collections.all   -- ALWAYS index .all, never the struct itself
col = all[i]
col:getType()                  -- df.history_event_collection_type enum
col.events[j]                  -- stores EVENT IDs (not array positions); match against ev.id
col.collections                -- child collection IDs (NOT .child_collections)
col.parent_collection          -- parent collection ID; WAR->BATTLE->DUEL nesting
col.name                       -- language_name (WAR and BATTLE only)

-- WRONG: col.type             -- use :getType()
-- WRONG: col.child_collections -- field is named .collections
-- WRONG: event_collections[i] -- must go through .all
```

**Collection by ID:** `df.history_event_collection.find(id)`

**Per-type key fields** (probe-verified, 250yr save):

| Type | Key fields | Notes |
|---|---|---|
| DUEL | `attacker_hf` scalar, `defender_hf` scalar, `site` scalar | |
| BEAST_ATTACK | `attacker_hf` **vector** `[0]`, `site` scalar | |
| ABDUCTION | `snatcher_hf`/`victim_hf` **vectors**, `attacker_civ` scalar, `site` | NOT `attacker_hf`/`target_hf` |
| BATTLE | `name`, `site` scalar, `attacker_squad_entity_pop`/`defender_squad_entity_pops` **vectors** (entity_population IDs), `attacker_squad_deaths`/`defender_squad_deaths` **vectors**, `attacker_hf`/`defender_hf` **vectors** | `attacker_civ`/`defender_civ` always empty; use entity_pop -> `civ_id` |
| SITE_CONQUERED | `attacker_civ`/`defender_civ` **vectors**, `site` scalar | no `new_civ_id` |
| WAR | `name`, `attacker_civ`/`defender_civ` **vectors** | no `site` |
| PERSECUTION | `entity` scalar (persecutor), `site` scalar | |
| ENTITY_OVERTHROWN | `entity` scalar (overthrown), `site` scalar | |
| JOURNEY | `traveler_hf` **vector**, no `site` | |
| OCCASION/COMPETITION/PERFORMANCE/PROCESSION/CEREMONY | `civ` scalar, no `site`, no `occasion_id` | site resolved from events via `site_from_collection_events` |
| RAID/THEFT/INSURRECTION/PURGE | unverified (absent from test save) | use `safe_get` guards |

Civ/entity fields use `attacker_civ`/`defender_civ` naming (NOT `attacking_entity`/`defending_entity`)
across all collection types.

## World Sites

```
site = df.global.world.world_data.sites[i]
site.civ_id        -- original owning civ (may be stale after conquest)
site.cur_owner_id  -- current owner entity ID (may be a SiteGovernment, not a Civ)
site.name          -- language_name struct
```

`cur_owner_id` may point to a SiteGovernment. `build_civ_choices()` in `herald-gui.lua` resolves
SiteGovernments to parent Civilizations via 5-tier fallback:

1. `cur_owner_id` is directly a Civilization
2. SiteGov -> position holder HF (`positions.assignments[].histfig2`) -> MEMBER link -> Civ
3. SiteGov -> `histfig_ids` members -> MEMBER/FORMER_MEMBER link -> Civ (catches vacant positions)
4. SITE_CONQUERED event collections -> `attacker_civ[0]` (most recent conquest wins)
5. `site.civ_id` (original/founding civ; last resort, may be stale after conquest)

## Entity Populations

```
ep = df.global.world.entity_populations[i]
ep.civ_id          -- parent civilisation entity ID
ep.races           -- vector of creature race IDs (parallel to ep.counts)
ep.counts          -- vector of population counts (0-indexed; NO count_min field)
```

Sum `ep.counts[j]` across all entries matching a civ_id for total population.
