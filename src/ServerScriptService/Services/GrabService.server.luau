--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local GrabConfig = require(Config:WaitForChild("GrabConfig"))

local ROLE_ATTRIBUTE = "Role"
local REMOTES_FOLDER_NAME = "Remotes"
local GRAB_REMOTE_NAME = "GrabRequest"
local PLACE_REMOTE_NAME = "PlaceRequest"

local HELD_TARGET_ATTRIBUTE = "HeldTargetUserId"
local HELD_BY_ATTRIBUTE = "HeldByUserId"

local heldTargetByGiantUserId: {[number]: number} = {}
local heldByTargetUserId: {[number]: number} = {}
local lastRequestAtByUserId: {[number]: number} = {}

local function debugLog(message: string)
	print(string.format("[GrabService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[GrabService] %s", message))
end

local function getPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player
		end
	end

	return nil
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

local function ensureRemote(parentFolder: Folder, remoteName: string): RemoteEvent
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

local function isPlayerRole(player: Player, roleName: string): boolean
	return player:GetAttribute(ROLE_ATTRIBUTE) == roleName
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

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end

	return nil
end

local function isAlive(player: Player): boolean
	local humanoid = getHumanoid(player)
	if not humanoid then
		return false
	end

	return humanoid.Health > 0
end

local function isCoolingDown(userId: number): boolean
	local last = lastRequestAtByUserId[userId]
	if not last then
		return false
	end

	return (os.clock() - last) < GrabConfig.RequestCooldownSeconds
end

local function markRequest(userId: number)
	lastRequestAtByUserId[userId] = os.clock()
end

local function setHeldAttributes(giant: Player?, target: Player?)
	if giant then
		if target then
			giant:SetAttribute(HELD_TARGET_ATTRIBUTE, target.UserId)
		else
			giant:SetAttribute(HELD_TARGET_ATTRIBUTE, nil)
		end
	end

	if target then
		if giant then
			target:SetAttribute(HELD_BY_ATTRIBUTE, giant.UserId)
		else
			target:SetAttribute(HELD_BY_ATTRIBUTE, nil)
		end
	end
end

local function clearHoldByGiantUserId(giantUserId: number, reason: string, placeCFrame: CFrame?)
	local targetUserId = heldTargetByGiantUserId[giantUserId]
	if not targetUserId then
		return
	end

	local giant = getPlayerByUserId(giantUserId)
	local target = getPlayerByUserId(targetUserId)

	heldTargetByGiantUserId[giantUserId] = nil
	heldByTargetUserId[targetUserId] = nil

	if target then
		local targetCharacter = target.Character
		if targetCharacter then
			local targetRoot = getHumanoidRootPart(target)
			if targetRoot then
				targetRoot.Anchored = false
			end

			local targetHumanoid = getHumanoid(target)
			if targetHumanoid then
				targetHumanoid.AutoRotate = true
			end

			if placeCFrame then
				targetCharacter:PivotTo(placeCFrame)
			end
		end
	end

	setHeldAttributes(giant, nil)
	setHeldAttributes(nil, target)

	debugLog(string.format("Released hold giantUserId=%d targetUserId=%d reason=%s", giantUserId, targetUserId, reason))
end

local function rejectGrab(player: Player, reason: string)
	debugWarn(string.format("Rejected GrabRequest giantUserId=%d reason=%s", player.UserId, reason))
end

local function rejectPlace(player: Player, reason: string)
	debugWarn(string.format("Rejected PlaceRequest giantUserId=%d reason=%s", player.UserId, reason))
end

local function resolveGrabTarget(payload: unknown): (Player?, string?)
	if type(payload) ~= "number" then
		return nil, "malformed_payload"
	end

	local targetUserId = payload
	if targetUserId % 1 ~= 0 then
		return nil, "target_user_id_not_integer"
	end

	local target = getPlayerByUserId(targetUserId)
	if not target then
		return nil, "target_not_found"
	end

	return target, nil
end

local function getDesiredPlacePosition(giantRoot: BasePart, payload: unknown): (Vector3?, string?)
	if payload == nil then
		return giantRoot.Position + giantRoot.CFrame.LookVector * GrabConfig.DefaultPlaceDistanceStuds, nil
	end

	if typeof(payload) ~= "Vector3" then
		return nil, "malformed_payload"
	end

	local desiredPosition = payload :: Vector3
	local delta = desiredPosition - giantRoot.Position
	local deltaMagnitude = delta.Magnitude

	if deltaMagnitude < 0.001 then
		return giantRoot.Position + giantRoot.CFrame.LookVector * GrabConfig.DefaultPlaceDistanceStuds, nil
	end

	if deltaMagnitude > GrabConfig.PlaceRangeStuds then
		desiredPosition = giantRoot.Position + delta.Unit * GrabConfig.PlaceRangeStuds
	end

	return desiredPosition, nil
