local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Event = require(script.Parent.Parent.Event)

type NetworkEvent = {
	className: string,
	remoteEventDestroyed: Event.Self,

	_name: string,
	_parent: Instance,
	_event: Event.Self,
	_remoteEventConnection: RBXScriptConnection?,
	_destroyingConnection: RBXScriptConnection?,
	_remoteEvent: (RemoteEvent | UnreliableRemoteEvent)?,

	new: (name: string, parent: Instance, unreliable: boolean?) -> NetworkEvent,
	destroy: (self: NetworkEvent) -> (),
	connect: (self: NetworkEvent, callback: (...any) -> ()) -> EventConnection,
	fireServer: (self: NetworkEvent, ...any) -> (),
	fireClient: (self: NetworkEvent, player: Player, ...any) -> (),
	fireFilteredClients: (self: NetworkEvent, predicate: (player: Player) -> boolean, ...any) -> (),
	fireAllClients: (self: NetworkEvent, ...any) -> (),

	_setupRemoteEvent: (self: NetworkEvent, unreliable: boolean) -> (),
	_connectRemoteEvent: (self: NetworkEvent) -> ()
}

--[=[
	@within NetworkEvent
	@type Self NetworkEvent
]=]
export type Self = NetworkEvent

--[=[
	@within NetworkEvent
	@interface EventConnection
	@field connected boolean
	@field disconnect () -> ()

	An interface that respresents a connection to an event. An object which conforms to this interface is returned by the `NetworkEvent:connect` method, this
	`EventConnection` object can be used to disconnect the callback from the event

	```lua
	print(connection.connected) -- true
	connection:disconnect()
	print(connection.connected) -- false
	```
]=]
export type EventConnection = Event.EventConnection

--[=[
	@within NetworkEvent
	@tag Static
	@prop className string

	Static property that defines the class name `NetworkEvent`
]=]

--[=[
	@within NetworkEvent
	@prop remoteEventDestroyed Event

	An event that fires when the underlying Roblox `RemoteEvent` instance is destroyed
]=]

--[=[
	@class NetworkEvent

	An object that wraps Roblox's remote events. It can be used to fire events between the server and client
	without having to manage remote event instance lifecycles manually – initialization and deinitialization are handled for you

	:::note
	Network events are intended to be paired. A `NetworkEvent` object should be initialized on the server first and then on the client,
	otherwise, an error will occur. The server `NetworkEvent` object will destroy the underlying Roblox `RemoteEvent` instance when it is destroyed.
	Attempting to call a method on a `NetworkEvent` after its server-side counterpart has been destroyed will result in an error. This can be monitored
	via the `NetworkEvent.remoteEventDestroyed` event

	Any type of Roblox object such as an `Enum`, `Instance`, or others can be passed as a parameter when a `NetworkEvent` is fired,
	as well as Luau types such as `number`, `string`, and `boolean`. `NetworkEvent` shares its limitations with Roblox's `RemoteEvent` class
	:::

	```lua
	-- Server
	local serverEvent = NetworkEvent.new("MyNetworkEvent", ReplicatedStorage)

	-- Client
	local clientEvent = NetworkEvent.new("MyNetworkEvent", ReplicatedStorage)
	clientEvent:connect(function(...)
		print("The event fired and passed the values:", ...) -- 1, 2, 3
	end)

	-- Server
	serverEvent:fireClient(player, 1, 2, 3)
	```
]=]
local NetworkEvent = {}
NetworkEvent.__index = NetworkEvent
NetworkEvent.className = "NetworkEvent"

--[=[
	@tag Static
	@param name string -- The name of the `NetworkEvent` instance which must match on the client and server
	@param parent Instance -- The parent of the `NetworkEvent` instance which must match on the client and server
	@param unreliable boolean? -- Whether or not the event should be unreliable. Defaults to `false`
	@return NetworkEvent -- The `NetworkEvent` object

	Constructs a new `NetworkEvent` object. The 'unreliable' parameter is defined by the server and ignored by the client
]=]
function NetworkEvent.new(name: string, parent: Instance, unreliable: boolean?): NetworkEvent
	assert(name ~= nil and type(name) == "string", "Argument #1 must be a string")
	assert(parent ~= nil and parent:IsA("Instance"), "Argument #2 must be an Instance")
	assert(unreliable == nil or type(unreliable) == "boolean", "Argument #3 must be a boolean or nil")

	if unreliable == nil then
		unreliable = false
	end

	local self = setmetatable({
		remoteEventDestroyed = Event.new(),
		_name = name,
		_parent = parent,
		_event = Event.new(),
		_remoteEventConnection = nil,
		_destroyingConnection = nil,
		_remoteEvent = nil,
	}, NetworkEvent)

	self:_setupRemoteEvent(unreliable)

	return self
end

--[=[
	Deconstructs the `NetworkEvent` object
]=]
function NetworkEvent.destroy(self: NetworkEvent)
	if self.remoteEventDestroyed then
		self.remoteEventDestroyed:destroy()
		self.remoteEventDestroyed = nil
	end
	self._name = nil
	self._parent = nil
	if self._event then
		self._event:destroy()
		self._event = nil
	end
	if self._remoteEventConnection then
		self._remoteEventConnection:Disconnect()
		self._remoteEventConnection = nil
	end
	if self._destroyingConnection then
		self._destroyingConnection:Disconnect()
		self._destroyingConnection = nil
	end
	if RunService:IsServer() and self._remoteEvent then
		self._remoteEvent:Destroy()
	end
	self._remoteEvent = nil
