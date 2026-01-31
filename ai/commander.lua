--[[
    DCS IADS AI Commander
    AI防空コマンダー

    脅威レベルに応じた自動的なIADS管理を行うAIコマンダー

    機能:
    - 脅威レベルに応じたEMCON自動調整
    - SAMアクティベーション最適化
    - 防空優先度の動的変更
    - 戦術的意思決定
    - セクター管理と資源配分
    - 攻撃パターン分析

    依存: core/utils.lua, iads/network.lua, core/emcon.lua
]]

IADS_COMMANDER = {}
IADS_COMMANDER.__index = IADS_COMMANDER

-- ============================================
-- 防空態勢レベル（DEFCON相当）
-- ============================================
IADS_COMMANDER.DEFENSE_CONDITION = {
    PEACE = "PEACE",           -- 平時（最小警戒）
    ELEVATED = "ELEVATED",     -- 警戒態勢
    HIGH = "HIGH",             -- 高警戒態勢
    SEVERE = "SEVERE",         -- 厳戒態勢
    CRITICAL = "CRITICAL"      -- 最大警戒（全SAM稼働）
}

-- ============================================
-- 戦術モード
-- ============================================
IADS_COMMANDER.TACTICAL_MODE = {
    CONSERVATIVE = "CONSERVATIVE",   -- 保守的（SAM温存）
    BALANCED = "BALANCED",           -- バランス
    AGGRESSIVE = "AGGRESSIVE",       -- 積極的（早期交戦）
    AMBUSH = "AMBUSH"                -- 待ち伏せ（ダーク→奇襲）
}

-- ============================================
-- 優先度タイプ
-- ============================================
IADS_COMMANDER.PRIORITY_TYPE = {
    SEAD_THREAT = "SEAD_THREAT",     -- SEAD機優先
    STRIKE_PACKAGE = "STRIKE_PACKAGE", -- 攻撃パッケージ優先
    HIGH_VALUE = "HIGH_VALUE",       -- 高価値目標優先
    CLOSEST = "CLOSEST",             -- 最近接優先
    WEAKEST = "WEAKEST"              -- 最弱目標優先
}

-- ============================================
-- AIコマンダー作成
-- ============================================
function IADS_COMMANDER.new(iadsNetwork)
    local self = setmetatable({}, IADS_COMMANDER)

    self.network = iadsNetwork
    self.updateInterval = 5        -- 更新間隔（秒）
    self.isRunning = false

    -- 現在の状態
    self.defenseCondition = IADS_COMMANDER.DEFENSE_CONDITION.PEACE
    self.tacticalMode = IADS_COMMANDER.TACTICAL_MODE.BALANCED
    self.priorityType = IADS_COMMANDER.PRIORITY_TYPE.SEAD_THREAT

    -- 脅威評価
    self.threatAssessment = {
        overallLevel = 0,          -- 0-100
        seadThreat = 0,
        strikeThreat = 0,
        airSuperiorityThreat = 0,
        detectedThreats = 0,
        engagedThreats = 0
    }

    -- 防空リソース状態
    self.resourceStatus = {
        totalSams = 0,
        activeSams = 0,
        darkSams = 0,
        damagedSams = 0,
        ammoLow = 0,
        ewrCoverage = 0            -- 0-100%
    }

    -- 戦術設定
    self.tactics = {
        -- EMCON自動調整
        autoEmcon = true,
        emconByDefcon = {
            [IADS_COMMANDER.DEFENSE_CONDITION.PEACE] = "ALPHA",
            [IADS_COMMANDER.DEFENSE_CONDITION.ELEVATED] = "BRAVO",
            [IADS_COMMANDER.DEFENSE_CONDITION.HIGH] = "CHARLIE",
            [IADS_COMMANDER.DEFENSE_CONDITION.SEVERE] = "DELTA",
            [IADS_COMMANDER.DEFENSE_CONDITION.CRITICAL] = "ECHO"
        },

        -- SAMアクティベーション閾値
        activationThreshold = {
            [IADS_COMMANDER.DEFENSE_CONDITION.PEACE] = 80,      -- 脅威80以上で起動
            [IADS_COMMANDER.DEFENSE_CONDITION.ELEVATED] = 60,
            [IADS_COMMANDER.DEFENSE_CONDITION.HIGH] = 40,
            [IADS_COMMANDER.DEFENSE_CONDITION.SEVERE] = 20,
            [IADS_COMMANDER.DEFENSE_CONDITION.CRITICAL] = 0     -- 常時起動
        },

        -- 待ち伏せ設定
        ambushRange = 0.7,         -- 射程の70%で起動
        ambushMinThreats = 2,      -- 最低2機で待ち伏せ解除

        -- SAM温存設定
        conserveAmmoThreshold = 0.3,  -- 残弾30%以下で温存
        conserveHealthThreshold = 0.5 -- HP50%以下で温存
    }

    -- 戦闘統計
    self.battleStats = {
        commandsIssued = 0,
        samActivations = 0,
        samDeactivations = 0,
        defconChanges = 0,
        tacticalDecisions = {}
    }

    -- 攻撃パターン分析
    self.patternAnalysis = {
        attackDirections = {},     -- 攻撃方向の統計
        attackTimes = {},          -- 攻撃時間帯の統計
        preferredTargets = {},     -- 狙われやすいターゲット
        seadTactics = {}           -- SEAD戦術の分析
    }

    -- コールバック
    self.callbacks = {
        onDefconChange = nil,
        onTacticalDecision = nil,
        onSamCommand = nil
    }

    return self