end

local function validatePlacePosition(giant: Player, target: Player, desiredPosition: Vector3): (CFrame?, string?)
	local giantRoot = getHumanoidRootPart(giant)
	if not giantRoot then
		return nil, "giant_root_missing"
	end

	if (desiredPosition - giantRoot.Position).Magnitude > GrabConfig.PlaceRangeStuds then
		return nil, "place_out_of_range"
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.FilterDescendantsInstances = {}

	local giantCharacter = giant.Character
	if giantCharacter then
		table.insert(raycastParams.FilterDescendantsInstances, giantCharacter)
	end

	local targetCharacter = target.Character
	if targetCharacter then
		table.insert(raycastParams.FilterDescendantsInstances, targetCharacter)
	end

	local rayOrigin = desiredPosition + Vector3.new(0, GrabConfig.PlaceProbeHeightStuds, 0)
	local rayDirection = Vector3.new(0, -GrabConfig.PlaceProbeDepthStuds, 0)
	local rayResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if not rayResult then
		return nil, "place_has_no_floor"
	end

	local finalPosition = rayResult.Position + Vector3.new(0, GrabConfig.PlaceYOffsetStuds, 0)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Blacklist
	overlapParams.FilterDescendantsInstances = {}
	if giantCharacter then
		table.insert(overlapParams.FilterDescendantsInstances, giantCharacter)
	end
	if targetCharacter then
		table.insert(overlapParams.FilterDescendantsInstances, targetCharacter)
	end

	local overlapCenter = finalPosition + Vector3.new(0, GrabConfig.PlaceClearanceSize.Y * 0.5, 0)
	local overlaps = Workspace:GetPartBoundsInBox(CFrame.new(overlapCenter), GrabConfig.PlaceClearanceSize, overlapParams)
	for _, part in overlaps do
		if part.CanCollide then
			return nil, "place_blocked"
		end
	end

	return CFrame.new(finalPosition, finalPosition + giantRoot.CFrame.LookVector), nil
end

local function updateHeldTarget(giant: Player, target: Player)
	local giantRoot = getHumanoidRootPart(giant)
	local targetCharacter = target.Character
	local targetRoot = getHumanoidRootPart(target)
	local targetHumanoid = getHumanoid(target)

	if not giantRoot or not targetCharacter or not targetRoot or not targetHumanoid then
		clearHoldByGiantUserId(giant.UserId, "missing_character_parts", nil)
		return
	end

	if not isPlayerRole(giant, RoleConfig.Roles.Giant) then
		clearHoldByGiantUserId(giant.UserId, "giant_role_invalid", nil)
		return
	end

	if not isPlayerRole(target, RoleConfig.Roles.Tinyfolk) then
		clearHoldByGiantUserId(giant.UserId, "target_role_invalid", nil)
		return
	end

	if not isAlive(giant) or not isAlive(target) then
		clearHoldByGiantUserId(giant.UserId, "actor_not_alive", nil)
		return
	end

	targetRoot.Anchored = true
	targetHumanoid.AutoRotate = false

	local holdCFrame = giantRoot.CFrame * CFrame.new(GrabConfig.HoldOffset)
	targetCharacter:PivotTo(CFrame.new(holdCFrame.Position, holdCFrame.Position + giantRoot.CFrame.LookVector))
end

local remotesFolder = ensureRemotesFolder()
local grabRequestRemote = ensureRemote(remotesFolder, GRAB_REMOTE_NAME)
local placeRequestRemote = ensureRemote(remotesFolder, PLACE_REMOTE_NAME)

grabRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if isCoolingDown(player.UserId) then
		rejectGrab(player, "request_cooldown")
		return
	end

	markRequest(player.UserId)

	if not isPlayerRole(player, RoleConfig.Roles.Giant) then
		rejectGrab(player, "requester_not_giant")
		return
	end

	if heldTargetByGiantUserId[player.UserId] then
		rejectGrab(player, "giant_already_holding")
		return
	end

	if heldByTargetUserId[player.UserId] then
		rejectGrab(player, "requester_currently_held")
		return
	end

	if not isAlive(player) then
		rejectGrab(player, "requester_not_alive")
		return
	end

	local target, payloadError = resolveGrabTarget(payload)
	if not target then
		rejectGrab(player, payloadError or "invalid_target")
		return
	end

	if target == player then
		rejectGrab(player, "self_target")
		return
	end

	if not isPlayerRole(target, RoleConfig.Roles.Tinyfolk) then
		rejectGrab(player, "target_not_tinyfolk")
		return
	end

	if heldByTargetUserId[target.UserId] then
		rejectGrab(player, "target_already_held")
		return
	end

	if not isAlive(target) then
		rejectGrab(player, "target_not_alive")
		return
	end

	local giantRoot = getHumanoidRootPart(player)
	local targetRoot = getHumanoidRootPart(target)
	if not giantRoot or not targetRoot then
		rejectGrab(player, "missing_humanoid_root_part")
		return
	end

	local distance = (targetRoot.Position - giantRoot.Position).Magnitude
	if distance > GrabConfig.GrabRangeStuds then
		rejectGrab(player, string.format("target_out_of_range distance=%.2f max=%.2f", distance, GrabConfig.GrabRangeStuds))
		return
	end

	heldTargetByGiantUserId[player.UserId] = target.UserId
	heldByTargetUserId[target.UserId] = player.UserId
	setHeldAttributes(player, target)

	updateHeldTarget(player, target)

	debugLog(string.format("Accepted GrabRequest giantUserId=%d targetUserId=%d distance=%.2f", player.UserId, target.UserId, distance))
end)

placeRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if isCoolingDown(player.UserId) then
		rejectPlace(player, "request_cooldown")
		return
	end

	markRequest(player.UserId)

	if not isPlayerRole(player, RoleConfig.Roles.Giant) then
		rejectPlace(player, "requester_not_giant")
		return
	end

	local targetUserId = heldTargetByGiantUserId[player.UserId]
	if not targetUserId then
		rejectPlace(player, "giant_not_holding_target")
		return
	end

	local target = getPlayerByUserId(targetUserId)
	if not target then
		clearHoldByGiantUserId(player.UserId, "target_missing_on_place", nil)
		rejectPlace(player, "target_not_found")
		return
	end

	local giantRoot = getHumanoidRootPart(player)
	if not giantRoot then
		clearHoldByGiantUserId(player.UserId, "giant_root_missing_on_place", nil)
		rejectPlace(player, "giant_root_missing")
		return
	end

	local desiredPosition, placePayloadError = getDesiredPlacePosition(giantRoot, payload)
	if not desiredPosition then
		rejectPlace(player, placePayloadError or "malformed_payload")
		return
	end

	local placeCFrame, placeError = validatePlacePosition(player, target, desiredPosition)
	if not placeCFrame then
		rejectPlace(player, placeError or "invalid_place")
		return
	end

	clearHoldByGiantUserId(player.UserId, "placed", placeCFrame)

	debugLog(string.format("Accepted PlaceRequest giantUserId=%d targetUserId=%d", player.UserId, target.UserId))
end)

local function setupPlayer(player: Player)
	player:SetAttribute(HELD_TARGET_ATTRIBUTE, nil)
	player:SetAttribute(HELD_BY_ATTRIBUTE, nil)

	player.CharacterAdded:Connect(function()
		local giantHolding = heldTargetByGiantUserId[player.UserId]
		if giantHolding then
			clearHoldByGiantUserId(player.UserId, "giant_character_reset", nil)
		end

		local heldByGiant = heldByTargetUserId[player.UserId]
		if heldByGiant then
			clearHoldByGiantUserId(heldByGiant, "target_character_reset", nil)
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, existingPlayer in Players:GetPlayers() do
	setupPlayer(existingPlayer)
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil

	local giantHolding = heldTargetByGiantUserId[player.UserId]
	if giantHolding then
		clearHoldByGiantUserId(player.UserId, "giant_left_game", nil)
	end

	local heldByGiant = heldByTargetUserId[player.UserId]
	if heldByGiant then
		clearHoldByGiantUserId(heldByGiant, "target_left_game", nil)
	end
end)

RunService.Heartbeat:Connect(function()
	for giantUserId, targetUserId in heldTargetByGiantUserId do
		local giant = getPlayerByUserId(giantUserId)
		local target = getPlayerByUserId(targetUserId)
		if not giant or not target then
			clearHoldByGiantUserId(giantUserId, "player_missing_during_hold", nil)
		else
			updateHeldTarget(giant, target)
		end
	end
end)

debugLog("GrabService initialized")
