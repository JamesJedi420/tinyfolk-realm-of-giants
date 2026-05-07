--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local UpgradeBoardShared = Shared:WaitForChild("UpgradeBoard")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local UpgradeBoardConfig = require(Config:WaitForChild("UpgradeBoardConfig"))
local UpgradeProgressionLogic = require(UpgradeBoardShared:WaitForChild("UpgradeProgressionLogic"))
local GiantEssenceSession = require(script.Parent:WaitForChild("GiantEssenceSession"))

local REMOTES_FOLDER_NAME = "Remotes"
local SELECT_REMOTE_NAME = "UpgradeBoardSelectRequest"
local DEBUG_REQUEST_REMOTE_NAME = "UpgradeBoardDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "UpgradeBoardDebugStateResponse"
local DEBUG_ESSENCE_DRAIN_REMOTE_NAME = "UpgradeBoardDebugEssenceDrain"
local SELECT_RESULT_REMOTE_NAME = "UpgradeBoardSelectResult"
local DEBUG_ESSENCE_DRAIN_AMOUNT = 25

local BOARD_ENABLED_ATTRIBUTE = "IsEnabled"
local BOARD_SELECTION_COUNT_ATTRIBUTE = "SelectionCount"
local UPGRADE_SUMMARY_ATTRIBUTE = "GiantUpgradesCsv"
local UPGRADE_ATTRIBUTE_PREFIX = "GiantUpgrade_"
local UPGRADE_STEP_COMPLETED_ATTRIBUTE = "GiantUpgradeStepCompleted"
local UPGRADE_STEP_TOTAL_ATTRIBUTE = "GiantUpgradeStepTotal"
local UPGRADE_NEXT_ID_ATTRIBUTE = "GiantUpgradeNextId"
local UPGRADE_PROGRESSION_STATUS_ATTRIBUTE = "GiantUpgradeProgressionStatus"
local EFFECT_MAX_HEALTH_ATTRIBUTE = "GiantEffect_MaxHealth"
local EFFECT_WALK_SPEED_ATTRIBUTE = "GiantEffect_WalkSpeed"
local EFFECT_MAX_HEALTH_BONUS_ATTRIBUTE = "GiantEffect_MaxHealthBonus"
local EFFECT_WALK_SPEED_BONUS_ATTRIBUTE = "GiantEffect_WalkSpeedBonus"
local EFFECT_POWER_BUDGET_ATTRIBUTE = "GiantEffect_PowerBudget"
local EFFECT_MOVEMENT_CONTROL_ATTRIBUTE = "GiantEffect_MovementControl"
local EFFECT_POWER_BUDGET_BONUS_ATTRIBUTE = "GiantEffect_PowerBudgetBonus"
local EFFECT_MOVEMENT_CONTROL_BONUS_ATTRIBUTE = "GiantEffect_MovementControlBonus"
local ESSENCE_TOTAL_ATTRIBUTE = "GiantEssenceTotal"
local ESSENCE_GENERATED_TOTAL_ATTRIBUTE = "GiantEssenceGeneratedTotal"
local ESSENCE_SPENT_TOTAL_ATTRIBUTE = "GiantEssenceSpentTotal"
local ESSENCE_LAST_SPENT_REASON_ATTRIBUTE = "GiantEssenceLastSpentReason"
local ESSENCE_LAST_SPENT_AMOUNT_ATTRIBUTE = "GiantEssenceLastSpentAmount"

local BOARDS_FOLDER_PATH = {"Map", "Stations"}

type UpgradeSelectionPayload = {
	boardId: string,
	upgradeId: string,
}

type SelectResultPayload = {
	accepted: boolean,
	upgradeId: string,
	reason: string?,
	newStepCompleted: number?,
}

type ProgressionState = {
	completedSteps: number,
	totalSteps: number,
	nextUpgradeId: string?,
	status: string,
}

