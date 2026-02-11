--[[
    DCS IADS Network Resilience Simulation
    ネットワーク劣化/回復シミュレーション

    データリンクノードの破壊や通信ジャミングによる
    ネットワーク分断と冗長経路による回復をシミュレート

    機能:
    - ネットワークトポロジー管理
    - ノード破壊時の影響伝播
    - 通信ジャミングによる孤立化
    - 冗長経路の自動切り替え
    - ネットワーク分断検出
    - 回復シミュレーション

    依存: core/utils.lua, iads/network.lua, iads/datalink.lua
]]

IADS_NETWORK_RESILIENCE = {}
IADS_NETWORK_RESILIENCE.__index = IADS_NETWORK_RESILIENCE

-- ============================================
-- ノード種別
-- ============================================
IADS_NETWORK_RESILIENCE.NODE_TYPE = {
    COMMAND_CENTER = "COMMAND_CENTER",   -- 指揮所（最重要）
    EWR = "EWR",                         -- 早期警戒レーダー
    SAM = "SAM",                         -- SAMサイト
    RELAY = "RELAY",                     -- 中継ノード
    BACKUP = "BACKUP"                    -- バックアップノード
}

-- ============================================
-- ノード状態
-- ============================================
IADS_NETWORK_RESILIENCE.NODE_STATUS = {
    ONLINE = "ONLINE",           -- オンライン
    DEGRADED = "DEGRADED",       -- 劣化
    JAMMED = "JAMMED",           -- ジャミング中
    ISOLATED = "ISOLATED",       -- 孤立
    OFFLINE = "OFFLINE",         -- オフライン
    DESTROYED = "DESTROYED"      -- 破壊
}

-- ============================================
-- リンク状態
-- ============================================
IADS_NETWORK_RESILIENCE.LINK_STATUS = {
    ACTIVE = "ACTIVE",           -- アクティブ
    DEGRADED = "DEGRADED",       -- 劣化
    JAMMED = "JAMMED",           -- ジャミング
    FAILED = "FAILED"            -- 切断
}

-- ============================================
-- ネットワーク健全性レベル
-- ============================================
IADS_NETWORK_RESILIENCE.HEALTH_LEVEL = {
    OPTIMAL = "OPTIMAL",         -- 最適
    GOOD = "GOOD",               -- 良好
    DEGRADED = "DEGRADED",       -- 劣化
    CRITICAL = "CRITICAL",       -- 危機的
    FAILED = "FAILED"            -- 機能停止
}

-- ============================================
-- ネットワーク回復性システム作成
-- ============================================
function IADS_NETWORK_RESILIENCE.new(iadsNetwork)
    local self = setmetatable({}, IADS_NETWORK_RESILIENCE)

    self.network = iadsNetwork
    self.nodes = {}                       -- ノードリスト
    self.links = {}                       -- リンクリスト
    self.topology = {}                    -- 接続トポロジー
    self.redundantPaths = {}              -- 冗長経路
    self.jammedAreas = {}                 -- ジャミングエリア
    self.isolatedNodes = {}               -- 孤立ノード
    self.networkHealth = IADS_NETWORK_RESILIENCE.HEALTH_LEVEL.OPTIMAL
    self.updateInterval = 3               -- 更新間隔（秒）
    self.autoReroute = true               -- 自動経路再設定
    self.maxHops = 5                      -- 最大ホップ数
    self.isRunning = false
    self.lastUpdate = 0

    -- コールバック
    self.callbacks = {
        onNodeStatusChange = nil,
        onLinkStatusChange = nil,
        onNetworkDegraded = nil,
        onNodeIsolated = nil,
        onPathRerouted = nil
    }

    return self
end

