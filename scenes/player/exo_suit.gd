extends Node3D
## Полярный экзоскафандр курьера — модель, походка, руки и следы повреждений.
##
## Модель собрана из простых форм прямо в коде (без внешних файлов):
##  * купол-шлем с широким визором, на визоре — «цифровые глаза» цвета игрока;
##  * массивные наплечники на клёпках, нагрудник, гофрированный пояс;
##  * за спиной котёл: манометр (стрелка = выносливость), две трубы и два сопла;
##  * трёхпалые перчатки, гидравлика под коленями, тяжёлые ботинки с пяточными
##    реактивными соплами (на бегу пыхают при каждом толчке).
##
## Анимация процедурная (считается каждый кадр, у всех игроков одинаково):
##  * ноги шагают по фазе: опорная стоит на земле, переносимая идёт по дуге;
##    на бегу — длинные пружинистые прыжки с фазой полёта;
##  * колени и локти сгибаются сами (обратная кинематика по двум звеньям);
##  * корпус «пружинит» (пружина с перелётом), руки болтаются по инерции;
##  * держит посылку ладонями за бока, тяжёлый ящик — за ручку, клюшку — двумя руками;
##  * особые позы: прыжок, падение, плавание, устал (руки на коленях), ветер
##    (закрывается рукой), каток, скольжение, удар, бросок, поломка (на колени).
##
## Следы на броне: ожоги лучом, вмятины и царапины, пробоины, ожоги паром;
## копятся до поломки. При малом здоровье — искры, дым, хромота, болтается
## наплечник, визор трескается и мигает.

const ARMOR_SHADER := preload("res://shaders/exo_armor.gdshader")
const VISOR_SHADER := preload("res://shaders/exo_visor.gdshader")

enum Mark { BURN, DENT, PIERCE, SCALD }
enum Mood { NORMAL, HAPPY, HURT, TIRED, OFF }

const HIP_H := 0.91           ## Высота таза стоя (колени чуть согнуты — пружинистая стойка)
const HIP_X := 0.13           ## Ноги от центра
const THIGH := 0.41
const SHIN := 0.4
const ANKLE_H := 0.11         ## Щиколотка над подошвой
const SHOULDER := Vector3(0.36, 0.40, 0.0)   ## Плечо (от пояса)
const UPPER := 0.3
const FORE := 0.29
const HAND := 0.09            ## От запястья до середины ладони
const HOLD_LOCAL := Vector3(0.0, 0.22, -0.48)   ## Где посылка (от пояса)
const MAX_SPOTS := 8

var color := Color(0.86, 0.45, 0.17)
var torso: Node3D                     ## пояс и всё, что выше (у игрока это $Visual/Body)
var pelvis: Node3D
var neck: Node3D
var head: Node3D
var pack: Node3D
var nozzle_glows: Array[MeshInstance3D] = []
var flames: Array[MeshInstance3D] = []
var thruster_light: OmniLight3D
var trail_mount: Node3D               ## сюда игрок переносит шлейф бега
var steam_mount: Node3D               ## …и пар
var icicle_mounts: Array = []         ## [узел, точка, длина]
var no_frost: Array[Node] = []        ## на эти детали иней не ложится (огоньки)
var knees: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]

var _vis: Node3D
var _legs: Array = []                 ## {thigh, shin, boot, rod, housing, heel, puff}
var _arms: Array = []                 ## {upper, fore, hand, f1, f2, th, pauldron}
var _visor_mat: ShaderMaterial
var _console_mat: StandardMaterial3D
var _antenna_mat: StandardMaterial3D
var _ear_mat: StandardMaterial3D
var _needle: Node3D
var _pieces: Array = []               ## {mesh, mat, pos, info, n, hot}
var _mats: Array[ShaderMaterial] = []
var _sparks: GPUParticles3D
var _smoke: GPUParticles3D

# состояние анимации
var _t := 0.0
var _phase := 0.0
var _amp := 0.0
var _move_dir := Vector3.FORWARD
var _feet: Array[Vector3] = [Vector3(-0.15, 0, 0), Vector3(0.15, 0, 0)]
var _pitch: Array[float] = [0.0, 0.0]
var _gnd: Array[float] = [0.0, 0.0]
var _stance: Array[bool] = [true, true]
var _puff: Array[float] = [0.0, 0.0]
var _bob := 0.0
var _bob_v := 0.0
var _lean := 0.0
var _lean_v := 0.0
var _roll := 0.0
var _twist := 0.0
var _hand_p: Array[Vector3] = [Vector3(-0.44, -0.15, 0.0), Vector3(0.44, -0.15, 0.0)]
var _hand_v: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _hold_w: Array[float] = [0.0, 0.0]
var _curl: Array[float] = [0.3, 0.3]
var _last_yaw := 0.0
var _yaw_rate := 0.0
var _last_lv := Vector3.ZERO
var _acc := Vector3.ZERO
var _turn_phase := 0.0
var _skate := 0.0
var _swim := 0.0
var _head_yaw := 0.0
var _head_pitch := 0.0
var _glance := 0.0
var _glance_t := 2.0
var _flex_t := 4.0
var _flex := 0.0
var _blink_t := 2.0
var _blink := 0.0
var _mood := Mood.NORMAL
var _mood_t := 0.0
var _punch_t := 0.0
var _throw_t := 0.0
var _reach_t := 0.0
var _hang := 0.0
var _hang_v := 0.0
var _spark_t := 1.0
var _visor_dmg := 0.0
var _snow := 0.0
var _wet := 0.0
var _wear := 0.0
var _mat_t := 0.0
var _heat_t := 0.0
var _carry_sway := Basis.IDENTITY
var _skid_t := 0.0
var _land_t := 0.0
var _prev_spd := 0.0
var _was_lifting := false
var _fidget := ""
var _fidget_t := 0.0
var _fidget_len := 1.0
var _idle_clock := 0.0
var _next_fidget := 6.0
# детали
var _hose: Array[MeshInstance3D] = []
var _leds: Array[StandardMaterial3D] = []
var _lamp_light: SpotLight3D
var _number: Label3D
var _coil_hand: Node3D
var _coil_belt: Node3D


# ---------------------------------------------------------------------------
#  Постройка модели
# ---------------------------------------------------------------------------

## body — узел, который станет поясом/торсом (у игрока $Visual/Body)
func build(body: Node3D, player_color: Color) -> void:
	color = player_color
	_vis = get_parent() as Node3D
	torso = body
	torso.position = Vector3(0.0, HIP_H + 0.02, 0.0)
	pelvis = Node3D.new()
	pelvis.name = "Pelvis"
	add_child(pelvis)
	pelvis.position.y = HIP_H
	_build_pelvis()
	_build_torso()
	_build_head()
	_build_pack()
	for i in 2:
		_build_arm(i)
		_build_leg(i)
	_build_fx()
	_build_details()


func _armor(kind: String, markable := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ARMOR_SHADER
	match kind:
		"paint":
			m.set_shader_parameter("base_color", color)
			m.set_shader_parameter("metal", 0.45)
			m.set_shader_parameter("rough", 0.42)
			m.set_shader_parameter("paint", 1.0)
		"steel":
			m.set_shader_parameter("base_color", Color(0.36, 0.37, 0.4))
			m.set_shader_parameter("metal", 0.85)
			m.set_shader_parameter("rough", 0.36)
			m.set_shader_parameter("paint", 0.0)
		"light":
			m.set_shader_parameter("base_color", Color(0.72, 0.72, 0.68))
			m.set_shader_parameter("metal", 0.6)
			m.set_shader_parameter("rough", 0.4)
			m.set_shader_parameter("paint", 1.0)
		"rubber":
			m.set_shader_parameter("base_color", Color(0.09, 0.09, 0.1))
			m.set_shader_parameter("metal", 0.0)
			m.set_shader_parameter("rough", 0.85)
			m.set_shader_parameter("paint", 0.0)
	m.set_shader_parameter("spot_count", 0)
	_mats.append(m)
	return m


func _plain(c: Color, metal := 0.9, rough := 0.3, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


## Деталь брони. markable — на ней остаются следы (у каждой свой материал).
func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO,
		scl := Vector3.ONE, markable := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	if markable and mat is ShaderMaterial:
		_pieces.append({"mesh": mi, "mat": mat, "pos": PackedVector4Array(), "info": PackedVector4Array(), "hot": false})
		var pc: Dictionary = _pieces.back()
		pc["pos"].resize(MAX_SPOTS)
		pc["info"].resize(MAX_SPOTS)
		pc["n"] = 0
	return mi


static func _sphere(r: float, h := -1.0, seg := 24) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h if h > 0.0 else r * 2.0
	s.radial_segments = seg
	s.rings = maxi(seg / 2, 6)
	return s


static func _cyl(top: float, bottom: float, h: float, seg := 18) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _torus(inner: float, outer: float, seg := 24) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = seg
	t.ring_segments = 8
	return t


func _rivets(parent: Node3D, center: Vector3, radius: float, count: int, axis_y := true, phase := 0.0) -> void:
	var brass := _plain(Color(0.7, 0.55, 0.28), 0.9, 0.3)
	var m := _sphere(0.014, -1.0, 8)
	for k in count:
		var a := TAU * k / count + phase
		var off := Vector3(cos(a) * radius, 0.0, sin(a) * radius) if axis_y else Vector3(cos(a) * radius, sin(a) * radius, 0.0)
		_part(parent, m, brass, center + off)


func _build_pelvis() -> void:
	_part(pelvis, _sphere(0.19, 0.24), _armor("steel"), Vector3(0, -0.03, 0), Vector3.ZERO, Vector3(1.12, 1.0, 0.86), true)
	_part(pelvis, _torus(0.17, 0.21), _armor("steel"), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1.1, 1.0, 0.85))
	# подсумки на поясе
	for s in [-1.0, 1.0]:
		_part(pelvis, _box(Vector3(0.07, 0.09, 0.11)), _armor("steel", false), Vector3(s * 0.2, -0.02, 0.06), Vector3(0, 0, s * 0.15))


func _build_torso() -> void:
	# гофрированный пояс (живот)
	_part(torso, _cyl(0.14, 0.14, 0.16), _armor("steel"), Vector3(0, 0.06, 0))
	for k in 3:
		_part(torso, _cyl(0.165, 0.165, 0.035), _armor("rubber"), Vector3(0, 0.0 + k * 0.05, 0), Vector3.ZERO, Vector3(1.05, 1.0, 0.92))
	# грудь
	_part(torso, _sphere(0.28), _armor("paint"), Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1.18, 0.8, 0.86), true)
	# нагрудная пластина из светлого металла на клёпках
	var plate := _part(torso, _sphere(0.2), _armor("steel"), Vector3(0, 0.33, -0.19), Vector3.ZERO, Vector3(1.0, 0.62, 0.3), true)
	for p in [Vector3(-0.13, 0.4, -0.235), Vector3(0.13, 0.4, -0.235), Vector3(-0.13, 0.26, -0.235), Vector3(0.13, 0.26, -0.235)]:
		_part(torso, _sphere(0.016, -1.0, 8), _plain(Color(0.7, 0.55, 0.28)), p)
	plate.name = "Breastplate"
	# опоясывающий обруч
	_part(torso, _torus(0.275, 0.305), _armor("steel"), Vector3(0, 0.17, 0), Vector3.ZERO, Vector3(1.17, 1.0, 0.86))
	# воротник
	_part(torso, _torus(0.1, 0.17), _armor("steel"), Vector3(0, 0.5, 0))
	# наплечники
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var pv := Node3D.new()
		pv.name = "Pauldron%d" % i
		pv.position = Vector3(s * 0.33, 0.47, 0.0)
		torso.add_child(pv)
		_part(pv, _sphere(0.16, 0.2), _armor("paint"), Vector3(s * 0.04, 0.0, 0), Vector3(0, 0, -s * 0.28), Vector3(1.0, 1.0, 1.05), true)
		_part(pv, _torus(0.135, 0.165), _armor("steel"), Vector3(s * 0.04, -0.03, 0), Vector3(0, 0, -s * 0.28), Vector3(1.0, 1.0, 1.05))
		_rivets(pv, Vector3(s * 0.04, -0.01, 0), 0.15, 6, true, 0.3)
		_part(torso, _sphere(0.085), _armor("steel"), SHOULDER * Vector3(s, 1, 1))
		icicle_mounts.append([pv, Vector3(s * 0.12, -0.06, -0.06), 0.8])
		icicle_mounts.append([pv, Vector3(s * 0.15, -0.06, 0.07), 0.7])
	for k in 8:
		var a := TAU * k / 8.0 + 0.2
		icicle_mounts.append([torso, Vector3(cos(a) * 0.3, 0.13, sin(a) * 0.23), 1.0])


