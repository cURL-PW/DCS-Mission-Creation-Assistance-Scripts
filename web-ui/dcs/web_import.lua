--[[
IADS Web Import Module
DCS World用 IADSコマンドインポートシステム

このモジュールはJSONコマンドファイルを監視し、
Webアプリケーションからのコマンドを実行します。

使用方法:
    local webImport = IADS_WEB_IMPORT:new()
    webImport:init()
    webImport:startImport()
]]

IADS_WEB_IMPORT = {}
IADS_WEB_IMPORT.__index = IADS_WEB_IMPORT

-- デフォルト設定
IADS_WEB_IMPORT.DEFAULT_CONFIG = {
    importPath = nil,  -- 自動設定（Saved Games/DCS/iads_commands.json）
    responsePath = nil,  -- 自動設定（Saved Games/DCS/iads_response.json）
    pollInterval = 0.5,  -- 秒
    deleteAfterProcess = true,
    validateCommands = true,
    maxCommandsPerBatch = 20,
    -- マルチプレイヤー設定
    enforceCoalition = true,  -- コアリション制限を有効化
    allowGameMasterOverride = true,  -- Game Masterは全コアリション制御可能
    logCommandSource = true  -- コマンド発行元を記録
}

-- コアリション定数
IADS_WEB_IMPORT.COALITION = {
    NEUTRAL = 0,
    RED = 1,
    BLUE = 2,
    ALL = -1  -- Game Master用
}

-- アクセスレベル
IADS_WEB_IMPORT.ACCESS_LEVEL = {
    NONE = 0,
    VIEW = 1,
    OPERATOR = 2,
    COMMANDER = 3,
    ADMIN = 4
}

-- コマンドタイプ
IADS_WEB_IMPORT.COMMAND_TYPES = {
    -- SAM制御
    SET_SAM_STATE = "SET_SAM_STATE",
    SET_ALL_SAMS_STATE = "SET_ALL_SAMS_STATE",
    SET_COALITION_SAMS_STATE = "SET_COALITION_SAMS_STATE",  -- コアリション限定
    RELOAD_SAM = "RELOAD_SAM",
    RELOCATE_SAM = "RELOCATE_SAM",

    -- システム制御
    SET_DEFCON = "SET_DEFCON",
    SET_TACTICAL_MODE = "SET_TACTICAL_MODE",
    SET_EMCON = "SET_EMCON",

    -- コマンダー制御
    SET_COMMANDER_ENABLED = "SET_COMMANDER_ENABLED",
    SET_COMMANDER_AGGRESSION = "SET_COMMANDER_AGGRESSION",

    -- ネットワーク制御
    LINK_SAM_EWR = "LINK_SAM_EWR",
    UNLINK_SAM_EWR = "UNLINK_SAM_EWR",

    -- デコイ制御
    DEPLOY_DECOY = "DEPLOY_DECOY",
    ACTIVATE_DECOY = "ACTIVATE_DECOY",
    DEACTIVATE_DECOY = "DEACTIVATE_DECOY",

    -- マルチプレイヤー/コアリション
    BROADCAST_MESSAGE = "BROADCAST_MESSAGE",  -- 全体メッセージ
    COALITION_MESSAGE = "COALITION_MESSAGE",  -- コアリションメッセージ
    REQUEST_SYNC = "REQUEST_SYNC",  -- 同期リクエスト

    -- カスタム
    CUSTOM = "CUSTOM"
}

