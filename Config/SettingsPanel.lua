--[[
    MedaBinds - SettingsPanel.lua
    Main settings UI with tabs for global styles, configured icons, and options
]]

local addonName, MedaBinds = ...

-- SettingsPanel module
local SettingsPanel = {}
MedaBinds.SettingsPanel = SettingsPanel

-- UI Constants
local PANEL_WIDTH = 650
local PANEL_HEIGHT = 550
local TAB_HEIGHT = 32

-- Get MedaUI library for theming
local MedaUI = LibStub("MedaUI-1.0")

-- Theme Colors (from MedaUI shared library)
local THEME = MedaUI:GetTheme()

-- Available fonts (built-in WoW fonts + common addon fonts)
local BUILTIN_FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri", path = "Fonts\\SKURRI.TTF" },
    { name = "2002", path = "Fonts\\2002.TTF" },
    { name = "2002 Bold", path = "Fonts\\2002B.TTF" },
}


-- Get fonts including LibSharedMedia fonts if available
local function GetAvailableFonts()
    local fonts = {}
    local addedPaths = {}
    local addedNames = {}

    -- Helper to add a font if not already added
    local function AddFont(name, path)
        local pathKey = path:lower():gsub("\\", "/")
        local nameKey = name:lower()
        if not addedPaths[pathKey] and not addedNames[nameKey] then
            table.insert(fonts, { name = name, value = path })
            addedPaths[pathKey] = true
            addedNames[nameKey] = true
            return true
        end
        return false
    end

    -- Try to get fonts from LibSharedMedia first (most comprehensive)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local lsmFonts = LSM:HashTable("font")
        if lsmFonts then
            for name, path in pairs(lsmFonts) do
                AddFont(name, path)
            end
        end
    end

    -- Add built-in WoW fonts (if not already from LSM)
    for _, font in ipairs(BUILTIN_FONTS) do
        AddFont(font.name, font.path)
    end

    -- Sort alphabetically by name
    table.sort(fonts, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    return fonts
end

local FONTS = GetAvailableFonts()

-- Font flags
local FONT_FLAGS = {
    { name = "None", value = "" },
    { name = "Outline", value = "OUTLINE" },
    { name = "Thick Outline", value = "THICKOUTLINE" },
    { name = "Monochrome", value = "MONOCHROME" },
}

-- Anchor points
local ANCHOR_POINTS = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

-- Modifier keys
local MODIFIER_KEYS = {
    { name = "ALT", value = "ALT" },
    { name = "CTRL", value = "CTRL" },
    { name = "SHIFT", value = "SHIFT" },
}

-- Main panel frame
local panel = nil
local tabs = {}
local tabContents = {}
local currentTab = 1

-- Icon list scroll frame data
local iconListData = {}
local selectedIconSpellID = nil
local selectedExternalIconKey = nil

-- Forward declarations
local CreateGlobalStylesTab, CreateConfiguredIconsTab, CreateOptionsTab
local RefreshIconList, UpdateSelectedIcon

-- Create the main settings panel
local function CreatePanel()
    if panel then return panel end

    -- Main frame (custom dark theme, no template)
    panel = CreateFrame("Frame", "MedaBindsSettingsPanel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:Hide()

    -- Allow ESC to close the panel
    tinsert(UISpecialFrames, "MedaBindsSettingsPanel")

    -- Dark background with subtle border
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    panel:SetBackdropColor(unpack(THEME.background))
    panel:SetBackdropBorderColor(unpack(THEME.border))

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", 2, -2)
    titleBar:SetPoint("TOPRIGHT", -2, -2)
    titleBar:SetHeight(28)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    titleBar:SetBackdropColor(unpack(THEME.backgroundLight))

    -- Title icon
    local titleIcon = titleBar:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(20, 20)
    titleIcon:SetPoint("LEFT", 8, 0)
    titleIcon:SetTexture("Interface\\AddOns\\MedaBinds\\Media\\binding-chain")

    -- Title text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 6, 0)
    titleText:SetText("MedaBinds Settings")
    titleText:SetTextColor(unpack(THEME.gold))

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", -4, 0)
    closeBtn:SetNormalFontObject("GameFontNormal")
    closeBtn:SetText("x")
    closeBtn:GetFontString():SetTextColor(unpack(THEME.textDim))
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    closeBtn:SetScript("OnEnter", function(self) self:GetFontString():SetTextColor(unpack(THEME.closeHover)) end)
    closeBtn:SetScript("OnLeave", function(self) self:GetFontString():SetTextColor(unpack(THEME.textDim)) end)

    -- Content area
    local content = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    content:SetPoint("TOPLEFT", 1, -30)
    content:SetPoint("BOTTOMRIGHT", -1, 1)
    content:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    content:SetBackdropColor(unpack(THEME.backgroundDark))
    panel.Inset = content

    -- Tab buttons container
    local tabContainer = CreateFrame("Frame", nil, content)
    tabContainer:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -5)
    tabContainer:SetPoint("TOPRIGHT", content, "TOPRIGHT", -5, -5)
    tabContainer:SetHeight(TAB_HEIGHT)

    -- Create tabs
    local tabNames = { "Global Styles", "Configured Icons", "Options" }
    local tabWidth = (PANEL_WIDTH - 30) / #tabNames

    for i, name in ipairs(tabNames) do
        local tab = CreateFrame("Button", nil, tabContainer, "BackdropTemplate")
        tab:SetSize(tabWidth - 4, TAB_HEIGHT - 4)
        tab:SetPoint("TOPLEFT", tabContainer, "TOPLEFT", (i - 1) * tabWidth + 2, -2)

        tab:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        tab:SetBackdropColor(unpack(THEME.tabInactive))

        -- Text
        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tab.text:SetPoint("CENTER")
        tab.text:SetText(name)
        tab.text:SetTextColor(unpack(THEME.textDim))

        tab.index = i
        tab:SetScript("OnClick", function(self)
            SettingsPanel:SelectTab(self.index)
        end)
        tab:SetScript("OnEnter", function(self)
            if currentTab ~= self.index then
                self:SetBackdropColor(unpack(THEME.tabActive))
            end
        end)
        tab:SetScript("OnLeave", function(self)
            if currentTab ~= self.index then
                self:SetBackdropColor(unpack(THEME.tabInactive))
            end
        end)

        tabs[i] = tab
    end

    -- Tab content container
    local contentContainer = CreateFrame("Frame", nil, panel)
    contentContainer:SetPoint("TOPLEFT", tabContainer, "BOTTOMLEFT", 0, -5)
    contentContainer:SetPoint("BOTTOMRIGHT", panel.Inset, "BOTTOMRIGHT", -5, 5)
    panel.contentContainer = contentContainer

    -- Create tab content frames
    tabContents[1] = CreateGlobalStylesTab(contentContainer)
    tabContents[2] = CreateConfiguredIconsTab(contentContainer)
    tabContents[3] = CreateOptionsTab(contentContainer)

    -- Show first tab
    SettingsPanel:SelectTab(1)

    return panel
end

-- Select a tab
function SettingsPanel:SelectTab(index)
    currentTab = index

    -- Update tab appearance
    for i, tab in ipairs(tabs) do
        if i == index then
            tab:SetBackdropColor(unpack(THEME.tabActive))
            tab.text:SetTextColor(unpack(THEME.gold))
        else
            tab:SetBackdropColor(unpack(THEME.tabInactive))
            tab.text:SetTextColor(unpack(THEME.textDim))
        end
    end

    -- Show/hide content
    for i, content in ipairs(tabContents) do
        if i == index then
            content:Show()
        else
            content:Hide()
        end
    end

    -- Refresh data for the selected tab
    if index == 2 then
        RefreshIconList()
    end
end

