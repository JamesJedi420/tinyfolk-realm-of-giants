--!strict

local FrontDeskHubPresentation = require("../src/ReplicatedStorage/Shared/FrontDeskHubPresentation")

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function serialize(value: any): string
	if type(value) ~= "table" then
		return string.format("%s:%s", type(value), tostring(value))
	end

	local keys: { any } = {}
	for key in pairs(value) do
		table.insert(keys, key)
	end
	table.sort(keys, function(left: any, right: any): boolean
		return tostring(left) < tostring(right)
	end)

	local parts: { string } = {}
	for _, key in ipairs(keys) do
		table.insert(parts, string.format("[%s]=%s", tostring(key), serialize(value[key])))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

do
	local card = FrontDeskHubPresentation.RenderOpportunityCard({
		id = "procurement_shortfall",
		title = "Procurement shortfall",
		body = "Wood reserves are below the next build threshold.",
		detail = "Ask the warehouse crew to reprioritize.",
		severity = "warning",
		actionLabel = "Open Procurement",
		source = "procurement",
	})

	assertTrue(card ~= nil, "shared opportunity renderer returns a card")
	assertEqual(card.id, "procurement_shortfall", "renderer preserves id")
	assertEqual(card.title, "Procurement shortfall", "renderer preserves title")
	assertEqual(card.severity, "warning", "renderer preserves normalized warning severity")
	assertEqual(card.source, "procurement", "renderer preserves source")
end

do
	local game = {
		procurementOpportunities = {
			{
				id = "procurement_low_wood",
				title = "Low wood stock",
				body = "Wood intake is below planned build demand.",
				detail = "Granary and warehouse queues need attention.",
				severity = "warning",
				actionLabel = "Review Stock",
				source = "procurement",
			},
		},
		staffingReadinessOpportunities = {
			{
				id = "staffing_missing_builder",
				title = "Builder coverage missing",
				body = "No builder is assigned to the next construction window.",
				detail = "Assign a specialist before the queue opens.",
				severity = "danger",
				actionLabel = "Assign Staff",
				source = "staffing_readiness",
			},
		},
	}
	local before = serialize(game)

	local view = FrontDeskHubPresentation.getFrontDeskHubView(game)

	assertEqual(serialize(game), before, "getFrontDeskHubView remains mutation-free with both opportunity cards active")
	assertTrue(view.hasOpportunities, "view reports active opportunities")
	assertEqual(#view.opportunityCards, 2, "view renders both opportunity cards")
	assertEqual(view.opportunityCards[1].id, "staffing_missing_builder", "danger opportunity sorts before warning")
	assertEqual(view.opportunityCards[2].id, "procurement_low_wood", "warning opportunity sorts after danger")
	assertEqual(view.opportunityCards[1].source, "staffing_readiness", "staffing card uses shared card shape")
	assertEqual(view.opportunityCards[2].source, "procurement", "procurement card uses shared card shape")
end

do
	local view = FrontDeskHubPresentation.getFrontDeskHubView({
		opportunities = {
			{
				id = "z_warning",
				severity = "warning",
			},
			{
				id = "a_warning",
				severity = "warning",
			},
		},
	})

	assertEqual(view.opportunityCards[1].id, "a_warning", "same-severity cards sort by deterministic id order")
	assertEqual(view.opportunityCards[2].id, "z_warning", "same-severity high id sorts second")
end

print("front_desk_hub_presentation: all checks passed")
