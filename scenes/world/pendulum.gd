extends Node3D
## Ледяной маятник: шипастая глыба на цепях качается поперёк узкой дороги.
## Над ущельем — ледяная балка, на ней цепи. Пробегай, пока глыба на взмахе в стороне;
## попала — сильный удар вбок (часто — с дороги в пропасть).
## Качается по общему времени игры — у всех одинаково, без пересылок.

const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")

@export var road_dir := Vector3.FORWARD     ## вдоль дороги (качается поперёк)
@export var chain := 13.0                    ## длина цепи до центра глыбы
@export var amp := 1.05                      ## размах (рад)
@export var period := 3.6
@export var phase := 0.0
@export var block := 2.6
@export var strength := 4.5
@export var beam_len := 34.0

var _local_t := 0.0
var _pivot: Node3D
var _arm: Node3D
var _block: MeshInstance3D
var _side := Vector3.RIGHT
var _cool := {}
var _whoosh: GPUParticles3D


func _ready() -> void:
	road_dir.y = 0.0
	road_dir = road_dir.normalized()
	_side = Vector3(-road_dir.z, 0.0, road_dir.x)
	var ice := ShaderMaterial.new()
	ice.shader = ICE_SHADER
	ice.set_shader_parameter("deep", Color(0.03, 0.15, 0.3))
	ice.set_shader_parameter("mid", Color(0.2, 0.5, 0.75))
	ice.set_shader_parameter("snow_amount", 1.2)
	ice.set_shader_parameter("crack_amount", 0.7)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.25, 0.27, 0.3)
	metal.metallic = 0.85
	metal.roughness = 0.45
	# балка через ущелье
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(beam_len, 1.6, 2.2)
	bm.material = ice
	beam.mesh = bm
	beam.position = Vector3(0, chain + 0.8, 0)
	beam.basis = Basis(Vector3.UP, atan2(-_side.z, _side.x))
	add_child(beam)
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, chain, 0)
	_pivot.basis = Basis(Vector3.UP, atan2(-_side.z, _side.x))
	add_child(_pivot)
	_arm = Node3D.new()
	_pivot.add_child(_arm)
	# две цепи — все звенья одним мешем (одна отрисовка вместо десятков)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.22
	tm.rings = 6
	tm.ring_segments = 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sgn in [-1.0, 1.0]:
		var links := int(chain / 0.9)
		for i in links:
			var rot := Basis.from_euler(Vector3(PI * 0.5 if i % 2 == 0 else 0.0, 0.0, PI * 0.5))
			st.append_from(tm, 0, Transform3D(rot, Vector3(0, -0.45 - i * 0.9, sgn * 0.5)))
	var chains := MeshInstance3D.new()
	chains.mesh = st.commit()
	chains.material_override = metal
	chains.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arm.add_child(chains)
	_block = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = block * 0.5
	sph.height = block
	sph.radial_segments = 10
	sph.rings = 6
	sph.material = ice
	_block.mesh = sph
	_block.position = Vector3(0, -chain, 0)
	_arm.add_child(_block)
	# ледяные шипы на глыбе
	var spike_mat := StandardMaterial3D.new()
	spike_mat.albedo_color = Color(0.75, 0.9, 1.0)
	spike_mat.roughness = 0.1
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.28
	cone.height = 1.1
	cone.radial_segments = 6
	var sst := SurfaceTool.new()
	sst.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 10:
		var a := TAU * i / 10.0
		var dir := Vector3(cos(a), sin(a * 2.0) * 0.5, sin(a)).normalized()
		sst.append_from(cone, 0, Transform3D(Basis(Quaternion(Vector3.UP, dir)), dir * block * 0.45))
	var spikes := MeshInstance3D.new()
	spikes.mesh = sst.commit()
	spikes.material_override = spike_mat
	_block.add_child(spikes)
	_whoosh = FX.particles(Color(0.9, 0.95, 1.0, 0.7), 30, 0.6, 0.12, 0.2, 1.0, Vector3(0, -2, 0), 180.0, false)
	_whoosh.emitting = true
	_whoosh.amount_ratio = 0.0
	_block.add_child(_whoosh)


func _physics_process(delta: float) -> void:
	_local_t += delta
	var t: float = Network.game_time if Network.in_game else _local_t
	var w := TAU / period
	var th := amp * sin(w * t + phase)
	var om := amp * w * cos(w * t + phase)
	_arm.rotation.z = th
	_whoosh.amount_ratio = clampf(absf(om) / (amp * w), 0.0, 1.0)
	var bp := _block.global_position
	# скорость глыбы (поперёк дороги)
	var vel := _side * (om * chain * cos(th))
	for d in get_tree().get_nodes_in_group("player"):
		if d.is_dead:
			continue
		var p: Vector3 = d.global_position + Vector3.UP * 1.0
		if p.distance_to(bp) > block * 0.5 + 0.7:
			continue
		var key := d.get_instance_id()
		if _cool.get(key, -10.0) > _local_t:
			continue
		_cool[key] = _local_t + 0.8
		var dir := vel.normalized() if vel.length() > 0.5 else (p - bp).normalized()
		dir.y = 0.25
		d.receive_hit(dir.normalized(), strength * clampf(vel.length() / 12.0, 0.6, 1.4), bp)
		var me = Network.local_player
		if d == me:
			me.add_shake(0.4)
