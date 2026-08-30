---@class QuestieConfigNextWidgets
local QuestieConfigNextWidgets = QuestieLoader:CreateModule("QuestieConfigNextWidgets")

local unpack = unpack or table.unpack
local floor = math.floor
local max = math.max
local min = math.min

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local activeTheme

local fallbackTheme = {
    windowBg = {0.035, 0.041, 0.051, 0.97},
    headerBg = {0.062, 0.070, 0.086, 0.98},
    panelBg = {0.050, 0.058, 0.074, 0.95},
    insetBg = {0.018, 0.022, 0.031, 0.95},
    border = {0.676, 0.551, 0.266, 0.94},
    borderSoft = {0.196, 0.215, 0.247, 0.88},
    accent = {0.082, 0.855, 0.804, 0.98},
    accentSoft = {0.082, 0.855, 0.804, 0.22},
    text = {1.000, 0.859, 0.349, 1.00},
    textBright = {1.000, 0.941, 0.545, 1.00},
    textMuted = {0.772, 0.804, 0.855, 1.00},
    textSoft = {0.584, 0.627, 0.690, 1.00},
    navIdleBg = {0.040, 0.047, 0.062, 0.86},
    navHoverBg = {0.062, 0.074, 0.094, 0.92},
    navActiveBg = {0.094, 0.113, 0.141, 0.98},
    navIdleText = {0.804, 0.831, 0.882, 1.00},
    navActiveText = {1.000, 0.925, 0.529, 1.00},
    closeHover = {0.929, 0.451, 0.302, 1.00},
}

local backdropCache = {}

local function _Theme()
    return activeTheme or fallbackTheme
end

local function _Backdrop(edgeSize)
    edgeSize = edgeSize or 1
    if not backdropCache[edgeSize] then
        backdropCache[edgeSize] = {
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = true,
            tileSize = 16,
            edgeSize = edgeSize,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        }
    end
    return backdropCache[edgeSize]
end

local function _FetchFont(name)
    if LSM then
        local ok, path = pcall(LSM.Fetch, LSM, "font", name, true)
        if ok and path then
            return path
        end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function _Round(value, step)
    step = tonumber(step) or 1
    if step <= 0 then
        return value
    end
    return floor((value / step) + 0.5) * step
end

local function _Clamp(value, low, high)
    return max(low, min(high, value))
end

local function _ShowTooltip(owner, title, description)
    if not description or description == "" then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    GameTooltip:SetText(title or "Setting", 1, 0.86, 0.35)
    GameTooltip:AddLine(description, 0.82, 0.85, 0.90, true)
    GameTooltip:Show()
end

local function _HideTooltip()
    if GameTooltip:IsOwned(UIParent) then
        return
    end
    GameTooltip:Hide()
end

local function _GetDisabled(spec)
    return spec.disabled and spec.disabled() or false
end

function QuestieConfigNextWidgets:SetTheme(theme)
    activeTheme = theme or fallbackTheme
end

function QuestieConfigNextWidgets:GetTheme()
    return _Theme()
end

function QuestieConfigNextWidgets:ApplyBackdrop(frame, background, border, edgeSize)
    frame:SetBackdrop(_Backdrop(edgeSize))
    frame:SetBackdropColor(unpack(background or _Theme().panelBg))
    frame:SetBackdropBorderColor(unpack(border or _Theme().borderSoft))
end

function QuestieConfigNextWidgets:CreateSolid(parent, layer, color, subLevel)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    if subLevel then
        texture:SetDrawLayer(layer or "BACKGROUND", subLevel)
    end
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    texture:SetVertexColor(unpack(color or {1, 1, 1, 1}))
    return texture
end

function QuestieConfigNextWidgets:CreateFont(parent, size, color, style)
    local font = parent:CreateFontString(nil, "OVERLAY")
    local fontName = style == "value" and "Source Code Pro (Regular)" or "Expressway"
    local flags = style == "title" and "OUTLINE" or ""
    font:SetFont(_FetchFont(fontName), size or 12, flags)
    font:SetTextColor(unpack(color or _Theme().textMuted))
    font:SetJustifyH("LEFT")
    font:SetJustifyV("MIDDLE")
    return font
