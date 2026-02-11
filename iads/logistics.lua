--[[
    DCS IADS Logistics System
    補給・兵站シミュレーション

    SAMサイトの燃料・弾薬補給をシミュレート

    機能:
    - 燃料消費シミュレーション
    - 弾薬補給トラック派遣
    - 補給ルート管理
    - 補給デポ/集積所
    - 補給優先度管理
    - 補給車両の脆弱性

    依存: core/utils.lua, iads/network.lua, core/ammo.lua
]]

IADS_LOGISTICS = {}
IADS_LOGISTICS.__index = IADS_LOGISTICS

-- ============================================
-- 補給品種別
-- ============================================
IADS_LOGISTICS.SUPPLY_TYPE = {
    MISSILES = "MISSILES",         -- ミサイル
    FUEL = "FUEL",                 -- 燃料
    SPARE_PARTS = "SPARE_PARTS",   -- 交換部品
    PERSONNEL = "PERSONNEL"         -- 人員
}

-- ============================================
-- 車両状態
-- ============================================
IADS_LOGISTICS.VEHICLE_STATUS = {
    IDLE = "IDLE",               -- 待機中
    LOADING = "LOADING",         -- 積み込み中
    EN_ROUTE = "EN_ROUTE",       -- 移動中
    UNLOADING = "UNLOADING",     -- 荷下ろし中
    RETURNING = "RETURNING",     -- 帰還中
    DESTROYED = "DESTROYED"      -- 破壊
}

-- ============================================
-- 補給優先度
-- ============================================
IADS_LOGISTICS.PRIORITY = {
    CRITICAL = 1,    -- 最優先
    HIGH = 2,        -- 高
    NORMAL = 3,      -- 通常
    LOW = 4          -- 低
}

-- ============================================
-- 補給デポタイプ
-- ============================================
IADS_LOGISTICS.DEPOT_TYPE = {
    MAIN = "MAIN",           -- 主要デポ
    FORWARD = "FORWARD",     -- 前方デポ
    FIELD = "FIELD"          -- 野戦デポ
}

-- ============================================
-- 補給システム作成
-- ============================================
function IADS_LOGISTICS.new(iadsNetwork)
    local self = setmetatable({}, IADS_LOGISTICS)

    self.network = iadsNetwork
    self.ammoSystem = nil                 -- 弾薬管理システム参照
    self.depots = {}                      -- 補給デポ
    self.convoys = {}                     -- 補給車列
    self.supplyRoutes = {}                -- 補給ルート
    self.pendingRequests = {}             -- 補給要請キュー
    self.samResources = {}                -- SAMサイトごとのリソース
    self.updateInterval = 5               -- 更新間隔（秒）
    self.fuelConsumptionRate = 0.5        -- 1時間あたりの燃料消費（%）
    self.autoResupply = true              -- 自動補給
    self.resupplyThreshold = 50           -- 自動補給閾値（%）
    self.convoySpeed = 15                 -- 車列速度（m/s、約54km/h）
    self.isRunning = false
    self.lastUpdate = 0
    self.nextConvoyId = 1

    -- コールバック
    self.callbacks = {
        onSupplyRequest = nil,
        onConvoyDispatched = nil,
        onConvoyArrived = nil,
        onConvoyDestroyed = nil,
        onResourceCritical = nil
    }

    return self
end

-- ============================================
-- 初期化
-- ============================================
function IADS_LOGISTICS:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end
    if options.fuelConsumptionRate then
        self.fuelConsumptionRate = options.fuelConsumptionRate
    end
    if options.autoResupply ~= nil then
        self.autoResupply = options.autoResupply
    end
    if options.resupplyThreshold then
        self.resupplyThreshold = options.resupplyThreshold
    end
    if options.convoySpeed then
        self.convoySpeed = options.convoySpeed
    end
    if options.ammoSystem then
        self.ammoSystem = options.ammoSystem
    end

    -- SAMサイトのリソース初期化
    if self.network then
        self:initializeSamResources()
    end

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[Logistics] System initialized")
    return self
end

-- ============================================
-- SAMリソース初期化
-- ============================================
function IADS_LOGISTICS:initializeSamResources()
    if not self.network or not self.network.samSites then return end

    for name, samData in pairs(self.network.samSites) do
        self.samResources[name] = {
            name = name,
            position = samData.position,
            fuel = 100,                    -- 燃料（%）
            missiles = samData.ammo or 100,-- ミサイル（%）
            spareParts = 100,              -- 交換部品（%）
            fuelConsumptionRate = self.fuelConsumptionRate,
            isOperational = true,
            lastResupply = timer.getTime(),
            pendingSupply = {}
        }
    end
