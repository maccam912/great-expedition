extends Node2D
## Draws whichever ExpeditionSim it is pointed at. Reads state only; never changes rules.

const ZOOM := 1.3
const DARK_SHADER := "
shader_type canvas_item;
uniform vec2 view_size;
uniform vec2 cave_x;
uniform vec3 lights[24];
uniform int light_count;
void fragment() {
	vec2 p = UV * view_size;
	float inside = smoothstep(cave_x.x - 10.0, cave_x.x + 70.0, p.x) * (1.0 - smoothstep(cave_x.y - 70.0, cave_x.y + 10.0, p.x));
	float lit = 0.0;
	for (int i = 0; i < 24; i++) {
		if (i >= light_count) { break; }
		lit = max(lit, 1.0 - smoothstep(lights[i].z * 0.5, lights[i].z, distance(p, lights[i].xy)));
	}
	COLOR = vec4(0.03, 0.02, 0.07, inside * (1.0 - lit) * 0.97);
}"

var sim: ExpeditionSim
var follow_id := 0              # 0 = slow backdrop pan
var camera := Camera2D.new()
var ground := Node2D.new()
var dark := ColorRect.new()
var clock := 0.0
var fx: Array = []              # {pos, t, life, text, ring, color}
var _shown: Dictionary = {}     # smoothing: key -> Vector2
var _moving: Dictionary = {}
var _ground_seed := -1
var _pings: Array = []

func _ready() -> void:
	ground.show_behind_parent = true
	ground.draw.connect(_draw_ground)
	add_child(ground)
	camera.zoom = Vector2(ZOOM, ZOOM)
	add_child(camera)
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var shader := Shader.new()
	shader.code = DARK_SHADER
	var material_resource := ShaderMaterial.new()
	material_resource.shader = shader
	dark.material = material_resource
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dark)

func show_sim(new_sim: ExpeditionSim, id: int) -> void:
	sim = new_sim
	follow_id = id
	_shown.clear()
	fx.clear()
	_ground_seed = -1

func on_event(event_name: String, pos: Vector2) -> void:
	var words := {"splash": "Sploosh!", "washed": "Washed up!", "fell": "Aaaah!", "stuck": "Stuck!", "whistle": "Fweeet!",
		"steal": "Yoink!", "munch": "Nom nom", "grumble": "GRRMBL", "tug": "Heave!", "snap": "Snap!", "miss": "…", "nope": "?"}
	if words.has(event_name):
		fx.append({"pos": pos, "t": 0.0, "life": 1.1, "text": words[event_name], "ring": event_name in ["splash", "whistle"],
			"color": Color("9ad7ff") if event_name == "splash" else Color.WHITE})
	if event_name == "whistle":
		_pings.append({"pos": pos, "t": 1.2})

func _hash(x: int, y: int) -> float:
	return fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)

func _smooth(key: String, target: Vector2, delta: float) -> Vector2:
	var current: Vector2 = _shown.get(key, target)
	_moving[key] = current.distance_to(target) > 0.6
	if current.distance_to(target) > 140.0:
		current = target
	else:
		current = current.lerp(target, 1.0 - exp(-delta * 18.0))
	_shown[key] = current
	return current

func _process(delta: float) -> void:
	clock += delta
	if sim == null or sim.terrain.w == 0:
		return
	if _ground_seed != sim.terrain.seed_value:
		_ground_seed = sim.terrain.seed_value
		ground.queue_redraw()
	var size := sim.terrain.size_px()
	var view := get_viewport_rect().size / ZOOM
	var target := Vector2(fposmod(clock * 40.0, maxf(size.x - view.x, 1.0)) + view.x / 2.0, size.y / 2.0)
	if sim.players.has(follow_id):
		target = _shown.get("p%d" % follow_id, sim.players[follow_id].pos)
	target.x = clampf(target.x, view.x / 2.0, size.x - view.x / 2.0)
	target.y = clampf(target.y, view.y / 2.0, size.y - view.y / 2.0)
	camera.position = camera.position.lerp(target, 1.0 - exp(-delta * 6.0)) if camera.position.distance_to(target) < 600.0 else target
	for effect: Dictionary in fx:
		effect.t += delta
	fx = fx.filter(func(effect: Dictionary) -> bool: return effect.t < effect.life)
	for ping: Dictionary in _pings:
		ping.t -= delta
	_pings = _pings.filter(func(ping: Dictionary) -> bool: return ping.t > 0.0)
	_update_darkness()
	queue_redraw()

