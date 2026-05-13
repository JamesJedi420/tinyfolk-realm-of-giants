--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local SpecialistConfig = require(Config:WaitForChild("SpecialistConfig"))
local StationConfig = require(Config:WaitForChild("StationConfig"))
local ShrineConfig = require(Config:WaitForChild("ShrineConfig"))
local ProfilePersistenceGateway = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
	else require("./ProfilePersistenceGateway")

local REMOTES_FOLDER_NAME = "Remotes"
local ASSIGN_REMOTE_NAME = "SpecialistAssignRequest"
local CLEAR_REMOTE_NAME = "SpecialistClearRequest"
local DEBUG_REQUEST_REMOTE_NAME = "SpecialistDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "SpecialistDebugStateResponse"

local SPECIALIST_ROLE_ATTRIBUTE = "SpecialistRole"
local ASSIGNED_STATION_ID_ATTRIBUTE = "SpecialistAssignedStationId"
local LAST_ASSIGNMENT_REASON_ATTRIBUTE = "SpecialistLastAssignmentReason"
local LAST_ASSIGNED_AT_ATTRIBUTE = "SpecialistLastAssignedAt"
local PROFILE_SPECIALIST_PREFERENCE_KEY = "specialistPreference"
local PROFILE_SPECIALIST_ROLE_KEY = "specialistRole"

local HAULING_RESERVED_LABELS = {
	Hauler = true,
	Hauling = true,
}

type SpecialistState = {
	specialistRole: string,
	assignedStationId: string?,
	lastAssignmentReason: string,
	lastAssignedAt: number,
}

type AssignPayload = {
	specialistRole: string,
	assignedStationId: string?,
}

local specialistStateByUserId: { [number]: SpecialistState? } = {}
local lastRequestAtByUserId: { [number]: number? } = {}

local validSpecialistRoleSet: { [string]: boolean } = {
	[SpecialistConfig.SpecialistRoles.Woodcutter] = true,
	[SpecialistConfig.SpecialistRoles.Miner] = true,
	[SpecialistConfig.SpecialistRoles.Worshipper] = true,
}

local validPersistedSpecialistRoleSet: { [string]: boolean } = {
	[SpecialistConfig.SpecialistRoles.None] = true,
	[SpecialistConfig.SpecialistRoles.Woodcutter] = true,
	[SpecialistConfig.SpecialistRoles.Miner] = true,
	[SpecialistConfig.SpecialistRoles.Worshipper] = true,
}

local function debugLog(message: string)
	print(string.format("[SpecialistAssignmentService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[SpecialistAssignmentService] %s", message))
end

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	debugLog("Created ReplicatedStorage.Remotes folder")
	return folder
end

local function ensureRemoteEvent(parentFolder: Folder, remoteName: string): RemoteEvent
	local existing = parentFolder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = parentFolder
	debugLog(string.format("Created ReplicatedStorage.Remotes.%s", remoteName))
	return remote
end

local function isCoolingDown(userId: number): boolean
	local last = lastRequestAtByUserId[userId]
	if last == nil then
		return false
	end

	return (os.clock() - last) < SpecialistConfig.RequestCooldownSeconds
end

local function markRequest(userId: number)
	lastRequestAtByUserId[userId] = os.clock()
end

local function isTinyfolk(player: Player): boolean
	return player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk
end

local function startsWithPrefix(name: string, prefix: string): boolean
	return string.match(name, "^" .. prefix) ~= nil
end

local function validateAssignedStationForRole(specialistRole: string, assignedStationId: string?): (boolean, string)
	if specialistRole == SpecialistConfig.SpecialistRoles.Worshipper then
		if type(assignedStationId) ~= "string" then
			return false, "assigned_station_required_for_worshipper"
		end

		if not startsWithPrefix(assignedStationId, ShrineConfig.ShrineNamePrefix) then
			return false, "assigned_station_mismatch_for_worshipper"
		end

		return true, ""
	end

	if
		specialistRole == SpecialistConfig.SpecialistRoles.Woodcutter
		or specialistRole == SpecialistConfig.SpecialistRoles.Miner
	then
		if type(assignedStationId) ~= "string" then
			return false, "assigned_station_required_for_material_specialist"
		end

		local requiredRole = StationConfig.RequiredSpecialistRoleByStationId[assignedStationId]
		if type(requiredRole) ~= "string" then
			return false, "assigned_station_not_specialist_mapped"
		end

		if requiredRole ~= specialistRole then
			return false, "assigned_station_role_mismatch"
		end

		return true, ""
	end

	return false, "unsupported_specialist_role"
