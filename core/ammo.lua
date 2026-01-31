--[[
    DCS SAM Ammunition Management System
    弾薬管理システム

    各SAMサイトの残弾数を追跡し、弾薬状況に応じた
    交戦優先度の調整を行う

    機能:
    - ランチャーごとの残弾追跡
    - 弾薬消費イベントの検知
    - 残弾に基づく交戦優先度調整
    - 弾薬切れSAMの自動ダーク化
    - 再装填シミュレーション（オプション）

    依存: core/utils.lua, core/config.lua
]]

SAM_AMMO = {}
SAM_AMMO.__index = SAM_AMMO

-- ============================================
-- 弾薬状態
-- ============================================
SAM_AMMO.STATUS = {
    FULL = "FULL",           -- 満弾
    HIGH = "HIGH",           -- 75%以上
    MEDIUM = "MEDIUM",       -- 50%以上
    LOW = "LOW",             -- 25%以上
    CRITICAL = "CRITICAL",   -- 25%未満
    EMPTY = "EMPTY"          -- 弾切れ
}

-- ============================================
-- SAMタイプごとのデフォルト弾薬数
-- ============================================
SAM_AMMO.DEFAULT_LOADOUT = {
    -- S-125 (SA-3)
    ["5p73 s-125 ln"] = 4,

    -- SA-2
    ["S_75M_Volhov"] = 1,

    -- SA-6 Kub
    ["Kub 2P25 ln"] = 3,

    -- SA-8 Osa
    ["Osa 9A33 ln"] = 6,

    -- SA-11 Buk
    ["SA-11 Buk LN 9A310M1"] = 4,

    -- SA-15 Tor
    ["Tor 9A331"] = 8,

    -- S-300PS
    ["S-300PS 5P85C ln"] = 4,
    ["S-300PS 5P85D ln"] = 4,

    -- Hawk
    ["Hawk ln"] = 3,

    -- Patriot
    ["Patriot ln"] = 4,

    -- Roland
    ["Roland ADS"] = 10,
}

-- ============================================
-- 弾薬管理システム作成
-- ============================================
function SAM_AMMO.new()
    local self = setmetatable({}, SAM_AMMO)

    self.launchers = {}           -- ランチャーごとの弾薬情報
    self.samSites = {}            -- SAMサイトごとの弾薬集計
    self.reloadEnabled = false    -- 再装填シミュレーション
    self.reloadTime = 300         -- 再装填時間（秒）
    self.autoGoGreen = true       -- 弾切れ時自動ダーク化
    self.lowAmmoThreshold = 0.25  -- 低弾薬警告閾値
    self.eventHandler = nil
    self.iadsNetwork = nil

    return self
end

-- ============================================
-- 初期化
-- ============================================
function SAM_AMMO:init(options)
    options = options or {}

    if options.reloadEnabled ~= nil then
        self.reloadEnabled = options.reloadEnabled
    end
    if options.reloadTime then
        self.reloadTime = options.reloadTime
    end
    if options.autoGoGreen ~= nil then
        self.autoGoGreen = options.autoGoGreen
    end
    if options.lowAmmoThreshold then
        self.lowAmmoThreshold = options.lowAmmoThreshold
    end
    if options.iadsNetwork then
        self.iadsNetwork = options.iadsNetwork
    end

    -- イベントハンドラ登録
    self:registerEventHandler()

    SAM_UTILS.debug("[Ammo] System initialized")
    return self
end

-- ============================================
-- IADSネットワーク連携
-- ============================================
function SAM_AMMO:setIADSNetwork(network)
    self.iadsNetwork = network
end

-- ============================================
-- ランチャーの登録
-- ============================================
function SAM_AMMO:registerLauncher(unit, customLoadout)
    if not unit or not unit:isExist() then return nil end

    local unitName = unit:getName()
    local unitType = unit:getTypeName()
    local group = unit:getGroup()
    local groupName = group and group:getName() or "unknown"

    -- 弾薬数を決定
    local maxAmmo = customLoadout or SAM_AMMO.DEFAULT_LOADOUT[unitType] or 4

    local launcherInfo = {
        unit = unit,
        unitName = unitName,
        unitType = unitType,
        groupName = groupName,
        maxAmmo = maxAmmo,
        currentAmmo = maxAmmo,
        totalFired = 0,
        isReloading = false,
        reloadCompleteTime = nil,
        lastFired = nil
    }

    self.launchers[unitName] = launcherInfo

    -- SAMサイト集計を更新
    self:updateSamSiteAmmo(groupName)

    SAM_UTILS.debug("[Ammo] Registered launcher: " .. unitName .. " (" .. maxAmmo .. " rounds)")
    return launcherInfo
end

-- ============================================
-- グループ内の全ランチャーを登録
-- ============================================
function SAM_AMMO:registerGroup(group)
    if not group then return 0 end

    local count = 0
    local units = group:getUnits()

    if units then
        for _, unit in ipairs(units) do
            local unitType = unit:getTypeName()
            -- ランチャータイプのみ登録
            if SAM_AMMO.DEFAULT_LOADOUT[unitType] then
                self:registerLauncher(unit)
                count = count + 1
            end
        end
    end

    return count
