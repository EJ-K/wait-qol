local _, ns = ...
local WaitQOL = ns.WaitQOL
local AG = ns.AG

-- Combat Timer module table
local CombatTimerModule = {
    displayName = "Combat Timer",
    order = 1,
    timerFrame = nil,
    combatStartTime = nil,
    updateTicker = nil,
    configPanelOpen = false,
}

-- Outline mode values
local OUTLINE_MODES = {
    [""] = "None",
    ["OUTLINE"] = "Outline",
    ["THICKOUTLINE"] = "Thick Outline",
    ["MONOCHROME,OUTLINE"] = "Monochrome Outline",
}

-- Default settings for this module
function CombatTimerModule:GetDefaults()
    return {
        enabled = false,
        fontSize = 18,
        font = "Friz Quadrata TT",
        fontOutline = "OUTLINE",
        textAnchor = "CENTER",
        textColorR = 1,
        textColorG = 1,
        textColorB = 1,
        border = "None",
        borderThickness = 16,
        borderColor = { r = 1, g = 1, b = 1, a = 1 },
        bgColor = { r = 0, g = 0, b = 0, a = 0.8 },
        anchorPoint = "CENTER",
        anchorFrame = "UIParent",
        anchorRelativePoint = "CENTER",
        anchorOffsetX = 0,
        anchorOffsetY = 0,
    }
end

-- Helper: Format time as MM:SS
local function FormatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", mins, secs)
end

-- Helper: Get font path from LSM or fall back to default
local function GetFontPath(fontName)
    return WaitQOL.ModuleHelpers:GetLSMFont(fontName)
end

-- Helper: Get border path from LSM or fall back
local function GetBorderPath(borderName)
    return WaitQOL.ModuleHelpers:GetLSMBorder(borderName)
end

-- Update existing timer frame or create new one
local function CreateTimerFrame(savedVars)
    local frame = _G["WaitQOL_CombatTimerFrame"]

    if frame then
        frame:ClearAllPoints()
    else
        frame = CreateFrame("Frame", "WaitQOL_CombatTimerFrame", UIParent, "BackdropTemplate")
        frame:SetSize(60, 26)
        frame:SetFrameStrata("MEDIUM")
        frame:SetClampedToScreen(true)
    end

    -- Set anchor position
    local anchorFrame = _G[savedVars.anchorFrame] or UIParent
    frame:SetPoint(
        savedVars.anchorPoint or "CENTER",
        anchorFrame,
        savedVars.anchorRelativePoint or "CENTER",
        savedVars.anchorOffsetX or 0,
        savedVars.anchorOffsetY or 0
    )

    -- Backdrop with optional border
    local borderPath = GetBorderPath(savedVars.border)
    local backdrop = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
    }

    if borderPath then
        backdrop.edgeFile = borderPath
        backdrop.edgeSize = savedVars.borderThickness or 16
        local inset = math.max(4, (savedVars.borderThickness or 16) / 4)
        backdrop.insets = { left = inset, right = inset, top = inset, bottom = inset }
    end

    frame:SetBackdrop(backdrop)

    local bgColor = savedVars.bgColor
    frame:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)

    if borderPath then
        local borderColor = savedVars.borderColor or { r = 1, g = 1, b = 1, a = 1 }
        frame:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a)
    end

    -- Create or update text display
    local text = frame.text
    if not text then
        text = frame:CreateFontString(nil, "OVERLAY")
        frame.text = text
    else
        text:ClearAllPoints()
    end

    local fontPath = GetFontPath(savedVars.font)
    text:SetFont(fontPath, savedVars.fontSize, savedVars.fontOutline or "OUTLINE")
    text:SetText("00:00")

    -- Position text based on textAnchor setting
    local anchor = savedVars.textAnchor or "CENTER"
    text:SetPoint(anchor, frame, anchor, 0, 0)

    text:SetTextColor(
        savedVars.textColorR or 1,
        savedVars.textColorG or 1,
        savedVars.textColorB or 1,
        1
    )

    return frame
end

-- Update timer display
local function UpdateTimerDisplay(module)
    if not module.combatStartTime or not module.timerFrame or not module.timerFrame.text then
        return
    end

    local elapsed = GetTime() - module.combatStartTime
    module.timerFrame.text:SetText(FormatTime(math.floor(elapsed)))
