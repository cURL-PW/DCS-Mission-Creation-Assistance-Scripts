--[[
    DCS SAM & IADS System - Main Entry Point
    SAMシステムと統合防空システムネットワークのメインエントリポイント

    必要ライブラリ: MIST 4.3.74以上

    使用方法:
    1. MISTをロードする
    2. このファイルをロードする
    3. 必要に応じて初期化関数を呼び出す

    基本的な使用例:
    --------------------------
    -- SEADシステムのみ使用（従来の動作）
    dofile("core/config.lua")
    dofile("core/utils.lua")
    dofile("core/sead.lua")

    SEAD_SYSTEM.init({debug = true})
    --------------------------

    IADSネットワーク使用例:
    --------------------------
    dofile("core/config.lua")
    dofile("core/utils.lua")
    dofile("core/sead.lua")
    dofile("iads/network.lua")
    dofile("iads/sector.lua")
    dofile("iads/threat.lua")

    -- ネットワーク作成
    local myIADS = IADS_NETWORK.new("Red IADS")
    myIADS:init()

    -- SAMサイトを追加
    myIADS:addSamSite(Group.getByName("SA-10_Battery_1"))
    myIADS:addSamSite(Group.getByName("SA-6_Battery_1"))

    -- EWRを追加
    myIADS:addEWR(Group.getByName("EWR_1"))

    -- リンクを設定
    myIADS:linkSamToEWR("SA-10_Battery_1", "EWR_1")
    myIADS:linkSamToSam("SA-10_Battery_1", "SA-6_Battery_1")

    -- SEADシステムと連携
    SEAD_SYSTEM.init({
        debug = true,
        iadsNetwork = myIADS
    })

    -- 全SAMをアクティブ化
    myIADS:activateAllSams()
    --------------------------
]]

-- ============================================
-- バージョン情報
-- ============================================
DCS_SAM_VERSION = "2.4.0"
DCS_SAM_AUTHOR = "DCS Mission Creation Scripts"

-- ============================================
-- 統合システムインスタンス格納
-- ============================================
IADS_SYSTEMS = {
    networks = {},       -- IADSネットワーク
    ammo = nil,          -- 弾薬管理システム
    emcon = nil,         -- EMCONシステム
    logger = nil,        -- ロガー
    pointDefense = nil,  -- ポイントディフェンス (Phase 2)
    datalink = nil,      -- データリンク (Phase 2)
    predictor = nil,     -- 航路予測 (Phase 2)
    decoy = nil,         -- デコイシステム (Phase 3)
    antiJam = nil,       -- ジャマー対策 (Phase 3)
    maintenance = nil,   -- 修復/再配置 (Phase 3)
    commander = nil,     -- AIコマンダー (Phase 4)
    f10Map = nil         -- F10マップ連携 (Phase 4)
}

-- ============================================
-- 簡易初期化関数
-- ============================================

--[[
    SEADシステムのみを初期化
    @param options テーブル
        - debug: デバッグモード (boolean)
    @return SEAD_SYSTEM
]]
function initSEAD(options)
    options = options or {}
    return SEAD_SYSTEM.init(options)
end

--[[
    IADSネットワークを作成・初期化
    @param name ネットワーク名
    @param options テーブル
        - debug: デバッグモード (boolean)
        - updateInterval: 更新間隔(秒)
    @return IADS_NETWORK インスタンス
]]
function createIADS(name, options)
    options = options or {}

    if options.debug then
        SAM_UTILS.DEBUG = true
    end

    local network = IADS_NETWORK.new(name)
    network:init(options)

    return network
end

--[[
    グループ名のパターンでSAMサイトを自動追加
    @param iads IADSネットワークインスタンス
    @param pattern グループ名のパターン（部分一致）
    @param coalition 所属陣営 (1=red, 2=blue, nil=both)
]]
function autoAddSamSites(iads, pattern, coalition)
    if not iads then return 0 end

    local count = 0

    -- MISTのデータベースを使用
    if mist and mist.DBs and mist.DBs.groupsByName then
        for groupName, groupData in pairs(mist.DBs.groupsByName) do
            if string.find(groupName, pattern) then
                local group = Group.getByName(groupName)
                if group then
                    local groupCoalition = group:getCoalition()
                    if coalition == nil or groupCoalition == coalition then
                        iads:addSamSite(group)
                        count = count + 1
                    end
                end
            end
        end
    end

    SAM_UTILS.debug("[Main] Auto-added " .. count .. " SAM sites matching '" .. pattern .. "'")
    return count
