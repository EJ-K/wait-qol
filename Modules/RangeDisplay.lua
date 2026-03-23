local _, ns = ...
local WaitQOL = ns.WaitQOL
local AG = ns.AG
local LSM = ns.LSM

-- Range Warning module
local RangeDisplayModule = {
    displayName = "Range Warning",
    order = 2,
    frame = nil,
    displayText = nil,
    pulseGroup = nil,
    inCombat = false,
    tickFrame = nil,
    tickAcc = 0,
    TICK_RATE = 0.1,
}

-- Spec -> spell ID used for range checking
local SPEC_SPELL = {
    -- DK: Death Strike
    [250] = 49998, [251] = 49998, [252] = 49998,
    -- DH: Chaos Strike / Soul Cleave
    [577] = 162794, [581] = 228477,
    -- Druid: Wrath / Shred / Mangle / Wrath
    [102] = 190984, [103] = 5221, [104] = 33917, [105] = 190984,
    -- Evoker: Living Flame
    [1467] = 361469, [1468] = 361469, [1473] = 361469,
    -- Hunter: Cobra Shot / Arcane Shot / Raptor Strike
    [253] = 193455, [254] = 185358, [255] = 186270,
    -- Mage: Arcane Blast / Fireball / Frostbolt
    [62] = 30451, [63] = 133, [64] = 116,
    -- Monk: Tiger Palm
    [268] = 100780, [269] = 100780, [270] = 100780,
    -- Paladin: Judgment
    [65] = 20271, [66] = 20271, [70] = 20271,
    -- Priest: Smite / Smite / Mind Blast
    [256] = 585, [257] = 585, [258] = 8092,
    -- Rogue: Mutilate / Sinister Strike / Backstab
    [259] = 1329, [260] = 193315, [261] = 53,
    -- Shaman: Lightning Bolt / Stormstrike / Lightning Bolt
    [262] = 188196, [263] = 17364, [264] = 188196,
    -- Warlock: Shadow Bolt / Shadow Bolt / Incinerate
    [265] = 686, [266] = 686, [267] = 29722,
    -- Warrior: Mortal Strike / Bloodthirst / Shield Slam
    [71] = 12294, [72] = 23881, [73] = 23922,
}

-- Outline mode values
local OUTLINE_MODES = {
    [""] = "None",
    ["OUTLINE"] = "Outline",
    ["THICKOUTLINE"] = "Thick Outline",
    ["MONOCHROME,OUTLINE"] = "Monochrome Outline",
}

function RangeDisplayModule:GetDefaults()
    return {
        enabled = false,
        displayText = "{range} yd",
        font = nil,
        fontSize = 24,
        outlineMode = "OUTLINE",
        colorR = 1,
        colorG = 1,
        colorB = 1,
        pulse = false,
        locked = true,
        point = "CENTER",
        x = 0,
        y = -190,
        frameWidth = 200,
        frameHeight = 40,
    }
end

-- Helper: Get font path
local function GetFontPath(fontName)
    if not fontName then
        return STANDARD_TEXT_FONT
    end
    if LSM and LSM:IsValid("font", fontName) then
        return LSM:Fetch("font", fontName)
    end
    return STANDARD_TEXT_FONT
end

-- Target helpers
local function HasAttackableTarget()
    if not UnitExists("target") then return false end
    if not UnitCanAttack("player", "target") then return false end
    if UnitIsDeadOrGhost("target") then return false end
    return true
end

local function GetSpecSpell()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo(specIndex)
    return specID and SPEC_SPELL[specID]
end

-- Format the display string from the template
local function FormatRangeText(template, minRange, maxRange)
    local rangeStr
    if minRange and maxRange then
        rangeStr = minRange .. "-" .. maxRange
    elseif maxRange then
        rangeStr = "0-" .. maxRange
    elseif minRange then
        rangeStr = minRange .. "+"
    else
        rangeStr = "--"
    end

    return template:gsub("{range}", rangeStr)
        :gsub("{min}", tostring(minRange or 0))
        :gsub("{max}", tostring(maxRange or "?"))
