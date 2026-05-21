-- luau-lsp definitions shim for local CLI analysis.

declare class Instance
	Name: string
	Parent: Instance?
	function FindFirstChild(self, childName: string): any
	function WaitForChild(self, childName: string): any
	function FindFirstChildOfClass(self, className: string): any
	function IsA(self, className: string): boolean
	function GetAttribute(self, attributeName: string): any
	function SetAttribute(self, attributeName: string, value: any): ()
end

declare class Folder extends Instance end

declare class Vector3
	Magnitude: number
end

declare class CFrame
	Position: Vector3
end

declare class BasePart extends Instance
	Position: Vector3
	CFrame: CFrame
end

declare class Humanoid extends Instance
	Health: number
end

declare class Player extends Instance
	UserId: number
	Character: Instance?
	function GetAttribute(self, attributeName: string): any
	function SetAttribute(self, attributeName: string, value: any): ()
end

declare class RemoteEvent extends Instance
	OnServerEvent: any
	OnClientEvent: any
	function FireClient(self, player: Player, payload: any): ()
	function FireServer(self, payload: any): ()
end

declare class Vector2 end
declare class UDim2 end
declare class Color3 end
declare class Enum end

declare game: any
declare workspace: any
declare script: any
declare task: any
declare Instance: any
declare Vector2: any
declare Vector3: any
declare UDim2: any
declare CFrame: any
declare Color3: any
declare Enum: any

declare warn: (...any) -> ()
declare print: (...any) -> ()
declare typeof: (any) -> string
