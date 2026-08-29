---@class QuestieRoute
local QuestieRoute = QuestieLoader:CreateModule("QuestieRoute")

---@type QuestieMap
local QuestieMap = QuestieLoader:ImportModule("QuestieMap")
---@type QuestieQuest
local QuestieQuest = QuestieLoader:ImportModule("QuestieQuest")
---@type QuestiePlayer
local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")
---@type ZoneDB
local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
---@type QuestieCoords
local QuestieCoords = QuestieLoader:ImportModule("QuestieCoords")

local HBD = QuestieCompat.HBD

local UiMapData = QuestieCompat.UiMapData

local ROUTE_TEXTURE
local ARROW_TEXTURE

local objectiveIcons
local enderIcons
local starterIcons

local ROUTE_SWITCH_MARGIN = 3 -- yards; TomTom alwaysclosest uses dist - 3
local ROUTE_TIMER_INTERVAL = 0.1 -- pfQuest uses 0.05s; 0.1s is enough for routes + arrow
local ROUTE_REPICK_INTERVAL = 0.5
local ROUTE_POSITION_SKIP = 1.0 -- skip tick when player hasn't moved (pfQuest: 1s)
local ROUTE_COLLECT_INTERVAL = 0.35 -- coalesce multikill QUEST_LOG / icon queue bursts
local ROUTE_MAP_SYNC_INTERVAL = 0.25 -- SetMapToCurrentZone throttle (arrow + tick)

local objectivePath = {}
local playerPath = {}
local mplayerPath = {}

local floor = math.floor
local ceil = math.ceil
local sqrt = math.sqrt
local atan2 = math.atan2
local pairs = pairs
local tinsert = table.insert

--- mapType 3 = zone; 0/1/2 = cosmic/world/continent (no AreaId in ZoneDB)
local function IsZoneLevelMap(uiMapId)
    local info = uiMapId and UiMapData[uiMapId]
    return info and info.mapType == 3
end

local zoneNameToUiMapId = {}
local cachedPlayerUiMapId = nil
local cachedPlayerZoneText = nil

local function ClearPath(path)
    for _, tex in pairs(path) do
        if type(tex) == "table" and tex.Hide then
            tex.enable = nil
            tex:Hide()
        end
    end
    path._nextFree = 1
end

local function AcquirePathTexture(path)
    local nline = path._nextFree or 1
    path._nextFree = nline + 1
    local tex = path[nline]
    if not tex then
        tex = QuestieRoute.routeDisplay:CreateTexture(nil, "OVERLAY")
        tex:SetWidth(4)
        tex:SetHeight(4)
        tex:SetTexture(ROUTE_TEXTURE)
        path[nline] = tex
    end
    return tex
end

local function modulo(val, by)
    return val - floor(val / by) * by
end

local function GetPlayerFacingReliable()
    local facing = GetPlayerFacing()
    if facing then
        return facing
    end
    if MinimapArrowFrame and MinimapArrowFrame.GetFacing then
        return MinimapArrowFrame:GetFacing()
    end
    return 0
end

--- HBD world bearing when available; pfQuest map bearing fallback (GetPlayerMapPosition 0-100 coords)
local function GetArrowAngle(target)
    if not target or not target[1] or not target[2] then
        return nil
    end

    if HBD and HBD.GetPlayerWorldPosition and HBD.GetWorldVector and target.uiMapId then
        local playerWorldX, playerWorldY, playerInstance = HBD:GetPlayerWorldPosition()
        local wx, wy, instance = HBD:GetWorldCoordinatesFromZone(target[1] / 100, target[2] / 100, target.uiMapId)
        if playerWorldX and wx and playerInstance == instance then
            local bearing = HBD:GetWorldVector(playerInstance, playerWorldX, playerWorldY, wx, wy)
            if bearing then
                return bearing - GetPlayerFacingReliable()
            end
        end
    end

    local xplayer, yplayer = GetPlayerMapPosition("player")
    if not xplayer or not yplayer or (xplayer == 0 and yplayer == 0) then
        return nil
    end

    local xDelta = (target[1] - xplayer * 100) * 1.5
    local yDelta = target[2] - yplayer * 100
    local dir = atan2(xDelta, -(yDelta))
    if dir > 0 then
        dir = math.pi * 2 - dir
    else
        dir = -dir
    end
    return dir - GetPlayerFacingReliable()
