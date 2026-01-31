--[[
    DCS IADS Data Link Simulation
    データリンクシミュレーション

    EWRからSAMへの目標情報転送をシミュレートし、
    SAMがダーク状態（レーダー停波）でも外部情報で
    目標追尾・発射（サイレントローンチ）を可能にする

    機能:
    - EWR→SAMへの目標トラック情報転送
    - サイレントローンチ能力（ダーク状態での発射準備）
    - トラック品質管理（更新頻度、精度）
    - データリンク遅延シミュレーション
    - リンク切断/再接続

    依存: core/utils.lua, iads/network.lua, iads/threat.lua
]]

IADS_DATALINK = {}
IADS_DATALINK.__index = IADS_DATALINK

-- ============================================
-- トラック品質
-- ============================================
IADS_DATALINK.TRACK_QUALITY = {
    EXCELLENT = "EXCELLENT", -- 高精度、リアルタイム更新
    GOOD = "GOOD",           -- 良好、2-5秒遅延
    FAIR = "FAIR",           -- 可、5-10秒遅延
    POOR = "POOR",           -- 低精度、10秒以上遅延
    STALE = "STALE"          -- 古いデータ、使用不可
}

-- ============================================
-- リンク状態
-- ============================================
IADS_DATALINK.LINK_STATUS = {
    ACTIVE = "ACTIVE",       -- アクティブ
    DEGRADED = "DEGRADED",   -- 劣化
    LOST = "LOST"            -- 切断
}

-- ============================================
-- データリンクシステム作成
-- ============================================
function IADS_DATALINK.new(iadsNetwork)
    local self = setmetatable({}, IADS_DATALINK)

    self.network = iadsNetwork
    self.links = {}                   -- リンク接続
    self.sharedTracks = {}            -- 共有トラック
    self.samTrackData = {}            -- SAMごとのトラックデータ
    self.updateInterval = 2           -- 更新間隔（秒）
    self.maxTrackAge = 15             -- トラック有効期限（秒）
    self.silentLaunchEnabled = true   -- サイレントローンチ有効
    self.linkDelay = 1                -- リンク遅延（秒）
    self.isRunning = false

    -- サイレントローンチ対応SAMタイプ
    self.silentLaunchCapableSams = {
        ["S-300PS 5P85C ln"] = true,
        ["S-300PS 5P85D ln"] = true,
        ["Patriot ln"] = true,
        ["SA-11 Buk LN 9A310M1"] = true,
    }

    return self
end

-- ============================================
-- 初期化
-- ============================================
function IADS_DATALINK:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end
    if options.maxTrackAge then
        self.maxTrackAge = options.maxTrackAge
    end
    if options.silentLaunchEnabled ~= nil then
        self.silentLaunchEnabled = options.silentLaunchEnabled
    end
    if options.linkDelay then
        self.linkDelay = options.linkDelay
    end

    -- 既存のネットワークリンクを初期化
    if self.network then
        self:initializeLinks()
    end

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[DataLink] System initialized")
    return self
end

-- ============================================
-- ネットワークリンクの初期化
-- ============================================
function IADS_DATALINK:initializeLinks()
    if not self.network then return end

    -- EWR→SAMリンクを作成
    for ewrName, ewr in pairs(self.network.ewrSites) do
        for _, samName in ipairs(ewr.linkedSAMs) do
            self:createLink(ewrName, samName, "EWR_TO_SAM")
        end
    end

    -- SAM→SAMリンクを作成
    for samName, samSite in pairs(self.network.samSites) do
        for _, linkedSamName in ipairs(samSite.linkedSAMs) do
            self:createLink(samName, linkedSamName, "SAM_TO_SAM")
        end

        -- SAMトラックデータを初期化
        self.samTrackData[samName] = {
            tracks = {},
            lastUpdate = 0,
            canSilentLaunch = self:canSilentLaunch(samSite)
        }
    end
end

-- ============================================
-- SAMがサイレントローンチ可能かチェック
-- ============================================
function IADS_DATALINK:canSilentLaunch(samSite)
    if not self.silentLaunchEnabled then return false end

    -- ユニットタイプをチェック
    for _, unitInfo in ipairs(samSite.units or {}) do
        if self.silentLaunchCapableSams[unitInfo.unitType] then
            return true
        end
    end

    return false
