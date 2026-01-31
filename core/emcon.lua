--[[
    DCS SAM Emission Control (EMCON) System
    動的レーダー運用（エミッションコントロール）システム

    SAMレーダーの送波パターンを制御し、SEAD機による
    位置特定を困難にする

    機能:
    - EMCONレベル管理（全面停波～全面送波）
    - 点滅モード（短時間照射→停波サイクル）
    - スケジュール運用（時間帯別のレーダー運用）
    - 脅威対応モード（脅威検知時のみ送波）
    - ランダム運用パターン

    依存: core/utils.lua
]]

SAM_EMCON = {}
SAM_EMCON.__index = SAM_EMCON

-- ============================================
-- EMCONレベル
-- ============================================
SAM_EMCON.LEVEL = {
    ALPHA = "ALPHA",     -- 全面送波禁止（完全沈黙）
    BRAVO = "BRAVO",     -- 最小限送波（EWRのみ）
    CHARLIE = "CHARLIE", -- 制限送波（点滅モード）
    DELTA = "DELTA",     -- 通常運用
    ECHO = "ECHO"        -- 全面送波（最大警戒）
}

-- ============================================
-- 運用モード
-- ============================================
SAM_EMCON.MODE = {
    STATIC = "STATIC",           -- 固定状態
    BLINK = "BLINK",             -- 点滅モード
    RANDOM = "RANDOM",           -- ランダム運用
    SCHEDULED = "SCHEDULED",     -- スケジュール運用
    THREAT_REACTIVE = "THREAT_REACTIVE"  -- 脅威対応
}

-- ============================================
-- EMCONシステム作成
-- ============================================
function SAM_EMCON.new()
    local self = setmetatable({}, SAM_EMCON)

    self.currentLevel = SAM_EMCON.LEVEL.DELTA
    self.mode = SAM_EMCON.MODE.STATIC
    self.samStates = {}          -- 各SAMの現在状態
    self.blinkProfiles = {}      -- 点滅プロファイル
    self.schedules = {}          -- スケジュール
    self.updateInterval = 1      -- 更新間隔（秒）
    self.iadsNetwork = nil
    self.isRunning = false

    -- 点滅モードデフォルト設定
    self.defaultBlinkProfile = {
        onDuration = 10,         -- 送波時間（秒）
        offDuration = 20,        -- 停波時間（秒）
        randomize = true,        -- ランダム化
        randomRange = 5          -- ランダム幅（±秒）
    }

    return self
end

-- ============================================
-- 初期化
-- ============================================
function SAM_EMCON:init(options)
    options = options or {}

    if options.level then
        self.currentLevel = options.level
    end
    if options.mode then
        self.mode = options.mode
    end
    if options.iadsNetwork then
        self.iadsNetwork = options.iadsNetwork
    end
    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end
    if options.blinkProfile then
        self.defaultBlinkProfile = SAM_UTILS.mergeTables(
            self.defaultBlinkProfile, options.blinkProfile)
    end

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[EMCON] System initialized - Level: " .. self.currentLevel)
    return self
end

-- ============================================
-- IADSネットワーク連携
-- ============================================
function SAM_EMCON:setIADSNetwork(network)
    self.iadsNetwork = network

    -- 既存のSAMサイトを登録
    if network and network.samSites then
        for groupName, samSite in pairs(network.samSites) do
            self:registerSam(groupName)
        end
    end
end

-- ============================================
-- SAMを登録
-- ============================================
function SAM_EMCON:registerSam(groupName, customProfile)
    self.samStates[groupName] = {
        groupName = groupName,
        isEmitting = false,
        blinkProfile = customProfile or SAM_UTILS.deepCopy(self.defaultBlinkProfile),
        nextToggleTime = 0,
        mode = self.mode,
        overrideLevel = nil  -- 個別オーバーライド
    }

    SAM_UTILS.debug("[EMCON] Registered SAM: " .. groupName)
end

-- ============================================
-- EMCONレベルを設定
-- ============================================
function SAM_EMCON:setLevel(level)
    local oldLevel = self.currentLevel
    self.currentLevel = level

    SAM_UTILS.debug("[EMCON] Level changed: " .. oldLevel .. " -> " .. level)

    -- レベルに応じて全SAMの状態を更新
    self:applyLevelToAll()

    return true
end

-- ============================================
-- 運用モードを設定
-- ============================================
function SAM_EMCON:setMode(mode)
    self.mode = mode

    -- 全SAMのモードを更新
    for groupName, state in pairs(self.samStates) do
        state.mode = mode
        state.nextToggleTime = SAM_UTILS.getTime()
    end

    SAM_UTILS.debug("[EMCON] Mode changed to: " .. mode)
end

-- ============================================
-- レベルを全SAMに適用
-- ============================================
function SAM_EMCON:applyLevelToAll()
    for groupName, _ in pairs(self.samStates) do
        self:applyLevelToSam(groupName)
    end
end

