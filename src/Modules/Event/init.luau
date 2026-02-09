--!strict
--!native

type Node = {
	Callback: (...any) -> (),
	Next: Node?,
}

type Event = {
	className: string,
	_Head: Node?,
	_Destroyed: boolean,

	new: () -> Event,
	Destroy: (self: Event) -> (),
	Connect: (self: Event, callback: (...any) -> ()) -> EventConnection,
	Once: (self: Event, callback: (...any) -> ()) -> EventConnection,
	WaitAsync: (self: Event, timeout: number?) -> ...any,
	Fire: (self: Event, ...any) -> (),
	DisconnectAll: (self: Event) -> (),
}

--[=[
	@within Event
	@type Self Event
]=]
export type Self = Event

--[=[
	@within Event
	@interface EventConnection
	@field Disconnect () -> ()
	@field IsConnected () -> boolean

	An interface that represents a connection to an event.

	This `EventConnection` object can be used to disconnect the callback from the event.

	```lua
	print(connection:IsConnected()) -- true
	connection:Disconnect()
	print(connection:IsConnected()) -- false
	```
]=]
export type EventConnection = {
	_Connected: boolean,
	_Event: Event,
	_Node: Node,

	Disconnect: (self: EventConnection) -> (),
	IsConnected: (self: EventConnection) -> boolean,
}

local runnerThread: thread? = nil

local function run(fn: (...any) -> (), ...)
	local acquired = runnerThread
	runnerThread = nil

	local success, errorMessage = pcall(fn, ...)

	runnerThread = acquired

	if not success then
		task.spawn(function()
			error(tostring(errorMessage), 0)
		end)
	end
end

local function runnerLoop(fn: (...any) -> (), ...)
	run(fn, ...)
	while true do
		run(coroutine.yield())
	end
end

--[=[
	@within EventConnection
	@tag Static
	@prop className string

	Static property that defines the class name of the `EventConnection` object.
]=]

--[=[
	@class EventConnection

	An object that represents a connection to an event.
]=]
local EventConnection = {}
EventConnection.__index = EventConnection
EventConnection.className = "EventConnection"

--[=[
	@tag Static
	@param event Event -- An event to connect to
	@param node Node -- A node representing the callback in the event's linked list
	@return EventConnection -- The `EventConnection` object

	Constructs a new `EventConnection` object.

	:::caution
	Do not construct this object manually. Use `Event:Connect` or `Event:Once` instead.
	:::
]=]
function EventConnection.new(event: Event, node: Node): EventConnection
	local self = setmetatable({
		_Connected = true,
		_Event = event,
		_Node = node,
	}, EventConnection)

	return self :: EventConnection
end

--[=[
	Deconstructs the `EventConnection` object and disconnects it from the event if it is still connected.

	:::note
	This alias exists primarily for compatibility with third-party libraries that expect connection objects to have a
	`Destroy` method. In general, it is recommended to use `Disconnect` instead of `Destroy` to disconnect from events.
	:::
]=]
function EventConnection.Destroy(self: EventConnection)
	self:Disconnect()
end

--[=[
	Disconnects the `EventConnection` object from the event and deconstructs the object.
]=]
function EventConnection.Disconnect(self: EventConnection)
	if not self._Connected then return end

	self._Connected = false

	local event = self._Event
	if event._Head == self._Node then
		event._Head = self._Node.Next
	else
		local prev = event._Head
		while prev and prev.Next ~= self._Node do
			prev = prev.Next
		end
		if prev then
			prev.Next = self._Node.Next
		end
	end

	self._Node.Next = nil
	self._Node.Callback = nil :: any
end

--[=[
	@return boolean -- Whether or not the `EventConnection` is connected to the event

	Checks if the `EventConnection` is still connected to the event.
]=]
function EventConnection.IsConnected(self: EventConnection): boolean
	return self._Connected
end

--[=[
	@within Event
	@tag Static
	@prop className string

	Static property that defines the class name of the `Event` object.
]=]