func _build_head() -> void:
	neck = Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0, 0.49, 0)
	torso.add_child(neck)
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.13, 0)
	neck.add_child(head)
	_part(head, _sphere(0.19, -1.0, 32), _armor("paint"), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, true)
	_visor_mat = ShaderMaterial.new()
	_visor_mat.shader = VISOR_SHADER
	_visor_mat.set_shader_parameter("radius", 0.197)
	_visor_mat.set_shader_parameter("eye_color", color.lightened(0.45))
	_part(head, _sphere(0.197, -1.0, 40), _visor_mat, Vector3.ZERO)
	# гребень-обруч через макушку
	_part(head, _torus(0.188, 0.212, 32), _armor("steel"), Vector3(0, 0, 0.0), Vector3(0, 0, PI * 0.5))
	# «челюсть»
	_part(head, _sphere(0.14, 0.13), _armor("steel"), Vector3(0, -0.13, -0.025), Vector3.ZERO, Vector3(1.05, 1.0, 1.0), true)
	for g in 3:
		_part(head, _box(Vector3(0.012, 0.035, 0.02)), _plain(Color(0.05, 0.05, 0.06), 0.3, 0.6), Vector3(-0.04 + g * 0.04, -0.15, -0.155))
	# «уши» с огоньками
	_ear_mat = _plain(color.lightened(0.4), 0.0, 0.3, 3.0)
	for s in [-1.0, 1.0]:
		_part(head, _cyl(0.058, 0.058, 0.06), _armor("steel"), Vector3(s * 0.185, -0.01, 0.02), Vector3(0, 0, PI * 0.5))
		var lamp := _part(head, _sphere(0.022, -1.0, 10), _ear_mat, Vector3(s * 0.218, -0.01, 0.02))
		no_frost.append(lamp)
	# антенна с мигающим огоньком
	_antenna_mat = _plain(Color(1.0, 0.25, 0.2), 0.0, 0.3, 3.0)
	_part(head, _cyl(0.007, 0.01, 0.24, 6), _armor("steel"), Vector3(-0.2, 0.11, 0.06), Vector3(-0.25, 0, 0.12))
	var tip := _part(head, _sphere(0.02, -1.0, 10), _antenna_mat, Vector3(-0.215, 0.23, 0.09))
	no_frost.append(tip)
	icicle_mounts.append([head, Vector3(0.07, -0.17, -0.1), 0.5])
	icicle_mounts.append([head, Vector3(-0.08, -0.16, -0.09), 0.45])


func _build_pack() -> void:
	pack = Node3D.new()
	pack.name = "Pack"
	pack.position = Vector3(0, 0.3, 0.26)
	torso.add_child(pack)
	_part(pack, _cyl(0.15, 0.15, 0.42, 24), _armor("steel"), Vector3.ZERO, Vector3.ZERO, Vector3(1.15, 1.0, 0.85), true)
	_part(pack, _sphere(0.15, 0.12), _armor("steel"), Vector3(0, 0.21, 0), Vector3.ZERO, Vector3(1.15, 1.0, 0.85))
	for y in [-0.12, 0.12]:
		_part(pack, _torus(0.145, 0.17), _armor("paint"), Vector3(0, y, 0), Vector3.ZERO, Vector3(1.15, 1.0, 0.85))
	# трубы
	for s in [-1.0, 1.0]:
		_part(pack, _cyl(0.026, 0.03, 0.14, 10), _armor("steel"), Vector3(s * 0.08, 0.27, -0.02))
		_part(pack, _torus(0.022, 0.036, 10), _plain(Color(0.7, 0.55, 0.28)), Vector3(s * 0.08, 0.34, -0.02))
	steam_mount = Node3D.new()
	steam_mount.position = Vector3(0, 0.36, -0.02)
	pack.add_child(steam_mount)
	# манометр (стрелка — выносливость)
	_part(pack, _cyl(0.058, 0.058, 0.03, 20), _plain(Color(0.7, 0.55, 0.28)), Vector3(0, 0.06, 0.135), Vector3(PI * 0.5, 0, 0))
	var face := _part(pack, _cyl(0.047, 0.047, 0.006, 20), _plain(Color(0.92, 0.9, 0.82), 0.0, 0.6, 0.25), Vector3(0, 0.06, 0.152), Vector3(PI * 0.5, 0, 0))
	no_frost.append(face)
	_needle = Node3D.new()
	_needle.position = Vector3(0, 0.06, 0.157)
	pack.add_child(_needle)
	_part(_needle, _box(Vector3(0.007, 0.04, 0.004)), _plain(Color(0.8, 0.1, 0.08), 0.0, 0.5), Vector3(0, 0.017, 0))
	# сопла
	var glow_mat := _plain(Color(1.0, 0.6, 0.2), 0.0, 0.5, 6.0)
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.55, 0.15, 0.7)
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for s in [-1.0, 1.0]:
		_part(pack, _cyl(0.042, 0.066, 0.11, 14), _armor("steel"), Vector3(s * 0.085, -0.265, 0.02))
		var g := _part(pack, _sphere(0.045, -1.0, 10), glow_mat, Vector3(s * 0.085, -0.33, 0.02))
		nozzle_glows.append(g)
		no_frost.append(g)
		var fl := _part(pack, _cyl(0.045, 0.0, 1.0, 10), flame_mat, Vector3(s * 0.085, -0.33, 0.02))
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fl.visible = false
		flames.append(fl)
		no_frost.append(fl)
		icicle_mounts.append([pack, Vector3(s * 0.13, -0.2, 0.06), 0.8])
	thruster_light = OmniLight3D.new()
	thruster_light.light_color = Color(1.0, 0.6, 0.25)
	thruster_light.omni_range = 2.5
	thruster_light.position = Vector3(0, -0.45, 0.02)
	pack.add_child(thruster_light)
	trail_mount = Node3D.new()
	trail_mount.position = Vector3(0, -0.34, 0.03)
	pack.add_child(trail_mount)


func _build_arm(i: int) -> void:
	var s := -1.0 if i == 0 else 1.0
	var upper := Node3D.new()
	upper.name = "UpperArm%d" % i
	add_child(upper)
	_part(upper, _cyl(0.05, 0.048, UPPER, 12), _armor("steel"), Vector3(0, -UPPER * 0.5, 0))
	_part(upper, _cyl(0.08, 0.07, 0.18), _armor("steel"), Vector3(0, -0.13, 0), Vector3.ZERO, Vector3.ONE, true)
	_part(upper, _sphere(0.062), _armor("steel"), Vector3(0, -UPPER, 0))
	var fore := Node3D.new()
	fore.name = "Forearm%d" % i
	add_child(fore)
	_part(fore, _cyl(0.074, 0.09, 0.21), _armor("paint"), Vector3(0, -0.125, 0), Vector3.ZERO, Vector3.ONE, true)
	_part(fore, _torus(0.07, 0.097), _armor("steel"), Vector3(0, -0.245, 0))
	_part(fore, _cyl(0.05, 0.05, 0.06, 10), _armor("steel"), Vector3(0, -0.02, 0))
	if i == 0:
		# наручный экран: цвет — здоровье
		_part(fore, _box(Vector3(0.03, 0.1, 0.07)), _armor("steel"), Vector3(s * 0.088, -0.13, 0.0))
		_console_mat = _plain(Color(0.4, 1.0, 0.5), 0.0, 0.4, 2.5)
		var scr := _part(fore, _box(Vector3(0.006, 0.08, 0.055)), _console_mat, Vector3(s * 0.104, -0.13, 0.0))
		no_frost.append(scr)
	var hand := Node3D.new()
	hand.name = "Hand%d" % i
	add_child(hand)
	var hm := Node3D.new()          # перчатки крупные — всё внутри чуть увеличено
	hm.scale = Vector3.ONE * 1.22
	hand.add_child(hm)
	var glove := _armor("steel")
	_part(hm, _box(Vector3(0.055, 0.1, 0.105)), glove, Vector3(0, -0.05, 0), Vector3.ZERO, Vector3.ONE, true)
	_part(hm, _box(Vector3(0.02, 0.085, 0.1)), _armor("paint"), Vector3(s * 0.033, -0.05, 0))
	var f1 := _finger(hm, Vector3(0, -0.1, -0.027))
	var f2 := _finger(hm, Vector3(0, -0.1, 0.027))
	var th := Node3D.new()
	th.position = Vector3(-s * 0.02, -0.035, -0.05)
	hm.add_child(th)
	var th_root := Node3D.new()
	th_root.rotation = Vector3(0.7, 0, -s * 0.25)
	th.add_child(th_root)
	var th1 := _finger(th_root, Vector3.ZERO)
	_arms.append({"upper": upper, "fore": fore, "hand": hand, "f1": f1, "f2": f2, "th": th1, "s": s,
		"pauldron": torso.get_node("Pauldron%d" % i)})


## Палец из двух фаланг; возвращает [сустав1, сустав2]
func _finger(parent: Node3D, pos: Vector3) -> Array:
	var mat := _armor("steel", false)
	var j1 := Node3D.new()
	j1.position = pos
	parent.add_child(j1)
	_part(j1, _box(Vector3(0.042, 0.052, 0.042)), mat, Vector3(0, -0.026, 0))
	var j2 := Node3D.new()
	j2.position = Vector3(0, -0.052, 0)
	j1.add_child(j2)
	_part(j2, _box(Vector3(0.038, 0.04, 0.038)), mat, Vector3(0, -0.02, 0))
	_part(j2, _sphere(0.02, -1.0, 8), mat, Vector3(0, -0.042, 0))
	return [j1, j2]


