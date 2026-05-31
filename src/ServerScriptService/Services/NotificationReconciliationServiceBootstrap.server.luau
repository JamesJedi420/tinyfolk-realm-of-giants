--!nocheck

local NotificationReconciliationService = require(script.Parent:WaitForChild("NotificationReconciliationService"))

NotificationReconciliationService.Start({
	enableReconciliationLoop = true,
})

return NotificationReconciliationService
