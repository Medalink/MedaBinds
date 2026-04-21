--[[
    MedaBinds - ConfigMode.lua
    Click-to-configure interaction and icon editor dialog
]]

local addonName, MedaBinds = ...

-- ConfigMode module
local ConfigMode = {}
MedaBinds.ConfigMode = ConfigMode

-- Get MedaUI library for theming and widgets
local MedaUI = LibStub("MedaUI-2.0")

-- State
local isConfigModeActive = false
local isInspectionMode = false
local editorFrame = nil
local currentEditSpellID = nil
local currentEditExternalKey = nil
local lastInspectedFrame = nil

-- Forward declarations
local CreateEditorFrame, UpdateEditorContent, UpdateLivePreview, UpdateExternalEditorContent

-- Get theme from MedaUI
local function GetTheme()
    return MedaUI:GetTheme()
end

-- Get frame path for identification
local function GetFramePath(frame)
    if not frame then return nil end
    local path = {}
    local current = frame
    local depth = 0
    while current and depth < 10 do
        local name = current:GetName()
        if name then
            table.insert(path, 1, name)
            -- If we hit a named frame, we can stop (it's globally accessible)
            break
        else
            local parent = current:GetParent()
            if parent then
                -- Find index among siblings
                local index = 1
                for i, child in ipairs({parent:GetChildren()}) do
                    if child == current then
                        index = i
                        break
                    end
                end
                table.insert(path, 1, "[" .. index .. "]")
            end
        end
        current = current:GetParent()
        depth = depth + 1
    end
    return table.concat(path, ".")
end

-- Get frame source (addon name or "Blizzard") using generic prefix detection
local function GetFrameSource(frame)
    if not frame then return "Unknown" end

    -- Walk up parent chain looking for named frames
    local current = frame
    local depth = 0
    while current and depth < 15 do
        local name = current:GetName()
        if name then
            -- Check for Blizzard UI patterns first
            if name:match("^UI") or name:match("^Interface") or name:match("^Blizzard") then
                return "Blizzard"
            end
            if name:match("^Action") or name:match("^Spell") or name:match("^Buff") or name:match("^Debuff") then
                return "Blizzard"
            end
            if name:match("^Cooldown") and name:match("Viewer") then
                return "Blizzard Cooldowns"
            end

            -- Generic addon prefix extraction
            -- Extract the prefix before common separators (_, number, Frame, Button, Icon, Bar)
            local prefix = name:match("^([A-Z][a-z]+[A-Z]?[a-z]*)") -- CamelCase prefix
                        or name:match("^([A-Z]+)_")                  -- CAPS_prefix
                        or name:match("^([A-Za-z]+)%d")              -- prefix before number
                        or name:match("^([A-Za-z]+)Frame")           -- prefixFrame
                        or name:match("^([A-Za-z]+)Button")          -- prefixButton
                        or name:match("^([A-Za-z]+)Icon")            -- prefixIcon
                        or name:match("^([A-Za-z]+)Bar")             -- prefixBar

            if prefix and #prefix >= 3 then
                return prefix
            end
        end
        current = current:GetParent()
        depth = depth + 1
    end
    return "Unknown"
end

-- Detect spell/item info from any frame
local function DetectFrameInfo(frame)
    if not frame then return nil end

    local info = {
        frameName = frame:GetName(),
        framePath = GetFramePath(frame),
        source = GetFrameSource(frame),
        spellID = nil,
        itemID = nil,
        textureID = nil,
        name = nil,
    }

    -- Try various methods to get spell/item info

    -- Method 0: Generic ID extraction from frame name patterns
    -- Many addons use patterns like "AddonName_Type_ID" or "AddonNameID"
    if info.frameName then
        -- Try to find a numeric ID at the end of the frame name
        local idStr = info.frameName:match("_(%d+)$") or info.frameName:match("(%d+)$")
        local id = idStr and tonumber(idStr)
        if id and id > 100 then  -- Likely a spell/item ID, not just an index
            -- Try to determine if it's an item or spell
            local itemInfo = C_Item.GetItemInfo(id)
            if itemInfo then
                info.itemID = id
            else
                local spellInfo = C_Spell.GetSpellInfo(id)
                if spellInfo then
                    info.spellID = id
                end
            end
        end
    end

    -- Method 1: Direct properties
    if frame.spellID then
        info.spellID = frame.spellID
    end
    if frame.itemID then
        info.itemID = frame.itemID
    end
    if frame.spell then
        if type(frame.spell) == "number" then
            info.spellID = info.spellID or frame.spell
        elseif type(frame.spell) == "table" then
            info.spellID = info.spellID or frame.spell.spellID or frame.spell.id
        end
    end
    if frame.item then
        if type(frame.item) == "number" then
            info.itemID = info.itemID or frame.item
        elseif type(frame.item) == "table" then
            info.itemID = info.itemID or frame.item.itemID or frame.item.id
        end
    end

    -- Method 2: cooldownID (Blizzard CooldownViewer)
    if frame.cooldownID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local cvInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(frame.cooldownID)
        if cvInfo then
            info.spellID = info.spellID or cvInfo.spellID
            info.itemID = info.itemID or cvInfo.itemID
        end
    end

    -- Method 3: GetSpellID/GetItemID methods
    if not info.spellID and frame.GetSpellID and type(frame.GetSpellID) == "function" then
        local success, result = pcall(frame.GetSpellID, frame)
        if success and result then info.spellID = result end
    end
    if not info.itemID and frame.GetItemID and type(frame.GetItemID) == "function" then
        local success, result = pcall(frame.GetItemID, frame)
        if success and result then info.itemID = result end
    end

    -- Method 4: Action button info (covers most action bar addons)
    if frame.action then
        local actionType, id = GetActionInfo(frame.action)
        if actionType == "spell" then
            info.spellID = info.spellID or id
        elseif actionType == "item" then
            info.itemID = info.itemID or id
        elseif actionType == "macro" then
            -- Try to get spell/item from macro
            local macroSpell = GetMacroSpell and GetMacroSpell(id)
            if macroSpell then
                info.spellID = info.spellID or macroSpell
            end
            local macroItem = GetMacroItem and GetMacroItem(id)
            if macroItem then
                info.itemID = info.itemID or macroItem
            end
        end
    end

    -- Method 5: GetAction method (Bartender4, etc.)
    if not info.spellID and not info.itemID and frame.GetAction and type(frame.GetAction) == "function" then
        local success, action = pcall(frame.GetAction, frame)
        if success and action then
            local actionType, id = GetActionInfo(action)
            if actionType == "spell" then
                info.spellID = id
            elseif actionType == "item" then
                info.itemID = id
            end
        end
    end

    -- Method 6: Check for aura info
    if frame.auraInstanceID and C_UnitAuras then
        local auraInfo = C_UnitAuras.GetAuraDataByAuraInstanceID("player", frame.auraInstanceID)
        if auraInfo then
            info.spellID = info.spellID or auraInfo.spellId
        end
    end

    -- Method 8: Try to get texture
    local texture = nil
    if frame.icon and frame.icon.GetTexture then
        texture = frame.icon:GetTexture()
    elseif frame.Icon then
        if frame.Icon.GetTexture and type(frame.Icon.GetTexture) == "function" then
            texture = frame.Icon:GetTexture()
        elseif frame.Icon.icon and frame.Icon.icon.GetTexture then
            texture = frame.Icon.icon:GetTexture()
        end
    elseif frame.texture and frame.texture.GetTexture then
        texture = frame.texture:GetTexture()
    elseif frame.Texture and frame.Texture.GetTexture then
        texture = frame.Texture:GetTexture()
    elseif frame.GetTexture and type(frame.GetTexture) == "function" then
        texture = frame:GetTexture()
    end

    -- Check children for textures if not found
    if not texture then
        for _, child in ipairs({frame:GetRegions()}) do
            if child:IsObjectType("Texture") then
                local tex = child:GetTexture()
                if tex and type(tex) == "number" then
                    texture = tex
                    break
                end
            end
        end
    end
    info.textureID = texture

    -- Method 9: Try to match texture to known items (hearthstone, etc.)
    if not info.itemID and texture and type(texture) == "number" then
        -- Check common items by texture
        local commonItems = {
            [134414] = 6948,   -- Hearthstone
            [1669494] = 140192, -- Dalaran Hearthstone
            [463508] = 110560,  -- Garrison Hearthstone
        }
        if commonItems[texture] then
            info.itemID = commonItems[texture]
        end
    end

    -- Get name from spell/item info
    if info.spellID then
        local spellInfo = C_Spell.GetSpellInfo(info.spellID)
        info.name = spellInfo and spellInfo.name
    elseif info.itemID then
        local itemName = C_Item.GetItemInfo(info.itemID)
        info.name = itemName
    end

    -- Generate unique key (prefer named frames for persistence)
    if info.frameName then
        info.uniqueKey = "name:" .. info.frameName
    elseif info.spellID then
        info.uniqueKey = "spell:" .. info.spellID .. ":" .. (info.framePath or "unknown")
    elseif info.itemID then
        info.uniqueKey = "item:" .. info.itemID .. ":" .. (info.framePath or "unknown")
    elseif info.textureID then
        info.uniqueKey = "tex:" .. tostring(info.textureID) .. ":" .. (info.framePath or "unknown")
    else
        info.uniqueKey = "path:" .. (info.framePath or tostring(frame))
    end

    return info
end

-- Helper to check if cursor is over a frame (manual hit-test for frames with EnableMouse(false))
local function IsCursorOverFrame(frame)
    if not frame then return false end

    -- Get frame position - if GetRect returns nil, frame isn't rendered
    local ok, left, bottom, width, height = pcall(function() return frame:GetRect() end)
    if not ok or not left or not width or width <= 0 or height <= 0 then return false end

    -- Get cursor position and scale
    local cx, cy = GetCursorPosition()
    local ok2, scale = pcall(function() return frame:GetEffectiveScale() end)
    if not ok2 or not scale or scale <= 0 then return false end

    cx, cy = cx / scale, cy / scale

    local right = left + width
    local top = bottom + height

    return cx >= left and cx <= right and cy >= bottom and cy <= top
end

-- Cache for discovered icon frames (refreshed periodically)
local iconFrameCache = {}
local iconCacheTime = 0
local ICON_CACHE_DURATION = 5  -- Refresh every 5 seconds (scanning is expensive)

-- Helper to check if a frame looks like an icon (generic detection based on properties only)
local function IsIconLikeFrame(frame)
    if not frame then return false end

    -- Must be visible
    local ok, visible = pcall(function() return frame:IsVisible() end)
    if not ok or not visible then return false end

    -- Check for common icon indicators - no size restrictions, purely property-based

    -- Has Icon/icon property (most common pattern for addon icons)
    -- Just check if the property exists - don't require texture to be set
    if frame.Icon then return true end
    if frame.icon then return true end

    -- Has Cooldown property (strong indicator of spell/item icon)
    if frame.Cooldown then return true end

    -- Has texture children that look like icon textures (numeric texture ID = spell/item art)
    local ok2, regions = pcall(function() return {frame:GetRegions()} end)
    if ok2 and regions then
        for _, region in ipairs(regions) do
            local isTexture = pcall(function() return region:IsObjectType("Texture") end)
            if isTexture then
                local ok3, tex = pcall(function() return region:GetTexture() end)
                if ok3 and tex and type(tex) == "number" then
                    return true
                end
            end
        end
    end

    -- Check for Cooldown child frames
    local ok4, children = pcall(function() return {frame:GetChildren()} end)
    if ok4 and children then
        for _, child in ipairs(children) do
            local ok5, isCooldown = pcall(function() return child:IsObjectType("Cooldown") end)
            if ok5 and isCooldown then
                return true
            end
        end
    end

    return false
end

-- Recursively scan frame and children for icon-like frames
local function ScanFrameForIcons(frame, results, depth)
    if not frame or depth > 6 then return end  -- Limit depth to reduce scan time

    -- Safety check: wrap all frame method calls in pcall since some UI elements can be in invalid states
    local ok, name = pcall(function() return frame:GetName() end)
    if not ok then return end

    -- Ensure name is actually a string (some frames return non-string values)
    if name and type(name) == "string" then
        if name:match("^MedaBinds") then return end
        if name == "WorldFrame" or name == "UIParent" then return end
        -- Skip common non-icon UI elements for performance
        if name:match("Tooltip") then return end
        if name:match("^GameMenu") then return end
        if name:match("^Chat") then return end
        if name:match("^Minimap") and not name:match("Button") then return end
        if name:match("^World") then return end
        if name:match("^Movie") then return end
        if name:match("^Cinematic") then return end
    end

    -- Skip invisible frames early
    local ok1, visible = pcall(function() return frame:IsVisible() end)
    if ok1 and not visible then return end

    -- Check if this frame is an icon
    if IsIconLikeFrame(frame) then
        table.insert(results, frame)
        return  -- Don't recurse into icons (they contain the content, not more icons)
    end

    -- Recursively check children (also wrapped for safety)
    local ok2, children = pcall(function() return {frame:GetChildren()} end)
    if not ok2 or not children then return end

    for _, child in ipairs(children) do
        ScanFrameForIcons(child, results, depth + 1)
    end
end

-- Build cache of all visible icon-like frames
local function RefreshIconCache()
    local now = GetTime()
    if now - iconCacheTime < ICON_CACHE_DURATION then
        return iconFrameCache
    end

    iconCacheTime = now
    wipe(iconFrameCache)

    -- Scan children of UIParent (all top-level frames)
    local topLevelFrames = {UIParent:GetChildren()}
    for _, frame in ipairs(topLevelFrames) do
        ScanFrameForIcons(frame, iconFrameCache, 0)
    end

    return iconFrameCache
end

-- Find any icon-like frame under cursor (for frames with EnableMouse=false)
local function GetIconFromPositionScan()
    local frames = RefreshIconCache()

    -- Check each cached icon frame for cursor overlap
    -- Don't check IsVisible() here since some frames report visibility inconsistently
    -- IsCursorOverFrame already checks visibility
    for _, frame in ipairs(frames) do
        if IsCursorOverFrame(frame) then
            return frame
        end
    end

    return nil
end

-- Get any icon-like frame at cursor (for inspection mode)
local function GetAnyIconAtCursor()
    local frames = GetMouseFoci and GetMouseFoci() or (GetMouseFocus and {GetMouseFocus()} or {})

    -- Helper to check if frame has icon-like properties
    local function HasIconProperties(frame)
        if not frame then return false end

        -- Direct texture properties
        if frame.icon or frame.Icon or frame.texture or frame.Texture then
            return true
        end

        -- Common addon properties
        if frame.cooldownID or frame.spellID or frame.itemID or frame.spell or frame.item then
            return true
        end

        -- Action button properties
        if frame.action or frame.GetAction then
            return true
        end

        -- Is a texture itself
        if frame:IsObjectType("Texture") and frame:GetTexture() then
            return true
        end

        -- Has texture children
        local regions = {frame:GetRegions()}
        for _, child in ipairs(regions) do
            if child:IsObjectType("Texture") then
                local tex = child:GetTexture()
                if tex then
                    return true
                end
            end
        end

        -- Check for cooldown child (indicates action/spell icon)
        local children = {frame:GetChildren()}
        for _, child in ipairs(children) do
            if child:IsObjectType("Cooldown") then
                return true
            end
            -- Nested icon frame
            if child.icon or child.Icon then
                return true
            end
        end

        return false
    end

    -- Helper to check frame size is reasonable for an icon
    local function IsReasonableSize(frame)
        if not frame then return false end
        local width, height = frame:GetSize()
        -- More permissive size range (8-300 pixels)
        return width and height and width >= 8 and width <= 300 and height >= 8 and height <= 300
    end

    -- First, check frames detected by GetMouseFoci (normal mouse-enabled frames)
    for _, frame in ipairs(frames) do
        if frame and frame ~= WorldFrame and frame ~= UIParent and frame:GetName() ~= "MedaBindsConfigHighlight" then
            -- Check the frame itself
            if IsReasonableSize(frame) and HasIconProperties(frame) then
                return frame
            end

            -- Check parent (icon might be nested in a button)
            local parent = frame:GetParent()
            if parent and parent ~= WorldFrame and parent ~= UIParent then
                if IsReasonableSize(parent) and HasIconProperties(parent) then
                    return parent
                end

                -- Check grandparent
                local grandparent = parent:GetParent()
                if grandparent and grandparent ~= WorldFrame and grandparent ~= UIParent then
                    if IsReasonableSize(grandparent) and HasIconProperties(grandparent) then
                        return grandparent
                    end
                end
            end

            -- If frame is small, it might be a sub-element - try to find the icon container
            local width, height = frame:GetSize()
            if width and height and (width < 10 or height < 10) then
                -- Walk up looking for an icon
                local current = frame:GetParent()
                local depth = 0
                while current and depth < 5 do
                    if current ~= WorldFrame and current ~= UIParent then
                        if IsReasonableSize(current) and HasIconProperties(current) then
                            return current
                        end
                    end
                    current = current:GetParent()
                    depth = depth + 1
                end
            end
        end
    end

    -- Second, do a position-based scan for frames with EnableMouse(false)
    local scannedIcon = GetIconFromPositionScan()
    if scannedIcon then
        return scannedIcon
    end

    return nil
end

-- Check if the correct modifier key is held
local function IsModifierHeld()
    local modifier = MedaBinds.db.options.configModifierKey or "ALT"
    if modifier == "ALT" then
        return IsAltKeyDown()
    elseif modifier == "CTRL" then
        return IsControlKeyDown()
    elseif modifier == "SHIFT" then
        return IsShiftKeyDown()
    end
    return false
end

-- Config mode indicator frame
local indicatorFrame = nil
local hoverHighlight = nil
local lastHoveredIcon = nil
local UpdateIndicator  -- Forward declaration

local function CreateIndicator()
    if indicatorFrame then return indicatorFrame end

    -- Get theme
    local THEME = GetTheme()

    indicatorFrame = CreateFrame("Frame", "MedaBindsConfigIndicator", UIParent, "BackdropTemplate")
    indicatorFrame:SetSize(480, 115)
    indicatorFrame:SetPoint("TOP", UIParent, "TOP", 0, -80)
    indicatorFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    indicatorFrame:SetClampedToScreen(true)
    indicatorFrame:SetMovable(true)
    indicatorFrame:EnableMouse(true)
    indicatorFrame:RegisterForDrag("LeftButton")
    indicatorFrame:SetScript("OnDragStart", indicatorFrame.StartMoving)
    indicatorFrame:SetScript("OnDragStop", indicatorFrame.StopMovingOrSizing)

    -- Dark themed background (matching main window)
    indicatorFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    indicatorFrame:SetBackdropColor(unpack(THEME.background))

    -- Title bar (matching main window style)
    local titleBar = CreateFrame("Frame", nil, indicatorFrame, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(28)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    titleBar:SetBackdropColor(unpack(THEME.backgroundLight))

    -- Title text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", 12, 0)
    titleText:SetText("Config Mode")
    titleText:SetTextColor(unpack(THEME.gold))

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", -4, 0)
    closeBtn:SetNormalFontObject("GameFontNormal")
    closeBtn:SetText("x")
    closeBtn:GetFontString():SetTextColor(unpack(THEME.textDim))
    closeBtn:SetScript("OnClick", function()
        ConfigMode:Disable()
    end)
    closeBtn:SetScript("OnEnter", function(self)
        self:GetFontString():SetTextColor(1, 0.4, 0.4, 1)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:GetFontString():SetTextColor(unpack(THEME.textDim))
    end)

    -- Instructions
    local instructions = indicatorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("TOP", titleBar, "BOTTOM", 0, -12)
    instructions:SetWidth(460)
    instructions:SetJustifyH("CENTER")
    instructions:SetTextColor(unpack(THEME.text))
    indicatorFrame.instructions = instructions

    -- Hint text
    local hint = indicatorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOP", instructions, "BOTTOM", 0, -8)
    hint:SetWidth(460)
    hint:SetJustifyH("CENTER")
    hint:SetTextColor(unpack(THEME.textDim))
    hint:SetText("Hover over cooldown icons to highlight them. Press ESC to exit.")
    indicatorFrame.hint = hint

    -- Status text (shows current hovered icon)
    local status = indicatorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("BOTTOMLEFT", indicatorFrame, "BOTTOMLEFT", 10, 10)
    status:SetWidth(330)
    status:SetJustifyH("LEFT")
    status:SetTextColor(unpack(THEME.gold))
    status:SetText("")
    indicatorFrame.status = status

    -- Helper to create a themed button
    local function CreateIndicatorButton(text, width)
        local btn = CreateFrame("Button", nil, indicatorFrame, "BackdropTemplate")
        btn:SetSize(width, 22)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(unpack(THEME.button))
        btn:SetBackdropBorderColor(unpack(THEME.border))

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btnText:SetPoint("CENTER")
        btnText:SetText(text)
        btnText:SetTextColor(unpack(THEME.text))
        btn.text = btnText

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(unpack(THEME.buttonHover))
            btnText:SetTextColor(unpack(THEME.gold))
        end)
        btn:SetScript("OnLeave", function(self)
            if not self.isActive then
                self:SetBackdropColor(unpack(THEME.button))
                self:SetBackdropBorderColor(unpack(THEME.border))
            end
            btnText:SetTextColor(unpack(self.isActive and THEME.gold or THEME.text))
        end)

        btn.SetActive = function(self, active)
            self.isActive = active
            if active then
                self:SetBackdropColor(unpack(THEME.backgroundDark))
                self:SetBackdropBorderColor(unpack(THEME.gold))
                btnText:SetTextColor(unpack(THEME.gold))
            else
                self:SetBackdropColor(unpack(THEME.button))
                self:SetBackdropBorderColor(unpack(THEME.border))
                btnText:SetTextColor(unpack(THEME.text))
            end
        end

        return btn
    end

    -- Inspection mode toggle button
    local inspectBtn = CreateIndicatorButton("Inspection Mode", 120)
    inspectBtn:SetPoint("BOTTOMRIGHT", indicatorFrame, "BOTTOMRIGHT", -10, 8)
    inspectBtn:SetScript("OnClick", function(self)
        isInspectionMode = not isInspectionMode
        self:SetActive(isInspectionMode)
        UpdateIndicator()

        if isInspectionMode then
            print("|cFF00FF00MedaBinds:|r Inspection mode enabled. Hover any icon to inspect it.")
        else
            print("|cFF00FF00MedaBinds:|r Inspection mode disabled.")
        end
    end)
    indicatorFrame.inspectBtn = inspectBtn

    indicatorFrame:Hide()
    return indicatorFrame
end

-- Create hover highlight frame
local function CreateHoverHighlight()
    if hoverHighlight then return hoverHighlight end

    hoverHighlight = CreateFrame("Frame", "MedaBindsConfigHighlight", UIParent, "BackdropTemplate")
    hoverHighlight:SetFrameStrata("FULLSCREEN")
    hoverHighlight:EnableMouse(false)  -- Don't intercept mouse clicks
    hoverHighlight:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    hoverHighlight:SetBackdropBorderColor(0.9, 0.7, 0.15, 1)  -- Gold border

    -- Inner glow
    local glow = hoverHighlight:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT", -4, 4)
    glow:SetPoint("BOTTOMRIGHT", 4, -4)
    glow:SetColorTexture(0.9, 0.7, 0.15, 0.25)  -- Subtle gold glow
    hoverHighlight.glow = glow

    -- Pulsing animation
    local pulseTime = 0
    hoverHighlight:SetScript("OnUpdate", function(self, elapsed)
        pulseTime = pulseTime + elapsed
        local alpha = 0.15 + 0.15 * math.sin(pulseTime * 4)  -- Pulse between 0.15 and 0.30
        glow:SetColorTexture(0.9, 0.7, 0.15, alpha)

        local borderAlpha = 0.8 + 0.2 * math.sin(pulseTime * 4)
        self:SetBackdropBorderColor(0.9, 0.7, 0.15, borderAlpha)
    end)

    hoverHighlight:Hide()
    return hoverHighlight
end

-- Update hover highlight position
local function UpdateHoverHighlight(icon)
    if not icon then
        if hoverHighlight then
            hoverHighlight:Hide()
        end
        lastHoveredIcon = nil
        lastInspectedFrame = nil
        if indicatorFrame and indicatorFrame.status then
            indicatorFrame.status:SetText("")
        end
        return
    end

    local highlight = CreateHoverHighlight()

    -- Position highlight around the icon
    highlight:ClearAllPoints()
    highlight:SetPoint("TOPLEFT", icon, "TOPLEFT", -3, 3)
    highlight:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 3, -3)
    highlight:Show()

    lastHoveredIcon = icon

    -- Update status text
    if indicatorFrame and indicatorFrame.status then
        if isInspectionMode then
            -- Show detailed frame info for inspection mode
            local info = DetectFrameInfo(icon)
            lastInspectedFrame = info
            if info then
                local statusParts = {}

                -- Source
                table.insert(statusParts, info.source)

                -- Name or ID
                if info.name then
                    table.insert(statusParts, info.name)
                elseif info.spellID then
                    table.insert(statusParts, "SpellID:" .. info.spellID)
                elseif info.itemID then
                    table.insert(statusParts, "ItemID:" .. info.itemID)
                end

                -- Frame name if available
                if info.frameName then
                    table.insert(statusParts, "[" .. info.frameName .. "]")
                elseif info.framePath then
                    -- Show shortened path
                    local shortPath = info.framePath
                    if #shortPath > 30 then
                        shortPath = "..." .. shortPath:sub(-27)
                    end
                    table.insert(statusParts, "[" .. shortPath .. "]")
                end

                indicatorFrame.status:SetText(table.concat(statusParts, " | "))
            else
                -- Show raw frame info for debugging
                local frameName = icon:GetName() or "unnamed"
                local objType = icon:GetObjectType()
                indicatorFrame.status:SetText("Frame: " .. frameName .. " (" .. objType .. ")")
            end
        else
            -- Standard mode - show spell info
            local spellInfo = MedaBinds.OverlayManager:GetSpellInfoFromIcon(icon)
            if spellInfo then
                indicatorFrame.status:SetText("Hovering: " .. spellInfo.name)
            else
                indicatorFrame.status:SetText("Hovering: Unknown Icon")
            end
        end
    end
