---@class TrackerBaseFrame
local TrackerBaseFrame = QuestieLoader:CreateModule("TrackerBaseFrame")
-------------------------
--Import QuestieTracker modules.
-------------------------
---@type QuestieTracker
local QuestieTracker = QuestieLoader:ImportModule("QuestieTracker")
---@type TrackerFadeTicker
local TrackerFadeTicker = QuestieLoader:ImportModule("TrackerFadeTicker")
-------------------------
--Import Questie modules.
-------------------------
---@type QuestieCombatQueue
local QuestieCombatQueue = QuestieLoader:ImportModule("QuestieCombatQueue")
---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

--- COMPATIBILITY ---
local C_Timer = QuestieCompat.C_Timer
local BackdropTemplateMixin = not QuestieCompat.Is335 and BackdropTemplateMixin

local WatchFrame = QuestWatchFrame or WatchFrame
local baseFrame, sizer, sizerVisual, sizerSetPoint, sizerSetPointY, sizerLine1, sizerLine2, sizerLine3
local updateTimer
local VALID_ANCHOR_POINTS = {
    TOP = true,
    BOTTOM = true,
    LEFT = true,
    RIGHT = true,
    TOPLEFT = true,
    TOPRIGHT = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
    CENTER = true,
}
local VALID_TRACKER_SETPOINTS = {
    TOPLEFT = true,
    TOPRIGHT = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
}

-- Pixels the tracker may extend past the screen edge while dragging.
-- WoW clamp + backdrop bounds often stop ~1px short of a flush edge; 2px covers rounding.
local TRACKER_SCREEN_EDGE_OVERSHOOT = 2
local TRACKER_COORD_EPSILON = 0.5
local SIZER_IDLE_ALPHA = 0.20
local SIZER_ACTIVE_ALPHA = 0.82
local SIZER_FRAME_SIZE = 18
local SIZER_VISUAL_SIZE = 11
local SIZER_VISUAL_INSET = 2
local SIZER_LINE_ALPHA = 0.72
local SIZER_LINE_COLOR_R = 0.74
local SIZER_LINE_COLOR_G = 0.79
local SIZER_LINE_COLOR_B = 0.87
local TRACKER_SCALE_DRAG_PIXELS_PER_STEP = 240

TrackerBaseFrame.IsInitialized = false
TrackerBaseFrame.isSizing = false
TrackerBaseFrame.isMoving = false
TrackerBaseFrame.isScaleSizing = false

local _OnEnter, _SetSizerTooltip, _UpdateTrackerPosition, _ClampTrackerCoordsToScreen
local scaleDragStartX, scaleDragStartY, scaleDragStartValue
local resizePreviewWidth, resizePreviewHeight

local function _GetTrackerSetPoint()
    local trackerSetPoint = Questie and Questie.db and Questie.db.profile and Questie.db.profile.trackerSetpoint
    if not VALID_TRACKER_SETPOINTS[trackerSetPoint] then
        return "TOPLEFT"
    end

    return trackerSetPoint
end

local function _GetSizerBaseAlpha()
    if Questie.db.profile.sizerHidden then
        return 0
    end

    return SIZER_IDLE_ALPHA
end

local function _GetTrackerScale()
    local trackerScale = tonumber(Questie.db.profile.trackerScale) or 1

    if trackerScale < 1 then
        trackerScale = 1
    elseif trackerScale > 5 then
        trackerScale = 5
    end

    if Questie.db.profile.trackerScale ~= trackerScale then
        Questie.db.profile.trackerScale = trackerScale
    end

    return trackerScale
end

local function _RoundTrackerScale(trackerScale)
    trackerScale = tonumber(trackerScale) or 1

    if trackerScale < 1 then
        trackerScale = 1
    elseif trackerScale > 5 then
        trackerScale = 5
    end

    return math.floor((trackerScale * 100) + 0.5) / 100
end

local function _GetCursorPositionInUIUnits()
    local cursorX, cursorY = GetCursorPosition()
    local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1

    if uiScale == 0 then
        uiScale = 1
    end

    return cursorX / uiScale, cursorY / uiScale
end

local function _GetFrameBoundsInUIParentUnits()
    if not baseFrame then
        return nil, nil, nil, nil
    end

    local left, top, right, bottom = baseFrame:GetLeft(), baseFrame:GetTop(), baseFrame:GetRight(), baseFrame:GetBottom()
    if not (left and top and right and bottom) then
        return nil, nil, nil, nil
    end

    local parentScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local frameScale = (baseFrame.GetEffectiveScale and baseFrame:GetEffectiveScale()) or parentScale
    local scaleRatio = frameScale / parentScale

    return left * scaleRatio, top * scaleRatio, right * scaleRatio, bottom * scaleRatio
end

local function _NeedsTrackerClamp(xLeft, yTop, xRight, yBottom)
    local clampedLeft, clampedTop, clampedRight, clampedBottom = _ClampTrackerCoordsToScreen(xLeft, yTop, xRight, yBottom)

    local needsClamp = math.abs(clampedLeft - xLeft) > TRACKER_COORD_EPSILON
        or math.abs(clampedTop - yTop) > TRACKER_COORD_EPSILON
        or math.abs(clampedRight - xRight) > TRACKER_COORD_EPSILON
        or math.abs(clampedBottom - yBottom) > TRACKER_COORD_EPSILON

    return needsClamp, clampedLeft, clampedTop, clampedRight, clampedBottom
