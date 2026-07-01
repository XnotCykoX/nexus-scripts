-- // ═══════════════════════════════════════════════════
-- //   NEXUS  |  Universal Aimbot + ESP + Sprint
-- //   Frontlines (5938036553) auto-detected
-- //   RightAlt=UI · RMB=aim · Shift+Q=lock
-- // ═══════════════════════════════════════════════════

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local GuiService   = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local lp    = Players.LocalPlayer
local mouse = lp:GetMouse()
local cam   = workspace.CurrentCamera
local INSET = GuiService:GetGuiInset()

local IS_FL       = game.PlaceId == 5938036553
-- in this game dead players leave a persistent "HumanBody" model in workspace.
-- it has a Humanoid with health so it passes isAlive, but it can't be killed.
-- IS_DEADWORLD gates the name-filter so the guard only runs in this one game.
local IS_DEADWORLD = game.PlaceId == 93091759101123
local IS_BP        = game.PlaceId == 3527629287
print("[NEXUS] PlaceId:", game.PlaceId, "| FL:", IS_FL, "| BP:", IS_BP, "| DeadWorld:", IS_DEADWORLD)

-- container for Highlight instances (Highlight needs to live in the DataModel to render)
local hlContainer = Instance.new("Folder")
hlContainer.Name  = "NexusHighlights"
local _ok, _cg = pcall(function() return game:GetService("CoreGui") end)
hlContainer.Parent = (_ok and _cg) or lp.PlayerGui

-- // ══════════════════ CONFIG ════════════════════════ //

local cfg = {
    aim = {
        enabled      = false,
        mode         = "Smooth",   -- "Smooth"|"Flick"|"Rage"|"Human"|"Trickshot"
        smooth       = 3,
        fov          = 150,
        target_parts = {Head=true},
        team_check   = true,
        vis_check    = false,
        prediction   = true,
        pred_mult    = 0.13,
        pred_speed   = 900,
        ts_flick_dur = 0.15,
        triggerbot   = false,
        trig_delay   = 0.07,
        toggle_mode  = false,
        auto_switch  = true,   -- retarget immediately when locked enemy dies
    },
    esp = {
        enabled    = false,
        box        = true,
        rainbow    = false,
        corners    = false,
        names      = true,
        health     = true,
        distance   = true,
        tracers    = false,
        skeleton   = false,
        outline    = false,
        team_check = false,
        dist_fade  = false,  -- fade all ESP elements with distance
        fade_start = 50,     -- studs: full opacity up to here
        fade_end   = 200,    -- studs: fully invisible at/beyond here
    },
    sprint = {
        enabled     = false,
        key         = Enum.KeyCode.LeftShift,
        speed       = 30,
        default_spd = 16,
    },
    misc = {
        fov_circle   = true,
        crosshair    = false,
        ch_size      = 10,
        npc_mode     = false,
        magic_bullet = false,
        mb_debug     = false,
        bhop         = false,  -- auto-rejump on landing while space held
        noclip       = false,  -- disable character collision
        prox_alarm   = false,  -- screen-edge pulse when enemy is close
        prox_dist    = 30,     -- studs threshold for proximity alarm
    },
    minimap = {
        enabled  = false,
        size     = 180,
        range    = 150,
        fov_cone = true,  -- draw camera FOV wedge on the radar
    },
    bp = {
        -- Big Paintball (3527629287) specific settings.
        -- drop_comp: aim above target by 0.5*g*tof² to hit where gravity pulls
        --            the bullet to by the time it arrives. tof = dist/velocity.
        -- patch_velocity: require-mutates the gun module so every LocalScript in
        --            the same Lua VM that required it sees the new velocity.
        --            higher velocity = less drop = easier hitting distant targets.
        -- patch_auto: turns semi-auto guns fully automatic via the same mutation.
        drop_comp      = true,
        patch_velocity = true,
        patched_vel    = 400,   -- studs/s (vanilla is 235; 400 keeps it somewhat believable)
        patch_auto     = true,  -- patch automatic = true (semi → auto)
    },
    keys = {
        aim    = Enum.KeyCode.F1,   -- toggle aimbot on/off
        esp    = Enum.KeyCode.F2,   -- toggle ESP on/off
        bhop   = Enum.KeyCode.F3,   -- toggle bhop on/off
        noclip = Enum.KeyCode.F4,   -- toggle noclip on/off
    },
}

-- // ════════════════ CONFIG I/O ══════════════════════ //
-- auto-load on startup, auto-save whenever the GUI changes a value
-- serialises cfg to JSON via HttpService; Enum values stored as "Enum.X.Y" strings

local CFG_FILE = "nexus_cfg.json"
local _HS; pcall(function() _HS = game:GetService("HttpService") end)

local function saveCfg()
    if not _HS then return end
    local flat = {}
    for sec, tbl in pairs(cfg) do
        for k, v in pairs(tbl) do
            local fk = sec.."."..k
            local vt = type(v)
            if vt=="boolean" or vt=="number" or vt=="string" then
                flat[fk] = v
            elseif typeof(v)=="EnumItem" then
                flat[fk] = tostring(v)           -- "Enum.KeyCode.LeftShift"
            elseif vt=="table" then
                flat[fk] = v                     -- target_parts sub-table (JSON-serialisable bools)
            end
        end
    end
    pcall(function() writefile(CFG_FILE, _HS:JSONEncode(flat)) end)
end

