--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)
local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
	}

	function node.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string): any
		return self._Children[childName]
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
end

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "EventLogConfig", "../../ReplicatedStorage/Shared/Config/EventLogConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "EventLogState", "../../ReplicatedStorage/Shared/GiantRealm/EventLogState")

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	error(string.format("unsupported service: %s", serviceName))
	return nil
end

game = fakeGame

local queryApi = require("../src/ServerScriptService/Services/EventLogService.server")
assertTrue(type(queryApi) == "table", "service exposes query api")
assertTrue(type(_G._EventLogService_QueryAPI) == "table", "service stores global query api")
assertTrue(type(queryApi.RecordEvent) == "function", "query api exposes RecordEvent")
assertTrue(type(queryApi.GetRecentEvents) == "function", "query api exposes GetRecentEvents")

queryApi.ResetForTests()

local accepted = queryApi.RecordEvent("capture", "capture accepted", "info", 10, { userId = 5101 })
assertTrue(accepted.accepted, "record event accepts valid payload")
assertEqual(accepted.reason, "accepted", "record event accepted reason")
assertEqual(accepted.record.sequence, 1, "record event sequence")
assertEqual(accepted.record.category, "capture", "record event category")
assertEqual(accepted.record.message, "capture accepted", "record event message")
assertEqual(accepted.record.severity, "info", "record event severity")

local invalid = queryApi.RecordEvent("", "capture accepted", "info", 11, nil)
assertFalse(invalid.accepted, "record event rejects invalid category")
assertEqual(invalid.reason, "category_invalid", "record event invalid category reason")

local fromPayload = queryApi.RecordEventFromPayload({
	category = "score",
	message = "score event accepted",
	severity = "warn",
	timestamp = 12,
	metadata = { points = 100 },
})
assertTrue(fromPayload.accepted, "payload record accepted")
assertEqual(fromPayload.record.sequence, 2, "payload record sequence")

local systemEmitter = function(systemName: string, message: string)
	return queryApi.RecordEvent(systemName, message, nil, 13, { source = "system" })
end
local emitted = systemEmitter("rescue_contract", "contract accepted")
assertTrue(emitted.accepted, "game system emitter accepted")
assertEqual(emitted.record.severity, "info", "game system emitter uses default severity")

local recent = queryApi.GetRecentEvents(2)
assertEqual(#recent, 2, "recent event limit")
assertEqual(recent[1].message, "contract accepted", "recent newest first")
assertEqual(recent[2].message, "score event accepted", "recent second newest")

local snapshot = queryApi.GetStateSnapshot()
assertEqual(snapshot.eventCount, 3, "state snapshot event count")
assertEqual(snapshot.sequence, 3, "state snapshot sequence")
assertEqual(snapshot.lastReason, "accepted", "state snapshot last reason")

queryApi.ResetForTests()
local resetSnapshot = queryApi.GetStateSnapshot()
assertEqual(resetSnapshot.eventCount, 0, "reset clears events")
assertEqual(resetSnapshot.sequence, 0, "reset clears sequence")

print("event_log_service_runtime_entrypoint: all checks passed")