end

local function _EnableSizerPreview()
    if baseFrame and baseFrame.sizer then
        baseFrame.sizer:SetAlpha(SIZER_ACTIVE_ALPHA)
    end

    -- Force the tracker boundaries visible while the user is adjusting it.
    Questie.db.profile.trackerBackdropEnabled = true
    Questie.db.profile.trackerBorderEnabled = true
    Questie.db.profile.trackerBackdropFader = false
end

local function _RestoreSizerPreview()
    Questie.db.profile.trackerBackdropEnabled = Questie.db.profile.currentBackdropEnabled
    Questie.db.profile.trackerBorderEnabled = Questie.db.profile.currentBorderEnabled
    Questie.db.profile.trackerBackdropFader = Questie.db.profile.currentBackdropFader
end

local function _GetBackdropRGB()
    local color = Questie.db.profile.trackerBackdropColor or { 0, 0, 0 }
    return tonumber(color[1]) or 0, tonumber(color[2]) or 0, tonumber(color[3]) or 0
end

local function _GetBorderRGB()
    local color = Questie.db.profile.trackerBorderColor or { 1, 1, 1 }
    return tonumber(color[1]) or 1, tonumber(color[2]) or 1, tonumber(color[3]) or 1
end

local function _UpdateTrackerScaleFromDrag()
    if not (scaleDragStartX and scaleDragStartY and scaleDragStartValue) then
        return
    end

    local currentX, currentY = _GetCursorPositionInUIUnits()
    local deltaX = currentX - scaleDragStartX
    local deltaY = currentY - scaleDragStartY
    local combinedDelta
    local trackerSetPoint = Questie.db.profile.trackerSetpoint

    if trackerSetPoint == "BOTTOMLEFT" or trackerSetPoint == "BOTTOMRIGHT" then
        combinedDelta = (deltaX + deltaY) / 2
    else
        combinedDelta = (deltaX - deltaY) / 2
    end

    local newScale = _RoundTrackerScale(scaleDragStartValue + (combinedDelta / TRACKER_SCALE_DRAG_PIXELS_PER_STEP))
    if Questie.db.profile.trackerScale ~= newScale then
        Questie.db.profile.trackerScale = newScale
        QuestieTracker:Update()

        if GameTooltip:IsShown() and GameTooltip._SizerToolTip == _SetSizerTooltip then
            _SetSizerTooltip()
        end
    end
end

local function _GetPreviewTrackerDimensions()
    if not baseFrame then
        return nil, nil
    end

    local maxTrackerHeight = GetScreenHeight() * (tonumber(Questie.db.profile.trackerHeightRatio) or 1)
    local trackerWidth = math.max(1, tonumber(baseFrame:GetWidth()) or 1)
    local trackerHeight = math.max(1, math.min(tonumber(baseFrame:GetHeight()) or 1, maxTrackerHeight))

    return trackerWidth, trackerHeight
end

local function _UpdateTrackerResizePreview()
    if not TrackerBaseFrame.isSizing or TrackerBaseFrame.isScaleSizing then
        return
    end

    local trackerWidth, trackerHeight = _GetPreviewTrackerDimensions()
    if not (trackerWidth and trackerHeight) then
        return
    end

    local widthChanged = (not resizePreviewWidth) or math.abs(resizePreviewWidth - trackerWidth) > TRACKER_COORD_EPSILON
    local heightChanged = (not resizePreviewHeight) or math.abs(resizePreviewHeight - trackerHeight) > TRACKER_COORD_EPSILON

    if not widthChanged and not heightChanged then
        return
    end

    if heightChanged and math.abs((tonumber(baseFrame:GetHeight()) or trackerHeight) - trackerHeight) > TRACKER_COORD_EPSILON then
        baseFrame:SetHeight(trackerHeight)
    end

    Questie.db.profile.TrackerWidth = trackerWidth
    Questie.db.profile.TrackerHeight = trackerHeight
    resizePreviewWidth = trackerWidth
    resizePreviewHeight = trackerHeight

    if widthChanged then
        QuestieTracker:UpdateWidth(trackerWidth)
    end

    QuestieTracker:UpdateHeight()
end

local function _StyleSizerLine(texture, width)
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    texture:SetWidth(width)
    texture:SetHeight(1)
    texture:SetVertexColor(SIZER_LINE_COLOR_R, SIZER_LINE_COLOR_G, SIZER_LINE_COLOR_B, SIZER_LINE_ALPHA)
    if texture.SetBlendMode then
        texture:SetBlendMode("BLEND")
    end
end

local function _PositionSizerLines(anchorTop)
    local anchor = sizerVisual or sizer
    if not (anchor and sizerLine1 and sizerLine2 and sizerLine3) then
        return
    end

    local point = anchorTop and "TOPRIGHT" or "BOTTOMRIGHT"
    local baseX = -2
    local baseY = anchorTop and -2 or 2
    local stepY = anchorTop and -3 or 3

    sizerLine1:ClearAllPoints()
    sizerLine1:SetPoint(point, anchor, point, baseX, baseY)

    sizerLine2:ClearAllPoints()
    sizerLine2:SetPoint(point, anchor, point, baseX, baseY + stepY)

    sizerLine3:ClearAllPoints()
    sizerLine3:SetPoint(point, anchor, point, baseX, baseY + (stepY * 2))
