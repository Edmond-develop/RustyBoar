extends Node3D
## Ледяной гейзер.
##   Покой: из ледяного конуса лениво курится пар, вода в жерле тихо колышется.
##   Предупреждение: вода бурлит, пар валит гуще, жерло светится.
##   Извержение: бьёт столб воды и брызг, вокруг — облако пара.
## Попавшего дрона подбрасывает, слегка ранит, а посылку сильно раскачивает.
## Время общее для всех игроков.

@export var period := 5.5
@export_range(0.0, 1.0) var phase := 0.0
@export var warning_time := 1.4
@export var erupt_time := 1.1
@export var radius := 1.6
@export var launch_speed := 17.7     ## ≈ 10 м вверх
@export var damage := 8.0

var _local_t := 0.0
var _glow_mat: StandardMaterial3D
var _water: MeshInstance3D
var _wisps: GPUParticles3D
var _bubbles: GPUParticles3D
var _column: GPUParticles3D
var _cloud: GPUParticles3D
var _blasted := false
var _was_erupting := false

static var _cone_mat: StandardMaterial3D


func _ready() -> void:
	if _cone_mat == null:
		_cone_mat = StandardMaterial3D.new()
		_cone_mat.albedo_color = Color(0.85, 0.93, 1.0)
		_cone_mat.roughness = 0.35
		_cone_mat.rim_enabled = true
		_cone_mat.rim = 0.4

	# Ледяной конус-кратер
	var cone := CylinderMesh.new()
	cone.top_radius = radius * 0.55
	cone.bottom_radius = radius * 1.25
	cone.height = 0.55
	cone.radial_segments = 16
	cone.rings = 2
	cone.material = _cone_mat
	var cmi := MeshInstance3D.new()
	cmi.mesh = cone
	cmi.position.y = 0.27
	add_child(cmi)

	# Вода в жерле (светится перед извержением)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(0.08, 0.25, 0.38)
	_glow_mat.roughness = 0.05
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(0.35, 0.8, 1.0)
	_glow_mat.emission_energy_multiplier = 0.0
	var disc := CylinderMesh.new()
	disc.top_radius = radius * 0.5
	disc.bottom_radius = radius * 0.5
	disc.height = 0.05
	disc.material = _glow_mat
	_water = MeshInstance3D.new()
	_water.mesh = disc
	_water.position.y = 0.5
	add_child(_water)

	_wisps = FX.particles(Color(0.95, 0.97, 1.0, 0.25), 10, 3.0, 0.35, 0.5, 1.0, Vector3(0.2, 0.4, 0), 20.0, false)
	_wisps.position.y = 0.6
	_wisps.emitting = true
	add_child(_wisps)

	_bubbles = FX.particles(Color(0.85, 0.95, 1.0, 0.8), 40, 0.6, 0.06, 1.0, 2.5, Vector3(0, -2, 0), 30.0, false)
	FX.set_box(_bubbles, Vector3(radius * 0.35, 0.05, radius * 0.35))
	_bubbles.position.y = 0.55
	add_child(_bubbles)

	_column = FX.particles(Color(0.9, 0.96, 1.0, 0.8), 320, 1.6, 0.14, 15.0, 20.0, Vector3(0, -12, 0), 6.0, false)
	FX.set_box(_column, Vector3(radius * 0.3, 0.1, radius * 0.3))
	_column.position.y = 0.6
	add_child(_column)

	_cloud = FX.particles(Color(0.95, 0.97, 1.0, 0.35), 60, 3.0, 1.1, 1.5, 4.0, Vector3(0, 0.8, 0), 60.0, false)
	FX.set_box(_cloud, Vector3(radius, 1.5, radius))
	_cloud.position.y = 6.0
	add_child(_cloud)


func _physics_process(delta: float) -> void:
	_local_t += delta
	var t: float = Network.game_time if Network.in_game else _local_t
	var cycle := fposmod(t + phase * period, period)
	var idle_time := period - warning_time - erupt_time
	var warning := cycle >= idle_time and cycle < idle_time + warning_time
	var erupting := cycle >= idle_time + warning_time

	_bubbles.emitting = warning
	_column.emitting = erupting
	_cloud.emitting = erupting
	_wisps.amount_ratio = 1.0 if warning else 0.5

	var glow := 0.0
	var wobble := 0.0
	if warning:
		var w := (cycle - idle_time) / warning_time
		glow = 0.5 + w * 2.5
		wobble = 0.03 + w * 0.05
	elif erupting:
		glow = 3.0
	_glow_mat.emission_energy_multiplier = glow
	_water.position.y = 0.5 + sin(t * 30.0) * wobble

	if erupting and not _was_erupting:
		_blasted = false
		var me = Network.local_player
		if me and me.global_position.distance_to(global_position) < 12.0:
			me.add_shake(0.06)
	_was_erupting = erupting

	if erupting and not _blasted:
		var me = Network.local_player
		if me and not me.is_dead:
			var p: Vector3 = me.global_position
			var flat := Vector2(p.x - global_position.x, p.z - global_position.z).length()
			if flat < radius * 1.1 and p.y < global_position.y + 2.5:
				_blasted = true
				me.launch(launch_speed, damage, 0.6, 5.0, true)
