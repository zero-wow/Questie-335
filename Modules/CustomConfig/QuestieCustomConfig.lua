---@class QuestieCustomConfig
local QuestieCustomConfig = QuestieLoader:CreateModule("QuestieCustomConfig")
local _QuestieCustomConfig = QuestieCustomConfig.private

---@type QuestieCustomConfigData
local QuestieCustomConfigData = QuestieLoader:ImportModule("QuestieCustomConfigData")
---@type QuestieCustomConfigSkin
local QuestieCustomConfigSkin = QuestieLoader:ImportModule("QuestieCustomConfigSkin")
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")
---@type QuestieOptions
local QuestieOptions = QuestieLoader:ImportModule("QuestieOptions")
---@type QuestieOptionsUtils
local QuestieOptionsUtils = QuestieLoader:ImportModule("QuestieOptionsUtils")
---@type TrackerLinePool
local TrackerLinePool = QuestieLoader:ImportModule("TrackerLinePool")

local C_Timer = QuestieCompat.C_Timer

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local LibSharedMedia = LibStub("LibSharedMedia-3.0", true)

local lower = string.lower
local find = string.find
local tinsert = table.insert
local mathMax = math.max
local mathMin = math.min
local unpack = unpack or table.unpack

local UI_NAME = "QuestieCustomConfig-1.0"
local FRAME_NAME = "QuestieCustomConfigFrame"
local DEFAULT_TAB = "general_tab"
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 840, 680
local MIN_HEIGHT, MAX_HEIGHT = 360, 1100
local COMPACT_LAYOUT_VERSION = 2
local NATIVE_SCROLL_STEP = 36
local RESIZE_REPORT_DELAY = 2
local HALF_SPAN_FONT_SELECT_PATHS = {
    ["tracker_tab.group_fonts.fontGlobal"] = true,
}

local palette = QuestieCustomConfigData.palette
local _GetTabInfo
local _EnsureAppRegistered
local _RefreshChromeTheme
local _RenderCurrentTab
local _NativeTabRenderers = {}

local function _FormatOpenDuration(duration)
    duration = tonumber(duration) or 0
    return string.format("%.3f", duration)
end

local function _ReportOpenTiming(requestStartTime, openStartTime, targetTab, wasRebuilt, wasColdStart)
    if not requestStartTime then
        return
    end

    local now = GetTime()
    local totalElapsed = now - requestStartTime
    local openElapsed = openStartTime and (now - openStartTime) or totalElapsed
    local mode = wasRebuilt and "rebuilt" or "cached"
    local startup = wasColdStart and "cold" or "warm"
    local tabInfo = _GetTabInfo(targetTab)
    local label = (tabInfo and tabInfo.title) or tostring(targetTab or "unknown")

    Questie:Print(string.format("[/qc] total %ss, ui %ss (%s, %s, %s page)", _FormatOpenDuration(totalElapsed), _FormatOpenDuration(openElapsed), startup, label, mode))
end

local function _GetState()
    Questie.db.char.questieCustomConfig = Questie.db.char.questieCustomConfig or {}
    local state = Questie.db.char.questieCustomConfig

    state.window = state.window or {
        width = DEFAULT_WIDTH,
        height = DEFAULT_HEIGHT,
    }
    if (tonumber(state.layoutVersion) or 0) < COMPACT_LAYOUT_VERSION then
        state.window.width = mathMin(tonumber(state.window.width) or DEFAULT_WIDTH, DEFAULT_WIDTH)
        state.window.height = mathMin(tonumber(state.window.height) or DEFAULT_HEIGHT, DEFAULT_HEIGHT)
        state.layoutVersion = COMPACT_LAYOUT_VERSION
    end
    state.lastTab = state.lastTab or DEFAULT_TAB
    state.colorway = state.colorway or QuestieCustomConfigData.defaultColorway

    return state
end

local function _ClampWindowBounds(width, height, left, top)
    local screenWidth = UIParent:GetWidth() or GetScreenWidth()
    local screenHeight = UIParent:GetHeight() or GetScreenHeight()

    width = tonumber(width) or DEFAULT_WIDTH
    height = mathMin(mathMax(height or DEFAULT_HEIGHT, MIN_HEIGHT), MAX_HEIGHT)

    if left and top then
        left = mathMin(mathMax(left, 0), mathMax(0, screenWidth - width))
        top = mathMin(mathMax(top, height), screenHeight)
    end

    return width, height, left, top
end

local function _SaveWindowState()
    if not _QuestieCustomConfig.frame then
        return
    end

    local state = _GetState()
    local frame = _QuestieCustomConfig.frame
    local width, height, left, top = _ClampWindowBounds(frame:GetWidth(), frame:GetHeight(), frame:GetLeft(), frame:GetTop())

    state.window.width = width
    state.window.height = height
    state.window.left = left
    state.window.top = top
end

local function _ApplyWindowState()
    local state = _GetState()
    local frame = _QuestieCustomConfig.frame
    local width, height, left, top = _ClampWindowBounds(state.window.width, state.window.height, state.window.left, state.window.top)

    -- Width is intentionally unrestricted so experimental layouts can be measured.
    state.window.width = width
    state.window.height = height
    state.window.left = left
    state.window.top = top

    frame:SetWidth(width)
    frame:SetHeight(height)
    frame:ClearAllPoints()

    if left and top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end
end

local function _CancelResizeReport()
    local timer = _QuestieCustomConfig.resizeReportTimer
    if timer and timer.Cancel then
        timer:Cancel()
    end
    _QuestieCustomConfig.resizeReportTimer = nil
end

local function _ReportResizeDimensions()
    local frame = _QuestieCustomConfig.frame
    if not frame or not frame:IsShown() then
        return
    end

    local contentInset = _QuestieCustomConfig.contentInset
    local nativeScroll = _QuestieCustomConfig.nativeScroll
    local nativePage = _QuestieCustomConfig.nativePage
    local tabInfo = _GetTabInfo(_QuestieCustomConfig.currentTab)
    local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    local windowWidth, windowHeight = frame:GetWidth() or 0, frame:GetHeight() or 0
    local contentWidth, contentHeight = 0, 0
    local viewportWidth, viewportHeight = 0, 0

    if contentInset then
        contentWidth, contentHeight = contentInset:GetWidth() or 0, contentInset:GetHeight() or 0
    end
    if nativeScroll then
        viewportWidth, viewportHeight = nativeScroll:GetWidth() or 0, nativeScroll:GetHeight() or 0
    end

    Questie:Print(string.format(
        "[/qc resize] window %.0fx%.0f UI (%.0fx%.0f px), scale %.3f, tab %s",
        windowWidth,
        windowHeight,
        windowWidth * scale,
        windowHeight * scale,
        scale,
        (tabInfo and tabInfo.title) or tostring(_QuestieCustomConfig.currentTab or "unknown")
    ))
    Questie:Print(string.format(
        "[/qc resize] content %.0fx%.0f, viewport %.0fx%.0f, page height %.0f, scroll range %.0f",
        contentWidth,
        contentHeight,
        viewportWidth,
        viewportHeight,
        (nativePage and nativePage.nativeContentHeight) or 0,
        (nativeScroll and nativeScroll:GetVerticalScrollRange()) or 0
    ))
end

local function _ScheduleResizeReport()
    _CancelResizeReport()
    _QuestieCustomConfig.resizeReportTimer = C_Timer.After(RESIZE_REPORT_DELAY, function()
        _QuestieCustomConfig.resizeReportTimer = nil
        _SaveWindowState()
        _ReportResizeDimensions()
    end)
end

local function _SetFont(fontString, template, color)
    fontString:SetFontObject(template)
    if color then
        QuestieCustomConfigSkin:ColorFont(fontString, color)
    end
end

local function _CopyPalette(paletteSpec)
    if not paletteSpec then
        return
    end

    for key, color in pairs(paletteSpec) do
        palette[key] = {color[1], color[2], color[3], color[4]}
    end
end

local function _GetActiveColorwayKey()
    local state = _GetState()
    local colorwayKey = state.colorway or QuestieCustomConfigData.defaultColorway

    if not QuestieCustomConfigData.colorways[colorwayKey] then
        colorwayKey = QuestieCustomConfigData.defaultColorway
        state.colorway = colorwayKey
    end

    return colorwayKey
end

local function _ApplyTrackerRowPalette(preset)
    local profile = Questie.db and Questie.db.profile
    local presetPalette = preset and preset.palette
    if not profile or not presetPalette then
        return
    end

    local odd = presetPalette.trackerRowOdd
    local even = presetPalette.trackerRowEven
    if type(odd) == "table" then
        profile.trackerAlternatingRowColorOdd = {odd[1], odd[2], odd[3], odd[4]}
    end
    if type(even) == "table" then
        profile.trackerAlternatingRowColorEven = {even[1], even[2], even[3], even[4]}
    end

    profile.trackerAlternatingRowPaletteVersion = 1
    TrackerLinePool.UpdateAlternatingRowBackgrounds()
end

local function _ApplyColorway(colorwayKey, applyTrackerRows)
    local resolvedKey = colorwayKey or _GetActiveColorwayKey()
    local preset = QuestieCustomConfigData.colorways[resolvedKey]
        or QuestieCustomConfigData.colorways[QuestieCustomConfigData.defaultColorway]

    if not QuestieCustomConfigData.colorways[resolvedKey] then
        resolvedKey = QuestieCustomConfigData.defaultColorway
    end

    _GetState().colorway = resolvedKey
    _CopyPalette(preset.palette)

    local profile = Questie.db and Questie.db.profile
    local needsTrackerRowMigration = profile and (tonumber(profile.trackerAlternatingRowPaletteVersion) or 0) < 1
    if applyTrackerRows == true or needsTrackerRowMigration then
        _ApplyTrackerRowPalette(preset)
    end

    if _QuestieCustomConfig.frame then
        _RefreshChromeTheme()
    end
end

_GetTabInfo = function(tabKey)
    for _, tab in ipairs(QuestieCustomConfigData.tabs) do
        if tab.key == tabKey then
            return tab
        end
    end
end

local function _ResolveTabKey(token)
    if not token or token == "" then
        return nil
    end

    token = lower(token)

    if QuestieCustomConfigData.aliases[token] then
        return QuestieCustomConfigData.aliases[token]
    end

    for _, tab in ipairs(QuestieCustomConfigData.tabs) do
        if token == lower(tab.key) or find(lower(tab.alias), token, 1, true) or find(lower(tab.title), token, 1, true) then
            return tab.key
        end
    end

    return nil
end

local function _ApplyNavButtonState(button, isActive)
    local accent = button.accent
    local title = button.title
    local subtitle = button.subtitle

    if isActive then
        button:SetBackdropColor(unpack(palette.navActiveBg))
        button:SetBackdropBorderColor(unpack(palette.accent))
        accent:SetVertexColor(unpack(palette.accent))
        accent:Show()
        title:SetTextColor(unpack(palette.navActiveText))
        if subtitle then
            subtitle:SetTextColor(unpack(palette.textMuted))
        end
    else
        button:SetBackdropColor(unpack(palette.navIdleBg))
        button:SetBackdropBorderColor(unpack(palette.borderSoft))
        accent:Hide()
        title:SetTextColor(unpack(palette.navIdleText))
        if subtitle then
            subtitle:SetTextColor(unpack(palette.textSoft))
        end
    end
end

local function _RefreshMetaText()
    if not _QuestieCustomConfig.metaText then
        return
    end

    local currentProfile = Questie.db.GetCurrentProfile and Questie.db:GetCurrentProfile() or "Default"
    _QuestieCustomConfig.metaText:SetText(string.format("v%s  |  %s", tostring(QuestieLib:GetAddonVersionString()), tostring(currentProfile)))
end

local function _RefreshSearchPlaceholder()
    if not _QuestieCustomConfig.searchBox then
        return
    end

    local searchText = _QuestieCustomConfig.searchBox:GetText() or ""
    if searchText == "" and not _QuestieCustomConfig.searchBoxFocused then
        _QuestieCustomConfig.searchPlaceholder:Show()
    else
        _QuestieCustomConfig.searchPlaceholder:Hide()
    end

    if searchText == "" then
        _QuestieCustomConfig.searchClear:Hide()
    else
        _QuestieCustomConfig.searchClear:Show()
    end
end

local function _ShowCategoryTooltip(self)
    if not self.tabData or not self.tabData.subtitle or self.tabData.subtitle == "" then
        return
    end

    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText(self.tabData.title, 1.0, 0.93, 0.55)
    GameTooltip:AddLine(self.tabData.subtitle, palette.textMuted[1], palette.textMuted[2], palette.textMuted[3], true)
    GameTooltip:Show()
end

local function _HideCategoryTooltip()
    GameTooltip:Hide()
end

local function _SetNativeScrollOffset(offset, updateSlider)
    local scrollFrame = _QuestieCustomConfig.nativeScroll
    local scrollBar = _QuestieCustomConfig.nativeScrollBar
    local page = _QuestieCustomConfig.nativePage
    if not scrollFrame or not page then
        return
    end

    local maxScroll = mathMax(0, (page:GetHeight() or 0) - (scrollFrame:GetHeight() or 0))
    offset = mathMin(mathMax(tonumber(offset) or 0, 0), maxScroll)
    scrollFrame:SetVerticalScroll(offset)

    if updateSlider ~= false and scrollBar then
        scrollBar.syncingValue = true
        scrollBar:SetValue(offset)
        scrollBar.syncingValue = nil
    end
end

