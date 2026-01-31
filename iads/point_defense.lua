--[[
    DCS IADS Point Defense System
    ポイントディフェンス連携システム

    高価値目標（HVT: High Value Target）を防護対象として登録し、
    脅威が接近した際に周囲のSAMを自動でアクティブ化する

    機能:
    - 高価値目標の登録と管理
    - 防護優先度の設定
    - 脅威接近時の自動SAMアクティブ化
    - 防護範囲の動的調整
    - 複数レイヤー防護（長距離/中距離/近距離SAM）

    依存: core/utils.lua, iads/network.lua
]]

IADS_POINT_DEFENSE = {}
IADS_POINT_DEFENSE.__index = IADS_POINT_DEFENSE

-- ============================================
-- 防護対象タイプ
-- ============================================
IADS_POINT_DEFENSE.TARGET_TYPE = {
    AIRBASE = "AIRBASE",           -- 飛行場
    COMMAND = "COMMAND",           -- 指揮所
    RADAR = "RADAR",               -- レーダーサイト
    SUPPLY = "SUPPLY",             -- 補給拠点
    INFRASTRUCTURE = "INFRASTRUCTURE", -- インフラ（橋、発電所等）
    UNIT = "UNIT",                 -- ユニット（艦艇、車両等）
    ZONE = "ZONE",                 -- カスタムゾーン
    CUSTOM = "CUSTOM"              -- その他
}

-- ============================================
-- 防護レイヤー
-- ============================================
IADS_POINT_DEFENSE.LAYER = {
    LONG_RANGE = "LONG_RANGE",     -- 長距離SAM (S-300, Patriot等)
    MEDIUM_RANGE = "MEDIUM_RANGE", -- 中距離SAM (SA-11, Hawk等)
    SHORT_RANGE = "SHORT_RANGE",   -- 短距離SAM (SA-8, SA-15等)
    SHORAD = "SHORAD"              -- 近接防空 (SA-19, Roland等)
}

-- ============================================
-- 防護状態
-- ============================================
IADS_POINT_DEFENSE.STATUS = {
    SAFE = "SAFE",                 -- 安全（脅威なし）
    ALERT = "ALERT",               -- 警戒（脅威接近中）
    ENGAGED = "ENGAGED",           -- 交戦中
    COMPROMISED = "COMPROMISED"    -- 防護困難（SAM不足等）
}

-- ============================================
-- ポイントディフェンスシステム作成
-- ============================================
function IADS_POINT_DEFENSE.new(iadsNetwork)
    local self = setmetatable({}, IADS_POINT_DEFENSE)

    self.network = iadsNetwork
    self.targets = {}                -- 防護対象
    self.assignments = {}            -- SAM割り当て
    self.updateInterval = 3          -- 更新間隔（秒）
    self.threatRangeMultiplier = 1.5 -- 脅威検知範囲倍率
    self.autoActivate = true         -- 自動アクティブ化
    self.layeredDefense = true       -- 多層防護有効
    self.isRunning = false

    -- レイヤー別の距離設定（メートル）
    self.layerRanges = {
        [IADS_POINT_DEFENSE.LAYER.LONG_RANGE] = {min = 50000, max = 150000},
        [IADS_POINT_DEFENSE.LAYER.MEDIUM_RANGE] = {min = 20000, max = 60000},
        [IADS_POINT_DEFENSE.LAYER.SHORT_RANGE] = {min = 5000, max = 25000},
        [IADS_POINT_DEFENSE.LAYER.SHORAD] = {min = 0, max = 10000}
    }

    return self
end

-- ============================================
-- 初期化
-- ============================================
function IADS_POINT_DEFENSE:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end
    if options.autoActivate ~= nil then
        self.autoActivate = options.autoActivate
    end
    if options.layeredDefense ~= nil then
        self.layeredDefense = options.layeredDefense
    end
    if options.threatRangeMultiplier then
        self.threatRangeMultiplier = options.threatRangeMultiplier
    end

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[PointDefense] System initialized")
    return self
end

