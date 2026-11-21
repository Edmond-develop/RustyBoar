extends Node3D
## Дорога, которая осыпается за спиной (каньон, верная дорога между разворотом и развилкой B).
##
## Это ледяной карниз из плит над пропастью. Стоит дрону ступить на него, через миг
## плиты начинают отваливаться — с того конца, откуда он пришёл, — и волна обвала
## катится вслед со скоростью WAVE_SPEED — быстрее шага: пешком догоняет, проскочить можно только бегом. Когда всё обвалилось и рядом никого — карниз нарастает заново.
## Решает хост: рассылает «волна пошла отсюда, в такое-то время», дальше каждый считает сам.

const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")
const TILE := 3.2
const THICK := 2.6
const WAVE_SPEED := 7.6          ## м/с — быстрее шага (6), медленнее бега (11.5)
const START_DELAY := 0.45
const WARN := 0.3                ## плита проседает перед тем, как отвалиться
const REGROW := 14.0             ## через сколько после обвала карниз нарастает

@export var a := Vector3.ZERO
@export var b := Vector3.ZERO
@export var width := 8.0

var _tiles: Array[StaticBody3D] = []
var _meshes: Array[MeshInstance3D] = []
var _rest: Array[Transform3D] = []
var _dir := Vector3.FORWARD
var _len := 0.0
var _count := 0
var _wave_t := -1.0              ## время старта волны (по часам _clock), < 0 — нет волны
var _from_a := true
var _clock := 0.0
var _done_t := 0.0
var _fall_v: PackedFloat32Array
var _debris: GPUParticles3D


func _ready() -> void:
	var d := b - a
	d.y = 0.0
	_len = d.length()
	_dir = d / _len
	_count = int(ceil(_len / TILE))
	var side := Vector3(-_dir.z, 0.0, _dir.x)
	var snow := ShaderMaterial.new()
	snow.shader = ICE_SHADER
	snow.set_shader_parameter("deep", Color(0.3, 0.45, 0.62))
	snow.set_shader_parameter("mid", Color(0.6, 0.76, 0.9))
	snow.set_shader_parameter("edge", Color(0.9, 0.97, 1.0))
	snow.set_shader_parameter("snow_amount", 1.7)
	snow.set_shader_parameter("crack_amount", 0.7)
	snow.set_shader_parameter("band_scale", 1.5)
	var yaw := atan2(_dir.x, _dir.z)
	for i in _count:
		var t0 := i * TILE
		var l := minf(TILE, _len - t0)
		var c := a + _dir * (t0 + l * 0.5)
		# верх плит чуть выше дорог по краям — без мерцания на стыке
		c.y = lerpf(a.y, b.y, (t0 + l * 0.5) / _len) - THICK * 0.5 + 0.06
		var body := StaticBody3D.new()
		body.name = "Tile%d" % i
		body.add_to_group("canyon_road")
		add_child(body)
		body.global_transform = Transform3D(Basis(Vector3.UP, yaw), c)
		var bm := BoxMesh.new()
		# плиты чуть разные: неровный край, щели между ними
		var jw := width * (0.94 + 0.08 * sin(i * 2.3))
		bm.size = Vector3(jw, THICK * (0.9 + 0.2 * sin(i * 1.7)), l - 0.12)
		bm.material = snow
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.position.y = THICK * 0.5 - bm.size.y * 0.5
		mi.rotation.z = 0.02 * sin(i * 3.1)
		body.add_child(mi)
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, THICK, l)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		_tiles.append(body)
		_meshes.append(mi)
		_rest.append(body.global_transform)
	_fall_v.resize(_count)
	_debris = FX.particles(Color(0.85, 0.92, 1.0), 40, 1.6, 0.25, 1.0, 4.0, Vector3(0, -12, 0))
	add_child(_debris)


func _tile_of(p: Vector3) -> int:
	var t := (p - a).dot(_dir)
	var side := (p - a - _dir * t)
	side.y = 0.0
	if t < 0.0 or t > _len or side.length() > width * 0.5 + 0.3:
		return -1
	if absf(p.y - lerpf(a.y, b.y, t / _len)) > 2.0:
		return -1
	return clampi(int(t / TILE), 0, _count - 1)


## Когда отваливается плита i (по часам _clock), если волна идёт
func _fall_time(i: int) -> float:
	var k := i if _from_a else _count - 1 - i
	return _wave_t + START_DELAY + k * TILE / WAVE_SPEED


func _physics_process(delta: float) -> void:
	_clock += delta
	if multiplayer.is_server():
		if _wave_t < 0.0:
			for d in get_tree().get_nodes_in_group("player"):
				if d.is_dead or not d.is_grounded():
					continue
				var i := _tile_of(d.global_position)
				if i >= 0:
					_start.rpc(i < _count / 2)
					break
		else:
			var last := _fall_time(_count - 1 if _from_a else 0)
			if _clock > last + REGROW:
				var near := false
				for d in get_tree().get_nodes_in_group("player"):
					var t: float = (d.global_position - a).dot(_dir)
					if t > -6.0 and t < _len + 6.0 and Vector2(d.global_position.x - a.x - _dir.x * t, d.global_position.z - a.z - _dir.z * t).length() < width:
						near = true
				if not near:
					_regrow.rpc()
	if _wave_t < 0.0:
		return
	for i in _count:
		var ft := _fall_time(i)
		var body := _tiles[i]
		var mi := _meshes[i]
		if _clock < ft - WARN:
			continue
		if _clock < ft:
			# проседает и кренится (без дрожания — оно мерцало)
			var s := 1.0 - (ft - _clock) / WARN
			mi.position.y = THICK * 0.5 - (mi.mesh as BoxMesh).size.y * 0.5 - 0.12 * s
			mi.rotation.x = 0.05 * s * (1.0 if i % 2 == 0 else -1.0)
			continue
		var col := body.get_child(1) as CollisionShape3D
		if not col.disabled:
			col.disabled = true
			_debris.global_position = body.global_position + Vector3(0, 1.0, 0)
			_debris.restart()
			_fall_v[i] = 3.0
		if body.visible:
			_fall_v[i] += 30.0 * delta
			body.global_position.y -= _fall_v[i] * delta
			body.rotate_object_local(Vector3.RIGHT, delta * (1.4 + 0.6 * sin(i)))
			if body.global_position.y < CanyonLayout.ABYSS_Y - 6.0:
				body.visible = false


@rpc("authority", "call_local", "reliable")
func _start(from_a: bool) -> void:
	_from_a = from_a
	_wave_t = _clock


@rpc("authority", "call_local", "reliable")
func _regrow() -> void:
	_wave_t = -1.0
	for i in _count:
		var body := _tiles[i]
		body.global_transform = _rest[i]
		body.visible = true
		(body.get_child(1) as CollisionShape3D).disabled = false
		_meshes[i].position.y = THICK * 0.5 - (_meshes[i].mesh as BoxMesh).size.y * 0.5
		_meshes[i].rotation.x = 0.0
