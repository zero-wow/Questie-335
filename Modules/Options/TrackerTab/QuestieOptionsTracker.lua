-------------------------
--Import modules.
-------------------------
---@type QuestieOptions
local QuestieOptions = QuestieLoader:ImportModule("QuestieOptions")
---@type QuestieOptionsUtils
local QuestieOptionsUtils = QuestieLoader:ImportModule("QuestieOptionsUtils")
---@type QuestieTracker
local QuestieTracker = QuestieLoader:ImportModule("QuestieTracker")
---@type TrackerBaseFrame
local TrackerBaseFrame = QuestieLoader:ImportModule("TrackerBaseFrame")
---@type TrackerFonts
local TrackerFonts = QuestieLoader:ImportModule("TrackerFonts")
---@type TrackerLinePool
local TrackerLinePool = QuestieLoader:ImportModule("TrackerLinePool")
---@type TrackerQuestTimers
local TrackerQuestTimers = QuestieLoader:ImportModule("TrackerQuestTimers")

---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

--- COMPATIBILITY ---
local C_Timer = QuestieCompat.C_Timer

QuestieOptions.tabs.tracker = { ... }

local _GetShortcuts
local trackerOptions = {}

local TRACKER_LAYOUT_PRESETS = {
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

local function _HasManualTrackerSize()
    return (tonumber(Questie.db.profile.TrackerWidth) or 0) > 0
        or (tonumber(Questie.db.profile.TrackerHeight) or 0) > 0
end

local function _MatchesLayoutPreset(preset)
    if not preset then
        return false
    end

    return (tonumber(Questie.db.profile.trackerQuestPadding) or 2) == preset.trackerQuestPadding
        and (tonumber(Questie.db.profile.trackerQuestTitlePadding) or 1) == preset.trackerQuestTitlePadding
        and (tonumber(Questie.db.profile.trackerQuestItemGutter) or 4) == preset.trackerQuestItemGutter
        and (tonumber(Questie.db.profile.trackerQuestTitleInset) or 0) == preset.trackerQuestTitleInset
        and (tonumber(Questie.db.profile.trackerObjectiveInset) or 0) == preset.trackerObjectiveInset
        and (tonumber(Questie.db.profile.trackerZoneSpacing) or 0) == preset.trackerZoneSpacing
        and (tonumber(Questie.db.profile.trackerTopSpacing) or 0) == preset.trackerTopSpacing
        and (tonumber(Questie.db.profile.trackerBottomSpacing) or 0) == preset.trackerBottomSpacing
end

local function _GetTrackerLayoutDensity()
    if _MatchesLayoutPreset(TRACKER_LAYOUT_PRESETS.compact) then
        return "compact"
    end

    if _MatchesLayoutPreset(TRACKER_LAYOUT_PRESETS.balanced) then
        return "balanced"
    end

    if _MatchesLayoutPreset(TRACKER_LAYOUT_PRESETS.spacious) then
        return "spacious"
    end

    return "custom"
end

local function _RefreshTrackerLayout(markCustom, resetManualSizer)
    if resetManualSizer and _HasManualTrackerSize() then
        Questie.db.profile.TrackerWidth = 0
        Questie.db.profile.TrackerHeight = 0
    end

    if markCustom then
        Questie.db.profile.trackerLayoutDensity = "custom"
    else
        Questie.db.profile.trackerLayoutDensity = _GetTrackerLayoutDensity()
    end

    QuestieTracker:Update()
end

local function _ApplyTrackerLayoutPreset(key)
    local preset = TRACKER_LAYOUT_PRESETS[key]
    if not preset then
        return
    end

    Questie.db.profile.trackerQuestPadding = preset.trackerQuestPadding
    Questie.db.profile.trackerQuestTitlePadding = preset.trackerQuestTitlePadding
    Questie.db.profile.trackerQuestItemGutter = preset.trackerQuestItemGutter
    Questie.db.profile.trackerQuestTitleInset = preset.trackerQuestTitleInset
    Questie.db.profile.trackerObjectiveInset = preset.trackerObjectiveInset
    Questie.db.profile.trackerZoneSpacing = preset.trackerZoneSpacing
    Questie.db.profile.trackerTopSpacing = preset.trackerTopSpacing
    Questie.db.profile.trackerBottomSpacing = preset.trackerBottomSpacing

    _RefreshTrackerLayout(false, true)
end

local function _FormatTrackerLocation(location)
    if type(location) ~= "table" then
        return "Unavailable"
    end

    local point = tostring(location[1] or "UNKNOWN")
    local relativePoint = tostring(location[3] or point)
    local xOffset = tonumber(location[4]) or 0
    local yOffset = tonumber(location[5]) or 0

    return string.format("%s -> %s @ %.1f, %.1f", point, relativePoint, xOffset, yOffset)
end

local function _GetTrackerDiagnosticsText()
    local savedLocation = TrackerBaseFrame:GetSavedLocation()
    local currentLocation = TrackerBaseFrame:GetCurrentLocation()
    local sizeMode = _HasManualTrackerSize() and "Manual" or "Auto"
    local malformed = TrackerBaseFrame:IsSavedLocationMalformed() and "Yes" or "No"

    return string.format(
        "Growth Direction: %s\nSizer Mode: %s\nMalformed Saved Anchor: %s\nSaved Position: %s\nCurrent Position: %s",
        tostring(Questie.db.profile.trackerSetpoint or "TOPLEFT"),
        sizeMode,
        malformed,
        _FormatTrackerLocation(savedLocation),
        _FormatTrackerLocation(currentLocation)
    )
end

local function _GetColorValue(setting, defaultR, defaultG, defaultB, defaultA)
    local color = Questie.db.profile[setting]
    if type(color) ~= "table" then
        return defaultR, defaultG, defaultB, defaultA
    end

    return tonumber(color[1]) or defaultR,
        tonumber(color[2]) or defaultG,
        tonumber(color[3]) or defaultB,
        tonumber(color[4]) or defaultA
end

local function _SetColorValue(setting, r, g, b, a)
    if a ~= nil then
        Questie.db.profile[setting] = { r, g, b, a }
    else
        Questie.db.profile[setting] = { r, g, b }
    end
end

local function _ApplyTrackerBackdropPreview()
    if not TrackerBaseFrame.baseFrame then
        return
    end

    local bgR, bgG, bgB = _GetColorValue("trackerBackdropColor", 0, 0, 0)
    local borderR, borderG, borderB = _GetColorValue("trackerBorderColor", 1, 1, 1)

    if Questie.db.profile.trackerBackdropEnabled then
        local bgAlpha = Questie.db.profile.trackerBackdropFader and 0 or Questie.db.profile.trackerBackdropAlpha
        TrackerBaseFrame.baseFrame:SetBackdropColor(bgR, bgG, bgB, bgAlpha)

        if Questie.db.profile.trackerBorderEnabled then
            local borderAlpha = Questie.db.profile.trackerBackdropFader and 0 or (Questie.db.profile.trackerBorderAlpha or Questie.db.profile.trackerBackdropAlpha)
            TrackerBaseFrame.baseFrame:SetBackdropBorderColor(borderR, borderG, borderB, borderAlpha)
        else
            TrackerBaseFrame.baseFrame:SetBackdropBorderColor(borderR, borderG, borderB, 0)
        end
    else
        TrackerBaseFrame.baseFrame:SetBackdropColor(bgR, bgG, bgB, 0)
        TrackerBaseFrame.baseFrame:SetBackdropBorderColor(borderR, borderG, borderB, 0)
    end
end

function QuestieOptions.tabs.tracker:Initialize()
    trackerOptions = {
        name = function() return l10n('Tracker') end,
        type = "group",
        order = 3,
        args = {
            header = {
                type = "header",
                order = 1,
                name = function() return l10n('Tracker Options') end,
            },
            enableQuestieTracker = {
                type = "toggle",
                order = 2,
                width = 1.5,
                name = function() return l10n('Enable Tracker') end,
                desc = function() return l10n("Enabling the Tracker will replace the default Blizzard Quest Tracker with the Questie Tracker.\n\nNOTE: Changing this setting will reload the UI.") end,
                disabled = function() return InCombatLockdown() end,
                get = function() return Questie.db.profile.trackerEnabled end,
                set = function()
                    if Questie.db.profile.trackerEnabled then
                        QuestieTracker:Disable()
                    else
                        QuestieTracker:Enable()
                    end
                end
            },
            Space_X = QuestieOptionsUtils:HorizontalSpacer(3, 0.1),
            resetTrackerLocation = {
                type = "execute",
                order = 4,
                width = 0.8,
                name = function() return l10n('Reset Tracker') end,
                desc = function() return l10n("If the Questie Tracker is stuck offscreen or lost, you can reset it's location to the center of the screen with this button.") end,
                disabled = function() return not Questie.db.profile.trackerEnabled or InCombatLockdown() end,
                func = function()
                    QuestieTracker:ResetLocation()
                    QuestieTracker:Update()
                end
            },
            Spacer_S = QuestieOptionsUtils:Spacer(5),
            group_quests = {
                type = "group",
                order = 6,
                inline = true,
                width = 0.5,
                name = function() return l10n("Quest and Achievement Options") end,
                disabled = function() return not Questie.db.profile.trackerEnabled end,
                args = {
                    autoTrackQuests = {
                        type = "toggle",
                        order = 1,
                        width = 1.5,
                        name = function() return l10n('Auto Track Quests') end,
                        desc = function() return l10n("This is the same as 'Enable Automatic Quest Tracking' in the Blizzard Interface Options. When enabled, the Questie Tracker will automatically track all Quests in your Quest Log. Disabling this option will untrack all Quests. You will have to manually select which Quests to track.\n\nNOTE: 'Show Complete Quests' is disabled while this option is not being used.") end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.autoTrackQuests end,
                        set = function(_, value)
                            Questie.db.profile.autoTrackQuests = value
                            if value then
                                Questie.db.char.TrackedQuests = {}
                            else
                                Questie.db.char.AutoUntrackedQuests = {}
                            end

                            -- Update Quest Log and mark tracked Quests
                            local questLogFrame = QuestLogExFrame or ClassicQuestLog or QuestLogFrame
                            if questLogFrame:IsShown() then
                                QuestLog_Update()
                            end

                            QuestieTracker:Update()
                        end
                    },
                    showQuestLevels = {
                        type = "toggle",
                        order = 2,
                        width = 1.5,
                        name = function() return l10n('Show Quest Level') end,
                        desc = function() return l10n('When this is checked, the Quest Level Tags for Quest Titles will show in the Questie Tracker.') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerShowQuestLevel end,
                        set = function(_, value)
                            Questie.db.profile.trackerShowQuestLevel = value
                            QuestieTracker:Update()
                        end
                    },
                    showQuestTimer = {
                        type = "toggle",
                        order = 3,
                        width = 1.5,
                        name = function() return l10n('Show Blizzard Timer') end,
                        desc = function() return l10n('When this is checked, the default Blizzard Timer Frame for Quests will be shown instead of being embedded inside the Questie Tracker.') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.showBlizzardQuestTimer end,
                        set = function(_, value)
                            Questie.db.profile.showBlizzardQuestTimer = value

                            if value == true then
                                TrackerQuestTimers:ShowBlizzardTimer()
                            else
                                TrackerQuestTimers:HideBlizzardTimer()
                            end

                            QuestieTracker:Update()
                        end
                    },
                    listAchievementsFirst = {
                        type = "toggle",
                        order = 4,
                        width = 1.5,
                        name = function() return l10n("List Achievements First") end,
                        desc = function() return l10n("When this is checked, the Questie Tracker will list Achievements first then Quests.") end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        hidden = function() return not (Questie.IsWotlk or QuestieCompat.Is335) end,
                        get = function() return Questie.db.profile.listAchievementsFirst end,
                        set = function(_, value)
                            Questie.db.profile.listAchievementsFirst = value
                            QuestieTracker:Update()
                        end
                    },
                    collapseDirection = {
                        type = "select",
                        order = 5,
                        width = 1.5,
                        values = function()
                            return {
                                normal = l10n("Normal"),
                                upward = l10n("Upward Into Header"),
                            }
                        end,
                        style = "dropdown",
                        name = function() return l10n("Collapse Direction") end,
                        desc = function()
                            return l10n("Normal uses the configured Tracker Growth Direction. Upward Into Header keeps the top/titlebar edge fixed so quests, zones, and the tracker itself collapse upward into the header and expand downward from it.")
                        end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerCollapseDirection or "normal" end,
                        set = function(_, key)
                            Questie.db.profile.trackerCollapseDirection = key == "upward" and "upward" or "normal"
                        end
                    },
                    Spacer_Dropdowns = QuestieOptionsUtils:Spacer(5.1),
                    openQuestLog = {
                        type = "select",
                        order = 7,
                        values = _GetShortcuts(),
                        style = 'dropdown',
                        name = function()
                            if Questie.IsWotlk then
                                return l10n('Show Quest / Achievement')
                            else
                                return l10n('Show in Quest Log')
                            end
                        end,
                        desc = function()
                            if Questie.IsWotlk then
                                return l10n('This shortcut will open the Quest Log with the clicked Quest selected or open Achievements with the clicked Achievement selected.')
                            else
                                return l10n('This shortcut will open the Quest Log with the clicked Quest selected.')
                            end
                        end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerbindOpenQuestLog end,
                        set = function(_, key)
                            Questie.db.profile.trackerbindOpenQuestLog = key
                        end
                    },
                    Space_Y = QuestieOptionsUtils:HorizontalSpacer(7.1, 0.1),
                    untrackQuest = {
                        type = "select",
                        order = 8,
                        values = _GetShortcuts(),
                        style = 'dropdown',
                        name = function()
                            if Questie.IsWotlk then
                                return l10n('Untrack / Link')
                            else
                                return l10n('Untrack / Link Quest')
                            end
                        end,
                        desc = function()
                            if Questie.IsWotlk then
                                return l10n('This shortcut removes a Quest or an Achievement from the Questie Tracker when the chat input box is NOT visible, otherwise this will link a Quest or an Achievement to chat.')
                            else
                                return l10n('This shortcut removes a Quest from the Questie Tracker when the chat input box is NOT visible, otherwise this will link a Quest to chat.')
                            end
                        end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerbindUntrack end,
                        set = function(_, key)
                            Questie.db.profile.trackerbindUntrack = key
                        end
                    },
                    Spacer_Sliders = QuestieOptionsUtils:Spacer(9),
                    group_tracker = {
                        type = "group",
                        order = 11,
                        inline = true,
                        width = 0.5,
                        name = function() return l10n('Objectives'); end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        args = {
                            showCompleteQuests = {
                                type = "toggle",
                                order = 1,
                                width = 1.5,
                                name = function() return l10n('Show Completed Quests') end,
                                desc = function() return l10n("When this is checked, completed Quests will show in the Questie Tracker.\n\nNOTE: This setting only works when 'Auto Track Quests' is enabled.") end,
                                disabled = function() return (not Questie.db.profile.trackerEnabled) or (not Questie.db.profile.autoTrackQuests) end,
                                get = function() return Questie.db.profile.trackerShowCompleteQuests end,
                                set = function(_, value)
                                    Questie.db.profile.trackerShowCompleteQuests = value
                                    QuestieTracker:Update()
                                end
                            },
                            collapseCompletedQuests = {
                                type = "toggle",
                                order = 2,
                                width = 1.5,
                                name = function() return l10n('Auto Minimize Completed Quests') end,
                                desc = function() return l10n('When this is checked, completed Quests will automatically minimize.') end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return Questie.db.profile.collapseCompletedQuests end,
                                set = function(_, value)
                                    Questie.db.profile.collapseCompletedQuests = value
                                    if value == false then
                                        for questId in pairs(Questie.db.char.autoCollapsedQuests or {}) do
                                            Questie.db.char.collapsedQuests[questId] = nil
                                        end
                                        Questie.db.char.autoCollapsedQuests = {}
                                    end
                                    QuestieTracker:Update()
                                end
                            },
                            collapseCompletedQuestsCurrentZoneOnly = {
                                type = "toggle",
                                order = 2.1,
                                width = 1.5,
                                name = function() return l10n('Active Zone Only') end,
                                desc = function() return l10n('Only auto-minimize completed quests assigned to your current zone or subzone. Manually minimized quests are left alone.') end,
                                disabled = function()
                                    return not Questie.db.profile.trackerEnabled
                                        or not Questie.db.profile.collapseCompletedQuests
                                end,
                                get = function() return Questie.db.profile.collapseCompletedQuestsCurrentZoneOnly end,
                                set = function(_, value)
                                    for questId in pairs(Questie.db.char.autoCollapsedQuests or {}) do
                                        Questie.db.char.collapsedQuests[questId] = nil
                                    end
                                    Questie.db.char.autoCollapsedQuests = {}
                                    Questie.db.profile.collapseCompletedQuestsCurrentZoneOnly = value
                                    QuestieTracker:Update()
                                end
                            },
                            hideCompletedQuestObjectives = {
                                type = "toggle",
                                order = 3,
                                width = 1.5,
                                name = function() return l10n('Hide Completed Quest Objectives') end,
                                desc = function() return l10n('When this is checked, completed Quest Objectives will automatically be removed from the Questie Tracker.') end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return Questie.db.profile.hideCompletedQuestObjectives end,
                                set = function(_, value)
                                    Questie.db.profile.hideCompletedQuestObjectives = value
                                    QuestieTracker:Update()
                                end
                            },
                            hideCompletedAchieveObjectives = {
                                type = "toggle",
                                order = 4,
                                width = 1.5,
                                name = function() return l10n('Hide Completed Achieve Objectives') end,
                                desc = function() return l10n('When this is checked, completed Achievement Objectives will automatically be removed from the Questie Tracker.') end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                hidden = function() return not Questie.IsWotlk end,
                                get = function() return Questie.db.profile.hideCompletedAchieveObjectives end,
                                set = function(_, value)
                                    Questie.db.profile.hideCompletedAchieveObjectives = value
                                    QuestieTracker:Update()
                                end
                            },
                            Spacer_X = QuestieOptionsUtils:Spacer(5),
                            colorObjectives = {
                                type = "select",
                                order = 6,
                                values = function()
                                     return {
                                         ['white'] = l10n('White'),
                                         ['whiteToGreen'] = l10n('White to Green'),
                                         ['whiteAndGreen'] = l10n('White and Green'),
                                         ['redToGreen'] = l10n('Red to Green'),
                                         ['questProgress'] = l10n('Quest %% Complete'),
                                         ['minimal'] = l10n('Minimalistic')
                                     }
                                 end,
                                 style = 'dropdown',
                                 name = function() return l10n('Objective Color') end,
                                 desc = function() return l10n('Change the color of Objectives in the Questie Tracker by how complete they are. "Quest %% Complete" colors quest objectives from the parent quest progress instead of each individual objective.\n\nNOTE: The Minimalistic option will not display the "Blizzard Completion Text" and just label the Quest as either "Quest Complete!" or "Quest Failed!".') end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return Questie.db.profile.trackerColorObjectives end,
                                set = function(_, key)
                                    Questie.db.profile.trackerColorObjectives = key
                                    QuestieTracker:Update()
                                end
                            },
                            Space_Y = QuestieOptionsUtils:HorizontalSpacer(7, 0.1),
                            hideBlizzardCompletionText = {
                                type = "toggle",
                                order = 8,
                                width = 1.5,
                                name = function() return l10n('Hide Blizzard Completion Text') end,
                                desc = function() return l10n('When this is checked, Blizzard Completion Text will be hidden for completed Quests and instead show the old Questie tags: "Quest Complete!" or "Quest Failed!"') end,
                                disabled = function() return not Questie.db.profile.trackerEnabled or Questie.db.profile.trackerColorObjectives == "minimal" end,
                                get = function() return Questie.db.profile.hideBlizzardCompletionText end,
                                set = function(_, value)
                                    Questie.db.profile.hideBlizzardCompletionText = value
                                    if Questie.db.profile.hideBlizzardCompletionText == false then
                                        Questie.db.char.collapsedQuests = {}
                                    end
                                    QuestieTracker:Update()
                                end
                            },
                            Spacer_Z = QuestieOptionsUtils:Spacer(9),
                            sortObjectives = {
                                type = "select",
                                order = 10,
                                values = function()
                                    return {
                                        ['byComplete'] = l10n('By %% Complete'),
                                        ['byCompleteReversed'] = l10n('By %% Complete (Reversed)'),
                                        ['byLevel'] = l10n('By Level'),
                                        ['byLevelReversed'] = l10n('By Level (Reversed)'),
                                        ['byProximity'] = l10n('By Proximity'),
                                        ['byProximityReversed'] = l10n('By Proximity (Reversed)'),
                                        ['byZone'] = l10n('By Zone'),
                                        ['byZonePlayerProximity'] = l10n('By Zone Prox'),
                                        ['byZonePlayerProximityReversed'] = l10n('By Zone Prox (Reversed)'),
                                    }
                                end,
                                style = 'dropdown',
                                name = function() return l10n('Objective Sorting') end,
                                desc = function() return l10n('How Objectives are sorted in the Questie Tracker.') end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return Questie.db.profile.trackerSortObjectives end,
                                set = function(_, key)
                                    Questie.db.profile.trackerSortObjectives = key
                                    QuestieTracker:Update()
                                end
                            },
                        },
                    },
                    group_lfgObjectives = {
                        type = "group",
                        order = 12,
                        inline = true,
                        width = 0.5,
                        name = function() return l10n('Dungeon Objectives') end,
                        hidden = function() return not QuestieCompat.Is335 end,
                        args = {
                            mirrorLFGObjectives = {
                                type = "toggle",
                                order = 1,
                                width = 1.5,
                                name = function() return l10n('Show Dungeon Objectives') end,
                                desc = function() return l10n("Recreates Ascension's LFG Objective Tracker as a compact, Questie-styled section. The native panel is made invisible only after Questie captures a valid replacement, and it is restored when this option is disabled.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return Questie.db.profile.trackerMirrorLFGObjectives end,
                                set = function(_, value)
                                    Questie.db.profile.trackerMirrorLFGObjectives = value
                                    QuestieTracker:SetLFGObjectiveMirrorEnabled(value)
                                end,
                            },
                            lfgObjectivePosition = {
                                type = "range",
                                order = 2,
                                width = 1.5,
                                name = function() return l10n('Dungeon Section Position') end,
                                desc = function() return l10n('Sets where the dungeon block appears. 0 places it above the first quest-zone block; each higher value places it after that many visible zone blocks. A value beyond the available zones places it at the bottom.') end,
                                min = 0,
                                max = 25,
                                step = 1,
                                disabled = function()
                                    return not Questie.db.profile.trackerEnabled
                                        or not Questie.db.profile.trackerMirrorLFGObjectives
                                end,
                                get = function() return tonumber(Questie.db.profile.trackerLFGObjectivePosition) or 0 end,
                                set = function(_, value)
                                    Questie.db.profile.trackerLFGObjectivePosition = math.max(0, math.min(25, math.floor((tonumber(value) or 0) + 0.5)))
                                    QuestieTracker:Update(true)
                                end,
                            },
                        },
                    },
                }
            },
            group_tracker = {
                type = "group",
                order = 8,
                inline = true,
                width = 0.5,
                name = function() return l10n('Tracker Window Options'); end,
                disabled = function() return not Questie.db.profile.trackerEnabled end,
                args = {
                    minimizeInCombat = {
                        type = "toggle",
                        order = 1,
                        width = 1.5,
                        name = function() return l10n('Minimize In Combat') end,
                        desc = function() return l10n('When this is checked, the Questie Tracker will automatically be minimized while entering combat.') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.hideTrackerInCombat end,
                        set = function(_, value)
                            Questie.db.profile.hideTrackerInCombat = value
                        end
                    },
                    minimizeInDungeons = {
                        type = "toggle",
                        order = 2,
                        width = 1.5,
                        name = function() return l10n('Minimize In Dungeons') end,
                        desc = function() return l10n('When this is checked, the Questie Tracker will automatically be minimized when entering a dungeon.') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.hideTrackerInDungeons end,
                        set = function(_, value)
                            Questie.db.profile.hideTrackerInDungeons = value
                            if value and IsInInstance() then
                                QuestieTracker:Collapse()
                            else
                                QuestieTracker:Expand()
                            end
                        end
                    },
                    fadeMinMaxButtons = {
                        type = "toggle",
                        order = 3,
                        width = 1.5,
                        name = function() return l10n('Fade Min/Max Buttons') end,
                        desc = function() return l10n('When this is checked, the Minimize and Maximize Buttons will fade and become transparent when not in use.') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerFadeMinMaxButtons end,
                        set = function(_, value)
                            Questie.db.profile.trackerFadeMinMaxButtons = value
                            if value == true then
                                local fadeTicker
                                local fadeTickerValue = 1
                                fadeTicker = C_Timer.NewTicker(0.02, function()
                                    if fadeTickerValue <= 1 then
                                        fadeTickerValue = fadeTickerValue - 0.05

                                        if fadeTickerValue < 0 then
                                            fadeTickerValue = 0
                                            fadeTicker:Cancel()
                                        end

                                        if (Questie.db.char.isTrackerExpanded) then
                                            TrackerLinePool.SetAllExpandQuestAlpha(fadeTickerValue)
                                        end
                                    else
                                        fadeTickerValue:Cancel()
                                        TrackerLinePool.SetAllExpandQuestAlpha(0)
                                    end
                                end)
                            else
                                TrackerLinePool.SetAllExpandQuestAlpha(1)
                            end
                            QuestieTracker:Update()
                        end
                    },
                    fadeQuestItemButtons = {
                        type = "toggle",
                        order = 4,
                        width = 1.5,
                        name = function() return l10n('Fade Quest Item Buttons') end,
                        desc = function() return l10n('When this is checked, the Quest Item Buttons will fade and become transparent when not in use.') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerFadeQuestItemButtons end,
                        set = function(_, value)
                            Questie.db.profile.trackerFadeQuestItemButtons = value
                            if value == true then
                                local fadeTicker
                                local fadeTickerValue = 1
                                fadeTicker = C_Timer.NewTicker(0.02, function()
                                    if fadeTickerValue <= 1 then
                                        fadeTickerValue = fadeTickerValue - 0.05

                                        if fadeTickerValue < 0 then
                                            fadeTickerValue = 0
                                            fadeTicker:Cancel()
                                        end

                                        if (Questie.db.char.isTrackerExpanded) then
                                            TrackerLinePool.SetAllItemButtonAlpha(fadeTickerValue)
                                        end
                                    else
                                        fadeTickerValue:Cancel()
                                        TrackerLinePool.SetAllItemButtonAlpha(0)
                                    end
                                end)
                            else
                                TrackerLinePool.SetAllItemButtonAlpha(1)
                            end
                            QuestieTracker:Update()
                        end
                    },
                    hideSizer = {
                        type = "toggle",
                        order = 5,
                        width = 1.5,
                        name = function() return l10n("Hide Tracker Sizer") end,
                        desc = function() return l10n("When this is checked, the Questie Tracker resize grip in the lower right-hand corner will be hidden.") end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.sizerHidden end,
                        set = function(_, value)
                            Questie.db.profile.sizerHidden = value
                            QuestieTracker:UpdateFormatting()
                        end
                    },
                    lockTracker = {
                        type = "toggle",
                        order = 6,
                        width = 1.5,
                        name = function() return l10n("Lock Tracker") end,
                        desc = function() return l10n("When this is checked, the Questie Tracker is locked and you need to hold CTRL when you want to move it.") end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerLocked end,
                        set = function(_, value)
                            Questie.db.profile.trackerLocked = value
                            TrackerBaseFrame:Update()
                        end
                    },
                    stickyDurabilityFrame = {
                        type = "toggle",
                        order = 7,
                        width = 1.5,
                        name = function() return l10n('Sticky Durability Frame') end,
                        desc = function() return l10n('When this is checked, the durability frame will be placed on the left or right side of the Questie Tracker depending on where the Tracker is placed on your screen.') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.stickyDurabilityFrame end,
                        set = function(_, value)
                            Questie.db.profile.stickyDurabilityFrame = value
                            if value == false then
                                QuestieTracker:ResetDurabilityFrame()
                            end
                            QuestieTracker:Update()
                        end
                    },
                    stickyVoiceOverFrame = {
                        type = "toggle",
                        order = 8,
                        width = 1.5,
                        name = function() return l10n("Sticky VoiceOver Frame") end,
                        desc = function() return l10n("When this is checked, the VoiceOver talking head / sound queue frame will be placed on the left or right side of the Questie Tracker depending on where the Tracker is placed on your screen.") end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        hidden = function() return not (IsAddOnLoaded("AI_VoiceOver") and IsAddOnLoaded("AI_VoiceOverData_Vanilla")) end,
                        get = function() return Questie.db.profile.stickyVoiceOverFrame end,
                        set = function(_, value)
                            Questie.db.profile.stickyVoiceOverFrame = value
                            if value == false then
                                QuestieTracker:ResetVoiceOverFrame()
                            end
                            QuestieTracker:Update()
                        end
                    },
                    questItemButtonPosition = {
                        type = "select",
                        order = 9,
                        values = function()
                            return {
                                ['outsideLeft'] = l10n('Outside Tracker'),
                                ['inside'] = l10n('Inside Tracker'),
                            }
                        end,
                        style = 'dropdown',
                        name = function() return l10n('Quest Item Buttons') end,
                        desc = function() return l10n('Place quest item buttons outside the tracker for a cleaner text column, or keep them inside and only indent text when a usable item actually exists.') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerQuestItemButtonPosition or "outsideLeft" end,
                        set = function(_, key)
                            Questie.db.profile.trackerQuestItemButtonPosition = key
                            QuestieTracker:Update()
                        end
                    },
                    Spacer_Dropdowns = QuestieOptionsUtils:Spacer(9),
                    setTomTom = {
                        type = "select",
                        order = 10,
                        values = _GetShortcuts(),
                        style = 'dropdown',
                        name = function() return l10n('Set |cFF54e33bTomTom|r Target') end,
                        desc = function()
                            if Questie.IsWotlk then
                                return l10n('This shortcut will set the TomTom arrow to point to either an NPC or the first incomplete Quest Objective (if location data is available).\n\nNOTE: This will not work with Achievements.')
                            else
                                return l10n('This shortcut will set the TomTom arrow to point to either an NPC or the first incomplete Quest Objective (if location data is available).')
                            end
                        end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        hidden = function() return not IsAddOnLoaded("TomTom") end,
                        get = function() return Questie.db.profile.trackerbindSetTomTom end,
                        set = function(_, key)
                            Questie.db.profile.trackerbindSetTomTom = key
                        end
                    },
                    trackerSetpoint = {
                        type = "select",
                        order = 11,
                        values = function()
                            return {
                                ["TOPLEFT"] = l10n('Down & Right'),
                                ["BOTTOMLEFT"] = l10n('Up & Right'),
                                ["TOPRIGHT"] = l10n('Down & Left'),
                                ["BOTTOMRIGHT"] = l10n('Up & Left'),
                            }
                        end,
                        style = 'dropdown',
                        name = function() return l10n('Tracker Growth Direction') end,
                        desc = function()
                            return l10n("This determines the direction in which the Questie Tracker grows when you add or remove Quests. For example, if you use the 'Up & Right' option then the ideal place for the Tracker should be in the lower left-hand corner of your screen. This allows the 'Sizer Mode: Auto' to push the Tracker Height and Width 'Up & Right' so the Tracker doesn't inadvertently cover up elements of your UI.")
                        end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerSetpoint end,
                        set = function(_, key)
                            Questie.db.profile.trackerSetpoint = key
                            QuestieTracker:ResetLocation()
                            QuestieTracker:Update()
                        end
                    },
                    Spacer_Sliders = QuestieOptionsUtils:Spacer(12),
                    trackerHeightRatio = {
                        type = "range",
                        order = 13,
                        name = function() return l10n('Tracker Height Ratio') end,
                        desc = function() return l10n('The height of the Questie Tracker based on percentage of usable screen height. A setting of 100 percent would make the Tracker fill the players entire screen height.\n\nNOTE: This setting only applies while in Sizer Mode: Auto') end,
                        width = 3,
                        min = 20,
                        max = 100,
                        step = 1,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerHeightRatio * 100 end,
                        set = function(_, value)
                            Questie.db.profile.trackerHeightRatio = value / 100
                            if IsMouseButtonDown("LeftButton") and Questie.db.profile.TrackerHeight == 0 then
                                TrackerBaseFrame.isSizing = true
                                Questie.db.profile.trackerBackdropEnabled = true
                                Questie.db.profile.trackerBorderEnabled = true
                                Questie.db.profile.trackerBackdropFader = false
                                QuestieTracker:UpdateFormatting()
                            else
                                TrackerBaseFrame.isSizing = false
                                Questie.db.profile.trackerBackdropEnabled = Questie.db.profile.currentBackdropEnabled
                                Questie.db.profile.trackerBorderEnabled = Questie.db.profile.currentBorderEnabled
                                Questie.db.profile.trackerBackdropFader = Questie.db.profile.currentBackdropFader
                                QuestieTracker:UpdateFormatting()
                            end
                        end
                    },
                    trackerScale = {
                        type = "range",
                        order = 14,
                        name = function() return l10n('Tracker Scale') end,
                        desc = function() return l10n('Scales tracker content such as fonts and inline tracker elements without multiplying the tracker padding or spacing. 1.00 is default size and 5.00 is five times larger.') end,
                        width = 3,
                        min = 1,
                        max = 5,
                        step = 0.01,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return tonumber(Questie.db.profile.trackerScale) or 1 end,
                        set = function(_, value)
                            local roundedValue = math.floor(((tonumber(value) or 1) * 100) + 0.5) / 100
                            Questie.db.profile.trackerScale = math.max(1, math.min(5, roundedValue))
                            QuestieTracker:Update()
                        end
                    },
                    group_layout = {
                        type = "group",
                        order = 15,
                        inline = true,
                        width = 0.5,
                        name = function() return l10n("Tracker Layout") end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        args = {
                            layoutDensity = {
                                type = "select",
                                order = 1,
                                width = 1.5,
                                values = function()
                                    return {
                                        compact = l10n("Compact"),
                                        balanced = l10n("Balanced"),
                                        spacious = l10n("Spacious"),
                                        custom = l10n("Custom"),
                                    }
                                end,
                                style = "dropdown",
                                name = function() return l10n("Layout Density") end,
                                desc = function() return l10n("Applies a preset for tracker spacing and quest-item gutter. Choosing one of the presets also returns the tracker sizer to Auto mode so text can reflow cleanly.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return _GetTrackerLayoutDensity() end,
                                set = function(_, key)
                                    if key == "custom" then
                                        Questie.db.profile.trackerLayoutDensity = "custom"
                                        return
                                    end

                                    _ApplyTrackerLayoutPreset(key)
                                end
                            },
                            showHeaderDivider = {
                                type = "toggle",
                                order = 2,
                                width = 1.5,
                                name = function() return l10n("Show Header Divider") end,
                                desc = function() return l10n("Shows a clean one-pixel divider under the tracker header to separate it from the quest list.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return Questie.db.profile.trackerHeaderDividerEnabled end,
                                set = function(_, value)
                                    Questie.db.profile.trackerHeaderDividerEnabled = value
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                            showZoneDividers = {
                                type = "toggle",
                                order = 3,
                                width = 1.5,
                                name = function() return l10n("Show Zone Dividers") end,
                                desc = function() return l10n("Adds a thin divider before each additional zone block so multi-zone trackers are easier to scan.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return Questie.db.profile.trackerZoneDividersEnabled end,
                                set = function(_, value)
                                    Questie.db.profile.trackerZoneDividersEnabled = value
                                    QuestieTracker:Update()
                                end
                            },
                            Spacer_Layout = QuestieOptionsUtils:Spacer(4),
                            questPadding = {
                                type = "range",
                                order = 5,
                                name = function() return l10n('Padding Between Quests') end,
                                desc = function() return l10n('The exact gap inserted after one quest block finishes and before the next tracked block begins. This controls separation between quests as blocks and does not affect the gap below a quest title before its objectives.\n\nNOTE: Changing this setting while in Sizer Manual Mode will reset the Sizer back to Auto Mode') end,
                                width = 3,
                                min = 0,
                                max = 15,
                                step = 1,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return Questie.db.profile.trackerQuestPadding end,
                                set = function(_, value)
                                    Questie.db.profile.trackerQuestPadding = value
                                    _RefreshTrackerLayout(true, true)
                                end
                            },
                            questTitlePadding = {
                                type = "range",
                                order = 6,
                                name = function() return l10n("Gap Below Quest Title") end,
                                desc = function() return l10n("Controls the uniform gap inside a quest block between the quest title and the first objective or completion line. This does not affect spacing between separate quest blocks.") end,
                                width = 3,
                                min = 0,
                                max = 12,
                                step = 1,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return tonumber(Questie.db.profile.trackerQuestTitlePadding) or 1 end,
                                set = function(_, value)
                                    Questie.db.profile.trackerQuestTitlePadding = value
                                    _RefreshTrackerLayout(true, true)
                                end
                            },
                            questTitleInset = {
                                type = "range",
                                order = 7,
                                name = function() return l10n("Quest Title Inset") end,
                                desc = function() return l10n("Adds left inset to quest titles without shifting the zone headers.") end,
                                width = 3,
                                min = 0,
                                max = 24,
                                step = 1,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return tonumber(Questie.db.profile.trackerQuestTitleInset) or 0 end,
                                set = function(_, value)
                                    Questie.db.profile.trackerQuestTitleInset = value
                                    _RefreshTrackerLayout(true, true)
                                end
                            },
                            objectiveInset = {
                                type = "range",
                                order = 8,
                                name = function() return l10n("Objective Inset") end,
                                desc = function() return l10n("Adds left inset to objective lines after the quest title indent and objective prefix.") end,
                                width = 3,
                                min = 0,
                                max = 32,
                                step = 1,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return tonumber(Questie.db.profile.trackerObjectiveInset) or 0 end,
                                set = function(_, value)
                                    Questie.db.profile.trackerObjectiveInset = value
                                    _RefreshTrackerLayout(true, true)
                                end
                            },
                            questItemGutter = {
                                type = "range",
                                order = 9,
                                name = function() return l10n("Quest Item Gutter") end,
                                desc = function() return l10n("Controls how much gap exists between the tracker text column and quest item buttons when they are placed inside or outside the tracker.") end,
                                width = 3,
                                min = 0,
                                max = 24,
                                step = 1,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return tonumber(Questie.db.profile.trackerQuestItemGutter) or 4 end,
                                set = function(_, value)
                                    Questie.db.profile.trackerQuestItemGutter = value
                                    _RefreshTrackerLayout(true, true)
                                end
                            },
                            zoneSpacing = {
                                type = "range",
                                order = 10,
                                name = function() return l10n("Gap Before Next Zone") end,
                                desc = function() return l10n("Controls the extra space inserted before each additional zone header. Negative values pull the next zone upward. This only affects transitions between zones, not the first zone in the tracker.") end,
                                width = 3,
                                min = -24,
                                max = 24,
                                step = 1,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return tonumber(Questie.db.profile.trackerZoneSpacing) or 0 end,
                                set = function(_, value)
                                    Questie.db.profile.trackerZoneSpacing = value
                                    _RefreshTrackerLayout(true, true)
                                end
                            },
                            topSpacing = {
                                type = "range",
                                order = 11,
                                name = function() return l10n("Top Content Padding") end,
                                desc = function() return l10n("Controls the empty space above the tracked content. With the header at the top this pads below the header; with the header at the bottom or disabled it pads from the top edge of the tracker.") end,
                                width = 3,
                                min = 0,
                                max = 24,
                                step = 1,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return tonumber(Questie.db.profile.trackerTopSpacing) or 0 end,
                                set = function(_, value)
                                    Questie.db.profile.trackerTopSpacing = value
                                    _RefreshTrackerLayout(true, true)
                                end
                            },
                            bottomSpacing = {
                                type = "range",
                                order = 12,
                                name = function() return l10n("Bottom Content Padding") end,
                                desc = function() return l10n("Controls the empty space below the tracked content. With the header at the bottom this becomes the gap between the final tracked row and the header block.") end,
                                width = 3,
                                min = 0,
                                max = 24,
                                step = 1,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return tonumber(Questie.db.profile.trackerBottomSpacing) or 0 end,
                                set = function(_, value)
                                    Questie.db.profile.trackerBottomSpacing = value
                                    _RefreshTrackerLayout(true, true)
                                end
                            },
                        },
                    },
                    group_header = {
                        type = "group",
                        order = 16,
                        inline = true,
                        width = 0.5,
                        name = function() return l10n('Tracker Header') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        args = {
                            enableHeader = {
                                type = "toggle",
                                order = 1,
                                width = 1.5,
                                name = function() return l10n("Enable Tracker Header") end,
                                desc = function() return l10n("When this is enabled the Tracker Header with the number of active quests and the Questie Icon will be permanently visible.\n\nWhen this is disabled the Questie Icon will fade in while your mouse is over the Tracker.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return Questie.db.profile.trackerHeaderEnabled end,
                                set = function(_, value)
                                    Questie.db.profile.trackerHeaderEnabled = value
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                            moveHeaderToBottom = {
                                type = "toggle",
                                order = 2,
                                width = 1.5,
                                name = function() return l10n("Show Tracker Header At The Bottom") end,
                                desc = function() return l10n("When this is enabled the Tracker Header and/or the Questie Icon will be moved to the bottom of the Questie Tracker.") end,
                                disabled = function() return (not Questie.db.profile.trackerEnabled) end,
                                get = function() return Questie.db.profile.moveHeaderToBottom end,
                                set = function(_, value)
                                    Questie.db.profile.moveHeaderToBottom = value
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                            alwaysShowTracker = {
                                type = "toggle",
                                order = 3,
                                width = 1.5,
                                name = function() return l10n("Show Header For Empty Tracker") end,
                                desc = function() return l10n("When this is enabled the Tracker Header will be visible even when no quests are being tracked versus the Tracker being hidden completely.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return Questie.db.profile.alwaysShowTracker end,
                                set = function(_, value)
                                    Questie.db.profile.alwaysShowTracker = value
                                    if (Questie.db.profile.alwaysShowTracker == true) and (Questie.db.char.isTrackerExpanded == false) then
                                        Questie.db.char.isTrackerExpanded = true
                                    end
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                        },
                    },
                    group_background = {
                        type = "group",
                        order = 17,
                        inline = true,
                        width = 0.5,
                        name = function() return l10n('Tracker Background') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        args = {
                            enableBackground = {
                                type = "toggle",
                                order = 1,
                                width = 1.5,
                                name = function() return l10n('Enable Background') end,
                                desc = function() return l10n('When this is checked, the Questie Tracker Background becomes visible.') end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function() return Questie.db.profile.trackerBackdropEnabled end,
                                set = function(_, value)
                                    Questie.db.profile.trackerBackdropEnabled = value
                                    Questie.db.profile.currentBackdropEnabled = value
                                    _ApplyTrackerBackdropPreview()
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                            enableBorder = {
                                type = "toggle",
                                order = 2,
                                width = 1.5,
                                name = function() return l10n('Enable Border') end,
                                desc = function() return l10n('When this is checked, the Questie Tracker Border becomes visible.') end,
                                disabled = function() return not Questie.db.profile.trackerEnabled or not Questie.db.profile.trackerBackdropEnabled end,
                                get = function() return Questie.db.profile.trackerBorderEnabled end,
                                set = function(_, value)
                                    Questie.db.profile.trackerBorderEnabled = value
                                    Questie.db.profile.currentBorderEnabled = value
                                    _ApplyTrackerBackdropPreview()
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                            fadeTrackerBackdrop = {
                                type = "toggle",
                                order = 3,
                                width = 1.5,
                                name = function() return l10n('Fade Background') end,
                                desc = function() return l10n('When this is checked, the Questie Tracker Backdrop and Border (if enabled) will fade and become transparent when not in use.') end,
                                disabled = function() return not Questie.db.profile.trackerEnabled or not Questie.db.profile.trackerBackdropEnabled end,
                                get = function() return Questie.db.profile.trackerBackdropFader end,
                                set = function(_, value)
                                    Questie.db.profile.trackerBackdropFader = value
                                    Questie.db.profile.currentBackdropFader = value

                                    if value == true then
                                        local fadeTicker
                                        local fadeTickerValue = 1
                                        fadeTicker = C_Timer.NewTicker(0.02, function()
                                            if fadeTickerValue <= 1 then
                                                fadeTickerValue = fadeTickerValue - 0.05

                                                if fadeTickerValue < 0 then
                                                    fadeTickerValue = 0
                                                    fadeTicker:Cancel()
                                                end

                                                if Questie.db.char.isTrackerExpanded then
                                                    local bgR, bgG, bgB = _GetColorValue("trackerBackdropColor", 0, 0, 0)
                                                    TrackerBaseFrame.baseFrame:SetBackdropColor(bgR, bgG, bgB, math.min(Questie.db.profile.trackerBackdropAlpha, fadeTickerValue))

                                                    if Questie.db.profile.trackerBorderEnabled then
                                                        local borderR, borderG, borderB = _GetColorValue("trackerBorderColor", 1, 1, 1)
                                                        local borderAlpha = Questie.db.profile.trackerBorderAlpha or Questie.db.profile.trackerBackdropAlpha
                                                        TrackerBaseFrame.baseFrame:SetBackdropBorderColor(borderR, borderG, borderB, math.min(borderAlpha, fadeTickerValue))
                                                    end
                                                end
                                            else
                                                fadeTickerValue:Cancel()
                                            end
                                        end)
                                    end
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                            questBorderAlpha = {
                                type = "range",
                                order = 4,
                                name = function() return l10n('Tracker Border Alpha') end,
                                desc = function() return l10n('The alpha level of the Questie Tracker border. A setting of 100 percent is fully visible.') end,
                                width = 3,
                                min = 0,
                                max = 100,
                                step = 5,
                                disabled = function() return not Questie.db.profile.trackerBackdropEnabled or not Questie.db.profile.trackerBorderEnabled or not Questie.db.profile.trackerEnabled end,
                                get = function() return (Questie.db.profile.trackerBorderAlpha or Questie.db.profile.trackerBackdropAlpha) * 100 end,
                                set = function(_, value)
                                    Questie.db.profile.trackerBorderAlpha = value / 100
                                    _ApplyTrackerBackdropPreview()
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                            questBackdropAlpha = {
                                type = "range",
                                order = 5,
                                name = function() return l10n('Tracker Backdrop Alpha') end,
                                desc = function() return l10n('The alpha level of the Questie Trackers backdrop. A setting of 100 percent is fully visible.') end,
                                width = 3,
                                min = 0,
                                max = 100,
                                step = 5,
                                disabled = function() return not Questie.db.profile.trackerBackdropEnabled or not Questie.db.profile.trackerEnabled end,
                                get = function() return Questie.db.profile.trackerBackdropAlpha * 100 end,
                                set = function(_, value)
                                    Questie.db.profile.trackerBackdropAlpha = value / 100
                                    _ApplyTrackerBackdropPreview()
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                        },
                    },
                    group_colors = {
                        type = "group",
                        order = 18,
                        inline = true,
                        width = 0.5,
                        name = function() return l10n("Tracker Colors") end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        args = {
                            trackerBackdropColor = {
                                type = "color",
                                order = 1,
                                name = function() return l10n("Background Color") end,
                                desc = function() return l10n("Sets the Questie tracker background color. Alpha is still controlled by the tracker backdrop alpha slider.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function()
                                    return _GetColorValue("trackerBackdropColor", 0, 0, 0)
                                end,
                                set = function(_, r, g, b)
                                    _SetColorValue("trackerBackdropColor", r, g, b)
                                    _ApplyTrackerBackdropPreview()
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                            trackerBorderColor = {
                                type = "color",
                                order = 2,
                                name = function() return l10n("Border Color") end,
                                desc = function() return l10n("Sets the tracker border color.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function()
                                    return _GetColorValue("trackerBorderColor", 1, 1, 1)
                                end,
                                set = function(_, r, g, b)
                                    _SetColorValue("trackerBorderColor", r, g, b)
                                    _ApplyTrackerBackdropPreview()
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                            trackerHeaderBackgroundColor = {
                                type = "color",
                                order = 3,
                                hasAlpha = true,
                                name = function() return l10n("Header Background") end,
                                desc = function() return l10n("Sets the background color and alpha for the tracker header strip.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function()
                                    return _GetColorValue("trackerHeaderBackgroundColor", 0, 0, 0, 0.5)
                                end,
                                set = function(_, r, g, b, a)
                                    _SetColorValue("trackerHeaderBackgroundColor", r, g, b, a)
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                            trackerHeaderTextColor = {
                                type = "color",
                                order = 4,
                                name = function() return l10n("Header Text") end,
                                desc = function() return l10n("Sets the Questie tracker title text color.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function()
                                    return _GetColorValue("trackerHeaderTextColor", 1, 0.82, 0)
                                end,
                                set = function(_, r, g, b)
                                    _SetColorValue("trackerHeaderTextColor", r, g, b)
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                            trackerHeaderAccentColor = {
                                type = "color",
                                order = 5,
                                hasAlpha = true,
                                name = function() return l10n("Header Accent Bar") end,
                                desc = function() return l10n("Sets the color of the accent line below the tracker header.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function()
                                    return _GetColorValue("trackerHeaderAccentColor", 0.16, 0.78, 0.72, 0.38)
                                end,
                                set = function(_, r, g, b, a)
                                    _SetColorValue("trackerHeaderAccentColor", r, g, b, a)
                                    QuestieTracker:UpdateFormatting()
                                end
                            },
                            trackerZoneHeaderColor = {
                                type = "color",
                                order = 6,
                                name = function() return l10n("Zone Header Text") end,
                                desc = function() return l10n("Sets the color used for zone headers inside the tracker.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function()
                                    return _GetColorValue("trackerZoneHeaderColor", 1, 0, 1)
                                end,
                                set = function(_, r, g, b)
                                    _SetColorValue("trackerZoneHeaderColor", r, g, b)
                                    QuestieTracker:Update()
                                end
                            },
                            trackerZoneDividerColor = {
                                type = "color",
                                order = 7,
                                hasAlpha = true,
                                name = function() return l10n("Zone Divider") end,
                                desc = function() return l10n("Sets the color of the optional divider shown before additional zone blocks.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function()
                                    return _GetColorValue("trackerZoneDividerColor", 0.16, 0.78, 0.72, 0.28)
                                end,
                                set = function(_, r, g, b, a)
                                    _SetColorValue("trackerZoneDividerColor", r, g, b, a)
                                    QuestieTracker:Update()
                                end
                            },
                            trackerAlternatingRowsEnabled = {
                                type = "toggle",
                                order = 8,
                                width = 3,
                                name = function() return l10n("Alternating Row Backgrounds") end,
                                desc = function() return l10n("Shows alternating background colors behind visible tracker rows. Wrapped text remains inside a single row, and colorways never change this option automatically.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled end,
                                get = function()
                                    return Questie.db.profile.trackerAlternatingRowsEnabled
                                end,
                                set = function(_, value)
                                    Questie.db.profile.trackerAlternatingRowsEnabled = value
                                    TrackerLinePool.UpdateAlternatingRowBackgrounds()
                                end,
                            },
                            trackerAlternatingRowMode = {
                                type = "select",
                                order = 9,
                                width = 1.5,
                                name = function() return l10n("Alternating Background Mode") end,
                                desc = function() return l10n("Quest Blocks gives each quest title and all of its objectives one continuous alternating background. Individual Rows alternates every visible tracker line, including zone headers.") end,
                                values = function()
                                    return {
                                        questBlocks = l10n("Quest Blocks"),
                                        rows = l10n("Individual Rows"),
                                    }
                                end,
                                disabled = function() return not Questie.db.profile.trackerEnabled or not Questie.db.profile.trackerAlternatingRowsEnabled end,
                                get = function()
                                    return Questie.db.profile.trackerAlternatingRowMode == "rows" and "rows" or "questBlocks"
                                end,
                                set = function(_, value)
                                    Questie.db.profile.trackerAlternatingRowMode = value == "rows" and "rows" or "questBlocks"
                                    TrackerLinePool.UpdateAlternatingRowBackgrounds()
                                end,
                            },
                            trackerAlternatingBlockEdgePadding = {
                                type = "range",
                                order = 10,
                                width = 1.5,
                                name = function() return l10n("Block Edge Padding") end,
                                desc = function() return l10n("Extends a quest-block background into the existing space above and below its text without changing tracker layout or quest spacing.") end,
                                min = 0,
                                max = 8,
                                step = 1,
                                disabled = function()
                                    return not Questie.db.profile.trackerEnabled
                                        or not Questie.db.profile.trackerAlternatingRowsEnabled
                                        or Questie.db.profile.trackerAlternatingRowMode == "rows"
                                end,
                                get = function()
                                    return math.max(0, math.min(8, tonumber(Questie.db.profile.trackerAlternatingBlockEdgePadding) or 2))
                                end,
                                set = function(_, value)
                                    Questie.db.profile.trackerAlternatingBlockEdgePadding = math.max(0, math.min(8, tonumber(value) or 2))
                                    TrackerLinePool.UpdateAlternatingRowBackgrounds()
                                end,
                            },
                            trackerAlternatingFullWidth = {
                                type = "toggle",
                                order = 11,
                                width = 3,
                                name = function() return l10n("Full-Width Alternating Backgrounds") end,
                                desc = function() return l10n("Extends alternating row or quest-block backgrounds to the inner edges of the tracker frame without changing text indentation or external quest-item buttons.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled or not Questie.db.profile.trackerAlternatingRowsEnabled end,
                                get = function()
                                    return Questie.db.profile.trackerAlternatingFullWidth
                                end,
                                set = function(_, value)
                                    Questie.db.profile.trackerAlternatingFullWidth = value
                                    TrackerLinePool.UpdateAlternatingRowBackgrounds()
                                end,
                            },
                            trackerAlternatingRowColorOdd = {
                                type = "color",
                                order = 12,
                                hasAlpha = true,
                                name = function() return l10n("Odd Alternating Background") end,
                                desc = function() return l10n("Sets the color and alpha for the first, third, and following alternating rows or quest blocks.") end,
                                disabled = function()
                                    return not Questie.db.profile.trackerEnabled or not Questie.db.profile.trackerAlternatingRowsEnabled
                                end,
                                get = function()
                                    return _GetColorValue("trackerAlternatingRowColorOdd", 0.018, 0.022, 0.031, 0.32)
                                end,
                                set = function(_, r, g, b, a)
                                    _SetColorValue("trackerAlternatingRowColorOdd", r, g, b, a)
                                    Questie.db.profile.trackerAlternatingRowPaletteVersion = 1
                                    TrackerLinePool.UpdateAlternatingRowBackgrounds()
                                end,
                            },
                            trackerAlternatingRowColorEven = {
                                type = "color",
                                order = 13,
                                hasAlpha = true,
                                name = function() return l10n("Even Alternating Background") end,
                                desc = function() return l10n("Sets the color and alpha for the second, fourth, and following alternating rows or quest blocks.") end,
                                disabled = function()
                                    return not Questie.db.profile.trackerEnabled or not Questie.db.profile.trackerAlternatingRowsEnabled
                                end,
                                get = function()
                                    return _GetColorValue("trackerAlternatingRowColorEven", 0.082, 0.855, 0.804, 0.08)
                                end,
                                set = function(_, r, g, b, a)
                                    _SetColorValue("trackerAlternatingRowColorEven", r, g, b, a)
                                    Questie.db.profile.trackerAlternatingRowPaletteVersion = 1
                                    TrackerLinePool.UpdateAlternatingRowBackgrounds()
                                end,
                            },
                        },
                    },
                    group_diagnostics = {
                        type = "group",
                        order = 19,
                        inline = true,
                        width = 0.5,
                        name = function() return l10n("Tracker Diagnostics") end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        args = {
                            trackerDiagnosticsText = {
                                type = "description",
                                order = 1,
                                width = "full",
                                fontSize = "medium",
                                name = function()
                                    return _GetTrackerDiagnosticsText()
                                end,
                            },
                            repairTrackerAnchor = {
                                type = "execute",
                                order = 2,
                                width = 1.2,
                                name = function() return l10n("Repair Tracker Anchor") end,
                                desc = function() return l10n("Normalizes the saved tracker anchor and re-applies the current growth direction without forcing a full reset to center.") end,
                                disabled = function() return not Questie.db.profile.trackerEnabled or InCombatLockdown() end,
                                func = function()
                                    TrackerBaseFrame:RepairLocation()
                                end
                            },
                        },
                    },
                }
            },
            group_fonts = {
                type = "group",
                order = 9,
                inline = true,
                width = 0.5,
                name = function() return l10n('Font Options'); end,
                disabled = function() return not Questie.db.profile.trackerEnabled end,
                args = {
                    fontGlobal = {
                        type = "select",
                        dialogControl = 'LSM30_Font',
                        order = 1,
                        values = function() return TrackerFonts:GetOverrideValues() end,
                        style = 'dropdown',
                        width = 1.5,
                        name = function() return l10n("Global Tracker Font Override") end,
                        desc = function() return l10n("Overrides all tracker font selections when set. Set this to NONE to use the individual tracker font settings below.") end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerFontGlobalOverride or TrackerFonts:GetNoneValue() end,
                        set = function(_, value)
                            Questie.db.profile.trackerFontGlobalOverride = value
                            QuestieTracker:Update()
                        end
                    },
                    fontGlobalScale = {
                        type = "range",
                        order = 1.1,
                        width = 1.5,
                        name = function() return l10n("Global Font Scale") end,
                        desc = function() return l10n("Multiplies every tracker font size without changing the individual Header, Zone, Quest, or Objective size settings. 1.00 keeps their configured sizes unchanged.") end,
                        min = 0.5,
                        max = 3,
                        step = 0.05,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerFontGlobalScale or 1 end,
                        set = function(_, value)
                            Questie.db.profile.trackerFontGlobalScale = value
                            QuestieTracker:Update()
                        end
                    },
                    fontSizeHeader = {
                        type = "range",
                        order = 2,
                        name = function() return l10n("Font Size for Active Quests Header") end,
                        desc = function() return l10n("The font size used for the Active Quests Header.") end,
                        width = "double",
                        min = 8,
                        max = 26,
                        step = 1,
                        disabled = function() return not Questie.db.profile.trackerEnabled or not Questie.db.profile.trackerHeaderEnabled end,
                        get = function() return Questie.db.profile.trackerFontSizeHeader end,
                        set = function(_, value)
                            Questie.db.profile.trackerFontSizeHeader = value
                            QuestieTracker:Update()
                        end
                    },
                    fontHeader = {
                        type = "select",
                        dialogControl = 'LSM30_Font',
                        order = 3,
                        values = function() return TrackerFonts:GetValues() end,
                        style = 'dropdown',
                        name = function() return l10n("Font for Active Quests Header") end,
                        desc = function() return l10n("The font used for the Active Quests Header.") end,
                        disabled = function() return not Questie.db.profile.trackerEnabled or not Questie.db.profile.trackerHeaderEnabled or TrackerFonts:IsGlobalOverrideActive() end,
                        get = function() return Questie.db.profile.trackerFontHeader or "SourceCodePro (Bold)" end,
                        set = function(_, value)
                            Questie.db.profile.trackerFontHeader = value
                            QuestieTracker:Update()
                        end
                    },
                    fontSizeZone = {
                        type = "range",
                        order = 4,
                        name = function() return l10n('Font Size for Zone Names') end,
                        desc = function() return l10n('The font size used for zone names.') end,
                        width = "double",
                        min = 8,
                        max = 26,
                        step = 1,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerFontSizeZone end,
                        set = function(_, value)
                            Questie.db.profile.trackerFontSizeZone = value
                            QuestieTracker:Update()
                        end
                    },
                    fontZone = {
                        type = "select",
                        dialogControl = 'LSM30_Font',
                        order = 5,
                        values = function() return TrackerFonts:GetValues() end,
                        style = 'dropdown',
                        name = function() return l10n('Font for Zone Names') end,
                        desc = function() return l10n('The font used for zone names.') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled or TrackerFonts:IsGlobalOverrideActive() end,
                        get = function() return Questie.db.profile.trackerFontZone or "SourceCodePro (Bold)" end,
                        set = function(_, value)
                            Questie.db.profile.trackerFontZone = value
                            QuestieTracker:Update()
                        end
                    },
                    fontSizeQuest = {
                        type = "range",
                        order = 6,
                        name = function() return l10n('Font Size for Quest Titles') end,
                        desc = function() return l10n("The font size used for Quest Titles.\n\nNOTE: Objective font size will auto adjust to less than or equal to Quest font size. This is necessary to avoid any text collisions and formatting abnormalities.") end,
                        width = "double",
                        min = 8,
                        max = 26,
                        step = 1,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerFontSizeQuest end,
                        set = function(_, value)
                            Questie.db.profile.trackerFontSizeQuest = value
                            if Questie.db.profile.trackerFontSizeObjective > value then
                                Questie.db.profile.trackerFontSizeObjective = value
                            end
                            QuestieTracker:Update()
                        end
                    },
                    fontQuest = {
                        type = "select",
                        dialogControl = 'LSM30_Font',
                        order = 7,
                        values = function() return TrackerFonts:GetValues() end,
                        style = 'dropdown',
                        name = function() return l10n('Font for Quest Titles') end,
                        desc = function() return l10n('The font used for Quest Titles.') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled or TrackerFonts:IsGlobalOverrideActive() end,
                        get = function() return Questie.db.profile.trackerFontQuest or "SourceCodePro (Bold)" end,
                        set = function(_, value)
                            Questie.db.profile.trackerFontQuest = value
                            QuestieTracker:Update()
                        end
                    },
                    fontSizeObjective = {
                        type = "range",
                        order = 8,
                        name = function() return l10n('Font Size for Objectives') end,
                        desc = function() return l10n("The font size used for Objectives.\n\nNOTE: Objective font size will auto adjust to less than or equal to Quest font size. This is necessary to avoid any text collisions and formatting abnormalities.") end,
                        width = "double",
                        min = 8,
                        max = 26,
                        step = 1,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerFontSizeObjective end,
                        set = function(_, value)
                            if Questie.db.profile.trackerFontSizeQuest < value then
                                Questie.db.profile.trackerFontSizeObjective = Questie.db.profile.trackerFontSizeQuest
                            else
                                Questie.db.profile.trackerFontSizeObjective = value
                            end
                            QuestieTracker:Update()
                        end
                    },
                    fontObjective = {
                        type = "select",
                        dialogControl = 'LSM30_Font',
                        order = 9,
                        values = function() return TrackerFonts:GetValues() end,
                        style = 'dropdown',
                        name = function() return l10n('Font for Objectives') end,
                        desc = function() return l10n('The font used for Objectives.') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled or TrackerFonts:IsGlobalOverrideActive() end,
                        get = function() return Questie.db.profile.trackerFontObjective or "SourceCodePro (Bold)" end,
                        set = function(_, value)
                            Questie.db.profile.trackerFontObjective = value
                            QuestieTracker:Update()
                        end
                    },
                    fontOutline = {
                        type = "select",
                        order = 10,
                        width = 1.5,
                        values = {
                            [""] = "None",
                            ["OUTLINE"] = "Outline",
                            ["MONOCHROME"] = "Monochrome"
                        },
                        style = 'dropdown',
                        name = function() return l10n('Outline for Zones, Titles, and Objectives') end,
                        desc = function() return l10n('The outline used for Quest Zones, Titles, and Objectives in the Questie Tracker.') end,
                        disabled = function() return not Questie.db.profile.trackerEnabled end,
                        get = function() return Questie.db.profile.trackerFontOutline or "OUTLINE" end,
                        set = function(_, value)
                            Questie.db.profile.trackerFontOutline = value
                            QuestieTracker:Update()
                        end
                    },
                }
            },
        }
    }

    return trackerOptions
end

_GetShortcuts = function()
    return {
        ['left'] = l10n('Left Click'),
        ['right'] = l10n('Right Click'),
        ['shiftleft'] = l10n('Shift') .. " + " .. l10n('Left Click'),
        ['shiftright'] = l10n('Shift') .. " + " .. l10n('Right Click'),
        ['ctrlleft'] = l10n('Control') .. " + " .. l10n('Left Click'),
        ['ctrlright'] = l10n('Control') .. " + " .. l10n('Right Click'),
        ['altleft'] = l10n('Alt') .. " + " .. l10n('Left Click'),
        ['altright'] = l10n('Alt') .. " + " .. l10n('Right Click'),
        ['disabled'] = l10n('Disabled'),
    }
end
