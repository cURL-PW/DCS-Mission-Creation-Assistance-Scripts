--[[
    DCS IADS Coalition Information Filter
    陣営別情報フィルタリングシステム

    マルチプレイヤー環境でプレイヤーの陣営に応じて情報を適切にフィルタリング

    機能:
    - 陣営別情報アクセス制御
    - Red/Blue/Neutral別の視点
    - ゲームマスター/観戦者権限
    - F10マップ表示の陣営フィルタ
    - ラジオメニューの陣営制限

    依存: core/utils.lua, iads/network.lua, ui/f10_map.lua
    DCS API: coalition, net
]]

IADS_COALITION = {}
IADS_COALITION.__index = IADS_COALITION

-- ============================================
-- 陣営定数
-- ============================================
IADS_COALITION.SIDE = {
    NEUTRAL = 0,
    RED = 1,
    BLUE = 2,
    ALL = -1        -- 全陣営（ゲームマスター用）
}

-- ============================================
-- アクセスレベル
-- ============================================
IADS_COALITION.ACCESS_LEVEL = {
    NONE = 0,           -- アクセス不可
    BASIC = 1,          -- 基本情報のみ（検出された敵のみ）
    STANDARD = 2,       -- 標準（自軍の詳細、敵は検出されたもののみ）
    ELEVATED = 3,       -- 上級（詳細な敵情報）
    FULL = 4,           -- 完全（ゲームマスター）
    ADMIN = 5           -- 管理者（全情報＋設定変更）
}

-- ============================================
-- 情報タイプ
-- ============================================
IADS_COALITION.INFO_TYPE = {
    SAM_POSITION = "SAM_POSITION",
    SAM_STATE = "SAM_STATE",
    SAM_AMMO = "SAM_AMMO",
    SAM_DAMAGE = "SAM_DAMAGE",
    EWR_POSITION = "EWR_POSITION",
    THREAT_TRACK = "THREAT_TRACK",
    DEFCON = "DEFCON",
    TACTICAL_MODE = "TACTICAL_MODE",
    NETWORK_LINKS = "NETWORK_LINKS"
}

-- ============================================
-- 陣営情報フィルタ作成
-- ============================================
function IADS_COALITION.new()
    local self = setmetatable({}, IADS_COALITION)

    -- 陣営別IADSネットワーク参照
    self.coalitionNetworks = {
        [IADS_COALITION.SIDE.RED] = nil,
        [IADS_COALITION.SIDE.BLUE] = nil
    }

    -- プレイヤー権限マッピング
    self.playerPermissions = {}

    -- デフォルトアクセス権限
    self.defaultAccess = {
        [IADS_COALITION.SIDE.NEUTRAL] = IADS_COALITION.ACCESS_LEVEL.NONE,
        [IADS_COALITION.SIDE.RED] = IADS_COALITION.ACCESS_LEVEL.STANDARD,
        [IADS_COALITION.SIDE.BLUE] = IADS_COALITION.ACCESS_LEVEL.STANDARD
    }

    -- 情報タイプごとの必要アクセスレベル
    self.requiredAccess = {
        [IADS_COALITION.INFO_TYPE.SAM_POSITION] = {
            own = IADS_COALITION.ACCESS_LEVEL.BASIC,
            enemy = IADS_COALITION.ACCESS_LEVEL.ELEVATED
        },
        [IADS_COALITION.INFO_TYPE.SAM_STATE] = {
            own = IADS_COALITION.ACCESS_LEVEL.BASIC,
            enemy = IADS_COALITION.ACCESS_LEVEL.FULL
        },
        [IADS_COALITION.INFO_TYPE.SAM_AMMO] = {
            own = IADS_COALITION.ACCESS_LEVEL.STANDARD,
            enemy = IADS_COALITION.ACCESS_LEVEL.ADMIN
        },
        [IADS_COALITION.INFO_TYPE.SAM_DAMAGE] = {
            own = IADS_COALITION.ACCESS_LEVEL.STANDARD,
            enemy = IADS_COALITION.ACCESS_LEVEL.FULL
        },
        [IADS_COALITION.INFO_TYPE.EWR_POSITION] = {
            own = IADS_COALITION.ACCESS_LEVEL.BASIC,
            enemy = IADS_COALITION.ACCESS_LEVEL.ELEVATED
        },
        [IADS_COALITION.INFO_TYPE.THREAT_TRACK] = {
            own = IADS_COALITION.ACCESS_LEVEL.BASIC,
            enemy = IADS_COALITION.ACCESS_LEVEL.BASIC  -- 相互に検出可能
        },
        [IADS_COALITION.INFO_TYPE.DEFCON] = {
            own = IADS_COALITION.ACCESS_LEVEL.STANDARD,
            enemy = IADS_COALITION.ACCESS_LEVEL.ADMIN
        },
        [IADS_COALITION.INFO_TYPE.TACTICAL_MODE] = {
            own = IADS_COALITION.ACCESS_LEVEL.STANDARD,
            enemy = IADS_COALITION.ACCESS_LEVEL.ADMIN
        },
        [IADS_COALITION.INFO_TYPE.NETWORK_LINKS] = {
            own = IADS_COALITION.ACCESS_LEVEL.ELEVATED,
            enemy = IADS_COALITION.ACCESS_LEVEL.ADMIN
        }
    }

    -- ゲームマスター設定
    self.gameMasterEnabled = false
    self.gameMasterPlayers = {}

    -- 観戦者設定
    self.spectatorAccess = IADS_COALITION.ACCESS_LEVEL.FULL

    return self