type GiantResolvedEffects = {
	maxHealth: number,
	walkSpeed: number,
	maxHealthBonus: number,
	walkSpeedBonus: number,
	powerBudget: number,
	movementControl: number,
	powerBudgetBonus: number,
	movementControlBonus: number,
}

type HumanoidState = {
	maxHealth: number,
	walkSpeed: number,
}

local boardPartById: {[string]: BasePart} = {}
local giantUpgradeStateByUserId: {[number]: {[string]: boolean}} = {}
local giantResolvedEffectsByUserId: {[number]: GiantResolvedEffects} = {}
local lastRequestAtByUserId: {[number]: number} = {}

local progressionKernel = UpgradeProgressionLogic.BuildKernel(UpgradeBoardConfig.UpgradeOptions, UpgradeBoardConfig.EffectByUpgradeId)
local orderedUpgradeIds = progressionKernel.orderedUpgradeIds
local validUpgradeIdSet = progressionKernel.validUpgradeIdSet
local upgradeCostById = progressionKernel.upgradeCostById

local function debugLog(message: string)
	print(string.format("[UpgradeBoardService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[UpgradeBoardService] %s", message))
end

for _, warningMessage in progressionKernel.warnings do
	debugWarn(warningMessage)
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

	return (os.clock() - last) < UpgradeBoardConfig.RequestCooldownSeconds
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

local function isGiant(player: Player): boolean
	return player:GetAttribute("Role") == RoleConfig.Roles.Giant
end

local function shouldTrackBoardPart(part: BasePart): boolean
	return string.match(part.Name, "^" .. UpgradeBoardConfig.BoardNamePrefix) ~= nil
end

local function findBoardsRoot(): Instance?
	local current: Instance = Workspace
	for _, childName in BOARDS_FOLDER_PATH do
		local nextNode = current:FindFirstChild(childName)
		if not nextNode then
			return nil
		end
		current = nextNode
	end

	return current
end

local function registerBoardPart(part: BasePart)
	local boardId = part.Name
	if boardPartById[boardId] then
		debugWarn(string.format("Duplicate upgrade board id ignored: %s", boardId))
		return
	end

	boardPartById[boardId] = part
	part:SetAttribute(BOARD_ENABLED_ATTRIBUTE, true)
	part:SetAttribute(BOARD_SELECTION_COUNT_ATTRIBUTE, 0)
	debugLog(string.format("Registered upgrade board id=%s", boardId))
end

local function registerBoardsFromWorkspace()
	local boardsRoot = findBoardsRoot()
	if not boardsRoot then
		debugWarn("No upgrade board root found at Workspace.Map.Stations")
		return
	end

	for _, descendant in boardsRoot:GetDescendants() do
		if descendant:IsA("BasePart") and shouldTrackBoardPart(descendant) then
			registerBoardPart(descendant)
		end
	end

	if next(boardPartById) == nil then
		debugWarn("No upgrade boards registered under Workspace.Map.Stations")
	end
end

local function getOrCreateGiantUpgradeState(userId: number): {[string]: boolean}
	local state = giantUpgradeStateByUserId[userId]
	if state then
		return state
	end

	local createdState: {[string]: boolean} = {}
	giantUpgradeStateByUserId[userId] = createdState
	return createdState
end

local function rebuildUpgradeCsv(state: {[string]: boolean}): string
	return UpgradeProgressionLogic.RebuildUpgradeCsv(progressionKernel, state)
end

local function resolveProgressionState(state: {[string]: boolean}): ProgressionState
	return UpgradeProgressionLogic.ResolveProgressionState(progressionKernel, state)
end

