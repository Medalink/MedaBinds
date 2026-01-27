--[[
    MedaUI Radio Button Widget
    Creates themed radio buttons for option groups
]]

local MedaUI = LibStub("MedaUI-1.0")
local Theme = MedaUI.Theme

-- Radio group management
MedaUI.RadioGroups = MedaUI.RadioGroups or {}

--- Create a themed radio button
--- @param parent Frame The parent frame
--- @param label string Radio button label text
--- @param group string|nil Optional group name for mutual exclusion
--- @return Frame The radio button container frame
function MedaUI:CreateRadio(parent, label, group)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(200, 20)
    container.group = group

    -- Radio circle (using a square with rounded appearance via backdrop)
    local box = CreateFrame("Button", nil, container, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 0, 0)
    box:SetBackdrop(self:CreateBackdrop(true))
    box:SetBackdropColor(unpack(Theme.input))
    box:SetBackdropBorderColor(unpack(Theme.border))

    -- Selected indicator (inner dot)
    box.dot = box:CreateTexture(nil, "OVERLAY")
    box.dot:SetSize(8, 8)
    box.dot:SetPoint("CENTER")
    box.dot:SetColorTexture(unpack(Theme.gold))
    box.dot:Hide()

    -- Label
    container.label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    container.label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    container.label:SetText(label)
    container.label:SetTextColor(unpack(Theme.text))

    -- State
    container.selected = false
    container.box = box

    -- Register with group
    if group then
        self.RadioGroups[group] = self.RadioGroups[group] or {}
        table.insert(self.RadioGroups[group], container)
    end

    -- Click behavior
    box:SetScript("OnClick", function()
        container:SetSelected(true)
        if container.OnValueChanged then
            container:OnValueChanged(true)
        end
    end)

    -- Hover effect
    box:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(Theme.gold))
    end)

    box:SetScript("OnLeave", function(self)
        if not container.selected then
            self:SetBackdropBorderColor(unpack(Theme.border))
        end
    end)

    -- API methods
    function container:SetSelected(value)
        -- Deselect others in group
        if value and self.group and MedaUI.RadioGroups[self.group] then
            for _, radio in ipairs(MedaUI.RadioGroups[self.group]) do
                if radio ~= self then
                    radio.selected = false
                    radio.box.dot:Hide()
                    radio.box:SetBackdropBorderColor(unpack(Theme.border))
                end
            end
        end

        self.selected = value
        if value then
            box.dot:Show()
            box:SetBackdropBorderColor(unpack(Theme.gold))
        else
            box.dot:Hide()
            box:SetBackdropBorderColor(unpack(Theme.border))
        end
    end

    function container:GetSelected()
        return self.selected
    end

    function container:SetLabel(text)
        self.label:SetText(text)
    end

    return container
end

--- Get the selected radio button in a group
--- @param group string The group name
--- @return Frame|nil The selected radio button or nil
function MedaUI:GetSelectedRadio(group)
    if self.RadioGroups[group] then
        for _, radio in ipairs(self.RadioGroups[group]) do
            if radio.selected then
                return radio
            end
        end
    end
    return nil
end
