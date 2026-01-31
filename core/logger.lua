--[[
    DCS SAM Statistics and Logging System
    統計・ログシステム

    IADSの活動を記録し、統計を収集する

    機能:
    - 交戦記録（発射、命中、撃墜）
    - SAM状態の履歴
    - 脅威検知ログ
    - SEAD攻撃記録
    - ミッション終了レポート生成
    - リアルタイム統計表示

    依存: core/utils.lua
]]

SAM_LOGGER = {}
SAM_LOGGER.__index = SAM_LOGGER

-- ============================================
-- ログレベル
-- ============================================
SAM_LOGGER.LOG_LEVEL = {
    DEBUG = 1,
    INFO = 2,
    WARNING = 3,
    ERROR = 4,
    CRITICAL = 5
}

-- ============================================
-- イベントタイプ
-- ============================================
SAM_LOGGER.EVENT_TYPE = {
    -- SAM関連
    SAM_ACTIVATED = "SAM_ACTIVATED",
    SAM_DEACTIVATED = "SAM_DEACTIVATED",
    SAM_SUPPRESSED = "SAM_SUPPRESSED",
    SAM_DESTROYED = "SAM_DESTROYED",
    SAM_MISSILE_FIRED = "SAM_MISSILE_FIRED",

    -- 交戦関連
    ENGAGEMENT_START = "ENGAGEMENT_START",
    ENGAGEMENT_END = "ENGAGEMENT_END",
    TARGET_HIT = "TARGET_HIT",
    TARGET_KILLED = "TARGET_KILLED",
    TARGET_MISSED = "TARGET_MISSED",

    -- 脅威関連
    THREAT_DETECTED = "THREAT_DETECTED",
    THREAT_LOST = "THREAT_LOST",
    ARM_LAUNCHED = "ARM_LAUNCHED",
    ARM_IMPACT = "ARM_IMPACT",

    -- システム関連
    EMCON_CHANGED = "EMCON_CHANGED",
    AMMO_LOW = "AMMO_LOW",
    AMMO_EMPTY = "AMMO_EMPTY",
    NETWORK_STATUS = "NETWORK_STATUS"
}

-- ============================================
-- ロガー作成
-- ============================================
function SAM_LOGGER.new()
    local self = setmetatable({}, SAM_LOGGER)

    self.logs = {}                    -- ログエントリ
    self.statistics = {}              -- 統計データ
    self.engagements = {}             -- 交戦記録
    self.activeEngagements = {}       -- 進行中の交戦
    self.minLogLevel = SAM_LOGGER.LOG_LEVEL.INFO
    self.maxLogEntries = 1000         -- 最大ログ保持数
    self.eventHandlers = {}           -- カスタムイベントハンドラ
    self.missionStartTime = 0
    self.iadsNetwork = nil

    -- 統計初期化
    self:initStatistics()

    return self
end

-- ============================================
-- 統計初期化
-- ============================================
function SAM_LOGGER:initStatistics()
    self.statistics = {
        -- SAM統計
        sam = {
            totalSites = 0,
            sitesDestroyed = 0,
            totalMissilesFired = 0,
            totalHits = 0,
            totalKills = 0,
            suppressionEvents = 0,
            activationCount = 0,
            deactivationCount = 0
        },

        -- 脅威統計
        threats = {
            totalDetected = 0,
            totalTracked = 0,
            totalEngaged = 0,
            totalKilled = 0,
            totalEscaped = 0,
            byCategory = {}
        },

        -- SEAD統計
        sead = {
            armsLaunched = 0,
            armsImpacted = 0,
            samsSuppressed = 0,
            samsDestroyed = 0
        },

        -- 効率統計
        efficiency = {
            hitRate = 0,
            killRate = 0,
            missilePerKill = 0
        }
    }
end

-- ============================================
-- 初期化
-- ============================================
function SAM_LOGGER:init(options)
    options = options or {}

    if options.minLogLevel then
        self.minLogLevel = options.minLogLevel
    end
    if options.maxLogEntries then
        self.maxLogEntries = options.maxLogEntries
    end
    if options.iadsNetwork then
        self.iadsNetwork = options.iadsNetwork
    end

    self.missionStartTime = SAM_UTILS.getTime()

    -- DCSイベントハンドラ登録
    self:registerDCSEventHandler()

    SAM_UTILS.debug("[Logger] System initialized")
    return self
end

-- ============================================
-- DCSイベントハンドラ登録
-- ============================================
function SAM_LOGGER:registerDCSEventHandler()
    local logger = self

    local handler = {}
    function handler:onEvent(event)
        logger:onDCSEvent(event)
    end

    world.addEventHandler(handler)
end

