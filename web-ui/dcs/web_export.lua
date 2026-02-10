--[[
IADS Web Export Module
DCS World用 IADS状態エクスポートシステム

このモジュールはIADSシステムの状態を定期的にJSONファイルにエクスポートし、
外部のWebアプリケーションから読み取れるようにします。

使用方法:
    local webExport = IADS_WEB_EXPORT:new()
    webExport:init()
    webExport:startExport()
]]

IADS_WEB_EXPORT = {}
IADS_WEB_EXPORT.__index = IADS_WEB_EXPORT

-- デフォルト設定
IADS_WEB_EXPORT.DEFAULT_CONFIG = {
    exportPath = nil,  -- 自動設定（Saved Games/DCS/iads_state.json）
    updateInterval = 1.0,  -- 秒
    includeThreats = true,
    includeStatistics = true,
    includeEWR = true,
    prettyPrint = false,  -- JSONを整形するか（デバッグ用）
    maxThreats = 50,  -- 最大脅威数
    positionPrecision = 2  -- 座標の小数点以下桁数
}

-- 状態定数
IADS_WEB_EXPORT.STATE = {
    STOPPED = "STOPPED",
    RUNNING = "RUNNING",
    ERROR = "ERROR"
}

--------------------------------------------------------------------------------
-- コンストラクタ
--------------------------------------------------------------------------------
function IADS_WEB_EXPORT:new(config)
    local self = setmetatable({}, IADS_WEB_EXPORT)

    self.config = {}
    for k, v in pairs(IADS_WEB_EXPORT.DEFAULT_CONFIG) do
        self.config[k] = config and config[k] or v
    end

    -- エクスポートパスの自動設定
    if not self.config.exportPath then
        self.config.exportPath = self:getDefaultExportPath()
    end

    self.state = IADS_WEB_EXPORT.STATE.STOPPED
    self.lastExportTime = 0
    self.exportCount = 0
    self.errorCount = 0
    self.lastError = nil

    return self
end

--------------------------------------------------------------------------------
-- 初期化
--------------------------------------------------------------------------------
function IADS_WEB_EXPORT:init()
    env.info("[IADS_WEB_EXPORT] Initializing web export system")

    -- lfsモジュールの確認
    if not lfs then
        env.warning("[IADS_WEB_EXPORT] LFS module not available, using fallback path")
    end

    -- エクスポートディレクトリの確認
    local dir = self:getExportDirectory()
    if dir and lfs then
        local attr = lfs.attributes(dir)
        if not attr then
            env.warning("[IADS_WEB_EXPORT] Export directory does not exist: " .. dir)
        end
    end

    env.info("[IADS_WEB_EXPORT] Export path: " .. self.config.exportPath)
    env.info("[IADS_WEB_EXPORT] Update interval: " .. self.config.updateInterval .. "s")

    return self
end

--------------------------------------------------------------------------------
-- エクスポートパス取得
--------------------------------------------------------------------------------
function IADS_WEB_EXPORT:getDefaultExportPath()
    if lfs then
        local writedir = lfs.writedir()
        if writedir then
            return writedir .. "iads_state.json"
        end
    end
    -- フォールバック
    return "iads_state.json"
end

function IADS_WEB_EXPORT:getExportDirectory()
    local path = self.config.exportPath
    local lastSlash = path:match(".*[/\\]()")
    if lastSlash then
        return path:sub(1, lastSlash - 1)
    end
    return nil
end

--------------------------------------------------------------------------------
-- エクスポート開始/停止
--------------------------------------------------------------------------------
function IADS_WEB_EXPORT:startExport()
    if self.state == IADS_WEB_EXPORT.STATE.RUNNING then
        env.info("[IADS_WEB_EXPORT] Already running")
        return self
    end

    env.info("[IADS_WEB_EXPORT] Starting export")
    self.state = IADS_WEB_EXPORT.STATE.RUNNING
    self:scheduleExport()

    return self
end

