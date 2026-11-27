--[[
    SRC Placement Reference
    Extracted from AnimeAdventures.lua: Match.bestSpot / Match.lookAt / Match.place / Match.count
    This file is a reference extract from the original src and depends on the original
    Units, Core, Brain, App, Utils and Match runtime modules. The active executor file
    uses the compatible adapter in DKHUB_Autofarm1.lua because those modules are not
    available under the same names outside the original script.
]]

function Match.bestSpot(_Nb, aOb, bOb)
    if Match.focus and not aOb and not bOb and not Units.allyBuff(_Nb.id) then
        local cOb, dOb = Match.focusSpot(_Nb)
        if cOb then
            return cOb, dOb
        end
    end
    if not aOb and not bOb and not (Match.depth and Match.depth.leak) then
        local eOb, fOb, gOb = pcall(Match.controlSpot, _Nb)
        if eOb and fOb then
            return fOb, gOb
        end
        local hOb, iOb, jOb = pcall(Match.holdSpot, _Nb)
        if hOb and iOb then
            return iOb, jOb
        end
    end
    local kOb = Match.depth and Match.depth.leak
    if Match.layout and Match.layout [_Nb.id] and not aOb and not bOb then
        local lOb = false
        for mOb, nOb in ipairs(Match.mine or {
        }) do
            local oOb = nOb._stats:FindFirstChild("uuid")
            if oOb and oOb.Value == _Nb.uuid then
                lOb = true
                break
            end
        end
        if not lOb then
            for pOb, qOb in ipairs(Match.layout [_Nb.id]) do
                local rOb = Match.valid(qOb, _Nb.data)
                if rOb and kOb then
                    local sOb, tOb, uOb = false, Utils.flat(rOb), Units.range(_Nb.u, 0) * ((Match.info and tonumber(Match.info.rangeScale)) or 1)
                    for vOb, wOb in ipairs(Match.samples) do
                        if wOb.prog >= kOb + 0.02 and (Utils.flat(wOb.pos) - tOb).Magnitude <= uOb then
                            sOb = true
                            break
                        end
                    end
                    if not sOb then
                        rOb = nil
                    end
                end
                if rOb then
                    Match.layoutUsed = Match.layoutUsed or {
                    }
                    Match.layoutUsed [_Nb.id] = rOb
                    return rOb, Match.cover(rOb, Units.range(_Nb.u, math.min(3, Units.rows(_Nb.id).max)) * ((Match.info and tonumber(Match.info.rangeScale)) or 1))
                end
            end
        end
    end
    local xOb = _Nb.data
    local yOb = Match.depth
    local zOb
    if bOb then
        zOb = 1
        for AOb, BOb in ipairs(Match.mine or {
        }) do
            local COb = BOb._stats
            if not Units.isFarm(COb.id.Value) and not (COb:FindFirstChild("uuid") and COb.uuid.Value == _Nb.uuid) then
                local DOb, EOb = Utils.flat(BOb:GetPivot().Position), COb.range.Value
                for FOb, GOb in ipairs(Match.samples) do
                    if GOb.prog < zOb and (Utils.flat(GOb.pos) - DOb).Magnitude <= EOb then
                        zOb = GOb.prog
                    end
                end
            end
        end
        if Units.ENTRY [_Nb.id] or (Match.studyEntry and _Nb.id == Match.trialId) then
            zOb = math.min(zOb, 0.1)
        end
    end
    local HOb = (Match.info and tonumber(Match.info.rangeScale)) or 1
    local IOb = Units.range(_Nb.u, (yOb and yOb.leak) and 0 or math.min(3, Units.rows(_Nb.id).max)) * HOb
    local JOb = (Match.kind == "dungeon" or Match.style == "box" or Match.style == "fast") and not aOb and not (yOb and yOb.leak) and not Units.isFarm(_Nb.id) and Units.range(_Nb.u, Units.rows(_Nb.id).max) * HOb or nil
    local KOb = Units.allyBuff(_Nb.id)
    if Match.killZone() and not aOb and not bOb and not KOb and not (yOb and yOb.leak) and not Units.isFarm(_Nb.id) then
        local LOb = JOb or IOb
        local MOb = {
        }
        for NOb, OOb in ipairs(Match.mine or {
        }) do
            local POb = OOb._stats
            local QOb = POb.id.Value
            if not Units.isFarm(QOb) and not Units.allyBuff(QOb) and POb:FindFirstChild("range") then
                table.insert(MOb, {
                    p = Utils.flat(OOb:GetPivot().Position),
                    r = POb.range.Value
                })
            end
        end
        local ROb = {
        }
        for SOb, TOb in ipairs(Match.samples) do
            local UOb = 0
            local VOb = Utils.flat(TOb.pos)
            for WOb, XOb in ipairs(MOb) do
                if (VOb - XOb.p).Magnitude <= XOb.r then
                    UOb = UOb + 1
                end
            end
            ROb [SOb] = UOb
        end
        local YOb, ZOb, _Ob
        local aPb = 0
        for bPb, cPb in ipairs(Match.cands) do
            local dPb = Match.valid(cPb, xOb)
            aPb = aPb + 1
            if aPb % 40 == 0 then
                task.wait()
            end
            if dPb then
                local ePb, fPb, gPb = Utils.flat(dPb), 0, 0
                for hPb, iPb in ipairs(Match.samples) do
                    if (Utils.flat(iPb.pos) - ePb).Magnitude <= LOb then
                        gPb = gPb + 1
                        if iPb.prog >= 0.6 then
                            fPb = fPb + (iPb.prog - 0.5) * (1 + ROb [hPb])
                        end
                    end
                end
                if not ZOb or fPb > ZOb then
                    YOb, ZOb, _Ob = dPb, fPb, gPb
                end
            end
        end
        if YOb and ZOb > 0 then
            if not Match.zoneSaid then
                Match.zoneSaid = true
                App.log(1, "PLACE", "attackers stack on the road's last stretch, so what walks in takes everyone's damage at once")
            end
            return YOb, _Ob or 0
        end
    end
    if Match.style == "fast" and not aOb and not bOb and not KOb and not (yOb and yOb.leak) and not Units.isFarm(_Nb.id) then
        local jPb = JOb or IOb
        local kPb, lPb, mPb
        local nPb = 0
        for oPb, pPb in ipairs(Match.cands) do
            local qPb = Match.valid(pPb, xOb)
            nPb = nPb + 1
            if nPb % 40 == 0 then
                task.wait()
            end
            if qPb then
                local rPb, sPb, tPb = Utils.flat(qPb), 0, 0
                for uPb, vPb in ipairs(Match.samples) do
                    if (Utils.flat(vPb.pos) - rPb).Magnitude <= jPb then
                        tPb = tPb + 1
                        if vPb.prog <= Match.FAST_ROAD then
                            sPb = sPb + 1.5 - vPb.prog
                        end
                    end
                end
                if not lPb or sPb > lPb then
                    kPb, lPb, mPb = qPb, sPb, tPb
                end
            end
        end
        if kPb and lPb > 0 then
            return kPb, mPb or 0
        end
    end
    local wPb = Match.infinite and Match.trainee and not bOb and _Nb.uuid ~= Match.trainee and not Units.isFarm(_Nb.id) and not KOb and not aOb and not (yOb and yOb.leak) and (Match.pressure or 0) < Config.dangerReach and Training.ZONE or nil
    local xPb = wPb and Units.range(_Nb.u, Units.rows(_Nb.id).max) or nil
    local yPb, zPb = Units.types(_Nb.id)
    local APb = KOb and {
    } or Match.fieldBuffers()
    local BPb, CPb = {
    }, 0
    if KOb then
        BPb = Match.buffShort(KOb)
        for DPb, EPb in ipairs(BPb) do
            CPb = CPb + EPb.dps
        end
    end
    local FPb = Config.community and not zOb and Core.TIPS [_Nb.id]
    local GPb = ((FPb and FPb.spot == "exit") or (not zOb and Match.needLastLine(_Nb))) and not (yOb and yOb.leak)
    local HPb = not (zOb or aOb or KOb) and Match.mergeSpot(_Nb)
    local IPb = HPb and Units.range(_Nb.u, 0) * 0.7
    local JPb, KPb
    if aOb and Units.isFarm(_Nb.id) then
        JPb, KPb = Match.farmMergeSpot(_Nb)
        KPb = JPb and KPb * 0.8
    end
    local LPb = aOb and not JPb and Match.random and Units.isFarm(_Nb.id) and Match.farmMergeOk() and {
    } or nil
    local MPb = Match.cands
    local NPb, OPb = JPb or HPb, JPb and KPb or IPb
    if NPb and OPb and OPb > 0 then
        MPb = table.clone(Match.cands)
        for PPb, QPb in ipairs({
            0.5,
            0.7,
            0.9
        }) do
            for RPb = 0, 11 do
                local SPb = RPb * math.pi / 6
                table.insert(MPb, NPb + Vector3.new(math.cos(SPb), 0, math.sin(SPb)) * OPb * QPb)
            end
        end
    end
    local TPb, UPb, VPb
    local WPb = 0
    local XPb = Brain.maps [Match.mapKey()] and Brain.maps [Match.mapKey()].dens
    for YPb, ZPb in ipairs(MPb) do
        local _Pb = Match.valid(ZPb, xOb)
        WPb = WPb + 1
        if WPb % 40 == 0 then
            task.wait()
        end
        if _Pb then
            local aQb
            if aOb then
                aQb = - Match.cover(_Pb, IOb)
            elseif zOb then
                aQb = 0
                local bQb = Utils.flat(_Pb)
                for cQb, dQb in ipairs(Match.samples) do
                    if (Utils.flat(dQb.pos) - bQb).Magnitude <= IOb then
                        aQb = aQb + (dQb.prog <= zOb + 0.05 and 1 or 0.1)
                    end
                end
            elseif wPb then
                aQb = 0
                local eQb = Utils.flat(_Pb)
                for fQb, gQb in ipairs(Match.samples) do
                    local hQb = (Utils.flat(gQb.pos) - eQb).Magnitude
                    if gQb.prog < wPb then
                        if hQb <= xPb then
                            aQb = aQb - 2
                        end
                    elseif hQb <= IOb then
                        aQb = aQb + 1
                    end
                end
            elseif GPb then
                aQb = 0
                local iQb = Utils.flat(_Pb)
                for jQb, kQb in ipairs(Match.samples) do
                    if (Utils.flat(kQb.pos) - iQb).Magnitude <= IOb then
                        aQb = aQb + kQb.prog * kQb.prog
                    end
                end
            elseif KOb and CPb > 0 then
                local lQb = 0
                for mQb, nQb in ipairs(BPb) do
                    local oQb = (Utils.flat(nQb.pos) - Utils.flat(_Pb)).Magnitude
                    if oQb <= IOb then
                        lQb = lQb + nQb.dps * (1.1 - 0.1 * oQb / math.max(1, IOb))
                    end
                end
                aQb = lQb / CPb * 100 + Match.cover(_Pb, IOb, true) * 0.05
            else
                local pQb = Match.cover(_Pb, IOb, true, yOb)
                if JOb then
                    pQb = Match.cover(_Pb, JOb) + pQb * 0.25
                end
                aQb = pQb + (XPb and 0 or (1 - Match.progressAt(_Pb)) * 0.5)
                local qQb = 0
                for rQb, sQb in ipairs(APb) do
                    local tQb = sQb.b.types [zPb]
                    if tQb and (Utils.flat(sQb.pos) - Utils.flat(_Pb)).Magnitude <= sQb.range then
                        qQb = math.max(qQb, math.min(tQb, qQb + tQb * sQb.b.uptime))
                    end
                end
                aQb = aQb * (1 + qQb)
            end
            if HPb and (Utils.flat(HPb) - Utils.flat(_Pb)).Magnitude <= IPb then
                aQb = aQb + 1e6
            end
            if JPb and (Utils.flat(JPb) - Utils.flat(_Pb)).Magnitude <= KPb then
                aQb = aQb + 1e6
            end
            if LPb then
                table.insert(LPb, {
                    p = _Pb,
                    sc = aQb
                })
            end
            if not UPb or aQb > UPb then
                TPb, UPb, VPb = _Pb, aQb, Match.cover(_Pb, IOb)
            end
        end
    end
    if KOb and # BPb > 0 and TPb then
        local uQb = false
        for vQb, wQb in ipairs(BPb) do
            if (Utils.flat(wQb.pos) - Utils.flat(TPb)).Magnitude <= IOb then
                uQb = true
                break
            end
        end
        if not uQb then
            return nil, 0
        end
    end
    if LPb and # LPb > 0 then
        table.sort(LPb, function(xQb, yQb)
            return xQb.sc > yQb.sc
        end)
        for zQb = 1, math.min(15, # LPb) do
            local AQb, BQb = LPb [zQb].p, 0
            for CQb = 0, 7 do
                local DQb = CQb * math.pi / 4
                if Match.valid(AQb + Vector3.new(math.cos(DQb), 0, math.sin(DQb)) * 5, xOb) then
                    BQb = BQb + 1
                end
                if BQb >= 2 then
                    break
                end
            end
            if BQb >= 2 then
                return AQb, Match.cover(AQb, IOb)
            end
        end
    end
    return TPb, VPb or 0
end

function Match.lookAt(EQb)
    local FQb, GQb = math.huge, nil
    for HQb, IQb in ipairs(Match.samples) do
        local JQb = (Utils.flat(IQb.pos) - Utils.flat(EQb)).Magnitude
        if JQb < FQb then
            FQb, GQb = JQb, IQb.pos
        end
    end
    local KQb = GQb and Utils.flat(GQb - EQb) or Vector3.new(0, 0, - 1)
    return KQb.Magnitude > 0.01 and KQb.Unit or Vector3.new(0, 0, - 1)
end

function Match.place(LQb, MQb)
    local NQb = Units.isFarm(LQb.id)
    local OQb, PQb = Match.bestSpot(LQb, NQb or (Match.random and Units.idol(LQb.id)), (Match.trainee ~= nil and LQb.uuid == Match.trainee) or Units.ENTRY [LQb.id] == true or (Match.studyEntry == true and LQb.id == Match.trialId))
    if not OQb then
        Match.noSpot [LQb.uuid] = (Match.noSpot [LQb.uuid] or 0) + 1
        App.status("Placement", "no free spot for " .. Units.name(LQb.id))
        return false
    end
    local QQb = Match.money()
    local RQb, SQb = App.request("place", "spawn_unit", LQb.uuid, Core.Util.CFramePLV(OQb, Match.lookAt(OQb)))
    if RQb and SQb then
        Match.spent = Match.spent + (LQb.data.cost or 0)
        table.insert(Match.actions, string.format("placed %s", Units.name(LQb.id)))
        App.log(1, "PLACE", string.format("%s at %s (covers %d road samples) — %s", Units.name(LQb.id), Match.spotKey(OQb), PQb, MQb))
        Match.placeLog = Match.placeLog or {
        }
        table.insert(Match.placeLog, {
            t = math.floor(Utils.now() - (Match.startT or Utils.now())),
            w = Match.wave(),
            id = LQb.id,
            x = math.floor(OQb.X),
            z = math.floor(OQb.Z),
            cover = math.floor((PQb or 0) + 0.5),
            why = tostring(MQb):sub(1,
            90)
        })
        App.status("Placement", string.format("placed %s — %s", Units.name(LQb.id), MQb))
        Match.placedAt = Match.placedAt or {
        }
        Match.placedAt [LQb.uuid] = (Match.placedAt [LQb.uuid] or 0) + 1
        return true
    end
    if QQb >= (LQb.data.cost or 0) and Match.random then
        Match.placeFail = Match.placeFail or {
        }
        Match.placeFail [LQb.uuid] = (Match.placeFail [LQb.uuid] or 0) + 1
        if Match.placeFail [LQb.uuid] >= 2 then
            Match.noSpot [LQb.uuid] = 3
            App.log(1, "PLACE", string.format("the game refused %s twice (%d/%d units counted) — buying something else", Units.name(LQb.id), Match.fieldCount(), Match.FIELD_MAX))
        end
    end
    if RQb and QQb >= (LQb.data.cost or 0) and not Match.random then
        local TQb = Match.spotKey(OQb)
        Match.refused [TQb] = true
        local UQb = Match.mapKey()
        Brain.blocked [UQb] = Brain.blocked [UQb] or {
        }
        if not Match.refusedRun [TQb] then
            Brain.blocked [UQb] [TQb] = (tonumber(Brain.blocked [UQb] [TQb]) or 0) + 1
            Match.refusedRun [TQb] = true
        end
        Match.refusals = (Match.refusals or 0) + 1
        Match.unitRefusals [LQb.uuid] = (Match.unitRefusals [LQb.uuid] or 0) + 1
        if Match.unitRefusals [LQb.uuid] >= 3 then
            local VQb = math.max(1, Match.count(LQb.uuid))
            if Brain.caps [LQb.uuid] ~= VQb then
                Brain.caps [LQb.uuid] = VQb
                App.log(1, "PLACE", string.format("%s: the server allows %d on the field (learned)", Units.name(LQb.id), VQb))
            end
        end
        App.log(2, "PLACE", "refused spot " .. TQb .. " for " .. Units.name(LQb.id))
        App.saveSoon()
    end
    return false
end

function Match.count(WQb)
    local XQb = 0
    for YQb, ZQb in ipairs({
        workspace._UNITS,
        workspace:FindFirstChild("_DEAD_UNITS")
    }) do
        if ZQb then
            for _Qb, aRb in ipairs(ZQb:GetChildren()) do
                local bRb = aRb:FindFirstChild("_stats")
                if bRb and bRb:FindFirstChild("uuid") and bRb.player.Value == LocalPlayer and bRb.uuid.Value == WQb then
                    XQb = XQb + 1
                end
            end
        end
    end
    return XQb