func _update_darkness() -> void:
	var to_screen := get_viewport().get_canvas_transform()
	var lights := PackedVector3Array()
	var cave := Vector2(-10000, -10000)
	for zone: Dictionary in sim.terrain.zones:
		if zone.kind == Defs.Z_CAVE:
			cave = Vector2((to_screen * Vector2(zone.x0 * Defs.TILE, 0)).x, (to_screen * Vector2(zone.x1 * Defs.TILE, 0)).x)
	for player: Dictionary in sim.players.values():
		var radius := Defs.LANTERN_LIGHT if sim.has_item(player, Defs.LANTERN) else 46.0
		var pos: Vector2 = _shown.get("p%d" % player.id, player.pos)
		lights.append(Vector3((to_screen * pos).x, (to_screen * pos).y, radius * ZOOM))
	for item: Dictionary in sim.items.values():
		if item.type == Defs.LANTERN:
			lights.append(Vector3((to_screen * item.pos).x, (to_screen * item.pos).y, 130.0 * ZOOM))
	for ping: Dictionary in _pings:
		lights.append(Vector3((to_screen * ping.pos).x, (to_screen * ping.pos).y, 150.0 * ZOOM * minf(ping.t, 1.0)))
	var count := mini(lights.size(), 24)
	lights.resize(24)
	var shader_material: ShaderMaterial = dark.material
	shader_material.set_shader_parameter("view_size", get_viewport_rect().size)
	shader_material.set_shader_parameter("cave_x", cave)
	shader_material.set_shader_parameter("lights", lights)
	shader_material.set_shader_parameter("light_count", count)

# --- static terrain (drawn once per world) ----------------------------------

