extends Node3D
## Чёрный лёд. Когда дрон заходит на него, в точке входа появляется трещина
## и бежит за ним по его же следу. Пока идёшь — она отстаёт.
## Остановился или слишком медленный (тяжёлый груз, выдохся) — трещина догоняет,
## и лёд под дроном расходится: дрон оказывается в воде.
## Трещина своя у каждого игрока (рисуется и проверяется только для своего дрона).

@export var half_x := 12.0
@export var half_z := 5.0
@export var crack_speed := 4.2     ## Скорость трещины, м/с (шагом с посылкой — 4.8)
@export var start_delay := 0.5

var _path := PackedVector3Array()
var _dist := PackedFloat32Array()  ## Длина пути до каждой точки
var _front := 0.0
var _active := false
var _delay := 0.0
var _fade := 0.0
var _lines: MeshInstance3D
var _imesh: ImmediateMesh
var _line_mat: StandardMaterial3D
var _splash: GPUParticles3D


func _ready() -> void:
	# Тёмная прозрачная «плёнка» поверх льда
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.08, 0.16, 0.55)
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dark.roughness = 0.02
	dark.metallic_specular = 1.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(half_x * 2.0, half_z * 2.0)
	plane.material = dark
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position.y = 0.035
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	_line_mat = StandardMaterial3D.new()
	_line_mat.albedo_color = Color(0.9, 0.97, 1.0)
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_imesh = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.mesh = _imesh
	_lines.top_level = true
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)

	_splash = FX.particles(Color(0.75, 0.9, 1.0, 0.9), 70, 1.2, 0.1, 2.0, 6.0, Vector3(0, -12, 0), 40.0)
	_splash.top_level = true
	add_child(_splash)


func _physics_process(delta: float) -> void:
	var me = Network.local_player
	if _fade > 0.0:
		_fade -= delta
		_line_mat.albedo_color.a = clampf(_fade / 2.0, 0.0, 1.0)
		if _fade <= 0.0:
			_imesh.clear_surfaces()
	if me == null or me.is_dead:
		_stop()
		return

	var p: Vector3 = me.global_position
	var rel := p - global_position
	var inside := absf(rel.x) < half_x and absf(rel.z) < half_z and absf(rel.y) < 1.5

	if not inside:
		_stop()
		return

	if not _active:
		_active = true
		_fade = 0.0
		_line_mat.albedo_color.a = 1.0
		_path = PackedVector3Array([p])
		_dist = PackedFloat32Array([0.0])
		_front = 0.0
		_delay = start_delay
		return

	if p.distance_to(_path[_path.size() - 1]) > 0.35:
		_dist.append(_dist[_dist.size() - 1] + p.distance_to(_path[_path.size() - 1]))
		_path.append(p)

	if _delay > 0.0:
		_delay -= delta
	else:
		_front += crack_speed * delta
	var total := _dist[_dist.size() - 1] + p.distance_to(_path[_path.size() - 1])
	_draw_crack()

	var gap := total - _front
	if gap < 1.5:
		me.add_shake(0.04)   # трещит прямо под ногами!
	if gap <= 0.2 and me.is_grounded():
		_splash.global_position = p
		_splash.restart()
		var lake = get_tree().get_first_node_in_group("ice_lake")
		if lake:
			lake.request_break(p, 2.2)   # лёд расходится — дрон проваливается в воду
		else:
			me.kill("ЧЁРНЫЙ ЛЁД РАЗОШЁЛСЯ ПОД ДРОНОМ")
		_stop()


func _stop() -> void:
	if _active:
		_active = false
		_fade = 2.0


## Рисуем трещину от точки входа до фронта: ломаная со случайными изломами и ответвлениями
func _draw_crack() -> void:
	_imesh.clear_surfaces()
	if _path.size() < 2 and _front < 0.1:
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _line_mat)
	var prev := _crack_point(0)
	for i in range(1, _path.size()):
		if _dist[i - 1] > _front:
			break
		var cur := _crack_point(i)
		if _dist[i] > _front:
			var k := (_front - _dist[i - 1]) / maxf(_dist[i] - _dist[i - 1], 0.001)
			cur = prev.lerp(cur, k)
		_segment(prev, cur, 0.06)
		# ответвление
		if i % 4 == 0:
			var h := hash(i) % 1000 / 1000.0
			var side := Vector3(cur.z - prev.z, 0.0, prev.x - cur.x).normalized() * (0.6 + h)
			_segment(cur, cur + side * (1.0 if i % 8 == 0 else -1.0), 0.035)
		prev = cur
	_imesh.surface_end()


func _crack_point(i: int) -> Vector3:
	var p := _path[i]
	var jitter := Vector3((hash(i * 31) % 100) / 100.0 - 0.5, 0.0, (hash(i * 17) % 100) / 100.0 - 0.5) * 0.35
	return Vector3(p.x, global_position.y + 0.05, p.z) + jitter


func _segment(a: Vector3, b: Vector3, width: float) -> void:
	var dir := b - a
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	var side := Vector3(-dir.z, 0.0, dir.x).normalized() * width
	for v in [a - side, a + side, b - side, a + side, b + side, b - side]:
		_imesh.surface_add_vertex(v)