end

function QuestieConfigNextWidgets:AttachTooltip(frame, title, description)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        _ShowTooltip(self, title, description)
    end)
    frame:SetScript("OnLeave", _HideTooltip)
end

function QuestieConfigNextWidgets:CreateButton(parent, spec)
    local widget = CreateFrame("Button", nil, parent)
    widget:SetHeight(spec.height or 30)
    widget:RegisterForClicks("LeftButtonUp")
    widget.qcLayoutHeight = spec.height or 30
    widget.qcSearchText = string.lower((spec.name or "") .. " " .. (spec.description or ""))
    QuestieConfigNextWidgets:ApplyBackdrop(widget, _Theme().navIdleBg, _Theme().borderSoft, 1)

    widget.label = QuestieConfigNextWidgets:CreateFont(widget, 12, _Theme().textBright)
    widget.label:SetPoint("LEFT", widget, "LEFT", 12, 0)
    widget.label:SetPoint("RIGHT", widget, "RIGHT", -12, 0)
    widget.label:SetJustifyH(spec.align or "CENTER")
    widget.label:SetText(spec.name or "Action")

    function widget:Refresh()
        local disabled = _GetDisabled(spec)
        self.qcDisabled = disabled
        self.label:SetTextColor(unpack(disabled and _Theme().textSoft or _Theme().textBright))
        self:SetBackdropColor(unpack(disabled and _Theme().insetBg or _Theme().navIdleBg))
        self:SetBackdropBorderColor(unpack(disabled and _Theme().borderSoft or _Theme().accent))
    end

    widget:SetScript("OnEnter", function(self)
        if not self.qcDisabled then
            self:SetBackdropColor(unpack(_Theme().navHoverBg))
        end
        _ShowTooltip(self, spec.name, spec.description)
    end)
    widget:SetScript("OnLeave", function(self)
        self:Refresh()
        _HideTooltip()
    end)
    widget:SetScript("OnMouseDown", function(self)
        if not self.qcDisabled then
            self.label:SetPoint("LEFT", self, "LEFT", 12, -1)
            self.label:SetPoint("RIGHT", self, "RIGHT", -12, -1)
        end
    end)
    widget:SetScript("OnMouseUp", function(self)
        self.label:SetPoint("LEFT", self, "LEFT", 12, 0)
        self.label:SetPoint("RIGHT", self, "RIGHT", -12, 0)
    end)
    widget:SetScript("OnClick", function(self)
        if self.qcDisabled then
            return
        end
        if spec.onClick then
            spec.onClick()
        end
        if spec.onChanged then
            spec.onChanged()
        end
        self:Refresh()
    end)
    widget:Refresh()
    return widget
end

