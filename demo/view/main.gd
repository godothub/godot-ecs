extends Node2D

# get global ecs world
var _world := ECSWorld.new("Demo")
	
@onready var _score = $VBoxContainer/Scroe
@onready var _time = $VBoxContainer/Time
@onready var _tips = $VBoxContainer/Tips
	
func _enter_tree() -> void:
	_world.add_system("game_system", preload("../system/game_system.gd").new(self))
	
func _exit_tree() -> void:
	_world.remove_system("game_system")
	
func _ready() -> void:
	_connect_components()
	
	# listen ecs world system viewed signal
	_world.on_system_viewed.connect(_print_system_viewed)
	
	# listen game save/load event
	_world.add_callable("game_saved", _on_game_saved)
	_world.add_callable("game_loaded", _on_game_loaded)
	
	# load game data
	_world.notify("load_game_command")
	
func _process(delta: float) -> void:
	_world.update(delta)
	
func _connect_components() -> void:
	for c: MyComponent in _world.view("my_component"):
		c.on_score_changed.connect(_on_score_changed)
		c.on_seconds_changed.connect(_on_seconds_changed)
	
func _on_game_loaded(e: GameEvent) -> void:
	var successed: bool = e.data.successed
	if not successed:
		_tips.text = "Game data load failed."
		return
	
	# Recovery signal connection
	_connect_components()
	
	_tips.text = "Game data loaded."
	await get_tree().create_timer(1).timeout
	_tips.text = ""
	
func _on_game_saved(e: GameEvent) -> void:
	var successed: bool = e.data.successed
	if not successed:
		_tips.text = "Game data save failed."
		return
		
	_tips.text = "Game data saved."
	await get_tree().create_timer(1).timeout
	_tips.text = ""
	
func _on_score_changed(value: int) -> void:
	_score.text = "Score: %d" % value
	
func _on_seconds_changed(value: float) -> void:
	_time.text = "Seconds: %.2f" % value
	
func _on_load_pressed() -> void:
	# load data
	_world.notify("load_game_command")
	
func _on_save_pressed() -> void:
	# save data
	_world.notify("save_game_command")
	
func _print_system_viewed(system: String, components: Array) -> void:
	if system == "my_system":
		return
	printt("System/Components:", system, components)
	
