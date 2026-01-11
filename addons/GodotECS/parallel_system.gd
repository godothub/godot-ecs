extends RefCounted
class_name ECSParallel

enum {
	READ_ONLY = 0,
	READ_WRITE,
}

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

## Return current system's name.
func name() -> StringName:
	return _name
	
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
	
func flush_commands() -> void:
	for c: Commands in _sub_commands:
		c.flush()
	_root_commands.flush()
	
# final
func thread_function(delta: float, task_poster := Callable(), steal_and_execute := Callable()) -> void:
	# view list components
	if _views.is_empty():
		_views = _world.multi_view(_list_components().keys())
	# empty check
	if _views.is_empty():
		return
		
	# save delta
	_delta = delta
		
	if _parallel():
		if _sub_commands.size() > _views.size():
			_sub_commands.resize(_views.size())
		else:
			for i in _views.size() - _sub_commands.size():
				_sub_commands.append(Commands.new())
		var task_id := WorkerThreadPool.add_group_task(func(index: int):
			_view_components(_views[index], _sub_commands[index]),
			_views.size(),
		)
		WorkerThreadPool.wait_for_group_task_completion(task_id)
	else:
		# non-parallel processing
		for view: Dictionary in _views:
			_view_components(view, _root_commands)
		
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
func _view_components(_view: Dictionary, _commands: Commands) -> void:
	pass
	
# ==============================================================================
# final
func _init(name: StringName) -> void:
	_name = name
	_root_commands = Commands.new()
	
# ==============================================================================
# private
func _set_world(w: ECSWorld) -> void:
	_world = w
	