end

-- ============================================
-- 初期化
-- ============================================
function IADS_COMMANDER:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end
    if options.tacticalMode then
        self.tacticalMode = options.tacticalMode
    end
    if options.priorityType then
        self.priorityType = options.priorityType
    end
    if options.defenseCondition then
        self.defenseCondition = options.defenseCondition
    end

    -- 戦術設定のオーバーライド
    if options.tactics then
        for k, v in pairs(options.tactics) do
            self.tactics[k] = v
        end
    end

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[Commander] AI Commander initialized")
    return self
end

-- ============================================
-- 脅威評価を更新
-- ============================================
function IADS_COMMANDER:updateThreatAssessment()
    if not self.network then return end

    local assessment = {
        overallLevel = 0,
        seadThreat = 0,
        strikeThreat = 0,
        airSuperiorityThreat = 0,
        detectedThreats = 0,
        engagedThreats = 0
    }

    -- ネットワークから脅威情報を収集
    if self.network.threats then
        for threatId, threat in pairs(self.network.threats) do
            assessment.detectedThreats = assessment.detectedThreats + 1

            -- 脅威タイプによる分類
            local threatType = threat.type or "UNKNOWN"
            local threatLevel = threat.level or 50

            if threatType == "SEAD" or threatType == "ARM_CARRIER" then
                assessment.seadThreat = assessment.seadThreat + threatLevel
            elseif threatType == "STRIKE" or threatType == "BOMBER" then
                assessment.strikeThreat = assessment.strikeThreat + threatLevel
            elseif threatType == "FIGHTER" or threatType == "CAP" then
                assessment.airSuperiorityThreat = assessment.airSuperiorityThreat + threatLevel
            end

            if threat.engaged then
                assessment.engagedThreats = assessment.engagedThreats + 1
            end
        end
    end

    -- 総合脅威レベルを計算（SEAD脅威を重視）
    assessment.overallLevel = math.min(100,
        assessment.seadThreat * 1.5 +
        assessment.strikeThreat * 1.0 +
        assessment.airSuperiorityThreat * 0.5
    )

    self.threatAssessment = assessment
    return assessment
end

