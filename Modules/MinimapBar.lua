local _, ns = ...
local WaitQOL = ns.WaitQOL
local AG = ns.AG

local HANDLE_THICKNESS = 4

local MinimapBarModule = {
    displayName = "Minimap Bar",
    order = 4,
    barFrame = nil,
    handleFrame = nil,
    capturedButtons = {},  -- [name] = button frame
    collapsed = false,
    initialized = false,
    dragging = nil,  -- name of button currently being dragged
}

function MinimapBarModule:GetDefaults()
    return {
        enabled = false,
        orientation = "HORIZONTAL",
        iconsPerRow = 8,
        iconSize = 28,
        iconSpacing = 2,
        bgColor = { r = 0, g = 0, b = 0, a = 0.6 },
        padding = 4,
        anchorPoint = "TOPRIGHT",
        anchorFrame = "MinimapCluster",
        anchorRelativePoint = "BOTTOMRIGHT",
        anchorOffsetX = 0,
        anchorOffsetY = 0,
        hideMinimapTextures = true,
        handleColor = { r = 0.2, g = 0.2, b = 0.2, a = 0.8 },
        buttonOrder = {},       -- persisted ordered list of button names
        excludedButtons = {},   -- [name] = true for buttons kept on minimap
    }
end

-- Get LibDBIcon reference
local function GetLibDBIcon()
    return LibStub("LibDBIcon-1.0", true)
end

-- Check if a button name belongs to a Blizzard/built-in addon
local function IsBlizzardButton(name)
    if name:find("^Blizzard") then return true end
    -- Known Blizzard minimap entries registered via LibDBIcon
    local blizzardNames = {
        ["ExpansionLandingPage"] = true,
        ["GameTimeFrame"] = true,
        ["MiniMapTracking"] = true,
        ["MiniMapMailFrame"] = true,
        ["AddonCompartment"] = true,
    }
    return blizzardNames[name] or false
end

-- Derive layout directions from anchor point and orientation
local function GetLayoutDirections(savedVars)
    local anchor = savedVars.anchorPoint or "TOPRIGHT"
    local isHorizontal = savedVars.orientation == "HORIZONTAL"

    local hasLeft = anchor:find("LEFT")
    local hasRight = anchor:find("RIGHT")
    local hasTop = anchor:find("TOP")
    local hasBottom = anchor:find("BOTTOM")

    if isHorizontal then
        local handleEdge = hasLeft and "LEFT" or "RIGHT"
        local primaryDir = hasLeft and 1 or -1
        local secondaryDir = hasBottom and -1 or 1
        return handleEdge, primaryDir, secondaryDir
    else
        local handleEdge = hasBottom and "BOTTOM" or "TOP"
        local primaryDir = hasBottom and -1 or 1
        local secondaryDir = hasLeft and 1 or -1
        return handleEdge, primaryDir, secondaryDir
    end
end

-- Get the ordered list of button names for layout
-- Uses persisted order, appending any new buttons not yet in the list
local function GetOrderedNames(module)
    local savedVars = module.savedVars
    local order = savedVars.buttonOrder
    local excluded = savedVars.excludedButtons

    -- Build a set of names currently in the order list
    local inOrder = {}
    for _, name in ipairs(order) do
        inOrder[name] = true
    end

    -- Append any captured buttons not yet in the order list (sorted for consistency)
    local newNames = {}
    for name in pairs(module.capturedButtons) do
        if not inOrder[name] then
            table.insert(newNames, name)
        end
    end
    table.sort(newNames)
    for _, name in ipairs(newNames) do
        table.insert(order, name)
    end

    -- Filter to only buttons that are captured, not excluded, and not hidden
    local result = {}
    for _, name in ipairs(order) do
        local button = module.capturedButtons[name]
        if button and not excluded[name] and (not button.db or not button.db.hide) then
            table.insert(result, name)
        end
    end

    return result
end