-- ============================================
-- 初期化
-- ============================================
function IADS_NETWORK_RESILIENCE:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end
    if options.autoReroute ~= nil then
        self.autoReroute = options.autoReroute
    end
    if options.maxHops then
        self.maxHops = options.maxHops
    end

    -- IADSネットワークからノードを初期化
    if self.network then
        self:initializeFromNetwork()
    end

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[NetworkResilience] System initialized")
    return self
end

-- ============================================
-- ネットワークからノード初期化
-- ============================================
function IADS_NETWORK_RESILIENCE:initializeFromNetwork()
    -- SAMサイトをノードとして追加
    if self.network.samSites then
        for name, samData in pairs(self.network.samSites) do
            self:addNode(name, IADS_NETWORK_RESILIENCE.NODE_TYPE.SAM, {
                position = samData.position,
                range = samData.range or 40000
            })
        end
    end

    -- EWRをノードとして追加
    if self.network.ewrSites then
        for name, ewrData in pairs(self.network.ewrSites) do
            self:addNode(name, IADS_NETWORK_RESILIENCE.NODE_TYPE.EWR, {
                position = ewrData.position,
                range = ewrData.range or 300000
            })
        end
    end

    -- 既存リンクを追加
    if self.network.samToEwrLinks then
        for samName, ewrLinks in pairs(self.network.samToEwrLinks) do
            for ewrName, _ in pairs(ewrLinks) do
                self:addLink(samName, ewrName)
            end
        end
    end

    -- 距離ベースで追加リンクを生成
    self:generateProximityLinks(150000)  -- 150km以内を接続
end

-- ============================================
-- ノード追加
-- ============================================
function IADS_NETWORK_RESILIENCE:addNode(name, nodeType, data)
    data = data or {}

    self.nodes[name] = {
        name = name,
        type = nodeType,
        status = IADS_NETWORK_RESILIENCE.NODE_STATUS.ONLINE,
        position = data.position,
        range = data.range,
        commRange = data.commRange or 200000,  -- 通信可能距離
        connectedNodes = {},
        primaryPath = nil,
        backupPaths = {},
        health = 100,
        lastUpdate = timer.getTime()
    }

    self.topology[name] = {}

    SAM_UTILS.debug("[NetworkResilience] Node added: " .. name)
    return self.nodes[name]
end

-- ============================================
-- リンク追加
-- ============================================
function IADS_NETWORK_RESILIENCE:addLink(node1Name, node2Name, options)
    options = options or {}

    local linkId = self:getLinkId(node1Name, node2Name)

    if self.links[linkId] then
        return self.links[linkId]  -- 既存リンク
    end

    local node1 = self.nodes[node1Name]
    local node2 = self.nodes[node2Name]

    if not node1 or not node2 then
        return nil
    end

    -- 距離計算
    local distance = 0
    if node1.position and node2.position then
        local dx = node2.position.x - node1.position.x
        local dz = node2.position.z - node1.position.z
        distance = math.sqrt(dx * dx + dz * dz)
    end

    self.links[linkId] = {
        id = linkId,
        node1 = node1Name,
        node2 = node2Name,
        status = IADS_NETWORK_RESILIENCE.LINK_STATUS.ACTIVE,
        distance = distance,
        bandwidth = options.bandwidth or 100,
        latency = options.latency or (distance / 300000 * 1000),  -- ms
        isPrimary = options.isPrimary or true,
        health = 100
    }

    -- トポロジー更新
    if not self.topology[node1Name] then
        self.topology[node1Name] = {}
    end
    if not self.topology[node2Name] then
        self.topology[node2Name] = {}
    end

    self.topology[node1Name][node2Name] = true
    self.topology[node2Name][node1Name] = true

    -- ノードの接続リスト更新
    node1.connectedNodes[node2Name] = true
    node2.connectedNodes[node1Name] = true

    return self.links[linkId]
end

-- ============================================
-- リンクID取得
-- ============================================
function IADS_NETWORK_RESILIENCE:getLinkId(node1, node2)
    if node1 < node2 then
        return node1 .. "_" .. node2
    else
        return node2 .. "_" .. node1
    end
