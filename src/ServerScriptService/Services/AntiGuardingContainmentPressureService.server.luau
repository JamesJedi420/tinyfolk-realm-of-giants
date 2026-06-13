--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService: any = nil
do
	local ok, service = pcall(function()
		return game:GetService("RunService")
	end)
	if ok then
		RunService = service
	end
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local CaptureConfig = require(Config:WaitForChild("CaptureConfig"))
local CaptivityDurationState = require(GiantRealm:WaitForChild("CaptivityDurationState"))
local AntiGuardingContainmentPressureState = require(GiantRealm:WaitForChild("AntiGuardingContainmentPressureState"))

local globalEnv: any = getfenv()
local PRESSURE_SCAN_INTERVAL_SECONDS = 0.5

local pressureByTargetUserId: { [number]: any? } = {}
local lastPressureScanAt = 0

local function now(): number
	return os.clock()
end

local function getPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player :: any
		end
	end
	return nil
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

local function resolveDistance(a: any, b: any): number?
	if a == nil or b == nil then
		return nil
	end
	if
		type(a) == "table"
		and type(b) == "table"
		and type(a.x) == "number"
		and type(a.y) == "number"
		and type(a.z) == "number"
		and type(b.x) == "number"
		and type(b.y) == "number"
		and type(b.z) == "number"
	then
		local dx = a.x - b.x
		local dy = a.y - b.y
		local dz = a.z - b.z
		return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
	end
	local ok, delta = pcall(function()
		return a - b
	end)
	if not ok then
		return nil
	end
	if type(delta) == "table" and type((delta :: any).Magnitude) == "number" then
		return (delta :: any).Magnitude
	end
	if type(delta) == "table" and type((delta :: any).Magnitude) == "function" then
		return (delta :: any):Magnitude()
	end
	return nil
end

local function getCaptureServiceQueryApi(): any?
	local queryApi = globalEnv._CaptureService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._CaptureService_QueryAPI) == "table" then
		return (_G :: any)._CaptureService_QueryAPI
	end
	return nil
end

local function getCaptivityEscapeServiceQueryApi(): any?
	local queryApi = globalEnv._CaptivityEscapeService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._CaptivityEscapeService_QueryAPI) == "table" then
		return (_G :: any)._CaptivityEscapeService_QueryAPI
	end
	return nil
end

local function clearPressureAttributes(player: Player?)
	if player == nil then
		return
	end
	local attrs = CaptureConfig.StateAttributes
	player:SetAttribute(attrs.AntiGuardingPressure, nil)
	player:SetAttribute(attrs.AntiGuardingPressurePhase, nil)
	player:SetAttribute(attrs.AntiGuardingCounterplayReady, false)
end

local function applyPressureAttributes(target: Player, snapshot: any)
	local attrs = CaptureConfig.StateAttributes
	target:SetAttribute(attrs.AntiGuardingPressure, snapshot.pressure)
	target:SetAttribute(attrs.AntiGuardingPressurePhase, snapshot.phase)
	target:SetAttribute(attrs.AntiGuardingCounterplayReady, snapshot.counterplayReady == true)
end

local function clearPressureForTarget(targetUserId: number)
	pressureByTargetUserId[targetUserId] = nil
	clearPressureAttributes(getPlayerByUserId(targetUserId))
end

local function setCaptureLastReason(player: Player?, reason: string)
	if player == nil then
		return
	end
	player:SetAttribute(CaptureConfig.StateAttributes.CaptureLastReason, reason)
end

local function applyCounterplay(targetUserId: number, at: number): any
	local outcome = AntiGuardingContainmentPressureState.GetCounterplayOutcome(CaptureConfig)
	if outcome ~= AntiGuardingContainmentPressureState.CounterplayOutcomes.escape_progress_release then
		return { accepted = false, reason = "counterplay_outcome_unsupported" }
	end

	local escapeApi = getCaptivityEscapeServiceQueryApi()
	if escapeApi == nil or type(escapeApi.ApplyAntiGuardingCounterplay) ~= "function" then
		return { accepted = false, reason = "captivity_escape_query_unavailable" }
	end

	local ok, result = pcall(escapeApi.ApplyAntiGuardingCounterplay, targetUserId, at)
	if not ok or type(result) ~= "table" then
		return { accepted = false, reason = "counterplay_apply_fault" }
	end

	local state = pressureByTargetUserId[targetUserId]
	if state ~= nil then
		pressureByTargetUserId[targetUserId] =
			AntiGuardingContainmentPressureState.ResolveCounterplayConsumed(state, at)
	end

	local target = getPlayerByUserId(targetUserId)
	if target ~= nil then
		local snapshot =
			AntiGuardingContainmentPressureState.Snapshot(pressureByTargetUserId[targetUserId], at, CaptureConfig)
		applyPressureAttributes(target, snapshot)
	end

	local record = nil
	local captureApi = getCaptureServiceQueryApi()
	if captureApi ~= nil and type(captureApi.GetTargetCapture) == "function" then
		record = captureApi.GetTargetCapture(targetUserId, at)
	end
	if type(record) == "table" then
		setCaptureLastReason(getPlayerByUserId(record.custodianUserId), "anti_guarding_counterplay_release")
		setCaptureLastReason(target, "anti_guarding_counterplay_release")
	end

	return result