end

local function _ApplyTrackerScreenClamp()
    if not baseFrame then
        return
    end

    baseFrame:SetClampedToScreen(true)
    if baseFrame.SetClampRectInsets then
        local overshoot = TRACKER_SCREEN_EDGE_OVERSHOOT
        -- left/bottom positive and right/top negative allow movement past screen edges
        baseFrame:SetClampRectInsets(overshoot, -overshoot, 0, 0)
    end
end

_ClampTrackerCoordsToScreen = function(xLeft, yTop, xRight, yBottom)
    if not xLeft or not yTop or not xRight or not yBottom then
        return xLeft, yTop, xRight, yBottom
    end

    local screenW, screenH = GetScreenWidth(), GetScreenHeight()
    local frameW = xRight - xLeft
    local frameH = yTop - yBottom
    local overshoot = TRACKER_SCREEN_EDGE_OVERSHOOT

    if xLeft < -overshoot then
        xLeft = -overshoot
        xRight = xLeft + frameW
    elseif xRight > (screenW + overshoot) then
        xRight = screenW + overshoot
        xLeft = xRight - frameW
    end

    if yBottom < 0 then
        yBottom = 0
        yTop = yBottom + frameH
    elseif yTop > screenH then
        yTop = screenH
        yBottom = yTop - frameH
    end

    return xLeft, yTop, xRight, yBottom
end

local function _NormalizeTrackerLocation(location)
    if type(location) ~= "table" then
        return nil
    end

    local point = location[1]
    local relativeTo = location[2]
    local relativePoint = location[3]
    local xOffset = tonumber(location[4]) or 0
    local yOffset = tonumber(location[5]) or 0
    local fallbackPoint = _GetTrackerSetPoint()

    -- Older private-server profiles sometimes serialized malformed tracker anchors.
    -- Recover the saved offsets by falling back to the configured growth corner.
    if not VALID_ANCHOR_POINTS[point] then
        if VALID_ANCHOR_POINTS[relativePoint] then
            point = relativePoint
        else
            point = fallbackPoint
        end
    end

    if not VALID_ANCHOR_POINTS[relativePoint] then
        relativePoint = point
    end

    if type(relativeTo) ~= "string" or relativeTo == "" then
        relativeTo = "UIParent"
    end

    return { point, relativeTo, relativePoint, xOffset, yOffset }
end

local function _GetWatchFrameLocation()
    if not WatchFrame then
        return nil
    end

    local point, _, relativePoint, xOffset, yOffset = WatchFrame:GetPoint()
    if not VALID_ANCHOR_POINTS[point] then
        return nil
    end

    if not VALID_ANCHOR_POINTS[relativePoint] then
        relativePoint = point
    end

    return { point, "UIParent", relativePoint, xOffset or 0, yOffset or 0 }
end

