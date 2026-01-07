extends RefCounted
class_name ECSScheduler

var _current_system: StringName
var _system_pool: Dictionary[StringName, ECSParallel]
var _system_graph: Dictionary[StringName, Array]
var _threads_size: int
var _world: ECSWorld

# batch parallel systems
var _batch_systems: Array[Array]
var _systems_completed: BatchSystemCompleted

# worker queue
var _queue: Array[ECSWorker]

func add_systems(systems: Array) -> ECSScheduler:
	for sys: ECSParallel in systems:
		_system_pool[sys.name()] = sys
	for sys: ECSParallel in systems:
		sys.fetch_before_systems(_set_system_before)
		sys.fetch_after_systems(_set_system_after)
		sys._set_world(_world)
	return self
	
func build() -> void:
	_build_workers()
	
func run(_delta: float = 0.0) -> void:
	_run_systems(_delta)
	_flush_commands()
	
## Finish the scheduler
func finish() -> void:
	_world = null
	# stop all worker
	for worker in _queue:
		worker.stop()
	_queue.clear()
	
func _insert_graph_node(key: StringName, value: StringName) -> void:
	assert(_system_pool.has(value), "Scheduler must have system key [%s]!" % value)
	if not _system_graph.has(key):
		_system_graph[key] = []
	var list := _system_graph[key]
	if value in list:
		return
	list.append(value)
	
func _set_system_before(name: StringName, before_systems: Array) -> void:
	for key: StringName in before_systems:
		_insert_graph_node(name, key)
	
func _set_system_after(name: StringName, after_systems: Array) -> void:
	for key: StringName in after_systems:
		_insert_graph_node(key, name)
	
func _init(world: ECSWorld, threads_size: int) -> void:
	_world = world
	_threads_size = threads_size if threads_size >= 1 else OS.get_processor_count()
	
func _run_systems(delta: float) -> void:
	for systems: Array in _batch_systems:
		_post_batch_systems(systems, delta)
		_wait_systems_completed()
	
func _flush_commands() -> void:
	for systems: Array in _batch_systems:
		for sys: ECSParallel in systems:
			sys.commands().flush()
	
func _post_batch_systems(systems: Array, delta: float) -> void:
	_systems_completed = BatchSystemCompleted.new(systems)
	var temp_systems := systems.duplicate()
	var index: int = 0
	while not temp_systems.is_empty():
		var sys: ECSParallel = temp_systems.pop_back()
		var worker := _queue[index % _queue.size()]
		worker.push(SystemTask.new(sys.thread_function.bind(delta)))
		index += 1
	
func _wait_systems_completed() -> void:
	while not _systems_completed.value:
		# work stealing
		var task: ECSWorker.Job = _queue.pick_random().steal()
		if task:
			task.execute()
	
func _build_workers() -> void:
	assert(_queue.is_empty())
	for i in _threads_size:
		_queue.append(ECSWorker.new(_queue))
		_queue.back().start()
	
# ==============================================================================
class BatchSystemCompleted extends RefCounted:
	var value: bool:
		set(v):
			pass
		get:
			return _count == _max
	var _mutex := Mutex.new()
	var _count: int = 0
	var _max: int = 0
	func _init(systems: Array) -> void:
		_max = -1 if systems.is_empty() else systems.size()
		for sys: ECSParallel in systems:
			sys.finished = _completed
	func _completed() -> void:
		_mutex.lock()
		_count += 1
		_mutex.unlock()
		
class SystemTask extends ECSWorker.Job:
	var _task: Callable
	func _init(task: Callable) -> void:
		_task = task
	func execute() -> void:
		_task.call()
	
