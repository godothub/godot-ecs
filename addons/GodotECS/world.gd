extends RefCounted
class_name ECSWorld

## The version identifier for this ECS framework implementation.
const VERSION = "1.0.0"

## Querier class for building complex entity queries.
const Querier = preload("querier.gd")

## QueryCache class for caching multi-view query results.
const QueryCache = preload("query_cache.gd")

## ECSRunner class for single-threaded system execution.
const ECSRunner = preload("runner.gd")

## When true, enables debug logging for ECS operations including entity/creation/destruction and component modifications.
var debug_print: bool

## When true, entities are created as DebugEntity instances with additional component tracking for debugging purposes.
var debug_entity: bool:
	set(v):
		debug_entity = v
		_create_entity_callback = _create_debug_entity if v else _create_common_entity

## Dictionary of event names to ignore in debug logging.
var ignore_notify_log: Dictionary

## Emitted when a system views components, used for tracking system access patterns.
## @param name: The name of the system that viewed components.
## @param components: Array of component names that were accessed.
signal on_system_viewed(name: StringName, components: Array)

## Emitted each frame during update, used to trigger system execution.
## @param delta: The time elapsed since the last frame in seconds.
signal on_update(delta: float)

var _name: StringName

var _entity_id: int = 0xFFFFFFFF
var _entity_pool: Dictionary
var _system_pool: Dictionary
var _event_pool := GameEventCenter.new()

var _type_component_dict: Dictionary
var _entity_component_dict: Dictionary
var _query_caches: Dictionary
var _scheduler_pool: Dictionary[StringName, ECSScheduler]
var _runner_pool: Dictionary[StringName, ECSRunner]

## Creates a new ECSWorld instance.
## @param name: Optional name for this world instance, defaults to "ECSWorld".
func _init(name := "ECSWorld") -> void:
	_name = name
	debug_entity = false

# ==============================================================================
# Public API - World Identity & Lifecycle
# ==============================================================================

## Returns the name identifier of this world.
## @return: The StringName identifier for this ECSWorld instance.
func name() -> StringName:
	return _name

## Cleans up all resources held by this world including systems, schedulers, and entities.
## Must be called before setting the world reference to null to prevent memory leaks.
func clear() -> void:
	remove_all_systems()
	remove_all_runners()
	remove_all_schedulers()
	remove_all_entities()

# ==============================================================================
# Public API - Entity Management
# ==============================================================================

## Creates a new entity and returns an ECSEntity wrapper.
## @param id: Optional specific entity ID to assign (0x1 to 0xFFFFFFFF). If 0, auto-generates next available ID.
## @return: ECSEntity wrapper for the newly created entity.
## @assert: Entity ID must be between 0 and 0xFFFFFFFF.
func create_entity(id: int = 0) -> ECSEntity:
	assert(id >= 0 and id <= 0xFFFFFFFF, "create_entity invalid id!")
	var eid: int = id if id >= 1 else _entity_id + 1
	if id == 0:
		_entity_id += 1
	remove_entity(eid)
	return _create_entity(eid)

## Removes an entity and all its components from the world.
## @param entity_id: The ID of the entity to remove.
## @return: True if the entity was successfully removed, false if entity didn't exist.
func remove_entity(entity_id: int) -> bool:
	if not remove_all_components(entity_id):
		return false
	if debug_print:
		print("entity <%s:%d> destroyed." % [_name, entity_id])
	_entity_component_dict.erase(entity_id)
	return _entity_pool.erase(entity_id)

## Removes all entities from the world.
## @return: Always returns true after completion.
func remove_all_entities() -> bool:
	for entity_id: int in _entity_pool.keys():
		remove_entity(entity_id)
	_entity_id = 0xFFFFFFFF
	return true

## Retrieves an entity wrapper by its ID.
## @param id: The entity ID to look up.
## @return: The ECSEntity wrapper, or null if entity doesn't exist.
func get_entity(id: int) -> ECSEntity:
	return _entity_pool.get(id)

## Returns all entity IDs currently in the world.
## @return: Array of integer entity IDs.
func get_entity_keys() -> Array:
	return _entity_pool.keys()

## Checks if an entity with the given ID exists in the world.
## @param id: The entity ID to check.
## @return: True if the entity exists, false otherwise.
func has_entity(id: int) -> bool:
	return _entity_pool.has(id)

# ==============================================================================
# Public API - Component Management
# ==============================================================================