end

-- Get range using CheckInteractDistance fallback
local function GetRangeFallback(unit)
    if not UnitExists(unit) then
        return nil, nil
    end

    -- Try to get distance using UnitDistanceSquared if possible
    local distanceSquared = UnitDistanceSquared(unit)
    if distanceSquared then
        local distance = math.floor(math.sqrt(distanceSquared))
        if distance > 0 then
            return distance, distance
        end
    end

    -- Fallback to CheckInteractDistance
    if CheckInteractDistance(unit, 1) then
        return 0, 10
    elseif CheckInteractDistance(unit, 2) then
        return 10, 11
    elseif CheckInteractDistance(unit, 3) then
        return 11, 28
    elseif CheckInteractDistance(unit, 4) then
        return 28, 50
    else
        return 50, nil
    end
end

-- Create the display frame
local function CreateDisplayFrame(savedVars)
    local frame = _G["WaitQOL_RangeWarningFrame"]

    if frame then
        frame:ClearAllPoints()
    else
        frame = CreateFrame("Frame", "WaitQOL_RangeWarningFrame", UIParent, "BackdropTemplate")
        frame:SetSize(savedVars.frameWidth or 200, savedVars.frameHeight or 40)
        frame:SetClampedToScreen(true)
        frame:Hide()

        -- Text
        local text = frame:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER")
        frame.text = text

        -- Pulse animation
        local pulseGroup = frame:CreateAnimationGroup()
        pulseGroup:SetLooping("BOUNCE")
        local pulseAnim = pulseGroup:CreateAnimation("Alpha")
        pulseAnim:SetFromAlpha(1)
        pulseAnim:SetToAlpha(0.3)
        pulseAnim:SetDuration(0.5)
        pulseAnim:SetSmoothing("IN_OUT")
        frame.pulseGroup = pulseGroup

        -- Dragging
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self)
            if not savedVars.locked then
                self:StartMoving()
            end
        end)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, _, x, y = self:GetPoint()
            savedVars.point = point
            savedVars.x = x
            savedVars.y = y
        end)
    end

    return frame
end

-- Update display appearance
function RangeDisplayModule:RefreshDisplay()
    if not self.savedVars or not self.frame then return end

    local db = self.savedVars

    if not db.enabled then
        self.frame:Hide()
        if self.frame.pulseGroup then
            self.frame.pulseGroup:Stop()
        end
        return
    end

    -- Update font
    local fontPath = GetFontPath(db.font)
    local outline = db.outlineMode or "OUTLINE"
    self.frame.text:SetFont(fontPath, db.fontSize or 24, outline)
    self.frame.text:SetTextColor(db.colorR or 1, db.colorG or 1, db.colorB or 1)

    -- Update position
    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.point or "CENTER", UIParent, db.point or "CENTER", db.x or 0, db.y or -190)
    self.frame:SetSize(db.frameWidth or 200, db.frameHeight or 40)

    -- Update lock state
    if db.locked then
        self.frame:SetBackdrop(nil)
        self.frame:EnableMouse(false)
        self.frame:SetMovable(false)
    else
        local backdrop = {
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        }
        self.frame:SetBackdrop(backdrop)
        self.frame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
        self.frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        self.frame:EnableMouse(true)
        self.frame:SetMovable(true)
        self.frame:Show()
        self.frame.text:SetText(FormatRangeText(db.displayText, 10, 15))
    end
end