end

-- ============================================
-- 初期化
-- ============================================
function IADS_COALITION:init(options)
    options = options or {}

    -- 陣営別ネットワークを設定
    if options.redNetwork then
        self.coalitionNetworks[IADS_COALITION.SIDE.RED] = options.redNetwork
    end
    if options.blueNetwork then
        self.coalitionNetworks[IADS_COALITION.SIDE.BLUE] = options.blueNetwork
    end

    -- ゲームマスター設定
    if options.gameMasterEnabled then
        self.gameMasterEnabled = true
    end

    -- 観戦者アクセス設定
    if options.spectatorAccess then
        self.spectatorAccess = options.spectatorAccess
    end

    SAM_UTILS.debug("[Coalition] System initialized")
    return self
end

-- ============================================
-- プレイヤーの陣営を取得
-- ============================================
function IADS_COALITION:getPlayerCoalition(playerId)
    if not playerId then return IADS_COALITION.SIDE.NEUTRAL end

    -- DCS APIを使用してプレイヤーの陣営を取得
    if net and net.get_slot then
        local slotInfo = net.get_slot(playerId)
        if slotInfo then
            return slotInfo.side or IADS_COALITION.SIDE.NEUTRAL
        end
    end

    -- 代替: ユニットから取得
    if net and net.get_player_info then
        local playerInfo = net.get_player_info(playerId)
        if playerInfo and playerInfo.side then
            return playerInfo.side
        end
    end

    return IADS_COALITION.SIDE.NEUTRAL
end

-- ============================================
-- プレイヤーのアクセスレベルを取得
-- ============================================
function IADS_COALITION:getPlayerAccessLevel(playerId)
    -- 個別権限が設定されている場合
    if self.playerPermissions[playerId] then
        return self.playerPermissions[playerId]
    end

    -- ゲームマスターチェック
    if self.gameMasterEnabled and self.gameMasterPlayers[playerId] then
        return IADS_COALITION.ACCESS_LEVEL.ADMIN
    end

    -- 観戦者チェック
    if self:isSpectator(playerId) then
        return self.spectatorAccess
    end

    -- 陣営別デフォルト
    local playerCoalition = self:getPlayerCoalition(playerId)
    return self.defaultAccess[playerCoalition] or IADS_COALITION.ACCESS_LEVEL.NONE
end

-- ============================================
-- 観戦者かどうか
-- ============================================
function IADS_COALITION:isSpectator(playerId)
    if net and net.get_slot then
        local slotInfo = net.get_slot(playerId)
        if slotInfo then
            -- 観戦者スロットまたは未割り当て
            return slotInfo.side == nil or slotInfo.side == 0
        end
    end
    return false
end

-- ============================================
-- 情報アクセス権限チェック
-- ============================================
function IADS_COALITION:canAccess(playerId, infoType, targetCoalition)
    local playerAccess = self:getPlayerAccessLevel(playerId)
    local playerCoalition = self:getPlayerCoalition(playerId)

    local requirements = self.requiredAccess[infoType]
    if not requirements then
        return false
    end

    -- 管理者は全てアクセス可能
    if playerAccess >= IADS_COALITION.ACCESS_LEVEL.ADMIN then
        return true
    end

    -- 自軍か敵軍か判定
    local isOwn = (playerCoalition == targetCoalition)

    if isOwn then
        return playerAccess >= requirements.own
    else
        return playerAccess >= requirements.enemy
    end
