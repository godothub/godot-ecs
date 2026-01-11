extends Node2D

@onready var _fps: Label = $fps

var _world := ECSWorld.new("AsyncDemo")

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
	for i in 10000:
		var e := _world.create_entity()
		e.add_component("my_component", MyComponent.new())
	_world.create_scheduler("demo").add_systems([
		LightSystem.new(&"light_system"),
		HeavyWorkSystem.new(&"heavy_system"),
		LightSystem.new(&"light1"),
		LightSystem.new(&"light2"),
		LightSystem.new(&"light3"),
	]).build()
	
func _process(delta: float) -> void:
	var first := Time.get_unix_time_from_system()
	_fps.text = "%.2f" % (1.0 / delta)
	
	if _multi_thread:
		_world.get_scheduler("demo").run(delta)
		
	else:
		if _views.is_empty():
			_views = _world.multi_view(["my_component"])
			
		for i in 5:
			for view: Dictionary in _views:
				var c: MyComponent = view.my_component
				c.value1 += 100
	
	var second := Time.get_unix_time_from_system()
	printt("%.4f" % (second-first), "%.2f" % delta)
	
const _multi_thread = true
var _views: Array
