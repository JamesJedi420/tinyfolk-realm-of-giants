--!strict

local TrailPressureLogic = require("../src/ReplicatedStorage/Shared/TinyfolkStatus/TrailPressureLogic")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	if not value then
		error(string.format("FAIL [%s]: expected true", label))
	end
	print(string.format("PASS [%s]", label))
end

local config = {
	TrailLifetimeSeconds = 5,
	TrailMaxPoints = 3,
	TrailSampleMinDistanceStuds = 4,
	TrailSampleMinIntervalSeconds = 0.25,
}

local function position(x: number, y: number, z: number): any
	return { X = x, Y = y, Z = z }
end

do
	local state = TrailPressureLogic.NewState()
	state = TrailPressureLogic.ResolveSample(state, config, {
		now = 10,
		position = position(0, 0, 0),
		shouldEmit = true,
	})
	assertEqual(#state.samples, 1, "first sample accepted")

	state = TrailPressureLogic.ResolveSample(state, config, {
		now = 10.1,
		position = position(10, 0, 0),
		shouldEmit = true,
	})
	assertEqual(#state.samples, 1, "min interval gates repeated sample")

	state = TrailPressureLogic.ResolveSample(state, config, {
		now = 10.5,
		position = position(2, 0, 0),
		shouldEmit = true,
	})
	assertEqual(#state.samples, 1, "min distance gates short move")

	state = TrailPressureLogic.ResolveSample(state, config, {
		now = 11,
		position = position(6, 0, 0),
		shouldEmit = true,
	})
	assertEqual(#state.samples, 2, "later distant sample accepted")

	local snapshot = TrailPressureLogic.BuildSnapshot(state, config, 11)
	assertTrue(snapshot.hasPressure, "snapshot reports pressure after two samples")
	assertEqual(snapshot.segmentCount, 1, "single segment built")
	assertEqual(snapshot.oldestAt, 10, "snapshot oldest timestamp")
	assertEqual(snapshot.newestAt, 11, "snapshot newest timestamp")
	assertEqual(snapshot.segments[1].fromPosition, nil, "snapshot does not expose exact fromPosition")
	assertEqual(snapshot.segments[1].toPosition, nil, "snapshot does not expose exact toPosition")
	assertEqual(snapshot.segments[1].direction, "east", "snapshot exposes coarse direction bucket")
end

do
	local state = TrailPressureLogic.NewState()
	state = TrailPressureLogic.ResolveSample(state, config, {
		now = 20,
		position = position(0, 0, 0),
		shouldEmit = true,
	})
	state = TrailPressureLogic.ResolveSample(state, config, {
		now = 21,
		position = position(5, 0, 0),
		shouldEmit = true,
	})
	state = TrailPressureLogic.ResolveSample(state, config, {
		now = 22,
		position = position(10, 0, 0),
		shouldEmit = true,
	})
	state = TrailPressureLogic.ResolveSample(state, config, {
		now = 23,
		position = position(15, 0, 0),
		shouldEmit = true,
	})
	assertEqual(#state.samples, 3, "max points bounds history")
	assertEqual(state.samples[1].at, 21, "oldest sample trimmed first")

	state = TrailPressureLogic.ResolveSample(state, config, {
		now = 29,
		shouldEmit = false,
	})
	assertEqual(#state.samples, 0, "expired samples prune on non-emitting tick")

	local snapshot = TrailPressureLogic.BuildSnapshot(state, config, 29)
	assertEqual(snapshot.segmentCount, 0, "empty state yields no segments")
	assertEqual(snapshot.hasPressure, false, "empty state yields no pressure")
end

print("trail_pressure_logic: all checks passed")
