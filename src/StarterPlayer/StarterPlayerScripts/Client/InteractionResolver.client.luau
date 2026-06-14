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
local LaborActionConfig = require(Config:WaitForChild("LaborActionConfig"))
local EscapeConfig = require(Config:WaitForChild("EscapeConfig"))
local ConstructionConfig = require(Config:WaitForChild("ConstructionConfig"))
local UpgradeBoardConfig = require(Config:WaitForChild("UpgradeBoardConfig"))
local VillageWorksiteUpgradeConfig = require(Config:WaitForChild("VillageWorksiteUpgradeConfig"))
local TinyfolkLaborUpgradeConfig = require(Config:WaitForChild("TinyfolkLaborUpgradeConfig"))
local RemoteControlStationConfig = require(Config:WaitForChild("RemoteControlStationConfig"))
local DefensivePropConfig = require(Config:WaitForChild("DefensivePropConfig"))
local CaptureConfig = require(Config:WaitForChild("CaptureConfig"))

local REMOTES_FOLDER_NAME = "Remotes"

local STATION_ACTIVATE_REMOTE_NAME = "StationActivateRequest"
local SHRINE_ACTIVATE_REMOTE_NAME = "ShrineActivateRequest"
local WAREHOUSE_DELIVER_REMOTE_NAME = "WarehouseDeliverRequest"
local GRANARY_DELIVER_REMOTE_NAME = "GranaryDeliverRequest"
local ESCAPE_ATTEMPT_REMOTE_NAME = "EscapeAttemptRequest"
local CONSTRUCTION_BUILD_REMOTE_NAME = "ConstructionBuildRequest"
local UPGRADE_HUB_REMOTE_NAME = "VillageUpgradeHubRequest"
local WORKSITE_UPGRADE_REMOTE_NAME = "VillageWorksiteUpgradeRequest"
local TINYFOLK_LABOR_UPGRADE_REMOTE_NAME = "TinyfolkLaborUpgradeRequest"
local REMOTE_CONTROL_STATION_REMOTE_NAME = "RemoteControlStationRequest"
local DEFENSIVE_PROP_REMOTE_NAME = "DefensivePropRequest"

local INTERACT_KEY = Enum.KeyCode.F

local localPlayer = Players.LocalPlayer
local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)

local stationActivateRemote = remotesFolder:WaitForChild(STATION_ACTIVATE_REMOTE_NAME) :: RemoteEvent
local shrineActivateRemote = remotesFolder:WaitForChild(SHRINE_ACTIVATE_REMOTE_NAME) :: RemoteEvent
local warehouseDeliverRemote = remotesFolder:WaitForChild(WAREHOUSE_DELIVER_REMOTE_NAME) :: RemoteEvent
local granaryDeliverRemote = remotesFolder:WaitForChild(GRANARY_DELIVER_REMOTE_NAME) :: RemoteEvent
local escapeAttemptRemote = remotesFolder:WaitForChild(ESCAPE_ATTEMPT_REMOTE_NAME) :: RemoteEvent
local constructionBuildRemote = remotesFolder:WaitForChild(CONSTRUCTION_BUILD_REMOTE_NAME) :: RemoteEvent
local upgradeHubRemote = remotesFolder:WaitForChild(UPGRADE_HUB_REMOTE_NAME) :: RemoteEvent
local worksiteUpgradeRemote = remotesFolder:WaitForChild(WORKSITE_UPGRADE_REMOTE_NAME) :: RemoteEvent
local tinyfolkLaborUpgradeRemote = remotesFolder:WaitForChild(TINYFOLK_LABOR_UPGRADE_REMOTE_NAME) :: RemoteEvent
local remoteControlStationRemote = remotesFolder:WaitForChild(REMOTE_CONTROL_STATION_REMOTE_NAME) :: RemoteEvent
local defensivePropRemote = remotesFolder:WaitForChild(DEFENSIVE_PROP_REMOTE_NAME) :: RemoteEvent

local INTERACTION_REPEAT_BLOCK_SECONDS = 0.2
local lastSentAtBySignature: { [string]: number } = {}
local activeConstructionTaskSiteId: string? = nil
local activeConstructionTaskToken = 0
local activeStationTaskStationId: string? = nil
local activeStationTaskToken = 0
local activeShrineTaskShrineId: string? = nil
local activeShrineTaskToken = 0
local activeRemoteControlStationId: string? = nil
local activeRemoteControlTaskToken = 0
local activeDefensivePropBreakPropId: string? = nil
local activeDefensivePropBreakToken = 0
local activeHaulHoldToken = 0
local activeHaulHold: {
	action: CandidateAction,
	targetId: string,
	mode: string,
	token: number,
}? = nil