end

-- Helper: Ensure timer frame exists (lazy initialization)
local function EnsureTimerFrame(savedVars)
    if not CombatTimerModule.timerFrame then
        CombatTimerModule.timerFrame = CreateTimerFrame(savedVars)
    end
    return CombatTimerModule.timerFrame
end

-- Create the config panel for this module (AceGUI version)
function CombatTimerModule:CreateConfigPanel(container, savedVars)
    CombatTimerModule.configPanelOpen = true

    -- Helper to update timer visibility based on state
    local function UpdateTimerVisibility()
        if not CombatTimerModule.timerFrame then return end

        local shouldShow = (CombatTimerModule.combatStartTime and savedVars.enabled) or
                          (CombatTimerModule.configPanelOpen and savedVars.enabled)

        if shouldShow then
            CombatTimerModule.timerFrame:Show()
        else
            CombatTimerModule.timerFrame:Hide()
        end
    end

    -- Helper to recreate timer frame
    local function RecreateTimerFrame()
        if not InCombatLockdown() then
            CombatTimerModule.timerFrame = CreateTimerFrame(savedVars)
            UpdateTimerVisibility()
        end
    end

    -- Ensure timer frame exists when opening config panel
    EnsureTimerFrame(savedVars)

    -- Create scroll frame for content
    local scrollFrame = AG:Create("ScrollFrame")
    scrollFrame:SetLayout("Flow")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    container:AddChild(scrollFrame)

    -- Set up callback to detect when config panel is closed
    container:SetCallback("OnRelease", function()
        CombatTimerModule.configPanelOpen = false
        if not CombatTimerModule.combatStartTime and CombatTimerModule.timerFrame then
            CombatTimerModule.timerFrame:Hide()
        end
    end)

    -- Module title
    local title = AG:Create("Heading")
    title:SetText("Combat Timer Configuration")
    title:SetFullWidth(true)
    scrollFrame:AddChild(title)

    -- Description
    local desc = AG:Create("Label")
    desc:SetText("Display a stopwatch showing how long you've been in combat.")
    desc:SetFullWidth(true)
    scrollFrame:AddChild(desc)

    -- Forward declare UpdateControlsVisibility
    local UpdateControlsVisibility

    -- Enable checkbox
    local enableCheck = AG:Create("CheckBox")
    enableCheck:SetLabel("Enable combat timer")
    enableCheck:SetValue(savedVars.enabled)
    enableCheck:SetFullWidth(true)
    enableCheck:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.enabled = value

        -- If enabling and in combat, start the timer
        if value and InCombatLockdown() and not CombatTimerModule.combatStartTime then
            CombatTimerModule:OnEnterCombat()
        end

        -- If disabling and timer is running, stop it
        if not value and CombatTimerModule.updateTicker then
            CombatTimerModule.updateTicker:Cancel()
            CombatTimerModule.updateTicker = nil
            if CombatTimerModule.timerFrame then
                CombatTimerModule.timerFrame:Hide()
            end
        end

        UpdateTimerVisibility()
        UpdateControlsVisibility()
    end)
    scrollFrame:AddChild(enableCheck)

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
        BOTTOMRIGHT = "Bottom Right"
    }

    -- Helper: Get list of available anchor frames
    local function GetAvailableFrames()
        local frames = {
            ["UIParent"] = "UIParent (Screen)",
        }

        -- Blizzard default UI frames
        local defaultFrames = {
            "PlayerFrame",
            "TargetFrame",
            "FocusFrame",
            "PetFrame",
            "PartyMemberFrame1",
            "Boss1TargetFrame",
            "MinimapCluster",
            "ObjectiveTrackerFrame",
            "ChatFrame1",
        }

        for _, frameName in ipairs(defaultFrames) do
            if _G[frameName] then
                frames[frameName] = frameName
            end
        end

        -- ElvUI (Orange)
        if _G.ElvUI then
            frames["ElvUI_Player"] = "|cFFFF8800ElvUI|r: Player"
            frames["ElvUI_Target"] = "|cFFFF8800ElvUI|r: Target"
            frames["ElvUI_Focus"] = "|cFFFF8800ElvUI|r: Focus"
        end

        -- UnhaltedUnitFrames (Light Purple)
        if _G.UnhaltedUnitFrames then
            local uufFrames = {
                { key = "UUF_Player", name = "Player" },
                { key = "UUF_Target", name = "Target" },
                { key = "UUF_TargetTarget", name = "Target Target" },
                { key = "UUF_Focus", name = "Focus" },
                { key = "UUF_FocusTarget", name = "Focus Target" },
                { key = "UUF_Pet", name = "Pet" },
            }
            for _, frame in ipairs(uufFrames) do
                if _G[frame.key] then
                    frames[frame.key] = "|cFF8080FFUUF|r: " .. frame.name
                end
            end
            -- Boss frames
            for i = 1, 5 do
                local bossFrame = "UUF_Boss" .. i
                if _G[bossFrame] then
                    frames[bossFrame] = "|cFF8080FFUUF|r: Boss " .. i
                end
            end
        end

        -- BetterCooldownManager (Blue)
        if _G.BCDMG then
            local bcdmFrames = {
                { key = "BCDM_PowerBar", name = "Power Bar" },
                { key = "BCDM_SecondaryPowerBar", name = "Secondary Power Bar" },
                { key = "BCDM_CastBar", name = "Cast Bar" },
                { key = "BCDM_TrinketBar", name = "Trinket Bar" },
                { key = "BCDM_CustomCooldownViewer", name = "Custom Cooldown Viewer" },
                { key = "BCDM_AdditionalCustomCooldownViewer", name = "Additional Custom Viewer" },
                { key = "BCDM_CustomItemBar", name = "Custom Item Bar" },
                { key = "BCDM_CustomItemSpellBar", name = "Custom Item Spell Bar" },
            }
            for _, frame in ipairs(bcdmFrames) do
                if _G[frame.key] then
                    frames[frame.key] = "|cFF0088FFBCDM|r: " .. frame.name
                end
            end
        end

        -- Grid2 (Green)
        if _G.Grid2 then
            frames["Grid2LayoutFrame"] = "|cFF00FF88Grid2|r"
        end

        -- VuhDo (Cyan)
        if _G.VuhDo then
            frames["Vd1"] = "|cFF00FFFFVuhDo|r: Panel 1"
        end

        -- Bartender4 (Red)
        if _G.Bartender4 then
            for i = 1, 10 do
                local bar = _G["BT4Bar" .. i]
                if bar then
                    frames["BT4Bar" .. i] = "|cFFFF0000Bartender|r: Bar " .. i
                end
            end
        end

        -- Dominos (Yellow)
        if _G.Dominos then
            for i = 1, 14 do
                local bar = _G["DominosActionBar" .. i]
                if bar then
                    frames["DominosActionBar" .. i] = "|cFFFFDD00Dominos|r: Bar " .. i
                end
            end
        end

        return frames
    end

    -- Anchor Point dropdown
    local anchorPointDropdown = AG:Create("Dropdown")
    anchorPointDropdown:SetLabel("Anchor Point")
    anchorPointDropdown:SetList(anchorPointsList)
    anchorPointDropdown:SetValue(savedVars.anchorPoint or "CENTER")
    anchorPointDropdown:SetRelativeWidth(0.33)
    anchorPointDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorPoint = value
        RecreateTimerFrame()
    end)
    positionSection:AddChild(anchorPointDropdown)

    -- Target Frame dropdown
    local targetFrameDropdown = AG:Create("Dropdown")
    targetFrameDropdown:SetLabel("Target Frame")
    targetFrameDropdown:SetList(GetAvailableFrames())
    targetFrameDropdown:SetValue(savedVars.anchorFrame or "UIParent")
    targetFrameDropdown:SetRelativeWidth(0.33)
    targetFrameDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorFrame = value
        RecreateTimerFrame()
    end)
    positionSection:AddChild(targetFrameDropdown)

    -- Target Anchor dropdown
    local targetAnchorDropdown = AG:Create("Dropdown")
    targetAnchorDropdown:SetLabel("Target Anchor")
    targetAnchorDropdown:SetList(anchorPointsList)
    targetAnchorDropdown:SetValue(savedVars.anchorRelativePoint or "CENTER")
    targetAnchorDropdown:SetRelativeWidth(0.33)
    targetAnchorDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorRelativePoint = value
        RecreateTimerFrame()
    end)
    positionSection:AddChild(targetAnchorDropdown)

    -- X Offset slider
    local xOffsetSlider = AG:Create("Slider")
    xOffsetSlider:SetLabel("X Offset")
    xOffsetSlider:SetSliderValues(-200, 200, 1)
    xOffsetSlider:SetValue(savedVars.anchorOffsetX or 0)
    xOffsetSlider:SetRelativeWidth(0.5)
    xOffsetSlider:SetIsPercent(false)
    xOffsetSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorOffsetX = value
        RecreateTimerFrame()
    end)
    positionSection:AddChild(xOffsetSlider)

    -- Y Offset slider
    local yOffsetSlider = AG:Create("Slider")
    yOffsetSlider:SetLabel("Y Offset")
    yOffsetSlider:SetSliderValues(-200, 200, 1)
    yOffsetSlider:SetValue(savedVars.anchorOffsetY or 0)
    yOffsetSlider:SetRelativeWidth(0.5)
    yOffsetSlider:SetIsPercent(false)
    yOffsetSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorOffsetY = value
        RecreateTimerFrame()
    end)
    positionSection:AddChild(yOffsetSlider)

    -- ==== APPEARANCE SECTION ====
    local appearanceSection = AG:Create("InlineGroup")
    appearanceSection:SetTitle("Appearance")
    appearanceSection:SetLayout("Flow")
    appearanceSection:SetFullWidth(true)
    scrollFrame:AddChild(appearanceSection)

    -- Font size slider
    local sizeSlider = AG:Create("Slider")
    sizeSlider:SetLabel("Font Size")
    sizeSlider:SetSliderValues(8, 96, 1)
    sizeSlider:SetValue(savedVars.fontSize)
    sizeSlider:SetRelativeWidth(0.5)
    sizeSlider:SetIsPercent(false)
    sizeSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.fontSize = value
        if CombatTimerModule.timerFrame and CombatTimerModule.timerFrame.text then
            local fontPath = GetFontPath(savedVars.font)
            CombatTimerModule.timerFrame.text:SetFont(fontPath, value, savedVars.fontOutline or "OUTLINE")
        end
    end)
    appearanceSection:AddChild(sizeSlider)

    -- Text anchor dropdown
    local textAnchorDropdown = AG:Create("Dropdown")
    textAnchorDropdown:SetLabel("Text Anchor")
    textAnchorDropdown:SetRelativeWidth(0.5)
    textAnchorDropdown:SetList(anchorPointsList)
    textAnchorDropdown:SetValue(savedVars.textAnchor or "CENTER")
    textAnchorDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.textAnchor = value
        RecreateTimerFrame()
    end)
    appearanceSection:AddChild(textAnchorDropdown)

    -- Outline dropdown
    local outlineDropdown = AG:Create("Dropdown")
    outlineDropdown:SetLabel("Outline Mode")
    outlineDropdown:SetList(OUTLINE_MODES)
    outlineDropdown:SetValue(savedVars.fontOutline or "OUTLINE")
    outlineDropdown:SetRelativeWidth(0.5)
    outlineDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.fontOutline = value
        if CombatTimerModule.timerFrame and CombatTimerModule.timerFrame.text then
            local fontPath = GetFontPath(savedVars.font)
            CombatTimerModule.timerFrame.text:SetFont(fontPath, savedVars.fontSize, value)
        end
    end)
    appearanceSection:AddChild(outlineDropdown)

    -- Text color picker
    local textColorPicker = AG:Create("ColorPicker")
    textColorPicker:SetLabel("Text Color")
    textColorPicker:SetHasAlpha(false)
    textColorPicker:SetColor(
        savedVars.textColorR or 1,
        savedVars.textColorG or 1,
        savedVars.textColorB or 1
    )
    textColorPicker:SetRelativeWidth(0.5)
    textColorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b)
        savedVars.textColorR = r
        savedVars.textColorG = g
        savedVars.textColorB = b
        if CombatTimerModule.timerFrame and CombatTimerModule.timerFrame.text then
            CombatTimerModule.timerFrame.text:SetTextColor(r, g, b, 1)
        end
    end)
    appearanceSection:AddChild(textColorPicker)

    -- Background color picker
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
        savedVars.bgColor.r = r
        savedVars.bgColor.g = g
        savedVars.bgColor.b = b
        savedVars.bgColor.a = a
        if CombatTimerModule.timerFrame then
            CombatTimerModule.timerFrame:SetBackdropColor(r, g, b, a)
        end
    end)
    appearanceSection:AddChild(bgColorPicker)

    -- Function to update visibility of all controls based on enabled state
    UpdateControlsVisibility = function()
        local enabled = savedVars.enabled

        -- Position section widgets
        anchorPointDropdown:SetDisabled(not enabled)
        targetFrameDropdown:SetDisabled(not enabled)
        targetAnchorDropdown:SetDisabled(not enabled)
        xOffsetSlider:SetDisabled(not enabled)
        yOffsetSlider:SetDisabled(not enabled)

        -- Appearance section widgets
        sizeSlider:SetDisabled(not enabled)
        textAnchorDropdown:SetDisabled(not enabled)
        outlineDropdown:SetDisabled(not enabled)
        textColorPicker:SetDisabled(not enabled)
        bgColorPicker:SetDisabled(not enabled)
    end

    -- Set initial visibility
    UpdateControlsVisibility()

    -- Show timer preview if enabled
    UpdateTimerVisibility()
