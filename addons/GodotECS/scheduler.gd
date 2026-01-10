extends RefCounted
class_name ECSScheduler

var _world: ECSWorld
var _threads_size: int
var _system_pool: Dictionary[StringName, ECSParallel]
var _system_graph: Dictionary[StringName, Array]

# batch parallel systems
var _batch_systems: Array[Array]
var _active_systems_count: int = 0
var _batch_mutex := Mutex.new()

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
	
## Clear the scheduler
func clear() -> void:
	# clear workers
	for worker in _queue:
		worker.stop()
	_queue.clear()
	
	# clear system pool
	for sys: ECSParallel in _system_pool.values():
		sys.queue_free()
	_system_pool.clear()
	_system_graph.clear()
	
func build() -> void:
	_build_workers()
	
func run(_delta: float = 0.0) -> void:
	_run_systems(_delta)
	_flush_commands()
	
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
	_active_systems_count = systems.size()
	var index: int = 0
	for sys: ECSParallel in systems:
		# finish callback
		sys.finished = _system_finished
		# push task
		var worker: ECSWorker = _queue[index % _queue.size()]
		worker.push(ECSParallel.Task.new(sys.thread_function.bind(delta, worker.push_jobs, worker.steal_and_execute)))
		index += 1
		
func _system_finished() -> void:
	_batch_mutex.lock()
	_active_systems_count -= 1
	_batch_mutex.unlock()
	
func _wait_systems_completed() -> void:
	while true:
		# check completed
		_batch_mutex.lock()
		var active_count := _active_systems_count
		_batch_mutex.unlock()
		if active_count <= 0:
			break
		
		# work stealing
		if not _queue.pick_random().steal_and_execute():
			# delay 100 us
			OS.delay_usec(100)
	
func _build_workers() -> void:
	assert(_queue.is_empty())
	for i in _threads_size:
		_queue.append(ECSWorker.new(_queue))
	for sys: ECSWorker in _queue:
		sys.start()
	
