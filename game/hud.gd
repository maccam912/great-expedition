extends Control
## In-game overlay: route strip, timer, inventory, context hints, banners.

const ZONE_COLORS := [Color("8ac765"), Color("8ac765"), Color("4a9bdb"), Color("6a5a36"), Color("c4b89f"), Color("4a4453"), Color("3f8a4a"), Color("ffe08a")]
const ZONE_TIPS := [
	"Grab supplies — E picks up, two items each.", "",
	"The current is strong, and the raft only holds two.",
	"Hop between tussocks. Deep mire swallows explorers.",
	"Gusts blow south. Hide just below a boulder.",
	"It is dark in there. Mind the pits.",
	"Something large is asleep in the only pass…",
	"Everyone gather at the egg!",
]

var toast := ""
var toast_time := 0.0
var _zone := -1
var _zone_time := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_toast(message: String, seconds := 2.5) -> void:
	toast = message
	toast_time = seconds

func _process(delta: float) -> void:
	toast_time -= delta
	_zone_time -= delta
	queue_redraw()

func _hint(sim: ExpeditionSim, player: Dictionary) -> String:
	match int(player.st):
		Defs.STUN: return "Dazed…"
		Defs.STUCK: return "Stuck in the mire! A friend can tug you free (E) or throw a rope — or wait and crawl back out."
		Defs.SWIM: return "Swept away! A friend with a rope can haul you in."
		Defs.RIDE: return "Paddle with WASD  ·  E to step ashore"
	for other: Dictionary in sim.players.values():
		if other.st == Defs.STUCK and other.id != player.id and other.pos.distance_to(player.pos) < 60.0:
			return "E: tug your friend free"
	for item: Dictionary in sim.items.values():
		if item.pos.distance_to(player.pos) < 38.0:
			var full: bool = not Defs.NONE in player.items.slice(0, sim.slots)
			return "E: pick up %s%s" % [Defs.ITEM_NAMES[item.type], " (swaps with your %s)" % Defs.ITEM_NAMES[player.items[player.sel]] if full else ""]
	for raft: Dictionary in sim.rafts.values():
		if raft.pos.distance_to(player.pos) < 64.0:
			return "Walk onto the raft to board  ·  E: pick it up"
	if sim.ropes.has(player.id):
		return "Space: let go of the rope"
	return Defs.ITEM_HINTS[player.items[player.sel]]

func _draw() -> void:
	if Session.phase != "playing":
		return
	var sim: ExpeditionSim = Session.sim
	if sim.terrain.w == 0:
		return
	var screen := size
	var player: Dictionary = Session.local_player()
	# Route strip.
	var strip := Rect2(screen.x / 2.0 - 280, 16, 560, 12)
	draw_rect(strip.grow(4), Color(0.1, 0.09, 0.14, 0.75))
	var total := float(sim.terrain.w)
	for zone: Dictionary in sim.terrain.zones:
		draw_rect(Rect2(strip.position.x + zone.x0 / total * strip.size.x, strip.position.y, (zone.x1 - zone.x0) / total * strip.size.x, strip.size.y), ZONE_COLORS[zone.kind])
	var ids := sim.players.keys()
	ids.sort()
	for index in range(ids.size()):
		var dot := Vector2(strip.position.x + sim.players[ids[index]].pos.x / (total * Defs.TILE) * strip.size.x, strip.get_center().y)
		draw_circle(dot, 7.0 if ids[index] == Session.local_id else 5.5, Art.INK)
		draw_circle(dot, 5.5 if ids[index] == Session.local_id else 4.0, Art.player_color(index))
	var shown_time := sim.win_time if sim.won else sim.time
	Art.text(self, Vector2(screen.x / 2.0, 54), "%d:%02d" % [int(shown_time) / 60, int(shown_time) % 60], 18, Color.WHITE)
	if player.is_empty():
		Art.text(self, screen / 2.0, "Joining the expedition…", 22, Color.WHITE)
		return
	# Zone banner.
	var zone_kind: int = sim.terrain.zone_at(player.pos.x).kind
	if zone_kind != _zone:
		_zone = zone_kind
		if zone_kind != Defs.Z_CLEARING:
			_zone_time = 4.5
	if _zone_time > 0.0 and not sim.won:
		var alpha := clampf(_zone_time, 0.0, 1.0)
		Art.text(self, Vector2(screen.x / 2.0, 120), Defs.ZONE_NAMES[_zone], 34, Color(1, 0.95, 0.75, alpha))
		Art.text(self, Vector2(screen.x / 2.0, 148), ZONE_TIPS[_zone], 17, Color(1, 1, 1, alpha))
	if zone_kind == Defs.Z_RIDGE and sim.wind != Defs.CALM and not sim.won:
		var message := "Gust incoming — take cover!" if sim.wind == Defs.WARN else "Hold on!"
		Art.text(self, Vector2(screen.x / 2.0, 190), message, 22, Color("ffd23f") if sim.wind == Defs.WARN else Color("ff8a5c"))
	# Inventory.
	var box := 62.0
	var left := screen.x / 2.0 - (sim.slots * (box + 10) - 10) / 2.0
	for index in range(sim.slots):
		var rect := Rect2(left + index * (box + 10), screen.y - box - 24, box, box)
		draw_rect(rect, Color(0.1, 0.09, 0.14, 0.8))
		draw_rect(rect, Color.WHITE if index == player.sel else Color(1, 1, 1, 0.25), false, 3.0 if index == player.sel else 1.5)
		if player.items[index] != Defs.NONE:
			Art.item(self, rect.get_center() + Vector2(0, 2), player.items[index], 2.0)
		Art.text(self, rect.position + Vector2(10, 16), str(index + 1), 12, Color(1, 1, 1, 0.7))
	var selected: int = player.items[player.sel]
	Art.text(self, Vector2(screen.x / 2.0, screen.y - 6), Defs.ITEM_NAMES[selected] if selected != Defs.NONE else "empty hands", 14, Color.WHITE)
	if not sim.won:
		Art.text(self, Vector2(screen.x / 2.0, screen.y - box - 38), _hint(sim, player), 16, Color("fff3b0"))
	Art.text(self, Vector2(16, screen.y - 12), "WASD move · Space use · E interact · Q drop · 1-%d/Tab select · Esc leave" % sim.slots, 12, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_LEFT)
	if toast_time > 0.0:
		Art.text(self, Vector2(screen.x / 2.0, 230), toast, 18, Color(1, 1, 1, clampf(toast_time, 0.0, 1.0)))
	if sim.won:
		var panel := Rect2(screen / 2.0 - Vector2(280, 110), Vector2(560, 200))
		draw_rect(panel, Color(0.1, 0.09, 0.14, 0.88))
		draw_rect(panel, Color("ffe08a"), false, 3.0)
		Art.text(self, panel.get_center() + Vector2(0, -40), "Expedition complete!", 38, Color("ffe08a"))
		Art.text(self, panel.get_center() + Vector2(0, 0), "Everyone reached the egg in %d:%02d  ·  route #%d" % [int(sim.win_time) / 60, int(sim.win_time) % 60, Session.seed_value], 18, Color.WHITE)
		var next := "Enter: new expedition  ·  Esc: back to camp" if Session.is_authority() else "Waiting for the host to pick the next route…"
		Art.text(self, panel.get_center() + Vector2(0, 50), next, 16, Color("fff3b0"))
