--!strict

local TaskQteTimingLogic = {}

export type EvaluateInput = {
	now: number,
	targetAt: number?,
	windowSeconds: number,
	bonusSeconds: number,
}

export type EvaluateResult = {
	success: boolean,
	effectiveNow: number,
	deltaSeconds: number,
	reason: string,
}

local function finite(value: any, fallback: number): number
	if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
		return value
	end

	return fallback
end

function TaskQteTimingLogic.Evaluate(input: EvaluateInput): EvaluateResult
	local now = finite(input.now, 0)
	local targetAt = input.targetAt
	local windowSeconds = math.max(0, finite(input.windowSeconds, 0.2))
	local bonusSeconds = math.max(0, finite(input.bonusSeconds, 0))

	if type(targetAt) ~= "number" then
		return {
			success = true,
			effectiveNow = now,
			deltaSeconds = 0,
			reason = "no_target",
		}
	end
	local target = targetAt :: number

	local deltaSeconds = math.abs(now - target)
	if deltaSeconds <= windowSeconds then
		return {
			success = true,
			effectiveNow = now + bonusSeconds,
			deltaSeconds = deltaSeconds,
			reason = "success",
		}
	end

	return {
		success = false,
		effectiveNow = now,
		deltaSeconds = deltaSeconds,
		reason = "outside_window",
	}
end

return TaskQteTimingLogic
