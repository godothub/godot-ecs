extends Serializer
class_name ECSComponent

## Base class for all ECS components.
## Components are data containers attached to entities.
## Override _on_pack() and _on_unpack() for serialization support.

var _name: StringName = "unknown"
var _entity: ECSEntity
var _world: WeakRef

# ==============================================================================
# Public API - Identity
# ==============================================================================

## Returns the component type name.
## @return: The StringName identifier for this component type.
func name() -> StringName:
	return _name

## Returns the entity this component is attached to.
## @return: The ECSEntity instance, or null if not attached.
func entity() -> ECSEntity:
	return _entity

## Returns the world this component belongs to.
## @return: The ECSWorld instance, or null if component was detached.
func world() -> ECSWorld:
	return _world.get_ref() if _world else null

# ==============================================================================
# Public API - Lifecycle
# ==============================================================================

## Removes this component from its entity.
func remove_from_entity() -> void:
	entity().remove_component(_name)

# ==============================================================================
# Internal Methods
# ==============================================================================

## Internal: Sets the world reference for this component.
## @param world: The ECSWorld instance to attach.
func _set_world(world: ECSWorld) -> void:
	_world = weakref(world)

## Returns a string representation of this component.
## @return: String in the format "component:<name>".
func _to_string() -> String:
	return "component:%s" % _name

# ==============================================================================
# Override Methods - Serialization
# ==============================================================================

## Override: Called during serialization to pack component data.
## Override to implement custom serialization logic.
## @param ar: The Archive to write data to.
func _on_pack(ar: Archive) -> void:
	pass

## Override: Called during deserialization to unpack component data.
## Override to implement custom deserialization logic.
## @param ar: The Archive to read data from.
func _on_unpack(ar: Archive) -> void:
	pass

## Override: Called during version migration to convert data format.
## Override to implement data migration between component versions.
## @param ar: The Archive containing old-format data.
func _on_convert(ar: Archive) -> void:
	pass

## Override: Called during testing to validate component state.
## Override to implement component self-tests.
func _on_test() -> void:
	pass
