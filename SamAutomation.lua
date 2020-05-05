SEAD_launch = {}
function SEAD_launch:onEvent(event)
    local debugmode = true
	if event.id == world.event.S_EVENT_SHOT then -- Detect weapon being fired
		--local _grp = Unit.getGroup(event.initiator)-- Identify the group that fired
		--local _groupname = _grp:getName() -- return the name of the group
		--local _unittable = {event.initiator:getName()} -- return the name of the units in the group
		local _SEADmissile = event.weapon -- Identify the weapon fired
		local _SEADmissileName = _SEADmissile:getTypeName()	-- return weapon type
		if debugmode == true then trigger.action.outText( string.format("Alerte, depart missile " ..string.format(_SEADmissileName)), 20) end --debug message 
		if _SEADmissileName == "KH-58" or _SEADmissileName == "KH-25MPU" or _SEADmissileName == "weapons.missiles.AGM_88" or _SEADmissileName == "weapons.missiles.LD-10" then --とりあえずHARMとLD-10のみ対応
            local _targetMim = Weapon.getTarget(_SEADmissile) -- Identify target
            if _targetMim == nil then
                return
            end
            local _targetMimname = Unit.getName(_targetMim)
            local _targetMimgroup = Unit.getGroup(Weapon.getTarget(_SEADmissile))
            local _targetMimcont= _targetMimgroup:getController()
            local _targetMimTypeName = _targetMim:getTypeName()
            local id = {
                groupName = _targetMimgroup,
                ctrl = _targetMimcont
            }
            SuppressedGroups = {}

            if debugmode == true then trigger.action.outText( string.format("target name " ..string.format(_targetMimTypeName)), 20) end
            --★Suppressed(id,Suppresse_rate,MinOffDelay,MaxOffDelay,MinStartDelay,MaxStartDelay)
            --id 無視
            --Suppresse_rate 0-停波せず 1-99 1％から99％停波する 100-必ず停波する
            --MinOffDelay 停波するまでの最小時間
            --MaxOffDelay 停波するまでの最大時間
            --MinStartDelay 停波した後、送波するまでの最小時間
            --MaxStartDelay 停波した後、送波するまでの最大時間
            if _targetMimTypeName == "1L13 EWR" then
                Suppressed(id,100,10,11,10,11)
            elseif _targetMimTypeName == "55G6 EWR" then
                Suppressed(id,100,10,11,10,11)
            elseif _targetMimTypeName == "p-19 s-125 sr" then
                Suppressed(id,100,15,20,40,80)
            elseif _targetMimTypeName == "Dog Ear radar" then
                Suppressed(id,100,10,11,10,11)
            elseif _targetMimTypeName == "SNR_75V" then
                Suppressed(id,100,10,20,40,80)
            elseif _targetMimTypeName == "snr s-125 tr" then
                Suppressed(id,100,10,15,20,40)
            elseif _targetMimTypeName == "Kub 1S91 str" then
                Suppressed(id,100,15,20,40,60)
            elseif _targetMimTypeName == "Osa 9A33 ln" then
                Suppressed(id,100,7,10,30,5z0)
            elseif _targetMimTypeName == "S-300PS 40B6M tr" then
                Suppressed(id,100,10,11,10,11)
            elseif _targetMimTypeName == "S-300PS 40B6MD sr" then
                Suppressed(id,100,10,11,10,11)
            elseif _targetMimTypeName == "S-300PS 64H6E sr" then
                Suppressed(id,100,10,11,10,11)
            elseif _targetMimTypeName == "SA-11 Buk SR 9S18M1" then
                Suppressed(id,100,10,11,10,11)
            elseif _targetMimTypeName == "SA-11 Buk LN 9A310M1" then
                Suppressed(id,100,10,11,10,11)
            elseif _targetMimTypeName == "Tor 9A331" then
                Suppressed(id,100,10,11,10,11)
            elseif _targetMimTypeName == "Hawk tr" then
                Suppressed(id,100,10,11,10,11)
            elseif _targetMimTypeName == "Hawk sr" then
                Suppressed(id,100,10,11,10,11)
            elseif _targetMimTypeName == "Patriot str" then
                Suppressed(id,100,10,11,10,11)
            elseif _targetMimTypeName == "Hawk cwar" then
                Suppressed(id,100,10,11,10,11)
            elseif _targetMimTypeName == "Roland Radar" then
                Suppressed(id,100,10,11,10,11)
            else
                Suppressed(id,100,10,11,10,11)
            end
        end
    end
end

function Suppressed(id,Suppresse_rate,MinOffDelay,MaxOffDelay,MinStartDelay,MaxStartDelay)
    local _evade = mist.random (1,100) -- random number for chance of evading action
    if (_evade <= Suppresse_rate) then --ここで何割起動するか設定する
        local RadarOffDelay = math.random(MinOffDelay, MaxOffDelay) --ミサイル発射時から何秒後に停波するか決める
        local RadarOnDelay = math.random(MinStartDelay, MaxStartDelay) --停波後から何秒後に起動するか決める
        if SuppressedGroups[id.groupName] == nil then
            SuppressedGroups[id.groupName] = {
                SuppressionStartTime = timer.getTime() + RadarOffDelay,
                SuppressionEndTime = timer.getTime() + RadarOnDelay +  RadarOffDelay,
                Missileobj = _SEADmissileName,
                SuppressionEndN = SuppressionEndCounter	--Store instance of SuppressionEnd() scheduled function
            }
            timer.scheduleFunction(SuppressionStart, id, SuppressedGroups[id.groupName].SuppressionStartTime)	--Schedule the SuppressionStart() function
            timer.scheduleFunction(SuppressionEnd, id, SuppressedGroups[id.groupName].SuppressionEndTime)	--Schedule the SuppressionEnd() function
            if debugmode == true then trigger.action.outText( string.format("Radar Off " ..string.format(RadarOffDelay)), 20) end --debug message
            if debugmode == true then trigger.action.outText( string.format("Radar On " ..string.format(RadarOnDelay)), 20) end --debug message
        end
    end
end

function SuppressionEnd(id)
    id.ctrl:setOption(AI.Option.Ground.id.ALARM_STATE,AI.Option.Ground.val.ALARM_STATE.RED)
    SuppressedGroups[id.groupName] = nil
end

function SuppressionStart(id)
    id.ctrl:setOption(AI.Option.Ground.id.ALARM_STATE,AI.Option.Ground.val.ALARM_STATE.GREEN)
end

function table.in_value (tbl, val)
    for k, v in pairs (tbl) do
        if v==val then return true end
    end
    return false
end

world.addEventHandler(SEAD_launch)
