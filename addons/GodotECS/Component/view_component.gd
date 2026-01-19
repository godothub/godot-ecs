extends ECSComponent
class_name ECSViewComponent

## A component that associates a Godot Node with an entity.
## Useful for connecting ECS entities with scene graph nodes and their
## transform hierarchies.

## The Godot Node associated with this entity.
var view: Node

## Creates a new ECSViewComponent with an optional Node reference.
## @param v: The Node to associate with this component.
func _init(v: Node = null) -> void:
	view = v
