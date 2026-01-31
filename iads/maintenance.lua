--[[
    DCS SAM Maintenance System
    修復/再配置システム

    損傷したSAMサイトの修復と戦術的再配置をシミュレート

    機能:
    - SAMサイトの損傷追跡
    - 修復チームの派遣と管理
    - 戦術的再配置（シュート＆スクート）
    - スペアユニットの管理
    - 修復優先度の自動計算

    依存: core/utils.lua, iads/network.lua
]]

SAM_MAINTENANCE = {}
SAM_MAINTENANCE.__index = SAM_MAINTENANCE

-- ============================================
-- 修復状態
-- ============================================
SAM_MAINTENANCE.REPAIR_STATUS = {
    NONE = "NONE",             -- 修復不要
    QUEUED = "QUEUED",         -- 修復待ち
    IN_PROGRESS = "IN_PROGRESS", -- 修復中
    COMPLETED = "COMPLETED"    -- 修復完了
}

-- ============================================
-- 再配置状態
-- ============================================
SAM_MAINTENANCE.RELOCATION_STATUS = {
    STATIC = "STATIC",         -- 静止中
    PACKING = "PACKING",       -- 撤収中
    MOVING = "MOVING",         -- 移動中
    DEPLOYING = "DEPLOYING",   -- 展開中
    READY = "READY"            -- 展開完了
}

-- ============================================
-- 損傷レベル
-- ============================================
SAM_MAINTENANCE.DAMAGE_LEVEL = {
    NONE = "NONE",             -- 損傷なし
    LIGHT = "LIGHT",           -- 軽微な損傷
    MODERATE = "MODERATE",     -- 中程度の損傷
    HEAVY = "HEAVY",           -- 重度の損傷
    DESTROYED = "DESTROYED"    -- 破壊
}

-- ============================================
-- メンテナンスシステム作成
-- ============================================
function SAM_MAINTENANCE.new(iadsNetwork)
    local self = setmetatable({}, SAM_MAINTENANCE)

    self.network = iadsNetwork
    self.updateInterval = 10       -- 更新間隔（秒）
    self.isRunning = false

    -- SAMサイトごとの状態
    self.siteStatus = {}

    -- 修復チーム
    self.repairTeams = {}
    self.repairTeamIdCounter = 0
    self.maxRepairTeams = 3        -- 最大同時修復チーム数

    -- スペアユニットプール
    self.spareUnits = {
        launchers = 10,
        radars = 5,
        commandPosts = 2,
        powerUnits = 5
    }

    -- 修復時間（秒）
    self.repairTimes = {
        [SAM_MAINTENANCE.DAMAGE_LEVEL.LIGHT] = 300,      -- 5分
        [SAM_MAINTENANCE.DAMAGE_LEVEL.MODERATE] = 900,   -- 15分
        [SAM_MAINTENANCE.DAMAGE_LEVEL.HEAVY] = 1800      -- 30分
    }

    -- 再配置時間（秒）
    self.relocationTimes = {
        packTime = 180,      -- 撤収時間（3分）
        deployTime = 300,    -- 展開時間（5分）
        moveSpeed = 30       -- 移動速度（km/h）
    }

    -- SAMタイプごとの機動性
    self.mobility = {
        ["S-300"] = {mobile = true, packTime = 300, deployTime = 300},
        ["SA-11"] = {mobile = true, packTime = 180, deployTime = 180},
        ["SA-6"] = {mobile = true, packTime = 240, deployTime = 240},
        ["Patriot"] = {mobile = true, packTime = 600, deployTime = 600},
        ["Hawk"] = {mobile = true, packTime = 900, deployTime = 900},
        ["SA-2"] = {mobile = false},
        ["SA-3"] = {mobile = false},
        ["default"] = {mobile = false}
    }

    -- シュート＆スクート設定
    self.shootAndScoot = {
        enabled = false,
        shotsBeforeMove = 2,       -- 発射後に移動するまでの発射数
        moveDistance = 3000,       -- 移動距離（メートル）
        cooldownTime = 600         -- 再配置後のクールダウン（秒）
    }

    return self
end

-- ============================================
-- 初期化
-- ============================================
function SAM_MAINTENANCE:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end
    if options.maxRepairTeams then
        self.maxRepairTeams = options.maxRepairTeams
    end
    if options.shootAndScoot then
        for k, v in pairs(options.shootAndScoot) do
            self.shootAndScoot[k] = v
        end
    end
    if options.spareUnits then
        for k, v in pairs(options.spareUnits) do
            self.spareUnits[k] = v
        end
    end

    -- 既存のSAMサイトを登録
    if self.network then
        for samGroupName, samSite in pairs(self.network.samSites) do
            self:registerSite(samGroupName)
        end
    end

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[Maintenance] System initialized")
    return self
