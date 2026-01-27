--[[
    DCS IADS Sector Management
    防空セクター管理

    特定のエリアを防空セクターとして定義し、
    そのセクター内のSAMを協調して運用する

    依存: core/utils.lua, iads/network.lua
]]

IADS_SECTOR = {}
IADS_SECTOR.__index = IADS_SECTOR

-- ============================================
-- セクタータイプ
-- ============================================
IADS_SECTOR.TYPE = {
    POINT = "POINT",         -- 円形セクター（中心点+半径）
    POLYGON = "POLYGON",     -- 多角形セクター
    ZONE = "ZONE"            -- DCSのトリガーゾーン
}

-- ============================================
-- セクター脅威レベル
-- ============================================
IADS_SECTOR.THREAT_LEVEL = {
    NONE = 0,
    LOW = 1,
    MEDIUM = 2,
    HIGH = 3,
    CRITICAL = 4
}

-- ============================================
-- セクター作成
-- ============================================
function IADS_SECTOR.new(id, sectorType, params)
    local self = setmetatable({}, IADS_SECTOR)

    self.id = id
    self.type = sectorType or IADS_SECTOR.TYPE.POINT
    self.samSites = {}           -- このセクター内のSAM
    self.ewrSites = {}           -- このセクター内のEWR
    self.threats = {}            -- 検知された脅威
    self.threatLevel = IADS_SECTOR.THREAT_LEVEL.NONE
    self.isActive = true
    self.engagementPolicy = "WEAPONS_FREE"  -- 交戦ポリシー

    -- セクター形状のパラメータ
    if sectorType == IADS_SECTOR.TYPE.POINT then
        self.center = params.center or {x = 0, y = 0, z = 0}
        self.radius = params.radius or 50000  -- メートル
    elseif sectorType == IADS_SECTOR.TYPE.POLYGON then
        self.vertices = params.vertices or {}
    elseif sectorType == IADS_SECTOR.TYPE.ZONE then
        self.zoneName = params.zoneName
        self:loadZone()
    end

    return self
end

-- ============================================
-- DCSトリガーゾーンの読み込み
-- ============================================
function IADS_SECTOR:loadZone()
    if not self.zoneName then return false end

    local zone = trigger.misc.getZone(self.zoneName)
    if zone then
        self.center = zone.point
        self.radius = zone.radius
        self.type = IADS_SECTOR.TYPE.POINT  -- ゾーンは円形として扱う
        return true
    end

    SAM_UTILS.debug("[IADS Sector] Zone not found: " .. self.zoneName)
    return false
end

-- ============================================
-- 位置がセクター内にあるかチェック
-- ============================================
function IADS_SECTOR:containsPosition(pos)
    if not pos then return false end

    if self.type == IADS_SECTOR.TYPE.POINT or self.type == IADS_SECTOR.TYPE.ZONE then
        local distance = SAM_UTILS.getDistance2D(pos, self.center)
        return distance and distance <= self.radius
    elseif self.type == IADS_SECTOR.TYPE.POLYGON then
        return self:pointInPolygon(pos)
    end

    return false
end

-- ============================================
-- 多角形内判定（レイキャスティング法）
-- ============================================
function IADS_SECTOR:pointInPolygon(pos)
    if not self.vertices or #self.vertices < 3 then return false end

    local x, z = pos.x, pos.z
    local inside = false
    local j = #self.vertices

    for i = 1, #self.vertices do
        local xi, zi = self.vertices[i].x, self.vertices[i].z
        local xj, zj = self.vertices[j].x, self.vertices[j].z

        if ((zi > z) ~= (zj > z)) and
           (x < (xj - xi) * (z - zi) / (zj - zi) + xi) then
            inside = not inside
        end

        j = i
    end

    return inside
end

-- ============================================
-- SAMサイトの追加
-- ============================================
function IADS_SECTOR:addSamSite(samSite)
    if not samSite then return false end

    self.samSites[samSite.groupName] = samSite
    samSite.sectorId = self.id
    return true
end

-- ============================================
-- SAMサイトの削除
-- ============================================
function IADS_SECTOR:removeSamSite(groupName)
    if self.samSites[groupName] then
        self.samSites[groupName].sectorId = nil
        self.samSites[groupName] = nil
        return true
    end
    return false
end

-- ============================================
-- EWRの追加
-- ============================================
function IADS_SECTOR:addEWR(ewr)
    if not ewr then return false end

    self.ewrSites[ewr.groupName] = ewr
    return true