-- Range tick update
local function OnRangeTick(module, elapsed)
    module.tickAcc = module.tickAcc + elapsed
    if module.tickAcc < module.TICK_RATE then return end
    module.tickAcc = 0

    local db = module.savedVars
    if not db or not db.enabled then
        if module.frame then
            module.frame:Hide()
        end
        return
    end

    if not module.inCombat or not HasAttackableTarget() then
        if db.locked and module.frame then
            module.frame:Hide()
            if module.frame.pulseGroup then
                module.frame.pulseGroup:Stop()
            end
        end
        return
    end

    local spellID = GetSpecSpell()
    if not spellID then return end

    local inRange = C_Spell.IsSpellInRange(spellID, "target")
    if inRange ~= false then
        -- In range or unable to check: hide
        if db.locked and module.frame then
            module.frame:Hide()
            if module.frame.pulseGroup then
                module.frame.pulseGroup:Stop()
            end
        end
        return
    end

    -- Out of range: show
    local minRange, maxRange = GetRangeFallback("target")

    -- Try LibRangeCheck if available
    local RangeLib = LibStub and LibStub("LibRangeCheck-3.0", true)
    if RangeLib then
        local libMin, libMax = RangeLib:GetRange("target")
        if libMin or libMax then
            minRange, maxRange = libMin, libMax
        end
    end

    module.frame.text:SetText(FormatRangeText(db.displayText, minRange, maxRange))
    module.frame.text:SetTextColor(db.colorR, db.colorG, db.colorB)

    if db.locked and module.frame then
        module.frame:Show()
        if db.pulse and not module.frame.pulseGroup:IsPlaying() then
            module.frame.pulseGroup:Play()
        elseif not db.pulse and module.frame.pulseGroup:IsPlaying() then
            module.frame.pulseGroup:Stop()
        end
    end
end

