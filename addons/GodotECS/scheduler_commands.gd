extends RefCounted

const Commands = preload("scheduler_commands.gd")

# ==============================================================================
# Constants (OpCodes)
# ==============================================================================
enum {
	OP_SPAWN = 0,       # [OP_SPAWN] -> Creates new entity, sets 'current_entity'
	OP_DESTROY,         # [OP_DESTROY, entity_id]
	OP_ADD_COMP,        # [OP_ADD_COMP, entity_id, name, component]
	OP_ADD_TO_NEW,      # [OP_ADD_TO_NEW, name, component] -> Adds to 'current_entity'
	OP_RM_COMP,         # [OP_RM_COMP, entity_id, name]
	OP_RM_ALL,          # [OP_RM_ALL, entity_id]
	OP_DEFER,           # [OP_DEFER, callable] -> New OpCode
}

# ==============================================================================
# Data Storage (Optimized for GC)
# ==============================================================================
# Flat array: [OP_CODE, param1, param2, OP_CODE, ...]
var _stream: Array = []

# Event buffer: { "event_name": [param1, param2, ...] }
var _event_buffer: Dictionary = {}

# ==============================================================================
# Public API (Fluent Interface)
# ==============================================================================

## 延迟执行一个自定义操作 (线程安全)
## 该操作会被记录，并在 flush 阶段(通常是主线程)执行
## 用法: commands.defer(func(): print("Safe on main thread"))
func defer(operation: Callable) -> void:
	_stream.append(OP_DEFER)
	_stream.append(operation)

## 获取针对特定实体的命令操作接口
## 用法: commands.entity(id).add_component(...).destroy()
func entity(id: int) -> EntityCommands:
	return EntityCommands.new(self, id)

## 生成一个新实体，并返回操作接口
## 用法: commands.spawn().add(...).add(...)
func spawn() -> Spawner:
	_stream.append(OP_SPAWN)
	return Spawner.new(self)

## 发送通知 (会被合并优化)
## 用法: commands.notify("level_up", 5)
func notify(event_name: StringName, value: Variant = null) -> void:
	if not _event_buffer.has(event_name):
		_event_buffer[event_name] = []
	_event_buffer[event_name].append(value)

## 发送 GameEvent 对象 (兼容旧接口)
func send(event: GameEvent) -> void:
	# 这种一般比较少合并，直接复用 notify 的通道或者单独处理
	# 这里为了统一，我们将其拆解为 notify
	notify(event.name, event.data)

# ==============================================================================
# Framework Interface
# ==============================================================================

## 合并另一个命令缓冲 (用于多线程汇合)
func merge(other: Commands) -> void:
	_stream.append_array(other._stream)
	
	# Merge events
	for name: StringName in other._event_buffer:
		if not _event_buffer.has(name):
			_event_buffer[name] = []
		_event_buffer[name].append_array(other._event_buffer[name])

## 执行所有缓冲命令
func flush(world: ECSWorld) -> void:
	# 1. Flush Commands
	_flush_stream(world)
	_stream.clear()
	
	# 2. Flush Events (Optimized)
	_flush_events(world)
	_event_buffer.clear()

func clear() -> void:
	_stream.clear()
	_event_buffer.clear()

func is_empty() -> bool:
	return _stream.is_empty() and _event_buffer.is_empty()

# ==============================================================================
# Internal Logic
# ==============================================================================

