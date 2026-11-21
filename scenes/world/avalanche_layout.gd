class_name AvalancheLayout
extends RefCounted
## План Лавинной долины (шаг 56) — между Снежной пустошью и Трещинами.
##
##   z −1668 … −1728 (шаг 63): «Передышка» — 60 м тихого широкого дна между бурей и долиной (s от −60 до 0),
##                    контрольная точка; ни лавин, ни роботов, буря сюда уже не доходит.
##   z −1728 … −2428 (700 м), дно шириной ~140 м (шаг 64 — вдвое шире), по бокам — крутые снежные склоны до +100 м.
##   s — расстояние от входа в долину (s = S_Z − z).
##   Тропа сначала поднимается к перевалу (s ≈ 230, +34 м), потом долго спускается.
##
##   s   0 … 330  «тихий» участок: шум (бег, прыжки, драка) тревожит снег — со склона сбоку
##                срывается лавина, от неё не убежать. Тут же бродят снежные роботы-воришки.
##   s ≈ 330      середина пути: лавина сходит в любом случае — с перевала за спиной,
##                и гонится вниз по долине. Бежать без остановки!
##   s   650+     выполаживание: лавина тут останавливается; на скальном гребне — безопасно.
##   Шаг 67: долина длиннее (860 м), зона погони шире (+20 м) и длиннее (до s 805); в конце — разлом
##                с подъёмным мостом (RIFT_S): мост опускают лебёдкой, пока один крутит — другие бегут.
##
## Прежний мир (Трещины, Плато бурь, пещера, озеро, станция) — за долиной, сдвинут на север.

const CALM := 60.0                 ## шаг 63: тихий участок перед долиной (между бурей и лавинами)
const S_Z := -1728.0               ## южный край долины (вход после «Передышки»; пустошь кончается на −1668)
const LENGTH := 860.0
const N_Z := S_Z - LENGTH          ## −2368 — северный край, дальше прежний мир
## прежний мир: z_old = z + OLD_SHIFT (старые координаты, z_old = 8 — край площадки у Трещин)
const OLD_SHIFT := 2596.0
## на сколько весь мир за долиной сдвинулся к северу по сравнению с шагом 55
const EXTRA_SHIFT := 856.0

const QUIET_END := 330.0           ## до сюда — тихий участок (лавины только от шума)
const TRIGGER_S := 330.0           ## тут сходит большая лавина (в любом случае)
const RIFT_S := 812.0              ## шаг 67: разлом поперёк долины (середина)
const RIFT_HW := 7.0               ## полуширина разлома (не перепрыгнуть)
const RIFT_D := 24.0               ## глубина
const SAFE_S := RIFT_S + RIFT_HW   ## дальше лавина не доходит (за разломом)
const PASS_S := 230.0              ## перевал
const PASS_H := 34.0

## Шаг 66: зона погони (s 330…668) — убежать от лавины нельзя (спасают только капсулы), зато есть где петлять.
## Трещины поперёк дна: [s, dx от, dx до] (dx — от тропы). На тропе через трещину — снежный мост 4 м.
const CRACKS := [[418.0, -56.0, 32.0], [492.0, -22.0, 62.0], [612.0, -62.0, 16.0], [700.0, -40.0, 56.0]]
const CRACK_W := 3.0               ## полуширина трещины
const CRACK_D := 1.8               ## глубина (выпрыгнуть можно, но время потеряешь)
## Скальные гряды поперёк дна: [s, сторона обхода]. На тропе — узкий проход (2·PASS_HALF), у склона — широкий обход
const RIDGES := [[450.0, 1.0], [535.0, -1.0]]
## Шаг 67: высокая скальная стена с ледяным тоннелем на тропе (короче, но тесно и темно); обход — у склона
## Шаг 68: тоннель 30 м, плавно изгибается (выхода из середины не видно), ширина гуляет
const TUNNEL_S := 655.0
const TUNNEL_SIDE := 1.0           ## с какой стороны обход
const TUNNEL_HALF := 1.7           ## полуширина тоннеля (средняя)
const TUNNEL_LEN := 30.0
const TUNNEL_BEND := 5.0           ## на сколько середина уходит вбок от тропы
const PASS_HALF := 2.0
## Ледяные проплешины: [s, dx, полуось по x, полуось по s] — скользко
const ICE := [[400.0, 26.0, 13.0, 7.0], [472.0, -30.0, 12.0, 6.5], [512.0, 4.0, 14.0, 6.0],
		[590.0, 38.0, 11.0, 7.0], [632.0, -22.0, 13.0, 6.5], [680.0, 12.0, 15.0, 7.0], [770.0, -20.0, 14.0, 7.0]]