end

-- ============================================
-- 補給デポ追加
-- ============================================
function IADS_LOGISTICS:addDepot(name, position, options)
    options = options or {}

    local depot = {
        name = name,
        position = position,
        type = options.type or IADS_LOGISTICS.DEPOT_TYPE.MAIN,
        inventory = {
            missiles = options.missiles or 1000,
            fuel = options.fuel or 10000,
            spareParts = options.spareParts or 500
        },
        maxInventory = {
            missiles = options.maxMissiles or 2000,
            fuel = options.maxFuel or 20000,
            spareParts = options.maxSpareParts or 1000
        },
        vehicles = options.vehicles or 5,     -- 利用可能車両数
        vehiclesAvailable = options.vehicles or 5,
        loadingTime = options.loadingTime or 300,  -- 積み込み時間（秒）
        isActive = true,
        coalition = options.coalition or 1
    }

    self.depots[name] = depot
    SAM_UTILS.debug("[Logistics] Depot added: " .. name)
    return depot
end

-- ============================================
-- 補給ルート設定
-- ============================================
function IADS_LOGISTICS:setSupplyRoute(depotName, samName, waypoints)
    local routeKey = depotName .. "_" .. samName

    local depot = self.depots[depotName]
    local sam = self.samResources[samName]

    if not depot or not sam then
        return nil
    end

    -- ルート距離計算
    local totalDistance = 0
    local prevPos = depot.position

    for _, wp in ipairs(waypoints or {}) do
        local dx = wp.x - prevPos.x
        local dz = wp.z - prevPos.z
        totalDistance = totalDistance + math.sqrt(dx * dx + dz * dz)
        prevPos = wp
    end

    -- 最終地点までの距離
    local dx = sam.position.x - prevPos.x
    local dz = sam.position.z - prevPos.z
    totalDistance = totalDistance + math.sqrt(dx * dx + dz * dz)

    local route = {
        depotName = depotName,
        samName = samName,
        waypoints = waypoints or {},
        totalDistance = totalDistance,
        estimatedTime = totalDistance / self.convoySpeed,
        riskLevel = 0,  -- 0-100
        isActive = true
    }

    self.supplyRoutes[routeKey] = route
    return route
end

-- ============================================
-- 自動ルート生成（直線）
-- ============================================
function IADS_LOGISTICS:generateDirectRoute(depotName, samName)
    return self:setSupplyRoute(depotName, samName, {})
end

-- ============================================
-- 補給要請
-- ============================================
function IADS_LOGISTICS:requestSupply(samName, supplyType, amount, priority)
    priority = priority or IADS_LOGISTICS.PRIORITY.NORMAL

    local request = {
        id = #self.pendingRequests + 1,
        samName = samName,
        supplyType = supplyType,
        amount = amount,
        priority = priority,
        requestTime = timer.getTime(),
        status = "PENDING",
        assignedConvoy = nil
    }

    table.insert(self.pendingRequests, request)

    -- 優先度でソート
    table.sort(self.pendingRequests, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.requestTime < b.requestTime
    end)

    if self.callbacks.onSupplyRequest then
        self.callbacks.onSupplyRequest(request)
    end

    SAM_UTILS.debug("[Logistics] Supply request: " .. samName .. " needs " .. supplyType)
    return request
end

