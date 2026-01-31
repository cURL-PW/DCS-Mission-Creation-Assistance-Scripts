--[[
    DCS IADS F10 Map Integration
    F10マップ連携システム

    F10マップ上にIADS情報を表示し、コマンド入力インターフェースを提供

    機能:
    - SAMサイトのステータス表示（マーカー）
    - 脅威情報表示
    - カバレッジエリア表示
    - ラジオメニューによるコマンド入力
    - マーカーイベント処理

    依存: core/utils.lua, iads/network.lua
    DCS API: trigger.action, missionCommands
]]

IADS_F10_MAP = {}
IADS_F10_MAP.__index = IADS_F10_MAP

-- ============================================
-- マーカータイプ
-- ============================================
IADS_F10_MAP.MARKER_TYPE = {
    SAM_ACTIVE = "SAM_ACTIVE",
    SAM_DARK = "SAM_DARK",
    SAM_DAMAGED = "SAM_DAMAGED",
    EWR = "EWR",
    THREAT = "THREAT",
    HVT = "HVT",
    DECOY = "DECOY"
}

-- ============================================
-- マーカーアイコン（Unicode/テキスト表現）
-- ============================================
IADS_F10_MAP.ICONS = {
    SAM_ACTIVE = "[SAM+]",
    SAM_DARK = "[SAM-]",
    SAM_DAMAGED = "[SAM!]",
    EWR = "[EWR]",
    THREAT = "[THR]",
    HVT = "[HVT]",
    DECOY = "[DCY]"
}

-- ============================================
-- F10マップシステム作成
-- ============================================
function IADS_F10_MAP.new(iadsNetwork)
    local self = setmetatable({}, IADS_F10_MAP)

    self.network = iadsNetwork
    self.updateInterval = 10       -- 更新間隔（秒）
    self.isRunning = false

    -- マーカー管理
    self.markers = {}
    self.markerIdCounter = 1000    -- DCSマーカーIDの開始値
    self.markerPrefix = "IADS_"

    -- 表示設定
    self.displaySettings = {
        showSamSites = true,
        showEwrSites = true,
        showThreats = true,
        showHvt = true,
        showDecoys = false,
        showCoverage = false,
        showDetailedInfo = true
    }

    -- ラジオメニュー
    self.radioMenus = {}
    self.commandHandlers = {}

    -- マーカーイベント
    self.markerEventHandlerId = nil

    -- 色設定（DCSは限られた色のみサポート）
    self.colors = {
        samActive = {0, 1, 0, 0.8},     -- 緑
        samDark = {0.5, 0.5, 0.5, 0.8}, -- グレー
        samDamaged = {1, 0.5, 0, 0.8},  -- オレンジ
        ewr = {0, 0, 1, 0.8},           -- 青
        threat = {1, 0, 0, 0.8},        -- 赤
        hvt = {1, 1, 0, 0.8},           -- 黄
        decoy = {0.5, 0, 0.5, 0.8}      -- 紫
    }

    return self
end

-- ============================================
-- 初期化
-- ============================================
function IADS_F10_MAP:init(options)
    options = options or {}

    if options.updateInterval then
        self.updateInterval = options.updateInterval
    end

    -- 表示設定
    if options.displaySettings then
        for k, v in pairs(options.displaySettings) do
            self.displaySettings[k] = v
        end
    end

    -- ラジオメニューを作成
    self:createRadioMenus()

    -- マーカーイベントハンドラを登録
    self:registerMarkerEventHandler()

    self.isRunning = true
    self:scheduleUpdate()

    SAM_UTILS.debug("[F10Map] System initialized")
    return self
end