function QuestieConfigNextWidgets:CreateToggle(parent, spec)
    local widget = CreateFrame("Button", nil, parent)
    widget:SetHeight(34)
    widget:RegisterForClicks("LeftButtonUp")
    widget.qcLayoutHeight = 34
    widget.qcSearchText = string.lower((spec.name or "") .. " " .. (spec.description or ""))

    widget.hover = QuestieConfigNextWidgets:CreateSolid(widget, "BACKGROUND", _Theme().accentSoft)
    widget.hover:SetAllPoints()
    widget.hover:Hide()

    widget.label = QuestieConfigNextWidgets:CreateFont(widget, 12, _Theme().textMuted)
    widget.label:SetPoint("LEFT", widget, "LEFT", 4, 0)
    widget.label:SetPoint("RIGHT", widget, "RIGHT", -64, 0)
    widget.label:SetText(spec.name or "Toggle")

    widget.switch = CreateFrame("Frame", nil, widget)
    widget.switch:SetSize(42, 18)
    widget.switch:SetPoint("RIGHT", widget, "RIGHT", -4, 0)
    QuestieConfigNextWidgets:ApplyBackdrop(widget.switch, _Theme().insetBg, _Theme().borderSoft, 1)

    widget.fill = QuestieConfigNextWidgets:CreateSolid(widget.switch, "BACKGROUND", _Theme().accentSoft)
    widget.fill:SetPoint("TOPLEFT", widget.switch, "TOPLEFT", 1, -1)
    widget.fill:SetPoint("BOTTOMRIGHT", widget.switch, "BOTTOMRIGHT", -1, 1)

    widget.thumb = QuestieConfigNextWidgets:CreateSolid(widget.switch, "ARTWORK", _Theme().textSoft)
    widget.thumb:SetSize(14, 14)

    function widget:Refresh()
        local disabled = _GetDisabled(spec)
        local checked = spec.get and spec.get() and true or false
        self.qcDisabled = disabled
        self.qcChecked = checked
        self.label:SetTextColor(unpack(disabled and _Theme().textSoft or _Theme().textMuted))
        self.switch:SetBackdropBorderColor(unpack(checked and _Theme().accent or _Theme().borderSoft))
        self.fill:SetVertexColor(unpack(checked and _Theme().accentSoft or _Theme().insetBg))
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint(checked and "RIGHT" or "LEFT", self.switch, checked and "RIGHT" or "LEFT", checked and -2 or 2, 0)
        self.thumb:SetVertexColor(unpack(disabled and _Theme().textSoft or (checked and _Theme().accent or _Theme().textMuted)))
    end

    widget:SetScript("OnEnter", function(self)
        self.hover:SetVertexColor(unpack(_Theme().accentSoft))
        self.hover:Show()
        _ShowTooltip(self, spec.name, spec.description)
    end)
    widget:SetScript("OnLeave", function(self)
        self.hover:Hide()
        _HideTooltip()
    end)
    widget:SetScript("OnClick", function(self)
        if self.qcDisabled then
            return
        end
        if spec.set then
            spec.set(not self.qcChecked)
        end
        if spec.onChanged then
            spec.onChanged()
        end
        self:Refresh()
    end)
    widget:Refresh()
    return widget
end

