--[[
    MedaBinds - SettingsPanel.lua
    Main settings UI with tabs for global styles, configured icons, and options
    Refactored to use MedaUI widget library
]]

local addonName, MedaBinds = ...

-- SettingsPanel module
local SettingsPanel = {}
MedaBinds.SettingsPanel = SettingsPanel

-- UI Constants
local PANEL_WIDTH = 650
local PANEL_HEIGHT = 550

-- Get MedaUI library
local MedaUI = LibStub("MedaUI-1.0")

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
            table.insert(fonts, { label = name, value = path })
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
        return a.label:lower() < b.label:lower()
    end)

    return fonts
end

local FONTS = GetAvailableFonts()

-- Font flags options for dropdown (MedaUI format)
local FONT_FLAGS = {
    { label = "None", value = "" },
    { label = "Outline", value = "OUTLINE" },
    { label = "Thick Outline", value = "THICKOUTLINE" },
    { label = "Monochrome", value = "MONOCHROME" },
}

-- Anchor points
local ANCHOR_POINTS = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

-- Modifier keys for dropdown (MedaUI format)
local MODIFIER_KEYS = {
    { label = "ALT", value = "ALT" },
    { label = "CTRL", value = "CTRL" },
    { label = "SHIFT", value = "SHIFT" },
}

-- Main panel frame
local panel = nil
local tabBar = nil
local tabContents = {}
local currentTab = "globalStyles"

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

    -- Create main panel using MedaUI
    panel = MedaUI:CreatePanel("MedaBindsSettingsPanel", PANEL_WIDTH, PANEL_HEIGHT, "MedaBinds Settings")

    -- Add custom title icon before the title text
    local titleIcon = panel.titleBar:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(20, 20)
    titleIcon:SetPoint("LEFT", 8, 0)
    titleIcon:SetTexture("Interface\\AddOns\\MedaBinds\\Media\\binding-chain")

    -- Adjust title text position to be after the icon
    if panel.titleText then
        panel.titleText:ClearAllPoints()
        panel.titleText:SetPoint("LEFT", titleIcon, "RIGHT", 6, 0)
    end

    -- Enable resizing with min bounds
    panel:SetResizable(true, {
        minWidth = 550,
        minHeight = 450,
    })

    -- Add addon icon watermark
    panel:SetAddonIcon("Interface\\AddOns\\MedaBinds\\Media\\binding-chain")

    -- Allow ESC to close the panel
    tinsert(UISpecialFrames, "MedaBindsSettingsPanel")

    -- Content area (get the panel's content area)
    local content = panel:GetContent()

    -- Create tab bar using MedaUI
    tabBar = MedaUI:CreateTabBar(content, {
        { id = "globalStyles", label = "Global Styles" },
        { id = "configuredIcons", label = "Configured Icons" },
        { id = "options", label = "Options" },
    })
    tabBar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)

    -- Tab content container
    local contentContainer = CreateFrame("Frame", nil, content)
    contentContainer:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -5)
    contentContainer:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    panel.contentContainer = contentContainer

    -- Create tab content frames
    tabContents.globalStyles = CreateGlobalStylesTab(contentContainer)
    tabContents.configuredIcons = CreateConfiguredIconsTab(contentContainer)
    tabContents.options = CreateOptionsTab(contentContainer)

    -- Tab changed handler
    tabBar.OnTabChanged = function(_, tabId, previousTabId)
        currentTab = tabId

        -- Show/hide content
        for id, contentFrame in pairs(tabContents) do
            if id == tabId then
                contentFrame:Show()
            else
                contentFrame:Hide()
            end
        end

        -- Refresh data for the selected tab
        local contentFrame = tabContents[tabId]
        if contentFrame and contentFrame.Refresh then
            contentFrame.Refresh()
        end
    end

    -- Show first tab (TabBar auto-selects first tab before OnTabChanged is set,
    -- so we need to manually show the content and call refresh)
    currentTab = "globalStyles"
    tabContents.globalStyles:Show()
    if tabContents.globalStyles.Refresh then
        tabContents.globalStyles.Refresh()
    end

    return panel
end

-- Select a tab
function SettingsPanel:SelectTab(tabId)
    if tabBar then
        tabBar:SetActiveTab(tabId)
    end
end