end

-- ============================================
-- 近接リンク自動生成
-- ============================================
function IADS_NETWORK_RESILIENCE:generateProximityLinks(maxDistance)
    for name1, node1 in pairs(self.nodes) do
        for name2, node2 in pairs(self.nodes) do
            if name1 ~= name2 and node1.position and node2.position then
                local dx = node2.position.x - node1.position.x
                local dz = node2.position.z - node1.position.z
                local distance = math.sqrt(dx * dx + dz * dz)

                if distance <= maxDistance then
                    self:addLink(name1, name2)
                end
            end
        end
    end
end

-- ============================================
-- ノード破壊
-- ============================================
function IADS_NETWORK_RESILIENCE:destroyNode(nodeName)
    local node = self.nodes[nodeName]
    if not node then return end

    local oldStatus = node.status
    node.status = IADS_NETWORK_RESILIENCE.NODE_STATUS.DESTROYED
    node.health = 0

    -- 接続リンクを切断
    for connectedName, _ in pairs(node.connectedNodes) do
        local linkId = self:getLinkId(nodeName, connectedName)
        if self.links[linkId] then
            self.links[linkId].status = IADS_NETWORK_RESILIENCE.LINK_STATUS.FAILED
        end
    end

    -- 影響を伝播
    self:propagateNodeFailure(nodeName)

    -- コールバック
    if self.callbacks.onNodeStatusChange then
        self.callbacks.onNodeStatusChange(nodeName, oldStatus, node.status)
    end

    SAM_UTILS.debug("[NetworkResilience] Node destroyed: " .. nodeName)
    return true
end

-- ============================================
-- ノード障害の影響伝播
-- ============================================
function IADS_NETWORK_RESILIENCE:propagateNodeFailure(failedNodeName)
    -- 孤立チェック
    self:detectIsolatedNodes()

    -- 自動経路再設定
    if self.autoReroute then
        self:rerouteAllPaths()
    end

    -- ネットワーク健全性更新
    self:updateNetworkHealth()
end

-- ============================================
-- 通信ジャミング適用
-- ============================================
function IADS_NETWORK_RESILIENCE:applyJamming(position, radius, power)
    power = power or 100

    local jamArea = {
        position = position,
        radius = radius,
        power = power,
        affectedNodes = {},
        affectedLinks = {},
        startTime = timer.getTime()
    }

    -- 影響を受けるノードを特定
    for name, node in pairs(self.nodes) do
        if node.position then
            local dx = position.x - node.position.x
            local dz = position.z - node.position.z
            local distance = math.sqrt(dx * dx + dz * dz)

            if distance <= radius then
                -- ジャミング効果計算（距離による減衰）
                local effect = power * (1 - distance / radius)

                if effect > 50 then
                    local oldStatus = node.status
                    node.status = IADS_NETWORK_RESILIENCE.NODE_STATUS.JAMMED
                    jamArea.affectedNodes[name] = effect

                    if self.callbacks.onNodeStatusChange then
                        self.callbacks.onNodeStatusChange(name, oldStatus, node.status)
                    end
                elseif effect > 20 then
                    if node.status == IADS_NETWORK_RESILIENCE.NODE_STATUS.ONLINE then
                        node.status = IADS_NETWORK_RESILIENCE.NODE_STATUS.DEGRADED
                    end
                    jamArea.affectedNodes[name] = effect
                end
            end
        end
    end

    -- 影響を受けるリンクを特定
    for linkId, link in pairs(self.links) do
        local node1 = self.nodes[link.node1]
        local node2 = self.nodes[link.node2]

        if jamArea.affectedNodes[link.node1] or jamArea.affectedNodes[link.node2] then
            local oldStatus = link.status
            link.status = IADS_NETWORK_RESILIENCE.LINK_STATUS.JAMMED
            jamArea.affectedLinks[linkId] = true

            if self.callbacks.onLinkStatusChange then
                self.callbacks.onLinkStatusChange(linkId, oldStatus, link.status)
            end
        end
    end

    table.insert(self.jammedAreas, jamArea)

    -- 影響を伝播
    self:detectIsolatedNodes()
    self:updateNetworkHealth()

    SAM_UTILS.debug("[NetworkResilience] Jamming applied at position, radius=" .. radius)
    return jamArea
