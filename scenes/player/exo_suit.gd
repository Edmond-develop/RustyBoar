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

enum Mark { BURN, DENT, PIERCE, SCALD, SCRATCH, FROSTBITE, CRUMPLE }
const LIMBS := ["arm_l", "arm_r", "leg_l", "leg_r"]     ## биты маски: 1, 2, 4, 8
enum Mood { NORMAL, HAPPY, HURT, TIRED, OFF, PANIC, FOCUS, DIZZY }
## Смерть по шагам (секунды): трясёт → на колени → тянет руку к небу → падает → удар о снег → последний «блик»
const D_KNEEL := 0.7
const D_REACH := 1.3
const D_FALL := 2.5
const D_HIT := 2.95
const D_BLIP := 3.9
const BOLT_K0 := 0.25         ## Ремонт: с какого прогресса начинаю крутить болты
const BOLT_DK := 0.12         ## …и сколько прогресса на каждый из 4 болтов

const HIP_H := 0.91           ## Высота таза стоя (колени чуть согнуты — пружинистая стойка)
const HIP_X := 0.13           ## Ноги от центра
const THIGH := 0.41
const SHIN := 0.4
const ANKLE_H := 0.11         ## Щиколотка над подошвой
const SHOULDER := Vector3(0.36, 0.40, 0.0)   ## Плечо (от пояса)
const UPPER := 0.3
const FORE := 0.29
const HAND := 0.09            ## От запястья до середины ладони
const GRIP_IN := 0.062       ## Верёвка в кулаке: насколько от середины ладони в сторону пальцев
const HOLD_LOCAL := Vector3(0.0, 0.22, -0.48)   ## Где посылка (от пояса)
const MAX_SPOTS := 8
const FP_PARCEL_TOP := 0.2    ## от 1-го лица: верх посылки (от пояса)
const FP_CLUB_GRIP := Vector3(0.33, -0.34, -0.46)    ## от 1-го лица: кулак с дубинкой
const FP_CLUB_DIR := Vector3(-0.05, 0.5, -0.86)      ## …куда торчит дубинка

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

var limb_mask := 15                   ## какие руки/ноги на месте (LIMBS)
var ice_mask := 0                     ## какие руки/ноги вмёрзли (не двигаются)
var _ice_nodes := {}                  ## вид → [корка на каждом звене]
var _ice_grow := {}                   ## вид → 0..1 (корка нарастает / тает)
var _ice_mat: StandardMaterial3D
var _rime_mat: StandardMaterial3D
var _drag := 0.0                      ## фаза «шаг — подтянуть замёрзшую ногу»
var _antenna: Node3D                  ## антенна (гнётся от ударов, при поломке отлетает)
var _antenna_rb := Basis.IDENTITY
var _dangle: Array[Node3D] = []       ## оборванные провода у локтей и колен (корпус плох)
var _leak: GPUParticles3D             ## свищ: пар из пробитого котла
var _death_steam: GPUParticles3D      ## поломка: котёл стравливает пар
var _death_smoke: GPUParticles3D      ## …и потом дымит
var _death_prev := -1.0
var _broken := false                  ## наплечник, антенна, брелок уже отлетели
var _debris: Array = []               ## {node, parent, xf, vel, spin, roll}
var _drag_fx: Array[GPUParticles3D] = []
var _stumps := {}                     ## вид → {node, sparks, drip, wires}
var _stump_t := 0.0
var _wrench_holster: Node3D
var _wrench_hand: Node3D
var _charm: Node3D                    ## брелок-кабанчик на ранце
var _charm_a := Vector2.ZERO
var _charm_v := Vector2.ZERO
var _knee_leds: Array[StandardMaterial3D] = []
var _hop := 0.0
var _crawl := 0.0
var _strain := {}                     ## меня тянут за руку/ногу: {kind, gap, k, t}
var _belly_now := 0.0                 ## на пузе (для посылки на спине)
var _belly_fx: GPUParticles3D         ## снег из-под груди на пузе
var _belly_ice_fx: GPUParticles3D     ## ледяная крошка
var _sit_pose := 0                    ## сижу: 0 — руки на коленях, 1 — откинулся на руки, 2 — обнял колени, 3 — грею руки
var _sit_pose_t := 0.0
var _sit_hand: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]   ## куда тянутся руки сидя (в осях визуала)
var _sit_lean := 0.0
var _strain_wires: Array[MeshInstance3D] = []
var _wire_snapped := [false, false, false]
var _flying: Array = []               ## вылетевшие болты: {node, vel, spin, life, gy}
var _bolt_mat: StandardMaterial3D
var _recoil_t := 0.0                  ## рванул и отлетел назад с добычей
var _check_t := 0.0                   ## проверяю только что прикрученную руку/ногу
var _check_kind := ""
var _limb_carry := Transform3D.IDENTITY   ## где лежит оторванная деталь у меня на плече
var _limb_carry_ok := false
var _wr := {}                         ## ключ на болте: {head, axis}
var _sweat: GPUParticles3D            ## капли с шлема, когда в панике
var _stars: Node3D                    ## звёздочки над головой, когда плюхнулся
var _vis: Node3D
var _f17: Array = []             ## шаг 80: ноги на ледорубах: [высота левой, правой, тело, кто шагает, t, откуда, куда]
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
var _hold_last: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]          ## последний хват (в осях пояса)
var _hold_last_b: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]
var _hold_raw: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _hold_off: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
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
var _haul_puff_t := 0.0
var _land_t := 0.0
var _prev_spd := 0.0
var _was_lifting := false
var _wind_l := Vector3.ZERO           ## ветер в осях тела, сглаженный
var _wind_arm := -1
var _wind_k := 0.0
var fp_on := false                    ## вид от 1-го лица у своего дрона: руки/дубинка/посылка — «для глаз»
var _fp_show := [0.0, 0.0]            ## шаг 70: насколько рука «в кадре» (ползу, чиню, копаю, верёвка, держу друга)
var _fp_pitch := 0.0
var _fp_yaw := 0.0
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
var _harness: Node3D             ## кольцо на поясе (для крюка)


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
	_optimize_parts.call_deferred()


## Оптимизация: мелочь (заклёпки, пальцы, огоньки) не отбрасывает тень и вдали не рисуется
func _optimize_parts() -> void:
	if _vis == null:
		return
	for n in _vis.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var ab := mi.mesh.get_aabb()
		var sc := mi.global_basis.get_scale()
		var s := maxf(ab.size.x * absf(sc.x), maxf(ab.size.y * absf(sc.y), ab.size.z * absf(sc.z)))
		# шаг 108: строже — у дрона ~400 деталей, каждая — отдельный вызов отрисовки (и ещё раз в тени)
		if s < 0.12:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 26.0
			mi.visibility_range_end_margin = 3.0
		elif s < 0.25:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 50.0
			mi.visibility_range_end_margin = 5.0
		elif s < 0.4:
			mi.visibility_range_end = 90.0
			mi.visibility_range_end_margin = 8.0


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


## Шаг 69: одинаковые детали у всех дронов — одни и те же меши (новый бот строится быстрее, без подвисания)
static var _mcache := {}

static func _sphere(r: float, h := -1.0, seg := 24) -> SphereMesh:
	var key := "s%.5f/%.5f/%d" % [r, h, seg]
	if _mcache.has(key):
		return _mcache[key]
	var s := SphereMesh.new()
	s.radius = r
	s.height = h if h > 0.0 else r * 2.0
	s.radial_segments = seg
	s.rings = maxi(seg / 2, 6)
	_mcache[key] = s
	return s


static func _cyl(top: float, bottom: float, h: float, seg := 18) -> CylinderMesh:
	var key := "c%.5f/%.5f/%.5f/%d" % [top, bottom, h, seg]
	if _mcache.has(key):
		return _mcache[key]
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	_mcache[key] = c
	return c


static func _box(size: Vector3) -> BoxMesh:
	var key := "b%.5f/%.5f/%.5f" % [size.x, size.y, size.z]
	if _mcache.has(key):
		return _mcache[key]
	var b := BoxMesh.new()
	b.size = size
	_mcache[key] = b
	return b


static func _torus(inner: float, outer: float, seg := 24) -> TorusMesh:
	var key := "t%.5f/%.5f/%d" % [inner, outer, seg]
	if _mcache.has(key):
		return _mcache[key]
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = seg
	t.ring_segments = 8
	_mcache[key] = t
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
		_part(torso, _cyl(0.165, 0.165, 0.035), _armor("rubber"), Vector3(0, 0.0 + k * 0.05, 0), Vector3.ZERO, Vector3(0.98, 1.0, 0.82))
	# грудь (шаг 92: тоньше — от 1-го лица не заслоняет взгляд вниз)
	_part(torso, _sphere(0.28), _armor("paint"), Vector3(0, 0.3, 0.02), Vector3.ZERO, Vector3(1.04, 0.8, 0.72), true)
	# нагрудная пластина из светлого металла на клёпках
	var plate := _part(torso, _sphere(0.2), _armor("steel"), Vector3(0, 0.33, -0.15), Vector3.ZERO, Vector3(0.92, 0.6, 0.26), true)
	# шаг 92: ремни разгрузки крест-накрест и пряжка
	for sx in [-1.0, 1.0]:
		_part(torso, _box(Vector3(0.05, 0.36, 0.012)), _armor("rubber", false), Vector3(sx * 0.1, 0.3, -0.19), Vector3(-0.12, 0.0, sx * 0.42))
	_part(torso, _box(Vector3(0.06, 0.05, 0.016)), _plain(Color(0.62, 0.63, 0.66), 0.9, 0.3), Vector3(0, 0.28, -0.2))
	for p in [Vector3(-0.12, 0.4, -0.195), Vector3(0.12, 0.4, -0.195), Vector3(-0.12, 0.26, -0.195), Vector3(0.12, 0.26, -0.195)]:
		_part(torso, _sphere(0.016, -1.0, 8), _plain(Color(0.7, 0.55, 0.28)), p)
	plate.name = "Breastplate"
	# опоясывающий обруч
	_part(torso, _torus(0.275, 0.305), _armor("steel"), Vector3(0, 0.17, 0.02), Vector3.ZERO, Vector3(1.04, 1.0, 0.74))
	# воротник (от 1-го лица своя камера его не рисует — закрывал взгляд вниз)
	var collar := _part(torso, _torus(0.1, 0.17), _armor("steel"), Vector3(0, 0.5, 0))
	collar.name = "Collar"
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
	_antenna_rb = Basis.from_euler(Vector3(-0.25, 0, 0.12))
	_antenna = Node3D.new()
	_antenna.position = Vector3(-0.2, 0.11, 0.06) - _antenna_rb * Vector3(0, 0.12, 0)
	_antenna.basis = _antenna_rb
	head.add_child(_antenna)
	_part(_antenna, _cyl(0.007, 0.01, 0.24, 6), _armor("steel"), Vector3(0, 0.12, 0))
	var tip := _part(_antenna, _sphere(0.02, -1.0, 10), _antenna_mat, _antenna_rb.inverse() * (Vector3(-0.215, 0.23, 0.09) - _antenna.position))
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
	hm.scale = Vector3.ONE * 1.3            # шаг 124: кисть чуть крупнее — не теряется рядом с наручем
	hand.add_child(hm)
	var glove := _armor("steel")
	# шаг 124: кисть — не «коробка»: тёмное ядро ладони, сверху выпуклый щиток в цвет игрока (сплюснутый купол),
	# валик костяшек, скруглённое основание большого пальца, ладонь — резина
	_part(hm, _box(Vector3(0.04, 0.096, 0.094)), glove, Vector3(0, -0.05, 0), Vector3.ZERO, Vector3.ONE, true)
	_part(hm, _sphere(0.05, -1.0, 16), _armor("paint"), Vector3(s * 0.017, -0.05, 0), Vector3.ZERO, Vector3(0.42, 0.98, 1.0))
	var kn := CapsuleMesh.new()
	kn.radius = 0.0145
	kn.height = 0.104
	kn.radial_segments = 10
	kn.rings = 3
	_part(hm, kn, _armor("steel", false), Vector3(s * 0.017, -0.097, 0), Vector3(PI * 0.5, 0, 0))
	_part(hm, _sphere(0.024, -1.0, 12), glove, Vector3(-s * 0.012, -0.034, -0.045), Vector3.ZERO, Vector3(0.9, 1.25, 0.8))
	_part(hm, _box(Vector3(0.008, 0.09, 0.088)), _armor("rubber", false), Vector3(-s * 0.022, -0.05, 0))
	var fingers: Array = []
	var fz := [-0.036, -0.012, 0.012, 0.036]
	var fl := [0.95, 1.05, 1.0, 0.82]
	for k in 4:
		fingers.append(_finger(hm, Vector3(0, -0.1, float(fz[k])), float(fl[k]), 0.0105, s))
		# шаг 124: костяшки — стальные купола над корнем каждого пальца
		_part(hm, _sphere(0.0115, -1.0, 10), _armor("light", false), Vector3(s * 0.027, -0.099, float(fz[k])))
	# манжета запястья: кольцо в цвет игрока, под ним — резиновый сильфон, 6 болтов
	_part(hm, _torus(0.036, 0.05, 16), _armor("paint", false), Vector3(0, -0.004, 0))
	_part(hm, _cyl(0.04, 0.036, 0.022, 14), _armor("rubber", false), Vector3(0, 0.012, 0))
	for rk in 6:
		var ra := TAU * rk / 6.0 + 0.5
		_part(hm, _sphere(0.006, -1.0, 6), _plain(Color(0.7, 0.55, 0.28), 0.9, 0.3), Vector3(cos(ra) * 0.05, -0.004, sin(ra) * 0.05))
	# тыльная пластина: окошко-индикатор (светится цветом состояния) и два ребра жёсткости
	_hand_led = _plain(Color(0.3, 0.95, 1.0), 0.0, 0.4, 2.2) if _hand_led == null else _hand_led
	var led := _part(hm, _box(Vector3(0.004, 0.007, 0.026)), _hand_led, Vector3(s * 0.0375, -0.036, 0.0))
	no_frost.append(led)
	# ладонь: рифлёные накладки-«подушки» у основания пальцев и под большим
	_part(hm, _box(Vector3(0.006, 0.02, 0.086)), _armor("rubber", false), Vector3(-s * 0.027, -0.086, 0))
	# предплечье: два штока-гидроцилиндра по внутренней стороне и кабель к кисти
	for rz2 in [-0.03, 0.03]:
		_part(fore, _cyl(0.008, 0.008, 0.2, 6), _plain(Color(0.78, 0.8, 0.84), 1.0, 0.18), Vector3(-s * 0.07, -0.15, rz2))
		_part(fore, _cyl(0.013, 0.013, 0.07, 8), _armor("steel", false), Vector3(-s * 0.07, -0.08, rz2))
	var th := Node3D.new()
	th.position = Vector3(-s * 0.02, -0.03, -0.052)
	hm.add_child(th)
	var th_root := Node3D.new()
	th_root.rotation = Vector3(0.75, 0, -s * 0.3)
	th.add_child(th_root)
	var th1 := _finger(th_root, Vector3.ZERO, 0.9, 0.012)
	var f1: Array = fingers[0]
	var f2: Array = fingers[2]
	_arms.append({"upper": upper, "fore": fore, "hand": hand, "f1": f1, "f2": f2, "fingers": fingers, "th": th1, "s": s,
		"pauldron": torso.get_node("Pauldron%d" % i)})


## Шаг 92: палец из трёх фаланг (скруглённые, с кольцами суставов); возвращает [сустав1, сустав2, сустав3]
static var _fmesh := {}
var _hand_led: StandardMaterial3D
func _finger(parent: Node3D, pos: Vector3, ln := 1.0, r := 0.0105, s := 0.0) -> Array:
	var mat := _armor("steel", false)
	var lens := [0.036 * ln, 0.026 * ln, 0.02 * ln]
	var joints: Array = []
	var par := parent
	var p := pos
	for k in 3:
		var j := Node3D.new()
		j.position = p
		par.add_child(j)
		var L: float = lens[k]
		var key := "%.4f/%.4f" % [L, r]
		if not _fmesh.has(key):
			var cm := CapsuleMesh.new()
			cm.radius = r * (1.0 - 0.08 * k)
			cm.height = maxf(L + r * 1.6, cm.radius * 2.05)
			cm.radial_segments = 10
			cm.rings = 2
			_fmesh[key] = cm
		_part(j, _fmesh[key], mat, Vector3(0, -L * 0.5, 0))
		if k < 2:
			_part(j, _cyl(r * 1.08, r * 1.08, 0.006, 8), _armor("rubber", false), Vector3(0, -L, 0))
		if s != 0.0:
			# шаг 124: с тыльной стороны — пластинка брони (в цвет игрока на первой фаланге), с ладонной на кончике — подушечка
			if k < 2:
				_part(j, _box(Vector3(0.004, L * 0.72, r * 1.7)), _armor("paint" if k == 0 else "steel", false), Vector3(s * r * 0.85, -L * 0.5, 0))
			else:
				_part(j, _sphere(r * 0.8, r * 1.5, 8), _armor("rubber", false), Vector3(-s * r * 0.45, -L * 0.62, 0))
		joints.append(j)
		par = j
		p = Vector3(0, -L, 0)
	return joints


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
	# на пузе: из-под груди летит снег / ледяная крошка
	_belly_fx = FX.particles(Color(0.95, 0.97, 1.0, 0.85), 40, 0.6, 0.045, 0.8, 2.5, Vector3(0, -6, 0), 40.0, false)
	(_belly_fx.process_material as ParticleProcessMaterial).direction = Vector3(0, 0.6, 1.0)
	_belly_fx.position = Vector3(0, 0.25, -0.25)
	torso.add_child(_belly_fx)
	_belly_ice_fx = FX.particles(Color(0.8, 0.93, 1.0, 1.0), 26, 0.4, 0.018, 1.0, 2.6, Vector3(0, -8, 0), 50.0, false, true)
	(_belly_ice_fx.process_material as ParticleProcessMaterial).direction = Vector3(0, 0.5, 1.0)
	_belly_ice_fx.position = Vector3(0, 0.25, -0.25)
	torso.add_child(_belly_ice_fx)
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
	var side := 1.0 if ((limb_mask & ~ice_mask) & 2) != 0 or ((limb_mask & ~ice_mask) & 1) == 0 else -1.0
	match weight:
		1:
			loc = Vector3((0.21 + ext.x) * side, 0.06, -0.04)    # под мышкой той руки, что работает
		3:
			loc = Vector3(0.0, 0.02, -(0.22 + ext.z))
		_:
			loc = Vector3(0.0, HOLD_LOCAL.y, -(0.2 + ext.z))
	if fp_on:
		# от 1-го лица посылка ниже, у живота: в кадре только её верхний край, центр экрана свободен
		loc.y = minf(loc.y, FP_PARCEL_TOP - ext.y)
	if _belly_now > 0.5:
		# на пузе: посылка лежит на спине поверх ранца
		var tb := tx.basis.orthonormalized()
		return Transform3D(tb * extra_basis, tx * Vector3(0.0, 0.22, 0.44 + ext.z * 0.9) + offset)
	var b := yaw_basis * _carry_sway * extra_basis
	if weight == 1:
		b = b * Basis(Vector3.UP, 0.3 * side)
	return Transform3D(b, tx * loc + offset)


## От 1-го лица: «глаза» — голова, повёрнутая туда, куда смотрит камера (наклон — наполовину,
## чтобы руки не уезжали из кадра, когда смотришь вверх-вниз)
## Точка w — в поле зрения своей камеры (у края кадра, если была за ним); top — как высоко можно (доля верха кадра)
func _fp_into_view(w: Vector3, i: int, top: float, bottom := 0.74) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return w
	var ct := cam.global_transform
	# шаг 93: камера с шага физики (кадровое сглаживание сдвигает её туда-сюда — руки дрожали)
	var fpv: Node = _vis.get_parent().get_node_or_null("FPView") if _vis and _vis.get_parent() else null
	if fpv != null and fpv.get("phys_cam") != null and (fpv.get("phys_cam") as Transform3D) != Transform3D.IDENTITY:
		ct = fpv.get("phys_cam")
	var l := ct.affine_inverse() * w
	var tv := tan(deg_to_rad(cam.fov) * 0.5)
	var vs := get_viewport().get_visible_rect().size
	var th := tv * vs.x / maxf(vs.y, 1.0)
	var d := maxf(-l.z, 0.36)
	var sx := 1.0 if i == 1 else -1.0
	l.z = -d
	l.x = clampf(l.x, -th * 0.8 * d, th * 0.8 * d)
	if l.x * sx < 0.08 * d:
		l.x = sx * 0.08 * d                          # своя рука — со своей стороны
	l.y = clampf(l.y, -tv * bottom * d, tv * top * d)
	return ct * l


func _fp_frame() -> Transform3D:
	var pitch := clampf(_fp_pitch * 0.6, -0.6, 0.45)
	var b := Basis(Vector3.UP, _fp_yaw) * Basis(Vector3.RIGHT, pitch)
	return Transform3D(b, head.global_position)


## Середина ладони (0 — левая, 1 — правая), мировые координаты
func hand_point(i: int) -> Vector3:
	return (_arms[i]["hand"] as Node3D).global_transform * Vector3(0, -HAND, 0)


## Точка внутри сжатого кулака (со стороны ладони) — сюда ложится верёвка
func grip_point(i: int) -> Vector3:
	var s: float = _arms[i]["s"]
	return (_arms[i]["hand"] as Node3D).global_transform * Vector3(-s * GRIP_IN, -HAND - 0.015, 0.0)


## Кольцо на поясе — куда цепляется крюк
func harness_point() -> Vector3:
	return _harness.global_transform * Vector3(0, 0, -0.03) if _harness else torso.global_position


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
		if not _shown_in_suit(mi):
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
var _board: MeshInstance3D = null


