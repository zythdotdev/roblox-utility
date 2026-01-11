local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Event = require(script.Parent.Event)

type Zone = {
	className: string,
	PlayerAdded: Event.Self,
	PlayerRemoved: Event.Self,
	Detected: Event.Self,

	_UpdateInterval: number,
	_DetectedCount: number,
	_DetectedHumanoidRootParts: {[Player]: BasePart},
	_DetectedPlayers: {[Player]: boolean},
	_Part: Part,
	_Characters: {BasePart},
	_PlayerAddedConnection: RBXScriptConnection?,
	_PlayerRemovingConnection: RBXScriptConnection?,
	_CharacterAddedConnections: {[Player]: RBXScriptConnection},
	_CharacterRemovingConnections: {[Player]: RBXScriptConnection},
	_TouchConnection: RBXScriptConnection?,
	_HeartbeatConnection: RBXScriptConnection?,
	_EnableTracking: boolean,
	_OverlapParams: OverlapParams,

	new: (part: Part, updateInterval: number?, overlapParams: OverlapParams?) -> Zone,
	Destroy: (self: Zone) -> (),
	Enable: (self: Zone) -> (),
	Disable: (self: Zone) -> (),
	GetDetectedPlayers: (self: Zone) -> {Player},
	GetDetectedHumanoidRootParts: (self: Zone) -> {[Player]: BasePart},

	_MonitorCharacters: (self: Zone, player: Player) -> (),
	_MonitorPlayers: (self: Zone) -> (),
	_AddPlayersWhoJoinedZone: (self: Zone, parts: {BasePart}) -> (),
	_RemovePlayersWhoLeftZone: (self: Zone, parts: {BasePart}) -> (),
	_UpdateDetectedArray: (self: Zone) -> (),
	_StartTracking: (self: Zone) -> (),
	_StopTracking: (self: Zone) -> ()
}

--[=[
	@within Zone
	@type Self Zone
]=]
export type Self = Zone

--[=[
	@within Zone
	@interface Event
	@field Connect (self: Event, callback: (...any) -> ()) -> EventConnection
	@field Once (self: Event, callback: (...any) -> ()) -> EventConnection
	@field WaitAsync (self: Event, timeout: number?) -> ...any

	An interface that represents an event that can be connected to.
]=]
export type Event = Event.Self

--[=[
	@within Zone
	@interface EventConnection
	@field Disconnect () -> ()
	@field IsConnected () -> boolean

	An interface that represents a connection to an event.

	```lua
	print(connection:IsConnected()) -- true
	connection:Disconnect()
	print(connection:IsConnected()) -- false
	```
]=]
export type EventConnection = Event.EventConnection

local DEFAULT_UPDATE_INTERVAL = 1

local function getPlayerForHumanoidRootPart(humanoidRootPart: BasePart): Player?
	if humanoidRootPart.Parent == nil or not humanoidRootPart:IsA("Part") or humanoidRootPart.Name ~= "HumanoidRootPart" then
		return nil
	end

	return Players:GetPlayerFromCharacter(humanoidRootPart.Parent)
end

--[=[
	@within Zone
	@prop className string
	@tag Static

	Static property that defines the class name `Zone`
]=]

--[=[
	@within Zone
	@prop PlayerAdded Event

	An event that fires when a player enters the zone
]=]

--[=[
	@within Zone
	@prop PlayerRemoved Event

	An event that fires when a player leaves the zone
]=]

--[=[
	@within Zone
	@prop UpdateInterval number

	The interval in seconds between each update of the list of detected players. The default value is 1 second
]=]

--[=[
	@within Zone
	@prop Detected Event

	An event that fires each interval when players are detected in the zone. This event doesn't fire if no players are detected
]=]

--[=[
	@class Zone

	An object that uses a Roblox `Part` instance to detect when players enter and exit a zone. It can be used to monitor players in a specific area on
	either the server or the client. The zone will attempt to detect players when they touch the `Part` instance and will continue to monitor them
	until they leave the zone, the zone is checked every update interval (default 1 second)

	```lua
	local part = Instance.new("Part")
	part.Size = Vector3.new(10, 10, 10)
	part.Position = Vector3.new(0, 10, 0)
	part.Anchored = true
	part.CanCollide = false
	part.Parent = workspace

	local zone = Zone.new(part)
	zone.PlayerAdded:Connect(function(player: Player)
		print(player.Name, "entered the zone")
	end)
	zone.PlayerRemoved:Connect(function(player: Player)
		print(player.Name, "left the zone")
	end)
	zone.Detected:Connect(function()
		print("Players detected in the zone this interval:", zone:GetDetectedPlayers())
	end)
	zone:Enable()
	```
]=]
local Zone = {}
Zone.__index = Zone
Zone.className = "Zone"