-- Strip minimap-specific visuals from a button
local function StyleButton(button, iconSize, hideTextures)
    button:SetSize(iconSize, iconSize)

    if hideTextures then
        for _, region in pairs({ button:GetRegions() }) do
            if region:IsObjectType("Texture") then
                local tex = region:GetTexture()
                if tex == 136430 or tex == 136467 then
                    region:Hide()
                end
                local layer = region:GetDrawLayer()
                if layer == "ARTWORK" then
                    region:ClearAllPoints()
                    region:SetAllPoints(button)
                end
            end
        end
    end
end

-- Forward declarations
local LayoutButtons, PositionHandle

-- Set up drag-to-reorder handlers on a button
local function SetupDragHandlers(module, button, name)
    button:RegisterForDrag("LeftButton")

    button:SetScript("OnDragStart", function(self)
        module.dragging = name
        self:SetAlpha(0.4)
        self:StartMoving()
    end)

    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetAlpha(1)

        if not module.dragging then return end

        -- Determine which position the button was dropped on
        local cx, cy = GetCursorPosition()
        local scale = module.barFrame:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale

        local savedVars = module.savedVars
        local orderedNames = GetOrderedNames(module)
        local iconSize = savedVars.iconSize
        local spacing = savedVars.iconSpacing
        local padding = savedVars.padding
        local perRow = savedVars.iconsPerRow or 8
        local isHorizontal = savedVars.orientation == "HORIZONTAL"
        local _, primaryDir, secondaryDir = GetLayoutDirections(savedVars)

        local barLeft, barBottom = module.barFrame:GetLeft(), module.barFrame:GetBottom()
        local barTop = module.barFrame:GetTop()
        local barRight = module.barFrame:GetRight()

        -- Calculate which slot the cursor is closest to
        local bestIdx = 1
        local bestDist = math.huge

        local primarySize = padding * 2 + math.min(#orderedNames, perRow) * iconSize + (math.min(#orderedNames, perRow) - 1) * spacing
        local secondaryCount = math.ceil(#orderedNames / perRow)
        local secondarySize = padding * 2 + secondaryCount * iconSize + (secondaryCount - 1) * spacing

        for i = 1, #orderedNames do
            local idx = i - 1
            local col = idx % perRow
            local row = math.floor(idx / perRow)
            local pOff = padding + col * (iconSize + spacing) + iconSize / 2
            local sOff = padding + row * (iconSize + spacing) + iconSize / 2

            local bx, by
            if isHorizontal then
                local x = primaryDir > 0 and pOff or (primarySize - pOff)
                local y = secondaryDir > 0 and sOff or (secondarySize - sOff)
                bx = barLeft + x
                by = barTop - y
            else
                local y = primaryDir > 0 and pOff or (primarySize - pOff)
                local x = secondaryDir > 0 and sOff or (secondarySize - sOff)
                bx = barLeft + x
                by = barTop - y
            end

            local dist = (cx - bx) ^ 2 + (cy - by) ^ 2
            if dist < bestDist then
                bestDist = dist
                bestIdx = i
            end
        end

        -- Reorder: remove dragged name from its current position and insert at target
        local dragName = module.dragging
        module.dragging = nil

        local order = savedVars.buttonOrder
        -- Find and remove the dragged button from the order list
        local fromIdx
        for i, n in ipairs(order) do
            if n == dragName then
                fromIdx = i
                break
            end
        end
        if fromIdx then
            table.remove(order, fromIdx)
        end

        -- Find the name at the target visual position and insert before/after it
        local targetName = orderedNames[bestIdx]
        local insertIdx
        for i, n in ipairs(order) do
            if n == targetName then
                insertIdx = i
                break
            end
        end
        if insertIdx then
            table.insert(order, insertIdx, dragName)
        else
            table.insert(order, dragName)
        end

        LayoutButtons(module)
        PositionHandle(module)
    end)
end

-- Layout all captured buttons in a wrapping grid
LayoutButtons = function(module)
    local savedVars = module.savedVars
    if not savedVars or not module.barFrame then return end

    local iconSize = savedVars.iconSize
    local spacing = savedVars.iconSpacing
    local padding = savedVars.padding
    local isHorizontal = savedVars.orientation == "HORIZONTAL"
    local perRow = savedVars.iconsPerRow or 8
    local _, primaryDir, secondaryDir = GetLayoutDirections(savedVars)

    local orderedNames = GetOrderedNames(module)
    local count = #orderedNames

    if count == 0 then
        module.barFrame:SetSize(1, 1)
        return
    end

    -- Calculate grid dimensions
    local primaryCount = math.min(count, perRow)
    local secondaryCount = math.ceil(count / perRow)

    local primarySize = padding * 2 + primaryCount * iconSize + (primaryCount - 1) * spacing
    local secondarySize = padding * 2 + secondaryCount * iconSize + (secondaryCount - 1) * spacing

    if isHorizontal then
        module.barFrame:SetSize(primarySize, secondarySize)
    else
        module.barFrame:SetSize(secondarySize, primarySize)
    end

    -- Position each button
    for i, name in ipairs(orderedNames) do
        local button = module.capturedButtons[name]
        if button then
            button:ClearAllPoints()
            button:SetParent(module.barFrame)
            button:SetMovable(true)
            button:SetClampedToScreen(false)

            -- Strip original drag handlers and set up reorder drag
            StyleButton(button, iconSize, savedVars.hideMinimapTextures)
            SetupDragHandlers(module, button, name)

            local idx = i - 1
            local col = idx % perRow
            local row = math.floor(idx / perRow)

            local primaryOffset = padding + col * (iconSize + spacing)
            local secondaryOffset = padding + row * (iconSize + spacing)

            if isHorizontal then
                local x = primaryDir > 0
                    and primaryOffset
                    or (primarySize - primaryOffset - iconSize)
                local y = secondaryDir > 0
                    and secondaryOffset
                    or (secondarySize - secondaryOffset - iconSize)
                button:SetPoint("TOPLEFT", module.barFrame, "TOPLEFT", x, -y)
            else
                local y = primaryDir > 0
                    and primaryOffset
                    or (primarySize - primaryOffset - iconSize)
                local x = secondaryDir > 0
                    and secondaryOffset
                    or (secondarySize - secondaryOffset - iconSize)
                button:SetPoint("TOPLEFT", module.barFrame, "TOPLEFT", x, -y)
            end
        end
    end
end

-- Create the bar frame
local function CreateBarFrame(savedVars)
    local frame = _G["WaitQOL_MinimapBarFrame"]

    if frame then
        frame:ClearAllPoints()
    else
        frame = CreateFrame("Frame", "WaitQOL_MinimapBarFrame", UIParent, "BackdropTemplate")
        frame:SetFrameStrata("MEDIUM")
        frame:SetFrameLevel(5)
        frame:SetClampedToScreen(true)
    end

    local anchorFrame = _G[savedVars.anchorFrame] or UIParent
    frame:SetPoint(
        savedVars.anchorPoint or "TOPRIGHT",
        anchorFrame,
        savedVars.anchorRelativePoint or "BOTTOMRIGHT",
        savedVars.anchorOffsetX or 0,
        savedVars.anchorOffsetY or 0
    )

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    local bg = savedVars.bgColor
    frame:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
    frame:SetBackdropBorderColor(0, 0, 0, bg.a > 0 and 0.8 or 0)

    return frame
end

-- Fade the handle in or out
local function FadeHandle(module, fadeIn)
    local handle = module.handleFrame
    if not handle then return end

    if fadeIn then
        UIFrameFadeIn(handle, 0.2, handle:GetAlpha(), 1)
    else
        UIFrameFadeOut(handle, 0.3, handle:GetAlpha(), 0)
    end
end

-- Update handle alpha based on collapsed state (instant, no animation)
local function UpdateHandleAlpha(module)
    local handle = module.handleFrame
    if not handle then return end

    if module.collapsed then
        handle:SetAlpha(0)
    else
        handle:SetAlpha(1)
    end
end

-- Create or update the handle (thin clickable strip)
local function CreateHandle(module, savedVars)
    local handle = _G["WaitQOL_MinimapBarHandle"]

    if not handle then
        handle = CreateFrame("Button", "WaitQOL_MinimapBarHandle", UIParent, "BackdropTemplate")
        handle:SetFrameStrata("MEDIUM")
        handle:SetFrameLevel(6)
        handle:SetClampedToScreen(true)

        handle:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
        })

        handle:SetScript("OnEnter", function(self)
            local c = savedVars.handleColor
            handle:SetBackdropColor(
                math.min(c.r + 0.2, 1),
                math.min(c.g + 0.2, 1),
                math.min(c.b + 0.2, 1),
                math.min(c.a + 0.1, 1)
            )
            if module.collapsed then
                FadeHandle(module, true)
            end
        end)
        handle:SetScript("OnLeave", function(self)
            local c = savedVars.handleColor
            handle:SetBackdropColor(c.r, c.g, c.b, c.a)
            if module.collapsed then
                FadeHandle(module, false)
            end
        end)
        handle:SetScript("OnClick", function()
            module:ToggleBar()
        end)

        -- Hook Minimap to also reveal the handle on hover
        if Minimap then
            Minimap:HookScript("OnEnter", function()
                if module.collapsed and module.handleFrame and module.handleFrame:IsShown() then
                    FadeHandle(module, true)
                end
            end)
            Minimap:HookScript("OnLeave", function()
                if module.collapsed and module.handleFrame and module.handleFrame:IsShown() then
                    -- Only fade out if cursor isn't over the handle
                    if not module.handleFrame:IsMouseOver() then
                        FadeHandle(module, false)
                    end
                end
            end)
        end
    end

    local c = savedVars.handleColor
    handle:SetBackdropColor(c.r, c.g, c.b, c.a)

    return handle
