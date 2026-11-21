class_name MountainLayout
extends RefCounted
## Шаг 72–73: Пик — последняя локация (за Лавинной долиной).
##
## Массив из двух частей (как настоящая гора с предвершиной):
##  * Предвершина (380 м): по ней вьётся тропа-полка (2.5 витка). Внизу — широко и тихо, выше — уже, ветер,
##    мороз, облака, карнизы. На полке — уступы (подсадка), трещина (верёвочный мост), приюты.
##    Наверху — плато: приют и нижняя станция канатной дороги (её надо починить).
##  * Главная вершина (650 м) — каменная пирамида с тремя гребнями, к северу. Канатка везёт с плато на «Плечо»
##    (520 м): там приют (ночь и буран) и подножие стены. Дальше — только скалолазанием: 5 верёвок по стене
##    с полками, связка, подтягивание за руку, посылку поднимают лебёдкой по кулуару.
##  * Вершина: площадка 16 м, станция «Пик» — пункт приёма посылки.
## u — доля пути по тропе предвершины (0 — подножие, 1 — плато).

const W := preload("res://scenes/world/avalanche_layout.gd")

const CX := 0.0
const CZ := -2940.0                ## центр предвершины (тропа начинается в 167 м за концом Лавинной долины)
const BASE_Y := 0.0                ## равнина у подножия
const H_SP := 380.0                ## высота плато предвершины (конец тропы)
const PEAK := 700.0                ## высота главной вершины (шаг 119: выше — стена 152 м)
const R0 := 185.0                  ## радиус тропы у подножия
const RT := 66.0                   ## радиус тропы у плато
const PLAT_R := 54.0               ## ровное плато наверху
const TURNS := 2.5
const TH0 := PI * 0.5              ## начало тропы — с юга (со стороны долины)
const WOB := 3.5                   ## тропа не идеальная спираль — изгибается

## Главная вершина (шаг 119: отнесена на север — от Плеча к ней ночная дорога ~240 м, потом стена)
const BX := 0.0
const BZ := -3547.0                ## центр вершинной площадки
const SUMMIT_R := 16.0
const K_TOP := 3.6                 ## крутизна верхней пирамиды (м высоты на м)
const R_MID := 60.0                ## где верхняя пирамида переходит в склоны
const K_LOW := 2.6
const RIDGE := 0.15                ## насколько гребни выпирают

## «Плечо» — площадка на южном гребне вершины (приют, верхняя станция, подножие стены)
const SH_Y := 520.0
const SH_X := 16.0                 ## полуширина
const SH_ZS := -3332.0             ## южный край
const SH_ZN := -3352.0             ## северный край (отсюда — ночная дорога)

## Шаг 119: ночная дорога от Плеча к подножию стены: точки (x, z) и высоты по длине.
## Крутые подъёмы — обледенелые (скользко: бегом — укатишься вниз)
const ROAD_PTS := [Vector2(0.0, -3352.0), Vector2(14.0, -3390.0), Vector2(-12.0, -3420.0), Vector2(-34.0, -3446.0),
	Vector2(-30.0, -3470.0), Vector2(-4.0, -3478.0), Vector2(26.0, -3474.0), Vector2(34.0, -3490.0), Vector2(13.0, -3501.0)]
const ROAD_HALF := 6.0             ## полуширина дороги (шаг 121: широкая — лёд можно обойти)
## профиль: [доля длины, высота]
const ROAD_PROF := [[0.0, 520.0], [0.16, 522.0], [0.29, 529.0], [0.5, 532.0], [0.63, 539.0], [0.84, 541.0], [0.95, 547.5], [1.0, 548.0]]
## обледенелые подъёмы: [доля от, доля до]
## Шаг 121: ледяные пятна — [от, до (доля длины), центр вбок (м, + — влево по ходу), полуширина]; рядом — проход
const ROAD_ICE := [[0.12, 0.31, -1.8, 3.6], [0.42, 0.61, 1.8, 3.6], [0.69, 0.855, -1.8, 2.8]]   ## шаг 122: длинные — по 40–45 м (последнее — до поворота к стене)
const K_FILL := 1.35               ## откос насыпи (дорога по гребню — обрывы по бокам)
const K_CUT := 2.6                 ## стенка выемки (у вершины дорога врезана в скалу)

## Шаг 119: площадка у подножия стены (сюда выходит дорога)
const FOOT_Y := 548.0
const FOOT_X := 12.0
const FOOT_ZS := -3497.0
const FOOT_ZN := BZ + 28.0         ## подножие стены (−3519; шаг 123: полки узкие — стена ближе к вершине)

## Стена: 5 верёвок (участков) с полками; каждая следующая — на LEDGE_D м глубже (к северу)
const FACE_W := 4.6                ## по стене можно лезть |x| < FACE_W
const FACE_SIDE := 6.2             ## полки и стена — шириной до |x| < FACE_SIDE
const LEDGE_D := 2.0               ## шаг 123: узкие скальные полки
const PITCHES := [26.0, 25.0, 26.0, 25.0, 25.0, 25.0]       ## высоты участков (сумма = PEAK − FOOT_Y)
## Гладкий лёд у верха участка (не за что зацепиться): [участок, высота полосы, x от, x до]; трещина — с краю
const BANDS := []
## Кулуар для лебёдки (слева от стены)
const SLOT_X0 := -13.2
const SLOT_X1 := -6.6
const SLOT_ZN := BZ + 9.0          ## задняя стенка кулуара (−3211)
const HOIST := Vector2(-10.0, BZ + 12.5)          ## где висит трос лебёдки (x, z)
const SNAGS := [590.0, 640.0]      ## на этой высоте над тросом нависают карнизы
const SNAG_OUT := 5.2              ## насколько карниз торчит от задней стенки

## Канатная дорога: с плато на Плечо
const RW_A := Vector3(0.0, H_SP, CZ - PLAT_R + 2.0)       ## нижняя станция (северный край плато)
const RW_B := Vector3(0.0, SH_Y, SH_ZS + 5.0)              ## верхняя станция (кабина причаливает у южного края Плеча)

