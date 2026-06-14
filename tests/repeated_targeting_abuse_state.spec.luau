local RepeatedTargetingAbuseState = require("../src/ReplicatedStorage/Shared/GiantRealm/RepeatedTargetingAbuseState")
local RepeatedTargetingAbuseConfig = require("../src/ReplicatedStorage/Shared/Config/RepeatedTargetingAbuseConfig")

local function assertTrue(value: any, message: string)
	if value ~= true then
		error(message)
	end
	print("PASS [" .. message .. "]")
end

local function assertEqual(actual: any, expected: any, message: string)
	if actual ~= expected then
		error(string.format("%s (expected=%s actual=%s)", message, tostring(expected), tostring(actual)))
	end
	print("PASS [" .. message .. "]")
end

local state = RepeatedTargetingAbuseState.NewState()
local custodianUserId = 1001
local targetUserId = 2002

for index = 1, RepeatedTargetingAbuseConfig.PairRepeatCaptureThreshold - 1 do
	local result = RepeatedTargetingAbuseState.RecordEvent(state, {
		now = index,
		kind = RepeatedTargetingAbuseState.EventKinds.CaptureStart,
		custodianUserId = custodianUserId,
		targetUserId = targetUserId,
	}, RepeatedTargetingAbuseConfig)
	state = result.state
	assertEqual(#result.detections, 0, "pair repeat below threshold has no detection")
end

local pairRepeatResult = RepeatedTargetingAbuseState.RecordEvent(state, {
	now = 4,
	kind = RepeatedTargetingAbuseState.EventKinds.CaptureStart,
	custodianUserId = custodianUserId,
	targetUserId = targetUserId,
}, RepeatedTargetingAbuseConfig)
state = pairRepeatResult.state
assertEqual(#pairRepeatResult.detections, 1, "pair repeat threshold emits one detection")
assertEqual(
	pairRepeatResult.detections[1].patternKind,
	RepeatedTargetingAbuseState.PatternKinds.PairRepeatTargeting,
	"pair repeat pattern kind"
)

local loopState = RepeatedTargetingAbuseState.NewState()
for index = 1, RepeatedTargetingAbuseConfig.TargetCustodyLoopThreshold - 1 do
	local result = RepeatedTargetingAbuseState.RecordEvent(loopState, {
		now = index,
		kind = RepeatedTargetingAbuseState.EventKinds.CaptureStart,
		custodianUserId = custodianUserId + index,
		targetUserId = targetUserId,
	}, RepeatedTargetingAbuseConfig)
	loopState = result.state
end
local loopResult = RepeatedTargetingAbuseState.RecordEvent(loopState, {
	now = 10,
	kind = RepeatedTargetingAbuseState.EventKinds.CustodyEnd,
	custodianUserId = custodianUserId,
	targetUserId = targetUserId,
	endReason = "released",
}, RepeatedTargetingAbuseConfig)
assertEqual(#loopResult.detections, 1, "target custody loop threshold emits detection")
assertEqual(
	loopResult.detections[1].patternKind,
	RepeatedTargetingAbuseState.PatternKinds.TargetCustodyLoop,
	"target custody loop pattern kind"
)

local transferState = RepeatedTargetingAbuseState.NewState()
local outgoingUserId = 3001
local incomingUserId = 3002
local firstTransfer = RepeatedTargetingAbuseState.RecordEvent(transferState, {
	now = 1,
	kind = RepeatedTargetingAbuseState.EventKinds.CustodyTransfer,
	targetUserId = targetUserId,
	outgoingCustodianUserId = outgoingUserId,
	incomingCustodianUserId = incomingUserId,
}, RepeatedTargetingAbuseConfig)
transferState = firstTransfer.state
assertEqual(#firstTransfer.detections, 0, "first transfer does not emit loop detection")

local secondTransfer = RepeatedTargetingAbuseState.RecordEvent(transferState, {
	now = 2,
	kind = RepeatedTargetingAbuseState.EventKinds.CustodyTransfer,
	targetUserId = targetUserId,
	outgoingCustodianUserId = incomingUserId,
	incomingCustodianUserId = outgoingUserId,
}, RepeatedTargetingAbuseConfig)
assertEqual(#secondTransfer.detections, 1, "ping-pong transfer emits loop detection")
assertEqual(
	secondTransfer.detections[1].patternKind,
	RepeatedTargetingAbuseState.PatternKinds.CustodyTransferLoop,
	"transfer loop pattern kind"
)

local cycleState = RepeatedTargetingAbuseState.NewState()
for cycleIndex = 1, RepeatedTargetingAbuseConfig.ShortCycleThreshold do
	local captureAt = cycleIndex * 20
	local endAt = captureAt + 5
	local captureResult = RepeatedTargetingAbuseState.RecordEvent(cycleState, {
		now = captureAt,
		kind = RepeatedTargetingAbuseState.EventKinds.CaptureStart,
		custodianUserId = custodianUserId,
		targetUserId = targetUserId,
	}, RepeatedTargetingAbuseConfig)
	cycleState = captureResult.state
	local endResult = RepeatedTargetingAbuseState.RecordEvent(cycleState, {
		now = endAt,
		kind = RepeatedTargetingAbuseState.EventKinds.CustodyEnd,
		custodianUserId = custodianUserId,
		targetUserId = targetUserId,
		endReason = "released",
	}, RepeatedTargetingAbuseConfig)
	cycleState = endResult.state
	if cycleIndex < RepeatedTargetingAbuseConfig.ShortCycleThreshold then
		assertEqual(#endResult.detections, 0, "short cycle below threshold has no detection")
	else
		assertEqual(#endResult.detections, 1, "short cycle threshold emits detection")
		assertEqual(
			endResult.detections[1].patternKind,
			RepeatedTargetingAbuseState.PatternKinds.ShortCustodyCycle,
			"short custody cycle pattern kind"
		)
	end
end

local rewardCapResult = RepeatedTargetingAbuseState.RecordEvent(RepeatedTargetingAbuseState.NewState(), {
	now = 1,
	kind = RepeatedTargetingAbuseState.EventKinds.PairRewardCap,
	custodianUserId = custodianUserId,
	targetUserId = targetUserId,
	pairRewardCount = 4,
	operationId = "containment-released-1",
}, RepeatedTargetingAbuseConfig)
assertEqual(#rewardCapResult.detections, 1, "pair reward cap emits detection")
assertEqual(
	rewardCapResult.detections[1].patternKind,
	RepeatedTargetingAbuseState.PatternKinds.PairRewardCapReached,
	"pair reward cap pattern kind"
)

local duplicateState = pairRepeatResult.state
local duplicateResult = RepeatedTargetingAbuseState.RecordEvent(duplicateState, {
	now = 5,
	kind = RepeatedTargetingAbuseState.EventKinds.CaptureStart,
	custodianUserId = custodianUserId,
	targetUserId = targetUserId,
}, RepeatedTargetingAbuseConfig)
assertEqual(#duplicateResult.detections, 0, "detection cooldown suppresses duplicate alert")

local snapshot = RepeatedTargetingAbuseState.GetPairSnapshot(
	pairRepeatResult.state,
	custodianUserId,
	targetUserId,
	4,
	RepeatedTargetingAbuseConfig
)
assertTrue(
	snapshot.captureCount >= RepeatedTargetingAbuseConfig.PairRepeatCaptureThreshold,
	"pair snapshot reflects capture count"
)

print("repeated_targeting_abuse_state: all checks passed")
