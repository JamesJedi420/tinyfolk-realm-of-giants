--!strict

local MockPlayer = require("../tests/mocks/MockPlayer")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local routeAttributes: { [string]: any } = {
	ThroughGapReachAllowed = true,
	RouteType = "TraversalGap",
}

local routePart: any = {
	Name = "EscapeRoute_A",
	ClassName = "BasePart",
	Position = { x = 0, y = 0, z = 0 },
}

function routePart:IsA(className: string): boolean
	return className == "BasePart"
end

function routePart:GetAttribute(attributeName: string): any
	return routeAttributes[attributeName]
end

function routePart:SetAttribute(attributeName: string, value: any)
	routeAttributes[attributeName] = value
end

local escapeRoutesFolder: any = {
	ClassName = "Folder",
}

function escapeRoutesFolder:FindFirstChild(_childName: string): any
	return nil
end

function escapeRoutesFolder:GetDescendants(): { any }
	return { routePart }
end

local mapFolder: any = {
	ClassName = "Folder",
}

function mapFolder:FindFirstChild(childName: string): any
	if childName == "EscapeRoutes" then
		return escapeRoutesFolder
	end
	return nil
end

local workspaceService: any = {
	ClassName = "Workspace",
}

function workspaceService:FindFirstChild(childName: string): any
	if childName == "Map" then
		return mapFolder
	end
	return nil
end

local playersByUserId: { [number]: any } = {}

local playersService: any = {}
playersService.GetPlayerByUserId = function(userId: number)
	return playersByUserId[userId]
end

local replicatedStorageService: any = {
	WaitForChild = function(_name: string)
		return {
			WaitForChild = function(childName: string)
				if childName == "Config" then
					return {
						WaitForChild = function(configName: string)
							if configName == "RoleConfig" then
								return { Roles = { Giant = "Giant", Tinyfolk = "Tinyfolk" } }
							end
							if configName == "EscapeConfig" then
								return {
									EscapeRouteNamePrefix = "EscapeRoute",
									TriggerRadiusStuds = 10,
									RequestCooldownSeconds = 5,
									ThroughGapReachAllowedAttribute = "ThroughGapReachAllowed",
									RouteTypeAttribute = "RouteType",
									CrossingPhaseAttribute = "CrossingPhase",
									RequiredCrossingPhase = "MidCrossing",
									SafeZoneAttribute = "InSafeZone",
									SupportedThroughGapRouteTypes = { TraversalGap = true },
								}
							end
							return nil
						end,
					}
				end
				return nil
			end,
		}
	end,
}

local MockGame: any = {}
MockGame.GetService = function(serviceName: string)
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorageService
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	return nil
end

_G.game = MockGame
local EscapeService = require("../src/ServerScriptService/Services/EscapeService.server")(MockGame, {
	autoInitialize = true,
})

local function resetRouteDefaults()
	routeAttributes.ThroughGapReachAllowed = true
	routeAttributes.RouteType = "TraversalGap"
end

local function makeRequest(overrides: any?): any
	local request: any = {
		routeId = "EscapeRoute_A",
		lineOfSightCheck = function()
			return true
		end,
	}

	if overrides ~= nil then
		for key, value in overrides do
			request[key] = value
		end
	end

	return request
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer", { crossingPhase = "MidCrossing" })
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, true, "explicit allowed gap accepts valid reach")
end

do
	resetRouteDefaults()
	routeAttributes.ThroughGapReachAllowed = nil
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "missing allowlist metadata rejects")
end

do
	resetRouteDefaults()
	routeAttributes.RouteType = "OpenField"
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "unsupported route type rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "TinyfolkPlayer", { role = "Tinyfolk" })
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "non-Giant caller rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer", { role = "Giant" })
	local target = MockPlayer.new(2, "GiantTarget", { role = "Giant" })
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "invalid or non-Tinyfolk target rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer", { role = "Giant", hasRoot = false })
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "missing character/root rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer", { role = "Giant", positionZ = 0 })
	local target = MockPlayer.new(2, "TinyfolkPlayer", { positionZ = 40 })
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "out-of-range rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer", { inSafeZone = true })
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "safe-zone target rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer", { crossingPhase = "Idle" })
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "not-crossing target rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer", { crossingPhase = "MidCrossing" })
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, true, "valid crossing-phase target accepts")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest({
		lineOfSightCheck = function()
			return false
		end,
	}))
	assertEqual(result, false, "blocked LOS/collision callback rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, {
		worldPosition = { x = 0, y = 0, z = 5 },
		lineOfSightCheck = function()
			return true
		end,
	})
	assertEqual(result, false, "generic non-gap/world-position-only attempt rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, true, "TIN-185 block state is not required or implemented")
end