end

function QuestieRoute:MarkCoordsDirty()
    self.coordsDirty = true
end

function QuestieRoute:SyncRouteMap()
    if WorldMapFrame and WorldMapFrame:IsShown() then
        return
    end

    local now = GetTime()
    if self._routeMapSync and self._routeMapSync > now then
        return
    end
    self._routeMapSync = now + ROUTE_MAP_SYNC_INTERVAL
    SetMapToCurrentZone()
end

function QuestieRoute:StartRouteTimer()
    if self.routeTimer then
        return
    end
    self.routeTimer = Questie:ScheduleRepeatingTimer(function()
        QuestieRoute:OnRouteTick()
    end, ROUTE_TIMER_INTERVAL)
end

function QuestieRoute:StopRouteTimer()
    if self.routeTimer then
        Questie:CancelTimer(self.routeTimer)
        self.routeTimer = nil
    end
end

local function GetColorGradient(perc)
    local r, g, b = 1, 0, 0
    if perc > 0.5 then
        r = 2 - perc * 2
        g = 1
    else
        r = 1
        g = perc * 2
    end
    return r, g, b
end

local function GetNearest(xstart, ystart, db, blacklist)
    local nearest = nil
    local best = nil

    for id, data in pairs(db) do
        if data[1] and data[2] and not blacklist[id] then
            local x = xstart - data[1]
            local y = ystart - data[2]
            local distance = ceil(sqrt(x * x + y * y) * 100) / 100

            if not nearest or distance < nearest then
                nearest = distance
                best = id
            end
        end
    end

    if not best then
        return
    end

    blacklist[best] = true
    return db[best]
end

local function DrawLine(path, x, y, nx, ny, hl, minimap)
    if minimap then
        return
    end

    local dx = x - nx
    local dy = y - ny
    local dots = ceil(sqrt(dx * 1.5 * dx * 1.5 + dy * dy))
    local mapW = WorldMapButton:GetWidth()
    local mapH = WorldMapButton:GetHeight()
    local r, g, b = 0.6, 0.4, 0.2
    if hl then
        r, g, b = 1, 0.8, 0.4
    end

    for i = 2, dots - 2 do
        local xpos = (nx + dx / dots * i) / 100 * mapW
        local ypos = (ny + dy / dots * i) / 100 * mapH

        local tex = AcquirePathTexture(path)
        if tex._routeColor ~= hl then
            tex:SetVertexColor(r, g, b, 1)
            tex._routeColor = hl
        end
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", WorldMapButton, "TOPLEFT", xpos, -ypos)
        tex:Show()
        tex.enable = true
    end
end

function QuestieRoute:IsObjectiveActive(objective, quest)
    if not objective then
        return false
    end
    if objective.Completed or objective.HideIcons or objective.FadeIcons then
        return false
    end
    if objective.Needed and objective.Collected and objective.Collected >= objective.Needed then
        return false
    end
    if quest and quest.FadeIcons then
        return false
    end
    return true
end

function QuestieRoute:AddRoutePoint(coords, usedKeys, x, y, uiMapId, key, meta, routeId)
    if usedKeys[key] then
        return
    end
    usedKeys[key] = true
    tinsert(coords, { x, y, meta, 0, uiMapId = uiMapId, key = key, routeId = routeId })
end

function QuestieRoute:GetRouteId(questId, objective)
    if objective then
        return questId .. ":" .. (objective.Index or 0)
    end
    return questId .. ":finisher"
end