func _build_leg(i: int) -> void:
	var s := -1.0 if i == 0 else 1.0
	var thigh := Node3D.new()
	thigh.name = "Thigh%d" % i
	add_child(thigh)
	_part(thigh, _sphere(0.072), _armor("steel"), Vector3.ZERO)
	_part(thigh, _cyl(0.055, 0.05, THIGH, 12), _armor("steel"), Vector3(0, -THIGH * 0.5, 0))
	_part(thigh, _cyl(0.1, 0.082, 0.28, 16), _armor("steel"), Vector3(0, -0.17, -0.008), Vector3.ZERO, Vector3.ONE, true)
	_part(thigh, _box(Vector3(0.11, 0.2, 0.03)), _armor("paint"), Vector3(0, -0.17, -0.095), Vector3(0.06, 0, 0), Vector3.ONE, true)
	var shin := Node3D.new()
	shin.name = "Shin%d" % i
	add_child(shin)
	_part(shin, _sphere(0.066), _armor("steel"), Vector3.ZERO)
	_part(shin, _sphere(0.08, 0.13), _armor("paint"), Vector3(0, -0.015, -0.06), Vector3.ZERO, Vector3(1.0, 1.0, 0.75), true)
	_part(shin, _cyl(0.046, 0.04, SHIN, 12), _armor("steel"), Vector3(0, -SHIN * 0.5, 0))
	_part(shin, _cyl(0.088, 0.07, 0.27, 16), _armor("paint"), Vector3(0, -0.19, -0.006), Vector3.ZERO, Vector3.ONE, true)
	_part(shin, _box(Vector3(0.085, 0.24, 0.035)), _armor("light"), Vector3(0, -0.19, -0.085), Vector3(-0.08, 0, 0), Vector3.ONE, true)
	_part(shin, _torus(0.068, 0.09), _armor("steel"), Vector3(0, -0.06, -0.006))
	# гидравлика под коленом
	var housing := _part(self, _cyl(0.03, 0.03, 0.14, 10), _armor("steel"), Vector3.ZERO)
	var rod := _part(self, _cyl(0.015, 0.015, 1.0, 8), _plain(Color(0.78, 0.62, 0.3), 0.95, 0.2), Vector3.ZERO)
	# ботинок
	var boot := Node3D.new()
	boot.name = "Boot%d" % i
	add_child(boot)
	_part(boot, _sphere(0.056), _armor("steel"), Vector3.ZERO)
	_part(boot, _cyl(0.078, 0.084, 0.08), _armor("paint"), Vector3(0, -0.015, 0.005), Vector3.ZERO, Vector3.ONE, true)
	_part(boot, _box(Vector3(0.15, 0.085, 0.27)), _armor("steel"), Vector3(0, -0.055, -0.045), Vector3.ZERO, Vector3.ONE, true)
	_part(boot, _sphere(0.085, 0.12), _armor("paint"), Vector3(0, -0.06, -0.15), Vector3.ZERO, Vector3(1.0, 1.0, 1.15), true)
	_part(boot, _box(Vector3(0.17, 0.03, 0.31)), _armor("rubber"), Vector3(0, -0.097, -0.045))
	_part(boot, _cyl(0.028, 0.036, 0.05, 10), _armor("steel"), Vector3(0, -0.05, 0.1), Vector3(PI * 0.5, 0, 0))
	var heel_mat := _plain(Color(1.0, 0.6, 0.2), 0.0, 0.5, 6.0)
	var heel := _part(boot, _sphere(0.035, -1.0, 8), heel_mat, Vector3(0, -0.05, 0.13))
	heel.visible = false
	no_frost.append(heel)
	var puff := FX.particles(Color(1.0, 0.75, 0.4, 0.8), 8, 0.25, 0.035, 1.0, 2.5, Vector3(0, 1.0, 0), 25.0, true, true)
	puff.position = Vector3(0, -0.05, 0.14)
	(puff.process_material as ParticleProcessMaterial).direction = Vector3(0, 0, 1)
	boot.add_child(puff)
	_legs.append({"thigh": thigh, "shin": shin, "boot": boot, "rod": rod, "housing": housing, "heel": heel, "puff": puff, "s": s})


func _build_fx() -> void:
	_sparks = FX.particles(Color(1.0, 0.85, 0.35), 14, 0.45, 0.022, 1.5, 4.0, Vector3(0, -9, 0), 120.0, true, true)
	_sparks.top_level = true
	add_child(_sparks)
	_smoke = FX.particles(Color(0.16, 0.16, 0.17, 0.32), 40, 1.4, 0.05, 0.5, 1.0, Vector3(0, 1.0, 0), 20.0, false)
	(_smoke.process_material as ParticleProcessMaterial).scale_max = 2.6
	((_smoke.draw_pass_1 as SphereMesh)).radial_segments = 10
	((_smoke.draw_pass_1 as SphereMesh)).rings = 6
	steam_mount.add_child(_smoke)


# ---------------------------------------------------------------------------
#  Обратная кинематика
# ---------------------------------------------------------------------------

## Базис звена: локальная −Y вдоль звена, локальная −Z — в сторону front
static func seg_basis(dir: Vector3, front: Vector3) -> Basis:
	var y := -dir.normalized()
	var z := -(front - y * front.dot(y))
	if z.length() < 0.0001:
		z = Vector3.BACK if absf(y.dot(Vector3.BACK)) < 0.9 else Vector3.RIGHT
		z = z - y * z.dot(y)
	z = z.normalized()
	var x := y.cross(z)
	return Basis(x, y, z)


