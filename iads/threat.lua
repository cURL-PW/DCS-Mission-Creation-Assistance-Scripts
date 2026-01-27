--[[
    DCS IADS Threat Information Sharing System
    脅威情報共有システム

    EWRやSAMが検知した航空機の情報をネットワーク全体で共有し、
    協調した迎撃を実現する

    依存: core/utils.lua, iads/network.lua
]]

IADS_THREAT = {}
IADS_THREAT.__index = IADS_THREAT

-- ============================================
-- 脅威カテゴリ
-- ============================================
IADS_THREAT.CATEGORY = {
    UNKNOWN = "UNKNOWN",
    FIGHTER = "FIGHTER",
    ATTACK = "ATTACK",
    BOMBER = "BOMBER",
    SEAD = "SEAD",
    HELICOPTER = "HELICOPTER",
    UAV = "UAV",
    CRUISE_MISSILE = "CRUISE_MISSILE",
    ARM = "ARM"  -- 対レーダーミサイル
}

-- ============================================
-- 脅威優先度
-- ============================================
IADS_THREAT.PRIORITY = {
    CRITICAL = 1,    -- 即時対応必要（ARM、接近中の脅威）
    HIGH = 2,        -- 高優先度（SEAD機、爆撃機）
    MEDIUM = 3,      -- 中優先度（攻撃機）
    LOW = 4,         -- 低優先度（戦闘機、偵察機）
    MINIMAL = 5      -- 最低優先度（遠方の脅威）
}

-- ============================================
-- 脅威情報管理システム作成
-- ============================================
function IADS_THREAT.new(iadsNetwork)
    local self = setmetatable({}, IADS_THREAT)

    self.network = iadsNetwork
    self.tracks = {}             -- 追跡中の脅威
    self.trackIdCounter = 0
    self.updateInterval = 2      -- 更新間隔（秒）
    self.trackTimeout = 30       -- 追跡タイムアウト（秒）
    self.mergeDistance = 1000    -- トラックマージ距離（メートル）

    return self
end

-- ============================================
-- 初期化
-- ============================================
function IADS_THREAT:init()
    -- 定期更新スケジュール
    self:scheduleUpdate()
    SAM_UTILS.debug("[IADS Threat] System initialized")
    return self
end

-- ============================================
-- 新規トラック作成
-- ============================================
function IADS_THREAT:createTrack(unit, detectedBy)
    if not unit or not unit:isExist() then return nil end

    self.trackIdCounter = self.trackIdCounter + 1
    local trackId = "TRK-" .. string.format("%04d", self.trackIdCounter)

    local track = {
        id = trackId,
        unit = unit,
        unitName = unit:getName(),
        coalition = unit:getCoalition(),
        category = self:categorizeTarget(unit),
        priority = IADS_THREAT.PRIORITY.MEDIUM,
        position = SAM_UTILS.getUnitPosition(unit),
        velocity = unit:getVelocity(),
        altitude = 0,
        heading = 0,
        speed = 0,
        detectedBy = {detectedBy},
        firstDetected = SAM_UTILS.getTime(),
        lastUpdated = SAM_UTILS.getTime(),
        engagedBy = {},
        isEngaged = false,
        isLost = false
    }

    -- 高度と速度を計算
    if track.position then
        track.altitude = track.position.y
    end
    if track.velocity then
        track.speed = math.sqrt(
            track.velocity.x^2 +
            track.velocity.y^2 +
            track.velocity.z^2
        )
        track.heading = math.deg(math.atan2(track.velocity.z, track.velocity.x))
        if track.heading < 0 then
            track.heading = track.heading + 360
        end
    end

    -- 優先度を計算
    track.priority = self:calculatePriority(track)

    self.tracks[trackId] = track
    SAM_UTILS.debug("[IADS Threat] New track: " .. trackId .. " (" .. track.category .. ")")

    return track
end

-- ============================================
-- ターゲットのカテゴリ分類
-- ============================================
function IADS_THREAT:categorizeTarget(unit)
    if not unit then return IADS_THREAT.CATEGORY.UNKNOWN end

    local typeName = unit:getTypeName()
    local desc = unit:getDesc()

    -- 属性をチェック
    if desc then
        local attrs = desc.attributes or {}

        -- ヘリコプター
        if attrs["Helicopters"] then
            return IADS_THREAT.CATEGORY.HELICOPTER
        end

        -- UAV
        if attrs["UAVs"] then
            return IADS_THREAT.CATEGORY.UAV
        end

        -- 爆撃機
        if attrs["Bombers"] then
            return IADS_THREAT.CATEGORY.BOMBER
        end

        -- 攻撃機（SEAD能力判定）
        if attrs["Battleplanes"] or attrs["Attack helicopters"] then
            -- SEAD機の判定（ペイロードチェックが必要だが、簡易的に機種で判定）
            if self:isSEADCapable(typeName) then
                return IADS_THREAT.CATEGORY.SEAD
            end
            return IADS_THREAT.CATEGORY.ATTACK
        end

        -- 戦闘機
        if attrs["Fighters"] then
            return IADS_THREAT.CATEGORY.FIGHTER
        end
    end

    return IADS_THREAT.CATEGORY.UNKNOWN
