--[[
    DCS IADS Multiplayer Synchronization System
    マルチプレイヤー同期システム

    マルチプレイヤー環境でIADS状態を同期するシステム

    機能:
    - クライアント間のIADS状態同期
    - ネットワークメッセージハンドリング
    - イベント複製
    - 状態永続化と復旧
    - ホスト/クライアント役割管理

    依存: core/utils.lua, iads/network.lua
    DCS API: net, timer
]]

IADS_MP_SYNC = {}
IADS_MP_SYNC.__index = IADS_MP_SYNC

-- ============================================
-- 同期モード
-- ============================================
IADS_MP_SYNC.MODE = {
    HOST = "HOST",             -- ホスト（権威サーバー）
    CLIENT = "CLIENT",         -- クライアント
    STANDALONE = "STANDALONE"  -- シングルプレイヤー
}

-- ============================================
-- メッセージタイプ
-- ============================================
IADS_MP_SYNC.MSG_TYPE = {
    STATE_FULL = "STATE_FULL",         -- 完全な状態同期
    STATE_DELTA = "STATE_DELTA",       -- 差分更新
    SAM_STATE = "SAM_STATE",           -- SAM状態変更
    THREAT_UPDATE = "THREAT_UPDATE",   -- 脅威情報更新
    COMMAND = "COMMAND",               -- コマンド
    REQUEST_SYNC = "REQUEST_SYNC",     -- 同期リクエスト
    HEARTBEAT = "HEARTBEAT"            -- 死活監視
}

-- ============================================
-- 同期システム作成
-- ============================================
function IADS_MP_SYNC.new(iadsNetwork)
    local self = setmetatable({}, IADS_MP_SYNC)

    self.network = iadsNetwork
    self.updateInterval = 1        -- 同期間隔（秒）
    self.fullSyncInterval = 30     -- 完全同期間隔（秒）
    self.isRunning = false

    -- 動作モード
    self.mode = IADS_MP_SYNC.MODE.STANDALONE
    self.isMultiplayer = false

    -- クライアント管理
    self.connectedClients = {}
    self.clientLastSeen = {}
    self.clientTimeout = 30        -- クライアントタイムアウト（秒）

    -- 状態追跡
    self.lastState = {}
    self.stateVersion = 0
    self.lastFullSync = 0
    self.pendingUpdates = {}

    -- メッセージキュー
    self.outgoingMessages = {}
    self.incomingMessages = {}

    -- イベントハンドラ
    self.eventHandlers = {}

    -- 統計
    self.stats = {
        messagesSent = 0,
        messagesReceived = 0,
        syncCount = 0,
        errors = 0
    }

    return self
end

-- ============================================
-- 初期化
-- ============================================
function IADS_MP_SYNC:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end
    if options.fullSyncInterval then
        self.fullSyncInterval = options.fullSyncInterval
    end

    -- マルチプレイヤー環境検出
    self:detectMultiplayerMode()

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[MPSync] System initialized in " .. self.mode .. " mode")
    return self
end

-- ============================================
-- マルチプレイヤーモード検出
-- ============================================
function IADS_MP_SYNC:detectMultiplayerMode()
    -- DCS APIを使用してマルチプレイヤー環境を検出
    if net and net.get_server_id then
        local serverId = net.get_server_id()
        if serverId then
            self.isMultiplayer = true

            -- ホストかクライアントかを判定
            local myId = net.get_my_player_id and net.get_my_player_id() or nil
            if myId == serverId or myId == 1 then
                self.mode = IADS_MP_SYNC.MODE.HOST
            else
                self.mode = IADS_MP_SYNC.MODE.CLIENT
            end
        else
            self.mode = IADS_MP_SYNC.MODE.STANDALONE
        end
    else
        self.mode = IADS_MP_SYNC.MODE.STANDALONE
    end

    SAM_UTILS.debug("[MPSync] Detected mode: " .. self.mode)
end

