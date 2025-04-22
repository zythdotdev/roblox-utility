local RunService = game:GetService("RunService")

local Event = require(script.Parent.Parent.Event)

type NetworkRequest = {
	className: string,
	remoteFunctionDestroyed: Event.Self,

	_name: string,
	_parent: Instance,
	_destroyingConnection: RBXScriptConnection?,
	_remoteFunction: RemoteFunction?,

	new: (name: string, parent: Instance, callback: (player: Player, ...any) -> (...any)?) -> NetworkRequest,
	destroy: (self: NetworkRequest) -> (),
	setCallback: (self: NetworkRequest, callback: (player: Player, ...any) -> (...any)?) -> (),
	invokeAsync: (self: NetworkRequest, ...any) -> (),

	_setupRemoteFunction: (self: NetworkRequest, callback: (player: Player, ...any) -> (...any)?) -> ()
}

--[=[
	@within NetworkRequest
	@type Self NetworkRequest
]=]
export type Self = NetworkRequest

--[=[
	@within NetworkRequest
	@interface Event
	@field connect (self: Event, callback: (...any) -> ()) -> EventConnection

	An interface that respresents an event that can be connected to
]=]
export type Event = Event.Self

--[=[
	@within NetworkRequest
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

--[=[
	@within NetworkRequest
	@prop className string
	@tag Static

	Static property that defines the class name `NetworkRequest`
]=]

--[=[
	@within NetworkRequest
	@prop remoteFunctionDestroyed Event

	An event that fires when the underlying Roblox `RemoteFunction` instance is destroyed
]=]

--[=[
	@class NetworkRequest

	An object that wraps Roblox's remote function. It can be used to request data from the server and receive a response on the client
	without having to manage remote function instance lifecycles manually – initialization and deinitialization are handled for you

	:::note
	Network requests are intended to be paired. A `NetworkRequest` object should be initialized on the server first and then on the client,
	otherwise, an error will occur. The server `NetworkRequest` object will destroy the underlying Roblox `RemoteFunction` instance when it is
	destroyed. Attempting to call a method on a `NetworkRequest` after its server-side counterpart has been destroyed will result in an error. This
	can be monitored via the `NetworkRequest.remoteFunctionDestroyed` event

	Any type of Roblox object such as an `Enum`, `Instance`, or others can be passed as a parameter when a `NetworkRequest` is fired,
	as well as Luau types such as `number`, `string`, and `boolean`. `NetworkRequest` shares its limitations with Roblox's `RemoteFunction` class
	:::

	```lua
	-- Server
	local serverRequest = NetworkRequest.new("MyNetworkRequest", ReplicatedStorage)
	serverRequest:connect(function(player, _)
		print("The client is requesting a response")
		return "Hello, Client!"
	end

	-- Client
	local clientRequest = NetworkRequest.new("MyNetworkRequest", ReplicatedStorage)
	local value = clientRequest:invoke()
	print("The server responded with:", value) -- Hello, Client!
	```
]=]
local NetworkRequest = {}
NetworkRequest.__index = NetworkRequest
NetworkRequest.className = "NetworkRequest"

--[=[
	@tag Static
	@param name string -- The name of the `NetworkRequest` instance which must match on the client and server
	@param parent Instance -- The parent of the `NetworkRequest` instance which must match on the client and server
	@param callback (player: Player, ...any) -> (...any)? -- An optional callback to be called when the request is invoked
	@return NetworkRequest -- The `NetworkRequest` object

	Constructs a new `NetworkRequest` object
]=]
function NetworkRequest.new(name: string, parent: Instance, callback: (player: Player, ...any) -> (...any)?): NetworkRequest
	assert(name ~= nil and type(name) == "string", "Argument #1 must be a string")
	assert(parent ~= nil and typeof(parent) == "Instance", "Argument #2 must be an Instance")
	if callback then
		if RunService:IsClient() then
			error("Cannot set NetworkRequest callback on the client", 2)
		end
		assert(typeof(callback) == "function", "Argument #3 must be a function or nil")
	end

	local self = setmetatable({
		remoteFunctionDestroyed = Event.new(),
		_name = name,
		_parent = parent,
		_destroyingConnection = nil,
		_remoteFunction = nil
	}, NetworkRequest)

	self:_setupRemoteFunction()

	return self
end

--[=[
	Deconstructs the `NetworkRequest` object
]=]
function NetworkRequest.destroy(self: NetworkRequest)
	if self.remoteFunctionDestroyed then
		self.remoteFunctionDestroyed:destroy()
		self.remoteFunctionDestroyed = nil
	end
	self._name = nil
	self._parent = nil
	if self._destroyingConnection then
		self._destroyingConnection:Disconnect()
		self._destroyingConnection = nil
	end
	if RunService:IsServer() and self._remoteFunction then
		self._remoteFunction:Destroy()
	end
	self._remoteFunction = nil
end

--[=[
	@server
	@param callback (player: Player, ...any) -> (...any)? -- The callback to be called when the request is invoked

	Sets the callback for the `NetworkRequest` which is called when the request is invoked. The callback can be set to nil to remove it

	```lua
	local serverRequest = NetworkRequest.new("MyNetworkRequest", ReplicatedStorage)
	serverRequest:setCallback(function(player, value)
		print("The client passed the value:", value)
		return "Thank you, Client!"
	end
	```
]=]
function NetworkRequest.setCallback(self: NetworkRequest, callback: (player: Player, ...any) -> (...any)?)
	if self._remoteFunction == nil then
		warn("NetworkRequest:setCallback() called on a destroyed NetworkRequest")
		return
	end

	if RunService:IsClient() then
		error("Cannot connect to NetworkRequest callback on the client")
	end

	assert(callback == nil or typeof(callback) == "function", "Argument #1 must be a function or nil")

	self._remoteFunction.OnServerInvoke = callback
end

--[=[
	@client
	@yields
	@param ... any -- The arguments to pass to the server
	@return ... any -- The response from the server

	Invokes the `NetworkRequest` with the given arguments and yields the thread until a response is returned from the server

	```lua
	local clientRequest = NetworkRequest.new("MyNetworkRequest", ReplicatedStorage)
	local value = clientRequest:invokeAsync("Hello")
	print("The server responded with:", value)
	```
]=]
function NetworkRequest.invokeAsync(self: NetworkRequest, ...: any): ...any
	if self._remoteFunction == nil then
		warn("NetworkRequest:invokeAsync() called on a destroyed NetworkRequest")
		return
	end

	if RunService:IsServer() then
		error("Cannot Invoke a NetworkRequest on the server")
	end

	return self._remoteFunction:InvokeServer(...)
end

function NetworkRequest._setupRemoteFunction(self: NetworkRequest, callback: (player: Player, ...any) -> (...any)?)
	if RunService:IsServer() then
		local remoteFunction = self._parent:FindFirstChild(self._name)
		if remoteFunction ~= nil then
			error("NetworkEvent can't create a RemoteEvent because an Instance with the name '" .. self._name .. "' already exists in " .. self._parent:GetFullName())
		end

		remoteFunction = Instance.new("RemoteFunction")
		remoteFunction.Name = self._name
		remoteFunction.Parent = self._parent

		remoteFunction.OnServerInvoke = callback

		self._remoteFunction = remoteFunction
	else
		local remoteFunction: RemoteFunction = self._parent:WaitForChild(self._name, 6)
		if remoteFunction == nil then
			error("NetworkRequest " .. self._name .. " not found in " .. self._parent:GetFullName() .. "- A NetworkRequest with matching properties should be initialized on the server first")
		end

		self._remoteFunction = remoteFunction
	end

	self._destroyingConnection = self._remoteFunction.Destroying:Connect(function()
		self.remoteFunctionDestroyed:fire()
	end)
end

return table.freeze(NetworkRequest)