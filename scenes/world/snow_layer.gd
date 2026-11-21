extends Node3D
## Слой снега, который оставляет лавина (шаг 57, переделан в шаге 62). Сетка глубин по всей Лавинной
## долине (клетка 1.5 м): лавина «насыпает» снег позади фронта — толще посередине потока, к краям сходит
## на нет. Из сетки строятся куски поверхности (по 30×30 м), перестраиваются только изменённые
## (не больше двух за кадр — без подвисаний).
##   * Рельеф: бугры, комья и поперечные валы (по направлению потока), рваные края; глыбы, которые
##     принесла лавина, остаются лежать наполовину в снегу (add_block).
##   * Свежий снег рыхлый: сразу после лавины он на ~0.3 м пышнее и белее, за 3 с оседает и
##     уплотняется (в шейдере — по времени насыпи, без перестройки сетки).
##   * Поверхность: искры на свету, голубоватые ложбины и склоны бугров, мягкий переход к насту.
##   * Опора под ногами — отдельная, гладкая (сглаженная глубина минус SINK): дрон идёт ровно,
##     проваливаясь по колено. На опоре мета "deep_snow" — player.gd идёт медленнее, прыжок ниже.
##   * Где ходят дроны — траншея: снег продавлен до опоры, по краям бортики, дно плотное и
##     голубоватое; из-под ног летит снег.
##   * Лежит до конца забега: когда все прошли долину или вернулись к её началу — сходит (clear()).

const W := preload("res://scenes/world/avalanche_layout.gd")
const FLOW := preload("res://scenes/world/avalanche_flow.gd")

const CELL := 1.5
const X0 := -210.0
const NX := 281                    ## вершин по x (до +210; долина с шага 64 вдвое шире)
const Z_TOP := W.S_Z + 6.0         ## верхний (южный) край сетки
const NZ := 586                    ## вершин по z (≈ 878 м; шаг 67 — долина длиннее)
const CH := 20                     ## клеток в куске
const MIN_D := 0.1                 ## тоньше — не рисуем
const SINK := 0.85                 ## шаг 137: проваливаешься почти по пояс (было 0.5 — по колено)
const SETTLE := 3.2                ## за сколько секунд рыхлый снег оседает
const MAX_BLOCKS := 70
const REBUILDS_PER_FRAME := 2
const EDGE_STEP := 0.2             ## края слоя: толщина меняется не больше чем на столько за клетку (1.5 м) —
                                   ## снег плавно сходит на нет (~7°), без обрыва

var depth := PackedFloat32Array()  ## видимая глубина (с траншеями)
var base := PackedFloat32Array()   ## насыпано лавиной (для опоры)
var tdep := PackedFloat32Array()   ## когда насыпано (часы слоя) — для оседания
var any_snow := false
var no_zones: Array = []           ## [центр Vector2, r0, r1] — тут снег не насыпается (укрытия)
var _clock := 0.0
var _ground := {}                  ## кусок → высоты рельефа в вершинах (с каймой в 1 вершину)
var _chunks := {}                  ## кусок → [MeshInstance3D, StaticBody3D, CollisionShape3D]
var _dirty := {}
var _press_t := 0.0
var _ter: Node
var _mat: ShaderMaterial
var _lumps := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _clods := FastNoiseLite.new()
var _kc := PackedFloat32Array()    ## кэш по клеткам: «можно сыпать» (−1 — ещё не считали)
var _lc := PackedFloat32Array()    ## кэш: бугристость
var _hc := PackedFloat32Array()    ## кэш: холмистость (фаза валов)
var _built := {}                   ## шаг 137: кусок → [когда перестроен вид, когда опора]
var _fluff := {}                   ## кусок → рыхлость в вершинах (шум, считается один раз)
var _blocks: Array = []            ## глыбы, оставшиеся лежать
var _kick := {}                    ## дрон → CPUParticles3D (снег из-под ног)
var _fe_lo := Vector2i(1 << 30, 1 << 30)   ## где насыпали за последние 0.15 с
var _fe_hi := Vector2i(-1, -1)
var _fe_t := 0.0
var _fe_queue: Array = []                  ## [когда, lo, hi] — края сглаживаю через FE_DELAY: к тому времени
                                           ## поток уже насыпал и соседние клетки впереди (иначе срезал бы весь слой)
const FE_DELAY := 1.0

