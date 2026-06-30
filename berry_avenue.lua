-- ╔══════════════════════════════════════════════════╗
-- ║         nexus — berry avenue rp                 ║
-- ║         clean, unobfuscated, maintained         ║
-- ╚══════════════════════════════════════════════════╝

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting     = game:GetService("Lighting")
local StarterGui   = game:GetService("StarterGui")
local HttpService  = game:GetService("HttpService")

local lp  = Players.LocalPlayer
local cam = workspace.CurrentCamera

-- ── state ─────────────────────────────────────────────────────────────
local conns = {}
local function conn(c) table.insert(conns, c) return c end

local flyActive     = false
local flyBody       = nil
local flyAttach     = nil
local savedPos      = nil
local origLighting  = {}
local espPool       = {}     -- [player] = { highlight, billboard }
local godConn       = nil
local afkConn       = nil
local bhopConn      = nil

-- ── config ─────────────────────────────────────────────────────────────
local cfg = {
    fly       = { enabled=false, speed=60 },
    speed     = { enabled=false, value=32, default=16 },
    jump      = { enabled=false, value=80,  default=50 },
    noclip    = { enabled=false },
    inf_jump  = { enabled=false },
    esp       = { enabled=false, color=Color3.fromRGB(255,80,80), fill=0.6 },
    god       = { enabled=false },
    afk       = { enabled=false },
    fullbright= { enabled=false },
}

-- ══════════════════════════════════════════════════════════════════════
-- FEATURE LOGIC
-- ══════════════════════════════════════════════════════════════════════

-- ── fly ───────────────────────────────────────────────────────────────
local function destroyFly()
    if flyBody   then flyBody:Destroy();   flyBody   = nil end
    if flyAttach then flyAttach:Destroy(); flyAttach = nil end
    flyActive = false
    local char = lp.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = false end
end

local function startFly()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not (root and hum) then return end
    hum.PlatformStand = true
    local att = Instance.new("Attachment"); att.Parent = root
    local bv  = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(1e9,1e9,1e9)
    bv.Velocity = Vector3.zero
    bv.Parent   = root
    flyAttach   = att
    flyBody     = bv
    flyActive   = true
end

local function flyTick()
    if not (cfg.fly.enabled and flyActive and flyBody) then return end
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if not root then destroyFly(); return end

    local spd = cfg.fly.speed
    local vel = Vector3.zero
    local look = cam.CFrame.LookVector
    local right= cam.CFrame.RightVector

    if UIS:IsKeyDown(Enum.KeyCode.W)     then vel = vel + look * spd  end
    if UIS:IsKeyDown(Enum.KeyCode.S)     then vel = vel - look * spd  end
    if UIS:IsKeyDown(Enum.KeyCode.A)     then vel = vel - right* spd  end
    if UIS:IsKeyDown(Enum.KeyCode.D)     then vel = vel + right* spd  end
    if UIS:IsKeyDown(Enum.KeyCode.Space) then vel = vel + Vector3.new(0,spd,0) end
    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then vel = vel - Vector3.new(0,spd,0) end

    flyBody.Velocity = vel
end

local function setFly(on)
    cfg.fly.enabled = on
    if on then startFly() else destroyFly() end
end

conn(lp.CharacterAdded:Connect(function()
    destroyFly()
    if cfg.fly.enabled then task.wait(0.5); startFly() end
end))

-- ── speed / jump ──────────────────────────────────────────────────────
local function applyMovement()
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum.WalkSpeed  = cfg.speed.enabled and cfg.speed.value or cfg.speed.default
    hum.JumpPower  = cfg.jump.enabled  and cfg.jump.value  or cfg.jump.default
end

conn(lp.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid",5)
    if hum then applyMovement() end
end))

-- ── noclip ────────────────────────────────────────────────────────────
conn(RunService.Stepped:Connect(function()
    if not cfg.noclip.enabled then return end
    local char = lp.Character; if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide = false end
    end
end))

-- ── infinite jump ─────────────────────────────────────────────────────
local function connectBhop(char)
    local hum = char:WaitForChild("Humanoid",4)
    if not hum then return end
    conn(hum.StateChanged:Connect(function(_, new)
        if cfg.inf_jump.enabled and new == Enum.HumanoidStateType.Landed then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end))