-- Helper to create a fully custom themed scrollbar (no Blizzard textures)
local function CreateCustomScrollBar(parent, scrollFrame)
    local scrollBar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    scrollBar:SetWidth(8)
    scrollBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    scrollBar:SetBackdropColor(unpack(THEME.backgroundDark))

    -- Thumb (draggable part)
    local thumb = CreateFrame("Button", nil, scrollBar, "BackdropTemplate")
    thumb:SetSize(8, 40)
    thumb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    thumb:SetBackdropColor(unpack(THEME.textDim))
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")
    scrollBar.thumb = thumb

    -- Thumb hover/drag states
    thumb:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(THEME.gold))
    end)
    thumb:SetScript("OnLeave", function(self)
        if not self.isDragging then
            self:SetBackdropColor(unpack(THEME.textDim))
        end
    end)

    -- Dragging logic
    local dragStart, scrollStart
    thumb:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:SetBackdropColor(unpack(THEME.gold))
        local _, y = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        dragStart = y / scale
        scrollStart = scrollFrame:GetVerticalScroll()
    end)

    thumb:SetScript("OnDragStop", function(self)
        self.isDragging = false
        if not self:IsMouseOver() then
            self:SetBackdropColor(unpack(THEME.textDim))
        end
    end)

    thumb:SetScript("OnUpdate", function(self)
        if self.isDragging then
            local _, y = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local currentY = y / scale

            local trackHeight = scrollBar:GetHeight() - thumb:GetHeight()
            local scrollRange = scrollFrame:GetVerticalScrollRange()

            if trackHeight > 0 and scrollRange > 0 then
                local delta = dragStart - currentY
                local scrollDelta = (delta / trackHeight) * scrollRange
                local newScroll = math.max(0, math.min(scrollStart + scrollDelta, scrollRange))
                scrollFrame:SetVerticalScroll(newScroll)
            end
        end
    end)

    -- Click on track to jump
    scrollBar:EnableMouse(true)
    scrollBar:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local _, y = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local localY = y / scale - self:GetBottom()
            local trackHeight = self:GetHeight()
            local thumbHeight = thumb:GetHeight()

            local scrollRange = scrollFrame:GetVerticalScrollRange()
            local clickRatio = 1 - (localY / trackHeight)
            local newScroll = clickRatio * scrollRange
            scrollFrame:SetVerticalScroll(math.max(0, math.min(newScroll, scrollRange)))
        end
    end)

    -- Update thumb position based on scroll
    local function UpdateThumb()
        local scrollRange = scrollFrame:GetVerticalScrollRange()
        local trackHeight = scrollBar:GetHeight()

        if scrollRange > 0 then
            -- Calculate thumb size (proportional to visible area)
            local visibleRatio = scrollFrame:GetHeight() / (scrollFrame:GetHeight() + scrollRange)
            local thumbHeight = math.max(20, trackHeight * visibleRatio)
            thumb:SetHeight(thumbHeight)

            -- Calculate thumb position
            local scrollPos = scrollFrame:GetVerticalScroll()
            local scrollRatio = scrollPos / scrollRange
            local thumbTravel = trackHeight - thumbHeight
            local thumbOffset = scrollRatio * thumbTravel

            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", scrollBar, "TOP", 0, -thumbOffset)
            thumb:Show()
        else
            thumb:Hide()
        end
    end

    -- Hook scroll changes
    scrollFrame:HookScript("OnVerticalScroll", UpdateThumb)
    scrollFrame:HookScript("OnScrollRangeChanged", UpdateThumb)

    -- Initial update (delayed to ensure layout is complete)
    C_Timer.After(0.1, UpdateThumb)

    scrollBar.UpdateThumb = UpdateThumb
    return scrollBar
end

-- Helper to hide the default Blizzard scrollbar elements
local function HideDefaultScrollBar(scrollFrame)
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:Hide()
        scrollBar:SetAlpha(0)
        -- Disable it completely
        scrollBar:EnableMouse(false)
    end
end

-- Helper to create a fully themed scroll frame with custom scrollbar
local function CreateThemedScrollFrame(parent)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    container:SetBackdropColor(unpack(THEME.backgroundDark))
    container:SetBackdropBorderColor(unpack(THEME.border))

    -- Create scroll frame (use template for scroll functionality, but hide its scrollbar)
    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -16, 4)

    -- Hide the default scrollbar
    HideDefaultScrollBar(scrollFrame)

    -- Create scroll child
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Create custom themed scrollbar
    local customScrollBar = CreateCustomScrollBar(container, scrollFrame)
    customScrollBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -2, -2)
    customScrollBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -2, 2)

    container.scrollFrame = scrollFrame
    container.scrollChild = scrollChild
    container.scrollBar = customScrollBar

    return container
end

-- Style an existing scroll frame with custom scrollbar
local function StyleScrollFrame(scrollFrame, parent)
    -- Hide the default scrollbar
    HideDefaultScrollBar(scrollFrame)

    -- Create custom themed scrollbar
    local customScrollBar = CreateCustomScrollBar(parent, scrollFrame)
    return customScrollBar
end

-- Helper to create a themed slider (fully custom, no Blizzard template)
local function CreateSlider(parent, label, minVal, maxVal, step, getValue, setValue)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(200, 50)

    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOPLEFT")
    labelText:SetText(label)
    labelText:SetTextColor(unpack(THEME.text))

    -- Custom slider frame
    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -12)
    slider:SetSize(180, 8)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetOrientation("HORIZONTAL")
    slider:EnableMouse(true)

    -- Track background
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    slider:SetBackdropColor(unpack(THEME.backgroundDark))
    slider:SetBackdropBorderColor(unpack(THEME.border))

    -- Custom thumb texture
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(14, 14)
    thumb:SetColorTexture(unpack(THEME.gold))
    slider:SetThumbTexture(thumb)

    -- Thumb hover effect
    slider:SetScript("OnEnter", function(self)
        thumb:SetColorTexture(unpack(THEME.goldBright))
    end)
    slider:SetScript("OnLeave", function(self)
        thumb:SetColorTexture(unpack(THEME.gold))
    end)

    -- Min/max labels
    local lowText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
    lowText:SetText(minVal)
    lowText:SetTextColor(unpack(THEME.textDim))

    local highText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
    highText:SetText(maxVal)
    highText:SetTextColor(unpack(THEME.textDim))

    -- Value display
    local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, -2)
    valueText:SetTextColor(unpack(THEME.gold))

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        valueText:SetText(string.format("%.0f", value))
        setValue(value)
    end)

    container.slider = slider
    container.valueText = valueText
    container.Refresh = function()
        local value = getValue()
        slider:SetValue(value)
        valueText:SetText(string.format("%.0f", value))
    end

    return container
end

