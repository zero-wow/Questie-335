---@class QuestieConfigNext
local QuestieConfigNext = QuestieLoader:CreateModule("QuestieConfigNext")

---@type QuestieConfigNextWidgets
local Widgets = QuestieLoader:ImportModule("QuestieConfigNextWidgets")
---@type QuestieCustomConfigData
local QuestieCustomConfigData = QuestieLoader:ImportModule("QuestieCustomConfigData")
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")
---@type QuestieTracker
local QuestieTracker = QuestieLoader:ImportModule("QuestieTracker")
---@type TrackerBaseFrame
local TrackerBaseFrame = QuestieLoader:ImportModule("TrackerBaseFrame")
---@type TrackerLinePool
local TrackerLinePool = QuestieLoader:ImportModule("TrackerLinePool")

local C_Timer = QuestieCompat.C_Timer
local unpack = unpack or table.unpack
local floor = math.floor
local max = math.max
local min = math.min

local WINDOW_NAME = "QuestieConfigNextFrame"
local DEFAULT_WIDTH = 860
local DEFAULT_HEIGHT = 620
local MIN_WIDTH = 720
local MIN_HEIGHT = 500
local NAV_WIDTH = 136
local OUTER_GUTTER = 12
local CARD_GUTTER = 12

local private = {
    built = false,
    slashRegistered = false,
    warmupScheduled = false,
    frame = nil,
    cards = {},
    controls = {},
    searchQuery = "",
    layoutBusy = false,
}

local layoutPresets = {
    compact = {
        trackerQuestPadding = 0,
        trackerQuestTitlePadding = 1,
        trackerQuestItemGutter = 0,
        trackerQuestTitleInset = 0,
        trackerObjectiveInset = 0,
        trackerZoneSpacing = 0,
        trackerTopSpacing = 0,
        trackerBottomSpacing = 0,
    },
    balanced = {
        trackerQuestPadding = 2,
        trackerQuestTitlePadding = 1,
        trackerQuestItemGutter = 4,
        trackerQuestTitleInset = 0,
        trackerObjectiveInset = 0,
        trackerZoneSpacing = 0,
        trackerTopSpacing = 0,
        trackerBottomSpacing = 0,
    },
    spacious = {
        trackerQuestPadding = 4,
        trackerQuestTitlePadding = 2,
        trackerQuestItemGutter = 8,
        trackerQuestTitleInset = 2,
        trackerObjectiveInset = 2,
        trackerZoneSpacing = 2,
        trackerTopSpacing = 2,
        trackerBottomSpacing = 2,
    },
}

local _LayoutFrame
local _RefreshControls
local _ReflowCards

local function _Profile()
    return Questie.db and Questie.db.profile
end

local function _CharacterState()
    if not (Questie.db and Questie.db.char) then
        return nil
    end
    Questie.db.char.questieConfigNext = Questie.db.char.questieConfigNext or {}
    Questie.db.char.questieConfigNext.window = Questie.db.char.questieConfigNext.window or {}
    return Questie.db.char.questieConfigNext
end

local function _Theme()
    return QuestieCustomConfigData.palette or Widgets:GetTheme()
end

local function _Clamp(value, low, high)
    return max(low, min(high, value))
end

local function _GetColor(setting, defaultR, defaultG, defaultB, defaultA)
    local profile = _Profile()
    local color = profile and profile[setting]
    if type(color) ~= "table" then
        return defaultR, defaultG, defaultB, defaultA
    end
    return tonumber(color[1]) or defaultR,
        tonumber(color[2]) or defaultG,
        tonumber(color[3]) or defaultB,
        tonumber(color[4]) or defaultA
end

local function _SetColor(setting, r, g, b, a)
    if a == nil then
        _Profile()[setting] = {r, g, b}
    else
        _Profile()[setting] = {r, g, b, a}
    end
end

local function _ApplyTrackerBackdropPreview()
    local baseFrame = TrackerBaseFrame.baseFrame
    local profile = _Profile()
    if not (baseFrame and profile) then
        return
    end

    local bgR, bgG, bgB = _GetColor("trackerBackdropColor", 0, 0, 0)
    local borderR, borderG, borderB = _GetColor("trackerBorderColor", 1, 1, 1)
    if profile.trackerBackdropEnabled then
        local backgroundAlpha = profile.trackerBackdropFader and 0 or (tonumber(profile.trackerBackdropAlpha) or 0.65)
        baseFrame:SetBackdropColor(bgR, bgG, bgB, backgroundAlpha)
        if profile.trackerBorderEnabled then
            local borderAlpha = profile.trackerBackdropFader and 0 or (tonumber(profile.trackerBorderAlpha) or backgroundAlpha)
            baseFrame:SetBackdropBorderColor(borderR, borderG, borderB, borderAlpha)
        else
            baseFrame:SetBackdropBorderColor(borderR, borderG, borderB, 0)
        end
    else
        baseFrame:SetBackdropColor(bgR, bgG, bgB, 0)
        baseFrame:SetBackdropBorderColor(borderR, borderG, borderB, 0)
    end
end

local function _UpdateTrackerFormatting()
    _ApplyTrackerBackdropPreview()
    QuestieTracker:UpdateFormatting()
end

local function _UpdateAlternatingRows()
    TrackerLinePool.UpdateAlternatingRowBackgrounds()
end