end

-- Update indicator text
UpdateIndicator = function()
    if not indicatorFrame then return end
    local modifier = MedaBinds.db.options.configModifierKey or "ALT"

    if isInspectionMode then
        indicatorFrame.instructions:SetText("INSPECTION MODE: Hover ANY icon to detect it.")
        indicatorFrame.hint:SetText(modifier .. "+Click to add icon to tracked list. Press ESC to exit.")
    else
        indicatorFrame.instructions:SetText(modifier .. "+Click on any cooldown icon to customize its keybind text and style.")
        indicatorFrame.hint:SetText("Hover over cooldown icons to highlight them. Press ESC to exit.")
    end
end

-- Enter config mode
function ConfigMode:Enable()
    if isConfigModeActive then return end

    -- Check combat
    if InCombatLockdown() and MedaBinds.db.options.autoDisableInCombat then
        print("|cFF00FF00MedaBinds:|r Cannot enter config mode during combat.")
        return
    end

    isConfigModeActive = true

    -- Hide settings panel if open
    if MedaBinds.SettingsPanel and MedaBinds.SettingsPanel.Hide then
        MedaBinds.SettingsPanel:Hide()
    end

    -- Show indicator
    local indicator = CreateIndicator()
    UpdateIndicator()
    indicator:Show()

    -- Start watching for clicks and hover on CooldownViewer icons
    self:StartClickWatch()

    MedaBinds:Debug("ConfigMode: Enabled")
