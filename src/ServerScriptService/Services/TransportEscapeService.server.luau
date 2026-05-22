--!nocheck
local TRANSPORT_ENDPOINT_PATH = { "Map", "TransportEndpoints" }

local TRANSPORT_ENDPOINT_ID_ATTRIBUTE = "TransportEndpointId"
local TRANSPORT_REQUIRED_COMPONENTS_ATTRIBUTE = "TransportRequiredComponents"
local TRANSPORT_CAPACITY_ATTRIBUTE = "TransportCapacity"
local TRANSPORT_OPERATOR_REQUIRED_ATTRIBUTE = "TransportOperatorRequired"
local TRANSPORT_STARTUP_DURATION_ATTRIBUTE = "TransportStartupDurationSeconds"
local TRANSPORT_LAUNCH_DURATION_ATTRIBUTE = "TransportLaunchDurationSeconds"
local TRANSPORT_MAX_INTERRUPTS_ATTRIBUTE = "TransportMaxStartupInterruptions"

local PHASE_ATTRIBUTE = "TransportPhase"
local BOARD_COUNT_ATTRIBUTE = "TransportBoardedCount"
local CAPACITY_ATTRIBUTE = "TransportCapacity"
local ASSEMBLY_READY_ATTRIBUTE = "TransportAssemblyReady"
local OPERATOR_USER_ID_ATTRIBUTE = "TransportOperatorUserId"
local STARTUP_ENDS_AT_ATTRIBUTE = "TransportStartupEndsAt"
local LAUNCH_ENDS_AT_ATTRIBUTE = "TransportLaunchEndsAt"
local DEPARTED_AT_ATTRIBUTE = "TransportDepartedAt"
local REQUIRED_COMPONENT_COUNT_ATTRIBUTE = "TransportRequiredComponentCount"
local SATISFIED_COMPONENT_COUNT_ATTRIBUTE = "TransportSatisfiedComponentCount"
local LAST_REASON_ATTRIBUTE = "TransportLastReason"

local function debugLog(message: string)
	print(string.format("[TransportEscapeService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[TransportEscapeService] %s", message))
end

local function getService(gameRef: any, serviceName: string): any
	local colonOk, colonValue = pcall(function()
		return gameRef:GetService(serviceName)
	end)
	if colonOk and colonValue ~= nil then
		return colonValue
	end

	local dotOk, dotValue = pcall(function()
		return gameRef.GetService(serviceName)
	end)
	if dotOk and dotValue ~= nil then
		return dotValue
	end

	return nil
end

local function resolveDependency(parent: any, childName: string, fallbackRequirePath: string): any
	if parent ~= nil and type(parent.WaitForChild) == "function" then
		local child = parent:WaitForChild(childName)
		if child ~= nil then
			local childAny = child :: any
			if type(childAny) == "table" and rawget(childAny, "NewState") ~= nil then
				return childAny
			end

			local ok, requiredOrError = pcall(function()
				return require(childAny)
			end)
			if ok then
				return requiredOrError
			end
		end
	end

	return require(fallbackRequirePath)
end