local function loadCfg()
    if not _HS then return end
    local ok, raw = pcall(readfile, CFG_FILE)
    if not ok or not raw or raw=="" then return end
    local ok2, flat = pcall(function() return _HS:JSONDecode(raw) end)
    if not ok2 or type(flat)~="table" then return end
    for fk, v in pairs(flat) do
        local dot = fk:find("%.")
        if not dot then continue end
        local sec = fk:sub(1, dot-1)
        local key = fk:sub(dot+1)
        if type(cfg[sec])~="table" then continue end
        if type(v)=="string" and v:sub(1,5)=="Enum." then
            -- reconstruct EnumItem from "Enum.KeyCode.LeftShift"
            local parts={}
            for p in v:gmatch("[^%.]+") do parts[#parts+1]=p end
            if #parts==3 then
                pcall(function() cfg[sec][key]=Enum[parts[2]][parts[3]] end)
            end
        elseif type(cfg[sec][key])=="table" and type(v)=="table" then
            for tk, tv in pairs(v) do cfg[sec][key][tk]=tv end
        elseif type(v)==type(cfg[sec][key]) or cfg[sec][key]==nil then
            cfg[sec][key]=v
        end
    end
end

loadCfg()  -- apply saved config before any GUI or system reads cfg

-- // ════════════════ DRAWING ═════════════════════════ //

local function D(class, props)
    local ok, d = pcall(Drawing.new, class)
    if not ok then return {Visible=false, Remove=function()end} end
    for k, v in pairs(props) do pcall(function() d[k]=v end) end
    return d
end

local WHITE = Color3.fromRGB(255,255,255)
local BLACK = Color3.new(0,0,0)
local RED   = Color3.fromRGB(255,60,60)
local GOLD  = Color3.fromRGB(255,210,50)

-- // ═══════════════ CONNECTIONS ══════════════════════ //

local conns = {}
local function conn(c) table.insert(conns,c); return c end

-- // ══════════ EVENT-DRIVEN MODEL CACHE ══════════════ //

local modelCache    = {}
local myModelCached = nil
local myModelStamp  = 0
local cacheRebuildT = 0

local function isPlayerChar(model)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == model then return true end
    end
    return false
end

local function shouldTrack(obj)
    if not (obj and obj:IsA("Model")) then return false end
    -- FL: soldier_model may NOT have Humanoid as a direct child — it's nested
    -- deeper or absent entirely. Only HumanoidRootPart is guaranteed.
    -- FindFirstChildOfClass searches direct children only, so requiring it here
    -- was silently dropping every model without a top-level Humanoid.
    if IS_FL then
        return obj.Name == "soldier_model"
           and obj:FindFirstChild("HumanoidRootPart") ~= nil
    end
    local hum  = obj:FindFirstChildOfClass("Humanoid")
    local root = obj:FindFirstChild("HumanoidRootPart")
    if not (hum and root) then return false end
    if cfg.misc.npc_mode then return (not isPlayerChar(obj)) and obj ~= lp.Character end
    return false
end

local function tryAdd(obj)
    if shouldTrack(obj) and not modelCache[obj] then modelCache[obj] = true end
end

local function rebuildModelCache()
    local fresh = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if shouldTrack(obj) then fresh[obj] = true end
    end
    for obj in pairs(modelCache) do if not fresh[obj] then modelCache[obj] = nil end end
    for obj in pairs(fresh) do modelCache[obj] = true end
end

conn(workspace.DescendantAdded:Connect(function(child)
    task.defer(function()
        if child:IsA("Model") then tryAdd(child) end
        local par = child.Parent
        if par and par:IsA("Model") then tryAdd(par) end
    end)
end))
conn(workspace.DescendantRemoving:Connect(function(child)
    if child:IsA("Model") then modelCache[child] = nil end
end))

-- // ═══════════ FORWARD DECLARES ═════════════════════ //

local getLocalFLModel
local destroyESP

-- // ════════════ WALL CHECK ══════════════════════════ //

local function wallCheck(targetModel, targetPos)
    local myChar = (IS_FL and getLocalFLModel) and getLocalFLModel() or lp.Character
    local ok, params = pcall(RaycastParams.new)
    if not ok then return true end
    params.FilterType = Enum.RaycastFilterType.Exclude
    -- Exclude BOTH own character AND the target model from the cast.
    -- Old approach: only excluded myChar, then post-checked IsAncestorOf.
    -- FL problem: soldier_models have weapons and accessories that physically
    -- clip through thin walls. the ray hits an accessory part, IsAncestorOf
    -- fires true, and the target is marked "visible" while their body is
    -- fully behind cover. excluding the target entirely and checking only
    -- whether any OTHER geometry blocks the path is far more reliable.
    local excl = {}
    if myChar       then excl[#excl+1] = myChar       end
    if targetModel  then excl[#excl+1] = targetModel  end
    params.FilterDescendantsInstances = excl
    local result = workspace:Raycast(cam.CFrame.Position, targetPos - cam.CFrame.Position, params)
    if not result then return true end
    if result.Instance.Transparency >= 0.9 then return true end
    return false
end

-- // ════════ FL CHARACTER + TEAM HELPERS ════════════ //
--
-- In Frontlines, player.Character = "StarterCharacter" — a dummy Roblox character
-- that sits at the wrong position (origin or underground). The real game character
-- lives in workspace named after the player (workspace:FindFirstChild(plr.Name)).
-- That workspace model has HumanoidRootPart, Humanoid, and the TPVBodyVanilla mesh.
--
-- Team detection: Frontlines uses the standard Roblox Teams service.
-- player.TeamColor comparison is the reliable signal (same approach as the
-- community Frontlines scripts). friendly_marker is not present on all builds.

local function getFLChar(plr)
    -- always prefer the workspace model — StarterCharacter has no real world position
    local ws = workspace:FindFirstChild(plr.Name)
    if ws and ws:FindFirstChild("HumanoidRootPart") then return ws end
    -- fallback to player.Character if workspace model isn't up yet
    return plr.Character
end

local function isFLTeammate(plr)
    -- Roblox TeamColor: both players on the same team share the same BrickColor number.
    -- BrickColor 194 = medium stone grey = "no team" default — treat as enemy.
    local tc = plr.TeamColor
    local myTc = lp.TeamColor
    if not tc or not myTc then return false end
    if tc.Number == 194 then return false end
    return tc == myTc
end

local function flHead(char)
    -- soldier_model uses TPVBodyVanillaHead instead of the standard "Head"
    return char:FindFirstChild("TPVBodyVanillaHead") or char:FindFirstChild("Head")
end

-- ordered list of FL body parts to try as aim targets.
-- torso-first: large hit region, reliable centre-mass contact.
-- head listed second so wall peeks (torso hidden) fall through to head.
local FL_BODY_PARTS = {
    "TPVBodyVanillaTorsoFront",
    "TPVBodyVanillaHead",
    "TPVBodyVanillaTorsoBack",
    "TPVBodyVanillaArmL",
    "TPVBodyVanillaArmR",
    "HumanoidRootPart",
}

-- returns the first FL body part that is on-screen, in FL_BODY_PARTS order.
-- order-based priority means:
--   standing / crouching / sliding → TorsoFront (always on screen, centre mass)
--   wall peek (torso behind cover)  → Head (falls through to first visible part)
--   last resort                     → HumanoidRootPart
-- previously used "lowest screen Y" (highest part) which always picked the
-- head, causing the aimbot to aim above where bullets actually register.
local function pickFLAimPart(char, root)
    for _, pName in ipairs(FL_BODY_PARTS) do
        local p = char:FindFirstChild(pName)
        if p then
            local _, onScreen = cam:WorldToViewportPoint(p.Position)
            if onScreen then return p end
        end
    end
    return root
end

-- // ══════════ FRONTLINES HELPERS ════════════════════ //

getLocalFLModel = function()
    local now = tick()
    if myModelCached and (now - myModelStamp) < 0.5 then return myModelCached end
    myModelStamp = now

    -- FL primary: the local player's character in Frontlines is a Model named
    -- "StarterPlayer" in workspace. find by name — unlike a numeric index this
    -- doesn't shift if workspace children are added or removed before it loads.
    local starterPlayer = workspace:FindFirstChild("StarterPlayer")
    if starterPlayer and starterPlayer:IsA("Model")
       and starterPlayer:FindFirstChildOfClass("Humanoid") then
        myModelCached = starterPlayer; return starterPlayer
    end

    -- fallback: camera subject walk-up (spectating, death-cam, late spawn)
    local subject = cam.CameraSubject
    if subject then
        local cur = subject
        for _ = 1, 6 do
            if cur:IsA("Model") and cur.Name == "soldier_model" then myModelCached=cur; return cur end
            local ok, p = pcall(function() return cur.Parent end)
            if not ok or not p or p == game then break end
            cur = p
        end
    end

    -- last resort: nearest soldier_model in cache
    local best, bestD = nil, 25
    for obj in pairs(modelCache) do
        local root = obj:FindFirstChild("HumanoidRootPart")
        if root then
            local d = (root.Position - cam.CFrame.Position).Magnitude
            if d < bestD then bestD=d; best=obj end
        end
    end
    myModelCached = best; return best
end

local function getFLTeam(model)
    local attr = model:GetAttribute("Team") or model:GetAttribute("TeamName")
                 or model:GetAttribute("TeamId") or model:GetAttribute("Side")
    if attr then return tostring(attr) end
    for _, v in ipairs(model:GetChildren()) do
        local n = v.Name:lower()
        if (n=="team" or n=="teamname" or n=="side") and v:IsA("StringValue") then return v.Value end
    end
    if model.Parent and model.Parent ~= workspace then return model.Parent.Name end
    return nil
end

local function getFLName(model)
    local attr = model:GetAttribute("PlayerName") or model:GetAttribute("Username")
    if attr then return tostring(attr) end
    for _, v in ipairs(model:GetChildren()) do
        if (v.Name=="PlayerName" or v.Name=="Username") and v:IsA("StringValue") then return v.Value end
    end
    return model.Name == "soldier_model" and "Soldier" or model.Name
end

-- // ════════════════ BIG PAINTBALL ══════════════════════════ //
-- Bullets travel at `velocity` studs/s and fall under workspace.Gravity.
-- Drop over distance d: drop = 0.5 * g * (d/v)².
-- We compensate by aiming that many studs ABOVE the target.
--
-- Gun module patch: require() caches module tables in the executor's Lua VM.
-- Mutating the returned table changes what every subsequent require() sees,
-- including the game's own LocalScripts — so patching velocity here makes
-- the game actually fire bullets faster, not just our internal prediction.

local BP_GUN_VELOCITY = 235  -- updated on startup by patchBPGun if patch_velocity = true

local function patchBPGun()
    if not IS_BP then return end
    local rs  = game:GetService("ReplicatedStorage")
    local ok, mod = pcall(require,
        rs.Game.Guns["1 - Default"]["guns | Default"])
    if not ok or type(mod) ~= "table" then
        warn("[NEXUS BP] require failed:", mod); return
    end
    if cfg.bp.patch_velocity then
        mod.velocity    = cfg.bp.patched_vel
        BP_GUN_VELOCITY = cfg.bp.patched_vel
    end
    if cfg.bp.patch_auto then
        mod.automatic = true
        mod.shotrate  = 0.05
    end
    print(string.format("[NEXUS BP] gun patched — vel=%d  auto=%s",
        mod.velocity, tostring(mod.automatic)))
end

-- // ════════ UNIVERSAL TEAM DETECTION ══════════════ //
-- Collects team signals from 7 methods, keyed so only like-for-like
-- comparisons fire (rteam vs rteam, pa_team vs pa_team, etc.).
-- Keys are deliberately narrow — only genuine team-division terms.
-- "class", "group", "guild", "party" etc. are excluded because
-- they are common non-team stats that cause false positives.
-- Folder grouping is excluded for players (all chars often share
-- one workspace folder). sigMatch also rejects uninformative values.

-- only terms that unambiguously describe which team a player is on
local TEAM_KEYS = { "team", "teamname", "teamid", "side", "faction" }

-- values that represent "not set yet" — never use these as match signals
local JUNK_VALS = { [""] = true, ["0"] = true, ["none"] = true,
                    ["null"] = true, ["false"] = true, ["n/a"] = true }

local teamSigCache = {}   -- [plr|model] = { s={signals}, t=tick() }
local SIG_TTL = 1.5       -- recheck at most every 1.5 s

local function addSig(s, key, raw)
    if raw == nil then return end
    local v = tostring(raw):lower():match("^%s*(.-)%s*$")  -- trim whitespace
    if v == "" or JUNK_VALS[v] then return end              -- discard non-informative
    s[key] = v
end

local function collectSignals(plr, char)
    local s = {}

    -- 1. Roblox built-in Teams service (highest authority)
    if plr and plr:IsA("Player") and plr.Team then
        addSig(s, "rteam", plr.Team.Name)
    end

    -- 2. Player.TeamColor BrickColor number
    --    194 = medium stone grey = Roblox "no team" default → skip
    if plr and plr:IsA("Player") then
        local ok, tc = pcall(function() return plr.TeamColor end)
        if ok and tc and tc.Number ~= 194 then
            addSig(s, "rcolor", tc.Number)
        end
    end

    -- 3. Attributes on the Player object  (e.g. :GetAttribute("Team"))
    if plr then
        for _, k in ipairs(TEAM_KEYS) do
            local v = plr:GetAttribute(k)
                   or plr:GetAttribute(k:sub(1,1):upper()..k:sub(2))
            addSig(s, "pa_"..k, v)
        end
    end

    -- 4. StringValue / IntValue children directly inside Player
    if plr then
        for _, inst in ipairs(plr:GetChildren()) do
            local n = inst.Name:lower()
            if inst:IsA("StringValue") or inst:IsA("IntValue") then
                for _, k in ipairs(TEAM_KEYS) do
                    if n == k then addSig(s, "pv_"..k, inst.Value) end
                end
            end
        end
    end

    -- 5. leaderstats — only look for the exact team-related keys, nothing else
    if plr then
        local ls = plr:FindFirstChild("leaderstats")
        if ls then
            for _, inst in ipairs(ls:GetChildren()) do
                local n = inst.Name:lower()
                if inst:IsA("StringValue") or inst:IsA("IntValue") then
                    for _, k in ipairs(TEAM_KEYS) do
                        if n == k then addSig(s, "ls_"..k, inst.Value) end
                    end
                end
            end
        end
    end

    -- 6. Attributes on the Character model
    if char then
        for _, k in ipairs(TEAM_KEYS) do
            local v = char:GetAttribute(k)
                   or char:GetAttribute(k:sub(1,1):upper()..k:sub(2))
            addSig(s, "ca_"..k, v)
        end
    end

    -- 7. StringValue / IntValue children inside Character
    if char then
        for _, inst in ipairs(char:GetChildren()) do
            local n = inst.Name:lower()
            if inst:IsA("StringValue") or inst:IsA("IntValue") then
                for _, k in ipairs(TEAM_KEYS) do
                    if n == k then addSig(s, "cv_"..k, inst.Value) end
                end
            end
        end
    end

    -- 8. Character dominant part-colour fingerprint
    -- Scan solid BaseParts and average their hue. Paintball / team games paint
    -- entire characters in team colours, so the average hue is a very reliable
    -- per-team signal — two Red players will both produce "red"; two Blue players
    -- will both produce "blue". Only counts parts with meaningful saturation so
    -- grey/white/black (weapons, default skin tone) don't pollute the average.
    if char then
        local sumH, n = 0, 0
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency < 0.5 then
                local h, sv, v = Color3.toHSV(part.Color)
                if sv > 0.25 and v > 0.25 then
                    sumH = sumH + h; n = n + 1
                end
            end
        end
        if n >= 3 then
            local avgH = sumH / n
            local hue
            if     avgH < 0.042 or avgH >= 0.958 then hue = "red"
            elseif avgH < 0.125 then hue = "orange"
            elseif avgH < 0.208 then hue = "yellow"
            elseif avgH < 0.458 then hue = "green"
            elseif avgH < 0.625 then hue = "cyan"
            elseif avgH < 0.792 then hue = "blue"
            elseif avgH < 0.875 then hue = "purple"
            else                     hue = "magenta" end
            addSig(s, "partcolor", hue)
        end
    end

    -- 9. Workspace ancestor folder name
    -- Some games place characters in team-named Folders one level up from
    -- workspace, e.g. workspace.RedTeam.Character or workspace.Blue.Char.
    -- Shared catch-all folders ("Players", "Characters", "NPCs") are skipped
    -- so they don't make every character look like a teammate.
    if char then
        local par = char.Parent
        if par and par ~= workspace and par ~= game and par:IsA("Folder") then
            local pn = par.Name:lower():gsub("%s+", "")
            local skip = { players=true, characters=true, npcs=true,
                           models=true, entities=true, units=true }
            if pn ~= "" and not skip[pn] then
                addSig(s, "wsfolder", pn)
            end
        end
    end

    -- 10. Overhead BillboardGui on Head
    -- Many games attach a nametag BillboardGui to the character's Head.
    -- The TextLabel inside often contains the team name, or its BackgroundColor3
    -- / TextColor3 is set to the team colour. Both text content and hue-bucketed
    -- colours are extracted so sigMatch can fire on either signal.
    if char then
        local head = char:FindFirstChild("Head")
        if head then
            local function hueKey(c3)
                local h, sv = Color3.toHSV(c3)
                if sv < 0.25 then return nil end   -- skip near-grey
                if     h < 0.042 or h >= 0.958 then return "red"
                elseif h < 0.208 then return "warm"
                elseif h < 0.458 then return "green"
                elseif h < 0.625 then return "cyan"
                elseif h < 0.792 then return "blue"
                else                   return "purple" end
            end
            for _, gui in ipairs(head:GetChildren()) do
                if gui:IsA("BillboardGui") then
                    for _, elem in ipairs(gui:GetDescendants()) do
                        if elem:IsA("TextLabel") or elem:IsA("TextButton") then
                            local txt = elem.Text:lower():match("^%s*(.-)%s*$")
                            if txt ~= "" and #txt < 40 then
                                addSig(s, "nametag", txt)
                            end
                            if elem.BackgroundTransparency < 0.7 then
                                local k = hueKey(elem.BackgroundColor3)
                                if k then addSig(s, "nametag_bg", k) end
                            end
                            local k = hueKey(elem.TextColor3)
                            if k then addSig(s, "nametag_txt", k) end
                        end
                    end
                end
            end
        end
    end

    return s
end

-- same team only if a named signal key produces the same non-junk value in both
local function sigMatch(a, b)
    for k, v in pairs(a) do
        if b[k] ~= nil and b[k] == v then return true end
    end
    return false
end

local function getSignals(cacheKey, plr, char)
    local c = teamSigCache[cacheKey]
    if c and (tick() - c.t) < SIG_TTL then return c.s end
    local s = collectSignals(plr, char)
    teamSigCache[cacheKey] = {s=s, t=tick()}
    return s
end

-- evict cache on player leave to avoid memory leak
conn(Players.PlayerRemoving:Connect(function(p) teamSigCache[p] = nil end))

-- // ══════════ TARGET LOCK + PREDICTION ═════════════ //
--
-- lockedKey  — the current locked-on target (player or model).
--              nil = no lock. set on first valid FOV target found.
--              cleared when: key released, target dies, target leaves screen.
--
-- velHistory — per-target velocity history used to compute acceleration.
--              prediction = pos + vel*tof + 0.5*accel*tof^2
--              where tof = dist / pred_speed (time of flight estimate).
--              this handles targets that are accelerating (jumping, strafing),
--              not just coasting at constant velocity.

local lockedKey    = nil
local lockedPart   = nil  -- the part name currently being aimed at (updated per-frame)
local tsFlickStart = nil  -- tick() when trickshot flick began
local tsFlickLook  = nil  -- cam LookVector at the moment flick was initiated
local prevAimDown  = false
local velHistory   = {}    -- [key] = { v=Vector3, t=number }
local trigBusy     = false
local aimToggled   = false
local partVisCache = {}    -- [key] = { part=name, t=tick() } — smart part cache
local PART_VIS_TTL = 0.08  -- re-evaluate visible parts ~every 5 frames

-- exponential moving-average filter for dx/dy
-- absorbs sudden recoil spikes so the aimbot doesn't chase them
-- alpha 0.70 = 70% new / 30% history. high enough to be responsive,
-- low enough that a single-frame spike (gun recoil) only moves us 70%
-- of the way instead of the full jolt — keeps tracking visually smooth.
local filtX, filtY = 0, 0
local FILT_ALPHA   = 0.35  -- lower = less phase lag = less orbital drift
-- shared between BindToRenderStep (writer) and RenderStepped post-pass (reader).
-- cleared by the post-pass each frame; set only when the aimbot is actively aiming.
local fps_aimPos, fps_alpha

local function isAimActive()
    if cfg.aim.toggle_mode and aimToggled then return true end
    return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
end

local function getCharData(key)
    if not key then return nil end
    local ok, _ = pcall(function() return key.Parent end)
    if not ok then return nil end
    if typeof(key) == "Instance" and key:IsA("Model") then
        local root = key:FindFirstChild("HumanoidRootPart")
        local hum  = key:FindFirstChildOfClass("Humanoid")
        local head = key:FindFirstChild("Head")
        return key, root, hum, head
    else
        local char = key.Character
        if not char then return nil end
        local root = char:FindFirstChild("HumanoidRootPart")
        local hum  = char:FindFirstChildOfClass("Humanoid")
        local head = char:FindFirstChild("Head")
        return char, root, hum, head
    end
end

-- single source of truth for "is this humanoid a valid target"
-- Health > 0 alone isn't enough: some games leave Health at a tiny float
-- after death while the Died state fires immediately. checking both
-- covers that edge case and any race between the two properties.
local function isAlive(hum)
    if not hum then return false end
    if hum.Health <= 0 then return false end
    if hum:GetState() == Enum.HumanoidStateType.Dead then return false end
    return true
end

local function isLockValid()
    if not lockedKey then return false end
    local char, root, hum
    if IS_FL and typeof(lockedKey) ~= "Instance" or
       IS_FL and typeof(lockedKey) == "Instance" and lockedKey:IsA("Player") then
        -- FL: get the real workspace character, not StarterCharacter
        local plr = lockedKey
        char = getFLChar(plr)
        root = char and char:FindFirstChild("HumanoidRootPart")
        hum  = char and char:FindFirstChildOfClass("Humanoid")
    else
        char, root, hum = getCharData(lockedKey)
    end
    if not (char and root) then return false end
    if not IS_FL and not isAlive(hum) then return false end
    local _, onScreen = cam:WorldToViewportPoint(root.Position)
    return onScreen
end

local function predictedPos(key, root)
    local now = tick()
    local vel = root.AssemblyLinearVelocity
    local dist = (cam.CFrame.Position - root.Position).Magnitude
    local tof  = dist / math.max(cfg.aim.pred_speed, 50)

    -- acceleration from velocity derivative
    local accel = Vector3.new(0, 0, 0)
    local hist  = velHistory[key]
    if hist then
        local dt = now - hist.t
        if dt > 0.001 and dt < 0.15 then
            accel = (vel - hist.v) / dt
        end
    end
    velHistory[key] = { v = vel, t = now }

    -- pos + vel*tof + 0.5*accel*tof^2
    local lead = root.Position
        + vel   * tof * cfg.aim.pred_mult
        + accel * tof * tof * 0.5 * cfg.aim.pred_mult

    return lead
end

-- // ════════════════ BOX ESP ═════════════════════════ //

local function newBox()
    local out, ln = {}, {}
    for i = 1, 4 do
        out[i] = D("Line", {Visible=false, Color=BLACK, Thickness=3.5})
        ln[i]  = D("Line", {Visible=false, Color=WHITE, Thickness=1.5})
    end
    return {out=out, ln=ln}
end

local function applyBox(box, bx, by, bw, bh, col, show)
    local edges = {
        {Vector2.new(bx,    by),    Vector2.new(bx+bw, by)   },
        {Vector2.new(bx,    by+bh), Vector2.new(bx+bw, by+bh)},
        {Vector2.new(bx,    by),    Vector2.new(bx,    by+bh) },
        {Vector2.new(bx+bw, by),    Vector2.new(bx+bw, by+bh) },
    }
    for i, e in ipairs(edges) do
        box.out[i].From=e[1]; box.out[i].To=e[2]; box.out[i].Visible=show
        box.ln[i].From=e[1];  box.ln[i].To=e[2];  box.ln[i].Color=col; box.ln[i].Visible=show
    end
end

local function hideBox(box)
    for i = 1, 4 do box.out[i].Visible=false; box.ln[i].Visible=false end
end

local function newCornerBox()
    local out, ln = {}, {}
    for i=1,8 do
        out[i]=D("Line",{Visible=false,Color=BLACK,Thickness=3})
        ln[i] =D("Line",{Visible=false,Color=WHITE,Thickness=1.5})
    end
    return {out=out,ln=ln}
end

local function applyCornerBox(cb,bx,by,bw,bh,col,show)
    local cl=math.max(bw,bh)*0.22
    local pts={
        {Vector2.new(bx,by),       Vector2.new(bx+cl,by)},
        {Vector2.new(bx,by),       Vector2.new(bx,by+cl)},
        {Vector2.new(bx+bw,by),    Vector2.new(bx+bw-cl,by)},
        {Vector2.new(bx+bw,by),    Vector2.new(bx+bw,by+cl)},
        {Vector2.new(bx,by+bh),    Vector2.new(bx+cl,by+bh)},
        {Vector2.new(bx,by+bh),    Vector2.new(bx,by+bh-cl)},
        {Vector2.new(bx+bw,by+bh), Vector2.new(bx+bw-cl,by+bh)},
        {Vector2.new(bx+bw,by+bh), Vector2.new(bx+bw,by+bh-cl)},
    }
    for i,pt in ipairs(pts) do
        cb.out[i].From=pt[1]; cb.out[i].To=pt[2]; cb.out[i].Visible=show
        cb.ln[i].From=pt[1];  cb.ln[i].To=pt[2];  cb.ln[i].Color=col; cb.ln[i].Visible=show
    end
end

local function hideCornerBox(cb)
    for i=1,8 do cb.out[i].Visible=false; cb.ln[i].Visible=false end
end

-- // ═══════════════════ ESP POOL ════════════════════ //

local SKEL = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
}

local pool     = {}
local visCache = {}

local function newESPObj()
    return {
        box      = newBox(),
        cb       = newCornerBox(),
        lockfill = D("Square",{Visible=false,Color=GOLD,Filled=true,Transparency=0.88,Thickness=0}),
        name_bg  = D("Square",{Visible=false,Color=Color3.fromRGB(0,0,0),Filled=true,Transparency=0.5,Thickness=0}),
        name     = D("Text",  {Visible=false,Color=WHITE,Size=13,Center=true,Outline=true,OutlineColor=BLACK}),
        hp_bg    = D("Square",{Visible=false,Color=Color3.fromRGB(10,10,10),Filled=true,Thickness=0}),
        hp_fill  = D("Square",{Visible=false,Color=Color3.fromRGB(0,220,80),Filled=true,Thickness=0}),
        hp_pct   = D("Text",  {Visible=false,Color=WHITE,Size=9,Center=true,Outline=true,OutlineColor=BLACK}),
        tracer   = D("Line",  {Visible=false,Color=WHITE,Thickness=1,Transparency=0.4}),
        dist     = D("Text",  {Visible=false,Color=Color3.fromRGB(190,190,190),Size=10,Center=true,Outline=true,OutlineColor=BLACK}),
        skel     = (function()
            local t={}
            for i=1,#SKEL do t[i]=D("Line",{Visible=false,Color=WHITE,Thickness=1,Transparency=0.4}) end
            return t
        end)(),
        hl       = nil,  -- Highlight instance, assigned in registerESP
    }
end

destroyESP = function(key)
    local o=pool[key]; if not o then return end
    hideBox(o.box); hideCornerBox(o.cb)
    for i=1,4 do
        pcall(function() o.box.out[i]:Remove() end); pcall(function() o.box.ln[i]:Remove() end)
        pcall(function() o.cb.out[i]:Remove()  end); pcall(function() o.cb.ln[i]:Remove()  end)
    end
    for i=5,8 do pcall(function() o.cb.out[i]:Remove() end); pcall(function() o.cb.ln[i]:Remove() end) end
    pcall(function() o.lockfill:Remove() end)
    for _,k in ipairs({"name_bg","name","hp_bg","hp_fill","hp_pct","tracer","dist"}) do
        pcall(function() o[k]:Remove() end)
    end
    for _,ln in ipairs(o.skel) do pcall(function() ln:Remove() end) end
    if o.hl then pcall(function() o.hl:Destroy() end) end
    pool[key]=nil; visCache[key]=nil
    if lockedKey == key then lockedKey = nil end
end

local function registerESP(key)
    if pool[key] then return end
    pool[key]     = newESPObj()
    visCache[key] = {vis=true, last=0}
    -- native 3D outline — Highlight follows every limb automatically
    local hl = Instance.new("Highlight")
    hl.FillTransparency    = 1    -- no shaded fill, outline ring only
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop  -- visible through walls
    hl.Enabled   = false
    hl.Parent    = hlContainer
    pool[key].hl = hl
end

local function hideESP(o)
    if not o then return end
    hideBox(o.box); hideCornerBox(o.cb)
    o.lockfill.Visible=false
    o.name_bg.Visible=false; o.name.Visible=false
    o.hp_bg.Visible=false; o.hp_fill.Visible=false; o.hp_pct.Visible=false
    o.tracer.Visible=false; o.dist.Visible=false
    for _,ln in ipairs(o.skel) do ln.Visible=false end
    if o.hl then o.hl.Enabled=false end
end

local function getBounds(root, head, model)
    local topY, botY
    if IS_FL and model then
        -- FL: hardcoded offsets from HRP are wrong when crouching — HRP anchor
        -- doesn't move proportionally as the mesh parts lower. scan every BasePart
        -- child for the real occupied Y range so the box shrinks correctly.
        topY = -math.huge
        botY =  math.huge
        for _, part in ipairs(model:GetChildren()) do
            if part:IsA("BasePart") then
                local halfH = part.Size.Y * 0.5
                local py    = part.Position.Y
                if py + halfH > topY then topY = py + halfH end
                if py - halfH < botY then botY = py - halfH end
            end
        end
        -- no parts found (race condition on spawn) — fall through to defaults
        if topY == -math.huge then
            topY = head and (head.Position.Y + head.Size.Y*0.55) or (root.Position.Y + 3.2)
            botY = root.Position.Y - 2.8
        end
    else
        topY = head and (head.Position.Y + head.Size.Y*0.55) or (root.Position.Y + 3.2)
        botY = root.Position.Y - 2.8
    end
    local cx, cz = root.Position.X, root.Position.Z
    local cr  = cam.CFrame.RightVector
    local rxz = Vector3.new(cr.X, 0, cr.Z)
    if rxz.Magnitude < 0.01 then rxz = Vector3.new(1,0,0) else rxz = rxz.Unit end
    local mid  = (topY + botY) * 0.5
    local topS = cam:WorldToViewportPoint(Vector3.new(cx, topY, cz))
    local botS = cam:WorldToViewportPoint(Vector3.new(cx, botY, cz))
    local lS   = cam:WorldToViewportPoint(Vector3.new(cx - rxz.X*1.35, mid, cz - rxz.Z*1.35))
    local rS   = cam:WorldToViewportPoint(Vector3.new(cx + rxz.X*1.35, mid, cz + rxz.Z*1.35))
    local bx = lS.X; local by = topS.Y
    local bw = math.max(rS.X - lS.X, 8); local bh = math.max(botS.Y - topS.Y, 8)
    return bx, by, bw, bh
end

local function drawESP(key, char, hum, root, head, label)
    local o = pool[key]; if not o then return end
    local rsp, onScreen = cam:WorldToViewportPoint(root.Position)
    if not onScreen then hideESP(o); return end

    local bx, by, bw, bh = getBounds(root, head, IS_FL and char or nil)
    local dst = (cam.CFrame.Position - root.Position).Magnitude
    local now = tick()

    -- distance fade: compute opacity multiplier (1=full, 0=gone)
    local fadeAlpha = 1.0
    if cfg.esp.dist_fade then
        local span = math.max(cfg.esp.fade_end - cfg.esp.fade_start, 1)
        fadeAlpha = 1.0 - math.clamp((dst - cfg.esp.fade_start) / span, 0, 1)
        if fadeAlpha < 0.02 then hideESP(o); return end
    end

    local vc = visCache[key]
    if not vc or (now - vc.last) >= 0.15 then
        visCache[key] = {vis=wallCheck(char, root.Position), last=now}
        vc = visCache[key]
    end

    local isLocked = (lockedKey == key)
    local col
    if isLocked then
        col = GOLD
    elseif cfg.esp.rainbow then
        col = Color3.fromHSV((now * 0.35) % 1, 1, 1)
    elseif vc.vis then
        col = Color3.fromRGB(235, 75, 75)
    else
        col = Color3.fromRGB(75, 115, 255)
    end

    -- 3D avatar outline (native Highlight instance)
    if o.hl then
        if cfg.esp.outline then
            o.hl.Adornee       = char
            o.hl.OutlineColor  = col
            o.hl.Enabled       = true
        else
            o.hl.Enabled = false
        end
    end

    -- lock fill highlight
    if isLocked then
        o.lockfill.Position=Vector2.new(bx,by); o.lockfill.Size=Vector2.new(bw,bh); o.lockfill.Visible=true
    else
        o.lockfill.Visible=false
    end

    if cfg.esp.box then
        applyBox(o.box, bx, by, bw, bh, col, true)
    else hideBox(o.box) end

    if cfg.esp.corners then
        applyCornerBox(o.cb, bx, by, bw, bh, col, true)
    else hideCornerBox(o.cb) end

    if cfg.esp.names then
        local nameY = by - 20
        local tw    = math.max(40, #label*6+10)
        o.name_bg.Size=Vector2.new(tw,16); o.name_bg.Position=Vector2.new(rsp.X-tw*0.5,nameY); o.name_bg.Visible=true
        o.name.Text=label; o.name.Position=Vector2.new(rsp.X, nameY); o.name.Color=col; o.name.Visible=true
    else o.name_bg.Visible=false; o.name.Visible=false end

    if cfg.esp.health and type(hum) ~= "boolean" then
        local pct  = math.clamp(hum.Health/hum.MaxHealth, 0, 1)
        local barH = bh * pct
        local barX = bx - 7
        local r    = math.min(1, 2*(1-pct)); local g = math.min(1, 2*pct)
        o.hp_bg.Position=Vector2.new(barX,by); o.hp_bg.Size=Vector2.new(3,bh); o.hp_bg.Visible=true
        o.hp_fill.Color=Color3.new(r,g,0.1)
        o.hp_fill.Position=Vector2.new(barX, by+bh-barH); o.hp_fill.Size=Vector2.new(3,barH); o.hp_fill.Visible=true
        if pct < 0.999 then
            o.hp_pct.Text=math.floor(pct*100).."%"
            o.hp_pct.Position=Vector2.new(barX+1, by+bh+2)
            o.hp_pct.Color=Color3.new(r,g,0.1); o.hp_pct.Visible=true
        else o.hp_pct.Visible=false end
    else o.hp_bg.Visible=false; o.hp_fill.Visible=false; o.hp_pct.Visible=false end

    if cfg.esp.tracers then
        o.tracer.From=Vector2.new(cam.ViewportSize.X*0.5, cam.ViewportSize.Y)
        o.tracer.To=Vector2.new(rsp.X, rsp.Y); o.tracer.Color=col; o.tracer.Visible=true
    else o.tracer.Visible=false end

    if cfg.esp.distance then
        o.dist.Text=string.format("[%.0fm]", dst)
        o.dist.Position=Vector2.new(rsp.X, by+bh+4); o.dist.Visible=true
    else o.dist.Visible=false end

    if cfg.esp.skeleton then
        for i, pair in ipairs(SKEL) do
            local p1=char:FindFirstChild(pair[1]); local p2=char:FindFirstChild(pair[2])
            local ln=o.skel[i]
            if p1 and p2 then
                local s1,ok1=cam:WorldToViewportPoint(p1.Position)
                local s2,ok2=cam:WorldToViewportPoint(p2.Position)
                if ok1 and ok2 then
                    ln.From=Vector2.new(s1.X,s1.Y); ln.To=Vector2.new(s2.X,s2.Y)
                    ln.Color=col; ln.Visible=true
                else ln.Visible=false end
            else ln.Visible=false end
        end
    else for _,ln in ipairs(o.skel) do ln.Visible=false end end

    -- distance fade: scale every visible drawing element toward transparent
    if fadeAlpha < 0.999 then
        local inv = 1 - fadeAlpha
        local function fd(d, base)
            if d and d.Visible then d.Transparency = 1-(1-base)*fadeAlpha end
        end
        fd(o.lockfill, 0.12); fd(o.name_bg, 0.5); fd(o.name, 0)
        fd(o.hp_bg, 0); fd(o.hp_fill, 0); fd(o.hp_pct, 0)
        fd(o.tracer, 0.4); fd(o.dist, 0)
        for _, ln in ipairs(o.skel) do fd(ln, 0.4) end
        for i = 1, 4 do
            if o.box.ln[i].Visible  then o.box.ln[i].Transparency  = inv end
            if o.box.out[i].Visible then o.box.out[i].Transparency = inv end
            if o.cb.ln[i].Visible   then o.cb.ln[i].Transparency   = inv end
            if o.cb.out[i].Visible  then o.cb.out[i].Transparency  = inv end
        end
        for i = 5, 8 do
            if o.cb.ln[i].Visible  then o.cb.ln[i].Transparency  = inv end
            if o.cb.out[i].Visible then o.cb.out[i].Transparency = inv end
        end
    end
end

-- // ════════════════ ESP TICK ════════════════════════ //

local function tickESP()
    local now = tick()
    if (IS_FL or cfg.misc.npc_mode) and (now - cacheRebuildT) >= 3 then
        cacheRebuildT = now
        task.spawn(rebuildModelCache)
    end

    if not cfg.esp.enabled then
        for _, o in pairs(pool) do hideESP(o) end
        return
    end

    -- draw ESP for real players (universal mode only — FL uses modelCache soldier_models)
    if not IS_FL then for plr in pairs(pool) do
        if typeof(plr) ~= "Instance" or not plr:IsA("Player") then continue end
        local char = IS_FL and getFLChar(plr) or plr.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and (IS_FL and flHead(char) or char:FindFirstChild("Head"))
        if not (char and root) then hideESP(pool[plr]); continue end
        if not IS_FL and not isAlive(hum) then hideESP(pool[plr]); continue end
        if IS_DEADWORLD and char.Name == "HumanBody" then hideESP(pool[plr]); continue end
        if IS_FL and cfg.esp.team_check then
            if isFLTeammate(plr) then hideESP(pool[plr]); continue end
        elseif cfg.esp.team_check then
            local mine  = getSignals(lp,  lp,  lp.Character)
            local their = getSignals(plr, plr, char)
            if next(mine) and sigMatch(mine, their) then hideESP(pool[plr]); continue end
        end
        drawESP(plr, char, hum, root, head, plr.DisplayName)
    end end  -- closes the `if not IS_FL then` and loop

    -- draw ESP for soldier_model modelCache in FL mode, NPC models in npc_mode
    if IS_FL or cfg.misc.npc_mode then
        local myModel = IS_FL and getLocalFLModel() or lp.Character
        -- FL uses friendly_marker child for team detection — getFLTeam attribute
        -- scanning returns garbage in Frontlines so myTeam is only for npc_mode games.
        local myTeam  = (not IS_FL and myModel) and getFLTeam(myModel) or nil
        local active  = {}

        for obj in pairs(modelCache) do
            if obj == myModel then continue end
            if IS_DEADWORLD and obj.Name == "HumanBody" then continue end
            local root = obj:FindFirstChild("HumanoidRootPart")
            -- FL: Humanoid is not always a direct child of soldier_model.
            -- don't require it for visibility — use root existence as alive signal.
            local hum  = obj:FindFirstChildOfClass("Humanoid")
            if not root then continue end
            registerESP(obj); active[obj] = true
            -- FL alive check: model still parented = alive. game removes on death.
            if IS_FL then
                if not obj.Parent then hideESP(pool[obj]); continue end
            else
                if not (hum and isAlive(hum)) then hideESP(pool[obj]); continue end
            end
            if IS_FL and cfg.esp.team_check then
                if obj:FindFirstChild("friendly_marker") then hideESP(pool[obj]); continue end
            elseif cfg.esp.team_check and myTeam then
                local their = getFLTeam(obj)
                if their and their == myTeam then hideESP(pool[obj]); continue end
            end
            local head = IS_FL and flHead(obj) or obj:FindFirstChild("Head")
            drawESP(obj, obj, hum or true, root, head, getFLName(obj))
        end

        for key in pairs(pool) do
            if typeof(key)=="Instance" and key:IsA("Model") and not active[key] then
                destroyESP(key)
            end
        end
    end
end

-- register real players for universal mode; FL uses modelCache soldier_models
if not IS_FL then
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp then registerESP(p) end
    end
    conn(Players.PlayerAdded:Connect(function(p) if p ~= lp then registerESP(p) end end))
    conn(Players.PlayerRemoving:Connect(destroyESP))
end
-- seed model cache for FL soldier_models and npc_mode
if IS_FL or cfg.misc.npc_mode then
    rebuildModelCache()
    for obj in pairs(modelCache) do registerESP(obj) end
end

-- BP: patch gun module on a deferred thread so the game's own require cache
-- is already populated before we mutate it (avoids a load-order race).
if IS_BP then task.defer(patchBPGun) end

conn(RunService.RenderStepped:Connect(tickESP))

-- // ════════════════ AIMBOT ══════════════════════════ //

local fovCircle  = D("Circle",{Visible=false,Radius=150,Color=WHITE,Thickness=1,Filled=false,Transparency=0.75})
local lockCircle = D("Circle",{Visible=false,Radius=6,Color=GOLD,Thickness=1.5,Filled=false,Transparency=0.3})
local chH = D("Line",{Visible=false,Color=RED,Thickness=1})
local chV = D("Line",{Visible=false,Color=RED,Thickness=1})

-- // ── Aim Modes ─────────────────────────────────────
--
--  Smooth   — gradual per-frame tracking with adaptive speed:
--             when crosshair is far from target, use full smooth.
--             as it closes in (< 30px), taper down so it snaps
--             clean instead of orbiting. no more endless circling.
--
--  Flick    — single instant snap on the rising edge of the aim key.
--             does nothing while held. classic quickscope/flick.
--
--  Rage     — continuous full-speed lock every frame. zero mercy.
--
--  Human    — smooth with sinusoidal micro-drift on top to break
--             the perfectly linear movement signature.
--
-- Target Lock:
--  once aim key is pressed and a target is found, that target is
--  locked. even if someone walks in front of your FOV circle, the
--  aimbot ignores them and stays on the original target. lock is
--  cleared only when: target dies · leaves screen · aim key released.
--  locked target turns gold in ESP.
--
-- Prediction:
--  pos + vel*tof + 0.5*accel*tof^2
--  accel is computed from the derivative of AssemblyLinearVelocity
--  between frames, so it handles players who are accelerating mid-strafe,
--  not just coasting at constant speed.

-- ordered list of selectable body parts shown in the UI.
-- IDs must match Roblox R15 part names exactly.
local PART_OPTIONS = {
    {id="Head",             label="Head"},
    {id="UpperTorso",       label="Chest"},
    {id="LowerTorso",       label="Stomach"},
    {id="HumanoidRootPart", label="Root"},
    {id="LeftUpperArm",     label="L.Arm"},
    {id="RightUpperArm",    label="R.Arm"},
}

-- fallback priority list used when NONE of the configured parts are visible.
-- head is checked first (most exposed when peeking), then upper body, then limbs.
-- HumanoidRootPart is excluded — it's invisible and inside the torso.
local FALLBACK_PARTS = {
    "Head", "UpperTorso", "LowerTorso",
    "RightUpperArm", "LeftUpperArm",
    "RightUpperLeg", "LeftUpperLeg",
}

-- picks one active part at random from cfg.aim.target_parts.
-- called once when a lock is acquired, result stored in lockedPart
-- so the aim stays on the same body part for the entire engagement.
local function pickLockedPart()
    local active = {}
    for _, opt in ipairs(PART_OPTIONS) do
        if cfg.aim.target_parts[opt.id] then
            table.insert(active, opt.id)
        end
    end
    if #active == 0 then return "HumanoidRootPart" end
    return active[math.random(1, #active)]
end

local function findBestTarget()
    local center = Vector2.new(cam.ViewportSize.X*0.5, cam.ViewportSize.Y*0.5)
    local bestKey, bestDist, bestPos = nil, cfg.aim.fov, nil

    -- FOV check uses the Head position (eye level) — same as the original.
    -- root (HRP) sits 1-2 studs below the head; in first-person that puts
    -- it 50-80px lower on screen, so root-based FOV would silently drop
    -- targets whose head is inside the circle but waist falls outside.
    -- the randomly chosen aim part (lockedPart) is applied in getLockedPos,
    -- not here — this function's only job is to find the closest valid target.
    local function tryKey(key, char, root, hum, fovPart, skipAlive)
        if not root then return end
        -- skipAlive: FL mode — StarterCharacter Humanoid.Health may be 0 because
        -- Frontlines uses its own health system. trust char existence instead;
        -- the game destroys/replaces the character on actual death.
        if not skipAlive and not isAlive(hum) then return end
        -- in DeadWorld: skip the persistent corpse model left when players die.
        -- "HumanBody" has a live Humanoid so isAlive passes, but it's not a
        -- valid target — it's immune and counts as griefing the lock queue.
        if IS_DEADWORLD and char and char.Name == "HumanBody" then return end
        local checkPos = fovPart and fovPart.Position or root.Position
        if cfg.aim.vis_check and not wallCheck(char, checkPos) then return end
        local sp, onScreen = cam:WorldToViewportPoint(checkPos)
        if not onScreen then return end
        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
        if d < bestDist then
            bestDist=d; bestKey=key
            bestPos = cfg.aim.prediction and predictedPos(key, root) or checkPos
        end
    end

    -- scan real players (universal mode only — FL scans modelCache soldier_models below)
    if not IS_FL then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr == lp then continue end
            local char = plr.Character
            if cfg.aim.team_check then
                local mine  = getSignals(lp,  lp,  lp.Character)
                local their = getSignals(plr, plr, char)
                if next(mine) and sigMatch(mine, their) then continue end
            end
            local hum  = char and char:FindFirstChildOfClass("Humanoid")
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local head = char and char:FindFirstChild("Head")
            tryKey(plr, char, root, hum, head)
        end
    end

    -- scan modelCache: FL soldier_models + npc_mode NPCs
    if IS_FL or cfg.misc.npc_mode then
        local myModel = IS_FL and getLocalFLModel() or lp.Character
        local myTeam  = (not IS_FL and myModel) and getFLTeam(myModel) or nil
        for obj in pairs(modelCache) do
            if obj == myModel then continue end
            if IS_DEADWORLD and obj.Name == "HumanBody" then continue end
            local root = obj:FindFirstChild("HumanoidRootPart")
            local hum  = obj:FindFirstChildOfClass("Humanoid")
            if not root then continue end
            -- FL alive: model parented = alive; game removes it on death
            if IS_FL and not obj.Parent then continue end
            if not IS_FL and not (hum and isAlive(hum)) then continue end
            if IS_FL and cfg.aim.team_check then
                if obj:FindFirstChild("friendly_marker") then continue end
            elseif cfg.aim.team_check and myTeam then
                local their = getFLTeam(obj)
                if their and their == myTeam then continue end
            end
            local head = IS_FL and flHead(obj) or obj:FindFirstChild("Head")
            tryKey(obj, obj, root, hum, head, IS_FL)
        end
    end

    return bestKey, bestPos
end

-- ─────────────────────────────────────────────────────────────────────────
-- pickSmartPart: visibility-aware part selector, evaluated every PART_VIS_TTL.
--
-- Logic:
--   Phase 0 — if the currently locked part is still visible AND still in the
--              configured set, keep it (stability: no random switching while
--              the target is wide open).
--   Phase 1 — configured parts no longer visible (target peeking behind cover).
--              scan PART_OPTIONS in order (Head→Chest→Stomach→…) and take the
--              first one that passes a raycast. head is naturally first so a
--              peeking target automatically gets head-targeted.
--   Phase 2 — none of the configured parts are visible at all (target stepped
--              fully into cover but lock is still valid). scan FALLBACK_PARTS
--              (head→upper torso→…) for any visible part — keeps the aim on
--              whatever fragment of the body is exposed.
--   Phase 3 — fully occluded. preserve last-known part so the aim doesn't
--              snap wildly; if the target re-emerges the cache will refresh.
-- ─────────────────────────────────────────────────────────────────────────
local function pickSmartPart(key, char, root)
    -- serve from cache if still fresh
    local cached = partVisCache[key]
    if cached and (tick() - cached.t) < PART_VIS_TTL then
        return char:FindFirstChild(cached.part) or root, cached.part
    end

    -- build a one-shot raycast params that ignores our own character
    local myChar = (IS_FL and getLocalFLModel) and getLocalFLModel() or lp.Character
    local ok, params = pcall(RaycastParams.new)
    if not ok then
        -- RaycastParams unavailable (unusual) — fall back gracefully
        local fallback = lockedPart or "HumanoidRootPart"
        return char:FindFirstChild(fallback) or root, fallback
    end
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = myChar and {myChar} or {}

    local origin = cam.CFrame.Position

    local function isVis(partName)
        local part = char:FindFirstChild(partName)
        if not part then return false end
        local result = workspace:Raycast(origin, part.Position - origin, params)
        if not result then return true end
        return char:IsAncestorOf(result.Instance)
            or result.Instance.Transparency >= 0.9
    end

    local function cache(partName)
        partVisCache[key] = {part=partName, t=tick()}
        return char:FindFirstChild(partName) or root, partName
    end

    -- Phase 0: current part still visible + still configured — keep it
    if lockedPart and cfg.aim.target_parts[lockedPart] and isVis(lockedPart) then
        return cache(lockedPart)
    end

    -- Phase 1: find first visible configured part (PART_OPTIONS order = Head first)
    for _, opt in ipairs(PART_OPTIONS) do
        if cfg.aim.target_parts[opt.id] and isVis(opt.id) then
            return cache(opt.id)
        end
    end

    -- Phase 2: no configured part visible — aim at whatever is exposed (head priority)
    for _, partName in ipairs(FALLBACK_PARTS) do
        if isVis(partName) then
            return cache(partName)
        end
    end

    -- Phase 3: fully behind cover — hold last known, don't thrash
    local last = lockedPart or "HumanoidRootPart"
    return cache(last)
end

local function getLockedPos()
    local char, root, hum, head
    if IS_FL and typeof(lockedKey) == "Instance" and lockedKey:IsA("Player") then
        char = getFLChar(lockedKey)
        root = char and char:FindFirstChild("HumanoidRootPart")
        hum  = char and char:FindFirstChildOfClass("Humanoid")
    else
        char, root, hum, head = getCharData(lockedKey)
    end
    if not (char and root) then return nil end
    local part, selectedName
    if IS_FL then
        part = root  -- HumanoidRootPart sits at centre-mass in FL soldier_models
    elseif typeof(lockedKey) == "Instance" and lockedKey:IsA("Model") then
        part = head or root
    else
        part, selectedName = pickSmartPart(lockedKey, char, root)
        lockedPart = selectedName
        part = part or root
    end
    if not part then return nil end
    local basePos
    if cfg.aim.prediction then
        local rootPred   = predictedPos(lockedKey, root)
        local partOffset = part.Position - root.Position
        basePos = rootPred + partOffset
    else
        basePos = part.Position
    end
    if IS_BP and cfg.bp.drop_comp then
        local dist = (cam.CFrame.Position - root.Position).Magnitude
        local tof  = dist / math.max(BP_GUN_VELOCITY, 1)
        basePos = basePos + Vector3.new(0, 0.5 * workspace.Gravity * tof * tof, 0)
    end
    return basePos
end

RunService:BindToRenderStep("NexusAim", 999999, function(dt)
-- priority 999999 — intentionally far above Enum.RenderPriority.Last (2000).
-- Roblox's OWN systems cap at 2000, but game scripts can bind at any value.
-- Sniper Arena appears to have a secondary scope-correction pass above 2000
-- that was still overriding us. 999999 ensures we are always the absolute
-- last writer before the frame flips, regardless of what the game does.
    local cx = cam.ViewportSize.X*0.5; local cy = cam.ViewportSize.Y*0.5
    local aimDown = isAimActive()

    fovCircle.Position=Vector2.new(cx,cy); fovCircle.Radius=cfg.aim.fov
    fovCircle.Visible=cfg.misc.fov_circle and cfg.aim.enabled

    if cfg.misc.crosshair then
        local s = cfg.misc.ch_size
        chH.From=Vector2.new(cx-s,cy); chH.To=Vector2.new(cx+s,cy); chH.Visible=true
        chV.From=Vector2.new(cx,cy-s); chV.To=Vector2.new(cx,cy+s); chV.Visible=true
    else chH.Visible=false; chV.Visible=false end

    -- release lock when aim key goes up, reset filter so stale values
    -- don't bleed into the next acquisition
    if not aimDown then
        if lockedKey then partVisCache[lockedKey] = nil end
        lockedKey          = nil
        lockedPart         = nil
        tsFlickStart       = nil
        tsFlickLook        = nil
        lockCircle.Visible = false
        prevAimDown        = false
        filtX, filtY       = 0, 0
        return
    end

    if not cfg.aim.enabled then
        prevAimDown = aimDown
        lockCircle.Visible = false
        return
    end

    -- acquire or validate lock
    if not isLockValid() then
        local hadLock = lockedKey ~= nil
        lockedKey = nil
        -- auto_switch: retarget immediately when locked enemy dies/leaves.
        -- if we never had a lock yet (fresh aim press), always try to acquire.
        if (not hadLock) or cfg.aim.auto_switch then
            local key, _ = findBestTarget()
            if key then
                lockedKey  = key
                lockedPart = nil         -- pickSmartPart determines this dynamically
                partVisCache[key] = nil  -- clear any stale cache for this target
                filtX, filtY = 0, 0
            end
        end
    end

    if not lockedKey then
        lockCircle.Visible = false
        prevAimDown = aimDown
        return
    end

    local pos = getLockedPos()
    if not pos then
        lockedKey = nil
        lockCircle.Visible = false
        prevAimDown = aimDown
        return
    end

    local sp, onScreen = cam:WorldToViewportPoint(pos)
    if not onScreen then
        lockCircle.Visible = false
        prevAimDown = aimDown
        return
    end

    -- use viewport CENTER as reference, not mouse cursor position.
    -- mouse.X + INSET shifts the reference by ~36px which creates a
    -- permanent non-zero error the aimbot endlessly chases → circular orbit.
    -- the camera always points at (cx, cy), so that's the correct anchor.
    local dx = sp.X - cx
    local dy = sp.Y - cy
    local dist2D = math.sqrt(dx*dx + dy*dy)

    -- skip micro-corrections inside 0.5px — sub-pixel, visually imperceptible.
    -- was 2px which is noticeable in zoomed scope views at sniper ranges.
    if dist2D < 0.5 then
        prevAimDown = aimDown
        return
    end

    -- update EMA filter — used by Smooth + Human to absorb recoil spikes
    filtX = filtX + (dx - filtX) * FILT_ALPHA
    filtY = filtY + (dy - filtY) * FILT_ALPHA

    -- lock indicator (small gold circle on target)
    lockCircle.Position = Vector2.new(sp.X, sp.Y)
    lockCircle.Visible  = true

    -- ── primary: cam.CFrame (third-person + fallback for all games) ─────
    -- directly writing cam.CFrame bypasses mouse sensitivity entirely.
    -- no oscillation possible because we skip the mouse pipeline.
    -- ──
    -- for FPS games (UIS.MouseBehavior == LockCenter): the game's camera
    -- script reads UIS:GetMouseDelta() each frame and rebuilds cam.CFrame
    -- from an internal accumulated look-angle. our CFrame write wins within
    -- BindToRenderStep at 999999, but if the game binds higher or uses
    -- RenderStepped:Connect() directly, their pass runs after ours.
    -- countermeasures:
    --   1. RenderStepped post-pass (below BindToRenderStep block) — fires
    --      LAST of all listeners, after every BindToRenderStep at any priority.
    --   2. mousemoverel proportional supplement — nudges the game's accumulated
    --      angle toward the target. proportional gain (1/(smooth*2)) keeps the
    --      feedback factor below 1 for any game sensitivity up to ~12, so
    --      the absolute-position oscillation described above cannot occur.
    -- ────────────────────────────────────────────────────────────────────

    local mode  = cfg.aim.mode
    local alpha = nil

    -- shared helper: framerate-independent exponential approach with
    -- angular boost. constant-rate lerp (alpha = 1/s every frame) is
    -- framerate-dependent — at 120fps it closes twice as fast as 60fps.
    -- 1 - exp(-dt * 60/s) gives the same convergence at any framerate.
    --
    -- angular boost: when the camera is far from the target it snaps in
    -- faster, then eases as it closes. this feels natural — quick initial
    -- pull, smooth settle. without boost the initial movement feels sluggish
    -- at high smooth values even though the settle is perfect.
    local function smoothAlpha(s, aimPos)
        -- base rate normalised to 60fps
        local rate = 1 - math.exp(-dt * 60 / s)
        -- angle between current look direction and target direction
        local toTarget = (aimPos - cam.CFrame.Position).Unit
        local dot      = math.clamp(cam.CFrame.LookVector:Dot(toTarget), -1, 1)
        local angleFrac = math.acos(dot) / math.pi  -- 0 = on target, 1 = 180° away
        -- boost peaks at 3× for a target directly behind, tapers to 1× on target
        local boost = 1 + angleFrac * 2
        return math.clamp(rate * boost, 0.005, 0.99)
    end

    if mode == "Smooth" then
        alpha = smoothAlpha(cfg.aim.smooth, pos)

    elseif mode == "Flick" then
        if not prevAimDown then alpha = 1 end

    elseif mode == "Rage" then
        alpha = 1 - math.exp(-dt * 60 / 1.5)
        alpha = math.clamp(alpha, 0.005, 0.99)

    elseif mode == "Human" then
        alpha = smoothAlpha(cfg.aim.smooth, pos)

    elseif mode == "Trickshot" then
        -- ── Trickshot mode ─────────────────────────────────────────────
        -- Inspired by the classic COD trickshot aimbot behaviour:
        --   1. On the RISING EDGE of the aim key, snapshot the current
        --      look direction and start a timed flick.
        --   2. Interpolate from that FIXED start direction → target using
        --      a cubic ease-out (fast at the start, slows into the mark).
        --   3. After the flick window closes, hold the camera exactly on
        --      target — no drift, no tracking jitter.
        --
        -- Why store the look direction at press-time instead of lerping
        -- the current camera each frame?  Because frame-by-frame lerp
        -- recomputes the starting point every tick, making the arc feel
        -- like a clumsy rubber-band chase.  Storing it once gives a clean,
        -- predictable curve — exactly the feel of the old BO2 bots.
        -- ────────────────────────────────────────────────────────────────
        if not prevAimDown then
            -- rising edge: latch the look direction right now
            tsFlickStart = tick()
            tsFlickLook  = cam.CFrame.LookVector
        end

        if tsFlickStart and tsFlickLook then
            local dur  = math.max(cfg.aim.ts_flick_dur, 0.02)
            local t    = math.clamp((tick() - tsFlickStart) / dur, 0, 1)

            -- cubic ease-out: f(t) = 1-(1-t)³
            -- at t=0.1 → 27% done, t=0.3 → 66%, t=0.5 → 87%, t=1 → 100%
            -- front-loads the movement so the first few frames feel explosive
            local ease = 1 - math.pow(1 - t, 3)

            -- build two CFrames with the same position (current cam pos)
            -- so Lerp only interpolates rotation, not position
            local startCF  = CFrame.new(cam.CFrame.Position,
                                        cam.CFrame.Position + tsFlickLook)
            local targetCF = CFrame.new(cam.CFrame.Position, pos)

            cam.CFrame = startCF:Lerp(targetCF, ease)
            fps_aimPos = pos; fps_alpha = ease
            -- FPS sync for trickshot: nudge accumulated look-angle toward target
            if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then
                pcall(mousemoverel,
                    math.clamp(filtX * 0.2, -100, 100),
                    math.clamp(filtY * 0.2, -100, 100))
            end
            -- alpha stays nil — camera is handled entirely above
        end
    end

    if alpha then
        local aimPos = pos

        if mode == "Human" then
            local drift = math.max(0.4, dist2D * 0.028)
            local now   = tick()
            local driftSp = Vector2.new(
                sp.X + math.sin(now * 11.7) * drift,
                sp.Y + math.cos(now *  8.3) * drift
            )
            local ray = cam:ScreenPointToRay(driftSp.X, driftSp.Y)
            aimPos = ray.Origin + ray.Direction * 500
        end

        local targetCF = CFrame.new(cam.CFrame.Position, aimPos)
        cam.CFrame = cam.CFrame:Lerp(targetCF, alpha)
        -- store for RenderStepped post-pass — see comment below BindToRenderStep
        fps_aimPos = aimPos; fps_alpha = alpha
        -- FPS supplement: in mouse-locked games the camera is driven by an
        -- internal accumulated look-angle that reads UIS:GetMouseDelta() each frame.
        -- Writing cam.CFrame directly doesn't update that state, so the game resets
        -- the camera next frame. Calling mousemoverel with a proportional gain nudges
        -- that accumulated angle toward our target — even if we lose the CFrame race,
        -- the game's own camera drifts toward us over a handful of frames.
        -- Gain formula: 1/(smooth*2) keeps gain*sensitivity < 1 for any realistic
        -- FPS sensitivity (tested stable up to sensitivity ≈ 12). No oscillation.
        if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then
            local mr_g = mode == "Rage" and 0.3 or math.min(0.35, 1 / (cfg.aim.smooth * 2))
            pcall(mousemoverel,
                math.clamp(filtX * mr_g, -100, 100),
                math.clamp(filtY * mr_g, -100, 100))
        end
    end

    -- triggerbot
    if cfg.aim.triggerbot and not trigBusy and dist2D < 20 then
        trigBusy=true; mouse1press()
        task.delay(0.05, function()
            mouse1release()
            task.delay(cfg.aim.trig_delay, function() trigBusy=false end)
        end)
    end

    prevAimDown = aimDown

    -- keep MB target synced with the aimbot lock every frame.
    -- this removes the timing race where the game's shot remote fires
    -- before our UIS.InputBegan handler runs — mbTargetRoot is always
    -- up-to-date by the time any remote call happens.
    if cfg.misc.magic_bullet then
        if lockedKey then
            local mc, mr = getCharData(lockedKey)
            mbTargetRoot = mr
            mbTargetChar = mc
        else
            mbTargetRoot = nil
            mbTargetChar = nil
        end
    end
end)

-- // ════════════════ FPS POST-PASS ══════════════════ //
-- RunService.RenderStepped:Connect callbacks fire AFTER all BindToRenderStep
-- callbacks complete (Roblox documented execution order). Connecting here —
-- post-injection, after the game has already set up its own connections —
-- means our callback runs LAST in FIFO order. This is the absolute final
-- cam.CFrame write before the frame is committed to the GPU, so no game
-- camera script can override it regardless of what BindToRenderStep priority
-- they bind at or whether they use RenderStepped:Connect themselves.
conn(RunService.RenderStepped:Connect(function()
    if fps_aimPos then
        -- Recompute CFrame from CURRENT camera position so any game-driven
        -- position drift (FPS head-bob, ADS offset, etc.) is absorbed.
        local cf = CFrame.new(cam.CFrame.Position, fps_aimPos)
        cam.CFrame = cam.CFrame:Lerp(cf, fps_alpha or 1)
        fps_aimPos = nil  -- consume — next frame must be re-set by BindToRenderStep
    end
end))

-- // ════════════════ SPRINT ══════════════════════════ //

conn(RunService.Heartbeat:Connect(function()
    if not cfg.sprint.enabled then return end
    local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum.WalkSpeed = UIS:IsKeyDown(cfg.sprint.key) and cfg.sprint.speed or cfg.sprint.default_spd
end))

-- // ════════════════ BHOP ════════════════════════════ //

local function connectBhop(char)
    local hum = char:WaitForChild("Humanoid", 4)
    if not hum then return end
    conn(hum.StateChanged:Connect(function(_, new)
        if cfg.misc.bhop
        and new == Enum.HumanoidStateType.Landed
        and UIS:IsKeyDown(Enum.KeyCode.Space) then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end))
end

if lp.Character then connectBhop(lp.Character) end
conn(lp.CharacterAdded:Connect(connectBhop))

-- // ═══════════════ NOCLIP ══════════════════════════ //

conn(RunService.Stepped:Connect(function()
    if not cfg.misc.noclip then return end
    local char = lp.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = false end
    end
end))

-- // ════════════════ KEYBINDS ════════════════════════ //
-- F1/F2/F3/F4 defaults, fully rebindable from the settings panel.
-- fires only on keyboard input and skips game-processed events so it
-- doesn't interfere with typing in chat or other UI elements.

conn(UIS.InputBegan:Connect(function(i, gpe)
    if gpe or i.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local k = i.KeyCode
    if k == cfg.keys.aim    then cfg.aim.enabled  = not cfg.aim.enabled  end
    if k == cfg.keys.esp    then cfg.esp.enabled  = not cfg.esp.enabled  end
    if k == cfg.keys.bhop   then cfg.misc.bhop    = not cfg.misc.bhop    end
    if k == cfg.keys.noclip then cfg.misc.noclip  = not cfg.misc.noclip  end
end))

-- // ═══════════════ MAGIC BULLET ════════════════════ //
--
-- Remote intercept approach — player never moves.
--
-- How it works:
--   In virtually every Roblox FPS game, "bullets" are not real physics
--   objects. Firing = the tool's LocalScript raycasts, finds a hit, then
--   calls  GunRemote:FireServer(hitPart, hitPosition, hitNormal, ...)
--   The server trusts those arguments and deals damage.
--
--   We hook __namecall on the game metatable (same technique that lets
--   executors intercept any method call). When tool.Activated fires, we
--   open a 2-frame hijack window. Any FireServer call that lands inside
--   that window gets its arguments rewritten before they leave the client:
--
--     Vector3 world-positions  → replaced with locked target's position
--     BasePart instances       → replaced with a part on the target's char
--     Model instances          → replaced with target's character model
--     Humanoid instances       → replaced with target's Humanoid
--     unit-vector normals      → replaced with shooter→target direction
--     numbers / strings / bool → left alone (damage values, flags, etc.)
--
--   The server receives already-modified data. It thinks you hit the
--   target legitimately. No teleport. No visual artifact. No footprint.
--
-- Requirements:
--   hookmetamethod + getnamecallmethod must be available on your executor
--   (Synapse X, Wave, Fluxus, KRNL, Hydrogen — all support these).
--   If not available, magic bullet silently disables itself.
--
-- Limitations:
--   • games that validate hit distance server-side (rare but exists):
--     the server confirms the "hit position" is within N studs of the
--     shooter's server position. since we don't move, it might reject.
--   • games using custom networking (not RemoteEvent FireServer) won't
--     be caught by this hook.
--   • server-side raycasting games (server re-raycasts independently):
--     our modified args are ignored; server does its own check.
--     these games need Method A (HRP teleport) instead.

-- ── debug helpers ─────────────────────────────────────────────────────
local function mbLog(...)
    if cfg.misc.mb_debug then print("[MB]", ...) end
end
local function mbWarn(...)
    if cfg.misc.mb_debug then warn("[MB]", ...) end
end
-- like pcall but prints what failed when debug is on
local function mbCall(label, fn)
    local ok, err = pcall(fn)
    if not ok then mbWarn(label, "FAILED:", err) end
    return ok
end

-- two systems run simultaneously, covering different game architectures:
--
-- SYSTEM 1 — Remote hook (raycast / hit-report games)
--   Intercepts FireServer calls during the shot window and rewrites
--   hit position / part / character args to point at the locked target.
--   Works on any game where the client reports hits via RemoteEvent.
--
-- SYSTEM 2 — Bullet watcher (physical projectile games)
--   Watches workspace.DescendantAdded for new BaseParts that appear
--   during the shot window. Roblox assigns network ownership of the
--   bullet to the firing player, making that client the physics
--   authority. We teleport the part inside the target immediately —
--   the server accepts our position because we own it.
--   Works on any game that spawns real projectile parts.
--
-- Both fire on every shot. Whichever one applies to the current game
-- handles it. They don't interfere with each other.

local mbHijacking    = false   -- remote hook active
local mbWatchActive  = false   -- bullet watcher active
local mbWatchExpiry  = 0       -- tick() deadline for watcher
local mbTargetRoot   = nil
local mbTargetChar   = nil
local MB_WINDOW      = 0.6     -- seconds to watch for bullets after shot

-- ── helper: pick a random body part to use as hit reference ──────────
local MB_BODY = {"Head","UpperTorso","LowerTorso","HumanoidRootPart"}
local function mbHitPart()
    local char = mbTargetChar; if not char then return mbTargetRoot end
    return char:FindFirstChild(MB_BODY[math.random(#MB_BODY)]) or mbTargetRoot
end

local function mbHitPos()
    local p = mbTargetRoot.Position
    return p + Vector3.new(
        (math.random()-.5)*.35,
         math.random()*.7 + .25,   -- bias chest/head height
        (math.random()-.5)*.35
    )
end

local function mbHitNormal()
    local myRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    return myRoot and (myRoot.Position - mbTargetRoot.Position).Unit or Vector3.new(0,1,0)
end

-- ── SYSTEM 1: remote hook ─────────────────────────────────────────────
local mbHookInstalled = false
local function installMBHook()
    if mbHookInstalled then return end
    if not (hookmetamethod and getnamecallmethod) then
        warn("[NEXUS] magic bullet: hookmetamethod not available — remote hook disabled, bullet watcher still active")
        mbHookInstalled = true
        return
    end

    hookmetamethod(game, "__namecall", newcclosure and newcclosure(function(self, ...)
        local method = getnamecallmethod()

        -- intercept FireServer (RemoteEvent) AND InvokeServer (RemoteFunction)
        -- gate only on mbTargetRoot — synced every frame from the aimbot lock,
        -- so no timing race with the game's shot handler
        local isShottable = (method == "FireServer"   and pcall(function() self:IsA("RemoteEvent")    end) and self:IsA("RemoteEvent"))
                         or (method == "InvokeServer" and pcall(function() self:IsA("RemoteFunction") end) and self:IsA("RemoteFunction"))

        if isShottable and mbTargetRoot then
            -- only rewrite if the args contain at least one Vector3 or BasePart —
            -- that's what shot remotes look like. this prevents intercepting
            -- unrelated remotes (chat, movement, UI) that happen while locked.
            local raw = {...}
            local looksLikeShot = false
            for _, v in ipairs(raw) do
                local t = typeof(v)
                if t == "Vector3" then looksLikeShot = true; break end
                if t == "Instance" then
                    local ok, isBP = pcall(function() return v:IsA("BasePart") end)
                    if ok and isBP then looksLikeShot = true; break end
                end
            end

            if looksLikeShot then
                mbLog("remote hook fired — method:", method, "| remote:", self.Name, "| target:", mbTargetRoot.Name)
                local hitPart   = mbHitPart()
                local hitPos    = mbHitPos()
                local hitNormal = mbHitNormal()
                local fixed = {}
                for i, arg in ipairs(raw) do
                    local t = typeof(arg)
                    if t == "Vector3" then
                        fixed[i] = arg.Magnitude < 1.5 and hitNormal or hitPos
                        mbLog("  arg["..i.."] Vector3 mag="..string.format("%.2f",arg.Magnitude).." → "..(arg.Magnitude<1.5 and "normal" or "hitPos"))
                    elseif t == "Instance" then
                        if     arg:IsA("BasePart")  then fixed[i] = hitPart
                        elseif arg:IsA("Model")     then fixed[i] = mbTargetChar or arg
                        elseif arg:IsA("Humanoid")  then
                            fixed[i] = (mbTargetChar and mbTargetChar:FindFirstChildOfClass("Humanoid")) or arg
                        else fixed[i] = arg end
                        mbLog("  arg["..i.."] Instance:", arg.ClassName, arg.Name, "→", fixed[i] and fixed[i].Name or "nil")
                    else
                        fixed[i] = arg
                        mbLog("  arg["..i.."] "..t..":", tostring(arg), "(kept)")
                    end
                end
                return self[method](self, table.unpack(fixed))
            else
                mbLog("remote skipped (no shot-like args):", self.Name, "method:", method)
            end
        end
        return self[method](self, ...)
    end) or function(self,...) return self[getnamecallmethod()](self,...) end)

    mbLog("remote hook installed")
    mbHookInstalled = true
end

-- ── SYSTEM 2: bullet watcher ─────────────────────────────────────────

-- generic heuristic — used only for games that don't have _Temp
local function looksLikeBullet(part, shooterPos)
    if part.Anchored then return false end
    local p = part.Parent
    if p then
        if p:FindFirstChildOfClass("Humanoid") then return false end
        if p:FindFirstChildOfClass("AnimationController") then return false end
        if p:IsA("Tool") then return false end
    end
    if shooterPos and (part.Position - shooterPos).Magnitude > 80 then return false end
    return true
end

local function teleportBullet(part)
    local dest    = mbHitPos()
    local hitPart = mbHitPart()
    local cf      = CFrame.new(dest)
    mbLog("teleporting:", part.Name, "(class="..part.ClassName..")",
          "| size="..string.format("%.2f", part.Size.Magnitude),
          "| target:", mbTargetRoot and mbTargetRoot.Name or "nil")
    local isAnchored = pcall(function() return part.Anchored end) and part.Anchored
    mbLog("anchored=", tostring(isAnchored))
    mbCall("SetNetworkOwner", function() part:SetNetworkOwner(lp) end)
    mbCall("CFrame frame-0",  function()
        part.CFrame = cf
        if not isAnchored then
            part.AssemblyLinearVelocity = Vector3.new(0, -20, 0)
        end
    end)
    task.spawn(function()
        local deadline = tick() + 0.25
        local frameN   = 0
        while tick() < deadline do
            frameN = frameN + 1
            local ok = pcall(function()
                part.CFrame = cf
                if not isAnchored then
                    part.AssemblyLinearVelocity = Vector3.new(0, -20, 0)
                end
            end)
            if not ok then mbWarn("persist loop: part destroyed at frame", frameN); break end
            RunService.Heartbeat:Wait()
        end
        mbLog("persist loop done — frames held:", frameN)
        if firetouchinterest then
            mbLog("firetouchinterest available — firing on:", hitPart and hitPart.Name or "nil")
            mbCall("firetouchinterest A", function() firetouchinterest(part, hitPart, 0) end)
            mbCall("firetouchinterest B", function() firetouchinterest(hitPart, part, 0) end)
        else
            mbLog("firetouchinterest: not exposed by this executor")
        end
    end)
end

-- ── _Temp watcher (primary — direct children of _Temp) ───────────────
local function onTempChild(obj)
    -- only care about parts named "Bullet" — _Temp also receives ThirdPerson
    -- models, ragdolls, default parts, etc. that we have no interest in
    if obj.Name ~= "Bullet" then return end

    mbLog("_Temp Bullet appeared (class="..obj.ClassName..")",
          "| anchored="..(obj:IsA("BasePart") and tostring(obj.Anchored) or "n/a"),
          "| watching=", tostring(mbWatchActive))

    if not cfg.misc.magic_bullet then return end
    if not mbWatchActive then mbLog("not watching — skipping"); return end
    if tick() > mbWatchExpiry then
        mbWatchActive = false
        mbLog("watch window expired — skipping")
        return
    end
    if not mbTargetRoot then mbLog("no target — skipping"); return end
    if not obj:IsA("BasePart") then mbLog("not a BasePart — skipping"); return end
    -- note: bullets in this game are anchored=true, so no anchored guard here
    mbLog("✓ bullet caught:", obj.Name, "anchored="..tostring(obj.Anchored))
    teleportBullet(obj)
    mbWatchActive = false
end

local function hookTempFolder(folder)
    mbLog("hooking _Temp.ChildAdded on", folder:GetFullName())
    conn(folder.ChildAdded:Connect(onTempChild))
end

do
    local t = workspace:FindFirstChild("_Temp")
    if t then
        hookTempFolder(t)
    else
        mbLog("_Temp not found at load — will hook if it appears")
    end
    conn(workspace.ChildAdded:Connect(function(c)
        if c.Name == "_Temp" then hookTempFolder(c) end
    end))
end

-- ── generic fallback (games without _Temp) ───────────────────────────
conn(workspace.DescendantAdded:Connect(function(obj)
    if not cfg.misc.magic_bullet then return end
    if not mbWatchActive         then return end
    if tick() > mbWatchExpiry    then mbWatchActive = false; return end
    if not mbTargetRoot          then return end
    if not obj:IsA("BasePart")   then return end
    local myRoot     = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    local shooterPos = myRoot and myRoot.Position
    local pass = looksLikeBullet(obj, shooterPos)
    mbLog("workspace.DescendantAdded:", obj.Name,
          "| size="..string.format("%.2f", obj.Size.Magnitude),
          "| anchored="..tostring(obj.Anchored),
          "→", pass and "PASS" or "fail")
    if pass then
        mbLog("✓ bullet caught via workspace fallback:", obj.Name)
        teleportBullet(obj)
        mbWatchActive = false
    end
end))

-- ── shared shot trigger via UIS.InputBegan ───────────────────────────
-- using InputBegan for MouseButton1 instead of tool.Activated because:
-- connections fire in FIFO order — the game connected its Activated
-- handler before us, so by the time our Activated fires, the game has
-- ALREADY called FireServer and our hook window missed it.
-- UIS.InputBegan fires at the raw input level, before ANY tool handlers,
-- giving the remote hook time to be set first.
conn(UIS.InputBegan:Connect(function(input, gpe)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if not cfg.misc.magic_bullet then return end
    -- no gpe guard here — games like sniper arena use a full-screen scope GUI
    -- which causes gpe=true on every shot click. we gate on aimbot lock instead.
    mbLog("LMB detected (gpe="..tostring(gpe)..")")

    local targetChar, targetRoot = getCharData(lockedKey)
    if not (targetChar and targetRoot) then
        mbLog("LMB — no aimbot lock, skipping")
        return
    end

    mbLog("LMB — target:", targetRoot.Name, "| opening window ("..MB_WINDOW.."s)")

    mbTargetRoot = targetRoot
    mbTargetChar = targetChar

    installMBHook()
    mbHijacking = true
    task.defer(function() task.defer(function() task.defer(function()
        mbHijacking = false
        mbLog("remote hook window closed")
    end) end) end)

    mbWatchActive = true
    mbWatchExpiry = tick() + MB_WINDOW
end))

-- // ════════════════ INPUT ═══════════════════════════ //

conn(UIS.InputBegan:Connect(function(i, gpe)
    if gpe then return end
    if i.KeyCode == Enum.KeyCode.Q
    and (UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)) then
        if not cfg.aim.enabled then return end
        aimToggled = not aimToggled
        print("[NEXUS] aim lock:", aimToggled)
    end
end))

-- // ═══════════════════ UI ══════════════════════════ //

local GUI_ROOT = (function()
    local ok, r = pcall(gethui); return ok and r or game:GetService("CoreGui")
end)()

local SG = Instance.new("ScreenGui")
SG.Name="NexusUI"; SG.ResetOnSpawn=false
SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; SG.Parent=GUI_ROOT

local BG0=Color3.fromRGB(9,9,13);   local BG1=Color3.fromRGB(14,14,20)
local BG2=Color3.fromRGB(19,19,27); local BG3=Color3.fromRGB(26,26,38)
local TABON=Color3.fromRGB(110,65,235); local TABOF=Color3.fromRGB(19,19,27)
local TGON=Color3.fromRGB(95,55,215);  local TGOFF=Color3.fromRGB(35,35,52)
local TXA=Color3.fromRGB(225,225,248); local TXB=Color3.fromRGB(95,95,125)
local TXC=Color3.fromRGB(145,105,255)

local WIN = Instance.new("Frame")
WIN.Size=UDim2.new(0,440,0,580); WIN.Position=UDim2.new(0.5,-220,0.5,-290)
WIN.BackgroundColor3=BG0; WIN.BorderSizePixel=0; WIN.Active=true; WIN.Parent=SG
Instance.new("UICorner",WIN).CornerRadius=UDim.new(0,10)
local GS=Instance.new("UIStroke"); GS.Color=Color3.fromRGB(110,65,235); GS.Thickness=1; GS.Transparency=0.5; GS.Parent=WIN
local SHD=Instance.new("Frame"); SHD.Size=UDim2.new(1,22,1,22); SHD.Position=UDim2.new(0,-11,0,-11)
SHD.BackgroundColor3=Color3.new(0,0,0); SHD.BackgroundTransparency=0.5; SHD.BorderSizePixel=0; SHD.ZIndex=WIN.ZIndex-1; SHD.Parent=WIN
Instance.new("UICorner",SHD).CornerRadius=UDim.new(0,15)

local TB = Instance.new("Frame")
TB.Size=UDim2.new(1,0,0,46); TB.BackgroundColor3=BG1; TB.BorderSizePixel=0; TB.Parent=WIN
Instance.new("UICorner",TB).CornerRadius=UDim.new(0,10)
local TBf=Instance.new("Frame"); TBf.Size=UDim2.new(1,0,0,10); TBf.Position=UDim2.new(0,0,1,-10)
TBf.BackgroundColor3=BG1; TBf.BorderSizePixel=0; TBf.Parent=TB

local function mkL(p,t,f,s,c,xa,pos,sz)
    local l=Instance.new("TextLabel"); l.Text=t; l.Font=f; l.TextSize=s; l.TextColor3=c
    l.BackgroundTransparency=1; l.TextXAlignment=xa or Enum.TextXAlignment.Center
    l.Position=pos or UDim2.new(0,0,0,0); l.Size=sz or UDim2.new(1,0,1,0); l.Parent=p; return l
end

mkL(TB,"NEXUS",Enum.Font.GothamBold,16,TXA,Enum.TextXAlignment.Left,UDim2.new(0,14,0,5),UDim2.new(0,80,0,20))
mkL(TB,IS_FL and "frontlines mode" or "universal",Enum.Font.Gotham,10,IS_FL and Color3.fromRGB(80,200,120) or TXB,
    Enum.TextXAlignment.Left,UDim2.new(0,15,0,26),UDim2.new(0,140,0,14))
local adot=Instance.new("Frame"); adot.Size=UDim2.new(0,6,0,6); adot.Position=UDim2.new(0,64,0,11)
adot.BackgroundColor3=IS_FL and Color3.fromRGB(80,200,120) or TXC; adot.BorderSizePixel=0; adot.Parent=TB
Instance.new("UICorner",adot).CornerRadius=UDim.new(1,0)

local UB=Instance.new("TextButton"); UB.Text="UNLOAD"; UB.Font=Enum.Font.GothamBold; UB.TextSize=9
UB.TextColor3=Color3.fromRGB(200,70,70); UB.BackgroundColor3=Color3.fromRGB(35,15,15)
UB.Size=UDim2.new(0,56,0,22); UB.Position=UDim2.new(1,-106,0.5,-11); UB.BorderSizePixel=0; UB.Parent=TB
Instance.new("UICorner",UB).CornerRadius=UDim.new(0,5)
Instance.new("UIStroke",UB).Color=Color3.fromRGB(120,30,30)

local CLO=Instance.new("TextButton"); CLO.Text="✕"; CLO.Font=Enum.Font.GothamBold; CLO.TextSize=13; CLO.TextColor3=TXB
CLO.BackgroundTransparency=1; CLO.Size=UDim2.new(0,40,0,46); CLO.Position=UDim2.new(1,-40,0,0); CLO.Parent=TB
CLO.MouseButton1Click:Connect(function() WIN.Visible=not WIN.Visible end)
CLO.MouseEnter:Connect(function() CLO.TextColor3=Color3.fromRGB(220,80,80) end)
CLO.MouseLeave:Connect(function() CLO.TextColor3=TXB end)

do  -- settings UI build block: all locals scoped here, freed before minimap/drag sections
local TABROW=Instance.new("Frame")
TABROW.Size=UDim2.new(1,-18,0,28); TABROW.Position=UDim2.new(0,9,0,52)
TABROW.BackgroundTransparency=1; TABROW.Parent=WIN
local TRL=Instance.new("UIListLayout")
TRL.FillDirection=Enum.FillDirection.Horizontal; TRL.SortOrder=Enum.SortOrder.LayoutOrder
TRL.Padding=UDim.new(0,4); TRL.Parent=TABROW

local SEP=Instance.new("Frame"); SEP.Size=UDim2.new(1,-18,0,1); SEP.Position=UDim2.new(0,9,0,82)
SEP.BackgroundColor3=Color3.fromRGB(26,26,42); SEP.BorderSizePixel=0; SEP.Parent=WIN

local SCR=Instance.new("ScrollingFrame")
SCR.Size=UDim2.new(1,0,1,-92); SCR.Position=UDim2.new(0,0,0,92); SCR.BackgroundTransparency=1
SCR.ScrollBarThickness=2; SCR.ScrollBarImageColor3=Color3.fromRGB(80,50,160)
SCR.BorderSizePixel=0; SCR.CanvasSize=UDim2.new(0,0,0,0); SCR.AutomaticCanvasSize=Enum.AutomaticSize.Y; SCR.Parent=WIN
Instance.new("UIListLayout",SCR).SortOrder=Enum.SortOrder.LayoutOrder
local SPad=Instance.new("UIPadding")
SPad.PaddingLeft=UDim.new(0,9); SPad.PaddingRight=UDim.new(0,9)
SPad.PaddingTop=UDim.new(0,10); SPad.PaddingBottom=UDim.new(0,10); SPad.Parent=SCR

local tabBtns={} local tabPanes={}

local function makeTab(name,icon,ord)
    local btn=Instance.new("TextButton")
    btn.Text=icon.." "..name; btn.Font=Enum.Font.GothamSemibold; btn.TextSize=11
    btn.TextColor3=TXB; btn.BackgroundColor3=TABOF
    btn.Size=UDim2.new(0,84,0,28); btn.BorderSizePixel=0; btn.LayoutOrder=ord; btn.Parent=TABROW
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,6)
    local pane=Instance.new("Frame"); pane.Name=name; pane.Size=UDim2.new(1,0,0,0)
    pane.AutomaticSize=Enum.AutomaticSize.Y; pane.BackgroundTransparency=1
    pane.Visible=false; pane.LayoutOrder=0; pane.Parent=SCR
    local pl=Instance.new("UIListLayout"); pl.SortOrder=Enum.SortOrder.LayoutOrder; pl.Padding=UDim.new(0,4); pl.Parent=pane
    tabBtns[name]=btn; tabPanes[name]=pane
    btn.MouseButton1Click:Connect(function()
        for _,p in pairs(tabPanes) do p.Visible=false end
        for _,b in pairs(tabBtns) do TweenService:Create(b,TweenInfo.new(0.1),{BackgroundColor3=TABOF,TextColor3=TXB}):Play() end
        pane.Visible=true
        TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=TABON,TextColor3=TXA}):Play()
    end)
    return pane
end

local function mkSec(p,label,ord)
    local f=Instance.new("Frame"); f.Size=UDim2.new(1,0,0,24); f.BackgroundTransparency=1
    f.LayoutOrder=ord or 0; f.Parent=p
    local ln=Instance.new("Frame"); ln.Size=UDim2.new(1,0,0,1); ln.Position=UDim2.new(0,0,1,-1)
    ln.BackgroundColor3=Color3.fromRGB(26,26,42); ln.BorderSizePixel=0; ln.Parent=f
    mkL(f,label,Enum.Font.GothamBold,9,TXC,Enum.TextXAlignment.Left)
end

local function mkTog(p,label,tbl,key,ord,hint,onChange)
    local h=hint and 46 or 38
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,h); row.BackgroundColor3=BG2
    row.BorderSizePixel=0; row.LayoutOrder=ord or 0; row.Parent=p
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,7)
    mkL(row,label,Enum.Font.GothamSemibold,12,TXA,Enum.TextXAlignment.Left,UDim2.new(0,12,0,8),UDim2.new(1,-58,0,20))
    if hint then mkL(row,hint,Enum.Font.Gotham,9,TXB,Enum.TextXAlignment.Left,UDim2.new(0,12,0,26),UDim2.new(1,-58,0,14)) end
    local pill=Instance.new("Frame"); pill.Size=UDim2.new(0,36,0,18); pill.Position=UDim2.new(1,-48,0.5,-9)
    pill.BackgroundColor3=tbl[key] and TGON or TGOFF; pill.BorderSizePixel=0; pill.Parent=row
    Instance.new("UICorner",pill).CornerRadius=UDim.new(1,0)
    local dt=Instance.new("Frame"); dt.Size=UDim2.new(0,14,0,14)
    dt.Position=tbl[key] and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)
    dt.BackgroundColor3=WHITE; dt.BorderSizePixel=0; dt.Parent=pill
    Instance.new("UICorner",dt).CornerRadius=UDim.new(1,0)
    local hit=Instance.new("TextButton"); hit.Text=""; hit.BackgroundTransparency=1
    hit.Size=UDim2.new(1,0,1,0); hit.Parent=row
    hit.MouseButton1Click:Connect(function()
        tbl[key]=not tbl[key]; local on=tbl[key]
        TweenService:Create(pill,TweenInfo.new(0.12),{BackgroundColor3=on and TGON or TGOFF}):Play()
        TweenService:Create(dt,TweenInfo.new(0.12),{Position=on and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7)}):Play()
        if onChange then onChange(on) end
        saveCfg()
    end)
