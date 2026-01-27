--[[
    MedaBinds - KeybindScanner.lua
    Auto-detect keybinds from action bars
]]

local addonName, MedaBinds = ...

-- KeybindScanner module
local KeybindScanner = {}
MedaBinds.KeybindScanner = KeybindScanner

-- Constants
local NUM_ACTIONBAR_BUTTONS = 12
local MAX_ACTION_SLOTS = 180

-- Cache tables
local bindingCache = {}      -- Maps binding commands to key strings
local bindingCacheValid = false
local spellToKeybind = {}    -- Maps spellID to formatted keybind
local spellToSlot = {}       -- Maps spellID to action slot(s)
local slotToKeybind = {}     -- Maps action slot to keybind
local slotToKeybindValid = false
local itemToKeybind = {}     -- Maps itemID to formatted keybind
local itemToSlot = {}        -- Maps itemID to action slot(s)
local trinketKeybinds = {}   -- Direct trinket slot keybinds (slot 13, 14)

-- Cached action bar state for class-specific bars
local cachedState = {
    page = 1,
    bonusOffset = 0,
    form = 0,
    hasOverride = false,
    hasVehicle = false,
    hasTemp = false,
    hash = 0,
    valid = false,
}

-- Binding patterns for different bars
local BINDING_PATTERNS = {
    "ACTIONBUTTON",
    "MULTIACTIONBAR1BUTTON", -- Bar 2 (or swapped in 11.0+)
    "MULTIACTIONBAR2BUTTON", -- Bar 3 (or swapped in 11.0+)
    "MULTIACTIONBAR3BUTTON", -- Bar 4
    "MULTIACTIONBAR4BUTTON", -- Bar 5
    "MULTIACTIONBAR5BUTTON", -- Bar 6
    "MULTIACTIONBAR6BUTTON", -- Bar 7
    "MULTIACTIONBAR7BUTTON", -- Bar 8
}

-- Format a keybind string (abbreviate if option is enabled)
local function FormatKeybind(keybind)
    if not keybind or keybind == "" then
        return ""
    end

    local db = MedaBinds.db
    if not db or not db.options.abbreviateKeybinds then
        return keybind
    end

    local formatted = keybind:upper()

    -- Modifier abbreviations
    formatted = formatted:gsub("SHIFT%-", "S")
    formatted = formatted:gsub("CTRL%-", "C")
    formatted = formatted:gsub("ALT%-", "A")
    formatted = formatted:gsub("STRG%-", "S") -- German Ctrl

    -- Mouse abbreviations
    formatted = formatted:gsub("MOUSE%s?WHEEL%s?UP", "MWU")
    formatted = formatted:gsub("MOUSE%s?WHEEL%s?DOWN", "MWD")
    formatted = formatted:gsub("MOUSE%s?BUTTON%s?", "M")
    formatted = formatted:gsub("BUTTON", "M")

    -- Numpad abbreviations
    formatted = formatted:gsub("NUMPAD%s?PLUS", "N+")
    formatted = formatted:gsub("NUMPAD%s?MINUS", "N-")
    formatted = formatted:gsub("NUMPAD%s?MULTIPLY", "N*")
    formatted = formatted:gsub("NUMPAD%s?DIVIDE", "N/")
    formatted = formatted:gsub("NUMPAD%s?DECIMAL", "N.")
    formatted = formatted:gsub("NUMPAD%s?ENTER", "NEnt")
    formatted = formatted:gsub("NUMPAD%s?", "N")
    formatted = formatted:gsub("NUM%s?", "N")

    -- Key abbreviations
    formatted = formatted:gsub("PAGE%s?UP", "PGU")
    formatted = formatted:gsub("PAGE%s?DOWN", "PGD")
    formatted = formatted:gsub("INSERT", "INS")
    formatted = formatted:gsub("DELETE", "DEL")
    formatted = formatted:gsub("SPACEBAR", "Spc")
    formatted = formatted:gsub("ENTER", "Ent")
    formatted = formatted:gsub("ESCAPE", "Esc")
    formatted = formatted:gsub("TAB", "Tab")
    formatted = formatted:gsub("CAPS%s?LOCK", "Caps")
    formatted = formatted:gsub("HOME", "Hom")
    formatted = formatted:gsub("END", "End")

    return formatted
end

