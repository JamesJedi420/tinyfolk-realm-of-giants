--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local ShrineConfig = require(Config:WaitForChild("ShrineConfig"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local SpecialistConfig = require(Config:WaitForChild("SpecialistConfig"))
local GiantEssenceSession = require(script.Parent:WaitForChild("GiantEssenceSession"))

local REMOTES_FOLDER_NAME = "Remotes"
local ACTIVATE_REMOTE_NAME = "ShrineActivateRequest"
local DEBUG_REQUEST_REMOTE_NAME = "ShrineDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "ShrineDebugStateResponse"

local ATTRIBUTE_IS_ACTIVE = "IsActive"
local ATTRIBUTE_ESSENCE_TOTAL = "EssenceTotal"
local ATTRIBUTE_TICK_COUNT = "EssenceTickCount"
local ATTRIBUTE_LAST_TICK_AT = "LastTickAt"
local ATTRIBUTE_ACTIVATED_BY = "ActivatedByUserId"

local SHRINE_FOLDER_PATH = {"Map", "Stations"}

type ShrineState = {
	shrineId: string,
	part: BasePart,
	isActive: boolean,
	essenceTotal: number,
	tickCount: number,
	lastTickAt: number,
	activatedByUserId: number?,
	accumulatorSeconds: number,
}

local shrineStateById: {[string]: ShrineState} = {}
local lastRequestAtByUserId: {[number]: number} = {}

local function debugLog(message: string)
	print(string.format("[ShrineService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[ShrineService] %s", message))
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
	if not last then
		return false
	end

	return (os.clock() - last) < ShrineConfig.RequestCooldownSeconds
end

local function markRequest(userId: number)
	lastRequestAtByUserId[userId] = os.clock()
end

local function getHumanoidRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function isPlayerAlive(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	return humanoid.Health > 0
end

local function isPlayerTinyfolkWorshipper(player: Player): boolean
	local role = player:GetAttribute("Role")
	if role ~= RoleConfig.Roles.Tinyfolk then
		return false
	end

	local specialistRole = player:GetAttribute("SpecialistRole")
	return specialistRole == SpecialistConfig.SpecialistRoles.Worshipper
end

local function applyDebugAttributes(state: ShrineState)
	state.part:SetAttribute(ATTRIBUTE_IS_ACTIVE, state.isActive)
	state.part:SetAttribute(ATTRIBUTE_ESSENCE_TOTAL, state.essenceTotal)
	state.part:SetAttribute(ATTRIBUTE_TICK_COUNT, state.tickCount)
	state.part:SetAttribute(ATTRIBUTE_LAST_TICK_AT, state.lastTickAt)
	state.part:SetAttribute(ATTRIBUTE_ACTIVATED_BY, state.activatedByUserId)
end

local function findShrinesRoot(): Instance?
	local current: Instance = Workspace
	for _, childName in SHRINE_FOLDER_PATH do
		local nextNode = current:FindFirstChild(childName)
		if not nextNode then
			return nil
		end
		current = nextNode
	end

	return current
end

local function shouldTrackShrinePart(part: BasePart): boolean
	return string.match(part.Name, "^" .. ShrineConfig.ShrineNamePrefix) ~= nil
end

local function registerShrinePart(part: BasePart)
	local shrineId = part.Name
	if shrineStateById[shrineId] then
		debugWarn(string.format("Duplicate shrine id ignored: %s", shrineId))
		return
	end

	local state: ShrineState = {
		shrineId = shrineId,
		part = part,
		isActive = false,
		essenceTotal = 0,
		tickCount = 0,
		lastTickAt = 0,
		activatedByUserId = nil,
		accumulatorSeconds = 0,
	}

	shrineStateById[shrineId] = state
	applyDebugAttributes(state)

	debugLog(string.format("Registered shrine id=%s", shrineId))
end

local function registerShrinesFromWorkspace()
	local shrinesRoot = findShrinesRoot()
	if not shrinesRoot then
		debugWarn("No shrine root found at Workspace.Map.Stations")
		return
	end

	for _, descendant in shrinesRoot:GetDescendants() do
		if descendant:IsA("BasePart") and shouldTrackShrinePart(descendant) then
			registerShrinePart(descendant)
		end
	end

	if next(shrineStateById) == nil then
		debugWarn("No shrine parts registered under Workspace.Map.Stations")
	end
end

local function rejectActivate(player: Player, reason: string)
	debugWarn(string.format("Rejected ShrineActivateRequest userId=%d reason=%s", player.UserId, reason))
end

local function rejectDebug(player: Player, reason: string)
	debugWarn(string.format("Rejected ShrineDebugStateRequest userId=%d reason=%s", player.UserId, reason))
end

local function deactivateShrine(state: ShrineState, reason: string)
	state.isActive = false
	state.accumulatorSeconds = 0
	applyDebugAttributes(state)
	debugLog(string.format("Shrine deactivated id=%s reason=%s essenceTotal=%d", state.shrineId, reason, state.essenceTotal))
end

local remotesFolder = ensureRemotesFolder()
local shrineActivateRequestRemote = ensureRemoteEvent(remotesFolder, ACTIVATE_REMOTE_NAME)
local shrineDebugStateRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
local shrineDebugStateResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)

registerShrinesFromWorkspace()

shrineActivateRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if isCoolingDown(player.UserId) then
		rejectActivate(player, "request_cooldown")
		return
	end

	markRequest(player.UserId)

	if type(payload) ~= "string" then
		rejectActivate(player, "malformed_payload")
		return
	end

	local shrineId = payload
	local shrineState = shrineStateById[shrineId]
	if not shrineState then
		rejectActivate(player, "shrine_not_found")
		return
	end

	if not isPlayerAlive(player) then
		rejectActivate(player, "player_not_alive")
		return
	end

	local root = getHumanoidRootPart(player)
	if not root then
		rejectActivate(player, "humanoid_root_missing")
		return
	end

	local distance = (shrineState.part.Position - root.Position).Magnitude
	if distance > ShrineConfig.ActivationRangeStuds then
		rejectActivate(player, string.format("out_of_range distance=%.2f max=%.2f", distance, ShrineConfig.ActivationRangeStuds))
		return
	end

	if not isPlayerTinyfolkWorshipper(player) then
		rejectActivate(player, "worshipper_role_required")
		return
	end

	if shrineState.isActive then
		rejectActivate(player, "already_active")
		return
	end

	shrineState.isActive = true
	shrineState.activatedByUserId = player.UserId
	shrineState.lastTickAt = os.clock()
	shrineState.accumulatorSeconds = 0
	applyDebugAttributes(shrineState)

	debugLog(string.format("Accepted ShrineActivateRequest userId=%d shrineId=%s", player.UserId, shrineId))
end)

shrineDebugStateRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if payload ~= nil and type(payload) ~= "string" then
		rejectDebug(player, "malformed_payload")
		return
	end

	local requestedShrineId = payload :: string?
	if requestedShrineId then
		local shrineState = shrineStateById[requestedShrineId]
		if not shrineState then
			rejectDebug(player, "shrine_not_found")
			return
		end

		shrineDebugStateResponseRemote:FireClient(player, {
			shrineId = shrineState.shrineId,
			isActive = shrineState.isActive,
			essenceTotal = shrineState.essenceTotal,
			tickCount = shrineState.tickCount,
			activatedByUserId = shrineState.activatedByUserId,
		})
		debugLog(string.format("Sent shrine debug state userId=%d shrineId=%s", player.UserId, shrineState.shrineId))
		return
	end

	local snapshot = {}
	for shrineId, shrineState in shrineStateById do
		table.insert(snapshot, {
			shrineId = shrineId,
			isActive = shrineState.isActive,
			essenceTotal = shrineState.essenceTotal,
			tickCount = shrineState.tickCount,
			activatedByUserId = shrineState.activatedByUserId,
		})
	end

	shrineDebugStateResponseRemote:FireClient(player, snapshot)
	debugLog(string.format("Sent shrine debug state snapshot userId=%d shrineCount=%d", player.UserId, #snapshot))
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil

	for _, shrineState in shrineStateById do
		if shrineState.activatedByUserId == player.UserId and shrineState.isActive then
			debugLog(string.format("Activation owner left; shrine remains active id=%s", shrineState.shrineId))
		end
	end
end)

RunService.Heartbeat:Connect(function(deltaTime: number)
	for _, shrineState in shrineStateById do
		if not shrineState.isActive then
			continue
		end

		shrineState.accumulatorSeconds += deltaTime

		while shrineState.accumulatorSeconds >= ShrineConfig.GenerationIntervalSeconds and shrineState.isActive do
			local activatingPlayer = shrineState.activatedByUserId and Players:GetPlayerByUserId(shrineState.activatedByUserId)
			if not activatingPlayer or not isPlayerTinyfolkWorshipper(activatingPlayer) then
				applyDebugAttributes(shrineState)
				deactivateShrine(shrineState, "worshipper_role_lost")
				break
			end

			shrineState.accumulatorSeconds -= ShrineConfig.GenerationIntervalSeconds
			shrineState.tickCount += 1
			shrineState.lastTickAt = os.clock()

			local remainingCapacity = ShrineConfig.MaxEssenceTotal - shrineState.essenceTotal
			local generatedAmount = math.min(ShrineConfig.EssencePerTick, math.max(0, remainingCapacity))
			if generatedAmount <= 0 then
				applyDebugAttributes(shrineState)
				deactivateShrine(shrineState, "max_essence_reached")
				break
			end

			shrineState.essenceTotal += generatedAmount
			local sessionSnapshot = GiantEssenceSession.AddGenerated("Shrine:" .. shrineState.shrineId, generatedAmount)

			if shrineState.essenceTotal >= ShrineConfig.MaxEssenceTotal then
				shrineState.essenceTotal = ShrineConfig.MaxEssenceTotal
				applyDebugAttributes(shrineState)
				debugLog(string.format("Shrine Essence tick id=%s tick=%d generated=%.0f total=%d giantSessionTotal=%.0f", shrineState.shrineId, shrineState.tickCount, generatedAmount, shrineState.essenceTotal, sessionSnapshot.total))
				deactivateShrine(shrineState, "max_essence_reached")
				break
			end

			applyDebugAttributes(shrineState)
			if shrineState.tickCount % ShrineConfig.DebugLogEveryTicks == 0 then
				debugLog(string.format("Shrine Essence tick id=%s tick=%d generated=%.0f total=%d giantSessionTotal=%.0f", shrineState.shrineId, shrineState.tickCount, generatedAmount, shrineState.essenceTotal, sessionSnapshot.total))
			end
		end
	end
end)

debugLog("ShrineService initialized")