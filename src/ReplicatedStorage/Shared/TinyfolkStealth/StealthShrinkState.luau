--!strict

export type StealthSnapshot = {
	isActive: boolean,
	startedAt: number?,
	endsAt: number?,
	remainingSeconds: number,
	lastReason: string?,
	lastChangedAt: number?,
}

export type StealthShrinkState = {
	isActive: boolean,
	startedAt: number?,
	endsAt: number?,
	lastReason: string?,
	lastChangedAt: number?,
	Activate: (self: StealthShrinkState, now: number, duration: number) -> (boolean, string),
	Cancel: (self: StealthShrinkState, reason: string, at: number) -> (boolean, string),
	Tick: (self: StealthShrinkState, now: number) -> (boolean, string?),
	GetSnapshot: (self: StealthShrinkState, now: number) -> StealthSnapshot,
}

local StealthShrinkState = {}
StealthShrinkState.__index = StealthShrinkState

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function StealthShrinkState.new(): StealthShrinkState
	local self = setmetatable({
		isActive = false,
		startedAt = nil,
		endsAt = nil,
		lastReason = nil,
		lastChangedAt = nil,
	}, StealthShrinkState)
	return self :: any
end

function StealthShrinkState.Activate(self: StealthShrinkState, now: number, duration: number): (boolean, string)
	if self.isActive then
		return false, "already_active"
	end
	if not isFiniteNumber(now) then
		return false, "invalid_now"
	end
	if not isFiniteNumber(duration) or duration <= 0 then
		return false, "duration_invalid"
	end

	self.isActive = true
	self.startedAt = now
	self.endsAt = now + duration
	self.lastReason = "accepted"
	self.lastChangedAt = now
	return true, "accepted"
end

function StealthShrinkState.Cancel(self: StealthShrinkState, reason: string, at: number): (boolean, string)
	if not self.isActive then
		return false, "not_active"
	end
	if type(reason) ~= "string" or reason == "" then
		return false, "cancel_reason_invalid"
	end
	if not isFiniteNumber(at) then
		return false, "invalid_now"
	end

	self.isActive = false
	self.startedAt = nil
	self.endsAt = nil
	self.lastReason = reason
	self.lastChangedAt = at
	return true, reason
end

function StealthShrinkState.Tick(self: StealthShrinkState, now: number): (boolean, string?)
	if not self.isActive then
		return false, nil
	end
	if not isFiniteNumber(now) then
		return false, nil
	end
	local endsAt = self.endsAt
	if endsAt == nil then
		return false, nil
	end
	if now < endsAt then
		return false, nil
	end

	self.isActive = false
	self.startedAt = nil
	self.endsAt = nil
	self.lastReason = "expired"
	self.lastChangedAt = now
	return true, "expired"
end

function StealthShrinkState.GetSnapshot(self: StealthShrinkState, now: number): StealthSnapshot
	local remaining = 0
	local endsAt = self.endsAt
	if self.isActive and endsAt ~= nil and isFiniteNumber(endsAt) and isFiniteNumber(now) then
		remaining = math.max((endsAt :: number) - now, 0)
	end

	return {
		isActive = self.isActive,
		startedAt = self.startedAt,
		endsAt = endsAt,
		remainingSeconds = remaining,
		lastReason = self.lastReason,
		lastChangedAt = self.lastChangedAt,
	}
end

return StealthShrinkState