local function _MatchesLayoutPreset(preset)
    local profile = _Profile()
    return profile
        and (tonumber(profile.trackerQuestPadding) or 2) == preset.trackerQuestPadding
        and (tonumber(profile.trackerQuestTitlePadding) or 1) == preset.trackerQuestTitlePadding
        and (tonumber(profile.trackerQuestItemGutter) or 4) == preset.trackerQuestItemGutter
        and (tonumber(profile.trackerQuestTitleInset) or 0) == preset.trackerQuestTitleInset
        and (tonumber(profile.trackerObjectiveInset) or 0) == preset.trackerObjectiveInset
        and (tonumber(profile.trackerZoneSpacing) or 0) == preset.trackerZoneSpacing
        and (tonumber(profile.trackerTopSpacing) or 0) == preset.trackerTopSpacing
        and (tonumber(profile.trackerBottomSpacing) or 0) == preset.trackerBottomSpacing
end

local function _GetLayoutDensity()
    if _MatchesLayoutPreset(layoutPresets.compact) then
        return "compact"
    elseif _MatchesLayoutPreset(layoutPresets.balanced) then
        return "balanced"
    elseif _MatchesLayoutPreset(layoutPresets.spacious) then
        return "spacious"
    end
    return "custom"
end

local function _ApplyLayoutDensity(key)
    local preset = layoutPresets[key]
    local profile = _Profile()
    if not (preset and profile) then
        return
    end
    for setting, value in pairs(preset) do
        profile[setting] = value
    end
    profile.trackerLayoutDensity = key
    profile.TrackerWidth = 0
    profile.TrackerHeight = 0
    QuestieTracker:Update()
end

local function _SaveGeometry()
    local frame = private.frame
    local state = _CharacterState()
    if not (frame and state) then
        return
    end
    local frameX, frameY = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if frameX and frameY and parentX and parentY then
        state.window.x = frameX - parentX
        state.window.y = frameY - parentY
    end
    state.window.width = floor(frame:GetWidth() + 0.5)
    state.window.height = floor(frame:GetHeight() + 0.5)
end

local function _RestoreGeometry(frame)
    local state = _CharacterState()
    local saved = state and state.window or {}
    local maxWidth = max(560, UIParent:GetWidth() - 30)
    local maxHeight = max(420, UIParent:GetHeight() - 30)
    local minWidth = min(MIN_WIDTH, maxWidth)
    local minHeight = min(MIN_HEIGHT, maxHeight)
    local width = _Clamp(tonumber(saved.width) or DEFAULT_WIDTH, minWidth, maxWidth)
    local height = _Clamp(tonumber(saved.height) or DEFAULT_HEIGHT, minHeight, maxHeight)

    frame:SetMinResize(minWidth, minHeight)
    frame:SetMaxResize(maxWidth, maxHeight)
    frame:SetSize(width, height)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", tonumber(saved.x) or 0, tonumber(saved.y) or 0)
end

local function _RefreshStatus()
    if not private.frame then
        return
    end
    local profileName = Questie.db.GetCurrentProfile and Questie.db:GetCurrentProfile() or "Default"
    private.frame.footerLeft:SetText("PROFILE  " .. tostring(profileName))
    private.frame.footerRight:SetText("v" .. tostring(QuestieLib:GetAddonVersionString()) .. "  |  NATIVE / CACHED")
end

local function _ApplyShellTheme()
    local frame = private.frame
    if not frame then
        return
    end
    local theme = _Theme()
    Widgets:SetTheme(theme)
    Widgets:ApplyBackdrop(frame, theme.windowBg, theme.border, 1)
    frame.headerBackground:SetVertexColor(unpack(theme.headerBg))
    frame.title:SetTextColor(unpack(theme.textBright))
    frame.titleAccent:SetVertexColor(unpack(theme.accent))
    frame.meta:SetTextColor(unpack(theme.textSoft))
    frame.search:SetBackdropColor(unpack(theme.insetBg))
    frame.search:SetBackdropBorderColor(unpack(theme.accent))
    frame.search.placeholder:SetTextColor(unpack(theme.textSoft))
    frame.search.clear.label:SetTextColor(unpack(theme.textSoft))
    frame.close.label:SetTextColor(unpack(theme.textMuted))
    frame.nav:SetBackdropColor(unpack(theme.panelBg))
    frame.nav:SetBackdropBorderColor(unpack(theme.borderSoft))
    frame.navTitle:SetTextColor(unpack(theme.textSoft))
    frame.page:SetBackdropColor(unpack(theme.panelBg))
    frame.page:SetBackdropBorderColor(unpack(theme.borderSoft))
    frame.pageTitle:SetTextColor(unpack(theme.textBright))
    frame.pageSubtitle:SetTextColor(unpack(theme.textMuted))
    frame.liveText:SetTextColor(unpack(theme.accent))
    frame.footerLeft:SetTextColor(unpack(theme.textSoft))
    frame.footerRight:SetTextColor(unpack(theme.textSoft))
    frame.scroll.track:SetBackdropColor(unpack(theme.insetBg))
    frame.scroll.track:SetBackdropBorderColor(unpack(theme.borderSoft))
    frame.scroll.thumb:SetBackdropColor(unpack(theme.accentSoft))
    frame.scroll.thumb:SetBackdropBorderColor(unpack(theme.accent))
    frame.navActive:SetBackdropColor(unpack(theme.navActiveBg))
    frame.navActive:SetBackdropBorderColor(unpack(theme.accent))
    frame.navActive.label:SetTextColor(unpack(theme.navActiveText))
    for _, navButton in ipairs(frame.futureNav) do
        navButton:Refresh()
    end
    for _, card in ipairs(private.cards) do
        card:SetBackdropColor(unpack(theme.insetBg))
        card:SetBackdropBorderColor(unpack(theme.borderSoft))
        card.title:SetTextColor(unpack(theme.text))
        card.accent:SetVertexColor(unpack(theme.accent))
    end
