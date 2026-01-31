--[[
    DCS IADS Flight Path Predictor
    航路予測システム

    脅威の現在位置と速度から将来の位置を予測し、
    予測経路上のSAMを事前にアクティブ化する

    機能:
    - 線形航路予測（現在の速度ベクトルに基づく）
    - 経路上のSAM交戦範囲との交差判定
    - 予測に基づく事前アクティブ化
    - 予測精度のトラッキング
    - 目標タイプ別の予測モデル

    依存: core/utils.lua, iads/network.lua, iads/threat.lua
]]

IADS_PREDICTOR = {}
IADS_PREDICTOR.__index = IADS_PREDICTOR

-- ============================================
-- 予測モード
-- ============================================
IADS_PREDICTOR.MODE = {
    LINEAR = "LINEAR",           -- 線形予測（直線）
    CURVED = "CURVED",           -- 曲線予測（旋回考慮）
    WAYPOINT = "WAYPOINT"        -- ウェイポイント予測（知的推測）
}

-- ============================================
-- 予測信頼度
-- ============================================
IADS_PREDICTOR.CONFIDENCE = {
    HIGH = "HIGH",         -- 高信頼度
    MEDIUM = "MEDIUM",     -- 中信頼度
    LOW = "LOW",           -- 低信頼度
    UNRELIABLE = "UNRELIABLE"  -- 信頼性なし
}

-- ============================================
-- 航路予測システム作成
-- ============================================
function IADS_PREDICTOR.new(iadsNetwork)
    local self = setmetatable({}, IADS_PREDICTOR)

    self.network = iadsNetwork
    self.predictions = {}            -- 航路予測データ
    self.updateInterval = 3          -- 更新間隔（秒）
    self.predictionTime = 120        -- 予測時間（秒）
    self.predictionSteps = 12        -- 予測ステップ数
    self.preActivationTime = 30      -- 事前アクティブ化時間（秒）
    self.autoPreActivate = true      -- 自動事前アクティブ化
    self.mode = IADS_PREDICTOR.MODE.LINEAR
    self.isRunning = false

    -- 予測精度追跡
    self.predictionAccuracy = {}

    return self
end

-- ============================================
-- 初期化
-- ============================================
function IADS_PREDICTOR:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end
    if options.predictionTime then
        self.predictionTime = options.predictionTime
    end
    if options.predictionSteps then
        self.predictionSteps = options.predictionSteps
    end
    if options.preActivationTime then
        self.preActivationTime = options.preActivationTime
    end
    if options.autoPreActivate ~= nil then
        self.autoPreActivate = options.autoPreActivate
    end
    if options.mode then
        self.mode = options.mode
    end

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[Predictor] System initialized")
    return self
end

-- ============================================
-- 脅威の航路を予測
-- ============================================
function IADS_PREDICTOR:predictPath(threat)
    if not threat or not threat.position or not threat.velocity then
        return nil
    end

    local currentTime = SAM_UTILS.getTime()
    local stepDuration = self.predictionTime / self.predictionSteps
    local path = {
        threatId = threat.id or threat.unitName,
        startPosition = SAM_UTILS.deepCopy(threat.position),
        startVelocity = SAM_UTILS.deepCopy(threat.velocity),
        startTime = currentTime,
        points = {},
        confidence = self:calculateConfidence(threat),
        samIntersections = {}
    }

    -- 各ステップの位置を予測
    for i = 1, self.predictionSteps do
        local t = i * stepDuration
        local predictedPos = self:predictPosition(threat, t)

        table.insert(path.points, {
            time = currentTime + t,
            timeOffset = t,
            position = predictedPos,
            altitude = predictedPos.y
        })
    end

    -- SAMとの交差を計算
    path.samIntersections = self:calculateSamIntersections(path)

    return path
end

