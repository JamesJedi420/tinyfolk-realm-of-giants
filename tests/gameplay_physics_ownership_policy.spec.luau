--!strict

local GameplayPhysicsOwnershipConfig = require("../src/ReplicatedStorage/Shared/Config/GameplayPhysicsOwnershipConfig")
local GameplayPhysicsOwnershipPolicy = require("../src/ReplicatedStorage/Shared/Physics/GameplayPhysicsOwnershipPolicy")

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
	local valid, reason = GameplayPhysicsOwnershipPolicy.ValidateConfig()
	assertTrue(valid, "config validates")
	assertEqual(reason, nil, "config validation reason nil")
end

do
	assertEqual(
		GameplayPhysicsOwnershipPolicy.ResolveCharacterAssembly({
			role = "Giant",
			captureActive = false,
			carriedState = "Free",
			heldTargetUserId = nil,
			heldByUserId = nil,
		}),
		GameplayPhysicsOwnershipConfig.Assemblies.FreeCharacter,
		"free giant assembly"
	)
	assertEqual(
		GameplayPhysicsOwnershipPolicy.ResolveCharacterTier({
			role = "Giant",
			captureActive = false,
			carriedState = "Free",
			heldTargetUserId = 42,
			heldByUserId = nil,
		}),
		GameplayPhysicsOwnershipConfig.OwnershipTier.Server,
		"carrying giant requires server ownership"
	)
	assertEqual(
		GameplayPhysicsOwnershipPolicy.ResolveCharacterAssembly({
			role = "Tinyfolk",
			captureActive = false,
			carriedState = "Carried",
			heldTargetUserId = nil,
			heldByUserId = 99,
		}),
		GameplayPhysicsOwnershipConfig.Assemblies.CarriedTinyfolk,
		"carried tinyfolk assembly"
	)
	assertEqual(
		GameplayPhysicsOwnershipPolicy.ResolveCharacterTier({
			role = "Tinyfolk",
			captureActive = true,
			carriedState = "Free",
			heldTargetUserId = nil,
			heldByUserId = nil,
		}),
		GameplayPhysicsOwnershipConfig.OwnershipTier.Server,
		"contained tinyfolk requires server ownership"
	)
end

do
	assertTrue(
		GameplayPhysicsOwnershipPolicy.IsServerCriticalAssembly(
			GameplayPhysicsOwnershipConfig.Assemblies.SnareTrap :: any
		),
		"snare trap is server critical"
	)
	assertTrue(
		not GameplayPhysicsOwnershipPolicy.IsServerCriticalAssembly(
			GameplayPhysicsOwnershipConfig.Assemblies.FreeCharacter :: any
		),
		"free character is not server critical"
	)
	assertTrue(
		GameplayPhysicsOwnershipPolicy.RequiresServerOwnership(
			GameplayPhysicsOwnershipConfig.OwnershipTier.Server :: any
		),
		"server tier requires server ownership"
	)
	assertTrue(
		not GameplayPhysicsOwnershipPolicy.RequiresServerOwnership(
			GameplayPhysicsOwnershipConfig.OwnershipTier.Automatic :: any
		),
		"automatic tier does not require forced server ownership"
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
		GameplayPhysicsOwnershipPolicy.ResolveWorldPartAssembly(mockPart),
		GameplayPhysicsOwnershipConfig.Assemblies.TriggerZone,
		"touch trigger assembly"
	)
	assertEqual(
		GameplayPhysicsOwnershipPolicy.ResolveWorldPartTier(mockPart),
		GameplayPhysicsOwnershipConfig.OwnershipTier.Server,
		"touch trigger requires server ownership"
	)

	mockPart.CanCollide = true
	mockPart.CanTouch = false
	mockPart._Attributes.SnareTrapId = "trap_a"
	assertEqual(
		GameplayPhysicsOwnershipPolicy.ResolveWorldPartAssembly(mockPart),
		GameplayPhysicsOwnershipConfig.Assemblies.SnareTrap,
		"snare trap attribute assembly"
	)

	mockPart._Attributes = { DistrictId = "Containment" }
	assertEqual(
		GameplayPhysicsOwnershipPolicy.ResolveWorldPartAssembly(mockPart),
		GameplayPhysicsOwnershipConfig.Assemblies.ContainmentStructure,
		"containment district assembly"
	)

	mockPart._Attributes = { BuildPreview = true }
	assertEqual(
		GameplayPhysicsOwnershipPolicy.ResolveWorldPartTier(mockPart),
		GameplayPhysicsOwnershipConfig.OwnershipTier.Client,
		"build preview is client owned"
	)
end

print("gameplay_physics_ownership_policy.spec.luau: all checks passed")