func animate(delta: float, st: Dictionary) -> void:
	_t += delta
	var dead: bool = st["dead"]
	var hp: float = st["hp"]
	_update_face(delta, st)
	_update_surface(delta, st)
	_update_details(delta, st)
	_update_limb_details(delta, st)
	_death_fx(delta, st)
	if st["frozen"]:
		return
	# смерть по шагам: 0–0.7 с — ещё стоит, трясёт (отказ систем); 0.7–1.3 — на колени;
	# дальше — лицом в снег (наклон всего тела делает игрок), лежит прямой
	var death_t := float(st.get("death_t", -1.0))
	var in_w: bool = st["swim"] or st["dive"]
	var dying := dead and death_t >= 0.0 and death_t < D_KNEEL and not in_w
	var lying := dead and death_t >= D_FALL and not in_w
	# на коленях тянет руку вверх, дрожит — и рука падает
	var reach_k := 0.0
	if dead and not in_w and death_t >= D_REACH and death_t < D_FALL + 0.2:
		reach_k = smoothstep(D_REACH, D_REACH + 0.5, death_t) * (1.0 - smoothstep(D_FALL - 0.15, D_FALL + 0.15, death_t))
	if dying:
		dead = false
	var downed: bool = st.get("downed", false)
	var carried_limp: bool = downed and st["carried"]
	if downed and not st["carried"]:
		dead = true          # лежит без сил — та же поза, что при поломке
	var vis_tx := _vis.global_transform
	var vel: Vector3 = st["vel"]
	var inv := _vis.global_basis.inverse()
	var lv := inv * Vector3(vel.x, 0.0, vel.z)
	lv.y = 0.0
	var spd := lv.length()
	var carried: bool = st["carried"]
	var tumble: bool = st["tumble"]
	var ride: bool = bool(st.get("ride", false))      # лавина несёт: еду на спине (как сижу, полулёжа)
	var on_floor: bool = (st["on_floor"] or ride) and not carried
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
	if dying:
		stagger = 1.0          # бьёт током, корпус дёргает
	var shake: float = st["shake"]
	var rrole: int = st["rescue_role"]
	var rt: float = st["rescue_t"]
	var clasp: Vector3 = st["clasp"]
	var rp: Dictionary = st["rope"]
	var rope_st: int = int(rp.get("state", 0))
	var rope_anchor: Vector3 = rp.get("anchor", Vector3.ZERO)
	var rope_grip: Vector3 = st.get("rope_grip", Vector3.ZERO)
	var push_pt: Vector3 = st.get("push_point", Vector3.ZERO)
	var wave_help: bool = st["wave"]
	var rip: Dictionary = st.get("rip", {})
	var rep: Dictionary = st.get("repair", {})
	var flop: float = float(st.get("flop", -1.0))
	var cl: Node3D = st.get("carry_limb", null)
	var sit_k: float = float(st.get("sit", 0.0))
	var belly_k: float = float(st.get("belly", 0.0))
	var belly_on := belly_k > 0.5 and not dead and not swim
	var belly_lead: Node3D = st.get("belly_lead", null)
	_belly_now = belly_k
	if belly_on:
		carry = 0            # посылка на спине — руки свободны
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
	fp_on = bool(st.get("fp", false))
	_fp_pitch = float(st.get("fp_pitch", 0.0))
	_fp_yaw = float(st.get("fp_yaw", 0.0))
	_reach_t = maxf(_reach_t - delta, 0.0)
	_skid_t = maxf(_skid_t - delta, 0.0)
	_haul_puff_t = maxf(_haul_puff_t - delta, 0.0)
	_land_t = maxf(_land_t - delta, 0.0)
	_recoil_t = maxf(_recoil_t - delta, 0.0)
	_check_t = maxf(_check_t - delta, 0.0)
	# занос: резко тормозим с бега
	if on_floor and _prev_spd > 7.0 and (_prev_spd - spd) / dt > 16.0 and spd > 1.5:
		_skid_t = 0.4
	_prev_spd = spd
	if st["just_landed"] and float(st["land_speed"]) > 9.0:
		_land_t = 0.45

	# чем сейчас занят (жесты от скуки — только когда ничем)
	var busy: bool = carry > 0 or stick != null or lift != null or carried or tumble or rope_st >= 2 \
		or flop >= 0.0 or not rip.is_empty() or not rep.is_empty() or cl != null or _check_t > 0.0 \
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
	var lift_h := (0.1 + 0.2 * clampf((gait_spd - 3.0) / 8.0, 0.0, 1.0)) * (0.55 if quiet else 1.0) * lerpf(1.0, 0.45, frost)
	if heavy_walk:
		lift_h *= 0.6
	# шаг 124: на бегу стопы ставятся почти в линию (как у бегуна)
	var width := lerpf(0.14, 0.075, clampf((gait_spd - 3.0) / 6.0, 0.0, 1.0))
	if heavy_walk:
		width = 0.2
	var turn_amt := clampf(absf(_yaw_rate) / 3.0, 0.0, 1.0) * (1.0 - _amp)
	_turn_phase += delta * 2.6 * turn_amt
	var run_k := clampf((spd - 5.0) / 5.0, 0.0, 1.0) if on_floor and not heavy_walk else 0.0
	# шаг 124: «спортивность» — трусца (0.35) … спринт (1): захлёст голени, вынос колена, работа рук
	var ath := clampf((spd - 3.2) / 8.0, 0.0, 1.0) * (0.0 if heavy_walk or quiet or limp or frost > 0.5 else 1.0) * _amp

	var foot_t: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var pitch_t: Array[float] = [0.0, 0.0]
	var toe_yaw: Array[float] = [0.0, 0.0]
	var crouch := 0.0
	var lean_t := 0.0
	var roll_t := 0.0
	var twist_t := 0.0
	var pelvis_y := HIP_H
	var air := not on_floor and not swim and not dead and not carried and rrole != 2 and flop < 0.0 and not belly_on
	var to_rope := Vector3.ZERO           ## в осях визуала: куда уходит верёвка
	if rope_st >= 3 and rope_anchor != Vector3.ZERO:
		to_rope = inv * (rope_anchor - _vis.global_position)
		to_rope.y = 0.0
		to_rope = to_rope.normalized() if to_rope.length() > 0.01 else Vector3.FORWARD
	if belly_on:
		# на пузе: ноги вытянуты назад, чуть болтаются; носки скребут снег
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			foot_t[i] = Vector3(s * 0.17, 0.02 + sin(_t * 7.0 + i * PI) * 0.04, 0.03)
			pitch_t[i] = 0.95
		lean_t = -0.08
		roll_t = sin(_t * 4.0) * 0.06
	elif lying:
		# падаю плашмя: тело прямое, ноги вытянуты
		pelvis_y = HIP_H
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			foot_t[i] = Vector3(s * 0.16, 0.0, 0.03)
			pitch_t[i] = 0.9
		lean_t = -0.12
		roll_t = 0.12
	elif dead:
		pelvis_y = 0.55
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			foot_t[i] = Vector3(s * 0.17, 0.0, 0.38 + 0.04 * i)
			pitch_t[i] = -1.2
		lean_t = lerpf(-0.75, 0.05, reach_k) + sin(_t * 23.0) * 0.03 * reach_k
		roll_t = lerpf(0.15, -0.12, reach_k)
		pelvis_y += 0.06 * reach_k
	elif carried_limp:
		# «тушка» без сил: руки и ноги свисают
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			foot_t[i] = Vector3(s * 0.2, 0.3, 0.42 + sin(_t * 2.0 + i) * 0.03)
			pitch_t[i] = 0.6
		lean_t = 0.1
	elif carried:
		# меня держат над головой: брыкаюсь
		var spun := float(st.get("spun", 0.0))
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			var k := _t * 11.0 + i * PI
			foot_t[i] = Vector3(s * 0.17, 0.28 + sin(k) * 0.2, -0.1 + cos(k) * 0.22)
			pitch_t[i] = sin(k) * 0.4
			# шаг 124: раскручивают за щиколотки — ноги вытянуты вместе, носки на себя
			foot_t[i] = foot_t[i].lerp(Vector3(s * 0.1, 0.0, 0.02), spun)
			pitch_t[i] = lerpf(pitch_t[i], -0.25, spun)
		lean_t = -0.1 + sin(_t * 5.0) * 0.1
		roll_t = sin(_t * 7.0) * 0.12
	elif flop >= 0.0:
		# плюхнулся на спину: ноги кверху дрыгаются; потом подтягиваю колени и встаю
		var up_k := smoothstep(0.6, 1.0, flop)
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			var kick := sin(_t * 9.0 + i * PI) * 0.1 * (1.0 - up_k) * (1.0 - smoothstep(0.1, 0.5, flop) * 0.6)
			foot_t[i] = Vector3(s * 0.22, 0.2 + kick, -0.25).lerp(Vector3(s * 0.17, 0.0, 0.05), up_k)
			pitch_t[i] = lerpf(0.5, 0.0, up_k)
		lean_t = lerpf(-0.35, 0.0, up_k)
	elif tumble:
		# бросили: паника! сучу ногами в воздухе, не переворачиваюсь
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			var k := _t * 13.0 + i * PI
			foot_t[i] = Vector3(s * 0.18, 0.3 + sin(k) * 0.2, -0.05 + cos(k) * 0.26)
			pitch_t[i] = sin(k) * 0.6
		lean_t = -0.12 + sin(_t * 6.0) * 0.08
		roll_t = sin(_t * 8.0) * 0.15
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
				# опора: касание серединой стопы, в конце — мощное отталкивание носком
				gpitch = -smoothstep(0.5, 1.0, u) * (0.55 + 0.35 * ath) + (1.0 - smoothstep(0.0, 0.2, u)) * 0.12 * (1.0 - ath)
			else:
				stance = false
				var v := (ph - f) / (1.0 - f)
				var e := v * v * (3.0 - 2.0 * v)
				# шаг 124: бег — стопа сперва задерживается сзади и взлетает к ягодице (захлёст),
				# потом колено выносится вперёд-вверх, перед касанием носок на себя и стопа «загребает» назад
				var e_run := smoothstep(0.12, 0.9, v)
				e = lerpf(e, e_run, ath)
				gp = _move_dir * lerpf(-travel * 0.5, travel * 0.5 * (1.0 + 0.06 * ath), e)
				var kick := sin(PI * clampf(v / 0.55, 0.0, 1.0))
				var knee_up := sin(PI * clampf((v - 0.3) / 0.6, 0.0, 1.0))
				gp.y = (sin(v * PI) * lift_h + ath * (0.3 * kick * kick + 0.1 * knee_up)) * lm
				var p_walk := lerpf(-0.5, 0.3, smoothstep(0.0, 0.7, v)) * (1.0 - smoothstep(0.85, 1.0, v))
				var p_run := lerpf(-1.25, 0.32, smoothstep(0.2, 0.72, v)) * (1.0 - smoothstep(0.88, 1.0, v))
				gpitch = lerpf(p_walk, p_run, ath)
			gp.x += s * width
			if _stance[i] and not stance and running and _amp > 0.5:
				_puff[i] = 1.0
				(_legs[i]["puff"] as GPUParticles3D).restart()
			_stance[i] = stance
			var rest := Vector3(s * (0.22 if exhausted or heavy_walk else 0.15), 0.0, -0.03 if i == 0 else 0.05)
			if rope_st >= 4 and rope_st != 6:
				# стойка с верёвкой: одна нога вперёд, к верёвке; тяну — стойка шире, упираюсь
				var wide := 1.45 if rope_st == 5 else 1.0
				rest = Vector3(s * 0.21, 0.0, 0.0) + to_rope * ((0.22 if i == 1 else -0.21) * wide)
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
			if rope_st == 5 and i == 1 and _amp < 0.3:
				pitch_t[i] = 0.3            # передняя нога: пятка врыта, носок вверх
			if rope_grip != Vector3.ZERO and on_floor:
				# меня волокут на верёвке: еду на пятках, ноги вперёд
				foot_t[i] = Vector3(s * 0.2, 0.0, -0.32 if i == 1 else -0.06)
				pitch_t[i] = 0.45
				if spd > 1.0 and fposmod(_t, 0.18) < delta:
					(_legs[i]["puff"] as GPUParticles3D).restart()
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
				bob_t = (0.085 + 0.035 * ath) * sin(PI * (q - sp) / (1.0 - sp)) * clampf(spd / 5.0, 0.0, 1.0)     # полёт: пружинисто вверх
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
		# шаг 124: корпус — наклон вперёд растёт со скоростью (спринт — заметный), плечи идут в противоход тазу,
		# в поворот — крен как у бегуна на вираже, лёгкая перекачка с ноги на ногу
		lean_t += -(0.05 + 0.2 * clampf(spd / 11.0, 0.0, 1.0) + 0.1 * ath * ath) * _amp
		lean_t += clampf(_acc.z * 0.014, -0.24, 0.24)
		twist_t = sin(TAU * _phase) * (0.12 + 0.13 * ath) * _amp
		roll_t = clampf(-_yaw_rate * spd * 0.016, -0.32, 0.32) + sin(TAU * _phase) * 0.035 * ath
		if heavy_walk:
			roll_t += sin(TAU * _phase) * 0.09 * _amp     # переваливается с ноги на ногу

	if not dead and not swim and not carried and not tumble and flop < 0.0 and rrole == 0:
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
			# шаг 124: раскручиваю друга — откинулся назад противовесом, присел, ноги шире
			var spn := float(st.get("spin", -1.0))
			if spn >= 0.0:
				lean_t += 0.16 + 0.2 * spn
				crouch -= 0.08 + 0.05 * spn
				for li in 2:
					foot_t[li].x += (-1.0 if li == 0 else 1.0) * 0.1
					foot_t[li].y += maxf(sin(TAU * (_turn_phase * 2.0 + li * 0.5)), 0.0) * 0.07
		if stick != null:
			lean_t -= 0.32
			crouch -= 0.1
			twist_t += 0.18
		match rope_st:
			2:
				# раскрутка: чем сильнее, тем сильнее откидываюсь и разворачиваюсь
				var ch := float(rp.get("charge", 0.0))
				lean_t += 0.12 * ch
				twist_t -= 0.2 * ch
				crouch -= 0.05 * ch
			5:
				# рывками: на каждом рывке откидываюсь назад и приседаю
				var hl := float(rp.get("haul", _t * 1.5))
				var pulse := sin(fposmod(hl * 2.0, 1.0) * PI)
				lean_t += 0.3 + 0.16 * pulse
				crouch -= 0.13 + 0.07 * pulse
				twist_t += 0.13 * sin(hl * TAU)
				if pulse > 0.97 and _haul_puff_t <= 0.0:
					_haul_puff_t = 0.25
					_puff[0] = 1.0
					(_legs[0]["puff"] as GPUParticles3D).restart()   # снег из-под упёртой ноги
			6:
				lean_t -= 0.5
				crouch -= 0.06
			7:
				lean_t += 0.38
				crouch -= 0.18
		if not rep.is_empty():
			# прикручиваю: наклонился к гнезду; на разряде отпрянул
			var rpt: Vector3 = rep["socket"]
			var rk0 := float(rep["k"])
			lean_t -= 0.28
			crouch -= 0.3 if rpt.y < _vis.global_position.y + 0.7 else 0.07
			if rk0 > 0.76 and rk0 < 0.84:
				lean_t += 0.4 * sin((rk0 - 0.76) / 0.08 * PI)
		if not rip.is_empty():
			# упёрся ногой в друга и тяну рывками: откидываюсь назад всем корпусом
			var bw := smoothstep(0.04, 0.2, float(rip["k"]))
			var pulse := float(rip["pulse"])
			lean_t += 0.12 + 0.36 * bw + pulse * 0.14
			crouch -= 0.05 + 0.07 * bw
			twist_t += 0.12 * bw
		if _recoil_t > 0.0:
			# рванул — и отлетел назад с добычей
			var rc := sin(PI * (1.0 - _recoil_t / 0.8))
			lean_t += 0.55 * rc
			crouch -= 0.12 * rc
		if push_pt != Vector3.ZERO:
			lean_t -= 0.32          # налегаю на глыбу всем корпусом
			crouch -= 0.1
		if rope_grip != Vector3.ZERO and on_floor:
			lean_t += 0.4           # волокут: откинулся назад, упираюсь
			crouch -= 0.14
		if st.get("balance", false):
			crouch -= 0.14          # присел, пружиню на трещащем льду
			roll_t += sin(_t * 9.0) * 0.12
		var tch := float(st.get("throw_charge", 0.0))
		if tch > 0.0:
			# замах: откидываюсь назад, плечи разворачиваются, присаживаюсь
			lean_t += 0.24 * tch
			twist_t += 0.32 * tch
			crouch -= 0.07 * tch
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
	# порывы сглажены — иначе корпус и рука дёргаются на каждом порыве
	_wind_l = _wind_l.lerp(inv * (st["wind"] as Vector3), clampf(delta * 2.5, 0.0, 1.0))
	var wl := _wind_l
	var wmag := minf(wl.length() / 6.0, 1.0)
	if wmag > 0.05 and not dead and not carried:
		var jit := 0.35 if fp_on else 1.0          # от 1-го лица дрожь мельче — это же камера
		lean_t += clampf(-wl.z * 0.07, -0.35, 0.35) + sin(_t * 33.0) * 0.04 * wmag * jit
		roll_t += clampf(wl.x * 0.07, -0.35, 0.35) + sin(_t * 29.0 + 1.3) * 0.05 * wmag * jit
	if stagger > 0.0:
		roll_t += sin(_t * 28.0) * 0.45 * stagger
		lean_t += 0.25 * stagger
	if frost > 0.4 and not swim and not dead:
		roll_t += sin(_t * 41.0) * 0.03 * frost
	if shake > 0.0:
		roll_t += sin(_t * 48.0) * 0.4 * shake

	# ---------------- без ноги / без ног ----------------
	var work := limb_mask & ~ice_mask     # что на месте и не вмёрзло
	var legs_n := int((work & 4) != 0) + int((work & 8) != 0)
	var arms_n := int((work & 1) != 0) + int((work & 2) != 0)
	var legs_have := int((limb_mask & 4) != 0) + int((limb_mask & 8) != 0)
	var dragging := false
	var one_leg := false
	var crawling := false
	var normal_pose := not dead and not swim and not carried and not tumble and not air and flop < 0.0 and not belly_on
	if legs_n == 1 and legs_have == 2 and normal_pose:
		# одна нога вмёрзла: шагаю живой, а ледяную — прямую, как бревно — волоку за собой
		dragging = true
		var good := 0 if (work & 4) != 0 else 1
		var bad := 1 - good
		var sg: float = _legs[good]["s"]
		var sb: float = _legs[bad]["s"]
		var mv := clampf(spd / 1.2, 0.0, 1.0)
		if spd > 0.2:
			_drag = fposmod(_drag + delta * (0.75 + spd * 0.45), 1.0)
		var ph := _drag
		var step_z := 0.0
		var lift_g := 0.0
		if ph < 0.45:
			# живая нога шагает вперёд
			var u := ph / 0.45
			step_z = lerpf(0.22, -0.32, smoothstep(0.0, 1.0, u))
			lift_g = sin(u * PI) * 0.14
		else:
			# опираюсь на неё и рывком подтягиваю ледяную
			var u2 := (ph - 0.45) / 0.55
			step_z = lerpf(-0.32, 0.22, u2)
		foot_t[good] = Vector3(sg * 0.15, lift_g * mv, step_z * mv)
		pitch_t[good] = -0.25 * lift_g / 0.14 * mv
		var heave := maxf(sin((ph - 0.45) / 0.55 * PI), 0.0) if ph >= 0.45 else 0.0
		foot_t[bad] = Vector3(sb * 0.2, 0.0, (0.34 - 0.1 * heave) * mv + 0.06)
		pitch_t[bad] = 0.35
		pelvis_y = HIP_H - 0.07 + 0.04 * heave * mv
		crouch = -0.02
		roll_t += sg * (0.1 + 0.08 * heave * mv)
		lean_t += 0.12 + 0.1 * heave * mv
		twist_t += sg * 0.15 * mv * (heave - 0.3)
	elif legs_n == 1 and normal_pose:
		# на одной ноге: прыгаю, нога — под тазом, корпус над ней, руки ловят равновесие
		one_leg = true
		var keep := 0 if (work & 4) != 0 else 1
		var sk: float = _legs[keep]["s"]
		if spd > 0.3:
			_hop = fposmod(_hop + delta * (1.7 + spd * 0.35), 1.0)
		else:
			_hop = move_toward(_hop, 0.0, delta * 2.0)
		var air_k := maxf(sin(_hop * TAU), 0.0) if spd > 0.3 else 0.0
		var hop_h := air_k * 0.17
		foot_t[keep] = Vector3(sk * 0.03, hop_h, -0.03 + sin(_hop * TAU) * 0.06 * clampf(spd, 0.0, 1.0))
		pitch_t[keep] = -0.35 * air_k
		pelvis_y = HIP_H - 0.03 + hop_h
		crouch = -0.05 * (1.0 - air_k)
		roll_t += sk * 0.1 + sin(_t * 3.3) * 0.05
		lean_t += 0.04
	elif legs_n == 0 and normal_pose:
		# без ног: лёжа ползу на руках (без рук — извиваюсь)
		crawling = true
		if spd > 0.15:
			_crawl = fposmod(_crawl + delta * (0.8 + spd * 0.9), 1.0)
		pelvis_y = 0.27
		crouch = 0.0
		lean_t = -1.32 + (sin(_crawl * TAU * 2.0) * 0.06 if arms_n == 0 else 0.0)
		roll_t = sin(_crawl * TAU) * (0.1 if arms_n > 0 else 0.25)
		twist_t = sin(_crawl * TAU) * 0.12
		# вмёрзшие ноги — прямые, тянутся по снегу позади
		for li in 2:
			if (limb_mask & (4 << li)) != 0:
				var sl: float = _legs[li]["s"]
				foot_t[li] = Vector3(sl * 0.17, 0.12, 0.86)
				pitch_t[li] = 1.3
	# сижу на снегу: таз опускается, колени вверх, стопы впереди
	if sit_k > 0.001 and normal_pose and not crawling:
		_sit_pose_t -= delta
		if _sit_pose_t <= 0.0 and bool(st.get("sitting", false)):
			_sit_pose_t = randf_range(5.0, 9.0)
			if bool(st.get("sit_fire", false)) and randf() < 0.6:
				_sit_pose = 3
			else:
				_sit_pose = randi() % 3
		if ride:
			_sit_pose = 1                    # откинулся на руки: ладонями цепляюсь за снег
			_sit_pose_t = 1.0
		for i in 2:
			var s := -1.0 if i == 0 else 1.0
			var sf := Vector3(s * 0.21, 0.0, -0.6 + (0.12 if _sit_pose == 2 else 0.0))
			if ride:
				# ноги вперёд по ходу, чуть врозь; на буграх подбрасывает
				sf = Vector3(s * 0.26, 0.06 + sin(_t * 4.3 + i * 1.7) * 0.07, -0.78)
			foot_t[i] = foot_t[i].lerp(sf, sit_k)
			pitch_t[i] = lerpf(pitch_t[i], 0.45, sit_k)
		var dip := sin(sit_k * PI) * 0.06                           # на полпути чуть «падает»
		pelvis_y = lerpf(pelvis_y, 0.25, sit_k) - dip
		crouch *= 1.0 - sit_k
		var sl: float = [-0.06, 0.32, -0.28, -0.12][_sit_pose]
		_sit_lean = lerpf(_sit_lean, sl, clampf(delta * 2.5, 0.0, 1.0))
		lean_t = lerpf(lean_t, _sit_lean, sit_k)
		if not bool(st.get("sitting", false)):
			lean_t -= 0.55 * sin(sit_k * PI)                         # встаю: наклон вперёд, толкаюсь
		roll_t = lerpf(roll_t, sin(_t * 0.7) * 0.03, sit_k)
		twist_t = lerpf(twist_t, sin(_t * 0.37) * 0.08, sit_k)
	# меня тянут за ногу — нога вытягивается к тому, кто тянет
	var ripped: Dictionary = st.get("ripped", {})
	if not ripped.is_empty() and String(ripped.get("kind", "")).begins_with("leg"):
		var li := 0 if ripped["kind"] == "leg_l" else 1
		var to_l: Vector3 = inv * ((ripped["to"] as Vector3) - _vis.global_position)
		foot_t[li] = Vector3(to_l.x * 0.6, clampf(to_l.y * 0.6, 0.1, 0.6), to_l.z * 0.6)
		pitch_t[li] = 0.4
	if not ripped.is_empty():
		roll_t += sin(_t * 31.0) * 0.06
		lean_t += sin(_t * 23.0) * 0.05
		# меня тянут к себе: наклоняюсь в сторону тянущего
		var tl: Vector3 = inv * ((ripped["to"] as Vector3) - _vis.global_position)
		lean_t += clampf(tl.z * 0.3, -0.3, 0.3) * clampf(float(ripped.get("k", 0.5)) * 2.0, 0.0, 1.0)
	# отрываю: правой ногой упираюсь другу в живот, левая — сзади, упор
	if not rip.is_empty() and legs_n == 2 and normal_pose:
		var bw2 := smoothstep(0.04, 0.2, float(rip["k"]))
		var bl: Vector3 = inv * ((rip["brace"] as Vector3) - _vis.global_position)
		var hip_l := Vector3(HIP_X, HIP_H + crouch - 0.05, 0.0)
		var dv := bl - hip_l
		if dv.length() > 0.8:
			bl = hip_l + dv.normalized() * 0.8
		foot_t[1] = foot_t[1].lerp(bl, bw2)
		pitch_t[1] = lerpf(pitch_t[1], 1.15, bw2)
		foot_t[0] = foot_t[0].lerp(Vector3(-0.17, 0.0, 0.2), bw2)
	# проверяю прикрученную ногу: пара пинков и притопов
	if _check_t > 0.0 and _check_kind.begins_with("leg") and normal_pose and legs_n == 2:
		var li2 := 0 if _check_kind == "leg_l" else 1
		var ck := 1.0 - _check_t / 1.5
		var kk := maxf(sin(ck * TAU * 2.0), 0.0)
		foot_t[li2] = Vector3(-0.15 if li2 == 0 else 0.15, 0.28 * kk, -0.22 * kk)
		pitch_t[li2] = -0.5 * kk

	# шаг 73: позы на Пике (подсадка, стена, вылезти на уступ, подтянуть, ворот, оттяжка, дрова)
	var mp := int(st.get("mpose", 0))
	if mp != 17:
		_f17.clear()
	if mp > 0 and not dead and not swim and not carried and legs_n == 2:
		var mk := float(st.get("mpose_k", 0.0))
		var mmov := bool(st.get("climb_moving", false))
		match mp:
			1, 2, 12:
				# на стене / лестнице: ноги по очереди ищут опору, корпус прижат к скале
				for li2 in 2:
					var sl2 := -1.0 if li2 == 0 else 1.0
					var cph := fposmod(_t * (1.6 if mmov else 0.0) + li2 * 0.5, 1.0)
					foot_t[li2] = Vector3(sl2 * 0.2, 0.32 + 0.22 * maxf(sin(cph * TAU), 0.0) - 0.1 * li2, 0.12)
					pitch_t[li2] = -0.35
				lean_t = 0.12
				crouch = -0.05
			3:
				# подсаживаю: присел, ноги широко, корпус вперёд
				for li3 in 2:
					var sl3 := -1.0 if li3 == 0 else 1.0
					foot_t[li3] = Vector3(sl3 * 0.3, 0.0, 0.06 * sl3)
					pitch_t[li3] = 0.0
				crouch = -0.34
				lean_t = -0.32
			4:
				# шаг 75: друг встал в ладони — принимаю вес, приседаю глубже, взрывом разгибаюсь,
				# подпрыгиваю на носках с руками над головой, потом опускаюсь
				var cr4 := -0.38
				var ln4 := -0.36
				var toe := 0.0
				if mk >= 0.0 and mk < 0.35:
					var a4 := mk / 0.35
					cr4 = lerpf(-0.38, -0.54, a4)
					ln4 = lerpf(-0.36, -0.44, a4)
				elif mk >= 0.35 and mk < 0.8:
					var b4 := smoothstep(0.0, 1.0, (mk - 0.35) / 0.45)
					cr4 = lerpf(-0.54, 0.06, b4)
					ln4 = lerpf(-0.44, 0.1, b4)
					toe = b4 * 0.5
				elif mk >= 0.8 and mk < 1.15:
					var c4 := (mk - 0.8) / 0.35
					cr4 = 0.06 + 0.13 * sin(c4 * PI)
					ln4 = lerpf(0.1, -0.12, c4)
					toe = 1.0 - 0.4 * c4
				elif mk >= 1.15:
					var d4 := clampf((mk - 1.15) / 0.52, 0.0, 1.0)
					cr4 = lerpf(0.02, -0.06, d4)
					ln4 = lerpf(-0.12, 0.0, d4)
				for li4 in 2:
					var sl4 := -1.0 if li4 == 0 else 1.0
					foot_t[li4] = Vector3(sl4 * 0.3, 0.07 * toe, 0.06 * sl4)
					pitch_t[li4] = -0.35 * toe
				crouch = cr4
				lean_t = ln4
			5:
				# шаг 76: меня подсаживают. 0–0.25 — правую ногу поднимаю в его ладони (левая на снегу);
				# 0.25–0.75 — стою правой в ладонях, он поднимает: нога выпрямляется, левая поджата;
				# 0.75–1 — оттолкнулся: лечу, ноги вместе, чуть согнуты
				if mk < 0.25:
					var a5 := mk / 0.25
					foot_t[1] = Vector3(0.1, 0.42 * a5, -0.25 * a5)
					pitch_t[1] = 0.25 * a5
					foot_t[0] = Vector3(-0.15, 0.0, 0.05 * a5)
					crouch = -0.06 * a5
					lean_t = 0.18 * a5
				elif mk < 0.75:
					var s5 := (mk - 0.25) / 0.5
					foot_t[1] = Vector3(0.1, 0.42 * (1.0 - s5), -0.25 * (1.0 - s5))
					pitch_t[1] = 0.25 * (1.0 - s5)
					foot_t[0] = Vector3(-0.15, 0.05 + 0.3 * s5, 0.12 + 0.05 * s5)
					pitch_t[0] = 0.5 * s5
					crouch = lerpf(-0.12, 0.0, s5)
					lean_t = lerpf(0.18, 0.02, s5)
				else:
					var f5 := (mk - 0.75) / 0.25
					foot_t[0] = Vector3(-0.14, 0.18 - 0.08 * f5, 0.1)
					foot_t[1] = Vector3(0.14, 0.12 - 0.06 * f5, 0.04)
					pitch_t[0] = 0.35
					pitch_t[1] = 0.3
					lean_t = 0.05
			6:
				# вылезаю: сначала вишу на руках (ноги болтаются), потом колено на край — встаю
				if mk < 0.55:
					foot_t[0] = Vector3(-0.16, -0.05 + 0.06 * sin(_t * 9.0), 0.12)
					foot_t[1] = Vector3(0.16, -0.02 + 0.06 * sin(_t * 9.0 + 1.5), 0.05)
					pitch_t[0] = 0.5
					pitch_t[1] = 0.5
					lean_t = 0.2
				else:
					var mk2 := (mk - 0.55) / 0.45
					foot_t[0] = Vector3(-0.17, lerpf(0.55, 0.0, mk2), lerpf(-0.35, 0.0, mk2))
					foot_t[1] = Vector3(0.17, lerpf(0.0, 0.0, mk2), lerpf(0.35, 0.0, mk2))
					pitch_t[0] = lerpf(-0.6, 0.0, mk2)
					crouch = lerpf(-0.3, 0.0, mk2)
					lean_t = lerpf(-0.6, 0.0, mk2)
			7:
				# лёг у края на колени, тянусь вниз
				for li7 in 2:
					var sl7 := -1.0 if li7 == 0 else 1.0
					foot_t[li7] = Vector3(sl7 * 0.2, 0.0, 0.5)
					pitch_t[li7] = 1.1
				crouch = -0.42
				lean_t = -0.95
			8:
				for li8 in 2:
					var sl8 := -1.0 if li8 == 0 else 1.0
					foot_t[li8] = Vector3(sl8 * 0.16, 0.1 + 0.12 * maxf(sin(_t * 8.0 + li8 * PI), 0.0), 0.1)
					pitch_t[li8] = 0.3
				lean_t = 0.15
			24:
				# траверс: ноги врозь на несущем канате, присел, корпус к перилам; шаг — приставной
				var st24 := sin(PI * clampf(mk - floor(mk), 0.0, 1.0)) * 0.08
				foot_t[0] = Vector3(-0.26 - st24, 0.0, 0.12)
				foot_t[1] = Vector3(0.26 + st24, 0.0, 0.12)
				crouch -= 0.14
				lean_t += 0.2
			23:
				if mk >= 2.0:
					# бросок: шаг вперёд, корпус за руками
					var kt := smoothstep(2.05, 2.4, mk)
					foot_t[0] = Vector3(-0.2, 0.0, -0.25 * kt)
					foot_t[1] = Vector3(0.2, 0.0, 0.15 * kt)
					lean_t += 0.25 * kt
				elif mk >= 1.0:
					# кладу доски: присел на колено, корпус вперёд
					var kd23 := smoothstep(1.0, 1.3, mk)
					foot_t[0] = Vector3(-0.22, 0.0, -0.2 * kd23)
					foot_t[1] = Vector3(0.22, 0.0, 0.26 * kd23)
					crouch -= 0.42 * kd23
					lean_t += 0.4 * kd23
			9:
				crouch -= 0.1
				lean_t -= 0.2 + 0.08 * sin(mk * TAU)
			25:
				# шаг 106: обвязываюсь — чуть присел, корпус вперёд (смотрю на узел)
				crouch -= 0.06
				lean_t -= 0.1 + 0.12 * smoothstep(0.3, 0.45, mk)
				foot_t[0] = Vector3(-0.2, 0.0, -0.08)
				foot_t[1] = Vector3(0.2, 0.0, 0.1)
			27:
				# шаг 110: держусь в кабине — ноги враспор (кабину качает)
				foot_t[0] = Vector3(-0.22, 0.0, -0.06)
				foot_t[1] = Vector3(0.22, 0.0, 0.08)
				crouch -= 0.05
			28:
				# шаг 115: заколачиваю пробоину молотком — ноги враспор, на ударе корпус подаётся к стене
				var c28 := fposmod(mk, 1.0)
				var st28 := smoothstep(0.45, 0.6, c28) * (1.0 - smoothstep(0.66, 0.95, c28))
				foot_t[0] = Vector3(-0.2, 0.0, -0.14)
				foot_t[1] = Vector3(0.22, 0.0, 0.16)
				crouch -= 0.05 + 0.05 * st28
				lean_t -= 0.05 + 0.12 * st28
				var ty28 := (st.get("mpose_pt", Vector3(0, 1.3, 0)) as Vector3).y
				crouch -= clampf((1.3 - ty28) * 0.6, 0.0, 0.26)
			29:
				# шаг 115: сварка на крыше — на колене у крепления троса
				foot_t[0] = Vector3(-0.2, 0.0, -0.1)
				foot_t[1] = Vector3(0.22, 0.0, 0.26)
				crouch -= 0.42
				lean_t += 0.4
			26:
				# шаг 106: кручу рукоять лебёдки: ноги враспор, корпус ходит за рукоятью
				foot_t[0] = Vector3(-0.22, 0.0, -0.16)
				foot_t[1] = Vector3(0.22, 0.0, 0.2)
				crouch -= 0.1 + 0.05 * cos(mk * TAU)
				lean_t -= 0.12 + 0.07 * sin(mk * TAU)
			10:
				foot_t[0] = Vector3(-0.2, 0.0, -0.32)
				foot_t[1] = Vector3(0.2, 0.0, 0.22)
				lean_t += 0.42
				crouch -= 0.16
			11:
				foot_t[0] = Vector3(-0.2, 0.0, -0.18)
				foot_t[1] = Vector3(0.2, 0.0, 0.16)
				lean_t += 0.18
				crouch -= 0.1
			13:
				lean_t += 0.1
			30:
				# шаг 122: леплю снежок — присел на одно колено, корпус к снегу; в конце встаю
				var d30 := smoothstep(0.0, 0.18, mk) * (1.0 - smoothstep(0.78, 1.0, mk))
				foot_t[0] = Vector3(-0.19, 0.0, -0.2 * d30)
				foot_t[1] = Vector3(0.21, 0.0, 0.3 * d30)
				crouch -= 0.5 * d30
				lean_t += 0.45 * d30 + 0.05 * sin(mk * 26.0) * d30
			31:
				# шаг 122: бросок снежка — замах (корпус назад), шаг левой вперёд, бросок (корпус вперёд), доводка
				var w31 := smoothstep(0.0, 0.45, mk) * (1.0 - smoothstep(0.45, 0.6, mk))
				var f31 := smoothstep(0.45, 0.62, mk) * (1.0 - smoothstep(0.75, 1.0, mk))
				if not mmov:
					foot_t[0] = Vector3(-0.2, 0.0, -0.32 * maxf(w31, f31))
					foot_t[1] = Vector3(0.22, 0.0, 0.16 * maxf(w31, f31))
				lean_t += -0.16 * w31 + 0.3 * f31
				crouch -= 0.06 * w31 + 0.1 * f31
			32:
				# шаг 122: вишу на ноге друга — ноги болтаются, носки вниз, раскачиваюсь
				for li32 in 2:
					var sl32 := -1.0 if li32 == 0 else 1.0
					foot_t[li32] = Vector3(sl32 * 0.13 + 0.05 * sin(_t * 1.7 + li32), 0.06 + 0.05 * li32, 0.05 * sin(_t * 2.3 + li32 * 1.4))
					pitch_t[li32] = 0.45
				lean_t = -0.08 + 0.05 * sin(_t * 1.7)
			17:
				# шаг 80: вишу на ледорубах — носки (кошки) вбиты в скалу. Ноги «держатся» за скалу на своей высоте:
				# тело подтянулось — ноги отстали; отстала сильно — переставляю её выше (по одной), с ударом носком
				var kk17 := int(mk)
				var swc17 := (kk17 / 10000) % 10
				var ph17l := float(kk17 / 100000) / 99.0 if swc17 > 0 else 0.0
				var yb := _vis.global_position.y
				if _f17.is_empty() or absf(yb - float(_f17[2])) > 2.5:
					_f17 = [yb + 0.12, yb + 0.2, yb, -1, 0.0, 0.0, 0.0]
				_f17[2] = yb
				var stp := int(_f17[3])
				if stp < 0:
					var lo := 0 if float(_f17[0]) < float(_f17[1]) else 1
					if float(_f17[lo]) - yb < -0.16:
						stp = lo
						_f17[3] = lo
						_f17[4] = 0.0
						_f17[5] = float(_f17[lo])
						_f17[6] = yb + randf_range(0.14, 0.3)
				for li17 in 2:
					var sl17 := -1.0 if li17 == 0 else 1.0
					var out17 := 0.0
					var up17 := 0.0
					if stp == li17:
						var t17 := float(_f17[4])
						var e17 := smoothstep(0.0, 1.0, t17)
						_f17[li17] = lerpf(float(_f17[5]), float(_f17[6]), e17)
						out17 = sin(t17 * PI) * 0.16 - (0.06 if t17 > 0.85 else 0.0)
						up17 = sin(t17 * PI) * 0.12
					_f17[li17] = clampf(float(_f17[li17]), yb - 0.45, yb + 0.42)
					var rel := float(_f17[li17]) - yb
					foot_t[li17] = Vector3(sl17 * 0.2, 0.06 + rel + up17, -0.3 + out17)
					pitch_t[li17] = -0.25 - out17 * 1.5
				if stp >= 0:
					_f17[4] = float(_f17[4]) + delta / 0.3
					if float(_f17[4]) >= 1.0:
						_f17[3] = -1
				# замах — корпус откидывается от скалы, удар — подаётся вперёд
				var lean17 := 0.0
				if swc17 > 0:
					lean17 = -0.16 * smoothstep(0.1, 0.5, ph17l) * (1.0 - smoothstep(0.55, 0.7, ph17l)) + 0.1 * sin(clampf((ph17l - 0.55) / 0.3, 0.0, 1.0) * PI)
				lean_t = 0.08 + lean17
				crouch = -0.05
			19:
				# шаг 80: вылезаю на ледорубах: ноги шагают по скале вверх → колено на край → встаю
				if mk < 0.5:
					var w19 := mk / 0.5
					for li19 in 2:
						var sl19 := -1.0 if li19 == 0 else 1.0
						var st19 := maxf(sin(w19 * PI * 2.0 + li19 * PI), 0.0)
						foot_t[li19] = Vector3(sl19 * 0.2, 0.15 + 0.3 * w19 + 0.22 * st19, -0.3 + 0.1 * st19)
						pitch_t[li19] = -0.3
					lean_t = 0.25 + 0.2 * w19
				elif mk < 0.78:
					var k19 := smoothstep(0.0, 1.0, (mk - 0.5) / 0.28)
					foot_t[0] = Vector3(-0.17, lerpf(0.45, 0.62, k19), lerpf(-0.3, -0.42, k19))
					foot_t[1] = Vector3(0.17, lerpf(0.4, 0.1, k19), lerpf(-0.3, 0.2, k19))
					pitch_t[0] = -0.6
					pitch_t[1] = 0.3
					crouch = lerpf(0.0, -0.35, k19)
					lean_t = lerpf(0.45, 0.55, k19)
				else:
					var m19 := smoothstep(0.0, 1.0, (mk - 0.78) / 0.22)
					foot_t[0] = Vector3(-0.17, lerpf(0.62, 0.0, m19), lerpf(-0.42, -0.05, m19))
					foot_t[1] = Vector3(0.17, lerpf(0.1, 0.0, m19), lerpf(0.2, 0.05, m19))
					pitch_t[0] = lerpf(-0.6, 0.0, m19)
					crouch = lerpf(-0.35, 0.0, m19)
					lean_t = lerpf(0.55, 0.0, m19)
			20:
				# шаг 86: тычу щупом — шаг вперёд, наклон на тычке
				var k20 := smoothstep(0.3, 0.5, mk) * (1.0 - smoothstep(0.75, 1.0, mk))
				foot_t[0] = Vector3(-0.19, 0.0, -0.22 * k20)
				foot_t[1] = Vector3(0.19, 0.0, 0.12 * k20)
				lean_t += 0.35 * k20 + 0.08
				crouch -= 0.12 * k20
			21:
				# шаг 87: на животе. Тащит — ноги волочатся, носками скребу снег; удержал — ноги врозь, кошки в снегу
				if belly_on:
					var drag21 := mk < 0.5
					# шаг 94: держу, но сползаю — носками кошек упираюсь в снег по очереди
					var slide21 := clampf(float(st.get("belly_spd", 0.0)) / 0.4, 0.0, 1.0) if not drag21 else 0.0
					for li21 in 2:
						var sl21 := -1.0 if li21 == 0 else 1.0
						var kick := sin(_t * 9.0 + li21 * PI) * 0.06 if drag21 else sin(_t * 4.5 + li21 * PI) * 0.035 * slide21
						foot_t[li21] = Vector3(sl21 * (0.16 if drag21 else 0.27), 0.02 + maxf(kick, 0.0), 0.03 - kick * 0.5)
						pitch_t[li21] = 1.2 if not drag21 else 0.95
					lean_t = -0.08
					roll_t = sin(_t * 6.0) * 0.08 if drag21 else 0.0
				else:
					crouch = -0.3
					lean_t = 0.4
			22:
				# шаг 86: вишу на верёвке в трещине — кошками в стену, перехват — колени вверх по очереди
				var hi22 := int(mk)
				var ph22 := mk - float(hi22)
				var lift22 := sin(clampf(ph22, 0.0, 1.0) * PI)
				if mk >= 3.0:
					# шаг 88: вишу на весу в широкой трещине: ноги свободно, носки вниз; тянут — поджимаю
					var c22 := mk - 3.0
					var tuck := 0.1 * sin(PI * clampf(c22 / 0.5, 0.0, 1.0)) if c22 > 0.0 and c22 < 0.5 else 0.0
					for lf3 in 2:
						var slf3 := -1.0 if lf3 == 0 else 1.0
						foot_t[lf3] = Vector3(slf3 * 0.15, 0.06 + tuck + 0.03 * sin(_t * 1.7 + lf3), 0.06 + 0.04 * sin(_t * 1.3 + lf3 * 2.0))
						pitch_t[lf3] = 0.35
					lean_t = 0.02
				elif mk >= 2.0:
					# лечу вниз: ноги болтаются, поджимаю
					for lf in 2:
						var slf := -1.0 if lf == 0 else 1.0
						foot_t[lf] = Vector3(slf * 0.24, 0.25 + 0.2 * sin(_t * 14.0 + lf * 2.0), 0.1 * cos(_t * 11.0 + lf))
						pitch_t[lf] = 0.3
					lean_t = -0.15
				else:
					# шаг 136: лезу по верёвке: рука тянется вверх — та же нога шагает выше по стене, корпус чуть
					# отклоняется назад; рука тянет — нога толкает вниз, корпус подаётся к верёвке
					var reach22 := smoothstep(0.0, 0.4, ph22)
					var pull22 := smoothstep(0.52, 1.0, ph22)
					for li22 in 2:
						var sl22 := -1.0 if li22 == 0 else 1.0
						var up22 := 0.0
						if li22 == hi22:
							up22 = 0.3 * reach22 * (1.0 - pull22)
						else:
							up22 = 0.3 * (1.0 - smoothstep(0.0, 0.35, ph22)) * 0.4
						foot_t[li22] = Vector3(sl22 * 0.2, 0.18 + up22, -0.3 - up22 * 0.35)
						pitch_t[li22] = -0.3 - up22 * 0.6
					lean_t = 0.04 - 0.07 * reach22 * (1.0 - pull22) + 0.1 * pull22
					crouch -= 0.06 * reach22 * (1.0 - pull22)
				crouch = -0.06
			14:
				# шаг 74: ставлю деталь — подался вперёд, колени чуть согнуты; на болтах — упор ногой
				lean_t += 0.2
				crouch -= 0.08 + 0.04 * float(mk > 0.6)
				if mk > 0.6:
					foot_t[0] = Vector3(-0.2, 0.0, -0.22)
					foot_t[1] = Vector3(0.2, 0.0, 0.2)
			15:
				# тяну рычаг на себя: ноги враспор, корпус откидывается назад
				foot_t[0] = Vector3(-0.2, 0.0, -0.3)
				foot_t[1] = Vector3(0.2, 0.0, 0.26)
				lean_t -= 0.1 + 0.3 * mk
				crouch -= 0.14
			16:
				# качаю мехи: приседаю в такт
				var pk := sin(mk * TAU)
				for li16 in 2:
					var sl16 := -1.0 if li16 == 0 else 1.0
					foot_t[li16] = Vector3(sl16 * 0.24, 0.0, 0.08 * sl16)
				crouch -= 0.18 + 0.1 * pk
				lean_t += 0.32 + 0.08 * pk
			50:
				# шаг 140: вишу на перекладине подъёмника: ноги свободно висят, носки вниз, слегка болтаются
				for li50 in 2:
					var sl50 := -1.0 if li50 == 0 else 1.0
					var ph50 := _t * 1.3 + li50 * 1.9
					foot_t[li50] = Vector3(sl50 * 0.11, 0.03 + 0.05 * maxf(sin(ph50), 0.0) + 0.03 * li50, 0.06 * sin(ph50 * 0.8) - 0.03)
					pitch_t[li50] = 0.6
				lean_t = 0.03
				crouch = 0.03
				roll_t = 0.0
			51:
				# шаг 140: на сноуборде (нос — +X): ноги на креплениях, колени согнуты и смотрят к носу,
				# таз низко, корпус слегка вперёд и раскрыт к носу; кант — наклон к пяткам/носкам;
				# mpose_pt = (кант, присед, захват), mpose_k = 1 в воздухе
				var bp: Vector3 = st.get("mpose_pt", Vector3.ZERO)
				var air51 := mk > 0.5
				var tuck := clampf(bp.y, 0.0, 1.0)
				var fl := 0.0
				if air51:
					fl = 0.26 + 0.12 * bp.z
				for li51 in 2:
					var sl51 := -1.0 if li51 == 0 else 1.0
					foot_t[li51] = Vector3(sl51 * 0.27, fl, 0.0)
					pitch_t[li51] = 0.0
				crouch = -0.2 - 0.18 * tuck - (0.14 + 0.12 * bp.z if air51 else 0.0) + 0.012 * sin(_t * 2.3)
				lean_t = 0.1 + 0.14 * tuck + clampf(bp.x, -1.0, 1.0) * 0.1 + (0.2 * bp.z if air51 else 0.0)
				twist_t = 0.14
				roll_t = -0.04
			52:
				# шаг 139: кувырок — сгруппировался (k — фаза: 0–1.1 кувырок, …1.45 лежу, …1.9 встаю)
				var g52 := 1.0 - smoothstep(1.45, 1.85, mk)
				for li52 in 2:
					var sl52 := -1.0 if li52 == 0 else 1.0
					foot_t[li52] = Vector3(sl52 * 0.16, 0.42 * g52, -0.3 * g52)
					pitch_t[li52] = 0.5 * g52
				crouch = -0.34 * g52
				lean_t = 0.5 * g52
	for li in 2:
		var bad_leg := (ice_mask & (4 << li)) != 0 and (limb_mask & (4 << li)) != 0
		_drag_fx[li].emitting = bad_leg and (dragging or crawling) and spd > 0.25 and on_floor

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
	if on_floor and not swim and flop < 0.0 and not dead and not belly_on and int(st.get("mpose", 0)) != 51:
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
	elif rope_st >= 3 and rope_st != 6 and rope_anchor != Vector3.ZERO:
		# смотрю туда, куда уходит верёвка (на друга, груз, конец)
		var ta := inv * (rope_anchor - head.global_position)
		look_yaw = clampf(atan2(-ta.x, -ta.z), -1.1, 1.1)
		look_pitch = clampf(atan2(ta.y, Vector2(ta.x, ta.z).length()) * 0.8, -0.6, 0.4)
	if rrole != 0 and clasp != Vector3.ZERO:
		var tc := inv * (clasp - head.global_position)
		look_yaw = clampf(atan2(-tc.x, -tc.z), -1.1, 1.1)
		look_pitch = clampf(atan2(tc.y, Vector2(tc.x, tc.z).length()) * 0.8, -0.6, 0.5)
	if carried:
		look_yaw = sin(_t * 3.0) * 0.6
	if tumble:
		look_yaw = sin(_t * 11.0) * 0.8     # паника: озираюсь
		look_pitch = 0.25
	if ride:
		look_yaw = sin(_t * 0.9) * 0.45     # смотрю, куда несёт (вперёд, поверх ног)
		look_pitch = -0.5 + sin(_t * 1.7) * 0.08
	if belly_on:
		look_yaw = sin(_t * 1.3) * 0.25
		look_pitch = 1.05                   # голову задрал — смотрю вперёд по ходу
	elif sit_k > 0.5:
		look_yaw = sin(_t * 0.31) * 0.7 + sin(_t * 0.83) * 0.2
		look_pitch = 0.05 + sin(_t * 0.5) * 0.1
		if _sit_pose == 3:
			look_yaw = 0.0
			look_pitch = -0.3
	if not rip.is_empty() or not rep.is_empty():
		var lpt: Vector3 = rip["grip"] if not rip.is_empty() else rep["socket"]
		var tl2 := inv * (lpt - head.global_position)
		look_yaw = clampf(atan2(-tl2.x, -tl2.z), -1.1, 1.1)
		look_pitch = clampf(atan2(tl2.y, Vector2(tl2.x, tl2.z).length()) * 0.8, -0.6, 0.4)
	if _check_t > 0.0 and _check_kind != "":
		look_yaw = 0.6 * (-1.0 if _check_kind.ends_with("_r") else 1.0)
		look_pitch = -0.1 if _check_kind.begins_with("arm") else -0.5
	if dead:
		look_yaw = lerpf(0.3, 0.35, reach_k)
		look_pitch = lerpf(-0.6, 0.55, reach_k)
	if mp == 51:
		look_yaw = -0.95
		look_pitch = -0.15
	_head_yaw = lerpf(_head_yaw, look_yaw, clampf(delta * 6.0, 0.0, 1.0))
	_head_pitch = lerpf(_head_pitch, look_pitch - _lean * 0.7, clampf(delta * 8.0, 0.0, 1.0))
	neck.rotation = Vector3(_head_pitch, _head_yaw + _twist * 0.8, -_roll * 0.6)

	# ---------------- ноги (ИК) ----------------
	var fwd := -_vis.global_basis.z
	for i in 2:
		if (limb_mask & (4 << i)) == 0:
			continue
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
		var hip := pelvis.global_transform * Vector3(s * HIP_X, -0.05, 0.0) + _strain_gap(LIMBS[2 + i])
		var side := _vis.global_basis.x * s
		var up_v := _vis.global_basis.y
		var pole := hip + fwd * 0.9 + side * 0.12 - up_v * 0.2
		if sit_k > 0.001:
			pole = pole.lerp(hip + fwd * 0.45 + side * 0.15 + up_v * 1.0, sit_k)
		if (ice_mask & (4 << i)) != 0:
			# вмёрзшая нога не гнётся: ставлю ступню на вытянутую ногу
			var dl := ankle - hip
			ankle = hip + dl.normalized() * (THIGH + SHIN - 0.004)
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

	# шаг 139: сноуборд под ногами
	var on_board := mp == 51
	if on_board and _board == null:
		_board = MeshInstance3D.new()
		var hill_sc = load("res://scenes/world/snow_hill.gd")
		_board.mesh = hill_sc.make_board_mesh()
		_board.name = "Snowboard"
		add_child(_board)
	if _board != null:
		_board.visible = on_board
		if _board.visible:
			var b0 := (_legs[0]["boot"] as Node3D).global_position
			var b1 := (_legs[1]["boot"] as Node3D).global_position
			var vb := _vis.global_basis.orthonormalized()
			_board.global_transform = Transform3D(vb, (b0 + b1) * 0.5 - vb.y * 0.105)

	# ---------------- руки ----------------
	var tx := torso.global_transform
	var up := _vis.global_basis.y
	var right := _vis.global_basis.x
	var parcel: Node3D = st["parcel"]
	var carry_tx := Transform3D.IDENTITY
	if carry == 1:
		carry_tx = carry_transform(st["carry_basis"], st["carry_offset"], weight, extents(parcel))
	# рука от ветра: какая — с запасом (ветер в лоб не перекидывает её туда-сюда), поднимается
	# и опускается плавно; другую поднимаю, только когда первая опустилась. От 1-го лица — не закрываюсь.
	var wind_tw := 0.0
	var want_arm := _wind_arm
	if wmag > 0.45 and carry == 0 and stick == null and not swim and not dead and lift == null and rope_st < 2 \
			and rrole == 0 and cl == null and not fp_on:
		wind_tw = clampf((wmag - 0.45) / 0.3, 0.0, 1.0)
		var side := 1 if wl.x <= 0.0 else 0
		if _wind_arm < 0 or (side != _wind_arm and absf(wl.x) > wl.length() * 0.35):
			want_arm = side
	if want_arm != _wind_arm:
		wind_tw = 0.0
		if _wind_k < 0.05:
			_wind_arm = want_arm
	if _wind_arm >= 0 and (limb_mask & (1 << _wind_arm)) == 0:
		wind_tw = 0.0
	_wind_k = move_toward(_wind_k, wind_tw, delta * (1.6 if wind_tw > _wind_k else 1.1))
	var wind_arm := _wind_arm if _wind_k > 0.001 else -1
	var wind_w := smoothstep(0.0, 1.0, _wind_k)
	var chest := tx * Vector3(0, 0.3, -0.1)
	var rope_dir := (rope_anchor - chest).normalized() if rope_anchor != Vector3.ZERO else fwd
	if lift != null:
		_was_lifting = true
	elif _throw_t <= 0.0:
		_was_lifting = false
	# оторванная деталь на плече: кулак у ключицы держит её за запястье/щиколотку,
	# рваный край лежит на плече и искрит за спиной
	var hold_i := 1 if (work & 2) != 0 else 0
	var carry_g := Vector3.ZERO
	var carry_back := Vector3.BACK
	_limb_carry_ok = false
	# от 1-го лица: «глаза» и что в кадре
	var fpf := _fp_frame() if fp_on else Transform3D.IDENTITY
	var fp_free := fp_on and not dead and not swim and not tumble and not carried and not carried_limp \
		and not belly_on and flop < 0.0 and sit_k < 0.25 and not crawling and rrole != 2 \
		and not bool(st.get("balance", false)) and not bool(st.get("plunge", false))
	var club_fp := false
	if cl != null and is_instance_valid(cl) and arms_n > 0 and not dead and not swim and rep.is_empty():
		var sh := 1.0 if hold_i == 1 else -1.0
		var rc2 := sin(PI * (1.0 - _recoil_t / 0.8)) if _recoil_t > 0.0 else 0.0
		var bob := sin(TAU * _phase * 2.0) * 0.022 * _amp
		carry_g = tx * Vector3(sh * 0.35, 0.5 + bob + rc2 * 0.2, -0.32 - rc2 * 0.05)
		# лежит поверх наплечника (как бита на плече)
		var rest := tx * Vector3(sh * 0.37, 0.71 + rc2 * 0.3, 0.05)
		carry_back = (rest - carry_g).normalized()
		if fp_free:
			# от 1-го лица — в кулаке, как оружие: торчит из нижнего угла кадра вверх-вперёд;
			# ЛКМ — замах назад-вверх и удар наискось через весь экран
			club_fp = true
			var u := 1.0 - _punch_t / 0.35 if _punch_t > 0.0 else 1.0
			var wind := sin(PI * clampf(u / 0.22, 0.0, 1.0)) if u < 0.22 else 0.0
			var hit := smoothstep(0.14, 0.42, u) * (1.0 - smoothstep(0.55, 1.0, u))
			var m := Vector3(sh, 1.0, 1.0)
			var sway := Vector3(sin(TAU * _phase) * 0.012, -absf(sin(TAU * _phase)) * 0.02, 0.0) * _amp
			var g_l := (FP_CLUB_GRIP * m).lerp(Vector3(sh * -0.04, -0.27, -0.6), hit) \
				+ Vector3(sh * 0.05, 0.07, 0.08) * wind + sway + Vector3(0.0, rc2 * 0.08, 0.0)
			var d_rest := (FP_CLUB_DIR * m).normalized()
			var d_l := d_rest.slerp(Vector3(sh * 0.25, 0.85, 0.45).normalized(), wind * 0.8)
			d_l = d_l.slerp(Vector3(-sh * 0.8, -0.15, -0.58).normalized(), hit)
			carry_g = fpf * g_l
			carry_back = (fpf.basis * d_l).normalized()
		var endv: Vector3 = st.get("carry_limb_end", Vector3(0, -0.7, 0))
		var L := maxf(endv.length(), 0.2)
		var from_end := 0.12 if String(st.get("carry_limb_kind", "")).begins_with("arm") else 0.14
		var cb := Basis(Quaternion(endv / L, -carry_back))
		_limb_carry = Transform3D(cb, carry_g + carry_back * (L - from_end))
		_limb_carry_ok = true
	for i in 2:
		if (limb_mask & (1 << i)) == 0:
			continue
		var arm_iced := (ice_mask & (1 << i)) != 0
		var am: Dictionary = _arms[i]
		var s: float = am["s"]
		var sh_l := SHOULDER * Vector3(s, 1, 1)
		var free := Vector3.ZERO
		var curl := 0.35 + 0.55 * run_k
		# шаг 124: руки бегуна — локоть ~90°, кулак ходит от бедра (сзади) до подбородка (спереди, чуть к центру),
		# на махе назад локоть раскрывается; на трусце — мягче и ниже
		var sw_ph := -cos(TAU * fposmod(_phase + i * 0.5, 1.0))
		var swing := sw_ph * _amp * lerpf(0.35 + 0.45 * run_k, 0.5 + 0.5 * ath, minf(ath * 3.0, 1.0)) * (0.4 if heavy_walk else 1.0)
		var v_hang := Vector3(s * 0.08, -0.57, 0.03)
		var v_bent := Vector3(s * 0.05, -0.33, -0.2)
		var v := v_hang.lerp(v_bent, maxf(run_k, 0.45 if quiet else 0.0))
		if ath > 0.0:
			var fwd_k := maxf(sw_ph, 0.0)
			var back_k := maxf(-sw_ph, 0.0)
			var v_run := Vector3(s * (0.07 - 0.1 * fwd_k * ath), -0.3 + 0.07 * fwd_k - 0.1 * back_k, -0.22 - 0.03 * fwd_k + 0.1 * back_k)
			v = v.lerp(v_run, minf(ath * 2.2, 1.0))
			curl = lerpf(curl, 0.8, minf(ath * 2.0, 1.0))
		if belly_on:
			# «супермен»: руки вперёд по ходу; гребу — по очереди загребаю под себя
			var pd: float = float(st.get("belly_paddle", 0.0))
			# шаг 88: тащит верёвкой — гребу судорожно, быстро, впиваясь в снег
			var bsp := float(st.get("belly_spd", 0.0)) if pd > 0.5 else 0.0
			var ph := fposmod(_t * (1.6 + clampf(bsp, 0.0, 3.0) * 0.9) + i * 0.5, 1.0)
			var kb := clampf(bsp - 1.0, 0.0, 1.0)
			var stroke := Vector3(s * (0.22 + 0.04 * kb), 0.55 + 0.5 * kb - ph * (0.85 + 0.25 * kb), -0.2 - sin(ph * PI) * (0.15 + 0.1 * kb))
			v = Vector3(s * 0.2, 0.6, -0.1).lerp(stroke, pd)
			curl = lerpf(0.15, 0.6, pd)
		elif lying:
			v = Vector3(s * 0.5, -0.22, -0.14)       # руки раскинуты по снегу
			curl = 0.3
		elif dead:
			v = Vector3(s * 0.12, -0.55, -0.06)
			curl = 0.5
		elif carried_limp:
			v = Vector3(s * 0.32, -0.25, 0.45 + sin(_t * 2.0 + i) * 0.04)
			curl = 0.5
		elif carried:
			v = Vector3(s * 0.45, -0.05 + sin(_t * 13.0 + i * 2.0) * 0.25, -0.1 + cos(_t * 10.0 + i) * 0.2)
			curl = 0.1
			# шаг 124: раскручивают — руки вытянуло за голову (наружу), машут
			var spun2 := float(st.get("spun", 0.0))
			v = v.lerp(Vector3(s * (0.3 + 0.1 * sin(_t * 9.0 + i * 2.0)), 0.72 + 0.08 * sin(_t * 12.0 + i * 3.0), 0.05 + 0.14 * cos(_t * 10.0 + i * 2.0)), spun2)
			curl = lerpf(curl, 0.0, spun2)
		elif flop >= 0.0:
			var up_k2 := smoothstep(0.6, 1.0, flop)
			v = Vector3(s * 0.5, 0.2 + sin(_t * 5.0 + i) * 0.06, 0.12).lerp(Vector3(s * 0.32, -0.45, 0.3), up_k2)
			curl = 0.1
		elif tumble:
			# мельница руками
			var kw := _t * 15.0 + i * PI
			v = Vector3(s * (0.4 + 0.08 * sin(kw * 0.5)), 0.15 + sin(kw) * 0.42, -0.05 + cos(kw) * 0.32)
			curl = 0.0
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
		if st.get("balance", false) and not swim:
			# лёд трещит под ногами: руки в стороны, ловлю равновесие
			free = sh_l + Vector3(s * (0.45 + 0.05 * sin(_t * 17.0 + i * 2.0)), -0.08 + 0.12 * sin(_t * 13.0 + i * 3.0), -0.08)
			curl = 0.05
		if st.get("plunge", false):
			# ухнул в воду: руки вверх, барахтаюсь
			free = sh_l + Vector3(s * 0.12, 0.5 + 0.1 * sin(_t * 15.0 + i * PI), -0.05 + 0.12 * cos(_t * 15.0 + i * PI))
			curl = 0.0
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
				# лёгкая — под рабочей рукой (обычно правой), ладонь снизу; другая свободна
				if i == hold_i:
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
			elif fp_on:
				# от 1-го лица: ладони сверху на углах посылки, пальцы через край — видны у нижнего края кадра
				var palm := carry_tx.origin + bx * s * (ext.x - 0.07) + by_ * (ext.y + 0.035) - bz * ext.z * 0.25
				var fingers := (bx * s * 0.75 - by_ * 0.55 - bz * 0.2).normalized()
				hold_basis = _hand_basis(fingers, by_ * s)
				hold_wrist = palm + hold_basis.y * HAND
				hold = true
				curl = 0.45
				pole_l = Vector3(s * 0.75, -0.4, 0.2)
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
			# шаг 124: «молот» — обе руки вытянуты вперёд, кулаки сжимают щиколотки друга
			var spn2 := float(st.get("spin", -1.0))
			var lv_vis: Node3D = lift.get("visual") if lift.get("visual") is Node3D else null
			if spn2 >= 0.0 and lv_vis != null:
				var ftx := lv_vis.global_transform.orthonormalized()
				var ank := ftx * Vector3(s * 0.1, 0.1, 0.0)
				var gb := _grip_basis(ftx.basis.x * s, ftx.basis.y)
				var sk2 := smoothstep(0.0, 0.2, spn2)
				hold_wrist = hold_wrist.lerp(_wrist_for(ank, gb, s), sk2)
				hold_basis = Basis(hold_basis.get_rotation_quaternion().slerp(gb.get_rotation_quaternion(), sk2))
				curl = lerpf(curl, 1.0, sk2)
				pole_l = Vector3(s * 0.8, -0.5, 0.2)
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
		elif push_pt != Vector3.ZERO and not dead and not swim:
			# упираюсь ладонями в глыбу: пальцы вверх, ладони вперёд
			var to_b := (push_pt - chest)
			to_b.y = 0.0
			var nb := to_b.normalized() if to_b.length() > 0.01 else fwd
			var sd := nb.cross(Vector3.UP).normalized()
			var fing := (Vector3.UP * 0.55 + nb * 0.45).normalized()
			hold_basis = _hand_basis(fing, -nb * s)
			hold_wrist = push_pt + sd * s * 0.27 - fing * HAND - nb * 0.04 + Vector3.DOWN * 0.05
			hold = true
			curl = 0.15
			pole_l = Vector3(s * 0.6, -0.6, 0.2)
		elif rope_grip != Vector3.ZERO and not dead:
			# меня тянут верёвкой: обеими руками вцепился в петлю, руки к спасателю,
			# правая дальше, левая ближе, чуть подрагивают от рывков
			var jerk := sin(_t * 9.0 + i * 1.7) * 0.025
			var dg := (0.56 if i == 1 else 0.36) + jerk
			var w5 := chest + rope_grip * dg + up * (0.06 if swim else -0.04) + _vis.global_basis.x * 0.05 * s
			hold_wrist = w5
			hold_basis = _hand_basis(rope_grip, up * s)
			hold = true
			curl = 0.98
			pole_l = Vector3(s * 0.7, -0.45, 0.25)
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
		# --- руки без ног, на одной ноге, деталь на плече, ремонт, «оторвать», меня тянут за руку ---
		if crawling and not hold and not arm_iced:
			# ползу: рука тянется вперёд, упирается в снег и подтягивает корпус
			var ph := fposmod(_crawl + i * 0.5, 1.0)
			var reach := 0.0
			var lift_c := 0.0
			if ph < 0.55:
				reach = lerpf(0.8, 0.2, ph / 0.55)
			else:
				var u := (ph - 0.55) / 0.45
				reach = lerpf(0.2, 0.8, u)
				lift_c = sin(u * PI) * 0.15
			var gpt := _vis.global_position + fwd * reach + right * s * 0.3 + up * (0.04 + lift_c)
			if fp_on:
				# шаг 138: от 1-го лица — гребки перед глазами: рука взлетает дугой, падает далеко впереди головы,
				# упирается и подтягивает тело (уходит под подбородок, из кадра) — по очереди
				var hg := Vector3(head.global_position.x, _vis.global_position.y, head.global_position.z)
				var rk := reach
				var lk := lift_c * 2.2
				if ph >= 0.55:
					var u2 := (ph - 0.55) / 0.45
					rk = lerpf(0.2, 1.1, smoothstep(0.0, 1.0, u2))
					lk = sin(u2 * PI) * 0.24
				else:
					rk = lerpf(1.1, 0.2, smoothstep(0.0, 1.0, ph / 0.55))
				gpt = hg + fwd * (rk - 0.15) + right * s * lerpf(0.36, 0.26, rk / 1.1) + up * (0.05 + lk)
			hold_basis = _hand_basis((fwd * 0.6 - up * 0.8).normalized(), right * s)
			hold_wrist = gpt + up * HAND
			hold = true
			curl = 0.45
			pole_l = Vector3(s * 0.8, 0.2, 0.1)
		elif one_leg and not hold:
			# руки в стороны — ловлю равновесие
			hold_wrist = tx * (sh_l + Vector3(s * 0.42, -0.22 + 0.1 * sin(_t * 6.0 + i * 2.0), -0.08))
			hold_basis = _hand_basis((right * s * 0.7 - up * 0.7).normalized(), -fwd * s)
			hold = true
			curl = 0.2
		if _limb_carry_ok and i == hold_i:
			hold_basis = _hand_basis((-up * 0.55 - right * s * 0.25 - carry_back * 0.2).normalized(), carry_back * s)
			if club_fp:
				# кулак вокруг рукояти: костяшки вдоль неё, большой палец — к «голове» дубинки
				var vr := fpf.basis.x * s
				var bk := (vr - carry_back * vr.dot(carry_back)).normalized()
				hold_basis = _hand_basis(carry_back.cross(bk) * s, bk * s)
				pole_l = Vector3(s * 0.7, -0.6, 0.15)
			hold_wrist = carry_g + hold_basis.y * HAND
			hold = true
			curl = 0.95
			pole_l = Vector3(s * 0.75, -0.55, 0.2)
		if not rep.is_empty():
			# механик: подношу деталь, вставляю со щелчком, кручу болты ключом,
			# придерживаю на разряде, простукиваю
			var rk := float(rep["k"])
			var part: Node3D = rep["part"]
			var px: Transform3D = part.repair_xform(rk, rep["target"])
			var endl: Vector3 = part.get("_end")
			var tool_i := 1 if arms_n == 2 else hold_i
			var to_r := px.origin - chest
			to_r.y = 0.0
			var nr := to_r.normalized() if to_r.length() > 0.01 else fwd
			var wires_on := rk >= 0.74 and rk < 0.86
			if i != tool_i or rk < 0.22 or wires_on:
				var at: Vector3 = px * (endl * (0.55 if rk < 0.22 else 0.32))
				hold_wrist = at - nr * 0.07 + up * 0.05
				hold_basis = _hand_basis((nr * 0.6 - up * 0.4).normalized(), up * s)
				curl = 0.85
				if rk > 0.76 and rk < 0.84:
					hold_wrist -= nr * 0.14 * sin((rk - 0.76) / 0.08 * PI)    # дёрнуло током
			if i == tool_i and arms_n == 2 and rk < 0.22:
				# достал ключ, жду
				hold_wrist = chest + nr * 0.28 + right * s * 0.14 + up * 0.02
				hold_basis = _hand_basis((nr - up * 0.3).normalized(), up * s)
				curl = 0.95
			elif i == tool_i and rk >= 0.22 and rk < 0.74:
				# кручу болт: кисть ходит трещоткой вокруг болта
				var j := clampi(int((rk - BOLT_K0) / BOLT_DK), 0, 3)
				var bp: Vector3 = px * (part.bolt_local(j, rk) as Vector3)
				var bo: Vector3 = (px.basis * (part.bolt_dir(j) as Vector3)).normalized()
				var lk := clampf((rk - (BOLT_K0 + j * BOLT_DK)) / BOLT_DK, 0.0, 1.0)
				var p1 := chest - bp
				p1 -= bo * p1.dot(bo)
				p1 = p1.normalized() if p1.length() > 0.01 else -up
				var p2 := bo.cross(p1)
				var rr := sin(lk * TAU * 3.0) * 0.5
				var shaft := (p1 * cos(rr) + p2 * sin(rr)).normalized()
				var head_p := bp + bo * 0.02
				var palm := head_p + shaft * 0.15
				hold_basis = _hand_basis(bo.cross(shaft).normalized() * s, -shaft * s)
				hold_wrist = palm + hold_basis.y * HAND
				curl = 1.0
				_wr = {"head": head_p, "axis": bo}
			elif i == tool_i and rk >= 0.86:
				# простукиваю ключом: тук-тук
				var tp: Vector3 = px * (endl * 0.22)
				var tk := absf(sin((rk - 0.86) / 0.14 * PI * 2.0))
				var palm2 := tp - nr * (0.2 + 0.12 * tk) + up * (0.06 + 0.12 * tk)
				hold_basis = _hand_basis((nr + up * 0.2).normalized(), up * s)
				hold_wrist = palm2 + hold_basis.y * HAND
				curl = 1.0
			hold = true
			pole_l = Vector3(s * 0.7, -0.4, 0.3)
		if not rip.is_empty():
			# вцепился в руку/ногу друга обеими руками, тяну рывками
			var gp: Vector3 = rip["grip"]
			var to_p := gp - chest
			to_p.y = 0.0
			var np := to_p.normalized() if to_p.length() > 0.01 else fwd
			var pulse2 := float(rip["pulse"])
			var along := 0.0 if arms_n == 1 else (0.07 if i == 1 else -0.09)
			var grab_k := smoothstep(0.0, 0.08, float(rip["k"]))
			hold_wrist = wrist_free.lerp(gp + np * along - np * pulse2 * 0.07 + up * 0.03, grab_k)
			hold_basis = _hand_basis((np * 0.5 - up * 0.5 - right * s * 0.3).normalized(), up * s)
			hold = true
			curl = lerpf(0.3, 1.0, grab_k)
			pole_l = Vector3(s * 0.75, -0.5, 0.25)
		if _check_t > 0.0 and _check_kind == LIMBS[i] and not dead and not swim:
			# проверяю прикрученную руку: поднял, кручу кистью, сжимаю-разжимаю пальцы
			var ck2 := 1.0 - _check_t / 1.5
			var raise := smoothstep(0.0, 0.2, ck2) * (1.0 - smoothstep(0.85, 1.0, ck2))
			var cw := tx * (sh_l + Vector3(s * 0.2, -0.05 + 0.12 * sin(ck2 * TAU * 1.5), -0.38))
			hold_wrist = wrist_free.lerp(cw, raise)
			var tw := sin(ck2 * TAU * 2.0) * 1.2
			hold_basis = _hand_basis((fwd * 0.3 + up * 0.7).normalized(), (right * cos(tw) + fwd * sin(tw)) * s)
			hold = true
			curl = 0.5 + 0.5 * sin(ck2 * TAU * 3.0)
		if not ripped.is_empty() and String(ripped.get("kind", "")) == LIMBS[i]:
			# мою руку тянут — вытянута к тому, кто тянет
			var to_g: Vector3 = ripped["to"]
			hold_wrist = to_g
			hold_basis = _hand_basis((to_g - tx * sh_l).normalized(), up * s)
			hold = true
			curl = 0.6
		if sit_k > 0.25 and not hold and not dead:
			# сижу: руки на коленях / откинулся на руки / обнял колени / грею ладони у огня
			var kn: Vector3 = knees[i] if (limb_mask & (4 << i)) != 0 else _vis.global_position + fwd * 0.35 + right * s * 0.2 + up * 0.45
			var tgt := Vector3.ZERO
			match _sit_pose:
				0:
					tgt = inv * (kn + up * 0.07 + fwd * 0.02 - _vis.global_position)
				1:
					tgt = Vector3(s * 0.3, 0.06, 0.32)
					if ride:
						# цепляюсь за снег: ладони загребают по бокам, то одна, то другая
						var scr := sin(_t * 5.0 + i * PI)
						tgt = Vector3(s * (0.42 + 0.06 * scr), 0.12 + maxf(scr, 0.0) * 0.16, 0.22 + scr * 0.16)
				2:
					tgt = inv * (kn - fwd * 0.03 - up * 0.12 - right * s * 0.1 - _vis.global_position)
				_:
					var rub := sin(_t * 9.0 + i * PI) * 0.035
					tgt = Vector3(-s * 0.02 + rub, 0.72, -0.42)
			_sit_hand[i] = _sit_hand[i].lerp(tgt, clampf(delta * 4.0, 0.0, 1.0)) if _sit_hand[i] != Vector3.ZERO else tgt
			var sw := vis_tx * _sit_hand[i]
			hold_wrist = wrist_free.lerp(sw, clampf((sit_k - 0.25) / 0.6, 0.0, 1.0))
			var fdir := (-up * 0.7 + fwd * 0.3).normalized() if _sit_pose != 3 else (fwd * 0.6 + up * 0.3).normalized()
			if _sit_pose == 1:
				fdir = (-up * 0.8 - fwd * 0.4).normalized()
			hold_basis = _hand_basis(fdir, right * s)
			hold = true
			curl = float([0.45, 0.2, 0.85, 0.15][_sit_pose])
			pole_l = Vector3(s * 0.75, -0.3, 0.2) if _sit_pose != 1 else Vector3(s * 0.7, 0.3, 0.6)
		if belly_on and belly_lead != null and is_instance_valid(belly_lead):
			# паровозик: держусь за ботинки друга впереди
			var lsuit = belly_lead.get("suit")
			if lsuit != null:
				var bt: Vector3 = (lsuit._legs[i]["boot"] as Node3D).global_position
				hold_wrist = wrist_free.lerp(bt + Vector3.UP * 0.05, 0.9)
				hold_basis = _hand_basis((bt - tx * sh_l).normalized(), up * s)
				hold = true
				curl = 0.95
		if reach_k > 0.0 and i == (1 if (work & 2) != 0 else 0):
			# последний жест: тянусь к небу, рука дрожит, пальцы раскрыты
			var tr := Vector3(sin(_t * 31.0), sin(_t * 27.0 + 1.0), 0.0) * 0.015 * reach_k
			hold_wrist = tx * (sh_l + Vector3(s * 0.12, lerpf(-0.3, 0.52, reach_k), lerpf(-0.1, -0.32, reach_k))) + tr
			hold_basis = _hand_basis((up * 0.85 - fwd * 0.4).normalized(), right * s)
			hold = true
			curl = lerpf(0.5, 0.05, reach_k)
			pole_l = Vector3(s * 0.7, -0.2, 0.3)
		if arm_iced and not dead:
			# вмёрзшая рука застыла чуть в сторону, пальцы скрючены — ничего ей не взять
			hold = true
			hold_wrist = tx * (sh_l + Vector3(s * 0.17, -0.5, -0.14))
			if crawling:
				hold_wrist = _vis.global_position + fwd * 0.55 + right * s * 0.38 + up * 0.12
			hold_basis = _hand_basis((-up * 0.8 + fwd * 0.2).normalized(), right * s)
			curl = 0.55
			pole_l = Vector3(s * 0.6, -0.3, 0.4)
			_hold_w[i] = 1.0
			trem = Vector3.ZERO
		var climbing := int(st.get("climb", 0))
		var mpo := int(st.get("mpose", 0))
		if mpo == 0 and climbing == 1:
			mpo = 1
		if mpo > 0 and not arm_iced and not dead:
			var mk := float(st.get("mpose_k", 0.0))
			var mpt: Vector3 = st.get("mpose_pt", Vector3.ZERO)
			var mdir: Vector3 = st.get("mpose_dir", fwd)
			var mmv := bool(st.get("climb_moving", false))
			var vp := _vis.global_position
			hold = true
			match mpo:
				1, 2, 12:
					# лезу: руки над головой по очереди перехватывают (ледорубы / лестница); вцепился — обе высоко
					var cph := fposmod(_t * (1.6 if mmv else 0.0) + i * 0.5, 1.0)
					var reach_up := 0.14 * sin(cph * TAU) if mmv else 0.0
					var hy := 0.5 if mpo == 12 else 0.42 + reach_up
					hold_wrist = tx * (sh_l + Vector3(s * 0.15, hy, -0.32))
					hold_basis = _hand_basis((up * 0.8 - fwd * 0.4).normalized(), right * s)
					curl = 1.0 if mpo == 12 else 0.9
					pole_l = Vector3(s * 0.7, -0.4, 0.3)
				3:
					# ладони «ступенькой» у колен, пальцы сцеплены
					var cup := vp + fwd * 0.42 + up * 0.5
					hold_basis = _hand_basis((fwd * 0.65 - right * s * 0.45 - up * 0.1).normalized(), -up * s)
					hold_wrist = cup + right * s * 0.07 + hold_basis.y * HAND * 0.6
					curl = 0.35
					pole_l = Vector3(s * 0.8, -0.2, 0.2)
				4:
					# шаг 75: ладони «ступенькой» с ногой друга: просели → рывком вверх над головой → раскрыл ладони
					var hh4 := 0.45
					var ff4 := 0.42
					var cl4 := 0.4
					if mk >= 0.0 and mk < 0.35:
						var a4 := mk / 0.35
						hh4 = lerpf(0.45, 0.3, a4)
						ff4 = lerpf(0.42, 0.38, a4)
					elif mk >= 0.35 and mk < 0.8:
						var b4 := smoothstep(0.0, 1.0, (mk - 0.35) / 0.45)
						hh4 = lerpf(0.3, 1.95, b4)
						ff4 = lerpf(0.38, 0.08, b4)
					elif mk >= 0.8 and mk < 1.15:
						var c4 := (mk - 0.8) / 0.35
						hh4 = lerpf(1.95, 2.12, sin(c4 * PI * 0.5))
						ff4 = lerpf(0.08, -0.12, c4)
						cl4 = lerpf(0.4, 0.05, c4)
					elif mk >= 1.15:
						var d4 := clampf((mk - 1.15) / 0.52, 0.0, 1.0)
						hh4 = lerpf(2.1, 1.1, d4)
						ff4 = lerpf(-0.12, 0.3, d4)
						cl4 = 0.2
					var cup2 := vp + fwd * ff4 + up * hh4
					var open4 := clampf((mk - 0.8) / 0.3, 0.0, 1.0)
					hold_basis = _hand_basis((fwd * lerpf(0.4, 0.0, open4) + up * lerpf(0.5, 1.0, open4) - right * s * lerpf(0.4, 0.15, open4)).normalized(), -up * s)
					hold_wrist = cup2 + right * s * lerpf(0.08, 0.16, open4)
					curl = cl4
					pole_l = Vector3(s * 0.8, -0.3, 0.3)
				5:
					# шаг 76: сначала ладони на плечах друга (опираюсь), потом — вверх, к краю уступа
					var reach := tx * (sh_l + Vector3(s * 0.2, 0.42 + 0.12 * mk, -0.22))
					var on_sh := mpt + right * s * 0.17 - fwd * 0.04 + up * 0.03
					var w5 := smoothstep(0.38, 0.62, mk)
					hold_wrist = on_sh.lerp(reach, w5)
					var b_sh := _hand_basis((fwd * 0.6 + Vector3.DOWN * 0.8).normalized(), up * s)
					var b_up := _hand_basis((up * 0.85 - fwd * 0.3).normalized(), right * s)
					hold_basis = b_up if w5 > 0.5 else b_sh
					curl = lerpf(0.55, 0.3, w5) if mk < 0.95 else 0.75
					pole_l = Vector3(s * 0.7, -0.2, 0.3)
				6:
					# ладони на краю: вишу, подтягиваюсь, отжимаюсь
					var edge := Vector3(vp.x, mpt.y, vp.z) + mdir * 0.32
					hold_wrist = edge + right * s * 0.28 + up * 0.06
					hold_basis = _hand_basis((mdir * 0.9 - up * 0.2).normalized(), up * s)
					curl = 0.55
					pole_l = Vector3(s * 0.8, 0.2, 0.4)
				7:
					if i == 1:
						# тяну руку вниз — к другу
						hold_wrist = vp + fwd * 0.75 + up * (-0.35 + 0.05 * sin(_t * 5.0))
						hold_basis = _hand_basis((-up * 0.9 + fwd * 0.2).normalized(), right * s)
						curl = 0.7
					else:
						# другой рукой упираюсь в снег у края
						hold_wrist = vp + fwd * 0.35 + right * s * 0.35 + up * 0.08
						hold_basis = _hand_basis((fwd * 0.6 - up * 0.6).normalized(), up * s)
						curl = 0.2
					pole_l = Vector3(s * 0.8, 0.2, 0.2)
				8:
					if i == 1:
						hold_wrist = tx * (sh_l + Vector3(s * 0.05, 0.62, -0.18))
						hold_basis = _hand_basis((up * 0.9 - fwd * 0.2).normalized(), right * s)
						curl = 0.9
					else:
						hold_wrist = tx * (sh_l + Vector3(s * 0.2, 0.25, -0.35))
						hold_basis = _hand_basis((up * 0.6 - fwd * 0.5).normalized(), right * s)
						curl = 0.8
					pole_l = Vector3(s * 0.7, -0.2, 0.3)
				23:
					# шаг 99: несу связку досок перед собой (снизу, ладони вверх); mk 1..2 — кладу её в дыру и прибиваю
					var c23 := vp + up * 1.3 + fwd * 0.46          # шаг 131: доска на груди — видна от первого лица
					var b_carry := _hand_basis((fwd * 0.85 - right * s * 0.25).normalized(), -up * s)
					if mk < 1.0:
						hold_basis = b_carry
						hold_wrist = c23 - up * 0.13 + right * s * 0.3 + b_carry.y * HAND
						curl = 0.4                                  # шаг 131: ладони под ближним краем доски, пальцы прижаты снизу
						pole_l = Vector3(s * 0.85, -0.7, 0.1)
					elif mk >= 2.0:
						# бросок: связку чуть к себе — и резко вперёд-вверх двумя руками; после — руки вытянуты
						var pt3 := mk - 2.0
						var e3 := smoothstep(0.1, 0.45, pt3)
						var wind := sin(PI * clampf(pt3 / 0.12, 0.0, 1.0)) * (1.0 - e3)
						var cc3 := c23 + fwd * (0.42 * e3 - 0.1 * wind) + up * (0.32 * e3 + 0.04 * wind)
						hold_basis = _hand_basis((fwd * (0.85 - 0.3 * e3) + up * 0.45 * e3 - right * s * 0.25).normalized(), (-up * (1.0 - e3) + fwd * e3).normalized() * s)
						hold_wrist = cc3 - up * 0.13 * (1.0 - e3) + right * s * (0.3 - 0.08 * e3) + hold_basis.y * HAND
						curl = lerpf(0.55, 0.12, smoothstep(0.42, 0.55, pt3))
						pole_l = Vector3(s * 0.7, -0.35, 0.3)
					else:
						var ph23 := mk - 1.0
						var g23 := mpt
						if ph23 < 0.42:
							var k23 := smoothstep(0.0, 1.0, ph23 / 0.42)
							var cc := c23.lerp(g23 + up * 0.1, k23)
							hold_basis = b_carry
							hold_wrist = cc - up * 0.13 + right * s * 0.3 + b_carry.y * HAND
							curl = 0.55
						elif i == 0:
							# левая — упёрлась в настил рядом
							var bl := _hand_basis((fwd * 0.6 + right * 0.2 + Vector3.DOWN * 0.2).normalized(), Vector3.DOWN)
							hold_basis = bl
							hold_wrist = g23 - right * 0.32 - fwd * 0.12 + Vector3.UP * 0.06 + bl.y * HAND * 0.3
							curl = 0.2
						else:
							# правая — молотком: замах вверх → удар (три удара)
							var hc := fposmod((ph23 - 0.42) / 0.58 * 3.0, 1.0)
							var hh := lerpf(0.14, 0.52, smoothstep(0.0, 1.0, hc / 0.62)) if hc < 0.62 else lerpf(0.52, 0.1, pow((hc - 0.62) / 0.38, 1.6))
							var hb := _hand_basis((fwd * 0.75 + Vector3.DOWN * 0.25).normalized(), -right)
							hold_basis = hb
							hold_wrist = g23 + right * 0.26 - fwd * 0.18 + Vector3.UP * hh
							curl = 1.0
						pole_l = Vector3(s * 0.75, -0.5, 0.3)
				25:
					# шаг 106: обвязываюсь страховкой. mk: 0–.18 тянусь к концу верёвки у крюка → .18–.36 несу к поясу →
					# .36–.66 обношу вокруг пояса (руки расходятся за спину и возвращаются) → .66–.86 вяжу узел
					# (кисти крутятся навстречу) → .86–1 рывком проверяю
					var hp25 := harness_point()
					var wc := vp + up * ((hp25 - vp).dot(up)) 
					var front := wc + fwd * 0.3
					var w25 := front
					var b25 := _hand_basis((fwd * 0.4 - up * 0.3 - right * s * 0.6).normalized(), up * s)
					var c25 := 1.0
					if mk < 0.18:
						var a25 := smoothstep(0.0, 1.0, mk / 0.18)
						var reach25 := mpt + right * s * 0.05
						w25 = (tx * (sh_l + Vector3(s * 0.2, -0.45, -0.15))).lerp(reach25, a25)
						b25 = _hand_basis((mpt - wc).normalized(), up * s)
						c25 = lerpf(0.3, 1.0, smoothstep(0.7, 1.0, a25))
					elif mk < 0.36:
						var a25b := smoothstep(0.0, 1.0, (mk - 0.18) / 0.18)
						w25 = (mpt + right * s * 0.05).lerp(front + right * s * 0.06, a25b)
					elif mk < 0.66:
						var a25c := (mk - 0.36) / 0.3
						var ang := s * deg_to_rad(150.0) * sin(PI * a25c)
						var dir25 := (fwd * cos(ang) + right * sin(ang)).normalized()
						w25 = wc + dir25 * 0.3 + up * 0.02 + right * s * 0.06 * (1.0 - sin(PI * a25c))
						b25 = _hand_basis((-dir25 * 0.7 - up * 0.3).normalized(), up * s)
					elif mk < 0.86:
						var a25d := (mk - 0.66) / 0.2
						var tw := a25d * TAU * 3.0 * s
						w25 = front + right * s * 0.05 + (up * cos(tw) + fwd * sin(tw)) * 0.045
						b25 = _hand_basis((fwd * 0.3 - up * 0.2 - right * s * 0.8).normalized(), up * s)
					else:
						var a25e := (mk - 0.86) / 0.14
						var jerk := sin(PI * clampf(a25e * 1.6, 0.0, 1.0))
						w25 = front + fwd * 0.14 * jerk + up * 0.1 * jerk + right * s * 0.07
						b25 = _hand_basis((fwd * 0.8 + up * 0.2).normalized(), up * s)
					hold_basis = b25
					hold_wrist = w25 + b25.y * HAND * 0.7
					curl = c25
					pole_l = Vector3(s * 0.8, -0.5, 0.25)
				26:
					# шаг 106: обе руки на рукояти лебёдки (mpt — сама рукоять, mdir — её ось), идут за ней по кругу
					var ax26 := mdir.normalized()
					if ax26.dot(right) < 0.0:
						ax26 = -ax26
					var g26 := _grip_basis(ax26 * s, fwd * 0.6 + up * 0.4)
					var f26 := mpt + ax26 * s * 0.055
					hold_basis = g26
					hold_wrist = _wrist_for(f26, g26, s)
					curl = 1.0
					pole_l = Vector3(s * 0.85, -0.45, 0.2)
				27:
					# шаг 110: держусь в кабине канатки. mpt/mdir — в осях тела (_vis): у других руки не отстают от едущей
					# кабины. mk: 0 — обе руки на горизонтальном поручне, 1 — на стойке (кулаки один над другим),
					# 2 — правая в потолочной петле, левая свободна. Кулак ровно на трубе, пальцы обхватывают её.
					var vb27 := _vis.global_transform
					var gp27 := vb27 * mpt
					var ax27 := (vb27.basis * mdir).normalized()
					var k27 := int(mk + 0.5)
					curl = 1.0
					if k27 == 1:
						var up27 := ax27 if ax27.dot(up) >= 0.0 else -ax27
						var to27 := gp27 - chest
						to27 -= up27 * to27.dot(up27)
						if to27.length() < 0.05:
							to27 = fwd
						var g27 := _grip_basis(-up27, to27.normalized() * 0.8 - right * s * 0.4)
						hold_basis = g27
						hold_wrist = _wrist_for(gp27 + up27 * (0.1 if i == 1 else -0.12), g27, s)
						pole_l = Vector3(s * 0.85, -0.55, 0.05)
					elif k27 == 2:
						if s < 0.0:
							hold = false
						else:
							var ax2 := ax27 if ax27.dot(right) >= 0.0 else -ax27
							var g2 := _grip_basis(ax2 * s, up * 0.85 + fwd * 0.15)
							hold_basis = g2
							hold_wrist = _wrist_for(gp27, g2, s)
							pole_l = Vector3(s * 0.9, 0.1, 0.25)
					else:
						var ax0 := ax27 if ax27.dot(right) >= 0.0 else -ax27
						var g0 := _grip_basis(ax0 * s, fwd * 0.75 + up * 0.25)
						hold_basis = g0
						hold_wrist = _wrist_for(gp27 + ax0 * s * 0.17, g0, s)
						pole_l = Vector3(s * 0.85, -0.5, 0.15)
				28:
					# шаг 115: молоток. mpt — куда бью (в осях тела), mdir — нормаль стены (из стены ко мне).
					# mk — фаза: 0–.5 замах (кулак назад-вверх, молоток запрокидывается за плечо), .5–.66 удар
					# (быстро, с разгоном), .66–1 отдача и короткая пауза у стены. Левая ладонью держит доску рядом.
					var vb28 := _vis.global_transform
					var tg28 := vb28 * mpt
					var nw := (vb28.basis * mdir).normalized()
					var into := -nw
					var c28b := fposmod(mk, 1.0)
					if i == 1:
						var w28 := 0.0
						if c28b < 0.5:
							w28 = smoothstep(0.0, 1.0, c28b / 0.5)
						elif c28b < 0.66:
							w28 = 1.0 - pow((c28b - 0.5) / 0.16, 2.2)
						else:
							w28 = 0.07 * sin(PI * (c28b - 0.66) / 0.34)
						var th := deg_to_rad(6.0 + 100.0 * w28)
						var a28 := (up * cos(th) + nw * sin(th)).normalized()
						var face := (into * cos(th) + up * sin(th)).normalized()
						var fist := tg28 + nw * 0.04 - up * 0.27 + nw * (0.2 * w28) + up * (0.16 * w28) + right * 0.03
						var g28 := _grip_basis(a28 * s, face)
						hold_basis = g28
						hold_wrist = _wrist_for(fist, g28, s)
						curl = 1.0
						pole_l = Vector3(s * 0.85, -0.25 - 0.35 * w28, 0.15)
					else:
						# левая — кулаком за стойку рамы слева, на уровне груди (кабину качает)
						var lo28 := maxf(mdir.length() - 1.0, 0.3)
						var lp28 := tg28 - right * lo28 + nw * 0.02
						lp28 += up * ((vb28.origin.y + 1.12) - lp28.dot(up) * 0.0 - lp28.y)
						var hb28 := _grip_basis(up * s, into * 0.7 + right * 0.3)
						hold_basis = hb28
						hold_wrist = _wrist_for(lp28, hb28, s)
						curl = 1.0
						pole_l = Vector3(s * 0.85, -0.5, 0.05)
				29:
					# шаг 115: сварка. mpt — шов (в осях тела), mdir — откуда держу горелку (из шва ко мне).
					# Правая — за рукоять горелки, ось горелки — точно на шов; левая — под трубку горелки;
					# сопло ведёт шов мелким зигзагом.
					var vb29 := _vis.global_transform
					var tg29 := vb29 * mpt
					var back29 := (vb29.basis * mdir).normalized()
					var weave := right * 0.022 * sin(_t * 7.0) + up * 0.008 * sin(_t * 13.0)
					var fist29 := tg29 + weave + back29 * 0.34
					var a29 := (tg29 + weave - fist29).normalized()
					if i == 1:
						var g29 := _grip_basis(a29 * s, up)
						hold_basis = g29
						hold_wrist = _wrist_for(fist29, g29, s)
						pole_l = Vector3(s * 0.8, -0.45, 0.15)
					else:
						var g29b := _grip_basis(a29 * s, Vector3.DOWN)
						hold_basis = g29b
						hold_wrist = _wrist_for(fist29 + a29 * 0.15, g29b, s)
						pole_l = Vector3(s * 0.8, -0.55, 0.1)
					curl = 1.0
				30:
					# шаг 122: леплю снежок. 0–.25 тянусь к снегу, загребаю; .25–.72 лепёшка: ладони сходятся,
					# мнут ком (по очереди сверху-снизу, поворачивают); .72–1 встаю, ком — в правой у груди
					var c30 := (vp + fwd * 0.5)
					var lowy := 0.12
					if mk < 0.25:
						var r30 := smoothstep(0.0, 0.25, mk)
						var dig := vp + fwd * (0.62 - 0.15 * r30) + right * s * (0.2 - 0.08 * r30) + up * lerpf(0.55, lowy, minf(r30 * 1.6, 1.0))
						hold_basis = _hand_basis((-up * 0.6 + fwd * 0.5 - right * s * 0.2).normalized(), right * s)
						hold_wrist = _wrist_for(dig, hold_basis, s)
						curl = 0.25 + 0.4 * r30
					elif mk < 0.72:
						var p30 := (mk - 0.25) / 0.47
						var hy30 := lowy + 0.38 * smoothstep(0.0, 0.5, p30)
						var ball := c30 + up * hy30 - fwd * 0.08 * p30
						var mash := sin(p30 * TAU * 3.0)
						var side30 := ball + right * s * 0.075 + up * (0.04 * mash * s)
						hold_basis = _hand_basis((-right * s * 0.8 + up * (0.25 * mash * s) + fwd * 0.2).normalized(), (up * s * 0.6 + fwd * 0.4).normalized())
						hold_wrist = _wrist_for(side30, hold_basis, s)
						curl = 0.55
					else:
						var e30 := smoothstep(0.72, 1.0, mk)
						if i == 1:
							var hp30 := (c30 + up * 0.5).lerp(vp + up * 1.05 + fwd * 0.32 + right * 0.18, e30)
							hold_basis = _hand_basis((fwd * 0.6 - up * 0.2 - right * 0.35).normalized(), -up)
							hold_wrist = _wrist_for(hp30, hold_basis, s)
							curl = 0.6
						else:
							var lp30 := (c30 + up * 0.5 - right * 0.08).lerp(vp + up * 0.8 + fwd * 0.12 - right * 0.28, e30)
							hold_basis = _hand_basis((-up * 0.8 + fwd * 0.2).normalized(), right * s)
							hold_wrist = _wrist_for(lp30, hold_basis, s)
							curl = 0.35
					pole_l = Vector3(s * 0.8, -0.35, 0.35)
				31:
					# шаг 122: бросок. Правая: замах за плечо (.0–.45) → хлёст вперёд (.45–.6, отпускаю на .55) →
					# доводка вниз-поперёк. Левая: целится вперёд, на броске уходит к поясу (корпус «закручивается»)
					var w31a := smoothstep(0.0, 0.45, mk)
					var f31a := smoothstep(0.45, 0.6, mk)
					var t31a := smoothstep(0.6, 1.0, mk)
					if i == 1:
						var rest := vp + up * 1.05 + fwd * 0.3 + right * 0.2
						var back := vp + up * 1.62 - fwd * 0.38 + right * 0.36
						var front := vp + up * 1.42 + fwd * 0.62 + right * 0.08
						var follow := vp + up * 0.95 + fwd * 0.4 - right * 0.12
						var hp31 := rest.lerp(back, w31a)
						hp31 = hp31.lerp(front, f31a)
						hp31 = hp31.lerp(follow, t31a)
						var fdir := (up * 0.7 - fwd * 0.5).normalized().slerp((fwd * 0.9 - up * 0.2).normalized(), f31a)
						hold_basis = _hand_basis(fdir, right)
						hold_wrist = _wrist_for(hp31, hold_basis, s)
						curl = 0.7 if mk < 0.55 else 0.15
						pole_l = Vector3(s * 0.9, -0.1 - 0.3 * f31a, -0.2)
					else:
						var aim := vp + up * 1.42 + fwd * 0.58 - right * 0.3
						var tuck := vp + up * 0.95 + fwd * 0.05 - right * 0.32
						var lp31 := (vp + up * 0.85 - right * 0.3).lerp(aim, w31a).lerp(tuck, f31a)
						hold_basis = _hand_basis((fwd * 0.85 - right * 0.15).normalized(), up * s)
						hold_wrist = _wrist_for(lp31, hold_basis, s)
						curl = 0.25
						pole_l = Vector3(s * 0.85, -0.35, 0.2)
				50:
					# шаг 140: вишу на перекладине — хват сверху, кулаки на резиновых ручках (mpt — середина перекладины)
					var bax := mdir.cross(Vector3.UP)
					bax = bax.normalized() if bax.length() > 0.01 else right
					var gp50 := mpt + bax * s * 0.24
					var arm50 := (gp50 - tx * sh_l).normalized()
					var g50 := _grip_basis(bax * s, (arm50 * 0.8 + fwd * 0.2).normalized())
					hold_basis = g50
					hold_wrist = _wrist_for(gp50, g50, s)
					curl = 1.0
					pole_l = Vector3(s * 0.9, 0.15, -0.1)
				51:
					# шаг 140: на доске: руки расслаблены у пояса и чуть в стороны (баланс), передняя (к носу) — впереди;
					# на канте руки уходят за наклоном; в воздухе — шире; с захватом (W) передняя тянется к носку доски
					var bp2: Vector3 = mpt
					var air2 := mk > 0.5
					var ek := clampf(bp2.x, -1.0, 1.0)
					var sw51 := sin(_t * 1.7 + i * 1.3) * 0.025
					var hp51: Vector3
					if i == 1:
						hp51 = tx * (sh_l + Vector3(0.2, -0.42 + sw51, -0.24 - 0.08 * ek))
					else:
						hp51 = tx * (sh_l + Vector3(-0.16, -0.5 + sw51, 0.04 - 0.06 * ek))
					var fd51 := (-up * 0.85 + right * s * 0.35 + fwd * 0.15).normalized()
					if air2:
						hp51 = tx * (sh_l + Vector3(s * 0.32, -0.12 + sw51, -0.12))
						fd51 = (right * s * 0.8 - up * 0.3).normalized()
					if air2 and bp2.z > 0.5 and i == 1:
						var b0g := (_legs[0]["boot"] as Node3D).global_position
						var b1g := (_legs[1]["boot"] as Node3D).global_position
						hp51 = (b0g + b1g) * 0.5 + right * 0.12 + fwd * 0.17 - up * 0.08
						fd51 = (-up * 0.8 + fwd * 0.3).normalized()
					hold_basis = _hand_basis(fd51, fwd if i == 1 else -fwd)
					hold_wrist = _wrist_for(hp51, hold_basis, s)
					curl = 0.9 if (air2 and bp2.z > 0.5 and i == 1) else 0.4
					pole_l = Vector3(s * 0.9, -0.3, 0.2)
				52:
					# шаг 139: кувырок — руки прижаты, кулаки у груди
					var hp52 := tx * (sh_l + Vector3(-s * 0.02, -0.3, -0.22))
					hold_basis = _hand_basis((-up * 0.4 + fwd * 0.6 - right * s * 0.4).normalized(), right * s)
					hold_wrist = _wrist_for(hp52, hold_basis, s)
					curl = 0.85
					pole_l = Vector3(s * 0.8, -0.3, 0.2)
				32:
					# шаг 122: вишу на ноге друга: обе руки обхватили его ботинок (mpt — где ботинок, в мире)
					var gp32: Vector3 = mpt + right * s * 0.075 + up * (0.03 if i == 0 else -0.04)
					var g32 := _grip_basis(up, -fwd + right * s * 0.4)
					hold_basis = g32
					hold_wrist = _wrist_for(gp32, g32, s)
					curl = 1.0
					pole_l = Vector3(s * 0.75, -0.2, 0.35)
				9:
					# кручу ворот / рукоять: кисти ходят по кругу
					var ax := Vector3(mdir.x, 0.0, mdir.z).normalized() if Vector3(mdir.x, 0.0, mdir.z).length() > 0.01 else fwd
					var perp := ax.cross(Vector3.UP).normalized()
					var ang := mk * TAU + (0.0 if i == 1 else 0.25)
					hold_wrist = mpt + (Vector3.UP * cos(ang) + perp * sin(ang)) * 0.22 + right * s * 0.05
					hold_basis = _hand_basis((fwd * 0.6 + Vector3.DOWN * 0.4).normalized(), up * s)
					curl = 1.0
					pole_l = Vector3(s * 0.8, -0.4, 0.3)
				24:
					# шаг 103: траверс по перилам над дырой: обе руки на канате перед грудью (канат — вдоль mdir),
					# перехват: рука mk-целое отрывается, скользит вдоль каната и снова хватает
					var ax24 := mdir.normalized()
					if ax24.dot(right) < 0.0:
						ax24 = -ax24
					var mh24 := int(mk)
					var ph24 := clampf(mk - float(mh24), 0.0, 1.0)
					var gb24 := _grip_basis(ax24 * s, fwd * 0.5 + up * 0.8)
					var p24 := mpt + ax24 * s * 0.25
					var c24 := 1.0
					if i == mh24 and ph24 < 1.0:
						var lift24 := sin(PI * ph24)
						p24 += (up * 0.09 - fwd * 0.05) * lift24 + ax24 * s * 0.1 * lift24
						c24 = 1.0 - 0.65 * lift24
					hold_basis = gb24
					hold_wrist = _wrist_for(p24, gb24, s)
					curl = c24
					pole_l = Vector3(s * 0.85, -0.45, 0.1)
				10:
					# тяну оттяжку: обе руки на верёвке, вперёд-вверх к корзине
					var dh := Vector3(mdir.x, 0.0, mdir.z).normalized() if Vector3(mdir.x, 0.0, mdir.z).length() > 0.01 else fwd
					hold_wrist = vp + up * (1.05 + 0.1 * i) + dh * (0.32 + 0.16 * i) + right * s * 0.05
					hold_basis = _hand_basis((dh * 0.6 + up * 0.4).normalized(), up * s)
					curl = 1.0
					pole_l = Vector3(s * 0.8, -0.5, 0.2)
				11:
					# держу верёвку: одна рука у груди, другая у бедра
					hold_wrist = chest + fwd * 0.28 + right * s * 0.05 if i == 1 else vp + up * 0.8 + right * s * 0.22 + fwd * 0.05
					hold_basis = _hand_basis((fwd * 0.5 + up * 0.3).normalized(), up * s)
					curl = 1.0
					pole_l = Vector3(s * 0.75, -0.5, 0.2)
				17:
					# шаг 77: на ледорубах. Вбитый — кулак на рукояти под головой (голова в скале);
					# замах — рука уходит вверх-назад от скалы и бьёт в цель; свободная — у бедра
					var kk17 := int(mk)
					var tq := (mk - float(kk17)) * 100.0
					var qa := (kk17 % 100) if i == 0 else ((kk17 / 100) % 100)
					var swc := (kk17 / 10000) % 10
					var ph17 := float(kk17 / 100000) / 99.0
					var md := Vector3(mdir.x, 0.0, mdir.z).normalized() if Vector3(mdir.x, 0.0, mdir.z).length() > 0.01 else fwd
					var lat := md.cross(Vector3.UP).normalized()
					var planted_b := _hand_basis(md, -lat)
					if swc - 1 == i:
						# шаг 78: выдернул (рывок на себя) → широкий замах за голову → резкий удар клювом в скалу → дрожь
						var tgt := mpt + Vector3.UP * (tq / 20.0) + lat * s * 0.2
						var p_low := tgt - Vector3.UP * 0.6 - md * 0.12
						var p_out := p_low - md * 0.3 + Vector3.UP * 0.12
						# шаг 80: замах шире — за голову, далеко от скалы; удар с разгоном; после — отдача и дрожь
						var p_back := tgt - md * 1.0 + Vector3.UP * 0.62 + lat * s * 0.24
						var p_hit := tgt - Vector3.UP * 0.42 - md * 0.1
						var b_back := _hand_basis((Vector3.UP * 0.25 - md * 1.0).normalized(), -lat)
						if ph17 < 0.16:
							var a17 := smoothstep(0.0, 1.0, ph17 / 0.16)
							hold_wrist = p_low.lerp(p_out, a17) + Vector3.DOWN * 0.06 * sin(a17 * PI)
							hold_basis = planted_b.slerp(_hand_basis((md * 0.7 + Vector3.UP * 0.7).normalized(), -lat), a17 * 0.5)
						elif ph17 < 0.55:
							var b17 := smoothstep(0.0, 1.0, (ph17 - 0.16) / 0.39)
							hold_wrist = p_out.lerp(p_back, b17) + Vector3.UP * sin(b17 * PI) * 0.18
							hold_basis = planted_b.slerp(b_back, b17)
						elif ph17 < 0.7:
							var c17 := pow((ph17 - 0.55) / 0.15, 2.2)
							hold_wrist = p_back.lerp(p_hit, c17) + Vector3.UP * sin(c17 * PI) * 0.1
							hold_basis = b_back.slerp(planted_b, c17)
						else:
							var d17 := (ph17 - 0.7) / 0.3
							hold_wrist = p_hit - md * 0.05 * exp(-d17 * 6.0) + md * 0.03 * sin(d17 * PI * 4.0) * (1.0 - d17) + Vector3.DOWN * 0.04 * exp(-d17 * 5.0)
							hold_basis = planted_b
						curl = 1.0
					elif qa < 99:
						var head := mpt + Vector3.UP * (float(qa) / 20.0) + lat * s * 0.2
						hold_wrist = head - Vector3.UP * 0.42 - md * 0.1
						hold_basis = planted_b
						curl = 1.0
					else:
						hold_wrist = vp + Vector3.UP * 0.95 + right * s * 0.32 - md * 0.1
						hold_basis = _hand_basis((Vector3.DOWN * 0.9 + md * 0.2).normalized(), right * s)
						curl = 1.0
					pole_l = Vector3(s * 0.7, -0.4, 0.3)
				19:
					# шаг 80: вылезаю на ледорубах: клювы зацеплены за край сверху, тяну → локти на край → отжимаюсь
					# ладонями (ледорубы плашмя) → встаю, ледорубы перед собой
					var md19 := Vector3(mdir.x, 0.0, mdir.z).normalized() if Vector3(mdir.x, 0.0, mdir.z).length() > 0.01 else fwd
					var lat19 := md19.cross(Vector3.UP).normalized()
					var edge19 := mpt
					if mk < 0.32:
						hold_wrist = edge19 + md19 * 0.22 + Vector3.UP * 0.08 + lat19 * s * 0.26
						hold_basis = _hand_basis((md19 * 0.4 - Vector3.UP * 0.9).normalized(), -lat19)
						curl = 1.0
						pole_l = Vector3(s * 0.8, 0.1, 0.4)
					elif mk < 0.6:
						var b19 := smoothstep(0.0, 1.0, (mk - 0.32) / 0.28)
						hold_wrist = edge19 + md19 * lerpf(0.22, 0.45, b19) + Vector3.UP * 0.06 + lat19 * s * 0.24
						hold_basis = _hand_basis((md19 * 0.9 - Vector3.UP * lerpf(0.9, 0.1, b19)).normalized(), -lat19)
						curl = 1.0
						pole_l = Vector3(s * 0.6, -0.6, 0.1)
					elif mk < 0.82:
						hold_wrist = edge19 + md19 * 0.3 + Vector3.UP * 0.05 + lat19 * s * 0.3
						hold_basis = _hand_basis((md19 * 0.6 - Vector3.UP * 0.8).normalized(), -lat19)
						curl = 0.9
						pole_l = Vector3(s * 0.9, -0.2, 0.3)
					else:
						var e19 := smoothstep(0.0, 1.0, (mk - 0.82) / 0.18)
						hold_wrist = (edge19 + md19 * 0.3 + Vector3.UP * 0.05 + lat19 * s * 0.3).lerp(vp + up * 1.1 + fwd * 0.42 + right * s * 0.2, e19)
						hold_basis = _hand_basis((md19 * 0.6 - Vector3.UP * 0.8).normalized(), -lat19).slerp(_hand_basis(fwd, -right), e19)
						curl = 1.0
						pole_l = Vector3(s * 0.7, -0.3, 0.3)
				20:
					# шаг 86: щуп двумя руками: правая ниже, левая выше по древку; замах вверх → тычок вниз-вперёд → назад
					var k20 := mk
					var up20 := 0.12 * smoothstep(0.0, 0.3, k20) * (1.0 - smoothstep(0.3, 0.42, k20))
					var push20 := smoothstep(0.3, 0.5, k20) * (1.0 - smoothstep(0.75, 1.0, k20))
					var wig := sin(k20 * 40.0) * 0.015 * float(k20 > 0.5 and k20 < 0.75)
					var g20 := vp + fwd * (0.42 + 0.28 * push20) + up * (1.05 + up20 - 0.42 * push20 + wig) + right * 0.1
					var pdir := (g20 - (vp + fwd * 1.45 + Vector3.DOWN * (0.05 + 0.75 * push20))).normalized()
					hold_wrist = g20
					hold_basis = _hand_basis((fwd * 0.6 - up * 0.4).normalized(), -right * s)
					curl = 1.0
					pole_l = Vector3(s * 0.75, -0.4, 0.25)
					if i == 0:
						hold = false               # левая — с ледорубом (держу как обычно)
				21:
					# шаг 87: на животе. Тащит — руки скребут снег (гребу, как на пузе); ЛКМ — левая с ледорубом
					# замах и удар в снег перед головой; держу: левая на ледорубе, правая на верёвке (E — перебирает)
					if mk < 0.5:
						hold = false
					elif i == 1 and mk < 0.69 and not bool(st.get("rope_hold", false)):
						# шаг 89: удар с рывка — правая упирается ладонью в снег справа (не лезет в глаза)
						hold_wrist = mdir + Vector3.DOWN * 0.18 + right * 0.16
						hold_basis = _hand_basis((fwd * 0.2 + Vector3.DOWN * 0.95).normalized(), up * s)
						curl = 0.4
						pole_l = Vector3(s * 0.9, -0.1, 0.2)
					else:
						var rope_pt: Vector3 = mdir
						if i == 0:
							# шаг 91: удар ледорубом — кулак на конце рукояти, ледоруб в кулаке (без зазора):
							# замах высоко (клюв назад-вверх) → резкая дуга вниз → клюв в снег, отдача
							var u21 := clampf((mk - 0.5) / 0.19, 0.0, 1.0) if mk < 0.69 else 1.0
							var hf := Vector3(fwd.x + up.x, 0.0, fwd.z + up.z)
							hf = hf.normalized() if hf.length() > 0.01 else fwd
							var lf := Vector3.UP.cross(hf).normalized()
							var snow21 := mpt - Vector3.UP * 0.36 + hf * 0.24
							var vplant := (snow21 - mpt).normalized()
							var vback := (Vector3.UP * 0.55 - hf * 0.85).normalized()
							var vcarry := (Vector3.DOWN * 0.3 + hf * 0.95).normalized()
							var planted := snow21 - vplant * 0.5
							var raised := planted + Vector3.UP * 0.6 + hf * 0.12 + lf * 0.14
							var fist := planted
							var sv := vplant
							if u21 < 0.38:
								var a21 := smoothstep(0.0, 1.0, u21 / 0.38)
								fist = (planted + Vector3.UP * 0.3 - hf * 0.05).lerp(raised, a21)
								sv = vcarry.slerp(vback, a21)
							elif u21 < 0.62:
								var b21 := pow((u21 - 0.38) / 0.24, 1.6)
								var ctrl := (raised + planted) * 0.5 + hf * 0.42 + Vector3.UP * 0.1
								fist = raised.lerp(ctrl, b21).lerp(ctrl.lerp(planted, b21), b21)
								sv = vback.slerp(vplant, pow((u21 - 0.38) / 0.24, 1.4))
							else:
								var c21 := (u21 - 0.62) / 0.38
								fist = planted + Vector3.UP * 0.05 * sin(minf(c21 * 2.0, 1.0) * PI) * (1.0 - c21)
							hold_basis = _grip_basis(sv, hf + Vector3.UP * 0.6)
							hold_wrist = _wrist_for(fist, hold_basis, s)
							curl = 1.0
							pole_l = Vector3(s * 0.8, 0.2, 0.1)
						else:
							# правая — на верёвке: кулак обхватывает её сверху, верёвка вдоль кулака к краю
							var hf2 := Vector3(fwd.x + up.x, 0.0, fwd.z + up.z)
							hf2 = hf2.normalized() if hf2.length() > 0.01 else fwd
							hold_basis = _grip_basis(hf2 - Vector3.UP * 0.12, Vector3.DOWN + right * 0.3)
							hold_wrist = _wrist_for(rope_pt, hold_basis, s)
							curl = 1.0
							pole_l = Vector3(s * 0.8, -0.1, 0.2)
				22:
					# шаг 86/87: вишу на верёвке: руками за неё над головой; перехват — рука тянется выше;
					# лечу вниз — руки вразлёт, потом хватаю верёвку
					# шаг 91: верёвка — одна линия перед грудью; кулаки точно на ней, пальцы обхватывают
					var rf := 0.2
					# шаг 133: кулаки — точно на самой верёвке (от обвязки к краю), ось кулака — вдоль неё;
					# хват сверху: тыльная сторона кисти к себе, пальцы обхватывают верёвку (кисть не выворачивается)
					var r_a := harness_point()
					var r_ax := (mpt - r_a)
					r_ax = r_ax.normalized() if r_ax.length() > 0.3 else up
					if r_ax.dot(up) < 0.2:
						r_ax = up
					# шаг 134: обе кисти — зеркально одинаковые (большой палец сверху, костяшки к верёвке)
					var gb22 := _grip_basis(-r_ax, -right * s * 0.8 + fwd * 0.4)
					if mk >= 3.0:
						# вишу на весу: обе руки на верёвке; тянут — подтягиваюсь
						var c22a := mk - 3.0
						var drop22 := 0.1 * sin(PI * clampf(c22a / 0.5, 0.0, 1.0)) if c22a > 0.0 and c22a < 0.5 else 0.0
						var hy22 := (1.78 if i == 0 else 1.58) - drop22
						if fp_on:
							hy22 = (1.42 if i == 0 else 1.26) - drop22      # от 1-го лица руки ниже — не заслоняют вид
						hold_basis = gb22
						hold_wrist = _wrist_for(_on_rope(r_a, r_ax, vp.y + hy22, vp + up * hy22 + fwd * rf), gb22, s)
						curl = 1.0
						pole_l = Vector3(s * 0.8, -0.1, 0.35)
					elif mk >= 2.0:
						var fk22 := mk - 2.0
						var flail := Vector3(s * 0.55, 1.35 + sin(_t * 17.0 + i) * 0.15, 0.1 + cos(_t * 13.0 + i) * 0.12)
						var grab := Vector3(0.0, 1.74 - 0.16 * float(i), rf)
						if fp_on:
							flail = Vector3(s * 0.62, 1.05 + sin(_t * 17.0 + i) * 0.15, 0.25 + cos(_t * 13.0 + i) * 0.1)
							grab = Vector3(0.0, 1.42 - 0.16 * float(i), rf)
						var gk := smoothstep(0.45, 0.8, fk22)
						var lv22 := flail.lerp(grab, gk)
						hold_basis = _hand_basis((up * 0.9 + fwd * 0.3).normalized(), right * s).slerp(gb22, gk)
						hold_wrist = _wrist_for(vp + right * lv22.x + up * lv22.y + fwd * lv22.z, hold_basis, s)
						curl = lerpf(0.2, 1.0, smoothstep(0.5, 0.8, fk22))
						pole_l = Vector3(s * 0.8, -0.1, 0.35)
					else:
						# лезу: рука скользит вверх по верёвке (пальцы приоткрыты) → хват → тяну вниз; другая держит
						var hi22a := int(mk)
						var ph22a := clampf(mk - float(hi22a), 0.0, 1.0)
						var lo := 1.18 if fp_on else 1.5
						var hi := 1.6 if fp_on else 1.95
						# шаг 134: перехват без рывков — одна рука тянется вверх (пальцы приоткрыты) → хват → тянет вниз,
						# вторая всё это время держит и плавно уходит вниз (тело поднимается); конец одной фазы = начало другой
						var bot22 := lo - 0.12
						var top22 := lo + 0.14
						var y22 := lerpf(top22, bot22, smoothstep(0.0, 1.0, ph22a))
						var c22 := 1.0
						if i == hi22a:
							if ph22a < 0.4:
								var e22 := smoothstep(0.0, 1.0, ph22a / 0.4)
								y22 = lerpf(bot22, hi, e22)
								c22 = lerpf(1.0, 0.3, smoothstep(0.0, 0.25, ph22a / 0.4)) if ph22a < 0.1 else 0.3
							elif ph22a < 0.52:
								y22 = hi + 0.02 * sin(PI * (ph22a - 0.4) / 0.12)
								c22 = lerpf(0.3, 1.0, smoothstep(0.0, 1.0, (ph22a - 0.4) / 0.12))
							else:
								y22 = lerpf(hi, top22, smoothstep(0.0, 1.0, (ph22a - 0.52) / 0.48))
						hold_basis = gb22
						hold_wrist = _wrist_for(_on_rope(r_a, r_ax, vp.y + y22, vp + up * y22 + fwd * rf), gb22, s)
						curl = c22
						# локоть: тянусь — под руку, к груди; тяну — в сторону и назад (как настоящий перехват)
						var pk22 := 0.0
						if i == hi22a:
							pk22 = smoothstep(0.5, 0.75, ph22a)
						else:
							pk22 = 1.0 - smoothstep(0.0, 0.3, ph22a)
						pole_l = Vector3(s * lerpf(0.55, 0.9, pk22), lerpf(-0.35, 0.0, pk22), lerpf(0.15, 0.4, pk22))
				18:
					# шаг 77: замах ледорубом без опоры: вверх-за голову → удар вперёд-вниз
					var h18 := int(mk)
					if h18 != i:
						hold = false
					else:
						var ph18 := mk - float(h18)
						# шаг 78: замах из стойки за голову → удар вперёд-вниз → доводка
						var r18 := vp + up * 1.12 + fwd * 0.34 + right * s * 0.2
						var w_up := chest + up * 0.6 - fwd * 0.3 + right * s * 0.2
						var w_hit := vp + up * 1.5 + fwd * 0.68 + right * s * 0.14
						var w_fol := vp + up * 1.15 + fwd * 0.6 + right * s * 0.16
						var b_rd := _hand_basis(fwd, -right)
						var b_up := _hand_basis((up * 0.5 - fwd * 0.85).normalized(), -right)
						var b_hit := _hand_basis((fwd * 0.85 + Vector3.DOWN * 0.3).normalized(), -right)
						if ph18 < 0.45:
							var b18 := smoothstep(0.0, 1.0, ph18 / 0.45)
							hold_wrist = r18.lerp(w_up, b18)
							hold_basis = b_rd.slerp(b_up, b18)
						elif ph18 < 0.68:
							var c18 := pow((ph18 - 0.45) / 0.23, 1.5)
							hold_wrist = w_up.lerp(w_hit, c18)
							hold_basis = b_up.slerp(b_hit, c18)
						else:
							var e18 := smoothstep(0.0, 1.0, (ph18 - 0.68) / 0.32)
							hold_wrist = w_hit.lerp(w_fol, e18)
							hold_basis = b_hit.slerp(b_rd, e18)
						curl = 1.0
						pole_l = Vector3(s * 0.7, -0.3, 0.3)
				14:
					# шаг 74: ставлю деталь в гнездо: вставляю (толкаю двумя руками) → доворачиваю (кисти по кругу)
					# → закручиваю болты (правая — ключом по кругу, левая упирается в корпус)
					var ax14 := mdir.normalized() if mdir.length() > 0.01 else fwd
					var p1 := ax14.cross(Vector3.UP)
					if p1.length() < 0.1:
						p1 = ax14.cross(Vector3.RIGHT)
					p1 = p1.normalized()
					var p2 := ax14.cross(p1).normalized()
					if mk < 0.34:
						var a14 := mk / 0.34
						hold_wrist = mpt - ax14 * lerpf(0.42, 0.12, a14) + right * s * 0.15 + up * 0.02
						hold_basis = _hand_basis((ax14 * 0.8 + right * -s * 0.3).normalized(), -right * s)
						curl = 0.7
					elif mk < 0.6:
						var b14 := (mk - 0.34) / 0.26
						var ph14 := b14 * 1.4 + (0.0 if i == 1 else PI)
						hold_wrist = mpt - ax14 * 0.12 + (p1 * cos(ph14) + p2 * sin(ph14)) * 0.17
						hold_basis = _hand_basis((ax14 * 0.7 - (p1 * cos(ph14) + p2 * sin(ph14)) * 0.5).normalized(), p1 * s)
						curl = 0.95
					elif i == 1:
						var c14 := mk * TAU * 7.0
						hold_wrist = mpt - ax14 * 0.2 + (p1 * cos(c14) + p2 * sin(c14)) * 0.08 + up * 0.04
						hold_basis = _hand_basis((ax14 * 0.6 + Vector3.DOWN * 0.3).normalized(), up * s)
						curl = 1.0
					else:
						hold_wrist = mpt - ax14 * 0.16 + right * s * 0.32 + up * 0.12
						hold_basis = _hand_basis((ax14 * 0.9 + up * 0.1).normalized(), -right * s)
						curl = 0.25
					pole_l = Vector3(s * 0.75, -0.3, 0.3)
				15:
					# обе руки на рукояти рычага
					hold_wrist = mpt + right * s * 0.09 + Vector3.DOWN * 0.02
					hold_basis = _hand_basis((fwd * 0.5 + Vector3.DOWN * 0.5).normalized(), up * s)
					curl = 1.0
					pole_l = Vector3(s * 0.8, -0.45, 0.25)
				16:
					# рукоять мехов: обе руки сверху, ходят вверх-вниз вместе с ней
					hold_wrist = mpt + right * s * 0.12 + up * 0.03
					hold_basis = _hand_basis((fwd * 0.4 + Vector3.DOWN * 0.6).normalized(), up * s)
					curl = 1.0
					pole_l = Vector3(s * 0.8, -0.3, 0.3)
				13:
					# охапка дров перед собой, ладони снизу
					hold_wrist = vp + fwd * 0.42 + up * 0.95 + right * s * 0.3
					hold_basis = _hand_basis((fwd * 0.7 - right * s * 0.3).normalized(), -up * s)
					curl = 0.6
					pole_l = Vector3(s * 0.7, -0.5, 0.3)
				_:
					hold = false
		# шаг 78: ледорубы в руках — держу перед собой, клювом вперёд, головой вверх (покачиваются на ходу)
		if not hold and bool(st.get("ice_axes", false)) and not arm_iced and not dead:
			var bob := sin(_t * 9.0 + i * PI) * 0.035 * clampf(spd / 6.0, 0.0, 1.0)
			hold_wrist = _vis.global_position + up * (1.1 + bob) + fwd * 0.34 + right * s * 0.21
			hold_basis = _hand_basis((fwd + right * s * 0.12).normalized(), -right)
			hold = true
			curl = 1.0
			pole_l = Vector3(s * 0.75, -0.45, 0.2)
		# шаг 87: ледоруб в левой — несу у бедра, головой в ладони
		if not hold and i == 0 and bool(st.get("probe", false)) and not arm_iced and not dead:
			var swl := sin(_t * 9.0 + PI) * 0.04 * clampf(spd / 6.0, 0.0, 1.0)
			hold_wrist = _vis.global_position + up * 0.92 + fwd * (0.12 + swl) - right * 0.33
			hold_basis = _hand_basis((fwd * 0.2 - up * 0.98).normalized(), right)
			hold = true
			curl = 1.0
			pole_l = Vector3(-0.7, -0.5, 0.2)
		var digging := bool(st.get("dig", false))
		if fp_on and digging and not hold and not arm_iced and not dead:
			# откапываю друга: обе руки по очереди гребут снег перед собой
			var dph := fposmod(_t * 2.4 + i * 0.5, 1.0)
			var dsc := sin(dph * TAU)
			hold_wrist = tx * (sh_l + Vector3(s * 0.06, -0.42 + 0.14 * dsc, -0.38 - 0.14 * cos(dph * TAU)))
			hold_basis = _hand_basis((fwd * 0.35 - up * 0.9).normalized(), right * s)
			hold = true
			curl = 0.75
			pole_l = Vector3(s * 0.7, -0.4, 0.3)
		if fp_free and not hold and not arm_iced and _punch_t > 0.0 and i == 1 and not digging:
			# от 1-го лица свободных рук не видно (висят вдоль тела, ниже кадра) —
			# кулак влетает в кадр только при ударе
			var pk := sin(PI * (1.0 - _punch_t / 0.35))
			var vb := fpf.basis
			hold_wrist = wrist_free.lerp(fpf * Vector3(0.12, -0.2, -0.64), pk)
			hold_basis = _hand_basis((vb * Vector3(-0.15, 0.1, -1.0)).normalized(), (vb * Vector3(0.8, 0.6, 0.0)) * s)
			hold = true
			curl = 1.0
			pole_l = Vector3(s * 0.7, -0.6, 0.2)
		hold_wrist += trem
		if hold:
			# один хват сменился другим (взял → кладу, ремонт → отпустил…) — рука переезжает плавно, без рывка
			var hl := tx.affine_inverse() * hold_wrist
			if _hold_w[i] > 0.3 and hl.distance_to(_hold_raw[i]) > 0.15:
				_hold_off[i] -= hl - _hold_raw[i]
			_hold_raw[i] = hl
			_hold_off[i] = _hold_off[i].lerp(Vector3.ZERO, clampf(delta * 10.0, 0.0, 1.0))
			hold_wrist = tx * (hl + _hold_off[i])
			_hold_last[i] = hl + _hold_off[i]
			_hold_last_b[i] = tx.basis.orthonormalized().inverse() * hold_basis.orthonormalized()
		elif _hold_w[i] > 0.0:
			# отпустил — рука возвращается из того места, где держала (а не тянется к нулю мира)
			hold_wrist = tx * _hold_last[i]
			hold_basis = tx.basis.orthonormalized() * _hold_last_b[i]
		_hold_w[i] = move_toward(_hold_w[i], 1.0 if hold else 0.0, delta * (9.0 if hold else 5.0))
		var hw := _hold_w[i]
		var wrist := wrist_free.lerp(hold_wrist, hw) if hw > 0.0 else wrist_free
		# шаг 70: от 1-го лица руки, занятые делом, — в кадре (если ушли за край — подтягиваю к краю кадра);
		# на бегу рука на взмахе вперёд мелькает у нижнего края
		if fp_on and not dead and not arm_iced:
			var act: bool = not rep.is_empty() or not rip.is_empty() or digging or lift != null or rope_st >= 1 \
				or (climbing > 0 and not int(st.get("mpose", 0)) in [50, 51, 52]) or (int(st.get("mpose", 0)) > 0 and not int(st.get("mpose", 0)) in [27, 28, 29, 50, 51, 52])
			# шаг 93: от 1-го лица руки — как от 3-го (не поднимаю их в кадр сам); в кадр — только когда заняты делом
			_fp_show[i] = move_toward(float(_fp_show[i]), 1.0 if act else 0.0, delta * 5.0)
			var kk := float(_fp_show[i])
			var bottom := 0.74
			if ath > 0.15 and not hold and not act and not crawling:
				# шаг 124: бегу — кулаки по очереди взлетают в нижнюю часть кадра (на трусце — мелькают у края)
				var wl2 := tx.affine_inverse() * wrist
				var kr := (0.5 + 0.45 * ath) * smoothstep(-0.02, -0.2, wl2.z)
				if kr > kk:
					kk = kr
					bottom = lerpf(0.76, 0.56, ath)
			if not act and not crawling and carry == 0 and cl == null and stick == null:
				# смотрю вниз — свои руки по бокам видны у нижних углов кадра (а оторванной — нет)
				var kd := 0.85 * smoothstep(-0.55, -1.15, _fp_pitch)
				if kd > kk:
					kk = kd
					bottom = 0.7
			kk *= 1.0 - smoothstep(0.25, 0.7, _fp_pitch)        # смотрю вверх — руки не тяну к лицу
			if kk > 0.001:
				wrist = wrist.lerp(_fp_into_view(wrist, i, 0.92 if (lift != null or climbing > 0) else 0.3, bottom), kk)
		else:
			_fp_show[i] = 0.0
		var S := tx * sh_l + _strain_gap(LIMBS[i])
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
			if not _broken:
				pv.rotation = Vector3(0, 0, -s * maxf(_hang, 0.0) * (1.0 if hp < 0.3 else 0.2))
		if not (_broken and i == 1):
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
	if hp < 0.5 and not swim and not dead:
		_spark_t -= delta
		if _spark_t <= 0.0:
			# чем хуже корпус, тем чаще искрит — из суставов и из вмятин
			_spark_t = randf_range(0.35, 1.4) * (0.3 + hp * 2.0)
			var at: Vector3
			var dent := _random_dent_point()
			if dent != Vector3.INF and randf() < 0.6:
				at = dent
			else:
				var joints := [knees[0], knees[1], (_arms[0]["fore"] as Node3D).global_position, (_arms[1]["fore"] as Node3D).global_position, neck.global_position]
				at = joints[randi() % joints.size()]
			_sparks.global_position = at
			_sparks.restart()
			if hp < 0.3 and randf() < 0.5:
				_ping(at, Color(0.6, 0.85, 1.0), 0.05)          # короткое замыкание — голубая вспышка
				jolt(0.15)
	_post_limb_fx(delta, tumble, flop, rep)
	var bs: float = float(st.get("belly_spd", 0.0))
	var spray := belly_on and on_floor and bs > 1.2
	_belly_fx.emitting = spray and not bool(st.get("belly_ice", false))
	_belly_ice_fx.emitting = spray and bool(st.get("belly_ice", false))
	if spray:
		(_belly_fx.process_material as ParticleProcessMaterial).initial_velocity_max = 1.5 + bs * 0.35
		_belly_fx.amount_ratio = clampf(bs / 8.0, 0.3, 1.0)
	_update_ice(delta)


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
				# раскручиваю крюк сбоку: кисть описывает маленький круг и ведёт крюк
				# (тот же угол, что у крюка — rope_tool._swing_a, рука чуть впереди)
				var a := float(rp.get("swing_a", 0.0)) + 0.5
				var rad := Vector3(0.0, cos(a), 0.0) + fwd * sin(a)
				var c := tx * Vector3(0.3, 0.42, -0.06)
				var w := c + rad * (0.11 + 0.04 * float(rp.get("charge", 0.0)))
				return [true, w, _hand_basis(rad.normalized(), side * s), 1.0, Vector3(s * 0.8, -0.3, 0.3)]
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
			# держу верёвку перед собой обеими кулаками: правый — дальше по верёвке,
			# левый — ближе (через него хвост уходит к мотку на поясе)
			var low := -up * (0.2 if rope_st == 7 else 0.13)
			var d := 0.5 if i == 1 else 0.24
			var rp0 := chest + rope_dir * d + low
			var g := _rope_grip(rp0, rope_dir, up, side, s)
			return [true, g[0], g[1], 1.0, Vector3(s * 0.65, -0.5, 0.3)]
		5:
			# перехват: рука тянется вперёд раскрытой, хватает и тянет к себе кулаком;
			# руки чередуются — в такт рывкам верёвки
			var haul := float(rp.get("haul", _t * 1.5))
			var ph := fposmod(haul + i * 0.5, 1.0)
			var d := 0.0
			var lift_u := 0.0
			var curl := 1.0
			if ph < 0.5:
				var u := ph / 0.5
				d = lerpf(0.7, 0.08, u * u * (3.0 - 2.0 * u))
			else:
				var u := (ph - 0.5) / 0.5
				var e := u * u * (3.0 - 2.0 * u)
				d = lerpf(0.08, 0.7, e)
				lift_u = sin(u * PI) * 0.09
				curl = lerpf(0.2, 1.0, smoothstep(0.75, 1.0, u))
			var rp1 := chest + rope_dir * d - up * 0.16 + up * lift_u
			var g := _rope_grip(rp1, rope_dir, up, side, s)
			var wr: Vector3 = g[0]
			if ph >= 0.5:
				wr += up * 0.04          # раскрытая ладонь идёт чуть над тросом
			return [true, wr, g[1], curl, Vector3(s * 0.65, -0.55, 0.35)]
		6:
			# волоку: верёвка через правое плечо, руки у плеча
			var w4 := tx * (Vector3(0.2, 0.4, -0.22) if i == 1 else Vector3(0.05, 0.32, -0.27))
			return [true, w4, _hand_basis(-up, fwd), 0.95, Vector3(s * 0.6, -0.5, 0.2)]
	return [false, Vector3.ZERO, Basis.IDENTITY, 0.35, Vector3(s * 0.55, -0.35, 0.45)]