end

-- Position the handle along the anchor edge of the bar
PositionHandle = function(module)
    local handle = module.handleFrame
    local bar = module.barFrame
    if not handle or not bar then return end

    local savedVars = module.savedVars
    local handleEdge = GetLayoutDirections(savedVars)

    handle:ClearAllPoints()

    if handleEdge == "RIGHT" then
        handle:SetSize(HANDLE_THICKNESS, math.max(bar:GetHeight(), 1))
        handle:SetPoint("TOPLEFT", bar, "TOPRIGHT", 0, 0)
    elseif handleEdge == "LEFT" then
        handle:SetSize(HANDLE_THICKNESS, math.max(bar:GetHeight(), 1))
        handle:SetPoint("TOPRIGHT", bar, "TOPLEFT", 0, 0)
    elseif handleEdge == "TOP" then
        handle:SetSize(math.max(bar:GetWidth(), 1), HANDLE_THICKNESS)
        handle:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 0)
    elseif handleEdge == "BOTTOM" then
        handle:SetSize(math.max(bar:GetWidth(), 1), HANDLE_THICKNESS)
        handle:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
    end
end

-- Capture all existing LibDBIcon buttons (excluding WaitQOL and excluded buttons)
local function CaptureAllButtons(module)
    local dbIcon = GetLibDBIcon()
    if not dbIcon then return end

    local savedVars = module.savedVars
    local excluded = savedVars.excludedButtons
    local names = dbIcon:GetButtonList()

    for _, name in ipairs(names) do
        if name ~= "WaitQOL" and not excluded[name] and not IsBlizzardButton(name) then
            if not module.capturedButtons[name] then
                local button = dbIcon:GetMinimapButton(name)
                if button then
                    module.capturedButtons[name] = button
                end
            end
        end
    end