-- ============================================
-- 位置を予測
-- ============================================
function IADS_PREDICTOR:predictPosition(threat, timeOffset)
    local pos = threat.position
    local vel = threat.velocity

    if self.mode == IADS_PREDICTOR.MODE.LINEAR then
        -- 線形予測
        return {
            x = pos.x + vel.x * timeOffset,
            y = pos.y + vel.y * timeOffset,
            z = pos.z + vel.z * timeOffset
        }
    elseif self.mode == IADS_PREDICTOR.MODE.CURVED then
        -- 曲線予測（簡易的な旋回予測）
        -- 過去の位置履歴があれば旋回率を計算
        local turnRate = self:estimateTurnRate(threat)

        if turnRate and math.abs(turnRate) > 0.01 then
            -- 旋回を考慮した予測
            local heading = math.atan2(vel.z, vel.x)
            local speed = math.sqrt(vel.x^2 + vel.z^2)
            local newHeading = heading + turnRate * timeOffset

            return {
                x = pos.x + speed * math.cos(newHeading) * timeOffset,
                y = pos.y + vel.y * timeOffset,
                z = pos.z + speed * math.sin(newHeading) * timeOffset
            }
        else
            -- 旋回なしなら線形
            return {
                x = pos.x + vel.x * timeOffset,
                y = pos.y + vel.y * timeOffset,
                z = pos.z + vel.z * timeOffset
            }
        end
    else
        -- デフォルトは線形
        return {
            x = pos.x + vel.x * timeOffset,
            y = pos.y + vel.y * timeOffset,
            z = pos.z + vel.z * timeOffset
        }
    end
end

-- ============================================
-- 旋回率を推定
-- ============================================
function IADS_PREDICTOR:estimateTurnRate(threat)
    -- 過去の予測と比較して旋回率を推定
    local prevPrediction = self.predictions[threat.id or threat.unitName]
    if not prevPrediction then return 0 end

    -- 前回の予測と実際の位置の差から旋回を推定
    local timeDiff = SAM_UTILS.getTime() - prevPrediction.startTime
    if timeDiff < 1 then return 0 end

    local prevHeading = math.atan2(prevPrediction.startVelocity.z, prevPrediction.startVelocity.x)
    local currentHeading = math.atan2(threat.velocity.z, threat.velocity.x)

    local headingDiff = currentHeading - prevHeading
    -- -π〜πの範囲に正規化
    while headingDiff > math.pi do headingDiff = headingDiff - 2 * math.pi end
    while headingDiff < -math.pi do headingDiff = headingDiff + 2 * math.pi end

    return headingDiff / timeDiff
end

-- ============================================
-- 予測信頼度を計算
-- ============================================
function IADS_PREDICTOR:calculateConfidence(threat)
    -- 速度に基づく基本信頼度
    local speed = 0
    if threat.velocity then
        speed = math.sqrt(
            threat.velocity.x^2 +
            threat.velocity.y^2 +
            threat.velocity.z^2
        )
    end

    -- 低速や停止中は予測困難
    if speed < 50 then
        return IADS_PREDICTOR.CONFIDENCE.LOW
    end

    -- カテゴリに基づく調整
    if threat.category == "FIGHTER" then
        -- 戦闘機は機動的なので予測困難
        return IADS_PREDICTOR.CONFIDENCE.MEDIUM
    elseif threat.category == "BOMBER" or threat.category == "ATTACK" then
        -- 爆撃機/攻撃機は比較的予測しやすい
        return IADS_PREDICTOR.CONFIDENCE.HIGH
    elseif threat.category == "CRUISE_MISSILE" then
        -- 巡航ミサイルは直線的
        return IADS_PREDICTOR.CONFIDENCE.HIGH
    end

    -- 過去の予測精度に基づく調整
    local accuracyRecord = self.predictionAccuracy[threat.id or threat.unitName]
    if accuracyRecord and accuracyRecord.samples > 5 then
        if accuracyRecord.averageError < 1000 then
            return IADS_PREDICTOR.CONFIDENCE.HIGH
        elseif accuracyRecord.averageError < 5000 then
            return IADS_PREDICTOR.CONFIDENCE.MEDIUM
        else
            return IADS_PREDICTOR.CONFIDENCE.LOW
        end
    end

    return IADS_PREDICTOR.CONFIDENCE.MEDIUM
end

