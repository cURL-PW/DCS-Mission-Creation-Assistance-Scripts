--[[
    SAM List Utility
    SAMユニットの列挙ユーティリティ

    ミッション内のすべてのSAMユニットを検出し、
    リストとして返す

    依存: core/config.lua (オプション)
]]

-- SAMタイプのフォールバック定義（core/config.luaがない場合）
local SamTypes = SAM_CONFIG and SAM_CONFIG.getAllTypeNames() or {
    "1L13 EWR",
    "55G6 EWR",
    "p-19 s-125 sr",
    "Dog Ear radar",
    "SNR_75V",
    "snr s-125 tr",
    "Kub 1S91 str",
    "Osa 9A33 ln",
    "S-300PS 40B6M tr",
    "S-300PS 40B6MD sr",
    "S-300PS 64H6E sr",
    "SA-11 Buk SR 9S18M1",
    "SA-11 Buk LN 9A310M1",
    "Tor 9A331",
    "Hawk tr",
    "Hawk sr",
    "Patriot str",
    "Hawk cwar",
    "Roland Radar",
}

-- ============================================
-- ユーティリティ関数
-- ============================================

-- テーブル内の値の存在確認
local function tableContainsValue(tbl, val)
    if tbl == nil then return false end
    for _, v in pairs(tbl) do
        if v == val then return true end
    end
    return false
end

-- デバッグ出力
local function debugLog(message)
    local debug = SAM_UTILS and SAM_UTILS.DEBUG or false
    if debug then
        trigger.action.outText(message, 20)
    end
end

-- ============================================
-- SAMリスト取得関数
-- ============================================

--[[
    指定した陣営のSAMユニットリストを取得
    @param coalition 陣営 ("red", "blue", "all")
    @return SAMユニット情報のテーブル配列
]]
function getSamList(coalition)
    coalition = coalition or "red"
    local list = {}

    if not mist or not mist.DBs or not mist.DBs.units then
        debugLog("[getSamList] Error: MIST not loaded or DBs not available")
        return list
    end

    local coalitions = {}
    if coalition == "all" then
        coalitions = {"red", "blue"}
    else
        coalitions = {coalition}
    end

    for _, side in ipairs(coalitions) do
        if mist.DBs.units[side] then
            for country, country_table in pairs(mist.DBs.units[side]) do
                if type(country_table.vehicle) == 'table' then
                    for group_ind, group_tbl in pairs(country_table.vehicle) do
                        for unit_ind, unit in pairs(group_tbl.units) do
                            local isSam = false

                            -- SAM_CONFIGが利用可能な場合
                            if SAM_CONFIG and SAM_CONFIG.isSamType then
                                isSam = SAM_CONFIG.isSamType(unit.type)
                            else
                                isSam = tableContainsValue(SamTypes, unit.type)
                            end

                            if isSam then
                                local samInfo = {
                                    unitName = unit.unitName,
                                    type = unit.type,
                                    groupName = group_tbl.groupName,
                                    coalition = side,
                                    country = country,
                                    position = {
                                        x = unit.x,
                                        y = unit.y
                                    }
                                }
                                table.insert(list, samInfo)
                                debugLog("[getSamList] Found SAM: " .. unit.unitName .. " (" .. unit.type .. ")")
                            end
                        end
                    end
                end
            end
        end
    end

    debugLog("[getSamList] Total SAMs found: " .. #list)
    return list
end

--[[
    SAMグループのリストを取得（ユニット単位ではなくグループ単位）
    @param coalition 陣営 ("red", "blue", "all")
    @return SAMグループ情報のテーブル配列
]]
function getSamGroups(coalition)
    local samList = getSamList(coalition)
    local groups = {}
    local seenGroups = {}

    for _, sam in ipairs(samList) do
        if not seenGroups[sam.groupName] then
            seenGroups[sam.groupName] = true
            table.insert(groups, {
                groupName = sam.groupName,
                coalition = sam.coalition,
                country = sam.country,
                units = {}
            })
        end

        -- グループにユニットを追加
        for _, group in ipairs(groups) do
            if group.groupName == sam.groupName then
                table.insert(group.units, sam)
                break
            end
        end
    end

    return groups
end

--[[
    SAMタイプでフィルタリング
    @param samList SAMリスト
    @param samType SAMタイプ名
    @return フィルタリングされたリスト
]]
function filterSamsByType(samList, samType)
    local filtered = {}
    for _, sam in ipairs(samList) do
        if sam.type == samType then
            table.insert(filtered, sam)
        end
    end
    return filtered
end

--[[
    SAMカテゴリでフィルタリング
    @param samList SAMリスト
    @param category カテゴリ ("EWR", "SR", "TR", "LN", "SHORAD", "STR")
    @return フィルタリングされたリスト
]]
function filterSamsByCategory(samList, category)
    if not SAM_CONFIG then
        debugLog("[filterSamsByCategory] Warning: SAM_CONFIG not loaded, cannot filter by category")
        return samList
    end

    local filtered = {}
    for _, sam in ipairs(samList) do
        local config = SAM_CONFIG.getTypeConfig(sam.type)
        if config and config.category == category then
            table.insert(filtered, sam)
        end
    end
    return filtered
end

--[[
    SAMリストを画面に表示
    @param samList SAMリスト（nilの場合は自動取得）
]]
function printSamList(samList)
    samList = samList or getSamList("all")

    local message = "=== SAM List ===\n"
    for i, sam in ipairs(samList) do
        message = message .. string.format("%d. %s (%s) - %s\n",
            i, sam.unitName, sam.type, sam.coalition)
    end
    message = message .. string.format("Total: %d SAMs", #samList)

    trigger.action.outText(message, 30)
end

--[[
    IADSネットワークにすべてのSAMを自動追加
    @param iads IADSネットワークインスタンス
    @param coalition 陣営 ("red", "blue")
    @return 追加されたSAMサイト数
]]
function addAllSamsToIADS(iads, coalition)
    if not iads then
        debugLog("[addAllSamsToIADS] Error: IADS network not provided")
        return 0
    end

    local samGroups = getSamGroups(coalition)
    local count = 0

    for _, groupInfo in ipairs(samGroups) do
        local group = Group.getByName(groupInfo.groupName)
        if group then
            iads:addSamSite(group)
            count = count + 1
        end
    end

    debugLog("[addAllSamsToIADS] Added " .. count .. " SAM sites to IADS")
    return count
end

return {
    getSamList = getSamList,
    getSamGroups = getSamGroups,
    filterSamsByType = filterSamsByType,
    filterSamsByCategory = filterSamsByCategory,
    printSamList = printSamList,
    addAllSamsToIADS = addAllSamsToIADS
}
