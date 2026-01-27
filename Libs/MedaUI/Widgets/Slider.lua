--[[
    MedaUI Slider Widget
    Creates themed sliders with value display
]]

local MedaUI = LibStub("MedaUI-1.0")
local Theme = MedaUI.Theme

--- Create a themed slider
--- @param parent Frame The parent frame
--- @param width number Slider width
--- @param min number Minimum value
--- @param max number Maximum value
--- @param step number|nil Step increment (default: 1)
--- @return Frame The slider container frame
function MedaUI:CreateSlider(parent, width, min, max, step)
    step = step or 1

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 32)

    -- Track background
    local track = CreateFrame("Frame", nil, container, "BackdropTemplate")
    track:SetSize(width - 40, 6)
    track:SetPoint("LEFT", 0, 0)
    track:SetBackdrop(self:CreateBackdrop(true))
    track:SetBackdropColor(unpack(Theme.backgroundDark))
    track:SetBackdropBorderColor(unpack(Theme.border))

    -- Filled portion of track
    local fill = track:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("LEFT", 1, 0)
    fill:SetHeight(4)
    fill:SetColorTexture(unpack(Theme.gold))

    -- Thumb (draggable handle)
    local thumb = CreateFrame("Button", nil, container, "BackdropTemplate")
    thumb:SetSize(14, 18)
    thumb:SetBackdrop(self:CreateBackdrop(true))
    thumb:SetBackdropColor(unpack(Theme.backgroundLight))
    thumb:SetBackdropBorderColor(unpack(Theme.gold))
    thumb:SetPoint("CENTER", track, "LEFT", 0, 0)

    -- Value display
    local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueText:SetPoint("LEFT", track, "RIGHT", 8, 0)
    valueText:SetTextColor(unpack(Theme.text))
    valueText:SetWidth(32)
    valueText:SetJustifyH("RIGHT")

    -- State
    container.min = min
    container.max = max
    container.step = step
    container.value = min

    -- Helper to update visual
    local function UpdateSlider()
        local pct = (container.value - min) / (max - min)
        local trackWidth = track:GetWidth() - 2
        thumb:SetPoint("CENTER", track, "LEFT", 1 + (pct * trackWidth), 0)
        fill:SetWidth(math.max(1, pct * trackWidth))

        -- Format value display
        if step < 1 then
            valueText:SetText(string.format("%.1f", container.value))
        else
            valueText:SetText(tostring(math.floor(container.value)))
        end
    end

    -- Dragging logic
    local isDragging = false

    local function OnUpdate()
        if not isDragging then return end

        local x = GetCursorPosition() / UIParent:GetEffectiveScale()
        local left = track:GetLeft() + 1
        local right = track:GetRight() - 1
        local pct = math.max(0, math.min(1, (x - left) / (right - left)))

        local rawValue = min + (pct * (max - min))
        local steppedValue = math.floor(rawValue / step + 0.5) * step
        steppedValue = math.max(min, math.min(max, steppedValue))

        if steppedValue ~= container.value then
            container.value = steppedValue
            UpdateSlider()
            if container.OnValueChanged then
                container:OnValueChanged(steppedValue)
            end
        end
    end

    thumb:SetScript("OnMouseDown", function()
        isDragging = true
        thumb:SetScript("OnUpdate", OnUpdate)
    end)

    thumb:SetScript("OnMouseUp", function()
        isDragging = false
        thumb:SetScript("OnUpdate", nil)
    end)

    -- Click on track to jump
    track:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            isDragging = true
            thumb:SetScript("OnUpdate", OnUpdate)
            OnUpdate()
        end
    end)

    track:SetScript("OnMouseUp", function()
        isDragging = false
        thumb:SetScript("OnUpdate", nil)
    end)

    -- Hover effects
    thumb:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(Theme.buttonHover))
    end)

    thumb:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(Theme.backgroundLight))
    end)

    -- API methods
    function container:SetValue(value)
        value = math.max(self.min, math.min(self.max, value))
        value = math.floor(value / self.step + 0.5) * self.step
        self.value = value
        UpdateSlider()
    end

    function container:GetValue()
        return self.value
    end

    function container:SetMinMaxValues(newMin, newMax)
        self.min = newMin
        self.max = newMax
        self:SetValue(self.value)
    end

    -- Initialize
    UpdateSlider()

    return container
end