-- ============================================
-- 補給車列派遣
-- ============================================
function IADS_LOGISTICS:dispatchConvoy(depotName, samName, supplies)
    local depot = self.depots[depotName]
    local sam = self.samResources[samName]

    if not depot or not sam then
        return nil
    end

    if depot.vehiclesAvailable <= 0 then
        SAM_UTILS.debug("[Logistics] No vehicles available at: " .. depotName)
        return nil
    end

    -- 在庫チェック
    for supplyType, amount in pairs(supplies) do
        local key = supplyType == IADS_LOGISTICS.SUPPLY_TYPE.MISSILES and "missiles" or
                   supplyType == IADS_LOGISTICS.SUPPLY_TYPE.FUEL and "fuel" or "spareParts"

        if depot.inventory[key] < amount then
            SAM_UTILS.debug("[Logistics] Insufficient " .. supplyType .. " at depot")
            return nil
        end
    end

    -- ルート取得または生成
    local routeKey = depotName .. "_" .. samName
    local route = self.supplyRoutes[routeKey]
    if not route then
        route = self:generateDirectRoute(depotName, samName)
    end

    -- 車列作成
    local convoy = {
        id = self.nextConvoyId,
        depotName = depotName,
        samName = samName,
        supplies = supplies,
        status = IADS_LOGISTICS.VEHICLE_STATUS.LOADING,
        route = route,
        currentPosition = depot.position,
        progress = 0,  -- 0-1
        departureTime = nil,
        estimatedArrival = nil,
        loadingStartTime = timer.getTime()
    }

    self.nextConvoyId = self.nextConvoyId + 1

    -- デポから在庫を引く
    for supplyType, amount in pairs(supplies) do
        local key = supplyType == IADS_LOGISTICS.SUPPLY_TYPE.MISSILES and "missiles" or
                   supplyType == IADS_LOGISTICS.SUPPLY_TYPE.FUEL and "fuel" or "spareParts"
        depot.inventory[key] = depot.inventory[key] - amount
    end

    depot.vehiclesAvailable = depot.vehiclesAvailable - 1

    self.convoys[convoy.id] = convoy

    if self.callbacks.onConvoyDispatched then
        self.callbacks.onConvoyDispatched(convoy)
    end

    SAM_UTILS.debug("[Logistics] Convoy dispatched: " .. depot.name .. " -> " .. samName)
    return convoy
end

-- ============================================
-- 車列位置更新
-- ============================================
function IADS_LOGISTICS:updateConvoyPosition(convoy, deltaTime)
    if convoy.status == IADS_LOGISTICS.VEHICLE_STATUS.LOADING then
        -- 積み込み完了チェック
        local depot = self.depots[convoy.depotName]
        if (timer.getTime() - convoy.loadingStartTime) >= depot.loadingTime then
            convoy.status = IADS_LOGISTICS.VEHICLE_STATUS.EN_ROUTE
            convoy.departureTime = timer.getTime()
            convoy.estimatedArrival = convoy.departureTime + convoy.route.estimatedTime
        end
        return
    end

    if convoy.status == IADS_LOGISTICS.VEHICLE_STATUS.EN_ROUTE then
        -- 移動
        local distancePerTick = self.convoySpeed * deltaTime
        local totalDistance = convoy.route.totalDistance

        convoy.progress = convoy.progress + (distancePerTick / totalDistance)

        if convoy.progress >= 1 then
            convoy.progress = 1
            convoy.status = IADS_LOGISTICS.VEHICLE_STATUS.UNLOADING
            convoy.unloadingStartTime = timer.getTime()
            SAM_UTILS.debug("[Logistics] Convoy arrived at: " .. convoy.samName)
        end

        -- 現在位置計算（補間）
        local depot = self.depots[convoy.depotName]
        local sam = self.samResources[convoy.samName]

        convoy.currentPosition = {
            x = depot.position.x + (sam.position.x - depot.position.x) * convoy.progress,
            z = depot.position.z + (sam.position.z - depot.position.z) * convoy.progress
        }

        return
    end

    if convoy.status == IADS_LOGISTICS.VEHICLE_STATUS.UNLOADING then
        -- 荷下ろし完了チェック（積み込みの半分の時間）
        local depot = self.depots[convoy.depotName]
        if (timer.getTime() - convoy.unloadingStartTime) >= (depot.loadingTime / 2) then
            -- 補給適用
            self:applySupply(convoy)
            convoy.status = IADS_LOGISTICS.VEHICLE_STATUS.RETURNING
            convoy.returnStartTime = timer.getTime()
        end
        return
    end

    if convoy.status == IADS_LOGISTICS.VEHICLE_STATUS.RETURNING then
        -- 帰還
        local distancePerTick = self.convoySpeed * deltaTime
        local totalDistance = convoy.route.totalDistance

        convoy.progress = convoy.progress - (distancePerTick / totalDistance)

        if convoy.progress <= 0 then
            -- 帰還完了
            convoy.progress = 0
            convoy.status = IADS_LOGISTICS.VEHICLE_STATUS.IDLE

            -- 車両をデポに戻す
            local depot = self.depots[convoy.depotName]
            depot.vehiclesAvailable = depot.vehiclesAvailable + 1

            -- 車列を削除
            self.convoys[convoy.id] = nil

            SAM_UTILS.debug("[Logistics] Convoy returned to: " .. depot.name)
        end
    end
