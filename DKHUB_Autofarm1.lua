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
local GEM_THRESHOLD = 500                -- ปรับได้จาก UI
-- คำว่า "Mystic" ในสเปก: ในข้อมูลเกมระดับสูงสุดที่พบในต้นฉบับคือ "Mythic"  [แก้ตรงนี้ ถ้าเกมใช้ชื่ออื่น]
local MYSTIC_RARITY = "Mythic"
local MYSTIC_SLOT   = 6                  -- ตัวแรกสวมสล็อตนี้ ตัวถัดไปเลื่อนลงทีละช่อง (6, 5, ...)
local MYSTIC_STOP_AT = 2                  -- ปรับได้จาก UI

-- จัดทีมที่ดีที่สุดให้เอง "ระหว่างที่ยังได้ Mythic ไม่ครบ" (จัดตอนอยู่ล็อบบี้)
-- เรียงตามระดับความหายาก > ตัว evolved > ดาเมจต่อวินาทีที่อัปสุด > เลเวล (เป็นการประมาณ ไม่ใช่ tier list ของเกม)
local BEST_TEAM        = true
local TEAM_SIZE        = 6                  -- [แก้ตรงนี้] จำนวนช่องทีม
local TEAM_FARM_SLOTS  = 1                  -- เลือก Bulby หรือ CEO เพียง 1 ตัว
local FIELD_MAX        = 20                 -- จำนวนยูนิตบนสนามสูงสุด ไม่ใช่จำนวนช่องทีม

-- รันสคริปต์ซ้ำเองหลังเกมวาร์ป/รีจอยน์ (ต้องใช้ executor ที่มี queue_on_teleport)
-- ใส่อย่างใดอย่างหนึ่ง: SCRIPT_URL (ลิงก์ raw ของสคริปต์นี้) หรือเซฟไฟล์นี้ไว้ใน workspace ชื่อ SCRIPT_FILE
local SCRIPT_URL   = "https://raw.githubusercontent.com/nightEX1/FD_Autofarm/main/DKHUB_Autofarm1.lua"
local SCRIPT_FILE  = "DKHUB_Autofarm1.lua"      -- ไฟล์ในโฟลเดอร์ workspace ของ executor
local AUTO_REJOIN  = true                   -- หลุด/ถูกเตะ -> เข้าเกมใหม่เองแล้วรันสคริปต์ต่อ

local LOOP_DELAY = 0.2                 -- วนประเมินเร็วขึ้นระหว่างด่าน
local PLACE_CONFIRM_TIMEOUT = 1.25     -- ไม่รอ 3 วินาทีทุกครั้ง ถ้า server ไม่สร้างตัวใหม่ให้ไป action อื่น

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
local VirtualUser  = game:GetService("VirtualUser")

-- Anti-AFK: ป้องกัน Roblox เตะออกเมื่อไม่มีอินพุตเป็นเวลานาน
pcall(function()
    plr.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end)

local State = { running = false, webhook = "", mystics = 0, startedAt = nil }
local Notify = {
    mystic = true, target = true, start = true,
    win = true, team = true, error = true,
}
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

local SETTINGS_FILE = SAVE_FOLDER .. "/settings.json"
local function saveSettings()
    pcall(function()
        if writefile then
            if makefolder and isfolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
            writefile(SETTINGS_FILE, HttpService:JSONEncode({
                gemThreshold = GEM_THRESHOLD,
                mysticStopAt = MYSTIC_STOP_AT,
                notify = Notify,
            }))
        end
    end)
end

