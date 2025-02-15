function widget:GetInfo()
    return {
        name = "EcoTracker",
        desc = "Tracks resources with start/stop controls.",
        author = "ChatGPT",
        date = "2025-01-05",
        license = "GPLv2",
        layer = 0,
        enabled = true
    }
end

local unitCache = {}
local unitDefsToTrack = {}
local outputDefs = {}
outputDefs.seconds = {}

local unitModelCache = {} -- to swapped out
unitModelCache.unitdefs = {}
unitModelCache.seconds = {}
unitModelCache.energyProduced = 0
unitModelCache.metalProduced = 0
unitModelCache.energySpent = 0
unitModelCache.metalSpent = 0
unitModelCache.liquidEnergy = 0
unitModelCache.liquidMetal = 0
local gaiaID = Spring.GetGaiaTeamID()
local gaiaAllyID = select(6, Spring.GetTeamInfo(gaiaID, false))

local options = {
    useMetalEquivalent70 = false,
    subtractReclaimFromIncome = false,
    staticWindValue = 14.2
}

function widget:Initialize()
    viewScreenWidth, viewScreenHeight = Spring.GetViewGeometry()

    buildUnitDefs()
    buildUnitCache()
end

local lastGameUpdate = 0
function widget:Update()
    local gs = math.floor(Spring.GetGameSeconds())
    if gs == lastGameUpdate then
        return
    end
    lastGameUpdate = gs
    calculateUnitData(unitCache, 0, "economyUnits", gs)
end

-- run test from 8:20 -> 23:00
-- make the columns key-values where the key is the unit and the value is the piece of data
gamesecondscoldef = { name = "Game Seconds", unit = nil, valueFunc = nil }
armfusEcoldef = { name = "Arm Fusion", unit = "armfus", valueProperty = "energyProducedOverTimeArray" }
armafusEcoldef = { name = "Arm AFUS", unit = "armafus", valueProperty = "energyProducedOverTimeArray" }
armwinEcoldef = { name = "Arm Wind", unit = "armwin", valueProperty = "energyProducedOverTimeArray" }
armmmkrMcoldef = { name = "Arm T2 Conv", unit = "armmmkr", valueProperty = "metalProducedOverTimeArray" }
armmakrMcoldef = { name = "Arm T1 Conv", unit = "armmakr", valueProperty = "metalProducedOverTimeArray" }
armmohoMcoldef = { name = "T2 Mex", unit = "armmoho", valueProperty = "metalProducedOverTimeArray" }
armnanotcMScoldef = { name = "Arm Con Turret", unit = "armnanotc", valueProperty = "metalSpentOverTimeArray" }
armnanotcCcoldef = { name = "Arm Con Turret Count", unit = "armnanotc", valueProperty = "countOverTimeArray" }
local csvColumns = { gamesecondscoldef, armmohoMcoldef, armmakrMcoldef, armmmkrMcoldef,
    armafusEcoldef, armfusEcoldef, armwinEcoldef,
    armnanotcMScoldef, armnanotcCcoldef }
-- local csvColumns = {gamesecondscoldef,armafusEcoldef,armwinEcoldef,armmakrMcoldef,armmmkrMcoldef, armnanotcMScoldef}

local function writeTableToCSV(filename, modelCacheDefs, coldefs)
    -- Open file for writing
    local file = io.open(filename, "w")
    if not file then
        return false, "Failed to open file"
    end

    -- Write header row
    headerRow = {}
    for i, coldef in ipairs(coldefs) do
        table.insert(headerRow, coldef.name)
    end
    file:write(table.concat(headerRow, ","), "\n")

    -- foreach second, write a line
    -- Create a lookup table for modelCacheDefs by name
    local modelCacheDefsByName = {}
    for _, v in pairs(modelCacheDefs) do
        modelCacheDefsByName[v.name] = v
    end

    for _, sec in ipairs(unitModelCache.seconds) do
        local values = {}
        table.insert(values, sec) -- Add time as the first column

        -- Process each column definition
        for _, coldef in ipairs(coldefs) do
            if coldef.valueProperty ~= nil then
                local v = modelCacheDefsByName[coldef.unit] -- Fetch the correct unit directly
                if v then
                    local value = (v[coldef.valueProperty] and v[coldef.valueProperty][sec]) or 0
                    table.insert(values, tostring(value))
                else
                    table.insert(values, "0") -- Default value if unit not found
                end
            end
        end

        -- Write the correctly formatted row
        file:write(table.concat(values, ","), "\n")
    end

    file:close()
    return true
