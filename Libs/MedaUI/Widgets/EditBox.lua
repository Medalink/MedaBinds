--[[
    MedaUI EditBox Widget
    Creates themed text input fields
]]

local MedaUI = LibStub("MedaUI-1.0")
local Theme = MedaUI.Theme

--- Create a themed edit box
--- @param parent Frame The parent frame
--- @param width number Edit box width
--- @param height number Edit box height (default: 24)
--- @param isMultiLine boolean|nil Whether to allow multiple lines
--- @return EditBox The created edit box
function MedaUI:CreateEditBox(parent, width, height, isMultiLine)
    height = height or 24

    -- Container with backdrop
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(width, height)
    container:SetBackdrop(self:CreateBackdrop(true))
    container:SetBackdropColor(unpack(Theme.input))
    container:SetBackdropBorderColor(unpack(Theme.border))

    -- EditBox
    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetPoint("TOPLEFT", 6, -4)
    editBox:SetPoint("BOTTOMRIGHT", -6, 4)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetTextColor(unpack(Theme.text))
    editBox:SetAutoFocus(false)
    editBox:SetMultiLine(isMultiLine or false)

    if not isMultiLine then
        editBox:SetMaxLetters(256)
    end

    -- Focus effects
    editBox:SetScript("OnEditFocusGained", function()
        container:SetBackdropBorderColor(unpack(Theme.gold))
    end)

    editBox:SetScript("OnEditFocusLost", function()
        container:SetBackdropBorderColor(unpack(Theme.border))
    end)

    -- Enter key handling (single line)
    if not isMultiLine then
        editBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            if container.OnEnterPressed then
                container:OnEnterPressed(self:GetText())
            end
        end)
    end

    -- Escape to clear focus
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Text changed callback
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and container.OnTextChanged then
            container:OnTextChanged(self:GetText())
        end
    end)

    -- Hover effect on container
    container:SetScript("OnEnter", function(self)
        if not editBox:HasFocus() then
            self:SetBackdropBorderColor(unpack(Theme.borderLight))
        end
    end)

    container:SetScript("OnLeave", function(self)
        if not editBox:HasFocus() then
            self:SetBackdropBorderColor(unpack(Theme.border))
        end
    end)

    -- Click container to focus
    container:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)

    -- Expose editBox methods on container
    container.editBox = editBox

    function container:SetText(text)
        self.editBox:SetText(text or "")
    end

    function container:GetText()
        return self.editBox:GetText()
    end

    function container:SetPlaceholder(text)
        -- Simple placeholder implementation
        self.placeholder = text
        if self.editBox:GetText() == "" then
            self.editBox:SetText(text)
            self.editBox:SetTextColor(unpack(Theme.textDim))
        end

        self.editBox:HookScript("OnEditFocusGained", function(eb)
            if eb:GetText() == self.placeholder then
                eb:SetText("")
                eb:SetTextColor(unpack(Theme.text))
            end
        end)

        self.editBox:HookScript("OnEditFocusLost", function(eb)
            if eb:GetText() == "" then
                eb:SetText(self.placeholder)
                eb:SetTextColor(unpack(Theme.textDim))
            end
        end)
    end

    function container:ClearFocus()
        self.editBox:ClearFocus()
    end

    function container:SetFocus()
        self.editBox:SetFocus()
    end

    return container
end
