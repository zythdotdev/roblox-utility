local Event = require(script.Parent.Event)

local NetworkEvent = require(script.NetworkEvent)
local NetworkRequest = require(script.NetworkRequest)
local NetworkValue = require(script.NetworkValue)

--[=[
	@within Connection
	@interface Event
	@field Connect (self: Event, callback: (...any) -> ()) -> EventConnection
	@field Once (self: Event, callback: (...any) -> ()) -> EventConnection
	@field WaitAsync (self: Event, timeout: number?) -> ...any

	An interface that respresents an event that can be connected to.
]=]
export type Event = Event.Self

--[=[
	@within Connection
	@interface EventConnection
	@field Disconnect () -> ()
	@field IsConnected () -> boolean

	An interface that respresents a connection to an event. This `EventConnection` object can be used to
	disconnect the callback from the event.

	```lua
	print(connection:IsConnected()) -- true
	connection:Disconnect()
	print(connection:IsConnected()) -- false
	```
]=]
export type EventConnection = Event.EventConnection

--[=[
	@within Connection
	@type NetworkEvent NetworkEvent
]=]
export type NetworkEvent = NetworkEvent.Self

--[=[
	@within Connection
	@type NetworkRequest NetworkRequest
]=]
export type NetworkRequest = NetworkRequest.Self

--[=[
	@within Connection
	@type NetworkValue NetworkValue
]=]
export type NetworkValue = NetworkValue.Self

--[=[
	@class Connection

	The `Connection` package provides access the following network modules:

	- [NetworkEvent](/api/NetworkEvent)
	- [NetworkRequest](/api/NetworkRequest)
	- [NetworkValue](/api/NetworkValue)

	To begin using the package, require it and access the various modules through the returned table.

	```lua
	local Connection = require(Packages.Connection)
	local NetworkEvent = Connection.NetworkEvent
	local NetworkRequest = Connection.NetworkRequest
	local NetworkValue = Connection.NetworkValue
	```
]=]
local Connection = {
	NetworkEvent = NetworkEvent,
	NetworkRequest = NetworkRequest,
	NetworkValue = NetworkValue
}

return Connection