function IADS_WEB_EXPORT:stopExport()
    env.info("[IADS_WEB_EXPORT] Stopping export")
    self.state = IADS_WEB_EXPORT.STATE.STOPPED

    return self
end

function IADS_WEB_EXPORT:scheduleExport()
    if self.state ~= IADS_WEB_EXPORT.STATE.RUNNING then
        return
    end

    timer.scheduleFunction(function()
        self:doExport()
        self:scheduleExport()
    end, nil, timer.getTime() + self.config.updateInterval)
end

--------------------------------------------------------------------------------
-- エクスポート実行
--------------------------------------------------------------------------------
function IADS_WEB_EXPORT:doExport()
    local success, err = pcall(function()
        local data = self:collectData()
        local json = self:toJSON(data)
        self:writeFile(json)

        self.lastExportTime = timer.getTime()
        self.exportCount = self.exportCount + 1
    end)

    if not success then
        self.errorCount = self.errorCount + 1
        self.lastError = err
        self.state = IADS_WEB_EXPORT.STATE.ERROR
        env.error("[IADS_WEB_EXPORT] Export failed: " .. tostring(err))
    end
end

--------------------------------------------------------------------------------
-- データ収集
--------------------------------------------------------------------------------
function IADS_WEB_EXPORT:collectData()
    local data = {
        timestamp = timer.getTime(),
        missionTime = self:formatMissionTime(timer.getTime()),
        exportTime = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        defcon = "NORMAL",
        tacticalMode = "BALANCED",
        samSites = {},
        ewrSites = {},
        threats = {},
        statistics = {}
    }

    -- グローバルIADSシステムからデータ収集
    if IADS_SYSTEMS then
        -- コマンダーからDEFCON/戦術モード取得
        if IADS_SYSTEMS.commander then
            data.defcon = IADS_SYSTEMS.commander.currentDefcon or "NORMAL"
            data.tacticalMode = IADS_SYSTEMS.commander.currentMode or "BALANCED"
        end

        -- SAMサイト情報収集
        data.samSites = self:collectSAMData()

        -- EWRサイト情報収集
        if self.config.includeEWR then
            data.ewrSites = self:collectEWRData()
        end

        -- 脅威情報収集
        if self.config.includeThreats then
            data.threats = self:collectThreatData()
        end

        -- 統計情報収集
        if self.config.includeStatistics then
            data.statistics = self:collectStatistics()
        end
    end

    return data
end

function IADS_WEB_EXPORT:collectSAMData()
    local sams = {}

    -- IADSネットワークからSAMサイト取得
    if IADS_SYSTEMS.network and IADS_SYSTEMS.network.samSites then
        for name, site in pairs(IADS_SYSTEMS.network.samSites) do
            local samData = {
                name = name,
                state = site.state or "UNKNOWN",
                type = site.type or "UNKNOWN",
                position = self:formatPosition(site.position),
                range = site.range or 0,
                ammo = 100,
                health = 100,
                isActive = site.state == "GREEN" or site.state == "TRACKING",
                lastEngagement = nil,
                linkedEWRs = {}
            }

            -- 弾薬管理システムからデータ取得
            if IADS_SYSTEMS.ammo and IADS_SYSTEMS.ammo.samAmmo then
                local ammoData = IADS_SYSTEMS.ammo.samAmmo[name]
                if ammoData then
                    samData.ammo = math.floor((ammoData.current / ammoData.max) * 100)
                end
            end

            -- メンテナンスシステムからHP取得
            if IADS_SYSTEMS.maintenance and IADS_SYSTEMS.maintenance.samStatus then
                local status = IADS_SYSTEMS.maintenance.samStatus[name]
                if status then
                    samData.health = math.floor(status.health or 100)
                end
            end

            -- 統合データリンクからEWR連携取得
            if IADS_SYSTEMS.datalink and IADS_SYSTEMS.datalink.linkedEWRs then
                local linked = IADS_SYSTEMS.datalink.linkedEWRs[name]
                if linked then
                    for ewrName, _ in pairs(linked) do
                        table.insert(samData.linkedEWRs, ewrName)
                    end
                end
            end

            sams[name] = samData
        end
    end

    return sams
