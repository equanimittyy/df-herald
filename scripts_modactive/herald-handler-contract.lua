--@ module=true

--[====[
herald-handler-contract
=======================

Tags: unavailable

  Installs no-op defaults for the Herald handler contract into a module env.

Handlers call contract.apply(_ENV) at module scope, then override the fields
they need. herald.lua can call init/reset/check_event/check_poll on any
handler without nil checks.
Not intended for direct use.

]====]

local NOOP = function() end

-- Contract fields and their defaults:
--   event_types  nil           { df.history_event_type.* } to receive events via check_event
--   polls        false         truthy to be called each cycle via check_poll
--   init         no-op         called on world load
--   reset        no-op         called on world unload
--   check_event  no-op         called for matching history events
--   check_poll   no-op         called each scan cycle
function apply(env)
    env.polls       = env.polls       or false
    env.init        = env.init        or NOOP
    env.reset       = env.reset       or NOOP
    env.check_event = env.check_event or NOOP
    env.check_poll  = env.check_poll  or NOOP
end