end

-- ============================================
-- リンク作成
-- ============================================
function IADS_DATALINK:createLink(sourceId, targetId, linkType)
    local linkId = sourceId .. "_TO_" .. targetId

    self.links[linkId] = {
        id = linkId,
        source = sourceId,
        target = targetId,
        type = linkType,
        status = IADS_DATALINK.LINK_STATUS.ACTIVE,
        quality = 1.0,  -- 1.0 = 100%品質
        delay = self.linkDelay,
        lastUpdate = SAM_UTILS.getTime(),
        messageQueue = {}
    }

    SAM_UTILS.debug("[DataLink] Created link: " .. linkId)
    return self.links[linkId]
end

-- ============================================
-- リンク状態を設定
-- ============================================
function IADS_DATALINK:setLinkStatus(linkId, status, quality)
    local link = self.links[linkId]
    if not link then return false end

    link.status = status
    if quality then
        link.quality = math.max(0, math.min(1, quality))
    end

    SAM_UTILS.debug("[DataLink] Link " .. linkId .. " status: " .. status)
    return true
end

-- ============================================
-- トラックを共有
-- ============================================
function IADS_DATALINK:shareTrack(track, sourceId)
    if not track then return end

    local trackId = track.id or track.unitName
    local currentTime = SAM_UTILS.getTime()

    -- 共有トラックを更新
    self.sharedTracks[trackId] = {
        track = track,
        source = sourceId,
        timestamp = currentTime,
        position = track.position,
        velocity = track.velocity,
        category = track.category,
        priority = track.priority
    }

    -- リンクを通じて転送
    for linkId, link in pairs(self.links) do
        if link.source == sourceId and link.status == IADS_DATALINK.LINK_STATUS.ACTIVE then
            self:queueTrackTransfer(link, trackId)
        end
    end
end

-- ============================================
-- トラック転送をキューに追加
-- ============================================
function IADS_DATALINK:queueTrackTransfer(link, trackId)
    local sharedTrack = self.sharedTracks[trackId]
    if not sharedTrack then return end

    -- 遅延を考慮してキューに追加
    local deliveryTime = SAM_UTILS.getTime() + link.delay

    table.insert(link.messageQueue, {
        trackId = trackId,
        data = SAM_UTILS.deepCopy(sharedTrack),
        deliveryTime = deliveryTime
    })
end

-- ============================================
-- メッセージキューを処理
-- ============================================
function IADS_DATALINK:processMessageQueues()
    local currentTime = SAM_UTILS.getTime()

    for linkId, link in pairs(self.links) do
        if link.status == IADS_DATALINK.LINK_STATUS.ACTIVE then
            local deliveredMessages = {}

            for i, message in ipairs(link.messageQueue) do
                if currentTime >= message.deliveryTime then
                    -- メッセージを配信
                    self:deliverTrackToSam(link.target, message.data)
                    table.insert(deliveredMessages, i)
                end
            end

            -- 配信済みメッセージを削除（逆順で削除）
            for i = #deliveredMessages, 1, -1 do
                table.remove(link.messageQueue, deliveredMessages[i])
            end
        end
    end
end

-- ============================================
-- トラックをSAMに配信
-- ============================================
function IADS_DATALINK:deliverTrackToSam(samName, trackData)
    if not self.samTrackData[samName] then
        self.samTrackData[samName] = {
            tracks = {},
            lastUpdate = 0,
            canSilentLaunch = false
        }
    end

    local samData = self.samTrackData[samName]
    local trackId = trackData.track.id or trackData.track.unitName

    -- トラックを保存
    samData.tracks[trackId] = {
        data = trackData,
        receivedAt = SAM_UTILS.getTime(),
        quality = self:calculateTrackQuality(trackData)
    }

    samData.lastUpdate = SAM_UTILS.getTime()
end