local function resolveEffectValues(state: {[string]: boolean}): GiantResolvedEffects
	local maxHealthBonus = 0
	local walkSpeedBonus = 0
	local powerBudgetBonus = 0
	local movementControlBonus = 0

	for upgradeId, enabled in state do
		if enabled then
			local effect = UpgradeBoardConfig.EffectByUpgradeId[upgradeId]
			if effect then
				maxHealthBonus += effect.maxHealthBonus
				walkSpeedBonus += effect.walkSpeedBonus
				powerBudgetBonus += effect.powerBudgetBonus
				movementControlBonus += effect.movementControlBonus
			end
		end
	end

	return {
		maxHealth = UpgradeBoardConfig.BaseHumanoidMaxHealth + maxHealthBonus,
		walkSpeed = UpgradeBoardConfig.BaseHumanoidWalkSpeed + walkSpeedBonus,
		maxHealthBonus = maxHealthBonus,
		walkSpeedBonus = walkSpeedBonus,
		powerBudget = UpgradeBoardConfig.BasePowerBudget + powerBudgetBonus,
		movementControl = UpgradeBoardConfig.BaseMovementControl + movementControlBonus,
		powerBudgetBonus = powerBudgetBonus,
		movementControlBonus = movementControlBonus,
	}
end

local function applyUpgradeAttributes(player: Player, state: {[string]: boolean})
	for upgradeId in validUpgradeIdSet do
		player:SetAttribute(UPGRADE_ATTRIBUTE_PREFIX .. upgradeId, state[upgradeId] == true)
	end

	player:SetAttribute(UPGRADE_SUMMARY_ATTRIBUTE, rebuildUpgradeCsv(state))
end

local function applyProgressionAttributes(player: Player, progression: ProgressionState)
	player:SetAttribute(UPGRADE_STEP_COMPLETED_ATTRIBUTE, progression.completedSteps)
	player:SetAttribute(UPGRADE_STEP_TOTAL_ATTRIBUTE, progression.totalSteps)
	player:SetAttribute(UPGRADE_PROGRESSION_STATUS_ATTRIBUTE, progression.status)
	if progression.nextUpgradeId then
		player:SetAttribute(UPGRADE_NEXT_ID_ATTRIBUTE, progression.nextUpgradeId)
	else
		player:SetAttribute(UPGRADE_NEXT_ID_ATTRIBUTE, nil)
	end
end

local function applyUpgradeEffectAttributes(player: Player, effects: GiantResolvedEffects)
	player:SetAttribute(EFFECT_MAX_HEALTH_ATTRIBUTE, effects.maxHealth)
	player:SetAttribute(EFFECT_WALK_SPEED_ATTRIBUTE, effects.walkSpeed)
	player:SetAttribute(EFFECT_MAX_HEALTH_BONUS_ATTRIBUTE, effects.maxHealthBonus)
	player:SetAttribute(EFFECT_WALK_SPEED_BONUS_ATTRIBUTE, effects.walkSpeedBonus)
	player:SetAttribute(EFFECT_POWER_BUDGET_ATTRIBUTE, effects.powerBudget)
	player:SetAttribute(EFFECT_MOVEMENT_CONTROL_ATTRIBUTE, effects.movementControl)
	player:SetAttribute(EFFECT_POWER_BUDGET_BONUS_ATTRIBUTE, effects.powerBudgetBonus)
	player:SetAttribute(EFFECT_MOVEMENT_CONTROL_BONUS_ATTRIBUTE, effects.movementControlBonus)
end

local function applyEssenceDebugAttributes(player: Player, snapshot)
	player:SetAttribute(ESSENCE_TOTAL_ATTRIBUTE, snapshot.total)
	player:SetAttribute(ESSENCE_GENERATED_TOTAL_ATTRIBUTE, snapshot.generatedTotal)
	player:SetAttribute(ESSENCE_SPENT_TOTAL_ATTRIBUTE, snapshot.spentTotal)
	player:SetAttribute(ESSENCE_LAST_SPENT_REASON_ATTRIBUTE, snapshot.lastSpentReason)
	player:SetAttribute(ESSENCE_LAST_SPENT_AMOUNT_ATTRIBUTE, snapshot.lastSpentAmount)
end