end

local function mkSld(p,label,tbl,key,mn,mx,ord,hint)
    local isF=(mx-mn)<=2
    local h=hint and 68 or 58
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,h); row.BackgroundColor3=BG2
    row.BorderSizePixel=0; row.LayoutOrder=ord or 0; row.Parent=p
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,7)
    mkL(row,label,Enum.Font.GothamSemibold,12,TXA,Enum.TextXAlignment.Left,UDim2.new(0,12,0,8),UDim2.new(0.65,0,0,20))
    if hint then mkL(row,hint,Enum.Font.Gotham,9,TXB,Enum.TextXAlignment.Left,UDim2.new(0,12,0,30),UDim2.new(1,-20,0,10)) end
    local vb=Instance.new("Frame"); vb.Size=UDim2.new(0,52,0,20); vb.Position=UDim2.new(1,-62,0,8)
    vb.BackgroundColor3=BG3; vb.BorderSizePixel=0; vb.Parent=row
    Instance.new("UICorner",vb).CornerRadius=UDim.new(0,5)
    local vL=mkL(vb,tostring(tbl[key]),Enum.Font.GothamBold,11,TXC)
    local trk=Instance.new("Frame"); trk.Size=UDim2.new(1,-24,0,4); trk.Position=UDim2.new(0,12,1,-14)
    trk.BackgroundColor3=Color3.fromRGB(26,26,44); trk.BorderSizePixel=0; trk.Parent=row
    Instance.new("UICorner",trk).CornerRadius=UDim.new(1,0)
    local p0=math.clamp((tbl[key]-mn)/(mx-mn),0,1)
    local fill=Instance.new("Frame"); fill.BackgroundColor3=TABON; fill.BorderSizePixel=0
    fill.Size=UDim2.new(p0,0,1,0); fill.Parent=trk
    Instance.new("UICorner",fill).CornerRadius=UDim.new(1,0)
    local th=Instance.new("Frame"); th.Size=UDim2.new(0,12,0,12); th.Position=UDim2.new(p0,-6,0.5,-6)
    th.BackgroundColor3=WHITE; th.BorderSizePixel=0; th.Parent=trk
    Instance.new("UICorner",th).CornerRadius=UDim.new(1,0)
    local sdrag=false
    local ht=Instance.new("TextButton"); ht.Text=""; ht.BackgroundTransparency=1
    ht.Size=UDim2.new(1,0,0,24); ht.Position=UDim2.new(0,0,0,-10); ht.Parent=trk
    local function apply(mx2)
        local a=trk.AbsolutePosition; local s=trk.AbsoluteSize
        local pct=math.clamp((mx2-a.X)/s.X,0,1)
        local raw=mn+(mx-mn)*pct
        local val=isF and (math.floor(raw*10)/10) or math.floor(raw)
        tbl[key]=val; fill.Size=UDim2.new(pct,0,1,0); th.Position=UDim2.new(pct,-6,0.5,-6); vL.Text=tostring(val)
        saveCfg()
    end
    ht.MouseButton1Down:Connect(function() sdrag=true; apply(UIS:GetMouseLocation().X) end)
    UIS.InputChanged:Connect(function(i)
        if sdrag and i.UserInputType==Enum.UserInputType.MouseMovement then apply(UIS:GetMouseLocation().X) end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then sdrag=false end
    end)
