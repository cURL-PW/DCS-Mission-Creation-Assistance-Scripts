--[[
    DCS IADS Terrain Masking Simulation
    地形遮蔽シミュレーション

    レーダーの見通し線（Line of Sight）を計算し、
    地形によるレーダー死角をシミュレートする

    機能:
    - レーダー位置から目標までのLOS計算
    - 地形高度サンプリングによる遮蔽判定
    - 低空侵入経路の検出
    - レーダーカバレッジマップの生成
    - SAMの実効射程計算（地形考慮）

    依存: core/utils.lua, iads/network.lua
]]

IADS_TERRAIN = {}
IADS_TERRAIN.__index = IADS_TERRAIN

-- ============================================
-- 定数
-- ============================================
IADS_TERRAIN.CONSTANTS = {
    EARTH_RADIUS = 6371000,        -- 地球半径（メートル）
    RADAR_HORIZON_FACTOR = 4.12,   -- レーダー水平線係数（km/√m）
    SAMPLE_INTERVAL = 1000,        -- 地形サンプリング間隔（メートル）
    MIN_CLEARANCE = 50,            -- 最小クリアランス（メートル）
    REFRACTION_FACTOR = 1.333,     -- 大気屈折係数（4/3地球モデル）
}

-- ============================================
-- LOS状態
-- ============================================
IADS_TERRAIN.LOS_STATUS = {
    CLEAR = "CLEAR",           -- 視通良好
    MASKED = "MASKED",         -- 地形遮蔽
    HORIZON = "HORIZON",       -- 水平線以遠
    PARTIAL = "PARTIAL"        -- 部分遮蔽
}

-- ============================================
-- カバレッジ品質
-- ============================================
IADS_TERRAIN.COVERAGE_QUALITY = {
    FULL = "FULL",             -- 完全カバー
    GOOD = "GOOD",             -- 良好（一部死角あり）
    LIMITED = "LIMITED",       -- 限定的
    POOR = "POOR",             -- 不良
    NONE = "NONE"              -- カバーなし
}

-- ============================================
-- 地形遮蔽システム作成
-- ============================================
function IADS_TERRAIN.new(iadsNetwork)
    local self = setmetatable({}, IADS_TERRAIN)

    self.network = iadsNetwork
    self.terrainCache = {}            -- 地形高度キャッシュ
    self.losCache = {}                -- LOS計算キャッシュ
    self.coverageMaps = {}            -- カバレッジマップ
    self.maskedZones = {}             -- 確認済み死角ゾーン
    self.penetrationRoutes = {}       -- 低空侵入経路
    self.updateInterval = 5           -- 更新間隔（秒）
    self.cacheLifetime = 60           -- キャッシュ有効期限（秒）
    self.sampleInterval = IADS_TERRAIN.CONSTANTS.SAMPLE_INTERVAL
    self.isRunning = false
    self.lastUpdate = 0

    return self
end

-- ============================================
-- 初期化
-- ============================================
function IADS_TERRAIN:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end
    if options.sampleInterval then
        self.sampleInterval = options.sampleInterval
    end
    if options.cacheLifetime then
        self.cacheLifetime = options.cacheLifetime
    end

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[Terrain] System initialized")
    return self
end

-- ============================================
-- 地形高度取得
-- ============================================
function IADS_TERRAIN:getTerrainHeight(x, z)
    -- キャッシュキー生成（100m単位で丸める）
    local keyX = math.floor(x / 100) * 100
    local keyZ = math.floor(z / 100) * 100
    local cacheKey = keyX .. "_" .. keyZ

    -- キャッシュチェック
    local cached = self.terrainCache[cacheKey]
    if cached and (timer.getTime() - cached.time) < self.cacheLifetime then
        return cached.height
    end

    -- DCS地形高度取得
    local height = land.getHeight({x = x, y = z})
    if not height then
        height = 0
    end

    -- キャッシュ保存
    self.terrainCache[cacheKey] = {
        height = height,
        time = timer.getTime()
    }

    return height
end

-- ============================================
-- レーダー水平線距離計算
-- ============================================
function IADS_TERRAIN:calculateRadarHorizon(radarHeight, targetHeight)
    -- 4/3地球モデルでの水平線距離
    local effectiveRadius = IADS_TERRAIN.CONSTANTS.EARTH_RADIUS *
                            IADS_TERRAIN.CONSTANTS.REFRACTION_FACTOR
    local factor = IADS_TERRAIN.CONSTANTS.RADAR_HORIZON_FACTOR

    -- レーダーからの水平線距離（km）
    local radarHorizon = factor * math.sqrt(radarHeight)

    -- 目標からの水平線距離（km）
    local targetHorizon = factor * math.sqrt(math.max(0, targetHeight))

    -- 合計水平線距離（メートル）
    return (radarHorizon + targetHorizon) * 1000
