--!strict
-- Tinyfolk Hiding State Machine

export type HidingState = any

local HidingState = {}
HidingState.__index = HidingState

type Coordinates = { x: number, y: number, z: number }

local function getCoordinates(value: any): Coordinates?
	if value == nil then
		return nil
	end
	local x = value.X or value.x
	local y = value.Y or value.y
	local z = value.Z or value.z
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return nil
	end
	return { x = x, y = y, z = z }
end

local function distanceBetween(a: any, b: any): number?
	local aCoords = getCoordinates(a)
	local bCoords = getCoordinates(b)
	if aCoords == nil or bCoords == nil then
		return nil
	end
	local dx = aCoords.x - bCoords.x
	local dy = aCoords.y - bCoords.y
	local dz = aCoords.z - bCoords.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function HidingState.new(): HidingState
	local self = setmetatable({
		isHiding = false,
		zoneId = nil,
		hiddenStartedAt = nil,
		endsAt = nil,
		lastRevealReason = nil,
	}, HidingState)
	return self
end

function HidingState:Enter(zoneId: string, now: number, duration: number)
	local safeNow = if type(now) == "number" and now == now and now ~= math.huge and now ~= -math.huge then now else 0
	local safeDuration = if type(duration) == "number"
			and duration == duration
			and duration ~= math.huge
			and duration ~= -math.huge
		then math.max(duration, 0)
		else 0
	self.isHiding = true
	self.zoneId = zoneId
	self.hiddenStartedAt = safeNow
	self.endsAt = safeNow + safeDuration
	self.lastRevealReason = nil
end

function HidingState:Exit(reason: string, _at: number?)
	self.isHiding = false
	self.zoneId = nil
	self.hiddenStartedAt = nil
	self.endsAt = nil
	self.lastRevealReason = reason
end

function HidingState:ProbeReveal(now: number, revealProximity: number, giantPositions: { any }, zonePosition: any)
	if not self.isHiding or not self.zoneId or not self.hiddenStartedAt or not self.endsAt then
		return false, "not_hiding"
	end
	if now >= self.endsAt then
		return true, "timeout"
	end
	for _, giantPos in ipairs(if type(giantPositions) == "table" then giantPositions else {}) do
		local distance = distanceBetween(giantPos, zonePosition)
		if distance ~= nil and distance <= revealProximity then
			return true, "giant_proximity"
		end
	end
	return false, nil
end

function HidingState:GetSnapshot(now: number)
	local hiddenFor = 0
	if self.hiddenStartedAt ~= nil then
		hiddenFor = math.max(now - self.hiddenStartedAt, 0)
	end
	return {
		isHiding = self.isHiding,
		zoneId = self.zoneId,
		hiddenFor = hiddenFor,
		endsAt = self.endsAt,
		lastRevealReason = self.lastRevealReason,
	}
end

return HidingState
