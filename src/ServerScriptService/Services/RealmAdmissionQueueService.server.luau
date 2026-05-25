--!nocheck

local RealmAdmissionQueueService = require(script.Parent.RealmAdmissionQueueService)
RealmAdmissionQueueService.Start({
	enableProcessingLoop = true,
})
