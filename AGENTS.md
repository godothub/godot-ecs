# Agent Guidelines for Godot Light ECS

This document provides guidelines for AI agents working on this Godot ECS framework.

## Build, Test & Run

### Running the Project
- **Editor**: Open the project in Godot 4.5+ via `godot_mcp_launch_editor` or the Godot editor directly
- **Headless Testing**: Run `godot_mcp_run_project` with specific scene paths

### Running Tests
Tests are located in `addons/GodotECS/`:
- **Full Test Suite**: `ECSTestSuite.new().run()` - Tests CRUD, queries, events, commands, scheduler, serialization
- **Scheduler Stress Test**: `ECSSchedulerStressTest.new().run()` - Tests dependency analysis, conflict resolution, cyclic detection

To run a single test:
```gdscript
var suite = ECSTestSuite.new()
suite._run_test("Test Name", suite._test_entity_component_crud)
suite.run()
```

Or call specific test methods directly:
```gdscript
var suite = ECSTestSuite.new()
suite._setup()
suite._test_entity_component_crud()
suite._teardown()
```

### Export
- Export presets are in `export_presets.cfg`
- Run Godot export via editor or CLI: `godot --export-release "Windows"`

## Code Style Guidelines

### File Organization
- One class per file (except inner test classes)
- Filename must match class name: `class_name ECSWorld` → `world.gd`
- Core framework in `addons/GodotECS/`
- Utilities in `addons/GodotUtils/`

### Class Declaration
```gdscript
extends RefCounted  # or Node, Serializer, etc.
class_name ECSWorld  # Required for all public classes
```

### Naming Conventions
- **Classes**: PascalCase (`ECSWorld`, `CompHealth`, `SysMovement`)
- **Methods/Variables**: snake_case (`entity_id`, `debug_print`, `multi_view`)
- **Private Members**: Leading underscore (`_name`, `_entity_pool`, `_on_update`)
- **Constants**: SCREAMING_SNAKE_CASE (`VERSION`, `READ_ONLY`, `READ_WRITE`)
- **Component Names**: StringName identifiers (`"Health"`, `"Position"`, `"Velocity"`)

### Type Hints (Required)
Always use explicit return types and parameter types:
```gdscript
func name() -> StringName:
    return _name

func add_component(entity_id: int, name: StringName, component: ECSComponent) -> bool:
```

### String Types
- Use `StringName` for keys, identifiers, and component names
- Use `String` for general text and formatting
```gdscript
var _name: StringName
var message: String = "entity created"
```

### Comments
- Use `##` for doc comments above functions/classes
- Use `#` for inline explanations
- Avoid redundant comments; code should be self-documenting

### Error Handling
- Use `assert()` for precondition validation and invariants
- Return `bool` to indicate success/failure
- Use `null` return for optional values
- Never silently ignore errors; log with `print_rich()` or `print()`

### Signal Patterns
- Define signals with typed parameters: `signal on_update(delta: float)`
- Connect/disconnect explicitly in lifecycle methods
- Use `weakref()` to avoid circular references with `WeakRef`

### Component Design
- Data components extend `ECSDataComponent` (has `.data` property)
- Complex components extend `ECSComponent`
- Override `_on_pack(ar: Archive)` and `_on_unpack(ar: Archive)` for serialization
- Never store `World` or `Entity` references directly; use `WeakRef`

### System Design
- **Direct Mode**: Extend `ECSSystem` for single-threaded, stateful systems
- **Parallel Mode**: Extend `ECSParallel` for multi-threaded, stateless systems
- Override `_list_components() -> Dictionary` to declare read/write access
- Use `_parallel() -> bool` to enable WorkerThreadPool execution
- Use `before()`/`after()` for explicit dependency declarations

### Query Patterns
```gdscript
# Single component view
var healths = world.view("Health")

# Multi-component AND query (cached)
var results = world.multi_view(["Position", "Velocity"])

# Complex queries with Querier
var query = world.query().with(["Health"]).without(["Mana"]).exec()
```

### Testing Patterns
- Use `ECSTestSuite` as base for test classes
- Helper method `_assert(condition: bool, msg: String)`
- Use `print_rich()` for colored test output: `[color=red][FAIL][/color]`
- Mock inner classes defined within test methods
- Always call `_setup()` before and `_teardown()` after tests

### Godot-Specific Patterns
- Use `Node` for systems that need child management (RPC support)
- Use `RefCounted` for pure data/logic classes
- Use `Callable` for callbacks and deferred execution
- Use `WorkerThreadPool` for parallel task distribution
- Use `Time.get_ticks_usec()` for microsecond timing

### Imports and Preloading
```gdscript
const Querier = preload("querier.gd")
const QueryCache = preload("query_cache.gd")
```

### Code Organization
- Group related functionality with `# ==============================================================================` separators
- Mark sections: `public`, `private`, `override`, `Test Cases`
- Keep `_init()` simple; defer complex setup
- Use `queue_free()` in `on_exit()` for Node-based systems

## Project Structure
```
addons/
  GodotECS/          # Core framework
    Component/       # Base component classes
    system.gd        # ECSSystem base
    parallel_system.gd  # ECSParallel base
    world.gd         # ECSWorld entry point
    entity.gd        # ECSEntity wrapper
    querier.gd       # Query builder
    scheduler.gd     # DAG-based scheduler
    test_suite.gd    # Full test suite
    test_scheduler.gd # Scheduler stress tests
  GodotUtils/        # Utilities
    event.gd         # GameEvent
    event_center.gd  # Event system
    packer.gd        # Serialization
demo/                # Examples
  sync/              # Direct mode examples
  async/             # Parallel mode examples
```

## Key Design Principles
1. **Zero GDExtension**: Pure GDScript for easy debugging
2. **Dual Mode**: Direct (main thread) vs Parallel (worker threads)
3. **DAG Scheduling**: Automatic dependency resolution
4. **O(1) Queries**: Cached query results via `QueryCache`
5. **Stateless Parallel**: Parallel systems must be pure functions
6. **Weak References**: Prevent memory leaks in component/entity
