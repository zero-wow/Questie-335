---@class QuestieCustomConfigSkin
local QuestieCustomConfigSkin = QuestieLoader:CreateModule("QuestieCustomConfigSkin")

local unpack = unpack or table.unpack

local backdropCache = {}

local function _GetBackdrop(edgeSize)
    edgeSize = edgeSize or 1

    if not backdropCache[edgeSize] then
        backdropCache[edgeSize] = {
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = true,
            tileSize = 16,
            edgeSize = edgeSize,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        }
    end

    return backdropCache[edgeSize]
end

function QuestieCustomConfigSkin:ApplySquareBackdrop(frame, bgColor, borderColor, edgeSize)
    frame:SetBackdrop(_GetBackdrop(edgeSize))
    frame:SetBackdropColor(unpack(bgColor))
    frame:SetBackdropBorderColor(unpack(borderColor))
end

function QuestieCustomConfigSkin:CreateSolid(parent, layer, color, subLevel)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    if subLevel then
        texture:SetDrawLayer(layer or "BACKGROUND", subLevel)
    end
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    texture:SetVertexColor(unpack(color))
    return texture
end

function QuestieCustomConfigSkin:ColorFont(fontString, color)
    fontString:SetTextColor(unpack(color))
end

