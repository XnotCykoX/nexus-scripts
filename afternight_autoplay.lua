--[[ ============================================================================
     NEXUS AUTOPLAY  —  Project: Afternight (VSRG / FNF-style)
     Personal testing tool. Self-discovers the strumline (Main.Game / Strum*),
     maps lanes to your in-game keybinds, and hits notes via VirtualInputManager.
       • Perfect  : per-note crossing detection — miss-proof (fast notes, jacks,
                    pooled/recycled notes, holds all handled).
       • Human    : set a target accuracy %; a controller reads the game's live
                    rating and converges its timing error onto your number.
     UI: XnotCykoX Apex Suite GUI library.
     ============================================================================ ]]

-- ---- load the Apex GUI library ----
-- Two in-memory tweaks (your repo file is untouched):
--   1) append `return ApexLibrary` so `loadstring(...)()` yields the table.
--   2) a parent-selection shim so the UI works on every executor. The stock library commits to
--      CoreGui after only reading CoreGui.Name; executors that allow that read but block parenting
--      (e.g. "lacking capability Plugin") then error. The shim prefers gethui(), falls back to
--      CoreGui only if it's actually writable, else PlayerGui.
local Apex
do
    local url = "https://raw.githubusercontent.com/XnotCykoX/nexus-scripts/refs/heads/main/Gui%20Library.lua"
    local src = game:HttpGet(url)
    -- gethui() first, else PlayerGui. Deliberately NEVER touch CoreGui directly: on some executors
    -- any CoreGui access (even a caught pcall) permanently drops the thread's capability, after which
    -- every Instance.new fails — which silently half-builds the UI. gethui already returns the safe
    -- hidden container, so CoreGui is never needed.
    local shim = "local ParentUI=(function() local a pcall(function() a=gethui() end) if a then return a end return LocalPlayer:WaitForChild('PlayerGui') end)()\n"
    src = src:gsub("local ParentUI = .-\n", shim, 1)
    Apex = loadstring(src .. "\nreturn ApexLibrary")()
end