end

-- ============================================
-- 2点間の距離計算
-- ============================================
function IADS_TERRAIN:calculateDistance(pos1, pos2)
    local dx = pos2.x - pos1.x
    local dz = pos2.z - pos1.z
    return math.sqrt(dx * dx + dz * dz)
end

-- ============================================
-- 3D距離計算
-- ============================================
function IADS_TERRAIN:calculateDistance3D(pos1, pos2)
    local dx = pos2.x - pos1.x
    local dy = (pos2.y or 0) - (pos1.y or 0)
    local dz = pos2.z - pos1.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ============================================
-- LOS（見通し線）チェック
-- ============================================
function IADS_TERRAIN:checkLineOfSight(radarPos, targetPos, radarHeight, targetAltitude)
    -- レーダー高度（地上高 + アンテナ高）
    local radarAlt = self:getTerrainHeight(radarPos.x, radarPos.z) + (radarHeight or 30)

    -- 目標高度
    local targetAlt = targetAltitude or (self:getTerrainHeight(targetPos.x, targetPos.z) + 10)

    -- 水平距離
    local distance = self:calculateDistance(radarPos, targetPos)

    -- 水平線チェック
    local horizonDistance = self:calculateRadarHorizon(radarAlt, targetAlt)
    if distance > horizonDistance then
        return IADS_TERRAIN.LOS_STATUS.HORIZON, 0, horizonDistance
    end

    -- 地形サンプリング
    local samples = math.max(2, math.floor(distance / self.sampleInterval))
    local dx = (targetPos.x - radarPos.x) / samples
    local dz = (targetPos.z - radarPos.z) / samples
    local dAlt = (targetAlt - radarAlt) / samples

    local maxObstruction = 0
    local obstructionCount = 0

    for i = 1, samples - 1 do
        local sampleX = radarPos.x + dx * i
        local sampleZ = radarPos.z + dz * i
        local expectedAlt = radarAlt + dAlt * i

        local terrainHeight = self:getTerrainHeight(sampleX, sampleZ)

        -- LOS高度と地形高度の比較
        local clearance = expectedAlt - terrainHeight

        if clearance < IADS_TERRAIN.CONSTANTS.MIN_CLEARANCE then
            obstructionCount = obstructionCount + 1
            local obstruction = terrainHeight - expectedAlt + IADS_TERRAIN.CONSTANTS.MIN_CLEARANCE
            if obstruction > maxObstruction then
                maxObstruction = obstruction
            end
        end
    end

    -- 結果判定
    if obstructionCount == 0 then
        return IADS_TERRAIN.LOS_STATUS.CLEAR, 0, distance
    elseif obstructionCount < samples * 0.3 then
        return IADS_TERRAIN.LOS_STATUS.PARTIAL, maxObstruction, distance
    else
        return IADS_TERRAIN.LOS_STATUS.MASKED, maxObstruction, distance
    end
end

-- ============================================
-- SAMの実効射程計算（地形考慮）
-- ============================================
function IADS_TERRAIN:calculateEffectiveRange(samSite, direction, targetAltitude)
    local samPos = samSite.position or samSite
    local maxRange = samSite.range or 40000
    local radarHeight = samSite.radarHeight or 30

    -- 指定方向に向かってLOSチェック
    local angleRad = math.rad(direction)
    local stepSize = 1000  -- 1km単位でチェック

    local effectiveRange = maxRange

    for dist = stepSize, maxRange, stepSize do
        local targetX = samPos.x + math.sin(angleRad) * dist
        local targetZ = samPos.z + math.cos(angleRad) * dist
        local targetPos = {x = targetX, z = targetZ}

        local losStatus, _, _ = self:checkLineOfSight(
            samPos, targetPos, radarHeight, targetAltitude
        )

        if losStatus == IADS_TERRAIN.LOS_STATUS.MASKED or
           losStatus == IADS_TERRAIN.LOS_STATUS.HORIZON then
            effectiveRange = dist - stepSize
            break
        end
    end

    return effectiveRange
end

