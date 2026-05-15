--!strict

local MockPlayer = require("../mocks/MockPlayer")

local MatchSimulation: any = {}
MatchSimulation.__index = MatchSimulation

export type SimulationConfig = {
	seed: number?,
	clock: (() -> number)?,
	escapeService: any?,
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
		appendMessage(self, string.format("[Tick %d] Assigned role %s to player %s", self.tick, payload.role, player.Name))
	elseif action == "throughGapReach" then
		local target = payload.target or self.players[payload.targetUserId]
		local result: any
		if self.escapeService ~= nil and type(self.escapeService.validateThroughGapReach) == "function" then
			result = self.escapeService.validateThroughGapReach(player, target, payload.request or payload)
		else
			result = player:attemptEscape(target, payload.request or payload).success == true
		end
		appendResult(self, action, player, { accepted = result == true, reason = if result then "accepted" else "rejected" })
		appendMessage(
			self,
			string.format("[Tick %d] Through-gap reach by %s: %s", self.tick, player.Name, if result then "Success" else "Failure")
		)
	elseif action == "attemptEscape" then
		local result: any
		if self.escapeService ~= nil and type(self.escapeService.requestEscapeAttempt) == "function" then
			result = self.escapeService.requestEscapeAttempt(player, payload.routeId)
		elseif self.escapeService ~= nil and type(self.escapeService.validateThroughGapReach) == "function" then
			result = {
				accepted = self.escapeService.validateThroughGapReach(player, payload.target, payload.request or payload) == true,
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
	elseif action == "captureAttempt" or action == "rescueAttempt" or action == "scoreEvent" then
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