-- Helper to create a themed dropdown
local function CreateDropdown(parent, label, options, getValue, setValue)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(280, 55)

    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOPLEFT")
    labelText:SetText(label)
    labelText:SetTextColor(unpack(THEME.text))

    -- Custom dropdown button
    local dropBtn = CreateFrame("Button", nil, container, "BackdropTemplate")
    dropBtn:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -4)
    dropBtn:SetSize(250, 28)
    dropBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    dropBtn:SetBackdropColor(unpack(THEME.button))

    local selectedText = dropBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectedText:SetPoint("LEFT", 10, 0)
    selectedText:SetPoint("RIGHT", -28, 0)
    selectedText:SetJustifyH("LEFT")
    selectedText:SetTextColor(unpack(THEME.text))
    dropBtn.selectedText = selectedText

    -- Arrow area (subtle separator line)
    local arrowSeparator = dropBtn:CreateTexture(nil, "ARTWORK")
    arrowSeparator:SetSize(1, 18)
    arrowSeparator:SetPoint("RIGHT", -28, 0)
    arrowSeparator:SetColorTexture(unpack(THEME.border))

    -- Use Atlas texture for clean dropdown arrow (available in modern WoW)
    local arrowIcon = dropBtn:CreateTexture(nil, "OVERLAY")
    arrowIcon:SetSize(12, 12)
    arrowIcon:SetPoint("RIGHT", -8, 0)

    -- Try to use Atlas first, fall back to manual if not available
    local atlasSet = pcall(function()
        arrowIcon:SetAtlas("common-dropdown-icon")
    end)

    if not atlasSet or not arrowIcon:GetAtlas() then
        -- Fallback: Use expand arrow rotated, or create simple indicator
        arrowIcon:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        arrowIcon:SetRotation(math.rad(90))  -- Rotate to point down
    end

    arrowIcon:SetDesaturated(true)
    arrowIcon:SetVertexColor(unpack(THEME.textDim))

    -- Store references for hover effects
    local arrow = { icon = arrowIcon, separator = arrowSeparator }

    -- Dropdown menu frame (container for scroll)
    local menuFrame = CreateFrame("Frame", nil, dropBtn, "BackdropTemplate")
    menuFrame:SetPoint("TOPLEFT", dropBtn, "BOTTOMLEFT", 0, -1)
    menuFrame:SetSize(250, 10)
    menuFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menuFrame:SetBackdropColor(unpack(THEME.menuBackground))
    menuFrame:SetBackdropBorderColor(unpack(THEME.borderLight))
    menuFrame:SetFrameStrata("TOOLTIP")
    menuFrame:SetClampedToScreen(true)
    menuFrame:Hide()
    dropBtn.menuFrame = menuFrame

    -- Scroll frame inside menu
    local scrollFrame = CreateFrame("ScrollFrame", nil, menuFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -14, 2)

    -- Hide default scrollbar and create custom one
    HideDefaultScrollBar(scrollFrame)
    local customScrollBar = CreateCustomScrollBar(menuFrame, scrollFrame)
    customScrollBar:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -3, -3)
    customScrollBar:SetPoint("BOTTOMRIGHT", menuFrame, "BOTTOMRIGHT", -3, 3)

    -- Scroll child (content holder)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(220, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local menuItems = {}
    local currentOptions = options  -- Store reference to current options

    local function BuildMenu()
        -- Clear old items
        for _, item in ipairs(menuItems) do
            item:Hide()
            item:SetParent(nil)
        end
        wipe(menuItems)

        local maxHeight = 300
        local itemHeight = 22
        local yOff = 0
        local menuWidth = 220

        for i, option in ipairs(currentOptions) do
            local item = CreateFrame("Button", nil, scrollChild)
            item:SetSize(menuWidth, itemHeight)
            item:SetPoint("TOPLEFT", 0, yOff)

            local itemBg = item:CreateTexture(nil, "BACKGROUND")
            itemBg:SetAllPoints()
            itemBg:SetColorTexture(0, 0, 0, 0)
            item.bg = itemBg

            local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            itemText:SetPoint("LEFT", 8, 0)
            itemText:SetPoint("RIGHT", -8, 0)
            itemText:SetJustifyH("LEFT")
            itemText:SetText(option.name or option)
            itemText:SetTextColor(unpack(THEME.text))
            item.text = itemText

            -- Store option data on the item
            item.optionValue = option.value or option
            item.optionName = option.name or option

            item:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(unpack(THEME.highlight))
                self.text:SetTextColor(unpack(THEME.gold))
            end)
            item:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(0, 0, 0, 0)
                self.text:SetTextColor(unpack(THEME.text))
            end)
            item:SetScript("OnClick", function(self)
                setValue(self.optionValue)
                selectedText:SetText(self.optionName)
                menuFrame:Hide()
            end)

            menuItems[i] = item
            yOff = yOff - itemHeight
        end

        local totalContentHeight = math.abs(yOff)
        scrollChild:SetHeight(totalContentHeight)

        -- Set menu height (capped at maxHeight)
        local displayHeight = math.min(totalContentHeight + 4, maxHeight)
        menuFrame:SetHeight(displayHeight)

        -- Reset scroll position
        scrollFrame:SetVerticalScroll(0)
    end

    -- Enable mouse wheel scrolling on menu
    menuFrame:EnableMouseWheel(true)
    menuFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollFrame:GetVerticalScroll()
        local maxScroll = scrollChild:GetHeight() - scrollFrame:GetHeight()
        local newScroll = current - (delta * 22)  -- 22 = item height
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        scrollFrame:SetVerticalScroll(newScroll)
    end)

    dropBtn:SetScript("OnClick", function()
        if menuFrame:IsShown() then
            menuFrame:Hide()
        else
            BuildMenu()
            menuFrame:Show()
        end
    end)

    -- Use a global click detector to close dropdown
    local clickDetector = CreateFrame("Button", nil, menuFrame)
    clickDetector:SetAllPoints(UIParent)
    clickDetector:SetFrameStrata("FULLSCREEN_DIALOG")
    clickDetector:SetFrameLevel(menuFrame:GetFrameLevel() - 1)
    clickDetector:Hide()
    clickDetector:SetScript("OnClick", function()
        menuFrame:Hide()
        clickDetector:Hide()
    end)

    menuFrame:HookScript("OnShow", function()
        clickDetector:Show()
    end)
    menuFrame:HookScript("OnHide", function()
        clickDetector:Hide()
    end)

    dropBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(THEME.buttonHover))
        arrow.separator:SetColorTexture(unpack(THEME.borderLight))
        arrow.icon:SetVertexColor(unpack(THEME.gold))
    end)
    dropBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(THEME.button))
        arrow.separator:SetColorTexture(unpack(THEME.border))
        arrow.icon:SetVertexColor(unpack(THEME.textDim))
    end)

    container.dropdown = dropBtn
    container.options = currentOptions
    container.Refresh = function()
        local value = getValue()
        -- Normalize path for comparison (handle different slash styles and casing)
        local normalizedValue = value and value:lower():gsub("\\", "/") or ""
        for _, option in ipairs(currentOptions) do
            local optionValue = option.value or option
            local normalizedOption = optionValue and tostring(optionValue):lower():gsub("\\", "/") or ""
            if normalizedOption == normalizedValue or optionValue == value then
                selectedText:SetText(option.name or option)
                return
            end
        end
        -- If no match found, show the raw value
        selectedText:SetText(tostring(value) or "")
    end

    -- Allow updating options dynamically
    container.SetOptions = function(self, newOptions)
        currentOptions = newOptions
        self.options = newOptions
    end

    return container
end

-- Helper to create a themed checkbox (fully custom, no Blizzard template)
local function CreateCheckbox(parent, label, getValue, setValue)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(300, 26)

    -- Custom checkbox button
    local checkbox = CreateFrame("Button", nil, container, "BackdropTemplate")
    checkbox:SetPoint("LEFT", 0, 0)
    checkbox:SetSize(18, 18)
    checkbox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    checkbox:SetBackdropColor(unpack(THEME.backgroundDark))
    checkbox:SetBackdropBorderColor(unpack(THEME.border))

    -- Solid square indicator (matching radio button style)
    local checkmark = checkbox:CreateTexture(nil, "ARTWORK")
    checkmark:SetPoint("CENTER", 0, 0)
    checkmark:SetSize(10, 10)
    checkmark:SetTexture("Interface\\Buttons\\WHITE8x8")
    checkmark:SetVertexColor(unpack(THEME.gold))
    checkmark:Hide()
    checkbox.checkmark = checkmark

    -- State tracking
    checkbox.checked = false
    checkbox.GetChecked = function(self)
        return self.checked
    end
    checkbox.SetChecked = function(self, value)
        self.checked = value
        if value then
            checkmark:Show()
            self:SetBackdropBorderColor(unpack(THEME.gold))
        else
            checkmark:Hide()
            self:SetBackdropBorderColor(unpack(THEME.border))
        end
    end

    -- Label
    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
    labelText:SetText(label)
    labelText:SetTextColor(unpack(THEME.text))
    checkbox.text = labelText

    -- Hover effect
    checkbox:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(THEME.button))
        if not self.checked then
            self:SetBackdropBorderColor(unpack(THEME.goldDim))
        end
        labelText:SetTextColor(unpack(THEME.goldBright))
    end)
    checkbox:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(THEME.backgroundDark))
        if not self.checked then
            self:SetBackdropBorderColor(unpack(THEME.border))
        end
        labelText:SetTextColor(unpack(THEME.text))
    end)

    -- Click handler
    checkbox:SetScript("OnClick", function(self)
        local newValue = not self.checked
        self:SetChecked(newValue)
        setValue(newValue)
        PlaySound(newValue and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    -- Make the label clickable too
    local hitArea = CreateFrame("Button", nil, container)
    hitArea:SetPoint("TOPLEFT", checkbox, "TOPLEFT", 0, 0)
    hitArea:SetPoint("BOTTOMRIGHT", labelText, "BOTTOMRIGHT", 5, 0)
    hitArea:SetScript("OnClick", function()
        checkbox:Click()
    end)
    hitArea:SetScript("OnEnter", function()
        checkbox:GetScript("OnEnter")(checkbox)
    end)
    hitArea:SetScript("OnLeave", function()
        checkbox:GetScript("OnLeave")(checkbox)
    end)

    container.checkbox = checkbox
    container.text = labelText
    container.Refresh = function()
        local value = getValue()
        checkbox:SetChecked(value)
    end

    -- Initialize with current value
    local initialValue = getValue()
    if initialValue then
        checkbox:SetChecked(true)
    end

    return container
end

-- Helper to create a themed color picker button
local function CreateColorPicker(parent, label, getColor, setColor)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(200, 28)

    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("LEFT")
    labelText:SetText(label)
    labelText:SetTextColor(unpack(THEME.text))

    local button = CreateFrame("Button", nil, container, "BackdropTemplate")
    button:SetSize(26, 26)
    button:SetPoint("LEFT", labelText, "RIGHT", 10, 0)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    button:SetBackdropBorderColor(unpack(THEME.border))

    local function UpdateSwatch()
        local color = getColor()
        button:SetBackdropColor(color.r, color.g, color.b, color.a or 1)
    end

    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(THEME.gold))
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(THEME.border))
    end)

    button:SetScript("OnClick", function()
        local color = getColor()
        local function OnColorChanged()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = ColorPickerFrame:GetColorAlpha()
            setColor({ r = r, g = g, b = b, a = a })
            UpdateSwatch()
        end

        local function OnCancel()
            setColor(color)
            UpdateSwatch()
        end

        ColorPickerFrame:SetupColorPickerAndShow({
            r = color.r,
            g = color.g,
            b = color.b,
            opacity = color.a or 1,
            hasOpacity = true,
            swatchFunc = OnColorChanged,
            opacityFunc = OnColorChanged,
            cancelFunc = OnCancel,
        })
    end)

    container.button = button
    container.Refresh = function()
        UpdateSwatch()
    end

    UpdateSwatch()
    return container
end