end

function IADS_WEB_EXPORT:collectEWRData()
    local ewrs = {}

    if IADS_SYSTEMS.network and IADS_SYSTEMS.network.ewrSites then
        for name, site in pairs(IADS_SYSTEMS.network.ewrSites) do
            ewrs[name] = {
                name = name,
                type = site.type or "EWR",
                position = self:formatPosition(site.position),
                range = site.range or 0,
                isActive = site.isActive ~= false,
                detectedThreats = 0
            }
        end
    end

    return ewrs
end

function IADS_WEB_EXPORT:collectThreatData()
    local threats = {}
    local count = 0

    -- 脅威追跡システムから取得
    if IADS_SYSTEMS.network and IADS_SYSTEMS.network.trackedThreats then
        for trackId, threat in pairs(IADS_SYSTEMS.network.trackedThreats) do
            if count >= self.config.maxThreats then
                break
            end

            local threatData = {
                id = trackId,
                type = threat.type or "UNKNOWN",
                category = threat.category or "AIR",
                position = self:formatPosition(threat.position),
                heading = threat.heading or 0,
                speed = threat.speed or 0,
                altitude = threat.altitude or 0,
                isSEAD = threat.isSEAD or false,
                threatLevel = threat.threatLevel or "LOW",
                firstDetected = threat.firstDetected,
                lastSeen = threat.lastSeen or timer.getTime()
            }

            threats[trackId] = threatData
            count = count + 1
        end
    end

    return threats
end

function IADS_WEB_EXPORT:collectStatistics()
    local stats = {
        totalSAMs = 0,
        activeSAMs = 0,
        darkSAMs = 0,
        totalEWRs = 0,
        activeThreats = 0,
        missilesRemaining = 0,
        missilesFired = 0,
        kills = 0
    }

    -- SAM統計
    if IADS_SYSTEMS.network and IADS_SYSTEMS.network.samSites then
        for name, site in pairs(IADS_SYSTEMS.network.samSites) do
            stats.totalSAMs = stats.totalSAMs + 1
            if site.state == "GREEN" or site.state == "TRACKING" or site.state == "ENGAGING" then
                stats.activeSAMs = stats.activeSAMs + 1
            elseif site.state == "DARK" then
                stats.darkSAMs = stats.darkSAMs + 1
            end
        end
    end

    -- EWR統計
    if IADS_SYSTEMS.network and IADS_SYSTEMS.network.ewrSites then
        for _, _ in pairs(IADS_SYSTEMS.network.ewrSites) do
            stats.totalEWRs = stats.totalEWRs + 1
        end
    end

    -- 脅威統計
    if IADS_SYSTEMS.network and IADS_SYSTEMS.network.trackedThreats then
        for _, _ in pairs(IADS_SYSTEMS.network.trackedThreats) do
            stats.activeThreats = stats.activeThreats + 1
        end
    end

    -- ロガーから戦闘統計取得
    if IADS_SYSTEMS.logger and IADS_SYSTEMS.logger.statistics then
        local logStats = IADS_SYSTEMS.logger.statistics
        stats.missilesFired = logStats.missilesFired or 0
        stats.kills = logStats.kills or 0
    end

    return stats
end