local function resetUpgradeState(player: Player, reason: string)
	giantUpgradeStateByUserId[player.UserId] = {}
	giantResolvedEffectsByUserId[player.UserId] = nil

	local emptyState: {[string]: boolean} = {}
	applyUpgradeAttributes(player, emptyState)
	applyProgressionAttributes(player, resolveProgressionState(emptyState))

	local baseEffects = resolveEffectValues(emptyState)
	applyUpgradeEffectAttributes(player, baseEffects)

	debugLog(string.format("Reset upgrade state userId=%d reason=%s", player.UserId, reason))
end

local function getRoleBaselineState(player: Player): HumanoidState
	local roleName = player:GetAttribute("Role")
	if type(roleName) ~= "string" then
		roleName = RoleConfig.DefaultRole
	end

	local baselineByRole = RoleConfig.HumanoidBaseByRole
	local roleBaseline = baselineByRole[roleName]
	if roleBaseline and type(roleBaseline.maxHealth) == "number" and type(roleBaseline.walkSpeed) == "number" then
		return {
			maxHealth = roleBaseline.maxHealth,
			walkSpeed = roleBaseline.walkSpeed,
		}
	end

	return {
		maxHealth = UpgradeBoardConfig.BaseHumanoidMaxHealth,
		walkSpeed = UpgradeBoardConfig.BaseHumanoidWalkSpeed,
	}
end

local function applyResolvedHumanoidState(player: Player, state: HumanoidState): boolean
	local humanoid = getHumanoid(player)
	if not humanoid then
		return false
	end

	local currentMaxHealth = humanoid.MaxHealth
	local healthRatio = 1
	if currentMaxHealth > 0 then
		healthRatio = math.clamp(humanoid.Health / currentMaxHealth, 0, 1)
	end

	humanoid.MaxHealth = state.maxHealth
	humanoid.WalkSpeed = state.walkSpeed
	humanoid.Health = math.clamp(state.maxHealth * healthRatio, 0, state.maxHealth)

	return true
end

local function applyGiantUpgradeEffects(player: Player, reason: string)
	local state = getOrCreateGiantUpgradeState(player.UserId)
	local effects = resolveEffectValues(state)
	giantResolvedEffectsByUserId[player.UserId] = effects
	applyUpgradeEffectAttributes(player, effects)

	local targetHumanoidState: HumanoidState
	if isGiant(player) then
		targetHumanoidState = {
			maxHealth = effects.maxHealth,
			walkSpeed = effects.walkSpeed,
		}
	else
		targetHumanoidState = getRoleBaselineState(player)
	end

	local applied = applyResolvedHumanoidState(player, targetHumanoidState)
	if not applied then
		debugLog(string.format("Deferred role state apply userId=%d reason=%s detail=missing_humanoid", player.UserId, reason))
		return
	end

	if not isGiant(player) then
		debugLog(string.format(
			"Applied non-giant baseline userId=%d reason=%s maxHealth=%.1f walkSpeed=%.1f",
			player.UserId,
			reason,
			targetHumanoidState.maxHealth,
			targetHumanoidState.walkSpeed
		))
		return
	end

	debugLog(string.format(
		"Applied Giant effects userId=%d reason=%s maxHealth=%.1f walkSpeed=%.1f powerBudget=%.1f movementControl=%.2f maxHealthBonus=%.1f walkSpeedBonus=%.1f",
		player.UserId,
		reason,
		effects.maxHealth,
		effects.walkSpeed,
		effects.powerBudget,
		effects.movementControl,
		effects.maxHealthBonus,
		effects.walkSpeedBonus
	))
end

local function rejectSelect(player: Player, reason: string)
	debugWarn(string.format("Rejected UpgradeBoardSelectRequest userId=%d reason=%s", player.UserId, reason))
end

local function rejectDebug(player: Player, reason: string)
	debugWarn(string.format("Rejected UpgradeBoardDebugStateRequest userId=%d reason=%s", player.UserId, reason))
end

