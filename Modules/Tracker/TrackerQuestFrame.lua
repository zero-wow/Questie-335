---@class TrackerQuestFrame
local TrackerQuestFrame = QuestieLoader:CreateModule("TrackerQuestFrame")
-------------------------
--Import QuestieTracker modules.
-------------------------
---@type QuestieCombatQueue
local QuestieCombatQueue = QuestieLoader:ImportModule("QuestieCombatQueue")
---@type TrackerBaseFrame
local TrackerBaseFrame = QuestieLoader:ImportModule("TrackerBaseFrame")
---@type TrackerFadeTicker
local TrackerFadeTicker = QuestieLoader:ImportModule("TrackerFadeTicker")
---@type QuestieTracker
local QuestieTracker = QuestieLoader:ImportModule("QuestieTracker")

local questFrame, trackerBaseFrame, trackerHeaderFrame
local TRACKER_CONTENT_EDGE_INSET = 4

function TrackerQuestFrame.Initialize(baseFrame, headerFrame)
    trackerBaseFrame = baseFrame
    trackerHeaderFrame = headerFrame

    -- TrackerQuestFrame
    questFrame = CreateFrame("Frame", "TrackedQuests", trackerBaseFrame)
    questFrame:SetWidth(25)
    questFrame:SetHeight(25)
    questFrame:SetFrameLevel((trackerBaseFrame:GetFrameLevel() or 0) + 5)

    TrackerQuestFrame.PositionTrackedQuestsFrame()

    questFrame:EnableMouse(true)
    questFrame:SetMovable(true)
    questFrame:SetResizable(true)
    questFrame:RegisterForDrag("LeftButton")
    questFrame:SetScript("OnDragStart", TrackerBaseFrame.OnDragStart)
    questFrame:SetScript("OnDragStop", TrackerBaseFrame.OnDragStop)
    questFrame:SetScript("OnEnter", TrackerFadeTicker.Unfade)
    questFrame:SetScript("OnLeave", TrackerFadeTicker.Fade)

    local scrollFrameTemplete
    if Questie.IsWotlk and (not QuestieCompat.Is335) then
        scrollFrameTemplete = "ScrollFrameTemplate"
    else
        scrollFrameTemplete = "UIPanelScrollFrameTemplate"
    end

    -- ScrollFrame
    questFrame.ScrollFrame = CreateFrame("ScrollFrame", "TrackedQuestsScrollFrame", questFrame, scrollFrameTemplete)
    questFrame.ScrollFrame:SetAllPoints(questFrame)

    if not Questie.IsWotlk or QuestieCompat.Is335 then
        local frameName = questFrame.ScrollFrame:GetName()
        questFrame.ScrollBar = _G[frameName .. "ScrollBar"]
        questFrame.ScrollBar:ClearAllPoints()
        questFrame.ScrollBar:SetPoint("TOPRIGHT", questFrame.ScrollUpButton, "BOTTOMRIGHT", -1, 4)
        questFrame.ScrollBar:SetPoint("BOTTOMRIGHT", questFrame.scrolldownbutton, "TOPRIGHT", -1, -2)
        questFrame.ScrollBar:SetValueStep(25)
        questFrame.ScrollBar.scrollStep = 25
        questFrame.ScrollBar:SetValue(0)
        questFrame.scrollBarHideable = true
        questFrame.ScrollBar:Hide()

        questFrame.ScrollUpButton = _G[frameName .. "ScrollBarScrollUpButton"]
        questFrame.ScrollUpButton:ClearAllPoints()
        questFrame.ScrollUpButton:SetPoint("TOPRIGHT", questFrame.ScrollFrame, "TOPRIGHT", -4, -1)
        questFrame.ScrollUpButton:Hide()

        questFrame.ScrollDownButton = _G[frameName .. "ScrollBarScrollDownButton"]
        questFrame.ScrollDownButton:ClearAllPoints()
        questFrame.ScrollDownButton:SetPoint("BOTTOMRIGHT", questFrame.ScrollFrame, "BOTTOMRIGHT", -4, -7)
        questFrame.ScrollDownButton:Hide()

        questFrame.ScrollBg = questFrame.ScrollBar:CreateTexture(nil, "BACKGROUND")
        questFrame.ScrollBg:SetAllPoints(questFrame.ScrollBar)
        if (not QuestieCompat.Is335) then
            questFrame.ScrollBg:SetColorTexture(0, 0, 0, 0.75)
        end
        questFrame.ScrollBg:Hide()

        questFrame.ScrollChildFrame = CreateFrame("Frame", _G[frameName .. "ScrollChildFrame"])
    else
        questFrame.ScrollFrame.ScrollBar:Hide()
        questFrame.ScrollChildFrame = CreateFrame("Frame", "TrackedQuestsScrollChildFrame")
    end

    questFrame.ScrollChildFrame:SetSize(questFrame.ScrollFrame:GetWidth(), (questFrame.ScrollFrame:GetHeight()))

    questFrame.ScrollFrame:SetScrollChild(questFrame.ScrollChildFrame)

    questFrame:Hide()

    TrackerQuestFrame.questFrame = questFrame

    return questFrame