-- ============================================
-- 現在の状態をシリアライズ
-- ============================================
function IADS_MP_SYNC:serializeState()
    if not self.network then return nil end

    local state = {
        version = self.stateVersion,
        timestamp = SAM_UTILS.getTime(),
        samSites = {},
        threats = {},
        defcon = nil,
        tacticalMode = nil
    }

    -- SAMサイト状態
    for samName, samSite in pairs(self.network.samSites or {}) do
        state.samSites[samName] = {
            state = samSite.state,
            position = samSite.position,
            isActive = samSite.state == "GREEN" or samSite.state == "RED"
        }
    end

    -- 脅威情報
    for threatId, threat in pairs(self.network.threats or {}) do
        state.threats[threatId] = {
            position = threat.position,
            type = threat.type,
            level = threat.level,
            heading = threat.heading
        }
    end

    -- コマンダー状態
    if IADS_SYSTEMS and IADS_SYSTEMS.commander then
        state.defcon = IADS_SYSTEMS.commander.defenseCondition
        state.tacticalMode = IADS_SYSTEMS.commander.tacticalMode
    end

    return state
end

-- ============================================
-- 差分状態を計算
-- ============================================
function IADS_MP_SYNC:calculateDelta()
    local currentState = self:serializeState()
    if not currentState then return nil end

    local delta = {
        version = self.stateVersion + 1,
        timestamp = SAM_UTILS.getTime(),
        changes = {}
    }

    -- SAM状態の変更を検出
    for samName, samState in pairs(currentState.samSites) do
        local lastSamState = self.lastState.samSites and self.lastState.samSites[samName]
        if not lastSamState or lastSamState.state ~= samState.state then
            delta.changes[samName] = {
                type = "SAM_STATE",
                state = samState.state
            }
        end
    end

    -- 脅威情報の変更を検出
    for threatId, threat in pairs(currentState.threats) do
        local lastThreat = self.lastState.threats and self.lastState.threats[threatId]
        if not lastThreat then
            delta.changes[threatId] = {
                type = "THREAT_NEW",
                data = threat
            }
        elseif lastThreat.position ~= threat.position then
            delta.changes[threatId] = {
                type = "THREAT_UPDATE",
                data = threat
            }
        end
    end

    -- 削除された脅威を検出
    if self.lastState.threats then
        for threatId, _ in pairs(self.lastState.threats) do
            if not currentState.threats[threatId] then
                delta.changes[threatId] = {
                    type = "THREAT_REMOVE"
                }
            end
        end
    end

    -- DEFCON変更を検出
    if currentState.defcon ~= self.lastState.defcon then
        delta.changes["DEFCON"] = {
            type = "DEFCON",
            value = currentState.defcon
        }
    end

    self.lastState = currentState
    self.stateVersion = delta.version

    -- 変更がなければnilを返す
    local hasChanges = false
    for _ in pairs(delta.changes) do
        hasChanges = true
        break
    end

    return hasChanges and delta or nil
end

-- ============================================
-- 状態を適用（クライアント側）
-- ============================================
function IADS_MP_SYNC:applyState(state)
    if not self.network or not state then return false end

    -- 完全同期
    if state.samSites then
        for samName, samState in pairs(state.samSites) do
            local samSite = self.network.samSites[samName]
            if samSite then
                samSite.state = samState.state
                -- 実際のDCSユニット状態を更新
                self.network:setSamState(samName, samState.state)
            end
        end
    end

    -- DEFCON適用
    if state.defcon and IADS_SYSTEMS and IADS_SYSTEMS.commander then
        IADS_SYSTEMS.commander.defenseCondition = state.defcon
    end

    -- 戦術モード適用
    if state.tacticalMode and IADS_SYSTEMS and IADS_SYSTEMS.commander then
        IADS_SYSTEMS.commander.tacticalMode = state.tacticalMode
    end

    SAM_UTILS.debug("[MPSync] State applied (version: " .. (state.version or "N/A") .. ")")
    return true
end

