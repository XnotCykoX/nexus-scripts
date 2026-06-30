-- auth menu - potassium

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local function w2s(worldPos)
    local s = Camera:WorldToScreenPoint(worldPos)
    return Vector2.new(s.X, s.Y), s.Z > 0
end

local function notify(text, title, duration)
    print("[AuthMenu] " .. tostring(title) .. ": " .. tostring(text))
end

-- config
local AIM_SMOOTH  = 0.18
local AIM_PREDICT = 0.12
local AIM_FOV     = 200
local FLY_SPEED   = 50
local HITBOX_SIZE = 10

-- colors
local C = {}
C.shadow = Color3.fromRGB(0,   0,   0)
C.panel  = Color3.fromRGB(22,  23,  30)
C.border = Color3.fromRGB(58,  62,  80)
C.accent = Color3.fromRGB(130, 160, 255)
C.text   = Color3.fromRGB(236, 239, 248)
C.sub    = Color3.fromRGB(138, 142, 158)
C.on     = Color3.fromRGB(95,  225, 140)
C.off    = Color3.fromRGB(110, 114, 130)
C.box    = Color3.fromRGB(255, 70,  70)
C.line   = Color3.fromRGB(255, 255, 255)
C.yellow = Color3.fromRGB(255, 210, 90)
C.fov    = Color3.fromRGB(255, 255, 255)

-- feature state
local state = {}
state.ESP       = false
state.Tracers   = false
state.Aim       = false
state.Weapons   = false
state.Hitbox    = false
state.TeamCheck = false
state.Fly       = false

local tabs      = { "Visual", "Combat", "Move", "Bind" }
local activeTab = 1

local features = {
    { name = "ESP",         field = "ESP",       key = Enum.KeyCode.One,   tab = "Visual" },
    { name = "Tracers",     field = "Tracers",   key = Enum.KeyCode.Two,   tab = "Visual" },
    { name = "Aim Assist",  field = "Aim",       key = Enum.KeyCode.Three, tab = "Combat" },
    { name = "Weapon Mods", field = "Weapons",   key = Enum.KeyCode.Four,  tab = "Combat" },
    { name = "Hitbox",      field = "Hitbox",    key = Enum.KeyCode.Five,  tab = "Combat" },
    { name = "Team Check",  field = "TeamCheck", key = Enum.KeyCode.Six,   tab = "Combat" },
    { name = "Fly",         field = "Fly",       key = nil,                tab = "Move"   },
}

local slotOf = {}
do
    local counts = {}
    for _, f in ipairs(features) do
        counts[f.tab] = (counts[f.tab] or 0) + 1
        slotOf[f] = counts[f.tab]
    end
end

local menuVisible  = true
local menuDirty    = true
local holdingAim   = false
local listeningFor = nil
local held         = {}
held.W    = false
held.A    = false
held.S    = false
held.D    = false
held.Up   = false
held.Down = false

local function setDirty()
    menuDirty = true
end

-- keybinds
local BINDABLE = {
    { Enum.KeyCode.C, "C" }, { Enum.KeyCode.V, "V" }, { Enum.KeyCode.X, "X" },
    { Enum.KeyCode.Z, "Z" }, { Enum.KeyCode.Q, "Q" }, { Enum.KeyCode.E, "E" },
    { Enum.KeyCode.R, "R" }, { Enum.KeyCode.F, "F" }, { Enum.KeyCode.G, "G" },
    { Enum.KeyCode.H, "H" }, { Enum.KeyCode.T, "T" }, { Enum.KeyCode.B, "B" },
    { Enum.KeyCode.Y, "Y" }, { Enum.KeyCode.N, "N" },
}

local aimKey     = Enum.KeyCode.C
local aimKeyName = "C"
local flyKey     = Enum.KeyCode.F
local flyKeyName = "F"

local function findBindable(kc)
    for _, e in ipairs(BINDABLE) do
        if kc == e[1] then
            return e[1], e[2]
        end
    end
    return nil, nil