end

-- ============================================
-- SAMサイトを登録
-- ============================================
function SAM_MAINTENANCE:registerSite(samGroupName)
    if self.siteStatus[samGroupName] then
        return self.siteStatus[samGroupName]
    end

    local status = {
        groupName = samGroupName,
        damageLevel = SAM_MAINTENANCE.DAMAGE_LEVEL.NONE,
        health = 100,
        repairStatus = SAM_MAINTENANCE.REPAIR_STATUS.NONE,
        relocationStatus = SAM_MAINTENANCE.RELOCATION_STATUS.STATIC,
        originalPosition = nil,
        currentPosition = nil,
        targetPosition = nil,
        shotsFired = 0,
        lastMoveTime = 0,
        assignedRepairTeam = nil,
        repairStartTime = nil,
        relocationStartTime = nil,
        isMobile = false
    }

    -- 元の位置を記録
    if self.network then
        local samSite = self.network.samSites[samGroupName]
        if samSite and samSite.position then
            status.originalPosition = SAM_UTILS.deepCopy(samSite.position)
            status.currentPosition = SAM_UTILS.deepCopy(samSite.position)
        end

        -- 機動性を判定
        status.isMobile = self:checkMobility(samGroupName)
    end

    self.siteStatus[samGroupName] = status
    return status
end

-- ============================================
-- SAMの機動性をチェック
-- ============================================
function SAM_MAINTENANCE:checkMobility(samGroupName)
    if not self.network then return false end

    local samSite = self.network.samSites[samGroupName]
    if not samSite then return false end

    for _, unitInfo in ipairs(samSite.units or {}) do
        if unitInfo.unitType then
            for samType, mobInfo in pairs(self.mobility) do
                if samType ~= "default" and string.find(unitInfo.unitType, samType) then
                    return mobInfo.mobile or false
                end
            end
        end
    end

    return self.mobility["default"].mobile or false
end

-- ============================================
-- SAMサイトにダメージを適用
-- ============================================
function SAM_MAINTENANCE:applyDamage(samGroupName, damagePercent)
    local status = self.siteStatus[samGroupName]
    if not status then
        status = self:registerSite(samGroupName)
    end

    status.health = math.max(0, status.health - damagePercent)

    -- 損傷レベルを更新
    if status.health >= 90 then
        status.damageLevel = SAM_MAINTENANCE.DAMAGE_LEVEL.NONE
    elseif status.health >= 60 then
        status.damageLevel = SAM_MAINTENANCE.DAMAGE_LEVEL.LIGHT
    elseif status.health >= 30 then
        status.damageLevel = SAM_MAINTENANCE.DAMAGE_LEVEL.MODERATE
    elseif status.health > 0 then
        status.damageLevel = SAM_MAINTENANCE.DAMAGE_LEVEL.HEAVY
    else
        status.damageLevel = SAM_MAINTENANCE.DAMAGE_LEVEL.DESTROYED
    end

    SAM_UTILS.debug("[Maintenance] " .. samGroupName ..
        " damaged. Health: " .. status.health .. "% Level: " .. status.damageLevel)

    -- 自動修復キュー登録
    if status.damageLevel ~= SAM_MAINTENANCE.DAMAGE_LEVEL.NONE and
       status.damageLevel ~= SAM_MAINTENANCE.DAMAGE_LEVEL.DESTROYED and
       status.repairStatus == SAM_MAINTENANCE.REPAIR_STATUS.NONE then
        self:queueRepair(samGroupName)
    end

    return status
end

-- ============================================
-- 修復キューに追加
-- ============================================
function SAM_MAINTENANCE:queueRepair(samGroupName)
    local status = self.siteStatus[samGroupName]
    if not status then return false end

    if status.damageLevel == SAM_MAINTENANCE.DAMAGE_LEVEL.NONE or
       status.damageLevel == SAM_MAINTENANCE.DAMAGE_LEVEL.DESTROYED then
        return false
    end

    if status.repairStatus ~= SAM_MAINTENANCE.REPAIR_STATUS.NONE then
        return false  -- 既にキューにある
    end

    status.repairStatus = SAM_MAINTENANCE.REPAIR_STATUS.QUEUED
    SAM_UTILS.debug("[Maintenance] " .. samGroupName .. " queued for repair")

    return true
end

