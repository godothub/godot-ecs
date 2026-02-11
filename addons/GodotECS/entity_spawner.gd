extends RefCounted
class_name ECSEntitySpawner

var _world: ECSWorld
var _entity: ECSEntity

## Supports: add("Name", comp) OR add(comp_instance)
func add(p1: Variant, p2: ECSComponent = null) -> ECSEntitySpawner:
	var name: StringName
	var component: ECSComponent
	
	if p1 is ECSComponent:
		component = p1
		name = _world.resolve_name(component)
	else:
		name = _world.resolve_name(p1)
		component = p2 if p2 else ECSComponent.new()
	
	if not name.is_empty():
		_entity.add_component(name, component)
		
	return self
	
func _init(w: ECSWorld) -> void:
	_world = w
	_entity = _world.create_entity()
	