## Уступы на тропе: [u, высота]
const STEPS := [[0.12, 4.5], [0.36, 3.4], [0.78, 3.8]]      ## шаг 75: первый — 4.5 м (подсадка до края + ухватиться)
## Приюты на тропе (широкие площадки)
const CAMPS := [0.3, 0.68]
## Трещина поперёк полки (верёвочный мост): u и ширина, м
const CHASM_U := 0.606              ## шаг 101: середина пропасти (ледник кончается на 0.574)
const CHASM_W := 66.0             ## шаг 101: пропасть 66 м — старый подвесной мост ~70 м (чинить)
const CHASM_MG := 0.0             ## шаг 103: запас выреза рельефа за кромками (его закрывают плиты краёв)
const CHASM_IN := 20.0            ## …врезана в скалу на столько за край тропы (обойти нельзя)
const CHASM_OUT := 30.0           ## …и наружу — по склону вниз
const CHASM_STEP := 0.6            ## та сторона выше (с уклоном тропы ~2.5 м) — не допрыгнуть (прыжок ~1.5 м), перебросить друга — да
## Снежные карнизы: [u от, u до]
const CORNICES := [[0.86, 0.9]]    ## шаг 101: участок после моста — обычная полка
const SP_U0 := 0.18                ## шаг 77: пропасть с выступами (ледорубы) — начало по u
const SP_LEN := 200.0              ## …длина вдоль тропы, м (шаг 82: 200)
const CORNICE_STRIP := 1.9         ## твёрдая полоса у скалы
const RAIL_FROM := 0.3             ## выше — леера; ниже — каменный парапет
## Детали канатки: ниша над тропой, конец карниза, обломки старой кабины на плато
const PART_U := [0.74, 0.885]

const PLAIN_N := -3700.0           ## за этим (на север) — горы-рамка
const EDGE_X := 395.0              ## по бокам дальше — горы-рамка (у Пика мир шире: «крылья» рельефа до ±452)

const _TOTAL_STEP := 12.3          ## сумма высот уступов и ступени у трещины (обновлять вместе с STEPS)


# ---------------------------------------------------------------------------
#  Тропа предвершины
# ---------------------------------------------------------------------------

static func radius(u: float) -> float:
	var uc := clampf(u, 0.0, 1.0)
	# по углу — выступы и заливы (у всех витков на одном луче — одинаково): массив не конус, а «лепестками»
	var a := angle(uc)
	var lobes := 1.0 + 0.06 * sin(3.0 * a + 1.3) + 0.035 * sin(5.0 * a + 0.4)
	return (R0 - (R0 - RT) * uc) * lobes + WOB * sin(uc * TAU * 6.0) * (1.0 - uc * 0.6)


static func angle(u: float) -> float:
	return TH0 + TAU * TURNS * u


static func len_per_u(u: float) -> float:
	return TAU * TURNS * radius(u)


static func height(u: float) -> float:
	var uc := clampf(u, 0.0, 1.0)
	# внизу полого, выше круче (лёгкое начало)
	var y := BASE_Y + (H_SP - _TOTAL_STEP) * (0.55 * uc + 0.45 * uc * uc)
	for s in STEPS:
		var us: float = s[0]
		var du := 0.6 / len_per_u(us)
		y += float(s[1]) * clampf((u - us) / du, 0.0, 1.0)
	y += CHASM_STEP * clampf((u - CHASM_U) / (0.6 / len_per_u(CHASM_U)), 0.0, 1.0)
	return y


static func point(u: float) -> Vector3:
	var a := angle(u)
	var r := radius(u)
	return Vector3(CX + cos(a) * r, height(u), CZ + sin(a) * r)


static func tangent(u: float) -> Vector3:
	var a := point(u - 0.0005)
	var b := point(u + 0.0005)
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	return d.normalized()


static func outward(u: float) -> Vector3:
	var a := angle(u)
	return Vector3(cos(a), 0.0, sin(a))


## Ширина полки: внизу 12 м, у плато 6; у приютов шире
static func width(u: float) -> float:
	var uc := clampf(u, 0.0, 1.0)
	var w := lerpf(12.0, 6.0, uc)
	for c in CAMPS:
		w += 8.0 * (1.0 - smoothstep(0.0, 16.0, absf(u - float(c)) * len_per_u(float(c))))
	return w


static func in_cornice(u: float) -> bool:
	for c in CORNICES:
		if u >= float(c[0]) and u <= float(c[1]):
			return true
	return false


static func half_in(u: float) -> float:
	return width(u) * 0.5


static func half_out(u: float) -> float:
	if in_cornice(u):
		return -width(u) * 0.5 + CORNICE_STRIP
	return width(u) * 0.5


## Трещина: где по u (насколько внутри, м от середины). Шаг 77: и пропасть с выступами — внутри неё
## значение тоже меньше CHASM_W/2 (всё, что обходит трещину, обходит и её)
static func chasm_d(u: float) -> float:
	var d1 := absf(u - CHASM_U) * len_per_u(CHASM_U)
	return minf(d1, spire_d(u) + CHASM_W * 0.5)


## Пропасть с выступами: конец по u
static func sp_u1() -> float:
	return SP_U0 + SP_LEN / len_per_u(SP_U0)


## Сколько метров до пропасти с выступами (внутри — отрицательно)
static func spire_d(u: float) -> float:
	var a := (SP_U0 - u) * len_per_u(SP_U0)
	var b := (u - sp_u1()) * len_per_u(SP_U0)
	return maxf(a, b)


## Шаг 79: пропасть широкая — вырезана в склоне: внутрь горы на SP_IN, наружу на SP_OUT, глубиной SP_DEPTH
const SP_IN := 26.0
const SP_OUT := 19.0
const SP_DEPTH := 60.0