-- Update cached action bar state
local function UpdateCachedState()
    cachedState.page = GetActionBarPage and GetActionBarPage() or 1
    cachedState.bonusOffset = GetBonusBarOffset and GetBonusBarOffset() or 0
    cachedState.form = GetShapeshiftFormID and GetShapeshiftFormID() or 0
    cachedState.hasOverride = HasOverrideActionBar and HasOverrideActionBar() or false
    cachedState.hasVehicle = HasVehicleActionBar and HasVehicleActionBar() or false
    cachedState.hasTemp = HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() or false

    cachedState.hash = cachedState.page + (cachedState.bonusOffset * 100) + (cachedState.form * 10000)
    if cachedState.hasOverride then
        cachedState.hash = cachedState.hash + 1000000
    end
    if cachedState.hasVehicle then
        cachedState.hash = cachedState.hash + 2000000
    end
    if cachedState.hasTemp then
        cachedState.hash = cachedState.hash + 4000000
    end

    cachedState.valid = true
end

-- Build the binding cache (binding command -> key string)
local function RebuildBindingCache()
    wipe(bindingCache)

    for _, pattern in ipairs(BINDING_PATTERNS) do
        for i = 1, NUM_ACTIONBAR_BUTTONS do
            local command = pattern .. i
            local key = GetBindingKey(command)
            if key then
                bindingCache[command] = key
            end
        end
    end

    -- Also support Bartender4 bindings if available
    for barNum = 1, 10 do
        for buttonNum = 1, 12 do
            local bindingKey = "CLICK BT4Button" .. ((barNum - 1) * 12 + buttonNum) .. ":LeftButton"
            local key = GetBindingKey(bindingKey)
            if key then
                bindingCache["BT4Bar" .. barNum .. "Button" .. buttonNum] = key
            end
        end
    end

    bindingCacheValid = true
end

-- Calculate action slot from button ID and bar type
local function CalculateActionSlot(buttonID, barType)
    if not cachedState.valid then
        UpdateCachedState()
    end

    local page = 1

    if barType == "main" then
        page = cachedState.page
        if cachedState.bonusOffset > 0 then
            page = 6 + cachedState.bonusOffset
        end
    elseif barType == "multibarbottomleft" then
        page = LE_EXPANSION_LEVEL_CURRENT >= 11 and 5 or 6
    elseif barType == "multibarbottomright" then
        page = LE_EXPANSION_LEVEL_CURRENT >= 11 and 6 or 5
    elseif barType == "multibarright" then
        page = 3
    elseif barType == "multibarleft" then
        page = 4
    elseif barType == "multibar5" then
        page = 13
    elseif barType == "multibar6" then
        page = 14
    elseif barType == "multibar7" then
        page = 15
    end

    local safePage = math.max(1, page)
    local safeButtonID = math.max(1, math.min(buttonID, NUM_ACTIONBAR_BUTTONS))
    return safeButtonID + ((safePage - 1) * NUM_ACTIONBAR_BUTTONS)
end

-- Build slot to keybind mapping
local function BuildSlotToKeybindMap()
    if not bindingCacheValid then
        RebuildBindingCache()
    end
    if not cachedState.valid then
        UpdateCachedState()
    end

    wipe(slotToKeybind)

    -- Main action bar
    for buttonID = 1, NUM_ACTIONBAR_BUTTONS do
        local slot = CalculateActionSlot(buttonID, "main")
        local key = bindingCache["ACTIONBUTTON" .. buttonID]
        if key and key ~= "" then
            slotToKeybind[slot] = key
        end
    end

    -- Bar mappings (adjusted for expansion differences)
    local barMappings = {
        { barType = "multibarbottomleft", pattern = LE_EXPANSION_LEVEL_CURRENT >= 11 and "MULTIACTIONBAR2BUTTON" or "MULTIACTIONBAR1BUTTON" },
        { barType = "multibarbottomright", pattern = LE_EXPANSION_LEVEL_CURRENT >= 11 and "MULTIACTIONBAR1BUTTON" or "MULTIACTIONBAR2BUTTON" },
        { barType = "multibarright", pattern = "MULTIACTIONBAR3BUTTON" },
        { barType = "multibarleft", pattern = "MULTIACTIONBAR4BUTTON" },
        { barType = "multibar5", pattern = "MULTIACTIONBAR5BUTTON" },
        { barType = "multibar6", pattern = "MULTIACTIONBAR6BUTTON" },
        { barType = "multibar7", pattern = "MULTIACTIONBAR7BUTTON" },
    }

    for _, barData in ipairs(barMappings) do
        for buttonID = 1, NUM_ACTIONBAR_BUTTONS do
            local slot = CalculateActionSlot(buttonID, barData.barType)
            local key = bindingCache[barData.pattern .. buttonID]
            if key and key ~= "" then
                slotToKeybind[slot] = key
            end
        end
    end

    slotToKeybindValid = true
