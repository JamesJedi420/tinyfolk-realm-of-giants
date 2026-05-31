--!nocheck

local NotificationRateGuard = require(script.Parent:WaitForChild("NotificationRateGuard"))

NotificationRateGuard.Start()

return NotificationRateGuard