const SHADER := """
shader_type spatial;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float now = 0.0;
uniform float settle_time = 3.2;
varying vec3 wp;
varying float dep;
varying float pressed;
varying float loose;
void vertex() {
	// рыхлый свежий снег: пышнее, потом оседает
	float st = clamp((now - UV2.x) / settle_time, 0.0, 1.0);
	st = st * st * (3.0 - 2.0 * st);
	loose = (1.0 - st) * step(0.01, UV2.y);
	VERTEX.y += UV2.y * (1.0 - st);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dep = COLOR.r;
	pressed = COLOR.g;
}
void fragment() {
	vec2 uv = wp.xz * 0.33;
	vec3 tex = texture(snow_tex, uv).rgb;
	float n = texture(noise, wp.xz * 0.025).r;
	float n2 = texture(noise, wp.xz * 0.21 + 0.37).r;
	// свежий снег: светлее старого наста, пятна чуть разные
	vec3 c = tex * mix(vec3(0.82, 0.87, 0.97), vec3(1.0, 1.01, 1.05), clamp(n * 0.8 + n2 * 0.45, 0.0, 1.0));
	// склоны бугров и ложбины — голубоватые
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	c = mix(c, c * vec3(0.56, 0.68, 0.92), clamp(slope * 3.6, 0.0, 0.8));   // шаг 137: рельеф заметнее
	// ложбинки между буграми — в тени
	float hol = texture(noise, wp.xz * 0.16 + 0.71).r;
	c *= mix(0.86, 1.03, smoothstep(0.3, 0.7, hol));
	// траншея: плотный, голубоватый, глаже
	c = mix(c, tex * vec3(0.5, 0.62, 0.88), pressed * 0.95);
	// рыхлый — белее
	c = mix(c, vec3(1.0, 1.0, 1.02), loose * 0.3);
	// у тонкого края слой сливается с настом
	c = mix(tex * vec3(0.72, 0.75, 0.82), c, smoothstep(0.0, 0.35, dep));
	ALBEDO = c;
	NORMAL_MAP = texture(snow_nrm, uv * 1.3).rgb;
	NORMAL_MAP_DEPTH = mix(2.2, 0.6, pressed);
	ROUGHNESS = mix(0.85, 0.55, pressed);
	RIM = 0.25;
	RIM_TINT = 0.5;
	// искры на свежем снегу: вспыхивают, когда смотришь под нужным углом
	float g = texture(noise, wp.xz * 3.1 + VIEW.xz * 0.6).r;
	float g2 = texture(noise, wp.xz * 5.3 - VIEW.xy * 0.9 + 0.5).r;
	float glint = smoothstep(0.76, 0.8, g) * smoothstep(0.6, 0.66, g2);
	EMISSION = vec3(0.9, 0.95, 1.0) * glint * 1.6 * (1.0 - pressed) * smoothstep(0.1, 0.4, dep);
}
"""

static var _shader: Shader


static func layer_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	return _shader


func _ready() -> void:
	add_to_group("snow_layer")
	_ter = get_tree().get_first_node_in_group("terrain")
	depth.resize(NX * NZ)
	depth.fill(0.0)
	base.resize(NX * NZ)
	base.fill(0.0)
	tdep.resize(NX * NZ)
	tdep.fill(-100.0)
	_kc.resize(NX * NZ)
	_kc.fill(-1.0)
	_lc.resize(NX * NZ)
	_hc.resize(NX * NZ)
	_lumps.seed = 57
	_lumps.frequency = 0.22
	_hills.seed = 91
	_hills.frequency = 0.035
	_clods.seed = 133
	_clods.frequency = 0.6
	_mat = ShaderMaterial.new()
	_mat.shader = layer_shader()
	_mat.set_shader_parameter("settle_time", SETTLE)
	var tm = _ter.get("terrain_material") if _ter else null
	if FLOW.tex_cached(FLOW.DEBRIS_TEX):
		# шаг 137: фото-текстура лавинного снега (ambientCG Snow010A + рельеф комьев Snow008C)
		_mat.set_shader_parameter("snow_tex", FLOW.tex_cached(FLOW.DEBRIS_TEX))
		_mat.set_shader_parameter("snow_nrm", FLOW.tex_cached(FLOW.DEBRIS_NRM))
	elif tm is ShaderMaterial:
		_mat.set_shader_parameter("snow_tex", (tm as ShaderMaterial).get_shader_parameter("snow_tex"))
		_mat.set_shader_parameter("snow_nrm", (tm as ShaderMaterial).get_shader_parameter("snow_nrm"))
	_mat.set_shader_parameter("noise", FLOW._noise_tex())


