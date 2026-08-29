---@class QuestieCustomConfigData
local QuestieCustomConfigData = QuestieLoader:CreateModule("QuestieCustomConfigData")

local function _CloneColor(color)
    return {color[1], color[2], color[3], color[4]}
end

local function _ClonePalette(source)
    local palette = {}

    for key, color in pairs(source) do
        palette[key] = _CloneColor(color)
    end

    return palette
end

QuestieCustomConfigData.defaultColorway = "ascension"

QuestieCustomConfigData.colorways = {
    ascension = {
        name = "Ascension Dark",
        subtitle = "Teal signal lines, warm gold text, and the original dark shell",
        preview = {
            {0.082, 0.855, 0.804, 1.00},
            {0.676, 0.551, 0.266, 1.00},
            {0.050, 0.058, 0.074, 1.00},
            {1.000, 0.941, 0.545, 1.00},
        },
        palette = {
            windowBg = {0.035, 0.041, 0.051, 0.97},
            headerBg = {0.062, 0.070, 0.086, 0.98},
            panelBg = {0.050, 0.058, 0.074, 0.95},
            insetBg = {0.018, 0.022, 0.031, 0.95},
            border = {0.676, 0.551, 0.266, 0.94},
            borderSoft = {0.196, 0.215, 0.247, 0.88},
            accent = {0.082, 0.855, 0.804, 0.98},
            accentSoft = {0.082, 0.855, 0.804, 0.22},
            text = {1.000, 0.859, 0.349, 1.00},
            textBright = {1.000, 0.941, 0.545, 1.00},
            textMuted = {0.772, 0.804, 0.855, 1.00},
            textSoft = {0.584, 0.627, 0.690, 1.00},
            navIdleBg = {0.040, 0.047, 0.062, 0.86},
            navHoverBg = {0.062, 0.074, 0.094, 0.92},
            navActiveBg = {0.094, 0.113, 0.141, 0.98},
            navIdleText = {0.804, 0.831, 0.882, 1.00},
            navActiveText = {1.000, 0.925, 0.529, 1.00},
            closeHover = {0.929, 0.451, 0.302, 1.00},
        },
    },
    emerald = {
        name = "Emerald Signal",
        subtitle = "Colder shell with stronger green signal accents and pale text",
        preview = {
            {0.165, 0.902, 0.612, 1.00},
            {0.133, 0.706, 0.478, 1.00},
            {0.028, 0.041, 0.050, 1.00},
            {0.925, 0.969, 0.906, 1.00},
        },
        palette = {
            windowBg = {0.024, 0.031, 0.039, 0.97},
            headerBg = {0.039, 0.054, 0.063, 0.98},
            panelBg = {0.034, 0.046, 0.056, 0.95},
            insetBg = {0.014, 0.020, 0.026, 0.95},
            border = {0.133, 0.706, 0.478, 0.92},
            borderSoft = {0.133, 0.271, 0.255, 0.88},
            accent = {0.165, 0.902, 0.612, 0.98},
            accentSoft = {0.165, 0.902, 0.612, 0.22},
            text = {0.839, 0.929, 0.804, 1.00},
            textBright = {0.925, 0.969, 0.906, 1.00},
            textMuted = {0.678, 0.859, 0.788, 1.00},
            textSoft = {0.451, 0.612, 0.561, 1.00},
            navIdleBg = {0.031, 0.042, 0.051, 0.86},
            navHoverBg = {0.041, 0.061, 0.071, 0.92},
            navActiveBg = {0.058, 0.082, 0.086, 0.98},
            navIdleText = {0.733, 0.855, 0.812, 1.00},
            navActiveText = {0.925, 0.969, 0.906, 1.00},
            closeHover = {0.953, 0.561, 0.435, 1.00},
        },
    },
    tangerine = {
        name = "Tangerine Forge",
        subtitle = "Warm orange callouts, tempered steel backgrounds, and brighter borders",
        preview = {
            {0.949, 0.486, 0.224, 1.00},
            {0.831, 0.643, 0.333, 1.00},
            {0.046, 0.037, 0.035, 1.00},
            {1.000, 0.910, 0.776, 1.00},
        },
        palette = {
            windowBg = {0.031, 0.027, 0.028, 0.97},
            headerBg = {0.052, 0.040, 0.036, 0.98},
            panelBg = {0.042, 0.034, 0.032, 0.95},
            insetBg = {0.020, 0.016, 0.018, 0.95},
            border = {0.831, 0.643, 0.333, 0.94},
            borderSoft = {0.267, 0.212, 0.188, 0.88},
            accent = {0.949, 0.486, 0.224, 0.98},
            accentSoft = {0.949, 0.486, 0.224, 0.22},
            text = {0.996, 0.831, 0.604, 1.00},
            textBright = {1.000, 0.910, 0.776, 1.00},
            textMuted = {0.855, 0.733, 0.627, 1.00},
            textSoft = {0.608, 0.506, 0.439, 1.00},
            navIdleBg = {0.038, 0.031, 0.030, 0.86},
            navHoverBg = {0.056, 0.043, 0.040, 0.92},
            navActiveBg = {0.078, 0.057, 0.050, 0.98},
            navIdleText = {0.925, 0.804, 0.690, 1.00},
            navActiveText = {1.000, 0.922, 0.812, 1.00},
            closeHover = {1.000, 0.714, 0.400, 1.00},
        },
    },
    peach = {
        name = "Peach Circuit",
        subtitle = "Softer peach highlights with a more neutral graphite shell",
        preview = {
            {0.973, 0.620, 0.537, 1.00},
            {0.871, 0.725, 0.659, 1.00},
            {0.044, 0.043, 0.052, 1.00},
            {1.000, 0.949, 0.906, 1.00},
        },
        palette = {
            windowBg = {0.030, 0.031, 0.037, 0.97},
            headerBg = {0.051, 0.052, 0.061, 0.98},
            panelBg = {0.041, 0.042, 0.051, 0.95},
            insetBg = {0.018, 0.019, 0.025, 0.95},
            border = {0.871, 0.725, 0.659, 0.94},
            borderSoft = {0.254, 0.243, 0.255, 0.88},
            accent = {0.973, 0.620, 0.537, 0.98},
            accentSoft = {0.973, 0.620, 0.537, 0.22},
            text = {0.980, 0.835, 0.792, 1.00},
            textBright = {1.000, 0.949, 0.906, 1.00},
            textMuted = {0.855, 0.788, 0.761, 1.00},
            textSoft = {0.616, 0.576, 0.592, 1.00},
            navIdleBg = {0.037, 0.037, 0.045, 0.86},
            navHoverBg = {0.054, 0.055, 0.066, 0.92},
            navActiveBg = {0.071, 0.072, 0.084, 0.98},
            navIdleText = {0.906, 0.847, 0.827, 1.00},
            navActiveText = {1.000, 0.949, 0.906, 1.00},
            closeHover = {0.976, 0.749, 0.600, 1.00},
        },
    },
}

