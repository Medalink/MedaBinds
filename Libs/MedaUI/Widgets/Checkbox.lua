--[[
    MedaUI Checkbox Widget
    Creates themed checkboxes with labels
]]

local MedaUI = LibStub("MedaUI-1.0")
local Theme = MedaUI.Theme

--- Create a themed checkbox
--- @param parent Frame The parent frame
--- @param label string Checkbox label text
--- @return Frame The checkbox container frame
function MedaUI:CreateCheckbox(parent, label)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(200, 20)

    -- Checkbox box
    local box = CreateFrame("Button", nil, container, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 0, 0)
    box:SetBackdrop(self:CreateBackdrop(true))
    box:SetBackdropColor(unpack(Theme.input))
    box:SetBackdropBorderColor(unpack(Theme.border))

    -- Checkmark
    box.check = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    box.check:SetPoint("CENTER", 0, 1)
    box.check:SetText("")
    box.check:SetTextColor(unpack(Theme.gold))

    -- Label
    container.label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    container.label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    container.label:SetText(label)
    container.label:SetTextColor(unpack(Theme.text))

    -- State
    container.checked = false

    -- Click behavior
    box:SetScript("OnClick", function()
        container.checked = not container.checked
        box.check:SetText(container.checked and "x" or "")
        if container.OnValueChanged then
            container:OnValueChanged(container.checked)
        end
    end)

    -- Hover effect
    box:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(Theme.gold))
    end)

    box:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(Theme.border))
    end)

    -- API methods
    function container:SetChecked(value)
        self.checked = value
        box.check:SetText(value and "x" or "")
    end

    function container:GetChecked()
        return self.checked
    end

    function container:SetLabel(text)
        self.label:SetText(text)
    end

    return container
end
