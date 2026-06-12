--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

local REMOTES_FOLDER_NAME = "Remotes"
local DEBUG_REQUEST_REMOTE_NAME = "PhysicsOwnershipDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "PhysicsOwnershipDebugStateResponse"
local TIER_ATTRIBUTE = "GameplayPhysicsOwnershipTier"
local ASSEMBLY_ATTRIBUTE = "GameplayPhysicsOwnershipAssembly"

local localPlayer = Players.LocalPlayer
if localPlayer == nil then
	return
end

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local debugRequestRemote = remotesFolder:WaitForChild(DEBUG_REQUEST_REMOTE_NAME) :: RemoteEvent
local debugResponseRemote = remotesFolder:WaitForChild(DEBUG_RESPONSE_REMOTE_NAME) :: RemoteEvent

local function debugLog(message: string)
	print(string.format("[PhysicsOwnershipDebugClient] %s", message))
end

local function summarizePlayerSnapshot(snapshot: any): string
	if type(snapshot) ~= "table" then
		return "invalid_snapshot"
	end
	return string.format(
		"userId=%s assembly=%s tier=%s requiresServer=%s",
		tostring(snapshot.userId),
		tostring(snapshot.characterAssembly),
		tostring(snapshot.characterTier),
		tostring(snapshot.requiresServerOwnership)
	)
end

debugResponseRemote.OnClientEvent:Connect(function(payload: any)
	if type(payload) ~= "table" then
		debugLog("Received invalid debug payload")
		return
	end

	if type(payload.player) == "table" then
		debugLog(string.format("Player snapshot: %s", summarizePlayerSnapshot(payload.player)))
	elseif type(payload.players) == "table" then
		for _, playerSnapshot in payload.players do
			debugLog(string.format("Player snapshot: %s", summarizePlayerSnapshot(playerSnapshot)))
		end
	end

	if type(payload.diagnostics) == "table" then
		debugLog(
			string.format(
				"Diagnostics partsEnforced=%s charactersRefreshed=%s worldPartsAssigned=%s lastReason=%s",
				tostring(payload.diagnostics.partsEnforced),
				tostring(payload.diagnostics.charactersRefreshed),
				tostring(payload.diagnostics.worldPartsAssigned),
				tostring(payload.diagnostics.lastReason)
			)
		)
	end
end)

local function logLocalCharacterParts()
	local character = localPlayer.Character
	if character == nil then
		return
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			local tier = descendant:GetAttribute(TIER_ATTRIBUTE)
			local assemblyKind = descendant:GetAttribute(ASSEMBLY_ATTRIBUTE)
			if tier ~= nil or assemblyKind ~= nil then
				debugLog(
					string.format(
						"Part %s tier=%s assembly=%s networkOwner=%s",
						descendant.Name,
						tostring(tier),
						tostring(assemblyKind),
						tostring(descendant:GetNetworkOwner())
					)
				)
			end
		end
	end
end

localPlayer.CharacterAdded:Connect(function()
	task.defer(function()
		debugRequestRemote:FireServer(nil)
		logLocalCharacterParts()
	end)
end)

task.defer(function()
	debugRequestRemote:FireServer(nil)
	logLocalCharacterParts()
end)

debugLog("Studio physics ownership debug client ready")
