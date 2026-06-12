--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local configFolder = {
	WaitForChild = function(_self: any, childName: string): any
		if childName == "GameplayPhysicsOwnershipConfig" then
			return "../../ReplicatedStorage/Shared/Config/GameplayPhysicsOwnershipConfig"
		end
		error("missing config " .. childName)
	end,
}

local physicsFolder = {
	WaitForChild = function(_self: any, childName: string): any
		if childName == "GameplayPhysicsOwnershipPolicy" then
			return "../../ReplicatedStorage/Shared/Physics/GameplayPhysicsOwnershipPolicy"
		end
		error("missing physics " .. childName)
	end,
}

local sharedFolder = {
	WaitForChild = function(_self: any, childName: string): any
		if childName == "Config" then
			return configFolder
		end
		if childName == "Physics" then
			return physicsFolder
		end
		error("missing shared " .. childName)
	end,
}

game = {
	GetService = function(_self: any, serviceName: string): any
		if serviceName == "ReplicatedStorage" then
			return {
				WaitForChild = function(_root: any, childName: string): any
					if childName == "Shared" then
						return sharedFolder
					end
					error("missing replicated storage child " .. childName)
				end,
			}
		end
		error("unsupported service " .. serviceName)
	end,
} :: any

local function makePart(name: string): any
	return {
		Name = name,
		ClassName = "Part",
		CanCollide = true,
		CanTouch = false,
		_NetworkOwner = "unset",
		_Attributes = {},
		GetAttribute = function(self: any, attributeName: string): any
			return self._Attributes[attributeName]
		end,
		SetAttribute = function(self: any, attributeName: string, value: any)
			self._Attributes[attributeName] = value
		end,
		SetNetworkOwner = function(self: any, owner: any)
			if owner == nil then
				self._NetworkOwner = "server"
			else
				self._NetworkOwner = owner
			end
		end,
	}
end

local function makeCharacter(): any
	local root = makePart("HumanoidRootPart")
	local head = makePart("Head")
	return {
		GetDescendants = function(): { any }
			return { root, head }
		end,
	}
end

local PhysicsOwnershipService = require("../src/ServerScriptService/Services/PhysicsOwnershipService")
PhysicsOwnershipService.ResetForTests()

local carriedPlayer: any = {
	UserId = 15001,
	Character = makeCharacter(),
	_Attributes = {
		Role = "Tinyfolk",
		CaptureActive = false,
		CarriedState = "Carried",
		HeldByUserId = 15002,
	},
	GetAttribute = function(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end,
	SetAttribute = function(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end,
}

PhysicsOwnershipService.RefreshPlayerCharacter(carriedPlayer)
assertEqual(
	carriedPlayer._Attributes.GameplayPhysicsOwnershipCharacterAssembly,
	"CarriedTinyfolk",
	"carried player assembly attribute"
)
assertEqual(carriedPlayer._Attributes.GameplayPhysicsOwnershipTier, "Server", "carried player tier attribute")
for _, part in carriedPlayer.Character:GetDescendants() do
	assertEqual(part._NetworkOwner, "server", "carried character parts server owned")
	assertEqual(part._Attributes.GameplayPhysicsOwnershipTier, "Server", "carried part tier debug attribute")
end

local giantPlayer: any = {
	UserId = 15002,
	Character = makeCharacter(),
	_Attributes = {
		Role = "Giant",
		CaptureActive = false,
		CarriedState = "Free",
		HeldTargetUserId = 15001,
	},
	GetAttribute = function(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end,
	SetAttribute = function(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end,
}

PhysicsOwnershipService.RefreshPlayerCharacter(giantPlayer)
assertEqual(
	giantPlayer._Attributes.GameplayPhysicsOwnershipCharacterAssembly,
	"CarryingGiant",
	"carrying giant assembly attribute"
)
assertTrue(PhysicsOwnershipService.RequiresServerOwnershipForPlayer(giantPlayer), "carrying giant requires server")

local freePlayer: any = {
	UserId = 15003,
	Character = makeCharacter(),
	_Attributes = {
		Role = "Tinyfolk",
		CaptureActive = false,
		CarriedState = "Free",
	},
	GetAttribute = function(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end,
	SetAttribute = function(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end,
}

PhysicsOwnershipService.RefreshPlayerCharacter(freePlayer)
assertEqual(freePlayer._Attributes.GameplayPhysicsOwnershipTier, "Automatic", "free player automatic tier")
for _, part in freePlayer.Character:GetDescendants() do
	assertEqual(part._NetworkOwner, freePlayer, "free character parts restore automatic client ownership")
end

local trapPart = makePart("SnareTrapPart")
trapPart._Attributes.SnareTrapId = "trap_runtime_a"
PhysicsOwnershipService.ApplyGroupToPart(trapPart, nil)
assertEqual(trapPart._NetworkOwner, "server", "snare trap part server owned")
assertEqual(trapPart._Attributes.GameplayPhysicsOwnershipAssembly, "SnareTrap", "snare trap assembly attribute")

local triggerPart = makePart("EscapeTrigger")
triggerPart.CanCollide = false
triggerPart.CanTouch = true
PhysicsOwnershipService.ApplyGroupToPart(triggerPart, nil)
assertEqual(triggerPart._NetworkOwner, "server", "trigger zone server owned")

local mapRoot: any = {
	GetDescendants = function(): { any }
		return { trapPart, triggerPart }
	end,
}

local assignedCount = PhysicsOwnershipService.AssignWorldPartsUnderRoot(mapRoot)
assertEqual(assignedCount, 2, "assigns two map parts")

local diagnostics = PhysicsOwnershipService.GetDiagnostics()
assertTrue(diagnostics.partsEnforced >= 4, "tracks enforced parts")

print("physics_ownership_service_runtime_entrypoint.spec.luau: all checks passed")
