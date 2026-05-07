local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ROLE_LOCKED_ATTRIBUTE = "RoleLocked"
local SELECTED_ROLE_ATTRIBUTE = "SelectedRole"

local localPlayer = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local remote = remotes:WaitForChild("UpgradeBoardSelectRequest")

local function isRoleSelected(): boolean
	local selectedRole = localPlayer:GetAttribute(SELECTED_ROLE_ATTRIBUTE)
	return localPlayer:GetAttribute(ROLE_LOCKED_ATTRIBUTE) == true
		and type(selectedRole) == "string"
		and selectedRole ~= ""
end

warn("LOCAL TEST WAITING FOR ROLE SELECTION")
while not isRoleSelected() do
	task.wait(0.1)
end

warn("LOCAL TEST START")

-- Wait for character to spawn and be alive before firing requests.
local function isCharacterAlive(): boolean
	local character = localPlayer.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

warn("LOCAL TEST WAITING FOR ALIVE CHARACTER")
while not isCharacterAlive() do
	task.wait(0.1)
end
task.wait(1)
warn("LOCAL TEST CHARACTER READY")

remote:FireServer({
	boardId = "GiantUpgradeBoard_A",
	upgradeId = "IronStride",
})
warn("LOCAL TEST SENT IronStride")

task.wait(0.25)

remote:FireServer({
	boardId = "GiantUpgradeBoard_A",
	upgradeId = "FakeUpgradeId",
})
warn("LOCAL TEST SENT FakeUpgradeId")

task.wait(0.25)

remote:FireServer({
	boardId = "GiantUpgradeBoard_A",
	upgradeId = "PowerCore",
})
warn("LOCAL TEST SENT PowerCore")