## Прогрев: поверхность слоя и снег из-под ног — один раз показать камере
func prewarm_node() -> Node3D:
	var root := Node3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.02)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _mat
	root.add_child(mi)
	var k := _make_kick()
	root.add_child(k)
	k.set_deferred("emitting", true)
	# всплеск рассыпавшейся глыбы
	var fx := FX.particles(Color(0.93, 0.96, 1.0), 8, 0.5, 0.01, 0.1, 0.2, Vector3(0, -8, 0), 70.0, true)
	root.add_child(fx)
	fx.set_deferred("emitting", true)
	return root


# ---------------------------------------------------------------------------
#  Сетка
# ---------------------------------------------------------------------------

func _ix(x: float) -> float:
	return (x - X0) / CELL


func _iz(z: float) -> float:
	return (Z_TOP - z) / CELL


func _vx(ix: int) -> float:
	return X0 + ix * CELL


func _vz(iz: int) -> float:
	return Z_TOP - iz * CELL


## Глубина снега в точке (плавно)
func depth_at(x: float, z: float) -> float:
	if not any_snow:
		return 0.0
	var fx := _ix(x)
	var fz := _iz(z)
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	if ix < 0 or iz < 0 or ix >= NX - 1 or iz >= NZ - 1:
		return 0.0
	var tx := fx - ix
	var tz := fz - iz
	var a := depth[iz * NX + ix]
	var b := depth[iz * NX + ix + 1]
	var c := depth[(iz + 1) * NX + ix]
	var d := depth[(iz + 1) * NX + ix + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


## Высота поверхности (рельеф + снег)
func surface(x: float, z: float) -> float:
	var g: float = _ter.height_at(x, z) if _ter else 0.0
	var d := depth_at(x, z)
	return g + (d - 0.1 if d > MIN_D else 0.0)


## Насыпать снег: в точке будет не меньше target (с буграми, комьями и поперечными валами).
## dir — куда шёл поток (валы — поперёк него).
func pile(x: float, z: float, target: float, dir := Vector3.ZERO) -> void:
	var ix := roundi(_ix(x))
	var iz := roundi(_iz(z))
	if ix < 0 or iz < 0 or ix >= NX or iz >= NZ or target <= 0.02:
		return
	var vx := _vx(ix)
	var vz := _vz(iz)
	var k := iz * NX + ix
	# бугры, комья и «нельзя сыпать» в клетке — считаются один раз и запоминаются (шум дорогой)
	if _kc[k] < 0.0:
		var keep0 := 1.0
		for zn in no_zones:
			var dd: float = Vector2(vx, vz).distance_to(zn[0])
			keep0 = minf(keep0, smoothstep(float(zn[1]), float(zn[2]), dd))
		_kc[k] = keep0
		var h0 := _hills.get_noise_2d(vx, vz)
		_hc[k] = h0
		# комья — редкие резкие бугорки
		_lc[k] = maxf(_lumps.get_noise_2d(vx, vz), 0.0) * 0.6 + h0 * 0.35 + smoothstep(0.35, 0.7, _clods.get_noise_2d(vx, vz)) * 0.45
	var keep: float = _kc[k]
	if keep <= 0.01:
		return
	var hill: float = _hc[k]
	var lump: float = _lc[k]
	if dir != Vector3.ZERO:
		var w := sin((vx * dir.x + vz * dir.z) * 0.75 + hill * 5.0) * 0.5 + 0.5
		lump += w * w * w * 0.55          # шаг 137: валы поперёк потока выше
	var t := maxf(target * (1.0 + lump) * keep, 0.0)
	if t > base[k] + 0.02:
		base[k] = t
		depth[k] = maxf(depth[k], t)
		tdep[k] = _clock
		any_snow = true
		_pristine = false
		_mark(ix, iz, 2)
		_fe_lo = Vector2i(mini(_fe_lo.x, ix), mini(_fe_lo.y, iz))
		_fe_hi = Vector2i(maxi(_fe_hi.x, ix), maxi(_fe_hi.y, iz))


## Примять снег (там, где прошёл дрон): траншея до опоры, по краям — бортики
func press(x: float, z: float, r: float) -> void:
	var rb := r + 0.9
	var ix0 := int(floor(_ix(x - rb)))
	var ix1 := int(ceil(_ix(x + rb)))
	var iz0 := int(floor(_iz(z + rb)))
	var iz1 := int(ceil(_iz(z - rb)))
	for iz in range(maxi(iz0, 0), mini(iz1 + 1, NZ)):
		for ix in range(maxi(ix0, 0), mini(ix1 + 1, NX)):
			var dx := _vx(ix) - x
			var dz := _vz(iz) - z
			var dd := dx * dx + dz * dz
			if dd > rb * rb:
				continue
			var k := iz * NX + ix
			var d := depth[k]
			if d < 0.35:
				continue
			if dd > r * r:
				# бортик: снег из траншеи — по краям (не выше чем насыпано + 0.25; дно колеи не трогаю)
				if d < base[k] - 0.05:
					continue
				var nb := minf(d + 0.08, base[k] + 0.35)
				if nb > d + 0.01:
					depth[k] = nb
					_mark(ix, iz, 1)
				continue
			# траншея — до опоры под ногами, не глубже (шаг 137: пробиваешь сразу почти до опоры — проём в снегу)
			var nd := maxf(d - 0.7, base[k] - SINK + 0.05)
			nd = maxf(nd, 0.3)
			if nd < d - 0.02:
				depth[k] = nd
				_pristine = false
				_mark(ix, iz, 1)


func clear() -> void:
	for b in _blocks:
		if is_instance_valid(b):
			(b as Node).queue_free()
	_blocks.clear()
	if not any_snow or _pristine:
		return
	_pristine = true
	if not _base0.is_empty():
		# шаг 138: новый забег — снова старый снег с сугробами (а не голая земля)
		depth = _base0.duplicate()
		base = _base0.duplicate()
	else:
		depth.fill(0.0)
		base.fill(0.0)
		any_snow = false
	tdep.fill(-100.0)
	_fe_lo = Vector2i(1 << 30, 1 << 30)
	_fe_hi = Vector2i(-1, -1)
	_fe_queue.clear()
	for key in _chunks.keys():
		_dirty[key] = 2


## Шаг 138: по всей Лавинной долине с самого начала лежит старый снег (по колено) с сугробами (по пояс):
## везде следы, траншеи, снег из-под ног — как после лавины. Лёд, трещины, капсулы, разлом — открыты
var _base0 := PackedFloat32Array()
var _pristine := false             ## шаг 138: с последней очистки ничего не насыпано и не примято


func prefill() -> void:
	var drift := FastNoiseLite.new()
	drift.seed = 4242
	drift.frequency = 0.022
	drift.fractal_octaves = 2
	for iz in NZ:
		var vz := _vz(iz)
		var s := W.s_of(vz)
		if s < 4.0 or s > W.LENGTH - 8.0 or absf(s - W.RIFT_S) < W.RIFT_HW + 5.0:
			continue
		var cx := W.center_x(s)
		var hw := W.half_w(s)
		var se := smoothstep(4.0, 24.0, s) * (1.0 - smoothstep(W.LENGTH - 30.0, W.LENGTH - 8.0, s)) \
			* smoothstep(W.RIFT_HW + 5.0, W.RIFT_HW + 16.0, absf(s - W.RIFT_S))
		for ix in NX:
			var vx := _vx(ix)
			var ax := absf(vx - cx)
			var e := se * (1.0 - smoothstep(hw - 8.0, hw + 6.0, ax))
			if e <= 0.01:
				continue
			# лёд и трещины — открыты
			for ic in W.ICE:
				var rr := pow((vx - cx - float(ic[1])) / float(ic[2]), 2.0) + pow((s - float(ic[0])) / float(ic[3]), 2.0)
				e *= smoothstep(1.0, 1.7, rr)
			for cr in W.CRACKS:
				if absf(s - float(cr[0])) < 9.0 and vx > cx + float(cr[1]) - 4.0 and vx < cx + float(cr[2]) + 4.0:
					e *= smoothstep(4.0, 9.0, absf(s - float(cr[0])))
			if e <= 0.01:
				continue
			var keep := 1.0
			for zn in no_zones:
				keep = minf(keep, smoothstep(float(zn[1]), float(zn[2]), Vector2(vx, vz).distance_to(zn[0])))
			var h1 := _hills.get_noise_2d(vx, vz)
			var dn := drift.get_noise_2d(vx, vz)
			# по колено, кое-где — сугробы по пояс и выше (в них вязнешь)
			var d := (0.5 + 0.16 * h1 + 1.45 * smoothstep(0.18, 0.62, dn)) * e * keep
			if d < MIN_D:
				continue
			var k := iz * NX + ix
			base[k] = d
			depth[k] = d
	_feather(Vector2i(0, 0), Vector2i(NX - 1, NZ - 1))
	depth = base.duplicate()
	_base0 = base.duplicate()
	any_snow = true
	_pristine = true
	var nkx := int(ceil(float(NX - 1) / CH))
	var nkz := int(ceil(float(NZ - 1) / CH))
	for kz in nkz:
		for kx in nkx:
			_dirty[Vector2i(kx, kz)] = 2


## Глыба, принесённая лавиной, остаётся лежать наполовину в снегу. Она рыхлая: врежешься — рассыплется
## (не застрянешь, и боты-курьеры не упрутся)
func add_block(mesh: Mesh, basis: Basis, at: Vector3, size: float) -> void:
	if _blocks.size() >= MAX_BLOCKS:
		var old = _blocks.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var body := Node3D.new()
	body.set_meta("size", size)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = FLOW.chunk_material()
	mi.scale = Vector3.ONE * size
	mi.basis = basis.scaled(Vector3.ONE * size)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	add_child(body)
	# утонула в рыхлом снегу примерно наполовину
	var top := surface(at.x, at.z)
	body.global_position = Vector3(at.x, top - 0.18 * size, at.z)
	_blocks.append(body)


func _crumble(b: Node3D) -> void:
	_blocks.erase(b)
	var sz := float(b.get_meta("size", 1.0))
	var fx := FX.particles(Color(0.93, 0.96, 1.0), int(18 + 14 * sz), 0.9, 0.12 * sz, 1.5, 4.0, Vector3(0, -8, 0), 70.0, true)
	add_child(fx)
	fx.global_position = b.global_position + Vector3.UP * 0.3 * sz
	fx.emitting = true
	get_tree().create_timer(1.5).timeout.connect(fx.queue_free)
	b.queue_free()


## level: 1 — только вид, 2 — вид и опора (опора сглажена по соседям — их тоже)
func _mark(ix: int, iz: int, level: int) -> void:
	var cx := ix / CH
	var cz := iz / CH
	# соседний кусок — только если вершина у края (нормали — ±1 вершина, опора сглажена на ±2)
	var m := 2 if level == 2 else 1
	var lo_x := cx - 1 if ix % CH <= m else cx
	var lo_z := cz - 1 if iz % CH <= m else cz
	var hi_x := cx + 1 if ix % CH >= CH - m else cx
	var hi_z := cz + 1 if iz % CH >= CH - m else cz
	for kz in range(maxi(lo_z, 0), hi_z + 1):
		for kx in range(maxi(lo_x, 0), hi_x + 1):
			var key := Vector2i(kx, kz)
			_dirty[key] = maxi(int(_dirty.get(key, 0)), level)


# ---------------------------------------------------------------------------
#  Каждый кадр: перестроить изменённые куски (понемногу), примять тропы, снег из-под ног
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	_mat.set_shader_parameter("now", _clock)



func _physics_process(delta: float) -> void:
	_press_t -= delta
	var do_press := _press_t <= 0.0
	if do_press:
		_press_t = 0.12
	for d in get_tree().get_nodes_in_group("player"):
		var node := d as Node3D
		var moving := false
		var p: Vector3 = node.global_position
		if any_snow and not d.is_dead and not (d.get("snow") != null and d.snow.busy()):
			var hs := Vector2(d.velocity.x, d.velocity.z).length()
			if hs > 0.8 and depth_at(p.x, p.z) > 0.4:
				moving = true
				if do_press:
					press(p.x, p.z, 1.15)          # шаг 137: сетка 1.5 м — уже траншею не нарисовать
		var kp: CPUParticles3D = _kick.get(d)
		if moving and kp == null:
			kp = _make_kick()
			add_child(kp)
			_kick[d] = kp
		if kp != null:
			kp.emitting = moving
			if moving:
				kp.global_position = p + Vector3.UP * 0.25
				kp.direction = Vector3(-d.velocity.x, 2.5, -d.velocity.z).normalized()
	# дрон врезался в глыбу — она рассыпается
	if not _blocks.is_empty():
		for d in get_tree().get_nodes_in_group("player"):
			var dp: Vector3 = (d as Node3D).global_position
			for b in _blocks:
				if not is_instance_valid(b):
					continue
				var bp: Vector3 = (b as Node3D).global_position
				var rr: float = 0.42 * float((b as Node3D).get_meta("size", 1.0)) + 0.45
				if Vector2(bp.x - dp.x, bp.z - dp.z).length() < rr and absf(bp.y - dp.y) < 2.5:
					_crumble(b)
					break
	for d in _kick.keys():
		if not is_instance_valid(d):
			(_kick[d] as Node).queue_free()
			_kick.erase(d)
	_fe_t -= delta
	if _fe_t <= 0.0:
		_fe_t = 0.15
		if _fe_hi.x >= 0:
			_fe_queue.append([_clock, _fe_lo, _fe_hi])
			_fe_lo = Vector2i(1 << 30, 1 << 30)
			_fe_hi = Vector2i(-1, -1)
		var lo := Vector2i(1 << 30, 1 << 30)
		var hi := Vector2i(-1, -1)
		while not _fe_queue.is_empty() and float(_fe_queue[0][0]) < _clock - FE_DELAY:
			var e: Array = _fe_queue.pop_front()
			lo = Vector2i(mini(lo.x, (e[1] as Vector2i).x), mini(lo.y, (e[1] as Vector2i).y))
			hi = Vector2i(maxi(hi.x, (e[2] as Vector2i).x), maxi(hi.y, (e[2] as Vector2i).y))
		if hi.x >= 0:
			_feather(lo, hi)
	if _dirty.is_empty():
		return
	# перестраиваю по времени: не дольше ~2.5 мс за кадр (хотя бы один кусок)
	# шаг 137: кусок перестраиваю не чаще раза в 0.12 с, опору — раз в 0.45 с (пока по нему идёт лавина,
	# он меняется каждый кадр — перестраивать каждый кадр незачем); бюджет — 1.5 мс за кадр
	var t0 := Time.get_ticks_usec()
	for key in _dirty.keys():
		var lb: Array = _built.get(key, [-9.0, -9.0])
		if _clock - float(lb[0]) < 0.12:
			continue
		var lvl: int = _dirty[key]
		var solid := lvl >= 2 and _clock - float(lb[1]) >= 0.45
		if lvl >= 2 and not solid:
			_dirty[key] = 2
		else:
			_dirty.erase(key)
		_rebuild(key, solid)
		lb[0] = _clock
		if solid:
			lb[1] = _clock
		_built[key] = lb
		if Time.get_ticks_usec() - t0 > 1500:
			break


func _make_kick() -> CPUParticles3D:
	var k := CPUParticles3D.new()
	k.amount = 28
	k.lifetime = 0.7
	k.emitting = false
	k.local_coords = false
	k.direction = Vector3.UP
	k.spread = 35.0
	k.initial_velocity_min = 1.5
	k.initial_velocity_max = 3.5
	k.gravity = Vector3(0, -7.0, 0)
	k.scale_amount_min = 0.5
	k.scale_amount_max = 1.2
	k.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	k.emission_sphere_radius = 0.3
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.1))
	k.scale_amount_curve = c
	var m := SphereMesh.new()
	m.radius = 0.06
	m.height = 0.1
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.97, 1.0)
	mat.roughness = 0.9
	m.material = mat
	k.mesh = m
	return k


