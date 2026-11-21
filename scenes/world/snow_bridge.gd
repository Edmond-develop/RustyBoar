extends StaticBody3D
## Ложный снежный мост: выглядит как надёжная заснеженная дорога, а на деле — надув снега.
## Наступил — и он сразу рушится в пропасть вместе с дроном. Через время надувает снова.
## Рядом стоит настоящий мост — из гладкого льда, скользкий и страшный на вид.
## Решает хост (по всем дронам), остальным рассылает.

const ICE_SHADER := preload("res://shaders/pressure_ice.gdshader")

@export var a := Vector3.ZERO
@export var b := Vector3.ZERO
@export var width := 6.0
@export var respawn_time := 10.0

var broken := false
var _timer := 0.0
var _mesh: MeshInstance3D
var _col: CollisionShape3D
var _len := 0.0
var _dir := Vector3.FORWARD
var _puff: GPUParticles3D
var _chunks: GPUParticles3D


func _ready() -> void:
	var d := b - a
	d.y = 0.0
	_len = d.length()
	_dir = d / _len
	global_position = (a + b) * 0.5
	rotation.y = atan2(_dir.x, _dir.z)
	var snow := ShaderMaterial.new()
	snow.shader = ICE_SHADER
	snow.set_shader_parameter("deep", Color(0.42, 0.56, 0.7))
	snow.set_shader_parameter("mid", Color(0.74, 0.84, 0.93))
	snow.set_shader_parameter("edge", Color(0.95, 0.98, 1.0))
	snow.set_shader_parameter("snow_amount", 1.8)
	snow.set_shader_parameter("base_rough", 0.6)
	snow.set_shader_parameter("band_scale", 1.2)
	# плотный на вид снежный пласт с провисающим низом
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 1.4, _len + 1.0)
	bm.material = snow
	_mesh = MeshInstance3D.new()
	_mesh.mesh = bm
	_mesh.position.y = -0.7
	add_child(_mesh)
	var sag := SphereMesh.new()
	sag.radius = 1.0
	sag.height = 2.0
	sag.material = snow
	var under := MeshInstance3D.new()
	under.mesh = sag
	under.scale = Vector3(width * 0.45, 1.2, _len * 0.5)
	under.position.y = -1.3
	_mesh.add_child(under)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 1.4, _len + 1.0)
	_col = CollisionShape3D.new()
	_col.shape = shape
	_col.position.y = -0.7
	add_child(_col)
	_puff = FX.particles(Color(0.95, 0.97, 1.0, 0.75), 120, 1.6, 0.6, 1.5, 5.0, Vector3(0, -4, 0))
	FX.set_box(_puff, Vector3(width * 0.5, 0.6, _len * 0.5))
	add_child(_puff)
	_chunks = FX.particles(Color(0.9, 0.94, 1.0), 60, 2.5, 0.35, 0.5, 2.0, Vector3(0, -14, 0))
	FX.set_box(_chunks, Vector3(width * 0.5, 0.4, _len * 0.5))
	add_child(_chunks)


func _on_bridge(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) < width * 0.5 + 0.2 and absf(l.z) < _len * 0.5 + 0.3 and l.y > -0.5 and l.y < 2.2


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if broken:
		_timer -= delta
		if _timer <= 0.0:
			for d in get_tree().get_nodes_in_group("player"):
				if _on_bridge(d.global_position):
					_timer = 1.0
					return
			_restore.rpc()
		return
	for d in get_tree().get_nodes_in_group("player"):
		if not d.is_dead and _on_bridge(d.global_position):
			_collapse.rpc()
			return


@rpc("authority", "call_local", "reliable")
func _collapse() -> void:
	broken = true
	_timer = respawn_time
	_col.set_deferred("disabled", true)
	_mesh.visible = false
	_puff.restart()
	_chunks.restart()
	var me = Network.local_player
	if me and to_local(me.global_position).length() < _len:
		me.add_shake(0.3)


@rpc("authority", "call_local", "reliable")
func _restore() -> void:
	broken = false
	_col.disabled = false
	_mesh.visible = true
