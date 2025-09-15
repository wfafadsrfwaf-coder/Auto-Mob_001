-- 🐉 Auto Farm + Auto Sell + GUI
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Player = Players.LocalPlayer

--== CONFIG ==--
local AUTO_FARM = true
local RETURN_POINT = CFrame.new(-170, 670, -851)
local SELL_WORLD = 3475397644
local FARM_WORLD = 4869039553
local MEAT_LIMIT, BACON_LIMIT = 10000, 10000

local WORLD_TARGETS = {
    [FARM_WORLD] = { "Dimorph", "Ptero", "Stego" },
}

local BURST_PER_FRAME = 8
local RESCAN_DELAY = 0.02
local REMOTE_MAX_CALLS_PER_SEC = 20
local REMOTE_MIN_INTERVAL_SEC = 0.05
local REMOTE_PER_TARGET_COOLDOWN = 0.15
local LOOT_PULL_TIME = 0.3
local LOOT_STAGGER = 0.05
local LOOT_NAMES = { "AshesResourcesModel", "MeatFoodModel", "BaconFoodModel" }

--== STATE ==--
local CURRENT_TARGETS = {}
local LOOT_SET = {}
local PlayerAntiFallPart = nil
local Character, HRP, Humanoid
local lastDeadMobCF = RETURN_POINT
local SPACEBAR_PRESSED = false
local ResourceLabel = nil
local AUTO_SELLING = false

--== Helper ==--
local function makeNameSet(list)
    local t = {}
    if list then for _, n in ipairs(list) do t[n:lower()] = true end end
    return t
end
CURRENT_TARGETS = makeNameSet(WORLD_TARGETS[game.PlaceId])
LOOT_SET = makeNameSet(LOOT_NAMES)

--== Wait Map Load ==--
local function waitForMapToLoad(timeout)
    timeout = timeout or 20
    local startTime = tick()
    while tick() - startTime < timeout do
        local char = Player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")

        if game.PlaceId == FARM_WORLD or game.PlaceId == SELL_WORLD then
            if char and hrp and remotes then
                return true
            end
        end
        task.wait(0.5)
    end
    return false
end

--== GUI ==--
local function createInfoGui()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoFarmInfoGui"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = game:GetService("CoreGui")

    local container = Instance.new("Frame")
    container.Name = "InfoContainer"
    container.Size = UDim2.new(0, 420, 0, 130)
    container.Position = UDim2.new(0.5, -210, 0, 20)
    container.BackgroundTransparency = 0.2
    container.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    container.Parent = screenGui

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Text = "ราคา 300 บาท"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 20
    title.TextColor3 = Color3.fromRGB(255, 220, 100)
    title.BackgroundTransparency = 1
    title.Parent = container

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 1, -50)
    label.Position = UDim2.new(0, 10, 0, 45)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextSize = 20
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.Text = "Loading..."
    label.Parent = container

    return label
end

--== Update GUI with resources ==--
local function startResourceTracker()
    ResourceLabel = createInfoGui()
    local resources = Player:WaitForChild("Data"):WaitForChild("Resources")

    local function updateLabel()
        local meat = resources:FindFirstChild("Meat")
        local bacon = resources:FindFirstChild("Bacon")
        local ashes = resources:FindFirstChild("Ashes")

        local meatVal = meat and meat.Value or 0
        local baconVal = bacon and bacon.Value or 0
        local ashesVal = ashes and ashes.Value or 0

        ResourceLabel.Text = string.format(
            "📦 อัพเดทใหม่\n🥩 Meat: %s\n🥓 Bacon: %s\n⚱️ Ashes: %s",
            meatVal, baconVal, ashesVal
        )

        -- Auto Sell Check
        if game.PlaceId == FARM_WORLD and not AUTO_SELLING then
            if meatVal >= MEAT_LIMIT and baconVal >= BACON_LIMIT then
                AUTO_SELLING = true
                task.spawn(function()
                    local teleport = game:GetService("ReplicatedStorage").Remotes.WorldTeleportRemote
                    if teleport then teleport:InvokeServer(SELL_WORLD, {}) end
                end)
            end
        end
    end

    for _, res in ipairs({"Meat", "Bacon", "Ashes"}) do
        local node = resources:FindFirstChild(res)
        if node then node.Changed:Connect(updateLabel) end
    end

    updateLabel()
end

--== Platform ==--
local function cleanupPlatforms()
    if PlayerAntiFallPart and PlayerAntiFallPart.Parent then PlayerAntiFallPart:Destroy() end
    for i = 1, 50 do
        local platform = workspace:FindFirstChild("DragonAntiFall_" .. i)
        if platform then platform:Destroy() end
    end
end