end

-- Build spellID-to-slot mapping
local function BuildSpellToSlotMap()
    wipe(spellToSlot)

    -- Determine start/end slots based on bonus bar
    local startSlot = 1
    local endSlot = 12

    if GetBonusBarOffset and GetBonusBarOffset() > 0 then
        local bonusOffset = GetBonusBarOffset()
        startSlot = 72 + (bonusOffset - 1) * NUM_ACTIONBAR_BUTTONS + 1
        endSlot = startSlot + NUM_ACTIONBAR_BUTTONS - 1
    end

    -- First scan bonus/class bar slots (priority)
    for slot = startSlot, endSlot do
        local actionType, id, subType = GetActionInfo(slot)
        if actionType == "spell" then
            if not spellToSlot[id] then
                spellToSlot[id] = slot
            end
        elseif actionType == "macro" then
            -- Use GetMacroSpell for reliable macro spell detection
            local macroSpellID = GetMacroSpell and GetMacroSpell(id)
            if macroSpellID and not spellToSlot[macroSpellID] then
                spellToSlot[macroSpellID] = slot
            end
            -- Also check subType for spell macros
            if subType == "spell" and id and not spellToSlot[id] then
                spellToSlot[id] = slot
            end
        end
    end

    -- Then scan remaining slots (skip class bar range 73-132)
    for slot = 25, MAX_ACTION_SLOTS do
        if (slot <= 72 or slot > 132) and HasAction(slot) then
            local actionType, id, subType = GetActionInfo(slot)
            if actionType == "spell" then
                if not spellToSlot[id] then
                    spellToSlot[id] = slot
                end
            elseif actionType == "macro" then
                local macroSpellID = GetMacroSpell and GetMacroSpell(id)
                if macroSpellID and not spellToSlot[macroSpellID] then
                    spellToSlot[macroSpellID] = slot
                end
                if subType == "spell" and id and not spellToSlot[id] then
                    spellToSlot[id] = slot
                end
            end
        end
    end
end

-- Build the spell-to-keybind mapping
local function BuildSpellToKeybindMap()
    wipe(spellToKeybind)

    for spellID, slot in pairs(spellToSlot) do
        local key = slotToKeybind[slot]
        if key and key ~= "" then
            spellToKeybind[spellID] = FormatKeybind(key)
        end
    end
end

-- Build itemID-to-slot mapping (for items on action bars)
local function BuildItemToSlotMap()
    wipe(itemToSlot)

    for slot = 1, MAX_ACTION_SLOTS do
        if HasAction(slot) then
            local actionType, id = GetActionInfo(slot)
            if actionType == "item" and id then
                if not itemToSlot[id] then
                    itemToSlot[id] = slot
                end
            elseif actionType == "macro" and id then
                -- Check if macro uses an item
                local macroName, macroIconTexture, macroBody = GetMacroInfo(id)
                if macroBody then
                    -- Look for #showtooltip item:XXXXX or /use item:XXXXX patterns
                    local itemID = macroBody:match("/use item:(%d+)") or
                                   macroBody:match("/cast item:(%d+)") or
                                   macroBody:match("#showtooltip item:(%d+)")
                    if itemID then
                        itemID = tonumber(itemID)
                        if itemID and not itemToSlot[itemID] then
                            itemToSlot[itemID] = slot
                        end
                    end
                end
            end
        end
    end
end

-- Build item-to-keybind mapping
local function BuildItemToKeybindMap()
    wipe(itemToKeybind)

    for itemID, slot in pairs(itemToSlot) do
        local key = slotToKeybind[slot]
        if key and key ~= "" then
            itemToKeybind[itemID] = FormatKeybind(key)
        end
    end
end

-- Build direct trinket slot keybinds
local function BuildTrinketKeybinds()
    wipe(trinketKeybinds)

    -- Check for direct trinket slot bindings
    local trinket1Key = GetBindingKey("TRINKET0SLOT")
    local trinket2Key = GetBindingKey("TRINKET1SLOT")

    -- Also check alternative binding names
    if not trinket1Key then
        trinket1Key = GetBindingKey("EXTRAACTIONBUTTON1")
    end

    -- Get equipped trinket itemIDs
    local trinket1ItemID = GetInventoryItemID("player", 13)  -- Slot 13 = Trinket 1
    local trinket2ItemID = GetInventoryItemID("player", 14)  -- Slot 14 = Trinket 2

    if trinket1Key and trinket1ItemID then
        trinketKeybinds[trinket1ItemID] = {
            raw = trinket1Key,
            formatted = FormatKeybind(trinket1Key),
            slot = 13,
        }
        -- Also add to itemToKeybind if not already there from action bars
        if not itemToKeybind[trinket1ItemID] then
            itemToKeybind[trinket1ItemID] = FormatKeybind(trinket1Key)
        end
    end

    if trinket2Key and trinket2ItemID then
        trinketKeybinds[trinket2ItemID] = {
            raw = trinket2Key,
            formatted = FormatKeybind(trinket2Key),
            slot = 14,
        }
        if not itemToKeybind[trinket2ItemID] then
            itemToKeybind[trinket2ItemID] = FormatKeybind(trinket2Key)
        end
    end
