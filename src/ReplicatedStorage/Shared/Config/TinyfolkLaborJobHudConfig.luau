--!strict

local TinyfolkLaborJobHudConfig: any = {}

TinyfolkLaborJobHudConfig.GuiName = "TinyfolkLaborJobHudGui"
TinyfolkLaborJobHudConfig.PanelName = "Panel"
TinyfolkLaborJobHudConfig.BillboardName = "TinyfolkLaborJobBillboard"

TinyfolkLaborJobHudConfig.CompletionFlashSeconds = 2

TinyfolkLaborJobHudConfig.Tones = {
	None = "none",
	Neutral = "neutral",
	Active = "active",
	Complete = "complete",
	Warning = "warning",
}

TinyfolkLaborJobHudConfig.DisplayNameByTargetId = {
	WorkStation_A = "Wood Station",
	MiningStation_A = "Mining Station",
	Farm_A = "Farm",
	Forge_A = "Forge",
	Warehouse_A = "Warehouse",
	Granary_A = "Granary",
	Shrine_A = "Shrine",
}

return TinyfolkLaborJobHudConfig
