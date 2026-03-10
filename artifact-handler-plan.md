# herald-ind-artifacts Implementation Plan

## Probe Findings (confirmed)

- `artifact_record`: `id`, `name`, `item`, `site`, `storage_site`, `holder_hf`, `owner_hf`. **No creator_hf** - creator only on ARTIFACT_CREATED event.
- `written_content`: `id`, `title` (string), `author` (HF ID), `type`, `poetic_form`.
- HF field names vary by event type: `creator_hfid` (ARTIFACT_CREATED) vs `histfig` (all others).
- `ITEM_STOLEN.item` = artifact_record ID when the stolen item is an artifact.
- Event volumes: WRITTEN_CONTENT_COMPOSED (5728) >> ARTIFACT_CLAIM_FORMED (972) > ITEM_STOLEN (684) > ARTIFACT_CREATED (544) > ARTIFACT_STORED (214) > ARTIFACT_POSSESSED (10).

## Event Types to Handle

All event-driven (no polling needed). Register in `event_types`:

| DF Type | HF field | What to announce |
|---|---|---|
| `ARTIFACT_CREATED` | `creator_hfid` | "[HF] created [artifact name], [material type] in [site]" |
| `ARTIFACT_STORED` | `histfig` | "[HF] stored [artifact name] in [site]" |
| `ARTIFACT_POSSESSED` | `histfig` | "[HF] claimed [artifact name] in [site]" |
| `ARTIFACT_CLAIM_FORMED` | `histfig` | "[HF] formed a claim on [artifact name]" (+ entity/claim_type context) |
| `ITEM_STOLEN` | `histfig` | "[HF] stole [artifact name] from [entity] in [site]" (only when .item is an artifact) |
| `WRITTEN_CONTENT_COMPOSED` | `histfig` | "[HF] composed \"[title]\" in [site]" |

## Implementation Steps

### 1. Register event_types in handler

```lua
event_types = {
    [df.history_event_type.ARTIFACT_CREATED] = true,
    [df.history_event_type.ARTIFACT_STORED] = true,
    [df.history_event_type.ARTIFACT_POSSESSED] = true,
    [df.history_event_type.ARTIFACT_CLAIM_FORMED] = true,
    [df.history_event_type.ITEM_STOLEN] = true,
    [df.history_event_type.WRITTEN_CONTENT_COMPOSED] = true,
}
```

### 2. Helper: resolve artifact name + description

Reuse the same pattern as `herald-event-history.lua:artifact_name_by_id` but simpler - just need name string for announcements. Use `dfhack.translation.translateName(art.name, true)`. For item description (material + type), use `item:getActualMaterial()`/`item:getType()` via `dfhack.matinfo.decode`.

### 3. Helper: resolve written_content title

`df.written_content.find(wc_id)` -> `.title` field (plain string).

### 4. Implement check_event dispatch

Extract HF ID per event type. Check if pinned (`pins.get_pinned()[hf_id]`). Check `artifacts_enabled(settings)`. Dispatch to per-type formatter.

Per-type logic:
- **ARTIFACT_CREATED**: `ev.creator_hfid`, `ev.artifact_id`, `ev.site`
- **ARTIFACT_STORED**: `ev.histfig`, `ev.artifact`, `ev.site`
- **ARTIFACT_POSSESSED**: `ev.histfig`, `ev.artifact`, `ev.site`
- **ARTIFACT_CLAIM_FORMED**: `ev.histfig`, `ev.artifact`, `ev.entity`, `ev.claim_type`
- **ITEM_STOLEN**: `ev.histfig`, `ev.item` (check if artifact via `df.artifact_record.find`), `ev.entity`, `ev.site`. Skip if `.item` is not a valid artifact (regular theft, not our concern).
- **WRITTEN_CONTENT_COMPOSED**: `ev.histfig`, `ev.content`, `ev.site`

### 5. Use `util.announce_artifact(msg)` for all announcements

Already exists in herald-util (yellow, push to recent ring buffer).

### 6. No init/reset/poll needed

Pure event-driven handler. No state to snapshot. Keep `reset()` as empty no-op.

## Edge Cases

- ITEM_STOLEN may fire for non-artifact items. Guard with `df.artifact_record.find(ev.item)` - if nil, skip.
- ARTIFACT_POSSESSED is very rare (10 events in 250 years). Still handle it.
- `ev.entity` on ARTIFACT_CLAIM_FORMED can be -1 (no entity context). Handle gracefully.
- written_content `.title` can be empty string. Fallback to "a written work".
- artifact name can be untranslatable (first 3 artifacts in probe had no name). Fallback to material+type description from `.item`, or "an artifact".

## Files to Change

1. `herald-handlers/herald-ind-artifacts.lua` - full implementation (replace skeleton)
2. `herald.lua` - verify `herald-ind-artifacts` is already in `handler_paths` (it is, line 318)
3. No changes to herald-util, herald-event-history, or herald-gui needed

## Post-Implementation

Run review agents (coupling, dead-code, robustness) per CLAUDE.md convention.
