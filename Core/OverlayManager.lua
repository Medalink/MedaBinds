--[[
    MedaBinds - OverlayManager.lua
    FontString creation and management on CooldownViewer icons
]]

local addonName, MedaBinds = ...

-- OverlayManager module
local OverlayManager = {}
MedaBinds.OverlayManager = OverlayManager

-- Table to track overlays on icons
local iconOverlays = {}  -- [icon] = FontString
local viewerHooks = {}   -- Track which viewers we've hooked

-- Target viewer frame names
local VIEWER_FRAMES = {
    essential = "EssentialCooldownViewer",
    utility = "UtilityCooldownViewer",
    buffIcons = "BuffIconCooldownViewer",
    buffBars = "BuffBarCooldownViewer",
}

-- Map viewer names to option keys
local VIEWER_OPTIONS = {
    [VIEWER_FRAMES.essential] = "showOnEssential",
    [VIEWER_FRAMES.utility] = "showOnUtility",
    [VIEWER_FRAMES.buffIcons] = "showOnBuffIcons",
    [VIEWER_FRAMES.buffBars] = "showOnBuffBars",
}

-- Create or get the keybind overlay FontString for an icon
local function GetOrCreateOverlay(icon)
    if iconOverlays[icon] and iconOverlays[icon].text then
        return iconOverlays[icon].text
    end

    -- Create container frame for proper layering
    local container = CreateFrame("Frame", nil, icon, "BackdropTemplate")
    container:SetFrameLevel(icon:GetFrameLevel() + 4)
    container:SetAllPoints(icon)

    -- Create FontString inside container
    local overlay = container:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    overlay:SetDrawLayer("OVERLAY", 7)

    -- Setup shadow
    overlay:SetShadowColor(0, 0, 0, 1)
    overlay:SetShadowOffset(1, -1)

    iconOverlays[icon] = {
        container = container,
        text = overlay,
        spellID = nil,
        viewerName = nil,
    }

    return overlay
end

-- Apply style settings to an overlay
local function ApplyStyleToOverlay(overlay, icon, style)
    if not overlay or not style then return end

    -- Font settings
    local fontPath = style.font or "Fonts\\FRIZQT__.TTF"
    local fontSize = style.fontSize or 12
    local fontFlags = style.fontFlags or "OUTLINE"

    overlay:SetFont(fontPath, fontSize, fontFlags)

    -- Color
    local color = style.color or { r = 1, g = 1, b = 1, a = 1 }
    overlay:SetTextColor(color.r, color.g, color.b, color.a)

    -- Shadow
    if style.shadowEnabled then
        local shadowColor = style.shadowColor or { r = 0, g = 0, b = 0, a = 1 }
        local shadowOffset = style.shadowOffset or { x = 1, y = -1 }
        overlay:SetShadowColor(shadowColor.r, shadowColor.g, shadowColor.b, shadowColor.a)
        overlay:SetShadowOffset(shadowOffset.x, shadowOffset.y)
    else
        overlay:SetShadowOffset(0, 0)
    end

    -- Position
    local anchor = style.anchor or "TOPRIGHT"
    local anchorTo = style.anchorTo or "TOPRIGHT"
    local offsetX = style.offsetX or -2
    local offsetY = style.offsetY or -2

    overlay:ClearAllPoints()
    overlay:SetPoint(anchor, icon, anchorTo, offsetX, offsetY)
end

