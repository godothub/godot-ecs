extends Node
class_name ECSParallel

enum {
	READ_ONLY = 0,
	READ_WRITE,
}

const Commands = preload("scheduler_commands.gd")

var finished := func() -> void:
	pass

var delta: float:
	set(v):
		pass
	get:
		return _delta

var _name: StringName
var _views: Array
var _before_list: Array
var _after_list: Array
var _world: ECSWorld
var _commands: Commands = Commands.new()
var _delta: float

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
	
## Internal function
func fetch_before_systems(querier: Callable) -> void:
	querier.call(_name, _before_list)
	
## Internal function
func fetch_after_systems(querier: Callable) -> void:
	querier.call(_name, _after_list)
	
## Returns the length of the component query / list.
func views_count() -> int:
	return _views.size()
	
# final
func thread_function(delta: float) -> void:
	# view list components
	_views = _world.multi_view(_list_components().keys())
	# empty check
	if _views.is_empty():
		return
		
	# save delta
	_delta = delta
		
	if _parallel():
		# parallel processing
		var task_id := WorkerThreadPool.add_group_task(func(index: int):
			_view_components(_views[index]),
			_views.size()
		)
		WorkerThreadPool.wait_for_group_task_completion(task_id)
	else:
		# non-parallel processing
		for view: Dictionary in _views:
			_view_components(view)
		
	# notify completed
	finished.call()
	
# ==============================================================================
# override
## Indicates to the external system whether to process component data in parallel, similar in effect to query.par_iter() in Bevy.
func _parallel() -> bool:
	return false
	
# override
## Returns the list of components that the current system is interested in, along with their read/write access permissions.
func _list_components() -> Dictionary[StringName, int]:
	return {}
	
# override
## A function that processes component data.
func _view_components(_view: Dictionary) -> void:
	pass
	
# ==============================================================================
# private
func _init(name: StringName, parent: Node = null) -> void:
	_name = name
	set_name("parallel_%s" % name)
	if parent:
		parent.add_child(self)
	
func _set_world(w: ECSWorld) -> void:
	_world = w
	
