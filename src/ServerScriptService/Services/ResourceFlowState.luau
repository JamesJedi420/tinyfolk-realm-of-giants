--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local StationConfig = require(Config:WaitForChild("StationConfig"))

type MaterialName = "Wood" | "Stone" | "Food" | "Metal"

type MaterialFlowState = {
	produced: number,
	inTransit: number,
	stored: number,
	generatedTotal: number,
	lastProducedSource: string?,
	lastProducedAmount: number,
	lastDeliveredTo: string?,
	lastDeliveredAmount: number,
}

type DeliveryPointsState = {
	warehouseId: string?,
	warehousePart: BasePart?,
	granaryId: string?,
	granaryPart: BasePart?,
}

type MaterialFlowSnapshot = {
	produced: number,
	inTransit: number,
	stored: number,
	usable: number,
	generatedTotal: number,
	lastProducedSource: string?,
	lastProducedAmount: number,
	lastDeliveredTo: string?,
	lastDeliveredAmount: number,
}

type FlowSnapshot = {
	Wood: MaterialFlowSnapshot,
	Stone: MaterialFlowSnapshot,
	Food: MaterialFlowSnapshot,
	Metal: MaterialFlowSnapshot,
	deliveryPoints: {
		warehouseId: string?,
		granaryId: string?,
	},
}

local ResourceFlowState = {}

local globalEnv: any = getfenv()

local TEST_STARTING_WOOD_STORED = 120
local TEST_STARTING_STONE_STORED = 120

local STATIONS_PATH = { "Map", "Stations" }

local ATTRIBUTE_WOOD_PRODUCED_TOTAL = "WoodProducedTotal"
local ATTRIBUTE_WOOD_IN_TRANSIT_TOTAL = "WoodInTransitTotal"
local ATTRIBUTE_WOOD_STORED_TOTAL = "WoodStoredTotal"
local ATTRIBUTE_WOOD_USABLE_TOTAL = "WoodUsableTotal"
local ATTRIBUTE_STONE_PRODUCED_TOTAL = "StoneProducedTotal"
local ATTRIBUTE_STONE_IN_TRANSIT_TOTAL = "StoneInTransitTotal"
local ATTRIBUTE_STONE_STORED_TOTAL = "StoneStoredTotal"
local ATTRIBUTE_STONE_USABLE_TOTAL = "StoneUsableTotal"
local ATTRIBUTE_FOOD_PRODUCED_TOTAL = "FoodProducedTotal"
local ATTRIBUTE_FOOD_IN_TRANSIT_TOTAL = "FoodInTransitTotal"
local ATTRIBUTE_FOOD_STORED_TOTAL = "FoodStoredTotal"
local ATTRIBUTE_FOOD_USABLE_TOTAL = "FoodUsableTotal"
local ATTRIBUTE_METAL_PRODUCED_TOTAL = "MetalProducedTotal"
local ATTRIBUTE_METAL_IN_TRANSIT_TOTAL = "MetalInTransitTotal"
local ATTRIBUTE_METAL_STORED_TOTAL = "MetalStoredTotal"
local ATTRIBUTE_METAL_USABLE_TOTAL = "MetalUsableTotal"

local stateByMaterial: { [MaterialName]: MaterialFlowState } = {
	Wood = {
		produced = 0,
		inTransit = 0,
		stored = 0,
		generatedTotal = 0,
		lastProducedSource = nil,
		lastProducedAmount = 0,
		lastDeliveredTo = nil,
		lastDeliveredAmount = 0,
	},
	Stone = {
		produced = 0,
		inTransit = 0,
		stored = 0,
		generatedTotal = 0,
		lastProducedSource = nil,
		lastProducedAmount = 0,
		lastDeliveredTo = nil,
		lastDeliveredAmount = 0,
	},
	Food = {
		produced = 0,
		inTransit = 0,
		stored = 0,
		generatedTotal = 0,
		lastProducedSource = nil,
		lastProducedAmount = 0,
		lastDeliveredTo = nil,
		lastDeliveredAmount = 0,
	},
	Metal = {
		produced = 0,
		inTransit = 0,
		stored = 0,
		generatedTotal = 0,
		lastProducedSource = nil,
		lastProducedAmount = 0,
		lastDeliveredTo = nil,
		lastDeliveredAmount = 0,
	},
}