end

-- Ensure WaitQOL's own minimap button retains its drag handlers
local function ProtectOwnButton()
    local dbIcon = GetLibDBIcon()
    if not dbIcon then return end

    local ownButton = dbIcon:GetMinimapButton("WaitQOL")
    if not ownButton then return end

    if not ownButton:GetScript("OnDragStart") then
        dbIcon:Unlock("WaitQOL")
    end
end

-- Ensure excluded buttons are visible on the minimap
local function RefreshExcludedButtons(module)
    local dbIcon = GetLibDBIcon()
    if not dbIcon then return end

    local excluded = module.savedVars.excludedButtons
    for name in pairs(excluded) do
        if name ~= "WaitQOL" then
            -- If it was previously captured, release it
            if module.capturedButtons[name] then
                local button = module.capturedButtons[name]
                button:SetScript("OnDragStart", nil)
                button:SetScript("OnDragStop", nil)
                button:SetParent(Minimap)
                button:ClearAllPoints()
                dbIcon:Refresh(name)
                module.capturedButtons[name] = nil
            end
        end
    end
end

-- Full refresh: recapture and relayout
local function FullRefresh(module)
    if not module.savedVars or not module.savedVars.enabled then return end
    if not module.barFrame then return end

    RefreshExcludedButtons(module)
    CaptureAllButtons(module)
    LayoutButtons(module)
    ProtectOwnButton()
    PositionHandle(module)

    if module.collapsed then
        module.barFrame:Hide()
    else
        module.barFrame:Show()
    end

    -- Handle is always shown but faded out when collapsed
    if module.handleFrame then
        module.handleFrame:Show()
        UpdateHandleAlpha(module)
    end
