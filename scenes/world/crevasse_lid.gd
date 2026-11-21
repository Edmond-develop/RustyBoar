extends StaticBody3D
## Скрытая трещина в Снежной пустоши: сверху — снежный пласт вровень с сугробами, под ним пропасть.
## Встал на пласт — он трещит (CRACK_TIME с) и обваливается вместе с дроном. Через RESPAWN с
## ветер надувает его снова. Издалека пласт не отличить от снега: чуть просел и в мелких трещинках.
## Решает хост (по всем дронам), остальным рассылает.

const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")
const CRACK_TIME := 0.35
const RESPAWN := 15.0

@export var a := Vector2.ZERO        ## концы трещины (x, z)
@export var b := Vector2.ZERO
@export var half_width := 1.6
@export var top_y := 0.0

var broken := false
var _timer := 0.0
var _cracking := -1.0
var _mesh: MeshInstance3D
var _col: CollisionShape3D
var _len := 0.0
var _w := 0.0
var _puff: GPUParticles3D
var _chunks: GPUParticles3D


func _ready() -> void:
	add_to_group("crevasse_lid")
	var d := b - a
	_len = d.length() + 3.6
	_w = half_width * 2.0 + 3.6        # с запасом: края трещины в рельефе — скошенные
	var mid := (a + b) * 0.5
	global_position = Vector3(mid.x, top_y, mid.y)
	rotation.y = atan2(d.x, d.y)
	# тот же снег, что и вокруг (материал рельефа) — пласт не отличить
	var ter = get_tree().get_first_node_in_group("terrain")
	var snow: Material = ter.get("terrain_material") if ter else null
	if snow == null:
		snow = _fallback_snow()
	var bm := BoxMesh.new()
	bm.size = Vector3(_w, 0.7, _len)
	bm.material = snow
	_mesh = MeshInstance3D.new()
	_mesh.mesh = bm
	_mesh.position.y = -0.32          # верх на 3 см выше снега вокруг — рваный край трещины не виден
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var shape := BoxShape3D.new()
	shape.size = Vector3(_w, 0.7, _len)
	_col = CollisionShape3D.new()
	_col.shape = shape
	_col.position.y = -0.32
	add_child(_col)
	_puff = FX.particles(Color(0.95, 0.97, 1.0, 0.8), 140, 1.8, 0.7, 1.5, 5.0, Vector3(0, -3, 0))
	FX.set_box(_puff, Vector3(_w * 0.5, 0.5, _len * 0.5))
	add_child(_puff)
	_chunks = FX.particles(Color(0.9, 0.94, 1.0), 70, 2.6, 0.35, 0.5, 2.0, Vector3(0, -14, 0))
	FX.set_box(_chunks, Vector3(_w * 0.5, 0.3, _len * 0.5))
	add_child(_chunks)


func _fallback_snow() -> Material:
	var m := ShaderMaterial.new()
	m.shader = ICE_SHADER
	m.set_shader_parameter("snow_amount", 2.2)
	return m


func _on_lid(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) < _w * 0.5 + 0.1 and absf(l.z) < _len * 0.5 + 0.1 and l.y > -0.5 and l.y < 2.2


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if broken:
		_timer -= delta
		if _timer <= 0.0:
			for d in get_tree().get_nodes_in_group("player"):
				if _on_lid(d.global_position) or to_local(d.global_position).y < -0.6 and absf(to_local(d.global_position).x) < _w * 0.5:
					_timer = 1.0
					return
			_restore.rpc()
		return
	if _cracking >= 0.0:
		_cracking += delta
		if _cracking >= CRACK_TIME:
			_cracking = -1.0
			_collapse.rpc()
		return
	for d in get_tree().get_nodes_in_group("player"):
		if not d.is_dead and _on_lid(d.global_position):
			_cracking = 0.0
			_crack.rpc()
			return


@rpc("authority", "call_local", "reliable")
func _crack() -> void:
	_puff.restart()
	var me = Network.local_player
	if me and _on_lid(me.global_position):
		me.add_shake(0.35)


@rpc("authority", "call_local", "reliable")
func _collapse() -> void:
	broken = true
	_timer = RESPAWN
	_col.set_deferred("disabled", true)
	_mesh.visible = false
	_puff.restart()
	_chunks.restart()


@rpc("authority", "call_local", "reliable")
func _restore() -> void:
	broken = false
	_col.disabled = false
	_mesh.visible = true