function QuestieRoute:PickPrimaryTarget(coords)
    if not coords[1] then
        self.activeTargetKey = nil
        self.activeRouteId = nil
        return
    end

    local closestIdx = 1
    local closestDist = coords[1][4] or 999999999

    for i = 2, #coords do
        local dist = coords[i][4]
        if dist and dist < closestDist then
            closestDist = dist
            closestIdx = i
        end
    end

    local chosenIdx = closestIdx

    -- TomTom CrazyArrow alwaysclosest: switch only if challenger is 3+ yards closer
    if self.activeRouteId then
        local activeIdx, activeDist
        for i, point in ipairs(coords) do
            if point.routeId == self.activeRouteId then
                activeIdx = i
                activeDist = point[4]
                break
            end
        end

        if activeIdx then
            if closestIdx ~= activeIdx and closestDist and activeDist then
                if not (closestDist < activeDist - ROUTE_SWITCH_MARGIN) then
                    chosenIdx = activeIdx
                end
            else
                chosenIdx = activeIdx
            end
        end
    end

    if chosenIdx ~= 1 then
        coords[1], coords[chosenIdx] = coords[chosenIdx], coords[1]
    end

    self.activeTargetKey = coords[1].key
    self.activeRouteId = coords[1].routeId
end

--- Keep the locked target at coords[1] for arrow/path drawing between repicks.
function QuestieRoute:PromoteActiveTarget(coords)
    if not self.activeRouteId or not coords[1] then
        return
    end

    if coords[1].routeId == self.activeRouteId then
        return
    end

    for i = 2, #coords do
        if coords[i].routeId == self.activeRouteId then
            coords[1], coords[i] = coords[i], coords[1]
            return
        end
    end

    self.activeRouteId = nil
    self.activeTargetKey = nil
end

function QuestieRoute:GetActiveTarget(coords)
    if not coords or not coords[1] then
        return self.cachedArrowTarget
    end

    if self.activeRouteId then
        for _, point in ipairs(coords) do
            if point.routeId == self.activeRouteId then
                return point
            end
        end
    end

    return coords[1]
end

function QuestieRoute:RefreshArrowCache()
    if not self.coords or not self.coords[1] then
        return self.cachedArrowTarget
    end

    local active = self:GetActiveTarget(self.coords)
    if active and active[4] then
        self.cachedArrowTarget = active
        return active
    end
    return self.cachedArrowTarget
end

function QuestieRoute:UpdateDistances(coords, xplayer, yplayer)
    local px, py, pZone
    local playerWorldX, playerWorldY, playerInstance
    if HBD then
        if HBD.GetPlayerZonePosition then
            px, py, pZone = HBD:GetPlayerZonePosition()
        end
        if HBD.GetPlayerWorldPosition then
            playerWorldX, playerWorldY, playerInstance = HBD:GetPlayerWorldPosition()
        end
    end

    if not xplayer or not yplayer then
        local x, y = GetPlayerMapPosition("player")
        if x and x > 0 and y and y > 0 then
            xplayer, yplayer = x * 100, y * 100
        end
    end

    for _, point in ipairs(coords) do
        if point[1] and point[2] and point.uiMapId then
            local yardDist

            if px and py and pZone and HBD.GetZoneDistance then
                yardDist = HBD:GetZoneDistance(pZone, px, py, point.uiMapId, point[1] / 100, point[2] / 100)
            end

            if not yardDist and playerWorldX and playerInstance and HBD.GetWorldCoordinatesFromZone and HBD.GetWorldDistance then
                local wx, wy, instance = HBD:GetWorldCoordinatesFromZone(point[1] / 100, point[2] / 100, point.uiMapId)
                if wx and wy and playerInstance == instance then
                    yardDist = HBD:GetWorldDistance(playerInstance, playerWorldX, playerWorldY, wx, wy)
                end
            end

            -- Legacy pfQuest map units (not true yards) when HBD cannot resolve positions
            if not yardDist and xplayer and yplayer then
                local x = (xplayer - point[1]) * 1.5
                local y = yplayer - point[2]
                yardDist = sqrt(x * x + y * y)
            end

            if yardDist then
                point[4] = ceil(yardDist * 100) / 100
            end
        end
    end
end

