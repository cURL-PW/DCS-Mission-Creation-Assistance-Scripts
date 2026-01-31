--[[
    DCS SAM Anti-Jamming System
    ジャマー対策システム

    電子戦（ECM）ジャマーに対するSAMの対抗措置をシミュレート

    機能:
    - ジャマー検出と追跡
    - ジャミング効果のシミュレーション
    - ECCM（電子対抗対抗手段）
    - 周波数ホッピング
    - バーンスルー（ジャマー位置特定）
    - ホームオンジャム（HOJ）モード

    依存: core/utils.lua, iads/network.lua
]]

SAM_ANTI_JAM = {}
SAM_ANTI_JAM.__index = SAM_ANTI_JAM

-- ============================================
-- ジャマータイプ
-- ============================================
SAM_ANTI_JAM.JAMMER_TYPE = {
    NOISE = "NOISE",           -- ノイズジャミング
    DECEPTIVE = "DECEPTIVE",   -- 欺瞞ジャミング
    DRFM = "DRFM",             -- デジタルRF記憶ジャミング
    BARRAGE = "BARRAGE",       -- バラージジャミング
    SPOT = "SPOT"              -- スポットジャミング
}

-- ============================================
-- ECCM（対抗対抗手段）モード
-- ============================================
SAM_ANTI_JAM.ECCM_MODE = {
    PASSIVE = "PASSIVE",       -- パッシブモード（送波停止）
    FREQ_HOP = "FREQ_HOP",     -- 周波数ホッピング
    BURN_THROUGH = "BURN_THROUGH", -- バーンスルー（高出力）
    HOJ = "HOJ",               -- ホームオンジャム
    TRIANGULATION = "TRIANGULATION" -- 三角測量
}

-- ============================================
-- ジャミング状態
-- ============================================
SAM_ANTI_JAM.JAM_STATUS = {
    CLEAR = "CLEAR",           -- ジャミングなし
    LIGHT = "LIGHT",           -- 軽度ジャミング
    MODERATE = "MODERATE",     -- 中度ジャミング
    HEAVY = "HEAVY",           -- 重度ジャミング
    SATURATED = "SATURATED"    -- 飽和状態（無効化）
}

-- ============================================
-- ジャマー対策システム作成
-- ============================================
function SAM_ANTI_JAM.new(iadsNetwork)
    local self = setmetatable({}, SAM_ANTI_JAM)

    self.network = iadsNetwork
    self.jammers = {}              -- 検出されたジャマー
    self.jammerIdCounter = 0
    self.updateInterval = 3        -- 更新間隔（秒）
    self.isRunning = false

    -- ジャミング効果パラメータ
    self.jamEffects = {
        -- 検出距離の低下率（ジャミングレベルごと）
        detectionReduction = {
            [SAM_ANTI_JAM.JAM_STATUS.CLEAR] = 1.0,
            [SAM_ANTI_JAM.JAM_STATUS.LIGHT] = 0.8,
            [SAM_ANTI_JAM.JAM_STATUS.MODERATE] = 0.5,
            [SAM_ANTI_JAM.JAM_STATUS.HEAVY] = 0.2,
            [SAM_ANTI_JAM.JAM_STATUS.SATURATED] = 0.0
        },
        -- 追尾精度の低下率
        trackingAccuracy = {
            [SAM_ANTI_JAM.JAM_STATUS.CLEAR] = 1.0,
            [SAM_ANTI_JAM.JAM_STATUS.LIGHT] = 0.9,
            [SAM_ANTI_JAM.JAM_STATUS.MODERATE] = 0.6,
            [SAM_ANTI_JAM.JAM_STATUS.HEAVY] = 0.3,
            [SAM_ANTI_JAM.JAM_STATUS.SATURATED] = 0.0
        }
    }

    -- SAMタイプごとのECCM能力
    self.eccmCapabilities = {
        ["S-300"] = {
            freqHop = true,
            burnThrough = true,
            hoj = true,
            triangulation = true,
            eccmEffectiveness = 0.8
        },
        ["SA-11"] = {
            freqHop = true,
            burnThrough = true,
            hoj = true,
            triangulation = false,
            eccmEffectiveness = 0.6
        },
        ["SA-6"] = {
            freqHop = false,
            burnThrough = true,
            hoj = true,
            triangulation = false,
            eccmEffectiveness = 0.4
        },
        ["Patriot"] = {
            freqHop = true,
            burnThrough = true,
            hoj = true,
            triangulation = true,
            eccmEffectiveness = 0.85
        },
        ["Hawk"] = {
            freqHop = false,
            burnThrough = true,
            hoj = true,
            triangulation = false,
            eccmEffectiveness = 0.5
        },
        ["default"] = {
            freqHop = false,
            burnThrough = false,
            hoj = false,
            triangulation = false,
            eccmEffectiveness = 0.3
        }
    }

    -- SAMごとのジャミング状態
    self.samJamStatus = {}

    -- SAMごとの現在のECCMモード
    self.samEccmMode = {}

    return self
