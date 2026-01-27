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
DCS_SAM_VERSION = "2.0.0"
DCS_SAM_AUTHOR = "DCS Mission Creation Scripts"

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
-- 情報出力
-- ============================================
SAM_UTILS = SAM_UTILS or {}
if SAM_UTILS.debug then
    SAM_UTILS.debug("[Main] DCS SAM System v" .. DCS_SAM_VERSION .. " loaded")
end
