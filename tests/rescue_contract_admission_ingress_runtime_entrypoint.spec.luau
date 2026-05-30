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

targetOne:SetAttribute("DownedIsDowned", true)
targetOne:SetAttribute("GiantRealmOwnerUserId", 9011)
targetTwo:SetAttribute("DownedIsDowned", true)
targetTwo:SetAttribute("GiantRealmOwnerUserId", 9012)

local playersList: { any } = { rescuerOne, targetOne, acceptedByOne, rescuerTwo, targetTwo, acceptedByTwo }
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
globalEnv._RescueAdmissionService_QueryAPI = {
	RequestRescueContractAdmission = function(payload: any): any
		table.insert(ingressPayloads, payload)
		return { accepted = true, reason = "accepted" }
	end,
}

require("../src/ServerScriptService/Services/RescueContractService.server")
local queryApi = globalEnv._RescueContractService_QueryAPI
queryApi.ResetForTests()

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
assertEqual(diagnosticsAfterPrimary.primaryAttempts, 1, "primary attempts tracked")
assertEqual(diagnosticsAfterPrimary.primarySucceeded, 1, "primary success tracked")
assertEqual(diagnosticsAfterPrimary.primaryFailed, 0, "primary failures baseline")
assertEqual(diagnosticsAfterPrimary.fallbackAttempts, 0, "fallback attempts baseline")
assertEqual(diagnosticsAfterPrimary.lastPath, "primary", "primary path tracked")
assertEqual(diagnosticsAfterPrimary.lastReason, "accepted", "primary reason tracked")

globalEnv._RescueAdmissionService_QueryAPI = {
	RequestRescueContractAdmission = function(_payload: any): any
		error("boom")
	end,
}

local requestTwo = queryApi.RequestRescueContract(rescuerTwo.UserId, targetTwo.UserId, 20)
assertEqual(requestTwo.accepted, true, "request two accepted")
local pendingTwo = queryApi.GetRescueQueueEntries(20)
assertEqual(#pendingTwo, 1, "one pending queue entry for second request")

local acceptTwo = queryApi.AcceptRescueQueueEntry(acceptedByTwo.UserId, pendingTwo[1].queueEntryId, 20.5)
assertEqual(acceptTwo.accepted, false, "ingress exception rejected")
assertEqual(acceptTwo.reason, "admission_enqueue_failed", "ingress exception reason")
local diagnosticsAfterPrimaryFailure = queryApi.GetAdmissionIngressDiagnostics()
assertEqual(diagnosticsAfterPrimaryFailure.primaryAttempts, 2, "primary attempts include failure")
assertEqual(diagnosticsAfterPrimaryFailure.primarySucceeded, 1, "primary success count preserved")
assertEqual(diagnosticsAfterPrimaryFailure.primaryFailed, 1, "primary failure tracked")
assertEqual(diagnosticsAfterPrimaryFailure.fallbackAttempts, 0, "fallback still unused")
assertEqual(diagnosticsAfterPrimaryFailure.lastPath, "primary", "primary failure path tracked")
assertEqual(diagnosticsAfterPrimaryFailure.lastReason, "admission_enqueue_failed", "primary failure reason tracked")

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
assertEqual(diagnosticsAfterFallback.fallbackAttempts, 1, "fallback attempt tracked")
assertEqual(diagnosticsAfterFallback.fallbackSucceeded, 1, "fallback success tracked")
assertEqual(diagnosticsAfterFallback.fallbackFailed, 0, "fallback failure baseline")
assertEqual(diagnosticsAfterFallback.lastPath, "fallback", "fallback path tracked")
assertEqual(diagnosticsAfterFallback.lastReason, "accepted", "fallback reason tracked")

print("rescue_contract_admission_ingress_runtime_entrypoint: all checks passed")
