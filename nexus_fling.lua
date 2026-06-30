-- // ═══════════════════════════════════════════════════════
-- //   NEXUS FLING  |  Standalone Universal Fling Tool
-- //   RightAlt = toggle UI
-- // ═══════════════════════════════════════════════════════
--
--  Method guide:
--
--  Self     — applies extreme BodyVelocity to OUR OWN character toward the
--             target, then welds our HRP to theirs so physics authority
--             transfers.  our character physics always replicates (we own it).
--             the weld merges assemblies so our velocity carries them even
--             with player collision off.
--
--  Platform — creates a Part in the target's lower body and launches it.
--             critically: raycasts under the target to find the floor's
--             CollisionGroup (player-world collision is always on), then sets
--             our Part to that same group.  the Part hits them the same way
--             the floor does — bypasses the player-player off setting.
--             fires 3 rapid shots.
--
--  Spin     — creates a Part, WeldConstraints it to the target's HRP.
--             extreme angular + linear velocity launches them.
--
--  All      — fires every method simultaneously.  use this.

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local lp = Players.LocalPlayer

-- // ══════════════════ STATE ═════════════════════════════ //

local selectedPlayer = nil
local flingMethod    = "All"   -- "Self" | "Platform" | "Spin" | "All"
local strength       = 800
local loopActive     = false
local flingCooldown  = false

-- // ══════════════════ COLORS ════════════════════════════ //

local BG0   = Color3.fromRGB(9,9,13)
local BG1   = Color3.fromRGB(14,14,20)
local BG2   = Color3.fromRGB(19,19,27)
local BG3   = Color3.fromRGB(26,26,38)
local TABON = Color3.fromRGB(110,65,235)
local TXA   = Color3.fromRGB(225,225,248)
local TXB   = Color3.fromRGB(95,95,125)
local TXC   = Color3.fromRGB(145,105,255)
local WHITE = Color3.new(1,1,1)
local RED   = Color3.fromRGB(220,60,60)
local GREEN = Color3.fromRGB(60,220,100)
local GOLD  = Color3.fromRGB(255,210,50)
local SEL   = Color3.fromRGB(55,30,110)

-- // ═══════════════════ FLING CORE ═══════════════════════ //

