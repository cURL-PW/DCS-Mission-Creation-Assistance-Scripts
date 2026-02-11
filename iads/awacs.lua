--[[
    DCS IADS AWACS Integration
    空中早期警戒機連携システム

    AWACSを移動式EWRとしてIADSネットワークに統合

    機能:
    - AWACSユニットの追跡と管理
    - 滞空時間・燃料管理
    - 軌道パターン設定（レーストラック、ホールディング等）
    - 脅威情報のリアルタイム共有
    - SAMサイトへのデータリンク

    依存: core/utils.lua, iads/network.lua, iads/datalink.lua
]]

IADS_AWACS = {}
IADS_AWACS.__index = IADS_AWACS

-- ============================================
-- 軌道パターン
-- ============================================
IADS_AWACS.ORBIT_PATTERN = {
    RACETRACK = "RACETRACK",       -- レーストラック
    FIGURE_EIGHT = "FIGURE_EIGHT", -- 8の字
    CIRCULAR = "CIRCULAR",         -- 円形
    LINEAR = "LINEAR",             -- 直線往復
    CUSTOM = "CUSTOM"              -- カスタム
}

-- ============================================
-- AWACS状態
-- ============================================
IADS_AWACS.STATUS = {
    ON_STATION = "ON_STATION",     -- 配置中
    TRANSIT_IN = "TRANSIT_IN",     -- 配置へ移動中
    TRANSIT_OUT = "TRANSIT_OUT",   -- 帰投中
    REFUELING = "REFUELING",       -- 空中給油中
    RTB = "RTB",                   -- 帰投（基地へ）
    OFFLINE = "OFFLINE",           -- オフライン
    DESTROYED = "DESTROYED"        -- 撃墜
}

-- ============================================
-- AWACSタイプ定義
-- ============================================
IADS_AWACS.AIRCRAFT_TYPES = {
    -- 西側
    ["E-3A"] = {
        name = "E-3A Sentry",
        radarRange = 400000,       -- 400km
        maxLoiterTime = 11 * 3600, -- 11時間
        fuelCapacity = 100,
        fuelBurnRate = 0.15,       -- 1時間あたり15%
        maxTracksSimultaneous = 300,
        dataLinkCapable = true
    },
    ["E-2C"] = {
        name = "E-2C Hawkeye",
        radarRange = 270000,       -- 270km
        maxLoiterTime = 5 * 3600,  -- 5時間
        fuelCapacity = 100,
        fuelBurnRate = 0.2,
        maxTracksSimultaneous = 150,
        dataLinkCapable = true
    },
    -- ロシア
    ["A-50"] = {
        name = "A-50 Mainstay",
        radarRange = 350000,       -- 350km
        maxLoiterTime = 7 * 3600,  -- 7時間
        fuelCapacity = 100,
        fuelBurnRate = 0.14,
        maxTracksSimultaneous = 200,
        dataLinkCapable = true
    }
}

-- ============================================
-- AWACSシステム作成
-- ============================================
function IADS_AWACS.new(iadsNetwork)
    local self = setmetatable({}, IADS_AWACS)

    self.network = iadsNetwork
    self.datalink = nil                   -- データリンクシステム参照
    self.awacsUnits = {}                  -- 登録AWACS
    self.orbitZones = {}                  -- 軌道ゾーン定義
    self.tracks = {}                      -- 検出トラック
    self.updateInterval = 2               -- 更新間隔（秒）
    self.fuelWarningThreshold = 30        -- 燃料警告閾値（%）
    self.autoRTB = true                   -- 自動帰投
    self.isRunning = false
    self.lastUpdate = 0

    -- コールバック
    self.callbacks = {
        onStatusChange = nil,
        onFuelWarning = nil,
        onNewTrack = nil,
        onTrackLost = nil,
        onAwacsDestroyed = nil
    }

    return self
end

-- ============================================
-- 初期化
-- ============================================
function IADS_AWACS:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end
    if options.fuelWarningThreshold then
        self.fuelWarningThreshold = options.fuelWarningThreshold
    end
    if options.autoRTB ~= nil then
        self.autoRTB = options.autoRTB
    end
    if options.datalink then
        self.datalink = options.datalink
    end

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[AWACS] System initialized")
    return self
end

