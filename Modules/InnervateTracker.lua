local _, ns = ...
local WaitQOL = ns.WaitQOL
local AG = ns.AG
local LSM = ns.LSM
local LibCustomGlow = LibStub("LibCustomGlow-1.0")

local InnervateModule = {
    displayName = "Innervate Tracker",
    order = 3,
    iconFrame = nil,
    isActive = false,
    currentSpells = nil,
    pollFrame = nil,
    pollAccum = 0,
    configPanelOpen = false,
}

local POLL_RATE = 0.1
local INNERVATE_ICON = 136048
local INNERVATE_DURATION = 8
local GLOW_KEY = "WaitQOL_Innervate"

-- 3 mana-costing spells per spec ID for zero-cost detection.
-- When Innervate is active, all spells cost 0 mana. Checking 3 avoids
-- false positives from single-spell procs like Clearcasting.
local SPEC_SPELLS = {
    -- Healers
    [105]  = { 48438, 8936, 774 },       -- Resto Druid: Wild Growth, Regrowth, Rejuvenation
    [264]  = { 77472, 1064, 61295 },      -- Resto Shaman: Healing Wave, Chain Heal, Riptide
    [65]   = { 19750, 82326, 20473 },     -- Holy Paladin: Flash of Light, Holy Light, Holy Shock
    [257]  = { 2061, 33076, 139 },        -- Holy Priest: Flash Heal, Prayer of Mending, Renew
    [256]  = { 17, 2061, 47540 },         -- Disc Priest: PW:Shield, Flash Heal, Penance
    [270]  = { 116670, 124682, 115151 },  -- Mistweaver: Vivify, Enveloping Mist, Renewing Mist
    [1468] = { 366155, 361469, 382614 },  -- Pres Evoker: Reversion, Living Flame, Dream Breath
    [1473] = { 361469, 409311, 360827 },  -- Aug Evoker: Living Flame, Prescience, Blistering Scales
    -- Caster DPS
    [102]  = { 190984, 78674, 194153 },   -- Balance Druid: Wrath, Starsurge, Starfire
    [62]   = { 30451, 44425, 235450 },    -- Arcane Mage: Arcane Blast, Arcane Barrage, Arcane Missiles
    [63]   = { 133, 108853, 11366 },      -- Fire Mage: Fireball, Fire Blast, Pyroblast
    [64]   = { 116, 30455, 44614 },       -- Frost Mage: Frostbolt, Ice Lance, Flurry
    [262]  = { 188196, 51505, 8042 },     -- Elemental Shaman: Lightning Bolt, Lava Burst, Earth Shock
    [258]  = { 8092, 34914, 589 },        -- Shadow Priest: Mind Blast, VT, SW:Pain
    [265]  = { 686, 172, 980 },           -- Affliction Lock: Shadow Bolt, Corruption, Agony
    [266]  = { 686, 104316, 603 },        -- Demo Lock: Shadow Bolt, Call Dreadstalkers, Doom
    [267]  = { 29722, 17962, 116858 },    -- Destro Lock: Incinerate, Conflagrate, Chaos Bolt
    [1467] = { 361469, 357208, 396197 },  -- Devastation Evoker: Living Flame, Fire Breath, Disintegrate
}

local GLOW_TYPES = {
    Pixel = "Pixel",
    Autocast = "Autocast",
    Proc = "Proc",
    Button = "Button",
}

local SOUND_CHANNELS = {
    ["Master"] = "Master",
    ["SFX"] = "Sound Effects",
    ["Music"] = "Music",
    ["Ambience"] = "Ambience",
    ["Dialog"] = "Dialog",
}

function InnervateModule:GetDefaults()
    return {
        enabled = false,
        iconSize = 48,
        borderColor = { r = 1, g = 1, b = 1, a = 1 },
        borderThickness = 1,
        glowEnabled = true,
        glowType = "Pixel",
        glow = {
            Pixel = {
                color = { 0.4, 0, 0.8, 1 },
                lines = 5,
                frequency = 0.25,
                length = 2,
                thickness = 1,
                xOffset = -1,
                yOffset = -1,
                border = false,
            },
            Autocast = {
                color = { 0.4, 0, 0.8, 1 },
                particles = 10,
                frequency = 0.25,
                scale = 1,
                xOffset = -1,
                yOffset = -1,
            },
            Proc = {
                color = { 0, 0.39, 1, 1 },
                inset = 0,
            },
            Button = {
                color = { 0.4, 0, 0.8, 1 },
                frequency = 0.125,
            },
        },
        showSwipe = true,
        showCountdownText = true,
        countdownTextSize = 18,
        reverseSwipe = false,
        startSound = "None",
        endSound = "None",
        soundChannel = "Master",
        anchorPoint = "CENTER",
        anchorFrame = "UIParent",
        anchorRelativePoint = "CENTER",
        anchorOffsetX = 0,
        anchorOffsetY = 0,
    }