end

local function _CreateSearchBox(parent)
    local search = CreateFrame("EditBox", nil, parent)
    search:SetHeight(30)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
    search:SetTextColor(0.86, 0.90, 0.94, 1)
    search:SetTextInsets(10, 32, 0, 0)
    Widgets:ApplyBackdrop(search, _Theme().insetBg, _Theme().accent, 1)

    search.placeholder = Widgets:CreateFont(search, 11, _Theme().textSoft, "value")
    search.placeholder:SetPoint("LEFT", search, "LEFT", 10, 0)
    search.placeholder:SetText("SEARCH SETTINGS")

    search.clear = CreateFrame("Button", nil, search)
    search.clear:SetSize(26, 26)
    search.clear:SetPoint("RIGHT", search, "RIGHT", -2, 0)
    search.clear:RegisterForClicks("LeftButtonUp")
    search.clear.label = Widgets:CreateFont(search.clear, 15, _Theme().textSoft, "title")
    search.clear.label:SetAllPoints()
    search.clear.label:SetJustifyH("CENTER")
    search.clear.label:SetText("x")
    search.clear:SetScript("OnEnter", function(self)
        self.label:SetTextColor(unpack(_Theme().closeHover))
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("Clear Search", 1, 0.86, 0.35)
        GameTooltip:Show()
    end)
    search.clear:SetScript("OnLeave", function(self)
        self.label:SetTextColor(unpack(_Theme().textSoft))
        GameTooltip:Hide()
    end)
    search.clear:SetScript("OnClick", function()
        search:SetText("")
        search:SetFocus()
    end)

    search:SetScript("OnEditFocusGained", function(self)
        self.placeholder:Hide()
        self:SetBackdropBorderColor(unpack(_Theme().textBright))
    end)
    search:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            self.placeholder:Show()
        end
        self:SetBackdropBorderColor(unpack(_Theme().accent))
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        self.placeholder:SetShown(text == "" and not self:HasFocus())
        private.searchQuery = string.lower(text)
        if _ReflowCards then
            _ReflowCards(true)
        end
    end)
    return search
end

local function _CreateNavButton(parent, name, description, active)
    if not active then
        return Widgets:CreateButton(parent, {
            name = name,
            description = description,
            height = 30,
            align = "LEFT",
            disabled = function() return true end,
        })
    end

    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(32)
    Widgets:ApplyBackdrop(button, _Theme().navActiveBg, _Theme().accent, 1)
    button.label = Widgets:CreateFont(button, 12, _Theme().navActiveText)
    button.label:SetPoint("LEFT", button, "LEFT", 12, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    button.label:SetText(name)
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(_Theme().navHoverBg))
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(name, 1, 0.86, 0.35)
        GameTooltip:AddLine(description, 0.82, 0.85, 0.90, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(_Theme().navActiveBg))
        GameTooltip:Hide()
    end)
    return button
end

