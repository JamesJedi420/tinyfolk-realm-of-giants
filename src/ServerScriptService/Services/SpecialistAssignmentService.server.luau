--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Specialist = Shared:WaitForChild("Specialist")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local SpecialistConfig = require(Config:WaitForChild("SpecialistConfig"))
local StationConfig = require(Config:WaitForChild("StationConfig"))
local ShrineConfig = require(Config:WaitForChild("ShrineConfig"))
local SpecialistPreferenceProfileState = if script ~= nil and script.Parent ~= nil
	then require(Specialist:WaitForChild("SpecialistPreferenceProfileState"))
	else require("../../ReplicatedStorage/Shared/Specialist/SpecialistPreferenceProfileState")
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
local PROFILE_ASSIGNED_STATION_ID_KEY = "assignedStationId"
local PROFILE_LAST_ASSIGNED_AT_KEY = "lastAssignedAt"

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
	[SpecialistConfig.SpecialistRoles.Farmer] = true,
	[SpecialistConfig.SpecialistRoles.Worshipper] = true,
}

local validPersistedSpecialistRoleSet: { [string]: boolean } = {
	[SpecialistConfig.SpecialistRoles.None] = true,
	[SpecialistConfig.SpecialistRoles.Woodcutter] = true,
	[SpecialistConfig.SpecialistRoles.Miner] = true,
	[SpecialistConfig.SpecialistRoles.Farmer] = true,
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
		or specialistRole == SpecialistConfig.SpecialistRoles.Farmer
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

local function readStoredSpecialistPreference(player: Player): any?
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

	return specialistPreference
end

local function readStoredSpecialistRole(player: Player, specialistPreference: any?): string?
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

local function readStoredAssignedStationId(player: Player, specialistRole: string, specialistPreference: any?): string?
	if specialistRole == SpecialistConfig.SpecialistRoles.None or type(specialistPreference) ~= "table" then
		return nil
	end

	local storedAssignedStationId = specialistPreference[PROFILE_ASSIGNED_STATION_ID_KEY]
	if storedAssignedStationId == nil then
		return nil
	end

	if type(storedAssignedStationId) ~= "string" then
		debugWarn(
			string.format(
				"Specialist assigned station ignored userId=%d reason=invalid_assigned_station_id_type value=%s",
				player.UserId,
				tostring(storedAssignedStationId)
			)
		)
		return nil
	end

	local stationValid, stationError = validateAssignedStationForRole(specialistRole, storedAssignedStationId)
	if stationValid then
		return storedAssignedStationId
	end

	debugWarn(
		string.format(
			"Specialist assigned station ignored userId=%d reason=%s stationId=%s",
			player.UserId,
			stationError,
			storedAssignedStationId
		)
	)
	return nil
end

local function readStoredLastAssignedAt(player: Player, specialistPreference: any?): number?
	if type(specialistPreference) ~= "table" then
		return nil
	end

	local storedLastAssignedAt = specialistPreference[PROFILE_LAST_ASSIGNED_AT_KEY]
	if storedLastAssignedAt == nil then
		return nil
	end

	if type(storedLastAssignedAt) ~= "number" then
		debugWarn(
			string.format(
				"Specialist last assigned at ignored userId=%d reason=invalid_timestamp_type value=%s",
				player.UserId,
				tostring(storedLastAssignedAt)
			)
		)
		return nil
	end

	if
		storedLastAssignedAt ~= storedLastAssignedAt
		or storedLastAssignedAt == math.huge
		or storedLastAssignedAt == -math.huge
		or storedLastAssignedAt < 0
	then
		debugWarn(
			string.format(
				"Specialist last assigned at ignored userId=%d reason=invalid_timestamp_value value=%s",
				player.UserId,
				tostring(storedLastAssignedAt)
			)
		)
		return nil
	end

	return storedLastAssignedAt
end

local function persistSpecialistRole(player: Player, specialistRole: string)
	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local transition = SpecialistPreferenceProfileState.ApplySpecialistRole(currentData, specialistRole)
		if not transition.accepted then
			return nil, transition.reason
		end
		return transition.profileData
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

local function persistAssignedStationId(player: Player, assignedStationId: string?)
	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local transition = SpecialistPreferenceProfileState.ApplyAssignedStationId(currentData, assignedStationId)
		if not transition.accepted then
			return nil, transition.reason
		end
		return transition.profileData
	end)

	if not updateResult.ok then
		debugWarn(
			string.format(
				"Specialist assigned station update failed userId=%d reason=%s",
				player.UserId,
				tostring(updateResult.reason)
			)
		)
	end
end

