--[[
    DCS SEAD Simulation System
    SEADミサイル検知とレーダー停波シミュレーション

    依存: core/config.lua, core/utils.lua
    オプション依存: iads/network.lua (IADSネットワーク連携)
]]

SEAD_SYSTEM = {}

-- ============================================
-- 内部状態
-- ============================================
local suppressedGroups = {}  -- 現在停波中のグループを追跡
local iadsNetwork = nil      -- IADSネットワーク参照（連携用）

-- ============================================
-- 初期化
-- ============================================
function SEAD_SYSTEM.init(options)
    options = options or {}

    -- デバッグモード設定
    if options.debug ~= nil then
        SAM_UTILS.DEBUG = options.debug
    end

    -- IADSネットワーク連携
    if options.iadsNetwork then
        iadsNetwork = options.iadsNetwork
    end

    -- イベントハンドラ登録
    world.addEventHandler(SEAD_SYSTEM.eventHandler)

    SAM_UTILS.debug("[SEAD] System initialized")
    return SEAD_SYSTEM
end

-- ============================================
-- IADSネットワークとの連携設定
-- ============================================
function SEAD_SYSTEM.setIADSNetwork(network)
    iadsNetwork = network
end

-- ============================================
-- イベントハンドラ
-- ============================================
SEAD_SYSTEM.eventHandler = {}

function SEAD_SYSTEM.eventHandler:onEvent(event)
    -- 武器発射イベントのみ処理
    if event.id ~= world.event.S_EVENT_SHOT then
        return
    end

    local weapon = event.weapon
    if not weapon then return end

    local weaponTypeName = weapon:getTypeName()
    SAM_UTILS.debug("[SEAD] Weapon fired: " .. weaponTypeName)

    -- 対レーダーミサイルかどうか判定
    if not SAM_CONFIG.isARM(weaponTypeName) then
        return
    end

    -- ターゲットを取得
    local target = Weapon.getTarget(weapon)
    if not target then
        SAM_UTILS.debug("[SEAD] ARM fired but no target acquired")
        return
    end

    -- ターゲット情報を取得
    local targetInfo = SAM_UTILS.getUnitGroupInfo(target)
    if not targetInfo then
        SAM_UTILS.debug("[SEAD] Could not get target info")
        return
    end

    SAM_UTILS.debug("[SEAD] ARM targeting: " .. targetInfo.unitType)

    -- SAM設定を取得
    local samConfig = SAM_CONFIG.getTypeConfig(targetInfo.unitType)

    -- 停波処理を実行
    SEAD_SYSTEM.processSuppression(targetInfo, samConfig, weaponTypeName)
end

-- ============================================
-- 停波処理
-- ============================================
function SEAD_SYSTEM.processSuppression(targetInfo, samConfig, weaponTypeName)
    -- 確率判定
    local roll = SAM_UTILS.random(1, 100)
    if roll > samConfig.suppressionRate then
        SAM_UTILS.debug("[SEAD] Suppression chance failed: " .. roll .. " > " .. samConfig.suppressionRate)
        return
    end

    -- 既に停波中の場合はスキップ
    local groupKey = targetInfo.groupName
    if suppressedGroups[groupKey] then
        SAM_UTILS.debug("[SEAD] Group already suppressed: " .. groupKey)
        return
    end

    -- 遅延時間を計算
    local offDelay = SAM_UTILS.random(samConfig.minOffDelay, samConfig.maxOffDelay)
    local onDelay = SAM_UTILS.random(samConfig.minOnDelay, samConfig.maxOnDelay)
    local currentTime = SAM_UTILS.getTime()

    -- 停波情報を記録
    local suppressionInfo = {
        targetInfo = targetInfo,
        samConfig = samConfig,
        weapon = weaponTypeName,
        startTime = currentTime + offDelay,
        endTime = currentTime + offDelay + onDelay,
        suppressGroup = samConfig.suppressGroup
    }
    suppressedGroups[groupKey] = suppressionInfo

    SAM_UTILS.debug(string.format("[SEAD] Scheduling suppression - Off in %ds, On in %ds",
        offDelay, offDelay + onDelay))

    -- タイマースケジュール
    SAM_UTILS.scheduleFunction(SEAD_SYSTEM.startSuppression, suppressionInfo, suppressionInfo.startTime)
    SAM_UTILS.scheduleFunction(SEAD_SYSTEM.endSuppression, suppressionInfo, suppressionInfo.endTime)

    -- IADSネットワークに通知
    if iadsNetwork then
        iadsNetwork:onSamThreatened(targetInfo, weaponTypeName)
    end
end

-- ============================================
-- 停波開始
-- ============================================
function SEAD_SYSTEM.startSuppression(suppressionInfo)
    local targetInfo = suppressionInfo.targetInfo
    SAM_UTILS.debug("[SEAD] Starting suppression: " .. targetInfo.groupName)

    if suppressionInfo.suppressGroup then
        -- グループ全体を停波
        SAM_UTILS.setGroupAlarmState(targetInfo.group, SAM_UTILS.ALARM_STATE.GREEN)
    else
        -- ユニット単体を停波（実際にはグループのコントローラを使用）
        SAM_UTILS.setGroupAlarmState(targetInfo.group, SAM_UTILS.ALARM_STATE.GREEN)
    end

    -- IADSネットワークに通知
    if iadsNetwork then
        iadsNetwork:onSamSuppressed(targetInfo)
    end
end

-- ============================================
-- 停波終了（レーダー再起動）
-- ============================================
function SEAD_SYSTEM.endSuppression(suppressionInfo)
    local targetInfo = suppressionInfo.targetInfo
    local groupKey = targetInfo.groupName

    SAM_UTILS.debug("[SEAD] Ending suppression: " .. groupKey)

    if suppressionInfo.suppressGroup then
        -- グループ全体を再起動
        SAM_UTILS.setGroupAlarmState(targetInfo.group, SAM_UTILS.ALARM_STATE.RED)
    else
        -- ユニット単体を再起動
        SAM_UTILS.setGroupAlarmState(targetInfo.group, SAM_UTILS.ALARM_STATE.RED)
    end

    -- 停波記録を削除
    suppressedGroups[groupKey] = nil

    -- IADSネットワークに通知
    if iadsNetwork then
        iadsNetwork:onSamReactivated(targetInfo)
    end
end

-- ============================================
-- 現在停波中のグループを取得
-- ============================================
function SEAD_SYSTEM.getSuppressedGroups()
    return suppressedGroups
end

-- ============================================
-- 特定のグループが停波中かどうか確認
-- ============================================
function SEAD_SYSTEM.isGroupSuppressed(groupName)
    return suppressedGroups[groupName] ~= nil
end

-- ============================================
-- 手動で停波を開始
-- ============================================
function SEAD_SYSTEM.manualSuppress(group, duration)
    if not group then return false end

    local groupName = group:getName()
    if suppressedGroups[groupName] then
        return false  -- 既に停波中
    end

    duration = duration or 30
    local currentTime = SAM_UTILS.getTime()

    local suppressionInfo = {
        targetInfo = {
            group = group,
            groupName = groupName,
        },
        startTime = currentTime,
        endTime = currentTime + duration,
        suppressGroup = true,
        manual = true
    }
    suppressedGroups[groupName] = suppressionInfo

    -- 即座に停波
    SAM_UTILS.setGroupAlarmState(group, SAM_UTILS.ALARM_STATE.GREEN)

    -- 終了タイマーをスケジュール
    SAM_UTILS.scheduleFunction(SEAD_SYSTEM.endSuppression, suppressionInfo, suppressionInfo.endTime)

    return true
end

return SEAD_SYSTEM