## Точка → (м вдоль пропасти от начала, м вбок от середины тропы, + наружу); NAN — далеко
static func sp_local(x: float, z: float) -> Vector2:
	var dx := x - CX
	var dz := z - CZ
	var r := sqrt(dx * dx + dz * dz)
	if r < RT or r > R0 + 40.0:
		return Vector2(NAN, NAN)
	var u := fposmod(atan2(dz, dx) - TH0, TAU) / (TAU * TURNS)
	var s := (u - SP_U0) * len_per_u(SP_U0)
	if s < -12.0 or s > SP_LEN + 12.0:
		return Vector2(NAN, NAN)
	var lat := r - radius(u)
	if absf(lat) > 40.0:
		return Vector2(NAN, NAN)
	return Vector2(s, lat)


## Внутрь (−) и наружу (+): края пропасти при s (чуть неровные)
static func sp_edges(s: float) -> Vector2:
	return Vector2(-SP_IN - 1.2 * sin(s * 0.21) - 0.6 * sin(s * 0.57 + 1.0), SP_OUT + 1.4 * sin(s * 0.17 + 2.0) + 0.5 * sin(s * 0.61))


## Высота дна пропасти в точке (NAN — точка не в пропасти)
static func sp_carve(x: float, z: float, pad := 0.0) -> float:
	var q := sp_local(x, z)
	if is_nan(q.x) or q.x < -pad or q.x > SP_LEN + pad:
		return NAN
	var e := sp_edges(q.x)
	if q.y < e.x - pad or q.y > e.y + pad:
		return NAN
	return lerpf(height(SP_U0), height(sp_u1()), clampf(q.x / SP_LEN, 0.0, 1.0)) - SP_DEPTH + sin(q.x * 0.4) * sin(q.y * 0.33) * 2.0


## Шаг 86: ледник со скрытыми трещинами (вместо парового котла). Поле вдоль тропы, шире её:
## внутрь горы на GL_IN, наружу на GL_OUT. Трещины поперёк — открытые, скрытые под снегом, с мостами.
const GL_U0 := 0.392
const GL_LEN := 400.0               ## шаг 95: 400 м
const GL_IN := 26.0                ## шаг 96: шире — ~50 м
const GL_OUT := 24.0
const GL_N := 26                     ## шаг 131: было 50 — реже, ~15 м между трещинами
const GL_MINW := 1.6                ## шаг 98: самая узкая трещина (тело 0.84 м — падает целиком)
static var _gl_cr: Array = []


static func gl_u1() -> float:
	return GL_U0 + GL_LEN / len_per_u(GL_U0)


static func in_glacier(u: float, pad := 0.0) -> bool:
	var s := (u - GL_U0) * len_per_u(GL_U0)
	return s > -pad and s < GL_LEN + pad


## Точка → (м вдоль ледника, м вбок от середины тропы); NAN — далеко
static func gl_local(x: float, z: float) -> Vector2:
	var dx := x - CX
	var dz := z - CZ
	var r := sqrt(dx * dx + dz * dz)
	if r < RT or r > R0 + 40.0:
		return Vector2(NAN, NAN)
	var a := fposmod(atan2(dz, dx) - TH0, TAU) / (TAU * TURNS)
	var best := Vector2(NAN, NAN)
	for k in 3:
		var u := a + k / TURNS
		var s := (u - GL_U0) * len_per_u(GL_U0)
		if s < -14.0 or s > GL_LEN + 14.0:
			continue
		var lat := r - radius(u)
		if absf(lat) < 34.0:
			best = Vector2(s, lat)
	return best


static func gl_line(s: float) -> float:
	return height(GL_U0 + s / len_per_u(GL_U0))


## Высота поверхности ледника (лёгкие волны и выпуклость; у концов — ровно как тропа)
static func gl_h(s: float, lat: float) -> float:
	var k := smoothstep(0.0, 10.0, s) * smoothstep(GL_LEN, GL_LEN - 10.0, s)
	var wav := 0.28 * sin(s * 0.19 + lat * 0.11) + 0.18 * sin(s * 0.07 - lat * 0.23) + 0.35 * (1.0 - clampf(lat * lat / 200.0, 0.0, 1.0))
	return gl_line(s) + wav * k


