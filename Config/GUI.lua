local _, ns = ...
local WaitQOL = ns.WaitQOL
local AG = ns.AG
local LSM = ns.LSM

ns.GUI = {}
local GUI = ns.GUI

local isGUIOpen = false
local Container = nil

-- Build main navigation tree
local function BuildMainNavigationTree()
    local tree = {}

    -- Add module entries (including Profiles module)
    for _, moduleName in ipairs(WaitQOL.moduleOrder) do
        local module = WaitQOL.modules[moduleName]
        if module then
            table.insert(tree, {
                text = module.displayName or moduleName,
                value = moduleName,
            })
        end
    end

    return tree
end

-- Create module configuration panel
local function CreateModuleConfigPanel(container, moduleName)
    local module = WaitQOL.modules[moduleName]
    if not module then
        print("ERROR: Module not found: " .. tostring(moduleName))
        return
    end

    local savedVars = WaitQOL.db.profile.modules[moduleName]
    if not savedVars then
        print("ERROR: SavedVars not found for module: " .. tostring(moduleName))
        -- Show an error message in the panel
        local label = AG:Create("Label")
        label:SetText("|cffff0000Error: Module settings not initialized. Try closing and reopening the config.|r")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    -- Call module's CreateConfigPanel if it exists
    if module.CreateConfigPanel then
        module:CreateConfigPanel(container, savedVars)
    else
        -- Default panel for modules without custom config
        local label = AG:Create("Label")
        label:SetText("No configuration options available for this module.")
        label:SetFullWidth(true)
        container:AddChild(label)
    end
end

-- Main tab selection handler
local function SelectTab(GUIContainer, _, tabValue)
    GUIContainer:ReleaseChildren()

    local Wrapper = AG:Create("SimpleGroup")
    Wrapper:SetFullWidth(true)
    Wrapper:SetFullHeight(true)
    Wrapper:SetLayout("Fill")
    GUIContainer:AddChild(Wrapper)

    -- All tabs are now module config panels (including Profiles)
    CreateModuleConfigPanel(Wrapper, tabValue)
end

-- Main GUI creation function
function GUI:CreateGUI()
    if isGUIOpen then return end
    if InCombatLockdown() then
        WaitQOL:Print("Cannot open config while in combat.")
        return
    end

    isGUIOpen = true

    Container = AG:Create("Frame")
    Container:SetTitle("WaitQOL")
    Container:SetLayout("Fill")
    Container:SetWidth(900)
    Container:SetHeight(600)
    Container:EnableResize(false)
    Container:SetCallback("OnClose", function(widget)
        AG:Release(widget)
        isGUIOpen = false
    end)

    local mainNavigationTree = BuildMainNavigationTree()
    local mainNavigationValues = {}
    for _, entry in ipairs(mainNavigationTree) do
        mainNavigationValues[entry.value] = true
    end

    -- Store navigation state
    GUI.MainNavigationStatus = GUI.MainNavigationStatus or {}

    local ContainerTreeGroup = AG:Create("TreeGroup")
    ContainerTreeGroup:SetLayout("Fill")
    ContainerTreeGroup:SetFullWidth(true)
    ContainerTreeGroup:SetFullHeight(true)
    ContainerTreeGroup:SetStatusTable(GUI.MainNavigationStatus)
    ContainerTreeGroup:SetTreeWidth(180, false)
    ContainerTreeGroup:SetTree(mainNavigationTree)
    ContainerTreeGroup:SetCallback("OnGroupSelected", SelectTab)
    Container:AddChild(ContainerTreeGroup)

    -- Select initial section
    local initialSection = GUI.MainNavigationStatus.selected
    if not initialSection or not mainNavigationValues[initialSection] then
        -- Default to first module
        if #WaitQOL.moduleOrder > 0 then
            initialSection = WaitQOL.moduleOrder[1]
        else
            initialSection = "Profiles"
        end
    end
    ContainerTreeGroup:SelectByValue(initialSection)
end

function GUI:CloseGUI()
    if isGUIOpen and Container then
        Container:Hide()
    end
end

function GUI:IsOpen()
    return isGUIOpen
end