end

local function mkChoice(p, label, hint, tbl, key, choices, ord)
    local h = hint and 68 or 58
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,h); row.BackgroundColor3=BG2
    row.BorderSizePixel=0; row.LayoutOrder=ord or 0; row.Parent=p
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,7)
    mkL(row,label,Enum.Font.GothamSemibold,12,TXA,Enum.TextXAlignment.Left,UDim2.new(0,12,0,8),UDim2.new(1,0,0,18))
    if hint then mkL(row,hint,Enum.Font.Gotham,9,TXB,Enum.TextXAlignment.Left,UDim2.new(0,12,0,26),UDim2.new(1,-20,0,14)) end
    local brow=Instance.new("Frame"); brow.Size=UDim2.new(1,-24,0,26); brow.Position=UDim2.new(0,12,1,-34)
    brow.BackgroundTransparency=1; brow.Parent=row
    local ll=Instance.new("UIListLayout"); ll.FillDirection=Enum.FillDirection.Horizontal
    ll.Padding=UDim.new(0,4); ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Parent=brow
    local btnMap={}
    local n=math.max(#choices,1)
    local bwScale=1/n; local bwOffset=-math.ceil((n-1)*4/n)
    for idx, choice in ipairs(choices) do
        local active=tbl[key]==choice
        local b=Instance.new("TextButton"); b.Text=choice; b.Font=Enum.Font.GothamSemibold; b.TextSize=11
        b.TextColor3=active and TXA or TXB; b.BackgroundColor3=active and TABON or BG3
        b.Size=UDim2.new(bwScale,bwOffset,1,0); b.BorderSizePixel=0; b.LayoutOrder=idx; b.Parent=brow
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,5)
        btnMap[choice]=b
        b.MouseButton1Click:Connect(function()
            tbl[key]=choice
            for c,btn in pairs(btnMap) do
                TweenService:Create(btn,TweenInfo.new(0.1),{
                    BackgroundColor3=c==choice and TABON or BG3,
                    TextColor3=c==choice and TXA or TXB,
                }):Play()
            end
        end)
    end