function QuestieConfigNextWidgets:CreateSegmented(parent, spec)
    local widget = CreateFrame("Frame", nil, parent)
    widget:SetHeight(38)
    widget.qcLayoutHeight = 38
    widget.qcSearchText = string.lower((spec.name or "") .. " " .. (spec.description or ""))
    widget.options = spec.options or {}
    widget.buttons = {}

    widget.label = QuestieConfigNextWidgets:CreateFont(widget, 12, _Theme().textMuted)
    widget.label:SetText(spec.name or "Choice")

    widget.group = CreateFrame("Frame", nil, widget)

    for index, option in ipairs(widget.options) do
        local button = CreateFrame("Button", nil, widget.group)
        button:RegisterForClicks("LeftButtonUp")
        QuestieConfigNextWidgets:ApplyBackdrop(button, _Theme().insetBg, _Theme().borderSoft, 1)
        button.label = QuestieConfigNextWidgets:CreateFont(button, 11, _Theme().textMuted)
        button.label:SetPoint("LEFT", button, "LEFT", 5, 0)
        button.label:SetPoint("RIGHT", button, "RIGHT", -5, 0)
        button.label:SetJustifyH("CENTER")
        button.label:SetText(option.label)
        button.value = option.value
        button.qcReadOnly = option.readOnly
        button:SetScript("OnClick", function(self)
            if widget.qcDisabled or self.qcReadOnly or widget.qcValue == self.value then
                return
            end
            if spec.set then
                spec.set(self.value)
            end
            if spec.onChanged then
                spec.onChanged()
            end
            widget:Refresh()
        end)
        button:SetScript("OnEnter", function(self)
            if not widget.qcDisabled and widget.qcValue ~= self.value then
                self:SetBackdropColor(unpack(_Theme().navHoverBg))
            end
            _ShowTooltip(widget, spec.name, spec.description)
        end)
        button:SetScript("OnLeave", function()
            widget:Refresh()
            _HideTooltip()
        end)
        widget.buttons[index] = button
    end

    function widget:Layout(width)
        self:SetWidth(width)
        local stacked = width < 470
        self.qcLayoutHeight = stacked and 64 or 38
        self:SetHeight(self.qcLayoutHeight)
        self.label:ClearAllPoints()
        self.group:ClearAllPoints()
        if stacked then
            self.label:SetPoint("TOPLEFT", self, "TOPLEFT", 4, -4)
            self.label:SetPoint("TOPRIGHT", self, "TOPRIGHT", -4, -4)
            self.group:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 4, 3)
            self.group:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -4, 3)
            self.group:SetHeight(27)
        else
            local groupWidth = min(320, max(235, floor(width * 0.58)))
            self.label:SetPoint("LEFT", self, "LEFT", 4, 0)
            self.label:SetPoint("RIGHT", self, "RIGHT", -(groupWidth + 12), 0)
            self.group:SetPoint("RIGHT", self, "RIGHT", -4, 0)
            self.group:SetSize(groupWidth, 27)
        end

        local count = max(1, #self.buttons)
        local spacing = 3
        local buttonWidth = (self.group:GetWidth() - ((count - 1) * spacing)) / count
        for index, button in ipairs(self.buttons) do
            button:ClearAllPoints()
            button:SetSize(buttonWidth, 27)
            if index == 1 then
                button:SetPoint("LEFT", self.group, "LEFT", 0, 0)
            else
                button:SetPoint("LEFT", self.buttons[index - 1], "RIGHT", spacing, 0)
            end
        end
    end

    function widget:Refresh()
        local disabled = _GetDisabled(spec)
        local value = spec.get and spec.get()
        self.qcDisabled = disabled
        self.qcValue = value
        self.label:SetTextColor(unpack(disabled and _Theme().textSoft or _Theme().textMuted))
        for _, button in ipairs(self.buttons) do
            local active = button.value == value
            button:SetBackdropColor(unpack(active and _Theme().navActiveBg or _Theme().insetBg))
            button:SetBackdropBorderColor(unpack(active and _Theme().accent or _Theme().borderSoft))
            button.label:SetTextColor(unpack((disabled or (button.qcReadOnly and not active)) and _Theme().textSoft or (active and _Theme().textBright or _Theme().textMuted)))
        end
    end

    widget:Layout(500)
    widget:Refresh()
    return widget
end

function QuestieConfigNextWidgets:CreateSlider(parent, spec)
    local widget = CreateFrame("Frame", nil, parent)
    widget:SetHeight(52)
    widget.qcLayoutHeight = 52
    widget.qcSearchText = string.lower((spec.name or "") .. " " .. (spec.description or ""))

    widget.label = QuestieConfigNextWidgets:CreateFont(widget, 12, _Theme().textMuted)
    widget.label:SetPoint("TOPLEFT", widget, "TOPLEFT", 4, -3)
    widget.label:SetText(spec.name or "Value")

    widget.valueText = QuestieConfigNextWidgets:CreateFont(widget, 11, _Theme().textBright, "value")
    widget.valueText:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -4, -3)
    widget.valueText:SetJustifyH("RIGHT")

    local function _CreateStepButton(symbol)
        local button = CreateFrame("Button", nil, widget)
        button:SetSize(24, 22)
        button:RegisterForClicks("LeftButtonUp")
        QuestieConfigNextWidgets:ApplyBackdrop(button, _Theme().insetBg, _Theme().borderSoft, 1)
        button.label = QuestieConfigNextWidgets:CreateFont(button, 15, _Theme().textMuted)
        button.label:SetAllPoints()
        button.label:SetJustifyH("CENTER")
        button.label:SetText(symbol)
        return button
    end

    widget.minus = _CreateStepButton("-")
    widget.minus:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 4, 3)
    widget.plus = _CreateStepButton("+")
    widget.plus:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -4, 3)

    widget.slider = CreateFrame("Slider", nil, widget)
    widget.slider:SetOrientation("HORIZONTAL")
    widget.slider:SetPoint("LEFT", widget.minus, "RIGHT", 10, 0)
    widget.slider:SetPoint("RIGHT", widget.plus, "LEFT", -10, 0)
    widget.slider:SetHeight(22)
    widget.slider:SetMinMaxValues(spec.min or 0, spec.max or 100)
    widget.slider:SetValueStep(spec.step or 1)
    widget.track = QuestieConfigNextWidgets:CreateSolid(widget.slider, "BACKGROUND", _Theme().borderSoft)
    widget.track:SetPoint("LEFT", widget.slider, "LEFT", 0, 0)
    widget.track:SetPoint("RIGHT", widget.slider, "RIGHT", 0, 0)
    widget.track:SetHeight(3)
    widget.slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    widget.thumb = widget.slider:GetThumbTexture()
    widget.thumb:SetSize(10, 18)

    local function _SetValue(value, notify)
        value = _Clamp(_Round(tonumber(value) or spec.min or 0, spec.step), spec.min or 0, spec.max or 100)
        widget.qcValue = value
        widget.qcSilent = true
        widget.slider:SetValue(value)
        widget.qcSilent = false
        widget.valueText:SetText(spec.format and spec.format(value) or tostring(value))
        if notify and spec.set then
            spec.set(value)
            if spec.onChanged then
                spec.onChanged()
            end
        end
    end

    widget.slider:SetScript("OnValueChanged", function(_, value)
        if widget.qcSilent or widget.qcDisabled then
            return
        end
        _SetValue(value, true)
    end)
    widget.slider:SetScript("OnEnter", function()
        _ShowTooltip(widget, spec.name, spec.description)
    end)
    widget.slider:SetScript("OnLeave", _HideTooltip)

    local function _Step(direction)
        if widget.qcDisabled then
            return
        end
        _SetValue((widget.qcValue or 0) + ((spec.step or 1) * direction), true)
    end

    widget.minus:SetScript("OnClick", function() _Step(-1) end)
    widget.plus:SetScript("OnClick", function() _Step(1) end)
    widget.minus:SetScript("OnEnter", function(self)
        if not widget.qcDisabled then self:SetBackdropColor(unpack(_Theme().navHoverBg)) end
        _ShowTooltip(widget, spec.name, spec.description)
    end)
    widget.plus:SetScript("OnEnter", widget.minus:GetScript("OnEnter"))
    widget.minus:SetScript("OnLeave", function(self) widget:Refresh(); _HideTooltip() end)
    widget.plus:SetScript("OnLeave", widget.minus:GetScript("OnLeave"))

    function widget:Refresh()
        local disabled = _GetDisabled(spec)
        self.qcDisabled = disabled
        _SetValue(spec.get and spec.get() or spec.min or 0, false)
        self.label:SetTextColor(unpack(disabled and _Theme().textSoft or _Theme().textMuted))
        self.valueText:SetTextColor(unpack(disabled and _Theme().textSoft or _Theme().textBright))
        self.track:SetVertexColor(unpack(disabled and _Theme().borderSoft or _Theme().accentSoft))
        self.thumb:SetVertexColor(unpack(disabled and _Theme().textSoft or _Theme().accent))
        self.slider:EnableMouse(not disabled)
        for _, button in ipairs({self.minus, self.plus}) do
            button:SetBackdropColor(unpack(_Theme().insetBg))
            button:SetBackdropBorderColor(unpack(disabled and _Theme().borderSoft or _Theme().accentSoft))
            button.label:SetTextColor(unpack(disabled and _Theme().textSoft or _Theme().textMuted))
        end
    end

    widget:Refresh()
    return widget
