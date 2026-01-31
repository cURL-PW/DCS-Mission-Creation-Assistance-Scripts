--[[
    DCS SAM Decoy System
    デコイ/おとりシステム

    対レーダーミサイル（ARM）を本物のSAMから逸らすための
    おとり送信機をシミュレートする

    機能:
    - デコイ送信機の配置と管理
    - ARM誘引シミュレーション
    - デコイパターン（固定/移動/ランダム）
    - SAMとの連携（SAM停波時にデコイ送波）
    - デコイ損害管理

    依存: core/utils.lua, iads/network.lua
]]

SAM_DECOY = {}
SAM_DECOY.__index = SAM_DECOY

-- ============================================
-- デコイタイプ
-- ============================================
SAM_DECOY.TYPE = {
    FIXED = "FIXED",           -- 固定デコイ
    MOBILE = "MOBILE",         -- 移動デコイ
    INFLATABLE = "INFLATABLE", -- 膨張式デコイ
    ELECTRONIC = "ELECTRONIC"  -- 電子デコイ（送信機のみ）
}

-- ============================================
-- デコイ状態
-- ============================================
SAM_DECOY.STATUS = {
    INACTIVE = "INACTIVE",     -- 非アクティブ
    STANDBY = "STANDBY",       -- 待機中
    EMITTING = "EMITTING",     -- 送波中
    ATTRACTING = "ATTRACTING", -- ARM誘引中
    DESTROYED = "DESTROYED"    -- 破壊済み
}

-- ============================================
-- デコイシステム作成
-- ============================================
function SAM_DECOY.new(iadsNetwork)
    local self = setmetatable({}, SAM_DECOY)

    self.network = iadsNetwork
    self.decoys = {}                  -- デコイリスト
    self.decoyIdCounter = 0
    self.updateInterval = 2           -- 更新間隔（秒）
    self.autoActivate = true          -- SAM停波時に自動送波
    self.attractionRadius = 5000      -- ARM誘引半径（メートル）
    self.attractionProbability = 0.7  -- ARM誘引確率
    self.isRunning = false

    -- SAMタイプごとのデコイエミッション特性
    self.emissionProfiles = {
        ["S-300"] = {power = 100, frequency = "X-band"},
        ["SA-11"] = {power = 80, frequency = "G-band"},
        ["SA-6"] = {power = 60, frequency = "G-band"},
        ["Hawk"] = {power = 70, frequency = "X-band"},
        ["Patriot"] = {power = 90, frequency = "C-band"},
        ["default"] = {power = 50, frequency = "X-band"}
    }

    return self
end

-- ============================================
-- 初期化
-- ============================================
function SAM_DECOY:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end
    if options.autoActivate ~= nil then
        self.autoActivate = options.autoActivate
    end
    if options.attractionRadius then
        self.attractionRadius = options.attractionRadius
    end
    if options.attractionProbability then
        self.attractionProbability = options.attractionProbability
    end

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[Decoy] System initialized")
    return self
end

-- ============================================
-- デコイを追加（座標指定）
-- ============================================
function SAM_DECOY:addDecoy(position, options)
    if not position then return nil end

    options = options or {}
    self.decoyIdCounter = self.decoyIdCounter + 1
    local decoyId = "DECOY-" .. string.format("%03d", self.decoyIdCounter)

    local decoy = {
        id = decoyId,
        position = SAM_UTILS.deepCopy(position),
        type = options.type or SAM_DECOY.TYPE.ELECTRONIC,
        status = SAM_DECOY.STATUS.STANDBY,
        emissionProfile = options.emissionProfile or "default",
        linkedSam = options.linkedSam,  -- 連携するSAM
        power = options.power or 50,
        health = 100,
        activationCount = 0,
        armsAttracted = 0,
        lastActivation = nil,
        autoMode = options.autoMode ~= false
    }

    self.decoys[decoyId] = decoy

    SAM_UTILS.debug("[Decoy] Added: " .. decoyId .. " at (" ..
        math.floor(position.x) .. ", " .. math.floor(position.z) .. ")")

    return decoy
end

