--!strict

local RealmAdmissionLocationCaller = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmAdmissionLocationCaller"))
	else (require :: any)("./RealmAdmissionLocationCaller")

local AdmissionQueueProducer: any = {}

type EnqueueResult = {
	accepted: boolean,
	reason: string,
	snapshot: any?,
	payload: any?,
}

local DEFAULT_EXPIRATION_SECONDS = 600

local function isFiniteNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return true
end

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function normalizeMemberUserIds(values: any): { number }?
	if type(values) ~= "table" then
		return nil
	end

	local normalized: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, value in ipairs(values) do
		if type(value) ~= "number" or value <= 0 or value % 1 ~= 0 then
			return nil
		end
		local userId = value :: number
		if seen[userId] ~= true then
			seen[userId] = true
			table.insert(normalized, userId)
		end
	end

	if #normalized <= 0 then
		return nil
	end

	table.sort(normalized)
	return normalized
end

local function resolveExpirationSeconds(config: any): number
	if
		type(config) == "table"
		and isFiniteNumber(config.defaultExpirationSeconds)
		and config.defaultExpirationSeconds > 0
	then
		return config.defaultExpirationSeconds
	end
	return DEFAULT_EXPIRATION_SECONDS
end

function AdmissionQueueProducer.Create(config: any?): any
	local configAny: any = config
	local nowFn = if type(configAny) == "table" and type(configAny.now) == "function" then configAny.now else os.clock
	local queryApiResolver = if type(configAny) == "table" and type(configAny.queryApiResolver) == "function"
		then configAny.queryApiResolver
		else function()
			return nil
		end
	local defaultExpirationSeconds = resolveExpirationSeconds(configAny)

	local producer: any = {}

	function producer.Enqueue(input: any): EnqueueResult
		if type(input) ~= "table" then
			return {
				accepted = false,
				reason = "admission_payload_invalid",
				snapshot = nil,
				payload = nil,
			}
		end

		if not isNonEmptyString(input.operationId) then
			return {
				accepted = false,
				reason = "operation_id_invalid",
				snapshot = nil,
				payload = nil,
			}
		end
		if not isNonEmptyString(input.partyId) then
			return {
				accepted = false,
				reason = "party_id_invalid",
				snapshot = nil,
				payload = nil,
			}
		end
		if not isNonEmptyString(input.targetRealmId) then
			return {
				accepted = false,
				reason = "target_realm_id_invalid",
				snapshot = nil,
				payload = nil,
			}
		end
		if not isNonEmptyString(input.entryType) then
			return {
				accepted = false,
				reason = "entry_type_invalid",
				snapshot = nil,
				payload = nil,
			}
		end

		local normalizedMembers = normalizeMemberUserIds(input.partyMemberUserIds)
		if normalizedMembers == nil then
			return {
				accepted = false,
				reason = "admission_party_members_invalid",
				snapshot = nil,
				payload = nil,
			}
		end

		local createdAt = if isFiniteNumber(input.createdAt) and input.createdAt >= 0 then input.createdAt else nowFn()
		if not isFiniteNumber(createdAt) or createdAt < 0 then
			return {
				accepted = false,
				reason = "created_at_invalid",
				snapshot = nil,
				payload = nil,
			}
		end

		local expiration = input.expiration
		if not (isFiniteNumber(expiration) and expiration > createdAt) then
			local expirationSeconds = if isFiniteNumber(input.expirationSeconds)
					and input.expirationSeconds > 0
				then input.expirationSeconds
				else defaultExpirationSeconds
			expiration = createdAt + expirationSeconds
		end

		local payload = {
			operationId = input.operationId,
			partyId = input.partyId,
			targetRealmId = input.targetRealmId,
			entryType = input.entryType,
			priority = input.priority,
			createdAt = createdAt,
			expiration = expiration,
			partySize = #normalizedMembers,
			partyMemberUserIds = normalizedMembers,
			retryCount = if isFiniteNumber(input.retryCount) and input.retryCount >= 0 then input.retryCount else 0,
		}

		local locationBeginInput = {
			targetRealmId = input.targetRealmId,
			entryType = input.entryType,
			assignmentReason = input.assignmentReason,
			now = os.time(),
		}
		local locationBeginResult =
			RealmAdmissionLocationCaller.ApplyBeginForAdmissionMembers(normalizedMembers, locationBeginInput)
		if type(locationBeginResult) ~= "table" or locationBeginResult.accepted ~= true then
			return {
				accepted = false,
				reason = if type(locationBeginResult) == "table"
						and type(locationBeginResult.reason) == "string"
					then locationBeginResult.reason
					else "location_transition_failed",
				snapshot = nil,
				payload = payload,
			}
		end

		local queueApi = queryApiResolver()
		if type(queueApi) ~= "table" or type((queueApi :: any).EnqueueAdmission) ~= "function" then
			return {
				accepted = false,
				reason = "admission_queue_unavailable",
				snapshot = nil,
				payload = payload,
			}
		end

		local enqueueOk, enqueueResult = pcall(function()
			return (queueApi :: any).EnqueueAdmission(payload)
		end)
		if not enqueueOk then
			RealmAdmissionLocationCaller.ApplyAbortRollbackForMembers(normalizedMembers, locationBeginInput)
			return {
				accepted = false,
				reason = "admission_enqueue_failed",
				snapshot = nil,
				payload = payload,
			}
		end

		if type(enqueueResult) ~= "table" then
			RealmAdmissionLocationCaller.ApplyAbortRollbackForMembers(normalizedMembers, locationBeginInput)
			return {
				accepted = false,
				reason = "admission_enqueue_failed",
				snapshot = nil,
				payload = payload,
			}
		end

		if enqueueResult.accepted ~= true then
			RealmAdmissionLocationCaller.ApplyAbortRollbackForMembers(normalizedMembers, locationBeginInput)
			return {
				accepted = false,
				reason = if type(enqueueResult.reason) == "string"
					then enqueueResult.reason
					else "admission_enqueue_failed",
				snapshot = enqueueResult.snapshot,
				payload = payload,
			}
		end

		return {
			accepted = true,
			reason = if type(enqueueResult.reason) == "string" then enqueueResult.reason else "accepted",
			snapshot = enqueueResult.snapshot,
			payload = payload,
		}
	end

	return producer
end

return AdmissionQueueProducer
