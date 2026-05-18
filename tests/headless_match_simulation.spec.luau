--!strict

local MatchSimulation = require("../tests/harness/MatchSimulation")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertFalse(condition: boolean, label: string)
	if condition then
		error(string.format("FAIL [%s]: expected false, got true", label))
	end
	print(string.format("PASS [%s]", label))
end

local function createEscapeServiceFixture()
	local routeAttributes: { [string]: any } = {
		ThroughGapReachAllowed = true,
		RouteType = "TraversalGap",
		InSafeZone = false,
		SafeZoneType = nil,
		SafeZoneProtectionEndsAt = nil,
		TraversalGapBlockExempt = false,
		TraversalGapBlockState = "Idle",
		TraversalGapBlockStartupEndsAt = nil,
		TraversalGapBlockActiveEndsAt = nil,
		TraversalGapBlockExpiresAt = nil,
		TraversalGapBlockedByUserId = nil,
	}

	local routePart: any = {
		Name = "EscapeRoute_A",
		ClassName = "BasePart",
		Position = { x = 0, y = 0, z = 0 },
	}

	function routePart:IsA(className: string): boolean
		return className == "BasePart"
	end

	function routePart:GetAttribute(attributeName: string): any
		return routeAttributes[attributeName]
	end

	function routePart:SetAttribute(attributeName: string, value: any)
		routeAttributes[attributeName] = value
	end

	local escapeRoutesFolder: any = {
		ClassName = "Folder",
	}

	function escapeRoutesFolder:FindFirstChild(childName: string): any
		if childName == "EscapeRoute_A" then
			return routePart
		end
		return nil
	end

	function escapeRoutesFolder:GetDescendants(): { any }
		return { routePart }
	end

	local mapFolder: any = {
		ClassName = "Folder",
	}

	function mapFolder:FindFirstChild(childName: string): any
		if childName == "EscapeRoutes" then
			return escapeRoutesFolder
		end
		return nil
	end

	local workspaceService: any = {
		ClassName = "Workspace",
	}

	function workspaceService:FindFirstChild(childName: string): any
		if childName == "Map" then
			return mapFolder
		end
		return nil
	end

	local playersByUserId: { [number]: any } = {}
	local playersService: any = {}
	playersService.GetPlayerByUserId = function(userId: number)
		return playersByUserId[userId]
	end

	local replicatedStorageService: any = {
		WaitForChild = function(_name: string)
			return {
				WaitForChild = function(childName: string)
					if childName == "Config" then
						return {
							WaitForChild = function(configName: string)
								if configName == "RoleConfig" then
									return { Roles = { Giant = "Giant", Tinyfolk = "Tinyfolk" } }
								end
								if configName == "EscapeConfig" then
									return {
										EscapeRouteNamePrefix = "EscapeRoute",
										TriggerRadiusStuds = 10,
										RequestCooldownSeconds = 0,
										ThroughGapReachAllowedAttribute = "ThroughGapReachAllowed",
										RouteTypeAttribute = "RouteType",
										CrossingPhaseAttribute = "CrossingPhase",
										RequiredCrossingPhase = "MidCrossing",
										SafeZoneAttribute = "InSafeZone",
										SafeZoneTypeAttribute = "SafeZoneType",
										SafeZoneProtectionEndsAtAttribute = "SafeZoneProtectionEndsAt",
										SafeZoneTypes = {
											SharedHub = "SharedHub",
											RealmEntry = "RealmEntry",
											RealmExit = "RealmExit",
										},
										SafeZoneAbuseWindowSeconds = 2,
										SafeZoneAbuseThreshold = 3,
										SafeZoneAbuseLockoutSeconds = 1,
										TraversalGapBlockStartupSeconds = 1,
										TraversalGapBlockActiveSeconds = 4,
										TraversalGapBlockRequestCooldownSeconds = 0,
										TraversalGapBlockStateAttribute = "TraversalGapBlockState",
										TraversalGapBlockStartupEndsAtAttribute = "TraversalGapBlockStartupEndsAt",
										TraversalGapBlockActiveEndsAtAttribute = "TraversalGapBlockActiveEndsAt",
										TraversalGapBlockExpiresAtAttribute = "TraversalGapBlockExpiresAt",
										TraversalGapBlockedByUserIdAttribute = "TraversalGapBlockedByUserId",
										TraversalGapBlockExemptAttribute = "TraversalGapBlockExempt",
										SupportedThroughGapRouteTypes = { TraversalGap = true },
									}
								end
								return nil
							end,
						}
					end
					if childName == "GiantRealm" then
						return {
							WaitForChild = function(_configName: string)
								return nil
							end,
						}
					end
					return nil
				end,
			}
		end,
	}

	local mockGame: any = {}
	mockGame.GetService = function(serviceName: string)
		if serviceName == "Players" then
			return playersService
		end
		if serviceName == "ReplicatedStorage" then
			return replicatedStorageService
		end
		if serviceName == "Workspace" then
			return workspaceService
		end
		return nil
	end

	local currentTime = 100
	local EscapeServiceFactory = require("../src/ServerScriptService/Services/EscapeService.server")
	local escapeService = EscapeServiceFactory(mockGame, {
		autoInitialize = true,
		clock = function()
			return currentTime
		end,
		disableBlockExpirationSchedule = true,
		tinyfolkMovementTraitService = {
			OnValidRouteCrossing = function(_player: any, _routeId: string)
				return
			end,
		},
	})

	return {
		escapeService = escapeService,
		routeAttributes = routeAttributes,
		playersByUserId = playersByUserId,
		setNow = function(nextNow: number)
			currentTime = nextNow
		end,
	}
