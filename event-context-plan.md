# Event Context Types — Concept & Implementation Plan

## The Problem

Several event types tell you *what* happened but not *why*. The player sees "Was wounded by Urist McAxe" with no indication of whether it was a one-on-one duel, a beast rampage, or a pitched battle. "Abducted by Urist McSpy" gives no hint of which civ ordered it. "Attacked a site" is meaningless without knowing it was a raid or part of a war. The goal is to enrich those descriptions with that "why" — the **event collection context**.

---

## What Are Event Collections?

DF groups related events into **historical event collections** (`world.history.event_collections`). Each collection is a container object of a specific *type* (the context) and holds:

- A list of **event IDs** (integers) — the actual `HIST_FIGURE_*` events that occurred within it.
- **Child collection IDs** — for nested containers (e.g. a WAR contains BATTLE collections).
- Type-specific fields describing the participants, location, and timing.

Collections are distinct from events. An event has `event.id` and lives in `world.history.events`. A collection has `collection.id`, a `collection.type`, and a vector `collection.events` of those IDs.

### Key DFHack Paths

```
df.global.world.history.event_collections     -- vector of all collections
df.global.world.history.events                -- vector of all events (already used)

-- Per-collection:
collection.id                                 -- int32
collection.type                               -- enum df.history_event_collection_type
collection.start_year / collection.end_year
collection.events                             -- vector<int32_t> of event IDs contained
collection.collections                        -- vector<int32_t> of nested collection IDs (field is 'collections', NOT 'child_collections')
-- plus type-specific fields (attacker_hf, site, etc.)
```

---

## Context Types Relevant to the Task

### 1. DUEL
One-on-one formal combat between two historical figures.

**Key fields:** `attacker_hf`, `defender_hf`, `site`

**Events inside it:** `HIST_FIGURE_SIMPLE_BATTLE_EVENT`, `HIST_FIGURE_WOUNDED`, `HIST_FIGURE_DIED`

**Desired output:** "...as part of a duel between [Attacker] and [Defender] at [Site]"

---

### 2. BEAST_ATTACK
A monster/beast attacking a location — a "rampage" scenario.

**Key fields:** `attacker_hf` (vector — beast HF; use `[0]`), `site` (scalar)

**Events inside it:** Multiple `HIST_FIGURE_SIMPLE_BATTLE_EVENT`, `HIST_FIGURE_WOUNDED`, `HIST_FIGURE_DIED` as defenders fight back or fall.

**Desired output:** "...during the beast attack on [Site] by [Beast]"

---

### 3. BATTLE
A full military engagement between forces.