-- Helper to create a themed button
local function CreateThemedButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 100, height or 26)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    btn:SetBackdropColor(unpack(THEME.button))

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER")
    btnText:SetText(text)
    btnText:SetTextColor(unpack(THEME.text))
    btn.text = btnText

    btn.isEnabled = true

    btn:SetScript("OnEnter", function(self)
        if self.isEnabled then
            self:SetBackdropColor(unpack(THEME.buttonHover))
            btnText:SetTextColor(unpack(THEME.gold))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if self.isEnabled then
            self:SetBackdropColor(unpack(THEME.button))
            btnText:SetTextColor(unpack(THEME.text))
        end
    end)

    -- Custom SetEnabled for themed buttons
    btn.SetEnabled = function(self, enabled)
        self.isEnabled = enabled
        if enabled then
            self:SetBackdropColor(unpack(THEME.button))
            btnText:SetTextColor(unpack(THEME.text))
            self:EnableMouse(true)
        else
            self:SetBackdropColor(unpack(THEME.buttonDisabled))
            btnText:SetTextColor(unpack(THEME.textDisabled))
            self:EnableMouse(false)
        end
    end

    return btn
end

-- Helper to create a themed edit box (fully custom, no Blizzard template)
local function CreateEditBox(parent, label, width, getValue, setValue)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width + 10, 40)

    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("TOPLEFT")
    labelText:SetText(label)
    labelText:SetTextColor(unpack(THEME.text))

    -- Custom edit box container for styling
    local editContainer = CreateFrame("Frame", nil, container, "BackdropTemplate")
    editContainer:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -4)
    editContainer:SetSize(width, 24)
    editContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    editContainer:SetBackdropColor(unpack(THEME.input))
    editContainer:SetBackdropBorderColor(unpack(THEME.border))

    -- The actual edit box
    local editBox = CreateFrame("EditBox", nil, editContainer)
    editBox:SetPoint("TOPLEFT", 6, -4)
    editBox:SetPoint("BOTTOMRIGHT", -6, 4)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetTextColor(unpack(THEME.text))
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetMultiLine(false)

    -- Focus styling
    editBox:SetScript("OnEditFocusGained", function(self)
        editContainer:SetBackdropBorderColor(unpack(THEME.gold))
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        editContainer:SetBackdropBorderColor(unpack(THEME.border))
    end)

    -- Hover effect on container
    editContainer:SetScript("OnEnter", function(self)
        if not editBox:HasFocus() then
            self:SetBackdropBorderColor(unpack(THEME.goldDim))
        end
    end)
    editContainer:SetScript("OnLeave", function(self)
        if not editBox:HasFocus() then
            self:SetBackdropBorderColor(unpack(THEME.border))
        end
    end)

    -- Click container to focus edit box
    editContainer:SetScript("OnMouseDown", function(self)
        editBox:SetFocus()
    end)

    editBox:SetScript("OnEnterPressed", function(self)
        setValue(self:GetText())
        self:ClearFocus()
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(getValue() or "")
        self:ClearFocus()
    end)

    container.editBox = editBox
    container.editContainer = editContainer
    container.Refresh = function()
        editBox:SetText(getValue() or "")
    end

    return container
end

-- Standalone themed edit box creator (for use in other modules)
function SettingsPanel:CreateThemedEditBox(parent, width, height)
    height = height or 24

    local editContainer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    editContainer:SetSize(width, height)
    editContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    editContainer:SetBackdropColor(unpack(THEME.input))
    editContainer:SetBackdropBorderColor(unpack(THEME.border))

    local editBox = CreateFrame("EditBox", nil, editContainer)
    editBox:SetPoint("TOPLEFT", 6, -4)
    editBox:SetPoint("BOTTOMRIGHT", -6, 4)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetTextColor(unpack(THEME.text))
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetMultiLine(false)

    editBox:SetScript("OnEditFocusGained", function(self)
        editContainer:SetBackdropBorderColor(unpack(THEME.gold))
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        editContainer:SetBackdropBorderColor(unpack(THEME.border))
    end)

    editContainer:SetScript("OnEnter", function(self)
        if not editBox:HasFocus() then
            self:SetBackdropBorderColor(unpack(THEME.goldDim))
        end
    end)
    editContainer:SetScript("OnLeave", function(self)
        if not editBox:HasFocus() then
            self:SetBackdropBorderColor(unpack(THEME.border))
        end
    end)

    editContainer:SetScript("OnMouseDown", function(self)
        editBox:SetFocus()
    end)

    editContainer.editBox = editBox
    return editContainer
end

-- Standalone themed checkbox creator (for use in other modules)
function SettingsPanel:CreateThemedCheckbox(parent, size)
    size = size or 18

    local checkbox = CreateFrame("Button", nil, parent, "BackdropTemplate")
    checkbox:SetSize(size, size)
    checkbox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    checkbox:SetBackdropColor(unpack(THEME.backgroundDark))
    checkbox:SetBackdropBorderColor(unpack(THEME.border))

    local checkmark = checkbox:CreateTexture(nil, "ARTWORK")
    checkmark:SetPoint("CENTER", 0, 0)
    checkmark:SetSize(size + 6, size + 6)
    checkmark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    checkmark:SetDesaturated(true)
    checkmark:SetVertexColor(unpack(THEME.gold))
    checkmark:Hide()
    checkbox.checkmark = checkmark

    checkbox.checked = false
    checkbox.GetChecked = function(self)
        return self.checked
    end
    checkbox.SetChecked = function(self, value)
        self.checked = value
        if value then
            checkmark:Show()
            self:SetBackdropBorderColor(unpack(THEME.gold))
        else
            checkmark:Hide()
            self:SetBackdropBorderColor(unpack(THEME.border))
        end
    end

    checkbox:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(THEME.button))
        if not self.checked then
            self:SetBackdropBorderColor(unpack(THEME.goldDim))
        end
    end)
    checkbox:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(THEME.backgroundDark))
        if not self.checked then
            self:SetBackdropBorderColor(unpack(THEME.border))
        end
    end)

    checkbox:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        PlaySound(self.checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)

    return checkbox
end

-- Standalone themed radio button creator (for use in other modules)
function SettingsPanel:CreateThemedRadioButton(parent, size)
    size = size or 18

    local radio = CreateFrame("Button", nil, parent, "BackdropTemplate")
    radio:SetSize(size, size)

    -- Circular appearance using rounded corner texture
    local bg = radio:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(unpack(THEME.backgroundDark))
    radio.bg = bg

    -- Border circle
    local border = radio:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetTexture("Interface\\Buttons\\WHITE8x8")
    border:SetVertexColor(unpack(THEME.border))
    radio.border = border

    -- Selected indicator (inner filled circle)
    local selected = radio:CreateTexture(nil, "ARTWORK")
    selected:SetPoint("CENTER")
    selected:SetSize(size - 8, size - 8)
    selected:SetTexture("Interface\\Buttons\\WHITE8x8")
    selected:SetVertexColor(unpack(THEME.gold))
    selected:Hide()
    radio.selected = selected

    radio.checked = false
    radio.GetChecked = function(self)
        return self.checked
    end
    radio.SetChecked = function(self, value)
        self.checked = value
        if value then
            selected:Show()
            border:SetVertexColor(unpack(THEME.gold))
        else
            selected:Hide()
            border:SetVertexColor(unpack(THEME.border))
        end
    end

    radio:SetScript("OnEnter", function(self)
        bg:SetVertexColor(unpack(THEME.button))
        if not self.checked then
            border:SetVertexColor(unpack(THEME.goldDim))
        end
    end)
    radio:SetScript("OnLeave", function(self)
        bg:SetVertexColor(unpack(THEME.backgroundDark))
        if not self.checked then
            border:SetVertexColor(unpack(THEME.border))
        end
    end)

    radio:SetScript("OnClick", function(self)
        self:SetChecked(true)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    return radio
end

-- Standalone themed slider creator (for use in other modules)
function SettingsPanel:CreateThemedSlider(parent, width, minVal, maxVal, step)
    width = width or 150
    step = step or 1

    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetSize(width, 8)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetOrientation("HORIZONTAL")
    slider:EnableMouse(true)

    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    slider:SetBackdropColor(unpack(THEME.backgroundDark))
    slider:SetBackdropBorderColor(unpack(THEME.border))

    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(14, 14)
    thumb:SetColorTexture(unpack(THEME.gold))
    slider:SetThumbTexture(thumb)
    slider.thumb = thumb

    slider:SetScript("OnEnter", function(self)
        thumb:SetColorTexture(unpack(THEME.goldBright))
    end)
    slider:SetScript("OnLeave", function(self)
        thumb:SetColorTexture(unpack(THEME.gold))
    end)

    return slider
end

-- Standalone themed color picker creator (for use in other modules)
function SettingsPanel:CreateThemedColorPicker(parent, size)
    size = size or 26

    local picker = CreateFrame("Button", nil, parent, "BackdropTemplate")
    picker:SetSize(size, size)
    picker:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    picker:SetBackdropColor(1, 1, 1, 1)
    picker:SetBackdropBorderColor(unpack(THEME.border))

    picker.color = { r = 1, g = 1, b = 1, a = 1 }

    picker.SetColor = function(self, color)
        self.color = color
        self:SetBackdropColor(color.r, color.g, color.b, color.a or 1)
    end

    picker.GetColor = function(self)
        return self.color
    end

    picker:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(THEME.gold))
    end)
    picker:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(THEME.border))
    end)

    picker:SetScript("OnClick", function(self)
        local function OnColorChanged()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = ColorPickerFrame:GetColorAlpha()
            self.color = { r = r, g = g, b = b, a = a }
            self:SetBackdropColor(r, g, b, a)
        end

        ColorPickerFrame:SetupColorPickerAndShow({
            r = self.color.r,
            g = self.color.g,
            b = self.color.b,
            opacity = self.color.a or 1,
            hasOpacity = true,
            swatchFunc = OnColorChanged,
            opacityFunc = OnColorChanged,
        })
    end)

    return picker
