local _, ns = ...
local WaitQOL = ns.WaitQOL

-- Module helper functions
WaitQOL.ModuleHelpers = {}

function WaitQOL.ModuleHelpers:CreateFrame(name, parent, template)
    return CreateFrame("Frame", name, parent or UIParent, template)
end

function WaitQOL.ModuleHelpers:GetLSMFont(fontName)
    local LSM = ns.LSM
    if LSM and LSM:IsValid("font", fontName) then
        return LSM:Fetch("font", fontName)
    end
    return "Fonts\\FRIZQT__.TTF"
end

function WaitQOL.ModuleHelpers:GetLSMBorder(borderName)
    if borderName == "None" then
        return nil
    end
    local LSM = ns.LSM
    if LSM and LSM:IsValid("border", borderName) then
        return LSM:Fetch("border", borderName)
    end
    return nil
end
