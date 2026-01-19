extends RefCounted
class_name ECSScheduler

## A DAG-based scheduler that manages ECSParallel system execution order.
## Automatically resolves dependencies between systems and handles component access conflicts.
## Systems are grouped into batches that can execute in parallel based on dependency analysis.

var _world: ECSWorld
var _threads_size: int
var _system_pool: Dictionary[StringName, ECSParallel]
var _system_graph: Dictionary[StringName, Array]
var _system_conflict: Dictionary[StringName, Dictionary]
var _system_group: Dictionary[StringName, int]
var _batch_systems: Array[Array]

# ==============================================================================
# Public API - System Management
# ==============================================================================

## Adds systems to the scheduler and configures their dependencies.
## Systems must override _list_components() to declare component access.
## @param systems: Array of ECSParallel instances to add.
## @return: This scheduler instance for method chaining.
## @assert: Each system must declare at least one component access.
func add_systems(systems: Array) -> ECSScheduler:
	for sys: ECSParallel in systems:
		assert(not sys._list_components().is_empty())
		_system_pool[sys.name()] = sys
	for sys: ECSParallel in systems:
		sys.fetch_before_systems(_set_system_before)
		sys.fetch_after_systems(_set_system_after)
		sys.fetch_conflict(_set_system_conflict)
		sys.fetch_group(_set_system_group)
		sys._set_world(_world)
	return self

## Clears all systems and built execution batches.
func clear() -> void:
	_system_pool.clear()
	_batch_systems.clear()
	_system_graph.clear()
	_system_conflict.clear()
	_system_group.clear()

## Builds the execution schedule by analyzing dependencies and conflicts.
## Must be called after adding all systems and before running.
## @return: This scheduler instance for method chaining.
## @assert: At least one system must be added.
func build() -> ECSScheduler:
	assert(not _system_pool.is_empty())
	_batch_systems.clear()
	if _system_pool.size() == 1:
		_batch_systems.append(_system_pool.values())
	else:
		_build_batch_systems()
	return self

## Runs one frame of system execution.
## Executes all batches and flushes queued commands.
## @param _delta: Time elapsed since last frame (unused, passed to systems).
func run(_delta: float = 0.0) -> void:
	_run_systems(_delta)
	_flush_commands()

# ==============================================================================
# Private Methods - Dependency Graph
# ==============================================================================

## Internal: Inserts a dependency edge into the system graph.
## @param key: System that must run first.
## @param value: System that depends on key (must run after key).
func _insert_graph_node(key: StringName, value: StringName) -> void:
	assert(_system_pool.has(value), "Scheduler must have system key [%s]!" % value)
	if not _system_graph.has(key):
		_system_graph[key] = []
	var list := _system_graph[key]
	if value in list:
		return
	list.append(value)

## Internal: Callback for systems declaring their before dependencies.
## @param name: System name.
## @param before_systems: Array of system names that must run after this system.
func _set_system_before(name: StringName, before_systems: Array) -> void:
	for key: StringName in before_systems:
		_insert_graph_node(name, key)

## Internal: Callback for systems declaring their after dependencies.
## @param name: System name.
## @param after_systems: Array of system names that must run before this system.
func _set_system_after(name: StringName, after_systems: Array) -> void:
	for key: StringName in after_systems:
		_insert_graph_node(key, name)

## Internal: Stores component access conflict information for a system.
## @param name: System name.
## @param table: Dictionary mapping component names to access modes.
func _set_system_conflict(name: StringName, table: Dictionary) -> void:
	_system_conflict[name] = table

## Internal: Stores scheduling group assignment for a system.
## @param name: System name.
## @param group: Integer group identifier.
func _set_system_group(name: StringName, group: int) -> void:
	_system_group[name] = group

# ==============================================================================
# Private Methods - Initialization & Execution
# ==============================================================================

## Internal: Creates a new scheduler for the given world.
## @param world: The ECSWorld this scheduler belongs to.
func _init(world: ECSWorld) -> void:
	_world = world

## Internal: Executes all systems in their scheduled batches.
## @param delta: Time elapsed since last frame.
func _run_systems(delta: float) -> void:
	for systems: Array in _batch_systems:
		var task_id := WorkerThreadPool.add_group_task(func(index: int):
			systems[index].thread_function(delta),
			systems.size())
		WorkerThreadPool.wait_for_group_task_completion(task_id)

## Internal: Flushes all commands queued by systems.
func _flush_commands() -> void:
	for systems: Array in _batch_systems:
		for sys: ECSParallel in systems:
			sys.flush_commands()

## Internal: Builds execution batches using dependency analysis.
func _build_batch_systems() -> void:
	DependencyBuilder.new()\
		.with_dag(_system_graph)\
		.with_conflict(_system_conflict)\
		.with_group(_system_group)\
		.build(func(batch_system_keys: Array):
		_batch_systems.append(batch_system_keys.map(func(key: StringName):
			return _system_pool[key]
		))
	)

# ==============================================================================
# Inner Class - DependencyBuilder
# ==============================================================================