type CandidateAction =
	"escape_attempt"
	| "defensive_prop_drop"
	| "defensive_prop_break"
	| "construction_build"
	| "upgrade_board_hub"
	| "worksite_upgrade"
	| "warehouse_deliver"
	| "granary_deliver"
	| "tinyfolk_labor_upgrade"
	| "station_pickup_or_assign"
	| "shrine_assign_worshipper"
	| "remote_control_station"

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
	defensive_prop_drop = 2,
	defensive_prop_break = 2,
	construction_build = 3,
	upgrade_board_hub = 4,
	worksite_upgrade = 4,
	warehouse_deliver = 5,
	granary_deliver = 5,
	tinyfolk_labor_upgrade = 5,
	station_pickup_or_assign = 6,
	shrine_assign_worshipper = 7,
	remote_control_station = 8,
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

local function isLocalPlayerCaptureInteractionActive(): boolean
	return localPlayer:GetAttribute(CaptureConfig.StateAttributes.CaptureActive) == true
end

local function isLocalPlayerCarriedForCounterplay(): boolean
	local carriedState = localPlayer:GetAttribute("CarriedState")
	return carriedState == "Carried" or carriedState == "Counterplay"
end

local function isDefensivePropBreakInProgress(part: BasePart): boolean
	local breakEndsAt = part:GetAttribute(DefensivePropConfig.Attributes.BreakEndsAt)
	return type(breakEndsAt) == "number" and breakEndsAt > 0
end

