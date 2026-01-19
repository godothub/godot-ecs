extends ECSEntity
class_name DebugEntity

## An entity wrapper with additional component tracking for debugging purposes.
## Maintains a local dictionary of components for inspection without
## requiring access to the world entity component dictionary.

var _components: Dictionary[StringName, ECSComponent]
var _groups: Dictionary[StringName, bool]

## Adds a component to this entity and tracks it locally.
## @param name: The StringName identifier for the component type.
## @param component: The ECSComponent instance to add.
## @return: True if the component was successfully added.
func add_component(name: StringName, component := ECSComponent.new()) -> bool:
	_components[name] = component
	return super.add_component(name, component)

## Removes a component from this entity and stops tracking it.
## @param name: The StringName identifier for the component type to remove.
## @return: True if the component was successfully removed.
func remove_component(name: StringName) -> bool:
	_components.erase(name)
	return super.remove_component(name)

## Removes all components from this entity and clears tracking.
## @return: True if all components were removed.
func remove_all_components() -> bool:
	_components.clear()
	return super.remove_all_components()
