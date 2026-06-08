--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local MockPlayer = require("../tests/mocks/MockPlayer")
local globalEnv: any = getfenv()

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function findQueueEntryForRescuer(entries: { any }, rescuerUserId: number): any
	for _, entry in ipairs(entries) do
		if type(entry) == "table" and entry.rescuerUserId == rescuerUserId then
			return entry
		end
	end
	return nil
end

local function makeSignal()
	local callbacks: { (...any) -> () } = {}
	return {
		Connect = function(_self: any, callback: (...any) -> ())
			table.insert(callbacks, callback)
			return {}
		end,
		Fire = function(_self: any, ...: any)
			for _, callback in ipairs(callbacks) do
				callback(...)
			end
		end,
	}
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
		_Attributes = {},
	}

	function node.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end

	function node.GetAttribute(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		_Handler = nil,
	}

	function remote.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote.FireClient(_self: any, _player: any, _payload: any)
		return
	end

	return remote
end

local remotesFolder = makeNode("Remotes", "Folder")
addChild(remotesFolder, "RescueContractRequest", makeRemoteEvent("RescueContractRequest"))
addChild(remotesFolder, "RescueContractResponse", makeRemoteEvent("RescueContractResponse"))
addChild(remotesFolder, "RescueContractCompleteRequest", makeRemoteEvent("RescueContractCompleteRequest"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
addChild(configFolder, "EscapeConfig", "../../ReplicatedStorage/Shared/Config/EscapeConfig")
addChild(configFolder, "RescueContractConfig", "../../ReplicatedStorage/Shared/Config/RescueContractConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "SafeZonePolicy", "../../ReplicatedStorage/Shared/GiantRealm/SafeZonePolicy")
addChild(giantRealmFolder, "RescueContractState", "../../ReplicatedStorage/Shared/GiantRealm/RescueContractState")
addChild(
	giantRealmFolder,
	"RescueContractQueueState",
	"../../ReplicatedStorage/Shared/GiantRealm/RescueContractQueueState"
)
addChild(giantRealmFolder, "GiantRealmSaveSchema", "../../ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema")
addChild(
	giantRealmFolder,
	"GiantRealmResourceState",
	"../../ReplicatedStorage/Shared/GiantRealm/GiantRealmResourceState"
)

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local rescuerOne = MockPlayer.new(7101, "RescuerOne", { role = "Tinyfolk", positionZ = 0, health = 100 })
local targetOne = MockPlayer.new(7102, "TargetOne", { role = "Tinyfolk", positionZ = 4, health = 100 })
local acceptedByOne = MockPlayer.new(7103, "AcceptedByOne", { role = "Tinyfolk", positionZ = 2, health = 100 })
local rescuerTwo = MockPlayer.new(7111, "RescuerTwo", { role = "Tinyfolk", positionZ = 0, health = 100 })
local targetTwo = MockPlayer.new(7112, "TargetTwo", { role = "Tinyfolk", positionZ = 4, health = 100 })
local acceptedByTwo = MockPlayer.new(7113, "AcceptedByTwo", { role = "Tinyfolk", positionZ = 2, health = 100 })
local rescuerThree = MockPlayer.new(7121, "RescuerThree", { role = "Tinyfolk", positionZ = 0, health = 100 })
local targetThree = MockPlayer.new(7122, "TargetThree", { role = "Tinyfolk", positionZ = 4, health = 100 })
local acceptedByThree = MockPlayer.new(7123, "AcceptedByThree", { role = "Tinyfolk", positionZ = 2, health = 100 })
local rescuerFour = MockPlayer.new(7131, "RescuerFour", { role = "Tinyfolk", positionZ = 0, health = 100 })
local targetFour = MockPlayer.new(7132, "TargetFour", { role = "Tinyfolk", positionZ = 4, health = 100 })
local acceptedByFour = MockPlayer.new(7133, "AcceptedByFour", { role = "Tinyfolk", positionZ = 2, health = 100 })

targetOne:SetAttribute("DownedIsDowned", true)
targetOne:SetAttribute("GiantRealmOwnerUserId", 9011)
targetTwo:SetAttribute("DownedIsDowned", true)
targetTwo:SetAttribute("GiantRealmOwnerUserId", 9012)
targetThree:SetAttribute("DownedIsDowned", true)
targetThree:SetAttribute("GiantRealmOwnerUserId", 9013)
targetFour:SetAttribute("DownedIsDowned", true)
targetFour:SetAttribute("GiantRealmOwnerUserId", 9014)

local playersList: { any } = {
	rescuerOne,
	targetOne,
	acceptedByOne,
	rescuerTwo,
	targetTwo,
	acceptedByTwo,
	rescuerThree,
	targetThree,
	acceptedByThree,
	rescuerFour,
	targetFour,
	acceptedByFour,
}
local playersService: any = { PlayerRemoving = makeSignal() }

function playersService:GetPlayers(): { any }
	return playersList
end

local workspaceService = makeNode("Workspace", "Workspace")
local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

require("../src/ServerScriptService/Services/RescueAdmissionService.server")
local rescueAdmissionApi = globalEnv._RescueAdmissionService_QueryAPI

globalEnv._GrabService_QueryAPI = {
	IsPlayerCarried = function(_userId: number): boolean
		return false
	end,
}

globalEnv._RoleService_QueryAPI = {
	IsPlayerDowned = function(userId: number): boolean
		for _, player in ipairs(playersList) do
			if player.UserId == userId then
				return player:GetAttribute("DownedIsDowned") == true
			end
		end
		return false
	end,
	CanPlayerPerformInteraction = function(_userId: number, _interactionName: string): boolean
		return true
	end,
}

globalEnv._EscapeService_QueryAPI = {
	ResolveRescueEntryRoute = function(_targetUserId: number, _targetRealmOwnerUserId: number): any
		return { accepted = true, routeId = "rescue_entry_route", routeKind = "RescueEntry" }
	end,
}

globalEnv._RescueHandoffService_QueryAPI = {
	CreateHandoffLock = function(_payload: any): any
		return { accepted = true, reason = "accepted" }
	end,
}

local ingressPayloads: { any } = {}
rescueAdmissionApi.ConfigureForTests({
	now = function(): number
		return 100
	end,
	admissionQueueApi = {
		EnqueueAdmission = function(payload: any): any
			table.insert(ingressPayloads, payload)
			return { accepted = true, reason = "accepted" }
		end,
	},
})

require("../src/ServerScriptService/Services/RescueContractService.server")
local queryApi = globalEnv._RescueContractService_QueryAPI
queryApi.ResetForTests()
rescueAdmissionApi.ResetForTests()
rescueAdmissionApi.ConfigureForTests({
	now = function(): number
		return 100
	end,
	admissionQueueApi = {
		EnqueueAdmission = function(payload: any): any
			table.insert(ingressPayloads, payload)
			return { accepted = true, reason = "accepted" }
		end,
	},
})

local requestOne = queryApi.RequestRescueContract(rescuerOne.UserId, targetOne.UserId, 10)
assertEqual(requestOne.accepted, true, "request one accepted")
local pendingOne = queryApi.GetRescueQueueEntries(10)
assertEqual(#pendingOne, 1, "one pending queue entry")

local acceptOne = queryApi.AcceptRescueQueueEntry(acceptedByOne.UserId, pendingOne[1].queueEntryId, 10.5)
assertEqual(acceptOne.accepted, true, "accept one accepted")
assertEqual(#ingressPayloads, 1, "ingress seam called once")
assertEqual(ingressPayloads[1].entryType, "rescue_contract", "ingress entry type")
assertEqual(ingressPayloads[1].targetRealmId, pendingOne[1].realmId, "ingress target realm")
assertEqual(type(ingressPayloads[1].partyMemberUserIds), "table", "ingress members table")
assertEqual(#ingressPayloads[1].partyMemberUserIds, 3, "ingress members count")
assertEqual(ingressPayloads[1].partyMemberUserIds[1], rescuerOne.UserId, "ingress member 1")
assertEqual(ingressPayloads[1].partyMemberUserIds[2], targetOne.UserId, "ingress member 2")
assertEqual(ingressPayloads[1].partyMemberUserIds[3], acceptedByOne.UserId, "ingress member 3")
local diagnosticsAfterPrimary = queryApi.GetAdmissionIngressDiagnostics()
local rescueDiagnosticsAfterPrimary = rescueAdmissionApi.GetAdmissionDiagnostics()
assertEqual(diagnosticsAfterPrimary.totalAttempts, 1, "total attempts tracked")
assertEqual(diagnosticsAfterPrimary.primaryAttempts, 1, "primary attempts tracked")
assertEqual(diagnosticsAfterPrimary.primarySucceeded, 1, "primary success tracked")
assertEqual(diagnosticsAfterPrimary.primaryFailed, 0, "primary failures baseline")
assertEqual(diagnosticsAfterPrimary.fallbackAttempts, 0, "fallback attempts baseline")
assertEqual(diagnosticsAfterPrimary.lastPath, "primary", "primary path tracked")
assertEqual(diagnosticsAfterPrimary.lastReason, "accepted", "primary reason tracked")
assertEqual(diagnosticsAfterPrimary.lastPrimaryReason, "accepted", "primary last reason tracked")
assertEqual(rescueDiagnosticsAfterPrimary.enqueueAttempts, 1, "rescue diagnostics attempts track primary success")
assertEqual(rescueDiagnosticsAfterPrimary.enqueueSucceeded, 1, "rescue diagnostics success track primary success")
assertEqual(rescueDiagnosticsAfterPrimary.enqueueFailed, 0, "rescue diagnostics failure baseline")
assertEqual(
	rescueDiagnosticsAfterPrimary.lastReason,
	diagnosticsAfterPrimary.lastPrimaryReason,
	"primary diagnostics parity"
)

rescueAdmissionApi.ConfigureForTests({
	now = function(): number
		return 200
	end,
	admissionQueueApi = {
		EnqueueAdmission = function(_payload: any): any
			error("boom")
		end,
	},
})

local requestTwo = queryApi.RequestRescueContract(rescuerTwo.UserId, targetTwo.UserId, 20)
assertEqual(requestTwo.accepted, true, "request two accepted")
local pendingTwo = queryApi.GetRescueQueueEntries(20)
assertEqual(#pendingTwo, 1, "one pending queue entry for second request")

local acceptTwo = queryApi.AcceptRescueQueueEntry(acceptedByTwo.UserId, pendingTwo[1].queueEntryId, 20.5)
assertEqual(acceptTwo.accepted, false, "ingress exception rejected")
assertEqual(acceptTwo.reason, "admission_enqueue_failed", "ingress exception reason")
local diagnosticsAfterPrimaryFailure = queryApi.GetAdmissionIngressDiagnostics()
local rescueDiagnosticsAfterPrimaryFailure = rescueAdmissionApi.GetAdmissionDiagnostics()
assertEqual(diagnosticsAfterPrimaryFailure.totalAttempts, 2, "total attempts include primary failure")
assertEqual(diagnosticsAfterPrimaryFailure.primaryAttempts, 2, "primary attempts include failure")
assertEqual(diagnosticsAfterPrimaryFailure.primarySucceeded, 1, "primary success count preserved")
assertEqual(diagnosticsAfterPrimaryFailure.primaryFailed, 1, "primary failure tracked")
assertEqual(diagnosticsAfterPrimaryFailure.fallbackAttempts, 0, "fallback still unused")
assertEqual(diagnosticsAfterPrimaryFailure.lastPath, "primary", "primary failure path tracked")
assertEqual(diagnosticsAfterPrimaryFailure.lastReason, "admission_enqueue_failed", "primary failure reason tracked")
assertEqual(
	diagnosticsAfterPrimaryFailure.lastPrimaryReason,
	"admission_enqueue_failed",
	"primary failure last primary reason tracked"
)
assertEqual(
	rescueDiagnosticsAfterPrimaryFailure.enqueueAttempts,
	2,
	"rescue diagnostics attempts include primary failure"
)
assertEqual(rescueDiagnosticsAfterPrimaryFailure.enqueueFailed, 1, "rescue diagnostics failure tracks primary failure")
assertEqual(
	rescueDiagnosticsAfterPrimaryFailure.lastReason,
	diagnosticsAfterPrimaryFailure.lastPrimaryReason,
	"primary failure diagnostics parity"
)

rescueAdmissionApi.ConfigureForTests({
	now = function(): number
		return 300
	end,
	admissionQueueApi = {
		EnqueueAdmission = function(_payload: any): any
			return { accepted = false, reason = "queue_backpressure" }
		end,
	},
})

local requestThree = queryApi.RequestRescueContract(rescuerThree.UserId, targetThree.UserId, 30)
assertEqual(requestThree.accepted, true, "request three accepted")
local pendingThree = queryApi.GetRescueQueueEntries(30)
local pendingThreeEntry = findQueueEntryForRescuer(pendingThree, rescuerThree.UserId)
assertEqual(type(pendingThreeEntry), "table", "third request queue entry exists")

local acceptRejectedByPrimary =
	queryApi.AcceptRescueQueueEntry(acceptedByThree.UserId, pendingThreeEntry.queueEntryId, 30.5)
assertEqual(acceptRejectedByPrimary.accepted, false, "primary rejected enqueue is propagated")
assertEqual(acceptRejectedByPrimary.reason, "queue_backpressure", "primary rejected reason propagated")
local diagnosticsAfterPrimaryRejected = queryApi.GetAdmissionIngressDiagnostics()
local rescueDiagnosticsAfterPrimaryRejected = rescueAdmissionApi.GetAdmissionDiagnostics()
assertEqual(diagnosticsAfterPrimaryRejected.totalAttempts, 3, "total attempts include primary rejection")
assertEqual(diagnosticsAfterPrimaryRejected.primaryAttempts, 3, "primary attempts include primary rejection")
assertEqual(diagnosticsAfterPrimaryRejected.primaryFailed, 2, "primary failure count includes rejection")
assertEqual(diagnosticsAfterPrimaryRejected.lastPath, "primary", "primary rejection path tracked")
assertEqual(diagnosticsAfterPrimaryRejected.lastReason, "queue_backpressure", "primary rejection reason tracked")
assertEqual(
	diagnosticsAfterPrimaryRejected.lastPrimaryReason,
	"queue_backpressure",
	"primary rejection last primary reason tracked"
)
assertEqual(
	rescueDiagnosticsAfterPrimaryRejected.enqueueAttempts,
	3,
	"rescue diagnostics attempts include primary rejection"
)
assertEqual(
	rescueDiagnosticsAfterPrimaryRejected.enqueueFailed,
	2,
	"rescue diagnostics failures include primary rejection"
)
assertEqual(
	rescueDiagnosticsAfterPrimaryRejected.lastReason,
	diagnosticsAfterPrimaryRejected.lastPrimaryReason,
	"primary rejection diagnostics parity"
)

rescueAdmissionApi.ResetForTests()
globalEnv._RescueAdmissionService_QueryAPI = nil
globalEnv._RealmAdmissionQueue_QueryAPI = {
	EnqueueAdmission = function(_payload: any): any
		return {
			accepted = true,
			reason = "accepted",
		}
	end,
}

local acceptThree = queryApi.AcceptRescueQueueEntry(acceptedByTwo.UserId, pendingTwo[1].queueEntryId, 30.5)
assertEqual(acceptThree.accepted, true, "fallback enqueue accepted")
local diagnosticsAfterFallback = queryApi.GetAdmissionIngressDiagnostics()
assertEqual(diagnosticsAfterFallback.totalAttempts, 4, "total attempts include fallback success")
assertEqual(diagnosticsAfterFallback.fallbackAttempts, 1, "fallback attempt tracked")
assertEqual(diagnosticsAfterFallback.fallbackSucceeded, 1, "fallback success tracked")
assertEqual(diagnosticsAfterFallback.fallbackFailed, 0, "fallback failure baseline")
assertEqual(diagnosticsAfterFallback.lastPath, "fallback", "fallback path tracked")
assertEqual(diagnosticsAfterFallback.lastReason, "accepted", "fallback reason tracked")
assertEqual(diagnosticsAfterFallback.lastFallbackReason, "accepted", "fallback last reason tracked")

globalEnv._RealmAdmissionQueue_QueryAPI = {
	EnqueueAdmission = function(_payload: any): any
		return {
			accepted = false,
			reason = "queue_backpressure",
		}
	end,
}

local requestFour = queryApi.RequestRescueContract(rescuerFour.UserId, targetFour.UserId, 40)
assertEqual(requestFour.accepted, true, "request four accepted")
local pendingFour = queryApi.GetRescueQueueEntries(40)
local pendingFourEntry = findQueueEntryForRescuer(pendingFour, rescuerFour.UserId)
assertEqual(type(pendingFourEntry), "table", "fourth request queue entry exists")

local acceptFallbackRejected =
	queryApi.AcceptRescueQueueEntry(acceptedByFour.UserId, pendingFourEntry.queueEntryId, 40.5)
assertEqual(acceptFallbackRejected.accepted, false, "fallback rejection propagated")
assertEqual(acceptFallbackRejected.reason, "queue_backpressure", "fallback rejection reason propagated")
local diagnosticsAfterFallbackRejected = queryApi.GetAdmissionIngressDiagnostics()
assertEqual(diagnosticsAfterFallbackRejected.totalAttempts, 5, "total attempts include fallback rejection")
assertEqual(diagnosticsAfterFallbackRejected.fallbackAttempts, 2, "fallback attempts include rejection")
assertEqual(diagnosticsAfterFallbackRejected.fallbackSucceeded, 1, "fallback success count preserved")
assertEqual(diagnosticsAfterFallbackRejected.fallbackFailed, 1, "fallback failure tracked")
assertEqual(diagnosticsAfterFallbackRejected.lastPath, "fallback", "fallback rejection path tracked")
assertEqual(diagnosticsAfterFallbackRejected.lastReason, "queue_backpressure", "fallback rejection reason tracked")
assertEqual(
	diagnosticsAfterFallbackRejected.lastFallbackReason,
	"queue_backpressure",
	"fallback rejection last fallback reason tracked"
)

print("rescue_contract_admission_ingress_runtime_entrypoint: all checks passed")