end

-- Exit config mode
function ConfigMode:Disable()
    if not isConfigModeActive then return end

    isConfigModeActive = false
    isInspectionMode = false

    -- Hide indicator
    if indicatorFrame then
        indicatorFrame:Hide()
        if indicatorFrame.inspectBtn then
            indicatorFrame.inspectBtn:SetActive(false)
        end
    end

    -- Hide hover highlight
    if hoverHighlight then
        hoverHighlight:Hide()
    end
    lastHoveredIcon = nil
    lastInspectedFrame = nil

    -- Stop watching for clicks
    self:StopClickWatch()

    MedaBinds:Debug("ConfigMode: Disabled")
    print("|cFF00FF00MedaBinds:|r Config mode disabled.")
end

-- Toggle config mode
function ConfigMode:Toggle()
    if isConfigModeActive then
        self:Disable()
    else
        self:Enable()
    end
end

-- Check if config mode is active
function ConfigMode:IsActive()
    return isConfigModeActive
end

-- Check if inspection mode is active
function ConfigMode:IsInspectionMode()
    return isInspectionMode
end

-- Add an external icon to the tracked list
function ConfigMode:AddExternalIcon(frame, info)
    if not frame then return end

    -- If no info provided, create basic info from frame
    if not info then
        info = DetectFrameInfo(frame)
    end

    -- If still no info, create minimal info
    if not info then
        info = {
            frameName = frame:GetName(),
            framePath = GetFramePath(frame),
            source = GetFrameSource(frame),
            uniqueKey = "frame:" .. (frame:GetName() or tostring(frame)),
        }
    end

    -- Check if already tracked
    if MedaBinds.db.externalIcons[info.uniqueKey] then
        print("|cFF00FF00MedaBinds:|r This icon is already being tracked.")

        -- Update frame reference in case it changed or wasn't set
        if MedaBinds.OverlayManager then
            MedaBinds.OverlayManager:SetExternalFrameRef(info.uniqueKey, frame)

            -- Make sure overlay exists and is properly parented
            MedaBinds.OverlayManager:RefreshExternalOverlay(info.uniqueKey, frame)
        end

        -- Open editor for existing entry
        self:OpenExternalEditor(info.uniqueKey, frame)
        return
    end

    -- Create entry for external icon
    local entry = {
        framePath = info.framePath,
        frameName = info.frameName,
        source = info.source or "Unknown",
        spellID = info.spellID,
        itemID = info.itemID,
        textureID = info.textureID,
        text = "",
        useAuto = false,  -- Default to custom text for external icons without spell/item
        style = nil,
        enabled = true,
    }

    -- If we have spell/item info, default to auto-detect
    if info.spellID or info.itemID then
        entry.useAuto = true
    end

    MedaBinds.db.externalIcons[info.uniqueKey] = entry

    -- Store reference to actual frame in runtime table (NOT in db - frames can't be serialized)
    if MedaBinds.OverlayManager then
        MedaBinds.OverlayManager:SetExternalFrameRef(info.uniqueKey, frame)
    end

    local displayName = info.name or info.frameName or info.framePath or "Unknown Icon"
    print("|cFF00FF00MedaBinds:|r Added external icon: " .. displayName .. " (from " .. (info.source or "Unknown") .. ")")
    MedaBinds:Debug("ConfigMode: Added external icon with key:", info.uniqueKey, "frameName:", info.frameName)

    -- Create overlay on the icon
    if MedaBinds.OverlayManager then
        MedaBinds.OverlayManager:CreateExternalOverlay(frame, info.uniqueKey)
    end

    -- Open editor for the new entry
    self:OpenExternalEditor(info.uniqueKey, frame)
end

-- Open editor for an external icon
function ConfigMode:OpenExternalEditor(uniqueKey, frame)
    local entry = MedaBinds.db.externalIcons[uniqueKey]
    if not entry then return end

    -- Store current edit context
    currentEditSpellID = nil
    currentEditExternalKey = uniqueKey

    -- Create or get editor frame
    local editorFrame = CreateEditorFrame()

    -- Update editor for external icon
    UpdateExternalEditorContent(uniqueKey, entry, frame)

    editorFrame:Show()
end

-- Click watcher frame
local clickWatcher = nil
local hoverUpdateInterval = 0
local HOVER_UPDATE_RATE = 0.1  -- Update hover every 100ms (was 50ms)
local positionScanInterval = 0
local POSITION_SCAN_RATE = 0.25  -- Position scan every 250ms (expensive operation)

-- Start watching for clicks and hover
function ConfigMode:StartClickWatch()
    if not clickWatcher then
        clickWatcher = CreateFrame("Frame", nil, UIParent)
        clickWatcher:EnableMouse(false)
    end

    -- Register ESC key to exit config mode
    clickWatcher:EnableKeyboard(true)
    clickWatcher:SetPropagateKeyboardInput(true)
    clickWatcher:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and isConfigModeActive then
            ConfigMode:Disable()
            self:SetPropagateKeyboardInput(false)
            return
        end
        self:SetPropagateKeyboardInput(true)
    end)

    -- Main update handler for clicks and hover
    clickWatcher:SetScript("OnUpdate", function(self, elapsed)
        if not isConfigModeActive then return end

        -- Throttle hover updates
        hoverUpdateInterval = hoverUpdateInterval + elapsed
        positionScanInterval = positionScanInterval + elapsed

        local updateRate = isInspectionMode and POSITION_SCAN_RATE or HOVER_UPDATE_RATE
        if hoverUpdateInterval >= updateRate then
            hoverUpdateInterval = 0

            -- Update hover highlight based on mode
            local icon
            if isInspectionMode then
                -- Inspection mode: use expensive position scan less frequently
                icon = GetAnyIconAtCursor()
            else
                icon = MedaBinds.OverlayManager:GetIconAtCursor()
            end

            if icon ~= lastHoveredIcon then
                UpdateHoverHighlight(icon)
            end
        end

        -- Check for mouse click with modifier
        if IsMouseButtonDown("LeftButton") and IsModifierHeld() then
            if not self.clickProcessed then
                self.clickProcessed = true

                if isInspectionMode then
                    -- Inspection mode: add external icon
                    local icon = GetAnyIconAtCursor()
                    if icon and lastInspectedFrame then
                        ConfigMode:AddExternalIcon(icon, lastInspectedFrame)
                    end
                else
                    -- Standard mode: open editor for cooldown viewer icon
                    local icon = MedaBinds.OverlayManager:GetIconAtCursor()
                    if icon then
                        local spellInfo = MedaBinds.OverlayManager:GetSpellInfoFromIcon(icon)
                        if spellInfo then
                            ConfigMode:OpenEditor(spellInfo.spellID, icon)
                        end
                    end
                end
            end
        else
            self.clickProcessed = false
        end
    end)