-- ============================================
-- SAMサイト周辺にデコイを配置
-- ============================================
function SAM_DECOY:deployAroundSam(samGroupName, count, radius, options)
    if not self.network then return {} end

    local samSite = self.network.samSites[samGroupName]
    if not samSite or not samSite.position then return {} end

    options = options or {}
    count = count or 2
    radius = radius or 3000

    local deployedDecoys = {}
    local centerPos = samSite.position

    for i = 1, count do
        -- 円形に配置
        local angle = (2 * math.pi * i) / count
        local offsetX = radius * math.cos(angle)
        local offsetZ = radius * math.sin(angle)

        local decoyPos = {
            x = centerPos.x + offsetX,
            y = centerPos.y or 0,
            z = centerPos.z + offsetZ
        }

        local decoyOptions = SAM_UTILS.deepCopy(options)
        decoyOptions.linkedSam = samGroupName

        -- SAMタイプに基づくエミッションプロファイル
        for _, unitInfo in ipairs(samSite.units or {}) do
            if unitInfo.unitType then
                for profile, _ in pairs(self.emissionProfiles) do
                    if string.find(unitInfo.unitType, profile) then
                        decoyOptions.emissionProfile = profile
                        break
                    end
                end
            end
        end

        local decoy = self:addDecoy(decoyPos, decoyOptions)
        if decoy then
            table.insert(deployedDecoys, decoy)
        end
    end

    SAM_UTILS.debug("[Decoy] Deployed " .. #deployedDecoys .. " decoys around " .. samGroupName)
    return deployedDecoys
end

-- ============================================
-- デコイを送波開始
-- ============================================
function SAM_DECOY:activateDecoy(decoyId)
    local decoy = self.decoys[decoyId]
    if not decoy then return false end

    if decoy.status == SAM_DECOY.STATUS.DESTROYED then
        return false
    end

    decoy.status = SAM_DECOY.STATUS.EMITTING
    decoy.activationCount = decoy.activationCount + 1
    decoy.lastActivation = SAM_UTILS.getTime()

    SAM_UTILS.debug("[Decoy] Activated: " .. decoyId)
    return true
end

-- ============================================
-- デコイを停波
-- ============================================
function SAM_DECOY:deactivateDecoy(decoyId)
    local decoy = self.decoys[decoyId]
    if not decoy then return false end

    if decoy.status == SAM_DECOY.STATUS.EMITTING or
       decoy.status == SAM_DECOY.STATUS.ATTRACTING then
        decoy.status = SAM_DECOY.STATUS.STANDBY
        SAM_UTILS.debug("[Decoy] Deactivated: " .. decoyId)
        return true
    end

    return false
end

-- ============================================
-- SAM連携デコイを自動制御
-- ============================================
function SAM_DECOY:updateLinkedDecoys()
    if not self.autoActivate or not self.network then return end

    for decoyId, decoy in pairs(self.decoys) do
        if decoy.linkedSam and decoy.autoMode then
            local samSite = self.network.samSites[decoy.linkedSam]

            if samSite then
                -- SAMが停波/被脅威状態ならデコイを送波
                local samState = samSite.state
                local shouldActivate = false

                if samState == IADS_NETWORK.SAM_STATE.SUPPRESSED then
                    shouldActivate = true
                elseif samState == IADS_NETWORK.SAM_STATE.DARK then
                    -- 脅威があればアクティブ化
                    if self.network.threats and next(self.network.threats) then
                        shouldActivate = true
                    end
                end

                if shouldActivate and decoy.status == SAM_DECOY.STATUS.STANDBY then
                    self:activateDecoy(decoyId)
                elseif not shouldActivate and decoy.status == SAM_DECOY.STATUS.EMITTING then
                    self:deactivateDecoy(decoyId)
                end
            end
        end
    end
end

-- ============================================
-- ARM誘引チェック
-- ============================================
function SAM_DECOY:checkArmAttraction(armPosition, armTarget)
    if not armPosition then return nil end

    local attractedDecoy = nil
    local closestDistance = math.huge

    for decoyId, decoy in pairs(self.decoys) do
        if decoy.status == SAM_DECOY.STATUS.EMITTING then
            local distance = SAM_UTILS.getDistance2D(armPosition, decoy.position)

            if distance and distance <= self.attractionRadius then
                -- 誘引確率チェック
                local roll = SAM_UTILS.random(1, 100) / 100

                -- デコイのパワーで確率を調整
                local adjustedProbability = self.attractionProbability * (decoy.power / 100)

                if roll <= adjustedProbability and distance < closestDistance then
                    attractedDecoy = decoy
                    closestDistance = distance
                end
            end
        end
    end

    if attractedDecoy then
        attractedDecoy.status = SAM_DECOY.STATUS.ATTRACTING
        attractedDecoy.armsAttracted = attractedDecoy.armsAttracted + 1

        SAM_UTILS.debug("[Decoy] " .. attractedDecoy.id .. " attracting ARM!")
        return attractedDecoy
    end

    return nil
end

-- ============================================
-- デコイ破壊
-- ============================================
function SAM_DECOY:destroyDecoy(decoyId)
    local decoy = self.decoys[decoyId]
    if not decoy then return false end

    decoy.status = SAM_DECOY.STATUS.DESTROYED
    decoy.health = 0

    SAM_UTILS.debug("[Decoy] Destroyed: " .. decoyId)

    -- 連携SAMに通知
    if decoy.linkedSam and self.network then
        SAM_UTILS.info("[Decoy] " .. decoyId .. " protecting " .. decoy.linkedSam .. " was destroyed")
    end

    return true
end

-- ============================================
-- デコイにダメージ
-- ============================================
function SAM_DECOY:damageDecoy(decoyId, damage)
    local decoy = self.decoys[decoyId]
    if not decoy or decoy.status == SAM_DECOY.STATUS.DESTROYED then
        return false
    end

    decoy.health = math.max(0, decoy.health - damage)

    if decoy.health <= 0 then
        self:destroyDecoy(decoyId)
    end

    return true
end

-- ============================================
-- ARM着弾シミュレーション
-- ============================================
function SAM_DECOY:onArmImpact(impactPosition, targetDecoyId)
    if targetDecoyId then
        local decoy = self.decoys[targetDecoyId]
        if decoy and decoy.status == SAM_DECOY.STATUS.ATTRACTING then
            -- ARMがデコイに命中
            self:destroyDecoy(targetDecoyId)
            SAM_UTILS.info("[Decoy] ARM successfully diverted to " .. targetDecoyId)
            return true
        end
    end

    -- 着弾位置周辺のデコイにダメージ
    for decoyId, decoy in pairs(self.decoys) do
        if decoy.status ~= SAM_DECOY.STATUS.DESTROYED then
            local distance = SAM_UTILS.getDistance2D(impactPosition, decoy.position)
            if distance and distance < 100 then
                -- 近距離で破壊
                self:destroyDecoy(decoyId)
            elseif distance and distance < 500 then
                -- 中距離でダメージ
                local damage = math.floor((500 - distance) / 5)
                self:damageDecoy(decoyId, damage)
            end
        end
    end

    return false
end

-- ============================================
-- 定期更新
-- ============================================
function SAM_DECOY:update()
    if not self.isRunning then return end

    -- SAM連携デコイの自動制御
    self:updateLinkedDecoys()

    -- 次の更新をスケジュール
    self:scheduleUpdate()
end

-- ============================================
-- 更新スケジュール
-- ============================================
function SAM_DECOY:scheduleUpdate()
    local decoySystem = self
    SAM_UTILS.scheduleFunction(function()
        decoySystem:update()
    end, nil, SAM_UTILS.getTime() + self.updateInterval)
end

-- ============================================
-- 停止
-- ============================================
function SAM_DECOY:stop()
    self.isRunning = false
end

-- ============================================
-- デコイを削除
-- ============================================
function SAM_DECOY:removeDecoy(decoyId)
    if self.decoys[decoyId] then
        self.decoys[decoyId] = nil
        return true
    end
    return false
end

-- ============================================
-- 全デコイをアクティブ化
-- ============================================
function SAM_DECOY:activateAll()
    for decoyId, decoy in pairs(self.decoys) do
        if decoy.status == SAM_DECOY.STATUS.STANDBY then
            self:activateDecoy(decoyId)
        end
    end
end

-- ============================================
-- 全デコイを停波
-- ============================================
function SAM_DECOY:deactivateAll()
    for decoyId, decoy in pairs(self.decoys) do
        if decoy.status == SAM_DECOY.STATUS.EMITTING or
           decoy.status == SAM_DECOY.STATUS.ATTRACTING then
            self:deactivateDecoy(decoyId)
        end
    end
end

-- ============================================
-- ステータス取得
-- ============================================
function SAM_DECOY:getStatus()
    local status = {
        totalDecoys = 0,
        standby = 0,
        emitting = 0,
        attracting = 0,
        destroyed = 0,
        totalArmsAttracted = 0,
        decoys = {}
    }

    for decoyId, decoy in pairs(self.decoys) do
        status.totalDecoys = status.totalDecoys + 1
        status.totalArmsAttracted = status.totalArmsAttracted + decoy.armsAttracted

        if decoy.status == SAM_DECOY.STATUS.STANDBY then
            status.standby = status.standby + 1
        elseif decoy.status == SAM_DECOY.STATUS.EMITTING then
            status.emitting = status.emitting + 1
        elseif decoy.status == SAM_DECOY.STATUS.ATTRACTING then
            status.attracting = status.attracting + 1
        elseif decoy.status == SAM_DECOY.STATUS.DESTROYED then
            status.destroyed = status.destroyed + 1
        end

        table.insert(status.decoys, {
            id = decoyId,
            status = decoy.status,
            linkedSam = decoy.linkedSam,
            health = decoy.health,
            armsAttracted = decoy.armsAttracted
        })
    end

    return status
end

-- ============================================
-- ステータス表示
-- ============================================
function SAM_DECOY:printStatus()
    local status = self:getStatus()

    local msg = "[Decoy Status]\n"
    msg = msg .. string.format("Total: %d | Standby: %d | Emitting: %d | Destroyed: %d\n",
        status.totalDecoys, status.standby, status.emitting, status.destroyed)
    msg = msg .. string.format("ARMs Attracted: %d\n", status.totalArmsAttracted)

    for _, decoy in ipairs(status.decoys) do
        local linkedStr = decoy.linkedSam and (" -> " .. decoy.linkedSam) or ""
        msg = msg .. string.format("  %s: %s (HP:%d)%s\n",
            decoy.id, decoy.status, decoy.health, linkedStr)
    end

    SAM_UTILS.info(msg, 20)
end

return SAM_DECOY
