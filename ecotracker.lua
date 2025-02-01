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
local cachedTotals = {}
local unitDefsToTrack = {}
local unitModelCache = {}
unitModelCache.unitdefs = {}
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
}

function widget:Initialize()
    viewScreenWidth, viewScreenHeight = Spring.GetViewGeometry()

    buildUnitDefs()
    buildUnitCache()
end

local totalEnergyProduced = 0
local lastGameUpdate = 0
local selectedUnits = {}

local csvColumns = {"Arm Commander", "oranges", "bananas"}

function widget:Update()

    local gs = math.floor(Spring.GetGameSeconds())
    if gs == lastGameUpdate then
        return
    end
    lastGameUpdate = gs
    calculateUnitData(unitCache,0,"energyProducingUnits", gs)
    -- write csv line of data per second
    -- list of supported units w/ header mapping file
    -- unit list fusion: con turret m spent,con turret count, wind e,fusion e, adv e converter 
    -- a row has: GameSecond, afus e, fusion e, t2 conv m produced, 

end

local function writeTableToCSV(filename, data, keys)
    -- Open file for writing
    local file = io.open(filename, "w")
    if not file then
        return false, "Failed to open file"
    end
    
    -- Write header row
    file:write(table.concat(keys, ","), "\n")
    
    -- Write data rows
    local values = {}
    for _, key in ipairs(keys) do
        for key, value in pairs(data) do
            if value.name == key then
                table.insert(values, tostring(value.lastSecondEnergyProduced or 0))
            end
        end
    end
    file:write(table.concat(values, ","), "\n")
    
    -- Close the file
    file:close()
    return true
end

lx = 0
ly = 300
rx = 50
ry = 350
function widget:MousePress(x, y, button)
    if is_point_in_box(x,y,lx,ly,rx,ry) then
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

function calculateUnitData(unitCache, teamID, cacheName, gameSecond)

    for key, value in pairs(unitModelCache.unitdefs) do
        value.count = 0
        value.lastSecondEnergyProduced = 0
        value.lastSecondEnergySpent = 0
        value.lastSecondMetalProduced = 0
        value.lastSecondMetalSpent = 0
    end

    -- Check if the team and cache exist
    if unitCache[teamID] and unitCache[teamID][cacheName] then
        for unitID, unitData in pairs(unitCache[teamID][cacheName]) do
            local udid = Spring.GetUnitDefID(unitID)
            -- PrintOnce(unitCache[teamID][cacheName][unitID])
            -- local unitName = unitData.unitName
            local metalMake, metalUse, energyMake, energyUse = Spring.GetUnitResources(unitID)
            -- Initialize result entry for this unit type
            if not unitModelCache.unitdefs[udid] then
                unitModelCache.unitdefs[udid] = {
                    name = UnitDefs[udid]["translatedHumanName"],
                    count = 0,

                    lastSecondEnergyProduced = 0,
                    totalEnergyProduced = 0,
                    totalEnergySpent = 0,
                    lastSecondEnergySpent = 0,
                    energyProducedOverTimeArray = {},


                    lastSecondMetalProduced = 0,
                    totalMetalProduced = 0,
                    totalMetalSpent = 0,
                    lastSecondMetalSpent = 0,
                    metalProducedOverTimeArray = {},

                }
            else

                unitModelCache.unitdefs[udid].count = unitModelCache.unitdefs[udid].count + 1
                
                unitModelCache.unitdefs[udid].totalEnergyProduced = unitModelCache.unitdefs[udid].totalEnergyProduced + energyMake
                unitModelCache.unitdefs[udid].lastSecondEnergyProduced = unitModelCache.unitdefs[udid].lastSecondEnergyProduced + energyMake
                unitModelCache.unitdefs[udid].lastSecondEnergySpent = unitModelCache.unitdefs[udid].lastSecondEnergySpent + energyUse
                unitModelCache.unitdefs[udid].totalEnergySpent = unitModelCache.unitdefs[udid].totalEnergySpent + energyUse
                table.insert(unitModelCache.unitdefs[udid].energyProducedOverTimeArray, gameSecond, unitModelCache.unitdefs[udid].lastSecondEnergyProduced)
                unitModelCache.energyProduced = unitModelCache.energyProduced + energyMake
                

                unitModelCache.unitdefs[udid].totalMetalProduced = unitModelCache.unitdefs[udid].totalMetalProduced + metalMake
                unitModelCache.unitdefs[udid].lastSecondMetalProduced = unitModelCache.unitdefs[udid].lastSecondMetalProduced + metalMake
                unitModelCache.unitdefs[udid].totalMetalSpent = unitModelCache.unitdefs[udid].totalMetalSpent + metalUse
                unitModelCache.unitdefs[udid].lastSecondMetalSpent = unitModelCache.unitdefs[udid].lastSecondMetalSpent + metalUse
                unitModelCache.metalProduced = unitModelCache.metalProduced + metalMake
            end
        end
    end