end

--[[
    グループ名のパターンでEWRを自動追加
    @param iads IADSネットワークインスタンス
    @param pattern グループ名のパターン（部分一致）
    @param coalition 所属陣営 (1=red, 2=blue, nil=both)
]]
function autoAddEWRs(iads, pattern, coalition)
    if not iads then return 0 end

    local count = 0

    if mist and mist.DBs and mist.DBs.groupsByName then
        for groupName, groupData in pairs(mist.DBs.groupsByName) do
            if string.find(groupName, pattern) then
                local group = Group.getByName(groupName)
                if group then
                    local groupCoalition = group:getCoalition()
                    if coalition == nil or groupCoalition == coalition then
                        iads:addEWR(group)
                        count = count + 1
                    end
                end
            end
        end
    end

    SAM_UTILS.debug("[Main] Auto-added " .. count .. " EWRs matching '" .. pattern .. "'")
    return count
end

--[[
    範囲内のSAMとEWRを自動リンク
    @param iads IADSネットワークインスタンス
    @param maxDistance 最大リンク距離（メートル）
]]
function autoLinkByDistance(iads, maxDistance)
    if not iads then return end

    maxDistance = maxDistance or 150000  -- デフォルト150km

    -- SAM-EWR リンク
    for samName, samSite in pairs(iads.samSites) do
        for ewrName, ewr in pairs(iads.ewrSites) do
            if samSite.position and ewr.position then
                local distance = SAM_UTILS.getDistance2D(samSite.position, ewr.position)
                if distance and distance <= maxDistance then
                    iads:linkSamToEWR(samName, ewrName)
                end
            end
        end
    end

    -- SAM-SAM リンク
    local samNames = {}
    for samName, _ in pairs(iads.samSites) do
        table.insert(samNames, samName)
    end

    for i = 1, #samNames do
        for j = i + 1, #samNames do
            local sam1 = iads.samSites[samNames[i]]
            local sam2 = iads.samSites[samNames[j]]
            if sam1.position and sam2.position then
                local distance = SAM_UTILS.getDistance2D(sam1.position, sam2.position)
                if distance and distance <= maxDistance then
                    iads:linkSamToSam(samNames[i], samNames[j])
                end
            end
        end
    end

    SAM_UTILS.debug("[Main] Auto-linking completed (max distance: " .. maxDistance .. "m)")
end

--[[
    セクターを作成してSAMを自動割り当て
    @param iads IADSネットワークインスタンス
    @param sectorId セクターID
    @param center 中心座標 {x, z}
    @param radius 半径（メートル）
    @return IADS_SECTOR インスタンス
]]
function createSectorWithSams(iads, sectorId, center, radius)
    if not iads then return nil end

    local sector = IADS_SECTOR.new(sectorId, IADS_SECTOR.TYPE.POINT, {
        center = center,
        radius = radius
    })

    -- セクター内のSAMを追加
    for samName, samSite in pairs(iads.samSites) do
        if samSite.position and sector:containsPosition(samSite.position) then
            sector:addSamSite(samSite)
        end
    end

    iads.sectors[sectorId] = sector
    SAM_UTILS.debug("[Main] Sector '" .. sectorId .. "' created with SAMs")

    return sector
end

-- ============================================
-- Phase 1: 弾薬管理システム
-- ============================================

--[[
    弾薬管理システムを作成・初期化
    @param options テーブル
        - reloadEnabled: 再装填シミュレーション有効化
        - reloadTime: 再装填時間（秒）
        - autoGoGreen: 弾切れ時自動ダーク化
        - iadsNetwork: IADSネットワーク参照
    @return SAM_AMMO インスタンス
]]
function createAmmoSystem(options)
    options = options or {}

    local ammo = SAM_AMMO.new()
    ammo:init(options)

    IADS_SYSTEMS.ammo = ammo

    SAM_UTILS.debug("[Main] Ammo system created")
    return ammo
end