-- ============================================
-- ラジオメニュー作成
-- ============================================
function IADS_F10_MAP:createRadioMenus()
    -- メインメニュー
    local mainMenu = missionCommands.addSubMenu("IADS Control")
    self.radioMenus.main = mainMenu

    -- ステータス表示サブメニュー
    local statusMenu = missionCommands.addSubMenu("Status", mainMenu)
    missionCommands.addCommand("Show All Status", statusMenu, function()
        self:showAllStatus()
    end)
    missionCommands.addCommand("Show SAM Status", statusMenu, function()
        self:showSamStatus()
    end)
    missionCommands.addCommand("Show Threat Status", statusMenu, function()
        self:showThreatStatus()
    end)

    -- DEFCON制御サブメニュー
    local defconMenu = missionCommands.addSubMenu("DEFCON", mainMenu)
    missionCommands.addCommand("PEACE", defconMenu, function()
        self:setDefcon("PEACE")
    end)
    missionCommands.addCommand("ELEVATED", defconMenu, function()
        self:setDefcon("ELEVATED")
    end)
    missionCommands.addCommand("HIGH", defconMenu, function()
        self:setDefcon("HIGH")
    end)
    missionCommands.addCommand("SEVERE", defconMenu, function()
        self:setDefcon("SEVERE")
    end)
    missionCommands.addCommand("CRITICAL", defconMenu, function()
        self:setDefcon("CRITICAL")
    end)

    -- 戦術モードサブメニュー
    local tacticsMenu = missionCommands.addSubMenu("Tactics", mainMenu)
    missionCommands.addCommand("Conservative", tacticsMenu, function()
        self:setTacticalMode("CONSERVATIVE")
    end)
    missionCommands.addCommand("Balanced", tacticsMenu, function()
        self:setTacticalMode("BALANCED")
    end)
    missionCommands.addCommand("Aggressive", tacticsMenu, function()
        self:setTacticalMode("AGGRESSIVE")
    end)
    missionCommands.addCommand("Ambush", tacticsMenu, function()
        self:setTacticalMode("AMBUSH")
    end)

    -- SAM制御サブメニュー
    local samMenu = missionCommands.addSubMenu("SAM Control", mainMenu)
    missionCommands.addCommand("Activate All", samMenu, function()
        self:activateAllSams()
    end)
    missionCommands.addCommand("Deactivate All", samMenu, function()
        self:deactivateAllSams()
    end)

    -- 表示制御サブメニュー
    local displayMenu = missionCommands.addSubMenu("Display", mainMenu)
    missionCommands.addCommand("Toggle SAMs", displayMenu, function()
        self:toggleDisplay("showSamSites")
    end)
    missionCommands.addCommand("Toggle Threats", displayMenu, function()
        self:toggleDisplay("showThreats")
    end)
    missionCommands.addCommand("Toggle EWRs", displayMenu, function()
        self:toggleDisplay("showEwrSites")
    end)
    missionCommands.addCommand("Refresh Map", displayMenu, function()
        self:refreshAllMarkers()
    end)

    SAM_UTILS.debug("[F10Map] Radio menus created")
end

-- ============================================
-- マーカーイベントハンドラ登録
-- ============================================
function IADS_F10_MAP:registerMarkerEventHandler()
    local f10Map = self

    local eventHandler = {}
    function eventHandler:onEvent(event)
        if event.id == world.event.S_EVENT_MARK_ADDED then
            f10Map:onMarkerAdded(event)
        elseif event.id == world.event.S_EVENT_MARK_CHANGE then
            f10Map:onMarkerChanged(event)
        elseif event.id == world.event.S_EVENT_MARK_REMOVED then
            f10Map:onMarkerRemoved(event)
        end
    end

    world.addEventHandler(eventHandler)
    self.markerEventHandlerId = eventHandler

    SAM_UTILS.debug("[F10Map] Marker event handler registered")
end

-- ============================================
-- マーカー追加イベント処理
-- ============================================
function IADS_F10_MAP:onMarkerAdded(event)
    -- ユーザーがマーカーを追加した場合の処理
    if event.text then
        self:processMarkerCommand(event.text, event.pos, event.idx)
    end
end

-- ============================================
-- マーカー変更イベント処理
-- ============================================
function IADS_F10_MAP:onMarkerChanged(event)
    if event.text then
        self:processMarkerCommand(event.text, event.pos, event.idx)
    end
end

-- ============================================
-- マーカー削除イベント処理
-- ============================================
function IADS_F10_MAP:onMarkerRemoved(event)
    -- 必要に応じて処理
end

-- ============================================
-- マーカーコマンド処理
-- ============================================
function IADS_F10_MAP:processMarkerCommand(text, position, markerId)
    if not text or not position then return end

    local cmd = string.upper(text)

    -- コマンドパターンをチェック
    if string.match(cmd, "^IADS%s+") then
        local command = string.match(cmd, "^IADS%s+(.+)")

        if command == "STATUS" then
            self:showStatusAtPosition(position)
        elseif command == "ACTIVATE" then
            self:activateSamsNear(position, 50000)
        elseif command == "DEACTIVATE" then
            self:deactivateSamsNear(position, 50000)
        elseif string.match(command, "^DEFCON%s+") then
            local level = string.match(command, "^DEFCON%s+(%w+)")
            self:setDefcon(level)
        end

        -- コマンドマーカーを削除
        trigger.action.removeMark(markerId)
    end
