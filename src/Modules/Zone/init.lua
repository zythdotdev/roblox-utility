local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Event = require(script.Parent.Event)

type Zone = {
	className: string,
	playerAdded: Event.Self,
	playerRemoved: Event.Self,
	detected: Event.Self,

	_updateInterval: number,
	_detectedCount: number,
	_detectedHumanoidRootParts: {[Player]: BasePart},
	_detectedPlayers: {[Player]: boolean},
	_part: Part,
	_characters: {BasePart},
	_playerAddedConnection: RBXScriptConnection?,
	_playerRemovingConnection: RBXScriptConnection?,
	_characterAddedConnections: {[Player]: RBXScriptConnection},
	_characterRemovingConnections: {[Player]: RBXScriptConnection},
	_touchConnection: RBXScriptConnection?,
	_heartbeatConnection: RBXScriptConnection?,
	_enableTracking: boolean,
	_overlapParams: OverlapParams,

	new: (part: Part, updateInterval: number?, overlapParams: OverlapParams?) -> Zone,
	destroy: (self: Zone) -> (),
	enable: (self: Zone) -> (),
	disable: (self: Zone) -> (),
	getDetectedPlayers: (self: Zone) -> {Player},
	getDetectedHumanoidRootParts: (self: Zone) -> {[Player]: BasePart},

	_monitorCharacters: (self: Zone, player: Player) -> (),
	_monitorPlayers: (self: Zone) -> (),
	_addPlayersWhoJoinedZone: (self: Zone, parts: {BasePart}) -> (),
	_removePlayersWhoLeftZone: (self: Zone, parts: {BasePart}) -> (),
	_updateDetectedArray: (self: Zone) -> (),
	_startTracking: (self: Zone) -> (),
	_stopTracking: (self: Zone) -> ()
}

--[=[
	@within Zone
	@type Self Zone
]=]
export type Self = Zone

--[=[
	@within Zone
	@interface Event
	@field connect (self: Event, callback: (...any) -> ()) -> EventConnection

	An interface that respresents an event that can be connected to
]=]
export type Event = Event.Self

