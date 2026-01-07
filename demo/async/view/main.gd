extends Node2D

@onready var _fps: Label = $fps

var _world := ECSWorld.new("AsyncDemo")

class LightSystem extends ECSParallel:
	pass
	
class HeavyWorkSystem extends ECSParallel:
	# override
	func _parallel() -> bool:
		return true
	# override
	func _list_components() -> Dictionary[StringName, int]:
		return {
			&"my_component": READ_ONLY,
			&"other_component": READ_WRITE,
		}
	# override
	func _view_components(_view: Dictionary) -> void:
		var c: MyComponent = _view.my_component
		c.value1 += 100
	
func _ready() -> void:
	_world.create_scheduler("demo").add_systems([
		LightSystem.new(&"light_system", self).before([&"heavy_system"]),
		HeavyWorkSystem.new(&"heavy_system", self).after([&"light_system"]),
	]).build()
	
func _physics_process(delta: float) -> void:
	_world.get_scheduler("demo").run(delta)
	_fps.text = "%.2f" % (1.0 / delta)
	