end

-- ============================================
-- プレイヤー権限を設定
-- ============================================
function IADS_COALITION:setPlayerPermission(playerId, accessLevel)
    self.playerPermissions[playerId] = accessLevel
    SAM_UTILS.debug("[Coalition] Player " .. playerId .. " access set to " .. accessLevel)
end

-- ============================================
-- ゲームマスターを追加
-- ============================================
function IADS_COALITION:addGameMaster(playerId)
    self.gameMasterPlayers[playerId] = true
    SAM_UTILS.debug("[Coalition] Player " .. playerId .. " added as Game Master")
end

-- ============================================
-- ゲームマスターを削除
-- ============================================
function IADS_COALITION:removeGameMaster(playerId)
    self.gameMasterPlayers[playerId] = nil
end

-- ============================================
-- フィルタリングされたSAM情報を取得
-- ============================================
function IADS_COALITION:getFilteredSamInfo(playerId, targetNetwork)
    if not targetNetwork then return {} end

    local playerCoalition = self:getPlayerCoalition(playerId)
    local networkCoalition = self:getNetworkCoalition(targetNetwork)
    local filteredSams = {}

    for samName, samSite in pairs(targetNetwork.samSites or {}) do
        local samInfo = {}
        local include = false

        -- 位置情報
        if self:canAccess(playerId, IADS_COALITION.INFO_TYPE.SAM_POSITION, networkCoalition) then
            samInfo.position = samSite.position
            samInfo.name = samName
            include = true
        end

        -- 状態情報
        if self:canAccess(playerId, IADS_COALITION.INFO_TYPE.SAM_STATE, networkCoalition) then
            samInfo.state = samSite.state
        end

        -- 弾薬情報
        if self:canAccess(playerId, IADS_COALITION.INFO_TYPE.SAM_AMMO, networkCoalition) then
            if IADS_SYSTEMS and IADS_SYSTEMS.ammo then
                local ammoStatus = IADS_SYSTEMS.ammo:getGroupStatus(samName)
                if ammoStatus then
                    samInfo.ammo = ammoStatus.ammoPercent
                end
            end
        end

        -- 損傷情報
        if self:canAccess(playerId, IADS_COALITION.INFO_TYPE.SAM_DAMAGE, networkCoalition) then
            if IADS_SYSTEMS and IADS_SYSTEMS.maintenance then
                local maintStatus = IADS_SYSTEMS.maintenance.siteStatus[samName]
                if maintStatus then
                    samInfo.health = maintStatus.health
                end
            end
        end

        if include then
            filteredSams[samName] = samInfo
        end
    end

    return filteredSams
end

-- ============================================
-- フィルタリングされた脅威情報を取得
-- ============================================
function IADS_COALITION:getFilteredThreats(playerId, targetNetwork)
    if not targetNetwork then return {} end

    local networkCoalition = self:getNetworkCoalition(targetNetwork)
    local filteredThreats = {}

    if not self:canAccess(playerId, IADS_COALITION.INFO_TYPE.THREAT_TRACK, networkCoalition) then
        return {}
    end

    for threatId, threat in pairs(targetNetwork.threats or {}) do
        filteredThreats[threatId] = {
            position = threat.position,
            type = threat.type,
            level = threat.level,
            heading = threat.heading
        }
    end

    return filteredThreats
end

-- ============================================
-- ネットワークの陣営を取得
-- ============================================
function IADS_COALITION:getNetworkCoalition(network)
    for coalition, net in pairs(self.coalitionNetworks) do
        if net == network then
            return coalition
        end
    end
    return IADS_COALITION.SIDE.NEUTRAL
end