-- Update a single icon's overlay
local function UpdateIconOverlay(icon, viewerName)
    if not icon then return end

    -- Check if this viewer type is enabled
    local optionKey = VIEWER_OPTIONS[viewerName]
    if optionKey and MedaBinds.db and not MedaBinds.db.options[optionKey] then
        -- Hide overlay if viewer is disabled
        local overlayData = iconOverlays[icon]
        if overlayData and overlayData.container then
            overlayData.container:Hide()
        end
        return
    end

    -- Get spellID or itemID from the icon using multiple methods
    local spellID = nil
    local itemID = nil

    -- Method 1: C_CooldownViewer API (primary for Blizzard CooldownViewer)
    if icon.cooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(icon.cooldownID)
        if info then
            spellID = info.spellID
            -- CooldownViewer might also have itemID for trinkets
            itemID = info.itemID
        end
    end

    -- Method 2: Direct itemID property (for items/trinkets)
    if not itemID and icon.itemID then
        itemID = icon.itemID
    end

    -- Method 3: Direct spellID property (custom addons)
    if not spellID and icon.spellID then
        spellID = icon.spellID
    end

    -- Method 4: GetSpellID method (some addons)
    if not spellID and icon.GetSpellID and type(icon.GetSpellID) == "function" then
        local success, result = pcall(icon.GetSpellID, icon)
        if success and result then
            spellID = result
        end
    end

    -- Method 5: GetItemID method (some addons)
    if not itemID and icon.GetItemID and type(icon.GetItemID) == "function" then
        local success, result = pcall(icon.GetItemID, icon)
        if success and result then
            itemID = result
        end
    end

    -- Method 6: spell field (common in some addons)
    if not spellID and icon.spell then
        if type(icon.spell) == "number" then
            spellID = icon.spell
        elseif type(icon.spell) == "table" and icon.spell.spellID then
            spellID = icon.spell.spellID
        end
    end

    -- Method 7: item field (for item-based icons)
    if not itemID and icon.item then
        if type(icon.item) == "number" then
            itemID = icon.item
        elseif type(icon.item) == "table" and icon.item.itemID then
            itemID = icon.item.itemID
        end
    end

    -- Method 8: auraInstanceID for buff frames
    if not spellID and icon.auraInstanceID and C_UnitAuras then
        local auraInfo = C_UnitAuras.GetAuraDataByAuraInstanceID("player", icon.auraInstanceID)
        if auraInfo then
            spellID = auraInfo.spellId
        end
    end

    -- Method 9: Check icon texture to match equipped trinkets (fallback)
    if not itemID and not spellID then
        local iconTexture = nil
        -- Safely try to get texture (Icon might be a Frame or Texture)
        if icon.Icon then
            if icon.Icon.GetTexture and type(icon.Icon.GetTexture) == "function" then
                iconTexture = icon.Icon:GetTexture()
            elseif icon.Icon.icon and icon.Icon.icon.GetTexture then
                iconTexture = icon.Icon.icon:GetTexture()
            end
        elseif icon.icon and icon.icon.GetTexture and type(icon.icon.GetTexture) == "function" then
            iconTexture = icon.icon:GetTexture()
        end
        if iconTexture then
            -- Check if it matches equipped trinkets
            for slot = 13, 14 do
                local equippedItemID = GetInventoryItemID("player", slot)
                if equippedItemID then
                    local itemIcon = C_Item.GetItemIconByID(equippedItemID)
                    if itemIcon == iconTexture then
                        itemID = equippedItemID
                        break
                    end
                end
            end
        end
    end

    if not spellID and not itemID then
        -- Hide overlay if no spell or item found
        local overlayData = iconOverlays[icon]
        if overlayData and overlayData.container then
            overlayData.container:Hide()
        end
        return
    end

    -- Check for spell override (talent replacement)
    -- Store base spell for keybind lookup, but use override for display
    local baseSpellID = spellID
    if spellID and C_Spell.GetOverrideSpell then
        local overrideSpellID = C_Spell.GetOverrideSpell(spellID)
        if overrideSpellID and overrideSpellID ~= spellID then
            spellID = overrideSpellID
        end
    end

    -- Get keybind text
    local keybindText, source = nil, nil

    -- Try item keybind first if we have an itemID
    if itemID and MedaBinds.KeybindScanner then
        keybindText = MedaBinds.KeybindScanner:GetKeybindForItem(itemID)
        if keybindText then
            source = "auto"
        end
    end

    -- Try spell keybind if no item keybind found
    if not keybindText and spellID then
        keybindText, source = MedaBinds:GetKeybindText(spellID)
        if not keybindText and baseSpellID and baseSpellID ~= spellID then
            keybindText, source = MedaBinds:GetKeybindText(baseSpellID)
        end
    end

    -- Store cached keybind on icon for persistence across updates
    if keybindText and keybindText ~= "" then
        icon._medabinds_keybind = keybindText
    elseif icon._medabinds_keybind then
        -- Use cached keybind if current lookup failed but we have a cached one
        keybindText = icon._medabinds_keybind
        source = "cached"
    end

    if not keybindText or keybindText == "" then
        -- Hide overlay if no keybind
        local overlayData = iconOverlays[icon]
        if overlayData and overlayData.container then
            overlayData.container:Hide()
        end
        return
    end

    -- Get or create overlay
    local overlay = GetOrCreateOverlay(icon)
    local overlayData = iconOverlays[icon]

    -- Get style for this spell/item (use spellID if available, otherwise itemID for style lookup)
    local styleID = spellID or itemID
    local style = styleID and MedaBinds:GetSpellStyle(styleID) or MedaBinds.db.globalStyle

    -- Apply style and text
    ApplyStyleToOverlay(overlay, icon, style)
    overlay:SetText(keybindText)
    overlay:Show()

    -- Show container
    if overlayData and overlayData.container then
        overlayData.container:Show()
    end

    -- Store metadata
    if overlayData then
        overlayData.spellID = spellID
        overlayData.itemID = itemID
        overlayData.viewerName = viewerName
    end
