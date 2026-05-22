--!strict

local GiantEssenceSession = {}

local TEST_STARTING_ESSENCE = 200

local function debugLog(message: string)
	print(string.format("[GiantEssenceSession] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[GiantEssenceSession] %s", message))
end

type GiantEssenceSnapshot = {
	total: number,
	generatedTotal: number,
	spentTotal: number,
	lastGeneratedSource: string?,
	lastGeneratedAmount: number,
	lastSpentReason: string?,
	lastSpentAmount: number,
}

local sessionByUserId: { [number]: GiantEssenceSnapshot } = {}

local function applyTestStartingEssence(s: GiantEssenceSnapshot, reason: string)
	if TEST_STARTING_ESSENCE <= 0 then
		return
	end

	s.total = TEST_STARTING_ESSENCE
	s.generatedTotal = TEST_STARTING_ESSENCE
	s.lastGeneratedSource = "TestBootstrap"
	s.lastGeneratedAmount = TEST_STARTING_ESSENCE
	debugLog(string.format("Applied test starting essence reason=%s amount=%.0f", reason, TEST_STARTING_ESSENCE))
end

local function getOrCreateSession(userId: number): GiantEssenceSnapshot
	local existing = sessionByUserId[userId]
	if existing then
		return existing
	end

	local s: GiantEssenceSnapshot = {
		total = 0,
		generatedTotal = 0,
		spentTotal = 0,
		lastGeneratedSource = nil,
		lastGeneratedAmount = 0,
		lastSpentReason = nil,
		lastSpentAmount = 0,
	}
	applyTestStartingEssence(s, "init")
	sessionByUserId[userId] = s
	debugLog(string.format("Initialized session userId=%d", userId))
	return s
end

local function snapshotCopyFor(userId: number): GiantEssenceSnapshot
	local s = getOrCreateSession(userId)
	return {
		total = s.total,
		generatedTotal = s.generatedTotal,
		spentTotal = s.spentTotal,
		lastGeneratedSource = s.lastGeneratedSource,
		lastGeneratedAmount = s.lastGeneratedAmount,
		lastSpentReason = s.lastSpentReason,
		lastSpentAmount = s.lastSpentAmount,
	}
end

function GiantEssenceSession.GetSnapshot(userId: number): GiantEssenceSnapshot
	return snapshotCopyFor(userId)
end

function GiantEssenceSession.CanSpend(userId: number, amount: number): boolean
	if amount <= 0 then
		return false
	end

	local s = getOrCreateSession(userId)
	return s.total >= amount
end

function GiantEssenceSession.AddGenerated(userId: number, source: string, amount: number): GiantEssenceSnapshot
	if type(source) ~= "string" or source == "" then
		debugWarn(string.format("Rejected generation update userId=%d reason=invalid_source", userId))
		return snapshotCopyFor(userId)
	end

	if amount <= 0 then
		debugWarn(
			string.format(
				"Rejected generation update userId=%d source=%s reason=non_positive_amount amount=%.2f",
				userId,
				source,
				amount
			)
		)
		return snapshotCopyFor(userId)
	end

	local s = getOrCreateSession(userId)
	s.total += amount
	s.generatedTotal += amount
	s.lastGeneratedSource = source
	s.lastGeneratedAmount = amount

	debugLog(
		string.format(
			"Generated userId=%d source=%s amount=%.0f total=%.0f generatedTotal=%.0f spentTotal=%.0f",
			userId,
			source,
			amount,
			s.total,
			s.generatedTotal,
			s.spentTotal
		)
	)
	return snapshotCopyFor(userId)
end

function GiantEssenceSession.Spend(userId: number, reason: string, amount: number): (boolean, GiantEssenceSnapshot)
	if type(reason) ~= "string" or reason == "" then
		debugWarn(string.format("Rejected spend userId=%d reason=invalid_reason", userId))
		return false, snapshotCopyFor(userId)
	end

	if amount <= 0 then
		debugWarn(
			string.format(
				"Rejected spend userId=%d reason=%s detail=non_positive_amount amount=%.2f",
				userId,
				reason,
				amount
			)
		)
		return false, snapshotCopyFor(userId)
	end

	local s = getOrCreateSession(userId)

	if s.total < amount then
		debugWarn(
			string.format(
				"Rejected spend userId=%d reason=%s detail=insufficient total=%.0f required=%.0f",
				userId,
				reason,
				s.total,
				amount
			)
		)
		return false, snapshotCopyFor(userId)
	end

	s.total -= amount
	s.spentTotal += amount
	s.lastSpentReason = reason
	s.lastSpentAmount = amount

	if s.total < 0 then
		s.total = 0
	end

	debugLog(
		string.format(
			"Spent userId=%d reason=%s amount=%.0f total=%.0f generatedTotal=%.0f spentTotal=%.0f",
			userId,
			reason,
			amount,
			s.total,
			s.generatedTotal,
			s.spentTotal
		)
	)
	return true, snapshotCopyFor(userId)
end

function GiantEssenceSession.ResetSession(userId: number, reason: string)
	local s = getOrCreateSession(userId)
	s.total = 0
	s.generatedTotal = 0
	s.spentTotal = 0
	s.lastGeneratedSource = nil
	s.lastGeneratedAmount = 0
	s.lastSpentReason = nil
	s.lastSpentAmount = 0
	applyTestStartingEssence(s, "reset")

	debugLog(string.format("Reset session userId=%d reason=%s", userId, reason))
end

function GiantEssenceSession.RemoveSession(userId: number)
	sessionByUserId[userId] = nil
	debugLog(string.format("Removed session userId=%d", userId))
end

return GiantEssenceSession