end

-- Create a custom scrollbar for an existing scroll frame (for use in other modules)
function SettingsPanel:CreateCustomScrollBar(parent, scrollFrame)
    HideDefaultScrollBar(scrollFrame)
    return CreateCustomScrollBar(parent, scrollFrame)
end

-- Create a themed scroll frame with custom scrollbar (for use in other modules)
function SettingsPanel:CreateThemedScrollFrame(parent, width, height)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if width and height then
        container:SetSize(width, height)
    end
    container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    container:SetBackdropColor(unpack(THEME.backgroundDark))
    container:SetBackdropBorderColor(unpack(THEME.border))

    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -16, 4)

    -- Hide default scrollbar
    HideDefaultScrollBar(scrollFrame)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(1)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Create custom themed scrollbar
    local customScrollBar = CreateCustomScrollBar(container, scrollFrame)
    customScrollBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -2, -2)
    customScrollBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -2, 2)

    container.scrollFrame = scrollFrame
    container.scrollChild = scrollChild
    container.scrollBar = customScrollBar

    return container
end

-- Get theme colors (for use in other modules)
function SettingsPanel:GetTheme()
    return MedaUI:GetTheme()
end

-- Create Global Styles tab content
CreateGlobalStylesTab = function(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:Hide()

    -- Helper to create section header
    local function CreateSectionHeader(parent, text, yPos, xPos)
        xPos = xPos or 10

        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", xPos, yPos)
        header:SetText(text)
        header:SetTextColor(unpack(THEME.gold))

        local line = parent:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
        line:SetSize(280, 1)
        line:SetColorTexture(unpack(THEME.border))

        return header, line
    end

    -- Layout constants
    local LEFT_COLUMN = 15
    local RIGHT_COLUMN = 320
    local COLUMN_WIDTH = 280

    -- ============================================
    -- LEFT COLUMN
    -- ============================================

    -- FONT SECTION
    local fontHeader = CreateSectionHeader(frame, "Font Settings", -10, LEFT_COLUMN)

    local fontDropdown = CreateDropdown(frame, "Font:", FONTS,
        function() return MedaBinds.db.globalStyle.font end,
        function(value)
            MedaBinds.db.globalStyle.font = value
            MedaBinds.OverlayManager:RefreshAllOverlays()
            if frame.UpdatePreview then frame.UpdatePreview() end
        end
    )
    fontDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -40)
    frame.fontDropdown = fontDropdown

    local sizeSlider = CreateSlider(frame, "Size:", 6, 24, 1,
        function() return MedaBinds.db.globalStyle.fontSize end,
        function(value)
            MedaBinds.db.globalStyle.fontSize = value
            MedaBinds.OverlayManager:RefreshAllOverlays()
            if frame.UpdatePreview then frame.UpdatePreview() end
        end
    )
    sizeSlider:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -100)
    frame.sizeSlider = sizeSlider

    local flagsDropdown = CreateDropdown(frame, "Outline:", FONT_FLAGS,
        function() return MedaBinds.db.globalStyle.fontFlags end,
        function(value)
            MedaBinds.db.globalStyle.fontFlags = value
            MedaBinds.OverlayManager:RefreshAllOverlays()
            if frame.UpdatePreview then frame.UpdatePreview() end
        end
    )
    flagsDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -155)
    frame.flagsDropdown = flagsDropdown

    -- POSITION SECTION
    local posHeader = CreateSectionHeader(frame, "Position", -225, LEFT_COLUMN)

    local anchorDropdown = CreateDropdown(frame, "Anchor:",
        (function()
            local opts = {}
            for _, pt in ipairs(ANCHOR_POINTS) do
                table.insert(opts, { name = pt, value = pt })
            end
            return opts
        end)(),
        function() return MedaBinds.db.globalStyle.anchor end,
        function(value)
            MedaBinds.db.globalStyle.anchor = value
            MedaBinds.db.globalStyle.anchorTo = value
            MedaBinds.OverlayManager:RefreshAllOverlays()
            if frame.UpdatePreview then frame.UpdatePreview() end
        end
    )
    anchorDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -255)
    frame.anchorDropdown = anchorDropdown

    local offsetXSlider = CreateSlider(frame, "Offset X:", -20, 20, 1,
        function() return MedaBinds.db.globalStyle.offsetX end,
        function(value)
            MedaBinds.db.globalStyle.offsetX = value
            MedaBinds.OverlayManager:RefreshAllOverlays()
            if frame.UpdatePreview then frame.UpdatePreview() end
        end
    )
    offsetXSlider:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -320)
    frame.offsetXSlider = offsetXSlider

    local offsetYSlider = CreateSlider(frame, "Offset Y:", -20, 20, 1,
        function() return MedaBinds.db.globalStyle.offsetY end,
        function(value)
            MedaBinds.db.globalStyle.offsetY = value
            MedaBinds.OverlayManager:RefreshAllOverlays()
            if frame.UpdatePreview then frame.UpdatePreview() end
        end
    )
    offsetYSlider:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -375)
    frame.offsetYSlider = offsetYSlider

    -- ============================================
    -- RIGHT COLUMN
    -- ============================================

    -- APPEARANCE SECTION
    local appearanceHeader = CreateSectionHeader(frame, "Appearance", -10, RIGHT_COLUMN)

    local colorPicker = CreateColorPicker(frame, "Text Color:",
        function() return MedaBinds.db.globalStyle.color end,
        function(value)
            MedaBinds.db.globalStyle.color = value
            MedaBinds.OverlayManager:RefreshAllOverlays()
            if frame.UpdatePreview then frame.UpdatePreview() end
        end
    )
    colorPicker:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN, -40)
    frame.colorPicker = colorPicker

    local shadowCheck = CreateCheckbox(frame, "Enable Text Shadow",
        function() return MedaBinds.db.globalStyle.shadowEnabled end,
        function(value)
            MedaBinds.db.globalStyle.shadowEnabled = value
            MedaBinds.OverlayManager:RefreshAllOverlays()
            if frame.UpdatePreview then frame.UpdatePreview() end
        end
    )
    shadowCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN, -75)
    frame.shadowCheck = shadowCheck

    -- PREVIEW SECTION
    local previewHeader = CreateSectionHeader(frame, "Preview", -120, RIGHT_COLUMN)

    local previewBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    previewBg:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN, -150)
    previewBg:SetSize(200, 80)
    previewBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    previewBg:SetBackdropColor(0.05, 0.05, 0.05, 1)
    previewBg:SetBackdropBorderColor(unpack(THEME.border))

    -- Sample icon background (use addon icon)
    local iconBg = previewBg:CreateTexture(nil, "ARTWORK")
    iconBg:SetSize(40, 40)
    iconBg:SetPoint("CENTER", previewBg, "CENTER", 0, 0)
    iconBg:SetTexture("Interface\\AddOns\\MedaBinds\\Media\\binding-chain")

    -- Preview keybind text
    local previewText = previewBg:CreateFontString(nil, "OVERLAY")
    previewText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")  -- Set default font first
    previewText:SetPoint("TOPRIGHT", iconBg, "TOPRIGHT", -2, -2)
    previewText:SetText("S1")
    frame.previewText = previewText

    -- Function to update preview
    local function UpdatePreview()
        local style = MedaBinds.db.globalStyle
        local fontPath = style.font or "Fonts\\FRIZQT__.TTF"
        local fontSize = style.fontSize or 12
        local fontFlags = style.fontFlags or "OUTLINE"

        previewText:SetFont(fontPath, fontSize, fontFlags)

        local color = style.color or { r = 1, g = 1, b = 1, a = 1 }
        previewText:SetTextColor(color.r, color.g, color.b, color.a or 1)

        if style.shadowEnabled then
            local shadowColor = style.shadowColor or { r = 0, g = 0, b = 0, a = 1 }
            local shadowOffset = style.shadowOffset or { x = 1, y = -1 }
            previewText:SetShadowColor(shadowColor.r, shadowColor.g, shadowColor.b, shadowColor.a or 1)
            previewText:SetShadowOffset(shadowOffset.x, shadowOffset.y)
        else
            previewText:SetShadowOffset(0, 0)
        end

        -- Update position based on anchor
        previewText:ClearAllPoints()
        local anchor = style.anchor or "TOPRIGHT"
        local offsetX = style.offsetX or -2
        local offsetY = style.offsetY or -2
        previewText:SetPoint(anchor, iconBg, anchor, offsetX, offsetY)
    end
    frame.UpdatePreview = UpdatePreview

    -- ============================================
    -- BOTTOM AREA
    -- ============================================

    -- Reset button
    local resetButton = CreateThemedButton(frame, "Reset Defaults", 120, 26)
    resetButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_COLUMN, 15)
    resetButton:SetScript("OnClick", function()
        MedaBinds.db.globalStyle = CopyTable(MedaBinds.DEFAULT_GLOBAL_STYLE or {
            font = "Fonts\\FRIZQT__.TTF",
            fontSize = 12,
            fontFlags = "OUTLINE",
            color = { r = 1, g = 1, b = 1, a = 1 },
            shadowEnabled = true,
            shadowColor = { r = 0, g = 0, b = 0, a = 1 },
            shadowOffset = { x = 1, y = -1 },
            anchor = "TOPRIGHT",
            anchorTo = "TOPRIGHT",
            offsetX = -2,
            offsetY = -2,
        })
        SettingsPanel:RefreshCurrentTab()
        MedaBinds.OverlayManager:RefreshAllOverlays()
        if frame.UpdatePreview then frame.UpdatePreview() end
    end)

    -- Apply to All button
    local applyAllButton = CreateThemedButton(frame, "Apply to All Icons", 140, 26)
    applyAllButton:SetPoint("LEFT", resetButton, "RIGHT", 10, 0)
    applyAllButton:SetScript("OnClick", function()
        -- Clear all per-spell style overrides, keep custom text
        for spellID, override in pairs(MedaBinds.db.spellOverrides) do
            if override.style then
                override.style = nil
            end
        end
        MedaBinds.OverlayManager:RefreshAllOverlays()
        print("|cFF00FF00MedaBinds:|r Global style applied to all icons.")
    end)

    frame.Refresh = function()
        fontDropdown.Refresh()
        sizeSlider.Refresh()
        flagsDropdown.Refresh()
        colorPicker.Refresh()
        shadowCheck.Refresh()
        anchorDropdown.Refresh()
        offsetXSlider.Refresh()
        offsetYSlider.Refresh()
        UpdatePreview()
    end

    -- Update preview when tab is shown
    frame:SetScript("OnShow", function()
        UpdatePreview()
    end)

    return frame