end

-- ============================================
-- ジャミング解除
-- ============================================
function IADS_NETWORK_RESILIENCE:removeJamming(jamAreaIndex)
    local jamArea = self.jammedAreas[jamAreaIndex]
    if not jamArea then return end

    -- 影響を受けていたノードを回復
    for nodeName, _ in pairs(jamArea.affectedNodes) do
        local node = self.nodes[nodeName]
        if node and node.status == IADS_NETWORK_RESILIENCE.NODE_STATUS.JAMMED then
            node.status = IADS_NETWORK_RESILIENCE.NODE_STATUS.ONLINE
        end
    end

    -- 影響を受けていたリンクを回復
    for linkId, _ in pairs(jamArea.affectedLinks) do
        local link = self.links[linkId]
        if link and link.status == IADS_NETWORK_RESILIENCE.LINK_STATUS.JAMMED then
            link.status = IADS_NETWORK_RESILIENCE.LINK_STATUS.ACTIVE
        end
    end

    table.remove(self.jammedAreas, jamAreaIndex)

    self:detectIsolatedNodes()
    self:updateNetworkHealth()

    SAM_UTILS.debug("[NetworkResilience] Jamming removed")
end

-- ============================================
-- 孤立ノード検出
-- ============================================
function IADS_NETWORK_RESILIENCE:detectIsolatedNodes()
    self.isolatedNodes = {}

    -- BFSで接続性チェック
    local visited = {}
    local queue = {}

    -- 指揮所またはオンラインのEWRを起点に
    local startNode = nil
    for name, node in pairs(self.nodes) do
        if node.type == IADS_NETWORK_RESILIENCE.NODE_TYPE.COMMAND_CENTER and
           node.status == IADS_NETWORK_RESILIENCE.NODE_STATUS.ONLINE then
            startNode = name
            break
        end
    end

    if not startNode then
        for name, node in pairs(self.nodes) do
            if node.type == IADS_NETWORK_RESILIENCE.NODE_TYPE.EWR and
               node.status == IADS_NETWORK_RESILIENCE.NODE_STATUS.ONLINE then
                startNode = name
                break
            end
        end
    end

    if not startNode then
        -- 全ノード孤立
        for name, node in pairs(self.nodes) do
            if node.status ~= IADS_NETWORK_RESILIENCE.NODE_STATUS.DESTROYED then
                self.isolatedNodes[name] = true
                node.status = IADS_NETWORK_RESILIENCE.NODE_STATUS.ISOLATED
            end
        end
        return
    end

    -- BFS実行
    table.insert(queue, startNode)
    visited[startNode] = true

    while #queue > 0 do
        local current = table.remove(queue, 1)

        for connected, _ in pairs(self.topology[current] or {}) do
            if not visited[connected] then
                local linkId = self:getLinkId(current, connected)
                local link = self.links[linkId]
                local connectedNode = self.nodes[connected]

                -- アクティブなリンクとオンラインのノードのみ通過
                if link and connectedNode and
                   link.status == IADS_NETWORK_RESILIENCE.LINK_STATUS.ACTIVE and
                   connectedNode.status ~= IADS_NETWORK_RESILIENCE.NODE_STATUS.DESTROYED then
                    visited[connected] = true
                    table.insert(queue, connected)
                end
            end
        end
    end

    -- 訪問されなかったノードは孤立
    for name, node in pairs(self.nodes) do
        if not visited[name] and
           node.status ~= IADS_NETWORK_RESILIENCE.NODE_STATUS.DESTROYED then
            self.isolatedNodes[name] = true

            if node.status ~= IADS_NETWORK_RESILIENCE.NODE_STATUS.JAMMED then
                local oldStatus = node.status
                node.status = IADS_NETWORK_RESILIENCE.NODE_STATUS.ISOLATED

                if self.callbacks.onNodeIsolated then
                    self.callbacks.onNodeIsolated(name)
                end
            end
        end
    end