## Кулак на верёвке: пальцы обхватывают трос поперёк, тыльная сторона наружу.
## Возвращает [запястье, базис ладони] — середина ладони ровно на точке троса.
func _rope_grip(rope_pt: Vector3, rdir: Vector3, up: Vector3, side: Vector3, s: float) -> Array:
	var r := rdir.normalized()
	var fdir := -up * 0.75 - side * s * 0.4
	fdir = fdir - r * fdir.dot(r)
	if fdir.length() < 0.01:
		fdir = -up
	fdir = fdir.normalized()
	# тыльная сторона кулака — наружу и чуть вверх (у _hand_basis ось X ладони = тыл * s)
	var back := (side * s + up * 0.35) * s
	back = back - r * back.dot(r)
	var b := _hand_basis(fdir, back)
	return [rope_pt + b.x * (s * GRIP_IN) - fdir * (HAND + 0.015), b]


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
	var fs: Array = am.get("fingers", [am["f1"], am["f2"]])
	# шаг 124: полусогнутая кисть — «каскадом» (указательный прямее, мизинец согнут сильнее), открытая — пальцы веером
	var relax := 1.0 - absf(2.0 * clampf(c, 0.0, 1.0) - 1.0)
	var bias := [-0.11, -0.03, 0.05, 0.13]
	for k in fs.size():
		var f: Array = fs[k]
		var lag := 1.0 + 0.06 * float(k)          # мизинец сгибается чуть сильнее — кулак плотнее
		var ck := clampf(c + float(bias[k % 4]) * relax, 0.0, 1.08) if fs.size() == 4 else c
		(f[0] as Node3D).rotation.z = -s * ck * 1.25 * lag
		(f[0] as Node3D).rotation.x = (float(k) - 1.5) * 0.075 * (1.0 - clampf(c * 1.6, 0.0, 1.0)) if fs.size() == 4 else 0.0
		(f[1] as Node3D).rotation.z = -s * ck * 1.45 * lag
		if f.size() > 2:
			(f[2] as Node3D).rotation.z = -s * ck * 1.1 * lag
	var th: Array = am["th"]
	(th[0] as Node3D).rotation.x = 0.35 * smoothstep(0.55, 1.0, c)
	(th[0] as Node3D).rotation.z = -s * c * 0.75
	(th[1] as Node3D).rotation.z = -s * c * 0.85
	if th.size() > 2:
		(th[2] as Node3D).rotation.z = -s * c * 0.6


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
	var dtt := float(st.get("death_t", -1.0))
	if dead:
		mood = Mood.OFF
		if dtt >= 0.0 and dtt < 1.1:
			mood = Mood.HURT if fmod(dtt * 9.0, 1.0) < 0.55 else Mood.OFF     # глаза мигают и гаснут
		elif dtt >= 1.1 and dtt < D_FALL:
			mood = Mood.TIRED if randf() > 0.12 else Mood.OFF                  # слабеет, помехи
		elif dtt >= D_BLIP and dtt < D_BLIP + 0.22:
			mood = Mood.NORMAL                                                  # последний блик
	elif st.get("downed", false):
		mood = Mood.TIRED
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink_t = randf_range(2.0, 5.0)
		_blink = 1.0
	_blink = maxf(_blink - delta * 8.0, 0.0)
	var power := 1.0
	if hp < 0.25 and not dead:
		power = 0.15 if randf() < 0.08 else randf_range(0.7, 1.0)
	if dead and dtt >= 0.0 and dtt < 1.1:
		power = randf_range(0.05, 1.0) * (1.0 - dtt / 1.1)
	elif dead and dtt >= 1.1 and dtt < D_FALL:
		var fade := 1.0 - (dtt - 1.1) / (D_FALL - 1.1)
		power = (0.25 + 0.55 * fade) * (randf_range(0.3, 1.0) if randf() < 0.3 else 1.0)
	elif dead and dtt >= D_BLIP and dtt < D_BLIP + 0.22:
		power = 0.6 * sin((dtt - D_BLIP) / 0.22 * PI)
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
		if _hand_led:
			_hand_led.albedo_color = c
			_hand_led.emission = c


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
	_wear = pow(1.0 - hp, 0.8)
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
	# страховочное кольцо на поясе спереди — за него цепляется крюк верёвки
	_part(pelvis, _box(Vector3(0.09, 0.055, 0.025)), _armor("steel", false), Vector3(0, 0.0, -0.19))
	_harness = _part(pelvis, _torus(0.026, 0.042, 16), _plain(Color(0.95, 0.78, 0.2), 0.9, 0.25), Vector3(0, -0.045, -0.225), Vector3(0, 0, PI * 0.5))
	_build_limb_details()


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