end

-- Initialize module functionality
function CombatTimerModule:OnInitialize(savedVars)
    CombatTimerModule.savedVars = savedVars

    -- Don't create timer frame yet - defer until it's needed
    -- This ensures other addons have loaded their frames first

    -- Create event frame
    CombatTimerModule.frame = CreateFrame("Frame")
    CombatTimerModule.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    CombatTimerModule.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    CombatTimerModule.frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Event handler
    CombatTimerModule.frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            CombatTimerModule:OnEnterCombat()
        elseif event == "PLAYER_REGEN_ENABLED" then
            CombatTimerModule:OnLeaveCombat()
        elseif event == "PLAYER_ENTERING_WORLD" then
            CombatTimerModule:ResetTimer()
        end
    end)

    -- Check if already in combat on load and enabled
    if savedVars.enabled and InCombatLockdown() then
        CombatTimerModule:OnEnterCombat()
    end
end

-- Called when module is enabled
function CombatTimerModule:OnEnable()
    -- If in combat when enabled, start the timer
    if InCombatLockdown() then
        self:OnEnterCombat()
    end
end

-- Handle entering combat
function CombatTimerModule:OnEnterCombat()
    if not CombatTimerModule.savedVars.enabled then
        return
    end

    -- Ensure timer frame exists (lazy initialization)
    local frame = EnsureTimerFrame(CombatTimerModule.savedVars)

    -- Reset display for new combat session
    if frame and frame.text then
        frame.text:SetText("00:00")
    end

    CombatTimerModule.combatStartTime = GetTime()

    -- Start update ticker
    if not CombatTimerModule.updateTicker then
        CombatTimerModule.updateTicker = C_Timer.NewTicker(0.1, function()
            UpdateTimerDisplay(CombatTimerModule)
        end)
    end

    if frame then
        frame:Show()
    end