end

-- ============================================
-- マーカーを追加
-- ============================================
function IADS_F10_MAP:addMarker(id, markerType, position, text, coalition)
    if not position then return nil end

    local markerId = self.markerIdCounter
    self.markerIdCounter = self.markerIdCounter + 1

    -- マーカーテキストを構築
    local icon = self.ICONS[markerType] or "[?]"
    local fullText = icon .. " " .. (text or "")

    -- DCSマーカーを追加
    if coalition then
        trigger.action.markToCoalition(markerId, fullText, position, coalition, true)
    else
        trigger.action.markToAll(markerId, fullText, position, true)
    end

    -- マーカー情報を保存
    self.markers[id] = {
        markerId = markerId,
        markerType = markerType,
        position = position,
        text = text
    }

    return markerId
end

-- ============================================
-- マーカーを更新
-- ============================================
function IADS_F10_MAP:updateMarker(id, markerType, position, text)
    local marker = self.markers[id]
    if marker then
        -- 既存マーカーを削除
        trigger.action.removeMark(marker.markerId)
    end

    -- 新しいマーカーを追加
    return self:addMarker(id, markerType, position, text)
end

-- ============================================
-- マーカーを削除
-- ============================================
function IADS_F10_MAP:removeMarker(id)
    local marker = self.markers[id]
    if marker then
        trigger.action.removeMark(marker.markerId)
        self.markers[id] = nil
        return true
    end
    return false
end

-- ============================================
-- 全マーカーを削除
-- ============================================
function IADS_F10_MAP:removeAllMarkers()
    for id, marker in pairs(self.markers) do
        trigger.action.removeMark(marker.markerId)
    end
    self.markers = {}
end

-- ============================================
-- SAMサイトマーカーを更新
-- ============================================
function IADS_F10_MAP:updateSamMarkers()
    if not self.network or not self.displaySettings.showSamSites then
        return
    end

    for samName, samSite in pairs(self.network.samSites) do
        if samSite.position then
            local markerType
            local status = ""

            -- 状態を判定
            local samState = samSite.state or "DARK"
            if samState == "GREEN" or samState == "RED" then
                markerType = IADS_F10_MAP.MARKER_TYPE.SAM_ACTIVE
                status = "ACTIVE"
            else
                markerType = IADS_F10_MAP.MARKER_TYPE.SAM_DARK
                status = "DARK"
            end

            -- 損傷チェック
            if IADS_SYSTEMS and IADS_SYSTEMS.maintenance then
                local maintStatus = IADS_SYSTEMS.maintenance.siteStatus[samName]
                if maintStatus and maintStatus.health and maintStatus.health < 100 then
                    markerType = IADS_F10_MAP.MARKER_TYPE.SAM_DAMAGED
                    status = string.format("DMG %d%%", maintStatus.health)
                end
            end

            -- 詳細情報
            local text = samName
            if self.displaySettings.showDetailedInfo then
                text = samName .. "\n" .. status

                -- 弾薬情報
                if IADS_SYSTEMS and IADS_SYSTEMS.ammo then
                    local ammoStatus = IADS_SYSTEMS.ammo:getGroupStatus(samName)
                    if ammoStatus and ammoStatus.ammoPercent then
                        text = text .. string.format("\nAmmo: %d%%", ammoStatus.ammoPercent)
                    end
                end
            end

            self:updateMarker("SAM_" .. samName, markerType, samSite.position, text)
        end
    end
end

-- ============================================
-- EWRマーカーを更新
-- ============================================
function IADS_F10_MAP:updateEwrMarkers()
    if not self.network or not self.displaySettings.showEwrSites then
        return
    end

    for ewrName, ewr in pairs(self.network.ewrSites or {}) do
        if ewr.position then
            local text = ewrName
            if self.displaySettings.showDetailedInfo then
                text = ewrName .. "\nEWR Active"
            end

            self:updateMarker("EWR_" .. ewrName, IADS_F10_MAP.MARKER_TYPE.EWR, ewr.position, text)
        end
    end
end

