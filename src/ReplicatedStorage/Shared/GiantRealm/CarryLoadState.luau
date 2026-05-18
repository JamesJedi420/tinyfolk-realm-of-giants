--!strict

local CarryLoadState: any = {}

export type Snapshot = {
	slotsUsed: number,
	capacity: number,
	isEncumbered: boolean,
	isAtCapacity: boolean,
	isOverloaded: boolean,
	encumbrance: number,
	speedMultiplier: number,
	carriedTargetUserIds: { number },
}

export type Result = {
	accepted: boolean,
	reason: string,
	snapshot: Snapshot,
}

local DEFAULT_CAPACITY = 1
local DEFAULT_ENCUMBRANCE_PER_TINYFOLK = 0.2
local DEFAULT_MINIMUM_SPEED_MULTIPLIER = 0.65

local ALLOWED_WHILE_CARRYING = {
	debugInspect = true,
	placeCarried = true,
	releaseCarried = true,
}

local function finiteNonNegative(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge or value < 0 then
		return fallback
	end
	return value
end

local function positiveInteger(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end

	local floored = math.floor(value)
	if floored <= 0 then
		return fallback
	end

	return floored
end

local function clamp01(value: number): number
	return math.max(0, math.min(1, value))
end

local function validUserId(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value % 1 == 0
end

local function copyValidTargets(targetUserIds: { number }?): { number }
	local copied: { number } = {}
	if type(targetUserIds) ~= "table" then
		return copied
	end

	local seen: { [number]: boolean } = {}
	for _, targetUserId in targetUserIds :: { any } do
		if validUserId(targetUserId) and seen[targetUserId] ~= true then
			seen[targetUserId] = true
			table.insert(copied, targetUserId)
		end
	end

	return copied
end

local function containsTarget(targetUserIds: { number }, targetUserId: number): boolean
	for _, existingTargetUserId in targetUserIds do
		if existingTargetUserId == targetUserId then
			return true
		end
	end

	return false
end

function CarryLoadState.Snapshot(config: any, targetUserIds: { number }?): Snapshot
	local carriedTargetUserIds = copyValidTargets(targetUserIds)
	local slotsUsed = #carriedTargetUserIds
	local capacity = positiveInteger(if config ~= nil then config.CarryCapacity else nil, DEFAULT_CAPACITY)
	local encumbrancePerTinyfolk = finiteNonNegative(
		if config ~= nil then config.CarryEncumbrancePerTinyfolk else nil,
		DEFAULT_ENCUMBRANCE_PER_TINYFOLK
	)
	local minimumSpeedMultiplier = clamp01(finiteNonNegative(
		if config ~= nil then config.CarryMinimumSpeedMultiplier else nil,
		DEFAULT_MINIMUM_SPEED_MULTIPLIER
	))

	local encumbrance = slotsUsed * encumbrancePerTinyfolk
	local speedMultiplier = 1
	if slotsUsed > 0 then
		speedMultiplier = math.max(1 - encumbrance, minimumSpeedMultiplier)
	end

	local isAtCapacity = slotsUsed >= capacity
	local isEncumbered = slotsUsed > 0

	return {
		slotsUsed = slotsUsed,
		capacity = capacity,
		isEncumbered = isEncumbered,
		isAtCapacity = isAtCapacity,
		isOverloaded = isEncumbered and isAtCapacity,
		encumbrance = encumbrance,
		speedMultiplier = speedMultiplier,
		carriedTargetUserIds = carriedTargetUserIds,
	}
end

function CarryLoadState.CanAcceptTarget(config: any, targetUserIds: { number }?, targetUserId: any): Result
	local snapshot = CarryLoadState.Snapshot(config, targetUserIds)
	if not validUserId(targetUserId) then
		return { accepted = false, reason = "target_user_id_invalid", snapshot = snapshot }
	end

	if containsTarget(snapshot.carriedTargetUserIds, targetUserId :: number) then
		return { accepted = false, reason = "target_already_in_carry_load", snapshot = snapshot }
	end

	if snapshot.isAtCapacity then
		return { accepted = false, reason = "carry_capacity_full", snapshot = snapshot }
	end

	return { accepted = true, reason = "accepted", snapshot = snapshot }
end

function CarryLoadState.CanPerformCarrierInteraction(config: any, targetUserIds: { number }?, interactionName: any): Result
	local snapshot = CarryLoadState.Snapshot(config, targetUserIds)
	if not snapshot.isEncumbered then
		return { accepted = true, reason = "accepted", snapshot = snapshot }
	end

	if type(interactionName) == "string" and ALLOWED_WHILE_CARRYING[interactionName] == true then
		return { accepted = true, reason = "accepted", snapshot = snapshot }
	end

	return { accepted = false, reason = "carrier_encumbered", snapshot = snapshot }
end

return CarryLoadState
