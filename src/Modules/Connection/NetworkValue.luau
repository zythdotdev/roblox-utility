--!strict

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Event = require(script.Parent.Parent.Event)
local NetworkEvent = require(script.Parent.NetworkEvent)

type NetworkValue = {
	className: string,
	RemoteEventDestroyed: Event.Self,

	_Value: any?,
	_PlayerValues: {[Player]: any},
	_DestroyingConnection: Event.EventConnection?,
	_NetworkEventConnection: Event.EventConnection?,
	_NetworkEvent: NetworkEvent.Self,
	_Changed: Event.Self,
	_PlayerRemovingConnection: RBXScriptConnection?,

	new: (name: string, parent: Instance, value: any?, player: Player?) -> NetworkValue,
	Destroy: (self: NetworkValue) -> (),
	Connect: (self: NetworkValue, callback: (value: any?, player: Player?) -> ()) -> EventConnection,
	Get: (self: NetworkValue, player: Player?) -> any?,
	WaitAsync: (self: NetworkValue, player: Player?, timeout: number?) -> any?,
	Set: (self: NetworkValue, value: any?, player: Player?) -> (),

	_ConnectNetworkEvent: (self: NetworkValue) -> ()
}

--[=[
	@within NetworkValue
	@type Self NetworkValue
]=]
export type Self = NetworkValue

--[=[
	@within NetworkValue
	@interface Event
	@field Connect (self: Event, callback: (...any) -> ()) -> EventConnection

	An interface that represents an event that can be connected to.
]=]
export type Event = Event.Self

--[=[
	@within NetworkValue
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
	@within NetworkValue
	@prop RemoteEventDestroyed Event

	An event that fires when the underlying Roblox `RemoteEvent` instance is destroyed.
]=]

--[=[
	@class NetworkValue

	An object that synchronizes values between the server and client using
	a network event.

	Values may be shared globally or set per-player. The server owns the
	underlying `RemoteEvent` and controls its lifecycle.

	:::note
	Network values are intended to be paired. A `NetworkValue` must be
	initialized on the server first, then on the client. The client will
	wait up to 5 seconds for the server to create the underlying
	`RemoteEvent`. If it doesn't exist after this timeout, an error
	will be thrown.

	The server-side `NetworkValue` owns the underlying Roblox
	`RemoteEvent` and will destroy it when the object is destroyed.
	:::
]=]
local NetworkValue = {}
NetworkValue.__index = NetworkValue
NetworkValue.className = "NetworkValue"

--[=[
	@tag Static
	@param name string
	@param parent Instance
	@param value any?
	@param player Player?
	@return NetworkValue

	Constructs a new `NetworkValue`. The `value` and `player` parameters are
	ignored on the client.
]=]
function NetworkValue.new(name: string, parent: Instance, value: any?, player: Player?): NetworkValue
	assert(name ~= nil and type(name) == "string", "Argument #1 must be a string")
	assert(parent ~= nil and parent:IsA("Instance"), "Argument #2 must be an Instance")

	local self = setmetatable({
		RemoteEventDestroyed = Event.new(),
		_Value = nil,
		_PlayerValues = {},
		_DestroyingConnection = nil,
		_NetworkEventConnection = nil,
		_NetworkEvent = NetworkEvent.new(name, parent),
		_Changed = Event.new(),
	}, NetworkValue) :: NetworkValue

	if RunService:IsServer() then
		if player then
			self._PlayerValues[player] = value
		else
			self._Value = value
		end

		self._PlayerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
			self._PlayerValues[player] = nil
		end)
	end

	self:_ConnectNetworkEvent()

	return self
end

--[=[
	Deconstructs the `NetworkValue` and releases all resources.
]=]
function NetworkValue.Destroy(self: NetworkValue)
	if self.RemoteEventDestroyed then
		self.RemoteEventDestroyed:Destroy()
		self.RemoteEventDestroyed = nil :: any
	end

	if self._DestroyingConnection then
		self._DestroyingConnection:Disconnect()
		self._DestroyingConnection = nil
	end

	if self._NetworkEventConnection then
		self._NetworkEventConnection:Disconnect()
		self._NetworkEventConnection = nil
	end

	if self._NetworkEvent then
		self._NetworkEvent:Destroy()
	end

	if self._Changed then
		self._Changed:Destroy()
		self._Changed = nil :: any
	end

	if self._PlayerRemovingConnection then
		self._PlayerRemovingConnection:Disconnect()
		self._PlayerRemovingConnection = nil
	end

	self._Value = nil
	self._PlayerValues = nil :: any
	self._NetworkEvent = nil :: any
end

