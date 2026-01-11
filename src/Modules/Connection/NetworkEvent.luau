--!strict

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Event = require(script.Parent.Parent.Event)

type AnyRemoteEvent = {
	OnServerEvent: RBXScriptSignal,
    OnClientEvent: RBXScriptSignal,
    Destroying: RBXScriptSignal,

    FireServer: (self: AnyRemoteEvent, ...any) -> (),
    FireClient: (self: AnyRemoteEvent, player: Player, ...any) -> (),
    FireAllClients: (self: AnyRemoteEvent, ...any) -> (),
	Destroy: (self: AnyRemoteEvent) -> (),
}

type NetworkEvent = {
	className: string,
	RemoteEventDestroyed: Event.Self,

	_Name: string,
	_Parent: Instance,
	_Event: Event.Self,
	_RemoteEventConnection: RBXScriptConnection?,
	_DestroyingConnection: RBXScriptConnection?,
	_RemoteEvent: AnyRemoteEvent?,

	new: (name: string, parent: Instance, unreliable: boolean?) -> NetworkEvent,
	Destroy: (self: NetworkEvent) -> (),
	Connect: (self: NetworkEvent, callback: (...any) -> ()) -> Event.EventConnection,
	FireServer: (self: NetworkEvent, ...any) -> (),
	FireClient: (self: NetworkEvent, player: Player, ...any) -> (),
	FireFilteredClients: (self: NetworkEvent, predicate: (player: Player) -> boolean, ...any) -> (),
	FireAllClients: (self: NetworkEvent, ...any) -> (),

	_SetupRemoteEvent: (self: NetworkEvent, unreliable: boolean) -> (),
}

--[=[
	@within NetworkEvent
	@type Self NetworkEvent
]=]
export type Self = NetworkEvent

--[=[
	@within NetworkEvent
	@interface Event
	@field Connect (self: Event, callback: (...any) -> ()) -> EventConnection
	@field Once (self: Event, callback: (...any) -> ()) -> EventConnection
	@field WaitAsync (self: Event, timeout: number?) -> ...any

	An interface that represents an event that can be connected to.
]=]
export type Event = Event.Self

