--!nocheck

local globalEnv: any = getfenv()
local _game = rawget(globalEnv, "game")
if _game == nil and type(_G) == "table" then
	_game = rawget(_G, "game")
end
if _game == nil then
	_game = game
end
local Players = _game:GetService("Players")

local StealthShrinkState
local testModules = rawget(globalEnv, "_TinyfolkStealth_TestModules")
if testModules == nil and type(_G) == "table" then
	testModules = rawget(_G, "_TinyfolkStealth_TestModules")
end
if testModules ~= nil then
	StealthShrinkState = testModules.StealthShrinkState
else
	StealthShrinkState = require(_game:GetService("ReplicatedStorage").Shared.TinyfolkStealth.StealthShrinkState)
end

local runtimeConfig: any = nil
local stateByUserId: { [number]: any } = {}
local diagnostics: any = {
	activationAttempts = 0,
	activationSucceeded = 0,
	activationFailed = 0,
	cancelAttempts = 0,
	cancelSucceeded = 0,
	cancelFailed = 0,
	tickExpired = 0,
	invalidStateCancelled = 0,
	invalidActionCancelled = 0,
	lastReason = "not_started",
	lastUserId = nil,
	lastActionName = nil,
}

local DEFAULT_STEALTH_DURATION_SECONDS = 15
local DEFAULT_BLOCKED_ACTIONS = {
	objective_work = true,
	final_exit_open = true,
	rescue_contract = true,
	heavy_tool_use = true,
}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value > 0 and value % 1 == 0 and value == value
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local output = {}
	for key, child in pairs(value) do
		output[key] = cloneTable(child)
	end
	return output
end

local function resolveNow(): number
	local configAny = runtimeConfig
	if type(configAny) == "table" and type(configAny.now) == "function" then
		local nowValue = configAny.now()
		if isFiniteNumber(nowValue) then
			return nowValue
		end
	end
	return os.clock()
end

local function resolveRoleServiceApi(): any?
	local configAny = runtimeConfig
	if type(configAny) == "table" and type(configAny.roleServiceApi) == "table" then
		return configAny.roleServiceApi
	end

	local fromEnv = rawget(globalEnv, "_RoleService_QueryAPI")
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, "_RoleService_QueryAPI")
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function resolveGrabServiceApi(): any?
	local configAny = runtimeConfig
	if type(configAny) == "table" and type(configAny.grabServiceApi) == "table" then
		return configAny.grabServiceApi
	end

	local fromEnv = rawget(globalEnv, "_GrabService_QueryAPI")
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, "_GrabService_QueryAPI")
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function resolveHidingServiceApi(): any?
	local configAny = runtimeConfig
	if type(configAny) == "table" and type(configAny.hidingServiceApi) == "table" then
		return configAny.hidingServiceApi
	end

	local fromEnv = rawget(globalEnv, "_TinyfolkHiding_QueryAPI")
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, "_TinyfolkHiding_QueryAPI")
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function resolveStatusServiceApi(): any?
	local configAny = runtimeConfig
	if type(configAny) == "table" and type(configAny.statusServiceApi) == "table" then
		return configAny.statusServiceApi
	end

	local fromEnv = rawget(globalEnv, "_TinyfolkStatusService_QueryAPI")
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, "_TinyfolkStatusService_QueryAPI")
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function isPlayerHiding(userId: number): boolean
	local hidingServiceApi = resolveHidingServiceApi()
	if type(hidingServiceApi) ~= "table" or type(hidingServiceApi.IsPlayerHiding) ~= "function" then
		return false
	end

	local ok, hidden = pcall(function()
		return hidingServiceApi.IsPlayerHiding(userId)
	end)
	return ok and hidden == true
end

local function isStatusStealthAllowed(userId: number, at: number): (boolean, string?)
	local configAny = runtimeConfig
	if type(configAny) == "table" and type(configAny.statusResolver) == "function" then
		local ok, allowed, reason = pcall(function()
			return configAny.statusResolver(userId, at)
		end)
		if ok and allowed ~= true then
			if isNonEmptyString(reason) then
				return false, reason
			end
			return false, "status_forbidden"
		end
	end

	local statusServiceApi = resolveStatusServiceApi()
	if type(statusServiceApi) == "table" and type(statusServiceApi.IsStealthShrinkAllowed) == "function" then
		local ok, allowed, reason = pcall(function()
			return statusServiceApi.IsStealthShrinkAllowed(userId, at)
		end)
		if ok and allowed ~= true then
			if isNonEmptyString(reason) then
				return false, reason
			end
			return false, "status_forbidden"
		end
	end

	return true, nil
end

local function getStateForUser(userId: number): any
	local state = stateByUserId[userId]
	if state == nil then
		state = StealthShrinkState.new()
		stateByUserId[userId] = state
	end
	return state
end

local function resolveStealthDurationSeconds(): number
	local configAny = runtimeConfig
	if type(configAny) == "table" and isFiniteNumber(configAny.stealthDurationSeconds) then
		return math.max(configAny.stealthDurationSeconds, 1)
	end
	return DEFAULT_STEALTH_DURATION_SECONDS
