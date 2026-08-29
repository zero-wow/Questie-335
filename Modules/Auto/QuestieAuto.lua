---@class QuestieAuto
---@field private private QuestieAutoPrivate
local QuestieAuto = QuestieLoader:CreateModule("QuestieAuto");
local _QuestieAuto = QuestieAuto.private
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB");
---@type QuestiePlayer
local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")

--- COMPATIBILITY ---
local C_Timer = QuestieCompat.C_Timer
local GetQuestID = QuestieCompat.GetQuestID

local ceil = math.ceil
local floor = math.floor
local max = math.max

local shouldRunAuto = true
local doneTalking = false

local cameFromProgressEvent = false
local isAllowedNPC = false
local lastAmountOfAvailableQuests = 0
local lastNPCTalkedTo
local doneWithAccept = false
local lastIndexTried = 1
local lastEvent
local merchantAutoBuySession = {
    pendingItems = {},
    lastOwned = {},
}

local MOP_INDEX_AVAILABLE = 7 -- was '5' in Cataclysm
local MOP_INDEX_COMPLETE = 6  -- was '4' in Cataclysm

-- forward declarations
local _SelectAvailableQuest

local function _ResetMerchantAutoBuySession()
    merchantAutoBuySession.pendingItems = {}
    merchantAutoBuySession.lastOwned = {}
end

local function _GetItemIdFromLink(link)
    if not link then
        return nil
    end

    return tonumber(string.match(link, "item:(%d+)"))
end

local function _GetEffectiveOwnedCount(itemId)
    local currentOwned = GetItemCount(itemId, false, false) or 0
    local previousOwned = merchantAutoBuySession.lastOwned[itemId]

    if previousOwned and currentOwned > previousOwned then
        local gained = currentOwned - previousOwned
        local pending = merchantAutoBuySession.pendingItems[itemId] or 0
        if pending > 0 then
            merchantAutoBuySession.pendingItems[itemId] = max(0, pending - gained)
        end
    end

    merchantAutoBuySession.lastOwned[itemId] = currentOwned

    return currentOwned + (merchantAutoBuySession.pendingItems[itemId] or 0)
end

local function _TrackNeededItem(neededItems, itemId, targetOwned)
    if (not itemId) or itemId <= 0 or (not targetOwned) or targetOwned <= 0 then
        return
    end

    local existing = neededItems[itemId]
    if existing then
        existing.targetOwned = max(existing.targetOwned or 0, targetOwned)
    else
        neededItems[itemId] = {
            targetOwned = targetOwned,
        }
    end
end

local function _TrackNeededItemPattern(neededItemPatterns, description, targetOwned)
    if type(description) ~= "string" or description == "" or (not targetOwned) or targetOwned <= 0 then
        return
    end

    local loweredDescription = string.lower(description)
    local existing = neededItemPatterns[loweredDescription]
    if existing then
        existing.targetOwned = max(existing.targetOwned or 0, targetOwned)
    else
        neededItemPatterns[loweredDescription] = {
            pattern = loweredDescription,
            targetOwned = targetOwned,
        }
    end
end

local function _FindNeededItemByName(neededItemPatterns, itemName)
    if type(itemName) ~= "string" or itemName == "" then
        return nil
    end

    local loweredItemName = string.lower(itemName)
    local bestMatch

    for _, patternData in pairs(neededItemPatterns) do
        if patternData and patternData.pattern and string.find(patternData.pattern, loweredItemName, 1, true) then
            if (not bestMatch) or ((patternData.targetOwned or 0) > (bestMatch.targetOwned or 0)) then
                bestMatch = patternData
            end
        end
    end

    return bestMatch
end

local function _IsQuestComplete(quest)
    if not quest then
        return true
    end

    if type(quest.IsComplete) == "function" then
        return quest:IsComplete() == 1
    end

    return quest.isComplete == true or quest.WasComplete == true
end