-- ============================================
-- トラック品質を計算
-- ============================================
function IADS_DATALINK:calculateTrackQuality(trackData)
    local age = SAM_UTILS.getTime() - trackData.timestamp

    if age < 2 then
        return IADS_DATALINK.TRACK_QUALITY.EXCELLENT
    elseif age < 5 then
        return IADS_DATALINK.TRACK_QUALITY.GOOD
    elseif age < 10 then
        return IADS_DATALINK.TRACK_QUALITY.FAIR
    elseif age < self.maxTrackAge then
        return IADS_DATALINK.TRACK_QUALITY.POOR
    else
        return IADS_DATALINK.TRACK_QUALITY.STALE
    end
end

-- ============================================
-- SAMが特定トラックをデータリンクで追跡可能かチェック
-- ============================================
function IADS_DATALINK:canTrackViaDL(samName, trackId)
    local samData = self.samTrackData[samName]
    if not samData then return false end

    local trackInfo = samData.tracks[trackId]
    if not trackInfo then return false end

    -- 品質チェック
    local quality = self:calculateTrackQuality(trackInfo.data)
    return quality ~= IADS_DATALINK.TRACK_QUALITY.STALE
end

-- ============================================
-- SAMがサイレントローンチ可能かチェック（特定トラックに対して）
-- ============================================
function IADS_DATALINK:canSilentLaunchAt(samName, trackId)
    local samData = self.samTrackData[samName]
    if not samData or not samData.canSilentLaunch then return false end

    -- トラック品質がGOOD以上必要
    local trackInfo = samData.tracks[trackId]
    if not trackInfo then return false end

    local quality = self:calculateTrackQuality(trackInfo.data)
    return quality == IADS_DATALINK.TRACK_QUALITY.EXCELLENT or
           quality == IADS_DATALINK.TRACK_QUALITY.GOOD
end

-- ============================================
-- SAMの利用可能トラックを取得
-- ============================================
function IADS_DATALINK:getAvailableTracks(samName)
    local samData = self.samTrackData[samName]
    if not samData then return {} end

    local availableTracks = {}
    local currentTime = SAM_UTILS.getTime()

    for trackId, trackInfo in pairs(samData.tracks) do
        local quality = self:calculateTrackQuality(trackInfo.data)
        if quality ~= IADS_DATALINK.TRACK_QUALITY.STALE then
            table.insert(availableTracks, {
                trackId = trackId,
                data = trackInfo.data,
                quality = quality,
                age = currentTime - trackInfo.data.timestamp
            })
        end
    end

    -- 品質でソート（良い順）
    table.sort(availableTracks, function(a, b)
        local qualityOrder = {
            [IADS_DATALINK.TRACK_QUALITY.EXCELLENT] = 1,
            [IADS_DATALINK.TRACK_QUALITY.GOOD] = 2,
            [IADS_DATALINK.TRACK_QUALITY.FAIR] = 3,
            [IADS_DATALINK.TRACK_QUALITY.POOR] = 4
        }
        return (qualityOrder[a.quality] or 5) < (qualityOrder[b.quality] or 5)
    end)

    return availableTracks
end

-- ============================================
-- 古いトラックをクリーンアップ
-- ============================================
function IADS_DATALINK:cleanupStaleTracks()
    for samName, samData in pairs(self.samTrackData) do
        local tracksToRemove = {}

        for trackId, trackInfo in pairs(samData.tracks) do
            local quality = self:calculateTrackQuality(trackInfo.data)
            if quality == IADS_DATALINK.TRACK_QUALITY.STALE then
                table.insert(tracksToRemove, trackId)
            end
        end

        for _, trackId in ipairs(tracksToRemove) do
            samData.tracks[trackId] = nil
        end
    end

    -- 共有トラックもクリーンアップ
    local sharedToRemove = {}
    local currentTime = SAM_UTILS.getTime()

    for trackId, sharedTrack in pairs(self.sharedTracks) do
        if currentTime - sharedTrack.timestamp > self.maxTrackAge then
            table.insert(sharedToRemove, trackId)
        end
    end

    for _, trackId in ipairs(sharedToRemove) do
        self.sharedTracks[trackId] = nil
    end
end