end

local function resolveBlockedActions(): any
	local configAny = runtimeConfig
	if type(configAny) == "table" and type(configAny.blockedActions) == "table" then
		local blocked = {}
		for _, actionName in ipairs(configAny.blockedActions) do
			if isNonEmptyString(actionName) then
				blocked[actionName] = true
			end
		end
		return blocked
	end
	return DEFAULT_BLOCKED_ACTIONS
end

local function resolveActorRole(userId: number): string?
	local configAny = runtimeConfig
	if type(configAny) == "table" and type(configAny.roleResolver) == "function" then
		local ok, roleName = pcall(function()
			return configAny.roleResolver(userId)
		end)
		if ok and isNonEmptyString(roleName) then
			return roleName
		end
	end

	local player = Players:GetPlayerByUserId(userId)
	if player ~= nil and type(player.GetAttribute) == "function" then
		local roleName = player:GetAttribute("Role")
		if isNonEmptyString(roleName) then
			return roleName
		end
	end
	return nil
end

local function checkInvalidState(userId: number, at: number): (boolean, string?)
	local configAny = runtimeConfig
	if type(configAny) == "table" and type(configAny.invalidStateResolver) == "function" then
		local ok, invalidState, reason = pcall(function()
			return configAny.invalidStateResolver(userId)
		end)
		if ok and invalidState == true then
			return true, if isNonEmptyString(reason) then reason else "cancelled_invalid_state"
		end
	end

	local roleName = resolveActorRole(userId)
	if roleName ~= "Tinyfolk" then
		return true, "cancelled_role_mismatch"
	end

	local roleServiceApi = resolveRoleServiceApi()
	if type(roleServiceApi) == "table" and type(roleServiceApi.IsPlayerDowned) == "function" then
		local ok, isDowned = pcall(function()
			return roleServiceApi.IsPlayerDowned(userId)
		end)
		if ok and isDowned == true then
			return true, "cancelled_downed"
		end
	end

	local grabServiceApi = resolveGrabServiceApi()
	if type(grabServiceApi) == "table" and type(grabServiceApi.IsPlayerCarried) == "function" then
		local ok, isCarried = pcall(function()
			return grabServiceApi.IsPlayerCarried(userId)
		end)
		if ok and isCarried == true then
			return true, "cancelled_carried"
		end
	end

	if isPlayerHiding(userId) then
		return true, "cancelled_hiding_conflict"
	end

	local statusAllowed, statusReason = isStatusStealthAllowed(userId, at)
	if statusAllowed ~= true then
		if statusReason == "status_forbidden" then
			return true, "cancelled_status_forbidden"
		end
		if isNonEmptyString(statusReason) and string.find(statusReason, "cancelled_", 1, true) == 1 then
			return true, statusReason
		end
		return true, "cancelled_status_forbidden"
	end

	return false, nil
end

local function setLastReason(userId: number, reason: string)
	diagnostics.lastUserId = userId
	diagnostics.lastReason = reason
end

local function requestStealthShrink(input: any): any
	diagnostics.activationAttempts += 1
	if type(input) ~= "table" then
		diagnostics.activationFailed += 1
		setLastReason(0, "request_invalid")
		return { accepted = false, reason = "request_invalid" }
	end
	if not isPositiveInteger(input.userId) then
		diagnostics.activationFailed += 1
		setLastReason(0, "user_id_invalid")
		return { accepted = false, reason = "user_id_invalid" }
	end

	local userId = input.userId
	local roleName = resolveActorRole(userId)
	if roleName ~= "Tinyfolk" then
		diagnostics.activationFailed += 1
		setLastReason(userId, "role_forbidden")
		return { accepted = false, reason = "role_forbidden" }
	end

	local roleServiceApi = resolveRoleServiceApi()
	if
		type(roleServiceApi) == "table"
		and type(roleServiceApi.CanPlayerPerformInteraction) == "function"
		and roleServiceApi.CanPlayerPerformInteraction(userId, "stealthShrink") ~= true
	then
		diagnostics.activationFailed += 1
		setLastReason(userId, "interaction_forbidden")
		return { accepted = false, reason = "interaction_forbidden" }
	end

	if isPlayerHiding(userId) then
		diagnostics.activationFailed += 1
		setLastReason(userId, "hiding_forbidden")
		return { accepted = false, reason = "hiding_forbidden" }
	end

	local statusAllowed, statusReason = isStatusStealthAllowed(userId, resolveNow())
	if statusAllowed ~= true then
		diagnostics.activationFailed += 1
		local resolvedReason = if isNonEmptyString(statusReason) then statusReason else "status_forbidden"
		setLastReason(userId, resolvedReason)
		return { accepted = false, reason = resolvedReason }
	end

	local state = getStateForUser(userId)
	local ok, reason = state:Activate(resolveNow(), resolveStealthDurationSeconds())
	if not ok then
		diagnostics.activationFailed += 1
		setLastReason(userId, reason)
		return { accepted = false, reason = reason }
	end

	diagnostics.activationSucceeded += 1
	setLastReason(userId, reason)
	return {
		accepted = true,
		reason = reason,
		snapshot = state:GetSnapshot(resolveNow()),
	}