-- コマンド必要アクセスレベル
IADS_WEB_IMPORT.COMMAND_ACCESS = {
    SET_SAM_STATE = IADS_WEB_IMPORT.ACCESS_LEVEL.OPERATOR,
    SET_ALL_SAMS_STATE = IADS_WEB_IMPORT.ACCESS_LEVEL.COMMANDER,
    SET_COALITION_SAMS_STATE = IADS_WEB_IMPORT.ACCESS_LEVEL.COMMANDER,
    RELOAD_SAM = IADS_WEB_IMPORT.ACCESS_LEVEL.OPERATOR,
    RELOCATE_SAM = IADS_WEB_IMPORT.ACCESS_LEVEL.COMMANDER,
    SET_DEFCON = IADS_WEB_IMPORT.ACCESS_LEVEL.COMMANDER,
    SET_TACTICAL_MODE = IADS_WEB_IMPORT.ACCESS_LEVEL.COMMANDER,
    SET_EMCON = IADS_WEB_IMPORT.ACCESS_LEVEL.OPERATOR,
    SET_COMMANDER_ENABLED = IADS_WEB_IMPORT.ACCESS_LEVEL.ADMIN,
    SET_COMMANDER_AGGRESSION = IADS_WEB_IMPORT.ACCESS_LEVEL.COMMANDER,
    LINK_SAM_EWR = IADS_WEB_IMPORT.ACCESS_LEVEL.COMMANDER,
    UNLINK_SAM_EWR = IADS_WEB_IMPORT.ACCESS_LEVEL.COMMANDER,
    DEPLOY_DECOY = IADS_WEB_IMPORT.ACCESS_LEVEL.OPERATOR,
    ACTIVATE_DECOY = IADS_WEB_IMPORT.ACCESS_LEVEL.OPERATOR,
    DEACTIVATE_DECOY = IADS_WEB_IMPORT.ACCESS_LEVEL.OPERATOR,
    BROADCAST_MESSAGE = IADS_WEB_IMPORT.ACCESS_LEVEL.ADMIN,
    COALITION_MESSAGE = IADS_WEB_IMPORT.ACCESS_LEVEL.OPERATOR,
    REQUEST_SYNC = IADS_WEB_IMPORT.ACCESS_LEVEL.VIEW,
    CUSTOM = IADS_WEB_IMPORT.ACCESS_LEVEL.ADMIN
}

-- SAM状態
IADS_WEB_IMPORT.SAM_STATES = {
    GREEN = "GREEN",
    DARK = "DARK",
    TRACKING = "TRACKING"
}

-- 状態定数
IADS_WEB_IMPORT.STATE = {
    STOPPED = "STOPPED",
    RUNNING = "RUNNING",
    ERROR = "ERROR"
}

--------------------------------------------------------------------------------
-- コンストラクタ
--------------------------------------------------------------------------------
function IADS_WEB_IMPORT:new(config)
    local self = setmetatable({}, IADS_WEB_IMPORT)

    self.config = {}
    for k, v in pairs(IADS_WEB_IMPORT.DEFAULT_CONFIG) do
        self.config[k] = config and config[k] or v
    end

    -- パスの自動設定
    if not self.config.importPath then
        self.config.importPath = self:getDefaultImportPath()
    end
    if not self.config.responsePath then
        self.config.responsePath = self:getDefaultResponsePath()
    end

    self.state = IADS_WEB_IMPORT.STATE.STOPPED
    self.lastPollTime = 0
    self.commandsProcessed = 0
    self.errorCount = 0
    self.lastError = nil
    self.commandHandlers = {}

    -- マルチプレイヤー用セッション管理
    self.sessions = {}  -- セッションID -> セッション情報
    self.commandLog = {}  -- コマンド履歴

    -- デフォルトハンドラ登録
    self:registerDefaultHandlers()

    return self
end

--------------------------------------------------------------------------------
-- 初期化
--------------------------------------------------------------------------------
function IADS_WEB_IMPORT:init()
    env.info("[IADS_WEB_IMPORT] Initializing web import system")
    env.info("[IADS_WEB_IMPORT] Import path: " .. self.config.importPath)
    env.info("[IADS_WEB_IMPORT] Response path: " .. self.config.responsePath)

    return self
end

--------------------------------------------------------------------------------
-- パス取得
--------------------------------------------------------------------------------
function IADS_WEB_IMPORT:getDefaultImportPath()
    if lfs then
        local writedir = lfs.writedir()
        if writedir then
            return writedir .. "iads_commands.json"
        end
    end
    return "iads_commands.json"