-- ============================================
-- EWRから検知情報を収集して共有
-- ============================================
function IADS_DATALINK:collectEwrDetections()
    if not self.network then return end

    -- EWRの検知情報を取得（実際のDCSでは検知システムと連携）
    -- ここではIADSネットワークの脅威情報を使用
    if self.network.threats then
        for threatId, threat in pairs(self.network.threats) do
            if not threat.isLost then
                -- 最も近いEWRを見つけて送信元とする
                local sourceEwr = self:findNearestEwr(threat.position)
                if sourceEwr then
                    self:shareTrack(threat, sourceEwr)
                end
            end
        end
    end
end

-- ============================================
-- 位置に最も近いEWRを見つける
-- ============================================
function IADS_DATALINK:findNearestEwr(position)
    if not self.network or not position then return nil end

    local nearestEwr = nil
    local nearestDistance = math.huge

    for ewrName, ewr in pairs(self.network.ewrSites) do
        if ewr.position and ewr.isActive then
            local distance = SAM_UTILS.getDistance2D(position, ewr.position)
            if distance and distance < nearestDistance then
                nearestDistance = distance
                nearestEwr = ewrName
            end
        end
    end

    return nearestEwr
end

-- ============================================
-- 定期更新
-- ============================================
function IADS_DATALINK:update()
    if not self.isRunning then return end

    -- EWR検知情報を収集して共有
    self:collectEwrDetections()

    -- メッセージキューを処理
    self:processMessageQueues()

    -- 古いトラックをクリーンアップ
    self:cleanupStaleTracks()

    -- 次の更新をスケジュール
    self:scheduleUpdate()
end

-- ============================================
-- 更新スケジュール
-- ============================================
function IADS_DATALINK:scheduleUpdate()
    local dl = self
    SAM_UTILS.scheduleFunction(function()
        dl:update()
    end, nil, SAM_UTILS.getTime() + self.updateInterval)
end

-- ============================================
-- 停止
-- ============================================
function IADS_DATALINK:stop()
    self.isRunning = false
end

-- ============================================
-- ステータス取得
-- ============================================
function IADS_DATALINK:getStatus()
    local status = {
        linkCount = 0,
        activeLinks = 0,
        degradedLinks = 0,
        lostLinks = 0,
        sharedTracks = 0,
        silentLaunchCapableSams = 0,
        links = {},
        sams = {}
    }

    for linkId, link in pairs(self.links) do
        status.linkCount = status.linkCount + 1

        if link.status == IADS_DATALINK.LINK_STATUS.ACTIVE then
            status.activeLinks = status.activeLinks + 1
        elseif link.status == IADS_DATALINK.LINK_STATUS.DEGRADED then
            status.degradedLinks = status.degradedLinks + 1
        else
            status.lostLinks = status.lostLinks + 1
        end

        table.insert(status.links, {
            id = linkId,
            type = link.type,
            status = link.status,
            queueSize = #link.messageQueue
        })
    end

    for trackId, _ in pairs(self.sharedTracks) do
        status.sharedTracks = status.sharedTracks + 1
    end

    for samName, samData in pairs(self.samTrackData) do
        local trackCount = 0
        for _, _ in pairs(samData.tracks) do
            trackCount = trackCount + 1
        end

        if samData.canSilentLaunch then
            status.silentLaunchCapableSams = status.silentLaunchCapableSams + 1
        end

        table.insert(status.sams, {
            name = samName,
            trackCount = trackCount,
            canSilentLaunch = samData.canSilentLaunch
        })
    end

    return status
end

-- ============================================
-- ステータス表示
-- ============================================
function IADS_DATALINK:printStatus()
    local status = self:getStatus()

    local msg = "[DataLink Status]\n"
    msg = msg .. string.format("Links: %d (Active: %d, Degraded: %d, Lost: %d)\n",
        status.linkCount, status.activeLinks, status.degradedLinks, status.lostLinks)
    msg = msg .. string.format("Shared Tracks: %d | Silent Launch SAMs: %d\n",
        status.sharedTracks, status.silentLaunchCapableSams)

    for _, sam in ipairs(status.sams) do
        local slStr = sam.canSilentLaunch and " [SL]" or ""
        msg = msg .. string.format("  %s: %d tracks%s\n",
            sam.name, sam.trackCount, slStr)
    end

    SAM_UTILS.info(msg, 20)
end

return IADS_DATALINK
