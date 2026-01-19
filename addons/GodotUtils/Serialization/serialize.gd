extends RefCounted
class_name Serializer

## Base class for serializable objects providing pack/unpack/convert/test interface.
## Used by ECSComponent and other serializable classes for data persistence.

const Archive = preload("archive.gd")
const InputArchive = preload("input_archive.gd")
const OutputArchive = preload("output_archive.gd")
const InOutArchive = preload("inout_archive.gd")

# ==============================================================================
# Public API - Serialization
# ==============================================================================

## Packs this object into an archive for serialization.
## Calls _on_pack() override to perform actual packing.
## @param ar: The Archive to write data to.
func pack(ar: Archive) -> void:
	_on_pack(ar)

## Unpacks this object from an archive for deserialization.
## Calls _on_unpack() override to perform actual unpacking.
## @param ar: The Archive to read data from.
func unpack(ar: Archive) -> void:
	_on_unpack(ar)

## Converts serialized data between versions.
## Calls _on_convert() override to perform version migration.
## @param ar: The Archive containing data to convert.
func convert(ar: Archive) -> void:
	_on_convert(ar)

## Runs self-tests to validate component state.
## Calls _on_test() override to perform tests.
func test() -> void:
	_on_test()

# ==============================================================================
# Override Methods
# ==============================================================================

## Override: Serializes this object into the archive.
## @param ar: The Archive to write data to.
func _on_pack(ar: Archive) -> void:
	pass

## Override: Deserializes this object from the archive.
## @param ar: The Archive to read data from.
func _on_unpack(ar: Archive) -> void:
	pass

## Override: Converts serialized data between format versions.
## @param ar: The Archive containing old-format data.
func _on_convert(ar: Archive) -> void:
	pass

## Override: Performs self-validation tests.
func _on_test() -> void:
	pass