-- ============================================
-- DCSイベント処理
-- ============================================
function SAM_LOGGER:onDCSEvent(event)
    if event.id == world.event.S_EVENT_SHOT then
        self:onShot(event)
    elseif event.id == world.event.S_EVENT_HIT then
        self:onHit(event)
    elseif event.id == world.event.S_EVENT_KILL then
        -- KILL は別途検出されないため DEAD を使用
    elseif event.id == world.event.S_EVENT_DEAD then
        self:onDead(event)
    end
end

-- ============================================
-- 発射イベント
-- ============================================
function SAM_LOGGER:onShot(event)
    local initiator = event.initiator
    if not initiator then return end

    local weapon = event.weapon
    if not weapon then return end

    local initiatorName = initiator:getName()
    local weaponType = weapon:getTypeName()

    -- SAMからの発射かチェック
    local group = initiator:getGroup()
    if group and self.iadsNetwork then
        local groupName = group:getName()
        if self.iadsNetwork.samSites[groupName] then
            -- SAMミサイル発射
            self.statistics.sam.totalMissilesFired =
                self.statistics.sam.totalMissilesFired + 1

            self:logEvent(SAM_LOGGER.EVENT_TYPE.SAM_MISSILE_FIRED, {
                samSite = groupName,
                launcher = initiatorName,
                weapon = weaponType,
                target = weapon:getTarget() and weapon:getTarget():getName() or "unknown"
            })

            -- 交戦記録を作成
            self:startEngagement(groupName, weapon)
        end
    end

    -- ARM発射チェック
    if SAM_CONFIG and SAM_CONFIG.isARM(weaponType) then
        self.statistics.sead.armsLaunched = self.statistics.sead.armsLaunched + 1

        self:logEvent(SAM_LOGGER.EVENT_TYPE.ARM_LAUNCHED, {
            shooter = initiatorName,
            weapon = weaponType
        })
    end
end

-- ============================================
-- 命中イベント
-- ============================================
function SAM_LOGGER:onHit(event)
    local initiator = event.initiator
    local target = event.target

    if not initiator or not target then return end

    local initiatorName = initiator:getName()
    local targetName = target:getName()

    -- SAMからの命中かチェック
    local group = initiator:getGroup()
    if group and self.iadsNetwork then
        local groupName = group:getName()
        if self.iadsNetwork.samSites[groupName] then
            self.statistics.sam.totalHits = self.statistics.sam.totalHits + 1

            self:logEvent(SAM_LOGGER.EVENT_TYPE.TARGET_HIT, {
                samSite = groupName,
                target = targetName
            })

            -- 交戦記録を更新
            self:updateEngagement(groupName, "hit", targetName)
        end
    end
end

-- ============================================
-- 撃破イベント
-- ============================================
function SAM_LOGGER:onDead(event)
    local initiator = event.initiator
    local target = event.target

    if not target then return end

    local targetName = target:getName()

    -- ターゲットがSAMサイトの一部かチェック
    if self.iadsNetwork then
        local group = target:getGroup()
        if group then
            local groupName = group:getName()
            if self.iadsNetwork.samSites[groupName] then
                -- SAMが破壊された
                self:logEvent(SAM_LOGGER.EVENT_TYPE.SAM_DESTROYED, {
                    samSite = groupName,
                    unit = targetName
                })
            end
        end
    end

    -- 撃墜記録
    if initiator then
        local shooterGroup = initiator:getGroup()
        if shooterGroup and self.iadsNetwork then
            local shooterGroupName = shooterGroup:getName()
            if self.iadsNetwork.samSites[shooterGroupName] then
                self.statistics.sam.totalKills = self.statistics.sam.totalKills + 1
                self.statistics.threats.totalKilled = self.statistics.threats.totalKilled + 1

                self:logEvent(SAM_LOGGER.EVENT_TYPE.TARGET_KILLED, {
                    samSite = shooterGroupName,
                    target = targetName
                })

                -- 交戦記録を更新
                self:updateEngagement(shooterGroupName, "kill", targetName)
            end
        end
    end
end

-- ============================================
-- ログエントリ追加
-- ============================================
function SAM_LOGGER:log(level, message, data)
    if level < self.minLogLevel then return end

    local entry = {
        timestamp = SAM_UTILS.getTime(),
        missionTime = SAM_UTILS.getTime() - self.missionStartTime,
        level = level,
        message = message,
        data = data
    }

    table.insert(self.logs, entry)

    -- 最大数を超えたら古いログを削除
    while #self.logs > self.maxLogEntries do
        table.remove(self.logs, 1)
    end

    -- デバッグモードなら画面出力
    if SAM_UTILS.DEBUG and level >= SAM_LOGGER.LOG_LEVEL.INFO then
        SAM_UTILS.debug("[Log] " .. message)
    end
end

