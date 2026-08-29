---@class TrackerFonts
local TrackerFonts = QuestieLoader:CreateModule("TrackerFonts")

local LSM30 = LibStub("LibSharedMedia-3.0")

local FONT_NONE = "NONE"
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local SHARED_MEDIA_ADDON = "SharedMedia"
local SHARED_MEDIA_FONT_ROOT = "Interface\\AddOns\\SharedMedia\\Fonts\\"

local cachedValues = {}
local cachedOverrideValues = {}
local cachedNames = {}
local cachedOverrideNames = {}
local cachedSearch = {}
local cachedVersion = 0
local callbacksRegistered = false

local function _PrewarmFontWidgetCache()
    if not LibStub then
        return
    end

    local ok, sharedMediaWidgets = pcall(LibStub, "AceGUISharedMediaWidgets-1.0", true)
    if ok and sharedMediaWidgets and sharedMediaWidgets.PrewarmTrackerFontMeasurements then
        sharedMediaWidgets:PrewarmTrackerFontMeasurements()
    end
end

local externalFontPack = {
    { "SourceCodePro (Regular)", "SourceCodePro-Regular.ttf" },
    { "SourceCodePro (Bold)", "SourceCodePro-Bold.ttf" },
    { "Source Code Pro (Regular)", "SourceCodePro-Regular.ttf" },
    { "Source Code Pro (Bold)", "SourceCodePro-Bold.ttf" },
    { "JetBrains Mono (Regular)", "JetBrainsMono-Regular.ttf" },
    { "JetBrains Mono (Medium)", "JetBrainsMono-Medium.ttf" },
    { "JetBrains Mono (Bold)", "JetBrainsMono-Bold.ttf" },
    { "IBM Plex Mono (Regular)", "IBMPlexMono-Regular.ttf" },
    { "IBM Plex Mono (Medium)", "IBMPlexMono-Medium.ttf" },
    { "IBM Plex Mono (Bold)", "IBMPlexMono-Bold.ttf" },
    { "Hack (Regular)", "Hack-Regular.ttf" },
    { "Hack (Bold)", "Hack-Bold.ttf" },
    { "Fira Mono (Regular)", "FiraMono-Regular.ttf" },
    { "Fira Mono (Bold)", "FiraMono-Bold.ttf" },
    { "Fira Code (Regular)", "FiraCode-Regular.ttf" },
    { "Fira Code (Medium)", "FiraCode-Medium.ttf" },
    { "Fira Code (Bold)", "FiraCode-Bold.ttf" },
    { "Cascadia Mono (Regular)", "CascadiaMono-Regular.ttf" },
    { "Cascadia Mono (SemiBold)", "CascadiaMono-SemiBold.ttf" },
    { "Cascadia Mono (Bold)", "CascadiaMono-Bold.ttf" },
    { "Cascadia Mono NF (Bold)", "CascadiaMonoNF-Bold.ttf" },
    { "Cascadia Mono PL (Bold)", "CascadiaMonoPL-Bold.ttf" },
    { "Iosevka Term (Regular)", "IosevkaTerm-Regular.ttf" },
    { "Iosevka Term (Medium)", "IosevkaTerm-Medium.ttf" },
    { "Iosevka Term (Bold)", "IosevkaTerm-Bold.ttf" },
    { "Victor Mono (Regular)", "VictorMono-Regular.ttf" },
    { "Cascadia Code (Bold)", "CascadiaCode-Bold.ttf" },
    { "Cascadia Code (SemiBold)", "CascadiaCode-SemiBold.ttf" },
    { "Cascadia Code NF (Bold)", "CascadiaCodeNF-Bold.ttf" },
    { "Cascadia Code NF (SemiBold)", "CascadiaCodeNF-SemiBold.ttf" },
    { "Cascadia Code PL (Bold)", "CascadiaCodePL-Bold.ttf" },
    { "Cascadia Code PL (SemiBold)", "CascadiaCodePL-SemiBold.ttf" },
}

local function _SortCaseInsensitive(a, b)
    return string.upper(a) < string.upper(b)
end

local function _RegisterExternalFonts()
    if not GetAddOnInfo or not GetAddOnInfo(SHARED_MEDIA_ADDON) then
        return
    end

    for _, font in ipairs(externalFontPack) do
        LSM30:Register("font", font[1], SHARED_MEDIA_FONT_ROOT .. font[2])
    end
end