--[[
    IADSネットワーク内の全SAMランチャーを弾薬管理に登録
    @param iads IADSネットワーク
    @param ammoSystem 弾薬管理システム（nilならグローバル使用）
    @return 登録されたランチャー数
]]
function registerAllLaunchers(iads, ammoSystem)
    ammoSystem = ammoSystem or IADS_SYSTEMS.ammo
    if not iads or not ammoSystem then return 0 end

    local count = 0
    for groupName, samSite in pairs(iads.samSites) do
        count = count + ammoSystem:registerGroup(samSite.group)
    end

    SAM_UTILS.debug("[Main] Registered " .. count .. " launchers to ammo system")
    return count
end

-- ============================================
-- Phase 1: EMCONシステム
-- ============================================

--[[
    EMCONシステムを作成・初期化
    @param options テーブル
        - level: 初期EMCONレベル
        - mode: 運用モード
        - iadsNetwork: IADSネットワーク参照
        - blinkProfile: 点滅プロファイル
    @return SAM_EMCON インスタンス
]]
function createEmconSystem(options)
    options = options or {}

    local emcon = SAM_EMCON.new()
    emcon:init(options)

    IADS_SYSTEMS.emcon = emcon

    SAM_UTILS.debug("[Main] EMCON system created")
    return emcon
end

--[[
    IADSネットワーク内の全SAMをEMCONに登録
    @param iads IADSネットワーク
    @param emconSystem EMCONシステム（nilならグローバル使用）
    @return 登録されたSAM数
]]
function registerAllSamsToEmcon(iads, emconSystem)
    emconSystem = emconSystem or IADS_SYSTEMS.emcon
    if not iads or not emconSystem then return 0 end

    local count = 0
    for groupName, _ in pairs(iads.samSites) do
        emconSystem:registerSam(groupName)
        count = count + 1
    end

    SAM_UTILS.debug("[Main] Registered " .. count .. " SAMs to EMCON system")
    return count
end

-- ============================================
-- Phase 1: ロガーシステム
-- ============================================

--[[
    ロガーシステムを作成・初期化
    @param options テーブル
        - minLogLevel: 最小ログレベル
        - maxLogEntries: 最大ログ保持数
        - iadsNetwork: IADSネットワーク参照
    @return SAM_LOGGER インスタンス
]]
function createLoggerSystem(options)
    options = options or {}

    local logger = SAM_LOGGER.new()
    logger:init(options)

    IADS_SYSTEMS.logger = logger

    SAM_UTILS.debug("[Main] Logger system created")
    return logger
end

-- ============================================
-- 統合セットアップ
-- ============================================

--[[
    全システムを一括でセットアップ
    @param name IADSネットワーク名
    @param options テーブル
        - debug: デバッグモード
        - samPattern: SAMグループ名パターン
        - ewrPattern: EWRグループ名パターン
        - coalition: 陣営フィルタ
        - linkDistance: 自動リンク距離
        - emconLevel: 初期EMCONレベル
        - emconMode: EMCON運用モード
        - reloadEnabled: 再装填シミュレーション
    @return テーブル {iads, ammo, emcon, logger, sead}
]]
function setupFullIADS(name, options)
    options = options or {}

    if options.debug then
        SAM_UTILS.DEBUG = true
    end

    SAM_UTILS.debug("[Main] Setting up full IADS: " .. (name or "default"))

    -- 1. IADSネットワーク作成
    local iads = IADS_NETWORK.new(name)
    iads:init({updateInterval = options.updateInterval or 5})
    IADS_SYSTEMS.networks[name] = iads

    -- 2. SAMとEWRを自動追加
    if options.samPattern then
        autoAddSamSites(iads, options.samPattern, options.coalition)
    end
    if options.ewrPattern then
        autoAddEWRs(iads, options.ewrPattern, options.coalition)
    end

    -- 3. 自動リンク
    if options.linkDistance then
        autoLinkByDistance(iads, options.linkDistance)
    end

    -- 4. 弾薬管理システム
    local ammo = createAmmoSystem({
        iadsNetwork = iads,
        reloadEnabled = options.reloadEnabled or false,
        reloadTime = options.reloadTime or 300
    })
    registerAllLaunchers(iads, ammo)

    -- 5. EMCONシステム
    local emcon = createEmconSystem({
        iadsNetwork = iads,
        level = options.emconLevel or SAM_EMCON.LEVEL.DELTA,
        mode = options.emconMode or SAM_EMCON.MODE.STATIC
    })
    registerAllSamsToEmcon(iads, emcon)

    -- 6. ロガー
    local logger = createLoggerSystem({
        iadsNetwork = iads
    })

    -- 7. SEADシステム連携
    SEAD_SYSTEM.init({
        debug = options.debug,
        iadsNetwork = iads
    })

    SAM_UTILS.debug("[Main] Full IADS setup completed")

    return {
        iads = iads,
        ammo = ammo,
        emcon = emcon,
        logger = logger,
        sead = SEAD_SYSTEM
    }