end

local function ensurePressureState(record: any, at: number): any?
	if type(record) ~= "table" or type(record.containedAt) ~= "number" then
		return nil
	end
	local existing = pressureByTargetUserId[record.targetUserId]
	if existing ~= nil then
		return existing
	end
	local created = AntiGuardingContainmentPressureState.NewState(record.containedAt, at)
	pressureByTargetUserId[record.targetUserId] = created
	return created
end

local function tickContainedRecord(record: any, at: number): any
	if type(record) ~= "table" or record.containmentPhase ~= CaptivityDurationState.Phases.contained then
		return { accepted = false, reason = "not_contained" }
	end
	if type(record.containedAt) ~= "number" then
		return { accepted = false, reason = "contained_at_missing" }
	end

	local custodian = getPlayerByUserId(record.custodianUserId)
	local target = getPlayerByUserId(record.targetUserId)
	if custodian == nil or target == nil then
		return { accepted = false, reason = "participant_missing" }
	end

	local custodianRoot = getHumanoidRootPart(custodian)
	local targetRoot = getHumanoidRootPart(target)
	if custodianRoot == nil or targetRoot == nil then
		return { accepted = false, reason = "missing_character_root" }
	end

	local distance = resolveDistance((custodianRoot :: any).Position, (targetRoot :: any).Position)
	local custodianInProximity = AntiGuardingContainmentPressureState.IsCustodianInProximity(distance, CaptureConfig)
	local state = ensurePressureState(record, at)
	if state == nil then
		return { accepted = false, reason = "pressure_state_missing" }
	end

	local ticked = AntiGuardingContainmentPressureState.ResolveTick(state, {
		now = at,
		containedAt = record.containedAt,
		custodianInProximity = custodianInProximity,
	}, CaptureConfig)
	pressureByTargetUserId[record.targetUserId] = ticked.state
	applyPressureAttributes(target, ticked.snapshot)

	if ticked.counterplayReady == true then
		return applyCounterplay(record.targetUserId, at)
	end

	return {
		accepted = true,
		reason = ticked.snapshot.lastReason or "pressure_updated",
		snapshot = ticked.snapshot,
		distanceStuds = distance,
		custodianInProximity = custodianInProximity,
	}
end

local function refreshPressureForActiveCaptures(at: number)
	local captureApi = getCaptureServiceQueryApi()
	if captureApi == nil or type(captureApi.GetAllCaptures) ~= "function" then
		return
	end

	local ok, captures = pcall(captureApi.GetAllCaptures, at)
	if not ok or type(captures) ~= "table" then
		return
	end

	local activeContainedTargets: { [number]: boolean } = {}
	for _, record in ipairs(captures) do
		if type(record) == "table" and type(record.targetUserId) == "number" then
			if record.containmentPhase == CaptivityDurationState.Phases.contained then
				activeContainedTargets[record.targetUserId] = true
				tickContainedRecord(record, at)
			end
		end
	end

	for targetUserId, _ in pairs(pressureByTargetUserId) do
		if activeContainedTargets[targetUserId] ~= true then
			clearPressureForTarget(targetUserId)
		end
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	clearPressureForTarget(player.UserId)
end)

if
	type(RunService) == "table"
	and type(RunService.Heartbeat) == "table"
	and type(RunService.Heartbeat.Connect) == "function"
then
	RunService.Heartbeat:Connect(function()
		local at = now()
		if at - lastPressureScanAt < PRESSURE_SCAN_INTERVAL_SECONDS then
			return
		end
		lastPressureScanAt = at
		refreshPressureForActiveCaptures(at)
	end)
end

_G._AntiGuardingContainmentPressureService_QueryAPI = {
	TickContainedTarget = function(targetUserId: number, at: number?): any
		local resolvedAt = if type(at) == "number" then at else now()
		local captureApi = getCaptureServiceQueryApi()
		if captureApi == nil or type(captureApi.GetTargetCapture) ~= "function" then
			return { accepted = false, reason = "capture_query_unavailable" }
		end
		local record = captureApi.GetTargetCapture(targetUserId, resolvedAt)
		if record == nil then
			clearPressureForTarget(targetUserId)
			return { accepted = false, reason = "capture_missing" }
		end
		return tickContainedRecord(record, resolvedAt)
	end,
	GetPressureSnapshot = function(targetUserId: number, at: number?): any?
		local resolvedAt = if type(at) == "number" then at else now()
		local state = pressureByTargetUserId[targetUserId]
		if state == nil then
			return nil
		end
		return AntiGuardingContainmentPressureState.Snapshot(state, resolvedAt, CaptureConfig)
	end,
	ResetForTests = function()
		pressureByTargetUserId = {}
		lastPressureScanAt = 0
		for _, player in Players:GetPlayers() do
			clearPressureAttributes(player)
		end
	end,
}
