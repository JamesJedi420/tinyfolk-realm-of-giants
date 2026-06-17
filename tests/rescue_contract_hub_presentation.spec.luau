--!nocheck
local RescueContractHubPresentation =
	require("../src/ReplicatedStorage/Shared/GiantRealm/RescueContractHubPresentation")

local function assertTrue(value: boolean, label: string)
	if value ~= true then
		error(string.format("FAIL [%s]", label))
	end
	print(string.format("PASS [%s]", label))
end

do
	local model = RescueContractHubPresentation.BuildPanelModel({
		accepted = true,
		contracts = {
			{
				queueEntryId = "queue_1",
				realmDisplayName = "giant_realm_9001",
				dangerRating = 0.6,
				rewardTierLabel = "Elevated",
				secondsRemaining = 12,
			},
		},
	})
	assertTrue(
		type(model.bodyText) == "string" and string.find(model.bodyText, "giant_realm_9001") ~= nil,
		"panel body includes realm"
	)
	assertTrue(model.title == "Rescue Contracts", "panel title")
end

do
	local acceptMessage = RescueContractHubPresentation.BuildAcceptStatusMessage({
		accepted = true,
		queueEntryId = "queue_1",
	})
	assertTrue(string.find(acceptMessage, "queue_1") ~= nil, "accept message includes queue id")
end

print("rescue_contract_hub_presentation: all checks passed")
