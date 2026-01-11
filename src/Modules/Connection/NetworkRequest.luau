--!strict

local RunService = game:GetService("RunService")

local Event = require(script.Parent.Parent.Event)

type ServerCallback = (player: Player, ...any) -> ...any

type NetworkRequest = {
	className: string,
	RemoteFunctionDestroyed: Event.Self,

	_Name: string,
	_Parent: Instance,
	_DestroyingConnection: RBXScriptConnection?,
	_RemoteFunction: RemoteFunction?,

	new: (name: string, parent: Instance, callback: ServerCallback?) -> NetworkRequest,
	Destroy: (self: NetworkRequest) -> (),
	SetCallback: (self: NetworkRequest, callback: ServerCallback?) -> (),
	InvokeAsync: (self: NetworkRequest, ...any) -> ...any,

	_SetupRemoteFunction: (self: NetworkRequest, callback: ServerCallback?) -> ()
}

--[=[
	@within NetworkRequest
	@type Self NetworkRequest
]=]
export type Self = NetworkRequest

--[=[
	@within NetworkRequest
	@interface Event
	@field Connect (self: Event, callback: (...any) -> ()) -> EventConnection
	@field Once (self: Event, callback: (...any) -> ()) -> EventConnection
	@field WaitAsync (self: Event, timeout: number?) -> ...any

	An interface that represents an event that can be connected to.
]=]
export type Event = Event.Self

--[=[
	@within NetworkRequest
	@interface EventConnection
	@field Disconnect () -> ()
	@field IsConnected () -> boolean

	An interface that represents a connection to an event.
]=]
export type EventConnection = Event.EventConnection

--[=[
	@class NetworkRequest

	An object that wraps Roblox's `RemoteFunction`. It allows clients to
	request data from the server and receive a response without manually
	managing `RemoteFunction` lifecycles.

	:::note
	Network requests are intended to be paired. A `NetworkRequest` must be
	initialized on the server first, then on the client. The client will
	wait up to 5 seconds for the server to create the `RemoteFunction`.
	If it doesn't exist after this timeout, an error will be thrown. Ensure
	the server initializes the `NetworkRequest` before any clients attempt to use it.

	The server-side `NetworkRequest` owns the underlying Roblox
	`RemoteFunction` and will destroy it when the object is destroyed.
	Calling methods on a `NetworkRequest` after its server counterpart
	has been destroyed will result in an error.

	This state can be monitored using the
	`NetworkRequest.RemoteFunctionDestroyed` event.

	Any Roblox-serializable value may be passed as arguments or returned,
	including `Instance`, `Enum`, and primitive Luau types. `NetworkRequest`
	shares the same limitations as Roblox's `RemoteFunction`.
	:::

	```lua
	-- Server
	local serverRequest = NetworkRequest.new("MyNetworkRequest", ReplicatedStorage)
	serverRequest:SetCallback(function(player: Player)
		print("The client is requesting a response")
		return "Hello, Client!"
	end)

	-- Client
	local clientRequest = NetworkRequest.new("MyNetworkRequest", ReplicatedStorage)
	local value = clientRequest:InvokeAsync()
	print("The server responded with:", value)
	```
]=]
local NetworkRequest = {}
NetworkRequest.__index = NetworkRequest
NetworkRequest.className = "NetworkRequest"

--[=[
	@tag Static
	@param name string -- The name of the request (must match on client and server)
	@param parent Instance -- The parent instance (must match on client and server)
	@param callback ((player: Player, ...any) -> ...any)? -- Optional server callback
	@return NetworkRequest

	Constructs a new `NetworkRequest`. The callback may only be provided
	on the server.
]=]
function NetworkRequest.new(name: string, parent: Instance, callback: ServerCallback?): NetworkRequest
	assert(name ~= nil and type(name) == "string", "Argument #1 must be a string")
	assert(parent ~= nil and parent:IsA("Instance"), "Argument #2 must be an Instance")

	if callback then
		if RunService:IsClient() then
			error("Cannot set NetworkRequest callback on the client", 2)
		end
		assert(typeof(callback) == "function", "Argument #3 must be a function or nil")
	end

	local self = setmetatable({
		RemoteFunctionDestroyed = Event.new(),
		_Name = name,
		_Parent = parent,
		_DestroyingConnection = nil,
		_RemoteFunction = nil,
	}, NetworkRequest) :: NetworkRequest

	self:_SetupRemoteFunction(callback)

	return self
end

--[=[
	Deconstructs the `NetworkRequest` and releases all associated resources.
]=]
function NetworkRequest.Destroy(self: NetworkRequest)
	if self.RemoteFunctionDestroyed then
		self.RemoteFunctionDestroyed:Destroy()
		self.RemoteFunctionDestroyed = nil :: any
	end

	if self._DestroyingConnection then
		self._DestroyingConnection:Disconnect()
		self._DestroyingConnection = nil
	end

	if RunService:IsServer() and self._RemoteFunction then
		self._RemoteFunction:Destroy()
	end

	self._RemoteFunction = nil
	self._Name = nil :: any
	self._Parent = nil :: any
end

--[=[
	@server
	@param callback ((player: Player, ...any) -> ...any)? -- The server callback

	Sets or clears the server callback for the `NetworkRequest`.
]=]
function NetworkRequest.SetCallback(self: NetworkRequest, callback: ServerCallback?)
	if not self._RemoteFunction then
		error("NetworkRequest:SetCallback() called on a destroyed NetworkRequest", 2)
	end

	if RunService:IsClient() then
		error("Cannot set NetworkRequest callback on the client", 2)
	end

	assert(callback == nil or typeof(callback) == "function", "Argument #1 must be a function or nil")

	self._RemoteFunction.OnServerInvoke = callback :: ServerCallback
end

--[=[
	@client
	@yields
	@param ... any -- Arguments passed to the server
	@return ...any -- The server response

	Invokes the request and yields until the server responds.

	:::warning
	If the server does not respond, this method will yield indefinitely.
	Ensure the server callback returns a value in all code paths.
	:::
]=]
function NetworkRequest.InvokeAsync(self: NetworkRequest, ...: any): ...any
	if not self._RemoteFunction then
		error("NetworkRequest:InvokeAsync() called on a destroyed NetworkRequest", 2)
	end

	if RunService:IsServer() then
		error("NetworkRequest:InvokeAsync() called on the server", 2)
	end

	return self._RemoteFunction:InvokeServer(...)
end

function NetworkRequest._SetupRemoteFunction(self: NetworkRequest, callback: ServerCallback?)
	if RunService:IsServer() then
		if self._Parent:FindFirstChild(self._Name) then
			error(
				"NetworkRequest cannot create a RemoteFunction because an Instance named '"
					.. self._Name
					.. "' already exists in "
					.. self._Parent:GetFullName()
			)
		end

		local remoteFunction = Instance.new("RemoteFunction")
		remoteFunction.Name = self._Name
		remoteFunction.Parent = self._Parent
		remoteFunction.OnServerInvoke = callback :: ServerCallback

		self._RemoteFunction = remoteFunction
	else
		local remoteFunction = self._Parent:WaitForChild(self._Name, 5)

		if not remoteFunction then
			error(
				"NetworkRequest '"
					.. self._Name
					.. "' not found in "
					.. self._Parent:GetFullName()
					.. ". Initialize it on the server first. Timed out after 5 seconds."
			)
		end

		self._RemoteFunction = remoteFunction :: RemoteFunction
	end

	self._DestroyingConnection = (self._RemoteFunction :: RemoteFunction).Destroying:Connect(function()
		self.RemoteFunctionDestroyed:Fire()
	end)
end

return NetworkRequest