## Helper class for building execution batches from dependency graph.
## Uses Kahn's algorithm for topological sorting with conflict-aware batching.
class DependencyBuilder extends RefCounted:
	var _graph: Dictionary[StringName, Array] = {}
	var _conflict: Dictionary[StringName, Dictionary] = {}
	var _group: Dictionary[StringName, int] = {}

	## Sets the dependency graph (DAG).
	## @param graph: Dictionary mapping system names to arrays of dependent systems.
	## @return: This builder for method chaining.
	func with_dag(graph: Dictionary[StringName, Array]) -> DependencyBuilder:
		_graph.merge(graph, true)
		return self

	## Sets the component access conflict table.
	## @param conf: Dictionary mapping system names to component access patterns.
	## @return: This builder for method chaining.
	func with_conflict(conf: Dictionary[StringName, Dictionary]) -> DependencyBuilder:
		_conflict.merge(conf, true)
		return self

	## Sets the system group assignments.
	## @param group: Dictionary mapping system names to group IDs.
	## @return: This builder for method chaining.
	func with_group(group: Dictionary[StringName, int]) -> DependencyBuilder:
		_group.merge(group, true)
		return self

	## Builds execution batches and invokes callback for each batch.
	## @param catch: Callable that receives Array of system names for each batch.
	func build(catch := Callable()) -> void:
		var all_systems: Array = _group.keys()
		var in_degree: Dictionary = {}
		
		for key: StringName in all_systems:
			in_degree[key] = 0
			
		for u: StringName in _graph:
			for v: StringName in _graph[u]:
				if in_degree.has(v):
					in_degree[v] += 1
					
		var ready_queue: Array[StringName] = []
		for key: StringName in all_systems:
			if in_degree[key] == 0:
				ready_queue.append(key)
				
		_sort_by_group(ready_queue)
		
		var result_batches: Array[Array] = []
		var processed_count: int = 0
		var total_count: int = all_systems.size()
		
		while processed_count < total_count:
			if ready_queue.is_empty():
				push_error("[ECS] Scheduler Cycle Detected! Dependency graph has a loop.")
				break
				
			var current_batch: Array[StringName] = []
			var batch_reads: Dictionary = {}
			var batch_writes: Dictionary = {}
			var next_loop_deferred: Array[StringName] = []
			var unlocked_nodes: Array[StringName] = []
			
			for sys_name: StringName in ready_queue:
				if _is_conflict(sys_name, batch_reads, batch_writes):
					next_loop_deferred.append(sys_name)
				else:
					current_batch.append(sys_name)
					_mark_access(sys_name, batch_reads, batch_writes)
			
			if current_batch.is_empty():
				push_error("[ECS] Scheduler Deadlock! Logic error or unsolvable resource conflict.")
				break
				
			result_batches.append(current_batch)
			processed_count += current_batch.size()
			
			for executed_sys: StringName in current_batch:
				if _graph.has(executed_sys):
					for neighbor: StringName in _graph[executed_sys]:
						if in_degree.has(neighbor):
							in_degree[neighbor] -= 1
							if in_degree[neighbor] == 0:
								unlocked_nodes.append(neighbor)
			
			_sort_by_group(unlocked_nodes)
			ready_queue = next_loop_deferred + unlocked_nodes
			
		for batch_keys: Array in result_batches:
			catch.call(batch_keys)

	## Checks if adding a system to the current batch would cause write conflicts.
	## Detects: (1) write-write conflict if batch has writes, (2) write-read conflict if batch has reads.
	## @param sys_name: System name to check.
	## @param batch_reads: Dictionary of components being read in current batch.
	## @param batch_writes: Dictionary of components being written in current batch.
	## @return: True if adding this system would cause a write conflict.
	func _is_conflict(sys_name: StringName, batch_reads: Dictionary, batch_writes: Dictionary) -> bool:
		var sys_access: Dictionary = _conflict.get(sys_name, {})
		for comp: StringName in sys_access:
			var access_type: int = sys_access[comp]
			if batch_writes.has(comp):
				return true
			if access_type == ECSParallel.READ_WRITE:
				if batch_reads.has(comp):
					return true
		return false

	## Marks component access for conflict detection.
	## @param sys_name: System name.
	## @param batch_reads: Dictionary to record read accesses.
	## @param batch_writes: Dictionary to record write accesses.
	func _mark_access(sys_name: StringName, batch_reads: Dictionary, batch_writes: Dictionary) -> void:
		var sys_access: Dictionary = _conflict.get(sys_name, {})
		for comp: StringName in sys_access:
			var access_type: int = sys_access[comp]
			if access_type == ECSParallel.READ_ONLY:
				batch_reads[comp] = true
			else:
				batch_writes[comp] = true

	## Sorts systems by group ID for deterministic execution order.
	## @param arr: Array of system names to sort.
	func _sort_by_group(arr: Array[StringName]) -> void:
		arr.sort_custom(func(a, b):
			return _group.get(a, 0) < _group.get(b, 0)
		)