## Adds a component to an entity.
## @param entity_id: The ID of the entity to add the component to.
## @param name: The StringName identifier for the component type.
## @param component: The ECSComponent instance to add. Defaults to empty ECSComponent if null.
## @return: True if the component was successfully added, false otherwise.
## @assert: Component must not already be attached to a world.
func add_component(entity_id: int, name: StringName, component := ECSComponent.new()) -> bool:
	assert(component._world == null)
	if not _add_entity_component(entity_id, name, component):
		return false
	component._name = name
	component._entity = get_entity(entity_id)
	component._set_world(self)
	for cache in _query_caches.values():
		cache.on_component_changed(entity_id, name, true)
	if debug_print:
		print("component <%s:%s> add to entity <%d>." % [_name, name, entity_id])
	var entity: ECSEntity = component._entity
	entity.on_component_added.emit(entity, component)
	return true

## Removes a component from an entity.
## @param entity_id: The ID of the entity to remove the component from.
## @param name: The StringName identifier for the component type to remove.
## @return: True if the component was successfully removed, false otherwise.
func remove_component(entity_id: int, name: StringName) -> bool:
	var c: ECSComponent = get_component(entity_id, name)
	if not c or not _remove_entity_component(entity_id, name):
		return false
	for cache in _query_caches.values():
		cache.on_component_changed(entity_id, name, false)
	if debug_print:
		print("component <%s:%s> remove from entity <%d>." % [_name, name, entity_id])
	var entity: ECSEntity = c._entity
	entity.on_component_removed.emit(entity, c)
	return true

## Removes all components from an entity.
## @param entity_id: The ID of the entity to clear components from.
## @return: True if all components were removed, false if entity didn't exist.
func remove_all_components(entity_id: int) -> bool:
	if not has_entity(entity_id):
		return false
	var entity_dict: Dictionary = _entity_component_dict[entity_id]
	for key: StringName in entity_dict.keys():
		remove_component(entity_id, key)
	return true

## Retrieves a specific component from an entity.
## @param entity_id: The ID of the entity to get the component from.
## @param name: The StringName identifier for the component type.
## @return: The ECSComponent instance, or null if not found.
func get_component(entity_id: int, name: StringName) -> ECSComponent:
	if not has_entity(entity_id):
		return null
	var entity_dict: Dictionary = _entity_component_dict[entity_id]
	if entity_dict.has(name):
		return entity_dict[name]
	return null

## Retrieves all components from an entity.
## @param entity_id: The ID of the entity to get components from.
## @return: Array of ECSComponent instances.
func get_components(entity_id: int) -> Array:
	if not has_entity(entity_id):
		return []
	var entity_dict: Dictionary = _entity_component_dict[entity_id]
	return entity_dict.values()

## Returns all component type names registered in this world.
## @return: Array of StringName component identifiers.
func get_component_keys() -> Array:
	return _type_component_dict.keys()

## Checks if an entity has a specific component.
## @param entity_id: The ID of the entity to check.
## @param name: The StringName identifier for the component type.
## @return: True if the entity has the component, false otherwise.
func has_component(entity_id: int, name: StringName) -> bool:
	if not has_entity(entity_id):
		return false
	var entity_dict: Dictionary = _entity_component_dict[entity_id]
	return entity_dict.has(name)

# ==============================================================================
# Public API - Query System
# ==============================================================================

## Retrieves all entities that have a specific component type (single-component view).
## @param name: The StringName identifier for the component type to query.
## @return: Array of ECSComponent instances for all entities with the component.
func view(name: StringName) -> Array:
	if not _type_component_dict.has(name):
		return []
	return _type_component_dict[name].values()

## Retrieves entities that have all specified component types (cached AND query).
## @param names: Array of StringName component types that must all be present.
## @return: Array of Dictionary views, each containing entity and component data.
func multi_view(names: Array) -> Array:
	var cache := multi_view_cache(names)
	return cache.results if cache else []

## Gets or creates a cached query for multi-component queries.
## @param names: Array of StringName component types to query.
## @return: QueryCache instance for the component combination, or null if names is empty.
func multi_view_cache(names: Array) -> QueryCache:
	if names.is_empty():
		return null
	
	var sorted_names = names.duplicate()
	sorted_names.sort()
	var cache_key = "_".join(sorted_names)
	
	var cache: QueryCache
	if _query_caches.has(cache_key):
		cache = _query_caches[cache_key]
	else:
		cache = QueryCache.new(self, sorted_names)
		_query_caches[cache_key] = cache
	
	return cache

## Creates a new Querier for building complex entity queries with filters.
## @return: A new Querier instance configured with this world.
func query() -> Querier:
	return Querier.new(self)