local function createTransportEscapeService(runtimeGame: any?, options: any?)
	local gameRef = runtimeGame or game
	local Players = getService(gameRef, "Players")
	local ReplicatedStorage = getService(gameRef, "ReplicatedStorage")
	local Workspace = getService(gameRef, "Workspace")

	local Shared = if ReplicatedStorage ~= nil and type(ReplicatedStorage.WaitForChild) == "function"
		then ReplicatedStorage:WaitForChild("Shared")
		else nil
	local GiantRealm = if Shared ~= nil and type(Shared.WaitForChild) == "function"
		then Shared:WaitForChild("GiantRealm")
		else nil

	local TransportEscapeState = resolveDependency(
		GiantRealm,
		"TransportEscapeState",
		"../../ReplicatedStorage/Shared/GiantRealm/TransportEscapeState"
	)

	local endpointStateById: { [string]: any } = {}
	local endpointNodeById: { [string]: any } = {}
	local endpointParticipantUserIdsById: { [string]: { [number]: true } } = {}

	local function now(): number
		if options ~= nil and type(options.clock) == "function" then
			local value = options.clock()
			if type(value) == "number" then
				return value
			end
		end
		return os.clock()
	end

	local function getPathNode(root: any, path: { string }): any?
		local current = root
		for _, segment in ipairs(path) do
			if current == nil then
				return nil
			end

			if type(current.FindFirstChild) == "function" then
				current = current:FindFirstChild(segment)
			elseif type(current.WaitForChild) == "function" then
				current = current:WaitForChild(segment, 0)
			else
				return nil
			end

			if current == nil then
				return nil
			end
		end

		return current
	end

	local function normalizeComponentList(value: any): { string }
		local result: { string } = {}
		local seen: { [string]: true } = {}

		if type(value) == "table" then
			for _, item in ipairs(value) do
				if type(item) == "string" and string.len(item) > 0 and seen[item] == nil then
					seen[item] = true
					table.insert(result, item)
				end
			end
		elseif type(value) == "string" then
			for token in string.gmatch(value, "[^,]+") do
				local trimmed = string.gsub(token, "^%s*(.-)%s*$", "%1")
				if string.len(trimmed) > 0 and seen[trimmed] == nil then
					seen[trimmed] = true
					table.insert(result, trimmed)
				end
			end
		end

		return result
	end

	local function resolveEndpointId(endpointNode: any): string?
		if endpointNode == nil then
			return nil
		end

		if type(endpointNode.GetAttribute) == "function" then
			local attributedEndpointId = endpointNode:GetAttribute(TRANSPORT_ENDPOINT_ID_ATTRIBUTE)
			if type(attributedEndpointId) == "string" and string.len(attributedEndpointId) > 0 then
				return attributedEndpointId
			end
		end

		if type(endpointNode.Name) == "string" and string.len(endpointNode.Name) > 0 then
			if string.find(endpointNode.Name, "Transport", 1, true) ~= nil then
				return endpointNode.Name
			end
		end

		return nil
	end

	local function applySnapshotAttributes(endpointId: string)
		local endpointNode = endpointNodeById[endpointId]
		if endpointNode == nil or type(endpointNode.SetAttribute) ~= "function" then
			return
		end

		local state = endpointStateById[endpointId]
		if state == nil then
			return
		end

		local snapshot = TransportEscapeState.GetSnapshot(state)
		endpointNode:SetAttribute(PHASE_ATTRIBUTE, snapshot.phase)
		endpointNode:SetAttribute(BOARD_COUNT_ATTRIBUTE, snapshot.boardedCount)
		endpointNode:SetAttribute(CAPACITY_ATTRIBUTE, snapshot.capacity)
		endpointNode:SetAttribute(ASSEMBLY_READY_ATTRIBUTE, snapshot.assemblyReady == true)
		endpointNode:SetAttribute(OPERATOR_USER_ID_ATTRIBUTE, snapshot.operatorUserId)
		endpointNode:SetAttribute(STARTUP_ENDS_AT_ATTRIBUTE, snapshot.startupEndsAt)
		endpointNode:SetAttribute(LAUNCH_ENDS_AT_ATTRIBUTE, snapshot.launchEndsAt)
		endpointNode:SetAttribute(DEPARTED_AT_ATTRIBUTE, snapshot.departedAt)
		endpointNode:SetAttribute(REQUIRED_COMPONENT_COUNT_ATTRIBUTE, snapshot.requiredComponentCount)
		endpointNode:SetAttribute(SATISFIED_COMPONENT_COUNT_ATTRIBUTE, snapshot.satisfiedRequiredCount)
		endpointNode:SetAttribute(LAST_REASON_ATTRIBUTE, snapshot.lastReason)
	end

	local function sortedEndpointIds(): { string }
		local endpointIds: { string } = {}
		for endpointId, _ in pairs(endpointStateById) do
			table.insert(endpointIds, endpointId)
		end
		table.sort(endpointIds)
		return endpointIds
	end

	local function resolveEndpointState(endpointId: string): any?
		if type(endpointId) ~= "string" or string.len(endpointId) <= 0 then
			return nil
		end
		return endpointStateById[endpointId]
	end

	local function getEscapeServiceQueryApi(): any?
		local globalValue: any = _G
		if type(globalValue) ~= "table" then
			return nil
		end

		local queryApi = globalValue._EscapeService_QueryAPI
		if type(queryApi) ~= "table" then
			return nil
		end

		return queryApi
	end

	local function markEndpointParticipant(endpointId: string, userId: number)
		local participants = endpointParticipantUserIdsById[endpointId]
		if participants == nil then
			participants = {}
			endpointParticipantUserIdsById[endpointId] = participants
		end
		participants[userId] = true
	end

	local function collectTinyfolkCandidateUserIds(endpointId: string): { number }
		local participants = endpointParticipantUserIdsById[endpointId]
		if participants == nil then
			return {}
		end
		if Players == nil or type(Players.GetPlayers) ~= "function" then
			return {}
		end

		local candidateUserIds: { number } = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if type((player :: any).UserId) == "number" and type((player :: any).GetAttribute) == "function" then
				if
					participants[(player :: any).UserId] == true
					and (player :: any):GetAttribute("Role") == "Tinyfolk"
				then
					table.insert(candidateUserIds, (player :: any).UserId)
				end
			end
		end
		table.sort(candidateUserIds)

		return candidateUserIds
	end

	local function registerEndpoint(endpointId: string, config: any?, endpointNode: any?): any
		if type(endpointId) ~= "string" or string.len(endpointId) <= 0 then
			return { accepted = false, reason = "endpoint_id_invalid", snapshot = nil }
		end

		if endpointStateById[endpointId] ~= nil then
			return {
				accepted = false,
				reason = "endpoint_already_registered",
				snapshot = TransportEscapeState.GetSnapshot(endpointStateById[endpointId]),
			}
		end

		local configAny = config
		local state = TransportEscapeState.NewState({
			EndpointId = endpointId,
			Capacity = if type(configAny) == "table" then configAny.Capacity else nil,
			OperatorRequired = if type(configAny) == "table" then configAny.OperatorRequired else nil,
			StartupDurationSeconds = if type(configAny) == "table" then configAny.StartupDurationSeconds else nil,
			LaunchDurationSeconds = if type(configAny) == "table" then configAny.LaunchDurationSeconds else nil,
			MaxStartupInterruptions = if type(configAny) == "table" then configAny.MaxStartupInterruptions else nil,
		})

		endpointStateById[endpointId] = state
		endpointNodeById[endpointId] = endpointNode
		endpointParticipantUserIdsById[endpointId] = {}

		local requiredComponents =
			normalizeComponentList(if type(configAny) == "table" then configAny.RequiredComponents else nil)
		for _, componentId in ipairs(requiredComponents) do
			local transition =
				TransportEscapeState.RegisterRequiredComponent(endpointStateById[endpointId], componentId)
			endpointStateById[endpointId] = transition.state
		end

		applySnapshotAttributes(endpointId)
		return {
			accepted = true,
			reason = "accepted",
			snapshot = TransportEscapeState.GetSnapshot(endpointStateById[endpointId]),
		}
	end

	local function discoverWorkspaceTransportEndpoints()
		local transportFolder = getPathNode(Workspace, TRANSPORT_ENDPOINT_PATH)
		if transportFolder == nil or type(transportFolder.GetChildren) ~= "function" then
			return
		end

		for _, child in ipairs(transportFolder:GetChildren()) do
			local endpointId = resolveEndpointId(child)
			if endpointId ~= nil then
				local requiredComponents: any = nil
				local capacity: any = nil
				local operatorRequired: any = nil
				local startupDurationSeconds: any = nil
				local launchDurationSeconds: any = nil
				local maxStartupInterruptions: any = nil

				if type(child.GetAttribute) == "function" then
					requiredComponents = child:GetAttribute(TRANSPORT_REQUIRED_COMPONENTS_ATTRIBUTE)
					capacity = child:GetAttribute(TRANSPORT_CAPACITY_ATTRIBUTE)
					operatorRequired = child:GetAttribute(TRANSPORT_OPERATOR_REQUIRED_ATTRIBUTE)
					startupDurationSeconds = child:GetAttribute(TRANSPORT_STARTUP_DURATION_ATTRIBUTE)
					launchDurationSeconds = child:GetAttribute(TRANSPORT_LAUNCH_DURATION_ATTRIBUTE)
					maxStartupInterruptions = child:GetAttribute(TRANSPORT_MAX_INTERRUPTS_ATTRIBUTE)
				end

				registerEndpoint(endpointId, {
					RequiredComponents = requiredComponents,
					Capacity = capacity,
					OperatorRequired = operatorRequired,
					StartupDurationSeconds = startupDurationSeconds,
					LaunchDurationSeconds = launchDurationSeconds,
					MaxStartupInterruptions = maxStartupInterruptions,
				}, child)
			end
		end
	end

	local function applyTransition(endpointId: string, transition: any): any
		endpointStateById[endpointId] = transition.state
		applySnapshotAttributes(endpointId)

		local escapeResolution: any = nil
		if transition.accepted == true and tostring(transition.reason) == "departed" then
			local escapeQueryApi = getEscapeServiceQueryApi()
			if escapeQueryApi ~= nil and type(escapeQueryApi.ResolveTransportDeparture) == "function" then
				escapeResolution =
					escapeQueryApi.ResolveTransportDeparture(endpointId, collectTinyfolkCandidateUserIds(endpointId))
			end
		end

		return {
			accepted = transition.accepted == true,
			reason = tostring(transition.reason or "unknown"),
			alert = transition.alert,
			escapeResolution = escapeResolution,
			snapshot = TransportEscapeState.GetSnapshot(endpointStateById[endpointId]),
		}
	end

	local service: any = {}

	function service.getTransportEndpointIds(): { string }
		return sortedEndpointIds()
	end

	function service.getTransportEndpointSnapshot(endpointId: string): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return nil
		end
		return TransportEscapeState.GetSnapshot(state)
	end

	function service.getAllTransportEndpointSnapshots(): any
		local snapshotsById: { [string]: any } = {}
		local endpointIds = sortedEndpointIds()
		for _, endpointId in ipairs(endpointIds) do
			snapshotsById[endpointId] = TransportEscapeState.GetSnapshot(endpointStateById[endpointId])
		end
		return {
			endpointIds = endpointIds,
			snapshotsById = snapshotsById,
		}
	end

	function service.registerTransportEndpointForTests(params: any): any
		local paramsAny = params
		return registerEndpoint(
			if type(paramsAny) == "table" then paramsAny.endpointId else nil,
			if type(paramsAny) == "table" then paramsAny else nil,
			nil
		)
	end

	function service.registerRequiredComponentForTests(endpointId: string, componentId: string): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", snapshot = nil }
		end
		local transition = TransportEscapeState.RegisterRequiredComponent(state, componentId)
		return applyTransition(endpointId, transition)
	end

	function service.recordComponentHeld(
		endpointId: string,
		componentId: string,
		holderUserId: number,
		at: number?
	): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", snapshot = nil }
		end
		return applyTransition(endpointId, TransportEscapeState.SetComponentHeld(state, componentId, holderUserId, at))
	end

	function service.recordComponentDropped(endpointId: string, componentId: string, at: number?): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", snapshot = nil }
		end
		return applyTransition(endpointId, TransportEscapeState.SetComponentDropped(state, componentId, at))
	end

	function service.recordComponentInstalled(
		endpointId: string,
		componentId: string,
		installedByUserId: number,
		at: number?
	): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", snapshot = nil }
		end
		return applyTransition(
			endpointId,
			TransportEscapeState.SetComponentInstalled(state, componentId, installedByUserId, at)
		)
	end

	function service.recordComponentLost(endpointId: string, componentId: string, at: number?): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", snapshot = nil }
		end
		return applyTransition(endpointId, TransportEscapeState.SetComponentLost(state, componentId, at))
	end

	function service.recordComponentRecovered(
		endpointId: string,
		componentId: string,
		holderUserId: number,
		at: number?
	): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", snapshot = nil }
		end
		return applyTransition(
			endpointId,
			TransportEscapeState.SetComponentRecovered(state, componentId, holderUserId, at)
		)
	end

	function service.recordComponentBlocked(endpointId: string, componentId: string, at: number?): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", snapshot = nil }
		end
		return applyTransition(endpointId, TransportEscapeState.SetComponentBlocked(state, componentId, at))
	end

	function service.recordComponentDelivered(
		endpointId: string,
		componentId: string,
		deliveredByUserId: number,
		at: number?
	): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", snapshot = nil }
		end
		return applyTransition(
			endpointId,
			TransportEscapeState.SetComponentDelivered(state, componentId, deliveredByUserId, at)
		)
	end

	function service.boardPassenger(endpointId: string, userId: number, asOperator: boolean?): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", snapshot = nil }
		end
		local result = applyTransition(
			endpointId,
			TransportEscapeState.BoardPassenger(state, userId, { asOperator = asOperator == true })
		)
		if result.accepted == true then
			markEndpointParticipant(endpointId, userId)
		end
		return result
	end

	function service.unboardPassenger(endpointId: string, userId: number): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", snapshot = nil }
		end
		return applyTransition(endpointId, TransportEscapeState.UnboardPassenger(state, userId))
	end

	function service.startStartup(endpointId: string, operatorUserId: number?, at: number?): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", snapshot = nil }
		end
		return applyTransition(
			endpointId,
			TransportEscapeState.StartStartup(state, operatorUserId, if type(at) == "number" then at else now())
		)
	end

	function service.interruptStartup(endpointId: string, at: number?): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", snapshot = nil }
		end
		return applyTransition(
			endpointId,
			TransportEscapeState.InterruptStartup(state, if type(at) == "number" then at else now())
		)
	end

	function service.tickEndpoint(endpointId: string, at: number?): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", snapshot = nil }
		end
		return applyTransition(
			endpointId,
			TransportEscapeState.ResolveTime(state, if type(at) == "number" then at else now())
		)
	end

	function service.resolveDepartureOutcome(endpointId: string, candidateTinyfolkUserIds: { number }): any
		local state = resolveEndpointState(endpointId)
		if state == nil then
			return { accepted = false, reason = "endpoint_not_found", outcome = nil, snapshot = nil }
		end

		local outcome = TransportEscapeState.ResolveDepartureOutcome(state, candidateTinyfolkUserIds)
		return {
			accepted = outcome.canResolve == true,
			reason = if outcome.canResolve == true then "accepted" else "transport_not_departed",
			outcome = outcome,
			snapshot = TransportEscapeState.GetSnapshot(state),
		}
	end

	function service.resetForTests()
		endpointStateById = {}
		endpointNodeById = {}
		endpointParticipantUserIdsById = {}
		discoverWorkspaceTransportEndpoints()
	end

	local function initialize()
		discoverWorkspaceTransportEndpoints()
		debugLog("TransportEscapeService initialized")
	end

	service.initialize = initialize

	_G._TransportEscapeService_QueryAPI = {
		GetTransportEndpointIds = function(): { string }
			return service.getTransportEndpointIds()
		end,
		GetTransportEndpointSnapshot = function(endpointId: string): any
			return service.getTransportEndpointSnapshot(endpointId)
		end,
		GetAllTransportEndpointSnapshots = function(): any
			return service.getAllTransportEndpointSnapshots()
		end,
		RegisterTransportEndpointForTests = function(params: any): any
			return service.registerTransportEndpointForTests(params)
		end,
		RegisterTransportRequiredComponentForTests = function(endpointId: string, componentId: string): any
			return service.registerRequiredComponentForTests(endpointId, componentId)
		end,
		RecordTransportComponentHeld = function(
			endpointId: string,
			componentId: string,
			holderUserId: number,
			at: number?
		): any
			return service.recordComponentHeld(endpointId, componentId, holderUserId, at)
		end,
		RecordTransportComponentDropped = function(endpointId: string, componentId: string, at: number?): any
			return service.recordComponentDropped(endpointId, componentId, at)
		end,
		RecordTransportComponentInstalled = function(
			endpointId: string,
			componentId: string,
			installedByUserId: number,
			at: number?
		): any
			return service.recordComponentInstalled(endpointId, componentId, installedByUserId, at)
		end,
		RecordTransportComponentLost = function(endpointId: string, componentId: string, at: number?): any
			return service.recordComponentLost(endpointId, componentId, at)
		end,
		RecordTransportComponentRecovered = function(
			endpointId: string,
			componentId: string,
			holderUserId: number,
			at: number?
		): any
			return service.recordComponentRecovered(endpointId, componentId, holderUserId, at)
		end,
		RecordTransportComponentBlocked = function(endpointId: string, componentId: string, at: number?): any
			return service.recordComponentBlocked(endpointId, componentId, at)
		end,
		RecordTransportComponentDelivered = function(
			endpointId: string,
			componentId: string,
			deliveredByUserId: number,
			at: number?
		): any
			return service.recordComponentDelivered(endpointId, componentId, deliveredByUserId, at)
		end,
		BoardTransportPassenger = function(endpointId: string, userId: number, asOperator: boolean?): any
			return service.boardPassenger(endpointId, userId, asOperator)
		end,
		UnboardTransportPassenger = function(endpointId: string, userId: number): any
			return service.unboardPassenger(endpointId, userId)
		end,
		StartTransportStartup = function(endpointId: string, operatorUserId: number?, at: number?): any
			return service.startStartup(endpointId, operatorUserId, at)
		end,
		InterruptTransportStartup = function(endpointId: string, at: number?): any
			return service.interruptStartup(endpointId, at)
		end,
		TickTransportEndpoint = function(endpointId: string, at: number?): any
			return service.tickEndpoint(endpointId, at)
		end,
		ResolveTransportDepartureOutcome = function(endpointId: string, candidateTinyfolkUserIds: { number }): any
			return service.resolveDepartureOutcome(endpointId, candidateTinyfolkUserIds)
		end,
		ResetForTests = function()
			service.resetForTests()
		end,
	}

	if options == nil or options.autoInitialize ~= false then
		local ok, errorOrNil = pcall(initialize)
		if not ok then
			debugWarn(string.format("Initialization skipped due to runtime mismatch: %s", tostring(errorOrNil)))
		end
	end

	return service
end

return createTransportEscapeService