end

-- Check if all 3 tracked spells currently cost 0 mana
local function AllSpellsFree(spells)
    if not spells then return false end
    for i = 1, 3 do
        local costs = C_Spell.GetSpellPowerCost(spells[i])
        local cost = costs and costs[1] and costs[1].cost
        if cost == nil or cost ~= 0 then
            return false
        end
    end
    return true
end

local function GetCurrentSpecSpells()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo(specIndex)
    return specID and SPEC_SPELLS[specID]
end

local function PlayLSMSound(soundName, channel)
    if not soundName or soundName == "None" then return end
    channel = channel or "Master"
    -- Try the hash table directly first (most reliable)
    local hashTable = LSM:HashTable("sound")
    local path = hashTable and hashTable[soundName]
    if not path then
        path = LSM:Fetch("sound", soundName, true)
    end
    if not path then return end
    if type(path) == "number" then
        PlaySound(path, channel)
    else
        PlaySoundFile(path, channel)
    end
end

local function PlayModuleSound(savedVars, soundKey)
    PlayLSMSound(savedVars[soundKey], savedVars.soundChannel)
end

local function StartGlow(frame, savedVars)
    if not savedVars.glowEnabled then return end

    local glowType = savedVars.glowType or "Pixel"
    local settings = savedVars.glow[glowType]
    if not settings then return end

    -- Stop any existing glow of a different type
    if frame._wqolGlowType and frame._wqolGlowType ~= glowType then
        InnervateModule:StopGlow(frame)
    end

    if glowType == "Pixel" then
        LibCustomGlow.PixelGlow_Start(frame, settings.color, settings.lines,
            settings.frequency, settings.length, settings.thickness,
            settings.xOffset, settings.yOffset, settings.border, GLOW_KEY, 1)
    elseif glowType == "Autocast" then
        LibCustomGlow.AutoCastGlow_Start(frame, settings.color, settings.particles,
            settings.frequency, settings.scale, settings.xOffset, settings.yOffset,
            GLOW_KEY, 1)
    elseif glowType == "Proc" then
        LibCustomGlow.ProcGlow_Start(frame, {
            key = GLOW_KEY,
            frameLevel = 1,
            color = settings.color,
            xOffset = settings.inset or 0,
            yOffset = settings.inset or 0,
        })
    elseif glowType == "Button" then
        LibCustomGlow.ButtonGlow_Start(frame, settings.color, settings.frequency, 1)
    end

    frame._wqolGlowType = glowType
end

function InnervateModule:StopGlow(frame)
    if not frame or not frame._wqolGlowType then return end

    if frame._wqolGlowType == "Pixel" then
        LibCustomGlow.PixelGlow_Stop(frame, GLOW_KEY)
    elseif frame._wqolGlowType == "Autocast" then
        LibCustomGlow.AutoCastGlow_Stop(frame, GLOW_KEY)
    elseif frame._wqolGlowType == "Proc" then
        LibCustomGlow.ProcGlow_Stop(frame, GLOW_KEY)
    elseif frame._wqolGlowType == "Button" then
        LibCustomGlow.ButtonGlow_Stop(frame)
    end

    frame._wqolGlowType = nil
end

-- Update the countdown font object size
local function UpdateCountdownFont(size)
    local fontObj = _G["WaitQOL_InnervateCountdownFont"]
    if not fontObj then
        fontObj = CreateFont("WaitQOL_InnervateCountdownFont")
    end
    fontObj:SetFont("Fonts\\FRIZQT__.TTF", size or 18, "OUTLINE")
end

-- Create or update the icon frame
local function CreateIconFrame(savedVars)
    local frame = _G["WaitQOL_InnervateFrame"]

    if frame then
        frame:ClearAllPoints()
        InnervateModule:StopGlow(frame)
    else
        frame = CreateFrame("Frame", "WaitQOL_InnervateFrame", UIParent, "BackdropTemplate")
        frame:SetFrameStrata("HIGH")
        frame:SetClampedToScreen(true)

        frame.icon = frame:CreateTexture(nil, "ARTWORK")
        frame.icon:SetTexture(INNERVATE_ICON)

        frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        frame.cooldown:SetAllPoints()
    end

    local size = savedVars.iconSize or 48
    frame:SetSize(size, size)

    -- Position
    local anchorFrame = _G[savedVars.anchorFrame] or UIParent
    frame:SetPoint(
        savedVars.anchorPoint or "CENTER",
        anchorFrame,
        savedVars.anchorRelativePoint or "CENTER",
        savedVars.anchorOffsetX or 0,
        savedVars.anchorOffsetY or 0
    )

    -- Icon texture
    frame.icon:SetAllPoints()

    -- Cooldown settings
    frame.cooldown:SetDrawSwipe(savedVars.showSwipe)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetHideCountdownNumbers(not savedVars.showCountdownText)
    frame.cooldown:SetReverse(savedVars.reverseSwipe)
    UpdateCountdownFont(savedVars.countdownTextSize)
    frame.cooldown:SetCountdownFont("WaitQOL_InnervateCountdownFont")

    -- Border via backdrop
    local borderThickness = savedVars.borderThickness or 2
    if borderThickness > 0 then
        frame:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = borderThickness,
        })
        local bc = savedVars.borderColor
        frame:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a)
    else
        frame:SetBackdrop(nil)
    end

    return frame