function QuestieRoute:IsRouteEligible(frame)
    local data = frame.data
    if not data or frame.miniMapIcon then
        return false
    end

    if frame.shouldBeShowing == false or frame:ShouldBeHidden() then
        return false
    end

    local profile = Questie.db.profile
    local icon = data.Icon
    local quest = data.QuestData

    if data.ObjectiveData and quest then
        if not self:IsObjectiveActive(data.ObjectiveData, quest) then
            return false
        end
    elseif quest and quest.FadeIcons then
        return false
    end

    if objectiveIcons[icon] then
        return true
    end

    if profile.enableRouteCluster and icon == Questie.ICON_TYPE_GLOW then
        return true
    end

    if profile.enableRouteEnder and enderIcons[icon] then
        return quest and quest:IsComplete() == 1
    end

    if profile.enableRouteStarter and starterIcons[icon] then
        return true
    end

    return false
end

function QuestieRoute:GetPlayerRouteUiMapId()
    local zoneText = GetRealZoneText and GetRealZoneText()
    if zoneText and zoneText == cachedPlayerZoneText and cachedPlayerUiMapId then
        return cachedPlayerUiMapId
    end

    cachedPlayerZoneText = zoneText
    cachedPlayerUiMapId = zoneText and zoneNameToUiMapId[zoneText] or nil
    if cachedPlayerUiMapId then
        return cachedPlayerUiMapId
    end

    local pos, uiMapId = QuestieCoords.GetPlayerMapPosition()
    if pos and pos.x > 0 and pos.y > 0 and IsZoneLevelMap(uiMapId) then
        cachedPlayerUiMapId = uiMapId
        return uiMapId
    end

    return nil
end

function QuestieRoute:GetPlayerRouteMapPosition(playerUiMapId)
    if not playerUiMapId then
        return nil, nil
    end

    -- Never hijack world map zoom while it is open (causes tooltip flash / WORLD_MAP_UPDATE spam)
    if WorldMapFrame:IsShown() then
        if QuestieCompat.GetCurrentUiMapID() == playerUiMapId then
            local x, y = GetPlayerMapPosition("player")
            if x and x > 0 and y and y > 0 then
                return x * 100, y * 100, playerUiMapId
            end
        end
        return nil, nil
    end

    SetMapToCurrentZone()

    local x, y = GetPlayerMapPosition("player")
    if (not x or x <= 0) and (not y or y <= 0) then
        return nil, nil
    end

    local uiMapId = QuestieCompat.GetCurrentUiMapID()
    if uiMapId ~= playerUiMapId and IsZoneLevelMap(uiMapId) then
        playerUiMapId = uiMapId
    end

    return x * 100, y * 100, playerUiMapId
end

function QuestieRoute:IsSameMapZone(iconUiMapId, playerUiMapId)
    if not iconUiMapId or not playerUiMapId then
        return false
    end
    if iconUiMapId == playerUiMapId then
        return true
    end

    if not IsZoneLevelMap(iconUiMapId) or not IsZoneLevelMap(playerUiMapId) then
        return false
    end

    local iconArea = ZoneDB:GetAreaIdByUiMapId(iconUiMapId)
    local playerArea = ZoneDB:GetAreaIdByUiMapId(playerUiMapId)
    if not iconArea or not playerArea then
        return false
    end

    if iconArea == playerArea then
        return true
    end

    return ZoneDB:GetParentZoneId(iconArea) == playerArea
        or ZoneDB:GetParentZoneId(playerArea) == iconArea
end

function QuestieRoute:IsQuestTracked(questId)
    if not QuestiePlayer.currentQuestlog[questId] then
        return false
    end
    return QuestieQuest:ShouldShowQuestNotes(questId)
end