local function _CollectNeededQuestItems()
    local neededItems = {}
    local neededItemPatterns = {}

    for questId, activeQuest in pairs(QuestiePlayer.currentQuestlog) do
        local quest = type(activeQuest) == "table" and activeQuest or QuestieDB.GetQuest(questId)

        if quest and (not _IsQuestComplete(quest)) then
            if quest.Objectives then
                for _, objective in pairs(quest.Objectives) do
                    if objective and objective.Type == "item" and objective.Completed ~= true then
                        local targetOwned = tonumber(objective.Needed) or 0
                        if quest._liveQuestFallback then
                            _TrackNeededItemPattern(neededItemPatterns, objective.Description, targetOwned)
                        elseif objective.Id and objective.Id > 0 then
                            _TrackNeededItem(neededItems, objective.Id, targetOwned)
                        else
                            _TrackNeededItemPattern(neededItemPatterns, objective.Description, targetOwned)
                        end
                    end
                end
            end

            if next(quest.SpecialObjectives or {}) then
                for _, objective in pairs(quest.SpecialObjectives) do
                    if objective and objective.Type == "item" and objective.Id and objective.Id > 0 and objective.Completed ~= true then
                        local targetOwned = tonumber(objective.Needed) or 1
                        _TrackNeededItem(neededItems, objective.Id, targetOwned)
                    end
                end
            end

            if quest.sourceItemId and quest.sourceItemId > 0 then
                _TrackNeededItem(neededItems, quest.sourceItemId, 1)
            end

            if type(quest.requiredSourceItems) == "table" then
                for _, itemId in pairs(quest.requiredSourceItems) do
                    _TrackNeededItem(neededItems, itemId, 1)
                end
            end

            if quest.SpellItemId and quest.SpellItemId > 0 then
                _TrackNeededItem(neededItems, quest.SpellItemId, 1)
            end
        end
    end

    return neededItems, neededItemPatterns
end

local function _AutoBuyQuestItems()
    if not Questie.db.profile.autobuyQuestItems then
        return
    end

    if _QuestieAuto:IsBindTrue(Questie.db.profile.autoModifier) then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Modifier-Key down: Skipping auto-buy quest items")
        return
    end

    local merchantItemCount = GetMerchantNumItems and GetMerchantNumItems() or 0
    if merchantItemCount <= 0 then
        return
    end

    local neededItems, neededItemPatterns = _CollectNeededQuestItems()
    if (not next(neededItems)) and (not next(neededItemPatterns)) then
        return
    end

    local remainingMoney = GetMoney() or 0

    for merchantIndex = 1, merchantItemCount do
        local itemId = _GetItemIdFromLink(GetMerchantItemLink(merchantIndex))
        local name, _, price, quantity, numAvailable, _, extendedCost = GetMerchantItemInfo(merchantIndex)
        local neededItem = itemId and neededItems[itemId]

        if (not neededItem) and name then
            neededItem = _FindNeededItemByName(neededItemPatterns, name)
        end

        if neededItem and itemId then
            if name and not extendedCost then
                local effectiveOwned = _GetEffectiveOwnedCount(itemId)
                local missingItems = (neededItem.targetOwned or 0) - effectiveOwned

                if missingItems > 0 then
                    local itemsPerPurchase = max(1, tonumber(quantity) or 1)
                    local purchaseCount = ceil(missingItems / itemsPerPurchase)

                    if numAvailable and numAvailable > -1 then
                        purchaseCount = math.min(purchaseCount, numAvailable)
                    end

                    if price and price > 0 then
                        purchaseCount = math.min(purchaseCount, floor(remainingMoney / price))
                    end

                    local merchantMaxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(merchantIndex)
                    if merchantMaxStack and merchantMaxStack > 0 then
                        purchaseCount = math.min(purchaseCount, merchantMaxStack)
                    end

                    if purchaseCount and purchaseCount > 0 then
                        local purchasedItems = purchaseCount * itemsPerPurchase
                        merchantAutoBuySession.pendingItems[itemId] = (merchantAutoBuySession.pendingItems[itemId] or 0) + purchasedItems
                        remainingMoney = remainingMoney - ((price or 0) * purchaseCount)
                        Questie:Debug(Questie.DEBUG_INFO, "[QuestieAuto] Auto-buying quest item:", itemId, name, "lots:", purchaseCount, "items:", purchasedItems)
                        BuyMerchantItem(merchantIndex, purchaseCount)
                    end
                end
            end
        end
    end
end


local function ResetModifier()
    shouldRunAuto = true
    lastEvent = nil
end

function QuestieAuto:GOSSIP_SHOW(event, ...)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto][EVENT] GOSSIP_SHOW", event, ...)
    doneTalking = false

    if (not shouldRunAuto) then
        return
    elseif _QuestieAuto:IsBindTrue(Questie.db.profile.autoModifier) then
        shouldRunAuto = false
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Modifier-Key down: Disabling QuestieAuto for now")
        return
    end
    lastEvent = "GOSSIP_SHOW"

    local availableQuests = { QuestieCompat.GetAvailableQuests() }
    local currentNPC = UnitName("target")
    if lastNPCTalkedTo ~= currentNPC or #availableQuests ~= lastAmountOfAvailableQuests then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Greeted by a new NPC")
        lastNPCTalkedTo = currentNPC
        isAllowedNPC = _QuestieAuto:IsAllowedNPC()
        lastIndexTried = 1
        lastAmountOfAvailableQuests = #availableQuests
        doneWithAccept = false
    end

    if cameFromProgressEvent then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Last event was Progress")
        cameFromProgressEvent = false
        lastIndexTried = lastIndexTried + MOP_INDEX_AVAILABLE
    end

    -- Turn in complete quests
    if Questie.db.profile.autocomplete and isAllowedNPC then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Checking active quests from gossip")
        local completeQuests = { QuestieCompat.GetActiveQuests() }

        for index = 1, #completeQuests, MOP_INDEX_COMPLETE do
            _QuestieAuto:CompleteQuestFromGossip(index, completeQuests, MOP_INDEX_COMPLETE)
        end
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] DONE. Checked all complete quests")
    end

    -- Accept new quests
    if Questie.db.profile.autoaccept and (not doneWithAccept) and isAllowedNPC then
        if lastIndexTried < #availableQuests then
            Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Checking available quests from gossip")
            _QuestieAuto:AcceptQuestFromGossip(lastIndexTried, availableQuests, MOP_INDEX_AVAILABLE)
            return
        else
            Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] DONE. Checked all available quests")
            doneWithAccept = true
            lastIndexTried = 1
        end
    end