local function _UpdateNativeScrollLayout(offset)
    local scrollFrame = _QuestieCustomConfig.nativeScroll
    local scrollBar = _QuestieCustomConfig.nativeScrollBar
    local page = _QuestieCustomConfig.nativePage
    if not scrollFrame or not scrollBar or not page then
        return
    end

    local viewportWidth = scrollFrame:GetWidth() or 0
    local viewportHeight = scrollFrame:GetHeight() or 0
    if viewportWidth < 1 or viewportHeight < 1 then
        return
    end

    page:SetWidth(viewportWidth)
    if page.Reflow then
        page:Reflow()
    end
    page:SetHeight(mathMax(page.nativeContentHeight or 1, viewportHeight))

    local maxScroll = mathMax(0, page:GetHeight() - viewportHeight)
    local targetOffset = mathMin(mathMax(tonumber(offset) or (scrollFrame:GetVerticalScroll() or 0), 0), maxScroll)

    scrollBar.syncingValue = true
    scrollBar:SetMinMaxValues(0, mathMax(maxScroll, 0.001))
    scrollBar:SetValue(targetOffset)
    scrollBar.syncingValue = nil

    if maxScroll > 0.5 then
        scrollBar:Show()
    else
        scrollBar:Hide()
    end

    scrollFrame:SetVerticalScroll(targetOffset)
end

local function _ReleaseNativePage()
    if _QuestieCustomConfig.nativePage then
        _QuestieCustomConfig.nativePage.scrollOffset = _QuestieCustomConfig.nativeScroll
            and (_QuestieCustomConfig.nativeScroll:GetVerticalScroll() or 0)
            or 0
        if _QuestieCustomConfig.nativeScroll then
            _QuestieCustomConfig.nativeScroll:SetVerticalScroll(0)
            _QuestieCustomConfig.nativeScroll:SetScrollChild(nil)
        end
        _QuestieCustomConfig.nativePage:Hide()
        _QuestieCustomConfig.nativePage = nil
    end

    if _QuestieCustomConfig.nativeScrollBar then
        _QuestieCustomConfig.nativeScrollBar.syncingValue = true
        _QuestieCustomConfig.nativeScrollBar:SetMinMaxValues(0, 0.001)
        _QuestieCustomConfig.nativeScrollBar:SetValue(0)
        _QuestieCustomConfig.nativeScrollBar.syncingValue = nil
        _QuestieCustomConfig.nativeScrollBar:Hide()
    end
end

local function _ActivateNativePage(page)
    if not page or not _QuestieCustomConfig.nativeScroll then
        return
    end

    if _QuestieCustomConfig.nativePage ~= page then
        _ReleaseNativePage()
    end

    page:SetParent(_QuestieCustomConfig.nativeScroll)
    page:Show()
    _QuestieCustomConfig.nativeScroll:SetScrollChild(page)
    _QuestieCustomConfig.nativePage = page
    _UpdateNativeScrollLayout(page.scrollOffset or 0)
end

local function _CreateColorSwatches(parent, colors, anchorFrame)
    if not colors then
        return {}
    end

    local swatches = {}
    local previous
    for index = #colors, 1, -1 do
        local swatch = QuestieCustomConfigSkin:CreateSolid(parent, "ARTWORK", colors[index])
        swatch:SetSize(10, 10)
        if previous then
            swatch:SetPoint("RIGHT", previous, "LEFT", -4, 0)
        elseif anchorFrame then
            swatch:SetPoint("RIGHT", anchorFrame, "LEFT", -9, 0)
        else
            swatch:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
        end
        swatches[#swatches + 1] = swatch
        previous = swatch
    end
    return swatches
end

local function _CreateNativeSection(parent, anchorFrame, titleText, descriptionText, height)
    local section = CreateFrame("Frame", nil, parent)
    section:SetPoint("LEFT", parent, "LEFT", 6, 0)
    section:SetPoint("RIGHT", parent, "RIGHT", -6, 0)

    if anchorFrame then
        section:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -7)
    else
        section:SetPoint("TOP", parent, "TOP", 0, -6)
    end

    section:SetHeight(height)
    QuestieCustomConfigSkin:ApplySquareBackdrop(section, palette.panelBg, palette.borderSoft, 1)

    local accent = QuestieCustomConfigSkin:CreateSolid(section, "ARTWORK", palette.accentSoft)
    accent:SetPoint("TOPLEFT", section, "TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", section, "TOPRIGHT", -1, -1)
    accent:SetHeight(1)

    local title = section:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", section, "TOPLEFT", 8, -7)
    title:SetPoint("TOPRIGHT", section, "TOPRIGHT", -8, -7)
    title:SetJustifyH("LEFT")
    title:SetText(titleText)
    title:SetTextColor(unpack(palette.textBright))

    local description = section:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    description:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -2)
    description:SetJustifyH("LEFT")
    description:SetJustifyV("TOP")
    description:SetText(descriptionText or "")
    description:SetTextColor(unpack(palette.textMuted))

    section.title = title
    section.description = description
    section.accent = accent

    return section
end

local function _GetRenderedTextHeight(fontString, fallback)
    if not fontString then
        return fallback or 1
    end

    return mathMax(tonumber(fontString:GetStringHeight()) or 0, fallback or 1)
end

local INHERITED_OPTION_MEMBERS = {
    set = true,
    get = true,
    func = true,
    confirm = true,
    validate = true,
    disabled = true,
    hidden = true,
}

local LITERAL_STRING_MEMBERS = {
    name = true,
    desc = true,
    icon = true,
    usage = true,
    width = true,
    image = true,
    fontSize = true,
    confirmText = true,
}

local function _TrimText(value)
    value = tostring(value or "")
    return (string.gsub(value, "^%s*(.-)%s*$", "%1"))
end

local function _PlainText(value)
    value = tostring(value or "")
    value = string.gsub(value, "|T.-|t", "")
    value = string.gsub(value, "|c%x%x%x%x%x%x%x%x", "")
    value = string.gsub(value, "|r", "")
    return value
end

local function _GetSubOption(group, key)
    if not group then
        return nil
    end

    if group.args and group.args[key] then
        return group.args[key]
    end

    if group.plugins then
        for _, pluginOptions in pairs(group.plugins) do
            if pluginOptions[key] then
                return pluginOptions[key]
            end
        end
    end
end

local function _GetOptionsRoot()
    if _QuestieCustomConfig.optionsRoot then
        return _QuestieCustomConfig.optionsRoot
    end

    local root = AceConfigRegistry:GetOptionsTable("Questie", "dialog", UI_NAME)
    if type(root) == "table" then
        _QuestieCustomConfig.optionsRoot = root
        return root
    end
end