end
if lp.Character then connectBhop(lp.Character) end
conn(lp.CharacterAdded:Connect(connectBhop))

-- ── god mode ──────────────────────────────────────────────────────────
local function setGod(on)
    cfg.god.enabled = on
    if godConn then godConn:Disconnect(); godConn = nil end
    if not on then return end
    godConn = conn(RunService.Heartbeat:Connect(function()
        local char = lp.Character; if not char then return end
        local hum  = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
        if hum.Health < hum.MaxHealth then hum.Health = hum.MaxHealth end
    end))
end

-- ── anti-afk ──────────────────────────────────────────────────────────
local function setAFK(on)
    cfg.afk.enabled = on
    if afkConn then afkConn:Disconnect(); afkConn = nil end
    if not on then return end
    -- fire a tiny virtual jump every 14 min to reset the server's AFK timer
    afkConn = conn(task.spawn(function()
        while cfg.afk.enabled do
            task.wait(840)  -- 14 minutes
            if not cfg.afk.enabled then break end
            local VIS = game:GetService("VirtualInputManager")
            pcall(function() VIS:SendKeyEvent(true, "Space", false, game) end)
            task.wait(0.1)
            pcall(function() VIS:SendKeyEvent(false,"Space", false, game) end)
        end
    end))
end

-- ── fullbright ────────────────────────────────────────────────────────
local function setFullbright(on)
    cfg.fullbright.enabled = on
    if on then
        origLighting.Brightness       = Lighting.Brightness
        origLighting.Ambient          = Lighting.Ambient
        origLighting.OutdoorAmbient   = Lighting.OutdoorAmbient
        origLighting.FogEnd           = Lighting.FogEnd
        origLighting.GlobalShadows    = Lighting.GlobalShadows
        Lighting.Brightness     = 2
        Lighting.Ambient        = Color3.fromRGB(178,178,178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178,178,178)
        Lighting.FogEnd         = 1e6
        Lighting.GlobalShadows  = false
    else
        if origLighting.Brightness then
            Lighting.Brightness     = origLighting.Brightness
            Lighting.Ambient        = origLighting.Ambient
            Lighting.OutdoorAmbient = origLighting.OutdoorAmbient
            Lighting.FogEnd         = origLighting.FogEnd
            Lighting.GlobalShadows  = origLighting.GlobalShadows
        end
    end
end

-- ── ESP ───────────────────────────────────────────────────────────────
local function destroyESP(plr)
    local e = espPool[plr]
    if not e then return end
    pcall(function() if e.highlight then e.highlight:Destroy() end end)
    pcall(function() if e.billboard then e.billboard:Destroy() end end)
    espPool[plr] = nil
end

