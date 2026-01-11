extends RefCounted
class_name ECSParallel

enum {
	READ_ONLY = 0,
	READ_WRITE,
}

const Commands = preload("scheduler_commands.gd")

class Task extends ECSWorker.Job:
	var _task: Callable
	func _init(task: Callable) -> void:
		_task = task
	func execute() -> void:
		_task.call()

var finished := _empty_finished

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
var _commands: Commands
var _delta: float
var _sub_systems: Array[ECSParallel]

## Return current system's name.
func name() -> StringName:
	return _name
	
func commands() -> Commands:
	return _commands
	
func before(systems: Array) -> ECSParallel:
	_before_list = systems
	return self
	
func after(systems: Array) -> ECSParallel:
	_after_list = systems
	return self
	
func in_set(value: int) -> ECSParallel:
	_group = value
	return self
	
## Internal function
func fetch_before_systems(querier: Callable) -> void:
	querier.call(_name, _before_list)
	
## Internal function
func fetch_after_systems(querier: Callable) -> void:
	querier.call(_name, _after_list)
	
## Internal function
func fetch_conflict(querier: Callable) -> void:
	querier.call(_name, _list_components())
	
func fetch_group(querier: Callable) -> void:
	querier.call(_name, _group)
	
## Returns the length of the component query / list.
func views_count() -> int:
	return _views.size()
	
# final
func thread_function(delta: float, task_poster := Callable(), steal_and_execute := Callable()) -> void:
	# view list components
	_views = _world.multi_view(_list_components().keys())
	# empty check
	if _views.is_empty():
		_on_finished()
		return
		
	# save delta
	_delta = delta
		
	if _parallel():
		# parallel processing
		if _sub_systems.size() < _views.size():
			# create sub parallel systems
			var SelfType = _self_type()
			assert(SelfType, "ECSParallel needs to implement the _self_type() method when parallel execution of subtasks is required!")
			for i in _views.size() - _sub_systems.size():
				var sys: ECSParallel = SelfType.new("SubSystem")
				_sub_systems.append(sys)
		# create job list
		var jobs: Array[ECSWorker.Job]
		jobs.resize(_views.size())
		for i in _views.size():
			var sys: ECSParallel = _sub_systems[i]
			var view: Dictionary = _views[i]
			sys._delta = delta
			sys.finished = _sub_system_finished
			jobs[i] = Task.new(
				(func(sys: ECSParallel, view: Dictionary):
					sys._view_components(view)
					sys.finished.call())
				.bind(sys, view)
			)
		# some init
		_sub_jobs_count = jobs.size()
		# post jobs
		task_poster.call(jobs)
		# wait sub jobs completed
		while true:
			# check completed
			_sub_mutex.lock()
			var active_count := _sub_jobs_count
			_sub_mutex.unlock()
			if active_count <= 0:
				break
			# work stealing
			steal_and_execute.call()
			
		# merge all commands
		for i in _views.size():
			var commands := _sub_systems[i].commands()
			if commands.is_empty():
				continue
			_commands.merge(commands)
			commands.clear()
	else:
		# non-parallel processing
		for view: Dictionary in _views:
			_view_components(view)
		
	# notify completed
	_on_finished()
	
# ==============================================================================
# override
## Indicates to the external system whether to process component data in parallel, similar in effect to query.par_iter() in Bevy.
func _parallel() -> bool:
	return false
	
# override
## duplicate self: It is required when sub-tasks need to be executed in parallel
func _self_type() -> Resource:
	return null
	
# override
## Returns the list of components that the current system is interested in, along with their read/write access permissions.
func _list_components() -> Dictionary[StringName, int]:
	return {}
	
# override
## A function that processes component data.
func _view_components(_view: Dictionary) -> void:
	pass
	
# ==============================================================================
# final
func _init(name: StringName, parent: Node = null) -> void:
	_name = name
	_commands = Commands.new()
	
# ==============================================================================
# private
func _set_world(w: ECSWorld) -> void:
	_world = w
	
# private
func _empty_finished() -> void:
	pass
	
func _on_finished() -> void:
	var _finished := finished
	finished = _empty_finished
	_finished.call()
	
var _sub_jobs_count: int = 0
var _sub_mutex := Mutex.new()
var _sub_jobs_completed := Semaphore.new()
	
func _sub_system_finished() -> void:
	_sub_mutex.lock()
	_sub_jobs_count -= 1
	_sub_mutex.unlock()
	
