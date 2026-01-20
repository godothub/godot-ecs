# Godot ECS Framework 🚀![](images/ecs.png)

[English](./README.md)

[中文文档](./docs/zh_CN/1.入门与基础.md)

一个专为 Godot 4 设计的、轻量级但功能强大的 **Entity Component System (ECS)** 框架。

本框架采用纯 GDScript 编写，旨在解决 Godot 项目中随着逻辑复杂度增加带来的耦合问题。它提供了从“类 Godot 风格”的简单系统到“全自动调度”的高性能并行系统的平滑过渡路径。

## ✨ 核心特性

* **纯 GDScript 实现**：无需编译 GDExtension，即插即用，轻松调试。
* **双模式设计**：
  * **Direct Mode (`ECSSystem`)**：单线程、有状态，适合 UI 和游戏流程控制，符合 Godot 使用直觉。
  * **Scheduled Mode (`ECSParallel`)**：多线程、自动依赖分析，适合高性能计算和大规模实体模拟。
* **高性能调度器**：内置基于拓扑排序的依赖图 (DAG)，自动处理系统执行顺序和资源读写冲突。
* **自动多线程**：利用 Godot 4 的 `WorkerThreadPool` 自动分发任务。
* **强大的查询系统**：支持 `With/Without/AnyOf` 复杂查询，且拥有 O(1) 的缓存查询性能 (`QueryCache`)。
* **完整的生态系统**：内置**序列化/存档系统** (支持版本迁移) 和 **事件系统**。

## 📦 安装

1. 下载本仓库。
2. 将 `GodotECS` 和 `GodotUtils` 文件夹复制到你的 Godot 项目的 `res://` 根目录下。
3. 完成！无需配置插件，直接在代码中引用。

## ⚡ 快速开始

### 1. 初始化世界

在你的主场景脚本中：

```gdscript
extends Node

var _world: ECSWorld
var _runner: ECSRunner

func _ready() -> void:
    # 创建世界
    _world = ECSWorld.new("MyGameWorld")
    
    # 创建执行器用于管理单线程系统（推荐方式）
    _runner = _world.create_runner("GameLogic")
    
    # 向执行器添加系统
    _runner.add_system("MoveSystem", SysMovement.new())

    # 创建一个实体
    var entity = _world.create_entity()
    entity.add_component("Position", CompPos.new(0, 0))
    entity.add_component("Velocity", CompVel.new(10, 0))

# 旧方式（已弃用，仅供参考）：
# _world.add_system("MoveSystem", SysMovement.new())
# _world.update(delta)

func _process(delta: float) -> void:
    # 驱动执行器更新（推荐方式）
    _runner.run(delta)

func _exit_tree() -> void:
    _world.clear()
```

### 2. 定义组件

组件只是数据的容器。

```gdscript
class CompPos extends ECSComponent:
    var x: float = 0
    var y: float = 0
    func _init(px=0, py=0): x=px; y=py

class CompVel extends ECSDataComponent:
    # ECSDataComponent 自带一个 data 属性
    pass 
```

### 3. 使用 ECSRunner（推荐）

**ECSRunner** 是管理单线程系统的推荐方式。它提供系统分组、更好的组织结构，以及与 ECSScheduler 一致的 API 风格。

> **注意**: 直接使用 `world.add_system()` 和 `world.update()` 的方法已被标记为**弃用**，但仍支持向后兼容。

```gdscript
extends Node

var _world: ECSWorld
var _runner: ECSRunner

func _ready() -> void:
    # 创建世界
    _world = ECSWorld.new("MyGameWorld")
    
    # 创建命名执行器用于管理单线程系统
    _runner = _world.create_runner("GameLogic")
    
    # 向执行器添加系统（支持链式调用）
    _runner.add_system("MoveSystem", SysMovement.new())
           .add_system("RenderSystem", SysRender.new())
    
    # 创建一个实体
    var entity = _world.create_entity()
    entity.add_component("Position", CompPos.new(0, 0))
    entity.add_component("Velocity", CompVel.new(10, 0))

func _process(delta: float) -> void:
    # 驱动执行器更新（替代 world.update()）
    _runner.run(delta)

func _exit_tree() -> void:
    # 清理资源
    _world.clear()
```

**ECSRunner 的优势：**
- ✅ 清晰的系统分组和组织结构
- ✅ 可创建多个执行器管理不同类别的系统
- ✅ 与 ECSScheduler 保持一致的 API 风格
- ✅ 更好的可扩展性和可维护性
- ✅ 单个系统更新控制

### 4. 定义系统

#### 方式 A: 直接模式 (简单直观)

适合处理逻辑、输入、UI。

```gdscript
class SysMovement extends ECSSystem:
    func _on_update(delta: float) -> void:
        # 获取所有拥有 Position 和 Velocity 的实体
        var list = world().multi_view(["Position", "Velocity"])

        for item in list:
            var pos = item["Position"]
            var vel = item["Velocity"]
            pos.x += vel.data * delta
```

#### 方式 B: 调度模式 (高性能)

适合物理模拟、AI 集群。支持依赖排序和自动并行。

```gdscript
class SysPhysics extends ECSParallel:
    func _init(): super._init("Physics")

    # 1. 声明读写权限，供调度器分析
    func _list_components() -> Dictionary:
        return {
            "Position": ECSParallel.READ_WRITE,
            "Velocity": ECSParallel.READ_ONLY
        }

    # 2. 开启多线程并行处理
    func _parallel() -> bool: return true

    # 3. 业务逻辑 (传入线程安全的 CommandBuffer)
    func _view_components(view: Dictionary, cmds: ECSParallel.Commands) -> void:
        view["Position"].x += view["Velocity"].data * delta
```

## 🏗️ 架构概览

### Direct Mode vs Scheduled Mode

| 特性       | ECSSystem (Direct) | ECSParallel (Scheduled)     |
|:-------- |:------------------ |:--------------------------- |
| **主要用途** | 游戏逻辑, UI, 输入, 流程控制 | 物理, AI, 大规模数据运算             |
| **线程模型** | 单线程 (主线程)          | **多线程 (WorkerThreadPool)**  |
| **状态管理** | 允许持有状态 (Stateful)  | 无状态 (Stateless), 纯逻辑        |
| **执行顺序** | 手动添加顺序             | **自动依赖排序 (.after/.before)** |
| **数据修改** | 直接调用 API           | **使用 CommandBuffer 延迟修改**   |

### 目录结构

* `GodotECS/`: 核心框架代码 (World, Entity, System, Scheduler).
* `GodotUtils/`: 工具库 (EventCenter, Serialization, Factory).

## 💾 序列化支持

框架内置了强大的存档支持，甚至支持数据结构升级：

```gdscript
# 保存
var packer = ECSWorldPacker.new(_world).with_factory(factory)
var data = packer.pack() # 得到可序列化的 DataPack

# 加载
packer.unpack(data) # 自动恢复世界状态
```

## 🤝 贡献

欢迎提交 Issue 和 PR！
如果你发现了 Bug 或有性能优化的建议，请务必告诉我们。

## 📄 许可证

本项目采用 [MIT License](LICENSE).