-- ============================================
-- 全方位カバレッジマップ生成
-- ============================================
function IADS_TERRAIN:generateCoverageMap(samSite, options)
    options = options or {}
    local angleStep = options.angleStep or 10       -- 角度ステップ（度）
    local targetAlt = options.targetAltitude or 1000  -- 想定目標高度

    local coverage = {
        samName = samSite.name,
        position = samSite.position,
        maxRange = samSite.range or 40000,
        targetAltitude = targetAlt,
        directions = {},
        averageEffectiveRange = 0,
        coverageQuality = IADS_TERRAIN.COVERAGE_QUALITY.FULL
    }

    local totalRange = 0
    local count = 0

    for angle = 0, 359, angleStep do
        local effRange = self:calculateEffectiveRange(samSite, angle, targetAlt)
        coverage.directions[angle] = {
            angle = angle,
            effectiveRange = effRange,
            rangeRatio = effRange / coverage.maxRange
        }
        totalRange = totalRange + effRange
        count = count + 1
    end

    coverage.averageEffectiveRange = totalRange / count
    local avgRatio = coverage.averageEffectiveRange / coverage.maxRange

    -- カバレッジ品質判定
    if avgRatio >= 0.9 then
        coverage.coverageQuality = IADS_TERRAIN.COVERAGE_QUALITY.FULL
    elseif avgRatio >= 0.7 then
        coverage.coverageQuality = IADS_TERRAIN.COVERAGE_QUALITY.GOOD
    elseif avgRatio >= 0.5 then
        coverage.coverageQuality = IADS_TERRAIN.COVERAGE_QUALITY.LIMITED
    elseif avgRatio >= 0.2 then
        coverage.coverageQuality = IADS_TERRAIN.COVERAGE_QUALITY.POOR
    else
        coverage.coverageQuality = IADS_TERRAIN.COVERAGE_QUALITY.NONE
    end

    self.coverageMaps[samSite.name] = coverage
    return coverage
end

-- ============================================
-- 死角ゾーン検出
-- ============================================
function IADS_TERRAIN:detectMaskedZones(samSite, options)
    options = options or {}
    local coverage = self.coverageMaps[samSite.name]

    if not coverage then
        coverage = self:generateCoverageMap(samSite, options)
    end

    local maskedZones = {}
    local inMaskedZone = false
    local zoneStart = nil

    for angle = 0, 359 do
        local dirData = coverage.directions[angle]
        if dirData then
            local isMasked = dirData.rangeRatio < 0.5

            if isMasked and not inMaskedZone then
                -- 死角ゾーン開始
                inMaskedZone = true
                zoneStart = angle
            elseif not isMasked and inMaskedZone then
                -- 死角ゾーン終了
                table.insert(maskedZones, {
                    startAngle = zoneStart,
                    endAngle = angle,
                    arcWidth = angle - zoneStart
                })
                inMaskedZone = false
            end
        end
    end

    -- 360度をまたぐ死角ゾーンの処理
    if inMaskedZone then
        table.insert(maskedZones, {
            startAngle = zoneStart,
            endAngle = 360,
            arcWidth = 360 - zoneStart
        })
    end

    self.maskedZones[samSite.name] = maskedZones
    return maskedZones
end

-- ============================================
-- 低空侵入経路検出
-- ============================================
function IADS_TERRAIN:detectPenetrationRoutes(startPos, targetPos, maxAltitude)
    maxAltitude = maxAltitude or 100  -- デフォルト100m AGL

    local route = {
        startPos = startPos,
        targetPos = targetPos,
        maxAltitude = maxAltitude,
        waypoints = {},
        threatExposure = {},
        viable = true
    }

    -- 経路上のウェイポイント生成
    local distance = self:calculateDistance(startPos, targetPos)
    local waypointCount = math.max(5, math.floor(distance / 5000))  -- 5km間隔

    local dx = (targetPos.x - startPos.x) / waypointCount
    local dz = (targetPos.z - startPos.z) / waypointCount

    for i = 0, waypointCount do
        local wpX = startPos.x + dx * i
        local wpZ = startPos.z + dz * i
        local terrainHeight = self:getTerrainHeight(wpX, wpZ)

        table.insert(route.waypoints, {
            x = wpX,
            z = wpZ,
            terrainHeight = terrainHeight,
            suggestedAlt = terrainHeight + maxAltitude
        })
    end

    -- 各SAMからの脅威評価
    if self.network then
        for samName, samData in pairs(self.network.samSites or {}) do
            local exposure = self:evaluateRouteExposure(route, samData)
            route.threatExposure[samName] = exposure
        end
    end

    table.insert(self.penetrationRoutes, route)
    return route
end