local remotesFolder = ensureRemotesFolder()
local selectRemote = ensureRemoteEvent(remotesFolder, SELECT_REMOTE_NAME)
local debugRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
local debugResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)
local debugEssenceDrainRemote = ensureRemoteEvent(remotesFolder, DEBUG_ESSENCE_DRAIN_REMOTE_NAME)
local selectResultRemote = ensureRemoteEvent(remotesFolder, SELECT_RESULT_REMOTE_NAME)

registerBoardsFromWorkspace()

selectRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if isCoolingDown(player.UserId) then
		rejectSelect(player, "request_cooldown")
		selectResultRemote:FireClient(player, { accepted = false, upgradeId = "", reason = "request_cooldown" } :: SelectResultPayload)
		return
	end

	markRequest(player.UserId)

	if type(payload) ~= "table" then
		rejectSelect(player, "malformed_payload")
		selectResultRemote:FireClient(player, { accepted = false, upgradeId = "", reason = "malformed_payload" } :: SelectResultPayload)
		return
	end

	local parsedPayload = payload :: UpgradeSelectionPayload
	local boardId = parsedPayload.boardId
	local upgradeId = parsedPayload.upgradeId

	if type(boardId) ~= "string" or type(upgradeId) ~= "string" then
		rejectSelect(player, "malformed_payload")
		selectResultRemote:FireClient(player, { accepted = false, upgradeId = "", reason = "malformed_payload" } :: SelectResultPayload)
		return
	end

	local boardPart = boardPartById[boardId]
	if not boardPart then
		rejectSelect(player, "board_not_found")
		selectResultRemote:FireClient(player, { accepted = false, upgradeId = upgradeId, reason = "board_not_found" } :: SelectResultPayload)
		return
	end

	if not isGiant(player) then
		rejectSelect(player, "requester_not_giant")
		selectResultRemote:FireClient(player, { accepted = false, upgradeId = upgradeId, reason = "requester_not_giant" } :: SelectResultPayload)
		return
	end

	if not isPlayerAlive(player) then
		rejectSelect(player, "player_not_alive")
		selectResultRemote:FireClient(player, { accepted = false, upgradeId = upgradeId, reason = "player_not_alive" } :: SelectResultPayload)
		return
	end

	local root = getHumanoidRootPart(player)
	if not root then
		rejectSelect(player, "humanoid_root_missing")
		selectResultRemote:FireClient(player, { accepted = false, upgradeId = upgradeId, reason = "humanoid_root_missing" } :: SelectResultPayload)
		return
	end

	local boardEnabled = boardPart:GetAttribute(BOARD_ENABLED_ATTRIBUTE)
	if boardEnabled == false then
		rejectSelect(player, "board_disabled")
		selectResultRemote:FireClient(player, { accepted = false, upgradeId = upgradeId, reason = "board_disabled" } :: SelectResultPayload)
		return
	end

	local distance = (boardPart.Position - root.Position).Magnitude
	if distance > UpgradeBoardConfig.InteractionRangeStuds then
		rejectSelect(player, string.format("out_of_range distance=%.2f max=%.2f", distance, UpgradeBoardConfig.InteractionRangeStuds))
		selectResultRemote:FireClient(player, { accepted = false, upgradeId = upgradeId, reason = "out_of_range" } :: SelectResultPayload)
		return
	end

	local state = getOrCreateGiantUpgradeState(player.UserId)
	local previewCost = upgradeCostById[upgradeId] or 0
	local hasSufficientEssence = true
	if previewCost > 0 then
		hasSufficientEssence = GiantEssenceSession.CanSpend(player.UserId, previewCost)
	end

	local selectionAllowed, selectionReason, _, upgradeCost = UpgradeProgressionLogic.ValidateSelection(
		progressionKernel,
		state,
		upgradeId,
		hasSufficientEssence
	)

	if not selectionAllowed then
		if selectionReason == "insufficient_essence" then
			local insufficientSnapshot = GiantEssenceSession.GetSnapshot(player.UserId)
			applyEssenceDebugAttributes(player, insufficientSnapshot)
			rejectSelect(player, string.format("insufficient_essence required=%d total=%.0f upgradeId=%s", upgradeCost, insufficientSnapshot.total, upgradeId))
			selectResultRemote:FireClient(player, { accepted = false, upgradeId = upgradeId, reason = "insufficient_essence" } :: SelectResultPayload)
			return
		end

		local rejectionReason = selectionReason or "selection_rejected"
		rejectSelect(player, rejectionReason)
		selectResultRemote:FireClient(player, { accepted = false, upgradeId = upgradeId, reason = rejectionReason } :: SelectResultPayload)
		return
	end

	if upgradeCost > 0 then
		local spent, spendSnapshot = GiantEssenceSession.Spend(player.UserId, "UpgradeBoard:" .. upgradeId, upgradeCost)
		applyEssenceDebugAttributes(player, spendSnapshot)
		if not spent then
			rejectSelect(player, string.format("insufficient_essence required=%d total=%.0f upgradeId=%s", upgradeCost, spendSnapshot.total, upgradeId))
			selectResultRemote:FireClient(player, { accepted = false, upgradeId = upgradeId, reason = "insufficient_essence" } :: SelectResultPayload)
			return
		end

		debugLog(string.format("Spent Giant Essence userId=%d upgradeId=%s cost=%d total=%.0f generatedTotal=%.0f spentTotal=%.0f", player.UserId, upgradeId, upgradeCost, spendSnapshot.total, spendSnapshot.generatedTotal, spendSnapshot.spentTotal))
	end

	state = UpgradeProgressionLogic.ApplySelection(state, upgradeId)
	giantUpgradeStateByUserId[player.UserId] = state
	applyUpgradeAttributes(player, state)
	local newProgression = resolveProgressionState(state)
	applyProgressionAttributes(player, newProgression)
	applyGiantUpgradeEffects(player, "selection")

	local currentSelectionCount = boardPart:GetAttribute(BOARD_SELECTION_COUNT_ATTRIBUTE)
	if type(currentSelectionCount) ~= "number" then
		currentSelectionCount = 0
	end
	boardPart:SetAttribute(BOARD_SELECTION_COUNT_ATTRIBUTE, currentSelectionCount + 1)

	selectResultRemote:FireClient(player, {
		accepted = true,
		upgradeId = upgradeId,
		newStepCompleted = newProgression.completedSteps,
	} :: SelectResultPayload)
	debugLog(string.format("Accepted UpgradeBoardSelectRequest userId=%d boardId=%s upgradeId=%s", player.UserId, boardId, upgradeId))