local function doFling(target)
    if flingCooldown then return end
    local char = target.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not (root and hum and hum.Health > 0) then return end
    flingCooldown = true

    local debris = game:GetService("Debris")
    local myChar = lp.Character
    local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myHum  = myChar and myChar:FindFirstChildOfClass("Humanoid")

    local dir
    if myHRP then
        local d = root.Position - myHRP.Position
        dir = Vector3.new(d.X, 0, d.Z)
        if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
        dir = dir.Unit
    else
        dir = Vector3.new(math.random()*2-1, 0, math.random()*2-1).Unit
    end

    local fv = Vector3.new(dir.X * strength, strength * 1.5, dir.Z * strength)

    -- ── Self ──────────────────────────────────────────────
    -- uses OUR OWN character physics — always replicates because we own it.
    -- weld our HRP to the target's HRP: because we own Part0 (our HRP),
    -- we become physics authority for the merged assembly.  BodyVelocity on
    -- us then carries them with us through the weld — no collision needed.
    -- this is the most FE-reliable method.
    if flingMethod == "Self" or flingMethod == "All" then
        task.spawn(function()
            if not (myHRP and myHum) then return end

            myHum.PlatformStand = true

            local wc    = Instance.new("WeldConstraint")
            wc.Part0    = myHRP   -- we own this part → we own the merged assembly
            wc.Part1    = root    -- their HRP joins our assembly
            wc.Parent   = myHRP  -- parented to our character, replicates with us

            local bv    = Instance.new("BodyVelocity")
            bv.Velocity = fv * 2
            bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
            bv.P        = 1e9
            bv.Parent   = myHRP

            local bav   = Instance.new("BodyAngularVelocity")
            bav.AngularVelocity = Vector3.new(0, 1e5, 0)
            bav.MaxTorque       = Vector3.new(1e9, 1e9, 1e9)
            bav.P               = 1e9
            bav.Parent          = myHRP

            task.wait(0.12)

            pcall(function() wc:Destroy()  end)
            pcall(function() bv:Destroy()  end)
            pcall(function() bav:Destroy() end)
            task.wait(0.05)
            myHum.PlatformStand = false
        end)
    end

    -- ── Platform ──────────────────────────────────────────
    -- raycasts under the target to find the floor's CollisionGroup.
    -- player-world collision is always on (they'd fall through otherwise),
    -- so the floor group definitely interacts with player characters.
    -- setting our Part to that same group bypasses the player-player off
    -- setting.  Part placed inside the lower body so physics must resolve
    -- the overlap by pushing the character in fv direction.
    -- 3 rapid shots to increase hit probability as target moves.
    if flingMethod == "Platform" or flingMethod == "All" then
        task.spawn(function()
            local floorGroup = "Default"
            local rp = RaycastParams.new()
            rp.FilterType = Enum.RaycastFilterType.Exclude
            rp.FilterDescendantsInstances = { char, myChar or char }
            local hit = workspace:Raycast(root.Position, Vector3.new(0, -8, 0), rp)
            if hit and hit.Instance and hit.Instance:IsA("BasePart") then
                floorGroup = hit.Instance.CollisionGroup
            end
            print("[NEXUS FLING] platform: floor group =", floorGroup,
                  "| target group =", root.CollisionGroup)

            for shot = 0, 2 do
                task.delay(shot * 0.07, function()
                    if not root.Parent then return end
                    local pad            = Instance.new("Part")
                    pad.Size             = Vector3.new(6, 6, 6)
                    pad.CFrame           = CFrame.new(root.Position - Vector3.new(0, 1.5, 0))
                    pad.Anchored         = false
                    pad.CanCollide       = true
                    pad.CanTouch         = false
                    pad.Transparency     = 1
                    pad.Material         = Enum.Material.SmoothPlastic
                    pad.CollisionGroup   = floorGroup
                    pad.Parent           = workspace
                    local bv             = Instance.new("BodyVelocity")
                    bv.Velocity          = fv
                    bv.MaxForce          = Vector3.new(1e9, 1e9, 1e9)
                    bv.P                 = 1e9
                    bv.Parent            = pad
                    debris:AddItem(pad, 3)
                end)
            end
        end)
    end

    -- ── Spin ──────────────────────────────────────────────
    -- WeldConstraint from our workspace Part to their HRP.
    -- we own Part0 → physics authority over the merged assembly.
    -- extreme angular + linear velocity launches them.
    if flingMethod == "Spin" or flingMethod == "All" then
        task.spawn(function()
            local sp        = Instance.new("Part")
            sp.Size         = Vector3.new(0.1, 0.1, 0.1)
            sp.CFrame       = root.CFrame
            sp.Anchored     = false
            sp.CanCollide   = false
            sp.Transparency = 1
            sp.Parent       = workspace

            local wc        = Instance.new("WeldConstraint")
            wc.Part0        = sp
            wc.Part1        = root
            wc.Parent       = sp

            local bav       = Instance.new("BodyAngularVelocity")
            bav.AngularVelocity = Vector3.new(0, 1e6, 0)
            bav.MaxTorque       = Vector3.new(1e9, 1e9, 1e9)
            bav.P               = 1e9
            bav.Parent          = sp

            local bvs       = Instance.new("BodyVelocity")
            bvs.Velocity    = Vector3.new(dir.X*strength*3, strength*2, dir.Z*strength*3)
            bvs.MaxForce    = Vector3.new(1e9, 1e9, 1e9)
            bvs.P           = 1e9
            bvs.Parent      = sp

            task.wait(0.1)
            pcall(function() wc:Destroy() end)
            debris:AddItem(sp, 2)
        end)
    end

    -- suppress target humanoid state resistance regardless of method
    pcall(function()
        hum.PlatformStand = true
        hum.Sit           = true
        task.delay(2, function()
            pcall(function() hum.PlatformStand = false end)
            pcall(function() hum.Sit           = false end)
        end)
    end)

    task.delay(0.35, function() flingCooldown = false end)
end

-- // ════════════════════ GUI ═════════════════════════════ //

local GUI_ROOT = (function()
    local ok, r = pcall(gethui); return ok and r or game:GetService("CoreGui")
end)()

local SG = Instance.new("ScreenGui")
SG.Name           = "NexusFlingUI"
SG.ResetOnSpawn   = false
SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SG.Parent         = GUI_ROOT

-- window

local WIN = Instance.new("Frame")
WIN.Size             = UDim2.new(0, 320, 0, 570)
WIN.Position         = UDim2.new(0.5,-160, 0.5,-285)
WIN.BackgroundColor3 = BG0
WIN.BorderSizePixel  = 0
WIN.Active           = true
WIN.Parent           = SG
Instance.new("UICorner", WIN).CornerRadius = UDim.new(0,10)
local WS = Instance.new("UIStroke", WIN)
WS.Color = Color3.fromRGB(110,65,235); WS.Thickness = 1; WS.Transparency = 0.5

local SHD = Instance.new("Frame", WIN)
SHD.Size = UDim2.new(1,22,1,22); SHD.Position = UDim2.new(0,-11,0,-11)
SHD.BackgroundColor3 = Color3.new(0,0,0); SHD.BackgroundTransparency = 0.5
SHD.BorderSizePixel  = 0; SHD.ZIndex = WIN.ZIndex - 1
Instance.new("UICorner", SHD).CornerRadius = UDim.new(0,15)

-- // TITLE BAR ───────────────────────────────────────────── //

local TB = Instance.new("Frame", WIN)
TB.Size = UDim2.new(1,0,0,46); TB.BackgroundColor3 = BG1; TB.BorderSizePixel = 0
Instance.new("UICorner", TB).CornerRadius = UDim.new(0,10)
local TBf = Instance.new("Frame", TB)
TBf.Size = UDim2.new(1,0,0,10); TBf.Position = UDim2.new(0,0,1,-10)
TBf.BackgroundColor3 = BG1; TBf.BorderSizePixel = 0

local function mkL(p, t, fn, s, c, xa, pos, sz)
    local l = Instance.new("TextLabel", p)
    l.Text = t; l.Font = fn; l.TextSize = s; l.TextColor3 = c
    l.BackgroundTransparency = 1
    l.TextXAlignment = xa  or Enum.TextXAlignment.Center
    l.Position       = pos or UDim2.new(0,0,0,0)
    l.Size           = sz  or UDim2.new(1,0,1,0)
    return l
end

mkL(TB,"NEXUS FLING",Enum.Font.GothamBold,15,TXA,Enum.TextXAlignment.Left,
    UDim2.new(0,14,0,6), UDim2.new(0,185,0,20))
mkL(TB,"universal fling tool",Enum.Font.Gotham,10,TXB,Enum.TextXAlignment.Left,
    UDim2.new(0,15,0,27), UDim2.new(0,185,0,14))

local adot = Instance.new("Frame", TB)
adot.Size = UDim2.new(0,6,0,6); adot.Position = UDim2.new(0,97,0,12)
adot.BackgroundColor3 = TXC; adot.BorderSizePixel = 0
Instance.new("UICorner", adot).CornerRadius = UDim.new(1,0)

local CLO = Instance.new("TextButton", TB)
CLO.Text = "✕"; CLO.Font = Enum.Font.GothamBold; CLO.TextSize = 13
CLO.TextColor3 = TXB; CLO.BackgroundTransparency = 1
CLO.Size = UDim2.new(0,40,0,46); CLO.Position = UDim2.new(1,-40,0,0)
CLO.MouseButton1Click:Connect(function() WIN.Visible = not WIN.Visible end)
CLO.MouseEnter:Connect(function() CLO.TextColor3 = RED end)
CLO.MouseLeave:Connect(function() CLO.TextColor3 = TXB end)

-- // SCROLLABLE BODY ─────────────────────────────────────── //

local SCR = Instance.new("ScrollingFrame", WIN)
SCR.Size = UDim2.new(1,0,1,-54); SCR.Position = UDim2.new(0,0,0,54)
SCR.BackgroundTransparency = 1; SCR.ScrollBarThickness = 2
SCR.ScrollBarImageColor3 = Color3.fromRGB(80,50,160)
SCR.BorderSizePixel = 0
SCR.CanvasSize = UDim2.new(0,0,0,0); SCR.AutomaticCanvasSize = Enum.AutomaticSize.Y
local SL = Instance.new("UIListLayout", SCR)
SL.SortOrder = Enum.SortOrder.LayoutOrder; SL.Padding = UDim.new(0,5)
local SP = Instance.new("UIPadding", SCR)
SP.PaddingLeft = UDim.new(0,9); SP.PaddingRight = UDim.new(0,9)
SP.PaddingTop  = UDim.new(0,10); SP.PaddingBottom = UDim.new(0,10)

local function mkSec(label, ord)
    local f = Instance.new("Frame", SCR)
    f.Size = UDim2.new(1,0,0,20); f.BackgroundTransparency = 1; f.LayoutOrder = ord
    mkL(f, label, Enum.Font.GothamBold, 9, TXC, Enum.TextXAlignment.Left)
    local ln = Instance.new("Frame", f)
    ln.Size = UDim2.new(1,0,0,1); ln.Position = UDim2.new(0,0,1,-1)
    ln.BackgroundColor3 = Color3.fromRGB(26,26,42); ln.BorderSizePixel = 0
end

-- // ── PLAYERS ───────────────────────────────────────────── //

mkSec("PLAYERS", 0)

local pRow = Instance.new("Frame", SCR)
pRow.Size = UDim2.new(1,0,0,24); pRow.BackgroundTransparency = 1; pRow.LayoutOrder = 1

mkL(pRow,"click a player to select them",Enum.Font.Gotham,9,TXB,
    Enum.TextXAlignment.Left, UDim2.new(0,0,0,0), UDim2.new(1,-78,1,0))

local refreshBtn = Instance.new("TextButton", pRow)
refreshBtn.Text = "↺ refresh"; refreshBtn.Font = Enum.Font.GothamSemibold; refreshBtn.TextSize = 9
refreshBtn.TextColor3 = TXC; refreshBtn.BackgroundColor3 = BG3
refreshBtn.Size = UDim2.new(0,72,0,22); refreshBtn.Position = UDim2.new(1,-72,0,1)
refreshBtn.BorderSizePixel = 0
Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0,5)