end

local bindRows = {
    { id = "aim", label = "Aim Key", getName = function() return aimKeyName end },
    { id = "fly", label = "Fly Key", getName = function() return flyKeyName end },
}

-- layout constants
local PX = 50
local PY = 120
local PW = 290
local HEAD_H = 42
local TAB_H  = 32
local ROW_H  = 30
local FOOT_H = 24
local PAD    = 10
local CONTENT_ROWS = 4
local PH   = HEAD_H + TAB_H + (CONTENT_ROWS * ROW_H) + FOOT_H + PAD
local tabW = PW / #tabs

local function tabRect(i)
    local x1 = PX + (i - 1) * tabW
    local y1 = PY + HEAD_H
    return x1, y1, x1 + tabW, y1 + TAB_H
end

local function rowRect(slot)
    local y1 = PY + HEAD_H + TAB_H + (slot - 1) * ROW_H
    return PX, y1, PX + PW, y1 + ROW_H
end

-- drawing factories
local function mkSq(z)
    local s = Drawing.new("Square")
    s.ZIndex       = z
    s.Transparency = 1
    s.Visible      = false
    return s
end

local function mkTx(sz, z)
    local t = Drawing.new("Text")
    t.Size         = sz
    t.Outline      = true
    t.ZIndex       = z
    t.Transparency = 1
    t.Visible      = false
    return t
end

local function mkLn(z)
    local l = Drawing.new("Line")
    l.ZIndex       = z
    l.Transparency = 1
    l.Visible      = false
    return l
end

-- menu drawables
local shadow = mkSq(7)
shadow.Filled   = true
shadow.Color    = C.shadow
shadow.Corner   = 12
shadow.Position = Vector2.new(PX + 5, PY + 6)
shadow.Size     = Vector2.new(PW, PH)

local panel = mkSq(8)
panel.Filled   = true
panel.Color    = C.panel
panel.Corner   = 12
panel.Position = Vector2.new(PX, PY)
panel.Size     = Vector2.new(PW, PH)

local border = mkSq(9)
border.Filled    = false
border.Thickness = 1
border.Color     = C.border
border.Corner    = 12
border.Position  = Vector2.new(PX, PY)
border.Size      = Vector2.new(PW, PH)

local logo = mkSq(10)
logo.Filled   = true
logo.Color    = C.accent
logo.Corner   = 3
logo.Position = Vector2.new(PX + 16, PY + 14)
logo.Size     = Vector2.new(12, 12)

local title = mkTx(20, 12)
title.Color    = C.text
title.Position = Vector2.new(PX + 36, PY + 11)
title.Text     = "Auth Menu"

local div1 = mkSq(9)
div1.Filled   = true
div1.Color    = C.border
div1.Position = Vector2.new(PX, PY + HEAD_H - 1)
div1.Size     = Vector2.new(PW, 1)

local tabPill = mkSq(10)
tabPill.Filled = true
tabPill.Color  = C.accent
tabPill.Corner = 6

local div2 = mkSq(9)
div2.Filled   = true
div2.Color    = C.border
div2.Position = Vector2.new(PX, PY + HEAD_H + TAB_H - 1)
div2.Size     = Vector2.new(PW, 1)

local tabBtns = {}
for i = 1, #tabs do
    tabBtns[i] = mkTx(14, 12)
end

local fInd = {}
local fLbl = {}
for _, f in ipairs(features) do
    fInd[f] = mkSq(10)
    fLbl[f] = mkTx(16, 12)
end

local bndTx = {}
for i = 1, #bindRows do
    bndTx[i] = mkTx(16, 12)
end

local footer = mkTx(13, 12)
footer.Color    = C.sub
footer.Position = Vector2.new(PX + 16, PY + PH - FOOT_H + 4)
footer.Text     = "M menu  |  Tab tabs  |  1-6 toggle  |  9 rebind"