end

--[[
    統合ステータス表示
    表示内容: IADS、弾薬、EMCON、統計
]]
function printFullStatus()
    -- IADSステータス
    for name, iads in pairs(IADS_SYSTEMS.networks) do
        iads:printStatus()
    end

    -- 弾薬ステータス
    if IADS_SYSTEMS.ammo then
        IADS_SYSTEMS.ammo:printStatus()
    end

    -- EMCONステータス
    if IADS_SYSTEMS.emcon then
        IADS_SYSTEMS.emcon:printStatus()
    end

    -- 統計
    if IADS_SYSTEMS.logger then
        IADS_SYSTEMS.logger:printStatistics()
    end
end

--[[
    ミッションレポート生成・表示
]]
function printMissionReport()
    if IADS_SYSTEMS.logger then
        IADS_SYSTEMS.logger:printReport()
    else
        SAM_UTILS.info("[Report] Logger not initialized")
    end
end

-- ============================================
-- Phase 2: ポイントディフェンス
-- ============================================

--[[
    ポイントディフェンスシステムを作成・初期化
    @param iadsNetwork IADSネットワーク参照
    @param options テーブル
        - autoActivate: 自動アクティブ化
        - layeredDefense: 多層防護有効
    @return IADS_POINT_DEFENSE インスタンス
]]
function createPointDefenseSystem(iadsNetwork, options)
    options = options or {}

    local pd = IADS_POINT_DEFENSE.new(iadsNetwork)
    pd:init(options)

    IADS_SYSTEMS.pointDefense = pd

    SAM_UTILS.debug("[Main] Point Defense system created")
    return pd
end

-- ============================================
-- Phase 2: データリンク
-- ============================================

--[[
    データリンクシステムを作成・初期化
    @param iadsNetwork IADSネットワーク参照
    @param options テーブル
        - silentLaunchEnabled: サイレントローンチ有効
        - linkDelay: リンク遅延（秒）
    @return IADS_DATALINK インスタンス
]]
function createDatalinkSystem(iadsNetwork, options)
    options = options or {}

    local dl = IADS_DATALINK.new(iadsNetwork)
    dl:init(options)

    IADS_SYSTEMS.datalink = dl

    SAM_UTILS.debug("[Main] DataLink system created")
    return dl
end

-- ============================================
-- Phase 2: 航路予測
-- ============================================

--[[
    航路予測システムを作成・初期化
    @param iadsNetwork IADSネットワーク参照
    @param options テーブル
        - predictionTime: 予測時間（秒）
        - autoPreActivate: 自動事前アクティブ化
    @return IADS_PREDICTOR インスタンス
]]
function createPredictorSystem(iadsNetwork, options)
    options = options or {}

    local pred = IADS_PREDICTOR.new(iadsNetwork)
    pred:init(options)

    IADS_SYSTEMS.predictor = pred

    SAM_UTILS.debug("[Main] Predictor system created")
    return pred
end

-- ============================================
-- Phase 3: デコイシステム
-- ============================================

--[[
    デコイシステムを作成・初期化
    @param iadsNetwork IADSネットワーク参照
    @param options テーブル
        - autoActivate: SAM停波時に自動送波
        - attractionRadius: ARM誘引半径（メートル）
        - attractionProbability: ARM誘引確率
    @return SAM_DECOY インスタンス
]]
function createDecoySystem(iadsNetwork, options)
    options = options or {}

    local decoy = SAM_DECOY.new(iadsNetwork)
    decoy:init(options)

    IADS_SYSTEMS.decoy = decoy

    SAM_UTILS.debug("[Main] Decoy system created")
    return decoy