local deliveryPointsState: DeliveryPointsState = {
	warehouseId = nil,
	warehousePart = nil,
	granaryId = nil,
	granaryPart = nil,
}

local warnedMissingDeliveryByMaterial: { [MaterialName]: boolean } = {
	Wood = false,
	Stone = false,
	Food = false,
	Metal = false,
}

local function debugLog(message: string)
	print(string.format("[ResourceFlowState] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[ResourceFlowState] %s", message))
end

local function applyTestStartingStoredResources(reason: string)
	if TEST_STARTING_WOOD_STORED > 0 then
		stateByMaterial.Wood.stored = TEST_STARTING_WOOD_STORED
	end

	if TEST_STARTING_STONE_STORED > 0 then
		stateByMaterial.Stone.stored = TEST_STARTING_STONE_STORED
	end

	debugLog(
		string.format(
			"Applied test starting stored resources reason=%s woodStored=%.0f stoneStored=%.0f",
			reason,
			stateByMaterial.Wood.stored,
			stateByMaterial.Stone.stored
		)
	)
end

local function cloneMaterialSnapshot(materialState: MaterialFlowState): MaterialFlowSnapshot
	return {
		produced = materialState.produced,
		inTransit = materialState.inTransit,
		stored = materialState.stored,
		usable = materialState.stored,
		generatedTotal = materialState.generatedTotal,
		lastProducedSource = materialState.lastProducedSource,
		lastProducedAmount = materialState.lastProducedAmount,
		lastDeliveredTo = materialState.lastDeliveredTo,
		lastDeliveredAmount = materialState.lastDeliveredAmount,
	}
end

local function getStationsRoot(): Instance?
	local current: Instance = Workspace
	for _, childName in STATIONS_PATH do
		local nextNode = current:FindFirstChild(childName)
		if not nextNode then
			return nil
		end
		current = nextNode
	end

	return current
end

local function applyFlowAttributes(part: BasePart)
	local woodState = stateByMaterial.Wood
	local stoneState = stateByMaterial.Stone
	local foodState = stateByMaterial.Food
	local metalState = stateByMaterial.Metal

	part:SetAttribute(ATTRIBUTE_WOOD_PRODUCED_TOTAL, woodState.produced)
	part:SetAttribute(ATTRIBUTE_WOOD_IN_TRANSIT_TOTAL, woodState.inTransit)
	part:SetAttribute(ATTRIBUTE_WOOD_STORED_TOTAL, woodState.stored)
	part:SetAttribute(ATTRIBUTE_WOOD_USABLE_TOTAL, woodState.stored)
	part:SetAttribute(ATTRIBUTE_STONE_PRODUCED_TOTAL, stoneState.produced)
	part:SetAttribute(ATTRIBUTE_STONE_IN_TRANSIT_TOTAL, stoneState.inTransit)
	part:SetAttribute(ATTRIBUTE_STONE_STORED_TOTAL, stoneState.stored)
	part:SetAttribute(ATTRIBUTE_STONE_USABLE_TOTAL, stoneState.stored)
	part:SetAttribute(ATTRIBUTE_FOOD_PRODUCED_TOTAL, foodState.produced)
	part:SetAttribute(ATTRIBUTE_FOOD_IN_TRANSIT_TOTAL, foodState.inTransit)
	part:SetAttribute(ATTRIBUTE_FOOD_STORED_TOTAL, foodState.stored)
	part:SetAttribute(ATTRIBUTE_FOOD_USABLE_TOTAL, foodState.stored)
	part:SetAttribute(ATTRIBUTE_METAL_PRODUCED_TOTAL, metalState.produced)
	part:SetAttribute(ATTRIBUTE_METAL_IN_TRANSIT_TOTAL, metalState.inTransit)
	part:SetAttribute(ATTRIBUTE_METAL_STORED_TOTAL, metalState.stored)
	part:SetAttribute(ATTRIBUTE_METAL_USABLE_TOTAL, metalState.stored)