# ==============================================================================
# Public API - System Management
# ==============================================================================

## Adds a system to the world and connects it to the update cycle.
## @param name: The StringName identifier for the system.
## @param system: The ECSSystem instance to add.
## @return: True if the system was successfully added.
## @deprecated: Use ECSRunner.add_system() instead.
func add_system(name: StringName, system: ECSSystem) -> bool:
	push_warning("[Deprecated] add_system() is deprecated. Use ECSRunner.add_system() instead.")
	remove_system(name)
	_system_pool[name] = system
	system._set_name(name)
	system._set_world(self)
	set_system_update(name, true)
	system.on_enter(self)
	return true

## Removes a system from the world and disconnects it from the update cycle.
## @param name: The StringName identifier for the system to remove.
## @return: True if the system was found and removed.
func remove_system(name: StringName) -> bool:
	if not _system_pool.has(name):
		return false
	set_system_update(name, false)
	_system_pool[name].on_exit(self)
	return _system_pool.erase(name)

## Removes all systems from the world.
## @return: Always returns true after completion.
func remove_all_systems() -> bool:
	for name: StringName in _system_pool.keys():
		remove_system(name)
	return true

## Retrieves a system by its name.
## @param name: The StringName identifier for the system.
## @return: The ECSSystem instance, or null if not found.
func get_system(name: StringName) -> ECSSystem:
	if not _system_pool.has(name):
		return null
	return _system_pool[name]

## Returns all system names registered in this world.
## @return: Array of StringName system identifiers.
func get_system_keys() -> Array:
	return _system_pool.keys()

## Checks if a system with the given name exists.
## @param name: The StringName identifier for the system.
## @return: True if the system exists, false otherwise.
func has_system(name: StringName) -> bool:
	return _system_pool.has(name)

# ==============================================================================
# Public API - Event System
# ==============================================================================

## Registers a callable to receive notifications for a specific event.
## @param name: The StringName identifier for the event.
## @param c: The Callable to invoke when the event is triggered.
func add_callable(name: StringName, c: Callable) -> void:
	_event_pool.add_callable(name, c)

## Unregisters a callable from receiving event notifications.
## @param name: The StringName identifier for the event.
## @param c: The Callable to remove.
func remove_callable(name: StringName, c: Callable) -> void:
	_event_pool.remove_callable(name, c)

## Sends a notification event to all registered listeners.
## @param event_name: The StringName identifier for the event.
## @param value: Optional value data to pass with the notification.
func notify(event_name: StringName, value: Variant = null) -> void:
	if debug_print and not ignore_notify_log.has(event_name):
		print('notify <%s> "%s", %s.' % [_name, event_name, value])
	_event_pool.notify(event_name, value)

## Sends a GameEvent object to all registered listeners.
## @param e: The GameEvent instance to dispatch.
func send(e: GameEvent) -> void:
	if debug_print and not ignore_notify_log.has(e.name):
		print('send <%s> "%s", %s.' % [_name, e.name, e.data])
	_event_pool.send(e)

# ==============================================================================
# Public API - Update Cycle
# ==============================================================================

## Triggers the update cycle, emitting the on_update signal to execute all connected systems.
## @param delta: The time elapsed since the last frame in seconds.
## @deprecated: Use ECSRunner.run() instead.
func update(delta: float) -> void:
	push_warning("[Deprecated] update() is deprecated. Use ECSRunner.run() instead.")
	on_update.emit(delta)

## Enables or disables a system's update callback.
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

## Checks if a system is currently connected to the update cycle.
## @param name: The StringName identifier for the system.
## @return: True if the system's update callback is connected.
func is_system_updating(name: StringName) -> bool:
	var system := get_system(name)
	if system == null or not system.has_method("_on_update"):
		return false
	return on_update.is_connected(system._on_update)

# ==============================================================================
# Public API - Scheduler Management
# ==============================================================================

## Creates a new scheduler with the given name.
## @param name: The StringName identifier for the scheduler.
## @return: A new ECSScheduler instance.
## @assert: A scheduler with this name must not already exist.
func create_scheduler(name: StringName) -> ECSScheduler:
	assert(not _scheduler_pool.has(name))
	var result := ECSScheduler.new(self)
	_scheduler_pool[name] = result
	return result

## Destroys a scheduler and clears its resources.
## @param name: The StringName identifier for the scheduler to destroy.
## @return: True if the scheduler was found and destroyed.
func destroy_scheduler(name: StringName) -> bool:
	if not _scheduler_pool.has(name):
		return false
	var scheduler := _scheduler_pool[name]
	scheduler.clear()
	_scheduler_pool.erase(name)
	return true

