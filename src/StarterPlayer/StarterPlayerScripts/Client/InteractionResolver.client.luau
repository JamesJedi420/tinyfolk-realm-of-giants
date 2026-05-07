--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local SpecialistConfig = require(Config:WaitForChild("SpecialistConfig"))
local StationConfig = require(Config:WaitForChild("StationConfig"))
local ShrineConfig = require(Config:WaitForChild("ShrineConfig"))
local EscapeConfig = require(Config:WaitForChild("EscapeConfig"))
local ConstructionConfig = require(Config:WaitForChild("ConstructionConfig"))
local UpgradeBoardConfig = require(Config:WaitForChild("UpgradeBoardConfig"))

local REMOTES_FOLDER_NAME = "Remotes"

local STATION_ACTIVATE_REMOTE_NAME = "StationActivateRequest"
local SHRINE_ACTIVATE_REMOTE_NAME = "ShrineActivateRequest"
local WAREHOUSE_DELIVER_REMOTE_NAME = "WarehouseDeliverRequest"
local ESCAPE_ATTEMPT_REMOTE_NAME = "EscapeAttemptRequest"
local CONSTRUCTION_BUILD_REMOTE_NAME = "ConstructionBuildRequest"
local UPGRADE_SELECT_REMOTE_NAME = "UpgradeBoardSelectRequest"
local SPECIALIST_ASSIGN_REMOTE_NAME = "SpecialistAssignRequest"
local SPECIALIST_CLEAR_REMOTE_NAME = "SpecialistClearRequest"

local INTERACT_KEY = Enum.KeyCode.F

local localPlayer = Players.LocalPlayer
local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)

local stationActivateRemote = remotesFolder:WaitForChild(STATION_ACTIVATE_REMOTE_NAME) :: RemoteEvent
local shrineActivateRemote = remotesFolder:WaitForChild(SHRINE_ACTIVATE_REMOTE_NAME) :: RemoteEvent
local warehouseDeliverRemote = remotesFolder:WaitForChild(WAREHOUSE_DELIVER_REMOTE_NAME) :: RemoteEvent
local escapeAttemptRemote = remotesFolder:WaitForChild(ESCAPE_ATTEMPT_REMOTE_NAME) :: RemoteEvent
local constructionBuildRemote = remotesFolder:WaitForChild(CONSTRUCTION_BUILD_REMOTE_NAME) :: RemoteEvent
local upgradeSelectRemote = remotesFolder:WaitForChild(UPGRADE_SELECT_REMOTE_NAME) :: RemoteEvent
local specialistAssignRemote = remotesFolder:WaitForChild(SPECIALIST_ASSIGN_REMOTE_NAME) :: RemoteEvent
local specialistClearRemote = remotesFolder:WaitForChild(SPECIALIST_CLEAR_REMOTE_NAME) :: RemoteEvent

local INTERACTION_REPEAT_BLOCK_SECONDS = 0.2
local lastSentAtBySignature: {[string]: number} = {}

type CandidateAction =
	"escape_attempt"
	| "construction_build"
	| "upgrade_board_progress"
	| "warehouse_deliver"
	| "station_pickup_or_assign"
	| "shrine_assign_worshipper"

type Candidate = {
	action: CandidateAction,
	targetId: string,
	distance: number,
	priority: number,
	mode: string,
	payload: any,
}

local PRIORITY_BY_ACTION: {[CandidateAction]: number} = {
	escape_attempt = 1,
	construction_build = 2,
	upgrade_board_progress = 3,
	warehouse_deliver = 4,
	station_pickup_or_assign = 5,
	shrine_assign_worshipper = 6,
}

local function debugLog(message: string)
	print(string.format("[InteractionResolver] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[InteractionResolver] %s", message))
end

local function getHumanoidRootPart(character: Model?): BasePart?
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function startsWithPrefix(name: string, prefix: string): boolean
	return string.match(name, "^" .. prefix) ~= nil
end

local function pushCandidate(candidates: {Candidate}, candidate: Candidate)
	table.insert(candidates, candidate)
end

local function chooseNextUpgradeId(): string?
	for _, option in UpgradeBoardConfig.UpgradeOptions do
		local upgradeId = option.id
		local alreadySelected = localPlayer:GetAttribute("GiantUpgrade_" .. upgradeId) == true
		if not alreadySelected then
			return upgradeId
		end
	end

	return nil
end

local function getProducedForMaterialStation(stationPart: BasePart): number
	if startsWithPrefix(stationPart.Name, StationConfig.MiningStationNamePrefix) then
		local stoneProduced = stationPart:GetAttribute("StoneProducedTotal")
		if type(stoneProduced) == "number" then
			return stoneProduced
		end
		return 0
	end

	local woodProduced = stationPart:GetAttribute("WoodProducedTotal")
	if type(woodProduced) == "number" then
		return woodProduced
	end

	return 0
