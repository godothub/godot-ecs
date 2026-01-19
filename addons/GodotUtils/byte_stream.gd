extends RefCounted
class_name ByteStream

## A byte stream handler for encoding and decoding Godot variants with
## optional compression support. Provides file I/O and variable encoding.

var _data: PackedByteArray
var _offset: int

# ==============================================================================
# Public API - File I/O
# ==============================================================================

## Opens a file and reads its contents into a ByteStream.
## @param path: The file path to read from.
## @return: A new ByteStream containing file data, or null on failure.
static func open(path: StringName) -> ByteStream:
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var bytes := f.get_buffer(f.get_length())
		f.close()
		return ByteStream.new(bytes)
	return null

## Writes the current byte data to a file.
## @param path: The file path to write to.
## @return: True if writing succeeded.
func write(path: StringName) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return false
	var ret := f.store_buffer(_data)
	f.close()
	return ret

# ==============================================================================
# Public API - Data Access
# ==============================================================================

## Returns the underlying byte array.
## @return: The PackedByteArray containing all data.
func data() -> PackedByteArray:
	return _data

## Returns the current read/write offset.
## @return: The integer offset position.
func offset() -> int:
	return _offset

## Seeks to a specific offset position.
## @param offset: The new offset position.
func seek(offset: int) -> void:
	_offset = offset

# ==============================================================================
# Public API - Variable Encoding
# ==============================================================================

## Encodes a variant into the byte stream.
## @param value: The variant to encode.
## @param compression_mode: Compression algorithm (-1 for none, or FileAccess compression constants).
func encode_var(value: Variant, compression_mode: int = -1) -> void:
	if compression_mode <= -1:
		var bytes := var_to_bytes(value)
		_data.append_array(bytes)
		_offset += bytes.size()
	else:
		var bytes := var_to_bytes(value)
		_append_s32(bytes.size())
		_append_array(bytes.compress(compression_mode))

## Decodes a variant from the byte stream.
## @param compression_mode: Compression algorithm (-1 for none, or FileAccess compression constants).
## @return: The decoded variant.
func decode_var(compression_mode: int = -1) -> Variant:
	if compression_mode <= -1:
		var var_offset := _offset
		_offset += _data.decode_var_size(_offset)
		return _data.decode_var(var_offset)
	var buffer_size: int = _pull_s32()
	var bytes := _pull_array()
	var decom_bytes: PackedByteArray = bytes.decompress(buffer_size, compression_mode)
	return decom_bytes.decode_var(0)

# ==============================================================================
# Private Methods - Internal
# ==============================================================================

## Internal: Expands the buffer if needed.
## @param size: Minimum required size.
func _expand(size: int) -> void:
	if _offset + size >= _data.size():
		_data.resize( maxi(_offset + size, _data.size() + size) )

# ==============================================================================
# Private Methods - Encoding
# ==============================================================================

## Internal: Appends a signed 32-bit integer.
## @param value: The integer to write.
func _append_s32(value: int) -> void:
	_expand(4)
	_data.encode_s32(_offset, value)
	_offset += 4

## Internal: Appends a byte array with length prefix.
## @param bytes: The array to append.
func _append_array(bytes: PackedByteArray) -> void:
	_append_s32(bytes.size())
	_data.append_array(bytes)
	_offset += bytes.size()

# ==============================================================================
# Private Methods - Decoding
# ==============================================================================

## Internal: Reads a signed 32-bit integer.
## @return: The decoded integer.
func _pull_s32() -> int:
	var v: int = _data.decode_s32(_offset)
	_offset += 4
	return v

## Internal: Reads a length-prefixed byte array.
## @return: The decoded byte array.
func _pull_array() -> PackedByteArray:
	var var_size := _pull_s32()
	var bytes := _data.slice(_offset, _offset + var_size)
	_offset += var_size
	return bytes

## Creates a new ByteStream with optional initial data.
## @param bytes: Initial byte data for the stream.
func _init(bytes: PackedByteArray = []) -> void:
	_data = bytes