end

-- Stop watching for clicks
function ConfigMode:StopClickWatch()
    if clickWatcher then
        clickWatcher:SetScript("OnUpdate", nil)
        clickWatcher:SetScript("OnKeyDown", nil)
        clickWatcher:EnableKeyboard(false)
    end
end

-- Local helper to create themed radio button (uses MedaUI)
local function CreateThemedRadio(parent, theme)
    return MedaUI:CreateRadio(parent)
end

-- Local helper to create themed checkbox (uses MedaUI)
local function CreateThemedCheckbox(parent, theme)
    return MedaUI:CreateCheckbox(parent)
end

-- Local helper to create themed edit box (uses MedaUI)
local function CreateThemedEditBox(parent, width, height, theme)
    return MedaUI:CreateEditBox(parent, width, height)
end

-- Local helper to create themed slider (uses MedaUI)
local function CreateThemedSlider(parent, width, minVal, maxVal, step, theme)
    return MedaUI:CreateSlider(parent, width, minVal, maxVal, step)
end

-- Update live preview on the actual icon overlay
UpdateLivePreview = function()
    if not editorFrame or not currentEditSpellID then return end
    if not MedaBinds.OverlayManager then return end

    -- Build temporary style/text settings from current editor state
    local text = nil
    local useAuto = true

    if editorFrame.useCustomRadio:GetChecked() then
        useAuto = false
        text = editorFrame.customEditBox:GetText()
        if text == "" then text = nil end
    end

    local style = nil
    if not editorFrame.useGlobalCheck:GetChecked() then
        style = {
            fontSize = editorFrame.fontSizeSlider:GetValue(),
            color = CopyTable(editorFrame.colorPicker:GetColor()),
        }
    end

    -- Apply preview to the overlay (temporary, not saved to DB)
    MedaBinds.OverlayManager:PreviewSpellOverlay(currentEditSpellID, text, useAuto, style)