end

-- ============================================
-- 補給適用
-- ============================================
function IADS_LOGISTICS:applySupply(convoy)
    local sam = self.samResources[convoy.samName]
    if not sam then return end

    for supplyType, amount in pairs(convoy.supplies) do
        if supplyType == IADS_LOGISTICS.SUPPLY_TYPE.MISSILES then
            sam.missiles = math.min(100, sam.missiles + amount)

            -- 弾薬システムにも反映
            if self.ammoSystem then
                self.ammoSystem:reloadNow(convoy.samName)
            end
        elseif supplyType == IADS_LOGISTICS.SUPPLY_TYPE.FUEL then
            sam.fuel = math.min(100, sam.fuel + amount)
        elseif supplyType == IADS_LOGISTICS.SUPPLY_TYPE.SPARE_PARTS then
            sam.spareParts = math.min(100, sam.spareParts + amount)
        end
    end

    sam.lastResupply = timer.getTime()

    if self.callbacks.onConvoyArrived then
        self.callbacks.onConvoyArrived(convoy)
    end

    SAM_UTILS.debug("[Logistics] Supply delivered to: " .. convoy.samName)
end

-- ============================================
-- 車列破壊
-- ============================================
function IADS_LOGISTICS:destroyConvoy(convoyId)
    local convoy = self.convoys[convoyId]
    if not convoy then return false end

    convoy.status = IADS_LOGISTICS.VEHICLE_STATUS.DESTROYED

    -- 補給品は失われる
    convoy.supplies = {}

    if self.callbacks.onConvoyDestroyed then
        self.callbacks.onConvoyDestroyed(convoy)
    end

    SAM_UTILS.debug("[Logistics] Convoy destroyed: " .. convoyId)
    return true
end

-- ============================================
-- 燃料消費更新
-- ============================================
function IADS_LOGISTICS:updateFuelConsumption(deltaTime)
    for name, sam in pairs(self.samResources) do
        -- アクティブなSAMのみ燃料消費
        if self.network and self.network.samSites then
            local samData = self.network.samSites[name]
            if samData and samData.state == "GREEN" then
                local consumption = sam.fuelConsumptionRate * (deltaTime / 3600)
                sam.fuel = math.max(0, sam.fuel - consumption)

                -- 燃料切れで非活性化
                if sam.fuel <= 0 then
                    sam.isOperational = false

                    if self.callbacks.onResourceCritical then
                        self.callbacks.onResourceCritical(name, "FUEL", 0)
                    end
                end
            end
        end
    end
end

-- ============================================
-- 自動補給チェック
-- ============================================
function IADS_LOGISTICS:checkAutoResupply()
    if not self.autoResupply then return end

    for name, sam in pairs(self.samResources) do
        -- ミサイル補給チェック
        if sam.missiles <= self.resupplyThreshold then
            local hasRequest = false
            for _, req in ipairs(self.pendingRequests) do
                if req.samName == name and req.supplyType == IADS_LOGISTICS.SUPPLY_TYPE.MISSILES then
                    hasRequest = true
                    break
                end
            end

            if not hasRequest then
                local priority = sam.missiles <= 20 and
                    IADS_LOGISTICS.PRIORITY.CRITICAL or IADS_LOGISTICS.PRIORITY.HIGH
                self:requestSupply(name, IADS_LOGISTICS.SUPPLY_TYPE.MISSILES,
                    100 - sam.missiles, priority)
            end
        end

        -- 燃料補給チェック
        if sam.fuel <= self.resupplyThreshold then
            local hasRequest = false
            for _, req in ipairs(self.pendingRequests) do
                if req.samName == name and req.supplyType == IADS_LOGISTICS.SUPPLY_TYPE.FUEL then
                    hasRequest = true
                    break
                end
            end

            if not hasRequest then
                local priority = sam.fuel <= 20 and
                    IADS_LOGISTICS.PRIORITY.CRITICAL or IADS_LOGISTICS.PRIORITY.HIGH
                self:requestSupply(name, IADS_LOGISTICS.SUPPLY_TYPE.FUEL,
                    100 - sam.fuel, priority)
            end
        end
    end
end