function TrackerBaseFrame.Initialize()
    if Questie.db.profile.trackerSizerVisibilityMigrated ~= true then
        Questie.db.profile.sizerHidden = false
        Questie.db.profile.trackerSizerVisibilityMigrated = true
    end

    Questie.db.profile.trackerSetpoint = _GetTrackerSetPoint()

    baseFrame = CreateFrame("Frame", "Questie_BaseFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    _ApplyTrackerScreenClamp()
    baseFrame:SetFrameStrata("MEDIUM")
    baseFrame:SetFrameLevel(0)
    baseFrame:SetSize(25, 25)

    baseFrame:EnableMouse(true)
    baseFrame:SetMovable(true)
    baseFrame:SetResizable(true)

    baseFrame:SetScript("OnMouseDown", TrackerBaseFrame.OnDragStart)
    baseFrame:SetScript("OnMouseUp", TrackerBaseFrame.OnDragStop)
    baseFrame:SetScript("OnEnter", TrackerFadeTicker.Unfade)

    baseFrame:SetScript("OnLeave", TrackerFadeTicker.Fade)

    baseFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 16,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    local backdropR, backdropG, backdropB = _GetBackdropRGB()
    local borderR, borderG, borderB = _GetBorderRGB()
    baseFrame:SetBackdropColor(backdropR, backdropG, backdropB, 0)
    baseFrame:SetBackdropBorderColor(borderR, borderG, borderB, 0)

    local QuestieTrackerLoc = Questie.db.profile.TrackerLocation
    sizerSetPoint = "BOTTOMRIGHT"
    sizerSetPointY = 4

    sizer = CreateFrame("Frame", "Questie_Sizer", baseFrame)
    sizer:SetPoint(sizerSetPoint, baseFrame, sizerSetPoint, 0, 0)
    sizer:SetWidth(SIZER_FRAME_SIZE)
    sizer:SetHeight(SIZER_FRAME_SIZE)
    sizer:SetFrameLevel((baseFrame:GetFrameLevel() or 0) + 10)
    sizer:SetAlpha(_GetSizerBaseAlpha())
    sizer:EnableMouse(true)
    sizer:SetScript("OnMouseDown", TrackerBaseFrame.OnResizeStart)
    sizer:SetScript("OnMouseUp", TrackerBaseFrame.OnResizeStop)

    sizer:SetScript("OnEnter", _OnEnter)

    sizer:SetScript("OnLeave", function(self)
        if GameTooltip:IsShown() then
            GameTooltip:Hide()
            GameTooltip._SizerToolTip = nil
        end

        TrackerFadeTicker.Fade(self)
    end)

    baseFrame.sizer = sizer

    sizerVisual = CreateFrame("Frame", nil, sizer)
    sizerVisual:SetPoint("BOTTOMRIGHT", sizer, "BOTTOMRIGHT", -SIZER_VISUAL_INSET, SIZER_VISUAL_INSET)
    sizerVisual:SetSize(SIZER_VISUAL_SIZE, SIZER_VISUAL_SIZE)
    sizerVisual:EnableMouse(false)
    baseFrame.sizerVisual = sizerVisual

    sizerLine1 = sizerVisual:CreateTexture(nil, "ARTWORK")
    _StyleSizerLine(sizerLine1, 8)

    sizerLine2 = sizerVisual:CreateTexture(nil, "ARTWORK")
    _StyleSizerLine(sizerLine2, 5)

    sizerLine3 = sizerVisual:CreateTexture(nil, "ARTWORK")
    _StyleSizerLine(sizerLine3, 2)

    _PositionSizerLines(false)
    TrackerBaseFrame:ApplyScale()

    local normalizedTrackerLocation = _NormalizeTrackerLocation(Questie.db.profile.TrackerLocation)
    if normalizedTrackerLocation then
        Questie.db.profile.TrackerLocation = normalizedTrackerLocation
        -- we need to pcall this because it can error if something like MoveAnything is used to move the tracker
        local result, reason = pcall(baseFrame.SetPoint, baseFrame, unpack(normalizedTrackerLocation))

        if (not result) then
            Questie.db.profile.TrackerLocation = nil
            print(l10n("Error: Questie tracker in invalid location, resetting..."))
            Questie:Debug(Questie.DEBUG_CRITICAL, "Resetting reason:", reason)

            local watchFrameLocation = _GetWatchFrameLocation()
            if watchFrameLocation then
                local result2, _ = pcall(baseFrame.SetPoint, baseFrame, unpack(watchFrameLocation))
                Questie.db.profile.trackerSetpoint = "TOPLEFT"

                if (not result2) then
                    Questie.db.profile.TrackerLocation = nil
                    TrackerBaseFrame:SetSafePoint()
                else
                    Questie.db.profile.TrackerLocation = watchFrameLocation
                end
            else
                TrackerBaseFrame:SetSafePoint()
            end
        end
    else
        Questie.db.profile.TrackerLocation = nil
        local watchFrameLocation = _GetWatchFrameLocation()
        if watchFrameLocation then
            local result, reason = pcall(baseFrame.SetPoint, baseFrame, unpack(watchFrameLocation))
            Questie.db.profile.trackerSetpoint = "TOPLEFT"

            if not result then
                Questie.db.profile.TrackerLocation = nil
                print(l10n("Error: Questie tracker in invalid location, resetting..."))
                Questie:Debug(Questie.DEBUG_CRITICAL, "Resetting reason:", reason)
                TrackerBaseFrame:SetSafePoint()
            else
                Questie.db.profile.TrackerLocation = watchFrameLocation
            end
        else
            TrackerBaseFrame:SetSafePoint()
        end
    end

    baseFrame:Hide()
    baseFrame.isSizing = false
    baseFrame.isMoving = false
    baseFrame.isScaleSizing = false

    TrackerBaseFrame.IsInitialized = true
    TrackerBaseFrame.baseFrame = baseFrame

    return baseFrame
end

function TrackerBaseFrame:ApplyScale()
    if not baseFrame then
        return
    end

    if (baseFrame:GetScale() or 1) ~= 1 then
        baseFrame:SetScale(1)
        _ApplyTrackerScreenClamp()
    end
end

function TrackerBaseFrame:Update()
    TrackerBaseFrame:ApplyScale()

    if Questie.db.char.isTrackerExpanded and QuestieTracker:HasQuest() then
        if Questie.db.profile.trackerBackdropEnabled then
            if Questie.db.profile.trackerBorderEnabled then
                if not Questie.db.profile.trackerBackdropFader then
                    local backdropR, backdropG, backdropB = _GetBackdropRGB()
                    local borderR, borderG, borderB = _GetBorderRGB()
                    baseFrame:SetBackdropColor(backdropR, backdropG, backdropB, Questie.db.profile.trackerBackdropAlpha)
                    baseFrame:SetBackdropBorderColor(borderR, borderG, borderB, Questie.db.profile.trackerBorderAlpha or Questie.db.profile.trackerBackdropAlpha)
                else
                    local backdropR, backdropG, backdropB = _GetBackdropRGB()
                    local borderR, borderG, borderB = _GetBorderRGB()
                    baseFrame:SetBackdropColor(backdropR, backdropG, backdropB, 0)
                    baseFrame:SetBackdropBorderColor(borderR, borderG, borderB, 0)
                end
            else
                if not Questie.db.profile.trackerBackdropFader then
                    local backdropR, backdropG, backdropB = _GetBackdropRGB()
                    baseFrame:SetBackdropColor(backdropR, backdropG, backdropB, Questie.db.profile.trackerBackdropAlpha)
                else
                    local backdropR, backdropG, backdropB = _GetBackdropRGB()
                    baseFrame:SetBackdropColor(backdropR, backdropG, backdropB, 0)
                end
                local borderR, borderG, borderB = _GetBorderRGB()
                baseFrame:SetBackdropBorderColor(borderR, borderG, borderB, 0)
            end
        else
            local backdropR, backdropG, backdropB = _GetBackdropRGB()
            local borderR, borderG, borderB = _GetBorderRGB()
            baseFrame:SetBackdropColor(backdropR, backdropG, backdropB, 0)
            baseFrame:SetBackdropBorderColor(borderR, borderG, borderB, 0)
        end

        sizer:ClearAllPoints()
        sizer:SetPoint("BOTTOMRIGHT", baseFrame, "BOTTOMRIGHT", 0, 0)
        _PositionSizerLines(false)

        baseFrame.sizer:SetAlpha(_GetSizerBaseAlpha())
    else
        baseFrame.sizer:SetAlpha(0)

        local backdropR, backdropG, backdropB = _GetBackdropRGB()
        local borderR, borderG, borderB = _GetBorderRGB()
        baseFrame:SetBackdropColor(backdropR, backdropG, backdropB, 0)
        baseFrame:SetBackdropBorderColor(borderR, borderG, borderB, 0)
    end

    -- Enables Click-Through when the tracker is locked
    if IsControlKeyDown() or (not Questie.db.profile.trackerLocked) then
        QuestieCombatQueue:Queue(function()
            baseFrame:EnableMouse(true)
            baseFrame:SetMovable(true)
            baseFrame:SetResizable(true)
        end)
    else
        QuestieCombatQueue:Queue(function()
            baseFrame:EnableMouse(false)
            baseFrame:SetMovable(false)
            baseFrame:SetResizable(false)
        end)
    end

    QuestieTracker:UpdateDurabilityFrame()
    QuestieTracker:UpdateVoiceOverFrame()
end

function TrackerBaseFrame:SetSafePoint()
    if TrackerBaseFrame.isMoving ~= true and TrackerBaseFrame.isResizing ~= true then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:SetSafePoint]")
    else
        Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:SetSafePoint] - Frame is moving or resizing! --> Exiting.")
        return
    end

    local trackerScale = baseFrame:GetScale() or 1
    local xOff = (baseFrame:GetWidth() * trackerScale) / 2
    local yOff = (baseFrame:GetHeight() * trackerScale) / 2
    local trackerSetPoint = _GetTrackerSetPoint()
    local resetCords = { ["BOTTOMLEFT"] = { x = -xOff, y = -yOff }, ["BOTTOMRIGHT"] = { x = xOff, y = -yOff }, ["TOPLEFT"] = { x = -xOff, y = yOff }, ["TOPRIGHT"] = { x = xOff, y = yOff } }
    baseFrame:ClearAllPoints()

    if trackerSetPoint then
        baseFrame:SetPoint(trackerSetPoint, UIParent, "CENTER", resetCords[trackerSetPoint].x, resetCords[trackerSetPoint].y)
        Questie.db.profile.TrackerLocation = { trackerSetPoint, "UIParent", "CENTER", resetCords[trackerSetPoint].x, resetCords[trackerSetPoint].y }
    end

    QuestieTracker:Update()