-- ============================================
-- SAMとの交差を計算
-- ============================================
function IADS_PREDICTOR:calculateSamIntersections(path)
    if not self.network then return {} end

    local intersections = {}

    for samName, samSite in pairs(self.network.samSites) do
        if samSite.position then
            local engagementRange = samSite.engagementRange or 50000

            -- 各予測ポイントとSAMの距離をチェック
            for i, point in ipairs(path.points) do
                local distance = SAM_UTILS.getDistance2D(point.position, samSite.position)

                if distance and distance <= engagementRange then
                    -- 交差を記録
                    if not intersections[samName] then
                        intersections[samName] = {
                            samName = samName,
                            samSite = samSite,
                            entryTime = point.time,
                            entryTimeOffset = point.timeOffset,
                            entryDistance = distance,
                            exitTime = point.time,
                            exitTimeOffset = point.timeOffset,
                            points = {}
                        }
                    end

                    -- 滞在時間を更新
                    intersections[samName].exitTime = point.time
                    intersections[samName].exitTimeOffset = point.timeOffset

                    table.insert(intersections[samName].points, {
                        time = point.time,
                        timeOffset = point.timeOffset,
                        distance = distance
                    })
                end
            end
        end
    end

    return intersections
end

-- ============================================
-- 事前アクティブ化が必要なSAMを取得
-- ============================================
function IADS_PREDICTOR:getSamsToPreActivate()
    local currentTime = SAM_UTILS.getTime()
    local samsToActivate = {}

    for threatId, prediction in pairs(self.predictions) do
        -- 信頼度が低すぎる予測は無視
        if prediction.confidence == IADS_PREDICTOR.CONFIDENCE.UNRELIABLE then
            goto continue
        end

        for samName, intersection in pairs(prediction.samIntersections) do
            local timeToEntry = intersection.entryTime - currentTime

            -- 事前アクティブ化時間内かチェック
            if timeToEntry > 0 and timeToEntry <= self.preActivationTime then
                if not samsToActivate[samName] then
                    samsToActivate[samName] = {
                        samName = samName,
                        threats = {},
                        earliestEntry = timeToEntry
                    }
                end

                table.insert(samsToActivate[samName].threats, {
                    threatId = threatId,
                    timeToEntry = timeToEntry,
                    confidence = prediction.confidence
                })

                if timeToEntry < samsToActivate[samName].earliestEntry then
                    samsToActivate[samName].earliestEntry = timeToEntry
                end
            end
        end

        ::continue::
    end

    return samsToActivate
end

-- ============================================
-- 自動事前アクティブ化を実行
-- ============================================
function IADS_PREDICTOR:executePreActivation()
    if not self.autoPreActivate or not self.network then return end

    local samsToActivate = self:getSamsToPreActivate()

    for samName, activationInfo in pairs(samsToActivate) do
        local samSite = self.network.samSites[samName]

        -- ダーク状態のSAMのみアクティブ化
        if samSite and samSite.state == IADS_NETWORK.SAM_STATE.DARK then
            self.network:activateSam(samName)

            SAM_UTILS.debug(string.format(
                "[Predictor] Pre-activating %s (threat in %.0fs)",
                samName, activationInfo.earliestEntry))
        end
    end
end

-- ============================================
-- 予測精度を記録
-- ============================================
function IADS_PREDICTOR:recordPredictionAccuracy(threatId, predictedPos, actualPos)
    if not predictedPos or not actualPos then return end

    local error = SAM_UTILS.getDistance(predictedPos, actualPos)

    if not self.predictionAccuracy[threatId] then
        self.predictionAccuracy[threatId] = {
            samples = 0,
            totalError = 0,
            averageError = 0
        }
    end

    local record = self.predictionAccuracy[threatId]
    record.samples = record.samples + 1
    record.totalError = record.totalError + error
    record.averageError = record.totalError / record.samples
end

