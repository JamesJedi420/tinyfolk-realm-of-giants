--!nocheck

local ContainmentStructureConfig = require("../src/ReplicatedStorage/Shared/Config/ContainmentStructureConfig")
local ContainmentStructurePlacementState =
	require("../src/ReplicatedStorage/Shared/GiantRealm/ContainmentStructurePlacementState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

do
	local placement = ContainmentStructurePlacementState.ResolveBuildModePlacement(
		ContainmentStructureConfig,
		"GiantStructure_Containment_Cage_A"
	)
	assertTrue(placement ~= nil, "cage placement resolves")
	if placement ~= nil then
		assertEqual(placement.structureType, "cage", "cage placement type")
		assertEqual(placement.capacity, 2, "cage placement capacity")
	end
end

do
	assertTrue(
		ContainmentStructurePlacementState.IsContainmentBuildStructure(
			{ category = "containment" },
			ContainmentStructureConfig,
			"GiantStructure_Containment_Jar_A"
		),
		"jar catalog category is containment build structure"
	)
	assertTrue(
		not ContainmentStructurePlacementState.IsContainmentBuildStructure(
			{ category = "utility" },
			ContainmentStructureConfig,
			"GiantStructure_Runtime_A"
		),
		"utility catalog entry is not containment build structure"
	)
end

do
	local structureId, zoneId = ContainmentStructurePlacementState.BuildContainmentIds(
		ContainmentStructureConfig,
		"GiantStructure_Containment_Cage_A"
	)
	assertEqual(structureId, "ContainmentStructure_GiantStructure_Containment_Cage_A", "structure id suffix")
	assertEqual(zoneId, "ContainmentStructureZone_GiantStructure_Containment_Cage_A", "zone id suffix")
end

do
	local geometry = ContainmentStructurePlacementState.BuildPlacementGeometry(
		ContainmentStructureConfig,
		"GiantStructure_Containment_Jar_A",
		{ x = 40, y = 2, z = -60 }
	)
	assertTrue(geometry ~= nil, "jar placement geometry resolves")
	if geometry ~= nil then
		assertEqual(geometry.structureType, "jar", "geometry structure type")
		assertEqual(geometry.capacity, 1, "geometry capacity")
		assertEqual(geometry.structurePosition.x, 40, "geometry center x")
		assertEqual(geometry.zoneSize.x, 14, "geometry zone width")
	end
end

print("containment_structure_placement_state: all checks passed")
