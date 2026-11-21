extends "res://scenes/world/snow_waste.gd"
## Шаг 73: «строитель» для Пика — те же помощники, что у Снежной пустоши (box/cyl/beam/sph/solid_box/rock,
## материалы, склейка мешей по кускам), но без самой пустоши. Им строятся большой лагерь у подножия
## (camp_cabin/peak_lodge), приюты, станции канатки, мост, лебёдка.


func _ready() -> void:
	_ter = get_tree().get_first_node_in_group("terrain")
	_rng.seed = 73073
	_solids = StaticBody3D.new()
	_solids.name = "PeakSolids"
	add_child(_solids)
	_shelter_body = StaticBody3D.new()
	_shelter_body.name = "PeakShelters"
	_shelter_body.add_to_group("wind_shelter")
	add_child(_shelter_body)
	var rk = ROCKS.new(self)
	rk._make_meshes()
	_rock_meshes = rk._meshes


## Шаг 74: дополнительные материалы для механизмов
const EXTRA := {
	"concrete": [Color(0.55, 0.55, 0.53), 0.95, 0.0], "drv_green": [Color(0.2, 0.34, 0.27), 0.55, 0.35],
	"paint_red": [Color(0.78, 0.15, 0.1), 0.45, 0.3], "cable": [Color(0.26, 0.26, 0.28), 0.5, 0.7],
	"brass": [Color(0.78, 0.6, 0.28), 0.3, 0.9], "copper": [Color(0.72, 0.42, 0.25), 0.35, 0.85],
	"pipe": [Color(0.32, 0.3, 0.28), 0.55, 0.75], "steel": [Color(0.62, 0.64, 0.68), 0.32, 0.85],
	"slab": [Color(0.47, 0.46, 0.45), 0.92, 0.0], "boiler": [Color(0.16, 0.16, 0.17), 0.5, 0.7],
	"chain": [Color(0.3, 0.3, 0.31), 0.45, 0.8], "w_white": [Color(0.92, 0.9, 0.84), 0.6, 0.0],
}
const CELL := 64.0


func mat(key: String) -> Material:
	if EXTRA.has(key) and not _mats.has(key):
		var e: Array = EXTRA[key]
		var m := StandardMaterial3D.new()
		m.albedo_color = e[0]
		m.roughness = e[1]
		m.metallic = e[2]
		_mats[key] = m
	return super.mat(key)


## Шаг 74: куски по клеткам 64 м и по размеру предмета — мелочь не рисуется издалека,
## что за камерой — не рисуется вовсе (раньше всё было одним мешем на материал на всю гору)
func put(mesh: Mesh, xf: Transform3D, key: String) -> void:
	var ab := xf * mesh.get_aabb()
	var sz := maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
	var cls := 0 if sz < 0.8 else (1 if sz < 4.0 else 2)
	var o := ab.get_center()
	var k := "%s#%d_%d_%d" % [key, floori(o.x / CELL), floori(o.z / CELL), cls]
	if not _st.has(k):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[k] = st
	(_st[k] as SurfaceTool).append_from(mesh, 0, xf)


## Склеить всё построенное в меши (звать после постройки)
func flush() -> void:
	for k: String in _st:
		var key := k.get_slice("#", 0)
		var cls := int(k.get_slice("_", k.get_slice_count("_") - 1))
		var mesh := (_st[k] as SurfaceTool).commit()
		var mi := MeshInstance3D.new()
		mi.name = "W_" + k.replace("#", "_")
		mi.mesh = mesh
		mi.material_override = mat(key)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = [70.0, 220.0, 700.0][cls]
		mi.visibility_range_end_margin = mi.visibility_range_end * 0.1
		add_child(mi)
	_st.clear()


## Глыба только для вида (без коллизии)
func rock_vis(pos: Vector3, size: Vector3, yaw: float, key: String, lod := 0) -> void:
	var vi := _rng.randi_range(0, 1)
	var b := Basis(Vector3.UP, yaw)
	b = Basis(b.x * size.x, b.y * size.y, b.z * size.z)
	put(_rock_meshes[vi * 2 + lod], Transform3D(b, pos), key)
