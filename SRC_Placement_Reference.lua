--[[
    RobScript Placement Extract
    Exact function bodies extracted from AnimeAdventures.lua (RobScript):
    Match.setupChecks, Match.valid, Match.buildCandidates, Match.coverage,
    Match.cover, Match.controlSpot, Match.holdSpot, Match.bestSpot,
    Match.lookAt, Match.place and Match.count.

    This is the original source extract for reference/integration. It depends on
    the original RobScript runtime modules (Units, Core, Brain, App, Utils,
    Simulator and Match state) and is not a standalone executor script.
]]

-- ===== source line 32183: Match.setupChecks =====
function Match.setupChecks()
    Match.probe = Instance.new("Part")
    Match.probe.Name = "_aa_probe"
    Match.probe.Anchored = true
    Match.probe.CanCollide = false
    Match.probe.CanTouch = false
    Match.probe.CanQuery = false
    Match.probe.Transparency = 1
    Match.probe.Parent = workspace:FindFirstChild("ignore") or workspace
    local dGb = ReplicatedStorage:FindFirstChild("_bounds")
    Match.bounds = Instance.new("Folder")
    Match.bounds.Name = "_aa_bounds"
    if dGb then
        for eGb, fGb in ipairs(dGb:GetDescendants()) do
            if fGb:IsA("BasePart") then
                local gGb = fGb:Clone()
                for hGb, iGb in ipairs(gGb:GetChildren()) do
                    iGb:Destroy()
                end
                gGb.Anchored = true
                gGb.CanCollide = false
                gGb.CanTouch = false
                gGb.CanQuery = true
                gGb.Transparency = 1
                gGb.CFrame = fGb.CFrame
                gGb.Parent = Match.bounds
            end
        end
    end
    Match.bounds.Parent = workspace:FindFirstChild("ignore") or workspace
    Match.overlap = OverlapParams.new()
    Match.overlap.FilterType = Enum.RaycastFilterType.Include
    Match.overlap.FilterDescendantsInstances = {
        workspace._road,
        Match.bounds
    }
end

-- ===== source line 32238: Match.valid =====
function Match.valid(nGb, oGb)
    local pGb = Core.PC.raycast(nGb + Vector3.new(0, 40, 0), Vector3.new(0, - 120, 0))
    if not pGb then
        return nil
    end
    if not Core.PC.is_valid_raycast_hit(pGb.Instance, oGb) then
        return nil
    end
    local qGb = pGb.Position
    if Match.blockedSpot(qGb) then
        return nil
    end
    local rGb = (tonumber(oGb.override_hitbox_radius) or 1.5) + 0.25
    Match.probe.Size = Vector3.new(rGb * 2, 2.5, rGb * 2)
    Match.probe.CFrame = CFrame.new(qGb + Vector3.new(0, 1.35, 0))
    if # workspace:GetPartsInPart(Match.probe, Match.overlap) > 0 then
        return nil
    end
    for sGb, tGb in ipairs(Match.mine or {
    }) do
        local uGb = tGb:FindFirstChild("_hitbox")
        local vGb = uGb and uGb.Position or tGb:GetPivot().Position
        local wGb = uGb and math.max(uGb.Size.X, uGb.Size.Z) / 2 or 1.5
        if (Utils.flat(qGb) - Utils.flat(vGb)).Magnitude < rGb + wGb then
            return nil
        end
    end
    return qGb
end