local function _CreateCard(parent, title, description)
    local card = CreateFrame("Frame", nil, parent)
    Widgets:ApplyBackdrop(card, _Theme().insetBg, _Theme().borderSoft, 1)
    card.title = Widgets:CreateFont(card, 13, _Theme().text, "title")
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_GUTTER, -10)
    card.title:SetText(title)
    card.titleHit = CreateFrame("Frame", nil, card)
    card.titleHit:SetPoint("TOPLEFT", card, "TOPLEFT", 7, -5)
    card.titleHit:SetPoint("TOPRIGHT", card, "TOPRIGHT", -7, -5)
    card.titleHit:SetHeight(28)
    Widgets:AttachTooltip(card.titleHit, title, description)
    card.accent = Widgets:CreateSolid(card, "ARTWORK", _Theme().accent)
    card.accent:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    card.accent:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
    card.accent:SetWidth(2)
    card.controls = {}
    card.qcSearchText = string.lower(title .. " " .. (description or ""))
    private.cards[#private.cards + 1] = card
    return card
end

local function _AddControl(card, control)
    card.controls[#card.controls + 1] = control
    private.controls[#private.controls + 1] = control
    control.qcCard = card
    return control
end

local function _TrackerAvailable()
    local profile = _Profile()
    return profile and profile.trackerEnabled
end

local function _TrackerSettingDisabled()
    return not _TrackerAvailable()
end

local function _CreateTrackerWorkspace(parent)
    local essentials = _CreateCard(parent, "Essentials", "The tracker master state, header behavior, and recovery controls.")
    _AddControl(essentials, Widgets:CreateToggle(essentials, {
        name = "Enable Tracker",
        description = "Replaces the Blizzard objective tracker with Questie. Changing this setting reloads the UI.",
        disabled = function() return InCombatLockdown() end,
        get = function() return _Profile().trackerEnabled end,
        set = function(value)
            if value then
                QuestieTracker:Enable()
            else
                QuestieTracker:Disable()
            end
        end,
    }))
    _AddControl(essentials, Widgets:CreateToggle(essentials, {
        name = "Show Tracker Header",
        description = "Keeps the Questie title strip and tracked-quest count visible.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerHeaderEnabled end,
        set = function(value)
            _Profile().trackerHeaderEnabled = value
            QuestieTracker:UpdateFormatting()
        end,
    }))
    _AddControl(essentials, Widgets:CreateSegmented(essentials, {
        name = "Header Position",
        description = "Places the tracker title strip above or below tracked content.",
        disabled = _TrackerSettingDisabled,
        options = {
            {value = "top", label = "Top"},
            {value = "bottom", label = "Bottom"},
        },
        get = function() return _Profile().moveHeaderToBottom and "bottom" or "top" end,
        set = function(value)
            _Profile().moveHeaderToBottom = value == "bottom"
            QuestieTracker:UpdateFormatting()
        end,
    }))
    _AddControl(essentials, Widgets:CreateToggle(essentials, {
        name = "Keep Header Visible When Empty",
        description = "Leaves the header available when no quests are currently tracked.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().alwaysShowTracker end,
        set = function(value)
            _Profile().alwaysShowTracker = value
            if value and Questie.db.char.isTrackerExpanded == false then
                Questie.db.char.isTrackerExpanded = true
            end
            QuestieTracker:UpdateFormatting()
        end,
    }))
    _AddControl(essentials, Widgets:CreateButton(essentials, {
        name = "Reset Tracker Position",
        description = "Returns an off-screen or misplaced tracker to the center of the screen.",
        height = 30,
        disabled = function() return _TrackerSettingDisabled() or InCombatLockdown() end,
        onClick = function()
            QuestieTracker:ResetLocation()
            QuestieTracker:Update()
        end,
    }))

    local layout = _CreateCard(parent, "Layout", "Scale and density without exposing internal SavedVariable names.")
    _AddControl(layout, Widgets:CreateSegmented(layout, {
        name = "Layout Density",
        description = "Applies a coordinated spacing preset and returns tracker width and height to automatic sizing. Custom is a read-only state for individually tuned spacing.",
        disabled = _TrackerSettingDisabled,
        options = {
            {value = "compact", label = "Compact"},
            {value = "balanced", label = "Balanced"},
            {value = "spacious", label = "Roomy"},
            {value = "custom", label = "Custom", readOnly = true},
        },
        get = _GetLayoutDensity,
        set = function(value)
            if value ~= "custom" then
                _ApplyLayoutDensity(value)
            end
        end,
    }))
    _AddControl(layout, Widgets:CreateSlider(layout, {
        name = "Tracker Scale",
        description = "Scales tracker text and inline elements while preserving configured pixel gaps.",
        min = 1,
        max = 5,
        step = 0.01,
        disabled = _TrackerSettingDisabled,
        get = function() return tonumber(_Profile().trackerScale) or 1 end,
        set = function(value)
            _Profile().trackerScale = _Clamp(floor((value * 100) + 0.5) / 100, 1, 5)
            QuestieTracker:Update()
        end,
        format = function(value) return string.format("%.2fx", value) end,
    }))
    _AddControl(layout, Widgets:CreateSegmented(layout, {
        name = "Collapse Direction",
        description = "Normal follows tracker growth. Up Into Header keeps the titlebar edge fixed while content collapses toward it.",
        disabled = _TrackerSettingDisabled,
        options = {
            {value = "normal", label = "Normal"},
            {value = "upward", label = "Up Into Header"},
        },
        get = function() return _Profile().trackerCollapseDirection == "upward" and "upward" or "normal" end,
        set = function(value)
            _Profile().trackerCollapseDirection = value == "upward" and "upward" or "normal"
        end,
    }))

    local surface = _CreateCard(parent, "Surface", "Tracker background, border, header strip, and accent appearance.")
    _AddControl(surface, Widgets:CreateToggle(surface, {
        name = "Show Background",
        description = "Draws the tracker background behind tracked content.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerBackdropEnabled end,
        set = function(value)
            _Profile().trackerBackdropEnabled = value
            _Profile().currentBackdropEnabled = value
            _UpdateTrackerFormatting()
        end,
        onChanged = function() _RefreshControls(false) end,
    }))
    _AddControl(surface, Widgets:CreateToggle(surface, {
        name = "Show Border",
        description = "Draws the one-pixel tracker border.",
        disabled = function() return _TrackerSettingDisabled() or not _Profile().trackerBackdropEnabled end,
        get = function() return _Profile().trackerBorderEnabled end,
        set = function(value)
            _Profile().trackerBorderEnabled = value
            _Profile().currentBorderEnabled = value
            _UpdateTrackerFormatting()
        end,
        onChanged = function() _RefreshControls(false) end,
    }))
    _AddControl(surface, Widgets:CreateToggle(surface, {
        name = "Fade Surface When Idle",
        description = "Fades the tracker background and border while the tracker is not being used.",
        disabled = function() return _TrackerSettingDisabled() or not _Profile().trackerBackdropEnabled end,
        get = function() return _Profile().trackerBackdropFader end,
        set = function(value)
            _Profile().trackerBackdropFader = value
            _Profile().currentBackdropFader = value
            _UpdateTrackerFormatting()
        end,
    }))
    _AddControl(surface, Widgets:CreateSlider(surface, {
        name = "Background Opacity",
        description = "Controls tracker background visibility from transparent to solid.",
        min = 0,
        max = 100,
        step = 5,
        disabled = function() return _TrackerSettingDisabled() or not _Profile().trackerBackdropEnabled end,
        get = function() return (tonumber(_Profile().trackerBackdropAlpha) or 0.65) * 100 end,
        set = function(value)
            _Profile().trackerBackdropAlpha = value / 100
            _UpdateTrackerFormatting()
        end,
        format = function(value) return string.format("%d%%", value) end,
    }))
    _AddControl(surface, Widgets:CreateSlider(surface, {
        name = "Border Opacity",
        description = "Controls the one-pixel border visibility independently of the background.",
        min = 0,
        max = 100,
        step = 5,
        disabled = function() return _TrackerSettingDisabled() or not _Profile().trackerBackdropEnabled or not _Profile().trackerBorderEnabled end,
        get = function() return (tonumber(_Profile().trackerBorderAlpha) or tonumber(_Profile().trackerBackdropAlpha) or 0.65) * 100 end,
        set = function(value)
            _Profile().trackerBorderAlpha = value / 100
            _UpdateTrackerFormatting()
        end,
        format = function(value) return string.format("%d%%", value) end,
    }))
    _AddControl(surface, Widgets:CreateColor(surface, {
        name = "Background Color",
        description = "Sets the tracker backdrop color. Opacity remains controlled separately.",
        disabled = _TrackerSettingDisabled,
        get = function() return _GetColor("trackerBackdropColor", 0, 0, 0, 1) end,
        set = function(r, g, b) _SetColor("trackerBackdropColor", r, g, b); _UpdateTrackerFormatting() end,
    }))
    _AddControl(surface, Widgets:CreateColor(surface, {
        name = "Border Color",
        description = "Sets the color of the tracker's one-pixel border.",
        disabled = _TrackerSettingDisabled,
        get = function() return _GetColor("trackerBorderColor", 1, 1, 1, 1) end,
        set = function(r, g, b) _SetColor("trackerBorderColor", r, g, b); _UpdateTrackerFormatting() end,
    }))
    _AddControl(surface, Widgets:CreateColor(surface, {
        name = "Header Background",
        description = "Sets both the color and opacity of the tracker title strip.",
        hasAlpha = true,
        disabled = _TrackerSettingDisabled,
        get = function() return _GetColor("trackerHeaderBackgroundColor", 0, 0, 0, 0.5) end,
        set = function(r, g, b, a) _SetColor("trackerHeaderBackgroundColor", r, g, b, a); QuestieTracker:UpdateFormatting() end,
    }))
    _AddControl(surface, Widgets:CreateColor(surface, {
        name = "Header Text",
        description = "Sets the Questie Tracker title and tracked-count color.",
        disabled = _TrackerSettingDisabled,
        get = function() return _GetColor("trackerHeaderTextColor", 1, 0.82, 0, 1) end,
        set = function(r, g, b) _SetColor("trackerHeaderTextColor", r, g, b); QuestieTracker:UpdateFormatting() end,
    }))
    _AddControl(surface, Widgets:CreateColor(surface, {
        name = "Header Accent",
        description = "Sets the color and opacity of the line beneath the tracker title strip.",
        hasAlpha = true,
        disabled = _TrackerSettingDisabled,
        get = function() return _GetColor("trackerHeaderAccentColor", 0.16, 0.78, 0.72, 0.38) end,
        set = function(r, g, b, a) _SetColor("trackerHeaderAccentColor", r, g, b, a); QuestieTracker:UpdateFormatting() end,
    }))

    local bands = _CreateCard(parent, "Quest Bands", "Alternating quest backgrounds that preserve wrapped objectives as one readable block.")
    _AddControl(bands, Widgets:CreateToggle(bands, {
        name = "Alternating Quest Backgrounds",
        description = "Draws alternating color bands behind tracker rows or complete quest blocks.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerAlternatingRowsEnabled end,
        set = function(value)
            _Profile().trackerAlternatingRowsEnabled = value
            _UpdateAlternatingRows()
        end,
        onChanged = function() _RefreshControls(false) end,
    }))
    _AddControl(bands, Widgets:CreateSegmented(bands, {
        name = "Band Mode",
        description = "Quest Blocks keeps each title and its objectives on one band. Individual Rows alternates every visible tracker line.",
        disabled = function() return _TrackerSettingDisabled() or not _Profile().trackerAlternatingRowsEnabled end,
        options = {
            {value = "questBlocks", label = "Quest Blocks"},
            {value = "rows", label = "Individual Rows"},
        },
        get = function() return _Profile().trackerAlternatingRowMode == "rows" and "rows" or "questBlocks" end,
        set = function(value)
            _Profile().trackerAlternatingRowMode = value == "rows" and "rows" or "questBlocks"
            _UpdateAlternatingRows()
        end,
        onChanged = function() _RefreshControls(false) end,
    }))
    _AddControl(bands, Widgets:CreateToggle(bands, {
        name = "Span Full Tracker Width",
        description = "Extends each band to the tracker's inner edges without changing text indentation.",
        disabled = function() return _TrackerSettingDisabled() or not _Profile().trackerAlternatingRowsEnabled end,
        get = function() return _Profile().trackerAlternatingFullWidth end,
        set = function(value)
            _Profile().trackerAlternatingFullWidth = value
            _UpdateAlternatingRows()
        end,
    }))
    _AddControl(bands, Widgets:CreateSlider(bands, {
        name = "Band Edge Padding",
        description = "Extends quest-block color into existing space above and below its text without changing tracker layout.",
        min = 0,
        max = 8,
        step = 1,
        disabled = function()
            return _TrackerSettingDisabled()
                or not _Profile().trackerAlternatingRowsEnabled
                or _Profile().trackerAlternatingRowMode == "rows"
        end,
        get = function() return _Clamp(tonumber(_Profile().trackerAlternatingBlockEdgePadding) or 2, 0, 8) end,
        set = function(value)
            _Profile().trackerAlternatingBlockEdgePadding = _Clamp(value, 0, 8)
            _UpdateAlternatingRows()
        end,
        format = function(value) return string.format("%d px", value) end,
    }))
    _AddControl(bands, Widgets:CreateColor(bands, {
        name = "First Band",
        description = "Sets the first, third, and following alternating quest background color and opacity.",
        hasAlpha = true,
        disabled = function() return _TrackerSettingDisabled() or not _Profile().trackerAlternatingRowsEnabled end,
        get = function() return _GetColor("trackerAlternatingRowColorOdd", 0.018, 0.022, 0.031, 0.32) end,
        set = function(r, g, b, a)
            _SetColor("trackerAlternatingRowColorOdd", r, g, b, a)
            _Profile().trackerAlternatingRowPaletteVersion = 1
            _UpdateAlternatingRows()
        end,
    }))
    _AddControl(bands, Widgets:CreateColor(bands, {
        name = "Second Band",
        description = "Sets the second, fourth, and following alternating quest background color and opacity.",
        hasAlpha = true,
        disabled = function() return _TrackerSettingDisabled() or not _Profile().trackerAlternatingRowsEnabled end,
        get = function() return _GetColor("trackerAlternatingRowColorEven", 0.082, 0.855, 0.804, 0.08) end,
        set = function(r, g, b, a)
            _SetColor("trackerAlternatingRowColorEven", r, g, b, a)
            _Profile().trackerAlternatingRowPaletteVersion = 1
            _UpdateAlternatingRows()
        end,
    }))
end

_ReflowCards = function(resetScroll)
    local frame = private.frame
    if not (frame and frame.scroll) then
        return
    end
    local scroll = frame.scroll
    local contentWidth = max(1, scroll.viewport:GetWidth() - 2)
    local query = private.searchQuery or ""
    local y = 0
    local visibleCards = 0

    scroll:SetContentWidth(contentWidth)
    for _, card in ipairs(private.cards) do
        local groupMatch = query == "" or string.find(card.qcSearchText, query, 1, true)
        local controlY = 40
        local visibleControls = 0
        local controlWidth = max(1, contentWidth - (CARD_GUTTER * 2))
        for _, control in ipairs(card.controls) do
            local visible = groupMatch or string.find(control.qcSearchText or "", query, 1, true)
            if visible then
                if control.Layout then
                    control:Layout(controlWidth)
                else
                    control:SetWidth(controlWidth)
                end
                local height = control.qcLayoutHeight or control:GetHeight() or 34
                control:ClearAllPoints()
                control:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_GUTTER, -controlY)
                control:SetHeight(height)
                control:Show()
                controlY = controlY + height + 2
                visibleControls = visibleControls + 1
            else
                control:Hide()
            end
        end

        if visibleControls > 0 then
            card:SetWidth(contentWidth)
            card:SetHeight(controlY + 8)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y)
            card:Show()
            y = y + card:GetHeight() + 10
            visibleCards = visibleCards + 1
        else
            card:Hide()
        end
    end

    frame.noResults:SetShown(visibleCards == 0)
    if visibleCards == 0 then
        frame.noResults:SetPoint("TOP", scroll.content, "TOP", 0, -28)
        y = 80
    end
    scroll:SetContentHeight(max(scroll.viewport:GetHeight() + 1, y > 0 and y - 10 or 1))
    if resetScroll then
        scroll:ScrollToTop()
    end
end

_RefreshControls = function(reflow)
    for _, control in ipairs(private.controls) do
        if control.Refresh then
            control:Refresh()
        end
    end
    if reflow ~= false then
        _ReflowCards(false)
    end
end

_LayoutFrame = function()
    local frame = private.frame
    if not frame or private.layoutBusy then
        return
    end
    private.layoutBusy = true

    local headerWidth = frame:GetWidth() - (OUTER_GUTTER * 2)
    local reservedLeft = 196
    local reservedRight = 212
    local searchWidth = _Clamp(headerWidth - reservedLeft - reservedRight, 220, 340)
    frame.search:SetWidth(searchWidth)
    frame.search:ClearAllPoints()
    frame.search:SetPoint("RIGHT", frame.meta, "LEFT", -12, 0)

    local scrollWidth = frame.scroll:GetWidth()
    if scrollWidth and scrollWidth > 0 then
        frame.scroll:SetContentWidth(max(1, frame.scroll.viewport:GetWidth() - 2))
    end
    _ReflowCards(false)
    private.layoutBusy = false
end

local function _CreateFrame()
    if private.built then
        return private.frame
    end
    if not (Questie.db and Questie.db.profile and Questie.db.char) then
        return nil
    end

    Widgets:SetTheme(_Theme())
    local frame = CreateFrame("Frame", WINDOW_NAME, UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(80)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    Widgets:ApplyBackdrop(frame, _Theme().windowBg, _Theme().border, 1)
    _RestoreGeometry(frame)
    private.frame = frame

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", OUTER_GUTTER, -10)
    frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -OUTER_GUTTER, -10)
    frame.header:SetHeight(48)
    frame.header:EnableMouse(true)
    frame.header:RegisterForDrag("LeftButton")
    frame.headerBackground = Widgets:CreateSolid(frame.header, "BACKGROUND", _Theme().headerBg)
    frame.headerBackground:SetAllPoints()
    frame.header:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    frame.header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        _SaveGeometry()
    end)

    frame.title = Widgets:CreateFont(frame.header, 18, _Theme().textBright, "title")
    frame.title:SetPoint("TOPLEFT", frame.header, "TOPLEFT", 14, -7)
    frame.title:SetText("Questie Settings")
    frame.titleAccent = Widgets:CreateSolid(frame.header, "ARTWORK", _Theme().accent)
    frame.titleAccent:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
    frame.titleAccent:SetSize(frame.title:GetStringWidth() + 2, 2)

    frame.close = CreateFrame("Button", nil, frame.header)
    frame.close:SetSize(30, 30)
    frame.close:SetPoint("RIGHT", frame.header, "RIGHT", -6, 0)
    frame.close:RegisterForClicks("LeftButtonUp")
    frame.close.label = Widgets:CreateFont(frame.close, 17, _Theme().textMuted, "title")
    frame.close.label:SetAllPoints()
    frame.close.label:SetJustifyH("CENTER")
    frame.close.label:SetText("x")
    frame.close:SetScript("OnEnter", function(self)
        self.label:SetTextColor(unpack(_Theme().closeHover))
    end)
    frame.close:SetScript("OnLeave", function(self)
        self.label:SetTextColor(unpack(_Theme().textMuted))
    end)
    frame.close:SetScript("OnMouseDown", function(self) self.label:SetTextColor(unpack(_Theme().textBright)) end)
    frame.close:SetScript("OnMouseUp", function(self) self.label:SetTextColor(unpack(_Theme().closeHover)) end)
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.meta = Widgets:CreateFont(frame.header, 10, _Theme().textSoft, "value")
    frame.meta:SetPoint("RIGHT", frame.close, "LEFT", -10, 0)
    frame.meta:SetWidth(160)
    frame.meta:SetJustifyH("RIGHT")
    frame.meta:SetText("TRACKER  |  LIVE")

    frame.search = _CreateSearchBox(frame.header)

    frame.footer = CreateFrame("Frame", nil, frame)
    frame.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", OUTER_GUTTER, 9)
    frame.footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -OUTER_GUTTER, 9)
    frame.footer:SetHeight(20)
    frame.footerLeft = Widgets:CreateFont(frame.footer, 9, _Theme().textSoft, "value")
    frame.footerLeft:SetPoint("LEFT", frame.footer, "LEFT", 3, 0)
    frame.footerRight = Widgets:CreateFont(frame.footer, 9, _Theme().textSoft, "value")
    frame.footerRight:SetPoint("RIGHT", frame.footer, "RIGHT", -20, 0)
    frame.footerRight:SetJustifyH("RIGHT")

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -8)
    frame.body:SetPoint("BOTTOMRIGHT", frame.footer, "TOPRIGHT", 0, 7)

    frame.nav = CreateFrame("Frame", nil, frame.body)
    frame.nav:SetPoint("TOPLEFT", frame.body, "TOPLEFT", 0, 0)
    frame.nav:SetPoint("BOTTOMLEFT", frame.body, "BOTTOMLEFT", 0, 0)
    frame.nav:SetWidth(NAV_WIDTH)
    Widgets:ApplyBackdrop(frame.nav, _Theme().panelBg, _Theme().borderSoft, 1)
    frame.navTitle = Widgets:CreateFont(frame.nav, 9, _Theme().textSoft, "value")
    frame.navTitle:SetPoint("TOPLEFT", frame.nav, "TOPLEFT", 12, -11)
    frame.navTitle:SetText("WORKSPACES")

    frame.navActive = _CreateNavButton(frame.nav, "Tracker", "Tracker layout, surface, scale, and quest-band presentation.", true)
    frame.navActive:SetPoint("TOPLEFT", frame.nav, "TOPLEFT", 8, -34)
    frame.navActive:SetPoint("TOPRIGHT", frame.nav, "TOPRIGHT", -8, -34)

    frame.futureNav = {}
    local future = {
        {"Map & Icons", "Planned next: world map, minimap, objective, and quest-note presentation."},
        {"Automation", "Planned next: quest interaction, tracking, and vendor automation."},
        {"Profiles", "Planned next: profile switching, import, export, and sharing."},
    }
    local previous = frame.navActive
    for _, info in ipairs(future) do
        local button = _CreateNavButton(frame.nav, info[1], info[2], false)
        button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
        button:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, -6)
        frame.futureNav[#frame.futureNav + 1] = button
        previous = button
    end

    frame.page = CreateFrame("Frame", nil, frame.body)
    frame.page:SetPoint("TOPLEFT", frame.nav, "TOPRIGHT", 10, 0)
    frame.page:SetPoint("BOTTOMRIGHT", frame.body, "BOTTOMRIGHT", 0, 0)
    Widgets:ApplyBackdrop(frame.page, _Theme().panelBg, _Theme().borderSoft, 1)
    frame.pageTitle = Widgets:CreateFont(frame.page, 18, _Theme().textBright, "title")
    frame.pageTitle:SetPoint("TOPLEFT", frame.page, "TOPLEFT", 16, -12)
    frame.pageTitle:SetText("Tracker")
    frame.pageSubtitle = Widgets:CreateFont(frame.page, 10, _Theme().textMuted)
    frame.pageSubtitle:SetPoint("TOPLEFT", frame.page, "TOPLEFT", 16, -36)
    frame.pageSubtitle:SetPoint("TOPRIGHT", frame.page, "TOPRIGHT", -72, -36)
    frame.pageSubtitle:SetText("Direct controls, immediate preview, cached layout.")
    frame.liveText = Widgets:CreateFont(frame.page, 9, _Theme().accent, "value")
    frame.liveText:SetPoint("TOPRIGHT", frame.page, "TOPRIGHT", -16, -18)
    frame.liveText:SetText("LIVE")

    frame.scroll = Widgets:CreateScrollArea(frame.page)
    frame.scroll:SetPoint("TOPLEFT", frame.page, "TOPLEFT", 12, -58)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame.page, "BOTTOMRIGHT", -10, 10)
    frame.noResults = Widgets:CreateFont(frame.scroll.content, 12, _Theme().textSoft)
    frame.noResults:SetText("No Tracker settings match your search.")
    frame.noResults:Hide()

    _CreateTrackerWorkspace(frame.scroll.content)

    frame.sizer = CreateFrame("Button", nil, frame)
    frame.sizer:SetSize(22, 22)
    frame.sizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    frame.sizer:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    frame.sizer.lines = {}
    for index = 1, 3 do
        local line = Widgets:CreateSolid(frame.sizer, "ARTWORK", _Theme().textSoft)
        line:SetSize(4 + (index * 3), 1)
        line:SetPoint("BOTTOMRIGHT", frame.sizer, "BOTTOMRIGHT", -3, 3 + ((index - 1) * 4))
        line:SetAlpha(0.55)
        frame.sizer.lines[index] = line
    end
    frame.sizer:SetScript("OnEnter", function()
        for _, line in ipairs(frame.sizer.lines) do line:SetVertexColor(unpack(_Theme().accent)) end
        GameTooltip:SetOwner(frame.sizer, "ANCHOR_CURSOR")
        GameTooltip:SetText("Resize Settings", 1, 0.86, 0.35)
        GameTooltip:AddLine("Drag to resize the native configuration panel.", 0.82, 0.85, 0.90, true)
        GameTooltip:Show()
    end)
    frame.sizer:SetScript("OnLeave", function()
        for _, line in ipairs(frame.sizer.lines) do line:SetVertexColor(unpack(_Theme().textSoft)) end
        GameTooltip:Hide()
    end)
    frame.sizer:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    frame.sizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        _SaveGeometry()
        _LayoutFrame()
    end)

    frame:SetScript("OnSizeChanged", function()
        _LayoutFrame()
    end)
    frame:SetScript("OnShow", function()
        QuestieConfigNext:Refresh()
        frame:Raise()
    end)
    frame:SetScript("OnHide", function()
        frame.search:ClearFocus()
        _SaveGeometry()
    end)

    local alreadySpecial
    for _, name in ipairs(UISpecialFrames) do
        if name == WINDOW_NAME then
            alreadySpecial = true
            break
        end
    end
    if not alreadySpecial then
        table.insert(UISpecialFrames, WINDOW_NAME)
    end

    private.built = true
    _ApplyShellTheme()
    _RefreshStatus()
    _RefreshControls(true)
    _LayoutFrame()
    frame:Hide()
    return frame
