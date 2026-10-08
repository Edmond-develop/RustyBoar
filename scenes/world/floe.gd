extends AnimatableBody3D
## Дрейфующая льдина неровной формы. Плывёт по разводью туда-обратно,
## покачивается на воде и кренится под весом стоящих на ней дронов.
## Время общее для всех игроков — льдины у всех в одном месте.

@export var from_x := -11.0
@export var to_x := 11.0
@export var period := 9.0
@export_range(0.0, 1.0) var phase := 0.0
@export var radius := 1.8
@export var seed_value := 1

const THICK := 0.4

var _base := Vector3.ZERO
var _local_t := 0.0
var _tilt := Vector2.ZERO
var _sink := 0.0

static var _ice_mat: StandardMaterial3D
static var _snow_mat: StandardMaterial3D


func _ready() -> void:
	_base = position
	if _ice_mat == null:
		_ice_mat = StandardMaterial3D.new()
		_ice_mat.albedo_color = Color(0.72, 0.88, 0.98)
		_ice_mat.roughness = 0.12
		_ice_mat.clearcoat_enabled = true
		_ice_mat.rim_enabled = true
		_ice_mat.rim = 0.5
		_snow_mat = StandardMaterial3D.new()
		_snow_mat.albedo_color = Color(0.95, 0.97, 1.0)
		_snow_mat.roughness = 0.9
		_ice_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_snow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var slippery := PhysicsMaterial.new()
	slippery.friction = 0.15
	physics_material_override = slippery

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var outline := PackedVector2Array()
	var n := rng.randi_range(7, 10)
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.2, 0.2)
		var r := radius * rng.randf_range(0.75, 1.15)
		outline.append(Vector2(cos(a) * r * 1.15, sin(a) * r * 0.85))

	var ice := _extrude(outline, THICK)
	ice.surface_set_material(0, _ice_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = ice
	add_child(mi)

	# Снежный нанос сверху (меньший контур)
	var snow_outline := PackedVector2Array()
	var off := Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.3, 0.3))
	for p in outline:
		snow_outline.append(p * rng.randf_range(0.45, 0.65) + off)
	var snow := _extrude(snow_outline, 0.06)
	snow.surface_set_material(0, _snow_mat)
	var smi := MeshInstance3D.new()
	smi.mesh = snow
	smi.position.y = THICK * 0.5 + 0.03
	add_child(smi)

	var points := PackedVector3Array()
	for p in outline:
		points.append(Vector3(p.x, THICK * 0.5, p.y))
		points.append(Vector3(p.x * 0.92, -THICK * 0.5, p.y * 0.92))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


func _physics_process(delta: float) -> void:
	_local_t += delta
	var t: float = Network.game_time if Network.in_game else _local_t
	var k := 0.5 - 0.5 * cos((t / period + phase) * TAU)

	# Кто стоит на льдине — туда она и кренится
	var target_tilt := Vector2.ZERO
	var target_sink := 0.0
	for d in get_tree().get_nodes_in_group("player"):
		var rel: Vector3 = d.global_position - global_position
		if absf(rel.y) < 1.0 and Vector2(rel.x, rel.z).length() < radius * 1.1 and d.is_grounded():
			target_tilt += Vector2(rel.x, rel.z) / radius
			target_sink += 0.08
	_tilt = _tilt.lerp(target_tilt.limit_length(1.0), 4.0 * delta)
	_sink = lerpf(_sink, minf(target_sink, 0.2), 4.0 * delta)

	var bob := sin(t * 1.3 + phase * 6.0) * 0.04
	position = Vector3(lerpf(from_x, to_x, k), _base.y - THICK * 0.5 + bob - _sink, _base.z)
	rotation = Vector3(
		_tilt.y * 0.12 + sin(t * 0.9 + phase * 3.0) * 0.02,
		sin(t * 0.3 + phase * 4.0) * 0.4,
		-_tilt.x * 0.12 + cos(t * 1.1 + phase * 5.0) * 0.02)


## Плоская призма по контуру (верх, низ, боковины)
func _extrude(outline: PackedVector2Array, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := outline.size()
	var top := thick * 0.5
	var bottom := -thick * 0.5
	var center := Vector2.ZERO
	for p in outline:
		center += p
	center /= n
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		# верх
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(center.x, top, center.y))
		st.add_vertex(Vector3(b.x, top, b.y))
		st.add_vertex(Vector3(a.x, top, a.y))
		# бок
		var side := Vector3(b.y - a.y, 0.0, -(b.x - a.x)).normalized()
		st.set_normal(-side)
		st.add_vertex(Vector3(a.x, top, a.y))
		st.add_vertex(Vector3(b.x, top, b.y))
		st.add_vertex(Vector3(a.x * 0.92, bottom, a.y * 0.92))
		st.add_vertex(Vector3(b.x, top, b.y))
		st.add_vertex(Vector3(b.x * 0.92, bottom, b.y * 0.92))
		st.add_vertex(Vector3(a.x * 0.92, bottom, a.y * 0.92))
	return st.commit()