end

local printCount = 1
local printCountCurrent = 0
function PrintOnce(msg)
    if printCountCurrent < printCount then
        if type(msg) == "table" then
            Spring.Echo("printonce: "..tableToString(msg))
        else
            Spring.Echo("printonce: "..msg)
        end
    end
    printCountCurrent = printCountCurrent + 1
end

function widget:DrawScreen()
    local mouseX, mouseY = Spring.GetMouseState()

    gl.Text(mouseX .." ".. mouseY, 400, 150, 16,"o")
    gl.Text("total E: "..unitModelCache.energyProduced, 400, 200, 16,"o")
    gl.Text("total M: "..unitModelCache.metalProduced, 400, 225, 16,"o")

    local startPosX = 1700
    local startPosY = 1350
    local textSpacing = 0
    local buffer = 5
    local function printecobuilding(prefix, value)
        gl.Text( prefix .. value, startPosX, startPosY - textSpacing, 16, "s")
        textSpacing = textSpacing + 25

        if textSpacing >= startPosY -200 then
            textSpacing = 0
            startPosX = startPosX + 300
        end
    end

    -- draw e structure diagnostics
    if unitModelCache then
        for unitDef, unitInfo in pairs(unitModelCache.unitdefs) do
            printecobuilding("", unitInfo.name)
            -- printecobuilding("UnitDefId:", unitDef)
            printecobuilding("Count: ", unitInfo.count)
            printecobuilding("Total E Produced:", unitInfo.totalEnergyProduced)
            printecobuilding("Total E Spent:", unitInfo.totalEnergySpent)
            -- printecobuilding("E/s IN:", unitInfo.lastSecondEnergyProduced)
            -- printecobuilding("E/s OUT:", unitInfo.lastSecondEnergySpent)
            printecobuilding("Total M Produced:", unitInfo.totalMetalProduced)
            printecobuilding("Total M Spent:", unitInfo.totalMetalSpent)
            -- printecobuilding("M/s IN:", unitInfo.lastSecondMetalProduced)
            -- printecobuilding("M/s OUT:", unitInfo.lastSecondMetalSpent)
            printecobuilding("-----------","")
        end
    end
    
    -- reset button
    WG.FlowUI.Draw.Element(
        lx, -- x of bottom left
        ly, -- y of bottom left
        rx, -- x of top right
        ry, -- y of top right
        1, 1, 1, 1,
        1, 1, 1, 1
    )
end

function is_point_in_box(x, y, x_min, y_min, x_max, y_max)
    return x >= x_min and x <= x_max and y >= y_min and y <= y_max
end

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
-- unitCache[teamid][cachetype][unitId]
-- keep track of energy produced by each unit type and the total
-- eproduced,mproduced and added to total
function buildUnitModelCache()
    iUnitModels = {}
    iUnitModels.add = function (self)
        table.insert(self.iUnitModels,{})
    end
end


