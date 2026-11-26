--[[
    FD Autofarm (Anime Adventures)  — เวอร์ชันรวมระบบจาก RobScript
    - ส่วน 1: หน้าโหลด | ส่วน 2: UI หลัก | ส่วน 3: ลอจิกออโต้ฟาร์ม (state machine)
    - การวางยูนิตอัตโนมัติ: ดัดแปลงแนวคิดจาก RobScript (Match.buildPath / buildCandidates /
      valid / bestSpot) ใช้โมดูลของเกม PathService + PlacementCore หาจุดที่ครอบคลุมถนนมากสุด
    - ชื่อ Remote มาจากต้นฉบับ (client_to_server.*) ค่าที่ไม่แน่ใจรวมไว้ใน CONFIG ([แก้ตรงนี้])
    หมายเหตุ: เขียนจากการอ่านโค้ดต้นฉบับเท่านั้น ยังไม่ได้ทดสอบในเกมจริง
]]

-- กันสคริปต์รันซ้อนกัน (เช่น autoexec + queue_on_teleport ทำงานพร้อมกัน)
if _G.FD_AUTOFARM_LOADED then return end
_G.FD_AUTOFARM_LOADED = true

-------------------------------------------------------------------------------
-- CONFIG
-------------------------------------------------------------------------------
local IMAGE_ID      = "rbxassetid://78028716933387"   -- โลโก้ของคุณ
local HUB_NAME      = "DKHUB AutoFram"
local RED           = Color3.fromRGB(220, 25, 35)   -- สีขอบ/ปุ่ม/แถบโหลด (ธีมแดง-ดำ)
local SAVE_FOLDER   = "FD_Autofarm"
local WEBHOOK_FILE  = SAVE_FOLDER .. "/webhook.txt"

local LOBBY_PLACE_ID = 8304191830        -- PlaceId ล็อบบี้ (จากต้นฉบับ)

-- ด่านแรก "World Keep": ถ้าใส่ FIRST_LEVEL_ID จะใช้ค่านั้นตรงๆ
-- ถ้าเว้นว่าง สคริปต์จะค้นชื่อด่าน/โลกในข้อมูลของเกม (Data.Levels/Worlds) ที่มีคำว่า LEVEL_SEARCH
local FIRST_LEVEL_ID = ""               -- [แก้ตรงนี้] ถ้ารู้ level id จริง
local LEVEL_SEARCH   = "keep"           -- คำค้นชื่อด่าน (ไม่สนตัวพิมพ์)
local DIFFICULTY     = "Normal"         -- ต้นฉบับใช้ "Normal"/"Hard"
-- วิธีเลือกด่าน (ดึงมาจากระบบ story ของ RobScript: Modes.list / Modes.done / Modes.open / Modes.diffOpen)
--   "progress" = ด่านถัดไปที่ "ยังไม่เคยชนะ" และปลดล็อกแล้ว ตามลำดับโลก/ด่านของเกม (Normal ก่อน แล้วค่อย Hard)
--                ได้เพชรรางวัลเคลียร์ครั้งแรก ถ้าชนะครบหมดแล้วจะฟาร์ม "ด่านล่าสุดที่บัญชีเราปลดล็อก" ต่อ
--   "search"   = ล็อกด่านตาม LEVEL_SEARCH ตลอด (ถ้าใส่ FIRST_LEVEL_ID จะใช้ค่านั้นก่อนเสมอ)
local STAGE_MODE     = "progress"
local FRIENDS_ONLY   = false

-- Remote (ReplicatedStorage.endpoints.client_to_server)
local R = {
    buyBanner   = "buy_from_banner",         -- (banner, method)
    equipUnit   = "equip_unit",              -- (uuid [, slot])
    joinLobby   = "request_join_lobby",      -- (lobbyName)
    lockLevel   = "request_lock_level",      -- (lobbyName, levelId, friendsOnly, difficulty)
    startGame   = "request_start_game",      -- (lobbyName)
    voteStart   = "vote_start",              -- ข้ามการรอเริ่มเวฟ
    spawnUnit   = "spawn_unit",              -- (uuid, CFrame)
    upgradeUnit = "upgrade_unit_ingame",     -- (unitInstance)
    finishVote  = "set_game_finished_vote",  -- ("next_story" | "replay")
    toLobby     = "teleport_back_to_lobby",
    autoPlay    = nil,                       -- [แก้ตรงนี้] ไม่พบ Remote เปิด Auto Play ในต้นฉบับ
}

-- สุ่ม unit
local BANNER        = "Standard"            -- [แก้ตรงนี้] "Standard" / "Special"
local SUMMON_METHOD = "gems10"
local GEM_THRESHOLD = 500
-- คำว่า "Mystic" ในสเปก: ในข้อมูลเกมระดับสูงสุดที่พบในต้นฉบับคือ "Mythic"  [แก้ตรงนี้ ถ้าเกมใช้ชื่ออื่น]
local MYSTIC_RARITY = "Mythic"
local MYSTIC_SLOT   = 6                  -- ตัวแรกสวมสล็อตนี้ ตัวถัดไปเลื่อนลงทีละช่อง (6, 5, ...)
local MYSTIC_STOP_AT = 2                  -- ได้ครบกี่ตัวแล้วหยุดสุ่ม แล้วฟาร์มยาวๆ ต่อ

-- จัดทีมที่ดีที่สุดให้เอง "ระหว่างที่ยังได้ Mythic ไม่ครบ" (จัดตอนอยู่ล็อบบี้)
-- เรียงตามระดับความหายาก > ตัว evolved > ดาเมจต่อวินาทีที่อัปสุด > เลเวล (เป็นการประมาณ ไม่ใช่ tier list ของเกม)
local BEST_TEAM        = true
local TEAM_SIZE        = 6                  -- [แก้ตรงนี้] จำนวนช่องทีม
local TEAM_FARM_SLOTS  = 1                  -- กันไว้ให้ยูนิตฟาร์มกี่ช่อง (0 = ไม่ใส่ฟาร์ม)

-- รันสคริปต์ซ้ำเองหลังเกมวาร์ป/รีจอยน์ (ต้องใช้ executor ที่มี queue_on_teleport)
-- ใส่อย่างใดอย่างหนึ่ง: SCRIPT_URL (ลิงก์ raw ของสคริปต์นี้) หรือเซฟไฟล์นี้ไว้ใน workspace ชื่อ SCRIPT_FILE
local SCRIPT_URL   = "https://raw.githubusercontent.com/nightEX1/FD_Autofarm/main/DKHUB_Autofarm.lua"
local SCRIPT_FILE  = "DKHUB_Autofarm.lua"      -- ไฟล์ในโฟลเดอร์ workspace ของ executor
local AUTO_REJOIN  = true                   -- หลุด/ถูกเตะ -> เข้าเกมใหม่เองแล้วรันสคริปต์ต่อ

local LOOP_DELAY = 0.5

-- ออโต้ข้ามเวฟ: ชื่อ Remote โหวตข้ามเวฟไม่มีในไฟล์ต้นฉบับ -> ใส่เองได้ ถ้าเว้นว่างจะค้นหาชื่อที่มีคำว่า "skip"
local SKIP_REMOTE   = nil               -- [แก้ตรงนี้] เช่น "vote_wave_skip" ถ้ารู้ชื่อจริง
-- ระบบฟาร์ม (ดัดแปลงจาก RobScript): ยูนิตฟาร์มวางก่อน อัปเกรดเฉพาะที่คืนทุนทัน และขายตอนเวฟสุดท้าย
local FARM_FIRST    = true
local SELL_FARM_LAST_WAVE = true

-------------------------------------------------------------------------------
-- Services / state
-------------------------------------------------------------------------------
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS           = game:GetService("ReplicatedStorage")
local UIS          = game:GetService("UserInputService")
local HttpService  = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Workspace    = game:GetService("Workspace")
local plr          = Players.LocalPlayer

local State = { running = false, webhook = "", mystics = 0, startedAt = nil }
local gui, setStatus

local function guiParent()
    if gethui then local ok, h = pcall(gethui) if ok and h then return h end end
    local ok, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok then return cg end
    return plr:WaitForChild("PlayerGui")
end

local function tween(obj, t, props, style, dir)
    local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function redStroke(obj, th)
    local st = Instance.new("UIStroke")
    st.Color, st.Thickness, st.ApplyStrokeMode = RED, th or 2, Enum.ApplyStrokeMode.Border
    st.Parent = obj
    return st
