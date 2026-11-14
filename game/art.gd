class_name Art
## Vector drawing helpers shared by the world view and the HUD. Everything is
## drawn in code so the game ships without sprite sheets (see DESIGN.md backlog).

const PLAYER_COLORS := [
	Color("f25f5c"), Color("3fa7d6"), Color("ffd23f"), Color("7bd389"),
	Color("c77dff"), Color("ff9f1c"), Color("5eead4"), Color("f472b6"),
]
const INK := Color("2a2233")

static func player_color(index: int) -> Color:
	return PLAYER_COLORS[posmod(index, PLAYER_COLORS.size())]

static func text(c: CanvasItem, pos: Vector2, value: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var font := ThemeDB.fallback_font
	var width := 1200.0 if align == HORIZONTAL_ALIGNMENT_CENTER else -1.0
	var origin := pos - Vector2(600.0, 0) if align == HORIZONTAL_ALIGNMENT_CENTER else pos
	c.draw_string_outline(font, origin, value, align, width, size, 5, Color(INK, color.a))
	c.draw_string(font, origin, value, align, width, size, color)

static func item(c: CanvasItem, pos: Vector2, type: int, s := 1.0) -> void:
	match type:
		Defs.RAFT:
			for index in range(3):
				var log_rect := Rect2(pos + Vector2(-11, -9 + index * 6.5) * s, Vector2(22, 5.5) * s)
				c.draw_rect(log_rect, Color("a9713c"))
				c.draw_rect(log_rect, Color("6b4423"), false, 1.0)
			c.draw_line(pos + Vector2(-6, -9) * s, pos + Vector2(-6, 10) * s, Color("e8d9a8"), 1.5 * s)
			c.draw_line(pos + Vector2(6, -9) * s, pos + Vector2(6, 10) * s, Color("e8d9a8"), 1.5 * s)
		Defs.ROPE:
			c.draw_arc(pos, 8 * s, 0, TAU, 20, Color("7a5a2e"), 5 * s)
			c.draw_arc(pos, 8 * s, 0, TAU, 20, Color("d9b572"), 3 * s)
			c.draw_line(pos + Vector2(6, 5) * s, pos + Vector2(12, 10) * s, Color("d9b572"), 2.5 * s)
		Defs.LANTERN:
			c.draw_circle(pos, 13 * s, Color(1, 0.85, 0.4, 0.25))
			c.draw_arc(pos + Vector2(0, -6) * s, 5 * s, PI, TAU, 10, Color("4a4a55"), 1.5 * s)
			c.draw_rect(Rect2(pos + Vector2(-5, -6) * s, Vector2(10, 13) * s), Color("ffd866"))
			c.draw_rect(Rect2(pos + Vector2(-5, -6) * s, Vector2(10, 13) * s), Color("4a4a55"), false, 1.5 * s)
			c.draw_rect(Rect2(pos + Vector2(-6, 6) * s, Vector2(12, 3) * s), Color("4a4a55"))
		Defs.WHISTLE:
			c.draw_circle(pos + Vector2(-3, 1) * s, 7 * s, Color("dfe6ee"))
			c.draw_arc(pos + Vector2(-3, 1) * s, 7 * s, 0, TAU, 16, Color("59626e"), 1.5 * s)
			c.draw_rect(Rect2(pos + Vector2(-1, -6) * s, Vector2(13, 6) * s), Color("dfe6ee"))
			c.draw_rect(Rect2(pos + Vector2(-1, -6) * s, Vector2(13, 6) * s), Color("59626e"), false, 1.5 * s)
			c.draw_circle(pos + Vector2(-3, 1) * s, 2.2 * s, Color("59626e"))
		Defs.SNACKS:
			var bag := PackedVector2Array([pos + Vector2(-8, -5) * s, pos + Vector2(8, -5) * s, pos + Vector2(10, 10) * s, pos + Vector2(-10, 10) * s])
			c.draw_colored_polygon(bag, Color("e4572e"))
			c.draw_polyline(PackedVector2Array([bag[0], bag[1], bag[2], bag[3], bag[0]]), Color("8a2f16"), 1.5 * s)
			c.draw_rect(Rect2(pos + Vector2(-6, -9) * s, Vector2(12, 4) * s), Color("ffd23f"))
			c.draw_circle(pos + Vector2(0, 3) * s, 3 * s, Color("ffe9a8"))

static func raft(c: CanvasItem, pos: Vector2) -> void:
	c.draw_circle(pos + Vector2(0, 3), 27, Color(1, 1, 1, 0.18))
	for index in range(5):
		var log_rect := Rect2(pos + Vector2(-24, -17 + index * 7), Vector2(48, 6.2))
		c.draw_rect(log_rect, Color("b07a44") if index % 2 == 0 else Color("a06c3a"))
		c.draw_rect(log_rect, Color("6b4423"), false, 1.0)
	for x: float in [-14.0, 14.0]:
		c.draw_line(pos + Vector2(x, -17), pos + Vector2(x, 18), Color("e8d9a8"), 2.0)

static func explorer(c: CanvasItem, pos: Vector2, color: Color, face: Vector2, state: int, sink: float, moving: bool, clock: float, held: int) -> void:
	var bob := sin(clock * 14.0) * 1.5 if moving and state == Defs.WALK else 0.0
	var body := pos + Vector2(0, bob)
	if state == Defs.SWIM:
		c.draw_arc(pos, 13 + fposmod(clock * 12.0, 8.0), 0, TAU, 20, Color(1, 1, 1, 0.5), 1.5)
		c.draw_circle(pos + Vector2(0, 4), 11, Color("3a86c8"))
		body = pos + Vector2(0, -2 + sin(clock * 6.0) * 1.5)
	else:
		c.draw_set_transform(pos + Vector2(0, 9), 0, Vector2(1, 0.45))
		c.draw_circle(Vector2.ZERO, 10, Color(0, 0, 0, 0.22))
		c.draw_set_transform(Vector2.ZERO)
	if state != Defs.SWIM:
		c.draw_circle(body - face * 6.0 + Vector2(0, 2), 6.5, color.darkened(0.45))
	c.draw_circle(body, 10.5, INK)
	c.draw_circle(body, 9.0, color)
	var look := body + face * 3.5
	var side := Vector2(-face.y, face.x)
	for sign_value: float in [-1.0, 1.0]:
		c.draw_circle(look + side * 3.6 * sign_value, 2.6, Color.WHITE)
		c.draw_circle(look + side * 3.6 * sign_value + face * 1.0, 1.3, INK)
	# Pith helmet.
	c.draw_set_transform(body + Vector2(0, -7), 0, Vector2(1, 0.55))
	c.draw_circle(Vector2.ZERO, 12, Color("c9b385"))
	c.draw_set_transform(Vector2.ZERO)
	c.draw_arc(body + Vector2(0, -7), 8, PI, TAU, 12, Color("efe2bd"), 7.0)
	c.draw_line(body + Vector2(-8, -8), body + Vector2(8, -8), color.darkened(0.2), 2.0)
	if sink > 0.05 and state != Defs.SWIM:
		c.draw_rect(Rect2(body + Vector2(-12, 10 - sink * 14.0), Vector2(24, sink * 14.0 + 3)), Color("4f4a2e"))
	if state == Defs.STUN:
		for index in range(3):
			var star := body + Vector2(0, -20) + Vector2.from_angle(clock * 5.0 + index * TAU / 3.0) * Vector2(11, 4)
			c.draw_circle(star, 2.5, Color("ffe66d"))
	if held != Defs.NONE and state != Defs.SWIM:
		item(c, body + side * 13.0 + Vector2(0, 2), held, 0.6)

static func snuffler(c: CanvasItem, pos: Vector2, dir: Vector2, held: int, clock: float) -> void:
	var face := dir.normalized() if dir.length() > 0.2 else Vector2.RIGHT
	var hop := absf(sin(clock * 9.0)) * 2.5 if dir.length() > 0.2 else 0.0
	var body := pos + Vector2(0, -hop)
	c.draw_set_transform(pos + Vector2(0, 7), 0, Vector2(1, 0.45))
	c.draw_circle(Vector2.ZERO, 9, Color(0, 0, 0, 0.2))
	c.draw_set_transform(Vector2.ZERO)
	c.draw_line(body - face * 7.0, body - face * 14.0 + Vector2(0, -5), Color("7d5ba6"), 3.0)
	c.draw_circle(body, 9.5, INK)
	c.draw_circle(body, 8.0, Color("a98bd6"))
	c.draw_circle(body + face * 7.0, 4.5, Color("d9c7f2"))
	c.draw_circle(body + face * 10.5, 1.8, INK)
	var side := Vector2(-face.y, face.x)
	for sign_value: float in [-1.0, 1.0]:
		c.draw_circle(body + face * 3.0 + side * 4.0 * sign_value + Vector2(0, -2), 1.6, INK)
		c.draw_circle(body - face * 2.0 + side * 6.5 * sign_value + Vector2(0, -5), 3.0, Color("7d5ba6"))
	if held != Defs.NONE:
		item(c, body + face * 14.0, held, 0.55)

static func grumble(c: CanvasItem, pos: Vector2, state: int, clock: float) -> void:
	var breathe := 1.0 + sin(clock * 1.6) * 0.03
	var radius := Defs.GRUMBLE_R * breathe
	c.draw_set_transform(pos + Vector2(0, 20), 0, Vector2(1, 0.4))
	c.draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.25))
	c.draw_set_transform(Vector2.ZERO)
	c.draw_circle(pos, radius + 2.0, INK)
	c.draw_circle(pos, radius, Color("6f8f5a"))
	c.draw_circle(pos + Vector2(-9, -11), 9, Color("86a86c"))
	c.draw_circle(pos + Vector2(10, -6), 6, Color("86a86c"))
	for sign_value: float in [-1.0, 1.0]:
		c.draw_circle(pos + Vector2(17 * sign_value, -20), 6.5, Color("56704a"))
		var eye := pos + Vector2(9 * sign_value, -3)
		if state == Defs.C_IDLE:
			c.draw_line(eye + Vector2(-4, 0), eye + Vector2(4, 0), INK, 2.0)
		else:
			c.draw_circle(eye, 3.6, Color.WHITE)
			c.draw_circle(eye, 1.8, INK)
			if state == Defs.C_STOMP:
				c.draw_line(eye + Vector2(-5 * sign_value, -4), eye + Vector2(4 * sign_value, -7), INK, 2.5)
	c.draw_circle(pos + Vector2(0, 5), 4.0, Color("3d4f33"))
	if state == Defs.C_EAT:
		c.draw_circle(pos + Vector2(0, 13), 3.0 + absf(sin(clock * 10.0)) * 3.0, INK)
	elif state == Defs.C_IDLE:
		for index in range(3):
			var phase := fposmod(clock * 0.5 + index * 0.33, 1.0)
			text(c, pos + Vector2(22 + phase * 16.0, -24 - phase * 26.0), "z", 10 + int(phase * 8.0), Color(1, 1, 1, 1.0 - phase))
	else:
		c.draw_arc(pos + Vector2(0, 14), 5, PI, TAU, 8, INK, 2.0)