local function buildESP(plr)
    if plr == lp then return end
    destroyESP(plr)
    local char = plr.Character; if not char then return end

    local hl = Instance.new("Highlight")
    hl.FillColor         = cfg.esp.color
    hl.OutlineColor      = Color3.fromRGB(255,255,255)
    hl.FillTransparency  = cfg.esp.fill
    hl.OutlineTransparency = 0
    hl.Adornee           = char
    hl.Enabled           = cfg.esp.enabled
    hl.Parent            = game:GetService("CoreGui")

    local head = char:FindFirstChild("Head")
    local bb   = Instance.new("BillboardGui")
    bb.Size          = UDim2.new(0,120,0,36)
    bb.StudsOffset   = Vector3.new(0,2.5,0)
    bb.AlwaysOnTop   = true
    bb.Enabled       = cfg.esp.enabled
    bb.Adornee       = head
    bb.Parent        = game:GetService("CoreGui")

    local lbl = Instance.new("TextLabel")
    lbl.Size            = UDim2.new(1,0,1,0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3      = Color3.fromRGB(255,255,255)
    lbl.TextStrokeTransparency = 0
    lbl.TextStrokeColor3       = Color3.fromRGB(0,0,0)
    lbl.Font            = Enum.Font.GothamBold
    lbl.TextSize        = 13
    lbl.Text            = plr.DisplayName
    lbl.Parent          = bb

    espPool[plr] = { highlight=hl, billboard=bb, label=lbl }
end

local function refreshESP()
    for plr, e in pairs(espPool) do
        if e.highlight then e.highlight.Enabled = cfg.esp.enabled end
        if e.billboard then e.billboard.Enabled = cfg.esp.enabled end
    end
end

-- tick: update labels with distance
conn(RunService.Heartbeat:Connect(function()
    if not cfg.esp.enabled then return end
    local myRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    for plr, e in pairs(espPool) do
        local char = plr.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not (e.label and root) then continue end
        local dist = myRoot and math.floor((myRoot.Position - root.Position).Magnitude) or 0
        e.label.Text = plr.DisplayName .. "\n" .. dist .. "m"
        -- rebuild if char changed
        if e.highlight and e.highlight.Adornee ~= char then
            buildESP(plr)
        end
    end
end))

-- register all players
for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= lp then
        buildESP(plr)
        conn(plr.CharacterAdded:Connect(function() task.wait(0.2); buildESP(plr) end))
    end
end
conn(Players.PlayerAdded:Connect(function(plr)
    buildESP(plr)
    conn(plr.CharacterAdded:Connect(function() task.wait(0.2); buildESP(plr) end))
end))
conn(Players.PlayerRemoving:Connect(destroyESP))

-- ── teleport ──────────────────────────────────────────────────────────
-- Berry Avenue landmark coordinates (approximate — Berry Avenue RP, game 8481844229).
-- Use "Save Position" in-game to capture exact spots you care about.
local LOCATIONS = {
    { name="School",          pos=Vector3.new( 132,  3,  -48) },
    { name="Police Station",  pos=Vector3.new(-205,  3,   72) },
    { name="Hospital",        pos=Vector3.new( 240,  3,  210) },
    { name="Bank",            pos=Vector3.new(  18,  3,  180) },
    { name="Grocery Store",   pos=Vector3.new(-120,  3, -230) },
    { name="Park",            pos=Vector3.new(  45,  3, -310) },
    { name="Residential Zone",pos=Vector3.new( 310,  3,  -90) },
    { name="Spawn",           pos=Vector3.new(   0,  5,    0) },
}

local function teleportTo(pos)
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    root.CFrame = CFrame.new(pos + Vector3.new(0,3,0))
end

local function teleportToPlayer(plr)
    local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    teleportTo(root.Position + Vector3.new(3,0,0))
end

-- ── avatar copy ───────────────────────────────────────────────────────
local function copyAvatar(plr)
    local myHum     = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    local targetHum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
    if not (myHum and targetHum) then return end
    local desc = targetHum:GetAppliedDescription()
    pcall(function() myHum:ApplyDescription(desc) end)
end

-- ── render step: fly tick ─────────────────────────────────────────────
conn(RunService.RenderStepped:Connect(function()
    flyTick()
    applyMovement()  -- keep speed/jump live even if game tries to reset it
end))

-- ══════════════════════════════════════════════════════════════════════
-- GUI
-- ══════════════════════════════════════════════════════════════════════
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name          = "NexusBerryAve"
ScreenGui.ResetOnSpawn  = false
ScreenGui.ZIndexBehavior= Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder  = 999
pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
if not ScreenGui.Parent then ScreenGui.Parent = lp:WaitForChild("PlayerGui") end

local function mkCorner(parent, r)
    local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 6); c.Parent=parent
end
local function mkStroke(parent, col, t)
    local s=Instance.new("UIStroke"); s.Color=col or Color3.fromRGB(60,60,60)
    s.Thickness=t or 1; s.Parent=parent
end
local function tween(obj, props, t)
    TweenService:Create(obj,TweenInfo.new(t or 0.15),props):Play()
end

-- main window
local Win = Instance.new("Frame")
Win.Name            = "Window"
Win.Size            = UDim2.new(0,320,0,400)
Win.Position        = UDim2.new(0.5,-160,0.5,-200)
Win.BackgroundColor3= Color3.fromRGB(18,18,22)
Win.BorderSizePixel = 0
Win.ClipsDescendants= true
Win.Parent          = ScreenGui
mkCorner(Win,10)
mkStroke(Win,Color3.fromRGB(55,55,70),1.5)