-- ============================================
-- 防護対象を追加（ユニット）
-- ============================================
function IADS_POINT_DEFENSE:addTarget(unit, options)
    if not unit then return nil end

    options = options or {}
    local unitName = unit:getName()

    local target = {
        id = unitName,
        unit = unit,
        type = options.type or IADS_POINT_DEFENSE.TARGET_TYPE.UNIT,
        priority = options.priority or 1,
        position = SAM_UTILS.getUnitPosition(unit),
        protectionRadius = options.protectionRadius or 30000, -- メートル
        alertRadius = options.alertRadius or 80000,
        assignedSams = {},
        status = IADS_POINT_DEFENSE.STATUS.SAFE,
        threats = {},
        isStatic = unit:getDesc().category == Unit.Category.STRUCTURE or false
    }

    self.targets[unitName] = target

    -- SAMの自動割り当て
    if self.network then
        self:assignSamsToTarget(unitName)
    end

    SAM_UTILS.debug("[PointDefense] Added target: " .. unitName .. " (priority: " .. target.priority .. ")")
    return target
end

-- ============================================
-- 防護対象を追加（座標指定）
-- ============================================
function IADS_POINT_DEFENSE:addStaticTarget(id, position, options)
    if not position then return nil end

    options = options or {}

    local target = {
        id = id,
        unit = nil,
        type = options.type or IADS_POINT_DEFENSE.TARGET_TYPE.ZONE,
        priority = options.priority or 1,
        position = position,
        protectionRadius = options.protectionRadius or 30000,
        alertRadius = options.alertRadius or 80000,
        assignedSams = {},
        status = IADS_POINT_DEFENSE.STATUS.SAFE,
        threats = {},
        isStatic = true
    }

    self.targets[id] = target

    if self.network then
        self:assignSamsToTarget(id)
    end

    SAM_UTILS.debug("[PointDefense] Added static target: " .. id)
    return target
end

-- ============================================
-- DCSトリガーゾーンを防護対象として追加
-- ============================================
function IADS_POINT_DEFENSE:addZoneTarget(zoneName, options)
    local zone = trigger.misc.getZone(zoneName)
    if not zone then
        SAM_UTILS.debug("[PointDefense] Zone not found: " .. zoneName)
        return nil
    end

    options = options or {}
    options.type = IADS_POINT_DEFENSE.TARGET_TYPE.ZONE
    options.protectionRadius = options.protectionRadius or zone.radius

    return self:addStaticTarget(zoneName, zone.point, options)
end

-- ============================================
-- 飛行場を防護対象として追加
-- ============================================
function IADS_POINT_DEFENSE:addAirbase(airbaseName, options)
    local airbase = Airbase.getByName(airbaseName)
    if not airbase then
        SAM_UTILS.debug("[PointDefense] Airbase not found: " .. airbaseName)
        return nil
    end

    options = options or {}
    options.type = IADS_POINT_DEFENSE.TARGET_TYPE.AIRBASE
    options.priority = options.priority or 1  -- 飛行場は高優先度
    options.protectionRadius = options.protectionRadius or 40000
    options.alertRadius = options.alertRadius or 100000

    local position = airbase:getPoint()
    return self:addStaticTarget(airbaseName, position, options)
end

-- ============================================
-- 防護対象を削除
-- ============================================
function IADS_POINT_DEFENSE:removeTarget(targetId)
    if self.targets[targetId] then
        -- 割り当て解除
        for _, samName in ipairs(self.targets[targetId].assignedSams) do
            self.assignments[samName] = nil
        end
        self.targets[targetId] = nil
        SAM_UTILS.debug("[PointDefense] Removed target: " .. targetId)
        return true
    end
    return false
end

