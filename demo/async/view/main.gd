extends Node2D

var _world := ECSWorld.new("AsyncDemo")
var _scheduler: ECSScheduler

class LightWorkSystem extends ECSParallel:
	# override
	func _parallel() -> bool:
		return false
	func _list_components() -> Dictionary[StringName, int]:
		return {
			&"component_name": READ_ONLY,
		}
	func _view_components(_view: Dictionary, _commands: Commands) -> void:
		pass
class HeavyWorkSystem extends ECSParallel:
	# override
	func _parallel() -> bool:
		return true
	# override
	func _list_components() -> Dictionary[StringName, int]:
		return {
			&"component_name": READ_WRITE,
		}
	# override
	func _view_components(_view: Dictionary, _commands: Commands) -> void:
		pass
	
func _ready() -> void:
	_scheduler = _world.get_scheduler("demo")
	if _scheduler == null:
		_scheduler = _world.create_scheduler("demo").add_systems([
			LightWorkSystem.new(&"light_system").before([&"heavy_system"]),
			HeavyWorkSystem.new(&"heavy_system"),
		]).build()
	
func _process(delta: float) -> void:
	_scheduler.run(delta)
	