end

do
	local simA = MatchSimulation.new({ seed = 12345 })
	local simB = MatchSimulation.new({ seed = 12345 })
	local simC = MatchSimulation.new({ seed = 98765 })

	local a1 = simA:createFakePlayer({ role = "Tinyfolk" })
	local a2 = simA:createFakePlayer({ role = "Giant" })
	local b1 = simB:createFakePlayer({ role = "Tinyfolk" })
	local b2 = simB:createFakePlayer({ role = "Giant" })
	local c1 = simC:createFakePlayer({ role = "Tinyfolk" })

	assertEqual(a1.UserId, b1.UserId, "same seed first fake player id")
	assertEqual(a2.UserId, b2.UserId, "same seed second fake player id")
	assertEqual(a1.Name, b1.Name, "same seed first fake player name")
	assertFalse(a1.UserId == c1.UserId, "different seed changes generated id")
end

do
	local sim = MatchSimulation.new({ seed = 88 })
	local p1 = sim:addPlayer(10, "RoleAlpha", { role = "Tinyfolk" })
	local p2 = sim:addPlayer(20, "RoleBeta", { role = "Giant" })

	sim:queueAction(1, "assignRole", { userId = 10, role = "Giant" })
	sim:queueAction(1, "assignRole", { userId = 20, role = "Tinyfolk" })
	sim:advanceTick()

	assertEqual(p1:GetAttribute("Role"), "Giant", "assignRole sets Giant")
	assertEqual(p2:GetAttribute("Role"), "Tinyfolk", "assignRole sets Tinyfolk")
	assertEqual(sim:getLog()[3], "[Tick 1] Assigned role Giant to player RoleAlpha", "log preserves queued order first")
	assertEqual(
		sim:getLog()[4],
		"[Tick 1] Assigned role Tinyfolk to player RoleBeta",
		"log preserves queued order second"
	)
end

do
	local sim = MatchSimulation.new({ seed = 99 })
	sim:addPlayer(1, "TickUser", { role = "Tinyfolk" })
	sim:queueAction(2, "assignRole", { userId = 1, role = "Giant" })
	assertEqual(sim.tick, 0, "tick starts at zero")
	sim:advanceTick()
	assertEqual(sim.tick, 1, "advanceTick increments by one")
	assertEqual(sim:getLog()[2], nil, "no action executed before scheduled tick")
	sim:advanceTick()
	assertEqual(sim.tick, 2, "advanceTick increments deterministically")
	assertEqual(
		sim:getLog()[2],
		"[Tick 2] Assigned role Giant to player TickUser",
		"scheduled action runs at target tick"
	)
end