end

function QuestieAuto:QUEST_PROGRESS(event, ...)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto][EVENT] QUEST_PROGRESS", event, ...)
    doneTalking = false

    if (not shouldRunAuto) then
        return
    elseif _QuestieAuto:IsBindTrue(Questie.db.profile.autoModifier) then
        shouldRunAuto = false
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Modifier-Key down: Disabling QuestieAuto for now")
        return
    end

    if Questie.db.profile.autocomplete then
        if _QuestieAuto:IsAllowedNPC() and _QuestieAuto:IsAllowedQuest() then
            if IsQuestCompletable() then
                CompleteQuest()
                return
            else
                Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Quest not completeable. Index", lastIndexTried)
            end
        end

        -- Close the QuestFrame if no quest is completeable again
        if QuestFrameGoodbyeButton and lastEvent ~= nil then
            QuestFrameGoodbyeButton:Click()
        end
        cameFromProgressEvent = true
    end
    lastEvent = "QUEST_PROGRESS"
end

_SelectAvailableQuest = function(index)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Selecting available quest at index", index)
    SelectAvailableQuest(index)
end

function QuestieAuto:QUEST_ACCEPT_CONFIRM(event, ...)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto][EVENT] QUEST_ACCEPT_CONFIRM", event, ...)
    lastEvent = "QUEST_ACCEPT_CONFIRM"
    doneTalking = false
    -- Escort stuff
    if (Questie.db.profile.autoaccept) then
        ConfirmAcceptQuest()
    end
end

function QuestieAuto:QUEST_GREETING(event, ...)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto][EVENT] QUEST_GREETING", event, GetNumActiveQuests(), ...)
    lastEvent = "QUEST_GREETING"
    doneTalking = false

    if (not shouldRunAuto) then
        return
    elseif _QuestieAuto:IsBindTrue(Questie.db.profile.autoModifier) then
        shouldRunAuto = false
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Modifier-Key down: Disabling QuestieAuto for now")
        return
    end

    if cameFromProgressEvent then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Last event was Progress")
        cameFromProgressEvent = false
        lastIndexTried = lastIndexTried + 1
    end

    -- Quest already taken
    if (Questie.db.profile.autocomplete) then
        for index = 1, GetNumActiveQuests() do
            local quest, isComplete = GetActiveTitle(index)
            Questie:Debug(Questie.DEBUG_DEVELOP, quest, isComplete)
            if isComplete then SelectActiveQuest(index) end
        end
    end

    if (Questie.db.profile.autoaccept) then
        local availableQuestsCount = GetNumAvailableQuests()
        if lastIndexTried == 0 or lastIndexTried > availableQuestsCount then
            lastIndexTried = 1
        end
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] lastIndex:", lastIndexTried)
        if availableQuestsCount > 0 and lastIndexTried < availableQuestsCount then
            _SelectAvailableQuest(lastIndexTried)
        end
    end
end

function QuestieAuto:QUEST_DETAIL(event, ...)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto][EVENT] QUEST_DETAIL", event, ...)
    lastEvent = "QUEST_DETAIL"
    doneTalking = false

    if (not shouldRunAuto) then
        return
    elseif _QuestieAuto:IsBindTrue(Questie.db.profile.autoModifier) then
        shouldRunAuto = false
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Modifier-Key down: Disabling QuestieAuto for now")
        return
    end

    -- We really want to disable this in instances, mostly to prevent retards from ruining groups.
    if (Questie.db.profile.autoaccept and _QuestieAuto:IsAllowedNPC() and _QuestieAuto:IsAllowedQuest(true)) then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] INSIDE", event, ...)

        local questId = GetQuestID(true)
        local questLevel

        if questId and questId ~= 0 then
            questLevel = QuestieDB.QueryQuestSingle(questId, "questLevel")
        end

        if not questLevel then
            Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] No quest object, retrying in 1 second")
            C_Timer.After(1, function()
                questId = GetQuestID(true)
                if questId and questId ~= 0 then
                    questLevel = QuestieDB.QueryQuestSingle(questId, "questLevel")
                    if not questLevel then
                        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] retry failed. Quest", questId, "might not be in the DB!")
                    elseif (not QuestieDB.IsTrivial(questLevel)) or Questie.db.profile.acceptTrivial then
                        Questie:Debug(Questie.DEBUG_INFO, "[QuestieAuto] Questie Auto-Accepting quest:", questId)
                        AcceptQuest()
                    end
                end
            end)

            return
        end

        if (not QuestieDB.IsTrivial(questLevel)) or Questie.db.profile.acceptTrivial then
            Questie:Debug(Questie.DEBUG_INFO, "[QuestieAuto] Questie Auto-Accepting quest:", questId)
            AcceptQuest()
        end
    end
