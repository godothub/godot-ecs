extends Node
class_name ECSSystem

## A system class for processing component data on the main thread.
## Inherits from Node to utilize RPC functionality, which is essential for online games
## as it greatly simplifies the implementation of network synchronization.
## Systems can be added to the world and will receive update callbacks each frame.

var _name: StringName
var _world: ECSWorld
var _runner: ECSRunner

# ==============================================================================
# Public API - Identity & World
# ==============================================================================

## Returns the name identifier of this system.
## @return: The StringName identifier for this system.
func name() -> StringName:
	return _name

## Returns a reference to the ECSWorld this system belongs to.
## @return: The ECSWorld instance, or null if not attached to a world.
func world() -> ECSWorld:
	return _world

# ==============================================================================
# Public API - Query System
# ==============================================================================

## Queries entities with a specific component type.
## Emits on_system_viewed signal for tracking system access patterns.
## @param name: The StringName identifier for the component type.
## @return: Array of ECSComponent instances.
func view(name: StringName) -> Array:
	_world.on_system_viewed.emit(self.name(), [name])
	return _world.view(name)

## Queries entities with multiple specified component types (AND logic).
## Emits on_system_viewed signal for tracking system access patterns.
## @param names: Array of StringName component types to query.
## @return: Array of Dictionary views containing entity and component data.
func multi_view(names: Array) -> Array:
	_world.on_system_viewed.emit(self.name(), names)
	return _world.multi_view(names)

## Gets or creates a cached query for multi-component queries.
## @param names: Array of StringName component types to query.
## @return: QueryCache instance for the component combination.
func multi_view_cache(names: Array) -> ECSWorld.QueryCache:
	return _world.multi_view_cache(names)

## Creates a Querier for building complex entity queries with filters.
## @return: A new Querier instance configured with this system's world.
func query() -> ECSWorld.Querier:
	return _world.query()

func spawn() -> ECSEntitySpawner:
	return ECSEntitySpawner.new(_world)

# ==============================================================================
# Public API - Lifecycle Callbacks
# ==============================================================================

## Called when the system is added to the world.
## Triggers _on_enter override for system initialization.
## @param w: The ECSWorld this system is being added to.
func on_enter(w: ECSWorld) -> void:
	if w.debug_print:
		print("system <%s:%s> on_enter." % [world().name(), _name])
	_on_enter(w)

## Called when the system is removed from the world.
## Triggers _on_exit override for system cleanup and queues node for deletion.
## @param w: The ECSWorld this system is being removed from.
func on_exit(w: ECSWorld) -> void:
	if w.debug_print:
		print("system <%s:%s> on_exit." % [world().name(), _name])
	_on_exit(w)
	queue_free()

# ==============================================================================
# Public API - Event System
# ==============================================================================

## Sends a notification event to the world.
## @param event_name: The StringName identifier for the event.
## @param value: Optional value data to send with the event.
func notify(event_name: StringName, value = null) -> void:
	world().notify(event_name, value)

## Sends a GameEvent to the world.
## @param e: The GameEvent instance to dispatch.
func send(e: GameEvent) -> void:
	world().send(e)

# ==============================================================================
# Public API - Update Control
# ==============================================================================

## Enables or disables this system's update callback.
## @param enable: True to enable updates, false to disable.
func set_update(enable: bool) -> void:
	if _runner == null:
		world().set_system_update(name(), enable)
		return
	_runner.set_system_update(_name, enable)

## Checks if this system is currently connected to the update cycle.
## @return: True if the system's update callback is connected.
func is_updating() -> bool:
	if _runner == null:
		return world().is_system_updating(_name)
	return _runner.is_system_updating(_name)

# ==============================================================================
# Override Methods
# ==============================================================================

## Override: Called when the system is added to the world.
## Use for initializing system state and resources.
## @param w: The ECSWorld this system is being added to.
func _on_enter(w: ECSWorld) -> void:
	pass

## Override: Called when the system is removed from the world.
## Use for cleaning up resources and releasing references.
## @param w: The ECSWorld this system is being removed from.
func _on_exit(w: ECSWorld) -> void:
	pass

## Override: Called each frame when update cycle runs.
## Use for per-frame processing logic.
## @param _delta: The time elapsed since the last frame in seconds.
#func _on_update(_delta: float) -> void:
#	pass

# ==============================================================================
# Private Methods
# ==============================================================================

## Creates the system and optionally adds it as a child of a parent node.
## @param parent: Optional parent Node to attach this system to.
func _init(parent: Node = null):
	if parent:
		parent.add_child(self)

## Sets the system's name identifier.
## @param n: The StringName to assign as the system's name.
func _set_name(n: StringName) -> void:
	_name = n
	set_name(n)

## Sets the world reference for this system.
## @param w: The ECSWorld instance to attach.
func _set_world(w: ECSWorld) -> void:
	_world = w

func _set_runner(runner: ECSRunner) -> void:
	_runner = runner

## Returns a string representation of this system.
## @return: String in the format "system:<name>".
func _to_string() -> String:
	return "system:%s" % _name
