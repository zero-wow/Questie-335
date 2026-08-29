---@class TrackerHeaderFrame
local TrackerHeaderFrame = QuestieLoader:CreateModule("TrackerHeaderFrame")
-------------------------
--Import QuestieTracker modules.
-------------------------
---@type QuestieTracker
local QuestieTracker = QuestieLoader:ImportModule("QuestieTracker")
---@type TrackerBaseFrame
local TrackerBaseFrame = QuestieLoader:ImportModule("TrackerBaseFrame")
---@type TrackerFadeTicker
local TrackerFadeTicker = QuestieLoader:ImportModule("TrackerFadeTicker")
---@type TrackerUtils
local TrackerUtils = QuestieLoader:ImportModule("TrackerUtils")
---@type TrackerFonts
local TrackerFonts = QuestieLoader:ImportModule("TrackerFonts")
-------------------------
--Import Questie modules.
-------------------------
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")
---@type QuestieOptions
local QuestieOptions = QuestieLoader:ImportModule("QuestieOptions")
---@type QuestieJourney
local QuestieJourney = QuestieLoader:ImportModule("QuestieJourney")
---@type QuestieCombatQueue
local QuestieCombatQueue = QuestieLoader:ImportModule("QuestieCombatQueue")
---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

--- COMPATIBILITY ---
local QuestieCompat = QuestieCompat
local C_QuestLog = QuestieCompat.C_QuestLog

local BAR_BG_ALPHA = 0.5
local ICON_SPACING = 2
local ACTIVE_ICON_COLOR = { 0.2, 1, 0.8 }
local INACTIVE_ICON_COLOR = { 1, 1, 1 }
local PRESSED_ICON_COLOR = { 1, 0.6, 0 }

-- pfBar layout tuning (align to tracker backdrop insets: left/right = 4 in TrackerBaseFrame)
local BAR_BACKDROP_INSET = 4
local BAR_WIDTH_OFFSET = -(BAR_BACKDROP_INSET * 2)
local BAR_POS_X = BAR_BACKDROP_INSET
local BAR_POS_Y = -4
local BAR_ICON_Y_OFFSET = -2.5
local BAR_LABEL_Y_OFFSET = -9.5
local BAR_QUESTIE_ICON_Y_OFFSET = BAR_LABEL_Y_OFFSET - -6.5
local BAR_LABEL_X = 6
local BAR_LABEL_GAP = 2
local BAR_ICON_X_OFFSET = -2
local TITLE_BUTTON_GAP = 8
local MIN_TITLE_DISPLAY_WIDTH = 1
local MIN_HEADER_TITLE_WIDTH = 52

local FILTER_BUTTONS = {
    { mode = "quests", icon = "tracker_quests", tooltip = "Show Quests" },
    { mode = "achievements", icon = "tracker_achievements", tooltip = "Show Achievements" },
}

local headerFrame, trackerBaseFrame, filterButtons, panelHeight

local function GetProfileColor(setting, defaultR, defaultG, defaultB, defaultA)
    local color = Questie.db.profile[setting]
    if type(color) ~= "table" then
        return defaultR, defaultG, defaultB, defaultA
    end

    return tonumber(color[1]) or defaultR,
        tonumber(color[2]) or defaultG,
        tonumber(color[3]) or defaultB,
        tonumber(color[4]) or defaultA
end

local function GetColorCode(setting, defaultR, defaultG, defaultB)
    local r, g, b = GetProfileColor(setting, defaultR, defaultG, defaultB)
    return string.format(
        "|cff%02x%02x%02x",
        math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5)
    )
end

local function GetPanelHeight()
    return math.max(16, TrackerFonts:GetHeaderFontSize())
end

local function GetButtonSize()
    return GetPanelHeight() - 2
end

