--!strict

type Bag = {
	className: string,

	_Destroyed: boolean,
	_Items: {{Item: Item, DisposeMethod: string}},
	_Tracked: {[Item]: number},
	_DestroyingConnection: RBXScriptConnection?,

	new: () -> Bag,
	Destroy: (self: Bag) -> (),
	Add: <T>(self: Bag, item: T & Item, disposeMethod: string?) -> T,
	Remove: <T>(self: Bag, item: T & Item) -> boolean,
	Dispose: (self: Bag) -> (),
	Attach: (self: Bag, instance: Instance) -> (),

	_AssertAlive: (self: Bag) -> (),
}
type DisconnectablePascal = {
	Disconnect: (self: DisconnectablePascal) -> ()
}
type DisconnectableCamel = {
	disconnect: (self: DisconnectableCamel) -> ()
}
type DestroyablePascal = {
	Destroy: (self: DestroyablePascal) -> ()
}
type DestroyableCamel = {
	destroy: (self: DestroyableCamel) -> ()
}
type Class = DestroyablePascal | DestroyableCamel | DisconnectablePascal | DisconnectableCamel
type Function = (...any) -> any

--[=[
	@within Bag
	@type Self Bag
]=]
export type Self = Bag

--[=[
	@within Bag
	@type Item Instance | RBXScriptConnection | Class | Function | thread

	An item that can be added to the Bag
]=]
export type Item = Instance | RBXScriptConnection | Class | Function | thread

local FUNCTION_DISPOSE_METHOD = "Function"
local THREAD_DISPOSE_METHOD = "Thread"
local TABLE_DISPOSE_METHODS = table.freeze({"destroy", "Destroy", "disconnect", "Disconnect"})

local function getDisposeMethod(object: Item): string
	local objectType = typeof(object)

	if objectType == "function" then
		return FUNCTION_DISPOSE_METHOD
	elseif objectType == "thread" then
		return THREAD_DISPOSE_METHOD
	elseif objectType == "Instance" then
		return "Destroy"
	elseif objectType == "RBXScriptConnection" then
		return "Disconnect"
	elseif objectType == "table" then
		for _, disposeMethod in TABLE_DISPOSE_METHODS do
			if typeof((object :: Class)[disposeMethod]) == "function" then
				return disposeMethod
			end
		end
	end
	error("Failed to get Dispose method for object type '" .. objectType .. "' " .. tostring(object), 3)
end

local function invokeDisposeMethod(item: Item, disposeMethod: string)
	if disposeMethod == FUNCTION_DISPOSE_METHOD then
		(item :: Function)()
	elseif disposeMethod == THREAD_DISPOSE_METHOD then
		pcall(task.cancel, item :: any)
	else
		(item :: Class)[disposeMethod](item)
	end
end

--[=[
	@within Bag
	@tag Static
	@prop className string

	Static property that defines the class name `Bag`
]=]

--[=[
	@class Bag

	A `Bag` is used to retain object references that need to be disposed of at some point in the future. When the bag is destroyed, all
	objects within the bag are also disposed of

	```lua
	local bag = Bag.new()
	local part = Instance.new("Part")
	bag:Add(part)
	bag:Add(part.Touched:Connect(function()
		print("Touched!")
	end))
	bag:Destroy() -- 'part' is destroyed and the 'Touched' connection is disconnected
	```
]=]
local Bag = {}
Bag.__index = Bag
Bag.className = "Bag"

--[=[
	@tag Static
	@return Bag -- The `Bag` object

	Constructs a new `Bag` object
]=]
function Bag.new(): Bag
	local self = setmetatable({
		_Destroyed = false,
		_Items = {},
		_Tracked = {},
		_DestroyingConnection = nil
	}, Bag)
	return self :: Bag
end

--[=[
	Deconstructs the `Bag` object and disposes of all objects within it
]=]
function Bag.Destroy(self: Bag)
	if self._Destroyed then
		return
	end

	self:Dispose()

	self._Destroyed = true

	self._Items = nil :: any
	self._Tracked = nil :: any
	if self._DestroyingConnection then
		self._DestroyingConnection:Disconnect()
		self._DestroyingConnection = nil
	end
end