end

local function getOrCreateState(userId: number): SpecialistState
	local existing = specialistStateByUserId[userId]
	if existing then
		return existing
	end

	local created: SpecialistState = {
		specialistRole = SpecialistConfig.SpecialistRoles.None,
		assignedStationId = nil,
		lastAssignmentReason = SpecialistConfig.AssignmentReasons.Initial,
		lastAssignedAt = os.clock(),
	}
	specialistStateByUserId[userId] = created
	return created
end

local function applyPlayerStateAttributes(player: Player, state: SpecialistState)
	player:SetAttribute(SPECIALIST_ROLE_ATTRIBUTE, state.specialistRole)
	player:SetAttribute(ASSIGNED_STATION_ID_ATTRIBUTE, state.assignedStationId)
	player:SetAttribute(LAST_ASSIGNMENT_REASON_ATTRIBUTE, state.lastAssignmentReason)
	player:SetAttribute(LAST_ASSIGNED_AT_ATTRIBUTE, state.lastAssignedAt)
end

local function setState(player: Player, specialistRole: string, assignedStationId: string?, reason: string)
	local state = getOrCreateState(player.UserId)
	state.specialistRole = specialistRole
	state.assignedStationId = assignedStationId
	state.lastAssignmentReason = reason
	state.lastAssignedAt = os.clock()
	applyPlayerStateAttributes(player, state)
end

local function clearState(player: Player, reason: string)
	setState(player, SpecialistConfig.SpecialistRoles.None, nil, reason)
end

local function readStoredSpecialistRole(player: Player): string?
	local profileResult = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
	if not profileResult.ok then
		debugWarn(
			string.format(
				"Specialist role read failed userId=%d reason=%s",
				player.UserId,
				tostring(profileResult.reason)
			)
		)
		return nil
	end

	if type(profileResult.data) ~= "table" then
		return nil
	end

	local specialistPreference = profileResult.data[PROFILE_SPECIALIST_PREFERENCE_KEY]
	if type(specialistPreference) ~= "table" then
		return nil
	end

	local specialistRole = specialistPreference[PROFILE_SPECIALIST_ROLE_KEY]
	if type(specialistRole) == "string" and validPersistedSpecialistRoleSet[specialistRole] == true then
		return specialistRole
	end

	if specialistRole ~= nil then
		debugWarn(
			string.format(
				"Specialist role ignored userId=%d reason=invalid_specialist_role value=%s",
				player.UserId,
				tostring(specialistRole)
			)
		)
	end

	return nil
end

local function persistSpecialistRole(player: Player, specialistRole: string)
	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local nextData = currentData
		if type(nextData[PROFILE_SPECIALIST_PREFERENCE_KEY]) ~= "table" then
			nextData[PROFILE_SPECIALIST_PREFERENCE_KEY] = {}
		end

		nextData[PROFILE_SPECIALIST_PREFERENCE_KEY][PROFILE_SPECIALIST_ROLE_KEY] = specialistRole
		return nextData
	end)

	if not updateResult.ok then
		debugWarn(
			string.format(
				"Specialist role update failed userId=%d reason=%s",
				player.UserId,
				tostring(updateResult.reason)
			)
		)
	end
end

local function snapshotForPlayer(player: Player)
	local state = getOrCreateState(player.UserId)
	return {
		userId = player.UserId,
		role = player:GetAttribute("Role"),
		isTinyfolk = isTinyfolk(player),
		specialistRole = state.specialistRole,
		assignedStationId = state.assignedStationId,
		lastAssignmentReason = state.lastAssignmentReason,
		lastAssignedAt = state.lastAssignedAt,
	}
end

local function rejectAssign(player: Player, reason: string)
	debugWarn(string.format("Rejected SpecialistAssignRequest userId=%d reason=%s", player.UserId, reason))
end

local function rejectClear(player: Player, reason: string)
	debugWarn(string.format("Rejected SpecialistClearRequest userId=%d reason=%s", player.UserId, reason))
end

local function rejectDebug(player: Player, reason: string)
	debugWarn(string.format("Rejected SpecialistDebugStateRequest userId=%d reason=%s", player.UserId, reason))
end

local remotesFolder = ensureRemotesFolder()
local assignRemote = ensureRemoteEvent(remotesFolder, ASSIGN_REMOTE_NAME)
local clearRemote = ensureRemoteEvent(remotesFolder, CLEAR_REMOTE_NAME)
local debugRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
local debugResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)

assignRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if isCoolingDown(player.UserId) then
		rejectAssign(player, "request_cooldown")
		return
	end

	markRequest(player.UserId)

	if type(payload) ~= "table" then
		rejectAssign(player, "malformed_payload")
		return
	end

	local parsed = payload :: AssignPayload
	if type(parsed.specialistRole) ~= "string" then
		rejectAssign(player, "malformed_payload")
		return
	end

	if not isTinyfolk(player) then
		rejectAssign(player, "requester_not_tinyfolk")
		return
	end

	if HAULING_RESERVED_LABELS[parsed.specialistRole] == true then
		rejectAssign(player, "hauling_not_specialist_role")
		return
	end

	if not validSpecialistRoleSet[parsed.specialistRole] then
		rejectAssign(player, "invalid_specialist_role")
		return
	end

	if parsed.assignedStationId ~= nil and type(parsed.assignedStationId) ~= "string" then
		rejectAssign(player, "malformed_payload")
		return
	end

	local stationValid, stationError = validateAssignedStationForRole(parsed.specialistRole, parsed.assignedStationId)
	if not stationValid then
		rejectAssign(player, stationError)
		return
	end

	local state = getOrCreateState(player.UserId)
	if state.specialistRole ~= SpecialistConfig.SpecialistRoles.None then
		if state.specialistRole == parsed.specialistRole and state.assignedStationId == parsed.assignedStationId then
			rejectAssign(player, string.format("already_assigned specialistRole=%s", state.specialistRole))
			return
		end

		local previousSpecialistRole = state.specialistRole
		local previousAssignedStationId = state.assignedStationId

		setState(player, parsed.specialistRole, parsed.assignedStationId, SpecialistConfig.AssignmentReasons.Assigned)
		persistSpecialistRole(player, parsed.specialistRole)
		debugLog(
			string.format(
				"Accepted SpecialistAssignRequest reassigned userId=%d fromSpecialistRole=%s fromAssignedStationId=%s toSpecialistRole=%s toAssignedStationId=%s",
				player.UserId,
				previousSpecialistRole,
				tostring(previousAssignedStationId),
				parsed.specialistRole,
				tostring(parsed.assignedStationId)
			)
		)
		return
	end

	setState(player, parsed.specialistRole, parsed.assignedStationId, SpecialistConfig.AssignmentReasons.Assigned)
	persistSpecialistRole(player, parsed.specialistRole)
	debugLog(
		string.format(
			"Accepted SpecialistAssignRequest userId=%d specialistRole=%s assignedStationId=%s",
			player.UserId,
			parsed.specialistRole,
			tostring(parsed.assignedStationId)
		)
	)
end)

clearRemote.OnServerEvent:Connect(function(player: Player)
	if isCoolingDown(player.UserId) then
		rejectClear(player, "request_cooldown")
		return
	end

	markRequest(player.UserId)

	local state = getOrCreateState(player.UserId)
	if state.specialistRole == SpecialistConfig.SpecialistRoles.None then
		rejectClear(player, "not_assigned")
		return
	end

	clearState(player, SpecialistConfig.AssignmentReasons.ClearedManual)
	persistSpecialistRole(player, SpecialistConfig.SpecialistRoles.None)
	debugLog(string.format("Accepted SpecialistClearRequest userId=%d", player.UserId))
end)

debugRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if payload ~= nil then
		rejectDebug(player, "malformed_payload")
		return
	end

	local snapshot = snapshotForPlayer(player)
	debugResponseRemote:FireClient(player, snapshot)
	debugLog(
		string.format(
			"Sent specialist debug state userId=%d specialistRole=%s",
			player.UserId,
			tostring(snapshot.specialistRole)
		)
	)
end)

local function setupPlayer(player: Player)
	local state = getOrCreateState(player.UserId)
	local storedSpecialistRole = readStoredSpecialistRole(player)
	if storedSpecialistRole ~= nil then
		state.specialistRole = storedSpecialistRole
	end
	applyPlayerStateAttributes(player, state)

	player:GetAttributeChangedSignal("Role"):Connect(function()
		if isTinyfolk(player) then
			return
		end

		local current = getOrCreateState(player.UserId)
		if current.specialistRole == SpecialistConfig.SpecialistRoles.None then
			return
		end

		clearState(player, SpecialistConfig.AssignmentReasons.ClearedRoleChange)
		debugLog(string.format("Cleared specialist assignment due to role change userId=%d", player.UserId))
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
	specialistStateByUserId[player.UserId] = nil
end)

debugLog("SpecialistAssignmentService initialized")
