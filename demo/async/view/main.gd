extends Node2D

var _world := ECSWorld.new("AsyncDemo")
var _scheduler: ECSScheduler

class LightSystem extends ECSParallel:
	# override
	func _parallel() -> bool:
		return false
	func _list_components() -> Dictionary[StringName, int]:
		return {
			&"my_component": READ_ONLY,
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
			&"my_component": READ_WRITE,
		}
	# override
	func _view_components(_view: Dictionary, _commands: Commands) -> void:
		var c: MyComponent = _view.my_component
		c.value1 += 100
	
func _ready() -> void:
	# 获取调度器分区
	_scheduler = _world.get_scheduler("demo")
	if _scheduler == null:
		_scheduler = _world.create_scheduler("demo").add_systems([
			LightSystem.new(&"light_system").before([&"heavy_system"]),
			HeavyWorkSystem.new(&"heavy_system"),
		]).build()
	
func _process(delta: float) -> void:
	# 运行特定分区调度器
	_scheduler.run(delta)
	