-- ===== source line 32268: Match.buildCandidates =====
function Match.buildCandidates()
    Match.cands = {
    }
    local xGb = {
    }
    for yGb = 1, # Match.samples, 3 do
        local zGb = Match.samples [yGb]
        local AGb = Match.samples [math.min(# Match.samples, yGb + 1)]
        local BGb = Utils.flat(AGb.pos - zGb.pos)
        if BGb.Magnitude < 0.01 then
            BGb = Vector3.new(1, 0, 0)
        end
        BGb = BGb.Unit
        local CGb = Vector3.new(- BGb.Z, 0, BGb.X)
        for DGb, EGb in ipairs({
            3,
            4.5,
            6,
            8,
            10.5,
            13.5,
            17
        }) do
            for FGb, GGb in ipairs({
                1,
                - 1
            }) do
                local HGb = zGb.pos + CGb * EGb * GGb
                local IGb = string.format("%d,%d", math.floor(HGb.X / 1.5), math.floor(HGb.Z / 1.5))
                if not xGb [IGb] then
                    xGb [IGb] = true
                    table.insert(Match.cands, HGb)
                end
            end
        end
    end
end

-- ===== source line 32306: Match.coverage =====
function Match.coverage(JGb, KGb)
    local LGb = {
    }
    for MGb, NGb in ipairs(JGb) do
        local OGb = NGb._stats
        if not Units.isFarm(OGb.id.Value) and OGb:FindFirstChild("range") then
            table.insert(LGb, {
                p = Utils.flat(NGb:GetPivot().Position),
                r = OGb.range.Value * (Units.SUMMONER [OGb.id.Value] and Units.SUMMONER [OGb.id.Value].reach or 1),
                air = Match.canAir(NGb)
            })
        end
    end
    local PGb, QGb = 0, 0
    if # LGb > 0 then
        for RGb, SGb in ipairs(Match.samples) do
            if SGb.prog > QGb then
                local TGb = Utils.flat(SGb.pos)
                for UGb, VGb in ipairs(LGb) do
                    if (TGb - VGb.p).Magnitude <= VGb.r then
                        if SGb.prog > PGb then
                            PGb = SGb.prog
                        end
                        if VGb.air then
                            QGb = SGb.prog
                            break
                        end
                    end
                end
            end
        end
    end
    local WGb, XGb = {
    }, Match.laneCount
    if XGb and XGb.n >= 2 and # LGb > 0 then
        local YGb = {
        }
        for ZGb, _Gb in ipairs(Match.samples) do
            local aHb = Utils.flat(_Gb.pos)
            for bHb, cHb in ipairs(LGb) do
                if (aHb - cHb.p).Magnitude <= cHb.r then
                    local dHb = tostring(_Gb.lane)
                    YGb [dHb] = (YGb [dHb] or 0) + 1
                    if _Gb.prog > (WGb [dHb] or 0) then
                        WGb [dHb] = _Gb.prog
                    end
                    break
                end
            end
        end
        local eHb, fHb = {
        }, 0
        for gHb, hHb in pairs(XGb.by) do
            eHb [gHb] = (YGb [gHb] or 0) / math.max(1, hHb)
            fHb = math.max(fHb, eHb [gHb])
        end
        Match.laneW = {
        }
        for iHb, jHb in pairs(XGb.by) do
            Match.laneW [iHb] = (XGb.avg / math.max(1, jHb)) * (1 + 1.5 * (fHb > 0 and (1 - eHb [iHb] / fHb) or 0))
        end
        Match.laneFrac = eHb
    else
        Match.laneW, Match.laneFrac = nil, nil
    end
    local kHb, lHb, mHb
    if # LGb > 0 then
        for nHb, oHb in ipairs(KGb) do
            local pHb = (Match.laneW and oHb.lane and WGb [oHb.lane]) or PGb
            if oHb.hp > 0 and oHb.prog > pHb + 0.02 and oHb.prog > (kHb or 0) then
                kHb, mHb = oHb.prog, Match.laneW and oHb.lane or nil
            end
            if oHb.hp > 0 and oHb.fly and oHb.prog > QGb + 0.02 then
                lHb = true
            end
        end
    end
    local qHb = # LGb > 0 and (Match.pressure or 0) >= PGb - 0.08
    return {
        covEnd = PGb,
        airEnd = QGb,
        leak = kHb,
        leakLane = mHb,
        covL = WGb,
        airLeak = lHb,
        push = qHb,
        units = # LGb
    }
end

-- ===== source line 32498: Match.cover =====
function Match.cover(WHb, XHb, YHb, ZHb)
    local _Hb = 0
    local aIb = Utils.flat(WHb)
    local bIb = YHb and Brain.maps [Match.mapKey()] and Brain.maps [Match.mapKey()].dens
    local cIb = Match.laneW
    for dIb, eIb in ipairs(Match.samples) do
        if (Utils.flat(eIb.pos) - aIb).Magnitude <= XHb then
            local fIb = 1
            if bIb then
                fIb = 0.15 + 0.85 * (tonumber(bIb [math.min(Simulator.BINS, math.floor(eIb.prog * Simulator.BINS) + 1)]) or 0)
            end
            if cIb then
                fIb = fIb * (cIb [tostring(eIb.lane)] or 1)
            end
            if ZHb then
                if ZHb.leak and eIb.prog >= ZHb.leak - 0.01 and (not ZHb.leakLane or tostring(eIb.lane) == ZHb.leakLane) then
                    fIb = fIb + 3
                elseif ZHb.push and eIb.prog > ZHb.covEnd then
                    fIb = fIb + 0.6
                end
            end
            _Hb = _Hb + fIb
        end
    end
    return _Hb
end

-- ===== source line 33136: Match.controlSpot =====
function Match.controlSpot(PMb, QMb)
    if not Match.killZone() then
        return nil
    end
    local RMb = Simulator.holds
    if not RMb(PMb.id) or Units.toggleOf(PMb.id) then
        return nil
    end
    local SMb, TMb, UMb, VMb = 1, 0, 0, {
    }
    for WMb, XMb in ipairs(Match.mine or {
    }) do
        local YMb = XMb._stats
        local ZMb = YMb.id.Value
        if YMb:FindFirstChild("range") and not Units.isFarm(ZMb) and not Units.allyBuff(ZMb) then
            local _Mb, aNb = Utils.flat(XMb:GetPivot().Position), YMb.range.Value
            if RMb(ZMb) and not Units.toggleOf(ZMb) then
                UMb = UMb + 1
                table.insert(VMb, {
                    p = _Mb,
                    r = aNb
                })
            else
                for bNb, cNb in ipairs(Match.samples) do
                    if (Utils.flat(cNb.pos) - _Mb).Magnitude <= aNb then
                        SMb, TMb = math.min(SMb, cNb.prog), math.max(TMb, cNb.prog)
                    end
                end
            end
        end
    end
    if TMb <= SMb then
        SMb, TMb = 0.75, 0.98
    end
    local dNb = (QMb or UMb) + 1
    local eNb = ({
        SMb,
        TMb,
        (SMb + TMb) / 2,
        SMb - (TMb - SMb) / 2
    }) [dNb]
    if not eNb then
        return nil
    end
    local fNb = Units.range(PMb.u, 0) * ((Match.info and tonumber(Match.info.rangeScale)) or 1)
    local gNb = {
    }
    for hNb, iNb in ipairs(Match.cands) do
        local jNb, kNb, lNb = Utils.flat(iNb), 0, 0
        for mNb, nNb in ipairs(Match.samples) do
            if (Utils.flat(nNb.pos) - jNb).Magnitude <= fNb then
                lNb = lNb + 1
                if math.abs(nNb.prog - eNb) <= 0.05 then
                    kNb = kNb + 1
                    local oNb = Utils.flat(nNb.pos)
                    for pNb, qNb in ipairs(VMb) do
                        if (oNb - qNb.p).Magnitude <= qNb.r then
                            kNb = kNb - 0.5
                            break
                        end
                    end
                end
            end
        end
        if kNb > 0 then
            table.insert(gNb, {
                pos = iNb,
                sc = kNb,
                cov = lNb
            })
        end
        if hNb % 60 == 0 then
            task.wait()
        end
    end
    table.sort(gNb, function(rNb, sNb)
        return rNb.sc > sNb.sc
    end)
    for tNb, uNb in ipairs(gNb) do
        local vNb = Match.valid(uNb.pos, PMb.data)
        if vNb then
            App.log(1, "PLACE", string.format("%s goes %s the kill box (%d%% of the road)", Units.name(PMb.id), Match.CONTROL_WORDS [dNb], math.floor(eNb * 100 + 0.5)))
            return vNb, uNb.cov, eNb
        end
        if tNb % 20 == 0 then
            task.wait()
        end
    end
    return nil
end

-- ===== source line 33227: Match.holdSpot =====
function Match.holdSpot(wNb)
    local xNb, yNb = Simulator.holds(wNb.id)
    if not xNb then
        return nil
    end
    local zNb, ANb = {
    }, 0
    for BNb, CNb in ipairs(Match.mine or {
    }) do
        local DNb = CNb._stats
        local ENb = DNb.id.Value
        if DNb:FindFirstChild("range") and not Units.isFarm(ENb) and not Units.allyBuff(ENb) and ENb ~= wNb.id then
            local FNb, GNb = pcall(Match.liveDps, CNb, ENb)
            GNb = FNb and tonumber(GNb) or 0
            if GNb > 0 then
                table.insert(zNb, {
                    p = Utils.flat(CNb:GetPivot().Position),
                    r = DNb.range.Value,
                    d = GNb
                })
                ANb = ANb + GNb
            end
        end
    end
    if # zNb == 0 or ANb <= 0 then
        return nil
    end
    local HNb = {
    }
    for INb, JNb in ipairs(Match.samples) do
        local KNb, LNb = Utils.flat(JNb.pos), 0
        for MNb, NNb in ipairs(zNb) do
            if (KNb - NNb.p).Magnitude <= NNb.r then
                LNb = LNb + NNb.d
            end
        end
        HNb [INb] = LNb / ANb
    end
    local ONb = Units.range(wNb.u, math.min(tonumber(yNb) or 0, 3, Units.rows(wNb.id).max)) * ((Match.info and tonumber(Match.info.rangeScale)) or 1)
    local PNb, QNb, RNb
    for SNb, TNb in ipairs(Match.cands) do
        local UNb, VNb, WNb = Utils.flat(TNb), 0, 0
        for XNb, YNb in ipairs(Match.samples) do
            if (Utils.flat(YNb.pos) - UNb).Magnitude <= ONb then
                VNb = VNb + HNb [XNb]
                WNb = WNb + 1
            end
        end
        if VNb > 0 and (not QNb or VNb > QNb) then
            local ZNb = Match.valid(TNb, wNb.data)
            if ZNb then
                PNb, QNb, RNb = ZNb, VNb, WNb
            end
        end
        if SNb % 40 == 0 then
            task.wait()
        end
    end
    if not PNb then
        return nil
    end
    Match.holdSaid = Match.holdSaid or {
    }
    if not Match.holdSaid [wNb.id] then
        Match.holdSaid [wNb.id] = true
        App.log(1, "PLACE", string.format("%s holds enemies, so it stands where your attackers' damage is: what it holds stays under all of them", Units.name(wNb.id)))
    end
    return PNb, RNb or 0
end

-- ===== source line 33297: Match.bestSpot =====
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

-- ===== source line 33618: Match.lookAt =====
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

-- ===== source line 33630: Match.place =====
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

-- ===== source line 33696: Match.count =====
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
end