-- ============================================
-- レベルを個別SAMに適用
-- ============================================
function SAM_EMCON:applyLevelToSam(groupName)
    local state = self.samStates[groupName]
    if not state then return end

    local level = state.overrideLevel or self.currentLevel

    if level == SAM_EMCON.LEVEL.ALPHA then
        -- 完全沈黙
        self:setSamEmitting(groupName, false)
        state.mode = SAM_EMCON.MODE.STATIC
    elseif level == SAM_EMCON.LEVEL.BRAVO then
        -- 最小限（SAMは停波、EWRのみ）
        self:setSamEmitting(groupName, false)
        state.mode = SAM_EMCON.MODE.STATIC
    elseif level == SAM_EMCON.LEVEL.CHARLIE then
        -- 点滅モード
        state.mode = SAM_EMCON.MODE.BLINK
        state.nextToggleTime = SAM_UTILS.getTime()
    elseif level == SAM_EMCON.LEVEL.DELTA then
        -- 通常運用（設定されたモードに従う）
        state.mode = self.mode
    elseif level == SAM_EMCON.LEVEL.ECHO then
        -- 全面送波
        self:setSamEmitting(groupName, true)
        state.mode = SAM_EMCON.MODE.STATIC
    end
end

-- ============================================
-- SAMの送波状態を設定
-- ============================================
function SAM_EMCON:setSamEmitting(groupName, emitting)
    local state = self.samStates[groupName]
    if not state then return false end

    state.isEmitting = emitting

    -- IADSネットワークを通じて実際に状態を変更
    if self.iadsNetwork then
        if emitting then
            self.iadsNetwork:activateSam(groupName)
        else
            self.iadsNetwork:deactivateSam(groupName)
        end
    else
        -- IADSなしの場合、直接グループを操作
        local group = Group.getByName(groupName)
        if group then
            if emitting then
                SAM_UTILS.setGroupAlarmState(group, SAM_UTILS.ALARM_STATE.RED)
            else
                SAM_UTILS.setGroupAlarmState(group, SAM_UTILS.ALARM_STATE.GREEN)
            end
        end
    end

    return true
end

-- ============================================
-- 点滅プロファイルを設定
-- ============================================
function SAM_EMCON:setBlinkProfile(groupName, profile)
    local state = self.samStates[groupName]
    if not state then return false end

    state.blinkProfile = SAM_UTILS.mergeTables(state.blinkProfile, profile)
    return true
end

-- ============================================
-- 個別オーバーライドを設定
-- ============================================
function SAM_EMCON:setOverride(groupName, level)
    local state = self.samStates[groupName]
    if not state then return false end

    state.overrideLevel = level
    self:applyLevelToSam(groupName)

    SAM_UTILS.debug("[EMCON] Override set for " .. groupName .. ": " .. (level or "none"))
    return true
end

-- ============================================
-- 個別オーバーライドをクリア
-- ============================================
function SAM_EMCON:clearOverride(groupName)
    return self:setOverride(groupName, nil)
end

-- ============================================
-- スケジュールを追加
-- ============================================
function SAM_EMCON:addSchedule(schedule)
    --[[
        schedule = {
            startTime = 秒（ミッション開始からの経過時間）,
            endTime = 秒,
            level = EMCONレベル,
            mode = 運用モード（オプション）,
            targets = {グループ名のリスト}（nilなら全体）
        }
    ]]
    table.insert(self.schedules, schedule)

    -- 開始時間でソート
    table.sort(self.schedules, function(a, b)
        return a.startTime < b.startTime
    end)

    SAM_UTILS.debug("[EMCON] Schedule added")
end

-- ============================================
-- 時間ベースのスケジュールを追加（時:分形式）
-- ============================================
function SAM_EMCON:addTimeSchedule(startHour, startMin, endHour, endMin, level, mode)
    local startTime = startHour * 3600 + startMin * 60
    local endTime = endHour * 3600 + endMin * 60

    self:addSchedule({
        startTime = startTime,
        endTime = endTime,
        level = level,
        mode = mode
    })
end

-- ============================================
-- 定期更新
-- ============================================
function SAM_EMCON:update()
    if not self.isRunning then return end

    local currentTime = SAM_UTILS.getTime()

    -- スケジュールチェック
    self:checkSchedules(currentTime)

    -- 各SAMの状態を更新
    for groupName, state in pairs(self.samStates) do
        self:updateSamState(groupName, state, currentTime)
    end

    -- 次の更新をスケジュール
    self:scheduleUpdate()
end

-- ============================================
-- スケジュールチェック
-- ============================================
function SAM_EMCON:checkSchedules(currentTime)
    for _, schedule in ipairs(self.schedules) do
        if currentTime >= schedule.startTime and currentTime < schedule.endTime then
            -- スケジュール期間内
            if schedule.targets then
                -- 特定のSAMのみ
                for _, groupName in ipairs(schedule.targets) do
                    self:setOverride(groupName, schedule.level)
                end
            else
                -- 全体
                if self.currentLevel ~= schedule.level then
                    self:setLevel(schedule.level)
                    if schedule.mode then
                        self:setMode(schedule.mode)
                    end
                end
            end
        end
    end
end