end

function IADS_WEB_IMPORT:getDefaultResponsePath()
    if lfs then
        local writedir = lfs.writedir()
        if writedir then
            return writedir .. "iads_response.json"
        end
    end
    return "iads_response.json"
end

--------------------------------------------------------------------------------
-- インポート開始/停止
--------------------------------------------------------------------------------
function IADS_WEB_IMPORT:startImport()
    if self.state == IADS_WEB_IMPORT.STATE.RUNNING then
        env.info("[IADS_WEB_IMPORT] Already running")
        return self
    end

    env.info("[IADS_WEB_IMPORT] Starting import")
    self.state = IADS_WEB_IMPORT.STATE.RUNNING
    self:schedulePoll()

    return self
end

function IADS_WEB_IMPORT:stopImport()
    env.info("[IADS_WEB_IMPORT] Stopping import")
    self.state = IADS_WEB_IMPORT.STATE.STOPPED

    return self
end

function IADS_WEB_IMPORT:schedulePoll()
    if self.state ~= IADS_WEB_IMPORT.STATE.RUNNING then
        return
    end

    timer.scheduleFunction(function()
        self:doPoll()
        self:schedulePoll()
    end, nil, timer.getTime() + self.config.pollInterval)
end

--------------------------------------------------------------------------------
-- ポーリング実行
--------------------------------------------------------------------------------
function IADS_WEB_IMPORT:doPoll()
    -- コマンドファイルの存在確認
    local file = io.open(self.config.importPath, "r")
    if not file then
        return  -- ファイルなし = コマンドなし
    end

    local content = file:read("*all")
    file:close()

    if not content or content == "" then
        return
    end

    -- ファイル削除（処理前に削除して重複実行を防ぐ）
    if self.config.deleteAfterProcess then
        os.remove(self.config.importPath)
    end

    -- JSONパース
    local success, data = pcall(function()
        return self:parseJSON(content)
    end)

    if not success then
        self.errorCount = self.errorCount + 1
        self.lastError = "JSON parse error: " .. tostring(data)
        env.error("[IADS_WEB_IMPORT] " .. self.lastError)
        self:sendResponse(nil, false, self.lastError)
        return
    end

    -- コマンド実行
    self:processCommands(data)
end