## Retrieves a scheduler by its name.
## @param name: The StringName identifier for the scheduler.
## @return: The ECSScheduler instance, or null if not found.
func get_scheduler(name: StringName) -> ECSScheduler:
	return _scheduler_pool.get(name)

## Destroys all schedulers in the pool.
func remove_all_schedulers() -> void:
	var keys := _scheduler_pool.keys()
	while not keys.is_empty():
		destroy_scheduler(keys.pop_back())

# ==============================================================================
# Public API - Runner Management
# ==============================================================================

## Creates a new runner with the given name.
## @param name: The StringName identifier for the runner.
## @return: A new ECSRunner instance.
## @assert: A runner with this name must not already exist.
func create_runner(name: StringName) -> ECSRunner:
	assert(not _runner_pool.has(name))
	var result := ECSRunner.new(self)
	_runner_pool[name] = result
	return result

## Destroys a runner and clears its resources.
## @param name: The StringName identifier for the runner to destroy.
## @return: True if the runner was found and destroyed.
func destroy_runner(name: StringName) -> bool:
	if not _runner_pool.has(name):
		return false
	var runner := _runner_pool[name]
	runner.clear()
	_runner_pool.erase(name)
	return true

## Retrieves a runner by its name.
## @param name: The StringName identifier for the runner.
## @return: The ECSRunner instance, or null if not found.
func get_runner(name: StringName) -> ECSRunner:
	return _runner_pool.get(name)

## Destroys all runners in the pool.
func remove_all_runners() -> void:
	var keys := _runner_pool.keys()
	while not keys.is_empty():
		destroy_runner(keys.pop_back())

# ==============================================================================
# Private Methods - Internal Helpers
# ==============================================================================

## Internal: Gets or creates the component type list dictionary.
## @param name: The component type name.
## @return: Dictionary mapping entity IDs to component instances.
func _get_type_list(name: StringName) -> Dictionary:
	if not _type_component_dict.has(name):
		_type_component_dict[name] = {}
	return _type_component_dict[name]

## Internal: Gets a dictionary containing entity and specified components.
## @param e: The ECSEntity to query.
## @param names: Array of component names to retrieve.
## @return: Dictionary with "entity" key and component entries.
func _get_satisfy_components(e: ECSEntity, names: Array) -> Dictionary:
	var result := {
		"entity": e,
	}
	for c: ECSComponent in names.map(func(key: StringName):
		return get_component(e.id(), key)
	):
		result.set(c.name(), c)
	return result

## Internal: Adds a component to an entity's component dictionary.
## @param entity_id: The entity ID.
## @param name: The component name.
## @param component: The component instance.
## @return: True if successful.
func _add_entity_component(entity_id: int, name: StringName, component: ECSComponent) -> bool:
	if not has_entity(entity_id):
		return false
	var entity_dict: Dictionary = _entity_component_dict[entity_id]
	entity_dict[name] = component
	var type_list: Dictionary = _get_type_list(name)
	type_list[entity_id] = component
	return true

## Internal: Removes a component from an entity's component dictionary.
## @param entity_id: The entity ID.
## @param name: The component name.
## @return: True if successful.
func _remove_entity_component(entity_id: int, name: StringName) -> bool:
	if not has_entity(entity_id):
		return false
	var type_list: Dictionary = _type_component_dict[name]
	type_list.erase(entity_id)
	var entity_dict: Dictionary = _entity_component_dict[entity_id]
	return entity_dict.erase(name)

## Internal: Creates an entity wrapper and registers it in the world.
## @param eid: The entity ID.
## @return: The created ECSEntity wrapper.
func _create_entity(eid: int) -> ECSEntity:
	var e := _create_entity_callback.call(eid)
	_entity_pool[eid] = e
	_entity_component_dict[eid] = {}
	if debug_print:
		print("entity <%s:%d> created." % [_name, eid])
	return e

var _create_entity_callback: Callable

## Internal: Creates a standard ECSEntity instance.
## @param id: The entity ID.
## @return: A new ECSEntity wrapper.
func _create_common_entity(id: int) -> ECSEntity:
	return ECSEntity.new(id, self)

## Internal: Creates a DebugEntity instance for debugging.
## @param id: The entity ID.
## @return: A new DebugEntity wrapper.
func _create_debug_entity(id: int) -> ECSEntity:
	return DebugEntity.new(id, self)
