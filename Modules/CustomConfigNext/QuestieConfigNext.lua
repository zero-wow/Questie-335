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
---@type TrackerFonts
local TrackerFonts = QuestieLoader:ImportModule("TrackerFonts")
---@type TrackerQuestTimers
local TrackerQuestTimers = QuestieLoader:ImportModule("TrackerQuestTimers")

local unpack = unpack or table.unpack
local floor = math.floor
local max = math.max
local min = math.min

local WINDOW_NAME = "QuestieConfigNextFrame"
local WINDOW_LAYOUT_VERSION = 2
local DEFAULT_WIDTH = 680
local DEFAULT_HEIGHT = 450
local MIN_WIDTH = 600
local MIN_HEIGHT = 390
local OUTER_GUTTER = 8
local CARD_GUTTER = 4
local CARD_HEADER_HEIGHT = 30
local CARD_GAP = 6
local CONTROL_COLUMN_GAP = 8
local CONTROL_ROW_GAP = 1

local private = {
    built = false,
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

local shortcutOptions = {
    {value = "left", label = "Left Click"},
    {value = "right", label = "Right Click"},
    {value = "shiftleft", label = "Shift + Left Click"},
    {value = "shiftright", label = "Shift + Right Click"},
    {value = "ctrlleft", label = "Control + Left Click"},
    {value = "ctrlright", label = "Control + Right Click"},
    {value = "altleft", label = "Alt + Left Click"},
    {value = "altright", label = "Alt + Right Click"},
    {value = "disabled", label = "Disabled"},
}

local objectiveColorOptions = {
    {value = "white", label = "White"},
    {value = "whiteToGreen", label = "White to Green"},
    {value = "whiteAndGreen", label = "White and Green"},
    {value = "redToGreen", label = "Red to Green"},
    {value = "questProgress", label = "Quest % Complete"},
    {value = "minimal", label = "Minimal"},
}

local objectiveSortOptions = {
    {value = "byComplete", label = "Completion"},
    {value = "byCompleteReversed", label = "Completion, Reversed"},
    {value = "byLevel", label = "Level"},
    {value = "byLevelReversed", label = "Level, Reversed"},
    {value = "byProximity", label = "Proximity"},
    {value = "byProximityReversed", label = "Proximity, Reversed"},
    {value = "byZone", label = "Zone"},
    {value = "byZonePlayerProximity", label = "Zone Proximity"},
    {value = "byZonePlayerProximityReversed", label = "Zone Proximity, Reversed"},
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

local function _ClearAutoCollapsedQuests()
    Questie.db.char.collapsedQuests = Questie.db.char.collapsedQuests or {}
    for questId in pairs(Questie.db.char.autoCollapsedQuests or {}) do
        Questie.db.char.collapsedQuests[questId] = nil
    end
    Questie.db.char.autoCollapsedQuests = {}
end

local function _SetCustomLayoutValue(setting, value)
    local profile = _Profile()
    profile[setting] = value
    profile.trackerLayoutDensity = "custom"
    if (tonumber(profile.TrackerWidth) or 0) ~= 0 then
        profile.TrackerWidth = 0
    end
    if (tonumber(profile.TrackerHeight) or 0) ~= 0 then
        profile.TrackerHeight = 0
    end
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
    state.window.layoutVersion = WINDOW_LAYOUT_VERSION
end

local function _RestoreGeometry(frame)
    local state = _CharacterState()
    local saved = state and state.window or {}
    local maxWidth = max(520, UIParent:GetWidth() - 16)
    local maxHeight = max(350, UIParent:GetHeight() - 16)
    local minWidth = min(MIN_WIDTH, maxWidth)
    local minHeight = min(MIN_HEIGHT, maxHeight)
    local requestedWidth = tonumber(saved.width) or DEFAULT_WIDTH
    local requestedHeight = tonumber(saved.height) or DEFAULT_HEIGHT

    -- Shrink the oversized prototype once without discarding a smaller custom size.
    if saved.layoutVersion ~= WINDOW_LAYOUT_VERSION then
        requestedWidth = min(requestedWidth, DEFAULT_WIDTH)
        requestedHeight = min(requestedHeight, DEFAULT_HEIGHT)
        saved.layoutVersion = WINDOW_LAYOUT_VERSION
    end

    local width = _Clamp(requestedWidth, minWidth, maxWidth)
    local height = _Clamp(requestedHeight, minHeight, maxHeight)

    frame:SetMinResize(minWidth, minHeight)
    frame:SetMaxResize(maxWidth, maxHeight)
    frame:SetSize(width, height)
    frame:ClearAllPoints()
    local maxX = max(0, (UIParent:GetWidth() - width) / 2)
    local maxY = max(0, (UIParent:GetHeight() - height) / 2)
    local x = _Clamp(tonumber(saved.x) or 0, -maxX, maxX)
    local y = _Clamp(tonumber(saved.y) or 0, -maxY, maxY)
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    saved.width = floor(width + 0.5)
    saved.height = floor(height + 0.5)
    saved.x = x
    saved.y = y
end

local function _RefreshStatus()
    if not private.frame then
        return
    end
    local profileName = Questie.db.GetCurrentProfile and Questie.db:GetCurrentProfile() or "Default"
    private.frame.meta:SetText(tostring(profileName) .. "  |  v" .. tostring(QuestieLib:GetAddonVersionString()))
end

local function _ApplyShellTheme()
    local frame = private.frame
    if not frame then
        return
    end
    local theme = _Theme()
    Widgets:SetTheme(theme)
    Widgets:ApplyBackdrop(frame, theme.windowBg, theme.borderSoft, 1)
    frame.headerBackground:SetVertexColor(unpack(theme.headerBg))
    frame.title:SetTextColor(unpack(theme.textBright))
    frame.titleAccent:SetVertexColor(unpack(theme.accent))
    frame.meta:SetTextColor(unpack(theme.textSoft))
    frame.search:SetBackdropColor(unpack(theme.insetBg))
    frame.search:SetBackdropBorderColor(unpack(frame.search:HasFocus() and theme.accent or theme.borderSoft))
    frame.search.placeholder:SetTextColor(unpack(theme.textSoft))
    frame.search.clear.label:SetTextColor(unpack(theme.textSoft))
    frame.close.label:SetTextColor(unpack(theme.textMuted))
    frame.page:SetBackdropColor(unpack(theme.panelBg))
    frame.page:SetBackdropBorderColor(0, 0, 0, 0)
    frame.scroll.track:SetBackdropColor(unpack(theme.insetBg))
    frame.scroll.track:SetBackdropBorderColor(unpack(theme.borderSoft))
    frame.scroll.thumb:SetBackdropColor(unpack(theme.accentSoft))
    frame.scroll.thumb:SetBackdropBorderColor(unpack(theme.accent))
    for _, navButton in ipairs(frame.navButtons) do
        navButton:Refresh()
    end
    for _, card in ipairs(private.cards) do
        card:SetBackdropColor(0, 0, 0, 0)
        card:SetBackdropBorderColor(0, 0, 0, 0)
        card.title:SetTextColor(unpack(theme.text))
        card.collapseLabel:SetTextColor(unpack(theme.textSoft))
        card.rule:SetVertexColor(unpack(theme.borderSoft))
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
    Widgets:ApplyBackdrop(search, _Theme().insetBg, _Theme().borderSoft, 1)

    search.placeholder = Widgets:CreateFont(search, 11, _Theme().textSoft, "value")
    search.placeholder:SetPoint("LEFT", search, "LEFT", 10, 0)
    search.placeholder:SetText("Search tracker settings")

    search.clear = CreateFrame("Button", nil, search)
    search.clear:SetSize(26, 26)
    search.clear:SetPoint("RIGHT", search, "RIGHT", -2, 0)
    search.clear:RegisterForClicks("LeftButtonUp")
    search.clear.label = Widgets:CreateFont(search.clear, 15, _Theme().textSoft, "title")
    search.clear.label:SetAllPoints()
    search.clear.label:SetJustifyH("CENTER")
    search.clear.label:SetText("x")
    search.clear:Hide()
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
        self:SetBackdropBorderColor(unpack(_Theme().accent))
    end)
    search:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            self.placeholder:Show()
        end
        self:SetBackdropBorderColor(unpack(_Theme().borderSoft))
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        Widgets:SetShown(self.placeholder, text == "" and not self:HasFocus())
        Widgets:SetShown(self.clear, text ~= "")
        private.searchQuery = string.lower(text)
        if _ReflowCards then
            _ReflowCards(true)
        end
    end)
    return search
