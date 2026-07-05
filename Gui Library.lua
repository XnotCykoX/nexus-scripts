-- ==============================================================================
-- APEX SUITE V5.2 - COMPLETE GUI LIBRARY ENGINE
-- ==============================================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local ParentUI = (pcall(function() return CoreGui.Name end) and CoreGui) or LocalPlayer:WaitForChild("PlayerGui")

local ApexLibrary = {}

local APEX = {
    BG_MAIN = Color3.fromRGB(10, 11, 15),
    BG_HEADER = Color3.fromRGB(14, 15, 20),
    BG_CARD = Color3.fromRGB(18, 20, 27),
    BG_TRACK = Color3.fromRGB(28, 30, 42),
    
    ACCENT_CYAN = Color3.fromRGB(0, 242, 254),
    ACCENT_BLUE = Color3.fromRGB(79, 172, 254),
    
    TEXT_MAIN = Color3.fromRGB(250, 250, 255),
    TEXT_MUTED = Color3.fromRGB(130, 135, 155),
    BORDER_DARK = Color3.fromRGB(30, 33, 46),
    BORDER_LIGHT = Color3.fromRGB(65, 70, 95),
    
    RADIUS_CARD = UDim.new(0, 8),
    RADIUS_PILL = UDim.new(1, 0),
    
    TWEEN_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    TWEEN_SPRING = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

local function applyGlassEdge(instance)
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 1
    stroke.Parent = instance

    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, APEX.BORDER_LIGHT),
        ColorSequenceKeypoint.new(1, APEX.BORDER_DARK)
    })
    gradient.Rotation = 90
    gradient.Parent = stroke
    return stroke
end

local function applyAccentGradient(instance, rotation)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, APEX.ACCENT_CYAN),
        ColorSequenceKeypoint.new(1, APEX.ACCENT_BLUE)
    })
    gradient.Rotation = rotation or 0
    gradient.Parent = instance
    return gradient
end

local function bindDragging(dragHandle, targetFrame)
    local dragging, dragInput, mousePos, framePos
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            mousePos = input.Position
            framePos = targetFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - mousePos
            targetFrame.Position = UDim2.new(framePos.X.Scale, framePos.X.Offset + delta.X, framePos.Y.Scale, framePos.Y.Offset + delta.Y)
        end
    end)
end