local function _CopyPath(path, key)
    local result = {}
    for index = 1, #path do
        result[index] = path[index]
    end
    if key ~= nil then
        result[#result + 1] = key
    end
    return result
end

local function _ResolveOptionContext(path)
    local root = _GetOptionsRoot()
    if not root then
        return nil
    end

    local option = root
    local handler = root.handler
    for index = 1, #path do
        option = _GetSubOption(option, path[index])
        if not option then
            return root
        end
        handler = option.handler or handler
    end

    return root, option, handler
end

local function _BuildOptionInfo(root, option, handler, path)
    local info = {}
    for index = 1, #path do
        info[index] = path[index]
    end
    info[0] = "Questie"
    info.options = root
    info.appName = "Questie"
    info.arg = option and option.arg
    info.handler = handler
    info.option = option
    info.type = option and option.type
    info.uiType = "dialog"
    info.uiName = UI_NAME
    return info
end

local function _GetRawOptionMember(memberName, path)
    local root, option, handler = _ResolveOptionContext(path)
    if not root or not option then
        return nil
    end

    local member
    if INHERITED_OPTION_MEMBERS[memberName] then
        local group = root
        handler = root.handler
        if group[memberName] ~= nil then
            member = group[memberName]
        end
        for index = 1, #path do
            group = _GetSubOption(group, path[index])
            if not group then
                break
            end
            handler = group.handler or handler
            if group[memberName] ~= nil then
                member = group[memberName]
            end
        end
    else
        member = option[memberName]
    end

    return member, root, option, handler
end

local function _ReportOptionError(path, memberName, errorMessage)
    local key = table.concat(path, ".") .. ":" .. tostring(memberName)
    _QuestieCustomConfig.optionErrors = _QuestieCustomConfig.optionErrors or {}
    if _QuestieCustomConfig.optionErrors[key] then
        return
    end
    _QuestieCustomConfig.optionErrors[key] = true
    Questie:Error(string.format("/qc option error (%s): %s", key, tostring(errorMessage)))
end

local function _GetOptionMember(memberName, path, ...)
    local member, root, option, handler = _GetRawOptionMember(memberName, path)
    if member == nil then
        return nil
    end

    local shouldCall = type(member) == "function"
        or (type(member) == "string" and not LITERAL_STRING_MEMBERS[memberName])
    if not shouldCall then
        return member
    end

    local info = _BuildOptionInfo(root, option, handler, path)
    local ok, a, b, c, d
    if type(member) == "function" then
        ok, a, b, c, d = pcall(member, info, ...)
    elseif handler and type(handler[member]) == "function" then
        ok, a, b, c, d = pcall(handler[member], handler, info, ...)
    else
        _ReportOptionError(path, memberName, "missing handler method " .. tostring(member))
        return nil
    end

    if not ok then
        _ReportOptionError(path, memberName, a)
        return nil
    end

    return a, b, c, d
end

local function _GetOptionName(path)
    return _TrimText(_GetOptionMember("name", path))
end

local function _GetOptionDescription(path)
    return _TrimText(_GetOptionMember("desc", path))
end

local function _IsOptionHidden(path)
    return _GetOptionMember("hidden", path) and true or false
end

local function _IsOptionDisabled(path)
    return _GetOptionMember("disabled", path) and true or false
end

local function _SortOptionKeys(group, path)
    local entries = {}
    local seen = {}

    local function _AddOptions(options)
        for key, option in pairs(options or {}) do
            if not seen[key] then
                local optionPath = _CopyPath(path, key)
                entries[#entries + 1] = {
                    key = key,
                    option = option,
                    order = tonumber(_GetOptionMember("order", optionPath)) or 100,
                    name = _PlainText(_GetOptionName(optionPath)),
                }
                seen[key] = true
            end
        end
    end

    _AddOptions(group.args)
    for _, pluginOptions in pairs(group.plugins or {}) do
        _AddOptions(pluginOptions)
    end

    table.sort(entries, function(left, right)
        if left.order == right.order then
            return string.lower(left.name) < string.lower(right.name)
        end
        if left.order < 0 and right.order >= 0 then
            return false
        end
        if right.order < 0 and left.order >= 0 then
            return true
        end
        return left.order < right.order
    end)

    return entries
end

local function _ShowOptionTooltip(control)
    local descriptor = control and control.optionDescriptor
    if not descriptor then
        return
    end

    local name = _GetOptionName(descriptor.path)
    local description = _GetOptionDescription(descriptor.path)
    if name == "" and description == "" then
        return
    end

    GameTooltip:SetOwner(control, "ANCHOR_CURSOR")
    if name ~= "" then
        GameTooltip:SetText(name, palette.textBright[1], palette.textBright[2], palette.textBright[3])
    end
    if description ~= "" then
        GameTooltip:AddLine(description, palette.textMuted[1], palette.textMuted[2], palette.textMuted[3], true)
    end
    GameTooltip:Show()
end

local function _HideOptionTooltip()
    GameTooltip:Hide()
end

local function _ScheduleNativeRefresh()
    if _QuestieCustomConfig.nativeRefreshScheduled then
        return
    end

    _QuestieCustomConfig.nativeRefreshScheduled = true
    C_Timer.After(0, function()
        _QuestieCustomConfig.nativeRefreshScheduled = nil
        _RefreshMetaText()
        local page = _QuestieCustomConfig.nativePage
        if page and page.Refresh then
            page:Refresh()
            _UpdateNativeScrollLayout()
        end
    end)
end

local CONFIRM_DIALOG_KEY = "QUESTIE_CUSTOM_CONFIG_CONFIRM"

local function _EnsureConfirmDialog()
    if StaticPopupDialogs[CONFIRM_DIALOG_KEY] then
        return
    end

    StaticPopupDialogs[CONFIRM_DIALOG_KEY] = {
        text = "%s",
        button1 = YES,
        button2 = NO,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function(_, data)
            if data and data.callback then
                data.callback()
            end
        end,
    }
end

local function _RunOptionAction(descriptor, memberName, value, valueKey)
    local function _Execute()
        if memberName == "set" then
            if valueKey ~= nil then
                _GetOptionMember("set", descriptor.path, valueKey, value)
            else
                _GetOptionMember("set", descriptor.path, value)
            end
        else
            _GetOptionMember(memberName, descriptor.path, value)
        end
        _ScheduleNativeRefresh()
    end

    local confirm
    if valueKey ~= nil then
        confirm = _GetOptionMember("confirm", descriptor.path, valueKey, value)
    else
        confirm = _GetOptionMember("confirm", descriptor.path, value)
    end
    local confirmText
    if type(confirm) == "string" then
        confirmText = confirm
        confirm = true
    end
    if not confirm then
        _Execute()
        return
    end

    _EnsureConfirmDialog()
    if not confirmText then
        if valueKey ~= nil then
            confirmText = _GetOptionMember("confirmText", descriptor.path, valueKey, value)
        else
            confirmText = _GetOptionMember("confirmText", descriptor.path, value)
        end
    end
    if not confirmText or confirmText == "" then
        local name = _GetOptionName(descriptor.path)
        local description = _GetOptionDescription(descriptor.path)
        confirmText = description ~= "" and (name .. " - " .. description) or name
    end
    confirmText = confirmText ~= "" and confirmText or "Are you sure?"
    StaticPopup_Show(CONFIRM_DIALOG_KEY, tostring(confirmText), nil, {callback = _Execute})
end

local function _ValidateOptionInput(descriptor, value)
    local validation = _GetOptionMember("validate", descriptor.path, value)
    if validation == nil or validation == true then
        return true
    end

    local message = type(validation) == "string" and validation or "That value is not valid."
    Questie:Print(message)
    return false
end

local _SetVisible
local SELECT_POPUP_ROWS = 11
local SELECT_POPUP_ROW_HEIGHT = 20

local function _GetSelectEntries(descriptor)
    if descriptor.cachedSelectEntries and not descriptor.dynamicValues then
        return descriptor.cachedSelectEntries
    end

    local values = _GetOptionMember("values", descriptor.path)
    if type(values) ~= "table" then
        return {}
    end

    local sorting = _GetOptionMember("sorting", descriptor.path)
    local keys = {}
    local seen = {}
    if type(sorting) == "table" then
        for _, key in ipairs(sorting) do
            if values[key] ~= nil and not seen[key] then
                keys[#keys + 1] = key
                seen[key] = true
            end
        end
    end
    for key in pairs(values) do
        if not seen[key] then
            keys[#keys + 1] = key
        end
    end

    if type(sorting) ~= "table" then
        table.sort(keys, function(left, right)
            return string.lower(_PlainText(values[left])) < string.lower(_PlainText(values[right]))
        end)
    end

    local entries = {}
    for _, key in ipairs(keys) do
        local display = values[key]
        if type(display) == "function" then
            local ok, result = pcall(display)
            display = ok and result or key
        end
        entries[#entries + 1] = {
            key = key,
            text = tostring(display or key),
            searchText = string.lower(_PlainText(display or key)),
        }
    end

    if descriptor.isFontSelect then
        for index = 1, #entries do
            if entries[index].key == "NONE" and index ~= 1 then
                local noneEntry = table.remove(entries, index)
                table.insert(entries, 1, noneEntry)
                break
            end
        end
    end

    if not descriptor.dynamicValues then
        descriptor.cachedSelectEntries = entries
    end
    return entries
end

local function _SetSelectRowFont(fontString, descriptor, entryKey)
    fontString:SetFontObject(GameFontNormal)
    if not descriptor.isFontSelect or not LibSharedMedia then
        return
    end

    local fontPath = type(entryKey) == "string" and LibSharedMedia:Fetch("font", entryKey, true)
    if fontPath then
        pcall(fontString.SetFont, fontString, fontPath, 12, "")
    end
end

local function _EnsureNativeSelectPopup()
    if _QuestieCustomConfig.selectPopup then
        return _QuestieCustomConfig.selectPopup
    end

    local popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetFrameLevel(500)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:EnableMouseWheel(true)
    QuestieCustomConfigSkin:ApplySquareBackdrop(popup, palette.windowBg, palette.accent, 1)
    popup:Hide()

    local searchFrame = CreateFrame("Frame", nil, popup)
    searchFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 5, -5)
    searchFrame:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -19, -5)
    searchFrame:SetHeight(20)
    QuestieCustomConfigSkin:ApplySquareBackdrop(searchFrame, palette.insetBg, palette.borderSoft, 1)

    local search = CreateFrame("EditBox", nil, searchFrame)
    search:SetAutoFocus(false)
    search:SetFontObject(ChatFontNormal)
    search:SetTextColor(unpack(palette.navIdleText))
    search:SetPoint("TOPLEFT", searchFrame, "TOPLEFT", 5, -2)
    search:SetPoint("BOTTOMRIGHT", searchFrame, "BOTTOMRIGHT", -17, 2)

    local placeholder = searchFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", search, "LEFT", 1, 0)
    placeholder:SetText("SEARCH")
    placeholder:SetTextColor(unpack(palette.textSoft))

    local clear = CreateFrame("Button", nil, searchFrame)
    clear:SetPoint("RIGHT", searchFrame, "RIGHT", -3, 0)
    clear:SetSize(12, 12)
    clear:SetNormalFontObject(GameFontDisableSmall)
    clear:SetHighlightFontObject(GameFontHighlightSmall)
    clear:SetText("x")
    clear:SetScript("OnClick", function()
        search:SetText("")
        search:SetFocus()
    end)

    local scrollBar = CreateFrame("Slider", nil, popup)
    scrollBar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -29)
    scrollBar:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -4, 4)
    scrollBar:SetWidth(10)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetValueStep(1)
    scrollBar:SetMinMaxValues(0, 0.001)
    scrollBar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    QuestieCustomConfigSkin:ApplySquareBackdrop(scrollBar, palette.insetBg, palette.borderSoft, 1)
    local thumb = scrollBar:GetThumbTexture()
    thumb:SetSize(6, 24)
    thumb:SetVertexColor(unpack(palette.accent))

    local rows = {}
    for index = 1, SELECT_POPUP_ROWS do
        local row = CreateFrame("Button", nil, popup)
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", 6, -30 - ((index - 1) * SELECT_POPUP_ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -19, -30 - ((index - 1) * SELECT_POPUP_ROW_HEIGHT))
        row:SetHeight(SELECT_POPUP_ROW_HEIGHT)

        local hover = QuestieCustomConfigSkin:CreateSolid(row, "BACKGROUND", palette.navHoverBg)
        hover:SetAllPoints(row)
        hover:Hide()

        local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("LEFT", row, "LEFT", 6, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        label:SetHeight(SELECT_POPUP_ROW_HEIGHT - 2)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)

        row.hover = hover
        row.label = label
        row:SetScript("OnEnter", function(self)
            self.hover:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self.hover:Hide()
        end)
        row:SetScript("OnClick", function(self)
            if not self.entry or not popup.descriptor then
                return
            end
            _RunOptionAction(popup.descriptor, "set", self.entry.key)
            popup:Hide()
        end)
        rows[index] = row
    end

    local measure = popup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    measure:Hide()

    function popup:RefreshRows()
        local query = string.lower(_TrimText(search:GetText()))
        self.filteredEntries = {}
        for _, entry in ipairs(self.entries or {}) do
            if query == "" or string.find(entry.searchText, query, 1, true) then
                self.filteredEntries[#self.filteredEntries + 1] = entry
            end
        end

        local maxOffset = mathMax(0, #self.filteredEntries - SELECT_POPUP_ROWS)
        self.offset = mathMin(mathMax(tonumber(self.offset) or 0, 0), maxOffset)
        scrollBar.syncing = true
        scrollBar:SetMinMaxValues(0, mathMax(maxOffset, 0.001))
        scrollBar:SetValue(self.offset)
        scrollBar.syncing = nil
        if maxOffset > 0 then
            scrollBar:Show()
        else
            scrollBar:Hide()
        end

        for index, row in ipairs(rows) do
            local entry = self.filteredEntries[self.offset + index]
            row.entry = entry
            if entry then
                _SetSelectRowFont(row.label, self.descriptor, entry.key)
                row.label:SetText(entry.text)
                if entry.key == self.selectedValue then
                    row.label:SetTextColor(unpack(palette.textBright))
                    row.hover:Show()
                else
                    row.label:SetTextColor(unpack(palette.navIdleText))
                    row.hover:Hide()
                end
                row:Show()
            else
                row:Hide()
            end
        end

        _SetVisible(placeholder, query == "")
        _SetVisible(clear, query ~= "")
    end

    local function _ScrollPopup(delta)
        local maxOffset = mathMax(0, #(popup.filteredEntries or {}) - SELECT_POPUP_ROWS)
        popup.offset = mathMin(mathMax((popup.offset or 0) - delta, 0), maxOffset)
        popup:RefreshRows()
    end

    popup:SetScript("OnMouseWheel", function(_, delta)
        _ScrollPopup(tonumber(delta) or 0)
    end)
    scrollBar:SetScript("OnMouseWheel", function(_, delta)
        _ScrollPopup(tonumber(delta) or 0)
    end)
    scrollBar:SetScript("OnValueChanged", function(self, value)
        if self.syncing then
            return
        end
        popup.offset = math.floor((tonumber(value) or 0) + 0.5)
        popup:RefreshRows()
    end)
    search:SetScript("OnTextChanged", function()
        popup.offset = 0
        popup:RefreshRows()
    end)
    search:SetScript("OnEscapePressed", function()
        popup:Hide()
    end)
    popup:SetScript("OnHide", function()
        search:ClearFocus()
    end)

    popup.searchFrame = searchFrame
    popup.search = search
    popup.placeholder = placeholder
    popup.clear = clear
    popup.scrollBar = scrollBar
    popup.thumb = thumb
    popup.rows = rows
    popup.measure = measure
    _QuestieCustomConfig.selectPopup = popup
    return popup
end

local function _OpenNativeSelectPopup(control)
    local descriptor = control.optionDescriptor
    local popup = _EnsureNativeSelectPopup()
    popup.descriptor = descriptor
    popup.entries = _GetSelectEntries(descriptor)
    popup.selectedValue = _GetOptionMember("get", descriptor.path)
    popup.offset = 0
    popup.search:SetText("")

    local maxTextWidth = 0
    for _, entry in ipairs(popup.entries) do
        _SetSelectRowFont(popup.measure, descriptor, entry.key)
        popup.measure:SetText(entry.text)
        maxTextWidth = mathMax(maxTextWidth, tonumber(popup.measure:GetStringWidth()) or 0)
    end

    local screenWidth = UIParent:GetWidth() or GetScreenWidth()
    local popupWidth = mathMin(mathMax(240, maxTextWidth + 52), mathMax(240, screenWidth - 24))
    local visibleRows = mathMin(mathMax(#popup.entries, 1), SELECT_POPUP_ROWS)
    popup:SetSize(popupWidth, 35 + (visibleRows * SELECT_POPUP_ROW_HEIGHT))
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 0, -3)
    popup:RefreshRows()
    popup:Show()
    popup.search:SetFocus()
end

_SetVisible = function(region, visible)
    if visible then
        region:Show()
    else
        region:Hide()
    end
end

local function _CreateInteractiveRow(page, descriptor, height)
    local row = CreateFrame("Button", nil, page)
    row:SetHeight(height)
    row.optionDescriptor = descriptor
    row.layoutHeight = height
    row.fullSpan = descriptor.fullSpan

    local hover = QuestieCustomConfigSkin:CreateSolid(row, "BACKGROUND", palette.navHoverBg)
    hover:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    hover:Hide()

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", row, "LEFT", 7, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -7, 0)
    label:SetJustifyH("LEFT")

    row.hover = hover
    row.label = label
    row:SetScript("OnEnter", function(self)
        if not self.optionDisabled then
            self.hover:Show()
        end
        _ShowOptionTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        _HideOptionTooltip()
    end)

    function row:RefreshCommon()
        local name = _GetOptionName(descriptor.path)
        local description = _GetOptionDescription(descriptor.path)
        self.label:SetText(name)
        self.optionHidden = _IsOptionHidden(descriptor.path) or name == ""
        self.optionDisabled = _IsOptionDisabled(descriptor.path)
        self.searchText = string.lower(_PlainText(
            (descriptor.ancestorSearch or "") .. " " .. name .. " " .. description
        ))
        self:SetAlpha(self.optionDisabled and 0.45 or 1)
        self.label:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.navIdleText))
    end

    function row:ApplyTheme()
        hover:SetVertexColor(unpack(palette.navHoverBg))
        self.label:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.navIdleText))
    end

    return row
end

local function _CreateToggleRow(page, descriptor)
    local row = _CreateInteractiveRow(page, descriptor, 27)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -29, 0)

    local box = CreateFrame("Frame", nil, row)
    box:SetPoint("RIGHT", row, "RIGHT", -7, 0)
    box:SetSize(15, 15)
    QuestieCustomConfigSkin:ApplySquareBackdrop(box, palette.insetBg, palette.borderSoft, 1)

    local check = QuestieCustomConfigSkin:CreateSolid(box, "ARTWORK", palette.accent)
    check:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
    check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)

    row:SetScript("OnClick", function(self)
        if self.optionDisabled then
            return
        end
        _RunOptionAction(descriptor, "set", not (_GetOptionMember("get", descriptor.path) and true or false))
    end)

    function row:Refresh()
        self:RefreshCommon()
        _SetVisible(check, _GetOptionMember("get", descriptor.path) and true or false)
    end

    local applyBaseTheme = row.ApplyTheme
    function row:ApplyTheme()
        applyBaseTheme(self)
        QuestieCustomConfigSkin:ApplySquareBackdrop(box, palette.insetBg, palette.borderSoft, 1)
        check:SetVertexColor(unpack(palette.accent))
    end

    return row
end

local function _CreateSelectRow(page, descriptor)
    descriptor.isFontSelect = string.find(tostring(descriptor.option.dialogControl or descriptor.option.control or ""), "LSM", 1, true) ~= nil
    local optionPathKey = table.concat(descriptor.path, ".")
    if descriptor.isFontSelect and not HALF_SPAN_FONT_SELECT_PATHS[optionPathKey] then
        descriptor.fullSpan = true
    end

    local row = _CreateInteractiveRow(page, descriptor, 29)
    row.fullSpan = descriptor.fullSpan
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.label:SetPoint("RIGHT", row, "CENTER", -6, 0)

    local button = CreateFrame("Button", nil, row)
    button:SetPoint("LEFT", row, "CENTER", 4, 0)
    button:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    button:SetHeight(20)
    QuestieCustomConfigSkin:ApplySquareBackdrop(button, palette.headerBg, palette.borderSoft, 1)
    button.optionDescriptor = descriptor

    local selected = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    selected:SetPoint("LEFT", button, "LEFT", 6, 0)
    selected:SetPoint("RIGHT", button, "RIGHT", -19, 0)
    selected:SetJustifyH("LEFT")
    selected:SetWordWrap(false)

    local arrow = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    arrow:SetPoint("RIGHT", button, "RIGHT", -6, 1)
    arrow:SetText("v")

    button:SetScript("OnClick", function(self)
        if not row.optionDisabled then
            _OpenNativeSelectPopup(self)
        end
    end)
    button:SetScript("OnEnter", function(self)
        if not row.optionDisabled then
            self:SetBackdropBorderColor(unpack(palette.accent))
        end
        _ShowOptionTooltip(row)
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(palette.borderSoft))
        _HideOptionTooltip()
    end)

    function row:MeasureHeight(width)
        self.label:ClearAllPoints()
        button:ClearAllPoints()
        if width < 360 then
            self.label:SetPoint("TOPLEFT", self, "TOPLEFT", 7, -3)
            self.label:SetPoint("TOPRIGHT", self, "TOPRIGHT", -7, -3)
            button:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 7, 4)
            button:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -7, 4)
            self.layoutHeight = 48
        else
            self.label:SetPoint("LEFT", self, "LEFT", 7, 0)
            self.label:SetPoint("RIGHT", self, "CENTER", -6, 0)
            button:SetPoint("LEFT", self, "CENTER", 4, 0)
            button:SetPoint("RIGHT", self, "RIGHT", -6, 0)
            self.layoutHeight = 29
        end
        return self.layoutHeight
    end

    function row:Refresh()
        self:RefreshCommon()
        local currentValue = _GetOptionMember("get", descriptor.path)
        local currentText = tostring(currentValue or "NONE")
        for _, entry in ipairs(_GetSelectEntries(descriptor)) do
            if entry.key == currentValue then
                currentText = entry.text
                break
            end
        end
        _SetSelectRowFont(selected, descriptor, currentValue)
        selected:SetText(currentText)
        selected:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.navIdleText))
        arrow:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.text))
        if self.optionDisabled then
            button:Disable()
        else
            button:Enable()
        end
    end

    local applyBaseTheme = row.ApplyTheme
    function row:ApplyTheme()
        applyBaseTheme(self)
        QuestieCustomConfigSkin:ApplySquareBackdrop(button, palette.headerBg, palette.borderSoft, 1)
        selected:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.navIdleText))
        arrow:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.text))
    end

    return row