-- ============================================
-- プレイヤー向けF10マーカーをフィルタリング
-- ============================================
function IADS_COALITION:createFilteredMarkers(playerId, f10MapSystem)
    if not f10MapSystem then return end

    local playerCoalition = self:getPlayerCoalition(playerId)
    local playerAccess = self:getPlayerAccessLevel(playerId)

    -- 自軍ネットワーク
    local ownNetwork = self.coalitionNetworks[playerCoalition]
    if ownNetwork then
        local samInfo = self:getFilteredSamInfo(playerId, ownNetwork)
        for samName, info in pairs(samInfo) do
            if info.position then
                local markerType = info.state == "GREEN" and "SAM_ACTIVE" or "SAM_DARK"
                local text = samName
                if info.ammo then
                    text = text .. string.format("\nAmmo: %d%%", info.ammo)
                end
                if info.health and info.health < 100 then
                    text = text .. string.format("\nHP: %d%%", info.health)
                end
                f10MapSystem:updateMarker("SAM_" .. samName, markerType, info.position, text)
            end
        end
    end

    -- 敵軍ネットワーク（管理者のみ）
    if playerAccess >= IADS_COALITION.ACCESS_LEVEL.ELEVATED then
        for coalition, network in pairs(self.coalitionNetworks) do
            if coalition ~= playerCoalition and network then
                local samInfo = self:getFilteredSamInfo(playerId, network)
                for samName, info in pairs(samInfo) do
                    if info.position then
                        f10MapSystem:updateMarker("ENEMY_SAM_" .. samName,
                            "THREAT", info.position, "Enemy SAM: " .. samName)
                    end
                end
            end
        end
    end
end

-- ============================================
-- 陣営別ラジオメニュー作成
-- ============================================
function IADS_COALITION:createCoalitionRadioMenus(coalitionSide)
    local network = self.coalitionNetworks[coalitionSide]
    if not network then return end

    -- 陣営名
    local coalitionName = coalitionSide == IADS_COALITION.SIDE.RED and "Red" or "Blue"

    -- メインメニュー
    local mainMenu = missionCommands.addSubMenuForCoalition(
        coalitionSide, coalitionName .. " IADS Control")

    -- ステータス表示
    local statusMenu = missionCommands.addSubMenuForCoalition(
        coalitionSide, "Status", mainMenu)

    missionCommands.addCommandForCoalition(
        coalitionSide, "Show IADS Status", statusMenu,
        function()
            network:printStatus()
        end)

    -- SAM制御
    local samMenu = missionCommands.addSubMenuForCoalition(
        coalitionSide, "SAM Control", mainMenu)

    missionCommands.addCommandForCoalition(
        coalitionSide, "Activate All SAMs", samMenu,
        function()
            network:activateAllSams()
            SAM_UTILS.info("[" .. coalitionName .. "] All SAMs activated", 10)
        end)

    missionCommands.addCommandForCoalition(
        coalitionSide, "Deactivate All SAMs", samMenu,
        function()
            for samName, _ in pairs(network.samSites) do
                network:setSamState(samName, "DARK")
            end
            SAM_UTILS.info("[" .. coalitionName .. "] All SAMs deactivated", 10)
        end)

    SAM_UTILS.debug("[Coalition] Radio menus created for " .. coalitionName)
end

-- ============================================
-- 陣営別メッセージ送信
-- ============================================
function IADS_COALITION:sendCoalitionMessage(coalitionSide, message, duration)
    duration = duration or 10

    if coalitionSide == IADS_COALITION.SIDE.ALL then
        trigger.action.outText(message, duration)
    elseif coalitionSide == IADS_COALITION.SIDE.RED then
        trigger.action.outTextForCoalition(coalition.side.RED, message, duration)
    elseif coalitionSide == IADS_COALITION.SIDE.BLUE then
        trigger.action.outTextForCoalition(coalition.side.BLUE, message, duration)
    end
end

-- ============================================
-- ステータス取得
-- ============================================
function IADS_COALITION:getStatus()
    local status = {
        networksConfigured = {},
        gameMasterEnabled = self.gameMasterEnabled,
        gameMasterCount = 0,
        playerPermissions = {}
    }

    for coalition, network in pairs(self.coalitionNetworks) do
        if network then
            local coalitionName
            if coalition == IADS_COALITION.SIDE.RED then
                coalitionName = "RED"
            elseif coalition == IADS_COALITION.SIDE.BLUE then
                coalitionName = "BLUE"
            else
                coalitionName = "NEUTRAL"
            end
            table.insert(status.networksConfigured, coalitionName)
        end
    end

    for _ in pairs(self.gameMasterPlayers) do
        status.gameMasterCount = status.gameMasterCount + 1
    end

    return status
end

-- ============================================
-- ステータス表示
-- ============================================
function IADS_COALITION:printStatus()
    local status = self:getStatus()

    local msg = "[Coalition Filter Status]\n"
    msg = msg .. "Networks: " .. table.concat(status.networksConfigured, ", ") .. "\n"
    msg = msg .. string.format("Game Master: %s (Count: %d)\n",
        status.gameMasterEnabled and "Enabled" or "Disabled",
        status.gameMasterCount)

    SAM_UTILS.info(msg, 15)
end

return IADS_COALITION