local function resolveUpgradeableWorksiteId(partName: string): string?
	if startsWithPrefix(partName, StationConfig.StationNamePrefix) then
		return partName
	end
	if startsWithPrefix(partName, StationConfig.MiningStationNamePrefix) then
		return partName
	end
	if startsWithPrefix(partName, StationConfig.WarehouseNamePrefix) then
		return partName
	end
	if startsWithPrefix(partName, StationConfig.GranaryNamePrefix) then
		return partName
	end
	if startsWithPrefix(partName, ShrineConfig.ShrineNamePrefix) then
		return partName
	end
	if startsWithPrefix(partName, StationConfig.FarmNamePrefix) then
		return partName
	end
	if startsWithPrefix(partName, StationConfig.PenNamePrefix) then
		return partName
	end
	if startsWithPrefix(partName, StationConfig.GuardTowerNamePrefix) then
		return partName
	end
	if startsWithPrefix(partName, StationConfig.GiantDwellingNamePrefix) then
		return partName
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

	if startsWithPrefix(stationPart.Name, StationConfig.FarmNamePrefix) then
		local foodProduced = stationPart:GetAttribute("FoodProducedTotal")
		if type(foodProduced) == "number" then
			return foodProduced
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

		if startsWithPrefix(targetId, DefensivePropConfig.PropNamePrefix) then
			local enabledAttr = part:GetAttribute(DefensivePropConfig.EnabledAttribute)
			if enabledAttr ~= false then
				local stateAttr = part:GetAttribute(DefensivePropConfig.Attributes.State)
				local propState = if type(stateAttr) == "string" then stateAttr else nil

				if
					isTinyfolk
					and not isLocalPlayerCaptureInteractionActive()
					and not isLocalPlayerCarriedForCounterplay()
					and propState == DefensivePropConfig.Status.Ready
					and distance <= DefensivePropConfig.DropInteractionRangeStuds
				then
					pushCandidate(candidates, {
						action = "defensive_prop_drop",
						targetId = targetId,
						distance = distance,
						priority = getPriority("defensive_prop_drop"),
						mode = "drop",
						payload = {
							mode = "drop",
							propId = targetId,
						},
					})
				end

				if
					isGiant
					and (
						propState == DefensivePropConfig.Status.Dropped
						or propState == DefensivePropConfig.Status.Blocked
					)
					and not isDefensivePropBreakInProgress(part)
					and distance <= DefensivePropConfig.BreakInteractionRangeStuds
				then
					pushCandidate(candidates, {
						action = "defensive_prop_break",
						targetId = targetId,
						distance = distance,
						priority = getPriority("defensive_prop_break"),
						mode = "start_break",
						payload = {
							mode = "start_break",
							propId = targetId,
						},
					})
				end
			end
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
			isGiant
			and startsWithPrefix(targetId, UpgradeBoardConfig.BoardNamePrefix)
			and distance <= UpgradeBoardConfig.InteractionRangeStuds
		then
			pushCandidate(candidates, {
				action = "upgrade_board_hub",
				targetId = targetId,
				distance = distance,
				priority = getPriority("upgrade_board_hub"),
				mode = "open",
				payload = {
					boardId = targetId,
				},
			})
		end

		if
			isGiant
			and resolveUpgradeableWorksiteId(targetId) ~= nil
			and distance <= VillageWorksiteUpgradeConfig.InteractionRangeStuds
		then
			pushCandidate(candidates, {
				action = "worksite_upgrade",
				targetId = targetId,
				distance = distance,
				priority = getPriority("worksite_upgrade"),
				mode = "upgrade",
				payload = targetId,
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
			startsWithPrefix(targetId, StationConfig.GranaryNamePrefix)
			and distance <= StationConfig.ActivationRangeStuds
		then
			pushCandidate(candidates, {
				action = "granary_deliver",
				targetId = targetId,
				distance = distance,
				priority = getPriority("granary_deliver"),
				mode = "deliver",
				payload = targetId,
			})
		end

		if
			isTinyfolk
			and type(TinyfolkLaborUpgradeConfig.TrackByBenchId[targetId]) == "string"
			and distance <= TinyfolkLaborUpgradeConfig.InteractionRangeStuds
		then
			pushCandidate(candidates, {
				action = "tinyfolk_labor_upgrade",
				targetId = targetId,
				distance = distance,
				priority = getPriority("tinyfolk_labor_upgrade"),
				mode = "upgrade",
				payload = targetId,
			})
		end

		if
			startsWithPrefix(targetId, StationConfig.StationNamePrefix)
			or startsWithPrefix(targetId, StationConfig.MiningStationNamePrefix)
			or startsWithPrefix(targetId, StationConfig.FarmNamePrefix)
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

		if startsWithPrefix(targetId, RemoteControlStationConfig.StationNamePrefix) then
			if isGiant and distance <= RemoteControlStationConfig.InteractionRangeStuds then
				pushCandidate(candidates, {
					action = "remote_control_station",
					targetId = targetId,
					distance = distance,
					priority = getPriority("remote_control_station"),
					mode = "enter",
					payload = {
						stationId = targetId,
						mode = RemoteControlStationConfig.Mode.Enter,
					},
				})
			elseif isTinyfolk and distance <= RemoteControlStationConfig.SabotageRangeStuds then
				pushCandidate(candidates, {
					action = "remote_control_station",
					targetId = targetId,
					distance = distance,
					priority = getPriority("remote_control_station"),
					mode = "sabotage",
					payload = {
						stationId = targetId,
						mode = RemoteControlStationConfig.Mode.Sabotage,
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
	if candidate.action == "escape_attempt" then
		escapeAttemptRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "construction_build" then
		constructionBuildRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "upgrade_board_hub" then
		upgradeHubRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "worksite_upgrade" then
		worksiteUpgradeRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "warehouse_deliver" then
		warehouseDeliverRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "granary_deliver" then
		granaryDeliverRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "tinyfolk_labor_upgrade" then
		tinyfolkLaborUpgradeRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "station_pickup_or_assign" then
		if candidate.mode == "assign" then
			stationActivateRemote:FireServer(candidate.targetId)
			return
		end

		if candidate.mode == "assign_replace" then
			stationActivateRemote:FireServer(candidate.targetId)
			return
		end

		stationActivateRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "shrine_assign_worshipper" then
		if candidate.mode == "assign_worshipper" then
			shrineActivateRemote:FireServer(candidate.targetId)
			return
		end

		if candidate.mode == "assign_worshipper_replace" then
			shrineActivateRemote:FireServer(candidate.targetId)
			return
		end

		shrineActivateRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "remote_control_station" then
		remoteControlStationRemote:FireServer(candidate.payload)
		return
	end

	if candidate.action == "defensive_prop_drop" or candidate.action == "defensive_prop_break" then
		defensivePropRemote:FireServer(candidate.payload)
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

local function cancelActiveRemoteControlTask(reason: string)
	if activeRemoteControlStationId == nil then
		return
	end

	local stationId = activeRemoteControlStationId
	activeRemoteControlStationId = nil
	activeRemoteControlTaskToken += 1

	debugLog(string.format("Cancelled remote control task stationId=%s reason=%s", stationId, reason))
end

local function cancelActiveDefensivePropBreakTask(reason: string)
	if activeDefensivePropBreakPropId == nil then
		return
	end

	local propId = activeDefensivePropBreakPropId
	activeDefensivePropBreakPropId = nil
	activeDefensivePropBreakToken += 1

	debugLog(string.format("Cancelled defensive prop break task propId=%s reason=%s", propId, reason))
end

local function beginConstructionTask(candidate: Candidate)
	cancelActiveConstructionTask("new_begin")
	cancelActiveStationTask("construction_begin")
	cancelActiveShrineTask("construction_begin")
	cancelActiveRemoteControlTask("construction_begin")
	cancelActiveDefensivePropBreakTask("construction_begin")

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
	cancelActiveRemoteControlTask("station_begin")
	cancelActiveDefensivePropBreakTask("station_begin")

	activeStationTaskStationId = candidate.targetId
	activeStationTaskToken += 1
	local tokenAtBegin = activeStationTaskToken

	stationActivateRemote:FireServer({
		stationId = candidate.targetId,
		mode = "begin",
		now = os.clock(),
	})

	local laborAction = (LaborActionConfig.ActionBySpecialistRole :: any)[localPlayer:GetAttribute("SpecialistRole") or ""]
	debugLog(
		string.format(
			"Sent station task begin stationId=%s action=%s duration=%.2f",
			candidate.targetId,
			tostring(laborAction),
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
	cancelActiveRemoteControlTask("shrine_begin")
	cancelActiveDefensivePropBreakTask("shrine_begin")

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
			"Sent shrine task begin shrineId=%s action=%s duration=%.2f",
			candidate.targetId,
			LaborActionConfig.Actions.Sermon,
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

local function beginRemoteControlSabotageTask(candidate: Candidate)
	cancelActiveConstructionTask("remote_control_begin")
	cancelActiveStationTask("remote_control_begin")
	cancelActiveShrineTask("remote_control_begin")
	cancelActiveRemoteControlTask("new_begin")
	cancelActiveDefensivePropBreakTask("remote_control_begin")

	activeRemoteControlStationId = candidate.targetId
	activeRemoteControlTaskToken += 1
	local tokenAtBegin = activeRemoteControlTaskToken

	debugLog(
		string.format(
			"Started remote control sabotage task stationId=%s duration=%.2f",
			candidate.targetId,
			RemoteControlStationConfig.SabotageTaskDurationSeconds
		)
	)

	task.delay(RemoteControlStationConfig.SabotageTaskDurationSeconds, function()
		if activeRemoteControlStationId ~= candidate.targetId then
			return
		end
		if activeRemoteControlTaskToken ~= tokenAtBegin then
			return
		end

		remoteControlStationRemote:FireServer(candidate.payload)
		activeRemoteControlStationId = nil
		activeRemoteControlTaskToken += 1
		debugLog(string.format("Sent remote control sabotage stationId=%s", candidate.targetId))
	end)
end

local function isHaulHoldCandidate(candidate: Candidate): boolean
	if candidate.action == "warehouse_deliver" or candidate.action == "granary_deliver" then
		return true
	end

	if candidate.action == "station_pickup_or_assign" and candidate.mode == "pickup" then
		return true
	end

	return false
end

local function setHaulHoldDebugAttributes(candidate: Candidate?, active: boolean)
	localPlayer:SetAttribute(StationConfig.HaulInteractionActiveAttribute, active)
	if not active or candidate == nil then
		localPlayer:SetAttribute(StationConfig.HaulInteractionActionAttribute, nil)
		localPlayer:SetAttribute(StationConfig.HaulInteractionTargetIdAttribute, nil)
		localPlayer:SetAttribute(StationConfig.HaulInteractionModeAttribute, nil)
		return
	end

	localPlayer:SetAttribute(StationConfig.HaulInteractionActionAttribute, candidate.action)
	localPlayer:SetAttribute(StationConfig.HaulInteractionTargetIdAttribute, candidate.targetId)
	localPlayer:SetAttribute(StationConfig.HaulInteractionModeAttribute, candidate.mode)
end

local function haulHoldMatchesCandidate(holdState: any, candidate: Candidate): boolean
	if holdState.action ~= candidate.action then
		return false
	end
	if holdState.targetId ~= candidate.targetId then
		return false
	end
	if holdState.mode ~= candidate.mode then
		return false
	end

	return true
end

local function cancelActiveHaulHold(reason: string)
	if activeHaulHold == nil then
		return
	end

	local holdState = activeHaulHold
	activeHaulHold = nil
	activeHaulHoldToken += 1
	setHaulHoldDebugAttributes(nil, false)
	debugLog(
		string.format(
			"Cancelled haul hold action=%s target=%s mode=%s reason=%s",
			holdState.action,
			holdState.targetId,
			holdState.mode,
			reason
		)
	)
end

local function beginHaulHold(candidate: Candidate)
	cancelActiveConstructionTask("haul_hold_begin")
	cancelActiveStationTask("haul_hold_begin")
	cancelActiveShrineTask("haul_hold_begin")
	cancelActiveRemoteControlTask("haul_hold_begin")
	cancelActiveDefensivePropBreakTask("haul_hold_begin")
	cancelActiveHaulHold("new_begin")

	activeHaulHoldToken += 1
	local tokenAtBegin = activeHaulHoldToken
	activeHaulHold = {
		action = candidate.action,
		targetId = candidate.targetId,
		mode = candidate.mode,
		token = tokenAtBegin,
	}
	setHaulHoldDebugAttributes(candidate, true)

	fireCandidate(candidate)
	debugLog(
		string.format(
			"Started haul hold action=%s target=%s mode=%s interval=%.2f",
			candidate.action,
			candidate.targetId,
			candidate.mode,
			StationConfig.HaulIntervalSeconds
		)
	)

	task.spawn(function()
		while activeHaulHold ~= nil and activeHaulHold.token == tokenAtBegin do
			task.wait(StationConfig.HaulIntervalSeconds)
			if activeHaulHold == nil or activeHaulHold.token ~= tokenAtBegin then
				break
			end

			local root = getHumanoidRootPart(localPlayer.Character)
			if not root then
				cancelActiveHaulHold("humanoid_root_missing")
				break
			end

			local candidates = collectCandidates(root)
			local winner = pickWinningCandidate(candidates)
			if not winner or not haulHoldMatchesCandidate(activeHaulHold, winner) then
				cancelActiveHaulHold("target_lost")
				break
			end

			fireCandidate(winner)
			debugLog(
				string.format(
					"Haul hold repeat action=%s target=%s mode=%s",
					winner.action,
					winner.targetId,
					winner.mode
				)
			)
		end
	end)
end

local function beginDefensivePropBreakTask(candidate: Candidate)
	cancelActiveConstructionTask("defensive_prop_break_begin")
	cancelActiveStationTask("defensive_prop_break_begin")
	cancelActiveShrineTask("defensive_prop_break_begin")
	cancelActiveRemoteControlTask("defensive_prop_break_begin")
	cancelActiveDefensivePropBreakTask("new_begin")

	activeDefensivePropBreakPropId = candidate.targetId
	activeDefensivePropBreakToken += 1
	local tokenAtBegin = activeDefensivePropBreakToken

	defensivePropRemote:FireServer({
		mode = "start_break",
		propId = candidate.targetId,
	})

	debugLog(
		string.format(
			"Sent defensive prop break start propId=%s duration=%.2f",
			candidate.targetId,
			DefensivePropConfig.BreakDurationSeconds
		)
	)

	task.delay(DefensivePropConfig.BreakDurationSeconds, function()
		if activeDefensivePropBreakPropId ~= candidate.targetId then
			return
		end
		if activeDefensivePropBreakToken ~= tokenAtBegin then
			return
		end

		defensivePropRemote:FireServer({
			mode = "complete_break",
			propId = candidate.targetId,
		})
		activeDefensivePropBreakPropId = nil
		activeDefensivePropBreakToken += 1
		debugLog(string.format("Sent defensive prop break complete propId=%s", candidate.targetId))
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

	if resolvedWinner.action == "remote_control_station" and resolvedWinner.mode == "sabotage" then
		beginRemoteControlSabotageTask(resolvedWinner)
		return
	end

	if resolvedWinner.action == "defensive_prop_break" and resolvedWinner.mode == "start_break" then
		beginDefensivePropBreakTask(resolvedWinner)
		return
	end

	if isHaulHoldCandidate(resolvedWinner) then
		beginHaulHold(resolvedWinner)
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
	cancelActiveRemoteControlTask("input_ended")
	cancelActiveDefensivePropBreakTask("input_ended")
	cancelActiveHaulHold("input_ended")
end)

debugLog("Input hook active (F=Context Interaction Resolver)")