-- ============================================
-- リソース状態を更新
-- ============================================
function IADS_COMMANDER:updateResourceStatus()
    if not self.network then return end

    local status = {
        totalSams = 0,
        activeSams = 0,
        darkSams = 0,
        damagedSams = 0,
        ammoLow = 0,
        ewrCoverage = 0
    }

    -- SAM状態をカウント
    for samName, samSite in pairs(self.network.samSites or {}) do
        status.totalSams = status.totalSams + 1

        local samState = samSite.state or "UNKNOWN"
        if samState == "GREEN" or samState == "RED" then
            status.activeSams = status.activeSams + 1
        else
            status.darkSams = status.darkSams + 1
        end

        -- 弾薬状態チェック（IADS_SYSTEMS.ammoがあれば）
        if IADS_SYSTEMS and IADS_SYSTEMS.ammo then
            local ammoStatus = IADS_SYSTEMS.ammo:getGroupStatus(samName)
            if ammoStatus and ammoStatus.overallStatus then
                if ammoStatus.overallStatus == "LOW" or
                   ammoStatus.overallStatus == "CRITICAL" or
                   ammoStatus.overallStatus == "EMPTY" then
                    status.ammoLow = status.ammoLow + 1
                end
            end
        end

        -- 損傷チェック（IADS_SYSTEMS.maintenanceがあれば）
        if IADS_SYSTEMS and IADS_SYSTEMS.maintenance then
            local maintStatus = IADS_SYSTEMS.maintenance.siteStatus[samName]
            if maintStatus and maintStatus.health < 100 then
                status.damagedSams = status.damagedSams + 1
            end
        end
    end

    -- EWRカバレッジ計算（簡易版）
    local ewrCount = 0
    for _, _ in pairs(self.network.ewrSites or {}) do
        ewrCount = ewrCount + 1
    end
    status.ewrCoverage = math.min(100, ewrCount * 25)  -- EWR1基あたり25%

    self.resourceStatus = status
    return status
end

-- ============================================
-- 防空態勢を自動判定
-- ============================================
function IADS_COMMANDER:evaluateDefenseCondition()
    local threat = self.threatAssessment.overallLevel
    local newCondition = self.defenseCondition

    if threat >= 80 then
        newCondition = IADS_COMMANDER.DEFENSE_CONDITION.CRITICAL
    elseif threat >= 60 then
        newCondition = IADS_COMMANDER.DEFENSE_CONDITION.SEVERE
    elseif threat >= 40 then
        newCondition = IADS_COMMANDER.DEFENSE_CONDITION.HIGH
    elseif threat >= 20 then
        newCondition = IADS_COMMANDER.DEFENSE_CONDITION.ELEVATED
    else
        newCondition = IADS_COMMANDER.DEFENSE_CONDITION.PEACE
    end

    if newCondition ~= self.defenseCondition then
        self:setDefenseCondition(newCondition)
    end

    return newCondition
end

-- ============================================
-- 防空態勢を設定
-- ============================================
function IADS_COMMANDER:setDefenseCondition(condition)
    local oldCondition = self.defenseCondition
    self.defenseCondition = condition

    self.battleStats.defconChanges = self.battleStats.defconChanges + 1

    SAM_UTILS.info("[Commander] Defense Condition: " .. oldCondition .. " -> " .. condition)

    -- EMCON自動調整
    if self.tactics.autoEmcon and IADS_SYSTEMS and IADS_SYSTEMS.emcon then
        local emconLevel = self.tactics.emconByDefcon[condition]
        if emconLevel then
            IADS_SYSTEMS.emcon:setLevel(SAM_EMCON.LEVEL[emconLevel])
        end
    end

    -- コールバック
    if self.callbacks.onDefconChange then
        self.callbacks.onDefconChange(oldCondition, condition)
    end

    return condition
end

-- ============================================
-- 戦術的意思決定
-- ============================================
function IADS_COMMANDER:makeTacticalDecisions()
    if not self.network then return end

    local decisions = {}

    -- 戦術モードに応じた判断
    if self.tacticalMode == IADS_COMMANDER.TACTICAL_MODE.AMBUSH then
        decisions = self:ambushTactics()
    elseif self.tacticalMode == IADS_COMMANDER.TACTICAL_MODE.CONSERVATIVE then
        decisions = self:conservativeTactics()
    elseif self.tacticalMode == IADS_COMMANDER.TACTICAL_MODE.AGGRESSIVE then
        decisions = self:aggressiveTactics()
    else
        decisions = self:balancedTactics()
    end

    -- 決定を実行
    for _, decision in ipairs(decisions) do
        self:executeDecision(decision)
    end

    return decisions
