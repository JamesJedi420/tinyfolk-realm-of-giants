--!strict

local GameplayCollisionGroupConfig = require("../src/ReplicatedStorage/Shared/Config/GameplayCollisionGroupConfig")
local GameplayCollisionGroupMatrix = require("../src/ReplicatedStorage/Shared/Physics/GameplayCollisionGroupMatrix")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

do
	local valid, reason = GameplayCollisionGroupMatrix.ValidateConfig()
	assertTrue(valid, "config validates")
	assertEqual(reason, nil, "config validation reason nil")
end

do
	local lookup = GameplayCollisionGroupMatrix.BuildRelationLookup()
	assertEqual(
		GameplayCollisionGroupMatrix.GetRelation(
			GameplayCollisionGroupConfig.Groups.Giant,
			GameplayCollisionGroupConfig.Groups.Tinyfolk,
			lookup
		),
		"collide",
		"giant tinyfolk collide"
	)
	assertEqual(
		GameplayCollisionGroupMatrix.GetRelation(
			GameplayCollisionGroupConfig.Groups.Giant,
			GameplayCollisionGroupConfig.Groups.CarriedTinyfolk,
			lookup
		),
		"ignore",
		"giant carried ignore"
	)
	assertEqual(
		GameplayCollisionGroupMatrix.GetRelation(
			GameplayCollisionGroupConfig.Groups.Tinyfolk,
			GameplayCollisionGroupConfig.Groups.GiantRoute,
			lookup
		),
		"ignore",
		"tinyfolk giant route ignore"
	)
	assertEqual(
		GameplayCollisionGroupMatrix.GetRelation(
			GameplayCollisionGroupConfig.Groups.Tinyfolk,
			GameplayCollisionGroupConfig.Groups.TinyfolkRoute,
			lookup
		),
		"collide",
		"tinyfolk route default collide"
	)
	assertEqual(
		GameplayCollisionGroupMatrix.GetRelation(
			GameplayCollisionGroupConfig.Groups.TriggerZone,
			GameplayCollisionGroupConfig.Groups.WorldGeometry,
			lookup
		),
		"touch",
		"trigger world touch"
	)
end

do
	assertEqual(
		GameplayCollisionGroupMatrix.ResolveCharacterGroup({
			role = "Giant",
			captureActive = false,
			carriedState = "Free",
		}),
		GameplayCollisionGroupConfig.Groups.Giant,
		"giant role group"
	)
	assertEqual(
		GameplayCollisionGroupMatrix.ResolveCharacterGroup({
			role = "Tinyfolk",
			captureActive = false,
			carriedState = "Free",
		}),
		GameplayCollisionGroupConfig.Groups.Tinyfolk,
		"tinyfolk role group"
	)
	assertEqual(
		GameplayCollisionGroupMatrix.ResolveCharacterGroup({
			role = "Tinyfolk",
			captureActive = true,
			carriedState = "Free",
		}),
		GameplayCollisionGroupConfig.Groups.ContainedTinyfolk,
		"capture active group"
	)
	assertEqual(
		GameplayCollisionGroupMatrix.ResolveCharacterGroup({
			role = "Tinyfolk",
			captureActive = false,
			carriedState = "Carried",
		}),
		GameplayCollisionGroupConfig.Groups.CarriedTinyfolk,
		"carried state group"
	)
end

do
	local mockPart: any = {
		ClassName = "Part",
		CanCollide = false,
		CanTouch = true,
		_Attributes = {},
		GetAttribute = function(self: any, name: string): any
			return self._Attributes[name]
		end,
	}
	assertEqual(
		GameplayCollisionGroupMatrix.ResolveWorldPartGroup(mockPart),
		GameplayCollisionGroupConfig.Groups.TriggerZone,
		"touch non-collide part is trigger"
	)

	mockPart.CanCollide = true
	mockPart.CanTouch = false
	assertEqual(
		GameplayCollisionGroupMatrix.ResolveWorldPartGroup(mockPart),
		GameplayCollisionGroupConfig.Groups.WorldGeometry,
		"solid part defaults world geometry"
	)

	mockPart._Attributes.TinyfolkOnlyRoute = true
	assertEqual(
		GameplayCollisionGroupMatrix.ResolveWorldPartGroup(mockPart),
		GameplayCollisionGroupConfig.Groups.TinyfolkRoute,
		"tinyfolk route attribute mapping"
	)
end

print("gameplay_collision_group_matrix.spec.luau: all checks passed")