end

-- Check if a frame looks like a cooldown icon
local function IsCooldownIcon(frame)
    if not frame then return false end

    -- Has cooldownID (standard Blizzard CooldownViewer icon)
    if frame.cooldownID then return true end

    -- Has Icon texture (common pattern)
    if frame.Icon then return true end

    -- Has icon texture (lowercase variant)
    if frame.icon then return true end

    -- Has a texture child that looks like an icon
    for _, child in ipairs({ frame:GetRegions() }) do
        if child:IsObjectType("Texture") then
            local tex = child:GetTexture()
            if tex and type(tex) == "number" then
                return true  -- Has a texture ID, likely a spell icon
            end
        end
    end

    return false
end

-- Refresh all icons on a specific viewer
local function RefreshViewerOverlays(viewerFrame, viewerName)
    if not viewerFrame then return end

    -- Check if viewer type is enabled
    local optionKey = VIEWER_OPTIONS[viewerName]
    if optionKey and MedaBinds.db and not MedaBinds.db.options[optionKey] then
        -- Hide all overlays on this viewer
        for icon, overlayData in pairs(iconOverlays) do
            if overlayData.viewerName == viewerName and overlayData.container then
                overlayData.container:Hide()
            end
        end
        return
    end

    -- Iterate through all children of the viewer (recursive to find nested icons)
    local function ScanChildren(parent, depth)
        if depth > 3 then return end  -- Limit recursion depth

        local children = { parent:GetChildren() }
        for _, child in ipairs(children) do
            if IsCooldownIcon(child) then
                UpdateIconOverlay(child, viewerName)
            else
                -- Check nested children for custom addon structures
                ScanChildren(child, depth + 1)
            end
        end
    end

    ScanChildren(viewerFrame, 0)
end

-- Hook a viewer frame to update overlays when it refreshes
local function HookViewer(viewerName)
    local viewerFrame = _G[viewerName]
    if not viewerFrame then
        MedaBinds:Debug("OverlayManager: Viewer not found:", viewerName)
        return
    end

    if viewerHooks[viewerName] then
        MedaBinds:Debug("OverlayManager: Viewer already hooked:", viewerName)
        return
    end

    MedaBinds:Debug("OverlayManager: Hooking viewer:", viewerName)

    -- Hook the RefreshLayout or Update method if it exists
    if viewerFrame.RefreshLayout then
        hooksecurefunc(viewerFrame, "RefreshLayout", function(self)
            C_Timer.After(0, function()
                RefreshViewerOverlays(self, viewerName)
            end)
        end)
    end

    if viewerFrame.UpdateIcons then
        hooksecurefunc(viewerFrame, "UpdateIcons", function(self)
            C_Timer.After(0, function()
                RefreshViewerOverlays(self, viewerName)
            end)
        end)
    end

    -- Hook OnShow to refresh when viewer becomes visible
    viewerFrame:HookScript("OnShow", function(self)
        C_Timer.After(0.1, function()
            RefreshViewerOverlays(self, viewerName)
        end)
    end)

    -- Also hook the container if it exists
    local container = viewerFrame.Container
    if container then
        -- Hook child changes
        if container.UpdateLayout then
            hooksecurefunc(container, "UpdateLayout", function()
                C_Timer.After(0, function()
                    RefreshViewerOverlays(viewerFrame, viewerName)
                end)
            end)
        end
    end

    viewerHooks[viewerName] = true

    -- Initial refresh
    RefreshViewerOverlays(viewerFrame, viewerName)
end

-- Try to hook viewers (may need to retry if not loaded yet)
local function TryHookViewers()
    local allHooked = true

    for key, viewerName in pairs(VIEWER_FRAMES) do
        if not viewerHooks[viewerName] then
            local frame = _G[viewerName]
            if frame then
                HookViewer(viewerName)
            else
                allHooked = false
            end
        end
    end

    return allHooked
end

