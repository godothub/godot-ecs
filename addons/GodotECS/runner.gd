extends RefCounted
class_name ECSRunner

## A sequential system executor for single-threaded system updates.
## Provides system grouping and management similar to ECSScheduler but without parallel execution.

var _world: ECSWorld
var _system_pool: Dictionary[StringName, ECSSystem]

## Emitted each frame during run, used to trigger system execution.
## @param delta: The time elapsed since the last frame in seconds.
signal on_update(delta: float)

# ==============================================================================
# Public API - System Management
# ==============================================================================

## Adds a system to this runner.
## @param name: The StringName identifier for the system.
## @param system: The ECSSystem instance to add.
## @return: This runner instance for method chaining.
func add_system(name: StringName, system: ECSSystem) -> ECSRunner:
	remove_system(name)
	_system_pool[name] = system
	system._set_name(name)
	system._set_world(_world)
	system.on_enter(_world)
	set_system_update(name, true)
	return self

## Adds multiple systems at once.
## @param systems: Dictionary mapping system names to ECSSystem instances.
## @return: This runner instance for method chaining.
func add_systems(systems: Dictionary) -> ECSRunner:
	for key: StringName in systems:
		add_system(key, systems[key])
	return self

## Removes a system from this runner.
## @param name: The StringName identifier for the system to remove.
## @return: True if the system was found and removed.
func remove_system(name: StringName) -> bool:
	if not _system_pool.has(name):
		return false
	var system := _system_pool[name]
	if system.has_method("_on_update"):
		if on_update.is_connected(system._on_update):
			on_update.disconnect(system._on_update)
	system.on_exit(_world)
	return _system_pool.erase(name)

## Clears all systems from this runner.
func clear() -> void:
	for name: StringName in _system_pool.keys():
		remove_system(name)

## Retrieves a system by its name.
## @param name: The StringName identifier for the system.
## @return: The ECSSystem instance, or null if not found.
func get_system(name: StringName) -> ECSSystem:
	if not _system_pool.has(name):
		return null
	return _system_pool[name]

## Returns all systems in this runner.
## @return: Array of ECSSystem instances.
func get_systems() -> Array:
	return _system_pool.values()

# ==============================================================================
# Public API - Update Control
# ==============================================================================

## Runs one frame of system execution for all enabled systems.
## Emits on_update signal to trigger all connected systems.
## @param delta: Time elapsed since last frame in seconds.
func run(delta: float) -> void:
	on_update.emit(delta)

## Enables or disables a system's update callback.
## Connects or disconnects system from the on_update signal.
## @param name: The StringName identifier for the system.
## @param enable: True to enable updates, false to disable.
func set_system_update(name: StringName, enable: bool) -> void:
	var system := get_system(name)
	if system == null or not system.has_method("_on_update"):
		return
	if enable:
		if not on_update.is_connected(system._on_update):
			on_update.connect(system._on_update)
	else:
		if on_update.is_connected(system._on_update):
			on_update.disconnect(system._on_update)

## Enables or disables all systems' update callbacks.
## @param enable: True to enable all updates, false to disable all.
func set_systems_update(enable: bool) -> void:
	for name: StringName in _system_pool.keys():
		set_system_update(name, enable)

## Checks if a system's update callback is enabled.
## @param name: The StringName identifier for the system.
## @return: True if the system's update callback is connected.
func is_system_updating(name: StringName) -> bool:
	var system := get_system(name)
	if system == null or not system.has_method("_on_update"):
		return false
	return on_update.is_connected(system._on_update)

# ==============================================================================
# Private Methods
# ==============================================================================

## Creates a new runner for the given world.
## @param world: The ECSWorld this runner belongs to.
func _init(world: ECSWorld) -> void:
	_world = world

## Returns a string representation of this runner.
## @return: String in the format "runner:<world_name>".
func _to_string() -> String:
	return "runner:%s" % _world.name()