static func s_of(z: float) -> float:
	return S_Z - z


static func z_of(s: float) -> float:
	return S_Z - s


## Середина дна (тропа) по x
static func center_x(s: float) -> float:
	var taper := smoothstep(0.0, 80.0, s) * (1.0 - smoothstep(LENGTH - 100.0, LENGTH - 10.0, s))
	return taper * (22.0 * sin(s * 0.0105) + 8.0 * sin(s * 0.027))


## Высота дна
static func floor_y(s: float) -> float:
	if s < PASS_S:
		return PASS_H * smoothstep(8.0, PASS_S, s)
	return PASS_H * (1.0 - smoothstep(PASS_S, LENGTH - 10.0, s))


## Полуширина ровного дна (шаг 64: вдвое шире — лавине есть где разгуляться, искать заваленных дольше)
static func half_w(s: float) -> float:
	return 68.0 + 12.0 * sin(s * 0.013) + 22.0 * smoothstep(LENGTH - 70.0, LENGTH, s) + 20.0 * (1.0 - smoothstep(0.0, 60.0, s)) \
			+ 20.0 * smoothstep(300.0, 380.0, s) * (1.0 - smoothstep(LENGTH - 70.0, LENGTH, s))   # шаг 67: зона погони шире


## Точка тропы (на дне, без шума)
static func path_point(s: float) -> Vector3:
	return Vector3(center_x(s), floor_y(s), z_of(s))


## Направление тропы (вниз по долине, на север)
static func path_dir(s: float) -> Vector3:
	var a := path_point(s)
	var b := path_point(s + 2.0)
	return (b - a).normalized()


## Насколько трещины опускают дно в точке (x, s): 0 или отрицательное
static func crack_off(x: float, s: float) -> float:
	if s < 405.0 or s > RIFT_S + RIFT_HW + 3.0:
		return 0.0
	var dx := x - center_x(s)
	var out := 0.0
	# разлом поперёк всей долины (и подножий склонов): отвесные стенки
	var rs := absf(s - RIFT_S)
	if rs < RIFT_HW + 1.5:
		var kx := 1.0 - smoothstep(half_w(s) + 35.0, half_w(s) + 50.0, absf(dx))
		out = -RIFT_D * smoothstep(RIFT_HW + 1.5, RIFT_HW - 0.5, rs) * kx
	for c in CRACKS:
		var cs: float = c[0]
		var line := cs + 2.5 * sin(dx * 0.07 + cs) + 1.2 * sin(dx * 0.21 + cs * 0.3)
		var u := (s - line) / CRACK_W
		if absf(u) >= 1.0:
			continue
		var a: float = c[1]
		var b: float = c[2]
		var k := smoothstep(a, a + 12.0, dx) * (1.0 - smoothstep(b - 12.0, b, dx))
		k *= smoothstep(PASS_HALF, PASS_HALF + 2.5, absf(dx))   # снежный мост на тропе
		out = minf(out, -CRACK_D * k * (1.0 - u * u))
	return out


## Ось тоннеля: t от −LEN/2 (вход) до +LEN/2 (выход); y = 0
static func tunnel_point(t: float) -> Vector3:
	var dir := path_dir(TUNNEL_S)
	dir.y = 0.0
	dir = dir.normalized()
	var lat := Vector3(-dir.z, 0.0, dir.x)
	var u := 2.0 * t / TUNNEL_LEN
	var c := path_point(TUNNEL_S)
	c.y = 0.0
	return c + dir * t - lat * TUNNEL_SIDE * TUNNEL_BEND * (1.0 - u * u)


## Полуширина тоннеля в точке t (то шире, то уже)
static func tunnel_half(t: float) -> float:
	return TUNNEL_HALF + 0.35 * sin(t * 0.41 + 1.3) + 0.18 * sin(t * 1.13)


static func inside(p: Vector3, margin := 0.0) -> bool:
	var s := s_of(p.z)
	return s > -margin and s < LENGTH + margin and absf(p.x - center_x(s)) < half_w(s) + 60.0