-- Refresh all overlays
function OverlayManager:RefreshAllOverlays()
    MedaBinds:Debug("OverlayManager: Refreshing all overlays")

    for viewerName, hooked in pairs(viewerHooks) do
        if hooked then
            local viewerFrame = _G[viewerName]
            if viewerFrame then
                RefreshViewerOverlays(viewerFrame, viewerName)
            end
        end
    end
end

-- Refresh a specific spell's overlay across all viewers
function OverlayManager:RefreshSpellOverlay(spellID)
    for icon, overlayData in pairs(iconOverlays) do
        if overlayData.spellID == spellID then
            local viewerName = overlayData.viewerName
            UpdateIconOverlay(icon, viewerName)
        end
    end
end

-- Preview spell overlay with temporary settings (for live editor preview)
function OverlayManager:PreviewSpellOverlay(spellID, text, useAuto, style)
    for icon, overlayData in pairs(iconOverlays) do
        if overlayData.spellID == spellID and overlayData.text then
            local overlay = overlayData.text

            -- Determine what text to show
            local displayText = nil
            if not useAuto and text and text ~= "" then
                displayText = text
            else
                -- Use auto-detected keybind
                if MedaBinds.KeybindScanner then
                    displayText = MedaBinds.KeybindScanner:GetKeybindForSpell(spellID)
                end
            end

            if displayText then
                overlay:SetText(displayText)
                overlay:Show()

                -- Build merged style (preview style overrides global)
                local globalStyle = MedaBinds.db.globalStyle
                local mergedStyle = CopyTable(globalStyle)

                if style then
                    for key, value in pairs(style) do
                        mergedStyle[key] = value
                    end
                end

                -- Apply style
                ApplyStyleToOverlay(overlay, icon, mergedStyle)

                -- Show container
                if overlayData.container then
                    overlayData.container:Show()
                end
            end
        end
    end
end

-- Get all icons for a specific spell
function OverlayManager:GetIconsForSpell(spellID)
    local icons = {}
    for icon, overlayData in pairs(iconOverlays) do
        if overlayData.spellID == spellID then
            table.insert(icons, icon)
        end
    end
    return icons
end

-- Get icon at cursor position (for config mode)
function OverlayManager:GetIconAtCursor()
    -- GetMouseFocus was removed in WoW 10.0, use GetMouseFoci instead
    local frames = GetMouseFoci and GetMouseFoci() or (GetMouseFocus and {GetMouseFocus()} or {})

    for _, focus in ipairs(frames) do
        if focus then
            -- Check if focus is a CooldownViewer icon
            if focus.cooldownID then
                return focus
            end

            -- Check parent
            local parent = focus:GetParent()
            if parent and parent.cooldownID then
                return parent
            end

            -- Check grandparent (for nested structures)
            if parent then
                local grandparent = parent:GetParent()
                if grandparent and grandparent.cooldownID then
                    return grandparent
                end
            end
        end
    end

    return nil
end