end

--[[
    IADSネットワーク内の全SAMにデコイを自動配置
    @param iads IADSネットワーク
    @param decoySystem デコイシステム（nilならグローバル使用）
    @param options テーブル
        - count: SAMあたりのデコイ数
        - radius: 配置半径
    @return 配置されたデコイ数
]]
function deployDecoysAroundAllSams(iads, decoySystem, options)
    decoySystem = decoySystem or IADS_SYSTEMS.decoy
    if not iads or not decoySystem then return 0 end

    options = options or {}
    local count = options.count or 2
    local radius = options.radius or 3000

    local totalDeployed = 0
    for samGroupName, _ in pairs(iads.samSites) do
        local deployed = decoySystem:deployAroundSam(samGroupName, count, radius, options)
        totalDeployed = totalDeployed + #deployed
    end

    SAM_UTILS.debug("[Main] Deployed " .. totalDeployed .. " decoys around SAM sites")
    return totalDeployed
end

-- ============================================
-- Phase 3: ジャマー対策システム
-- ============================================

--[[
    ジャマー対策システムを作成・初期化
    @param iadsNetwork IADSネットワーク参照
    @param options テーブル
        - updateInterval: 更新間隔（秒）
    @return SAM_ANTI_JAM インスタンス
]]
function createAntiJamSystem(iadsNetwork, options)
    options = options or {}

    local antiJam = SAM_ANTI_JAM.new(iadsNetwork)
    antiJam:init(options)

    IADS_SYSTEMS.antiJam = antiJam

    SAM_UTILS.debug("[Main] Anti-Jam system created")
    return antiJam
end

-- ============================================
-- Phase 3: 修復/再配置システム
-- ============================================

--[[
    修復/再配置システムを作成・初期化
    @param iadsNetwork IADSネットワーク参照
    @param options テーブル
        - maxRepairTeams: 最大同時修復チーム数
        - shootAndScoot: シュート＆スクート設定
        - spareUnits: スペアユニット数
    @return SAM_MAINTENANCE インスタンス
]]
function createMaintenanceSystem(iadsNetwork, options)
    options = options or {}

    local maintenance = SAM_MAINTENANCE.new(iadsNetwork)
    maintenance:init(options)

    IADS_SYSTEMS.maintenance = maintenance

    SAM_UTILS.debug("[Main] Maintenance system created")
    return maintenance
end

-- ============================================
-- Phase 2統合: 高度なIADSセットアップ
-- ============================================

--[[
    Phase 1+2の全システムを一括でセットアップ
    @param name IADSネットワーク名
    @param options テーブル
        -- Phase 1 オプション
        - debug: デバッグモード
        - samPattern: SAMグループ名パターン
        - ewrPattern: EWRグループ名パターン
        - coalition: 陣営フィルタ
        - linkDistance: 自動リンク距離
        - emconLevel: 初期EMCONレベル
        - emconMode: EMCON運用モード
        - reloadEnabled: 再装填シミュレーション
        -- Phase 2 オプション
        - pointDefense: ポイントディフェンス有効 (boolean)
        - datalink: データリンク有効 (boolean)
        - predictor: 航路予測有効 (boolean)
        - silentLaunch: サイレントローンチ有効 (boolean)
        - hvTargets: 高価値目標のリスト (テーブル配列)
    @return テーブル {iads, ammo, emcon, logger, sead, pointDefense, datalink, predictor}
]]
function setupAdvancedIADS(name, options)
    options = options or {}

    -- Phase 1 セットアップを実行
    local systems = setupFullIADS(name, options)

    local iads = systems.iads

    -- Phase 2: ポイントディフェンス
    if options.pointDefense ~= false then
        local pd = createPointDefenseSystem(iads, {
            autoActivate = options.autoActivate ~= false,
            layeredDefense = options.layeredDefense ~= false
        })
        systems.pointDefense = pd

        -- 高価値目標を追加
        if options.hvTargets then
            for _, hvt in ipairs(options.hvTargets) do
                if hvt.type == "airbase" then
                    pd:addAirbase(hvt.name, hvt.options)
                elseif hvt.type == "zone" then
                    pd:addZoneTarget(hvt.name, hvt.options)
                elseif hvt.type == "unit" then
                    local unit = Unit.getByName(hvt.name)
                    if unit then
                        pd:addTarget(unit, hvt.options)
                    end
                end
            end
        end
    end

    -- Phase 2: データリンク
    if options.datalink ~= false then
        local dl = createDatalinkSystem(iads, {
            silentLaunchEnabled = options.silentLaunch ~= false
        })
        systems.datalink = dl
    end

    -- Phase 2: 航路予測
    if options.predictor ~= false then
        local pred = createPredictorSystem(iads, {
            autoPreActivate = true,
            predictionTime = options.predictionTime or 120
        })
        systems.predictor = pred
    end

    SAM_UTILS.debug("[Main] Advanced IADS setup completed")

    return systems