function QuestieRoute:CollectCoords(playerUiMapId, into)
    local coords = into or {}
    for i = #coords, 1, -1 do
        coords[i] = nil
    end

    local usedKeys = {}

    -- pfQuest-style: route points come from visible map pins, not spawn DB scans
    for questId, frameNames in pairs(QuestieMap.questIdFrames) do
        if self:IsQuestTracked(questId) then
            for _, frameName in pairs(frameNames) do
                local frame = _G[frameName]
                if frame and frame.x and frame.y and self:IsRouteEligible(frame)
                    and self:IsSameMapZone(frame.UiMapID, playerUiMapId) then
                    local data = frame.data
                    local objIndex = data.ObjectiveData and data.ObjectiveData.Index or 0
                    local key = questId .. ":" .. objIndex .. ":" .. floor(frame.x + 0.5) .. "|" .. floor(frame.y + 0.5)
                    local routeId = self:GetRouteId(questId, data.ObjectiveData)
                    local meta = {
                        Id = questId,
                        Name = data.Name,
                        QuestData = data.QuestData,
                        ObjectiveData = data.ObjectiveData,
                        Icon = data.Icon,
                    }
                    self:AddRoutePoint(coords, usedKeys, frame.x, frame.y, frame.UiMapID, key, meta, routeId)
                end
            end
        end
    end

    return coords
end

function QuestieRoute:ClearAllPaths()
    ClearPath(objectivePath)
    ClearPath(playerPath)
    ClearPath(mplayerPath)
    if self.drawLayer then
        self.drawLayer:Hide()
    end
    if self.routeFrame then
        self.routeFrame.firstnode = nil
        self.routeFrame.lastPlayerLineKey = nil
        self.routeFrame.wasDrawingRoutes = false
    end
end

function QuestieRoute:UpdateArrowVisual()
    local arrow = self.arrowFrame
    if not arrow or not arrow:IsShown() then
        return
    end

    local target = self.cachedArrowTarget
    if not target or not target[4] then
        return
    end

    -- Throttle map sync; only needed when world map is closed
    if not WorldMapFrame:IsShown() then
        QuestieRoute:SyncRouteMap()
    end

    local angle = GetArrowAngle(target)
    if angle then
        self._arrowLastAngle = angle
    elseif self._arrowLastAngle then
        angle = self._arrowLastAngle
    else
        angle = 0
    end

    local cell = modulo(floor(angle / (math.pi * 2) * 108 + 0.5), 108)
    if cell ~= arrow.lastArrowCell then
        local perc = math.abs(((math.pi - math.abs(angle)) / math.pi))
        local r, g, b = GetColorGradient(floor(perc * 100) / 100)
        local column = modulo(cell, 9)
        local row = floor(cell / 9)
        arrow.model:SetTexCoord(
            (column * 56) / 512, ((column + 1) * 56) / 512,
            (row * 42) / 512, ((row + 1) * 42) / 512
        )
        arrow.model:SetVertexColor(r, g, b)
        arrow.lastArrowCell = cell
    end
    arrow.model:SetAlpha(1)
end

function QuestieRoute:UpdateArrow()
    local arrow = self.arrowFrame
    if not arrow or not Questie.db.profile.enableRouteArrow or not Questie.db.profile.enableRoutes then
        if arrow then
            arrow:Hide()
        end
        return
    end

    local target = self.cachedArrowTarget
    if not target or not target[4] then
        arrow:Hide()
        return
    end

    arrow:Show()
    self:UpdateArrowVisual()

    local meta = target[3]
    if meta and meta.QuestData then
        local objIndex = meta.ObjectiveData and meta.ObjectiveData.Index or "finisher"
        local displayKey = meta.QuestData.Id .. ":" .. tostring(objIndex)
        if displayKey ~= self._arrowDisplayKey then
            local title = meta.Name or "Objective"
            if meta.QuestData.level and Questie.db.profile.enableTooltipsQuestLevel then
                title = "[" .. meta.QuestData.level .. "] " .. title
            end
            arrow.title:SetText("|cffffcc00" .. title .. "|r")
            arrow.description:SetText("|cffffff00(!) " .. (meta.QuestData.name or "") .. "|r")
            self._arrowDisplayKey = displayKey
        end
    end

    local distance = floor((target[4] or 0) * 10) / 10
    if distance ~= arrow.distance.number then
        arrow.distance:SetText("|cffaaaaaaDistance: " .. string.format("%.1f", distance))
        arrow.distance.number = distance
    end
