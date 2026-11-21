extends Node3D
## Гейзерная трещина поперёк дороги. Из неё всё время сочится пар; перед выбросом шипит
## и светится (~1.2 с), потом бьёт столб пара: дрона подбрасывает и сносит вбок —
## можно улететь с дороги в пропасть. Время выбросов — по общим часам игры.

@export var road_dir := Vector3.FORWARD
@export var road_width := 7.5
@export var period := 6.0
@export var phase := 0.0
@export var up_speed := 10.5
@export var side_speed := 4.0

const WARN := 1.2
const BLAST := 0.7

var _local_t := 0.0
var _side := Vector3.RIGHT
var _glow: StandardMaterial3D
var _wisps: GPUParticles3D
var _column: GPUParticles3D
var _hiss: GPUParticles3D
var _blasted := {}
var _last_cycle := -1


func _ready() -> void:
	road_dir.y = 0.0
	road_dir = road_dir.normalized()
	_side = Vector3(-road_dir.z, 0.0, road_dir.x)
	var yaw := atan2(road_dir.x, road_dir.z)
	# сама трещина: тёмная рваная щель через всю дорогу, края светятся
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(0.05, 0.07, 0.1)
	_glow.emission_enabled = true
	_glow.emission = Color(0.55, 0.85, 1.0)
	_glow.emission_energy_multiplier = 0.3
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 13.0 + global_position.z * 7.0)
	var n := 7
	var w := road_width + 0.6
	for i in n:
		var bm := BoxMesh.new()
		bm.size = Vector3(w / n + 0.35, 0.06, rng.randf_range(0.35, 0.7))
		bm.material = _glow
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.position = Vector3(-w * 0.5 + (i + 0.5) * w / n, 0.02, rng.randf_range(-0.25, 0.25))
		mi.rotation.y = rng.randf_range(-0.35, 0.35)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var holder := Node3D.new()
		holder.rotation.y = yaw
		add_child(holder)
		holder.add_child(mi)
	_wisps = FX.particles(Color(0.92, 0.95, 1.0, 0.35), 40, 2.2, 0.35, 0.6, 1.6, Vector3(0, 0.4, 0), 20.0, false)
	FX.set_box(_wisps, Vector3(w * 0.5, 0.05, 0.3))
	_wisps.rotation.y = yaw
	_wisps.emitting = true
	add_child(_wisps)
	_hiss = FX.particles(Color(1.0, 1.0, 1.0, 0.6), 90, 0.6, 0.15, 3.0, 6.0, Vector3(0, -1, 0), 25.0, false)
	FX.set_box(_hiss, Vector3(w * 0.5, 0.05, 0.25))
	_hiss.rotation.y = yaw
	_hiss.emitting = false
	add_child(_hiss)
	_column = FX.particles(Color(0.95, 0.97, 1.0, 0.75), 260, 1.6, 0.9, 12.0, 20.0, Vector3(0, -3, 0), 12.0, false)
	FX.set_box(_column, Vector3(w * 0.5, 0.1, 0.4))
	_column.rotation.y = yaw
	_column.emitting = false
	add_child(_column)


func _physics_process(delta: float) -> void:
	_local_t += delta
	var t: float = Network.game_time if Network.in_game else _local_t
	var ct := t / period + phase
	var cyc := int(floor(ct))
	var c := (ct - cyc) * period          # секунды внутри цикла
	var blast_at := period - BLAST
	var warn := c >= blast_at - WARN and c < blast_at
	var blast := c >= blast_at
	_hiss.emitting = warn
	_column.emitting = blast
	_glow.emission_energy_multiplier = 3.5 if blast else (0.6 + 2.2 * (c - (blast_at - WARN)) / WARN if warn else 0.3)
	if cyc != _last_cycle:
		_blasted.clear()
		_last_cycle = cyc
	if not blast:
		return
	# сторона, куда сносит, — своя у каждого выброса (одинаковая у всех игроков)
	var sgn := 1.0 if (cyc * 7919 + int(global_position.x)) % 2 == 0 else -1.0
	for d in get_tree().get_nodes_in_group("player"):
		if d.is_dead or _blasted.has(d):
			continue
		var rel: Vector3 = d.global_position - global_position
		if absf(rel.dot(road_dir)) > 1.4 or absf(rel.dot(_side)) > road_width * 0.5 + 0.6 or rel.y < -1.0 or rel.y > 3.0:
			continue
		_blasted[d] = true
		d.launch(up_speed, 4.0, 0.8, 6.0, false, "scald")
		d.wind_shove(_side * sgn, side_speed)
		if d == Network.local_player:
			d.add_shake(0.3)