end

local function collectCandidates(localRoot: BasePart): {Candidate}
	local mapRoot = Workspace:FindFirstChild("Map")
	if not mapRoot then
		return {}
	end

	local role = localPlayer:GetAttribute("Role")
	local specialistRoleValue = localPlayer:GetAttribute("SpecialistRole")
	local specialistRole = if type(specialistRoleValue) == "string" then specialistRoleValue else SpecialistConfig.SpecialistRoles.None

	local isTinyfolk = role == RoleConfig.Roles.Tinyfolk
	local isGiant = role == RoleConfig.Roles.Giant
	local nextUpgradeId = if isGiant then chooseNextUpgradeId() else nil

	local candidates: {Candidate} = {}

	for _, descendant in mapRoot:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		local distance = (descendant.Position - localRoot.Position).Magnitude
		local targetId = descendant.Name

		if isTinyfolk and startsWithPrefix(targetId, EscapeConfig.EscapeRouteNamePrefix) and distance <= EscapeConfig.TriggerRadiusStuds then
			pushCandidate(candidates, {
				action = "escape_attempt",
				targetId = targetId,
				distance = distance,
				priority = PRIORITY_BY_ACTION.escape_attempt,
				mode = "attempt",
				payload = targetId,
			})
		end

		if startsWithPrefix(targetId, ConstructionConfig.ConstructionSiteNamePrefix) and distance <= ConstructionConfig.InteractionRangeStuds then
			pushCandidate(candidates, {
				action = "construction_build",
				targetId = targetId,
				distance = distance,
				priority = PRIORITY_BY_ACTION.construction_build,
				mode = "build",
				payload = targetId,
			})
		end

		if nextUpgradeId and startsWithPrefix(targetId, UpgradeBoardConfig.BoardNamePrefix) and distance <= UpgradeBoardConfig.InteractionRangeStuds then
			pushCandidate(candidates, {
				action = "upgrade_board_progress",
				targetId = targetId,
				distance = distance,
				priority = PRIORITY_BY_ACTION.upgrade_board_progress,
				mode = "progress_next",
				payload = {
					boardId = targetId,
					upgradeId = nextUpgradeId,
				},
			})
		end

		if startsWithPrefix(targetId, StationConfig.WarehouseNamePrefix) and distance <= StationConfig.ActivationRangeStuds then
			pushCandidate(candidates, {
				action = "warehouse_deliver",
				targetId = targetId,
				distance = distance,
				priority = PRIORITY_BY_ACTION.warehouse_deliver,
				mode = "deliver",
				payload = targetId,
			})
		end

		if startsWithPrefix(targetId, StationConfig.StationNamePrefix) or startsWithPrefix(targetId, StationConfig.MiningStationNamePrefix) then
			if distance <= StationConfig.ActivationRangeStuds then
				local requiredSpecialistRole = StationConfig.RequiredSpecialistRoleByStationId[targetId]
				if type(requiredSpecialistRole) ~= "string" then
					pushCandidate(candidates, {
						action = "station_pickup_or_assign",
						targetId = targetId,
						distance = distance,
						priority = PRIORITY_BY_ACTION.station_pickup_or_assign,
						mode = "activate",
						payload = targetId,
					})
				elseif isTinyfolk then
					if specialistRole == requiredSpecialistRole then
						local producedTotal = getProducedForMaterialStation(descendant)
						local mode = if producedTotal > 0 then "pickup" else "activate"
						pushCandidate(candidates, {
							action = "station_pickup_or_assign",
							targetId = targetId,
							distance = distance,
							priority = PRIORITY_BY_ACTION.station_pickup_or_assign,
							mode = mode,
							payload = targetId,
						})
					elseif specialistRole == SpecialistConfig.SpecialistRoles.None then
						pushCandidate(candidates, {
							action = "station_pickup_or_assign",
							targetId = targetId,
							distance = distance,
							priority = PRIORITY_BY_ACTION.station_pickup_or_assign,
							mode = "assign",
							payload = {
								specialistRole = requiredSpecialistRole,
								assignedStationId = targetId,
							},
						})
					else
						pushCandidate(candidates, {
							action = "station_pickup_or_assign",
							targetId = targetId,
							distance = distance,
							priority = PRIORITY_BY_ACTION.station_pickup_or_assign,
							mode = "assign_replace",
							payload = {
								specialistRole = requiredSpecialistRole,
								assignedStationId = targetId,
							},
						})
					end
				end
			end
		end

		if startsWithPrefix(targetId, ShrineConfig.ShrineNamePrefix) and distance <= ShrineConfig.ActivationRangeStuds and isTinyfolk then
			if specialistRole == SpecialistConfig.SpecialistRoles.Worshipper then
				pushCandidate(candidates, {
					action = "shrine_assign_worshipper",
					targetId = targetId,
					distance = distance,
					priority = PRIORITY_BY_ACTION.shrine_assign_worshipper,
					mode = "activate",
					payload = targetId,
				})
			elseif specialistRole == SpecialistConfig.SpecialistRoles.None then
				pushCandidate(candidates, {
					action = "shrine_assign_worshipper",
					targetId = targetId,
					distance = distance,
					priority = PRIORITY_BY_ACTION.shrine_assign_worshipper,
					mode = "assign_worshipper",
					payload = {
						specialistRole = SpecialistConfig.SpecialistRoles.Worshipper,
						assignedStationId = targetId,
					},
				})
			else
				pushCandidate(candidates, {
					action = "shrine_assign_worshipper",
					targetId = targetId,
					distance = distance,
					priority = PRIORITY_BY_ACTION.shrine_assign_worshipper,
					mode = "assign_worshipper_replace",
					payload = {
						specialistRole = SpecialistConfig.SpecialistRoles.Worshipper,
						assignedStationId = targetId,
					},
				})
			end
		end
	end

	return candidates