## Трещины: [s, lat0, lat1, ширина, наклон, изгиб, вид]; вид: hidden (вся под снегом), open (видна, узкая),
## wide (видна, широкая — обходить), bridged (видна, есть снежный мост). Одинаковые у всех (сид).
static func gl_cracks() -> Array:
	if not _gl_cr.is_empty():
		return _gl_cr
	var rng := RandomNumberGenerator.new()
	rng.seed = 870087
	# шаг 95: ~60% скрытых, остальные — узкие открытые, широкие (обходить), со снежными мостами
	var kinds: Array = []
	var krng := RandomNumberGenerator.new()
	krng.seed = 950095
	for kk in GL_N:
		var r0 := krng.randf()
		kinds.append("hidden" if r0 < 0.5 else ("open" if r0 < 0.68 else ("bridged" if r0 < 0.84 else "wide")))
	var step := (GL_LEN - 26.0) / float(GL_N - 1)
	for i in GL_N:
		var kd: String = kinds[i]
		var sc := 11.0 + step * i + rng.randf_range(-step * 0.2, step * 0.2)
		var w := rng.randf_range(1.7, 2.4)          # шаг 98: узких нет — тело проваливается целиком
		match kd:
			"open":
				w = rng.randf_range(1.8, 2.5) if rng.randf() < 0.6 else rng.randf_range(1.6, 2.0)
			"wide":
				w = rng.randf_range(3.0, 4.8)
			"bridged":
				w = rng.randf_range(2.2, 3.4)
		# шаг 88: по леднику трещины меняются: внизу узкие и прямее, в середине — дугами, наверху — шире, вздутые
		var zone := float(i) / float(GL_N - 1)
		w *= lerpf(0.88, 1.12, zone)
		# шаг 131: во всю ширину — реже; остальные — куски в разных местах поперёк ледника (есть где обойти)
		var full := kd == "bridged" or kd == "hidden" and rng.randf() < 0.3 or kd == "open" and rng.randf() < 0.12
		var l0 := -GL_IN - rng.randf_range(-2.5, 5.0)
		var l1 := GL_OUT + rng.randf_range(-2.5, 5.0)
		if kd == "bridged":
			l0 = -GL_IN - 5.0
			l1 = GL_OUT + 5.0
		if not full:
			var ln := rng.randf_range(7.0, 20.0) if kd != "wide" else rng.randf_range(12.0, 22.0)
			# центр — то левее, то правее, то посередине (по очереди со сдвигом), чтобы не стояли в одну линию
			var lane: float = [-0.6, 0.55, 0.0, 0.3, -0.3][i % 5]
			var c0 := clampf(lerpf(-GL_IN, GL_OUT, 0.5 + lane * 0.5) + rng.randf_range(-6.0, 6.0), -GL_IN + ln * 0.35, GL_OUT - ln * 0.35)
			l0 = c0 - ln * 0.5
			l1 = c0 + ln * 0.5
		# форма (без острых углов): 0 — дуга-полумесяц, 1 — извилистая, 2 — волнистая (несколько изгибов)
		var style := rng.randi_range(0, 2)
		if zone < 0.25 and rng.randf() < 0.5:
			style = 0
		var wa: float = [rng.randf_range(0.05, 0.15), rng.randf_range(0.45, 1.0), rng.randf_range(0.5, 0.9)][style]
		var wf: float = [0.25, rng.randf_range(0.15, 0.3), rng.randf_range(0.3, 0.5)][style]
		var bend := rng.randf_range(1.6, 3.8) * (1.0 if rng.randf() < 0.5 else -1.0) if style == 0 else rng.randf_range(-1.6, 1.6)
		var c := [sc, l0, l1, w, rng.randf_range(-0.16, 0.16), bend, kd,
			wa, wf, rng.randf() * TAU, style, rng.randf_range(0.1, 0.25 + 0.3 * zone), rng.randi_range(1, 3), rng.randf() * TAU,
			rng.randf_range(0.45, 1.0), rng.randi_range(0, 3), rng.randf() < 0.55, rng.randi_range(0, 2)]
		# не пересекаться с предыдущей: между ними везде ≥ 1.6 м снега
		if not _gl_cr.is_empty():
			var pc: Array = _gl_cr[_gl_cr.size() - 1]
			var need := 0.0
			var l := -GL_IN - 5.0
			while l <= GL_OUT + 5.0:
				need = maxf(need, gl_eff(pc, l).y + 5.0 - gl_eff(c, l).x)   # шаг 131: ≥ 5 м снега между трещинами
				l += 0.5
			c[0] = float(c[0]) + maxf(need, 0.0)
		if float(c[0]) > GL_LEN - 9.0:
			break
		_gl_cr.append(c)
	return _gl_cr


## Ось трещины на этом «вбок» (t — доля длины 0…1)
static func _gl_ctr(c: Array, lat: float, t: float) -> float:
	var ctr := float(c[0]) + tan(float(c[4])) * (lat - (float(c[1]) + float(c[2])) * 0.5) + float(c[5]) * sin(PI * t)
	var ph := lat * float(c[8]) + float(c[9])
	var wa := float(c[7])
	match int(c[10]):
		1:
			ctr += wa * (sin(ph) + 0.35 * sin(ph * 2.3 + 1.0))
		2:
			ctr += wa * (0.6 * sin(ph) + 0.3 * sin(ph * 2.1 + 2.0) + 0.12 * sin(ph * 4.3 + 0.5))
		_:
			ctr += wa * sin(ph)
	return ctr


## Как gl_span, но и за концом трещины — точка (её край), чтобы полосы снега стыковались
static func gl_eff(c: Array, lat: float) -> Vector2:
	var sp := gl_span(c, lat)
	if not is_nan(sp.x):
		return sp
	var l0 := float(c[1])
	var l1 := float(c[2])
	var l := clampf(lat, l0, l1)
	var t := (l - l0) / maxf(l1 - l0, 0.01)
	var ctr := _gl_ctr(c, l, t)
	return Vector2(ctr, ctr)


## Где трещина на этом «вбок»: (откуда, докуда) вдоль; x = NAN — тут её нет
static func gl_span(c: Array, lat: float) -> Vector2:
	var l0 := float(c[1])
	var l1 := float(c[2])
	if lat <= l0 or lat >= l1:
		return Vector2(NAN, NAN)
	var t := (lat - l0) / (l1 - l0)
	var ctr := _gl_ctr(c, lat, t)
	var prof := pow(sin(PI * t), float(c[14]))
	var ph2 := float(c[13])
	# вздутия и перехваты (плавные), мелкая рвань края
	var mod := 1.0 + float(c[11]) * sin(TAU * t * float(c[12]) * 0.5 + ph2) + 0.16 * sin(lat * 0.7 + ph2 * 2.0) + 0.08 * sin(lat * 1.9 + ph2)
	var rag := 1.0 + 0.06 * sin(lat * 2.3 + ph2) * sin(lat * 0.9)
	var hw := maxf(float(c[3]) * 0.5 * prof * mod * rag, 0.0)
	# края не параллельны: одна сторона «гуляет» отдельно
	var asym := 0.12 * float(c[3]) * sin(lat * 0.45 + ph2 * 3.0) * prof
	var right := maxf(hw + asym, hw * 0.4)
	# шаг 98: нигде не уже 1.6 м; концы — скруглённые (радиус 0.8 м), а не длинная тонкая щель
	var de := minf(lat - l0, l1 - lat)
	var cap := sqrt(maxf(1.0 - pow(1.0 - minf(de / 0.8, 1.0), 2.0), 0.0))
	var minw := GL_MINW * cap
	if hw + right < minw:
		var add := (minw - hw - right) * 0.5
		hw += add
		right += add
	return Vector2(ctr - hw, ctr + right)