end

-- Create the editor frame
CreateEditorFrame = function()
    if editorFrame then return editorFrame end

    -- If the global frame exists from a previous session, destroy it
    -- This ensures widgets are recreated with current code
    if _G["MedaBindsIconEditor"] then
        _G["MedaBindsIconEditor"]:Hide()
        _G["MedaBindsIconEditor"]:SetParent(nil)
        _G["MedaBindsIconEditor"] = nil
    end

    local THEME = GetTheme()

    local frame = CreateFrame("Frame", "MedaBindsIconEditor", UIParent, "BackdropTemplate")
    frame:SetSize(380, 520)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Allow ESC to close the editor
    tinsert(UISpecialFrames, "MedaBindsIconEditor")

    -- Dark background with subtle border
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(unpack(THEME.background))
    frame:SetBackdropBorderColor(unpack(THEME.border))

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(28)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    titleBar:SetBackdropColor(unpack(THEME.backgroundLight))

    -- Title text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", 10, 0)
    titleText:SetText("Edit Keybind Overlay")
    titleText:SetTextColor(unpack(THEME.gold))

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", -4, 0)
    closeBtn:SetNormalFontObject("GameFontNormal")
    closeBtn:SetText("x")
    closeBtn:GetFontString():SetTextColor(unpack(THEME.textDim))
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    closeBtn:SetScript("OnEnter", function(self) self:GetFontString():SetTextColor(unpack(THEME.closeHover)) end)
    closeBtn:SetScript("OnLeave", function(self) self:GetFontString():SetTextColor(unpack(THEME.textDim)) end)

    -- Content area background (visual only)
    local contentBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    contentBg:SetPoint("TOPLEFT", 1, -30)
    contentBg:SetPoint("BOTTOMRIGHT", -1, 1)
    contentBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    contentBg:SetBackdropColor(unpack(THEME.backgroundDark))
    contentBg:SetFrameLevel(frame:GetFrameLevel())  -- Behind other elements

    local yOffset = -46

    -- Spell info display
    local spellLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spellLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)
    spellLabel:SetText("Spell: ")
    spellLabel:SetTextColor(unpack(THEME.text))
    frame.spellLabel = spellLabel
    yOffset = yOffset - 32

    local viewerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    viewerLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)
    viewerLabel:SetText("Viewer: ")
    viewerLabel:SetTextColor(unpack(THEME.textDim))
    frame.viewerLabel = viewerLabel
    yOffset = yOffset - 26

    -- Auto-detected keybind display
    local detectedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detectedLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)
    detectedLabel:SetText("Keybind: ")
    detectedLabel:SetTextColor(unpack(THEME.text))
    frame.detectedLabel = detectedLabel
    yOffset = yOffset - 18

    local abbreviatedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    abbreviatedLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)
    abbreviatedLabel:SetText("Abbreviated: ")
    abbreviatedLabel:SetTextColor(unpack(THEME.textGreen))
    frame.abbreviatedLabel = abbreviatedLabel
    yOffset = yOffset - 18

    -- Bar/slot info display
    local barSlotLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    barSlotLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)
    barSlotLabel:SetText("Location: ")
    barSlotLabel:SetTextColor(unpack(THEME.textDim))
    frame.barSlotLabel = barSlotLabel
    yOffset = yOffset - 28

    -- Keybind Text section header
    local keybindSection = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keybindSection:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)
    keybindSection:SetText("Keybind Text")
    keybindSection:SetTextColor(unpack(THEME.gold))
    yOffset = yOffset - 26

    -- Custom text input (themed)
    local customEditBox = CreateThemedEditBox(frame, 200, 28, THEME)
    customEditBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)
    frame.customEditBox = customEditBox
    yOffset = yOffset - 36

    -- Radio buttons for text source (themed)
    local useCustomRadio = CreateThemedRadio(frame, THEME)
    useCustomRadio:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)
    local useCustomLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    useCustomLabel:SetPoint("LEFT", frame, "TOPLEFT", 36, yOffset)
    useCustomLabel:SetText("Use custom text")
    useCustomLabel:SetTextColor(unpack(THEME.text))
    useCustomRadio.text = useCustomLabel
    frame.useCustomRadio = useCustomRadio
    yOffset = yOffset - 26

    local useAutoRadio = CreateThemedRadio(frame, THEME)
    useAutoRadio:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)
    local useAutoLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    useAutoLabel:SetPoint("LEFT", frame, "TOPLEFT", 36, yOffset)
    useAutoLabel:SetText("Use auto-detected keybind")
    useAutoLabel:SetTextColor(unpack(THEME.text))
    useAutoRadio.text = useAutoLabel
    frame.useAutoRadio = useAutoRadio
    yOffset = yOffset - 38

    -- Radio button behavior
    useCustomRadio:SetScript("OnClick", function()
        useCustomRadio:SetChecked(true)
        useAutoRadio:SetChecked(false)
        customEditBox:Enable()
        customEditBox:SetFocus()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        UpdateLivePreview()
    end)

    useAutoRadio:SetScript("OnClick", function()
        useAutoRadio:SetChecked(true)
        useCustomRadio:SetChecked(false)
        customEditBox:Disable()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        UpdateLivePreview()
    end)

    -- Auto-select custom text when clicking on the input field
    customEditBox.editBox:SetScript("OnEditFocusGained", function()
        useCustomRadio:SetChecked(true)
        useAutoRadio:SetChecked(false)
        customEditBox:Enable()
        customEditBox:SetBackdropBorderColor(unpack(THEME.gold))
    end)

    -- Live preview on text change
    customEditBox.editBox:SetScript("OnTextChanged", function()
        if useCustomRadio:GetChecked() then
            UpdateLivePreview()
        end
    end)

    -- Style Override section header
    local styleSection = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    styleSection:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)
    styleSection:SetText("Style Override")
    styleSection:SetTextColor(unpack(THEME.gold))
    yOffset = yOffset - 28

    -- Use global checkbox (themed)
    local useGlobalCheck = CreateThemedCheckbox(frame, THEME)
    useGlobalCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)
    local useGlobalLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    useGlobalLabel:SetPoint("LEFT", frame, "TOPLEFT", 36, yOffset)
    useGlobalLabel:SetText("Use global style defaults")
    useGlobalLabel:SetTextColor(unpack(THEME.text))
    useGlobalCheck.text = useGlobalLabel
    frame.useGlobalCheck = useGlobalCheck

    useGlobalCheck:SetScript("OnClick", function(self)
        local newValue = not self.checked
        self:SetChecked(newValue)
        PlaySound(newValue and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if newValue then
            -- Disable style controls (use global)
            frame.fontSizeSlider:EnableMouse(false)
            frame.fontSizeSlider:SetBackdropBorderColor(unpack(THEME.backgroundDark))
            frame.fontSizeSlider.thumb:SetColorTexture(unpack(THEME.textDim))
            frame.colorPicker:EnableMouse(false)
            frame.colorPicker:SetBackdropBorderColor(unpack(THEME.backgroundDark))
        else
            -- Enable style controls (custom per-spell)
            frame.fontSizeSlider:EnableMouse(true)
            frame.fontSizeSlider:SetBackdropBorderColor(unpack(THEME.border))
            frame.fontSizeSlider.thumb:SetColorTexture(unpack(THEME.gold))
            frame.colorPicker:EnableMouse(true)
            frame.colorPicker:SetBackdropBorderColor(unpack(THEME.border))
        end
        UpdateLivePreview()
    end)
    yOffset = yOffset - 36

    -- Font size slider (themed)
    local fontSizeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fontSizeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, yOffset)
    fontSizeLabel:SetText("Font Size:")
    fontSizeLabel:SetTextColor(unpack(THEME.text))
    yOffset = yOffset - 20

    local fontSizeSlider = CreateThemedSlider(frame, 160, 6, 24, 1, THEME)
    fontSizeSlider:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, yOffset)
    frame.fontSizeSlider = fontSizeSlider

    -- Min/max labels
    local lowLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lowLabel:SetPoint("TOPLEFT", fontSizeSlider, "BOTTOMLEFT", 0, -4)
    lowLabel:SetText("6")
    lowLabel:SetTextColor(unpack(THEME.textDim))

    local highLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    highLabel:SetPoint("TOPRIGHT", fontSizeSlider, "BOTTOMRIGHT", 0, -4)
    highLabel:SetText("24")
    highLabel:SetTextColor(unpack(THEME.textDim))

    local fontSizeValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fontSizeValue:SetPoint("TOP", fontSizeSlider, "BOTTOM", 0, -4)
    fontSizeValue:SetTextColor(unpack(THEME.gold))
    frame.fontSizeValue = fontSizeValue

    fontSizeSlider:SetScript("OnValueChanged", function(self, value)
        fontSizeValue:SetText(string.format("%.0f", value))
        UpdateLivePreview()
    end)
    yOffset = yOffset - 50

    -- Color picker
    local colorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, yOffset)
    colorLabel:SetText("Color:")
    colorLabel:SetTextColor(unpack(THEME.text))

    local colorPicker = CreateFrame("Button", nil, frame, "BackdropTemplate")
    colorPicker:SetSize(28, 28)
    colorPicker:SetPoint("LEFT", colorLabel, "RIGHT", 12, 0)
    colorPicker:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    colorPicker:SetBackdropColor(1, 1, 1, 1)  -- Default white
    colorPicker:SetBackdropBorderColor(unpack(THEME.border))

    colorPicker.color = { r = 1, g = 1, b = 1, a = 1 }

    colorPicker:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(THEME.gold))
    end)
    colorPicker:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(THEME.border))
    end)

    colorPicker:SetScript("OnClick", function(self)
        local function OnColorChanged()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = ColorPickerFrame:GetColorAlpha()
            self.color = { r = r, g = g, b = b, a = a }
            self:SetBackdropColor(r, g, b, a)
            UpdateLivePreview()
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

    -- Custom methods for color picker
    colorPicker.SetColor = function(self, color)
        self.color = color
        self:SetBackdropColor(color.r, color.g, color.b, color.a or 1)
    end
    colorPicker.GetColor = function(self)
        return self.color
    end

    frame.colorPicker = colorPicker

    -- Helper to create themed button (local to this function, using THEME)
    local function CreateEditorButton(parent, text)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(100, 26)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        btn:SetBackdropColor(unpack(THEME.button))

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btnText:SetPoint("CENTER")
        btnText:SetText(text)
        btnText:SetTextColor(unpack(THEME.text))
        btn.text = btnText

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(unpack(THEME.buttonHover))
            btnText:SetTextColor(unpack(THEME.gold))
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(unpack(THEME.button))
            btnText:SetTextColor(unpack(THEME.text))
        end)

        return btn
    end

    -- Save button
    local saveBtn = CreateEditorButton(frame, "Save")
    saveBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 15)
    saveBtn:SetScript("OnClick", function()
        ConfigMode:SaveEditorChanges()
        frame:Hide()
    end)

    -- Cancel button
    local cancelBtn = CreateEditorButton(frame, "Cancel")
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 10, 0)
    cancelBtn:SetScript("OnClick", function()
        -- Revert to saved state
        if currentEditSpellID and MedaBinds.OverlayManager then
            MedaBinds.OverlayManager:RefreshSpellOverlay(currentEditSpellID)
        end
        frame:Hide()
    end)

    -- Also revert when closed via ESC or X button
    frame:SetScript("OnHide", function()
        if currentEditSpellID and MedaBinds.OverlayManager then
            MedaBinds.OverlayManager:RefreshSpellOverlay(currentEditSpellID)
        end
    end)

    editorFrame = frame
    return frame
