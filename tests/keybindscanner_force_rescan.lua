local function assertEquals(expected, actual, message)
    if expected ~= actual then
        error(string.format("%s\nexpected: %s\nactual:   %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertTrue(value, message)
    if not value then
        error(message, 2)
    end
end

local function loadScanner()
    local inCombat = false
    local probeCount = 0
    local timers = {}
    local frames = {}

    _G.LE_EXPANSION_LEVEL_CURRENT = 12
    _G.wipe = function(tableValue)
        for key in pairs(tableValue) do
            tableValue[key] = nil
        end
    end

    _G.CreateFrame = function()
        local frame = { events = {} }

        function frame:RegisterEvent(eventName)
            self.events[eventName] = true
        end

        function frame:SetScript(scriptName, handler)
            self[scriptName] = handler
        end

        frames[#frames + 1] = frame
        return frame
    end

    _G.C_Timer = {
        After = function(_, callback)
            timers[#timers + 1] = callback
        end,
    }

    _G.GetTime = function()
        return 1
    end

    _G.InCombatLockdown = function()
        return inCombat
    end

    _G.GetBindingKey = function()
        probeCount = probeCount + 1
        return nil
    end

    _G.GetActionBarPage = function()
        return 1
    end

    _G.GetBonusBarOffset = function()
        return 0
    end

    _G.GetShapeshiftFormID = function()
        return 0
    end

    _G.HasOverrideActionBar = function()
        return false
    end

    _G.HasVehicleActionBar = function()
        return false
    end

    _G.HasTempShapeshiftActionBar = function()
        return false
    end

    _G.HasAction = function()
        probeCount = probeCount + 1
        return false
    end

    _G.GetInventoryItemID = function()
        return nil
    end

    local MedaBinds = {
        db = {
            options = {
                abbreviateKeybinds = true,
                customPagedKeybind = "",
                showPagedKeybinds = false,
            },
        },
        Debug = function() end,
    }

    local chunk = assert(loadfile("Core/KeybindScanner.lua"))
    chunk("MedaBinds", MedaBinds)

    return MedaBinds.KeybindScanner, {
        setCombat = function(value)
            inCombat = value
        end,
        getProbeCount = function()
            return probeCount
        end,
        resetProbeCount = function()
            probeCount = 0
        end,
        initialize = function()
            MedaBinds.KeybindScanner:Initialize()
        end,
        fire = function(eventName, ...)
            assertTrue(frames[1] and frames[1].OnEvent, "scanner event frame was not initialized")
            frames[1].OnEvent(frames[1], eventName, ...)
        end,
        runTimers = function()
            while #timers > 0 do
                local callback = table.remove(timers, 1)
                callback()
            end
        end,
    }
end

local function testForceRescanDefersInCombat()
    local scanner, env = loadScanner()
    env.initialize()
    env.setCombat(true)

    local result = scanner:ForceRescan()

    assertEquals(false, result, "ForceRescan should report that the scan was deferred in combat")
    assertEquals(0, env.getProbeCount(), "ForceRescan should not touch action or binding APIs in combat")
end

local function testDeferredForceRescanRunsAfterCombat()
    local scanner, env = loadScanner()
    env.initialize()
    env.setCombat(true)

    scanner:ForceRescan()
    env.resetProbeCount()
    env.setCombat(false)
    env.fire("PLAYER_REGEN_ENABLED")
    env.runTimers()

    assertTrue(env.getProbeCount() > 0, "deferred ForceRescan should run after combat ends")
end

local function testForceRescanRunsImmediatelyOutOfCombat()
    local scanner, env = loadScanner()
    env.initialize()

    local result = scanner:ForceRescan()

    assertEquals(true, result, "ForceRescan should report that it scanned immediately out of combat")
    assertTrue(env.getProbeCount() > 0, "ForceRescan should scan immediately out of combat")
end

testForceRescanDefersInCombat()
testDeferredForceRescanRunsAfterCombat()
testForceRescanRunsImmediatelyOutOfCombat()

print("keybindscanner_force_rescan: ok")
