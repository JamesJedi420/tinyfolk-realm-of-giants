--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local TinyfolkLaborUpgradeConfig = require(Config:WaitForChild("TinyfolkLaborUpgradeConfig"))
local TinyfolkLaborUpgradeState = require(GiantRealm:WaitForChild("TinyfolkLaborUpgradeState"))

local ResourceFlowState = require(script.Parent:WaitForChild("ResourceFlowState"))

local REMOTES_FOLDER_NAME = "Remotes"
local REQUEST_REMOTE_NAME = "TinyfolkLaborUpgradeRequest"
local RESPONSE_REMOTE_NAME = "TinyfolkLaborUpgradeResponse"
local DEBUG_REQUEST_REMOTE_NAME = "TinyfolkLaborUpgradeDebugRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "TinyfolkLaborUpgradeDebugResponse"

local ROLE_ATTRIBUTE = "Role"
local BENCH_FOLDER_PATH = { "Map", "Stations" }

local globalEnv: any = getfenv()
local playerStateByUserId: { [number]: TinyfolkLaborUpgradeState.PlayerState } = {}
local registeredBenchIds: { [string]: boolean } = {}
local lastRequestAtByUserId: { [number]: number? } = {}

local function now(): number
	return os.clock()
end

local function debugLog(message: string)
	print(string.format("[TinyfolkLaborUpgradeService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[TinyfolkLaborUpgradeService] %s", message))
end

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
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

local function getOrCreatePlayerState(userId: number): TinyfolkLaborUpgradeState.PlayerState
	local existing = playerStateByUserId[userId]
	if existing ~= nil then
		return existing
	end

	local created = TinyfolkLaborUpgradeState.CreateEmptyPlayerState()
	playerStateByUserId[userId] = created
	return created
end

local function applyDebugAttributes(player: Player, state: TinyfolkLaborUpgradeState.PlayerState, lastReason: string?)
	local snapshot = TinyfolkLaborUpgradeState.BuildDebugSnapshot(state)
	player:SetAttribute(TinyfolkLaborUpgradeConfig.LaborTokensAttribute, snapshot.laborTokens)
	player:SetAttribute(TinyfolkLaborUpgradeConfig.HaulYieldLevelAttribute, snapshot.haulYieldLevel)
	player:SetAttribute(TinyfolkLaborUpgradeConfig.TaskPaceLevelAttribute, snapshot.taskPaceLevel)
	player:SetAttribute(TinyfolkLaborUpgradeConfig.EffectiveHaulYieldMultiplierAttribute, snapshot.haulYieldMultiplier)
	player:SetAttribute(TinyfolkLaborUpgradeConfig.EffectiveTaskPaceMultiplierAttribute, snapshot.taskPaceMultiplier)
	if type(lastReason) == "string" then
		player:SetAttribute(TinyfolkLaborUpgradeConfig.LastReasonAttribute, lastReason)
	end
end