local function GetFilterButtonsWidth()
    local buttonSize = GetButtonSize()
    return (#FILTER_BUTTONS * buttonSize) + ((#FILTER_BUTTONS - 1) * ICON_SPACING)
end

local function GetTitleTextStartX()
    return BAR_LABEL_X + GetButtonSize() + BAR_LABEL_GAP
end

local function GetTitleAvailableWidth()
    if not headerFrame then
        return MIN_TITLE_DISPLAY_WIDTH
    end

    local reservedRightWidth = GetFilterButtonsWidth() + math.abs(BAR_ICON_X_OFFSET) + TITLE_BUTTON_GAP
    return math.max(MIN_TITLE_DISPLAY_WIDTH, (headerFrame:GetWidth() or 0) - GetTitleTextStartX() - reservedRightWidth)
end

local function GetFullTitleText(viewMode)
    local viewMode = Questie.db.char.trackerViewMode or "quests"
    local suffix = Questie.db.char.isTrackerExpanded and "" or " +"

    if viewMode == "achievements" then
        return "Achievement Tracker: " .. tostring(GetNumTrackedAchievements(true)) .. "/10" .. suffix
    end

    local _, activeQuests = GetNumQuestLogEntries()
    return l10n("Questie Tracker") .. ": " .. tostring(activeQuests) .. "/" .. C_QuestLog.GetMaxNumQuestsCanAccept() .. suffix
end

local function GetTitleCandidates(viewMode)
    local suffix = Questie.db.char.isTrackerExpanded and "" or " +"

    if viewMode == "achievements" then
        local countText = tostring(GetNumTrackedAchievements(true)) .. "/10" .. suffix
        return {
            GetFullTitleText(viewMode),
            "Achievements: " .. countText,
            "Achv: " .. countText,
            countText,
        }
    end

    local _, activeQuests = GetNumQuestLogEntries()
    local countText = tostring(activeQuests) .. "/" .. C_QuestLog.GetMaxNumQuestsCanAccept() .. suffix
    return {
        GetFullTitleText(viewMode),
        "Quests: " .. countText,
        "Q: " .. countText,
        countText,
    }
end

local function GetFittedTitleText(viewMode, availableWidth)
    if not headerFrame or not headerFrame.titleLabel then
        return GetFullTitleText(viewMode)
    end

    local width = math.max(MIN_TITLE_DISPLAY_WIDTH, availableWidth or MIN_TITLE_DISPLAY_WIDTH)
    local titleLabel = headerFrame.titleLabel

    titleLabel:SetWidth(width)

    for _, candidate in ipairs(GetTitleCandidates(viewMode)) do
        titleLabel:SetText(candidate)
        if titleLabel:GetUnboundedStringWidth() <= width then
            return candidate
        end
    end

    return GetTitleCandidates(viewMode)[#GetTitleCandidates(viewMode)]
end

local function SetFilterButtonColor(button, r, g, b)
    if button and button.icon then
        button.icon:SetVertexColor(r, g, b)
    end
end

local function RefreshFilterButtonColors()
    local activeMode = Questie.db.char.trackerViewMode or "quests"

    for _, button in ipairs(filterButtons) do
        if button.mode == activeMode then
            SetFilterButtonColor(button, ACTIVE_ICON_COLOR[1], ACTIVE_ICON_COLOR[2], ACTIVE_ICON_COLOR[3])
        else
            SetFilterButtonColor(button, INACTIVE_ICON_COLOR[1], INACTIVE_ICON_COLOR[2], INACTIVE_ICON_COLOR[3])
        end
    end
end

local function LayoutTitle()
    if not headerFrame or not headerFrame.titleLabel then
        return
    end

    local trackerFontSizeHeader = TrackerFonts:GetHeaderFontSize()
    local viewMode = Questie.db.char.trackerViewMode or "quests"
    local iconSize = GetButtonSize()
    local textStartX = GetTitleTextStartX()
    local titleWidth = GetTitleAvailableWidth()
    local titleText = GetFittedTitleText(viewMode, titleWidth)

    headerFrame.titleLabel:SetFont(TrackerFonts:GetHeaderFont(), trackerFontSizeHeader, Questie.db.profile.trackerFontOutline)
    headerFrame.titleLabel:SetWidth(titleWidth)
    headerFrame.titleLabel:SetText(GetColorCode("trackerHeaderTextColor", 1.0, 0.82, 0.0) .. titleText .. "|r")

    headerFrame.titleLabel:ClearAllPoints()
    headerFrame.titleLabel:SetPoint("LEFT", headerFrame, "TOPLEFT", textStartX, BAR_LABEL_Y_OFFSET)

    if headerFrame.questieIcon then
        headerFrame.questieIcon:SetSize(iconSize, iconSize)
        headerFrame.questieIcon:ClearAllPoints()
        headerFrame.questieIcon:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", BAR_LABEL_X, BAR_QUESTIE_ICON_Y_OFFSET)
        headerFrame.questieIcon.texture:SetTexture(Questie.icons["tracker_settings"])
        headerFrame.questieIcon.texture:SetVertexColor(1, 1, 1)
        headerFrame.questieIcon:Show()
    end

    if headerFrame.trackedQuests and filterButtons[1] then
        headerFrame.trackedQuests:ClearAllPoints()
        headerFrame.trackedQuests:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", textStartX, 0)
        headerFrame.trackedQuests:SetPoint("TOPRIGHT", filterButtons[1], "TOPLEFT", -TITLE_BUTTON_GAP, 0)
        headerFrame.trackedQuests:SetHeight(panelHeight + 5)
        headerFrame.trackedQuests:Show()
    end
end

local function SetupQuestieIconButton(questieIcon)
    questieIcon.texture = questieIcon:CreateTexture(nil, "ARTWORK")
    questieIcon.texture:SetTexture(Questie.icons["tracker_settings"])
    questieIcon.texture:SetAllPoints()

    questieIcon:EnableMouse(true)
    questieIcon:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    questieIcon:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            if QuestieJourney:IsShown() then
                QuestieJourney.ToggleJourneyWindow()
            end

            QuestieCombatQueue:Queue(function()
                QuestieOptions:OpenConfigWindow()
            end)

            return
        elseif button == "RightButton" then
            if QuestieConfigFrame:IsShown() then
                QuestieConfigFrame:Hide()
            end

            QuestieCombatQueue:Queue(function()
                QuestieJourney.ToggleJourneyWindow()
            end)

            return
        end
    end)

    questieIcon:SetScript("OnEnter", function(self)
        if InCombatLockdown() then
            if GameTooltip:IsShown() then
                GameTooltip:Hide()
                return
            end
        end

        GameTooltip._owner = self
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine("Questie " .. QuestieLib:GetAddonVersionString(), 1, 1, 1)
        GameTooltip:AddLine(Questie:Colorize(l10n("Left Click") .. ": ", "gray") .. l10n("Toggle Options"))
        GameTooltip:AddLine(Questie:Colorize(l10n("Right Click") .. ": ", "gray") .. l10n("Toggle My Journey"))
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Questie:Colorize(l10n("Left Click + Hold") .. ": ", "gray") .. l10n("Drag while Unlocked"))
        GameTooltip:AddLine(Questie:Colorize(l10n("Ctrl + Left Click + Hold") .. ": ", "gray") .. l10n("Drag while Locked"))

        local VoiceOver, TomTom = TrackerUtils:IsVoiceOverLoaded(), IsAddOnLoaded("TomTom")

        if VoiceOver or TomTom then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(Questie:Colorize(l10n("Questie Tracker Integrations") .. ": ", "gray"))

            if VoiceOver then
                GameTooltip:AddLine(Questie:Colorize(l10n("VoiceOver") .. ": ", "white") .. l10n("Hold shift to see PlayButtons"))
            end

            if TomTom then
                GameTooltip:AddLine(Questie:Colorize(l10n("TomTom") .. ": ", "white") .. l10n("Ctrl + Left Click or Right Click a Quest Title"))
            end
        end

        GameTooltip:Show()
        TrackerFadeTicker.Unfade(self)
    end)

    questieIcon:SetScript("OnLeave", function(self)
        if GameTooltip:IsShown() then
            GameTooltip:Hide()
        end
        TrackerFadeTicker.Fade(self)
    end)
