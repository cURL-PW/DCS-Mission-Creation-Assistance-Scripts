--[[
    DCS Integrated Air Defense System (IADS) Network
    統合防空システムネットワーク

    SAM同士を連携させ、協調した防空を実現するシステム

    機能:
    - SAMサイトのネットワーク管理
    - 早期警戒レーダー(EWR)からの情報配信
    - SAM間の脅威情報共有
    - 協調したレーダー運用（停波時のカバー）
    - セクター管理

    依存: core/config.lua, core/utils.lua
]]

IADS_NETWORK = {}
IADS_NETWORK.__index = IADS_NETWORK

-- ============================================
-- ネットワークノードタイプ
-- ============================================
IADS_NETWORK.NODE_TYPE = {
    EWR = "EWR",           -- 早期警戒レーダー
    SAM_SITE = "SAM_SITE", -- SAMサイト
    COMMAND = "COMMAND"    -- 指揮所
}

-- ============================================
-- SAMサイト運用状態
-- ============================================
IADS_NETWORK.SAM_STATE = {
    DARK = "DARK",           -- レーダー停波（電波放射なし）
    ACTIVE = "ACTIVE",       -- アクティブ（レーダー送波中）
    TRACKING = "TRACKING",   -- 追尾中
    ENGAGING = "ENGAGING",   -- 交戦中
    SUPPRESSED = "SUPPRESSED" -- SEAD攻撃により強制停波
}

-- ============================================
-- ネットワーク作成
-- ============================================
function IADS_NETWORK.new(name)
    local self = setmetatable({}, IADS_NETWORK)

    self.name = name or "IADS"
    self.nodes = {}              -- ネットワークノード
    self.samSites = {}           -- SAMサイト
    self.ewrSites = {}           -- 早期警戒レーダー
    self.sectors = {}            -- 防空セクター
    self.threats = {}            -- 検知された脅威
    self.updateInterval = 5      -- 更新間隔（秒）
    self.darkMode = false        -- ダークモード（全SAM停波）
    self.emissionControl = false -- EMCON（電波管制）

    return self
end

-- ============================================
-- 初期化
-- ============================================
function IADS_NETWORK:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end

    -- 定期更新スケジュール
    self:scheduleUpdate()

    SAM_UTILS.debug("[IADS] Network '" .. self.name .. "' initialized")
    return self
end

-- ============================================
-- SAMサイトの追加
-- ============================================
function IADS_NETWORK:addSamSite(group, options)
    if not group then
        SAM_UTILS.debug("[IADS] Error: Cannot add nil group as SAM site")
        return nil
    end

    options = options or {}
    local groupName = group:getName()

    -- SAMサイト情報を作成
    local samSite = {
        group = group,
        groupName = groupName,
        state = IADS_NETWORK.SAM_STATE.DARK, -- 初期状態はダーク
        position = SAM_UTILS.getGroupPosition(group),
        engagementRange = options.engagementRange or 50000, -- メートル
        trackingRange = options.trackingRange or 100000,
        linkedEWRs = {},           -- リンクされたEWR
        linkedSAMs = {},           -- リンクされた他のSAM
        sectorId = options.sectorId,
        priority = options.priority or 1,
        units = {},                -- ユニット情報
        canEngage = true,
        lastUpdate = SAM_UTILS.getTime()
    }

    -- ユニット情報を収集
    local units = group:getUnits()
    if units then
        for _, unit in ipairs(units) do
            local unitType = unit:getTypeName()
            local config = SAM_CONFIG.getTypeConfig(unitType)
            if SAM_CONFIG.isSamType(unitType) then
                table.insert(samSite.units, {
                    unit = unit,
                    unitName = unit:getName(),
                    unitType = unitType,
                    config = config,
                    category = config.category
                })

                -- 射程を更新（設定から取得）
                if config.engagementRange > 0 then
                    samSite.engagementRange = math.max(samSite.engagementRange, config.engagementRange * 1000)
                end
                if config.trackingRange > 0 then
                    samSite.trackingRange = math.max(samSite.trackingRange, config.trackingRange * 1000)
                end
            end
        end
    end

    self.samSites[groupName] = samSite
    self.nodes[groupName] = {
        type = IADS_NETWORK.NODE_TYPE.SAM_SITE,
        data = samSite
    }

    SAM_UTILS.debug("[IADS] Added SAM site: " .. groupName)
    return samSite
end