end

-- Hook for newly created icons (after initial load)
local function OnIconCreated(_, _, name)
    if not MinimapBarModule.savedVars or not MinimapBarModule.savedVars.enabled then return end
    if name == "WaitQOL" then return end
    if IsBlizzardButton(name) then return end
    if MinimapBarModule.savedVars.excludedButtons[name] then return end

    local dbIcon = GetLibDBIcon()
    if not dbIcon then return end

    C_Timer.After(0.1, function()
        local button = dbIcon:GetMinimapButton(name)
        if button and not MinimapBarModule.capturedButtons[name] then
            MinimapBarModule.capturedButtons[name] = button
            LayoutButtons(MinimapBarModule)
            PositionHandle(MinimapBarModule)
            ProtectOwnButton()
        end
    end)
end

-- Public: Toggle the bar visibility
function MinimapBarModule:ToggleBar()
    if not self.savedVars or not self.savedVars.enabled then
        WaitQOL:Print("Minimap Bar is not enabled. Enable it in /wqol settings.")
        return
    end

    self.collapsed = not self.collapsed

    if self.collapsed then
        if self.barFrame then
            self.barFrame:Hide()
        end
        FadeHandle(self, false)
    else
        if self.barFrame then
            self.barFrame:Show()
            LayoutButtons(self)
            PositionHandle(self)
        end
        if self.handleFrame then
            self.handleFrame:SetAlpha(1)
        end
    end
end

function MinimapBarModule:OnInitialize(savedVars)
    self.savedVars = savedVars
    self.collapsed = true

    -- Ensure tables exist (migration from older saved vars)
    if not savedVars.buttonOrder then savedVars.buttonOrder = {} end
    if not savedVars.excludedButtons then savedVars.excludedButtons = {} end

    if not savedVars.enabled then return end

    self.barFrame = CreateBarFrame(savedVars)
    self.barFrame:Hide()
    self.handleFrame = CreateHandle(self, savedVars)
    self.handleFrame:Hide()

    -- Wait for PLAYER_ENTERING_WORLD so all other addons have registered their buttons
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(frame)
        frame:UnregisterEvent("PLAYER_ENTERING_WORLD")

        local dbIcon = GetLibDBIcon()
        if dbIcon and dbIcon.RegisterCallback then
            dbIcon.RegisterCallback(self, "LibDBIcon_IconCreated", OnIconCreated)
        end

        C_Timer.After(0.5, function()
            self.initialized = true
            FullRefresh(self)
        end)
    end)
end

function MinimapBarModule:OnEnable()
    -- No-op: initialization is handled by OnInitialize + PLAYER_ENTERING_WORLD
end

function MinimapBarModule:OnDisable()
    -- No-op: disabling requires a UI reload
end

