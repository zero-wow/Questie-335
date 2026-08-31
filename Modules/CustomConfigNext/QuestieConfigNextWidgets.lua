---@class QuestieConfigNextWidgets
local QuestieConfigNextWidgets = QuestieLoader:CreateModule("QuestieConfigNextWidgets")

local unpack = unpack or table.unpack
local floor = math.floor
local max = math.max
local min = math.min

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local activeTheme
local selectPopup
local selectMeasure
local selectOptionCache = {}
local selectMetadataCache = {}
local SELECT_VISIBLE_ROWS = 10
local SELECT_ROW_HEIGHT = 22

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

function QuestieConfigNextWidgets:SetShown(region, shown)
    if shown then
        region:Show()
    else
        region:Hide()
    end
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
    widget:SetHeight(spec.height or 28)
    widget:RegisterForClicks("LeftButtonUp")
    widget.qcLayoutHeight = spec.height or 28
    widget.qcFullWidth = spec.fullWidth and true or false
    widget.qcSearchText = string.lower((spec.name or "") .. " " .. (spec.description or ""))
    QuestieConfigNextWidgets:ApplyBackdrop(widget, _Theme().navIdleBg, _Theme().borderSoft, 1)

    widget.label = QuestieConfigNextWidgets:CreateFont(widget, 11, _Theme().textMuted)
    widget.label:SetText(spec.name or "Action")
    widget.qcMinimumWidth = max(120, widget.label:GetStringWidth() + 24)
    widget.label:SetPoint("LEFT", widget, "LEFT", 9, 0)
    widget.label:SetPoint("RIGHT", widget, "RIGHT", -9, 0)
    widget.label:SetJustifyH(spec.align or "CENTER")

    function widget:Refresh()
        local disabled = _GetDisabled(spec)
        self.qcDisabled = disabled
        self.label:SetTextColor(unpack(disabled and _Theme().textSoft or _Theme().textMuted))
        self:SetBackdropColor(unpack(disabled and _Theme().insetBg or _Theme().navIdleBg))
        self:SetBackdropBorderColor(unpack((not disabled and spec.primary) and _Theme().accent or _Theme().borderSoft))
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
            self.label:ClearAllPoints()
            self.label:SetPoint("LEFT", self, "LEFT", 9, -1)
            self.label:SetPoint("RIGHT", self, "RIGHT", -9, -1)
        end
    end)
    widget:SetScript("OnMouseUp", function(self)
        self.label:ClearAllPoints()
        self.label:SetPoint("LEFT", self, "LEFT", 9, 0)
        self.label:SetPoint("RIGHT", self, "RIGHT", -9, 0)
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
    widget:SetHeight(30)
    widget:RegisterForClicks("LeftButtonUp")
    widget.qcLayoutHeight = 30
    widget.qcFullWidth = spec.fullWidth and true or false
    widget.qcSearchText = string.lower((spec.name or "") .. " " .. (spec.description or ""))

    widget.hover = QuestieConfigNextWidgets:CreateSolid(widget, "BACKGROUND", _Theme().navHoverBg)
    widget.hover:SetAllPoints()
    widget.hover:Hide()

    widget.label = QuestieConfigNextWidgets:CreateFont(widget, 11, _Theme().textMuted)
    widget.label:SetText(spec.name or "Toggle")
    widget.qcMinimumWidth = max(150, widget.label:GetStringWidth() + 58)
    widget.label:SetPoint("LEFT", widget, "LEFT", 3, 0)
    widget.label:SetPoint("RIGHT", widget, "RIGHT", -52, 0)

    widget.switch = CreateFrame("Frame", nil, widget)
    widget.switch:SetSize(36, 16)
    widget.switch:SetPoint("RIGHT", widget, "RIGHT", -3, 0)
    QuestieConfigNextWidgets:ApplyBackdrop(widget.switch, _Theme().insetBg, _Theme().borderSoft, 1)

    widget.fill = QuestieConfigNextWidgets:CreateSolid(widget.switch, "BACKGROUND", _Theme().accentSoft)
    widget.fill:SetPoint("TOPLEFT", widget.switch, "TOPLEFT", 1, -1)
    widget.fill:SetPoint("BOTTOMRIGHT", widget.switch, "BOTTOMRIGHT", -1, 1)

    widget.thumb = QuestieConfigNextWidgets:CreateSolid(widget.switch, "ARTWORK", _Theme().textSoft)
    widget.thumb:SetSize(12, 12)

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
        self.hover:SetVertexColor(unpack(_Theme().navHoverBg))
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
    widget:SetHeight(34)
    widget.qcLayoutHeight = 34
    widget.qcFullWidth = true
    widget.qcMinimumWidth = 390
    widget.qcSearchText = string.lower((spec.name or "") .. " " .. (spec.description or ""))
    widget.options = spec.options or {}
    widget.buttons = {}

    widget.label = QuestieConfigNextWidgets:CreateFont(widget, 11, _Theme().textMuted)
    widget.label:SetText(spec.name or "Choice")

    widget.group = CreateFrame("Frame", nil, widget)

    for index, option in ipairs(widget.options) do
        local button = CreateFrame("Button", nil, widget.group)
        button:RegisterForClicks("LeftButtonUp")
        QuestieConfigNextWidgets:ApplyBackdrop(button, _Theme().insetBg, _Theme().borderSoft, 1)
        button.label = QuestieConfigNextWidgets:CreateFont(button, 10, _Theme().textMuted)
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
        local stacked = width < 440
        self.qcLayoutHeight = stacked and 56 or 34
        self:SetHeight(self.qcLayoutHeight)
        self.label:ClearAllPoints()
        self.group:ClearAllPoints()
        if stacked then
            self.label:SetPoint("TOPLEFT", self, "TOPLEFT", 3, -2)
            self.label:SetPoint("TOPRIGHT", self, "TOPRIGHT", -3, -2)
            self.group:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 3, 2)
            self.group:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -3, 2)
            self.group:SetHeight(24)
        else
            local groupWidth = min(300, max(220, floor(width * 0.56)))
            self.label:SetPoint("LEFT", self, "LEFT", 3, 0)
            self.label:SetPoint("RIGHT", self, "RIGHT", -(groupWidth + 9), 0)
            self.group:SetPoint("RIGHT", self, "RIGHT", -3, 0)
            self.group:SetSize(groupWidth, 24)
        end

        local count = max(1, #self.buttons)
        local spacing = 3
        local buttonWidth = (self.group:GetWidth() - ((count - 1) * spacing)) / count
        for index, button in ipairs(self.buttons) do
            button:ClearAllPoints()
            button:SetSize(buttonWidth, 24)
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
    widget:SetHeight(44)
    widget.qcLayoutHeight = 44
    widget.qcFullWidth = spec.fullWidth ~= false
    widget.qcMinimumWidth = spec.minWidth or 280
    widget.qcSearchText = string.lower((spec.name or "") .. " " .. (spec.description or ""))

    widget.label = QuestieConfigNextWidgets:CreateFont(widget, 11, _Theme().textMuted)
    widget.label:SetPoint("TOPLEFT", widget, "TOPLEFT", 3, -1)
    widget.label:SetText(spec.name or "Value")

    widget.valueText = QuestieConfigNextWidgets:CreateFont(widget, 10, _Theme().textBright, "value")
    widget.valueText:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -3, -1)
    widget.valueText:SetJustifyH("RIGHT")

    local function _CreateStepButton(symbol)
        local button = CreateFrame("Button", nil, widget)
        button:SetSize(20, 18)
        button:RegisterForClicks("LeftButtonUp")
        QuestieConfigNextWidgets:ApplyBackdrop(button, _Theme().insetBg, _Theme().borderSoft, 1)
        button.label = QuestieConfigNextWidgets:CreateFont(button, 13, _Theme().textMuted)
        button.label:SetAllPoints()
        button.label:SetJustifyH("CENTER")
        button.label:SetText(symbol)
        return button
    end

    widget.minus = _CreateStepButton("-")
    widget.minus:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 3, 2)
    widget.plus = _CreateStepButton("+")
    widget.plus:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -3, 2)

    widget.slider = CreateFrame("Slider", nil, widget)
    widget.slider:SetOrientation("HORIZONTAL")
    widget.slider:SetPoint("LEFT", widget.minus, "RIGHT", 8, 0)
    widget.slider:SetPoint("RIGHT", widget.plus, "LEFT", -8, 0)
    widget.slider:SetHeight(18)
    widget.slider:SetMinMaxValues(spec.min or 0, spec.max or 100)
    widget.slider:SetValueStep(spec.step or 1)
    widget.track = QuestieConfigNextWidgets:CreateSolid(widget.slider, "BACKGROUND", _Theme().borderSoft)
    widget.track:SetPoint("LEFT", widget.slider, "LEFT", 0, 0)
    widget.track:SetPoint("RIGHT", widget.slider, "RIGHT", 0, 0)
    widget.track:SetHeight(3)
    widget.slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    widget.thumb = widget.slider:GetThumbTexture()
    widget.thumb:SetSize(8, 16)

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
    widget.slider:SetScript("OnMouseUp", function()
        if not widget.qcDisabled and spec.onDragStop then
            spec.onDragStop(widget.qcValue)
        end
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
        self.track:SetVertexColor(unpack(_Theme().borderSoft))
        self.thumb:SetVertexColor(unpack(disabled and _Theme().textSoft or _Theme().accent))
        self.slider:EnableMouse(not disabled)
        for _, button in ipairs({self.minus, self.plus}) do
            button:SetBackdropColor(unpack(_Theme().insetBg))
            button:SetBackdropBorderColor(unpack(_Theme().borderSoft))
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
    widget:SetHeight(30)
    widget:RegisterForClicks("LeftButtonUp")
    widget.qcLayoutHeight = 30
    widget.qcFullWidth = spec.fullWidth and true or false
    widget.qcSearchText = string.lower((spec.name or "") .. " " .. (spec.description or ""))

    widget.hover = QuestieConfigNextWidgets:CreateSolid(widget, "BACKGROUND", _Theme().navHoverBg)
    widget.hover:SetAllPoints()
    widget.hover:Hide()
    widget.label = QuestieConfigNextWidgets:CreateFont(widget, 11, _Theme().textMuted)
    widget.label:SetText(spec.name or "Color")
    widget.qcMinimumWidth = max(150, widget.label:GetStringWidth() + 48)
    widget.label:SetPoint("LEFT", widget, "LEFT", 3, 0)

    widget.valueText = QuestieConfigNextWidgets:CreateFont(widget, 10, _Theme().textSoft, "value")
    widget.valueText:SetPoint("RIGHT", widget, "RIGHT", -29, 0)
    widget.valueText:SetWidth(100)
    widget.valueText:SetJustifyH("RIGHT")

    widget.swatch = CreateFrame("Frame", nil, widget)
    widget.swatch:SetSize(20, 16)
    widget.swatch:SetPoint("RIGHT", widget, "RIGHT", -3, 0)
    QuestieConfigNextWidgets:ApplyBackdrop(widget.swatch, _Theme().insetBg, _Theme().borderSoft, 1)
    widget.swatchColor = QuestieConfigNextWidgets:CreateSolid(widget.swatch, "ARTWORK", {1, 1, 1, 1})
    widget.swatchColor:SetPoint("TOPLEFT", widget.swatch, "TOPLEFT", 2, -2)
    widget.swatchColor:SetPoint("BOTTOMRIGHT", widget.swatch, "BOTTOMRIGHT", -2, 2)

    function widget:Layout(width)
        self:SetWidth(width)
        self.label:ClearAllPoints()
        self.label:SetPoint("LEFT", self, "LEFT", 3, 0)
        if width < 290 then
            self.valueText:Hide()
            self.label:SetPoint("RIGHT", self, "RIGHT", -29, 0)
        else
            self.valueText:Show()
            self.label:SetPoint("RIGHT", self, "RIGHT", -136, 0)
        end
    end

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
        self.swatch:SetBackdropBorderColor(unpack(_Theme().borderSoft))
        self.swatchColor:SetVertexColor(r, g, b, disabled and 0.35 or max(0.35, a))
        if spec.hasAlpha then
            self.valueText:SetText(string.format("%s  %d%%", _ColorHex(r, g, b), floor(a * 100 + 0.5)))
        else
            self.valueText:SetText(_ColorHex(r, g, b))
        end
    end

    widget:SetScript("OnEnter", function(self)
        self.hover:SetVertexColor(unpack(_Theme().navHoverBg))
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
    widget:Layout(320)
    widget:Refresh()
    return widget
end

local function _NormalizeSelectOptions(spec)
    if spec.cacheKey and selectOptionCache[spec.cacheKey] then
        return selectOptionCache[spec.cacheKey]
    end

    local source = type(spec.options) == "function" and spec.options() or spec.options or {}
    local options = {}

    if #source > 0 then
        for _, option in ipairs(source) do
            if type(option) == "table" then
                options[#options + 1] = {
                    value = option.value,
                    label = tostring(option.label or option.value or ""),
                }
            else
                options[#options + 1] = {value = option, label = tostring(option)}
            end
        end
    else
        for value, label in pairs(source) do
            options[#options + 1] = {value = value, label = tostring(label)}
        end
        table.sort(options, function(a, b)
            return string.upper(a.label) < string.upper(b.label)
        end)
    end

    if spec.firstValue ~= nil then
        for index, option in ipairs(options) do
            if option.value == spec.firstValue and index ~= 1 then
                table.remove(options, index)
                table.insert(options, 1, option)
                break
            end
        end
    end

    if spec.cacheKey then
        selectOptionCache[spec.cacheKey] = options
    end
    return options
end

local function _MeasureSelectOption(label, fontPath)
    if not selectMeasure then
        selectMeasure = UIParent:CreateFontString(nil, "OVERLAY")
        selectMeasure:Hide()
    end
    selectMeasure:SetFont(fontPath or _FetchFont("Expressway"), 11, "")
    selectMeasure:SetText(label or "")
    return selectMeasure:GetStringWidth() or 0
end

local function _RefreshSelectPopup()
    local popup = selectPopup
    local owner = popup and popup.owner
    if not (popup and owner) then
        return
    end

    local query = popup.searchable and string.lower(popup.search:GetText() or "") or ""
    local filtered = popup.filtered
    for index = #filtered, 1, -1 do
        filtered[index] = nil
    end
    for _, option in ipairs(owner.qcOptions) do
        if query == "" or string.find(string.lower(option.label), query, 1, true) then
            filtered[#filtered + 1] = option
        end
    end

    popup.visibleRows = min(SELECT_VISIBLE_ROWS, max(1, #filtered))
    popup:SetHeight(8 + (popup.visibleRows * SELECT_ROW_HEIGHT) + (popup.searchable and 29 or 0))
    popup.maximumOffset = max(0, #filtered - popup.visibleRows)
    popup.offset = _Clamp(popup.offset or 0, 0, popup.maximumOffset)
    local selectedValue = owner.qcValue
    for index, row in ipairs(popup.rows) do
        local option = index <= popup.visibleRows and filtered[index + popup.offset] or nil
        if option then
            row.qcOption = option
            row.label:SetText(option.label)
            if owner.qcSpec.fontPreview and owner.qcSpec.fontPath then
                row.label:SetFont(owner.qcSpec.fontPath(option.value), 11, "")
            else
                row.label:SetFont(_FetchFont("Expressway"), 11, "")
            end
            local selected = option.value == selectedValue
            row:SetBackdropColor(unpack(selected and _Theme().navActiveBg or _Theme().insetBg))
            row:SetBackdropBorderColor(0, 0, 0, 0)
            row.label:SetTextColor(unpack(selected and _Theme().navActiveText or _Theme().textMuted))
            row:Show()
        else
            row.qcOption = nil
            row:Hide()
        end
    end

    QuestieConfigNextWidgets:SetShown(popup.noResults, #filtered == 0)
    QuestieConfigNextWidgets:SetShown(popup.track, popup.maximumOffset > 0)
    if popup.maximumOffset > 0 then
        local trackHeight = popup.track:GetHeight() - 2
        local thumbHeight = max(28, floor(trackHeight * (popup.visibleRows / #filtered)))
        thumbHeight = min(trackHeight, thumbHeight)
        local travel = max(0, trackHeight - thumbHeight)
        local offset = (popup.offset / popup.maximumOffset) * travel
        popup.thumb:SetHeight(thumbHeight)
        popup.thumb:ClearAllPoints()
        popup.thumb:SetPoint("TOP", popup.track, "TOP", 0, -(1 + offset))
    end
end

local function _ScrollSelectPopup(delta)
    local popup = selectPopup
    if not (popup and popup.owner and popup.maximumOffset) then
        return
    end
    popup.offset = _Clamp((popup.offset or 0) + delta, 0, popup.maximumOffset)
    _RefreshSelectPopup()
end

local function _EnsureSelectPopup()
    if selectPopup then
        return selectPopup
    end

    local popup = CreateFrame("Frame", "QuestieConfigNextSelectPopup", UIParent)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(320)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:EnableMouseWheel(true)
    QuestieConfigNextWidgets:ApplyBackdrop(popup, _Theme().windowBg, _Theme().borderSoft, 1)
    popup.filtered = {}
    popup.rows = {}

    popup.search = CreateFrame("EditBox", nil, popup)
    popup.search:SetHeight(24)
    popup.search:SetAutoFocus(false)
    popup.search:SetMaxLetters(80)
    popup.search:SetFont(_FetchFont("Source Code Pro (Regular)"), 11, "")
    popup.search:SetTextColor(unpack(_Theme().textMuted))
    popup.search:SetTextInsets(7, 24, 0, 0)
    QuestieConfigNextWidgets:ApplyBackdrop(popup.search, _Theme().insetBg, _Theme().borderSoft, 1)
    popup.search.placeholder = QuestieConfigNextWidgets:CreateFont(popup.search, 10, _Theme().textSoft, "value")
    popup.search.placeholder:SetPoint("LEFT", popup.search, "LEFT", 7, 0)
    popup.search.placeholder:SetText("Search")
    popup.search.clear = CreateFrame("Button", nil, popup.search)
    popup.search.clear:SetSize(20, 20)
    popup.search.clear:SetPoint("RIGHT", popup.search, "RIGHT", -2, 0)
    popup.search.clear.label = QuestieConfigNextWidgets:CreateFont(popup.search.clear, 12, _Theme().textSoft, "title")
    popup.search.clear.label:SetAllPoints()
    popup.search.clear.label:SetJustifyH("CENTER")
    popup.search.clear.label:SetText("x")
    popup.search.clear:SetScript("OnClick", function()
        popup.search:SetText("")
        popup.search:SetFocus()
    end)
    popup.search:SetScript("OnEditFocusGained", function(self)
        self.placeholder:Hide()
        self:SetBackdropBorderColor(unpack(_Theme().accent))
    end)
    popup.search:SetScript("OnEditFocusLost", function(self)
        QuestieConfigNextWidgets:SetShown(self.placeholder, self:GetText() == "")
        self:SetBackdropBorderColor(unpack(_Theme().borderSoft))
    end)
    popup.search:SetScript("OnEscapePressed", function() popup:Hide() end)
    popup.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    popup.search:SetScript("OnTextChanged", function(self)
        local hasText = self:GetText() ~= ""
        QuestieConfigNextWidgets:SetShown(self.placeholder, not hasText and not self:HasFocus())
        QuestieConfigNextWidgets:SetShown(self.clear, hasText)
        popup.offset = 0
        _RefreshSelectPopup()
    end)

    popup.track = CreateFrame("Frame", nil, popup)
    popup.track:SetWidth(7)
    QuestieConfigNextWidgets:ApplyBackdrop(popup.track, _Theme().insetBg, _Theme().borderSoft, 1)
    popup.thumb = CreateFrame("Button", nil, popup.track)
    popup.thumb:SetWidth(5)
    QuestieConfigNextWidgets:ApplyBackdrop(popup.thumb, _Theme().accentSoft, _Theme().accent, 1)
    popup.thumb:RegisterForDrag("LeftButton")
    popup.thumb:SetScript("OnDragStart", function(self)
        if (popup.maximumOffset or 0) <= 0 then
            return
        end
        local _, cursorY = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        self.qcStartCursorY = cursorY / (uiScale > 0 and uiScale or 1)
        self.qcStartOffset = popup.offset or 0
        self:SetScript("OnUpdate", function(button)
            local _, currentY = GetCursorPosition()
            currentY = currentY / (uiScale > 0 and uiScale or 1)
            local travel = max(1, popup.track:GetHeight() - 2 - button:GetHeight())
            local rowDelta = ((button.qcStartCursorY - currentY) / travel) * popup.maximumOffset
            popup.offset = _Clamp(floor(button.qcStartOffset + rowDelta + 0.5), 0, popup.maximumOffset)
            _RefreshSelectPopup()
        end)
    end)
    local function _StopSelectThumb(self)
        self:SetScript("OnUpdate", nil)
    end
    popup.thumb:SetScript("OnDragStop", _StopSelectThumb)
    popup.thumb:SetScript("OnHide", _StopSelectThumb)

    for index = 1, SELECT_VISIBLE_ROWS do
        local row = CreateFrame("Button", nil, popup)
        row:SetHeight(SELECT_ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp")
        row:EnableMouseWheel(true)
        QuestieConfigNextWidgets:ApplyBackdrop(row, _Theme().insetBg, {0, 0, 0, 0}, 1)
        row.label = QuestieConfigNextWidgets:CreateFont(row, 11, _Theme().textMuted)
        row.label:SetPoint("LEFT", row, "LEFT", 7, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        row:SetScript("OnEnter", function(self)
            if self.qcOption and self.qcOption.value ~= popup.owner.qcValue then
                self:SetBackdropColor(unpack(_Theme().navHoverBg))
            end
        end)
        row:SetScript("OnLeave", _RefreshSelectPopup)
        row:SetScript("OnMouseWheel", function(_, delta) _ScrollSelectPopup(-delta) end)
        row:SetScript("OnClick", function(self)
            local owner = popup.owner
            if not (owner and self.qcOption) then
                return
            end
            if owner.qcSpec.set then
                owner.qcSpec.set(self.qcOption.value)
            end
            if owner.qcSpec.onChanged then
                owner.qcSpec.onChanged()
            end
            owner:Refresh()
            popup:Hide()
        end)
        popup.rows[index] = row
    end

    popup.noResults = QuestieConfigNextWidgets:CreateFont(popup, 11, _Theme().textSoft)
    popup.noResults:SetText("No matching choices")
    popup.noResults:SetJustifyH("CENTER")
    popup.noResults:Hide()
    popup:SetScript("OnMouseWheel", function(_, delta) _ScrollSelectPopup(-delta) end)
    popup:SetScript("OnHide", function(self)
        self.search:ClearFocus()
        self.owner = nil
    end)

    local registered
    for _, name in ipairs(UISpecialFrames) do
        if name == "QuestieConfigNextSelectPopup" then
            registered = true
            break
        end
    end
    if not registered then
        table.insert(UISpecialFrames, "QuestieConfigNextSelectPopup")
    end

    selectPopup = popup
    popup:Hide()
    return popup
end

local function _OpenSelectPopup(owner)
    local popup = _EnsureSelectPopup()
    if popup:IsShown() and popup.owner == owner then
        popup:Hide()
        return
    end

    popup:Hide()
    popup.owner = owner
    popup.searchable = owner.qcSpec.searchable and true or false
    popup.visibleRows = min(SELECT_VISIBLE_ROWS, max(1, #owner.qcOptions))
    popup.offset = 0
    popup:SetWidth(min(UIParent:GetWidth() - 24, max(owner.qcPopupWidth, owner.select:GetWidth())))
    popup:SetHeight(8 + (popup.visibleRows * SELECT_ROW_HEIGHT) + (popup.searchable and 29 or 0))
    QuestieConfigNextWidgets:ApplyBackdrop(popup, _Theme().windowBg, _Theme().borderSoft, 1)
    QuestieConfigNextWidgets:ApplyBackdrop(popup.search, _Theme().insetBg, _Theme().borderSoft, 1)
    popup.search:SetTextColor(unpack(_Theme().textMuted))
    popup.search.placeholder:SetTextColor(unpack(_Theme().textSoft))
    QuestieConfigNextWidgets:ApplyBackdrop(popup.track, _Theme().insetBg, _Theme().borderSoft, 1)
    QuestieConfigNextWidgets:ApplyBackdrop(popup.thumb, _Theme().accentSoft, _Theme().accent, 1)

    popup.search:ClearAllPoints()
    popup.search:SetPoint("TOPLEFT", popup, "TOPLEFT", 5, -5)
    popup.search:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -15, -5)
    QuestieConfigNextWidgets:SetShown(popup.search, popup.searchable)
    popup.search:SetText("")
    popup.search.clear:Hide()

    local rowTop = popup.searchable and -34 or -4
    for index, row in ipairs(popup.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, rowTop - ((index - 1) * SELECT_ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -14, rowTop - ((index - 1) * SELECT_ROW_HEIGHT))
    end
    popup.track:ClearAllPoints()
    popup.track:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -3, rowTop)
    popup.track:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -3, 4)
    popup.noResults:ClearAllPoints()
    popup.noResults:SetPoint("TOPLEFT", popup, "TOPLEFT", 8, rowTop - 5)
    popup.noResults:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -15, rowTop - 5)

    popup:ClearAllPoints()
    local roomBelow = owner.select:GetBottom() or 0
    if roomBelow >= popup:GetHeight() + 8 then
        popup:SetPoint("TOPLEFT", owner.select, "BOTTOMLEFT", 0, -4)
    else
        popup:SetPoint("BOTTOMLEFT", owner.select, "TOPLEFT", 0, 4)
    end
    _RefreshSelectPopup()
    popup:Show()
end

function QuestieConfigNextWidgets:CreateSelect(parent, spec)
    local widget = CreateFrame("Frame", nil, parent)
    widget:SetHeight(32)
    widget.qcLayoutHeight = 32
    widget.qcFullWidth = spec.fullWidth ~= false
    widget.qcMinimumWidth = spec.minWidth or 280
    widget.qcSpec = spec
    widget.qcOptions = _NormalizeSelectOptions(spec)

    local optionSearchText = ""
    local maxOptionWidth = 0
    local cachedMetadata = spec.cacheKey and selectMetadataCache[spec.cacheKey]
    if cachedMetadata then
        maxOptionWidth = cachedMetadata.width
        optionSearchText = cachedMetadata.searchText
    else
        local optionNames = {}
        for _, option in ipairs(widget.qcOptions) do
            optionNames[#optionNames + 1] = option.label
            local fontPath = spec.fontPreview and spec.fontPath and spec.fontPath(option.value) or nil
            maxOptionWidth = max(maxOptionWidth, _MeasureSelectOption(option.label, fontPath))
        end
        optionSearchText = table.concat(optionNames, " ")
        if spec.cacheKey then
            selectMetadataCache[spec.cacheKey] = {width = maxOptionWidth, searchText = optionSearchText}
        end
    end
    widget.qcSearchText = string.lower((spec.name or "") .. " " .. (spec.description or "") .. " " .. optionSearchText)
    widget.qcPopupWidth = max(220, maxOptionWidth + 34)

    widget.label = QuestieConfigNextWidgets:CreateFont(widget, 11, _Theme().textMuted)
    widget.label:SetText(spec.name or "Choice")
    widget.qcLabelWidth = widget.label:GetStringWidth() or 0

    widget.select = CreateFrame("Button", nil, widget)
    widget.select:SetHeight(26)
    widget.select:RegisterForClicks("LeftButtonUp")
    QuestieConfigNextWidgets:ApplyBackdrop(widget.select, _Theme().insetBg, _Theme().borderSoft, 1)
    widget.selected = QuestieConfigNextWidgets:CreateFont(widget.select, 11, _Theme().textMuted)
    widget.selected:SetPoint("LEFT", widget.select, "LEFT", 7, 0)
    widget.selected:SetPoint("RIGHT", widget.select, "RIGHT", -22, 0)
    widget.arrow = QuestieConfigNextWidgets:CreateFont(widget.select, 11, _Theme().textSoft, "value")
    widget.arrow:SetPoint("RIGHT", widget.select, "RIGHT", -7, 0)
    widget.arrow:SetText("v")

    function widget:Layout(width)
        self:SetWidth(width)
        self.label:ClearAllPoints()
        self.select:ClearAllPoints()
        local selectWidth = min(310, max(230, floor(width * 0.52)))
        local stacked = self.qcLabelWidth + selectWidth + 14 > width
        self.qcLayoutHeight = stacked and 55 or 32
        self:SetHeight(self.qcLayoutHeight)
        if stacked then
            self.label:SetPoint("TOPLEFT", self, "TOPLEFT", 3, -2)
            self.label:SetPoint("TOPRIGHT", self, "TOPRIGHT", -3, -2)
            self.select:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 3, 2)
            self.select:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -3, 2)
        else
            self.label:SetPoint("LEFT", self, "LEFT", 3, 0)
            self.label:SetPoint("RIGHT", self, "RIGHT", -(selectWidth + 10), 0)
            self.select:SetPoint("RIGHT", self, "RIGHT", -3, 0)
            self.select:SetWidth(selectWidth)
        end
    end

    function widget:Refresh()
        local disabled = _GetDisabled(spec)
        local value = spec.get and spec.get()
        local selectedLabel = tostring(value or "")
        self.qcDisabled = disabled
        self.qcValue = value
        for _, option in ipairs(self.qcOptions) do
            if option.value == value then
                selectedLabel = option.label
                break
            end
        end
        self.selected:SetText(selectedLabel)
        if spec.fontPreview and spec.fontPath then
            self.selected:SetFont(spec.fontPath(value), 11, "")
        else
            self.selected:SetFont(_FetchFont("Expressway"), 11, "")
        end
        self.label:SetTextColor(unpack(disabled and _Theme().textSoft or _Theme().textMuted))
        self.selected:SetTextColor(unpack(disabled and _Theme().textSoft or _Theme().textMuted))
        self.arrow:SetTextColor(unpack(disabled and _Theme().textSoft or _Theme().textSoft))
        self.select:SetBackdropColor(unpack(_Theme().insetBg))
        self.select:SetBackdropBorderColor(unpack(_Theme().borderSoft))
    end

    widget.select:SetScript("OnEnter", function(self)
        if not widget.qcDisabled then
            self:SetBackdropColor(unpack(_Theme().navHoverBg))
        end
        _ShowTooltip(widget, spec.name, spec.description)
    end)
    widget.select:SetScript("OnLeave", function()
        widget:Refresh()
        _HideTooltip()
    end)
    widget.select:SetScript("OnClick", function()
        if not widget.qcDisabled then
            _OpenSelectPopup(widget)
        end
    end)

    widget:Layout(560)
    widget:Refresh()
    return widget
end

function QuestieConfigNextWidgets:ClosePopups()
    if selectPopup then
        selectPopup:Hide()
    end
end

function QuestieConfigNextWidgets:CreateScrollArea(parent)
    local area = CreateFrame("Frame", nil, parent)
    local viewport = CreateFrame("ScrollFrame", nil, area)
    local content = CreateFrame("Frame", nil, viewport)
    local track = CreateFrame("Frame", nil, area)
    local thumb = CreateFrame("Button", nil, track)

    viewport:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
    viewport:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -13, 0)
    viewport:EnableMouseWheel(true)
    content:SetSize(1, 1)
    viewport:SetScrollChild(content)

    track:SetPoint("TOPRIGHT", area, "TOPRIGHT", -2, -2)
    track:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -2, 2)
    track:SetWidth(8)
    QuestieConfigNextWidgets:ApplyBackdrop(track, _Theme().insetBg, _Theme().borderSoft, 1)
    thumb:SetWidth(6)
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