## Края слоя: толщина снега у соседних вершин отличается не больше чем на EDGE_STEP (×1.41 по диагонали) —
## слой плавно сходит на нет к краям и к началу насыпи (два прохода «фаски» по изменённому месту с запасом)
func _feather(lo: Vector2i, hi: Vector2i) -> void:
	var x0 := maxi(lo.x - 1, 0)
	var x1 := mini(hi.x + 1, NX - 1)
	var z0 := maxi(lo.y - 1, 0)
	var z1 := mini(hi.y + 1, NZ - 1)
	var st := EDGE_STEP
	var sd := EDGE_STEP * 1.414
	var b := base
	var changed := PackedInt32Array()
	# вперёд: слева и сверху
	for iz in range(z0, z1 + 1):
		var row := iz * NX
		for ix in range(x0, x1 + 1):
			var k := row + ix
			var v := b[k]
			if v <= 0.0:
				continue
			var lim := v
			lim = minf(lim, (b[k - 1] if ix > 0 else 0.0) + st)
			if iz > 0:
				lim = minf(lim, b[k - NX] + st)
				lim = minf(lim, (b[k - NX - 1] if ix > 0 else 0.0) + sd)
				lim = minf(lim, (b[k - NX + 1] if ix < NX - 1 else 0.0) + sd)
			else:
				lim = minf(lim, st)
			if lim < v - 0.001:
				b[k] = lim
				changed.append(k)
	# назад: справа и снизу
	for iz in range(z1, z0 - 1, -1):
		var row2 := iz * NX
		for ix in range(x1, x0 - 1, -1):
			var k := row2 + ix
			var v := b[k]
			if v <= 0.0:
				continue
			var lim := v
			lim = minf(lim, (b[k + 1] if ix < NX - 1 else 0.0) + st)
			if iz < NZ - 1:
				lim = minf(lim, b[k + NX] + st)
				lim = minf(lim, (b[k + NX + 1] if ix < NX - 1 else 0.0) + sd)
				lim = minf(lim, (b[k + NX - 1] if ix > 0 else 0.0) + sd)
			else:
				lim = minf(lim, st)
			if lim < v - 0.001:
				b[k] = lim
				changed.append(k)
	base = b
	for k in changed:
		if depth[k] > base[k]:
			depth[k] = base[k]
		_mark(k % NX, k / NX, 2)