local function magnitudeBetweenPositions(a: any, b: any): number
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function getHumanoidRootPart(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function isWithinBenchRange(player: Player, benchId: string): boolean
	local root = getHumanoidRootPart(player)
	if root == nil then
		return false
	end

	local mapFolder = Workspace:FindFirstChild("Map")
	if mapFolder == nil then
		return false
	end
	local stationsFolder = mapFolder:FindFirstChild("Stations")
	if stationsFolder == nil then
		return false
	end

	local benchPart: BasePart? = nil
	for _, descendant in stationsFolder:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == benchId then
			benchPart = descendant
			break
		end
	end
	if benchPart == nil then
		return false
	end

	local distance = magnitudeBetweenPositions(root.Position :: any, benchPart.Position :: any)
	return distance <= TinyfolkLaborUpgradeConfig.InteractionRangeStuds
end

local function registerBenchFromPart(part: BasePart)
	local track = TinyfolkLaborUpgradeState.ResolveTrackForBenchId(part.Name)
	if track == nil then
		return
	end
	if registeredBenchIds[part.Name] then
		return
	end
	registeredBenchIds[part.Name] = true
	debugLog(string.format("Registered labor bench id=%s track=%s", part.Name, track))
end

local function registerBenchesFromWorkspace()
	local mapFolder = Workspace:FindFirstChild(BENCH_FOLDER_PATH[1])
	if mapFolder == nil then
		debugWarn("Map folder missing for labor bench discovery")
		return
	end
	local stationsFolder = mapFolder:FindFirstChild(BENCH_FOLDER_PATH[2])
	if stationsFolder == nil then
		debugWarn("Stations folder missing for labor bench discovery")
		return
	end

	for _, descendant in stationsFolder:GetDescendants() do
		if descendant:IsA("BasePart") then
			registerBenchFromPart(descendant)
		end
	end
end

local function isCoolingDown(userId: number, at: number): boolean
	local last = lastRequestAtByUserId[userId]
	if last == nil then
		return false
	end
	return (at - last) < TinyfolkLaborUpgradeConfig.RequestCooldownSeconds
end

local function rejectUpgrade(
	player: Player,
	reason: string,
	benchId: string?,
	track: string?,
	responseRemote: RemoteEvent
)
	debugWarn(
		string.format(
			"Rejected TinyfolkLaborUpgradeRequest userId=%d benchId=%s track=%s reason=%s",
			player.UserId,
			tostring(benchId),
			tostring(track),
			reason
		)
	)
	applyDebugAttributes(player, getOrCreatePlayerState(player.UserId), reason)
	responseRemote:FireClient(player, {
		accepted = false,
		reason = reason,
		benchId = benchId,
		track = track,
	})
end

local function requestUpgrade(player: Player, benchId: any, at: number?, responseRemote: RemoteEvent): any
	local resolvedAt = if type(at) == "number" then at else now()
	if isCoolingDown(player.UserId, resolvedAt) then
		rejectUpgrade(
			player,
			"request_cooldown",
			if type(benchId) == "string" then benchId else nil,
			nil,
			responseRemote
		)
		return { accepted = false, reason = "request_cooldown" }
	end
	lastRequestAtByUserId[player.UserId] = resolvedAt

	if player:GetAttribute(ROLE_ATTRIBUTE) ~= RoleConfig.Roles.Tinyfolk then
		rejectUpgrade(
			player,
			"requester_not_tinyfolk",
			if type(benchId) == "string" then benchId else nil,
			nil,
			responseRemote
		)
		return { accepted = false, reason = "requester_not_tinyfolk" }
	end

	if type(benchId) ~= "string" or benchId == "" then
		rejectUpgrade(player, "bench_id_invalid", nil, nil, responseRemote)
		return { accepted = false, reason = "bench_id_invalid" }
	end

	local track = TinyfolkLaborUpgradeState.ResolveTrackForBenchId(benchId)
	if track == nil then
		rejectUpgrade(player, "bench_not_registered", benchId, nil, responseRemote)
		return { accepted = false, reason = "bench_not_registered" }
	end

	if registeredBenchIds[benchId] ~= true then
		rejectUpgrade(player, "bench_not_registered", benchId, track, responseRemote)
		return { accepted = false, reason = "bench_not_registered" }
	end

	if not isWithinBenchRange(player, benchId) then
		rejectUpgrade(player, "out_of_range", benchId, track, responseRemote)
		return { accepted = false, reason = "out_of_range" }
	end

	local currentState = getOrCreatePlayerState(player.UserId)
	local transition = TinyfolkLaborUpgradeState.ResolveUpgrade(currentState, track)
	if transition.accepted ~= true then
		rejectUpgrade(player, transition.reason or "upgrade_rejected", benchId, track, responseRemote)
		return transition
	end

	local nextState = transition.state
	if transition.spendKind == "stored_food" then
		local foodCost = transition.pendingFoodCost
		if type(foodCost) ~= "number" or foodCost <= 0 then
			rejectUpgrade(player, "cost_missing", benchId, track, responseRemote)
			return { accepted = false, reason = "cost_missing" }
		end

		local spent, _, spendReason = ResourceFlowState.SpendStoredAtomic(
			0,
			0,
			string.format("TinyfolkLaborUpgrade:%s:%d", benchId, transition.level),
			foodCost
		)
		if not spent then
			rejectUpgrade(player, spendReason or "insufficient_food", benchId, track, responseRemote)
			return { accepted = false, reason = spendReason or "insufficient_food" }
		end

		nextState = TinyfolkLaborUpgradeState.ApplyFoodSpendSuccess(currentState, track, transition.level)
	end

	playerStateByUserId[player.UserId] = nextState
	applyDebugAttributes(player, nextState, "accepted")
	responseRemote:FireClient(player, {
		accepted = true,
		reason = "accepted",
		benchId = benchId,
		track = track,
		level = transition.level,
		cost = transition.cost,
		spendKind = transition.spendKind,
	})
	debugLog(
		string.format(
			"Accepted TinyfolkLaborUpgradeRequest userId=%d benchId=%s track=%s level=%d spendKind=%s",
			player.UserId,
			benchId,
			track,
			transition.level,
			tostring(transition.spendKind)
		)
	)
	return transition
end

local function RecordWorkActionCompleted(player: Player)
	if player:GetAttribute(ROLE_ATTRIBUTE) ~= RoleConfig.Roles.Tinyfolk then
		return
	end

	local nextState = TinyfolkLaborUpgradeState.GrantWorkActionReward(getOrCreatePlayerState(player.UserId))
	playerStateByUserId[player.UserId] = nextState
	applyDebugAttributes(player, nextState, "work_action_rewarded")
	debugLog(string.format("Granted labor tokens userId=%d tokens=%d", player.UserId, nextState.laborTokens))
end

local function GetHaulYieldMultiplier(userId: number): number
	local state = playerStateByUserId[userId]
	if state == nil then
		return TinyfolkLaborUpgradeState.ResolveHaulYieldMultiplier(0)
	end
	return TinyfolkLaborUpgradeState.ResolveHaulYieldMultiplier(state.haulYieldLevel)
end

local function GetTaskPaceMultiplier(userId: number): number
	local state = playerStateByUserId[userId]
	if state == nil then
		return TinyfolkLaborUpgradeState.ResolveTaskPaceMultiplier(0)
	end
	return TinyfolkLaborUpgradeState.ResolveTaskPaceMultiplier(state.taskPaceLevel)
end

local function GetPlayerSnapshot(userId: number): any
	return TinyfolkLaborUpgradeState.BuildDebugSnapshot(getOrCreatePlayerState(userId))
end

local remotesFolder = ensureRemotesFolder()
local requestRemote = ensureRemoteEvent(remotesFolder, REQUEST_REMOTE_NAME)
local responseRemote = ensureRemoteEvent(remotesFolder, RESPONSE_REMOTE_NAME)
local debugRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
local debugResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)

