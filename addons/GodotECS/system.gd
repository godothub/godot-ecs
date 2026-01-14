## A system class for processing component data on the main thread.
## It inherits from Node to utilize RPC functionality, 
## which is essential for online games as it greatly simplifies the implementation of network synchronizatio.
extends Node
class_name ECSSystem

var _name: StringName
var _world: ECSWorld

func name() -> StringName:
	return _name
	
func world() -> ECSWorld:
	return _world
	
func view(name: StringName) -> Array:
	_world.on_system_viewed.emit(self.name(), [name])
	return _world.view(name)
	
func multi_view(names: Array) -> Array:
	_world.on_system_viewed.emit(self.name(), names)
	return _world.multi_view(names)
	
func multi_view_cache(names: Array) -> ECSWorld.QueryCache:
	return _world.multi_view_cache(names)
	
func query() -> ECSWorld.Querier:
	return _world.query()
	
func on_enter(w: ECSWorld) -> void:
	if w.debug_print:
		print("system <%s:%s> on_enter." % [world().name(), _name])
	_on_enter(w)
	
func on_exit(w: ECSWorld) -> void:
	if w.debug_print:
		print("system <%s:%s> on_exit." % [world().name(), _name])
	_on_exit(w)
	queue_free()
	
func notify(event_name: StringName, value = null) -> void:
	world().notify(event_name, value)
	
func send(e: GameEvent) -> void:
	world().send(e)
	
func set_update(enable: bool) -> void:
	world().set_system_update(name(), enable)
	
func is_updating() -> bool:
	return world().is_system_updating(_name)
	
# ==============================================================================
# override function
	
# override
func _on_enter(w: ECSWorld) -> void:
	pass
	
# override
func _on_exit(w: ECSWorld) -> void:
	pass
	
# override
#func _on_update(_delta: float) -> void:
#	pass
	
# ==============================================================================
# private function
	
func _init(parent: Node = null):
	if parent:
		parent.add_child(self)
	
func _set_name(n: StringName) -> void:
	_name = n
	set_name(n)
	
func _set_world(w: ECSWorld) -> void:
	_world = w
	
func _to_string() -> String:
	return "system:%s" % _name
	