# ---------------------------------------------------------------------------
#  Руки и ноги можно потерять (удар, друг оторвал) и прикрутить обратно.
#  На месте оторванной — культя: фланец, тёмное гнездо, болтающиеся провода,
#  искры и капли гидравлики.
# ---------------------------------------------------------------------------
func _build_limb_details() -> void:
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		_make_stump(torso, SHOULDER * Vector3(s, 1, 1), Vector3(0, 0, s * 1.15), LIMBS[i])
		_make_stump(pelvis, Vector3(s * HIP_X, -0.09, 0.0), Vector3.ZERO, LIMBS[2 + i])
	# гаечный ключ в кобуре на поясе справа (им друг прикручивает детали)
	_wrench_holster = Node3D.new()
	_wrench_holster.position = Vector3(0.21, -0.1, 0.12)
	_wrench_holster.rotation = Vector3(0.25, 0, -0.2)
	pelvis.add_child(_wrench_holster)
	_part(_wrench_holster, _box(Vector3(0.05, 0.11, 0.04)), _armor("rubber", false), Vector3(0, -0.03, 0))
	_wrench_shape(_wrench_holster, Vector3(0, 0.05, 0))
	_wrench_hand = Node3D.new()
	_wrench_hand.visible = false
	_wrench_hand.top_level = true
	add_child(_wrench_hand)
	_wrench_shape(_wrench_hand, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	# провода между гнездом и рукой/ногой, когда её тянут
	var wcols2 := [Color(0.85, 0.15, 0.1), Color(0.95, 0.8, 0.15), Color(0.15, 0.4, 0.9)]
	for k in 3:
		var sw := MeshInstance3D.new()
		sw.mesh = _cyl(0.008, 0.008, 1.0, 6)
		sw.material_override = _plain(wcols2[k], 0.2, 0.5)
		sw.top_level = true
		sw.visible = false
		sw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sw)
		_strain_wires.append(sw)
	_bolt_mat = _plain(Color(0.72, 0.72, 0.76), 0.95, 0.25)
	# паника — капли летят с шлема
	_sweat = FX.particles(Color(0.7, 0.9, 1.0, 0.85), 14, 0.6, 0.014, 1.2, 2.4, Vector3(0, -7, 0), 60.0, false)
	_sweat.position = Vector3(0, 0.18, 0)
	head.add_child(_sweat)
	# плюхнулся — звёздочки над головой
	_stars = Node3D.new()
	_stars.top_level = true
	_stars.visible = false
	add_child(_stars)
	for k in 5:
		var star := MeshInstance3D.new()
		star.mesh = _sphere(0.022, -1.0, 6)
		star.material_override = _plain(Color(1.0, 0.86, 0.25), 0.0, 0.4, 3.0)
		star.position = Vector3(cos(k * TAU / 5.0) * 0.2, sin(k * 2.3) * 0.03, sin(k * TAU / 5.0) * 0.2)
		star.scale = Vector3(1.0, 0.45, 1.0)
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stars.add_child(star)
	# брелок-кабанчик на ранце: болтается на цепочке
	var hook := Node3D.new()
	hook.position = Vector3(0.14, -0.18, 0.13)
	pack.add_child(hook)
	_charm = Node3D.new()
	hook.add_child(_charm)
	var chain_m := _plain(Color(0.75, 0.75, 0.78), 0.9, 0.3)
	for k in 3:
		_part(_charm, _torus(0.006, 0.011, 8), chain_m, Vector3(0, -0.015 - k * 0.018, 0), Vector3(0, k * 1.5, PI * 0.5 * (k % 2)))
	var pink := _plain(Color(0.95, 0.55, 0.62), 0.0, 0.55)
	var pig := Node3D.new()
	pig.position = Vector3(0, -0.085, 0)
	_charm.add_child(pig)
	_part(pig, _sphere(0.026, -1.0, 12), pink, Vector3.ZERO)
	_part(pig, _cyl(0.012, 0.013, 0.012, 10), _plain(Color(0.9, 0.42, 0.5), 0.0, 0.5), Vector3(0, -0.003, 0.026), Vector3(PI * 0.5, 0, 0))
	for e in [-1.0, 1.0]:
		_part(pig, _cyl(0.0, 0.009, 0.014, 6), pink, Vector3(e * 0.014, 0.025, 0.004), Vector3(0, 0, -e * 0.4))
		_part(pig, _sphere(0.004, -1.0, 6), _plain(Color(0.05, 0.05, 0.05), 0.0, 0.3), Vector3(e * 0.01, 0.008, 0.023))
	# ледяная корка на каждом звене рук и ног (нарастает, когда конечность вмерзает)
	_ice_mat = StandardMaterial3D.new()
	_ice_mat.albedo_color = Color(0.74, 0.88, 1.0, 0.58)
	_ice_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ice_mat.roughness = 0.06
	_ice_mat.metallic_specular = 0.9
	_ice_mat.rim_enabled = true
	_ice_mat.rim = 0.7
	_ice_mat.rim_tint = 0.2
	_ice_mat.emission_enabled = true
	_ice_mat.emission = Color(0.45, 0.68, 0.95)
	_ice_mat.emission_energy_multiplier = 0.18
	_rime_mat = _plain(Color(0.93, 0.97, 1.0), 0.0, 0.85)
	for i in 2:
		var am: Dictionary = _arms[i]
		_ice_nodes[LIMBS[i]] = [
			_ice_shell(am["upper"], UPPER, 0.09, 11 + i, false),
			_ice_shell(am["fore"], 0.26, 0.115, 23 + i, false),
			_ice_shell(am["hand"], 0.16, 0.1, 37 + i, false)]
		var lg: Dictionary = _legs[i]
		_ice_nodes[LIMBS[2 + i]] = [
			_ice_shell(lg["thigh"], THIGH, 0.12, 51 + i, false),
			_ice_shell(lg["shin"], SHIN, 0.11, 67 + i, false),
			_ice_shell(lg["boot"], 0.0, 0.0, 83 + i, true)]
		_ice_grow[LIMBS[i]] = 0.0
		_ice_grow[LIMBS[2 + i]] = 0.0
		# борозда в снегу за волочащейся ногой
		var tr := FX.particles(Color(0.93, 0.96, 1.0, 0.85), 24, 0.7, 0.035, 0.4, 1.4, Vector3(0, -5, 0), 35.0, false)
		(tr.process_material as ParticleProcessMaterial).direction = Vector3(0, 1, 0.6)
		tr.position = Vector3(0, -0.09, -0.15)
		(lg["boot"] as Node3D).add_child(tr)
		_drag_fx.append(tr)
	# оборванные провода (видны, когда корпус плох): у локтей и под коленями
	var wcol3 := [Color(0.85, 0.15, 0.1), Color(0.95, 0.8, 0.15), Color(0.2, 0.45, 0.95)]
	for k in 4:
		var host: Node3D = (_arms[k]["fore"] if k < 2 else _legs[k - 2]["shin"]) as Node3D
		var dn := Node3D.new()
		dn.position = Vector3(0.0, -0.02, 0.07) if k < 2 else Vector3(0.0, -0.08, 0.075)
		dn.visible = false
		host.add_child(dn)
		for j in 2:
			var wn := Node3D.new()
			wn.rotation = Vector3(0.3 * (j * 2 - 1), 0, 0.25 * (j * 2 - 1))
			dn.add_child(wn)
			_part(wn, _cyl(0.006, 0.006, 0.13, 5), _plain(wcol3[(k + j) % 3], 0.2, 0.5), Vector3(0, -0.065, 0))
			_part(wn, _sphere(0.008, -1.0, 6), _plain(Color(0.85, 0.6, 0.3), 0.95, 0.25), Vector3(0, -0.13, 0))
		_dangle.append(dn)
	# свищ в котле: пар бьёт вбок
	_leak = FX.particles(Color(0.95, 0.97, 1.0, 0.5), 30, 0.6, 0.05, 1.5, 2.8, Vector3(0, 0.6, 0), 12.0, false)
	(_leak.process_material as ParticleProcessMaterial).direction = Vector3(1, 0.3, 0.2)
	_leak.position = Vector3(0.16, 0.08, 0.02)
	pack.add_child(_leak)
	# поломка: котёл со свистом стравливает пар вверх
	_death_steam = FX.particles(Color(0.95, 0.97, 1.0, 0.55), 60, 1.4, 0.09, 2.0, 4.0, Vector3(0, 0.8, 0), 18.0, false)
	_death_steam.position = Vector3(0, 0.36, -0.02)
	pack.add_child(_death_steam)
	# сломан: из котла тянется тёмный дымок
	_death_smoke = FX.particles(Color(0.22, 0.22, 0.24, 0.45), 26, 2.6, 0.12, 0.3, 0.8, Vector3(0, 0.9, 0), 20.0, false)
	_death_smoke.local_coords = false
	_death_smoke.position = Vector3(0, 0.2, 0.05)
	pack.add_child(_death_smoke)
	# огоньки сервоприводов на коленях
	for i in 2:
		var m := _plain(Color(0.35, 1.0, 0.55), 0.0, 0.3, 2.5)
		_knee_leds.append(m)
		var led := _part(_legs[i]["shin"] as Node3D, _sphere(0.011, -1.0, 8), m, Vector3(0, -0.07, -0.1))
		no_frost.append(led)