end

-- Create Configured Icons tab content
CreateConfiguredIconsTab = function(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    title:SetText("Configured Icons")
    title:SetTextColor(unpack(THEME.gold))

    -- Scan keybinds button
    local scanBtn = CreateThemedButton(frame, "Scan Keybinds", 110, 24)
    scanBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    scanBtn:SetScript("OnClick", function()
        if frame.scanStatus then
            frame.scanStatus:SetText("Scanning...")
            frame.scanStatus:SetTextColor(unpack(THEME.gold))
        end

        -- Use C_Timer to allow UI to update before scan
        C_Timer.After(0.01, function()
            local startTime = debugprofilestop()

            -- Perform the scan
            if MedaBinds.KeybindScanner then
                MedaBinds.KeybindScanner:ForceRescan()
            end

            local endTime = debugprofilestop()
            local elapsed = (endTime - startTime) / 1000  -- Convert to ms

            -- Get counts
            local spellCount = MedaBinds.KeybindScanner and MedaBinds.KeybindScanner:GetCacheCount() or 0
            local itemCount = MedaBinds.KeybindScanner and MedaBinds.KeybindScanner:GetItemCacheCount() or 0

            -- Update status
            if frame.scanStatus then
                frame.scanStatus:SetText(string.format("Found %d spells, %d items (%.1fms)", spellCount, itemCount, elapsed))
                frame.scanStatus:SetTextColor(unpack(THEME.textGreen))
            end

            -- Refresh the icon list
            RefreshIconList()
        end)
    end)
    frame.scanBtn = scanBtn

    -- Config mode button
    local configModeBtn = CreateThemedButton(frame, "Enter Config Mode", 140, 24)
    configModeBtn:SetPoint("RIGHT", scanBtn, "LEFT", -8, 0)
    configModeBtn:SetScript("OnClick", function()
        if MedaBinds.ConfigMode then
            MedaBinds.ConfigMode:Toggle()
        end
    end)

    -- Scroll frame for icon list
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -45)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 80)

    -- Hide default scrollbar
    HideDefaultScrollBar(scrollFrame)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(PANEL_WIDTH - 60, 1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild
    frame.scrollFrame = scrollFrame

    -- Create custom themed scrollbar
    local customScrollBar = CreateCustomScrollBar(frame, scrollFrame)
    customScrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, 0)
    customScrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 0)
    frame.customScrollBar = customScrollBar

    -- Info text
    local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 55)
    infoText:SetText("[Auto] = Detected from action bars  |  [Custom] = User-defined override")
    infoText:SetTextColor(unpack(THEME.textDim))

    -- Scan status text (shows results) - positioned at bottom right
    local scanStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scanStatus:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 55)
    scanStatus:SetJustifyH("RIGHT")
    scanStatus:SetText("")
    scanStatus:SetTextColor(unpack(THEME.textDim))
    frame.scanStatus = scanStatus

    -- Selected icon display
    local selectedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectedLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 35)
    selectedLabel:SetText("Selected: None")
    frame.selectedLabel = selectedLabel

    -- Edit button
    local editBtn = CreateThemedButton(frame, "Edit", 80, 22)
    editBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    editBtn:SetEnabled(false)  -- Disabled until icon selected
    editBtn:SetScript("OnClick", function()
        if selectedIconSpellID and MedaBinds.ConfigMode then
            MedaBinds.ConfigMode:OpenEditor(selectedIconSpellID)
        end
    end)
    frame.editBtn = editBtn

    -- Clear custom button
    local clearBtn = CreateThemedButton(frame, "Clear Custom", 130, 22)
    clearBtn:SetPoint("LEFT", editBtn, "RIGHT", 5, 0)
    clearBtn:SetEnabled(false)  -- Disabled until icon selected
    clearBtn:SetScript("OnClick", function()
        if selectedIconSpellID then
            local override = MedaBinds.db.spellOverrides[selectedIconSpellID]
            if override then
                override.text = nil
                override.useAuto = true
            end
            MedaBinds.OverlayManager:RefreshSpellOverlay(selectedIconSpellID)
            RefreshIconList()
        end
    end)
    frame.clearBtn = clearBtn

    -- External icon buttons (right side)
    local editExternalBtn = CreateThemedButton(frame, "Edit External", 110, 22)
    editExternalBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -130, 10)
    editExternalBtn:SetEnabled(false)
    editExternalBtn:SetScript("OnClick", function()
        if selectedExternalIconKey and MedaBinds.ConfigMode then
            MedaBinds.ConfigMode:OpenExternalEditor(selectedExternalIconKey)
        end
    end)
    frame.editExternalBtn = editExternalBtn

    local removeExternalBtn = CreateThemedButton(frame, "Remove External", 115, 22)
    removeExternalBtn:SetPoint("LEFT", editExternalBtn, "RIGHT", 5, 0)
    removeExternalBtn:SetEnabled(false)
    removeExternalBtn:SetScript("OnClick", function()
        if selectedExternalIconKey then
            MedaBinds.OverlayManager:RemoveExternalIcon(selectedExternalIconKey)
            selectedExternalIconKey = nil
            UpdateSelectedIcon()
            RefreshIconList()
        end
    end)
    frame.removeExternalBtn = removeExternalBtn

    frame.Refresh = function()
        RefreshIconList()
        -- Update scan status with current counts
        if frame.scanStatus then
            local spellCount = MedaBinds.KeybindScanner and MedaBinds.KeybindScanner:GetCacheCount() or 0
            local itemCount = MedaBinds.KeybindScanner and MedaBinds.KeybindScanner:GetItemCacheCount() or 0
            if spellCount > 0 or itemCount > 0 then
                frame.scanStatus:SetText(string.format("Cached: %d spells, %d items", spellCount, itemCount))
                frame.scanStatus:SetTextColor(unpack(THEME.textDim))
            end
        end
    end

    return frame
end