-- ============================================
-- AWACSユニット登録
-- ============================================
function IADS_AWACS:registerAWACS(groupName, options)
    options = options or {}

    local group = Group.getByName(groupName)
    if not group then
        SAM_UTILS.debug("[AWACS] Group not found: " .. groupName)
        return nil
    end

    local unit = group:getUnit(1)
    if not unit then
        SAM_UTILS.debug("[AWACS] No unit in group: " .. groupName)
        return nil
    end

    local typeName = unit:getTypeName()
    local typeData = IADS_AWACS.AIRCRAFT_TYPES[typeName] or {
        name = typeName,
        radarRange = 300000,
        maxLoiterTime = 6 * 3600,
        fuelCapacity = 100,
        fuelBurnRate = 0.17,
        maxTracksSimultaneous = 100,
        dataLinkCapable = true
    }

    local awacs = {
        name = groupName,
        group = group,
        unit = unit,
        typeName = typeName,
        typeData = typeData,
        status = IADS_AWACS.STATUS.OFFLINE,
        position = nil,
        altitude = nil,
        heading = nil,
        fuel = options.initialFuel or 100,
        onStationTime = 0,
        currentOrbit = nil,
        homeBase = options.homeBase,
        detectedTargets = {},
        tracksShared = 0,
        coalition = unit:getCoalition(),
        lastUpdate = timer.getTime()
    }

    self.awacsUnits[groupName] = awacs

    -- IADSネットワークにEWRとして追加
    if self.network then
        self.network:addEWR({
            name = groupName,
            type = "AWACS",
            range = typeData.radarRange,
            isMobile = true,
            position = unit:getPoint()
        })
    end

    SAM_UTILS.debug("[AWACS] Registered: " .. groupName .. " (" .. typeData.name .. ")")
    return awacs
end

-- ============================================
-- 軌道ゾーン設定
-- ============================================
function IADS_AWACS:setOrbitZone(awacs, orbitOptions)
    local awacsData = self.awacsUnits[awacs]
    if not awacsData then return nil end

    orbitOptions = orbitOptions or {}

    local orbit = {
        pattern = orbitOptions.pattern or IADS_AWACS.ORBIT_PATTERN.RACETRACK,
        center = orbitOptions.center,
        altitude = orbitOptions.altitude or 9000,  -- 9000m
        speed = orbitOptions.speed or 180,         -- m/s
        legLength = orbitOptions.legLength or 80000,  -- 80km
        turnRadius = orbitOptions.turnRadius or 15000, -- 15km
        heading = orbitOptions.heading or 0
    }

    awacsData.currentOrbit = orbit
    self.orbitZones[awacs] = orbit

    SAM_UTILS.debug("[AWACS] Orbit set for: " .. awacs)
    return orbit
end

-- ============================================
-- AWACS配置開始
-- ============================================
function IADS_AWACS:deployAWACS(awacs)
    local awacsData = self.awacsUnits[awacs]
    if not awacsData then return false end

    if awacsData.status == IADS_AWACS.STATUS.DESTROYED then
        return false
    end

    local oldStatus = awacsData.status
    awacsData.status = IADS_AWACS.STATUS.TRANSIT_IN
    awacsData.onStationTime = 0

    if self.callbacks.onStatusChange then
        self.callbacks.onStatusChange(awacs, oldStatus, awacsData.status)
    end

    SAM_UTILS.debug("[AWACS] Deploying: " .. awacs)
    return true
end

-- ============================================
-- 配置完了（ステーション到着）
-- ============================================
function IADS_AWACS:arriveOnStation(awacs)
    local awacsData = self.awacsUnits[awacs]
    if not awacsData then return false end

    local oldStatus = awacsData.status
    awacsData.status = IADS_AWACS.STATUS.ON_STATION
    awacsData.onStationTime = timer.getTime()

    if self.callbacks.onStatusChange then
        self.callbacks.onStatusChange(awacs, oldStatus, awacsData.status)
    end

    SAM_UTILS.debug("[AWACS] On station: " .. awacs)
    return true
end

-- ============================================
-- 帰投命令
-- ============================================
function IADS_AWACS:orderRTB(awacs, reason)
    local awacsData = self.awacsUnits[awacs]
    if not awacsData then return false end

    local oldStatus = awacsData.status
    awacsData.status = IADS_AWACS.STATUS.RTB

    if self.callbacks.onStatusChange then
        self.callbacks.onStatusChange(awacs, oldStatus, awacsData.status, reason)
    end

    SAM_UTILS.debug("[AWACS] RTB ordered: " .. awacs .. " (reason: " .. (reason or "manual") .. ")")
    return true
end