-- ============================================
-- 差分を適用（クライアント側）
-- ============================================
function IADS_MP_SYNC:applyDelta(delta)
    if not delta or not delta.changes then return false end

    for id, change in pairs(delta.changes) do
        if change.type == "SAM_STATE" then
            if self.network then
                self.network:setSamState(id, change.state)
            end
        elseif change.type == "THREAT_NEW" or change.type == "THREAT_UPDATE" then
            if self.network and self.network.threats then
                self.network.threats[id] = change.data
            end
        elseif change.type == "THREAT_REMOVE" then
            if self.network and self.network.threats then
                self.network.threats[id] = nil
            end
        elseif change.type == "DEFCON" then
            if IADS_SYSTEMS and IADS_SYSTEMS.commander then
                IADS_SYSTEMS.commander.defenseCondition = change.value
            end
        end
    end

    self.stateVersion = delta.version
    SAM_UTILS.debug("[MPSync] Delta applied (version: " .. delta.version .. ")")
    return true
end

-- ============================================
-- メッセージを送信
-- ============================================
function IADS_MP_SYNC:sendMessage(msgType, data, targetClient)
    local message = {
        type = msgType,
        sender = self.mode,
        timestamp = SAM_UTILS.getTime(),
        data = data
    }

    -- メッセージをシリアライズ
    local serialized = self:serializeMessage(message)
    if not serialized then return false end

    -- DCSネットワーク送信（利用可能な場合）
    if net and net.send_chat then
        -- 注: DCSの実際のネットワークAPIに合わせて調整が必要
        -- これは概念的な実装
        if targetClient then
            -- 特定クライアントに送信
            table.insert(self.outgoingMessages, {
                target = targetClient,
                message = serialized
            })
        else
            -- ブロードキャスト
            table.insert(self.outgoingMessages, {
                target = "all",
                message = serialized
            })
        end

        self.stats.messagesSent = self.stats.messagesSent + 1
        return true
    end

    return false
end

-- ============================================
-- メッセージをシリアライズ
-- ============================================
function IADS_MP_SYNC:serializeMessage(message)
    -- JSONライクな形式でシリアライズ
    -- 注: 実際の実装ではluasocketやその他のシリアライズを使用
    local parts = {
        "IADS_MSG",
        message.type,
        tostring(message.timestamp)
    }

    if message.data then
        -- データを簡易エンコード
        local dataStr = self:encodeData(message.data)
        if dataStr then
            table.insert(parts, dataStr)
        end
    end

    return table.concat(parts, "|")
end

-- ============================================
-- メッセージをデシリアライズ
-- ============================================
function IADS_MP_SYNC:deserializeMessage(serialized)
    if not serialized or type(serialized) ~= "string" then
        return nil
    end

    -- "IADS_MSG|TYPE|TIMESTAMP|DATA" 形式をパース
    local parts = {}
    for part in string.gmatch(serialized, "[^|]+") do
        table.insert(parts, part)
    end

    if parts[1] ~= "IADS_MSG" or #parts < 3 then
        return nil
    end

    local message = {
        type = parts[2],
        timestamp = tonumber(parts[3]),
        data = nil
    }

    if parts[4] then
        message.data = self:decodeData(parts[4])
    end

    return message
end

-- ============================================
-- データをエンコード
-- ============================================
function IADS_MP_SYNC:encodeData(data)
    if type(data) == "table" then
        local parts = {}
        for k, v in pairs(data) do
            local encodedValue
            if type(v) == "table" then
                encodedValue = self:encodeData(v)
            else
                encodedValue = tostring(v)
            end
            table.insert(parts, k .. "=" .. encodedValue)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    else
        return tostring(data)
    end
end

-- ============================================
-- データをデコード
-- ============================================
function IADS_MP_SYNC:decodeData(encoded)
    -- 簡易デコード（実際の実装ではより堅牢なパーサーが必要）
    if string.sub(encoded, 1, 1) == "{" then
        local data = {}
        local content = string.sub(encoded, 2, -2)
        for pair in string.gmatch(content, "[^,]+") do
            local key, value = string.match(pair, "([^=]+)=(.+)")
            if key and value then
                data[key] = value
            end
        end
        return data
    end
    return encoded
end

