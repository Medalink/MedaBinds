--[[
    MedaUI - Shared UI Library
    A themed UI component library for Medalink's WoW addons
]]

-- Library registration with LibStub
local MAJOR, MINOR = "MedaUI-1.0", 1
local MedaUI = LibStub:NewLibrary(MAJOR, MINOR)
if not MedaUI then return end  -- Newer version already loaded

-- ============================================================================
-- Theme Definition (Dark Grey + Gold - Modern Material UI)
-- ============================================================================

MedaUI.Theme = {
    -- Backgrounds
    background = { 0.11, 0.11, 0.12, 0.97 },
    backgroundLight = { 0.16, 0.16, 0.17, 1 },
    backgroundDark = { 0.09, 0.09, 0.1, 1 },

    -- Borders
    border = { 0.2, 0.2, 0.21, 0.6 },
    borderLight = { 0.25, 0.25, 0.26, 0.4 },

    -- Gold accent colors
    gold = { 0.9, 0.7, 0.15, 1 },
    goldBright = { 1, 0.78, 0.2, 1 },
    goldDim = { 0.7, 0.55, 0.1, 1 },

    -- Text colors
    text = { 0.9, 0.9, 0.9, 1 },
    textDim = { 0.55, 0.55, 0.55, 1 },
    textDisabled = { 0.35, 0.35, 0.35, 1 },
    textGreen = { 0.4, 0.9, 0.4, 1 },

    -- Interactive elements
    button = { 0.16, 0.16, 0.17, 1 },
    buttonHover = { 0.22, 0.22, 0.23, 1 },
    buttonDisabled = { 0.1, 0.1, 0.11, 1 },
    input = { 0.13, 0.13, 0.14, 1 },

    -- Tabs
    tabActive = { 0.18, 0.18, 0.19, 1 },
    tabInactive = { 0.13, 0.13, 0.14, 1 },

    -- Table rows
    rowEven = { 0.12, 0.12, 0.13, 1 },
    rowOdd = { 0.1, 0.1, 0.11, 1 },
    rowHeader = { 0.16, 0.16, 0.17, 1 },
    rowSubheader = { 0.13, 0.13, 0.14, 1 },

    -- Highlights
    highlight = { 0.9, 0.7, 0.15, 0.15 },

    -- Misc
    closeHover = { 1, 0.4, 0.4, 1 },
    menuBackground = { 0.12, 0.12, 0.13, 0.98 },
}

-- ============================================================================
-- Theme Access API
-- ============================================================================

--- Get the theme table
--- @return table The complete theme color table
function MedaUI:GetTheme()
    return self.Theme
end

--- Get a specific color from the theme
--- @param key string The color key (e.g., "gold", "background")
--- @return table|nil The color as {r, g, b, a} or nil if not found
function MedaUI:GetColor(key)
    return self.Theme[key]
end

--- Unpack a color for use with SetBackdropColor, etc.
--- @param key string The color key
--- @return number, number, number, number r, g, b, a values
function MedaUI:UnpackColor(key)
    local color = self.Theme[key]
    if color then
        return unpack(color)
    end
    return 1, 1, 1, 1  -- Default white
end

-- ============================================================================
-- Widget Creation API (populated by widget files)
-- ============================================================================

-- These methods are defined in the individual widget files:
-- MedaUI:CreateButton(parent, text, width, height)
-- MedaUI:CreateCheckbox(parent, label)
-- MedaUI:CreateRadio(parent, label)
-- MedaUI:CreateEditBox(parent, width, height)
-- MedaUI:CreateSlider(parent, width, min, max, step)
-- MedaUI:CreatePanel(name, width, height, title)
-- MedaUI:CreateMinimapButton(name, icon, onClick, onRightClick)

-- ============================================================================
-- Utility Functions
-- ============================================================================

--- Create a standard backdrop table for themed frames
--- @param hasEdge boolean Whether to include an edge/border
--- @return table Backdrop configuration table
function MedaUI:CreateBackdrop(hasEdge)
    local backdrop = {
        bgFile = "Interface\\Buttons\\WHITE8x8",
    }
    if hasEdge then
        backdrop.edgeFile = "Interface\\Buttons\\WHITE8x8"
        backdrop.edgeSize = 1
        backdrop.insets = { left = 1, right = 1, top = 1, bottom = 1 }
    end
    return backdrop
end

--- Apply theme colors to a backdrop frame
--- @param frame Frame The frame with BackdropTemplate
--- @param bgKey string|nil Background color key (default: "background")
--- @param borderKey string|nil Border color key (default: "border")
function MedaUI:ApplyBackdrop(frame, bgKey, borderKey)
    bgKey = bgKey or "background"
    borderKey = borderKey or "border"

    if self.Theme[bgKey] then
        frame:SetBackdropColor(unpack(self.Theme[bgKey]))
    end
    if self.Theme[borderKey] then
        frame:SetBackdropBorderColor(unpack(self.Theme[borderKey]))
    end
end