local listScr = Instance.new("ScrollingFrame", SCR)
listScr.Size = UDim2.new(1,0,0,158); listScr.LayoutOrder = 2
listScr.BackgroundColor3 = BG2; listScr.BorderSizePixel = 0
listScr.ScrollBarThickness = 2; listScr.ScrollBarImageColor3 = Color3.fromRGB(80,50,160)
listScr.CanvasSize = UDim2.new(0,0,0,0); listScr.AutomaticCanvasSize = Enum.AutomaticSize.Y
Instance.new("UICorner", listScr).CornerRadius = UDim.new(0,7)
local ll = Instance.new("UIListLayout", listScr)
ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Padding = UDim.new(0,2)
local lpad = Instance.new("UIPadding", listScr)
lpad.PaddingLeft = UDim.new(0,4); lpad.PaddingRight  = UDim.new(0,4)
lpad.PaddingTop  = UDim.new(0,4); lpad.PaddingBottom = UDim.new(0,4)

local playerEntries = {}

local function buildList()
    for _, e in ipairs(playerEntries) do e.btn:Destroy() end
    playerEntries = {}
    local count = 0

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == lp then continue end
        local char  = plr.Character
        local hum   = char and char:FindFirstChildOfClass("Humanoid")
        local alive = hum and hum.Health > 0
        local isSel = selectedPlayer == plr

        local btn = Instance.new("TextButton", listScr)
        btn.Size             = UDim2.new(1,0,0,34)
        btn.BackgroundColor3 = isSel and SEL or BG3
        btn.BorderSizePixel  = 0
        btn.LayoutOrder      = count
        btn.Font             = Enum.Font.GothamSemibold
        btn.TextSize         = 12
        btn.TextColor3       = isSel and GOLD or (alive and TXA or TXB)
        btn.TextXAlignment   = Enum.TextXAlignment.Left
        btn.Text             = "   " .. plr.DisplayName .. (not alive and "  [dead]" or "")
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)

        local dot = Instance.new("Frame", btn)
        dot.Size = UDim2.new(0,7,0,7); dot.Position = UDim2.new(1,-16,0.5,-3.5)
        dot.BackgroundColor3 = alive and GREEN or RED; dot.BorderSizePixel = 0
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1,0)

        btn.MouseButton1Click:Connect(function()
            selectedPlayer = plr
            for _, e in ipairs(playerEntries) do
                local me = e.player == plr
                TweenService:Create(e.btn, TweenInfo.new(0.1), {
                    BackgroundColor3 = me and SEL or BG3,
                }):Play()
                e.btn.TextColor3 = me and GOLD or TXA
            end
        end)

        table.insert(playerEntries, { player = plr, btn = btn })
        count = count + 1
    end

    if count == 0 then
        local empty = Instance.new("TextLabel", listScr)
        empty.Size = UDim2.new(1,0,0,36); empty.BackgroundTransparency = 1
        empty.Font = Enum.Font.Gotham; empty.TextSize = 10
        empty.TextColor3 = TXB; empty.Text = "no other players in server"
        table.insert(playerEntries, { player = nil, btn = empty })
    end
