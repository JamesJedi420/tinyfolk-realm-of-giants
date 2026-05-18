--!strict

local MockPlayer = require("../mocks/MockPlayer")

local MatchSimulation: any = {}
MatchSimulation.__index = MatchSimulation

export type SimulationConfig = {
	seed: number?,
	clock: (() -> number)?,
	escapeService: any?,
	grabService: any?,
	applyRole: ((any, string) -> ())?,
}

export type Simulation = {
	players: { [number]: any },
	clock: (() -> number)?,
	seed: number,
	log: { string },
	results: { any },
	tick: number,
	sequence: number,
	actions: { [number]: { { action: string, params: any } } },
	nextGeneratedUserId: number,
	usedUserIds: { [number]: boolean },
	escapeService: any?,
	grabService: any?,
	applyRole: ((any, string) -> ())?,
	addPlayer: (self: Simulation, userId: number?, name: string?, options: any?) -> any,
	createFakePlayer: (self: Simulation, options: any?) -> any,
	queueAction: (self: Simulation, tick: number, action: string, params: any) -> (),
	advanceTick: (self: Simulation, stepCount: number?) -> (),
	executeAction: (self: Simulation, action: string, params: any) -> (),
	getLog: (self: Simulation) -> { string },
	getResults: (self: Simulation) -> { any },
}

local RNG_MOD = 2147483648

local function normalizeSeed(seed: number?): number
	local resolved = if type(seed) == "number" then math.floor(seed) else 1337
	if resolved < 0 then
		resolved = -resolved
	end
	if resolved == 0 then
		resolved = 1
	end
	return resolved % RNG_MOD
end

local function nextRandom(self: Simulation): number
	self.seed = (1103515245 * self.seed + 12345) % RNG_MOD
	return self.seed
end

local function nextRandomRange(self: Simulation, minValue: number, maxValue: number): number
	local span = maxValue - minValue + 1
	return minValue + (nextRandom(self) % span)
end

local function appendResult(self: Simulation, action: string, player: any?, result: any)
	self.sequence += 1
	local outcome = {
		tick = self.tick,
		sequence = self.sequence,
		action = action,
		userId = if player ~= nil then player.UserId else nil,
		playerName = if player ~= nil then player.Name else nil,
		result = result,
	}
	table.insert(self.results, outcome)
end

local function appendMessage(self: Simulation, message: string)
	table.insert(self.log, message)
end

local function generateUserId(self: Simulation): number
	while true do
		local candidate = self.nextGeneratedUserId + nextRandomRange(self, 1, 57)
		self.nextGeneratedUserId = candidate
		if self.usedUserIds[candidate] ~= true then
			self.usedUserIds[candidate] = true
			return candidate
		end
	end
	return self.nextGeneratedUserId
end

local function assignRole(self: Simulation, player: any, roleName: string)
	if self.applyRole ~= nil then
		(self.applyRole :: any)(player, roleName)
	else
		player:SetAttribute("Role", roleName)
	end
end

local function getRoleServiceQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end
	local queryApi = globalValue._RoleService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end
	return queryApi
end

local function getGrabServiceQueryApi(self: Simulation): any?
	if self.grabService ~= nil then
		return self.grabService
	end

	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end
	local queryApi = globalValue._GrabService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end
	return queryApi
end

local function getRescueServiceQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end
	local queryApi = globalValue._RescueContractService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end
	return queryApi
end

local function getCaptureServiceQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end
	local queryApi = globalValue._CaptureService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end
	return queryApi
end

local function attachCarrierLoadSnapshot(self: Simulation, result: any, giantUserId: number?)
	if type(result) ~= "table" or type(giantUserId) ~= "number" then
		return
	end

	if result.carrierLoadSnapshot ~= nil then
		return
	end

	local grabServiceQueryApi = getGrabServiceQueryApi(self)
	if grabServiceQueryApi ~= nil and type(grabServiceQueryApi.GetCarrierLoadSnapshot) == "function" then
		result.carrierLoadSnapshot = grabServiceQueryApi.GetCarrierLoadSnapshot(giantUserId)
	end
