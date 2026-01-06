extends RefCounted
class_name ECSScheduler

var _current_system: StringName
var _system_pool: Dictionary[StringName, ECSAsyncSystem]
var _system_graph: Dictionary[StringName, Array]

func add_systems(systems: Array) -> ECSScheduler:
	for sys: ECSAsyncSystem in systems:
		_system_pool[sys.name()] = sys
	for sys: ECSAsyncSystem in systems:
		sys.fetch_before_systems(_set_system_before)
		sys.fetch_after_systems(_set_system_after)
	return self
	
func run() -> void:
	pass
	
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
	
