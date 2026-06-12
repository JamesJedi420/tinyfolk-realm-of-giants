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

local _registeredGroups: { string } = {}
local collidablePairs: { [string]: boolean } = {}

local mockPhysicsService = {
	RegisterCollisionGroup = function(_self: any, groupName: string)
		table.insert(_registeredGroups, groupName)
	end,
	CollisionGroupSetCollidable = function(_self: any, groupA: string, groupB: string, collidable: boolean)
		collidablePairs[groupA .. "|" .. groupB] = collidable
		collidablePairs[groupB .. "|" .. groupA] = collidable
	end,
}

local configFolder = {
	WaitForChild = function(_self: any, childName: string): any
		if childName == "GameplayCollisionGroupConfig" then
			return "../../ReplicatedStorage/Shared/Config/GameplayCollisionGroupConfig"
		end
		error("missing config " .. childName)
	end,
}

local physicsFolder = {
	WaitForChild = function(_self: any, childName: string): any
		if childName == "GameplayCollisionGroupMatrix" then
			return "../../ReplicatedStorage/Shared/Physics/GameplayCollisionGroupMatrix"
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

local CollisionGroupService = require("../src/ServerScriptService/Services/CollisionGroupService")
CollisionGroupService.ResetForTests()

local registered, reason = CollisionGroupService.RegisterMatrix(mockPhysicsService)
assertTrue(registered, "matrix registers with mock physics service")
assertEqual(reason, nil, "matrix registration reason nil")
assertTrue(CollisionGroupService.IsMatrixRegistered(), "matrix marked registered")

local diagnostics = CollisionGroupService.GetRegistrationDiagnostics()
assertEqual(#diagnostics.registeredGroups, 10, "registers ten gameplay groups")
assertTrue(diagnostics.appliedPairs >= 55, "applies full symmetric pair matrix")

assertEqual(
	CollisionGroupService.GetRelation("Gameplay_Giant", "Gameplay_CarriedTinyfolk"),
	"ignore",
	"runtime relation lookup giant carried"
)
assertEqual(
	CollisionGroupService.GetRelation("Gameplay_Giant", "Gameplay_Tinyfolk"),
	"collide",
	"runtime relation lookup giant tinyfolk"
)

local function makePart(name: string): any
	return {
		Name = name,
		ClassName = "Part",
		CollisionGroup = "Default",
		CanCollide = true,
		CanTouch = false,
		_Attributes = {},
		GetAttribute = function(self: any, attributeName: string): any
			return self._Attributes[attributeName]
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

local giantPlayer: any = {
	UserId = 14901,
	Character = makeCharacter(),
	_Attributes = {
		Role = "Giant",
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

CollisionGroupService.RefreshPlayerCharacter(giantPlayer)
assertEqual(giantPlayer._Attributes.GameplayCollisionGroup, "Gameplay_Giant", "giant player group attribute")
for _, part in giantPlayer.Character:GetDescendants() do
	assertEqual(part.CollisionGroup, "Gameplay_Giant", "giant character parts assigned")
end

giantPlayer._Attributes.CarriedState = "Carried"
CollisionGroupService.RefreshPlayerCharacter(giantPlayer)
assertEqual(giantPlayer._Attributes.GameplayCollisionGroup, "Gameplay_CarriedTinyfolk", "carried overrides role")

local cachedMapDescendants: { any }? = nil

local mapRoot: any = {
	GetDescendants = function(): { any }
		if cachedMapDescendants ~= nil then
			return cachedMapDescendants
		end

		local escapeRoute = makePart("EscapeRoute_A")
		escapeRoute._Attributes.TinyfolkOnlyRoute = true
		local trigger = makePart("ControlZone")
		trigger.CanCollide = false
		trigger.CanTouch = true
		cachedMapDescendants = { escapeRoute, trigger }
		return cachedMapDescendants
	end,
}

local assignedCount = CollisionGroupService.AssignWorldPartsUnderRoot(mapRoot)
assertEqual(assignedCount, 2, "assigns two map parts")
local descendants = mapRoot:GetDescendants()
local escapeRoute = descendants[1]
local trigger = descendants[2]
assertEqual(escapeRoute.CollisionGroup, "Gameplay_TinyfolkRoute", "escape route gets tinyfolk route group")
assertEqual(trigger.CollisionGroup, "Gameplay_TriggerZone", "control zone gets trigger group")

print("collision_group_service_runtime_entrypoint.spec.luau: all checks passed")