-- ============================================
-- イベントログ
-- ============================================
function SAM_LOGGER:logEvent(eventType, data)
    local message = eventType
    if data then
        if data.samSite then
            message = message .. " - " .. data.samSite
        end
        if data.target then
            message = message .. " -> " .. data.target
        end
    end

    self:log(SAM_LOGGER.LOG_LEVEL.INFO, message, {
        eventType = eventType,
        eventData = data
    })

    -- カスタムイベントハンドラを呼び出し
    if self.eventHandlers[eventType] then
        for _, handler in ipairs(self.eventHandlers[eventType]) do
            handler(data)
        end
    end
end

-- ============================================
-- カスタムイベントハンドラ登録
-- ============================================
function SAM_LOGGER:addEventListener(eventType, handler)
    if not self.eventHandlers[eventType] then
        self.eventHandlers[eventType] = {}
    end
    table.insert(self.eventHandlers[eventType], handler)
end

-- ============================================
-- 交戦記録開始
-- ============================================
function SAM_LOGGER:startEngagement(samSite, weapon)
    local engagementId = samSite .. "_" .. SAM_UTILS.getTime()

    local target = weapon:getTarget()

    self.activeEngagements[engagementId] = {
        id = engagementId,
        samSite = samSite,
        startTime = SAM_UTILS.getTime(),
        target = target and target:getName() or "unknown",
        targetType = target and target:getTypeName() or "unknown",
        missilesFired = 1,
        hits = 0,
        result = "pending"
    }

    self.statistics.threats.totalEngaged = self.statistics.threats.totalEngaged + 1
end

-- ============================================
-- 交戦記録更新
-- ============================================
function SAM_LOGGER:updateEngagement(samSite, event, target)
    -- 該当する交戦を検索
    for id, engagement in pairs(self.activeEngagements) do
        if engagement.samSite == samSite and
           (engagement.target == target or target == nil) then

            if event == "hit" then
                engagement.hits = engagement.hits + 1
            elseif event == "kill" then
                engagement.result = "kill"
                engagement.endTime = SAM_UTILS.getTime()

                -- 完了した交戦を記録に移動
                table.insert(self.engagements, engagement)
                self.activeEngagements[id] = nil
            elseif event == "miss" then
                engagement.result = "miss"
                engagement.endTime = SAM_UTILS.getTime()

                table.insert(self.engagements, engagement)
                self.activeEngagements[id] = nil
            end

            break
        end
    end
end

-- ============================================
-- SAMアクティブ化記録
-- ============================================
function SAM_LOGGER:logSamActivated(groupName)
    self.statistics.sam.activationCount = self.statistics.sam.activationCount + 1
    self:logEvent(SAM_LOGGER.EVENT_TYPE.SAM_ACTIVATED, {
        samSite = groupName
    })
end

-- ============================================
-- SAM停波記録
-- ============================================
function SAM_LOGGER:logSamDeactivated(groupName)
    self.statistics.sam.deactivationCount = self.statistics.sam.deactivationCount + 1
    self:logEvent(SAM_LOGGER.EVENT_TYPE.SAM_DEACTIVATED, {
        samSite = groupName
    })
end

-- ============================================
-- SAM停波（SEAD）記録
-- ============================================
function SAM_LOGGER:logSamSuppressed(groupName, weaponType)
    self.statistics.sam.suppressionEvents = self.statistics.sam.suppressionEvents + 1
    self.statistics.sead.samsSuppressed = self.statistics.sead.samsSuppressed + 1
    self:logEvent(SAM_LOGGER.EVENT_TYPE.SAM_SUPPRESSED, {
        samSite = groupName,
        weapon = weaponType
    })
end

-- ============================================
-- 脅威検知記録
-- ============================================
function SAM_LOGGER:logThreatDetected(threat, detectedBy)
    self.statistics.threats.totalDetected = self.statistics.threats.totalDetected + 1

    local category = threat.category or "UNKNOWN"
    if not self.statistics.threats.byCategory[category] then
        self.statistics.threats.byCategory[category] = 0
    end
    self.statistics.threats.byCategory[category] =
        self.statistics.threats.byCategory[category] + 1

    self:logEvent(SAM_LOGGER.EVENT_TYPE.THREAT_DETECTED, {
        target = threat.unitName,
        category = category,
        detectedBy = detectedBy
    })
end

-- ============================================
-- EMCONレベル変更記録
-- ============================================
function SAM_LOGGER:logEmconChanged(oldLevel, newLevel)
    self:logEvent(SAM_LOGGER.EVENT_TYPE.EMCON_CHANGED, {
        oldLevel = oldLevel,
        newLevel = newLevel
    })
end