-- title bar
local TitleBar = Instance.new("Frame")
TitleBar.Size            = UDim2.new(1,0,0,36)
TitleBar.BackgroundColor3= Color3.fromRGB(26,26,32)
TitleBar.BorderSizePixel = 0
TitleBar.Parent          = Win

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size              = UDim2.new(1,-80,1,0)
TitleLabel.Position          = UDim2.new(0,12,0,0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.TextColor3        = Color3.fromRGB(220,220,230)
TitleLabel.Font              = Enum.Font.GothamBold
TitleLabel.TextSize          = 14
TitleLabel.TextXAlignment    = Enum.TextXAlignment.Left
TitleLabel.Text              = "nexus  •  berry avenue"
TitleLabel.Parent            = TitleBar

-- close / minimise
local function mkIconBtn(text, xOff)
    local btn = Instance.new("TextButton")
    btn.Size            = UDim2.new(0,22,0,22)
    btn.Position        = UDim2.new(1,xOff,0.5,-11)
    btn.BackgroundColor3= Color3.fromRGB(40,40,50)
    btn.TextColor3      = Color3.fromRGB(200,200,210)
    btn.Font            = Enum.Font.GothamBold
    btn.TextSize        = 12
    btn.Text            = text
    btn.BorderSizePixel = 0
    btn.Parent          = TitleBar
    mkCorner(btn,4)
    return btn
end
local CloseBtn = mkIconBtn("✕", -32)
local MinBtn   = mkIconBtn("−", -58)

local minimised = false
local contentH  = 364  -- Win.Size.Y.Offset - titlebar

local MinContent = Instance.new("Frame")
MinContent.Name            = "Content"
MinContent.Size            = UDim2.new(1,0,0,contentH)
MinContent.Position        = UDim2.new(0,0,0,36)
MinContent.BackgroundTransparency = 1
MinContent.ClipsDescendants= true
MinContent.Parent          = Win

MinBtn.MouseButton1Click:Connect(function()
    minimised = not minimised
    tween(Win, { Size = UDim2.new(0,320, 0, minimised and 36 or 400) }, 0.18)
    MinBtn.Text = minimised and "+" or "−"
end)
CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- drag
do
    local dragging, dragStart, startPos = false, nil, nil
    TitleBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging=true; dragStart=i.Position; startPos=Win.Position
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
            local delta = i.Position - dragStart
            Win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+delta.X,
                                     startPos.Y.Scale, startPos.Y.Offset+delta.Y)
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging=false
        end
    end)
end

-- ── tab row ───────────────────────────────────────────────────────────
local TABS = {"Move","Teleport","ESP","Misc"}
local TAB_COL = {
    active   = Color3.fromRGB(120,80,220),
    inactive = Color3.fromRGB(30,30,38),
}

local TabRow = Instance.new("Frame")
TabRow.Size            = UDim2.new(1,0,0,32)
TabRow.BackgroundColor3= Color3.fromRGB(22,22,28)
TabRow.BorderSizePixel = 0
TabRow.Parent          = MinContent
local TabLayout = Instance.new("UIListLayout")
TabLayout.FillDirection      = Enum.FillDirection.Horizontal
TabLayout.HorizontalAlignment= Enum.HorizontalAlignment.Left
TabLayout.SortOrder          = Enum.SortOrder.LayoutOrder
TabLayout.Parent             = TabRow

local paneParent = Instance.new("Frame")
paneParent.Size              = UDim2.new(1,0,1,-32)
paneParent.Position          = UDim2.new(0,0,0,32)
paneParent.BackgroundTransparency = 1
paneParent.Parent            = MinContent

local tabBtns  = {}
local tabPanes = {}
local activeTab= nil

local function switchTab(name)
    for _, n in ipairs(TABS) do
        local b = tabBtns[n]; local p = tabPanes[n]
        if n == name then
            tween(b, {BackgroundColor3=TAB_COL.active}, 0.12)
            p.Visible = true
        else
            tween(b, {BackgroundColor3=TAB_COL.inactive}, 0.12)
            p.Visible = false
        end
    end
    activeTab = name