end

function QuestieRoute:OnRouteTick()
    local f = self.routeFrame
    local now = GetTime()

    if not Questie.db.profile.enabled or not Questie.db.profile.enableRoutes then
        if f.tickerActive then
            self:ClearAllPaths()
            if self.arrowFrame then
                self.arrowFrame:Hide()
            end
            f.tickerActive = false
        end
        return
    end

    if not f.tickerActive then
        f.tickerActive = true
    end

    local mapOpen = WorldMapFrame:IsShown()
    local xNorm, yNorm = GetPlayerMapPosition("player")
    if not mapOpen and (not xNorm or xNorm == 0) and (not yNorm or yNorm == 0) then
        self:SyncRouteMap()
        xNorm, yNorm = GetPlayerMapPosition("player")
    end
    local curpos = (xNorm or 0) + (yNorm or 0)
    local wrongmap = (not xNorm or xNorm == 0) and (not yNorm or yNorm == 0)

    -- pfQuest: skip heavy route work when player hasn't moved for ~1s (unless forced/dirty)
    if (f.positionSkip or 0) > now and f.lastpos == curpos and not f.forceUpdate and not self.coordsDirty then
        if Questie.db.profile.enableRouteArrow and self.cachedArrowTarget then
            self:UpdateDistances(self.coords)
            self:UpdateArrow()
        end
        return
    end
    f.positionSkip = now + ROUTE_POSITION_SKIP
    f.lastpos = curpos
    f.forceUpdate = nil

    local playerUiMapId = self:GetPlayerRouteUiMapId()
    local canDrawRoutes = mapOpen and playerUiMapId and QuestieCompat.GetCurrentUiMapID() == playerUiMapId

    if canDrawRoutes ~= f.wasDrawingRoutes then
        if not canDrawRoutes then
            self:ClearAllPaths()
        else
            f.firstnode = nil
            self:MarkCoordsDirty()
            if self.drawLayer then
                self.drawLayer:Show()
            end
        end
        f.wasDrawingRoutes = canDrawRoutes
    end

    if not playerUiMapId then
        self:UpdateArrow()
        return
    end

    if self.coordsDirty and (not f.nextCollect or f.nextCollect <= now) then
        local prevKey = self.coords[1] and self.coords[1].key
        self:CollectCoords(playerUiMapId, self.coords)
        self.coordsDirty = false
        f.nextCollect = now + ROUTE_COLLECT_INTERVAL
        local newKey = self.coords[1] and self.coords[1].key
        if newKey ~= prevKey then
            f.firstnode = nil
        end
        f.repick = 0
    elseif not self.coords[1] then
        self:CollectCoords(playerUiMapId, self.coords)
        f.nextCollect = now + ROUTE_COLLECT_INTERVAL
        f.firstnode = nil
        f.repick = 0
    end

    local xplayer, yplayer
    if not wrongmap then
        xplayer, yplayer = xNorm * 100, yNorm * 100
    end

    self:UpdateDistances(self.coords, xplayer, yplayer)

    if not f.repick or f.repick < now then
        self:PickPrimaryTarget(self.coords)
        f.repick = now + ROUTE_REPICK_INTERVAL
    else
        self:PromoteActiveTarget(self.coords)
    end

    local active = self:RefreshArrowCache()
    self:UpdateArrow()

    if not active or not active[4] or wrongmap then
        if not canDrawRoutes then
            ClearPath(playerPath)
        end
        return
    end

    if not canDrawRoutes or not xplayer or not yplayer then
        ClearPath(playerPath)
        return
    end

    if f.firstnode ~= (active.key or tostring(active[1] .. active[2])) then
        f.firstnode = active.key or tostring(active[1] .. active[2])

        local route = { [1] = active }
        local blacklist = { [1] = true }
        for i = 2, table.getn(self.coords) do
            if route[i - 1] then
                route[i] = GetNearest(route[i - 1][1], route[i - 1][2], self.coords, blacklist)
            end
        end

        ClearPath(objectivePath)
        for i = 2, table.getn(route) do
            if route[i] then
                DrawLine(objectivePath, route[i - 1][1], route[i - 1][2], route[i][1], route[i][2])
            end
        end
    end

    -- Redraw player path only when position or target moved (full dot density preserved)
    local lineKey = floor(xplayer + 0.5) .. ":" .. floor(yplayer + 0.5)
        .. ":" .. floor(active[1] + 0.5) .. ":" .. floor(active[2] + 0.5)
    if f.lastPlayerLineKey ~= lineKey then
        ClearPath(playerPath)
        DrawLine(playerPath, xplayer, yplayer, active[1], active[2], true)
        f.lastPlayerLineKey = lineKey
    end