end

-- ============================================
-- SAMサイトの弾薬集計を更新
-- ============================================
function SAM_AMMO:updateSamSiteAmmo(groupName)
    local totalMax = 0
    local totalCurrent = 0
    local launcherCount = 0

    for _, launcher in pairs(self.launchers) do
        if launcher.groupName == groupName then
            totalMax = totalMax + launcher.maxAmmo
            totalCurrent = totalCurrent + launcher.currentAmmo
            launcherCount = launcherCount + 1
        end
    end

    if launcherCount > 0 then
        local percentage = totalCurrent / totalMax
        local status = self:calculateStatus(percentage)

        self.samSites[groupName] = {
            groupName = groupName,
            totalMax = totalMax,
            totalCurrent = totalCurrent,
            launcherCount = launcherCount,
            percentage = percentage,
            status = status
        }

        -- 弾切れ時の処理
        if status == SAM_AMMO.STATUS.EMPTY and self.autoGoGreen then
            self:onAmmoEmpty(groupName)
        elseif status == SAM_AMMO.STATUS.CRITICAL or status == SAM_AMMO.STATUS.LOW then
            self:onAmmoLow(groupName, status)
        end
    end
end

-- ============================================
-- 弾薬状態を計算
-- ============================================
function SAM_AMMO:calculateStatus(percentage)
    if percentage <= 0 then
        return SAM_AMMO.STATUS.EMPTY
    elseif percentage < 0.25 then
        return SAM_AMMO.STATUS.CRITICAL
    elseif percentage < 0.5 then
        return SAM_AMMO.STATUS.LOW
    elseif percentage < 0.75 then
        return SAM_AMMO.STATUS.MEDIUM
    elseif percentage < 1.0 then
        return SAM_AMMO.STATUS.HIGH
    else
        return SAM_AMMO.STATUS.FULL
    end
end

-- ============================================
-- イベントハンドラ登録
-- ============================================
function SAM_AMMO:registerEventHandler()
    local ammoSystem = self

    self.eventHandler = {}
    function self.eventHandler:onEvent(event)
        -- ミサイル発射イベント
        if event.id == world.event.S_EVENT_SHOT then
            ammoSystem:onWeaponFired(event)
        end
    end

    world.addEventHandler(self.eventHandler)
end

-- ============================================
-- 武器発射イベント処理
-- ============================================
function SAM_AMMO:onWeaponFired(event)
    local initiator = event.initiator
    if not initiator then return end

    local unitName = initiator:getName()
    local launcher = self.launchers[unitName]

    if launcher then
        -- 弾薬を消費
        launcher.currentAmmo = math.max(0, launcher.currentAmmo - 1)
        launcher.totalFired = launcher.totalFired + 1
        launcher.lastFired = SAM_UTILS.getTime()

        SAM_UTILS.debug(string.format("[Ammo] %s fired: %d/%d remaining",
            unitName, launcher.currentAmmo, launcher.maxAmmo))

        -- SAMサイト集計を更新
        self:updateSamSiteAmmo(launcher.groupName)

        -- 再装填開始（オプション）
        if launcher.currentAmmo == 0 and self.reloadEnabled then
            self:startReload(unitName)
        end
    end
end

-- ============================================
-- 弾薬切れ時の処理
-- ============================================
function SAM_AMMO:onAmmoEmpty(groupName)
    SAM_UTILS.debug("[Ammo] SAM site out of ammo: " .. groupName)

    -- IADSに通知してダーク化
    if self.iadsNetwork then
        self.iadsNetwork:deactivateSam(groupName)
        SAM_UTILS.info("[Ammo] " .. groupName .. " went dark (out of ammo)")
    end
end

-- ============================================
-- 低弾薬時の処理
-- ============================================
function SAM_AMMO:onAmmoLow(groupName, status)
    SAM_UTILS.debug("[Ammo] SAM site low on ammo: " .. groupName .. " (" .. status .. ")")

    -- IADSに通知（交戦優先度を下げる等の処理用）
    if self.iadsNetwork then
        local samSite = self.iadsNetwork.samSites[groupName]
        if samSite then
            -- 優先度を下げる（弾薬温存）
            samSite.ammoStatus = status
        end
    end
end

-- ============================================
-- 再装填開始
-- ============================================
function SAM_AMMO:startReload(unitName)
    local launcher = self.launchers[unitName]
    if not launcher or launcher.isReloading then return end

    launcher.isReloading = true
    launcher.reloadCompleteTime = SAM_UTILS.getTime() + self.reloadTime

    SAM_UTILS.debug("[Ammo] Starting reload: " .. unitName)

    -- 再装填完了をスケジュール
    local ammoSystem = self
    SAM_UTILS.scheduleFunction(function()
        ammoSystem:completeReload(unitName)
    end, nil, launcher.reloadCompleteTime)
end