-- Get spell info from an icon (also detects items)
function OverlayManager:GetSpellInfoFromIcon(icon)
    if not icon then return nil end

    local spellID = nil
    local itemID = nil

    -- Try C_CooldownViewer API first (primary method for 12.0)
    if icon.cooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(icon.cooldownID)
        if info then
            spellID = info.spellID
            itemID = info.itemID
        end
    end

    -- Try direct itemID property
    if not itemID and icon.itemID then
        itemID = icon.itemID
    end

    -- Try direct spellID property (some addons use this)
    if not spellID and icon.spellID then
        spellID = icon.spellID
    end

    -- Try GetSpellID method (some addons provide this)
    if not spellID and icon.GetSpellID and type(icon.GetSpellID) == "function" then
        local success, result = pcall(icon.GetSpellID, icon)
        if success and result then
            spellID = result
        end
    end

    -- Try GetItemID method
    if not itemID and icon.GetItemID and type(icon.GetItemID) == "function" then
        local success, result = pcall(icon.GetItemID, icon)
        if success and result then
            itemID = result
        end
    end

    -- Try auraInstanceID for buff tracking frames
    if not spellID and icon.auraInstanceID and C_UnitAuras then
        local auraInfo = C_UnitAuras.GetAuraDataByAuraInstanceID("player", icon.auraInstanceID)
        if auraInfo then
            spellID = auraInfo.spellId
        end
    end

    -- Try cached data from our overlay
    if not spellID and not itemID then
        local overlayData = iconOverlays[icon]
        if overlayData then
            spellID = overlayData.spellID
            itemID = overlayData.itemID
        end
    end

    -- Check icon texture to match equipped trinkets (fallback)
    if not itemID and not spellID then
        local iconTexture = nil
        -- Safely try to get texture (Icon might be a Frame or Texture)
        if icon.Icon then
            if icon.Icon.GetTexture and type(icon.Icon.GetTexture) == "function" then
                iconTexture = icon.Icon:GetTexture()
            elseif icon.Icon.icon and icon.Icon.icon.GetTexture then
                iconTexture = icon.Icon.icon:GetTexture()
            end
        elseif icon.icon and icon.icon.GetTexture and type(icon.icon.GetTexture) == "function" then
            iconTexture = icon.icon:GetTexture()
        end
        if iconTexture then
            for slot = 13, 14 do
                local equippedItemID = GetInventoryItemID("player", slot)
                if equippedItemID then
                    local itemIcon = C_Item.GetItemIconByID(equippedItemID)
                    if itemIcon == iconTexture then
                        itemID = equippedItemID
                        break
                    end
                end
            end
        end
    end

    -- If we have an itemID but no spellID, return item info
    if itemID and not spellID then
        local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemID)
        return {
            spellID = nil,
            itemID = itemID,
            baseSpellID = nil,
            name = itemName or ("Item " .. itemID),
            icon = itemIcon,
            isOverride = false,
            isItem = true,
        }
    end

    if not spellID then
        return nil
    end

    -- Check if this spell has an override (talent replacement)
    local displaySpellID = spellID
    local baseSpellID = spellID
    if C_Spell.GetOverrideSpell then
        local overrideSpellID = C_Spell.GetOverrideSpell(spellID)
        if overrideSpellID and overrideSpellID ~= spellID then
            displaySpellID = overrideSpellID
        end
    end

    -- Get spell name/info for the display spell (override if applicable)
    local spellInfo = C_Spell.GetSpellInfo(displaySpellID)

    return {
        spellID = displaySpellID,
        itemID = itemID,
        baseSpellID = baseSpellID,
        name = spellInfo and spellInfo.name or "Unknown",
        icon = spellInfo and spellInfo.iconID,
        isOverride = displaySpellID ~= baseSpellID,
        isItem = false,
    }
end

-- Get viewer name for an icon
function OverlayManager:GetViewerNameForIcon(icon)
    if not icon then return nil end

    -- First check if we have cached viewer name from overlay data
    local overlayData = iconOverlays[icon]
    if overlayData and overlayData.viewerName then
        return overlayData.viewerName
    end

    -- Walk up the parent chain looking for a known viewer frame
    local parent = icon:GetParent()
    while parent do
        local name = parent:GetName()
        if name then
            for key, viewerName in pairs(VIEWER_FRAMES) do
                if name == viewerName or name:find(viewerName) then
                    return viewerName
                end
            end
        end
        parent = parent:GetParent()
    end

    return nil
end

-- Initialize the overlay manager
function OverlayManager:Initialize()
    MedaBinds:Debug("OverlayManager: Initializing")

    -- Try to hook viewers immediately
    local allHooked = TryHookViewers()

    -- If not all hooked, retry periodically
    if not allHooked then
        local attempts = 0
        local maxAttempts = 20

        local ticker
        ticker = C_Timer.NewTicker(0.5, function()
            attempts = attempts + 1
            if TryHookViewers() or attempts >= maxAttempts then
                ticker:Cancel()
                MedaBinds:Debug("OverlayManager: Hook attempts complete. Hooked viewers:", self:GetHookedViewerCount())
            end
        end)
    end

    -- Reconnect external icons after a delay (other addons need to load their frames first)
    C_Timer.After(3, function()
        self:ReconnectExternalIcons()
    end)

    -- Also reconnect on PLAYER_ENTERING_WORLD (some addons create frames on this event)
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(self, event, isInitialLogin, isReloadingUI)
        -- Delay slightly to let other addons finish their initialization
        C_Timer.After(1, function()
            MedaBinds:Debug("OverlayManager: PLAYER_ENTERING_WORLD - checking external icons")
            OverlayManager:DoReconnectExternalIcons()
        end)
    end)

    MedaBinds:Debug("OverlayManager: Initialized")
end

-- Get count of hooked viewers
function OverlayManager:GetHookedViewerCount()
    local count = 0
    for _ in pairs(viewerHooks) do
        count = count + 1
    end
    return count
end