function buildUnitCache()
    unitCache = {}
    cachedTotals = {}

    unitCache.energyProducingUnits = {}

    unitCache.reclaimerUnits = {
        add = nil,
        update = function(unitID, value)
            local reclaimMetal = 0
            local reclaimEnergy = 0
            local metalMake, metalUse, energyMake, energyUse = Spring.GetUnitResources(unitID)
            if metalMake then
                if value[1] then
                    reclaimMetal = metalMake - value[1]
                else
                    reclaimMetal = metalMake
                end
                if value[2] then
                    reclaimEnergy = energyMake - value[2]
                else
                    reclaimEnergy = energyMake
                end
            end
            return { reclaimMetal, reclaimEnergy }
        end,
        remove = nil,
    }
    unitCache.energyConverters = {
        add = nil,
        update = function(unitID, value)
            local metalMake, metalUse, energyMake, energyUse = Spring.GetUnitResources(unitID)
            if metalMake then
                return metalMake
            end
            return 0
        end,
        remove = nil,
    }
    unitCache.buildPower = {
        add = function(unitID, value)
            return value
        end,
        update = nil,
        remove = function(unitID, value)
            return value
        end,
    }
    unitCache.armyUnits = {
        add = function(unitID, value)
            local result = value[1]
            if options.useMetalEquivalent70 then
                result = result + (value[2] / 70)
            end
            return result
        end,
        update = nil,
        remove = function(unitID, value)
            local result = value[1]
            if options.useMetalEquivalent70 then
                result = result + (value[2] / 70)
            end
            return result
        end,
    }
    unitCache.defenseUnits = unitCache.armyUnits
    unitCache.utilityUnits = unitCache.armyUnits
    unitCache.economyBuildings = unitCache.armyUnits

    for _, allyID in ipairs(Spring.GetAllyTeamList()) do
        if allyID ~= gaiaAllyID then
            local teamList = Spring.GetTeamList(allyID)
            for _, teamID in ipairs(teamList) do
                unitCache[teamID] = {}
                cachedTotals[teamID] = {}
                unitCache[teamID].energyProducingUnits = {}
                cachedTotals[teamID].energyProducingUnits = 0
                unitCache[teamID].reclaimerUnits = {}
                cachedTotals[teamID].reclaimerUnits = 0
                unitCache[teamID].energyConverters = {}
                cachedTotals[teamID].energyConverters = 0
                unitCache[teamID].buildPower = {}
                cachedTotals[teamID].buildPower = 0
                unitCache[teamID].armyUnits = {}
                cachedTotals[teamID].armyUnits = 0
                unitCache[teamID].defenseUnits = {}
                cachedTotals[teamID].defenseUnits = 0
                unitCache[teamID].utilityUnits = {}
                cachedTotals[teamID].utilityUnits = 0
                unitCache[teamID].economyBuildings = {}
                cachedTotals[teamID].economyBuildings = 0
                local unitIDs = Spring.GetTeamUnits(teamID)
                for i=1,#unitIDs do
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

function addToUnitCache(teamID, unitID, unitDefID)
    local function addToUnitCacheInternal(cache, teamID, unitID, value)
        if unitCache[teamID][cache] then
            if not unitCache[teamID][cache][unitID] then
                if cachedTotals[teamID][cache] then
                    local valueToAdd = 0
                    if unitCache[cache].add then
                        valueToAdd = unitCache[cache].add(unitID, value)
                    end
                    cachedTotals[teamID][cache] = cachedTotals[teamID][cache] + valueToAdd
                end
                unitCache[teamID][cache][unitID] = value
            else
                Spring.Echo(string.format("WARNING: addToUnitCache(), unitID %d already added", unitID))
            end
        end
    end

    if unitDefsToTrack.energyProducerDefs[unitDefID] then
        addToUnitCacheInternal("energyProducingUnits",teamID,unitID,
                        unitDefsToTrack.energyProducerDefs[unitDefID])
    end
    if unitDefsToTrack.reclaimerUnitDefs[unitDefID] then
        addToUnitCacheInternal("reclaimerUnits", teamID, unitID,
                       unitDefsToTrack.reclaimerUnitDefs[unitDefID])
    end
    if unitDefsToTrack.energyConverterDefs[unitDefID] then
        addToUnitCacheInternal("energyConverters", teamID, unitID,
                       unitDefsToTrack.energyConverterDefs[unitDefID])
    end
    if unitDefsToTrack.buildPowerDefs[unitDefID] then
        addToUnitCacheInternal("buildPower", teamID, unitID,
                       unitDefsToTrack.buildPowerDefs[unitDefID])
    end
    if unitDefsToTrack.armyUnitDefs[unitDefID] then
        addToUnitCacheInternal("armyUnits", teamID, unitID,
                       unitDefsToTrack.armyUnitDefs[unitDefID])
    end
    if unitDefsToTrack.defenseUnitDefs[unitDefID] then
        addToUnitCacheInternal("defenseUnits", teamID, unitID,
                       unitDefsToTrack.defenseUnitDefs[unitDefID])
    end
    if unitDefsToTrack.utilityUnitDefs[unitDefID] then
        addToUnitCacheInternal("utilityUnits", teamID, unitID,
                       unitDefsToTrack.utilityUnitDefs[unitDefID])
    end
    if unitDefsToTrack.economyBuildingDefs[unitDefID] then
        addToUnitCacheInternal("economyBuildings", teamID, unitID,
                       unitDefsToTrack.economyBuildingDefs[unitDefID])
    end