end

local function SetTrackerViewMode(mode)
    if Questie.db.char.trackerViewMode == mode then
        return
    end

    Questie.db.char.trackerViewMode = mode
    RefreshFilterButtonColors()
    LayoutTitle()

    QuestieCombatQueue:Queue(function()
        QuestieTracker:Update()
    end)
end

local function CreateFilterButton(parent, config)
    local buttonSize = GetButtonSize()
    local button = CreateFrame("Button", nil, parent)

    button.mode = config.mode
    button.tooltip = config.tooltip
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(Questie.icons[config.icon])

    button:SetSize(buttonSize, buttonSize)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltip, 1, 1, 1)
        GameTooltip:Show()
        if not self.isPressed then
            SetFilterButtonColor(self, ACTIVE_ICON_COLOR[1], ACTIVE_ICON_COLOR[2], ACTIVE_ICON_COLOR[3])
        end
        TrackerFadeTicker.Unfade(self)
    end)

    button:SetScript("OnLeave", function(self)
        if GameTooltip:IsShown() then
            GameTooltip:Hide()
        end
        self.isPressed = false
        RefreshFilterButtonColors()
        TrackerFadeTicker.Fade(self)
    end)

    button:SetScript("OnMouseDown", function(self)
        self.isPressed = true
        SetFilterButtonColor(self, PRESSED_ICON_COLOR[1], PRESSED_ICON_COLOR[2], PRESSED_ICON_COLOR[3])
    end)

    button:SetScript("OnMouseUp", function(self)
        self.isPressed = false
        if self.mode == (Questie.db.char.trackerViewMode or "quests") then
            SetFilterButtonColor(self, ACTIVE_ICON_COLOR[1], ACTIVE_ICON_COLOR[2], ACTIVE_ICON_COLOR[3])
        elseif MouseIsOver(self) then
            SetFilterButtonColor(self, ACTIVE_ICON_COLOR[1], ACTIVE_ICON_COLOR[2], ACTIVE_ICON_COLOR[3])
        else
            SetFilterButtonColor(self, INACTIVE_ICON_COLOR[1], INACTIVE_ICON_COLOR[2], INACTIVE_ICON_COLOR[3])
        end
    end)

    button:SetScript("OnClick", function(self)
        SetTrackerViewMode(self.mode)
    end)

    return button