end

-- Update editor content for a spell
UpdateEditorContent = function(spellID, icon)
    if not editorFrame or not spellID then return end

    currentEditSpellID = spellID

    -- Get spell info (including override detection)
    local iconSpellInfo = icon and MedaBinds.OverlayManager and MedaBinds.OverlayManager:GetSpellInfoFromIcon(icon)
    local spellInfo = C_Spell.GetSpellInfo(spellID)
    local spellName = spellInfo and spellInfo.name or "Unknown"

    -- Show spell name with override indicator if applicable
    local spellText = "Spell: " .. spellName .. " (ID: " .. spellID .. ")"
    if iconSpellInfo and iconSpellInfo.isOverride and iconSpellInfo.baseSpellID then
        local baseInfo = C_Spell.GetSpellInfo(iconSpellInfo.baseSpellID)
        local baseName = baseInfo and baseInfo.name or "Unknown"
        spellText = spellText .. "\n       (replaces " .. baseName .. ")"
    end
    editorFrame.spellLabel:SetText(spellText)

    -- Get viewer name
    local viewerName = "Unknown"
    if icon and MedaBinds.OverlayManager then
        viewerName = MedaBinds.OverlayManager:GetViewerNameForIcon(icon) or "Unknown"
    end
    editorFrame.viewerLabel:SetText("Viewer: " .. viewerName:gsub("CooldownViewer", " Cooldowns"))

    -- Get auto-detected keybind (show on two lines)
    -- Try the displayed spell first, then the base spell
    local rawKeybind = nil
    local formattedKeybind = nil
    if MedaBinds.KeybindScanner then
        rawKeybind = MedaBinds.KeybindScanner:GetRawKeybindForSpell(spellID)
        formattedKeybind = MedaBinds.KeybindScanner:GetKeybindForSpell(spellID)

        -- If no keybind found and this is an override, try the base spell
        if not rawKeybind and iconSpellInfo and iconSpellInfo.baseSpellID and iconSpellInfo.baseSpellID ~= spellID then
            rawKeybind = MedaBinds.KeybindScanner:GetRawKeybindForSpell(iconSpellInfo.baseSpellID)
            formattedKeybind = MedaBinds.KeybindScanner:GetKeybindForSpell(iconSpellInfo.baseSpellID)
        end
    end

    editorFrame.detectedLabel:SetText("Keybind: " .. (rawKeybind or "None"))

    -- Show abbreviated version, or "None" if same as raw or not found
    if formattedKeybind and rawKeybind and formattedKeybind ~= rawKeybind then
        editorFrame.abbreviatedLabel:SetText("Abbreviated: " .. formattedKeybind)
    else
        editorFrame.abbreviatedLabel:SetText("Abbreviated: " .. (formattedKeybind or "None"))
    end

    -- Show bar/slot info
    local slot = MedaBinds.KeybindScanner and MedaBinds.KeybindScanner:GetSlotForSpell(spellID)
    if not slot and iconSpellInfo and iconSpellInfo.baseSpellID then
        slot = MedaBinds.KeybindScanner:GetSlotForSpell(iconSpellInfo.baseSpellID)
    end
    if slot then
        local barName, buttonNum = MedaBinds.KeybindScanner:GetBarInfoForSlot(slot)
        editorFrame.barSlotLabel:SetText("Location: " .. barName .. ", Button " .. buttonNum .. " (Slot " .. slot .. ")")
    else
        editorFrame.barSlotLabel:SetText("Location: Not on action bar")
    end

    -- Load current override settings
    local override = MedaBinds.db.spellOverrides[spellID]
    local globalStyle = MedaBinds.db.globalStyle

    if override and not override.useAuto and override.text then
        -- Custom text mode
        editorFrame.customEditBox:SetText(override.text)
        editorFrame.customEditBox:Enable()
        editorFrame.useCustomRadio:SetChecked(true)
        editorFrame.useAutoRadio:SetChecked(false)
    else
        -- Auto mode
        editorFrame.customEditBox:SetText("")
        editorFrame.customEditBox:Disable()
        editorFrame.useCustomRadio:SetChecked(false)
        editorFrame.useAutoRadio:SetChecked(true)
    end

    -- Style settings
    local hasStyleOverride = override and override.style
    editorFrame.useGlobalCheck:SetChecked(not hasStyleOverride)

    local fontSize = hasStyleOverride and override.style.fontSize or globalStyle.fontSize
    editorFrame.fontSizeSlider:SetValue(fontSize)

    local color = hasStyleOverride and override.style.color or globalStyle.color
    editorFrame.colorPicker:SetColor(CopyTable(color))

    -- Enable/disable style controls based on checkbox
    local THEME = GetTheme()
    if hasStyleOverride then
        editorFrame.fontSizeSlider:EnableMouse(true)
        editorFrame.fontSizeSlider.slider:SetBackdropBorderColor(unpack(THEME.border))
        editorFrame.fontSizeSlider.thumb:SetColorTexture(unpack(THEME.gold))
        editorFrame.colorPicker:EnableMouse(true)
        editorFrame.colorPicker:SetBackdropBorderColor(unpack(THEME.border))
    else
        editorFrame.fontSizeSlider:EnableMouse(false)
        editorFrame.fontSizeSlider.slider:SetBackdropBorderColor(unpack(THEME.backgroundDark))
        editorFrame.fontSizeSlider.thumb:SetColorTexture(unpack(THEME.textDim))
        editorFrame.colorPicker:EnableMouse(false)
        editorFrame.colorPicker:SetBackdropBorderColor(unpack(THEME.backgroundDark))
    end