end

-- ============================================
-- Phase 3統合: カウンターメジャー付きIADSセットアップ
-- ============================================

--[[
    Phase 1+2+3の全システムを一括でセットアップ
    @param name IADSネットワーク名
    @param options テーブル
        -- Phase 1 オプション
        - debug: デバッグモード
        - samPattern: SAMグループ名パターン
        - ewrPattern: EWRグループ名パターン
        - coalition: 陣営フィルタ
        - linkDistance: 自動リンク距離
        - emconLevel: 初期EMCONレベル
        - emconMode: EMCON運用モード
        - reloadEnabled: 再装填シミュレーション
        -- Phase 2 オプション
        - pointDefense: ポイントディフェンス有効 (boolean)
        - datalink: データリンク有効 (boolean)
        - predictor: 航路予測有効 (boolean)
        - silentLaunch: サイレントローンチ有効 (boolean)
        - hvTargets: 高価値目標のリスト (テーブル配列)
        -- Phase 3 オプション
        - decoy: デコイシステム有効 (boolean)
        - antiJam: ジャマー対策有効 (boolean)
        - maintenance: 修復/再配置有効 (boolean)
        - shootAndScoot: シュート＆スクート設定
        - decoyCount: SAMあたりのデコイ数
        - decoyRadius: デコイ配置半径
    @return テーブル {iads, ammo, emcon, logger, sead, pointDefense, datalink, predictor, decoy, antiJam, maintenance}
]]
function setupFullCountermeasuresIADS(name, options)
    options = options or {}

    -- Phase 1+2 セットアップを実行
    local systems = setupAdvancedIADS(name, options)

    local iads = systems.iads

    -- Phase 3: デコイシステム
    if options.decoy ~= false then
        local decoy = createDecoySystem(iads, {
            autoActivate = options.decoyAutoActivate ~= false,
            attractionRadius = options.decoyAttractionRadius or 5000,
            attractionProbability = options.decoyProbability or 0.7
        })
        systems.decoy = decoy

        -- 全SAMにデコイを配置
        deployDecoysAroundAllSams(iads, decoy, {
            count = options.decoyCount or 2,
            radius = options.decoyRadius or 3000
        })
    end

    -- Phase 3: ジャマー対策
    if options.antiJam ~= false then
        local antiJam = createAntiJamSystem(iads, {
            updateInterval = options.antiJamUpdateInterval or 3
        })
        systems.antiJam = antiJam
    end

    -- Phase 3: 修復/再配置
    if options.maintenance ~= false then
        local maintenance = createMaintenanceSystem(iads, {
            maxRepairTeams = options.maxRepairTeams or 3,
            shootAndScoot = options.shootAndScoot or {
                enabled = false,
                shotsBeforeMove = 2,
                moveDistance = 3000
            },
            spareUnits = options.spareUnits
        })
        systems.maintenance = maintenance
    end

    SAM_UTILS.debug("[Main] Full Countermeasures IADS setup completed")

    return systems
end

