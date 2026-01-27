--[[
    DCS SAM System Configuration
    SAMシステムの設定ファイル

    各SAMタイプの設定:
    - suppressionRate: 停波確率 (0-100)
    - minOffDelay: 停波するまでの最小時間(秒)
    - maxOffDelay: 停波するまでの最大時間(秒)
    - minOnDelay: 再起動までの最小時間(秒)
    - maxOnDelay: 再起動までの最大時間(秒)
    - suppressGroup: true=グループ全体を停波, false=ユニット単体
    - category: SAMカテゴリ (EWR, SR, TR, LN, SHORAD)
    - trackingRange: 追尾レーダー射程(km)
    - engagementRange: 交戦射程(km)
]]

SAM_CONFIG = {}

-- ============================================
-- SAMタイプ定義
-- ============================================
SAM_CONFIG.Types = {
    -- Early Warning Radars (早期警戒レーダー)
    ["1L13 EWR"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "EWR",
        trackingRange = 300,
        engagementRange = 0,
        displayName = "1L13 EWR"
    },
    ["55G6 EWR"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "EWR",
        trackingRange = 400,
        engagementRange = 0,
        displayName = "55G6 EWR"
    },

    -- S-125 Neva (SA-3 Goa)
    ["p-19 s-125 sr"] = {
        suppressionRate = 100,
        minOffDelay = 15, maxOffDelay = 20,
        minOnDelay = 40, maxOnDelay = 80,
        suppressGroup = false,
        category = "SR",
        trackingRange = 160,
        engagementRange = 0,
        displayName = "P-19 S-125 SR"
    },
    ["snr s-125 tr"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 15,
        minOnDelay = 20, maxOnDelay = 40,
        suppressGroup = false,
        category = "TR",
        trackingRange = 100,
        engagementRange = 35,
        displayName = "SNR S-125 TR"
    },

    -- SA-2 Guideline
    ["SNR_75V"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 20,
        minOnDelay = 40, maxOnDelay = 80,
        suppressGroup = false,
        category = "TR",
        trackingRange = 120,
        engagementRange = 43,
        displayName = "SNR-75V (SA-2)"
    },

    -- SA-6 Kub (Gainful)
    ["Kub 1S91 str"] = {
        suppressionRate = 100,
        minOffDelay = 15, maxOffDelay = 20,
        minOnDelay = 40, maxOnDelay = 60,
        suppressGroup = true, -- 2バンドレーダーのため、グループ全体を停波
        category = "STR",
        trackingRange = 75,
        engagementRange = 24,
        displayName = "Kub 1S91 STR (SA-6)"
    },
    ["Dog Ear radar"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "SR",
        trackingRange = 40,
        engagementRange = 0,
        displayName = "Dog Ear Radar"
    },

    -- SA-8 Osa (Gecko)
    ["Osa 9A33 ln"] = {
        suppressionRate = 100,
        minOffDelay = 7, maxOffDelay = 10,
        minOnDelay = 30, maxOnDelay = 50,
        suppressGroup = false,
        category = "LN",
        trackingRange = 30,
        engagementRange = 10,
        displayName = "9A33 Osa (SA-8)"
    },

    -- S-300PS (SA-10 Grumble)
    ["S-300PS 40B6M tr"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "TR",
        trackingRange = 150,
        engagementRange = 75,
        displayName = "S-300PS 40B6M TR"
    },
    ["S-300PS 40B6MD sr"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "SR",
        trackingRange = 300,
        engagementRange = 0,
        displayName = "S-300PS 40B6MD SR"
    },
    ["S-300PS 64H6E sr"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "SR",
        trackingRange = 300,
        engagementRange = 0,
        displayName = "S-300PS 64H6E SR"
    },

    -- SA-11 Buk (Gadfly)
    ["SA-11 Buk SR 9S18M1"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "SR",
        trackingRange = 140,
        engagementRange = 0,
        displayName = "SA-11 Buk SR"
    },
    ["SA-11 Buk LN 9A310M1"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "LN",
        trackingRange = 85,
        engagementRange = 35,
        displayName = "SA-11 Buk LN"
    },

    -- Tor (SA-15 Gauntlet)
    ["Tor 9A331"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "SHORAD",
        trackingRange = 25,
        engagementRange = 12,
        displayName = "Tor 9A331 (SA-15)"
    },

    -- Western Systems
    -- Hawk
    ["Hawk tr"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "TR",
        trackingRange = 90,
        engagementRange = 45,
        displayName = "Hawk TR"
    },
    ["Hawk sr"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "SR",
        trackingRange = 100,
        engagementRange = 0,
        displayName = "Hawk SR"
    },
    ["Hawk cwar"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "TR",
        trackingRange = 100,
        engagementRange = 0,
        displayName = "Hawk CWAR"
    },

    -- Patriot
    ["Patriot str"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "STR",
        trackingRange = 170,
        engagementRange = 100,
        displayName = "Patriot STR"
    },

    -- Roland
    ["Roland Radar"] = {
        suppressionRate = 100,
        minOffDelay = 10, maxOffDelay = 11,
        minOnDelay = 10, maxOnDelay = 11,
        suppressGroup = false,
        category = "SHORAD",
        trackingRange = 15,
        engagementRange = 8,
        displayName = "Roland Radar"
    },
}

-- ============================================
-- 対レーダーミサイル定義
-- ============================================
SAM_CONFIG.ARMs = {
    "KH-58",
    "KH-25MPU",
    "weapons.missiles.AGM_88",
    "weapons.missiles.LD-10",
    "weapons.missiles.ALARM",
}

-- ============================================
-- デフォルト設定
-- ============================================
SAM_CONFIG.Defaults = {
    suppressionRate = 100,
    minOffDelay = 10,
    maxOffDelay = 11,
    minOnDelay = 10,
    maxOnDelay = 11,
    suppressGroup = false,
    category = "UNKNOWN",
    trackingRange = 50,
    engagementRange = 25,
}

-- ============================================
-- ユーティリティ関数
-- ============================================

-- SAMタイプの設定を取得
function SAM_CONFIG.getTypeConfig(typeName)
    return SAM_CONFIG.Types[typeName] or SAM_CONFIG.Defaults
end

-- SAMタイプかどうかを判定
function SAM_CONFIG.isSamType(typeName)
    return SAM_CONFIG.Types[typeName] ~= nil
end

-- ARMかどうかを判定
function SAM_CONFIG.isARM(weaponTypeName)
    for _, armName in ipairs(SAM_CONFIG.ARMs) do
        if weaponTypeName == armName then
            return true
        end
    end
    return false
end

-- すべてのSAMタイプ名のリストを取得
function SAM_CONFIG.getAllTypeNames()
    local names = {}
    for name, _ in pairs(SAM_CONFIG.Types) do
        table.insert(names, name)
    end
    return names
end

-- カテゴリでフィルタリング
function SAM_CONFIG.getTypesByCategory(category)
    local types = {}
    for name, config in pairs(SAM_CONFIG.Types) do
        if config.category == category then
            types[name] = config
        end
    end
    return types
end

return SAM_CONFIG