end

buildList()
refreshBtn.MouseButton1Click:Connect(buildList)
Players.PlayerAdded:Connect(function() task.wait(1); buildList() end)
Players.PlayerRemoving:Connect(function(plr)
    if selectedPlayer == plr then selectedPlayer = nil end
    task.wait(0.1); buildList()
end)

-- // ── METHOD ────────────────────────────────────────────── //

mkSec("METHOD", 3)

local mRow = Instance.new("Frame", SCR)
mRow.Size = UDim2.new(1,0,0,30); mRow.BackgroundTransparency = 1; mRow.LayoutOrder = 4
local mLL = Instance.new("UIListLayout", mRow)
mLL.FillDirection = Enum.FillDirection.Horizontal; mLL.Padding = UDim.new(0,3)
mLL.SortOrder = Enum.SortOrder.LayoutOrder

-- 4 buttons: (302px inner - 3 gaps × 3px) / 4 = 72px each
local BW = math.floor((302 - 9) / 4)
local methodMap = {}

for i, m in ipairs({"Self","Platform","Spin","All"}) do
    local active = flingMethod == m
    local mb = Instance.new("TextButton", mRow)
    mb.Text = m; mb.Font = Enum.Font.GothamSemibold; mb.TextSize = 10
    mb.TextColor3 = active and TXA or TXB
    mb.BackgroundColor3 = active and TABON or BG3
    mb.Size = UDim2.new(0,BW,1,0); mb.BorderSizePixel = 0; mb.LayoutOrder = i
    Instance.new("UICorner", mb).CornerRadius = UDim.new(0,6)
    methodMap[m] = mb
    mb.MouseButton1Click:Connect(function()
        flingMethod = m
        for name, b in pairs(methodMap) do
            TweenService:Create(b, TweenInfo.new(0.1), {
                BackgroundColor3 = name==m and TABON or BG3,
                TextColor3       = name==m and TXA   or TXB,
            }):Play()
        end
    end)