end

lx = 0
ly = 300
rx = 50
ry = 350
function widget:MousePress(x, y, button)
    if is_point_in_box(x, y, lx, ly, rx, ry) then
        writeTableToCSV("LuaUI/Widgets/data.csv", unitModelCache.unitdefs, csvColumns)
        unitModelCache.energyProduced = 0
        unitModelCache.metalProduced = 0
        for udid, value in pairs(unitModelCache.unitdefs) do
            value.totalEnergyProduced = 0
            value.totalEnergySpent = 0
            value.totalMetalProduced = 0
            value.totalMetalSpent = 0
        end
    end
end

-- todo: refactor to just care about unitdefid
function calculateUnitData(unitCache, teamID, cacheName, gameSecond)
    table.insert(unitModelCache.seconds, gameSecond)

    for key, value in pairs(unitModelCache.unitdefs) do
        value.count = 0 -- NLN
        value.lastSecondEnergyProduced = 0
        value.lastSecondEnergySpent = 0
        value.lastSecondMetalProduced = 0
        value.lastSecondMetalSpent = 0
    end

    -- track stable/unstable for better efficiency
    if unitCache[teamID] and unitCache[teamID][cacheName] then
        -- change to loop over defs
        for udid, unitIds in pairs(unitCache[teamID][cacheName].defs) do
            if not unitModelCache.unitdefs[udid] then
                unitModelCache.unitdefs[udid] = {
                    name = UnitDefs[udid]["tooltip"],
                    count = 0,
                    countOverTimeArray = {},

                    lastSecondEnergyProduced = 0,
                    totalEnergyProduced = 0,
                    totalEnergySpent = 0,
                    lastSecondEnergySpent = 0,
                    energyProducedOverTimeArray = {},
                    energySpentOverTimeArray = {},

                    lastSecondMetalProduced = 0,
                    totalMetalProduced = 0,
                    totalMetalSpent = 0,
                    lastSecondMetalSpent = 0,
                    metalProducedOverTimeArray = {},
                    metalSpentOverTimeArray = {}
                }
            else
                if isWind(udid) then
                    local windPower =  (function() if options.staticWindValue > 0 then return options.staticWindValue else return select(4, Spring.GetWind()) end end)()
                    unitModelCache.unitdefs[udid].count = #unitCache[teamID][cacheName].defs[udid]
                    table.insert(unitModelCache.unitdefs[udid].energyProducedOverTimeArray, gameSecond,
                        windPower * unitModelCache.unitdefs[udid].count)
                    table.insert(unitModelCache.unitdefs[udid].energySpentOverTimeArray, gameSecond,
                        unitModelCache.unitdefs[udid].lastSecondEnergySpent)
                    table.insert(unitModelCache.unitdefs[udid].metalProducedOverTimeArray, gameSecond,
                        unitModelCache.unitdefs[udid].lastSecondMetalProduced)
                    table.insert(unitModelCache.unitdefs[udid].metalSpentOverTimeArray, gameSecond,
                        unitModelCache.unitdefs[udid].lastSecondMetalSpent)
                else
                    -- iterate over each unit like before
                    for _, unitId in ipairs(unitIds) do
                        local metalMake, metalUse, energyMake, energyUse = Spring.GetUnitResources(unitId)

                        unitModelCache.unitdefs[udid].totalEnergyProduced = unitModelCache.unitdefs[udid].totalEnergyProduced +
                        energyMake
                        unitModelCache.unitdefs[udid].lastSecondEnergyProduced = unitModelCache.unitdefs[udid]
                        .lastSecondEnergyProduced + energyMake
                        unitModelCache.unitdefs[udid].lastSecondEnergySpent = unitModelCache.unitdefs[udid]
                        .lastSecondEnergySpent + energyUse
                        unitModelCache.unitdefs[udid].totalEnergySpent = unitModelCache.unitdefs[udid].totalEnergySpent +
                        energyUse
                        table.insert(unitModelCache.unitdefs[udid].energyProducedOverTimeArray, gameSecond,
                            unitModelCache.unitdefs[udid].lastSecondEnergyProduced)
                        table.insert(unitModelCache.unitdefs[udid].energySpentOverTimeArray, gameSecond,
                            unitModelCache.unitdefs[udid].lastSecondEnergySpent)

                        unitModelCache.unitdefs[udid].totalMetalProduced = unitModelCache.unitdefs[udid].totalMetalProduced +
                        metalMake
                        unitModelCache.unitdefs[udid].lastSecondMetalProduced = unitModelCache.unitdefs[udid]
                        .lastSecondMetalProduced + metalMake
                        unitModelCache.unitdefs[udid].lastSecondMetalSpent = unitModelCache.unitdefs[udid].lastSecondMetalSpent +
                        metalUse
                        unitModelCache.unitdefs[udid].totalMetalSpent = unitModelCache.unitdefs[udid].totalMetalSpent + metalUse
                        table.insert(unitModelCache.unitdefs[udid].metalProducedOverTimeArray, gameSecond,
                            unitModelCache.unitdefs[udid].lastSecondMetalProduced)
                        table.insert(unitModelCache.unitdefs[udid].metalSpentOverTimeArray, gameSecond,
                            unitModelCache.unitdefs[udid].lastSecondMetalSpent)

                        unitModelCache.energyProduced = unitModelCache.energyProduced + energyMake
                        unitModelCache.metalProduced = unitModelCache.metalProduced + metalMake
                    end
                end
            end
            unitModelCache.unitdefs[udid].count = #unitCache[teamID][cacheName].defs[udid]
            table.insert(unitModelCache.unitdefs[udid].countOverTimeArray, gameSecond,
            #unitCache[teamID][cacheName].defs[udid])
                
        end
    end
end

-- commente out for performance
function widget:DrawScreen()
    gl.Text("Hello There", 1700, 1350, 16, "s")
    --     local mouseX, mouseY = Spring.GetMouseState()

    --     gl.Text(mouseX .. " " .. mouseY, 400, 150, 16, "o")
    --     gl.Text("total E: " .. unitModelCache.energyProduced, 400, 200, 16, "o")
    --     gl.Text("total M: " .. unitModelCache.metalProduced, 400, 225, 16, "o")

    --     local startPosX = 1700
    --     local startPosY = 1350
    --     local textSpacing = 0
    --     local buffer = 5
    --     local function printecobuilding(prefix, value)
    --         gl.Text(prefix .. value, startPosX, startPosY - textSpacing, 16, "s")
    --         textSpacing = textSpacing + 25

    --         if textSpacing >= startPosY - 200 then
    --             textSpacing = 0
    --             startPosX = startPosX + 300
    --         end
    --     end

    --     -- draw e structure diagnostics
    --     if unitModelCache then
    --         for unitDef, unitInfo in pairs(unitModelCache.unitdefs) do
    --             printecobuilding("", unitInfo.name)
    --             -- printecobuilding("UnitDefId:", unitDef)
    --             printecobuilding("Count: ", unitInfo.count)
    --             printecobuilding("Total E Produced:", unitInfo.totalEnergyProduced)
    --             printecobuilding("Total E Spent:", unitInfo.totalEnergySpent)
    --             printecobuilding("E/s IN:", unitInfo.lastSecondEnergyProduced)
    --             -- printecobuilding("E/s OUT:", unitInfo.lastSecondEnergySpent)
    --             printecobuilding("Total M Produced:", unitInfo.totalMetalProduced)
    --             printecobuilding("Total M Spent:", unitInfo.totalMetalSpent)
    --             printecobuilding("M/s IN:", unitInfo.lastSecondMetalProduced)
    --             -- printecobuilding("M/s OUT:", unitInfo.lastSecondMetalSpent)
    --             printecobuilding("-----------", "")
    --         end
    --     end

    --     -- reset button
    WG.FlowUI.Draw.Element(
        lx, -- x of bottom left
        ly, -- y of bottom left
        rx, -- x of top right
        ry, -- y of top right
        1, 1, 1, 1,
        1, 1, 1, 1
    )
end

-- Spring.GetTeamUnitDefCount
-- Spring.GetTeamUnitsByDefs
local windDefIds = {}
function buildUnitDefs()
    local function isEnergyProducer(unitDefId, unitDef)
        return ((unitDef.customParams.unitgroup == 'metal') or (unitDef.customParams.unitgroup == 'energy')) or
            (unitDef.customParams.energyconv_capacity and unitDef.customParams.energyconv_efficiency) or
            (unitDef.buildSpeed and (unitDef.buildSpeed > 0))
    end

    unitDefsToTrack = {}
    unitDefsToTrack.economyUnitDefs = {}

    for unitDefID, unitDef in ipairs(UnitDefs) do
        if isEnergyProducer(unitDefID, unitDef) then
            unitDefsToTrack.economyUnitDefs[unitDefID] = {
                name = unitDef.tooltip,
                energyMake = unitDef.energyMake,
                metalMake = unitDef
                    .metalMake
            }
        end

        if unitDef.tooltip == 'armwin' or unitDef.tooltip == 'corwin' then
            table.insert(windDefIds, unitDefID)
        end
    end
end

function buildUnitCache()
    unitCache = {}

    unitCache.economyUnits = {}

    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            local teamList = Spring.GetTeamList(allyID)
            for _, teamID in ipairs(teamList) do
                unitCache[teamID] = {}
                unitCache[teamID].economyUnits = {}
                unitCache[teamID].economyUnits.defs = {}
                unitCache[teamID].economyUnits.units = {}
                local unitIDs = Spring.GetTeamUnits(teamID)
                for i = 1, #unitIDs do
                    local unitID = unitIDs[i]
                    if not Spring.GetUnitIsBeingBuilt(unitID) then
                        local unitDefID = Spring.GetUnitDefID(unitID)
                        addToUnitCache(teamID, unitID, unitDefID)
                    end
                end
            end
        end
    end
end

----- ADD/REMOVE -----
function addToUnitCache(teamID, unitID, unitDefID)
    local function addToUnitCacheInternal(cache, teamID, unitID, value)
        if unitCache[teamID][cache] then
            if not unitCache[teamID][cache][unitID] then
                -- might want to push unit into array here
                unitCache[teamID][cache].units[unitID] = value
                if unitCache[teamID][cache].defs[unitDefID] == nil then
                    unitCache[teamID][cache].defs[unitDefID] = {}
                end
                table.insert(unitCache[teamID][cache].defs[unitDefID], unitID)
            else
                Spring.Echo(string.format("WARNING: addToUnitCache(), unitID %d already added", unitID))
            end
        end
    end

    if unitDefsToTrack.economyUnitDefs[unitDefID] then
        addToUnitCacheInternal("economyUnits", teamID, unitID,
            unitDefsToTrack.economyUnitDefs[unitDefID])
    end
end

function removeFromUnitCache(teamID, unitID, unitDefID)
    local function removeFromUnitCacheInternal(cache, teamID, unitID, value)
        if unitCache[teamID][cache] then
            if unitCache[teamID][cache].units[unitID] then
                unitCache[teamID][cache].units[unitID] = nil
                removeValue(unitCache[teamID][cache].defs[unitDefID], unitID)
            else
                Spring.Echo(string.format("WARNING: removeFromUnitCache(), unitID %d not in unit cache", unitID))
            end
        end
    end

    if unitDefsToTrack.economyUnitDefs[unitDefID] then
        removeFromUnitCacheInternal("economyUnits", teamID, unitID,
            unitDefsToTrack.economyUnitDefs[unitDefID])
    end
end

function removeValue(array, value)
    for i, v in ipairs(array) do
        if v == value then
            table.remove(array, i)
            return true -- Return true if a value was removed
        end
    end
    return false -- Return false if the value was not found
end

----- ADD/REMOVE -----

------- CREATE/DESTROY -------
function widget:UnitFinished(unitID, unitDefID, unitTeam)
    if unitCache[unitTeam] then
        addToUnitCache(unitTeam, unitID, unitDefID)
    end
end

function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    if Spring.GetUnitIsBeingBuilt(unitID) then
        return
    end

    if unitCache[oldTeam] then
        removeFromUnitCache(oldTeam, unitID, unitDefID)
    end

    if unitCache[newTeam] then
        addToUnitCache(newTeam, unitID, unitDefID)
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
    -- unit might've been a nanoframe
    if Spring.GetUnitIsBeingBuilt(unitID) then
        return
    end

    if unitCache[unitTeam] then
        removeFromUnitCache(unitTeam, unitID, unitDefID)
    end
end

------- CREATE/DESTROY -------

----- UTILITIES -----
function selectedUnitTableToString(tbl)
    local result = "{"
    for key, value in pairs(tbl) do
        local keyStr = tostring(key)
        local valueStr = type(value) == "table" and tableToString(value) or tostring(value)
        local unitDefID = Spring.GetUnitDefID(value)
        result = result .. keyStr .. " = " .. valueStr .. "," .. unitDefID .. ", "
    end
    result = result:sub(1, -3) -- Remove the trailing comma and space
    return result .. "}"
end

function tableToString(tbl)
    local result = "{"
    for key, value in pairs(tbl) do
        local keyStr = tostring(key)
        local valueStr = type(value) == "table" and tableToString(value) or tostring(value)
        result = result .. keyStr .. " = " .. valueStr .. ", "
    end
    result = result:sub(1, -3) -- Remove the trailing comma and space
    return result .. "}"
end

function is_point_in_box(x, y, x_min, y_min, x_max, y_max)
    return x >= x_min and x <= x_max and y >= y_min and y <= y_max
end

function containsValue(array, value)
    for _, v in ipairs(array) do
        if v == value then
            return true -- Value found
        end
    end
    return false -- Value not found
end

function isWind(unitDefId)
    return containsValue(windDefIds, unitDefId)
end

local printCount = 5
local printCountCurrent = 0
function PrintSome(msg)
    if printCountCurrent < printCount then
        if type(msg) == "table" then
            Spring.Echo("printsome: " .. tableToString(msg))
        else
            Spring.Echo("printsome: " .. msg)
        end
    end
    printCountCurrent = printCountCurrent + 1
end

----- UTILITIES -----



----- OLD ------------------------
----- unitCache[teamid][cachetype][unitId]
-- keep track of energy produced by each unit type and the total
-- eproduced,mproduced and added to total
local unitsICareAbout = {
    {
        name = 'armwin',
        isConstant = true,
        eFunc = function()
            return Spring.GetWind()
        end,
        mFunc = function()
            return 0
        end
    }, {
    name = "armfus"
}
}
function initializeUnitDefCache()
    -- local teams = Spring.GetTeamList()
    -- for i,t in ipairs(teams) do
    -- only get defs from list by name

    local t = 0
    outputDefs[t] = {}
    outputDefs[t].defs = {}

    outputDefs[t].countOverTimeArray = {}
    for k, v in pairs(UnitDefs) do
        for index, value in ipairs(unitsICareAbout) do
            if (v.name == value) then
                outputDefs[t].defs[k] = {} -- initialize every team w/ every def we care about
                outputDefs[t].defs[k].name = v["tooltip"]
                outputDefs[t].defs[k].energyProducedOverTimeArray = {}
                outputDefs[t].defs[k].energySpentOverTimeArray = {}
                outputDefs[t].defs[k].metalProducedOverTimeArray = {}
                outputDefs[t].defs[k].metalSpentOverTimeArray = {}
            end
        end
    end
    -- end
end

function calculateUnitDefData(teamID, gameSecond)
    table.insert(outputDefs.seconds, gameSecond)

    for key, value in pairs(outputDefs[teamID].defs) do
        value.lastSecondEnergyProduced = 0
        value.lastSecondEnergySpent = 0
        value.lastSecondMetalProduced = 0
        value.lastSecondMetalSpent = 0
    end

    if outputDefs[teamID] then
        for udid, v in pairs(outputDefs[teamID].defs) do
            local toSet = outputDefs[teamID].defs[udid]
            local toSetCount = Spring.GetTeamUnitDefCount(teamID, udid)
            toSet.count = toSetCount
            toSet.totalEnergyProduced = toSetCount * Spring.getteamun
        end
    end
    PrintSome(outputDefs[teamID])

    -- do all the math by multiplying by count
end
----- OLD