-- ============================================
-- 補給要請処理
-- ============================================
function IADS_LOGISTICS:processRequests()
    local processedRequests = {}

    for i, request in ipairs(self.pendingRequests) do
        if request.status == "PENDING" then
            -- 最も近いデポを検索
            local sam = self.samResources[request.samName]
            if sam then
                local bestDepot = nil
                local bestDistance = math.huge

                for depotName, depot in pairs(self.depots) do
                    if depot.isActive and depot.vehiclesAvailable > 0 then
                        local dx = depot.position.x - sam.position.x
                        local dz = depot.position.z - sam.position.z
                        local distance = math.sqrt(dx * dx + dz * dz)

                        if distance < bestDistance then
                            bestDistance = distance
                            bestDepot = depotName
                        end
                    end
                end

                if bestDepot then
                    local supplies = {}
                    supplies[request.supplyType] = request.amount

                    local convoy = self:dispatchConvoy(bestDepot, request.samName, supplies)
                    if convoy then
                        request.status = "DISPATCHED"
                        request.assignedConvoy = convoy.id
                        table.insert(processedRequests, i)
                    end
                end
            end
        end
    end

    -- 処理済み要請を削除（逆順で）
    for i = #processedRequests, 1, -1 do
        table.remove(self.pendingRequests, processedRequests[i])
    end
end

-- ============================================
-- コールバック設定
-- ============================================
function IADS_LOGISTICS:setCallback(event, handler)
    if self.callbacks[event] ~= nil then
        self.callbacks[event] = handler
    end
end

-- ============================================
-- 定期更新スケジュール
-- ============================================
function IADS_LOGISTICS:scheduleUpdate()
    if not self.isRunning then return end

    timer.scheduleFunction(function()
        self:update()
        self:scheduleUpdate()
    end, nil, timer.getTime() + self.updateInterval)
end

-- ============================================
-- 更新処理
-- ============================================
function IADS_LOGISTICS:update()
    local now = timer.getTime()
    local deltaTime = now - self.lastUpdate
    self.lastUpdate = now

    -- 燃料消費
    self:updateFuelConsumption(deltaTime)

    -- 車列位置更新
    for id, convoy in pairs(self.convoys) do
        if convoy.status ~= IADS_LOGISTICS.VEHICLE_STATUS.DESTROYED then
            self:updateConvoyPosition(convoy, deltaTime)
        end
    end

    -- 自動補給チェック
    self:checkAutoResupply()

    -- 補給要請処理
    self:processRequests()
end

-- ============================================
-- 停止
-- ============================================
function IADS_LOGISTICS:stop()
    self.isRunning = false
    SAM_UTILS.debug("[Logistics] System stopped")
end

-- ============================================
-- ステータス表示
-- ============================================
function IADS_LOGISTICS:printStatus()
    local text = "=== Logistics System Status ===\n"
    text = text .. string.format("Depots: %d\n", SAM_UTILS.tableLength(self.depots))
    text = text .. string.format("Active Convoys: %d\n", SAM_UTILS.tableLength(self.convoys))
    text = text .. string.format("Pending Requests: %d\n", #self.pendingRequests)

    text = text .. "\n--- Depot Status ---\n"
    for name, depot in pairs(self.depots) do
        text = text .. string.format("  %s (%s)\n", name, depot.type)
        text = text .. string.format("    Vehicles: %d/%d\n", depot.vehiclesAvailable, depot.vehicles)
        text = text .. string.format("    Missiles: %d\n", depot.inventory.missiles)
        text = text .. string.format("    Fuel: %d\n", depot.inventory.fuel)
    end

    text = text .. "\n--- SAM Resources ---\n"
    for name, sam in pairs(self.samResources) do
        text = text .. string.format("  %s\n", name)
        text = text .. string.format("    Fuel: %.1f%%  Missiles: %.1f%%  Parts: %.1f%%\n",
            sam.fuel, sam.missiles, sam.spareParts)
    end

    if SAM_UTILS.tableLength(self.convoys) > 0 then
        text = text .. "\n--- Active Convoys ---\n"
        for id, convoy in pairs(self.convoys) do
            text = text .. string.format("  #%d: %s -> %s (%s, %.0f%%)\n",
                id, convoy.depotName, convoy.samName, convoy.status,
                convoy.progress * 100)
        end
    end

    text = text .. "==============================="
    trigger.action.outText(text, 15)
end

-- ============================================
-- 統合関数: 補給システム作成
-- ============================================
function createLogisticsSystem(network, options)
    local logistics = IADS_LOGISTICS.new(network)
    logistics:init(options)
    return logistics
end