end

-- ============================================
-- 脅威レベルの更新
-- ============================================
function IADS_SECTOR:updateThreatLevel()
    local threatCount = 0
    for _, _ in pairs(self.threats) do
        threatCount = threatCount + 1
    end

    if threatCount == 0 then
        self.threatLevel = IADS_SECTOR.THREAT_LEVEL.NONE
    elseif threatCount <= 2 then
        self.threatLevel = IADS_SECTOR.THREAT_LEVEL.LOW
    elseif threatCount <= 5 then
        self.threatLevel = IADS_SECTOR.THREAT_LEVEL.MEDIUM
    elseif threatCount <= 10 then
        self.threatLevel = IADS_SECTOR.THREAT_LEVEL.HIGH
    else
        self.threatLevel = IADS_SECTOR.THREAT_LEVEL.CRITICAL
    end

    return self.threatLevel
end

-- ============================================
-- 脅威の追加
-- ============================================
function IADS_SECTOR:addThreat(threat)
    if not threat then return false end

    local unitName = threat.unit:getName()
    self.threats[unitName] = threat
    self:updateThreatLevel()

    -- 脅威レベルに応じてSAMをアクティブ化
    self:respondToThreatLevel()

    return true
end

-- ============================================
-- 脅威の削除
-- ============================================
function IADS_SECTOR:removeThreat(unitName)
    if self.threats[unitName] then
        self.threats[unitName] = nil
        self:updateThreatLevel()
        return true
    end
    return false
end

-- ============================================
-- 脅威レベルへの対応
-- ============================================
function IADS_SECTOR:respondToThreatLevel()
    if self.threatLevel == IADS_SECTOR.THREAT_LEVEL.NONE then
        -- 脅威なし：最小限のSAMのみアクティブ
        self:setMinimumCoverage()
    elseif self.threatLevel == IADS_SECTOR.THREAT_LEVEL.LOW then
        -- 低脅威：一部のSAMをアクティブ
        self:setPartialCoverage()
    elseif self.threatLevel >= IADS_SECTOR.THREAT_LEVEL.MEDIUM then
        -- 中～高脅威：全SAMをアクティブ
        self:setFullCoverage()
    end
end

-- ============================================
-- 最小限のカバレッジ
-- ============================================
function IADS_SECTOR:setMinimumCoverage()
    local activatedCount = 0
    for groupName, samSite in pairs(self.samSites) do
        if activatedCount < 1 and samSite.priority == 1 then
            -- 優先度1のSAMを1つだけアクティブ
            SAM_UTILS.setGroupAlarmState(samSite.group, SAM_UTILS.ALARM_STATE.RED)
            activatedCount = activatedCount + 1
        else
            SAM_UTILS.setGroupAlarmState(samSite.group, SAM_UTILS.ALARM_STATE.GREEN)
        end
    end
end

-- ============================================
-- 部分的なカバレッジ
-- ============================================
function IADS_SECTOR:setPartialCoverage()
    for groupName, samSite in pairs(self.samSites) do
        if samSite.priority <= 2 then
            SAM_UTILS.setGroupAlarmState(samSite.group, SAM_UTILS.ALARM_STATE.RED)
        else
            SAM_UTILS.setGroupAlarmState(samSite.group, SAM_UTILS.ALARM_STATE.GREEN)
        end
    end
end

-- ============================================
-- 全面カバレッジ
-- ============================================
function IADS_SECTOR:setFullCoverage()
    for groupName, samSite in pairs(self.samSites) do
        SAM_UTILS.setGroupAlarmState(samSite.group, SAM_UTILS.ALARM_STATE.RED)
    end
end

-- ============================================
-- セクター状態の取得
-- ============================================
function IADS_SECTOR:getStatus()
    local samCount = 0
    local activeSams = 0

    for groupName, samSite in pairs(self.samSites) do
        samCount = samCount + 1
        if samSite.state == "ACTIVE" or samSite.state == "TRACKING" or samSite.state == "ENGAGING" then
            activeSams = activeSams + 1
        end
    end

    return {
        id = self.id,
        type = self.type,
        isActive = self.isActive,
        threatLevel = self.threatLevel,
        samCount = samCount,
        activeSams = activeSams,
        threatCount = 0  -- 実際のカウントを追加
    }
end

return IADS_SECTOR