end

function QuestieConfigNext:Prime()
    return _CreateFrame() ~= nil
end

function QuestieConfigNext:ScheduleWarmup(delay)
    if private.built or private.warmupScheduled then
        return
    end
    private.warmupScheduled = true
    local attempts = 0
    local function warm()
        attempts = attempts + 1
        if QuestieConfigNext:Prime() or attempts >= 10 then
            private.warmupScheduled = false
            return
        end
        C_Timer.After(0.5, warm)
    end
    C_Timer.After(tonumber(delay) or 0.25, warm)
end

function QuestieConfigNext:Refresh()
    if not private.built then
        return
    end
    _ApplyShellTheme()
    _RefreshStatus()
    _RefreshControls(true)
end

function QuestieConfigNext:Open()
    local started = GetTime()
    local wasBuilt = private.built
    local frame = _CreateFrame()
    if not frame then
        Questie:Print("/qcnew is waiting for Questie initialization. Try again in a moment.")
        return
    end
    if frame:IsShown() then
        self:Refresh()
    else
        frame:Show()
    end
    frame:Raise()
    Questie:Print(string.format("[/qcnew] %.3fs (%s, Tracker)", GetTime() - started, wasBuilt and "warm" or "cold"))
end

function QuestieConfigNext:Toggle()
    if private.frame and private.frame:IsShown() then
        private.frame:Hide()
    else
        self:Open()
    end
end

function QuestieConfigNext:HandleSlash(input)
    local command = string.lower((input or ""):match("^%s*(.-)%s*$"))
    if command == "" or command == "tracker" then
        self:Toggle()
    elseif command == "open" then
        self:Open()
    elseif command == "close" then
        if private.frame then private.frame:Hide() end
    elseif command == "reset" then
        local state = _CharacterState()
        if state then
            state.window = {}
        end
        if private.frame then
            _RestoreGeometry(private.frame)
            _LayoutFrame()
            _SaveGeometry()
        end
        Questie:Print("/qcnew window position and size reset.")
    else
        Questie:Print("/qcnew [tracker | open | close | reset]")
    end
end

function QuestieConfigNext:RegisterSlashCommands()
    if private.slashRegistered then
        return
    end
    Questie:RegisterChatCommand("qcnew", function(input)
        QuestieConfigNext:HandleSlash(input)
    end)
    private.slashRegistered = true
end