-- ============================================
-- 脅威検出
-- ============================================
function IADS_AWACS:detectThreats(awacs)
    local awacsData = self.awacsUnits[awacs]
    if not awacsData then return {} end

    if awacsData.status ~= IADS_AWACS.STATUS.ON_STATION then
        return {}
    end

    local unit = awacsData.unit
    if not unit or not unit:isExist() then
        self:handleAwacsLost(awacs)
        return {}
    end

    local awacsPos = unit:getPoint()
    local radarRange = awacsData.typeData.radarRange
    local detectedTargets = {}

    -- 球形範囲内の航空機を検索
    local sphere = {
        id = world.VolumeType.SPHERE,
        params = {
            point = awacsPos,
            radius = radarRange
        }
    }

    local coalition = awacsData.coalition
    local enemyCoalition = coalition == 1 and 2 or 1

    world.searchObjects(Object.Category.UNIT, sphere, function(foundObject)
        if foundObject:getCoalition() == enemyCoalition then
            local objPos = foundObject:getPoint()
            local objVel = foundObject:getVelocity()

            local target = {
                id = foundObject:getName(),
                type = foundObject:getTypeName(),
                position = objPos,
                altitude = objPos.y,
                velocity = objVel,
                speed = math.sqrt(objVel.x^2 + objVel.y^2 + objVel.z^2),
                heading = math.deg(math.atan2(objVel.x, objVel.z)),
                detectedBy = awacs,
                detectedAt = timer.getTime()
            }

            table.insert(detectedTargets, target)
        end
        return true
    end)

    -- トラック数制限
    local maxTracks = awacsData.typeData.maxTracksSimultaneous
    if #detectedTargets > maxTracks then
        -- 距離でソートして近い順に制限
        table.sort(detectedTargets, function(a, b)
            local distA = SAM_UTILS.getDistance(awacsPos, a.position)
            local distB = SAM_UTILS.getDistance(awacsPos, b.position)
            return distA < distB
        end)

        local limited = {}
        for i = 1, maxTracks do
            limited[i] = detectedTargets[i]
        end
        detectedTargets = limited
    end

    awacsData.detectedTargets = detectedTargets
    return detectedTargets
end

-- ============================================
-- トラック共有（データリンク経由）
-- ============================================
function IADS_AWACS:shareTracksWithNetwork(awacs)
    local awacsData = self.awacsUnits[awacs]
    if not awacsData then return 0 end

    if not awacsData.typeData.dataLinkCapable then
        return 0
    end

    local sharedCount = 0

    for _, target in ipairs(awacsData.detectedTargets) do
        -- データリンクシステム経由で共有
        if self.datalink then
            local track = {
                id = target.id,
                position = target.position,
                velocity = target.velocity,
                altitude = target.altitude,
                heading = target.heading,
                source = awacs,
                timestamp = target.detectedAt,
                quality = "GOOD"  -- AWACSトラックは高品質
            }

            self.datalink:shareTrack(track, awacs)
            sharedCount = sharedCount + 1
        end

        -- 脅威システムに登録
        if self.network and self.network.threatSystem then
            self.network.threatSystem:updateThreat({
                id = target.id,
                type = target.type,
                position = target.position,
                velocity = target.velocity,
                altitude = target.altitude,
                heading = target.heading,
                source = "AWACS:" .. awacs
            })
        end
    end

    awacsData.tracksShared = sharedCount
    return sharedCount
end

-- ============================================
-- 燃料更新
-- ============================================
function IADS_AWACS:updateFuel(awacs, deltaTime)
    local awacsData = self.awacsUnits[awacs]
    if not awacsData then return end

    if awacsData.status == IADS_AWACS.STATUS.ON_STATION or
       awacsData.status == IADS_AWACS.STATUS.TRANSIT_IN or
       awacsData.status == IADS_AWACS.STATUS.TRANSIT_OUT then

        local burnRate = awacsData.typeData.fuelBurnRate
        local fuelBurned = burnRate * (deltaTime / 3600)  -- 時間あたりの消費率
        awacsData.fuel = awacsData.fuel - fuelBurned

        -- 燃料警告
        if awacsData.fuel <= self.fuelWarningThreshold and
           awacsData.fuel > self.fuelWarningThreshold - 1 then
            if self.callbacks.onFuelWarning then
                self.callbacks.onFuelWarning(awacs, awacsData.fuel)
            end

            -- 自動帰投
            if self.autoRTB and awacsData.fuel <= 20 then
                self:orderRTB(awacs, "BINGO_FUEL")
            end
        end

        -- 燃料切れ
        if awacsData.fuel <= 0 then
            awacsData.fuel = 0
            self:handleAwacsLost(awacs, "FUEL_EXHAUSTED")
        end
    end
end

-- ============================================
-- AWACS喪失処理
-- ============================================
function IADS_AWACS:handleAwacsLost(awacs, reason)
    local awacsData = self.awacsUnits[awacs]
    if not awacsData then return end

    local oldStatus = awacsData.status

    if reason == "DESTROYED" or reason == "SHOT_DOWN" then
        awacsData.status = IADS_AWACS.STATUS.DESTROYED
    else
        awacsData.status = IADS_AWACS.STATUS.OFFLINE
    end

    -- IADSネットワークからEWRを削除
    if self.network then
        self.network:removeEWR(awacs)
    end

    if self.callbacks.onAwacsDestroyed then
        self.callbacks.onAwacsDestroyed(awacs, reason)
    end

    SAM_UTILS.debug("[AWACS] Lost: " .. awacs .. " (reason: " .. (reason or "unknown") .. ")")