## Два звена от root к target, колено/локоть — в сторону pole. Возвращает [середина, конец, в сторону колена]
static func ik2(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var d := target - root
	var len := d.length()
	var dir := d / len if len > 0.0001 else Vector3.DOWN
	var dist := clampf(len, absf(l1 - l2) + 0.02, l1 + l2 - 0.003)
	var end := root + dir * dist
	var ca := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var a := acos(ca)
	var pd := pole - root
	pd = pd - dir * pd.dot(dir)
	if pd.length() < 0.0001:
		pd = Vector3.FORWARD - dir * Vector3.FORWARD.dot(dir)
	pd = pd.normalized()
	var mid := root + (dir * cos(a) + pd * sin(a)) * l1
	return [mid, end, pd]


# ---------------------------------------------------------------------------
#  Посылка в руках
# ---------------------------------------------------------------------------

## Где держать посылку (мировые координаты), с покачиванием в такт шагам.
## weight: 1 — лёгкая (под правой рукой), 2 — обычная (перед грудью), 3 — тяжёлая (в обнимку, ниже)
func carry_transform(extra_basis: Basis, offset: Vector3, weight := 2, ext := Vector3(0.3, 0.3, 0.3)) -> Transform3D:
	var tx := torso.global_transform
	var yaw_basis := Basis(Vector3.UP, _vis.global_rotation.y)
	var loc: Vector3
	match weight:
		1:
			loc = Vector3(0.21 + ext.x, 0.06, -0.04)
		3:
			loc = Vector3(0.0, 0.02, -(0.22 + ext.z))
		_:
			loc = Vector3(0.0, HOLD_LOCAL.y, -(0.2 + ext.z))
	var b := yaw_basis * _carry_sway * extra_basis
	if weight == 1:
		b = b * Basis(Vector3.UP, 0.3)
	return Transform3D(b, tx * loc + offset)


## Середина ладони (0 — левая, 1 — правая), мировые координаты
func hand_point(i: int) -> Vector3:
	return (_arms[i]["hand"] as Node3D).global_transform * Vector3(0, -HAND, 0)


## Куда повесить моток верёвки: в левую руку или на пояс
func coil_mount(in_hand: bool) -> Node3D:
	return _coil_hand if in_hand else _coil_belt


## Номер на наплечнике
func set_number(text: String) -> void:
	if _number:
		_number.text = text


# ---------------------------------------------------------------------------
#  Следы повреждений
# ---------------------------------------------------------------------------

## Оставить след. kind — Mark, point — мировая точка, radius — размер (м).
func add_mark(kind: int, point: Vector3, radius := 0.1, strength := 1.0, heat := 0.0) -> void:
	var cands: Array = []
	for pc in _pieces:
		var mi: MeshInstance3D = pc["mesh"]
		if not mi.is_visible_in_tree():
			continue
		var inv := mi.global_transform.affine_inverse()
		var lp := inv * point
		var aabb := mi.get_aabb()
		var cl := Vector3(clampf(lp.x, aabb.position.x, aabb.end.x), clampf(lp.y, aabb.position.y, aabb.end.y), clampf(lp.z, aabb.position.z, aabb.end.z))
		var sc := mi.global_basis.get_scale()
		var k := (sc.x + sc.y + sc.z) / 3.0
		var dist := (lp - cl).length() * k
		cands.append([dist, pc, cl, k])
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var used := 0
	for c in cands:
		if used >= 2 or (used > 0 and float(c[0]) > radius * 0.6):
			break
		_spot(c[1], kind, c[2], radius / float(c[3]), strength, heat)
		used += 1


func _spot(pc: Dictionary, kind: int, lp: Vector3, r: float, strength: float, heat: float) -> void:
	var pos: PackedVector4Array = pc["pos"]
	var info: PackedVector4Array = pc["info"]
	var n: int = pc["n"]
	# рядом уже есть такой же след — он растёт
	for k in n:
		var sp := pos[k]
		var si := info[k]
		if int(si.x) == kind and Vector3(sp.x, sp.y, sp.z).distance_to(lp) < sp.w * 0.6:
			sp.w = minf(sp.w * 1.08 + r * 0.05, r * 1.8)
			si.z = minf(si.z + strength * 0.35, 1.0)
			si.y = maxf(si.y, heat)
			pos[k] = sp
			info[k] = si
			_upload(pc, pos, info, n)
			return
	var slot := n
	if n >= MAX_SPOTS:
		# места нет — заменяем самый слабый
		slot = 0
		for k in n:
			if info[k].z < info[slot].z:
				slot = k
	else:
		n += 1
	pos[slot] = Vector4(lp.x, lp.y, lp.z, r)
	info[slot] = Vector4(float(kind), heat, clampf(strength, 0.2, 1.0), randf() * 40.0)
	_upload(pc, pos, info, n)


func _upload(pc: Dictionary, pos: PackedVector4Array, info: PackedVector4Array, n: int) -> void:
	pc["pos"] = pos
	pc["info"] = info
	pc["n"] = n
	var hot := false
	for k in n:
		if info[k].y > 0.01:
			hot = true
	pc["hot"] = hot
	var m: ShaderMaterial = pc["mat"]
	m.set_shader_parameter("spot_pos", pos)
	m.set_shader_parameter("spot_info", info)
	m.set_shader_parameter("spot_count", n)


## Визор: удар по шлему / давление — трещины
func crack_visor(amount: float) -> void:
	_visor_dmg = clampf(_visor_dmg + amount, 0.0, 1.0)


## Стереть все следы (после поломки — новый скафандр)
func clear_marks() -> void:
	for pc in _pieces:
		_upload(pc, pc["pos"], pc["info"], 0)
	_visor_dmg = 0.0
	_snow = 0.0
	_wet = 0.0
	_hang = 0.0
	_hang_v = 0.0


## Выражение «лица» на визоре на время
func emote(mood: int, time := 1.0) -> void:
	_mood = mood
	_mood_t = time


func punch() -> void:
	_punch_t = 0.35


func throw_anim() -> void:
	_throw_t = 0.4


func reach() -> void:
	_reach_t = 0.35


# ---------------------------------------------------------------------------
#  Анимация (каждый кадр)
# ---------------------------------------------------------------------------
## st — состояние игрока (см. player.gd → _suit_state()).
func animate(delta: float, st: Dictionary) -> void:
	_t += delta
	var dead: bool = st["dead"]
	var hp: float = st["hp"]
	_update_face(delta, st)
	_update_surface(delta, st)
	_update_details(delta, st)
	if st["frozen"]:
		return
	var vis_tx := _vis.global_transform
	var vel: Vector3 = st["vel"]
	var inv := _vis.global_basis.inverse()
	var lv := inv * Vector3(vel.x, 0.0, vel.z)
	lv.y = 0.0
	var spd := lv.length()
	var carried: bool = st["carried"]
	var tumble: bool = st["tumble"]
	var on_floor: bool = st["on_floor"] and not carried
	var swim: bool = (st["swim"] or st["dive"]) and not carried
	var running: bool = st["running"]
	var quiet: bool = st["quiet"]
	var frost: float = st["frost"]
	var carry: int = st["carry"]
	var weight: int = st["weight"]
	var stick: Node3D = st["stick"]
	var lift: Node3D = st["lift"]
	var exhausted: bool = st["exhausted"]
	var stagger: float = st["stagger"]
	var shake: float = st["shake"]
	var rrole: int = st["rescue_role"]
	var rt: float = st["rescue_t"]
	var clasp: Vector3 = st["clasp"]
	var rp: Dictionary = st["rope"]
	var rope_st: int = int(rp.get("state", 0))
	var rope_anchor: Vector3 = rp.get("anchor", Vector3.ZERO)
	var wave_help: bool = st["wave"]
	var limp := hp < 0.3 and not dead
	var dt := maxf(delta, 0.0001)
	var heavy_walk := (carry == 1 and weight >= 3) or lift != null or carry == 3 or rope_st == 6

	var yaw := _vis.global_rotation.y
	_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / dt, clampf(delta * 10.0, 0.0, 1.0))
	_last_yaw = yaw
	_acc = _acc.lerp((lv - _last_lv) / dt, clampf(delta * 8.0, 0.0, 1.0))
	_last_lv = lv
	_punch_t = maxf(_punch_t - delta, 0.0)
	_throw_t = maxf(_throw_t - delta, 0.0)
	_reach_t = maxf(_reach_t - delta, 0.0)
	_skid_t = maxf(_skid_t - delta, 0.0)
	_land_t = maxf(_land_t - delta, 0.0)
	# занос: резко тормозим с бега
	if on_floor and _prev_spd > 7.0 and (_prev_spd - spd) / dt > 16.0 and spd > 1.5:
		_skid_t = 0.4
	_prev_spd = spd
	if st["just_landed"] and float(st["land_speed"]) > 9.0:
		_land_t = 0.45

	# чем сейчас занят (жесты от скуки — только когда ничем)
	var busy: bool = carry > 0 or stick != null or lift != null or carried or tumble or rope_st >= 2 \
		or rrole != 0 or swim or dead or not on_floor or exhausted or stagger > 0.0 or shake > 0.0
	_update_fidget(delta, busy or spd > 0.4 or _amp > 0.08, st)

	# ---------------- ноги: фаза шага ----------------
	if spd > 0.25:
		_move_dir = _move_dir.lerp(lv / spd, clampf(delta * 10.0, 0.0, 1.0)).normalized()
	var gait_spd := spd
	if st["slipping"]:
		gait_spd = maxf(spd, float(st["target_speed"])) * 1.4      # на льду ноги буксуют
	var step_len := clampf(0.5 + gait_spd * 0.18, 0.5, 2.6)
	if quiet:
		step_len *= 0.75
	if heavy_walk:
		step_len *= 0.62
	step_len *= lerpf(1.0, 0.6, frost)
	if carry >= 2:
		step_len = minf(step_len, 0.8)
	var f := clampf(0.6 / (2.0 * step_len), 0.14, 0.62)
	var cadence := gait_spd / (2.0 * step_len)
	var walking: bool = on_floor and not swim and not dead and not st["skating"] and rrole == 0
	if walking:
		_phase = fposmod(_phase + cadence * delta, 1.0)
	_amp = move_toward(_amp, clampf(gait_spd / 1.0, 0.0, 1.0) if walking else 0.0, delta * 5.0)
	var travel := 2.0 * f * step_len
	var lift_h := (0.1 + 0.22 * clampf((gait_spd - 3.0) / 8.0, 0.0, 1.0)) * (0.55 if quiet else 1.0) * lerpf(1.0, 0.45, frost)
	if heavy_walk:
		lift_h *= 0.6
	var width := 0.14 if not running else 0.11
	if heavy_walk:
		width = 0.2
	var turn_amt := clampf(absf(_yaw_rate) / 3.0, 0.0, 1.0) * (1.0 - _amp)
	_turn_phase += delta * 2.6 * turn_amt
	var run_k := clampf((spd - 5.0) / 5.0, 0.0, 1.0) if on_floor and not heavy_walk else 0.0

	var foot_t: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var pitch_t: Array[float] = [0.0, 0.0]
	var toe_yaw: Array[float] = [0.0, 0.0]
	var crouch := 0.0
	var lean_t := 0.0
	var roll_t := 0.0
	var twist_t := 0.0
	var pelvis_y := HIP_H
	var air := not on_floor and not swim and not dead and not carried and rrole != 2
	var to_rope := Vector3.ZERO           ## в осях визуала: куда уходит верёвка
	if rope_st >= 3 and rope_anchor != Vector3.ZERO:
		to_rope = inv * (rope_anchor - _vis.global_position)
		to_rope.y = 0.0
		to_rope = to_rope.normalized() if to_rope.length() > 0.01 else Vector3.FORWARD
	if dead:
		pelvis_y = 0.55
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			foot_t[i] = Vector3(s * 0.17, 0.0, 0.38 + 0.04 * i)
			pitch_t[i] = -1.2
		lean_t = -0.75
		roll_t = 0.15
	elif carried:
		# меня держат над головой: брыкаюсь
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			var k := _t * 11.0 + i * PI
			foot_t[i] = Vector3(s * 0.17, 0.28 + sin(k) * 0.2, -0.1 + cos(k) * 0.22)
			pitch_t[i] = sin(k) * 0.4
		lean_t = -0.1 + sin(_t * 5.0) * 0.1
		roll_t = sin(_t * 7.0) * 0.12
	elif tumble:
		# кувырок: колени к груди
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			foot_t[i] = Vector3(s * 0.15, 0.55, -0.22)
			pitch_t[i] = 0.5
		lean_t = -0.6
	elif rrole == 1:
		# спасаю: на колено у края, тянусь к руке друга, потом тяну и встаю
		var down := 1.0
		if rt > 1.3:
			down = clampf(1.0 - (rt - 1.3) / 0.45, 0.0, 1.0)
		var pull := clampf((rt - 0.5) / 0.8, 0.0, 1.0)
		pelvis_y = lerpf(HIP_H, lerpf(0.52, 0.7, pull), down)
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			var kneel := Vector3(s * 0.17, 0.0, -0.28) if i == 1 else Vector3(s * 0.16, 0.0, 0.42)
			var rest := Vector3(s * 0.15, 0.0, 0.0)
			foot_t[i] = rest.lerp(kneel, down)
			pitch_t[i] = (-1.15 if i == 0 else 0.0) * down
		lean_t = lerpf(-0.75, 0.2, pull) * down
	elif rrole == 2 and rt >= 1.3:
		# меня вытащили: встаю с колена
		var up := clampf((rt - 1.3) / 0.45, 0.0, 1.0)
		pelvis_y = lerpf(0.58, HIP_H, up)
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			foot_t[i] = Vector3(s * 0.17, 0.0, -0.2 if i == 1 else 0.3).lerp(Vector3(s * 0.15, 0, 0), up)
			pitch_t[i] = (-1.0 if i == 0 else 0.0) * (1.0 - up)
		lean_t = -0.5 * (1.0 - up)
	elif swim or rrole == 2:
		var rising: bool = st["rising"]
		_swim += delta * (7.5 if st["swim"] else (10.0 if rising else 3.5))
		pelvis_y = HIP_H
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			var k := sin(_swim * 1.3 + i * PI)
			foot_t[i] = Vector3(s * 0.16, HIP_H - 0.78 + k * 0.1, 0.28 + k * 0.12)
			pitch_t[i] = -0.6 + k * 0.3
			if rrole == 2 and rt > 0.5:
				foot_t[i] = Vector3(s * 0.16, 0.08 + 0.05 * i, 0.05)    # ноги болтаются в воздухе
				pitch_t[i] = 0.2
		lean_t = -0.55 if spd > 0.5 or st["swim"] else -0.25
		if rrole == 2:
			lean_t = -0.1
	elif air:
		var up_v := vel.y
		pelvis_y = HIP_H
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			if up_v > 0.5:
				# взлёт: одно колено вверх, другая нога вытянута
				foot_t[i] = Vector3(s * 0.15, 0.32, -0.2) if i == 0 else Vector3(s * 0.14, 0.05, 0.22)
				pitch_t[i] = 0.2 if i == 0 else -0.5
			else:
				# падение: ноги тянутся вниз, готовятся к приземлению
				foot_t[i] = Vector3(s * 0.17, 0.06 + (0.06 if i == 0 else 0.0), -0.08 + 0.12 * i)
				pitch_t[i] = 0.15
		lean_t = -0.12 if up_v > 0.0 else 0.08
	else:
		var skating: bool = st["skating"]
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			var ph := fposmod(_phase + i * 0.5, 1.0)
			var gp := Vector3.ZERO
			var gpitch := 0.0
			var stance := true
			var lm := 0.35 if (limp and i == 0) else 1.0
			if ph < f:
				var u := ph / f
				gp = _move_dir * lerpf(travel * 0.5, -travel * 0.5, u)
				gpitch = -smoothstep(0.55, 1.0, u) * 0.55
			else:
				stance = false
				var v := (ph - f) / (1.0 - f)
				var e := v * v * (3.0 - 2.0 * v)
				gp = _move_dir * lerpf(-travel * 0.5, travel * 0.5, e)
				gp.y = sin(v * PI) * lift_h * lm
				gpitch = lerpf(-0.5, 0.3, smoothstep(0.0, 0.7, v)) * (1.0 - smoothstep(0.85, 1.0, v))
			gp.x += s * width
			if _stance[i] and not stance and running and _amp > 0.5:
				_puff[i] = 1.0
				(_legs[i]["puff"] as GPUParticles3D).restart()
			_stance[i] = stance
			var rest := Vector3(s * (0.22 if exhausted or heavy_walk else 0.15), 0.0, -0.03 if i == 0 else 0.05)
			if rope_st >= 4 and rope_st != 6:
				# стойка с верёвкой: одна нога вперёд, к верёвке
				rest = Vector3(s * 0.2, 0.0, 0.0) + to_rope * (0.22 if i == 1 else -0.2)
			var tl := maxf(sin(TAU * (_turn_phase + i * 0.5)), 0.0) * 0.08 * turn_amt
			var fp := rest.lerp(gp, _amp) + Vector3(0, tl, 0)
			var pp := gpitch * _amp
			if skating:
				var k := sin(TAU * (_skate + i * 0.5))
				if k > 0.0:
					fp = Vector3(s * (0.16 + 0.28 * k), 0.0, 0.25 * k)
					toe_yaw[i] = s * 0.5 * k
				else:
					fp = Vector3(s * 0.15, 0.09 * -k, -0.06)
					pp = 0.15 * -k
			elif st["sliding"]:
				fp = Vector3(s * 0.2, 0.0, -0.18 if i == 0 else 0.2)
				toe_yaw[i] = s * 0.35
				pp = 0.0
			elif _skid_t > 0.0:
				fp = Vector3(s * 0.18, 0.0, -0.3 + 0.12 * i)
				pp = 0.35
			if _fidget == "bounce":
				pp = -0.35 * maxf(sin(_fidget_t * 14.0), 0.0)
			foot_t[i] = fp
			pitch_t[i] = pp
		if skating:
			_skate += delta * (0.4 + spd * 0.12)
			crouch -= 0.13
			lean_t = -0.32
		# пружина таза по фазе шага
		var q := fposmod(_phase * 2.0, 1.0)
		var bob_t := 0.0
		if f < 0.5:
			var sp := 2.0 * f
			if q < sp:
				bob_t = -0.045 * sin(PI * q / sp)
			else:
				bob_t = 0.085 * sin(PI * (q - sp) / (1.0 - sp)) * clampf(spd / 5.0, 0.0, 1.0)
		else:
			bob_t = -0.03 * sin(PI * q)
		if heavy_walk:
			bob_t = -0.05 * absf(sin(TAU * _phase))
		if limp and fposmod(_phase, 1.0) < f:
			bob_t -= 0.04
		pelvis_y = HIP_H + bob_t * _amp
		if quiet:
			crouch -= 0.07
			lean_t -= 0.15
		if exhausted and spd < 1.0:
			crouch -= 0.14
			lean_t = -0.75
		if st["sliding"]:
			crouch -= 0.12
		if _skid_t > 0.0:
			crouch -= 0.15
			lean_t += 0.35
		if _land_t > 0.0:
			crouch -= 0.28 * sin(PI * _land_t / 0.45)
			lean_t -= 0.3 * sin(PI * _land_t / 0.45)
		if _fidget == "bounce":
			crouch += 0.04 * maxf(sin(_fidget_t * 14.0), 0.0)
		elif _fidget == "stretch":
			lean_t += 0.18 * sin(PI * clampf(_fidget_t / 2.0, 0.0, 1.0))
		lean_t += -(0.05 + 0.22 * clampf(spd / 11.0, 0.0, 1.0)) * _amp
		lean_t += clampf(_acc.z * 0.012, -0.2, 0.2)
		twist_t = sin(TAU * _phase) * 0.12 * _amp
		roll_t = clampf(-_yaw_rate * spd * 0.012, -0.25, 0.25)
		if heavy_walk:
			roll_t += sin(TAU * _phase) * 0.09 * _amp     # переваливается с ноги на ногу

	if not dead and not swim and not carried and not tumble and rrole == 0:
		if carry == 1:
			lean_t += [0.0, 0.07, 0.2][clampi(weight, 1, 3) - 1]
			if weight == 1:
				roll_t -= 0.05
		elif carry == 3:
			lean_t += 0.1
			crouch -= 0.06
		elif carry == 2:
			lean_t -= 0.45
			crouch -= 0.08
		if lift != null:
			lean_t += 0.12
			crouch -= 0.05
		if stick != null:
			lean_t -= 0.32
			crouch -= 0.1
			twist_t += 0.18
		match rope_st:
			5:
				lean_t += 0.32
				crouch -= 0.12
			6:
				lean_t -= 0.5
				crouch -= 0.06
			7:
				lean_t += 0.38
				crouch -= 0.18
		if _reach_t > 0.0:
			var rk := sin(PI * (1.0 - _reach_t / 0.35))
			lean_t -= 0.45 * rk
			crouch -= 0.2 * rk
		if _punch_t > 0.0:
			twist_t -= 0.35 * sin(PI * (1.0 - _punch_t / 0.35))
		if _throw_t > 0.0:
			var tk := sin(PI * (1.0 - _throw_t / 0.4))
			lean_t -= 0.3 * tk
			if lift == null and _was_lifting:
				lean_t -= 0.2 * tk
		if _fidget == "look_back":
			twist_t += 0.3 * sin(PI * clampf(_fidget_t / 1.8, 0.0, 1.0))

	# ветер: корпус кренится навстречу, мелко дрожит
	var wl := inv * (st["wind"] as Vector3)
	var wmag := minf(wl.length() / 6.0, 1.0)
	if wmag > 0.05 and not dead and not carried:
		lean_t += clampf(-wl.z * 0.07, -0.35, 0.35) + sin(_t * 33.0) * 0.04 * wmag
		roll_t += clampf(wl.x * 0.07, -0.35, 0.35) + sin(_t * 29.0 + 1.3) * 0.05 * wmag
	if stagger > 0.0:
		roll_t += sin(_t * 28.0) * 0.45 * stagger
		lean_t += 0.25 * stagger
	if frost > 0.4 and not swim and not dead:
		roll_t += sin(_t * 41.0) * 0.03 * frost
	if shake > 0.0:
		roll_t += sin(_t * 48.0) * 0.4 * shake

	# ---------------- таз и корпус (пружины) ----------------
	var y_t := pelvis_y + crouch
	if st["just_landed"]:
		_bob_v -= clampf(float(st["land_speed"]) * 0.35, 0.8, 4.0)
	_bob_v += (220.0 * (y_t - HIP_H - _bob) - 17.0 * _bob_v) * delta
	_bob += _bob_v * delta
	_lean_v += (130.0 * (lean_t - _lean) - 15.0 * _lean_v) * delta
	_lean += _lean_v * delta
	_roll = lerpf(_roll, roll_t, clampf(delta * (6.0 if dead else 12.0), 0.0, 1.0))
	_twist = lerpf(_twist, twist_t, clampf(delta * 10.0, 0.0, 1.0))

	# земля под ступнями
	var gl := [0.0, 0.0]
	if on_floor and not swim:
		var space := get_world_3d().direct_space_state
		for i in 2:
			var wp := vis_tx * Vector3(foot_t[i].x, 0.0, foot_t[i].z)
			var q := PhysicsRayQueryParameters3D.create(wp + Vector3.UP * 0.6, wp + Vector3.DOWN * 0.6, 1)
			var ex: Array[RID] = []
			if st["rid"] is RID:
				ex.append(st["rid"])
			q.exclude = ex
			var hit := space.intersect_ray(q)
			var g := 0.0
			if not hit.is_empty():
				g = clampf((hit["position"] as Vector3).y - vis_tx.origin.y, -0.4, 0.35)
			gl[i] = g
	for i in 2:
		_gnd[i] = lerpf(_gnd[i], gl[i], clampf(delta * 18.0, 0.0, 1.0))
	var gdrop := minf(_gnd[0], _gnd[1]) if on_floor and not swim else 0.0

	var sway_x := 0.0
	if walking and f >= 0.4:
		sway_x = sin(TAU * _phase) * 0.025 * _amp
	pelvis.position = Vector3(sway_x, HIP_H + _bob + gdrop, 0.0)
	pelvis.rotation = Vector3(0.0, _twist, _roll * 0.3)
	var breathe := sin(_t * (2.6 if exhausted else 1.7)) * (0.014 if exhausted else 0.006)
	torso.position = pelvis.position + Vector3(0, 0.02 + breathe, 0)
	torso.rotation = Vector3(_lean, -_twist * 0.8, _roll)
	torso.scale = torso.scale.lerp(Vector3.ONE, clampf(10.0 * delta, 0.0, 1.0))

	# покачивание посылки в такт шагам
	var sway_k := 1.6 if weight == 1 else (0.6 if weight == 3 else 1.0)
	_carry_sway = Basis.from_euler(Vector3(sin(TAU * _phase * 2.0) * 0.03 * _amp * sway_k, 0.0, sin(TAU * _phase) * 0.05 * _amp * sway_k))

	# ---------------- голова ----------------
	_glance_t -= delta
	if _glance_t <= 0.0:
		_glance_t = randf_range(2.5, 6.0)
		_glance = randf_range(-0.7, 0.7) if _amp < 0.2 and randf() < 0.6 else 0.0
	var look_yaw: float = clampf(float(st["look_yaw"]) * 0.85 + _glance, -1.1, 1.1)
	var look_pitch: float = clampf(float(st["look_pitch"]) * 0.5, -0.4, 0.35)
	var friend := _nearest_friend(st, 7.0)
	if not busy and friend != null and _amp < 0.1:
		var tf := inv * (friend.global_position - _vis.global_position)
		look_yaw = clampf(atan2(-tf.x, -tf.z), -1.1, 1.1)
	match _fidget:
		"wrist":
			look_yaw = 0.45
			look_pitch = -0.55
		"wipe":
			look_pitch = -0.1
		"look_back":
			look_yaw = 1.25 * sin(PI * clampf(_fidget_t / 1.8, 0.0, 1.0))
		"stretch":
			look_pitch = 0.35 * sin(PI * clampf(_fidget_t / 2.0, 0.0, 1.0))
	if rope_st == 2:
		look_pitch = 0.3
	if rrole != 0 and clasp != Vector3.ZERO:
		var tc := inv * (clasp - head.global_position)
		look_yaw = clampf(atan2(-tc.x, -tc.z), -1.1, 1.1)
		look_pitch = clampf(atan2(tc.y, Vector2(tc.x, tc.z).length()) * 0.8, -0.6, 0.5)
	if carried:
		look_yaw = sin(_t * 3.0) * 0.6
	if dead:
		look_yaw = 0.3
		look_pitch = -0.6
	_head_yaw = lerpf(_head_yaw, look_yaw, clampf(delta * 6.0, 0.0, 1.0))
	_head_pitch = lerpf(_head_pitch, look_pitch - _lean * 0.7, clampf(delta * 8.0, 0.0, 1.0))
	neck.rotation = Vector3(_head_pitch, _head_yaw + _twist * 0.8, -_roll * 0.6)

	# ---------------- ноги (ИК) ----------------
	var fwd := -_vis.global_basis.z
	for i in 2:
		var lg: Dictionary = _legs[i]
		var s: float = lg["s"]
		var ft := foot_t[i] + Vector3(0, (_gnd[i] if on_floor and not swim else 0.0), 0)
		if air or swim or carried or tumble:
			ft.y += pelvis.position.y - HIP_H
		var k := clampf(delta * (25.0 if on_floor else 10.0), 0.0, 1.0)
		_feet[i] = _feet[i].lerp(ft, k)
		_pitch[i] = lerpf(_pitch[i], pitch_t[i], k)
		var heel_up := maxf(-_pitch[i], 0.0)
		var ankle := vis_tx * (_feet[i] + Vector3(0, ANKLE_H + sin(heel_up) * 0.15, 0))
		var hip := pelvis.global_transform * Vector3(s * HIP_X, -0.05, 0.0)
		var side := _vis.global_basis.x * s
		var up_v := _vis.global_basis.y
		var pole := hip + fwd * 0.9 + side * 0.12 - up_v * 0.2
		var sol := ik2(hip, ankle, THIGH, SHIN, pole)
		var knee: Vector3 = sol[0]
		var end: Vector3 = sol[1]
		var pd: Vector3 = sol[2]
		knees[i] = knee
		(lg["thigh"] as Node3D).global_transform = Transform3D(seg_basis(knee - hip, pd), hip)
		(lg["shin"] as Node3D).global_transform = Transform3D(seg_basis(end - knee, pd), knee)
		var by := _vis.global_basis.orthonormalized() * Basis(Vector3.UP, _twist * 0.3 - s * 0.06 - toe_yaw[i]) * Basis(Vector3.RIGHT, _pitch[i])
		(lg["boot"] as Node3D).global_transform = Transform3D(by, end)
		# гидравлика: корпус на бедре, шток — на голени
		var tb := (lg["thigh"] as Node3D).global_transform
		var sb := (lg["shin"] as Node3D).global_transform
		var a := tb * Vector3(0, -THIGH * 0.62, 0.075)
		var b := sb * Vector3(0, -SHIN * 0.4, 0.065)
		var ab := b - a
		var abl := maxf(ab.length(), 0.01)
		var abd := ab / abl
		(lg["housing"] as Node3D).global_transform = Transform3D(seg_basis(-abd, pd), a + abd * 0.07)
		var rl := maxf(abl - 0.06, 0.05)
		var rod := lg["rod"] as Node3D
		rod.global_transform = Transform3D(seg_basis(-abd, pd).scaled_local(Vector3(1, rl, 1)), b - abd * rl * 0.5)
		# пяточные сопла
		_puff[i] = maxf(_puff[i] - delta * 6.0, 0.0)
		var heel := lg["heel"] as MeshInstance3D
		heel.visible = _puff[i] > 0.02
		if heel.visible:
			heel.scale = Vector3.ONE * (0.6 + _puff[i] * 1.2)

	# ---------------- руки ----------------
	var tx := torso.global_transform
	var up := _vis.global_basis.y
	var right := _vis.global_basis.x
	var parcel: Node3D = st["parcel"]
	var carry_tx := Transform3D.IDENTITY
	if carry == 1:
		carry_tx = carry_transform(st["carry_basis"], st["carry_offset"], weight, extents(parcel))
	var wind_arm := -1
	var wind_w := 0.0
	if wmag > 0.45 and carry == 0 and stick == null and not swim and not dead and lift == null and rope_st < 2 and rrole == 0:
		wind_arm = 1 if wl.x <= 0.0 else 0
		wind_w = clampf((wmag - 0.45) / 0.3, 0.0, 1.0)
	var chest := tx * Vector3(0, 0.3, -0.1)
	var rope_dir := (rope_anchor - chest).normalized() if rope_anchor != Vector3.ZERO else fwd
	if lift != null:
		_was_lifting = true
	elif _throw_t <= 0.0:
		_was_lifting = false
	for i in 2:
		var am: Dictionary = _arms[i]
		var s: float = am["s"]
		var sh_l := SHOULDER * Vector3(s, 1, 1)
		var free := Vector3.ZERO
		var curl := 0.35 + 0.55 * run_k
		var swing := -cos(TAU * fposmod(_phase + i * 0.5, 1.0)) * _amp * (0.35 + 0.45 * run_k) * (0.4 if heavy_walk else 1.0)
		var v_hang := Vector3(s * 0.08, -0.57, 0.03)
		var v_bent := Vector3(s * 0.05, -0.33, -0.2)
		var v := v_hang.lerp(v_bent, maxf(run_k, 0.45 if quiet else 0.0))
		if dead:
			v = Vector3(s * 0.12, -0.55, -0.06)
			curl = 0.5
		elif carried:
			v = Vector3(s * 0.45, -0.05 + sin(_t * 13.0 + i * 2.0) * 0.25, -0.1 + cos(_t * 10.0 + i) * 0.2)
			curl = 0.1
		elif tumble:
			v = Vector3(s * 0.1, -0.3, -0.35)
			curl = 0.8
		elif swim:
			var c := _swim + i * 0.0
			v = Vector3(s * (0.2 + 0.2 * cos(c)), -0.08 + 0.12 * sin(c), -0.38 - 0.15 * sin(c))
			curl = 0.1
			if wave_help and i == 1:
				v = Vector3(s * 0.3 + sin(_t * 9.0) * 0.15, 0.78, -0.05)
				curl = 0.0
		elif air:
			if vel.y > 0.5:
				v = Vector3(s * 0.28, -0.22, 0.18)
			else:
				v = Vector3(s * 0.45, -0.12 + sin(_t * 9.0 + i) * 0.05, -0.05)
			curl = 0.15
		elif stagger > 0.0 or shake > 0.0:
			v = Vector3(s * 0.4, -0.1 + sin(_t * 22.0 + i * 2.0) * 0.2, -0.1 + cos(_t * 19.0 + i) * 0.2)
			curl = 0.05
		elif _skid_t > 0.0 or _land_t > 0.0:
			v = Vector3(s * 0.42, -0.35, -0.25)
			curl = 0.1
		elif st["slipping"] or st["sliding"]:
			v = Vector3(s * 0.45, -0.15 + sin(_t * 13.0 + i * 2.0) * 0.1 * (1.0 if st["slipping"] else 0.3), -0.08)
			curl = 0.1
		elif st["skating"]:
			var k := sin(TAU * (_skate + i * 0.5))
			v = Vector3(s * 0.12 - k * 0.25, -0.45, -0.12)
			curl = 0.6
		else:
			v = Basis(Vector3.RIGHT, swing) * v
		# жесты от скуки
		var fu := clampf(_fidget_t / maxf(_fidget_len, 0.01), 0.0, 1.0)
		var fk := sin(PI * fu)
		match _fidget:
			"wrist":
				if i == 0:
					v = v.lerp(Vector3(0.05, 0.02, -0.4), fk)
					curl = 0.3
			"stretch":
				v = v.lerp(Vector3(s * 0.22, 0.6, -0.02), fk)
				curl = lerpf(curl, 0.0, fk)
			"wipe":
				if i == 1:
					v = v.lerp(Vector3(0.05 + sin(_fidget_t * 10.0) * 0.12, 0.28, -0.42), fk)
					curl = 0.1
			"wave":
				if i == 1:
					v = v.lerp(Vector3(s * 0.32 + sin(_fidget_t * 10.0) * 0.12, 0.62, -0.1), fk)
					curl = 0.0
		if not dead and not swim and _amp < 0.2:
			# пальцы иногда «разминаются»
			_flex_t -= delta * 0.5
			if _flex_t <= 0.0:
				_flex_t = randf_range(5.0, 10.0)
				_flex = 1.0
		free = sh_l + v
		free += Vector3(clampf(-_acc.x * 0.004, -0.12, 0.12), 0.0, clampf(-_acc.z * 0.004, -0.12, 0.12))
		free.y += breathe * 2.0
		if wind_arm == i:
			free = free.lerp(Vector3(s * 0.02, 0.6, -0.3), wind_w)
		if _punch_t > 0.0 and i == 1:
			free = free.lerp(Vector3(0.06, 0.36, -0.72), sin(PI * (1.0 - _punch_t / 0.35)))
			curl = 1.0
		if _throw_t > 0.0 and _was_lifting and lift == null:
			# только что кинул друга: руки летят вперёд-вверх
			free = free.lerp(Vector3(s * 0.15, 0.65, -0.5), sin(PI * (1.0 - _throw_t / 0.4)))
			curl = 0.0
		# пружина: рука догоняет цель с перелётом — болтается
		_hand_v[i] += (170.0 * (free - _hand_p[i]) - 16.0 * _hand_v[i]) * delta
		_hand_p[i] += _hand_v[i] * delta
		var wrist_free := tx * _hand_p[i]

		# захват
		var hold := false
		var hold_wrist := Vector3.ZERO
		var hold_basis := Basis.IDENTITY
		var pole_l := Vector3(s * 0.55, -0.35, 0.45)
		var trem := Vector3.ZERO
		if carry == 1:
			var ext := extents(parcel)
			var bx := carry_tx.basis.x.normalized()
			var by_ := carry_tx.basis.y.normalized()
			var bz := carry_tx.basis.z.normalized()
			if weight == 1:
				# лёгкая — под правой рукой, ладонь снизу; левая свободна
				if i == 1:
					var palm := carry_tx.origin - by_ * (ext.y + 0.03) + bx * ext.x * 0.15
					hold_basis = _hand_basis((-bz * 0.9 + bx * 0.2).normalized(), -up * s)
					hold_wrist = palm + hold_basis.y * HAND
					hold = true
					curl = 0.45
					pole_l = Vector3(s * 0.6, -0.3, 0.55)
			elif weight >= 3:
				# тяжёлая — в обнимку снизу, ладони вверх, руки дрожат от натуги
				var palm := carry_tx.origin - by_ * (ext.y + 0.025) + bx * s * ext.x * 0.55 + bz * ext.z * 0.1
				hold_basis = _hand_basis((-bz * 0.85 + bx * -s * 0.3).normalized(), -up * s)
				hold_wrist = palm + hold_basis.y * HAND
				hold = true
				curl = 0.55
				pole_l = Vector3(s * 0.75, -0.45, 0.2)
				trem = Vector3(sin(_t * 37.0 + i), sin(_t * 41.0), 0.0) * 0.006
			else:
				var palm := carry_tx.origin + bx * s * (ext.x + 0.035) - by_ * ext.y * 0.15 - bz * ext.z * 0.05
				var fingers := (-bz * 0.85 - by_ * 0.35).normalized()
				hold_basis = _hand_basis(fingers, bx)
				hold_wrist = palm + hold_basis.y * HAND
				hold = true
				curl = 0.18
				pole_l = Vector3(s * 0.7, -0.5, 0.25)
			if hold and _throw_t > 0.0:
				hold_wrist = hold_wrist.lerp(tx * Vector3(s * 0.14, 0.35, -0.68), sin(PI * (1.0 - _throw_t / 0.4)))
		elif (carry == 2 or carry == 3) and parcel != null:
			var ext := extents(parcel)
			var pb := parcel.global_basis.orthonormalized()
			var to_me := _vis.global_position - parcel.global_position
			var sg := signf(to_me.dot(pb.x)) if absf(to_me.dot(pb.x)) > 0.01 else 1.0
			var handle := parcel.global_position + pb.x * sg * (ext.x + 0.06) + pb.y * ext.y * 0.25
			var across := pb.z if pb.z.dot(_vis.global_basis.x) > 0.0 else -pb.z
			var palm := handle + across * s * 0.15 + Vector3.UP * 0.03
			var fingers := (-pb.x * sg * 0.6 + Vector3.DOWN * 0.8).normalized()
			hold_basis = _hand_basis(fingers, Vector3.UP * s)
			hold_wrist = palm + hold_basis.y * HAND
			hold = true
			curl = 0.85
			pole_l = Vector3(s * 0.6, -0.6, 0.3)
			if carry == 3 and spd > 0.3:
				trem = Vector3(sin(_t * 31.0 + i * 2.0), sin(_t * 27.0), 0.0) * 0.008
		elif lift != null:
			# друг над головой: ладони вверх под спину
			var center := lift.global_position + Vector3.UP * 2.12
			var palm := center + right * s * 0.3 - up * 0.17
			hold_basis = _hand_basis((-right * s * 0.3 + up * 0.2 - fwd * 0.6).normalized(), -up * s)
			hold_wrist = palm + hold_basis.y * HAND
			hold = true
			curl = 0.4
			pole_l = Vector3(s * 0.85, -0.1, 0.15)
			trem = Vector3(sin(_t * 23.0 + i), 0.0, sin(_t * 19.0)) * 0.01
		elif stick != null:
			var st_tx := stick.global_transform
			var grip := st_tx * (Vector3(0, 1.3, 0.22) if i == 1 else Vector3(0, 1.07, 0.18))
			var shaft := (st_tx.basis * Vector3(0, 1, 0.17)).normalized()
			hold_basis = _hand_basis((_vis.global_basis.x * -s + Vector3.DOWN * 0.3).normalized(), -shaft * s)
			hold_wrist = grip + hold_basis.y * 0.04
			hold = true
			curl = 0.95
			pole_l = Vector3(s * 0.7, -0.4, 0.2)
		elif rrole != 0 and clasp != Vector3.ZERO and (rrole == 1 and rt < 1.35 or rrole == 2 and rt < 1.3):
			# рука в руку
			if i == 1:
				var to_c := (clasp - tx * sh_l).normalized()
				hold_basis = _hand_basis(to_c, up * s)
				hold_wrist = clasp - to_c * HAND
				hold = true
				curl = 0.75
				pole_l = Vector3(s * 0.6, -0.4, 0.3)
			elif rrole == 1:
				hold_wrist = knees[1] + up * 0.07 + fwd * 0.04
				hold_basis = _hand_basis((-up * 0.3 + fwd * 0.7).normalized(), up * s)
				hold = true
				curl = 0.3
		elif rope_st >= 1 and not dead and not swim:
			var rk := _rope_hand(i, s, rope_st, rp, tx, chest, rope_dir, up, fwd)
			if rk[0]:
				hold_wrist = rk[1]
				hold_basis = rk[2]
				curl = rk[3]
				pole_l = rk[4]
				hold = true
		elif exhausted and spd < 1.0 and on_floor and not dead and not swim and stagger <= 0.0:
			hold_wrist = knees[i] + fwd * 0.07 + up * 0.07
			hold_basis = _hand_basis((-up * 0.3 + fwd * 0.7).normalized(), up * s)
			hold = true
			curl = 0.3
		elif _reach_t > 0.0:
			hold_wrist = tx * Vector3(s * 0.2, -0.2, -0.55)
			hold_basis = _hand_basis((-up * 0.6 + fwd * 0.4).normalized(), up * s)
			hold = true
			curl = 0.1
		hold_wrist += trem
		_hold_w[i] = move_toward(_hold_w[i], 1.0 if hold else 0.0, delta * (9.0 if hold else 5.0))
		var hw := _hold_w[i]
		var wrist := wrist_free.lerp(hold_wrist, hw) if hw > 0.0 else wrist_free
		var S := tx * sh_l
		var pole := S + tx.basis * pole_l
		var sol := ik2(S, wrist, UPPER, FORE, pole)
		var elbow: Vector3 = sol[0]
		var end: Vector3 = sol[1]
		var pd: Vector3 = sol[2]
		(am["upper"] as Node3D).global_transform = Transform3D(seg_basis(elbow - S, -pd), S)
		var fb := seg_basis(end - elbow, -pd)
		(am["fore"] as Node3D).global_transform = Transform3D(fb, elbow)
		var hb := fb
		if hw > 0.0:
			hb = Basis(fb.get_rotation_quaternion().slerp(hold_basis.get_rotation_quaternion(), hw))
		(am["hand"] as Node3D).global_transform = Transform3D(hb, end)
		# пальцы
		if _flex > 0.0 and i == 0 and not hold:
			curl = lerpf(curl, 0.0 if _flex > 0.5 else 1.0, sin(_flex * PI))
		_curl[i] = lerpf(_curl[i], curl, clampf(delta * 14.0, 0.0, 1.0))
		_set_curl(am, _curl[i])
		# наплечник: при поломке болтается
		var pv := am["pauldron"] as Node3D
		if i == 1:
			var hang_t := 0.85 if hp < 0.3 and not dead else 0.0
			_hang_v += (60.0 * (hang_t - _hang) - 2.5 * _hang_v + _acc.x * 0.4 + _bob_v * 3.0) * delta
			_hang += _hang_v * delta
			_hang = clampf(_hang, -0.3, 1.3)
			pv.rotation = Vector3(0, 0, -s * maxf(_hang, 0.0) * (1.0 if hp < 0.3 else 0.2))
		pv.position.y = 0.47 + breathe * 1.5
	_flex = maxf(_flex - delta * 0.6, 0.0)

	# ---------------- сопла и манометр ----------------
	var thrust: float = st["thrust"]
	var flick := 1.0 + randf_range(-0.08, 0.08)
	thruster_light.light_energy = thrust * flick
	for g in nozzle_glows:
		g.scale = Vector3.ONE * (0.6 + thrust * 0.15) * flick
	for fl in flames:
		fl.visible = thrust > 0.9
		if fl.visible:
			var ln := clampf((thrust - 0.8) * 0.13, 0.05, 0.6) * flick
			fl.scale = Vector3(1.0, ln, 1.0)
			fl.position.y = -0.33 - ln * 0.5
	_needle.rotation.z = lerpf(_needle.rotation.z, lerpf(2.3, -2.3, float(st["stamina"])), clampf(delta * 8.0, 0.0, 1.0))

	# ---------------- поломка: искры, дым ----------------
	_smoke.emitting = hp < 0.25 and not swim
	if hp < 0.45 and not swim:
		_spark_t -= delta
		if _spark_t <= 0.0:
			_spark_t = randf_range(0.6, 2.2) * (0.5 + hp * 2.0)
			var joints := [knees[0], knees[1], (_arms[0]["fore"] as Node3D).global_position, (_arms[1]["fore"] as Node3D).global_position, neck.global_position]
			_sparks.global_position = joints[randi() % joints.size()]
			_sparks.restart()