--[=[
	@tag Static
	@param part Part -- The `Part` instance that defines the zones physical boundaries
	@param updateInterval number? -- An optional interval in seconds between each check for players. Defaults to 1
	@param overlapParams OverlapParams? -- An optional `OverlapParams` instance that defines the parameters for underlying checks
	@return Zone -- The `Zone` object

	Constructs a new `Zone` object
]=]
function Zone.new(part: Part, updateInterval: number?, overlapParams: OverlapParams?): Zone
	assert(typeof(part) == "Instance" and part:IsA("Part"), "Argument #1 must be a Part")
	assert(updateInterval == nil or (typeof(updateInterval) == "number" and updateInterval > 0), "Argument #2 must be a positive number or nil")
	assert(overlapParams == nil or (typeof(overlapParams) == "Instance" and overlapParams:IsA("OverlapParams")), "Argument #3 must be an OverlapParams or nil")

	local self = setmetatable({
		PlayerAdded = Event.new(),
		PlayerRemoved = Event.new(),
		Detected = Event.new(),
		_UpdateInterval = updateInterval or DEFAULT_UPDATE_INTERVAL,
		_DetectedCount = 0,
		_DetectedHumanoidRootParts = {},
		_DetectedPlayers = {},
		_Part = part,
		_Characters = {},
		_PlayerAddedConnection = nil,
		_PlayerRemovingConnection = nil,
		_CharacterAddedConnections = {},
		_CharacterRemovingConnections = {},
		_TouchConnection = nil,
		_HeartbeatConnection = nil,
		_EnableTracking = false,
		_OverlapParams = overlapParams or OverlapParams.new()
	}, Zone)

	self._OverlapParams.FilterType = Enum.RaycastFilterType.Include
	self._OverlapParams.FilterDescendantsInstances = self._Characters

	self:_MonitorPlayers()

	return self
end

--[=[
	Deconstructs the `Zone` object
]=]
function Zone.Destroy(self: Zone)
	self.PlayerAdded:Destroy()
	self.PlayerAdded = nil
	self.PlayerRemoved:Destroy()
	self.PlayerRemoved = nil
	self.Detected:Destroy()
	self.Detected = nil
	self._UpdateInterval = nil
	self._DetectedCount = nil
	self._DetectedHumanoidRootParts = nil
	self._DetectedPlayers = nil
	self._Part = nil
	self._Characters = nil
	if self._PlayerAddedConnection then
		self._PlayerAddedConnection:Disconnect()
		self._PlayerAddedConnection = nil
	end
	if self._PlayerRemovingConnection then
		self._PlayerRemovingConnection:Disconnect()
		self._PlayerRemovingConnection = nil
	end
	for _, connection in self._CharacterAddedConnections do
		connection:Disconnect()
	end
	self._CharacterAddedConnections = nil
	for _, connection in self._CharacterRemovingConnections do
		connection:Disconnect()
	end
	self._CharacterRemovingConnections = nil
	if self._TouchConnection then
		self._TouchConnection:Disconnect()
		self._TouchConnection = nil
	end
	if self._HeartbeatConnection then
		self._HeartbeatConnection:Disconnect()
		self._HeartbeatConnection = nil
	end
	self._EnableTracking = nil
	self._OverlapParams = nil
end

--[=[
	Enables the `Zone` object. Any players that enter or leave the zone after it has been enabled will trigger the `PlayerAdded` and `PlayerRemoved` events respectively
]=]
function Zone.Enable(self: Zone)
	assert(self.PlayerAdded, "Zone has been destroyed")

	if self._EnableTracking then return end
	self._EnableTracking = true

	local debounce = {}
	self._TouchConnection = self._Part.Touched:Connect(function(otherPart: Part)
		local player = getPlayerForHumanoidRootPart(otherPart)
		if player ~= nil and not debounce[player] then
			debounce[player] = true
			task.delay(0.1, function()
				debounce[player] = nil
			end)

			if self._HeartbeatConnection then return end

			self._DetectedCount = 0
			self:_StartTracking()

			-- Do an initial check after 0.1 seconds (if the interval is greater than 0.1) to detect players 'instantly'
			-- We wait 0.1 seconds because the player might not actually be in the volume when the touch event fires
			-- This 'feels' correct
			if self._UpdateInterval > 0.1 then
				task.delay(0.1, self._UpdateDetectedArray, self)
			end
		end
	end)