--------------------------------------------------------------------------------
-- ユーティリティ関数
--------------------------------------------------------------------------------
function IADS_WEB_EXPORT:formatMissionTime(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", hours, mins, secs)
end

function IADS_WEB_EXPORT:formatPosition(pos)
    if not pos then
        return {x = 0, y = 0, z = 0, lat = 0, lon = 0}
    end

    local precision = self.config.positionPrecision
    local lat, lon = 0, 0

    -- DCS座標を緯度経度に変換
    if coord and coord.LOtoLL then
        lat, lon, _ = coord.LOtoLL({x = pos.x, y = pos.y or 0, z = pos.z})
    end

    return {
        x = self:round(pos.x, precision),
        y = self:round(pos.y or 0, precision),
        z = self:round(pos.z, precision),
        lat = self:round(lat, precision + 4),
        lon = self:round(lon, precision + 4)
    }
end

function IADS_WEB_EXPORT:round(num, decimals)
    local mult = 10^(decimals or 0)
    return math.floor(num * mult + 0.5) / mult
end

--------------------------------------------------------------------------------
-- JSON変換
--------------------------------------------------------------------------------
function IADS_WEB_EXPORT:toJSON(data)
    return self:encodeValue(data, self.config.prettyPrint, 0)
end

function IADS_WEB_EXPORT:encodeValue(value, pretty, indent)
    local t = type(value)

    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        if value ~= value then
            return "null"  -- NaN
        elseif value == math.huge or value == -math.huge then
            return "null"  -- Infinity
        end
        return tostring(value)
    elseif t == "string" then
        return self:encodeString(value)
    elseif t == "table" then
        return self:encodeTable(value, pretty, indent)
    else
        return "null"
    end
end

function IADS_WEB_EXPORT:encodeString(s)
    local escaped = s:gsub('[\\"\b\f\n\r\t]', function(c)
        local map = {
            ['\\'] = '\\\\',
            ['"'] = '\\"',
            ['\b'] = '\\b',
            ['\f'] = '\\f',
            ['\n'] = '\\n',
            ['\r'] = '\\r',
            ['\t'] = '\\t'
        }
        return map[c]
    end)
    return '"' .. escaped .. '"'
end

function IADS_WEB_EXPORT:encodeTable(tbl, pretty, indent)
    -- 配列かオブジェクトか判定
    local isArray = true
    local maxIndex = 0
    local count = 0

    for k, _ in pairs(tbl) do
        count = count + 1
        if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then
            isArray = false
            break
        end
        if k > maxIndex then
            maxIndex = k
        end
    end

    if isArray and maxIndex ~= count then
        isArray = false
    end

    local newline = pretty and "\n" or ""
    local space = pretty and " " or ""
    local indentStr = pretty and string.rep("  ", indent + 1) or ""
    local closeIndent = pretty and string.rep("  ", indent) or ""

    local parts = {}

    if isArray then
        for i = 1, #tbl do
            table.insert(parts, indentStr .. self:encodeValue(tbl[i], pretty, indent + 1))
        end
        if #parts == 0 then
            return "[]"
        end
        return "[" .. newline .. table.concat(parts, "," .. newline) .. newline .. closeIndent .. "]"
    else
        for k, v in pairs(tbl) do
            local key = type(k) == "string" and self:encodeString(k) or self:encodeString(tostring(k))
            table.insert(parts, indentStr .. key .. ":" .. space .. self:encodeValue(v, pretty, indent + 1))
        end
        if #parts == 0 then
            return "{}"
        end
        return "{" .. newline .. table.concat(parts, "," .. newline) .. newline .. closeIndent .. "}"
    end
end

--------------------------------------------------------------------------------
-- ファイル書き込み
--------------------------------------------------------------------------------
function IADS_WEB_EXPORT:writeFile(content)
    local file = io.open(self.config.exportPath, "w")
    if not file then
        error("Cannot open file for writing: " .. self.config.exportPath)
    end

    file:write(content)
    file:close()
end

--------------------------------------------------------------------------------
-- ステータス表示
--------------------------------------------------------------------------------
function IADS_WEB_EXPORT:printStatus()
    env.info("========== IADS WEB EXPORT STATUS ==========")
    env.info(string.format("State: %s", self.state))
    env.info(string.format("Export Path: %s", self.config.exportPath))
    env.info(string.format("Update Interval: %.1fs", self.config.updateInterval))
    env.info(string.format("Export Count: %d", self.exportCount))
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
    IADS_SYSTEMS.webExport = IADS_WEB_EXPORT
end

env.info("[IADS_WEB_EXPORT] Module loaded")
