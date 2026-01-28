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

-- Paged keybind caches
local pageKeybinds = {}      -- Maps page number to keybind (e.g., {[2] = "Q", [3] = "SHIFT-Q"})
local spellToPage = {}       -- Maps spellID to page number (1-6)
local pagedSpellKeybinds = {}  -- Maps spellID to formatted paged keybind

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

    -- Standard Blizzard binding patterns
    for _, pattern in ipairs(BINDING_PATTERNS) do
        for i = 1, NUM_ACTIONBAR_BUTTONS do
            local command = pattern .. i
            local key = GetBindingKey(command)
            if key then
                bindingCache[command] = key
            end
        end
    end

    bindingCacheValid = true
end

-- Build page keybind cache (detects ACTIONPAGE1-6 keybinds or uses manual override)
local function BuildPageKeybindCache()
    wipe(pageKeybinds)

    local options = MedaBinds.db and MedaBinds.db.options or {}
    local manualOverride = options.pageKeybindOverride

    -- Detect keybinds for action pages 1-6
    for page = 1, 6 do
        -- First check for manual override (for users with macro-based paging)
        -- The override applies to ALL pages (single key for page switching)
        if manualOverride and manualOverride ~= "" then
            pageKeybinds[page] = manualOverride
            MedaBinds:Debug("BuildPageKeybindCache: Page", page, "= (manual)", manualOverride)
        else
            -- Fall back to auto-detected ACTIONPAGE binding
            local key = GetBindingKey("ACTIONPAGE" .. page)
            if key then
                pageKeybinds[page] = key
                MedaBinds:Debug("BuildPageKeybindCache: Page", page, "=", key)
            end
        end
    end
end

-- Paged keybind separator (indicates key sequence)
local PAGED_SEPARATOR = ">"

-- Format a paged keybind based on user settings
local function FormatPagedKeybind(pageKey, slotKey, pageNum, options)
    local format = options.pagedKeybindFormat or "auto"

    if format == "custom" and options.customPagePrefix and options.customPagePrefix ~= "" then
        return options.customPagePrefix .. FormatKeybind(slotKey)
    elseif format == "pagenum" then
        return "P" .. pageNum .. PAGED_SEPARATOR .. FormatKeybind(slotKey)
    else -- "auto" or "pagekey"
        return FormatKeybind(pageKey) .. PAGED_SEPARATOR .. FormatKeybind(slotKey)
    end
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

    MedaBinds:Debug("BuildSlotToKeybindMap: page=", cachedState.page, "bonusOffset=", cachedState.bonusOffset)

    -- Main action bar (slots 1-12, or bonus bar slots)
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
-- Key insight: spells can exist in MULTIPLE slots, we must prefer slots that have keybinds
-- Now also tracks which page (1-6) each spell is on for paged keybind support
local function BuildSpellToSlotMap()
    wipe(spellToSlot)
    wipe(spellToPage)

    MedaBinds:Debug("BuildSpellToSlotMap: Scanning all slots, preferring those with keybinds")

    local currentPage = GetActionBarPage and GetActionBarPage() or 1

    -- Helper to check if we should use a new slot for a spell
    -- Priority: 1) slot with keybind, 2) current page, 3) first found
    local function ShouldUseSlot(spellID, newSlot, newPage)
        local existingSlot = spellToSlot[spellID]
        if not existingSlot then
            return true  -- No existing mapping, use this slot
        end

        local existingHasKey = slotToKeybind[existingSlot] ~= nil
        local newHasKey = slotToKeybind[newSlot] ~= nil

        -- Prefer slot with keybind
        if newHasKey and not existingHasKey then
            return true
        end

        -- If both have/lack keybinds equally, prefer current page
        if newHasKey == existingHasKey then
            local existingPage = spellToPage[spellID]
            if newPage == currentPage and existingPage ~= currentPage then
                return true
            end
        end

        return false  -- Keep existing mapping
    end

    -- First scan main bar pages 1-6 (slots 1-72) to track page info
    for page = 1, 6 do
        for buttonNum = 1, NUM_ACTIONBAR_BUTTONS do
            local slot = buttonNum + ((page - 1) * NUM_ACTIONBAR_BUTTONS)
            if HasAction(slot) then
                local actionType, id, subType = GetActionInfo(slot)
                if actionType == "spell" and id then
                    if ShouldUseSlot(id, slot, page) then
                        spellToSlot[id] = slot
                        spellToPage[id] = page
                    end
                elseif actionType == "macro" and id then
                    local macroSpellID = GetMacroSpell and GetMacroSpell(id)
                    if macroSpellID then
                        if ShouldUseSlot(macroSpellID, slot, page) then
                            spellToSlot[macroSpellID] = slot
                            spellToPage[macroSpellID] = page
                        end
                    end
                    if subType == "spell" and id then
                        if ShouldUseSlot(id, slot, page) then
                            spellToSlot[id] = slot
                            spellToPage[id] = page
                        end
                    end
                end
            end
        end
    end

    -- Scan remaining slots (skip 73-132 class bar range, handled separately if needed)
    for slot = 73, MAX_ACTION_SLOTS do
        if slot > 132 then  -- Skip class bar range 73-132
            if HasAction(slot) then
                local actionType, id, subType = GetActionInfo(slot)
                if actionType == "spell" and id then
                    if ShouldUseSlot(id, slot, nil) then
                        spellToSlot[id] = slot
                        -- Don't set spellToPage for non-main-bar spells
                    end
                elseif actionType == "macro" and id then
                    local macroSpellID = GetMacroSpell and GetMacroSpell(id)
                    if macroSpellID then
                        if ShouldUseSlot(macroSpellID, slot, nil) then
                            spellToSlot[macroSpellID] = slot
                        end
                    end
                    if subType == "spell" and id then
                        if ShouldUseSlot(id, slot, nil) then
                            spellToSlot[id] = slot
                        end
                    end
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

