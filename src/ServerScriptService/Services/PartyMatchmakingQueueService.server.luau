--!nocheck

local PartyMatchmakingQueueService = require(script.Parent.PartyMatchmakingQueueService)
PartyMatchmakingQueueService.Start({
	enableProcessingLoop = true,
})
