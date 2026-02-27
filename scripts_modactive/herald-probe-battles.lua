-- Herald battle display probe.
-- Run from DFHack console: herald-probe-battles [CIV_ID]
-- Omit CIV_ID to use the player civ.
-- Diagnoses why battles may not appear in civ event history.

local args = {...}
local civ_id = tonumber(args[1]) or df.global.plotinfo.civ_id

print(('=== Herald Battle Probe - civ_id=%d ==='):format(civ_id))

-- 1. Verify the civ entity exists.
local entity = df.historical_entity.find(civ_id)
if not entity then
    print('FAIL: entity not found for civ_id=' .. civ_id)
    return
end
local ename = dfhack.translation.translateName(entity.name, true)
print(('Civ: %s (type=%s)'):format(ename or '?', tostring(df.historical_entity_type[entity.type])))

-- 2. Scan all collections for BATTLE type.
local all = df.global.world.history.event_collections.all
local total_cols = #all
local battle_count = 0
local battle_match = 0
local war_count = 0

print(('Total event collections: %d'):format(total_cols))

for ci = 0, total_cols - 1 do
    local col = all[ci]
    local ok, ctype = pcall(function()
        return df.history_event_collection_type[col:getType()]
    end)
    if ok then
        if ctype == 'WAR' then war_count = war_count + 1 end
        if ctype == 'BATTLE' then
            battle_count = battle_count + 1

            -- Check if civ_matches_collection would match this battle.
            local function vec_has(field)
                local ok_v, vec = pcall(function() return col[field] end)
                if not ok_v or not vec then return false, {} end
                local ok_n, n = pcall(function() return #vec end)
                if not ok_n then return false, {} end
                local ids = {}
                local found = false
                for i = 0, n - 1 do
                    local ok2, v = pcall(function() return vec[i] end)
                    if ok2 then
                        table.insert(ids, v)
                        if v == civ_id then found = true end
                    end
                end
                return found, ids
            end

            local att_match, att_ids = vec_has('attacker_civ')
            local def_match, def_ids = vec_has('defender_civ')
            local matches = att_match or def_match

            if matches then
                battle_match = battle_match + 1
                -- Print first 5 matching battles in detail.
                if battle_match <= 5 then
                    local bname_ok, bname = pcall(function()
                        return dfhack.translation.translateName(col.name, true)
                    end)
                    local name_str = (bname_ok and bname and bname ~= '') and bname or '(unnamed)'
                    local site_id = pcall(function() return col.site end) and col.site or -1
                    local site_name = '?'
                    if site_id and site_id >= 0 then
                        local site = df.global.world.world_data.sites[site_id]
                        if site then
                            local ok_sn, sn = pcall(function()
                                return dfhack.translation.translateName(site.name, true)
                            end)
                            site_name = (ok_sn and sn and sn ~= '') and sn or ('site#' .. site_id)
                        end
                    end
                    local yr = pcall(function() return col.start_year end) and col.start_year or '?'
                    local parent_id = pcall(function() return col.parent_collection end) and col.parent_collection or -1
                    local parent_type = '(none)'
                    if parent_id and parent_id >= 0 then
                        local parent = df.history_event_collection.find(parent_id)
                        if parent then
                            local ok_pt, pt = pcall(function()
                                return df.history_event_collection_type[parent:getType()]
                            end)
                            parent_type = (ok_pt and pt) or '?'
                            if parent_type == 'WAR' then
                                local ok_wn, wn = pcall(function()
                                    return dfhack.translation.translateName(parent.name, true)
                                end)
                                parent_type = 'WAR: ' .. ((ok_wn and wn and wn ~= '') and wn or '(unnamed)')
                            end
                        end
                    end

                    -- Count events and deaths.
                    local ok_evs, evs = pcall(function() return col.events end)
                    local ev_count = 0
                    local died_count = 0
                    local DIED_TYPE = df.history_event_type['HIST_FIGURE_DIED']
                    if ok_evs and evs then
                        local ok_n, n = pcall(function() return #evs end)
                        if ok_n then
                            ev_count = n
                            for ei = 0, n - 1 do
                                local ev = df.history_event.find(evs[ei])
                                if ev and DIED_TYPE then
                                    local ok_t, et = pcall(function() return ev:getType() end)
                                    if ok_t and et == DIED_TYPE then died_count = died_count + 1 end
                                end
                            end
                        end
                    end

                    -- Count child collections.
                    local ok_cc, cc = pcall(function() return col.collections end)
                    local child_count = 0
                    local child_died = 0
                    if ok_cc and cc then
                        local ok_cn, cn = pcall(function() return #cc end)
                        if ok_cn then
                            child_count = cn
                            for chi = 0, cn - 1 do
                                local child = df.history_event_collection.find(cc[chi])
                                if child then
                                    local ok_ce, ce = pcall(function() return child.events end)
                                    if ok_ce and ce then
                                        local ok_en, en = pcall(function() return #ce end)
                                        if ok_en then
                                            for ej = 0, en - 1 do
                                                local cev = df.history_event.find(ce[ej])
                                                if cev and DIED_TYPE then
                                                    local ok_ct, cet = pcall(function() return cev:getType() end)
                                                    if ok_ct and cet == DIED_TYPE then child_died = child_died + 1 end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end

                    print(('  BATTLE #%d: col_id=%d yr=%s'):format(battle_match, col.id, tostring(yr)))
                    print(('    name: %s'):format(name_str))
                    print(('    site: %s (id=%s)'):format(site_name, tostring(site_id)))
                    print(('    attacker_civ: %s'):format(table.concat(att_ids, ', ')))
                    print(('    defender_civ: %s'):format(table.concat(def_ids, ', ')))
                    print(('    parent: %s (id=%s)'):format(parent_type, tostring(parent_id)))
                    print(('    events: %d (deaths: %d), children: %d (child deaths: %d)'):format(
                        ev_count, died_count, child_count, child_died))
                end
            end
        end
    end
end

print(('--- Collection summary: %d WARs, %d BATTLEs total, %d BATTLEs match civ_id=%d ---'):format(
    war_count, battle_count, battle_match, civ_id))

-- 2b. If no direct matches, check what entity IDs battles actually contain.
--     Battles are likely fought by SiteGovernments, not the parent Civilization.
if battle_match == 0 and battle_count > 0 then
    print('--- No direct civ match. Probing SiteGovernment resolution ---')

    -- Build set of SiteGovernment entity IDs that belong to this civ.
    -- Uses the same 5-tier resolution as herald-gui build_civ_choices.
    local child_entity_ids = {}
    for _, ent in ipairs(df.global.world.entities.all) do
        if ent.type == df.historical_entity_type.SiteGovernment then
            -- Tier 2: position holder HF -> MEMBER link -> civ
            local resolved = false
            local ok_pa, pa = pcall(function() return ent.positions.assignments end)
            if ok_pa and pa then
                local ok_n, n = pcall(function() return #pa end)
                if ok_n then
                    for ai = 0, n - 1 do
                        local asgn = pa[ai]
                        local hf_id = asgn.histfig2
                        if hf_id and hf_id >= 0 then
                            local hf = df.historical_figure.find(hf_id)
                            if hf then
                                for _, link in ipairs(hf.entity_links) do
                                    local ok_lt, lt = pcall(function()
                                        return df.histfig_entity_link_type[link:getType()]
                                    end)
                                    if ok_lt and lt == 'MEMBER' then
                                        local link_ent = df.historical_entity.find(link.entity_id)
                                        if link_ent and link_ent.type == df.historical_entity_type.Civilization then
                                            if link.entity_id == civ_id then
                                                child_entity_ids[ent.id] = true
                                                resolved = true
                                            end
                                            break
                                        end
                                    end
                                end
                            end
                            if resolved then break end
                        end
                    end
                end
            end
        end
    end
    local child_count = 0
    for _ in pairs(child_entity_ids) do child_count = child_count + 1 end
    print(('  SiteGovernments belonging to civ: %d'):format(child_count))

    -- Re-scan battles checking for SiteGovernment IDs.
    local sg_battle_match = 0
    for ci = 0, total_cols - 1 do
        local col = all[ci]
        local ok4, ctype = pcall(function()
            return df.history_event_collection_type[col:getType()]
        end)
        if ok4 and ctype == 'BATTLE' then
            local ok_ac2, acv = pcall(function() return col.attacker_civ end)
            local ok_dc2, dcv = pcall(function() return col.defender_civ end)
            local found = false
            if ok_ac2 and acv then
                local ok_n, n = pcall(function() return #acv end)
                if ok_n then
                    for i = 0, n - 1 do
                        if child_entity_ids[acv[i]] then found = true; break end
                    end
                end
            end
            if not found and ok_dc2 and dcv then
                local ok_n, n = pcall(function() return #dcv end)
                if ok_n then
                    for i = 0, n - 1 do
                        if child_entity_ids[dcv[i]] then found = true; break end
                    end
                end
            end
            if found then
                sg_battle_match = sg_battle_match + 1
                if sg_battle_match <= 3 then
                    local att_ids, def_ids = {}, {}
                    if ok_ac2 and acv then
                        local ok_n, n = pcall(function() return #acv end)
                        if ok_n then for i = 0, n - 1 do table.insert(att_ids, acv[i]) end end
                    end
                    if ok_dc2 and dcv then
                        local ok_n, n = pcall(function() return #dcv end)
                        if ok_n then for i = 0, n - 1 do table.insert(def_ids, dcv[i]) end end
                    end
                    print(('  BATTLE via SiteGov #%d: col_id=%d'):format(sg_battle_match, col.id))
                    print(('    attacker_civ: %s'):format(table.concat(att_ids, ', ')))
                    print(('    defender_civ: %s'):format(table.concat(def_ids, ', ')))
                end
            end
        end
    end
    print(('  BATTLEs matching via SiteGovernment: %d'):format(sg_battle_match))
    if sg_battle_match > 0 then
        print('  DIAGNOSIS: civ_matches_collection needs SiteGovernment->Civ resolution for BATTLEs')
    end

    -- 2c. Dump entity IDs from first 5 battles to see what's actually in the vectors.
    print('--- Raw entity IDs in first 5 BATTLEs ---')
    local dumped = 0
    for ci = 0, total_cols - 1 do
        local col = all[ci]
        local ok5, ctype = pcall(function()
            return df.history_event_collection_type[col:getType()]
        end)
        if ok5 and ctype == 'BATTLE' then
            dumped = dumped + 1
            if dumped <= 5 then
                local att_ids, def_ids = {}, {}
                local ok_ac3, acv = pcall(function() return col.attacker_civ end)
                if ok_ac3 and acv then
                    local ok_n, n = pcall(function() return #acv end)
                    if ok_n then for i = 0, n - 1 do table.insert(att_ids, acv[i]) end end
                end
                local ok_dc3, dcv = pcall(function() return col.defender_civ end)
                if ok_dc3 and dcv then
                    local ok_n, n = pcall(function() return #dcv end)
                    if ok_n then for i = 0, n - 1 do table.insert(def_ids, dcv[i]) end end
                end
                -- Resolve entity types for each ID.
                local function describe_ids(ids)
                    local parts = {}
                    for _, eid in ipairs(ids) do
                        local ent = df.historical_entity.find(eid)
                        if ent then
                            local etype = df.historical_entity_type[ent.type] or '?'
                            local ename2 = dfhack.translation.translateName(ent.name, true)
                            if not ename2 or ename2 == '' then ename2 = '(unnamed)' end
                            table.insert(parts, ('%d=%s[%s]'):format(eid, etype, ename2))
                        else
                            table.insert(parts, ('%d=(not found)'):format(eid))
                        end
                    end
                    return #parts > 0 and table.concat(parts, ', ') or '(empty)'
                end
                print(('  BATTLE col_id=%d:'):format(col.id))
                print(('    attackers: %s'):format(describe_ids(att_ids)))
                print(('    defenders: %s'):format(describe_ids(def_ids)))
            end
        end
    end

    -- 2d. Dump what entity types the player civ's SiteGovernments are.
    print('--- Player civ child entities ---')
    print(('  Civ entity_id=%d, type=%s'):format(civ_id, tostring(df.historical_entity_type[entity.type])))
    for sg_id in pairs(child_entity_ids) do
        local sg = df.historical_entity.find(sg_id)
        if sg then
            local sgname = dfhack.translation.translateName(sg.name, true)
            print(('  SiteGov id=%d name="%s"'):format(sg_id, sgname or '?'))
        end
    end

    -- 2e. Test two resolution paths for matching battles to civs.
    print('--- Resolution path tests ---')

    -- Path A: parent WAR collection -> civ match.
    local via_parent = 0
    -- Path B: entity_populations -> civ_id.
    local via_entpop = 0
    -- Battles with no parent WAR.
    local orphan_battles = 0

    -- Build entity_pop -> civ_id lookup.
    local entpop_to_civ = {}
    for _, ep in ipairs(df.global.world.entity_populations) do
        if ep.civ_id and ep.civ_id >= 0 then
            entpop_to_civ[ep.id] = ep.civ_id
        end
    end

    local detailed = 0
    for ci = 0, total_cols - 1 do
        local col = all[ci]
        local ok7, ctype = pcall(function()
            return df.history_event_collection_type[col:getType()]
        end)
        if ok7 and ctype == 'BATTLE' then
            -- Path A: check parent WAR.
            local parent_match = false
            local ok_pid, pid = pcall(function() return col.parent_collection end)
            if ok_pid and pid and pid >= 0 then
                local parent = df.history_event_collection.find(pid)
                if parent then
                    local ok_pt, pt = pcall(function()
                        return df.history_event_collection_type[parent:getType()]
                    end)
                    if ok_pt and pt == 'WAR' then
                        -- Check WAR's attacker/defender_civ for our civ.
                        local ok_ac5, acv = pcall(function() return parent.attacker_civ end)
                        if ok_ac5 and acv then
                            local ok_n, n = pcall(function() return #acv end)
                            if ok_n then
                                for i = 0, n - 1 do
                                    if acv[i] == civ_id then parent_match = true; break end
                                end
                            end
                        end
                        if not parent_match then
                            local ok_dc5, dcv = pcall(function() return parent.defender_civ end)
                            if ok_dc5 and dcv then
                                local ok_n, n = pcall(function() return #dcv end)
                                if ok_n then
                                    for i = 0, n - 1 do
                                        if dcv[i] == civ_id then parent_match = true; break end
                                    end
                                end
                            end
                        end
                    end
                end
            else
                orphan_battles = orphan_battles + 1
            end
            if parent_match then via_parent = via_parent + 1 end

            -- Path B: check entity_populations.
            local entpop_match = false
            local function check_entpop_vec(fname)
                local ok_v, vec = pcall(function() return col[fname] end)
                if not ok_v or not vec then return false end
                local ok_n, n = pcall(function() return #vec end)
                if not ok_n then return false end
                for i = 0, n - 1 do
                    local ok2, epid = pcall(function() return vec[i] end)
                    if ok2 and entpop_to_civ[epid] == civ_id then return true end
                end
                return false
            end
            if check_entpop_vec('attacker_squad_entity_pop')
                or check_entpop_vec('defender_squad_entity_pops') then
                entpop_match = true
            end
            if entpop_match then via_entpop = via_entpop + 1 end

            -- Print detail for first 3 matches (either path).
            if (parent_match or entpop_match) and detailed < 3 then
                detailed = detailed + 1
                local bname_ok, bname = pcall(function()
                    return dfhack.translation.translateName(col.name, true)
                end)
                local name_s = (bname_ok and bname and bname ~= '') and bname or '(unnamed)'

                -- Determine side via entity_pop and sum squad deaths.
                local is_attacker = check_entpop_vec('attacker_squad_entity_pop')
                local att_deaths, def_deaths = 0, 0
                local function sum_deaths(vec_name)
                    local ok_v, vec = pcall(function() return col[vec_name] end)
                    if not ok_v or not vec then return 0 end
                    local ok_n, n = pcall(function() return #vec end)
                    if not ok_n then return 0 end
                    local total = 0
                    for i = 0, n - 1 do
                        local ok2, v = pcall(function() return vec[i] end)
                        if ok2 and v > 0 then total = total + v end
                    end
                    return total
                end
                att_deaths = sum_deaths('attacker_squad_deaths')
                def_deaths = sum_deaths('defender_squad_deaths')

                local killed = is_attacker and def_deaths or att_deaths
                local lost   = is_attacker and att_deaths or def_deaths

                -- Opponent via entity_pop.
                local opp_vec_name = is_attacker and 'defender_squad_entity_pops' or 'attacker_squad_entity_pop'
                local ok_ov, ov = pcall(function() return col[opp_vec_name] end)
                local opp_civ = nil
                if ok_ov and ov then
                    local ok_n, n = pcall(function() return #ov end)
                    if ok_n and n > 0 then
                        local ok2, epid = pcall(function() return ov[0] end)
                        if ok2 then opp_civ = entpop_to_civ[epid] end
                    end
                end
                local opp_name = '?'
                if opp_civ then
                    local opp_ent = df.historical_entity.find(opp_civ)
                    if opp_ent then
                        opp_name = dfhack.translation.translateName(opp_ent.name, true) or '?'
                    end
                end

                print(('  BATTLE col_id=%d: %s'):format(col.id, name_s))
                print(('    parent_war=%s, entpop=%s, side=%s'):format(
                    tostring(parent_match), tostring(entpop_match),
                    is_attacker and 'attacker' or 'defender'))
                print(('    squad deaths: att=%d def=%d -> killed=%d lost=%d'):format(
                    att_deaths, def_deaths, killed, lost))
                print(('    opponent civ: %s (id=%s)'):format(opp_name, tostring(opp_civ)))
            end
        end
    end

    print(('--- Results: via parent WAR=%d, via entity_pop=%d, orphan=%d (of %d total) ---'):format(
        via_parent, via_entpop, orphan_battles, battle_count))
end

-- 3. Check cache state.
local ok_cache, cache = pcall(dfhack.reqscript, 'herald-cache')
if ok_cache and cache then
    print(('Cache ready: %s, building: %s'):format(
        tostring(cache.cache_ready), tostring(cache.building)))
    local col_ids = cache.get_civ_collection_ids(civ_id)
    if col_ids then
        local battle_in_cache = 0
        for _, col_id in ipairs(col_ids) do
            local col = df.history_event_collection.find(col_id)
            if col then
                local ok2, ct = pcall(function()
                    return df.history_event_collection_type[col:getType()]
                end)
                if ok2 and ct == 'BATTLE' then battle_in_cache = battle_in_cache + 1 end
            end
        end
        print(('Cache: %d total collection IDs for civ, %d are BATTLEs'):format(
            #col_ids, battle_in_cache))
    else
        print('Cache: no collection IDs stored for this civ (nil)')
    end
else
    print('Cache: could not load herald-cache')
end

-- 4. Inline test of new helpers (get_parent_war_name, count_battle_deaths logic).
--    format_collection_entry and format_event are local to herald-event-history,
--    so we replicate the critical logic here to probe for errors.
local ok_eh, ev_hist = pcall(dfhack.reqscript, 'herald-event-history')
if ok_eh and ev_hist then
    local DIED_TYPE = df.history_event_type['HIST_FIGURE_DIED']
    print(('_DIED_TYPE resolved: %s'):format(tostring(DIED_TYPE)))

    for ci = 0, total_cols - 1 do
        local col = all[ci]
        local ok3, ctype = pcall(function()
            return df.history_event_collection_type[col:getType()]
        end)
        if ok3 and ctype == 'BATTLE' and ev_hist.civ_matches_collection(col, civ_id) then
            print(('--- Helper tests on BATTLE col_id=%d ---'):format(col.id))

            -- Test get_parent_war_name logic.
            local ok_pid, pid = pcall(function() return col.parent_collection end)
            print(('  parent_collection field access: ok=%s, value=%s'):format(
                tostring(ok_pid), tostring(pid)))
            if ok_pid and pid and pid >= 0 then
                local parent = df.history_event_collection.find(pid)
                if parent then
                    local ok_pt, ptype = pcall(function()
                        return df.history_event_collection_type[parent:getType()]
                    end)
                    print(('  parent type: ok=%s, value=%s'):format(tostring(ok_pt), tostring(ptype)))
                    if ok_pt and ptype == 'WAR' then
                        local ok_wn, wname = pcall(function()
                            return dfhack.translation.translateName(parent.name, true)
                        end)
                        print(('  parent war name: ok=%s, value="%s"'):format(
                            tostring(ok_wn), tostring(wname)))
                    end
                else
                    print('  parent collection not found via find()')
                end
            else
                print('  no parent collection (or field inaccessible)')
            end

            -- Test count_battle_deaths logic.
            local ok_ac, acv = pcall(function() return col.attacker_civ end)
            local ok_dc, dcv = pcall(function() return col.defender_civ end)
            local att_set, def_set = {}, {}
            if ok_ac and acv then
                local ok_n, n = pcall(function() return #acv end)
                if ok_n then for i = 0, n - 1 do att_set[acv[i]] = true end end
            end
            if ok_dc and dcv then
                local ok_n, n = pcall(function() return #dcv end)
                if ok_n then for i = 0, n - 1 do def_set[dcv[i]] = true end end
            end
            local focal_is_att = att_set[civ_id] or false
            local own_set   = focal_is_att and att_set or def_set
            local enemy_set = focal_is_att and def_set or att_set
            print(('  focal_is_attacker: %s'):format(tostring(focal_is_att)))

            -- Collect event IDs from battle + children.
            local event_ids = {}
            local ok_evs, evs = pcall(function() return col.events end)
            if ok_evs and evs then
                local ok_n, n = pcall(function() return #evs end)
                if ok_n then for i = 0, n - 1 do event_ids[evs[i]] = true end end
            end
            local ok_cc, cc = pcall(function() return col.collections end)
            if ok_cc and cc then
                local ok_cn, cn = pcall(function() return #cc end)
                if ok_cn then
                    for i = 0, cn - 1 do
                        local child = df.history_event_collection.find(cc[i])
                        if child then
                            local ok_ce, ce = pcall(function() return child.events end)
                            if ok_ce and ce then
                                local ok_en, en = pcall(function() return #ce end)
                                if ok_en then
                                    for j = 0, en - 1 do event_ids[ce[j]] = true end
                                end
                            end
                        end
                    end
                end
            end
            local total_eids = 0
            for _ in pairs(event_ids) do total_eids = total_eids + 1 end
            print(('  total event IDs (battle+children): %d'):format(total_eids))

            -- Count deaths by side.
            local enemy_killed, own_lost, unmatched = 0, 0, 0
            if DIED_TYPE then
                for eid, _ in pairs(event_ids) do
                    local ev = df.history_event.find(eid)
                    if ev then
                        local ok_t, etype = pcall(function() return ev:getType() end)
                        if ok_t and etype == DIED_TYPE then
                            local victim_id = ev_hist.safe_get(ev, 'victim_hf')
                            if victim_id and victim_id >= 0 then
                                local hf = df.historical_figure.find(victim_id)
                                if hf then
                                    local ok_el, elinks = pcall(function() return hf.entity_links end)
                                    local matched = false
                                    if ok_el and elinks then
                                        local ok_ln, ln = pcall(function() return #elinks end)
                                        if ok_ln then
                                            for li = 0, ln - 1 do
                                                local link = elinks[li]
                                                local ok_lt, ltype = pcall(function()
                                                    return df.histfig_entity_link_type[link:getType()]
                                                end)
                                                if ok_lt and (ltype == 'MEMBER' or ltype == 'FORMER_MEMBER') then
                                                    local ent_id = ev_hist.safe_get(link, 'entity_id')
                                                    if ent_id then
                                                        if enemy_set[ent_id] then
                                                            enemy_killed = enemy_killed + 1
                                                            matched = true; break
                                                        elseif own_set[ent_id] then
                                                            own_lost = own_lost + 1
                                                            matched = true; break
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                    if not matched then unmatched = unmatched + 1 end
                                end
                            end
                        end
                    end
                end
            end
            print(('  death counts: killed=%d, lost=%d, unmatched=%d'):format(
                enemy_killed, own_lost, unmatched))

            -- Show what the final output would look like.
            local bname_ok, bname = pcall(function()
                return dfhack.translation.translateName(col.name, true)
            end)
            local name = (bname_ok and bname and bname ~= '') and bname or nil
            local site_id = ev_hist.safe_get(col, 'site')
            local site_str = ''
            if site_id and site_id >= 0 then
                local site = df.global.world.world_data.sites[site_id]
                if site then
                    local ok_sn, sn = pcall(function()
                        return dfhack.translation.translateName(site.name, true)
                    end)
                    if ok_sn and sn and sn ~= '' then site_str = ' at ' .. sn end
                end
            end
            local deaths_str = ''
            if enemy_killed > 0 or own_lost > 0 then
                deaths_str = (' (killed %d, lost %d)'):format(enemy_killed, own_lost)
            end
            local war_str = ''
            if ok_pid and pid and pid >= 0 then
                local parent = df.history_event_collection.find(pid)
                if parent then
                    local ok_pt2, pt2 = pcall(function()
                        return df.history_event_collection_type[parent:getType()]
                    end)
                    if ok_pt2 and pt2 == 'WAR' then
                        local ok_wn2, wn2 = pcall(function()
                            return dfhack.translation.translateName(parent.name, true)
                        end)
                        if ok_wn2 and wn2 and wn2 ~= '' then
                            war_str = ' - part of ' .. wn2
                        end
                    end
                end
            end
            local base = name or 'battle'
            print(('  Expected output: "%s%s%s%s"'):format(base, site_str, deaths_str, war_str))
            print('  (opponent logic omitted from probe - tested separately in format_collection_entry)')
            break
        end
    end
else
    print('Could not load herald-event-history: ' .. tostring(ev_hist))
end

print('=== Probe complete ===')
