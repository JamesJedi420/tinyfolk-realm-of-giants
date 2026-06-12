--!nocheck

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CollisionGroupService = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("CollisionGroupService"))
	else (require :: any)("./CollisionGroupService")

local MAP_ROOT_NAME = "Map"
local ROLE_ATTRIBUTE = "Role"
local CAPTURE_ACTIVE_ATTRIBUTE = "CaptureActive"
local CARRIED_STATE_ATTRIBUTE = "CarriedState"

local serviceStarted = false

local function debugLog(message: string)
	print(string.format("[CollisionGroupService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[CollisionGroupService] %s", message))
end

local function bindPlayerRefresh(player: any)
	local function refresh()
		CollisionGroupService.RefreshPlayerCharacter(player)
	end

	player.CharacterAdded:Connect(refresh)
	player:GetAttributeChangedSignal(ROLE_ATTRIBUTE):Connect(refresh)
	player:GetAttributeChangedSignal(CAPTURE_ACTIVE_ATTRIBUTE):Connect(refresh)
	player:GetAttributeChangedSignal(CARRIED_STATE_ATTRIBUTE):Connect(refresh)

	if player.Character ~= nil then
		refresh()
	end
end

local function assignAuthoredWorldParts()
	local mapRoot = Workspace:FindFirstChild(MAP_ROOT_NAME)
	if mapRoot == nil then
		debugWarn("Workspace.Map missing; skipping world collision group assignment")
		return
	end

	local assignedCount = CollisionGroupService.AssignWorldPartsUnderRoot(mapRoot)
	debugLog(string.format("Assigned gameplay collision groups to %d map parts", assignedCount))
end

local function startService(): (boolean, string?)
	if serviceStarted then
		return true, nil
	end

	local registered, registerReason = CollisionGroupService.RegisterMatrix(PhysicsService)
	if not registered then
		debugWarn(string.format("Matrix registration failed reason=%s", tostring(registerReason)))
		return false, registerReason
	end

	assignAuthoredWorldParts()

	Players.PlayerAdded:Connect(bindPlayerRefresh)

	for _, player in Players:GetPlayers() do
		bindPlayerRefresh(player)
	end

	serviceStarted = true
	debugLog("Collision group service started")
	return true, nil
end

local startOk, startReason = startService()
if not startOk then
	debugWarn(string.format("CollisionGroupService bootstrap deferred reason=%s", tostring(startReason)))
end

local globalEnv: any = getfenv()
globalEnv._CollisionGroupService_QueryAPI = {
	RefreshPlayerCharacter = function(player: any)
		CollisionGroupService.RefreshPlayerCharacter(player)
	end,
	ResolveCharacterGroupForPlayer = function(player: any): string
		return CollisionGroupService.ResolveCharacterGroupForPlayer(player)
	end,
	AssignWorldPartsUnderRoot = function(root: any): number
		return CollisionGroupService.AssignWorldPartsUnderRoot(root)
	end,
	GetRegistrationDiagnostics = function(): any
		return CollisionGroupService.GetRegistrationDiagnostics()
	end,
	GetRelation = function(groupA: string, groupB: string): string
		return CollisionGroupService.GetRelation(groupA, groupB)
	end,
	IsMatrixRegistered = function(): boolean
		return CollisionGroupService.IsMatrixRegistered()
	end,
}