-- Create Global Styles tab content
CreateGlobalStylesTab = function(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:Hide()

    -- Layout constants
    local LEFT_COLUMN = 15
    local RIGHT_COLUMN = 320
    local COLUMN_WIDTH = 280

    -- ============================================
    -- LEFT COLUMN
    -- ============================================

    -- FONT SECTION
    local fontHeader, fontLine = MedaUI:CreateSectionHeader(frame, "Font Settings", COLUMN_WIDTH)
    fontHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -10)

    -- Font dropdown
    local fontLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -40)
    fontLabel:SetText("Font:")
    fontLabel:SetTextColor(unpack(MedaUI.Theme.text))

    local fontDropdown = MedaUI:CreateDropdown(frame, 250, FONTS)
    fontDropdown:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -4)
    fontDropdown.OnValueChanged = function(_, value)
        MedaBinds.db.globalStyle.font = value
        MedaBinds.OverlayManager:RefreshAllOverlays()
        if frame.UpdatePreview then frame.UpdatePreview() end
    end
    frame.fontDropdown = fontDropdown

    -- Size slider
    local sizeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -100)
    sizeLabel:SetText("Size:")
    sizeLabel:SetTextColor(unpack(MedaUI.Theme.text))

    local sizeSlider = MedaUI:CreateSlider(frame, 200, 6, 24, 1)
    sizeSlider:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -12)
    sizeSlider.OnValueChanged = function(_, value)
        MedaBinds.db.globalStyle.fontSize = value
        MedaBinds.OverlayManager:RefreshAllOverlays()
        if frame.UpdatePreview then frame.UpdatePreview() end
    end
    frame.sizeSlider = sizeSlider

    -- Outline dropdown
    local flagsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    flagsLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -155)
    flagsLabel:SetText("Outline:")
    flagsLabel:SetTextColor(unpack(MedaUI.Theme.text))

    local flagsDropdown = MedaUI:CreateDropdown(frame, 250, FONT_FLAGS)
    flagsDropdown:SetPoint("TOPLEFT", flagsLabel, "BOTTOMLEFT", 0, -4)
    flagsDropdown.OnValueChanged = function(_, value)
        MedaBinds.db.globalStyle.fontFlags = value
        MedaBinds.OverlayManager:RefreshAllOverlays()
        if frame.UpdatePreview then frame.UpdatePreview() end
    end
    frame.flagsDropdown = flagsDropdown

    -- POSITION SECTION
    local posHeader, posLine = MedaUI:CreateSectionHeader(frame, "Position", COLUMN_WIDTH)
    posHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -225)

    -- Anchor dropdown
    local anchorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    anchorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -255)
    anchorLabel:SetText("Anchor:")
    anchorLabel:SetTextColor(unpack(MedaUI.Theme.text))

    local anchorOptions = {}
    for _, pt in ipairs(ANCHOR_POINTS) do
        table.insert(anchorOptions, { label = pt, value = pt })
    end

    local anchorDropdown = MedaUI:CreateDropdown(frame, 250, anchorOptions)
    anchorDropdown:SetPoint("TOPLEFT", anchorLabel, "BOTTOMLEFT", 0, -4)
    anchorDropdown.OnValueChanged = function(_, value)
        MedaBinds.db.globalStyle.anchor = value
        MedaBinds.db.globalStyle.anchorTo = value
        MedaBinds.OverlayManager:RefreshAllOverlays()
        if frame.UpdatePreview then frame.UpdatePreview() end
    end
    frame.anchorDropdown = anchorDropdown

    -- Offset X slider
    local offsetXLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    offsetXLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -320)
    offsetXLabel:SetText("Offset X:")
    offsetXLabel:SetTextColor(unpack(MedaUI.Theme.text))

    local offsetXSlider = MedaUI:CreateSlider(frame, 200, -20, 20, 1)
    offsetXSlider:SetPoint("TOPLEFT", offsetXLabel, "BOTTOMLEFT", 0, -12)
    offsetXSlider.OnValueChanged = function(_, value)
        MedaBinds.db.globalStyle.offsetX = value
        MedaBinds.OverlayManager:RefreshAllOverlays()
        if frame.UpdatePreview then frame.UpdatePreview() end
    end
    frame.offsetXSlider = offsetXSlider

    -- Offset Y slider
    local offsetYLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    offsetYLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, -375)
    offsetYLabel:SetText("Offset Y:")
    offsetYLabel:SetTextColor(unpack(MedaUI.Theme.text))

    local offsetYSlider = MedaUI:CreateSlider(frame, 200, -20, 20, 1)
    offsetYSlider:SetPoint("TOPLEFT", offsetYLabel, "BOTTOMLEFT", 0, -12)
    offsetYSlider.OnValueChanged = function(_, value)
        MedaBinds.db.globalStyle.offsetY = value
        MedaBinds.OverlayManager:RefreshAllOverlays()
        if frame.UpdatePreview then frame.UpdatePreview() end
    end
    frame.offsetYSlider = offsetYSlider

    -- ============================================
    -- RIGHT COLUMN
    -- ============================================

    -- APPEARANCE SECTION
    local appearanceHeader, appearanceLine = MedaUI:CreateSectionHeader(frame, "Appearance", COLUMN_WIDTH)
    appearanceHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN, -10)

    -- Text Color picker
    local colorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN, -40)
    colorLabel:SetText("Text Color:")
    colorLabel:SetTextColor(unpack(MedaUI.Theme.text))

    local colorPicker = MedaUI:CreateColorPicker(frame, 26, 26, true)
    colorPicker:SetPoint("LEFT", colorLabel, "RIGHT", 10, 0)
    colorPicker.OnColorChanged = function(_, r, g, b, a)
        MedaBinds.db.globalStyle.color = { r = r, g = g, b = b, a = a }
        MedaBinds.OverlayManager:RefreshAllOverlays()
        if frame.UpdatePreview then frame.UpdatePreview() end
    end
    frame.colorPicker = colorPicker

    -- Shadow checkbox
    local shadowCheck = MedaUI:CreateCheckbox(frame, "Enable Text Shadow")
    shadowCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN, -75)
    shadowCheck.OnValueChanged = function(_, checked)
        MedaBinds.db.globalStyle.shadowEnabled = checked
        MedaBinds.OverlayManager:RefreshAllOverlays()
        if frame.UpdatePreview then frame.UpdatePreview() end
    end
    frame.shadowCheck = shadowCheck

    -- PREVIEW SECTION
    local previewHeader, previewLine = MedaUI:CreateSectionHeader(frame, "Preview", COLUMN_WIDTH)
    previewHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN, -120)

    local previewBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    previewBg:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN, -150)
    previewBg:SetSize(200, 80)
    previewBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    previewBg:SetBackdropColor(0.05, 0.05, 0.05, 1)
    previewBg:SetBackdropBorderColor(unpack(MedaUI.Theme.border))

    -- Sample icon background (use addon icon)
    local iconBg = previewBg:CreateTexture(nil, "ARTWORK")
    iconBg:SetSize(40, 40)
    iconBg:SetPoint("CENTER", previewBg, "CENTER", 0, 0)
    iconBg:SetTexture("Interface\\AddOns\\MedaBinds\\Media\\binding-chain")

    -- Preview keybind text
    local previewText = previewBg:CreateFontString(nil, "OVERLAY")
    previewText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
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
    local resetButton = MedaUI:CreateButton(frame, "Reset Defaults", 120, 26)
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
    local applyAllButton = MedaUI:CreateButton(frame, "Apply to All Icons", 140, 26)
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
        -- Refresh font dropdown
        local currentFont = MedaBinds.db.globalStyle.font
        fontDropdown:SetSelected(currentFont)

        -- Refresh size slider
        sizeSlider:SetValue(MedaBinds.db.globalStyle.fontSize or 12)

        -- Refresh flags dropdown
        flagsDropdown:SetSelected(MedaBinds.db.globalStyle.fontFlags or "OUTLINE")

        -- Refresh anchor dropdown
        anchorDropdown:SetSelected(MedaBinds.db.globalStyle.anchor or "TOPRIGHT")

        -- Refresh offset sliders
        offsetXSlider:SetValue(MedaBinds.db.globalStyle.offsetX or -2)
        offsetYSlider:SetValue(MedaBinds.db.globalStyle.offsetY or -2)

        -- Refresh color picker
        local color = MedaBinds.db.globalStyle.color or { r = 1, g = 1, b = 1, a = 1 }
        colorPicker:SetColor(color.r, color.g, color.b, color.a or 1)

        -- Refresh shadow checkbox
        shadowCheck:SetChecked(MedaBinds.db.globalStyle.shadowEnabled)

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
    title:SetTextColor(unpack(MedaUI.Theme.gold))

    -- Scan keybinds button
    local scanBtn = MedaUI:CreateButton(frame, "Scan Keybinds", 110, 24)
    scanBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    scanBtn:SetScript("OnClick", function()
        if frame.scanStatus then
            frame.scanStatus:SetText("Scanning...")
            frame.scanStatus:SetTextColor(unpack(MedaUI.Theme.gold))
        end

        -- Use C_Timer to allow UI to update before scan
        C_Timer.After(0.01, function()
            local startTime = debugprofilestop()

            -- Perform the scan
            if MedaBinds.KeybindScanner then
                MedaBinds.KeybindScanner:ForceRescan()
            end

            local endTime = debugprofilestop()
            local elapsed = (endTime - startTime) / 1000

            -- Get counts
            local spellCount = MedaBinds.KeybindScanner and MedaBinds.KeybindScanner:GetCacheCount() or 0
            local itemCount = MedaBinds.KeybindScanner and MedaBinds.KeybindScanner:GetItemCacheCount() or 0

            -- Update status
            if frame.scanStatus then
                frame.scanStatus:SetText(string.format("Found %d spells, %d items (%.1fms)", spellCount, itemCount, elapsed))
                frame.scanStatus:SetTextColor(unpack(MedaUI.Theme.textGreen))
            end

            -- Refresh the icon list
            RefreshIconList()
        end)
    end)
    frame.scanBtn = scanBtn

    -- Config mode button
    local configModeBtn = MedaUI:CreateButton(frame, "Enter Config Mode", 140, 24)
    configModeBtn:SetPoint("RIGHT", scanBtn, "LEFT", -8, 0)
    configModeBtn:SetScript("OnClick", function()
        if MedaBinds.ConfigMode then
            MedaBinds.ConfigMode:Toggle()
        end
    end)

    -- Scroll frame for icon list (using standard WoW scroll frame)
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -45)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 80)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(PANEL_WIDTH - 60, 1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild
    frame.scrollFrame = scrollFrame

    -- Info text
    local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 55)
    infoText:SetText("[Auto] = Detected from action bars  |  [Custom] = User-defined override")
    infoText:SetTextColor(unpack(MedaUI.Theme.textDim))

    -- Scan status text (shows results) - positioned at bottom right
    local scanStatus = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scanStatus:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 55)
    scanStatus:SetJustifyH("RIGHT")
    scanStatus:SetText("")
    scanStatus:SetTextColor(unpack(MedaUI.Theme.textDim))
    frame.scanStatus = scanStatus

    -- Selected icon display
    local selectedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectedLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 35)
    selectedLabel:SetText("Selected: None")
    frame.selectedLabel = selectedLabel

    -- Edit button
    local editBtn = MedaUI:CreateButton(frame, "Edit", 80, 22)
    editBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    editBtn:SetEnabled(false)
    editBtn:SetScript("OnClick", function()
        if selectedIconSpellID and MedaBinds.ConfigMode then
            MedaBinds.ConfigMode:OpenEditor(selectedIconSpellID)
        end
    end)
    frame.editBtn = editBtn

    -- Clear custom button
    local clearBtn = MedaUI:CreateButton(frame, "Clear Custom", 130, 22)
    clearBtn:SetPoint("LEFT", editBtn, "RIGHT", 5, 0)
    clearBtn:SetEnabled(false)
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
    local editExternalBtn = MedaUI:CreateButton(frame, "Edit External", 110, 22)
    editExternalBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -130, 10)
    editExternalBtn:SetEnabled(false)
    editExternalBtn:SetScript("OnClick", function()
        if selectedExternalIconKey and MedaBinds.ConfigMode then
            MedaBinds.ConfigMode:OpenExternalEditor(selectedExternalIconKey)
        end
    end)
    frame.editExternalBtn = editExternalBtn

    local removeExternalBtn = MedaUI:CreateButton(frame, "Remove External", 115, 22)
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
                frame.scanStatus:SetTextColor(unpack(MedaUI.Theme.textDim))
            end
        end
    end

    return frame
