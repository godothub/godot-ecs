extends RefCounted
class_name DataPack

## A simple wrapper around a Dictionary for packaging serialized data.
## Used as the return type for pack() operations.

var _dict: Dictionary

## Creates a new DataPack containing the given dictionary.
## @param dict: The Dictionary to wrap.
func _init(dict: Dictionary) -> void:
	_dict = dict

## Returns a duplicate of the underlying dictionary.
## @return: A copy of the packed data.
func data() -> Dictionary:
	return _dict.duplicate()