end

-- Update editor content for an external icon
UpdateExternalEditorContent = function(uniqueKey, entry, frame)
    if not editorFrame or not uniqueKey or not entry then return end

    currentEditSpellID = nil
    currentEditExternalKey = uniqueKey

    -- Build display name
    local displayName = "External Icon"
    if entry.spellID then
        local spellInfo = C_Spell.GetSpellInfo(entry.spellID)
        displayName = spellInfo and spellInfo.name or ("SpellID: " .. entry.spellID)
    elseif entry.itemID then
        local itemName = C_Item.GetItemInfo(entry.itemID)
        displayName = itemName or ("ItemID: " .. entry.itemID)
    elseif entry.frameName then
        displayName = entry.frameName
    end

    editorFrame.spellLabel:SetText("External: " .. displayName)
    editorFrame.viewerLabel:SetText("Source: " .. (entry.source or "Unknown"))

    -- Get auto-detected keybind if spell/item is known
    local rawKeybind = nil
    local formattedKeybind = nil
    if MedaBinds.KeybindScanner then
        if entry.spellID then
            rawKeybind = MedaBinds.KeybindScanner:GetRawKeybindForSpell(entry.spellID)
            formattedKeybind = MedaBinds.KeybindScanner:GetKeybindForSpell(entry.spellID)
        elseif entry.itemID then
            rawKeybind = MedaBinds.KeybindScanner:GetRawKeybindForItem(entry.itemID)
            formattedKeybind = MedaBinds.KeybindScanner:GetKeybindForItem(entry.itemID)
        end
    end

    editorFrame.detectedLabel:SetText("Keybind: " .. (rawKeybind or "None"))
    if formattedKeybind and rawKeybind and formattedKeybind ~= rawKeybind then
        editorFrame.abbreviatedLabel:SetText("Abbreviated: " .. formattedKeybind)
    else
        editorFrame.abbreviatedLabel:SetText("Abbreviated: " .. (formattedKeybind or "None"))
    end

    -- Show bar/slot info for external icons
    local slot = nil
    if entry.spellID and MedaBinds.KeybindScanner then
        slot = MedaBinds.KeybindScanner:GetSlotForSpell(entry.spellID)
    end
    if slot then
        local barName, buttonNum = MedaBinds.KeybindScanner:GetBarInfoForSlot(slot)
        editorFrame.barSlotLabel:SetText("Location: " .. barName .. ", Button " .. buttonNum .. " (Slot " .. slot .. ")")
    else
        editorFrame.barSlotLabel:SetText("Location: External icon")
    end

    -- Load current settings
    local globalStyle = MedaBinds.db.globalStyle

    if entry.text and entry.text ~= "" and not entry.useAuto then
        editorFrame.customEditBox:SetText(entry.text)
        editorFrame.customEditBox:Enable()
        editorFrame.useCustomRadio:SetChecked(true)
        editorFrame.useAutoRadio:SetChecked(false)
    else
        editorFrame.customEditBox:SetText("")
        editorFrame.customEditBox:Disable()
        editorFrame.useCustomRadio:SetChecked(false)
        editorFrame.useAutoRadio:SetChecked(true)
    end

    -- Style settings
    local hasStyleOverride = entry.style ~= nil
    editorFrame.useGlobalCheck:SetChecked(not hasStyleOverride)

    local fontSize = hasStyleOverride and entry.style.fontSize or globalStyle.fontSize
    editorFrame.fontSizeSlider:SetValue(fontSize)

    local color = hasStyleOverride and entry.style.color or globalStyle.color
    editorFrame.colorPicker:SetColor(CopyTable(color))

    -- Enable/disable style controls
    local THEME = GetTheme()
    if hasStyleOverride then
        editorFrame.fontSizeSlider:EnableMouse(true)
        editorFrame.fontSizeSlider.slider:SetBackdropBorderColor(unpack(THEME.border))
        editorFrame.fontSizeSlider.thumb:SetColorTexture(unpack(THEME.gold))
        editorFrame.colorPicker:EnableMouse(true)
        editorFrame.colorPicker:SetBackdropBorderColor(unpack(THEME.border))
    else
        editorFrame.fontSizeSlider:EnableMouse(false)
        editorFrame.fontSizeSlider.slider:SetBackdropBorderColor(unpack(THEME.backgroundDark))
        editorFrame.fontSizeSlider.thumb:SetColorTexture(unpack(THEME.textDim))
        editorFrame.colorPicker:EnableMouse(false)
        editorFrame.colorPicker:SetBackdropBorderColor(unpack(THEME.backgroundDark))
    end