end

local function cancelStealthShrink(input: any): any
	diagnostics.cancelAttempts += 1
	if type(input) ~= "table" then
		diagnostics.cancelFailed += 1
		setLastReason(0, "request_invalid")
		return { accepted = false, reason = "request_invalid" }
	end
	if not isPositiveInteger(input.userId) then
		diagnostics.cancelFailed += 1
		setLastReason(0, "user_id_invalid")
		return { accepted = false, reason = "user_id_invalid" }
	end

	local userId = input.userId
	local state = getStateForUser(userId)
	local at = resolveNow()
	local ok, reason = state:Cancel("cancelled_by_request", at)
	if not ok then
		diagnostics.cancelFailed += 1
		setLastReason(userId, reason)
		return { accepted = false, reason = reason }
	end

	diagnostics.cancelSucceeded += 1
	setLastReason(userId, reason)
	return {
		accepted = true,
		reason = reason,
		snapshot = state:GetSnapshot(at),
	}
end

local function canPerformMajorAction(input: any): any
	if type(input) ~= "table" then
		return { accepted = false, reason = "request_invalid" }
	end
	if not isPositiveInteger(input.userId) then
		return { accepted = false, reason = "user_id_invalid" }
	end
	if not isNonEmptyString(input.actionName) then
		return { accepted = false, reason = "action_invalid" }
	end

	local state = getStateForUser(input.userId)
	if not state.isActive then
		return { accepted = true, reason = "accepted" }
	end

	local blockedActions = resolveBlockedActions()
	if blockedActions[input.actionName] ~= true then
		return { accepted = true, reason = "accepted" }
	end

	local now = resolveNow()
	state:Cancel("cancelled_invalid_action", now)
	diagnostics.invalidActionCancelled += 1
	diagnostics.lastActionName = input.actionName
	setLastReason(input.userId, "cancelled_invalid_action")
	return {
		accepted = false,
		reason = "cancelled_invalid_action",
		snapshot = state:GetSnapshot(now),
	}
end

local function getStealthShrinkSnapshot(input: any): any
	if type(input) ~= "table" or not isPositiveInteger(input.userId) then
		return nil
	end
	local state = getStateForUser(input.userId)
	return state:GetSnapshot(resolveNow())
end

local function tickStealthShrink(input: any?): any
	local at = if type(input) == "table" and isFiniteNumber(input.at) then input.at else resolveNow()
	for userId, state in pairs(stateByUserId) do
		if state.isActive then
			local invalidState, reason = checkInvalidState(userId, at)
			if invalidState then
				state:Cancel(reason or "cancelled_invalid_state", at)
				diagnostics.invalidStateCancelled += 1
				setLastReason(userId, reason or "cancelled_invalid_state")
				continue
			end

			local expired, expiredReason = state:Tick(at)
			if expired then
				diagnostics.tickExpired += 1
				setLastReason(userId, expiredReason or "expired")
			end
		end
	end

	return { accepted = true, reason = "accepted", at = at }
end

local function resetForTests()
	stateByUserId = {}
	diagnostics = {
		activationAttempts = 0,
		activationSucceeded = 0,
		activationFailed = 0,
		cancelAttempts = 0,
		cancelSucceeded = 0,
		cancelFailed = 0,
		tickExpired = 0,
		invalidStateCancelled = 0,
		invalidActionCancelled = 0,
		lastReason = "reset",
		lastUserId = nil,
		lastActionName = nil,
	}
end

local function configureForTests(config: any)
	runtimeConfig = if type(config) == "table" then config else {}
	resetForTests()
	return { accepted = true, reason = "accepted" }
end

resetForTests()

globalEnv._TinyfolkStealthService_QueryAPI = {
	RequestStealthShrink = requestStealthShrink,
	CancelStealthShrink = cancelStealthShrink,
	CanPerformMajorAction = canPerformMajorAction,
	GetStealthShrinkSnapshot = getStealthShrinkSnapshot,
	TickStealthShrink = tickStealthShrink,
	GetStealthShrinkDiagnostics = function()
		return cloneTable(diagnostics)
	end,
	ConfigureForTests = configureForTests,
	ResetForTests = resetForTests,
}

if type(_G) == "table" then
	rawset(_G, "_TinyfolkStealthService_QueryAPI", globalEnv._TinyfolkStealthService_QueryAPI)
end

if Players.PlayerRemoving and typeof(Players.PlayerRemoving.Connect) == "function" then
	Players.PlayerRemoving:Connect(function(player)
		stateByUserId[player.UserId] = nil
	end)
end

return globalEnv._TinyfolkStealthService_QueryAPI