end

-- ============================================
-- 全経路再設定
-- ============================================
function IADS_NETWORK_RESILIENCE:rerouteAllPaths()
    for nodeName, node in pairs(self.nodes) do
        if node.type == IADS_NETWORK_RESILIENCE.NODE_TYPE.SAM then
            local newPath = self:findBestPath(nodeName)
            if newPath then
                node.primaryPath = newPath

                if self.callbacks.onPathRerouted then
                    self.callbacks.onPathRerouted(nodeName, newPath)
                end
            end
        end
    end
end

-- ============================================
-- 最適経路検索（Dijkstra）
-- ============================================
function IADS_NETWORK_RESILIENCE:findBestPath(fromNode, toNodeType)
    toNodeType = toNodeType or IADS_NETWORK_RESILIENCE.NODE_TYPE.EWR

    local distances = {}
    local previous = {}
    local unvisited = {}

    for name, _ in pairs(self.nodes) do
        distances[name] = math.huge
        unvisited[name] = true
    end
    distances[fromNode] = 0

    while SAM_UTILS.tableLength(unvisited) > 0 do
        -- 最小距離のノードを選択
        local minDist = math.huge
        local current = nil
        for name, _ in pairs(unvisited) do
            if distances[name] < minDist then
                minDist = distances[name]
                current = name
            end
        end

        if not current or distances[current] == math.huge then
            break  -- 到達不能
        end

        unvisited[current] = nil

        -- 目標タイプに到達したか
        local currentNode = self.nodes[current]
        if currentNode and currentNode.type == toNodeType and
           currentNode.status == IADS_NETWORK_RESILIENCE.NODE_STATUS.ONLINE then
            -- 経路を構築
            local path = {}
            local node = current
            while node do
                table.insert(path, 1, node)
                node = previous[node]
            end
            return path
        end

        -- 隣接ノードを更新
        for neighbor, _ in pairs(self.topology[current] or {}) do
            if unvisited[neighbor] then
                local linkId = self:getLinkId(current, neighbor)
                local link = self.links[linkId]
                local neighborNode = self.nodes[neighbor]

                if link and neighborNode and
                   link.status == IADS_NETWORK_RESILIENCE.LINK_STATUS.ACTIVE and
                   neighborNode.status ~= IADS_NETWORK_RESILIENCE.NODE_STATUS.DESTROYED then
                    local alt = distances[current] + link.distance
                    if alt < distances[neighbor] then
                        distances[neighbor] = alt
                        previous[neighbor] = current
                    end
                end
            end
        end
    end

    return nil  -- 経路なし
end