function ApexLibrary:CreateWindow(windowTitle)
    local WindowAPI = { Tabs = {}, ToggleKey = Enum.KeyCode.RightShift, Minimized = false }
    
    -- Destroy old instance if re-executing
    if ParentUI:FindFirstChild("ApexLibrary_UI") then
        ParentUI.ApexLibrary_UI:Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ApexLibrary_UI"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.Parent = ParentUI

    -- Global Toggle Key Listener
    UserInputService.InputBegan:Connect(function(input, gpe)
        if not gpe and input.KeyCode == WindowAPI.ToggleKey then
            screenGui.Enabled = not screenGui.Enabled
        end
    end)

    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 600, 0, 440)
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.BackgroundColor3 = APEX.BG_MAIN
    mainFrame.BorderSizePixel = 0
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui
    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)
    applyGlassEdge(mainFrame)

    local headerBar = Instance.new("Frame")
    headerBar.Size = UDim2.new(1, 0, 0, 42)
    headerBar.BackgroundColor3 = APEX.BG_HEADER
    headerBar.BorderSizePixel = 0
    headerBar.ZIndex = 10
    headerBar.Parent = mainFrame

    local divider = Instance.new("Frame")
    divider.Size = UDim2.new(1, 0, 0, 1)
    divider.Position = UDim2.new(0, 0, 1, 0)
    divider.BackgroundColor3 = APEX.BORDER_DARK
    divider.BorderSizePixel = 0
    divider.ZIndex = 11
    divider.Parent = headerBar

    -- ========================================================
    -- FIXED WINDOW CONTROLS (macOS Dots with explicit layout)
    -- ========================================================
    local dotsContainer = Instance.new("Frame")
    dotsContainer.Size = UDim2.new(0, 60, 0, 16)
    dotsContainer.Position = UDim2.new(0, 14, 0, 13) -- Exact vertical center of 42px header
    dotsContainer.BackgroundTransparency = 1
    dotsContainer.ZIndex = 20
    dotsContainer.Parent = headerBar

    local dotLayout = Instance.new("UIListLayout")
    dotLayout.FillDirection = Enum.FillDirection.Horizontal
    dotLayout.Padding = UDim.new(0, 7)
    dotLayout.Parent = dotsContainer

    local function createDot(color, callback)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 12, 0, 12)
        btn.BackgroundColor3 = color
        btn.Text = ""
        btn.AutoButtonColor = false
        btn.ZIndex = 25
        btn.Parent = dotsContainer
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6) -- Exact half of 12px

        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, APEX.TWEEN_FAST, {BackgroundTransparency = 0.2}):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, APEX.TWEEN_FAST, {BackgroundTransparency = 0}):Play()
        end)
        if callback then
            btn.MouseButton1Click:Connect(callback)
        end
        return btn
    end

    -- Red: Close / Hide UI
    createDot(Color3.fromRGB(255, 90, 82), function()
        screenGui.Enabled = false
    end)

    -- Yellow: Minimize / Expand UI
    createDot(Color3.fromRGB(230, 192, 41), function()
        WindowAPI.Minimized = not WindowAPI.Minimized
        TweenService:Create(mainFrame, APEX.TWEEN_SPRING, {
            Size = WindowAPI.Minimized and UDim2.new(0, 600, 0, 42) or UDim2.new(0, 600, 0, 440)
        }):Play()
    end)

    -- Green: Maximize (Reset Size)
    createDot(Color3.fromRGB(83, 215, 105), function()
        TweenService:Create(mainFrame, APEX.TWEEN_SPRING, {Size = UDim2.new(0, 600, 0, 440)}):Play()
        mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    end)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -200, 1, 0)
    title.Position = UDim2.new(0, 80, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = string.upper(windowTitle or "APEX SUITE")
    title.TextColor3 = APEX.TEXT_MUTED
    title.TextSize = 12
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 11
    title.Parent = headerBar

    -- ========================================================
    -- SIDEBAR & TAB CONTAINER
    -- ========================================================
    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0, 160, 1, -43)
    sidebar.Position = UDim2.new(0, 0, 0, 43)
    sidebar.BackgroundTransparency = 1
    sidebar.Parent = mainFrame

    local sideDivider = Instance.new("Frame")
    sideDivider.Size = UDim2.new(0, 1, 1, 0)
    sideDivider.Position = UDim2.new(1, 0, 0, 0)
    sideDivider.BackgroundColor3 = APEX.BORDER_DARK
    sideDivider.BorderSizePixel = 0
    sideDivider.Parent = sidebar

    -- Reduced height (-52) to leave space for settings button at bottom
    local tabContainer = Instance.new("ScrollingFrame")
    tabContainer.Size = UDim2.new(1, -24, 1, -56)
    tabContainer.Position = UDim2.new(0, 12, 0, 14)
    tabContainer.BackgroundTransparency = 1
    tabContainer.ScrollBarThickness = 0
    tabContainer.Parent = sidebar

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0, 6)
    tabLayout.Parent = tabContainer

    local contentFrame = Instance.new("Frame")
    contentFrame.Size = UDim2.new(1, -161, 1, -43)
    contentFrame.Position = UDim2.new(0, 161, 0, 43)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = mainFrame

    bindDragging(headerBar, mainFrame)
    bindDragging(sidebar, mainFrame)

    -- ========================================================
    -- INTERNAL SETTINGS OVERLAY PANEL
    -- ========================================================
    local settingsPanel = Instance.new("ScrollingFrame")
    settingsPanel.Size = UDim2.new(1, -36, 1, -24)
    settingsPanel.Position = UDim2.new(0, 18, 0, 14)
    settingsPanel.BackgroundTransparency = 1
    settingsPanel.ScrollBarThickness = 2
    settingsPanel.ScrollBarImageColor3 = APEX.BORDER_LIGHT
    settingsPanel.Visible = false
    settingsPanel.ZIndex = 15
    settingsPanel.Parent = contentFrame

    local settingsLayout = Instance.new("UIListLayout")
    settingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    settingsLayout.Padding = UDim.new(0, 10)
    settingsLayout.Parent = settingsPanel

    -- Pinned Bottom-Left Settings Button
    local settingsBtn = Instance.new("TextButton")
    settingsBtn.Size = UDim2.new(1, -24, 0, 32)
    settingsBtn.Position = UDim2.new(0, 12, 1, -40)
    settingsBtn.BackgroundColor3 = APEX.BG_CARD
    settingsBtn.TextColor3 = APEX.TEXT_MUTED
    settingsBtn.TextSize = 12
    settingsBtn.Font = Enum.Font.GothamBold
    settingsBtn.Text = "⚙   Settings"
    settingsBtn.AutoButtonColor = false
    settingsBtn.Parent = sidebar
    Instance.new("UICorner", settingsBtn).CornerRadius = APEX.RADIUS_CARD
    applyGlassEdge(settingsBtn)

    local isSettingsOpen = false
    settingsBtn.MouseButton1Click:Connect(function()
        isSettingsOpen = not isSettingsOpen
        if isSettingsOpen then
            for _, t in ipairs(WindowAPI.Tabs) do
                TweenService:Create(t.Button, APEX.TWEEN_FAST, {BackgroundTransparency = 1, TextColor3 = APEX.TEXT_MUTED}):Play()
                t.Indicator.Visible = false
                t.Content.Visible = false
            end
            TweenService:Create(settingsBtn, APEX.TWEEN_FAST, {BackgroundColor3 = APEX.BG_TRACK, TextColor3 = APEX.ACCENT_CYAN}):Play()
            settingsPanel.Visible = true
        else
            TweenService:Create(settingsBtn, APEX.TWEEN_FAST, {BackgroundColor3 = APEX.BG_CARD, TextColor3 = APEX.TEXT_MUTED}):Play()
            settingsPanel.Visible = false
            if #WindowAPI.Tabs > 0 then
                local firstTab = WindowAPI.Tabs[1]
                TweenService:Create(firstTab.Button, APEX.TWEEN_FAST, {BackgroundTransparency = 0.3, TextColor3 = APEX.TEXT_MAIN}):Play()
                firstTab.Indicator.Visible = true
                firstTab.Content.Visible = true
            end
        end
    end)

    -- POPULATE INTERNAL SETTINGS PANEL
    local function createSectionHeader(parent, text)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 24)
        container.BackgroundTransparency = 1
        container.Parent = parent

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(0, 160, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = string.upper(text)
        label.TextColor3 = APEX.ACCENT_CYAN
        label.TextSize = 11
        label.Font = Enum.Font.GothamBold
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = container

        local line = Instance.new("Frame")
        line.Size = UDim2.new(1, -label.TextBounds.X - 15, 0, 1)
        line.Position = UDim2.new(0, label.TextBounds.X + 10, 0.5, 0)
        line.BackgroundColor3 = APEX.BORDER_DARK
        line.BorderSizePixel = 0
        line.Parent = container
    end

    createSectionHeader(settingsPanel, "Menu Controls")

    -- DYNAMIC UI TOGGLE KEYBIND COMPONENT inside Settings Panel
    local keybindContainer = Instance.new("Frame")
    keybindContainer.Size = UDim2.new(1, 0, 0, 46)
    keybindContainer.BackgroundColor3 = APEX.BG_CARD
    keybindContainer.Parent = settingsPanel
    Instance.new("UICorner", keybindContainer).CornerRadius = APEX.RADIUS_CARD
    applyGlassEdge(keybindContainer)

    local keybindTitle = Instance.new("TextLabel")
    keybindTitle.Size = UDim2.new(1, -140, 1, 0)
    keybindTitle.Position = UDim2.new(0, 16, 0, 0)
    keybindTitle.BackgroundTransparency = 1
    keybindTitle.Text = "Menu Toggle Keybind"
    keybindTitle.TextColor3 = APEX.TEXT_MAIN
    keybindTitle.TextSize = 13
    keybindTitle.Font = Enum.Font.GothamMedium
    keybindTitle.TextXAlignment = Enum.TextXAlignment.Left
    keybindTitle.Parent = keybindContainer

    local keybindBtn = Instance.new("TextButton")
    keybindBtn.Size = UDim2.new(0, 110, 0, 26)
    keybindBtn.Position = UDim2.new(1, -126, 0.5, -13)
    keybindBtn.BackgroundColor3 = APEX.BG_TRACK
    keybindBtn.TextColor3 = APEX.ACCENT_CYAN
    keybindBtn.TextSize = 12
    keybindBtn.Font = Enum.Font.GothamBold
    keybindBtn.Text = WindowAPI.ToggleKey.Name
    keybindBtn.Parent = keybindContainer
    Instance.new("UICorner", keybindBtn).CornerRadius = UDim.new(0, 6)

    local bindingToggle = false
    keybindBtn.MouseButton1Click:Connect(function()
        bindingToggle = true
        keybindBtn.Text = "Press any key..."
    end)

    UserInputService.InputBegan:Connect(function(input)
        if bindingToggle and input.UserInputType == Enum.UserInputType.Keyboard then
            bindingToggle = false
            WindowAPI.ToggleKey = input.KeyCode
            keybindBtn.Text = input.KeyCode.Name
        end
    end)

    createSectionHeader(settingsPanel, "System Operations")

    -- UNLOAD / DESTROY UI BUTTON
    local unloadBtn = Instance.new("TextButton")
    unloadBtn.Size = UDim2.new(1, 0, 0, 42)
    unloadBtn.BackgroundColor3 = Color3.fromRGB(40, 20, 25)
    unloadBtn.TextColor3 = Color3.fromRGB(255, 90, 82)
    unloadBtn.TextSize = 13
    unloadBtn.Font = Enum.Font.GothamBold
    unloadBtn.Text = "Unload & Destroy Interface"
    unloadBtn.AutoButtonColor = false
    unloadBtn.Parent = settingsPanel
    Instance.new("UICorner", unloadBtn).CornerRadius = APEX.RADIUS_CARD
    applyGlassEdge(unloadBtn)

    unloadBtn.MouseButton1Click:Connect(function()
        screenGui:Destroy()
    end)

    -- ========================================================
    -- API: TAB & ELEMENT BUILDER
    -- ========================================================
    function WindowAPI:CreateTab(tabName)
        local TabAPI = {}
        
        local tabBtn = Instance.new("TextButton")
        tabBtn.Size = UDim2.new(1, 0, 0, 36)
        tabBtn.BackgroundTransparency = 1
        tabBtn.BackgroundColor3 = APEX.BG_CARD
        tabBtn.TextColor3 = APEX.TEXT_MUTED
        tabBtn.TextSize = 13
        tabBtn.Font = Enum.Font.GothamMedium
        tabBtn.Text = "    " .. tabName
        tabBtn.TextXAlignment = Enum.TextXAlignment.Left
        tabBtn.AutoButtonColor = false
        tabBtn.Parent = tabContainer
        Instance.new("UICorner", tabBtn).CornerRadius = APEX.RADIUS_CARD

        local indicator = Instance.new("Frame")
        indicator.Size = UDim2.new(0, 3, 0, 18)
        indicator.Position = UDim2.new(0, 6, 0.5, -9)
        indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        indicator.Visible = false
        indicator.Parent = tabBtn
        Instance.new("UICorner", indicator).CornerRadius = UDim.new(0, 100)
        applyAccentGradient(indicator, 180)

        local tabContent = Instance.new("ScrollingFrame")
        tabContent.Size = UDim2.new(1, -36, 1, -24)
        tabContent.Position = UDim2.new(0, 18, 0, 14)
        tabContent.BackgroundTransparency = 1
        tabContent.ScrollBarThickness = 2
        tabContent.ScrollBarImageColor3 = APEX.BORDER_LIGHT
        tabContent.Visible = false
        tabContent.Parent = contentFrame

        local listLayout = Instance.new("UIListLayout")
        listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        listLayout.Padding = UDim.new(0, 10)
        listLayout.Parent = tabContent

        listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            tabContent.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 15)
        end)

        local tabData = { Button = tabBtn, Content = tabContent, Indicator = indicator }
        table.insert(WindowAPI.Tabs, tabData)

        tabBtn.MouseButton1Click:Connect(function()
            isSettingsOpen = false
            settingsPanel.Visible = false
            TweenService:Create(settingsBtn, APEX.TWEEN_FAST, {BackgroundColor3 = APEX.BG_CARD, TextColor3 = APEX.TEXT_MUTED}):Play()

            for _, t in ipairs(WindowAPI.Tabs) do
                TweenService:Create(t.Button, APEX.TWEEN_FAST, {BackgroundTransparency = 1, TextColor3 = APEX.TEXT_MUTED}):Play()
                t.Indicator.Visible = false
                t.Content.Visible = false
            end
            TweenService:Create(tabBtn, APEX.TWEEN_FAST, {BackgroundTransparency = 0.3, TextColor3 = APEX.TEXT_MAIN}):Play()
            indicator.Visible = true
            tabContent.Visible = true
        end)

        if #WindowAPI.Tabs == 1 then
            tabBtn.BackgroundTransparency = 0.3
            tabBtn.TextColor3 = APEX.TEXT_MAIN
            indicator.Visible = true
            tabContent.Visible = true
        end

        function TabAPI:CreateSection(text)
            createSectionHeader(tabContent, text)
        end

        function TabAPI:CreateToggle(label, default, callback)
            local container = Instance.new("TextButton")
            container.Size = UDim2.new(1, 0, 0, 46)
            container.BackgroundColor3 = APEX.BG_CARD
            container.Text = ""
            container.AutoButtonColor = false
            container.Parent = tabContent
            Instance.new("UICorner", container).CornerRadius = APEX.RADIUS_CARD
            applyGlassEdge(container)

            local titleLabel = Instance.new("TextLabel")
            titleLabel.Size = UDim2.new(1, -80, 1, 0)
            titleLabel.Position = UDim2.new(0, 16, 0, 0)
            titleLabel.BackgroundTransparency = 1
            titleLabel.Text = label
            titleLabel.TextColor3 = APEX.TEXT_MAIN
            titleLabel.TextSize = 13
            titleLabel.Font = Enum.Font.GothamMedium
            titleLabel.TextXAlignment = Enum.TextXAlignment.Left
            titleLabel.Parent = container

            local track = Instance.new("Frame")
            track.Size = UDim2.new(0, 42, 0, 22)
            track.Position = UDim2.new(1, -58, 0.5, -11)
            track.BackgroundColor3 = default and Color3.fromRGB(255, 255, 255) or APEX.BG_TRACK
            track.BorderSizePixel = 0
            track.Parent = container
            Instance.new("UICorner", track).CornerRadius = UDim.new(0, 100)
            
            local trackGrad = applyAccentGradient(track, 0)
            trackGrad.Enabled = default

            local thumb = Instance.new("Frame")
            thumb.Size = UDim2.new(0, 16, 0, 16)
            thumb.Position = default and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
            thumb.BackgroundColor3 = APEX.TEXT_MAIN
            thumb.Parent = track
            Instance.new("UICorner", thumb).CornerRadius = UDim.new(0, 100)

            local state = default
            container.MouseButton1Click:Connect(function()
                state = not state
                trackGrad.Enabled = state
                TweenService:Create(track, APEX.TWEEN_FAST, {BackgroundColor3 = state and Color3.fromRGB(255, 255, 255) or APEX.BG_TRACK}):Play()
                TweenService:Create(thumb, APEX.TWEEN_SPRING, {Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)}):Play()
                if callback then callback(state) end
            end)
        end

        function TabAPI:CreateSlider(label, min, max, default, callback)
            local container = Instance.new("Frame")
            container.Size = UDim2.new(1, 0, 0, 60)
            container.BackgroundColor3 = APEX.BG_CARD
            container.Parent = tabContent
            Instance.new("UICorner", container).CornerRadius = APEX.RADIUS_CARD
            applyGlassEdge(container)

            local titleLabel = Instance.new("TextLabel")
            titleLabel.Size = UDim2.new(0.6, 0, 0, 20)
            titleLabel.Position = UDim2.new(0, 16, 0, 10)
            titleLabel.BackgroundTransparency = 1
            titleLabel.Text = label
            titleLabel.TextColor3 = APEX.TEXT_MAIN
            titleLabel.TextSize = 13
            titleLabel.Font = Enum.Font.GothamMedium
            titleLabel.TextXAlignment = Enum.TextXAlignment.Left
            titleLabel.Parent = container

            local valDisplay = Instance.new("TextLabel")
            valDisplay.Size = UDim2.new(0, 50, 0, 20)
            valDisplay.Position = UDim2.new(1, -66, 0, 10)
            valDisplay.BackgroundTransparency = 1
            valDisplay.Text = tostring(default)
            valDisplay.TextColor3 = APEX.ACCENT_CYAN
            valDisplay.TextSize = 13
            valDisplay.Font = Enum.Font.Code
            valDisplay.TextXAlignment = Enum.TextXAlignment.Right
            valDisplay.Parent = container

            local hitbox = Instance.new("TextButton")
            hitbox.Size = UDim2.new(1, -32, 0, 24)
            hitbox.Position = UDim2.new(0, 16, 0, 28)
            hitbox.BackgroundTransparency = 1
            hitbox.Text = ""
            hitbox.Parent = container

            local track = Instance.new("Frame")
            track.Size = UDim2.new(1, 0, 0, 6)
            track.Position = UDim2.new(0, 0, 0.5, -3)
            track.BackgroundColor3 = APEX.BG_TRACK
            track.BorderSizePixel = 0
            track.Parent = hitbox
            Instance.new("UICorner", track).CornerRadius = UDim.new(0, 100)

            local fill = Instance.new("Frame")
            fill.Size = UDim2.new(0, 0, 1, 0)
            fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            fill.BorderSizePixel = 0
            fill.Parent = track
            Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 100)
            applyAccentGradient(fill, 0)

            local handle = Instance.new("Frame")
            handle.Size = UDim2.new(0, 16, 0, 16)
            handle.AnchorPoint = Vector2.new(0.5, 0.5)
            handle.Position = UDim2.new(0, 0, 0.5, 0)
            handle.BackgroundColor3 = APEX.TEXT_MAIN
            handle.Parent = track
            Instance.new("UICorner", handle).CornerRadius = UDim.new(0, 100)

            local handleRing = Instance.new("UIStroke")
            handleRing.Color = APEX.ACCENT_CYAN
            handleRing.Thickness = 2
            handleRing.Parent = handle

            local dragging = false
            local function update(inputX)
                local percent = math.clamp((inputX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                local val = math.floor(min + (max - min) * percent + 0.5)
                handle.Position = UDim2.new(percent, 0, 0.5, 0)
                fill.Size = UDim2.new(percent, 0, 1, 0)
                valDisplay.Text = tostring(val)
                if callback then callback(val) end
            end

            hitbox.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    dragging = true
                    TweenService:Create(handle, APEX.TWEEN_FAST, {Size = UDim2.new(0, 18, 0, 18)}):Play()
                    update(input.Position.X)
                end
            end)

            UserInputService.InputChanged:Connect(function(input)
                if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                    update(input.Position.X)
                end
            end)

            UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    dragging = false
                    TweenService:Create(handle, APEX.TWEEN_FAST, {Size = UDim2.new(0, 16, 0, 16)}):Play()
                end
            end)

            local initPercent = math.clamp((default - min) / (max - min), 0, 1)
            handle.Position = UDim2.new(initPercent, 0, 0.5, 0)
            fill.Size = UDim2.new(initPercent, 0, 1, 0)
        end

        function TabAPI:CreateInput(label, placeholder, callback)
            local container = Instance.new("Frame")
            container.Size = UDim2.new(1, 0, 0, 46)
            container.BackgroundColor3 = APEX.BG_CARD
            container.Parent = tabContent
            Instance.new("UICorner", container).CornerRadius = APEX.RADIUS_CARD
            applyGlassEdge(container)

            local titleLabel = Instance.new("TextLabel")
            titleLabel.Size = UDim2.new(0.5, 0, 1, 0)
            titleLabel.Position = UDim2.new(0, 16, 0, 0)
            titleLabel.BackgroundTransparency = 1
            titleLabel.Text = label
            titleLabel.TextColor3 = APEX.TEXT_MAIN
            titleLabel.TextSize = 13
            titleLabel.Font = Enum.Font.GothamMedium
            titleLabel.TextXAlignment = Enum.TextXAlignment.Left
            titleLabel.Parent = container

            local box = Instance.new("TextBox")
            box.Size = UDim2.new(0, 140, 0, 28)
            box.Position = UDim2.new(1, -156, 0.5, -14)
            box.BackgroundColor3 = APEX.BG_TRACK
            box.TextColor3 = APEX.TEXT_MAIN
            box.PlaceholderColor3 = APEX.TEXT_MUTED
            box.PlaceholderText = placeholder or "Type here..."
            box.Text = ""
            box.TextSize = 12
            box.Font = Enum.Font.GothamMedium
            box.Parent = container
            Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

            box.FocusLost:Connect(function(enterPressed)
                if callback then callback(box.Text, enterPressed) end
            end)
        end

        return TabAPI
    end

    return WindowAPI
end


-- ==============================================================================
-- SIMPLE USAGE EXAMPLE
-- ==============================================================================

--local Window = ApexLibrary:CreateWindow("NEXUS // HUB V1.0")

--local CombatTab = Window:CreateTab("Combat")
--CombatTab:CreateSection("Aim Assist")
--CombatTab:CreateToggle("Enable Silent Aim", false, function(state) print("Aim:", state) end)

--local GeneralTab = Window:CreateTab("General")
--GeneralTab:CreateSection("Customization")
--GeneralTab:CreateInput("Config Name", "MyLegitConfig", function(text) print("Saved:", text) end)
--GeneralTab:CreateSlider("FOV Circle Size", 10, 500, 100, function(val) print("FOV:", val) end)