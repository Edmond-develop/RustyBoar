extends CanvasLayer
## ВРЕМЕННАЯ карта Ледяного лабиринта — пока держишь Tab.
## Рисует стены, расщелины с водой, площадку с воротами, гнёзда и зеркала,
## жаровни, себя (стрелка — куда смотрит камера), друзей и ботов.
## Создаётся из toros_field.gd; ей нужны его массивы стен.

var maze: Node3D                 ## toros_field.gd
var _view: Control


func _ready() -> void:
	layer = 20
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_map)
	_view.visible = false
	add_child(_view)


func _process(_delta: float) -> void:
	var show := Input.is_action_pressed("map") and maze != null
	_view.visible = show
	if show:
		_view.queue_redraw()


func _draw_map() -> void:
	var vp := _view.get_viewport_rect().size
	var x_min: float = -maze.half_width
	var x_max: float = maze.half_width
	var z_top: float = maze.wall_z - 6.0          # север — сверху
	var z_bot: float = maze.z_south + 8.0
	var margin := Vector2(40.0, 70.0)
	var s := minf((vp.x - margin.x * 2.0) / (x_max - x_min), (vp.y - margin.y * 2.0 - 30.0) / (z_bot - z_top))
	var size := Vector2((x_max - x_min) * s, (z_bot - z_top) * s)
	var origin := Vector2((vp.x - size.x) * 0.5, margin.y)
	var to_map := func(x: float, z: float) -> Vector2:
		return origin + Vector2((x - x_min) * s, (z - z_top) * s)

	# фон
	_view.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.04, 0.08, 0.72))
	_view.draw_rect(Rect2(origin, size), Color(0.85, 0.9, 0.96, 0.95))
	var font := ThemeDB.fallback_font
	_view.draw_string(font, Vector2(origin.x, origin.y - 22.0), "КАРТА ЛЕДЯНОГО ЛАБИРИНТА  (временная, пока держишь Tab)   ↑ север — ворота",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.9, 0.6))

	# расщелины с водой
	for r in maze.crevasse_rects:
		var a: Vector2 = to_map.call(r.x, r.z)
		var b: Vector2 = to_map.call(r.y, r.w)
		_view.draw_rect(Rect2(a, b - a), Color(0.1, 0.35, 0.8))
	# скользкий лёд
	for r in maze.slick_rects:
		var a: Vector2 = to_map.call(r.x, r.z)
		var b: Vector2 = to_map.call(r.y, r.w)
		_view.draw_rect(Rect2(a, b - a), Color(0.6, 0.85, 1.0, 0.8))

	# стены лабиринта
	var wall_col := Color(0.12, 0.2, 0.35)
	var wt := maxf(2.0, s * 2.6)
	var cell: float = maze.cell
	var x0: float = maze._x0
	var zs: float = maze.z_south
	for r in maze._h.size():
		for c in maze._h[r].size():
			if maze._h[r][c]:
				var z: float = zs - r * cell
				_view.draw_line(to_map.call(x0 + c * cell, z), to_map.call(x0 + (c + 1) * cell, z), wall_col, wt)
	for r in maze._v.size():
		for c in maze._v[r].size():
			if maze._v[r][c]:
				var x: float = x0 + c * cell
				_view.draw_line(to_map.call(x, zs - r * cell), to_map.call(x, zs - (r + 1) * cell), wall_col, wt)
	# Ледяной вал и ворота
	var gate = get_tree().get_first_node_in_group("coop_gate")
	var wz: float = maze.wall_z
	_view.draw_line(to_map.call(x_min, wz), to_map.call(-4.5, wz), wall_col, wt * 1.6)
	_view.draw_line(to_map.call(4.5, wz), to_map.call(x_max, wz), wall_col, wt * 1.6)
	var gate_col := Color(0.2, 0.9, 0.3) if gate and gate.is_open else Color(1.0, 0.5, 0.1)
	_view.draw_line(to_map.call(-4.5, wz), to_map.call(4.5, wz), gate_col, wt * 1.6)
	_view.draw_string(font, to_map.call(-14.0, wz - 2.0), "ВОРОТА", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, gate_col)
	# вход
	_view.draw_string(font, to_map.call(-10.0, zs + 6.5), "ВХОД (с юга)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.2, 0.3, 0.5))

	if gate:
		# маяк, его луч (до глыбы), барьер и печать
		var bp: Vector2 = to_map.call(gate.beacon_pos.x, gate.beacon_pos.z)
		var stop: Vector2 = to_map.call(maze.beam_stop.x, maze.beam_stop.y)
		_view.draw_dashed_line(bp, stop, Color(1.0, 0.6, 0.1), 2.0, 8.0)
		_view.draw_circle(bp, 6.0, Color(1.0, 0.75, 0.2))
		_view.draw_string(font, bp + Vector2(8, -6), "маяк", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.4, 0.1))
		_view.draw_circle(stop, 6.0, Color(0.15, 0.25, 0.45))
		var br: Vector4 = maze.barrier
		_view.draw_line(to_map.call(br.x, br.z), to_map.call(br.y, br.z), Color(0.15, 0.25, 0.45), wt * 1.5)
		_view.draw_string(font, to_map.call(br.x, br.z - 2.0), "барьер", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.15, 0.25, 0.45))
		var sc: Vector3 = gate.seal_center()
		_view.draw_circle(to_map.call(sc.x, sc.z), 5.0, Color(1.0, 0.5, 0.1))
	# жаровни
	for h in get_tree().get_nodes_in_group("heat_source"):
		var hp: Vector3 = (h as Node3D).global_position
		if hp.z < z_top or hp.z > z_bot:
			continue
		_view.draw_circle(to_map.call(hp.x, hp.z), 4.0, Color(1.0, 0.35, 0.1))
	# боты
	for b in get_tree().get_nodes_in_group("coop_helper"):
		var p: Vector3 = (b as Node3D).global_position
		_view.draw_circle(to_map.call(p.x, p.z), 5.0, Color(0.3, 0.85, 0.35))
	# игроки
	var me: Node3D = Network.local_player
	for d in get_tree().get_nodes_in_group("player"):
		var p: Vector3 = (d as Node3D).global_position
		var q: Vector2 = to_map.call(clampf(p.x, x_min, x_max), clampf(p.z, z_top, z_bot))
		if d == me:
			var cam: Node3D = me.get("camera_pivot")
			var yaw: float = cam.global_rotation.y if cam else 0.0
			var fwd := Vector2(-sin(yaw), -cos(yaw))
			var right := Vector2(-fwd.y, fwd.x)
			var tri := PackedVector2Array([q + fwd * 12.0, q - fwd * 7.0 + right * 7.0, q - fwd * 7.0 - right * 7.0])
			_view.draw_colored_polygon(tri, Color(1.0, 0.45, 0.1))
			_view.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0.2, 0.08, 0.0), 2.0)
		else:
			_view.draw_circle(q, 6.0, d.get("player_color") if d.get("player_color") else Color.WHITE)
			_view.draw_string(font, q + Vector2(8, 5), Network.get_player_name(int(d.get("peer_id"))), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.1, 0.1, 0.2))

	# легенда
	var ly := origin.y + size.y + 24.0
	var lx := origin.x
	var items := [
		[Color(1.0, 0.45, 0.1), "ты"], [Color(0.3, 0.85, 0.35), "бот"], [Color(1.0, 0.6, 0.1), "луч маяка"],
		[Color(1.0, 0.35, 0.1), "жаровня"], [Color(0.1, 0.35, 0.8), "расщелина с водой"],
		[Color(0.6, 0.85, 1.0), "скользкий лёд"],
	]
	for it in items:
		_view.draw_rect(Rect2(Vector2(lx, ly - 12.0), Vector2(14, 14)), it[0])
		_view.draw_string(font, Vector2(lx + 20.0, ly), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.95, 1.0))
		lx += 40.0 + font.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
