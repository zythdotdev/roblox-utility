local Types = require(script.Types)
local EventConnection = require(script.EventConnection)

type Event = Types.Event

--[=[
	@within Event
	@type Self Event
]=]
export type Self = Event

--[=[
	@within Event
	@interface EventConnection
	@field connected boolean
	@field disconnect () -> ()

	An interface that respresents a connection to an event. An object which conforms to this interface is returned by the `Event:connect` method.
	This `EventConnection` object can be used to disconnect the callback from the event

	```lua
	print(connection.connected) -- true
	connection:disconnect()
	print(connection.connected) -- false
	```
]=]
export type EventConnection = Types.EventConnection

--[=[
	@within Event
	@tag Static
	@prop className string

	Static property that defines the class name of the `Event` object
]=]

--[=[
	@class Event

	A signal implementation that wraps Roblox's BindableEvent

	```lua
	local event = Event.new()
	local connection = event:connect(function(value)
		print("The event fired and passed the value:", value)
	end)
	event:fire("Hello, world!")
	connection:disconnect()
	event:destroy()
	```
]=]
local Event = {}
Event.__index = Event
Event.className = "Event"

--[=[
	@tag Static
	@return Event -- The `Event` object

	Constructs a new `Event` object
]=]
function Event.new(): Event
	local self = setmetatable({
		_bindableEvent = Instance.new("BindableEvent"),
		_bindableEventConnection = nil,
		_connections = {},
		_callbacks = {},
		_values = {}
	}, Event)

	return self
end

--[=[
	Deconstructs the `Event` object and disconnects/destroys all connections
]=]
function Event.destroy(self: Event)
	task.defer(function()
		if self._connections then
			for _, connection in pairs(self._connections) do
				connection:destroy()
			end
			self._connections = nil
		end
		self._callbacks = nil
		self._values = nil
		if self._bindableEventConnection then
			self._bindableEventConnection:Disconnect()
			self._bindableEventConnection = nil
		end
		if self._bindableEvent then
			self._bindableEvent:Destroy()
			self._bindableEvent = nil
		end
	end)
end

--[=[
	@param callback (...any) -> () -- The callback to connect to the event
	@return EventConnection -- An event connection that can be disconnected

	Connects a callback to the event which is invoked when the event is fired

	```lua
	local event = Event.new()
	event:connect(function(...)
		print("The event fired and passed the values:", ...)
	end)
	event:fire(1, 2, 3)
	```
]=]
function Event.connect(self: Event, callback: (...any) -> ()): EventConnection
	assert(callback ~= nil and type(callback) == "function", "callback must be a function")

	local eventConnection = EventConnection.new(self)
	self._connections[eventConnection] = eventConnection
	self._callbacks[eventConnection] = callback

	if not self._bindableEventConnection then
		self:_connectBindableEvent()
	end

	return eventConnection
end

--[=[
	@param eventConnection EventConnection -- The connection to disconnect from the event

	Disconnects a callback from the event

	:::caution
	This is called automatically when an EventConnection is disconnected. It's not necessary to call this manually
	:::
]=]
function Event.disconnect(self: Event, eventConnection: EventConnection)
	assert(eventConnection ~= nil and type(eventConnection) == "table" and eventConnection.className == "EventConnection", "eventConnection must be an EventConnection")

	if self._connections[eventConnection] then
		eventConnection:destroy()
		self._connections[eventConnection] = nil
		self._callbacks[eventConnection] = nil
	end
end

--[=[
	@param ... any -- The values to pass to the event's callbacks

	Fires the event with the given arguments

	```lua
	event:fire("Hello, world!")
	```
]=]
function Event.fire(self: Event, ...: any)
	if not self._bindableEventConnection then return end
	table.insert(self._values, {...})
	self._bindableEvent:Fire()

	-- Roblox's BindableEvent is used to hook into 'deferred events' behavior. In the future, Roblox plans to collapse events into
	-- a single event call (https://devforum.roblox.com/t/beta-deferred-lua-event-handling/1240569), presumably when the value is the same
	-- to reduce redundant calls
end

function Event._connectBindableEvent(self: Event)
	self._bindableEventConnection = self._bindableEvent.Event:Connect(function()
		if self._callbacks then
			for _, connection in pairs(self._connections) do
				local callback = self._callbacks[connection]
				task.spawn(callback, table.unpack(self._values[1]))
			end
		end
		table.remove(self._values, 1)
	end)
end

return table.freeze(Event)