--!nocheck

local globalEnv: any = getfenv()
local _game = rawget(globalEnv, "game") or game
local Players = _game:GetService("Players")
local Workspace = _game:GetService("Workspace")

type HidingZone = {
	id: string,
	position: any,
	radius: number,
	ref: any,
}

local HidingConfig, HidingState
if rawget(globalEnv, "_TinyfolkHiding_TestModules") then
	HidingConfig = globalEnv._TinyfolkHiding_TestModules.HidingConfig
	HidingState = globalEnv._TinyfolkHiding_TestModules.HidingState
else
	HidingConfig = require(_game:GetService("ReplicatedStorage").Shared.Config.HidingConfig)
	HidingState = require(_game:GetService("ReplicatedStorage").Shared.TinyfolkHiding.HidingState)
end

local hidingZones: { HidingZone } = {}
local hidingStateByUserId: { [number]: any } = {}
local lastEntryAtByUserId: { [number]: number } = {}
local lastExitAtByUserId: { [number]: number } = {}

local function resolveZoneRadius(sizeValue: any): number
	if sizeValue == nil then
		return 0
	end

	local magnitude = sizeValue.Magnitude
	if
		type(magnitude) == "number"
		and magnitude == magnitude
		and magnitude ~= math.huge
		and magnitude ~= -math.huge
	then
		return math.max(magnitude / 2, 0)
	end

	local x = sizeValue.X or sizeValue.x
	local y = sizeValue.Y or sizeValue.y
	local z = sizeValue.Z or sizeValue.z
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return 0
	end

	return math.sqrt(x * x + y * y + z * z) / 2
end

local function discoverHidingZones()
	hidingZones = {}
	local node = Workspace
	for _, seg in ipairs(HidingConfig.HidingZonePath) do
		node = node:FindFirstChild(seg)
		if not node then
			return
		end
	end
	if node and typeof(node.GetChildren) == "function" then
		for _, part in ipairs(node:GetChildren()) do
			if part:IsA("BasePart") then
				table.insert(hidingZones, {
					id = part.Name,
					position = part.Position,
					radius = resolveZoneRadius(part.Size),
					ref = part,
				})
			end
		end
	end
end
discoverHidingZones()

local function getZoneById(zoneId: string): HidingZone?
	for _, zone in ipairs(hidingZones) do
		if zone.id == zoneId then
			return zone
		end
	end

	-- Late-loading map hierarchies can make startup discovery stale; retry once on miss.
	discoverHidingZones()
	for _, zone in ipairs(hidingZones) do
		if zone.id == zoneId then
			return zone
		end
	end
	return nil
end

local function canEnterHiding(userId: number, zoneId: string, at: number)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return false, "player_not_found"
	end
	if player:GetAttribute("Role") ~= "Tinyfolk" then
		return false, "not_tinyfolk"
	end
	local zone = getZoneById(zoneId)
	if not zone then
		return false, "zone_not_found"
	end
	local lastExit = lastExitAtByUserId[userId]
	if lastExit and (at - lastExit) < HidingConfig.HidingEntryCooldownSeconds then
		return false, "entry_cooldown"
	end
	local state = hidingStateByUserId[userId]
	if state and state.isHiding then
		return false, "already_hiding"
	end
	return true, "accepted"
end

local function requestEnterHiding(userId: number, zoneId: string, at: number)
	local ok, reason = canEnterHiding(userId, zoneId, at)
	if not ok then
		return { accepted = false, reason = reason }
	end
	local state = hidingStateByUserId[userId] or HidingState.new()
	state:Enter(zoneId, at, HidingConfig.HidingDurationSeconds)
	hidingStateByUserId[userId] = state
	lastEntryAtByUserId[userId] = at
	return { accepted = true, reason = "accepted", snapshot = state:GetSnapshot(at) }
end

local function requestExitHiding(userId: number, at: number, reason: string?)
	local state = hidingStateByUserId[userId]
	if not state or not state.isHiding then
		return { accepted = false, reason = "not_hiding" }
	end
	state:Exit(reason or "manual", at)
	lastExitAtByUserId[userId] = at
	return { accepted = true, reason = reason or "manual", snapshot = state:GetSnapshot(at) }
end

local function probeReveals(userId: number, at: number, giantPositions: { Vector3 })
	local state = hidingStateByUserId[userId]
	if not state or not state.isHiding then
		return { shouldReveal = false, reason = nil, snapshot = nil }
	end
	local zone = getZoneById(state.zoneId :: string)
	if not zone then
		return { shouldReveal = true, reason = "zone_missing", snapshot = state:GetSnapshot(at) }
	end
	local shouldReveal, reason =
		state:ProbeReveal(at, HidingConfig.HidingRevealProximityStuds, giantPositions, zone.position)
	if shouldReveal then
		requestExitHiding(userId, at, reason)
	end
	return { shouldReveal = shouldReveal, reason = reason, snapshot = state:GetSnapshot(at) }
end

local function getHidingSnapshot(userId: number, at: number)
	local state = hidingStateByUserId[userId]
	if not state then
		return nil
	end
	return state:GetSnapshot(at)
end

globalEnv._TinyfolkHiding_QueryAPI = {
	GetHidingZones = function()
		discoverHidingZones()
		local zones = {}
		for _, z in ipairs(hidingZones) do
			table.insert(zones, { id = z.id, position = z.position, radius = z.radius })
		end
		return zones
	end,
	IsPlayerHiding = function(userId: number)
		local state = hidingStateByUserId[userId]
		return state and state.isHiding or false
	end,
	CanEnterHiding = canEnterHiding,
	RequestEnterHiding = requestEnterHiding,
	RequestExitHiding = requestExitHiding,
	ProbeReveals = probeReveals,
	GetHidingSnapshot = getHidingSnapshot,
}

if Players.PlayerRemoving and typeof(Players.PlayerRemoving.Connect) == "function" then
	Players.PlayerRemoving:Connect(function(player)
		hidingStateByUserId[player.UserId] = nil
		lastEntryAtByUserId[player.UserId] = nil
		lastExitAtByUserId[player.UserId] = nil
	end)
end