end

local function LayoutFilterButtons()
    if not headerFrame or not filterButtons[1] then
        return
    end

    local buttonSize = GetButtonSize()
    local yOffset = BAR_ICON_Y_OFFSET
    local xOffset = BAR_ICON_X_OFFSET

    for index = #filterButtons, 1, -1 do
        local button = filterButtons[index]
        button:SetSize(buttonSize, buttonSize)
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", headerFrame, "TOPRIGHT", xOffset, yOffset)
        xOffset = xOffset - buttonSize - ICON_SPACING
    end
end

local function LayoutHeaderDivider()
    if not headerFrame or not headerFrame.divider then
        return
    end

    if not Questie.db.profile.trackerHeaderDividerEnabled then
        headerFrame.divider:Hide()
        return
    end

    headerFrame.divider:ClearAllPoints()
    if Questie.db.profile.moveHeaderToBottom then
        headerFrame.divider:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 0, -1)
        headerFrame.divider:SetPoint("TOPRIGHT", headerFrame, "TOPRIGHT", 0, -1)
    else
        headerFrame.divider:SetPoint("BOTTOMLEFT", headerFrame, "BOTTOMLEFT", 0, 0)
        headerFrame.divider:SetPoint("BOTTOMRIGHT", headerFrame, "BOTTOMRIGHT", 0, 0)
    end

    local accentR, accentG, accentB, accentA = GetProfileColor("trackerHeaderAccentColor", 0.16, 0.78, 0.72, 0.38)
    headerFrame.divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    headerFrame.divider:SetVertexColor(accentR, accentG, accentB, accentA)
    headerFrame.divider:Show()