--[=[
	@param item Item -- Item to retain a reference to
	@param disposeMethod string? -- An optional Dispose method name to invoke on the item when the bags disposed or destroyed
	@return Item -- The item that was passed in

	Adds an `Item` reference to the `Bag`. When the bags contents are disposed of or the bag is destroyed the item's Dispose method will be invoked and the reference
	to the item will be removed from the bag

	| Type | Dispose Method |
	| ---- | ------- |
	| `Instance` | `object:Destroy()` |
	| `RBXScriptConnection` | `object:Disconnect()` |
	| `function` | `object()` |
	| `thread` | `task.cancel(object)` |
	| `table` | `object:Destroy()` _or_ `object:Disconnect()` _or_ `object:destroy()` _or_ `object:disconnect()` |
	| `table` with `disposeMethod` | `object:disposeMethod()` |

	:::caution
	An error will be thrown if a Dispose method cannot be found for the object type that was added to the `Bag`
	:::

	```lua
	-- Adding a function to the `Bag` and then disposing of the bags contents will invoke the function
	Bag:Add(function()
		print("Disposed!")
	end)
	Bag:Dispose()

	-- Adding a table to the `Bag` and then disposing of the bags contents will invoke the tables `Destroy`, 'Disconnect' or their camelCased counterpart methods if they exist
	local class = {
		Destroy = function(self)
			print("Disposed!")
		end
	}
	Bag:Add(class)
	Bag:Dispose()

	-- Adding a Roblox `Instance` to the `Bag` and then disposing of the bags contents will also destroy the `Instance`
	local part = Instance.new("Part")
	Bag:Add(part)
	Bag:Dispose()

	-- You can define a custom Dispose method on a table and pass it in as the second argument. This will be invoked when the bags contents are disposed of
	local class = {
		CustomDisposeMethod = function(self)
			print("Disposed!")
		end
	}
	Bag:Add(class, "CustomDisposeMethod")
	Bag:Dispose()
	```
]=]
function Bag.Add<T>(self: Bag, item: T & Item, disposeMethod: string?): T
	assert(disposeMethod == nil or typeof(disposeMethod) == "string", "Argument #2 must be a string or nil")

	self:_AssertAlive()

	if self._Tracked[item] then
		return item
	end

	local resolvedDisposeMethod = disposeMethod or getDisposeMethod(item)

	local index = #self._Items + 1
	self._Items[index] = {
		Item = item,
		DisposeMethod = resolvedDisposeMethod,
	}

	self._Tracked[item] = index

	return item
end

--[=[
	@param item Item -- Item to Remove from the bag
	@return boolean -- Whether or not the item was removed

	Removes the item reference from the `Bag` and invokes its Dispose method. If the item was found and removed, `true` is returned, otherwise `false` is returned

	```lua
	local func = Bag:Add(function()
		print("Disposed!")
	end)
	Bag:Remove(func) -- "Disposed!" will be printed
	```
]=]
function Bag.Remove<T>(self: Bag, item: T & Item): boolean
	self:_AssertAlive()

	local index = self._Tracked[item]
	if not index then
		return false
	end

	local lastIndex = #self._Items
	local removed = self._Items[index]

	if index ~= lastIndex then
		local last = self._Items[lastIndex]
		self._Items[index] = last
		self._Tracked[last.Item] = index
	end

	self._Items[lastIndex] = nil
	self._Tracked[item] = nil

	invokeDisposeMethod(removed.Item, removed.DisposeMethod)

	return true
end

--[=[
	Disposes of all item references in the `Bag`. This is the same as invoking `Remove` on each object added to the `Bag`. The
	objects are disposed of in reverse order (LIFO - Last In, First Out), which is useful for proper cleanup of dependent resources

	```lua
	local part = Instance.new("Part")
	local connection = part.Touched:Connect(function()
		print("Touched!")
	end)
	Bag:Add(part)
	Bag:Add(connection)
	Bag:Dispose() -- 'connection' is disconnected first, then 'part' is destroyed
	```
]=]
function Bag.Dispose(self: Bag)
	self:_AssertAlive()

	local items = self._Items
	self._Items = {}
	self._Tracked = {}

	for i = #items, 1, -1 do
		local object = items[i]
		local success, errorMessage = pcall(invokeDisposeMethod, object.Item, object.DisposeMethod)
		if not success then
			warn("Bag failed to dispose item:", errorMessage)
		end
	end
end

--[=[
	@param instance Instance

	Attaches the `Bag` object to a Roblox `Instance`. Invoking this method will detach the `Bag` from any previously attached `Instance`. When
	the attached instance is removed from the game (its parent or ancestor's parent is set to `nil`), the Bag will automatically destroy
	itself. It's important that any references to the bag are still released when it's no longer being used

	:::caution
	An error will be thrown if `instance` is not a descendant of the DataModel
	:::
]=]
function Bag.Attach(self: Bag, instance: Instance)
	assert(typeof(instance) == "Instance", "Argument #1 must be an Instance")

	self:_AssertAlive()

	if not instance:IsDescendantOf(game) then
		error("Instance is not a descendant of the game DataModel", 2)
	end

	if self._DestroyingConnection then
		self._DestroyingConnection:Disconnect()
	end

	self._DestroyingConnection = instance.Destroying:Connect(function()
		self:Destroy()
	end)
end

function Bag:_AssertAlive()
	if self._Destroyed then
		error("Bag has been destroyed", 2)
	end
end

return Bag