--[=[
	@class Event

	A signal implementation using a linked list to store callbacks.

	This behaves similarly to `RBXScriptSignal`:
	- Argument types are not encoded into the signal
	- Fire expects `...any` and callbacks receive `...any`
	- Type safety is enforced by convention (consumer-side annotation) and documentation

	:::note
	Tables are passed by reference, so modifying a table passed through a callback will affect the original table. This
	is distinguished from Roblox's `RBXScriptSignal`, which passes tables by value using deep copies.
	:::

	```lua
	local event = Event.new()
	event:Connect(function(stringValue: string, numberValue: number)
		print("The event fired and passed the values:", stringValue, numberValue)
	end)
	event:Fire("Hello, world!", 42)
	event:Destroy()
	```
]=]
local Event = {}
Event.__index = Event
Event.className = "Event"

--[=[
	@tag Static
	@return Event -- The `Event` object

	Constructs a new `Event` object.
]=]
function Event.new(): Event
	local self = setmetatable({
		_Head = nil,
		_Destroyed = false,
	}, Event)

	return self :: Event
end

--[=[
	Deconstructs the `Event` object and disconnects/destroys all connections.
]=]
function Event.Destroy(self: Event)
	if self._Destroyed then
		return
	end
	self._Destroyed = true

	self:DisconnectAll()
	self._Head = nil
end

--[=[
	@param callback (...any) -> () -- The callback to invoke
	@return EventConnection -- An event connection that can be disconnected

	Connects a callback to the event which is invoked when the event is fired.
]=]
function Event.Connect(self: Event, callback: (...any) -> ()): EventConnection
	if self._Destroyed then
		error("Cannot connect to a destroyed Event", 2)
	end

	assert(type(callback) == "function", "Argument #1 must be a function")

	local node: Node = {
		Callback = callback,
		Next = self._Head,
	}

	self._Head = node

	return EventConnection.new(self, node)
end

--[=[
	@param callback (...any) -> () -- The callback to invoke once
	@return EventConnection -- An event connection that can be disconnected

	Connects a callback to the event which is invoked only once when the event is fired and then disconnected.
]=]
function Event.Once(self: Event, callback: (...any) -> ()): EventConnection
	if self._Destroyed then
		error("Cannot connect to a destroyed Event", 2)
	end

	assert(type(callback) == "function", "Argument #1 must be a function")

	local connection: EventConnection

	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)

	return connection
end

--[=[
	@yields
	@param timeout number? -- Optional timeout in seconds
	@return ...any -- The values passed when the event is fired

	Yields the current thread until the event is fired, then returns the values passed to the event. If a timeout is
	provided, the thread will resume after the timeout elapses and return no values.
]=]
function Event.WaitAsync(self: Event, timeout: number?): ...any
	if self._Destroyed then
		error("Cannot wait on a destroyed Event", 2)
	end

	assert(timeout == nil or (type(timeout) == "number" and timeout >= 0), "Timeout must be a non-negative number or nil")

	local thread = coroutine.running()
	local connection: EventConnection
	local timedOut = false

	connection = self:Connect(function(...)
		if timedOut then
			return
		end
		connection:Disconnect()
		task.spawn(thread, ...)
	end)

	if timeout ~= nil then
		task.delay(timeout, function()
			if connection:IsConnected() then
				timedOut = true
				connection:Disconnect()
				task.spawn(thread)
			end
		end)
	end

	return coroutine.yield()
end

--[=[
	@param ... any -- Values to pass to the event's callbacks

	Fires the event with the given arguments.
]=]
function Event.Fire(self: Event, ...)
	if self._Destroyed then
		return
	end

	local node = self._Head

	if not runnerThread then
		runnerThread = coroutine.create(runnerLoop)
	end

	local runner = runnerThread :: thread
	while node do
		local nextNode = node.Next
		task.spawn(runner, node.Callback, ...)
		node = nextNode
	end
end

--[=[
	Disconnects all connections from the event.
]=]
function Event.DisconnectAll(self: Event)
	self._Head = nil
end

return Event