end

--[=[
	Disables the `Zone` object. Players will no longer be detected and the current list of detected players will be cleared
]=]
function Zone.Disable(self: Zone)
	assert(self.PlayerAdded, "Zone has been destroyed")

	if not self._EnableTracking then return end
	self._EnableTracking = false
	if self._TouchConnection then
		self._TouchConnection:Disconnect()
		self._TouchConnection = nil
	end
	self:_StopTracking()

	self._DetectedCount = 0
	table.clear(self._DetectedHumanoidRootParts)
	table.clear(self._DetectedPlayers)
end

--[=[
	@return {Player} -- An array of players that are currently detected in the zone

	Returns an array of players that are currently in the zone
]=]
function Zone.GetDetectedPlayers(self: Zone): {Player}
	assert(self.PlayerAdded, "Zone has been destroyed")

	local players = {}
	for player, _ in self._DetectedPlayers do
		table.insert(players, player)
	end
	return players
end

--[=[
	@return {[Player]: BasePart} -- A dictionary of players and their corresponding `HumanoidRootPart` instances

	Returns a dictionary of players and their corresponding `HumanoidRootPart` instances that are currently detected in the zone
]=]
function Zone.GetDetectedHumanoidRootParts(self: Zone): {[Player]: BasePart}
	assert(self.PlayerAdded, "Zone has been destroyed")

	return table.clone(self._DetectedHumanoidRootParts)
end

function Zone._MonitorCharacters(self: Zone, player: Player)
	if player.Character then
		table.insert(self._Characters, player.Character)
	end
	self._CharacterAddedConnections[player] = player.CharacterAdded:Connect(function(character: Model)
		table.insert(self._Characters, character)
	end)
	self._CharacterRemovingConnections[player] = player.CharacterRemoving:Connect(function(character: Model)
		local position = table.find(self._Characters, character)
		if position then
			table.remove(self._Characters, position)
		end
	end)
end

function Zone._MonitorPlayers(self: Zone)
	for _, player in Players:GetPlayers() do
		self:_MonitorCharacters(player)
	end
	self._PlayerAddedConnection = Players.PlayerAdded:Connect(function(player)
		self:_MonitorCharacters(player)
	end)
	self._PlayerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		self._CharacterAddedConnections[player]:Disconnect()
		self._CharacterAddedConnections[player] = nil
		self._CharacterRemovingConnections[player]:Disconnect()
		self._CharacterRemovingConnections[player] = nil
	end)
end

function Zone._AddPlayersWhoJoinedZone(self: Zone, parts: {BasePart})
	for _, part in parts do
		local player = getPlayerForHumanoidRootPart(part)
		if not player then continue end

		local existingPlayer = self._DetectedPlayers[player]
		if existingPlayer then continue end

		self._DetectedHumanoidRootParts[player] = part
		self._DetectedPlayers[player] = true
		self.PlayerAdded:Fire(player)

		self._DetectedCount += 1
	end
end

function Zone._RemovePlayersWhoLeftZone(self: Zone, parts: {BasePart})
	for _, humanoidRootPart in self._DetectedHumanoidRootParts do
		local player = getPlayerForHumanoidRootPart(humanoidRootPart)
		if not player then continue end

		local exists = false
		for _, part in parts do
			if humanoidRootPart ~= part then continue end
			exists = true
		end

		if not exists then
			self._DetectedHumanoidRootParts[player] = nil
			self._DetectedPlayers[player] = nil
			self.PlayerRemoved:Fire(player)

			self._DetectedCount -= 1
			if self._DetectedCount == 0 then
				self:_StopTracking()
			end
		end
	end
end

function Zone._UpdateDetectedArray(self: Zone)
	self._OverlapParams.FilterDescendantsInstances = self._Characters
	local parts = workspace:GetPartsInPart(self._Part, self._OverlapParams)

	self:_RemovePlayersWhoLeftZone(parts)

	if #parts == 0 then
		self:_StopTracking()
		return
	end

	self:_AddPlayersWhoJoinedZone(parts)

	self.Detected:Fire()
end

function Zone._StartTracking(self: Zone)
	local updateBuffer = 0
	self._HeartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		if not self._EnableTracking then return end
		updateBuffer += deltaTime
		if updateBuffer < self._UpdateInterval then return end
		updateBuffer = 0
		self:_UpdateDetectedArray()
	end)
end

function Zone._StopTracking(self: Zone)
	if self._HeartbeatConnection then
		self._HeartbeatConnection:Disconnect()
		self._HeartbeatConnection = nil
	end
end

return Zone