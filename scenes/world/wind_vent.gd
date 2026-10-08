extends Node3D
## Ледяная расщелина в берегу, из которой периодически бьёт ветер поперёк реки.
## Перед порывом из расщелины сыплется снег. Ветер сносит дрона (к полыньям!)
## и раскачивает посылку. Узел ставится у берега, ветер дует по blow_dir.

@export var blow_dir := Vector3(-1, 0, 0)
@export var length := 32.0          ## Как далеко бьёт ветер
@export var depth := 7.0            ## Ширина полосы ветра (вдоль реки)
@export var strength := 7.0         ## Скорость сноса, м/с
@export var period := 6.0
@export_range(0.0, 1.0) var phase := 0.0
@export var warning_time := 1.0
@export var gust_time := 2.2

var _local_t := 0.0
var _stream: GPUParticles3D
var _warn: GPUParticles3D


func _ready() -> void:
	var grill_mat := StandardMaterial3D.new()
	grill_mat.albedo_color = Color(0.1, 0.14, 0.2)
	grill_mat.roughness = 0.8
	var grill := BoxMesh.new()
	grill.size = Vector3(0.6, 2.4, depth * 0.8)
	grill.material = grill_mat
	var mi := MeshInstance3D.new()
	mi.mesh = grill
	mi.position.y = 1.2
	add_child(mi)

	_stream = FX.particles(Color(1, 1, 1, 0.8), 500, 1.6, 0.05, 16.0, 22.0, Vector3(0, -1, 0), 6.0, false)
	FX.set_box(_stream, Vector3(0.3, 1.2, depth * 0.5))
	(_stream.process_material as ParticleProcessMaterial).direction = blow_dir.normalized()
	_stream.position.y = 1.2
	add_child(_stream)

	_warn = FX.particles(Color(1, 1, 1, 0.8), 60, 1.0, 0.08, 1.0, 3.0, Vector3(0, -4, 0), 40.0, false)
	FX.set_box(_warn, Vector3(0.3, 1.0, depth * 0.4))
	(_warn.process_material as ParticleProcessMaterial).direction = blow_dir.normalized()
	_warn.position.y = 1.5
	add_child(_warn)


func _physics_process(delta: float) -> void:
	_local_t += delta
	var t: float = Network.game_time if Network.in_game else _local_t
	var cycle := fposmod(t + phase * period, period)
	var idle_time := period - warning_time - gust_time
	var warning := cycle >= idle_time and cycle < idle_time + warning_time
	var gusting := cycle >= idle_time + warning_time

	_warn.emitting = warning
	_stream.emitting = gusting
	if not gusting:
		return

	var me = Network.local_player
	if me == null or me.is_dead:
		return
	var rel: Vector3 = me.global_position - global_position
	var along := rel.dot(blow_dir.normalized())
	if along > -1.0 and along < length and absf(rel.z) < depth * 0.5 and rel.y < 6.0:
		var fade := clampf(1.0 - along / length, 0.3, 1.0)
		me.apply_wind(blow_dir.normalized() * strength * fade)
		me.add_shake(0.03)