end

-- Full rescan of all keybinds
function KeybindScanner:FullScan()
    MedaBinds:Debug("KeybindScanner: Starting full scan")

    -- Invalidate all caches
    bindingCacheValid = false
    slotToKeybindValid = false
    cachedState.valid = false

    -- Rebuild caches
    RebuildBindingCache()
    UpdateCachedState()
    BuildSlotToKeybindMap()
    BuildSpellToSlotMap()
    BuildSpellToKeybindMap()

    -- Build item keybind caches
    BuildItemToSlotMap()
    BuildItemToKeybindMap()
    BuildTrinketKeybinds()

    MedaBinds:Debug("KeybindScanner: Scan complete. Found", self:GetCacheCount(), "spell keybinds,", self:GetItemCacheCount(), "item keybinds")

    -- Notify overlay manager to refresh
    if MedaBinds.OverlayManager then
        MedaBinds.OverlayManager:RefreshAllOverlays()
    end
end

-- Get keybind for a specific spellID (handles override/base spell lookups)
function KeybindScanner:GetKeybindForSpell(spellID)
    if not spellID or spellID == 0 then
        return nil
    end

    -- Direct lookup
    if spellToKeybind[spellID] then
        return spellToKeybind[spellID]
    end

    -- Try override spell (e.g., talent-modified abilities)
    if C_Spell.GetOverrideSpell then
        local overrideSpellID = C_Spell.GetOverrideSpell(spellID)
        if overrideSpellID and spellToKeybind[overrideSpellID] then
            return spellToKeybind[overrideSpellID]
        end
    end

    -- Try base spell
    if C_Spell.GetBaseSpell then
        local baseSpellID = C_Spell.GetBaseSpell(spellID)
        if baseSpellID and spellToKeybind[baseSpellID] then
            return spellToKeybind[baseSpellID]
        end
    end

    return nil
end

-- Get raw (unformatted) keybind for a spell
function KeybindScanner:GetRawKeybindForSpell(spellID)
    if not spellID or spellID == 0 then
        return nil
    end

    -- Find slot for this spell (or override/base)
    local slot = spellToSlot[spellID]

    if not slot and C_Spell.GetOverrideSpell then
        local overrideSpellID = C_Spell.GetOverrideSpell(spellID)
        if overrideSpellID then
            slot = spellToSlot[overrideSpellID]
        end
    end

    if not slot and C_Spell.GetBaseSpell then
        local baseSpellID = C_Spell.GetBaseSpell(spellID)
        if baseSpellID then
            slot = spellToSlot[baseSpellID]
        end
    end

    if slot then
        return slotToKeybind[slot]
    end

    return nil
end

-- Get keybind for an item (trinkets, usable items, etc.)
function KeybindScanner:GetKeybindForItem(itemID)
    if not itemID or itemID == 0 then
        return nil
    end

    -- Direct lookup
    if itemToKeybind[itemID] then
        return itemToKeybind[itemID]
    end

    -- Check trinket keybinds
    if trinketKeybinds[itemID] then
        return trinketKeybinds[itemID].formatted
    end

    return nil
end

-- Get raw (unformatted) keybind for an item
function KeybindScanner:GetRawKeybindForItem(itemID)
    if not itemID or itemID == 0 then
        return nil
    end

    -- Check trinket keybinds first
    if trinketKeybinds[itemID] then
        return trinketKeybinds[itemID].raw
    end

    -- Find slot for this item
    local slot = itemToSlot[itemID]
    if slot then
        return slotToKeybind[slot]
    end

    return nil
end

-- Get item cache count
function KeybindScanner:GetItemCacheCount()
    local count = 0
    for _ in pairs(itemToKeybind) do
        count = count + 1
    end
    return count
end

-- Force a complete rescan
function KeybindScanner:ForceRescan()
    self:FullScan()
end