end

local function refreshDeliveryPointAttributes()
	if deliveryPointsState.warehousePart then
		applyFlowAttributes(deliveryPointsState.warehousePart)
	end

	if deliveryPointsState.granaryPart then
		applyFlowAttributes(deliveryPointsState.granaryPart)
	end
end

function ResourceFlowState.ApplyAttributesToPart(part: BasePart)
	applyFlowAttributes(part)
end

function ResourceFlowState.RefreshDeliveryPoints()
	deliveryPointsState.warehouseId = nil
	deliveryPointsState.warehousePart = nil
	deliveryPointsState.granaryId = nil
	deliveryPointsState.granaryPart = nil
	warnedMissingDeliveryByMaterial.Wood = false
	warnedMissingDeliveryByMaterial.Stone = false
	warnedMissingDeliveryByMaterial.Food = false
	warnedMissingDeliveryByMaterial.Metal = false

	local stationsRoot = getStationsRoot()
	if not stationsRoot then
		debugWarn("No stations root found at Workspace.Map.Stations while scanning delivery points")
		return
	end

	for _, descendant in stationsRoot:GetDescendants() do
		if descendant:IsA("BasePart") then
			if string.match(descendant.Name, "^" .. StationConfig.WarehouseNamePrefix) ~= nil then
				deliveryPointsState.warehouseId = descendant.Name
				deliveryPointsState.warehousePart = descendant
			elseif string.match(descendant.Name, "^" .. StationConfig.GranaryNamePrefix) ~= nil then
				deliveryPointsState.granaryId = descendant.Name
				deliveryPointsState.granaryPart = descendant
			end
		end
	end

	if not deliveryPointsState.warehousePart then
		debugWarn("Missing warehouse delivery point part")
	end

	if not deliveryPointsState.granaryPart then
		debugWarn("Missing granary delivery point part")
	end

	refreshDeliveryPointAttributes()
end

function ResourceFlowState.GetMaterialSnapshot(material: MaterialName): MaterialFlowSnapshot
	return cloneMaterialSnapshot(stateByMaterial[material])
end

function ResourceFlowState.GetSnapshot(): FlowSnapshot
	return {
		Wood = cloneMaterialSnapshot(stateByMaterial.Wood),
		Stone = cloneMaterialSnapshot(stateByMaterial.Stone),
		Food = cloneMaterialSnapshot(stateByMaterial.Food),
		Metal = cloneMaterialSnapshot(stateByMaterial.Metal),
		deliveryPoints = {
			warehouseId = deliveryPointsState.warehouseId,
			granaryId = deliveryPointsState.granaryId,
		},
	}
end

function ResourceFlowState.AddProduced(material: MaterialName, source: string, amount: number): MaterialFlowSnapshot
	if type(source) ~= "string" or source == "" then
		debugWarn("Rejected produced update reason=invalid_source")
		return cloneMaterialSnapshot(stateByMaterial[material])
	end

	if amount <= 0 then
		debugWarn(
			string.format(
				"Rejected produced update material=%s source=%s reason=non_positive_amount amount=%.2f",
				material,
				source,
				amount
			)
		)
		return cloneMaterialSnapshot(stateByMaterial[material])
	end

	local materialState = stateByMaterial[material]
	materialState.produced += amount
	materialState.generatedTotal += amount
	materialState.lastProducedSource = source
	materialState.lastProducedAmount = amount

	refreshDeliveryPointAttributes()
	debugLog(
		string.format(
			"Produced material=%s source=%s amount=%.0f produced=%.0f",
			material,
			source,
			amount,
			materialState.produced
		)
	)

	return cloneMaterialSnapshot(materialState)
end