-- ============================================
-- 修復チームを派遣
-- ============================================
function SAM_MAINTENANCE:dispatchRepairTeam(samGroupName)
    local status = self.siteStatus[samGroupName]
    if not status then return false end

    if status.repairStatus ~= SAM_MAINTENANCE.REPAIR_STATUS.QUEUED then
        return false
    end

    -- 利用可能なチーム数をチェック
    local activeTeams = 0
    for _, team in pairs(self.repairTeams) do
        if team.isActive then
            activeTeams = activeTeams + 1
        end
    end

    if activeTeams >= self.maxRepairTeams then
        SAM_UTILS.debug("[Maintenance] No repair teams available")
        return false
    end

    -- 修復チームを作成
    self.repairTeamIdCounter = self.repairTeamIdCounter + 1
    local teamId = "REPAIR-" .. string.format("%03d", self.repairTeamIdCounter)

    local team = {
        id = teamId,
        assignedSite = samGroupName,
        isActive = true,
        startTime = SAM_UTILS.getTime()
    }

    self.repairTeams[teamId] = team
    status.assignedRepairTeam = teamId
    status.repairStatus = SAM_MAINTENANCE.REPAIR_STATUS.IN_PROGRESS
    status.repairStartTime = SAM_UTILS.getTime()

    SAM_UTILS.debug("[Maintenance] Repair team " .. teamId .. " dispatched to " .. samGroupName)

    return true
end

-- ============================================
-- 修復を処理
-- ============================================
function SAM_MAINTENANCE:processRepairs()
    local currentTime = SAM_UTILS.getTime()

    for samGroupName, status in pairs(self.siteStatus) do
        if status.repairStatus == SAM_MAINTENANCE.REPAIR_STATUS.QUEUED then
            -- キュー中のサイトにチームを派遣
            self:dispatchRepairTeam(samGroupName)

        elseif status.repairStatus == SAM_MAINTENANCE.REPAIR_STATUS.IN_PROGRESS then
            -- 修復進行中
            local repairTime = self.repairTimes[status.damageLevel] or 600
            local elapsed = currentTime - status.repairStartTime

            if elapsed >= repairTime then
                -- 修復完了
                self:completeRepair(samGroupName)
            end
        end
    end
end

-- ============================================
-- 修復完了
-- ============================================
function SAM_MAINTENANCE:completeRepair(samGroupName)
    local status = self.siteStatus[samGroupName]
    if not status then return false end

    -- 修復チームを解放
    if status.assignedRepairTeam then
        local team = self.repairTeams[status.assignedRepairTeam]
        if team then
            team.isActive = false
        end
    end

    -- ステータスを更新
    status.health = 100
    status.damageLevel = SAM_MAINTENANCE.DAMAGE_LEVEL.NONE
    status.repairStatus = SAM_MAINTENANCE.REPAIR_STATUS.COMPLETED
    status.assignedRepairTeam = nil
    status.repairStartTime = nil

    SAM_UTILS.info("[Maintenance] " .. samGroupName .. " repair completed")

    -- しばらくしてからステータスをリセット
    local maintenanceSystem = self
    SAM_UTILS.scheduleFunction(function()
        if maintenanceSystem.siteStatus[samGroupName] then
            maintenanceSystem.siteStatus[samGroupName].repairStatus =
                SAM_MAINTENANCE.REPAIR_STATUS.NONE
        end
    end, nil, SAM_UTILS.getTime() + 10)

    return true
end

-- ============================================
-- 再配置を開始（シュート＆スクート）
-- ============================================
function SAM_MAINTENANCE:startRelocation(samGroupName, targetPosition)
    local status = self.siteStatus[samGroupName]
    if not status then
        status = self:registerSite(samGroupName)
    end

    if not status.isMobile then
        SAM_UTILS.debug("[Maintenance] " .. samGroupName .. " is not mobile")
        return false
    end

    if status.relocationStatus ~= SAM_MAINTENANCE.RELOCATION_STATUS.STATIC and
       status.relocationStatus ~= SAM_MAINTENANCE.RELOCATION_STATUS.READY then
        return false  -- 既に移動中
    end

    -- 目標位置を設定
    if targetPosition then
        status.targetPosition = SAM_UTILS.deepCopy(targetPosition)
    else
        -- ランダムな方向に移動
        local angle = SAM_UTILS.random(0, 360) * math.pi / 180
        local distance = self.shootAndScoot.moveDistance
        status.targetPosition = {
            x = status.currentPosition.x + distance * math.cos(angle),
            y = status.currentPosition.y or 0,
            z = status.currentPosition.z + distance * math.sin(angle)
        }
    end

    status.relocationStatus = SAM_MAINTENANCE.RELOCATION_STATUS.PACKING
    status.relocationStartTime = SAM_UTILS.getTime()

    -- ネットワーク上でSAMを停止
    if self.network then
        self.network:setSamState(samGroupName, IADS_NETWORK.SAM_STATE.DARK)
    end

    SAM_UTILS.debug("[Maintenance] " .. samGroupName .. " starting relocation (packing)")

    return true
