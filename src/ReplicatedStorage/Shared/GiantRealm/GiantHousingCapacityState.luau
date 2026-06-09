--!strict

local GiantHousingCapacityState: any = {}

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

function GiantHousingCapacityState.ResolvePublishedCapacity(
	baseCapacity: number,
	housingCapacityMultiplier: number
): number
	local safeBase = if isFiniteNumber(baseCapacity) and baseCapacity > 0 then baseCapacity else 1
	local multiplier = if isFiniteNumber(housingCapacityMultiplier) and housingCapacityMultiplier > 0
		then housingCapacityMultiplier
		else 1
	return math.max(1, math.floor(safeBase * multiplier + 0.5))
end

function GiantHousingCapacityState.ResolveMaxGiantsFromHousing(publishedHousingCapacity: number): number
	if not isFiniteNumber(publishedHousingCapacity) or publishedHousingCapacity < 0 then
		return 0
	end
	return math.floor(publishedHousingCapacity)
end

return GiantHousingCapacityState