do
	local fixture = createEscapeServiceFixture()
	local sim = MatchSimulation.new({ seed = 101, escapeService = fixture.escapeService })
	local giant = sim:addPlayer(1, "GiantUser", { role = "Giant" })
	local tinyfolk = sim:addPlayer(2, "TinyfolkUser", { role = "Tinyfolk", crossingPhase = "MidCrossing" })
	fixture.playersByUserId[2] = tinyfolk
	fixture.setNow(200)

	sim:queueAction(1, "throughGapReach", {
		userId = 1,
		target = tinyfolk,
		request = {
			routeId = "EscapeRoute_A",
			lineOfSightCheck = function()
				return true
			end,
		},
	})

	sim:queueAction(1, "attemptEscape", {
		userId = 2,
		routeId = "EscapeRoute_A",
	})

	sim:queueAction(1, "blockTraversalGap", {
		userId = 1,
		routeId = "EscapeRoute_A",
	})

	sim:advanceTick()

	local results = sim:getResults()
	assertEqual(results[3].result.accepted, true, "through-gap reach valid via EscapeService")
	assertEqual(results[4].result.accepted, true, "escape attempt accepted via EscapeService")
	assertEqual(results[5].result.accepted, true, "traversal-gap block accepted via EscapeService")
	assertEqual(giant:GetAttribute("Role"), "Giant", "existing role remains unchanged")
end

do
	local fixture = createEscapeServiceFixture()
	fixture.routeAttributes.InSafeZone = true
	local sim = MatchSimulation.new({ seed = 202, escapeService = fixture.escapeService })
	local giant = sim:addPlayer(3, "SafeZoneGiant", { role = "Giant" })
	local tinyfolk = sim:addPlayer(4, "SafeZoneTinyfolk", { role = "Tinyfolk", crossingPhase = "MidCrossing" })
	fixture.playersByUserId[4] = tinyfolk

	sim:queueAction(1, "throughGapReach", {
		userId = 3,
		target = tinyfolk,
		request = {
			routeId = "EscapeRoute_A",
			lineOfSightCheck = function()
				return true
			end,
		},
	})

	sim:queueAction(1, "attemptEscape", {
		userId = 4,
		routeId = "EscapeRoute_A",
	})

	sim:advanceTick()

	local results = sim:getResults()
	assertEqual(results[3].result.accepted, false, "safe-zone rejects through-gap reach")
	assertEqual(
		results[4].result.accepted,
		true,
		"safe-zone route does not reject direct escape attempt in current service"
	)
	assertEqual(results[4].result.reason, "accepted", "escape attempt reason is accepted on current service path")
	assertEqual(giant:GetAttribute("Role"), "Giant", "safe-zone flow does not mutate role")
end

do
	local sim = MatchSimulation.new({ seed = 303 })
	sim:addPlayer(11, "UnsupportedUser", { role = "Tinyfolk" })
	sim:queueAction(1, "captureAttempt", { userId = 11 })
	sim:queueAction(1, "rescueAttempt", { userId = 11 })
	sim:queueAction(1, "scoreEvent", { userId = 11 })
	sim:advanceTick()

	local results = sim:getResults()
	assertEqual(results[2].result.reason, "not_implemented", "capture unsupported explicit")
	assertEqual(results[3].result.reason, "not_implemented", "rescue unsupported explicit")
	assertEqual(results[4].result.reason, "not_implemented", "scoring unsupported explicit")
end