end

local rebinding=false
local function mkBind(p,label,tbl,key,ord)
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,46); row.BackgroundColor3=BG2
    row.BorderSizePixel=0; row.LayoutOrder=ord or 0; row.Parent=p
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,7)
    mkL(row,label,Enum.Font.GothamSemibold,12,TXA,Enum.TextXAlignment.Left,UDim2.new(0,12,0,8),UDim2.new(1,-100,0,20))
    mkL(row,"click to rebind · Esc=cancel",Enum.Font.Gotham,9,TXB,Enum.TextXAlignment.Left,UDim2.new(0,12,0,28),UDim2.new(1,-100,0,14))
    local kb=Instance.new("TextButton")
    kb.Text=tostring(tbl[key]):gsub("Enum.KeyCode.",""); kb.Font=Enum.Font.GothamBold; kb.TextSize=10
    kb.TextColor3=TXC; kb.BackgroundColor3=BG3; kb.Size=UDim2.new(0,80,0,26); kb.Position=UDim2.new(1,-90,0.5,-13)
    kb.BorderSizePixel=0; kb.Parent=row
    Instance.new("UICorner",kb).CornerRadius=UDim.new(0,6)
    Instance.new("UIStroke",kb).Color=Color3.fromRGB(60,40,100)
    local listening=false
    kb.MouseButton1Click:Connect(function()
        if rebinding then return end
        rebinding=true; listening=true; kb.Text="..."; kb.TextColor3=Color3.fromRGB(255,210,50)
    end)
    conn(UIS.InputBegan:Connect(function(i,gpe)
        if not listening then return end
        if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if i.KeyCode ~= Enum.KeyCode.Escape then
            tbl[key]=i.KeyCode; kb.Text=tostring(i.KeyCode):gsub("Enum.KeyCode.","")
            saveCfg()
        else
            kb.Text=tostring(tbl[key]):gsub("Enum.KeyCode.","")
        end
        kb.TextColor3=TXC; listening=false; rebinding=false
    end))
