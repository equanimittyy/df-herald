# Event History Subsystem (`herald-event-history.lua`)

Contains the event-display subsystem used by the EventHistory popup (Ctrl-E).
Required by `herald-gui.lua` as `local ev_hist = dfhack.reqscript('herald-event-history')`.

## Exports (non-local at module scope)

- **`HF_FIELDS`** — ordered list of scalar HF ID field names (e.g. `victim_hf`, `attacker_general_hf`).
  Fallback for unknown event types in `get_hf_events` and `herald-cache`.
- **`TYPE_HF_FIELDS`** — `{ [event_type_int] = {field, ...} }` dispatch table mapping event types
  to 1-4 relevant HF fields. Reduces `safe_get` calls from ~28 to 1-4 for known types.
  Used by `herald-cache` and `get_hf_events`.
- **`safe_get(obj, field)`** — pcall-guarded field accessor; used by event describers and
  `herald-cache`.
- **`event_will_be_shown(ev)`** — calls the describer with `focal=-1`; returns false if the result
  is nil. Used by `herald-cache` to exclude noise events from counts.
- **`civ_matches_collection(col, civ_id)`** — returns true if a collection involves the given
  civ. Used by `herald-cache` for civ collection scanning.
- **`open_event_history(hf_id, hf_name)`** — opens (or raises) the EventHistory popup. Uses
  `widgets.FilteredList` with `search_key` for text search/filtering across events. Multi-line
  events share the same `search_key` so they filter as a group. Called via
  `ev_hist.open_event_history(...)` from `FiguresPanel` and `PinnedPanel`.
- **`open_civ_event_history(entity_id, entity_name)`** — opens (or raises) the EventHistory
  popup for a civilisation. Shows collection-level summaries (wars, battles, conquests, raids,
  theft, abductions) plus individual position-change events. Same singleton pattern as
  `open_event_history`; opening one dismisses the other.
- **`reset_civ_caches()`** — invalidates lazy civ caches (`_entpop_to_civ`) on world unload.
  Called from `herald-main.cleanup()`.

## Internal (local) Components

- **`EVENT_DESCRIBE`** — `{ [event_type_int] = fn(ev, focal_hf_id) -> string }`. Populated in a
  `do` block via `add(type_name, fn)`, which silently skips unknown type names (handles DFHack
  version differences). Describers return verb-first text when focal matches a participant;
  return `nil` to suppress the event entirely.
- **`article(s)`** — returns `"a <s>"` or `"an <s>"` based on first letter.
- **`title_case(s)`** — converts `ALL_CAPS_ENUM_NAME` to `"All Caps Enum Name"`.
- **`artifact_name_by_id(art_id)`** — resolves an artifact ID to its translated name and item
  description (material + type, e.g. "copper sword"). Returns `(name_or_nil, item_desc_or_nil)`.
  pcall-guarded, returns nil on failure.
- **`building_name_at_site(site_id, structure_id)`** — resolves a structure within a site to its
  translated building name by scanning `site.buildings`. pcall-guarded.
- **`civ_name_by_id(entity_id)`** — like `ent_name_by_id` but resolves SiteGovernments to their
  parent Civilisation (via position holder HF -> MEMBER link -> Civilization). Falls back to
  the entity's own name. Used in `format_collection_entry` so opponents show civ names.
- **`event_sort_cmp(a, b)`** — shared sort comparator for event lists; sorts by year, seconds,
  id. Direct field access (no pcall); synthetic entries must set `seconds=-1, id=-1`.
  Used by both `get_civ_events` and `get_hf_events`.
- **`get_hf_events(hf_id)`** — event collection for the popup. Uses `herald-cache` event IDs
  when available (O(n) lookups per HF); falls back to full world scan if cache not ready.
  Relationship events always scanned from block store. Contextual `WAR_FIELD_BATTLE`
  aggregation only runs in fallback path. Also builds and returns a `ctx_map`
  (event_id -> best collection) via `build_event_to_collection()`.
  Returns `(results, ctx_map)`.
  **Note:** battle participation via contextual aggregation is implemented but unconfirmed -
  see the TODO comment above `get_hf_events`.
