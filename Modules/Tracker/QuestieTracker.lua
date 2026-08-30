---@class QuestieTracker
local QuestieTracker = QuestieLoader:CreateModule("QuestieTracker")
-------------------------
--Import QuestieTracker modules.
-------------------------
---@type TrackerBaseFrame
local TrackerBaseFrame = QuestieLoader:ImportModule("TrackerBaseFrame")
---@type TrackerHeaderFrame
local TrackerHeaderFrame = QuestieLoader:ImportModule("TrackerHeaderFrame")
---@type TrackerQuestFrame
local TrackerQuestFrame = QuestieLoader:ImportModule("TrackerQuestFrame")
---@type TrackerLinePool
local TrackerLinePool = QuestieLoader:ImportModule("TrackerLinePool")
---@type TrackerFadeTicker
local TrackerFadeTicker = QuestieLoader:ImportModule("TrackerFadeTicker")
---@type TrackerQuestTimers
local TrackerQuestTimers = QuestieLoader:ImportModule("TrackerQuestTimers")
---@type TrackerUtils
local TrackerUtils = QuestieLoader:ImportModule("TrackerUtils")
---@type TrackerFonts
local TrackerFonts = QuestieLoader:ImportModule("TrackerFonts")
-------------------------
--Import Questie modules.
-------------------------
---@type QuestieQuest
local QuestieQuest = QuestieLoader:ImportModule("QuestieQuest")
---@type QuestieMap
local QuestieMap = QuestieLoader:ImportModule("QuestieMap")
---@type QuestieTooltips
local QuestieTooltips = QuestieLoader:ImportModule("QuestieTooltips")
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")
---@type QuestiePlayer
local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
---@type QuestieAuto
local QuestieAuto = QuestieLoader:ImportModule("QuestieAuto")
local _QuestieAuto = QuestieAuto.private
---@type QuestieCombatQueue
local QuestieCombatQueue = QuestieLoader:ImportModule("QuestieCombatQueue")
---@type QuestEventHandler
local QuestEventHandler = QuestieLoader:ImportModule("QuestEventHandler")
local _QuestEventHandler = QuestEventHandler.private
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")
---@type QuestieDebugOffer
local QuestieDebugOffer = QuestieLoader:ImportModule("QuestieDebugOffer")

--- COMPATIBILITY ---
local C_Timer = QuestieCompat.C_Timer
local NativeC_QuestLog = _G.C_QuestLog
local C_QuestLog = QuestieCompat.C_QuestLog or NativeC_QuestLog
local GetQuestLogTitle = QuestieCompat.GetQuestLogTitle
local GetQuestLogIndexByID = QuestieCompat.GetQuestLogIndexByID
local GetItemInfo = QuestieCompat.GetItemInfo

-- Local Vars
local trackerLineWidth = 0
local trackerMinLineWidth = 260
local trackerMarginRight = 30
local trackerMarginLeft = 2
local TRACKER_CONTENT_VERTICAL_PADDING = 8
local lastAQW = GetTime()
local lastTrackerUpdate = GetTime()
local lastAchieveId = GetTime()
local durabilityInitialPosition = { DurabilityFrame:GetPoint() }

local voiceOverInitialPosition
if VoiceOverFrame then
    voiceOverInitialPosition = { VoiceOverFrame:GetPoint() }
end

local questsWatched = GetNumQuestWatches()

local trackedAchievements
local trackedAchievementIds

if Questie.IsWotlk or QuestieCompat.Is335 then
    trackedAchievements = { GetTrackedAchievements() }
    trackedAchievementIds = {}
end

local isFirstRun = true
local allowFormattingUpdate = false
local trackerBaseFrame, trackerHeaderFrame, trackerQuestFrame
local QuestLogFrame = QuestLogExFrame or ClassicQuestLog or QuestLogFrame

local LFG_MIRROR_ZONE_KEY = "__QuestieLFGObjectives"
local LFG_MIRROR_MAX_ROWS = 40
local LFG_MIRROR_QUEST = { Id = -335001, name = "LFG Objectives" }
local lfgMirrorSnapshot
local lfgMirrorRefreshScheduled = false
local lfgNativeFrame
local lfgRenderedLines = {}
local _RequestLFGObjectiveMirrorRefresh

local AUTO_QUEST_NOTICE_RETRY_DELAY = 0.25
local AUTO_QUEST_NOTICE_MAX_RETRIES = 4
local AUTO_QUEST_NOTICE_ANIMATION_TIME = 0.24
local AUTO_QUEST_DISCOVERY_DELAYS = {0, 0.05, 0.15, 0.35, 0.75, 1.5, 3}
local autoQuestOffers = {}
local autoQuestOfferOrder = {}
local autoQuestRenderedLines = {}
local autoQuestRefreshScheduled = false
local autoQuestSuppressionScanNeeded = false
local autoQuestSuppressedFrames = {}
local autoQuestSuppressedFrameSet = {}
local autoQuestEventFrame
local autoQuestGlobalHookInstalled = false
local autoQuestRemoveHookInstalled = false
local autoQuestDialogueHookInstalled = false
local autoQuestDialogueHookRetries = 0
local autoQuestDiscoveryGeneration = 0
local autoQuestWatchFrameUpdateHookInstalled = false
local autoQuestOpeningQuestId
local autoQuestOpeningShouldAccept = false
local autoQuestOpeningAutomatic = false
local autoQuestAcceptButtonCounter = 0
local autoQuestNativeSuppressionSuspended = false
local autoQuestNativeWatchFrameHooked
local autoQuestNativeWatchFrameSuppressed = false
local autoQuestNativeWatchFrameWasShown = false
local _RequestAutoQuestNoticeRefresh
local _RestoreNativeAutoQuestDefaults
local _EnsureAutoQuestNativeHook
local _SuppressNativeAutoQuestDefaults
local _ScheduleNextAutoQuestAutoAccept
local _HandlePresentedAutoQuestDetail

local function _TrimLFGMirrorText(value)
    value = tostring(value or "")
    value = string.gsub(value, "\r\n", "\n")
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    return value
end

local function _StripLFGMirrorFormatting(value)
    value = _TrimLFGMirrorText(value)
    value = string.gsub(value, "|T.-|t", "")
    value = string.gsub(value, "|c%x%x%x%x%x%x%x%x", "")
    value = string.gsub(value, "|r", "")
    return _TrimLFGMirrorText(value)
end

local function _ColorByte(value)
    value = math.max(0, math.min(1, tonumber(value) or 1))
    return math.floor((value * 255) + 0.5)
end

local function _ColorizeLFGMirrorText(text, red, green, blue)
    if string.find(text, "|c%x%x%x%x%x%x%x%x") then
        return text
    end

    return string.format("|cff%02x%02x%02x%s|r", _ColorByte(red), _ColorByte(green), _ColorByte(blue), text)
end

local function _GetLFGProfileColor(key, defaultRed, defaultGreen, defaultBlue, defaultAlpha)
    local profile = Questie and Questie.db and Questie.db.profile
    local color = profile and profile[key]

    return tonumber(color and color[1]) or defaultRed,
        tonumber(color and color[2]) or defaultGreen,
        tonumber(color and color[3]) or defaultBlue,
        tonumber(color and color[4]) or defaultAlpha
end

local function _GetLFGDisplayTitle(snapshot)
    local dungeonName = _StripLFGMirrorFormatting(snapshot and snapshot.title)
    if dungeonName == "" then
        return l10n("Dungeon Objectives")
    end

    if string.find(string.lower(dungeonName), "dungeon", 1, true) then
        return dungeonName
    end

    return "Dungeon: " .. dungeonName
end

local function _FormatLFGObjectiveRow(row)
    local text = _StripLFGMirrorFormatting(row and row.plainText)
    local lowerText = string.lower(text)
    local current, required = string.match(text, "(%d+)%s*/%s*(%d+)")
    current = tonumber(current)
    required = tonumber(required)

    local isFailed = row and row.failedHint
        or string.find(lowerText, "failed", 1, true)
        or string.find(lowerText, "failure", 1, true)
    local isComplete = row and row.completeHint
        or (current and required and required > 0 and current >= required)
        or (not string.find(lowerText, "incomplete", 1, true) and string.find(lowerText, "complete", 1, true))

    if isFailed then
        return _ColorizeLFGMirrorText(text, 1, 0.18, 0.18)
    elseif isComplete then
        return _ColorizeLFGMirrorText(text, 0.2, 1, 0.35)
    elseif current and required and required > 0 then
        return QuestieLib:GetPfQuestProgressColorHex(current, required) .. text .. "|r"
    end

    return _ColorizeLFGMirrorText(text, 0.92, 0.92, 0.92)
end

local function _CollectLFGFontStrings(frame, output, visited, depth)
    if not frame or visited[frame] or depth > 16 then
        return
    end
    visited[frame] = true

    local regions = {frame:GetRegions()}
    for _, region in ipairs(regions) do
        if region
            and region.GetObjectType
            and region:GetObjectType() == "FontString"
            and (not region.IsShown or region:IsShown())
        then
            local text = _TrimLFGMirrorText(region:GetText())
            local alpha = region.GetAlpha and tonumber(region:GetAlpha()) or 1
            if text ~= "" and alpha > 0.01 then
                local red, green, blue, textAlpha = 1, 1, 1, 1
                if region.GetTextColor then
                    red, green, blue, textAlpha = region:GetTextColor()
                end
                textAlpha = tonumber(textAlpha) or 1

                if textAlpha > 0.01 then
                    output[#output + 1] = {
                        plainText = text,
                        red = tonumber(red) or 1,
                        green = tonumber(green) or 1,
                        blue = tonumber(blue) or 1,
                        top = tonumber(region:GetTop()) or 0,
                        left = tonumber(region:GetLeft()) or 0,
                        height = math.max(1, tonumber(region:GetHeight()) or 1),
                    }
                end
            end
        end
    end

    local children = {frame:GetChildren()}
    for _, child in ipairs(children) do
        if child and (not child.IsShown or child:IsShown()) then
            _CollectLFGFontStrings(child, output, visited, depth + 1)
        end
    end
end