## Ледяная корка вокруг звена (по оси −Y длиной len) или вокруг ботинка
func _ice_shell(parent: Node3D, len: float, r: float, seed_v: int, boot: bool) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := Node3D.new()
	n.visible = false
	parent.add_child(n)
	var parts: Array[MeshInstance3D] = []
	if boot:
		parts.append(_part(n, _box(Vector3(0.21, 0.15, 0.36)), _ice_mat, Vector3(0, -0.05, -0.045), Vector3(0.05, 0.08, -0.04)))
		parts.append(_part(n, _sphere(0.12, 0.16, 7), _ice_mat, Vector3(0.0, 0.01, 0.0), Vector3(0, 0.5, 0)))
		for k in 3:
			var x := rng.randf_range(-0.09, 0.09)
			parts.append(_part(n, _cyl(0.0, 0.03, 0.09, 4), _ice_mat, Vector3(x, -0.02, rng.randf_range(-0.2, 0.1)), Vector3(rng.randf_range(-0.6, 0.6), 0, signf(x) * rng.randf_range(0.6, 1.2))))
	else:
		# основной слой — гранёный, чуть кривой
		parts.append(_part(n, _cyl(r * 1.02, r * 1.18, len * 1.08, 7), _ice_mat, Vector3(0, -len * 0.5, 0), Vector3(rng.randf_range(-0.06, 0.06), rng.randf_range(0, TAU), rng.randf_range(-0.06, 0.06))))
		# иней пятнами
		for k in 2:
			parts.append(_part(n, _sphere(r * 0.75, r * 0.5, 6), _rime_mat, Vector3(rng.randf_range(-r, r) * 0.6, -len * rng.randf_range(0.2, 0.8), rng.randf_range(-r, r) * 0.6), Vector3.ZERO, Vector3(1.0, 0.45, 1.0)))
		# торчащие кристаллы
		for k in 3:
			var a := rng.randf_range(0.0, TAU)
			var out := Vector3(cos(a), 0.0, sin(a))
			var tilt := Basis(out.cross(Vector3.UP).normalized(), rng.randf_range(0.9, 1.35))
			var m := _part(n, _cyl(0.0, r * 0.32, r * 1.5, 4), _ice_mat, out * r * 1.05 + Vector3(0, -len * rng.randf_range(0.15, 0.85), 0))
			m.basis = tilt
		# сосулька
		parts.append(_part(n, _cyl(0.0, r * 0.22, r * 1.8, 5), _ice_mat, Vector3(rng.randf_range(-r, r) * 0.5, -len * 1.02 - r * 0.6, rng.randf_range(-r, r) * 0.5), Vector3(PI, 0, 0)))
	for c in n.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		no_frost.append(c)
	return n