end

-- ============================================
-- 再配置を処理
-- ============================================
function SAM_MAINTENANCE:processRelocations()
    local currentTime = SAM_UTILS.getTime()

    for samGroupName, status in pairs(self.siteStatus) do
        if not status.isMobile then
            -- 非機動型はスキップ
        elseif status.relocationStatus == SAM_MAINTENANCE.RELOCATION_STATUS.PACKING then
            -- 撤収中
            local mobInfo = self:getMobilityInfo(samGroupName)
            local packTime = mobInfo.packTime or self.relocationTimes.packTime
            local elapsed = currentTime - status.relocationStartTime

            if elapsed >= packTime then
                status.relocationStatus = SAM_MAINTENANCE.RELOCATION_STATUS.MOVING
                status.relocationStartTime = currentTime
                SAM_UTILS.debug("[Maintenance] " .. samGroupName .. " packed, now moving")
            end

        elseif status.relocationStatus == SAM_MAINTENANCE.RELOCATION_STATUS.MOVING then
            -- 移動中
            local distance = SAM_UTILS.getDistance2D(status.currentPosition, status.targetPosition)
            local moveSpeed = self.relocationTimes.moveSpeed * 1000 / 3600  -- m/s
            local moveTime = distance / moveSpeed
            local elapsed = currentTime - status.relocationStartTime

            if elapsed >= moveTime then
                status.currentPosition = SAM_UTILS.deepCopy(status.targetPosition)
                status.relocationStatus = SAM_MAINTENANCE.RELOCATION_STATUS.DEPLOYING
                status.relocationStartTime = currentTime
                SAM_UTILS.debug("[Maintenance] " .. samGroupName .. " arrived, now deploying")
            end

        elseif status.relocationStatus == SAM_MAINTENANCE.RELOCATION_STATUS.DEPLOYING then
            -- 展開中
            local mobInfo = self:getMobilityInfo(samGroupName)
            local deployTime = mobInfo.deployTime or self.relocationTimes.deployTime
            local elapsed = currentTime - status.relocationStartTime

            if elapsed >= deployTime then
                status.relocationStatus = SAM_MAINTENANCE.RELOCATION_STATUS.READY
                status.lastMoveTime = currentTime
                status.shotsFired = 0

                -- ネットワーク上でSAMを再有効化
                if self.network then
                    self.network:setSamState(samGroupName, IADS_NETWORK.SAM_STATE.GREEN)

                    -- 位置を更新
                    local samSite = self.network.samSites[samGroupName]
                    if samSite then
                        samSite.position = SAM_UTILS.deepCopy(status.currentPosition)
                    end
                end

                SAM_UTILS.info("[Maintenance] " .. samGroupName .. " deployed at new position")
            end
        end
    end
end

-- ============================================
-- SAMタイプの機動性情報を取得
-- ============================================
function SAM_MAINTENANCE:getMobilityInfo(samGroupName)
    if not self.network then
        return self.mobility["default"]
    end

    local samSite = self.network.samSites[samGroupName]
    if not samSite then
        return self.mobility["default"]
    end

    for _, unitInfo in ipairs(samSite.units or {}) do
        if unitInfo.unitType then
            for samType, mobInfo in pairs(self.mobility) do
                if samType ~= "default" and string.find(unitInfo.unitType, samType) then
                    return mobInfo
                end
            end
        end
    end

    return self.mobility["default"]
end

-- ============================================
-- 発射をカウント（シュート＆スクート用）
-- ============================================
function SAM_MAINTENANCE:recordShot(samGroupName)
    local status = self.siteStatus[samGroupName]
    if not status then
        status = self:registerSite(samGroupName)
    end

    status.shotsFired = status.shotsFired + 1

    -- シュート＆スクート判定
    if self.shootAndScoot.enabled and status.isMobile then
        local currentTime = SAM_UTILS.getTime()
        local cooldownPassed = (currentTime - status.lastMoveTime) > self.shootAndScoot.cooldownTime

        if status.shotsFired >= self.shootAndScoot.shotsBeforeMove and cooldownPassed then
            SAM_UTILS.debug("[Maintenance] " .. samGroupName .. " initiating shoot-and-scoot")
            self:startRelocation(samGroupName)
        end
    end