local function createPlayerAntiFallPart()
    if not Character or not HRP then return end
    if PlayerAntiFallPart and PlayerAntiFallPart.Parent then
        PlayerAntiFallPart.CFrame = HRP.CFrame * CFrame.new(0, -4, 0)
        return
    end
    local part = Instance.new("Part")
    part.Size = Vector3.new(12, 1, 12)
    part.Anchored = true
    part.CanCollide = true
    part.Transparency = 0.4
    part.Material = Enum.Material.ForceField
    part.Color = Color3.fromRGB(100, 255, 100)
    part.CFrame = HRP.CFrame * CFrame.new(0, -4, 0)
    part.Parent = workspace
    PlayerAntiFallPart = part
end

local function createDragonAntiFallParts()
    if not Character then return end
    local dragons = Character:FindFirstChild("Dragons")
    if not dragons then return end
    for i = 1, 50 do
        local dragon = dragons:FindFirstChild(tostring(i))
        if dragon and dragon:FindFirstChild("RealHitbox") then
            local hitbox = dragon.RealHitbox
            local name = "DragonAntiFall_" .. i
            local platform = workspace:FindFirstChild(name)
            local cf = lastDeadMobCF or (hitbox.CFrame * CFrame.new(0, -8, 0))
            if platform then
                platform.CFrame = cf
            else
                local part = Instance.new("Part")
                part.Size = Vector3.new(15, 1, 15)
                part.Anchored = true
                part.CanCollide = true
                part.Transparency = 0.3
                part.Material = Enum.Material.ForceField
                part.Color = Color3.fromRGB(255, 100, 255)
                part.CFrame = cf
                part.Name = name
                part.Parent = workspace
            end
        end
    end
end

local function createAllAntiFallPlatforms()
    createPlayerAntiFallPart()
    createDragonAntiFallParts()
end

local function startAntiFallLoop()
    task.spawn(function()
        while AUTO_FARM do
            if Character and HRP then createAllAntiFallPlatforms() end
            task.wait(0.1)
        end
    end)
end

--== Character Refresh ==--
local function refreshChar()
    cleanupPlatforms()
    Character = Player.Character or Player.CharacterAdded:Wait()
    HRP = Character:WaitForChild("HumanoidRootPart")
    Humanoid = Character:WaitForChild("Humanoid")
end
refreshChar()
Player.CharacterAdded:Connect(function() task.defer(refreshChar) end)

--== Attack ==--
local function getAttackRemote()
    local dragons = Character and Character:FindFirstChild("Dragons")
    if not dragons then return nil end
    for i = 1, 50 do
        local d = dragons:FindFirstChild(tostring(i))
        if d and d:FindFirstChild("Remotes") and d.Remotes:FindFirstChild("PlaySoundRemote") then
            return d.Remotes.PlaySoundRemote
        end
    end
    return nil
end

local function pressSpacebarOnce()
    if not SPACEBAR_PRESSED then
        local vim = game:GetService("VirtualInputManager")
        vim:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.wait(0.1)
        vim:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        SPACEBAR_PRESSED = true
    end
end

local Rate = {tokens = REMOTE_MAX_CALLS_PER_SEC, lastRefill = os.clock(), last = 0, perTarget = setmetatable({}, {__mode="k"})}
local function refillTokens() local now=os.clock() local dt=now-Rate.lastRefill if dt>0 then Rate.tokens=math.clamp(Rate.tokens+dt*REMOTE_MAX_CALLS_PER_SEC,0,REMOTE_MAX_CALLS_PER_SEC) Rate.lastRefill=now end end
local function canFireForTarget(target) refillTokens() local now=os.clock() if now-Rate.last<REMOTE_MIN_INTERVAL_SEC then return false end local tlast=Rate.perTarget[target] if tlast and now-tlast<REMOTE_PER_TARGET_COOLDOWN then return false end if Rate.tokens<1 then return false end Rate.tokens-=1 Rate.last=now Rate.perTarget[target]=now return true end

local function stickToMob(target)
    if not Character or not HRP or not target then return end
    local lastCF = RETURN_POINT
    while target and target.Parent and Character and HRP do
        local root = target:FindFirstChild("HumanoidRootPart")
        local cf = root and root.CFrame or target:GetPivot()
        if cf then
            lastCF = cf
            Character:PivotTo(cf + Vector3.new(0, 6, 0))
        end
        local health = target:FindFirstChild("Health")
        if not health or health.Value <= 0 then lastDeadMobCF = lastCF break end
        RunService.Heartbeat:Wait()
    end
    Character:PivotTo(lastDeadMobCF + Vector3.new(0, 6, 0))
end

