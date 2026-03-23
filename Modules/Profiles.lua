local _, ns = ...
local WaitQOL = ns.WaitQOL
local AG = ns.AG

-- Profiles module table
local ProfilesModule = {
    displayName = "Profiles",
    order = 999, -- Show at the end
}

-- Default settings for this module (none needed, profiles are handled by AceDB)
function ProfilesModule:GetDefaults()
    return {}
end

-- Helper: Serialize a table to a string
local function SerializeTable(tbl, depth)
    depth = depth or 0
    if depth > 10 then return "..." end -- Prevent infinite recursion

    local result = "{"
    local first = true

    for k, v in pairs(tbl) do
        if not first then
            result = result .. ","
        end
        first = false

        -- Serialize key
        if type(k) == "string" then
            result = result .. '["' .. k:gsub('"', '\\"') .. '"]='
        else
            result = result .. "[" .. tostring(k) .. "]="
        end

        -- Serialize value
        if type(v) == "table" then
            result = result .. SerializeTable(v, depth + 1)
        elseif type(v) == "string" then
            result = result .. '"' .. v:gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
        elseif type(v) == "number" or type(v) == "boolean" then
            result = result .. tostring(v)
        else
            result = result .. "nil"
        end
    end

    result = result .. "}"
    return result
end

-- Helper: Deserialize a string to a table
local function DeserializeTable(str)
    if not str or str == "" then return nil end

    -- Use loadstring to evaluate the table string
    local func, err = loadstring("return " .. str)
    if not func then
        return nil, "Parse error: " .. tostring(err)
    end

    local success, result = pcall(func)
    if not success then
        return nil, "Execution error: " .. tostring(result)
    end

    return result
end

-- Helper: Export profile to string
local function ExportProfile()
    local profileData = {}
    -- Include profile name
    profileData.profileName = WaitQOL.db:GetCurrentProfile()
    -- Copy only module settings, not internal AceDB data
    if WaitQOL.db.profile.modules then
        profileData.modules = WaitQOL.db.profile.modules
    end

    local serialized = SerializeTable(profileData)

    -- Try to use LibDeflate if available
    local LibDeflate = LibStub("LibDeflate", true)
    if LibDeflate then
        local compressed = LibDeflate:CompressDeflate(serialized)
        local encoded = LibDeflate:EncodeForPrint(compressed)
        return "!WQL1!" .. encoded
    else
        -- Fallback: just return the serialized string
        return "!WQL0!" .. serialized
    end
end

-- Helper: Generate unique profile name by appending numbers
local function GetUniqueProfileName(baseName)
    local existingProfiles = {}
    for _, profile in ipairs(WaitQOL.db:GetProfiles()) do
        existingProfiles[profile] = true
    end

    if not existingProfiles[baseName] then
        return baseName
    end

    -- Try appending (2), (3), etc.
    local counter = 2
    while existingProfiles[baseName .. " (" .. counter .. ")"] do
        counter = counter + 1
    end

    return baseName .. " (" .. counter .. ")"
end

-- Helper: Extract profile data from import string without applying it
local function ParseImportString(importString)
    if not importString or importString == "" then
        return nil, "No data provided"
    end

    -- Check for version prefix
    local version = importString:sub(1, 6)
    if version ~= "!WQL1!" and version ~= "!WQL0!" then
        return nil, "Invalid format - must start with !WQL1! or !WQL0!"
    end

    local serialized
    if version == "!WQL1!" then
        -- Compressed format
        local LibDeflate = LibStub("LibDeflate", true)
        if not LibDeflate then
            return nil, "LibDeflate not available - cannot decompress"
        end

        local encoded = importString:sub(7)
        local compressed = LibDeflate:DecodeForPrint(encoded)
        if not compressed then
            return nil, "Failed to decode data"
        end

        serialized = LibDeflate:DecompressDeflate(compressed)
        if not serialized then
            return nil, "Failed to decompress data"
        end
    else
        -- Uncompressed format
        serialized = importString:sub(7)
    end

    -- Deserialize
    local profileData, err = DeserializeTable(serialized)
    if not profileData then
        return nil, err or "Failed to parse data"
    end

    return profileData