end

local mHint = Instance.new("Frame", SCR)
mHint.Size = UDim2.new(1,0,0,18); mHint.BackgroundTransparency = 1; mHint.LayoutOrder = 5
mkL(mHint,
    "Self: weld our HRP to theirs (FE-safe)  ·  Platform: floor-group collision ×3  ·  Spin: weld+spin",
    Enum.Font.Gotham, 8, TXB, Enum.TextXAlignment.Center)

-- // ── STRENGTH ──────────────────────────────────────────── //

mkSec("TUNING", 6)

local sRow = Instance.new("Frame", SCR)
sRow.Size = UDim2.new(1,0,0,52); sRow.BackgroundColor3 = BG2
sRow.BorderSizePixel = 0; sRow.LayoutOrder = 7
Instance.new("UICorner", sRow).CornerRadius = UDim.new(0,7)
mkL(sRow,"Strength",Enum.Font.GothamSemibold,12,TXA,Enum.TextXAlignment.Left,
    UDim2.new(0,12,0,7), UDim2.new(0.65,0,0,18))

local sVB = Instance.new("Frame", sRow)
sVB.Size = UDim2.new(0,52,0,20); sVB.Position = UDim2.new(1,-62,0,7)
sVB.BackgroundColor3 = BG3; sVB.BorderSizePixel = 0
Instance.new("UICorner", sVB).CornerRadius = UDim.new(0,5)
local sVL = mkL(sVB, tostring(strength), Enum.Font.GothamBold, 11, TXC)