func _flush_stream(world: ECSWorld) -> void:
	var idx: int = 0
	var limit: int = _stream.size()
	var last_spawned_id: int = 0 # Track for OP_ADD_TO_NEW
	
	while idx < limit:
		var op: int = _stream[idx]
		idx += 1
		
		match op:
			OP_SPAWN:
				var e := world.create_entity()
				last_spawned_id = e.id()
				
			OP_ADD_TO_NEW:
				var key = _stream[idx]
				var comp: ECSComponent = _stream[idx+1]
				idx += 2
				
				var name: StringName
				if key == null:
					name = world.resolve_name(comp)
				elif key is StringName:
					name = key
				else:
					name = world.resolve_name(key)
				
				if last_spawned_id != 0 and not name.is_empty():
					world.add_component(last_spawned_id, name, comp)
				elif last_spawned_id == 0:
					push_error("[ECS] OP_ADD_TO_NEW called without preceding OP_SPAWN")
					
			OP_DESTROY:
				var eid: int = _stream[idx]
				idx += 1
				world.remove_entity(eid)
				
			OP_ADD_COMP:
				var eid: int = _stream[idx]
				var key = _stream[idx+1]
				var comp: ECSComponent = _stream[idx+2]
				idx += 3
				
				var name: StringName
				if key == null:
					name = world.resolve_name(comp)
				elif key is StringName:
					name = key
				else:
					name = world.resolve_name(key)
				
				if not name.is_empty():
					world.add_component(eid, name, comp)
				
			OP_RM_COMP:
				var eid: int = _stream[idx]
				var name: StringName = _stream[idx+1]
				idx += 2
				world.remove_component(eid, name)
				
			OP_RM_ALL:
				var eid: int = _stream[idx]
				idx += 1
				world.remove_all_components(eid)
				
			OP_DEFER:
				var operation: Callable = _stream[idx]
				idx += 1
				if operation.is_valid():
					operation.call()
				else:
					push_error("[ECS] Deferred callable is invalid during flush.")

func _flush_events(world: ECSWorld) -> void:
	# 优化：每个事件名只查找一次 Listener
	var event_pool = world._event_pool # Access internal GameEventCenter
	
	for name: StringName in _event_buffer:
		var params: Array = _event_buffer[name]
		if params.is_empty(): continue
		
		# 仅查找一次
		var listener = event_pool._get_event_listener(name)
		
		# 批量分发
		# 注意：这里我们构建临时的 GameEvent 对象
		# 如果非常追求极致 GC，GameEvent 对象池也可以考虑，
		# 但考虑到 notify 通常频率远低于组件操作，这里可以直接 new
		for val in params:
			var e := GameEvent.new(name, val)
			e._event_center = weakref(event_pool)
			listener.receive(e)

# ==============================================================================
# Helper Proxies (For Fluent Syntax)
# ==============================================================================

## 针对现有实体的操作代理
class EntityCommands extends RefCounted:
	var _cmd: Commands
	var _id: int
	
	func _init(cmd: Commands, id: int) -> void:
		_cmd = cmd
		_id = id
	
	func add_component(p1: Variant, p2: ECSComponent = null) -> EntityCommands:
		var name_var: Variant = p1
		var comp: ECSComponent = p2
		
		if p1 is ECSComponent:
			comp = p1
			name_var = null
		elif p2 == null:
			comp = ECSComponent.new()
			
		_cmd._stream.append(Commands.OP_ADD_COMP)
		_cmd._stream.append(_id)
		_cmd._stream.append(name_var)
		_cmd._stream.append(comp)
		return self
		
	func remove_component(name: StringName) -> EntityCommands:
		_cmd._stream.append(Commands.OP_RM_COMP)
		_cmd._stream.append(_id)
		_cmd._stream.append(name)
		return self
		
	func remove_all_components() -> EntityCommands:
		_cmd._stream.append(Commands.OP_RM_ALL)
		_cmd._stream.append(_id)
		return self
		
	func destroy() -> void:
		_cmd._stream.append(Commands.OP_DESTROY)
		_cmd._stream.append(_id)

## 针对新实体的操作代理
class Spawner extends RefCounted:
	var _cmd: Commands
	
	func _init(cmd: Commands) -> void:
		_cmd = cmd
	
	func add_component(p1: Variant, p2: ECSComponent = null) -> Spawner:
		var name_var: Variant = p1
		var comp: ECSComponent = p2
		
		if p1 is ECSComponent:
			comp = p1
			name_var = null
		elif p2 == null:
			comp = ECSComponent.new()
			
		_cmd._stream.append(Commands.OP_ADD_TO_NEW)
		_cmd._stream.append(name_var)
		_cmd._stream.append(comp)
		return self