end

--[=[
	@param callback (...any) -> () -- The callback to be invoked when the event is fired
	@return EventConnection -- An event connection that can be disconnected

	Connects a callback to the `NetworkEvent` which is invoked when the event is fired

	:::note
	When connecting on the server, the first argument passed to the callback is always the player that fired the event
	:::

	```lua
	-- Client
	clientEvent:connect(function(...)
		print("The event fired and passed the values:", ...)
	end)

	-- Server
	serverEvent:connect(function(player, ...)
		print("The event was fired by " .. player .. " and passed the values:", ...)
	end)
	```
]=]
function NetworkEvent.connect(self: NetworkEvent, callback: (...any) -> ()): EventConnection
	if self._remoteEvent == nil then
		error("NetworkEvent:connect() called on a destroyed NetworkEvent")
	end

	assert(callback ~= nil and type(callback) == "function", "Argument #1 must be a function")

	local connection = self._event:connect(callback)

	if RunService:IsClient() and not self._remoteEventConnection then
		self:_connectRemoteEvent()
	end

	return connection
end

--[=[
	@client
	@param ... any -- The arguments to pass to the server

	Fires the `NetworkEvent` on the client, passing the given arguments to the server

	```lua
	event:fireServer("Hello, server!")
	```
]=]
function NetworkEvent.fireServer(self: NetworkEvent, ...: any)
	if self._remoteEvent == nil then
		error("NetworkEvent:fireServer() called on a destroyed NetworkEvent")
	end

	if RunService:IsServer() then
		error("NetworkEvent:fireServer() called on the server", 2)
	end

	self._remoteEvent:FireServer(...)
end

--[=[
	@server
	@param player Player -- The player to fire the event to
	@param ... any -- The arguments to pass to the client

	Fires the `NetworkEvent` on the server, passing the given arguments to the players client

	```lua
	event:fireClient(player, "Hello, client!")
	```
]=]
function NetworkEvent.fireClient(self: NetworkEvent, player: Player, ...: any)
	if self._remoteEvent == nil then
		error("NetworkEvent:fireClient() called on a destroyed NetworkEvent")
	end

	if RunService:IsClient() then
		error("NetworkEvent:fireClient() called on the client", 2)
	end

	assert(player ~= nil and player:IsA("Player"), "Argument #1 must be a Player")

	self._remoteEvent:FireClient(player, ...)
end

--[=[
	@server
	@param predicate (player: Player) -> boolean -- The predicate to check against each player
	@param ... any -- The arguments to pass to the client

	Fires the `NetworkEvent` on the server, passing the given arguments to player clients that pass the given predicate check

	```lua
	event:fireFilteredClients(function(player)
		return player.Team == game.Teams.Heroes
	end, "You win!")
	```
]=]
function NetworkEvent.fireFilteredClients(self: NetworkEvent, predicate: (player: Player) -> boolean, ...: any)
	if self._remoteEvent == nil then
		error("NetworkEvent:fireFilteredClients() called on a destroyed NetworkEvent")
	end

	if RunService:IsClient() then
		error("NetworkEvent:fireFilteredClients() called on the client")
	end

	assert(predicate ~= nil and type(predicate) == "function", "Argument #1 must be a function")

	for _, player in ipairs(Players:GetPlayers()) do
		if predicate(player) then
			self._remoteEvent:FireClient(player, ...)
		end
	end
end

--[=[
	@server
	@param ... any -- The arguments to pass to the clients

	Fires the `NetworkEvent` on the server, passing the given arguments to all clients

	```lua
	event:fireAllClients(1, 2, 3)
	```
]=]
function NetworkEvent.fireAllClients(self: NetworkEvent, ...: any)
	if self._remoteEvent == nil then
		error("NetworkEvent:fireAllClients() called on a destroyed NetworkEvent")
	end

	if RunService:IsClient() then
		error("NetworkEvent:fireAllClients() called on the client")
	end

	self._remoteEvent:FireAllClients(...)
end

function NetworkEvent._setupRemoteEvent(self: NetworkEvent, unreliable: boolean)
	if RunService:IsServer() then
		local remoteEvent = self._parent:FindFirstChild(self._name)
		if remoteEvent ~= nil then
			error("NetworkEvent can't create a remote event because an Instance with the name '" .. self._name .. "' already exists in " .. self._parent:GetFullName())
		end

		remoteEvent = if not unreliable then Instance.new("RemoteEvent") else Instance.new("UnreliableRemoteEvent")
		remoteEvent.Name = self._name
		remoteEvent.Parent = self._parent

		self._remoteEventConnection = remoteEvent.OnServerEvent:Connect(function(player, ...)
			self._event:fire(player, ...)
		end)

		self._remoteEvent = remoteEvent
	else
		local remoteEvent: RemoteEvent = self._parent:WaitForChild(self._name, 6)
		if remoteEvent == nil then
			error("NetworkEvent can't find a remote event with the name '" .. self._name .. "' in " .. self._parent:GetFullName() .. " - A NetworkEvent with matching properties should be initialized on the server first")
		end

		self._remoteEvent = remoteEvent
	end

	self._destroyingConnection = self._remoteEvent.Destroying:Connect(function()
		self.remoteEventDestroyed:fire()
	end)
end

function NetworkEvent._connectRemoteEvent(self: NetworkEvent)
	self._remoteEventConnection = self._remoteEvent.OnClientEvent:Connect(function(...)
		self._event:fire(...)
	end)
end

return table.freeze(NetworkEvent)