local function _BuildCache()
    wipe(cachedValues)
    wipe(cachedOverrideValues)
    wipe(cachedNames)
    wipe(cachedOverrideNames)
    wipe(cachedSearch)
    cachedVersion = cachedVersion + 1

    cachedOverrideValues[FONT_NONE] = FONT_NONE
    cachedOverrideNames[1] = FONT_NONE
    cachedSearch[FONT_NONE] = string.lower(FONT_NONE)

    local fontTable = LSM30:HashTable("font") or {}
    local names = {}

    for name, path in pairs(fontTable) do
        if type(name) == "string" and type(path) == "string" and name ~= FONT_NONE then
            names[#names + 1] = name
        end
    end

    table.sort(names, _SortCaseInsensitive)

    for _, name in ipairs(names) do
        cachedValues[name] = name
        cachedNames[#cachedNames + 1] = name
        cachedOverrideValues[name] = name
        cachedOverrideNames[#cachedOverrideNames + 1] = name
        cachedSearch[name] = string.lower(name)
    end
end

local function _EnsureCache()
    if not cachedNames[1] then
        _BuildCache()
    end
end

local function _FetchFont(fontName)
    if type(fontName) ~= "string" or fontName == FONT_NONE or fontName == "" then
        return nil
    end

    return LSM30:Fetch("font", fontName, true)
end

local function _GetTrackerScale()
    local trackerScale = Questie and Questie.db and Questie.db.profile and tonumber(Questie.db.profile.trackerScale) or 1

    if trackerScale < 1 then
        trackerScale = 1
    elseif trackerScale > 5 then
        trackerScale = 5
    end

    return trackerScale
end

local function _GetGlobalFontScale()
    local fontScale = Questie and Questie.db and Questie.db.profile
        and tonumber(Questie.db.profile.trackerFontGlobalScale)
        or 1

    if fontScale < 0.5 then
        fontScale = 0.5
    elseif fontScale > 3 then
        fontScale = 3
    end

    return fontScale
end

local function _GetScaledFontSize(baseSize)
    local size = tonumber(baseSize) or 12
    local scaledSize = size * _GetTrackerScale() * _GetGlobalFontScale()

    if scaledSize < 1 then
        scaledSize = 1
    end

    return scaledSize
end

local function _GetBaseFontSize(baseSize)
    local size = tonumber(baseSize) or 12

    if size < 1 then
        size = 1
    end

    return size
end

function TrackerFonts:Initialize()
    _RegisterExternalFonts()
    _BuildCache()
    _PrewarmFontWidgetCache()

    if not callbacksRegistered then
        local ok = pcall(LSM30.RegisterCallback, self, "LibSharedMedia_Registered", "OnMediaRegistered")
        callbacksRegistered = ok and true or false
    end
end

function TrackerFonts:OnMediaRegistered(_, mediaType)
    if mediaType == "font" then
        _BuildCache()
        _PrewarmFontWidgetCache()
    end
end

function TrackerFonts:GetNoneValue()
    return FONT_NONE
end

function TrackerFonts:GetValues()
    _EnsureCache()
    return cachedValues
end

function TrackerFonts:GetOverrideValues()
    _EnsureCache()
    return cachedOverrideValues
end

function TrackerFonts:GetCacheVersion()
    _EnsureCache()
    return cachedVersion
end

function TrackerFonts:GetOrderedNames(searchText, includeNone)
    _EnsureCache()

    local sourceNames = includeNone and cachedOverrideNames or cachedNames

    if not searchText or searchText == "" then
        return sourceNames
    end

    local lowered = string.lower(searchText)
    local filtered = {}

    if includeNone then
        filtered[1] = FONT_NONE
    end

    for index = 1, #cachedNames do
        local name = cachedNames[index]
        if string.find(cachedSearch[name], lowered, 1, true) then
            filtered[#filtered + 1] = name
        end
    end

    return filtered
end

function TrackerFonts:GetFontPathByName(fontName)
    return _FetchFont(fontName) or FALLBACK_FONT
end

function TrackerFonts:GetGlobalOverrideName()
    local override = Questie and Questie.db and Questie.db.profile and Questie.db.profile.trackerFontGlobalOverride
    if override and override ~= FONT_NONE and LSM30:IsValid("font", override) then
        return override
    end
end

function TrackerFonts:IsGlobalOverrideActive()
    return self:GetGlobalOverrideName() ~= nil
end

function TrackerFonts:GetResolvedFont(fontName)
    local globalOverride = self:GetGlobalOverrideName()
    return _FetchFont(globalOverride) or _FetchFont(fontName) or FALLBACK_FONT
end

function TrackerFonts:GetScale()
    return _GetTrackerScale()
end

function TrackerFonts:GetGlobalFontScale()
    return _GetGlobalFontScale()
end

function TrackerFonts:GetScaledFontSize(baseSize)
    return _GetScaledFontSize(baseSize)
end

function TrackerFonts:GetBaseHeaderFontSize()
    return _GetBaseFontSize(Questie.db.profile.trackerFontSizeHeader)
end

function TrackerFonts:GetBaseZoneFontSize()
    return _GetBaseFontSize(Questie.db.profile.trackerFontSizeZone)
end

function TrackerFonts:GetBaseQuestFontSize()
    return _GetBaseFontSize(Questie.db.profile.trackerFontSizeQuest)
end

function TrackerFonts:GetBaseObjectiveFontSize()
    return _GetBaseFontSize(Questie.db.profile.trackerFontSizeObjective)
end

function TrackerFonts:GetHeaderFont()
    return self:GetResolvedFont(Questie.db.profile.trackerFontHeader)
end

function TrackerFonts:GetHeaderFontSize()
    return _GetScaledFontSize(Questie.db.profile.trackerFontSizeHeader)
end

function TrackerFonts:GetZoneFont()
    return self:GetResolvedFont(Questie.db.profile.trackerFontZone)
end

function TrackerFonts:GetZoneFontSize()
    return _GetScaledFontSize(Questie.db.profile.trackerFontSizeZone)
end

function TrackerFonts:GetQuestFont()
    return self:GetResolvedFont(Questie.db.profile.trackerFontQuest)
end

function TrackerFonts:GetQuestFontSize()
    return _GetScaledFontSize(Questie.db.profile.trackerFontSizeQuest)
end

function TrackerFonts:GetObjectiveFont()
    return self:GetResolvedFont(Questie.db.profile.trackerFontObjective)
end

function TrackerFonts:GetObjectiveFontSize()
    return _GetScaledFontSize(Questie.db.profile.trackerFontSizeObjective)
end