func _draw_ground() -> void:
	if sim == null or sim.terrain.w == 0:
		return
	var terrain := sim.terrain
	var tile := Defs.TILE
	for x in range(terrain.w):
		var zone_kind: int = terrain.zone_at(x * tile).kind
		for y in range(terrain.h):
			var kind := terrain.tile(x, y)
			var noise := _hash(x, y)
			var rect := Rect2(x * tile, y * tile, tile, tile)
			var mid := rect.get_center()
			match kind:
				Defs.GRASS, Defs.TREE:
					var grass := Color("7cb85a").lerp(Color("8ac765"), noise)
					if zone_kind == Defs.Z_BOG:
						grass = Color("a4cf6b")
					ground.draw_rect(rect, grass)
					if zone_kind == Defs.Z_BOG and kind == Defs.GRASS:
						ground.draw_rect(rect.grow(-1), Color("b7dc7a"))
						ground.draw_rect(rect.grow(-1), Color("6f9a45"), false, 2.0)
					if kind == Defs.GRASS and (noise > 0.82 or zone_kind == Defs.Z_BOG):
						for blade in range(3):
							var base := mid + Vector2(-6 + blade * 6, 6)
							ground.draw_line(base, base + Vector2(-2 + blade * 2, -8), Color("5e9a48"), 1.5)
					elif kind == Defs.GRASS and noise < 0.035:
						ground.draw_circle(mid + Vector2(4, -3), 2.5, Color("fff3b0"))
						ground.draw_circle(mid + Vector2(-5, 5), 2.0, Color("ffb3c6"))
				Defs.WATER:
					ground.draw_rect(rect, Color("3f8fd0").lerp(Color("4a9bdb"), noise))
				Defs.SAND:
					ground.draw_rect(rect, Color("e6d39a").lerp(Color("eddca8"), noise))
					if noise > 0.7:
						ground.draw_circle(mid + Vector2(noise * 10.0 - 5.0, 3), 1.5, Color("c9b57a"))
				Defs.MUD:
					ground.draw_rect(rect, Color("8a6a48").lerp(Color("93724e"), noise))
					if noise > 0.75:
						ground.draw_arc(mid, 5, 0.3, 2.6, 6, Color("75583a"), 1.5)
				Defs.BOG:
					ground.draw_rect(rect, Color("4f4a2e").lerp(Color("585333"), noise))
					if noise > 0.6:
						ground.draw_circle(mid + Vector2(noise * 14.0 - 7.0, 2), 2.5, Color("6f6a42"))
						ground.draw_arc(mid + Vector2(-6, -5), 3.5, 0, TAU, 8, Color("6f6a42"), 1.0)
				Defs.ROCK:
					if zone_kind == Defs.Z_CAVE:
						ground.draw_rect(rect, Color("2b2733").lerp(Color("332e3d"), noise))
						if terrain.tile(x, y + 1) != Defs.ROCK:
							ground.draw_rect(Rect2(rect.position + Vector2(0, tile - 7), Vector2(tile, 7)), Color("1d1a24"))
					else:
						ground.draw_rect(rect, Color("b9ad94"))
				Defs.CAVE, Defs.PIT:
					ground.draw_rect(rect, Color("5a5364").lerp(Color("625b6d"), noise))
					if kind == Defs.PIT:
						ground.draw_circle(mid, 14, Color("2a2531"))
						ground.draw_circle(mid + Vector2(0, 2), 11.5, Color("0b0910"))
					elif noise > 0.85:
						ground.draw_circle(mid + Vector2(5, 4), 2.0, Color("4a4453"))
				Defs.RIDGE:
					ground.draw_rect(rect, Color("b9ad94").lerp(Color("c4b89f"), noise))
					if noise > 0.8:
						ground.draw_line(mid + Vector2(-7, -2), mid + Vector2(5, 4), Color("9d917a"), 1.5)
				Defs.VOID:
					var depth := clampf((y - 16) / 7.0, 0.0, 1.0)
					ground.draw_rect(rect, Color("5d6b7a").lerp(Color("131a26"), depth))
					if terrain.tile(x, y - 1) == Defs.RIDGE:
						ground.draw_rect(Rect2(rect.position, Vector2(tile, 9)), Color("8c8069"))
						ground.draw_rect(Rect2(rect.position + Vector2(0, 9), Vector2(tile, 4)), Color("3c4654"))
				Defs.GOAL:
					ground.draw_rect(rect, Color("f3ecd0").lerp(Color("fbf5dd"), noise))
					if noise > 0.8:
						ground.draw_circle(mid, 2.0, Color("ffe08a"))
	# Second pass so canopies and boulders overlap their neighbours.
	for y in range(terrain.h):
		for x in range(terrain.w):
			var kind := terrain.tile(x, y)
			var noise := _hash(x, y)
			var mid := Vector2((x + 0.5) * tile + noise * 6.0 - 3.0, (y + 0.5) * tile + _hash(y, x) * 6.0 - 3.0)
			if kind == Defs.TREE:
				ground.draw_circle(mid + Vector2(2, 5), 17, Color(0, 0, 0, 0.18))
				ground.draw_circle(mid, 18, Color("2f6b3a"))
				ground.draw_circle(mid + Vector2(-3, -4), 13, Color("3f8a4a"))
				ground.draw_circle(mid + Vector2(-6, -7), 6, Color("55a35c"))
			elif kind == Defs.ROCK and terrain.zone_at(x * tile).kind != Defs.Z_CAVE:
				ground.draw_circle(mid + Vector2(2, 5), 16, Color(0, 0, 0, 0.2))
				ground.draw_circle(mid, 17, Color("6f727c"))
				ground.draw_circle(mid + Vector2(-2, -3), 13.5, Color("8d909b"))
				ground.draw_circle(mid + Vector2(-6, -7), 5, Color("a9acb6"))

# --- everything that moves --------------------------------------------------

