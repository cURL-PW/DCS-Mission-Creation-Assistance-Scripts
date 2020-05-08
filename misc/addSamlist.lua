SamType = {
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
  
  function table.in_value (tbl, val)
      for k, v in pairs (tbl) do
          if v==val then return true end
      end
      return false
  end
  
  function getSamList()
      local list = {}
      for country, country_table in pairs(mist.DBs.units.red) do
          if type(country_table.vehicle) == 'table' then
              for group_ind, group_tbl in pairs(country_table.vehicle) do
                  for unit_ind, unit in pairs(group_tbl.units) do
                      if table.in_value(SamType,unit.type) == true then
                        table.insert(list,unit)
                        if debugmode == true then trigger.action.outText( string.format("Add SAM List -> " .. unit.unitName), 20) end --debug message 
                      end
                  end
              end
          end
      end
      return list
  end