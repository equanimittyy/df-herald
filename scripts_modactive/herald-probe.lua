--@ module=true

--[====[
herald-probe
============
Tags: unavailable

Debug utility for inspecting live DF data. Edit the probe code below as needed,
then run via: herald probe
Requires debug mode: herald debug true

Not intended for direct use.
]====]

local main = dfhack.reqscript('herald')

if not main.DEBUG then
    dfhack.printerr('[Herald] Probe requires debug mode. Enable with: herald debug true')
    return
end

print('=== START PROBE: Peace/Agreement Events ===')

local util = dfhack.reqscript('herald-util')
local events = df.global.world.history.events
local ET = df.history_event_type

-- Resolve type IDs (may not exist in all DFHack versions).
local PEACE_ACCEPTED = ET['WAR_PEACE_ACCEPTED']
local PEACE_REJECTED = ET['WAR_PEACE_REJECTED']
local TOPIC_CONCLUDED = ET['TOPICAGREEMENT_CONCLUDED']
local TOPIC_MADE = ET['TOPICAGREEMENT_MADE']
local TOPIC_REJECTED = ET['TOPICAGREEMENT_REJECTED']

local target_types = {}
if PEACE_ACCEPTED then target_types[PEACE_ACCEPTED] = 'WAR_PEACE_ACCEPTED' end
if PEACE_REJECTED then target_types[PEACE_REJECTED] = 'WAR_PEACE_REJECTED' end
if TOPIC_CONCLUDED then target_types[TOPIC_CONCLUDED] = 'TOPICAGREEMENT_CONCLUDED' end
if TOPIC_MADE then target_types[TOPIC_MADE] = 'TOPICAGREEMENT_MADE' end
if TOPIC_REJECTED then target_types[TOPIC_REJECTED] = 'TOPICAGREEMENT_REJECTED' end

print('Registered type IDs:')
for id, name in pairs(target_types) do
    print(('  %s = %d'):format(name, id))
end
print('')

local shown = 0
local max_show = 20

for i = 0, #events - 1 do
    if shown >= max_show then break end
    local ev = events[i]
    local ok_t, ev_type = pcall(function() return ev:getType() end)
    if not ok_t then goto continue end

    local type_name = target_types[ev_type]
    if not type_name then goto continue end

    shown = shown + 1
    print(('--- [yr%d] event id=%d type=%s ---'):format(ev.year, ev.id, type_name))

    -- source / destination fields
    local src = util.safe_get(ev, 'source')
    local dst = util.safe_get(ev, 'destination')
    local topic = util.safe_get(ev, 'topic')

    local function ent_info(eid)
        if not eid or eid < 0 then return '(none)' end
        local ent = df.historical_entity.find(eid)
        if not ent then return ('id=%d (not found)'):format(eid) end
        local name = dfhack.translation.translateName(ent.name, true)
        if not name or name == '' then name = '(unnamed)' end
        return ('id=%d (%s)'):format(eid, name)
    end

    print(('  source:      %s'):format(ent_info(src)))
    print(('  destination: %s'):format(ent_info(dst)))
    print(('  topic:       %s'):format(topic and tostring(topic) or '(nil)'))

    -- Dump all fields
    print('  All fields:')
    pcall(function()
        for k, v in pairs(ev) do
            local vs = tostring(v)
            if #vs > 80 then vs = vs:sub(1, 80) .. '...' end
            print(('    %s = %s'):format(tostring(k), vs))
        end
    end)
    print('')

    ::continue::
end

if shown == 0 then
    print('No peace/agreement events found.')
end

print(('Showed %d of max %d'):format(shown, max_show))
print('=== END PROBE ===')
