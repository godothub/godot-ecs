extends ECSComponent
class_name MyComponent

var value1: int:
	set(v):
		value1 = v
		on_score_changed.emit(value1)

var value2: float:
	set(v):
		value2 = v
		on_seconds_changed.emit(value2)

signal on_score_changed(value: int)
signal on_seconds_changed(value: float)

# override
func _on_pack(ar: Archive) -> void:
	# Serialization
	# ar.version = 1
	ar.set_var("value1", value1)
	ar.set_var("value2", value2)
	
# override
func _on_unpack(ar: Archive) -> void:
	# Deserialization
	value1 = ar.get_var("value1", 0)
	value2 = ar.get_var("value2", 0.0)
	
# override
func _on_convert(ar: Archive) -> void:
	# Component data upgrade program for archived version compatibility
	match ar.version:
		0:	# from version 0 to version 1
			# example
			ar.set_var("value3", ar.get_var("value1", 0))
	
# override
func _on_test() -> void:
	# some test
	var ar := InOutArchive.new({})
	ar.set_var("value1", 1)
	ar.set_var("value2", 1.0)
	
	while ar.version < 1:
		self.convert(ar)
		ar.version += 1
		
		match ar.version:
			1:
				assert(ar.get_var("value3", 0) == 1)
	
