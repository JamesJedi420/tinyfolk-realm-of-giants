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
local lastSentAtBySignature: { [string]: number } = {}
local activeConstructionTaskSiteId: string? = nil
local activeConstructionTaskToken = 0
local activeStationTaskStationId: string? = nil
local activeStationTaskToken = 0
local activeShrineTaskShrineId: string? = nil
local activeShrineTaskToken = 0

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

local PRIORITY_BY_ACTION: { [CandidateAction]: number } = {
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

local function getHumanoidRootPart(character: Instance?): BasePart?
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

local function pushCandidate(candidates: { Candidate }, candidate: Candidate)
	table.insert(candidates, candidate)
end

local function magnitudeBetweenPositions(a: any, b: any): number
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function getPriority(action: CandidateAction): number
	return (PRIORITY_BY_ACTION :: any)[action]
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

local function collectCandidates(localRoot: BasePart): { Candidate }
	local mapRoot = Workspace:FindFirstChild("Map")
	if not mapRoot then
		return {}
	end

	local role = localPlayer:GetAttribute("Role")
	local specialistRoleValue = localPlayer:GetAttribute("SpecialistRole")
	local specialistRole = if type(specialistRoleValue) == "string"
		then specialistRoleValue
		else SpecialistConfig.SpecialistRoles.None

	local isTinyfolk = role == RoleConfig.Roles.Tinyfolk
	local isGiant = role == RoleConfig.Roles.Giant
	local nextUpgradeId = if isGiant then chooseNextUpgradeId() else nil

	local candidates: { Candidate } = {}

	for _, descendant in mapRoot:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		local part = descendant :: BasePart

		local distance = magnitudeBetweenPositions(part.Position :: any, localRoot.Position :: any)
		local targetId = part.Name

		if
			isTinyfolk
			and startsWithPrefix(targetId, EscapeConfig.EscapeRouteNamePrefix)
			and distance <= EscapeConfig.TriggerRadiusStuds
		then
			pushCandidate(candidates, {
				action = "escape_attempt",
				targetId = targetId,
				distance = distance,
				priority = getPriority("escape_attempt"),
				mode = "attempt",
				payload = targetId,
			})
		end

		if
			startsWithPrefix(targetId, ConstructionConfig.ConstructionSiteNamePrefix)
			and distance <= ConstructionConfig.InteractionRangeStuds
		then
			pushCandidate(candidates, {
				action = "construction_build",
				targetId = targetId,
				distance = distance,
				priority = getPriority("construction_build"),
				mode = "build",
				payload = targetId,
			})
		end

		if
			nextUpgradeId
			and startsWithPrefix(targetId, UpgradeBoardConfig.BoardNamePrefix)
			and distance <= UpgradeBoardConfig.InteractionRangeStuds
		then
			pushCandidate(candidates, {
				action = "upgrade_board_progress",
				targetId = targetId,
				distance = distance,
				priority = getPriority("upgrade_board_progress"),
				mode = "progress_next",
				payload = {
					boardId = targetId,
					upgradeId = nextUpgradeId,
				},
			})
		end

		if
			startsWithPrefix(targetId, StationConfig.WarehouseNamePrefix)
			and distance <= StationConfig.ActivationRangeStuds
		then
			pushCandidate(candidates, {
				action = "warehouse_deliver",
				targetId = targetId,
				distance = distance,
				priority = getPriority("warehouse_deliver"),
				mode = "deliver",
				payload = targetId,
			})
		end

		if
			startsWithPrefix(targetId, StationConfig.StationNamePrefix)
			or startsWithPrefix(targetId, StationConfig.MiningStationNamePrefix)
		then
			if distance <= StationConfig.ActivationRangeStuds then
				local requiredSpecialistRole = StationConfig.RequiredSpecialistRoleByStationId[targetId]
				if type(requiredSpecialistRole) ~= "string" then
					pushCandidate(candidates, {
						action = "station_pickup_or_assign",
						targetId = targetId,
						distance = distance,
						priority = getPriority("station_pickup_or_assign"),
						mode = "activate",
						payload = targetId,
					})
				elseif isTinyfolk then
					if specialistRole == requiredSpecialistRole then
						local producedTotal = getProducedForMaterialStation(part)
						local mode = if producedTotal > 0 then "pickup" else "activate"
						pushCandidate(candidates, {
							action = "station_pickup_or_assign",
							targetId = targetId,
							distance = distance,
							priority = getPriority("station_pickup_or_assign"),
							mode = mode,
							payload = targetId,
						})
					elseif specialistRole == SpecialistConfig.SpecialistRoles.None then
						pushCandidate(candidates, {
							action = "station_pickup_or_assign",
							targetId = targetId,
							distance = distance,
							priority = getPriority("station_pickup_or_assign"),
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
							priority = getPriority("station_pickup_or_assign"),
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

		if
			startsWithPrefix(targetId, ShrineConfig.ShrineNamePrefix)
			and distance <= ShrineConfig.ActivationRangeStuds
			and isTinyfolk
		then
			if specialistRole == SpecialistConfig.SpecialistRoles.Worshipper then
				pushCandidate(candidates, {
					action = "shrine_assign_worshipper",
					targetId = targetId,
					distance = distance,
					priority = getPriority("shrine_assign_worshipper"),
					mode = "activate",
					payload = targetId,
				})
			elseif specialistRole == SpecialistConfig.SpecialistRoles.None then
				pushCandidate(candidates, {
					action = "shrine_assign_worshipper",
					targetId = targetId,
					distance = distance,
					priority = getPriority("shrine_assign_worshipper"),
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
					priority = getPriority("shrine_assign_worshipper"),
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

local function pickWinningCandidate(candidates: { Candidate }): Candidate?
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
	if
		candidate.action == "upgrade_board_progress"
		and type(candidate.payload) == "table"
		and type(candidate.payload.upgradeId) == "string"
	then
		return string.format(
			"%s|%s|%s|%s",
			candidate.action,
			candidate.targetId,
			candidate.mode,
			candidate.payload.upgradeId
		)
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

local function cancelActiveConstructionTask(reason: string)
	if activeConstructionTaskSiteId == nil then
		return
	end

	local siteId = activeConstructionTaskSiteId
	activeConstructionTaskSiteId = nil
	activeConstructionTaskToken += 1

	constructionBuildRemote:FireServer({
		siteId = siteId,
		mode = "cancel",
		now = os.clock(),
	})
	debugLog(string.format("Sent construction task cancel siteId=%s reason=%s", siteId, reason))
end

local function cancelActiveStationTask(reason: string)
	if activeStationTaskStationId == nil then
		return
	end

	local stationId = activeStationTaskStationId
	activeStationTaskStationId = nil
	activeStationTaskToken += 1

	stationActivateRemote:FireServer({
		stationId = stationId,
		mode = "cancel",
		now = os.clock(),
	})
	debugLog(string.format("Sent station task cancel stationId=%s reason=%s", stationId, reason))
end

local function cancelActiveShrineTask(reason: string)
	if activeShrineTaskShrineId == nil then
		return
	end

	local shrineId = activeShrineTaskShrineId
	activeShrineTaskShrineId = nil
	activeShrineTaskToken += 1

	shrineActivateRemote:FireServer({
		shrineId = shrineId,
		mode = "cancel",
		now = os.clock(),
	})
	debugLog(string.format("Sent shrine task cancel shrineId=%s reason=%s", shrineId, reason))
end

local function beginConstructionTask(candidate: Candidate)
	cancelActiveConstructionTask("new_begin")
	cancelActiveStationTask("construction_begin")
	cancelActiveShrineTask("construction_begin")

	activeConstructionTaskSiteId = candidate.targetId
	activeConstructionTaskToken += 1
	local tokenAtBegin = activeConstructionTaskToken

	constructionBuildRemote:FireServer({
		siteId = candidate.targetId,
		mode = "begin",
		now = os.clock(),
	})

	debugLog(
		string.format(
			"Sent construction task begin siteId=%s duration=%.2f",
			candidate.targetId,
			ConstructionConfig.TaskDurationSeconds
		)
	)

	task.delay(ConstructionConfig.TaskDurationSeconds, function()
		if activeConstructionTaskSiteId ~= candidate.targetId then
			return
		end
		if activeConstructionTaskToken ~= tokenAtBegin then
			return
		end

		constructionBuildRemote:FireServer({
			siteId = candidate.targetId,
			mode = "complete",
			now = os.clock(),
			qteTapAt = os.clock(),
		})
		activeConstructionTaskSiteId = nil
		activeConstructionTaskToken += 1
		debugLog(string.format("Sent construction task complete siteId=%s", candidate.targetId))
	end)
end

local function beginStationTask(candidate: Candidate)
	cancelActiveConstructionTask("station_begin")
	cancelActiveStationTask("new_begin")
	cancelActiveShrineTask("station_begin")

	activeStationTaskStationId = candidate.targetId
	activeStationTaskToken += 1
	local tokenAtBegin = activeStationTaskToken

	stationActivateRemote:FireServer({
		stationId = candidate.targetId,
		mode = "begin",
		now = os.clock(),
	})

	debugLog(
		string.format(
			"Sent station task begin stationId=%s duration=%.2f",
			candidate.targetId,
			StationConfig.TaskDurationSeconds
		)
	)

	task.delay(StationConfig.TaskDurationSeconds, function()
		if activeStationTaskStationId ~= candidate.targetId then
			return
		end
		if activeStationTaskToken ~= tokenAtBegin then
			return
		end

		stationActivateRemote:FireServer({
			stationId = candidate.targetId,
			mode = "complete",
			now = os.clock(),
			qteTapAt = os.clock(),
		})
		activeStationTaskStationId = nil
		activeStationTaskToken += 1
		debugLog(string.format("Sent station task complete stationId=%s", candidate.targetId))
	end)
end

local function beginShrineTask(candidate: Candidate)
	cancelActiveConstructionTask("shrine_begin")
	cancelActiveStationTask("shrine_begin")
	cancelActiveShrineTask("new_begin")

	activeShrineTaskShrineId = candidate.targetId
	activeShrineTaskToken += 1
	local tokenAtBegin = activeShrineTaskToken

	shrineActivateRemote:FireServer({
		shrineId = candidate.targetId,
		mode = "begin",
		now = os.clock(),
	})

	debugLog(
		string.format(
			"Sent shrine task begin shrineId=%s duration=%.2f",
			candidate.targetId,
			ShrineConfig.TaskDurationSeconds
		)
	)

	task.delay(ShrineConfig.TaskDurationSeconds, function()
		if activeShrineTaskShrineId ~= candidate.targetId then
			return
		end
		if activeShrineTaskToken ~= tokenAtBegin then
			return
		end

		shrineActivateRemote:FireServer({
			shrineId = candidate.targetId,
			mode = "complete",
			now = os.clock(),
			qteTapAt = os.clock(),
		})
		activeShrineTaskShrineId = nil
		activeShrineTaskToken += 1
		debugLog(string.format("Sent shrine task complete shrineId=%s", candidate.targetId))
	end)
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
	local resolvedWinner = winner :: Candidate

	debugLog(
		string.format(
			"Resolved action=%s target=%s mode=%s priority=%d distance=%.2f",
			resolvedWinner.action,
			resolvedWinner.targetId,
			resolvedWinner.mode,
			resolvedWinner.priority,
			resolvedWinner.distance
		)
	)

	if not shouldSendCandidate(resolvedWinner) then
		return
	end

	if resolvedWinner.action == "construction_build" then
		beginConstructionTask(resolvedWinner)
		return
	end

	if resolvedWinner.action == "station_pickup_or_assign" and resolvedWinner.mode == "activate" then
		beginStationTask(resolvedWinner)
		return
	end

	if resolvedWinner.action == "shrine_assign_worshipper" and resolvedWinner.mode == "activate" then
		beginShrineTask(resolvedWinner)
		return
	end

	fireCandidate(resolvedWinner)
end

UserInputService.InputBegan:Connect(function(input: any, gameProcessedEvent: boolean)
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

UserInputService.InputEnded:Connect(function(input: any, _gameProcessedEvent: boolean)
	if input.KeyCode ~= INTERACT_KEY then
		return
	end

	cancelActiveConstructionTask("input_ended")
	cancelActiveStationTask("input_ended")
	cancelActiveShrineTask("input_ended")
end)

debugLog("Input hook active (F=Context Interaction Resolver)")