## Конечность вмёрзла / оттаяла: корка нарастает с хрустом или отваливается кусками
func set_ice(mask: int) -> void:
	var old := ice_mask
	ice_mask = mask
	for i in 4:
		var b := 1 << i
		var kind: String = LIMBS[i]
		if (old & b) == 0 and (mask & b) != 0:
			_ice_burst(kind, true)
		elif (old & b) != 0 and (mask & b) == 0:
			_ice_burst(kind, false)


func _ice_burst(kind: String, freezing: bool) -> void:
	if not has_limb(kind):
		return
	var at := _limb_mid(kind)
	if freezing:
		# хрусь: ледяная пыль и искорки инея
		_fx_burst(at, Color(0.85, 0.95, 1.0), 30, 0.5, 0.8, 2.4, Vector3(0, -3, 0))
		_ping(at, Color(0.7, 0.9, 1.0), 0.12)
		jolt(0.5)
		emote(Mood.HURT, 0.8)
	else:
		# оттаяла: корка трескается и отваливается кусками, капает вода
		_fx_burst(at, Color(0.8, 0.92, 1.0), 22, 0.9, 0.6, 2.0, Vector3(0, -12, 0))
		_fx_burst(at, Color(0.55, 0.75, 0.95), 14, 0.8, 0.1, 0.5, Vector3(0, -8, 0))
		emote(Mood.HAPPY, 1.0)