## Руки с верёвкой. Возвращает [держит?, запястье, базис ладони, сжатие пальцев, полюс локтя]
func _rope_hand(i: int, s: float, rope_st: int, rp: Dictionary, tx: Transform3D, chest: Vector3,
		rope_dir: Vector3, up: Vector3, fwd: Vector3) -> Array:
	var side := _vis.global_basis.x
	match rope_st:
		1:
			# моток в левой руке у бедра
			if i == 0:
				var w := tx * Vector3(-0.24, -0.16, -0.18)
				return [true, w, _hand_basis((-up * 0.5 + fwd * 0.5).normalized(), side * s), 0.85, Vector3(s * 0.6, -0.3, 0.4)]
		2:
			if i == 1:
				# раскручиваю петлю над головой
				var a := float(rp.get("swing_t", 0.0)) * 11.0
				var c := tx * Vector3(0.12, 0.88, -0.05)
				var w := c + Vector3(cos(a), 0.0, sin(a)) * 0.16
				return [true, w, _hand_basis(up, side * s), 0.9, Vector3(s * 0.8, -0.1, 0.2)]
			var w0 := tx * Vector3(-0.12, 0.18, -0.3)
			return [true, w0, _hand_basis(fwd, side * s), 0.85, Vector3(s * 0.6, -0.4, 0.3)]
		3:
			var tt := float(rp.get("throw_t", 1.0))
			if i == 1 and tt < 0.6:
				var S := tx * (SHOULDER * Vector3(s, 1, 1))
				return [true, S + rope_dir * 0.62, _hand_basis(rope_dir, side * s), 0.3, Vector3(s * 0.6, -0.4, 0.3)]
			if i == 0:
				var w1 := tx * Vector3(-0.14, 0.12, -0.3)
				return [true, w1, _hand_basis(fwd, side * s), 0.85, Vector3(s * 0.6, -0.4, 0.3)]
		4, 7:
			# держу верёвку перед собой: правая — дальше по верёвке, левая — ближе
			var low := -up * (0.18 if rope_st == 7 else 0.12)
			var d := 0.48 if i == 1 else 0.22
			var w2 := chest + rope_dir * d + low + side * 0.03 * s
			return [true, w2, _hand_basis(rope_dir, up * s), 0.9, Vector3(s * 0.6, -0.5, 0.3)]
		5:
			# перехват: руки по очереди тянутся вперёд и тянут к себе
			var ph := fposmod(_t * 2.6 + i * 0.5, 1.0)
			var d := 0.0
			var lift_u := 0.0
			if ph < 0.45:
				var u := ph / 0.45
				d = lerpf(0.12, 0.62, u * u * (3.0 - 2.0 * u))
				lift_u = sin(u * PI) * 0.06
			else:
				var u := (ph - 0.45) / 0.55
				d = lerpf(0.62, 0.12, u)
			var w3 := chest + rope_dir * d - up * 0.14 + up * lift_u + side * 0.04 * s
			return [true, w3, _hand_basis(rope_dir, up * s), 0.95 if ph >= 0.45 else 0.3, Vector3(s * 0.6, -0.5, 0.35)]
		6:
			# волоку: верёвка через правое плечо, руки у плеча
			var w4 := tx * (Vector3(0.2, 0.4, -0.22) if i == 1 else Vector3(0.05, 0.32, -0.27))
			return [true, w4, _hand_basis(-up, fwd), 0.95, Vector3(s * 0.6, -0.5, 0.2)]
	return [false, Vector3.ZERO, Basis.IDENTITY, 0.35, Vector3(s * 0.55, -0.35, 0.45)]