end

local function makeTab(name, order)
    local btn = Instance.new("TextButton")
    btn.Size            = UDim2.new(0,80,1,0)
    btn.BackgroundColor3= TAB_COL.inactive
    btn.TextColor3      = Color3.fromRGB(200,200,210)
    btn.Font            = Enum.Font.GothamBold
    btn.TextSize        = 12
    btn.Text            = name
    btn.BorderSizePixel = 0
    btn.LayoutOrder     = order
    btn.Parent          = TabRow
    tabBtns[name]       = btn

    local pane = Instance.new("ScrollingFrame")
    pane.Size                 = UDim2.new(1,0,1,0)
    pane.BackgroundTransparency = 1
    pane.BorderSizePixel      = 0
    pane.ScrollBarThickness   = 3
    pane.ScrollBarImageColor3 = Color3.fromRGB(100,80,180)
    pane.CanvasSize           = UDim2.new(0,0,0,0)
    pane.AutomaticCanvasSize  = Enum.AutomaticSize.Y
    pane.Visible              = false
    pane.Parent               = paneParent
    tabPanes[name] = pane

    local layout = Instance.new("UIListLayout")
    layout.Padding    = UDim.new(0,6)
    layout.SortOrder  = Enum.SortOrder.LayoutOrder
    layout.Parent     = pane
    Instance.new("UIPadding").PaddingTop    = UDim.new(0,8); -- inline below
    local pad = Instance.new("UIPadding"); pad.PaddingLeft=UDim.new(0,10)
    pad.PaddingRight=UDim.new(0,10); pad.PaddingTop=UDim.new(0,8); pad.Parent=pane

    btn.MouseButton1Click:Connect(function() switchTab(name) end)
    return pane
end

local movePane = makeTab("Move",1)
local tpPane   = makeTab("Teleport",2)
local espPane  = makeTab("ESP",3)
local miscPane = makeTab("Misc",4)

-- ── widget builders ───────────────────────────────────────────────────
local rowZ = 0
local function nextZ() rowZ=rowZ+1; return rowZ end

