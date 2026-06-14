--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local CustodyTransferConfig = require(Config:WaitForChild("CustodyTransferConfig"))

local localPlayer = Players.LocalPlayer
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local requestRemote = remotesFolder:WaitForChild(CustodyTransferConfig.Remotes.Request) :: RemoteEvent
local confirmRemote = remotesFolder:WaitForChild(CustodyTransferConfig.Remotes.Confirm) :: RemoteEvent
local cancelRemote = remotesFolder:WaitForChild(CustodyTransferConfig.Remotes.Cancel) :: RemoteEvent
local notifyRemote = remotesFolder:WaitForChild(CustodyTransferConfig.Remotes.Notify) :: RemoteEvent

local function debugLog(message: string)
	print(string.format("[CustodyTransferClient] %s", message))
end

local function requestCustodyTransfer(targetUserId: number, incomingCustodianUserId: number)
	if localPlayer:GetAttribute("Role") ~= "Giant" then
		return
	end

	requestRemote:FireServer({
		targetUserId = targetUserId,
		incomingCustodianUserId = incomingCustodianUserId,
	})
	debugLog(string.format("Requested transfer target=%d incoming=%d", targetUserId, incomingCustodianUserId))
end

local function confirmCustodyTransfer(requestId: string)
	if localPlayer:GetAttribute("Role") ~= "Giant" then
		return
	end

	confirmRemote:FireServer({
		requestId = requestId,
	})
	debugLog(string.format("Confirmed transfer request=%s", requestId))
end

local function cancelCustodyTransfer(requestId: string)
	cancelRemote:FireServer({
		requestId = requestId,
	})
	debugLog(string.format("Cancelled transfer request=%s", requestId))
end

requestRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	debugLog(
		string.format("Request response accepted=%s reason=%s", tostring(payload.accepted), tostring(payload.reason))
	)
end)

confirmRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	debugLog(
		string.format("Confirm response accepted=%s reason=%s", tostring(payload.accepted), tostring(payload.reason))
	)
end)

cancelRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	debugLog(
		string.format("Cancel response accepted=%s reason=%s", tostring(payload.accepted), tostring(payload.reason))
	)
end)

notifyRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	debugLog(
		string.format(
			"Transfer notice target=%s outgoing=%s incoming=%s remaining=%s",
			tostring(payload.targetUserId),
			tostring(payload.outgoingCustodianUserId),
			tostring(payload.incomingCustodianUserId),
			tostring(if type(payload.terms) == "table" then payload.terms.remainingSeconds else nil)
		)
	)
end)

_G._CustodyTransferClient_QueryAPI = {
	RequestCustodyTransfer = requestCustodyTransfer,
	ConfirmCustodyTransfer = confirmCustodyTransfer,
	CancelCustodyTransfer = cancelCustodyTransfer,
}

debugLog("Custody transfer client ready")
