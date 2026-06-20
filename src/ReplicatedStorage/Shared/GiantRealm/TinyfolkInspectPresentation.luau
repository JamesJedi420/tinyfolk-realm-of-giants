--!strict

local TinyfolkInspectState = require("./TinyfolkInspectState")

local TinyfolkInspectPresentation = {}

export type PanelModel = {
	visible: boolean,
	title: string,
	summary: string,
	tone: string,
}

function TinyfolkInspectPresentation.BuildPanelModel(snapshotInput: any): PanelModel
	local snapshot = TinyfolkInspectState.BuildSnapshot(snapshotInput)

	local summary = string.format(
		"%s | %s\n%s\n%s | %s\n%s\n%s\n%s",
		snapshot.roleLine,
		snapshot.custodyLine,
		snapshot.traitsLine,
		snapshot.moraleLine,
		snapshot.fatigueLine,
		snapshot.loyaltyLine,
		snapshot.assignmentLine,
		snapshot.valueLine
	)

	return {
		visible = true,
		title = snapshot.displayName,
		summary = summary,
		tone = snapshot.tone,
	}
end

return TinyfolkInspectPresentation
