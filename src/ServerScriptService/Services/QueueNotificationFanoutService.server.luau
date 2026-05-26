--!nocheck

local QueueNotificationFanout = require(script.Parent:WaitForChild("QueueNotificationFanout"))

local globalEnv: any = getfenv()
local fanout = QueueNotificationFanout.CreateDefault()
if type(fanout) == "table" then
	globalEnv._QueueNotificationFanout_QueryAPI = fanout
	if type(_G) == "table" then
		rawset(_G, "_QueueNotificationFanout_QueryAPI", fanout)
	end
end

return globalEnv._QueueNotificationFanout_QueryAPI
