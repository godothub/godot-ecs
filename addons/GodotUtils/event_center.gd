extends RefCounted
class_name GameEventCenter

## Central event management system for registering listeners and dispatching events.
## Provides pub/sub pattern for game event communication.

var _event_dict: Dictionary[StringName, _listener]

# ==============================================================================
# Public API - Listener Management
# ==============================================================================

## Registers a callable to receive events with the given name.
## @param name: The StringName identifier for the event.
## @param c: The Callable to invoke when the event is dispatched.
## @return: True if the callable was successfully registered.
func add_callable(name: StringName, c: Callable) -> bool:
	return _get_event_listener(name).add(c)

## Unregisters a callable from receiving events.
## @param name: The StringName identifier for the event.
## @param c: The Callable to remove.
## @return: True if the callable was successfully removed.
func remove_callable(name: StringName, c: Callable) -> bool:
	return _get_event_listener(name).remove(c)

# ==============================================================================
# Public API - Event Dispatch
# ==============================================================================

## Sends a notification event to all registered listeners.
## @param name: The StringName identifier for the event.
## @param value: Optional value data to send with the event.
func notify(name: StringName, value: Variant = null) -> void:
	send( GameEvent.new(name, value) )

## Dispatches a GameEvent to all registered listeners.
## @param e: The GameEvent to dispatch.
func send(e: GameEvent) -> void:
	e._event_center = weakref(self)
	_get_event_listener(e.name).receive(e)

# ==============================================================================
# Public API - Lifecycle
# ==============================================================================

## Clears all registered event listeners.
func clear() -> void:
	_event_dict.clear()

# ==============================================================================
# Private Methods
# ==============================================================================

## Internal: Gets or creates an event listener for the given name.
## @param name: The event name.
## @return: The _listener instance.
func _get_event_listener(name: StringName) -> _listener:
	if not _event_dict.has(name):
		_event_dict[name] = _listener.new()
	return _event_dict[name]

# ==============================================================================
# Inner Class - Listener
# ==============================================================================

## Internal helper class managing a single event's listeners.
class _listener extends RefCounted:
	signal _impl(e: GameEvent)
	
	## Adds a callable to receive this event.
	## @param c: The Callable to register.
	## @return: True if successfully added.
	func add(c: Callable) -> bool:
		if _impl.is_connected(c):
			return false
		_impl.connect(c)
		return true
	
	## Removes a callable from receiving this event.
	## @param c: The Callable to remove.
	## @return: True if successfully removed.
	func remove(c: Callable) -> bool:
		if not _impl.is_connected(c):
			return false
		_impl.disconnect(c)
		return true
	
	## Dispatches the event to all registered callables.
	## @param e: The GameEvent to dispatch.
	func receive(e: GameEvent) -> void:
		_impl.emit(e)
