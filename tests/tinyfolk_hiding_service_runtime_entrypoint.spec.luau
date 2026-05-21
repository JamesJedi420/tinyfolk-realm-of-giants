--!nocheck
-- Minimal Vector3 implementation for test
local globalEnv = getfenv()

local Vector3 = {}
Vector3.__index = Vector3
function Vector3.new(x, y, z)
	return setmetatable({ x = x, y = y, z = z }, Vector3)
end
function Vector3.__sub(a, b)
	return Vector3.new(a.x - b.x, a.y - b.y, a.z - b.z)
end
function Vector3:Magnitude()
	return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
end
setmetatable(Vector3, {
	__call = function(_, ...)
		return Vector3.new(...)
	end,
})
globalEnv.Vector3 = Vector3

local HidingConfig = {
	HidingZonePath = { "Map", "HidingZones" },
	HidingDurationSeconds = 20,
	HidingRevealProximityStuds = 10,
	HidingEntryCooldownSeconds = 5,
	HidingExitCooldownSeconds = 3,
}

local HidingState = require("../src/ReplicatedStorage/Shared/TinyfolkHiding/HidingState")

globalEnv._TinyfolkHiding_TestModules = { HidingConfig = HidingConfig, HidingState = HidingState }

local Players = {}
local playerList = {}
function Players:GetPlayers()
	return playerList
end
function Players:GetPlayerByUserId(userId)
	for _, p in ipairs(playerList) do
		if p.UserId == userId then
			return p
		end
	end
	return nil
end

local function makePlayer(userId, role)
	return {
		UserId = userId,
		GetAttribute = function(_self, attr)
			if attr == "Role" then
				return role
			end
			return nil
		end,
	}
end

table.insert(playerList, makePlayer(101, "Tinyfolk"))
table.insert(playerList, makePlayer(102, "Giant"))

-- Workspace mock with FindFirstChild chain for HidingZonePath
local sizeVec = Vector3.new(10, 0, 0)
function sizeVec:Magnitude()
	return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)
end
local zonePart = {
	Name = "ZoneA",
	IsA = function()
		return true
	end,
	Position = Vector3.new(0, 0, 0),
	Size = sizeVec,
}
local hidingZonesNode = {
	GetChildren = function()
		return { zonePart }
	end,
}
local mapNode = {
	FindFirstChild = function(_self, name)
		if name == "HidingZones" then
			return hidingZonesNode
		end
		return nil
	end,
}
local workspaceMock = {
	FindFirstChild = function(_self, name)
		if name == "Map" and globalEnv._zoneReady == true then
			return mapNode
		end
		return nil
	end,
}

globalEnv._zoneReady = false

globalEnv.game = {
	GetService = function(_, name)
		if name == "Players" then
			return Players
		end
		if name == "ReplicatedStorage" then
			return {
				WaitForChild = function()
					return {
						WaitForChild = function()
							return {}
						end,
					}
				end,
			}
		end
		if name == "Workspace" then
			return workspaceMock
		end
		return nil
	end,
}

require("../src/ServerScriptService/Services/TinyfolkHidingService.server")
local api = globalEnv._TinyfolkHiding_QueryAPI

local now = 100
globalEnv._zoneReady = true

local lateOk, lateReason = api.CanEnterHiding(101, "ZoneA", now)
assert(lateOk == true, "CanEnterHiding refreshes late-loaded zones")
assert(lateReason == "accepted", "CanEnterHiding late-loaded zone reason accepted")

local zones = api.GetHidingZones()
assert(#zones == 1 and zones[1].id == "ZoneA", "zone discovery")

local ok, _reason = api.CanEnterHiding(101, "ZoneA", now)
assert(ok == true, "Tinyfolk can enter hiding")

local result = api.RequestEnterHiding(101, "ZoneA", now)
assert(result.accepted == true, "RequestEnterHiding accepted")

local snapshot = api.GetHidingSnapshot(101, now)
assert(snapshot.isHiding == true, "snapshot isHiding after entry")

local reveal = api.ProbeReveals(101, now + 21, { Vector3.new(1, 0, 0) })
assert(reveal.shouldReveal == true, "giant proximity triggers reveal")

local exit = api.RequestExitHiding(101, now + 22, "manual")
assert(exit.accepted == false, "RequestExitHiding rejects after reveal-driven exit")
assert(exit.reason == "not_hiding", "RequestExitHiding reports not_hiding after reveal-driven exit")

print("tinyfolk_hiding_service_runtime_entrypoint: all checks passed")