function RangeDisplayModule:CreateConfigPanel(container, savedVars)
    local scrollFrame = AG:Create("ScrollFrame")
    scrollFrame:SetLayout("Flow")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    container:AddChild(scrollFrame)

    -- Title
    local title = AG:Create("Heading")
    title:SetText("Range Warning Configuration")
    title:SetFullWidth(true)
    scrollFrame:AddChild(title)

    -- Description
    local desc = AG:Create("Label")
    desc:SetText("Displays a warning with range information when your target is out of range during combat.")
    desc:SetFullWidth(true)
    scrollFrame:AddChild(desc)

    -- Helper functions
    local UpdateControlsVisibility

    -- Enable checkbox
    local enableCheck = AG:Create("CheckBox")
    enableCheck:SetLabel("Enable Range Warning")
    enableCheck:SetValue(savedVars.enabled)
    enableCheck:SetFullWidth(true)
    enableCheck:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.enabled = value
        RangeDisplayModule:RefreshDisplay()
        UpdateControlsVisibility()
    end)
    scrollFrame:AddChild(enableCheck)

    -- Display Section
    local displaySection = AG:Create("InlineGroup")
    displaySection:SetTitle("Display")
    displaySection:SetLayout("Flow")
    displaySection:SetFullWidth(true)
    scrollFrame:AddChild(displaySection)

    -- Display text
    local textBox = AG:Create("EditBox")
    textBox:SetLabel("Display Text")
    textBox:SetText(savedVars.displayText)
    textBox:SetFullWidth(true)
    textBox:SetCallback("OnEnterPressed", function(_, _, value)
        savedVars.displayText = value
        RangeDisplayModule:RefreshDisplay()
    end)
    displaySection:AddChild(textBox)

    local textHelp = AG:Create("Label")
    textHelp:SetText("Text shown when target is out of range. Placeholders: {range} = full range (e.g. 10-15), {min} = minimum, {max} = maximum")
    textHelp:SetFullWidth(true)
    textHelp:SetColor(0.7, 0.7, 0.7)
    displaySection:AddChild(textHelp)

    -- Font (LSM)
    local fontDropdown
    if LSM then
        fontDropdown = AG:Create("LSM30_Font")
        fontDropdown:SetLabel("Font")
        fontDropdown:SetList(LSM:HashTable("font"))
        if savedVars.font then
            fontDropdown:SetValue(savedVars.font)
        end
        fontDropdown:SetFullWidth(true)
        fontDropdown:SetCallback("OnValueChanged", function(_, _, value)
            savedVars.font = value
            RangeDisplayModule:RefreshDisplay()
        end)
        displaySection:AddChild(fontDropdown)
    end

    -- Font size
    local fontSizeSlider = AG:Create("Slider")
    fontSizeSlider:SetLabel("Font Size")
    fontSizeSlider:SetSliderValues(8, 128, 1)
    fontSizeSlider:SetValue(savedVars.fontSize)
    fontSizeSlider:SetFullWidth(true)
    fontSizeSlider:SetIsPercent(false)
    fontSizeSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.fontSize = value
        RangeDisplayModule:RefreshDisplay()
    end)
    displaySection:AddChild(fontSizeSlider)

    -- Outline mode
    local outlineDropdown = AG:Create("Dropdown")
    outlineDropdown:SetLabel("Outline Mode")
    outlineDropdown:SetList(OUTLINE_MODES)
    outlineDropdown:SetValue(savedVars.outlineMode)
    outlineDropdown:SetFullWidth(true)
    outlineDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.outlineMode = value
        RangeDisplayModule:RefreshDisplay()
    end)
    displaySection:AddChild(outlineDropdown)

    -- Text color
    local colorPicker = AG:Create("ColorPicker")
    colorPicker:SetLabel("Text Color")
    colorPicker:SetColor(savedVars.colorR, savedVars.colorG, savedVars.colorB)
    colorPicker:SetFullWidth(true)
    colorPicker:SetHasAlpha(false)
    colorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b)
        savedVars.colorR = r
        savedVars.colorG = g
        savedVars.colorB = b
        RangeDisplayModule:RefreshDisplay()
    end)
    displaySection:AddChild(colorPicker)

    -- Pulse
    local pulseCheck = AG:Create("CheckBox")
    pulseCheck:SetLabel("Pulse text")
    pulseCheck:SetValue(savedVars.pulse)
    pulseCheck:SetFullWidth(true)
    pulseCheck:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.pulse = value
    end)
    displaySection:AddChild(pulseCheck)

    -- Position Section
    local positionSection = AG:Create("InlineGroup")
    positionSection:SetTitle("Position")
    positionSection:SetLayout("Flow")
    positionSection:SetFullWidth(true)
    scrollFrame:AddChild(positionSection)

    -- Lock button
    local lockBtn = AG:Create("Button")
    lockBtn:SetText(savedVars.locked and "Unlock (click to reposition)" or "Lock Position")
    lockBtn:SetFullWidth(true)
    lockBtn:SetCallback("OnClick", function(widget)
        savedVars.locked = not savedVars.locked
        widget:SetText(savedVars.locked and "Unlock (click to reposition)" or "Lock Position")
        RangeDisplayModule:RefreshDisplay()
    end)
    positionSection:AddChild(lockBtn)

    local lockHelp = AG:Create("Label")
    lockHelp:SetText("When unlocked, drag the warning frame to reposition it. It will show a preview.")
    lockHelp:SetFullWidth(true)
    lockHelp:SetColor(0.7, 0.7, 0.7)
    positionSection:AddChild(lockHelp)

    -- Update controls visibility function
    UpdateControlsVisibility = function()
        local enabled = savedVars.enabled
        textBox:SetDisabled(not enabled)
        if fontDropdown then fontDropdown:SetDisabled(not enabled) end
        fontSizeSlider:SetDisabled(not enabled)
        outlineDropdown:SetDisabled(not enabled)
        colorPicker:SetDisabled(not enabled)
        pulseCheck:SetDisabled(not enabled)
        lockBtn:SetDisabled(not enabled)
    end

    UpdateControlsVisibility()
end

function RangeDisplayModule:OnInitialize(savedVars)
    self.savedVars = savedVars
    self.frame = CreateDisplayFrame(savedVars)

    -- Create tick frame
    self.tickFrame = CreateFrame("Frame")
    self.tickFrame:SetScript("OnUpdate", function(_, elapsed)
        OnRangeTick(self, elapsed)
    end)

    -- Event frame for combat tracking
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            self.inCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            self.inCombat = false
        end
        self.tickAcc = self.TICK_RATE
    end)

    -- Initialize combat state
    self.inCombat = UnitAffectingCombat("player")

    self:RefreshDisplay()
end

function RangeDisplayModule:OnEnable()
    self:RefreshDisplay()
end

-- Register module
WaitQOL:RegisterModule("RangeDisplay", RangeDisplayModule)