end

local function _CreateInputRow(page, descriptor)
    descriptor.fullSpan = true
    local row = _CreateInteractiveRow(page, descriptor, 29)
    row.fullSpan = true
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.label:SetPoint("RIGHT", row, "CENTER", -6, 0)

    local edit = CreateFrame("EditBox", nil, row)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetPoint("LEFT", row, "CENTER", 4, 0)
    edit:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    edit:SetHeight(20)
    edit:SetTextInsets(6, 6, 0, 0)
    QuestieCustomConfigSkin:ApplySquareBackdrop(edit, palette.headerBg, palette.borderSoft, 1)
    edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        row:Refresh()
    end)
    edit:SetScript("OnEnterPressed", function(self)
        if row.optionDisabled then
            return
        end
        local value = self:GetText() or ""
        if _ValidateOptionInput(descriptor, value) then
            _RunOptionAction(descriptor, "set", value)
            self:ClearFocus()
        end
    end)
    edit:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(unpack(palette.accent))
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(unpack(palette.borderSoft))
    end)

    function row:MeasureHeight(width)
        self.label:ClearAllPoints()
        edit:ClearAllPoints()
        if width < 360 then
            self.label:SetPoint("TOPLEFT", self, "TOPLEFT", 7, -3)
            self.label:SetPoint("TOPRIGHT", self, "TOPRIGHT", -7, -3)
            edit:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 7, 4)
            edit:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -7, 4)
            self.layoutHeight = 48
        else
            self.label:SetPoint("LEFT", self, "LEFT", 7, 0)
            self.label:SetPoint("RIGHT", self, "CENTER", -6, 0)
            edit:SetPoint("LEFT", self, "CENTER", 4, 0)
            edit:SetPoint("RIGHT", self, "RIGHT", -6, 0)
            self.layoutHeight = 29
        end
        return self.layoutHeight
    end

    function row:Refresh()
        self:RefreshCommon()
        if not edit:HasFocus() then
            local current = _GetOptionMember("get", descriptor.path)
            edit:SetText(type(current) == "string" and current or "")
        end
        edit:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.navIdleText))
        edit:EnableMouse(not self.optionDisabled)
    end

    local applyBaseTheme = row.ApplyTheme
    function row:ApplyTheme()
        applyBaseTheme(self)
        QuestieCustomConfigSkin:ApplySquareBackdrop(edit, palette.headerBg, palette.borderSoft, 1)
        edit:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.navIdleText))
    end

    return row
end

local function _CreateExecuteRow(page, descriptor)
    local row = _CreateInteractiveRow(page, descriptor, 29)
    row.label:Hide()

    local button = CreateFrame("Button", nil, row)
    button:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -4)
    button:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 4)
    QuestieCustomConfigSkin:ApplySquareBackdrop(button, palette.headerBg, palette.borderSoft, 1)

    local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", button, "LEFT", 7, 0)
    label:SetPoint("RIGHT", button, "RIGHT", -7, 0)
    label:SetJustifyH("CENTER")

    button:SetScript("OnClick", function()
        if not row.optionDisabled then
            _RunOptionAction(descriptor, "func")
        end
    end)
    button:SetScript("OnEnter", function(self)
        if not row.optionDisabled then
            self:SetBackdropBorderColor(unpack(palette.accent))
            label:SetTextColor(unpack(palette.textBright))
        end
        _ShowOptionTooltip(row)
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(palette.borderSoft))
        label:SetTextColor(unpack(row.optionDisabled and palette.textSoft or palette.text))
        _HideOptionTooltip()
    end)

    function row:Refresh()
        self:RefreshCommon()
        label:SetText(_GetOptionName(descriptor.path))
        label:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.text))
        if self.optionDisabled then
            button:Disable()
        else
            button:Enable()
        end
    end

    local applyBaseTheme = row.ApplyTheme
    function row:ApplyTheme()
        applyBaseTheme(self)
        QuestieCustomConfigSkin:ApplySquareBackdrop(button, palette.headerBg, palette.borderSoft, 1)
        label:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.text))
    end

    return row
end

local function _FormatRangeValue(value, step, isPercent)
    value = tonumber(value) or 0
    if isPercent then
        return string.format("%d%%", math.floor((value * 100) + 0.5))
    elseif step and step < 0.01 then
        return string.format("%.3f", value)
    elseif step and step < 0.1 then
        return string.format("%.2f", value)
    elseif step and step < 1 then
        return string.format("%.1f", value)
    end
    return tostring(math.floor(value + 0.5))
end

local function _CreateRangeRow(page, descriptor)
    local row = _CreateInteractiveRow(page, descriptor, 43)
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 7, -4)
    row.label:SetPoint("TOPRIGHT", row, "TOPRIGHT", -57, -4)

    local valueBox = CreateFrame("EditBox", nil, row)
    valueBox:SetAutoFocus(false)
    valueBox:SetFontObject(GameFontNormalSmall)
    valueBox:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -3)
    valueBox:SetSize(48, 17)
    valueBox:SetJustifyH("CENTER")
    QuestieCustomConfigSkin:ApplySquareBackdrop(valueBox, palette.headerBg, palette.borderSoft, 1)

    local slider = CreateFrame("Slider", nil, row)
    slider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 7, 5)
    slider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -7, 5)
    slider:SetHeight(11)
    slider:SetOrientation("HORIZONTAL")
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    QuestieCustomConfigSkin:ApplySquareBackdrop(slider, palette.insetBg, palette.borderSoft, 1)
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(7, 13)
    thumb:SetVertexColor(unpack(palette.accent))

    local function _GetRange()
        local minimum = tonumber(_GetOptionMember("softMin", descriptor.path))
            or tonumber(_GetOptionMember("min", descriptor.path))
            or 0
        local maximum = tonumber(_GetOptionMember("softMax", descriptor.path))
            or tonumber(_GetOptionMember("max", descriptor.path))
            or 100
        local step = tonumber(_GetOptionMember("bigStep", descriptor.path))
            or tonumber(_GetOptionMember("step", descriptor.path))
            or 1
        return minimum, maximum, step
    end

    slider:SetScript("OnValueChanged", function(self, value)
        if self.refreshing or row.optionDisabled then
            return
        end
        local _, _, step = _GetRange()
        valueBox:SetText(_FormatRangeValue(value, step, _GetOptionMember("isPercent", descriptor.path)))
        _GetOptionMember("set", descriptor.path, value)
    end)
    slider:SetScript("OnMouseUp", function()
        _ScheduleNativeRefresh()
    end)
    valueBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        row:Refresh()
    end)
    valueBox:SetScript("OnEnterPressed", function(self)
        local minimum, maximum, step = _GetRange()
        local raw = string.gsub(self:GetText() or "", "%%", "")
        local value = tonumber(raw)
        if not value then
            row:Refresh()
            self:ClearFocus()
            return
        end
        if _GetOptionMember("isPercent", descriptor.path) then
            value = value / 100
        end
        value = mathMin(mathMax(value, minimum), maximum)
        if step > 0 then
            value = minimum + (math.floor(((value - minimum) / step) + 0.5) * step)
        end
        _RunOptionAction(descriptor, "set", value)
        self:ClearFocus()
    end)

    function row:Refresh()
        self:RefreshCommon()
        local minimum, maximum, step = _GetRange()
        local value = tonumber(_GetOptionMember("get", descriptor.path)) or minimum
        slider.refreshing = true
        slider:SetMinMaxValues(minimum, maximum)
        slider:SetValueStep(step)
        slider:SetValue(mathMin(mathMax(value, minimum), maximum))
        slider.refreshing = nil
        valueBox:SetText(_FormatRangeValue(value, step, _GetOptionMember("isPercent", descriptor.path)))
        valueBox:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.navIdleText))
        slider:EnableMouse(not self.optionDisabled)
        valueBox:EnableMouse(not self.optionDisabled)
    end

    local applyBaseTheme = row.ApplyTheme
    function row:ApplyTheme()
        applyBaseTheme(self)
        QuestieCustomConfigSkin:ApplySquareBackdrop(valueBox, palette.headerBg, palette.borderSoft, 1)
        QuestieCustomConfigSkin:ApplySquareBackdrop(slider, palette.insetBg, palette.borderSoft, 1)
        thumb:SetVertexColor(unpack(palette.accent))
    end

    return row
end

local function _CreateColorRow(page, descriptor)
    local row = _CreateInteractiveRow(page, descriptor, 29)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -72, 0)

    local swatch = CreateFrame("Button", nil, row)
    swatch:SetPoint("RIGHT", row, "RIGHT", -7, 0)
    swatch:SetSize(58, 18)
    QuestieCustomConfigSkin:ApplySquareBackdrop(swatch, palette.headerBg, palette.borderSoft, 1)

    local color = QuestieCustomConfigSkin:CreateSolid(swatch, "ARTWORK", {1, 1, 1, 1})
    color:SetPoint("TOPLEFT", swatch, "TOPLEFT", 3, -3)
    color:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -3, 3)

    swatch:SetScript("OnClick", function()
        if row.optionDisabled then
            return
        end

        ColorPickerFrame:Hide()
        local r, g, b, a = _GetOptionMember("get", descriptor.path)
        r, g, b, a = tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1, tonumber(a) or 1
        local hasAlpha = _GetOptionMember("hasAlpha", descriptor.path) and true or false

        local function _ApplyPickerColor()
            local newR, newG, newB = ColorPickerFrame:GetColorRGB()
            local newA = hasAlpha and (1 - OpacitySliderFrame:GetValue()) or 1
            _GetOptionMember("set", descriptor.path, newR, newG, newB, newA)
            color:SetVertexColor(newR, newG, newB, newA)
        end

        ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ColorPickerFrame:SetFrameLevel((row:GetFrameLevel() or 1) + 20)
        ColorPickerFrame:SetClampedToScreen(true)
        ColorPickerFrame.func = _ApplyPickerColor
        ColorPickerFrame.hasOpacity = hasAlpha
        ColorPickerFrame.opacity = 1 - a
        ColorPickerFrame.opacityFunc = _ApplyPickerColor
        ColorPickerFrame.cancelFunc = function()
            _GetOptionMember("set", descriptor.path, r, g, b, a)
            color:SetVertexColor(r, g, b, a)
            _ScheduleNativeRefresh()
        end
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Show()
    end)
    swatch:SetScript("OnEnter", function(self)
        if not row.optionDisabled then
            self:SetBackdropBorderColor(unpack(palette.accent))
        end
        _ShowOptionTooltip(row)
    end)
    swatch:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(palette.borderSoft))
        _HideOptionTooltip()
        _ScheduleNativeRefresh()
    end)

    function row:Refresh()
        self:RefreshCommon()
        local r, g, b, a = _GetOptionMember("get", descriptor.path)
        color:SetVertexColor(tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1, tonumber(a) or 1)
        if self.optionDisabled then
            swatch:Disable()
        else
            swatch:Enable()
        end
    end

    local applyBaseTheme = row.ApplyTheme
    function row:ApplyTheme()
        applyBaseTheme(self)
        QuestieCustomConfigSkin:ApplySquareBackdrop(swatch, palette.headerBg, palette.borderSoft, 1)
    end

    return row
end

local function _CreateMultiSelectRow(page, descriptor)
    descriptor.fullSpan = true
    local values = _GetOptionMember("values", descriptor.path)
    local keys = {}
    for key in pairs(type(values) == "table" and values or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)

    local row = _CreateInteractiveRow(page, descriptor, 27 + (#keys * 20))
    row.fullSpan = true
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 7, -4)
    row.label:SetPoint("TOPRIGHT", row, "TOPRIGHT", -7, -4)

    row.checks = {}
    for index, key in ipairs(keys) do
        local checkButton = CreateFrame("Button", nil, row)
        checkButton:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -24 - ((index - 1) * 20))
        checkButton:SetPoint("TOPRIGHT", row, "TOPRIGHT", -7, -24 - ((index - 1) * 20))
        checkButton:SetHeight(18)

        local box = CreateFrame("Frame", nil, checkButton)
        box:SetPoint("LEFT", checkButton, "LEFT", 0, 0)
        box:SetSize(13, 13)
        QuestieCustomConfigSkin:ApplySquareBackdrop(box, palette.insetBg, palette.borderSoft, 1)
        local fill = QuestieCustomConfigSkin:CreateSolid(box, "ARTWORK", palette.accent)
        fill:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
        fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)

        local label = checkButton:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("LEFT", box, "RIGHT", 6, 0)
        label:SetPoint("RIGHT", checkButton, "RIGHT", 0, 0)
        label:SetJustifyH("LEFT")
        label:SetText(tostring(values[key]))

        checkButton:SetScript("OnClick", function()
            if not row.optionDisabled then
                local current = _GetOptionMember("get", descriptor.path, key) and true or false
                _RunOptionAction(descriptor, "set", not current, key)
            end
        end)
        row.checks[#row.checks + 1] = {
            key = key,
            button = checkButton,
            box = box,
            fill = fill,
            label = label,
        }
    end

    function row:Refresh()
        self:RefreshCommon()
        for _, checkData in ipairs(self.checks) do
            _SetVisible(checkData.fill, _GetOptionMember("get", descriptor.path, checkData.key) and true or false)
            checkData.label:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.navIdleText))
            if self.optionDisabled then
                checkData.button:Disable()
            else
                checkData.button:Enable()
            end
        end
    end

    local applyBaseTheme = row.ApplyTheme
    function row:ApplyTheme()
        applyBaseTheme(self)
        for _, checkData in ipairs(self.checks) do
            QuestieCustomConfigSkin:ApplySquareBackdrop(checkData.box, palette.insetBg, palette.borderSoft, 1)
            checkData.fill:SetVertexColor(unpack(palette.accent))
            checkData.label:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.navIdleText))
        end
    end

    return row