## В трещине ли точка (с запасом pad); номер трещины или −1
static func gl_crack_at(s: float, lat: float, pad := 0.0) -> int:
	var cr := gl_cracks()
	for i in cr.size():
		if absf(s - float(cr[i][0])) > 12.0:
			continue
		var sp := gl_span(cr[i], lat)
		if not is_nan(sp.x) and s > sp.x - pad and s < sp.y + pad:
			return i
	return -1


## Рельеф под ледником: чуть ниже поверхности (её держит своя сетка), у трещин — глубоко
static func gl_carve(x: float, z: float) -> float:
	var q := gl_local(x, z)
	if is_nan(q.x) or q.x < 0.0 or q.x > GL_LEN or q.y < -GL_IN + 0.4 or q.y > GL_OUT - 0.2:
		return NAN
	if gl_crack_at(q.x, q.y, 1.4) >= 0:
		return gl_h(q.x, q.y) - 45.0
	return gl_h(q.x, q.y) - 0.45


static func cliff(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 0.6)


static func _foot(y: float) -> float:
	return 6.0 + 0.35 * (y - BASE_Y)


## Высота предвершины в точке; NAN — вне её. Шаг 99: пропасть прорезает и скалу, и склон под тропой
static func ground(x: float, z: float, n1: float, n2: float) -> float:
	var h := _ground_raw(x, z, n1, n2)
	if is_nan(h):
		return h
	var cut := chasm_cut(x, z)
	return minf(h, cut) if not is_nan(cut) else h


## Дно пропасти в точке (NAN — не над ней): по всей ширине от скалы до склона
static func chasm_cut(x: float, z: float) -> float:
	var dx := x - CX
	var dz := z - CZ
	var r := sqrt(dx * dx + dz * dz)
	var a := fposmod(atan2(dz, dx) - TH0, TAU)
	var k := roundf((CHASM_U * TAU * TURNS - a) / TAU)
	var uk := (a + TAU * k) / (TAU * TURNS)
	var along := (uk - CHASM_U) * len_per_u(CHASM_U)
	if absf(along) >= CHASM_W * 0.5 + CHASM_MG:
		return NAN                      # шаг 103: вырез шире пропасти — откос рельефа прячется в скальных плитах
	var lat := r - radius(uk)
	if lat < -(half_in(uk) + CHASM_IN) or lat > half_out(uk) + CHASM_OUT:
		return NAN
	# шаг 145: было −150 — вырез пробивал нижний виток (под мостом — пропасть с выступами), и снизу было видно
	# «висящие» стены и плиты. Дно — сразу под низом стен (−72), сверху его прячут туман и темнота
	return height(CHASM_U) - 76.0


static func _ground_raw(x: float, z: float, n1: float, n2: float) -> float:
	var dx := x - CX
	var dz := z - CZ
	var r := sqrt(dx * dx + dz * dz)
	if r > R0 + 80.0:
		return NAN
	var a := fposmod(atan2(dz, dx) - TH0, TAU)
	var uo := -1.0
	var ui := -1.0
	for k in 4:
		var uk := (a + TAU * k) / (TAU * TURNS)
		if uk > 1.0:
			break
		if radius(uk) >= r:
			uo = uk
		else:
			ui = uk
			break
	# скалы: крупные контрфорсы и кулуары (вертикальные рёбра) + мелкий рельеф
	var rib := absf(sin(a * 23.0 + n1 * 2.5)) * 2.0 - 1.0
	var rock := n1 * 7.0 + n2 * 2.0 + rib * 3.5
	if uo < 0.0:
		var u0 := a / (TAU * TURNS)
		var d := r - radius(u0) - half_out(u0)
		if d <= 0.0:
			return _shelf(u0, n2)
		var fy := height(u0)
		var t := clampf(d / _foot(fy), 0.0, 1.0)
		if fy - BASE_Y < 2.0:
			return lerpf(fy, BASE_Y, smoothstep(0.0, 1.0, t))
		return lerpf(fy, BASE_Y, pow(t, 0.6)) + rock * sin(PI * t) * smoothstep(2.0, 20.0, fy)
	if ui < 0.0:
		# внутри верхнего витка — обрыв до плато
		var d_o := radius(uo) - r
		if d_o <= half_in(uo):
			return _shelf(uo, n2)
		if r <= PLAT_R:
			return H_SP + n2 * 0.25
		var span := radius(uo) - half_in(uo) - PLAT_R
		if span <= 0.5:
			return H_SP
		var t2 := clampf((d_o - half_in(uo)) / span, 0.0, 1.0)
		return lerpf(height(uo), H_SP, cliff(t2)) + rock * sin(PI * t2) * 0.7
	var d_o2 := radius(uo) - r
	var d_i := r - radius(ui)
	if d_o2 <= half_in(uo):
		return _shelf(uo, n2)
	if d_i <= half_out(ui):
		return _shelf(ui, n2)
	var span2 := (radius(uo) - half_in(uo)) - (radius(ui) + half_out(ui))
	var t3 := clampf((d_o2 - half_in(uo)) / maxf(span2, 0.5), 0.0, 1.0)
	return lerpf(height(uo), height(ui), cliff(t3)) + rock * sin(PI * t3)


## Полка (с трещиной поперёк)
static func _shelf(u: float, n2: float) -> float:
	var h := height(u) + n2 * 0.12
	var cd := chasm_d(u)
	if cd < CHASM_W * 0.5:
		return h - 70.0
	return h


# ---------------------------------------------------------------------------
#  Главная вершина
# ---------------------------------------------------------------------------

## Сколько «гребня» в направлении (гребни — на юг и ещё два через 120°)
static func ridge_k(dx: float, dz: float) -> float:
	var phi := atan2(dz, dx)
	return pow(maxf(cos(3.0 * (phi - PI * 0.5)), 0.0), 2.0)