end

function TrackerBaseFrame:GetSavedLocation()
    return _NormalizeTrackerLocation(Questie.db.profile.TrackerLocation)
end

function TrackerBaseFrame:GetCurrentLocation()
    if not baseFrame or not baseFrame.GetPoint then
        return nil
    end

    local point, relativeTo, relativePoint, xOffset, yOffset = baseFrame:GetPoint()
    if not point then
        return nil
    end

    local relativeName = "UIParent"
    if type(relativeTo) == "string" and relativeTo ~= "" then
        relativeName = relativeTo
    elseif type(relativeTo) == "table" and relativeTo.GetName and relativeTo:GetName() then
        relativeName = relativeTo:GetName()
    end

    if not VALID_ANCHOR_POINTS[relativePoint] then
        relativePoint = point
    end

    return { point, relativeName, relativePoint, tonumber(xOffset) or 0, tonumber(yOffset) or 0 }
end

function TrackerBaseFrame:CaptureCollapsePosition()
    if Questie.db.profile.trackerCollapseDirection ~= "upward" or not baseFrame then
        return nil
    end

    return baseFrame:GetTop()
end

function TrackerBaseFrame:RestoreCollapsePosition(targetTop)
    if Questie.db.profile.trackerCollapseDirection ~= "upward" or not baseFrame or not targetTop then
        return
    end

    local currentTop = baseFrame:GetTop()
    if not currentTop then
        return
    end

    local verticalOffset = targetTop - currentTop
    if math.abs(verticalOffset) <= TRACKER_COORD_EPSILON then
        return
    end

    local point, relativeTo, relativePoint, xOffset, yOffset = baseFrame:GetPoint()
    if not VALID_ANCHOR_POINTS[point] then
        return
    end

    if not VALID_ANCHOR_POINTS[relativePoint] then
        relativePoint = point
    end

    relativeTo = relativeTo or UIParent
    xOffset = tonumber(xOffset) or 0
    yOffset = (tonumber(yOffset) or 0) + verticalOffset

    baseFrame:ClearAllPoints()
    baseFrame:SetPoint(point, relativeTo, relativePoint, xOffset, yOffset)

    local relativeName = "UIParent"
    if type(relativeTo) == "string" and relativeTo ~= "" then
        relativeName = relativeTo
    elseif type(relativeTo) == "table" and relativeTo.GetName and relativeTo:GetName() then
        relativeName = relativeTo:GetName()
    end

    Questie.db.profile.TrackerLocation = { point, relativeName, relativePoint, xOffset, yOffset }
