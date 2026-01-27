--[[
    DCS SAM System Utilities
    共通ユーティリティ関数
]]

SAM_UTILS = {}

-- ============================================
-- デバッグ設定
-- ============================================
SAM_UTILS.DEBUG = false

-- ============================================
-- デバッグ出力
-- ============================================
function SAM_UTILS.debug(message, duration)
    if SAM_UTILS.DEBUG then
        duration = duration or 20
        trigger.action.outText(tostring(message), duration)
    end
end

-- ============================================
-- 情報出力（常に表示）
-- ============================================
function SAM_UTILS.info(message, duration)
    duration = duration or 10
    trigger.action.outText(tostring(message), duration)
end

-- ============================================
-- テーブル内の値の存在確認
-- ============================================
function SAM_UTILS.tableContainsValue(tbl, val)
    if tbl == nil then return false end
    for _, v in pairs(tbl) do
        if v == val then return true end
    end
    return false
end

-- ============================================
-- テーブル内のキーの存在確認
-- ============================================
function SAM_UTILS.tableContainsKey(tbl, key)
    if tbl == nil then return false end
    return tbl[key] ~= nil
end

-- ============================================
-- 2点間の距離計算(メートル)
-- ============================================
function SAM_UTILS.getDistance(pos1, pos2)
    if not pos1 or not pos2 then return nil end
    local dx = pos1.x - pos2.x
    local dy = (pos1.y or 0) - (pos2.y or 0)
    local dz = pos1.z - pos2.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ============================================
-- 2点間の2D距離計算(メートル、高度無視)
-- ============================================
function SAM_UTILS.getDistance2D(pos1, pos2)
    if not pos1 or not pos2 then return nil end
    local dx = pos1.x - pos2.x
    local dz = pos1.z - pos2.z
    return math.sqrt(dx * dx + dz * dz)
end

-- ============================================
-- ランダム値の取得
-- ============================================
function SAM_UTILS.random(min, max)
    if mist and mist.random then
        return mist.random(min, max)
    else
        return math.random(min, max)
    end
end

-- ============================================
-- ユニットの位置を取得
-- ============================================
function SAM_UTILS.getUnitPosition(unit)
    if unit and unit:isExist() then
        return unit:getPoint()
    end
    return nil
end

-- ============================================
-- グループの位置を取得(先頭ユニットの位置)
-- ============================================
function SAM_UTILS.getGroupPosition(group)
    if group then
        local units = group:getUnits()
        if units and #units > 0 then
            return SAM_UTILS.getUnitPosition(units[1])
        end
    end
    return nil
end

-- ============================================
-- ユニットの状態設定
-- ============================================
function SAM_UTILS.setUnitAlarmState(unit, state)
    if unit then
        local group = unit:getGroup()
        if group then
            local ctrl = group:getController()
            if ctrl then
                ctrl:setOption(AI.Option.Ground.id.ALARM_STATE, state)
                return true
            end
        end
    end
    return false
end

-- ============================================
-- グループの状態設定
-- ============================================
function SAM_UTILS.setGroupAlarmState(group, state)
    if group then
        local ctrl = group:getController()
        if ctrl then
            ctrl:setOption(AI.Option.Ground.id.ALARM_STATE, state)
            return true
        end
    end
    return false
end

-- ============================================
-- アラーム状態定義
-- ============================================
SAM_UTILS.ALARM_STATE = {
    GREEN = AI.Option.Ground.val.ALARM_STATE.GREEN,  -- レーダーOFF
    RED = AI.Option.Ground.val.ALARM_STATE.RED,      -- レーダーON
    AUTO = AI.Option.Ground.val.ALARM_STATE.AUTO
}

-- ============================================
-- ユニットからグループ情報を取得
-- ============================================
function SAM_UTILS.getUnitGroupInfo(unit)
    if not unit then return nil end
    local group = unit:getGroup()
    if not group then return nil end

    return {
        unit = unit,
        unitName = unit:getName(),
        unitType = unit:getTypeName(),
        group = group,
        groupName = group:getName(),
        controller = group:getController(),
        position = SAM_UTILS.getUnitPosition(unit)
    }
end

-- ============================================
-- テーブルの浅いコピー
-- ============================================
function SAM_UTILS.shallowCopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = v
    end
    return copy
end

-- ============================================
-- テーブルの深いコピー
-- ============================================
function SAM_UTILS.deepCopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            copy[k] = SAM_UTILS.deepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- ============================================
-- テーブルのマージ
-- ============================================
function SAM_UTILS.mergeTables(t1, t2)
    local result = SAM_UTILS.shallowCopy(t1)
    for k, v in pairs(t2) do
        result[k] = v
    end
    return result
end

-- ============================================
-- 現在時刻の取得
-- ============================================
function SAM_UTILS.getTime()
    return timer.getTime()
end

-- ============================================
-- タイマースケジュール
-- ============================================
function SAM_UTILS.scheduleFunction(func, args, time)
    return timer.scheduleFunction(func, args, time)
end

return SAM_UTILS