end

-- Refresh the icon list (grouped by viewer)
RefreshIconList = function()
    local scrollChild = tabContents.configuredIcons and tabContents.configuredIcons.scrollChild
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
                        local slot = MedaBinds.KeybindScanner and MedaBinds.KeybindScanner:GetSlotForSpell(spellInfo.spellID)
                        local barName, buttonNum = nil, nil
                        if slot then
                            barName, buttonNum = MedaBinds.KeybindScanner:GetBarInfoForSlot(slot)
                        end
                        local data = {
                            spellID = spellInfo.spellID,
                            name = spellInfo.name,
                            keybind = keybindText or "—",
                            source = source or "none",
                            viewerName = displayName,
                            slot = slot,
                            barName = barName,
                            buttonNum = buttonNum,
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
            local slot = MedaBinds.KeybindScanner and MedaBinds.KeybindScanner:GetSlotForSpell(spellID)
            local barName, buttonNum = nil, nil
            if slot then
                barName, buttonNum = MedaBinds.KeybindScanner:GetBarInfoForSlot(slot)
            end
            local data = {
                spellID = spellID,
                name = spellInfo and spellInfo.name or "Unknown",
                keybind = keybindText or "—",
                source = source or "custom",
                viewerName = "Custom",
                slot = slot,
                barName = barName,
                buttonNum = buttonNum,
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
            groupHeader:SetBackdropColor(unpack(MedaUI.Theme.rowHeader))

            local headerText = groupHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headerText:SetPoint("LEFT", 8, 0)
            headerText:SetText(viewerDisplayName .. " (" .. #entries .. ")")
            headerText:SetTextColor(unpack(MedaUI.Theme.gold))

            yOffset = yOffset - headerHeight

            -- Column headers
            local colHeader = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
            colHeader:SetSize(PANEL_WIDTH - 60, 18)
            colHeader:SetPoint("TOPLEFT", 0, yOffset)
            colHeader:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
            })
            colHeader:SetBackdropColor(unpack(MedaUI.Theme.rowSubheader))

            local colWidths = { 180, 80, 140, 80 }
            local colLabels = { "Spell", "Keybind", "Location", "Source" }
            local xPos = 10

            for i, label in ipairs(colLabels) do
                local text = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                text:SetPoint("LEFT", xPos, 0)
                text:SetText(label)
                text:SetTextColor(unpack(MedaUI.Theme.goldDim))
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
                    row:SetBackdropColor(unpack(MedaUI.Theme.rowEven))
                else
                    row:SetBackdropColor(unpack(MedaUI.Theme.rowOdd))
                end

                row:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(unpack(MedaUI.Theme.highlight))
                end)
                row:SetScript("OnLeave", function(self)
                    if currentRowIndex % 2 == 0 then
                        self:SetBackdropColor(unpack(MedaUI.Theme.rowEven))
                    else
                        self:SetBackdropColor(unpack(MedaUI.Theme.rowOdd))
                    end
                end)

                xPos = 10
                local locationText = data.barName and (data.barName .. " #" .. data.buttonNum) or "—"
                local texts = { data.name, data.keybind, locationText, "[" .. data.source .. "]" }
                local colors = {
                    MedaUI.Theme.text,
                    MedaUI.Theme.textGreen,
                    MedaUI.Theme.textDim,
                    data.source == "custom" and MedaUI.Theme.gold or MedaUI.Theme.textDim,
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
                    selectedExternalIconKey = nil
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
        groupHeader:SetBackdropColor(unpack(MedaUI.Theme.rowHeader))

        local headerText = groupHeader:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        headerText:SetPoint("LEFT", 8, 0)
        headerText:SetText("External Icons (" .. externalCount .. ")")
        headerText:SetTextColor(unpack(MedaUI.Theme.gold))

        yOffset = yOffset - headerHeight

        -- Column headers for external icons
        local colHeader = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        colHeader:SetSize(PANEL_WIDTH - 60, 18)
        colHeader:SetPoint("TOPLEFT", 0, yOffset)
        colHeader:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        colHeader:SetBackdropColor(unpack(MedaUI.Theme.rowSubheader))

        local extColWidths = { 240, 180, 120 }
        local extColLabels = { "Frame Name", "Text", "Status" }
        local xPos = 10

        for i, label in ipairs(extColLabels) do
            local text = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", xPos, 0)
            text:SetText(label)
            text:SetTextColor(unpack(MedaUI.Theme.goldDim))
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
                row:SetBackdropColor(unpack(MedaUI.Theme.rowEven))
            else
                row:SetBackdropColor(unpack(MedaUI.Theme.rowOdd))
            end

            row:SetScript("OnEnter", function(self)
                self:SetBackdropColor(unpack(MedaUI.Theme.highlight))
            end)
            row:SetScript("OnLeave", function(self)
                if currentRowIndex % 2 == 0 then
                    self:SetBackdropColor(unpack(MedaUI.Theme.rowEven))
                else
                    self:SetBackdropColor(unpack(MedaUI.Theme.rowOdd))
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
                MedaUI.Theme.text,
                entry.text and MedaUI.Theme.textGreen or MedaUI.Theme.textDim,
                entry.enabled ~= false and MedaUI.Theme.textGreen or MedaUI.Theme.textDim,
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
                selectedIconSpellID = nil
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
    local frame = tabContents.configuredIcons
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

    -- Layout constants (two-column layout)
    local LEFT_COLUMN = 15
    local RIGHT_COLUMN = 320
    local COLUMN_WIDTH = 280

    -- ============================================
    -- LEFT COLUMN
    -- ============================================
    local leftY = -10

    -- Cooldown Viewers section
    local viewerTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    viewerTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, leftY)
    viewerTitle:SetText("Cooldown Viewers")
    viewerTitle:SetTextColor(unpack(MedaUI.Theme.gold))
    leftY = leftY - 25

    local essentialCheck = MedaUI:CreateCheckbox(frame, "Show on Essential Cooldowns")
    essentialCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN + 5, leftY)
    essentialCheck.OnValueChanged = function(_, checked)
        MedaBinds.db.options.showOnEssential = checked
        MedaBinds.OverlayManager:RefreshAllOverlays()
    end
    frame.essentialCheck = essentialCheck
    leftY = leftY - 22

    local utilityCheck = MedaUI:CreateCheckbox(frame, "Show on Utility Cooldowns")
    utilityCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN + 5, leftY)
    utilityCheck.OnValueChanged = function(_, checked)
        MedaBinds.db.options.showOnUtility = checked
        MedaBinds.OverlayManager:RefreshAllOverlays()
    end
    frame.utilityCheck = utilityCheck
    leftY = leftY - 22

    local buffIconCheck = MedaUI:CreateCheckbox(frame, "Show on Buff Icons")
    buffIconCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN + 5, leftY)
    buffIconCheck.OnValueChanged = function(_, checked)
        MedaBinds.db.options.showOnBuffIcons = checked
        MedaBinds.OverlayManager:RefreshAllOverlays()
    end
    frame.buffIconCheck = buffIconCheck
    leftY = leftY - 35

    -- Auto-Detection section
    local autoTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    autoTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, leftY)
    autoTitle:SetText("Auto-Detection")
    autoTitle:SetTextColor(unpack(MedaUI.Theme.gold))
    leftY = leftY - 25

    local enableAutoCheck = MedaUI:CreateCheckbox(frame, "Enable auto-detection")
    enableAutoCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN + 5, leftY)
    enableAutoCheck.OnValueChanged = function(_, checked)
        MedaBinds.db.options.enableAutoDetection = checked
        MedaBinds.OverlayManager:RefreshAllOverlays()
    end
    frame.enableAutoCheck = enableAutoCheck
    leftY = leftY - 22

    local abbreviateCheck = MedaUI:CreateCheckbox(frame, "Abbreviate keybinds (S1)")
    abbreviateCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN + 5, leftY)
    abbreviateCheck.OnValueChanged = function(_, checked)
        MedaBinds.db.options.abbreviateKeybinds = checked
        MedaBinds.KeybindScanner:ForceRescan()
    end
    frame.abbreviateCheck = abbreviateCheck
    leftY = leftY - 22

    local scanHiddenCheck = MedaUI:CreateCheckbox(frame, "Include hidden bars (6-8)")
    scanHiddenCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN + 5, leftY)
    scanHiddenCheck.OnValueChanged = function(_, checked)
        MedaBinds.db.options.scanHiddenBars = checked
        MedaBinds.KeybindScanner:ForceRescan()
    end
    frame.scanHiddenCheck = scanHiddenCheck
    leftY = leftY - 22

    local scanMacrosCheck = MedaUI:CreateCheckbox(frame, "Scan macros for spells")
    scanMacrosCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN + 5, leftY)
    scanMacrosCheck.OnValueChanged = function(_, checked)
        MedaBinds.db.options.scanMacros = checked
        MedaBinds.KeybindScanner:ForceRescan()
    end
    frame.scanMacrosCheck = scanMacrosCheck
    leftY = leftY - 35

    -- Config Mode section
    local configTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    configTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, leftY)
    configTitle:SetText("Config Mode")
    configTitle:SetTextColor(unpack(MedaUI.Theme.gold))
    leftY = leftY - 25

    local modifierLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modifierLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN + 5, leftY)
    modifierLabel:SetText("Modifier Key:")
    modifierLabel:SetTextColor(unpack(MedaUI.Theme.text))

    local modifierDropdown = MedaUI:CreateDropdown(frame, 120, MODIFIER_KEYS)
    modifierDropdown:SetPoint("TOPLEFT", modifierLabel, "BOTTOMLEFT", 0, -4)
    modifierDropdown.OnValueChanged = function(_, value)
        MedaBinds.db.options.configModifierKey = value
    end
    frame.modifierDropdown = modifierDropdown
    leftY = leftY - 50

    local combatDisableCheck = MedaUI:CreateCheckbox(frame, "Auto-disable in combat")
    combatDisableCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN + 5, leftY)
    combatDisableCheck.OnValueChanged = function(_, checked)
        MedaBinds.db.options.autoDisableInCombat = checked
    end
    frame.combatDisableCheck = combatDisableCheck
    leftY = leftY - 35

    -- Interface section
    local interfaceTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    interfaceTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN, leftY)
    interfaceTitle:SetText("Interface")
    interfaceTitle:SetTextColor(unpack(MedaUI.Theme.gold))
    leftY = leftY - 25

    local minimapCheck = MedaUI:CreateCheckbox(frame, "Show minimap button")
    minimapCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN + 5, leftY)
    minimapCheck.OnValueChanged = function(_, checked)
        MedaBinds.db.options.showMinimapButton = checked
        MedaBinds:SetMinimapButtonShown(checked)
    end
    frame.minimapCheck = minimapCheck
    leftY = leftY - 30

    local themeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    themeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_COLUMN + 5, leftY)
    themeLabel:SetText("UI Theme:")
    themeLabel:SetTextColor(unpack(MedaUI.Theme.text))

    local themeSelector = MedaUI:CreateThemeSelector(frame, 180, {
        showPreview = true,
        onChange = function(themeName)
            MedaBinds.db.options.theme = themeName
        end
    })
    themeSelector:SetPoint("TOPLEFT", themeLabel, "BOTTOMLEFT", 0, -4)
    frame.themeSelector = themeSelector

    -- ============================================
    -- RIGHT COLUMN
    -- ============================================
    local rightY = -10

    -- Paged Keybinds section
    local pagedTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pagedTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN, rightY)
    pagedTitle:SetText("Paged Keybinds")
    pagedTitle:SetTextColor(unpack(MedaUI.Theme.gold))
    rightY = rightY - 25

    -- Enable checkbox (renamed and off by default)
    local showPagedCheck = MedaUI:CreateCheckbox(frame, "Enable Paged Keybinds Support")
    showPagedCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN + 5, rightY)
    showPagedCheck.OnValueChanged = function(_, checked)
        MedaBinds.db.options.showPagedKeybinds = checked
        MedaBinds.KeybindScanner:ForceRescan()
        if frame.UpdatePagedPreview then frame.UpdatePagedPreview() end
    end
    frame.showPagedCheck = showPagedCheck
    rightY = rightY - 30

    -- Paged keybind color picker (moved up)
    local pagedColorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pagedColorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN + 5, rightY)
    pagedColorLabel:SetText("Paged Color:")
    pagedColorLabel:SetTextColor(unpack(MedaUI.Theme.text))

    local pagedColorPicker = MedaUI:CreateColorPicker(frame, 26, 26, true)
    pagedColorPicker:SetPoint("LEFT", pagedColorLabel, "RIGHT", 10, 0)
    pagedColorPicker.OnColorChanged = function(_, r, g, b, a)
        MedaBinds.db.options.pagedKeybindColor = { r = r, g = g, b = b, a = a }
        MedaBinds.OverlayManager:RefreshAllOverlays()
        if frame.UpdatePagedPreview then frame.UpdatePagedPreview() end
    end
    frame.pagedColorPicker = pagedColorPicker
    rightY = rightY - 35

    -- Separator input
    local separatorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    separatorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN + 5, rightY)
    separatorLabel:SetText("Separator:")
    separatorLabel:SetTextColor(unpack(MedaUI.Theme.text))

    local separatorEditBox = MedaUI:CreateEditBox(frame, 50, 24)
    separatorEditBox:SetPoint("LEFT", separatorLabel, "RIGHT", 10, 0)
    separatorEditBox:SetText(MedaBinds.db and MedaBinds.db.options.pagedKeybindSeparator or ">")
    frame.separatorEditBox = separatorEditBox

    -- Saved feedback text for separator
    local separatorSavedText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    separatorSavedText:SetPoint("LEFT", separatorEditBox, "RIGHT", 8, 0)
    separatorSavedText:SetText("")
    separatorSavedText:SetTextColor(0.4, 1, 0.4, 1)

    -- Track last saved value to avoid duplicate saves
    separatorEditBox._lastSavedValue = nil
    separatorEditBox._pendingRescan = nil

    -- Function to save the separator (with dedup and debounced rescan)
    local function SaveSeparator()
        local value = separatorEditBox:GetText()
        -- Only save if value actually changed
        if value == separatorEditBox._lastSavedValue then
            return
        end
        separatorEditBox._lastSavedValue = value
        MedaBinds.db.options.pagedKeybindSeparator = value
        separatorSavedText:SetText("Saved!")

        -- Cancel any pending rescan
        if separatorEditBox._pendingRescan then
            separatorEditBox._pendingRescan:Cancel()
        end

        -- Debounce and use light rescan to avoid freezing
        separatorEditBox._pendingRescan = C_Timer.NewTimer(0.1, function()
            MedaBinds.KeybindScanner:RebuildPagedKeybinds()
            separatorEditBox._pendingRescan = nil
        end)

        -- Update preview
        if frame.UpdatePagedPreview then frame.UpdatePagedPreview() end

        C_Timer.After(2, function()
            if separatorSavedText then
                separatorSavedText:SetText("")
            end
        end)
    end

    -- Save on Enter press
    separatorEditBox.OnEnterPressed = function(_, text)
        SaveSeparator()
    end

    -- Also save on focus lost by hooking the inner editBox
    separatorEditBox.editBox:HookScript("OnEditFocusLost", function()
        SaveSeparator()
    end)

    rightY = rightY - 32

    -- Custom Paged Keybind input (renamed from Page Switch Key)
    local customPagedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    customPagedLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN + 5, rightY)
    customPagedLabel:SetText("Custom Paged Keybind:")
    customPagedLabel:SetTextColor(unpack(MedaUI.Theme.text))
    rightY = rightY - 22

    local customPagedEditBox = MedaUI:CreateEditBox(frame, 80, 24)
    customPagedEditBox:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN + 5, rightY)
    customPagedEditBox:SetText(MedaBinds.db and MedaBinds.db.options.customPagedKeybind or "")
    frame.customPagedEditBox = customPagedEditBox

    -- Saved feedback text for custom paged keybind
    local customPagedSavedText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customPagedSavedText:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN + 5, rightY - 26)
    customPagedSavedText:SetText("")
    customPagedSavedText:SetTextColor(0.4, 1, 0.4, 1)

    -- Track last saved value to avoid duplicate saves
    customPagedEditBox._lastSavedValue = nil
    customPagedEditBox._pendingRescan = nil

    -- Function to save the custom paged keybind (with dedup and debounced rescan)
    local function SaveCustomPagedKeybind()
        local value = customPagedEditBox:GetText()
        -- Only save if value actually changed
        if value == customPagedEditBox._lastSavedValue then
            return
        end
        customPagedEditBox._lastSavedValue = value
        MedaBinds.db.options.customPagedKeybind = value
        customPagedSavedText:SetText("Saved!")

        -- Cancel any pending rescan
        if customPagedEditBox._pendingRescan then
            customPagedEditBox._pendingRescan:Cancel()
        end

        -- Debounce and use light rescan to avoid freezing
        customPagedEditBox._pendingRescan = C_Timer.NewTimer(0.1, function()
            MedaBinds.KeybindScanner:RebuildPagedKeybinds()
            customPagedEditBox._pendingRescan = nil
        end)

        -- Update preview
        if frame.UpdatePagedPreview then frame.UpdatePagedPreview() end

        C_Timer.After(2, function()
            if customPagedSavedText then
                customPagedSavedText:SetText("")
            end
        end)
    end

    -- Save on Enter press
    customPagedEditBox.OnEnterPressed = function(_, text)
        SaveCustomPagedKeybind()
    end

    -- Also save on focus lost by hooking the inner editBox
    customPagedEditBox.editBox:HookScript("OnEditFocusLost", function()
        SaveCustomPagedKeybind()
    end)

    -- Help text
    rightY = rightY - 42
    local helpText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    helpText:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN + 5, rightY)
    helpText:SetText("e.g. Q shows Q>E, empty shows >E")
    helpText:SetTextColor(unpack(MedaUI.Theme.textDim))
    rightY = rightY - 20

    -- Preview section
    local previewLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN + 5, rightY)
    previewLabel:SetText("Preview:")
    previewLabel:SetTextColor(unpack(MedaUI.Theme.text))
    rightY = rightY - 22

    local pagedPreviewBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    pagedPreviewBg:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_COLUMN + 5, rightY)
    pagedPreviewBg:SetSize(200, 80)
    pagedPreviewBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    pagedPreviewBg:SetBackdropColor(0.05, 0.05, 0.05, 1)
    pagedPreviewBg:SetBackdropBorderColor(unpack(MedaUI.Theme.border))

    -- Sample icon background (same size as global styles preview)
    local pagedIconBg = pagedPreviewBg:CreateTexture(nil, "ARTWORK")
    pagedIconBg:SetSize(40, 40)
    pagedIconBg:SetPoint("CENTER", pagedPreviewBg, "CENTER", 0, 0)
    pagedIconBg:SetTexture("Interface\\AddOns\\MedaBinds\\Media\\binding-chain")

    -- Preview keybind text
    local pagedPreviewText = pagedPreviewBg:CreateFontString(nil, "OVERLAY")
    pagedPreviewText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    pagedPreviewText:SetPoint("TOPRIGHT", pagedIconBg, "TOPRIGHT", -2, -2)
    pagedPreviewText:SetText(">E")
    frame.pagedPreviewText = pagedPreviewText

    -- Function to update the paged keybind preview
    -- Uses global style for font/position but paged color for text
    local function UpdatePagedPreview()
        local options = MedaBinds.db and MedaBinds.db.options or {}
        local style = MedaBinds.db.globalStyle or {}
        local separator = options.pagedKeybindSeparator or ">"
        local customKey = options.customPagedKeybind or ""
        local pagedColor = options.pagedKeybindColor or { r = 0.7, g = 0.7, b = 0.9, a = 1 }

        -- Build preview text: "Q>E" or ">E"
        local previewStr
        if customKey ~= "" then
            previewStr = customKey .. separator .. "E"
        else
            previewStr = separator .. "E"
        end

        -- Apply global style font settings
        local fontPath = style.font or "Fonts\\FRIZQT__.TTF"
        local fontSize = style.fontSize or 12
        local fontFlags = style.fontFlags or "OUTLINE"
        pagedPreviewText:SetFont(fontPath, fontSize, fontFlags)

        -- Apply paged color (not global color)
        pagedPreviewText:SetTextColor(pagedColor.r, pagedColor.g, pagedColor.b, pagedColor.a or 1)

        -- Apply global style shadow settings
        if style.shadowEnabled then
            local shadowColor = style.shadowColor or { r = 0, g = 0, b = 0, a = 1 }
            local shadowOffset = style.shadowOffset or { x = 1, y = -1 }
            pagedPreviewText:SetShadowColor(shadowColor.r, shadowColor.g, shadowColor.b, shadowColor.a or 1)
            pagedPreviewText:SetShadowOffset(shadowOffset.x, shadowOffset.y)
        else
            pagedPreviewText:SetShadowOffset(0, 0)
        end

        -- Apply global style position settings
        pagedPreviewText:ClearAllPoints()
        local anchor = style.anchor or "TOPRIGHT"
        local offsetX = style.offsetX or -2
        local offsetY = style.offsetY or -2
        pagedPreviewText:SetPoint(anchor, pagedIconBg, anchor, offsetX, offsetY)

        pagedPreviewText:SetText(previewStr)
    end
    frame.UpdatePagedPreview = UpdatePagedPreview

    frame.Refresh = function()
        essentialCheck:SetChecked(MedaBinds.db.options.showOnEssential)
        utilityCheck:SetChecked(MedaBinds.db.options.showOnUtility)
        buffIconCheck:SetChecked(MedaBinds.db.options.showOnBuffIcons)
        enableAutoCheck:SetChecked(MedaBinds.db.options.enableAutoDetection)
        abbreviateCheck:SetChecked(MedaBinds.db.options.abbreviateKeybinds)
        scanHiddenCheck:SetChecked(MedaBinds.db.options.scanHiddenBars)
        scanMacrosCheck:SetChecked(MedaBinds.db.options.scanMacros)

        -- Paged keybind settings
        showPagedCheck:SetChecked(MedaBinds.db.options.showPagedKeybinds)

        -- Paged color picker
        local pagedColor = MedaBinds.db.options.pagedKeybindColor or { r = 0.7, g = 0.7, b = 0.9, a = 1 }
        pagedColorPicker:SetColor(pagedColor.r, pagedColor.g, pagedColor.b, pagedColor.a or 1)

        -- Separator
        local separatorValue = MedaBinds.db.options.pagedKeybindSeparator or ">"
        separatorEditBox:SetText(separatorValue)
        separatorEditBox._lastSavedValue = separatorValue

        -- Custom paged keybind
        local customPagedValue = MedaBinds.db.options.customPagedKeybind or ""
        customPagedEditBox:SetText(customPagedValue)
        customPagedEditBox._lastSavedValue = customPagedValue

        -- Update preview
        UpdatePagedPreview()

        modifierDropdown:SetSelected(MedaBinds.db.options.configModifierKey)
        combatDisableCheck:SetChecked(MedaBinds.db.options.autoDisableInCombat)
        minimapCheck:SetChecked(MedaBinds.db.options.showMinimapButton)
        -- Theme selector refreshes itself automatically
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
    local globalStylesTab = tabContents.globalStyles
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