-- Get count of cached keybinds
function KeybindScanner:GetCacheCount()
    local count = 0
    for _ in pairs(spellToKeybind) do
        count = count + 1
    end
    return count
end

-- Get all cached keybinds (for debugging)
function KeybindScanner:GetAllKeybinds()
    return spellToKeybind
end

-- Invalidate caches on state change
local function InvalidateCaches()
    bindingCacheValid = false
    slotToKeybindValid = false
    cachedState.valid = false
end

-- Event handlers
local eventFrame = CreateFrame("Frame")
local scanRequestedInCombat = false
local lastScanTime = 0
local SCAN_COOLDOWN = 0.5  -- Minimum seconds between scans

local function DoScan()
    -- Enforce cooldown between scans
    local now = GetTime()
    if now - lastScanTime < SCAN_COOLDOWN then
        return
    end
    lastScanTime = now

    InvalidateCaches()
    KeybindScanner:FullScan()
end

local function RequestScan(immediate)
    -- Skip during combat - keybinds can't be changed anyway
    if InCombatLockdown() then
        scanRequestedInCombat = true
        MedaBinds:Debug("KeybindScanner: Scan deferred (in combat)")
        return
    end

    -- Debounce rapid requests
    if KeybindScanner.scanPending then return end

    KeybindScanner.scanPending = true
    C_Timer.After(immediate and 0 or 0.1, function()
        KeybindScanner.scanPending = false
        DoScan()
    end)
end

local function OnEvent(self, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended - do deferred scan if one was requested
        if scanRequestedInCombat then
            scanRequestedInCombat = false
            MedaBinds:Debug("KeybindScanner: Running deferred scan (combat ended)")
            RequestScan(false)
        end
        return
    end

    if event == "UPDATE_BINDINGS" then
        -- User changed keybinds - scan immediately after combat check
        MedaBinds:Debug("KeybindScanner: Keybinds changed")
        RequestScan(true)
    elseif event == "UPDATE_BONUS_ACTIONBAR" or event == "UPDATE_SHAPESHIFT_FORM" then
        -- Class bar changed (druid forms, etc.) - need to remap slots
        MedaBinds:Debug("KeybindScanner: Class bar changed")
        cachedState.valid = false
        RequestScan(false)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
        -- Spec/talent change - spells on bars may have changed
        MedaBinds:Debug("KeybindScanner: Spec/talents changed")
        RequestScan(false)
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        -- User moved a spell on their action bar
        MedaBinds:Debug("KeybindScanner: Action bar slot changed")
        RequestScan(false)
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        -- Edit mode changed bar layout
        MedaBinds:Debug("KeybindScanner: Edit mode layout changed")
        RequestScan(false)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Zone load - good time for a fresh scan
        local isInitialLogin, isReloadingUI = ...
        if isInitialLogin or isReloadingUI then
            MedaBinds:Debug("KeybindScanner: Initial load scan")
            RequestScan(true)
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Equipment changed (trinkets swapped, etc.)
        local equipmentSlot = ...
        if equipmentSlot == 13 or equipmentSlot == 14 then  -- Trinket slots
            MedaBinds:Debug("KeybindScanner: Trinket changed in slot", equipmentSlot)
            RequestScan(false)
        end
    end
end

-- Initialize the scanner
function KeybindScanner:Initialize()
    MedaBinds:Debug("KeybindScanner: Initializing")

    -- Initial scan
    self:FullScan()
    lastScanTime = GetTime()

    -- Register for keybind-related events (minimal set)
    eventFrame:SetScript("OnEvent", OnEvent)

    -- Essential events
    eventFrame:RegisterEvent("UPDATE_BINDINGS")           -- User changed keybinds
    eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")    -- User moved spell on bar
    eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")    -- Class bar activation
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")    -- Druid forms, etc.
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED") -- Spec change
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")      -- Talent change
    eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED") -- Edit mode changes
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")     -- Zone/reload

    -- Combat tracking for deferred scans
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")      -- Combat ended

    -- Equipment changes (for trinket keybinds)
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")  -- Trinkets swapped

    -- NOT registered (too noisy or unnecessary):
    -- SPELLS_CHANGED - fires on buffs, way too frequent
    -- PLAYER_MOUNT_DISPLAY_CHANGED - doesn't affect keybinds
    -- ACTIONBAR_HIDEGRID - less reliable than ACTIONBAR_SLOT_CHANGED
    -- PLAYER_TALENT_UPDATE - TRAIT_CONFIG_UPDATED covers this

    MedaBinds:Debug("KeybindScanner: Initialized")
end
