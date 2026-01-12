extends RefCounted
class_name ECSScheduler

var _world: ECSWorld
var _threads_size: int
var _system_pool: Dictionary[StringName, ECSParallel]
var _system_graph: Dictionary[StringName, Array]
var _system_conflict: Dictionary[StringName, Dictionary]
var _system_group: Dictionary[StringName, int]

# batch parallel systems
var _batch_systems: Array[Array]

func add_systems(systems: Array) -> ECSScheduler:
	for sys: ECSParallel in systems:
		assert(not sys._list_components().is_empty())
		_system_pool[sys.name()] = sys
	for sys: ECSParallel in systems:
		sys.fetch_before_systems(_set_system_before)
		sys.fetch_after_systems(_set_system_after)
		sys.fetch_conflict(_set_system_conflict)
		sys.fetch_group(_set_system_group)
		sys._set_world(_world)
	return self
	
## Clear the scheduler
func clear() -> void:
	# clear system pool
	_system_pool.clear()
	_batch_systems.clear()
	
	# other
	_system_graph.clear()
	_system_conflict.clear()
	_system_group.clear()
	
func build() -> ECSScheduler:
	assert(not _system_pool.is_empty())
	_batch_systems.clear()
	if _system_pool.size() == 1:
		_batch_systems.append(_system_pool.values())
	else:
		_build_batch_systems()
	return self
	
func run(_delta: float = 0.0) -> void:
	_run_systems(_delta)
	_flush_commands()
	
func _insert_graph_node(key: StringName, value: StringName) -> void:
	assert(_system_pool.has(value), "Scheduler must have system key [%s]!" % value)
	if not _system_graph.has(key):
		_system_graph[key] = []
	var list := _system_graph[key]
	if value in list:
		return
	list.append(value)
	
func _set_system_before(name: StringName, before_systems: Array) -> void:
	for key: StringName in before_systems:
		_insert_graph_node(name, key)
	
func _set_system_after(name: StringName, after_systems: Array) -> void:
	for key: StringName in after_systems:
		_insert_graph_node(key, name)
	
func _set_system_conflict(name: StringName, table: Dictionary) -> void:
	_system_conflict[name] = table
	
func _set_system_group(name: StringName, group: int) -> void:
	_system_group[name] = group
	
func _init(world: ECSWorld) -> void:
	_world = world
	
func _run_systems(delta: float) -> void:
	for systems: Array in _batch_systems:
		var task_id := WorkerThreadPool.add_group_task(func(index: int):
			systems[index].thread_function(delta),
			systems.size())
		WorkerThreadPool.wait_for_group_task_completion(task_id)
	
func _flush_commands() -> void:
	for systems: Array in _batch_systems:
		for sys: ECSParallel in systems:
			sys.flush_commands()
	
func _build_batch_systems() -> void:
	DependencyBuilder.new()\
		.with_dag(_system_graph)\
		.with_conflict(_system_conflict)\
		.with_group(_system_group)\
		.build(func(batch_system_keys: Array):
		_batch_systems.append(batch_system_keys.map(func(key: StringName):
			return _system_pool[key]
		))
	)
	
