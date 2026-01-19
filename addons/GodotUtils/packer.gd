extends RefCounted
class_name DataPacker

## Base abstract class for serializable data containers.
## Provides pack/unpack interface with signals for lifecycle callbacks.

## Emitted after a successful pack operation.
## @param sender: This DataPacker instance.
## @param pack: The resulting DataPack.
signal on_packed(sender: DataPacker, pack: DataPack)

## Emitted after a successful unpack operation.
## @param sender: This DataPacker instance.
## @param pack: The DataPack that was unpacked.
signal on_unpacked(sender: DataPacker, pack: DataPack)

# ==============================================================================
# Public API - Serialization
# ==============================================================================

## Packs the data into a DataPack.
## Calls _pack() override and emits on_packed signal on success.
## @return: The resulting DataPack, or null if packing failed.
func pack() -> DataPack:
	var dp := _pack()
	if dp:
		on_packed.emit(self, dp)
	return dp

## Unpacks data from a DataPack.
## Calls _unpack() override and emits on_unpacked signal on success.
## @param dp: The DataPack to unpack from.
## @return: True if unpacking succeeded.
func unpack(dp: DataPack) -> bool:
	if _unpack(dp):
		on_unpacked.emit(self, dp)
		return true
	return false

# ==============================================================================
# Override Methods
# ==============================================================================

## Override: Performs actual packing logic.
## @return: The resulting DataPack, or null on failure.
func _pack() -> DataPack:
	return null

## Override: Performs actual unpacking logic.
## @param data: The DataPack to unpack from.
## @return: True if unpacking succeeded.
func _unpack(data: DataPack) -> bool:
	return false