end

-- ============================================
-- 初期化
-- ============================================
function SAM_ANTI_JAM:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[AntiJam] System initialized")
    return self
end

-- ============================================
-- ジャマーを検出/登録
-- ============================================
function SAM_ANTI_JAM:detectJammer(position, options)
    if not position then return nil end

    options = options or {}
    self.jammerIdCounter = self.jammerIdCounter + 1
    local jammerId = "JAM-" .. string.format("%03d", self.jammerIdCounter)

    local jammer = {
        id = jammerId,
        position = SAM_UTILS.deepCopy(position),
        type = options.type or SAM_ANTI_JAM.JAMMER_TYPE.NOISE,
        power = options.power or 100,         -- ジャミングパワー（%）
        frequency = options.frequency or "X-band",
        effectiveRange = options.effectiveRange or 80000, -- 有効範囲（メートル）
        unitName = options.unitName,          -- DCSユニット名
        isActive = true,
        detectedTime = SAM_UTILS.getTime(),
        lastUpdate = SAM_UTILS.getTime()
    }

    self.jammers[jammerId] = jammer

    SAM_UTILS.debug("[AntiJam] Detected jammer: " .. jammerId ..
        " Type: " .. jammer.type .. " Power: " .. jammer.power)

    return jammer
end

-- ============================================
-- ジャマー位置を更新
-- ============================================
function SAM_ANTI_JAM:updateJammerPosition(jammerId, newPosition)
    local jammer = self.jammers[jammerId]
    if not jammer then return false end

    jammer.position = SAM_UTILS.deepCopy(newPosition)
    jammer.lastUpdate = SAM_UTILS.getTime()

    return true
end

-- ============================================
-- ジャマーを削除
-- ============================================
function SAM_ANTI_JAM:removeJammer(jammerId)
    if self.jammers[jammerId] then
        self.jammers[jammerId] = nil
        SAM_UTILS.debug("[AntiJam] Removed jammer: " .. jammerId)
        return true
    end
    return false
end

