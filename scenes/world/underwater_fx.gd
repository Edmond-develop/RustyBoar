extends Node3D
## Вид из-под воды (только для своей камеры, у каждого игрока свой).
##
## Когда камера уходит под воду (или в щель подо льдом):
##  * камера получает своё «окружение» с густым туманом — видно метров на 5–7,
##    чем глубже, тем темнее вода;
##  * поверх экрана — лёгкое дрожание, сине-зелёный оттенок и тёмные края;
##  * вокруг плавает муть (мелкие частицы);
##  * под каждой полыньёй висят столбы света — их видно сквозь муть издалека,
##    по ним подо льдом можно найти выход.

const SHAFT_SHADER := preload("res://shaders/light_shaft.gdshader")
const SCREEN_SHADER := preload("res://shaders/underwater_screen.gdshader")
const SHAFT_RANGE := 34.0     ## На каком расстоянии от камеры рисуем столбы света
const SHAFT_STEP := 2.2       ## Шаг сетки столбов внутри полыньи
const SHAFT_MAX := 320

const SHALLOW_FOG := Color(0.17, 0.38, 0.42)
const DEEP_FOG := Color(0.015, 0.06, 0.085)

var _lake: Node
var _cam: Camera3D
var _cam_old_env: Environment
var _uw_env: Environment
var _under := false
var _layer: CanvasLayer
var _overlay: ColorRect
var _screen_mat: ShaderMaterial
var _silt: GPUParticles3D
var _mm: MultiMesh
var _mm_instance: MultiMeshInstance3D
var _shaft_timer := 0.0
var _shaft_center := Vector3.INF

## Насколько глубоко камера (0 — у поверхности, 1 — у самого дна). Читает дрон для HUD.
var depth01 := 0.0
var hurt := 0.0


func _ready() -> void:
	_lake = get_parent()

	_layer = CanvasLayer.new()
	_layer.layer = 0          # под интерфейсом
	add_child(_layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_mat = ShaderMaterial.new()
	_screen_mat.shader = SCREEN_SHADER
	_overlay.material = _screen_mat
	_overlay.visible = false
	_layer.add_child(_overlay)

	_silt = FX.particles(Color(0.75, 0.88, 0.85, 0.45), 220, 7.0, 0.018, 0.02, 0.12, Vector3(0, -0.04, 0), 180.0, false)
	FX.set_box(_silt, Vector3(5.0, 3.0, 5.0))
	_silt.top_level = true
	_silt.visible = false
	add_child(_silt)

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = _make_shaft_mesh()
	_mm.instance_count = SHAFT_MAX
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-400, -60, -100), Vector3(800, 120, 800))
	mmi.top_level = true
	add_child(mmi)
	_mm_instance = mmi
	mmi.visible = false


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if cam != _cam:
		_set_under(false)
		_cam = cam
	var p := cam.global_position
	var under := is_underwater(p)
	if under != _under:
		_set_under(under)
	if not _under:
		return

	var depth := maxf(_lake.water_y(p.z) - p.y, 0.0)
	depth01 = clampf(depth / IceRiver.DEPTH_MAX, 0.0, 1.0)
	var fog := SHALLOW_FOG.lerp(DEEP_FOG, pow(depth01, 0.7))
	# Солнце сквозь лёд почти не пробивается: подо льдом темно, в полынье светлее
	var light := lerpf(0.85, 0.45, depth01)
	if not _lake.is_hole(p.x, p.z):
		fog = fog.darkened(0.25)
		light *= 0.8
	var k := clampf(delta * 3.0, 0.0, 1.0)
	_uw_env.fog_light_color = _uw_env.fog_light_color.lerp(fog, k)
	_uw_env.adjustment_brightness = lerpf(_uw_env.adjustment_brightness, light, k)
	_uw_env.background_color = _uw_env.fog_light_color
	_screen_mat.set_shader_parameter("depth01", depth01)
	hurt = move_toward(hurt, 0.0, delta * 1.5)
	_screen_mat.set_shader_parameter("hurt", hurt)
	_silt.global_position = p

	_shaft_timer -= delta
	if _shaft_timer <= 0.0 and (_shaft_center == Vector3.INF or _shaft_center.distance_to(p) > 1.5):
		_shaft_timer = 0.3
		_shaft_center = p
		_update_shafts(p)


## Камера под водой: ниже поверхности воды или в щели между водой и льдом (не в полынье)
func is_underwater(p: Vector3) -> bool:
	if not _lake.in_bounds(p):
		return false
	if p.y < _lake.water_y(p.z):
		return true
	return p.y < IceRiver.river_y(p.z) + 0.05 and not _lake.is_hole(p.x, p.z)