local function mkSection(pane, title)
    local f = Instance.new("Frame")
    f.Size            = UDim2.new(1,0,0,20)
    f.BackgroundTransparency = 1
    f.LayoutOrder     = nextZ()
    f.Parent          = pane
    local lbl = Instance.new("TextLabel")
    lbl.Size          = UDim2.new(1,0,1,0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3    = Color3.fromRGB(130,100,220)
    lbl.Font          = Enum.Font.GothamBold
    lbl.TextSize      = 11
    lbl.TextXAlignment= Enum.TextXAlignment.Left
    lbl.Text          = "— " .. title:upper()
    lbl.Parent        = f
    return f
end

local function mkToggle(pane, label, getter, setter)
    local row = Instance.new("Frame")
    row.Size            = UDim2.new(1,0,0,30)
    row.BackgroundColor3= Color3.fromRGB(26,26,34)
    row.BorderSizePixel = 0
    row.LayoutOrder     = nextZ()
    row.Parent          = pane
    mkCorner(row,6)

    local lbl = Instance.new("TextLabel")
    lbl.Size          = UDim2.new(1,-50,1,0)
    lbl.Position      = UDim2.new(0,10,0,0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3    = Color3.fromRGB(210,210,220)
    lbl.Font          = Enum.Font.Gotham
    lbl.TextSize      = 13
    lbl.TextXAlignment= Enum.TextXAlignment.Left
    lbl.Text          = label
    lbl.Parent        = row

    local knob = Instance.new("TextButton")
    knob.Size            = UDim2.new(0,36,0,18)
    knob.Position        = UDim2.new(1,-46,0.5,-9)
    knob.BorderSizePixel = 0
    knob.Text            = ""
    knob.Parent          = row
    mkCorner(knob,9)

    local dot = Instance.new("Frame")
    dot.Size            = UDim2.new(0,14,0,14)
    dot.Position        = UDim2.new(0,2,0.5,-7)
    dot.BackgroundColor3= Color3.fromRGB(255,255,255)
    dot.BorderSizePixel = 0
    dot.Parent          = knob
    mkCorner(dot,7)

    local function refresh()
        local on = getter()
        tween(knob, { BackgroundColor3 = on and Color3.fromRGB(110,70,210) or Color3.fromRGB(50,50,62) })
        tween(dot,  { Position = on and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7) })
    end
    refresh()

    knob.MouseButton1Click:Connect(function()
        setter(not getter())
        refresh()
    end)
    return refresh
end

local function mkSlider(pane, label, min, max, getter, setter)
    local row = Instance.new("Frame")
    row.Size            = UDim2.new(1,0,0,48)
    row.BackgroundColor3= Color3.fromRGB(26,26,34)
    row.BorderSizePixel = 0
    row.LayoutOrder     = nextZ()
    row.Parent          = pane
    mkCorner(row,6)

    local hdr = Instance.new("TextLabel")
    hdr.Size          = UDim2.new(1,0,0,20)
    hdr.Position      = UDim2.new(0,10,0,4)
    hdr.BackgroundTransparency = 1
    hdr.TextColor3    = Color3.fromRGB(200,200,215)
    hdr.Font          = Enum.Font.Gotham
    hdr.TextSize      = 12
    hdr.TextXAlignment= Enum.TextXAlignment.Left
    hdr.Text          = label .. ":  " .. getter()
    hdr.Parent        = row

    local track = Instance.new("Frame")
    track.Size            = UDim2.new(1,-20,0,6)
    track.Position        = UDim2.new(0,10,0,30)
    track.BackgroundColor3= Color3.fromRGB(40,40,52)
    track.BorderSizePixel = 0
    track.Parent          = row
    mkCorner(track,3)

    local fill = Instance.new("Frame")
    fill.Size            = UDim2.new((getter()-min)/(max-min),0,1,0)
    fill.BackgroundColor3= Color3.fromRGB(110,70,210)
    fill.BorderSizePixel = 0
    fill.Parent          = track
    mkCorner(fill,3)

    local dragging = false
    track.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging=true end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging=false end
    end)
    UIS.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local abs = track.AbsolutePosition; local sz = track.AbsoluteSize
        local frac = math.clamp((i.Position.X - abs.X) / sz.X, 0, 1)
        local val  = math.floor(min + frac*(max-min))
        setter(val)
        fill.Size  = UDim2.new(frac,0,1,0)
        hdr.Text   = label .. ":  " .. val
    end)
    return function()
        local frac = (getter()-min)/(max-min)
        fill.Size = UDim2.new(frac,0,1,0)
        hdr.Text  = label .. ":  " .. getter()
    end
end

local function mkButton(pane, label, action)
    local btn = Instance.new("TextButton")
    btn.Size            = UDim2.new(1,0,0,30)
    btn.BackgroundColor3= Color3.fromRGB(90,55,190)
    btn.TextColor3      = Color3.fromRGB(240,240,250)
    btn.Font            = Enum.Font.GothamBold
    btn.TextSize        = 13
    btn.Text            = label
    btn.BorderSizePixel = 0
    btn.LayoutOrder     = nextZ()
    btn.Parent          = pane
    mkCorner(btn,6)
    btn.MouseButton1Click:Connect(action)
    btn.MouseEnter:Connect(function() tween(btn,{BackgroundColor3=Color3.fromRGB(110,70,220)}) end)
    btn.MouseLeave:Connect(function() tween(btn,{BackgroundColor3=Color3.fromRGB(90,55,190)}) end)
    return btn
end

