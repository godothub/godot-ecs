extends RefCounted

# 缓存的结果数组: Array[Dictionary]
var results: Array = []

# 缓存特定组件组合的查询结果
var _signature: Array[StringName] # 排序后的组件名列表
var _entity_indices: Dictionary = {} # EntityID -> index in results (用于快速查找移除)
var _world: ECSWorld

func _init(w: ECSWorld, sig: Array):
	_world = w
	_signature.append_array(sig)
	_rebuild_all() # 初始化时构建一次

# 全量构建 (仅初始化使用)
func _rebuild_all() -> void:
	results.clear()
	_entity_indices.clear()
	# 找到数量最少的组件作为主遍历对象，优化性能
	var min_count = 2147483647
	var best_comp = _signature[0]
	for name in _signature:
		var count = _world._get_type_list(name).size()
		if count < min_count:
			min_count = count
			best_comp = name
	
	# 遍历该组件的所有实体
	var type_list = _world._get_type_list(best_comp)
	for entity_id in type_list:
		if _match(entity_id):
			_add(entity_id)

# 检查实体是否满足当前 Query
func _match(entity_id: int) -> bool:
	for name in _signature:
		if not _world.has_component(entity_id, name):
			return false
	return true

# 添加实体到缓存
func _add(entity_id: int) -> void:
	if _entity_indices.has(entity_id): return # 已经在缓存里了
	
	var entity = _world.get_entity(entity_id)
	var view_data = { "entity": entity }
	for name in _signature:
		view_data[name] = _world.get_component(entity_id, name)
	
	results.append(view_data)
	_entity_indices[entity_id] = results.size() - 1

# 从缓存移除实体 (Swap-back-and-pop O(1) 删除)
func _remove(entity_id: int) -> void:
	if not _entity_indices.has(entity_id): return
	
	var idx = _entity_indices[entity_id]
	var last_idx = results.size() - 1
	var last_item = results[last_idx]
	var last_entity_id = last_item["entity"].id()
	
	# 如果不是最后一个，将最后一个移到当前删除的位置
	if idx != last_idx:
		results[idx] = last_item
		_entity_indices[last_entity_id] = idx
	
	results.pop_back()
	_entity_indices.erase(entity_id)

# 当组件发生变化时调用
func on_component_changed(entity_id: int, component_name: StringName, is_added: bool) -> void:
	# 如果变化的组件不在我的关注列表里，直接忽略
	if not component_name in _signature:
		return
		
	var in_cache = _entity_indices.has(entity_id)
	
	if is_added:
		# 新增组件：如果你不在缓存里，且现在满足条件了 -> 添加
		if not in_cache and _match(entity_id):
			_add(entity_id)
	else:
		# 移除组件：如果你在缓存里，且移除的是我关注的组件 -> 移除
		# (因为移除任何一个关注的组件，就不再满足 match 了)
		if in_cache:
			_remove(entity_id)