end

local function EnsureIconFrame(savedVars)
    if not InnervateModule.iconFrame then
        InnervateModule.iconFrame = CreateIconFrame(savedVars)
    end
    return InnervateModule.iconFrame
end

local function ShowIcon(savedVars)
    local frame = EnsureIconFrame(savedVars)
    frame:Show()
    StartGlow(frame, savedVars)

    if frame.cooldown then
        frame.cooldown:SetCooldown(GetTime(), INNERVATE_DURATION)
    end
end

local function HideIcon()
    if InnervateModule.iconFrame then
        InnervateModule:StopGlow(InnervateModule.iconFrame)

        if InnervateModule.iconFrame.cooldown then
            InnervateModule.iconFrame.cooldown:Clear()
        end

        InnervateModule.iconFrame:Hide()
    end
end

function InnervateModule:StartPolling()
    self.currentSpells = GetCurrentSpecSpells()
    if not self.currentSpells then return end

    self.isActive = false
    self.pollAccum = 0

    if not self.pollFrame then
        self.pollFrame = CreateFrame("Frame")
    end

    self.pollFrame:SetScript("OnUpdate", function(_, elapsed)
        self.pollAccum = self.pollAccum + elapsed
        if self.pollAccum < POLL_RATE then return end
        self.pollAccum = 0

        local isFree = AllSpellsFree(self.currentSpells)

        if isFree and not self.isActive then
            self.isActive = true
            ShowIcon(self.savedVars)
            PlayModuleSound(self.savedVars, "startSound")
        elseif not isFree and self.isActive then
            self.isActive = false
            HideIcon()
            PlayModuleSound(self.savedVars, "endSound")
        end

    end)
end

function InnervateModule:StopPolling()
    if self.pollFrame then
        self.pollFrame:SetScript("OnUpdate", nil)
    end
    if self.isActive then
        self.isActive = false
        HideIcon()
    end
end

function InnervateModule:OnInitialize(savedVars)
    self.savedVars = savedVars

    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        self.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

        self.eventFrame:SetScript("OnEvent", function(_, event)
            if not InnervateModule.savedVars.enabled then return end

            if event == "PLAYER_REGEN_DISABLED" then
                InnervateModule:StartPolling()
            elseif event == "PLAYER_REGEN_ENABLED" then
                InnervateModule:StopPolling()
            elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
                InnervateModule.currentSpells = GetCurrentSpecSpells()
            elseif event == "PLAYER_ENTERING_WORLD" then
                InnervateModule:StopPolling()
            end
        end)
    end

    if savedVars.enabled and InCombatLockdown() then
        self:StartPolling()
    end
end

function InnervateModule:OnEnable()
    if InCombatLockdown() then
        self:StartPolling()
    end
end

-- Helper to convert between color table formats
-- Saved: { r, g, b, a } (array) for LibCustomGlow
-- AceGUI ColorPicker uses (r, g, b, a) as separate args
local function ColorToRGBA(color)
    return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
end

