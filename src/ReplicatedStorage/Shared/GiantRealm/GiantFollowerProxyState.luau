--!strict

local GiantFollowerProxyState = {}

export type ProxyState = {
	enabled: boolean,
	controlMode: string,
	lastSwitchAt: number?,
	lastRequestAt: number?,
	lastPressureAt: number?,
}

local function readBand(config: any, key: string): string
	if type(config) ~= "table" or type(config.PressureBands) ~= "table" then
		return string.lower(key)
	end

	local band = config.PressureBands[key]
	if type(band) == "string" and band ~= "" then
		return band
	end

	return string.lower(key)
end

function GiantFollowerProxyState.NewState(_now: number): ProxyState
	return {
		enabled = false,
		controlMode = "direct",
		lastSwitchAt = nil,
		lastRequestAt = nil,
		lastPressureAt = nil,
	}
end

function GiantFollowerProxyState.RequestMode(state: ProxyState, config: any, requestedMode: string, now: number): any
	if requestedMode ~= "direct" and requestedMode ~= "proxy" then
		return {
			accepted = false,
			reason = "mode_invalid",
			state = state,
		}
	end

	local cooldown = if type(config.ControlSwitchCooldownSeconds) == "number"
		then config.ControlSwitchCooldownSeconds
		else 0
	if state.lastSwitchAt ~= nil and (now - state.lastSwitchAt) < cooldown then
		return {
			accepted = false,
			reason = "control_switch_cooldown",
			state = state,
		}
	end

	state.controlMode = requestedMode
	state.enabled = requestedMode == "proxy"
	state.lastSwitchAt = now
	state.lastRequestAt = now
	return {
		accepted = true,
		reason = "accepted",
		state = state,
	}
end

function GiantFollowerProxyState.BuildPressureSnapshot(
	state: ProxyState,
	config: any,
	now: number,
	trailSnapshots: { [number]: any }
): any
	if state.enabled ~= true then
		return {
			enabled = false,
			pressureBand = readBand(config, "None"),
			direction = nil,
			trackedCount = 0,
			updatedAt = now,
		}
	end

	local minIntensity = if type(config.TrailMinimumIntensity) == "number" then config.TrailMinimumIntensity else 0.25
	local freshnessWindow = if type(config.TrailFreshnessSeconds) == "number" then config.TrailFreshnessSeconds else 6
	local maxTracked = if type(config.MaxTrackedTinyfolk) == "number" then config.MaxTrackedTinyfolk else 2

	local candidates = {}
	for userId, snapshot in pairs(trailSnapshots) do
		if type(snapshot) == "table" then
			local intensity = snapshot.intensity
			local updatedAt = snapshot.updatedAt
			local direction = snapshot.primaryDirection
			if
				type(intensity) == "number"
				and type(updatedAt) == "number"
				and type(direction) == "string"
				and intensity >= minIntensity
				and (now - updatedAt) <= freshnessWindow
			then
				table.insert(candidates, {
					userId = userId,
					intensity = intensity,
					updatedAt = updatedAt,
					direction = direction,
				})
			end
		end
	end

	table.sort(candidates, function(a, b)
		if a.intensity == b.intensity then
			return a.updatedAt > b.updatedAt
		end
		return a.intensity > b.intensity
	end)

	local trackedCount = math.min(#candidates, maxTracked)
	local lead = candidates[1]
	local pressureBand = readBand(config, "Watch")
	if lead ~= nil and lead.intensity >= 0.65 then
		pressureBand = readBand(config, "Pressure")
	end
	if lead == nil then
		pressureBand = readBand(config, "None")
	end

	if lead ~= nil then
		state.lastPressureAt = now
	end

	return {
		enabled = true,
		pressureBand = pressureBand,
		direction = if lead ~= nil then lead.direction else nil,
		trackedCount = trackedCount,
		updatedAt = now,
	}
end

return GiantFollowerProxyState