end

function QuestieRoute:Reset()
    self.coords = {}
    self.firstnode = nil
    self.activeTargetKey = nil
    self.activeRouteId = nil
    self.cachedArrowTarget = nil
    self:MarkCoordsDirty()
end

function QuestieRoute:Initialize()
    if self.routeFrame then
        return
    end

    ROUTE_TEXTURE = QuestieLib.AddonPath .. "Icons\\route.tga"
    ARROW_TEXTURE = QuestieLib.AddonPath .. "Icons\\arrow.tga"

    objectiveIcons = {
        [Questie.ICON_TYPE_SLAY] = true,
        [Questie.ICON_TYPE_LOOT] = true,
        [Questie.ICON_TYPE_EVENT] = true,
        [Questie.ICON_TYPE_OBJECT] = true,
        [Questie.ICON_TYPE_TALK] = true,
        [Questie.ICON_TYPE_INCOMPLETE] = true,
        [Questie.ICON_TYPE_INTERACT] = true,
        [Questie.ICON_TYPE_SLAY_MONO] = true,
        [Questie.ICON_TYPE_LOOT_MONO] = true,
        [Questie.ICON_TYPE_OBJECT_MONO] = true,
    }

    enderIcons = {
        [Questie.ICON_TYPE_COMPLETE] = true,
        [Questie.ICON_TYPE_REPEATABLE_COMPLETE] = true,
        [Questie.ICON_TYPE_EVENTQUEST_COMPLETE] = true,
        [Questie.ICON_TYPE_PVPQUEST_COMPLETE] = true,
    }

    starterIcons = {
        [Questie.ICON_TYPE_AVAILABLE] = true,
        [Questie.ICON_TYPE_AVAILABLE_GRAY] = true,
        [Questie.ICON_TYPE_REPEATABLE] = true,
        [Questie.ICON_TYPE_EVENTQUEST] = true,
        [Questie.ICON_TYPE_PVPQUEST] = true,
    }

    for uiMapId, data in pairs(UiMapData) do
        if data.name and data.mapType == 3 then
            zoneNameToUiMapId[data.name] = uiMapId
        end
    end

    local drawLayer = CreateFrame("Frame", "QuestieRouteDrawLayer", WorldMapButton)
    drawLayer:SetFrameLevel(113)
    drawLayer:SetAllPoints()
    drawLayer:EnableMouse(false)
    drawLayer:EnableMouseWheel(false)
    drawLayer:Hide()
    self.drawLayer = drawLayer

    self.routeDisplay = CreateFrame("Frame", "QuestieRouteDisplay", drawLayer)
    self.routeDisplay:SetAllPoints()
    self.routeDisplay:EnableMouse(false)
    self.routeDisplay:EnableMouseWheel(false)

    self.coords = {}
    self.coordsDirty = true
    self.firstnode = nil
    self.activeTargetKey = nil
    self.activeRouteId = nil
    self.cachedArrowTarget = nil

    objectivePath._nextFree = 1
    playerPath._nextFree = 1
    mplayerPath._nextFree = 1

    self.routeFrame = CreateFrame("Frame", "QuestieRouteFrame", WorldFrame)
    self.routeFrame.coords = self.coords
    self.routeFrame.repick = 0
    self.routeFrame.nextCollect = 0
    self.routeFrame.firstnode = nil
    self.routeFrame.lastPlayerLineKey = nil
    self.routeFrame.lastpos = nil
    self.routeFrame.positionSkip = 0
    self.routeFrame.arrow = nil
    self.routeFrame.wasDrawingRoutes = false
    self.routeFrame.tickerActive = false
    self.routeFrame.forceUpdate = false
    self._arrowDisplayKey = nil
    self._arrowLastAngle = nil

    self.routeFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self.routeFrame:RegisterEvent("WORLD_MAP_UPDATE")
    self.routeFrame:SetScript("OnEvent", function()
        if event == "ZONE_CHANGED_NEW_AREA" then
            cachedPlayerUiMapId = nil
            cachedPlayerZoneText = nil
            this.firstnode = nil
            this.lastPlayerLineKey = nil
            this.nextCollect = 0
            this.forceUpdate = true
            QuestieRoute:MarkCoordsDirty()
        elseif event == "WORLD_MAP_UPDATE" then
            this.forceUpdate = true
        end
    end)

    self:StartRouteTimer()

    self:CreateArrow()
