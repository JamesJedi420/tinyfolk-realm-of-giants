--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local EscapeConfig = require(Config:WaitForChild("EscapeConfig"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local TinyfolkHubConfig = require(Config:WaitForChild("TinyfolkHubConfig"))
local RealmAssignmentProfileState = require(GiantRealm:WaitForChild("RealmAssignmentProfileState"))
local RealmTransferState = require(GiantRealm:WaitForChild("RealmTransferState"))
local TinyfolkHubState = require(Shared:WaitForChild("TinyfolkHub"):WaitForChild("TinyfolkHubState"))

local globalEnv: any = getfenv()

local assignmentApiOverride: any = nil

local diagnostics = {
	syncAttempts = 0,
	syncSucceeded = 0,
	syncFailed = 0,
	lastReason = "none",
	lastUserId = nil,
}

local function cloneDiagnostics(): any
	return {
		syncAttempts = diagnostics.syncAttempts,
		syncSucceeded = diagnostics.syncSucceeded,
		syncFailed = diagnostics.syncFailed,
		lastReason = diagnostics.lastReason,
		lastUserId = diagnostics.lastUserId,
	}
end

local function getGlobalTable(name: string): any?
	local fromEnv = rawget(globalEnv, name)
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, name)
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function getAssignmentApi(): any?
	if assignmentApiOverride ~= nil then
		return assignmentApiOverride
	end
	return getGlobalTable("_RealmTransferAssignmentService_QueryAPI")
end

local function getRoleName(player: Player): string?
	local role = player:GetAttribute("Role")
	if type(role) == "string" then
		return role
	end
	return nil
end

local function resolveAssignmentSnapshot(userId: number): (string, any?)
	local api = getAssignmentApi()
	if type(api) == "table" and type(api.GetAssignmentSnapshot) == "function" then
		local ok, snapshotResult = pcall(function()
			return api.GetAssignmentSnapshot(userId)
		end)
		if ok and type(snapshotResult) == "table" and snapshotResult.accepted == true then
			local assignment = snapshotResult.assignment
			if type(assignment) == "table" and type(assignment.locationCategory) == "string" then
				return assignment.locationCategory, assignment
			end
		end
	end

	return RealmAssignmentProfileState.LocationCategory.SharedHub, nil
end

local function projectHubAttributes(player: Player, presence: TinyfolkHubState.HubPresenceSnapshot)
	player:SetAttribute(TinyfolkHubConfig.LocationCategoryAttribute, presence.locationCategory)
	player:SetAttribute(TinyfolkHubConfig.InHubAttribute, presence.inHub)

	if presence.safeZoneProtected then
		player:SetAttribute(EscapeConfig.SafeZoneAttribute, true)
		player:SetAttribute(EscapeConfig.SafeZoneTypeAttribute, EscapeConfig.SafeZoneTypes.SharedHub)
		player:SetAttribute(EscapeConfig.SafeZoneProtectionEndsAtAttribute, nil)
		return
	end

	player:SetAttribute(EscapeConfig.SafeZoneAttribute, false)
	player:SetAttribute(EscapeConfig.SafeZoneTypeAttribute, nil)
	player:SetAttribute(EscapeConfig.SafeZoneProtectionEndsAtAttribute, nil)
end

local function ensureSharedHubAssignment(userId: number): (boolean, string)
	local api = getAssignmentApi()
	if type(api) ~= "table" or type(api.GetAssignmentSnapshot) ~= "function" then
		return true, "assignment_api_unavailable"
	end

	local snapshotResult = api.GetAssignmentSnapshot(userId)
	if type(snapshotResult) ~= "table" then
		return false, "assignment_snapshot_invalid"
	end

	local assignment = snapshotResult.assignment
	if type(assignment) == "table" then
		if assignment.locationCategory == RealmAssignmentProfileState.LocationCategory.GiantRealm then
			return true, "assignment_giant_realm_preserved"
		end
		if assignment.locationCategory == RealmAssignmentProfileState.LocationCategory.TransferInFlight then
			return true, "assignment_transfer_in_flight_preserved"
		end
	end

	if type(api.ApplyTransition) ~= "function" then
		return true, "assignment_transition_unavailable"
	end

	local transitionResult = api.ApplyTransition(userId, {
		operation = RealmTransferState.Operations.SetSharedHub,
		now = os.time(),
	})
	if type(transitionResult) ~= "table" or transitionResult.accepted ~= true then
		local reason = if type(transitionResult) == "table" and type(transitionResult.reason) == "string"
			then transitionResult.reason
			else "assignment_transition_failed"
		return false, reason
	end

	return true, "accepted"
end

local function syncHubPresenceForPlayer(player: Player, trigger: string?): (boolean, string)
	diagnostics.syncAttempts += 1
	diagnostics.lastUserId = player.UserId

	local roleName = getRoleName(player)
	if roleName ~= RoleConfig.Roles.Tinyfolk then
		diagnostics.syncFailed += 1
		diagnostics.lastReason = "role_not_tinyfolk"
		return false, "role_not_tinyfolk"
	end

	local locationCategory = resolveAssignmentSnapshot(player.UserId)
	local presence = TinyfolkHubState.BuildHubPresenceSnapshot(roleName, locationCategory)
	projectHubAttributes(player, presence)

	diagnostics.syncSucceeded += 1
	diagnostics.lastReason = if type(trigger) == "string" then trigger else "accepted"
	return true, diagnostics.lastReason
end

local function onTinyfolkRoleLocked(player: Player)
	local assignmentOk, assignmentReason = ensureSharedHubAssignment(player.UserId)
	if assignmentOk ~= true then
		warn(
			string.format(
				"[TinyfolkHubService] Shared hub assignment failed userId=%d reason=%s",
				player.UserId,
				assignmentReason
			)
		)
	end
	syncHubPresenceForPlayer(player, "role_locked")
end

local function bindPlayer(player: Player)
	player:GetAttributeChangedSignal("Role"):Connect(function()
		if player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk and player:GetAttribute("RoleLocked") == true then
			onTinyfolkRoleLocked(player)
		end
	end)

	player.CharacterAdded:Connect(function(_character: Instance)
		if player:GetAttribute("Role") ~= RoleConfig.Roles.Tinyfolk then
			return
		end
		syncHubPresenceForPlayer(player, "character_added")
	end)

	if player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk and player:GetAttribute("RoleLocked") == true then
		onTinyfolkRoleLocked(player)
	elseif player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk then
		syncHubPresenceForPlayer(player, "setup")
	end
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in Players:GetPlayers() do
	bindPlayer(player)
end

globalEnv._TinyfolkHubService_QueryAPI = {
	SyncHubPresenceForUserId = function(userId: number): any
		for _, player in Players:GetPlayers() do
			if player.UserId == userId then
				local accepted, reason = syncHubPresenceForPlayer(player, "query_api")
				return {
					accepted = accepted,
					reason = reason,
					presence = TinyfolkHubState.BuildHubPresenceSnapshot(
						getRoleName(player),
						resolveAssignmentSnapshot(userId)
					),
				}
			end
		end
		return {
			accepted = false,
			reason = "player_not_found",
		}
	end,
	ResolveActivityEligibility = function(userId: number, activity: string): any
		for _, player in Players:GetPlayers() do
			if player.UserId == userId then
				local locationCategory = resolveAssignmentSnapshot(userId)
				local accepted, reason =
					TinyfolkHubState.ResolveActivityEligibility(activity, getRoleName(player), locationCategory)
				return {
					accepted = accepted,
					reason = reason,
					locationCategory = locationCategory,
				}
			end
		end
		return {
			accepted = false,
			reason = "player_not_found",
		}
	end,
	GetDiagnostics = function(): any
		return cloneDiagnostics()
	end,
	ConfigureForTests = function(config: any?)
		local configAny: any = if type(config) == "table" then config else {}
		assignmentApiOverride = configAny.assignmentApi
	end,
	ResetForTests = function()
		assignmentApiOverride = nil
		diagnostics = {
			syncAttempts = 0,
			syncSucceeded = 0,
			syncFailed = 0,
			lastReason = "none",
			lastUserId = nil,
		}
	end,
}

if type(_G) == "table" then
	rawset(_G, "_TinyfolkHubService_QueryAPI", globalEnv._TinyfolkHubService_QueryAPI)
end

print("[TinyfolkHubService] initialized")

return globalEnv._TinyfolkHubService_QueryAPI