local fovCircle = Drawing.new("Circle")
fovCircle.Filled      = false
fovCircle.Thickness   = 1
fovCircle.Color       = C.fov
fovCircle.NumSides    = 64
fovCircle.Radius      = AIM_FOV
fovCircle.Transparency = 1
fovCircle.Visible     = false
fovCircle.ZIndex      = 1

-- menu render
local function updateMenu()
    if not menuDirty then return end
    menuDirty = false
    local v = menuVisible

    shadow.Visible  = v
    panel.Visible   = v
    border.Visible  = v
    logo.Visible    = v
    title.Visible   = v
    footer.Visible  = v
    div1.Visible    = v
    div2.Visible    = v
    tabPill.Visible = v

    for i, name in ipairs(tabs) do
        local tb = tabBtns[i]
        tb.Visible = v
        if v then
            tb.Text     = name
            tb.Color    = (i == activeTab) and C.panel or C.sub
            tb.Position = Vector2.new(PX + (i - 1) * tabW + 12, PY + HEAD_H + 8)
        end
    end

    if v then
        local x1, y1 = tabRect(activeTab)
        tabPill.Position = Vector2.new(x1 + 4, y1 + 4)
        tabPill.Size     = Vector2.new(tabW - 8, TAB_H - 8)
    end

    local onBind = tabs[activeTab] == "Bind"

    for _, f in ipairs(features) do
        local show = v and not onBind and f.tab == tabs[activeTab]
        fInd[f].Visible = show
        fLbl[f].Visible = show
        if show then
            local _, y1 = rowRect(slotOf[f])
            local on    = state[f.field]
            fInd[f].Position  = Vector2.new(PX + 16, y1 + 7)
            fInd[f].Size      = Vector2.new(16, 16)
            fInd[f].Corner    = 4
            fInd[f].Filled    = on
            fInd[f].Thickness = 1
            fInd[f].Color     = on and C.on or C.off
            fLbl[f].Position  = Vector2.new(PX + 42, y1 + 6)
            fLbl[f].Text      = f.name
            fLbl[f].Color     = on and C.text or C.sub
        end
    end

    for i, br in ipairs(bindRows) do
        local t    = bndTx[i]
        local show = v and onBind
        t.Visible = show
        if show then
            local _, y1 = rowRect(i)
            t.Position = Vector2.new(PX + 16, y1 + 6)
            if listeningFor == br.id then
                t.Text  = br.label .. ":  <press a key>"
                t.Color = C.yellow
            else
                t.Text  = br.label .. ":  " .. br.getName()
                t.Color = C.accent
            end
        end
    end
end

