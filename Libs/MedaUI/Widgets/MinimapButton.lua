--[[
    MedaUI Minimap Button Widget
    Creates themed minimap buttons with drag-around-minimap functionality
]]

local MedaUI = LibStub("MedaUI-1.0")
local Theme = MedaUI.Theme

-- Storage for minimap button positions
MedaUI.MinimapButtons = MedaUI.MinimapButtons or {}

--- Create a themed minimap button
--- @param name string Unique button name (used for saved position)
--- @param icon string|number Icon texture path or fileID
--- @param onClick function|nil Left-click handler
--- @param onRightClick function|nil Right-click handler
--- @return Button The created minimap button
function MedaUI:CreateMinimapButton(name, icon, onClick, onRightClick)
    local button = CreateFrame("Button", "MedaUI_MinimapButton_" .. name, Minimap, "BackdropTemplate")
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    button:SetBackdropColor(unpack(Theme.background))
    button:SetBackdropBorderColor(unpack(Theme.border))

    -- Icon
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("CENTER")
    button.icon:SetTexture(icon)

    -- Highlight texture
    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetColorTexture(unpack(Theme.highlight))

    -- Position management
    button.minimapAngle = self.MinimapButtons[name] or 225

    local function UpdatePosition()
        local angle = math.rad(button.minimapAngle)
        local x = math.cos(angle) * 80
        local y = math.sin(angle) * 80
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    -- Dragging
    local isDragging = false

    button:RegisterForDrag("LeftButton")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    button:SetScript("OnDragStart", function(self)
        isDragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale

            button.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
            MedaUI.MinimapButtons[name] = button.minimapAngle
            UpdatePosition()
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        isDragging = false
        self:SetScript("OnUpdate", nil)
    end)

    -- Click handlers
    button:SetScript("OnClick", function(self, btn)
        if isDragging then return end
        if btn == "LeftButton" and onClick then
            onClick()
        elseif btn == "RightButton" and onRightClick then
            onRightClick()
        end
    end)

    -- Hover effects
    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(Theme.gold))
        if button.tooltipTitle then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(button.tooltipTitle, unpack(Theme.gold))
            if button.tooltipText then
                GameTooltip:AddLine(button.tooltipText, unpack(Theme.text))
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Left-click to open", unpack(Theme.textDim))
            GameTooltip:AddLine("Right-click for options", unpack(Theme.textDim))
            GameTooltip:AddLine("Drag to move", unpack(Theme.textDim))
            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(Theme.border))
        GameTooltip:Hide()
    end)

    -- API methods
    function button:SetIcon(newIcon)
        self.icon:SetTexture(newIcon)
    end

    function button:SetTooltip(title, text)
        self.tooltipTitle = title
        self.tooltipText = text
    end

    function button:SetAngle(angle)
        self.minimapAngle = angle
        MedaUI.MinimapButtons[name] = angle
        UpdatePosition()
    end

    -- Initialize position
    UpdatePosition()

    return button
end