local function getAllTargets()
    local t = {}
    local folder = workspace:FindFirstChild("MobFolder")
    if not folder then return t end
    for _, holder in ipairs(folder:GetChildren()) do
        for _, mob in ipairs(holder:GetChildren()) do
            if CURRENT_TARGETS[mob.Name:lower()] and mob:FindFirstChild("Health") and mob.Health.Value>0 then
                table.insert(t,{mob=mob,health=mob.Health})
            end
        end
    end
    return t
end

local function attackUntilDead(target,health,remote)
    pressSpacebarOnce()
    task.spawn(function() stickToMob(target) end)
    while target.Parent and health and health.Value and health.Value>0 do
        for _=1,BURST_PER_FRAME do
            if canFireForTarget(target) then pcall(function() remote:FireServer("Breath","Mobs",target) end) else break end
        end
        RunService.Heartbeat:Wait()
    end
end

--== Auto Farm ==--
local function runContinuousFarm()
    startAntiFallLoop()
    CURRENT_TARGETS = makeNameSet(WORLD_TARGETS[FARM_WORLD])
    local remote = getAttackRemote()
    if not remote then return end

    while AUTO_FARM and game.PlaceId == FARM_WORLD do
        local targets = getAllTargets()
        if #targets==0 then
            task.wait(RESCAN_DELAY)
        else
            for _,t in ipairs(targets) do
                if t.mob.Parent and t.health and t.health.Value>0 then
                    attackUntilDead(t.mob,t.health,remote)
                end
                if not AUTO_FARM then break end
                task.wait(RESCAN_DELAY)
            end
        end
    end
end-- ขายทุกอย่างให้หมด ด้วย FireServer(unpack(args)) แบบตัวอย่างของคุณ
local function sellAllItems()
    local resources = Player:WaitForChild("Data"):WaitForChild("Resources")
    local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
    local sellRemote = remotes:WaitForChild("SellItemRemote")

    -- รายการที่จะขาย
    local toSell = { "Meat", "Bacon", "Ashes" }

    -- helper: ขาย item ทีละชุด จนเหลือ 0 หรือครบจำนวนรอบกันแหก
    local function sellItemUntilZero(name)
        local val = resources:FindFirstChild(name)
        if not val then return end

        local tries = 0
        while val.Value > 0 and tries < 50 do
            local amount = val.Value  -- อยากขายหมดก็ส่งเท่าที่มี
            local args = { { ItemName = name, Amount = amount } }

            -- ตามตัวอย่างที่คุณให้มา: FireServer(unpack(args))
            local ok, err = pcall(function()
                sellRemote:FireServer(unpack(args))
            end)
            if not ok then
                warn("ขาย ", name, " ล้มเหลว:", err)
                break
            end

            -- รอให้เซิร์ฟอัพเดตค่ากลับมา
            local before = val.Value
            local t0 = os.clock()
            repeat
                task.wait(0.15)
            until val.Value < before or (os.clock() - t0) > 2

            tries += 1
        end
        print(("✅ %s เหลือ %d"):format(name, val.Value))
    end

    -- ขายทุกชิ้น
    for _, item in ipairs(toSell) do
        sellItemUntilZero(item)
        task.wait(0.1)
    end
end

--== Start ==--
task.spawn(function()
    if not waitForMapToLoad(25) then return end
    startResourceTracker()

    if game.PlaceId == FARM_WORLD then
        task.wait(3)
        createAllAntiFallPlatforms()
        runContinuousFarm()

    elseif game.PlaceId == SELL_WORLD then
        print("🛒 กำลังขายทั้งหมด...")
        task.wait(1.5) -- รอให้ resource / remote โหลดให้ครบ

        sellAllItems() -- ฟังก์ชันขายที่แก้ให้ขายทั้งหมดแล้ว

        -- ✅ ยืนยันว่าขายหมดจริงก่อนวาร์ป
        local resources = Player:WaitForChild("Data"):WaitForChild("Resources")
        local meat  = resources:FindFirstChild("Meat")
        local bacon = resources:FindFirstChild("Bacon")
        local ashes = resources:FindFirstChild("Ashes")

        local function allZero()
            return (not meat or meat.Value == 0)
               and (not bacon or bacon.Value == 0)
               and (not ashes or ashes.Value == 0)
        end

        -- รอสั้น ๆ ให้ค่าลดครบ
        local t0 = os.clock()
        while not allZero() and (os.clock() - t0) < 5 do
            task.wait(0.2)
        end

        print("✈️ วาร์ปกลับโลกฟาร์ม...")
        local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
        local teleportRemote = remotes:WaitForChild("WorldTeleportRemote")
        local args = { 4869039553, {} }
        pcall(function()
            teleportRemote:InvokeServer(unpack(args))
        end)
    end
end)