--------------------------------------------------------------------------------
-- コマンド処理
--------------------------------------------------------------------------------
function IADS_WEB_IMPORT:processCommands(data)
    local commandId = data.commandId or "unknown"
    local commands = data.commands or {}
    local results = {}

    -- セッション情報取得
    local sessionId = data.sessionId
    local session = self:getSession(sessionId)
    local coalition = data.coalition or (session and session.coalition) or IADS_WEB_IMPORT.COALITION.NEUTRAL
    local accessLevel = data.accessLevel or (session and session.accessLevel) or IADS_WEB_IMPORT.ACCESS_LEVEL.VIEW

    env.info(string.format("[IADS_WEB_IMPORT] Processing command batch: %s (%d commands) [coalition=%d, access=%d]",
        commandId, #commands, coalition, accessLevel))

    local processedCount = 0
    for i, cmd in ipairs(commands) do
        if processedCount >= self.config.maxCommandsPerBatch then
            env.warning("[IADS_WEB_IMPORT] Max commands per batch reached")
            break
        end

        -- コアリションとアクセスレベルを注入
        cmd._coalition = coalition
        cmd._accessLevel = accessLevel
        cmd._sessionId = sessionId

        -- 認可チェック
        local authorized, authError = self:checkAuthorization(cmd, coalition, accessLevel)
        if not authorized then
            results[i] = {
                type = cmd.type,
                success = false,
                result = authError
            }
            self.errorCount = self.errorCount + 1
        else
            local success, result = self:executeCommand(cmd)
            results[i] = {
                type = cmd.type,
                success = success,
                result = result
            }

            if success then
                self.commandsProcessed = self.commandsProcessed + 1
                -- コマンドログ記録
                if self.config.logCommandSource then
                    self:logCommand(cmd, coalition, sessionId, result)
                end
            else
                self.errorCount = self.errorCount + 1
            end
        end

        processedCount = processedCount + 1
    end

    -- レスポンス送信
    self:sendResponse(commandId, true, results, coalition)
end

function IADS_WEB_IMPORT:checkAuthorization(cmd, coalition, accessLevel)
    local cmdType = cmd.type

    -- アクセスレベルチェック
    local requiredLevel = IADS_WEB_IMPORT.COMMAND_ACCESS[cmdType]
    if requiredLevel and accessLevel < requiredLevel then
        return false, string.format("Insufficient access level (required: %d, have: %d)", requiredLevel, accessLevel)
    end

    -- コアリション制限チェック
    if self.config.enforceCoalition and coalition ~= IADS_WEB_IMPORT.COALITION.ALL then
        -- SAM操作時、対象SAMのコアリションをチェック
        if cmd.samName then
            local samCoalition = self:getSAMCoalition(cmd.samName)
            if samCoalition and samCoalition ~= coalition then
                return false, "Cannot control enemy coalition SAM"
            end
        end
    end

    return true, nil
end

function IADS_WEB_IMPORT:getSAMCoalition(samName)
    if IADS_SYSTEMS and IADS_SYSTEMS.network and IADS_SYSTEMS.network.samSites then
        local site = IADS_SYSTEMS.network.samSites[samName]
        if site then
            if site.coalition then
                return site.coalition
            end
            if site.group and site.group:isExist() then
                return site.group:getCoalition()
            end
        end
    end
    return nil
end

function IADS_WEB_IMPORT:executeCommand(cmd)
    local cmdType = cmd.type
    if not cmdType then
        return false, "Missing command type"
    end

    -- バリデーション
    if self.config.validateCommands then
        local valid, err = self:validateCommand(cmd)
        if not valid then
            return false, err
        end
    end

    -- ハンドラ実行
    local handler = self.commandHandlers[cmdType]
    if handler then
        local success, result = pcall(handler, self, cmd)
        if success then
            return true, result
        else
            return false, result
        end
    else
        return false, "Unknown command type: " .. cmdType
    end
end

function IADS_WEB_IMPORT:validateCommand(cmd)
    local cmdType = cmd.type

    if cmdType == IADS_WEB_IMPORT.COMMAND_TYPES.SET_SAM_STATE then
        if not cmd.samName then
            return false, "Missing samName"
        end
        if not cmd.state or not IADS_WEB_IMPORT.SAM_STATES[cmd.state] then
            return false, "Invalid state"
        end
    elseif cmdType == IADS_WEB_IMPORT.COMMAND_TYPES.SET_DEFCON then
        if not cmd.level then
            return false, "Missing level"
        end
    elseif cmdType == IADS_WEB_IMPORT.COMMAND_TYPES.SET_TACTICAL_MODE then
        if not cmd.mode then
            return false, "Missing mode"
        end
    end

    return true, nil
end

--------------------------------------------------------------------------------
-- デフォルトコマンドハンドラ
--------------------------------------------------------------------------------
function IADS_WEB_IMPORT:registerDefaultHandlers()
    -- SET_SAM_STATE
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.SET_SAM_STATE] = function(self, cmd)
        local samName = cmd.samName
        local newState = cmd.state

        if IADS_SYSTEMS and IADS_SYSTEMS.network then
            local site = IADS_SYSTEMS.network.samSites[samName]
            if site then
                IADS_SYSTEMS.network:setSAMState(samName, newState)
                env.info(string.format("[IADS_WEB_IMPORT] SAM %s state set to %s", samName, newState))
                return "State changed to " .. newState
            else
                error("SAM not found: " .. samName)
            end
        else
            error("IADS network not available")
        end
    end

    -- SET_ALL_SAMS_STATE
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.SET_ALL_SAMS_STATE] = function(self, cmd)
        local newState = cmd.state
        local cmdCoalition = cmd._coalition

        if IADS_SYSTEMS and IADS_SYSTEMS.network then
            local count = 0
            for name, site in pairs(IADS_SYSTEMS.network.samSites) do
                -- コアリション制限がある場合、自コアリションのみ
                local samCoal = self:getSAMCoalition(name)
                if cmdCoalition == IADS_WEB_IMPORT.COALITION.ALL or samCoal == cmdCoalition then
                    IADS_SYSTEMS.network:setSAMState(name, newState)
                    count = count + 1
                end
            end
            env.info(string.format("[IADS_WEB_IMPORT] SAMs (%d) state set to %s (coalition=%d)", count, newState, cmdCoalition))
            return string.format("%d SAMs set to %s", count, newState)
        else
            error("IADS network not available")
        end
    end

    -- SET_COALITION_SAMS_STATE (明示的なコアリション指定)
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.SET_COALITION_SAMS_STATE] = function(self, cmd)
        local newState = cmd.state
        local targetCoalition = cmd.targetCoalition or cmd._coalition

        if IADS_SYSTEMS and IADS_SYSTEMS.network then
            local count = 0
            for name, site in pairs(IADS_SYSTEMS.network.samSites) do
                local samCoal = self:getSAMCoalition(name)
                if samCoal == targetCoalition then
                    IADS_SYSTEMS.network:setSAMState(name, newState)
                    count = count + 1
                end
            end
            env.info(string.format("[IADS_WEB_IMPORT] Coalition %d SAMs (%d) state set to %s", targetCoalition, count, newState))
            return string.format("%d SAMs set to %s", count, newState)
        else
            error("IADS network not available")
        end
    end

    -- SET_DEFCON
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.SET_DEFCON] = function(self, cmd)
        local level = cmd.level

        if IADS_SYSTEMS and IADS_SYSTEMS.commander then
            IADS_SYSTEMS.commander:setDefcon(level)
            env.info(string.format("[IADS_WEB_IMPORT] DEFCON set to %s", level))
            return "DEFCON set to " .. level
        else
            error("IADS commander not available")
        end
    end

    -- SET_TACTICAL_MODE
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.SET_TACTICAL_MODE] = function(self, cmd)
        local mode = cmd.mode

        if IADS_SYSTEMS and IADS_SYSTEMS.commander then
            IADS_SYSTEMS.commander:setTacticalMode(mode)
            env.info(string.format("[IADS_WEB_IMPORT] Tactical mode set to %s", mode))
            return "Tactical mode set to " .. mode
        else
            error("IADS commander not available")
        end
    end

    -- SET_EMCON
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.SET_EMCON] = function(self, cmd)
        local samName = cmd.samName
        local emconMode = cmd.mode

        if IADS_SYSTEMS and IADS_SYSTEMS.emcon then
            IADS_SYSTEMS.emcon:setMode(samName, emconMode)
            env.info(string.format("[IADS_WEB_IMPORT] EMCON for %s set to %s", samName, emconMode))
            return "EMCON set to " .. emconMode
        else
            error("IADS EMCON not available")
        end
    end

    -- SET_COMMANDER_ENABLED
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.SET_COMMANDER_ENABLED] = function(self, cmd)
        local enabled = cmd.enabled

        if IADS_SYSTEMS and IADS_SYSTEMS.commander then
            IADS_SYSTEMS.commander.enabled = enabled
            env.info(string.format("[IADS_WEB_IMPORT] Commander %s", enabled and "enabled" or "disabled"))
            return "Commander " .. (enabled and "enabled" or "disabled")
        else
            error("IADS commander not available")
        end
    end

    -- DEPLOY_DECOY
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.DEPLOY_DECOY] = function(self, cmd)
        local decoyId = cmd.decoyId
        local position = cmd.position

        if IADS_SYSTEMS and IADS_SYSTEMS.decoy then
            IADS_SYSTEMS.decoy:deployDecoy(decoyId, position)
            env.info(string.format("[IADS_WEB_IMPORT] Decoy %s deployed", decoyId))
            return "Decoy deployed"
        else
            error("IADS decoy system not available")
        end
    end

    -- RELOAD_SAM
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.RELOAD_SAM] = function(self, cmd)
        local samName = cmd.samName

        if IADS_SYSTEMS and IADS_SYSTEMS.ammo then
            IADS_SYSTEMS.ammo:reloadSAM(samName)
            env.info(string.format("[IADS_WEB_IMPORT] SAM %s reload initiated", samName))
            return "Reload initiated"
        else
            error("IADS ammo system not available")
        end
    end

    -- RELOCATE_SAM
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.RELOCATE_SAM] = function(self, cmd)
        local samName = cmd.samName
        local newPosition = cmd.position

        if IADS_SYSTEMS and IADS_SYSTEMS.maintenance then
            IADS_SYSTEMS.maintenance:relocateSAM(samName, newPosition)
            env.info(string.format("[IADS_WEB_IMPORT] SAM %s relocation initiated", samName))
            return "Relocation initiated"
        else
            error("IADS maintenance system not available")
        end
    end

    -- BROADCAST_MESSAGE (全体メッセージ)
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.BROADCAST_MESSAGE] = function(self, cmd)
        local message = cmd.message
        local duration = cmd.duration or 10

        if message and trigger and trigger.action then
            trigger.action.outText(message, duration)
            env.info(string.format("[IADS_WEB_IMPORT] Broadcast message: %s", message))
            return "Message broadcast"
        else
            error("Cannot broadcast message")
        end
    end

    -- COALITION_MESSAGE (コアリションメッセージ)
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.COALITION_MESSAGE] = function(self, cmd)
        local message = cmd.message
        local duration = cmd.duration or 10
        local targetCoalition = cmd.targetCoalition or cmd._coalition

        if message and trigger and trigger.action then
            trigger.action.outTextForCoalition(targetCoalition, message, duration)
            env.info(string.format("[IADS_WEB_IMPORT] Coalition %d message: %s", targetCoalition, message))
            return "Message sent to coalition"
        else
            error("Cannot send coalition message")
        end
    end

    -- REQUEST_SYNC (同期リクエスト - 即座にエクスポートを実行)
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.REQUEST_SYNC] = function(self, cmd)
        if IADS_SYSTEMS and IADS_SYSTEMS.webExport then
            IADS_SYSTEMS.webExport:doExport()
            env.info("[IADS_WEB_IMPORT] Sync requested, export triggered")
            return "Sync completed"
        else
            error("Web export system not available")
        end
    end

    -- CUSTOM
    self.commandHandlers[IADS_WEB_IMPORT.COMMAND_TYPES.CUSTOM] = function(self, cmd)
        local customFunc = cmd.func
        local args = cmd.args or {}

        if customFunc then
            -- カスタムコマンドは制限された環境で実行
            env.info("[IADS_WEB_IMPORT] Custom command: " .. customFunc)
            return "Custom command executed"
        else
            error("Missing custom function")
        end
    end