local function _BuildLFGMirrorSnapshot(frame)
    local labels = {}
    _CollectLFGFontStrings(frame, labels, {}, 0)
    if #labels == 0 then
        return nil
    end

    table.sort(labels, function(left, right)
        if math.abs(left.top - right.top) <= 0.5 then
            return left.left < right.left
        end
        return left.top > right.top
    end)

    local groups = {}
    for _, label in ipairs(labels) do
        local group = groups[#groups]
        local tolerance = group and math.max(3, math.min(group.height, label.height) * 0.45) or 0
        if group and math.abs(group.top - label.top) <= tolerance then
            group.parts[#group.parts + 1] = label
            group.height = math.max(group.height, label.height)
        else
            groups[#groups + 1] = {
                top = label.top,
                height = label.height,
                parts = {label},
            }
        end
    end

    local logicalRows = {}
    for _, group in ipairs(groups) do
        table.sort(group.parts, function(left, right)
            return left.left < right.left
        end)

        local plainParts = {}
        local completeHint = false
        local failedHint = false
        local previousText
        local previousLeft
        for _, part in ipairs(group.parts) do
            local duplicate = previousText == part.plainText
                and previousLeft
                and math.abs(previousLeft - part.left) <= 2
            if not duplicate then
                plainParts[#plainParts + 1] = part.plainText
                if part.green >= part.red + 0.15 and part.green >= part.blue + 0.05 then
                    completeHint = true
                elseif part.red >= part.green + 0.2 and part.red >= part.blue + 0.1 then
                    failedHint = true
                end
                previousText = part.plainText
                previousLeft = part.left
            end
        end

        local plainText = _TrimLFGMirrorText(table.concat(plainParts, " "))
        if plainText ~= "" then
            logicalRows[#logicalRows + 1] = {
                plainText = plainText,
                completeHint = completeHint,
                failedHint = failedHint,
            }
        end
        if #logicalRows >= LFG_MIRROR_MAX_ROWS then
            break
        end
    end

    if #logicalRows == 0 then
        return nil
    end

    local titleRow = table.remove(logicalRows, 1)
    local signatureParts = {titleRow.plainText}
    for _, row in ipairs(logicalRows) do
        signatureParts[#signatureParts + 1] = row.plainText
    end

    return {
        title = titleRow.plainText,
        rows = logicalRows,
        signature = table.concat(signatureParts, "\031"),
    }
end

local function _RefreshRenderedLFGSnapshot(snapshot)
    if not snapshot or #lfgRenderedLines == 0 then
        return false
    end

    local rows = snapshot.rows or {}
    local isCollapsed = Questie.db.char.collapsedZones[LFG_MIRROR_ZONE_KEY]
    local requiredLines = isCollapsed and 1 or (#rows + 1)
    if #lfgRenderedLines ~= requiredLines then
        return false
    end

    for _, line in ipairs(lfgRenderedLines) do
        if not line or not line.isLFGSectionLine or not line.label then
            return false
        end
    end

    local displayTitle = _GetLFGDisplayTitle(snapshot)

    local red, green, blue = _GetLFGProfileColor("trackerHeaderTextColor", 1, 0.82, 0, 1)
    if isCollapsed then
        displayTitle = displayTitle .. " +"
    end
    lfgRenderedLines[1].label:SetText(_ColorizeLFGMirrorText(displayTitle, red, green, blue))

    if not isCollapsed then
        for index, row in ipairs(rows) do
            lfgRenderedLines[index + 1].label:SetText(_FormatLFGObjectiveRow(row))
        end
    end

    return true
end

local function _CollectLFGFrames(frame, output, visited, depth)
    if not frame or visited[frame] or depth > 16 then
        return
    end
    visited[frame] = true
    output[#output + 1] = frame

    if not frame.GetChildren then
        return
    end

    local children = {frame:GetChildren()}
    for _, child in ipairs(children) do
        _CollectLFGFrames(child, output, visited, depth + 1)
    end
end

local function _RestoreNativeLFGTracker(frame)
    frame = frame or lfgNativeFrame
    if not frame or not frame.__Questie335LFGSuppressed then
        return
    end

    if frame.SetAlpha then
        pcall(frame.SetAlpha, frame, tonumber(frame.__Questie335LFGOriginalAlpha) or 1)
    end

    local mouseState = frame.__Questie335LFGMouseState
    if mouseState then
        for _, target in ipairs(mouseState.order) do
            local originalState = mouseState.original[target]
            if target and target.EnableMouse and originalState ~= nil then
                pcall(target.EnableMouse, target, originalState == 1)
            end
        end
    end

    frame.__Questie335LFGSuppressed = nil
    frame.__Questie335LFGOriginalAlpha = nil
    frame.__Questie335LFGMouseState = nil
end

local function _SuppressNativeLFGTracker(frame)
    if not frame then
        return false
    end

    if InCombatLockdown() and frame.__Questie335LFGSuppressed then
        return true
    end

    if InCombatLockdown() and frame.IsProtected then
        local ok, isProtected = pcall(frame.IsProtected, frame)
        if ok and isProtected then
            return false
        end
    end

    local newlySuppressed = not frame.__Questie335LFGSuppressed
    if not frame.__Questie335LFGSuppressed then
        frame.__Questie335LFGOriginalAlpha = frame.GetAlpha and frame:GetAlpha() or 1
        frame.__Questie335LFGMouseState = {
            order = {},
            original = {},
        }
        frame.__Questie335LFGSuppressed = true
    end

    if frame.SetAlpha then
        local ok = pcall(frame.SetAlpha, frame, 0)
        if not ok then
            if newlySuppressed then
                frame.__Questie335LFGSuppressed = nil
                frame.__Questie335LFGOriginalAlpha = nil
                frame.__Questie335LFGMouseState = nil
            end
            return false
        end
    end

    -- Mouse-state changes are unnecessary for a frame already suppressed before combat,
    -- and avoiding them keeps this path clear of protected child controls.
    if InCombatLockdown() then
        return true
    end

    local mouseState = frame.__Questie335LFGMouseState
    local frames = {}
    _CollectLFGFrames(frame, frames, {}, 0)
    for _, target in ipairs(frames) do
        if target.EnableMouse and target.IsMouseEnabled then
            if mouseState.original[target] == nil then
                local ok, enabled = pcall(target.IsMouseEnabled, target)
                if ok then
                    mouseState.original[target] = enabled and 1 or 0
                    mouseState.order[#mouseState.order + 1] = target
                end
            end
            if mouseState.original[target] ~= nil then
                pcall(target.EnableMouse, target, false)
            end
        end
    end

    return true
end

local function _GetNativeLFGTracker()
    local frame = _G and _G.LFGObjectiveTracker
    if frame and (not frame.GetRegions or not frame.GetChildren or not frame.IsShown) then
        frame = nil
    end
    if frame ~= lfgNativeFrame then
        _RestoreNativeLFGTracker(lfgNativeFrame)
        lfgNativeFrame = frame
    end
    return lfgNativeFrame
end

local function _EnsureNativeLFGTrackerHooks(frame)
    if not frame or frame.__Questie335LFGHooksInstalled or not frame.HookScript then
        return
    end

    frame.__Questie335LFGHooksInstalled = true
    local function _Hook(scriptName)
        pcall(frame.HookScript, frame, scriptName, function()
            _RequestLFGObjectiveMirrorRefresh()
        end)
    end

    _Hook("OnEvent")
    _Hook("OnShow")
    _Hook("OnHide")
    _Hook("OnSizeChanged")
end

function QuestieTracker:RefreshLFGObjectiveMirror()
    local previousSignature = lfgMirrorSnapshot and lfgMirrorSnapshot.signature
    local frame = _GetNativeLFGTracker()
    if frame then
        _EnsureNativeLFGTrackerHooks(frame)
    end

    local enabled = QuestieTracker.started
        and Questie.db.profile.trackerEnabled
        and Questie.db.profile.trackerMirrorLFGObjectives
        and not QuestieTracker.disableHooks

    if not enabled or not frame or not frame:IsShown() then
        _RestoreNativeLFGTracker(frame)
        lfgMirrorSnapshot = nil
        return previousSignature ~= nil
    end

    local snapshot = _BuildLFGMirrorSnapshot(frame)
    if not snapshot then
        _RestoreNativeLFGTracker(frame)
        lfgMirrorSnapshot = nil
        return previousSignature ~= nil
    end

    lfgMirrorSnapshot = snapshot
    if InCombatLockdown() then
        if _RefreshRenderedLFGSnapshot(snapshot) then
            _SuppressNativeLFGTracker(frame)
        else
            _RestoreNativeLFGTracker(frame)
        end
    elseif #lfgRenderedLines > 0 then
        _SuppressNativeLFGTracker(frame)
    end
    return previousSignature ~= snapshot.signature
end

_RequestLFGObjectiveMirrorRefresh = function()
    if lfgMirrorRefreshScheduled then
        return
    end

    lfgMirrorRefreshScheduled = true
    C_Timer.After(0, function()
        lfgMirrorRefreshScheduled = false
        local changed = QuestieTracker:RefreshLFGObjectiveMirror()
        if changed and not InCombatLockdown() and QuestieTracker.started then
            QuestieCombatQueue:Queue(function()
                QuestieTracker:Update(true)
            end)
        end
    end)
end

function QuestieTracker:RequestLFGObjectiveMirrorRefresh()
    _RequestLFGObjectiveMirrorRefresh()
end

function QuestieTracker:SetLFGObjectiveMirrorEnabled(enabled)
    Questie.db.profile.trackerMirrorLFGObjectives = enabled and true or false
    if not enabled then
        _RestoreNativeLFGTracker()
        lfgMirrorSnapshot = nil
    else
        QuestieTracker:RefreshLFGObjectiveMirror()
    end

    if QuestieTracker.started and not InCombatLockdown() then
        QuestieTracker:Update(true)
    end
end

function QuestieTracker:SetLFGObjectiveCombatFallback(inCombat)
    if not Questie.db.profile.trackerMirrorLFGObjectives then
        return
    end

    if inCombat then
        QuestieTracker:RefreshLFGObjectiveMirror()
    elseif QuestieTracker.started then
        QuestieCombatQueue:Queue(function()
            QuestieTracker:Update(true)
        end)
    end
end

local function _TrimAutoQuestText(value)
    if type(value) == "table" then
        value = value.title or value.name or value.questName
    end
    if type(value) ~= "string" then
        return nil
    end

    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    if value == "" then
        return nil
    end
    return value
end

local function _CallQuestTitleProvider(provider, methodName, questId)
    local method = type(provider) == "table" and provider[methodName]
    if type(method) ~= "function" then
        return nil
    end

    local ok, value = pcall(method, questId)
    if not ok then
        return nil
    end
    return _TrimAutoQuestText(value)
end

local function _ResolveAutoQuestTitle(questId, titleHint)
    local title = _TrimAutoQuestText(titleHint)
    if title then
        return title
    end

    if QuestieCompat.GetQuestNameById then
        local ok, value = pcall(QuestieCompat.GetQuestNameById, questId)
        if ok then
            title = _TrimAutoQuestText(value)
            if title then
                return title
            end
        end
    end

    title = _CallQuestTitleProvider(_G.C_TaskQuest, "GetQuestInfoByQuestID", questId)
    if title then
        return title
    end

    title = _CallQuestTitleProvider(NativeC_QuestLog, "GetTitleForQuestID", questId)
        or _CallQuestTitleProvider(NativeC_QuestLog, "GetQuestInfo", questId)
        or _CallQuestTitleProvider(C_QuestLog, "GetTitleForQuestID", questId)
        or _CallQuestTitleProvider(C_QuestLog, "GetQuestInfo", questId)
    if title then
        return title
    end

    if NativeC_QuestLog and type(NativeC_QuestLog.RequestLoadQuestByID) == "function" then
        pcall(NativeC_QuestLog.RequestLoadQuestByID, questId)
    elseif C_QuestLog and type(C_QuestLog.RequestLoadQuestByID) == "function" then
        pcall(C_QuestLog.RequestLoadQuestByID, questId)
    end

    local questLogIndex = GetQuestLogIndexByID and GetQuestLogIndexByID(questId)
    if questLogIndex then
        return _TrimAutoQuestText(GetQuestLogTitle(questLogIndex))
    end
end

local function _IsPlayerOnAutoQuest(questId)
    if not questId then
        return false
    end

    local questLogIndex = GetQuestLogIndexByID and GetQuestLogIndexByID(questId)
    if questLogIndex and questLogIndex > 0 then
        return true
    end

    if C_QuestLog and type(C_QuestLog.IsOnQuest) == "function" then
        local ok, isOnQuest = pcall(C_QuestLog.IsOnQuest, questId)
        if ok and isOnQuest then
            return true
        end
    end
    return false
end

local function _HasReadyAutoQuestOffers()
    if not Questie.db or not Questie.db.profile or not Questie.db.profile.trackerAutoQuestNotices then
        return false
    end

    for _, questId in ipairs(autoQuestOfferOrder) do
        local offer = autoQuestOffers[questId]
        if offer and offer.title then
            return true
        end
    end
    return false
end

local function _HasPendingAutoQuestOffers()
    local profile = Questie.db and Questie.db.profile
    if not profile or not profile.trackerEnabled or not profile.trackerAutoQuestNotices then
        return false
    end

    for _, questId in ipairs(autoQuestOfferOrder) do
        if autoQuestOffers[questId] then
            return true
        end
    end
    return false
end

local function _IsFrameEffectivelyVisible(frame)
    if not frame then
        return false
    end
    if type(frame.IsVisible) == "function" then
        return frame:IsVisible()
    end
    return not frame.IsShown or frame:IsShown()
end

local function _HasVisibleAutoQuestReplacement()
    local profile = Questie.db and Questie.db.profile
    if not profile or not profile.trackerEnabled or not profile.trackerAutoQuestNotices then
        return false
    end
    if not _IsFrameEffectivelyVisible(trackerBaseFrame) then
        return false
    end

    for _, noticeLine in ipairs(autoQuestRenderedLines) do
        if noticeLine.isAutoQuestNotice and _IsFrameEffectivelyVisible(noticeLine)
            and _IsFrameEffectivelyVisible(noticeLine.autoQuestPanel)
        then
            return true
        end
    end
    return false
end

local function _IsAutoQuestModifierDown()
    local modifier = Questie.db and Questie.db.profile and Questie.db.profile.autoModifier
    if type(_QuestieAuto.IsBindTrue) == "function" then
        local ok, isDown = pcall(_QuestieAuto.IsBindTrue, _QuestieAuto, modifier)
        if ok then
            return isDown == true
        end
    end

    if modifier == "shift" then
        return IsShiftKeyDown()
    elseif modifier == "ctrl" then
        return IsControlKeyDown()
    elseif modifier == "alt" then
        return IsAltKeyDown()
    end
    return false
end

local function _ShouldAutoAcceptAutoQuest(questId, offer)
    if not Questie.db or not Questie.db.profile or not Questie.db.profile.autoaccept then
        return false
    end
    if offer and offer.autoAcceptSuppressed then
        return false
    end
    if _QuestieAuto.disallowedQuests and _QuestieAuto.disallowedQuests[questId] then
        return false
    end
    return true
end

local function _RetryAutoQuestNativeSuppression(questId)
    if not autoQuestOffers[questId] then
        return
    end

    autoQuestSuppressionScanNeeded = true
    if _SuppressNativeAutoQuestDefaults and _HasVisibleAutoQuestReplacement() then
        _SuppressNativeAutoQuestDefaults()
    else
        _RequestAutoQuestNoticeRefresh()
    end
end

local function _RemoveAutoQuestOffer(questId)
    questId = tonumber(questId)
    if not questId or not autoQuestOffers[questId] then
        return false
    end

    autoQuestOffers[questId] = nil
    for index = #autoQuestOfferOrder, 1, -1 do
        if autoQuestOfferOrder[index] == questId then
            table.remove(autoQuestOfferOrder, index)
            break
        end
    end
    autoQuestSuppressionScanNeeded = true
    C_Timer.After(0, function()
        if _ScheduleNextAutoQuestAutoAccept then
            _ScheduleNextAutoQuestAutoAccept()
        end
    end)
    return true
end

local function _ScheduleAutoQuestTitleRetry(offer)
    offer.titleRetries = (offer.titleRetries or 0) + 1
    local questId = offer.questId
    C_Timer.After(AUTO_QUEST_NOTICE_RETRY_DELAY, function()
        if autoQuestOffers[questId] ~= offer or (offer.title and not offer.titleIsFallback) then
            return
        end

        local resolvedTitle = _ResolveAutoQuestTitle(questId, offer.titleHint)
        if resolvedTitle then
            offer.title = resolvedTitle
            offer.titleIsFallback = nil
        end
        if not resolvedTitle and offer.titleRetries < AUTO_QUEST_NOTICE_MAX_RETRIES then
            _ScheduleAutoQuestTitleRetry(offer)
            return
        end

        -- Ascension custom quests can be absent from Questie's DB and still be
        -- valid server offers. Keep the interaction functional in that case.
        if not resolvedTitle then
            offer.title = "Quest " .. tostring(questId)
            offer.titleIsFallback = true
        end
        autoQuestSuppressionScanNeeded = true
        _RequestAutoQuestNoticeRefresh()
    end)
end

local function _CaptureAutoQuestOffer(questId, popupType, titleHint, nativeFrame)
    questId = tonumber(questId)
    if not questId or questId <= 0 then
        return false
    end
    if autoQuestOpeningQuestId == questId then
        return false
    end

    popupType = string.upper(tostring(popupType or "OFFER"))
    if popupType ~= "OFFER" or _IsPlayerOnAutoQuest(questId) then
        return false
    end

    local offer = autoQuestOffers[questId]
    local isNewOffer = not offer
    if not offer then
        offer = {
            questId = questId,
            shouldAnimate = true,
            autoAcceptSuppressed = _IsAutoQuestModifierDown(),
        }
        autoQuestOffers[questId] = offer
        autoQuestOfferOrder[#autoQuestOfferOrder + 1] = questId
    end

    if nativeFrame then
        offer.nativeFrame = nativeFrame
    end

    local resolvedHint = _TrimAutoQuestText(titleHint)
    if resolvedHint then
        offer.titleHint = resolvedHint
        offer.title = resolvedHint
        offer.titleIsFallback = nil
    elseif not offer.title or offer.titleIsFallback then
        local resolvedTitle = _ResolveAutoQuestTitle(questId, offer.titleHint)
        if resolvedTitle then
            offer.title = resolvedTitle
            offer.titleIsFallback = nil
        end
    end
    if (not offer.title or offer.titleIsFallback) and not offer.titleRetryScheduled then
        offer.titleRetryScheduled = true
        _ScheduleAutoQuestTitleRetry(offer)
    end

    autoQuestSuppressionScanNeeded = true
    _RequestAutoQuestNoticeRefresh()

    if isNewOffer then
        C_Timer.After(0, function()
            if _ScheduleNextAutoQuestAutoAccept then
                _ScheduleNextAutoQuestAutoAccept()
            end
        end)
        -- Native and DialogueUI popup frames are created immediately after the
        -- API call. Two bounded retries catch those frames without polling forever.
        C_Timer.After(0.10, function()
            _RetryAutoQuestNativeSuppression(questId)
        end)
        C_Timer.After(0.40, function()
            _RetryAutoQuestNativeSuppression(questId)
        end)
    end
    return true
end

local function _GetWatchFrameAutoQuestPopupData(frame)
    if not frame or type(frame.GetName) ~= "function" then
        return nil, nil, nil
    end

    local ok, frameName = pcall(frame.GetName, frame)
    local popupIndex = ok and type(frameName) == "string"
        and tonumber(string.match(frameName, "^WatchFrameAutoQuestPopUp(%d+)$")) or nil
    if not popupIndex then
        return nil, nil, nil
    end

    if type(GetAutoQuestPopUp) == "function" then
        local dataOk, questId, popupType = pcall(GetAutoQuestPopUp, popupIndex)
        if dataOk then
            return tonumber(questId), popupType, popupIndex
        end
    end
    return nil, nil, popupIndex
end

local function _GetFrameQuestId(frame)
    if not frame then
        return nil
    end

    local questId = tonumber(frame.questID or frame.questId or frame.QuestID)
    if questId then
        return questId
    end
    return _GetWatchFrameAutoQuestPopupData(frame)
end

local function _GetAutoQuestFrameTitle(frame)
    if not frame then
        return nil
    end

    local ignoredText = {
        ["accept"] = true,
        ["accept quest"] = true,
        ["auto-provided quest"] = true,
        ["click to accept quest"] = true,
        ["click to view quest"] = true,
        ["new quest available"] = true,
        ["objectives"] = true,
        ["quest accepted"] = true,
        ["quest discovered"] = true,
        ["quest discovered!"] = true,
        ["view"] = true,
        ["view quest"] = true,
    }
    local bestTitle
    local titleParts = {}
    local titlePartSet = {}

    local function ConsiderText(value)
        value = _TrimAutoQuestText(value)
        if not value then
            return
        end
        value = string.gsub(value, "|T.-|t", "")
        value = string.gsub(value, "|c%x%x%x%x%x%x%x%x", "")
        value = string.gsub(value, "|r", "")

        local parts = {}
        for part in string.gmatch(value, "[^\r\n]+") do
            part = _TrimAutoQuestText(part)
            local lower = part and string.lower(part)
            if part and not ignoredText[lower]
                and not string.find(lower, "^click to ")
                and not string.find(lower, "^quest %d+$")
            then
                parts[#parts + 1] = part
            end
        end

        local candidate = _TrimAutoQuestText(table.concat(parts, " "))
        if candidate and string.find(candidate, "[^%s%p]") then
            if not titlePartSet[candidate] then
                titlePartSet[candidate] = true
                titleParts[#titleParts + 1] = candidate
            end
            if not bestTitle or string.len(candidate) > string.len(bestTitle) then
                bestTitle = candidate
            end
        end
    end

    local function GetObjects(container, methodName)
        local method = container and container[methodName]
        if type(method) ~= "function" then
            return {}
        end

        local objects
        local ok = pcall(function()
            objects = {method(container)}
        end)
        return ok and objects or {}
    end

    local visited = {}
    local function ScanContainer(container, depth)
        if not container or visited[container] or depth > 3 then
            return
        end
        visited[container] = true

        for _, key in ipairs({"QuestName", "questName", "QuestTitle", "questTitle", "Title", "title", "Text", "text"}) do
            local value = container[key]
            if type(value) == "string" then
                ConsiderText(value)
            elseif value and type(value.GetText) == "function" then
                local ok, text = pcall(value.GetText, value)
                if ok then
                    ConsiderText(text)
                end
            end
        end

        if type(container.GetRegions) == "function" then
            for _, region in ipairs(GetObjects(container, "GetRegions")) do
                if region and type(region.GetText) == "function" then
                    local ok, text = pcall(region.GetText, region)
                    if ok then
                        ConsiderText(text)
                    end
                end
            end
        end
        if type(container.GetChildren) == "function" then
            for _, child in ipairs(GetObjects(container, "GetChildren")) do
                ScanContainer(child, depth + 1)
            end
        end
    end

    ScanContainer(frame, 0)
    if frame.ScrollChild then
        ScanContainer(frame.ScrollChild, 1)
    elseif type(frame.GetName) == "function" then
        local ok, frameName = pcall(frame.GetName, frame)
        if ok and type(frameName) == "string" then
            ScanContainer(_G[frameName .. "ScrollChild"], 1)
        end
    end
    if #titleParts <= 1 then
        return bestTitle
    end

    local independentParts = {}
    for index, candidate in ipairs(titleParts) do
        local contained = false
        for otherIndex, other in ipairs(titleParts) do
            if index ~= otherIndex and string.len(other) > string.len(candidate)
                and string.find(other, candidate, 1, true)
            then
                contained = true
                break
            end
        end
        if not contained then
            independentParts[#independentParts + 1] = candidate
        end
    end

    local combinedTitle = _TrimAutoQuestText(table.concat(independentParts, " "))
    if combinedTitle and string.len(combinedTitle) <= 255 then
        return combinedTitle
    end
    return bestTitle
end

local function _IsExplicitAutoQuestOfferFrame(frame)
    if not frame then
        return false
    end

    local layout = string.lower(tostring(frame.layout or ""))
    local popupType = string.upper(tostring(frame.popupType or frame.questPopupType or frame.type or ""))
    local _, watchPopupType, watchPopupIndex = _GetWatchFrameAutoQuestPopupData(frame)
    return layout == "offer"
        or popupType == "OFFER"
        or frame.isAutoQuestPopup == true
        or frame.isAutoQuest == true
        or (watchPopupIndex and (watchPopupType == nil or string.upper(tostring(watchPopupType)) == "OFFER"))
end

local function _EnumerateFrames(callback)
    if type(EnumerateFrames) ~= "function" then
        return
    end

    local frame = EnumerateFrames()
    local count = 0
    while frame and count < 10000 do
        count = count + 1
        if callback(frame) == true then
            return frame
        end
        frame = EnumerateFrames(frame)
    end
end

local function _ScanPendingNativeAutoQuestOffers()
    if type(GetAutoQuestPopUp) ~= "function" then
        return
    end

    local popupCount
    if type(GetNumAutoQuestPopUps) == "function" then
        local ok, value = pcall(GetNumAutoQuestPopUps)
        popupCount = ok and tonumber(value) or nil
    end

    -- Ascension exposes GetAutoQuestPopUp even on builds where the count helper
    -- is absent. A small bounded scan recovers offers that survived /reload.
    local scanLimit = math.max(0, math.min(50, popupCount or 20))
    for popupIndex = 1, scanLimit do
        local ok, questId, popupType = pcall(GetAutoQuestPopUp, popupIndex)
        questId = ok and tonumber(questId) or nil
        if questId then
            _CaptureAutoQuestOffer(questId, popupType, nil)
        end
    end
end

local function _ScanVisibleAutoQuestOffers(scanPendingQueue)
    if scanPendingQueue then
        _ScanPendingNativeAutoQuestOffers()
    end

    _EnumerateFrames(function(frame)
        local _, _, watchPopupIndex = _GetWatchFrameAutoQuestPopupData(frame)
        local isShown = not frame.IsShown or frame:IsShown()
        local isActive = frame.isActive == true
        if _IsExplicitAutoQuestOfferFrame(frame) and (isShown or isActive or watchPopupIndex) then
            local questId = _GetFrameQuestId(frame)
            if questId then
                if _EnsureAutoQuestNativeHook then
                    _EnsureAutoQuestNativeHook(frame)
                end
                _CaptureAutoQuestOffer(questId, "OFFER", _GetAutoQuestFrameTitle(frame), frame)
            end
        end
    end)
end

local function _FindNativeAutoQuestFrame(questId)
    local offer = autoQuestOffers[questId]
    local frame = offer and offer.nativeFrame
    if frame and _GetFrameQuestId(frame) == questId then
        return frame
    end

    return _EnumerateFrames(function(candidate)
        return _GetFrameQuestId(candidate) == questId
            and _IsExplicitAutoQuestOfferFrame(candidate)
    end)
end

local function _InvokeNativeAutoQuestFrame(frame)
    if not frame then
        return false
    end

    if type(frame.Click) == "function" and pcall(frame.Click, frame, "LeftButton") then
        return true
    end

    local globalHandler = _G.WatchFrameAutoQuestPopUp_OnClick or _G.WatchFrameAutoQuestPopup_OnClick
    if type(globalHandler) == "function" and pcall(globalHandler, frame, "LeftButton") then
        return true
    end

    local function InvokeScript(target, scriptName)
        if not target or type(target.GetScript) ~= "function" then
            return false
        end
        local ok, script = pcall(target.GetScript, target, scriptName)
        if ok and type(script) == "function" then
            return pcall(script, target, "LeftButton") == true
        end
        return false
    end

    if InvokeScript(frame, "OnClick") or InvokeScript(frame, "OnMouseUp") then
        return true
    end

    local scrollChild = frame.ScrollChild
    if not scrollChild and type(frame.GetName) == "function" then
        local ok, frameName = pcall(frame.GetName, frame)
        if ok and type(frameName) == "string" then
            scrollChild = _G[frameName .. "ScrollChild"]
        end
    end
    return InvokeScript(scrollChild, "OnClick") or InvokeScript(scrollChild, "OnMouseUp")
end

local function _RequestAutoQuestOfferDisplay(questId, preferNativeFrame)
    if preferNativeFrame then
        local nativeFrame = _FindNativeAutoQuestFrame(questId)
        if _InvokeNativeAutoQuestFrame(nativeFrame) then
            return true
        end
    end

    if type(ShowQuestOffer) ~= "function" then
        return false
    end
    local ok, result = pcall(ShowQuestOffer, questId)
    return ok and result ~= false
end

local function _CloseDialogueAutoQuestOffer(questId)
    local closed = false
    _EnumerateFrames(function(frame)
        if _GetFrameQuestId(frame) == questId
            and frame.layout == "offer"
            and frame.isActive ~= false
            and type(frame.SetQuestOffer) == "function"
            and type(frame.Close) == "function"
        then
            closed = pcall(frame.Close, frame) == true
            return closed
        end
    end)
    return closed
end

local function _DismissPendingAutoQuestPopup(questId)
    if _CloseDialogueAutoQuestOffer(questId) then
        return
    end

    if type(RemoveAutoQuestPopUp) == "function" then
        pcall(RemoveAutoQuestPopUp, questId)
    elseif type(WatchFrameAutoQuest_ClearPopUp) == "function" then
        pcall(WatchFrameAutoQuest_ClearPopUp, questId)
    end
    if type(WatchFrame_Update) == "function" then
        pcall(WatchFrame_Update)
    end
end

local function _SuppressAutoQuestFrame(frame)
    if not frame or frame == trackerBaseFrame or not frame.SetAlpha then
        return false
    end
    if InCombatLockdown() then
        return false
    end

    local state = autoQuestSuppressedFrameSet[frame]
    if not state then
        state = {
            frame = frame,
            alpha = frame.GetAlpha and frame:GetAlpha() or 1,
            wasShown = not frame.IsShown or frame:IsShown(),
            mouse = {},
            mouseOrder = {},
        }
        if _IsExplicitAutoQuestOfferFrame(frame) and frame.isActive ~= false and state.alpha <= 0 then
            state.alpha = 1
        end
        autoQuestSuppressedFrameSet[frame] = state
        autoQuestSuppressedFrames[#autoQuestSuppressedFrames + 1] = state
    end

    if not pcall(frame.SetAlpha, frame, 0) then
        return false
    end
    local frames = {}
    _CollectLFGFrames(frame, frames, {}, 0)
    for _, target in ipairs(frames) do
        if target.EnableMouse and target.IsMouseEnabled then
            if state.mouse[target] == nil then
                local ok, enabled = pcall(target.IsMouseEnabled, target)
                if ok then
                    state.mouse[target] = enabled and 1 or 0
                    state.mouseOrder[#state.mouseOrder + 1] = target
                end
            end
            if state.mouse[target] ~= nil then
                pcall(target.EnableMouse, target, false)
            end
        end
    end
    if frame.Hide and (not frame.IsShown or frame:IsShown()) then
        state.hiddenByQuestie = pcall(frame.Hide, frame) == true
    end
    return true
end

local function _RestoreAutoQuestFrame(state)
    local frame = state and state.frame
    if not frame then
        return true
    end

    local complete = true
    if frame.SetAlpha and not pcall(frame.SetAlpha, frame, tonumber(state.alpha) or 1) then
        complete = false
    end
    for _, target in ipairs(state.mouseOrder or {}) do
        if target and target.EnableMouse and state.mouse[target] ~= nil then
            if not pcall(target.EnableMouse, target, state.mouse[target] == 1) then
                complete = false
            end
        end
    end
    if state.hiddenByQuestie and state.wasShown and frame.Show then
        local questId = _GetFrameQuestId(frame)
        if questId and autoQuestOffers[questId] and not _IsPlayerOnAutoQuest(questId) then
            if not pcall(frame.Show, frame) then
                complete = false
            end
        end
    end
    state.hiddenByQuestie = nil
    return complete
end

local function _GetNativeWatchFrame()
    return _G.WatchFrame or _G.QuestWatchFrame
end

local function _ShouldSuppressNativeWatchFrame()
    local profile = Questie.db and Questie.db.profile
    return not autoQuestNativeSuppressionSuspended
        and profile and profile.trackerAutoQuestHideNative
        and _HasPendingAutoQuestOffers()
end

local function _SuppressNativeWatchFrame()
    if not _ShouldSuppressNativeWatchFrame() then
        return false
    end

    local frame = _GetNativeWatchFrame()
    if not frame or not frame.Hide then
        return false
    end
    if not autoQuestNativeWatchFrameSuppressed then
        autoQuestNativeWatchFrameWasShown = not frame.IsShown or frame:IsShown()
        autoQuestNativeWatchFrameSuppressed = true
    end
    if not frame.IsShown or frame:IsShown() then
        pcall(frame.Hide, frame)
    end
    return true
end

local function _RestoreNativeWatchFrame()
    if not autoQuestNativeWatchFrameSuppressed then
        return
    end

    local frame = _GetNativeWatchFrame()
    local wasShown = autoQuestNativeWatchFrameWasShown
    autoQuestNativeWatchFrameSuppressed = false
    autoQuestNativeWatchFrameWasShown = false

    local profile = Questie.db and Questie.db.profile
    if frame and frame.Show and wasShown and profile and profile.trackerEnabled
        and profile.showBlizzardQuestTimer
    then
        pcall(frame.Show, frame)
    end
end

local function _InstallNativeWatchFrameSuppression()
    local frame = _GetNativeWatchFrame()
    if not frame or frame == autoQuestNativeWatchFrameHooked or not frame.HookScript then
        return
    end

    autoQuestNativeWatchFrameHooked = frame
    pcall(frame.HookScript, frame, "OnShow", function()
        _SuppressNativeWatchFrame()
    end)
end

_RestoreNativeAutoQuestDefaults = function()
    local remaining = {}
    for index = #autoQuestSuppressedFrames, 1, -1 do
        local state = autoQuestSuppressedFrames[index]
        if _RestoreAutoQuestFrame(state) then
            autoQuestSuppressedFrameSet[state.frame] = nil
        else
            table.insert(remaining, 1, state)
        end
    end
    autoQuestSuppressedFrames = remaining
    _RestoreNativeWatchFrame()
end

_EnsureAutoQuestNativeHook = function(frame)
    if not frame or frame.__Questie335AutoQuestHooked or not frame.HookScript then
        return
    end

    frame.__Questie335AutoQuestHooked = true
    local isOfferFrame = _IsExplicitAutoQuestOfferFrame(frame)
    local function RefreshAfterNativeChange(self)
        if isOfferFrame then
            local questId = _GetFrameQuestId(self)
            if questId then
                _CaptureAutoQuestOffer(questId, "OFFER", _GetAutoQuestFrameTitle(self), self)
            end
        end
        if isOfferFrame
            and not autoQuestNativeSuppressionSuspended
            and Questie.db.profile.trackerAutoQuestHideNative
            and _HasVisibleAutoQuestReplacement()
            and not InCombatLockdown()
        then
            _SuppressAutoQuestFrame(self)
        end
        if _HasReadyAutoQuestOffers() then
            autoQuestSuppressionScanNeeded = true
            _RequestAutoQuestNoticeRefresh()
        end
    end
    pcall(frame.HookScript, frame, "OnShow", RefreshAfterNativeChange)
    pcall(frame.HookScript, frame, "OnEvent", RefreshAfterNativeChange)
    if isOfferFrame then
        pcall(frame.HookScript, frame, "OnUpdate", function(self)
            if autoQuestSuppressedFrameSet[self] and self.SetAlpha then
                self:SetAlpha(0)
            end
        end)
        pcall(frame.HookScript, frame, "OnHide", function(self)
            local questId = self.isActive == false and _GetFrameQuestId(self)
            if questId and _RemoveAutoQuestOffer(questId) then
                _RequestAutoQuestNoticeRefresh()
            end
        end)
    end
end

_SuppressNativeAutoQuestDefaults = function()
    if autoQuestNativeSuppressionSuspended then
        _RestoreNativeAutoQuestDefaults()
        return
    end
    if not Questie.db.profile.trackerAutoQuestHideNative or not _HasPendingAutoQuestOffers() then
        _RestoreNativeAutoQuestDefaults()
        return
    end

    _InstallNativeWatchFrameSuppression()
    _SuppressNativeWatchFrame()
    if InCombatLockdown() then
        autoQuestSuppressionScanNeeded = true
        return
    end

    for _, frame in ipairs({_G.ObjectiveTrackerFrame, _G.QuestObjectiveTracker, _G.WatchFrame}) do
        if frame and frame.GetChildren and frame.IsShown and frame:IsShown() then
            _EnsureAutoQuestNativeHook(frame)
        end
    end

    if not autoQuestSuppressionScanNeeded then
        return
    end
    autoQuestSuppressionScanNeeded = false

    _EnumerateFrames(function(frame)
        local questId = _GetFrameQuestId(frame)
        if questId and autoQuestOffers[questId] and _IsExplicitAutoQuestOfferFrame(frame)
            and (not frame.IsShown or frame:IsShown())
        then
            _EnsureAutoQuestNativeHook(frame)
            _SuppressAutoQuestFrame(frame)
        end
    end)
end

local function _FindDialogueUIWidgetManager()
    return _EnumerateFrames(function(frame)
        return type(frame.AddAutoQuestPopUp) == "function"
            and type(frame.AcquireQuestPopup) == "function"
    end)
end

local function _InstallDialogueUIAutoQuestHook()
    if autoQuestDialogueHookInstalled then
        return true
    end

    local manager = _FindDialogueUIWidgetManager()
    if not manager then
        return false
    end

    local ok = pcall(hooksecurefunc, manager, "AddAutoQuestPopUp", function()
        local questId = type(GetQuestID) == "function" and GetQuestID()
        local title = type(GetTitleText) == "function" and GetTitleText()
        _CaptureAutoQuestOffer(questId, "OFFER", title)
        _ScanVisibleAutoQuestOffers()
    end)
    autoQuestDialogueHookInstalled = ok == true
    return autoQuestDialogueHookInstalled
end

local function _RetryDialogueUIAutoQuestHook()
    if _InstallDialogueUIAutoQuestHook() then
        return
    end
    autoQuestDialogueHookRetries = autoQuestDialogueHookRetries + 1
    if autoQuestDialogueHookRetries < 4 then
        C_Timer.After(autoQuestDialogueHookRetries, _RetryDialogueUIAutoQuestHook)
    end
end

local function _ScheduleAutoQuestOfferDiscovery()
    autoQuestDiscoveryGeneration = autoQuestDiscoveryGeneration + 1
    local generation = autoQuestDiscoveryGeneration

    for _, delay in ipairs(AUTO_QUEST_DISCOVERY_DELAYS) do
        C_Timer.After(delay, function()
            if generation ~= autoQuestDiscoveryGeneration then
                return
            end
            _ScanVisibleAutoQuestOffers(true)
        end)
    end
end

local function _SweepAcceptedAutoQuestOffers()
    local changed = false
    for index = #autoQuestOfferOrder, 1, -1 do
        local questId = autoQuestOfferOrder[index]
        if _IsPlayerOnAutoQuest(questId) then
            changed = _RemoveAutoQuestOffer(questId) or changed
        end
    end

    if changed then
        _RequestAutoQuestNoticeRefresh()
    elseif not _HasReadyAutoQuestOffers() then
        _RestoreNativeAutoQuestDefaults()
    end
end

local function _OnAutoQuestDetail(questStartItemId)
    local questId = type(GetQuestID) == "function" and GetQuestID()
    if not questId or questId == 0 then
        return
    end

    local fromItem = questStartItemId and tonumber(questStartItemId) and tonumber(questStartItemId) ~= 0
    local fromArea = false
    local autoAccept = false
    if type(QuestIsFromAreaTrigger) == "function" then
        local ok, value = pcall(QuestIsFromAreaTrigger)
        fromArea = ok and value == true
    end
    if type(QuestGetAutoAccept) == "function" then
        local ok, value = pcall(QuestGetAutoAccept)
        autoAccept = ok and value == true
    end

    if fromItem or (fromArea and (autoAccept or InCombatLockdown())) then
        local title = type(GetTitleText) == "function" and GetTitleText()
        _CaptureAutoQuestOffer(questId, "OFFER", title)
    end
end

local function _InitializeAutoQuestNoticeHooks()
    autoQuestNativeSuppressionSuspended = false
    _InstallNativeWatchFrameSuppression()
    if type(AddAutoQuestPopUp) == "function" and not autoQuestGlobalHookInstalled then
        local ok = pcall(hooksecurefunc, "AddAutoQuestPopUp", function(questId, popupType)
            _CaptureAutoQuestOffer(questId, popupType, nil)
        end)
        autoQuestGlobalHookInstalled = ok == true
    end
    if type(RemoveAutoQuestPopUp) == "function" and not autoQuestRemoveHookInstalled then
        local ok = pcall(hooksecurefunc, "RemoveAutoQuestPopUp", function(questId)
            if _RemoveAutoQuestOffer(questId) then
                _RequestAutoQuestNoticeRefresh()
            end
        end)
        autoQuestRemoveHookInstalled = ok == true
    end
    if type(WatchFrame_Update) == "function" and not autoQuestWatchFrameUpdateHookInstalled then
        local ok = pcall(hooksecurefunc, "WatchFrame_Update", function()
            autoQuestSuppressionScanNeeded = true
            _ScanVisibleAutoQuestOffers()
            if _HasPendingAutoQuestOffers() then
                _SuppressNativeAutoQuestDefaults()
            else
                _RestoreNativeAutoQuestDefaults()
            end
        end)
        autoQuestWatchFrameUpdateHookInstalled = ok == true
    end

    _RetryDialogueUIAutoQuestHook()

    if not autoQuestEventFrame then
        autoQuestEventFrame = CreateFrame("Frame")
        autoQuestEventFrame:RegisterEvent("QUEST_DETAIL")
        autoQuestEventFrame:RegisterEvent("QUEST_ACCEPTED")
        autoQuestEventFrame:RegisterEvent("QUEST_LOG_UPDATE")
        autoQuestEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        autoQuestEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        autoQuestEventFrame:SetScript("OnEvent", function(_, event, ...)
            if event == "QUEST_DETAIL" then
                if not (_HandlePresentedAutoQuestDetail and _HandlePresentedAutoQuestDetail(...)) then
                    _OnAutoQuestDetail(...)
                end
            elseif event == "QUEST_ACCEPTED" or event == "QUEST_LOG_UPDATE" then
                C_Timer.After(0, _SweepAcceptedAutoQuestOffers)
            elseif event == "PLAYER_ENTERING_WORLD" then
                _ScheduleAutoQuestOfferDiscovery()
            elseif event == "PLAYER_REGEN_ENABLED" then
                _SweepAcceptedAutoQuestOffers()
                autoQuestSuppressionScanNeeded = true
                _RequestAutoQuestNoticeRefresh()
            end
        end)
    end

    -- Questie can initialize before WatchFrame recreates a pending popup after
    -- /reload. These bounded scans bridge that startup window without polling.
    _ScheduleAutoQuestOfferDiscovery()
end

local function _SetTextureColor(texture, color, fallback)
    color = type(color) == "table" and color or fallback
    texture:SetVertexColor(
        tonumber(color[1]) or fallback[1],
        tonumber(color[2]) or fallback[2],
        tonumber(color[3]) or fallback[3],
        tonumber(color[4]) or fallback[4]
    )
end

local function _CreateNoticeEdge(parent)
    local edge = parent:CreateTexture(nil, "BORDER")
    edge:SetTexture("Interface\\Buttons\\WHITE8X8")
    return edge
end

local function _CreateAutoQuestNoticeAction(parent, name, label)
    local action = CreateFrame("Button", name, parent)
    action:RegisterForClicks("LeftButtonUp")
    action:SetFrameLevel(parent:GetFrameLevel() + 2)
    action.background = action:CreateTexture(nil, "BACKGROUND")
    action.background:SetTexture("Interface\\Buttons\\WHITE8X8")
    action.background:SetAllPoints(action)
    action.glow = action:CreateTexture(nil, "BACKGROUND")
    action.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    action.glow:SetPoint("TOPLEFT", action, "TOPLEFT", -2, 2)
    action.glow:SetPoint("BOTTOMRIGHT", action, "BOTTOMRIGHT", 2, -2)
    action.edges = {
        top = _CreateNoticeEdge(action),
        bottom = _CreateNoticeEdge(action),
        left = _CreateNoticeEdge(action),
        right = _CreateNoticeEdge(action),
    }
    action.edges.top:SetPoint("TOPLEFT", action, "TOPLEFT", 0, 0)
    action.edges.top:SetPoint("TOPRIGHT", action, "TOPRIGHT", 0, 0)
    action.edges.top:SetHeight(1)
    action.edges.bottom:SetPoint("BOTTOMLEFT", action, "BOTTOMLEFT", 0, 0)
    action.edges.bottom:SetPoint("BOTTOMRIGHT", action, "BOTTOMRIGHT", 0, 0)
    action.edges.bottom:SetHeight(1)
    action.edges.left:SetPoint("TOPLEFT", action, "TOPLEFT", 0, 0)
    action.edges.left:SetPoint("BOTTOMLEFT", action, "BOTTOMLEFT", 0, 0)
    action.edges.left:SetWidth(1)
    action.edges.right:SetPoint("TOPRIGHT", action, "TOPRIGHT", 0, 0)
    action.edges.right:SetPoint("BOTTOMRIGHT", action, "BOTTOMRIGHT", 0, 0)
    action.edges.right:SetWidth(1)
    action.label = action:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    action.label:SetPoint("CENTER", action, "CENTER", 0, 0)
    action.label:SetText(label)
    action:SetScript("OnUpdate", function(self, elapsed)
        if not self.pulseEnabled then
            self.glow:SetAlpha(0)
            return
        end
        self.pulseTime = (self.pulseTime or 0) + elapsed
        local alpha = 0.10 + ((math.sin(self.pulseTime * 4.5) + 1) * 0.12)
        self.glow:SetAlpha(self.hovered and 0.42 or alpha)
    end)
    return action
end

local function _EnsureAutoQuestNoticeWidgets(line)
    if line.autoQuestPanel then
        return
    end

    local panel = CreateFrame("Frame", nil, line)
    panel:SetFrameLevel((line:GetFrameLevel() or 0) + 1)
    panel:EnableMouse(false)
    panel.background = panel:CreateTexture(nil, "BACKGROUND")
    panel.background:SetTexture("Interface\\Buttons\\WHITE8X8")
    panel.background:SetAllPoints(panel)
    panel.accent = panel:CreateTexture(nil, "ARTWORK")
    panel.accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    panel.accent:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -1)
    panel.accent:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 1)
    panel.accent:SetWidth(3)

    panel.edges = {
        top = _CreateNoticeEdge(panel),
        bottom = _CreateNoticeEdge(panel),
        left = _CreateNoticeEdge(panel),
        right = _CreateNoticeEdge(panel),
    }
    panel.edges.top:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    panel.edges.top:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    panel.edges.top:SetHeight(1)
    panel.edges.bottom:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    panel.edges.bottom:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    panel.edges.bottom:SetHeight(1)
    panel.edges.left:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    panel.edges.left:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    panel.edges.left:SetWidth(1)
    panel.edges.right:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    panel.edges.right:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    panel.edges.right:SetWidth(1)

    panel.badge = CreateFrame("Frame", nil, panel)
    panel.badge:SetSize(22, 22)
    panel.badge.background = panel.badge:CreateTexture(nil, "BACKGROUND")
    panel.badge.background:SetTexture("Interface\\Buttons\\WHITE8X8")
    panel.badge.background:SetAllPoints(panel.badge)
    panel.badgeText = panel.badge:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.badgeText:SetPoint("CENTER", panel.badge, "CENTER", 0, 0)
    panel.badgeText:SetText("!")

    panel.kicker = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    panel.kicker:SetJustifyH("LEFT")
    panel.kicker:SetJustifyV("TOP")
    if panel.kicker.SetWordWrap then
        panel.kicker:SetWordWrap(true)
    end
    if panel.kicker.SetNonSpaceWrap then
        panel.kicker:SetNonSpaceWrap(false)
    end
    panel.kicker:SetText("AUTO-PROVIDED QUEST")
    panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.title:SetJustifyH("LEFT")
    panel.title:SetJustifyV("TOP")
    if panel.title.SetWordWrap then
        panel.title:SetWordWrap(true)
    end
    if panel.title.SetNonSpaceWrap then
        panel.title:SetNonSpaceWrap(false)
    end

    local action = _CreateAutoQuestNoticeAction(panel, nil, "VIEW")
    action:SetScript("OnClick", function(self)
        QuestieTracker:OpenAutoQuestOffer(self.questId)
    end)
    action:SetScript("OnEnter", function(self)
        self.hovered = true
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine("Auto-provided quest", 1, 0.82, 0)
        GameTooltip:AddLine("Open the server quest offer so you can review and accept it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    action:SetScript("OnLeave", function(self)
        self.hovered = nil
        GameTooltip:Hide()
    end)
    panel.action = action

    autoQuestAcceptButtonCounter = autoQuestAcceptButtonCounter + 1
    local accept = _CreateAutoQuestNoticeAction(
        panel,
        "Questie335AutoQuestAcceptButton" .. autoQuestAcceptButtonCounter,
        "ACCEPT"
    )
    accept:SetScript("OnClick", function(self)
        QuestieTracker:AcceptAutoQuestOffer(self.questId, false)
    end)
    accept:SetScript("OnEnter", function(self)
        self.hovered = true
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine("Accept auto-provided quest", 1, 0.82, 0)
        GameTooltip:AddLine("Accept this quest immediately.", 1, 1, 1, true)
        GameTooltip:AddLine("Questie's Auto Accept Quests setting also applies to these offers.", 0.35, 0.9, 0.75, true)
        GameTooltip:Show()
    end)
    accept:SetScript("OnLeave", function(self)
        self.hovered = nil
        GameTooltip:Hide()
    end)
    panel.accept = accept

    line.autoQuestPanel = panel
    line.UpdateAutoQuestNoticeLayout = function(self)
        local noticePanel = self.autoQuestPanel
        if not noticePanel or not self.isAutoQuestNotice then
            return
        end

        local baseWidth = math.max(trackerMinLineWidth + trackerMarginRight, tonumber(trackerBaseFrame and trackerBaseFrame:GetWidth()) or 290)
        local panelWidth = math.max(252, baseWidth - 4)
        local textLeft = 38
        local textWidth = math.max(180, panelWidth - textLeft - 8)
        local questFontSize = TrackerFonts:GetQuestFontSize()
        local kickerFontSize = math.max(9, questFontSize - 2)

        noticePanel:ClearAllPoints()
        noticePanel:SetPoint("TOPLEFT", self, "TOPLEFT", -8, 0)
        noticePanel:SetWidth(panelWidth)
        noticePanel.badge:ClearAllPoints()
        noticePanel.badge:SetPoint("TOPLEFT", noticePanel, "TOPLEFT", 8, -9)
        noticePanel.kicker:ClearAllPoints()
        noticePanel.kicker:SetPoint("TOPLEFT", noticePanel, "TOPLEFT", textLeft, -7)
        noticePanel.kicker:SetWidth(textWidth)
        noticePanel.kicker:SetFont(TrackerFonts:GetQuestFont(), kickerFontSize, Questie.db.profile.trackerFontOutline)
        local kickerHeight = tonumber(noticePanel.kicker:GetStringHeight()) or kickerFontSize
        noticePanel.title:ClearAllPoints()
        noticePanel.title:SetPoint("TOPLEFT", noticePanel.kicker, "BOTTOMLEFT", 0, -2)
        noticePanel.title:SetWidth(textWidth)
        noticePanel.title:SetFont(TrackerFonts:GetQuestFont(), questFontSize, Questie.db.profile.trackerFontOutline)
        noticePanel.title:SetText(self.autoQuestTitle or ("Quest " .. tostring(self.autoQuestId or "?")))
        local titleHeight = tonumber(noticePanel.title:GetStringHeight()) or questFontSize
        local targetHeight = math.max(70, titleHeight + kickerHeight + 44)

        noticePanel.action:ClearAllPoints()
        noticePanel.action:SetPoint("BOTTOMLEFT", noticePanel, "BOTTOMLEFT", textLeft, 7)
        noticePanel.action:SetSize(panelWidth < 310 and 68 or 78, 23)
        noticePanel.accept:ClearAllPoints()
        noticePanel.accept:SetPoint("BOTTOMRIGHT", noticePanel, "BOTTOMRIGHT", -8, 7)
        noticePanel.accept:SetSize(panelWidth < 310 and 108 or 120, 23)
        noticePanel:SetHeight(targetHeight)
        self:SetWidth(math.max(1, baseWidth - 20))
        self.label:SetHeight(1)
        self.contentBottomPadding = targetHeight - 1
        self.autoQuestTargetHeight = targetHeight
        self:SetHeight(targetHeight)
    end
end

local function _ApplyAutoQuestNoticeColors(line)
    local panel = line.autoQuestPanel
    local backdrop = Questie.db.profile.trackerBackdropColor or {0, 0, 0}
    local accent = Questie.db.profile.trackerHeaderAccentColor or {0.16, 0.78, 0.72, 0.9}
    local gold = Questie.db.profile.trackerHeaderTextColor or {1, 0.82, 0}

    panel.background:SetVertexColor(
        math.max(0.01, (tonumber(backdrop[1]) or 0) * 0.55),
        math.max(0.015, (tonumber(backdrop[2]) or 0) * 0.55),
        math.max(0.02, (tonumber(backdrop[3]) or 0) * 0.55),
        0.96
    )
    _SetTextureColor(panel.accent, gold, {1, 0.82, 0, 1})
    for _, edge in pairs(panel.edges) do
        _SetTextureColor(edge, accent, {0.16, 0.78, 0.72, 0.9})
    end
    panel.badge.background:SetVertexColor(0.10, 0.075, 0.01, 0.98)
    panel.badgeText:SetTextColor(tonumber(gold[1]) or 1, tonumber(gold[2]) or 0.82, tonumber(gold[3]) or 0)
    panel.kicker:SetTextColor(tonumber(accent[1]) or 0.16, tonumber(accent[2]) or 0.78, tonumber(accent[3]) or 0.72)
    panel.title:SetTextColor(1, 0.94, 0.70)
    panel.action.background:SetVertexColor(0.055, 0.065, 0.078, 0.98)
    _SetTextureColor(panel.action.glow, accent, {0.16, 0.78, 0.72, 0.9})
    for _, edge in pairs(panel.action.edges) do
        _SetTextureColor(edge, accent, {0.16, 0.78, 0.72, 0.9})
    end
    panel.action.label:SetTextColor(tonumber(accent[1]) or 0.16, tonumber(accent[2]) or 0.78, tonumber(accent[3]) or 0.72)
    panel.accept.background:SetVertexColor(
        math.max(0.025, (tonumber(accent[1]) or 0.16) * 0.18),
        math.max(0.035, (tonumber(accent[2]) or 0.78) * 0.18),
        math.max(0.035, (tonumber(accent[3]) or 0.72) * 0.18),
        0.98
    )
    _SetTextureColor(panel.accept.glow, gold, {1, 0.82, 0, 1})
    for _, edge in pairs(panel.accept.edges) do
        _SetTextureColor(edge, gold, {1, 0.82, 0, 1})
    end
    panel.accept.label:SetTextColor(tonumber(gold[1]) or 1, tonumber(gold[2]) or 0.82, tonumber(gold[3]) or 0)
end

local function _StartAutoQuestNoticeAnimations()
    for _, line in ipairs(autoQuestRenderedLines) do
        if line.autoQuestNeedsIntro and line.autoQuestPanel and line.autoQuestTargetHeight then
            line.autoQuestNeedsIntro = nil
            local panel = line.autoQuestPanel
            local targetHeight = line.autoQuestTargetHeight
            line:SetHeight(1)
            panel:SetHeight(1)
            panel:SetAlpha(0)
            panel.introElapsed = 0
            panel:SetScript("OnUpdate", function(self, elapsed)
                if not line.isAutoQuestNotice or line.autoQuestPanel ~= self then
                    self:SetScript("OnUpdate", nil)
                    return
                end

                self.introElapsed = self.introElapsed + elapsed
                local progress = math.min(1, self.introElapsed / AUTO_QUEST_NOTICE_ANIMATION_TIME)
                local eased = 1 - ((1 - progress) * (1 - progress) * (1 - progress))
                local height = math.max(1, targetHeight * eased)
                line:SetHeight(height)
                self:SetHeight(height)
                self:SetAlpha(math.min(1, progress * 1.8))
                if progress >= 1 then
                    line:SetHeight(targetHeight)
                    self:SetHeight(targetHeight)
                    self:SetAlpha(1)
                    self:SetScript("OnUpdate", nil)
                end
            end)
        end
    end
end

local function _GetAutoQuestRenderedHeight()
    local height = 0
    for _, noticeLine in ipairs(autoQuestRenderedLines) do
        if noticeLine.isAutoQuestNotice and noticeLine:IsShown() then
            height = height + (tonumber(noticeLine.autoQuestTargetHeight) or tonumber(noticeLine:GetHeight()) or 52)
        end
    end
    return height
end

local function _GetAutoQuestMinimumRenderedHeight()
    for _, noticeLine in ipairs(autoQuestRenderedLines) do
        if noticeLine.isAutoQuestNotice and noticeLine:IsShown() then
            return tonumber(noticeLine.autoQuestTargetHeight) or tonumber(noticeLine:GetHeight()) or 52
        end
    end
    return 0
end

local function _GetDisplayedAutoQuestId()
    if type(_G.GetQuestID) == "function" then
        local ok, questId = pcall(_G.GetQuestID)
        if ok then
            return tonumber(questId)
        end
    end
end

local function _ClearAutoQuestOpeningState(questId)
    if not questId or autoQuestOpeningQuestId == questId then
        autoQuestOpeningQuestId = nil
        autoQuestOpeningShouldAccept = false
        autoQuestOpeningAutomatic = false
    end
end

local function _FinishAutoQuestPresentationFailure(questId, offer, message)
    local isAutomatic = autoQuestOpeningAutomatic
    if _IsPlayerOnAutoQuest(questId) then
        _RemoveAutoQuestOffer(questId)
    elseif offer and autoQuestOffers[questId] == offer then
        offer.acceptPending = nil
    end
    _ClearAutoQuestOpeningState(questId)
    _RequestAutoQuestNoticeRefresh()
    if message and not isAutomatic then
        Questie:Print(message)
    end
    _ScheduleNextAutoQuestAutoAccept()
end

local function _BeginAutoQuestPresentation(questId, shouldAccept, isAutomatic)
    local offer = autoQuestOffers[questId]
    if not offer or autoQuestOpeningQuestId then
        return false
    end

    offer.presentationSerial = (offer.presentationSerial or 0) + 1
    local serial = offer.presentationSerial
    offer.acceptPending = shouldAccept and true or nil
    autoQuestOpeningQuestId = questId
    autoQuestOpeningShouldAccept = shouldAccept and true or false
    autoQuestOpeningAutomatic = isAutomatic and true or false
    _RequestAutoQuestNoticeRefresh()

    -- The native WatchFrame button is Ascension's authoritative opener. Direct
    -- ShowQuestOffer retries cover offers captured before that button exists.
    _RequestAutoQuestOfferDisplay(questId, true)
    for _, retry in ipairs({{0.15, false}, {0.50, true}, {1.00, false}}) do
        C_Timer.After(retry[1], function()
            if autoQuestOpeningQuestId == questId and offer.presentationSerial == serial
            then
                _RequestAutoQuestOfferDisplay(questId, retry[2])
            end
        end)
    end
    C_Timer.After(2, function()
        if autoQuestOpeningQuestId == questId and offer.presentationSerial == serial
        then
            local action = shouldAccept and "accept" or "open"
            _FinishAutoQuestPresentationFailure(
                questId,
                offer,
                "|cffff5555The server did not " .. action .. " auto-provided quest " .. tostring(questId) .. ".|r"
            )
        end
    end)
    return true
end

_HandlePresentedAutoQuestDetail = function()
    local questId = autoQuestOpeningQuestId
    if not questId then
        return false
    end

    local displayedQuestId = _GetDisplayedAutoQuestId()
    if displayedQuestId and displayedQuestId > 0 and displayedQuestId ~= questId then
        return false
    end

    local offer = autoQuestOffers[questId]
    local title = type(GetTitleText) == "function" and _TrimAutoQuestText(GetTitleText())
    if offer and title then
        offer.title = title
        offer.titleHint = title
        offer.titleIsFallback = nil
    end

    if not autoQuestOpeningShouldAccept then
        _DismissPendingAutoQuestPopup(questId)
        _RemoveAutoQuestOffer(questId)
        _ClearAutoQuestOpeningState(questId)
        _RequestAutoQuestNoticeRefresh()
        _ScheduleNextAutoQuestAutoAccept()
        return true
    end

    if type(AcceptQuest) ~= "function" then
        _FinishAutoQuestPresentationFailure(
            questId,
            offer,
            "|cffff5555Unable to accept auto-provided quest " .. tostring(questId) .. ": AcceptQuest is unavailable.|r"
        )
        return true
    end

    local accepted = pcall(AcceptQuest)
    if not accepted then
        _FinishAutoQuestPresentationFailure(
            questId,
            offer,
            "|cffff5555The server rejected the accept action for quest " .. tostring(questId) .. ".|r"
        )
        return true
    end

    _ClearAutoQuestOpeningState(questId)
    C_Timer.After(0, _SweepAcceptedAutoQuestOffers)
    C_Timer.After(0.25, _SweepAcceptedAutoQuestOffers)
    C_Timer.After(1, function()
        if offer and autoQuestOffers[questId] == offer then
            if _IsPlayerOnAutoQuest(questId) then
                _DismissPendingAutoQuestPopup(questId)
                _RemoveAutoQuestOffer(questId)
            else
                offer.acceptPending = nil
            end
            _RequestAutoQuestNoticeRefresh()
        end
        _ScheduleNextAutoQuestAutoAccept()
    end)
    return true
end

_ScheduleNextAutoQuestAutoAccept = function()
    if autoQuestOpeningQuestId then
        return
    end

    for _, questId in ipairs(autoQuestOfferOrder) do
        local offer = autoQuestOffers[questId]
        if offer and not offer.acceptPending and not offer.autoAcceptAttempted
            and not offer.autoAcceptScheduled and _ShouldAutoAcceptAutoQuest(questId, offer)
        then
            offer.autoAcceptScheduled = true
            C_Timer.After(0, function()
                if autoQuestOffers[questId] ~= offer then
                    return
                end
                offer.autoAcceptScheduled = nil
                if autoQuestOpeningQuestId or not _ShouldAutoAcceptAutoQuest(questId, offer) then
                    return
                end
                offer.autoAcceptAttempted = true
                QuestieTracker:AcceptAutoQuestOffer(questId, true)
            end)
            return
        end
    end
end

function QuestieTracker:OpenAutoQuestOffer(questId)
    questId = tonumber(questId)
    if not questId or not autoQuestOffers[questId] or autoQuestOpeningQuestId then
        return false
    end
    return _BeginAutoQuestPresentation(questId, false, false)
end

function QuestieTracker:AcceptAutoQuestOffer(questId, isAutomatic)
    questId = tonumber(questId)
    local offer = questId and autoQuestOffers[questId]
    if not offer or offer.acceptPending or autoQuestOpeningQuestId then
        return false
    end
    if _IsPlayerOnAutoQuest(questId) then
        _RemoveAutoQuestOffer(questId)
        _RequestAutoQuestNoticeRefresh()
        return true
    end
    if isAutomatic and not _ShouldAutoAcceptAutoQuest(questId, offer) then
        return false
    end
    if type(AcceptQuest) ~= "function" then
        if not isAutomatic then
            Questie:Print("|cffff5555Unable to accept auto-provided quest " .. tostring(questId) .. ": AcceptQuest is unavailable.|r")
        end
        return false
    end
    return _BeginAutoQuestPresentation(questId, true, isAutomatic)
end

function QuestieTracker:SetAutoQuestNoticesEnabled(enabled)
    Questie.db.profile.trackerAutoQuestNotices = enabled and true or false
    if not enabled then
        autoQuestNativeSuppressionSuspended = true
        _RestoreNativeAutoQuestDefaults()
    else
        autoQuestNativeSuppressionSuspended = false
        _ScanVisibleAutoQuestOffers(true)
    end
    _RequestAutoQuestNoticeRefresh()
end

function QuestieTracker:SetAutoQuestHideNative(enabled)
    Questie.db.profile.trackerAutoQuestHideNative = enabled and true or false
    if not enabled then
        autoQuestNativeSuppressionSuspended = true
        _RestoreNativeAutoQuestDefaults()
    else
        autoQuestNativeSuppressionSuspended = false
        autoQuestSuppressionScanNeeded = true
    end
    _RequestAutoQuestNoticeRefresh()
end

function QuestieTracker:RefreshAutoQuestAutoAccept()
    _ScheduleNextAutoQuestAutoAccept()
end

function QuestieTracker:RestoreAutoQuestNativeDefaults()
    autoQuestNativeSuppressionSuspended = true
    _RestoreNativeAutoQuestDefaults()
end

_RequestAutoQuestNoticeRefresh = function()
    if autoQuestRefreshScheduled then
        return
    end
    autoQuestRefreshScheduled = true
    C_Timer.After(0, function()
        autoQuestRefreshScheduled = false
        if not QuestieTracker.started then
            return
        end
        QuestieCombatQueue:Queue(function()
            if QuestieTracker.started then
                QuestieTracker:Update(true)
            end
        end)
    end)
end

local function _NormalizeZoneName(zoneName)
    zoneName = tostring(zoneName or "")
    zoneName = string.gsub(zoneName, "^%s*(.-)%s*$", "%1")
    return string.lower(zoneName)
end

local function _IsCurrentTrackerZone(zoneName)
    local target = _NormalizeZoneName(zoneName)
    if target == "" then
        return false
    end

    local zoneGetters = {}
    if type(GetZoneText) == "function" then
        table.insert(zoneGetters, GetZoneText)
    end
    if type(GetRealZoneText) == "function" then
        table.insert(zoneGetters, GetRealZoneText)
    end
    if type(GetSubZoneText) == "function" then
        table.insert(zoneGetters, GetSubZoneText)
    end
    if type(GetMinimapZoneText) == "function" then
        table.insert(zoneGetters, GetMinimapZoneText)
    end

    for _, getter in ipairs(zoneGetters) do
        if type(getter) == "function" and _NormalizeZoneName(getter()) == target then
            return true
        end
    end

    return false
end

local function _AreFramePointsEqual(savedPoint, frame)
    if not savedPoint or not frame or not frame.GetPoint then
        return false
    end

    local point, relativeTo, relativePoint, xOffset, yOffset = frame:GetPoint()
    if not point then
        return false
    end

    return savedPoint[1] == point
        and savedPoint[2] == relativeTo
        and savedPoint[3] == relativePoint
        and math.abs((tonumber(savedPoint[4]) or 0) - (tonumber(xOffset) or 0)) <= 0.5
        and math.abs((tonumber(savedPoint[5]) or 0) - (tonumber(yOffset) or 0)) <= 0.5
end

function QuestieTracker.Initialize()
    if QuestieTracker.started then
        -- The Tracker was already initialized, so we don't need to do it again.
        return
    end

    -- These values might also be accessed by other modules, so we need to make sure they exist. Even when the Tracker is disabled
    if (not Questie.db.char.TrackerHiddenQuests) then
        Questie.db.char.TrackerHiddenQuests = {}
    end
    if (not Questie.db.char.TrackerHiddenObjectives) then
        Questie.db.char.TrackerHiddenObjectives = {}
    end
    if (not Questie.db.char.TrackedQuests) then
        Questie.db.char.TrackedQuests = {}
    end
    if (not Questie.db.char.AutoUntrackedQuests) then
        Questie.db.char.AutoUntrackedQuests = {}
    end
    if (not Questie.db.char.collapsedZones) then
        Questie.db.char.collapsedZones = {}
    end
    if (not Questie.db.char.minAllQuestsInZone) then
        Questie.db.char.minAllQuestsInZone = {}
    end
    if (not Questie.db.char.collapsedQuests) then
        Questie.db.char.collapsedQuests = {}
    end
    if (not Questie.db.char.autoCollapsedQuests) then
        Questie.db.char.autoCollapsedQuests = {}
    end
    if (not Questie.db.char.trackedAchievementIds) then
        Questie.db.char.trackedAchievementIds = {}
    end
    if (not Questie.db.profile.TrackerWidth) then
        Questie.db.profile.TrackerWidth = 0
    end
    if (not Questie.db.profile.TrackerHeight) then
        Questie.db.profile.TrackerHeight = 0
    end
    if (not Questie.db.profile.trackerSetpoint) then
        Questie.db.profile.trackerSetpoint = "TOPLEFT"
    end
    if (not Questie.db.profile.trackerQuestItemButtonPosition) then
        Questie.db.profile.trackerQuestItemButtonPosition = "outsideLeft"
    end
    if (not Questie.db.char.trackerViewMode) then
        Questie.db.char.trackerViewMode = "quests"
    end

    if (not Questie.db.profile.trackerEnabled) then
        -- The Tracker is disabled, no need to continue
        return
    end

    -- Initialize tracker frames
    trackerBaseFrame = TrackerBaseFrame.Initialize()
    trackerHeaderFrame = TrackerHeaderFrame.Initialize(trackerBaseFrame)
    trackerQuestFrame = TrackerQuestFrame.Initialize(trackerBaseFrame, trackerHeaderFrame)

    -- Initialize tracker functions
    TrackerLinePool.Initialize(trackerQuestFrame)
    TrackerFadeTicker.Initialize(trackerBaseFrame, trackerHeaderFrame)
    QuestieTracker.started = true

    -- Initialize hooks
    QuestieTracker:HookBaseTracker()
    _InitializeAutoQuestNoticeHooks()

    -- Insures all other data we're getting from other addons and WoW is loaded. There are edge
    -- cases where Questie loads too fast before everything else is available.
    C_Timer.After(1.0, function()
        -- Hide frames during startup
        if QuestieTracker.alreadyHooked then
            if Questie.db.profile.stickyDurabilityFrame then DurabilityFrame:Hide() end
            if TrackerUtils:IsVoiceOverLoaded() then VoiceOverFrame:Hide() end
        end

        -- Flip some Dugi Guides options to prevent weird behavior
        if IsAddOnLoaded("DugisGuideViewerZ") then
            -- Turns off "Show Quest Objectives - Display quest objectives in small/anchored frame instead of the watch frame"
            DugisGuideViewer:SetDB(false, 39) -- DGV_OBJECTIVECOUNTER

            -- Turns off "Auto Quest Tracking - Automatically add quest to the Objective Tracker on accept or objective update"
            DugisGuideViewer:SetDB(false, 78) -- DGV_AUTO_QUEST_TRACK

            -- Turns on "Clear Final Waypoint - Always clear the last waypoint on reach"
            DugisGuideViewer:SetDB(true, 1006) -- DGV_CLEAR_FINAL_WAYPOINT
        end

        -- Quest Focus Feature
        if Questie.db.char.TrackerFocus then
            local focusType = type(Questie.db.char.TrackerFocus)
            if focusType == "number" then
                TrackerUtils:FocusQuest(Questie.db.char.TrackerFocus)
                QuestieQuest:ToggleNotes(false)
            elseif focusType == "string" then
                local questId, objectiveIndex = string.match(Questie.db.char.TrackerFocus, "(%d+) (%d+)")
                TrackerUtils:FocusObjective(questId, objectiveIndex)
                QuestieQuest:ToggleNotes(false)
            end
        end

        QuestieCombatQueue:Queue(function()
            -- Hides tracker during a login or reloadUI
            if Questie.db.profile.hideTrackerInDungeons and IsInInstance() then
                QuestieTracker:Collapse()
            end

            -- Sync and populate the QuestieTracker - this should only run when a player has loaded
            -- Questie for the first time or when Re-enabling the QuestieTracker after it's disabled.

            -- The questsWatched variable is populated by the Unhooked GetNumQuestWatches(). If Questie
            -- is enabled, this is always 0 unless it's run with a true var RE:GetNumQuestWatches(true).
            if questsWatched > 0 then
                -- When a quest is removed from the Watch Frame, the questIndex can change so we need to snag
                -- the entire list and build a temp table with QuestIDs instead to ensure we remove them all.
                local tempQuestIDs = {}
                for i = 1, questsWatched do
                    local questIndex = GetQuestIndexForWatch(i)
                    if questIndex then
                        local questId = select(8, GetQuestLogTitle(questIndex))
                        if questId then
                            tempQuestIDs[i] = questId
                        end
                    end
                end

                -- Remove quest from the Blizzard Quest Watch and populate the tracker.
                for _, questId in pairs(tempQuestIDs) do
                    local questIndex = GetQuestLogIndexByID(questId)
                    if questIndex then
                        QuestieTracker:AQW_Insert(questIndex, QUEST_WATCH_NO_EXPIRE)
                    end
                end
            end

            -- Look for any QuestID's that don't belong in the Questie.db.char.TrackedQuests or
            -- the Questie.db.char.AutoUntrackedQuests tables. They can get out of sync.
            if Questie.db.profile.autoTrackQuests and Questie.db.char.AutoUntrackedQuests then
                for untrackedQuestId in pairs(Questie.db.char.AutoUntrackedQuests) do
                    if not QuestiePlayer.currentQuestlog[untrackedQuestId] then
                        Questie.db.char.AutoUntrackedQuests[untrackedQuestId] = nil
                    end
                end
            elseif Questie.db.char.TrackedQuests then
                for trackedQuestId in pairs(Questie.db.char.TrackedQuests) do
                    if not QuestiePlayer.currentQuestlog[trackedQuestId] then
                        Questie.db.char.TrackedQuests[trackedQuestId] = nil
                    end
                end
            end

            -- The trackedAchievements variable is populated by GetTrackedAchievements(). If Questie
            -- is enabled, this will always return nil so we need to save it before we enable Questie.
            if Questie.IsWotlk or QuestieCompat.Is335 then
                if #trackedAchievements > 0 then
                    local tempAchieves = trackedAchievements

                    -- Remove achievement from the Blizzard Quest Watch and populate the tracker.
                    for _, achieveId in pairs(tempAchieves) do
                        if achieveId then
                            RemoveTrackedAchievement(achieveId)
                            Questie.db.char.trackedAchievementIds[achieveId] = true

                            if (not AchievementFrame) then
                                AchievementFrame_LoadUI()
                            end

                            AchievementFrameAchievements_ForceUpdate()
                        end
                    end
                end

                trackedAchievements = { GetTrackedAchievements() }
                WatchFrame_Update()

                -- Sync and populate QuestieTrackers achievement cache
                if Questie.db.char.trackedAchievementIds ~= trackedAchievementIds then
                    for achieveId in pairs(Questie.db.char.trackedAchievementIds) do
                        if Questie.db.char.trackedAchievementIds[achieveId] == true then
                            trackedAchievementIds[achieveId] = true
                        end
                    end
                end
            else
                QuestWatch_Update()
            end

            if QuestLogFrame:IsShown() then QuestLog_Update() end
            QuestieTracker:Update()
        end)
    end)
end

function QuestieTracker:ResetLocation()
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:ResetLocation]")
    trackerHeaderFrame.trackedQuests:SetMode(1) -- maximized
    Questie.db.char.isTrackerExpanded = true
    Questie.db.char.AutoUntrackedQuests = {}
    Questie.db.profile.TrackerLocation = nil
    Questie.db.char.collapsedQuests = {}
    Questie.db.char.autoCollapsedQuests = {}
    Questie.db.char.collapsedZones = {}
    Questie.db.profile.TrackerWidth = 0
    Questie.db.profile.TrackerHeight = 0

    trackerBaseFrame:SetSize(25, 25)
    TrackerBaseFrame:SetSafePoint()

    QuestieTracker:Update()
end

function QuestieTracker:ResetDurabilityFrame()
    if durabilityInitialPosition then
        -- Only reset if it's been moved from it's default position set by Blizzard
        if not _AreFramePointsEqual(durabilityInitialPosition, DurabilityFrame) then
            Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:ResetDurabilityFrame]")

            -- Resets Durability Frame back to it's default position
            DurabilityFrame:ClearAllPoints()
            DurabilityFrame:SetPoint(unpack(durabilityInitialPosition))

            local numAlerts = 0

            for i = 1, #INVENTORY_ALERT_STATUS_SLOTS do
                if GetInventoryAlertStatus(i) > 0 then
                    numAlerts = numAlerts + 1
                end
            end

            -- Check the alert status and reset visibility
            if numAlerts > 0 then
                DurabilityFrame:Show()
            else
                if DurabilityFrame:IsShown() then
                    DurabilityFrame:Hide()
                end
            end
        end
    end
end

function QuestieTracker:UpdateDurabilityFrame()
    if QuestieTracker.started and Questie.db.profile.trackerEnabled and Questie.db.profile.stickyDurabilityFrame then
        if Questie.db.char.isTrackerExpanded and QuestieTracker:HasQuest() then
            local numAlerts = 0

            for i = 1, #INVENTORY_ALERT_STATUS_SLOTS do
                if GetInventoryAlertStatus(i) > 0 then
                    numAlerts = numAlerts + 1
                end
            end

            if numAlerts > 0 then
                -- screen width accounting for scale
                local screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale()
                -- middle of the frame, first return is x value, second return is the y value
                local trackerFrameX = trackerBaseFrame:GetCenter()

                DurabilityFrame:ClearAllPoints()
                DurabilityFrame:SetClampedToScreen(true)
                DurabilityFrame:SetFrameStrata("MEDIUM")
                DurabilityFrame:SetFrameLevel(0)

                if trackerFrameX <= (screenWidth / 2) then
                    DurabilityFrame:SetPoint("LEFT", trackerBaseFrame, "TOPRIGHT", 0, -40)
                else
                    DurabilityFrame:SetPoint("RIGHT", trackerBaseFrame, "TOPLEFT", 0, -40)
                end

                DurabilityFrame:Show()
            else
                if DurabilityFrame:IsShown() then
                    DurabilityFrame:Hide()
                end
            end

            if TrackerBaseFrame.isSizing == true or TrackerBaseFrame.isMoving == true then
                Questie:Debug(Questie.DEBUG_SPAM, "[QuestieTracker:UpdateDurabilityFrame]")
            else
                Questie:Debug(Questie.DEBUG_INFO, "[QuestieTracker:UpdateDurabilityFrame]")
            end
        else
            QuestieTracker:ResetDurabilityFrame()
        end
    end
end

function QuestieTracker:ResetVoiceOverFrame()
    if voiceOverInitialPosition then
        if not _AreFramePointsEqual(voiceOverInitialPosition, VoiceOverFrame) then
            Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:ResetVoiceOverFrame]")

            VoiceOverFrame:ClearAllPoints()
            VoiceOverFrame:SetPoint(unpack(voiceOverInitialPosition))

            VoiceOverFrame:SetClampedToScreen(true)
            VoiceOverFrame:SetFrameStrata("MEDIUM")
            VoiceOverFrame:SetFrameLevel(0)
            VoiceOver.Addon.db.profile.SoundQueueUI.LockFrame = false
            VoiceOver.SoundQueueUI:RefreshConfig()

            if VoiceOverFrame:IsShown() then
                VoiceOver.SoundQueue:RemoveAllSoundsFromQueue()
                VoiceOverFrame:Hide()
            end
        end
    end
end

function QuestieTracker:UpdateVoiceOverFrame()
    if TrackerUtils:IsVoiceOverLoaded() then
        if QuestieTracker.started and Questie.db.profile.trackerEnabled and Questie.db.profile.stickyVoiceOverFrame then
            if Questie.db.char.isTrackerExpanded and QuestieTracker:HasQuest() then
                -- screen width accounting for scale
                local screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale()
                -- middle of the frame, first return is x value, second return is the y value
                local trackerFrameX = trackerBaseFrame:GetCenter()

                VoiceOverFrame:SetClampedToScreen(true)
                VoiceOverFrame:SetFrameStrata("MEDIUM")
                VoiceOverFrame:SetFrameLevel(0)

                local verticalOffSet

                if Questie.db.profile.stickyDurabilityFrame then
                    if DurabilityFrame:IsVisible() then
                        verticalOffSet = -125
                    else
                        verticalOffSet = -7
                    end
                end

                if trackerFrameX <= (screenWidth / 2) then
                    VoiceOverFrame:ClearAllPoints()
                    VoiceOverFrame:SetPoint("TOPLEFT", trackerBaseFrame, "TOPRIGHT", 15, verticalOffSet)
                else
                    VoiceOverFrame:ClearAllPoints()
                    VoiceOverFrame:SetPoint("TOPRIGHT", trackerBaseFrame, "TOPLEFT", -15, verticalOffSet)
                end

                VoiceOverFrame:SetWidth(500)
                VoiceOverFrame:SetHeight(120)
                VoiceOver.Addon.db.profile.SoundQueueUI.LockFrame = true
                VoiceOver.SoundQueueUI:RefreshConfig()
                VoiceOver.SoundQueueUI:UpdateSoundQueueDisplay()

                if TrackerBaseFrame.isSizing == true or TrackerBaseFrame.isMoving == true then
                    Questie:Debug(Questie.DEBUG_SPAM, "[QuestieTracker:UpdateVoiceOverFrame]")
                else
                    Questie:Debug(Questie.DEBUG_INFO, "[QuestieTracker:UpdateVoiceOverFrame]")
                end
            else
                QuestieTracker:ResetVoiceOverFrame()
            end
        end
    end
end

-- If the player loots a "Quest Item" then this triggers a Tracker Update so the
-- Quest Item Button can be switched on and appear in the tracker.
---@param text string
function QuestieTracker:QuestItemLooted(text)
    local playerLoot = strmatch(text, "You receive ") or strmatch(text, "You create")
    local itemId = tonumber(string.match(text, "item:(%d+)"))

    if playerLoot and itemId then
        local _, _, _, _, _, itemType, _, _, _, _, _, classID = GetItemInfo(itemId)
        local usableItem = TrackerUtils:IsQuestItemUsable(itemId)

        if (itemType == "Quest" or classID == 12 or QuestieDB.QueryItemSingle(itemId, "class") == 12) and usableItem then
            Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker] - Quest Item Detected (itemId) - ", itemId)

            C_Timer.After(0.25, function()
                _QuestEventHandler:UpdateAllQuests()
                Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker] - Callback --> QuestEventHandler:UpdateAllQuests()")
            end)

            QuestieCombatQueue:Queue(function()
                C_Timer.After(0.5, function()
                    QuestieTracker:Update()
                end)
            end)
        end
    end
end

function QuestieTracker:HasQuest()
    if _HasReadyAutoQuestOffers() then
        return true
    end

    if lfgMirrorSnapshot then
        return true
    end

    local hasQuest

    if (GetNumQuestWatches(true) == 0) then
        if Questie.IsWotlk or QuestieCompat.Is335 then
            if (GetNumTrackedAchievements(true) == 0) then
                hasQuest = false
            else
                hasQuest = true
            end
        else
            hasQuest = false
        end
    else
        if not Questie.db.profile.trackerShowCompleteQuests then
            local completedQuests = 0
            -- Keep track of the number of completed quests
            for questId, quest in pairs(QuestiePlayer.currentQuestlog) do
                if not quest then break end
                if quest:IsComplete() == 1 then
                    completedQuests = completedQuests + 1
                end
            end

            -- This hides the Tracker when all tracked Quests are complete
            if completedQuests == GetNumQuestWatches(true) then
                hasQuest = false
            else
                hasQuest = true
            end
        else
            hasQuest = true
        end
    end

    Questie:Debug(Questie.DEBUG_SPAM, "[QuestieTracker:HasQuest] - ", hasQuest)
    return hasQuest
end

function QuestieTracker:HasAutoQuestNotice()
    return _HasReadyAutoQuestOffers()
end

function QuestieTracker:Enable()
    -- Update the questsWatched var before we re-enable
    if questsWatched == 0 then
        questsWatched = GetNumQuestWatches()
    end

    Questie.db.profile.trackerEnabled = true
    QuestieTracker.started = false
    QuestieTracker.Initialize()
    --QuestieCompat.QuestieTracker_Initialize(trackerQuestFrame)
    QuestieTracker:Update()
    ReloadUI()
end

function QuestieTracker:Disable()
    Questie.db.profile.trackerEnabled = false
    autoQuestNativeSuppressionSuspended = true
    _RestoreNativeLFGTracker()
    _RestoreNativeAutoQuestDefaults()
    lfgMirrorSnapshot = nil
    QuestieTracker:ResetDurabilityFrame()
    QuestieTracker:ResetVoiceOverFrame()
    Questie.db.char.TrackedQuests = {}
    Questie.db.char.AutoUntrackedQuests = {}

    if Questie.IsWotlk or QuestieCompat.Is335 then
        Questie.db.char.trackedAchievementIds = {}
        trackedAchievementIds = {}
    end

    QuestieTracker:Unhook()
    QuestieTracker:Update()
    ReloadUI()
end

-- Function for the Slash handler
function QuestieTracker:Toggle()
    if Questie.db.profile.trackerEnabled then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:Toggle] - Tracker Disabled.")
        Questie.db.profile.trackerEnabled = false
        autoQuestNativeSuppressionSuspended = true
        _RestoreNativeLFGTracker()
        _RestoreNativeAutoQuestDefaults()
        lfgMirrorSnapshot = nil
    else
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:Toggle] - Tracker Enabled.")
        Questie.db.profile.trackerEnabled = true
        autoQuestNativeSuppressionSuspended = false
    end
    QuestieTracker:Update()
end

-- Minimizes the QuestieTracker
function QuestieTracker:Collapse()
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:Collapse]")
    if trackerHeaderFrame and Questie.db.char.isTrackerExpanded then
        TrackerHeaderFrame:ToggleExpanded()
    end
end

-- Maximizes the QuestieTracker
function QuestieTracker:Expand()
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:Expand]")
    if trackerHeaderFrame and (not Questie.db.char.isTrackerExpanded) then
        TrackerHeaderFrame:ToggleExpanded()
    end
end

function QuestieTracker:Update(forceUpdate)
    -- Prevents calling the tracker too often, especially when the QuestieCombatQueue empties after combat ends
    local now = GetTime()
    if (not QuestieTracker.started) or InCombatLockdown() or ((not forceUpdate) and (now - lastTrackerUpdate) < 0.1) then
        return
    end

    lastTrackerUpdate = now

    -- Tracker has started but not enabled, hide the frames
    if (not Questie.db.profile.trackerEnabled or QuestieTracker.disableHooks == true) then
        _RestoreNativeLFGTracker()
        _RestoreNativeAutoQuestDefaults()
        lfgMirrorSnapshot = nil
        if trackerBaseFrame and trackerBaseFrame:IsShown() then
            QuestieCombatQueue:Queue(function()
                if Questie.db.profile.stickyDurabilityFrame then
                    QuestieTracker:ResetDurabilityFrame()
                end

                if Questie.db.profile.stickyVoiceOverFrame then
                    QuestieTracker:ResetVoiceOverFrame()
                end

                trackerBaseFrame:Hide()
            end)
        end
        return
    end

    QuestieTracker:RefreshLFGObjectiveMirror()

    if TrackerBaseFrame.isSizing == true or TrackerBaseFrame.isMoving == true or TrackerUtils.FilterProximityTimer == true then
        Questie:Debug(Questie.DEBUG_SPAM, "[QuestieTracker:Update]")
    else
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:Update]")
    end

    TrackerHeaderFrame:Update()
    TrackerQuestFrame:Update()
    TrackerBaseFrame:Update()
    TrackerLinePool.ResetLinesForChange()
    TrackerLinePool.ResetButtonsForChange()
    lfgRenderedLines = {}
    autoQuestRenderedLines = {}

    -- This is needed so the Tracker can also decrease its width
    trackerLineWidth = 0

    -- Setup local QuestieTracker:Update vars
    local trackerFontSizeZone = TrackerFonts:GetZoneFontSize()
    local trackerFontSizeQuest = TrackerFonts:GetQuestFontSize()
    local trackerFontSizeObjective = TrackerFonts:GetObjectiveFontSize()
    local trackerItemButtonGap = 2
    local questPadding = math.max(0, tonumber(Questie.db.profile.trackerQuestPadding) or 0)
    local trackerItemButtonOutsideGap = math.max(0, tonumber(Questie.db.profile.trackerQuestItemGutter) or 4)
    local trackItemButtonsOutside = (Questie.db.profile.trackerQuestItemButtonPosition or "outsideLeft") == "outsideLeft"
    local questMarginLeft = trackerMarginLeft + math.max(0, tonumber(Questie.db.profile.trackerQuestTitleInset) or 0)
    -- Keep the small gap that followed the old dash, without reserving a full dash column.
    local objectiveMarginLeft = questMarginLeft + 2 + math.max(0, tonumber(Questie.db.profile.trackerObjectiveInset) or 0)
    local zoneMarginLeft = trackerMarginLeft
    local titleMarginLeft = objectiveMarginLeft
    local zoneSpacing = tonumber(Questie.db.profile.trackerZoneSpacing) or 0
    local zoneHeaderColor = Questie.db.profile.trackerZoneHeaderColor or { 1.0, 0.0, 1.0 }
    local trackerZoneHeaderColor = string.format(
        "|cff%02x%02x%02x",
        math.floor((tonumber(zoneHeaderColor[1]) or 1.0) * 255 + 0.5),
        math.floor((tonumber(zoneHeaderColor[2]) or 0.0) * 255 + 0.5),
        math.floor((tonumber(zoneHeaderColor[3]) or 1.0) * 255 + 0.5)
    )
    local questItemButtonSize = 12 + trackerFontSizeQuest
    local objectiveColor = Questie.db.profile.trackerColorObjectives
    local showZoneDividers = Questie.db.profile.trackerZoneDividersEnabled
    local zoneDividerColor = Questie.db.profile.trackerZoneDividerColor or { 0.16, 0.78, 0.72, 0.28 }
    local zoneDividerColorR = tonumber(zoneDividerColor[1]) or 0.16
    local zoneDividerColorG = tonumber(zoneDividerColor[2]) or 0.78
    local zoneDividerColorB = tonumber(zoneDividerColor[3]) or 0.72
    local zoneDividerColorA = tonumber(zoneDividerColor[4]) or 0.28
    local zoneDividerTopPadding = math.max(0, zoneSpacing)
    local questTitleBottomPadding = math.max(0, tonumber(Questie.db.profile.trackerQuestTitlePadding) or 1)
    local lfgSnapshot = lfgMirrorSnapshot
    local lfgPosition = math.max(0, math.min(25, math.floor((tonumber(Questie.db.profile.trackerLFGObjectivePosition) or 0) + 0.5)))
    local lfgRendered = false
    local lfgZoneBlocksRendered = 0
    local lfgHeaderMarginLeft = math.max(zoneMarginLeft, 7)
    local lfgObjectiveMarginLeft = math.max(objectiveMarginLeft, 9)
    local lfgHeaderBgR, lfgHeaderBgG, lfgHeaderBgB, lfgHeaderBgA = _GetLFGProfileColor(
        "trackerHeaderBackgroundColor", 0, 0, 0, 0.5
    )
    local lfgHeaderTextR, lfgHeaderTextG, lfgHeaderTextB = _GetLFGProfileColor(
        "trackerHeaderTextColor", 1, 0.82, 0, 1
    )
    local lfgAccentR, lfgAccentG, lfgAccentB, lfgAccentA = _GetLFGProfileColor(
        "trackerHeaderAccentColor", 0.16, 0.78, 0.72, 0.38
    )
    local lfgBodyBgR, lfgBodyBgG, lfgBodyBgB = _GetLFGProfileColor(
        "trackerBackdropColor", 0, 0, 0, 1
    )
    local line
    local zoneCheck

    local function GetInsideQuestItemInset(visibleButtonCount)
        if trackItemButtonsOutside or not visibleButtonCount or visibleButtonCount < 1 then
            return 0
        end

        return trackerItemButtonOutsideGap + (visibleButtonCount * questItemButtonSize) + (math.max(0, visibleButtonCount - 1) * trackerItemButtonGap)
    end

    local function AttachQuestItemButton(button, parentLine, slotIndex)
        button:ClearAllPoints()

        if trackItemButtonsOutside then
            local outsideOffset = questItemButtonSize + trackerItemButtonOutsideGap + ((slotIndex - 1) * (questItemButtonSize + trackerItemButtonGap))
            button:SetParent(trackerBaseFrame)
            button:SetPoint("TOPRIGHT", parentLine, "TOPLEFT", -outsideOffset, 0)
        else
            local insideOffset = trackerItemButtonOutsideGap + ((slotIndex - 1) * (questItemButtonSize + trackerItemButtonGap))
            button:SetParent(parentLine)
            button:SetPoint("TOPLEFT", parentLine, "TOPLEFT", insideOffset, 0)
        end
    end

    local function ConfigureZoneDivider(line, shouldShow)
        if not line or not line.separator then
            return 0
        end

        line.separator:Hide()
        line.zoneTopInset = 0
        if not shouldShow then
            return 0
        end

        line.separator:ClearAllPoints()
        line.separator:SetPoint("TOPLEFT", line, "TOPLEFT", zoneMarginLeft, 0)
        line.separator:SetPoint("TOPRIGHT", line, "TOPRIGHT", -trackerMarginRight, 0)
        line.separator:SetVertexColor(zoneDividerColorR, zoneDividerColorG, zoneDividerColorB, zoneDividerColorA)
        line.separator:Show()
        line.zoneTopInset = zoneDividerTopPadding

        return zoneDividerTopPadding
    end

    local function RememberLineLayout(line, leftInset, fontSize, bottomPadding)
        if not line then
            return
        end

        line.contentLeftInset = leftInset
        line.contentFontSize = fontSize
        line.contentBottomPadding = bottomPadding or 0
    end

    local function SkinLFGLine(targetLine, isHeader)
        if not targetLine.lfgSectionBackground then
            targetLine.lfgSectionBackground = targetLine:CreateTexture(nil, "BACKGROUND")
            targetLine.lfgSectionBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
        end
        if not targetLine.lfgSectionAccent then
            targetLine.lfgSectionAccent = targetLine:CreateTexture(nil, "BORDER")
            targetLine.lfgSectionAccent:SetTexture("Interface\\Buttons\\WHITE8X8")
        end

        targetLine.lfgSectionBackground:ClearAllPoints()
        targetLine.lfgSectionBackground:SetAllPoints(targetLine)
        if isHeader then
            targetLine.lfgSectionBackground:SetVertexColor(lfgHeaderBgR, lfgHeaderBgG, lfgHeaderBgB, lfgHeaderBgA)
        else
            targetLine.lfgSectionBackground:SetVertexColor(lfgBodyBgR, lfgBodyBgG, lfgBodyBgB, math.min(0.24, math.max(0, lfgHeaderBgA * 0.35)))
        end
        targetLine.lfgSectionBackground:Show()

        targetLine.lfgSectionAccent:ClearAllPoints()
        targetLine.lfgSectionAccent:SetPoint("TOPLEFT", targetLine, "TOPLEFT", 0, 0)
        targetLine.lfgSectionAccent:SetPoint("BOTTOMLEFT", targetLine, "BOTTOMLEFT", 0, 0)
        targetLine.lfgSectionAccent:SetWidth(2)
        targetLine.lfgSectionAccent:SetVertexColor(lfgAccentR, lfgAccentG, lfgAccentB, lfgAccentA)
        targetLine.lfgSectionAccent:Show()
        targetLine.isLFGSectionLine = true
    end

    --- Applies tracker width constraints and multi-line height for a label.
    local function ApplyWrappedTrackerLabel(label, parentLine, marginLeft, labelInset, lineWidthExtra, fontSize)
        local labelWidth = math.max(1, trackerBaseFrame:GetWidth() - labelInset)
        label:SetWidth(labelWidth)
        parentLine:SetWidth(label:GetWidth() + lineWidthExtra)

        local unboundedWidth = label:GetUnboundedStringWidth()
        local numLines = label:GetNumLines()
        local wrappedHeight = label.GetWrappedStringHeight and label:GetWrappedStringHeight() or label:GetStringHeight()
        local widthWithMargins = unboundedWidth + marginLeft + trackerMarginRight

        if numLines > 1 then
            label:SetHeight(math.max(fontSize, wrappedHeight))
            return math.max(trackerMinLineWidth, label:GetWrappedWidth() + lineWidthExtra)
        elseif widthWithMargins < trackerMinLineWidth then
            QuestieTracker:UpdateWidth(widthWithMargins)
            label:SetHeight(fontSize)
            return unboundedWidth + lineWidthExtra
        else
            label:SetHeight(fontSize)
            return unboundedWidth + lineWidthExtra
        end
    end

    --- Renders an indented pfQuest-style objective without the dash column.
    local function ApplyPfQuestObjectiveLine(line, objective, lineLabelWidthQBC, lineLabelBaseFrameQBC, lineWidthQBC, quest, complete)
        local bodyText = QuestieLib:FormatPfQuestTrackerObjectiveBody(objective, quest, complete)
        RememberLineLayout(line, lineWidthQBC, trackerFontSizeObjective, 1)

        -- Keep the body at its existing inset, but remove the visible "-" prefix.
        if line.prefixLabel then
            line.prefixLabel:Hide()
        end

        line.label:ClearAllPoints()
        line.label:SetPoint("TOPLEFT", line, "TOPLEFT", lineWidthQBC, 0)
        line.label:SetText(bodyText)

        local objectiveLabelWidth = math.max(1, trackerBaseFrame:GetWidth() - lineLabelBaseFrameQBC)
        line.label:SetWidth(objectiveLabelWidth)
        line:SetWidth(line.label:GetWidth() + lineWidthQBC)

        local unboundedObjectiveWidth = line.label:GetUnboundedStringWidth()
        local objectiveNumLines = line.label:GetNumLines()
        local wrappedHeight = line.label.GetWrappedStringHeight and line.label:GetWrappedStringHeight() or line.label:GetStringHeight()
        if objectiveNumLines > 1 then
            line.label:SetHeight(math.max(trackerFontSizeObjective, wrappedHeight))
            return math.max(trackerLineWidth, trackerMinLineWidth, line.label:GetWrappedWidth() + lineWidthQBC)
        elseif unboundedObjectiveWidth + lineLabelWidthQBC < trackerMinLineWidth then
            QuestieTracker:UpdateWidth(unboundedObjectiveWidth + lineLabelWidthQBC)
            line.label:SetHeight(trackerFontSizeObjective)
            return math.max(trackerLineWidth, unboundedObjectiveWidth + lineWidthQBC)
        else
            line.label:SetHeight(trackerFontSizeObjective)
            return math.max(trackerLineWidth, unboundedObjectiveWidth + lineWidthQBC)
        end
    end

    local function HideObjectivePrefix(line)
        if line.prefixLabel then
            line.prefixLabel:Hide()
        end
    end

    local function LayoutQuestTitleLine(questLine, visibleButtonCount)
        local leftInset = questMarginLeft + GetInsideQuestItemInset(visibleButtonCount)

        RememberLineLayout(questLine, leftInset, trackerFontSizeQuest, questTitleBottomPadding)
        questLine.expandQuest:Hide()
        questLine.label:ClearAllPoints()
        questLine.label:SetPoint("TOPLEFT", questLine, "TOPLEFT", leftInset, 0)

        trackerLineWidth = math.max(trackerLineWidth, ApplyWrappedTrackerLabel(
            questLine.label,
            questLine,
            leftInset,
            leftInset + trackerMarginRight,
            leftInset,
            trackerFontSizeQuest
        ))
    end

    local function _UpdateAutoQuestNotices()
        if not Questie.db.profile.trackerAutoQuestNotices then
            return
        end

        for _, questId in ipairs(autoQuestOfferOrder) do
            local offer = autoQuestOffers[questId]
            if offer and offer.title then
                line = TrackerLinePool.GetNextLine()
                if not line then
                    return
                end

                _EnsureAutoQuestNoticeWidgets(line)
                line:SetMode("autoQuest")
                line:SetOnClick("none")
                line:SetScript("OnClick", function(self, button)
                    if button == "LeftButton" then
                        QuestieTracker:OpenAutoQuestOffer(self.autoQuestId)
                    end
                end)
                line.expandZone:Hide()
                line.expandQuest:Hide()
                line.criteriaMark:Hide()
                line.playButton:Hide()
                line.separator:Hide()
                line.label:SetFont(TrackerFonts:GetQuestFont(), trackerFontSizeQuest, Questie.db.profile.trackerFontOutline)
                line.label:SetText("AUTO-PROVIDED QUEST  VIEW  ACCEPT")
                line.label:SetHeight(1)
                line.label:Hide()
                line.prefixLabel:Hide()
                line.Quest = nil
                line.Objective = nil
                line.isAutoQuestNotice = true
                line.autoQuestId = questId
                line.autoQuestTitle = offer.title
                line.autoQuestPanel.action.questId = questId
                line.autoQuestPanel.action.label:SetText("VIEW")
                if autoQuestOpeningQuestId then
                    line.autoQuestPanel.action:Disable()
                    line.autoQuestPanel.action:SetAlpha(0.62)
                else
                    line.autoQuestPanel.action:Enable()
                    line.autoQuestPanel.action:SetAlpha(1)
                end
                line.autoQuestPanel.action.pulseEnabled = false
                line.autoQuestPanel.action.pulseTime = 0
                line.autoQuestPanel.accept.questId = questId
                if offer.acceptPending then
                    line.autoQuestPanel.accept.label:SetText("ACCEPTING...")
                    line.autoQuestPanel.accept:Disable()
                    line.autoQuestPanel.accept:SetAlpha(0.62)
                elseif autoQuestOpeningQuestId then
                    line.autoQuestPanel.accept.label:SetText("WAIT...")
                    line.autoQuestPanel.accept:Disable()
                    line.autoQuestPanel.accept:SetAlpha(0.62)
                else
                    line.autoQuestPanel.accept.label:SetText("ACCEPT")
                    line.autoQuestPanel.accept:Enable()
                    line.autoQuestPanel.accept:SetAlpha(1)
                end
                line.autoQuestPanel.accept.pulseEnabled = not offer.acceptPending and not autoQuestOpeningQuestId
                    and Questie.db.profile.trackerAutoQuestNoticeAnimation ~= false
                line.autoQuestPanel.accept.pulseTime = 0
                line.autoQuestPanel:SetScript("OnUpdate", nil)
                line.autoQuestPanel:SetAlpha(1)
                line.autoQuestPanel:Show()
                _ApplyAutoQuestNoticeColors(line)
                line:UpdateAutoQuestNoticeLayout()
                line.autoQuestNeedsIntro = offer.shouldAnimate
                    and Questie.db.profile.trackerAutoQuestNoticeAnimation ~= false
                offer.shouldAnimate = nil
                line:Show()
                autoQuestRenderedLines[#autoQuestRenderedLines + 1] = line
                trackerLineWidth = math.max(trackerLineWidth, trackerMinLineWidth)
            end
        end
    end

    local function _UpdateLFGObjectives()
        if lfgRendered or not lfgSnapshot then
            return
        end

        local lfgRows = lfgSnapshot.rows or {}
        local isCollapsed = Questie.db.char.collapsedZones[LFG_MIRROR_ZONE_KEY]
        local requiredLines = isCollapsed and 1 or (#lfgRows + 1)
        if TrackerLinePool.GetRemainingLineCount() < requiredLines then
            return
        end

        local hasPreviousLine = TrackerLinePool.GetHighestIndex() > 0
        line = TrackerLinePool.GetNextLine()
        if not line then
            return
        end

        local zoneTopInset = hasPreviousLine and zoneSpacing or 0
        local displayTitle = _GetLFGDisplayTitle(lfgSnapshot)

        line:SetMode("zone")
        line:SetOnClick("zone")
        line:SetZone(LFG_MIRROR_ZONE_KEY)
        line.expandQuest:Hide()
        line.criteriaMark:Hide()
        line.playButton:Hide()
        -- This section has its own continuous accent; a zone divider would cross it.
        ConfigureZoneDivider(line, false)
        line.zoneTopInset = zoneTopInset
        RememberLineLayout(line, lfgHeaderMarginLeft, trackerFontSizeZone, 4 + zoneTopInset)
        line.label:ClearAllPoints()
        line.label:SetPoint("TOPLEFT", line, "TOPLEFT", lfgHeaderMarginLeft, -zoneTopInset)

        if isCollapsed then
            line.expandZone:SetMode(0)
            line.label:SetText(_ColorizeLFGMirrorText(displayTitle .. " +", lfgHeaderTextR, lfgHeaderTextG, lfgHeaderTextB))
        else
            line.expandZone:SetMode(1)
            line.label:SetText(_ColorizeLFGMirrorText(displayTitle, lfgHeaderTextR, lfgHeaderTextG, lfgHeaderTextB))
        end

        trackerLineWidth = math.max(trackerLineWidth, ApplyWrappedTrackerLabel(
            line.label,
            line,
            lfgHeaderMarginLeft,
            lfgHeaderMarginLeft + trackerMarginRight,
            lfgHeaderMarginLeft,
            trackerFontSizeZone
        ))

        line.expandZone:ClearAllPoints()
        line.expandZone:SetPoint("TOPLEFT", line.label, "TOPLEFT", 0, 0)
        line.expandZone:SetWidth(line.label:GetWidth())
        line.expandZone:SetHeight(line.label:GetHeight())
        line.expandZone:Show()
        line:SetHeight(line.label:GetHeight() + 4 + zoneTopInset)
        SkinLFGLine(line, true)
        line:Show()
        line.label:Show()
        line.Quest = nil
        line.Objective = nil
        lfgRenderedLines[#lfgRenderedLines + 1] = line
        lfgRendered = true
        zoneCheck = LFG_MIRROR_ZONE_KEY

        if isCollapsed then
            return
        end

        for _, row in ipairs(lfgRows) do
            line = TrackerLinePool.GetNextLine()

            line:SetMode("objective")
            line:SetOnClick("none")
            line:SetQuest(LFG_MIRROR_QUEST)
            line:SetObjective(nil)
            line.expandZone:Hide()
            line.expandQuest:Hide()
            line.criteriaMark:Hide()
            line.playButton:Hide()
            HideObjectivePrefix(line)
            line.label:ClearAllPoints()
            line.label:SetPoint("TOPLEFT", line, "TOPLEFT", lfgObjectiveMarginLeft, 0)
            line.label:SetText(_FormatLFGObjectiveRow(row))

            trackerLineWidth = math.max(trackerLineWidth, ApplyWrappedTrackerLabel(
                line.label,
                line,
                lfgObjectiveMarginLeft,
                lfgObjectiveMarginLeft + trackerMarginRight,
                lfgObjectiveMarginLeft,
                trackerFontSizeObjective
            ))
            RememberLineLayout(line, lfgObjectiveMarginLeft, trackerFontSizeObjective, 1)
            line:SetHeight(line.label:GetHeight() + 1)
            SkinLFGLine(line, false)
            line:Show()
            line.label:Show()
            lfgRenderedLines[#lfgRenderedLines + 1] = line
        end

        if line and line.mode == "objective" then
            line:SetHeight(line.label:GetHeight() + questPadding)
            line.contentBottomPadding = questPadding
        end
    end

    local function _MaybeRenderLFGBeforeNextZone()
        if not lfgRendered and lfgSnapshot and lfgPosition <= lfgZoneBlocksRendered then
            _UpdateLFGObjectives()
        end
        lfgZoneBlocksRendered = lfgZoneBlocksRendered + 1
    end

    _UpdateAutoQuestNotices()

    local sortedQuestIds, questDetails = TrackerUtils:GetSortedQuestIds()

    local firstQuestInZone = false

    local primaryButton = false
    local secondaryButton = false
    local secondaryButtonAlpha

    -- Begin populating the Tracker with Quests
    local _UpdateQuests = function()
        for _, questId in pairs(sortedQuestIds) do
            if not questId then break end

            local quest = questDetails[questId].quest
            local complete = quest:IsComplete()
            local zoneName = questDetails[questId].zoneName
            local remainingSeconds = TrackerQuestTimers:GetRemainingTime(quest, nil, true)
            local timedQuest = (quest.trackTimedQuest or quest.timedBlizzardQuest)

            if (complete ~= 1 or Questie.db.profile.trackerShowCompleteQuests or timedQuest)
                and (Questie.db.profile.autoTrackQuests and not Questie.db.char.AutoUntrackedQuests[questId])
                or (not Questie.db.profile.autoTrackQuests and Questie.db.char.TrackedQuests[questId]) then
                -- Add Quest Zones
                if zoneCheck ~= zoneName then
                    _MaybeRenderLFGBeforeNextZone()
                    firstQuestInZone = true
                end

                if firstQuestInZone then
                    -- Get first line in linePool
                    line = TrackerLinePool.GetNextLine()

                    -- Safety check - make sure we didn't run over our linePool limit.
                    if not line then break end

                    -- Set Line Mode, Types, Clickers
                    line:SetMode("zone")
                    line:SetOnClick("zone")
                    line:SetZone(zoneName)
                    line.expandQuest:Hide()
                    line.criteriaMark:Hide()
                    line.playButton:Hide()

                    -- Setup Zone Label
                    local zoneTopInset = zoneCheck and zoneSpacing or 0
                    ConfigureZoneDivider(line, showZoneDividers and zoneCheck ~= nil)
                    line.zoneTopInset = zoneTopInset
                    RememberLineLayout(line, zoneMarginLeft, trackerFontSizeZone, 4 + zoneTopInset)
                    line.label:ClearAllPoints()
                    line.label:SetPoint("TOPLEFT", line, "TOPLEFT", zoneMarginLeft, -zoneTopInset)

                    -- Set Zone Title and default Min/Max states
                    if Questie.db.char.collapsedZones[zoneName] then
                        line.expandZone:SetMode(0)
                        line.label:SetText(trackerZoneHeaderColor .. l10n(zoneName) .. " +|r")
                    else
                        line.expandZone:SetMode(1)
                        line.label:SetText(trackerZoneHeaderColor .. l10n(zoneName) .. "|r")
                    end

                    -- Checks the minAllQuestsInZone[zone] table and if empty, zero out the table.
                    if Questie.db.char.minAllQuestsInZone[zoneName] ~= nil and not Questie.db.char.collapsedZones[zoneName] then
                        local minQuestIdCount = 0
                        for minQuestId, _ in pairs(Questie.db.char.minAllQuestsInZone[zoneName]) do
                            if type(minQuestId) == "number" then
                                minQuestIdCount = minQuestIdCount + 1
                            end
                        end

                        if minQuestIdCount == 0 then
                            Questie.db.char.minAllQuestsInZone[zoneName] = nil
                        end
                    end

                    trackerLineWidth = math.max(trackerLineWidth, ApplyWrappedTrackerLabel(
                        line.label,
                        line,
                        zoneMarginLeft,
                        zoneMarginLeft + trackerMarginRight,
                        zoneMarginLeft,
                        trackerFontSizeZone
                    ))

                    -- Setup Min/Max Button
                    line.expandZone:ClearAllPoints()
                    line.expandZone:SetPoint("TOPLEFT", line.label, "TOPLEFT", 0, 0)
                    line.expandZone:SetWidth(line.label:GetWidth())
                    line.expandZone:SetHeight(line.label:GetHeight())
                    line.expandZone:Show()

                    -- Adds 4 pixels between Zone and first Quest Title
                    line:SetHeight(line.label:GetHeight() + 4 + zoneTopInset)

                    -- Set Zone states
                    line:Show()
                    line.label:Show()
                    line.Quest = nil
                    line.Objective = nil
                    firstQuestInZone = false
                    zoneCheck = zoneName
                end

                -- Add quest
                if (not Questie.db.char.collapsedZones[zoneName]) then
                    -- Get next line in linePool
                    line = TrackerLinePool.GetNextLine()

                    -- Safety check - make sure we didn't run over our linePool limit.
                    if not line then break end

                    -- Set Line Mode, Types, Clickers
                    line:SetMode("quest")
                    line:SetOnClick("quest")
                    line:SetQuest(quest)
                    line:SetObjective(nil)
                    line.expandZone:Hide()
                    line.criteriaMark:Hide()

                    -- Set Min/Max Button and default states
                    line.expandQuest.zoneId = zoneName


                    -- Set Completion Text
                    local completionText = TrackerUtils:GetCompletionText(quest)

                    -- Clear Blizzard Completion Text
                    if ((Questie.db.profile.hideBlizzardCompletionText or objectiveColor == "minimal") and not timedQuest) or complete == -1 then
                        completionText = nil
                    end

                    -- This removes any blank lines from Completion Text
                    if completionText ~= nil then
                        if strfind(completionText, "\r\n") then
                            completionText = completionText:gsub("\r\n", "")
                        else
                            completionText = completionText:gsub("(.\r?\n?)\r?\n?", "%1")
                        end

                        completionText = completionText:gsub("^%s+", ""):gsub("%s+$", "")
                        if completionText == "" then
                            completionText = nil
                        else
                            -- Completion Text should always be green
                            completionText = "|cFF4CFF4C" .. completionText
                        end
                    end

                    -- Set minimizable quest flag
                    local isMinimizable = (complete == 1 or (#quest.Objectives == 0 and quest.isComplete == true)) and completionText == nil

                    local shouldAutoMinimize = Questie.db.profile.collapseCompletedQuests
                        and isMinimizable
                        and not timedQuest
                        and (
                            not Questie.db.profile.collapseCompletedQuestsCurrentZoneOnly
                            or _IsCurrentTrackerZone(zoneName)
                        )

                    -- Keep automatic state separate so zone changes never undo a manual collapse.
                    if shouldAutoMinimize then
                        if not Questie.db.char.collapsedQuests[quest.Id] then
                            Questie.db.char.collapsedQuests[quest.Id] = true
                            Questie.db.char.autoCollapsedQuests[quest.Id] = true
                        end
                    elseif Questie.db.char.autoCollapsedQuests[quest.Id] then
                        Questie.db.char.autoCollapsedQuests[quest.Id] = nil
                        Questie.db.char.collapsedQuests[quest.Id] = nil
                    end

                    -- Handles all the Min/Max behavior individually for each quest.
                    if Questie.db.char.collapsedQuests[quest.Id] then
                        line.expandQuest:SetMode(0)
                    else
                        line.expandQuest:SetMode(1)
                    end

                    -- Set Quest Title - This handles the "Auto Minimize Completed Quests" option but we don't auto-minimize timed quests.
                    local coloredQuestName

                    if timedQuest then
                        coloredQuestName = QuestieLib:GetColoredQuestName(quest.Id, Questie.db.profile.trackerShowQuestLevel, false, false)
                    else
                        coloredQuestName = QuestieLib:GetColoredQuestName(quest.Id, Questie.db.profile.trackerShowQuestLevel, (Questie.db.profile.collapseCompletedQuests and isMinimizable), false)
                    end

                    line.label:SetText(coloredQuestName .. QuestieLib:FormatPfQuestTrackerPercentSuffix(quest, complete))
                    LayoutQuestTitleLine(line, 0)

                    -- Adds the AI_VoiceOver Play Buttons
                    line.playButton:SetPlayButton(questId)

                    local usableQIB = false
                    local sourceItemId = QuestieDB.QueryQuestSingle(quest.Id, "sourceItemId")
                    local sourceItem = sourceItemId and TrackerUtils:IsQuestItemUsable(sourceItemId)
                    local requiredItems = quest.requiredSourceItems
                    local requiredItem = requiredItems and TrackerUtils:IsQuestItemUsable(requiredItems[1])
                    local isComplete = (quest.isComplete ~= true and #quest.Objectives == 0) or quest.isComplete == true

                    -- Occasionally a quest will be in a complete state and still have a usable Quest Item. Sometimes these usable
                    -- items spawn an NPC that is needed to finish the quest. Or an item that teleports you to the quest finisher.
                    if complete == 1 and isComplete and (sourceItem or requiredItem) then
                        -- This shows QIB's for Quest Itmes that are needed after a quest is complete with objectives
                        if sourceItemId > 1 and requiredItem and sourceItemId ~= requiredItems[1] then
                            quest.sourceItemId = 0
                            usableQIB = true
                        end

                        -- This shows QIB's for Quest Items that are needed after a quest is complete without objectives
                        if sourceItemId > 1 and not requiredItem and quest.isComplete ~= true then
                            usableQIB = true
                        end
                    end

                    -- Adds the primary Quest Item button
                    if complete ~= 1 and (sourceItem or (requiredItems and #requiredItems == 1 and requiredItem)) or usableQIB then
                        -- Get button from buttonPool
                        local button = TrackerLinePool.GetNextItemButton()
                        if not button then break end -- stop populating the tracker

                        -- Get and save Quest Title linePool to buttonPool
                        button.line = line

                        -- Setup button and set attributes
                        if button:SetItem(quest, "primary", questItemButtonSize) then
                            local height = 0
                            local frame = button.line
                            while frame and frame ~= trackerQuestFrame do
                                local _, parent, _, _, yOff = frame:GetPoint()
                                height = height - (frame:GetHeight() - yOff)
                                frame = parent
                            end

                            -- Attach button to Quest Title linePool
                            AttachQuestItemButton(button, button.line, 1)
                            button:Show()

                            -- If the Quest Zone or Quest is minimized then set UIParent and hide buttons since the buttons are normally attached to the Quest frame.
                            -- If buttons are left attached to the Quest frame and if the Tracker frame is hidden in combat, then it would also try and hide the
                            -- buttons which you can't do in combat. This helps avoid violating the Blizzard SecureActionButtonTemplate restrictions relating to combat.
                            if Questie.db.char.collapsedZones[zoneName] or Questie.db.char.collapsedQuests[quest.Id] then
                                button:SetParent(UIParent)
                                button:Hide()
                            end

                            -- Set flag to allow secondary Quest Item Buttons
                            primaryButton = button:IsShown()
                        else
                            -- Button failed to get setup for some reason or the quest item is now gone.
                            -- See previous comment for details on why we're setting this button to UIParent.
                            button:SetParent(UIParent)

                            button:Hide()
                        end

                        -- Save button to linePool
                        line.button = button

                    end

                    -- Adds the Secondary Quest Item Button (only if Primary is present)
                    if (complete ~= 1 and primaryButton and requiredItems and #requiredItems > 1 and next(quest.Objectives)) then
                        if type(requiredItems) == "table" then
                            -- Make sure it's a "secondary" button and if a quest item is "usable".
                            for _, itemId in pairs(requiredItems) do
                                -- GetItemSpell(itemId) is a bit of a work around for not having a Blizzard API for checking an items IsUsable state.
                                if itemId and itemId ~= sourceItemId and QuestieDB.QueryItemSingle(itemId, "class") == 12 and TrackerUtils:IsQuestItemUsable(itemId) then
                                    -- Get button from buttonPool
                                    local altButton = TrackerLinePool.GetNextItemButton()
                                    if not altButton then break end -- stop populating the tracker

                                    -- Set itemID
                                    altButton.itemID = itemId

                                    -- Get and save Quest Title linePool to buttonPool
                                    altButton.line = line

                                    -- Setup button and set attributes
                                    if altButton:SetItem(quest, "secondary", questItemButtonSize) then
                                        local height = 0
                                        local frame = altButton.line

                                        while frame and frame ~= trackerQuestFrame do
                                            local _, parent, _, _, yOff = frame:GetPoint()
                                            height = height - (frame:GetHeight() - yOff)
                                            frame = parent
                                        end

                                        -- Attach button to Quest Title linePool
                                        AttachQuestItemButton(altButton, altButton.line, 2)
                                        altButton:Show()

                                        -- If the Quest Zone or Quest is minimized then set UIParent and hide buttons since the buttons are normally attached to the Quest frame.
                                        -- If buttons are left attached to the Quest frame and if the Tracker frame is hidden in combat, then it would also try and hide the
                                        -- buttons which you can't do in combat. This helps avoid violating the Blizzard SecureActionButtonTemplate restrictions relating to combat.
                                        if Questie.db.char.collapsedZones[zoneName] or Questie.db.char.collapsedQuests[quest.Id] then
                                            altButton:SetParent(UIParent)
                                            altButton:Hide()
                                        end

                                        -- Set flag to shift objective lines
                                        secondaryButton = altButton:IsShown()
                                        secondaryButtonAlpha = altButton:GetAlpha()
                                    else
                                        -- See previous comment for details on why we're setting this button to UIParent.
                                        altButton:SetParent(UIParent)
                                        altButton:Hide()
                                    end

                                    -- Save button to linePool
                                    line.altButton = altButton
                                end
                            end
                        end
                    end

                    local visibleQuestItemCount = 0
                    if primaryButton then
                        visibleQuestItemCount = visibleQuestItemCount + 1
                    end
                    if secondaryButton and secondaryButtonAlpha and secondaryButtonAlpha > 0 then
                        visibleQuestItemCount = visibleQuestItemCount + 1
                    end

                    LayoutQuestTitleLine(line, visibleQuestItemCount)

                    -- Adds the configured gap between the quest title and the first objective/completion line.
                    line:SetHeight(line.label:GetHeight() + questTitleBottomPadding)

                    -- Set Secondary Quest Item Button Margins (QBC - Quest Button Check)
                    local lineLabelWidthQBC, lineLabelBaseFrameQBC, lineWidthQBC
                    local questItemInset = GetInsideQuestItemInset(visibleQuestItemCount)
                    lineLabelWidthQBC = objectiveMarginLeft + trackerMarginRight + questItemInset
                    lineLabelBaseFrameQBC = objectiveMarginLeft + trackerMarginRight + questItemInset
                    lineWidthQBC = objectiveMarginLeft + questItemInset

                    -- Set Quest Line states
                    line:Show()
                    line.label:Show()

                    -- Add quest Objectives (if applicable)
                    if (not Questie.db.char.collapsedQuests[quest.Id]) then
                        -- Add Quest Timers (if applicable)
                        if timedQuest then
                            -- Get next line in linePool
                            line = TrackerLinePool.GetNextLine()

                            -- Safety check - make sure we didn't run over our linePool limit.
                            if not line then break end

                            -- Set Line Mode, Types, Clickers
                            line:SetMode("objective")
                            line:SetOnClick("quest")
                            line:SetQuest(quest)
                            line.expandZone:Hide()
                            line.expandQuest:Hide()
                            line.criteriaMark:Hide()
                            line.playButton:Hide()
                            HideObjectivePrefix(line)

                            -- Setup Timer Label
                            line.label:ClearAllPoints()
                            line.label:SetPoint("TOPLEFT", line, "TOPLEFT", lineWidthQBC, 0)

                            -- Set Timer font
                            line.label:SetFont(TrackerFonts:GetObjectiveFont(), trackerFontSizeObjective, Questie.db.profile.trackerFontOutline)

                            -- Set Timer Title based on states
                            line.label.activeTimer = false
                            if quest.timedBlizzardQuest then
                                line.label:SetText(Questie:Colorize(l10n("Blizzard Timer Active") .. "!", "blue"))
                            else
                                local timeRemainingString, timeRemaining = TrackerQuestTimers:GetRemainingTime(quest, line, false)
                                if timeRemaining then
                                    if timeRemaining <= 1 then
                                        line.label:SetText(Questie:Colorize("0 Seconds", "blue"))
                                        line.label.activeTimer = false
                                    else
                                        line.label:SetText(Questie:Colorize(timeRemainingString, "blue"))
                                        line.label.activeTimer = true
                                    end
                                end
                            end

                            RememberLineLayout(line, lineWidthQBC, trackerFontSizeObjective, 1)
                            trackerLineWidth = math.max(trackerLineWidth, ApplyWrappedTrackerLabel(
                                line.label,
                                line,
                                lineWidthQBC,
                                lineLabelBaseFrameQBC,
                                lineWidthQBC,
                                trackerFontSizeObjective
                            ))
                            line:SetHeight(line.label:GetHeight() + 1)

                            -- Set Timer states
                            line:Show()
                            line.label:Show()
                        end

                        -- Add incomplete Quest Objectives
                        if complete == 0 and quest.isComplete ~= true then
                            for _, objective in pairs(quest.Objectives) do
                                if (not Questie.db.profile.hideCompletedQuestObjectives or (Questie.db.profile.hideCompletedQuestObjectives and objective.Needed ~= objective.Collected)) then
                                    -- Get next line in linePool
                                    line = TrackerLinePool.GetNextLine()

                                    -- Safety check - make sure we didn't run over our linePool limit.
                                    if not line then break end

                                    -- Set Line Mode, Types, Clickers
                                    line:SetMode("objective")
                                    line:SetOnClick("quest")
                                    line:SetQuest(quest)
                                    line:SetObjective(objective)
                                    line.expandZone:Hide()
                                    line.expandQuest:Hide()
                                    line.criteriaMark:Hide()
                                    line.playButton:Hide()

                                    if (objective.Completed ~= true or (objective.Completed == true and #quest.Objectives > 1)) then
                                        line.questItemInset = questItemInset
                                        trackerLineWidth = ApplyPfQuestObjectiveLine(line, objective, lineLabelWidthQBC, lineLabelBaseFrameQBC, lineWidthQBC, quest, complete)

                                        -- Edge case where the quest is still flagged incomplete for single objectives and yet the objective itself is flagged complete
                                    elseif (objective.Completed == true and completionText ~= nil and #quest.Objectives == 1) and objectiveColor ~= "minimal" then
                                        line.questItemInset = questItemInset
                                        HideObjectivePrefix(line)

                                        -- Setup Objective Label based on states.
                                        line.label:ClearAllPoints()
                                        line.label:SetPoint("TOPLEFT", line, "TOPLEFT", lineWidthQBC, 0)

                                        -- Set Blizzard Completion text for single objectives
                                        line.label:SetText(completionText)
                                        RememberLineLayout(line, lineWidthQBC, trackerFontSizeObjective, 1)
                                        trackerLineWidth = math.max(trackerLineWidth, ApplyWrappedTrackerLabel(
                                            line.label,
                                            line,
                                            lineWidthQBC,
                                            lineLabelBaseFrameQBC,
                                            lineWidthQBC,
                                            trackerFontSizeObjective
                                        ))
                                        line:SetHeight(line.label:GetHeight() + 1)

                                        -- Update Quest has a check for this edge case. Should reset the Quest Icons and show the Quest Finisher
                                        QuestieQuest:UpdateQuest(quest.Id)

                                        -- Hide the Secondary Quest Item Button
                                        if secondaryButton and secondaryButtonAlpha ~= 0 then
                                            line.altButton:SetParent(UIParent)
                                            line.altButton:Hide()
                                        end
                                    end

                                    -- Adds 1 pixel between multiple Objectives
                                    line:SetHeight(line.label:GetHeight() + 1)

                                    -- Set Objective state
                                    line:Show()
                                    line.label:Show()
                                end
                            end

                            -- Add complete/failed Quest Objectives and tag them as either complete or failed so as to always have at least one objective.
                            -- Some quests have "Blizzard Completion Text" that is displayed to show where to go next or where to turn in the quest.
                        elseif complete == 1 or complete == -1 or quest.isComplete == true then
                            -- Get next line in linePool
                            line = TrackerLinePool.GetNextLine()

                            -- Safety check - make sure we didn't run over our linePool limit.
                            if not line then break end

                            -- Set Line Mode, Types, Clickers
                            line:SetMode("objective")
                            line:SetOnClick("quest")
                            line:SetQuest(quest)
                            line.questItemInset = questItemInset
                            line.expandZone:Hide()
                            line.expandQuest:Hide()
                            line.criteriaMark:Hide()
                            line.playButton:Hide()
                            HideObjectivePrefix(line)

                            -- Setup Objective Label
                            line.label:ClearAllPoints()
                            line.label:SetPoint("TOPLEFT", line, "TOPLEFT", lineWidthQBC, 0)

                            -- Set Objective label based on states
                            if ((complete == 1 and completionText ~= nil and #quest.Objectives == 0) or (quest.isComplete == true and completionText ~= nil)) and objectiveColor ~= "minimal" then
                                -- Set Blizzard Completion text for single objectives
                                line.label:SetText(completionText)
                                RememberLineLayout(line, lineWidthQBC, trackerFontSizeObjective, 1)
                                trackerLineWidth = math.max(trackerLineWidth, ApplyWrappedTrackerLabel(
                                    line.label,
                                    line,
                                    lineWidthQBC,
                                    lineLabelBaseFrameQBC,
                                    lineWidthQBC,
                                    trackerFontSizeObjective
                                ))
                                line:SetHeight(line.label:GetHeight() + 1)

                                -- Hide the Secondary Quest Item Button. There are some quests with usable items after a quest is completed I
                                -- have yet to encounter a completed quest where both a Primary and Secondary "usable" Quest Item was needed.
                                if secondaryButton and secondaryButtonAlpha ~= 0 then
                                    line.altButton:SetParent(UIParent)
                                    line.altButton:Hide()
                                end
                            else
                                if complete == 1 or (#quest.Objectives == 0 and quest.isComplete == true and completionText == nil and complete ~= -1) then
                                    line.label:SetText(Questie:Colorize(l10n("Quest Complete") .. "!", "green"))
                                elseif complete == -1 then
                                    line.label:SetText(Questie:Colorize(l10n("Quest Failed") .. "!", "red"))
                                end

                                RememberLineLayout(line, lineWidthQBC, trackerFontSizeObjective, 1)
                                trackerLineWidth = math.max(trackerLineWidth, ApplyWrappedTrackerLabel(
                                    line.label,
                                    line,
                                    lineWidthQBC,
                                    lineLabelBaseFrameQBC,
                                    lineWidthQBC,
                                    trackerFontSizeObjective
                                ))
                                line:SetHeight(line.label:GetHeight() + 1)
                            end

                            -- Set Objective state
                            line:Show()
                            line.label:Show()
                        end
                    end

                    -- Safety check in case we hit the linePool limit
                    if not line then
                        line = TrackerLinePool.GetLastLine()
                    end

                    -- The configured quest padding is the exact gap below a complete quest block.
                    line:SetHeight(line.label:GetHeight() + questPadding)
                    line.contentBottomPadding = questPadding
                end

                primaryButton = false
                secondaryButton = false
            end
        end
    end

    -- Begin populating the tracker with achievements
    local _UpdateAchievements = function()
        -- Begin populating the tracker with achievements
        if Questie.IsWotlk or QuestieCompat.Is335 then
            -- Begin populating the tracker with tracked achievements - Note: We're limited to tracking only 10 Achievements at a time.
            -- For all intents and purposes at a code level we're going to treat each tracked Achievement the same way we treat and add Quests. This loop is
            -- necessary to keep separate from the above tracked Quests loop so we can place all tracked Achievements into it's own "Zone" called Achievements.
            -- This will force Achievements to always appear at the bottom of the tracker. Obviously it'll show at the top if there are no quests being tracked.
            local firstAchieveInZone = false
            local achieveId, achieveName, achieveDescription, achieveComplete, numCriteria, zoneName, achieve

            for trackedId, _ in pairs(trackedAchievementIds) do
                achieveId, achieveName, _, _, _, _, _, achieveDescription, _, _, _, _, achieveComplete, _, _ = GetAchievementInfo(trackedId)
                numCriteria = GetAchievementNumCriteria(trackedId)
                zoneName = "Achievements"

                achieve = {
                    Id = achieveId,
                    Name = achieveName,
                    Description = achieveDescription
                }

                if achieveId and (not achieveComplete) and trackedAchievementIds[achieveId] == true then
                    -- Add Achievement Zone
                    if zoneCheck ~= zoneName then
                        _MaybeRenderLFGBeforeNextZone()
                        firstAchieveInZone = true
                    end

                    if firstAchieveInZone then
                        -- Get first line in linePool
                        line = TrackerLinePool.GetNextLine()

                        -- Safety check - make sure we didn't run over our linePool limit.
                        if not line then break end

                        -- Set Line Mode, Types, Clickers
                        line:SetMode("zone")
                        line:SetOnClick("zone")
                        line:SetZone(zoneName)
                        line.expandQuest:Hide()
                        line.criteriaMark:Hide()
                        line.playButton:Hide()

                    -- Setup Zone Label
                    local zoneTopInset = zoneCheck and zoneSpacing or 0
                    ConfigureZoneDivider(line, showZoneDividers and zoneCheck ~= nil)
                    line.zoneTopInset = zoneTopInset
                    RememberLineLayout(line, zoneMarginLeft, trackerFontSizeZone, 4 + zoneTopInset)
                    line.label:ClearAllPoints()
                    line.label:SetPoint("TOPLEFT", line, "TOPLEFT", zoneMarginLeft, -zoneTopInset)

                        -- Set Zone Title and Min/Max states
                        if Questie.db.char.collapsedZones[zoneName] then
                            line.expandZone:SetMode(0)
                            local text = zoneName == "Achievements" and l10n("Achievements") or zoneName
                            line.label:SetText("|cFFC0C0C0" .. text .. " +|r")
                        else
                            line.expandZone:SetMode(1)
                            local text = zoneName == "Achievements" and l10n("Achievements") or zoneName
                            line.label:SetText("|cFFC0C0C0" .. text .. ": " .. GetNumTrackedAchievements(true) .. "/10|r")
                        end

                        -- Checks the minAllQuestsInZone[zone] table and if empty, zero out the table.
                        if Questie.db.char.minAllQuestsInZone[zoneName] ~= nil and not Questie.db.char.collapsedZones[zoneName] then
                            local minQuestIdCount = 0
                            for minQuestId, _ in pairs(Questie.db.char.minAllQuestsInZone[zoneName]) do
                                if type(minQuestId) == "number" then
                                    minQuestIdCount = minQuestIdCount + 1
                                end
                            end

                            if minQuestIdCount == 0 then
                                Questie.db.char.minAllQuestsInZone[zoneName] = nil
                            end
                        end

                        trackerLineWidth = math.max(trackerLineWidth, ApplyWrappedTrackerLabel(
                            line.label,
                            line,
                            zoneMarginLeft,
                            zoneMarginLeft + trackerMarginRight,
                            zoneMarginLeft,
                            trackerFontSizeZone
                        ))

                        -- Setup Min/Max Button
                        line.expandZone:ClearAllPoints()
                        line.expandZone:SetPoint("TOPLEFT", line.label, "TOPLEFT", 0, 0)
                        line.expandZone:SetWidth(line.label:GetWidth())
                        line.expandZone:SetHeight(line.label:GetHeight())
                        line.expandZone:Show()

                        -- Adds 4 pixels between Zone and first Achievement Title
                        line:SetHeight(line.label:GetHeight() + 4 + zoneTopInset)

                        -- Set Zone states
                        line:Show()
                        line.label:Show()
                        line.Quest = nil
                        line.Objective = nil
                        firstAchieveInZone = false
                        zoneCheck = zoneName
                    end

                    -- Add Achievements
                    if (not Questie.db.char.collapsedZones[zoneName]) then
                        -- Get next line in linePool
                        line = TrackerLinePool.GetNextLine()

                        -- Safety check - make sure we didn't run over our linePool limit.
                        if not line then break end

                        -- Set Line Mode, Types, Clickers
                        line:SetMode("achieve")
                        line:SetOnClick("achieve")
                        line:SetQuest(achieve)
                        line:SetObjective(nil)
                        line.expandZone:Hide()
                        line.criteriaMark:Hide()
                        line.playButton:Hide()

                        -- Set Min/Max Button and default states
                        line.expandQuest:Show()
                        line.expandQuest:SetPoint("TOPRIGHT", line, "TOPLEFT", questMarginLeft - 8, 1)
                        line.expandQuest.zoneId = zoneName

                        -- Handles all the Min/Max behavior individually for each Achievement.
                        if Questie.db.char.collapsedQuests[achieve.Id] then
                            line.expandQuest:SetMode(0)
                        else
                            line.expandQuest:SetMode(1)
                        end

                        -- Setup Achievement Label (zone font, yellow title styling)
                        line.label:ClearAllPoints()
                        line.label:SetPoint("TOPLEFT", line, "TOPLEFT", questMarginLeft, 0)
                        line.label:SetFont(TrackerFonts:GetZoneFont(), trackerFontSizeZone, Questie.db.profile.trackerFontOutline)

                        -- Set Achievement Title
                        if Questie.db.profile.enableTooltipsQuestID then
                            line.label:SetText("|cFFFFFF00" .. achieve.Name .. " (" .. achieve.Id .. ")|r")
                        else
                            line.label:SetText("|cFFFFFF00" .. achieve.Name .. "|r")
                        end

                        trackerLineWidth = math.max(trackerLineWidth, ApplyWrappedTrackerLabel(
                            line.label,
                            line,
                            questMarginLeft,
                            questMarginLeft + trackerMarginRight,
                            questMarginLeft,
                                trackerFontSizeZone
                        ))
                        RememberLineLayout(line, questMarginLeft, trackerFontSizeZone, questTitleBottomPadding)

                        -- Adds the configured gap between the achievement title and the first criteria/objective line.
                        line:SetHeight(line.label:GetHeight() + questTitleBottomPadding)

                        -- Set Achievement states
                        line:Show()
                        line.label:Show()

                        -- Add achievement Objective (if applicable)
                        if (not Questie.db.char.collapsedQuests[achieve.Id]) then
                            -- Achievements with no number criteria
                            if numCriteria == 0 then
                                -- Get next line in linePool
                                line = TrackerLinePool.GetNextLine()

                                -- Safety check - make sure we didn't run over our linePool limit.
                                if not line then break end

                                -- Set Line Mode, Types, Clickers
                                line:SetMode("objective")
                                line:SetOnClick("achieve")
                                line:SetQuest(achieve)
                                line:SetObjective("objective")
                                line.expandZone:Hide()
                                line.expandQuest:Hide()
                                line.criteriaMark:Hide()
                                line.playButton:Hide()

                                -- Setup Objective Label (quest title font/size)
                                line.label:ClearAllPoints()
                                line.label:SetPoint("TOPLEFT", line, "TOPLEFT", titleMarginLeft, 0)
                                line.label:SetFont(TrackerFonts:GetQuestFont(), trackerFontSizeQuest, Questie.db.profile.trackerFontOutline)

                                -- Set Objective text
                                local objDesc = achieve.Description:gsub("%.", "")
                                line.label:SetText(QuestieLib:GetRGBForObjective({ Collected = 0, Needed = 1 }) .. objDesc)

                                trackerLineWidth = math.max(trackerLineWidth, ApplyWrappedTrackerLabel(
                                    line.label,
                                    line,
                                    titleMarginLeft,
                                    titleMarginLeft + trackerMarginRight,
                                    titleMarginLeft,
                                    trackerFontSizeQuest
                                ))
                                RememberLineLayout(line, titleMarginLeft, trackerFontSizeQuest, 1)
                                line:SetHeight(line.label:GetHeight() + 1)

                                -- Set Objective state
                                line:Show()
                                line.label:Show()
                            end

                            -- Achievements with number criteria
                            for objCriteria = 1, numCriteria do
                                local criteriaString, _, completed, quantityProgress, quantityNeeded, _, _, refId, quantityString = GetAchievementCriteriaInfo(achieve.Id, objCriteria)
                                if ((Questie.db.profile.hideCompletedAchieveObjectives) and (not completed)) or (not Questie.db.profile.hideCompletedAchieveObjectives) then
                                    -- Get next line in linePool
                                    line = TrackerLinePool.GetNextLine()

                                    -- Safety check - make sure we didn't run over our linePool limit.
                                    if not line then break end

                                    -- Set Line Mode, Types, Clickers
                                    line:SetMode("objective")
                                    line:SetOnClick("achieve")

                                    -- Set correct Objective ID. Sometimes stand alone trackable Achievements are part of a group of Achievements under a parent Achievement.
                                    local objId

                                    if refId and select(2, GetAchievementInfo(refId)) == criteriaString and ((GetAchievementInfo(refId) and refId ~= 0) or (refId > 0 and (not QuestieDB.GetQuest(refId)))) then
                                        objId = refId
                                    else
                                        objId = achieve
                                    end

                                    line:SetQuest(objId)
                                    line:SetObjective("objective")
                                    line.expandZone:Hide()
                                    line.expandQuest:Hide()
                                    line.criteriaMark:Hide()
                                    line.playButton:Hide()

                                    -- Setup Objective Label (quest title font/size)
                                    line.label:ClearAllPoints()
                                    line.label:SetPoint("TOPLEFT", line, "TOPLEFT", titleMarginLeft, 0)
                                    line.label:SetFont(TrackerFonts:GetQuestFont(), trackerFontSizeQuest, Questie.db.profile.trackerFontOutline)

                                    -- Set Objective label based on state
                                    if (criteriaString == "") then
                                        criteriaString = achieve.Description
                                    end

                                    local objDesc = criteriaString:gsub("%.", "")

                                    -- Set Objectives with more than one Objective number criteria
                                    if not (completed or quantityNeeded == 1 or quantityProgress == quantityNeeded) then
                                        if string.find(quantityString, "|") then
                                            quantityString = quantityString:gsub("/%s?", "/")
                                        else
                                            quantityString = quantityProgress .. "/" .. quantityNeeded
                                        end

                                        local lineEnding = tostring(quantityString)

                                        -- Set Objective text
                                        line.label:SetText(QuestieLib:GetRGBForObjective({ Collected = quantityProgress, Needed = quantityNeeded }) .. objDesc .. ": " .. lineEnding)

                                        trackerLineWidth = math.max(trackerLineWidth, ApplyWrappedTrackerLabel(
                                            line.label,
                                            line,
                                            titleMarginLeft,
                                            titleMarginLeft + trackerMarginRight,
                                            titleMarginLeft,
                                            trackerFontSizeQuest
                                        ))
                                        RememberLineLayout(line, titleMarginLeft, trackerFontSizeQuest, 1)
                                        line:SetHeight(line.label:GetHeight() + 1)

                                        -- Set Objectives with a single Objective number criteria
                                    else
                                        -- Set Objective text
                                        if completed then
                                            line.label:SetText(QuestieLib:GetRGBForObjective({ Collected = 1, Needed = 1 }) .. objDesc)
                                        else
                                            line.label:SetText(QuestieLib:GetRGBForObjective({ Collected = 0, Needed = 1 }) .. objDesc)
                                        end

                                        -- Set Objective criteria mark
                                        if not Questie.db.profile.hideCompletedAchieveObjectives and (not objectiveColor or objectiveColor == "white") then
                                            line.criteriaMark:SetCriteria(completed)

                                            if line.criteriaMark.mode == true then
                                                line.criteriaMark:Show()
                                            end
                                        end

                                        trackerLineWidth = math.max(trackerLineWidth, ApplyWrappedTrackerLabel(
                                            line.label,
                                            line,
                                            titleMarginLeft,
                                            titleMarginLeft + trackerMarginRight,
                                            titleMarginLeft,
                                            trackerFontSizeQuest
                                        ))
                                        RememberLineLayout(line, titleMarginLeft, trackerFontSizeQuest, 1)
                                    end

                                    -- Adds 1 pixel between multiple Objectives
                                    line:SetHeight(line.label:GetHeight() + 1)

                                    -- Set Objective state
                                    line:Show()
                                    line.label:Show()
                                end
                            end
                        end

                        -- Safety check in case we hit the linePool limit
                        if not line then
                            line = TrackerLinePool.GetLastLine()
                        end

                        -- The configured quest padding is the exact gap below a complete achievement block.
                        line:SetHeight(line.label:GetHeight() + questPadding)
                        line.contentBottomPadding = questPadding
                    end
                end
            end
        end
    end

    -- Populate tracker content based on the header filter (Quests / Achievements)
    local trackerViewMode = Questie.db.char.trackerViewMode or "quests"

    if trackerViewMode == "achievements" and (Questie.IsWotlk or QuestieCompat.Is335) then
        _UpdateAchievements()
    else
        _UpdateQuests()
    end

    -- Any position beyond the number of rendered zone blocks resolves to the bottom.
    _UpdateLFGObjectives()
    if lfgRendered and lfgNativeFrame then
        _SuppressNativeLFGTracker(lfgNativeFrame)
    else
        _RestoreNativeLFGTracker(lfgNativeFrame)
    end
    -- Safety check in case we hit the linePool limit
    if not line then
        line = TrackerLinePool.GetCurrentLine()
    end

    QuestieTracker:UpdateFormatting()

    -- First run clean up
    if isFirstRun then
        trackerBaseFrame:Hide()
        for questId, quest in pairs(QuestiePlayer.currentQuestlog) do
            if quest then
                if Questie.db.char.TrackerHiddenQuests[questId] then
                    quest.HideIcons = true
                end

                if Questie.db.char.TrackerFocus and type(Questie.db.char.TrackerFocus) == "number" and Questie.db.char.TrackerFocus == quest.Id then -- quest focus
                    TrackerUtils:FocusQuest(quest.Id)
                end

                for _, objective in pairs(quest.Objectives) do
                    if Questie.db.char.TrackerHiddenObjectives[tostring(questId) .. " " .. tostring(objective.Index)] then
                        objective.HideIcons = true
                    end

                    if Questie.db.char.TrackerFocus and type(Questie.db.char.TrackerFocus) == "string" and Questie.db.char.TrackerFocus == tostring(quest.Id) .. " " .. tostring(objective.Index) then
                        TrackerUtils:FocusObjective(quest.Id, objective.Index)
                    end
                end

                for _, objective in pairs(quest.SpecialObjectives) do
                    if Questie.db.char.TrackerHiddenObjectives[tostring(questId) .. " " .. tostring(objective.Index)] then
                        objective.HideIcons = true
                    end

                    if Questie.db.char.TrackerFocus and type(Questie.db.char.TrackerFocus) == "string" and Questie.db.char.TrackerFocus == tostring(quest.Id) .. " " .. tostring(objective.Index) then
                        TrackerUtils:FocusObjective(quest.Id, objective.Index)
                    end
                end
            end
        end
        isFirstRun = false
        C_Timer.After(0.05, function()
            QuestieCombatQueue:Queue(function()
                allowFormattingUpdate = true
                QuestieTracker:UpdateFormatting()
            end)
        end)
    end
end

function QuestieTracker:UpdateFormatting()
    if not allowFormattingUpdate then
        return
    end

    if TrackerBaseFrame.isSizing == true or TrackerBaseFrame.isMoving == true or TrackerUtils.FilterProximityTimer == true then
        Questie:Debug(Questie.DEBUG_SPAM, "[QuestieTracker:UpdateFormatting]")
    else
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:UpdateFormatting]")
    end

    -- The Proximity Timer only pulses every 5 secs while running.
    -- Flip back to false so we're not hiding other valid updates.
    TrackerUtils.FilterProximityTimer = nil

    -- Hide unused lines
    TrackerLinePool.HideUnusedLines()

    -- Hide unused item buttons
    QuestieCombatQueue:Queue(function()
        TrackerLinePool.HideUnusedButtons()
    end)

    -- This is responsible for handling the visibility of the Tracker
    -- when nothing is tracked or when alwaysShowTracker is being used.
    if (not QuestieTracker:HasQuest()) then
        if Questie.db.profile.alwaysShowTracker then
            trackerBaseFrame:Show()
        else
            trackerBaseFrame:Hide()
        end
    else
        trackerBaseFrame:Show()
    end

    if _HasPendingAutoQuestOffers() then
        _SuppressNativeAutoQuestDefaults()
    else
        _RestoreNativeAutoQuestDefaults()
    end

    TrackerHeaderFrame:Update()

    if TrackerLinePool.GetHighestIndex() > 0 and trackerLineWidth > 1 then
        local trackerVarsCombined = trackerLineWidth + trackerMarginRight
        QuestieTracker:UpdateWidth(trackerVarsCombined)
        TrackerLinePool.UpdateWrappedLineWidths(trackerLineWidth)
        QuestieTracker:UpdateHeight()
        TrackerQuestFrame:Update()
    elseif Questie.db.profile.trackerHeaderEnabled or (Questie.db.profile.alwaysShowTracker and not QuestieTracker:HasQuest()) then
        QuestieTracker:UpdateWidth(TrackerHeaderFrame:GetMinWidth())
        QuestieTracker:UpdateHeight()
        TrackerQuestFrame:Update()
    end

    TrackerBaseFrame:Update()
    TrackerLinePool.UpdateAlternatingRowBackgrounds()

    local trackerFontSizeZone = TrackerFonts:GetZoneFontSize()
    local trackerTopSpacing = math.max(0, tonumber(Questie.db.profile.trackerTopSpacing) or 0)
    local trackerBottomSpacing = math.max(0, tonumber(Questie.db.profile.trackerBottomSpacing) or 0)
    local firstLine = TrackerLinePool.GetFirstLine()
    local autoQuestMinimumHeight = _GetAutoQuestMinimumRenderedHeight()
    local autoQuestMinWidth = firstLine and firstLine.isAutoQuestNotice
        and (trackerMinLineWidth + trackerMarginRight) or 0
    if Questie.db.profile.trackerHeaderEnabled or (Questie.db.profile.alwaysShowTracker and not QuestieTracker:HasQuest()) then
        QuestieCompat.SetResizeBounds(
            trackerBaseFrame,
            math.max(TrackerHeaderFrame:GetMinWidth(), autoQuestMinWidth),
            trackerHeaderFrame:GetHeight()
                + math.max(trackerFontSizeZone + 3, autoQuestMinimumHeight)
                + TRACKER_CONTENT_VERTICAL_PADDING + trackerTopSpacing + trackerBottomSpacing
        )
    else
        QuestieCompat.SetResizeBounds(
            trackerBaseFrame,
            math.max(firstLine.label:GetUnboundedStringWidth() + 40, autoQuestMinWidth),
            math.max(trackerFontSizeZone + 2, autoQuestMinimumHeight)
                + TRACKER_CONTENT_VERTICAL_PADDING + trackerTopSpacing + trackerBottomSpacing
        )
    end

    TrackerUtils:UpdateVoiceOverPlayButtons()
    TrackerUtils:ShowVoiceOverPlayButtons()
    _StartAutoQuestNoticeAnimations()
end

function QuestieTracker:UpdateWidth(trackerVarsCombined)
    local trackerWidthByManual = Questie.db.profile.TrackerWidth
    local trackerHeaderEnabled = Questie.db.profile.trackerHeaderEnabled or (Questie.db.profile.alwaysShowTracker and not QuestieTracker:HasQuest())
    local trackerHeaderMinWidth = TrackerHeaderFrame:GetMinWidth()
    local trackerHeaderFrameWidth = trackerHeaderEnabled and math.max(trackerVarsCombined or 0, trackerHeaderMinWidth) or (trackerHeaderFrame:GetWidth() + TrackerFonts:GetHeaderFontSize() + 10)
    local firstLine = TrackerLinePool.GetFirstLine()
    local trackerHeaderlessWidth = firstLine.label:GetUnboundedStringWidth() + 30
    if firstLine.isAutoQuestNotice then
        trackerHeaderlessWidth = math.max(trackerHeaderlessWidth, trackerMinLineWidth + trackerMarginRight)
    end

    if Questie.db.char.isTrackerExpanded then
        if trackerWidthByManual > 0 then
            -- Tracker Sizer is in Manual Mode
            if (not TrackerBaseFrame.isSizing) then
                -- Tracker is not being Sized | Manual width based on the width set by the Tracker Sizer
                if trackerWidthByManual < trackerHeaderFrameWidth and (Questie.db.profile.trackerHeaderEnabled or (Questie.db.profile.alwaysShowTracker and not QuestieTracker:HasQuest())) then
                    trackerBaseFrame:SetWidth(trackerHeaderFrameWidth)
                elseif trackerWidthByManual < trackerHeaderlessWidth then
                    trackerBaseFrame:SetWidth(trackerHeaderlessWidth)
                else
                    trackerBaseFrame:SetWidth(trackerWidthByManual)
                end
            else
                -- Tracker is being Sized | This will update the Tracker width while the Sizer is being used
                trackerBaseFrame:SetWidth(trackerWidthByManual)
            end
        else
            -- Tracker Sizer is in Auto Mode
            if (trackerVarsCombined < trackerHeaderFrameWidth and (Questie.db.profile.trackerHeaderEnabled or (Questie.db.profile.alwaysShowTracker and not QuestieTracker:HasQuest()))) then
                -- Apply headerFrameWidth
                trackerBaseFrame:SetWidth(trackerHeaderFrameWidth)
            else
                -- Apply trackerVarsCombined width based on the maximum size of the largest line in the Tracker
                trackerBaseFrame:SetWidth(trackerVarsCombined)
            end
        end

        trackerQuestFrame:SetWidth(trackerBaseFrame:GetWidth())
        trackerQuestFrame.ScrollChildFrame:SetWidth(trackerBaseFrame:GetWidth())
    else
        if Questie.db.profile.trackerHeaderEnabled or (Questie.db.profile.alwaysShowTracker and not QuestieTracker:HasQuest()) then
            trackerBaseFrame:SetWidth(trackerHeaderFrameWidth)
            trackerQuestFrame:SetWidth(trackerHeaderFrameWidth)
            trackerQuestFrame.ScrollChildFrame:SetWidth(trackerHeaderFrameWidth)
        elseif firstLine and firstLine.isAutoQuestNotice then
            local collapsedWidth = math.max(
                trackerHeaderlessWidth,
                trackerVarsCombined or 0,
                trackerWidthByManual > 0 and trackerWidthByManual or 0
            )
            trackerBaseFrame:SetWidth(collapsedWidth)
            trackerQuestFrame:SetWidth(collapsedWidth)
            trackerQuestFrame.ScrollChildFrame:SetWidth(collapsedWidth)
        end
    end

    if Questie.db.profile.trackerHeaderEnabled or (Questie.db.profile.alwaysShowTracker and not QuestieTracker:HasQuest()) then
        TrackerHeaderFrame:SyncWidth(trackerBaseFrame:GetWidth())
    end
end

function QuestieTracker:UpdateHeight()
    local trackerFontSizeHeader = TrackerFonts:GetHeaderFontSize()
    local trackerFontSizeZone = TrackerFonts:GetZoneFontSize()
    local trackerTopSpacing = math.max(0, tonumber(Questie.db.profile.trackerTopSpacing) or 0)
    local trackerBottomSpacing = math.max(0, tonumber(Questie.db.profile.trackerBottomSpacing) or 0)
    local headerHeight = trackerHeaderFrame:GetHeight() or (trackerFontSizeHeader + 5)
    local firstLine = TrackerLinePool.GetFirstLine()
    local autoQuestContentHeight = _GetAutoQuestRenderedHeight()
    local autoQuestMinimumHeight = _GetAutoQuestMinimumRenderedHeight()
    local trackerHeaderFrameHeight = headerHeight
        + math.max(trackerFontSizeZone + 3, autoQuestMinimumHeight)
        + TRACKER_CONTENT_VERTICAL_PADDING + trackerTopSpacing + trackerBottomSpacing
    local trackerHeightByRatio = GetScreenHeight() * Questie.db.profile.trackerHeightRatio
    local trackerHeightByManual = Questie.db.profile.TrackerHeight
    local trackerHeightCheck = trackerHeightByManual > 0 and trackerHeightByManual or trackerHeightByRatio
    local trackerHeaderlessHeight = math.max(trackerFontSizeZone + 2, autoQuestMinimumHeight)
        + TRACKER_CONTENT_VERTICAL_PADDING + trackerTopSpacing + trackerBottomSpacing

    local function GetScrollContentHeight()
        local totalHeight = 0
        local highestIndex = TrackerLinePool.GetHighestIndex()

        for i = 1, highestIndex do
            local trackerLine = TrackerLinePool.GetLine(i)
            if trackerLine and trackerLine:IsShown() then
                totalHeight = totalHeight + trackerLine:GetHeight()
            end
        end

        return totalHeight
    end

    if Questie.db.char.isTrackerExpanded then
        local currentLine = TrackerLinePool.GetCurrentLine()
        local scrollContentHeight = GetScrollContentHeight()

        if currentLine and currentLine.label and scrollContentHeight > 0 then
            currentLine:SetHeight(currentLine.label:GetHeight() + (currentLine.contentBottomPadding or 0))

            local firstTop = firstLine and firstLine:GetTop()
            local currentBottom = currentLine:GetBottom()

            if firstTop and currentBottom then
                if currentLine.mode == "zone" then
                    trackerQuestFrame.ScrollChildFrame:SetHeight(firstTop - currentBottom)
                else
                    trackerQuestFrame.ScrollChildFrame:SetHeight(firstTop - currentBottom + 3)
                end
            else
                scrollContentHeight = GetScrollContentHeight()
                if currentLine.mode == "zone" then
                    trackerQuestFrame.ScrollChildFrame:SetHeight(scrollContentHeight)
                else
                    trackerQuestFrame.ScrollChildFrame:SetHeight(scrollContentHeight + 3)
                end
            end
        else
            trackerQuestFrame.ScrollChildFrame:SetHeight(1)
        end

        -- Set the baseFrame to full height so we can measure it
        trackerQuestFrame:SetHeight(trackerQuestFrame.ScrollChildFrame:GetHeight())

        if Questie.db.profile.trackerHeaderEnabled or (Questie.db.profile.alwaysShowTracker and not QuestieTracker:HasQuest()) then
            trackerBaseFrame:SetHeight(trackerQuestFrame:GetHeight() + headerHeight + TRACKER_CONTENT_VERTICAL_PADDING + trackerTopSpacing + trackerBottomSpacing)
        else
            trackerBaseFrame:SetHeight(trackerQuestFrame:GetHeight() + TRACKER_CONTENT_VERTICAL_PADDING + trackerTopSpacing + trackerBottomSpacing)
        end

        -- Use trackerHeightCheck (Sizer Manual or Auto) and set the heights
        if (not TrackerBaseFrame.isSizing) then
            -- Tracker is not being re-sized
            if trackerBaseFrame:GetHeight() > trackerHeightCheck then
                if trackerHeightCheck < trackerHeaderFrameHeight + 10 and (Questie.db.profile.trackerHeaderEnabled or (Questie.db.profile.alwaysShowTracker and not QuestieTracker:HasQuest())) then
                    trackerBaseFrame:SetHeight(trackerHeaderFrameHeight)
                elseif trackerHeightCheck < trackerHeaderlessHeight then
                    trackerBaseFrame:SetHeight(trackerHeaderlessHeight)
                else
                    trackerBaseFrame:SetHeight(trackerHeightCheck)
                end
            end
        else
            trackerBaseFrame:SetHeight(trackerHeightCheck)
        end

        -- Resize the questFrame to match the baseFrame after the trackerHeightCheck is applied
        if Questie.db.profile.trackerHeaderEnabled or (Questie.db.profile.alwaysShowTracker and not QuestieTracker:HasQuest()) then
            -- With Header Frame
            trackerQuestFrame:SetHeight(trackerBaseFrame:GetHeight() - headerHeight - TRACKER_CONTENT_VERTICAL_PADDING - trackerTopSpacing - trackerBottomSpacing)
        else
            -- Without Header Frame
            trackerQuestFrame:SetHeight(trackerBaseFrame:GetHeight() - TRACKER_CONTENT_VERTICAL_PADDING - trackerTopSpacing - trackerBottomSpacing)
        end
    elseif autoQuestContentHeight > 0 then
        local hasHeader = Questie.db.profile.trackerHeaderEnabled
            or (Questie.db.profile.alwaysShowTracker and not QuestieTracker:HasQuest())
        local frameChromeHeight = TRACKER_CONTENT_VERTICAL_PADDING + trackerTopSpacing + trackerBottomSpacing
            + (hasHeader and headerHeight or 0)
        local minimumBaseHeight = frameChromeHeight + autoQuestMinimumHeight
        local desiredBaseHeight = frameChromeHeight + autoQuestContentHeight
        local maximumBaseHeight = math.max(minimumBaseHeight, trackerHeightCheck)
        local visibleBaseHeight = math.min(desiredBaseHeight, maximumBaseHeight)

        trackerQuestFrame.ScrollChildFrame:SetHeight(autoQuestContentHeight)
        trackerQuestFrame:SetHeight(math.max(1, visibleBaseHeight - frameChromeHeight))
        trackerBaseFrame:SetHeight(visibleBaseHeight)
    else
        trackerBaseFrame:SetHeight(trackerHeaderFrameHeight - TRACKER_CONTENT_VERTICAL_PADDING)
        trackerQuestFrame:SetHeight(trackerHeaderFrameHeight - TRACKER_CONTENT_VERTICAL_PADDING)
        trackerQuestFrame.ScrollChildFrame:SetHeight(trackerHeaderFrameHeight - TRACKER_CONTENT_VERTICAL_PADDING)
    end
end

function QuestieTracker:Unhook()
    if (not QuestieTracker.alreadyHooked) then
        return
    end

    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:Unhook]")

    QuestieTracker.disableHooks = true

    TrackerQuestTimers:ShowBlizzardTimer()

    -- Quest Hooks
    if QuestieTracker.IsQuestWatched then
        IsQuestWatched = QuestieTracker.IsQuestWatched
        GetNumQuestWatches = QuestieTracker.GetNumQuestWatches
    end

    -- Achievement Hooks
    if Questie.IsWotlk or QuestieCompat.Is335 then
        if QuestieTracker.IsTrackedAchievement then
            IsTrackedAchievement = QuestieTracker.IsTrackedAchievement
            GetNumTrackedAchievements = QuestieTracker.GetNumTrackedAchievements
        end
    end

    QuestieTracker.alreadyHooked = nil
end

function QuestieTracker:HookBaseTracker()
    if QuestieTracker.alreadyHooked then
        return
    end

    QuestieTracker.disableHooks = nil

    if not QuestieTracker.alreadyHookedSecure then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:HookBaseTracker] - Secure hooks")

        -- Durability Frame hook
        hooksecurefunc("UIParent_ManageFramePositions", QuestieTracker.UpdateDurabilityFrame)

        -- QuestWatch secure hook
        if AutoQuestWatch_Insert then
            hooksecurefunc("AutoQuestWatch_Insert", function(index, watchTimer) QuestieTracker:AQW_Insert(index, watchTimer) end)
        end

        hooksecurefunc("AddQuestWatch", function(index, watchTimer) QuestieTracker:AQW_Insert(index, watchTimer) end)
        hooksecurefunc("RemoveQuestWatch", QuestieTracker.RemoveQuestWatch)

        -- Achievement secure hooks
        if Questie.IsWotlk or QuestieCompat.Is335 then
            hooksecurefunc("AddTrackedAchievement", function(achieveId) QuestieTracker:TrackAchieve(achieveId) end)
            hooksecurefunc("RemoveTrackedAchievement", QuestieTracker.RemoveTrackedAchievement)
        end

        QuestieTracker.alreadyHookedSecure = true
    end

    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:HookBaseTracker] - Non-secure hooks")

    -- Quest Hooks
    if not QuestieTracker.IsQuestWatched then
        QuestieTracker.IsQuestWatched = IsQuestWatched
        QuestieTracker.GetNumQuestWatches = GetNumQuestWatches
    end

    -- Intercept and return a Questie boolean value
    IsQuestWatched = function(index)
        local questId = select(8, GetQuestLogTitle(index))
        if questId == 0 then
            -- When an objective progresses in TBC "index" is the questId, but when a quest is manually added to the quest watch
            -- (e.g. shift clicking it in the quest log) "index" is the questLogIndex.
            questId = index
        end

        if not Questie.db.profile.autoTrackQuests then
            return Questie.db.char.TrackedQuests[questId or -1]
        else
            return questId and QuestiePlayer.currentQuestlog[questId] and (not Questie.db.char.AutoUntrackedQuests[questId])
        end
    end

    -- Intercept and return only what Questie is tracking
    GetNumQuestWatches = function(isQuestie)
        local activeQuests = 0
        if isQuestie and Questie.db.profile.autoTrackQuests and Questie.db.char.AutoUntrackedQuests then
            local autoUnTrackedQuests = 0
            for _ in pairs(Questie.db.char.AutoUntrackedQuests) do
                autoUnTrackedQuests = autoUnTrackedQuests + 1
            end
            return select(2, GetNumQuestLogEntries()) - autoUnTrackedQuests
        elseif isQuestie and Questie.db.char.TrackedQuests then
            local autoTrackedQuests = 0
            for _ in pairs(Questie.db.char.TrackedQuests) do
                autoTrackedQuests = autoTrackedQuests + 1
            end
            return autoTrackedQuests
        else
            return 0
        end
    end

    -- Achievement Hooks
    if Questie.IsWotlk or QuestieCompat.Is335 then
        if not QuestieTracker.IsTrackedAchievement then
            QuestieTracker.IsTrackedAchievement = IsTrackedAchievement
            QuestieTracker.GetNumTrackedAchievements = GetNumTrackedAchievements
        end

        -- Intercept and return a Questie boolean value
        IsTrackedAchievement = function(achieveId)
            if Questie.db.char.trackedAchievementIds[achieveId] then
                return achieveId and Questie.db.char.trackedAchievementIds[achieveId]
            else
                return false
            end
        end

        -- Intercept and return only what Questie is tracking
        GetNumTrackedAchievements = function(isQuestie)
            if isQuestie and Questie.db.char.trackedAchievementIds then
                local numTrackedAchievements = 0
                for _ in pairs(Questie.db.char.trackedAchievementIds) do
                    numTrackedAchievements = numTrackedAchievements + 1
                end
                return numTrackedAchievements
            else
                return 0
            end
        end
    end

    if Questie.db.profile.showBlizzardQuestTimer then
        TrackerQuestTimers:ShowBlizzardTimer()
    else
        TrackerQuestTimers:HideBlizzardTimer()
    end

    QuestieTracker.alreadyHooked = true
    QuestieCombatQueue:Queue(function()
        QuestieTracker:Update()
    end)
end

function QuestieTracker:RemoveQuest(questId)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:RemoveQuest] - ", questId)
    if Questie.db.char.collapsedQuests then
        Questie.db.char.collapsedQuests[questId] = nil
    end
    if Questie.db.char.autoCollapsedQuests then
        Questie.db.char.autoCollapsedQuests[questId] = nil
    end

    -- Let's remove the Quest from the Tracker tables just in case...
    if Questie.db.char.AutoUntrackedQuests[questId] then
        Questie.db.char.AutoUntrackedQuests[questId] = nil
    elseif Questie.db.char.TrackedQuests[questId] then
        Questie.db.char.TrackedQuests[questId] = nil
    end

    if Questie.db.char.TrackerFocus then
        if (type(Questie.db.char.TrackerFocus) == "number" and Questie.db.char.TrackerFocus == questId)
            or (type(Questie.db.char.TrackerFocus) == "string" and Questie.db.char.TrackerFocus:sub(1, #tostring(questId)) == tostring(questId)) then
            TrackerUtils:UnFocus()
            QuestieQuest:ToggleNotes(true)
        end
    end
end

function QuestieTracker.RemoveQuestWatch(index, isQuestie)
    if QuestieTracker.disableHooks then
        return
    end

    if not isQuestie then
        if index then
            local questId = select(8, GetQuestLogTitle(index))
            if questId == 0 then
                -- When an objective progresses in TBC "index" is the questId, but when a quest is manually removed from
                --  the quest watch (e.g. shift clicking it in the quest log) "index" is the questLogIndex.
                questId = index
            end

            if questId then
                QuestieTracker:UntrackQuestId(questId)
                Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker.RemoveQuestWatch] - by Blizzard")
            end
        end
    else
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker.RemoveQuestWatch] - by Questie")
    end
end

function QuestieTracker:UntrackQuestId(questId)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:UntrackQuestId] - ", questId)
    if not Questie.db.profile.autoTrackQuests then
        Questie.db.char.TrackedQuests[questId] = nil
    else
        Questie.db.char.AutoUntrackedQuests[questId] = true
    end

    if Questie.db.profile.hideUntrackedQuestsMapIcons then
        -- Hides objective icons for untracked quests.
        QuestieQuest:ToggleNotes(false)

        -- Removes objective tooltips for untracked quests.
        QuestieTooltips:RemoveQuest(questId)
    end

    QuestieCombatQueue:Queue(function()
        QuestieTracker:Update()
    end)
end

function QuestieTracker:AQW_Insert(index, expire)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:AQW_Insert]")
    if (not Questie.db.profile.trackerEnabled) or (index == 0) or (index == nil) then
        return
    end

    -- This prevents double calling this function
    local now = GetTime()
    if index and index == QuestieTracker.last_aqw and (now - lastAQW) < 0.1 then
        return
    end

    lastAQW = now
    QuestieTracker.last_aqw = index

    -- This removes quests from the Blizzard QuestWatchFrame so when the option "Show Blizzard Timer" is enabled,
    -- that is all the player will see. This also prevents hitting the Blizzard Quest Watch Limit.
    RemoveQuestWatch(index, true)

    local questId = select(8, GetQuestLogTitle(index))
    if questId == 0 then
        -- When an objective progresses in TBC "index" is the questId, but when a quest is manually added to the quest watch
        -- (e.g. shift clicking it in the quest log) "index" is the questLogIndex.
        questId = index
    end

    if questId > 0 then
        -- These checks makes sure the only way to track a quest is through the Blizzard Quest Log
        -- or another Addon hooked into the Blizzard Quest Log that replaces the default Quest Log.
        if not Questie.db.profile.autoTrackQuests then
            if Questie.db.char.TrackedQuests[questId] then
                Questie.db.char.TrackedQuests[questId] = nil
            else
                -- Add quest to the tracker
                Questie.db.char.TrackedQuests[questId] = true
            end
        else
            if Questie.db.char.AutoUntrackedQuests[questId] then
                Questie.db.char.AutoUntrackedQuests[questId] = nil

                -- Add quest to the tracker
            elseif IsShiftKeyDown() and QuestLogFrame:IsShown() then
                Questie.db.char.AutoUntrackedQuests[questId] = true
            end
        end

        local quest = QuestiePlayer.currentQuestlog[questId]
        if type(quest) ~= "table" then
            quest = QuestieDB.GetQuest(questId)
        end

        if quest then
            -- Make sure quests or zones (re)added to the tracker isn't in a minimized state
            local zoneId = quest.zoneOrSort
            if Questie.db.char.collapsedQuests[questId] == true then
                Questie.db.char.collapsedQuests[questId] = nil
            end
            if Questie.db.char.autoCollapsedQuests then
                Questie.db.char.autoCollapsedQuests[questId] = nil
            end

            if Questie.db.char.collapsedZones[zoneId] == true then
                Questie.db.char.collapsedZones[zoneId] = nil
            end

            -- Unhide quest icons when retracking quests.
            if Questie.db.profile.hideUntrackedQuestsMapIcons then
                -- Shows objective icons for tracked quests.
                QuestieQuest:ToggleNotes(true)

                -- Readd objective tooltips for tracked quests.
                QuestieQuest:PopulateObjectiveNotes(quest)
            end
        else
            Questie:Debug(Questie.DEBUG_INFO, "[QuestieTracker] No live quest data available during tracker update", questId, expire)
        end
    end
    QuestieCombatQueue:Queue(function()
        QuestieTracker:Update()
    end)
end

QuestieTracker.RemoveTrackedAchievement = function(achieveId, isQuestie)
    if QuestieTracker.disableHooks then
        return
    end

    if not isQuestie then
        if achieveId then
            QuestieTracker:UntrackAchieveId(achieveId)
            Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker.RemoveTrackedAchievement] - by Blizzard")
        end
    else
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker.RemoveTrackedAchievement] - by Questie")
    end
end

function QuestieTracker:UpdateAchieveTrackerCache(achieveId)
    -- Since we're essentially adding & force removing an achievement from the QuestWatch frame while we add an achievement to the Questie Tracker, the event this
    -- function is called from, TRACKED_ACHIEVEMENT_LIST_CHANGED, fires twice. When we remove an achievement from the Questie Tracker the event still fires twice
    -- because the Blizzard function responsible for this is essentially a "toggle". It quickly re-adds the achievement to the QuestWatch frame and then removes it.
    -- So, again this event again fires twice. We only need to allow this to run once and it often fires before the Questie.db.char.trackedAchievementIds table is
    -- updated so we're going to throttle this 1/10th of a second.
    if Questie.db.profile.trackerEnabled then
        if achieveId then
            C_Timer.After(0.1, function()
                Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:UpdateAchieveTrackerCache] - ", achieveId)

                if (not Questie.db.profile.trackerEnabled) or (achieveId == 0) then
                    return
                end

                -- Look for changes in the Saved VAR and update the achievement cache
                if Questie.db.char.trackedAchievementIds[achieveId] ~= trackedAchievementIds[achieveId] then
                    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:UpdateAchieveTrackerCache] - Change Detected!")

                    trackedAchievementIds[achieveId] = Questie.db.char.trackedAchievementIds[achieveId]

                    QuestieCombatQueue:Queue(function()
                        C_Timer.After(0.1, function()
                            QuestieTracker:Update()
                        end)
                    end)
                else
                    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:UpdateAchieveTrackerCache] - No Change Detected!")
                end
            end)
        end
    end
end

function QuestieTracker:UntrackAchieveId(achieveId)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:UntrackAchieve] - ", achieveId)
    if Questie.db.char.trackedAchievementIds[achieveId] then
        Questie.db.char.trackedAchievementIds[achieveId] = nil
    end
end

function QuestieTracker:TrackAchieve(achieveId)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieTracker:TrackAchieve] - ", achieveId)
    if (not Questie.db.profile.trackerEnabled) or (achieveId == 0) then
        return
    end

    -- If an achievement is already tracked in the Achievement UI then untrack it (Mimicks a Toggle effect).
    if Questie.db.char.trackedAchievementIds[achieveId] then
        QuestieTracker:UntrackAchieveId(achieveId)
        RemoveTrackedAchievement(achieveId, true)
        return
    end

    -- Prevents tracking more than 10 Achievements
    if (GetNumTrackedAchievements(true) == 10) then
        RemoveTrackedAchievement(achieveId, true)
        UIErrorsFrame:AddMessage(format(l10n("You may only track 10 achievements at a time."), 10), 1.0, 0.1, 0.1, 1.0)
        return
    end

    -- This prevents double calling this function
    local now = GetTime()
    if achieveId and achieveId == QuestieTracker.last_achieveId and (now - lastAchieveId) < 0.1 then
        return
    end

    lastAchieveId = now
    QuestieTracker.last_achieveId = achieveId

    -- This removes achievements from the Blizzard QuestWatchFrame so when the
    -- option "Show Blizzard Timer" is enabled, that is all the player will see.
    RemoveTrackedAchievement(achieveId, true)

    if achieveId > 0 then
        -- This handles the Track check box in the Achievement UI
        local mouseFocus
        local frameMatch

        -- Krowi isn't using this check box for their Achievement frame
        if not IsAddOnLoaded("Krowi_AchievementFilter") then
            mouseFocus = GetMouseFocus():GetName()
            frameMatch = strmatch(mouseFocus, "(AchievementFrameAchievementsContainerButton%dTracked.*)")
        end

        -- Upon first login or reloadui, this frame isn't loaded
        if (not AchievementFrame) then
            AchievementFrame_LoadUI()
        end

        -- This check makes sure the only way to track an achieve is through the Blizzard Achievement UI
        if Questie.db.char.trackedAchievementIds[achieveId] then
            Questie.db.char.trackedAchievementIds[achieveId] = nil
        elseif IsShiftKeyDown() and AchievementFrame:IsShown() then
            Questie.db.char.trackedAchievementIds[achieveId] = true
        elseif AchievementFrame:IsShown() and (mouseFocus == frameMatch) then
            Questie.db.char.trackedAchievementIds[achieveId] = true
        end

        -- Forces the achievement out of a minimized state
        if Questie.db.char.collapsedQuests[achieveId] == true then
            Questie.db.char.collapsedQuests[achieveId] = nil
        end

        -- Forces the 'Achievement Zone' out of a minimized state
        if Questie.db.char.collapsedZones["Achievements"] == true then
            Questie.db.char.collapsedZones["Achievements"] = nil
        end
    end
end