local function getDeliveryIdForMaterial(material: MaterialName): string?
	local configuredId = StationConfig.DeliveryPointIdByMaterial[material]
	if configuredId == deliveryPointsState.granaryId then
		return deliveryPointsState.granaryId
	end
	if configuredId == deliveryPointsState.warehouseId then
		return deliveryPointsState.warehouseId
	end

	if material == "Food" then
		return deliveryPointsState.granaryId
	end

	return deliveryPointsState.warehouseId
end

local function getDeliveryPartForMaterial(material: MaterialName): BasePart?
	local configuredId = getDeliveryIdForMaterial(material)
	if configuredId == deliveryPointsState.granaryId then
		return deliveryPointsState.granaryPart
	end
	if configuredId == deliveryPointsState.warehouseId then
		return deliveryPointsState.warehousePart
	end

	if material == "Food" then
		return deliveryPointsState.granaryPart
	end

	return deliveryPointsState.warehousePart
end

local function getMaxTransitForMaterial(material: MaterialName): number
	local configured = StationConfig.MaxInTransitByMaterial[material]
	if type(configured) ~= "number" then
		return math.huge
	end

	local multiplier = 1
	local deliveryId = getDeliveryIdForMaterial(material)
	local upgradeApi = globalEnv._VillageWorksiteUpgradeService_QueryAPI
	if
		type(deliveryId) == "string"
		and type(upgradeApi) == "table"
		and type(upgradeApi.GetInTransitCapacityMultiplier) == "function"
	then
		local resolvedMultiplier = upgradeApi.GetInTransitCapacityMultiplier(deliveryId)
		if type(resolvedMultiplier) == "number" and resolvedMultiplier > 0 then
			multiplier = resolvedMultiplier
		end
	end

	return math.max(0, math.floor(configured * multiplier + 0.5))
end

function ResourceFlowState.TransferProducedToInTransit(material: MaterialName, maxAmount: number): MaterialFlowSnapshot
	if maxAmount <= 0 then
		return cloneMaterialSnapshot(stateByMaterial[material])
	end

	local materialState = stateByMaterial[material]
	local maxInTransit = getMaxTransitForMaterial(material)
	local inTransitHeadroom = math.max(0, maxInTransit - materialState.inTransit)
	local transferAmount = math.min(maxAmount, math.max(0, materialState.produced), inTransitHeadroom)

	if transferAmount > 0 then
		materialState.produced -= transferAmount
		materialState.inTransit += transferAmount

		debugLog(
			string.format(
				"Hauled to transit material=%s amount=%.0f produced=%.0f inTransit=%.0f",
				material,
				transferAmount,
				materialState.produced,
				materialState.inTransit
			)
		)
		refreshDeliveryPointAttributes()
	end

	return cloneMaterialSnapshot(materialState)
end

function ResourceFlowState.TransferInTransitToStored(material: MaterialName, maxAmount: number): MaterialFlowSnapshot
	if maxAmount <= 0 then
		return cloneMaterialSnapshot(stateByMaterial[material])
	end

	local materialState = stateByMaterial[material]
	local deliveryPart = getDeliveryPartForMaterial(material)
	if not deliveryPart then
		if warnedMissingDeliveryByMaterial[material] ~= true then
			debugWarn(string.format("Skipping delivery material=%s reason=missing_delivery_point", material))
			warnedMissingDeliveryByMaterial[material] = true
		end
		return cloneMaterialSnapshot(materialState)
	end
	warnedMissingDeliveryByMaterial[material] = false

	local transferAmount = math.min(maxAmount, math.max(0, materialState.inTransit))
	if transferAmount > 0 then
		materialState.inTransit -= transferAmount
		materialState.stored += transferAmount
		materialState.lastDeliveredTo = getDeliveryIdForMaterial(material)
		materialState.lastDeliveredAmount = transferAmount

		debugLog(
			string.format(
				"Delivered to storage material=%s amount=%.0f deliveryPoint=%s inTransit=%.0f stored=%.0f",
				material,
				transferAmount,
				tostring(materialState.lastDeliveredTo),
				materialState.inTransit,
				materialState.stored
			)
		)
		refreshDeliveryPointAttributes()
	end

	return cloneMaterialSnapshot(materialState)