-- ============================================
-- SAMをターゲットに割り当て
-- ============================================
function IADS_POINT_DEFENSE:assignSamsToTarget(targetId)
    local target = self.targets[targetId]
    if not target or not self.network then return end

    target.assignedSams = {}

    -- 防護範囲内のSAMを検索
    for samName, samSite in pairs(self.network.samSites) do
        if samSite.position and target.position then
            local distance = SAM_UTILS.getDistance2D(target.position, samSite.position)

            if distance and distance <= target.alertRadius then
                -- 射程が防護対象をカバーできるか確認
                local canCover = distance <= (samSite.engagementRange or 50000)

                if canCover then
                    table.insert(target.assignedSams, samName)

                    -- 割り当て記録
                    if not self.assignments[samName] then
                        self.assignments[samName] = {}
                    end
                    table.insert(self.assignments[samName], targetId)
                end
            end
        end
    end

    SAM_UTILS.debug("[PointDefense] Assigned " .. #target.assignedSams .. " SAMs to " .. targetId)
end

-- ============================================
-- SAMのレイヤーを判定
-- ============================================
function IADS_POINT_DEFENSE:getSamLayer(samSite)
    local engagementRange = samSite.engagementRange or 50000

    if engagementRange >= 70000 then
        return IADS_POINT_DEFENSE.LAYER.LONG_RANGE
    elseif engagementRange >= 30000 then
        return IADS_POINT_DEFENSE.LAYER.MEDIUM_RANGE
    elseif engagementRange >= 10000 then
        return IADS_POINT_DEFENSE.LAYER.SHORT_RANGE
    else
        return IADS_POINT_DEFENSE.LAYER.SHORAD
    end
end

-- ============================================
-- 脅威をチェックして対応
-- ============================================
function IADS_POINT_DEFENSE:checkThreatsForTarget(targetId, threats)
    local target = self.targets[targetId]
    if not target then return end

    local nearThreats = {}
    local oldStatus = target.status

    -- 脅威を距離でチェック
    for _, threat in ipairs(threats) do
        if threat.position and target.position then
            local distance = SAM_UTILS.getDistance2D(target.position, threat.position)

            if distance then
                if distance <= target.protectionRadius then
                    -- 防護範囲内
                    table.insert(nearThreats, {
                        threat = threat,
                        distance = distance,
                        inProtectionZone = true
                    })
                elseif distance <= target.alertRadius then
                    -- 警戒範囲内
                    table.insert(nearThreats, {
                        threat = threat,
                        distance = distance,
                        inProtectionZone = false
                    })
                end
            end
        end
    end

    target.threats = nearThreats

    -- ステータス更新
    if #nearThreats == 0 then
        target.status = IADS_POINT_DEFENSE.STATUS.SAFE
    else
        local hasEngaging = false
        for _, t in ipairs(nearThreats) do
            if t.inProtectionZone then
                hasEngaging = true
                break
            end
        end

        if hasEngaging then
            target.status = IADS_POINT_DEFENSE.STATUS.ENGAGED
        else
            target.status = IADS_POINT_DEFENSE.STATUS.ALERT
        end
    end

    -- ステータス変更時の処理
    if oldStatus ~= target.status then
        self:onTargetStatusChanged(targetId, oldStatus, target.status)
    end

    -- 自動アクティブ化
    if self.autoActivate and target.status ~= IADS_POINT_DEFENSE.STATUS.SAFE then
        self:activateDefenseForTarget(targetId)
    end
end

-- ============================================
-- ターゲットの防護をアクティブ化
-- ============================================
function IADS_POINT_DEFENSE:activateDefenseForTarget(targetId)
    local target = self.targets[targetId]
    if not target or not self.network then return end

    local activatedCount = 0

    if self.layeredDefense then
        -- 多層防護: 脅威の距離に応じてレイヤーをアクティブ化
        local threatDistances = {}
        for _, t in ipairs(target.threats) do
            table.insert(threatDistances, t.distance)
        end

        local minDistance = math.huge
        for _, d in ipairs(threatDistances) do
            if d < minDistance then minDistance = d end
        end

        -- 脅威距離に応じたレイヤーをアクティブ化
        for _, samName in ipairs(target.assignedSams) do
            local samSite = self.network.samSites[samName]
            if samSite then
                local layer = self:getSamLayer(samSite)
                local layerRange = self.layerRanges[layer]

                -- このレイヤーが脅威距離に適切かチェック
                local shouldActivate = false

                if minDistance <= layerRange.max * self.threatRangeMultiplier then
                    shouldActivate = true
                end

                if shouldActivate then
                    self.network:activateSam(samName)
                    activatedCount = activatedCount + 1
                end
            end
        end
    else
        -- 全SAMをアクティブ化
        for _, samName in ipairs(target.assignedSams) do
            self.network:activateSam(samName)
            activatedCount = activatedCount + 1
        end
    end

    if activatedCount > 0 then
        SAM_UTILS.debug("[PointDefense] Activated " .. activatedCount .. " SAMs for " .. targetId)
    end
end

-- ============================================
-- ターゲットの防護を非アクティブ化
-- ============================================
function IADS_POINT_DEFENSE:deactivateDefenseForTarget(targetId)
    local target = self.targets[targetId]
    if not target or not self.network then return end

    for _, samName in ipairs(target.assignedSams) do
        -- 他のターゲットにも割り当てられていないか確認
        local otherAssignments = false
        if self.assignments[samName] then
            for _, otherId in ipairs(self.assignments[samName]) do
                if otherId ~= targetId then
                    local otherTarget = self.targets[otherId]
                    if otherTarget and otherTarget.status ~= IADS_POINT_DEFENSE.STATUS.SAFE then
                        otherAssignments = true
                        break
                    end
                end
            end
        end

        if not otherAssignments then
            self.network:deactivateSam(samName)
        end
    end
end

-- ============================================
-- ステータス変更時のコールバック
-- ============================================
function IADS_POINT_DEFENSE:onTargetStatusChanged(targetId, oldStatus, newStatus)
    SAM_UTILS.debug(string.format("[PointDefense] %s: %s -> %s",
        targetId, oldStatus, newStatus))

    if newStatus == IADS_POINT_DEFENSE.STATUS.SAFE then
        -- 脅威が去った: 遅延して非アクティブ化
        local pd = self
        SAM_UTILS.scheduleFunction(function()
            local target = pd.targets[targetId]
            if target and target.status == IADS_POINT_DEFENSE.STATUS.SAFE then
                pd:deactivateDefenseForTarget(targetId)
            end
        end, nil, SAM_UTILS.getTime() + 60)  -- 60秒後
    end
end

-- ============================================
-- 定期更新
-- ============================================
function IADS_POINT_DEFENSE:update()
    if not self.isRunning then return end

    -- ターゲット位置の更新（移動ユニットの場合）
    for targetId, target in pairs(self.targets) do
        if target.unit and not target.isStatic then
            if target.unit:isExist() then
                target.position = SAM_UTILS.getUnitPosition(target.unit)
            end
        end
    end

    -- 脅威情報を取得（IADSの脅威システムから）
    local threats = {}
    if self.network and self.network.threats then
        for _, threat in pairs(self.network.threats) do
            if not threat.isLost and threat.position then
                table.insert(threats, threat)
            end
        end
    end

    -- 各ターゲットの脅威をチェック
    for targetId, _ in pairs(self.targets) do
        self:checkThreatsForTarget(targetId, threats)
    end

    -- 次の更新をスケジュール
    self:scheduleUpdate()
end

-- ============================================
-- 更新スケジュール
-- ============================================
function IADS_POINT_DEFENSE:scheduleUpdate()
    local pd = self
    SAM_UTILS.scheduleFunction(function()
        pd:update()
    end, nil, SAM_UTILS.getTime() + self.updateInterval)
end

-- ============================================
-- 停止
-- ============================================
function IADS_POINT_DEFENSE:stop()
    self.isRunning = false
end

-- ============================================
-- ステータス取得
-- ============================================
function IADS_POINT_DEFENSE:getStatus()
    local status = {
        targetCount = 0,
        safe = 0,
        alert = 0,
        engaged = 0,
        compromised = 0,
        targets = {}
    }

    for targetId, target in pairs(self.targets) do
        status.targetCount = status.targetCount + 1

        if target.status == IADS_POINT_DEFENSE.STATUS.SAFE then
            status.safe = status.safe + 1
        elseif target.status == IADS_POINT_DEFENSE.STATUS.ALERT then
            status.alert = status.alert + 1
        elseif target.status == IADS_POINT_DEFENSE.STATUS.ENGAGED then
            status.engaged = status.engaged + 1
        elseif target.status == IADS_POINT_DEFENSE.STATUS.COMPROMISED then
            status.compromised = status.compromised + 1
        end

        table.insert(status.targets, {
            id = targetId,
            type = target.type,
            priority = target.priority,
            status = target.status,
            assignedSams = #target.assignedSams,
            threats = #target.threats
        })
    end

    return status
end

-- ============================================
-- ステータス表示
-- ============================================
function IADS_POINT_DEFENSE:printStatus()
    local status = self:getStatus()

    local msg = "[Point Defense Status]\n"
    msg = msg .. string.format("Targets: %d | Safe: %d | Alert: %d | Engaged: %d\n",
        status.targetCount, status.safe, status.alert, status.engaged)

    for _, target in ipairs(status.targets) do
        local threatStr = target.threats > 0 and (" [" .. target.threats .. " threats]") or ""
        msg = msg .. string.format("  %s: %s (P%d, %d SAMs)%s\n",
            target.id, target.status, target.priority, target.assignedSams, threatStr)
    end

    SAM_UTILS.info(msg, 20)
end

return IADS_POINT_DEFENSE