static func egg(c: CanvasItem, pos: Vector2, glow: float, clock: float, hatched: bool) -> void:
	var pulse := 0.5 + 0.5 * sin(clock * 2.0)
	for ring in range(5):
		c.draw_circle(pos, 60.0 + ring * 22.0 + pulse * 8.0, Color(1.0, 0.95, 0.6, (0.05 + glow * 0.07) * (1.0 - ring / 6.0)))
	if hatched:
		for ray in range(12):
			var angle := ray * TAU / 12.0 + clock * 0.4
			c.draw_line(pos + Vector2.from_angle(angle) * 60.0, pos + Vector2.from_angle(angle) * (110.0 + pulse * 30.0), Color(1, 0.97, 0.7, 0.7), 4.0)
	var wobble := sin(clock * 5.0) * 0.06 * glow
	c.draw_set_transform(pos + Vector2(0, 40), 0, Vector2(1, 0.3))
	c.draw_circle(Vector2.ZERO, 40, Color(0, 0, 0, 0.25))
	c.draw_set_transform(pos, wobble, Vector2(1, 1.3))
	c.draw_circle(Vector2.ZERO, 37, INK)
	c.draw_circle(Vector2.ZERO, 35, Color("fff6d6").lerp(Color("fffbe8"), pulse))
	for spot: Vector3 in [Vector3(-14, -12, 7), Vector3(12, -4, 9), Vector3(-6, 14, 6), Vector3(16, 18, 5), Vector3(-20, 6, 4)]:
		c.draw_circle(Vector2(spot.x, spot.y), spot.z, Color("9be3d3"))
	if hatched:
		c.draw_polyline(PackedVector2Array([Vector2(-34, -4), Vector2(-18, 4), Vector2(-8, -8), Vector2(6, 5), Vector2(18, -6), Vector2(34, 2)]), INK, 2.5)
	c.draw_set_transform(Vector2.ZERO)