end

function removeFromUnitCache(teamID, unitID, unitDefID)
    local function removeFromUnitCacheInternal(cache, teamID, unitID, value)
        if unitCache[teamID][cache] then
            if unitCache[teamID][cache][unitID] then
                if cachedTotals[teamID][cache] then
                    local valueToRemove = 0
                    if unitCache[cache].remove then
                        valueToRemove = unitCache[cache].remove(unitID, value)
                    end
                    cachedTotals[teamID][cache] = cachedTotals[teamID][cache] - valueToRemove
                end
                unitCache[teamID][cache][unitID] = nil
                -- unitModelCache[Spring.GetUnitDefID(unitID)] = nil
            else
                Spring.Echo(string.format("WARNING: removeFromUnitCache(), unitID %d not in unit cache", unitID))
            end
        end
    end

    if unitDefsToTrack.energyProducerDefs[unitDefID] then
        removeFromUnitCacheInternal("energyProducingUnits", teamID, unitID,
                       unitDefsToTrack.energyProducerDefs[unitDefID])
    end
    if unitDefsToTrack.reclaimerUnitDefs[unitDefID] then
        removeFromUnitCacheInternal("reclaimerUnits", teamID, unitID,
                       unitDefsToTrack.reclaimerUnitDefs[unitDefID])
    end
    if unitDefsToTrack.energyConverterDefs[unitDefID] then
        removeFromUnitCacheInternal("energyConverters", teamID, unitID,
                       unitDefsToTrack.energyConverterDefs[unitDefID])
    end
    if unitDefsToTrack.buildPowerDefs[unitDefID] then
        removeFromUnitCacheInternal("buildPower", teamID, unitID,
                       unitDefsToTrack.buildPowerDefs[unitDefID])
    end
    if unitDefsToTrack.armyUnitDefs[unitDefID] then
        removeFromUnitCacheInternal("armyUnits", teamID, unitID,
                       unitDefsToTrack.armyUnitDefs[unitDefID])
    end
    if unitDefsToTrack.defenseUnitDefs[unitDefID] then
        removeFromUnitCacheInternal("defenseUnits", teamID, unitID,
                       unitDefsToTrack.defenseUnitDefs[unitDefID])
    end
    if unitDefsToTrack.utilityUnitDefs[unitDefID] then
        removeFromUnitCacheInternal("utilityUnits", teamID, unitID,
                       unitDefsToTrack.utilityUnitDefs[unitDefID])
    end
    if unitDefsToTrack.economyBuildingDefs[unitDefID] then
        removeFromUnitCacheInternal("economyBuildings", teamID, unitID,
                       unitDefsToTrack.economyBuildingDefs[unitDefID])
    end
end