func _draw() -> void:
	if sim == null or sim.terrain.w == 0:
		return
	var delta := get_process_delta_time()
	var terrain := sim.terrain
	var tile := Defs.TILE
	var view := get_viewport_rect().size / ZOOM
	var x0 := int((camera.position.x - view.x / 2.0) / tile) - 1
	var x1 := int((camera.position.x + view.x / 2.0) / tile) + 2
	var y0 := int((camera.position.y - view.y / 2.0) / tile) - 1
	var y1 := int((camera.position.y + view.y / 2.0) / tile) + 2
	for x in range(x0, x1):
		for y in range(y0, y1):
			var kind := terrain.tile(x, y)
			var noise := _hash(x, y)
			if kind == Defs.WATER and noise < 0.4:
				var offset := fposmod(clock * 60.0 + noise * 900.0, tile * 3.0) - tile
				var start := Vector2(x * tile + 6.0 + noise * 40.0, y * tile + offset)
				draw_line(start, start + Vector2(0, 10), Color(1, 1, 1, 0.28), 2.0)
			elif kind == Defs.RIDGE and sim.wind != Defs.CALM and noise < (0.5 if sim.wind == Defs.GUST else 0.15):
				var speed := 420.0 if sim.wind == Defs.GUST else 120.0
				var offset := fposmod(clock * speed + noise * 700.0, tile * 4.0) - tile
				var start := Vector2(x * tile + noise * 60.0, y * tile + offset)
				draw_line(start, start + Vector2(0, 26 if sim.wind == Defs.GUST else 10), Color(1, 1, 1, 0.5 if sim.wind == Defs.GUST else 0.3), 1.5)
	var near := 0
	for player: Dictionary in sim.players.values():
		if player.pos.distance_to(terrain.goal) < Defs.GOAL_RADIUS:
			near += 1
	Art.egg(self, terrain.goal, float(near) / maxf(sim.players.size(), 1.0), clock, sim.won)
	for item: Dictionary in sim.items.values():
		var pos := _smooth("i%d" % item.id, item.pos, delta)
		draw_set_transform(pos + Vector2(0, 8), 0, Vector2(1, 0.4))
		draw_circle(Vector2.ZERO, 10, Color(0, 0, 0, 0.2))
		draw_set_transform(Vector2.ZERO)
		Art.item(self, pos + Vector2(0, sin(clock * 3.0 + item.id) * 1.5), item.type)
	for raft: Dictionary in sim.rafts.values():
		Art.raft(self, _smooth("r%d" % raft.id, raft.pos, delta))
	for creature: Dictionary in sim.creatures.values():
		var pos := _smooth("c%d" % creature.id, creature.pos, delta)
		if creature.kind == Defs.GRUMBLE:
			Art.grumble(self, pos, creature.st, clock)
		else:
			var heading: Vector2 = creature.dir if _moving.get("c%d" % creature.id, false) else Vector2.ZERO
			Art.snuffler(self, pos, heading, creature.held, clock)
	var ids := sim.players.keys()
	ids.sort()
	for index in range(ids.size()):
		var player: Dictionary = sim.players[ids[index]]
		var key := "p%d" % player.id
		var pos := _smooth(key, player.pos, delta)
		Art.explorer(self, pos, Art.player_color(index), player.face, player.st, player.sink, _moving.get(key, false), clock + index, player.items[player.sel])
		if sim.blown(player):
			draw_arc(pos + Vector2(0, -12), 14, PI * 1.1, PI * 1.9, 8, Color(1, 1, 1, 0.8), 2.0)
		if player.id == follow_id and sim.time < 6.0:
			var tip := pos + Vector2(0, -26 - absf(sin(clock * 4.0)) * 5.0)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-6, -9), tip + Vector2(6, -9)]), Color.WHITE)
			Art.text(self, tip + Vector2(0, -13), "You", 13, Color.WHITE)
	for rope: Dictionary in sim.ropes.values():
		var end := sim.rope_end(rope)
		if end == Vector2.INF or not sim.players.has(rope.from):
			continue
		var from: Vector2 = _shown.get("p%d" % rope.from, sim.players[rope.from].pos)
		var to: Vector2 = _shown.get("%s%d" % [rope.kind, rope.target], end)
		var points := PackedVector2Array()
		var normal := (to - from).orthogonal().normalized()
		for step in range(13):
			var along := step / 12.0
			points.append(from.lerp(to, along) + normal * sin(along * PI) * sin(clock * 9.0 + along * 5.0) * 6.0)
		draw_polyline(points, Color("7a5a2e"), 4.0)
		draw_polyline(points, Color("d9b572"), 2.0)
	for effect: Dictionary in fx:
		var progress: float = effect.t / effect.life
		if effect.ring:
			draw_arc(effect.pos, 10.0 + progress * 70.0, 0, TAU, 28, Color(effect.color, 1.0 - progress), 3.0)
		Art.text(self, effect.pos + Vector2(0, -22 - progress * 26.0), effect.text, 15, Color(effect.color, 1.0 - progress * progress))