func _limb_mid(kind: String) -> Vector3:
	var i := LIMBS.find(kind)
	if i < 2:
		return (_arms[i]["fore"] as Node3D).global_position
	return (_legs[i - 2]["shin"] as Node3D).global_position


func _update_ice(delta: float) -> void:
	for kind in _ice_nodes:
		var i := LIMBS.find(kind)
		var want := 1.0 if (ice_mask & (1 << i)) != 0 and has_limb(kind) else 0.0
		var g: float = _ice_grow[kind]
		g = move_toward(g, want, delta * (2.2 if want > g else 1.4))
		_ice_grow[kind] = g
		var nodes: Array = _ice_nodes[kind]
		for k in nodes.size():
			var n := nodes[k] as Node3D
			# звенья обрастают по очереди: от тела к кисти/ступне
			var gk := clampf(g * 3.0 - (k if want > 0.5 else 2 - k) * 0.9, 0.0, 1.0)
			n.visible = gk > 0.02
			if n.visible:
				var e := gk * (1.0 + 0.15 * sin(gk * PI))       # с перелётом — «хрусть»
				n.scale = Vector3(lerpf(0.55, 1.0, e), lerpf(0.3, 1.0, e), lerpf(0.55, 1.0, e))


func _wrench_shape(parent: Node3D, pos: Vector3, rot := Vector3.ZERO) -> void:
	var w := Node3D.new()
	w.position = pos
	w.rotation = rot
	parent.add_child(w)
	var chrome := _plain(Color(0.8, 0.82, 0.86), 0.95, 0.18)
	_part(w, _box(Vector3(0.022, 0.16, 0.012)), chrome, Vector3(0, 0, 0))
	_part(w, _box(Vector3(0.026, 0.07, 0.016)), _plain(Color(0.85, 0.2, 0.12), 0.2, 0.5), Vector3(0, -0.045, 0))
	_part(w, _torus(0.014, 0.026, 10), chrome, Vector3(0, 0.09, 0), Vector3(PI * 0.5, 0, 0))


func _make_stump(parent: Node3D, pos: Vector3, rot: Vector3, kind: String) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation = rot
	n.visible = false
	parent.add_child(n)
	_part(n, _cyl(0.07, 0.078, 0.045, 14), _armor("steel", false), Vector3(0, -0.02, 0))
	_part(n, _cyl(0.052, 0.052, 0.02, 12), _plain(Color(0.05, 0.05, 0.06), 0.3, 0.8), Vector3(0, -0.045, 0))
	_rivets(n, Vector3(0, -0.04, 0), 0.066, 6)
	var wires: Array = []
	var wcols := [Color(0.85, 0.15, 0.1), Color(0.95, 0.8, 0.15), Color(0.15, 0.4, 0.9)]
	for k in 3:
		var wn := Node3D.new()
		wn.position = Vector3(cos(k * 2.1) * 0.025, -0.05, sin(k * 2.1) * 0.025)
		n.add_child(wn)
		_part(wn, _cyl(0.007, 0.007, 0.11, 6), _plain(wcols[k], 0.2, 0.5), Vector3(0, -0.055, 0))
		_part(wn, _sphere(0.009, -1.0, 6), _plain(Color(0.8, 0.6, 0.3), 0.9, 0.3), Vector3(0, -0.11, 0))
		wires.append(wn)
	var sp := FX.particles(Color(1.0, 0.78, 0.35, 1.0), 10, 0.35, 0.012, 1.0, 2.6, Vector3(0, -9, 0), 70.0, true, true)
	sp.position = Vector3(0, -0.06, 0)
	n.add_child(sp)
	var dr := FX.particles(Color(0.35, 0.2, 0.05, 0.9), 6, 0.8, 0.012, 0.0, 0.3, Vector3(0, -6, 0), 15.0, false)
	dr.position = Vector3(0, -0.06, 0)
	n.add_child(dr)
	_stumps[kind] = {"node": n, "sparks": sp, "drip": dr, "wires": wires}


func has_limb(kind: String) -> bool:
	return (limb_mask & (1 << LIMBS.find(kind))) != 0


## Какие руки/ноги на месте (маска LIMBS)
func set_limbs(mask: int) -> void:
	limb_mask = mask
	for i in 2:
		var arm_on := (mask & (1 << i)) != 0
		for k in ["upper", "fore", "hand"]:
			(_arms[i][k] as Node3D).visible = arm_on
		(_stumps[LIMBS[i]]["node"] as Node3D).visible = not arm_on
		(_stumps[LIMBS[i]]["drip"] as GPUParticles3D).emitting = not arm_on
		var leg_on := (mask & (4 << i)) != 0
		for k in ["thigh", "shin", "boot", "housing", "rod", "heel"]:
			(_legs[i][k] as Node3D).visible = leg_on and k != "heel"
		(_stumps[LIMBS[2 + i]]["node"] as Node3D).visible = not leg_on
		(_stumps[LIMBS[2 + i]]["drip"] as GPUParticles3D).emitting = not leg_on


