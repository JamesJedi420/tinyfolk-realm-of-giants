--!strict

local WoodSession = {}

local function debugLog(message: string)
	print(string.format("[WoodSession] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[WoodSession] %s", message))
end

type WoodSnapshot = {
	total: number,
	generatedTotal: number,
	lastGeneratedSource: string?,
	lastGeneratedAmount: number,
}

local state: WoodSnapshot = {
	total = 0,
	generatedTotal = 0,
	lastGeneratedSource = nil,
	lastGeneratedAmount = 0,
}

local function snapshotCopy(): WoodSnapshot
	return {
		total = state.total,
		generatedTotal = state.generatedTotal,
		lastGeneratedSource = state.lastGeneratedSource,
		lastGeneratedAmount = state.lastGeneratedAmount,
	}
end

function WoodSession.GetSnapshot(): WoodSnapshot
	return snapshotCopy()
end

function WoodSession.AddGenerated(source: string, amount: number): WoodSnapshot
	if type(source) ~= "string" or source == "" then
		debugWarn("Rejected generation update reason=invalid_source")
		return snapshotCopy()
	end

	if amount <= 0 then
		debugWarn(string.format("Rejected generation update source=%s reason=non_positive_amount amount=%.2f", source, amount))
		return snapshotCopy()
	end

	state.total += amount
	state.generatedTotal += amount
	state.lastGeneratedSource = source
	state.lastGeneratedAmount = amount

	debugLog(string.format("Generated source=%s amount=%.0f total=%.0f generatedTotal=%.0f", source, amount, state.total, state.generatedTotal))
	return snapshotCopy()
end

function WoodSession.ResetSession(reason: string)
	state.total = 0
	state.generatedTotal = 0
	state.lastGeneratedSource = nil
	state.lastGeneratedAmount = 0

	debugLog(string.format("Reset session reason=%s", reason))
end

return WoodSession