function MinimapBarModule:CreateConfigPanel(container, savedVars)
    local function Refresh()
        if self.barFrame then
            self.barFrame = CreateBarFrame(savedVars)
        end
        if self.initialized then
            FullRefresh(self)
        end
    end

    local scrollFrame = AG:Create("ScrollFrame")
    scrollFrame:SetLayout("Flow")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    container:AddChild(scrollFrame)

    -- Title
    local title = AG:Create("Heading")
    title:SetText("Minimap Bar Configuration")
    title:SetFullWidth(true)
    scrollFrame:AddChild(title)

    local desc = AG:Create("Label")
    desc:SetText("Collects minimap addon buttons into a collapsible bar. Right-click the WaitQOL minimap button or click the handle strip to toggle. Drag icons to reorder them.")
    desc:SetFullWidth(true)
    scrollFrame:AddChild(desc)

    local UpdateControlsVisibility

    -- Enable checkbox (requires reload)
    local enableCheck = AG:Create("CheckBox")
    enableCheck:SetLabel("Enable Minimap Bar")
    enableCheck:SetDescription("Requires UI reload to take effect")
    enableCheck:SetValue(savedVars.enabled)
    enableCheck:SetFullWidth(true)
    enableCheck:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.enabled = value
        UpdateControlsVisibility()
        StaticPopup_Show("WAITQOL_RELOAD_UI")
    end)
    scrollFrame:AddChild(enableCheck)

    -- ==== LAYOUT SECTION ====
    local layoutSection = AG:Create("InlineGroup")
    layoutSection:SetTitle("Layout")
    layoutSection:SetLayout("Flow")
    layoutSection:SetFullWidth(true)
    scrollFrame:AddChild(layoutSection)

    local orientationDropdown = AG:Create("Dropdown")
    orientationDropdown:SetLabel("Orientation")
    orientationDropdown:SetList({
        HORIZONTAL = "Horizontal",
        VERTICAL = "Vertical",
    })
    orientationDropdown:SetValue(savedVars.orientation)
    orientationDropdown:SetRelativeWidth(0.5)
    orientationDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.orientation = value
        Refresh()
    end)
    layoutSection:AddChild(orientationDropdown)

    local iconsPerRowSlider = AG:Create("Slider")
    iconsPerRowSlider:SetLabel("Icons Per Row")
    iconsPerRowSlider:SetSliderValues(1, 20, 1)
    iconsPerRowSlider:SetValue(savedVars.iconsPerRow)
    iconsPerRowSlider:SetRelativeWidth(0.5)
    iconsPerRowSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.iconsPerRow = value
        Refresh()
    end)
    layoutSection:AddChild(iconsPerRowSlider)

    local iconSizeSlider = AG:Create("Slider")
    iconSizeSlider:SetLabel("Icon Size")
    iconSizeSlider:SetSliderValues(16, 48, 1)
    iconSizeSlider:SetValue(savedVars.iconSize)
    iconSizeSlider:SetRelativeWidth(0.5)
    iconSizeSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.iconSize = value
        Refresh()
    end)
    layoutSection:AddChild(iconSizeSlider)

    local spacingSlider = AG:Create("Slider")
    spacingSlider:SetLabel("Icon Spacing")
    spacingSlider:SetSliderValues(0, 16, 1)
    spacingSlider:SetValue(savedVars.iconSpacing)
    spacingSlider:SetRelativeWidth(0.5)
    spacingSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.iconSpacing = value
        Refresh()
    end)
    layoutSection:AddChild(spacingSlider)

    local paddingSlider = AG:Create("Slider")
    paddingSlider:SetLabel("Padding")
    paddingSlider:SetSliderValues(0, 16, 1)
    paddingSlider:SetValue(savedVars.padding)
    paddingSlider:SetRelativeWidth(0.5)
    paddingSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.padding = value
        Refresh()
    end)
    layoutSection:AddChild(paddingSlider)

    -- ==== APPEARANCE SECTION ====
    local appearanceSection = AG:Create("InlineGroup")
    appearanceSection:SetTitle("Appearance")
    appearanceSection:SetLayout("Flow")
    appearanceSection:SetFullWidth(true)
    scrollFrame:AddChild(appearanceSection)

    local bgColorPicker = AG:Create("ColorPicker")
    bgColorPicker:SetLabel("Background Color")
    bgColorPicker:SetHasAlpha(true)
    bgColorPicker:SetColor(
        savedVars.bgColor.r,
        savedVars.bgColor.g,
        savedVars.bgColor.b,
        savedVars.bgColor.a
    )
    bgColorPicker:SetRelativeWidth(0.5)
    bgColorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
        savedVars.bgColor = { r = r, g = g, b = b, a = a }
        if self.barFrame then
            self.barFrame:SetBackdropColor(r, g, b, a)
            self.barFrame:SetBackdropBorderColor(0, 0, 0, a > 0 and 0.8 or 0)
        end
    end)
    appearanceSection:AddChild(bgColorPicker)

    local handleColorPicker = AG:Create("ColorPicker")
    handleColorPicker:SetLabel("Handle Color")
    handleColorPicker:SetHasAlpha(true)
    handleColorPicker:SetColor(
        savedVars.handleColor.r,
        savedVars.handleColor.g,
        savedVars.handleColor.b,
        savedVars.handleColor.a
    )
    handleColorPicker:SetRelativeWidth(0.5)
    handleColorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
        savedVars.handleColor = { r = r, g = g, b = b, a = a }
        if self.handleFrame then
            self.handleFrame:SetBackdropColor(r, g, b, a)
        end
    end)
    appearanceSection:AddChild(handleColorPicker)

    local hideTexCheck = AG:Create("CheckBox")
    hideTexCheck:SetLabel("Hide minimap button textures")
    hideTexCheck:SetDescription("Removes the circular border/background from icons")
    hideTexCheck:SetValue(savedVars.hideMinimapTextures)
    hideTexCheck:SetFullWidth(true)
    hideTexCheck:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.hideMinimapTextures = value
        Refresh()
    end)
    appearanceSection:AddChild(hideTexCheck)

    -- ==== BUTTONS SECTION (exclude/include per button) ====
    local buttonsSection = AG:Create("InlineGroup")
    buttonsSection:SetTitle("Buttons")
    buttonsSection:SetLayout("Flow")
    buttonsSection:SetFullWidth(true)
    scrollFrame:AddChild(buttonsSection)

    local buttonsDesc = AG:Create("Label")
    buttonsDesc:SetText("Uncheck a button to keep it on the minimap instead of the bar. Requires UI reload.")
    buttonsDesc:SetFullWidth(true)
    buttonsSection:AddChild(buttonsDesc)

    -- List all known LibDBIcon buttons
    local dbIcon = GetLibDBIcon()
    local buttonCheckboxes = {}
    if dbIcon then
        local allNames = dbIcon:GetButtonList()
        table.sort(allNames)
        for _, name in ipairs(allNames) do
            if name ~= "WaitQOL" and not IsBlizzardButton(name) then
                local cb = AG:Create("CheckBox")
                cb:SetLabel(name)
                cb:SetValue(not savedVars.excludedButtons[name])
                cb:SetRelativeWidth(0.5)
                cb:SetCallback("OnValueChanged", function(_, _, value)
                    if value then
                        savedVars.excludedButtons[name] = nil
                    else
                        savedVars.excludedButtons[name] = true
                    end
                    StaticPopup_Show("WAITQOL_RELOAD_UI")
                end)
                buttonsSection:AddChild(cb)
                table.insert(buttonCheckboxes, cb)
            end
        end
    end

    -- ==== POSITION SECTION ====
    local positionSection = AG:Create("InlineGroup")
    positionSection:SetTitle("Position")
    positionSection:SetLayout("Flow")
    positionSection:SetFullWidth(true)
    scrollFrame:AddChild(positionSection)

    local anchorPointsList = {
        TOPLEFT = "Top Left",
        TOP = "Top",
        TOPRIGHT = "Top Right",
        LEFT = "Left",
        CENTER = "Center",
        RIGHT = "Right",
        BOTTOMLEFT = "Bottom Left",
        BOTTOM = "Bottom",
        BOTTOMRIGHT = "Bottom Right",
    }

    local anchorPointDropdown = AG:Create("Dropdown")
    anchorPointDropdown:SetLabel("Anchor Point")
    anchorPointDropdown:SetList(anchorPointsList)
    anchorPointDropdown:SetValue(savedVars.anchorPoint)
    anchorPointDropdown:SetRelativeWidth(0.33)
    anchorPointDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorPoint = value
        Refresh()
    end)
    positionSection:AddChild(anchorPointDropdown)

    local framesList = {
        ["UIParent"] = "UIParent (Screen)",
        ["MinimapCluster"] = "MinimapCluster",
        ["Minimap"] = "Minimap",
    }
    local targetFrameDropdown = AG:Create("Dropdown")
    targetFrameDropdown:SetLabel("Target Frame")
    targetFrameDropdown:SetList(framesList)
    targetFrameDropdown:SetValue(savedVars.anchorFrame)
    targetFrameDropdown:SetRelativeWidth(0.33)
    targetFrameDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorFrame = value
        Refresh()
    end)
    positionSection:AddChild(targetFrameDropdown)

    local targetAnchorDropdown = AG:Create("Dropdown")
    targetAnchorDropdown:SetLabel("Target Anchor")
    targetAnchorDropdown:SetList(anchorPointsList)
    targetAnchorDropdown:SetValue(savedVars.anchorRelativePoint)
    targetAnchorDropdown:SetRelativeWidth(0.33)
    targetAnchorDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorRelativePoint = value
        Refresh()
    end)
    positionSection:AddChild(targetAnchorDropdown)

    local xOffsetSlider = AG:Create("Slider")
    xOffsetSlider:SetLabel("X Offset")
    xOffsetSlider:SetSliderValues(-400, 400, 1)
    xOffsetSlider:SetValue(savedVars.anchorOffsetX)
    xOffsetSlider:SetRelativeWidth(0.5)
    xOffsetSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorOffsetX = value
        Refresh()
    end)
    positionSection:AddChild(xOffsetSlider)

    local yOffsetSlider = AG:Create("Slider")
    yOffsetSlider:SetLabel("Y Offset")
    yOffsetSlider:SetSliderValues(-400, 400, 1)
    yOffsetSlider:SetValue(savedVars.anchorOffsetY)
    yOffsetSlider:SetRelativeWidth(0.5)
    yOffsetSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorOffsetY = value
        Refresh()
    end)
    positionSection:AddChild(yOffsetSlider)

    UpdateControlsVisibility = function()
        local enabled = savedVars.enabled
        orientationDropdown:SetDisabled(not enabled)
        iconsPerRowSlider:SetDisabled(not enabled)
        iconSizeSlider:SetDisabled(not enabled)
        spacingSlider:SetDisabled(not enabled)
        paddingSlider:SetDisabled(not enabled)
        bgColorPicker:SetDisabled(not enabled)
        handleColorPicker:SetDisabled(not enabled)
        hideTexCheck:SetDisabled(not enabled)
        for _, cb in ipairs(buttonCheckboxes) do
            cb:SetDisabled(not enabled)
        end
        anchorPointDropdown:SetDisabled(not enabled)
        targetFrameDropdown:SetDisabled(not enabled)
        targetAnchorDropdown:SetDisabled(not enabled)
        xOffsetSlider:SetDisabled(not enabled)
        yOffsetSlider:SetDisabled(not enabled)
    end

    UpdateControlsVisibility()

    C_Timer.After(0, function()
        scrollFrame:DoLayout()
    end)
end

-- Register reload confirmation dialog
StaticPopupDialogs["WAITQOL_RELOAD_UI"] = {
    text = "This setting requires a UI reload to take effect. Reload now?",
    button1 = "Reload",
    button2 = "Later",
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

WaitQOL:RegisterModule("MinimapBar", MinimapBarModule)