end

function TrackerHeaderFrame.Initialize(baseFrame)
    trackerBaseFrame = baseFrame
    panelHeight = GetPanelHeight()

    headerFrame = CreateFrame("Button", "Questie_HeaderFrame", trackerBaseFrame)
    headerFrame:SetHeight(panelHeight + 5)

    headerFrame.bg = headerFrame:CreateTexture(nil, "BACKGROUND")
    headerFrame.bg:SetAllPoints()
    local bgR, bgG, bgB, bgA = GetProfileColor("trackerHeaderBackgroundColor", 0, 0, 0, BAR_BG_ALPHA)
    headerFrame.bg:SetTexture(bgR, bgG, bgB, bgA)

    headerFrame.divider = headerFrame:CreateTexture(nil, "BORDER")
    headerFrame.divider:SetHeight(2)
    headerFrame.divider:Hide()

    headerFrame.questieIcon = CreateFrame("Button", nil, headerFrame)
    headerFrame.questieIcon:SetFrameLevel(headerFrame:GetFrameLevel() + 2)
    SetupQuestieIconButton(headerFrame.questieIcon)

    headerFrame.titleLabel = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    headerFrame.titleLabel:SetJustifyH("LEFT")
    headerFrame.titleLabel:SetJustifyV("MIDDLE")
    headerFrame.titleLabel.GetUnboundedStringWidth = QuestieCompat.GetUnboundedStringWidth

    TrackerHeaderFrame.PositionTrackerHeaderFrame()

    headerFrame:RegisterForDrag("LeftButton")
    headerFrame:RegisterForClicks("RightButtonUp", "LeftButtonUp")
    headerFrame:SetScript("OnDragStart", TrackerBaseFrame.OnDragStart)
    headerFrame:SetScript("OnDragStop", TrackerBaseFrame.OnDragStop)
    headerFrame:SetScript("OnEnter", TrackerFadeTicker.Unfade)
    headerFrame:SetScript("OnLeave", TrackerFadeTicker.Fade)

    headerFrame:SetScript("OnClick", function(_, button)
        if InCombatLockdown() then
            return
        end

        if button == "RightButton" then
            TrackerHeaderFrame:ToggleExpanded()
            return
        end

        if button == "LeftButton" and IsShiftKeyDown() then
            TrackerHeaderFrame:ToggleExpanded()
        end
    end)

    filterButtons = {}
    for _, config in ipairs(FILTER_BUTTONS) do
        table.insert(filterButtons, CreateFilterButton(headerFrame, config))
    end
    LayoutFilterButtons()
    LayoutHeaderDivider()
    LayoutTitle()

    local trackedQuests = CreateFrame("Button", nil, headerFrame)
    trackedQuests:SetFrameLevel(headerFrame:GetFrameLevel() + 1)

    trackedQuests.SetMode = function(self, mode)
        self.mode = mode
    end

    if Questie.db.char.isTrackerExpanded then
        trackedQuests:SetMode(1)
    else
        trackedQuests:SetMode(0)
    end

    trackedQuests:EnableMouse(true)
    trackedQuests:RegisterForDrag("LeftButton")
    trackedQuests:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    trackedQuests:SetScript("OnClick", function()
        if InCombatLockdown() then
            return
        end
        TrackerHeaderFrame:ToggleExpanded()
    end)
    trackedQuests:SetScript("OnDragStart", TrackerBaseFrame.OnDragStart)
    trackedQuests:SetScript("OnDragStop", TrackerBaseFrame.OnDragStop)
    trackedQuests:SetScript("OnEnter", TrackerFadeTicker.Unfade)
    trackedQuests:SetScript("OnLeave", TrackerFadeTicker.Fade)

    trackedQuests.label = headerFrame.titleLabel

    headerFrame.trackedQuests = trackedQuests
    headerFrame.filterButtons = filterButtons

    LayoutTitle()
    headerFrame:Hide()

    TrackerHeaderFrame.headerFrame = headerFrame

    return headerFrame