-- ============================================
-- 脅威マーカーを更新
-- ============================================
function IADS_F10_MAP:updateThreatMarkers()
    if not self.network or not self.displaySettings.showThreats then
        return
    end

    -- 古い脅威マーカーを削除
    local toRemove = {}
    for id, _ in pairs(self.markers) do
        if string.match(id, "^THREAT_") then
            table.insert(toRemove, id)
        end
    end
    for _, id in ipairs(toRemove) do
        self:removeMarker(id)
    end

    -- 新しい脅威マーカーを追加
    for threatId, threat in pairs(self.network.threats or {}) do
        if threat.position then
            local text = threatId
            if self.displaySettings.showDetailedInfo then
                local threatType = threat.type or "UNKNOWN"
                local threatLevel = threat.level or 0
                text = string.format("%s\n%s\nLevel: %d", threatId, threatType, threatLevel)
            end

            self:updateMarker("THREAT_" .. threatId, IADS_F10_MAP.MARKER_TYPE.THREAT, threat.position, text)
        end
    end
end

-- ============================================
-- 全マーカーを更新
-- ============================================
function IADS_F10_MAP:refreshAllMarkers()
    self:removeAllMarkers()
    self:updateSamMarkers()
    self:updateEwrMarkers()
    self:updateThreatMarkers()

    SAM_UTILS.info("[F10Map] Map markers refreshed", 5)
end

-- ============================================
-- 表示設定を切り替え
-- ============================================
function IADS_F10_MAP:toggleDisplay(setting)
    if self.displaySettings[setting] ~= nil then
        self.displaySettings[setting] = not self.displaySettings[setting]
        self:refreshAllMarkers()

        local state = self.displaySettings[setting] and "ON" or "OFF"
        SAM_UTILS.info("[F10Map] " .. setting .. ": " .. state, 5)
    end
end

-- ============================================
-- 全ステータス表示
-- ============================================
function IADS_F10_MAP:showAllStatus()
    if IADS_SYSTEMS and IADS_SYSTEMS.commander then
        IADS_SYSTEMS.commander:printStatus()
    else
        self:showSamStatus()
    end
end

-- ============================================
-- SAMステータス表示
-- ============================================
function IADS_F10_MAP:showSamStatus()
    if not self.network then return end

    local msg = "=== SAM Status ===\n"
    local active = 0
    local dark = 0
    local total = 0

    for samName, samSite in pairs(self.network.samSites) do
        total = total + 1
        local state = samSite.state or "UNKNOWN"
        if state == "GREEN" or state == "RED" then
            active = active + 1
        else
            dark = dark + 1
        end
    end

    msg = msg .. string.format("Total: %d | Active: %d | Dark: %d", total, active, dark)

    SAM_UTILS.info(msg, 15)
end

-- ============================================
-- 脅威ステータス表示
-- ============================================
function IADS_F10_MAP:showThreatStatus()
    if not self.network then return end

    local msg = "=== Threat Status ===\n"
    local threatCount = 0

    for threatId, threat in pairs(self.network.threats or {}) do
        threatCount = threatCount + 1
        local threatType = threat.type or "UNKNOWN"
        msg = msg .. string.format("%s: %s\n", threatId, threatType)
    end

    if threatCount == 0 then
        msg = msg .. "No active threats detected"
    end

    SAM_UTILS.info(msg, 15)
end

-- ============================================
-- 位置のステータス表示
-- ============================================
function IADS_F10_MAP:showStatusAtPosition(position)
    if not self.network or not position then return end

    local msg = "=== Area Status ===\n"
    local nearestSam = nil
    local minDistance = math.huge

    for samName, samSite in pairs(self.network.samSites) do
        if samSite.position then
            local dist = SAM_UTILS.getDistance2D(position, samSite.position)
            if dist and dist < minDistance then
                minDistance = dist
                nearestSam = samName
            end
        end
    end

    if nearestSam then
        msg = msg .. string.format("Nearest SAM: %s (%.1f km)", nearestSam, minDistance / 1000)
    else
        msg = msg .. "No SAM sites found"
    end

    SAM_UTILS.info(msg, 10)
end

-- ============================================
-- DEFCONを設定
-- ============================================
function IADS_F10_MAP:setDefcon(level)
    if IADS_SYSTEMS and IADS_SYSTEMS.commander then
        local defcon = IADS_COMMANDER.DEFENSE_CONDITION[level]
        if defcon then
            IADS_SYSTEMS.commander:setDefenseCondition(defcon)
            SAM_UTILS.info("[F10Map] DEFCON set to: " .. level, 10)
        end
    else
        SAM_UTILS.info("[F10Map] Commander not available", 5)
    end