-- ============================================
-- SAMへのジャミング効果を計算
-- ============================================
function SAM_ANTI_JAM:calculateJamEffect(samGroupName)
    if not self.network then return SAM_ANTI_JAM.JAM_STATUS.CLEAR end

    local samSite = self.network.samSites[samGroupName]
    if not samSite or not samSite.position then
        return SAM_ANTI_JAM.JAM_STATUS.CLEAR
    end

    local totalJamPower = 0
    local samPos = samSite.position

    -- 全ジャマーからの影響を計算
    for jammerId, jammer in pairs(self.jammers) do
        if jammer.isActive then
            local distance = SAM_UTILS.getDistance2D(samPos, jammer.position)
            if distance and distance < jammer.effectiveRange then
                -- 距離による減衰を計算
                local distanceFactor = 1 - (distance / jammer.effectiveRange)
                local effectivePower = jammer.power * distanceFactor

                -- ジャマータイプによる補正
                if jammer.type == SAM_ANTI_JAM.JAMMER_TYPE.DRFM then
                    effectivePower = effectivePower * 1.5  -- DRFMは効果が高い
                elseif jammer.type == SAM_ANTI_JAM.JAMMER_TYPE.BARRAGE then
                    effectivePower = effectivePower * 1.2  -- バラージは広範囲
                end

                totalJamPower = totalJamPower + effectivePower
            end
        end
    end

    -- ECCM能力による軽減
    local eccmMode = self.samEccmMode[samGroupName]
    if eccmMode then
        local capability = self:getSamEccmCapability(samGroupName)
        local reduction = capability.eccmEffectiveness

        if eccmMode == SAM_ANTI_JAM.ECCM_MODE.FREQ_HOP and capability.freqHop then
            reduction = reduction * 1.3
        elseif eccmMode == SAM_ANTI_JAM.ECCM_MODE.BURN_THROUGH and capability.burnThrough then
            reduction = reduction * 1.2
        end

        totalJamPower = totalJamPower * (1 - math.min(reduction, 0.9))
    end

    -- ジャミングレベルを判定
    local jamStatus
    if totalJamPower < 10 then
        jamStatus = SAM_ANTI_JAM.JAM_STATUS.CLEAR
    elseif totalJamPower < 30 then
        jamStatus = SAM_ANTI_JAM.JAM_STATUS.LIGHT
    elseif totalJamPower < 60 then
        jamStatus = SAM_ANTI_JAM.JAM_STATUS.MODERATE
    elseif totalJamPower < 90 then
        jamStatus = SAM_ANTI_JAM.JAM_STATUS.HEAVY
    else
        jamStatus = SAM_ANTI_JAM.JAM_STATUS.SATURATED
    end

    self.samJamStatus[samGroupName] = jamStatus
    return jamStatus
end

-- ============================================
-- SAMのECCM能力を取得
-- ============================================
function SAM_ANTI_JAM:getSamEccmCapability(samGroupName)
    if not self.network then
        return self.eccmCapabilities["default"]
    end

    local samSite = self.network.samSites[samGroupName]
    if not samSite then
        return self.eccmCapabilities["default"]
    end

    -- SAMタイプからECCM能力を検索
    for _, unitInfo in ipairs(samSite.units or {}) do
        if unitInfo.unitType then
            for samType, capability in pairs(self.eccmCapabilities) do
                if samType ~= "default" and string.find(unitInfo.unitType, samType) then
                    return capability
                end
            end
        end
    end

    return self.eccmCapabilities["default"]
end

-- ============================================
-- ECCMモードを設定
-- ============================================
function SAM_ANTI_JAM:setEccmMode(samGroupName, mode)
    local capability = self:getSamEccmCapability(samGroupName)

    -- 能力チェック
    if mode == SAM_ANTI_JAM.ECCM_MODE.FREQ_HOP and not capability.freqHop then
        SAM_UTILS.debug("[AntiJam] " .. samGroupName .. " does not support frequency hopping")
        return false
    end
    if mode == SAM_ANTI_JAM.ECCM_MODE.TRIANGULATION and not capability.triangulation then
        SAM_UTILS.debug("[AntiJam] " .. samGroupName .. " does not support triangulation")
        return false
    end

    self.samEccmMode[samGroupName] = mode
    SAM_UTILS.debug("[AntiJam] " .. samGroupName .. " ECCM mode set to " .. mode)

    return true
end