-- ============================================
-- 効率統計を計算
-- ============================================
function SAM_LOGGER:calculateEfficiency()
    local stats = self.statistics

    if stats.sam.totalMissilesFired > 0 then
        stats.efficiency.hitRate =
            (stats.sam.totalHits / stats.sam.totalMissilesFired) * 100

        stats.efficiency.killRate =
            (stats.sam.totalKills / stats.sam.totalMissilesFired) * 100

        if stats.sam.totalKills > 0 then
            stats.efficiency.missilePerKill =
                stats.sam.totalMissilesFired / stats.sam.totalKills
        end
    end

    return stats.efficiency
end

-- ============================================
-- 統計取得
-- ============================================
function SAM_LOGGER:getStatistics()
    self:calculateEfficiency()
    return self.statistics
end

-- ============================================
-- 最近のログを取得
-- ============================================
function SAM_LOGGER:getRecentLogs(count)
    count = count or 20
    local result = {}

    local startIdx = math.max(1, #self.logs - count + 1)
    for i = startIdx, #self.logs do
        table.insert(result, self.logs[i])
    end

    return result
end

-- ============================================
-- イベントタイプでログをフィルタ
-- ============================================
function SAM_LOGGER:getLogsByEventType(eventType)
    local result = {}

    for _, entry in ipairs(self.logs) do
        if entry.data and entry.data.eventType == eventType then
            table.insert(result, entry)
        end
    end

    return result
end

-- ============================================
-- レポート生成
-- ============================================
function SAM_LOGGER:generateReport()
    self:calculateEfficiency()
    local stats = self.statistics

    local report = "====== IADS Mission Report ======\n\n"

    -- ミッション時間
    local missionDuration = SAM_UTILS.getTime() - self.missionStartTime
    local hours = math.floor(missionDuration / 3600)
    local minutes = math.floor((missionDuration % 3600) / 60)
    report = report .. string.format("Mission Duration: %02d:%02d\n\n", hours, minutes)

    -- SAM統計
    report = report .. "=== SAM Statistics ===\n"
    report = report .. string.format("Missiles Fired: %d\n", stats.sam.totalMissilesFired)
    report = report .. string.format("Hits: %d\n", stats.sam.totalHits)
    report = report .. string.format("Kills: %d\n", stats.sam.totalKills)
    report = report .. string.format("Suppression Events: %d\n", stats.sam.suppressionEvents)
    report = report .. string.format("Activations: %d\n", stats.sam.activationCount)
    report = report .. string.format("Deactivations: %d\n\n", stats.sam.deactivationCount)

    -- 効率
    report = report .. "=== Efficiency ===\n"
    report = report .. string.format("Hit Rate: %.1f%%\n", stats.efficiency.hitRate)
    report = report .. string.format("Kill Rate: %.1f%%\n", stats.efficiency.killRate)
    report = report .. string.format("Missiles per Kill: %.2f\n\n", stats.efficiency.missilePerKill)

    -- 脅威統計
    report = report .. "=== Threat Statistics ===\n"
    report = report .. string.format("Detected: %d\n", stats.threats.totalDetected)
    report = report .. string.format("Engaged: %d\n", stats.threats.totalEngaged)
    report = report .. string.format("Killed: %d\n", stats.threats.totalKilled)

    if next(stats.threats.byCategory) then
        report = report .. "By Category:\n"
        for category, count in pairs(stats.threats.byCategory) do
            report = report .. string.format("  %s: %d\n", category, count)
        end
    end
    report = report .. "\n"

    -- SEAD統計
    report = report .. "=== SEAD Statistics ===\n"
    report = report .. string.format("ARMs Launched: %d\n", stats.sead.armsLaunched)
    report = report .. string.format("SAMs Suppressed: %d\n", stats.sead.samsSuppressed)

    report = report .. "\n====== End Report ======\n"

    return report
end

-- ============================================
-- 統計表示
-- ============================================
function SAM_LOGGER:printStatistics()
    self:calculateEfficiency()
    local stats = self.statistics

    local msg = "[IADS Statistics]\n"
    msg = msg .. string.format("Missiles: %d | Hits: %d | Kills: %d\n",
        stats.sam.totalMissilesFired, stats.sam.totalHits, stats.sam.totalKills)
    msg = msg .. string.format("Hit Rate: %.1f%% | Kill Rate: %.1f%%\n",
        stats.efficiency.hitRate, stats.efficiency.killRate)
    msg = msg .. string.format("Threats Detected: %d | Engaged: %d\n",
        stats.threats.totalDetected, stats.threats.totalEngaged)
    msg = msg .. string.format("SEAD: %d ARMs | %d Suppressions\n",
        stats.sead.armsLaunched, stats.sead.samsSuppressed)

    SAM_UTILS.info(msg, 20)
end

-- ============================================
-- レポート表示
-- ============================================
function SAM_LOGGER:printReport()
    local report = self:generateReport()
    SAM_UTILS.info(report, 60)
end

return SAM_LOGGER