QuestieCustomConfigData.palette = _ClonePalette(QuestieCustomConfigData.colorways[QuestieCustomConfigData.defaultColorway].palette)

QuestieCustomConfigData.tabs = {
    {
        key = "colorways_tab",
        alias = "colorways",
        title = "Colorways",
        subtitle = "Preset icon styles and command-center skin themes",
    },
    {
        key = "tracker_tab",
        alias = "tracker",
        title = "Tracker",
        subtitle = "Fonts, layout, colors, scaling, spacing, and presentation",
    },
    {
        key = "general_tab",
        alias = "general",
        title = "General",
        subtitle = "Core quest behavior, quest levels, phases, and misc controls",
    },
    {
        key = "icons_tab",
        alias = "icons",
        title = "Icons",
        subtitle = "World map, minimap, objective icon, and quest note presentation",
    },
    {
        key = "auto_tab",
        alias = "auto",
        title = "Automation",
        subtitle = "Automatic interactions, vendor helpers, and quality-of-life behavior",
    },
    {
        key = "nameplate_tab",
        alias = "nameplates",
        title = "Nameplates",
        subtitle = "Objective overlays and target marker controls for units in the world",
    },
    {
        key = "dbm_hud_tab",
        alias = "dbm",
        title = "DBM / HUD",
        subtitle = "Route HUD integration and related display settings",
    },
    {
        key = "advanced_tab",
        alias = "advanced",
        title = "Advanced",
        subtitle = "Debug, locale, hidden quest behavior, and low-level technical toggles",
    },
    {
        key = "profiles_tab",
        alias = "profiles",
        title = "Profiles",
        subtitle = "Profile switching, copying, reset, and shared configuration state",
    },
}

QuestieCustomConfigData.aliases = {}
for _, tab in ipairs(QuestieCustomConfigData.tabs) do
    QuestieCustomConfigData.aliases[string.lower(tab.alias)] = tab.key
    QuestieCustomConfigData.aliases[string.lower(tab.title)] = tab.key
end