end)

debugRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	debugLog(string.format("Received UpgradeBoardDebugStateRequest userId=%d payloadType=%s", player.UserId, typeof(payload)))

	if payload ~= nil and type(payload) ~= "string" then
		rejectDebug(player, "malformed_payload")
		return
	end

	local requestedBoardId = payload :: string?
	local state = getOrCreateGiantUpgradeState(player.UserId)
	local selectedCsv = rebuildUpgradeCsv(state)
	local progression = resolveProgressionState(state)
	local effects = giantResolvedEffectsByUserId[player.UserId] or resolveEffectValues(state)
	local essenceSnapshot = GiantEssenceSession.GetSnapshot(player.UserId)
	applyEssenceDebugAttributes(player, essenceSnapshot)
	applyProgressionAttributes(player, progression)

	if requestedBoardId then
		local boardPart = boardPartById[requestedBoardId]
		if not boardPart then
			rejectDebug(player, "board_not_found")
			return
		end

		debugResponseRemote:FireClient(player, {
			boardId = requestedBoardId,
			isEnabled = boardPart:GetAttribute(BOARD_ENABLED_ATTRIBUTE),
			selectionCount = boardPart:GetAttribute(BOARD_SELECTION_COUNT_ATTRIBUTE),
			selectedUpgradesCsv = selectedCsv,
			upgradeStepCompleted = progression.completedSteps,
			upgradeStepTotal = progression.totalSteps,
			nextUpgradeId = progression.nextUpgradeId,
			upgradeProgressionStatus = progression.status,
			resolvedMaxHealth = effects.maxHealth,
			resolvedWalkSpeed = effects.walkSpeed,
			resolvedPowerBudget = effects.powerBudget,
			resolvedMovementControl = effects.movementControl,
			giantEssenceTotal = essenceSnapshot.total,
			giantEssenceGeneratedTotal = essenceSnapshot.generatedTotal,
			giantEssenceSpentTotal = essenceSnapshot.spentTotal,
			giantEssenceLastSpentReason = essenceSnapshot.lastSpentReason,
			giantEssenceLastSpentAmount = essenceSnapshot.lastSpentAmount,
		})
		debugLog(string.format("Sent upgrade debug state userId=%d boardId=%s", player.UserId, requestedBoardId))
		return
	end

	local snapshot = {}
	for boardId, boardPart in boardPartById do
		table.insert(snapshot, {
			boardId = boardId,
			isEnabled = boardPart:GetAttribute(BOARD_ENABLED_ATTRIBUTE),
			selectionCount = boardPart:GetAttribute(BOARD_SELECTION_COUNT_ATTRIBUTE),
		})
	end

	debugResponseRemote:FireClient(player, {
		boards = snapshot,
		selectedUpgradesCsv = selectedCsv,
		upgradeStepCompleted = progression.completedSteps,
		upgradeStepTotal = progression.totalSteps,
		nextUpgradeId = progression.nextUpgradeId,
		upgradeProgressionStatus = progression.status,
		resolvedMaxHealth = effects.maxHealth,
		resolvedWalkSpeed = effects.walkSpeed,
		resolvedPowerBudget = effects.powerBudget,
		resolvedMovementControl = effects.movementControl,
		giantEssenceTotal = essenceSnapshot.total,
		giantEssenceGeneratedTotal = essenceSnapshot.generatedTotal,
		giantEssenceSpentTotal = essenceSnapshot.spentTotal,
		giantEssenceLastSpentReason = essenceSnapshot.lastSpentReason,
		giantEssenceLastSpentAmount = essenceSnapshot.lastSpentAmount,
	})
	debugLog(string.format("Sent upgrade debug snapshot userId=%d boardCount=%d", player.UserId, #snapshot))
end)

debugEssenceDrainRemote.OnServerEvent:Connect(function(player: Player)
	local _, drainSnapshot = GiantEssenceSession.Spend(player.UserId, "DebugDrain", DEBUG_ESSENCE_DRAIN_AMOUNT)
	applyEssenceDebugAttributes(player, drainSnapshot)
	debugLog(string.format("DebugEssenceDrain userId=%d drained=%d total=%.0f", player.UserId, DEBUG_ESSENCE_DRAIN_AMOUNT, drainSnapshot.total))
end)

local function setupPlayer(player: Player)
	local state = getOrCreateGiantUpgradeState(player.UserId)
	applyUpgradeAttributes(player, state)
	applyProgressionAttributes(player, resolveProgressionState(state))
	applyEssenceDebugAttributes(player, GiantEssenceSession.GetSnapshot(player.UserId))
	applyGiantUpgradeEffects(player, "player_setup")

	player.CharacterAdded:Connect(function()
		applyGiantUpgradeEffects(player, "character_added")
	end)

	player:GetAttributeChangedSignal("Role"):Connect(function()
		resetUpgradeState(player, "role_changed")
		GiantEssenceSession.ResetSession(player.UserId, "role_changed")
		applyEssenceDebugAttributes(player, GiantEssenceSession.GetSnapshot(player.UserId))
		applyGiantUpgradeEffects(player, "role_changed")
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
	giantUpgradeStateByUserId[player.UserId] = nil
	giantResolvedEffectsByUserId[player.UserId] = nil
	GiantEssenceSession.RemoveSession(player.UserId)
end)

debugLog("UpgradeBoardService initialized")