end

-- Handle leaving combat
function CombatTimerModule:OnLeaveCombat()
    CombatTimerModule.combatStartTime = nil

    -- Stop update ticker
    if CombatTimerModule.updateTicker then
        CombatTimerModule.updateTicker:Cancel()
        CombatTimerModule.updateTicker = nil
    end

    -- Hide the frame if not showing preview in config panel
    if CombatTimerModule.timerFrame then
        if not (CombatTimerModule.configPanelOpen and CombatTimerModule.savedVars.enabled) then
            CombatTimerModule.timerFrame:Hide()
        end
    end
end

-- Reset timer (called on zone change)
function CombatTimerModule:ResetTimer()
    if CombatTimerModule.updateTicker then
        CombatTimerModule.updateTicker:Cancel()
        CombatTimerModule.updateTicker = nil
    end

    CombatTimerModule.combatStartTime = nil

    if CombatTimerModule.timerFrame and CombatTimerModule.timerFrame.text then
        CombatTimerModule.timerFrame.text:SetText("00:00")
        if not (CombatTimerModule.configPanelOpen and CombatTimerModule.savedVars.enabled) then
            CombatTimerModule.timerFrame:Hide()
        end
    end
end

-- Register the module with the core
WaitQOL:RegisterModule("CombatTimer", CombatTimerModule)