do
	local fixture = createEscapeServiceFixture()
	local downedByUserId: { [number]: any } = {}
	_G._RoleService_QueryAPI = {
		SetDowned = function(userId: number, durationSeconds: number, _reason: string): boolean
			local player = fixture.playersByUserId[userId]
			if player == nil then
				return false
			end
			if player:GetAttribute("Role") ~= "Tinyfolk" then
				return false
			end
			downedByUserId[userId] = {
				expiresAt = 100 + durationSeconds,
				selfRecoveryProgress = 0,
				selfRecoveryCap = 0.5,
				status = "Downed",
			}
			player:SetAttribute("DownedState", "Downed")
			player:SetAttribute("DownedIsDowned", true)
			player:SetAttribute("DownedSelfRecoveryProgress", 0)
			return true
		end,
		SelfRecoverDowned = function(userId: number, progressDelta: number): boolean
			local state = downedByUserId[userId]
			local player = fixture.playersByUserId[userId]
			if state == nil or player == nil then
				return false
			end
			state.selfRecoveryProgress = math.min(state.selfRecoveryProgress + progressDelta, state.selfRecoveryCap)
			if state.selfRecoveryProgress >= state.selfRecoveryCap then
				state.status = "SelfRecoveryCapped"
				player:SetAttribute("DownedState", "SelfRecoveryCapped")
			end
			player:SetAttribute("DownedSelfRecoveryProgress", state.selfRecoveryProgress)
			return true
		end,
		TickDownedStates = function(nowSeconds: number)
			for userId, state in pairs(downedByUserId) do
				local player = fixture.playersByUserId[userId]
				if player ~= nil and nowSeconds >= state.expiresAt then
					state.status = "SafeResolved"
					player:SetAttribute("DownedState", "SafeResolved")
					player:SetAttribute("DownedIsDowned", false)
				end
			end
		end,
		IsPlayerDowned = function(userId: number): boolean
			local state = downedByUserId[userId]
			if state == nil then
				return false
			end
			return state.status == "Downed" or state.status == "SelfRecoveryCapped"
		end,
		CanPlayerPerformInteraction = function(userId: number, interactionName: string): boolean
			if interactionName ~= "escapeAttempt" then
				return true
			end
			local state = downedByUserId[userId]
			if state == nil then
				return true
			end
			local status = tostring(state.status)
			if status == "Downed" or status == "SelfRecoveryCapped" then
				return false
			end
			return true
		end,
	}

	local simulation = MatchSimulation.new({ seed = 12345, escapeService = fixture.escapeService })
	local tinyfolk = simulation:addPlayer(501, "DownedTinyfolk", { role = "Tinyfolk" })
	local giant = simulation:addPlayer(502, "DownedGiant", { role = "Giant" })
	fixture.playersByUserId[tinyfolk.UserId] = tinyfolk
	fixture.playersByUserId[giant.UserId] = giant

	simulation:queueAction(1, "downTinyfolk", {
		userId = tinyfolk.UserId,
		durationSeconds = 5,
		reason = "headless_downed",
	})
	simulation:queueAction(1, "attemptEscapeWhileDowned", {
		userId = tinyfolk.UserId,
		routeId = "EscapeRoute_A",
	})
	simulation:queueAction(1, "selfRecoverDowned", {
		userId = tinyfolk.UserId,
		progressDelta = 0.7,
	})
	simulation:queueAction(1, "allyRecoverDowned", {
		userId = giant.UserId,
		targetUserId = tinyfolk.UserId,
	})
	simulation:advanceTick()

	assertEqual(
		tinyfolk:GetAttribute("DownedState"),
		"SelfRecoveryCapped",
		"self recovery reaches cap but not full recovery"
	)
	local results = simulation:getResults()
	assertEqual(results[3].result.accepted, true, "downTinyfolk accepted for Tinyfolk")
	assertEqual(results[4].result.accepted, false, "attemptEscapeWhileDowned rejected")
	assertEqual(results[4].result.reason, "actor_downed", "attemptEscapeWhileDowned rejection reason")
	assertEqual(results[6].result.reason, "not_implemented", "unsupported ally recovery explicit not_implemented")

	simulation:queueAction(2, "tickDowned", {
		userId = tinyfolk.UserId,
		now = 106,
	})
	simulation:advanceTick()
	assertEqual(
		tinyfolk:GetAttribute("DownedState"),
		"SafeResolved",
		"downed state expiration resolves in headless flow"
	)

	simulation:queueAction(3, "downTinyfolk", {
		userId = giant.UserId,
		durationSeconds = 5,
		reason = "headless_invalid_role",
	})
	simulation:advanceTick()
	local finalResults = simulation:getResults()
	assertEqual(finalResults[#finalResults].result.accepted, false, "non-Tinyfolk cannot enter downed state")
end

do
	local carriedByUserId: { [number]: number } = {}
	local carriedTargetByGiantUserId: { [number]: number } = {}
	local counterplayProgressByUserId: { [number]: number } = {}
	local fakeGrabService = {
		RequestGrab = function(giantUserId: number, targetUserId: number, _now: number): any
			if carriedTargetByGiantUserId[giantUserId] ~= nil then
				return {
					accepted = false,
					reason = "carry_capacity_full",
					carrierLoadSnapshot = {
						slotsUsed = 1,
						capacity = 1,
						isEncumbered = true,
						isAtCapacity = true,
						isOverloaded = true,
						speedMultiplier = 0.8,
					},
				}
			end
			if carriedByUserId[targetUserId] ~= nil then
				return { accepted = false, reason = "target_already_carried" }
			end
			carriedByUserId[targetUserId] = giantUserId
			carriedTargetByGiantUserId[giantUserId] = targetUserId
			counterplayProgressByUserId[targetUserId] = 0
			return {
				accepted = true,
				reason = "accepted",
				snapshot = {
					state = "Carried",
					carriedByUserId = giantUserId,
					targetUserId = targetUserId,
					counterplayProgress = 0,
					counterplayRequired = 2,
					isCarried = true,
				},
				carrierLoadSnapshot = {
					slotsUsed = 1,
					capacity = 1,
					isEncumbered = true,
					isAtCapacity = true,
					isOverloaded = true,
					speedMultiplier = 0.8,
				},
			}
		end,
		RequestCounterplay = function(targetUserId: number, _now: number): any
			if carriedByUserId[targetUserId] == nil then
				return { accepted = false, reason = "not_carried" }
			end
			local giantUserId = carriedByUserId[targetUserId]
			local progress = (counterplayProgressByUserId[targetUserId] or 0) + 1
			counterplayProgressByUserId[targetUserId] = progress
			if progress >= 2 then
				carriedByUserId[targetUserId] = nil
				carriedTargetByGiantUserId[giantUserId] = nil
				return {
					accepted = true,
					reason = "accepted",
					snapshot = {
						state = "Released",
						counterplayProgress = progress,
						counterplayRequired = 2,
						releaseReason = "counterplay_completed",
						isCarried = false,
					},
					carrierLoadSnapshot = {
						slotsUsed = 0,
						capacity = 1,
						isEncumbered = false,
						isAtCapacity = false,
						isOverloaded = false,
						speedMultiplier = 1,
					},
				}
			end
			return {
				accepted = true,
				reason = "accepted",
				snapshot = {
					state = "Counterplay",
					counterplayProgress = progress,
					counterplayRequired = 2,
					isCarried = true,
				},
			}
		end,
		GetCarrierLoadSnapshot = function(giantUserId: number): any
			local slotsUsed = if carriedTargetByGiantUserId[giantUserId] ~= nil then 1 else 0
			return {
				slotsUsed = slotsUsed,
				capacity = 1,
				isEncumbered = slotsUsed > 0,
				isAtCapacity = slotsUsed >= 1,
				isOverloaded = slotsUsed >= 1,
				speedMultiplier = if slotsUsed > 0 then 0.8 else 1,
			}
		end,
	}

	local sim = MatchSimulation.new({ seed = 404, grabService = fakeGrabService })
	local giant = sim:addPlayer(601, "HarnessGiant", { role = "Giant" })
	local tinyfolk = sim:addPlayer(602, "HarnessTinyfolk", { role = "Tinyfolk" })
	local extraTinyfolk = sim:addPlayer(603, "HarnessExtraTinyfolk", { role = "Tinyfolk" })

	sim:queueAction(1, "grabTinyfolk", {
		userId = giant.UserId,
		targetUserId = tinyfolk.UserId,
	})
	sim:queueAction(1, "grabTinyfolk", {
		userId = giant.UserId,
		targetUserId = extraTinyfolk.UserId,
	})
	sim:queueAction(2, "carriedCounterplay", {
		userId = tinyfolk.UserId,
	})
	sim:queueAction(3, "carriedCounterplay", {
		userId = tinyfolk.UserId,
	})
	sim:advanceTick(3)

	local results = sim:getResults()
	assertEqual(results[4].action, "grabTinyfolk", "grab action recorded")
	assertEqual(results[4].result.accepted, true, "headless grab accepted")
	assertEqual(results[4].result.carrierLoadSnapshot.slotsUsed, 1, "headless grab exposes carrier load")
	assertEqual(results[5].result.accepted, false, "headless repeated grab rejected")
	assertEqual(results[5].result.reason, "carry_capacity_full", "headless repeated grab capacity reason")
	assertEqual(results[6].result.snapshot.state, "Counterplay", "headless counterplay state exposed")
	assertEqual(results[7].result.snapshot.state, "Released", "headless counterplay release exposed")
	assertEqual(results[7].result.carrierLoadSnapshot.slotsUsed, 0, "headless release clears carrier load")
	assertEqual(
		results[7].result.snapshot.releaseReason,
		"counterplay_completed",
		"headless release reason exposed"
	)
end

print("headless_match_simulation: all checks passed")
