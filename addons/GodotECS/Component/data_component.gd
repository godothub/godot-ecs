extends ECSComponent
class_name ECSDataComponent

## A component that stores a single variable data value.
## Provides built-in serialization for the data property and emits
## on_data_changed signal when the value is modified.

## The variable data value stored in this component.
var data: Variant

## Emitted when the data value is modified via set_data().
## @param sender: The ECSDataComponent that was modified.
## @param data: The new data value.
signal on_data_changed(sender: ECSDataComponent, data)

## Creates a new ECSDataComponent with the specified initial value.
## @param v: The initial value to store.
func _init(v: Variant) -> void:
	data = v

# ==============================================================================
# Public API - Data Management
# ==============================================================================

## Sets the data value and emits on_data_changed signal.
## @param v: The new value to store.
func set_data(v: Variant) -> void:
	data = v
	on_data_changed.emit(self, data)

# ==============================================================================
# Override Methods - Serialization
# ==============================================================================

## Override: Packs the data value into the archive.
## @param ar: The Archive to write data to.
func _on_pack(ar: Archive) -> void:
	ar.set_var("data", data)

## Override: Unpacks the data value from the archive.
## @param ar: The Archive to read data from.
func _on_unpack(ar: Archive) -> void:
	data = ar.get_var("data")
