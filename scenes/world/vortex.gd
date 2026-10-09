extends Node3D
## Снежный вихрь. Бродит по льду по плавной траектории (одинаковой у всех игроков).
## Попавшего дрона затягивает к центру и раскручивает вокруг, раскачивая посылку;
## в самом центре — подбрасывает и выкидывает наружу.

@export var range_x := 50.0        ## Как далеко гуляет вправо-влево
@export var range_z := 10.0        ## …и вперёд-назад
@export var speed := 0.06          ## Скорость блуждания
@export_range(0.0, 1.0) var phase := 0.0
@export var radius := 4.0          ## Радиус действия
@export var swirl := 7.0           ## Сила закручивания (м/с)
@export var pull := 2.5            ## Сила затягивания к центру

var _base := Vector3.ZERO
var _local_t := 0.0
var _funnel: Node3D
var _spiral: GPUParticles3D
var _dust: GPUParticles3D
var _throw_cooldown := 0.0


const VORTEX_SHADER := preload("res://shaders/vortex.gdshader")


func _ready() -> void:
	_base = position
	_funnel = Node3D.new()
	add_child(_funnel)

	# Воронка: три вложенных полупрозрачных конуса с бегущими полосами снега
	for i in 3:
		var mat := ShaderMaterial.new()
		mat.shader = VORTEX_SHADER
		mat.set_shader_parameter("spin", 2.0 + i * 0.8)
		mat.set_shader_parameter("rise", 1.0 + i * 0.4)
		mat.set_shader_parameter("density", 0.5 - i * 0.1)
		var cone := CylinderMesh.new()
		cone.top_radius = radius * (1.0 - i * 0.18)
		cone.bottom_radius = 0.5 + i * 0.35
		cone.height = 9.0
		cone.radial_segments = 24
		cone.rings = 4
		cone.cap_top = false
		cone.cap_bottom = false
		cone.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.position.y = 4.5
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_funnel.add_child(mi)

	# Спирали снега на разной высоте (вращаются вместе с воронкой)
	for k in 3:
		var spiral := FX.particles(Color(1, 1, 1, 0.8), 120, 1.8, 0.05, 1.0, 2.5, Vector3(0, 0.8, 0), 10.0, false)
		var pm := spiral.process_material as ParticleProcessMaterial
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_radius = radius * (0.35 + k * 0.2)
		pm.emission_ring_inner_radius = radius * (0.25 + k * 0.15)
		pm.emission_ring_height = 0.5
		pm.emission_ring_axis = Vector3.UP
		spiral.local_coords = true
		spiral.position.y = 0.5 + k * 2.0
		spiral.emitting = true
		_funnel.add_child(spiral)
	_spiral = _funnel.get_child(_funnel.get_child_count() - 1) as GPUParticles3D

	# Позёмка у основания
	_dust = FX.particles(Color(0.95, 0.97, 1.0, 0.55), 90, 1.2, 0.2, 2.0, 4.0, Vector3(0, -2, 0), 80.0, false)
	FX.set_box(_dust, Vector3(radius, 0.2, radius))
	_dust.emitting = true
	add_child(_dust)


func _physics_process(delta: float) -> void:
	_local_t += delta
	var t: float = Network.game_time if Network.in_game else _local_t
	var a := (t * speed + phase) * TAU
	var x := _base.x + sin(a) * range_x
	var z := _base.z + sin(a * 1.7 + phase * 5.0) * range_z
	position = Vector3(x, IceRiver.river_y(z), z)
	_funnel.rotation.y = fmod(t * 3.0, TAU)
	_funnel.scale = Vector3(1.0 + sin(t * 3.0) * 0.06, 1.0, 1.0 + cos(t * 2.7) * 0.06)

	_throw_cooldown -= delta
	var me = Network.local_player
	if me == null or me.is_dead:
		return
	var rel: Vector3 = me.global_position - global_position
	var flat := Vector2(rel.x, rel.z)
	var d := flat.length()
	if d > radius or rel.y > 8.0:
		return
	var out := flat.normalized() if d > 0.05 else Vector2.RIGHT
	var tangent := Vector2(-out.y, out.x)
	var strength := 1.0 - d / radius * 0.5
	var wind := (tangent * swirl - out * pull) * strength
	me.apply_wind(Vector3(wind.x, 0.0, wind.y))
	me.add_shake(0.04)
	if d < 1.3 and _throw_cooldown <= 0.0:
		_throw_cooldown = 2.0
		me.launch(6.5, 4.0, 0.5, 0.0)
