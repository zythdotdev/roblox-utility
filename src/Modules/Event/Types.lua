export type EventConnection = {
	className: string,
	connected: boolean,

	_event: Event,

	new: (event: Event) -> EventConnection,
	destroy: (self: EventConnection) -> (),
	disconnect: (self: EventConnection) -> ()
}

export type Event = {
	className: string,

	_bindableEvent: BindableEvent,
	_bindableEventConnection: RBXScriptConnection?,
	_connections: {[EventConnection]: EventConnection},
	_callbacks: {[EventConnection]: (...any) -> ()},
	_values: {{any}},

	new: () -> Event,
	destroy: (self: Event) -> (),
	connect: (self: Event, callback: (...any) -> ()) -> EventConnection,
	fire: (self: Event, ...any) -> ()
}

return table.freeze({})