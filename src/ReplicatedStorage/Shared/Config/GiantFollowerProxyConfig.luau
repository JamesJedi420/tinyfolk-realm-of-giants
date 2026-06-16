--!strict

local GiantFollowerProxyConfig = {
	RequestCooldownSeconds = 1.5,
	ControlSwitchCooldownSeconds = 6,
	PressureRetainSeconds = 4,
	MaxTrackedTinyfolk = 2,
	TrailMinimumIntensity = 0.25,
	TrailFreshnessSeconds = 6,
	PressureBands = {
		None = "none",
		Watch = "watch",
		Pressure = "pressure",
	},
}

return GiantFollowerProxyConfig