end

-- ============================================
-- 待ち伏せ戦術
-- ============================================
function IADS_COMMANDER:ambushTactics()
    local decisions = {}

    -- 脅威が閾値を超えるまでダーク維持
    if self.threatAssessment.detectedThreats < self.tactics.ambushMinThreats then
        -- 全SAMをダークに
        for samName, samSite in pairs(self.network.samSites) do
            if samSite.state ~= "DARK" then
                table.insert(decisions, {
                    type = "DEACTIVATE",
                    target = samName,
                    reason = "AMBUSH_WAIT"
                })
            end
        end
    else
        -- 脅威が射程内に入ったら一斉起動
        for samName, samSite in pairs(self.network.samSites) do
            if self:hasThreatInRange(samName, self.tactics.ambushRange) then
                table.insert(decisions, {
                    type = "ACTIVATE",
                    target = samName,
                    reason = "AMBUSH_SPRING"
                })
            end
        end
    end

    return decisions
end

-- ============================================
-- 保守的戦術
-- ============================================
function IADS_COMMANDER:conservativeTactics()
    local decisions = {}

    for samName, samSite in pairs(self.network.samSites) do
        local shouldConserve = false
        local reason = ""

        -- 弾薬チェック
        if IADS_SYSTEMS and IADS_SYSTEMS.ammo then
            local ammoStatus = IADS_SYSTEMS.ammo:getGroupStatus(samName)
            if ammoStatus and ammoStatus.ammoPercent then
                if ammoStatus.ammoPercent < self.tactics.conserveAmmoThreshold * 100 then
                    shouldConserve = true
                    reason = "LOW_AMMO"
                end
            end
        end

        -- 損傷チェック
        if IADS_SYSTEMS and IADS_SYSTEMS.maintenance then
            local maintStatus = IADS_SYSTEMS.maintenance.siteStatus[samName]
            if maintStatus and maintStatus.health then
                if maintStatus.health < self.tactics.conserveHealthThreshold * 100 then
                    shouldConserve = true
                    reason = "DAMAGED"
                end
            end
        end

        if shouldConserve and samSite.state ~= "DARK" then
            table.insert(decisions, {
                type = "DEACTIVATE",
                target = samName,
                reason = "CONSERVE_" .. reason
            })
        end
    end

    return decisions
end

-- ============================================
-- 積極的戦術
-- ============================================
function IADS_COMMANDER:aggressiveTactics()
    local decisions = {}

    -- 脅威があれば積極的に全SAMを起動
    if self.threatAssessment.detectedThreats > 0 then
        for samName, samSite in pairs(self.network.samSites) do
            if samSite.state == "DARK" then
                table.insert(decisions, {
                    type = "ACTIVATE",
                    target = samName,
                    reason = "AGGRESSIVE_ENGAGE"
                })
            end
        end
    end

    return decisions
end

-- ============================================
-- バランス戦術
-- ============================================
function IADS_COMMANDER:balancedTactics()
    local decisions = {}
    local threshold = self.tactics.activationThreshold[self.defenseCondition] or 50

    for samName, samSite in pairs(self.network.samSites) do
        local samThreatLevel = self:getSamThreatLevel(samName)

        if samThreatLevel >= threshold then
            if samSite.state == "DARK" then
                table.insert(decisions, {
                    type = "ACTIVATE",
                    target = samName,
                    reason = "THREAT_THRESHOLD"
                })
            end
        else
            -- 脅威レベルが閾値以下でもSEAD脅威がある場合は維持
            if not self:isUnderSeadThreat(samName) and samSite.state ~= "DARK" then
                table.insert(decisions, {
                    type = "DEACTIVATE",
                    target = samName,
                    reason = "NO_THREAT"
                })
            end
        end
    end

    return decisions
end