end

local function _CreateHeadingItem(page, descriptor, isGroup)
    local frame = CreateFrame("Frame", nil, page)
    frame:SetHeight(isGroup and 24 or 22)
    frame.layoutHeight = isGroup and 24 or 22
    frame.fullSpan = true
    frame.optionDescriptor = descriptor

    local title = frame:CreateFontString(nil, "ARTWORK", isGroup and "GameFontNormalLarge" or "GameFontNormal")
    title:SetPoint("LEFT", frame, "LEFT", isGroup and 5 or 7, 1)
    title:SetPoint("RIGHT", frame, "RIGHT", -7, 1)
    title:SetJustifyH("LEFT")

    local line = QuestieCustomConfigSkin:CreateSolid(frame, "ARTWORK", palette.borderSoft)
    line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 5, 2)
    line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 2)
    line:SetHeight(1)

    function frame:Refresh()
        local name = _GetOptionName(descriptor.path)
        self.optionHidden = _IsOptionHidden(descriptor.path) or name == ""
        self.optionDisabled = _IsOptionDisabled(descriptor.path)
        self.searchText = string.lower(_PlainText(
            (descriptor.ancestorSearch or "") .. " " .. name
        ))
        title:SetText(name)
        title:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.textBright))
    end

    function frame:MeasureHeight(width)
        title:SetWidth(mathMax(1, width - 14))
        self.layoutHeight = mathMax(isGroup and 24 or 22, _GetRenderedTextHeight(title, 12) + 9)
        return self.layoutHeight
    end

    function frame:ApplyTheme()
        title:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.textBright))
        line:SetVertexColor(unpack(isGroup and palette.accent or palette.borderSoft))
    end

    return frame
end

local function _CreateDescriptionItem(page, descriptor)
    local frame = CreateFrame("Frame", nil, page)
    frame:SetHeight(16)
    frame.layoutHeight = 16
    frame.fullSpan = true
    frame.optionDescriptor = descriptor

    local label = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -2)
    label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -2)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetWordWrap(true)

    function frame:Refresh()
        local textValue = _GetOptionName(descriptor.path)
        self.optionHidden = _IsOptionHidden(descriptor.path) or textValue == ""
        self.optionDisabled = _IsOptionDisabled(descriptor.path)
        self.searchText = string.lower(_PlainText(
            (descriptor.ancestorSearch or "") .. " " .. textValue
        ))
        label:SetText(textValue)
        label:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.textMuted))
    end

    function frame:MeasureHeight(width)
        label:SetWidth(mathMax(1, width - 14))
        self.layoutHeight = mathMax(16, _GetRenderedTextHeight(label, 11) + 6)
        return self.layoutHeight
    end

    function frame:ApplyTheme()
        label:SetTextColor(unpack(self.optionDisabled and palette.textSoft or palette.textMuted))
    end

    return frame
end

local NATIVE_CONTROL_CREATORS = {
    toggle = _CreateToggleRow,
    select = _CreateSelectRow,
    input = _CreateInputRow,
    execute = _CreateExecuteRow,
    range = _CreateRangeRow,
    color = _CreateColorRow,
    multiselect = _CreateMultiSelectRow,
}

local function _AppendNativeOptions(page, group, path, depth, ancestorSearch)
    for _, entry in ipairs(_SortOptionKeys(group, path)) do
        local option = entry.option
        local optionPath = _CopyPath(path, entry.key)
        local optionName = _GetOptionName(optionPath)
        local optionWidth = _GetOptionMember("width", optionPath)
        local descriptor = {
            option = option,
            path = optionPath,
            depth = depth,
            ancestorSearch = ancestorSearch or "",
            fullSpan = optionWidth == "full"
                or optionWidth == "double"
                or (type(optionWidth) == "number" and optionWidth >= 2),
            dynamicValues = path[1] == "profiles_tab",
        }
        if #_PlainText(optionName) > 34 then
            descriptor.fullSpan = true
        end

        if option.type == "group" then
            local groupSearch = _TrimText((ancestorSearch or "") .. " " .. optionName)
            if optionName ~= "" then
                page.items[#page.items + 1] = _CreateHeadingItem(page, descriptor, true)
            end
            _AppendNativeOptions(page, option, optionPath, depth + 1, groupSearch)
        elseif option.type == "header" then
            page.items[#page.items + 1] = _CreateHeadingItem(page, descriptor, false)
        elseif option.type == "description" then
            page.items[#page.items + 1] = _CreateDescriptionItem(page, descriptor)
        else
            local creator = NATIVE_CONTROL_CREATORS[option.type]
            if creator then
                page.items[#page.items + 1] = creator(page, descriptor)
            end
        end
    end
end

local function _CreateNativeOptionsPage(tabKey)
    local root = _GetOptionsRoot()
    local tabOptions = root and _GetSubOption(root, tabKey)
    if not tabOptions then
        return nil
    end

    local page = CreateFrame("Frame", nil, _QuestieCustomConfig.nativeScroll)
    page:SetSize(1, 1)
    page.items = {}
    page.tabKey = tabKey
    _AppendNativeOptions(page, tabOptions, {tabKey}, 0, _GetOptionName({tabKey}))

    function page:ApplyTheme()
        for _, item in ipairs(self.items) do
            if item.ApplyTheme then
                item:ApplyTheme()
            end
        end
    end

    function page:Refresh()
        for _, item in ipairs(self.items) do
            if item.Refresh then
                item:Refresh()
            end
        end
        self:Reflow()
    end

    function page:ApplyFilter(filterText)
        self.filterText = string.lower(_TrimText(filterText))
        self:Reflow()
    end

    function page:Reflow()
        local pageWidth = mathMax(1, self:GetWidth() or 1)
        local margin = 7
        local gap = 6
        local innerWidth = mathMax(1, pageWidth - (margin * 2))
        local twoColumns = innerWidth >= 590
        local cellWidth = twoColumns and ((innerWidth - gap) / 2) or innerWidth
        local y = -5
        local pendingItem
        local pendingHeight = 0
        local filterText = self.filterText or ""

        local function _FlushPending()
            if pendingItem then
                y = y - pendingHeight - 3
                pendingItem = nil
                pendingHeight = 0
            end
        end

        for _, item in ipairs(self.items) do
            local matchesFilter = filterText == ""
                or string.find(item.searchText or "", filterText, 1, true) ~= nil
            local visible = not item.optionHidden and matchesFilter
            if visible then
                local fullSpan = item.fullSpan or not twoColumns
                if fullSpan then
                    _FlushPending()
                    item:ClearAllPoints()
                    item:SetPoint("TOPLEFT", self, "TOPLEFT", margin, y)
                    item:SetWidth(innerWidth)
                    local height = item.MeasureHeight and item:MeasureHeight(innerWidth) or item.layoutHeight
                    item:SetHeight(height)
                    item:Show()
                    y = y - height - 3
                elseif not pendingItem then
                    item:ClearAllPoints()
                    item:SetPoint("TOPLEFT", self, "TOPLEFT", margin, y)
                    item:SetWidth(cellWidth)
                    local height = item.MeasureHeight and item:MeasureHeight(cellWidth) or item.layoutHeight
                    item:SetHeight(height)
                    item:Show()
                    pendingItem = item
                    pendingHeight = height
                else
                    item:ClearAllPoints()
                    item:SetPoint("TOPLEFT", self, "TOPLEFT", margin + cellWidth + gap, y)
                    item:SetWidth(cellWidth)
                    local height = item.MeasureHeight and item:MeasureHeight(cellWidth) or item.layoutHeight
                    item:SetHeight(height)
                    item:Show()
                    pendingHeight = mathMax(pendingHeight, height)
                    _FlushPending()
                end
            else
                item:Hide()
            end
        end
        _FlushPending()
        self.nativeContentHeight = mathMax(1, -y + 4)
    end

    page:Refresh()
    page:ApplyTheme()
    return page
end

local function _RenderNativeOptionsPage(_, tabKey)
    _QuestieCustomConfig.nativePages = _QuestieCustomConfig.nativePages or {}
    local page = _QuestieCustomConfig.nativePages[tabKey]
    if not page then
        page = _CreateNativeOptionsPage(tabKey)
        if not page then
            return false
        end
        _QuestieCustomConfig.nativePages[tabKey] = page
    end

    _ActivateNativePage(page)
    page:Refresh()
    local searchText = _QuestieCustomConfig.searchBox and _QuestieCustomConfig.searchBox:GetText() or ""
    page:ApplyFilter(searchText)
    _UpdateNativeScrollLayout(page.scrollOffset or 0)
    return true
end

local function _CreatePresetCard(parent, width, height, titleText, descriptionText, previewColors, isActive, onClick)
    local card = CreateFrame("Frame", nil, parent)
    card:SetWidth(width or 1)
    card:SetHeight(height)
    QuestieCustomConfigSkin:ApplySquareBackdrop(card, palette.navIdleBg, palette.borderSoft, 1)

    local accent = QuestieCustomConfigSkin:CreateSolid(card, "ARTWORK", palette.accent)
    accent:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
    accent:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1)
    accent:SetWidth(2)

    local title = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -6)
    title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -170, -6)
    title:SetJustifyH("LEFT")
    title:SetText(titleText)

    local description = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    description:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -170, 6)
    description:SetJustifyH("LEFT")
    description:SetJustifyV("TOP")
    description:SetText(descriptionText)

    local actionButton = CreateFrame("Button", nil, card)
    actionButton:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    actionButton:SetSize(54, 20)
    QuestieCustomConfigSkin:ApplySquareBackdrop(actionButton, palette.headerBg, palette.borderSoft, 1)

    local stateText = actionButton:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    stateText:SetPoint("CENTER", actionButton, "CENTER", 0, 0)
    stateText:SetJustifyH("CENTER")

    local swatches = _CreateColorSwatches(card, previewColors, actionButton)

    function card:SetCompact(compact)
        title:ClearAllPoints()
        if compact then
            title:SetPoint("LEFT", card, "LEFT", 10, 0)
            title:SetPoint("RIGHT", card, "RIGHT", -72, 0)
        else
            title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -6)
            title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -170, -6)
        end
        _SetVisible(description, not compact)
        for _, swatch in ipairs(swatches) do
            _SetVisible(swatch, not compact)
        end
    end

    local function _ApplyState()
        local active = isActive()
        if active then
            card:SetBackdropColor(unpack(palette.navActiveBg))
            card:SetBackdropBorderColor(unpack(palette.accent))
            accent:SetVertexColor(unpack(palette.accent))
            title:SetTextColor(unpack(palette.textBright))
            description:SetTextColor(unpack(palette.textMuted))
            actionButton:SetBackdropColor(unpack(palette.headerBg))
            actionButton:SetBackdropBorderColor(unpack(palette.accent))
            stateText:SetText("ACTIVE")
            stateText:SetTextColor(unpack(palette.accent))
            actionButton:Disable()
        else
            card:SetBackdropColor(unpack(palette.navIdleBg))
            card:SetBackdropBorderColor(unpack(palette.borderSoft))
            accent:SetVertexColor(unpack(palette.borderSoft))
            title:SetTextColor(unpack(palette.navIdleText))
            description:SetTextColor(unpack(palette.textSoft))
            actionButton:SetBackdropColor(unpack(palette.headerBg))
            actionButton:SetBackdropBorderColor(unpack(palette.border))
            stateText:SetText("APPLY")
            stateText:SetTextColor(unpack(palette.text))
            actionButton:Enable()
        end
    end

    actionButton:SetScript("OnEnter", function()
        if not isActive() then
            actionButton:SetBackdropColor(unpack(palette.navActiveBg))
            actionButton:SetBackdropBorderColor(unpack(palette.accent))
            stateText:SetTextColor(unpack(palette.textBright))
        end
    end)
    actionButton:SetScript("OnLeave", _ApplyState)
    actionButton:SetScript("OnClick", function()
        onClick()
    end)

    card.ApplyState = _ApplyState
    card.actionButton = actionButton
    card.description = description
    card.swatches = swatches
    card:SetCompact(false)
    _ApplyState()

    return card
end