function buildUnitDefs()

    local function isEnergyProducer(unitDefId, unitDef)
        return ((unitDef.customParams.unitgroup == 'metal') or (unitDef.customParams.unitgroup == 'energy')) or 
        (unitDef.customParams.energyconv_capacity and unitDef.customParams.energyconv_efficiency) or 
        (unitDef.buildSpeed and (unitDef.buildSpeed > 0))
    end
    local function isCommander(unitDefID, unitDef)
        return unitDef.customParams.iscommander
    end

    local function isReclaimerUnit(unitDefID, unitDef)
        return unitDef.isBuilder and not unitDef.isFactory
    end

    local function isEnergyConverter(unitDefID, unitDef)
        return unitDef.customParams.energyconv_capacity and unitDef.customParams.energyconv_efficiency
    end

    local function isBuildPower(unitDefID, unitDef)
        return unitDef.buildSpeed and (unitDef.buildSpeed > 0)
    end

    local function isArmyUnit(unitDefID, unitDef)
        -- anything with a least one weapon and speed above zero is considered an army unit
        return unitDef.weapons and (#unitDef.weapons > 0) and unitDef.speed and (unitDef.speed > 0)
    end

    local function isDefenseUnit(unitDefID, unitDef)
        return unitDef.weapons and (#unitDef.weapons > 0) and (not unitDef.speed or (unitDef.speed == 0))
    end

    local function isUtilityUnit(unitDefID, unitDef)
        return unitDef.customParams.unitgroup == 'util'
    end

    local function isEconomyBuilding(unitDefID, unitDef)
        return (unitDef.customParams.unitgroup == 'metal') or (unitDef.customParams.unitgroup == 'energy')
    end

    unitDefsToTrack = {}
    unitDefsToTrack.energyProducerDefs = {}
    unitDefsToTrack.commanderUnitDefs = {}
    unitDefsToTrack.reclaimerUnitDefs = {}
    unitDefsToTrack.energyConverterDefs = {}
    unitDefsToTrack.buildPowerDefs = {}
    unitDefsToTrack.armyUnitDefs = {}
    unitDefsToTrack.defenseUnitDefs = {}
    unitDefsToTrack.utilityUnitDefs = {}
    unitDefsToTrack.economyBuildingDefs = {}

    -- modify this to take in units that produce energy and metal 
    -- track metalmake/energymake

    for unitDefID, unitDef in ipairs(UnitDefs) do
        if isEnergyProducer(unitDefID,unitDef) then
            unitDefsToTrack.energyProducerDefs[unitDefID] = {energyMake = unitDef.energyMake, metalMake = unitDef.metalMake}
        end
        if isCommander(unitDefID, unitDef) then
            unitDefsToTrack.commanderUnitDefs[unitDefID] = true
        end
        if isReclaimerUnit(unitDefID, unitDef) then
            unitDefsToTrack.reclaimerUnitDefs[unitDefID] = { unitDef.metalMake, unitDef.energyMake }
        end
        if isEnergyConverter(unitDefID, unitDef) then
            unitDefsToTrack.energyConverterDefs[unitDefID] = tonumber(unitDef.customParams.energyconv_capacity)
        end
        if isBuildPower(unitDefID, unitDef) then
            unitDefsToTrack.buildPowerDefs[unitDefID] = unitDef.buildSpeed
        end
        if isArmyUnit(unitDefID, unitDef) then
            unitDefsToTrack.armyUnitDefs[unitDefID] = { unitDef.metalCost, unitDef.energyCost }
        end
        if isDefenseUnit(unitDefID, unitDef) then
            unitDefsToTrack.defenseUnitDefs[unitDefID] = { unitDef.metalCost, unitDef.energyCost }
        end
        if isUtilityUnit(unitDefID, unitDef) then
            unitDefsToTrack.utilityUnitDefs[unitDefID] = { unitDef.metalCost, unitDef.energyCost }
        end
        if isEconomyBuilding(unitDefID, unitDef) then
            unitDefsToTrack.economyBuildingDefs[unitDefID] = { unitDef.metalCost, unitDef.energyCost }
        end
    end
end

function selectedUnitTableToString(tbl)
    local result = "{"
    for key, value in pairs(tbl) do
        local keyStr = tostring(key)
        local valueStr = type(value) == "table" and tableToString(value) or tostring(value)
        local unitDefID = Spring.GetUnitDefID(value)
        result = result .. keyStr .. " = " .. valueStr ..",".. unitDefID .. ", "
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
