--!strict

local FrontDeskHubPresentation: any = {}

export type OpportunityInput = {
	id: string?,
	title: string?,
	body: string?,
	detail: string?,
	severity: string?,
	actionLabel: string?,
	source: string?,
}

export type OpportunityCard = {
	id: string,
	title: string,
	body: string,
	detail: string,
	severity: string,
	actionLabel: string,
	source: string,
	tone: string,
}

local SEVERITY_RANK: { [string]: number } = {
	danger = 1,
	critical = 1,
	warning = 2,
	caution = 2,
	info = 3,
	positive = 4,
}

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function titleCase(value: any): string
	if not isNonEmptyString(value) then
		return ""
	end

	local normalized = string.gsub(string.lower(value), "[_%-]+", " ")
	local words: { string } = {}
	for word in string.gmatch(normalized, "%S+") do
		local head = string.upper(string.sub(word, 1, 1))
		local tail = string.sub(word, 2)
		table.insert(words, head .. tail)
	end
	return table.concat(words, " ")
end

local function normalizeSeverity(value: any): string
	if not isNonEmptyString(value) then
		return "info"
	end

	local normalized = string.lower(value)
	if normalized == "critical" then
		return "danger"
	end
	if normalized == "caution" then
		return "warning"
	end
	if SEVERITY_RANK[normalized] ~= nil then
		return normalized
	end
	return "info"
end

local function severityRank(card: OpportunityCard): number
	return SEVERITY_RANK[card.severity] or SEVERITY_RANK.info
end

local function renderOpportunityCard(opportunity: OpportunityInput): OpportunityCard?
	if type(opportunity) ~= "table" or not isNonEmptyString(opportunity.id) then
		return nil
	end

	local id = opportunity.id :: string
	local source = if isNonEmptyString(opportunity.source) then opportunity.source :: string else "operations"
	local title = if isNonEmptyString(opportunity.title) then opportunity.title :: string else titleCase(id)
	local body = if isNonEmptyString(opportunity.body) then opportunity.body :: string else ""
	local detail = if isNonEmptyString(opportunity.detail) then opportunity.detail :: string else ""
	local severity = normalizeSeverity(opportunity.severity)

	return {
		id = id,
		title = title,
		body = body,
		detail = detail,
		severity = severity,
		actionLabel = if isNonEmptyString(opportunity.actionLabel) then opportunity.actionLabel :: string else "Review",
		source = source,
		tone = severity,
	}
end

local function appendOpportunityCards(cards: { OpportunityCard }, opportunities: any)
	if type(opportunities) ~= "table" then
		return
	end

	for _, opportunity in ipairs(opportunities) do
		local card = renderOpportunityCard(opportunity :: any)
		if card ~= nil then
			table.insert(cards, card)
		end
	end
end

local function sortOpportunityCards(cards: { OpportunityCard })
	table.sort(cards, function(left: OpportunityCard, right: OpportunityCard): boolean
		local leftRank = severityRank(left)
		local rightRank = severityRank(right)
		if leftRank ~= rightRank then
			return leftRank < rightRank
		end
		return left.id < right.id
	end)
end

function FrontDeskHubPresentation.RenderOpportunityCard(opportunity: OpportunityInput): OpportunityCard?
	return renderOpportunityCard(opportunity)
end

function FrontDeskHubPresentation.GetFrontDeskHubView(gameState: any): any
	local cards: { OpportunityCard } = {}
	local stateAny: any = gameState
	if type(stateAny) == "table" then
		appendOpportunityCards(cards, stateAny.procurementOpportunities)
		appendOpportunityCards(cards, stateAny.staffingReadinessOpportunities)
		appendOpportunityCards(cards, stateAny.readinessOpportunities)
		appendOpportunityCards(cards, stateAny.opportunities)
	end

	sortOpportunityCards(cards)

	return {
		title = "Operations Hub",
		opportunityCards = cards,
		hasOpportunities = #cards > 0,
	}
end

FrontDeskHubPresentation.getFrontDeskHubView = FrontDeskHubPresentation.GetFrontDeskHubView

return FrontDeskHubPresentation