end

function MatchSimulation.new(config: SimulationConfig?): Simulation
	local configAny: any = config
	local seed = normalizeSeed(if configAny ~= nil then configAny.seed else nil)
	local self = setmetatable({}, MatchSimulation)
	self.players = {}
	self.clock = if configAny ~= nil then configAny.clock else nil
	self.seed = seed
	self.log = {}
	self.results = {}
	self.tick = 0
	self.sequence = 0
	self.actions = {}
	self.nextGeneratedUserId = 100000 + (seed % 900000)
	self.usedUserIds = {}
	self.escapeService = if configAny ~= nil then configAny.escapeService else nil
	self.grabService = if configAny ~= nil then configAny.grabService else nil
	self.applyRole = if configAny ~= nil then configAny.applyRole else nil
	return self
end

function MatchSimulation.addPlayer(self: Simulation, userId: number?, name: string?, options: any?)
	local resolvedUserId = if type(userId) == "number" then userId else generateUserId(self)
	local resolvedName = if type(name) == "string" then name else string.format("SimPlayer_%d", resolvedUserId)
	self.usedUserIds[resolvedUserId] = true
	local player = MockPlayer.new(resolvedUserId, resolvedName, options)
	self.players[resolvedUserId] = player
	appendResult(self, "addPlayer", player, { accepted = true, reason = "created" })
	appendMessage(self, string.format("[Tick %d] Added player %s (%d)", self.tick, resolvedName, resolvedUserId))
	return player
end

function MatchSimulation.createFakePlayer(self: Simulation, options: any?)
	return self:addPlayer(nil, nil, options)
end

function MatchSimulation.queueAction(self: Simulation, tick: number, action: string, params: any)
	if not self.actions[tick] then
		self.actions[tick] = {}
	end
	table.insert(self.actions[tick], { action = action, params = params })
end

function MatchSimulation.advanceTick(self: Simulation, stepCount: number?)
	local iterations = if type(stepCount) == "number" and stepCount > 0 then math.floor(stepCount) else 1
	for _ = 1, iterations do
		self.tick += 1
		local roleServiceQueryApi = getRoleServiceQueryApi()
		if roleServiceQueryApi ~= nil and type(roleServiceQueryApi.TickDownedStates) == "function" then
			roleServiceQueryApi.TickDownedStates(self.tick)
		end
		if self.actions[self.tick] then
			for _, action in ipairs(self.actions[self.tick]) do
				self:executeAction(action.action, action.params)
			end
		end
	end
end

