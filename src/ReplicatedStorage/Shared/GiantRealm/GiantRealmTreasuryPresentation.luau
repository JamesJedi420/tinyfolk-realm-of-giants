--!strict

local GiantRealmTreasuryPresentation: any = {}

export type TreasuryModel = {
	visible: boolean,
	title: string,
	summary: string,
	ledgerEssence: number,
	ledgerWood: number,
	ledgerStone: number,
	sessionEssence: number,
	sessionWood: number,
	sessionStone: number,
	sessionMetal: number,
}

local function finiteNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function readLedgerField(snapshot: any, fieldName: string): number
	if type(snapshot) ~= "table" then
		return 0
	end
	local value = finiteNumber(snapshot[fieldName])
	if value == nil or value < 0 then
		return 0
	end
	return math.floor(value + 0.5)
end

function GiantRealmTreasuryPresentation.BuildHudModel(ledgerSnapshot: any, sessionSnapshot: any): TreasuryModel
	local ledgerEssence = readLedgerField(ledgerSnapshot, "essence")
	local ledgerWood = readLedgerField(ledgerSnapshot, "wood")
	local ledgerStone = readLedgerField(ledgerSnapshot, "stone")
	local sessionEssence = readLedgerField(sessionSnapshot, "essenceStored")
	local sessionWood = readLedgerField(sessionSnapshot, "woodStored")
	local sessionStone = readLedgerField(sessionSnapshot, "stoneStored")
	local sessionMetal = readLedgerField(sessionSnapshot, "metalStored")

	local summary = string.format(
		"Ledger E%d W%d S%d | Session E%d W%d S%d M%d",
		ledgerEssence,
		ledgerWood,
		ledgerStone,
		sessionEssence,
		sessionWood,
		sessionStone,
		sessionMetal
	)

	return {
		visible = true,
		title = "Giant Realm Treasury",
		summary = summary,
		ledgerEssence = ledgerEssence,
		ledgerWood = ledgerWood,
		ledgerStone = ledgerStone,
		sessionEssence = sessionEssence,
		sessionWood = sessionWood,
		sessionStone = sessionStone,
		sessionMetal = sessionMetal,
	}
end

return GiantRealmTreasuryPresentation
