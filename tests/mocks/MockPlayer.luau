--!strict

local MockPlayer: any = {}
MockPlayer.__index = MockPlayer

local function makeVector(x: number, y: number, z: number)
	local function buildVector(nx: number, ny: number, nz: number, vectorMt: any)
		local vector: any = { x = nx, y = ny, z = nz }
		vector.Magnitude = function(self: any)
			return math.sqrt((self.x * self.x) + (self.y * self.y) + (self.z * self.z))
		end
		return setmetatable(vector, vectorMt)
	end

	local vectorMt: any = nil
	vectorMt = {
		__sub = function(a: any, b: any)
			return buildVector(a.x - b.x, a.y - b.y, a.z - b.z, vectorMt)
		end,
	}

	return buildVector(x, y, z, vectorMt)
end

local function makeRootPart(position: any)
	local root: any = {
		ClassName = "BasePart",
		Position = position,
	}

	function root:IsA(className: string): boolean
		return className == "BasePart"
	end

	return root
end

local function makeCharacter(position: any, hasRoot: boolean, options: any?)
	local root = if hasRoot then makeRootPart(position) else nil
	local opts = options or {}
	local character: any = {}

	function character:FindFirstChild(childName: string): any
		if childName == "HumanoidRootPart" then
			return root
		end
		return nil
	end

	function character:FindFirstChildOfClass(className: string): any
		if className == "Humanoid" then
			if opts.missingHumanoid == true then
				return nil
			end
			return { Health = if type(opts.health) == "number" then opts.health else 100, AutoRotate = true }
		end
		return nil
	end

	function character:PivotTo(_cframe: any)
		return
	end

	return character
end

local function getRoleByName(name: string): string
	if string.find(name, "Giant", 1, true) then
		return "Giant"
	end
	return "Tinyfolk"
end

function MockPlayer.new(userId: number, name: string, options: any?)
	local opts = options or {}
	local position = makeVector(0, 0, if opts.positionZ ~= nil then opts.positionZ else (if userId == 2 then 4 else 6))
	local hasRoot = if opts.hasRoot == nil then true else opts.hasRoot

	local attributes: { [string]: any } = {
		Role = if type(opts.role) == "string" then opts.role else getRoleByName(name),
		CrossingPhase = if type(opts.crossingPhase) == "string" then opts.crossingPhase else "MidCrossing",
		InSafeZone = opts.inSafeZone == true,
		SafeZoneType = opts.safeZoneType,
		SafeZoneProtectionEndsAt = opts.safeZoneProtectionEndsAt,
		DownedState = "Normal",
		DownedIsDowned = false,
	}

	local self: any = setmetatable({
		UserId = userId,
		Name = name,
		Character = if opts.missingCharacter == true then nil else makeCharacter(position, hasRoot, opts),
	}, MockPlayer)

	function self:GetAttribute(attributeName: string): any
		return attributes[attributeName]
	end

	function self:SetAttribute(attributeName: string, value: any)
		attributes[attributeName] = value
	end

	return self
end

-- Extend MockPlayer for simulation harness
function MockPlayer.attemptEscape(self: any, _target: any, _params: any)
	-- Simulate an escape attempt
	return {
		success = not self:GetAttribute("InSafeZone"),
		reason = self:GetAttribute("InSafeZone") and "safe_zone" or "success",
	}
end

function MockPlayer.blockTraversalGap(_self: any, routeId: any, _config: any)
	-- Simulate a traversal-gap block request
	return {
		accepted = true,
		reason = "accepted",
		routeId = routeId,
	}
end

return MockPlayer
