local Event = require(script.Parent.Event)

type Value<T> = {
	className: string,

	_Event: Event.Self,
	_Value: T?,
	_ComputedConnections: {Event.EventConnection}?,

	new: (value: T?) -> Value<T?>,
	computed: <T>(selector: ((...any) -> T?)?, dependencies: {Value<any>}?) -> Value<T?>,
	Destroy: (self: Value<T?>) -> (),
	Observe: (self: Value<T>, callback: (T?) -> ()) -> Event.EventConnection,
	Setter: (self: Value<T>) -> (value: T?) -> (),
	Set: (self: Value<T>, value: T?) -> (),
	Get: (self: Value<T>) -> T?,
}

--[=[
	@within Value
	@type Self Value
]=]
export type Self<T> = Value<T>

--[=[
	@within Value
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
	@within Value
	@tag Static
	@prop className string

	Static property that defines the class name of the `Value` object
]=]

--[=[
	@class Value

	A value implementation that can be observed by multiple observers

	```lua
	local value = Value.new(1)
	local connection = Value:Observe(function(value)
		print("The value is: ", value)
	end)
	value:Set(2)
	connection:Disconnect()
	value:Destroy()
	```
]=]
local Value = {}
Value.__index = Value
Value.className = "Value"

--[=[
	@tag Static
	@return Value -- The `Value` object

	Constructs a new `Value` object
]=]
function Value.new<T>(value: T?): Value<T?>
	local self = setmetatable({
		_Event = Event.new(),
		_Value = value
	}, Value)

	return self
end

--[=[
	@param selector (...any) -> T? -- A function that derives the computed value from the current dependency values in order
	@param dependencies {Value<any>}? -- Dependency values to observe while computing the result. Each entry is passed to the selector as its own argument
	@return Value -- A derived value that updates when its dependencies change

	Creates a derived value from one or more dependencies.

	```lua
	local base = Value.new(2)
	local multiplier = Value.new(3)
	local total = Value.computed(function(baseValue, multiplierValue)
		return baseValue * multiplierValue
	end, { base, multiplier })
	```

	This example uses multiple dependencies in the array form so the computed result stays in sync with both values.
]=]
function Value.computed<T>(selector: (...any) -> T?, dependencies: {Value<any>}?): Value<T?>
	assert(type(selector) == "function", "selector must be a function")
	assert(dependencies == nil or type(dependencies) == "table", "dependencies must be an array-like table")

	dependencies = dependencies or {}

	local computed = Value.new(nil)
	computed._ComputedConnections = {}

	local function refresh()
		local args = {}
		for _, dependency in dependencies do
			if dependency and type(dependency) == "table" and type(dependency.Get) == "function" then
				table.insert(args, dependency:Get())
			else
				table.insert(args, dependency)
			end
		end

		local success, result = pcall(selector, unpack(args))
		if not success then
			warn("Error in computed Value callback:", result)
			return
		end

		computed:Set(result)
	end

	for _, dependency in dependencies do
		if dependency and type(dependency) == "table" and type(dependency.Observe) == "function" then
			local connection = dependency:Observe(function()
				refresh()
			end)
			table.insert(computed._ComputedConnections, connection)
		end
	end

	refresh()

	return computed
end

--[=[
	Deconstructs the `Value` object
]=]
function Value.Destroy<T>(self: Value<T?>)
	if self._ComputedConnections then
		for _, connection in self._ComputedConnections do
			if connection and connection:IsConnected() then
				connection:Disconnect()
			end
		end
		self._ComputedConnections = nil
	end

	self._Event:Destroy()
	self._Event = nil
	self._Value = nil
end

--[=[
	@param callback (T?) -> () -- The callback to be invoked when the value is changed
	@return EventConnection -- An event connection that can be disconnected

	Connects a callback to the Value which is invoked once upon connection and then whenever the value is changed

	```lua
	local value = Value.new(1)
	value:Observe(function(value: number?)
		print("The value is: ", value)
	end)
	```
]=]
function Value.Observe<T>(self: Value<T?>, callback: (T?) -> ()): EventConnection
	assert(callback ~= nil and type(callback) == "function", "callback must be a function")
	assert(self._Event, "Value has been destroyed")

	local connection = self._Event:Connect(callback)

	local success, err = pcall(callback, self._Value)
	if not success then
		warn("Error in initial Value observer callback:", err)
	end

	return connection
end

--[=[
	@return (value: T?) -> () -- A Setter function that can be used to Set the value

	Returns a Setter function that can be used to Set the value of the `Value` object

	```lua
	local value = Value.new(1)
	local Setter = value:Setter()
	Setter(2)
	```
]=]
function Value.Setter<T>(self: Value<T?>): (value: T?) -> ()
	assert(self._Event, "Value has been destroyed")

	return function(value: T?)
		self:Set(value)
	end
end

--[=[
	@param value T? -- The new value

	Sets the new value and updates any observers

	```lua
	local value = Value.new(1)
	value:Set(2)
	```
]=]
function Value.Set<T>(self: Value<T?>, value: T?)
	assert(self._Event, "Value has been destroyed")

	if self._Value ~= value then
		self._Value = value
		self._Event:Fire(value)
	end
end

--[=[
	@return T? -- The current value

	Returns the current value

	```lua
	local value = Value.new(1)
	print(value:Get()) -- 1
	```
]=]
function Value.Get<T>(self: Value<T?>): T?
	assert(self._Event, "Value has been destroyed")

	return self._Value
end

return Value