end

function TrackerBaseFrame:IsSavedLocationMalformed()
    local location = Questie.db.profile.TrackerLocation
    if type(location) ~= "table" then
        return true
    end

    return not VALID_ANCHOR_POINTS[location[1]]
        or not VALID_ANCHOR_POINTS[location[3]]
        or type(location[2]) ~= "string"
        or location[2] == ""
end

function TrackerBaseFrame:RepairLocation()
    Questie.db.profile.trackerSetpoint = _GetTrackerSetPoint()

    local normalized = _NormalizeTrackerLocation(Questie.db.profile.TrackerLocation)
    if normalized then
        Questie.db.profile.TrackerLocation = normalized

        if baseFrame then
            baseFrame:ClearAllPoints()
            baseFrame:SetPoint(unpack(normalized))
            _UpdateTrackerPosition(true)
        end
    elseif baseFrame then
        _UpdateTrackerPosition(true)

        if not _NormalizeTrackerLocation(Questie.db.profile.TrackerLocation) then
            Questie.db.profile.TrackerLocation = nil
            TrackerBaseFrame:SetSafePoint()
        end
    else
        Questie.db.profile.TrackerLocation = nil
    end

    if QuestieTracker and QuestieTracker.started then
        QuestieTracker:Update()
    end
end

function TrackerBaseFrame.ShrinkToMinSize(minSize)
    baseFrame:SetHeight(minSize)
end

---@param button string @The mouse button that is pressed when dragging starts
function TrackerBaseFrame.OnDragStart(frame, button)
    if GameTooltip:IsShown() then
        GameTooltip:Hide()
        GameTooltip._SizerToolTip = nil
    end

    if InCombatLockdown() or IsShiftKeyDown() or IsAltKeyDown() then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnDragStart] - In Combat or shift key or alt key detected! --> Exiting.")
        return
    else
        if (IsControlKeyDown() and Questie.db.profile.trackerLocked and not ChatEdit_GetActiveWindow()) or not Questie.db.profile.trackerLocked then
            if TrackerBaseFrame.isMoving ~= false or TrackerBaseFrame.isSizing == true then
                Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnDragStart] - Frame is already moving or frame is already resizing! --> Exiting.")
                return
            end
        else
            Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnDragStart] - Tracker is Locked. Use CTRL Key. --> Exiting.")
            return
        end
    end

    if TrackerBaseFrame.isMoving ~= true and TrackerBaseFrame.isSizing ~= true then
        if IsMouseButtonDown(button) and button ~= "MiddleButton" then
            if (IsControlKeyDown() and Questie.db.profile.trackerLocked and not ChatEdit_GetActiveWindow()) or not Questie.db.profile.trackerLocked then
                if baseFrame:IsMovable() then
                    Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnDragStart] - Dragging Started.")
                    TrackerBaseFrame.isMoving = true
                    TrackerBaseFrame.baseFrame.isMoving = true

                    baseFrame:StartMoving()
                    TrackerBaseFrame:Update()
                else
                    Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnDragStart] - Frame is not movable!")
                end
            end
        end
    end
end

_UpdateTrackerPosition = function(forceSave)
    if TrackerBaseFrame.isMoving ~= true and TrackerBaseFrame.isResizing ~= true then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:UpdateTrackerPosition]")
    else
        Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:UpdateTrackerPosition] - Frame is moving or resizing! --> Exiting.")
        return
    end

    local xLeft, yTop, xRight, yBottom = _GetFrameBoundsInUIParentUnits()
    if not (xLeft and yTop and xRight and yBottom) then
        return
    end
    local needsClamp
    needsClamp, xLeft, yTop, xRight, yBottom = _NeedsTrackerClamp(xLeft, yTop, xRight, yBottom)
    if not forceSave and not needsClamp then
        C_Timer.After(0.12, function()
            QuestieCombatQueue:Queue(function()
                QuestieTracker:Update()
            end)
        end)
        return
    end

    local trackerSetPoint = _GetTrackerSetPoint()
    baseFrame:ClearAllPoints()

    if trackerSetPoint == "BOTTOMLEFT" then
        baseFrame:SetPoint("BOTTOMLEFT", UIParent, xLeft, yBottom)
        Questie.db.profile.TrackerLocation = { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", xLeft, yBottom }
    elseif trackerSetPoint == "BOTTOMRIGHT" then
        baseFrame:SetPoint("BOTTOMRIGHT", UIParent, -(GetScreenWidth() - xRight), yBottom)
        Questie.db.profile.TrackerLocation = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -(GetScreenWidth() - xRight), yBottom }
    elseif trackerSetPoint == "TOPRIGHT" then
        baseFrame:SetPoint("TOPRIGHT", UIParent, -(GetScreenWidth() - xRight), -(GetScreenHeight() - yTop))
        Questie.db.profile.TrackerLocation = { "TOPRIGHT", "UIParent", "TOPRIGHT", -(GetScreenWidth() - xRight), -(GetScreenHeight() - yTop) }
    else
        baseFrame:SetPoint("TOPLEFT", UIParent, xLeft, -(GetScreenHeight() - yTop))
        Questie.db.profile.TrackerLocation = { "TOPLEFT", "UIParent", "TOPLEFT", xLeft, -(GetScreenHeight() - yTop) }
    end

    C_Timer.After(0.12, function()
        QuestieCombatQueue:Queue(function()
            QuestieTracker:Update()
        end)
    end)