-- ============================================
-- 早期警戒レーダー(EWR)の追加
-- ============================================
function IADS_NETWORK:addEWR(group, options)
    if not group then
        SAM_UTILS.debug("[IADS] Error: Cannot add nil group as EWR")
        return nil
    end

    options = options or {}
    local groupName = group:getName()

    local ewr = {
        group = group,
        groupName = groupName,
        position = SAM_UTILS.getGroupPosition(group),
        detectionRange = options.detectionRange or 300000, -- メートル
        linkedSAMs = {},
        isActive = true,
        lastUpdate = SAM_UTILS.getTime()
    }

    self.ewrSites[groupName] = ewr
    self.nodes[groupName] = {
        type = IADS_NETWORK.NODE_TYPE.EWR,
        data = ewr
    }

    SAM_UTILS.debug("[IADS] Added EWR: " .. groupName)
    return ewr
end

-- ============================================
-- SAMとEWRのリンク
-- ============================================
function IADS_NETWORK:linkSamToEWR(samGroupName, ewrGroupName)
    local samSite = self.samSites[samGroupName]
    local ewr = self.ewrSites[ewrGroupName]

    if not samSite or not ewr then
        SAM_UTILS.debug("[IADS] Error: Invalid SAM or EWR for linking")
        return false
    end

    -- 双方向リンク
    if not SAM_UTILS.tableContainsValue(samSite.linkedEWRs, ewrGroupName) then
        table.insert(samSite.linkedEWRs, ewrGroupName)
    end
    if not SAM_UTILS.tableContainsValue(ewr.linkedSAMs, samGroupName) then
        table.insert(ewr.linkedSAMs, samGroupName)
    end

    SAM_UTILS.debug("[IADS] Linked SAM '" .. samGroupName .. "' to EWR '" .. ewrGroupName .. "'")
    return true
end

-- ============================================
-- SAM同士のリンク
-- ============================================
function IADS_NETWORK:linkSamToSam(samGroupName1, samGroupName2)
    local sam1 = self.samSites[samGroupName1]
    local sam2 = self.samSites[samGroupName2]

    if not sam1 or not sam2 then
        SAM_UTILS.debug("[IADS] Error: Invalid SAM sites for linking")
        return false
    end

    -- 双方向リンク
    if not SAM_UTILS.tableContainsValue(sam1.linkedSAMs, samGroupName2) then
        table.insert(sam1.linkedSAMs, samGroupName2)
    end
    if not SAM_UTILS.tableContainsValue(sam2.linkedSAMs, samGroupName1) then
        table.insert(sam2.linkedSAMs, samGroupName1)
    end

    SAM_UTILS.debug("[IADS] Linked SAM '" .. samGroupName1 .. "' to SAM '" .. samGroupName2 .. "'")
    return true
end

-- ============================================
-- SAM状態の変更
-- ============================================
function IADS_NETWORK:setSamState(samGroupName, state)
    local samSite = self.samSites[samGroupName]
    if not samSite then return false end

    local oldState = samSite.state
    samSite.state = state

    -- 実際のゲーム内状態を変更
    if state == IADS_NETWORK.SAM_STATE.DARK or state == IADS_NETWORK.SAM_STATE.SUPPRESSED then
        SAM_UTILS.setGroupAlarmState(samSite.group, SAM_UTILS.ALARM_STATE.GREEN)
    else
        SAM_UTILS.setGroupAlarmState(samSite.group, SAM_UTILS.ALARM_STATE.RED)
    end

    SAM_UTILS.debug(string.format("[IADS] SAM '%s' state: %s -> %s", samGroupName, oldState, state))
    return true
end

-- ============================================
-- SAMのアクティブ化
-- ============================================
function IADS_NETWORK:activateSam(samGroupName)
    return self:setSamState(samGroupName, IADS_NETWORK.SAM_STATE.ACTIVE)
end

-- ============================================
-- SAMのダーク化（停波）
-- ============================================
function IADS_NETWORK:deactivateSam(samGroupName)
    return self:setSamState(samGroupName, IADS_NETWORK.SAM_STATE.DARK)
end

-- ============================================
-- 全SAMのアクティブ化
-- ============================================
function IADS_NETWORK:activateAllSams()
    self.darkMode = false
    for groupName, _ in pairs(self.samSites) do
        self:activateSam(groupName)
    end
    SAM_UTILS.debug("[IADS] All SAM sites activated")
end

-- ============================================
-- 全SAMのダーク化
-- ============================================
function IADS_NETWORK:deactivateAllSams()
    self.darkMode = true
    for groupName, _ in pairs(self.samSites) do
        self:deactivateSam(groupName)
    end
    SAM_UTILS.debug("[IADS] All SAM sites went dark")