-- player helpers
local function getEnemies()
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            out[#out + 1] = p
        end
    end
    return out
end

local function getRoot(player)
    local c = player.Character
    if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart")
end

local function getHead(player)
    local c = player.Character
    if not c then return nil end
    return c:FindFirstChild("Head")
end

local function getAimPart(player)
    return getHead(player) or getRoot(player)
end

local function getHum(player)
    local c = player.Character
    if not c then return nil end
    return c:FindFirstChildOfClass("Humanoid")
end

local function teamOf(player)
    local ok, name = pcall(function()
        return player.Team and player.Team.Name or nil
    end)
    return ok and name or nil
end

local function isEnemy(player)
    if not state.TeamCheck then return true end
    local mt = teamOf(LocalPlayer)
    local pt = teamOf(player)
    if mt and pt and mt == pt then return false end
    return true
end

-- esp pool
local espBox    = {}
local espHpBg   = {}
local espHpFg   = {}
local espName   = {}
local espTracer = {}

local function hideFrom(pool, from)
    for j = from, #pool do
        pool[j].Visible = false
    end
end

local function hideAllEsp(from)
    hideFrom(espBox,    from)
    hideFrom(espHpBg,   from)
    hideFrom(espHpFg,   from)
    hideFrom(espName,   from)
    hideFrom(espTracer, from)
end

local function getBox(i)
    if not espBox[i] then
        local b = Drawing.new("Square")
        b.Filled      = false
        b.Thickness   = 1
        b.Color       = C.box
        b.Transparency = 1
        b.Visible     = false
        b.ZIndex      = 2
        espBox[i] = b
    end
    return espBox[i]
end

local function getHpBg(i)
    if not espHpBg[i] then
        local l = mkLn(2)
        l.Thickness = 3
        l.Color     = Color3.fromRGB(0, 0, 0)
        espHpBg[i] = l
    end
    return espHpBg[i]
end

local function getHpFg(i)
    if not espHpFg[i] then
        local l = mkLn(3)
        l.Thickness = 2
        espHpFg[i] = l
    end
    return espHpFg[i]
end

local function getEspName(i)
    if not espName[i] then
        local t = mkTx(11, 4)
        t.Color   = C.text
        espName[i] = t
    end
    return espName[i]
end

local function getTracer(i)
    if not espTracer[i] then
        local l = Drawing.new("Line")
        l.Thickness   = 1
        l.Color       = C.line
        l.Transparency = 1
        l.Visible     = false
        l.ZIndex      = 1
        espTracer[i] = l
    end
    return espTracer[i]
end

local function updateEspTracers(players)
    local doEsp = state.ESP
    local doTr  = state.Tracers

    if not doEsp and not doTr then
        hideAllEsp(1)
        return
    end

    local vp = Camera.ViewportSize
    if vp.X == 0 then return end

    local origin = Vector2.new(vp.X / 2, vp.Y)
    local n      = #players

    for i, player in ipairs(players) do
        local box   = getBox(i)
        local hpBg  = getHpBg(i)
        local hpFg  = getHpFg(i)
        local nm    = getEspName(i)
        local tr    = getTracer(i)
        local showBox = false
        local showTr  = false

        local root = getRoot(player)

        if root and isEnemy(player) then
            local pos  = root.Position
            local sMid, midOn = w2s(pos)
            local sTop, _     = w2s(pos + Vector3.new(0, 3.2, 0))
            local sFeet, _    = w2s(pos - Vector3.new(0, 3.0, 0))

            if midOn then
                if doEsp then
                    local h = math.abs(sFeet.Y - sTop.Y)
                    if h < 6 then h = 6 end
                    local w = h * 0.55
                    box.Position = Vector2.new(sMid.X - w / 2, sTop.Y)
                    box.Size     = Vector2.new(w, h)
                    showBox      = true

                    local hum = getHum(player)
                    if hum and hum.MaxHealth > 0 then
                        local pct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                        local bx  = sMid.X - w / 2 - 5
                        local top = sTop.Y
                        local bot = sFeet.Y
                        hpBg.From    = Vector2.new(bx, top)
                        hpBg.To      = Vector2.new(bx, bot)
                        hpBg.Visible = true
                        local mid = bot - ((bot - top) * pct)
                        local r   = math.floor(255 * (1 - pct))
                        local g   = math.floor(220 * pct)
                        hpFg.Color   = Color3.fromRGB(r, g, 40)
                        hpFg.From    = Vector2.new(bx, mid)
                        hpFg.To      = Vector2.new(bx, bot)
                        hpFg.Visible = pct > 0
                    else
                        hpBg.Visible = false
                        hpFg.Visible = false
                    end

                    nm.Text     = player.Name
                    nm.Position = Vector2.new(sMid.X - 20, sTop.Y - 13)
                    nm.Visible  = true
                else
                    hpBg.Visible = false
                    hpFg.Visible = false
                    nm.Visible   = false
                end

                if doTr then
                    tr.From = origin
                    tr.To   = sMid
                    showTr  = true
                end
            else
                hpBg.Visible = false
                hpFg.Visible = false
                nm.Visible   = false
            end
        else
            hpBg.Visible = false
            hpFg.Visible = false
            nm.Visible   = false
        end

        box.Visible = showBox
        tr.Visible  = showTr
    end

    hideAllEsp(n + 1)
end

-- visibility raycast: true if the part is not behind a wall
local function partVis(camPos, targetChar, part)
    if not part then return false end
    local dir = part.Position - camPos
    local rp  = RaycastParams.new()
    rp.FilterDescendantsInstances = { LocalPlayer.Character }
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local hit = workspace:Raycast(camPos, dir, rp)
    if hit == nil then return true end
    return hit.Instance:IsDescendantOf(targetChar)
end

-- aim assist  (RMB primary, keyboard aimKey secondary)
-- body visible  -> aim at HRP with normal smooth lerp
-- head only     -> snap directly to head (0.9 lerp = locks in 1-2 frames)
local function updateAim(players)
    local vp = Camera.ViewportSize
    local cx = vp.X / 2
    local cy = vp.Y / 2

    fovCircle.Visible  = state.Aim
    fovCircle.Position = Vector2.new(cx, cy)

    if not (state.Aim and holdingAim) then return end

    local myPart = getAimPart(LocalPlayer)
    local myPos  = myPart and myPart.Position
    local camPos = Camera.CFrame.Position

    local bestDist   = AIM_FOV * AIM_FOV
    local bestTarget = nil
    local bestSmooth = AIM_SMOOTH
    local bestRoot   = nil

    for _, player in ipairs(players) do
        if isEnemy(player) then
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local head = char and char:FindFirstChild("Head")

            if root and char then
                local tooClose = myPos and (root.Position - myPos).Magnitude < 4
                if not tooClose then
                    local bodyVis = partVis(camPos, char, root)
                    local headVis = head and partVis(camPos, char, head)

                    local tgtPart   = nil
                    local tgtSmooth = AIM_SMOOTH

                    if bodyVis then
                        tgtPart   = root
                        tgtSmooth = AIM_SMOOTH
                    elseif headVis then
                        tgtPart   = head
                        tgtSmooth = 0.9
                    end

                    if tgtPart then
                        local sp, on = w2s(tgtPart.Position)
                        if on then
                            local d2 = (sp.X - cx) ^ 2 + (sp.Y - cy) ^ 2
                            if d2 < bestDist then
                                bestDist   = d2
                                bestTarget = tgtPart.Position
                                bestSmooth = tgtSmooth
                                bestRoot   = root
                            end
                        end
                    end
                end
            end
        end
    end

    if not bestTarget then return end

    local predict = bestTarget
    if bestRoot then
        local ok, vel = pcall(function() return bestRoot.AssemblyLinearVelocity end)
        if ok and vel then
            predict = bestTarget + vel * AIM_PREDICT
        end
    end

    local tgt     = CFrame.new(camPos, predict)
    Camera.CFrame = Camera.CFrame:Lerp(tgt, bestSmooth)
end

-- weapon mods
local weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")

-- staticVals: set once when Weapons enabled, restored when disabled
local staticVals = {}
staticVals.ReloadTime    = 0
staticVals.MaxSpread     = 0
staticVals.RecoilControl = 0
staticVals.Auto          = true

-- contVals: numeric values re-applied every 3 frames (server resets these)
-- FireRate = 0 locks the weapon (zero shots/sec). 999 = rapid fire.
local contVals = {}
contVals.Ammo       = 999999999
contVals.StoredAmmo = 999999999
contVals.FireRate   = 999

local snapshots      = {}
local weaponsApplied = false

local function applyStatic()
    if not weaponsFolder then return end
    snapshots = {}
    for _, w in ipairs(weaponsFolder:GetChildren()) do
        for name, val in pairs(staticVals) do
            local o = w:FindFirstChild(name)
            if o then
                snapshots[#snapshots + 1] = { obj = o, orig = o.Value }
                pcall(function() o.Value = val end)
            end
        end
    end
end

local function restoreAll()
    for _, s in ipairs(snapshots) do
        pcall(function() s.obj.Value = s.orig end)
    end
    snapshots = {}
end

local function tickAmmo()
    if not weaponsFolder then return end
    for _, w in ipairs(weaponsFolder:GetChildren()) do
        for name, cap in pairs(contVals) do
            local o = w:FindFirstChild(name)
            if o and o.Value < cap then
                pcall(function() o.Value = cap end)
            end
        end
    end
end

local function updateWeapons(frame)
    if state.Weapons and not weaponsApplied then
        applyStatic()
        weaponsApplied = true
    elseif not state.Weapons and weaponsApplied then
        restoreAll()
        weaponsApplied = false
    end
    if state.Weapons and frame % 3 == 0 then
        tickAmmo()
    end
end

-- hitbox
local hbSaved = {}

local function applyHitbox(players)
    for _, player in ipairs(players) do
        local root = getRoot(player)
        if root and not hbSaved[player] then
            hbSaved[player] = { root = root, size = root.Size }
            pcall(function()
                root.Size = Vector3.new(HITBOX_SIZE, HITBOX_SIZE, HITBOX_SIZE)
            end)
        end
    end
end

local function restoreHitbox()
    for _, data in pairs(hbSaved) do
        pcall(function()
            if data.root and data.root.Parent then
                data.root.Size = data.size
            end
        end)
    end
    hbSaved = {}
end

local function updateHitbox(players)
    if state.Hitbox then
        applyHitbox(players)
    elseif next(hbSaved) then
        restoreHitbox()
    end
end

-- fly
local flyActive = false
local flyBV     = nil
local flyParts  = {}

local function enableFly()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not root then return end

    flyParts = {}
    for _, p in ipairs(char:GetChildren()) do
        if p:IsA("BasePart") then
            flyParts[#flyParts + 1] = { p, p.CanCollide }
            pcall(function() p.CanCollide = false end)
        end
    end

    if hum then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
    end

    flyBV          = Instance.new("BodyVelocity")
    flyBV.Velocity = Vector3.new(0, 0, 0)
    flyBV.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    flyBV.P        = 1e4
    flyBV.Parent   = root
    flyActive      = true
end

local function disableFly()
    for _, e in ipairs(flyParts) do
        pcall(function() e[1].CanCollide = e[2] end)
    end
    flyParts = {}

    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end

    if flyBV then
        pcall(function() flyBV:Destroy() end)
        flyBV = nil
    end
    flyActive = false
end

local function updateFly()
    if state.Fly and not flyActive then
        enableFly()
    elseif not state.Fly and flyActive then
        disableFly()
    end

    if not (state.Fly and flyBV) then return end

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    if flyBV.Parent ~= root then
        pcall(function() flyBV:Destroy() end)
        flyBV     = nil
        flyActive = false
        return
    end

    for _, p in ipairs(char:GetChildren()) do
        if p:IsA("BasePart") then
            pcall(function() p.CanCollide = false end)
        end
    end

    local move = Vector3.new(0, 0, 0)
    local cf   = root.CFrame
    if held.W    then move = move + cf.LookVector  * FLY_SPEED end
    if held.S    then move = move - cf.LookVector  * FLY_SPEED end
    if held.D    then move = move + cf.RightVector * FLY_SPEED end
    if held.A    then move = move - cf.RightVector * FLY_SPEED end
    if held.Up   then move = move + Vector3.new(0,  FLY_SPEED, 0) end
    if held.Down then move = move + Vector3.new(0, -FLY_SPEED, 0) end

    flyBV.Velocity = move
end

-- input
local downKeys = {}

local function isDown(kc)
    for _, k in ipairs(downKeys) do
        if k == kc then return true end
    end
    return false
end

local function removeDown(kc)
    for i, k in ipairs(downKeys) do
        if k == kc then
            table.remove(downKeys, i)
            return
        end
    end
end

local function toggleField(field)
    state[field] = not state[field]
    setDirty()
end

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        holdingAim = true
        return
    end

    local kc = input.KeyCode
    if kc == Enum.KeyCode.Unknown then return end
    if isDown(kc) then return end
    downKeys[#downKeys + 1] = kc

    if listeningFor then
        local k, n = findBindable(kc)
        if k then
            if listeningFor == "aim" then
                aimKey     = k
                aimKeyName = n
            else
                flyKey     = k
                flyKeyName = n
            end
            listeningFor = nil
            setDirty()
        end
        return
    end

    if kc == Enum.KeyCode.W then
        held.W = true
    elseif kc == Enum.KeyCode.A then
        held.A = true
    elseif kc == Enum.KeyCode.S then
        held.S = true
    elseif kc == Enum.KeyCode.D then
        held.D = true
    elseif kc == Enum.KeyCode.Space then
        held.Up = true
    elseif kc == Enum.KeyCode.LeftShift then
        held.Down = true
    end

    if kc == Enum.KeyCode.M or kc == Enum.KeyCode.RightShift then
        menuVisible = not menuVisible
        setDirty()
    elseif kc == Enum.KeyCode.Zero or kc == Enum.KeyCode.Tab then
        activeTab = (activeTab % #tabs) + 1
        setDirty()
    elseif kc == Enum.KeyCode.Nine or kc == Enum.KeyCode.RightControl then
        if listeningFor == nil then
            listeningFor = "aim"
        elseif listeningFor == "aim" then
            listeningFor = "fly"
        else
            listeningFor = nil
        end
        setDirty()
    elseif kc == flyKey then
        toggleField("Fly")
    elseif kc == aimKey then
        holdingAim = true
    else
        for _, f in ipairs(features) do
            if f.key and kc == f.key then
                toggleField(f.field)
            end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        holdingAim = false
        return
    end

    local kc = input.KeyCode
    removeDown(kc)

    if kc == aimKey then holdingAim = false end

    if kc == Enum.KeyCode.W then
        held.W = false
    elseif kc == Enum.KeyCode.A then
        held.A = false
    elseif kc == Enum.KeyCode.S then
        held.S = false
    elseif kc == Enum.KeyCode.D then
        held.D = false
    elseif kc == Enum.KeyCode.Space then
        held.Up = false
    elseif kc == Enum.KeyCode.LeftShift then
        held.Down = false
    end
end)

-- click detection
local wasPressed = false

local function updateClicks()
    if not menuVisible then return end

    local pressed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)

    if pressed and not wasPressed then
        local loc     = UserInputService:GetMouseLocation()
        local mx      = loc.X
        local my      = loc.Y
        local handled = false

        for i = 1, #tabs do
            local x1, y1, x2, y2 = tabRect(i)
            if mx >= x1 and mx <= x2 and my >= y1 and my <= y2 then
                activeTab = i
                setDirty()
                handled = true
                break
            end
        end

        if not handled then
            if tabs[activeTab] == "Bind" then
                for i = 1, #bindRows do
                    local x1, y1, x2, y2 = rowRect(i)
                    if mx >= x1 and mx <= x2 and my >= y1 and my <= y2 then
                        listeningFor = bindRows[i].id
                        setDirty()
                        handled = true
                        break
                    end
                end
            else
                for _, f in ipairs(features) do
                    if f.tab == tabs[activeTab] then
                        local x1, y1, x2, y2 = rowRect(slotOf[f])
                        if mx >= x1 and mx <= x2 and my >= y1 and my <= y2 then
                            toggleField(f.field)
                            handled = true
                            break
                        end
                    end
                end
            end
        end
    end

    wasPressed = pressed
end

-- main loop
local frame = 0

RunService.RenderStepped:Connect(function()
    frame = frame + 1
    updateMenu()
    updateClicks()

    local players = getEnemies()

    updateEspTracers(players)
    updateAim(players)

    if frame % 8 == 0 then
        updateHitbox(players)
    end

    updateWeapons(frame)
    updateFly()
end)

print("[AuthMenu] loaded  |  M=menu  |  1-6=toggle  |  RMB=aim  |  F=fly")