## Ближайший друг (для взгляда и приветствия)
func _nearest_friend(st: Dictionary, max_d: float) -> Node3D:
	var me: Node = st.get("self")
	var best: Node3D = null
	var bd := max_d
	for d in get_tree().get_nodes_in_group("player"):
		if d == me:
			continue
		var dist := (d as Node3D).global_position.distance_to(_vis.global_position)
		if dist < bd:
			bd = dist
			best = d
	return best


## Жесты, пока стоишь без дела: посмотреть на наручный экран, потянуться,
## протереть визор, оглянуться на манометр, помахать другу, попружинить
func _update_fidget(delta: float, interrupted: bool, st: Dictionary) -> void:
	if interrupted:
		_fidget = ""
		_fidget_t = 0.0
		_idle_clock = 0.0
		return
	if _fidget != "":
		_fidget_t += delta
		if _fidget_t >= _fidget_len:
			_fidget = ""
			_fidget_t = 0.0
			_idle_clock = 0.0
		return
	_idle_clock += delta
	if _idle_clock < _next_fidget:
		return
	_next_fidget = randf_range(5.0, 10.0)
	var opts := ["wrist", "stretch", "look_back", "bounce"]
	if _snow > 0.2 or float(st["frost"]) > 0.1 or _wet > 0.3:
		opts.append("wipe")
		opts.append("wipe")
	else:
		opts.append("wipe")
	if _nearest_friend(st, 9.0) != null:
		opts.append("wave")
		opts.append("wave")
	_fidget = opts.pick_random()
	_fidget_t = 0.0
	_fidget_len = {"wrist": 2.4, "stretch": 2.0, "look_back": 1.8, "bounce": 1.3, "wipe": 1.6, "wave": 1.8}[_fidget]
	if _fidget == "wave":
		emote(Mood.HAPPY, 1.8)