local function persistLastAssignedAt(player: Player, lastAssignedAt: number)
	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local transition = SpecialistPreferenceProfileState.ApplyLastAssignedAt(currentData, lastAssignedAt)
		if not transition.accepted then
			return nil, transition.reason
		end
		return transition.profileData
	end)

	if not updateResult.ok then
		debugWarn(
			string.format(
				"Specialist last assigned at update failed userId=%d reason=%s",
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

local function assignSpecialistState(
	player: Player,
	specialistRole: string,
	assignedStationId: string?,
	reason: string,
	allowIdempotent: boolean,
	source: string
): (boolean, string)
	if not isTinyfolk(player) then
		return false, "requester_not_tinyfolk"
	end

	if HAULING_RESERVED_LABELS[specialistRole] == true then
		return false, "hauling_not_specialist_role"
	end

	if not validSpecialistRoleSet[specialistRole] then
		return false, "invalid_specialist_role"
	end

	if assignedStationId ~= nil and type(assignedStationId) ~= "string" then
		return false, "malformed_payload"
	end

	local stationValid, stationError = validateAssignedStationForRole(specialistRole, assignedStationId)
	if not stationValid then
		return false, stationError
	end

	local state = getOrCreateState(player.UserId)
	if state.specialistRole ~= SpecialistConfig.SpecialistRoles.None then
		if state.specialistRole == specialistRole and state.assignedStationId == assignedStationId then
			if allowIdempotent then
				debugLog(
					string.format(
						"Accepted SpecialistAssignRequest idempotent source=%s userId=%d specialistRole=%s assignedStationId=%s",
						source,
						player.UserId,
						specialistRole,
						tostring(assignedStationId)
					)
				)
				return true, "already_assigned"
			end

			return false, string.format("already_assigned specialistRole=%s", state.specialistRole)
		end

		local previousSpecialistRole = state.specialistRole
		local previousAssignedStationId = state.assignedStationId

		setState(player, specialistRole, assignedStationId, reason)
		local updatedState = getOrCreateState(player.UserId)
		persistSpecialistRole(player, specialistRole)
		persistAssignedStationId(player, assignedStationId)
		persistLastAssignedAt(player, updatedState.lastAssignedAt)
		debugLog(
			string.format(
				"Accepted SpecialistAssignRequest reassigned source=%s userId=%d fromSpecialistRole=%s fromAssignedStationId=%s toSpecialistRole=%s toAssignedStationId=%s",
				source,
				player.UserId,
				previousSpecialistRole,
				tostring(previousAssignedStationId),
				specialistRole,
				tostring(assignedStationId)
			)
		)
		return true, "reassigned"
	end

	setState(player, specialistRole, assignedStationId, reason)
	local updatedState = getOrCreateState(player.UserId)
	persistSpecialistRole(player, specialistRole)
	persistAssignedStationId(player, assignedStationId)
	persistLastAssignedAt(player, updatedState.lastAssignedAt)
	debugLog(
		string.format(
			"Accepted SpecialistAssignRequest source=%s userId=%d specialistRole=%s assignedStationId=%s",
			source,
			player.UserId,
			specialistRole,
			tostring(assignedStationId)
		)
	)
	return true, "assigned"
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

	local assigned, reason = assignSpecialistState(
		player,
		parsed.specialistRole,
		parsed.assignedStationId,
		SpecialistConfig.AssignmentReasons.Assigned,
		false,
		"remote"
	)
	if not assigned then
		rejectAssign(player, reason)
	end
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
	local updatedState = getOrCreateState(player.UserId)
	persistSpecialistRole(player, SpecialistConfig.SpecialistRoles.None)
	persistAssignedStationId(player, nil)
	persistLastAssignedAt(player, updatedState.lastAssignedAt)
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
	local specialistPreference = readStoredSpecialistPreference(player)
	local storedSpecialistRole = readStoredSpecialistRole(player, specialistPreference)
	if storedSpecialistRole ~= nil then
		state.specialistRole = storedSpecialistRole
	end

	local storedAssignedStationId = readStoredAssignedStationId(player, state.specialistRole, specialistPreference)
	if storedAssignedStationId ~= nil then
		state.assignedStationId = storedAssignedStationId
	else
		state.assignedStationId = nil
	end

	local storedLastAssignedAt = readStoredLastAssignedAt(player, specialistPreference)
	if storedLastAssignedAt ~= nil then
		state.lastAssignedAt = storedLastAssignedAt
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

-- selene: allow(global_usage)
_G._SpecialistAssignmentService_QueryAPI = {
	AssignForInteraction = function(
		player: Player,
		specialistRole: string,
		assignedStationId: string?
	): (boolean, string)
		return assignSpecialistState(
			player,
			specialistRole,
			assignedStationId,
			SpecialistConfig.AssignmentReasons.Assigned,
			true,
			"interaction"
		)
	end,
	GetSnapshotForPlayer = function(player: Player): any
		return snapshotForPlayer(player)
	end,
}

debugLog("SpecialistAssignmentService initialized")