end

-- ============================================
-- AWACS位置更新
-- ============================================
function IADS_AWACS:updatePosition(awacs)
    local awacsData = self.awacsUnits[awacs]
    if not awacsData then return end

    local unit = awacsData.unit
    if not unit or not unit:isExist() then
        self:handleAwacsLost(awacs, "DESTROYED")
        return
    end

    local pos = unit:getPoint()
    local vel = unit:getVelocity()

    awacsData.position = pos
    awacsData.altitude = pos.y
    awacsData.heading = math.deg(math.atan2(vel.x, vel.z))

    -- IADSネットワークのEWR位置を更新
    if self.network then
        self.network:updateEWRPosition(awacs, pos)
    end
end

-- ============================================
-- 配置中AWACSのカバレッジ計算
-- ============================================
function IADS_AWACS:getTotalCoverage()
    local coverage = {
        totalArea = 0,
        onStationCount = 0,
        awacsList = {}
    }

    for name, awacsData in pairs(self.awacsUnits) do
        if awacsData.status == IADS_AWACS.STATUS.ON_STATION then
            coverage.onStationCount = coverage.onStationCount + 1
            local range = awacsData.typeData.radarRange
            local area = math.pi * range * range

            table.insert(coverage.awacsList, {
                name = name,
                position = awacsData.position,
                range = range,
                area = area
            })

            coverage.totalArea = coverage.totalArea + area
        end
    end

    return coverage
end

-- ============================================
-- コールバック設定
-- ============================================
function IADS_AWACS:setCallback(event, handler)
    if self.callbacks[event] ~= nil then
        self.callbacks[event] = handler
    end
end

-- ============================================
-- 定期更新スケジュール
-- ============================================
function IADS_AWACS:scheduleUpdate()
    if not self.isRunning then return end

    timer.scheduleFunction(function()
        self:update()
        self:scheduleUpdate()
    end, nil, timer.getTime() + self.updateInterval)
end

-- ============================================
-- 更新処理
-- ============================================
function IADS_AWACS:update()
    local now = timer.getTime()
    local deltaTime = now - self.lastUpdate
    self.lastUpdate = now

    for name, awacsData in pairs(self.awacsUnits) do
        if awacsData.status ~= IADS_AWACS.STATUS.DESTROYED and
           awacsData.status ~= IADS_AWACS.STATUS.OFFLINE then

            -- 位置更新
            self:updatePosition(name)

            -- 燃料更新
            self:updateFuel(name, deltaTime)

            -- 脅威検出
            if awacsData.status == IADS_AWACS.STATUS.ON_STATION then
                self:detectThreats(name)
                self:shareTracksWithNetwork(name)
            end

            awacsData.lastUpdate = now
        end
    end
end

-- ============================================
-- 停止
-- ============================================
function IADS_AWACS:stop()
    self.isRunning = false
    SAM_UTILS.debug("[AWACS] System stopped")
end

-- ============================================
-- ステータス表示
-- ============================================
function IADS_AWACS:printStatus()
    local text = "=== AWACS System Status ===\n"
    text = text .. string.format("Registered AWACS: %d\n", SAM_UTILS.tableLength(self.awacsUnits))

    local onStation = 0
    for _, awacsData in pairs(self.awacsUnits) do
        if awacsData.status == IADS_AWACS.STATUS.ON_STATION then
            onStation = onStation + 1
        end
    end
    text = text .. string.format("On Station: %d\n", onStation)

    text = text .. "\n--- AWACS Details ---\n"
    for name, awacsData in pairs(self.awacsUnits) do
        text = text .. string.format("  %s (%s)\n", name, awacsData.typeData.name)
        text = text .. string.format("    Status: %s\n", awacsData.status)
        text = text .. string.format("    Fuel: %.1f%%\n", awacsData.fuel)
        text = text .. string.format("    Detected Targets: %d\n", #awacsData.detectedTargets)
        text = text .. string.format("    Tracks Shared: %d\n", awacsData.tracksShared)

        if awacsData.position then
            text = text .. string.format("    Altitude: %.0f m\n", awacsData.altitude)
        end
    end

    text = text .. "==========================="
    trigger.action.outText(text, 15)
end

-- ============================================
-- 統合関数: AWACSシステム作成
-- ============================================
function createAWACSSystem(network, options)
    local awacs = IADS_AWACS.new(network)
    awacs:init(options)
    return awacs
end