end

function TrackerBaseFrame.OnDragStop(frame, button)
    if IsShiftKeyDown() or IsAltKeyDown() then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnDragStop] - Shift key or alt key detected! --> Exiting.")
        return
    else
        if TrackerBaseFrame.isMoving ~= true or TrackerBaseFrame.isSizing == true then
            Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnDragStop] - Frame isn't moving or frame is resizing! --> Exiting.")
            return
        end
    end

    if TrackerBaseFrame.isMoving ~= false and TrackerBaseFrame.isSizing ~= true then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnDragStop] - Dragging Stopped.")

        TrackerBaseFrame.isMoving = false
        TrackerBaseFrame.baseFrame.isMoving = false

        baseFrame:StopMovingOrSizing()
        QuestieCombatQueue:Queue(function()
            _UpdateTrackerPosition(true)
        end)
    end
end

---@param button string @The mouse button that is pressed when resize starts
function TrackerBaseFrame.OnResizeStart(frame, button)
    if GameTooltip:IsShown() then
        GameTooltip:Hide()
        GameTooltip._SizerToolTip = nil
    end

    local ctrlActive = IsControlKeyDown() and not ChatEdit_GetActiveWindow()
    local useScaleSizing = ctrlActive and not IsShiftKeyDown()

    if InCombatLockdown() or IsAltKeyDown() then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnResizeStart] - In Combat or alt key detected! --> Exiting.") -- TODO: Why is the alt key a problem?
        return
    else
        if (ctrlActive and Questie.db.profile.trackerLocked) or not Questie.db.profile.trackerLocked then
            if TrackerBaseFrame.isSizing ~= false or TrackerBaseFrame.isMoving == true then
                Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnResizeStart] - Frame is already resizing or frame is moving! --> Exiting.")
                return
            end
        else
            Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnResizeStart] - Tracker is Locked. Use CTRL Key. --> Exiting.")
            return
        end
    end

    if TrackerBaseFrame.isSizing ~= true and TrackerBaseFrame.isMoving ~= true then
        if IsMouseButtonDown(button) and button ~= "MiddleButton" then
            if (ctrlActive and Questie.db.profile.trackerLocked) or not Questie.db.profile.trackerLocked then
                if baseFrame:IsResizable() then
                    if button == "LeftButton" then
                        Questie:Debug(Questie.DEBUG_DEVELOP, useScaleSizing and "[TrackerBaseFrame:OnResizeStart] - Scale Sizing Started." or "[TrackerBaseFrame:OnResizeStart] - Sizing Started.")
                        TrackerBaseFrame.isSizing = true
                        TrackerBaseFrame.isScaleSizing = useScaleSizing
                        TrackerBaseFrame.baseFrame.isSizing = true
                        TrackerBaseFrame.baseFrame.isScaleSizing = useScaleSizing
                        resizePreviewWidth = nil
                        resizePreviewHeight = nil
                        _EnableSizerPreview()

                        if updateTimer then
                            updateTimer:Cancel()
                            updateTimer = nil
                        end

                        if useScaleSizing then
                            scaleDragStartX, scaleDragStartY = _GetCursorPositionInUIUnits()
                            scaleDragStartValue = _RoundTrackerScale(Questie.db.profile.trackerScale)

                            updateTimer = C_Timer.NewTicker(0.03, function()
                                _UpdateTrackerScaleFromDrag()
                            end)
                        else
                            -- Size from the visible lower-right nib and keep the content layout frozen
                            -- while dragging so the tracker shell feels fluid instead of jittering.
                            baseFrame:StartSizing("BOTTOMRIGHT")

                            updateTimer = C_Timer.NewTicker(0.03, function()
                                _UpdateTrackerResizePreview()
                            end)
                        end
                    end
                else
                    Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnResizeStart] - Frame is not resizable!")
                end

                if button == "RightButton" then
                    Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnResizeStart] - Resetting Sizer mode.")
                    Questie.db.profile.TrackerWidth = 0
                    Questie.db.profile.TrackerHeight = 0
                end
            end
        end
    end
end