local function _RenderColorwaysPage(host)
    _QuestieCustomConfig.nativePages = _QuestieCustomConfig.nativePages or {}
    local cachedPage = _QuestieCustomConfig.nativePages.colorways_tab
    if cachedPage then
        _ActivateNativePage(cachedPage)
        cachedPage:Refresh()
        cachedPage:ApplyTheme()
        _UpdateNativeScrollLayout(cachedPage.scrollOffset or 0)
        return true
    end

    local previousScroll = 0
    if _QuestieCustomConfig.nativePage and _QuestieCustomConfig.nativeScroll then
        previousScroll = _QuestieCustomConfig.nativeScroll:GetVerticalScroll() or 0
    end
    _ReleaseNativePage()

    local scrollFrame = _QuestieCustomConfig.nativeScroll
    local page = CreateFrame("Frame", nil, scrollFrame or host)
    if scrollFrame then
        local pageWidth = scrollFrame:GetWidth() or 0
        if pageWidth < 100 then
            pageWidth = mathMax(1, (host:GetWidth() or 1) - 16)
        end
        page:SetWidth(pageWidth)
        page:SetHeight(1)
    else
        page:SetAllPoints(host)
    end

    if QuestieOptionsUtils.DetermineTheme then
        QuestieOptionsUtils.DetermineTheme()
    end

    local activeIconTheme = Questie.db.profile.iconTheme or "custom"
    local activeColorway = _GetActiveColorwayKey()

    local intro = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    intro:SetPoint("TOPLEFT", page, "TOPLEFT", 12, -8)
    intro:SetPoint("TOPRIGHT", page, "TOPRIGHT", -12, -8)
    intro:SetJustifyH("LEFT")
    intro:SetText("Choose an icon preset or interface colorway. Changes apply immediately.")
    intro:SetTextColor(unpack(palette.textSoft))

    local iconCardHeight = 52
    local iconCardGap = 4
    local iconSection = _CreateNativeSection(page, intro, "Objective Icon Colorways", "These apply Questie's existing objective-icon presets directly: the exact same logic used by the legacy icon-theme selector.", 1)

    local iconCards = {
        {
            key = "questie",
            title = "Questie",
            desc = "Default Questie objective icons, Questie glow behavior, and Questie color rules.",
            preview = {
                {1.000, 0.925, 0.529, 1.00},
                {0.082, 0.855, 0.804, 1.00},
                {0.196, 0.215, 0.247, 1.00},
            },
        },
        {
            key = "pfquest",
            title = "pfQuest",
            desc = "Node-style objective markers with colorized objectives and tighter hotzone clustering.",
            preview = {
                {1.000, 0.090, 0.996, 1.00},
                {0.149, 1.000, 0.149, 1.00},
                {0.180, 0.180, 0.180, 1.00},
            },
        },
        {
            key = "blizzard",
            title = "Blizzard",
            desc = "Uses the 3.3.5a quest POI flow and disables Questie objective markers on the map.",
            preview = {
                {0.380, 0.612, 1.000, 1.00},
                {0.851, 0.918, 1.000, 1.00},
                {0.180, 0.224, 0.322, 1.00},
            },
        },
        {
            key = "custom",
            title = "Custom",
            desc = "Leaves current icon settings untouched and reflects any mixed/manual configuration.",
            preview = {
                {0.906, 0.647, 0.282, 1.00},
                {0.580, 0.580, 0.580, 1.00},
                {0.200, 0.200, 0.200, 1.00},
            },
        },
    }

    local presetCards = {}
    local previousCard
    for index, cardData in ipairs(iconCards) do
        local preset = cardData
        local card = _CreatePresetCard(iconSection, 1, iconCardHeight, preset.title, preset.desc, preset.preview, function()
            if QuestieOptionsUtils.DetermineTheme then
                QuestieOptionsUtils.DetermineTheme()
            end
            return (Questie.db.profile.iconTheme or "custom") == preset.key
        end, function()
            if preset.key ~= "custom" and QuestieOptionsUtils.ExecuteTheme then
                QuestieOptionsUtils.ExecuteTheme(nil, preset.key)
            end
            _RenderCurrentTab("colorways_tab")
        end)
        presetCards[#presetCards + 1] = card
        card:SetPoint("LEFT", iconSection, "LEFT", 8, 0)
        card:SetPoint("RIGHT", iconSection, "RIGHT", -8, 0)
        if previousCard then
            card:SetPoint("TOP", previousCard, "BOTTOM", 0, -iconCardGap)
        else
            card:SetPoint("TOP", iconSection.description, "BOTTOM", 0, -8)
        end
        previousCard = card
    end

    local cardHeight = 54
    local cardGap = 5
    local firstRowTop = -8
    local shellSection = _CreateNativeSection(page, iconSection, "Interface Colorways", "Recolors the /qc shell and supplies matching alternating tracker-row colors. Applying one never enables row backgrounds or changes map colors.", 1)

    local previousShellCard

    local colorwayOrder = {"ascension", "emerald", "tangerine", "peach"}
    local shellRowCount = #colorwayOrder
    for _, colorwayKey in ipairs(colorwayOrder) do
        local presetKey = colorwayKey
        local colorwayData = QuestieCustomConfigData.colorways[presetKey]
        local card = _CreatePresetCard(shellSection, 1, cardHeight, colorwayData.name, colorwayData.subtitle, colorwayData.preview, function()
            return _GetActiveColorwayKey() == presetKey
        end, function()
            _ApplyColorway(presetKey, true)
            _RenderCurrentTab("colorways_tab")
        end)
        presetCards[#presetCards + 1] = card

        card:SetPoint("LEFT", shellSection, "LEFT", 8, 0)
        card:SetPoint("RIGHT", shellSection, "RIGHT", -8, 0)
        if previousShellCard then
            card:SetPoint("TOP", previousShellCard, "BOTTOM", 0, -cardGap)
        else
            card:SetPoint("TOP", shellSection.description, "BOTTOM", 0, firstRowTop)
        end
        previousShellCard = card
    end

    local statusSection = _CreateNativeSection(page, shellSection, "Status", "Current preset state for both systems.", 1)
    local statusText = statusSection:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", statusSection.description, "BOTTOMLEFT", 0, -8)
    statusText:SetPoint("TOPRIGHT", statusSection.description, "BOTTOMRIGHT", 0, -8)
    statusText:SetJustifyH("LEFT")
    statusText:SetText(string.format("Icon preset: %s\nInterface colorway: %s", tostring(activeIconTheme), tostring((QuestieCustomConfigData.colorways[activeColorway] and QuestieCustomConfigData.colorways[activeColorway].name) or activeColorway)))
    statusText:SetTextColor(unpack(palette.navIdleText))

    page.Reflow = function()
        local compactCards = (page:GetWidth() or 0) < 440
        local renderedIconCardHeight = compactCards and 36 or iconCardHeight
        local renderedShellCardHeight = compactCards and 36 or cardHeight
        for _, card in ipairs(presetCards) do
            card:SetCompact(compactCards)
        end
        for index = 1, #iconCards do
            presetCards[index]:SetHeight(renderedIconCardHeight)
        end
        for index = #iconCards + 1, #presetCards do
            presetCards[index]:SetHeight(renderedShellCardHeight)
        end

        local iconSectionHeight = 7
            + _GetRenderedTextHeight(iconSection.title, 14)
            + 2
            + _GetRenderedTextHeight(iconSection.description, 11)
            + 8
            + (#iconCards * renderedIconCardHeight)
            + ((#iconCards - 1) * iconCardGap)
            + 8
        iconSection:SetHeight(iconSectionHeight)

        local shellSectionHeight = 7
            + _GetRenderedTextHeight(shellSection.title, 14)
            + 2
            + _GetRenderedTextHeight(shellSection.description, 11)
            + 8
            + (shellRowCount * renderedShellCardHeight)
            + ((shellRowCount - 1) * cardGap)
            + 8
        shellSection:SetHeight(shellSectionHeight)

        local statusSectionHeight = 7
            + _GetRenderedTextHeight(statusSection.title, 14)
            + 2
            + _GetRenderedTextHeight(statusSection.description, 11)
            + 8
            + _GetRenderedTextHeight(statusText, 22)
            + 8
        statusSection:SetHeight(statusSectionHeight)

        page.nativeContentHeight = 6
            + _GetRenderedTextHeight(intro, 12)
            + 7
            + iconSectionHeight
            + 7
            + shellSectionHeight
            + 7
            + statusSectionHeight
            + 6
    end

    function page:Refresh()
        if QuestieOptionsUtils.DetermineTheme then
            QuestieOptionsUtils.DetermineTheme()
        end
        for _, card in ipairs(presetCards) do
            card:ApplyState()
        end
        local iconTheme = Questie.db.profile.iconTheme or "custom"
        local colorway = _GetActiveColorwayKey()
        statusText:SetText(string.format(
            "Icon preset: %s\nInterface colorway: %s",
            tostring(iconTheme),
            tostring((QuestieCustomConfigData.colorways[colorway] and QuestieCustomConfigData.colorways[colorway].name) or colorway)
        ))
        self:Reflow()
    end

    function page:ApplyTheme()
        intro:SetTextColor(unpack(palette.textSoft))
        for _, section in ipairs({iconSection, shellSection, statusSection}) do
            QuestieCustomConfigSkin:ApplySquareBackdrop(section, palette.panelBg, palette.borderSoft, 1)
            section.accent:SetVertexColor(unpack(palette.accentSoft))
            section.title:SetTextColor(unpack(palette.textBright))
            section.description:SetTextColor(unpack(palette.textMuted))
        end
        statusText:SetTextColor(unpack(palette.navIdleText))
        for _, card in ipairs(presetCards) do
            card:ApplyState()
        end
    end

    _QuestieCustomConfig.nativePages.colorways_tab = page
    _ActivateNativePage(page)
    page:Refresh()
    page:ApplyTheme()
    _UpdateNativeScrollLayout(previousScroll)
    return true
end

_NativeTabRenderers.colorways_tab = _RenderColorwaysPage

for _, nativeTab in ipairs(QuestieCustomConfigData.tabs) do
    if nativeTab.key ~= "colorways_tab" then
        local tabKey = nativeTab.key
        _NativeTabRenderers[tabKey] = function(host)
            return _RenderNativeOptionsPage(host, tabKey)
        end
    end
end

_RefreshChromeTheme = function()
    if not _QuestieCustomConfig.frame then
        return
    end

    QuestieCustomConfigSkin:ApplySquareBackdrop(_QuestieCustomConfig.frame, palette.windowBg, palette.border, 1)
    if _QuestieCustomConfig.searchFrame then
        QuestieCustomConfigSkin:ApplySquareBackdrop(_QuestieCustomConfig.searchFrame, {0.020, 0.024, 0.031, 0.98}, palette.accent, 1)
    end
    if _QuestieCustomConfig.sidebar then
        QuestieCustomConfigSkin:ApplySquareBackdrop(_QuestieCustomConfig.sidebar, palette.panelBg, palette.borderSoft, 1)
    end
    if _QuestieCustomConfig.contentPanel then
        QuestieCustomConfigSkin:ApplySquareBackdrop(_QuestieCustomConfig.contentPanel, palette.panelBg, palette.borderSoft, 1)
    end
    if _QuestieCustomConfig.contentHeader then
        QuestieCustomConfigSkin:ApplySquareBackdrop(_QuestieCustomConfig.contentHeader, palette.headerBg, palette.borderSoft, 1)
    end
    if _QuestieCustomConfig.contentInset then
        QuestieCustomConfigSkin:ApplySquareBackdrop(_QuestieCustomConfig.contentInset, palette.insetBg, palette.borderSoft, 1)
    end
    if _QuestieCustomConfig.titleText then
        QuestieCustomConfigSkin:ColorFont(_QuestieCustomConfig.titleText, palette.textBright)
    end
    if _QuestieCustomConfig.metaText then
        QuestieCustomConfigSkin:ColorFont(_QuestieCustomConfig.metaText, palette.textSoft)
    end
    if _QuestieCustomConfig.closeText then
        QuestieCustomConfigSkin:ColorFont(_QuestieCustomConfig.closeText, palette.textMuted)
    end
    if _QuestieCustomConfig.legacyButton then
        QuestieCustomConfigSkin:ApplySquareBackdrop(_QuestieCustomConfig.legacyButton, palette.headerBg, palette.borderSoft, 1)
    end
    if _QuestieCustomConfig.legacyText then
        QuestieCustomConfigSkin:ColorFont(_QuestieCustomConfig.legacyText, palette.text)
    end
    if _QuestieCustomConfig.tooSmallText then
        QuestieCustomConfigSkin:ColorFont(_QuestieCustomConfig.tooSmallText, palette.textSoft)
    end
    if _QuestieCustomConfig.contentTitle then
        QuestieCustomConfigSkin:ColorFont(_QuestieCustomConfig.contentTitle, palette.textBright)
    end
    if _QuestieCustomConfig.contentSubtitle then
        QuestieCustomConfigSkin:ColorFont(_QuestieCustomConfig.contentSubtitle, palette.textMuted)
    end
    if _QuestieCustomConfig.emptySearchText then
        QuestieCustomConfigSkin:ColorFont(_QuestieCustomConfig.emptySearchText, palette.textSoft)
    end
    if _QuestieCustomConfig.searchPlaceholder then
        QuestieCustomConfigSkin:ColorFont(_QuestieCustomConfig.searchPlaceholder, palette.textSoft)
    end
    if _QuestieCustomConfig.searchBox then
        _QuestieCustomConfig.searchBox:SetTextColor(unpack(palette.navIdleText))
    end
    if _QuestieCustomConfig.headerAccent then
        _QuestieCustomConfig.headerAccent:SetVertexColor(unpack(palette.accent))
    end
    if _QuestieCustomConfig.contentAccent then
        _QuestieCustomConfig.contentAccent:SetVertexColor(unpack(palette.accent))
    end
    if _QuestieCustomConfig.accentGlow then
        _QuestieCustomConfig.accentGlow:SetVertexColor(unpack(palette.accentSoft))
    end
    if _QuestieCustomConfig.nativeScrollBar then
        QuestieCustomConfigSkin:ApplySquareBackdrop(_QuestieCustomConfig.nativeScrollBar, palette.insetBg, palette.borderSoft, 1)
    end
    if _QuestieCustomConfig.nativeScrollThumb then
        _QuestieCustomConfig.nativeScrollThumb:SetVertexColor(unpack(palette.accent))
    end
    if _QuestieCustomConfig.selectPopup then
        local popup = _QuestieCustomConfig.selectPopup
        QuestieCustomConfigSkin:ApplySquareBackdrop(popup, palette.windowBg, palette.accent, 1)
        QuestieCustomConfigSkin:ApplySquareBackdrop(popup.searchFrame, palette.insetBg, palette.borderSoft, 1)
        QuestieCustomConfigSkin:ApplySquareBackdrop(popup.scrollBar, palette.insetBg, palette.borderSoft, 1)
        popup.thumb:SetVertexColor(unpack(palette.accent))
        popup.placeholder:SetTextColor(unpack(palette.textSoft))
        popup.search:SetTextColor(unpack(palette.navIdleText))
    end
    if _QuestieCustomConfig.resizeDots then
        if _QuestieCustomConfig.resizeDots[1] then
            _QuestieCustomConfig.resizeDots[1]:SetVertexColor(unpack(palette.border))
        end
        if _QuestieCustomConfig.resizeDots[2] then
            _QuestieCustomConfig.resizeDots[2]:SetVertexColor(unpack(palette.border))
        end
        if _QuestieCustomConfig.resizeDots[3] then
            _QuestieCustomConfig.resizeDots[3]:SetVertexColor(unpack(palette.borderSoft))
        end
    end
    for _, button in ipairs(_QuestieCustomConfig.navButtons or {}) do
        _ApplyNavButtonState(button, button.tabKey == _QuestieCustomConfig.currentTab)
    end
    for _, page in pairs(_QuestieCustomConfig.nativePages or {}) do
        if page.ApplyTheme then
            page:ApplyTheme()
        end
    end
end

_RenderCurrentTab = function(tabKey)
    local renderer = _NativeTabRenderers[tabKey]

    if not renderer then
        Questie:Error("No native /qc renderer is registered for " .. tostring(tabKey))
        return false
    end

    _QuestieCustomConfig.nativeHost:Show()
    return renderer(_QuestieCustomConfig.nativeHost) ~= false
end

local function _SelectTab(tabKey, forceOpen)
    if not _QuestieCustomConfig.nativeHost then
        return
    end

    tabKey = tabKey or _QuestieCustomConfig.currentTab or _GetState().lastTab or DEFAULT_TAB
    local tabInfo = _GetTabInfo(tabKey)
    if not tabInfo then
        tabKey = DEFAULT_TAB
        tabInfo = _GetTabInfo(tabKey)
    end

    if not forceOpen and _QuestieCustomConfig.currentTab == tabKey then
        return
    end

    _QuestieCustomConfig.currentTab = tabKey
    _QuestieCustomConfig.renderedTab = tabKey
    _GetState().lastTab = tabKey

    if _QuestieCustomConfig.contentTitle then
        _QuestieCustomConfig.contentTitle:SetText(tabInfo.title)
    end

    if _QuestieCustomConfig.contentSubtitle then
        _QuestieCustomConfig.contentSubtitle:SetText(tabInfo.subtitle)
    end

    for _, button in ipairs(_QuestieCustomConfig.navButtons or {}) do
        _ApplyNavButtonState(button, button.tabKey == tabKey)
    end

    _RenderCurrentTab(tabKey)
end

local function _LayoutNavButtons(filterText)
    if not _QuestieCustomConfig.navButtons then
        return
    end

    filterText = lower(filterText or "")

    local visibleIndex = 0
    local firstVisibleTab
    local currentIsVisible = false

    for _, button in ipairs(_QuestieCustomConfig.navButtons) do
        local titleText = lower(button.tabData.title)
        local subtitleText = lower(button.tabData.subtitle)
        local matches = (filterText == "") or find(titleText, filterText, 1, true) or find(subtitleText, filterText, 1, true)

        if matches then
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", _QuestieCustomConfig.navContainer, "TOPLEFT", 0, -(visibleIndex * 28))
            button:SetPoint("TOPRIGHT", _QuestieCustomConfig.navContainer, "TOPRIGHT", 0, -(visibleIndex * 28))
            button:Show()
            visibleIndex = visibleIndex + 1

            if not firstVisibleTab then
                firstVisibleTab = button.tabKey
            end

            if button.tabKey == _QuestieCustomConfig.currentTab then
                currentIsVisible = true
            end
        else
            button:Hide()
        end
    end

    _QuestieCustomConfig.navContainer:SetHeight(mathMax(visibleIndex * 28, 1))

    if visibleIndex == 0 then
        _QuestieCustomConfig.emptySearchText:Show()
    else
        _QuestieCustomConfig.emptySearchText:Hide()
    end

    if firstVisibleTab and not currentIsVisible then
        _SelectTab(firstVisibleTab, true)
    end
end

local function _CreateSearchBox(parent)
    local searchFrame = CreateFrame("Frame", nil, parent)
    searchFrame:SetHeight(20)
    searchFrame:SetWidth(1)
    QuestieCustomConfigSkin:ApplySquareBackdrop(searchFrame, {0.020, 0.024, 0.031, 0.98}, palette.accent, 1)

    local searchBox = CreateFrame("EditBox", nil, searchFrame)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject(ChatFontNormal)
    searchBox:SetTextColor(unpack(palette.navIdleText))
    searchBox:SetPoint("TOPLEFT", searchFrame, "TOPLEFT", 6, -2)
    searchBox:SetPoint("BOTTOMRIGHT", searchFrame, "BOTTOMRIGHT", -18, 2)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEditFocusGained", function()
        _QuestieCustomConfig.searchBoxFocused = true
        _RefreshSearchPlaceholder()
    end)
    searchBox:SetScript("OnEditFocusLost", function()
        _QuestieCustomConfig.searchBoxFocused = false
        _RefreshSearchPlaceholder()
    end)
    searchBox:SetScript("OnTextChanged", function(self)
        _RefreshSearchPlaceholder()
        _LayoutNavButtons(self:GetText())
        local page = _QuestieCustomConfig.nativePage
        if page and page.ApplyFilter then
            page:ApplyFilter(self:GetText())
            _UpdateNativeScrollLayout()
        end
    end)

    local placeholder = searchFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    placeholder:SetText("SEARCH")
    placeholder:SetTextColor(unpack(palette.textSoft))

    local clearButton = CreateFrame("Button", nil, searchFrame)
    clearButton:SetSize(12, 12)
    clearButton:SetPoint("RIGHT", searchFrame, "RIGHT", -3, 0)
    clearButton:SetNormalFontObject(GameFontDisable)
    clearButton:SetHighlightFontObject(GameFontHighlight)
    clearButton:SetText("x")
    clearButton:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:SetFocus()
    end)
    clearButton:Hide()

    _QuestieCustomConfig.searchBox = searchBox
    _QuestieCustomConfig.searchFrame = searchFrame
    _QuestieCustomConfig.searchPlaceholder = placeholder
    _QuestieCustomConfig.searchClear = clearButton
    return searchFrame
end

local function _CreateNavButton(tabData, order)
    local button = CreateFrame("Button", nil, _QuestieCustomConfig.navContainer)
    button:SetHeight(25)
    button:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 16,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    button:SetBackdropColor(unpack(palette.navIdleBg))
    button:SetBackdropBorderColor(unpack(palette.borderSoft))
    button:SetScript("OnEnter", function(self)
        if self.tabKey ~= _QuestieCustomConfig.currentTab then
            self:SetBackdropColor(unpack(palette.navHoverBg))
        end
        _ShowCategoryTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        _ApplyNavButtonState(self, self.tabKey == _QuestieCustomConfig.currentTab)
        _HideCategoryTooltip()
    end)
    button:SetScript("OnClick", function(self)
        _SelectTab(self.tabKey)
    end)

    local accent = QuestieCustomConfigSkin:CreateSolid(button, "ARTWORK", palette.accent)
    accent:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -1)
    accent:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 1)
    accent:SetWidth(2)

    local title = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("LEFT", button, "LEFT", 7, 0)
    title:SetPoint("RIGHT", button, "RIGHT", -7, 0)
    title:SetJustifyH("LEFT")
    title:SetText(tabData.title)

    button.accent = accent
    button.title = title
    button.subtitle = nil
    button.tabKey = tabData.key
    button.tabData = tabData

    _ApplyNavButtonState(button, false)

    return button
end

local function _HideLegacyPanel()
    QuestieOptions:HideFrame()
end

function _QuestieCustomConfig:CreateFrame()
    if self.frame then
        return
    end

    _ApplyColorway(_GetActiveColorwayKey())

    local frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:Hide()
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(160)
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    QuestieCustomConfigSkin:ApplySquareBackdrop(frame, palette.windowBg, palette.border, 1)

    -- Keep only a technical one-unit width minimum; no design min/max width is enforced.
    if frame.SetMinResize then
        frame:SetMinResize(1, MIN_HEIGHT)
    end

    frame:SetScript("OnHide", function()
        _CancelResizeReport()
        _QuestieCustomConfig.isUserResizing = nil
        _SaveWindowState()
    end)
    frame:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        _SaveWindowState()
        if _QuestieCustomConfig.isUserResizing then
            _QuestieCustomConfig.isUserResizing = nil
            _ScheduleResizeReport()
        end
    end)

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -5)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -5)
    header:SetHeight(26)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        _SaveWindowState()
    end)

    local title = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", header, "LEFT", 8, 0)
    title:SetText("Questie Command Center")
    title:SetTextColor(unpack(palette.textBright))

    local headerAccent = QuestieCustomConfigSkin:CreateSolid(header, "ARTWORK", palette.accent)
    headerAccent:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    headerAccent:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -2)
    headerAccent:SetHeight(2)

    local metaText = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    metaText:SetJustifyH("RIGHT")
    metaText:SetTextColor(unpack(palette.textSoft))

    local legacyButton = CreateFrame("Button", nil, header)
    legacyButton:SetSize(64, 18)
    legacyButton:SetPoint("RIGHT", header, "RIGHT", -28, 0)
    QuestieCustomConfigSkin:ApplySquareBackdrop(legacyButton, palette.headerBg, palette.borderSoft, 1)
    local legacyText = legacyButton:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    legacyText:SetPoint("CENTER", legacyButton, "CENTER", 0, 0)
    legacyText:SetText("Legacy")
    legacyText:SetTextColor(unpack(palette.text))
    legacyButton:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(palette.accent))
        legacyText:SetTextColor(unpack(palette.textBright))
    end)
    legacyButton:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(palette.borderSoft))
        legacyText:SetTextColor(unpack(palette.text))
    end)
    legacyButton:SetScript("OnClick", function()
        frame:Hide()
        QuestieOptions:OpenConfigWindow()
    end)

    local closeButton = CreateFrame("Button", nil, header)
    closeButton:SetPoint("RIGHT", header, "RIGHT", -2, -1)
    closeButton:SetSize(16, 16)
    local closeText = closeButton:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    closeText:SetPoint("CENTER", closeButton, "CENTER", 0, 0)
    closeText:SetText("x")
    closeText:SetTextColor(unpack(palette.textMuted))
    closeButton:SetScript("OnEnter", function()
        closeText:SetTextColor(unpack(palette.closeHover))
    end)
    closeButton:SetScript("OnLeave", function()
        closeText:SetTextColor(unpack(palette.textMuted))
        closeText:ClearAllPoints()
        closeText:SetPoint("CENTER", closeButton, "CENTER", 0, 0)
    end)
    closeButton:SetScript("OnMouseDown", function()
        closeText:ClearAllPoints()
        closeText:SetPoint("CENTER", closeButton, "CENTER", 1, -1)
    end)
    closeButton:SetScript("OnMouseUp", function()
        closeText:ClearAllPoints()
        closeText:SetPoint("CENTER", closeButton, "CENTER", 0, 0)
    end)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local searchFrame = _CreateSearchBox(header)
    metaText:SetPoint("RIGHT", legacyButton, "LEFT", -10, 0)
    metaText:SetWidth(132)
    searchFrame:ClearAllPoints()
    searchFrame:SetPoint("LEFT", title, "RIGHT", 15, 0)
    searchFrame:SetPoint("RIGHT", metaText, "LEFT", -10, 0)

    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 6)
    sidebar:SetWidth(132)
    QuestieCustomConfigSkin:ApplySquareBackdrop(sidebar, palette.panelBg, palette.borderSoft, 1)

    local navContainer = CreateFrame("Frame", nil, sidebar)
    navContainer:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, -4)
    navContainer:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -4, -4)
    navContainer:SetHeight(1)

    local emptySearchText = sidebar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    emptySearchText:SetPoint("TOP", sidebar, "TOP", 0, -14)
    emptySearchText:SetText("No matching categories.")
    emptySearchText:SetTextColor(unpack(palette.textSoft))
    emptySearchText:Hide()

    local contentPanel = CreateFrame("Frame", nil, frame)
    contentPanel:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 4, 0)
    contentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    QuestieCustomConfigSkin:ApplySquareBackdrop(contentPanel, palette.panelBg, palette.borderSoft, 1)

    local contentHeader = CreateFrame("Frame", nil, contentPanel)
    contentHeader:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", 4, -4)
    contentHeader:SetPoint("TOPRIGHT", contentPanel, "TOPRIGHT", -4, -4)
    contentHeader:SetHeight(24)
    QuestieCustomConfigSkin:ApplySquareBackdrop(contentHeader, palette.headerBg, palette.borderSoft, 1)

    local contentTitle = contentHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    contentTitle:SetPoint("LEFT", contentHeader, "LEFT", 8, 0)
    contentTitle:SetPoint("RIGHT", contentHeader, "RIGHT", -8, 0)
    contentTitle:SetJustifyH("LEFT")
    contentTitle:SetTextColor(unpack(palette.textBright))

    local contentSubtitle = contentHeader:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    contentSubtitle:SetPoint("LEFT", contentHeader, "LEFT", 8, 0)
    contentSubtitle:SetPoint("RIGHT", contentHeader, "RIGHT", -8, 0)
    contentSubtitle:SetJustifyH("LEFT")
    contentSubtitle:SetTextColor(unpack(palette.textMuted))
    contentSubtitle:Hide()

    local contentAccent = QuestieCustomConfigSkin:CreateSolid(contentHeader, "ARTWORK", palette.accent)
    contentAccent:SetPoint("BOTTOMLEFT", contentHeader, "BOTTOMLEFT", 1, 0)
    contentAccent:SetPoint("BOTTOMRIGHT", contentHeader, "BOTTOMRIGHT", -1, 0)
    contentAccent:SetHeight(2)

    local contentInset = CreateFrame("Frame", nil, contentPanel)
    contentInset:SetPoint("TOPLEFT", contentHeader, "BOTTOMLEFT", 0, -3)
    contentInset:SetPoint("BOTTOMRIGHT", contentPanel, "BOTTOMRIGHT", -4, 4)
    QuestieCustomConfigSkin:ApplySquareBackdrop(contentInset, palette.insetBg, palette.borderSoft, 1)

    local accentGlow = QuestieCustomConfigSkin:CreateSolid(contentInset, "BACKGROUND", palette.accentSoft)
    accentGlow:SetPoint("TOPLEFT", contentInset, "TOPLEFT", 1, -1)
    accentGlow:SetPoint("TOPRIGHT", contentInset, "TOPRIGHT", -1, -1)
    accentGlow:SetHeight(1)

    local nativeHost = CreateFrame("Frame", nil, contentInset)
    nativeHost:SetPoint("TOPLEFT", contentInset, "TOPLEFT", 2, -2)
    nativeHost:SetPoint("BOTTOMRIGHT", contentInset, "BOTTOMRIGHT", -2, 2)
    nativeHost:Hide()

    local nativeScroll = CreateFrame("ScrollFrame", nil, nativeHost)
    nativeScroll:SetPoint("TOPLEFT", nativeHost, "TOPLEFT", 0, 0)
    nativeScroll:SetPoint("BOTTOMRIGHT", nativeHost, "BOTTOMRIGHT", -14, 0)
    nativeScroll:EnableMouseWheel(true)
    local function _ScrollNativeByWheel(_, delta)
        _SetNativeScrollOffset((nativeScroll:GetVerticalScroll() or 0) - ((tonumber(delta) or 0) * NATIVE_SCROLL_STEP))
    end
    nativeScroll:SetScript("OnMouseWheel", _ScrollNativeByWheel)

    local nativeScrollBar = CreateFrame("Slider", nil, nativeHost)
    nativeScrollBar:SetPoint("TOPRIGHT", nativeHost, "TOPRIGHT", -1, -2)
    nativeScrollBar:SetPoint("BOTTOMRIGHT", nativeHost, "BOTTOMRIGHT", -1, 2)
    nativeScrollBar:SetWidth(10)
    nativeScrollBar:SetOrientation("VERTICAL")
    nativeScrollBar:EnableMouse(true)
    nativeScrollBar:EnableMouseWheel(true)
    nativeScrollBar:SetValueStep(1)
    nativeScrollBar:SetMinMaxValues(0, 0.001)
    QuestieCustomConfigSkin:ApplySquareBackdrop(nativeScrollBar, palette.insetBg, palette.borderSoft, 1)
    nativeScrollBar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")

    local nativeScrollThumb = nativeScrollBar:GetThumbTexture()
    nativeScrollThumb:SetSize(6, 26)
    nativeScrollThumb:SetVertexColor(unpack(palette.accent))

    nativeScrollBar:SetScript("OnValueChanged", function(self, value)
        if self.syncingValue or not _QuestieCustomConfig.nativePage then
            return
        end

        _SetNativeScrollOffset(value, false)
    end)
    nativeScrollBar:SetScript("OnMouseWheel", _ScrollNativeByWheel)
    nativeScrollBar:Hide()

    nativeHost:SetScript("OnSizeChanged", function()
        _UpdateNativeScrollLayout()
    end)

    local resizeHandle = CreateFrame("Frame", nil, frame)
    resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    resizeHandle:SetSize(20, 20)
    resizeHandle:EnableMouse(true)
    resizeHandle:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            _CancelResizeReport()
            _QuestieCustomConfig.isUserResizing = true
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        _SaveWindowState()
        if _QuestieCustomConfig.isUserResizing then
            _QuestieCustomConfig.isUserResizing = nil
            _ScheduleResizeReport()
        end
    end)

    local resizeDotA = QuestieCustomConfigSkin:CreateSolid(resizeHandle, "ARTWORK", palette.border)
    resizeDotA:SetPoint("BOTTOMRIGHT", resizeHandle, "BOTTOMRIGHT", -3, 3)
    resizeDotA:SetSize(2, 2)

    local resizeDotB = QuestieCustomConfigSkin:CreateSolid(resizeHandle, "ARTWORK", palette.border)
    resizeDotB:SetPoint("BOTTOMRIGHT", resizeHandle, "BOTTOMRIGHT", -7, 7)
    resizeDotB:SetSize(2, 2)

    local resizeDotC = QuestieCustomConfigSkin:CreateSolid(resizeHandle, "ARTWORK", palette.borderSoft)
    resizeDotC:SetPoint("BOTTOMRIGHT", resizeHandle, "BOTTOMRIGHT", -11, 11)
    resizeDotC:SetSize(2, 2)

    local tooSmallText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    tooSmallText:SetPoint("CENTER", frame, "CENTER", 0, 0)
    tooSmallText:SetText("Widen /qc to continue")
    tooSmallText:SetTextColor(unpack(palette.textSoft))
    tooSmallText:Hide()

    local function _UpdateResponsiveLayout()
        local width = frame:GetWidth() or DEFAULT_WIDTH
        local height = frame:GetHeight() or DEFAULT_HEIGHT

        title:SetText(width >= 640 and "Questie Command Center" or "Questie QC")
        _SetVisible(metaText, width >= 760)
        _SetVisible(searchFrame, width >= 480)
        _SetVisible(legacyButton, width >= 300)
        _SetVisible(title, width >= 150)
        _SetVisible(headerAccent, width >= 150)
        _SetVisible(closeButton, width >= 40)

        searchFrame:ClearAllPoints()
        searchFrame:SetPoint("LEFT", title, "RIGHT", 15, 0)
        if width >= 760 then
            searchFrame:SetPoint("RIGHT", metaText, "LEFT", -10, 0)
        else
            searchFrame:SetPoint("RIGHT", legacyButton, "LEFT", -10, 0)
        end

        contentPanel:ClearAllPoints()
        if width >= 480 then
            sidebar:Show()
            contentPanel:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 4, 0)
        else
            sidebar:Hide()
            contentPanel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
        end
        contentPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)

        local bodyUsable = width >= 420 and height >= 180
        _SetVisible(contentPanel, bodyUsable)
        _SetVisible(tooSmallText, not bodyUsable and width >= 120)
        if width < 120 then
            tooSmallText:Hide()
        end

        _UpdateNativeScrollLayout()
    end

    frame:SetScript("OnSizeChanged", function()
        _UpdateResponsiveLayout()
        _SaveWindowState()
    end)

    frame:SetScript("OnMouseDown", function()
        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focus and focus.ClearFocus then
            focus:ClearFocus()
        end
    end)

    self.frame = frame
    self.header = header
    self.titleText = title
    self.headerAccent = headerAccent
    self.closeText = closeText
    self.sidebar = sidebar
    self.contentPanel = contentPanel
    self.contentHeader = contentHeader
    self.nativeHost = nativeHost
    self.nativeScroll = nativeScroll
    self.nativeScrollBar = nativeScrollBar
    self.nativeScrollThumb = nativeScrollThumb
    self.contentTitle = contentTitle
    self.contentSubtitle = contentSubtitle
    self.contentAccent = contentAccent
    self.contentInset = contentInset
    self.accentGlow = accentGlow
    self.navContainer = navContainer
    self.emptySearchText = emptySearchText
    self.metaText = metaText
    self.legacyButton = legacyButton
    self.legacyText = legacyText
    self.tooSmallText = tooSmallText
    self.UpdateResponsiveLayout = _UpdateResponsiveLayout
    self.resizeDots = {resizeDotA, resizeDotB, resizeDotC}
    self.navButtons = {}

    for index, tab in ipairs(QuestieCustomConfigData.tabs) do
        local button = _CreateNavButton(tab, index)
        tinsert(self.navButtons, button)
    end

    _LayoutNavButtons("")
    _RefreshMetaText()
    _RefreshSearchPlaceholder()
    _ApplyWindowState()
    _UpdateResponsiveLayout()
    _RefreshChromeTheme()

    tinsert(UISpecialFrames, FRAME_NAME)