end

-- ============================================
-- SEAD脅威通知（SEADシステムからのコールバック）
-- ============================================
function IADS_NETWORK:onSamThreatened(targetInfo, weaponTypeName)
    local groupName = targetInfo.groupName
    local samSite = self.samSites[groupName]

    if not samSite then return end

    SAM_UTILS.debug("[IADS] SAM '" .. groupName .. "' threatened by " .. weaponTypeName)

    -- 脅威情報をリンクされたSAMに伝播
    self:propagateThreatWarning(samSite, weaponTypeName)
end

-- ============================================
-- SAM停波通知（SEADシステムからのコールバック）
-- ============================================
function IADS_NETWORK:onSamSuppressed(targetInfo)
    local groupName = targetInfo.groupName
    local samSite = self.samSites[groupName]

    if not samSite then return end

    samSite.state = IADS_NETWORK.SAM_STATE.SUPPRESSED
    SAM_UTILS.debug("[IADS] SAM '" .. groupName .. "' suppressed, activating backup coverage")

    -- リンクされたSAMをアクティブ化してカバー
    self:activateBackupCoverage(samSite)
end

-- ============================================
-- SAM再起動通知（SEADシステムからのコールバック）
-- ============================================
function IADS_NETWORK:onSamReactivated(targetInfo)
    local groupName = targetInfo.groupName
    local samSite = self.samSites[groupName]

    if not samSite then return end

    -- EMCON/ダークモードでなければアクティブに
    if not self.darkMode and not self.emissionControl then
        samSite.state = IADS_NETWORK.SAM_STATE.ACTIVE
    else
        samSite.state = IADS_NETWORK.SAM_STATE.DARK
    end

    SAM_UTILS.debug("[IADS] SAM '" .. groupName .. "' reactivated")
end

-- ============================================
-- 脅威警報の伝播
-- ============================================
function IADS_NETWORK:propagateThreatWarning(samSite, weaponTypeName)
    -- リンクされたSAMに警告
    for _, linkedSamName in ipairs(samSite.linkedSAMs) do
        local linkedSam = self.samSites[linkedSamName]
        if linkedSam then
            SAM_UTILS.debug("[IADS] Warning propagated to: " .. linkedSamName)
            -- リンクされたSAMは警戒態勢に
            if linkedSam.state == IADS_NETWORK.SAM_STATE.DARK then
                -- 停波中のSAMはそのまま維持（ただし準備態勢に）
            end
        end
    end

    -- リンクされたEWRに警告
    for _, ewrName in ipairs(samSite.linkedEWRs) do
        local ewr = self.ewrSites[ewrName]
        if ewr then
            SAM_UTILS.debug("[IADS] EWR notified: " .. ewrName)
        end
    end
end

-- ============================================
-- バックアップカバレッジのアクティブ化
-- ============================================
function IADS_NETWORK:activateBackupCoverage(suppressedSamSite)
    local suppressedPos = suppressedSamSite.position
    if not suppressedPos then return end

    -- リンクされたSAMをアクティブ化
    for _, linkedSamName in ipairs(suppressedSamSite.linkedSAMs) do
        local linkedSam = self.samSites[linkedSamName]
        if linkedSam and linkedSam.state == IADS_NETWORK.SAM_STATE.DARK then
            -- 距離チェック（射程内ならカバー可能）
            local linkedPos = linkedSam.position
            if linkedPos then
                local distance = SAM_UTILS.getDistance2D(suppressedPos, linkedPos)
                -- 射程の1.5倍以内なら重複カバレッジがある
                if distance and distance < linkedSam.engagementRange * 1.5 then
                    self:activateSam(linkedSamName)
                    SAM_UTILS.debug("[IADS] Backup coverage: " .. linkedSamName .. " activated")
                end
            end
        end
    end

    -- 同じセクターのSAMもアクティブ化
    if suppressedSamSite.sectorId then
        for groupName, samSite in pairs(self.samSites) do
            if samSite.sectorId == suppressedSamSite.sectorId and
               samSite.groupName ~= suppressedSamSite.groupName and
               samSite.state == IADS_NETWORK.SAM_STATE.DARK then
                self:activateSam(groupName)
                SAM_UTILS.debug("[IADS] Sector backup: " .. groupName .. " activated")
            end
        end
    end
end