## Естественная высота пирамиды (без Плеча и стены)
static func block_natural(x: float, z: float, n1: float, n2: float) -> float:
	var dx := x - BX
	var dz := z - BZ
	var r := sqrt(dx * dx + dz * dz)
	var phi := atan2(dz, dx)
	# контрфорсы и кулуары по кругу, неровный силуэт
	var buttress := 0.07 * sin(5.0 * phi + 0.7) + 0.05 * sin(9.0 * phi + 2.1) + 0.04 * sin(13.0 * phi)
	var re := r * (1.0 - RIDGE * ridge_k(dx, dz)) * (1.0 + 0.05 * n1 + buttress * smoothstep(SUMMIT_R + 4.0, SUMMIT_R + 30.0, r))
	var h: float
	const ROUND := 10.0                # край вершины скруглён (не «стол» с отвесом)
	if re <= SUMMIT_R:
		h = PEAK                          # шаг 122: ровная площадка под станцию-маяк
	elif re <= SUMMIT_R + ROUND:
		var e := re - SUMMIT_R
		h = PEAK - K_TOP * e * e / (2.0 * ROUND)
	elif re <= R_MID:
		h = PEAK - K_TOP * ROUND * 0.5 - (re - SUMMIT_R - ROUND) * K_TOP
	else:
		h = PEAK - K_TOP * ROUND * 0.5 - (R_MID - SUMMIT_R - ROUND) * K_TOP - (re - R_MID) * K_LOW
	# скальные пояса: полки и стенки (порода слоями) — ниже вершинного купола
	if re > SUMMIT_R + 6.0 and h > 40.0 and h < PEAK - 35.0:
		var band := 34.0
		var tb := (h + n2 * 6.0) / band
		var ter: float = (floorf(tb) + smoothstep(0.25, 0.95, fposmod(tb, 1.0))) * band - n2 * 6.0
		h = lerpf(h, ter, 0.55)
	# предвершина-«жандарм» к востоку
	var dx2 := x - (BX + 92.0)
	var dz2 := z - (BZ + 24.0)
	var r2 := sqrt(dx2 * dx2 + dz2 * dz2) * (1.0 + 0.08 * sin(4.0 * atan2(dz2, dx2) + 1.0))
	h = maxf(h, 555.0 - r2 * 3.1)
	if re > SUMMIT_R + 2.0:
		var rib := absf(sin(atan2(dz, dx) * 31.0 + n2 * 2.0)) * 2.0 - 1.0
		h += (n1 * 9.0 + n2 * 3.0 + rib * 4.0) * smoothstep(SUMMIT_R + 2.0, SUMMIT_R + 12.0, re)
	return h


## Верх участка k стены (полка над ним)
static func pitch_top(k: int) -> float:
	var y := FOOT_Y
	for i in k + 1:
		y += float(PITCHES[i])
	return y


static func pitch_base(k: int) -> float:
	return FOOT_Y if k == 0 else pitch_top(k - 1)


## Плоскость стены участка k (z)
static func face_z(k: int) -> float:
	return FOOT_ZN - LEDGE_D * k


## Какой участок стены (полка) под точкой: −1 — Плечо (южнее стены), 5 — вершина
static func face_cell(z: float) -> int:
	if z > FOOT_ZN:
		return -1
	return mini(int(floor((FOOT_ZN - z) / LEDGE_D)), PITCHES.size())


## Высота главной вершины в точке (с Плечом, полками стены и кулуаром); NAN — далеко
static func block(x: float, z: float, n1: float, n2: float) -> float:
	var dx := x - BX
	var dz := z - BZ
	if dx * dx + dz * dz > 330.0 * 330.0:
		return NAN
	var h := block_natural(x, z, n1, n2)
	# стена: ступени-полки (вертикальные части — отдельные меши со своей коллизией)
	var ax := absf(x)
	var in_face_x := 1.0 - smoothstep(FACE_SIDE, FACE_SIDE + 2.5, ax)
	# шаг 119: дорога от Плеча (насыпь по гребню / выемка в скале)
	h = road_shape(x, z, h, n2)
	# площадка у подножия стены — врезана в пирамиду (стенки выемки)
	var fx := maxf(ax - FOOT_X, 0.0)
	var fz := maxf(maxf(z - FOOT_ZS, FOOT_ZN - z), 0.0)
	var fe := sqrt(fx * fx + fz * fz)
	if z >= FOOT_ZN - 0.5:
		if fe < 0.01:
			h = FOOT_Y + n2 * 0.08
		else:
			h = minf(h, FOOT_Y + fe * K_CUT + n1 * 1.5)
	if in_face_x > 0.0 and z <= FOOT_ZN + 0.5 and z > FOOT_ZN - LEDGE_D * PITCHES.size() - 3.0:
		var k := face_cell(z + 0.75)          # ступенька — на 0.75 м за плоскостью стены (её закрывает меш)
		var hy := FOOT_Y if k < 0 else pitch_top(mini(k, PITCHES.size() - 1))
		h = lerpf(h, hy, in_face_x)
	# кулуар лебёдки: узкий жёлоб до самого подножия
	if x > SLOT_X0 - 2.0 and x < SLOT_X1 + 1.0 and z < FOOT_ZN + 0.5 and z > SLOT_ZN - 1.5:
		var kx := smoothstep(SLOT_X0 - 2.0, SLOT_X0, x) * (1.0 - smoothstep(SLOT_X1, SLOT_X1 + 1.0, x))
		var kz := smoothstep(SLOT_ZN - 1.5, SLOT_ZN, z)
		h = lerpf(h, FOOT_Y, kx * kz)
	# Плечо: ровная площадка на гребне (шаг 119: под ней — насыпь-откос, вершина теперь далеко)
	var ex := maxf(ax - SH_X, 0.0)
	var ez := maxf(maxf(z - SH_ZS, SH_ZN - z), 0.0)
	var e := sqrt(ex * ex + ez * ez)
	if e < 0.01:
		h = SH_Y + n2 * 0.08
	else:
		h = maxf(h, SH_Y - e * K_FILL + n1 * 3.0 * smoothstep(2.0, 12.0, e))
	# под причалом канатки — жёлоб (кабина подходит снизу и не задевает склон)
	if absf(x - RW_B.x) < 6.0 and z > SH_ZS + 0.3 and z < SH_ZS + 40.0:
		var dzs := z - SH_ZS
		h = minf(h, lerpf(h, SH_Y - 4.0 - dzs * 0.9, 1.0 - smoothstep(3.5, 6.0, absf(x - RW_B.x))))
	return h


