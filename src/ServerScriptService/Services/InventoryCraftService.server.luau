--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local InventoryCraft = Shared:WaitForChild("InventoryCraft")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local InventoryCraftConfig = require(Config:WaitForChild("InventoryCraftConfig"))
local InventoryCraftState = if script ~= nil and script.Parent ~= nil
	then require(InventoryCraft:WaitForChild("InventoryCraftState"))
	else require("../../ReplicatedStorage/Shared/InventoryCraft/InventoryCraftState")

local REMOTES_FOLDER_NAME = "Remotes"
local CRAFT_REQUEST_REMOTE_NAME = "InventoryCraftRequest"
local DEBUG_REQUEST_REMOTE_NAME = "InventoryCraftDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "InventoryCraftDebugStateResponse"

local CANONICAL_ITEM_CATALOG = InventoryCraftConfig.DEFAULT_ITEM_CATALOG
local CANONICAL_RECIPE_CATALOG = InventoryCraftConfig.DEFAULT_RECIPE_CATALOG

type SessionState = InventoryCraftState.State

local sessionByUserId: { [number]: SessionState? } = {}

local function debugLog(message: string)
	print(string.format("[InventoryCraftService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[InventoryCraftService] %s", message))
end

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	debugLog("Created ReplicatedStorage.Remotes folder")
	return folder
end

local function ensureRemoteEvent(parentFolder: Folder, remoteName: string): RemoteEvent
	local existing = parentFolder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = parentFolder
	debugLog(string.format("Created ReplicatedStorage.Remotes.%s", remoteName))
	return remote
end

local function isTinyfolk(player: Player): boolean
	return player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk
end

local function getOrCreateSession(userId: number): SessionState
	local existing = sessionByUserId[userId]
	if existing ~= nil then
		return existing
	end

	local created = InventoryCraftState.NewState(InventoryCraftConfig.TEST_STARTING_ITEMS)
	sessionByUserId[userId] = created
	debugLog(string.format("Initialized inventory session userId=%d", userId))
	return created
end

local function setSession(userId: number, state: SessionState)
	sessionByUserId[userId] = state
end

local function clearSession(userId: number, reason: string)
	sessionByUserId[userId] = nil
	debugLog(string.format("Cleared inventory session userId=%d reason=%s", userId, reason))
end

