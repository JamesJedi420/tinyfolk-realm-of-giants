--!nocheck

local NotificationReconciliationService = require(script.Parent:WaitForChild("NotificationReconciliationService"))

NotificationReconciliationService.Start({
	enableReconciliationLoop = true,
	enableReturnRecoveryOnJoin = true,
})

return NotificationReconciliationService
