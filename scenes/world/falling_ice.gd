extends Node3D
## Ущелье, где с краёв срываются ледяные глыбы (каньон, верная дорога после развилки B).
##
## На дороге сначала появляется тень (растёт и темнеет ~1.5 с), потом сверху падает глыба
## и разлетается. Попало — удар и толчок (можно слететь с дороги!).
## Когда и куда падает — считается по общему времени игры, у всех игроков одинаково,
## без пересылок по сети.

const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")
const SLOTS := 5

@export var a := Vector3.ZERO
@export var b := Vector3.ZERO
@export var lateral := 3.0        ## разброс поперёк дороги
@export var period := 1.5         ## как часто падает глыба
@export var warn := 1.6           ## сколько видна тень до удара
@export var fall_time := 0.7      ## сколько глыба летит
@export var top_y := 32.0
@export var radius := 2.4         ## радиус удара
@export var strength := 2.8

var _local_t := 0.0
var _shadows: Array[MeshInstance3D] = []
var _blocks: Array[MeshInstance3D] = []
var _shadow_mat: StandardMaterial3D
var _bursts: Array[GPUParticles3D] = []
var _hit_done := {}              ## номер глыбы → уже ударила (у этого компьютера)
var _side := Vector3.RIGHT


func _ready() -> void:
	var d := b - a
	d.y = 0.0
	_side = Vector3(-d.z, 0.0, d.x).normalized()
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.albedo_color = Color(0.02, 0.04, 0.08, 0.6)
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ice := ShaderMaterial.new()
	ice.shader = ICE_SHADER
	ice.set_shader_parameter("deep", Color(0.05, 0.22, 0.4))
	ice.set_shader_parameter("mid", Color(0.3, 0.6, 0.82))
	ice.set_shader_parameter("snow_amount", 1.2)
	for i in SLOTS:
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = 0.04
		cyl.radial_segments = 20
		cyl.material = _shadow_mat.duplicate()
		var sh := MeshInstance3D.new()
		sh.mesh = cyl
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sh.visible = false
		add_child(sh)
		_shadows.append(sh)
		var bm := BoxMesh.new()
		bm.size = Vector3(2.2, 1.8, 2.6)
		bm.material = ice
		var bl := MeshInstance3D.new()
		bl.mesh = bm
		bl.visible = false
		add_child(bl)
		_blocks.append(bl)
		var p := FX.particles(Color(0.82, 0.93, 1.0), 50, 1.3, 0.22, 3.0, 8.0, Vector3(0, -14, 0))
		add_child(p)
		_bursts.append(p)


## Хэш номера глыбы → 0..1
static func _h(k: int, salt: int) -> float:
	var x := (k * 73856093) ^ (salt * 19349663)
	x = (x ^ (x >> 13)) * 1274126177
	return float(absi(x) % 10007) / 10007.0


func _drop(k: int) -> Array:
	var t0 := k * period + _h(k, 1) * period * 0.6
	var u := _h(k, 2)
	var pos := a.lerp(b, u) + _side * (_h(k, 3) * 2.0 - 1.0) * lateral
	pos.y = lerpf(a.y, b.y, u) + 0.05
	return [t0, pos]


func _physics_process(delta: float) -> void:
	_local_t += delta
	var t: float = Network.game_time if Network.in_game else _local_t
	var k_now := int(floor(t / period))
	for slot in SLOTS:
		_shadows[slot].visible = false
		_blocks[slot].visible = false
	for k in range(k_now - 2, k_now + 2):
		if k < 0:
			continue
		var dr := _drop(k)
		var t0: float = dr[0]
		var pos: Vector3 = dr[1]
		var hit_t := t0 + warn
		var slot := posmod(k, SLOTS)
		if t >= t0 and t < hit_t:
			var u := (t - t0) / warn
			var sh := _shadows[slot]
			sh.visible = true
			sh.global_position = pos
			sh.scale = Vector3(0.3 + 0.7 * u, 1.0, 0.3 + 0.7 * u)
			(sh.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.a = 0.15 + 0.55 * u
			if t > hit_t - fall_time:
				var f := (t - (hit_t - fall_time)) / fall_time
				var bl := _blocks[slot]
				bl.visible = true
				bl.global_position = Vector3(pos.x, lerpf(top_y, pos.y + 0.9, f * f), pos.z)
				bl.rotation = Vector3(f * 2.0, k * 0.7, f * 1.3)
		elif t >= hit_t and not _hit_done.has(k):
			_hit_done[k] = true
			if t - hit_t < 0.5:
				_impact(slot, pos)
	# память о старых глыбах не копим
	if _hit_done.size() > 40:
		for key in _hit_done.keys():
			if int(key) < k_now - 4:
				_hit_done.erase(key)


func _impact(slot: int, pos: Vector3) -> void:
	_bursts[slot].global_position = pos + Vector3(0, 0.6, 0)
	_bursts[slot].restart()
	for d in get_tree().get_nodes_in_group("player"):
		if d.is_dead:
			continue
		var p: Vector3 = d.global_position
		var flat := Vector2(p.x - pos.x, p.z - pos.z)
		if flat.length() < radius + 0.4 and absf(p.y - pos.y) < 3.0:
			var dir := Vector3(flat.x, 0.0, flat.y)
			dir = dir.normalized() if dir.length() > 0.1 else _side
			d.receive_hit(dir, strength, pos + Vector3(0, 1.6, 0))
	var me = Network.local_player
	if me and Vector2(me.global_position.x - pos.x, me.global_position.z - pos.z).length() < 14.0:
		me.add_shake(0.15)