end

-- Helper: Import profile from string
local function ImportProfile(importString)
    local profileData, err = ParseImportString(importString)
    if not profileData then
        return false, err
    end

    -- Apply to current profile
    if profileData.modules then
        WaitQOL.db.profile.modules = profileData.modules
    end

    return true
end


-- Tab 1: Profile Management
local function CreateProfilesTab(container)
    local scrollFrame = AG:Create("ScrollFrame")
    scrollFrame:SetLayout("Flow")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    container:AddChild(scrollFrame)

    -- Module title
    local title = AG:Create("Heading")
    title:SetText("Profile Management")
    title:SetFullWidth(true)
    scrollFrame:AddChild(title)

    -- Description
    local desc = AG:Create("Label")
    desc:SetText("Manage your addon profiles. Profiles allow you to have different settings for different characters or situations.")
    desc:SetFullWidth(true)
    scrollFrame:AddChild(desc)

    -- Profile management section
    local profileGroup = AG:Create("InlineGroup")
    profileGroup:SetTitle("Profile Management")
    profileGroup:SetLayout("Flow")
    profileGroup:SetFullWidth(true)
    scrollFrame:AddChild(profileGroup)

    local function GetProfileList()
        local profiles = {}
        for _, profile in ipairs(WaitQOL.db:GetProfiles()) do
            profiles[profile] = profile
        end
        return profiles
    end

    -- Forward declarations for widgets that need to be updated
    local currentProfileLabel, profileDropdown, copyFromDropdown, deleteDropdown
    local enableSpecCheck, specDropdowns

    -- RefreshProfiles function to update all UI widgets
    local function RefreshProfiles()
        local profileKeys = GetProfileList()
        local current = WaitQOL.db:GetCurrentProfile()

        -- Update current profile label
        currentProfileLabel:SetText("Active Profile: |cff00ff00" .. current .. "|r")

        -- Update profile dropdown
        profileDropdown:SetList(profileKeys)
        profileDropdown:SetValue(current)

        -- Update copy dropdown
        copyFromDropdown:SetList(profileKeys)
        copyFromDropdown:SetValue(nil)

        -- Update delete dropdown (exclude current profile)
        local profilesToDelete = {}
        for k, v in pairs(profileKeys) do
            if k ~= current then
                profilesToDelete[k] = v
            end
        end
        deleteDropdown:SetList(profilesToDelete)
        deleteDropdown:SetValue(nil)

        -- Update spec dropdowns if they exist
        if specDropdowns then
            for i, dropdown in ipairs(specDropdowns) do
                dropdown:SetList(profileKeys)
                dropdown:SetValue(WaitQOL.db:GetDualSpecProfile(i))
            end
        end

        profileGroup:DoLayout()
    end

    -- Row 1: Current profile display
    currentProfileLabel = AG:Create("Label")
    currentProfileLabel:SetText("Active Profile: |cff00ff00" .. WaitQOL.db:GetCurrentProfile() .. "|r")
    currentProfileLabel:SetFullWidth(true)
    profileGroup:AddChild(currentProfileLabel)

    -- Row 2: Switch profile dropdown
    profileDropdown = AG:Create("Dropdown")
    profileDropdown:SetLabel("Switch Profile:")
    profileDropdown:SetList(GetProfileList())
    profileDropdown:SetValue(WaitQOL.db:GetCurrentProfile())
    profileDropdown:SetRelativeWidth(0.6)
    profileDropdown:SetCallback("OnValueChanged", function(_, _, value)
        WaitQOL.db:SetProfile(value)
        RefreshProfiles()
    end)
    profileGroup:AddChild(profileDropdown)

    -- Row 3: Create new profile (name box + button)
    local newProfileBox = AG:Create("EditBox")
    newProfileBox:SetLabel("Create New Profile:")
    newProfileBox:SetRelativeWidth(0.6)
    profileGroup:AddChild(newProfileBox)

    local newProfileBtn = AG:Create("Button")
    newProfileBtn:SetText("Create")
    newProfileBtn:SetRelativeWidth(0.35)
    newProfileBtn:SetCallback("OnClick", function()
        local name = newProfileBox:GetText()
        if name and name ~= "" then
            WaitQOL.db:SetProfile(name)
            print("|cff00ff00WaitQOL|r: Created and switched to profile '" .. name .. "'")
            RefreshProfiles()
            newProfileBox:SetText("")
        end
    end)
    profileGroup:AddChild(newProfileBtn)

    -- Row 4: Copy profile
    copyFromDropdown = AG:Create("Dropdown")
    copyFromDropdown:SetLabel("Copy From Profile:")
    copyFromDropdown:SetList(GetProfileList())
    copyFromDropdown:SetRelativeWidth(0.6)
    copyFromDropdown:SetCallback("OnValueChanged", function(_, _, value)
        if value and value ~= WaitQOL.db:GetCurrentProfile() then
            WaitQOL.db:CopyProfile(value)
            print("|cff00ff00WaitQOL|r: Copied settings from '" .. value .. "' to current profile")
            RefreshProfiles()
        end
    end)
    profileGroup:AddChild(copyFromDropdown)

    -- Row 5: Reset button
    local resetBtn = AG:Create("Button")
    resetBtn:SetText("Reset Current Profile")
    resetBtn:SetRelativeWidth(0.6)
    resetBtn:SetCallback("OnClick", function()
        WaitQOL.db:ResetProfile()
        print("|cff00ff00WaitQOL|r: Reset profile to defaults")
        RefreshProfiles()
    end)
    profileGroup:AddChild(resetBtn)

    -- Row 6: Delete profile (dropdown + button)
    deleteDropdown = AG:Create("Dropdown")
    deleteDropdown:SetLabel("Delete Profile:")
    deleteDropdown:SetRelativeWidth(0.6)
    profileGroup:AddChild(deleteDropdown)

    local deleteBtn = AG:Create("Button")
    deleteBtn:SetText("Delete")
    deleteBtn:SetRelativeWidth(0.35)
    deleteBtn:SetCallback("OnClick", function()
        local selectedProfile = deleteDropdown:GetValue()
        if selectedProfile and selectedProfile ~= WaitQOL.db:GetCurrentProfile() then
            WaitQOL.db:DeleteProfile(selectedProfile)
            print("|cff00ff00WaitQOL|r: Deleted profile '" .. selectedProfile .. "'")
            RefreshProfiles()
        end
    end)
    profileGroup:AddChild(deleteBtn)

    -- Spacer
    local spacer1 = AG:Create("Label")
    spacer1:SetText(" ")
    spacer1:SetFullWidth(true)
    scrollFrame:AddChild(spacer1)

    -- Spec-specific profiles (if LibDualSpec is available)
    if WaitQOL.db.IsDualSpecEnabled then
        local specProfileGroup = AG:Create("InlineGroup")
        specProfileGroup:SetTitle("Spec-Specific Profiles")
        specProfileGroup:SetLayout("Flow")
        specProfileGroup:SetFullWidth(true)
        scrollFrame:AddChild(specProfileGroup)

        local specDesc = AG:Create("Label")
        specDesc:SetText("Automatically switch profiles when you change specializations.")
        specDesc:SetFullWidth(true)
        specDesc:SetColor(0.7, 0.7, 0.7)
        specProfileGroup:AddChild(specDesc)

        -- Enable spec profiles checkbox
        enableSpecCheck = AG:Create("CheckBox")
        enableSpecCheck:SetLabel("Enable Spec-Specific Profiles")
        enableSpecCheck:SetValue(WaitQOL.db:IsDualSpecEnabled())
        enableSpecCheck:SetFullWidth(true)
        specProfileGroup:AddChild(enableSpecCheck)

        -- Spec dropdowns
        local numSpecs = GetNumSpecializations()
        specDropdowns = {}

        for i = 1, numSpecs do
            local _, specName = GetSpecializationInfo(i)

            local specDropdown = AG:Create("Dropdown")
            specDropdown:SetLabel(specName .. ":")
            specDropdown:SetList(GetProfileList())
            specDropdown:SetRelativeWidth(0.5)

            -- Get current profile assignment for this spec
            local currentProfile = WaitQOL.db:GetDualSpecProfile(i)
            if currentProfile then
                specDropdown:SetValue(currentProfile)
            end

            specDropdown:SetCallback("OnValueChanged", function(_, _, value)
                WaitQOL.db:SetDualSpecProfile(value, i)
                RefreshProfiles()
            end)
            specProfileGroup:AddChild(specDropdown)
            specDropdowns[i] = specDropdown
        end

        -- Set initial visibility of spec dropdowns
        local enabled = WaitQOL.db:IsDualSpecEnabled()
        for _, dropdown in ipairs(specDropdowns) do
            dropdown:SetDisabled(not enabled)
        end

        -- Set checkbox callback
        enableSpecCheck:SetCallback("OnValueChanged", function(_, _, value)
            WaitQOL.db:SetDualSpecEnabled(value)
            for i = 1, numSpecs do
                specDropdowns[i]:SetDisabled(not value)
            end
            RefreshProfiles()
        end)
    end

    -- Initial refresh to populate all dropdowns
    RefreshProfiles()