-- Build paged keybind map for spells on non-current pages ONLY
-- This map only contains spells that require a page switch to access
local function BuildPagedKeybindMap()
    wipe(pagedSpellKeybinds)

    local currentPage = GetActionBarPage and GetActionBarPage() or 1
    local options = MedaBinds.db and MedaBinds.db.options or {}

    MedaBinds:Debug("BuildPagedKeybindMap: currentPage =", currentPage, "showPagedKeybinds =", tostring(options.showPagedKeybinds))

    -- Skip if paged keybinds are disabled
    if options.showPagedKeybinds == false then
        MedaBinds:Debug("BuildPagedKeybindMap: DISABLED - skipping")
        return
    end

    for spellID, slot in pairs(spellToSlot) do
        local page = spellToPage[spellID]

        -- Only process spells on OTHER pages (not current page)
        -- and only if they're in the main bar page range (1-6)
        if page and page >= 1 and page <= 6 and page ~= currentPage then
            -- Skip if this spell already has a direct keybind (e.g., on a multibar)
            if spellToKeybind[spellID] then
                MedaBinds:Debug("BuildPagedKeybindMap: Skipping", spellID, "- has direct keybind:", spellToKeybind[spellID])
            else
                local buttonNum = ((slot - 1) % NUM_ACTIONBAR_BUTTONS) + 1
                local slotKey = bindingCache["ACTIONBUTTON" .. buttonNum]
                local pageKey = pageKeybinds[page]

                MedaBinds:Debug("BuildPagedKeybindMap: Checking spellID", spellID, "slot", slot, "page", page, "buttonNum", buttonNum, "slotKey", slotKey or "nil", "pageKey", pageKey or "nil")

                if slotKey and pageKey then
                    local formatted = FormatPagedKeybind(pageKey, slotKey, page, options)
                    pagedSpellKeybinds[spellID] = formatted
                    MedaBinds:Debug("BuildPagedKeybindMap: Created", spellID, "->", formatted)
                elseif not slotKey then
                    MedaBinds:Debug("BuildPagedKeybindMap: No slotKey for ACTIONBUTTON" .. buttonNum)
                elseif not pageKey then
                    MedaBinds:Debug("BuildPagedKeybindMap: No pageKey for page", page)
                end
            end
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