## Где крепится рука/нога (мировая система: ось −Y — вдоль конечности)
func socket_xform(kind: String) -> Transform3D:
	var i := LIMBS.find(kind)
	if i < 2:
		var s := -1.0 if i == 0 else 1.0
		return torso.global_transform * Transform3D(Basis.from_euler(Vector3(0, 0, s * 1.15)), SHOULDER * Vector3(s, 1, 1))
	var s2 := -1.0 if i == 2 else 1.0
	return pelvis.global_transform * Transform3D(Basis.IDENTITY, Vector3(s2 * HIP_X, -0.05, 0.0))


func socket_point(kind: String) -> Vector3:
	return socket_xform(kind).origin


## Копия руки/ноги для упавшей детали: узлы в системе крепления. Возвращает [узел, конец].
func make_limb_visual(kind: String) -> Array:
	var root := Node3D.new()
	var i := LIMBS.find(kind)
	var nodes: Array = []
	var end := Vector3(0, -0.7, 0)
	var sock := socket_xform(kind)
	var inv := sock.affine_inverse()
	if i < 2:
		nodes = [_arms[i]["upper"], _arms[i]["fore"], _arms[i]["hand"]]
		end = inv * (_arms[i]["hand"] as Node3D).global_transform * Vector3(0, -HAND, 0)
	else:
		var li := i - 2
		nodes = [_legs[li]["thigh"], _legs[li]["shin"], _legs[li]["boot"], _legs[li]["housing"], _legs[li]["rod"]]
		end = inv * (_legs[li]["boot"] as Node3D).global_position
	for node in nodes:
		var d := (node as Node3D).duplicate() as Node3D
		root.add_child(d)
		d.transform = inv * (node as Node3D).global_transform
		d.visible = true
		# моток верёвки в руке не копируем
		for c in d.get_children():
			if c.name == "RopeCoil" or c.get_child_count() > 0 and c.get_child(0).name == "RopeCoil":
				c.queue_free()
	# рваный край: фланец и провода
	var cap := Node3D.new()
	root.add_child(cap)
	var cm := _plain(Color(0.3, 0.31, 0.34), 0.9, 0.35)
	var flange := MeshInstance3D.new()
	flange.mesh = _cyl(0.065, 0.06, 0.04, 12)
	flange.material_override = cm
	cap.add_child(flange)
	var wcols := [Color(0.85, 0.15, 0.1), Color(0.95, 0.8, 0.15), Color(0.15, 0.4, 0.9)]
	for k in 3:
		var wire := MeshInstance3D.new()
		wire.mesh = _cyl(0.007, 0.007, 0.09, 6)
		wire.material_override = _plain(wcols[k], 0.2, 0.5)
		wire.position = Vector3(cos(k * 2.1) * 0.02, 0.05, sin(k * 2.1) * 0.02)
		wire.rotation = Vector3(sin(k * 1.7) * 0.5, 0, cos(k * 2.3) * 0.5)
		cap.add_child(wire)
	return [root, end]


## Брызги, искры, болты — деталь отлетела
func limb_burst(kind: String) -> void:
	var st: Dictionary = _stumps[kind]
	(st["sparks"] as GPUParticles3D).amount = 40
	(st["sparks"] as GPUParticles3D).restart()
	var p := FX.particles(Color(0.28, 0.16, 0.05, 0.95), 26, 0.9, 0.022, 2.0, 4.5, Vector3(0, -9, 0), 50.0)
	p.top_level = true
	add_child(p)
	p.global_position = socket_point(kind)
	p.restart()
	var bolts := FX.particles(Color(0.72, 0.72, 0.75, 1.0), 8, 1.2, 0.02, 2.5, 5.0, Vector3(0, -12, 0), 80.0)
	bolts.top_level = true
	add_child(bolts)
	bolts.global_position = socket_point(kind)
	bolts.restart()
	var steam := FX.particles(Color(0.95, 0.97, 1.0, 0.4), 16, 1.4, 0.12, 0.4, 1.2, Vector3(0, 0.8, 0), 40.0)
	steam.top_level = true
	add_child(steam)
	steam.global_position = socket_point(kind)
	steam.restart()
	get_tree().create_timer(2.0).timeout.connect(func():
		for n in [p, bolts, steam]:
			if is_instance_valid(n):
				n.queue_free())
	emote(Mood.HURT, 2.0)


## Деталь прикрутили: щелчок, искры — и проверка: шевелю рукой / топаю ногой
func limb_clunk(kind: String) -> void:
	var st: Dictionary = _stumps[kind]
	(st["sparks"] as GPUParticles3D).amount = 18
	(st["sparks"] as GPUParticles3D).restart()
	torso.scale = Vector3(1.06, 0.95, 1.06)
	emote(Mood.HAPPY, 2.2)
	_check_t = 1.5
	_check_kind = kind


## Меня тянут за руку/ногу: она отходит от гнезда на gap (мир), между ними — провода
func set_strain(kind: String, gap: Vector3, k: float) -> void:
	_strain = {"kind": kind, "gap": gap, "k": k, "t": 0.25}


func _strain_gap(kind: String) -> Vector3:
	if _strain.is_empty() or String(_strain["kind"]) != kind:
		return Vector3.ZERO
	return _strain["gap"]


## Вылетел болт из крепления (когда отрывают): летит, звенит, скачет по снегу
func pop_bolt(kind: String, toward: Vector3) -> void:
	var sock := socket_xform(kind).orthonormalized()
	var a := randf() * TAU
	var radial := sock.basis * Vector3(cos(a), 0.0, sin(a))
	var at := sock.origin + radial * 0.075 - sock.basis.y * 0.02
	var b := _make_bolt()
	b.top_level = true
	add_child(b)
	b.global_position = at
	var v := radial * 2.2 + toward * 1.6 + Vector3.UP * randf_range(2.5, 4.0)
	_flying.append({"node": b, "vel": v, "spin": Vector3(randf_range(-30, 30), randf_range(-30, 30), randf_range(-30, 30)), "life": 6.0, "gy": _vis.global_position.y})
	_fx_burst(at, Color(1.0, 0.8, 0.4), 18, 0.35, 1.5, 3.5)
	_ping(at, Color(1.0, 0.95, 0.8), 0.06)
	jolt(0.7)
	emote(Mood.HURT, 0.5)


func _make_bolt() -> Node3D:
	var n := Node3D.new()
	var h := MeshInstance3D.new()
	h.mesh = _cyl(0.017, 0.017, 0.012, 6)
	h.material_override = _bolt_mat
	n.add_child(h)
	var sh := MeshInstance3D.new()
	sh.mesh = _cyl(0.0065, 0.0065, 0.035, 6)
	sh.material_override = _bolt_mat
	sh.position = Vector3(0, -0.022, 0)
	n.add_child(sh)
	return n


## Сел: плюх — снежная пыль из-под себя
func sit_plop() -> void:
	_dust(_vis.global_position + Vector3.UP * 0.05, 18)
	_bob_v -= 1.2
	_sit_pose = 0
	_sit_pose_t = randf_range(3.0, 5.0)
	_sit_hand = [Vector3.ZERO, Vector3.ZERO]


## Вздрогнул всем корпусом (болт вылетел, разряд, щелчок)
func jolt(a: float) -> void:
	_bob_v -= a * 1.6
	_lean_v += a * randf_range(-3.0, 3.0)
	torso.scale = Vector3(1.0 + a * 0.05, 1.0 - a * 0.05, 1.0 + a * 0.05)


## Рванул и оторвал — отлетаю назад, добыча над головой
func recoil() -> void:
	_recoil_t = 0.8
	emote(Mood.HAPPY, 2.0)


## Деталь на плече (мир), если сейчас несу её так
func limb_carry_xform() -> Variant:
	return _limb_carry if _limb_carry_ok else null


func _fx_burst(at: Vector3, c: Color, n: int, life: float, smin: float, smax: float, grav := Vector3(0, -9, 0)) -> void:
	var p := FX.particles(c, n, life, 0.012, smin, smax, grav, 180.0, true, true)
	p.top_level = true
	add_child(p)
	p.global_position = at
	p.restart()
	get_tree().create_timer(life + 0.6).timeout.connect(p.queue_free)


## Короткая вспышка-«дзынь»
func _ping(at: Vector3, c: Color, r: float) -> void:
	var m := MeshInstance3D.new()
	m.mesh = _sphere(r, -1.0, 10)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = c
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.top_level = true
	add_child(m)
	m.global_position = at
	m.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(m, "scale", Vector3.ONE * 1.6, 0.14)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.16)
	tw.tween_callback(m.queue_free)


## Тонкий цилиндр (высота 1) от a до b
static func _seg(n: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := maxf(d.length(), 0.001)
	var y := d / len
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	n.global_transform = Transform3D(Basis(x, y * len, x.cross(y)), (a + b) * 0.5)


## Анимация поломки: искры по суставам, на ударе о снег — отлетают наплечник,
## антенна и брелок-кабанчик (он укатывается), котёл свистит паром. Возрождение — всё на место.
func _death_fx(delta: float, st: Dictionary) -> void:
	var dtt := float(st.get("death_t", -1.0))
	var dead: bool = st["dead"]
	if not dead or dtt < 0.0:
		if _broken:
			_restore_debris()
		_death_prev = -1.0
		_death_steam.emitting = false
		_death_smoke.emitting = false
		return
	var prev := _death_prev
	_death_prev = dtt
	var in_w: bool = st["swim"] or st["dive"] or st["frozen"]
	# отказ систем: искры то из одного сустава, то из другого
	if dtt < 1.25 and floorf(dtt * 9.0) != floorf(maxf(prev, 0.0) * 9.0):
		var joints: Array[Vector3] = [neck.global_position, knees[0], knees[1]]
		for i in 2:
			if has_limb(LIMBS[i]):
				joints.append((_arms[i]["fore"] as Node3D).global_position)
		var at: Vector3 = joints[randi() % joints.size()]
		_fx_burst(at, Color(1.0, 0.75, 0.3), 16, 0.35, 1.5, 3.8)
		jolt(0.35)
	if prev < 0.7 and dtt >= 0.7:
		var chest := torso.global_transform * Vector3(0, 0.3, -0.2)
		_fx_burst(chest, Color(1.0, 0.85, 0.5), 40, 0.5, 2.0, 4.5)
		_ping(chest, Color(1.0, 0.8, 0.5), 0.15)
	# стоя на коленях: болты вылетают из плеч, котёл начинает свистеть
	for bt in [1.55, 2.05]:
		if prev < bt and dtt >= bt and not in_w:
			var bk := "arm_l" if bt < 2.0 else "arm_r"
			if has_limb(bk):
				pop_bolt(bk, -_vis.global_basis.z)
	if prev < 1.4 and dtt >= 1.4 and not in_w:
		_death_steam.emitting = true
	if prev < D_BLIP and dtt >= D_BLIP and not in_w:
		_fx_burst(head.global_position, Color(1.0, 0.8, 0.4), 8, 0.3, 0.6, 1.6)
	if prev < D_HIT and dtt >= D_HIT and not in_w and not _broken:
		_broken = true
		var gy: float = (st["self"] as Node3D).global_position.y
		var right := _vis.global_basis.x
		var fwd := -_vis.global_basis.z
		var hp0 := head.global_position
		_dust(Vector3(hp0.x, gy + 0.05, hp0.z), 36)
		_dust(torso.global_position * Vector3(1, 0, 1) + Vector3(0, gy + 0.05, 0), 24)
		_fx_burst(torso.global_position, Color(1.0, 0.8, 0.4), 30, 0.4, 2.0, 4.0)
		var oil := FX.particles(Color(0.18, 0.1, 0.03, 0.95), 24, 0.9, 0.02, 1.0, 3.0, Vector3(0, -9, 0), 60.0)
		oil.top_level = true
		add_child(oil)
		oil.global_position = torso.global_position
		oil.restart()
		get_tree().create_timer(1.6).timeout.connect(oil.queue_free)
		_detach(torso.get_node("Pauldron1") as Node3D, right * 2.6 + Vector3.UP * 3.2 + fwd * 0.6, Vector3(7, 3, 9), false, gy + 0.08)
		_detach(_antenna, fwd * 1.5 - right * 1.2 + Vector3.UP * 4.0, Vector3(14, 4, 9), false, gy + 0.02)
		var rd := (right * randf_range(-1.0, 1.0) + fwd * 0.4).normalized()
		_detach(_charm, rd * 2.2 + Vector3.UP * 2.0, Vector3.ZERO, true, gy + 0.03)
		_death_steam.emitting = true
		jolt(1.2)
	if dtt > 4.8:
		_death_steam.emitting = false
	_death_smoke.emitting = dtt > D_HIT and not in_w
	if _broken:
		_update_debris(delta)


func _dust(at: Vector3, n: int) -> void:
	var p := FX.particles(Color(0.93, 0.95, 1.0, 0.7), n, 1.0, 0.07, 0.6, 2.2, Vector3(0, -2.5, 0), 70.0)
	p.top_level = true
	add_child(p)
	p.global_position = at
	p.restart()
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _detach(n: Node3D, vel: Vector3, spin: Vector3, roll: bool, ground: float) -> void:
	if n == null:
		return
	_debris.append({"node": n, "xf": n.transform, "vel": vel, "spin": spin, "roll": roll, "g": ground})
	n.top_level = true


func _update_debris(delta: float) -> void:
	for d in _debris:
		var n: Node3D = d["node"]
		var v: Vector3 = d["vel"]
		v.y -= 12.0 * delta
		var p := n.global_position + v * delta
		var g: float = d["g"]
		var spin: Vector3 = d["spin"]
		if p.y < g:
			p.y = g
			if v.y < -1.2:
				v = Vector3(v.x * 0.7, -v.y * 0.32, v.z * 0.7)
				spin *= 0.7
			else:
				v.y = 0.0
				if bool(d["roll"]):
					v.x *= 1.0 - delta * 0.5          # кабанчик катится далеко
					v.z *= 1.0 - delta * 0.5
				else:
					v.x *= 1.0 - delta * 6.0
					v.z *= 1.0 - delta * 6.0
					spin *= 1.0 - delta * 6.0
		if bool(d["roll"]):
			var hv := Vector3(v.x, 0.0, v.z)
			if hv.length() > 0.02:
				spin = Vector3.UP.cross(hv.normalized()) * (hv.length() / 0.03)
			else:
				spin = Vector3.ZERO
		d["vel"] = v
		d["spin"] = spin
		n.global_position = p
		if spin.length() > 0.01:
			n.global_basis = (Basis.from_euler(spin * delta) * n.global_basis).orthonormalized()


func _restore_debris() -> void:
	for d in _debris:
		var n: Node3D = d["node"]
		if is_instance_valid(n):
			n.top_level = false
			n.transform = d["xf"]
	_debris.clear()
	_broken = false


## После поз: ключ в руке, провода растяжки, летящие болты, пот, звёздочки
func _post_limb_fx(delta: float, tumble: bool, flop: float, rep: Dictionary) -> void:
	var show_wr := not rep.is_empty() and float(rep["k"]) > 0.08 and (limb_mask & 3) != 0
	_wrench_hand.visible = show_wr
	_wrench_holster.visible = not show_wr
	if show_wr:
		var hi := 1 if (limb_mask & 2) != 0 else 0
		var hand := (_arms[hi]["hand"] as Node3D).global_transform.orthonormalized()
		var palm := hand * Vector3(0, -HAND, 0)
		if not _wr.is_empty():
			# головка ключа на болте, рукоять — в кулак
			var head_p: Vector3 = _wr["head"]
			var ax: Vector3 = _wr["axis"]
			var zz := (head_p - palm).normalized()
			var yy := (ax - zz * ax.dot(zz))
			yy = yy.normalized() if yy.length() > 0.01 else Vector3.UP
			_wrench_hand.global_transform = Transform3D(Basis(yy.cross(zz), yy, zz), head_p - zz * 0.09)
		else:
			_wrench_hand.global_transform = hand * Transform3D(Basis.IDENTITY, Vector3(0, -HAND - 0.02, 0))
	_wr = {}
	# растяжка
	if not _strain.is_empty():
		_strain["t"] = float(_strain["t"]) - delta
		if float(_strain["t"]) <= 0.0:
			_strain = {}
	var show := not _strain.is_empty() and (_strain["gap"] as Vector3).length() > 0.008 and has_limb(String(_strain["kind"]))
	# шаг 124: провода натягиваются, раскаляются (светятся всё ярче) и в самом конце лопаются по одному — с искрами
	var sk_now := float(_strain.get("k", 0.0)) if show else 0.0
	for k in 3:
		var snapped := sk_now > 0.88 + 0.035 * k
		if show and snapped and not bool(_wire_snapped[k]):
			var s0 := socket_xform(String(_strain["kind"])).orthonormalized()
			_fx_burst(s0.origin + (_strain["gap"] as Vector3) * 0.5, Color(1.0, 0.85, 0.4), 14, 0.35, 1.5, 4.0)
			_ping(s0.origin + (_strain["gap"] as Vector3) * 0.5, Color(0.7, 0.9, 1.0), 0.09)
			jolt(0.25)
		_wire_snapped[k] = snapped and show
		_strain_wires[k].visible = show and not snapped
		var wm := _strain_wires[k].material_override as StandardMaterial3D
		if show and wm:
			var hot := smoothstep(0.35, 0.9, sk_now)
			wm.emission_enabled = hot > 0.01
			wm.emission = wm.albedo_color.lerp(Color(1.0, 0.75, 0.4), hot * 0.6)
			wm.emission_energy_multiplier = hot * (1.5 + 2.5 * absf(sin(_t * 31.0 + k * 2.0)))
	if show:
		var sock := socket_xform(String(_strain["kind"])).orthonormalized()
		var gap: Vector3 = _strain["gap"]
		for k in 3:
			var a := float(k) * 2.1 + 0.3
			var off := sock.basis * Vector3(cos(a) * 0.035, -0.02, sin(a) * 0.035)
			_seg(_strain_wires[k], sock.origin + off, sock.origin + gap + off * 0.8 - sock.basis.y * 0.03)
		if sk_now > 0.3 and randf() < delta * (4.0 + 16.0 * sk_now):
			_fx_burst(sock.origin + gap * randf_range(0.2, 0.9), Color(0.6, 0.85, 1.0), 6 + int(8.0 * sk_now), 0.3, 0.8, 2.6)
		if sk_now > 0.6 and randf() < delta * 5.0:
			_ping(sock.origin + gap * 0.5, Color(0.6, 0.85, 1.0), 0.05)          # дуга между гнездом и деталью
	# вылетевшие болты
	for k in range(_flying.size() - 1, -1, -1):
		var f: Dictionary = _flying[k]
		var n: Node3D = f["node"]
		f["life"] = float(f["life"]) - delta
		if float(f["life"]) <= 0.0 or not is_instance_valid(n):
			if is_instance_valid(n):
				n.queue_free()
			_flying.remove_at(k)
			continue
		var v: Vector3 = f["vel"]
		v.y -= 12.0 * delta
		var p := n.global_position + v * delta
		var gy: float = float(f["gy"]) + 0.012
		var spin: Vector3 = f["spin"]
		if p.y < gy:
			p.y = gy
			if v.y < -0.8:
				v = Vector3(v.x * 0.6, -v.y * 0.35, v.z * 0.6)
				spin *= 0.6
			else:
				v = Vector3.ZERO
				spin = Vector3.ZERO
		f["vel"] = v
		f["spin"] = spin
		n.global_position = p
		if spin.length() > 0.01:
			n.global_basis = Basis.from_euler(spin * delta) * n.global_basis
		if float(f["life"]) < 0.5:
			n.scale = Vector3.ONE * maxf(float(f["life"]) / 0.5, 0.01)
	# пот и звёзды
	_sweat.emitting = tumble
	_stars.visible = flop >= 0.0 and flop < 0.8
	if _stars.visible:
		_stars.global_position = head.global_position + Vector3.UP * 0.32
		_stars.rotation.y += delta * 5.0


func _update_limb_details(delta: float, st: Dictionary) -> void:
	# культи: искрят время от времени, провода болтаются
	_stump_t -= delta
	var spark_now := _stump_t <= 0.0
	if spark_now:
		_stump_t = randf_range(0.6, 2.0)
	for kind in _stumps:
		var sd: Dictionary = _stumps[kind]
		var n := sd["node"] as Node3D
		if not n.visible:
			continue
		var wires: Array = sd["wires"]
		for k in wires.size():
			(wires[k] as Node3D).rotation = Vector3(sin(_t * 3.1 + k * 2.0) * 0.35 + _acc.z * 0.01, 0.0, cos(_t * 2.7 + k) * 0.35 - _acc.x * 0.01)
		if spark_now and randf() < 0.5:
			(sd["sparks"] as GPUParticles3D).amount = 10
			(sd["sparks"] as GPUParticles3D).restart()
	# брелок: пружинка, реагирует на ускорение
	if _charm:
		var force := Vector2(-_acc.x, -_acc.z) * 0.02 - _charm_a * 60.0 - _charm_v * 3.0
		_charm_v += force * delta
		_charm_a += _charm_v * delta
		_charm_a = _charm_a.limit_length(0.9)
		if not _broken:
			_charm.rotation = Vector3(_charm_a.y, 0.0, -_charm_a.x)
	# огоньки на коленях: зелёные; корпус плох — красные мигают
	var hp: float = st["hp"]
	# потрёпан: антенна погнута, болтаются оборванные провода, из котла свистит пар
	if not _broken:
		var bend := clampf((0.65 - hp) * 1.8, 0.0, 0.85)
		_antenna.basis = _antenna_rb * Basis(Vector3.FORWARD, bend + sin(_t * 3.0) * 0.05 * bend) * Basis(Vector3.RIGHT, bend * 0.5)
	var dl_on := hp < 0.55 and not bool(st["dead"])
	for k in _dangle.size():
		var dn := _dangle[k]
		var limb_on := has_limb(LIMBS[k])
		dn.visible = dl_on and limb_on
		if dn.visible:
			dn.rotation = Vector3(sin(_t * 2.3 + k * 1.3) * 0.5 + _acc.z * 0.02, 0.0, cos(_t * 1.9 + k) * 0.4 - _acc.x * 0.02)
	_leak.emitting = hp < 0.4 and not bool(st["dead"]) and fmod(_t * 0.7, 1.0) < 0.55
	for m in _knee_leds:
		if hp < 0.3:
			m.albedo_color = Color(1.0, 0.25, 0.2)
			m.emission = m.albedo_color
			m.emission_energy_multiplier = 4.0 if fmod(_t, 0.5) < 0.25 else 0.3
		else:
			m.albedo_color = Color(0.35, 1.0, 0.55)
			m.emission = m.albedo_color
			m.emission_energy_multiplier = 1.5 + sin(_t * 1.5) * 1.0


## Шаг 77: вложить предмет в кулак (ледоруб): рукоять — вдоль Z кисти через кулак, голова — над большим пальцем
func attach_to_hand(i: int, node: Node3D) -> void:
	var hand := _arms[i]["hand"] as Node3D
	var s: float = _arms[i]["s"]
	hand.add_child(node)
	node.position = Vector3(-s * GRIP_IN, -HAND - 0.015, 0.0)
	node.basis = Basis(Vector3.RIGHT, PI)


## Шаг 91: где кулак (середина хвата) — туда кладу верёвку/рукоять
func fist_pos(i: int) -> Vector3:
	var s: float = _arms[i]["s"]
	return (_arms[i]["hand"] as Node3D).global_transform * Vector3(-s * GRIP_IN, -HAND - 0.015, 0.0)


## Кисть так, чтобы предмет в кулаке (рукоять / верёвка) шёл вдоль axis; пальцы обхватывают со стороны hint
## Шаг 133: точка на верёвке (из a по оси ax) на высоте y; верёвка почти горизонтальна — запасная точка
static func _on_rope(a: Vector3, ax: Vector3, y: float, fallback: Vector3) -> Vector3:
	if ax.y < 0.2:
		return fallback
	var p := a + ax * ((y - a.y) / ax.y)
	return p if p.distance_to(fallback) < 0.6 else fallback


static func _grip_basis(axis: Vector3, hint: Vector3) -> Basis:
	var ax := axis.normalized()
	var f := hint - ax * hint.dot(ax)
	if f.length() < 0.01:
		f = Vector3.UP.cross(ax) if absf(ax.y) < 0.9 else Vector3.RIGHT
	f = f.normalized()
	return _hand_basis(f, ax.cross(f))


## Запястье, при котором кулак окажется ровно в точке fist
static func _wrist_for(fist: Vector3, b: Basis, s: float) -> Vector3:
	return fist - b * Vector3(-s * GRIP_IN, -HAND - 0.015, 0.0)


func hand_xform(i: int) -> Transform3D:
	return (_arms[i]["hand"] as Node3D).global_transform


## Шаг 115: кисть (узел) — к ней крепится инструмент в руке; и где в ней кулак (рукоять вдоль z)
func hand_node(i: int) -> Node3D:
	return _arms[i]["hand"] as Node3D


func grip_local(i: int) -> Transform3D:
	var s: float = _arms[i]["s"]
	return Transform3D(Basis.IDENTITY, Vector3(-s * GRIP_IN, -HAND - 0.015, 0.0))



## Случайная вмятина/пробоина на корпусе (в мире) — оттуда искрит
func _random_dent_point() -> Vector3:
	var cands: Array = []
	for pc in _pieces:
		var n: int = pc["n"]
		if n <= 0:
			continue
		var mi := pc["mesh"] as MeshInstance3D
		if mi == null or not mi.is_visible_in_tree():
			continue
		var info: PackedVector4Array = pc["info"]
		var pos: PackedVector4Array = pc["pos"]
		for k in n:
			var kind := int(info[k].x + 0.5)
			if kind == Mark.DENT or kind == Mark.PIERCE or kind == Mark.CRUMPLE:
				cands.append(mi.global_transform * Vector3(pos[k].x, pos[k].y, pos[k].z))
	if cands.is_empty():
		return Vector3.INF
	return cands[randi() % cands.size()]


## Видна ли деталь (без учёта мигания всего дрона после возрождения)
func _shown_in_suit(n: Node) -> bool:
	var cur := n
	while cur != null and cur != self and cur != _vis:
		if cur is Node3D and not (cur as Node3D).visible:
			return false
		cur = cur.get_parent()
	return true
