extends RefCounted
class_name ECSParallel

## Access mode constant for read-only component access.
enum {
	READ_ONLY = 0,
	## Access mode constant for read-write component access.
	READ_WRITE,
}

## Commands class reference for command buffer operations.
const Commands = preload("scheduler_commands.gd")

var delta: float:
	set(v):
		pass
	get:
		return _delta

var _name: StringName
var _views: Array
var _before_list: Array
var _after_list: Array
var _group: int
var _world: ECSWorld
var _delta: float

var _root_commands: Commands
var _sub_commands: Array[Commands]

# ==============================================================================
# Public API - Identity & World
# ==============================================================================

## Returns the name identifier of this system.
## @return: The StringName identifier.
func name() -> StringName:
	return _name

## Returns a reference to the ECSWorld this system belongs to.
## @return: The ECSWorld instance.
func world() -> ECSWorld:
	return _world

# ==============================================================================
# Public API - Dependency Configuration
# ==============================================================================

## Declares that this system must run before the specified systems.
## @param systems: Array of system names that must run after this system.
## @return: This ECSParallel instance for method chaining.
func before(systems: Array) -> ECSParallel:
	_before_list = systems
	return self

## Declares that this system must run after the specified systems.
## @param systems: Array of system names that must run before this system.
## @return: This ECSParallel instance for method chaining.
func after(systems: Array) -> ECSParallel:
	_after_list = systems
	return self

## Assigns this system to a scheduling group.
## @param value: Integer group identifier.
## @return: This ECSParallel instance for method chaining.
func in_set(value: int) -> ECSParallel:
	_group = value
	return self

# ==============================================================================
# Public API - Internal Callbacks (Called by Scheduler)
# ==============================================================================

## Internal: Fetches systems that this system must run before.
## @param querier: Callable that receives (system_name, before_list).
func fetch_before_systems(querier: Callable) -> void:
	querier.call(_name, _before_list)

## Internal: Fetches systems that this system must run after.
## @param querier: Callable that receives (system_name, after_list).
func fetch_after_systems(querier: Callable) -> void:
	querier.call(_name, _after_list)

## Internal: Fetches component access pattern for conflict detection.
## @param querier: Callable that receives (system_name, component_table).
func fetch_conflict(querier: Callable) -> void:
	querier.call(_name, _list_components())

## Internal: Fetches scheduling group assignment.
## @param querier: Callable that receives (system_name, group_id).
func fetch_group(querier: Callable) -> void:
	querier.call(_name, _group)

# ==============================================================================
# Public API - Execution
# ==============================================================================

## Returns the number of component views currently queried.
## @return: Integer count of queried views.
func views_count() -> int:
	return _views.size()

## Flushes all queued commands (both root and thread-local).
## Commands are executed on the main thread after parallel processing.
func flush_commands() -> void:
	for c: Commands in _sub_commands:
		c.flush(_world)
	_root_commands.flush(_world)

## Main entry point for system execution.
## Called by the scheduler to process component data.
## @param delta: Time elapsed since last frame in seconds.
func thread_function(delta: float) -> void:
	_views = _world.multi_view(_list_components().keys())
	if _views.is_empty():
		return
		
	_delta = delta
		
	if _parallel():
		if _sub_commands.size() > _views.size():
			_sub_commands.resize(_views.size())
		else:
			for i in _views.size() - _sub_commands.size():
				_sub_commands.append(Commands.new())
		var task_id := WorkerThreadPool.add_group_task(
			_sub_view_components.bind(_views, _sub_commands),
			_views.size(),
		)
		WorkerThreadPool.wait_for_group_task_completion(task_id)
	else:
		for view: Dictionary in _views:
			_view_components(view, _root_commands)

# ==============================================================================
# Override Methods
# ==============================================================================

## Override: Determines whether component processing runs in parallel.
## Similar to query.par_iter() in Bevy ECS.
## @return: True to enable parallel processing using WorkerThreadPool.
func _parallel() -> bool:
	return false

## Override: Returns the list of components this system accesses with their read/write permissions.
## @return: Dictionary mapping component StringName to access mode (READ_ONLY or READ_WRITE).
func _list_components() -> Dictionary[StringName, int]:
	return {}

## Override: Processes component data for a single view.
## Override this method to implement system logic.
## @param _view: Dictionary containing entity and component data for matched entities.
## @param _commands: Commands buffer for scheduling entity modifications.
func _view_components(_view: Dictionary, _commands: Commands) -> void:
	pass

# ==============================================================================
# Private Methods
# ==============================================================================

## Internal: Creates a new ECSParallel system.
## @param name: The StringName identifier for this system.
func _init(name: StringName) -> void:
	_name = name
	_root_commands = Commands.new()

## Internal: Sets the world reference for this system.
## @param w: The ECSWorld instance to attach.
func _set_world(w: ECSWorld) -> void:
	_world = w

## Internal: Worker function for parallel view processing.
## @param index: Index of this worker thread.
## @param _views: Array of view dictionaries to process.
## @param _commands: Array of command buffers for each worker.
func _sub_view_components(index: int, _views: Array, _commands: Array) -> void:
	_view_components(_views[index], _commands[index])
	