end

function QuestieRoute:CreateArrow()
    if self.arrowFrame then
        return
    end

    local arrow = CreateFrame("Frame", "QuestieRouteArrow", UIParent)
    arrow:SetPoint("CENTER", 0, Questie.db.profile.routeArrowPosY or -100)
    if Questie.db.profile.routeArrowPosX then
        arrow:ClearAllPoints()
        arrow:SetPoint("CENTER", UIParent, "CENTER", Questie.db.profile.routeArrowPosX, Questie.db.profile.routeArrowPosY or -100)
    end
    arrow:SetWidth(48)
    arrow:SetHeight(36)
    arrow:SetClampedToScreen(true)
    arrow:SetMovable(true)
    arrow:EnableMouse(true)
    arrow:RegisterForDrag("LeftButton")
    arrow:SetScript("OnDragStart", function()
        if IsShiftKeyDown() then
            this:StartMoving()
        end
    end)
    arrow:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local x, y = this:GetCenter()
        local uiWidth, uiHeight = UIParent:GetWidth(), UIParent:GetHeight()
        Questie.db.profile.routeArrowPosX = x - (uiWidth / 2)
        Questie.db.profile.routeArrowPosY = y - (uiHeight / 2)
    end)
    arrow:Hide()

    arrow.texture = arrow:CreateTexture(nil, "OVERLAY")
    arrow.texture:SetWidth(28)
    arrow.texture:SetHeight(28)
    arrow.texture:SetPoint("BOTTOM", 0, 0)
    arrow.texture:Hide()

    arrow.model = arrow:CreateTexture(nil, "MEDIUM")
    arrow.model:SetTexture(ARROW_TEXTURE)
    arrow.model:SetTexCoord(0, 0, 0.109375, 0.08203125)
    arrow.model:SetAllPoints()

    arrow.title = arrow:CreateFontString(nil, "HIGH", "GameFontNormal")
    arrow.title:SetPoint("TOP", arrow.model, "BOTTOM", 0, -10)
    arrow.title:SetTextColor(1, 0.8, 0)

    arrow.description = arrow:CreateFontString(nil, "HIGH", "GameFontNormalSmall")
    arrow.description:SetPoint("TOP", arrow.title, "BOTTOM", 0, -2)
    arrow.description:SetTextColor(1, 1, 1)

    arrow.distance = arrow:CreateFontString(nil, "HIGH", "GameFontNormalSmall")
    arrow.distance:SetPoint("TOP", arrow.description, "BOTTOM", 0, -2)
    arrow.distance:SetTextColor(0.8, 0.8, 0.8)

    arrow.parent = self.routeFrame
    self.routeFrame.arrow = arrow
    self.arrowFrame = arrow
    arrow.lastArrowCell = nil
    arrow:SetScript("OnUpdate", function()
        QuestieRoute:UpdateArrowVisual()
    end)
end

return QuestieRoute