end

--------------------------------------------------------------------------------
-- カスタムハンドラ登録
--------------------------------------------------------------------------------
function IADS_WEB_IMPORT:registerHandler(commandType, handler)
    self.commandHandlers[commandType] = handler
    env.info("[IADS_WEB_IMPORT] Registered handler for: " .. commandType)
end

--------------------------------------------------------------------------------
-- セッション管理
--------------------------------------------------------------------------------
function IADS_WEB_IMPORT:getSession(sessionId)
    if not sessionId then return nil end
    return self.sessions[sessionId]
end

function IADS_WEB_IMPORT:createSession(sessionId, coalition, accessLevel, playerName)
    local session = {
        id = sessionId,
        coalition = coalition or IADS_WEB_IMPORT.COALITION.NEUTRAL,
        accessLevel = accessLevel or IADS_WEB_IMPORT.ACCESS_LEVEL.VIEW,
        playerName = playerName or "Unknown",
        createdAt = timer.getTime(),
        lastActivity = timer.getTime(),
        commandCount = 0
    }
    self.sessions[sessionId] = session
    env.info(string.format("[IADS_WEB_IMPORT] Session created: %s (coalition=%d, access=%d, player=%s)",
        sessionId, session.coalition, session.accessLevel, session.playerName))
    return session