local sTrk = Instance.new("Frame", sRow)
sTrk.Size = UDim2.new(1,-24,0,4); sTrk.Position = UDim2.new(0,12,1,-14)
sTrk.BackgroundColor3 = Color3.fromRGB(26,26,44); sTrk.BorderSizePixel = 0
Instance.new("UICorner", sTrk).CornerRadius = UDim.new(1,0)

local sMin, sMax = 100, 2000
local sPct0 = (strength - sMin) / (sMax - sMin)

local sFill = Instance.new("Frame", sTrk)
sFill.BackgroundColor3 = TABON; sFill.BorderSizePixel = 0
sFill.Size = UDim2.new(sPct0, 0, 1, 0)
Instance.new("UICorner", sFill).CornerRadius = UDim.new(1,0)

local sTh = Instance.new("Frame", sTrk)
sTh.Size = UDim2.new(0,12,0,12); sTh.Position = UDim2.new(sPct0,-6,0.5,-6)
sTh.BackgroundColor3 = WHITE; sTh.BorderSizePixel = 0
Instance.new("UICorner", sTh).CornerRadius = UDim.new(1,0)

local sDrag = false
local sHit  = Instance.new("TextButton", sTrk)
sHit.Text = ""; sHit.BackgroundTransparency = 1
sHit.Size = UDim2.new(1,0,0,24); sHit.Position = UDim2.new(0,0,0,-10)

local function applyStr(mx2)
    local a = sTrk.AbsolutePosition; local s = sTrk.AbsoluteSize
    local pct = math.clamp((mx2 - a.X) / s.X, 0, 1)
    strength = math.floor(sMin + (sMax - sMin) * pct)
    sFill.Size = UDim2.new(pct,0,1,0); sTh.Position = UDim2.new(pct,-6,0.5,-6)
    sVL.Text = tostring(strength)
end

sHit.MouseButton1Down:Connect(function() sDrag=true; applyStr(UIS:GetMouseLocation().X) end)
UIS.InputChanged:Connect(function(i)
    if sDrag and i.UserInputType == Enum.UserInputType.MouseMovement then
        applyStr(UIS:GetMouseLocation().X)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then sDrag = false end
end)

-- // ── ACTION ────────────────────────────────────────────── //

mkSec("ACTION", 8)

local aRow = Instance.new("Frame", SCR)
aRow.Size = UDim2.new(1,0,0,42); aRow.BackgroundTransparency = 1; aRow.LayoutOrder = 9
local aLL = Instance.new("UIListLayout", aRow)
aLL.FillDirection = Enum.FillDirection.Horizontal; aLL.Padding = UDim.new(0,6)
aLL.SortOrder = Enum.SortOrder.LayoutOrder

-- FLING button
local fBtn = Instance.new("TextButton", aRow)
fBtn.Text = "  ⚡  FLING"; fBtn.Font = Enum.Font.GothamBold; fBtn.TextSize = 13
fBtn.TextColor3 = WHITE; fBtn.BackgroundColor3 = Color3.fromRGB(85,40,195)
fBtn.Size = UDim2.new(0.5,-3,1,0); fBtn.BorderSizePixel = 0; fBtn.LayoutOrder = 1
Instance.new("UICorner", fBtn).CornerRadius = UDim.new(0,8)
Instance.new("UIStroke", fBtn).Color = Color3.fromRGB(140,80,255)
fBtn.MouseEnter:Connect(function()
    TweenService:Create(fBtn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(115,60,230)}):Play()
