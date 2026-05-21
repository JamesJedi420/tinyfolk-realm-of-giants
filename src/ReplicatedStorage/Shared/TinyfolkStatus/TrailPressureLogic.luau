--!strict

local TrailPressureLogic: any = {}

export type TrailSample = {
	position: any,
	at: number,
}

export type TrailState = {
	samples: { TrailSample },
	lastSampleAt: number?,
	lastSamplePosition: any?,
}

local function finiteNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function clonePosition(value: any): any?
	if value == nil then
		return nil
	end
	local x = finiteNumber(value.X or value.x)
	local y = finiteNumber(value.Y or value.y)
	local z = finiteNumber(value.Z or value.z)
	if x == nil or y == nil or z == nil then
		return nil
	end
	return {
		X = x,
		Y = y,
		Z = z,
	}
end

local function cloneState(state: TrailState?): TrailState
	local nextState: TrailState = {
		samples = {},
		lastSampleAt = nil,
		lastSamplePosition = nil,
	}
	if state == nil then
		return nextState
	end
	for _, sample in ipairs(state.samples or {}) do
		local position = clonePosition(sample.position)
		local at = finiteNumber(sample.at)
		if position ~= nil and at ~= nil then
			table.insert(nextState.samples, {
				position = position,
				at = at,
			})
		end
	end
	nextState.lastSampleAt = finiteNumber(state.lastSampleAt)
	nextState.lastSamplePosition = clonePosition(state.lastSamplePosition)
	return nextState
end

local function distanceBetween(a: any, b: any): number?
	local aPos = clonePosition(a)
	local bPos = clonePosition(b)
	if aPos == nil or bPos == nil then
		return nil
	end
	local dx = aPos.X - bPos.X
	local dy = aPos.Y - bPos.Y
	local dz = aPos.Z - bPos.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function directionBucket(fromPosition: any, toPosition: any): string
	local fromPos = clonePosition(fromPosition)
	local toPos = clonePosition(toPosition)
	if fromPos == nil or toPos == nil then
		return "unknown"
	end

	local dx = toPos.X - fromPos.X
	local dz = toPos.Z - fromPos.Z
	local absDx = math.abs(dx)
	local absDz = math.abs(dz)
	if absDx < 0.001 and absDz < 0.001 then
		return "stationary"
	end

	if absDx > absDz * 1.5 then
		return if dx >= 0 then "east" else "west"
	end
	if absDz > absDx * 1.5 then
		return if dz >= 0 then "south" else "north"
	end
	if dx >= 0 and dz >= 0 then
		return "southeast"
	end
	if dx >= 0 and dz < 0 then
		return "northeast"
	end
	if dx < 0 and dz >= 0 then
		return "southwest"
	end
	return "northwest"
end

local function getLifetime(config: any): number
	local lifetime = finiteNumber(config and config.TrailLifetimeSeconds) or 6
	return math.max(lifetime, 0)
end

local function getMaxPoints(config: any): number
	local maxPoints = finiteNumber(config and config.TrailMaxPoints) or 6
	maxPoints = math.floor(math.max(maxPoints, 1))
	return maxPoints
end

local function getMinDistance(config: any): number
	local minDistance = finiteNumber(config and config.TrailSampleMinDistanceStuds) or 4
	return math.max(minDistance, 0)
end

local function getMinInterval(config: any): number
	local minInterval = finiteNumber(config and config.TrailSampleMinIntervalSeconds) or 0.25
	return math.max(minInterval, 0)
end

local function pruneExpired(state: TrailState, config: any, now: number)
	local lifetime = getLifetime(config)
	local keepAfter = now - lifetime
	local kept: { TrailSample } = {}
	for _, sample in ipairs(state.samples) do
		if sample.at >= keepAfter then
			table.insert(kept, sample)
		end
	end
	state.samples = kept
	if #state.samples == 0 then
		state.lastSampleAt = nil
		state.lastSamplePosition = nil
	end
end

function TrailPressureLogic.NewState(): TrailState
	return cloneState(nil)
end

function TrailPressureLogic.ResolveSample(state: TrailState?, config: any, input: any): TrailState
	local nextState = cloneState(state)
	local now = finiteNumber(input and input.now)
	if now == nil then
		return nextState
	end

	pruneExpired(nextState, config, now)

	if input == nil or input.shouldEmit ~= true then
		return nextState
	end

	local position = clonePosition(input.position)
	if position == nil then
		return nextState
	end

	local minInterval = getMinInterval(config)
	local minDistance = getMinDistance(config)
	local lastSampleAt = nextState.lastSampleAt
	local lastSamplePosition = nextState.lastSamplePosition
	local canSampleByInterval = lastSampleAt == nil or now - (lastSampleAt :: number) >= minInterval
	local canSampleByDistance = lastSamplePosition == nil
		or ((distanceBetween(position, lastSamplePosition) or 0) >= minDistance)

	if not canSampleByInterval or not canSampleByDistance then
		return nextState
	end

	table.insert(nextState.samples, {
		position = position,
		at = now,
	})
	nextState.lastSampleAt = now
	nextState.lastSamplePosition = position

	local maxPoints = getMaxPoints(config)
	while #nextState.samples > maxPoints do
		table.remove(nextState.samples, 1)
	end

	return nextState
end

function TrailPressureLogic.BuildSnapshot(state: TrailState?, config: any, now: number): any
	local activeState = cloneState(state)
	local activeNow = finiteNumber(now) or 0
	pruneExpired(activeState, config, activeNow)

	local lifetime = getLifetime(config)
	local segments = {}
	for index = 2, #activeState.samples do
		local previous = activeState.samples[index - 1]
		local current = activeState.samples[index]
		local ageSeconds = math.max(activeNow - current.at, 0)
		local ageRatio = if lifetime > 0 then math.min(ageSeconds / lifetime, 1) else 1
		table.insert(segments, {
			direction = directionBucket(previous.position, current.position),
			startedAt = previous.at,
			endedAt = current.at,
			ageSeconds = ageSeconds,
			ageRatio = ageRatio,
		})
	end

	return {
		hasPressure = #segments > 0,
		sampleCount = #activeState.samples,
		segmentCount = #segments,
		oldestAt = activeState.samples[1] and activeState.samples[1].at or nil,
		newestAt = activeState.samples[#activeState.samples] and activeState.samples[#activeState.samples].at or nil,
		segments = segments,
	}
end

return TrailPressureLogic