registerBenchesFromWorkspace()

requestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local benchId: string? = nil
	local requestAt: number? = nil

	if type(payload) == "string" then
		benchId = payload
	elseif type(payload) == "table" then
		local payloadAny = payload :: any
		if type(payloadAny.benchId) == "string" then
			benchId = payloadAny.benchId
		end
		if type(payloadAny.at) == "number" then
			requestAt = payloadAny.at
		end
	else
		rejectUpgrade(player, "malformed_payload", nil, nil, responseRemote)
		return
	end

	requestUpgrade(player, benchId, requestAt, responseRemote)
end)

debugRequestRemote.OnServerEvent:Connect(function(player: Player, _payload: unknown)
	debugResponseRemote:FireClient(player, GetPlayerSnapshot(player.UserId))
end)

Players.PlayerRemoving:Connect(function(player: Player)
	playerStateByUserId[player.UserId] = nil
	lastRequestAtByUserId[player.UserId] = nil
end)

globalEnv._TinyfolkLaborUpgradeService_QueryAPI = {
	RecordWorkActionCompleted = RecordWorkActionCompleted,
	GetHaulYieldMultiplier = GetHaulYieldMultiplier,
	GetTaskPaceMultiplier = GetTaskPaceMultiplier,
	GetPlayerSnapshot = GetPlayerSnapshot,
	RequestUpgradeForTests = function(player: Player, benchId: string, at: number?)
		return requestUpgrade(player, benchId, at, responseRemote)
	end,
	RegisterBenchForTests = function(benchId: string)
		registeredBenchIds[benchId] = true
	end,
	SetPlayerStateForTests = function(userId: number, state: TinyfolkLaborUpgradeState.PlayerState)
		playerStateByUserId[userId] = state
	end,
}

debugLog("TinyfolkLaborUpgradeService initialized")