-- Refresh the icon list (grouped by viewer)
RefreshIconList = function()
    local scrollChild = tabContents[2] and tabContents[2].scrollChild
    if not scrollChild then return end

    -- Clear existing entries
    for _, child in ipairs({scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    -- Build list from current overlays and overrides, grouped by viewer
    local viewerGroups = {}
    wipe(iconListData)

    -- Add spells from overlays
    if MedaBinds.OverlayManager then
        local viewerNames = MedaBinds.OverlayManager:GetViewerFrameNames()
        for key, viewerName in pairs(viewerNames) do
            local viewerFrame = _G[viewerName]
            if viewerFrame then
                local displayName = viewerName:gsub("CooldownViewer", "")
                if not viewerGroups[displayName] then
                    viewerGroups[displayName] = {}
                end

                local children = { viewerFrame:GetChildren() }
                for _, child in ipairs(children) do
                    local spellInfo = MedaBinds.OverlayManager:GetSpellInfoFromIcon(child)
                    if spellInfo and not iconListData[spellInfo.spellID] then
                        local keybindText, source = MedaBinds:GetKeybindText(spellInfo.spellID)
                        local data = {
                            spellID = spellInfo.spellID,
                            name = spellInfo.name,
                            keybind = keybindText or "—",
                            source = source or "none",
                            viewerName = displayName,
                        }
                        iconListData[spellInfo.spellID] = data
                        table.insert(viewerGroups[displayName], data)
                    end
                end
            end
        end
    end

    -- Add spells from overrides to their own group
    local hasOverrides = false
    for spellID, override in pairs(MedaBinds.db.spellOverrides) do
        if not iconListData[spellID] then
            hasOverrides = true
            if not viewerGroups["Custom Overrides"] then
                viewerGroups["Custom Overrides"] = {}
            end
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            local keybindText, source = MedaBinds:GetKeybindText(spellID)
            local data = {
                spellID = spellID,
                name = spellInfo and spellInfo.name or "Unknown",
                keybind = keybindText or "—",
                source = source or "custom",
                viewerName = "Custom",
            }
            iconListData[spellID] = data
            table.insert(viewerGroups["Custom Overrides"], data)
        end
    end

    -- Define viewer display order
    local viewerOrder = { "Essential", "Utility", "BuffIcon", "BuffBar", "Custom Overrides" }

    -- Create list entries
    local yOffset = 0
    local entryHeight = 22
    local headerHeight = 26
    local rowIndex = 0

    for _, viewerDisplayName in ipairs(viewerOrder) do
        local entries = viewerGroups[viewerDisplayName]
        if entries and #entries > 0 then
            -- Sort entries by spell name
            table.sort(entries, function(a, b) return (a.name or "") < (b.name or "") end)

            -- Group header
            local groupHeader = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
            groupHeader:SetSize(PANEL_WIDTH - 60, headerHeight)
            groupHeader:SetPoint("TOPLEFT", 0, yOffset)
            groupHeader:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
            })
            groupHeader:SetBackdropColor(unpack(THEME.rowHeader))

            local headerText = groupHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headerText:SetPoint("LEFT", 8, 0)
            headerText:SetText(viewerDisplayName .. " (" .. #entries .. ")")
            headerText:SetTextColor(unpack(THEME.gold))

            yOffset = yOffset - headerHeight

            -- Column headers
            local colHeader = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
            colHeader:SetSize(PANEL_WIDTH - 60, 18)
            colHeader:SetPoint("TOPLEFT", 0, yOffset)
            colHeader:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
            })
            colHeader:SetBackdropColor(unpack(THEME.rowSubheader))

            local colWidths = { 260, 120, 160 }
            local colLabels = { "Spell", "Keybind", "Source" }
            local xPos = 10

            for i, label in ipairs(colLabels) do
                local text = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                text:SetPoint("LEFT", xPos, 0)
                text:SetText(label)
                text:SetTextColor(unpack(THEME.goldDim))
                xPos = xPos + colWidths[i]
            end

            yOffset = yOffset - 18

            -- Rows for this group
            for _, data in ipairs(entries) do
                rowIndex = rowIndex + 1
                local currentRowIndex = rowIndex
                local row = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
                row:SetSize(PANEL_WIDTH - 60, entryHeight)
                row:SetPoint("TOPLEFT", 0, yOffset)
                row.spellID = data.spellID

                row:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8x8",
                })
                if currentRowIndex % 2 == 0 then
                    row:SetBackdropColor(unpack(THEME.rowEven))
                else
                    row:SetBackdropColor(unpack(THEME.rowOdd))
                end

                row:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(unpack(THEME.highlight))
                end)
                row:SetScript("OnLeave", function(self)
                    if currentRowIndex % 2 == 0 then
                        self:SetBackdropColor(unpack(THEME.rowEven))
                    else
                        self:SetBackdropColor(unpack(THEME.rowOdd))
                    end
                end)

                xPos = 10
                local texts = { data.name, data.keybind, "[" .. data.source .. "]" }
                local colors = {
                    THEME.text,
                    THEME.textGreen,
                    data.source == "custom" and THEME.gold or THEME.textDim,
                }

                for i, text in ipairs(texts) do
                    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    fs:SetPoint("LEFT", xPos, 0)
                    fs:SetWidth(colWidths[i] - 5)
                    fs:SetJustifyH("LEFT")
                    fs:SetText(text or "")
                    fs:SetTextColor(unpack(colors[i]))
                    xPos = xPos + colWidths[i]
                end

                row:SetScript("OnClick", function(self)
                    selectedIconSpellID = self.spellID
                    selectedExternalIconKey = nil  -- Clear external selection
                    UpdateSelectedIcon()
                    -- Open the editor for this spell
                    if MedaBinds.ConfigMode then
                        MedaBinds.ConfigMode:OpenEditor(self.spellID)
                    end
                end)

                yOffset = yOffset - entryHeight
            end

            yOffset = yOffset - 8  -- Gap between groups
        end
    end

    -- ============================================
    -- EXTERNAL ICONS SECTION
    -- ============================================
    local externalIcons = MedaBinds.OverlayManager and MedaBinds.OverlayManager:GetExternalIcons() or {}
    local externalCount = 0
    for _ in pairs(externalIcons) do
        externalCount = externalCount + 1
    end

    if externalCount > 0 then
        -- Group header for external icons
        local groupHeader = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        groupHeader:SetSize(PANEL_WIDTH - 60, headerHeight)
        groupHeader:SetPoint("TOPLEFT", 0, yOffset)
        groupHeader:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        groupHeader:SetBackdropColor(unpack(THEME.rowHeader))

        local headerText = groupHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        headerText:SetPoint("LEFT", 8, 0)
        headerText:SetText("External Icons (" .. externalCount .. ")")
        headerText:SetTextColor(unpack(THEME.gold))

        yOffset = yOffset - headerHeight

        -- Column headers for external icons
        local colHeader = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        colHeader:SetSize(PANEL_WIDTH - 60, 18)
        colHeader:SetPoint("TOPLEFT", 0, yOffset)
        colHeader:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        colHeader:SetBackdropColor(unpack(THEME.rowSubheader))

        local extColWidths = { 240, 180, 120 }
        local extColLabels = { "Frame Name", "Text", "Status" }
        local xPos = 10

        for i, label in ipairs(extColLabels) do
            local text = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", xPos, 0)
            text:SetText(label)
            text:SetTextColor(unpack(THEME.goldDim))
            xPos = xPos + extColWidths[i]
        end

        yOffset = yOffset - 18

        -- Sort external icons by frame name
        local sortedExternal = {}
        for uniqueKey, entry in pairs(externalIcons) do
            table.insert(sortedExternal, { key = uniqueKey, entry = entry })
        end
        table.sort(sortedExternal, function(a, b)
            return (a.entry.frameName or "") < (b.entry.frameName or "")
        end)

        -- Rows for external icons
        for _, item in ipairs(sortedExternal) do
            local uniqueKey = item.key
            local entry = item.entry
            rowIndex = rowIndex + 1
            local currentRowIndex = rowIndex

            local row = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
            row:SetSize(PANEL_WIDTH - 60, entryHeight)
            row:SetPoint("TOPLEFT", 0, yOffset)
            row.externalKey = uniqueKey

            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
            })
            if currentRowIndex % 2 == 0 then
                row:SetBackdropColor(unpack(THEME.rowEven))
            else
                row:SetBackdropColor(unpack(THEME.rowOdd))
            end

            row:SetScript("OnEnter", function(self)
                self:SetBackdropColor(unpack(THEME.highlight))
            end)
            row:SetScript("OnLeave", function(self)
                if currentRowIndex % 2 == 0 then
                    self:SetBackdropColor(unpack(THEME.rowEven))
                else
                    self:SetBackdropColor(unpack(THEME.rowOdd))
                end
            end)

            -- Determine display text and status
            local displayName = entry.frameName or "Unknown"
            local displayText = entry.text or "—"
            local status = entry.enabled ~= false and "Active" or "Disabled"
            if entry.useAuto then
                status = status .. " (Auto)"
            end

            xPos = 10
            local texts = { displayName, displayText, status }
            local colors = {
                THEME.text,
                entry.text and THEME.textGreen or THEME.textDim,
                entry.enabled ~= false and THEME.textGreen or THEME.textDim,
            }

            for i, text in ipairs(texts) do
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetPoint("LEFT", xPos, 0)
                fs:SetWidth(extColWidths[i] - 5)
                fs:SetJustifyH("LEFT")
                fs:SetText(text or "")
                fs:SetTextColor(unpack(colors[i]))
                xPos = xPos + extColWidths[i]
            end

            row:SetScript("OnClick", function(self)
                selectedExternalIconKey = self.externalKey
                selectedIconSpellID = nil  -- Clear spell selection
                UpdateSelectedIcon()
            end)

            yOffset = yOffset - entryHeight
        end

        yOffset = yOffset - 8  -- Gap after external icons
    end

    scrollChild:SetHeight(math.abs(yOffset) + 10)
