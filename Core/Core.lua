--[[
    MedaBinds - Core.lua
    Initialization, events, and slash commands
]]

-- Create addon namespace
local addonName, MedaBinds = ...
_G.MedaBinds = MedaBinds

-- Addon version
MedaBinds.version = "1.0.4"
local MedaUI = LibStub("MedaUI-2.0", true)
local logger

-- Default database schema
local DEFAULT_DB = {
    version = 1,

    -- Global default style
    globalStyle = {
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
    },

    -- Per-spell custom overrides (keyed by spellID)
    spellOverrides = {},

    -- External icons (from other addons, tracked by frame path)
    externalIcons = {
        -- [uniqueKey] = {
        --     framePath = "ParentFrame.ChildFrame.Icon",  -- Path to re-find the frame
        --     frameName = "SomeAddonIcon1",               -- Global name if available
        --     spellID = 12345,                            -- SpellID if detected
        --     itemID = 67890,                             -- ItemID if detected
        --     textureID = 123456,                         -- Texture ID for matching
        --     text = "F1",                                -- Custom keybind text
        --     useAuto = false,                            -- Use auto-detected keybind
        --     style = nil,                                -- Style overrides (nil = use global)
        --     enabled = true,                             -- Whether to show overlay
        -- }
    },

    -- Options (defaults - most features enabled)
    options = {
        -- Which viewers to show keybinds on (all enabled by default)
        showOnEssential = true,
        showOnUtility = true,
        showOnBuffIcons = true,
        showOnBuffBars = false,

        -- Auto-detection settings (all enabled by default)
        enableAutoDetection = true,
        abbreviateKeybinds = true,
        scanHiddenBars = true,
        scanMacros = true,

        -- Paged keybind settings
        showPagedKeybinds = false,          -- Enable/disable paged keybind detection (off by default)
        pagedKeybindSeparator = ">",        -- Separator between page key and slot key (e.g., ">")
        customPagedKeybind = "",            -- Custom page switch key (e.g., "Q" shows "Q>E")
        pagedKeybindColor = { r = 0.7, g = 0.7, b = 0.9, a = 1 },  -- Light blue-ish tint for paged keybinds

        -- Config mode
        configModifierKey = "ALT",
        autoDisableInCombat = true,

        -- Minimap button
        showMinimapButton = true,

        -- Theme (nil = use default)
        theme = nil,

        logging = {
            enabled = true,
            minLevel = "WARN",
            combatMode = "always",
            chatFallback = false,
        },
    },

    -- Minimap button position (LibDBIcon format)
    minimapButton = {
        hide = false,
    },
}

-- Main event frame
local eventFrame = CreateFrame("Frame")
MedaBinds.eventFrame = eventFrame

-- Initialize database
local function InitializeDB()
    if not MedaBindsDB then
        MedaBindsDB = CopyTable(DEFAULT_DB)
    else
        -- Migrate/update schema if needed
        if not MedaBindsDB.version then
            MedaBindsDB.version = 1
        end

        -- Ensure all default keys exist
        for key, value in pairs(DEFAULT_DB) do
            if MedaBindsDB[key] == nil then
                MedaBindsDB[key] = CopyTable(value)
            elseif type(value) == "table" and type(MedaBindsDB[key]) == "table" then
                -- Deep merge for nested tables
                for subKey, subValue in pairs(value) do
                    if MedaBindsDB[key][subKey] == nil then
                        MedaBindsDB[key][subKey] = type(subValue) == "table" and CopyTable(subValue) or subValue
                    end
                end
            end
        end
    end

    if MedaUI and MedaUI.NormalizeLogPolicy then
        MedaBindsDB.options.logging = MedaUI:NormalizeLogPolicy(MedaBindsDB.options.logging)
    end

    MedaBinds.db = MedaBindsDB
end

local function GetLoggingPolicy()
    if MedaUI and MedaUI.NormalizeLogPolicy and MedaBinds.db and MedaBinds.db.options then
        return MedaUI:NormalizeLogPolicy(MedaBinds.db.options.logging)
    end

    return {
        enabled = true,
        minLevel = MedaBinds.debug and "DEBUG" or "WARN",
        combatMode = "always",
        chatFallback = false,
    }
end

local function UpdateDebugFlag()
    local policy = GetLoggingPolicy()
    MedaBinds.debug = policy.enabled ~= false and policy.minLevel == "DEBUG"
    return MedaBinds.debug
end

local function SetLoggingPolicy(policy)
    if not MedaBinds.db or not MedaBinds.db.options then
        return GetLoggingPolicy()
    end

    local normalized = MedaUI and MedaUI.NormalizeLogPolicy and MedaUI:NormalizeLogPolicy(policy) or policy
    MedaBinds.db.options.logging = normalized
    UpdateDebugFlag()
    return normalized
end