-- ============================================
-- 再装填完了
-- ============================================
function SAM_AMMO:completeReload(unitName)
    local launcher = self.launchers[unitName]
    if not launcher then return end

    launcher.currentAmmo = launcher.maxAmmo
    launcher.isReloading = false
    launcher.reloadCompleteTime = nil

    SAM_UTILS.debug("[Ammo] Reload complete: " .. unitName)

    -- SAMサイト集計を更新
    self:updateSamSiteAmmo(launcher.groupName)

    -- IADSに通知
    if self.iadsNetwork then
        SAM_UTILS.info("[Ammo] " .. launcher.groupName .. " reloaded and ready")
    end
end

-- ============================================
-- 手動で弾薬を設定
-- ============================================
function SAM_AMMO:setAmmo(unitName, amount)
    local launcher = self.launchers[unitName]
    if not launcher then return false end

    launcher.currentAmmo = math.min(amount, launcher.maxAmmo)
    self:updateSamSiteAmmo(launcher.groupName)

    return true
end

-- ============================================
-- 手動で再装填（即時）
-- ============================================
function SAM_AMMO:reloadNow(unitName)
    local launcher = self.launchers[unitName]
    if not launcher then return false end

    launcher.currentAmmo = launcher.maxAmmo
    launcher.isReloading = false
    self:updateSamSiteAmmo(launcher.groupName)

    return true
end

-- ============================================
-- グループ全体を再装填
-- ============================================
function SAM_AMMO:reloadGroup(groupName)
    local count = 0
    for unitName, launcher in pairs(self.launchers) do
        if launcher.groupName == groupName then
            self:reloadNow(unitName)
            count = count + 1
        end
    end
    return count
end

-- ============================================
-- ランチャー情報を取得
-- ============================================
function SAM_AMMO:getLauncherInfo(unitName)
    return self.launchers[unitName]
end

-- ============================================
-- SAMサイト弾薬情報を取得
-- ============================================
function SAM_AMMO:getSamSiteAmmo(groupName)
    return self.samSites[groupName]
end

-- ============================================
-- 交戦可能かどうかを判定
-- ============================================
function SAM_AMMO:canEngage(groupName)
    local siteAmmo = self.samSites[groupName]
    if not siteAmmo then return true end  -- 追跡していない場合はOK

    return siteAmmo.status ~= SAM_AMMO.STATUS.EMPTY
end

-- ============================================
-- 優先度修正値を取得（弾薬に基づく）
-- ============================================
function SAM_AMMO:getPriorityModifier(groupName)
    local siteAmmo = self.samSites[groupName]
    if not siteAmmo then return 0 end

    -- 弾薬が少ないほど優先度を下げる（大きい値 = 低優先度）
    if siteAmmo.status == SAM_AMMO.STATUS.EMPTY then
        return 100  -- 交戦不可
    elseif siteAmmo.status == SAM_AMMO.STATUS.CRITICAL then
        return 3
    elseif siteAmmo.status == SAM_AMMO.STATUS.LOW then
        return 2
    elseif siteAmmo.status == SAM_AMMO.STATUS.MEDIUM then
        return 1
    else
        return 0
    end
end

-- ============================================
-- 全体ステータスを取得
-- ============================================
function SAM_AMMO:getStatus()
    local status = {
        totalLaunchers = 0,
        totalAmmo = 0,
        totalMaxAmmo = 0,
        launchersEmpty = 0,
        launchersLow = 0,
        launchersReloading = 0,
        sites = {}
    }

    for unitName, launcher in pairs(self.launchers) do
        status.totalLaunchers = status.totalLaunchers + 1
        status.totalAmmo = status.totalAmmo + launcher.currentAmmo
        status.totalMaxAmmo = status.totalMaxAmmo + launcher.maxAmmo

        if launcher.currentAmmo == 0 then
            status.launchersEmpty = status.launchersEmpty + 1
        elseif launcher.currentAmmo / launcher.maxAmmo < self.lowAmmoThreshold then
            status.launchersLow = status.launchersLow + 1
        end

        if launcher.isReloading then
            status.launchersReloading = status.launchersReloading + 1
        end
    end

    for groupName, siteAmmo in pairs(self.samSites) do
        table.insert(status.sites, {
            groupName = groupName,
            ammo = siteAmmo.totalCurrent .. "/" .. siteAmmo.totalMax,
            percentage = math.floor(siteAmmo.percentage * 100) .. "%",
            status = siteAmmo.status
        })
    end

    return status
end

-- ============================================
-- ステータス表示
-- ============================================
function SAM_AMMO:printStatus()
    local status = self:getStatus()

    local msg = "[Ammo Status]\n"
    msg = msg .. string.format("Launchers: %d | Ammo: %d/%d\n",
        status.totalLaunchers, status.totalAmmo, status.totalMaxAmmo)
    msg = msg .. string.format("Empty: %d | Low: %d | Reloading: %d\n",
        status.launchersEmpty, status.launchersLow, status.launchersReloading)

    for _, site in ipairs(status.sites) do
        msg = msg .. string.format("  %s: %s (%s)\n",
            site.groupName, site.ammo, site.status)
    end

    SAM_UTILS.info(msg, 20)
end

return SAM_AMMO