local function applyDebugAttributes(player: Player, snapshot: any)
	local attributes = InventoryCraftConfig.Attributes
	player:SetAttribute(attributes.ItemCount, #snapshot.items)
	player:SetAttribute(attributes.CraftedTotal, snapshot.craftedTotal)
	player:SetAttribute(
		attributes.CraftableRecipeCount,
		if type(snapshot.craftableRecipeIds) == "table" then #snapshot.craftableRecipeIds else 0
	)
	player:SetAttribute(attributes.LastCraftRecipeId, snapshot.lastCraftRecipeId)
	player:SetAttribute(attributes.LastCraftAt, snapshot.lastCraftAt)
	player:SetAttribute(attributes.LastReason, snapshot.lastReason)
end

local function snapshotForPlayer(player: Player): any
	local state = getOrCreateSession(player.UserId)
	local snapshot = InventoryCraftState.GetSnapshot(state, CANONICAL_ITEM_CATALOG)
	applyDebugAttributes(player, snapshot)
	return {
		userId = player.UserId,
		role = player:GetAttribute("Role"),
		itemCounts = snapshot.itemCounts,
		items = snapshot.items,
		craftedTotal = snapshot.craftedTotal,
		craftableRecipeIds = snapshot.craftableRecipeIds,
		lastCraftRecipeId = snapshot.lastCraftRecipeId,
		lastCraftAt = snapshot.lastCraftAt,
		lastReason = snapshot.lastReason,
	}
end

local function listCraftableRecipesForPlayer(player: Player): any
	if not isTinyfolk(player) then
		return {
			accepted = false,
			reason = "tinyfolk_role_required",
			recipes = {},
		}
	end

	local state = getOrCreateSession(player.UserId)
	local recipes = InventoryCraftState.ListCraftableRecipes(
		state,
		RoleConfig.Roles.Tinyfolk,
		CANONICAL_ITEM_CATALOG,
		CANONICAL_RECIPE_CATALOG
	)
	return {
		accepted = true,
		reason = "accepted",
		recipes = recipes,
	}
end

local function consumeItemsForPlayer(player: Player, consumptions: any): any
	if not isTinyfolk(player) then
		return {
			accepted = false,
			reason = "tinyfolk_role_required",
			snapshot = snapshotForPlayer(player),
		}
	end

	if type(consumptions) ~= "table" then
		return {
			accepted = false,
			reason = "consumptions_invalid",
			snapshot = snapshotForPlayer(player),
		}
	end

	local currentState = getOrCreateSession(player.UserId)
	local transition = InventoryCraftState.ConsumeItems(currentState, consumptions, CANONICAL_ITEM_CATALOG)
	if not transition.accepted then
		local rejectedState = transition.state
		rejectedState.lastReason = transition.reason
		setSession(player.UserId, rejectedState)
		local snapshot = InventoryCraftState.GetSnapshot(rejectedState, CANONICAL_ITEM_CATALOG)
		applyDebugAttributes(player, snapshot)
		return {
			accepted = false,
			reason = transition.reason,
			snapshot = {
				userId = player.UserId,
				role = player:GetAttribute("Role"),
				itemCounts = snapshot.itemCounts,
				items = snapshot.items,
				craftedTotal = snapshot.craftedTotal,
				craftableRecipeIds = snapshot.craftableRecipeIds,
				lastCraftRecipeId = snapshot.lastCraftRecipeId,
				lastCraftAt = snapshot.lastCraftAt,
				lastReason = snapshot.lastReason,
			},
		}
	end

	setSession(player.UserId, transition.state)
	local snapshot = InventoryCraftState.GetSnapshot(transition.state, CANONICAL_ITEM_CATALOG)
	applyDebugAttributes(player, snapshot)
	debugLog(
		string.format(
			"Consume accepted userId=%d itemCount=%d craftedTotal=%d",
			player.UserId,
			#snapshot.items,
			snapshot.craftedTotal
		)
	)
	return {
		accepted = true,
		reason = "accepted",
		snapshot = {
			userId = player.UserId,
			role = player:GetAttribute("Role"),
			itemCounts = snapshot.itemCounts,
			items = snapshot.items,
			craftedTotal = snapshot.craftedTotal,
			craftableRecipeIds = snapshot.craftableRecipeIds,
			lastCraftRecipeId = snapshot.lastCraftRecipeId,
			lastCraftAt = snapshot.lastCraftAt,
			lastReason = snapshot.lastReason,
		},
	}
end

local function grantItemsForPlayer(player: Player, additions: any, reason: string?): any
	if not isTinyfolk(player) then
		return {
			accepted = false,
			reason = "tinyfolk_role_required",
			snapshot = snapshotForPlayer(player),
		}
	end

	if type(additions) ~= "table" or next(additions) == nil then
		return {
			accepted = false,
			reason = "additions_invalid",
			snapshot = snapshotForPlayer(player),
		}
	end

	local currentState = getOrCreateSession(player.UserId)
	local transition = InventoryCraftState.AddItems(currentState, additions, CANONICAL_ITEM_CATALOG)
	if not transition.accepted then
		local rejectedState = transition.state
		rejectedState.lastReason = transition.reason
		setSession(player.UserId, rejectedState)
		local snapshot = InventoryCraftState.GetSnapshot(rejectedState, CANONICAL_ITEM_CATALOG)
		applyDebugAttributes(player, snapshot)
		return {
			accepted = false,
			reason = transition.reason,
			snapshot = {
				userId = player.UserId,
				role = player:GetAttribute("Role"),
				itemCounts = snapshot.itemCounts,
				items = snapshot.items,
				craftedTotal = snapshot.craftedTotal,
				craftableRecipeIds = snapshot.craftableRecipeIds,
				lastCraftRecipeId = snapshot.lastCraftRecipeId,
				lastCraftAt = snapshot.lastCraftAt,
				lastReason = snapshot.lastReason,
			},
		}
	end

	local nextState = transition.state
	if type(reason) == "string" and reason ~= "" then
		nextState.lastReason = reason
	end
	setSession(player.UserId, nextState)
	local snapshot = InventoryCraftState.GetSnapshot(nextState, CANONICAL_ITEM_CATALOG)
	applyDebugAttributes(player, snapshot)
	debugLog(
		string.format(
			"Grant accepted userId=%d itemCount=%d reason=%s",
			player.UserId,
			#snapshot.items,
			tostring(reason)
		)
	)
	return {
		accepted = true,
		reason = "accepted",
		snapshot = {
			userId = player.UserId,
			role = player:GetAttribute("Role"),
			itemCounts = snapshot.itemCounts,
			items = snapshot.items,
			craftedTotal = snapshot.craftedTotal,
			craftableRecipeIds = snapshot.craftableRecipeIds,
			lastCraftRecipeId = snapshot.lastCraftRecipeId,
			lastCraftAt = snapshot.lastCraftAt,
			lastReason = snapshot.lastReason,
		},
	}
end

local function craftForPlayer(player: Player, recipeId: any, catalogOverride: any?, recipeCatalogOverride: any?): any
	if not isTinyfolk(player) then
		return {
			accepted = false,
			reason = "tinyfolk_role_required",
			snapshot = snapshotForPlayer(player),
		}
	end

	local itemCatalog = if catalogOverride ~= nil then catalogOverride else CANONICAL_ITEM_CATALOG
	local recipeCatalog = if recipeCatalogOverride ~= nil then recipeCatalogOverride else CANONICAL_RECIPE_CATALOG

	local currentState = getOrCreateSession(player.UserId)
	local transition = InventoryCraftState.ResolveCraft(currentState, {
		recipeId = recipeId,
		requesterRole = RoleConfig.Roles.Tinyfolk,
		now = os.clock(),
	}, itemCatalog, recipeCatalog)

	if not transition.accepted then
		local rejectedState = transition.state
		rejectedState.lastReason = transition.reason
		setSession(player.UserId, rejectedState)
		local snapshot = InventoryCraftState.GetSnapshot(rejectedState, itemCatalog)
		applyDebugAttributes(player, snapshot)
		return {
			accepted = false,
			reason = transition.reason,
			snapshot = {
				userId = player.UserId,
				role = player:GetAttribute("Role"),
				itemCounts = snapshot.itemCounts,
				items = snapshot.items,
				craftedTotal = snapshot.craftedTotal,
				craftableRecipeIds = snapshot.craftableRecipeIds,
				lastCraftRecipeId = snapshot.lastCraftRecipeId,
				lastCraftAt = snapshot.lastCraftAt,
				lastReason = snapshot.lastReason,
			},
		}
	end

	setSession(player.UserId, transition.state)
	local snapshot = InventoryCraftState.GetSnapshot(transition.state, itemCatalog)
	applyDebugAttributes(player, snapshot)
	debugLog(
		string.format(
			"Craft accepted userId=%d recipeId=%s craftedTotal=%d itemCount=%d",
			player.UserId,
			tostring(recipeId),
			snapshot.craftedTotal,
			#snapshot.items
		)
	)
	return {
		accepted = true,
		reason = "accepted",
		snapshot = {
			userId = player.UserId,
			role = player:GetAttribute("Role"),
			itemCounts = snapshot.itemCounts,
			items = snapshot.items,
			craftedTotal = snapshot.craftedTotal,
			craftableRecipeIds = snapshot.craftableRecipeIds,
			lastCraftRecipeId = snapshot.lastCraftRecipeId,
			lastCraftAt = snapshot.lastCraftAt,
			lastReason = snapshot.lastReason,
		},
	}
end

local function rejectCraft(player: Player, reason: string)
	debugWarn(string.format("Rejected InventoryCraftRequest userId=%d reason=%s", player.UserId, reason))
end

local function rejectDebug(player: Player, reason: string)
	debugWarn(string.format("Rejected InventoryCraftDebugStateRequest userId=%d reason=%s", player.UserId, reason))
end

local remotesFolder = ensureRemotesFolder()
local craftRequestRemote = ensureRemoteEvent(remotesFolder, CRAFT_REQUEST_REMOTE_NAME)
local debugRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
local debugResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)

craftRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if type(payload) ~= "table" then
		rejectCraft(player, "malformed_payload")
		return
	end

	local recipeId = (payload :: any).recipeId
	if type(recipeId) ~= "string" or recipeId == "" then
		rejectCraft(player, "recipe_id_invalid")
		return
	end

	local result = craftForPlayer(player, recipeId, CANONICAL_ITEM_CATALOG, CANONICAL_RECIPE_CATALOG)
	if not result.accepted then
		rejectCraft(player, result.reason)
	end
end)

debugRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if payload ~= nil then
		rejectDebug(player, "malformed_payload")
		return
	end

	local snapshot = snapshotForPlayer(player)
	debugResponseRemote:FireClient(player, snapshot)
	debugLog(
		string.format(
			"Sent inventory craft debug state userId=%d itemCount=%d craftedTotal=%d",
			player.UserId,
			#snapshot.items,
			snapshot.craftedTotal
		)
	)
end)

local function setupPlayer(player: Player)
	if isTinyfolk(player) then
		snapshotForPlayer(player)
	end

	player:GetAttributeChangedSignal("Role"):Connect(function()
		if player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk then
			snapshotForPlayer(player)
			return
		end

		clearSession(player.UserId, "role_change")
		applyDebugAttributes(player, {
			items = {},
			craftedTotal = 0,
			craftableRecipeIds = {},
			lastCraftRecipeId = nil,
			lastCraftAt = nil,
			lastReason = "cleared_role_change",
		})
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	clearSession(player.UserId, "player_removing")
end)