end)
fBtn.MouseLeave:Connect(function()
    TweenService:Create(fBtn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(85,40,195)}):Play()
end)

-- LOOP button
local loopBtn = Instance.new("TextButton", aRow)
loopBtn.Text = "⟳  LOOP  ○"; loopBtn.Font = Enum.Font.GothamBold; loopBtn.TextSize = 11
loopBtn.TextColor3 = TXB; loopBtn.BackgroundColor3 = BG3
loopBtn.Size = UDim2.new(0.5,-3,1,0); loopBtn.BorderSizePixel = 0; loopBtn.LayoutOrder = 2
Instance.new("UICorner", loopBtn).CornerRadius = UDim.new(0,8)
local lStroke = Instance.new("UIStroke", loopBtn)
lStroke.Color = Color3.fromRGB(60,40,100)

local function tryFling()
    if not selectedPlayer then
        print("[NEXUS FLING] no target selected")
        return
    end
    doFling(selectedPlayer)
end

fBtn.MouseButton1Click:Connect(tryFling)

local function setLoop(on)
    loopActive = on
    if on then
        loopBtn.Text = "⟳  LOOP  ●"
        TweenService:Create(loopBtn,TweenInfo.new(0.1),{
            BackgroundColor3 = Color3.fromRGB(18,50,20), TextColor3 = GREEN,
        }):Play()
        TweenService:Create(lStroke,TweenInfo.new(0.1),{Color=Color3.fromRGB(40,180,70)}):Play()
        task.spawn(function()
            while loopActive do
                if selectedPlayer then pcall(tryFling) end
                task.wait(0.4)
            end
        end)
    else
        loopBtn.Text = "⟳  LOOP  ○"
        TweenService:Create(loopBtn,TweenInfo.new(0.1),{
            BackgroundColor3 = BG3, TextColor3 = TXB,
        }):Play()
        TweenService:Create(lStroke,TweenInfo.new(0.1),{Color=Color3.fromRGB(60,40,100)}):Play()
    end
end

loopBtn.MouseButton1Click:Connect(function() setLoop(not loopActive) end)

-- // ── STATUS ────────────────────────────────────────────── //

local statRow = Instance.new("Frame", SCR)
statRow.Size = UDim2.new(1,0,0,26); statRow.BackgroundColor3 = BG2
statRow.BorderSizePixel = 0; statRow.LayoutOrder = 10
Instance.new("UICorner", statRow).CornerRadius = UDim.new(0,6)
local statLbl = mkL(statRow,"ready  ·  no target selected",Enum.Font.Gotham,9,TXB)

RunService.RenderStepped:Connect(function()
    if not selectedPlayer then
        statLbl.Text = "ready  ·  no target selected"; statLbl.TextColor3 = TXB; return
    end
    local char = selectedPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        statLbl.Text = "⚠  " .. selectedPlayer.DisplayName .. "  ·  dead / respawning"
        statLbl.TextColor3 = RED
    elseif loopActive then
        statLbl.Text = "⟳  looping  ·  " .. selectedPlayer.DisplayName
        statLbl.TextColor3 = GREEN
    else
        statLbl.Text = "target: " .. selectedPlayer.DisplayName .. "  ·  ready"
        statLbl.TextColor3 = TXC
    end
end)

-- // ════════════════════ DRAG ════════════════════════════ //

local drag, ds, wp = false, nil, nil
TB.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        drag=true; ds=i.Position; wp=WIN.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - ds
        WIN.Position = UDim2.new(wp.X.Scale, wp.X.Offset+d.X, wp.Y.Scale, wp.Y.Offset+d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
end)

UIS.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if i.KeyCode == Enum.KeyCode.RightAlt then WIN.Visible = not WIN.Visible end
end)

print("[NEXUS FLING] loaded  ·  RightAlt = toggle UI")
