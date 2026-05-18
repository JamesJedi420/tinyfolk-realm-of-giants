--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local ScoreConfig = require(Config:WaitForChild("ScoreConfig"))
local ScoreState = require(GiantRealm:WaitForChild("ScoreState"))

local REMOTES_FOLDER_NAME = "Remotes"
local REQUEST_REMOTE_NAME = "ScoreEventRequest"
local RESPONSE_REMOTE_NAME = "ScoreEventResponse"
local ROLE_ATTRIBUTE = "Role"

local state = ScoreState.NewState()

local function now(): number
	return os.clock()
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

local function getPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player :: any
		end
	end
	return nil
end

local function applyScoreAttributes(player: Player)
	local attrs = ScoreConfig.StateAttributes
	local snapshot = ScoreState.GetPlayerSnapshot(state, player.UserId)
	player:SetAttribute(attrs.ScoreTotal, snapshot.total)
	player:SetAttribute(attrs.ScoreObjective, snapshot.categories.objective or 0)
	player:SetAttribute(attrs.ScoreTeamplay, snapshot.categories.teamplay or 0)
	player:SetAttribute(attrs.ScoreControl, snapshot.categories.control or 0)
end

local function applyAllScoreAttributes()
	for _, player in Players:GetPlayers() do
		applyScoreAttributes(player)
	end
end

local function setLastReason(player: Player?, reason: string)
	if player == nil then
		return
	end
	player:SetAttribute(ScoreConfig.StateAttributes.ScoreLastReason, reason)
end

local function requestScoreEvent(actor: Player, eventId: any, at: number?, metadata: any?): any
	local resolvedNow = if type(at) == "number" then at else now()

	if type(eventId) ~= "string" then
		setLastReason(actor, "invalid_event_id")
		return { accepted = false, reason = "invalid_event_id", record = nil }
	end

	local transition = ScoreState.ResolveScoreEvent(state, {
		now = resolvedNow,
		userId = actor.UserId,
		eventId = eventId,
		actorRole = actor:GetAttribute(ROLE_ATTRIBUTE),
		metadata = metadata,
	})

	state = transition.state
	setLastReason(actor, transition.reason)
	if transition.accepted then
		applyScoreAttributes(actor)
	end

	return {
		accepted = transition.accepted,
		reason = transition.reason,
		record = transition.record,
	}
end

local remotesFolder = ensureRemotesFolder()
local requestRemote = ensureRemoteEvent(remotesFolder, REQUEST_REMOTE_NAME)
local responseRemote = ensureRemoteEvent(remotesFolder, RESPONSE_REMOTE_NAME)

requestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local eventId = nil
	local metadata = nil
	local at = nil
	if type(payload) == "string" then
		eventId = payload
	elseif type(payload) == "table" then
		eventId = (payload :: any).eventId
		at = (payload :: any).now
		metadata = (payload :: any).metadata
	end

	local result = requestScoreEvent(player, eventId, at, metadata)
	responseRemote:FireClient(player, result)
end)

Players.PlayerAdded:Connect(function(player: Player)
	applyScoreAttributes(player)
end)

_G._ScoreService_QueryAPI = {
	RequestScoreEvent = function(userId: number, eventId: string, at: number?, metadata: any?): any
		local actor = getPlayerByUserId(userId)
		if actor == nil then
			return { accepted = false, reason = "actor_not_found" }
		end
		return requestScoreEvent(actor, eventId, at, metadata)
	end,
	GetPlayerScoreSnapshot = function(userId: number): any
		return ScoreState.GetPlayerSnapshot(state, userId)
	end,
	GetCategoryTotals = function(): any
		return ScoreState.GetCategoryTotals(state)
	end,
	GetRecentScoreEvents = function(limit: number?): any
		return ScoreState.GetRecentEvents(state, limit)
	end,
	ResetForTests = function()
		state = ScoreState.NewState()
		applyAllScoreAttributes()
	end,
}

for _, player in Players:GetPlayers() do
	applyScoreAttributes(player)
end