-- ============================================
-- 自動ECCM選択
-- ============================================
function SAM_ANTI_JAM:autoSelectEccm(samGroupName)
    local jamStatus = self.samJamStatus[samGroupName] or SAM_ANTI_JAM.JAM_STATUS.CLEAR
    local capability = self:getSamEccmCapability(samGroupName)

    local selectedMode = SAM_ANTI_JAM.ECCM_MODE.PASSIVE

    if jamStatus == SAM_ANTI_JAM.JAM_STATUS.CLEAR then
        -- ジャミングなし - 通常モード
        selectedMode = nil
    elseif jamStatus == SAM_ANTI_JAM.JAM_STATUS.LIGHT then
        -- 軽度 - 周波数ホッピング優先
        if capability.freqHop then
            selectedMode = SAM_ANTI_JAM.ECCM_MODE.FREQ_HOP
        end
    elseif jamStatus == SAM_ANTI_JAM.JAM_STATUS.MODERATE then
        -- 中度 - バーンスルーまたはHOJ
        if capability.burnThrough then
            selectedMode = SAM_ANTI_JAM.ECCM_MODE.BURN_THROUGH
        elseif capability.hoj then
            selectedMode = SAM_ANTI_JAM.ECCM_MODE.HOJ
        end
    elseif jamStatus == SAM_ANTI_JAM.JAM_STATUS.HEAVY or
           jamStatus == SAM_ANTI_JAM.JAM_STATUS.SATURATED then
        -- 重度 - HOJまたはパッシブ
        if capability.hoj then
            selectedMode = SAM_ANTI_JAM.ECCM_MODE.HOJ
        else
            selectedMode = SAM_ANTI_JAM.ECCM_MODE.PASSIVE
        end
    end

    if selectedMode then
        self:setEccmMode(samGroupName, selectedMode)
    else
        self.samEccmMode[samGroupName] = nil
    end

    return selectedMode
end

-- ============================================
-- ホームオンジャム処理
-- ============================================
function SAM_ANTI_JAM:processHomeOnJam(samGroupName)
    local eccmMode = self.samEccmMode[samGroupName]
    if eccmMode ~= SAM_ANTI_JAM.ECCM_MODE.HOJ then
        return nil
    end

    if not self.network then return nil end

    local samSite = self.network.samSites[samGroupName]
    if not samSite or not samSite.position then return nil end

    -- 最も強いジャマーを特定
    local strongestJammer = nil
    local maxPower = 0

    for jammerId, jammer in pairs(self.jammers) do
        if jammer.isActive then
            local distance = SAM_UTILS.getDistance2D(samSite.position, jammer.position)
            if distance and distance < jammer.effectiveRange then
                local effectivePower = jammer.power * (1 - distance / jammer.effectiveRange)
                if effectivePower > maxPower then
                    maxPower = effectivePower
                    strongestJammer = jammer
                end
            end
        end
    end

    if strongestJammer then
        SAM_UTILS.debug("[AntiJam] " .. samGroupName .. " HOJ targeting " .. strongestJammer.id)
        return {
            jammerId = strongestJammer.id,
            position = strongestJammer.position,
            bearing = SAM_UTILS.getBearing(samSite.position, strongestJammer.position)
        }
    end

    return nil
end

-- ============================================
-- 三角測量によるジャマー位置特定
-- ============================================
function SAM_ANTI_JAM:triangulateJammer(jammerId)
    local jammer = self.jammers[jammerId]
    if not jammer or not self.network then return nil end

    -- 複数のSAMサイトからの方位を収集
    local bearings = {}

    for samGroupName, samSite in pairs(self.network.samSites) do
        local capability = self:getSamEccmCapability(samGroupName)
        if capability.triangulation and samSite.position then
            local distance = SAM_UTILS.getDistance2D(samSite.position, jammer.position)
            if distance and distance < jammer.effectiveRange then
                local bearing = SAM_UTILS.getBearing(samSite.position, jammer.position)
                if bearing then
                    table.insert(bearings, {
                        samName = samGroupName,
                        position = samSite.position,
                        bearing = bearing
                    })
                end
            end
        end
    end

    -- 2つ以上の方位があれば位置を計算
    if #bearings >= 2 then
        -- 簡易的な三角測量（最初の2つの交点）
        local b1 = bearings[1]
        local b2 = bearings[2]

        -- 実際のDCSでは三角測量の計算が必要だが、
        -- ここではジャマーの実際の位置を使用（シミュレーション簡略化）
        local estimatedPosition = {
            x = jammer.position.x + SAM_UTILS.random(-500, 500),
            y = jammer.position.y or 0,
            z = jammer.position.z + SAM_UTILS.random(-500, 500)
        }

        SAM_UTILS.debug("[AntiJam] Triangulated " .. jammerId .. " position")

        return {
            jammerId = jammerId,
            estimatedPosition = estimatedPosition,
            accuracy = 500,  -- メートル
            contributors = bearings
        }
    end

    return nil
