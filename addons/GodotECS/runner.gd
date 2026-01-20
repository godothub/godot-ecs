extends RefCounted
class_name ECSRunner

## A sequential system executor for single-threaded system updates.
## Provides system grouping and management similar to ECSScheduler but without parallel execution.

var _world: ECSWorld
var _system_pool: Dictionary[StringName, ECSSystem]
var _update_enabled: Dictionary[StringName, bool] = {}

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
	_update_enabled[name] = true
	system._set_name(name)
	system._set_world(_world)
	system.on_enter(_world)
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
	_update_enabled.erase(name)
	_system_pool[name].on_exit(_world)
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
## @param delta: Time elapsed since last frame in seconds.
func run(delta: float) -> void:
	for sys: ECSSystem in _system_pool.values():
		if _is_update_enabled(sys.name()) and sys.has_method("_on_update"):
			sys._on_update(delta)

## Enables or disables a system's update callback.
## @param name: The StringName identifier for the system.
## @param enable: True to enable updates, false to disable.
func set_system_update(name: StringName, enable: bool) -> void:
	if _system_pool.has(name):
		_update_enabled[name] = enable

## Enables or disables all systems' update callbacks.
## @param enable: True to enable all updates, false to disable all.
func set_systems_update(enable: bool) -> void:
	for name: StringName in _system_pool.keys():
		_update_enabled[name] = enable

## Checks if a system's update callback is enabled.
## @param name: The StringName identifier for the system.
## @return: True if the system's update is enabled.
func is_system_updating(name: StringName) -> bool:
	if not _system_pool.has(name):
		return false
	return _update_enabled.get(name, false)

# ==============================================================================
# Private Methods
# ==============================================================================

## Creates a new runner for the given world.
## @param world: The ECSWorld this runner belongs to.
func _init(world: ECSWorld) -> void:
	_world = world

## Internal: Checks if a system's update is enabled.
## @param name: System name.
## @return: True if update is enabled.
func _is_update_enabled(name: StringName) -> bool:
	return _update_enabled.get(name, true)

## Returns a string representation of this runner.
## @return: String in the format "runner:<world_name>".
func _to_string() -> String:
	return "runner:%s" % _world.name()
