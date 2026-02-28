--@ module=true

--[====[
herald-probe
============
Debug utility for inspecting live DF data. Edit the probe code below as needed,
then run via: herald-main probe
Requires debug mode: herald-main debug true

Not intended for direct use.
]====]

local main = dfhack.reqscript('herald-main')

if not main.DEBUG then
    dfhack.printerr('[Herald] Probe requires debug mode. Enable with: herald-main debug true')
    return
end

print('=== START PROBE: Announcement Medallions ===')

-- 1. Dump announcement_alertst struct fields
print('')
print('--- announcement_alertst struct ---')
local ok1, alertst = pcall(function() return df.announcement_alertst end)
if ok1 and alertst then
    local a = alertst:new()
    printall(a)
    a:delete()
else
    print('  NOT FOUND')
end

-- 2. Fire test announcements with different announcement_types that should
--    produce different medallions, then inspect the resulting alerts.
print('')
print('--- Fire test announcements with makeAnnouncement ---')

-- Interesting announcement_types to test (one per expected alert_type)
local test_types = {
    'REACHED_PEAK',           -- expect GENERAL
    'MIGRANT_ARRIVAL_NAMED',  -- expect MIGRANT
    'CAVE_COLLAPSE',          -- expect UNDERGROUND?
    'DIG_CANCEL_DAMP',        -- expect UNDERGROUND?
    'AMBUSH',                 -- expect AMBUSH
    'CARAVAN_ARRIVAL',        -- expect TRADE
    'BIRTH_CITIZEN',          -- expect BIRTH
    'MOOD_BUILDING',          -- expect MOOD
    'CREATURE_SOUND',         -- expect ANIMAL?
    'NOBLE_ARRIVAL',          -- expect NOBLE?
    'MASTERPIECE',            -- expect MASTERPIECE
    'D_COMBAT_ATTACK_STRIKE', -- expect COMBAT
    'GHOST_ATTACK',           -- expect GHOST?
    'WEATHER_MISSING_RAIN',   -- expect WEATHER?
    'CITIZEN_DEATH',          -- expect DEATH?
    'ERA_CHANGE',             -- expect ERA_CHANGE
}

local flags = df.announcement_flags:new()
flags.D_DISPLAY = true
flags.A_DISPLAY = true
flags.ALERT = true

local fired = {}
for _, name in ipairs(test_types) do
    local ok, t = pcall(function() return df.announcement_type[name] end)
    if ok and t then
        local idx = dfhack.gui.makeAnnouncement(
            t, flags, {x=0,y=0,z=0},
            '[PROBE] type=' .. name, COLOR_WHITE, false
        )
        print(('  Fired: %-35s type_int=%-3d report_idx=%d'):format(name, t, idx))
        table.insert(fired, {name=name, type_int=t, report_idx=idx})
    else
        print(('  SKIP:  %s (not in enum)'):format(name))
    end
end

flags:delete()

-- 3. Now inspect the announcement_alert vector to see which alert_types appeared
print('')
print('--- announcement_alert after firing ---')
local alerts = df.global.world.status.announcement_alert
print(('  Total alerts: %d'):format(#alerts))
for i = 0, #alerts - 1 do
    local a = alerts[i]
    print(('  Alert [%d]:'):format(i))
    printall(a)
end

-- 4. Also inspect the report.type field for each fired announcement
print('')
print('--- Report type field for fired announcements ---')
local reports = df.global.world.status.reports
for _, f in ipairs(fired) do
    if f.report_idx >= 0 and f.report_idx < #reports then
        local r = reports[f.report_idx]
        print(('  %-35s report.type=%d'):format(f.name, r.type))
    end
end

print('')
print('=== END PROBE ===')