function MatchSimulation.executeAction(self: Simulation, action: string, params: any)
	local payload = params or {}
	local player = self.players[payload.userId]
	if player == nil then
		appendResult(self, action, nil, { accepted = false, reason = "player_not_found" })
		appendMessage(self, string.format("[Tick %d] %s: player_not_found", self.tick, action))
		return
	end

	if action == "assignRole" then
		assignRole(self, player, payload.role)
		appendResult(self, action, player, { accepted = true, role = payload.role })
		appendMessage(
			self,
			string.format("[Tick %d] Assigned role %s to player %s", self.tick, payload.role, player.Name)
		)
	elseif action == "downTinyfolk" then
		local roleServiceQueryApi = getRoleServiceQueryApi()
		local accepted = false
		if roleServiceQueryApi ~= nil and type(roleServiceQueryApi.SetDowned) == "function" then
			accepted = roleServiceQueryApi.SetDowned(
				player.UserId,
				if type(payload.durationSeconds) == "number" then payload.durationSeconds else 30,
				if type(payload.reason) == "string" then payload.reason else "simulation_downed"
			)
		end
		appendResult(
			self,
			action,
			player,
			{ accepted = accepted, reason = if accepted then "accepted" else "rejected" }
		)
		appendMessage(
			self,
			string.format(
				"[Tick %d] Downed request for %s: %s",
				self.tick,
				player.Name,
				if accepted then "Accepted" else "Rejected"
			)
		)
	elseif action == "selfRecoverDowned" then
		local roleServiceQueryApi = getRoleServiceQueryApi()
		local accepted = false
		if roleServiceQueryApi ~= nil and type(roleServiceQueryApi.SelfRecoverDowned) == "function" then
			accepted = roleServiceQueryApi.SelfRecoverDowned(
				player.UserId,
				if type(payload.progressDelta) == "number" then payload.progressDelta else 0
			)
		end
		appendResult(
			self,
			action,
			player,
			{ accepted = accepted, reason = if accepted then "accepted" else "rejected" }
		)
		appendMessage(
			self,
			string.format(
				"[Tick %d] Self-recover downed by %s: %s",
				self.tick,
				player.Name,
				if accepted then "Accepted" else "Rejected"
			)
		)
	elseif action == "tickDowned" then
		local roleServiceQueryApi = getRoleServiceQueryApi()
		if roleServiceQueryApi ~= nil and type(roleServiceQueryApi.TickDownedStates) == "function" then
			roleServiceQueryApi.TickDownedStates(if type(payload.now) == "number" then payload.now else self.tick)
		end
		appendResult(self, action, player, { accepted = true, reason = "accepted" })
		appendMessage(self, string.format("[Tick %d] Downed state tick by %s: Applied", self.tick, player.Name))
	elseif action == "attemptEscapeWhileDowned" then
		local result: any
		if self.escapeService ~= nil and type(self.escapeService.requestEscapeAttempt) == "function" then
			result = self.escapeService.requestEscapeAttempt(player, payload.routeId)
		else
			result = { accepted = false, reason = "escape_service_unavailable" }
		end
		appendResult(self, action, player, result)
		appendMessage(
			self,
			string.format(
				"[Tick %d] Escape while downed by %s: %s",
				self.tick,
				player.Name,
				if result.accepted == true then "Success" else "Failure"
			)
		)
	elseif action == "throughGapReach" then
		local target = payload.target or self.players[payload.targetUserId]
		local result: any
		if self.escapeService ~= nil and type(self.escapeService.validateThroughGapReach) == "function" then
			result = self.escapeService.validateThroughGapReach(player, target, payload.request or payload)
		else
			result = player:attemptEscape(target, payload.request or payload).success == true
		end
		appendResult(
			self,
			action,
			player,
			{ accepted = result == true, reason = if result then "accepted" else "rejected" }
		)
		appendMessage(
			self,
			string.format(
				"[Tick %d] Through-gap reach by %s: %s",
				self.tick,
				player.Name,
				if result then "Success" else "Failure"
			)
		)
	elseif action == "attemptEscape" then
		local result: any
		if self.escapeService ~= nil and type(self.escapeService.requestEscapeAttempt) == "function" then
			result = self.escapeService.requestEscapeAttempt(player, payload.routeId)
		elseif self.escapeService ~= nil and type(self.escapeService.validateThroughGapReach) == "function" then
			result = {
				accepted = self.escapeService.validateThroughGapReach(
					player,
					payload.target,
					payload.request or payload
				) == true,
				reason = "validate_through_gap_reach",
			}
		else
			result = player:attemptEscape(payload.target, payload.request or payload)
		end
		appendResult(self, action, player, result)
		appendMessage(
			self,
			string.format(
				"[Tick %d] Escape attempt by %s: %s",
				self.tick,
				player.Name,
				if result.accepted == true or result.success == true then "Success" else "Failure"
			)
		)
	elseif action == "blockTraversalGap" then
		local result: any
		if self.escapeService ~= nil and type(self.escapeService.requestTraversalGapBlock) == "function" then
			result = self.escapeService.requestTraversalGapBlock(player, payload.routeId)
		else
			result = player:blockTraversalGap(payload.routeId, payload.config)
		end
		appendResult(self, action, player, result)
		appendMessage(
			self,
			string.format(
				"[Tick %d] Traversal gap block by %s: %s",
				self.tick,
				player.Name,
				if result.accepted == true then "Accepted" else "Rejected"
			)
		)
	elseif action == "grabTinyfolk" or action == "carryDowned" then
		local result: any
		local targetUserId = payload.targetUserId
		local grabServiceQueryApi = getGrabServiceQueryApi(self)
		if grabServiceQueryApi ~= nil and type(grabServiceQueryApi.RequestGrab) == "function" then
			result = grabServiceQueryApi.RequestGrab(player.UserId, targetUserId, self.tick)
		else
			result = { accepted = false, reason = "grab_service_unavailable" }
		end
		attachCarrierLoadSnapshot(self, result, player.UserId)
		appendResult(self, action, player, result)
		appendMessage(
			self,
			string.format(
				"[Tick %d] Grab by %s: %s",
				self.tick,
				player.Name,
				if result.accepted == true then "Accepted" else "Rejected"
			)
		)
	elseif action == "carriedCounterplay" then
		local result: any
		local grabServiceQueryApi = getGrabServiceQueryApi(self)
		if grabServiceQueryApi ~= nil and type(grabServiceQueryApi.RequestCounterplay) == "function" then
			result = grabServiceQueryApi.RequestCounterplay(player.UserId, self.tick)
		else
			result = { accepted = false, reason = "grab_service_unavailable" }
		end
		if type(result) == "table" and type(result.snapshot) == "table" then
			attachCarrierLoadSnapshot(self, result, result.snapshot.carriedByUserId)
		end
		appendResult(self, action, player, result)
		appendMessage(
			self,
			string.format(
				"[Tick %d] Carried counterplay by %s: %s",
				self.tick,
				player.Name,
				if result.accepted == true then "Accepted" else "Rejected"
			)
		)
	elseif action == "rescueAttempt" then
		local rescueServiceQueryApi = getRescueServiceQueryApi()
		local result: any
		if rescueServiceQueryApi ~= nil and type(rescueServiceQueryApi.RequestRescueContract) == "function" then
			result = rescueServiceQueryApi.RequestRescueContract(player.UserId, payload.targetUserId, self.tick)
		else
			result = {
				accepted = false,
				reason = "not_implemented",
				system = action,
			}
		end
		appendResult(self, action, player, result)
		appendMessage(
			self,
			string.format(
				"[Tick %d] %s by %s: %s",
				self.tick,
				action,
				player.Name,
				if result.accepted == true then "Accepted" else "Rejected"
			)
		)
	elseif action == "captureAttempt" then
		local captureServiceQueryApi = getCaptureServiceQueryApi()
		local result: any
		if captureServiceQueryApi ~= nil and type(captureServiceQueryApi.RequestCapture) == "function" then
			result = captureServiceQueryApi.RequestCapture(player.UserId, payload.targetUserId, self.tick)
		else
			result = {
				accepted = false,
				reason = "not_implemented",
				system = action,
			}
		end
		appendResult(self, action, player, result)
		appendMessage(
			self,
			string.format(
				"[Tick %d] %s by %s: %s",
				self.tick,
				action,
				player.Name,
				if result.accepted == true then "Accepted" else "Rejected"
			)
		)
	elseif action == "scoreEvent" then
		local result = {
			accepted = false,
			reason = "not_implemented",
			system = action,
		}
		appendResult(self, action, player, result)
		appendMessage(self, string.format("[Tick %d] %s by %s: NotImplemented", self.tick, action, player.Name))
	elseif action == "allyRecoverDowned" or action == "rescueDowned" then
		local result = {
			accepted = false,
			reason = "not_implemented",
			system = action,
		}
		appendResult(self, action, player, result)
		appendMessage(self, string.format("[Tick %d] %s by %s: NotImplemented", self.tick, action, player.Name))
	else
		appendResult(self, action, player, { accepted = false, reason = "action_not_supported" })
		appendMessage(self, string.format("[Tick %d] %s by %s: Unsupported", self.tick, action, player.Name))
	end
end

function MatchSimulation.getLog(self: Simulation)
	return self.log
end

function MatchSimulation.getResults(self: Simulation)
	return self.results
end

return MatchSimulation
