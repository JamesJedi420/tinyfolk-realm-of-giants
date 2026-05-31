--!nocheck

local MessagingServiceAdapter = require(script.Parent:WaitForChild("MessagingServiceAdapter"))
local NotificationRateGuard = require(script.Parent:WaitForChild("NotificationRateGuard"))

local globalEnv: any = getfenv()
local rateGuard = rawget(globalEnv, "_NotificationRateGuard_QueryAPI")
if type(rateGuard) ~= "table" then
	NotificationRateGuard.Start()
end

local adapter = MessagingServiceAdapter.CreateDefault()
if type(adapter) == "table" then
	globalEnv._MessagingServiceAdapter_QueryAPI = adapter
	if type(_G) == "table" then
		rawset(_G, "_MessagingServiceAdapter_QueryAPI", adapter)
	end
end

return globalEnv._MessagingServiceAdapter_QueryAPI