end

-- I was forced to make decision on offhand, cloak and shields separate from armor but I can't pick up my mind about the reason...
function QuestieAuto:QUEST_COMPLETE(event, ...)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[EVENT] QUEST_COMPLETE", event, ...)
    lastEvent = "QUEST_COMPLETE"
    doneTalking = false

    if (not shouldRunAuto) then
        return
    elseif _QuestieAuto:IsBindTrue(Questie.db.profile.autoModifier) then
        shouldRunAuto = false
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Modifier-Key down: Disabling QuestieAuto for now")
        return
    end

    -- blasted Lands citadel wonderful NPC. They do not trigger any events except quest_complete.
    -- if not AllowedToHandle() then
    --    return
    -- end
    if (Questie.db.profile.autocomplete) then
        local questname = GetTitleText()
        local numOptions = GetNumQuestChoices()
        Questie:Debug(Questie.DEBUG_DEVELOP, event, questname, numOptions, ...)

        if numOptions > 1 then
            Questie:Debug(Questie.DEBUG_INFO, "[QuestieAuto] Multiple rewards (" .. numOptions .. ")! Please choose appropriate reward!")
        else
            _QuestieAuto:TurnInQuest(1)
            Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] Completed quest!")
        end
    end
end

local _QuestFinishedCallback = function()
    if _QuestieAuto:AllQuestWindowsClosed() then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] All quest windows closed! Resetting shouldRunAuto")
        ResetModifier()
    end
end

function QuestieAuto:QUEST_FINISHED()
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto][EVENT] QUEST_FINISHED")

    C_Timer.After(0.5, _QuestFinishedCallback)
end

function QuestieAuto:QUEST_ACCEPTED()
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto][EVENT] QUEST_ACCEPTED")
    if Questie.db.profile.bugWorkarounds == true and QuestFrameDetailPanel:IsVisible() == true then
        QuestFrameCloseButton:Click()
    end
end

function QuestieAuto:MERCHANT_SHOW(event, ...)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto][EVENT] MERCHANT_SHOW", event, ...)
    _ResetMerchantAutoBuySession()
    _AutoBuyQuestItems()
end

function QuestieAuto:MERCHANT_UPDATE(event, ...)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto][EVENT] MERCHANT_UPDATE", event, ...)
    _AutoBuyQuestItems()
end

function QuestieAuto:MERCHANT_CLOSED(event, ...)
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto][EVENT] MERCHANT_CLOSED", event, ...)
    _ResetMerchantAutoBuySession()
end

--[[ TODO: This function already exsists in Privates.lua line 8. Does it belong here or in Privates?
function _QuestieAuto:AllQuestWindowsClosed()
    if GossipFrame and (not GossipFrame:IsVisible())
        and GossipFrameGreetingPanel and (not GossipFrameGreetingPanel:IsVisible())
        and QuestFrameGreetingPanel and (not QuestFrameGreetingPanel:IsVisible())
        and QuestFrameDetailPanel and (not QuestFrameDetailPanel:IsVisible())
        and QuestFrameProgressPanel and (not QuestFrameProgressPanel:IsVisible())
        and QuestFrameRewardPanel and (not QuestFrameRewardPanel:IsVisible()) then
        return true
    end
    return false
end
--]]
--- The closingCounter needs to reach 1 for QuestieAuto to reset
--- Whenever the gossip frame is closed this event is called once, HOWEVER
--- when totally stop talking to an NPC this event is called twice.
--- Another special case is: If you run away from the NPC the event is called
--- just once.
function QuestieAuto:GOSSIP_CLOSED()
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto][EVENT] GOSSIP_CLOSED")
    lastEvent = "GOSSIP_CLOSED"

    if doneTalking then
        doneTalking = false
        Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieAuto] We are done talking to an NPC! Resetting shouldRunAuto")
        shouldRunAuto = true
        lastEvent = nil
    else
        doneTalking = true
    end
end