end

-- ============================================
-- SEAD能力のある機体かどうか判定
-- ============================================
function IADS_THREAT:isSEADCapable(typeName)
    local seadAircraft = {
        "F-16C_50",
        "F-16CM_50",
        "FA-18C_hornet",
        "F-4E",
        "F-15E",
        "Su-25",
        "Su-25T",
        "Su-24M",
        "Su-34",
        "Tornado IDS",
        "Tornado ECR",
        "JF-17",
        "A-10C",
        "A-10C_2"
    }

    for _, aircraft in ipairs(seadAircraft) do
        if typeName == aircraft then
            return true
        end
    end
    return false
end

-- ============================================
-- 優先度の計算
-- ============================================
function IADS_THREAT:calculatePriority(track)
    local priority = IADS_THREAT.PRIORITY.MEDIUM

    -- カテゴリによる基本優先度
    if track.category == IADS_THREAT.CATEGORY.ARM then
        priority = IADS_THREAT.PRIORITY.CRITICAL
    elseif track.category == IADS_THREAT.CATEGORY.SEAD then
        priority = IADS_THREAT.PRIORITY.HIGH
    elseif track.category == IADS_THREAT.CATEGORY.BOMBER then
        priority = IADS_THREAT.PRIORITY.HIGH
    elseif track.category == IADS_THREAT.CATEGORY.ATTACK then
        priority = IADS_THREAT.PRIORITY.MEDIUM
    elseif track.category == IADS_THREAT.CATEGORY.CRUISE_MISSILE then
        priority = IADS_THREAT.PRIORITY.CRITICAL
    elseif track.category == IADS_THREAT.CATEGORY.FIGHTER then
        priority = IADS_THREAT.PRIORITY.LOW
    elseif track.category == IADS_THREAT.CATEGORY.HELICOPTER then
        priority = IADS_THREAT.PRIORITY.MEDIUM
    elseif track.category == IADS_THREAT.CATEGORY.UAV then
        priority = IADS_THREAT.PRIORITY.LOW
    end

    -- 高度による補正（低高度は優先度UP）
    if track.altitude and track.altitude < 500 then
        priority = math.max(1, priority - 1)
    end

    -- 速度による補正（高速接近は優先度UP）
    if track.speed and track.speed > 300 then
        priority = math.max(1, priority - 1)
    end

    return priority
end

-- ============================================
-- トラックの更新
-- ============================================
function IADS_THREAT:updateTrack(trackId)
    local track = self.tracks[trackId]
    if not track then return false end

    -- ユニットが存在するかチェック
    if not track.unit or not track.unit:isExist() then
        track.isLost = true
        SAM_UTILS.debug("[IADS Threat] Track lost: " .. trackId)
        return false
    end

    -- 位置情報を更新
    track.position = SAM_UTILS.getUnitPosition(track.unit)
    track.velocity = track.unit:getVelocity()
    track.lastUpdated = SAM_UTILS.getTime()

    -- 高度と速度を再計算
    if track.position then
        track.altitude = track.position.y
    end
    if track.velocity then
        track.speed = math.sqrt(
            track.velocity.x^2 +
            track.velocity.y^2 +
            track.velocity.z^2
        )
        track.heading = math.deg(math.atan2(track.velocity.z, track.velocity.x))
        if track.heading < 0 then
            track.heading = track.heading + 360
        end
    end

    -- 優先度を再計算
    track.priority = self:calculatePriority(track)

    return true
end

-- ============================================
-- 検出報告の追加（センサーからの報告）
-- ============================================
function IADS_THREAT:reportDetection(unit, detectedBy)
    if not unit or not unit:isExist() then return nil end

    local unitName = unit:getName()

    -- 既存のトラックを検索
    local existingTrack = self:findTrackByUnit(unitName)

    if existingTrack then
        -- 既存トラックに検出源を追加
        if not SAM_UTILS.tableContainsValue(existingTrack.detectedBy, detectedBy) then
            table.insert(existingTrack.detectedBy, detectedBy)
        end
        self:updateTrack(existingTrack.id)
        return existingTrack
    else
        -- 新規トラック作成
        return self:createTrack(unit, detectedBy)
    end
end

-- ============================================
-- ユニット名でトラックを検索
-- ============================================
function IADS_THREAT:findTrackByUnit(unitName)
    for trackId, track in pairs(self.tracks) do
        if track.unitName == unitName then
            return track
        end
    end
    return nil
end