# ==============================================================================
# private
class DependencyBuilder extends RefCounted:
	var _graph: Dictionary[StringName, Array] = {}
	var _conflict: Dictionary[StringName, Dictionary] = {}
	var _group: Dictionary[StringName, int] = {}
	
	# set dependency graph
	func with_dag(graph: Dictionary[StringName, Array]) -> DependencyBuilder:
		_graph.merge(graph, true)
		return self
		
	# set read write conflict
	func with_conflict(conf: Dictionary[StringName, Dictionary]) -> DependencyBuilder:
		_conflict.merge(conf, true)
		return self
		
	# set system group
	func with_group(group: Dictionary[StringName, int]) -> DependencyBuilder:
		_group.merge(group, true)
		return self
		
	# catch every batch system names
	func build(catch := Callable()) -> void:
		# 1. 整理所有系统 Key (以 Group 字典为准，因为所有系统都会注册 Group)
		var all_systems: Array = _group.keys()
		var in_degree: Dictionary = {}
		
		# 初始化入度
		for key: StringName in all_systems:
			in_degree[key] = 0
			
		# 2. 计算入度 (In-Degree)
		# 遍历邻接表 _graph: Key -> [Children]
		for u: StringName in _graph:
			for v: StringName in _graph[u]:
				# 确保 v 存在于系统中，防止无效引用
				if in_degree.has(v):
					in_degree[v] += 1
					
		# 3. 初始化 Ready Queue (入度为 0 的节点)
		var ready_queue: Array[StringName] = []
		for key: StringName in all_systems:
			if in_degree[key] == 0:
				ready_queue.append(key)
				
		# 按照 Group ID 排序 Ready Queue，作为一种简单的启发式优化
		# Group 小的系统倾向于排在前面处理，虽然不强制，但有助于逻辑分层
		_sort_by_group(ready_queue)
		
		var result_batches: Array[Array] = []
		var processed_count: int = 0
		var total_count: int = all_systems.size()
		
		# 4. 分批循环 (Batching Loop)
		while processed_count < total_count:
			if ready_queue.is_empty():
				push_error("[ECS] Scheduler Cycle Detected! Dependency graph has a loop.")
				break
				
			var current_batch: Array[StringName] = []
			
			# 当前 Batch 占用的资源锁
			# key: ComponentName, value: true (used)
			var batch_reads: Dictionary = {} 
			var batch_writes: Dictionary = {}
			
			var next_loop_deferred: Array[StringName] = [] # 因冲突本轮没跑的
			var unlocked_nodes: Array[StringName] = []     # 本轮跑完解锁的
			
			# 贪婪匹配：尝试把 ready_queue 里的系统塞入 current_batch
			for sys_name: StringName in ready_queue:
				if _is_conflict(sys_name, batch_reads, batch_writes):
					# 冲突：留到下一轮
					next_loop_deferred.append(sys_name)
				else:
					# 兼容：加入当前 Batch
					current_batch.append(sys_name)
					_mark_access(sys_name, batch_reads, batch_writes)
			
			if current_batch.is_empty():
				push_error("[ECS] Scheduler Deadlock! Logic error or unsolvable resource conflict.")
				break
				
			# 记录结果
			result_batches.append(current_batch)
			processed_count += current_batch.size()
			
			# 5. 解锁后继节点 (Topological Advance)
			# 只有在 current_batch 里真正执行了的节点，才能解锁它们的后继
			for executed_sys: StringName in current_batch:
				if _graph.has(executed_sys):
					for neighbor: StringName in _graph[executed_sys]:
						if in_degree.has(neighbor):
							in_degree[neighbor] -= 1
							if in_degree[neighbor] == 0:
								unlocked_nodes.append(neighbor)
			
			# 6. 准备下一轮的队列
			# 下一轮候选 = (本轮冲突的) + (本轮解锁的)
			# 再次排序优化执行顺序
			_sort_by_group(unlocked_nodes) 
			ready_queue = next_loop_deferred + unlocked_nodes
			
		# 返回结果：Array[Array[StringName]]
		for batch_keys: Array in result_batches:
			catch.call(batch_keys)

	# --- Helpers ---
	
	# 检查系统是否与当前 Batch 冲突
	func _is_conflict(sys_name: StringName, batch_reads: Dictionary, batch_writes: Dictionary) -> bool:
		var sys_access: Dictionary = _conflict.get(sys_name, {})
		for comp: StringName in sys_access:
			var access_type: int = sys_access[comp]
			
			# 规则 1: 如果当前 Batch 已经有人在该组件上写数据 -> 绝对冲突 (无论我是读还是写)
			if batch_writes.has(comp):
				return true
				
			# 规则 2: 如果我想写数据 -> 检查当前 Batch 是否有人在读 (写读冲突) 或 写 (写写冲突已由规则1覆盖)
			if access_type == ECSParallel.READ_WRITE:
				if batch_reads.has(comp):
					return true
					
		return false
		
	# 标记资源占用
	func _mark_access(sys_name: StringName, batch_reads: Dictionary, batch_writes: Dictionary) -> void:
		var sys_access: Dictionary = _conflict.get(sys_name, {})
		for comp: StringName in sys_access:
			var access_type: int = sys_access[comp]
			if access_type == ECSParallel.READ_ONLY:
				batch_reads[comp] = true
			else:
				batch_writes[comp] = true
				
	# 简单的排序辅助，让 Group ID 小的排前面
	func _sort_by_group(arr: Array[StringName]) -> void:
		arr.sort_custom(func(a, b):
			return _group.get(a, 0) < _group.get(b, 0)
		)
	
