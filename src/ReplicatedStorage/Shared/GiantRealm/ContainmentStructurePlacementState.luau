--!strict

local ContainmentStructurePlacementState = {}

export type Vector3Like = {
	x: number?,
	y: number?,
	z: number?,
	X: number?,
	Y: number?,
	Z: number?,
}

export type BuildModePlacementDefinition = {
	structureType: string,
	capacity: number,
	structureSize: Vector3Like,
	zoneSize: Vector3Like,
	escapeInteractionEnabled: boolean?,
}

export type BuildModePlacementConfig = {
	BuildModeCategory: string,
	BuildModePlacements: { [string]: BuildModePlacementDefinition },
	StructureNamePrefix: string,
	ZoneNamePrefix: string,
}

export type PlacementGeometry = {
	structureId: string,
	zoneId: string,
	structurePosition: { x: number, y: number, z: number },
	structureSize: { x: number, y: number, z: number },
	zonePosition: { x: number, y: number, z: number },
	zoneSize: { x: number, y: number, z: number },
	structureType: string,
	capacity: number,
	escapeInteractionEnabled: boolean,
}

local function readAxis(value: Vector3Like?, upperKey: string, lowerKey: string, fallback: number): number
	if type(value) ~= "table" then
		return fallback
	end
	local upper = value[upperKey]
	if type(upper) == "number" and upper > 0 then
		return upper
	end
	local lower = value[lowerKey]
	if type(lower) == "number" and lower > 0 then
		return lower
	end
	return fallback
end

local function readCenter(worldCenter: any): { x: number, y: number, z: number }?
	if type(worldCenter) ~= "table" then
		return nil
	end
	local x = worldCenter.x
	local y = worldCenter.y
	local z = worldCenter.z
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return nil
	end
	return { x = x, y = y, z = z }
end

function ContainmentStructurePlacementState.ResolveBuildModePlacement(
	config: BuildModePlacementConfig,
	giantStructureId: string
): BuildModePlacementDefinition?
	if type(giantStructureId) ~= "string" or giantStructureId == "" then
		return nil
	end
	if type(config.BuildModePlacements) ~= "table" then
		return nil
	end
	local placement = config.BuildModePlacements[giantStructureId]
	if type(placement) ~= "table" then
		return nil
	end
	return placement
end

function ContainmentStructurePlacementState.IsContainmentBuildStructure(
	catalogDefinition: any,
	config: BuildModePlacementConfig,
	giantStructureId: string
): boolean
	if type(catalogDefinition) ~= "table" then
		return false
	end
	if catalogDefinition.category ~= config.BuildModeCategory then
		return false
	end
	return ContainmentStructurePlacementState.ResolveBuildModePlacement(config, giantStructureId) ~= nil
end

function ContainmentStructurePlacementState.BuildContainmentIds(
	config: BuildModePlacementConfig,
	giantStructureId: string
): (string?, string?)
	if type(giantStructureId) ~= "string" or giantStructureId == "" then
		return nil, nil
	end
	local suffix = giantStructureId
	return config.StructureNamePrefix .. suffix, config.ZoneNamePrefix .. suffix
end

function ContainmentStructurePlacementState.BuildPlacementGeometry(
	config: BuildModePlacementConfig,
	giantStructureId: string,
	worldCenter: any
): PlacementGeometry?
	local placement = ContainmentStructurePlacementState.ResolveBuildModePlacement(config, giantStructureId)
	if placement == nil then
		return nil
	end
	local center = readCenter(worldCenter)
	if center == nil then
		return nil
	end
	local structureId, zoneId = ContainmentStructurePlacementState.BuildContainmentIds(config, giantStructureId)
	if structureId == nil or zoneId == nil then
		return nil
	end

	local structureSize = {
		x = readAxis(placement.structureSize, "X", "x", 8),
		y = readAxis(placement.structureSize, "Y", "y", 5),
		z = readAxis(placement.structureSize, "Z", "z", 8),
	}
	local zoneSize = {
		x = readAxis(placement.zoneSize, "X", "x", 16),
		y = readAxis(placement.zoneSize, "Y", "y", 6),
		z = readAxis(placement.zoneSize, "Z", "z", 16),
	}

	return {
		structureId = structureId,
		zoneId = zoneId,
		structurePosition = center,
		structureSize = structureSize,
		zonePosition = center,
		zoneSize = zoneSize,
		structureType = placement.structureType,
		capacity = placement.capacity,
		escapeInteractionEnabled = if placement.escapeInteractionEnabled == false then false else true,
	}
end

return ContainmentStructurePlacementState