end

local function _ColorHex(r, g, b)
    return string.format("#%02X%02X%02X", floor(_Clamp(r or 0, 0, 1) * 255 + 0.5), floor(_Clamp(g or 0, 0, 1) * 255 + 0.5), floor(_Clamp(b or 0, 0, 1) * 255 + 0.5))
end

function QuestieConfigNextWidgets:CreateColor(parent, spec)
    local widget = CreateFrame("Button", nil, parent)
    widget:SetHeight(36)
    widget:RegisterForClicks("LeftButtonUp")
    widget.qcLayoutHeight = 36
    widget.qcSearchText = string.lower((spec.name or "") .. " " .. (spec.description or ""))

    widget.hover = QuestieConfigNextWidgets:CreateSolid(widget, "BACKGROUND", _Theme().accentSoft)
    widget.hover:SetAllPoints()
    widget.hover:Hide()
    widget.label = QuestieConfigNextWidgets:CreateFont(widget, 12, _Theme().textMuted)
    widget.label:SetPoint("LEFT", widget, "LEFT", 4, 0)
    widget.label:SetPoint("RIGHT", widget, "RIGHT", -146, 0)
    widget.label:SetText(spec.name or "Color")

    widget.valueText = QuestieConfigNextWidgets:CreateFont(widget, 10, _Theme().textSoft, "value")
    widget.valueText:SetPoint("RIGHT", widget, "RIGHT", -34, 0)
    widget.valueText:SetWidth(104)
    widget.valueText:SetJustifyH("RIGHT")

    widget.swatch = CreateFrame("Frame", nil, widget)
    widget.swatch:SetSize(24, 20)
    widget.swatch:SetPoint("RIGHT", widget, "RIGHT", -4, 0)
    QuestieConfigNextWidgets:ApplyBackdrop(widget.swatch, _Theme().insetBg, _Theme().borderSoft, 1)
    widget.swatchColor = QuestieConfigNextWidgets:CreateSolid(widget.swatch, "ARTWORK", {1, 1, 1, 1})
    widget.swatchColor:SetPoint("TOPLEFT", widget.swatch, "TOPLEFT", 3, -3)
    widget.swatchColor:SetPoint("BOTTOMRIGHT", widget.swatch, "BOTTOMRIGHT", -3, 3)

    local function _ReadColor()
        local r, g, b, a = spec.get()
        return tonumber(r) or 0, tonumber(g) or 0, tonumber(b) or 0, tonumber(a) or 1
    end

    local function _ApplyPickerColor()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        local a = 1
        if spec.hasAlpha and OpacitySliderFrame then
            a = 1 - (OpacitySliderFrame:GetValue() or 0)
        end
        spec.set(r, g, b, a)
        if spec.onChanged then
            spec.onChanged()
        end
        widget:Refresh()
    end

    function widget:Refresh()
        local disabled = _GetDisabled(spec)
        local r, g, b, a = _ReadColor()
        self.qcDisabled = disabled
        self.label:SetTextColor(unpack(disabled and _Theme().textSoft or _Theme().textMuted))
        self.valueText:SetTextColor(unpack(disabled and _Theme().textSoft or _Theme().textSoft))
        self.swatch:SetBackdropBorderColor(unpack(disabled and _Theme().borderSoft or _Theme().accentSoft))
        self.swatchColor:SetVertexColor(r, g, b, disabled and 0.35 or max(0.35, a))
        if spec.hasAlpha then
            self.valueText:SetText(string.format("%s  %d%%", _ColorHex(r, g, b), floor(a * 100 + 0.5)))
        else
            self.valueText:SetText(_ColorHex(r, g, b))
        end
    end

    widget:SetScript("OnEnter", function(self)
        self.hover:Show()
        _ShowTooltip(self, spec.name, spec.description)
    end)
    widget:SetScript("OnLeave", function(self)
        self.hover:Hide()
        _HideTooltip()
    end)
    widget:SetScript("OnClick", function(self)
        if self.qcDisabled then
            return
        end
        local r, g, b, a = _ReadColor()
        self.qcPickerStart = {r, g, b, a}
        ColorPickerFrame.hasOpacity = spec.hasAlpha and true or false
        ColorPickerFrame.opacity = 1 - a
        ColorPickerFrame.previousValues = {r, g, b}
        ColorPickerFrame.func = _ApplyPickerColor
        ColorPickerFrame.opacityFunc = _ApplyPickerColor
        ColorPickerFrame.cancelFunc = function()
            local old = widget.qcPickerStart
            spec.set(old[1], old[2], old[3], old[4])
            if spec.onChanged then
                spec.onChanged()
            end
            widget:Refresh()
        end
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end)
    widget:Refresh()
    return widget