-- ============================================
-- 受信メッセージを処理
-- ============================================
function IADS_MP_SYNC:processIncomingMessage(message)
    if not message then return end

    self.stats.messagesReceived = self.stats.messagesReceived + 1

    local msgType = message.type

    if msgType == IADS_MP_SYNC.MSG_TYPE.STATE_FULL then
        -- 完全状態同期
        self:applyState(message.data)

    elseif msgType == IADS_MP_SYNC.MSG_TYPE.STATE_DELTA then
        -- 差分更新
        self:applyDelta(message.data)

    elseif msgType == IADS_MP_SYNC.MSG_TYPE.SAM_STATE then
        -- 個別SAM状態更新
        if message.data and message.data.samName and message.data.state then
            if self.network then
                self.network:setSamState(message.data.samName, message.data.state)
            end
        end

    elseif msgType == IADS_MP_SYNC.MSG_TYPE.COMMAND then
        -- コマンド実行
        self:executeRemoteCommand(message.data)

    elseif msgType == IADS_MP_SYNC.MSG_TYPE.REQUEST_SYNC then
        -- 同期リクエスト（ホストのみ処理）
        if self.mode == IADS_MP_SYNC.MODE.HOST then
            self:sendFullState(message.sender)
        end

    elseif msgType == IADS_MP_SYNC.MSG_TYPE.HEARTBEAT then
        -- クライアント死活確認
        if message.clientId then
            self.clientLastSeen[message.clientId] = SAM_UTILS.getTime()
        end
    end

    -- イベントハンドラを呼び出し
    if self.eventHandlers[msgType] then
        self.eventHandlers[msgType](message)
    end
end

-- ============================================
-- 完全状態を送信（ホスト）
-- ============================================
function IADS_MP_SYNC:sendFullState(targetClient)
    if self.mode ~= IADS_MP_SYNC.MODE.HOST then return false end

    local state = self:serializeState()
    if state then
        self:sendMessage(IADS_MP_SYNC.MSG_TYPE.STATE_FULL, state, targetClient)
        self.lastFullSync = SAM_UTILS.getTime()
        self.stats.syncCount = self.stats.syncCount + 1
        return true
    end
    return false
end

-- ============================================
-- 差分を送信（ホスト）
-- ============================================
function IADS_MP_SYNC:sendDelta()
    if self.mode ~= IADS_MP_SYNC.MODE.HOST then return false end

    local delta = self:calculateDelta()
    if delta then
        self:sendMessage(IADS_MP_SYNC.MSG_TYPE.STATE_DELTA, delta)
        return true
    end
    return false
end

-- ============================================
-- リモートコマンドを実行
-- ============================================
function IADS_MP_SYNC:executeRemoteCommand(commandData)
    if not commandData or not commandData.command then return false end

    local cmd = commandData.command

    if cmd == "ACTIVATE_SAM" and commandData.samName then
        if self.network then
            self.network:setSamState(commandData.samName, "GREEN")
        end
    elseif cmd == "DEACTIVATE_SAM" and commandData.samName then
        if self.network then
            self.network:setSamState(commandData.samName, "DARK")
        end
    elseif cmd == "SET_DEFCON" and commandData.level then
        if IADS_SYSTEMS and IADS_SYSTEMS.commander then
            IADS_SYSTEMS.commander:setDefenseCondition(commandData.level)
        end
    elseif cmd == "SET_TACTICAL" and commandData.mode then
        if IADS_SYSTEMS and IADS_SYSTEMS.commander then
            IADS_SYSTEMS.commander:setTacticalMode(commandData.mode)
        end
    end

    SAM_UTILS.debug("[MPSync] Executed remote command: " .. cmd)
    return true
end

-- ============================================
-- コマンドを送信（クライアント→ホスト）
-- ============================================
function IADS_MP_SYNC:sendCommand(command, params)
    local commandData = {
        command = command
    }
    for k, v in pairs(params or {}) do
        commandData[k] = v
    end

    return self:sendMessage(IADS_MP_SYNC.MSG_TYPE.COMMAND, commandData)
end