-- Config panel
function InnervateModule:CreateConfigPanel(container, savedVars)
    self.configPanelOpen = true

    local function UpdatePreviewVisibility()
        if not InnervateModule.iconFrame then return end
        local frame = InnervateModule.iconFrame
        local shouldShow = savedVars.enabled and (InnervateModule.isActive or InnervateModule.configPanelOpen)
        if shouldShow then
            frame:Show()
            StartGlow(frame, savedVars)
            if frame.cooldown then
                frame.cooldown:SetDrawSwipe(savedVars.showSwipe)
                frame.cooldown:SetHideCountdownNumbers(not savedVars.showCountdownText)
                frame.cooldown:SetReverse(savedVars.reverseSwipe)
                UpdateCountdownFont(savedVars.countdownTextSize)
                frame.cooldown:SetCountdownFont("WaitQOL_InnervateCountdownFont")
                if not InnervateModule.isActive then
                    frame.cooldown:SetCooldown(GetTime(), INNERVATE_DURATION)
                end
            end
        else
            InnervateModule:StopGlow(frame)
            frame:Hide()
        end
    end

    local function RecreateFrame()
        if not InCombatLockdown() then
            InnervateModule.iconFrame = CreateIconFrame(savedVars)
            UpdatePreviewVisibility()
        end
    end

    EnsureIconFrame(savedVars)

    local scrollFrame = AG:Create("ScrollFrame")
    scrollFrame:SetLayout("Flow")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    container:AddChild(scrollFrame)

    container:SetCallback("OnRelease", function()
        InnervateModule.configPanelOpen = false
        if not InnervateModule.isActive and InnervateModule.iconFrame then
            InnervateModule:StopGlow(InnervateModule.iconFrame)
            InnervateModule.iconFrame:Hide()
        end
    end)

    -- Title
    local title = AG:Create("Heading")
    title:SetText("Innervate Tracker Configuration")
    title:SetFullWidth(true)
    scrollFrame:AddChild(title)

    local desc = AG:Create("Label")
    desc:SetText("Detects Innervate by polling spell mana costs. When all tracked spells cost 0 mana, Innervate is active.")
    desc:SetFullWidth(true)
    scrollFrame:AddChild(desc)

    local specDesc = AG:Create("Label")
    local spells = GetCurrentSpecSpells()
    if spells then
        specDesc:SetText("|cFF00FF00Your current spec is supported.|r")
    else
        specDesc:SetText("|cFFFF4444Your current spec is not a mana user. The tracker will not function.|r")
    end
    specDesc:SetFullWidth(true)
    scrollFrame:AddChild(specDesc)

    -- Forward declare
    local UpdateControlsVisibility
    local glowSettingsWidgets = {}

    -- Enable
    local enableCheck = AG:Create("CheckBox")
    enableCheck:SetLabel("Enable Innervate Tracker")
    enableCheck:SetValue(savedVars.enabled)
    enableCheck:SetFullWidth(true)
    enableCheck:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.enabled = value
        if value and InCombatLockdown() then
            InnervateModule:StartPolling()
        elseif not value then
            InnervateModule:StopPolling()
        end
        UpdatePreviewVisibility()
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
        TOPLEFT = "Top Left", TOP = "Top", TOPRIGHT = "Top Right",
        LEFT = "Left", CENTER = "Center", RIGHT = "Right",
        BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom Right",
    }

    local function GetAvailableFrames()
        local frames = { ["UIParent"] = "UIParent (Screen)" }
        local defaultFrames = {
            "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame",
            "PartyMemberFrame1", "Boss1TargetFrame", "MinimapCluster",
            "ObjectiveTrackerFrame", "ChatFrame1",
        }
        for _, frameName in ipairs(defaultFrames) do
            if _G[frameName] then
                frames[frameName] = frameName
            end
        end
        if _G.ElvUI then
            frames["ElvUI_Player"] = "|cFFFF8800ElvUI|r: Player"
            frames["ElvUI_Target"] = "|cFFFF8800ElvUI|r: Target"
            frames["ElvUI_Focus"] = "|cFFFF8800ElvUI|r: Focus"
        end
        if _G.UnhaltedUnitFrames then
            local uufFrames = {
                { key = "UUF_Player", name = "Player" },
                { key = "UUF_Target", name = "Target" },
                { key = "UUF_TargetTarget", name = "Target Target" },
                { key = "UUF_Focus", name = "Focus" },
                { key = "UUF_FocusTarget", name = "Focus Target" },
                { key = "UUF_Pet", name = "Pet" },
            }
            for _, f in ipairs(uufFrames) do
                if _G[f.key] then
                    frames[f.key] = "|cFF8080FFUUF|r: " .. f.name
                end
            end
            for i = 1, 5 do
                local bossFrame = "UUF_Boss" .. i
                if _G[bossFrame] then
                    frames[bossFrame] = "|cFF8080FFUUF|r: Boss " .. i
                end
            end
        end
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
            for _, f in ipairs(bcdmFrames) do
                if _G[f.key] then
                    frames[f.key] = "|cFF0088FFBCDM|r: " .. f.name
                end
            end
        end
        if _G.Grid2 then
            frames["Grid2LayoutFrame"] = "|cFF00FF88Grid2|r"
        end
        if _G.VuhDo then
            frames["Vd1"] = "|cFF00FFFFVuhDo|r: Panel 1"
        end
        if _G.Bartender4 then
            for i = 1, 10 do
                local bar = _G["BT4Bar" .. i]
                if bar then
                    frames["BT4Bar" .. i] = "|cFFFF0000Bartender|r: Bar " .. i
                end
            end
        end
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

    local anchorPointDropdown = AG:Create("Dropdown")
    anchorPointDropdown:SetLabel("Anchor Point")
    anchorPointDropdown:SetList(anchorPointsList)
    anchorPointDropdown:SetValue(savedVars.anchorPoint or "CENTER")
    anchorPointDropdown:SetRelativeWidth(0.33)
    anchorPointDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorPoint = value
        RecreateFrame()
    end)
    positionSection:AddChild(anchorPointDropdown)

    local targetFrameDropdown = AG:Create("Dropdown")
    targetFrameDropdown:SetLabel("Target Frame")
    targetFrameDropdown:SetList(GetAvailableFrames())
    targetFrameDropdown:SetValue(savedVars.anchorFrame or "UIParent")
    targetFrameDropdown:SetRelativeWidth(0.33)
    targetFrameDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorFrame = value
        RecreateFrame()
    end)
    positionSection:AddChild(targetFrameDropdown)

    local targetAnchorDropdown = AG:Create("Dropdown")
    targetAnchorDropdown:SetLabel("Target Anchor")
    targetAnchorDropdown:SetList(anchorPointsList)
    targetAnchorDropdown:SetValue(savedVars.anchorRelativePoint or "CENTER")
    targetAnchorDropdown:SetRelativeWidth(0.33)
    targetAnchorDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorRelativePoint = value
        RecreateFrame()
    end)
    positionSection:AddChild(targetAnchorDropdown)

    local xOffsetSlider = AG:Create("Slider")
    xOffsetSlider:SetLabel("X Offset")
    xOffsetSlider:SetSliderValues(-200, 200, 1)
    xOffsetSlider:SetValue(savedVars.anchorOffsetX or 0)
    xOffsetSlider:SetRelativeWidth(0.5)
    xOffsetSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorOffsetX = value
        RecreateFrame()
    end)
    positionSection:AddChild(xOffsetSlider)

    local yOffsetSlider = AG:Create("Slider")
    yOffsetSlider:SetLabel("Y Offset")
    yOffsetSlider:SetSliderValues(-200, 200, 1)
    yOffsetSlider:SetValue(savedVars.anchorOffsetY or 0)
    yOffsetSlider:SetRelativeWidth(0.5)
    yOffsetSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.anchorOffsetY = value
        RecreateFrame()
    end)
    positionSection:AddChild(yOffsetSlider)

    -- ==== APPEARANCE SECTION ====
    local appearanceSection = AG:Create("InlineGroup")
    appearanceSection:SetTitle("Appearance")
    appearanceSection:SetLayout("Flow")
    appearanceSection:SetFullWidth(true)
    scrollFrame:AddChild(appearanceSection)

    local sizeSlider = AG:Create("Slider")
    sizeSlider:SetLabel("Icon Size")
    sizeSlider:SetSliderValues(24, 96, 1)
    sizeSlider:SetValue(savedVars.iconSize or 48)
    sizeSlider:SetRelativeWidth(0.5)
    sizeSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.iconSize = value
        RecreateFrame()
    end)
    appearanceSection:AddChild(sizeSlider)

    local borderThicknessSlider = AG:Create("Slider")
    borderThicknessSlider:SetLabel("Border Thickness")
    borderThicknessSlider:SetSliderValues(0, 8, 1)
    borderThicknessSlider:SetValue(savedVars.borderThickness or 2)
    borderThicknessSlider:SetRelativeWidth(0.5)
    borderThicknessSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.borderThickness = value
        RecreateFrame()
    end)
    appearanceSection:AddChild(borderThicknessSlider)

    local borderColorPicker = AG:Create("ColorPicker")
    borderColorPicker:SetLabel("Border Color")
    borderColorPicker:SetHasAlpha(true)
    borderColorPicker:SetColor(
        savedVars.borderColor.r, savedVars.borderColor.g,
        savedVars.borderColor.b, savedVars.borderColor.a
    )
    borderColorPicker:SetRelativeWidth(0.5)
    borderColorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
        savedVars.borderColor = { r = r, g = g, b = b, a = a }
        if InnervateModule.iconFrame then
            InnervateModule.iconFrame:SetBackdropBorderColor(r, g, b, a)
        end
    end)
    appearanceSection:AddChild(borderColorPicker)

    -- ==== COOLDOWN SECTION ====
    local cooldownSection = AG:Create("InlineGroup")
    cooldownSection:SetTitle("Cooldown")
    cooldownSection:SetLayout("Flow")
    cooldownSection:SetFullWidth(true)
    scrollFrame:AddChild(cooldownSection)

    local swipeCheck = AG:Create("CheckBox")
    swipeCheck:SetLabel("Show Cooldown Swipe")
    swipeCheck:SetValue(savedVars.showSwipe)
    swipeCheck:SetRelativeWidth(0.5)
    swipeCheck:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.showSwipe = value
        UpdatePreviewVisibility()
    end)
    cooldownSection:AddChild(swipeCheck)

    local countdownTextCheck = AG:Create("CheckBox")
    countdownTextCheck:SetLabel("Show Countdown Text")
    countdownTextCheck:SetValue(savedVars.showCountdownText)
    countdownTextCheck:SetRelativeWidth(0.5)
    countdownTextCheck:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.showCountdownText = value
        UpdatePreviewVisibility()
        UpdateControlsVisibility()
    end)
    cooldownSection:AddChild(countdownTextCheck)

    local reverseSwipeCheck = AG:Create("CheckBox")
    reverseSwipeCheck:SetLabel("Reverse Swipe")
    reverseSwipeCheck:SetValue(savedVars.reverseSwipe)
    reverseSwipeCheck:SetRelativeWidth(0.5)
    reverseSwipeCheck:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.reverseSwipe = value
        UpdatePreviewVisibility()
    end)
    cooldownSection:AddChild(reverseSwipeCheck)

    local countdownTextSizeSlider = AG:Create("Slider")
    countdownTextSizeSlider:SetLabel("Countdown Text Size")
    countdownTextSizeSlider:SetSliderValues(8, 48, 1)
    countdownTextSizeSlider:SetValue(savedVars.countdownTextSize or 18)
    countdownTextSizeSlider:SetRelativeWidth(0.5)
    countdownTextSizeSlider:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.countdownTextSize = value
        UpdatePreviewVisibility()
    end)
    cooldownSection:AddChild(countdownTextSizeSlider)

    -- ==== GLOW SECTION ====
    local glowSection = AG:Create("InlineGroup")
    glowSection:SetTitle("Glow")
    glowSection:SetLayout("Flow")
    glowSection:SetFullWidth(true)
    scrollFrame:AddChild(glowSection)

    local glowCheck = AG:Create("CheckBox")
    glowCheck:SetLabel("Enable Glow")
    glowCheck:SetValue(savedVars.glowEnabled)
    glowCheck:SetRelativeWidth(0.5)
    glowCheck:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.glowEnabled = value
        UpdatePreviewVisibility()
        UpdateControlsVisibility()
    end)
    glowSection:AddChild(glowCheck)

    local glowTypeDropdown = AG:Create("Dropdown")
    glowTypeDropdown:SetLabel("Glow Type")
    glowTypeDropdown:SetList(GLOW_TYPES)
    glowTypeDropdown:SetValue(savedVars.glowType or "Pixel")
    glowTypeDropdown:SetRelativeWidth(0.5)
    glowTypeDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.glowType = value
        UpdatePreviewVisibility()
        UpdateControlsVisibility()
    end)
    glowSection:AddChild(glowTypeDropdown)

    -- Per-type glow settings container
    local glowSettingsGroup = AG:Create("SimpleGroup")
    glowSettingsGroup:SetLayout("Flow")
    glowSettingsGroup:SetFullWidth(true)
    glowSection:AddChild(glowSettingsGroup)

    local function RebuildGlowSettings()
        glowSettingsGroup:ReleaseChildren()
        glowSettingsWidgets = {}

        local glowType = savedVars.glowType or "Pixel"
        local settings = savedVars.glow[glowType]
        if not settings then return end

        -- Color picker (shared by all types)
        local colorPicker = AG:Create("ColorPicker")
        colorPicker:SetLabel("Glow Color")
        colorPicker:SetHasAlpha(true)
        colorPicker:SetColor(ColorToRGBA(settings.color))
        colorPicker:SetRelativeWidth(0.33)
        colorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
            settings.color = { r, g, b, a }
            UpdatePreviewVisibility()
        end)
        glowSettingsGroup:AddChild(colorPicker)
        table.insert(glowSettingsWidgets, colorPicker)

        if glowType == "Pixel" then
            local linesSlider = AG:Create("Slider")
            linesSlider:SetLabel("Lines")
            linesSlider:SetSliderValues(1, 20, 1)
            linesSlider:SetValue(settings.lines or 5)
            linesSlider:SetRelativeWidth(0.33)
            linesSlider:SetCallback("OnValueChanged", function(_, _, value)
                settings.lines = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(linesSlider)
            table.insert(glowSettingsWidgets, linesSlider)

            local freqSlider = AG:Create("Slider")
            freqSlider:SetLabel("Frequency")
            freqSlider:SetSliderValues(0.05, 1, 0.05)
            freqSlider:SetValue(settings.frequency or 0.25)
            freqSlider:SetRelativeWidth(0.33)
            freqSlider:SetCallback("OnValueChanged", function(_, _, value)
                settings.frequency = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(freqSlider)
            table.insert(glowSettingsWidgets, freqSlider)

            local lengthSlider = AG:Create("Slider")
            lengthSlider:SetLabel("Length")
            lengthSlider:SetSliderValues(1, 10, 1)
            lengthSlider:SetValue(settings.length or 2)
            lengthSlider:SetRelativeWidth(0.33)
            lengthSlider:SetCallback("OnValueChanged", function(_, _, value)
                settings.length = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(lengthSlider)
            table.insert(glowSettingsWidgets, lengthSlider)

            local thicknessSlider = AG:Create("Slider")
            thicknessSlider:SetLabel("Thickness")
            thicknessSlider:SetSliderValues(1, 5, 1)
            thicknessSlider:SetValue(settings.thickness or 1)
            thicknessSlider:SetRelativeWidth(0.33)
            thicknessSlider:SetCallback("OnValueChanged", function(_, _, value)
                settings.thickness = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(thicknessSlider)
            table.insert(glowSettingsWidgets, thicknessSlider)

            local xOffSlider = AG:Create("Slider")
            xOffSlider:SetLabel("X Offset")
            xOffSlider:SetSliderValues(-10, 10, 1)
            xOffSlider:SetValue(settings.xOffset or -1)
            xOffSlider:SetRelativeWidth(0.33)
            xOffSlider:SetCallback("OnValueChanged", function(_, _, value)
                settings.xOffset = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(xOffSlider)
            table.insert(glowSettingsWidgets, xOffSlider)

            local yOffSlider = AG:Create("Slider")
            yOffSlider:SetLabel("Y Offset")
            yOffSlider:SetSliderValues(-10, 10, 1)
            yOffSlider:SetValue(settings.yOffset or -1)
            yOffSlider:SetRelativeWidth(0.33)
            yOffSlider:SetCallback("OnValueChanged", function(_, _, value)
                settings.yOffset = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(yOffSlider)
            table.insert(glowSettingsWidgets, yOffSlider)

            local borderCheck = AG:Create("CheckBox")
            borderCheck:SetLabel("Border")
            borderCheck:SetValue(settings.border or false)
            borderCheck:SetRelativeWidth(0.33)
            borderCheck:SetCallback("OnValueChanged", function(_, _, value)
                settings.border = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(borderCheck)
            table.insert(glowSettingsWidgets, borderCheck)

        elseif glowType == "Autocast" then
            local particlesSlider = AG:Create("Slider")
            particlesSlider:SetLabel("Particles")
            particlesSlider:SetSliderValues(1, 20, 1)
            particlesSlider:SetValue(settings.particles or 10)
            particlesSlider:SetRelativeWidth(0.33)
            particlesSlider:SetCallback("OnValueChanged", function(_, _, value)
                settings.particles = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(particlesSlider)
            table.insert(glowSettingsWidgets, particlesSlider)

            local freqSlider = AG:Create("Slider")
            freqSlider:SetLabel("Frequency")
            freqSlider:SetSliderValues(0.05, 1, 0.05)
            freqSlider:SetValue(settings.frequency or 0.25)
            freqSlider:SetRelativeWidth(0.33)
            freqSlider:SetCallback("OnValueChanged", function(_, _, value)
                settings.frequency = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(freqSlider)
            table.insert(glowSettingsWidgets, freqSlider)

            local scaleSlider = AG:Create("Slider")
            scaleSlider:SetLabel("Scale")
            scaleSlider:SetSliderValues(0.5, 3, 0.1)
            scaleSlider:SetValue(settings.scale or 1)
            scaleSlider:SetRelativeWidth(0.33)
            scaleSlider:SetCallback("OnValueChanged", function(_, _, value)
                settings.scale = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(scaleSlider)
            table.insert(glowSettingsWidgets, scaleSlider)

            local xOffSlider = AG:Create("Slider")
            xOffSlider:SetLabel("X Offset")
            xOffSlider:SetSliderValues(-10, 10, 1)
            xOffSlider:SetValue(settings.xOffset or -1)
            xOffSlider:SetRelativeWidth(0.33)
            xOffSlider:SetCallback("OnValueChanged", function(_, _, value)
                settings.xOffset = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(xOffSlider)
            table.insert(glowSettingsWidgets, xOffSlider)

            local yOffSlider = AG:Create("Slider")
            yOffSlider:SetLabel("Y Offset")
            yOffSlider:SetSliderValues(-10, 10, 1)
            yOffSlider:SetValue(settings.yOffset or -1)
            yOffSlider:SetRelativeWidth(0.33)
            yOffSlider:SetCallback("OnValueChanged", function(_, _, value)
                settings.yOffset = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(yOffSlider)
            table.insert(glowSettingsWidgets, yOffSlider)

        elseif glowType == "Proc" then
            local insetSlider = AG:Create("Slider")
            insetSlider:SetLabel("Inset")
            insetSlider:SetSliderValues(-10, 10, 1)
            insetSlider:SetValue(settings.inset or 0)
            insetSlider:SetRelativeWidth(0.33)
            insetSlider:SetCallback("OnValueChanged", function(_, _, value)
                settings.inset = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(insetSlider)
            table.insert(glowSettingsWidgets, insetSlider)

        elseif glowType == "Button" then
            local freqSlider = AG:Create("Slider")
            freqSlider:SetLabel("Frequency")
            freqSlider:SetSliderValues(0.05, 1, 0.05)
            freqSlider:SetValue(settings.frequency or 0.125)
            freqSlider:SetRelativeWidth(0.33)
            freqSlider:SetCallback("OnValueChanged", function(_, _, value)
                settings.frequency = value
                UpdatePreviewVisibility()
            end)
            glowSettingsGroup:AddChild(freqSlider)
            table.insert(glowSettingsWidgets, freqSlider)
        end

        -- Apply disabled state if needed
        local disabled = not savedVars.enabled or not savedVars.glowEnabled
        for _, widget in ipairs(glowSettingsWidgets) do
            widget:SetDisabled(disabled)
        end
    end

    -- Build initial glow settings
    RebuildGlowSettings()

    -- Hook glow type changes to rebuild the settings panel
    glowTypeDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.glowType = value
        RebuildGlowSettings()
        scrollFrame:DoLayout()
        UpdatePreviewVisibility()
    end)

    -- ==== SOUND SECTION ====
    local soundSection = AG:Create("InlineGroup")
    soundSection:SetTitle("Sound")
    soundSection:SetLayout("Flow")
    soundSection:SetFullWidth(true)
    scrollFrame:AddChild(soundSection)

    local channelDropdown = AG:Create("Dropdown")
    channelDropdown:SetLabel("Sound Channel")
    channelDropdown:SetList(SOUND_CHANNELS)
    channelDropdown:SetValue(savedVars.soundChannel or "Master")
    channelDropdown:SetRelativeWidth(0.33)
    channelDropdown:SetCallback("OnValueChanged", function(_, _, value)
        savedVars.soundChannel = value
    end)
    soundSection:AddChild(channelDropdown)

    local startSoundDropdown = AG:Create("LSM30_Sound")
    startSoundDropdown:SetList()
    startSoundDropdown:SetLabel("Innervate Start Sound")
    startSoundDropdown:SetValue(savedVars.startSound or "None")
    startSoundDropdown:SetRelativeWidth(0.33)
    startSoundDropdown:SetCallback("OnValueChanged", function(widget, _, value)
        savedVars.startSound = value
        widget:SetValue(value)
        PlayLSMSound(value, savedVars.soundChannel)
    end)
    soundSection:AddChild(startSoundDropdown)

    local endSoundDropdown = AG:Create("LSM30_Sound")
    endSoundDropdown:SetList()
    endSoundDropdown:SetLabel("Innervate End Sound")
    endSoundDropdown:SetValue(savedVars.endSound or "None")
    endSoundDropdown:SetRelativeWidth(0.33)
    endSoundDropdown:SetCallback("OnValueChanged", function(widget, _, value)
        savedVars.endSound = value
        widget:SetValue(value)
        PlayLSMSound(value, savedVars.soundChannel)
    end)
    soundSection:AddChild(endSoundDropdown)

    -- Controls visibility
    UpdateControlsVisibility = function()
        local enabled = savedVars.enabled
        local glowEnabled = savedVars.glowEnabled

        anchorPointDropdown:SetDisabled(not enabled)
        targetFrameDropdown:SetDisabled(not enabled)
        targetAnchorDropdown:SetDisabled(not enabled)
        xOffsetSlider:SetDisabled(not enabled)
        yOffsetSlider:SetDisabled(not enabled)
        sizeSlider:SetDisabled(not enabled)
        borderThicknessSlider:SetDisabled(not enabled)
        borderColorPicker:SetDisabled(not enabled)
        swipeCheck:SetDisabled(not enabled)
        countdownTextCheck:SetDisabled(not enabled)
        countdownTextSizeSlider:SetDisabled(not enabled or not savedVars.showCountdownText)
        reverseSwipeCheck:SetDisabled(not enabled)
        glowCheck:SetDisabled(not enabled)
        glowTypeDropdown:SetDisabled(not enabled or not glowEnabled)
        channelDropdown:SetDisabled(not enabled)
        startSoundDropdown:SetDisabled(not enabled)
        endSoundDropdown:SetDisabled(not enabled)

        for _, widget in ipairs(glowSettingsWidgets) do
            widget:SetDisabled(not enabled or not glowEnabled)
        end
    end

    UpdateControlsVisibility()
    UpdatePreviewVisibility()

    -- Defer a layout pass so nested container heights are resolved before
    -- the ScrollFrame calculates its scroll range.
    C_Timer.After(0, function()
        scrollFrame:DoLayout()
    end)
end

WaitQOL:RegisterModule("InnervateTracker", InnervateModule)
