extends DataPacker
class_name ECSWorldPacker

## A serializer for ECSWorld instances that handles complete world state
## including all entities, components, and component data.

# ==============================================================================
# Public API - Factory Configuration
# ==============================================================================

## Sets the object factory for component type resolution during serialization.
## Required for registering inner class components.
## @param f: The ObjectFactory instance to use.
## @return: This packer instance for method chaining.
func with_factory(f: ObjectFactory) -> ECSWorldPacker:
	_factory = f
	return self

## Returns the current object factory.
## @return: The ObjectFactory instance.
func factory() -> ObjectFactory:
	return _factory

# ==============================================================================
# Override Methods - Serialization
# ==============================================================================

## Internal: Creates a DataPack containing the complete world state.
## @return: DataPack with entities, components, and metadata.
func _pack() -> DataPack:
	var dict := {
		"version": _w.VERSION,
	}
	var pack := DataPack.new(dict)
	_pack_entities(dict)
	return pack

## Internal: Restores world state from a DataPack.
## @param pack: The DataPack containing serialized world state.
## @return: True if unpacking succeeded.
func _unpack(pack: DataPack) -> bool:
	return _unpack_entities(pack.data())

# ==============================================================================
# Private Members
# ==============================================================================

var _w: ECSWorld
var _filter: Array[StringName]
var _factory := ObjectFactory.new()

## Creates a new ECSWorldPacker for the specified world.
## @param w: The ECSWorld to serialize.
## @param filter: Optional array of component names to filter during packing.
func _init(w: ECSWorld, filter: Array[StringName] = []) -> void:
	_w = w
	_filter = filter

# ==============================================================================
# Private Methods - Packing
# ==============================================================================

## Internal: Packs all entities into the dictionary.
## @param dict: The dictionary to populate with entity data.
func _pack_entities(dict: Dictionary) -> void:
	var entity_data := {}
	var uid_list: Array[int]
	
	if _filter.is_empty():
		for eid: int in _w.get_entity_keys():
			var e := _w.get_entity(eid)
			var entity_dict := {
				"components": {},
			}
			_pack_components(e, entity_dict["components"], uid_list)
			entity_data[e.id()] = entity_dict
	else:
		for views: Dictionary in _w.multi_view(_filter):
			var e: ECSEntity = views.entity
			var entity_dict := {
				"components": {},
			}
			_pack_components(e, entity_dict["components"], uid_list)
			entity_data[e.id()] = entity_dict
	
	dict["entities"] = entity_data
	dict["uid_list"] = uid_list
	dict["last_entity_id"] = _w._entity_id

## Internal: Packs all components of an entity.
## @param e: The entity whose components to pack.
## @param dict: The dictionary to populate with component data.
## @param uid_list: The list to populate with component type UIDs.
func _pack_components(e: ECSEntity, dict: Dictionary, uid_list: Array[int]) -> void:
	for c: ECSComponent in e.get_components():
		var c_dict := {}
		var output := Serializer.OutputArchive.new(c_dict)
		c.pack(output)
		dict[c.name()] = c_dict
		
		var uid := _factory.object_to_uid(c)
		var pos = uid_list.find(uid)
		if pos == -1:
			uid_list.append(uid)
			pos = uid_list.size() - 1
		c_dict["_class_index"] = pos

# ==============================================================================
# Private Methods - Unpacking
# ==============================================================================

## Internal: Unpacks all entities from the dictionary.
## @param dict: The dictionary containing entity data.
## @return: True if unpacking succeeded.
func _unpack_entities(dict: Dictionary) -> bool:
	if not dict.has("version") or not _valid_version(dict["version"]):
		return false
	
	var required_keys := ["entities", "uid_list", "last_entity_id"]
	for key: StringName in required_keys:
		if not dict.has(key):
			return false
	
	_w.remove_all_entities()
	
	var uid_list: Array[int] = dict.uid_list
	
	for eid: int in dict.entities:
		var entity_dict: Dictionary = dict.entities[eid]
		var e = _w._create_entity(eid)
	
	for eid: int in dict.entities:
		var entity_dict: Dictionary = dict.entities[eid]
		_unpack_components(_w.get_entity(eid), entity_dict["components"], uid_list)
	
	for eid: int in dict.entities:
		var entity_dict: Dictionary = dict.entities[eid]
		_unpack_archives(_w.get_entity(eid), entity_dict["components"])
	
	_w._entity_id = dict["last_entity_id"]
	
	return true

## Internal: Validates the serialization version.
## @param version: The version string to validate.
## @return: True if version is compatible.
func _valid_version(version: StringName) -> bool:
	return true

## Internal: Unpacks component instances from the dictionary.
## @param e: The entity to add components to.
## @param dict: The dictionary containing component data.
## @param uid_list: The list of component type UIDs.
func _unpack_components(e: ECSEntity, dict: Dictionary, uid_list: Array[int]) -> void:
	for name: StringName in dict:
		var c_dict: Dictionary = dict[name]
		var index: int = c_dict["_class_index"]
		
		if index >= uid_list.size():
			push_error("unpack component fail: class index <%d> is invalid!" % index)
			continue
		
		var uid := uid_list[index]
		var c: ECSComponent = _factory.uid_to_object(uid)
		if c:
			e.add_component(name, c)
		else:
			e.add_component(name)
			push_error("unpack component fail: script <%s> is not exist!" % ResourceUID.id_to_text(uid_list[index]))

## Internal: Unpacks component data archives.
## @param e: The entity whose components to populate.
## @param dict: The dictionary containing component archive data.
func _unpack_archives(e: ECSEntity, dict: Dictionary) -> void:
	for name: StringName in dict:
		var c_dict: Dictionary = dict[name]
		var c: ECSComponent = e.get_component(name)
		var input := Serializer.InputArchive.new(c_dict)
		_load_component_archive(c, input)

## Internal: Loads component data with version migration support.
## @param c: The component to populate.
## @param from: The archive containing serialized data.
func _load_component_archive(c: ECSComponent, from: Serializer.Archive) -> void:
	var ar := Serializer.InOutArchive.new({})
	c.pack(ar)
	var newest_version: int = ar.version
	
	ar.copy_from(from)
	while ar.version < newest_version:
		c.convert(ar)
		ar.version += 1
		
	c.unpack(ar)