---@param button string @The mouse button that is pressed when resize stops
function TrackerBaseFrame.OnResizeStop(frame, button)
    if IsAltKeyDown() then
        Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnResizeStop] - Alt key detected! --> Exiting.") -- TODO: Why is the alt key a problem?
        return
    else
        if TrackerBaseFrame.isSizing ~= true or TrackerBaseFrame.isMoving == true then
            if button == "LeftButton" or button == "MiddleButton" then
                Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnResizeStop] - Frame isn't resizing or frame is moving! --> Exiting.")
                return
            end

            if button == "RightButton" then
                Questie:Debug(Questie.DEBUG_DEVELOP, "[TrackerBaseFrame:OnResizeStop] - Sizer mode reset. Updating Tracker.")

                QuestieCombatQueue:Queue(function()
                    QuestieTracker:Update()
                end)
                return
            end
        end
    end

    if TrackerBaseFrame.isSizing ~= false and TrackerBaseFrame.isMoving ~= true then
        Questie:Debug(Questie.DEBUG_DEVELOP, TrackerBaseFrame.isScaleSizing and "[TrackerBaseFrame:OnResizeStop] - Scale Sizing Stopped." or "[TrackerBaseFrame:OnResizeStop] - Sizing Stopped.")

        if not TrackerBaseFrame.isScaleSizing then
            local trackerWidth, trackerHeight = _GetPreviewTrackerDimensions()
            if trackerWidth and trackerHeight then
                Questie.db.profile.TrackerWidth = trackerWidth
                Questie.db.profile.TrackerHeight = trackerHeight
                resizePreviewWidth = trackerWidth
                resizePreviewHeight = trackerHeight
            end
        end

        TrackerBaseFrame.isSizing = false
        TrackerBaseFrame.isScaleSizing = false
        TrackerBaseFrame.baseFrame.isSizing = false
        TrackerBaseFrame.baseFrame.isScaleSizing = false
        scaleDragStartX = nil
        scaleDragStartY = nil
        scaleDragStartValue = nil
        resizePreviewWidth = nil
        resizePreviewHeight = nil

        -- This returns the players desired Background, Border and Fader to the correct setting
        _RestoreSizerPreview()

        baseFrame:StopMovingOrSizing()
        if updateTimer then
            updateTimer:Cancel()
            updateTimer = nil
        end
        baseFrame.sizer:SetAlpha(_GetSizerBaseAlpha())
        QuestieCombatQueue:Queue(function()
            _UpdateTrackerPosition(false)
        end)
    end
end

function TrackerBaseFrame:OnProfileChange()
    local QuestieTrackerLoc = _NormalizeTrackerLocation(Questie.db.profile.TrackerLocation)

    if (not baseFrame) and Questie.db.profile.trackerEnabled then
        -- The Tracker was disabled and is now enabled
        QuestieTracker:Enable()
        return
    elseif baseFrame and (not Questie.db.profile.trackerEnabled) then
        -- The Tracker was enabled and is now disabled
        QuestieTracker:Disable()
        return
    end

    if QuestieTrackerLoc then
        Questie.db.profile.TrackerLocation = QuestieTrackerLoc
        baseFrame:ClearAllPoints()
        baseFrame:SetPoint(QuestieTrackerLoc[1], QuestieTrackerLoc[2], QuestieTrackerLoc[3], QuestieTrackerLoc[4], QuestieTrackerLoc[5])

        C_Timer.After(0.12, function()
            QuestieCombatQueue:Queue(function()
                QuestieTracker:Update()
            end)
        end)
    else
        Questie.db.profile.TrackerLocation = nil
        _UpdateTrackerPosition(true)
    end
end

_OnEnter = function(self)
    if InCombatLockdown() then
        if GameTooltip:IsShown() then
            GameTooltip:Hide()
            return
        end
    end

    -- Set initial tooltip
    GameTooltip._owner = self
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    _SetSizerTooltip()

    -- Update tooltip
    GameTooltip._SizerToolTip = _SetSizerTooltip

    TrackerFadeTicker.Unfade(self)
end

_SetSizerTooltip = function()
    -- Set Sizer mode
    local trackerSizeMode
    if Questie.db.profile.TrackerHeight == 0 then
        trackerSizeMode = Questie:Colorize(l10n("Auto"), "green")
    else
        trackerSizeMode = Questie:Colorize(l10n("Manual"), "orange")
    end

    if IsShiftKeyDown() then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(Questie:Colorize(l10n("Sizer Mode") .. ": ", "white") .. trackerSizeMode)
        if Questie.db.profile.trackerLocked then
            GameTooltip:AddLine(Questie:Colorize(l10n("Ctrl + Left Click + Hold") .. ": ", "gray") .. l10n("Scale Tracker"))
            GameTooltip:AddLine(Questie:Colorize(l10n("Ctrl + Shift + Left Click + Hold") .. ": ", "gray") .. l10n("Resize Tracker"))
            GameTooltip:AddLine(Questie:Colorize(l10n("Ctrl + Right Click") .. ": ", "gray") .. l10n("Reset Sizer"))
        else
            GameTooltip:AddLine(Questie:Colorize(l10n("Left Click + Hold") .. ": ", "gray") .. l10n("Resize Tracker"))
            GameTooltip:AddLine(Questie:Colorize(l10n("Ctrl + Left Click + Hold") .. ": ", "gray") .. l10n("Scale Tracker"))
            GameTooltip:AddLine(Questie:Colorize(l10n("Right Click") .. ": ", "gray") .. l10n("Reset Sizer"))
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Questie:Colorize(l10n("NOTE") .. ": ", "red") .. l10n("The Tracker Height Ratio\nis ignored while in Manual mode"))
        GameTooltip:Show()
    else
        GameTooltip:ClearLines()
        GameTooltip:AddLine(Questie:Colorize(l10n("Sizer Mode") .. ": ", "white") .. trackerSizeMode)
        if Questie.db.profile.trackerLocked then
            GameTooltip:AddLine(Questie:Colorize(l10n("Ctrl + Drag") .. ": ", "gray") .. l10n("Scale Tracker"))
        else
            GameTooltip:AddLine(Questie:Colorize(l10n("Drag") .. ": ", "gray") .. l10n("Resize Tracker"))
            GameTooltip:AddLine(Questie:Colorize(l10n("Ctrl + Drag") .. ": ", "gray") .. l10n("Scale Tracker"))
        end
        GameTooltip:AddLine(Questie:Colorize("(" .. l10n("Hold Shift for more") .. ")", "gray"))
        GameTooltip:Show()
    end
end