-- ============================================
-- SAMの脅威レベルを取得
-- ============================================
function IADS_COMMANDER:getSamThreatLevel(samName)
    if not self.network then return 0 end

    local samSite = self.network.samSites[samName]
    if not samSite or not samSite.position then return 0 end

    local totalThreat = 0

    for threatId, threat in pairs(self.network.threats or {}) do
        if threat.position then
            local distance = SAM_UTILS.getDistance2D(samSite.position, threat.position)
            local range = samSite.maxRange or 80000

            if distance and distance < range * 1.5 then
                local threatLevel = threat.level or 50
                local distanceFactor = 1 - (distance / (range * 1.5))
                totalThreat = totalThreat + (threatLevel * distanceFactor)
            end
        end
    end

    return math.min(100, totalThreat)
end

-- ============================================
-- SAMがSEAD脅威下にあるか
-- ============================================
function IADS_COMMANDER:isUnderSeadThreat(samName)
    if not self.network then return false end

    local samSite = self.network.samSites[samName]
    if not samSite or not samSite.position then return false end

    for threatId, threat in pairs(self.network.threats or {}) do
        if threat.type == "SEAD" or threat.type == "ARM_CARRIER" then
            if threat.position then
                local distance = SAM_UTILS.getDistance2D(samSite.position, threat.position)
                if distance and distance < 100000 then  -- 100km以内
                    return true
                end
            end
        end
    end

    return false
end

-- ============================================
-- 射程内に脅威があるか
-- ============================================
function IADS_COMMANDER:hasThreatInRange(samName, rangeFactor)
    if not self.network then return false end

    local samSite = self.network.samSites[samName]
    if not samSite or not samSite.position then return false end

    local range = (samSite.maxRange or 80000) * (rangeFactor or 1.0)

    for threatId, threat in pairs(self.network.threats or {}) do
        if threat.position then
            local distance = SAM_UTILS.getDistance2D(samSite.position, threat.position)
            if distance and distance < range then
                return true
            end
        end
    end

    return false
end

-- ============================================
-- 決定を実行
-- ============================================
function IADS_COMMANDER:executeDecision(decision)
    if not decision or not decision.type or not decision.target then
        return false
    end

    self.battleStats.commandsIssued = self.battleStats.commandsIssued + 1

    if decision.type == "ACTIVATE" then
        if self.network then
            self.network:setSamState(decision.target, IADS_NETWORK.SAM_STATE.GREEN)
            self.battleStats.samActivations = self.battleStats.samActivations + 1
        end
    elseif decision.type == "DEACTIVATE" then
        if self.network then
            self.network:setSamState(decision.target, IADS_NETWORK.SAM_STATE.DARK)
            self.battleStats.samDeactivations = self.battleStats.samDeactivations + 1
        end
    end

    -- 決定を記録
    table.insert(self.battleStats.tacticalDecisions, {
        time = SAM_UTILS.getTime(),
        decision = decision
    })

    -- コールバック
    if self.callbacks.onTacticalDecision then
        self.callbacks.onTacticalDecision(decision)
    end

    SAM_UTILS.debug("[Commander] Decision: " .. decision.type ..
        " " .. decision.target .. " (" .. (decision.reason or "N/A") .. ")")

    return true
end

-- ============================================
-- 戦術モードを設定
-- ============================================
function IADS_COMMANDER:setTacticalMode(mode)
    self.tacticalMode = mode
    SAM_UTILS.info("[Commander] Tactical mode set to: " .. mode)
    return mode
end

-- ============================================
-- 優先度タイプを設定
-- ============================================
function IADS_COMMANDER:setPriorityType(priorityType)
    self.priorityType = priorityType
    SAM_UTILS.info("[Commander] Priority type set to: " .. priorityType)
    return priorityType
end

-- ============================================
-- 攻撃パターンを分析
-- ============================================
function IADS_COMMANDER:analyzeAttackPattern(threat)
    if not threat or not threat.position then return end

    -- 攻撃方向を記録
    local bearing = threat.heading or 0
    local directionBin = math.floor(bearing / 45) * 45  -- 45度単位
    self.patternAnalysis.attackDirections[directionBin] =
        (self.patternAnalysis.attackDirections[directionBin] or 0) + 1

    -- 攻撃時間を記録
    local hour = math.floor((SAM_UTILS.getTime() % 86400) / 3600)
    self.patternAnalysis.attackTimes[hour] =
        (self.patternAnalysis.attackTimes[hour] or 0) + 1