-- ============================================
-- 個別SAMの状態更新
-- ============================================
function SAM_EMCON:updateSamState(groupName, state, currentTime)
    if state.mode == SAM_EMCON.MODE.BLINK then
        -- 点滅モード処理
        if currentTime >= state.nextToggleTime then
            self:toggleBlink(groupName, state, currentTime)
        end
    elseif state.mode == SAM_EMCON.MODE.RANDOM then
        -- ランダム運用
        if currentTime >= state.nextToggleTime then
            self:randomToggle(groupName, state, currentTime)
        end
    end
    -- STATICとTHREAT_REACTIVEは外部トリガーで制御
end

-- ============================================
-- 点滅トグル
-- ============================================
function SAM_EMCON:toggleBlink(groupName, state, currentTime)
    local profile = state.blinkProfile

    -- 送波状態を反転
    local newEmitting = not state.isEmitting
    self:setSamEmitting(groupName, newEmitting)

    -- 次のトグル時間を計算
    local duration
    if newEmitting then
        duration = profile.onDuration
    else
        duration = profile.offDuration
    end

    -- ランダム化
    if profile.randomize then
        local randomOffset = SAM_UTILS.random(-profile.randomRange, profile.randomRange)
        duration = math.max(1, duration + randomOffset)
    end

    state.nextToggleTime = currentTime + duration
end

-- ============================================
-- ランダムトグル
-- ============================================
function SAM_EMCON:randomToggle(groupName, state, currentTime)
    -- 50%の確率で送波/停波
    local emit = SAM_UTILS.random(1, 100) > 50
    self:setSamEmitting(groupName, emit)

    -- 次のトグルまでランダムな時間
    local nextDuration = SAM_UTILS.random(10, 60)
    state.nextToggleTime = currentTime + nextDuration
end

-- ============================================
-- 脅威対応モード：脅威検知時に送波
-- ============================================
function SAM_EMCON:onThreatDetected(groupName, threat)
    local state = self.samStates[groupName]
    if not state then return end

    if state.mode == SAM_EMCON.MODE.THREAT_REACTIVE then
        self:setSamEmitting(groupName, true)
        SAM_UTILS.debug("[EMCON] Threat reactive: " .. groupName .. " activated")
    end
end

-- ============================================
-- 脅威対応モード：脅威消失時に停波
-- ============================================
function SAM_EMCON:onThreatLost(groupName)
    local state = self.samStates[groupName]
    if not state then return end

    if state.mode == SAM_EMCON.MODE.THREAT_REACTIVE then
        -- 遅延停波（すぐには停波しない）
        local emconSystem = self
        SAM_UTILS.scheduleFunction(function()
            emconSystem:setSamEmitting(groupName, false)
            SAM_UTILS.debug("[EMCON] Threat reactive: " .. groupName .. " deactivated")
        end, nil, SAM_UTILS.getTime() + 30)
    end
end

-- ============================================
-- 更新スケジュール
-- ============================================
function SAM_EMCON:scheduleUpdate()
    local emconSystem = self
    SAM_UTILS.scheduleFunction(function()
        emconSystem:update()
    end, nil, SAM_UTILS.getTime() + self.updateInterval)
end

-- ============================================
-- システム停止
-- ============================================
function SAM_EMCON:stop()
    self.isRunning = false
    SAM_UTILS.debug("[EMCON] System stopped")
end

-- ============================================
-- システム再開
-- ============================================
function SAM_EMCON:resume()
    if not self.isRunning then
        self.isRunning = true
        self:scheduleUpdate()
        SAM_UTILS.debug("[EMCON] System resumed")
    end
end

-- ============================================
-- ステータス取得
-- ============================================
function SAM_EMCON:getStatus()
    local status = {
        level = self.currentLevel,
        mode = self.mode,
        isRunning = self.isRunning,
        samCount = 0,
        emitting = 0,
        silent = 0,
        sams = {}
    }

    for groupName, state in pairs(self.samStates) do
        status.samCount = status.samCount + 1
        if state.isEmitting then
            status.emitting = status.emitting + 1
        else
            status.silent = status.silent + 1
        end

        table.insert(status.sams, {
            groupName = groupName,
            isEmitting = state.isEmitting,
            mode = state.mode,
            override = state.overrideLevel
        })
    end

    return status
end

-- ============================================
-- ステータス表示
-- ============================================
function SAM_EMCON:printStatus()
    local status = self:getStatus()

    local msg = string.format("[EMCON Status]\nLevel: %s | Mode: %s\n",
        status.level, status.mode)
    msg = msg .. string.format("SAMs: %d | Emitting: %d | Silent: %d\n",
        status.samCount, status.emitting, status.silent)

    for _, sam in ipairs(status.sams) do
        local emitStr = sam.isEmitting and "ON" or "OFF"
        local overrideStr = sam.override and (" [" .. sam.override .. "]") or ""
        msg = msg .. string.format("  %s: %s (%s)%s\n",
            sam.groupName, emitStr, sam.mode, overrideStr)
    end

    SAM_UTILS.info(msg, 20)
end

return SAM_EMCON