--[=[
	@param callback (value: any?, player: Player?) -> ()
	@return EventConnection

	Connects a callback that fires whenever the value changes.
]=]
function NetworkValue.Connect(self: NetworkValue, callback: (value: any?, player: Player?) -> ()): EventConnection
	if not self._NetworkEvent then
		error("NetworkValue:Connect() called on a destroyed NetworkValue", 2)
	end

	assert(type(callback) == "function", "Argument #1 must be a function")

	return self._Changed:Connect(callback)
end

--[=[
	@param player Player?
	@return any?

	Returns the current value of the `NetworkValue`. If `player` is provided, the
	player-specific value is returned; otherwise, the global value is returned. The player
	parameter is ignored on the client.
]=]
function NetworkValue.Get(self: NetworkValue, player: Player?): any?
	if not self._NetworkEvent then
		error("NetworkValue:Get() called on a destroyed NetworkValue", 2)
	end

	assert(player == nil or player:IsA("Player"), "Argument #1 must be a Player or nil")

	if RunService:IsClient() then
		return self._Value
	end

	if player then
		local playerValue = self._PlayerValues[player]
		if playerValue ~= nil then
			return playerValue
		end
	end

	return self._Value
end

--[=[
	@yields
	@param player Player?
	@param timeout number?
	@return any?

	Yields the current thread until the `NetworkValue` has a non-nil value,
	or until the optional timeout (in seconds) elapses.

	If `player` is provided, the thread will only resume when that player's
	value becomes available; otherwise, it will resume when the global value
	becomes available.

	If the value already exists, this function returns immediately.
	If the timeout elapses before a value becomes available, `nil` is returned.

	The `player` parameter is ignored on the client.

	:::warning
	If no timeout is provided and the value never becomes non-nil,
	this method will yield indefinitely. Always use a timeout in
	production code to prevent thread leaks.
	:::
]=]
function NetworkValue.WaitAsync(self: NetworkValue, player: Player?, timeout: number?): any?
	if not self._NetworkEvent then
		error("NetworkValue:WaitAsync() called on a destroyed NetworkValue", 2)
	end

	assert(player == nil or player:IsA("Player"), "Argument #1 must be a Player or nil")
	assert(timeout == nil or timeout >= 0, "Argument #2 must be a non-negative number or nil")

	local value = self:Get(player)
	if value ~= nil then
		return value
	end

	local thread = coroutine.running()
	assert(thread, "WaitAsync() must be called from a yieldable thread")

	local finished = false
	local connection: EventConnection?

	local function resume(result)
		if finished then
			return
		end
		finished = true

		if connection then
			connection:Disconnect()
			connection = nil
		end

		task.spawn(thread, result)
	end

	connection = self._Changed:Connect(function(newValue, changedPlayer)
		if RunService:IsServer() and player ~= nil then
			if changedPlayer ~= player then
				return
			end
		end

		resume(newValue)
	end)

	if timeout ~= nil then
		task.delay(timeout, function()
			resume(nil)
		end)
	end

	return coroutine.yield()
end

--[=[
	@server
	@param value any?
	@param player Player?

	Sets the value of the `NetworkValue`. If `player` is provided, only that player's
	value is set; otherwise, the global value is set. When the global value is set, all
	player-specific values are cleared.
]=]
function NetworkValue.Set(self: NetworkValue, value: any?, player: Player?)
	if not self._NetworkEvent then
		error("NetworkValue:Set() called on a destroyed NetworkValue", 2)
	end

	if RunService:IsClient() then
		error("NetworkValue:Set() must be called on the server", 2)
	end

	assert(player == nil or player:IsA("Player"), "Argument #2 must be a Player or nil")

	if player then
		self._PlayerValues[player] = value
		self._NetworkEvent:FireClient(player, value)
		self._Changed:Fire(value, player)
	else
		self._Value = value
		table.clear(self._PlayerValues)
		self._NetworkEvent:FireAllClients(value)
		self._Changed:Fire(value)
	end
end

function NetworkValue._ConnectNetworkEvent(self: NetworkValue)
	if RunService:IsServer() then
		self._NetworkEventConnection = self._NetworkEvent:Connect(function(player: Player)
			local playerValue = self._PlayerValues[player]
			self._NetworkEvent:FireClient(player, playerValue ~= nil and playerValue or self._Value)
		end)
	else
		self._NetworkEventConnection = self._NetworkEvent:Connect(function(value)
			local valueType = typeof(value)
			local shouldFire = false

			if valueType == "table" then
				shouldFire = true
			else
				shouldFire = self._Value ~= value
			end

			if shouldFire then
				self._Value = value
				self._Changed:Fire(value)
			end
		end)

		self._NetworkEvent:FireServer()
	end

	self._DestroyingConnection = self._NetworkEvent.RemoteEventDestroyed:Connect(function()
		self.RemoteEventDestroyed:Fire()
	end)
end

return NetworkValue