end

-- multi-select toggle grid — multiple buttons can be active at once.
-- tbl[key] is a {PartName=bool} table. each button flips its own entry.
-- options = PART_OPTIONS-style list of {id, label} pairs.
local function mkMultiSelect(p, label, tbl, key, options, ord)
    local rows    = math.ceil(#options / 3)
    local gridH   = rows * 26 + math.max(0, rows-1) * 4
    local totalH  = 52 + gridH + 8
    local row     = Instance.new("Frame")
    row.Size           = UDim2.new(1,0,0,totalH)
    row.BackgroundColor3 = BG2
    row.BorderSizePixel  = 0
    row.LayoutOrder      = ord or 0
    row.Parent           = p
    Instance.new("UICorner",row).CornerRadius = UDim.new(0,7)
    mkL(row, label, Enum.Font.GothamSemibold, 12, TXA,
        Enum.TextXAlignment.Left, UDim2.new(0,12,0,8), UDim2.new(1,0,0,18))
    mkL(row, "select multiple — randomly picks one per lock", Enum.Font.Gotham, 9, TXB,
        Enum.TextXAlignment.Left, UDim2.new(0,12,0,26), UDim2.new(1,-20,0,14))
    local grid = Instance.new("Frame")
    grid.Size                = UDim2.new(1,-24,0,gridH)
    grid.Position            = UDim2.new(0,12,0,46)
    grid.BackgroundTransparency = 1
    grid.Parent              = row
    local gl = Instance.new("UIGridLayout")
    -- 3 columns: (416 - 2 gaps * 4) / 3 = 136 px per cell
    gl.CellSize    = UDim2.new(0,136,0,26)
    gl.CellPadding = UDim2.new(0,4,0,4)
    gl.SortOrder   = Enum.SortOrder.LayoutOrder
    gl.Parent      = grid
    for idx, opt in ipairs(options) do
        local active = tbl[key][opt.id] == true
        local b = Instance.new("TextButton")
        b.Text             = opt.label
        b.Font             = Enum.Font.GothamSemibold
        b.TextSize         = 10
        b.TextColor3       = active and TXA or TXB
        b.BackgroundColor3 = active and TABON or BG3
        b.BorderSizePixel  = 0
        b.LayoutOrder      = idx
        b.Parent           = grid
        Instance.new("UICorner",b).CornerRadius = UDim.new(0,5)
        b.MouseButton1Click:Connect(function()
            tbl[key][opt.id] = not (tbl[key][opt.id] == true)
            local on = tbl[key][opt.id] == true
            TweenService:Create(b, TweenInfo.new(0.1), {
                BackgroundColor3 = on and TABON or BG3,
                TextColor3       = on and TXA or TXB,
            }):Play()
        end)
    end
end

local aP=makeTab("Aimbot","◎",1)
local eP=makeTab("ESP",   "◈",2)
local sP=makeTab("Sprint","▶",3)
local mP=makeTab("Misc",  "⊹",4)

mkSec(aP,"CORE",0)
mkTog(aP,"Aimbot Enabled",            cfg.aim,"enabled",    1)
mkTog(aP,"Aim Lock  (Shift+Q)",       cfg.aim,"toggle_mode",2,"RMB=hold · Shift+Q=persistent lock")
mkSec(aP,"MODE",3)
mkChoice(aP,"Aim Mode",
    "Smooth · Flick=snap once · Rage=instant · Human=drift · Trickshot=COD flick",
    cfg.aim,"mode",{"Smooth","Flick","Rage","Human","Trickshot"},4)
mkSec(aP,"TARGETING",5)
mkTog(aP,"Team Check",                cfg.aim,"team_check", 6)
mkTog(aP,"Skip Targets Behind Walls", cfg.aim,"vis_check",  7)
mkTog(aP,"Velocity Prediction",       cfg.aim,"prediction", 8,"accel-based · pos + vel·t + ½a·t²")
mkMultiSelect(aP,"Target Part",       cfg.aim,"target_parts", PART_OPTIONS, 9)
mkSec(aP,"TUNING",10)
mkSld(aP,"FOV Radius",                cfg.aim,"fov",       50, 500, 11)
mkSld(aP,"Smoothness",                cfg.aim,"smooth",     1,  20, 12,"Smooth + Human only · 1=snap")
mkSld(aP,"Pred Factor",               cfg.aim,"pred_mult",  0, 0.5, 13)
mkSld(aP,"Proj Speed (studs/s)",      cfg.aim,"pred_speed",100,2000,14,"time-of-flight = dist ÷ this")
mkSld(aP,"Flick Speed (s)",           cfg.aim,"ts_flick_dur",0.03,0.5,15,"Trickshot only · lower = faster snap")
mkSec(aP,"TRIGGERBOT",16)
mkTog(aP,"Triggerbot",                cfg.aim,"triggerbot", 17)
mkSld(aP,"Trigger Delay (s)",         cfg.aim,"trig_delay", 0, 0.5, 18)

mkSec(eP,"CORE",0)
mkTog(eP,"ESP Enabled",               cfg.esp,"enabled",   1)
mkTog(eP,"Team Check",                cfg.esp,"team_check",2,"red=visible · blue=hidden · gold=locked")
mkSec(eP,"STYLE",3)
mkTog(eP,"Box",                       cfg.esp,"box",       4)
mkTog(eP,"Rainbow",                   cfg.esp,"rainbow",   5)
mkTog(eP,"Corner Brackets",           cfg.esp,"corners",   6)
mkSec(eP,"ELEMENTS",7)
mkTog(eP,"Names",                     cfg.esp,"names",     8)
mkTog(eP,"Health Bars",               cfg.esp,"health",    9)
mkTog(eP,"Tracers",                   cfg.esp,"tracers",   10)
mkTog(eP,"Distance",                  cfg.esp,"distance",  11)
mkTog(eP,"Skeleton",                  cfg.esp,"skeleton",  12)
mkTog(eP,"Avatar Outline",            cfg.esp,"outline",   13,"3D highlight · matches ESP colour · visible through walls")

mkSec(sP,"SPRINT",0)
mkTog(sP,"Sprint Enabled",            cfg.sprint,"enabled",    1)
mkBind(sP,"Sprint Key",               cfg.sprint,"key",        2)
mkSld(sP,"Sprint Speed",              cfg.sprint,"speed",      16,120,3)
mkSld(sP,"Default Walkspeed",         cfg.sprint,"default_spd",8, 50, 4)

mkSec(mP,"TARGETING",0)
mkTog(mP,"NPC / Bot Mode",cfg.misc,"npc_mode",1,"targets humanoid NPCs · Scoped / bot games",function(on)
    if on then
        rebuildModelCache()
        for obj in pairs(modelCache) do registerESP(obj) end
    else
        for k in pairs(pool) do
            if typeof(k)=="Instance" and k:IsA("Model") then destroyESP(k) end
        end
        modelCache={}
    end
end)
mkSec(mP,"MAGIC BULLET",2)
mkTog(mP,"Magic Bullet",cfg.misc,"magic_bullet",3,
    "redirects bullets to locked target · requires aimbot lock")
mkTog(mP,"MB Debug Log",cfg.misc,"mb_debug",4,
    "prints magic bullet events to console — turn off when not diagnosing")
mkSec(mP,"MINIMAP",4)
mkTog(mP,"Minimap",      cfg.minimap,"enabled", 5,"north-up terrain map · arrow = cam dir · drag to reposition")
mkTog(mP,"FOV Cone",     cfg.minimap,"fov_cone",6,"yellow wedge showing camera field of view on radar")
mkSld(mP,"Radar Size",   cfg.minimap,"size",    100,300,7,nil,true)
mkSld(mP,"Radar Range",  cfg.minimap,"range",    50,500,8,"studs radius shown")
mkSec(mP,"VISUALS",9)
mkTog(mP,"FOV Circle",   cfg.misc,"fov_circle",10)
mkTog(mP,"Crosshair",    cfg.misc,"crosshair", 11)
mkSld(mP,"Crosshair Size",cfg.misc,"ch_size",  7,30,12)
mkSec(mP,"COMBAT",13)
mkTog(mP,"Bhop",          cfg.misc,"bhop",       14,"auto-rejump on landing while space held")
mkTog(mP,"Noclip",        cfg.misc,"noclip",     15,"disables character collision · toggle off to restore")
mkSec(mP,"ALARM",16)
mkTog(mP,"Proximity Alarm",cfg.misc,"prox_alarm",17,"pulsing red border when enemy is close")
mkSld(mP,"Alarm Distance", cfg.misc,"prox_dist",  5,200,18,"studs · triggers alarm at this range")
mkSec(aP,"AUTO SWITCH",19)
mkTog(aP,"Auto Retarget",  cfg.aim,"auto_switch",20,"immediately locks new target when current dies · disable to hold fire until key re-pressed")
mkSec(eP,"DISTANCE FADE",14)
mkTog(eP,"Distance Fade",  cfg.esp,"dist_fade",  15,"ESP elements fade out as enemies get farther away")
mkSld(eP,"Fade Start (st)",cfg.esp,"fade_start",  0,500,16,"full opacity within this range")
mkSld(eP,"Fade End (st)",  cfg.esp,"fade_end",    0,500,17,"fully invisible beyond this range")

mkSec(aP,"KEYBIND",21)
mkBind(aP,"Aimbot Toggle Key", cfg.keys,"aim",   22)
mkSec(eP,"KEYBIND",18)
mkBind(eP,"ESP Toggle Key",    cfg.keys,"esp",   19)
mkSec(mP,"KEYBINDS",19)
mkBind(mP,"Bhop Toggle Key",   cfg.keys,"bhop",  20)
mkBind(mP,"Noclip Toggle Key", cfg.keys,"noclip",21)

tabPanes["Aimbot"].Visible=true
TweenService:Create(tabBtns["Aimbot"],TweenInfo.new(0),{BackgroundColor3=TABON,TextColor3=TXA}):Play()
end  -- settings UI build block

-- // ═══════════════ PROXIMITY ALARM ═════════════════ //
-- full-screen red vignette border that pulses (sin-wave) when the nearest
-- enemy is within cfg.misc.prox_dist studs.  zero cost when idle.

local proxFrame = Instance.new("Frame")
proxFrame.Name                    = "NexusProxAlarm"
proxFrame.Size                    = UDim2.new(1, 0, 1, 0)
proxFrame.BackgroundTransparency  = 1
proxFrame.BorderSizePixel         = 0
proxFrame.ZIndex                  = 50
proxFrame.Visible                 = false
proxFrame.Parent                  = SG

local proxStroke = Instance.new("UIStroke", proxFrame)
proxStroke.Color     = Color3.fromRGB(220, 30, 30)
proxStroke.Thickness = 14
proxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local proxActive = false
conn(RunService.Heartbeat:Connect(function()
    if not cfg.misc.prox_alarm then
        proxFrame.Visible = false
        proxActive = false
        return
    end
    local myChar2 = lp.Character
    local myRoot2 = myChar2 and myChar2:FindFirstChild("HumanoidRootPart")
    if not myRoot2 then proxFrame.Visible = false; return end
    local myP2 = myRoot2.Position
    local nearest = math.huge
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == lp then continue end
        local root2 = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        local hum2  = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
        if root2 and isAlive(hum2) then
            local d = (myP2 - root2.Position).Magnitude
            if d < nearest then nearest = d end
        end
    end
    proxActive = nearest <= cfg.misc.prox_dist
    proxFrame.Visible = proxActive
    if proxActive then
        -- sin-wave pulse: 0.3 ↔ 0.85 at ~2 Hz
        proxStroke.Transparency = 0.3 + 0.55 * (0.5 + 0.5 * math.sin(tick() * math.pi * 2 * 2))
    end
end))

-- // ════════════════ MINIMAP ═════════════════════════ //
-- north-up terrain radar with wall-accurate geometry
-- dual-layer raycast: near probe (playerY+1 → -3) catches walls at body height → very dark
-- far probe (playerY-2 → -400) finds actual floor → real part color + normal lighting
-- 48×48 grid at 3-stud tile resolution means a 2-stud wall shows as a distinct dark strip
-- tiles cached by world coord + vertical band → persistent, never rescanned unless you move floors
-- sorted centre-first fill so radar builds inward from your position

local MM_EDOT    = 6
local MM_SELF    = 10
local GRID_N     = 48         -- 48×48 = 2304 cells, ~1809 inside circle
local TILE_SZ    = 3          -- 3-stud tile cache → walls render at true pixel width
local SCAN_BATCH = 24         -- tiles scanned per heartbeat (each costs 2 raycasts)
local MM_Y_BAND  = 8          -- vertical slice in studs for cache key (handles stairs)

-- COD-style tactical palette
local MM_LOCK_COL  = GOLD
local MM_ENEMY_COL = Color3.fromRGB(220, 45,  45)   -- punchy red
local MM_TEAM_COL  = Color3.fromRGB(80,  200, 90)
local MM_BDR_COL   = Color3.fromRGB(90,  115, 78)   -- military olive border
local MM_RING_COL  = Color3.fromRGB(42,  55,  38)   -- subtle olive rings
local MM_VOID_COL  = Color3.fromRGB(10,  12,  10)   -- near-black, slight green tinge
local MM_SCAN_COL  = Color3.fromRGB(15,  18,  14)   -- scan-pending (marginally lighter)

-- material → COD floor colour table
-- muted, desaturated military palette so the map reads like a real tactical radar
-- build MM_MAT safely: invalid/missing enum names are silently skipped
-- so a game running an older or different material set won't crash the script
local MM_MAT = (function()
    local t = {}
    local function add(name, col)
        local ok, m = pcall(function() return Enum.Material[name] end)
        if ok and m then t[m] = col end
    end
    add("Grass",         Color3.fromRGB(42, 58, 36))
    add("LeafyGrass",    Color3.fromRGB(38, 55, 32))
    add("Ground",        Color3.fromRGB(55, 50, 38))
    add("Mud",           Color3.fromRGB(48, 40, 30))
    add("Sand",          Color3.fromRGB(80, 72, 50))
    add("Salt",          Color3.fromRGB(82, 80, 72))
    add("Sandstone",     Color3.fromRGB(74, 62, 44))
    add("SmoothPlastic", Color3.fromRGB(52, 60, 66))
    add("Plastic",       Color3.fromRGB(50, 58, 64))
    add("Concrete",      Color3.fromRGB(50, 55, 60))
    add("Asphalt",       Color3.fromRGB(34, 38, 40))
    add("Pavement",      Color3.fromRGB(44, 48, 52))
    add("Cobblestone",   Color3.fromRGB(50, 53, 56))
    add("Brick",         Color3.fromRGB(64, 44, 36))
    add("Rock",          Color3.fromRGB(46, 50, 54))
    add("SmoothRock",    Color3.fromRGB(54, 57, 62))
    add("Limestone",     Color3.fromRGB(66, 63, 56))
    add("Basalt",        Color3.fromRGB(30, 33, 35))
    add("Slate",         Color3.fromRGB(40, 44, 47))
    add("Marble",        Color3.fromRGB(76, 74, 70))
    add("Metal",         Color3.fromRGB(50, 57, 64))
    add("DiamondPlate",  Color3.fromRGB(54, 61, 68))
    add("Foil",          Color3.fromRGB(56, 63, 70))
    add("Wood",          Color3.fromRGB(54, 43, 31))
    add("WoodPlanks",    Color3.fromRGB(50, 41, 29))
    add("Fabric",        Color3.fromRGB(48, 46, 43))
    add("Water",         Color3.fromRGB(26, 50, 66))
    add("Ice",           Color3.fromRGB(60, 74, 84))
    add("Glacier",       Color3.fromRGB(63, 76, 86))
    add("Snow",          Color3.fromRGB(72, 78, 82))
    add("Glass",         Color3.fromRGB(52, 66, 76))
    add("Neon",          Color3.fromRGB(68, 80, 86))
    add("Pebble",        Color3.fromRGB(48, 51, 54))
    add("CrackedLava",   Color3.fromRGB(72, 30, 20))
    add("Lava",          Color3.fromRGB(78, 34, 18))
    return t
end)()

-- floor colour: material palette + normal-based brightness
local function mmFloorCol(inst, normalY)
    local base = MM_MAT[inst.Material]
    if not base then
        -- unknown material: desaturate part colour and push toward military midtone
        local c   = inst.Color
        local lum = c.R * 0.299 + c.G * 0.587 + c.B * 0.114
        base = Color3.new(lum * 0.28 + 0.030, lum * 0.32 + 0.030, lum * 0.27 + 0.025)
    end
    local lf = math.clamp(normalY * 0.35 + 0.72, 0.50, 1.0)
    return Color3.new(base.R * lf, base.G * lf, base.B * lf)
end

-- wall colour: same palette, significantly darker so walls read as solid shapes
local function mmWallCol(inst)
    local base = MM_MAT[inst.Material]
    if base then
        return Color3.new(base.R * 0.32, base.G * 0.32, base.B * 0.32)
    end
    local c   = inst.Color
    local lum = c.R * 0.299 + c.G * 0.587 + c.B * 0.114
    return Color3.new(lum * 0.07 + 0.012, lum * 0.08 + 0.012, lum * 0.07 + 0.010)
end

-- tile cache: ["tx,tz,ys"] = Color3   (persists entire script session)
local tileCache   = {}
local queuedTiles = {}  -- ["tx,tz,ys"] = true
local scanQueue   = {}  -- { {tx, tz, ys}, ... }

local scanParams   = RaycastParams.new()
scanParams.FilterType = Enum.RaycastFilterType.Exclude
local scanParamAge = 0

-- dual-layer scan: wall probe first, floor probe if clear
local function scanTileAt(wx, wz, playerY)
    local wRay = workspace:Raycast(
        Vector3.new(wx, playerY + 1.0, wz),
        Vector3.new(0, -4.5, 0),
        scanParams
    )
    if wRay and wRay.Instance and wRay.Instance:IsA("BasePart") then
        return mmWallCol(wRay.Instance)
    end
    local fRay = workspace:Raycast(
        Vector3.new(wx, playerY - 2.5, wz),
        Vector3.new(0, -400, 0),
        scanParams
    )
    if not fRay or not fRay.Instance or not fRay.Instance:IsA("BasePart") then
        return MM_VOID_COL
    end
    return mmFloorCol(fRay.Instance, fRay.Normal.Y)
end

-- ── GUI ───────────────────────────────────────────────────────

local mmFrame = Instance.new("Frame")
mmFrame.Name               = "NexusMinimap"
mmFrame.Size               = UDim2.new(0, cfg.minimap.size, 0, cfg.minimap.size)
mmFrame.Position           = UDim2.new(0, 14, 1, -(cfg.minimap.size + 14))
mmFrame.BackgroundTransparency = 1
mmFrame.Visible            = false
mmFrame.ZIndex             = 10
mmFrame.Parent             = SG

-- void background disk
do
    local mmBG = Instance.new("Frame")
    mmBG.Size               = UDim2.new(1,0,1,0)
    mmBG.BackgroundColor3   = MM_VOID_COL
    mmBG.BackgroundTransparency = 0
    mmBG.BorderSizePixel    = 0
    mmBG.ZIndex             = 10
    mmBG.Parent             = mmFrame
    Instance.new("UICorner", mmBG).CornerRadius = UDim.new(0.5, 0)
end

-- 48×48 terrain grid (all frames created once; layout set by rebuildGrid)
local gridCells = {}
local mmHalfN   = GRID_N * 0.5
for gi = 1, GRID_N do
    gridCells[gi] = {}
    for gj = 1, GRID_N do
        local f = Instance.new("Frame")
        f.BorderSizePixel  = 0
        f.ZIndex           = 11
        f.BackgroundColor3 = MM_VOID_COL
        f.Visible          = false
        f.Parent           = mmFrame
        gridCells[gi][gj]  = f
    end
end

-- precompute in-circle cells sorted closest-to-centre-first
-- this list drives BOTH the colour update loop and the scan queue order
-- so the radar builds inward from your position rather than from a corner
local mmSortedCells = (function()
    local list = {}
    for gi = 1, GRID_N do
        for gj = 1, GRID_N do
            local dx   = gi - mmHalfN - 0.5
            local dy   = gj - mmHalfN - 0.5
            local dist = math.sqrt(dx*dx + dy*dy)
            if dist <= mmHalfN - 0.3 then
                list[#list+1] = {gi=gi, gj=gj, dist=dist}
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end)()

-- range rings
do
    local function makeRing(frac)
        local r = Instance.new("Frame")
        r.AnchorPoint       = Vector2.new(0.5, 0.5)
        r.Position          = UDim2.new(0.5, 0, 0.5, 0)
        r.Size              = UDim2.new(frac, 0, frac, 0)
        r.BackgroundTransparency = 1
        r.BorderSizePixel   = 0
        r.ZIndex            = 20
        r.Parent            = mmFrame
        Instance.new("UICorner", r).CornerRadius = UDim.new(0.5, 0)
        local s = Instance.new("UIStroke", r)
        s.Color     = MM_RING_COL
        s.Thickness = 1
    end
    makeRing(0.45)
    makeRing(0.78)
end

-- compass "N"
do
    local mmNLabel = Instance.new("TextLabel")
    mmNLabel.Text               = "N"
    mmNLabel.Size               = UDim2.new(0, 14, 0, 10)
    mmNLabel.AnchorPoint        = Vector2.new(0.5, 0.5)
    mmNLabel.Position           = UDim2.new(0.5, 0, 0, 7)
    mmNLabel.Font               = Enum.Font.GothamBold
    mmNLabel.TextSize           = 8
    mmNLabel.TextColor3         = Color3.fromRGB(148, 185, 125)
    mmNLabel.BackgroundTransparency = 1
    mmNLabel.ZIndex             = 25
    mmNLabel.Parent             = mmFrame
end

-- range readout at bottom (e.g. "150 st")
local mmRngLabel = Instance.new("TextLabel")
mmRngLabel.Size              = UDim2.new(0, 70, 0, 10)
mmRngLabel.AnchorPoint       = Vector2.new(0.5, 0.5)
mmRngLabel.Position          = UDim2.new(0.5, 0, 1, -8)
mmRngLabel.Font              = Enum.Font.Gotham
mmRngLabel.TextSize          = 7
mmRngLabel.TextColor3        = Color3.fromRGB(110, 140, 90)
mmRngLabel.BackgroundTransparency = 1
mmRngLabel.ZIndex            = 25
mmRngLabel.Parent            = mmFrame

-- camera direction arrow (pivot at bottom → rotates around self-dot)
-- 0° = north,  90° = east,  derived from atan2(look.X, -look.Z)
local mmArrow = Instance.new("Frame")
mmArrow.AnchorPoint      = Vector2.new(0.5, 1)
mmArrow.Size             = UDim2.new(0, 2, 0, 14)
mmArrow.Position         = UDim2.new(0.5, 0, 0.5, 0)
mmArrow.BackgroundColor3 = Color3.fromRGB(240, 242, 238)  -- near-white: matches self-dot, not gold (gold = locked)
mmArrow.BackgroundTransparency = 0
mmArrow.BorderSizePixel  = 0
mmArrow.ZIndex           = 26
mmArrow.Parent           = mmFrame
Instance.new("UICorner", mmArrow).CornerRadius = UDim.new(1, 0)

-- FOV cone: two thin lines showing camera horizontal FOV wedge on radar
-- each line is a 1px-wide frame rotated to camera_angle ± fov/2 degrees,
-- anchored at the center self-dot so they radiate outward
local mmFovL = Instance.new("Frame")
mmFovL.AnchorPoint        = Vector2.new(0.5, 1)
mmFovL.Size               = UDim2.new(0, 1, 0, 0)  -- length set in heartbeat
mmFovL.Position           = UDim2.new(0.5, 0, 0.5, 0)
mmFovL.BackgroundColor3   = Color3.fromRGB(255, 220, 60)
mmFovL.BackgroundTransparency = 0.45
mmFovL.BorderSizePixel    = 0
mmFovL.ZIndex             = 23
mmFovL.Visible            = false
mmFovL.Parent             = mmFrame

local mmFovR = Instance.new("Frame")
mmFovR.AnchorPoint        = Vector2.new(0.5, 1)
mmFovR.Size               = UDim2.new(0, 1, 0, 0)
mmFovR.Position           = UDim2.new(0.5, 0, 0.5, 0)
mmFovR.BackgroundColor3   = Color3.fromRGB(255, 220, 60)
mmFovR.BackgroundTransparency = 0.45
mmFovR.BorderSizePixel    = 0
mmFovR.ZIndex             = 23
mmFovR.Visible            = false
mmFovR.Parent             = mmFrame

-- border ring on top: covers jagged cell edges at the rim
do
    local mmBdrRing = Instance.new("Frame")
    mmBdrRing.Size               = UDim2.new(1,0,1,0)
    mmBdrRing.BackgroundTransparency = 1
    mmBdrRing.BorderSizePixel    = 0
    mmBdrRing.ZIndex             = 29
    mmBdrRing.Parent             = mmFrame
    Instance.new("UICorner", mmBdrRing).CornerRadius = UDim.new(0.5, 0)
    local mmBdrStroke = Instance.new("UIStroke", mmBdrRing)
    mmBdrStroke.Color     = MM_BDR_COL
    mmBdrStroke.Thickness = 2
    mmBdrStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

-- player dot with a subtle blue outline for contrast against bright floors
do
    local mmSelfDot = Instance.new("Frame")
    mmSelfDot.AnchorPoint      = Vector2.new(0.5, 0.5)
    mmSelfDot.Size             = UDim2.new(0, MM_SELF, 0, MM_SELF)
    mmSelfDot.Position         = UDim2.new(0.5, 0, 0.5, 0)
    mmSelfDot.BackgroundColor3 = WHITE
    mmSelfDot.BorderSizePixel  = 0
    mmSelfDot.ZIndex           = 27
    mmSelfDot.Parent           = mmFrame
    Instance.new("UICorner", mmSelfDot).CornerRadius = UDim.new(1, 0)
    local mmSelfStroke = Instance.new("UIStroke", mmSelfDot)
    mmSelfStroke.Color     = Color3.fromRGB(90, 115, 78)   -- olive outline matches border
    mmSelfStroke.Thickness = 1
    mmSelfStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

-- entity dot pool
local mmDots = {}

local function mmGetDot(key)
    if mmDots[key] then return mmDots[key] end
    local d = Instance.new("Frame")
    d.Size             = UDim2.new(0, MM_EDOT, 0, MM_EDOT)
    d.BackgroundColor3 = MM_ENEMY_COL
    d.BorderSizePixel  = 0
    d.ZIndex           = 24
    d.Visible          = false
    d.Parent           = mmFrame
    Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)
    -- white outline: makes dots readable against both dark walls and light floors
    local ds = Instance.new("UIStroke", d)
    ds.Color     = Color3.fromRGB(255, 255, 255)
    ds.Thickness = 1
    ds.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    mmDots[key] = d
    return d
end

local function mmDestroyDot(key)
    if mmDots[key] then
        pcall(function() mmDots[key]:Destroy() end)
        mmDots[key] = nil
    end
end

-- ── terrain state (separate from per-frame dot logic) ─────────
-- snap position: only re-queue tiles when player crosses a tile-grid boundary
-- (prevents constant re-queuing as the player drifts within a single tile)
local mmSnapTx    = nil   -- last snapped tile X
local mmSnapTz    = nil   -- last snapped tile Z
local mmSnapYs    = nil   -- last snapped y-slice
local mmLastRange2 = -1   -- detect range slider changes independently
local mmNeedsRedraw = true -- dirty flag: redraw terrain cell colours this frame?

-- dynamic batch: burst-scan on initial load, quieter maintenance after
local function mmBatch()
    local n = #scanQueue
    if     n > 500 then return 100
    elseif n > 100 then return 50
    elseif n >   0 then return 20
    else                return 0
    end
end

-- ── grid layout (pixel positions — only recalculated when the size slider moves) ──

local mmLastSz = -1

local function rebuildGrid(sz)
    mmLastSz     = sz
    local cellPx = sz / GRID_N
    -- position visible cells from the sorted list
    for _, cell in ipairs(mmSortedCells) do
        local f = gridCells[cell.gi][cell.gj]
        f.Position = UDim2.new(0, (cell.gi-1)*cellPx, 0, (cell.gj-1)*cellPx)
        f.Size     = UDim2.new(0, math.ceil(cellPx)+1, 0, math.ceil(cellPx)+1)
        f.Visible  = true
    end
    -- explicitly hide corner cells outside the circle
    for gi = 1, GRID_N do
        for gj = 1, GRID_N do
            local dx = gi - mmHalfN - 0.5
            local dy = gj - mmHalfN - 0.5
            if math.sqrt(dx*dx + dy*dy) > mmHalfN - 0.3 then
                gridCells[gi][gj].Visible = false
            end
        end
    end
end

-- ── heartbeat ─────────────────────────────────────────────────

conn(RunService.Heartbeat:Connect(function()
    local sz    = cfg.minimap.size
    local range = cfg.minimap.range

    mmFrame.Size    = UDim2.new(0, sz, 0, sz)
    mmFrame.Visible = cfg.minimap.enabled

    if not cfg.minimap.enabled then
        for _, d in pairs(mmDots) do d.Visible = false end
        return
    end

    if sz ~= mmLastSz then rebuildGrid(sz) end

    local myChar = lp.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local myPos  = myRoot.Position
    local look   = cam.CFrame.LookVector
    -- vertical band: groups 8 studs of elevation so the cache stays valid on ramps
    -- but correctly separates multi-floor buildings
    local ySlice = math.floor(myPos.Y / MM_Y_BAND) * MM_Y_BAND

    local camDeg = math.deg(math.atan2(look.X, -look.Z))
    mmArrow.Rotation = camDeg
    mmRngLabel.Text  = range .. " st"

    -- FOV cone: two lines spanning ~80 % of radar radius at ±half-fov from cam direction
    if cfg.minimap.fov_cone then
        local halfFov  = cam.FieldOfView * 0.5
        local coneLen  = math.floor(sz * 0.43)  -- 43 % of diameter ≈ 86 % of radius
        mmFovL.Size    = UDim2.new(0, 1, 0, coneLen)
        mmFovR.Size    = UDim2.new(0, 1, 0, coneLen)
        mmFovL.Rotation = camDeg - halfFov
        mmFovR.Rotation = camDeg + halfFov
        mmFovL.Visible  = true
        mmFovR.Visible  = true
    else
        mmFovL.Visible = false
        mmFovR.Visible = false
    end

    -- refresh character exclusion list every 5 s
    if tick() - scanParamAge > 5 then
        scanParamAge = tick()
        local ex = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Character then table.insert(ex, p.Character) end
        end
        scanParams.FilterDescendantsInstances = ex
    end

    -- ── tile queuing: only fires when player crosses a tile boundary ──
    -- tiles are keyed by absolute world position, so the cache is permanent.
    -- re-queuing only happens when myPos floor-divides into a new tile coord
    -- or when the range/ySlice changes — never on sub-tile drift.
    local txSnap = math.floor(myPos.X / TILE_SZ)
    local tzSnap = math.floor(myPos.Z / TILE_SZ)
    local snapChanged = txSnap ~= mmSnapTx
                     or tzSnap ~= mmSnapTz
                     or ySlice ~= mmSnapYs
                     or range  ~= mmLastRange2

    if snapChanged then
        mmSnapTx     = txSnap
        mmSnapTz     = tzSnap
        mmSnapYs     = ySlice
        mmLastRange2 = range
        mmNeedsRedraw = true
        -- queue every in-range tile that isn't already cached or pending
        local studsPerCell = (2 * range) / GRID_N
        for _, cell in ipairs(mmSortedCells) do
            local dx  = (cell.gi - mmHalfN - 0.5) * studsPerCell
            local dz  = (cell.gj - mmHalfN - 0.5) * studsPerCell
            local tx  = math.floor((myPos.X + dx) / TILE_SZ)
            local tz  = math.floor((myPos.Z + dz) / TILE_SZ)
            local key = tx..","..tz..","..ySlice
            if not tileCache[key] and not queuedTiles[key] then
                queuedTiles[key] = true
                scanQueue[#scanQueue+1] = {tx=tx, tz=tz, ys=ySlice}
            end
        end
    end

    -- ── scan queue: dynamic burst rate (fast initial fill, idle when done) ──
    local batchN = mmBatch()
    if batchN > 0 then
        for _ = 1, batchN do
            local tile = table.remove(scanQueue, 1)
            if not tile then break end
            local k = tile.tx..","..tile.tz..","..tile.ys
            queuedTiles[k] = nil
            tileCache[k] = scanTileAt(
                (tile.tx + 0.5) * TILE_SZ,
                (tile.tz + 0.5) * TILE_SZ,
                tile.ys
            )
        end
        mmNeedsRedraw = true  -- freshly scanned tiles → update display
    end

    -- ── terrain display: redraws only when dirty, frozen otherwise ──
    -- when player is still and all tiles are cached: zero terrain frame cost,
    -- only entity dots keep updating.
    if mmNeedsRedraw then
        mmNeedsRedraw = #scanQueue > 0  -- stay dirty until queue drains
        local studsPerCell = (2 * range) / GRID_N
        for _, cell in ipairs(mmSortedCells) do
            local gi, gj = cell.gi, cell.gj
            local dx  = (gi - mmHalfN - 0.5) * studsPerCell
            local dz  = (gj - mmHalfN - 0.5) * studsPerCell
            local tx  = math.floor((myPos.X + dx) / TILE_SZ)
            local tz  = math.floor((myPos.Z + dz) / TILE_SZ)
            local key = tx..","..tz..","..ySlice
            gridCells[gi][gj].BackgroundColor3 =
                tileCache[key] or (queuedTiles[key] and MM_SCAN_COL or MM_VOID_COL)
        end
    end

    -- ── entity dots (north-up projection, no rotation needed) ─
    local halfSz   = sz * 0.5
    local maxR     = halfSz - MM_EDOT * 0.5 - 2
    local pixPerSt = maxR / math.max(range, 1)

    for _, d in pairs(mmDots) do d.Visible = false end

    -- locked target dot is 2px larger so it punches above the crowd
    local function placeDot(key, worldPos, col, locked)
        local sz2 = locked and (MM_EDOT + 3) or MM_EDOT
        local dx  = worldPos.X - myPos.X
        local dz  = worldPos.Z - myPos.Z
        local px  = dx * pixPerSt
        local py  = dz * pixPerSt
        local mag = math.sqrt(px*px + py*py)
        if mag > maxR then
            local inv = maxR / mag
            px = px * inv; py = py * inv
        end
        local d = mmGetDot(key)
        d.Size            = UDim2.new(0, sz2, 0, sz2)
        d.Position        = UDim2.new(0.5, px - sz2*0.5, 0.5, py - sz2*0.5)
        d.BackgroundColor3 = col
        d.Visible         = true
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr == lp then continue end
        local char = plr.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not (root and isAlive(hum)) then continue end
        local isLocked = lockedKey == plr
        local col
        if isLocked then
            col = MM_LOCK_COL
        elseif cfg.esp.team_check or cfg.aim.team_check then
            local mine  = getSignals(lp,  lp,  myChar)
            local their = getSignals(plr, plr, char)
            col = (next(mine) and sigMatch(mine, their)) and MM_TEAM_COL or MM_ENEMY_COL
        else
            col = MM_ENEMY_COL
        end
        placeDot(plr, root.Position, col, isLocked)
    end

    if cfg.misc.npc_mode then
        for obj in pairs(modelCache) do
            if obj == myChar then continue end
            local root = obj:FindFirstChild("HumanoidRootPart")
            local hum  = obj:FindFirstChildOfClass("Humanoid")
            if not (root and isAlive(hum)) then continue end
            local isLocked = lockedKey == obj
            placeDot(obj, root.Position, isLocked and MM_LOCK_COL or MM_ENEMY_COL, isLocked)
        end
    end
end))

conn(Players.PlayerRemoving:Connect(mmDestroyDot))

-- minimap drag (independent of main window drag)
do
    local mmDragging, mmDragStart, mmFrameStart = false, nil, nil
    conn(mmFrame.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            mmDragging   = true
            mmDragStart  = i.Position
            mmFrameStart = mmFrame.Position
        end
    end))
    conn(UIS.InputChanged:Connect(function(i)
        if mmDragging and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - mmDragStart
            mmFrame.Position = UDim2.new(
                mmFrameStart.X.Scale, mmFrameStart.X.Offset + d.X,
                mmFrameStart.Y.Scale, mmFrameStart.Y.Offset + d.Y)
        end
    end))
    conn(UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then mmDragging = false end
    end))