end

function QuestieConfigNextWidgets:CreateScrollArea(parent)
    local area = CreateFrame("Frame", nil, parent)
    local viewport = CreateFrame("ScrollFrame", nil, area)
    local content = CreateFrame("Frame", nil, viewport)
    local track = CreateFrame("Frame", nil, area)
    local thumb = CreateFrame("Button", nil, track)

    viewport:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
    viewport:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -15, 0)
    viewport:EnableMouseWheel(true)
    content:SetSize(1, 1)
    viewport:SetScrollChild(content)

    track:SetPoint("TOPRIGHT", area, "TOPRIGHT", -2, -2)
    track:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -2, 2)
    track:SetWidth(9)
    QuestieConfigNextWidgets:ApplyBackdrop(track, _Theme().insetBg, _Theme().borderSoft, 1)
    thumb:SetWidth(7)
    QuestieConfigNextWidgets:ApplyBackdrop(thumb, _Theme().accentSoft, _Theme().accent, 1)

    area.viewport = viewport
    area.content = content
    area.track = track
    area.thumb = thumb
    area.contentHeight = 1

    function area:RefreshRange()
        local viewportHeight = max(1, self.viewport:GetHeight() or 1)
        local trackHeight = max(1, self.track:GetHeight() - 2)
        local maximum = max(0, (self.contentHeight or 1) - viewportHeight)
        local scroll = _Clamp(self.viewport:GetVerticalScroll() or 0, 0, maximum)
        local thumbHeight = maximum > 0 and max(30, floor(trackHeight * (viewportHeight / self.contentHeight))) or trackHeight
        thumbHeight = min(trackHeight, thumbHeight)
        self.maximum = maximum
        self.viewport:SetVerticalScroll(scroll)
        self.thumb:SetHeight(thumbHeight)
        self.thumb:ClearAllPoints()
        local travel = max(0, trackHeight - thumbHeight)
        local offset = maximum > 0 and ((scroll / maximum) * travel) or 0
        self.thumb:SetPoint("TOP", self.track, "TOP", 0, -(1 + offset))
        self.track:SetAlpha(maximum > 0 and 1 or 0.32)
    end

    function area:SetContentHeight(height)
        self.contentHeight = max(1, height or 1)
        self.content:SetHeight(self.contentHeight)
        self:RefreshRange()
    end

    function area:SetContentWidth(width)
        self.content:SetWidth(max(1, width or 1))
    end

    function area:ScrollToTop()
        self.viewport:SetVerticalScroll(0)
        self:RefreshRange()
    end

    local function _ScrollBy(delta)
        area.viewport:SetVerticalScroll(_Clamp((area.viewport:GetVerticalScroll() or 0) + delta, 0, area.maximum or 0))
        area:RefreshRange()
    end

    viewport:SetScript("OnMouseWheel", function(_, delta)
        _ScrollBy(-delta * 44)
    end)
    area:SetScript("OnSizeChanged", function()
        area:RefreshRange()
    end)

    local function _StopThumbDrag()
        thumb.qcDragging = nil
        thumb:SetScript("OnUpdate", nil)
    end

    thumb:RegisterForDrag("LeftButton")
    thumb:SetScript("OnDragStart", function(self)
        if (area.maximum or 0) <= 0 then
            return
        end
        local _, cursorY = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        self.qcDragging = true
        self.qcStartCursorY = cursorY / (uiScale > 0 and uiScale or 1)
        self.qcStartScroll = area.viewport:GetVerticalScroll() or 0
        self:SetScript("OnUpdate", function(button)
            if not button.qcDragging then
                return
            end
            local _, currentY = GetCursorPosition()
            currentY = currentY / (uiScale > 0 and uiScale or 1)
            local travel = max(1, area.track:GetHeight() - 2 - button:GetHeight())
            local scrollDelta = (button.qcStartCursorY - currentY) * ((area.maximum or 0) / travel)
            area.viewport:SetVerticalScroll(_Clamp(button.qcStartScroll + scrollDelta, 0, area.maximum or 0))
            area:RefreshRange()
        end)
    end)
    thumb:SetScript("OnDragStop", _StopThumbDrag)
    thumb:SetScript("OnHide", _StopThumbDrag)
    thumb:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(_Theme().accent))
    end)
    thumb:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(_Theme().accentSoft))
    end)

    return area
end