**Key fields:** `name` (language_name — battle's own name), `attacker_civ` (vector — may be empty), `defender_civ` (vector — may be empty), `site` (scalar)

**Events inside it:** `HIST_FIGURE_SIMPLE_BATTLE_EVENT`, `HIST_FIGURE_DIED`, `HIST_FIGURE_WOUNDED`

**Desired output:** "...during [Battle Name]" (preferred) or "...during the battle at [Site] between [Civ A] and [Civ B]"

---

### 4. ABDUCTION
A snatcher or spy kidnapping someone. Knowing the collection reveals the orchestrating civ and origin site — information not on the event itself.

**Key fields:** `snatcher_hf` (vector — use `[0]`), `victim_hf` (vector — use `[0]`), `attacker_civ` (scalar — ordering civ), `site` (scalar)

**Events inside it:** `HIST_FIGURE_ABDUCTED`; also `HIST_FIGURE_SIMPLE_BATTLE_EVENT` / `HIST_FIGURE_DIED` if the snatcher was intercepted.

**Desired output:** "...as part of the abduction of [Target] from [Site], ordered by [Civ]"

---

### 5. RAID
A raiding party attacking a site — smaller scale than BATTLE, no full army.

**Key fields:** `attacking_entity`, `defending_entity`, `site`

**Events inside it:** `HF_ATTACKED_SITE`, `HIST_FIGURE_SIMPLE_BATTLE_EVENT`, `HIST_FIGURE_WOUNDED`, `HIST_FIGURE_DIED`

**Desired output:** "...during a raid on [Site] by [Raider Civ]"

---

### 6. SITE_CONQUERED
A site changing hands after an assault. Provides "why the attack happened" context for deaths and wounds that the individual events lack.

**Key fields:** `attacker_civ` (vector — use `[0]`), `defender_civ` (vector), `site` (scalar) — no `new_civ_id` or `attacking_entity` field

**Events inside it:** `HF_ATTACKED_SITE`, `WAR_ATTACKED_SITE`, `HIST_FIGURE_DIED`, `HIST_FIGURE_WOUNDED`, and possibly `CREATED_SITE` (replacement settlement).

**Desired output:** "...during the conquest of [Site] by [Civ]"

---

### 7. WAR
A prolonged conflict containing BATTLE and RAID child collections. Events are rarely *directly* inside WAR; they sit inside child BATTLEs/RAIDs. However `WAR_FIELD_BATTLE` and `WAR_ATTACKED_SITE` events can appear at this level and benefit from naming the war.

**Key fields:** `name` (language_name — use `translateName`), `attacker_civ` (vector — use `[0]`), `defender_civ` (vector) — no `attacking_entity`/`defending_entity` field

**Desired output:** "...during [War Name]" (preferred) or "...as part of the war between [A] and [B]"

---

### 8. PURGE
A civ expelling or executing a group of members — a targeted elimination.

**Key fields (unverified):** `entity` (purging entity), possibly `site`

**Events inside it:** `HIST_FIGURE_DIED`, `REMOVE_HF_ENTITY_LINK` (expulsions)

**Desired output:** "...during the purge of [Entity]"

---

### 9. THEFT
A targeted theft of an artifact or item.

**Key fields (unverified):** `attacking_entity` (thief's group), `target_entity` (victim), `site`

**Events inside it:** `HIST_FIGURE_DIED` (if thief or defender killed), `HIST_FIGURE_WOUNDED`

**Desired output:** "...during a theft from [Site] by [Civ]"

---

### 10. INSURRECTION
An internal rebellion within or against an entity.

**Key fields (unverified):** `target_entity` (entity being rebelled against), `site`, possibly `leader_hf`

**Events inside it:** `HIST_FIGURE_SIMPLE_BATTLE_EVENT`, `HIST_FIGURE_DIED`, `HIST_FIGURE_WOUNDED`

**Desired output:** "...during the insurrection against [Entity]"

---

### 11. ENTITY_OVERTHROWN
The outcome of a successful coup or revolution — an entity changing control.

**Key fields:** `entity` (scalar — the overthrown entity), `site` (scalar) — no attacker field visible

**Events inside it:** `HIST_FIGURE_DIED`, position-change events

**Desired output:** "...during the overthrow of [Entity] at [Site]"

---

### 12. PERSECUTION
Systematic targeting of a group, typically religious or political.

**Key fields:** `entity` (scalar — the persecutor), `site` (scalar) — no `target_entity`/`target_religion` field

**Events inside it:** `HIST_FIGURE_DIED`, `HIST_FIGURE_WOUNDED`, `CHANGE_HF_STATE` (exile/flight)

**Desired output:** "...during the persecution by [Entity]"

---

### 13. OCCASION
A parent container for cultural gatherings — contains COMPETITION, PERFORMANCE, CEREMONY, and PROCESSION child collections rather than events directly.

**Key fields:** `civ` (scalar entity ID — no `site` field on this type)

**Desired output:** "...during a gathering by [Civ]"

---

### 14. COMPETITION
A contest between historical figures.

**Key fields:** `civ` (scalar entity ID — no `site` field)

**Events inside it:** `COMPETITION` history events, `HIST_FIGURE_DIED` (rare)

**Desired output:** "...during a competition by [Civ]"

---

### 15. PERFORMANCE
A public performance — music, dance, storytelling.

**Key fields:** `civ` (scalar entity ID — no `site` field)

**Events inside it:** `MASTERPIECE_CREATED_*`, `HIST_FIGURE_DIED` (rare)

**Desired output:** "...during a performance by [Civ]"

---

### 16. PROCESSION
A ceremonial march or parade.

**Key fields:** `civ` (scalar entity ID — no `site` field)

**Desired output:** "...during a procession by [Civ]"

---

### 17. CEREMONY
A formal ritual or ceremony.

**Key fields:** `civ` (scalar entity ID — no `site` field)

**Desired output:** "...during a ceremony by [Civ]"

---

### 18. JOURNEY
An HF travelling between locations. Low contextual value for combat events but can explain deaths en route.

**Key fields:** `traveler_hf` (vector — use `[0]`) — no `site` field

**Events inside it:** `CHANGE_HF_STATE` (travel), `HIST_FIGURE_DIED` (died en route)

**Desired output:** "...during a journey"

---

## The Lookup Problem: Events Don't Point to Collections

Events do **not** carry a field like `collection_id`. The relationship is one-way: the collection lists its event IDs, not the other way around.

**Solution:** Build an **index** `event_id → collection` by scanning `event_collections` once per popup open. When an event has multiple matching collections, keep the highest-priority one (see Priority below).

```lua
-- Pseudocode
local PRIORITY = {
    DUEL=1, BEAST_ATTACK=2, ABDUCTION=3, PURGE=4, THEFT=5,
    BATTLE=6, INSURRECTION=6, RAID=7, PERSECUTION=8,
    SITE_CONQUERED=9, ENTITY_OVERTHROWN=9, WAR=10,
    JOURNEY=11, COMPETITION=12, PERFORMANCE=12,
    OCCASION=12, PROCESSION=13, CEREMONY=13,
}
-- event_collections is a struct; the vector lives at .all (confirmed via probe_diag)
-- #all and #col.events both work on these vector types (confirmed via probe_diag)
local all             = df.global.world.history.event_collections.all
local event_to_collection = {}
for ci = 0, #all - 1 do
    local col   = all[ci]
    local ctype = df.history_event_collection_type[col:getType()]
    local pri   = PRIORITY[ctype] or 99
    local ok_n, n = pcall(function() return #col.events end)
    if ok_n then
        for j = 0, n - 1 do
            local eid      = col.events[j]
            local existing = event_to_collection[eid]
            local ex_pri   = existing and (PRIORITY[df.history_event_collection_type[existing:getType()]] or 99) or 99
            if pri < ex_pri then
                event_to_collection[eid] = col
            end
        end
    end
end
```

This index is built once inside `get_hf_events` and returned alongside the event list so `format_event` can use it.

---

## Priority / Conflict Resolution

Most specific context wins:

`DUEL > BEAST_ATTACK > ABDUCTION > PURGE > THEFT > BATTLE = INSURRECTION > RAID > PERSECUTION > SITE_CONQUERED = ENTITY_OVERTHROWN > WAR > JOURNEY > COMPETITION = PERFORMANCE = OCCASION > PROCESSION = CEREMONY`

Rationale: most-specific conflict context wins. One-on-one (DUEL) beats group conflict (BATTLE); targeted crimes (ABDUCTION, PURGE, THEFT) beat generic military action; cultural contexts (OCCASION, CEREMONY, etc.) are lowest priority and rarely co-occur with combat events.

---

## Affected Events and Current Describers

| Event type | Current describer | Change needed |
|---|---|---|
| `HIST_FIGURE_SIMPLE_BATTLE_EVENT` / `HF_SIMPLE_BATTLE_EVENT` | `hf_simple_battle_fn` | Append DUEL / BEAST_ATTACK / BATTLE / RAID context suffix |
| `HIST_FIGURE_WOUNDED` / `HF_WOUNDED` | `hf_wounded_fn` | Append DUEL / BEAST_ATTACK / BATTLE / RAID context suffix |
| `HIST_FIGURE_DIED` | `add('HIST_FIGURE_DIED', ...)` | Append BATTLE / RAID / SITE_CONQUERED context (death already shows site; add "in the battle of..." when applicable) |
| `HF_ABDUCTED` / `HIST_FIGURE_ABDUCTED` | `hf_abducted_fn` | Append ABDUCTION context (adds ordering civ, not just the snatcher) |
| `HF_ATTACKED_SITE` | `add('HF_ATTACKED_SITE', ...)` | Append RAID / BATTLE / SITE_CONQUERED / WAR context |
| `HF_DESTROYED_SITE` | `add('HF_DESTROYED_SITE', ...)` | Append RAID / BATTLE / WAR context |
| `WAR_ATTACKED_SITE` | `add('WAR_ATTACKED_SITE', ...)` | Append WAR or SITE_CONQUERED context (names the war) |
| `WAR_FIELD_BATTLE` | `add('WAR_FIELD_BATTLE', ...)` | Append WAR context (names the containing war) |

---

## Context Suffix Format

```
"...as part of a duel between [A] and [B]"
"...during the beast attack on [Site] by [Beast]"
"...during the battle at [Site] between [Civ A] and [Civ B]"
"...as part of the abduction of [Target] from [Site], ordered by [Civ]"
"...during a raid on [Site] by [Civ]"
"...during the conquest of [Site] by [Civ]"
"...as part of the war between [Civ A] and [Civ B]"
```

Suffix is appended inside the describer after the existing text, separated by a comma. If the describer already encodes the site (e.g. HIST_FIGURE_DIED's `site_sfx`), skip the site in the context suffix to avoid repetition.

---

## Implementation Approach

### Step 1 — Build the index in `get_hf_events`
- Scan `world.history.event_collections` after collecting events.
- Build priority-aware `event_to_collection` map (`event.id` → best-match collection).
- Return it alongside the event list: `return results, event_to_collection`.

### Step 2 — Thread the index into `format_event`
- Add an optional second parameter: `format_event(ev, focal_hf_id, ctx_map)`.
- Inside the describer call, also pass `ctx_map[ev.id]` as a third argument: `describer(ev, focal, ctx_map and ctx_map[safe_get(ev,'id')])`.
- Each describer that needs context accepts an optional `col` third argument.

### Step 3 — Write `describe_collection(col, skip_site)` helper
Returns a human-readable suffix string. `skip_site` avoids duplicating site info already in the base description.

```lua
local function describe_collection(col, skip_site)
    if not col then return nil end
    local ok, ctype = pcall(function()
        return df.history_event_collection_type[col:getType()]
    end)
    if not ok then return nil end

    if ctype == 'DUEL' then
        local a    = hf_name_by_id(safe_get(col, 'attacker_hf')) or 'someone'
        local d    = hf_name_by_id(safe_get(col, 'defender_hf')) or 'someone'
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local loc  = site and (' at ' .. site) or ''
        return 'as part of a duel between ' .. a .. ' and ' .. d .. loc

    elseif ctype == 'BEAST_ATTACK' then
        -- attacker_hf is a vector (confirmed); site is scalar
        local ok_b, bv = pcall(function() return col.attacker_hf end)
        local beast = (ok_b and #bv > 0) and hf_name_by_id(bv[0]) or 'a beast'
        local site  = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local loc   = site and (' on ' .. site) or ''
        return 'during the beast attack' .. loc .. ' by ' .. beast

    elseif ctype == 'ABDUCTION' then
        -- snatcher_hf/victim_hf are vectors; attacker_civ is a scalar civ ID (not attacking_entity)
        local ok_v, vv = pcall(function() return col.victim_hf end)
        local victim = (ok_v and #vv > 0) and hf_name_by_id(vv[0]) or 'someone'
        local civ    = ent_name_by_id(safe_get(col, 'attacker_civ'))
        local site   = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local loc    = site and (' from ' .. site) or ''
        local by     = civ and (', ordered by ' .. civ) or ''
        return 'as part of the abduction of ' .. victim .. loc .. by

    elseif ctype == 'BATTLE' then
        -- has 'name' (language_name); attacker_civ/defender_civ are vectors (may be empty)
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local ok_n, bname = pcall(function()
            return dfhack.translation.translateName(col.name, true)
        end)
        if ok_n and bname and bname ~= '' then
            local loc = site and (' at ' .. site) or ''
            return 'during ' .. bname .. loc
        end
        local ok_ac, acv = pcall(function() return col.attacker_civ end)
        local ok_dc, dcv = pcall(function() return col.defender_civ end)
        local ac = (ok_ac and #acv > 0) and ent_name_by_id(acv[0]) or nil
        local dc = (ok_dc and #dcv > 0) and ent_name_by_id(dcv[0]) or nil
        local loc = site and (' at ' .. site) or ''
        if ac and dc then
            return 'during the battle' .. loc .. ' between ' .. ac .. ' and ' .. dc
        end
        return 'during a battle' .. loc

    elseif ctype == 'RAID' then
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local ac   = ent_name_by_id(safe_get(col, 'attacking_entity'))
        local loc  = site and (' on ' .. site) or ''
        local by   = ac and (' by ' .. ac) or ''
        return 'during a raid' .. loc .. by

    elseif ctype == 'SITE_CONQUERED' then
        -- attacker_civ/defender_civ are vectors (no attacking_entity field)
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local ok_ac, acv = pcall(function() return col.attacker_civ end)
        local ac = (ok_ac and #acv > 0) and ent_name_by_id(acv[0]) or nil
        local loc = site and (' of ' .. site) or ''
        local by  = ac and (' by ' .. ac) or ''
        return 'during the conquest' .. loc .. by

    elseif ctype == 'WAR' then
        -- name is language_name (confirmed); attacker_civ/defender_civ are vectors
        local ok_n, war_name = pcall(function()
            return dfhack.translation.translateName(col.name, true)
        end)
        if ok_n and war_name and war_name ~= '' then
            return 'during ' .. war_name
        end
        local ok_ac, acv = pcall(function() return col.attacker_civ end)
        local ok_dc, dcv = pcall(function() return col.defender_civ end)
        local ac = (ok_ac and #acv > 0) and ent_name_by_id(acv[0]) or nil
        local dc = (ok_dc and #dcv > 0) and ent_name_by_id(dcv[0]) or nil
        if ac and dc then
            return 'as part of the war between ' .. ac .. ' and ' .. dc
        end
        return nil

    elseif ctype == 'PERSECUTION' then
        -- entity is scalar (the persecutor); site is scalar
        local ent  = ent_name_by_id(safe_get(col, 'entity'))
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local by   = ent and (' by ' .. ent) or ''
        local loc  = site and (' at ' .. site) or ''
        return 'during a persecution' .. by .. loc

    elseif ctype == 'ENTITY_OVERTHROWN' then
        -- entity is scalar (the overthrown entity); site is scalar
        local ent  = ent_name_by_id(safe_get(col, 'entity'))
        local site = not skip_site and site_name_by_id(safe_get(col, 'site'))
        local of_  = ent and (' of ' .. ent) or ''
        local loc  = site and (' at ' .. site) or ''
        return 'during the overthrow' .. of_ .. loc

    elseif ctype == 'JOURNEY' then
        -- traveler_hf is a vector; no site field on this type
        return 'during a journey'

    elseif ctype == 'OCCASION' or ctype == 'COMPETITION' or ctype == 'PERFORMANCE'
        or ctype == 'PROCESSION' or ctype == 'CEREMONY' then
        -- civ is scalar entity ID; no site field on these types
        local labels = {
            OCCASION='a gathering', COMPETITION='a competition', PERFORMANCE='a performance',
            PROCESSION='a procession', CEREMONY='a ceremony',
        }
        local civ = ent_name_by_id(safe_get(col, 'civ'))
        local by  = civ and (' by ' .. civ) or ''
        return 'during ' .. labels[ctype] .. by
    end

    return nil
end
```

### Step 4 — Modify describers
For each event type in the affected table:
- Accept optional `col` third argument.
- Call `describe_collection(col, has_site_already)` at the end.
- If non-nil, append: `base .. ', ' .. ctx_suffix`.
- Pass `skip_site=true` where the base description already names the site (e.g. HIST_FIGURE_DIED with `site_sfx`, HF_ATTACKED_SITE with `loc`).

### Step 5 — Field name verification
Before coding, use the DFHack console to inspect real collections of each type:
Use `probe/probe_5` (change TARGET at top) — the probes already use the confirmed correct patterns.
This confirms actual field names, which may differ from the XML spec in the installed DFHack version. Verify each type before writing its branch.

---

## Scope Limits (this task only)

- Touch only the eight event types listed in the affected table above.
- Do not rebuild the GUI or civ event window here (separate major task).
- `describe_collection` is local to `herald-event-history.lua` — no new module.
- Collection index is per-popup only (not persisted or globally cached).
- Field name branches in `describe_collection` must be guarded with `safe_get` / pcall — collection subtypes may not expose all fields on all DFHack versions.