-- Get all viewer names
function OverlayManager:GetViewerFrameNames()
    return VIEWER_FRAMES
end

-- Check if a viewer is hooked
function OverlayManager:IsViewerHooked(viewerName)
    return viewerHooks[viewerName] == true
end

-- ============================================================================
-- External Icon Support
-- ============================================================================

-- Table to track external icon overlays
local externalOverlays = {}  -- [uniqueKey] = { frame = frame, overlay = FontString, container = Frame }

-- Separate runtime table for frame references (NOT stored in SavedVariables)
-- This is critical because WoW cannot serialize frame references (userdata)
local externalFrameRefs = {}  -- [uniqueKey] = frame

-- Create overlay on an external icon
-- Parents directly to the target frame, with OnUpdate to detect and recreate when frame is destroyed
function OverlayManager:CreateExternalOverlay(frame, uniqueKey)
    if not frame or not uniqueKey then return end

    local entry = MedaBinds.db.externalIcons[uniqueKey]
    if not entry then return end

    -- Clean up existing overlay if present
    local existingData = externalOverlays[uniqueKey]
    if existingData and existingData.container then
        existingData.container:SetScript("OnUpdate", nil)
        existingData.container:Hide()
        existingData.container:SetParent(nil)
        externalOverlays[uniqueKey] = nil
    end

    -- Store the target frame name for re-finding after recreation
    local targetFrameName = entry.frameName

    -- Create container frame parented directly to the target frame
    -- Match parent strata but use very high frame level (some addons use +999 for their overlays)
    local container = CreateFrame("Frame", nil, frame)
    container:SetFrameStrata(frame:GetFrameStrata())
    container:SetFrameLevel(frame:GetFrameLevel() + 1001)
    container:SetAllPoints(frame)

    -- Create FontString
    local overlay = container:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    overlay:SetDrawLayer("OVERLAY", 7)
    overlay:SetShadowColor(0, 0, 0, 1)
    overlay:SetShadowOffset(1, -1)


    externalOverlays[uniqueKey] = {
        frame = frame,
        overlay = overlay,
        container = container,
        targetFrameName = targetFrameName,
    }

    -- Create a watcher frame (parented to UIParent) to detect when target frame is destroyed/hidden
    local watcher = CreateFrame("Frame", nil, UIParent)
    local watcherThrottle = 0
    watcher:SetScript("OnUpdate", function(self, elapsed)
        -- Throttle checks to every 0.5 seconds
        watcherThrottle = watcherThrottle + elapsed
        if watcherThrottle < 0.5 then return end
        watcherThrottle = 0

        -- Check if our container still has a valid, visible parent
        local currentParent = container:GetParent()
        local parentLost = not currentParent
        local parentHidden = currentParent and not currentParent:IsVisible()

        if parentLost or parentHidden then
            MedaBinds:Debug("Watcher: parent", parentLost and "lost" or "hidden", "for", targetFrameName)

            -- Container's parent was destroyed or hidden, try to find the new visible frame
            local newFrame = OverlayManager:FindVisibleFrameByName(targetFrameName)

            if newFrame and newFrame ~= currentParent then
                MedaBinds:Debug("Watcher: rebuilding overlay for", targetFrameName)
                externalFrameRefs[uniqueKey] = newFrame
                self:SetScript("OnUpdate", nil)  -- Stop watching
                -- Recreate the overlay
                OverlayManager:CreateExternalOverlay(newFrame, uniqueKey)
            end
        end
    end)
    container.watcher = watcher

    -- Check if frame is actually visible
    local frameVisible = frame:IsVisible()
    local frameParentName = frame:GetParent() and frame:GetParent():GetName() or "nil"

    MedaBinds:Debug("CreateExternalOverlay: created for", targetFrameName,
        "visible:", frameVisible, "parent:", frameParentName)

    -- Apply style and text
    self:RefreshExternalOverlay(uniqueKey, frame)

    return overlay
end