-- ============================================
-- イベントハンドラを登録
-- ============================================
function IADS_MP_SYNC:registerEventHandler(msgType, handler)
    self.eventHandlers[msgType] = handler
end

-- ============================================
-- クライアント接続を管理
-- ============================================
function IADS_MP_SYNC:manageClients()
    if self.mode ~= IADS_MP_SYNC.MODE.HOST then return end

    local currentTime = SAM_UTILS.getTime()
    local disconnected = {}

    for clientId, lastSeen in pairs(self.clientLastSeen) do
        if currentTime - lastSeen > self.clientTimeout then
            table.insert(disconnected, clientId)
        end
    end

    for _, clientId in ipairs(disconnected) do
        self.clientLastSeen[clientId] = nil
        self.connectedClients[clientId] = nil
        SAM_UTILS.debug("[MPSync] Client disconnected: " .. clientId)
    end
end

-- ============================================
-- 同期リクエストを送信（クライアント）
-- ============================================
function IADS_MP_SYNC:requestSync()
    if self.mode ~= IADS_MP_SYNC.MODE.CLIENT then return false end

    return self:sendMessage(IADS_MP_SYNC.MSG_TYPE.REQUEST_SYNC, {
        clientVersion = self.stateVersion
    })
end

-- ============================================
-- 定期更新
-- ============================================
function IADS_MP_SYNC:update()
    if not self.isRunning then return end

    local currentTime = SAM_UTILS.getTime()

    if self.mode == IADS_MP_SYNC.MODE.HOST then
        -- ホスト: 差分を送信
        self:sendDelta()

        -- 定期的に完全同期
        if currentTime - self.lastFullSync > self.fullSyncInterval then
            self:sendFullState()
        end

        -- クライアント管理
        self:manageClients()

    elseif self.mode == IADS_MP_SYNC.MODE.CLIENT then
        -- クライアント: ハートビート送信
        self:sendMessage(IADS_MP_SYNC.MSG_TYPE.HEARTBEAT, {
            clientId = net and net.get_my_player_id and net.get_my_player_id() or "unknown"
        })
    end

    -- 受信メッセージを処理
    for _, msg in ipairs(self.incomingMessages) do
        local message = self:deserializeMessage(msg)
        if message then
            self:processIncomingMessage(message)
        end
    end
    self.incomingMessages = {}

    -- 次の更新をスケジュール
    self:scheduleUpdate()
end

-- ============================================
-- 更新スケジュール
-- ============================================
function IADS_MP_SYNC:scheduleUpdate()
    local syncSystem = self
    SAM_UTILS.scheduleFunction(function()
        syncSystem:update()
    end, nil, SAM_UTILS.getTime() + self.updateInterval)
end

-- ============================================
-- 停止
-- ============================================
function IADS_MP_SYNC:stop()
    self.isRunning = false
end

-- ============================================
-- ステータス取得
-- ============================================
function IADS_MP_SYNC:getStatus()
    return {
        mode = self.mode,
        isMultiplayer = self.isMultiplayer,
        isRunning = self.isRunning,
        stateVersion = self.stateVersion,
        connectedClients = #self.connectedClients,
        stats = SAM_UTILS.deepCopy(self.stats)
    }
end

-- ============================================
-- ステータス表示
-- ============================================
function IADS_MP_SYNC:printStatus()
    local status = self:getStatus()

    local msg = "[MP Sync Status]\n"
    msg = msg .. string.format("Mode: %s | Multiplayer: %s | Running: %s\n",
        status.mode,
        status.isMultiplayer and "Yes" or "No",
        status.isRunning and "Yes" or "No")
    msg = msg .. string.format("State Version: %d | Connected Clients: %d\n",
        status.stateVersion, status.connectedClients)
    msg = msg .. string.format("Messages - Sent: %d | Received: %d | Syncs: %d | Errors: %d\n",
        status.stats.messagesSent,
        status.stats.messagesReceived,
        status.stats.syncCount,
        status.stats.errors)

    SAM_UTILS.info(msg, 15)
end

return IADS_MP_SYNC
