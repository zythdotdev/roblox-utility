type Bag = {
	className: string,

	_items: {{item: Item, disposeMethod: string}},
	_destroyingConnection: RBXScriptConnection?,

	new: () -> Bag,
	destroy: (self: Bag) -> (),
	add: <T>(self: Bag, item: T & Item, disposeMethod: string?) -> T,
	remove: <T>(self: Bag, item: T & Item) -> boolean,
	dispose: (self: Bag) -> (),
	attach: (self: Bag, instance: Instance) -> ()
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
type Function = ((...any) -> any)

--[=[
	@within Bag
	@type Self Bag
]=]
export type Self = Bag

--[=[
	@within Bag
	@type Instance Instance

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
	error("Failed to get dispose method for object type '" .. objectType .. "' " .. tostring(object), 3)
end

local function invokeDisposeMethod(item: Item, disposeMethod: string)
	if disposeMethod == FUNCTION_DISPOSE_METHOD then
		(item :: Function)()
	elseif disposeMethod == THREAD_DISPOSE_METHOD then
		pcall(task.cancel, item)
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
	objects within the bag are also disposed of. This class is inspired by Trove, Maid and Janitor but implements a camelCased API and has
	a few minor differences in how it handles disposing objects

	```lua
	local bag = Bag.new()
	local part = Instance.new("Part")
	bag:add(part)
	bag:add(part.Touched:Connect(function()
		print("Touched!")
	end))
	bag:destroy() -- 'part' is destroyed and the 'Touched' connection is disconnected
	```
]=]
local Bag = {}
Bag.__index = Bag
Bag.className = "Bag"

--[=[
	@return Bag -- The `Bag` object

	Constructs a new `Bag` object
]=]
function Bag.new(): Bag
	local self = setmetatable({
		_items = {},
		_destroyingConnection = nil
	}, Bag)
	return self
end

--[=[
	Deconstructs the `Bag` object
]=]
function Bag.destroy(self: Bag)
	self:dispose()
	self._items = nil
	if self._destroyingConnection then
		self._destroyingConnection:Disconnect()
		self._destroyingConnection = nil
	end
end

--[=[
	@param item Item -- Item to retain a reference to
	@param disposeMethod string? -- An optional dispose method name to invoke on the item when the bags disposed or destroyed
	@return item Item -- The item that was passed in

	Adds an `Item` reference to the `Bag`. When the bags contents are disposed of or the bag is destroyed the item's dispose method will be invoked and the reference
	to the item will be removed from the bag.

	| Type | Dispose Method |
	| ---- | ------- |
	| `Instance` | `object:Destroy()` |
	| `RBXScriptConnection` | `object:Disconnect()` |
	| `function` | `object()` |
	| `thread` | `task.cancel(object)` |
	| `table` | `object:Destroy()` _or_ `object:Disconnect()` _or_ `object:destroy()` _or_ `object:disconnect()` |
	| `table` with `disposeMethod` | `object:disposeMethod()` |

	:::caution
	An error will be thrown if a dispose method cannot be found for the object type that was added to the `Bag`
	:::

	```lua
	-- Adding a function to the `Bag` and then disposing of the bags contents will invoke the function
	Bag:add(function()
		print("Disposed!")
	end)
	Bag:dispose()

	-- Adding a table to the `Bag` and then disposing of the bags contents will invoke the tables `destroy`, 'disconnect' or their PascalCased counterpart methods if they exist
	local class = {
		destroy = function(self)
			print("Disposed!")
		end
	}
	Bag:add(class)
	Bag:dispose()

	-- Adding a Roblox `Instance` to the `Bag` and then disposing of the bags contents will also destroy the `Instance`
	local part = Instance.new("Part")
	Bag:add(part)
	Bag:dispose()

	-- You can define a custom dispose method on a table and pass it in as the second argument. This will be invoked when the bags contents are disposed of
	local class = {
		customDisposeMethod = function(self)
			print("Disposed!")
		end
	}
	Bag:add(class, "customDisposeMethod")
	Bag:dispose()
	```
]=]
function Bag.add<T>(self: Bag, item: T & Item, disposeMethod: string?): T
	table.insert(self._items, {item, if disposeMethod then disposeMethod else getDisposeMethod(item)})
	return item
end

--[=[
	@param item Item -- Item to remove from the bag
	@return boolean -- Whether or not the item was removed

	Removes the item reference from the `Bag` and invokes its dispose method. If the item was found and removed, `true` is returned, otherwise `false` is returned

	```lua
	local func = Bag:add(function()
		print("Disposed!")
	end)
	Bag:remove(func) -- "Disposed!" will be printed
	```
]=]
function Bag.remove<T>(self: Bag, item: T & Item): boolean
	for i, itemData in ipairs(self._items) do
		if itemData[1] ~= item then continue end
		local count = #self._items
		self._items[i] = self._items[count]
		self._items[count] = nil
		invokeDisposeMethod(itemData[1], itemData[2])
		return true
	end
	return false
end

--[=[
	Disposes of all item references in the `Bag`. This is the same as invoking `remove` on each object added to the `Bag`. The
	ordering in which the objects are disposed of isn't guaranteed to match the order in which they were added

	```lua
	local part = Instance.new("Part")
	local connection = part.Touched:Connect(function()
		print("Touched!")
	end)
	Bag:add(part)
	Bag:add(connection)
	Bag:dispose() -- 'part' is destroyed and 'connection' is disconnected
	```
]=]
function Bag.dispose(self: Bag)
	for _, object in self._items do
		invokeDisposeMethod(object[1], object[2])
	end
	table.clear(self._items)
end

--[=[
	@param instance Instance

	Attaches the `Bag` object to a Roblox `Instance`. Invoking this method will detach the `Bag` from any previously attached `Instance`. When
	the attached instance is removed from the game (its parent or ancestor's parent is set to `nil`), the Bag will automatically destroy
	itself. It's important that any references to the bag are still released when it's no longer being used

	:::caution
	An error will be thrown if `instance` is not a descendant of the game's DataModel
	:::
]=]
function Bag.attach(self: Bag, instance: Instance)
	assert(typeof(instance) == "Instance", "Argument #1 must be an Instance")

	if not instance:IsDescendantOf(game) then
		error("Instance is not a descendant of the game DataModel", 2)
	end

	if self._destroyingConnection then
		self._destroyingConnection:Disconnect()
	end

	self._destroyingConnection = instance.Destroying:Connect(function()
		self:destroy()
	end)
end

return table.freeze(Bag)