end

-- ============================================
-- スペアユニットを使用
-- ============================================
function SAM_MAINTENANCE:useSpareUnit(unitType)
    if self.spareUnits[unitType] and self.spareUnits[unitType] > 0 then
        self.spareUnits[unitType] = self.spareUnits[unitType] - 1
        SAM_UTILS.debug("[Maintenance] Used spare " .. unitType ..
            ". Remaining: " .. self.spareUnits[unitType])
        return true
    end
    return false
end

-- ============================================
-- スペアユニットを追加
-- ============================================
function SAM_MAINTENANCE:addSpareUnits(unitType, count)
    if self.spareUnits[unitType] then
        self.spareUnits[unitType] = self.spareUnits[unitType] + count
        return true
    end
    return false
end

-- ============================================
-- 定期更新
-- ============================================
function SAM_MAINTENANCE:update()
    if not self.isRunning then return end

    -- 修復処理
    self:processRepairs()

    -- 再配置処理
    self:processRelocations()

    -- 次の更新をスケジュール
    self:scheduleUpdate()
end

-- ============================================
-- 更新スケジュール
-- ============================================
function SAM_MAINTENANCE:scheduleUpdate()
    local maintenanceSystem = self
    SAM_UTILS.scheduleFunction(function()
        maintenanceSystem:update()
    end, nil, SAM_UTILS.getTime() + self.updateInterval)
end

-- ============================================
-- 停止
-- ============================================
function SAM_MAINTENANCE:stop()
    self.isRunning = false
end

-- ============================================
-- ステータス取得
-- ============================================
function SAM_MAINTENANCE:getStatus()
    local status = {
        totalSites = 0,
        damaged = 0,
        repairing = 0,
        relocating = 0,
        activeRepairTeams = 0,
        spareUnits = SAM_UTILS.deepCopy(self.spareUnits),
        sites = {}
    }

    for samGroupName, siteStatus in pairs(self.siteStatus) do
        status.totalSites = status.totalSites + 1

        if siteStatus.damageLevel ~= SAM_MAINTENANCE.DAMAGE_LEVEL.NONE then
            status.damaged = status.damaged + 1
        end
        if siteStatus.repairStatus == SAM_MAINTENANCE.REPAIR_STATUS.IN_PROGRESS then
            status.repairing = status.repairing + 1
        end
        if siteStatus.relocationStatus ~= SAM_MAINTENANCE.RELOCATION_STATUS.STATIC and
           siteStatus.relocationStatus ~= SAM_MAINTENANCE.RELOCATION_STATUS.READY then
            status.relocating = status.relocating + 1
        end

        table.insert(status.sites, {
            name = samGroupName,
            health = siteStatus.health,
            damageLevel = siteStatus.damageLevel,
            repairStatus = siteStatus.repairStatus,
            relocationStatus = siteStatus.relocationStatus,
            isMobile = siteStatus.isMobile
        })
    end

    for _, team in pairs(self.repairTeams) do
        if team.isActive then
            status.activeRepairTeams = status.activeRepairTeams + 1
        end
    end

    return status
end

-- ============================================
-- ステータス表示
-- ============================================
function SAM_MAINTENANCE:printStatus()
    local status = self:getStatus()

    local msg = "[Maintenance Status]\n"
    msg = msg .. string.format("Sites: %d | Damaged: %d | Repairing: %d | Relocating: %d\n",
        status.totalSites, status.damaged, status.repairing, status.relocating)
    msg = msg .. string.format("Repair Teams Active: %d/%d\n",
        status.activeRepairTeams, self.maxRepairTeams)
    msg = msg .. string.format("Spares - Launchers: %d | Radars: %d | CP: %d | Power: %d\n",
        status.spareUnits.launchers, status.spareUnits.radars,
        status.spareUnits.commandPosts, status.spareUnits.powerUnits)

    for _, site in ipairs(status.sites) do
        local mobileStr = site.isMobile and "[M]" or "[S]"
        local relocStr = ""
        if site.relocationStatus ~= SAM_MAINTENANCE.RELOCATION_STATUS.STATIC and
           site.relocationStatus ~= SAM_MAINTENANCE.RELOCATION_STATUS.READY then
            relocStr = " (" .. site.relocationStatus .. ")"
        end

        msg = msg .. string.format("  %s%s: HP:%d%% %s %s%s\n",
            mobileStr, site.name, site.health, site.damageLevel,
            site.repairStatus, relocStr)
    end

    SAM_UTILS.info(msg, 25)
end

return SAM_MAINTENANCE