- **`format_event(ev, focal_hf_id, ctx_map, civ_mode)`** — renders `"In the year NNN, ..."` using
  `EVENT_DESCRIBE` or `clean_enum_name` fallback. When `ctx_map` is provided and the event
  type is in `CTX_TYPES`, appends a collection context suffix (e.g. "as part of a duel
  between X and Y") via `describe_collection`. In HF mode (default), lowercases the first char
  of descriptions (verb-first). In civ mode (`civ_mode=true`), keeps capitalisation intact
  (descriptions start with HF names).
- **`BATTLE_TYPES` set pattern** — used in both `get_hf_events` and `build_hf_event_counts` to
  resolve `HF_SIMPLE_BATTLE_EVENT` / `HIST_FIGURE_SIMPLE_BATTLE_EVENT` across DFHack versions.
  Always use a set (`{ [v] = true }`) not a single value with `or`.

## Event Collection Context

- **`_CT`** — `{ [name_string] = collection_type_int }` lookup table pre-computed at module
  load. Maps 18 collection type names (DUEL, BEAST_ATTACK, ... CEREMONY) to their integer
  values. Used by `describe_collection`, `civ_matches_collection`, `format_collection_entry`,
  `get_parent_war_name`, `peace_war_suffix`, and `build_war_event_map` for fast integer
  dispatch instead of string comparison.
- **`COLLECTION_PRIORITY`** — `{ [collection_type_int] = priority }` mapping. Lower number =
  more specific context. DUEL(1) > BEAST_ATTACK(2) > ... > CEREMONY(13). Built from `_CT`.
- **`build_war_event_map()`** — scans only WAR-type collections, builds
  `{ [event_id] = war_collection }`. Used by `get_civ_events` (civ mode only needs war context
  for peace/agreement event suffixes).
- **`build_event_to_collection()`** — scans `event_collections.all` once, builds
  `{ [event_id] = best_collection }` keeping highest-priority collection per event.
  Called once per popup open inside `get_hf_events`.
- **`describe_collection(col, skip_site)`** — returns human-readable context suffix string
  (e.g. "during The Scraped Conflict") for 13+ collection types. `skip_site=true` omits site
  info to avoid duplication with the base description. All field access pcall-guarded.
  Unverified types (RAID, THEFT, INSURRECTION, PURGE) use safe_get fallback chains.
  Uses `_CT` integer comparisons (no string lookup per call).
- **`CTX_TYPES`** — `{ [event_type_int] = fn(ev)->bool }` table of event types that receive
  collection context. The function returns true when site should be skipped in the suffix.
  Covers 11 event type names (8 distinct types accounting for version aliases).

## Civ Event History

- **`civ_matches_collection(col, civ_id)`** — returns true if a collection involves the given
  civ as attacker, defender, or participant. Uses `_CT` integer dispatch; pcall-guarded vector/
  scalar field checks.
- **`site_from_collection_events(col)`** — resolves a site name from a collection's first
  event. Used as fallback for collection types with no direct `site` field (OCCASION and its
  sub-collections: COMPETITION, PERFORMANCE, PROCESSION, CEREMONY).
- **`get_parent_war_name(col)`** — returns translated name of the parent WAR collection, or nil.
  Looks up `col.parent_collection`, verifies it is WAR type. pcall-guarded.
- **`get_entpop_to_civ()`** — lazily builds and caches `{ [entity_population.id] = civ_id }`
  lookup from `df.global.world.entity_populations`. Used by BATTLE matching and details.
  Invalidated by `reset_civ_caches()` on world unload.
- **`entpop_vec_has_civ(col, field, civ_id, ep_map)`** — checks if any entity_population ID
  in a squad vector field belongs to `civ_id`. Used by `civ_matches_collection` BATTLE branch.
- **`sum_squad_vec(col, field)`** — sums integer values from a squad vector (e.g.
  `attacker_squad_deaths`). Returns total.
- **`vec_to_set(col, field)`** — builds `{ [value] = true }` set from an integer vector field.
- **`count_battle_hf_deaths(col)`** — counts HF deaths per side in a battle by scanning
  `HIST_FIGURE_DIED` events (battle + child collections), classifying victims via
  `attacker_hf`/`defender_hf` vectors. Returns `(att_hf_deaths, def_hf_deaths)`.
- **`_DIED_TYPE`** — pre-computed `df.history_event_type['HIST_FIGURE_DIED']` integer.
- **`get_battle_details(col, focal_civ_id)`** — returns `(opponent_name, killed, lost)` for a
  BATTLE collection. Determines side via `attacker_squad_entity_pop` / `defender_squad_entity_pops`
  entity_population lookup, sums squad deaths (generic population) + HF deaths (named figures),
  resolves opponent civ name.
- **`format_collection_entry(col, focal_civ_id)`** — returns civ-perspective description text
  for a collection. Uses `_CT` integer dispatch. BATTLE entries use entity_population-based
  resolution (not `attacker_civ`/`defender_civ` which are empty on BATTLEs), include death
  counts (`killed X, lost Y` - omitted when both zero) and parent war name suffix.
  Lowercase-first for generated text (e.g. "conquered Site from Enemy", "hosted a gathering at
  Site"), preserves capitalisation for proper names from DF translation (e.g. "The War of X -
  war with Y"). No year prefix; caller handles that. OCCASION collections have no `occasion_id`
  field; name resolved via `col_name()` fallback, site resolved from own events or first child
  collection's events.
- **`get_civ_events(civ_id)`** — collects events relevant to a civ: collection-level summaries
  for warfare/raids/theft/kidnappings + individual position-change, entity-creation, and
  peace/agreement events. Uses `build_war_event_map()` (WAR-only) instead of full
  `build_event_to_collection()`. Returns `(results, ctx_map)` matching `get_hf_events` signature.
