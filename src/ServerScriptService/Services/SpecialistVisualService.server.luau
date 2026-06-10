--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local SpecialistVisual = Shared:WaitForChild("SpecialistVisual")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local SpecialistConfig = require(Config:WaitForChild("SpecialistConfig"))
local SpecialistVisualConfig = require(Config:WaitForChild("SpecialistVisualConfig"))
local SpecialistVisualApply = if script ~= nil and script.Parent ~= nil
	then require(SpecialistVisual:WaitForChild("SpecialistVisualApply"))
	else require("../../ReplicatedStorage/Shared/SpecialistVisual/SpecialistVisualApply")

local REMOTES_FOLDER_NAME = "Remotes"
local DEBUG_REQUEST_REMOTE_NAME = "SpecialistVisualDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "SpecialistVisualDebugStateResponse"

local SPECIALIST_ROLE_ATTRIBUTE = "SpecialistRole"

type AppliedState = SpecialistVisualApply.AppliedState

local appliedStateByUserId: { [number]: AppliedState? } = {}

local function debugLog(message: string)
	print(string.format("[SpecialistVisualService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[SpecialistVisualService] %s", message))
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

local function colorFromConfig(colorConfig: any): Color3
	if type(colorConfig) ~= "table" then
		return Color3.fromRGB(180, 180, 180)
	end

	local red = if type(colorConfig.r) == "number" then colorConfig.r else 0.7
	local green = if type(colorConfig.g) == "number" then colorConfig.g else 0.7
	local blue = if type(colorConfig.b) == "number" then colorConfig.b else 0.7
	return Color3.new(red, green, blue)
end

local function findAttachPart(character: Instance, partNames: { string }): BasePart?
	for _, partName in ipairs(partNames) do
		local child = character:FindFirstChild(partName)
		if child and child:IsA("BasePart") then
			return child :: BasePart
		end
	end

	return nil
end

local function clearCharacterVisuals(character: Instance)
	local existing = character:FindFirstChild(SpecialistVisualConfig.CharacterFolderName)
	if existing then
		existing:Destroy()
	end
end

local function createPlaceholderPart(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = false
	part.CastShadow = false
	return part
end

local function weldPartToAttach(visualPart: BasePart, attachPart: BasePart)
	visualPart.CFrame = attachPart.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachPart
	weld.Part1 = visualPart
	weld.Parent = visualPart
end

local function applyCharacterVisuals(character: Instance, plan: SpecialistVisualApply.ApplyPlan)
	clearCharacterVisuals(character)

	if not plan.shouldApply then
		return
	end

	local placeholder = SpecialistVisualConfig.PlaceholderBySpecialistRole[plan.activeRole]
	if type(placeholder) ~= "table" then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = SpecialistVisualConfig.CharacterFolderName
	folder.Parent = character

	local outfitAttach = findAttachPart(character, SpecialistVisualConfig.OutfitAttachPartNames)
	if outfitAttach ~= nil then
		local outfitPart = createPlaceholderPart(
			tostring(plan.outfitId or "specialist_outfit"),
			Vector3.new(1.4, 1.1, 0.35),
			colorFromConfig(placeholder.outfitColor)
		)
		outfitPart.Parent = folder
		weldPartToAttach(outfitPart, outfitAttach)
	end

	local toolAttach = findAttachPart(character, SpecialistVisualConfig.ToolAttachPartNames)
	if toolAttach ~= nil then
		local toolPart = createPlaceholderPart(
			tostring(plan.toolId or "specialist_tool"),
			Vector3.new(0.2, 1.2, 0.2),
			colorFromConfig(placeholder.toolColor)
		)
		toolPart.Parent = folder
		weldPartToAttach(toolPart, toolAttach)
	end
end

local function getOrCreateState(userId: number): AppliedState
	local existing = appliedStateByUserId[userId]
	if existing then
		return existing
	end

	local created: AppliedState = {
		applied = false,
		activeRole = SpecialistConfig.SpecialistRoles.None,
		outfitId = nil,
		toolId = nil,
		lastApplyReason = SpecialistVisualConfig.ApplyReasons.Initial,
		lastAppliedAt = nil,
	}
	appliedStateByUserId[userId] = created
	return created
end

local function applyDebugAttributes(player: Player, state: AppliedState)
	local attributes = SpecialistVisualConfig.Attributes
	player:SetAttribute(attributes.Applied, state.applied)
	player:SetAttribute(attributes.ActiveRole, state.activeRole)
	player:SetAttribute(attributes.OutfitId, state.outfitId)
	player:SetAttribute(attributes.ToolId, state.toolId)
	player:SetAttribute(attributes.LastApplyReason, state.lastApplyReason)
	player:SetAttribute(attributes.LastAppliedAt, state.lastAppliedAt)
end

local function syncVisualsForPlayer(player: Player, applyReason: string)
	local plan = SpecialistVisualApply.Resolve({
		requesterRole = player:GetAttribute("Role"),
		specialistRole = player:GetAttribute(SPECIALIST_ROLE_ATTRIBUTE),
	}, applyReason)

	local state = getOrCreateState(player.UserId)
	local character = player.Character

	if plan.shouldClear then
		if character ~= nil then
			clearCharacterVisuals(character)
		end

		state.applied = false
		state.activeRole = SpecialistConfig.SpecialistRoles.None
		state.outfitId = nil
		state.toolId = nil
		state.lastApplyReason = plan.reason
		state.lastAppliedAt = os.clock()
		applyDebugAttributes(player, state)
		debugLog(string.format("Cleared specialist visuals userId=%d reason=%s", player.UserId, plan.reason))
		return
	end

	if character ~= nil then
		applyCharacterVisuals(character, plan)
	end

	state.applied = true
	state.activeRole = plan.activeRole
	state.outfitId = plan.outfitId
	state.toolId = plan.toolId
	state.lastApplyReason = plan.reason
	state.lastAppliedAt = os.clock()
	applyDebugAttributes(player, state)
	debugLog(
		string.format(
			"Applied specialist visuals userId=%d role=%s outfitId=%s toolId=%s reason=%s",
			player.UserId,
			plan.activeRole,
			tostring(plan.outfitId),
			tostring(plan.toolId),
			plan.reason
		)
	)
end

local function snapshotForPlayer(player: Player)
	local state = getOrCreateState(player.UserId)
	return {
		userId = player.UserId,
		role = player:GetAttribute("Role"),
		specialistRole = player:GetAttribute(SPECIALIST_ROLE_ATTRIBUTE),
		applied = state.applied,
		activeRole = state.activeRole,
		outfitId = state.outfitId,
		toolId = state.toolId,
		lastApplyReason = state.lastApplyReason,
		lastAppliedAt = state.lastAppliedAt,
	}
end

local function rejectDebug(player: Player, reason: string)
	debugWarn(string.format("Rejected SpecialistVisualDebugStateRequest userId=%d reason=%s", player.UserId, reason))
end

local remotesFolder = ensureRemotesFolder()
local debugRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
local debugResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)

debugRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if payload ~= nil then
		rejectDebug(player, "malformed_payload")
		return
	end

	local snapshot = snapshotForPlayer(player)
	debugResponseRemote:FireClient(player, snapshot)
	debugLog(
		string.format(
			"Sent specialist visual debug state userId=%d applied=%s activeRole=%s",
			player.UserId,
			tostring(snapshot.applied),
			tostring(snapshot.activeRole)
		)
	)
end)

local function setupPlayer(player: Player)
	syncVisualsForPlayer(player, SpecialistVisualConfig.ApplyReasons.Initial)

	player:GetAttributeChangedSignal(SPECIALIST_ROLE_ATTRIBUTE):Connect(function()
		local specialistRole = player:GetAttribute(SPECIALIST_ROLE_ATTRIBUTE)
		local reason = if specialistRole == SpecialistConfig.SpecialistRoles.None
			then SpecialistVisualConfig.ApplyReasons.Cleared
			else SpecialistVisualConfig.ApplyReasons.Assigned
		syncVisualsForPlayer(player, reason)
	end)

	player:GetAttributeChangedSignal("Role"):Connect(function()
		if player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk then
			syncVisualsForPlayer(player, SpecialistVisualConfig.ApplyReasons.Initial)
			return
		end

		syncVisualsForPlayer(player, SpecialistVisualConfig.ApplyReasons.ClearedRoleChange)
	end)

	local playerAny: any = player
	playerAny.CharacterAdded:Connect(function(_character: Instance)
		syncVisualsForPlayer(player, SpecialistVisualConfig.ApplyReasons.CharacterRespawn)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	appliedStateByUserId[player.UserId] = nil
end)

-- selene: allow(global_usage)
_G._SpecialistVisualService_QueryAPI = {
	GetSnapshotForPlayer = function(player: Player): any
		return snapshotForPlayer(player)
	end,
	SyncForPlayer = function(player: Player, applyReason: string?): any
		syncVisualsForPlayer(
			player,
			if type(applyReason) == "string" then applyReason else SpecialistVisualConfig.ApplyReasons.Assigned
		)
		return snapshotForPlayer(player)
	end,
}

debugLog("SpecialistVisualService initialized")
