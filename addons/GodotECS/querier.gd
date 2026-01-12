extends RefCounted

const Querier = preload("querier.gd")

# ==============================================================================
# public
func with(names: Array) -> Querier:
	_with_names = names
	return self
	
func without(names: Array) -> Querier:
	_without_names = names
	return self
	
func any_of(names: Array) -> Querier:
	_any_names = names
	return self
	
func filter(predicate: Callable) -> Querier:
	_custom_filter = predicate
	return self
	
func exec() -> Array:
	# -----------------------------------------------------------
	# 情况 1: 存在 'with' 锚点 (AND 逻辑为主)
	# 这是最高效的路径，利用 QueryCache
	# -----------------------------------------------------------
	if not _with_names.is_empty():
		return _world.multi_view(_with_names).filter(_internal_filter)
	
	# -----------------------------------------------------------
	# 情况 2: 没有 'with'，但有 'any_of' (OR 逻辑为主)
	# 我们需要手动收集所有涉及组件的实体，并去重
	# -----------------------------------------------------------
	if not _any_names.is_empty():
		return _exec_union_query()
		
	# -----------------------------------------------------------
	# 情况 3: 既没 with 也没 any_of
	# -----------------------------------------------------------
	# 通常返回空，或者抛出警告，除非你想返回世界上的所有实体
	return []
	
# ==============================================================================
# private
var _world: ECSWorld
var _with_names: Array[StringName] = []
var _without_names: Array[StringName] = []
var _any_names: Array[StringName] = []
var _custom_filter: Callable
	
func _init(w: ECSWorld) -> void:
	_world = w
	
func _internal_filter(view_data: Dictionary) -> bool:
	var entity_id: int = view_data["entity"].id()
	
	# 1. Check Without (必须不包含)
	if not _without_names.is_empty():
		for name in _without_names:
			if _world.has_component(entity_id, name):
				return false # 包含了一项"排除"的组件，这就不是我们要的
	
	# 2. Check AnyOf (必须包含任意一个)
	if not _any_names.is_empty():
		var has_any := false
		for name in _any_names:
			if _world.has_component(entity_id, name):
				has_any = true
				break
		if not has_any:
			return false # 一个备选组件都没找到
			
	# 3. Check Custom Filter (用户自定义逻辑)
	if _custom_filter.is_valid():
		return _custom_filter.call(view_data)
		
	return true
	
func _exec_union_query() -> Array:
	var result_map: Dictionary = {} # 使用字典 key 来去重: { entity_id: view_data }
	
	# 1. 遍历 any_of 中的每一个组件类型
	for name in _any_names:
		# 利用 World 的底层接口直接获取该组件的所有实体
		# 注意：这里访问了 World 的私有变量 _get_type_list，
		# 建议在 World 中公开一个方法 get_entities_with_component(name)
		var type_list: Dictionary = _world._get_type_list(name)
		
		for entity_id in type_list:
			# 如果该实体已经被加入结果集，跳过（去重）
			if result_map.has(entity_id):
				continue
				
			# 2. 检查 without (排除逻辑)
			if not _check_without(entity_id):
				continue
				
			# 3. 构造返回数据
			var e = _world.get_entity(entity_id)
			var data = { "entity": e }
			
			# 填充存在的组件数据
			# 注意：因为是 AnyOf，实体可能只有部分组件，其他的为 null
			for key in _any_names:
				data[key] = _world.get_component(entity_id, key)
				
			# 4. 执行自定义 Filter
			if _custom_filter.is_valid():
				if not _custom_filter.call(data):
					continue
					
			result_map[entity_id] = data
			
	return result_map.values()
	
func _check_without(entity_id: int) -> bool:
	if _without_names.is_empty():
		return true
	for name in _without_names:
		if _world.has_component(entity_id, name):
			return false
	return true
	