-- ============================================
-- 経路の脅威曝露評価
-- ============================================
function IADS_TERRAIN:evaluateRouteExposure(route, samSite)
    local exposure = {
        samName = samSite.name,
        inRangeWaypoints = 0,
        visibleWaypoints = 0,
        totalWaypoints = #route.waypoints,
        exposureRatio = 0,
        threatLevel = "NONE"
    }

    for _, wp in ipairs(route.waypoints) do
        local distance = self:calculateDistance(samSite.position, wp)
        local maxRange = samSite.range or 40000

        if distance <= maxRange then
            exposure.inRangeWaypoints = exposure.inRangeWaypoints + 1

            local losStatus, _, _ = self:checkLineOfSight(
                samSite.position, wp,
                samSite.radarHeight or 30,
                wp.suggestedAlt
            )

            if losStatus == IADS_TERRAIN.LOS_STATUS.CLEAR or
               losStatus == IADS_TERRAIN.LOS_STATUS.PARTIAL then
                exposure.visibleWaypoints = exposure.visibleWaypoints + 1
            end
        end
    end

    if exposure.totalWaypoints > 0 then
        exposure.exposureRatio = exposure.visibleWaypoints / exposure.totalWaypoints
    end

    -- 脅威レベル判定
    if exposure.exposureRatio >= 0.7 then
        exposure.threatLevel = "HIGH"
    elseif exposure.exposureRatio >= 0.4 then
        exposure.threatLevel = "MEDIUM"
    elseif exposure.exposureRatio >= 0.1 then
        exposure.threatLevel = "LOW"
    else
        exposure.threatLevel = "NONE"
    end

    return exposure
end

-- ============================================
-- 目標の可視SAM取得
-- ============================================
function IADS_TERRAIN:getVisibleSAMs(targetPos, targetAltitude)
    local visibleSAMs = {}

    if not self.network then
        return visibleSAMs
    end

    for samName, samData in pairs(self.network.samSites or {}) do
        local distance = self:calculateDistance(samData.position, targetPos)
        local maxRange = samData.range or 40000

        if distance <= maxRange then
            local losStatus, obstruction, _ = self:checkLineOfSight(
                samData.position, targetPos,
                samData.radarHeight or 30,
                targetAltitude
            )

            if losStatus == IADS_TERRAIN.LOS_STATUS.CLEAR or
               losStatus == IADS_TERRAIN.LOS_STATUS.PARTIAL then
                table.insert(visibleSAMs, {
                    name = samName,
                    distance = distance,
                    losStatus = losStatus,
                    obstruction = obstruction
                })
            end
        end
    end

    return visibleSAMs
end

-- ============================================
-- キャッシュクリア
-- ============================================
function IADS_TERRAIN:clearCache()
    self.terrainCache = {}
    self.losCache = {}
    SAM_UTILS.debug("[Terrain] Cache cleared")
end

-- ============================================
-- 定期更新スケジュール
-- ============================================
function IADS_TERRAIN:scheduleUpdate()
    if not self.isRunning then return end

    timer.scheduleFunction(function()
        self:update()
        self:scheduleUpdate()
    end, nil, timer.getTime() + self.updateInterval)
end

-- ============================================
-- 更新処理
-- ============================================
function IADS_TERRAIN:update()
    self.lastUpdate = timer.getTime()

    -- 古いキャッシュをクリア
    local now = timer.getTime()
    for key, cached in pairs(self.terrainCache) do
        if (now - cached.time) > self.cacheLifetime * 2 then
            self.terrainCache[key] = nil
        end
    end
end

-- ============================================
-- 停止
-- ============================================
function IADS_TERRAIN:stop()
    self.isRunning = false
    SAM_UTILS.debug("[Terrain] System stopped")
end

-- ============================================
-- ステータス表示
-- ============================================
function IADS_TERRAIN:printStatus()
    local text = "=== Terrain Masking System Status ===\n"
    text = text .. string.format("Running: %s\n", tostring(self.isRunning))
    text = text .. string.format("Terrain Cache Entries: %d\n", SAM_UTILS.tableLength(self.terrainCache))
    text = text .. string.format("Coverage Maps: %d\n", SAM_UTILS.tableLength(self.coverageMaps))

    if SAM_UTILS.tableLength(self.coverageMaps) > 0 then
        text = text .. "\n--- Coverage Quality ---\n"
        for samName, coverage in pairs(self.coverageMaps) do
            text = text .. string.format("  %s: %s (%.0f%% effective)\n",
                samName,
                coverage.coverageQuality,
                (coverage.averageEffectiveRange / coverage.maxRange) * 100)
        end
    end

    if SAM_UTILS.tableLength(self.maskedZones) > 0 then
        text = text .. "\n--- Masked Zones ---\n"
        for samName, zones in pairs(self.maskedZones) do
            if #zones > 0 then
                text = text .. string.format("  %s: %d zones\n", samName, #zones)
                for _, zone in ipairs(zones) do
                    text = text .. string.format("    %d° - %d° (arc: %d°)\n",
                        zone.startAngle, zone.endAngle, zone.arcWidth)
                end
            end
        end
    end

    text = text .. "==================================="
    trigger.action.outText(text, 15)
end

-- ============================================
-- 統合関数: 地形遮蔽システム作成
-- ============================================
function createTerrainSystem(network, options)
    local terrain = IADS_TERRAIN.new(network)
    terrain:init(options)
    return terrain
end