end

-- ============================================
-- ジャミング下でのSAM性能を取得
-- ============================================
function SAM_ANTI_JAM:getJammedPerformance(samGroupName)
    local jamStatus = self.samJamStatus[samGroupName] or SAM_ANTI_JAM.JAM_STATUS.CLEAR

    return {
        jamStatus = jamStatus,
        detectionMultiplier = self.jamEffects.detectionReduction[jamStatus],
        trackingMultiplier = self.jamEffects.trackingAccuracy[jamStatus],
        eccmMode = self.samEccmMode[samGroupName]
    }
end

-- ============================================
-- 定期更新
-- ============================================
function SAM_ANTI_JAM:update()
    if not self.isRunning then return end

    -- 全SAMのジャミング状態を更新
    if self.network then
        for samGroupName, _ in pairs(self.network.samSites) do
            self:calculateJamEffect(samGroupName)
            self:autoSelectEccm(samGroupName)
        end
    end

    -- 古いジャマー情報をクリーンアップ（60秒以上更新なし）
    local currentTime = SAM_UTILS.getTime()
    local toRemove = {}

    for jammerId, jammer in pairs(self.jammers) do
        if currentTime - jammer.lastUpdate > 60 then
            table.insert(toRemove, jammerId)
        end
    end

    for _, jammerId in ipairs(toRemove) do
        self:removeJammer(jammerId)
    end

    -- 次の更新をスケジュール
    self:scheduleUpdate()
end

-- ============================================
-- 更新スケジュール
-- ============================================
function SAM_ANTI_JAM:scheduleUpdate()
    local antiJamSystem = self
    SAM_UTILS.scheduleFunction(function()
        antiJamSystem:update()
    end, nil, SAM_UTILS.getTime() + self.updateInterval)
end

-- ============================================
-- 停止
-- ============================================
function SAM_ANTI_JAM:stop()
    self.isRunning = false
end

-- ============================================
-- ステータス取得
-- ============================================
function SAM_ANTI_JAM:getStatus()
    local status = {
        totalJammers = 0,
        activeJammers = 0,
        jammers = {},
        samStatuses = {}
    }

    for jammerId, jammer in pairs(self.jammers) do
        status.totalJammers = status.totalJammers + 1
        if jammer.isActive then
            status.activeJammers = status.activeJammers + 1
        end

        table.insert(status.jammers, {
            id = jammerId,
            type = jammer.type,
            power = jammer.power,
            isActive = jammer.isActive
        })
    end

    for samGroupName, jamStatus in pairs(self.samJamStatus) do
        table.insert(status.samStatuses, {
            samName = samGroupName,
            jamStatus = jamStatus,
            eccmMode = self.samEccmMode[samGroupName]
        })
    end

    return status
end

-- ============================================
-- ステータス表示
-- ============================================
function SAM_ANTI_JAM:printStatus()
    local status = self:getStatus()

    local msg = "[Anti-Jam Status]\n"
    msg = msg .. string.format("Jammers: %d (Active: %d)\n",
        status.totalJammers, status.activeJammers)

    if #status.jammers > 0 then
        msg = msg .. "Detected Jammers:\n"
        for _, jammer in ipairs(status.jammers) do
            local activeStr = jammer.isActive and "ON" or "OFF"
            msg = msg .. string.format("  %s: %s Power:%d [%s]\n",
                jammer.id, jammer.type, jammer.power, activeStr)
        end
    end

    if #status.samStatuses > 0 then
        msg = msg .. "SAM Jam Status:\n"
        for _, samStatus in ipairs(status.samStatuses) do
            local eccmStr = samStatus.eccmMode and (" ECCM:" .. samStatus.eccmMode) or ""
            msg = msg .. string.format("  %s: %s%s\n",
                samStatus.samName, samStatus.jamStatus, eccmStr)
        end
    end

    SAM_UTILS.info(msg, 20)
end

return SAM_ANTI_JAM