-- Refresh an external icon overlay
function OverlayManager:RefreshExternalOverlay(uniqueKey, frame)
    local overlayData = externalOverlays[uniqueKey]
    local entry = MedaBinds.db.externalIcons[uniqueKey]

    MedaBinds:Debug("RefreshExternalOverlay:", uniqueKey, "entry:", entry and "exists" or "nil", "overlayData:", overlayData and "exists" or "nil")

    if not entry then
        -- Entry removed, hide overlay
        if overlayData and overlayData.container then
            overlayData.container:Hide()
        end
        return
    end

    if not entry.enabled then
        MedaBinds:Debug("RefreshExternalOverlay: entry disabled")
        if overlayData and overlayData.container then
            overlayData.container:Hide()
        end
        return
    end

    -- Create overlay if it doesn't exist
    -- Note: With the new independent container approach, we don't need to recreate
    -- when the frame changes - the OnUpdate handler will find the frame automatically
    if not overlayData then
        MedaBinds:Debug("RefreshExternalOverlay: creating overlay")
        self:CreateExternalOverlay(frame, uniqueKey)
        overlayData = externalOverlays[uniqueKey]
    end

    -- Update frame reference if provided
    if frame then
        externalFrameRefs[uniqueKey] = frame
        if overlayData then
            overlayData.frame = frame
        end
    end

    if not overlayData then
        MedaBinds:Debug("RefreshExternalOverlay: no overlayData after create attempt")
        return
    end

    local overlay = overlayData.overlay

    -- Determine text to display
    local displayText = nil
    if not entry.useAuto and entry.text and entry.text ~= "" then
        displayText = entry.text
        MedaBinds:Debug("RefreshExternalOverlay: using custom text:", displayText)
    else
        -- Try auto-detect
        MedaBinds:Debug("RefreshExternalOverlay: trying auto-detect, spellID:", entry.spellID, "itemID:", entry.itemID)
        if MedaBinds.KeybindScanner then
            if entry.spellID then
                displayText = MedaBinds.KeybindScanner:GetKeybindForSpell(entry.spellID)
            elseif entry.itemID then
                displayText = MedaBinds.KeybindScanner:GetKeybindForItem(entry.itemID)
            end
        end
        MedaBinds:Debug("RefreshExternalOverlay: auto-detected:", displayText or "none")
    end

    if not displayText or displayText == "" then
        MedaBinds:Debug("RefreshExternalOverlay: no text to display, hiding")
        overlayData.container:Hide()
        return
    end

    -- Get style
    local style = entry.style and CopyTable(MedaBinds.db.globalStyle) or MedaBinds.db.globalStyle
    if entry.style then
        for key, value in pairs(entry.style) do
            style[key] = value
        end
    end

    -- Apply style (use container as anchor since it matches target frame via SetAllPoints)
    ApplyStyleToOverlay(overlay, overlayData.container, style)
    overlay:SetText(displayText)
    overlay:Show()
    overlayData.container:Show()

    MedaBinds:Debug("RefreshExternalOverlay: text:", displayText, "for", uniqueKey)
end

-- Refresh all external overlays
function OverlayManager:RefreshAllExternalOverlays()
    for uniqueKey, entry in pairs(MedaBinds.db.externalIcons) do
        local overlayData = externalOverlays[uniqueKey]
        if overlayData then
            self:RefreshExternalOverlay(uniqueKey, overlayData.frame)
        end
    end
end

-- Track reconnection retry state
local reconnectRetryCount = 0
local MAX_RECONNECT_RETRIES = 10

-- Find and reconnect external icons after reload
function OverlayManager:ReconnectExternalIcons()
    reconnectRetryCount = 0
    self:DoReconnectExternalIcons()
end