-- Light rescan - only rebuild paged keybind data (for settings changes)
function KeybindScanner:RebuildPagedKeybinds()
    BuildPageKeybindCache()
    BuildPagedKeybindMap()
    -- Notify overlay manager to refresh
    if MedaBinds.OverlayManager then
        MedaBinds.OverlayManager:RefreshAllOverlays()
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
    BuildPageKeybindCache()      -- Detect page switch keybinds (ACTIONPAGE1-6)
    UpdateCachedState()
    BuildSlotToKeybindMap()
    BuildSpellToSlotMap()        -- Now scans all pages and tracks spellToPage
    BuildSpellToKeybindMap()
    BuildPagedKeybindMap()       -- Create paged keybind strings

    -- Build item keybind caches
    BuildItemToSlotMap()
    BuildItemToKeybindMap()
    BuildTrinketKeybinds()

    MedaBinds:Debug("KeybindScanner: Scan complete. Found", self:GetCacheCount(), "spell keybinds,", self:GetItemCacheCount(), "item keybinds")

    -- Always output detailed debug when debug mode is on
    if MedaBinds.debug then
        MedaBinds:Debug("========================================")
        MedaBinds:Debug("KEYBIND SCANNER DEBUG REPORT")
        MedaBinds:Debug("========================================")

        -- Show page keybinds (ACTIONPAGE1-6 or manual override)
        MedaBinds:Debug("")
        MedaBinds:Debug("=== PAGE KEYBINDS ===")
        local manualOverride = MedaBinds.db and MedaBinds.db.options and MedaBinds.db.options.pageKeybindOverride or ""
        if manualOverride ~= "" then
            MedaBinds:Debug("Manual override:", manualOverride, "(applies to all pages)")
        end
        for page = 1, 6 do
            local key = pageKeybinds[page]
            if key then
                local source = (manualOverride ~= "") and "(manual)" or "(auto)"
                MedaBinds:Debug("Page", page, "=", key, source)
            else
                MedaBinds:Debug("Page", page, "= (not bound)")
            end
        end

        -- Show binding commands that have keys assigned
        MedaBinds:Debug("")
        MedaBinds:Debug("=== BINDING COMMANDS WITH KEYS ===")
        for _, pattern in ipairs(BINDING_PATTERNS) do
            for i = 1, NUM_ACTIONBAR_BUTTONS do
                local cmd = pattern .. i
                local key = bindingCache[cmd]
                if key then
                    MedaBinds:Debug(cmd, "=", key)
                end
            end
        end

        -- Show slot -> keybind map with contents
        MedaBinds:Debug("")
        MedaBinds:Debug("=== SLOTS WITH KEYBINDS (", self:CountSlotKeybinds(), " total) ===")
        local sortedSlots = {}
        for slot, key in pairs(slotToKeybind) do
            table.insert(sortedSlots, { slot = slot, key = key })
        end
        table.sort(sortedSlots, function(a, b) return a.slot < b.slot end)
        for _, info in ipairs(sortedSlots) do
            local actionType, id = GetActionInfo(info.slot)
            local content = "(empty)"
            if actionType == "spell" and id then
                local spellInfo = C_Spell.GetSpellInfo(id)
                content = "spell: " .. (spellInfo and spellInfo.name or "?") .. " (" .. id .. ")"
            elseif actionType == "macro" and id then
                local macroName = GetMacroInfo(id)
                local macroSpell = GetMacroSpell and GetMacroSpell(id)
                content = "macro: " .. (macroName or "?")
                if macroSpell then
                    local spellInfo = C_Spell.GetSpellInfo(macroSpell)
                    content = content .. " -> " .. (spellInfo and spellInfo.name or "?") .. " (" .. macroSpell .. ")"
                end
            elseif actionType then
                content = actionType .. ": " .. tostring(id)
            end
            MedaBinds:Debug("Slot", info.slot, "| Key:", info.key, "|", content)
        end

        -- Show spells that HAVE keybinds
        MedaBinds:Debug("")
        MedaBinds:Debug("=== SPELLS WITH KEYBINDS (", self:GetCacheCount(), " total) ===")
        local sortedSpells = {}
        for spellID, keybind in pairs(spellToKeybind) do
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            local name = spellInfo and spellInfo.name or "Unknown"
            local slot = spellToSlot[spellID] or "?"
            table.insert(sortedSpells, { name = name, spellID = spellID, slot = slot, keybind = keybind })
        end
        table.sort(sortedSpells, function(a, b) return a.name < b.name end)
        for _, info in ipairs(sortedSpells) do
            MedaBinds:Debug(info.name, "| Slot:", info.slot, "| Key:", info.keybind)
        end

        -- Show paged keybinds (spells on non-current pages)
        MedaBinds:Debug("")
        MedaBinds:Debug("=== PAGED KEYBINDS ===")
        local currentPage = GetActionBarPage and GetActionBarPage() or 1
        MedaBinds:Debug("Current page:", currentPage)
        local pagedCount = 0
        local sortedPaged = {}
        for spellID, keybind in pairs(pagedSpellKeybinds) do
            local page = spellToPage[spellID]
            if page and page ~= currentPage then
                pagedCount = pagedCount + 1
                local spellInfo = C_Spell.GetSpellInfo(spellID)
                local name = spellInfo and spellInfo.name or "Unknown"
                table.insert(sortedPaged, { name = name, spellID = spellID, page = page, keybind = keybind })
            end
        end
        table.sort(sortedPaged, function(a, b) return a.name < b.name end)
        for _, info in ipairs(sortedPaged) do
            MedaBinds:Debug(info.name, "| Page:", info.page, "| Key:", info.keybind)
        end
        if pagedCount == 0 then
            MedaBinds:Debug("(none - no spells on other pages with keybinds)")
        end

        -- Show spells WITHOUT keybinds - THIS IS KEY FOR DEBUGGING
        MedaBinds:Debug("")
        MedaBinds:Debug("=== SPELLS WITHOUT KEYBINDS (PROBLEMS) ===")
        local problemCount = 0
        for spellID, slot in pairs(spellToSlot) do
            if not spellToKeybind[spellID] then
                problemCount = problemCount + 1
                local spellInfo = C_Spell.GetSpellInfo(spellID)
                local name = spellInfo and spellInfo.name or "Unknown"
                local slotKey = slotToKeybind[slot]
                if slotKey then
                    MedaBinds:Debug(name, "| Slot:", slot, "| Slot has key:", slotKey, "but spell not mapped!")
                else
                    MedaBinds:Debug(name, "| Slot:", slot, "| NO KEYBIND FOR THIS SLOT")
                end
            end
        end
        if problemCount == 0 then
            MedaBinds:Debug("(none - all spells have keybinds)")
        end

        -- Show all action slots with content (to see what's on bars)
        MedaBinds:Debug("")
        MedaBinds:Debug("=== ALL OCCUPIED ACTION SLOTS ===")
        for slot = 1, MAX_ACTION_SLOTS do
            if HasAction(slot) then
                local actionType, id, subType = GetActionInfo(slot)
                local key = slotToKeybind[slot] or "NO KEY"
                local content = ""
                if actionType == "spell" and id then
                    local spellInfo = C_Spell.GetSpellInfo(id)
                    content = (spellInfo and spellInfo.name or "?") .. " (" .. id .. ")"
                elseif actionType == "macro" and id then
                    local macroName = GetMacroInfo(id)
                    content = "macro:" .. (macroName or id)
                else
                    content = (actionType or "?") .. ":" .. tostring(id)
                end
                MedaBinds:Debug("Slot", slot, "| Key:", key, "|", actionType, "|", content)
            end
        end

        MedaBinds:Debug("")
        MedaBinds:Debug("========================================")
        MedaBinds:Debug("END DEBUG REPORT")
        MedaBinds:Debug("========================================")
    end

    -- Notify overlay manager to refresh
    if MedaBinds.OverlayManager then
        MedaBinds.OverlayManager:RefreshAllOverlays()
    end
end

-- Get keybind for a specific spellID (handles override/base spell lookups)
-- Now checks paged keybinds first (includes current page direct keybinds)
function KeybindScanner:GetKeybindForSpell(spellID)
    if not spellID or spellID == 0 then
        return nil
    end

    local spellInfo = C_Spell.GetSpellInfo(spellID)
    local spellName = spellInfo and spellInfo.name or "Unknown"

    -- First check direct keybinds (from visible action bars)
    if spellToKeybind[spellID] then
        MedaBinds:Debug("GetKeybindForSpell:", spellName, "(", spellID, ") -> direct:", spellToKeybind[spellID])
        return spellToKeybind[spellID]
    end

    -- Then check paged keybinds (spells on other pages that require page switch)
    if pagedSpellKeybinds[spellID] then
        MedaBinds:Debug("GetKeybindForSpell:", spellName, "(", spellID, ") -> paged:", pagedSpellKeybinds[spellID])
        return pagedSpellKeybinds[spellID]
    end

    -- Try override spell (e.g., talent-modified abilities)
    if C_Spell.GetOverrideSpell then
        local overrideSpellID = C_Spell.GetOverrideSpell(spellID)
        if overrideSpellID and overrideSpellID ~= spellID then
            local overrideInfo = C_Spell.GetSpellInfo(overrideSpellID)
            local overrideName = overrideInfo and overrideInfo.name or "Unknown"
            MedaBinds:Debug("GetKeybindForSpell:", spellName, "-> checking override:", overrideName, "(", overrideSpellID, ")")
            -- Check direct keybinds for override first
            if spellToKeybind[overrideSpellID] then
                MedaBinds:Debug("GetKeybindForSpell:", spellName, "-> via override:", spellToKeybind[overrideSpellID])
                return spellToKeybind[overrideSpellID]
            end
            -- Then paged keybinds for override
            if pagedSpellKeybinds[overrideSpellID] then
                MedaBinds:Debug("GetKeybindForSpell:", spellName, "-> via override paged:", pagedSpellKeybinds[overrideSpellID])
                return pagedSpellKeybinds[overrideSpellID]
            end
        end
    end

    -- Try base spell
    if C_Spell.GetBaseSpell then
        local baseSpellID = C_Spell.GetBaseSpell(spellID)
        if baseSpellID and baseSpellID ~= spellID then
            local baseInfo = C_Spell.GetSpellInfo(baseSpellID)
            local baseName = baseInfo and baseInfo.name or "Unknown"
            MedaBinds:Debug("GetKeybindForSpell:", spellName, "-> checking base:", baseName, "(", baseSpellID, ")")
            -- Check direct keybinds for base first
            if spellToKeybind[baseSpellID] then
                MedaBinds:Debug("GetKeybindForSpell:", spellName, "-> via base:", spellToKeybind[baseSpellID])
                return spellToKeybind[baseSpellID]
            end
            -- Then paged keybinds for base
            if pagedSpellKeybinds[baseSpellID] then
                MedaBinds:Debug("GetKeybindForSpell:", spellName, "-> via base paged:", pagedSpellKeybinds[baseSpellID])
                return pagedSpellKeybinds[baseSpellID]
            end
        end
    end

    MedaBinds:Debug("GetKeybindForSpell:", spellName, "(", spellID, ") -> NOT FOUND")
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

-- Get count of slot keybinds
function KeybindScanner:CountSlotKeybinds()
    local count = 0
    for _ in pairs(slotToKeybind) do
        count = count + 1
    end
    return count
end

-- Get bar name and button number from a slot
function KeybindScanner:GetBarInfoForSlot(slot)
    if not slot or slot <= 0 then return nil, nil end

    local page = math.ceil(slot / NUM_ACTIONBAR_BUTTONS)
    local buttonNum = ((slot - 1) % NUM_ACTIONBAR_BUTTONS) + 1

    local barName = "Unknown"

    -- For main bar pages 1-6, show current vs other page info
    if page >= 1 and page <= 6 then
        local currentPage = GetActionBarPage and GetActionBarPage() or 1
        if page == currentPage then
            barName = "Main Bar"
        else
            barName = "Main Bar (Page " .. page .. ")"
        end
    elseif page >= 7 and page <= 11 then
        -- Class/bonus bar pages (73-132)
        barName = "Class Bar " .. (page - 6)
    elseif page == 12 then
        barName = "Bar 5"
    elseif page == 13 then
        barName = "Bar 6"
    elseif page == 14 then
        barName = "Bar 7"
    elseif page == 15 then
        barName = "Bar 8"
    end

    return barName, buttonNum
end

-- Get slot for a spell (exposed for external use)
function KeybindScanner:GetSlotForSpell(spellID)
    return spellToSlot[spellID]
end

-- Get page for a spell (1-6 for main bar, nil for other bars)
function KeybindScanner:GetPageForSpell(spellID)
    return spellToPage[spellID]
end

-- Check if a spell's keybind is a paged keybind (requires page switch)
-- Returns true only if the spell is in the pagedSpellKeybinds map
-- (meaning it's on another page AND doesn't have a direct keybind)
function KeybindScanner:IsPagedKeybind(spellID)
    return pagedSpellKeybinds[spellID] ~= nil
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

    -- Register for keybind-related events (minimal set)
    -- Note: Initial scan happens via PLAYER_ENTERING_WORLD event
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