end

-- // ════════════════ UNLOAD ══════════════════════════ //

do
    local function unload()
        for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        RunService:UnbindFromRenderStep("NexusAim")
        pcall(function() fovCircle:Remove()  end)
        pcall(function() lockCircle:Remove() end)
        pcall(function() chH:Remove() end)
        pcall(function() chV:Remove() end)
        for key in pairs(pool) do destroyESP(key) end
        for key in pairs(mmDots) do mmDestroyDot(key) end
        pcall(function() mmFrame:Destroy() end)
        pcall(function() proxFrame:Destroy() end)
        -- restore noclip: re-enable collision on all character parts
        local char = lp.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function() part.CanCollide = true end)
                end
            end
        end
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 16 end
        SG:Destroy(); print("[NEXUS] unloaded")
    end
    UB.MouseButton1Click:Connect(unload)
end

do
    local drag2,ds2,wp2=false,nil,nil
    TB.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then drag2=true; ds2=i.Position; wp2=WIN.Position end
    end)
    conn(UIS.InputChanged:Connect(function(i)
        if drag2 and i.UserInputType==Enum.UserInputType.MouseMovement then
            local d=i.Position-ds2
            WIN.Position=UDim2.new(wp2.X.Scale,wp2.X.Offset+d.X,wp2.Y.Scale,wp2.Y.Offset+d.Y)
        end
    end))
    conn(UIS.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then drag2=false end
    end))
end
conn(UIS.InputBegan:Connect(function(i,gpe)
    if gpe then return end
    if i.KeyCode==Enum.KeyCode.RightAlt then WIN.Visible=not WIN.Visible end
end))

print("[NEXUS] ready"
    ..(IS_FL and " · FRONTLINES" or " · universal")
    .." · RightAlt=UI · RMB=aim · Shift+Q=lock")