end

-- Tab 2: Export
local function CreateExportTab(container)
    local scrollFrame = AG:Create("ScrollFrame")
    scrollFrame:SetLayout("Flow")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    container:AddChild(scrollFrame)

    -- Title
    local title = AG:Create("Heading")
    title:SetText("Export Profile")
    title:SetFullWidth(true)
    scrollFrame:AddChild(title)

    -- Description
    local desc = AG:Create("Label")
    desc:SetText("Export your current profile settings to a shareable string. Copy the text below and share it with others.")
    desc:SetFullWidth(true)
    scrollFrame:AddChild(desc)

    -- Spacer
    local spacer1 = AG:Create("Label")
    spacer1:SetText(" ")
    spacer1:SetFullWidth(true)
    scrollFrame:AddChild(spacer1)

    -- Generate export string
    local exportString = ExportProfile()

    -- Multi-line editbox for export
    local exportBox = AG:Create("MultiLineEditBox")
    exportBox:SetLabel("Profile String:")
    exportBox:SetText(exportString)
    exportBox:SetFullWidth(true)
    exportBox:SetNumLines(20)
    exportBox:DisableButton(true)
    scrollFrame:AddChild(exportBox)

    -- Focus and select all on next frame
    C_Timer.After(0, function()
        if exportBox and exportBox.editBox then
            exportBox.editBox:SetFocus()
            exportBox.editBox:HighlightText()
            exportBox.editBox:SetCursorPosition(0)
        end
    end)
