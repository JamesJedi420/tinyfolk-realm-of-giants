--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local RansomBoardConfig = require(Config:WaitForChild("RansomBoardConfig"))

local localPlayer = Players.LocalPlayer
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local postRemote = remotesFolder:WaitForChild(RansomBoardConfig.Remotes.Post) :: RemoteEvent
local settleRemote = remotesFolder:WaitForChild(RansomBoardConfig.Remotes.Settle) :: RemoteEvent
local cancelRemote = remotesFolder:WaitForChild(RansomBoardConfig.Remotes.Cancel) :: RemoteEvent
local notifyRemote = remotesFolder:WaitForChild(RansomBoardConfig.Remotes.Notify) :: RemoteEvent

local function debugLog(message: string)
	print(string.format("[RansomBoardClient] %s", message))
end

local function postRansomOffer(targetUserId: number, settlementKind: string?, foodCost: number?)
	if localPlayer:GetAttribute("Role") ~= "Giant" then
		return
	end

	postRemote:FireServer({
		targetUserId = targetUserId,
		settlementKind = settlementKind,
		foodCost = foodCost,
	})
	debugLog(
		string.format(
			"Posted ransom target=%d settlementKind=%s foodCost=%s",
			targetUserId,
			tostring(settlementKind),
			tostring(foodCost)
		)
	)
end

local function settleRansomOffer(offerId: string)
	if localPlayer:GetAttribute("Role") ~= "Tinyfolk" then
		return
	end

	settleRemote:FireServer({
		offerId = offerId,
	})
	debugLog(string.format("Settled ransom offer=%s", offerId))
end

local function cancelRansomOffer(offerId: string)
	cancelRemote:FireServer({
		offerId = offerId,
	})
	debugLog(string.format("Cancelled ransom offer=%s", offerId))
end

postRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	debugLog(string.format("Post response accepted=%s reason=%s", tostring(payload.accepted), tostring(payload.reason)))
end)

settleRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	debugLog(
		string.format("Settle response accepted=%s reason=%s", tostring(payload.accepted), tostring(payload.reason))
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
	debugLog(string.format("Notify eventKind=%s offerId=%s", tostring(payload.eventKind), tostring(payload.offerId)))
end)

return {
	PostRansomOffer = postRansomOffer,
	SettleRansomOffer = settleRansomOffer,
	CancelRansomOffer = cancelRansomOffer,
}