-- ============================================
-- 位置でトラックを検索（マージ用）
-- ============================================
function IADS_THREAT:findTrackByPosition(pos)
    if not pos then return nil end

    for trackId, track in pairs(self.tracks) do
        if track.position then
            local distance = SAM_UTILS.getDistance2D(pos, track.position)
            if distance and distance < self.mergeDistance then
                return track
            end
        end
    end
    return nil
end

-- ============================================
-- トラックの削除
-- ============================================
function IADS_THREAT:removeTrack(trackId)
    if self.tracks[trackId] then
        SAM_UTILS.debug("[IADS Threat] Track removed: " .. trackId)
        self.tracks[trackId] = nil
        return true
    end
    return false
end

-- ============================================
-- 古いトラックのクリーンアップ
-- ============================================
function IADS_THREAT:cleanupTracks()
    local currentTime = SAM_UTILS.getTime()
    local tracksToRemove = {}

    for trackId, track in pairs(self.tracks) do
        -- ロストまたはタイムアウト
        if track.isLost or (currentTime - track.lastUpdated > self.trackTimeout) then
            table.insert(tracksToRemove, trackId)
        end
    end

    for _, trackId in ipairs(tracksToRemove) do
        self:removeTrack(trackId)
    end
end

-- ============================================
-- 定期更新
-- ============================================
function IADS_THREAT:update()
    -- すべてのトラックを更新
    for trackId, _ in pairs(self.tracks) do
        self:updateTrack(trackId)
    end

    -- 古いトラックをクリーンアップ
    self:cleanupTracks()

    -- 次の更新をスケジュール
    self:scheduleUpdate()
end

-- ============================================
-- 更新スケジュール
-- ============================================
function IADS_THREAT:scheduleUpdate()
    local self_ref = self
    SAM_UTILS.scheduleFunction(function()
        self_ref:update()
    end, nil, SAM_UTILS.getTime() + self.updateInterval)
end

-- ============================================
-- 優先度でソートされたトラック一覧を取得
-- ============================================
function IADS_THREAT:getTracksByPriority()
    local trackList = {}

    for trackId, track in pairs(self.tracks) do
        if not track.isLost then
            table.insert(trackList, track)
        end
    end

    -- 優先度でソート
    table.sort(trackList, function(a, b)
        return a.priority < b.priority
    end)

    return trackList
end

-- ============================================
-- 指定位置に最も近い脅威を取得
-- ============================================
function IADS_THREAT:getNearestThreat(pos)
    if not pos then return nil end

    local nearestTrack = nil
    local nearestDistance = math.huge

    for trackId, track in pairs(self.tracks) do
        if not track.isLost and track.position then
            local distance = SAM_UTILS.getDistance2D(pos, track.position)
            if distance and distance < nearestDistance then
                nearestTrack = track
                nearestDistance = distance
            end
        end
    end

    return nearestTrack, nearestDistance
end

-- ============================================
-- 指定範囲内の脅威を取得
-- ============================================
function IADS_THREAT:getThreatsInRange(pos, range)
    if not pos then return {} end

    local threatsInRange = {}

    for trackId, track in pairs(self.tracks) do
        if not track.isLost and track.position then
            local distance = SAM_UTILS.getDistance2D(pos, track.position)
            if distance and distance <= range then
                table.insert(threatsInRange, {
                    track = track,
                    distance = distance
                })
            end
        end
    end

    -- 距離でソート
    table.sort(threatsInRange, function(a, b)
        return a.distance < b.distance
    end)

    return threatsInRange
end

-- ============================================
-- トラックを交戦中としてマーク
-- ============================================
function IADS_THREAT:markEngaged(trackId, engagedBy)
    local track = self.tracks[trackId]
    if not track then return false end

    track.isEngaged = true
    if not SAM_UTILS.tableContainsValue(track.engagedBy, engagedBy) then
        table.insert(track.engagedBy, engagedBy)
    end

    SAM_UTILS.debug("[IADS Threat] Track " .. trackId .. " engaged by " .. engagedBy)
    return true
end

-- ============================================
-- ステータス取得
-- ============================================
function IADS_THREAT:getStatus()
    local activeCount = 0
    local lostCount = 0
    local engagedCount = 0

    for trackId, track in pairs(self.tracks) do
        if track.isLost then
            lostCount = lostCount + 1
        else
            activeCount = activeCount + 1
            if track.isEngaged then
                engagedCount = engagedCount + 1
            end
        end
    end

    return {
        activeTracks = activeCount,
        lostTracks = lostCount,
        engagedTracks = engagedCount,
        totalTracks = activeCount + lostCount
    }
end

-- ============================================
-- ステータス表示
-- ============================================
function IADS_THREAT:printStatus()
    local status = self:getStatus()
    local msg = string.format(
        "[IADS Threat Status]\nActive: %d | Engaged: %d | Lost: %d",
        status.activeTracks,
        status.engagedTracks,
        status.lostTracks
    )
    SAM_UTILS.info(msg)
end

return IADS_THREAT