end

-- Tab 3: Import
local function CreateImportTab(container)
    local scrollFrame = AG:Create("ScrollFrame")
    scrollFrame:SetLayout("Flow")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    container:AddChild(scrollFrame)

    -- Title
    local title = AG:Create("Heading")
    title:SetText("Import Profile")
    title:SetFullWidth(true)
    scrollFrame:AddChild(title)

    -- Description
    local desc = AG:Create("Label")
    desc:SetText("Import a profile from a shared string. Paste the profile string below, and the profile name will be auto-filled (you can change it).")
    desc:SetFullWidth(true)
    scrollFrame:AddChild(desc)

    -- Spacer
    local spacer1 = AG:Create("Label")
    spacer1:SetText(" ")
    spacer1:SetFullWidth(true)
    scrollFrame:AddChild(spacer1)

    -- Import form group
    local importGroup = AG:Create("InlineGroup")
    importGroup:SetTitle("Import Settings")
    importGroup:SetLayout("Flow")
    importGroup:SetFullWidth(true)
    scrollFrame:AddChild(importGroup)

    -- Profile name input
    local profileNameBox = AG:Create("EditBox")
    profileNameBox:SetLabel("New Profile Name:")
    profileNameBox:SetRelativeWidth(0.6)
    importGroup:AddChild(profileNameBox)

    -- Spacer
    local spacer2 = AG:Create("Label")
    spacer2:SetText(" ")
    spacer2:SetFullWidth(true)
    importGroup:AddChild(spacer2)

    -- Import string multiline editbox
    local importBox = AG:Create("MultiLineEditBox")
    importBox:SetLabel("Profile String:")
    importBox:SetFullWidth(true)
    importBox:SetNumLines(15)
    importBox:DisableButton(true)
    importGroup:AddChild(importBox)

    -- Import button
    local importBtn = AG:Create("Button")
    importBtn:SetText("Import Profile")
    importBtn:SetRelativeWidth(0.5)
    importBtn:SetDisabled(true)
    importGroup:AddChild(importBtn)

    -- Validation function
    local function ValidateInputs()
        local profileName = profileNameBox:GetText()
        local importString = importBox:GetText()

        -- Check if profile name is valid
        local nameValid = profileName and profileName:trim() ~= ""

        -- Check if import string is valid
        local stringValid = importString and importString:trim() ~= ""

        -- Enable button only if both are valid
        if nameValid and stringValid then
            importBtn:SetDisabled(false)
        else
            importBtn:SetDisabled(true)
        end
    end

    -- Add validation on text change
    profileNameBox:SetCallback("OnTextChanged", function()
        ValidateInputs()
    end)

    -- When import string changes, try to parse it and auto-fill profile name
    importBox:SetCallback("OnTextChanged", function(widget)
        local importString = widget:GetText()

        if importString and importString:trim() ~= "" then
            local profileData = ParseImportString(importString)

            if profileData and profileData.profileName then
                -- Generate unique name if needed
                local uniqueName = GetUniqueProfileName(profileData.profileName)
                profileNameBox:SetText(uniqueName)
            end
        end

        ValidateInputs()
    end)

    -- Import button click handler
    importBtn:SetCallback("OnClick", function()
        local profileName = profileNameBox:GetText()
        local importString = importBox:GetText()

        -- Ensure unique name
        local finalName = GetUniqueProfileName(profileName)

        -- Create new profile
        WaitQOL.db:SetProfile(finalName)

        -- Import to new profile
        local success, err = ImportProfile(importString)

        if success then
            print("|cff00ff00WaitQOL|r: Import successful! Created profile '" .. finalName .. "'.")

            -- Switch to Profiles tab on next frame (this will rebuild the tab content with updated profile list)
            C_Timer.After(0, function()
                -- The container passed to CreateImportTab is the tabGroup widget
                -- We need to traverse up the widget hierarchy to find it
                local widget = scrollFrame
                while widget and widget.type ~= "TabGroup" do
                    widget = widget.parent
                end

                if widget and widget.type == "TabGroup" then
                    widget:SelectTab("profiles")
                end
            end)
        else
            print("|cffff0000WaitQOL|r: Import failed: " .. tostring(err))
            -- Try to clean up the new profile if import failed
            if WaitQOL.db:GetCurrentProfile() == finalName then
                WaitQOL.db:DeleteProfile(finalName)
            end
        end
    end)

    -- Focus the import box on next frame
    C_Timer.After(0, function()
        if importBox and importBox.editBox then
            importBox.editBox:SetFocus()
        end
    end)
end

-- Create the config panel for this module (AceGUI version)
function ProfilesModule:CreateConfigPanel(container, _)
    -- Create tab group
    local tabGroup = AG:Create("TabGroup")
    tabGroup:SetLayout("Flow")
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)

    -- Define tabs
    local tabs = {
        { text = "Profiles", value = "profiles" },
        { text = "Export", value = "export" },
        { text = "Import", value = "import" }
    }

    tabGroup:SetTabs(tabs)
    tabGroup:SelectTab("profiles")

    -- Tab selection handler
    tabGroup:SetCallback("OnGroupSelected", function(widget, _, selectedTab)
        widget:ReleaseChildren()

        if selectedTab == "profiles" then
            CreateProfilesTab(widget)
        elseif selectedTab == "export" then
            CreateExportTab(widget)
        elseif selectedTab == "import" then
            CreateImportTab(widget)
        end
    end)

    container:AddChild(tabGroup)

    -- Trigger initial tab display
    tabGroup:SelectTab("profiles")
end

-- Register the module with the core
WaitQOL:RegisterModule("Profiles", ProfilesModule)
