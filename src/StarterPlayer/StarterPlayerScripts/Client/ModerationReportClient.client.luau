--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local ModerationReportConfig = require(Config:WaitForChild("ModerationReportConfig"))

local localPlayer = Players.LocalPlayer
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local exportRemote = remotesFolder:WaitForChild(ModerationReportConfig.Remotes.RequestExport) :: RemoteEvent

local function debugLog(message: string)
	print(string.format("[ModerationReportClient] %s", message))
end

local function requestReportExport(surfaceKind: string?)
	exportRemote:FireServer({
		surfaceKind = surfaceKind,
	})
	debugLog(string.format("Requested moderation report export surfaceKind=%s", tostring(surfaceKind)))
end

exportRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	debugLog(
		string.format(
			"Export response accepted=%s reason=%s reportId=%s",
			tostring(payload.accepted),
			tostring(payload.reason),
			if type(payload.summary) == "table" then tostring(payload.summary.reportId) else "nil"
		)
	)
end)

localPlayer:GetAttributeChangedSignal(ModerationReportConfig.StateAttributes.AffordanceAvailable):Connect(function()
	local available = localPlayer:GetAttribute(ModerationReportConfig.StateAttributes.AffordanceAvailable) == true
	if available then
		debugLog("Report affordance available")
	end
end)

_G._ModerationReportClient = {
	RequestExport = requestReportExport,
}