end

-- โลโก้: ถ้า ID ที่ให้มาเป็น Decal จะดึงรูปจริงออกมาให้ (ไม่งั้นรูปไม่ขึ้น) ถ้าเป็นรูปอยู่แล้วก็ใช้ตรงๆ
local LOGO = IMAGE_ID
local function resolveLogo()
    local id = tostring(IMAGE_ID):match("%d+")
    if not id or id == "0" then return end
    local done = false
    task.spawn(function()
        pcall(function()
            local objs = game:GetObjects("rbxassetid://" .. id)
            for _, o in ipairs(objs) do
                local tex
                if o:IsA("Decal") or o:IsA("Texture") then tex = o.Texture
                elseif o:IsA("ImageLabel") or o:IsA("ImageButton") then tex = o.Image end
                if tex and tex ~= "" then LOGO = tex break end
            end
            for _, o in ipairs(objs) do o:Destroy() end
        end)
        done = true
    end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < 4 do task.wait(0.05) end
end

local function remote(name)
    local ep = RS:FindFirstChild("endpoints")
    local c2s = ep and ep:FindFirstChild("client_to_server")
    return c2s and c2s:FindFirstChild(name)
end

-- เรียก Remote แบบกัน error + กันค้าง (timeout 15 วินาที เหมือน App.request ของ RobScript)
local function fire(name, ...)
    if not name then return false end
    local args = table.pack(...)
    local done, ok, res = false, false, nil
    task.spawn(function()
        ok, res = pcall(function()
            local r = remote(name)
            assert(r, "ไม่พบ Remote: " .. tostring(name))
            return r:InvokeServer(table.unpack(args, 1, args.n))
        end)
        done = true
    end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < 15 do task.wait(0.05) end
    if not done then warn("[FD] " .. name .. " timeout") return false end
    if not ok then warn("[FD] " .. name .. " ล้มเหลว: " .. tostring(res)) end
    return ok, res
end

-------------------------------------------------------------------------------
-- โมดูลของเกม (ใช้แบบเดียวกับ RobScript: Loader.load_core_service / load_data)
-------------------------------------------------------------------------------
local Game = {}
local function loadGame()
    local ok = pcall(function()
        local src = RS:WaitForChild("src", 30)
        Game.Loader = require(src:WaitForChild("Loader"))
        Game.Util   = require(src:WaitForChild("Util"))
        local L = Game.Loader
        Game.PC     = L.load_core_service(nil, "PlacementCore")
        Game.PATH   = L.load_core_service(nil, "PathService")
        Game.Units  = L.load_data(nil, "Units")
        Game.Levels = L.load_data(nil, "Levels")
        Game.Worlds = L.load_data(nil, "Worlds")
        Game.Waves  = L.load_data(nil, "Waves")
        Game.USC    = L.load_core_service(nil, "UnitServiceCore") -- ใช้เช็กว่าเป็นยูนิตฟาร์ม
        Game.PSC    = L.load_core_service(nil, "ProgressionServiceCore") -- เช็กด่าน/ความยากที่ปลดล็อก
        Game.WLO    = L.load_data(nil, "WorldLevelOrder")               -- ลำดับโลก/ด่านของเกม
    end)
    return ok
end

local function session()
    local ok, s = pcall(function() return Game.Loader.load_client_service(nil, "GUIService").session end)
    return ok and s or nil
end

-------------------------------------------------------------------------------
-- Webhook
-------------------------------------------------------------------------------
local function saveWebhook(url)
    url = tostring(url or ""):gsub("%s+", "")
    if url:sub(1, 33) ~= "https://discord.com/api/webhooks/" then return false, "URL ไม่ถูกต้อง" end
    State.webhook = url
    pcall(function()
        if writefile then
            if makefolder and isfolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
            writefile(WEBHOOK_FILE, url)
        end
    end)
    return true, "บันทึกแล้ว"
end

local function loadWebhook()
    pcall(function()
        if readfile and isfile and isfile(WEBHOOK_FILE) then State.webhook = readfile(WEBHOOK_FILE) end
    end)
end

-- เก็บสถานะลงไฟล์ (นับ Mythic, เวลาเริ่มรัน, เปิดสวิตช์ค้างไว้) เพื่อให้ต่อได้หลังเกมวาร์ปแล้วสคริปต์โหลดใหม่
-- ถ้าอยากเริ่มรอบใหม่ (นับ Mythic ใหม่) ให้ลบไฟล์ FD_Autofarm/state.json
local STATE_FILE = SAVE_FOLDER .. "/state.json"
local function saveState()
    pcall(function()
        if writefile then
            if makefolder and isfolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
            writefile(STATE_FILE, HttpService:JSONEncode({
                mystics = State.mystics, startedAt = State.startedAt, running = State.running }))
        end
    end)
end
local function loadState()
    pcall(function()
        if readfile and isfile and isfile(STATE_FILE) then
            local d = HttpService:JSONDecode(readfile(STATE_FILE))
            State.mystics = tonumber(d.mystics) or 0
            State.startedAt = tonumber(d.startedAt)
            State.running = d.running == true
        end
    end)
end
local function mysticDone() return State.mystics >= MYSTIC_STOP_AT end

local function sendWebhook(title, desc, color)
    if State.webhook == "" then return end
    task.spawn(function()
        local req = (syn and syn.request) or http_request or request or (fluxus and fluxus.request)
        if not req then return end
        pcall(req, {
            Url = State.webhook, Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({ embeds = {{
                title = title, description = desc, color = color or 5814783,
                footer = { text = HUB_NAME .. " • " .. plr.Name },
            }} }),
        })
    end)
end

-- ===== รันสคริปต์ซ้ำเองหลังวาร์ป/รีจอยน์ =====
local queued = false
local function queueReload()
    if queued then return true end
    local q = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
    if not q then warn("[FD] executor ไม่มี queue_on_teleport: ใช้โฟลเดอร์ autoexec แทน") return false end
    local code
    if SCRIPT_URL ~= "" then
        code = string.format("loadstring(game:HttpGet(%q))()", SCRIPT_URL)
    elseif readfile and isfile and isfile(SCRIPT_FILE) then
        code = string.format("loadstring(readfile(%q))()", SCRIPT_FILE)
    end
    if not code then
        warn("[FD] ไม่มีทั้ง SCRIPT_URL และไฟล์ " .. SCRIPT_FILE .. " ใน workspace: ยังรันซ้ำเองไม่ได้")
        return false
    end
    queued = pcall(q, code)
    return queued
end

-- ก่อนวาร์ป: ถ้าสวิตช์ฟาร์มเปิดอยู่ ให้เข้าคิวรันสคริปต์ในแมพถัดไป
local function hookTeleportQueue()
    plr.OnTeleport:Connect(function()
        _G.FD_AUTOFARM_LOADED = nil -- เผื่อ executor ที่ _G ไม่รีเซ็ตตอนวาร์ป จะได้ไม่บล็อกรอบถัดไป
        if State.running then queueReload() end
    end)
end

-- หลุด/ถูกเตะ (หน้าต่าง ErrorPrompt ของ Roblox) -> วาร์ปกลับล็อบบี้เอง แล้วสคริปต์โหลดใหม่และฟาร์มต่อ
local function hookAutoRejoin()
    if not AUTO_REJOIN then return end
    pcall(function()
        local overlay = game:GetService("CoreGui"):WaitForChild("RobloxPromptGui", 10)
        overlay = overlay and overlay:WaitForChild("promptOverlay", 10)
        if not overlay then return end
        overlay.ChildAdded:Connect(function(c)
            if c.Name ~= "ErrorPrompt" then return end
            task.spawn(function()
                task.wait(2)
                if State.running then queueReload() end
                while true do -- ถ้าวาร์ปไม่ติด ลองใหม่ทุก 10 วิ
                    pcall(function() TeleportService:Teleport(LOBBY_PLACE_ID, plr) end)
                    task.wait(10)
                end
            end)
        end)
    end)
end

-------------------------------------------------------------------------------
-- ส่วนที่ 1: หน้าโหลด
-------------------------------------------------------------------------------
local function createLoading()
    local sg = Instance.new("ScreenGui")
    sg.Name, sg.ResetOnSpawn, sg.IgnoreGuiInset, sg.DisplayOrder = "FD_Loading", false, true, 999
    sg.Parent = guiParent()

    local bg = Instance.new("Frame", sg)
    bg.Size, bg.BackgroundColor3, bg.BackgroundTransparency = UDim2.fromScale(1, 1), Color3.fromRGB(0, 0, 0), 0.1

    local box = Instance.new("Frame", bg)
    box.AnchorPoint, box.Position, box.Size = Vector2.new(.5, .5), UDim2.fromScale(.5, .5), UDim2.fromOffset(320, 260)
    box.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 14)
    redStroke(box, 2)

    local icon = Instance.new("ImageLabel", box)
    icon.AnchorPoint, icon.Position, icon.Size = Vector2.new(.5, 0), UDim2.new(.5, 0, 0, 30), UDim2.fromOffset(90, 90)
    icon.BackgroundTransparency, icon.Image = 1, LOGO
    local floatTween = TweenService:Create(icon,
        TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { Position = UDim2.new(.5, 0, 0, 10) })
    floatTween:Play()

    local pct = Instance.new("TextLabel", box)
    pct.Size, pct.Position, pct.BackgroundTransparency = UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 140), 1
    pct.Font, pct.TextSize, pct.TextColor3, pct.Text = Enum.Font.GothamBold, 22, Color3.new(1, 1, 1), "0%"

    local barBg = Instance.new("Frame", box)
    barBg.Size, barBg.Position = UDim2.new(1, -60, 0, 12), UDim2.new(0, 30, 0, 185)
    barBg.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)
    local bar = Instance.new("Frame", barBg)
    bar.Size, bar.BackgroundColor3 = UDim2.fromScale(0, 1), RED
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    tween(bar, 5, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
    local t0 = os.clock()
    while true do
        local p = math.clamp((os.clock() - t0) / 5, 0, 1)
        pct.Text = math.floor(p * 100) .. "%"
        if p >= 1 then break end
        task.wait()
    end
    pct.Text = "100%"
    floatTween:Cancel()

    for _, d in ipairs(sg:GetDescendants()) do
        if d:IsA("Frame") then tween(d, 0.6, { BackgroundTransparency = 1 }) end
        if d:IsA("TextLabel") then tween(d, 0.6, { TextTransparency = 1 }) end
        if d:IsA("ImageLabel") then tween(d, 0.6, { ImageTransparency = 1 }) end
        if d:IsA("UIStroke") then tween(d, 0.6, { Transparency = 1 }) end
    end
    task.wait(0.7)
    sg:Destroy()
end

-------------------------------------------------------------------------------
-- ส่วนที่ 2: UI หลัก
-------------------------------------------------------------------------------
local function createMainUI(onToggle)
    gui = Instance.new("ScreenGui")
    gui.Name, gui.ResetOnSpawn = "FD_Main", false
    gui.Parent = guiParent()

    local main = Instance.new("Frame", gui)
    main.AnchorPoint, main.Position = Vector2.new(.5, .5), UDim2.fromScale(.5, .5)
    main.Size, main.BackgroundColor3 = UDim2.fromOffset(300, 356), Color3.fromRGB(0, 0, 0)
    main.ClipsDescendants = true
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)
    local mainStroke = redStroke(main, 2)
    local scale = Instance.new("UIScale", main)

    local top = Instance.new("Frame", main)
    top.Size, top.BackgroundColor3 = UDim2.new(1, 0, 0, 32), Color3.fromRGB(22, 0, 0)
    local title = Instance.new("TextLabel", top)
    title.Size, title.Position, title.BackgroundTransparency = UDim2.new(1, -80, 1, 0), UDim2.fromOffset(10, 0), 1
    title.Font, title.TextSize, title.TextColor3, title.TextXAlignment = Enum.Font.GothamBold, 14, Color3.fromRGB(255, 70, 70), Enum.TextXAlignment.Left
    title.Text = HUB_NAME

    local function topBtn(txt, x)
        local b = Instance.new("TextButton", top)
        b.Size, b.Position, b.Text = UDim2.fromOffset(26, 22), UDim2.new(1, x, 0, 5), txt
        b.Font, b.TextSize, b.TextColor3, b.BackgroundColor3 = Enum.Font.GothamBold, 14, Color3.new(1, 1, 1), Color3.fromRGB(70, 10, 10)
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        return b
    end
    local minBtn, closeBtn = topBtn("–", -62), topBtn("×", -32)

    local body = Instance.new("Frame", main)
    body.Size, body.Position, body.BackgroundTransparency = UDim2.new(1, 0, 1, -32), UDim2.fromOffset(0, 32), 1

    local img = Instance.new("ImageLabel", body)
    img.AnchorPoint, img.Position, img.Size = Vector2.new(.5, 0), UDim2.new(.5, 0, 0, 10), UDim2.fromOffset(80, 80)
    img.BackgroundTransparency, img.Image = 1, LOGO

    local lbl = Instance.new("TextLabel", body)
    lbl.Size, lbl.Position, lbl.BackgroundTransparency = UDim2.new(1, -90, 0, 30), UDim2.fromOffset(16, 100), 1
    lbl.Font, lbl.TextSize, lbl.TextColor3, lbl.TextXAlignment = Enum.Font.GothamMedium, 14, Color3.new(1, 1, 1), Enum.TextXAlignment.Left
    lbl.Text = "Auto Kaitan / ออโต้ฟาร์ม"

    local sw = Instance.new("TextButton", body)
    sw.Size, sw.Position, sw.Text = UDim2.fromOffset(52, 26), UDim2.new(1, -68, 0, 102), ""
    sw.BackgroundColor3, sw.AutoButtonColor = Color3.fromRGB(45, 45, 45), false
    Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)
    local knob = Instance.new("Frame", sw)
    knob.Size, knob.Position, knob.BackgroundColor3 = UDim2.fromOffset(20, 20), UDim2.fromOffset(3, 3), Color3.new(1, 1, 1)
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local on = false
    local function setOn(v)
        on = v
        tween(knob, 0.2, { Position = on and UDim2.fromOffset(29, 3) or UDim2.fromOffset(3, 3) })
        tween(sw, 0.2, { BackgroundColor3 = on and RED or Color3.fromRGB(45, 45, 45) })
        onToggle(on)
    end
    sw.MouseButton1Click:Connect(function() setOn(not on) end)

    local tb = Instance.new("TextBox", body)
    tb.Size, tb.Position = UDim2.new(1, -32, 0, 30), UDim2.fromOffset(16, 150)
    tb.BackgroundColor3, tb.TextColor3, tb.PlaceholderText = Color3.fromRGB(16, 16, 16), Color3.new(1, 1, 1), "Discord Webhook URL"
    tb.Font, tb.TextSize, tb.ClearTextOnFocus, tb.Text = Enum.Font.Gotham, 12, false, State.webhook
    Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 8)
    redStroke(tb, 1)

    local save = Instance.new("TextButton", body)
    save.Size, save.Position, save.Text = UDim2.new(1, -32, 0, 30), UDim2.fromOffset(16, 188), "บันทึก"
    save.Font, save.TextSize, save.TextColor3, save.BackgroundColor3 = Enum.Font.GothamBold, 13, Color3.new(1, 1, 1), RED
    Instance.new("UICorner", save).CornerRadius = UDim.new(0, 8)

    local msg = Instance.new("TextLabel", body)
    msg.Size, msg.Position, msg.BackgroundTransparency = UDim2.new(1, -32, 0, 20), UDim2.fromOffset(16, 224), 1
    msg.Font, msg.TextSize, msg.TextColor3, msg.Text = Enum.Font.Gotham, 12, Color3.fromRGB(200, 200, 215), ""
    save.MouseButton1Click:Connect(function()
        local ok, text = saveWebhook(tb.Text)
        msg.Text = text
        msg.TextColor3 = ok and Color3.fromRGB(110, 220, 130) or Color3.fromRGB(240, 100, 100)
    end)

    local st = Instance.new("TextLabel", body)
    st.Size, st.Position, st.BackgroundTransparency = UDim2.new(1, -32, 0, 20), UDim2.fromOffset(16, 250), 1
    st.Font, st.TextSize, st.TextColor3, st.Text = Enum.Font.Gotham, 12, Color3.fromRGB(175, 175, 175), "สถานะ: พร้อม"
    setStatus = function(t) st.Text = "สถานะ: " .. t end

    -- แถวเวลารัน + จำนวน Mythic ที่ได้
    local info = Instance.new("TextLabel", body)
    info.Size, info.Position, info.BackgroundTransparency = UDim2.new(1, -32, 0, 20), UDim2.fromOffset(16, 272), 1
    info.Font, info.TextSize, info.TextColor3 = Enum.Font.GothamMedium, 12, Color3.fromRGB(255, 110, 110)
    info.TextXAlignment = Enum.TextXAlignment.Left
    task.spawn(function()
        while info.Parent do
            local t = State.startedAt and math.max(0, os.time() - State.startedAt) or 0
            info.Text = string.format("เวลารัน: %02d:%02d:%02d   Mythic: %d/%d%s",
                t // 3600, (t % 3600) // 60, t % 60, State.mystics, MYSTIC_STOP_AT, mysticDone() and " (หยุดสุ่ม)" or "")
            task.wait(1)
        end
    end)

    local minimized = false
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        tween(main, 0.25, { Size = minimized and UDim2.fromOffset(300, 32) or UDim2.fromOffset(300, 356) })
    end)
    closeBtn.MouseButton1Click:Connect(function()
        onToggle(false) -- หยุดและเซฟสถานะ ไม่ให้เปิดต่อเองรอบหน้า
        _G.FD_AUTOFARM_LOADED = nil -- ปิดหน้าต่างแล้ว รันสคริปต์ใหม่ได้
        tween(scale, 0.25, { Scale = 0 })
        task.wait(0.3)
        gui:Destroy()
    end)

    local dragging, dragStart, startPos
    top.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, i.Position, main.Position
            i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)

    scale.Scale, main.BackgroundTransparency, mainStroke.Transparency = 0.6, 1, 1
    tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
    tween(main, 0.45, { BackgroundTransparency = 0 })
    tween(mainStroke, 0.45, { Transparency = 0 })
    return setOn