end

-- ============================================
-- 戦術モードを設定
-- ============================================
function IADS_F10_MAP:setTacticalMode(mode)
    if IADS_SYSTEMS and IADS_SYSTEMS.commander then
        local tacticalMode = IADS_COMMANDER.TACTICAL_MODE[mode]
        if tacticalMode then
            IADS_SYSTEMS.commander:setTacticalMode(tacticalMode)
            SAM_UTILS.info("[F10Map] Tactical mode set to: " .. mode, 10)
        end
    else
        SAM_UTILS.info("[F10Map] Commander not available", 5)
    end
end

-- ============================================
-- 全SAMをアクティブ化
-- ============================================
function IADS_F10_MAP:activateAllSams()
    if self.network then
        self.network:activateAllSams()
        SAM_UTILS.info("[F10Map] All SAMs activated", 10)
        self:refreshAllMarkers()
    end
end

-- ============================================
-- 全SAMを停波
-- ============================================
function IADS_F10_MAP:deactivateAllSams()
    if self.network then
        for samName, _ in pairs(self.network.samSites) do
            self.network:setSamState(samName, IADS_NETWORK.SAM_STATE.DARK)
        end
        SAM_UTILS.info("[F10Map] All SAMs deactivated", 10)
        self:refreshAllMarkers()
    end
end

-- ============================================
-- 位置近くのSAMをアクティブ化
-- ============================================
function IADS_F10_MAP:activateSamsNear(position, radius)
    if not self.network or not position then return end

    local count = 0
    for samName, samSite in pairs(self.network.samSites) do
        if samSite.position then
            local dist = SAM_UTILS.getDistance2D(position, samSite.position)
            if dist and dist < radius then
                self.network:setSamState(samName, IADS_NETWORK.SAM_STATE.GREEN)
                count = count + 1
            end
        end
    end

    SAM_UTILS.info(string.format("[F10Map] Activated %d SAMs near marker", count), 10)
    self:refreshAllMarkers()
end

-- ============================================
-- 位置近くのSAMを停波
-- ============================================
function IADS_F10_MAP:deactivateSamsNear(position, radius)
    if not self.network or not position then return end

    local count = 0
    for samName, samSite in pairs(self.network.samSites) do
        if samSite.position then
            local dist = SAM_UTILS.getDistance2D(position, samSite.position)
            if dist and dist < radius then
                self.network:setSamState(samName, IADS_NETWORK.SAM_STATE.DARK)
                count = count + 1
            end
        end
    end

    SAM_UTILS.info(string.format("[F10Map] Deactivated %d SAMs near marker", count), 10)
    self:refreshAllMarkers()
end

-- ============================================
-- 定期更新
-- ============================================
function IADS_F10_MAP:update()
    if not self.isRunning then return end

    -- マーカーを更新
    self:updateSamMarkers()
    self:updateEwrMarkers()
    self:updateThreatMarkers()

    -- 次の更新をスケジュール
    self:scheduleUpdate()
end

-- ============================================
-- 更新スケジュール
-- ============================================
function IADS_F10_MAP:scheduleUpdate()
    local f10Map = self
    SAM_UTILS.scheduleFunction(function()
        f10Map:update()
    end, nil, SAM_UTILS.getTime() + self.updateInterval)
end

-- ============================================
-- 停止
-- ============================================
function IADS_F10_MAP:stop()
    self.isRunning = false
    self:removeAllMarkers()
end

-- ============================================
-- ステータス取得
-- ============================================
function IADS_F10_MAP:getStatus()
    local markerCount = 0
    for _ in pairs(self.markers) do
        markerCount = markerCount + 1
    end

    return {
        isRunning = self.isRunning,
        markerCount = markerCount,
        displaySettings = SAM_UTILS.deepCopy(self.displaySettings)
    }
end

-- ============================================
-- ステータス表示
-- ============================================
function IADS_F10_MAP:printStatus()
    local status = self:getStatus()

    local msg = "[F10 Map Status]\n"
    msg = msg .. string.format("Running: %s | Markers: %d\n",
        status.isRunning and "Yes" or "No", status.markerCount)
    msg = msg .. "Display Settings:\n"

    for setting, value in pairs(status.displaySettings) do
        msg = msg .. string.format("  %s: %s\n", setting, value and "ON" or "OFF")
    end

    SAM_UTILS.info(msg, 15)
end

return IADS_F10_MAP