local function mkDropdown(pane, label, options, action)
    local wrap = Instance.new("Frame")
    wrap.Size            = UDim2.new(1,0,0,30)
    wrap.BackgroundColor3= Color3.fromRGB(26,26,34)
    wrap.BorderSizePixel = 0
    wrap.LayoutOrder     = nextZ()
    wrap.ClipsDescendants= false
    wrap.Parent          = pane
    mkCorner(wrap,6)

    local lbl = Instance.new("TextLabel")
    lbl.Size          = UDim2.new(0.5,0,1,0)
    lbl.Position      = UDim2.new(0,10,0,0)
    lbl.BackgroundTransparency=1
    lbl.TextColor3    = Color3.fromRGB(200,200,215)
    lbl.Font          = Enum.Font.Gotham
    lbl.TextSize      = 12
    lbl.TextXAlignment= Enum.TextXAlignment.Left
    lbl.Text          = label
    lbl.Parent        = wrap

    local sel = Instance.new("TextButton")
    sel.Size            = UDim2.new(0.48,0,0,24)
    sel.Position        = UDim2.new(0.51,0,0.5,-12)
    sel.BackgroundColor3= Color3.fromRGB(38,38,50)
    sel.TextColor3      = Color3.fromRGB(180,180,200)
    sel.Font            = Enum.Font.Gotham
    sel.TextSize        = 12
    sel.Text            = options[1] or "—"
    sel.BorderSizePixel = 0
    sel.ClipsDescendants= false
    sel.Parent          = wrap
    mkCorner(sel,5)

    local menu = Instance.new("Frame")
    menu.Size            = UDim2.new(1,0,0,#options*26+4)
    menu.Position        = UDim2.new(0,0,1,2)
    menu.BackgroundColor3= Color3.fromRGB(32,32,44)
    menu.BorderSizePixel = 0
    menu.Visible         = false
    menu.ZIndex          = 20
    menu.Parent          = wrap
    mkCorner(menu,6)
    mkStroke(menu,Color3.fromRGB(70,55,120),1)
    local mLayout = Instance.new("UIListLayout"); mLayout.Parent=menu
    local mPad    = Instance.new("UIPadding")
    mPad.PaddingLeft=UDim.new(0,4); mPad.PaddingRight=UDim.new(0,4)
    mPad.PaddingTop=UDim.new(0,2); mPad.Parent=menu

    local function close() menu.Visible=false end

    for _, opt in ipairs(options) do
        local item = Instance.new("TextButton")
        item.Size            = UDim2.new(1,0,0,22)
        item.BackgroundTransparency=1
        item.TextColor3      = Color3.fromRGB(190,190,210)
        item.Font            = Enum.Font.Gotham
        item.TextSize        = 12
        item.Text            = opt
        item.ZIndex          = 21
        item.Parent          = menu
        item.MouseButton1Click:Connect(function()
            sel.Text = opt
            action(opt)
            close()
        end)
        item.MouseEnter:Connect(function() item.BackgroundTransparency=0.7 end)
        item.MouseLeave:Connect(function() item.BackgroundTransparency=1 end)
    end

    sel.MouseButton1Click:Connect(function()
        menu.Visible = not menu.Visible
    end)

    return sel, close
end

-- ══════════════════════════════════════════════════════════════════════
-- BUILD TABS
-- ══════════════════════════════════════════════════════════════════════

-- ── MOVEMENT TAB ──────────────────────────────────────────────────────
mkSection(movePane,"flight")
mkToggle(movePane,"Fly",
    function() return cfg.fly.enabled end,
    function(v) setFly(v) end)
mkSlider(movePane,"Fly Speed",10,200,
    function() return cfg.fly.speed end,
    function(v) cfg.fly.speed=v end)

mkSection(movePane,"movement")
mkToggle(movePane,"Speed Hack",
    function() return cfg.speed.enabled end,
    function(v) cfg.speed.enabled=v; applyMovement() end)
mkSlider(movePane,"Walk Speed",16,150,
    function() return cfg.speed.value end,
    function(v) cfg.speed.value=v end)

mkToggle(movePane,"Jump Hack",
    function() return cfg.jump.enabled end,
    function(v) cfg.jump.enabled=v; applyMovement() end)
mkSlider(movePane,"Jump Power",50,500,
    function() return cfg.jump.value end,
    function(v) cfg.jump.value=v end)

mkSection(movePane,"misc movement")
mkToggle(movePane,"Noclip",
    function() return cfg.noclip.enabled end,
    function(v) cfg.noclip.enabled=v end)
mkToggle(movePane,"Infinite Jump",
    function() return cfg.inf_jump.enabled end,
    function(v) cfg.inf_jump.enabled=v end)

mkSection(movePane,"position")
mkButton(movePane,"Save Position", function()
    local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    if root then savedPos = root.Position end
end)
mkButton(movePane,"Return to Saved", function()
    if savedPos then teleportTo(savedPos) end
end)

-- ── TELEPORT TAB ──────────────────────────────────────────────────────
mkSection(tpPane,"landmarks")
for _, loc in ipairs(LOCATIONS) do
    mkButton(tpPane, "⟶  " .. loc.name, function()
        teleportTo(loc.pos)
    end)
end

mkSection(tpPane,"player teleport")
local playerNames = {}
local function refreshPlayerList()
    playerNames = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then table.insert(playerNames, p.DisplayName) end
    end
    if #playerNames == 0 then playerNames = {"(no players)"} end
end
refreshPlayerList()

local tpSel
local function doTpToPlayer(name)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.DisplayName == name then teleportToPlayer(p); return end
    end
end

do
    local opts = playerNames
    tpSel = mkButton(tpPane,"Refresh Player List", function()
        refreshPlayerList()
    end)
    mkDropdown(tpPane,"Teleport to:", playerNames, doTpToPlayer)
end

mkSection(tpPane,"bring player")
mkDropdown(tpPane,"Bring to me:", playerNames, function(name)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.DisplayName == name then
            local myRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            local theirRoot = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if myRoot and theirRoot then
                theirRoot.CFrame = myRoot.CFrame * CFrame.new(3,0,0)
            end
        end
    end
end)

-- ── ESP TAB ───────────────────────────────────────────────────────────
mkSection(espPane,"player esp")
mkToggle(espPane,"Enable ESP",
    function() return cfg.esp.enabled end,
    function(v)
        cfg.esp.enabled=v
        -- rebuild on toggle so chars without highlight get it
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= lp then
                if not espPool[plr] then buildESP(plr)
                else
                    local e = espPool[plr]
                    if e.highlight then e.highlight.Enabled=v end
                    if e.billboard then e.billboard.Enabled=v end
                end
            end
        end
        refreshESP()
    end)

mkSection(espPane,"avatar")
mkDropdown(espPane,"Copy outfit:", playerNames, function(name)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.DisplayName == name then copyAvatar(p) end
    end
end)

-- ── MISC TAB ──────────────────────────────────────────────────────────
mkSection(miscPane,"survival")
mkToggle(miscPane,"God Mode",
    function() return cfg.god.enabled end,
    function(v) setGod(v) end)

mkSection(miscPane,"comfort")
mkToggle(miscPane,"Anti-AFK",
    function() return cfg.afk.enabled end,
    function(v) setAFK(v) end)
mkToggle(miscPane,"Fullbright",
    function() return cfg.fullbright.enabled end,
    function(v) setFullbright(v) end)

mkSection(miscPane,"server")
mkButton(miscPane,"Rejoin Server", function()
    local TS = game:GetService("TeleportService")
    TS:Teleport(game.PlaceId, lp)
end)
mkButton(miscPane,"Hop to New Server", function()
    local TS  = game:GetService("TeleportService")
    local res = TS:GetPlayerPlaceInstanceAsync(lp.UserId)
    TS:TeleportToPlaceInstance(game.PlaceId, res, lp)
end)

mkSection(miscPane,"debug")
mkButton(miscPane,"Print All Remotes", function()
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            print("[nexus remote] " .. v:GetFullName())
        end
    end
    for _, v in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
        if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
            print("[nexus remote] " .. v:GetFullName())
        end
    end
end)

-- open on Move tab by default
switchTab("Move")

-- ── notification helper ───────────────────────────────────────────────
local function notify(title, body)
    pcall(function()
        StarterGui:SetCore("SendNotification",{
            Title   = title,
            Text    = body,
            Duration= 3,
        })
    end)
end

-- ── cleanup on gui destroy ────────────────────────────────────────────
ScreenGui.AncestryChanged:Connect(function()
    if not ScreenGui.Parent then
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        destroyFly()
        setGod(false)
        setAFK(false)
        setFullbright(false)
        for plr in pairs(espPool) do destroyESP(plr) end
        local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed=16; hum.JumpPower=50; hum.PlatformStand=false end
    end
end)

notify("nexus — berry avenue", "loaded. open the window to get started.")
print("[nexus] berry avenue script loaded")