--[=[
	@within Zone
	@interface EventConnection
	@field connected boolean
	@field disconnect (self: EventConnection) -> ()

	An interface that respresents a connection to an event. This `EventConnection` object can be used to disconnect a callback

	```lua
	print(connection.connected) -- true
	connection:disconnect()
	print(connection.connected) -- false
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
	@prop playerAdded Event

	An event that fires when a player enters the zone
]=]

--[=[
	@within Zone
	@prop playerRemoved Event

	An event that fires when a player leaves the zone
]=]

--[=[
	@within Zone
	@prop updateInterval number

	The interval in seconds between each update of the list of detected players. The default value is 1 second
]=]

--[=[
	@within Zone
	@prop detected Event

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
	zone.playerAdded:connect(function(player: Player)
		print(player.Name, "entered the zone")
	end)
	zone.playerRemoved:connect(function(player: Player)
		print(player.Name, "left the zone")
	end)
	zone.detected:connect(function()
		print("Players detected in the zone this interval:", zone:getDetectedPlayers())
	end)
	zone:enable()
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
		playerAdded = Event.new(),
		playerRemoved = Event.new(),
		detected = Event.new(),
		_updateInterval = updateInterval or DEFAULT_UPDATE_INTERVAL,
		_detectedCount = 0,
		_detectedHumanoidRootParts = {},
		_detectedPlayers = {},
		_part = part,
		_characters = {},
		_playerAddedConnection = nil,
		_playerRemovingConnection = nil,
		_characterAddedConnections = {},
		_characterRemovingConnections = {},
		_touchConnection = nil,
		_heartbeatConnection = nil,
		_enableTracking = false,
		_overlapParams = overlapParams or OverlapParams.new()
	}, Zone)

	self._overlapParams.FilterType = Enum.RaycastFilterType.Include
	self._overlapParams.FilterDescendantsInstances = self._characters

	self:_monitorPlayers()

	return self
end

--[=[
	Deconstructs the `Zone` object
]=]
function Zone.destroy(self: Zone)
	self.playerAdded:destroy()
	self.playerAdded = nil
	self.playerRemoved:destroy()
	self.playerRemoved = nil
	self.detected:destroy()
	self.detected = nil
	self._updateInterval = nil
	self._detectedCount = nil
	self._detectedHumanoidRootParts = nil
	self._detectedPlayers = nil
	self._part = nil
	self._characters = nil
	self._playerAddedConnection:Disconnect()
	self._playerAddedConnection = nil
	self._playerRemovingConnection:Disconnect()
	self._playerRemovingConnection = nil
	for _, connection in pairs(self._characterAddedConnections) do
		connection:Disconnect()
	end
	self._characterAddedConnections = nil
	for _, connection in pairs(self._characterRemovingConnections) do
		connection:Disconnect()
	end
	self._characterRemovingConnections = nil
	self._touchConnection:Disconnect()
	self._touchConnection = nil
	if self._heartbeatConnection then
		self._heartbeatConnection:Disconnect()
		self._heartbeatConnection = nil
	end
	self._enableTracking = nil
	self._overlapParams = nil
end

--[=[
	Enables the `Zone` object. Any players that enter or leave the zone after it has been enabled will trigger the `playerAdded` and `playerRemoved` events respectively
]=]
function Zone.enable(self: Zone)
	if self._enableTracking then return end
	self._enableTracking = true

	local debounce = {}
	self._touchConnection = self._part.Touched:Connect(function(otherPart: Part)
		local player = getPlayerForHumanoidRootPart(otherPart)
		if player ~= nil and not debounce[player] then
			debounce[player] = true
			task.delay(0.1, function()
				debounce[player] = nil
			end)

			if self._heartbeatConnection then return end

			self._detectedCount = 0
			self:_startTracking()

			-- Do an initial check after 0.1 seconds (if the interval is greater than 0.1) to detect players 'instantly'
			-- We wait 0.1 seconds because the player might not actually be in the volume when the touch event fires
			-- This 'feels' correct
			if self._updateInterval > 0.1 then
				task.delay(0.1, self._updateDetectedArray, self)
			end
		end
	end)
end

--[=[
	Disables the `Zone` object. Players will no longer be detected and the current list of detected players will be cleared
]=]
function Zone.disable(self: Zone)
	if not self._enableTracking then return end
	self._enableTracking = false
	self._touchConnection:Disconnect()
	self._touchConnection = nil
	self:_stopTracking()

	self._detectedCount = 0
	table.clear(self._detectedHumanoidRootParts)
	table.clear(self._detectedPlayers)
end

--[=[
	@return {Player} -- An array of players that are currently detected in the zone

	Returns an array of players that are currently in the zone
]=]
function Zone.getDetectedPlayers(self: Zone): {Player}
	local players = {}
	for player, _ in pairs(self._detectedPlayers) do
		table.insert(players, player)
	end
	return players
end

--[=[
	@return {[Player]: BasePart} -- A dictionary of players and their corresponding `HumanoidRootPart` instances

	Returns a dictionary of players and their corresponding `HumanoidRootPart` instances that are currently detected in the zone
]=]
function Zone.getDetectedHumanoidRootParts(self: Zone): {[Player]: BasePart}
	return table.clone(self._detectedHumanoidRootParts)
end

function Zone._monitorCharacters(self: Zone, player: Player)
	if player.Character then
		table.insert(self._characters, player.Character)
	end
	self._characterAddedConnections[player] = player.CharacterAdded:Connect(function(character: Model)
		table.insert(self._characters, character)
	end)
	self._characterRemovingConnections[player] = player.CharacterRemoving:Connect(function(character: Model)
		local position = table.find(self._characters, character)
		if position then
			table.remove(self._characters, position)
		end
	end)
end

function Zone._monitorPlayers(self: Zone)
	for _, player in ipairs(Players:GetPlayers()) do
		self:_monitorCharacters(player)
	end
	self._playerAddedConnection = Players.PlayerAdded:Connect(function(player)
		self:_monitorCharacters(player)
	end)
	self._playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		self._characterAddedConnections[player]:Disconnect()
		self._characterAddedConnections[player] = nil
		self._characterRemovingConnections[player]:Disconnect()
		self._characterRemovingConnections[player] = nil
	end)
end

function Zone._addPlayersWhoJoinedZone(self: Zone, parts: {BasePart})
	for _, part in ipairs(parts) do
		local player = getPlayerForHumanoidRootPart(part)
		if not player then continue end

		local existingPlayer = self._detectedPlayers[player]
		if existingPlayer then continue end

		self._detectedHumanoidRootParts[player] = part
		self._detectedPlayers[player] = true
		self.playerAdded:fire(player)

		self._detectedCount += 1
	end
end

function Zone._removePlayersWhoLeftZone(self: Zone, parts: {BasePart})
	for _, humanoidRootPart in pairs(self._detectedHumanoidRootParts) do
		local player = getPlayerForHumanoidRootPart(humanoidRootPart)
		if not player then continue end

		local exists = false
		for _, part in ipairs(parts) do
			if humanoidRootPart ~= part then continue end
			exists = true
		end

		if not exists then
			self._detectedHumanoidRootParts[player] = nil
			self._detectedPlayers[player] = nil
			self.playerRemoved:fire(player)

			self._detectedCount -= 1
			if self._detectedCount == 0 then
				self:_stopTracking()
			end
		end
	end
end

function Zone._updateDetectedArray(self: Zone)
	self._overlapParams.FilterDescendantsInstances = self._characters
	local parts = workspace:GetPartsInPart(self._part, self._overlapParams)

	self:_removePlayersWhoLeftZone(parts)

	if #parts == 0 then
		self:_stopTracking()
		return
	end

	self:_addPlayersWhoJoinedZone(parts)

	self.detected:fire()
end

function Zone._startTracking(self: Zone)
	local updateBuffer = 0
	self._heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		if not self._enableTracking then return end
		updateBuffer += deltaTime
		if updateBuffer < self._updateInterval then return end
		updateBuffer = 0
		self:_updateDetectedArray()
	end)
end

function Zone._stopTracking(self: Zone)
	if self._heartbeatConnection then
		self._heartbeatConnection:Disconnect()
		self._heartbeatConnection = nil
	end
end

return table.freeze(Zone)