local function EnsureLogger()
    if not MedaUI or not MedaUI.CreateAddonLogger then
        return nil
    end

    if not logger then
        logger = MedaUI:CreateAddonLogger({
            addonName = "MedaBinds",
            color = { 0.0, 1.0, 0.0 },
            prefix = "[MedaBinds]",
            getPolicy = GetLoggingPolicy,
            setPolicy = SetLoggingPolicy,
        })
    end

    return logger
end

function MedaBinds:GetLogPolicy()
    return GetLoggingPolicy()
end

function MedaBinds:SetLogPolicy(policy)
    return SetLoggingPolicy(policy)
end

function MedaBinds:CanLog(level)
    local activeLogger = EnsureLogger()
    return activeLogger and activeLogger:CanEmit(level or "INFO") or false
end

function MedaBinds:SetDebugMode(enabled)
    local policy = GetLoggingPolicy()
    policy.minLevel = enabled and "DEBUG" or "WARN"
    SetLoggingPolicy(policy)
    return self.debug
end

function MedaBinds:IsDebugModeEnabled()
    return self.debug == true
end

-- Get a style value (per-spell override or global default)
function MedaBinds:GetStyleValue(spellID, key)
    local override = self.db.spellOverrides[spellID]
    if override and override.style and override.style[key] ~= nil then
        return override.style[key]
    end
    return self.db.globalStyle[key]
end

-- Get the full style for a spell (merged with global defaults)
function MedaBinds:GetSpellStyle(spellID)
    local style = CopyTable(self.db.globalStyle)
    local override = self.db.spellOverrides[spellID]
    if override and override.style then
        for key, value in pairs(override.style) do
            style[key] = value
        end
    end
    return style
end

-- Get keybind text for a spell (custom override or auto-detected)
function MedaBinds:GetKeybindText(spellID)
    local override = self.db.spellOverrides[spellID]

    -- Check for custom text override
    if override and not override.useAuto and override.text then
        return override.text, "custom"
    end

    -- Use auto-detected keybind
    if self.db.options.enableAutoDetection and self.KeybindScanner then
        local keybind = self.KeybindScanner:GetKeybindForSpell(spellID)
        if keybind then
            return keybind, "auto"
        end
    end

    return nil, nil
end

-- Slash command handler
local function SlashCommandHandler(msg)
    local cmd = msg:lower():trim()

    if cmd == "" or cmd == "options" or cmd == "settings" then
        -- Open settings panel (default action)
        if MedaBinds.SettingsPanel then
            MedaBinds.SettingsPanel:Toggle()
        else
            print("|cFF00FF00MedaBinds:|r Settings panel not yet loaded.")
        end
    elseif cmd == "config" then
        -- Toggle config mode
        if MedaBinds.ConfigMode then
            MedaBinds.ConfigMode:Toggle()
        else
            print("|cFF00FF00MedaBinds:|r Config mode not yet loaded.")
        end
    elseif cmd == "scan" then
        -- Force rescan keybinds
        if MedaBinds.KeybindScanner then
            local scanned = MedaBinds.KeybindScanner:ForceRescan()
            if scanned == false then
                print("|cFF00FF00MedaBinds:|r Keybind rescan queued until combat ends.")
            else
                print("|cFF00FF00MedaBinds:|r Keybinds rescanned.")
            end
        end
    elseif cmd == "reset" then
        -- Reset all settings with confirmation
        StaticPopup_Show("MEDABINDS_RESET_CONFIRM")
    elseif cmd == "debug" then
        -- Toggle debug mode
        MedaBinds:SetDebugMode(not MedaBinds.debug)
        print("|cFF00FF00MedaBinds:|r Debug mode " .. (MedaBinds.debug and "enabled" or "disabled"))
    elseif cmd == "debugscan" then
        -- Debug: scan and print found icon frames
        if MedaBinds.ConfigMode then
            MedaBinds.ConfigMode:DebugScan()
        end
    elseif cmd == "reconnect" then
        -- Force reconnect external icons
        if MedaBinds.OverlayManager then
            MedaBinds.OverlayManager:ForceReconnectExternalIcons()
        end
    else
        -- Show help
        print("|cFF00FF00MedaBinds Commands:|r")
        print("  /mbinds - Open settings panel")
        print("  /mbinds config - Toggle config mode (ALT+click icons)")
        print("  /mbinds scan - Force rescan keybinds")
        print("  /mbinds reconnect - Reconnect external icon overlays")
        print("  /mbinds reset - Reset all settings")
        print("  /mbinds debugscan - Debug: list detected icon frames")
    end
end

