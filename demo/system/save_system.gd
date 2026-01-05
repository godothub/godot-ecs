extends ECSSystem

# override
func _on_enter(w: ECSWorld) -> void:
	w.add_callable("load_game_command", _on_load_game)
	w.add_callable("save_game_command", _on_save_game)
	
# override
func _on_exit(w: ECSWorld) -> void:
	w.remove_callable("load_game_command", _on_load_game)
	w.remove_callable("save_game_command", _on_save_game)
	
func _on_load_game(_e: GameEvent) -> void:
	# load file
	var stream := ByteStream.open("user://game.save")
	if stream == null:
		return
	
	# restore the world
	var packer := ECSWorldPacker.new(world())
	var data = stream.decode_var()
	var pack := DataPack.new(data if data else {})
	var successed := packer.unpack(pack)
	
	# notify game data
	world().notify("game_loaded", {
		"successed": successed,
	})

# override
func _on_save_game(_e: GameEvent) -> void:
	# pack the world
	var packer := ECSWorldPacker.new(world())
	var pack := packer.pack()
	
	# save to file
	var bytes := ByteStream.new()
	bytes.encode_var(pack.data())
	var successed := bytes.write("user://game.save")
	
	# notify game data
	world().notify("game_saved", {
		"successed": successed,
	})
	