--[=[
	@within NetworkEvent
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

--[=[
	@within NetworkEvent
	@tag Static
	@prop className string

	Static property that defines the class name `NetworkEvent`.
]=]

--[=[
	@within NetworkEvent
	@prop RemoteEventDestroyed Event

	An event that fires when the underlying Roblox `RemoteEvent` instance is destroyed.
]=]

--[=[
	@class NetworkEvent

	An object that wraps Roblox remote events. It allows server ↔ client
	communication without requiring manual lifecycle management of
	`RemoteEvent` instances.

	:::note
	Network events are intended to be paired. A `NetworkEvent` must be
	initialized on the server first, then on the client. The client will
	wait up to 5 seconds for the server to create the `RemoteEvent`.
	If it doesn't exist after this timeout, an error will be thrown. Ensure
	the server initializes the `NetworkEvent` before any clients attempt to use it.

	The server-side `NetworkEvent` owns the underlying Roblox
	`RemoteEvent` and will destroy it when the object is destroyed.
	Calling methods on a `NetworkEvent` after its server counterpart
	has been destroyed will result in an error.

	This state can be monitored using the
	`NetworkEvent.RemoteEventDestroyed` event.

	Any Roblox-serializable value may be passed when firing a
	`NetworkEvent`, including `Instance`, `Enum`, and primitive Luau
	types. `NetworkEvent` shares the same limitations as Roblox's
	`RemoteEvent`.
	:::

	```lua
	-- Server
	local serverEvent = NetworkEvent.new("MyNetworkEvent", ReplicatedStorage)

	-- Client
	local clientEvent = NetworkEvent.new("MyNetworkEvent", ReplicatedStorage)
	clientEvent:Connect(function(...)
		print("The event fired and passed the values:", ...)
	end)

	-- Server
	serverEvent:FireClient(player, 1, 2, 3)
	```
]=]
local NetworkEvent = {}
NetworkEvent.__index = NetworkEvent
NetworkEvent.className = "NetworkEvent"

--[=[
	@tag Static
	@param name string -- The name of the network event (must match on client and server)
	@param parent Instance -- The parent instance (must match on client and server)
	@param unreliable boolean? -- Whether to use `UnreliableRemoteEvent` (server only)
	@return NetworkEvent

	Constructs a new `NetworkEvent`. The `unreliable` flag is defined by the server and
	ignored by the client.
]=]
function NetworkEvent.new(name: string, parent: Instance, unreliable: boolean?): NetworkEvent
	assert(name ~= nil and type(name) == "string", "Argument #1 must be a string")
	assert(parent ~= nil and parent:IsA("Instance"), "Argument #2 must be an Instance")
	assert(unreliable == nil or type(unreliable) == "boolean", "Argument #3 must be a boolean or nil")

	if unreliable == nil then
		unreliable = false
	end

	local self = setmetatable({
		RemoteEventDestroyed = Event.new(),
		_Name = name,
		_Parent = parent,
		_Event = Event.new(),
		_RemoteEventConnection = nil,
		_DestroyingConnection = nil,
		_RemoteEvent = nil,
	}, NetworkEvent) :: NetworkEvent

	self:_SetupRemoteEvent(unreliable :: boolean)

	return self
end

--[=[
	Deconstructs the `NetworkEvent` and releases all associated resources.
]=]
function NetworkEvent.Destroy(self: NetworkEvent)
	if self.RemoteEventDestroyed then
		self.RemoteEventDestroyed:Destroy()
		self.RemoteEventDestroyed = nil :: any
	end

	if self._Event then
		self._Event:Destroy()
		self._Event = nil :: any
	end

	if self._RemoteEventConnection then
		self._RemoteEventConnection:Disconnect()
		self._RemoteEventConnection = nil
	end

	if self._DestroyingConnection then
		self._DestroyingConnection:Disconnect()
		self._DestroyingConnection = nil
	end

	if RunService:IsServer() and self._RemoteEvent then
		self._RemoteEvent:Destroy()
	end

	self._RemoteEvent = nil
	self._Name = nil :: any
	self._Parent = nil :: any
end

--[=[
	@param callback (...any) -> ()
	@return EventConnection

	Connects a callback to the `NetworkEvent`.

	:::note
	On the server, the first argument passed to the callback is always
	the `Player` who fired the event.
	:::
]=]
function NetworkEvent.Connect(self: NetworkEvent, callback: (...any) -> ()): EventConnection
	if not self._RemoteEvent then
		error("NetworkEvent:Connect() called on a destroyed NetworkEvent", 2)
	end

	assert(type(callback) == "function", "Argument #1 must be a function")

	return self._Event:Connect(callback)
end

--[=[
	@client
	@param ... any

	Fires the event from the client to the server.
]=]
function NetworkEvent.FireServer(self: NetworkEvent, ...: any)
	if not self._RemoteEvent then
		error("NetworkEvent:FireServer() called on a destroyed NetworkEvent", 2)
	end

	if RunService:IsServer() then
		error("NetworkEvent:FireServer() called on the server", 2)
	end

	self._RemoteEvent:FireServer(...)
end

--[=[
	@server
	@param player Player
	@param ... any

	Fires the event from the server to a specific client.
]=]
function NetworkEvent.FireClient(self: NetworkEvent, player: Player, ...: any)
	if not self._RemoteEvent then
		error("NetworkEvent:FireClient() called on a destroyed NetworkEvent", 2)
	end

	if RunService:IsClient() then
		error("NetworkEvent:FireClient() called on the client", 2)
	end

	assert(player ~= nil and player:IsA("Player"), "Argument #1 must be a Player")

	self._RemoteEvent:FireClient(player, ...)
end

--[=[
	@server
	@param predicate (player: Player) -> boolean
	@param ... any

	Fires the event to all clients that pass the predicate check.
]=]
function NetworkEvent.FireFilteredClients(self: NetworkEvent, predicate: (Player) -> boolean, ...: any)
	if not self._RemoteEvent then
		error("NetworkEvent:FireFilteredClients() called on a destroyed NetworkEvent", 2)
	end

	if RunService:IsClient() then
		error("NetworkEvent:FireFilteredClients() called on the client", 2)
	end

	assert(predicate ~= nil and type(predicate) == "function", "Argument #1 must be a function")

	local filteredPlayers = {}
	for _, player in Players:GetPlayers() do
		if predicate(player) then
			table.insert(filteredPlayers, player)
		end
	end

	for _, player in filteredPlayers do
		self._RemoteEvent:FireClient(player, ...)
	end
end

--[=[
	@server
	@param ... any

	Fires the event to all connected clients.
]=]
function NetworkEvent.FireAllClients(self: NetworkEvent, ...: any)
	if not self._RemoteEvent then
		error("NetworkEvent:FireAllClients() called on a destroyed NetworkEvent", 2)
	end

	if RunService:IsClient() then
		error("NetworkEvent:FireAllClients() called on the client", 2)
	end

	self._RemoteEvent:FireAllClients(...)
end

function NetworkEvent._SetupRemoteEvent(self: NetworkEvent, unreliable: boolean)
	if RunService:IsServer() then
		if self._Parent:FindFirstChild(self._Name) then
			error(
				"NetworkEvent cannot create a RemoteEvent because an Instance named '"
					.. self._Name
					.. "' already exists in "
					.. self._Parent:GetFullName()
			)
		end

		local remoteEvent = if unreliable then Instance.new("UnreliableRemoteEvent") else Instance.new("RemoteEvent")

		remoteEvent.Name = self._Name
		remoteEvent.Parent = self._Parent

		self._RemoteEvent = (remoteEvent :: AnyRemoteEvent)

		self._RemoteEventConnection = (remoteEvent :: AnyRemoteEvent).OnServerEvent:Connect(function(player, ...: any)
			self._Event:Fire(player, ...)
		end)
	else
		local remoteEvent = self._Parent:WaitForChild(self._Name, 5)

		if not remoteEvent then
			error(
				"NetworkEvent cannot find a RemoteEvent named '"
					.. self._Name
					.. "' in "
					.. self._Parent:GetFullName()
					.. ". The server must initialize it first. Timed out after 5 seconds."
			)
		end

		self._RemoteEvent = (remoteEvent :: AnyRemoteEvent)

		self._RemoteEventConnection = (self._RemoteEvent :: AnyRemoteEvent).OnClientEvent:Connect(function(...: any)
			self._Event:Fire(...)
		end)
	end

	self._DestroyingConnection = (self._RemoteEvent :: AnyRemoteEvent).Destroying:Connect(function()
		self.RemoteEventDestroyed:Fire()
	end)
end

return NetworkEvent