end

function TrackerHeaderFrame:ToggleExpanded()
    if InCombatLockdown() then
        return
    end

    local collapseTop = TrackerBaseFrame:CaptureCollapsePosition()

    if Questie.db.char.isTrackerExpanded then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerHeaderFrame:ToggleExpanded] - Tracker Minimized")
        Questie.db.char.isTrackerExpanded = false
        headerFrame.trackedQuests:SetMode(0)
    else
        Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerHeaderFrame:ToggleExpanded] - Tracker Maximized")
        Questie.db.char.isTrackerExpanded = true
        headerFrame.trackedQuests:SetMode(1)
    end

    LayoutTitle()

    QuestieCombatQueue:Queue(function()
        QuestieTracker:Update(true)
        TrackerBaseFrame:RestoreCollapsePosition(collapseTop)
    end)
end

function TrackerHeaderFrame:GetMinWidth()
    local requiredHeaderWidth = GetTitleTextStartX() + MIN_HEADER_TITLE_WIDTH + GetFilterButtonsWidth() + math.abs(BAR_ICON_X_OFFSET) + TITLE_BUTTON_GAP
    return requiredHeaderWidth - BAR_WIDTH_OFFSET
end

function TrackerHeaderFrame:SyncWidth(width)
    if not headerFrame or not width or width < 1 then
        return
    end

    headerFrame:SetWidth(width + BAR_WIDTH_OFFSET)
    LayoutFilterButtons()
    LayoutHeaderDivider()
    LayoutTitle()
end

function TrackerHeaderFrame:Update()
    panelHeight = GetPanelHeight()

    if Questie.db.profile.trackerHeaderEnabled or (not QuestieTracker:HasQuest()) then
        headerFrame:ClearAllPoints()
        headerFrame:SetHeight(panelHeight + 5)
        local bgR, bgG, bgB, bgA = GetProfileColor("trackerHeaderBackgroundColor", 0, 0, 0, BAR_BG_ALPHA)
        headerFrame.bg:SetTexture(bgR, bgG, bgB, bgA)

        LayoutFilterButtons()
        LayoutHeaderDivider()
        RefreshFilterButtonColors()
        LayoutTitle()

        for _, button in ipairs(filterButtons) do
            button:Show()
        end

        if trackerBaseFrame and trackerBaseFrame:GetWidth() > 1 then
            TrackerHeaderFrame:SyncWidth(trackerBaseFrame:GetWidth())
        else
            local minWidth = TrackerHeaderFrame:GetMinWidth()
            headerFrame:SetWidth(minWidth + BAR_WIDTH_OFFSET)
        end

        headerFrame:Show()
        TrackerHeaderFrame.PositionTrackerHeaderFrame()
    else
        headerFrame:Hide()
    end
end

function TrackerHeaderFrame.PositionTrackerHeaderFrame()
    if not headerFrame then
        return
    end

    if Questie.db.profile.moveHeaderToBottom then
        headerFrame:SetPoint("BOTTOMLEFT", trackerBaseFrame, "BOTTOMLEFT", BAR_POS_X, 5)
    else
        if Questie.db.char.isTrackerExpanded then
            headerFrame:SetPoint("TOPLEFT", trackerBaseFrame, "TOPLEFT", BAR_POS_X, BAR_POS_Y)
        else
            headerFrame:SetPoint("BOTTOMLEFT", trackerBaseFrame, "BOTTOMLEFT", BAR_POS_X, 5)
        end
    end

    LayoutHeaderDivider()
end