-- ============================================
-- 予測精度を検証
-- ============================================
function IADS_PREDICTOR:validatePredictions()
    if not self.network then return end

    local currentTime = SAM_UTILS.getTime()

    for threatId, prediction in pairs(self.predictions) do
        -- 対応する脅威を取得
        local threat = self.network.threats and self.network.threats[threatId]

        if threat and threat.position then
            -- 現在時刻に対応する予測位置を探す
            for _, point in ipairs(prediction.points) do
                if math.abs(point.time - currentTime) < self.updateInterval then
                    self:recordPredictionAccuracy(threatId, point.position, threat.position)
                    break
                end
            end
        end
    end
end

-- ============================================
-- 定期更新
-- ============================================
function IADS_PREDICTOR:update()
    if not self.isRunning then return end

    -- 予測精度を検証
    self:validatePredictions()

    -- 脅威の航路を予測
    if self.network and self.network.threats then
        for threatId, threat in pairs(self.network.threats) do
            if not threat.isLost then
                local prediction = self:predictPath(threat)
                if prediction then
                    self.predictions[threatId] = prediction
                end
            else
                -- ロストした脅威の予測を削除
                self.predictions[threatId] = nil
            end
        end
    end

    -- 事前アクティブ化を実行
    self:executePreActivation()

    -- 次の更新をスケジュール
    self:scheduleUpdate()
end

-- ============================================
-- 更新スケジュール
-- ============================================
function IADS_PREDICTOR:scheduleUpdate()
    local predictor = self
    SAM_UTILS.scheduleFunction(function()
        predictor:update()
    end, nil, SAM_UTILS.getTime() + self.updateInterval)
end

-- ============================================
-- 停止
-- ============================================
function IADS_PREDICTOR:stop()
    self.isRunning = false
end

-- ============================================
-- 特定脅威の予測を取得
-- ============================================
function IADS_PREDICTOR:getPrediction(threatId)
    return self.predictions[threatId]
end

-- ============================================
-- すべての予測を取得
-- ============================================
function IADS_PREDICTOR:getAllPredictions()
    return self.predictions
end

-- ============================================
-- ステータス取得
-- ============================================
function IADS_PREDICTOR:getStatus()
    local status = {
        mode = self.mode,
        predictionCount = 0,
        highConfidence = 0,
        mediumConfidence = 0,
        lowConfidence = 0,
        totalIntersections = 0,
        preActivationCandidates = 0,
        predictions = {}
    }

    for threatId, prediction in pairs(self.predictions) do
        status.predictionCount = status.predictionCount + 1

        if prediction.confidence == IADS_PREDICTOR.CONFIDENCE.HIGH then
            status.highConfidence = status.highConfidence + 1
        elseif prediction.confidence == IADS_PREDICTOR.CONFIDENCE.MEDIUM then
            status.mediumConfidence = status.mediumConfidence + 1
        else
            status.lowConfidence = status.lowConfidence + 1
        end

        local intersectionCount = 0
        for _, _ in pairs(prediction.samIntersections) do
            intersectionCount = intersectionCount + 1
            status.totalIntersections = status.totalIntersections + 1
        end

        table.insert(status.predictions, {
            threatId = threatId,
            confidence = prediction.confidence,
            intersections = intersectionCount,
            pointCount = #prediction.points
        })
    end

    local preActivateSams = self:getSamsToPreActivate()
    for _, _ in pairs(preActivateSams) do
        status.preActivationCandidates = status.preActivationCandidates + 1
    end

    return status
end

-- ============================================
-- ステータス表示
-- ============================================
function IADS_PREDICTOR:printStatus()
    local status = self:getStatus()

    local msg = "[Predictor Status]\n"
    msg = msg .. string.format("Mode: %s | Predictions: %d\n",
        status.mode, status.predictionCount)
    msg = msg .. string.format("Confidence: High=%d, Med=%d, Low=%d\n",
        status.highConfidence, status.mediumConfidence, status.lowConfidence)
    msg = msg .. string.format("SAM Intersections: %d | Pre-Activate: %d\n",
        status.totalIntersections, status.preActivationCandidates)

    for _, pred in ipairs(status.predictions) do
        msg = msg .. string.format("  %s: %s (%d SAMs)\n",
            pred.threatId, pred.confidence, pred.intersections)
    end

    SAM_UTILS.info(msg, 20)
end

return IADS_PREDICTOR