end

local function pickWinningCandidate(candidates: {Candidate}): Candidate?
	table.sort(candidates, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end

		if a.distance ~= b.distance then
			return a.distance < b.distance
		end

		return a.targetId < b.targetId
	end)

	return candidates[1]
end

local function getCandidateSignature(candidate: Candidate): string
	if candidate.action == "upgrade_board_progress" and type(candidate.payload) == "table" and type(candidate.payload.upgradeId) == "string" then
		return string.format("%s|%s|%s|%s", candidate.action, candidate.targetId, candidate.mode, candidate.payload.upgradeId)
	end

	return string.format("%s|%s|%s", candidate.action, candidate.targetId, candidate.mode)
end

local function shouldSendCandidate(candidate: Candidate): boolean
	local signature = getCandidateSignature(candidate)
	local now = os.clock()
	local lastSentAt = lastSentAtBySignature[signature]
	if type(lastSentAt) == "number" and (now - lastSentAt) < INTERACTION_REPEAT_BLOCK_SECONDS then
		debugLog(string.format("Suppressed duplicate interaction signature=%s", signature))
		return false
	end

	lastSentAtBySignature[signature] = now
	return true
end

local function fireCandidate(candidate: Candidate)
	local function sendAssignThenActivate(assignPayload: any, activateRemote: RemoteEvent, activatePayload: any)
		specialistAssignRemote:FireServer(assignPayload)
		-- Small defer helps ensure server-side SpecialistRole is updated before activation validation runs.
		task.delay(0.05, function()
			activateRemote:FireServer(activatePayload)
		end)
	end

	if candidate.action == "escape_attempt" then
		escapeAttemptRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "construction_build" then
		constructionBuildRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "upgrade_board_progress" then
		upgradeSelectRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "warehouse_deliver" then
		warehouseDeliverRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "station_pickup_or_assign" then
		if candidate.mode == "assign" then
			sendAssignThenActivate(candidate.payload, stationActivateRemote, candidate.targetId)
			return
		end

		if candidate.mode == "assign_replace" then
			sendAssignThenActivate(candidate.payload, stationActivateRemote, candidate.targetId)
			return
		end

		if candidate.mode == "clear_then_assign" then
			specialistClearRemote:FireServer()
			return
		end

		stationActivateRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "shrine_assign_worshipper" then
		if candidate.mode == "assign_worshipper" then
			sendAssignThenActivate(candidate.payload, shrineActivateRemote, candidate.targetId)
			return
		end

		if candidate.mode == "assign_worshipper_replace" then
			sendAssignThenActivate(candidate.payload, shrineActivateRemote, candidate.targetId)
			return
		end

		if candidate.mode == "clear_then_assign_worshipper" then
			specialistClearRemote:FireServer()
			return
		end

		shrineActivateRemote:FireServer(candidate.payload)
		return
	end
end

local function requestContextInteraction()
	local root = getHumanoidRootPart(localPlayer.Character)
	if not root then
		debugWarn("Resolved action=none target=none reason=humanoid_root_missing")
		return
	end

	local candidates = collectCandidates(root)
	local winner = pickWinningCandidate(candidates)
	if not winner then
		debugLog("Resolved action=none target=none mode=none")
		return
	end

	debugLog(string.format(
		"Resolved action=%s target=%s mode=%s priority=%d distance=%.2f",
		winner.action,
		winner.targetId,
		winner.mode,
		winner.priority,
		winner.distance
	))

	if not shouldSendCandidate(winner) then
		return
	end

	fireCandidate(winner)
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end

	if UserInputService:GetFocusedTextBox() ~= nil then
		return
	end

	if input.KeyCode == INTERACT_KEY then
		requestContextInteraction()
	end
end)

debugLog("Input hook active (F=Context Interaction Resolver)")