func _set_under(on: bool) -> void:
	_under = on
	_overlay.visible = on
	_silt.visible = on
	_silt.emitting = on
	_mm_instance.visible = on
	_shaft_center = Vector3.INF
	if _cam == null or not is_instance_valid(_cam):
		return
	if on:
		_cam_old_env = _cam.environment
		if _uw_env == null:
			_uw_env = _make_env()
		_uw_env.fog_light_color = SHALLOW_FOG
		_cam.environment = _uw_env
	else:
		if _cam.environment == _uw_env:
			_cam.environment = _cam_old_env
		depth01 = 0.0


func _make_env() -> Environment:
	var base: Environment = null
	var found := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if not found.is_empty():
		base = (found[0] as WorldEnvironment).environment
	var env: Environment = base.duplicate() if base else Environment.new()
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 0.6
	env.fog_depth_end = 7.5
	env.fog_depth_curve = 1.6
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_sky_affect = 1.0
	env.fog_aerial_perspective = 0.0
	env.fog_density = 0.97   # в режиме DEPTH это предельная густота тумана
	env.volumetric_fog_enabled = false
	env.glow_intensity = 0.6
	env.ssao_enabled = false
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.8
	env.adjustment_saturation = 0.8
	env.adjustment_contrast = 1.05
	return env


## Столбы света под полыньями рядом с камерой
func _update_shafts(cam_pos: Vector3) -> void:
	# сначала отбираем полыньи поблизости — дальше проверяем только их
	var near_c: Array[Vector3] = []
	for c in _lake.circles:
		if Vector2(c.x - cam_pos.x, c.y - cam_pos.z).length() < SHAFT_RANGE + c.z:
			near_c.append(c)
	var near_r: Array[Vector4] = []
	for r in _lake.rects:
		if cam_pos.x > r.x - SHAFT_RANGE and cam_pos.x < r.y + SHAFT_RANGE \
				and cam_pos.z > r.z - SHAFT_RANGE and cam_pos.z < r.w + SHAFT_RANGE:
			near_r.append(r)
	var n := 0
	if not near_c.is_empty() or not near_r.is_empty():
		var g0 := Vector2i(floori((cam_pos.x - SHAFT_RANGE) / SHAFT_STEP), floori((cam_pos.z - SHAFT_RANGE) / SHAFT_STEP))
		var g1 := Vector2i(floori((cam_pos.x + SHAFT_RANGE) / SHAFT_STEP), floori((cam_pos.z + SHAFT_RANGE) / SHAFT_STEP))
		for gz in range(g0.y, g1.y + 1):
			for gx in range(g0.x, g1.x + 1):
				if n >= SHAFT_MAX:
					break
				# случайный, но постоянный сдвиг для каждой клетки сетки
				var h := _hash(gx, gz)
				var x := (gx + 0.2 + 0.6 * h.x) * SHAFT_STEP
				var z := (gz + 0.2 + 0.6 * h.y) * SHAFT_STEP
				if Vector2(x - cam_pos.x, z - cam_pos.z).length() > SHAFT_RANGE:
					continue
				if not _inside(x, z, near_c, near_r):
					continue
				var top: float = _lake.water_y(z)
				var height := minf(IceRiver.lake_depth(x, z), 9.0) * (0.75 + 0.25 * h.z)
				var width := SHAFT_STEP * (0.9 + 0.7 * h.z)
				var b := Basis.from_scale(Vector3(width, height, 1.0))
				_mm.set_instance_transform(n, Transform3D(b, Vector3(x, top, z)))
				_mm.set_instance_color(n, Color(h.x, h.y, 1.0, 0.55 + 0.45 * h.z))
				n += 1
	_mm.visible_instance_count = n


func _inside(x: float, z: float, near_c: Array[Vector3], near_r: Array[Vector4]) -> bool:
	for c in near_c:
		if Vector2(x - c.x, z - c.y).length() < c.z - 0.5:
			return true
	for r in near_r:
		if x > r.x + 0.5 and x < r.y - 0.5 and z > r.z + 0.5 and z < r.w - 0.5:
			return true
	return false


func _hash(x: int, z: int) -> Vector3:
	var hv := absi((x * 73856093) ^ (z * 19349663))
	return Vector3(float(hv % 1000) / 1000.0, float((hv / 1000) % 1000) / 1000.0, float((hv / 1000000) % 1000) / 1000.0)


## Столб света: вертикальная полоса от поверхности вниз (x -0.5..0.5, y 0..-1).
## Шейдер разворачивает её к камере.
func _make_shaft_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(-0.5, -1, 0),
		Vector3(0.5, 0, 0), Vector3(0.5, -1, 0), Vector3(-0.5, -1, 0)])
	var uvs := PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(0, 1),
		Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = SHAFT_SHADER
	mat.render_priority = 4
	mesh.surface_set_material(0, mat)
	return mesh