--[[
    全システムの詳細ステータスを表示
]]
function printAdvancedStatus()
    -- 基本ステータス
    printFullStatus()

    -- ポイントディフェンス
    if IADS_SYSTEMS.pointDefense then
        IADS_SYSTEMS.pointDefense:printStatus()
    end

    -- データリンク
    if IADS_SYSTEMS.datalink then
        IADS_SYSTEMS.datalink:printStatus()
    end

    -- 航路予測
    if IADS_SYSTEMS.predictor then
        IADS_SYSTEMS.predictor:printStatus()
    end

    -- デコイ
    if IADS_SYSTEMS.decoy then
        IADS_SYSTEMS.decoy:printStatus()
    end

    -- ジャマー対策
    if IADS_SYSTEMS.antiJam then
        IADS_SYSTEMS.antiJam:printStatus()
    end

    -- 修復/再配置
    if IADS_SYSTEMS.maintenance then
        IADS_SYSTEMS.maintenance:printStatus()
    end

    -- AIコマンダー
    if IADS_SYSTEMS.commander then
        IADS_SYSTEMS.commander:printStatus()
    end

    -- F10マップ
    if IADS_SYSTEMS.f10Map then
        IADS_SYSTEMS.f10Map:printStatus()
    end
end

-- ============================================
-- Phase 4: AIコマンダー
-- ============================================

--[[
    AIコマンダーを作成・初期化
    @param iadsNetwork IADSネットワーク参照
    @param options テーブル
        - tacticalMode: 戦術モード (CONSERVATIVE/BALANCED/AGGRESSIVE/AMBUSH)
        - defenseCondition: 初期防空態勢
        - updateInterval: 更新間隔（秒）
        - tactics: 戦術設定テーブル
    @return IADS_COMMANDER インスタンス
]]
function createCommanderSystem(iadsNetwork, options)
    options = options or {}

    local commander = IADS_COMMANDER.new(iadsNetwork)
    commander:init(options)

    IADS_SYSTEMS.commander = commander

    SAM_UTILS.debug("[Main] AI Commander system created")
    return commander
end

-- ============================================
-- Phase 4: F10マップ連携
-- ============================================

--[[
    F10マップ連携システムを作成・初期化
    @param iadsNetwork IADSネットワーク参照
    @param options テーブル
        - updateInterval: 更新間隔（秒）
        - displaySettings: 表示設定
    @return IADS_F10_MAP インスタンス
]]
function createF10MapSystem(iadsNetwork, options)
    options = options or {}

    local f10Map = IADS_F10_MAP.new(iadsNetwork)
    f10Map:init(options)

    IADS_SYSTEMS.f10Map = f10Map

    SAM_UTILS.debug("[Main] F10 Map system created")
    return f10Map
end

-- ============================================
-- Phase 4統合: 完全なIADSセットアップ
-- ============================================

--[[
    Phase 1+2+3+4の全システムを一括でセットアップ
    @param name IADSネットワーク名
    @param options テーブル
        -- Phase 1-3 オプション
        （setupFullCountermeasuresIADSと同じ）
        -- Phase 4 オプション
        - commander: AIコマンダー有効 (boolean)
        - f10Map: F10マップ連携有効 (boolean)
        - tacticalMode: 戦術モード
        - defenseCondition: 初期防空態勢
    @return テーブル（全システム）
]]
function setupCompleteIADS(name, options)
    options = options or {}

    -- Phase 1+2+3 セットアップを実行
    local systems = setupFullCountermeasuresIADS(name, options)

    local iads = systems.iads

    -- Phase 4: AIコマンダー
    if options.commander ~= false then
        local commander = createCommanderSystem(iads, {
            tacticalMode = options.tacticalMode or IADS_COMMANDER.TACTICAL_MODE.BALANCED,
            defenseCondition = options.defenseCondition or IADS_COMMANDER.DEFENSE_CONDITION.ELEVATED,
            updateInterval = options.commanderUpdateInterval or 5,
            tactics = options.tactics
        })
        systems.commander = commander
    end

    -- Phase 4: F10マップ連携
    if options.f10Map ~= false then
        local f10Map = createF10MapSystem(iads, {
            updateInterval = options.f10MapUpdateInterval or 10,
            displaySettings = options.f10MapDisplaySettings
        })
        systems.f10Map = f10Map
    end

    SAM_UTILS.debug("[Main] Complete IADS setup finished")

    return systems
end

-- ============================================
-- 情報出力
-- ============================================
SAM_UTILS = SAM_UTILS or {}
if SAM_UTILS.debug then
    SAM_UTILS.debug("[Main] DCS SAM System v" .. DCS_SAM_VERSION .. " loaded")
end