-- ============================================
-- 脅威の追加
-- ============================================
function IADS_NETWORK:addThreat(unit, threatLevel)
    if not unit then return end

    local unitName = unit:getName()
    self.threats[unitName] = {
        unit = unit,
        position = SAM_UTILS.getUnitPosition(unit),
        threatLevel = threatLevel or 1,
        detectedTime = SAM_UTILS.getTime(),
        detectedBy = {}
    }

    SAM_UTILS.debug("[IADS] Threat added: " .. unitName)
end

-- ============================================
-- 脅威の削除
-- ============================================
function IADS_NETWORK:removeThreat(unitName)
    self.threats[unitName] = nil
end

-- ============================================
-- 脅威への対応
-- ============================================
function IADS_NETWORK:respondToThreat(threat)
    if not threat or not threat.position then return end

    -- 脅威に最も近いSAMを見つける
    local closestSam = nil
    local closestDistance = math.huge

    for groupName, samSite in pairs(self.samSites) do
        if samSite.canEngage and samSite.state ~= IADS_NETWORK.SAM_STATE.SUPPRESSED then
            local samPos = samSite.position
            if samPos then
                local distance = SAM_UTILS.getDistance2D(threat.position, samPos)
                if distance and distance < samSite.engagementRange and distance < closestDistance then
                    closestSam = samSite
                    closestDistance = distance
                end
            end
        end
    end

    if closestSam then
        -- 最も近いSAMをアクティブ化
        if closestSam.state == IADS_NETWORK.SAM_STATE.DARK then
            self:activateSam(closestSam.groupName)
            SAM_UTILS.debug("[IADS] SAM '" .. closestSam.groupName .. "' responding to threat")
        end
    end
end

-- ============================================
-- 定期更新
-- ============================================
function IADS_NETWORK:update()
    local currentTime = SAM_UTILS.getTime()

    -- SAMサイトの位置を更新
    for groupName, samSite in pairs(self.samSites) do
        if samSite.group and samSite.group:isExist() then
            samSite.position = SAM_UTILS.getGroupPosition(samSite.group)
            samSite.lastUpdate = currentTime
        end
    end

    -- EWRの位置を更新
    for groupName, ewr in pairs(self.ewrSites) do
        if ewr.group and ewr.group:isExist() then
            ewr.position = SAM_UTILS.getGroupPosition(ewr.group)
            ewr.lastUpdate = currentTime
        end
    end

    -- 次の更新をスケジュール
    self:scheduleUpdate()
end

-- ============================================
-- 更新スケジュール
-- ============================================
function IADS_NETWORK:scheduleUpdate()
    local self_ref = self
    SAM_UTILS.scheduleFunction(function()
        self_ref:update()
    end, nil, SAM_UTILS.getTime() + self.updateInterval)
end

-- ============================================
-- ネットワーク状態の取得
-- ============================================
function IADS_NETWORK:getStatus()
    local status = {
        name = self.name,
        darkMode = self.darkMode,
        emissionControl = self.emissionControl,
        samSites = {},
        ewrSites = {},
        activeSams = 0,
        darkSams = 0,
        suppressedSams = 0
    }

    for groupName, samSite in pairs(self.samSites) do
        table.insert(status.samSites, {
            groupName = groupName,
            state = samSite.state,
            linkedEWRs = #samSite.linkedEWRs,
            linkedSAMs = #samSite.linkedSAMs
        })

        if samSite.state == IADS_NETWORK.SAM_STATE.ACTIVE or
           samSite.state == IADS_NETWORK.SAM_STATE.TRACKING or
           samSite.state == IADS_NETWORK.SAM_STATE.ENGAGING then
            status.activeSams = status.activeSams + 1
        elseif samSite.state == IADS_NETWORK.SAM_STATE.SUPPRESSED then
            status.suppressedSams = status.suppressedSams + 1
        else
            status.darkSams = status.darkSams + 1
        end
    end

    for groupName, ewr in pairs(self.ewrSites) do
        table.insert(status.ewrSites, {
            groupName = groupName,
            isActive = ewr.isActive,
            linkedSAMs = #ewr.linkedSAMs
        })
    end

    return status
end

-- ============================================
-- ステータスの表示
-- ============================================
function IADS_NETWORK:printStatus()
    local status = self:getStatus()
    local msg = string.format(
        "[IADS %s Status]\nActive: %d | Dark: %d | Suppressed: %d\nEWRs: %d | Total SAMs: %d",
        status.name,
        status.activeSams,
        status.darkSams,
        status.suppressedSams,
        #status.ewrSites,
        #status.samSites
    )
    SAM_UTILS.info(msg)
end

return IADS_NETWORK