local function loadSettings()
    pcall(function()
        if readfile and isfile and isfile(SETTINGS_FILE) then
            local d = HttpService:JSONDecode(readfile(SETTINGS_FILE))
            GEM_THRESHOLD = math.clamp(math.floor(tonumber(d.gemThreshold) or GEM_THRESHOLD), 0, 100000000)
            MYSTIC_STOP_AT = math.clamp(math.floor(tonumber(d.mysticStopAt) or MYSTIC_STOP_AT), 1, 99)
            if type(d.notify) == "table" then
                for k, v in pairs(Notify) do
                    if type(d.notify[k]) == "boolean" then Notify[k] = d.notify[k] end
                end
            end
        end
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

local function sendWebhook(kind, title, desc, color)
    if State.webhook == "" or Notify[kind] == false then return end
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

    -- หน้าต่างแนวนอน 16:9 แบบไร้เส้นขอบ
    local main = Instance.new("Frame", gui)
    main.AnchorPoint, main.Position = Vector2.new(.5, .5), UDim2.fromScale(.5, .5)
    main.Size, main.BackgroundColor3 = UDim2.fromOffset(640, 360), Color3.fromRGB(0, 0, 0)
    main.ClipsDescendants = true
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
    local scale = Instance.new("UIScale", main)

    -- Responsive: ย่อทั้ง UI ให้พอดีกับจอมือถือ/จอเล็ก โดยคงอัตราส่วน 16:9
    local minimized = false
    local function fitToScreen()
        local camera = Workspace.CurrentCamera
        if not camera then return 1 end
        local viewport = camera.ViewportSize
        local target = math.min(1, math.max(0.35, (viewport.X - 20) / 640), math.max(0.35, (viewport.Y - 20) / 360))
        if not minimized then scale.Scale = target end
        return target
    end
    local camera = Workspace.CurrentCamera
    if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitToScreen) end

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

    local function textLabel(text, x, y, w, h, size, color)
        local l = Instance.new("TextLabel", body)
        l.Size, l.Position, l.BackgroundTransparency = UDim2.fromOffset(w or 300, h or 20), UDim2.fromOffset(x, y), 1
        l.Font, l.TextSize, l.TextColor3 = Enum.Font.Gotham, size or 12, color or Color3.fromRGB(220, 220, 220)
        l.TextXAlignment, l.Text = Enum.TextXAlignment.Left, text
        return l
    end
    local function textBox(x, y, w, placeholder, value)
        local b = Instance.new("TextBox", body)
        b.Size, b.Position = UDim2.fromOffset(w, 28), UDim2.fromOffset(x, y)
        b.BackgroundColor3, b.TextColor3, b.PlaceholderText = Color3.fromRGB(16, 16, 16), Color3.new(1, 1, 1), placeholder
        b.Font, b.TextSize, b.ClearTextOnFocus, b.Text = Enum.Font.Gotham, 11, false, tostring(value or "")
        b.TextXAlignment, b.TextWrapped, b.ClipsDescendants = Enum.TextXAlignment.Left, false, true
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        return b
    end
    local function button(text, x, y, w, callback, color)
        local b = Instance.new("TextButton", body)
        b.Size, b.Position, b.Text = UDim2.fromOffset(w or 300, 28), UDim2.fromOffset(x, y), text
        b.Font, b.TextSize, b.TextColor3, b.BackgroundColor3 = Enum.Font.GothamBold, 11, Color3.new(1, 1, 1), color or RED
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        b.MouseButton1Click:Connect(callback)
        return b
    end

    -- ฝั่งซ้าย: การทำงานและการตั้งค่า
    local img = Instance.new("ImageLabel", body)
    img.Position, img.Size = UDim2.fromOffset(18, 10), UDim2.fromOffset(48, 48)
    img.BackgroundTransparency, img.Image = 1, LOGO
    textLabel("Auto Kaitan / ออโต้ฟาร์ม", 78, 12, 190, 22, 14, Color3.new(1, 1, 1))

    local sw = Instance.new("TextButton", body)
    sw.Size, sw.Position, sw.Text = UDim2.fromOffset(52, 26), UDim2.fromOffset(270, 20), ""
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

    textLabel("Discord Webhook", 18, 66, 300, 18, 11, Color3.fromRGB(190, 190, 190))
    local webhookBox = textBox(18, 86, 304, "Discord Webhook URL", State.webhook)
    local webhookMsg = textLabel("", 18, 154, 304, 18, 10, Color3.fromRGB(170, 170, 170))
    button("บันทึก Webhook", 18, 118, 304, function()
        local ok, msg = saveWebhook(webhookBox.Text)
        webhookMsg.Text, webhookMsg.TextColor3 = msg, ok and Color3.fromRGB(110, 220, 130) or Color3.fromRGB(240, 100, 100)
    end)

    textLabel("ตั้งค่าการสุ่ม", 18, 180, 304, 18, 12, Color3.fromRGB(255, 110, 110))
    local mysticBox = textBox(18, 204, 145, "จำนวน Mystic", MYSTIC_STOP_AT)
    local gemBox = textBox(177, 204, 145, "เพชรขั้นต่ำ", GEM_THRESHOLD)
    local settingMsg = textLabel("", 18, 238, 170, 18, 10, Color3.fromRGB(170, 170, 170))
    button("บันทึกค่าการสุ่ม", 190, 236, 132, function()
        local m, g = tonumber(mysticBox.Text), tonumber(gemBox.Text)
        if not m or not g or m < 1 or g < 0 then
            settingMsg.Text, settingMsg.TextColor3 = "ตัวเลขไม่ถูกต้อง", Color3.fromRGB(240, 100, 100)
            return
        end
        MYSTIC_STOP_AT = math.clamp(math.floor(m), 1, 99)
        GEM_THRESHOLD = math.clamp(math.floor(g), 0, 100000000)
        saveSettings()
        settingMsg.Text, settingMsg.TextColor3 = "บันทึกแล้ว", Color3.fromRGB(110, 220, 130)
    end)

    local st = textLabel("สถานะ: พร้อม", 18, 276, 304, 20, 11, Color3.fromRGB(175, 175, 175))
    setStatus = function(t) st.Text = "สถานะ: " .. t end
    local info = textLabel("", 18, 302, 304, 20, 10, Color3.fromRGB(255, 110, 110))
    task.spawn(function()
        while info.Parent do
            local t = State.startedAt and math.max(0, os.time() - State.startedAt) or 0
            info.Text = string.format("เวลา %02d:%02d:%02d | Mystic %d/%d | เพชร %d", t // 3600, (t % 3600) // 60, t % 60, State.mystics, MYSTIC_STOP_AT, gems())
            task.wait(1)
        end
    end)

    -- ฝั่งขวา: เลือกประเภทแจ้งเตือน
    textLabel("เปิด/ปิดการแจ้งเตือน Webhook", 350, 12, 270, 20, 13, Color3.fromRGB(255, 110, 110))
    local names = {
        {"ได้ Mystic", "mystic"}, {"ครบเป้าหมาย", "target"},
        {"เริ่มทำงาน", "start"}, {"ชนะด่าน", "win"},
        {"จัดทีม", "team"}, {"เกิดข้อผิดพลาด", "error"},
    }
    for i, item in ipairs(names) do
        local y = 48 + (i - 1) * 38
        textLabel(item[1], 350, y + 3, 190, 24, 12, Color3.fromRGB(215, 215, 215))
        local b = Instance.new("TextButton", body)
        b.Size, b.Position = UDim2.fromOffset(62, 26), UDim2.fromOffset(550, y)
        b.Font, b.TextSize = Enum.Font.GothamBold, 11
        b.Text = Notify[item[2]] and "เปิด" or "ปิด"
        b.TextColor3, b.BackgroundColor3 = Color3.new(1, 1, 1), Notify[item[2]] and RED or Color3.fromRGB(45, 45, 45)
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        b.MouseButton1Click:Connect(function()
            Notify[item[2]] = not Notify[item[2]]
            b.Text, b.BackgroundColor3 = Notify[item[2]] and "เปิด" or "ปิด", Notify[item[2]] and RED or Color3.fromRGB(45, 45, 45)
            saveSettings()
        end)
    end

    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        tween(main, 0.25, { Size = minimized and UDim2.fromOffset(640, 32) or UDim2.fromOffset(640, 360) })
        if not minimized then fitToScreen() end
    end)
    closeBtn.MouseButton1Click:Connect(function()
        onToggle(false)
        _G.FD_AUTOFARM_LOADED = nil
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

    local targetScale = fitToScreen()
    scale.Scale, main.BackgroundTransparency = targetScale * 0.6, 1
    tween(scale, 0.45, { Scale = targetScale }, Enum.EasingStyle.Back)
    tween(main, 0.45, { BackgroundTransparency = 0 })
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
                sendWebhook("mystic", "🌟 สุ่มได้ " .. MYSTIC_RARITY .. " (" .. State.mystics .. "/" .. MYSTIC_STOP_AT .. ")",
                    "**" .. name .. "** — สวมใส่แล้วที่สล็อต " .. slot, 16766720)
            end
        end
    end
    if found > 0 then
        saveState()
        if mysticDone() then
            sendWebhook("target", "🛑 ครบ " .. MYSTIC_STOP_AT .. " " .. MYSTIC_RARITY, "หยุดสุ่ม แล้วฟาร์มต่อเรื่อยๆ", 15158332)
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

-- ลำดับพิเศษตาม src: Bulby/CEO เป็นตัวทำเงิน ต้องมาก่อนตัวดาเมจทั่วไป
local function unitText(id, data)
    return (tostring(id) .. " " .. tostring(data and data.name or "")):lower()
end
local function isMoneyPriorityUnit(id, data)
    local text = unitText(id, data)
    return text:find("bulby", 1, true) ~= nil or text:find("ceo", 1, true) ~= nil
end
local function unitPriority(id, data)
    if isMoneyPriorityUnit(id, data) then return 100 end
    return RARITY_RANK[tostring(data and data.rarity or ""):lower()] or 0
end
local function unitPlacementTier(id, data)
    if isMoneyPriorityUnit(id, data) then return 3 end
    local rarity = tostring(data and data.rarity or ""):lower()
    if rarity == "mythic" or rarity == "mystic" or rarity == "legendary" then return 3 end
    if rarity == "epic" or rarity == "common" then return 1 end
    return 2
end
local function isPreferredTeamUnit(id, data)
    local rarity = tostring(data and data.rarity or ""):lower()
    return isMoneyPriorityUnit(id, data) or rarity == "mythic" or rarity == "mystic" or rarity == "legendary"
end

local function unitScore(u)
    local d = Game.Units and Game.Units[u.unit_id]
    if not d then return -1 end
    local rank = unitPriority(u.unit_id, d)
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
        local data = Game.Units[u.unit_id]
        -- ทีมออโต้เลือกเฉพาะ Mystic/Mythic + Legendary และ Bulby/CEO เป็นข้อยกเว้น
        if data and isPreferredTeamUnit(u.unit_id, data) then
            local sc = unitScore(u)
            if sc >= 0 then
                local row = { uuid = u.uuid, id = u.unit_id, score = sc }
                if isFarm(u.unit_id) or isMoneyPriorityUnit(u.unit_id, data) then farms[#farms + 1] = row else atks[#atks + 1] = row end
            end
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
        sendWebhook("team", "🛡️ จัดทีมที่ดีที่สุด", "เปลี่ยน " .. changed .. " สล็อต (ยังได้ Mythic " .. State.mystics .. "/" .. MYSTIC_STOP_AT .. ")", 3447003)
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
-- Match = ตารางเดียวกับ Place (ชื่อตามระบบ src): Match.refused / Match.noSpot / Match.bestSpot / Match.place
local Place = {
    samples = {}, cands = {}, ready = false, matchId = 0, totalWeight = 1,
    refused = {},   -- "x,z" -> เวลาที่เกมปฏิเสธจุดนั้น (หมดอายุ 90 วิ)
    noSpot = {},    -- uuid -> { n = จำนวนครั้งที่หาจุดไม่ได้, t = เวลา }
    placeFail = {}, pending = {}, sold = {}, spotCache = {}, upFail = {},
    cap = nil, capAt = 0, failStreak = 0,
    coverCache = {}, escalated = false,
}
local Match = Place

-- ===== จุดที่เกมปฏิเสธ จำไว้ต่อแผนที่ (ข้ามแมตช์/ข้ามการวาร์ป) =====
local REFUSED_FILE = SAVE_FOLDER .. "/refused.json"
local RefusedStore = {} -- mapKey -> { ["x,z"] = จำนวนครั้งที่ถูกปฏิเสธ }
local function loadRefused()
    pcall(function()
        if readfile and isfile and isfile(REFUSED_FILE) then
            local d = HttpService:JSONDecode(readfile(REFUSED_FILE))
            if type(d) == "table" then RefusedStore = d end
        end
    end)
end
local function saveRefused()
    pcall(function()
        if writefile then
            if makefolder and isfolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
            writefile(REFUSED_FILE, HttpService:JSONEncode(RefusedStore))
        end
    end)
end
loadRefused()
local function currentMapKey()
    local ok, id = pcall(function()
        local ld = Game.Loader.LevelData
        return tostring(ld.id or ld.name or ld.level)
    end)
    return ok and id or tostring(game.PlaceId)
end

-- ===== Layout ต่อแผนที่ (เรียนรู้จากผลแมตช์ แบบเดียวกับที่ RobScript ลดระดับเมื่อแพ้) =====
--   1 เร็ว (ยิงตั้งแต่ต้นถนน) -> 2 กระจายตามถนน -> 3 kill box ท้ายถนน (ปลอดภัยสุด)
--   แพ้ = ขยับไปแบบที่ปลอดภัยขึ้น 1 ขั้น | ชนะติด 3 ครั้ง = ลองแบบที่เร็วขึ้น 1 ขั้น
local LAYOUT_FILE = SAVE_FOLDER .. "/layout.json"
local LayoutStore = {}
pcall(function()
    if readfile and isfile and isfile(LAYOUT_FILE) then
        local d = HttpService:JSONDecode(readfile(LAYOUT_FILE))
        if type(d) == "table" then LayoutStore = d end
    end
end)
local function saveLayout()
    pcall(function()
        if writefile then
            if makefolder and isfolder and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
            writefile(LAYOUT_FILE, HttpService:JSONEncode(LayoutStore))
        end
    end)
end
function Match.layoutLevel()
    local e = LayoutStore[Place.mapKey or ""]
    return e and math.clamp(tonumber(e.lvl) or 2, 1, 3) or 2
end
function Match.recordResult(won)
    local mk = Place.mapKey or ""
    local e = LayoutStore[mk] or { lvl = 2, streak = 0 }
    e.lvl = math.clamp(tonumber(e.lvl) or 2, 1, 3)
    if won then
        e.streak = (tonumber(e.streak) or 0) + 1
        if e.streak >= 3 and e.lvl > 1 then e.lvl -= 1 e.streak = 0 end
    else
        e.lvl = math.min(3, e.lvl + 1)
        e.streak = 0
    end
    LayoutStore[mk] = e
    saveLayout()
    print(string.format("[FD] layout แผนที่ %s -> %d (%s)", mk, e.lvl, won and "ชนะ" or "แพ้"))
end

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
                    Place.samples[#Place.samples + 1] = { pos = a:Lerp(b, j / n), prog = (acc + len * j / n) / math.max(1, total), lane = lane.Name, len = total }
                end
                acc += len
            end
            if pts[#pts] then Place.samples[#Place.samples + 1] = { pos = pts[#pts], prog = 1, lane = lane.Name, len = total } end
        end
    end
    local tw = 0
    for _, sp in ipairs(Place.samples) do tw += 1 + 2 * sp.prog * sp.prog end
    Place.totalWeight = math.max(1, tw)
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
local function refusedNow(pos)
    local k = spotKey(pos)
    local t = Place.refused[k]
    if t ~= nil and os.clock() - t < 90 then return true end
    local m = RefusedStore[Place.mapKey or ""]
    return m ~= nil and (m[k] or 0) >= 2 -- ถูกปฏิเสธซ้ำ 2 ครั้งขึ้นไปบนแผนที่นี้ = จำถาวร
end

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

-- src แยก "ยูนิตในทีม" ออกจาก "จำนวนสำเนาที่วางบนสนาม" ด้วย Match.count(uuid)
local function unitCountByUuid(uuid, mine)
    local n = 0
    for _, u in ipairs(mine or myUnits()) do
        local st = u:FindFirstChild("_stats")
        local uu = st and st:FindFirstChild("uuid")
        if uu and uu.Value == uuid then n += 1 end
    end
    return n
end

local function unitSpawnCap(data)
    -- spawn_cap คือชื่อเดียวกับ Units.field(id, "spawn_cap") ใน src
    local cap = tonumber(data and (data.spawn_cap or data.max_placement or data.placement_cap or data.cap))
    return math.max(1, math.floor(cap or FIELD_MAX))
end

-- ตรวจว่าจุดวางได้ (Match.valid): raycast ลงพื้น + PlacementCore + ไม่ทับถนน/ยูนิตอื่น
local function validSpot(p, unitData, mine)
    local hit = Game.PC.raycast(p + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0))
    if not hit or not Game.PC.is_valid_raycast_hit(hit.Instance, unitData) then return nil end
    local pos = hit.Position
    if refusedNow(pos) then return nil end
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

-- คะแนนครอบคลุมถนนของจุด/ระยะ (ใช้ตอนประเมินอัปเกรดของยูนิตที่วางอยู่แล้ว)
--  * ท้ายถนนมีน้ำหนักมาก (prog^2)
--  * wmul = น้ำหนักรายจุดตัวอย่างจากสถานการณ์ (ศัตรูอยู่ตรงนั้น / layout / ต้องขยับลึกขึ้น / เฝ้าก่อนฐาน / ขวางตัวที่หลุด / บอส)
--  * จุดที่มียูนิตครอบคลุมแล้วถูกลดคะแนน (cov) -> ตัวถัดไปขยับไปคลุมช่วงที่ยังโล่ง
--  * selfRange = ระยะปัจจุบันของยูนิตที่วางอยู่แล้ว (หักตัวมันเองออกจาก cov)
local function scoreAt(pos, range, cov, wmul, selfRange)
    local fp, score = flat(pos), 0
    for i, s in ipairs(Place.samples) do
        local d = (flat(s.pos) - fp).Magnitude
        if d <= range then
            local c = cov[i] or 0
            if selfRange and d <= selfRange then c = math.max(0, c - 1) end
            local w = (1 + 2 * s.prog * s.prog) * (wmul and wmul[i] or 1)
            score += w / (1 + 0.35 * c)
        end
    end
    return score
end

-- รายชื่อจุดตัวอย่างบนถนนที่ผู้สมัครตัวที่ ci ยิงถึงที่ระยะ range (คำนวณครั้งเดียวต่อแผนที่/ระยะ แล้วแคชไว้)
-- ทำให้ bestSpot เร็วขึ้นมาก: จากเดิมวนทุกจุดตัวอย่างต่อผู้สมัคร เหลือวนเฉพาะจุดที่ยิงถึง
local function candCover(ci, pos, range)
    local rk = math.floor(range * 2)
    local bucket = Place.coverCache[rk]
    if not bucket then bucket = {} Place.coverCache[rk] = bucket end
    local list = bucket[ci]
    if not list then
        list = {}
        local fp = flat(pos)
        for i, s in ipairs(Place.samples) do
            if (flat(s.pos) - fp).Magnitude <= range then list[#list + 1] = i end
        end
        bucket[ci] = list
    end
    return list
end

local function scoreList(list, cov, wmul)
    local score = 0
    for _, i in ipairs(list) do
        local s = Place.samples[i]
        score += (1 + 2 * s.prog * s.prog) * (wmul and wmul[i] or 1) / (1 + 0.35 * (cov[i] or 0))
    end
    return score
end

-- คะแนนเสริมที่พอร์ตจาก Match.bestSpot ของ src ให้เข้ากับข้อมูลที่ไฟล์นี้มีจริง
-- src จะแยก control/fast/kill-zone ก่อนค่อยใช้ coverage ปกติ; ฟังก์ชันนี้ทำหน้าที่
-- เป็นชั้นเดียวกันโดยใช้ layout, road density และตำแหน่งศัตรูจาก Economy.snapshot()
local function sourceSpotBonus(pos, range, ctx, farm)
    if farm or not ctx or #Place.samples == 0 then return 0 end
    local fp = flat(pos)
    local bonus, covered, late, early, danger = 0, 0, 0, 0, 0
    local enemy = ctx.enemies or {}
    local front = tonumber(enemy.front) or 0
    local density = enemy.dens or {}
    for i, s in ipairs(Place.samples) do
        if (flat(s.pos) - fp).Magnitude <= range then
            covered += 1
            if s.prog >= 0.6 then late += 1 end
            if s.prog <= 0.35 then early += 1 end
            if density[i] and density[i] > 0 then danger += density[i] end
        end
    end
    if covered == 0 then return -1000 end

    -- Match.style == fast: คุมช่วงต้นถนนเพื่อเก็บศัตรูตั้งแต่ทางเข้า
    if ctx.layout == 1 then bonus += early * 0.9 end
    -- Match.killZone: stack จุดยิงช่วงท้ายถนนและช่วงที่มีศัตรูหนาแน่น
    if ctx.layout == 3 or ctx.boss then bonus += late * 1.25 + danger * 0.7 end
    -- Match.controlSpot / Match.holdSpot: ถ้ามีศัตรูอยู่ ให้ย้ายจุดไปช่วงหน้าหัวแถว
    if front > 0 then
        local nearFront = math.max(0, 1 - math.abs((late > 0 and 0.8 or 0) - front) * 2)
        if ctx.leak or ctx.deepen then
            bonus += nearFront * 12
        else
            bonus += nearFront * 3
        end
    end
    -- guard/last-line: หลังวาง core แล้วต้องมีจุดยิงช่วงก่อนฐานเสมอ
    if ctx.guardNeed then
        local guardFrom = 0.75 -- ค่าเดียวกับ ECON.GUARD_FROM ซึ่งประกาศหลัง bestSpot
        for _, s in ipairs(Place.samples) do
            if s.prog >= guardFrom and (flat(s.pos) - fp).Magnitude <= range then
                bonus += 8
                break
            end
        end
    end
    return bonus
end

-- ยูนิตสายสนับสนุน/คุมเกม (ไม่มีดาเมจเอง ไม่ใช่ฟาร์ม): ไปยืนที่ที่ตัวดาเมจของเราอยู่ในระยะมากที่สุด
local function isSupportUnit(data)
    local up = type(data.upgrade) == "table" and data.upgrade[#data.upgrade] or nil
    local dmg = tonumber(up and up.damage) or tonumber(data.damage) or 0
    return dmg <= 0
end

-- Match.bestSpot: หาจุดวางที่ดีที่สุดของยูนิตหนึ่งตัว
--  * ตัวดาเมจ: จุดที่ครอบคลุมถนนตาม layout/สถานการณ์ได้ดีที่สุด (layout อยู่ใน wmul: เร็ว/กระจาย/kill box)
--  * ตัวฟาร์ม: จุดที่ใช้ได้แต่คะแนนต่ำสุด (ไม่แย่งจุดดีของตัวดาเมจ)
--  * ตัวสนับสนุน: จุดที่ตัวดาเมจของเราอยู่ในระยะรวม dps มากที่สุด
--  * จุดที่เกมเคยปฏิเสธอยู่ใน Match.refused (หมดอายุ 90 วิ) และใน RefusedStore ต่อแผนที่
-- ผลลัพธ์แคชไว้ 6 วิ (ต่อ uuid) และใช้ซ้ำถ้าจำนวนยูนิตในสนามและโหมดไม่เปลี่ยน
local function bestSpot(unit, mine, ctx)
    local now = os.clock()
    local cache = Place.spotCache[unit.uuid]
    local mode = ctx and ctx.mode or ""
    if cache and cache.n == #mine and cache.mode == mode and now - cache.t < 6 then
        if not cache.pos then return nil end
        if not refusedNow(cache.pos) then return cache.pos, cache.score end
    end
    local farm = isFarm(unit.id)
    local support = (not farm) and isSupportUnit(unit.data)
    local range = unitRange(unit.data)
    local cov = ctx and ctx.cov or coverCounts(mine)
    local wmul = ctx and ctx.wmul or nil

    -- ตัวสนับสนุน: เก็บตำแหน่ง+dps ของตัวดาเมจที่วางแล้ว
    local attackers
    if support then
        attackers = {}
        for _, u in ipairs(mine) do
            pcall(function()
                local id = u._stats.id.Value
                if isFarm(id) then return end
                local d = Game.Units[id]
                if not d or isSupportUnit(d) then return end
                local up = type(d.upgrade) == "table" and d.upgrade[#d.upgrade] or nil
                local dmg = tonumber(up and up.damage) or tonumber(d.damage) or 0
                local cd = tonumber(up and (up.attack_cooldown or up.cooldown)) or tonumber(d.attack_cooldown) or 1
                attackers[#attackers + 1] = { p = flat(u:GetPivot().Position), dps = dmg / math.max(cd, 0.5) }
            end)
        end
        if #attackers == 0 then
            Place.spotCache[unit.uuid] = { n = #mine, t = now, pos = nil, mode = mode }
            return nil -- ยังไม่มีตัวดาเมจให้สนับสนุน รอก่อน
        end
    end

    -- ช่วงเร่งเติมสนามยังคงตรวจ validSpot และ refused ตามปกติ แต่ไม่เสียเวลา
    -- คำนวณคะแนนทุกจุด เพราะเป้าหมายตอนนี้คือขึ้นจำนวนตัวให้ทันเวฟแรก
    if ctx and ctx.fastFill and not support then
        for ci, c in ipairs(Place.cands) do
            local pos = validSpot(c, unit.data, mine)
            if pos then
                local score = scoreList(candCover(ci, pos, range), cov, wmul)
                Place.spotCache[unit.uuid] = { n = #mine, t = os.clock(), pos = pos, score = score, mode = mode }
                return pos, score
            end
            if ci % 40 == 0 then task.wait() end
        end
        Place.spotCache[unit.uuid] = { n = #mine, t = os.clock(), pos = nil, mode = mode }
        return nil
    end

    local bestPos, bestScore
    local n = 0
    for ci, c in ipairs(Place.cands) do
        local pos = validSpot(c, unit.data, mine)
        n += 1
        if n % 40 == 0 then task.wait() end
        if pos then
            local score
            if support then
                score = 0
                local fp = flat(pos)
                for _, a in ipairs(attackers) do
                    if (a.p - fp).Magnitude <= range then score += a.dps end
                end
            else
                score = scoreList(candCover(ci, pos, range), cov, wmul)
                score += sourceSpotBonus(pos, range, ctx, farm)
            end
            if farm then
                if not bestScore or score < bestScore then bestPos, bestScore = pos, score end
            elseif score > 0 and (not bestScore or score > bestScore) then
                bestPos, bestScore = pos, score
            end
        end
    end
    Place.spotCache[unit.uuid] = { n = #mine, t = os.clock(), pos = bestPos, score = bestScore, mode = mode }
    return bestPos, bestScore
end
Match.bestSpot = bestSpot

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
    Place.refused, Place.noSpot, Place.placeFail, Place.pending = {}, {}, {}, {}
    Place.sold, Place.spotCache, Place.upFail, Place.coverCache = {}, {}, {}, {}
    Place.escalated = false
    Place.cap, Place.failStreak = nil, 0
    Place.matchId += 1
    Place.mapKey = currentMapKey()
    Place.ready = true
    return true
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

-- ===== Economy (แนว src): สร้างตัวเลือกทั้งหมด -> ให้คะแนนความคุ้มค่า -> เลือก 1 action -> ทำ -> วนประเมินใหม่ =====
-- ไม่มีการล็อกว่า "ต้องวางให้ครบก่อน" หรือ "ต้องอัปเกรดตัวเดียวจนเต็มก่อน" ทุกอย่างแข่งกันที่ค่า value (ประโยชน์ต่อเงิน 1 หน่วย)
local ECON = {
    SAVE_MAX_ETA  = 18,   -- ออมเงินรอของที่คุ้มที่สุดได้ไม่เกินกี่วินาที (ประมาณจากรายได้จริง)
    SAVE_MAX_TIME = 25,   -- ออมเป้าหมายเดิมต่อเนื่องได้ไม่เกินกี่วินาที กันรอจนค้าง
    SAVE_RATIO    = 1.35, -- ของที่แพงกว่าต้องคุ้มกว่าตัวที่ซื้อได้ตอนนี้กี่เท่า ถึงจะยอมรอ
    FARM_WEIGHT   = 0.5,  -- น้ำหนักแปลง "กำไรเงินจากฟาร์ม" ให้เทียบกับ "ดาเมจ" ได้
    SELL_REFUND   = 0.5,  -- ประมาณเงินคืนตอนขาย (ของ total_spent)
    COVER_FLOOR   = 0.15, -- ยูนิตที่ครอบคลุมถนนน้อยมากยังมีค่าขั้นต่ำเล็กน้อย
    SAFE_REACH    = 0.45, -- ศัตรูตายก่อนถึงช่วงนี้ของถนน = ปลอดภัย (ฟาร์มได้เต็มที่)
    DANGER_REACH  = 0.7,  -- ศัตรูเดินเกินช่วงนี้ = อันตราย: เลิกลงทุนฟาร์ม ทุกอย่างลงดาเมจ
    GUARD_AFTER   = 5,    -- วางครบกี่ตัวแล้วเริ่มบังคับให้มีตัวเฝ้าก่อนฐาน
    GUARD_MIN     = 2,    -- ต้องมีตัวดาเมจอย่างน้อยกี่ตัวครอบคลุมช่วงก่อนฐาน
    GUARD_FROM    = 0.75, -- "ช่วงก่อนฐาน" เริ่มที่ความคืบหน้าของถนนเท่าไร
    BOSS_MAX      = 2,    -- เวฟสุดท้ายเหลือศัตรูไม่เกินกี่ตัว ถือเป็นโหมดตามบอส
    SPOT_BUDGET   = 12,   -- เพิ่มจำนวน candidate ที่ตรวจต่อรอบ ลดเวลาค้างตอนเติมสนาม
    FILL_TARGET    = 12,  -- ช่วงต้นเกมให้เร่งวางจนมี core ประมาณนี้ก่อนค่อยแข่งกับอัปเกรด
    FAST_FILL      = true, -- ช่วงเร่งด่วนใช้จุดแรกที่ valid ไม่สแกนทั้งแผนที่
}

local Economy = { rate = 0 }

local function unitDpsAt(data, idx)
    local row = idx == 0 and data or (data.upgrade and data.upgrade[idx])
    local dmg = tonumber(row and row.damage) or tonumber(data.damage) or 0
    local cd = tonumber(row and (row.attack_cooldown or row.cooldown)) or tonumber(data.attack_cooldown) or 1
    return dmg / math.max(cd, 0.5)
end

local function rangeAt(data, idx)
    local row = idx > 0 and data.upgrade and data.upgrade[idx] or nil
    return tonumber(row and row.range) or tonumber(data.range) or unitRange(data)
end

local function farmIncomeAt(data, idx)
    if idx == 0 then return tonumber(data.farm_amount) or 0 end
    local row = data.upgrade and data.upgrade[idx]
    return tonumber(row and row.farm_amount) or 0
end

-- ตัวคูณความสำคัญเล็กน้อย: Bulby/CEO ก่อน ตามด้วยตัวหายาก (แค่ช่วยตัดสินเมื่อคะแนนใกล้กัน)
local function prioMul(id, data)
    if isMoneyPriorityUnit(id, data) then return 1.5 end
    return 1 + math.min(unitPriority(id, data), 6) * 0.04
end

-- ยูนิตระยะสั้นได้ค่าน้อยลงช่วงท้ายด่าน (บอสเดินผ่านไปเร็ว)
local function rangeFactor(ctx, r)
    if ctx.left <= 3 then return math.clamp((tonumber(r) or 28) / 28, 0.6, 1.1) end
    return 1
end

local function coverFactor(score)
    return ECON.COVER_FLOOR + (score or 0) / math.max(1, Place.totalWeight or 1)
end

-- ศัตรูในสนาม: จำนวน / ตำแหน่งบนถนน (prog) / ระยะที่เหลือก่อนถึงปลายทาง / ความหนาแน่นรายจุดตัวอย่าง
local function enemyModel()
    local m = { count = 0, danger = 0, front = 0, frontIdx = nil, distLeft = 0, dens = {} }
    local ns = #Place.samples
    for i = 1, ns do m.dens[i] = 0 end
    local folder = Workspace:FindFirstChild("_ENEMIES") or Workspace:FindFirstChild("_enemies")
    if not folder or ns == 0 then return m end
    local n, sumLeft = 0, 0
    for _, e in ipairs(folder:GetChildren()) do
        if n >= 40 then break end
        pcall(function()
            local p = flat(e:GetPivot().Position)
            local bi, bd = nil, math.huge
            for i, s in ipairs(Place.samples) do
                local d = (flat(s.pos) - p).Magnitude
                if d < bd then bi, bd = i, d end
            end
            if bi and bd < 25 then
                n += 1
                local s = Place.samples[bi]
                if s.prog > m.front or not m.frontIdx then m.front, m.frontIdx = s.prog, bi end
                if s.prog > 0.7 then m.danger += 1 end
                sumLeft += (1 - s.prog) * (s.len or 0)
                for k = math.max(1, bi - 4), math.min(ns, bi + 4) do
                    m.dens[k] += 1 - math.abs(k - bi) * 0.15
                end
            end
        end)
    end
    m.count = n
    m.distLeft = n > 0 and sumLeft / n or 0
    return m
end

-- อ่านสถานะปัจจุบันทั้งหมดครั้งเดียวต่อรอบ
function Economy.snapshot()
    local now = os.clock()
    if Economy.matchId ~= Place.matchId then
        Economy.matchId, Economy.rate, Economy.lastCash = Place.matchId, 0, nil
        Economy.saveTarget, Economy.saveSince, Economy.lastMsg = nil, nil, nil
    end
    local cash = money()
    if Economy.lastCash then
        local dt = math.max(0.05, now - Economy.lastT)
        Economy.rate = Economy.rate * 0.92 + (math.max(0, cash - Economy.lastCash) / dt) * 0.08
    end
    Economy.lastCash, Economy.lastT = cash, now

    local total = math.max(1, totalWaves())
    local w = wave()
    local mine = myUnits()
    local byUuid = {}
    local countsByUuid = {}
    for _, u in ipairs(mine) do
        local st = u:FindFirstChild("_stats")
        local uu = st and st:FindFirstChild("uuid")
        if uu then
            byUuid[uu.Value] = byUuid[uu.Value] or u
            countsByUuid[uu.Value] = (countsByUuid[uu.Value] or 0) + 1
        end
    end
    local em = enemyModel()
    -- ความกดดัน: ความคืบหน้าด่าน + จำนวนศัตรู + ศัตรูที่ใกล้ถึงปลายทาง + ตำแหน่งหัวแถว
    local stage = math.clamp(w / total, 0, 1)
    local pressure = math.clamp(
        0.35 * stage
        + math.min(em.count, 25) / 25 * 0.5
        + math.min(em.danger, 5) / 5 * 0.7
        + (em.count > 0 and em.front * 0.3 or 0),
        0, 1.5)

    -- สนามเต็ม: ถึง FIELD_MAX หรือเกมปฏิเสธต่อเนื่องเมื่อถึงเพดานจริง (เรียนรู้เพดานเอง)
    if Place.cap and (#mine < Place.cap or now - (Place.capAt or 0) > 60) then
        Place.cap, Place.failStreak = nil, 0
    end
    local left = math.max(0, total - w)
    local cov = coverCounts(mine)
    local ns = #Place.samples

    -- Defense in depth: ยูนิตของเราครอบคลุมถนนลึกแค่ไหน (reach) และมีตัวเฝ้าช่วงก่อนฐานกี่ตัว
    local reach, guards = 0, 0
    for i = 1, ns do
        if cov[i] > 0 and Place.samples[i].prog > reach then reach = Place.samples[i].prog end
    end
    for _, u in ipairs(mine) do
        pcall(function()
            local id = u._stats.id.Value
            if isFarm(id) then return end
            local d = Game.Units[id]
            if not d then return end
            local r, p = unitRange(d), flat(u:GetPivot().Position)
            for _, s in ipairs(Place.samples) do
                if s.prog >= ECON.GUARD_FROM and (flat(s.pos) - p).Magnitude <= r then guards += 1 break end
            end
        end)
    end
    local deepen = em.count > 0 and em.front >= reach - 0.08                 -- ศัตรูมาถึงปลายช่วงที่เราครอบคลุม -> ตัวถัดไปไปลึกกว่าเดิม
    local leak = em.count > 0 and #mine > 0 and reach > 0 and em.front > reach + 0.03 -- ศัตรูหลุดพ้นทุกตัวไปแล้ว -> วางขวางหน้ามัน
    local guardNeed = #mine >= ECON.GUARD_AFTER and guards < ECON.GUARD_MIN
    local boss = left == 0 and em.count > 0 and em.count <= ECON.BOSS_MAX    -- เวฟสุดท้ายเหลือแต่บอส -> ไปตรงที่บอสอยู่
    local danger = em.count > 0 and em.front >= ECON.DANGER_REACH

    -- Layout (ปรับตามผลแมตช์ก่อนหน้าของแผนที่นี้ ดู Match.recordResult):
    --   1 = เร็ว (ยิงตั้งแต่ต้นถนน) | 2 = กระจายตามถนน | 3 = kill box ที่ท้ายถนน
    -- ถ้าศัตรูหลุด/เดินลึกในแมตช์นี้ จะขยับเป็น kill box ตลอดที่เหลือของแมตช์
    if leak or danger then Place.escalated = true end
    local layout = Place.escalated and 3 or Match.layoutLevel()
    local wmul = {}
    for i = 1, ns do
        local s = Place.samples[i]
        local wv = 1 + 0.6 * math.min(em.dens[i], 6)
        if layout == 1 then wv *= 1 + 3 * (1 - s.prog) * (1 - s.prog)
        elseif layout == 3 and s.prog >= 0.7 then wv *= 4 end
        if deepen and s.prog > reach then wv *= 3 end
        if guardNeed and s.prog >= ECON.GUARD_FROM then wv *= 3 end
        if leak and s.prog >= em.front and s.prog <= em.front + 0.18 then wv *= 6 end
        if boss then
            wv *= 1 + 4 * math.min(em.dens[i], 3)
            if s.prog >= em.front - 0.05 then wv *= 2.5 end
        end
        wmul[i] = wv
    end
    local fastFill = ECON.FAST_FILL and #mine < ECON.FILL_TARGET
    local mode = tostring(layout) .. (deepen and "d" or "") .. (guardNeed and "g" or "") .. (leak and "l" or "") .. (boss and "b" or "") .. (fastFill and "f" or "")

    return {
        cash = cash, wave = w, total = total, left = left,
        pressure = pressure, threat = 1 + 2 * pressure, enemies = em,
        reach = reach, guards = guards, deepen = deepen, leak = leak, guardNeed = guardNeed, boss = boss, danger = danger,
        wmul = wmul, mode = mode, layout = layout, fastFill = fastFill,
        mine = mine, byUuid = byUuid, cov = cov, dens = em.dens,
        fieldFull = #mine >= FIELD_MAX or (Place.cap ~= nil and #mine >= Place.cap),
        countsByUuid = countsByUuid,
        spotBudget = ECON.SPOT_BUDGET, incomplete = false,
    }
end

-- ===== Match.place: หาจุดที่ดีที่สุดก่อน แล้วค่อยเรียก spawn_unit =====
function Match.place(unit, reason, ctx)
    local mine = ctx and ctx.mine or myUnits()
    local beforeCount = unitCountByUuid(unit.uuid, mine)
    local pos, score = Match.bestSpot(unit, mine, ctx)
    if not pos then
        local ns = Place.noSpot[unit.uuid] or { n = 0, t = 0 }
        ns.n += 1
        ns.t = os.clock()
        Place.noSpot[unit.uuid] = ns
        return false, "nospot"
    end
    Place.pending[unit.uuid] = os.clock()
    local ok, res = fire(R.spawnUnit, unit.uuid, Game.Util.CFramePLV(pos, lookAt(pos)))
    if ok and res then
        -- รอให้ยูนิตขึ้นในสนามจริง ก่อนประเมินรอบถัดไป (กันคำสั่งซ้ำ/เงินยังไม่ถูกหัก)
        local t0 = os.clock()
        while os.clock() - t0 < PLACE_CONFIRM_TIMEOUT and alive() do
            if unitCountByUuid(unit.uuid) > beforeCount then break end
            task.wait(0.05)
        end
        if unitCountByUuid(unit.uuid) > beforeCount then
            Place.noSpot[unit.uuid], Place.placeFail[unit.uuid] = nil, 0
            local mk = RefusedStore[Place.mapKey or ""]
            if mk and mk[spotKey(pos)] then mk[spotKey(pos)] = nil saveRefused() end -- วางสำเร็จ = จุดนี้ใช้ได้ ลบออกจากรายการแบน
            Place.spotCache = {} -- ยูนิตใหม่เปลี่ยน coverage ทุกจุด ให้ทุกตัวหาจุดใหม่
            Place.pending[unit.uuid], Place.failStreak = nil, 0
            print(string.format("[FD] วาง %s (%s) ที่ %s คะแนน %.1f", tostring(unit.id), tostring(reason), spotKey(pos), score or 0))
            return true
        end
    end
    -- เกมปฏิเสธ / ไม่ขึ้นในสนาม: จำจุดนี้ไว้ ไม่เลือกซ้ำ
    Place.pending[unit.uuid] = nil
    local key = spotKey(pos)
    Place.refused[key] = os.clock()
    -- จำจุดที่ถูกปฏิเสธต่อแผนที่ (ข้ามแมตช์/ข้ามการวาร์ป): นับเฉพาะตอนเงินพอและสนามยังไม่เต็ม ไม่ให้จุดดีถูกแบนเพราะเหตุอื่น
    if money() >= (tonumber(unit.data.cost) or 0) and not (ctx and ctx.fieldFull) then
        local mk = Place.mapKey or ""
        RefusedStore[mk] = RefusedStore[mk] or {}
        RefusedStore[mk][key] = (RefusedStore[mk][key] or 0) + 1
        saveRefused()
    end
    Place.spotCache[unit.uuid] = nil
    Place.placeFail[unit.uuid] = (Place.placeFail[unit.uuid] or 0) + 1
    Place.failStreak = (Place.failStreak or 0) + 1
    if Place.failStreak >= 3 and #mine >= FIELD_MAX and money() >= (tonumber(unit.data.cost) or 0) then
        Place.cap, Place.capAt = FIELD_MAX, os.clock() -- ปฏิเสธต่อเนื่องเมื่อถึงเพดานสนามจริง
    end
    if Place.placeFail[unit.uuid] >= 3 then
        Place.noSpot[unit.uuid] = { n = 3, t = os.clock() }
    end
    return false, "refused"
end

-- ===== สร้างตัวเลือกทั้งหมด =====
-- ตัวเลือกแต่ละอันมี: kind (place/upgrade/sell), cost, value (ประโยชน์ต่อเงิน 1 หน่วย)
--   ตัวดาเมจ: value = (dps ที่เพิ่ม x coverage ของถนน x ความกดดัน) / ราคา
--   ตัวฟาร์ม: value = (กำไรเงินสุทธิ ณ จบด่าน / ราคา) x น้ำหนักเศรษฐกิจ (ลดลงเมื่อด่านกดดัน) แปลงเป็นหน่วยเดียวกับดาเมจ
function Economy.options(ctx)
    local opts, damageOpts, farmOpts, unplaced = {}, {}, {}, {}
    local now = os.clock()

    for _, unit in ipairs(equippedUnits()) do
        local data = Game.Units and Game.Units[unit.id]
        if data then
            local inst = ctx.byUuid[unit.uuid]
            if inst then
                -- อัปเกรดเลเวลถัดไป / อัปเกรดฟาร์ม (เฉพาะถ้าคืนทุนทัน)
                pcall(function()
                    local st = inst._stats
                    local idx = tonumber(st.upgrade.Value) or 0
                    local nextRow = data.upgrade and data.upgrade[idx + 1]
                    if not nextRow then return end
                    if Place.upFail[inst] and now - Place.upFail[inst] < 5 then return end
                    local cost = tonumber(nextRow.cost)
                    if not cost then return end
                    local o = { kind = "upgrade", unit = unit, data = data, inst = inst, cost = cost, idx = idx }
                    if isFarm(unit.id) then
                        local gain = farmIncomeAt(data, idx + 1) - farmIncomeAt(data, idx)
                        local net = gain * ctx.left - cost
                        if gain <= 0 or net <= 0 then return end -- คืนทุนไม่ทัน
                        if ctx.danger or ctx.leak then return end -- ศัตรูเดินลึก/หลุดแล้ว: ไม่ลงทุนฟาร์ม
                        o.cashBenefit = net
                        farmOpts[#farmOpts + 1] = o
                    else
                        local pos = inst:GetPivot().Position
                        local r0, r1 = rangeAt(data, idx), rangeAt(data, idx + 1)
                        local cf0 = coverFactor(scoreAt(pos, r0, ctx.cov, ctx.wmul, r0))
                        local cf1 = coverFactor(scoreAt(pos, r1, ctx.cov, ctx.wmul, r0))
                        local d0 = unitDpsAt(data, idx) * cf0 * rangeFactor(ctx, r0)
                        local d1 = unitDpsAt(data, idx + 1) * cf1 * rangeFactor(ctx, r1)
                        o.dmgBenefit = math.max(d1 - d0, d0 * 0.05) -- เผื่อแถวอัปเกรดที่ไม่มีตัวเลข damage
                        damageOpts[#damageOpts + 1] = o
                    end
                    opts[#opts + 1] = o
                end)
            end
            -- การมี instance อยู่แล้วไม่ได้แปลว่ายูนิตนั้นวางครบจำนวนแล้ว
            -- src ใช้ Match.count(uuid) และยังสร้าง action วางซ้ำจนถึง spawn_cap
            local placedCount = ctx.countsByUuid[unit.uuid] or 0
            if placedCount < unitSpawnCap(data) and not Place.sold[unit.uuid] then
                unplaced[#unplaced + 1] = { unit = unit, data = data, placedCount = placedCount }
            end
        end
    end

    -- วางยูนิตใหม่ (ตัดทิ้งทั้งหมดถ้าสนามเต็ม)
    if not ctx.fieldFull then
        local reach = ctx.cash + math.max(Economy.rate, 0) * ECON.SAVE_MAX_ETA
        for _, e in ipairs(unplaced) do
            local unit, data = e.unit, e.data
            local uuid = unit.uuid
            local pend = Place.pending[uuid]
            local ns = Place.noSpot[uuid]
            if ns and ns.n >= 3 and now - ns.t >= 15 then Place.noSpot[uuid], ns = nil, nil end -- ให้ลองใหม่ได้ (coverage เปลี่ยนแล้ว)
            local blocked = (pend and now - pend < 4) or (ns and ns.n >= 3)
            local cost = tonumber(data.cost) or math.huge
            -- noSpot/รอเงินนานเกิน: ข้ามเฉพาะตัวนี้ ไม่บล็อกตัวอื่น
            if not blocked and cost <= reach then
                local o = { kind = "place", unit = unit, data = data, cost = cost }
                local farm = isFarm(unit.id)
                local usable = true
                if farm then
                    local income = farmIncomeAt(data, 0)
                    if income <= 0 and isMoneyPriorityUnit(unit.id, data) then income = cost * 0.25 end
                    local net = income * ctx.left - cost
                    if ctx.danger or ctx.leak then
                        usable = false -- ศัตรูเดินลึก/หลุดแล้ว: เงินทั้งหมดลงดาเมจ
                    elseif net > 0 or (isMoneyPriorityUnit(unit.id, data) and ctx.left >= 3) then
                        o.cashBenefit = math.max(net, cost * 0.1)
                    else
                        usable = false -- ฟาร์มคืนทุนไม่ทัน ไม่วาง
                    end
                end
                if usable then
                    -- ต้องรู้จุดวางก่อน (ทั้งตัวฟาร์มและตัวดาเมจ) ใช้แคชถ้ามี
                    local c = Place.spotCache[uuid]
                    local fresh = c and c.n == #ctx.mine and c.mode == ctx.mode and now - c.t < 6
                    local skip = false
                    if not fresh then
                        if ctx.spotBudget > 0 then ctx.spotBudget -= 1 else skip, ctx.incomplete = true, true end
                    end
                    if not skip then
                        local pos, score = Match.bestSpot(unit, ctx.mine, ctx)
                        if pos then
                            o.pos = pos
                            if not farm then
                                if isSupportUnit(data) then
                                    o.dmgBenefit = (score or 0) * 0.25 -- ตัวสนับสนุน: ค่าตามดาเมจของตัวดาเมจที่มันอยู่ใกล้
                                else
                                    o.dmgBenefit = unitDpsAt(data, 0) * coverFactor(score) * rangeFactor(ctx, unitRange(data))
                                end
                                damageOpts[#damageOpts + 1] = o
                            else
                                farmOpts[#farmOpts + 1] = o
                            end
                            opts[#opts + 1] = o
                        elseif not fresh then
                            local n2 = Place.noSpot[uuid] or { n = 0, t = 0 }
                            n2.n += 1
                            n2.t = now
                            Place.noSpot[uuid] = n2 -- นับ noSpot แล้วไปประเมินตัวอื่นต่อ
                        end
                    end
                end
            end
        end
    end

    -- ให้คะแนน: ดาเมจ
    local dmgRef = 0
    for _, o in ipairs(damageOpts) do
        o.value = (o.dmgBenefit * ctx.threat) / math.max(1, o.cost)
        if o.value > dmgRef then dmgRef = o.value end
    end
    -- ให้คะแนน: ฟาร์ม (แปลงเป็นหน่วยเดียวกับดาเมจ; ด่านยิ่งกดดัน เศรษฐกิจยิ่งน้ำหนักน้อย)
    local econW = math.clamp(1.4 - ctx.pressure, 0.15, 1.4)
    for _, o in ipairs(farmOpts) do
        local roi = o.cashBenefit / math.max(1, o.cost)
        o.value = roi * econW * ECON.FARM_WEIGHT * (dmgRef > 0 and dmgRef or 1)
        if o.kind == "place" and FARM_FIRST and ctx.wave <= 3 then o.value *= 1.3 end
    end
    for _, o in ipairs(opts) do
        o.value = (o.value or 0) * prioMul(o.unit.id, o.data)
        if o.kind == "place" then
            -- ช่วงต้นด่านต้องเติมสำเนาลงสนามก่อน ไม่ปล่อยให้อัปเกรดตัวเดียวจนแพ้
            if #ctx.mine < ECON.FILL_TARGET then
                local missing = (ECON.FILL_TARGET - #ctx.mine) / ECON.FILL_TARGET
                o.value *= 2.2 + missing * 1.8
            end
            if ctx.leak and not isFarm(o.unit.id) then o.value *= 2 end -- มีตัวหลุด: วางตัวใหม่ขวางหน้าก่อนอัปเกรด
        end
        if o.kind == "place" and o.value <= 0 then o.value = 1e-6 end -- กันค้าง: ยังไงก็ให้วางตัวที่เหลือได้เมื่อไม่มีอะไรดีกว่า
    end

    -- สนามเต็มแต่ยังมีตัวรอวาง: พิจารณาขาย/เปลี่ยนตัวที่อ่อนที่สุด
    if ctx.fieldFull and #unplaced > 0 then
        local bestNew
        for _, e in ipairs(unplaced) do
            if not isFarm(e.unit.id) then
                local cost = tonumber(e.data.cost) or math.huge
                local b = unitDpsAt(e.data, 0) * coverFactor(Place.totalWeight * 0.25)
                if not bestNew or b > bestNew.b then bestNew = { e = e, b = b, cost = cost } end
            end
        end
        if bestNew then
            local weakest
            for _, inst in ipairs(ctx.mine) do
                pcall(function()
                    local st = inst._stats
                    local id = st.id.Value
                    local d = Game.Units[id]
                    if not d or d.unsellable then return end
                    local idx = tonumber(st.upgrade.Value) or 0
                    local spent = st:FindFirstChild("total_spent") and tonumber(st.total_spent.Value) or 0
                    local refund = spent * ECON.SELL_REFUND
                    if ctx.cash + refund < bestNew.cost then return end
                    local sellable, keep = false, 0
                    if isFarm(id) then
                        keep = farmIncomeAt(d, idx) * ctx.left
                        sellable = keep < refund * 0.8
                    else
                        local r = rangeAt(d, idx)
                        keep = unitDpsAt(d, idx) * coverFactor(scoreAt(inst:GetPivot().Position, r, ctx.cov, ctx.wmul, r))
                        sellable = keep * 1.5 < bestNew.b
                    end
                    if isMoneyPriorityUnit(id, d) and ctx.left > 1 then sellable = false end
                    if sellable and (not weakest or keep < weakest.keep) then weakest = { inst = inst, id = id, keep = keep } end
                end)
            end
            if weakest then
                opts[#opts + 1] = {
                    kind = "sell", unit = { id = weakest.id, uuid = weakest.inst._stats.uuid.Value },
                    data = Game.Units[weakest.id], inst = weakest.inst, cost = 0,
                    value = (bestNew.b * ctx.threat / math.max(1, bestNew.cost)) * 0.8,
                    reason = "สนามเต็ม เปลี่ยนเป็น " .. tostring(bestNew.e.unit.id),
                }
            end
        end
    end
    return opts
end

-- ===== Economy.decide: เลือก action ที่ดีที่สุดเพียงอันเดียว =====
-- ถ้าตัวที่คุ้มที่สุดยังซื้อไม่ได้ แต่ใกล้พอและคุ้มกว่าตัวที่ซื้อได้ตอนนี้มาก -> ออมเงินรอ (ไม่เอาเงินไปผลาญกับของถูกที่คุ้มน้อย)
function Economy.decide(ctx, opts)
    if ctx.incomplete then return nil, "กำลังประเมินจุดวาง" end
    table.sort(opts, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return unitPriority(a.unit.id, a.data) > unitPriority(b.unit.id, b.data)
    end)
    local bestAll = opts[1]
    if not bestAll then return nil, nil end
    local bestAff
    for _, o in ipairs(opts) do
        if o.cost <= ctx.cash then bestAff = o break end
    end
    if bestAff == bestAll then
        Economy.saveTarget, Economy.saveSince = nil, nil
        return bestAll
    end
    local now = os.clock()
    local key = tostring(bestAll.kind) .. tostring(bestAll.unit.uuid or bestAll.unit.id)
    if Economy.saveTarget ~= key then Economy.saveTarget, Economy.saveSince = key, now end
    local eta = (bestAll.cost - ctx.cash) / math.max(Economy.rate, 0.01)
    local saving = Economy.rate > 0.5 and eta <= ECON.SAVE_MAX_ETA and now - Economy.saveSince < ECON.SAVE_MAX_TIME
        and not (ctx.leak or ctx.danger) -- ศัตรูเดินลึกแล้วไม่ออมเงิน ใช้ทันที
    if not bestAff then return nil, "รอเงินซื้อ " .. tostring(bestAll.unit.id) end
    if saving and bestAll.value >= bestAff.value * ECON.SAVE_RATIO then
        return nil, string.format("ออมเงินรอ %s %s (อีก ~%.0f วิ)", bestAll.kind, tostring(bestAll.unit.id), eta)
    end
    return bestAff
end

-- ===== ลงมือทำ action ที่เลือก =====
function Economy.act(action, ctx)
    print(string.format("[FD] เลือก %s %s | คุ้ม %.5f ราคา %d | เงิน %d เวฟเหลือ %d กดดัน %.2f ศัตรู %d | ครอบคลุมถึง %.2f หัวแถว %.2f เฝ้า %d layout/โหมด[%s]",
        action.kind, tostring(action.unit.id), action.value, action.cost, ctx.cash, ctx.left, ctx.pressure, ctx.enemies.count,
        ctx.reach, ctx.enemies.front, ctx.guards, ctx.mode))
    if action.kind == "place" then
        local ok = Match.place(action.unit, "economy", ctx)
        if ok then say("วาง " .. tostring(action.unit.id) .. " แล้วประเมินใหม่") task.wait(0.25) end
        return ok
    elseif action.kind == "upgrade" then
        local st = action.inst._stats
        local before = tonumber(st.upgrade.Value) or 0
        local ok, res = fire(R.upgradeUnit, action.inst)
        local t0 = os.clock()
        while os.clock() - t0 < 1.5 and (tonumber(st.upgrade.Value) or 0) == before do task.wait(0.1) end
        local changed = (tonumber(st.upgrade.Value) or 0) ~= before
        if changed or (ok and res) then
            say("อัปเกรด " .. tostring(action.unit.id) .. " แล้วประเมินใหม่")
            Place.spotCache = {} -- ระยะ/coverage เปลี่ยน
            task.wait(0.15)
            return true
        end
        Place.upFail[action.inst] = os.clock()
        return false
    elseif action.kind == "sell" then
        local ok = fire("sell_unit_ingame", action.inst)
        if ok then
            Place.sold[action.unit.uuid] = true -- ตัวที่ขายแล้วไม่ถูกวางกลับมาอีกในแมตช์นี้
            Place.spotCache, Place.cap, Place.failStreak = {}, nil, 0
            say(tostring(action.reason or "ขายยูนิต") .. " แล้วประเมินใหม่")
            task.wait(0.3)
        end
        return ok
    end
    return false
end

-- หนึ่งรอบ = ประเมินใหม่ทั้งหมด แล้วทำ action เดียว
function Economy.step()
    if not prepareMatch() then return false end
    local ctx = Economy.snapshot()
    local action, why = Economy.decide(ctx, Economy.options(ctx))
    if not action then
        if why and why ~= Economy.lastMsg then Economy.lastMsg = why say(why) end
        return false
    end
    Economy.lastMsg = nil
    return Economy.act(action, ctx)
end

local function autoPlay()
    if R.autoPlay then fire(R.autoPlay, true) end
    Economy.step()
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
    sendWebhook("start", "▶️ เริ่มออโต้ฟาร์ม", plr.Name, 5763719)
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
                    -- src-style economy loop: หนึ่ง action ต่อรอบ แล้ววนประเมินใหม่
                    while alive() and not matchFinished() do
                        if not autoSkipOn() then voteSkip() end
                        autoPlay()
                        task.wait(LOOP_DELAY)
                    end
                end
                if alive() and matchFinished() then
                    task.wait(2) -- รอผลลัพธ์
                    local won = lastResult and lastResult.victory
                    if won ~= nil then Match.recordResult(won == true) end
                    if won ~= false then
                        markCleared()
                        sendWebhook("win", "🏆 ชนะด่าน", "เพชรตอนนี้: " .. gems(), 5763719)
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
            sendWebhook("error", "⚠️ เกิดข้อผิดพลาด", "```" .. tostring(err):sub(1, 500) .. "```", 15548997)
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
loadSettings()
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