local InventoryCraftService: any = {}

-- selene: allow(global_usage)
_G._InventoryCraftService_QueryAPI = {
	Craft = function(player: Player, recipeId: any, _itemCatalog: any?, _recipeCatalog: any?): any
		return craftForPlayer(player, recipeId, CANONICAL_ITEM_CATALOG, CANONICAL_RECIPE_CATALOG)
	end,
	ConsumeItems = function(player: Player, consumptions: any): any
		return consumeItemsForPlayer(player, consumptions)
	end,
	GetSnapshot = function(player: Player): any
		return snapshotForPlayer(player)
	end,
	ListCraftableRecipes = function(player: Player): any
		return listCraftableRecipesForPlayer(player)
	end,
	GrantItems = function(player: Player, additions: any, reason: string?): any
		return grantItemsForPlayer(player, additions, reason)
	end,
}

InventoryCraftService.TestHarness = {
	CraftWithCatalogOverride = function(
		player: Player,
		recipeId: any,
		itemCatalogOverride: any?,
		recipeCatalogOverride: any?
	): any
		return craftForPlayer(player, recipeId, itemCatalogOverride, recipeCatalogOverride)
	end,
	ResetSessionForTests = function(userId: number, bootstrapItems: any?)
		sessionByUserId[userId] = InventoryCraftState.NewState(bootstrapItems)
	end,
}

debugLog("InventoryCraftService initialized")

return InventoryCraftService
