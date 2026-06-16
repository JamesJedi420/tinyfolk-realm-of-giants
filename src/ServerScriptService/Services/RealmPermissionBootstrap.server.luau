--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local RealmPermissionConfig = require(Config:WaitForChild("RealmPermissionConfig"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))

local createRealmPermissionService = require(script.Parent:WaitForChild("RealmPermissionService.server"))
local globalEnv: any = getfenv()

local lastRequestAtByUserId: { [number]: number? } = {}
local roleServiceApiOverride: any = nil

createRealmPermissionService(game, nil)

local permissionApi = globalEnv._RealmPermissionService_QueryAPI

local function now(): number
	return os.clock()
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and value > 0
end

local function getRoleServiceApi(): any?
	if roleServiceApiOverride ~= nil then
		return roleServiceApiOverride
	end

	local fromEnv = rawget(globalEnv, "_RoleService_QueryAPI")
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, "_RoleService_QueryAPI")
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
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
	return remote
end

local function isCoolingDown(userId: number, at: number): boolean
	local lastAt = lastRequestAtByUserId[userId]
	if type(lastAt) ~= "number" then
		return false
	end
	return (at - lastAt) < RealmPermissionConfig.RequestCooldownSeconds
end

local function isGiantRealmOwner(player: Player): (boolean, string)
	if player:GetAttribute("Role") ~= RoleConfig.Roles.Giant then
		return false, "role_not_giant"
	end

	local roleApi = getRoleServiceApi()
	if type(roleApi) ~= "table" or type(roleApi.GetActiveGiantRealmOwnerUserId) ~= "function" then
		return false, RealmPermissionConfig.Reasons.OwnerUnavailable
	end

	local activeOwnerUserId = roleApi.GetActiveGiantRealmOwnerUserId()
	if not isPositiveInteger(activeOwnerUserId) or activeOwnerUserId ~= player.UserId then
		return false, RealmPermissionConfig.Reasons.OwnerMismatch
	end

	return true, RealmPermissionConfig.Reasons.Accepted
end

local function fireOwnerResponse(player: Player, responseRemote: RemoteEvent, response: any)
	responseRemote:FireClient(player, response)
end

local function handleOwnerRequest(player: Player, payload: any, responseRemote: RemoteEvent, at: number?): any
	local resolvedAt = if type(at) == "number" then at else now()
	local requestId = if type(payload) == "table" and isNonEmptyString(payload.requestId) then payload.requestId else ""
	local action = if type(payload) == "table" then payload.action else nil

	if isCoolingDown(player.UserId, resolvedAt) then
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "rate_limited",
		}
		fireOwnerResponse(player, responseRemote, response)
		return response
	end
	lastRequestAtByUserId[player.UserId] = resolvedAt

	local ownerOk, ownerReason = isGiantRealmOwner(player)
	if not ownerOk then
		local response = {
			requestId = requestId,
			accepted = false,
			reason = ownerReason,
		}
		fireOwnerResponse(player, responseRemote, response)
		return response
	end

	if type(permissionApi) ~= "table" then
		local response = {
			requestId = requestId,
			accepted = false,
			reason = "permission_api_unavailable",
		}
		fireOwnerResponse(player, responseRemote, response)
		return response
	end

	if action == RealmPermissionConfig.OwnerActions.SetAccessMode then
		local accessMode = if type(payload) == "table" then payload.accessMode else nil
		local result = permissionApi.SetOwnerRealmAccessMode(player.UserId, accessMode)
		local response = {
			requestId = requestId,
			accepted = result.accepted == true,
			reason = if type(result.reason) == "string" then result.reason else "owner_access_mode_failed",
			accessMode = if result.accepted == true then result.accessMode else nil,
			realmId = if result.accepted == true then result.realmId else nil,
		}
		fireOwnerResponse(player, responseRemote, response)
		return response
	end

	if action == RealmPermissionConfig.OwnerActions.AddInvite then
		local targetUserId = if type(payload) == "table" then payload.targetUserId else nil
		local realmId = string.format("giant_realm_%d", player.UserId)
		local result = permissionApi.AddInviteAllowlistUser(realmId, targetUserId)
		local response = {
			requestId = requestId,
			accepted = result.accepted == true,
			reason = if type(result.reason) == "string" then result.reason else "invite_allowlist_add_failed",
			targetUserId = if isPositiveInteger(targetUserId) then math.floor(targetUserId) else nil,
		}
		fireOwnerResponse(player, responseRemote, response)
		return response
	end

	if action == RealmPermissionConfig.OwnerActions.RemoveInvite then
		local targetUserId = if type(payload) == "table" then payload.targetUserId else nil
		local realmId = string.format("giant_realm_%d", player.UserId)
		local result = permissionApi.RemoveInviteAllowlistUser(realmId, targetUserId)
		local response = {
			requestId = requestId,
			accepted = result.accepted == true,
			reason = if type(result.reason) == "string" then result.reason else "invite_allowlist_remove_failed",
			targetUserId = if isPositiveInteger(targetUserId) then math.floor(targetUserId) else nil,
		}
		fireOwnerResponse(player, responseRemote, response)
		return response
	end

	local response = {
		requestId = requestId,
		accepted = false,
		reason = "owner_action_invalid",
	}
	fireOwnerResponse(player, responseRemote, response)
	return response
end

local remotesFolder = ensureRemotesFolder()
local ownerRequestRemote = ensureRemoteEvent(remotesFolder, RealmPermissionConfig.Remotes.OwnerRequest)
local ownerResponseRemote = ensureRemoteEvent(remotesFolder, RealmPermissionConfig.Remotes.OwnerResponse)

ownerRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	handleOwnerRequest(player, payload, ownerResponseRemote, nil)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
end)

globalEnv._RealmPermissionOwnerService_QueryAPI = {
	HandleOwnerRequestForTests = function(player: Player, payload: any, at: number?): any
		return handleOwnerRequest(player, payload, ownerResponseRemote, at)
	end,
	ConfigureForTests = function(config: any?)
		local configAny: any = if type(config) == "table" then config else {}
		roleServiceApiOverride = configAny.roleServiceApi
		if type(permissionApi) == "table" and type(permissionApi.ConfigureForTests) == "function" then
			permissionApi.ConfigureForTests(configAny.permissionApi)
		end
	end,
	ResetForTests = function()
		roleServiceApiOverride = nil
		lastRequestAtByUserId = {}
		if type(permissionApi) == "table" and type(permissionApi.ResetForTests) == "function" then
			permissionApi.ResetForTests()
		end
	end,
}

if type(_G) == "table" then
	rawset(_G, "_RealmPermissionOwnerService_QueryAPI", globalEnv._RealmPermissionOwnerService_QueryAPI)
end

return globalEnv._RealmPermissionOwnerService_QueryAPI