## Высоты рельефа куска — с каймой в одну вершину (для гладких нормалей на стыках)
func _ground_of(key: Vector2i) -> PackedFloat32Array:
	if _ground.has(key):
		return _ground[key]
	var g := PackedFloat32Array()
	var w := CH + 3
	g.resize(w * w)
	for j in w:
		for i in w:
			var ix := key.x * CH + i - 1
			var iz := key.y * CH + j - 1
			g[j * w + i] = _ter.height_at(_vx(ix), _vz(iz)) if _ter else 0.0
	_ground[key] = g
	return g


## Сглаженная «насыпанная» глубина в вершине (опора): среднее по 5×5 вершинам
func _smooth_base(ix: int, iz: int) -> float:
	var sum := 0.0
	for dz in range(-2, 3):
		var jz := clampi(iz + dz, 0, NZ - 1) * NX
		for dx in range(-2, 3):
			sum += base[jz + clampi(ix + dx, 0, NX - 1)]
	return sum / 25.0


func _d(ix: int, iz: int) -> float:
	if ix < 0 or iz < 0 or ix >= NX or iz >= NZ:
		return 0.0
	return depth[iz * NX + ix]


func _rebuild(key: Vector2i, solid: bool) -> void:
	var ix0 := key.x * CH
	var iz0 := key.y * CH
	if ix0 >= NX - 1 or iz0 >= NZ - 1:
		return
	var any := false
	for j in CH + 1:
		var ja := mini(iz0 + j, NZ - 1)
		for i in CH + 1:
			var ia := mini(ix0 + i, NX - 1)
			if depth[ja * NX + ia] >= MIN_D or base[ja * NX + ia] >= MIN_D:
				any = true
				break
		if any:
			break
	var ent: Array = _chunks.get(key, [])
	if not any:
		if not ent.is_empty():
			(ent[0] as MeshInstance3D).visible = false
			(ent[2] as CollisionShape3D).disabled = true
		return
	var g := _ground_of(key)
	var gw := CH + 3
	if ent.is_empty():
		var mi0 := MeshInstance3D.new()
		mi0.material_override = _mat
		mi0.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi0.mesh = ArrayMesh.new()
		mi0.extra_cull_margin = 2.0
		add_child(mi0)
		var body := StaticBody3D.new()
		body.set_meta("deep_snow", true)
		body.collision_layer = 1
		body.collision_mask = 0
		var cs0 := CollisionShape3D.new()
		var hs := HeightMapShape3D.new()
		hs.map_width = CH + 1
		hs.map_depth = CH + 1
		cs0.shape = hs
		cs0.scale = Vector3.ONE * CELL
		body.add_child(cs0)
		add_child(body)
		body.global_position = Vector3(_vx(ix0) + CH * CELL * 0.5, 0.0, _vz(iz0) - CH * CELL * 0.5)
		ent = [mi0, body, cs0]
		_chunks[key] = ent
		solid = true
	# --- видимая поверхность: сетка (CH+1)² вершин, высоты — с каймой для нормалей
	var hw := CH + 3
	var hh := PackedFloat32Array()
	hh.resize(hw * hw)
	for j in hw:
		for i in hw:
			var d := _d(ix0 + i - 1, iz0 + j - 1)
			hh[j * hw + i] = g[j * gw + i] + (d - 0.1 if d >= MIN_D * 0.5 else -0.18)
	var nv := (CH + 1) * (CH + 1)
	var fz: PackedFloat32Array = _fluff.get(key, PackedFloat32Array())
	if fz.is_empty():
		fz.resize(nv)
		for j in CH + 1:
			for i in CH + 1:
				fz[j * (CH + 1) + i] = maxf(_lumps.get_noise_2d(_vx(mini(ix0 + i, NX - 1)), _vz(mini(iz0 + j, NZ - 1))), 0.0) * 0.4
		_fluff[key] = fz
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uv2 := PackedVector2Array()
	verts.resize(nv)
	norms.resize(nv)
	cols.resize(nv)
	uv2.resize(nv)
	for j in CH + 1:
		for i in CH + 1:
			var ia := mini(ix0 + i, NX - 1)
			var ja := mini(iz0 + j, NZ - 1)
			var hi := (j + 1) * hw + (i + 1)
			var v := j * (CH + 1) + i
			verts[v] = Vector3(_vx(ix0 + i), hh[hi], _vz(iz0 + j))
			# нормаль по соседям (x растёт вправо, z — вниз по сетке к северу)
			var dxh := hh[hi + 1] - hh[hi - 1]
			var dzh := hh[hi + hw] - hh[hi - hw]
			norms[v] = Vector3(-dxh, 2.0 * CELL, dzh).normalized()
			var k := ja * NX + ia
			var d := depth[k]
			var b := base[k]
			cols[v] = Color(clampf(d / 1.5, 0.0, 1.0), clampf((b - d) / 0.45, 0.0, 1.0), 0.0)
			# рыхлость: сколько снег «пышнее» сразу после насыпи (бугры — пышнее)
			var fl := 0.0
			if d >= MIN_D and b - d < 0.05:
				fl = (0.12 + fz[v]) * minf(b, 1.2)
			uv2[v] = Vector2(tdep[k], fl)
	var idx := PackedInt32Array()
	for j in CH:
		var ja2 := iz0 + j
		if ja2 + 1 >= NZ:
			break
		for i in CH:
			var ia2 := ix0 + i
			if ia2 + 1 >= NX:
				break
			var r0 := ja2 * NX + ia2
			if maxf(maxf(depth[r0], depth[r0 + 1]), maxf(depth[r0 + NX], depth[r0 + NX + 1])) < MIN_D:
				continue
			var a := j * (CH + 1) + i
			var bb := a + 1
			var c := a + CH + 1
			var dd := c + 1
			idx.append_array(PackedInt32Array([a, c, bb, bb, c, dd]))
	var mi := ent[0] as MeshInstance3D
	var am := mi.mesh as ArrayMesh
	am.clear_surfaces()
	if idx.size() > 0:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mi.visible = true
	else:
		mi.visible = false
	if not solid:
		return
	# --- опора: гладкая, на SINK ниже насыпанного снега — карта высот (HeightMapShape3D, дёшево для физики)
	var W5 := CH + 5
	var rowsum := PackedFloat32Array()
	rowsum.resize(W5 * (CH + 1))
	for jj in W5:
		var gz := clampi(iz0 + jj - 2, 0, NZ - 1) * NX
		for i in CH + 1:
			var sacc := 0.0
			for dx in range(-2, 3):
				sacc += base[gz + clampi(ix0 + i + dx, 0, NX - 1)]
			rowsum[jj * (CH + 1) + i] = sacc
	var md := PackedFloat32Array()
	md.resize((CH + 1) * (CH + 1))
	var top := -1.0
	for j in CH + 1:
		for i in CH + 1:
			var sacc2 := 0.0
			for dz in 5:
				sacc2 += rowsum[(j + dz) * (CH + 1) + i]
			var h := sacc2 / 25.0 - SINK
			top = maxf(top, h)
			var q := (j + 1) * gw + (i + 1)
			# строка карты растёт к +z (на юг), моя сетка — к северу: переворачиваю
			md[(CH - j) * (CH + 1) + i] = (g[q] + (h if h > 0.03 else -0.3)) / CELL
	var cs := ent[2] as CollisionShape3D
	(cs.shape as HeightMapShape3D).map_data = md
	cs.disabled = top < 0.03


## Шаг 137: в протоптанной траншее? (снег примят до опоры) — по ней идти легче
func in_trench(x: float, z: float) -> bool:
	var ix := clampi(roundi(_ix(x)), 0, NX - 1)
	var iz := clampi(roundi(_iz(z)), 0, NZ - 1)
	var k := iz * NX + ix
	return base[k] - depth[k] > 0.35


## Высота опоры (куда встают ноги) — для проверок
func floor_at(x: float, z: float) -> float:
	var g: float = _ter.height_at(x, z) if _ter else 0.0
	var ix := clampi(roundi(_ix(x)), 0, NX - 1)
	var iz := clampi(roundi(_iz(z)), 0, NZ - 1)
	return g + maxf(_smooth_base(ix, iz) - SINK, 0.0)