-- Reset confirmation dialog
StaticPopupDialogs["MEDABINDS_RESET_CONFIRM"] = {
    text = "Are you sure you want to reset all MedaBinds settings? This cannot be undone.",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        MedaBindsDB = CopyTable(DEFAULT_DB)
        MedaBinds.db = MedaBindsDB
        if MedaUI and MedaUI.NormalizeLogPolicy then
            MedaBindsDB.options.logging = MedaUI:NormalizeLogPolicy(MedaBindsDB.options.logging)
        end
        UpdateDebugFlag()

        -- Refresh overlays
        if MedaBinds.OverlayManager then
            MedaBinds.OverlayManager:RefreshAllOverlays()
        end

        print("|cFF00FF00MedaBinds:|r Settings reset to defaults.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Debug print helper
function MedaBinds:Debug(...)
    if not self.debug then
        return
    end

    local activeLogger = EnsureLogger()
    if not activeLogger or not activeLogger:CanEmit("DEBUG") then
        return
    end

    local argCount = select("#", ...)
    local args = { ... }
    activeLogger:EmitLazy("DEBUG", function()
        local parts = {}
        for index = 1, argCount do
            parts[#parts + 1] = tostring(args[index])
        end
        return table.concat(parts, " ")
    end)
end

-- Event handlers
local function OnAddonLoaded(self, event, loadedAddon)
    if loadedAddon ~= addonName then return end

    -- Initialize database
    InitializeDB()
    UpdateDebugFlag()
    if EnsureLogger() then
        logger:RefreshSink()
    end

    -- Register slash commands
    SLASH_MEDABINDS1 = "/medab"
    SLASH_MEDABINDS2 = "/mbinds"
    SlashCmdList["MEDABINDS"] = SlashCommandHandler

    print("|cFF00FF00MedaBinds|r v" .. MedaBinds.version .. " loaded. Type /mbinds for commands.")

    -- Unregister this event
    eventFrame:UnregisterEvent("ADDON_LOADED")
end

local function OnPlayerLogin(self, event)
    if EnsureLogger() then
        logger:RefreshSink()
    end

    -- Restore saved theme
    if MedaUI and MedaBinds.db.options.theme then
        MedaUI:SetTheme(MedaBinds.db.options.theme)
    end

    -- Initialize keybind scanner
    if MedaBinds.KeybindScanner then
        MedaBinds.KeybindScanner:Initialize()
    end

    -- Initialize overlay manager
    if MedaBinds.OverlayManager then
        MedaBinds.OverlayManager:Initialize()
    end

    -- Initialize config mode
    if MedaBinds.ConfigMode then
        MedaBinds.ConfigMode:Initialize()
    end

    -- Initialize minimap button
    MedaBinds:InitializeMinimapButton()
end

local function OnPlayerEnteringWorld(self, event, isInitialLogin, isReloadingUI)
    -- Refresh overlays after zoning/reload
    C_Timer.After(0.5, function()
        if MedaBinds.OverlayManager then
            MedaBinds.OverlayManager:RefreshAllOverlays()
        end
    end)
end

-- Event dispatcher
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(self, event, ...)
    elseif event == "PLAYER_LOGIN" then
        OnPlayerLogin(self, event)
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnPlayerEnteringWorld(self, event, ...)
    end
end)

-- Register events
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- ============================================================================
-- Minimap Button
-- ============================================================================

-- LibDBIcon minimap button
local LDB = LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub("LibDBIcon-1.0", true)
local minimapDataObj = nil

local function CreateMinimapButton()
    if minimapDataObj then return minimapDataObj end
    if not LDB or not LDBIcon then
        print("|cFFFF0000MedaBinds:|r LibDBIcon not available, minimap button disabled.")
        return nil
    end

    minimapDataObj = LDB:NewDataObject("MedaBinds", {
        type = "launcher",
        icon = "Interface\\AddOns\\MedaBinds\\Media\\binding-chain",
        OnClick = function(self, button)
            if button == "LeftButton" then
                if MedaBinds.SettingsPanel then
                    MedaBinds.SettingsPanel:Toggle()
                end
            elseif button == "RightButton" then
                if MedaBinds.ConfigMode then
                    MedaBinds.ConfigMode:Toggle()
                end
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("MedaBinds", 0.9, 0.7, 0.15)
            tooltip:AddLine(" ")
            tooltip:AddLine("Left-click: Open settings", 0.8, 0.8, 0.8)
            tooltip:AddLine("Right-click: Toggle config mode", 0.8, 0.8, 0.8)
            tooltip:AddLine("Drag: Move button", 0.5, 0.5, 0.5)
        end,
    })

    LDBIcon:Register("MedaBinds", minimapDataObj, MedaBinds.db.minimapButton)

    return minimapDataObj
end

-- Show/hide minimap button
function MedaBinds:SetMinimapButtonShown(show)
    if not LDBIcon then return end

    if show then
        if not minimapDataObj then
            CreateMinimapButton()
        end
        LDBIcon:Show("MedaBinds")
        self.db.minimapButton.hide = false
    else
        LDBIcon:Hide("MedaBinds")
        self.db.minimapButton.hide = true
    end
end

-- Initialize minimap button after db is loaded
function MedaBinds:InitializeMinimapButton()
    if self.db.options.showMinimapButton then
        CreateMinimapButton()
    end
end
