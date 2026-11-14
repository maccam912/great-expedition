extends SceneTree
## Renders the menu and each zone to build/shot_*.png for visual checks.
## Run windowed (not --headless): python3 tools/godot.py --script res://tests/render_game.gd -- --quiet

func _initialize() -> void:
	call_deferred("_run")

func _shot(name: String) -> void:
	for frame in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/shot_%s.png" % name)

func _run() -> void:
	var scene := load("res://game/main.tscn") as PackedScene
	root.add_child(scene.instantiate())
	var session := root.get_node("Session")
	await _shot("menu")
	session.roster = [1, 2, 3]
	session.start_game(7)
	var sim: ExpeditionSim = session.sim
	await _shot("camp")
	var names := ["camp", "clearing", "river", "bog", "ridge", "cave", "thicket", "landmark"]
	for zone: Dictionary in sim.terrain.zones:
		if zone.kind <= Defs.Z_CLEARING:
			continue
		var spot := sim.terrain.entrance(zone, 10 * Defs.TILE) + Vector2(5 * Defs.TILE, 0)
		if zone.kind == Defs.Z_THICKET:
			spot = sim.terrain.grumble_home + Vector2(-110, 0)
		if zone.kind == Defs.Z_LANDMARK:
			spot = sim.terrain.goal + Vector2(-60, 30)
		if zone.kind == Defs.Z_CAVE:
			for x in range(zone.x0 + 6, zone.x1):
				if sim.terrain.tile(x, 8) == Defs.CAVE:
					spot = sim.terrain.center(x, 8)
					break
			sim.players[1].items[0] = Defs.LANTERN
		for id in [1, 2, 3]:
			sim.players[id].pos = spot + Vector2(0, (id - 1) * 34)
			sim.players[id].st = Defs.WALK
		if zone.kind == Defs.Z_LANDMARK:
			sim.players[2].pos = sim.terrain.goal + Vector2(70, 20)
			sim.players[3].pos = sim.terrain.goal + Vector2(0, 80)
		await _shot(names[zone.kind])
	# Action shot: a raft mid-river, a swimmer on a rope, a snack thief.
	session.start_game(7)
	sim = session.sim
	for zone: Dictionary in sim.terrain.zones:
		if zone.kind == Defs.Z_RIVER:
			var bank := sim.terrain.washup(zone) + Vector2(0, -16 * Defs.TILE)
			for x in range(zone.x0, zone.x1):
				if sim.terrain.tile(x, 18) == Defs.WATER:
					bank = sim.terrain.center(x - 1, 18)
					break
			sim.players[1].pos = bank
			sim.players[1].items[0] = Defs.RAFT
			sim.players[1].face = Vector2.RIGHT
			sim.act(1, "use")
			sim.set_axis(1, Vector2(1, -0.9))
			sim.players[3].pos = bank + Vector2(0, 150)
			sim.players[3].items[0] = Defs.ROPE
			sim.players[3].face = Vector2.RIGHT
			sim.players[2].pos = bank + Vector2(150, 60)
			sim.players[2].items = [Defs.LANTERN, Defs.WHISTLE, 0]
			var thief: Dictionary = sim.creatures.values()[0]
			thief.pos = bank + Vector2(-70, 60)
			thief.home = thief.pos
			thief.held = Defs.SNACKS
			thief.munch = 99.0
			for frame in range(40):
				await physics_frame
			sim.act(3, "use")
	await _shot("action")
	print("RENDER_PASS")
	quit()
