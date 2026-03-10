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

local function build_event_types()
    local T = df.history_event_type
    local candidates = {
        T.ARTIFACT_CREATED,
        T.ARTIFACT_STORED,
        T.ARTIFACT_POSSESSED,
        T.ARTIFACT_CLAIM_FORMED,
        T.ITEM_STOLEN,
        T.WRITTEN_CONTENT_COMPOSED,
    }
    local result = {}
    for _, et in ipairs(candidates) do
        if et then table.insert(result, et) end
    end
    return result
end

-- Contract fields -----------------------------------------------------------

event_types = build_event_types()

function check_event(ev, dprint)
    -- skeleton: wire up event dispatch here
    dprint('ind-artifacts: event received type=%s', tostring(ev:getType()))
end

function reset()
    -- nothing to clear yet
end

dfhack.reqscript('herald-handler-contract').apply(_ENV)