-- ============================================
-- ネットワーク健全性更新
-- ============================================
function IADS_NETWORK_RESILIENCE:updateNetworkHealth()
    local totalNodes = SAM_UTILS.tableLength(self.nodes)
    local onlineNodes = 0
    local degradedNodes = 0
    local isolatedNodes = SAM_UTILS.tableLength(self.isolatedNodes)

    for _, node in pairs(self.nodes) do
        if node.status == IADS_NETWORK_RESILIENCE.NODE_STATUS.ONLINE then
            onlineNodes = onlineNodes + 1
        elseif node.status == IADS_NETWORK_RESILIENCE.NODE_STATUS.DEGRADED then
            degradedNodes = degradedNodes + 1
        end
    end

    local healthRatio = (onlineNodes + degradedNodes * 0.5) / totalNodes

    local oldHealth = self.networkHealth

    if healthRatio >= 0.9 then
        self.networkHealth = IADS_NETWORK_RESILIENCE.HEALTH_LEVEL.OPTIMAL
    elseif healthRatio >= 0.7 then
        self.networkHealth = IADS_NETWORK_RESILIENCE.HEALTH_LEVEL.GOOD
    elseif healthRatio >= 0.5 then
        self.networkHealth = IADS_NETWORK_RESILIENCE.HEALTH_LEVEL.DEGRADED
    elseif healthRatio >= 0.2 then
        self.networkHealth = IADS_NETWORK_RESILIENCE.HEALTH_LEVEL.CRITICAL
    else
        self.networkHealth = IADS_NETWORK_RESILIENCE.HEALTH_LEVEL.FAILED
    end

    if oldHealth ~= self.networkHealth and self.callbacks.onNetworkDegraded then
        self.callbacks.onNetworkDegraded(oldHealth, self.networkHealth)
    end
end

-- ============================================
-- コールバック設定
-- ============================================
function IADS_NETWORK_RESILIENCE:setCallback(event, handler)
    if self.callbacks[event] ~= nil then
        self.callbacks[event] = handler
    end
end

-- ============================================
-- 定期更新スケジュール
-- ============================================
function IADS_NETWORK_RESILIENCE:scheduleUpdate()
    if not self.isRunning then return end

    timer.scheduleFunction(function()
        self:update()
        self:scheduleUpdate()
    end, nil, timer.getTime() + self.updateInterval)
end

-- ============================================
-- 更新処理
-- ============================================
function IADS_NETWORK_RESILIENCE:update()
    self.lastUpdate = timer.getTime()

    -- ジャミングエリアの自動減衰（オプション）
    for i = #self.jammedAreas, 1, -1 do
        local jamArea = self.jammedAreas[i]
        -- 必要に応じてジャミング効果を減衰
    end

    -- 孤立ノード再チェック
    self:detectIsolatedNodes()
    self:updateNetworkHealth()
end

-- ============================================
-- 停止
-- ============================================
function IADS_NETWORK_RESILIENCE:stop()
    self.isRunning = false
    SAM_UTILS.debug("[NetworkResilience] System stopped")
end

-- ============================================
-- ステータス表示
-- ============================================
function IADS_NETWORK_RESILIENCE:printStatus()
    local text = "=== Network Resilience System Status ===\n"
    text = text .. string.format("Network Health: %s\n", self.networkHealth)
    text = text .. string.format("Total Nodes: %d\n", SAM_UTILS.tableLength(self.nodes))
    text = text .. string.format("Total Links: %d\n", SAM_UTILS.tableLength(self.links))
    text = text .. string.format("Isolated Nodes: %d\n", SAM_UTILS.tableLength(self.isolatedNodes))
    text = text .. string.format("Active Jamming Areas: %d\n", #self.jammedAreas)

    -- ノード状態サマリー
    local statusCounts = {}
    for _, node in pairs(self.nodes) do
        statusCounts[node.status] = (statusCounts[node.status] or 0) + 1
    end

    text = text .. "\n--- Node Status Summary ---\n"
    for status, count in pairs(statusCounts) do
        text = text .. string.format("  %s: %d\n", status, count)
    end

    -- 孤立ノードリスト
    if SAM_UTILS.tableLength(self.isolatedNodes) > 0 then
        text = text .. "\n--- Isolated Nodes ---\n"
        for nodeName, _ in pairs(self.isolatedNodes) do
            text = text .. "  " .. nodeName .. "\n"
        end
    end

    text = text .. "========================================"
    trigger.action.outText(text, 15)
end

-- ============================================
-- 統合関数: ネットワーク回復性システム作成
-- ============================================
function createNetworkResilienceSystem(network, options)
    local resilience = IADS_NETWORK_RESILIENCE.new(network)
    resilience:init(options)
    return resilience
end