end

function QuestieCustomConfig:Prime(tabToken)
    if _QuestieCustomConfig.primeInProgress then
        return false
    end

    local targetTab = _ResolveTabKey(tabToken) or _GetState().lastTab or DEFAULT_TAB
    if (targetTab ~= "colorways_tab" and not _EnsureAppRegistered()) or InCombatLockdown() then
        return false
    end

    if _QuestieCustomConfig.frame and _QuestieCustomConfig.renderedTab == targetTab then
        _QuestieCustomConfig.primeDone = true
        return true
    end

    _QuestieCustomConfig.primeInProgress = true
    _QuestieCustomConfig:CreateFrame()

    local frame = _QuestieCustomConfig.frame
    local previousAlpha = frame:GetAlpha()
    local wasMouseEnabled = frame:IsMouseEnabled()
    frame:SetAlpha(0)
    frame:EnableMouse(false)
    frame:Show()
    _SelectTab(targetTab, true)
    frame:Hide()
    frame:SetAlpha(previousAlpha or 1)
    frame:EnableMouse(wasMouseEnabled)

    _QuestieCustomConfig.primeDone = true
    _QuestieCustomConfig.primeInProgress = false
    return true
end

function QuestieCustomConfig:WarmNativePages()
    if _QuestieCustomConfig.pageWarmupStarted or not _QuestieCustomConfig.frame then
        return
    end
    if not _EnsureAppRegistered() then
        return
    end

    _QuestieCustomConfig.pageWarmupStarted = true
    local queue = {}
    for _, tab in ipairs(QuestieCustomConfigData.tabs) do
        if tab.key ~= "colorways_tab" then
            queue[#queue + 1] = tab.key
        end
    end

    local queueIndex = 1
    local function _WarmNextPage()
        if InCombatLockdown() then
            C_Timer.After(1, _WarmNextPage)
            return
        end

        local tabKey = queue[queueIndex]
        if not tabKey then
            _QuestieCustomConfig.pageWarmupComplete = true
            return
        end

        _QuestieCustomConfig.nativePages = _QuestieCustomConfig.nativePages or {}
        if not _QuestieCustomConfig.nativePages[tabKey] then
            local page = _CreateNativeOptionsPage(tabKey)
            if page then
                page:Hide()
                _QuestieCustomConfig.nativePages[tabKey] = page
            end
        end

        queueIndex = queueIndex + 1
        C_Timer.After(0, _WarmNextPage)
    end

    _WarmNextPage()
end

function QuestieCustomConfig:ScheduleWarmup(delay)
    if _QuestieCustomConfig.primeScheduled then
        return
    end

    _QuestieCustomConfig.primeScheduled = true

    local function _TryPrime()
        if not QuestieCustomConfig:Prime(_GetState().lastTab or DEFAULT_TAB) then
            C_Timer.After(1, _TryPrime)
            return
        end
        QuestieCustomConfig:WarmNativePages()
    end

    C_Timer.After(delay or 1.0, _TryPrime)
end

_EnsureAppRegistered = function()
    if _QuestieCustomConfig.appRegistered and _GetOptionsRoot() then
        return true
    end

    if not _GetOptionsRoot() then
        return false
    end

    _QuestieCustomConfig.appRegistered = true
    return true
end

function QuestieCustomConfig:Refresh()
    if _QuestieCustomConfig.frame and _QuestieCustomConfig.frame:IsShown() then
        _RefreshMetaText()
        _SelectTab(_QuestieCustomConfig.currentTab, true)
    end
end

function QuestieCustomConfig:Open(tabToken, requestStartTime)
    local targetTab = _ResolveTabKey(tabToken) or _QuestieCustomConfig.currentTab or _GetState().lastTab or DEFAULT_TAB
    if targetTab ~= "colorways_tab" and not _EnsureAppRegistered() then
        Questie:Error("Questie custom config is not ready yet. Try again in a moment.")
        return
    end

    local openStartTime = GetTime()
    local wasColdStart = not _QuestieCustomConfig.frame
    _QuestieCustomConfig:CreateFrame()
    _ApplyWindowState()
    _HideLegacyPanel()
    _RefreshMetaText()
    _QuestieCustomConfig.frame:Show()

    local wasRebuilt = _QuestieCustomConfig.renderedTab ~= targetTab
    if _QuestieCustomConfig.renderedTab ~= targetTab then
        _SelectTab(targetTab, true)
    else
        _SelectTab(targetTab, false)
    end
    _ReportOpenTiming(requestStartTime, openStartTime, targetTab, wasRebuilt, wasColdStart)
end

function QuestieCustomConfig:Toggle(tabToken, requestStartTime)
    if _QuestieCustomConfig.frame and _QuestieCustomConfig.frame:IsShown() and not tabToken then
        _QuestieCustomConfig.frame:Hide()
        return
    end

    self:Open(tabToken, requestStartTime)
end

function QuestieCustomConfig:PrintHelp()
    Questie:Print("/qc - Toggle the separate Questie Command Center")
    Questie:Print("/qc colorways|tracker|general|icons|auto|nameplates|dbm|advanced|profiles - Jump straight to a category")
    Questie:Print("/qc legacy - Open the original /questie options window")
end

function QuestieCustomConfig:HandleSlash(input)
    input = string.trim(input or "", " ")
    local command = ""
    local requestStartTime = GetTime()

    if input ~= "" then
        for token in string.gmatch(input, "([^%s]+)") do
            command = token
            break
        end
    end

    if command == "" then
        QuestieCustomConfig:Toggle(nil, requestStartTime)
        return
    end

    command = lower(command)

    if command == "help" or command == "?" then
        QuestieCustomConfig:PrintHelp()
        return
    end

    if command == "legacy" then
        if _QuestieCustomConfig.frame and _QuestieCustomConfig.frame:IsShown() then
            _QuestieCustomConfig.frame:Hide()
        end
        QuestieOptions:OpenConfigWindow()
        return
    end

    local tabKey = _ResolveTabKey(command)
    if tabKey then
        QuestieCustomConfig:Open(tabKey, requestStartTime)
        return
    end

    Questie:Print("Unknown /qc command. Use /qc help.")
end

function QuestieCustomConfig:RegisterSlashCommands()
    Questie:RegisterChatCommand("qc", function(input)
        QuestieCustomConfig:HandleSlash(input)
    end)
end