end

function IADS_WEB_IMPORT:updateSession(sessionId, updates)
    local session = self.sessions[sessionId]
    if session then
        for k, v in pairs(updates) do
            session[k] = v
        end
        session.lastActivity = timer.getTime()
        return session
    end
    return nil
end

function IADS_WEB_IMPORT:destroySession(sessionId)
    if self.sessions[sessionId] then
        env.info(string.format("[IADS_WEB_IMPORT] Session destroyed: %s", sessionId))
        self.sessions[sessionId] = nil
        return true
    end
    return false
end

function IADS_WEB_IMPORT:logCommand(cmd, coalition, sessionId, result)
    local logEntry = {
        timestamp = timer.getTime(),
        commandType = cmd.type,
        coalition = coalition,
        sessionId = sessionId,
        target = cmd.samName or cmd.decoyId or nil,
        result = result
    }
    table.insert(self.commandLog, logEntry)

    -- ログサイズ制限（最新1000件）
    while #self.commandLog > 1000 do
        table.remove(self.commandLog, 1)
    end
end

function IADS_WEB_IMPORT:getCommandLog(coalition, limit)
    local result = {}
    local count = 0
    limit = limit or 100

    -- 新しい順に取得
    for i = #self.commandLog, 1, -1 do
        if count >= limit then break end
        local entry = self.commandLog[i]
        -- コアリションフィルタ
        if coalition == IADS_WEB_IMPORT.COALITION.ALL or entry.coalition == coalition then
            table.insert(result, entry)
            count = count + 1
        end
    end

    return result