func extents(parcel: Node3D) -> Vector3:
	if parcel == null:
		return Vector3(0.3, 0.3, 0.3)
	if parcel.has_meta("half_ext"):
		return parcel.get_meta("half_ext")
	var e := Vector3(0.3, 0.3, 0.3)
	for c in parcel.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			e = ((c as CollisionShape3D).shape as BoxShape3D).size * 0.5
			break
	parcel.set_meta("half_ext", e)
	return e


## Базис ладони: пальцы — fingers, тыльная сторона наружу — back_x (ось X ладони)
static func _hand_basis(fingers: Vector3, back_x: Vector3) -> Basis:
	var y := -fingers.normalized()
	var x := back_x - y * back_x.dot(y)
	if x.length() < 0.001:
		x = Vector3.RIGHT - y * y.x
	x = x.normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


func _set_curl(am: Dictionary, c: float) -> void:
	var s: float = am["s"]
	for key in ["f1", "f2"]:
		var f: Array = am[key]
		(f[0] as Node3D).rotation.z = -s * c * 1.15
		(f[1] as Node3D).rotation.z = -s * c * 1.3
	var th: Array = am["th"]
	(th[0] as Node3D).rotation.z = -s * c * 0.7
	(th[1] as Node3D).rotation.z = -s * c * 0.8