end

-- Open editor for a spell
function ConfigMode:OpenEditor(spellID, icon)
    if not spellID then return end

    currentEditExternalKey = nil  -- Clear external key when opening spell editor

    local frame = CreateEditorFrame()
    UpdateEditorContent(spellID, icon)
    frame:Show()
end

-- Save editor changes
function ConfigMode:SaveEditorChanges()
    -- Handle external icon save
    if currentEditExternalKey then
        local entry = MedaBinds.db.externalIcons[currentEditExternalKey]
        if not entry then return end

        -- Text settings
        if editorFrame.useCustomRadio:GetChecked() then
            entry.useAuto = false
            entry.text = editorFrame.customEditBox:GetText()
            if entry.text == "" then
                entry.text = nil
                entry.useAuto = true
            end
        else
            entry.useAuto = true
            entry.text = nil
        end

        -- Style settings
        if editorFrame.useGlobalCheck:GetChecked() then
            entry.style = nil
        else
            entry.style = entry.style or {}
            entry.style.fontSize = editorFrame.fontSizeSlider:GetValue()
            entry.style.color = CopyTable(editorFrame.colorPicker:GetColor())
        end

        -- Refresh external overlay using runtime frame reference
        if MedaBinds.OverlayManager then
            local frame = MedaBinds.OverlayManager:GetExternalFrameRef(currentEditExternalKey)
            if frame then
                MedaBinds.OverlayManager:RefreshExternalOverlay(currentEditExternalKey, frame)
            end
        end

        MedaBinds:Debug("ConfigMode: Saved changes for external icon", currentEditExternalKey, "text:", entry.text, "useAuto:", entry.useAuto)
        return
    end

    -- Handle spell override save
    if not currentEditSpellID then return end

    local spellID = currentEditSpellID

    -- Ensure override entry exists
    if not MedaBinds.db.spellOverrides[spellID] then
        MedaBinds.db.spellOverrides[spellID] = {}
    end

    local override = MedaBinds.db.spellOverrides[spellID]

    -- Text settings
    if editorFrame.useCustomRadio:GetChecked() then
        override.useAuto = false
        override.text = editorFrame.customEditBox:GetText()
        if override.text == "" then
            override.text = nil
            override.useAuto = true
        end
    else
        override.useAuto = true
        override.text = nil
    end

    -- Style settings
    if editorFrame.useGlobalCheck:GetChecked() then
        override.style = nil
    else
        override.style = override.style or {}
        override.style.fontSize = editorFrame.fontSizeSlider:GetValue()
        override.style.color = CopyTable(editorFrame.colorPicker:GetColor())
    end

    -- Clean up empty overrides
    if override.useAuto and not override.text and not override.style then
        MedaBinds.db.spellOverrides[spellID] = nil
    end

    -- Refresh the overlay
    if MedaBinds.OverlayManager then
        MedaBinds.OverlayManager:RefreshSpellOverlay(spellID)
    end

    -- Refresh the Configured Icons list if settings panel is open
    if MedaBinds.SettingsPanel and MedaBinds.SettingsPanel:IsShown() then
        MedaBinds.SettingsPanel:RefreshCurrentTab()
    end

    MedaBinds:Debug("ConfigMode: Saved changes for spellID", spellID)
end

-- Combat event handling
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if isConfigModeActive and MedaBinds.db.options.autoDisableInCombat then
            ConfigMode:Disable()
            print("|cFF00FF00MedaBinds:|r Config mode auto-disabled due to combat.")
        end
    end
end)

-- Initialize config mode
function ConfigMode:Initialize()
    MedaBinds:Debug("ConfigMode: Initialized")
end

-- Debug function to print found icons (run /mbinds debugscan)
function ConfigMode:DebugScan()
    -- Force cache refresh
    iconCacheTime = 0
    local frames = RefreshIconCache()

    print("|cFF00FF00MedaBinds:|r Found " .. #frames .. " icon-like frames:")

    -- Print first 20 frames
    for i = 1, math.min(20, #frames) do
        local frame = frames[i]
        local name = frame:GetName() or "unnamed"
        local width, height = frame:GetSize()
        local hasIcon = frame.Icon and "yes" or "no"
        local hasCooldown = frame.Cooldown and "yes" or "no"
        print(string.format("  %d: %s (%.0fx%.0f) Icon:%s CD:%s", i, name, width or 0, height or 0, hasIcon, hasCooldown))
    end

    if #frames > 20 then
        print("  ... and " .. (#frames - 20) .. " more")
    end

    -- Check tracked external icon frames
    print("|cFF00FF00MedaBinds:|r Checking tracked external icon frames...")
    for uniqueKey, entry in pairs(MedaBinds.db.externalIcons or {}) do
        local frameName = entry.frameName
        if frameName then
            -- Check _G reference
            local globalFrame = _G[frameName]
            local globalStatus = "NOT_IN_G"
            if globalFrame then
                local visible = globalFrame.IsVisible and globalFrame:IsVisible()
                globalStatus = visible and "G_VISIBLE" or "G_HIDDEN"
            end

            -- Try to find visible frame in hierarchy
            local visibleFrame = MedaBinds.OverlayManager and MedaBinds.OverlayManager:FindVisibleFrameByName(frameName)
            local hierarchyStatus = visibleFrame and "FOUND_VISIBLE" or "NOT_FOUND"

            -- Check overlay status
            local overlayStatus = "NO_OVERLAY"
            if MedaBinds.OverlayManager then
                local overlayData = MedaBinds.OverlayManager:GetExternalOverlayData(uniqueKey)
                if overlayData and overlayData.container then
                    local hasParent = overlayData.container:GetParent() ~= nil
                    overlayStatus = hasParent and "OVERLAY_OK" or "OVERLAY_ORPHANED"
                end
            end

            print(string.format("  %s: %s | %s | %s", frameName, globalStatus, hierarchyStatus, overlayStatus))
        end
    end

    -- Also print cursor position info
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    print(string.format("|cFF00FF00MedaBinds:|r Cursor at %.0f, %.0f (scale %.2f)", cx/scale, cy/scale, scale))

    -- Print external icons status
    print("|cFF00FF00MedaBinds:|r External icons in database:")
    local extCount = 0
    for uniqueKey, entry in pairs(MedaBinds.db.externalIcons or {}) do
        extCount = extCount + 1
        local frameRef = MedaBinds.OverlayManager and MedaBinds.OverlayManager:GetExternalFrameRef(uniqueKey)
        local hasFrame = frameRef and "HAS_FRAME" or "NO_FRAME"
        local text = entry.text or "(none)"
        local useAuto = entry.useAuto and "auto" or "custom"
        print(string.format("  %s: %s | text=%s | mode=%s | enabled=%s",
            uniqueKey:sub(1, 50),
            hasFrame,
            text:sub(1, 10),
            useAuto,
            entry.enabled and "yes" or "no"
        ))
        if extCount >= 10 then
            print("  ... and more")
            break
        end
    end
    if extCount == 0 then
        print("  (none)")
    end
end