# ---------------------------------------------------------------------------
#  Шаг 119: ночная дорога
# ---------------------------------------------------------------------------
static var _rd: PackedVector3Array = PackedVector3Array()     ## точки оси через ~2 м (x, y, z)
static var _rs: PackedFloat32Array = PackedFloat32Array()     ## длина до точки
static var _fd: PackedVector3Array = PackedVector3Array()     ## растр 2 м вокруг дороги: (вбок, высота, длина)
const _F0 := Vector2(-190.0, -3650.0)
const _FC := 2.0
const _FN := Vector2i(190, 225)


static func _road_build() -> void:
	if not _rd.is_empty():
		return
	# сглаженная (Catmull-Rom) ось
	var raw: Array = []
	var n := ROAD_PTS.size()
	for i in n - 1:
		var p0: Vector2 = ROAD_PTS[maxi(i - 1, 0)]
		var p1: Vector2 = ROAD_PTS[i]
		var p2: Vector2 = ROAD_PTS[i + 1]
		var p3: Vector2 = ROAD_PTS[mini(i + 2, n - 1)]
		var seg := p1.distance_to(p2)
		var m := maxi(int(seg / 3.0), 2)
		for j in m:
			var t := j / float(m)
			var t2 := t * t
			var t3 := t2 * t
			raw.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	raw.append(ROAD_PTS[n - 1])
	var acc := 0.0
	var lens: Array = [0.0]
	for i2 in range(1, raw.size()):
		acc += (raw[i2] as Vector2).distance_to(raw[i2 - 1])
		lens.append(acc)
	for i3 in raw.size():
		var q: Vector2 = raw[i3]
		_rd.append(Vector3(q.x, _prof(lens[i3] / acc), q.y))
		_rs.append(lens[i3])
	# растр расстояний (для рельефа)
	_fd.resize(_FN.x * _FN.y)
	for iz in _FN.y:
		for ix in _FN.x:
			var r := _near_exact(_F0.x + ix * _FC, _F0.y + iz * _FC)
			_fd[iz * _FN.x + ix] = Vector3(r.x, r.y, r.z)