end

-------------------------------------------------------------------------------
-- ส่วนที่ 3: ลอจิกออโต้ฟาร์ม
-------------------------------------------------------------------------------
local function say(t) if setStatus then setStatus(t) end print("[FD] " .. t) end
local function alive() return State.running end
local function inLobby() return game.PlaceId == LOBBY_PLACE_ID end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end

-- ยูนิตฟาร์ม (ใช้ UnitServiceCore ของเกม เหมือน Units.isFarm ใน RobScript)
local function isFarm(id)
    local ok, v = pcall(function() return Game.USC.unit_static_is_farm(id) end)
    return ok and v or false
end


local function money()
    local s = plr:FindFirstChild("_stats")
    return s and s:FindFirstChild("resource") and s.resource.Value or 0
end
local function gems()
    local ok, v = pcall(function() return plr._stats.gem_amount.Value end)
    return ok and v or 0
end

-- ===== ข้อมูลยูนิต =====
local function equippedUnits()
    local out = {}
    local s = session()
    if not s then return out end
    pcall(function()
        for slot, uuid in pairs(s.profile_data.collection.equipped_units or {}) do
            local u = s.collection:get_unit_by_uuid(uuid)
            if u and Game.Units[u.unit_id] then
                out[#out + 1] = { slot = tonumber(slot) or 0, uuid = uuid, id = u.unit_id, data = Game.Units[u.unit_id] }
            end
        end
    end)
    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out
end

local function ownedUnits()
    local ok, list = pcall(function()
        local svc = Game.Loader.load_client_service(nil, "ItemInventoryServiceClient")
        return svc.session.collection.collection_profile_data.owned_units
    end)
    return ok and list or {}
end

local function snapshotUuids()
    local s = {}
    for _, u in pairs(ownedUnits()) do s[u.uuid] = true end
    return s
end

-- ===== สุ่ม / สวมใส่ =====
local function summonUnit()
    say("กำลังสุ่ม unit")
    local ok = fire(R.buyBanner, BANNER, SUMMON_METHOD)
    task.wait(1.5)
    return ok
end

local function equipUnit(uuid, slot)
    if slot then return fire(R.equipUnit, uuid, slot) end
    return fire(R.equipUnit, uuid)
end

local function equipMystic(before)
    local found = 0
    for _, u in pairs(ownedUnits()) do
        if not before[u.uuid] then
            local info = Game.Units[u.unit_id]
            if info and tostring(info.rarity) == MYSTIC_RARITY then
                State.mystics += 1
                found += 1
                local name = tostring(info.name or u.unit_id)
                local slot = math.max(1, MYSTIC_SLOT - (State.mystics - 1))
                say("ได้ " .. MYSTIC_RARITY .. " ตัวที่ " .. State.mystics .. ": " .. name)
                equipUnit(u.uuid, slot)
                sendWebhook("🌟 สุ่มได้ " .. MYSTIC_RARITY .. " (" .. State.mystics .. "/" .. MYSTIC_STOP_AT .. ")",
                    "**" .. name .. "** — สวมใส่แล้วที่สล็อต " .. slot, 16766720)
            end
        end
    end
    if found > 0 then
        saveState()
        if mysticDone() then
            sendWebhook("🛑 ครบ " .. MYSTIC_STOP_AT .. " " .. MYSTIC_RARITY, "หยุดสุ่ม แล้วฟาร์มต่อเรื่อยๆ", 15158332)
        end
    end
    return found > 0
end

local function checkGems()
    if mysticDone() then return false end -- ครบแล้ว: ไม่สุ่มอีก
    if gems() < GEM_THRESHOLD then return false end
    local before = snapshotUuids()
    if summonUnit() then
        -- รอให้ยูนิตใหม่เข้าคลังจริง (สูงสุด 8 วิ) ไม่งั้นอาจนับ Mythic ตกหล่นแล้วสุ่มเกิน
        local t0 = os.clock()
        local arrived = false
        while os.clock() - t0 < 8 and not arrived do
            for _, u in pairs(ownedUnits()) do
                if not before[u.uuid] then arrived = true break end
            end
            if not arrived then task.wait(0.5) end
        end
        task.wait(1) -- ให้ครบทั้ง 10 ตัว
        equipMystic(before)
        return true
    end
    return false
end

-- ===== จัดทีมที่ดีที่สุด (ใช้ตอนยังได้ Mythic ไม่ครบ) =====
local RARITY_RANK = { common = 1, uncommon = 2, rare = 2, epic = 3, legendary = 4, mythic = 5, mystic = 5, secret = 6 }
local lastTeam = {} -- slot -> uuid ที่สคริปต์สวมไปแล้ว กันสวมซ้ำทุกรอบ

local function unitScore(u)
    local d = Game.Units and Game.Units[u.unit_id]
    if not d then return -1 end
    local rank = RARITY_RANK[tostring(d.rarity):lower()] or 0
    local dps = 0
    pcall(function()
        local up = d.upgrade
        local row = type(up) == "table" and up[#up]
        local dmg = tonumber(row and row.damage) or tonumber(d.damage) or 0
        local cd = tonumber(row and row.attack_cooldown) or tonumber(d.attack_cooldown) or 1
        dps = dmg / math.max(cd, 0.5)
    end)
    local evo = tostring(u.unit_id):find("_evolved", 1, true) and 1 or 0
    return rank * 1e6 + evo * 1e5 + dps * 10 + (tonumber(u.level) or 0)
end

local function equipBestTeam()
    if not BEST_TEAM or not Game.Units then return end
    local farms, atks = {}, {}
    for _, u in pairs(ownedUnits()) do
        local sc = unitScore(u)
        if sc >= 0 then
            local row = { uuid = u.uuid, id = u.unit_id, score = sc }
            if isFarm(u.unit_id) then farms[#farms + 1] = row else atks[#atks + 1] = row end
        end
    end
    local function byScore(a, b) return a.score > b.score end
    table.sort(farms, byScore)
    table.sort(atks, byScore)

    local team, usedId, usedUuid = {}, {}, {}
    local function take(list, n, allowDup)
        for pass = 1, allowDup and 2 or 1 do -- รอบแรกเอาตัวที่ไม่ซ้ำก่อน
            for _, r in ipairs(list) do
                if n <= 0 then return end
                if not usedUuid[r.uuid] and (pass == 2 or not usedId[r.id]) then
                    team[#team + 1] = r
                    usedUuid[r.uuid], usedId[r.id] = true, true
                    n -= 1
                end
            end
        end
    end
    local farmPart = {}
    take(farms, TEAM_FARM_SLOTS, false)
    for i = 1, #team do farmPart[i] = team[i] end
    local nFarm = #team
    team = {}
    take(atks, TEAM_SIZE - nFarm, true)
    local ordered = {}
    for _, r in ipairs(team) do ordered[#ordered + 1] = r end   -- ตัวโจมตีเก่งสุดได้สล็อตสูงสุด
    for _, r in ipairs(farmPart) do ordered[#ordered + 1] = r end
    if #ordered == 0 then return end

    local cur = {}
    for _, e in ipairs(equippedUnits()) do cur[e.slot] = e.uuid end
    local changed = 0
    for i, r in ipairs(ordered) do
        local slot = math.max(1, TEAM_SIZE - (i - 1))
        if cur[slot] ~= r.uuid and lastTeam[slot] ~= r.uuid then
            say("จัดทีม: " .. tostring(r.id) .. " -> สล็อต " .. slot)
            if equipUnit(r.uuid, slot) then lastTeam[slot] = r.uuid end
            changed += 1
            task.wait(0.4)
        end
    end
    if changed > 0 then
        sendWebhook("🛡️ จัดทีมที่ดีที่สุด", "เปลี่ยน " .. changed .. " สล็อต (ยังได้ Mythic " .. State.mystics .. "/" .. MYSTIC_STOP_AT .. ")", 3447003)
    end
end

-- ===== หาด่าน World Keep =====
-- คำที่ทำให้ตัดด่านทิ้ง (ไม่ใช่ด่านสตอรี่)
local LEVEL_EXCLUDE = { "infinite", "raid", "event", "portal", "dungeon", "challenge", "tutorial", "legend", "hunt", "artifact" }
local foundLevel

-- ลำดับด่านในโลก: ใช้ฟิลด์ลำดับของเกมถ้ามี ไม่งั้นใช้เลขท้าย id
local function levelOrder(id, lv)
    local n = tonumber(lv.order) or tonumber(lv.act) or tonumber(lv.level_order) or tonumber(lv.index)
    if n then return n end
    return tonumber(tostring(id):match("(%d+)$")) or 999
end

local function scanLevels(terms, useExclude)
    local cands = {}
    pcall(function()
        for id, lv in pairs(Game.Levels) do
            local w = lv.world and Game.Worlds[lv.world]
            local full = ((w and w.name or "") .. " " .. tostring(lv.name or id) .. " " .. tostring(id)):lower()
            local hit, bad = false, false
            for _, t in ipairs(terms) do if full:find(t, 1, true) then hit = true end end
            if useExclude then
                for _, x in ipairs(LEVEL_EXCLUDE) do if full:find(x, 1, true) then bad = true end end
            end
            if hit and not bad then
                cands[#cands + 1] = { id = id, ord = levelOrder(id, lv), name = tostring(lv.name or id) }
            end
        end
    end)
    return cands
end

-- LEVEL_SEARCH ใส่ได้หลายคำคั่นด้วย | เช่น "keep|world 1"; เลือกด่านลำดับน้อยสุดที่ตรง และพิมพ์ 5 อันดับแรกลง console
local function findFirstLevel()
    if FIRST_LEVEL_ID ~= "" then return FIRST_LEVEL_ID end
    if foundLevel then return foundLevel end
    local terms = {}
    for t in tostring(LEVEL_SEARCH):lower():gmatch("[^|]+") do terms[#terms + 1] = (t:gsub("^%s+", ""):gsub("%s+$", "")) end
    local cands = scanLevels(terms, true)
    if #cands == 0 then cands = scanLevels(terms, false) end -- ถ้าตัดจนหมด ลองอีกรอบแบบไม่ตัด
    table.sort(cands, function(a, b)
        if a.ord ~= b.ord then return a.ord < b.ord end
        return tostring(a.id) < tostring(b.id)
    end)
    for i = 1, math.min(5, #cands) do
        print(string.format("[FD] ด่านที่เจอ #%d: %s (%s) ลำดับ %s", i, tostring(cands[i].id), cands[i].name, tostring(cands[i].ord)))
    end
    foundLevel = cands[1] and cands[1].id
    return foundLevel
end

-- ===== ระบบเลือกด่านแบบ RobScript =====
-- Utils.list ของต้นฉบับ: ตารางที่ไม่ใช่ array (key เป็นตัวเลข) -> เรียงตาม key
local function listOf(t)
    if type(t) ~= "table" then return {} end
    if #t > 0 then return t end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = t[k] end
    return out
end

local function profile()
    local s = session()
    return s and s.profile_data
end

-- ด่านปลดล็อกแล้วไหม (Modes.open)
local function levelOpen(id)
    local s, lv = session(), Game.Levels and Game.Levels[id]
    if not (s and lv and Game.PSC) then return false end
    local ok, r = pcall(Game.PSC.check_if_unlocked_level, s, lv)
    return ok and r and true or false
end

-- ความยากนี้ปลดล็อกแล้วไหม (Modes.diffOpen)
local function diffOpen(id, diff)
    local s, lv = session(), Game.Levels and Game.Levels[id]
    if not (s and lv and Game.PSC) then return false end
    local ok, r = pcall(Game.PSC.check_if_unlocked_difficulty, s, lv, diff)
    return ok and r and true or false
end

-- เคยชนะด่าน+ความยากนี้แล้วไหม (Modes.done) ข้อมูลโปรไฟล์อัปเดตหลังวาร์ป จึงมีแคชชนะในรอบนี้ไว้ด้วย
local clearedCache = {}
local function levelDone(id, diff)
    if clearedCache[id .. ":" .. diff] then return true end
    local p = profile()
    local ld = p and p.level_data -- ต้นฉบับ: Core.prof().level_data.completed_story_levels
    local cd = ld and ld.completed_story_levels and ld.completed_story_levels[id]
    if not cd then return false end
    if cd.difficulty_completed_data then
        local d = cd.difficulty_completed_data[diff]
        return d and (tonumber(d.times_completed) or 0) > 0 or false
    end
    return (tonumber(cd.times_completed) or 0) > 0
end

local function markCleared()
    pcall(function()
        local ld = Game.Loader.LevelData
        if ld and ld.id then clearedCache[ld.id .. ":" .. tostring(ld._difficulty or "Normal")] = true end
    end)
end

local function stageName(id)
    local lv = Game.Levels and Game.Levels[id]
    if not lv then return tostring(id) end
    local w = lv.world and Game.Worlds and Game.Worlds[lv.world]
    return (w and w.name and (w.name .. " ") or "") .. tostring(lv.name or id)
end

local stageSkip = {} -- "id:diff" -> เวลาที่ห้ามเลือกซ้ำ (เซิร์ฟเวอร์ปฏิเสธการล็อกด่านนั้น)

-- ด่านถัดไปที่ยังไม่เคยชนะ: วนตามความยาก (Normal -> Hard) แล้วตามลำดับโลก/ด่านของเกม
-- ข้ามโลก legend/raid และด่านที่เป็นพอร์ทัล/เรด
local function nextUnclearedStage()
    local now = os.time()
    local order = listOf(Game.WLO and Game.WLO.WORLD_ORDER)
    for _, diff in ipairs({ "Normal", "Hard" }) do
        for rank, wid in ipairs(order) do
            local w = Game.Worlds and Game.Worlds[wid]
            if w and not w.legend_stage and not w.raid_world then
                for _, ref in ipairs(listOf(w.levels)) do
                    local id = type(ref) == "table" and ref.id
                    local lv = id and Game.Levels[id]
                    if lv and not lv._portal_only_level and not lv.is_raid
                        and (stageSkip[id .. ":" .. diff] or 0) <= now
                        and levelOpen(id) and diffOpen(id, diff) and not levelDone(id, diff) then
                        return id, diff, rank
                    end
                end
            end
        end
    end
end

-- ด่านล่าสุด (ลำดับสูงสุด) ที่บัญชีนี้ปลดล็อกแล้ว ใช้ตอนชนะครบทุกด่าน หรืออ่านประวัติการชนะไม่ได้
local function latestOpenStage()
    local now, best, bestRank = os.time(), nil, 0
    for rank, wid in ipairs(listOf(Game.WLO and Game.WLO.WORLD_ORDER)) do
        local w = Game.Worlds and Game.Worlds[wid]
        if w and not w.legend_stage and not w.raid_world then
            for _, ref in ipairs(listOf(w.levels)) do
                local id = type(ref) == "table" and ref.id
                local lv = id and Game.Levels[id]
                if lv and not lv._portal_only_level and not lv.is_raid
                    and (stageSkip[id .. ":" .. DIFFICULTY] or 0) <= now and levelOpen(id) then
                    best, bestRank = id, rank
                end
            end
        end
    end
    return best, bestRank
end

-- นับด่านที่เปิด/ชนะแล้ว (Normal) ไว้พิมพ์ debug
local function stageStats()
    local opened, done = 0, 0
    for _, wid in ipairs(listOf(Game.WLO and Game.WLO.WORLD_ORDER)) do
        local w = Game.Worlds and Game.Worlds[wid]
        if w and not w.legend_stage and not w.raid_world then
            for _, ref in ipairs(listOf(w.levels)) do
                local id = type(ref) == "table" and ref.id
                if id and Game.Levels[id] and levelOpen(id) then
                    opened += 1
                    if levelDone(id, "Normal") then done += 1 end
                end
            end
        end
    end
    return opened, done
end

local sessionWaited = false
-- คืน (levelId, difficulty) ของด่านที่จะเล่นรอบนี้
local function findStage()
    if FIRST_LEVEL_ID ~= "" then return FIRST_LEVEL_ID, DIFFICULTY end
    if STAGE_MODE == "progress" then
        if not sessionWaited then -- รอข้อมูลโปรไฟล์โหลดเสร็จ (สูงสุด 30 วิ) ไม่งั้นเช็กด่านที่ปลดล็อกไม่ได้
            local t0 = os.clock()
            while os.clock() - t0 < 30 do
                local s = session()
                if s and s._initialized ~= false then break end
                task.wait(0.5)
            end
            sessionWaited = true
        end
        local p = profile()
        local haveHistory = p and p.level_data ~= nil
        local opened, done = stageStats()
        print(string.format("[FD] ด่านที่เปิดแล้ว %d ด่าน / ชนะ Normal แล้ว %d ด่าน (อ่านประวัติ: %s)", opened, done, tostring(haveHistory)))
        if haveHistory then
            local id, diff, rank = nextUnclearedStage()
            if id then
                print(string.format("[FD] ด่านถัดไปที่ยังไม่เคยชนะ: %s (%s) โลกลำดับ %d", stageName(id), diff, rank))
                return id, diff
            end
        end
        -- ชนะครบแล้ว (หรืออ่านประวัติไม่ได้): เล่นด่านล่าสุดที่ปลดล็อกในบัญชีเรา ไม่ย้อนกลับไปด่าน 1
        local id, rank = latestOpenStage()
        if id then
            local diff = diffOpen(id, DIFFICULTY) and DIFFICULTY or "Normal"
            print(string.format("[FD] ฟาร์มด่านล่าสุดที่เปิดแล้ว: %s (%s) โลกลำดับ %d", stageName(id), diff, rank))
            return id, diff
        end
        print("[FD] หาด่านที่ปลดล็อกไม่ได้ -> ใช้ LEVEL_SEARCH")
    end
    return findFirstLevel(), DIFFICULTY
end

local function freeLobby()
    local lobbies = Workspace:FindFirstChild("_LOBBIES")
    local story = lobbies and lobbies:FindFirstChild("Story")
    if not story then return nil end
    for _, pad in ipairs(story:GetChildren()) do -- แท่นที่ไม่มีเจ้าของและไม่ได้ Active (เหมือน FarmHub.pad ของต้นฉบับ)
        local owner, active = pad:FindFirstChild("Owner"), pad:FindFirstChild("Active")
        if owner and owner.Value == nil and not (active and active.Value) then return pad end
    end
end

local function joinStage()
    local level, diff = findStage()
    if not level then say("หาด่านไม่เจอ: ใส่ FIRST_LEVEL_ID") return false end
    local pad = freeLobby()
    if not pad then return false end
    say("เข้าด่าน " .. stageName(level) .. " (" .. tostring(diff) .. ")")
    local ok1, r1 = fire(R.joinLobby, pad.Name)
    if not (ok1 and r1) then return false end
    local ok2, r2 = fire(R.lockLevel, pad.Name, level, FRIENDS_ONLY, diff)
    if not (ok2 and r2) then
        fire("request_leave_lobby", pad.Name)
        stageSkip[level .. ":" .. tostring(diff)] = os.time() + 1800 -- ด่านนี้ล็อกไม่ผ่าน: ข้ามไป 30 นาที
        return false
    end
    task.wait(0.5)
    fire(R.startGame, pad.Name)
    return true
end

-- ===== ระบบวางยูนิตอัตโนมัติ (ดัดแปลงจาก RobScript Match.*) =====
local Place = { samples = {}, cands = {}, refused = {}, ready = false }

-- สร้างจุดตัวอย่างตามถนนทุก lane (Match.buildPath)
local function buildPath()
    Place.samples = {}
    local cache = Game.PATH and Game.PATH.PATH_CACHE and Game.PATH.PATH_CACHE[Workspace._BASES.pve]
    if not cache then return false end
    for lane, info in pairs(cache) do
        if not (Game.PATH.HIDDEN_MOCK_LANES and Game.PATH.HIDDEN_MOCK_LANES[lane.Name]) then
            local pts = {}
            for _, p in ipairs(info.points or {}) do pts[#pts + 1] = p.part.Position end
            local total = 0
            for i = 2, #pts do total += (pts[i] - pts[i - 1]).Magnitude end
            local acc = 0
            for i = 2, #pts do
                local a, b = pts[i - 1], pts[i]
                local len = (b - a).Magnitude
                local n = math.max(1, math.floor(len / 2))
                for j = 0, n - 1 do
                    Place.samples[#Place.samples + 1] = { pos = a:Lerp(b, j / n), prog = (acc + len * j / n) / math.max(1, total), lane = lane.Name }
                end
                acc += len
            end
            if pts[#pts] then Place.samples[#Place.samples + 1] = { pos = pts[#pts], prog = 1, lane = lane.Name } end
        end
    end
    return #Place.samples > 0
end

-- สร้างจุดผู้สมัครเว้นระยะข้างถนน (Match.buildCandidates)
local function buildCandidates()
    Place.cands = {}
    local seen = {}
    for i = 1, #Place.samples, 2 do
        local a = Place.samples[i]
        local b = Place.samples[math.min(#Place.samples, i + 1)]
        local dir = flat(b.pos - a.pos)
        dir = dir.Magnitude < 0.01 and Vector3.new(1, 0, 0) or dir.Unit
        local side = Vector3.new(-dir.Z, 0, dir.X)
        for _, off in ipairs({ 3, 4.5, 6, 8, 10.5, 13.5, 17 }) do
            for _, sgn in ipairs({ 1, -1 }) do
                local p = a.pos + side * off * sgn
                local key = string.format("%d,%d", math.floor(p.X / 1.5), math.floor(p.Z / 1.5))
                if not seen[key] then seen[key] = true Place.cands[#Place.cands + 1] = p end
            end
        end
    end
end

-- ตัวตรวจจุดวาง (Match.setupChecks)
local function setupChecks()
    if Place.probe then Place.probe:Destroy() end
    Place.probe = Instance.new("Part")
    Place.probe.Anchored, Place.probe.CanCollide, Place.probe.CanTouch, Place.probe.CanQuery = true, false, false, false
    Place.probe.Transparency = 1
    Place.probe.Parent = Workspace:FindFirstChild("ignore") or Workspace
    if Place.bounds then Place.bounds:Destroy() end
    Place.bounds = Instance.new("Folder")
    local src = RS:FindFirstChild("_bounds")
    if src then
        for _, p in ipairs(src:GetDescendants()) do
            if p:IsA("BasePart") then
                local c = p:Clone()
                for _, ch in ipairs(c:GetChildren()) do ch:Destroy() end
                c.Anchored, c.CanCollide, c.CanTouch, c.CanQuery, c.Transparency = true, false, false, true, 1
                c.CFrame = p.CFrame
                c.Parent = Place.bounds
            end
        end
    end
    Place.bounds.Parent = Workspace:FindFirstChild("ignore") or Workspace
    Place.overlap = OverlapParams.new()
    Place.overlap.FilterType = Enum.RaycastFilterType.Include
    Place.overlap.FilterDescendantsInstances = { Workspace:FindFirstChild("_road"), Place.bounds }
end

local function spotKey(p) return string.format("%d,%d", math.floor(p.X + 0.5), math.floor(p.Z + 0.5)) end

local function myUnits()
    local out = {}
    local folder = Workspace:FindFirstChild("_UNITS")
    if not folder then return out end
    for _, u in ipairs(folder:GetChildren()) do
        local st = u:FindFirstChild("_stats")
        if st and st:FindFirstChild("player") and st.player.Value == plr then out[#out + 1] = u end
    end
    return out
end

-- ตรวจว่าจุดวางได้ (Match.valid): raycast ลงพื้น + PlacementCore + ไม่ทับถนน/ยูนิตอื่น
local function validSpot(p, unitData, mine)
    local hit = Game.PC.raycast(p + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0))
    if not hit or not Game.PC.is_valid_raycast_hit(hit.Instance, unitData) then return nil end
    local pos = hit.Position
    if Place.refused[spotKey(pos)] then return nil end
    local r = (tonumber(unitData.override_hitbox_radius) or 1.5) + 0.25
    Place.probe.Size = Vector3.new(r * 2, 2.5, r * 2)
    Place.probe.CFrame = CFrame.new(pos + Vector3.new(0, 1.35, 0))
    if #Workspace:GetPartsInPart(Place.probe, Place.overlap) > 0 then return nil end
    for _, u in ipairs(mine) do
        local hb = u:FindFirstChild("_hitbox")
        local up = hb and hb.Position or u:GetPivot().Position
        local ur = hb and math.max(hb.Size.X, hb.Size.Z) / 2 or 1.5
        if (flat(pos) - flat(up)).Magnitude < r + ur then return nil end
    end
    return pos
end

-- ระยะโจมตีตอนวาง: ใช้ระยะตอนอัปเกรดสุด (ยูนิตจะถูกอัปจนสุดอยู่แล้ว) เหมือนที่ RobScript นับ "ที่ระยะเต็ม"
local function unitRange(unitData)
    local up = unitData.upgrade
    local row = type(up) == "table" and up[#up]
    return tonumber(row and row.range) or tonumber(unitData.range) or 20
end

-- นับว่าแต่ละจุดบนถนนมียูนิตโจมตีของเราครอบคลุมอยู่กี่ตัวแล้ว (ไม่นับฟาร์ม)
local function coverCounts(mine)
    local cov = {}
    for i = 1, #Place.samples do cov[i] = 0 end
    for _, u in ipairs(mine) do
        pcall(function()
            local id = u._stats.id.Value
            if isFarm(id) then return end
            local d = Game.Units[id]
            if not d then return end
            local r, p = unitRange(d), flat(u:GetPivot().Position)
            for i, s in ipairs(Place.samples) do
                if (flat(s.pos) - p).Magnitude <= r then cov[i] += 1 end
            end
        end)
    end
    return cov
end

-- เลือกจุดวาง:
--  * ยูนิตโจมตี: จุดที่คะแนนครอบคลุมถนนสูงสุด โดยท้ายถนนมีน้ำหนักมาก (prog^2) และจุดที่มียูนิตครอบคลุมแล้วถูกลดคะแนน
--    -> ตัวถัดไปขยับไปคลุมช่วงที่ยังโล่ง แต่ยังรวมแน่นช่วงท้ายถนนที่ศัตรูต้องผ่าน
--  * ยูนิตฟาร์ม: เลือกจุดที่ใช้ได้แต่คะแนนต่ำสุด เก็บจุดดีไว้ให้ยูนิตโจมตี
local function bestSpot(unit, mine)
    local farm = isFarm(unit.id)
    local range = unitRange(unit.data)
    local cov = coverCounts(mine)
    local bestPos, bestScore
    local n = 0
    for _, c in ipairs(Place.cands) do
        local pos = validSpot(c, unit.data, mine)
        n += 1
        if n % 40 == 0 then task.wait() end
        if pos then
            local fp, score = flat(pos), 0
            for i, s in ipairs(Place.samples) do
                if (flat(s.pos) - fp).Magnitude <= range then
                    score += (1 + 2 * s.prog * s.prog) / (1 + 0.35 * cov[i])
                end
            end
            if farm then
                if not bestScore or score < bestScore then bestPos, bestScore = pos, score end
            elseif score > 0 and (not bestScore or score > bestScore) then
                bestPos, bestScore = pos, score
            end
        end
    end
    return bestPos, bestScore
end

local function lookAt(pos)
    local nearest, d = nil, math.huge
    for _, s in ipairs(Place.samples) do
        local m = (flat(s.pos) - flat(pos)).Magnitude
        if m < d then d, nearest = m, s.pos end
    end
    local v = nearest and flat(nearest - pos) or Vector3.new(0, 0, -1)
    return v.Magnitude > 0.01 and v.Unit or Vector3.new(0, 0, -1)
end

local function prepareMatch()
    if Place.ready then return true end
    if not buildPath() then return false end
    buildCandidates()
    setupChecks()
    Place.refused = {}
    Place.ready = true
    return true
end

local function placeUnits(noWait)
    if not prepareMatch() then say("ยังหาเส้นทางไม่เจอ") return end
    say("วางตัวละคร")
    local placed = {}
    for _, u in ipairs(myUnits()) do
        local st = u:FindFirstChild("_stats")
        if st and st:FindFirstChild("uuid") then placed[st.uuid.Value] = true end
    end
    local order = equippedUnits()
    if FARM_FIRST then
        table.sort(order, function(a, b)
            local fa, fb = isFarm(a.id) and 0 or 1, isFarm(b.id) and 0 or 1
            if fa ~= fb then return fa < fb end
            return a.slot < b.slot
        end)
    end
    for _, unit in ipairs(order) do
        if not alive() then return end
        if not placed[unit.uuid] then
            local cost = tonumber(unit.data.cost) or 0
            local tries = 0
            while not noWait and alive() and money() < cost and tries < 120 and not Workspace._DATA.GameFinished.Value do
                tries += 1 task.wait(0.5) -- รอเงินพอ (ยูนิตตัวต่อไปค่อยวางทีหลัง)
            end
            if money() >= cost then
                for attempt = 1, 3 do -- จุดโดนเซิร์ฟเวอร์ปฏิเสธ -> หาจุดใหม่ ลองสูงสุด 3 ครั้ง
                    if not alive() then return end
                    local pos, score = bestSpot(unit, myUnits())
                    if not pos then break end
                    local ok, res = fire(R.spawnUnit, unit.uuid, Game.Util.CFramePLV(pos, lookAt(pos)))
                    if ok and res then
                        placed[unit.uuid] = true
                        print(string.format("[FD] วาง %s ที่ %s (คะแนน %.1f)", tostring(unit.id), spotKey(pos), score or 0))
                        break
                    end
                    Place.refused[spotKey(pos)] = true -- จำจุดที่เซิร์ฟเวอร์ปฏิเสธ
                end
            end
            task.wait(0.4)
        end
    end
end

-- มียูนิตในทีมที่ยังไม่ได้วางในสนามไหม (ไว้ตรวจซ้ำระหว่างแมตช์)
local function hasUnplaced()
    local placed = {}
    for _, u in ipairs(myUnits()) do
        local st = u:FindFirstChild("_stats")
        if st and st:FindFirstChild("uuid") then placed[st.uuid.Value] = true end
    end
    for _, unit in ipairs(equippedUnits()) do
        if not placed[unit.uuid] then return true end
    end
    return false
end

-- ===== ระบบฟาร์ม (ดึงแนวคิดจาก RobScript: Units.isFarm / lastWaveCash / farm vs damage) =====
local function wave()
    local w = Workspace:FindFirstChild("_wave_num")
    return w and w.Value or 0
end

-- จำนวนเวฟทั้งหมดของด่าน (Match.buildWaves แบบย่อ; ด่าน bound ปกติจบที่ 15)
local function totalWaves()
    local ok, total = pcall(function()
        local ld = Game.Loader.LevelData
        if not ld then return nil end
        if tonumber(ld._override_infinite_bound_waves) then return tonumber(ld._override_infinite_bound_waves) end
        local w = Game.Waves[ld.waves or ld.id]
        local list = type(w) == "table" and (w.override_waves or w.waves)
        local n = type(list) == "table" and #list or 0
        if ld._infinite_bound_level then return n > 0 and math.min(n, 15) or 15 end
        return n > 0 and n or 15
    end)
    return ok and total or 15
end

-- รายได้ฟาร์มต่อเวฟของแถวอัปเกรด
local function farmGain(data, idx)
    local up = data.upgrade or {}
    local cur = idx == 0 and (tonumber(data.farm_amount) or 0) or (tonumber(up[idx] and up[idx].farm_amount) or 0)
    local nxt = tonumber(up[idx + 1] and up[idx + 1].farm_amount) or cur
    return nxt - cur
end

local function autoUpgrade()
    local remaining = math.max(0, totalWaves() - wave())
    local list = myUnits()
    -- ฟาร์มก่อน แล้วค่อยยูนิตโจมตี
    table.sort(list, function(a, b)
        local fa = isFarm(a._stats.id.Value) and 0 or 1
        local fb = isFarm(b._stats.id.Value) and 0 or 1
        return fa < fb
    end)
    for _, u in ipairs(list) do
        if not alive() then return end
        pcall(function()
            local st = u._stats
            local id = st.id.Value
            local data = Game.Units[id]
            local idx = tonumber(st.upgrade.Value) or 0
            local nextRow = data and data.upgrade and data.upgrade[idx + 1]
            if not nextRow then return end
            local cost = tonumber(nextRow.cost) or math.huge
            if money() < cost then return end
            if isFarm(id) then
                -- ฟาร์ม: อัปเกรดเฉพาะเมื่อเวฟที่เหลือคืนทุนทัน
                local gain = farmGain(data, idx)
                if gain <= 0 or gain * remaining < cost then return end
            end
            fire(R.upgradeUnit, u)
            task.wait(0.15)
        end)
    end
end

-- เวฟสุดท้าย: ขายฟาร์มเอาเงินไปลงดาเมจ (ฟาร์มไม่จ่ายหลังเวฟนี้) เลือกตัวที่ลงทุนมากสุดก่อน
local soldFarm = {}
local function sellFarmLastWave()
    if not SELL_FARM_LAST_WAVE or wave() < totalWaves() then return end
    local best, bestSpent
    for _, u in ipairs(myUnits()) do
        local st = u._stats
        local id = st.id.Value
        local d = Game.Units[id]
        if isFarm(id) and not (d and d.unsellable) and (soldFarm[u] or 0) < 2 then
            local spent = st:FindFirstChild("total_spent") and tonumber(st.total_spent.Value) or 0
            if not bestSpent or spent > bestSpent then best, bestSpent = u, spent end
        end
    end
    if best then
        soldFarm[best] = (soldFarm[best] or 0) + 1
        fire("sell_unit_ingame", best)
        print("[FD] เวฟสุดท้าย: ขายฟาร์ม เอาเงินไปลงดาเมจ")
    end
end

-- ===== ออโต้ข้ามเวฟ =====
-- ต้นฉบับ RobScript อ่านค่า LocalPlayer._settings.autoskip_waves และฟังอีเวนต์ start_vote_wave_skip
-- แต่ไม่มีโค้ดส่งโหวต จึงหา Remote ที่ชื่อมีคำว่า "skip" ตอนรันแล้วโหวตให้เมื่อมีอีเวนต์
local skipRemoteName, skipWarned
local function findSkipRemote()
    if SKIP_REMOTE then return SKIP_REMOTE end
    if skipRemoteName ~= nil then return skipRemoteName or nil end
    skipRemoteName = false
    pcall(function()
        for _, r in ipairs(RS.endpoints.client_to_server:GetChildren()) do
            if r.Name:lower():find("skip") then skipRemoteName = r.Name break end
        end
    end)
    return skipRemoteName or nil
end

local function autoSkipOn()
    local ok, v = pcall(function() return plr._settings.autoskip_waves.Value end)
    return ok and v == true
end

local function voteSkip()
    local name = findSkipRemote()
    if not name then
        if not skipWarned then
            skipWarned = true
            warn("[FD] ไม่พบ Remote โหวตข้ามเวฟ — ใส่ชื่อที่ SKIP_REMOTE (เกมอาจข้ามให้เองถ้าเปิด autoskip_waves ในการตั้งค่า)")
        end
        return
    end
    fire(name)
end

local function hookSkip()
    pcall(function()
        local ev = RS.endpoints.server_to_client:FindFirstChild("start_vote_wave_skip")
        if ev then
            ev.OnClientEvent:Connect(function()
                if alive() then voteSkip() end
            end)
        end
    end)
end

local function autoPlay()
    if R.autoPlay then fire(R.autoPlay, true) end
    autoUpgrade()
    sellFarmLastWave()
end

local function matchStarted()
    local ok, v = pcall(function() return Workspace._DATA.GameStarted.Value end)
    return ok and v
end
local function matchFinished()
    local ok, v = pcall(function() return Workspace._DATA.GameFinished.Value end)
    return ok and v
end

-- ผลลัพธ์จากอีเวนต์ game_finished ของเกม (RobScript: Match.result.victory)
local lastResult
local function hookResult()
    pcall(function()
        RS.endpoints.server_to_client.game_finished.OnClientEvent:Connect(function(r) lastResult = r end)
    end)
end

local function nextStage()
    say("เล่นต่อ")
    fire(R.finishVote, "next_story")
end

-- State machine หลัก
local function mainLoop()
    sendWebhook("▶️ เริ่มออโต้ฟาร์ม", plr.Name, 5763719)
    while alive() do
        local ok, err = pcall(function()
            if inLobby() then
                Place.ready = false
                checkGems() -- เพชรถึงเกณฑ์ -> สุ่ม + สวม Mythic ถ้าได้
                if alive() and not mysticDone() then equipBestTeam() end -- ยังได้ Mythic ไม่ครบ -> ใส่ตัวที่ดีที่สุดที่มี
                if alive() and joinStage() then task.wait(8) end
            else
                -- ในด่าน
                if not matchStarted() then
                    fire(R.voteStart)
                    task.wait(1)
                end
                if matchStarted() and not matchFinished() then
                    placeUnits()
                    local lastRecheck = os.clock()
                    while alive() and not matchFinished() do
                        if not autoSkipOn() then voteSkip() end -- ถ้าเกมไม่ได้เปิด autoskip ให้โหวตเอง
                        autoPlay()
                        -- ทุก 8 วิ: ยูนิตที่ยังไม่ได้วาง (เงินไม่พอ/จุดโดนปฏิเสธ) ลองวางใหม่ ยกเว้นเวฟสุดท้าย (ฟาร์มโดนขาย)
                        if os.clock() - lastRecheck > 8 then
                            lastRecheck = os.clock()
                            if wave() < totalWaves() and hasUnplaced() then placeUnits(true) end
                        end
                        task.wait(LOOP_DELAY)
                    end
                end
                if alive() and matchFinished() then
                    task.wait(2) -- รอผลลัพธ์
                    local won = lastResult and lastResult.victory
                    if won ~= false then
                        markCleared()
                        sendWebhook("🏆 ชนะด่าน", "เพชรตอนนี้: " .. gems(), 5763719)
                    end
                    Place.ready = false
                    lastResult = nil
                    if gems() >= GEM_THRESHOLD and not mysticDone() then
                        say("เพชรถึง " .. GEM_THRESHOLD .. " กลับล็อบบี้เพื่อสุ่ม")
                        fire(R.toLobby)
                        task.wait(10)
                    else
                        nextStage()
                        task.wait(5)
                    end
                end
            end
        end)
        if not ok then
            warn("[FD] error: " .. tostring(err))
            sendWebhook("⚠️ เกิดข้อผิดพลาด", "```" .. tostring(err):sub(1, 500) .. "```", 15548997)
            task.wait(2)
        end
        task.wait(LOOP_DELAY)
    end
    say("หยุดแล้ว")
end

local function onToggle(on)
    State.running = on
    if on then
        State.startedAt = State.startedAt or os.time() -- ถ้ามีเวลาเดิมจากรอบก่อน (หลังวาร์ป) นับต่อ
        say(mysticDone() and "ครบ Mythic แล้ว: ฟาร์มต่อ" or "กำลังทำงาน")
        task.spawn(mainLoop)
    else
        State.startedAt = nil
        say("หยุดแล้ว")
    end
    saveState()
end

-------------------------------------------------------------------------------
-- เริ่มทำงาน
-------------------------------------------------------------------------------
repeat task.wait() until game:IsLoaded()
loadWebhook()
loadState()
local resume = State.running -- สวิตช์ค้างเปิดไว้ก่อนเกมวาร์ป -> เปิดต่อเอง
State.running = false
local gameOk = loadGame()
if not gameOk then warn("[FD] โหลดโมดูลของเกมไม่สำเร็จ (ReplicatedStorage.src.Loader)") end
hookResult()
hookSkip()
hookTeleportQueue()
hookAutoRejoin()
resolveLogo()
createLoading()
local setSwitch = createMainUI(onToggle)
if resume then task.wait(0.5) setSwitch(true) end