end

local function _CreateNavButton(parent, name, description, active, available)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(28)
    button:RegisterForClicks("LeftButtonUp")
    button.qcActive = active and true or false
    button.qcAvailable = available ~= false
    Widgets:ApplyBackdrop(button, active and _Theme().navActiveBg or _Theme().navIdleBg, _Theme().borderSoft, 1)
    button.label = Widgets:CreateFont(button, 11, active and _Theme().navActiveText or _Theme().textSoft)
    button.label:SetPoint("LEFT", button, "LEFT", 7, 0)
    button.label:SetPoint("RIGHT", button, "RIGHT", -7, 0)
    button.label:SetJustifyH("CENTER")
    button.label:SetText(name)
    button.accent = Widgets:CreateSolid(button, "ARTWORK", _Theme().accent)
    button.accent:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
    button.accent:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.accent:SetHeight(2)

    function button:Refresh()
        self:SetBackdropColor(unpack(self.qcActive and _Theme().navActiveBg or _Theme().navIdleBg))
        self:SetBackdropBorderColor(unpack(_Theme().borderSoft))
        self.label:SetTextColor(unpack(self.qcActive and _Theme().navActiveText or _Theme().textSoft))
        self.accent:SetVertexColor(unpack(_Theme().accent))
        Widgets:SetShown(self.accent, self.qcActive)
        self:SetAlpha(self.qcAvailable and 1 or 0.55)
    end

    button:SetScript("OnEnter", function(self)
        if self.qcAvailable and not self.qcActive then
            self:SetBackdropColor(unpack(_Theme().navHoverBg))
        end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(name, 1, 0.86, 0.35)
        GameTooltip:AddLine(description, 0.82, 0.85, 0.90, true)
        if not self.qcAvailable then
            GameTooltip:AddLine("Planned for a later /qcnew workspace.", 0.58, 0.63, 0.69, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        self:Refresh()
        GameTooltip:Hide()
    end)
    button:Refresh()
    return button
end

local function _CreateCard(parent, title, description)
    local card = CreateFrame("Frame", nil, parent)
    Widgets:ApplyBackdrop(card, {0, 0, 0, 0}, {0, 0, 0, 0}, 1)
    card.title = Widgets:CreateFont(card, 12, _Theme().text, "title")
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_GUTTER, -7)
    card.title:SetText(title)
    card.titleHit = CreateFrame("Button", nil, card)
    card.titleHit:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -3)
    card.titleHit:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -3)
    card.titleHit:SetHeight(23)
    card.titleHit:RegisterForClicks("LeftButtonUp")
    card.collapseLabel = Widgets:CreateFont(card.titleHit, 10, _Theme().textSoft, "value")
    card.collapseLabel:SetPoint("RIGHT", card.titleHit, "RIGHT", -2, 0)
    card.rule = Widgets:CreateSolid(card, "ARTWORK", _Theme().borderSoft)
    card.rule:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_GUTTER, -26)
    card.rule:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_GUTTER, -26)
    card.rule:SetHeight(1)
    card.controls = {}
    card.qcSearchText = string.lower(title .. " " .. (description or ""))
    local state = _CharacterState()
    state.collapsedSections = state.collapsedSections or {}
    local savedCollapseState = state.collapsedSections[title]
    card.qcCollapsed = savedCollapseState == nil and title ~= "Essentials" or savedCollapseState == true
    function card:RefreshCollapseLabel()
        self.collapseLabel:SetText(self.qcCollapsed and ">" or "v")
    end
    card.titleHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(title, 1, 0.86, 0.35)
        GameTooltip:AddLine(description, 0.82, 0.85, 0.90, true)
        GameTooltip:AddLine(card.qcCollapsed and "Click to expand" or "Click to collapse", 0.36, 0.86, 0.80)
        GameTooltip:Show()
    end)
    card.titleHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    card.titleHit:SetScript("OnClick", function()
        card.qcCollapsed = not card.qcCollapsed
        state.collapsedSections[title] = card.qcCollapsed
        card:RefreshCollapseLabel()
        _ReflowCards(false)
    end)
    card:RefreshCollapseLabel()
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
    _AddControl(essentials, Widgets:CreateButton(essentials, {
        name = "Repair Tracker Anchor",
        description = "Normalizes the saved anchor and reapplies the current growth direction without forcing the tracker to screen center.",
        height = 30,
        disabled = function() return _TrackerSettingDisabled() or InCombatLockdown() end,
        onClick = function() TrackerBaseFrame:RepairLocation() end,
    }))

    local quests = _CreateCard(parent, "Quests & Interactions", "Quest visibility, timer behavior, ordering, and tracker click actions.")
    _AddControl(quests, Widgets:CreateToggle(quests, {
        name = "Auto Track Quests",
        description = "Automatically tracks every quest in the quest log. Turning this off clears Questie's automatic tracking state.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().autoTrackQuests end,
        set = function(value)
            _Profile().autoTrackQuests = value
            if value then
                Questie.db.char.TrackedQuests = {}
            else
                Questie.db.char.AutoUntrackedQuests = {}
            end
            local questLogFrame = QuestLogExFrame or ClassicQuestLog or QuestLogFrame
            if questLogFrame and questLogFrame:IsShown() and QuestLog_Update then
                QuestLog_Update()
            end
            QuestieTracker:Update()
        end,
        onChanged = function() _RefreshControls(false) end,
    }))
    _AddControl(quests, Widgets:CreateToggle(quests, {
        name = "Show Quest Levels",
        description = "Shows each quest's level before its title.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerShowQuestLevel end,
        set = function(value) _Profile().trackerShowQuestLevel = value; QuestieTracker:Update() end,
    }))
    _AddControl(quests, Widgets:CreateToggle(quests, {
        name = "Use Blizzard Quest Timer",
        description = "Shows Blizzard's timer frame instead of embedding timed quests in Questie.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().showBlizzardQuestTimer end,
        set = function(value)
            _Profile().showBlizzardQuestTimer = value
            if value then
                TrackerQuestTimers:ShowBlizzardTimer()
            else
                TrackerQuestTimers:HideBlizzardTimer()
            end
            QuestieTracker:Update()
        end,
    }))
    _AddControl(quests, Widgets:CreateToggle(quests, {
        name = "List Achievements First",
        description = "Places tracked achievements before quests.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().listAchievementsFirst end,
        set = function(value) _Profile().listAchievementsFirst = value; QuestieTracker:Update() end,
    }))
    _AddControl(quests, Widgets:CreateSelect(quests, {
        name = "Open Quest Log",
        description = "Mouse shortcut that opens the clicked tracker quest in the quest log.",
        options = shortcutOptions,
        fullWidth = false,
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerbindOpenQuestLog or "left" end,
        set = function(value) _Profile().trackerbindOpenQuestLog = value end,
    }))
    _AddControl(quests, Widgets:CreateSelect(quests, {
        name = "Untrack or Link",
        description = "Mouse shortcut that untracks a quest, or links it when a chat input is active.",
        options = shortcutOptions,
        fullWidth = false,
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerbindUntrack or "shiftleft" end,
        set = function(value) _Profile().trackerbindUntrack = value end,
    }))

    local objectives = _CreateCard(parent, "Objectives", "Completion visibility, automatic collapsing, color progression, and sort order.")
    _AddControl(objectives, Widgets:CreateToggle(objectives, {
        name = "Show Completed Quests",
        description = "Keeps completed quests visible while automatic quest tracking is enabled.",
        disabled = function() return _TrackerSettingDisabled() or not _Profile().autoTrackQuests end,
        get = function() return _Profile().trackerShowCompleteQuests end,
        set = function(value) _Profile().trackerShowCompleteQuests = value; QuestieTracker:Update() end,
    }))
    _AddControl(objectives, Widgets:CreateToggle(objectives, {
        name = "Auto Collapse Completed Quests",
        description = "Automatically collapses completed quest blocks without affecting manually collapsed quests.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().collapseCompletedQuests end,
        set = function(value)
            _Profile().collapseCompletedQuests = value
            if not value then
                _ClearAutoCollapsedQuests()
            end
            QuestieTracker:Update()
        end,
        onChanged = function() _RefreshControls(false) end,
    }))
    _AddControl(objectives, Widgets:CreateToggle(objectives, {
        name = "Active Zone Only",
        description = "Limits automatic completed-quest collapsing to the current zone or subzone.",
        disabled = function() return _TrackerSettingDisabled() or not _Profile().collapseCompletedQuests end,
        get = function() return _Profile().collapseCompletedQuestsCurrentZoneOnly end,
        set = function(value)
            _ClearAutoCollapsedQuests()
            _Profile().collapseCompletedQuestsCurrentZoneOnly = value
            QuestieTracker:Update()
        end,
    }))
    _AddControl(objectives, Widgets:CreateToggle(objectives, {
        name = "Hide Completed Quest Objectives",
        description = "Removes completed objective lines from tracked quests.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().hideCompletedQuestObjectives end,
        set = function(value) _Profile().hideCompletedQuestObjectives = value; QuestieTracker:Update() end,
    }))
    _AddControl(objectives, Widgets:CreateToggle(objectives, {
        name = "Hide Completed Achievement Objectives",
        description = "Removes completed objective lines from tracked achievements.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().hideCompletedAchieveObjectives end,
        set = function(value) _Profile().hideCompletedAchieveObjectives = value; QuestieTracker:Update() end,
    }))
    _AddControl(objectives, Widgets:CreateToggle(objectives, {
        name = "Hide Blizzard Completion Text",
        description = "Uses Questie's compact complete or failed labels instead of Blizzard completion text.",
        disabled = function() return _TrackerSettingDisabled() or _Profile().trackerColorObjectives == "minimal" end,
        get = function() return _Profile().hideBlizzardCompletionText end,
        set = function(value)
            _Profile().hideBlizzardCompletionText = value
            if not value then
                Questie.db.char.collapsedQuests = {}
            end
            QuestieTracker:Update()
        end,
    }))
    _AddControl(objectives, Widgets:CreateSelect(objectives, {
        name = "Objective Color",
        description = "Colors objective text by individual or parent-quest completion progress.",
        options = objectiveColorOptions,
        fullWidth = false,
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerColorObjectives or "minimal" end,
        set = function(value) _Profile().trackerColorObjectives = value; QuestieTracker:Update() end,
        onChanged = function() _RefreshControls(false) end,
    }))
    _AddControl(objectives, Widgets:CreateSelect(objectives, {
        name = "Objective Sorting",
        description = "Controls how tracked quests and objectives are ordered.",
        options = objectiveSortOptions,
        fullWidth = false,
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerSortObjectives or "byZonePlayerProximity" end,
        set = function(value) _Profile().trackerSortObjectives = value; QuestieTracker:Update() end,
    }))

    local autoQuests = _CreateCard(parent, "Auto-Provided Quests", "Ascension quest offers shown directly at the top of the Questie Tracker.")
    _AddControl(autoQuests, Widgets:CreateToggle(autoQuests, {
        name = "Show Auto-Provided Quests",
        description = "Mirrors every Ascension auto-provided quest as a compact notice. The global Auto Accept Quests setting also applies.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerAutoQuestNotices end,
        set = function(value) QuestieTracker:SetAutoQuestNoticesEnabled(value) end,
        onChanged = function() _RefreshControls(false) end,
    }))
    _AddControl(autoQuests, Widgets:CreateToggle(autoQuests, {
        name = "Hide Native Quest Notices",
        description = "Keeps the native WatchFrame hidden while Questie owns an auto-provided offer, then restores timed-quest behavior.",
        disabled = function() return _TrackerSettingDisabled() or not _Profile().trackerAutoQuestNotices end,
        get = function() return _Profile().trackerAutoQuestHideNative end,
        set = function(value) QuestieTracker:SetAutoQuestHideNative(value) end,
    }))
    _AddControl(autoQuests, Widgets:CreateToggle(autoQuests, {
        name = "Animate Quest Notices",
        description = "Slides new notices open and pulses the Accept action.",
        disabled = function() return _TrackerSettingDisabled() or not _Profile().trackerAutoQuestNotices end,
        get = function() return _Profile().trackerAutoQuestNoticeAnimation end,
        set = function(value)
            _Profile().trackerAutoQuestNoticeAnimation = value and true or false
            QuestieTracker:Update(true)
        end,
    }))

    local dungeon = _CreateCard(parent, "Dungeon Objectives", "Ascension's LFG objective data mirrored inside the Questie Tracker.")
    _AddControl(dungeon, Widgets:CreateToggle(dungeon, {
        name = "Show Dungeon Objectives",
        description = "Recreates the native LFG objective block in Questie's style and hides the native block only after a valid mirror exists.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerMirrorLFGObjectives end,
        set = function(value) QuestieTracker:SetLFGObjectiveMirrorEnabled(value) end,
        onChanged = function() _RefreshControls(false) end,
    }))
    _AddControl(dungeon, Widgets:CreateSlider(dungeon, {
        name = "Dungeon Section Position",
        description = "Zero places the dungeon block first. Higher values place it after that many visible zone blocks.",
        min = 0,
        max = 25,
        step = 1,
        fullWidth = false,
        disabled = function() return _TrackerSettingDisabled() or not _Profile().trackerMirrorLFGObjectives end,
        get = function() return _Clamp(tonumber(_Profile().trackerLFGObjectivePosition) or 0, 0, 25) end,
        set = function(value)
            _Profile().trackerLFGObjectivePosition = _Clamp(floor(value + 0.5), 0, 25)
            QuestieTracker:Update(true)
        end,
        format = function(value) return tostring(floor(value + 0.5)) end,
    }))

    local window = _CreateCard(parent, "Window & Controls", "Tracker visibility, movement, quest-item placement, growth, and attachment behavior.")
    _AddControl(window, Widgets:CreateToggle(window, {
        name = "Collapse in Combat",
        description = "Automatically collapses the tracker when combat starts.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().hideTrackerInCombat end,
        set = function(value) _Profile().hideTrackerInCombat = value end,
    }))
    _AddControl(window, Widgets:CreateToggle(window, {
        name = "Collapse in Dungeons",
        description = "Automatically collapses the tracker while inside an instance.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().hideTrackerInDungeons end,
        set = function(value)
            _Profile().hideTrackerInDungeons = value
            if value and IsInInstance() then
                QuestieTracker:Collapse()
            else
                QuestieTracker:Expand()
            end
        end,
    }))
    _AddControl(window, Widgets:CreateToggle(window, {
        name = "Fade Quest Item Buttons",
        description = "Fades quest-item buttons until the tracker is being used.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerFadeQuestItemButtons end,
        set = function(value)
            _Profile().trackerFadeQuestItemButtons = value
            TrackerLinePool.SetAllItemButtonAlpha(value and 0 or 1)
            QuestieTracker:Update()
        end,
    }))
    _AddControl(window, Widgets:CreateToggle(window, {
        name = "Hide Resize Grip",
        description = "Hides the lower-right tracker resize and scale grip.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().sizerHidden end,
        set = function(value) _Profile().sizerHidden = value; QuestieTracker:UpdateFormatting() end,
    }))
    _AddControl(window, Widgets:CreateToggle(window, {
        name = "Lock Tracker",
        description = "Requires Control to be held while moving the tracker.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerLocked end,
        set = function(value) _Profile().trackerLocked = value; TrackerBaseFrame:Update() end,
    }))
    _AddControl(window, Widgets:CreateToggle(window, {
        name = "Attach Durability Frame",
        description = "Places the durability frame beside the tracker based on screen position.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().stickyDurabilityFrame end,
        set = function(value)
            _Profile().stickyDurabilityFrame = value
            if not value then QuestieTracker:ResetDurabilityFrame() end
            QuestieTracker:Update()
        end,
    }))
    if IsAddOnLoaded and IsAddOnLoaded("AI_VoiceOver") and IsAddOnLoaded("AI_VoiceOverData_Vanilla") then
        _AddControl(window, Widgets:CreateToggle(window, {
            name = "Attach VoiceOver Frame",
            description = "Places the VoiceOver queue beside the tracker based on screen position.",
            disabled = _TrackerSettingDisabled,
            get = function() return _Profile().stickyVoiceOverFrame end,
            set = function(value)
                _Profile().stickyVoiceOverFrame = value
                if not value then QuestieTracker:ResetVoiceOverFrame() end
                QuestieTracker:Update()
            end,
        }))
    end
    _AddControl(window, Widgets:CreateSegmented(window, {
        name = "Quest Item Buttons",
        description = "Keeps quest-item buttons outside for a clean text column, or embeds them inside the tracker.",
        disabled = _TrackerSettingDisabled,
        options = {
            {value = "outsideLeft", label = "Outside"},
            {value = "inside", label = "Inside"},
        },
        get = function() return _Profile().trackerQuestItemButtonPosition or "outsideLeft" end,
        set = function(value) _Profile().trackerQuestItemButtonPosition = value; QuestieTracker:Update() end,
    }))
    if IsAddOnLoaded and IsAddOnLoaded("TomTom") then
        _AddControl(window, Widgets:CreateSelect(window, {
            name = "Set TomTom Target",
            description = "Mouse shortcut that points TomTom at the clicked quest's next available objective.",
            options = shortcutOptions,
            disabled = _TrackerSettingDisabled,
            get = function() return _Profile().trackerbindSetTomTom or "ctrlleft" end,
            set = function(value) _Profile().trackerbindSetTomTom = value end,
        }))
    end
    _AddControl(window, Widgets:CreateSelect(window, {
        name = "Tracker Growth",
        description = "Sets the anchored corner and growth direction. Changing it intentionally resets the tracker location.",
        options = {
            {value = "TOPLEFT", label = "Down & Right"},
            {value = "BOTTOMLEFT", label = "Up & Right"},
            {value = "TOPRIGHT", label = "Down & Left"},
            {value = "BOTTOMRIGHT", label = "Up & Left"},
        },
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerSetpoint or "TOPLEFT" end,
        set = function(value)
            _Profile().trackerSetpoint = value
            QuestieTracker:ResetLocation()
            QuestieTracker:Update()
        end,
    }))
    local function _FinishHeightRatioResize()
        TrackerBaseFrame.isSizing = false
        _Profile().trackerBackdropEnabled = _Profile().currentBackdropEnabled
        _Profile().trackerBorderEnabled = _Profile().currentBorderEnabled
        _Profile().trackerBackdropFader = _Profile().currentBackdropFader
        QuestieTracker:UpdateFormatting()
    end
    _AddControl(window, Widgets:CreateSlider(window, {
        name = "Maximum Auto Height",
        description = "Maximum tracker height as a percentage of usable screen height while automatic sizing is active.",
        min = 20,
        max = 100,
        step = 1,
        disabled = _TrackerSettingDisabled,
        get = function() return (tonumber(_Profile().trackerHeightRatio) or 0.5) * 100 end,
        set = function(value)
            _Profile().trackerHeightRatio = value / 100
            if IsMouseButtonDown("LeftButton") and (tonumber(_Profile().TrackerHeight) or 0) == 0 then
                TrackerBaseFrame.isSizing = true
                _Profile().trackerBackdropEnabled = true
                _Profile().trackerBorderEnabled = true
                _Profile().trackerBackdropFader = false
                QuestieTracker:UpdateFormatting()
            else
                _FinishHeightRatioResize()
            end
        end,
        onDragStop = _FinishHeightRatioResize,
        format = function(value) return string.format("%d%%", value) end,
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
    _AddControl(layout, Widgets:CreateToggle(layout, {
        name = "Show Header Divider",
        description = "Draws the one-pixel accent divider beneath the tracker header.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerHeaderDividerEnabled end,
        set = function(value) _Profile().trackerHeaderDividerEnabled = value; QuestieTracker:UpdateFormatting() end,
    }))
    _AddControl(layout, Widgets:CreateToggle(layout, {
        name = "Show Zone Dividers",
        description = "Draws a thin separator before each additional zone block.",
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerZoneDividersEnabled end,
        set = function(value) _Profile().trackerZoneDividersEnabled = value; QuestieTracker:Update() end,
    }))

    local spacingSpecs = {
        {"Padding Between Quests", "Gap inserted between complete quest blocks.", "trackerQuestPadding", 0, 15, 2},
        {"Gap Below Quest Title", "Gap between a quest title and its first objective.", "trackerQuestTitlePadding", 0, 12, 1},
        {"Quest Title Inset", "Left inset applied to quest titles without moving zone headers.", "trackerQuestTitleInset", 0, 24, 0},
        {"Objective Inset", "Additional left inset applied to objective lines.", "trackerObjectiveInset", 0, 32, 0},
        {"Quest Item Gutter", "Gap between tracker text and quest-item buttons.", "trackerQuestItemGutter", 0, 24, 4},
        {"Gap Before Next Zone", "Extra zone-transition gap. Negative values pull the next zone upward.", "trackerZoneSpacing", -24, 24, 0},
        {"Top Content Padding", "Space above the first tracked content block.", "trackerTopSpacing", 0, 24, 0},
        {"Bottom Content Padding", "Space below the final tracked content block.", "trackerBottomSpacing", 0, 24, 0},
    }
    local function _AddSpacingControl(spacing)
        local name, description, setting, minimum, maximum, fallback = unpack(spacing)
        _AddControl(layout, Widgets:CreateSlider(layout, {
            name = name,
            description = description,
            min = minimum,
            max = maximum,
            step = 1,
            fullWidth = false,
            disabled = _TrackerSettingDisabled,
            get = function() return _Clamp(tonumber(_Profile()[setting]) or fallback, minimum, maximum) end,
            set = function(value) _SetCustomLayoutValue(setting, value) end,
            format = function(value) return string.format("%d px", value) end,
        }))
    end
    for _, spacing in ipairs(spacingSpecs) do
        _AddSpacingControl(spacing)
    end

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
    _AddControl(surface, Widgets:CreateColor(surface, {
        name = "Zone Header Text",
        description = "Sets the text color used by zone and subzone headers.",
        disabled = _TrackerSettingDisabled,
        get = function() return _GetColor("trackerZoneHeaderColor", 1, 0, 1, 1) end,
        set = function(r, g, b) _SetColor("trackerZoneHeaderColor", r, g, b); QuestieTracker:Update() end,
    }))
    _AddControl(surface, Widgets:CreateColor(surface, {
        name = "Zone Divider",
        description = "Sets the color and opacity of optional zone separators.",
        hasAlpha = true,
        disabled = _TrackerSettingDisabled,
        get = function() return _GetColor("trackerZoneDividerColor", 0.16, 0.78, 0.72, 0.28) end,
        set = function(r, g, b, a) _SetColor("trackerZoneDividerColor", r, g, b, a); QuestieTracker:Update() end,
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

    local typography = _CreateCard(parent, "Typography", "A cached searchable font library with independent role sizes and a global override.")
    _AddControl(typography, Widgets:CreateSelect(typography, {
        name = "Global Font",
        description = "Overrides every tracker font. Choose None to use the individual role fonts below.",
        options = function() return TrackerFonts:GetOverrideValues() end,
        cacheKey = "trackerFontsWithNone",
        firstValue = TrackerFonts:GetNoneValue(),
        searchable = true,
        fontPreview = true,
        fontPath = function(value) return TrackerFonts:GetFontPathByName(value) end,
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerFontGlobalOverride or TrackerFonts:GetNoneValue() end,
        set = function(value)
            _Profile().trackerFontGlobalOverride = value
            QuestieTracker:Update()
        end,
        onChanged = function() _RefreshControls(false) end,
    }))
    _AddControl(typography, Widgets:CreateSlider(typography, {
        name = "Global Font Scale",
        description = "Multiplies every tracker font size without changing the individual size settings.",
        min = 0.5,
        max = 3,
        step = 0.05,
        disabled = _TrackerSettingDisabled,
        get = function() return tonumber(_Profile().trackerFontGlobalScale) or 1 end,
        set = function(value)
            _Profile().trackerFontGlobalScale = value
            QuestieTracker:Update()
        end,
        format = function(value) return string.format("%.2fx", value) end,
    }))

    local function _RoleFontDisabled(requireHeader)
        return _TrackerSettingDisabled()
            or (requireHeader and not _Profile().trackerHeaderEnabled)
            or TrackerFonts:IsGlobalOverrideActive()
    end

    _AddControl(typography, Widgets:CreateSelect(typography, {
        name = "Header Font",
        description = "Font used by the Questie Tracker title and tracked-quest count.",
        options = function() return TrackerFonts:GetValues() end,
        cacheKey = "trackerFonts",
        searchable = true,
        fontPreview = true,
        fontPath = function(value) return TrackerFonts:GetFontPathByName(value) end,
        fullWidth = false,
        disabled = function() return _RoleFontDisabled(true) end,
        get = function() return _Profile().trackerFontHeader or "SourceCodePro (Bold)" end,
        set = function(value) _Profile().trackerFontHeader = value; QuestieTracker:Update() end,
    }))
    _AddControl(typography, Widgets:CreateSlider(typography, {
        name = "Header Size",
        description = "Base font size for the Questie Tracker title.",
        min = 8,
        max = 26,
        step = 1,
        fullWidth = false,
        disabled = function() return _TrackerSettingDisabled() or not _Profile().trackerHeaderEnabled end,
        get = function() return tonumber(_Profile().trackerFontSizeHeader) or 12 end,
        set = function(value) _Profile().trackerFontSizeHeader = value; QuestieTracker:Update() end,
        format = function(value) return string.format("%d px", value) end,
    }))
    _AddControl(typography, Widgets:CreateSelect(typography, {
        name = "Zone Font",
        description = "Font used by zone and subzone headers.",
        options = function() return TrackerFonts:GetValues() end,
        cacheKey = "trackerFonts",
        searchable = true,
        fontPreview = true,
        fontPath = function(value) return TrackerFonts:GetFontPathByName(value) end,
        fullWidth = false,
        disabled = function() return _RoleFontDisabled(false) end,
        get = function() return _Profile().trackerFontZone or "SourceCodePro (Bold)" end,
        set = function(value) _Profile().trackerFontZone = value; QuestieTracker:Update() end,
    }))
    _AddControl(typography, Widgets:CreateSlider(typography, {
        name = "Zone Size",
        description = "Base font size for zone and subzone headers.",
        min = 8,
        max = 26,
        step = 1,
        fullWidth = false,
        disabled = _TrackerSettingDisabled,
        get = function() return tonumber(_Profile().trackerFontSizeZone) or 12 end,
        set = function(value) _Profile().trackerFontSizeZone = value; QuestieTracker:Update() end,
        format = function(value) return string.format("%d px", value) end,
    }))
    _AddControl(typography, Widgets:CreateSelect(typography, {
        name = "Quest Title Font",
        description = "Font used by tracked quest titles.",
        options = function() return TrackerFonts:GetValues() end,
        cacheKey = "trackerFonts",
        searchable = true,
        fontPreview = true,
        fontPath = function(value) return TrackerFonts:GetFontPathByName(value) end,
        fullWidth = false,
        disabled = function() return _RoleFontDisabled(false) end,
        get = function() return _Profile().trackerFontQuest or "SourceCodePro (Bold)" end,
        set = function(value) _Profile().trackerFontQuest = value; QuestieTracker:Update() end,
    }))
    _AddControl(typography, Widgets:CreateSlider(typography, {
        name = "Quest Title Size",
        description = "Base font size for quest titles. Objective size is kept at or below this value.",
        min = 8,
        max = 26,
        step = 1,
        fullWidth = false,
        disabled = _TrackerSettingDisabled,
        get = function() return tonumber(_Profile().trackerFontSizeQuest) or 12 end,
        set = function(value)
            _Profile().trackerFontSizeQuest = value
            if (tonumber(_Profile().trackerFontSizeObjective) or 12) > value then
                _Profile().trackerFontSizeObjective = value
            end
            QuestieTracker:Update()
        end,
        format = function(value) return string.format("%d px", value) end,
    }))
    _AddControl(typography, Widgets:CreateSelect(typography, {
        name = "Objective Font",
        description = "Font used by quest objectives and completion text.",
        options = function() return TrackerFonts:GetValues() end,
        cacheKey = "trackerFonts",
        searchable = true,
        fontPreview = true,
        fontPath = function(value) return TrackerFonts:GetFontPathByName(value) end,
        fullWidth = false,
        disabled = function() return _RoleFontDisabled(false) end,
        get = function() return _Profile().trackerFontObjective or "SourceCodePro (Bold)" end,
        set = function(value) _Profile().trackerFontObjective = value; QuestieTracker:Update() end,
    }))
    _AddControl(typography, Widgets:CreateSlider(typography, {
        name = "Objective Size",
        description = "Base font size for objectives, capped at the current quest-title size.",
        min = 8,
        max = 26,
        step = 1,
        fullWidth = false,
        disabled = _TrackerSettingDisabled,
        get = function() return tonumber(_Profile().trackerFontSizeObjective) or 12 end,
        set = function(value)
            _Profile().trackerFontSizeObjective = min(value, tonumber(_Profile().trackerFontSizeQuest) or 12)
            QuestieTracker:Update()
        end,
        format = function(value) return string.format("%d px", value) end,
    }))
    _AddControl(typography, Widgets:CreateSelect(typography, {
        name = "Font Outline",
        description = "Outline style applied to tracker text.",
        options = {
            {value = "", label = "None"},
            {value = "OUTLINE", label = "Outline"},
            {value = "MONOCHROME", label = "Monochrome"},
        },
        disabled = _TrackerSettingDisabled,
        get = function() return _Profile().trackerFontOutline or "OUTLINE" end,
        set = function(value) _Profile().trackerFontOutline = value; QuestieTracker:Update() end,
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
    local trailingGap = 0
    local visibleCards = 0
    local innerWidth = max(1, contentWidth - (CARD_GUTTER * 2))
    local useColumns = innerWidth >= 500
    local columnWidth = useColumns and floor((innerWidth - CONTROL_COLUMN_GAP) / 2) or innerWidth

    local function _SizeControl(control, width)
        if control.Layout then
            control:Layout(width)
        else
            control:SetWidth(width)
        end
        local height = control.qcLayoutHeight or control:GetHeight() or 30
        control:SetHeight(height)
        return height
    end

    local function _AnchorControl(control, card, x, controlY)
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", card, "TOPLEFT", x, -controlY)
        control:Show()
    end

    scroll:SetContentWidth(contentWidth)
    for _, card in ipairs(private.cards) do
        local groupMatch = query == "" or string.find(card.qcSearchText, query, 1, true)
        local controls = {}
        for _, control in ipairs(card.controls) do
            local visible = groupMatch or string.find(control.qcSearchText or "", query, 1, true)
            if visible then
                controls[#controls + 1] = control
            else
                control:Hide()
            end
        end

        if #controls > 0 then
            local controlY = CARD_HEADER_HEIGHT
            local pendingHalf
            local collapsed = card.qcCollapsed and query == ""
            if collapsed then
                for _, control in ipairs(controls) do
                    control:Hide()
                end
            else
                for _, control in ipairs(controls) do
                    local canUseHalf = useColumns
                        and not control.qcFullWidth
                        and (tonumber(control.qcMinimumWidth) or 0) <= columnWidth

                    if canUseHalf then
                        if pendingHalf then
                            local firstHeight = _SizeControl(pendingHalf, columnWidth)
                            local secondHeight = _SizeControl(control, columnWidth)
                            _AnchorControl(pendingHalf, card, CARD_GUTTER, controlY)
                            _AnchorControl(control, card, CARD_GUTTER + columnWidth + CONTROL_COLUMN_GAP, controlY)
                            controlY = controlY + max(firstHeight, secondHeight) + CONTROL_ROW_GAP
                            pendingHalf = nil
                        else
                            pendingHalf = control
                        end
                    else
                        if pendingHalf then
                            local pendingHeight = _SizeControl(pendingHalf, columnWidth)
                            _AnchorControl(pendingHalf, card, CARD_GUTTER, controlY)
                            controlY = controlY + pendingHeight + CONTROL_ROW_GAP
                            pendingHalf = nil
                        end
                        local height = _SizeControl(control, innerWidth)
                        _AnchorControl(control, card, CARD_GUTTER, controlY)
                        controlY = controlY + height + CONTROL_ROW_GAP
                    end
                end
            end

            if pendingHalf and not collapsed then
                local pendingHeight = _SizeControl(pendingHalf, columnWidth)
                _AnchorControl(pendingHalf, card, CARD_GUTTER, controlY)
                controlY = controlY + pendingHeight + CONTROL_ROW_GAP
            end

            card:SetWidth(contentWidth)
            card:SetHeight(collapsed and CARD_HEADER_HEIGHT or (controlY + 5 - CONTROL_ROW_GAP))
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y)
            card:Show()
            trailingGap = collapsed and 2 or CARD_GAP
            y = y + card:GetHeight() + trailingGap
            visibleCards = visibleCards + 1
        else
            card:Hide()
        end
    end

    Widgets:SetShown(frame.noResults, visibleCards == 0)
    if visibleCards == 0 then
        frame.noResults:ClearAllPoints()
        frame.noResults:SetPoint("TOP", scroll.content, "TOP", 0, -28)
        y = 80
    end
    scroll:SetContentHeight(max(scroll.viewport:GetHeight() + 1, y > 0 and y - trailingGap or 1))
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

    local frameWidth = frame:GetWidth()
    local showMeta = frameWidth >= 820
    Widgets:SetShown(frame.meta, showMeta)

    local searchWidth = _Clamp(floor(frameWidth * 0.34), 200, 250)
    frame.search:SetWidth(searchWidth)
    frame.search:ClearAllPoints()
    frame.search:SetPoint("RIGHT", showMeta and frame.meta or frame.close, "LEFT", -8, 0)

    local navWidth = frame.nav:GetWidth()
    local navGap = 4
    local navButtonWidth = (navWidth - ((#frame.navButtons - 1) * navGap)) / #frame.navButtons
    for index, button in ipairs(frame.navButtons) do
        button:ClearAllPoints()
        button:SetWidth(navButtonWidth)
        if index == 1 then
            button:SetPoint("TOPLEFT", frame.nav, "TOPLEFT", 0, 0)
        else
            button:SetPoint("LEFT", frame.navButtons[index - 1], "RIGHT", navGap, 0)
        end
    end

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
    Widgets:ApplyBackdrop(frame, _Theme().windowBg, _Theme().borderSoft, 1)
    _RestoreGeometry(frame)
    private.frame = frame

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", OUTER_GUTTER, -7)
    frame.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -OUTER_GUTTER, -7)
    frame.header:SetHeight(42)
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

    frame.title = Widgets:CreateFont(frame.header, 16, _Theme().textBright, "title")
    frame.title:SetPoint("LEFT", frame.header, "LEFT", 10, 1)
    frame.title:SetText("Questie Settings")
    frame.titleAccent = Widgets:CreateSolid(frame.header, "ARTWORK", _Theme().accent)
    frame.titleAccent:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -2)
    frame.titleAccent:SetSize(frame.title:GetStringWidth(), 2)

    frame.close = CreateFrame("Button", nil, frame.header)
    frame.close:SetSize(26, 26)
    frame.close:SetPoint("RIGHT", frame.header, "RIGHT", -3, 0)
    frame.close:RegisterForClicks("LeftButtonUp")
    frame.close.label = Widgets:CreateFont(frame.close, 15, _Theme().textMuted, "title")
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
    frame.meta:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)
    frame.meta:SetWidth(190)
    frame.meta:SetJustifyH("RIGHT")

    frame.search = _CreateSearchBox(frame.header)

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", frame.header, "BOTTOMLEFT", 0, -6)
    frame.body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -OUTER_GUTTER, OUTER_GUTTER)

    frame.nav = CreateFrame("Frame", nil, frame.body)
    frame.nav:SetPoint("TOPLEFT", frame.body, "TOPLEFT", 0, 0)
    frame.nav:SetPoint("TOPRIGHT", frame.body, "TOPRIGHT", 0, 0)
    frame.nav:SetHeight(28)

    frame.navActive = _CreateNavButton(frame.nav, "Tracker", "Tracker layout, surface, scale, and quest-band presentation.", true, true)

    frame.navButtons = {frame.navActive}
    local future = {
        {"Map & Icons", "Planned next: world map, minimap, objective, and quest-note presentation."},
        {"Automation", "Planned next: quest interaction, tracking, and vendor automation."},
        {"Profiles", "Planned next: profile switching, import, export, and sharing."},
    }
    for _, info in ipairs(future) do
        local button = _CreateNavButton(frame.nav, info[1], info[2], false, false)
        frame.navButtons[#frame.navButtons + 1] = button
    end

    frame.page = CreateFrame("Frame", nil, frame.body)
    frame.page:SetPoint("TOPLEFT", frame.nav, "BOTTOMLEFT", 0, -5)
    frame.page:SetPoint("BOTTOMRIGHT", frame.body, "BOTTOMRIGHT", 0, 0)
    Widgets:ApplyBackdrop(frame.page, _Theme().panelBg, {0, 0, 0, 0}, 1)

    frame.scroll = Widgets:CreateScrollArea(frame.page)
    frame.scroll:SetPoint("TOPLEFT", frame.page, "TOPLEFT", 8, -6)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame.page, "BOTTOMRIGHT", -6, 12)
    frame.noResults = Widgets:CreateFont(frame.scroll.content, 12, _Theme().textSoft)
    frame.noResults:SetText("No tracker settings match your search.")
    frame.noResults:Hide()

    _CreateTrackerWorkspace(frame.scroll.content)

    frame.sizer = CreateFrame("Button", nil, frame)
    frame.sizer:SetSize(18, 18)
    frame.sizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    frame.sizer:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    frame.sizer.lines = {}
    for index = 1, 3 do
        local line = Widgets:CreateSolid(frame.sizer, "ARTWORK", _Theme().textSoft)
        line:SetSize(3 + (index * 2), 1)
        line:SetPoint("BOTTOMRIGHT", frame.sizer, "BOTTOMRIGHT", -2, 2 + ((index - 1) * 3))
        line:SetAlpha(0.38)
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
        Widgets:ClosePopups()
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

function QuestieConfigNext:Refresh()
    if not private.built then
        return
    end
    _ApplyShellTheme()
    _RefreshStatus()
    _RefreshControls(false)
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

if C_Timer and C_Timer.After then
    local warmupAttempts = 0
    local function _WarmConfigNext()
        warmupAttempts = warmupAttempts + 1
        if QuestieConfigNext:Prime() or warmupAttempts >= 8 then
            return
        end
        C_Timer.After(1, _WarmConfigNext)
    end
    C_Timer.After(2, _WarmConfigNext)
end
