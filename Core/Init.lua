local addonName, ns = ...

-- Create the main addon object
WaitQOL = LibStub("AceAddon-3.0"):NewAddon("WaitQOL", "AceEvent-3.0", "AceConsole-3.0")
local WaitQOL = WaitQOL

-- Store namespace reference
ns.WaitQOL = WaitQOL
ns.AG = LibStub("AceGUI-3.0")
ns.LSM = LibStub("LibSharedMedia-3.0")

-- Module registry
WaitQOL.modules = {}
WaitQOL.moduleOrder = {}

-- Default database structure
local defaults = {
    profile = {
        modules = {},
    },
    global = {
        UseGlobalProfile = false,
        GlobalProfile = nil,
        minimapIcon = {},
    },
}

-- Helper to merge defaults into saved settings
local function MergeDefaults(saved, defaultSettings)
    for key, value in pairs(defaultSettings) do
        if saved[key] == nil then
            saved[key] = value
        elseif type(value) == "table" and type(saved[key]) == "table" then
            MergeDefaults(saved[key], value)
        end
    end
end

function WaitQOL:OnInitialize()
    -- Initialize database with profiles
    self.db = LibStub("AceDB-3.0"):New("WaitQOLDB", defaults, true)

    -- Set up dual spec support
    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

    -- Enable LibDualSpec if available
    local LibDualSpec = LibStub("LibDualSpec-1.0", true)
    if LibDualSpec then
        LibDualSpec:EnhanceDatabase(self.db, "WaitQOL")
    end

    -- Initialize all registered modules
    for _, moduleName in ipairs(self.moduleOrder) do
        local module = self.modules[moduleName]
        if module then
            -- Get module defaults
            local moduleDefaults = {}
            if module.GetDefaults then
                moduleDefaults = module:GetDefaults()
            end

            -- Ensure module settings exist in profile
            if not self.db.profile.modules[moduleName] then
                self.db.profile.modules[moduleName] = moduleDefaults
            else
                -- Merge in any missing default values
                MergeDefaults(self.db.profile.modules[moduleName], moduleDefaults)
            end

            -- Initialize the module
            if module.OnInitialize then
                module:OnInitialize(self.db.profile.modules[moduleName])
            end
        end
    end

    -- Register slash commands
    SLASH_WAITQOL1 = "/wqol"
    SlashCmdList["WAITQOL"] = function(msg)
        self:OpenConfig()
    end

    -- Minimap button via LibDBIcon
    local ldb = LibStub("LibDataBroker-1.1", true)
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if ldb and dbIcon then
        local dataObject = ldb:NewDataObject("WaitQOL", {
            type = "launcher",
            icon = "Interface\\AddOns\\WaitQOL\\WaitAddons",
            OnClick = function(_, button)
                if button == "LeftButton" then
                    WaitQOL:OpenConfig()
                end
            end,
            OnTooltipShow = function(tooltip)
                tooltip:AddLine("WaitQOL")
                tooltip:AddLine("Click to open settings", 0.8, 0.8, 0.8)
            end,
        })
        dbIcon:Register("WaitQOL", dataObject, self.db.global.minimapIcon)
    end

    self:Print("WaitQOL loaded. Use /wqol to open settings.")
end

function WaitQOL:OnEnable()
    -- Enable modules that are marked as enabled
    for _, moduleName in ipairs(self.moduleOrder) do
        local module = self.modules[moduleName]
        if module then
            local settings = self.db.profile.modules[moduleName]
            if settings and settings.enabled then
                if module.OnEnable then
                    module:OnEnable()
                end
            end
        end
    end
end

function WaitQOL:RefreshConfig()
    -- Always ensure module defaults exist in the profile
    for _, moduleName in ipairs(self.moduleOrder) do
        local module = self.modules[moduleName]
        if module then
            -- Get module defaults
            local moduleDefaults = {}
            if module.GetDefaults then
                moduleDefaults = module:GetDefaults()
            end

            -- Ensure module settings exist in profile
            if not self.db.profile.modules[moduleName] then
                self.db.profile.modules[moduleName] = moduleDefaults
            else
                -- Merge in any missing default values
                MergeDefaults(self.db.profile.modules[moduleName], moduleDefaults)
            end
        end
    end

    -- Skip module reinitialization if config GUI is open
    -- The Profiles module handles its own UI refresh via RefreshProfiles()
    if ns.GUI and ns.GUI.IsOpen and ns.GUI:IsOpen() then
        return
    end

    -- Reload all modules with new profile settings
    for _, moduleName in ipairs(self.moduleOrder) do
        local module = self.modules[moduleName]
        if module then
            local settings = self.db.profile.modules[moduleName]
            if settings then
                if module.OnInitialize then
                    module:OnInitialize(settings)
                end
                if settings.enabled and module.OnEnable then
                    module:OnEnable()
                end
            end
        end
    end
end

function WaitQOL:OpenConfig()
    if InCombatLockdown() then
        self:Print("Cannot open config while in combat.")
        return
    end

    if ns.GUI then
        if ns.GUI:IsOpen() then
            ns.GUI:CloseGUI()
        elseif ns.GUI.CreateGUI then
            ns.GUI:CreateGUI()
        end
    end
end

function WaitQOL:RegisterModule(moduleName, moduleTable)
    if not moduleName or not moduleTable then
        error("RegisterModule requires moduleName and moduleTable")
        return
    end

    self.modules[moduleName] = moduleTable
    table.insert(self.moduleOrder, moduleName)

    -- Sort modules by order if available
    table.sort(self.moduleOrder, function(a, b)
        local orderA = self.modules[a].order or 999
        local orderB = self.modules[b].order or 999
        return orderA < orderB
    end)
end