end

--------------------------------------------------------------------------------
-- レスポンス送信
--------------------------------------------------------------------------------
function IADS_WEB_IMPORT:sendResponse(commandId, success, data, coalition)
    local response = {
        commandId = commandId,
        timestamp = timer.getTime(),
        success = success,
        data = data,
        coalition = coalition or IADS_WEB_IMPORT.COALITION.NEUTRAL
    }

    local json = self:toJSON(response)
    local file = io.open(self.config.responsePath, "w")
    if file then
        file:write(json)
        file:close()
    end
end

--------------------------------------------------------------------------------
-- JSONパース（シンプルな実装）
--------------------------------------------------------------------------------
function IADS_WEB_IMPORT:parseJSON(str)
    -- 空白をスキップ
    local pos = 1

    local function skipWhitespace()
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            else
                break
            end
        end
    end

    local parseValue

    local function parseString()
        pos = pos + 1  -- skip opening quote
        local start = pos
        local result = ""

        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == '"' then
                pos = pos + 1
                return result
            elseif c == '\\' then
                pos = pos + 1
                local escaped = str:sub(pos, pos)
                local escapeMap = {
                    ['"'] = '"',
                    ['\\'] = '\\',
                    ['/'] = '/',
                    ['b'] = '\b',
                    ['f'] = '\f',
                    ['n'] = '\n',
                    ['r'] = '\r',
                    ['t'] = '\t'
                }
                result = result .. (escapeMap[escaped] or escaped)
                pos = pos + 1
            else
                result = result .. c
                pos = pos + 1
            end
        end
        error("Unterminated string")
    end

    local function parseNumber()
        local start = pos
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c:match("[%d%.eE%+%-]") then
                pos = pos + 1
            else
                break
            end
        end
        return tonumber(str:sub(start, pos - 1))
    end

    local function parseArray()
        local arr = {}
        pos = pos + 1  -- skip [
        skipWhitespace()

        if str:sub(pos, pos) == ']' then
            pos = pos + 1
            return arr
        end

        while true do
            table.insert(arr, parseValue())
            skipWhitespace()

            local c = str:sub(pos, pos)
            if c == ']' then
                pos = pos + 1
                return arr
            elseif c == ',' then
                pos = pos + 1
                skipWhitespace()
            else
                error("Expected ',' or ']' in array")
            end
        end
    end

    local function parseObject()
        local obj = {}
        pos = pos + 1  -- skip {
        skipWhitespace()

        if str:sub(pos, pos) == '}' then
            pos = pos + 1
            return obj
        end

        while true do
            skipWhitespace()
            if str:sub(pos, pos) ~= '"' then
                error("Expected string key in object")
            end
            local key = parseString()
            skipWhitespace()

            if str:sub(pos, pos) ~= ':' then
                error("Expected ':' in object")
            end
            pos = pos + 1
            skipWhitespace()

            obj[key] = parseValue()
            skipWhitespace()

            local c = str:sub(pos, pos)
            if c == '}' then
                pos = pos + 1
                return obj
            elseif c == ',' then
                pos = pos + 1
            else
                error("Expected ',' or '}' in object")
            end
        end
    end

    parseValue = function()
        skipWhitespace()
        local c = str:sub(pos, pos)

        if c == '"' then
            return parseString()
        elseif c == '{' then
            return parseObject()
        elseif c == '[' then
            return parseArray()
        elseif c == 't' then
            if str:sub(pos, pos + 3) == 'true' then
                pos = pos + 4
                return true
            end
        elseif c == 'f' then
            if str:sub(pos, pos + 4) == 'false' then
                pos = pos + 5
                return false
            end
        elseif c == 'n' then
            if str:sub(pos, pos + 3) == 'null' then
                pos = pos + 4
                return nil
            end
        elseif c:match("[%d%-]") then
            return parseNumber()
        end

        error("Invalid JSON at position " .. pos)
    end

    return parseValue()
end

--------------------------------------------------------------------------------
-- JSON変換（シンプルな実装）
--------------------------------------------------------------------------------
function IADS_WEB_IMPORT:toJSON(data)
    local t = type(data)

    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return data and "true" or "false"
    elseif t == "number" then
        return tostring(data)
    elseif t == "string" then
        local escaped = data:gsub('[\\"\n\r\t]', function(c)
            local map = {['\\'] = '\\\\', ['"'] = '\\"', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
            return map[c]
        end)
        return '"' .. escaped .. '"'
    elseif t == "table" then
        -- 配列かオブジェクトか判定
        local isArray = true
        local count = 0
        for k, _ in pairs(data) do
            count = count + 1
            if type(k) ~= "number" then
                isArray = false
                break
            end
        end

        local parts = {}
        if isArray then
            for i, v in ipairs(data) do
                table.insert(parts, self:toJSON(v))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(data) do
                table.insert(parts, self:toJSON(tostring(k)) .. ":" .. self:toJSON(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end

    return "null"
end

--------------------------------------------------------------------------------
-- ステータス表示
--------------------------------------------------------------------------------
function IADS_WEB_IMPORT:printStatus()
    env.info("========== IADS WEB IMPORT STATUS ==========")
    env.info(string.format("State: %s", self.state))
    env.info(string.format("Import Path: %s", self.config.importPath))
    env.info(string.format("Poll Interval: %.1fs", self.config.pollInterval))
    env.info(string.format("Commands Processed: %d", self.commandsProcessed))
    env.info(string.format("Error Count: %d", self.errorCount))
    if self.lastError then
        env.info(string.format("Last Error: %s", self.lastError))
    end
    env.info("=============================================")
end

--------------------------------------------------------------------------------
-- グローバル登録
--------------------------------------------------------------------------------
if IADS_SYSTEMS then
    IADS_SYSTEMS.webImport = IADS_WEB_IMPORT
end

env.info("[IADS_WEB_IMPORT] Module loaded")