end

function ResourceFlowState.SpendStoredAtomic(
	woodCost: number,
	stoneCost: number,
	reason: string,
	foodCost: number?
): (boolean, FlowSnapshot, string?)
	if type(reason) ~= "string" or reason == "" then
		return false, ResourceFlowState.GetSnapshot(), "invalid_reason"
	end

	local resolvedFoodCost = if type(foodCost) == "number" then foodCost else 0

	if woodCost < 0 or stoneCost < 0 or resolvedFoodCost < 0 then
		return false, ResourceFlowState.GetSnapshot(), "negative_cost"
	end

	if woodCost == 0 and stoneCost == 0 and resolvedFoodCost == 0 then
		return false, ResourceFlowState.GetSnapshot(), "zero_cost"
	end

	local woodState = stateByMaterial.Wood
	local stoneState = stateByMaterial.Stone
	local foodState = stateByMaterial.Food

	if woodState.stored < woodCost then
		return false,
			ResourceFlowState.GetSnapshot(),
			string.format("insufficient_wood required=%.0f stored=%.0f", woodCost, woodState.stored)
	end

	if stoneState.stored < stoneCost then
		return false,
			ResourceFlowState.GetSnapshot(),
			string.format("insufficient_stone required=%.0f stored=%.0f", stoneCost, stoneState.stored)
	end

	if foodState.stored < resolvedFoodCost then
		return false,
			ResourceFlowState.GetSnapshot(),
			string.format("insufficient_food required=%.0f stored=%.0f", resolvedFoodCost, foodState.stored)
	end

	woodState.stored -= woodCost
	stoneState.stored -= stoneCost
	foodState.stored -= resolvedFoodCost
	refreshDeliveryPointAttributes()

	debugLog(
		string.format(
			"Spent stored reason=%s woodCost=%.0f stoneCost=%.0f foodCost=%.0f woodStored=%.0f stoneStored=%.0f foodStored=%.0f",
			reason,
			woodCost,
			stoneCost,
			resolvedFoodCost,
			woodState.stored,
			stoneState.stored,
			foodState.stored
		)
	)

	return true, ResourceFlowState.GetSnapshot(), nil
end

function ResourceFlowState.AddStoredAtomic(
	woodAmount: number,
	stoneAmount: number,
	reason: string,
	foodAmount: number?
): FlowSnapshot
	local safeWoodAmount = math.max(0, woodAmount)
	local safeStoneAmount = math.max(0, stoneAmount)
	local safeFoodAmount = if type(foodAmount) == "number" then math.max(0, foodAmount) else 0

	stateByMaterial.Wood.stored += safeWoodAmount
	stateByMaterial.Stone.stored += safeStoneAmount
	stateByMaterial.Food.stored += safeFoodAmount
	refreshDeliveryPointAttributes()

	debugLog(
		string.format(
			"Restored stored reason=%s woodAmount=%.0f stoneAmount=%.0f foodAmount=%.0f woodStored=%.0f stoneStored=%.0f foodStored=%.0f",
			reason,
			safeWoodAmount,
			safeStoneAmount,
			safeFoodAmount,
			stateByMaterial.Wood.stored,
			stateByMaterial.Stone.stored,
			stateByMaterial.Food.stored
		)
	)

	return ResourceFlowState.GetSnapshot()
end

function ResourceFlowState.ResetSession(reason: string)
	for _, materialState in stateByMaterial do
		materialState.produced = 0
		materialState.inTransit = 0
		materialState.stored = 0
		materialState.generatedTotal = 0
		materialState.lastProducedSource = nil
		materialState.lastProducedAmount = 0
		materialState.lastDeliveredTo = nil
		materialState.lastDeliveredAmount = 0
	end

	applyTestStartingStoredResources("reset")

	refreshDeliveryPointAttributes()
	debugLog(string.format("Reset session reason=%s", reason))
end

applyTestStartingStoredResources("startup")

return ResourceFlowState