end

-- Update selected icon UI
UpdateSelectedIcon = function()
    local frame = tabContents[2]
    if not frame then return end

    if selectedIconSpellID then
        -- Spell icon selected
        local data = iconListData[selectedIconSpellID]
        if data then
            frame.selectedLabel:SetText("Selected: " .. (data.name or "Unknown"))
        else
            frame.selectedLabel:SetText("Selected: SpellID " .. selectedIconSpellID)
        end
        frame.editBtn:SetEnabled(true)
        frame.clearBtn:SetEnabled(true)
        frame.editExternalBtn:SetEnabled(false)
        frame.removeExternalBtn:SetEnabled(false)
    elseif selectedExternalIconKey then
        -- External icon selected
        local externalIcons = MedaBinds.OverlayManager and MedaBinds.OverlayManager:GetExternalIcons() or {}
        local entry = externalIcons[selectedExternalIconKey]
        if entry then
            frame.selectedLabel:SetText("Selected: " .. (entry.frameName or "External Icon"))
        else
            frame.selectedLabel:SetText("Selected: External Icon")
        end
        frame.editBtn:SetEnabled(false)
        frame.clearBtn:SetEnabled(false)
        frame.editExternalBtn:SetEnabled(true)
        frame.removeExternalBtn:SetEnabled(true)
    else
        -- Nothing selected
        frame.selectedLabel:SetText("Selected: None")
        frame.editBtn:SetEnabled(false)
        frame.clearBtn:SetEnabled(false)
        frame.editExternalBtn:SetEnabled(false)
        frame.removeExternalBtn:SetEnabled(false)
    end
end

-- Create Options tab content
CreateOptionsTab = function(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:Hide()

    local yOffset = -10

    -- Cooldown Viewers section
    local viewerTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    viewerTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
    viewerTitle:SetText("Cooldown Viewers")
    viewerTitle:SetTextColor(unpack(THEME.gold))
    yOffset = yOffset - 25

    local essentialCheck = CreateCheckbox(frame, "Show keybinds on Essential Cooldowns",
        function() return MedaBinds.db.options.showOnEssential end,
        function(value)
            MedaBinds.db.options.showOnEssential = value
            MedaBinds.OverlayManager:RefreshAllOverlays()
        end
    )
    essentialCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
    frame.essentialCheck = essentialCheck
    yOffset = yOffset - 25

    local utilityCheck = CreateCheckbox(frame, "Show keybinds on Utility Cooldowns",
        function() return MedaBinds.db.options.showOnUtility end,
        function(value)
            MedaBinds.db.options.showOnUtility = value
            MedaBinds.OverlayManager:RefreshAllOverlays()
        end
    )
    utilityCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
    frame.utilityCheck = utilityCheck
    yOffset = yOffset - 25

    local buffIconCheck = CreateCheckbox(frame, "Show keybinds on Buff Icons",
        function() return MedaBinds.db.options.showOnBuffIcons end,
        function(value)
            MedaBinds.db.options.showOnBuffIcons = value
            MedaBinds.OverlayManager:RefreshAllOverlays()
        end
    )
    buffIconCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
    frame.buffIconCheck = buffIconCheck
    yOffset = yOffset - 40

    -- Auto-Detection section
    local autoTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    autoTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
    autoTitle:SetText("Auto-Detection")
    autoTitle:SetTextColor(unpack(THEME.gold))
    yOffset = yOffset - 25

    local enableAutoCheck = CreateCheckbox(frame, "Enable auto-detection from action bars",
        function() return MedaBinds.db.options.enableAutoDetection end,
        function(value)
            MedaBinds.db.options.enableAutoDetection = value
            MedaBinds.OverlayManager:RefreshAllOverlays()
        end
    )
    enableAutoCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
    frame.enableAutoCheck = enableAutoCheck
    yOffset = yOffset - 25

    local abbreviateCheck = CreateCheckbox(frame, "Abbreviate keybinds (SHIFT-1 -> S1)",
        function() return MedaBinds.db.options.abbreviateKeybinds end,
        function(value)
            MedaBinds.db.options.abbreviateKeybinds = value
            MedaBinds.KeybindScanner:ForceRescan()
        end
    )
    abbreviateCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
    frame.abbreviateCheck = abbreviateCheck
    yOffset = yOffset - 25

    local scanHiddenCheck = CreateCheckbox(frame, "Include hidden action bars (6-8)",
        function() return MedaBinds.db.options.scanHiddenBars end,
        function(value)
            MedaBinds.db.options.scanHiddenBars = value
            MedaBinds.KeybindScanner:ForceRescan()
        end
    )
    scanHiddenCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
    frame.scanHiddenCheck = scanHiddenCheck
    yOffset = yOffset - 25

    local scanMacrosCheck = CreateCheckbox(frame, "Scan macros for spell keybinds",
        function() return MedaBinds.db.options.scanMacros end,
        function(value)
            MedaBinds.db.options.scanMacros = value
            MedaBinds.KeybindScanner:ForceRescan()
        end
    )
    scanMacrosCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
    frame.scanMacrosCheck = scanMacrosCheck
    yOffset = yOffset - 40

    -- Config Mode section
    local configTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    configTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
    configTitle:SetText("Config Mode")
    configTitle:SetTextColor(unpack(THEME.gold))
    yOffset = yOffset - 25

    local modifierDropdown = CreateDropdown(frame, "Modifier Key:", MODIFIER_KEYS,
        function() return MedaBinds.db.options.configModifierKey end,
        function(value)
            MedaBinds.db.options.configModifierKey = value
        end
    )
    modifierDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
    frame.modifierDropdown = modifierDropdown
    yOffset = yOffset - 55

    local combatDisableCheck = CreateCheckbox(frame, "Auto-disable config mode in combat",
        function() return MedaBinds.db.options.autoDisableInCombat end,
        function(value)
            MedaBinds.db.options.autoDisableInCombat = value
        end
    )
    combatDisableCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
    frame.combatDisableCheck = combatDisableCheck
    yOffset = yOffset - 40

    -- Interface section
    local interfaceTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    interfaceTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
    interfaceTitle:SetText("Interface")
    interfaceTitle:SetTextColor(unpack(THEME.gold))
    yOffset = yOffset - 25

    local minimapCheck = CreateCheckbox(frame, "Show minimap button",
        function() return MedaBinds.db.options.showMinimapButton end,
        function(value)
            MedaBinds.db.options.showMinimapButton = value
            MedaBinds:SetMinimapButtonShown(value)
        end
    )
    minimapCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
    frame.minimapCheck = minimapCheck

    frame.Refresh = function()
        essentialCheck.Refresh()
        utilityCheck.Refresh()
        buffIconCheck.Refresh()
        enableAutoCheck.Refresh()
        abbreviateCheck.Refresh()
        scanHiddenCheck.Refresh()
        scanMacrosCheck.Refresh()
        modifierDropdown.Refresh()
        combatDisableCheck.Refresh()
        minimapCheck.Refresh()
    end

    return frame
end

-- Refresh current tab
function SettingsPanel:RefreshCurrentTab()
    local content = tabContents[currentTab]
    if content and content.Refresh then
        content.Refresh()
    end
end

-- Show the settings panel
function SettingsPanel:Show()
    -- Refresh fonts list (picks up LSM fonts loaded after init)
    FONTS = GetAvailableFonts()

    local p = CreatePanel()

    -- Update font dropdown with refreshed fonts list
    local globalStylesTab = tabContents[1]
    if globalStylesTab and globalStylesTab.fontDropdown then
        globalStylesTab.fontDropdown:SetOptions(FONTS)
    end

    self:RefreshCurrentTab()
    p:Show()
end

-- Hide the settings panel
function SettingsPanel:Hide()
    if panel then
        panel:Hide()
    end
end

-- Toggle the settings panel
function SettingsPanel:Toggle()
    if panel and panel:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Check if panel is shown
function SettingsPanel:IsShown()
    return panel and panel:IsShown()
end
