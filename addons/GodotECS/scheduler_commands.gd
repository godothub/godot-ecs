extends RefCounted

class Operation extends RefCounted:
	func execute() -> void:
		pass
	
var _operations: Array[Operation]

func merge(other_commands: Variant) -> void:
	_operations.append_array(other_commands._operations)
	
func flush() -> void:
	for op in _operations:
		op.execute()
	_operations.clear()
	
func clear() -> void:
	_operations.clear()
	
func is_empty() -> bool:
	return _operations.is_empty()
	