end

-- ============================================
-- 予測される攻撃方向を取得
-- ============================================
function IADS_COMMANDER:getPredictedAttackDirection()
    local maxCount = 0
    local likelyDirection = nil

    for direction, count in pairs(self.patternAnalysis.attackDirections) do
        if count > maxCount then
            maxCount = count
            likelyDirection = direction
        end
    end

    return likelyDirection
end

-- ============================================
-- コールバックを設定
-- ============================================
function IADS_COMMANDER:setCallback(eventType, handler)
    if self.callbacks[eventType] ~= nil then
        self.callbacks[eventType] = handler
        return true
    end
    return false
end

-- ============================================
-- 定期更新
-- ============================================
function IADS_COMMANDER:update()
    if not self.isRunning then return end

    -- 状態更新
    self:updateThreatAssessment()
    self:updateResourceStatus()

    -- 防空態勢評価
    self:evaluateDefenseCondition()

    -- 戦術的意思決定
    self:makeTacticalDecisions()

    -- 次の更新をスケジュール
    self:scheduleUpdate()
end

-- ============================================
-- 更新スケジュール
-- ============================================
function IADS_COMMANDER:scheduleUpdate()
    local commander = self
    SAM_UTILS.scheduleFunction(function()
        commander:update()
    end, nil, SAM_UTILS.getTime() + self.updateInterval)
end

-- ============================================
-- 停止
-- ============================================
function IADS_COMMANDER:stop()
    self.isRunning = false
end

-- ============================================
-- ステータス取得
-- ============================================
function IADS_COMMANDER:getStatus()
    return {
        defenseCondition = self.defenseCondition,
        tacticalMode = self.tacticalMode,
        priorityType = self.priorityType,
        threatAssessment = SAM_UTILS.deepCopy(self.threatAssessment),
        resourceStatus = SAM_UTILS.deepCopy(self.resourceStatus),
        battleStats = SAM_UTILS.deepCopy(self.battleStats)
    }
end

-- ============================================
-- ステータス表示
-- ============================================
function IADS_COMMANDER:printStatus()
    local status = self:getStatus()

    local msg = "[AI Commander Status]\n"
    msg = msg .. string.format("DEFCON: %s | Mode: %s | Priority: %s\n",
        status.defenseCondition, status.tacticalMode, status.priorityType)

    msg = msg .. "\n[Threat Assessment]\n"
    msg = msg .. string.format("Overall: %d%% | SEAD: %d | Strike: %d | A/A: %d\n",
        status.threatAssessment.overallLevel,
        status.threatAssessment.seadThreat,
        status.threatAssessment.strikeThreat,
        status.threatAssessment.airSuperiorityThreat)
    msg = msg .. string.format("Detected: %d | Engaged: %d\n",
        status.threatAssessment.detectedThreats,
        status.threatAssessment.engagedThreats)

    msg = msg .. "\n[Resources]\n"
    msg = msg .. string.format("SAMs: %d (Active: %d | Dark: %d | Damaged: %d)\n",
        status.resourceStatus.totalSams,
        status.resourceStatus.activeSams,
        status.resourceStatus.darkSams,
        status.resourceStatus.damagedSams)
    msg = msg .. string.format("Ammo Low: %d | EWR Coverage: %d%%\n",
        status.resourceStatus.ammoLow,
        status.resourceStatus.ewrCoverage)

    msg = msg .. "\n[Battle Stats]\n"
    msg = msg .. string.format("Commands: %d | Activations: %d | Deactivations: %d\n",
        status.battleStats.commandsIssued,
        status.battleStats.samActivations,
        status.battleStats.samDeactivations)
    msg = msg .. string.format("DEFCON Changes: %d\n",
        status.battleStats.defconChanges)

    SAM_UTILS.info(msg, 30)
end

return IADS_COMMANDER