# ---------------------------------------------------------------------------
#  Визор, огоньки и поверхность брони
# ---------------------------------------------------------------------------
func _update_face(delta: float, st: Dictionary) -> void:
	var hp: float = st["hp"]
	var dead: bool = st["dead"]
	_mood_t -= delta
	var mood := _mood if _mood_t > 0.0 else Mood.NORMAL
	if st["exhausted"] or st["frost"] > 0.6:
		mood = Mood.TIRED if _mood_t <= 0.0 else mood
	if st["stagger"] > 0.0 or st["frozen"]:
		mood = Mood.HURT
	if dead:
		mood = Mood.OFF
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink_t = randf_range(2.0, 5.0)
		_blink = 1.0
	_blink = maxf(_blink - delta * 8.0, 0.0)
	var power := 1.0
	if hp < 0.25 and not dead:
		power = 0.15 if randf() < 0.08 else randf_range(0.7, 1.0)
	_visor_mat.set_shader_parameter("mood", mood)
	_visor_mat.set_shader_parameter("blink", sin(_blink * PI))
	_visor_mat.set_shader_parameter("power", power)
	var lk := Vector2(clampf(float(st["look_yaw"]) * 0.6, -1.0, 1.0), clampf(float(st["look_pitch"]), -1.0, 1.0))
	_visor_mat.set_shader_parameter("look", lk)
	_visor_mat.set_shader_parameter("cracks", maxf(_visor_dmg, clampf((0.3 - hp) * 2.5, 0.0, 1.0)))
	_antenna_mat.emission_energy_multiplier = 4.0 if fmod(_t, 1.2) < 0.15 else 0.4
	_ear_mat.emission_energy_multiplier = 3.0 * power
	if _console_mat:
		var c := Color(1, 0.25, 0.2).lerp(Color(0.4, 1.0, 0.5), hp)
		if hp < 0.3 and fmod(_t, 0.5) < 0.25:
			c = c.darkened(0.7)
		_console_mat.albedo_color = c
		_console_mat.emission = c


func _update_surface(delta: float, st: Dictionary) -> void:
	var hp: float = st["hp"]
	var wind: Vector3 = st["wind"]
	var in_water: bool = st["swim"] or st["dive"]
	if in_water:
		_wet = 1.0
		_snow = 0.0
	else:
		_wet = maxf(_wet - delta * (0.4 if st["heat"] else 0.07), 0.0)
		if bool(st["wet"]):
			_wet = maxf(_wet, 0.7)
		if wind.length() > 3.0:
			_snow = minf(_snow + delta * 0.05, 0.85)
		else:
			_snow = maxf(_snow - delta * (0.3 if st["heat"] else 0.006), 0.0)
	_wear = 1.0 - hp
	_mat_t -= delta
	if _mat_t <= 0.0:
		_mat_t = 0.2
		for m in _mats:
			m.set_shader_parameter("snow", _snow)
			m.set_shader_parameter("wet", _wet)
			m.set_shader_parameter("wear", _wear)
	# свежие ожоги остывают
	_heat_t -= delta
	if _heat_t <= 0.0:
		_heat_t = 0.1
		for pc in _pieces:
			if not pc["hot"]:
				continue
			var info: PackedVector4Array = pc["info"]
			var n: int = pc["n"]
			for k in n:
				var si := info[k]
				if si.y > 0.0:
					si.y = maxf(si.y - 0.035, 0.0)
					info[k] = si
			_upload(pc, pc["pos"], info, n)


# ---------------------------------------------------------------------------
#  Детали: шланг от котла к шлему, огоньки на груди, налобный фонарь, номер
# ---------------------------------------------------------------------------
func _build_details() -> void:
	var rub := _armor("rubber", false)
	var rub2 := _armor("steel", false)
	for k in 10:
		var mi := MeshInstance3D.new()
		mi.mesh = _cyl(0.024, 0.024, 1.0, 8)
		mi.material_override = rub if k % 2 == 0 else rub2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_hose.append(mi)
	# огоньки на груди слева
	var cols := [Color(0.3, 1.0, 0.4), Color(1.0, 0.8, 0.2), Color(1.0, 0.25, 0.2)]
	for k in 3:
		var x := -0.17
		var y := 0.4 - k * 0.045
		var e := 1.0 - pow(x / 0.33, 2.0) - pow((y - 0.3) / 0.224, 2.0)
		var z := -0.241 * sqrt(maxf(e, 0.0)) - 0.006
		var m := _plain(cols[k], 0.0, 0.3, 3.0)
		_leds.append(m)
		var led := _part(torso, _sphere(0.013, -1.0, 8), m, Vector3(x, y, z))
		no_frost.append(led)
	# налобный фонарь
	_part(head, _cyl(0.032, 0.036, 0.06, 12), _armor("steel"), Vector3(0.14, 0.1, -0.11), Vector3(PI * 0.5, 0, 0))
	var lens := _part(head, _sphere(0.026, -1.0, 10), _plain(Color(1.0, 0.95, 0.8), 0.0, 0.2, 4.0), Vector3(0.14, 0.1, -0.142))
	no_frost.append(lens)
	_lamp_light = SpotLight3D.new()
	_lamp_light.light_color = Color(1.0, 0.93, 0.8)
	_lamp_light.light_energy = 1.4
	_lamp_light.spot_range = 11.0
	_lamp_light.spot_angle = 24.0
	_lamp_light.position = Vector3(0.14, 0.1, -0.15)
	_lamp_light.rotation = Vector3(-0.12, 0, 0)
	head.add_child(_lamp_light)
	# номер на левом наплечнике
	_number = Label3D.new()
	_number.text = "01"
	_number.font_size = 56
	_number.pixel_size = 0.0021
	_number.outline_size = 0
	_number.modulate = Color(0.08, 0.08, 0.1)
	_number.shaded = true
	_number.double_sided = false
	_number.position = Vector3(-0.205, -0.005, 0.0)
	_number.rotation = Vector3(0, -PI * 0.5, 0.28)
	(torso.get_node("Pauldron0") as Node3D).add_child(_number)
	# места для мотка верёвки
	_coil_hand = Node3D.new()
	_coil_hand.position = Vector3(0, -HAND, 0)
	_coil_hand.rotation = Vector3(0, 0, PI * 0.5)
	(_arms[0]["hand"] as Node3D).add_child(_coil_hand)
	_coil_belt = Node3D.new()
	_coil_belt.position = Vector3(0.22, -0.07, 0.04)
	_coil_belt.rotation = Vector3(0, 0, PI * 0.5)
	pelvis.add_child(_coil_belt)


func _update_details(_delta: float, st: Dictionary) -> void:
	# шланг: от котла к затылку, мягкая дуга
	var a := pack.global_transform * Vector3(-0.12, 0.2, -0.05)
	var b := head.global_transform * Vector3(-0.11, -0.09, 0.13)
	var back := torso.global_basis.z.normalized()
	var c := (a + b) * 0.5 + back * 0.1 + torso.global_basis.y.normalized() * 0.03
	var n := _hose.size()
	var prev := a
	for k in n:
		var t := float(k + 1) / n
		var q := a.lerp(c, t).lerp(c.lerp(b, t), t)
		var d := q - prev
		var len := d.length()
		if len > 0.0005:
			var y := d / len
			var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
			_hose[k].global_transform = Transform3D(Basis(x, y * len, x.cross(y)), (prev + q) * 0.5)
		prev = q
	# огоньки: зелёный дышит, жёлтый — мало сил, красный — мало корпуса
	var hp: float = st["hp"]
	var stam: float = st["stamina"]
	_leds[0].emission_energy_multiplier = 1.5 + sin(_t * 2.0) * 1.2
	_leds[1].emission_energy_multiplier = 4.0 if stam < 0.3 and fmod(_t, 0.6) < 0.3 else 0.3
	_leds[2].emission_energy_multiplier = 4.0 if hp < 0.4 and fmod(_t, 0.4) < 0.2 else 0.2
	_lamp_light.visible = not bool(st["dead"])
