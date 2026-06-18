--!nocheck

local Players = game:GetService("Players")

local RoleConfig = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RoleConfig")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/Config/RoleConfig")

local GiantRealmLoadService = if script ~= nil and script.Parent ~= nil
	then require(script.Parent.GiantRealmLoadService)
	else (require :: any)("./GiantRealmLoadService")

local ROLE_ATTRIBUTE = "Role"

local function releaseGiantRealmForPlayer(player: Player, reason: string)
	if player:GetAttribute(ROLE_ATTRIBUTE) ~= RoleConfig.Roles.Giant then
		return
	end

	if not GiantRealmLoadService.IsRealmLoaded(player.UserId) then
		return
	end

	local releaseResult = GiantRealmLoadService.SaveAndRelease(player.UserId, reason)
	if type(releaseResult) ~= "table" or releaseResult.accepted ~= true then
		warn(
			string.format(
				"[GiantRealmLoadService.server] release failed userId=%d reason=%s cleanupReason=%s",
				player.UserId,
				if type(releaseResult) == "table" then tostring(releaseResult.reason) else "release_unavailable",
				reason
			)
		)
	end
end

Players.PlayerRemoving:Connect(function(player)
	releaseGiantRealmForPlayer(player, "player_removing")
end)

if game ~= nil and type((game :: any).BindToClose) == "function" then
	(game :: any):BindToClose(function()
		GiantRealmLoadService.ReleaseAllLoadedRealms("bind_to_close")
	end)
end
