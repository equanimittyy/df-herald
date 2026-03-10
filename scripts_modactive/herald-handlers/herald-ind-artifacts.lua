--@ module=true

--[====[
herald-ind-artifacts
====================

Tags: dev

  Event-driven handler for pinned individual artifact and written work events.

Fires when a pinned HF creates an artifact, claims/stores/loses one,
or composes a written work.
Not intended for direct use.

]====]

local util = dfhack.reqscript('herald-util')
local pins = dfhack.reqscript('herald-pins')

-- Helpers -------------------------------------------------------------------

local function artifacts_enabled(settings)
    return settings and settings.artifacts
end

-- Event handling -------------------------------------------------------------

-- Event types this handler will claim once check_event is implemented.
-- Kept here for reference; not exported until dispatch logic is ready.
--   ARTIFACT_CREATED, ARTIFACT_STORED, ARTIFACT_POSSESSED,
--   ARTIFACT_CLAIM_FORMED, ITEM_STOLEN, WRITTEN_CONTENT_COMPOSED

-- Contract fields -----------------------------------------------------------

-- No event_types exported yet; skeleton only.

function check_event(ev, dprint)
    dprint('ind-artifacts: event received type=%s', tostring(ev:getType()))
end

function reset()
    -- nothing to clear yet
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
