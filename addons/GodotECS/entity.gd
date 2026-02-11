extends RefCounted
class_name ECSEntity

## Emitted when a component is added to this entity.
## @param e: The ECSEntity that received the component.
## @param c: The ECSComponent that was added.
signal on_component_added(e: ECSEntity, c: ECSComponent)

## Emitted when a component is removed from this entity.
## @param e: The ECSEntity that lost the component.
## @param c: The ECSComponent that was removed.
signal on_component_removed(e: ECSEntity, c: ECSComponent)

var _id: int
var _world: WeakRef

## Creates a new ECSEntity wrapper.
## @param id: The unique identifier for this entity.
## @param world: Reference to the owning ECSWorld instance.
func _init(id: int, world: ECSWorld) -> void:
	_id = id
	_world = weakref(world)

# ==============================================================================
# Public API - Entity Lifecycle
# ==============================================================================

## Destroys this entity, removing it and all its components from the world.
## After destruction, the entity ID is set to 0 and valid() returns false.
func destroy() -> void:
	if _id != 0:
		world().remove_entity(_id)
		_id = 0

## Returns the unique identifier for this entity.
## @return: The integer entity ID.
func id() -> int:
	return _id

## Returns a reference to the ECSWorld that owns this entity.
## @return: The ECSWorld instance, or null if the world was destroyed.
func world() -> ECSWorld:
	return _world.get_ref()

## Checks if this entity is valid and still exists in the world.
## @return: True if the entity ID is non-zero and exists in the world.
func valid() -> bool:
	return _id >= 1 and world().has_entity(_id)

# ==============================================================================
# Public API - Event System
# ==============================================================================

## Sends a notification event to the world.
## @param event_name: The StringName identifier for the event.
## @param value: Optional value data to send with the event.
func notify(event_name: StringName, value = null) -> void:
	if _id == 0:
		return
	world().notify(event_name, value)

## Sends a GameEvent to the world.
## @param e: The GameEvent instance to dispatch.
func send(e: GameEvent) -> void:
	if _id == 0:
		return
	world().send(e)

# ==============================================================================
# Public API - Component Management
# ==============================================================================

## Adds a component instance, automatically deducing its name.
## @param component: The ECSComponent instance to add.
## @return: This ECSEntity for chaining.
## Usage: entity.add(CompHealth.new())
func add(component: ECSComponent) -> ECSEntity:
	if component == null: 
		return self
	var name = world().resolve_name(component)
	if not name.is_empty():
		add_component(name, component)
	return self

## Adds a component to this entity.
## @param key: The StringName identifier, Script, or Component class for the component type.
## @param component: The ECSComponent instance to add. Defaults to empty ECSComponent.
## @return: True if the component was successfully added.
## @deprecated: Use add() or remove() instead for shorter, cleaner syntax.
func add_component(key: Variant, component := ECSComponent.new()) -> bool:
	var name = world().resolve_name(key)
	if name.is_empty(): 
		return false
	return world().add_component(_id, name, component)

## Removes a component from this entity.
## @param key: The StringName identifier, Script, or Component class for the component type to remove.
## @return: True if the component was successfully removed.
func remove(key: Variant) -> bool:
	var name = world().resolve_name(key)
	if name.is_empty(): 
		return false
	return world().remove_component(_id, name)

## Removes a component from this entity.
## @param key: The StringName identifier, Script, or Component class for the component type to remove.
## @return: True if the component was successfully removed.
## @deprecated: Use remove() instead for shorter syntax.
func remove_component(key: Variant) -> bool:
	var name = world().resolve_name(key)
	if name.is_empty(): 
		return false
	return world().remove_component(_id, name)

## Removes all components from this entity.
## @return: True if all components were removed.
func remove_all() -> bool:
	return world().remove_all_components(_id)

## Removes all components from this entity.
## @return: True if all components were removed.
## @deprecated: Use remove_all() instead for shorter syntax.
func remove_all_components() -> bool:
	return world().remove_all_components(_id)

## Gets a specific component from this entity.
## @param key: The StringName identifier, Script, or Component class for the component type.
## @return: The ECSComponent instance, or null if not found.
func getc(key: Variant) -> ECSComponent:
	var name = world().resolve_name(key)
	if name.is_empty(): 
		return null
	return world().get_component(_id, name)

## Gets a specific component from this entity.
## @param key: The StringName identifier, Script, or Component class for the component type.
## @return: The ECSComponent instance, or null if not found.
## @deprecated: Use getc() instead for shorter syntax.
func get_component(key: Variant) -> ECSComponent:
	var name = world().resolve_name(key)
	if name.is_empty(): 
		return null
	return world().get_component(_id, name)

## Gets all components attached to this entity.
## @return: Array of ECSComponent instances.
func getc_all() -> Array:
	return world().get_components(_id)

## Gets all components attached to this entity.
## @return: Array of ECSComponent instances.
## @deprecated: Use getc_all() instead for shorter syntax.
func get_components() -> Array:
	return world().get_components(_id)

## Checks if this entity has a specific component.
## @param key: The StringName identifier, Script, or Component class for the component type.
## @return: True if the entity has the component.
func has(key: Variant) -> bool:
	var name = world().resolve_name(key)
	if name.is_empty():
		return false
	return world().has_component(_id, name)

## Checks if this entity has a specific component.
## @param key: The StringName identifier, Script, or Component class for the component type.
## @return: True if the entity has the component.
## @deprecated: Use has() instead for shorter syntax.
func has_component(key: Variant) -> bool:
	var name = world().resolve_name(key)
	if name.is_empty():
		return false
	return world().has_component(_id, name)

# ==============================================================================
# Private Methods
# ==============================================================================

## Returns a string representation of this entity.
## @return: String in the format "entity:<id>".
func _to_string() -> String:
	return "entity:%d" % _id