local ok, err = pcall(function()

-- ---- teardown any previous instance FIRST, then claim a new generation ----
if getgenv and getgenv().NexusAP and getgenv().NexusAP.Destroy then pcall(getgenv().NexusAP.Destroy) end
local myGen = ((getgenv and getgenv().NexusAP_gen) or 0) + 1
if getgenv then getgenv().NexusAP_gen = myGen end
local AP = {} if getgenv then getgenv().NexusAP = AP end
local function genOK() return (not getgenv) or getgenv().NexusAP_gen == myGen end

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local RS      = game:GetService("RunService")
local VIM     = game:GetService("VirtualInputManager")
local RSt     = game:GetService("ReplicatedStorage")
local lp      = Players.LocalPlayer
local pg      = lp:WaitForChild("PlayerGui")

local cfg = { enabled=false, mode="Perfect", window=26, offset=0, holds=true, targetAcc=95,
              holdGrace=0.05, tapLen=0.05, showHud=true }
AP.cfg = cfg

-- keybinds from the game's own DataManager
local kbAll = {}
pcall(function() local d = require(RSt.Modules.Data.DataManager).GetData(); kbAll = d and d.Keybinds or {} end)
local ORDERS = {
    [1]={"Square"}, [2]={"Left","Right"}, [3]={"Left","Square","Right"},
    [4]={"Left","Down","Up","Right"}, [5]={"Left","Down","Square","Up","Right"},
    [6]={"Left","Down","Up","Left2","Down2","Up2"}, [7]={"Left","Down","Up","Square","Left2","Down2","Up2"},
}
local function keyEnum(n) if not n then return nil end local okk,e = pcall(function() return Enum.KeyCode[n] end) return okk and e or nil end

local keyDown, tapReleaseAt, lastHold, heldKeys = {}, {}, {}, {}
local noteInfo = {}
local stats = { hits=0, K=0, lanes=0, active=0, acc=-1 }
AP.stats = stats
local humanErr, missChance = 0, 0

local function press(k, down) pcall(function() VIM:SendKeyEvent(down, k, false, game) end) end
local function pressKey(i, ln, down)
    if down then press(ln.key, true); keyDown[i]=true; heldKeys[i]=ln.key
    else if heldKeys[i] then press(heldKeys[i], false) end keyDown[i]=false end
end
local function releaseAllKeys() for i,k in pairs(heldKeys) do if keyDown[i] then press(k,false); keyDown[i]=false end end end
local function getGameFrame() local m = pg:FindFirstChild("Main"); return m and m:FindFirstChild("Game") end
local hud = pg.Main:FindFirstChild("HUD")
local function readAcc()
    if not hud then hud = pg.Main:FindFirstChild("HUD") end
    local al = hud and hud:FindFirstChild("Accuracy")
    local t = al and tostring(al.Text) or ""
    local n = t:match("([%d%.]+)%%")
    return n and tonumber(n)
end

local function buildLanes(gm)
    local strums = {}
    for _, c in ipairs(gm:GetChildren()) do
        if c:IsA("ImageLabel") and string.match(c.Name, "^Strum") and string.find(tostring(c.Image), "rbxassetid") then
            strums[#strums+1] = c
        end
    end
    table.sort(strums, function(a,b) return a.AbsolutePosition.X < b.AbsolutePosition.X end)
    local K = #strums
    local order, kb = ORDERS[K], kbAll[tostring(K)]
    local lanes = {}
    for i, s in ipairs(strums) do
        local key if order and kb then key = keyEnum(kb[order[i]]) end
        lanes[i] = { cx = s.AbsolutePosition.X + s.AbsoluteSize.X/2, cy = s.AbsolutePosition.Y + s.AbsoluteSize.Y/2, key = key }
    end
    stats.K = K; stats.lanes = #lanes
    return lanes
end

-- ---- hit loop ----
AP.loopConn = RS.Heartbeat:Connect(function()
    if not genOK() then AP.loopConn:Disconnect(); releaseAllKeys(); return end
    if not cfg.enabled then releaseAllKeys(); stats.active=0; return end
    local gm = getGameFrame() if not gm then releaseAllKeys() return end
    local lanes = buildLanes(gm) if #lanes == 0 then return end
    local tol = 80 if #lanes >= 2 then tol = math.abs(lanes[2].cx - lanes[1].cx) * 0.5 end
    local now = os.clock()
    local holdActive, tapFire, seen = {}, {}, {}
    local active = 0
    for _, c in ipairs(gm:GetChildren()) do
        if c:IsA("ImageLabel") and not string.match(c.Name, "^Strum") then
            local sz = c.AbsoluteSize
            if sz.Y > 0 and c.ImageTransparency < 0.95 then
                local cx  = c.AbsolutePosition.X + sz.X/2
                local top = c.AbsolutePosition.Y
                local bi, bd = nil, tol
                for i, ln in ipairs(lanes) do local d = math.abs(cx - ln.cx) if d < bd then bd=d; bi=i end end
                if bi then
                    local ln  = lanes[bi]
                    local eff = ln.cy + cfg.offset
                    if cfg.mode == "Human" then eff = eff + humanErr + (math.random()*6-3) end
                    local sustain = c.AnchorPoint.Y < 0.25          -- hold trails are top-anchored (0.5,0.0)
                    if sustain then
                        if cfg.holds and eff >= top - cfg.window and eff <= top + sz.Y + cfg.window then
                            holdActive[bi] = true; active = active + 1
                        end
                    else
                        local ctr  = top + sz.Y/2
                        local info = noteInfo[c] if not info then info = {prevY=ctr, tapped=false}; noteInfo[c]=info end
                        if info.prevY and math.abs(ctr - info.prevY) > 300 then info.tapped = false end   -- recycled/pooled -> re-arm
                        seen[c] = true
                        local crossed = (not info.tapped) and
                            ((info.prevY ~= nil and (info.prevY-eff)*(ctr-eff) <= 0) or (math.abs(ctr-eff) <= cfg.window))
                        if crossed then
                            info.tapped = true
                            if not (cfg.mode=="Human" and missChance>0 and math.random()<missChance) then
                                tapFire[bi] = true; active = active + 1
                            end
                        end
                        info.prevY = ctr
                    end
                end
            end
        end
    end
    for c,_ in pairs(noteInfo) do if not seen[c] or not c.Parent then noteInfo[c]=nil end end
    stats.active = active
    for i, ln in ipairs(lanes) do if ln.key then
        if holdActive[i] then lastHold[i] = now end
        local holding = holdActive[i] or (lastHold[i] ~= nil and (now - lastHold[i]) <= cfg.holdGrace)
        if holding then
            if not keyDown[i] then pressKey(i, ln, true) end
            tapReleaseAt[i] = nil
        else
            if tapFire[i] then
                if keyDown[i] then pressKey(i, ln, false) end     -- release prior (jack) same frame
                pressKey(i, ln, true); tapReleaseAt[i] = now + cfg.tapLen; stats.hits = stats.hits + 1
            elseif keyDown[i] then
                if (tapReleaseAt[i] and now >= tapReleaseAt[i]) or (not tapReleaseAt[i]) then
                    pressKey(i, ln, false); tapReleaseAt[i] = nil
                end
            end
        end
    end end
end)

-- ---- accuracy feedback controller (Human) ----
local lastCtrl = 0
AP.ctrlConn = RS.Heartbeat:Connect(function()
    if not genOK() then AP.ctrlConn:Disconnect(); return end
    local now = os.clock() if now - lastCtrl < 0.4 then return end lastCtrl = now
    if cfg.mode ~= "Human" or not cfg.enabled then humanErr=0; missChance=0; return end
    local a = readAcc() if not a then return end stats.acc = a
    local d = a - cfg.targetAcc
    if d > 0.15 then
        if humanErr < cfg.window*0.9 then humanErr = math.min(humanErr+1.5, cfg.window*0.9) else missChance = math.min(missChance+0.008, 0.6) end
    elseif d < -0.15 then
        if missChance > 0 then missChance = math.max(missChance-0.02, 0) else humanErr = math.max(humanErr-1.5, 0) end
    end
end)

-- ---- status HUD (small floating chip; the Apex lib has no live-label element) ----
-- Parented via gethui()/PlayerGui only (never CoreGui) and fully guarded, so it can never abort the
-- engine — the chip is optional cosmetics; the loop above already runs regardless.
local chip
pcall(function()
    local hudGui = Instance.new("ScreenGui")
    hudGui.Name = "NexusAPStatus"; hudGui.ResetOnSpawn = false; hudGui.IgnoreGuiInset = true
    local p pcall(function() p = gethui() end)
    hudGui.Parent = p or pg
    AP.hudGui = hudGui
    chip = Instance.new("TextLabel")
    chip.AnchorPoint = Vector2.new(0.5, 0); chip.Position = UDim2.new(0.5, 0, 0, 8); chip.Size = UDim2.new(0, 320, 0, 24)
    chip.BackgroundColor3 = Color3.fromRGB(14,15,20); chip.BackgroundTransparency = 0.1
    chip.Font = Enum.Font.Code; chip.TextSize = 12; chip.TextColor3 = Color3.fromRGB(0,242,254)
    chip.Text = "Nexus Autoplay"; chip.Parent = hudGui
    Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 6)
    local cs = Instance.new("UIStroke"); cs.Color = Color3.fromRGB(65,70,95); cs.Thickness = 1; cs.Parent = chip
end)

AP.statConn = RS.Heartbeat:Connect(function()
    if not genOK() then AP.statConn:Disconnect(); return end
    if not chip then return end
    chip.Visible = cfg.showHud
    local accS = stats.acc >= 0 and string.format("%.2f%%", stats.acc) or "--"
    local extra = cfg.mode == "Human" and string.format(" err%.0f miss%.0f%%", humanErr, missChance*100) or ""
    chip.Text = string.format("%s  %dK  hits:%d  active:%d  acc:%s%s",
        cfg.enabled and "RUNNING" or "idle", stats.K, stats.hits, stats.active, accS, extra)
    chip.TextColor3 = cfg.enabled and Color3.fromRGB(83,215,105) or Color3.fromRGB(130,135,155)
end)

-- ---- teardown (defined BEFORE the UI, so a re-run always cleans up even if UI creation fails) ----
AP.Destroy = function()
    if getgenv then getgenv().NexusAP_gen = (getgenv().NexusAP_gen or 0) + 1 end
    pcall(function() AP.loopConn:Disconnect() end)
    pcall(function() AP.ctrlConn:Disconnect() end)
    pcall(function() AP.statConn:Disconnect() end)
    releaseAllKeys()
    pcall(function() AP.hudGui:Destroy() end)
    -- find/destroy the Apex UI via gethui()/PlayerGui only — never CoreGui (see the shim note above).
    local roots = { pg }
    pcall(function() roots[#roots+1] = gethui() end)
    for _, root in ipairs(roots) do
        if root then pcall(function() local u = root:FindFirstChild("ApexLibrary_UI") if u then u:Destroy() end end) end
    end
end

-- ---- UI (Apex Suite) ----
local Window = Apex:CreateWindow("NEXUS AUTOPLAY // AFTERNIGHT")
local Tab = Window:CreateTab("Autoplay")
Tab:CreateSection("Main")
Tab:CreateToggle("Autoplay", false, function(s) cfg.enabled = s if not s then releaseAllKeys() end end)
Tab:CreateToggle("Human mode", false, function(s) cfg.mode = s and "Human" or "Perfect" end)
Tab:CreateToggle("Hold notes", true, function(s) cfg.holds = s end)
Tab:CreateSection("Tuning")
Tab:CreateSlider("Target accuracy % (Human)", 60, 100, cfg.targetAcc, function(v) cfg.targetAcc = v end)
Tab:CreateSlider("Hit window (px)", 6, 120, cfg.window, function(v) cfg.window = v end)
Tab:CreateSlider("Timing offset (px)", -60, 60, cfg.offset, function(v) cfg.offset = v end)
Tab:CreateSection("Interface")
Tab:CreateToggle("Show status HUD", true, function(s) cfg.showHud = s end)

print("[NexusAP] loaded via Apex UI. Toggle Autoplay in the menu (RightShift to hide/show).")
end)

if not ok then warn("[NexusAP] error: " .. tostring(err)) end