static func _prof(f: float) -> float:
	for i in ROAD_PROF.size() - 1:
		var a: Array = ROAD_PROF[i]
		var b: Array = ROAD_PROF[i + 1]
		if f <= float(b[0]):
			var t := (f - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			return lerpf(float(a[1]), float(b[1]), smoothstep(0.0, 1.0, t) * 0.35 + t * 0.65)
	return float(ROAD_PROF.back()[1])


static func road_len() -> float:
	_road_build()
	return _rs[_rs.size() - 1]


## Точно: ближайшая точка оси — Vector3(расстояние вбок, высота дороги, длина от Плеча)
static func _near_exact(x: float, z: float) -> Vector3:
	var best := INF
	var by := 0.0
	var bs := 0.0
	for i in _rd.size() - 1:
		var a := _rd[i]
		var b := _rd[i + 1]
		var abx := b.x - a.x
		var abz := b.z - a.z
		var l2 := abx * abx + abz * abz
		var t := clampf(((x - a.x) * abx + (z - a.z) * abz) / maxf(l2, 0.0001), 0.0, 1.0)
		var px := a.x + abx * t - x
		var pz := a.z + abz * t - z
		var d := px * px + pz * pz
		if d < best:
			best = d
			by = lerpf(a.y, b.y, t)
			bs = lerpf(_rs[i], _rs[i + 1], t)
	return Vector3(sqrt(best), by, bs)


## Ближайшая точка оси: Vector4(расстояние вбок, высота дороги, длина от Плеча, 0); x = INF — дальше r
static func road_near(x: float, z: float, r := 40.0) -> Vector4:
	_road_build()
	if x < -60.0 - r or x > 60.0 + r or z > -3340.0 + r or z < -3515.0 - r:
		return Vector4(INF, 0.0, 0.0, -1.0)
	var e := _near_exact(x, z)
	if e.x > r:
		return Vector4(INF, 0.0, 0.0, -1.0)
	return Vector4(e.x, e.y, e.z, 0.0)


## Для рельефа: то же по растру (быстро); x = INF — вне растра
static func road_field(x: float, z: float) -> Vector3:
	_road_build()
	var fx := (x - _F0.x) / _FC
	var fz := (z - _F0.y) / _FC
	if fx < 0.0 or fz < 0.0 or fx >= _FN.x - 1 or fz >= _FN.y - 1:
		return Vector3(INF, 0.0, 0.0)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := _fd[iz * _FN.x + ix].lerp(_fd[iz * _FN.x + ix + 1], tx)
	var b := _fd[(iz + 1) * _FN.x + ix].lerp(_fd[(iz + 1) * _FN.x + ix + 1], tx)
	return a.lerp(b, tz)


## Точка на оси дороги по длине s (м от Плеча)
static func road_at(s: float) -> Vector3:
	_road_build()
	s = clampf(s, 0.0, road_len())
	var lo := 0
	var hi := _rs.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _rs[mid] <= s:
			lo = mid
		else:
			hi = mid
	var t := (s - _rs[lo]) / maxf(_rs[hi] - _rs[lo], 0.0001)
	return _rd[lo].lerp(_rd[hi], t)


## Направление дороги (вверх по ней) в точке s
static func road_dir(s: float) -> Vector3:
	var a := road_at(s - 0.8)
	var b := road_at(s + 0.8)
	var d := b - a
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


## Обледенелый подъём под точкой s
static func road_icy(s: float) -> bool:
	var f := s / road_len()
	for r in ROAD_ICE:
		if f >= float(r[0]) and f <= float(r[1]):
			return true
	return false


## Шаг 121: смещение вбок от оси (+ — влево по ходу вверх) и s; x = INF — не у дороги
static func road_lat(x: float, z: float) -> Vector2:
	var rn := road_near(x, z, ROAD_HALF + 2.0)
	if rn.x == INF:
		return Vector2(INF, 0.0)
	var c := road_at(rn.z)
	var d := road_dir(rn.z)
	var lat := Vector2(-d.z, d.x).normalized()
	return Vector2(Vector2(x - c.x, z - c.z).dot(lat), rn.z)


## Шаг 121: ледяное пятно под точкой (x, z)
static func ice_at(x: float, z: float) -> bool:
	var ls := road_lat(x, z)
	if ls.x == INF:
		return false
	var f := ls.y / road_len()
	for r in ROAD_ICE:
		if f >= float(r[0]) and f <= float(r[1]) and absf(ls.x - float(r[2])) < float(r[3]):
			return true
	return false


## Шаг 121: где идти мимо льда на длине s (смещение вбок; 0 — по оси)
static func safe_lat(s: float) -> float:
	var L := road_len()
	for r in ROAD_ICE:
		if s >= float(r[0]) * L - 8.0 and s <= float(r[1]) * L + 2.0:
			var c := float(r[2])
			var h := float(r[3])
			var gl := ROAD_HALF - (c + h)          # проход слева
			var gr := (c - h) + ROAD_HALF          # проход справа
			return (c + h + gl * 0.5) if gl >= gr else (c - h - gr * 0.5)
	return 0.0


## Форма рельефа у дороги: по оси — дорога; дальше — насыпь (обрыв) вниз или выемка (скала) вверх
static func road_shape(x: float, z: float, h: float, n2: float) -> float:
	var rn := road_field(x, z)
	if rn.x == INF:
		return h
	var d := rn.x
	var ry := rn.y
	# у Плеча и у подножия — их площадки
	if d <= ROAD_HALF:
		return ry + n2 * 0.06
	var dd := d - ROAD_HALF
	var hf := ry - dd * K_FILL - dd * dd * 0.004 - 0.25
	var hc := ry + 0.4 + dd * K_CUT
	if h < hf:
		return hf
	if h > hc:
		# за линией стены (к вершине) выемку не режем — там стена и вершина
		return lerpf(h, hc, smoothstep(FOOT_ZN - 0.5, FOOT_ZN + 6.0, z))
	return h


## На дороге (или у края)
static func on_road(p: Vector3, pad := 0.6) -> bool:
	var rn := road_near(p.x, p.z, 8.0)
	return rn.x != INF and rn.x < ROAD_HALF + pad and absf(p.y - rn.y) < 3.0


## Точка на стене: x (вбок), высота y, участок k → мировые координаты (у самой стены)
static func face_point(k: int, x: float, y: float) -> Vector3:
	return Vector3(BX + x, y, face_z(k))


static func summit() -> Vector3:
	return Vector3(BX, PEAK, BZ)


# ---------------------------------------------------------------------------
#  Где я
# ---------------------------------------------------------------------------

## Ближайшая точка тропы (u) — по углу и высоте; −1 — не на тропе предвершины
static func u_at(p: Vector3) -> float:
	var dx := p.x - CX
	var dz := p.z - CZ
	var r := sqrt(dx * dx + dz * dz)
	if r > R0 + 60.0:
		return -1.0
	var a := fposmod(atan2(dz, dx) - TH0, TAU)
	var best := -1.0
	var bd := INF
	for k in 4:
		var uk := (a + TAU * k) / (TAU * TURNS)
		if uk > 1.0:
			break
		var d := absf(height(uk) - p.y) + absf(radius(uk) - r) * 0.5
		if d < bd:
			bd = d
			best = uk
	if r < PLAT_R + 2.0 and p.y > H_SP - 6.0:
		return 1.0
	return best


static func on_block(p: Vector3) -> bool:
	var dx := p.x - BX
	var dz := p.z - BZ
	return dx * dx + dz * dz < 300.0 * 300.0 and p.y > 60.0


static func on_mountain(p: Vector3) -> bool:
	if p.z >= W.N_Z:
		return false
	var dx := p.x - CX
	var dz := p.z - CZ
	return dx * dx + dz * dz < (R0 + 50.0) * (R0 + 50.0) or on_block(p)


## На Плече (площадка у подножия стены)
static func on_shoulder(p: Vector3) -> bool:
	return absf(p.x - BX) < SH_X + 1.0 and p.z < SH_ZS + 1.0 and p.z > SH_ZN - 0.5 and absf(p.y - SH_Y) < 4.0 \
		or (p.x > SLOT_X0 and p.x < SLOT_X1 and p.z <= SH_ZN and p.z > SLOT_ZN and absf(p.y - SH_Y) < 4.0)


## Шаг 119: на площадке у подножия стены (или в кулуаре лебёдки)
static func on_foot(p: Vector3) -> bool:
	return absf(p.x - BX) < FOOT_X + 1.0 and p.z < FOOT_ZS + 1.0 and p.z > FOOT_ZN - 0.5 and absf(p.y - FOOT_Y) < 4.0 \
		or (p.x > SLOT_X0 and p.x < SLOT_X1 and p.z <= FOOT_ZN and p.z > SLOT_ZN and absf(p.y - FOOT_Y) < 4.0)


## Канатная дорога: точка на тросе (t 0…1), с провисом
static func cable_at(t: float) -> Vector3:
	var a := RW_A + Vector3.UP * 12.0
	var b := RW_B + Vector3.UP * 12.0
	return a.lerp(b, t) + Vector3.DOWN * 16.0 * sin(PI * t)