-- Perform the actual reconnection attempt
function OverlayManager:DoReconnectExternalIcons()
    local totalIcons = self:CountExternalIcons()
    if totalIcons == 0 then
        return
    end

    local reconnected = 0
    local notFound = 0
    local alreadyConnected = 0

    MedaBinds:Debug("ReconnectExternalIcons: attempt", reconnectRetryCount + 1, "checking", totalIcons, "saved icons")

    for uniqueKey, entry in pairs(MedaBinds.db.externalIcons) do
        -- Check if already connected with valid overlay
        if externalFrameRefs[uniqueKey] and externalOverlays[uniqueKey] then
            -- Verify the existing overlay is still valid
            local existingData = externalOverlays[uniqueKey]
            if existingData.container and existingData.container:GetParent() then
                alreadyConnected = alreadyConnected + 1
            else
                -- Overlay lost its parent, need to reconnect
                externalOverlays[uniqueKey] = nil
                externalFrameRefs[uniqueKey] = nil
            end
        end

        -- If not connected, try to find the frame
        if not externalOverlays[uniqueKey] then
            local frame = nil

            -- Try to find the frame by name - but verify it's actually visible
            if entry.frameName then
                local candidate = _G[entry.frameName]
                -- Check if the frame is valid and visible (not a stale reference)
                if candidate and candidate.IsVisible and candidate:IsVisible() then
                    frame = candidate
                    MedaBinds:Debug("ReconnectExternalIcons: found visible frame", entry.frameName)
                elseif candidate then
                    MedaBinds:Debug("ReconnectExternalIcons: found frame but hidden", entry.frameName)
                    -- Try to find it as a child of known containers
                    frame = self:FindVisibleFrameByName(entry.frameName)
                end
            end

            if frame then
                externalFrameRefs[uniqueKey] = frame
                self:CreateExternalOverlay(frame, uniqueKey)
                reconnected = reconnected + 1
                MedaBinds:Debug("ReconnectExternalIcons: connected", entry.frameName)
            else
                notFound = notFound + 1
            end
        end
    end

    MedaBinds:Debug("ReconnectExternalIcons: connected", reconnected, "already", alreadyConnected, "not found", notFound)

    -- If some weren't found and we haven't exhausted retries, try again
    if notFound > 0 and reconnectRetryCount < MAX_RECONNECT_RETRIES then
        reconnectRetryCount = reconnectRetryCount + 1
        -- Increasing delay: 1s, 2s, 3s, etc up to 5s
        local delay = math.min(reconnectRetryCount, 5)
        C_Timer.After(delay, function()
            self:DoReconnectExternalIcons()
        end)
    elseif notFound > 0 then
        MedaBinds:Debug("ReconnectExternalIcons: gave up after", MAX_RECONNECT_RETRIES, "retries,", notFound, "icons not found")
    end
end

-- Count external icons in the database
function OverlayManager:CountExternalIcons()
    local count = 0
    for _ in pairs(MedaBinds.db.externalIcons) do
        count = count + 1
    end
    return count
end

-- Find a visible frame by name by searching through UI hierarchy
-- This handles cases where _G contains a stale reference but a new frame exists
function OverlayManager:FindVisibleFrameByName(frameName)
    if not frameName then return nil end

    -- Recursive search function
    local function SearchChildren(parent, depth)
        if depth > 5 then return nil end  -- Limit depth to avoid performance issues

        local ok, children = pcall(function() return {parent:GetChildren()} end)
        if not ok or not children then return nil end

        for _, child in ipairs(children) do
            local ok2, childName = pcall(function() return child:GetName() end)
            if ok2 and childName == frameName then
                local ok3, isVisible = pcall(function() return child:IsVisible() end)
                if ok3 and isVisible then
                    return child
                end
            end
            -- Recurse into children
            local found = SearchChildren(child, depth + 1)
            if found then return found end
        end
        return nil
    end

    -- Search from UIParent
    local found = SearchChildren(UIParent, 0)
    if found then
        MedaBinds:Debug("FindVisibleFrameByName: found", frameName, "in UI hierarchy")
    end
    return found
end

-- Manual reconnect command (can be called via /mbinds reconnect)
function OverlayManager:ForceReconnectExternalIcons()
    reconnectRetryCount = 0
    print("|cFF00FF00MedaBinds:|r Forcing reconnection of external icons...")
    self:DoReconnectExternalIcons()
end

-- Remove an external icon from tracking
function OverlayManager:RemoveExternalIcon(uniqueKey)
    local overlayData = externalOverlays[uniqueKey]
    if overlayData then
        if overlayData.container then
            -- Clean up watcher frame
            if overlayData.container.watcher then
                overlayData.container.watcher:SetScript("OnUpdate", nil)
                overlayData.container.watcher:Hide()
                overlayData.container.watcher:SetParent(nil)
            end
            overlayData.container:Hide()
            overlayData.container:SetParent(nil)
        end
        externalOverlays[uniqueKey] = nil
    end
    externalFrameRefs[uniqueKey] = nil
    MedaBinds.db.externalIcons[uniqueKey] = nil
end

-- Get the frame reference for an external icon (from runtime table)
function OverlayManager:GetExternalFrameRef(uniqueKey)
    return externalFrameRefs[uniqueKey]
end

-- Get the overlay data for an external icon (for debugging)
function OverlayManager:GetExternalOverlayData(uniqueKey)
    return externalOverlays[uniqueKey]
end

-- Set the frame reference for an external icon (in runtime table only)
function OverlayManager:SetExternalFrameRef(uniqueKey, frame)
    externalFrameRefs[uniqueKey] = frame
end

-- Get all external icons
function OverlayManager:GetExternalIcons()
    return MedaBinds.db.externalIcons
end
