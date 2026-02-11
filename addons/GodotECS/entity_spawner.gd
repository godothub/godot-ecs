extends RefCounted
class_name ECSEntitySpawner

var _world: ECSWorld
var _entity: ECSEntity

func add(name: StringName, c := ECSComponent.new()) -> ECSEntitySpawner:
	_entity.add_component(name, c)
	return self
	
func _init(w: ECSWorld) -> void:
	_world = w
	_entity = _world.create_entity()
	
