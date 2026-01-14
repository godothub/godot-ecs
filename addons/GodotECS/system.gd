extends Node
class_name ECSSystem

var _name: StringName
var _world: WeakRef

func name() -> StringName:
	return _name
	
func world() -> ECSWorld:
	return _world.get_ref()
	
func view(name: StringName) -> Array:
	var w := world()
	w.on_system_viewed.emit(self.name(), [name])
	return w.view(name)
	
func multi_view(names: Array) -> Array:
	var w := world()
	w.on_system_viewed.emit(self.name(), names)
	return w.multi_view(names)
	
func multi_view_cache(names: Array) -> ECSWorld.QueryCache:
	return world().multi_view_cache(names)
	
func query() -> ECSWorld.Querier:
	return world().query()
	
func get_remote_sender_id() -> int:
	return multiplayer.get_remote_sender_id()
	
func get_rpc_unique_id() -> int:
	return multiplayer.get_unique_id()
	
func is_server() -> bool:
	return multiplayer.is_server()
	
func is_peer_connected() -> bool:
	return peer().get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	
func peer() -> MultiplayerPeer:
	return multiplayer.multiplayer_peer
	
func set_peer(peer: MultiplayerPeer) -> void:
	multiplayer.multiplayer_peer = peer
	
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
	_world = weakref(w)
	
func _to_string() -> String:
	return "system:%s" % _name
	
