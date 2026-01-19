extends RefCounted
class_name ObjectFactory

## Factory for creating object instances with optional initialization parameters.
## Supports both global classes and inner classes with UID-based type resolution.

var _inner_type: Dictionary[int, Resource]
var _inner_creater: Dictionary[int, Callable]

# ==============================================================================
# Public API - Registration
# ==============================================================================

## Registers a class type with optional initialization parameters.
## @param class_type: The Resource (script) to register.
## @param init_params: Optional array of parameters for the constructor.
func register(class_type: Resource, init_params := []) -> void:
	_register(class_type, init_params)

# ==============================================================================
# Public API - UID Conversion
# ==============================================================================

## Converts an object instance to its type UID.
## @param object: The object instance to get UID for.
## @return: The integer UID identifying the object's type.
func object_to_uid(object: Object) -> int:
	return _object_to_uid(object)

## Retrieves an object instance from its type UID.
## @param uid: The integer UID of the type to create.
## @return: A new instance of the type identified by the UID.
func uid_to_object(uid: int) -> Object:
	return _uid_to_object(uid)

# ==============================================================================
# Private Methods - Registration
# ==============================================================================

## Internal: Registers a class with factory.
## @param class_type: The Resource to register.
## @param init_params: Parameters for the constructor.
func _register(class_type: Resource, init_params: Array) -> void:
	var uid := _get_class_uid(class_type)
	_inner_type[uid] = class_type
	_inner_creater[uid] = _get_class_creater(uid, init_params)

# ==============================================================================
# Private Methods - UID Conversion
# ==============================================================================

## Internal: Converts object to type UID.
## @param object: The object instance.
## @return: The type UID.
func _object_to_uid(object: Object) -> int:
	var uid: int = 0
	var path: String = object.get_script().resource_path
	if path.is_empty():
		return _get_class_uid(object.get_script())
	return ResourceLoader.get_resource_uid(path)

## Internal: Creates instance from type UID.
## @param uid: The type UID.
## @return: A new instance.
func _uid_to_object(uid: int) -> Object:
	var creater := _inner_creater[uid]
	if creater == null:
		var path := ResourceUID.id_to_text(uid)
		assert(ResourceLoader.exists(path), "uid<%s> is not exists!" % path)
		return load(path).new()
	return creater.call()

## Internal: Gets UID for a class type.
## @param type: The Resource to get UID for.
## @return: The type UID.
func _get_class_uid(type: Resource) -> int:
	var path := "uid://%s" % type
	return ResourceUID.create_id_for_path(path)

## Internal: Creates a callable constructor with parameters.
## @param uid: The type UID.
## @param init_params: Constructor parameters.
## @return: Callable that creates a new instance.
func _get_class_creater(uid: int, init_params: Array) -> Callable:
	match init_params.size():
		0:
			return (func(inner_type: Dictionary[int, Resource], uid: int) -> Object:
				return inner_type[uid].new()
			).bind(_inner_type, uid)
		1:
			return (func(inner_type: Dictionary[int, Resource], uid: int, v1: Variant) -> Object:
				return inner_type[uid].new(v1)
			).bind(_inner_type, uid, init_params[0])
		2:
			return (func(inner_type: Dictionary[int, Resource], uid: int, v1: Variant, v2: Variant) -> Object:
				return inner_type[uid].new(v1, v2)
			).bind(_inner_type, uid, init_params[0], init_params[1])
		3:
			return (func(inner_type: Dictionary[int, Resource], uid: int, v1: Variant, v2: Variant, v3: Variant) -> Object:
				return inner_type[uid].new(v1, v2, v3)
			).bind(_inner_type, uid, init_params[0], init_params[1], init_params[2])
		4:
			return (func(inner_type: Dictionary[int, Resource], uid: int, v1: Variant, v2: Variant, v3: Variant, v4: Variant) -> Object:
				return inner_type[uid].new(v1, v2, v3, v4)
			).bind(_inner_type, uid, init_params[0], init_params[1], init_params[2], init_params[3])
		5:
			return (func(inner_type: Dictionary[int, Resource], uid: int, v1: Variant, v2: Variant, v3: Variant, v4: Variant, v5: Variant) -> Object:
				return inner_type[uid].new(v1, v2, v3, v4, v5)
			).bind(_inner_type, uid, init_params[0], init_params[1], init_params[2], init_params[3], init_params[4])
	return Callable()