end

function TrackerQuestFrame:Update()
    local showCollapsedAutoQuestNotice = not Questie.db.char.isTrackerExpanded
        and QuestieTracker:HasAutoQuestNotice()
    if Questie.db.char.isTrackerExpanded or showCollapsedAutoQuestNotice then
        questFrame:ClearAllPoints()
        TrackerQuestFrame.PositionTrackedQuestsFrame()

        questFrame:Show()

        -- Enables Click-Through when the tracker is locked
        if IsControlKeyDown() or (not Questie.db.profile.trackerLocked) then
            QuestieCombatQueue:Queue(function()
                questFrame:EnableMouse(true)
                questFrame:SetMovable(true)
                questFrame:SetResizable(true)
            end)
        else
            QuestieCombatQueue:Queue(function()
                questFrame:EnableMouse(false)
                questFrame:SetMovable(false)
                questFrame:SetResizable(false)
            end)
        end
    else
        questFrame:Hide()
    end
end

function TrackerQuestFrame.PositionTrackedQuestsFrame()
    local QuestieTrackerLoc = Questie.db.profile.TrackerLocation
    local trackerTopSpacing = math.max(0, tonumber(Questie.db.profile.trackerTopSpacing) or 0)
    local baseTopInset = TRACKER_CONTENT_EDGE_INSET + trackerTopSpacing
    local baseBottomInset = TRACKER_CONTENT_EDGE_INSET + math.max(0, tonumber(Questie.db.profile.trackerBottomSpacing) or 0)
    if Questie.db.profile.trackerHeaderEnabled or (Questie.db.profile.alwaysShowTracker and not QuestieTracker:HasQuest()) then
        if Questie.db.profile.moveHeaderToBottom then
            questFrame:SetPoint("TOPLEFT", trackerBaseFrame, "TOPLEFT", 0, -baseTopInset)
        else
            -- Move the tracker header to the top
            questFrame:SetPoint("TOPLEFT", trackerHeaderFrame, "BOTTOMLEFT", 0, -trackerTopSpacing)
        end
    elseif QuestieTrackerLoc and (QuestieTrackerLoc[1] == "BOTTOMLEFT" or QuestieTrackerLoc[1] == "BOTTOMRIGHT") then
        -- No header. TrackedQuestsFrame is attached to the bottom.
        questFrame:SetPoint("BOTTOMLEFT", trackerBaseFrame, "BOTTOMLEFT", 0, baseBottomInset)
    else
        -- No header. TrackedQuestsFrame is attached to the top.
        questFrame:SetPoint("TOPLEFT", trackerBaseFrame, "TOPLEFT", 0, -baseTopInset)
    end
end
