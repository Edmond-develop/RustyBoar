extends Node3D
## Шаг 109: канатка «Плато → Плечо» — длинный серпантин (~800 м, 4–5 минут), большая кабина на 3–4 человек.
##   * Пульт — в будке на каждой станции. E у пульта — встал за пульт (крупный план). Управление МЫШЬЮ:
##     тянешь ручку хода, крутишь штурвал лебёдки (кабина выше/ниже) и штурвал поворота кабины, щёлкаешь
##     тумблеры стрелок; клавиши дублируют (W/S, R/F, A/D, 1/2/3, пробел, C, H — гудок).
##   * На пульте — монитор: камера смотрит на кабину. Ближе к середине пути — помехи, с середины «НЕТ СИГНАЛА»:
##     дальше оператор слеп и слушается тех, кто в кабине (голос и сигналы 1–9).
##   * На тросе: гребни (кабину выше), сосульки (ниже), ледяные столбы (вдоль), ущелья ветров (тихо в порыв),
##     окна в скале (высота + вдоль), камнепады (переждать обвал и проскочить), три развилки с тупиками.
##   * Удар на малом ходу — тряска и отскок; на большом — двери настежь, кто не держится (E) — вылетает.
##   * Пустую кабину можно вызвать к своей станции — едет сама.
## Решает хост; всем — состояние кабины ~20 раз в секунду и события (удар, сигнал, причал).

const M := preload("res://scenes/world/mountain_layout.gd")
const SFX := preload("res://scripts/sfx.gd")
const GATE := preload("res://scenes/world/mountain_gate.gd")
const SPIRE_SHADER := preload("res://shaders/spire_rock.gdshader")
const MON_SHADER := preload("res://shaders/crt_monitor.gdshader")
const RWA := "res://assets/ropeway/"   ## шаг 114: ассеты канатки (рычаги, кнопки, металл, скалы)
const LEVA := 55.0                 ## рычаг хода: наклон ручки от среднего, градусов

const CW := 3.4                    ## ширина кабины (её x)
const CL := 5.2                    ## длина (её z)
const CHT := 2.8                   ## высота корпуса
const CTOP := 3.22                 ## верх лебёдки на крыше
const CR := 0.42                   ## скругление углов корпуса
const DOOR_HZ := 0.65              ## полупроём двери (по z)
const H_DOCK := 12.0               ## подвес у станции: пол кабины вровень с платформой
const H_MIN := 6.0
const H_MAX := 18.0
const H_RATE := 2.2                ## м/с
const YAW_RATE := 0.9              ## рад/с
const GEARS := [-3.0, -1.2, 0.0, 1.2, 3.0, 5.5, 10.0]
const GEAR_N := 2
const GEAR_NAMES := ["Н2", "Н1", "0", "1", "2", "3", "4"]
const ACC := 1.05                  ## большая кабина разгоняется и тормозит дольше
const STRONG_V := 2.0              ## удар на таком ходу — сильный (двери настежь)
const DOCK_V := 1.3
const SAG := 0.012
const WIND_V := 1.7
const SIGNALS := ["ВПЕРЁД", "НАЗАД", "БЫСТРЕЕ", "МЕДЛЕННЕЕ", "СТОП!", "ВЫШЕ", "НИЖЕ", "ПОВЕРНУТЬ", "СТРЕЛКА"]
const SIG_SHORT := ["ВПЕР", "НАЗАД", "БЫСТР", "МЕДЛ", "СТОП", "ВЫШЕ", "НИЖЕ", "ПОВОР", "СТРЕЛ"]
## Маршрут в своей системе: x — вдоль (от Плато к Плечу), y — вбок (+ вправо). Серпантин над пропастью;
## последняя точка (станция Плеча) добавляется сама.
const WP := [Vector2(0, 0), Vector2(55, 0), Vector2(110, 60), Vector2(150, 140), Vector2(220, 170), Vector2(285, 125),
	Vector2(240, 45), Vector2(170, 80), Vector2(125, 10), Vector2(120, -80), Vector2(190, -140), Vector2(260, -180),
	Vector2(310, -120), Vector2(250, -60), Vector2(272, -4)]
const DEAD := [[5, Vector2(270, 195)], [8, Vector2(70, -40)], [12, Vector2(318, -55)]]   ## развилка у опоры WP[i] → тупик
enum {RIDGE, ICE, SLOT, WIND, WINDOW, ROCK, MILL, CANYON, RGATE}
## Препятствия: [вид, участок (от WP[i]), с какого метра участка, длина, параметр 1, параметр 2]
##   гребень: подвес не длиннее p1; сосульки: не короче p1; окно: подвес p1…p2 и вдоль; столбы: вдоль
## Шаг 112: первые ~250 м — свободный полёт (покататься), дальше препятствия реже и сложнее по нарастающей
const OBS_DEF := [
	[RIDGE, 3, 25.0, 13.0, 9.0, 0.0],
	[ICE, 4, 30.0, 8.0, 15.0, 0.0],
	[SLOT, 5, 28.0, 8.0, 0.0, 0.0],
	[MILL, 6, 40.0, 1.6, 0.0, 0.0],
	[WIND, 7, 18.0, 36.0, 0.0, 0.0],
	[WINDOW, 8, 22.0, 6.0, 10.3, 13.5],
	[ROCK, 8, 60.0, 8.0, 0.0, 0.0],
	[RIDGE, 9, 20.0, 12.0, 7.5, 0.0],
	[ICE, 9, 54.0, 8.0, 15.5, 0.0],
	[ROCK, 10, 20.0, 8.0, 0.0, 0.0],
	[WINDOW, 10, 55.0, 6.0, 14.0, 17.0],
	[MILL, 11, 40.0, 1.6, 0.0, 0.0],
	[CANYON, 12, 12.0, 50.0, 0.0, 0.0],
	[RGATE, 12, 18.0, 1.4, 7.0, 10.0],
	[RGATE, 12, 27.0, 1.4, 13.5, 16.5],
	[RGATE, 12, 36.0, 1.4, 9.0, 12.0],
	[RGATE, 12, 45.0, 1.4, 14.5, 17.5],
	[RGATE, 12, 54.0, 1.4, 6.5, 9.5],
]
const OBS_NAMES := ["скальный гребень", "ледяные сосульки", "ледяные столбы", "скалу (порыв ветра)", "скальную стену", "камни",
	"лопасть ветряка", "стену каньона", "скальные ворота"]
## Ветряк: ступица сбоку и ниже троса, три лопасти крутятся поперёк троса — проскочить между ними
const MILL_W := 0.45               ## рад/с
const MILL_R := 13.0
const MILL_HUB := Vector2(10.5, -15.0)   ## (вбок, вниз) от троса
const MILL_BW := 0.75              ## полуширина лопасти
const GAP := 3.8                   ## щель/окно в ширину (кабина 3.4 — только вдоль, почти без зазора)
const ROCK_T := [7.5, 9.0, 11.0]   ## камнепад: тихо до 7.5 с, гул до 9, камни до 11 (цикл 11 с)
const ROCK_HIT := 10.0              ## с этого мига камни уже на уровне кабины
const MON_LOSE := 0.5              ## с середины пути камера кабины не ловит
## Шаг 113: открытые окна, люк на крышу, два троса подвеса, турбо-ползунок с перегревом
const WIN_Z := Vector2(0.85, 2.1)  ## открытые окна: правый борт (+x) z 0.85…2.1, левый (−x) z −2.1…−0.85
const WIN_Y := Vector2(0.5, 2.42)  ## проём по высоте: низкий подоконник — можно вывалиться
const HATCH := Vector3(0.0, 2.5, -1.8)   ## люк в потолке (у жёлтой стойки)
const ANCH := [Vector3(0.0, 3.38, 0.98), Vector3(0.0, 3.38, -0.98)]   ## крепления тросов на крыше (бит 1, бит 2)
const XTRA_V := 10.0               ## турбо: до +10 м/с к ходу
const SNAP_V := 4.5                ## удар на таком ходу рвёт трос
const TILT := 0.2                  ## на одном тросе кабину перекашивает (рад)
const TILT_M := 0.3                ## …и её край опускается/поднимается — запас по высоте у препятствий
const FIX_T := 5.0                 ## варить трос, сек
const MEND_T := 5.0                ## заколотить пробоину / вправить дверь, сек
const SLOT_N := 4                  ## шаг 115: что может разрушиться: 0 — правый борт (глухая половина), 1 — левый, 2/3 — двери
const HAMMER_AT := Vector3(0.0, 1.35, 1.19)   ## шаг 116: молоток висит на щитке у передней жёлтой стойки
const WELD_BOX := Vector3(0.6, 2.85, 1.85)      ## шаг 117: ящик со сваркой — в переднем конце крыши (подальше от люка)

var mtn: Node
var is_open := false               ## для ботов (coop_gate): дела у канатки бывают всегда
var at_b := false                  ## (для совместимости) кабина у Плеча

# --- состояние кабины (решает хост) ---
var tr := 0                        ## трос: 0 — главный, 1…3 — тупики
var s := 0.0                       ## метров по тросу
var v := 0.0
var H := H_DOCK
var yaw := PI * 0.5                ## поворот кабины относительно троса (0 — вдоль)
var gear := GEAR_N
var sw := [false, true, false]     ## стрелки: true — вправо
var docked := 0                    ## 0 — у Плато, 1 — у Плеча, −1 — в пути
var doors := 1                     ## маска открытых дверей: 1 — правая (+x), 2 — левая
var gust := 0.0
var gust_ph := 0                   ## 0 — тихо, 1 — сейчас дунет, 2 — порыв
var rock_ph := 0                   ## 0 — тихо, 1 — гул, 2 — камни летят
var hits := 0
var auto_to := -1                  ## пустая кабина едет сама к станции
var op_pid := -1
var op_panel := -1
var hdir := 0
var rdir := 0
var _h_tgt := NAN
var _y_tgt := NAN
var _hv := 0.0                     ## лебёдка и поворот разгоняются/тормозят не мгновенно
var _yv := 0.0
var _close_t := 0.0
var _hit_t := 0.0
var _gust_t := 0.0
var _rock_t := 0.0
var _commit := -1                  ## автоматика/бот решились проскочить это препятствие (не тормозить посреди)
var _clk := 0.0                    ## общие часы (ветряки, у всех одинаково — шлёт хост)
var _send_t := 0.0
var _scrape_t := 0.0
var _horn_cd := 0.0
var _sigq: Array = []              ## бот у пульта: [когда, сигнал]
var _bot_sig_t := 0.0
var _bot_last := -1
var _riders := 0
var _sig_t := {}
var ropes := 3                     ## шаг 113: целые тросы (бит 1 — передний, бит 2 — задний)
var _xtra_in := 0.0                ## турбо-ползунок у оператора 0…1
var _xtra := 0.0                   ## турбо, что работает сейчас
var _heat := 0.0                   ## нагрев турбо 0…1
var _ovh_t := 0.0                  ## перегрев: турбо выключено (сек)
var _fall_t := -1.0                ## оборвались оба троса — кабина падает
var _fall_v := 0.0
var _jolt := 0.0                   ## удар: кабину крутанёт на следующем шаге
var _jolt_keep := false
var _turbo_msg_t := 0.0
var dmg := 0                       ## шаг 115: разрушено (биты SLOT_N)
var brd := 0                       ## заколочено досками (биты 0/1)
var _tool := {}                    ## pid → 0 ничего, 1 молоток, 2 сварка

# --- маршрут ---
var _dir := Vector3.FORWARD
var _side := Vector3.RIGHT
var _lab := 1.0
var _tr: Array = []
var _sj: Array = []                ## где на главном тросе развилки (м)
var _swok: Array = []              ## верная стрелка у каждой развилки (true — вправо)
var _obs: Array = []               ## препятствия: [вид, s0, s1, p1, p2]

# --- показ у всех ---
var _ds := 0.0
var _dtr := 0
var _dh := H_DOCK
var _dy := PI * 0.5
var _sw_a := 0.0
var _sw_av := 0.0
var _sw_l := 0.0
var _sw_lv := 0.0
var _pv := 0.0
var _door_k := [1.0, 0.0]
var _cabin: AnimatableBody3D
var _door_nodes: Array = []
var _door_cols: Array = []
var _carriage: Node3D
var _ropes_m: Array = []           ## шаг 113: два троса подвеса
var _hum: AudioStreamPlayer3D
var _wheels: Array = []
var _sw_lamps: Array = []          ## [развилка] → [лампа Л, лампа П]
var _gust_fx: Array = []
var _rocks: Array = []             ## камнепады: узлы камней, пыль
var _mills := {}                   ## ветряки: индекс препятствия → {ротор, ступица, бок, …}
var _rp_last := 0
var _rp_t := 0.0
var _cab_disp: Label3D
var _map_dot: Node3D
var _map_k := 1.0
var _map_mid := Vector2.ZERO
var _beacon_m: StandardMaterial3D
var _beacon_on := false
var _panels: Array = []            ## пульты: словари с узлами
var _booths: Array = []            ## [центр будки, её базис]
var _m_metal: StandardMaterial3D
var _m_paint: StandardMaterial3D
var _m_dark: StandardMaterial3D
var _m_glass: StandardMaterial3D
var _m_concrete: StandardMaterial3D
var _m_ice: StandardMaterial3D
var _m_rock: Material
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D
var _gate: Node3D
var _shadowed := false             ## строю будку: стены и крыша должны давать тень (внутри — полумрак)
var _bk := {}                      ## материал → ключ у строителя горы (склейка неподвижного)
var _lamp_state := {}              ## лампа → горит ли (менять материал только когда изменилось)

# --- пульт крупным планом (у себя) ---
var _my_panel := -1
var _ui: CanvasLayer
var _hidden: Array = []
var _hid_body: Array = []
var _prev_mouse := Input.MOUSE_MODE_CAPTURED
var _drag := ""                    ## что тянут мышью: lever / hw (лебёдка) / steer (поворот)
var _drag_a := 0.0
var _drag_g := -1
var _lever_v := 0.0
var _loc_h := H_DOCK               ## куда крутит оператор (цели лебёдки и поворота)
var _loc_y := PI * 0.5
var _tgt_dirty := false
var _send_tgt_t := 0.0
var _crank_snd := 0.0
var _glitch := 0.0
var _mon_vp: SubViewport           ## монитор пульта: камера на кабину
var _mon_cam: Camera3D
var _mon_lost := 0.0
var _mon_frame := 0
var _mon_pos := Vector3.INF
var _mon_dir := Vector3.FORWARD
var _sig_on := {}                  ## сигнал → до какого времени мигает
var _sig_last := -1
var _sig_from := ""
var _cp_set := {}
var _eject := {}                   ## pid → высота, где вылетел
var _hold := {}
# --- шаг 110: приколы, камеры монитора ---
var _turbo_t := 0.0
var _turbo_dir := 1.0
var _spin_left := 0.0
var _drop_left := 0.0
var _fun_cd := [0.0, 0.0, 0.0, 0.0]
var _drop_v := 0.0
var _fun_until := {}               ## у всех: до какого времени кнопка перезаряжается
var _swing_t := 0.0
var _disco_t := 0.0
var _dark_t := 0.0
var _announce := ""
var _announce_t := 0.0
var _bnc := 0.0                    ## кабина пружинит на тросе после сброса
var _bnc_v := 0.0
var _fx_mode := 0
var _cab_light: OmniLight3D
var _strip_m: StandardMaterial3D
var _disco_ball: Node3D
var _cam_mode := 0
var _tcov := 0.0                   ## ТУРБО: крышка (0 — закрыта, 1 — откинута)
var _tcov_tgt := 0.0
var _tcov_close_at := 0.0
var _tlev := 0.0                   ## ТУРБО: рычаг на себя
var _crank_a := 0.0                ## КАРУСЕЛЬ: угол ручки и «заряд»
var _crank_acc := 0.0
var _brk := 0.0                    ## СБРОС: рубильник вниз
var _drag_y0 := 0.0
var _prev_scale := -1.0            ## у пульта картинка в полном разрешении (надписи резкие)
var _grip := {}                    ## pid → за что держусь (шаг 110)
var _tilt := 0.0                   ## шаг 113: перекос кабины на одном тросе
var _tilt_z := 0.0
var _fall_vis := -1.0
var _xt_loc := 0.0                 ## мой ползунок турбо
var _xt_sent := -1
var _xt_send_t := 0.0
var _pcz := Vector3.ZERO           ## седоки: прошлый «нос» кабины (вращение) и ход (разгон)
var _pvr := 0.0
var _acc_s := 0.0
var _roll_on := false
var _prev_e := {}
var _fix_t := 0.0
var _fix_snd := 0.0
var _aboard := {}
var _hatch_cd := 0.0
var _roof_pin := {}
var _grad_m: StandardMaterial3D    ## шаг 114: дерево и красные ручки рычагов (атлас-градиент)
var _rock_boxes: Array = []     ## шаг 145: где стоят скалы (для глыб-украшений)
var _m_crag: Material              ## шаг 114: скалы препятствий (фототекстура cliff_side, снег сверху)
var _dress: Array = []             ## камни-сканы (rock_face_01) у очередного препятствия
var _rock_mesh: Mesh
var _slots: Array = []             ## шаг 115: борта — {"in","br","bd","col"}
var _slot_seen := -1
var _tool_vis := {}
var _e_used := {}
var _mend_t := 0.0
var _mend_ph := 0.0
var _mend_k := -1
var _weld_ph := 0.0
var _weld_bi := -1                 ## шаг 116: какое крепление сейчас варю (для показа шва)
var _beads: Array = []             ## раскалённый шов у креплений
var _jl: Array = []                ## огни развилок: [{"mm", "na", "nm"}]
var _pyl_base := {}                ## шаг 115: основание мачты у точки маршрута i (для щита развилки)
var _dmg_t := 0.0
var _blobs: Array = []             ## шаг 114: глыбы (сфера, искажённая шумом) — порода как у скал, снег сверху
var _boulder_mesh: Mesh
var _smoke: GPUParticles3D
var _smoke_t := 0.0

# --- раскладка пульта (лицевая панель, метры от центра) ---
const FACE_W := 2.6
const FACE_H := 1.35
const LEV_X := -1.13
const SPD_C := Vector2(-0.79, 0.25)
const STOP_C := Vector2(-0.79, -0.19)
const MON_C := Vector2(-0.1, 0.1)
const MON_S := Vector2(0.88, 0.54)
const HBAR_X := 0.455
const HS_X := 0.62                 ## прорезь лебёдки (Т-рукоять)
const HW_C := Vector2(0.63, 0.06)
const ST_C := Vector2(1.04, 0.06)
const WHEEL_R := 0.13
const YD_C := Vector2(1.04, 0.31)
const CAM_C := Vector2(-0.42, -0.28)
const FORK_C := Vector2(-0.08, -0.265)
const CALL_C := Vector2(0.24, -0.28)
const FUN_Y := -0.53
## Шаг 110: «приколы» с пульта (клавиши 1–7) и их перезарядка, с
const FUN_NAMES := ["ТУРБО", "КАРУСЕЛЬ", "СБРОС", "ДИСКО"]
const FUN_CD := [12.0, 10.0, 10.0, 16.0]
const TURBO_V := 20.0
const H_DROP := 22.0               ## СБРОС может опустить кабину ниже обычного предела
const FUN_COL := [Color(1.0, 0.25, 0.1), Color(0.95, 0.25, 0.85), Color(1.0, 0.85, 0.1), Color(0.4, 1.0, 0.3)]
const FUN_HOW := ["тяни вверх — быстрее", "раскрути ручку", "дёрни рубильник вниз", "щёлкни тумблер"]
const FUN_X := [-1.05, -0.43, 0.19, 0.81]
const CRANK_FULL := 4.0 * PI       ## КАРУСЕЛЬ: два оборота ручки
const CAM_NAMES := ["СЗАДИ", "СВЕРХУ", "СБОКУ", "С КРЫШИ", "В САЛОНЕ"]
const ANNOUNCE := [
	"Уважаемые пассажиры! Канатная дорога сертифицирована. Почти.",
	"Просьба не смотреть вниз. Внизу ничего интересного. Только пропасть.",
	"Напоминаем: парашюты выдаются в конце маршрута.",
	"Оператор сегодня впервые за пультом. Пожелайте ему удачи!",
	"Если кабина начала падать — это так задумано. Наверное.",
	"Спасибо, что выбрали нашу канатку! Отзывы не принимаются.",
	"Внимание! Сейчас будет ветряк. Мы в него почти не врезаемся.",
	"Пожалуйста, держитесь за поручни. И друг за друга. И за надежду.",
	"Дорогие гости! Буфет закрыт. Навсегда.",
	"Говорит оператор. Я вас вижу. А вот куда еду — уже не очень.",
]



func build() -> void:
	add_to_group("part_sockets")
	_dir = M.RW_B - M.RW_A
	_dir.y = 0.0
	_lab = _dir.length()
	_dir = _dir.normalized()
	_side = Vector3(-_dir.z, 0.0, _dir.x)
	_mats()
	# главный трос: высота растёт по длине пути (серпантин не проседает, когда петляет назад)
	var pts2: Array = WP.duplicate()
	pts2.append(Vector2(_lab, 0.0))
	var acc: Array = [0.0]
	for i in range(1, pts2.size()):
		acc.append(float(acc[i - 1]) + (pts2[i] as Vector2).distance_to(pts2[i - 1] as Vector2))
	var tot: float = acc[acc.size() - 1]
	var main_pts: Array = []
	for i in pts2.size():
		var q: Vector2 = pts2[i]
		main_pts.append(_wy(q.x, q.y, float(acc[i]) / tot))
	_tr.append(_mk_track(main_pts))
	_swok.clear()
	for dd in DEAD:
		var j: int = dd[0]
		var e: Vector2 = dd[1]
		var jp: Vector3 = main_pts[j]
		var ep := _w(e.x, e.y)
		ep.y = jp.y
		_tr.append(_mk_track([jp, ep]))
		# верная стрелка: главный трос правее тупика — «вправо»
		var mo: Vector2 = (pts2[j + 1] as Vector2) - (pts2[j] as Vector2)
		var dv: Vector2 = e - (pts2[j] as Vector2)
		_swok.append(dv.cross(mo) > 0.0)
	var cv: PackedFloat32Array = _tr[0]["c"]
	_sj.clear()
	for dd2 in DEAD:
		_sj.append(cv[int(dd2[0])])
	sw = [not bool(_swok[0]), bool(_swok[1]), not bool(_swok[2])]
	_obs.clear()
	for od in OBS_DEF:
		var s0: float = cv[int(od[1])] + float(od[2])
		_obs.append([int(od[0]), s0, s0 + float(od[3]), float(od[4]), float(od[5])])
	_make_monitor()
	_build_stations()
	_build_cables()
	_build_pylons()
	_build_obstacles()
	_build_cabin()
	_ui = _make_ui()
	_gate = GATE.make(self, M.RW_A)
	doors = _platform_door(0)
	_apply_visual(0.0)


func _mats() -> void:
	_m_metal = StandardMaterial3D.new()
	_m_metal.albedo_color = Color(0.42, 0.44, 0.47)
	_m_metal.metallic = 0.8
	_m_metal.roughness = 0.38
	_m_paint = StandardMaterial3D.new()
	_m_paint.albedo_color = Color(0.82, 0.22, 0.12)
	_m_paint.metallic = 0.25
	_m_paint.roughness = 0.42
	_m_dark = StandardMaterial3D.new()
	_m_dark.albedo_color = Color(0.13, 0.14, 0.16)
	_m_dark.metallic = 0.5
	_m_dark.roughness = 0.5
	_m_glass = StandardMaterial3D.new()
	_m_glass.albedo_color = Color(0.62, 0.78, 0.92, 0.28)
	_m_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_m_glass.roughness = 0.05
	_m_glass.metallic_specular = 1.0
	_m_concrete = StandardMaterial3D.new()
	_m_concrete.albedo_color = Color(0.56, 0.56, 0.54)
	_m_concrete.roughness = 0.95
	_m_ice = StandardMaterial3D.new()
	_m_ice.albedo_color = Color(0.72, 0.88, 1.0, 0.82)
	_m_ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_m_ice.roughness = 0.12
	_m_ice.metallic_specular = 0.9
	_m_ice.rim_enabled = true
	_m_ice.rim = 0.6
	_m_ice.albedo_color = Color(0.7, 0.88, 1.0, 0.72)
	_m_ice.clearcoat_enabled = true
	_m_ice.clearcoat = 1.0
	_m_ice.clearcoat_roughness = 0.05
	_m_ice.emission_enabled = true
	_m_ice.emission = Color(0.12, 0.26, 0.38)
	_m_ice.emission_energy_multiplier = 0.6
	var sm := ShaderMaterial.new()
	sm.shader = SPIRE_SHADER
	var tm = mtn.builder.mat("rock") if mtn and mtn.get("builder") else null
	if tm is ShaderMaterial:
		for k in ["rock_tex", "rock_nrm", "snow_tex", "rock_scale", "snow_tint", "normal_strength"]:
			var vv = (tm as ShaderMaterial).get_shader_parameter(k)
			if vv != null:
				sm.set_shader_parameter(k, vv)
	_m_rock = sm
	# шаг 114: скалы препятствий — та же порода со снегом, но фототекстура скалы Poly Haven (cliff_side)
	var cg := sm.duplicate() as ShaderMaterial
	if ResourceLoader.exists(RWA + "rocks/textures/cliff_side_diff_1k.jpg"):
		cg.set_shader_parameter("rock_tex", load(RWA + "rocks/textures/cliff_side_diff_1k.jpg"))
		cg.set_shader_parameter("rock_nrm", load(RWA + "rocks/textures/cliff_side_nor_gl_1k.jpg"))
		cg.set_shader_parameter("rock_scale", 0.16)
		cg.set_shader_parameter("normal_strength", 1.6)
	_m_crag = cg
	_lamp_on = StandardMaterial3D.new()
	_lamp_on.albedo_color = Color(1.0, 0.75, 0.2)
	_lamp_on.emission_enabled = true
	_lamp_on.emission = Color(1.0, 0.65, 0.15)
	_lamp_on.emission_energy_multiplier = 3.0
	_lamp_off = StandardMaterial3D.new()
	_lamp_off.albedo_color = Color(0.25, 0.2, 0.12)
	_lamp_off.roughness = 0.3
	# шаг 108: неподвижное — склеивается строителем горы (куски по 64 м, без теней, дальнее не рисуется)
	var cab_m := StandardMaterial3D.new()
	cab_m.albedo_color = Color(0.2, 0.2, 0.22)
	cab_m.metallic = 0.9
	cab_m.roughness = 0.35
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.34, 0.42, 0.5)
	wall.roughness = 0.7
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.95, 0.78, 0.1)
	for e in [["rw_metal", _m_metal], ["rw_paint", _m_paint], ["rw_dark", _m_dark], ["rw_glass", _m_glass],
			["rw_concrete", _m_concrete], ["rw_ice", _m_ice], ["rw_rock", _m_rock], ["rw_crag", _m_crag], ["rw_cable", cab_m],
			["rw_wall", wall], ["rw_stripe", stripe], ["rw_lamp", _lamp_on]]:
		_bk[e[1]] = String(e[0])
		if mtn and mtn.get("builder"):
			mtn.builder._mats[String(e[0])] = e[1]


# ---------------------------------------------------------------------------
#  Маршрут
# ---------------------------------------------------------------------------
func _w(a: float, l: float) -> Vector3:
	var p := M.RW_A + _dir * a + _side * l
	p.y = lerpf(M.RW_A.y, M.RW_B.y, clampf(a / _lab, 0.0, 1.0)) + H_DOCK
	return p


func _mk_track(pts: Array) -> Dictionary:
	var pv := PackedVector3Array()
	var cv := PackedFloat32Array()
	var acc := 0.0
	for i in pts.size():
		var q: Vector3 = pts[i]
		if i > 0:
			var d: Vector3 = q - pv[i - 1]
			d.y = 0.0
			acc += d.length()
		pv.append(q)
		cv.append(acc)
	return {"p": pv, "c": cv, "len": acc}


func track_len(t_: int) -> float:
	return float(_tr[t_]["len"])


func _seg_i(cv: PackedFloat32Array, s_: float) -> int:
	for i in range(cv.size() - 2, -1, -1):
		if s_ >= cv[i]:
			return i
	return 0


## Точка на тросе (с провисом между опорами)
func cable_pt(t_: int, s_: float) -> Vector3:
	var T: Dictionary = _tr[t_]
	var pv: PackedVector3Array = T["p"]
	var cv: PackedFloat32Array = T["c"]
	var sc := clampf(s_, 0.0, float(T["len"]))
	var i := _seg_i(cv, sc)
	var L := cv[i + 1] - cv[i]
	var u := (sc - cv[i]) / maxf(L, 0.001)
	return pv[i].lerp(pv[i + 1], u) + Vector3.DOWN * SAG * L * 4.0 * u * (1.0 - u)


func _seg_dir(pv: PackedVector3Array, i: int) -> Vector3:
	var d := pv[i + 1] - pv[i]
	d.y = 0.0
	return d.normalized()


## Куда идёт трос (по горизонтали); у опор поворот сглажен
func tangent(t_: int, s_: float) -> Vector3:
	var T: Dictionary = _tr[t_]
	var pv: PackedVector3Array = T["p"]
	var cv: PackedFloat32Array = T["c"]
	var sc := clampf(s_, 0.0, float(T["len"]))
	var i := _seg_i(cv, sc)
	var d := _seg_dir(pv, i)
	const BL := 7.0
	if i > 0 and sc - cv[i] < BL:
		d = _seg_dir(pv, i - 1).slerp(d, 0.5 + 0.5 * (sc - cv[i]) / BL)
	elif i + 2 < pv.size() and cv[i + 1] - sc < BL:
		d = d.slerp(_seg_dir(pv, i + 1), 0.5 - 0.5 * (cv[i + 1] - sc) / BL)
	if t_ > 0 and sc < BL:
		# тупик уходит от развилки: начало — по главному тросу
		var j: int = DEAD[t_ - 1][0]
		var pm: PackedVector3Array = _tr[0]["p"]
		d = _seg_dir(pm, j - 1).slerp(d, 0.5 + 0.5 * sc / BL)
	return d.normalized()


func _lat_axis(tg: Vector3) -> Vector3:
	return Vector3(-tg.z, 0.0, tg.x)


## Пол кабины: где и как повёрнута
func cabin_xf(t_: int, s_: float, h_: float, yw: float, sa: float, sl: float) -> Transform3D:
	var c := cable_pt(t_, s_)
	var tg := tangent(t_, s_)
	var b := Basis(Vector3.UP, atan2(tg.x, tg.z) + yw)
	var rot := Basis(_lat_axis(tg), sa) * Basis(tg, sl)
	return Transform3D(rot * b, c + rot * (Vector3.DOWN * h_))


## Полуразмер кабины вдоль троса (x) и поперёк (y) при повороте yw
func _ext(yw: float) -> Vector2:
	var c := absf(cos(yw))
	var sn := absf(sin(yw))
	return Vector2(0.5 * (CL * c + CW * sn), 0.5 * (CL * sn + CW * c))


## Какое препятствие задевает кабина в этом положении (−1 — ничего). Камнепад — отдельно (_rock_at)
func _blocked(t_: int, s_: float, h_: float, yw: float) -> int:
	if t_ != 0:
		return -1
	var e := _ext(yw)
	var tm := TILT_M if ropes == 1 or ropes == 2 else 0.0
	for i in _obs.size():
		var o: Array = _obs[i]
		if s_ + e.x < float(o[1]) or s_ - e.x > float(o[2]):
			continue
		match int(o[0]):
			RIDGE:
				if h_ + tm > float(o[3]) + 0.01:
					return i
			ICE:
				if h_ - tm < float(o[3]) - 0.01:
					return i
			SLOT, CANYON:
				if e.y * 2.0 > GAP - 0.1:
					return i
			WINDOW, RGATE:
				if h_ - tm < float(o[3]) - 0.01 or h_ + tm > float(o[4]) + 0.01 or e.y * 2.0 > GAP - 0.1:
					return i
	return -1


func _in_wind(t_: int, s_: float, yw: float) -> bool:
	if t_ != 0:
		return false
	var e := _ext(yw)
	for o in _obs:
		if int(o[0]) == WIND and s_ + e.x >= float(o[1]) and s_ - e.x <= float(o[2]):
			return true
	return false


# ---------------------------------------------------------------------------
#  Постройки
# ---------------------------------------------------------------------------
func _mesh(parent: Node3D, mesh: Mesh, xf: Transform3D, mat: Material, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.lod_bias = 8.0
	parent.add_child(mi)
	mi.transform = xf
	return mi


func _bm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Цилиндр/конус. Сеткой ArrayMesh: у примитивов движок на «низкой» графике упрощает круг до восьмиугольника
func _cyl(r0: float, r1: float, h: float, seg := 12) -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = r0
	c.bottom_radius = r1
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	if seg < 14:
		return c
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, c.get_mesh_arrays())
	return am


## Неподвижное: в склейку строителя горы (если материал известен), иначе — отдельный меш
## Шаг 145–146: высокие скальные столбы/стены препятствий канатки уходили вниз на 150–260 м и обрывались
## в воздухе над тропой Пика (видно от моста и из пропасти с выступами). Теперь у всех один низ — RW_LOW
## (под «морем облаков» на 326–336 м: сверху, с канатки и плато, низ спрятан в облаках), а снизу, с тропы
## (камера ниже RW_HIDE_Y), скалы препятствий не показываются вовсе — см. _low_view().
const RW_LOW := 215.0          # шаг 148: под самым плотным слоем облаков (228 м)
const RW_HIDE_Y := 330.0
func _anchor(mesh: Mesh, xf: Transform3D, mat: Material) -> Transform3D:
	if mat != _m_rock and mat != _m_crag:
		return xf
	var ab: AABB = xf * mesh.get_aabb()
	if ab.size.y < 60.0:
		return xf
	var target := minf(RW_LOW, ab.end.y - 30.0)
	var k := (ab.end.y - target) / ab.size.y
	var top := ab.end.y
	var nb := Basis(xf.basis.x, xf.basis.y * k, xf.basis.z)
	var nx := Transform3D(nb, xf.origin)
	var top2 := (nx * mesh.get_aabb()).end.y
	nx.origin.y += top - top2
	return nx


var _low_nodes: Array = []
var _low_hidden := false
var _low_ready := false


## Камера ниже RW_HIDE_Y (на тропе, под облаками) — канатку со всеми препятствиями не рисую
func _low_view() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var y := cam.global_position.y
	var hide := y < RW_HIDE_Y - (0.0 if _low_hidden else 4.0)
	if hide == _low_hidden and _low_ready and Engine.get_process_frames() % 120 != 0:
		return
	_low_ready = true
	_low_hidden = hide
	_low_nodes.clear()
	if true:
		var pb = mtn.get("builder") if mtn else null
		if pb:
			for c in (pb as Node).get_children():
				var nm := String(c.name)
				if nm.begins_with("W_rw_"):
					_low_nodes.append(c)
		# шаг 149: снизу канатку не видно вовсе (она над облаками) — прячу весь её вид, коллизии не трогаю
		for c2 in get_children():
			if c2 is Node3D:
				_low_nodes.append(c2)
	for nd in _low_nodes:
		if is_instance_valid(nd):
			(nd as Node3D).visible = not hide


## Шаг 145: длинная скала вместо ровного бруса — неровные грани, книзу шире (как столб из ущелья).
## Верхние keep м — точно по размеру (там проходит кабина), ниже — изломы.
func _rock_prism(hx: float, hz: float, h: float, round_k: bool, sd: float, keep := 24.0) -> ArrayMesh:
	var nv := 9 if round_k else 8
	var rings := maxi(3, int(ceil(h / 9.0)) + 1)
	var pts: Array = []
	for i in rings:
		var y := h * 0.5 - h * float(i) / float(rings - 1)
		var dtop := h * 0.5 - y
		var amp := smoothstep(keep, keep + 22.0, dtop)
		var fl := amp * minf(dtop * 0.035, 7.0)
		var ox := amp * 2.2 * sin(dtop * 0.021 + sd)
		var oz := amp * 2.2 * sin(dtop * 0.017 + sd * 1.7)
		var ring: Array = []
		for k in nv:
			var a := TAU * float(k) / float(nv) + PI / float(nv)
			var px: float
			var pz: float
			if round_k:
				px = cos(a) * hx
				pz = sin(a) * hz
			else:
				# прямоугольник: углы и середины сторон
				var cs := [Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 0)]
				px = (cs[k] as Vector2).x * hx
				pz = (cs[k] as Vector2).y * hz
			var dir := Vector2(px, pz).normalized() if Vector2(px, pz).length() > 0.001 else Vector2.RIGHT
			# только наружу (уже бруса не становится — не выглядит «обломом»)
			var j := amp * (1.0 + 0.12 * minf(hx, hz)) * (0.55 + 0.3 * sin(float(i) * 2.31 + float(k) * 1.7 + sd) + 0.15 * sin(float(i) * 0.77 + float(k) * 3.1 + sd * 2.0))
			ring.append(Vector3(px + dir.x * (fl + j) + ox, y, pz + dir.y * (fl + j) + oz))
		pts.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings - 1:
		for k in nv:
			var k2 := (k + 1) % nv
			var a0: Vector3 = pts[i][k]
			var a1: Vector3 = pts[i][k2]
			var b0: Vector3 = pts[i + 1][k]
			var b1: Vector3 = pts[i + 1][k2]
			for q in [a0, b0, a1, a1, b0, b1]:
				st.set_uv(Vector2(float(k) / nv * 4.0, q.y * 0.1))
				st.add_vertex(q)
	# крышки
	for e in [[0, false], [rings - 1, true]]:
		var rg: Array = pts[int(e[0])]
		var cc := Vector3.ZERO
		for p in rg:
			cc += p
		cc /= float(nv)
		for k in nv:
			var k2 := (k + 1) % nv
			var tri := [cc, rg[k2], rg[k]] if not bool(e[1]) else [cc, rg[k], rg[k2]]
			for q in tri:
				st.set_uv(Vector2(q.x, q.z) * 0.1)
				st.add_vertex(q)
	st.generate_normals()
	return st.commit()


func _static(mesh0: Mesh, xf0: Transform3D, mat: Material) -> void:
	var mesh := mesh0
	if mat == _m_rock or mat == _m_crag:
		if mesh0 is BoxMesh and (mesh0 as BoxMesh).size.y > 60.0:
			var bs: Vector3 = (mesh0 as BoxMesh).size
			mesh = _rock_prism(bs.x * 0.5, bs.z * 0.5, bs.y, false, xf0.origin.x * 0.13 + xf0.origin.z * 0.07)
		elif mesh0 is CylinderMesh and (mesh0 as CylinderMesh).height > 60.0:
			var cm := mesh0 as CylinderMesh
			mesh = _rock_prism(cm.top_radius, cm.top_radius, cm.height, true, xf0.origin.x * 0.11 + xf0.origin.z * 0.05, 8.0)
	var xf := _anchor(mesh, xf0, mat)
	if mat == _m_rock or mat == _m_crag:
		if mesh0 is BoxMesh:
			_rock_boxes.append([xf0, (mesh0 as BoxMesh).size * 0.5, false])
		elif mesh0 is CylinderMesh:
			var cm2 := mesh0 as CylinderMesh
			_rock_boxes.append([xf0, Vector3(maxf(cm2.top_radius, cm2.bottom_radius), cm2.height * 0.5, 0.0), true])
	if mesh != mesh0:
		# шаг 145: изломанные скалы — в свою склейку (склейка строителя горы их теряла)
		if not _jag.has(mat):
			var stj := SurfaceTool.new()
			stj.begin(Mesh.PRIMITIVE_TRIANGLES)
			_jag[mat] = stj
			if _jag.size() == 1:
				_flush_jag.call_deferred()
		(_jag[mat] as SurfaceTool).append_from(mesh, 0, xf)
	elif _bk.has(mat) and mtn and mtn.get("builder") and not _shadowed:
		mtn.builder.put(mesh, xf, String(_bk[mat]))
	else:
		var mi := _mesh(self, mesh, Transform3D.IDENTITY, mat)
		mi.global_transform = xf


var _jag := {}                     ## шаг 145: материал → SurfaceTool (изломанные скалы препятствий)


func _flush_jag() -> void:
	for m in _jag:
		var mi := MeshInstance3D.new()
		mi.mesh = (_jag[m] as SurfaceTool).commit()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "RwCrags"
		add_child(mi)
	_jag.clear()


## Неподвижный блок (в мире), с коллизией или без
func _block(size: Vector3, xf: Transform3D, mat: Material, solid: bool) -> void:
	if solid:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		b.add_child(cs)
		add_child(b)
		b.global_transform = xf
	_static(_bm(size), xf, mat)


func _beam(a: Vector3, b: Vector3, r: float, mat: Material, _shadow := true) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.001:
		return
	var up := d / L
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	_static(_cyl(r, r, L, 8), Transform3D(Basis(x, up, x.cross(up)), (a + b) * 0.5), mat)


func _label(parent: Node3D, text: String, pos: Vector3, size: int, col: Color, px := 0.004, bill := true) -> Label3D:
	var lb := Label3D.new()
	lb.visibility_range_end = 140.0 if bill else 14.0
	lb.text = text
	lb.font_size = size
	lb.outline_size = maxi(4, size / 5)
	lb.modulate = col
	lb.pixel_size = px
	if bill:
		lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	parent.add_child(lb)
	lb.position = pos
	return lb


## Станции: бетонная платформа с перилами, стальной портал, большое колесо, будка с пультом
func _build_stations() -> void:
	for st in 2:
		var base: Vector3 = M.RW_A if st == 0 else M.RW_B
		var bk := -_dir if st == 0 else _dir           # платформа — за кабиной
		var yb := Basis(Vector3.UP, atan2(bk.x, bk.z))
		var pc := base + bk * (1.8 + 2.6)
		var g: float = mtn._gy(pc.x, pc.z)
		var hh := maxf(base.y - g + 2.0, 1.2)
		_block(Vector3(8.0, hh, 5.2), Transform3D(yb, pc + Vector3.DOWN * (hh * 0.5)), _m_concrete, true)
		# кромка платформы — жёлто-чёрная полоса
		_block(Vector3(8.0, 0.03, 0.25), Transform3D(yb, base + bk * 1.93 + Vector3.UP * 0.015), mtn.builder.mat("rw_stripe"), false)
		# перила справа (слева — проход к будке пульта)
		var sx := 1.0
		var a0: Vector3 = base + bk * 1.9 + _side * sx * 3.9 + Vector3.UP * 1.05
		var a1: Vector3 = base + bk * 6.8 + _side * sx * 3.9 + Vector3.UP * 1.05
		_beam(a0, a1, 0.045, _m_metal)
		for k in 4:
			var pp: Vector3 = a0.lerp(a1, k / 3.0)
			_beam(pp + Vector3.DOWN * 1.05, pp, 0.04, _m_metal)
		_block(Vector3(0.1, 1.1, 4.9), Transform3D(yb, base + bk * 4.35 + _side * sx * 3.9 + Vector3.UP * 0.55), _m_glass, true)
		# портал над причалом и колесо
		for sx2 in [-1.0, 1.0]:
			_beam(base + bk * 4.9 + _side * sx2 * 3.3, base + bk * 4.9 + _side * sx2 * 3.3 + Vector3.UP * 14.2, 0.2, _m_paint)
			_beam(base + bk * 4.9 + _side * sx2 * 3.3 + Vector3.UP * 14.2, base + _side * sx2 * 1.2 + Vector3.UP * 13.4, 0.12, _m_paint)
		_beam(base + bk * 4.9 - _side * 3.5 + Vector3.UP * 14.2, base + bk * 4.9 + _side * 3.5 + Vector3.UP * 14.2, 0.2, _m_paint)
		_block(Vector3(7.6, 0.25, 6.0), Transform3D(yb, base + bk * 4.0 + Vector3.UP * 14.6), _m_metal, false)
		var wheel := _mesh(self, _cyl(1.7, 1.7, 0.28, 24), Transform3D.IDENTITY, _m_metal)
		wheel.global_position = base + bk * 3.4 + Vector3.UP * 12.9
		_wheels.append(wheel)
		_label(self, "КАНАТНАЯ ДОРОГА\n%s" % ("Плато → Плечо" if st == 0 else "Плечо → Плато"),
			base + bk * 4.9 + Vector3.UP * 15.6, 34, Color(1.0, 0.85, 0.5))
		# будка пульта — сбоку от платформы, дверью к платформе
		var bc := base + bk * 3.6 - _side * 5.75
		var gb: float = mtn._gy(bc.x, bc.z)
		bc.y = base.y
		var bb := Basis(Vector3.UP, atan2(_side.x, _side.z))   # будка смотрит дверью к платформе (+z — к платформе)
		_build_booth(st, bc, bb, gb)


func _build_booth(st: int, c: Vector3, b: Basis, ground: float) -> void:
	var xf := Transform3D(b, c)
	_shadowed = true
	var hh := maxf(c.y - ground + 1.5, 0.8)
	_block(Vector3(3.6, hh, 3.4), xf * Transform3D(Basis.IDENTITY, Vector3(0, -hh * 0.5, 0)), _m_concrete, true)
	var wall: Material = mtn.builder.mat("rw_wall")
	# стены (дверной проём на +z — к платформе)
	_block(Vector3(3.2, 2.6, 0.12), xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.3, -1.5)), wall, true)
	for sx in [-1.0, 1.0]:
		_block(Vector3(0.12, 2.6, 3.0), xf * Transform3D(Basis.IDENTITY, Vector3(sx * 1.6, 1.3, 0)), wall, true)
		_block(Vector3(1.0, 2.6, 0.12), xf * Transform3D(Basis.IDENTITY, Vector3(sx * 1.1, 1.3, 1.5)), wall, true)
	_block(Vector3(1.2, 0.5, 0.12), xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.35, 1.5)), wall, true)
	_block(Vector3(3.6, 0.16, 3.4), xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.68, 0)), _m_paint, true)
	_block(Vector3(3.2, 0.04, 3.0), xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0)), _m_dark, false)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.88, 0.7)
	lamp.light_energy = 1.1
	lamp.omni_range = 4.5
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = 25.0
	lamp.distance_fade_length = 5.0
	add_child(lamp)
	lamp.global_position = xf * Vector3(0, 2.3, -0.4)
	_shadowed = false
	_label(self, "ПУЛЬТ КАНАТКИ", xf * Vector3(0, 3.2, 1.55), 30, Color(0.7, 0.9, 1.0))
	_booths.append([c, b])
	_panels.append(_build_console(st, xf))


# ---------------------------------------------------------------------------
#  Пульт
# ---------------------------------------------------------------------------


func _build_console(st: int, bx: Transform3D) -> Dictionary:
	var P := {}
	_static(_bm(Vector3(2.85, 0.56, 0.6)), bx * Transform3D(Basis.IDENTITY, Vector3(0, 0.28, -1.15)), _m_dark)
	var tilt := deg_to_rad(38.0)
	var fb := Basis(Vector3.RIGHT, -tilt)
	var fo: Vector3 = bx * Vector3(0, 1.02, -0.95)
	var fxf := Transform3D(bx.basis * fb, fo)
	var face := Node3D.new()
	add_child(face)
	face.global_transform = fxf
	P["face"] = face
	P["stand"] = bx * Vector3(0, 0.05, -0.05)
	P["st"] = st
	var plate := _cmat(Color(0.22, 0.26, 0.26), 0.55, 0.55)
	var mtx = load(RWA + "panel/metal_albedo.png")
	if mtx:
		plate.albedo_texture = mtx
		plate.albedo_color = Color(0.82, 0.86, 0.86)
		plate.roughness_texture = load(RWA + "panel/metal_rough.png")
		plate.roughness = 1.0
		plate.metallic = 0.65
		plate.uv1_triplanar = true
		plate.uv1_scale = Vector3(1.4, 1.4, 1.4)
	_mesh(face, _bm(Vector3(FACE_W + 0.12, FACE_H + 0.1, 0.06)), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.03)), plate)
	var wood := _cmat(Color(0.42, 0.27, 0.15), 0.6)
	for sx in [-1.0, 1.0]:
		_mesh(face, _bm(Vector3(0.05, FACE_H + 0.14, 0.12)), Transform3D(Basis.IDENTITY, Vector3(sx * (FACE_W * 0.5 + 0.085), 0, -0.01)), wood)
	_mesh(face, _bm(Vector3(FACE_W + 0.22, 0.06, 0.14)), Transform3D(Basis.IDENTITY, Vector3(0, -FACE_H * 0.5 - 0.06, 0.0)), wood)
	var trim := _cmat(Color(0.58, 0.6, 0.57), 0.3, 0.8)
	for r in [[LEV_X, 0.07, 0.26, 0.72], [SPD_C.x, 0.07, 0.36, 0.72], [MON_C.x, MON_C.y, MON_S.x + 0.1, MON_S.y + 0.1],
			[MON_C.x, -0.3, MON_S.x + 0.1, 0.17], [0.57, 0.07, 0.44, 0.72], [ST_C.x, 0.07, 0.4, 0.72]]:
		_frame_rect(face, Vector2(r[0], r[1]), Vector2(r[2], r[3]), trim)
	var white := Color(0.94, 0.95, 0.92)
	var amber := Color(1.0, 0.8, 0.35)
	var grey := Color(0.75, 0.8, 0.8)
	_pl(face, "СТАНЦИЯ «%s»" % ("ПЛАТО" if st == 0 else "ПЛЕЧО"), Vector2(0.84, -0.35), 0.032, amber)
	# --- ручка хода ---
	_mesh(face, _bm(Vector3(0.05, _gear_v(GEARS.size() - 1) - _gear_v(0) + 0.08, 0.02)), Transform3D(Basis.IDENTITY, Vector3(LEV_X, (_gear_v(0) + _gear_v(GEARS.size() - 1)) * 0.5, 0.005)), _m_dark)
	for g in GEARS.size():
		var gv := _gear_v(g)
		_pl(face, GEAR_NAMES[g], Vector2(LEV_X + 0.1, gv), 0.04, Color(1.0, 0.45, 0.35) if g < GEAR_N else (white if g == GEAR_N else Color(0.55, 1.0, 0.6)))
		_mesh(face, _bm(Vector3(0.1, 0.006, 0.006)), Transform3D(Basis.IDENTITY, Vector3(LEV_X, gv, 0.012)), trim)
	_pl(face, "ХОД", Vector2(LEV_X, 0.47), 0.044, amber)
	_pl(face, "W / S", Vector2(LEV_X, -0.33), 0.034, grey)
	var lever := Node3D.new()
	face.add_child(lever)
	lever.position = Vector3(LEV_X, _gear_v(GEAR_N), 0.0)
	var knob := _cmat(Color(0.9, 0.12, 0.08), 0.3)
	var la := _lever_asset("lev/Lever13.fbx", face, Vector3(LEV_X, (_gear_v(0) + _gear_v(GEARS.size() - 1)) * 0.5, 0.004), 0.36)
	if la.is_empty():
		_mesh(lever, _cyl(0.013, 0.013, 0.14), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.07)), _m_metal)
		var ks := SphereMesh.new()
		ks.radius = 0.045
		ks.height = 0.09
		_mesh(lever, ks, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.15)), knob)
	P["lever"] = lever
	P["lever_a"] = la
	# --- спидометр до 20 м/с: шкала через 1, красная зона, табло ---
	var sr := 0.15
	_mesh(face, _cyl(sr + 0.016, sr + 0.016, 0.02, 40), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(SPD_C.x, SPD_C.y, 0.008)), _m_metal)
	_mesh(face, _cyl(sr, sr, 0.024, 40), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(SPD_C.x, SPD_C.y, 0.01)), _cmat(Color(0.06, 0.07, 0.08), 0.5))
	var tw := _glow(Color(0.95, 0.95, 0.9), 0.4)
	var tr_ := _glow(Color(1.0, 0.15, 0.1), 0.9)
	for k in 21:
		var a := lerpf(-2.36, 2.36, k / 20.0)
		var big := k % 5 == 0
		var L := 0.03 if big else 0.016
		var rr := sr - 0.012 - L * 0.5
		_mesh(face, _bm(Vector3(0.006 if big else 0.004, L, 0.004)), Transform3D(Basis(Vector3.BACK, -a), Vector3(SPD_C.x + sin(a) * rr, SPD_C.y + cos(a) * rr, 0.024)), tr_ if k >= 15 else tw)
		if big:
			var lb := _pl(face, "%d" % k, Vector2(SPD_C.x + sin(a) * (sr - 0.06), SPD_C.y + cos(a) * (sr - 0.06)), 0.03, Color(1.0, 0.3, 0.25) if k >= 15 else white, 0.026)
			lb.outline_size = 0
	var unit := _pl(face, "м/с", Vector2(SPD_C.x, SPD_C.y - sr * 0.42), 0.024, grey, 0.026)
	unit.outline_size = 0
	var tlamp := _pl(face, "ТУРБО", Vector2(SPD_C.x, SPD_C.y + sr * 0.34), 0.026, Color(1.0, 0.25, 0.15), 0.026)
	tlamp.outline_size = 0
	tlamp.visible = false
	P["tlamp"] = tlamp
	var nd := Node3D.new()
	face.add_child(nd)
	nd.position = Vector3(SPD_C.x, SPD_C.y, 0.028)
	_mesh(nd, _bm(Vector3(0.008, sr - 0.02, 0.004)), Transform3D(Basis.IDENTITY, Vector3(0, (sr - 0.02) * 0.5 - 0.02, 0)), _glow(Color(1.0, 0.35, 0.1), 0.8))
	_mesh(nd, _cyl(0.016, 0.016, 0.01, 14), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), _m_metal)
	P["spd"] = nd
	_mesh(face, _bm(Vector3(0.24, 0.06, 0.01)), Transform3D(Basis.IDENTITY, Vector3(SPD_C.x, 0.035, 0.006)), _m_dark)
	P["spd_d"] = _pl(face, "0.0 м/с", Vector2(SPD_C.x, 0.035), 0.04, Color(0.6, 1.0, 0.7), 0.013)
	P["odo"] = _pl(face, "ПРОЙДЕНО 000 м", Vector2(SPD_C.x, -0.035), 0.026, white)
	var red := _glow(Color(0.95, 0.08, 0.05), 0.5)
	var yel := _cmat(Color(0.95, 0.8, 0.05))
	_mesh(face, _cyl(0.095, 0.095, 0.02, 24), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(STOP_C.x, STOP_C.y, 0.01)), yel)
	var stop := Node3D.new()
	face.add_child(stop)
	stop.position = Vector3(STOP_C.x, STOP_C.y, 0.0)
	if _asset("ctl/RedButton.glb", stop, Vector3(0, 0, 0.018), _face_up(), 0.165) == null:
		_mesh(stop, _cyl(0.068, 0.076, 0.05, 20), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.045)), red)
	P["stop"] = stop
	_pl(face, "СТОП (пробел)", Vector2(STOP_C.x, -0.33), 0.032, white)
	# --- монитор ---
	_mesh(face, _bm(Vector3(MON_S.x + 0.06, MON_S.y + 0.06, 0.04)), Transform3D(Basis.IDENTITY, Vector3(MON_C.x, MON_C.y, 0.015)), _m_dark)
	var scr := QuadMesh.new()
	scr.size = MON_S
	var mm := ShaderMaterial.new()
	mm.shader = MON_SHADER
	mm.set_shader_parameter("feed", _mon_vp.get_texture())
	mm.set_shader_parameter("lost", 1.0)
	_mesh(face, scr, Transform3D(Basis.IDENTITY, Vector3(MON_C.x, MON_C.y, 0.036)), mm, false)
	P["mon"] = mm
	P["osd_top"] = _pl(face, "", Vector2(MON_C.x, MON_C.y + MON_S.y * 0.5 - 0.03), 0.036, Color(0.85, 1.0, 0.85), 0.04)
	P["osd_bot"] = _pl(face, "", Vector2(MON_C.x, MON_C.y - MON_S.y * 0.5 + 0.06), 0.034, Color(0.85, 1.0, 0.85), 0.04)
	P["mon_txt"] = _pl(face, "", Vector2(MON_C.x, MON_C.y + 0.01), 0.056, Color(1.0, 0.95, 0.85), 0.042)
	P["osd_fork"] = _pl(face, "", Vector2(MON_C.x, MON_C.y + MON_S.y * 0.5 - 0.085), 0.05, Color(0.4, 1.0, 0.5), 0.045)
	# --- под монитором: камера, развилка, вызов ---
	var blu := _glow(Color(0.15, 0.45, 1.0), 0.6)
	P["cam_b"] = _button_n(face, CAM_C, blu, 0.045, "ctl/BlueButton.glb")
	_pl(face, "КАМЕРА (V)", Vector2(CAM_C.x, CAM_C.y - 0.075), 0.03, white)
	_build_fork(face, P, trim)
	var grn := _glow(Color(0.1, 0.75, 0.25), 0.3)
	P["call"] = _button_n(face, CALL_C, grn, 0.045, "ctl/GreenButton.glb")
	_pl(face, "ВЫЗОВ (C)", Vector2(CALL_C.x, CALL_C.y - 0.075), 0.03, white)
	# --- лебёдка: Т-образная рукоять в прорези (вверх — кабина выше) и шкала подвеса ---
	_pl(face, "ЛЕБЁДКА", Vector2(0.57, 0.47), 0.044, amber)
	_mesh(face, _bm(Vector3(0.2, 0.055, 0.01)), Transform3D(Basis.IDENTITY, Vector3(HS_X, 0.37, 0.006)), _m_dark)
	P["hread"] = _pl(face, "12.0 м", Vector2(HS_X, 0.37), 0.04, Color(0.6, 1.0, 0.7), 0.013)
	_mesh(face, _bm(Vector3(0.03, _h_v(H_MIN) - _h_v(H_MAX) + 0.03, 0.012)), Transform3D(Basis.IDENTITY, Vector3(HBAR_X, (_h_v(H_MIN) + _h_v(H_MAX)) * 0.5, 0.006)), _m_dark)
	for hm in [6, 9, 12, 15, 18]:
		var hv := _h_v(float(hm))
		_mesh(face, _bm(Vector3(0.045, 0.004, 0.006)), Transform3D(Basis.IDENTITY, Vector3(HBAR_X, hv, 0.014)), trim)
		if hm % 6 == 0:
			_pl(face, "%d" % hm, Vector2(HBAR_X + 0.055, hv), 0.03, grey)
	var hk := _mesh(face, _bm(Vector3(0.06, 0.025, 0.02)), Transform3D(Basis.IDENTITY, Vector3(HBAR_X, _h_v(H_DOCK), 0.018)), knob)
	P["hmark"] = hk
	# прорезь с насечками и надписями «ВЫШЕ / НИЖЕ»
	var slot_h := _h_v(H_MIN) - _h_v(H_MAX)
	_mesh(face, _bm(Vector3(0.05, slot_h + 0.06, 0.016)), Transform3D(Basis.IDENTITY, Vector3(HS_X, (_h_v(H_MIN) + _h_v(H_MAX)) * 0.5, 0.008)), trim)
	_mesh(face, _bm(Vector3(0.022, slot_h + 0.04, 0.02)), Transform3D(Basis.IDENTITY, Vector3(HS_X, (_h_v(H_MIN) + _h_v(H_MAX)) * 0.5, 0.012)), _m_dark)
	for k2 in 13:
		var yy := lerpf(_h_v(H_MIN), _h_v(H_MAX), k2 / 12.0)
		_mesh(face, _bm(Vector3(0.03 if k2 % 6 == 0 else 0.016, 0.003, 0.004)), Transform3D(Basis.IDENTITY, Vector3(HS_X + 0.045, yy, 0.012)), trim)
	_pl(face, "ВЫШЕ", Vector2(HS_X + 0.1, _h_v(H_MIN) - 0.01), 0.026, Color(0.6, 0.9, 1.0))
	_pl(face, "НИЖЕ", Vector2(HS_X + 0.1, _h_v(H_MAX) + 0.01), 0.026, Color(1.0, 0.75, 0.5))
	var hs := Node3D.new()
	face.add_child(hs)
	hs.position = Vector3(HS_X, _h_v(H_DOCK), 0.0)
	_mesh(hs, _cyl(0.012, 0.012, 0.06, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.04)), _m_metal)
	var th := _cmat(Color(0.95, 0.75, 0.1), 0.35)
	_mesh(hs, _cyl(0.02, 0.02, 0.15, 16), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0, 0.075)), th)
	for ex in [-0.075, 0.075]:
		_mesh(hs, _cyl(0.024, 0.024, 0.02, 14), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(ex, 0, 0.075)), _m_dark)
	P["hw"] = hs
	_pl(face, "тяни вверх / вниз · R / F", Vector2(0.57, -0.24), 0.026, grey)
	# --- поворот: штурвал ---
	_pl(face, "ПОВОРОТ", Vector2(ST_C.x, 0.47), 0.044, amber)
	_dial(face, YD_C, 0.075, "", [])
	_mesh(face, _bm(Vector3(0.008, 0.13, 0.004)), Transform3D(Basis.IDENTITY, Vector3(YD_C.x, YD_C.y, 0.024)), trim)
	var icon := Node3D.new()
	face.add_child(icon)
	icon.position = Vector3(YD_C.x, YD_C.y, 0.03)
	_mesh(icon, _bm(Vector3(0.045, 0.07, 0.008)), Transform3D.IDENTITY, _glow(Color(0.95, 0.4, 0.15), 0.4))
	_mesh(icon, _bm(Vector3(0.012, 0.022, 0.01)), Transform3D(Basis.IDENTITY, Vector3(0.025, 0.0, 0.002)), _lamp_on)
	P["icon"] = icon
	var stw := _wheel(face, ST_C, Color(0.36, 0.22, 0.12), 4)
	P["steer"] = stw
	_pl(face, "крути · A / D", Vector2(ST_C.x, -0.15), 0.03, grey)
	# --- сигналы из кабины ---
	var lamps2: Array = []
	for k3 in 9:
		var lx2 := -1.04 + k3 * 0.26
		lamps2.append(_mesh(face, _cyl(0.026, 0.026, 0.025, 14), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(lx2, 0.6, 0.014)), _lamp_off))
		_pl(face, "%d %s" % [k3 + 1, SIG_SHORT[k3]], Vector2(lx2, 0.545), 0.03, white)
	P["sig"] = lamps2
	# --- ряд приколов: у каждого свой механизм ---
	var hz := _cmat(Color(0.95, 0.75, 0.08), 0.5)
	var bk := _cmat(Color(0.06, 0.06, 0.06), 0.6)
	_mesh(face, _bm(Vector3(FACE_W - 0.06, 0.255, 0.006)), Transform3D(Basis.IDENTITY, Vector3(0, FUN_Y - 0.01, 0.003)), _m_dark)
	for yy2 in [FUN_Y + 0.115, FUN_Y - 0.135]:
		_mesh(face, _bm(Vector3(FACE_W - 0.06, 0.022, 0.008)), Transform3D(Basis.IDENTITY, Vector3(0, yy2, 0.006)), hz)
		for k4 in 30:
			_mesh(face, _bm(Vector3(0.012, 0.03, 0.009)), Transform3D(Basis(Vector3.BACK, 0.7), Vector3(-FACE_W * 0.5 + 0.08 + k4 * 0.084, yy2, 0.008)), bk)
	_mesh(face, _bm(Vector3(0.82, 0.04, 0.01)), Transform3D(Basis.IDENTITY, Vector3(0, FUN_Y + 0.115, 0.012)), _m_dark)
	_pl(face, "ПРИКОЛЫ ДЛЯ ТЕХ, КТО В КАБИНЕ", Vector2(0, FUN_Y + 0.115), 0.03, Color(1.0, 0.85, 0.3), 0.018)
	var leds: Array = []
	for k5 in FUN_NAMES.size():
		var c5: Vector2 = Vector2(FUN_X[k5], FUN_Y)
		var led := _mesh(face, _cyl(0.014, 0.014, 0.016, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c5.x + 0.09, FUN_Y + 0.075, 0.012)), _lamp_off)
		leds.append(led)
		_pl(face, "%s (%d)" % [FUN_NAMES[k5], k5 + 1], Vector2(c5.x + 0.12, FUN_Y + 0.02), 0.038, white, 0.012, true)
		_pl(face, FUN_HOW[k5], Vector2(c5.x + 0.12, FUN_Y - 0.035), 0.026, grey, 0.012, true)
	P["fun_led"] = leds
	_build_fun_devices(face, P, trim)
	# камера крупного плана
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = 74.0
	cam.near = 0.05
	cam.far = 30.0
	add_child(cam)
	cam.global_transform = Transform3D(fxf.basis, fxf * Vector3(0.0, -0.02, 1.95))
	P["cam"] = cam
	var pl := OmniLight3D.new()
	pl.light_color = Color(1.0, 0.95, 0.85)
	pl.light_energy = 0.9
	pl.omni_range = 3.2
	pl.distance_fade_enabled = true
	pl.distance_fade_begin = 10.0
	pl.distance_fade_length = 3.0
	add_child(pl)
	pl.global_position = fxf * Vector3(0.0, 0.6, 1.1)
	P["hum"] = SFX.loop(face, "whirr", -16.0, 6.0)
	var keep: Array = [lever, nd, stop, P["call"], P["cam_b"], P["fork_lv"], hs, stw, icon, hk]
	if not la.is_empty():
		keep.append(la["n"])
	if not (P["fork_la"] as Dictionary).is_empty():
		keep.append(P["fork_la"]["n"])
	keep.append_array(lamps2)
	keep.append_array(leds)
	keep.append_array(P["fork_lamps"])
	keep.append_array(P["fun_nodes"])
	_merge_children(face, keep)
	for gi in face.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).visibility_range_end = 12.0
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return P


func _gear_v(g: int) -> float:
	return -0.22 + g * 0.1


func _h_v(h: float) -> float:
	return lerpf(0.27, -0.15, (h - H_MIN) / (H_MAX - H_MIN))


func _frame_rect(face: Node3D, c: Vector2, sz: Vector2, mat: Material) -> void:
	for k in 4:
		var horiz := k < 2
		var sg := -1.0 if k % 2 == 0 else 1.0
		var size := Vector3(sz.x, 0.008, 0.01) if horiz else Vector3(0.008, sz.y, 0.01)
		var pos := Vector3(c.x, c.y + sg * sz.y * 0.5, 0.004) if horiz else Vector3(c.x + sg * sz.x * 0.5, c.y, 0.004)
		_mesh(face, _bm(size), Transform3D(Basis.IDENTITY, pos), mat, false)


func _dial(face: Node3D, c: Vector2, r: float, unit: String, marks: Array) -> void:
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.92, 0.9, 0.82)
	dm.roughness = 0.6
	_mesh(face, _cyl(r + 0.012, r + 0.012, 0.02, 32), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c.x, c.y, 0.008)), _m_metal)
	_mesh(face, _cyl(r, r, 0.024, 32), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c.x, c.y, 0.01)), dm)
	for i in marks.size():
		var a := lerpf(-2.3, 2.3, i / float(maxi(marks.size() - 1, 1)))
		var p := Vector3(c.x + sin(a) * r * 0.72, c.y + cos(a) * r * 0.72, 0.024)
		var lb := _label(face, String(marks[i]), p, 64, Color(0.1, 0.1, 0.1), 0.000469, false)
		lb.outline_size = 0
	if unit != "":
		var lu := _label(face, unit, Vector3(c.x, c.y - r * 0.45, 0.024), 64, Color(0.2, 0.2, 0.2), 0.000406, false)
		lu.outline_size = 0


func _needle(face: Node3D, c: Vector2, r: float) -> Node3D:
	var n := Node3D.new()
	face.add_child(n)
	n.position = Vector3(c.x, c.y, 0.026)
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(0.85, 0.1, 0.05)
	_mesh(n, _bm(Vector3(0.008, r, 0.004)), Transform3D(Basis.IDENTITY, Vector3(0, r * 0.5, 0)), nm)
	_mesh(n, _cyl(0.012, 0.012, 0.008, 12), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), _m_dark)
	return n


func _button(face: Node3D, c: Vector2, col: Color) -> Node3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.4
	_mesh(face, _cyl(0.05, 0.05, 0.015, 18), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c.x, c.y, 0.008)), _m_metal)
	var n := Node3D.new()
	face.add_child(n)
	n.position = Vector3(c.x, c.y, 0.0)
	_mesh(n, _cyl(0.038, 0.04, 0.03, 18), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.025)), m)
	return n


# ---------------------------------------------------------------------------
#  Тросы, опоры, препятствия
# ---------------------------------------------------------------------------
func _build_cables() -> void:
	var cab_m: Material = mtn.builder.mat("rw_cable") if mtn and mtn.get("builder") else _m_dark
	for t_ in _tr.size():
		var L := track_len(t_)
		var n := int(ceil(L / 6.0))
		var prev := cable_pt(t_, 0.0)
		for i in range(1, n + 1):
			var p := cable_pt(t_, L * i / n)
			_beam(prev, p, 0.045, cab_m, false)
			prev = p
	# у станций трос уходит на колесо
	for st in 2:
		var base: Vector3 = M.RW_A if st == 0 else M.RW_B
		var bk := -_dir if st == 0 else _dir
		_beam(base + Vector3.UP * H_DOCK, base + bk * 3.4 + Vector3.UP * 12.9 + _side * 1.6, 0.045, cab_m, false)


func _build_pylons() -> void:
	var pv: PackedVector3Array = _tr[0]["p"]
	for i in range(1, pv.size() - 1):
		var top := pv[i]
		var d0 := _seg_dir(pv, i - 1)
		var d1 := _seg_dir(pv, i)
		# мачта — в сторону, где нет тросов (снаружи поворота, мимо тупика)
		var avoid: Array = [-d0, d1]
		for dd in DEAD:
			if int(dd[0]) == i:
				var e: Vector2 = dd[1]
				var dv := _w(e.x, e.y) - top
				dv.y = 0.0
				avoid.append(dv.normalized())
		var best := Vector3.RIGHT
		var bs := -2.0
		for k in 24:
			var cand := Vector3(cos(TAU * k / 24.0), 0.0, sin(TAU * k / 24.0))
			var mn := 9.0
			for av in avoid:
				mn = minf(mn, 1.0 - cand.dot(av as Vector3))
			if mn > bs:
				bs = mn
				best = cand
		var base := top + best * 8.0
		_pyl_base[i] = base
		var tb := Vector3(base.x, top.y - 16.0, base.z)
		_spire(tb + Vector3.DOWN * 1.0, 3.6, 260.0)
		# решётчатая мачта
		var tt := Vector3(base.x, top.y + 2.6, base.z)
		for k2 in 4:
			var o := Vector3(0.7 if k2 % 2 == 0 else -0.7, 0.0, 0.7 if k2 < 2 else -0.7)
			_beam(tb + o * 1.6, tt + o * 0.6, 0.09, _m_paint)
		for lv in 5:
			var y0 := lerpf(tb.y, tt.y, lv / 5.0)
			var y1 := lerpf(tb.y, tt.y, (lv + 1) / 5.0)
			var w0 := lerpf(1.6, 0.6, lv / 5.0) * 0.7
			var w1 := lerpf(1.6, 0.6, (lv + 1) / 5.0) * 0.7
			_beam(Vector3(base.x - w0, y0, base.z + w0), Vector3(base.x + w1, y1, base.z + w1), 0.04, _m_metal, false)
			_beam(Vector3(base.x - w0, y0, base.z - w0), Vector3(base.x + w1, y1, base.z - w1), 0.04, _m_metal, false)
		# консоль к тросу и седло
		var saddle := top + Vector3.UP * 0.35
		_beam(tt, Vector3(saddle.x, tt.y, saddle.z), 0.16, _m_paint)
		_beam(Vector3(saddle.x, tt.y, saddle.z), saddle, 0.1, _m_paint)
		var bis := (d0 + d1).normalized()
		_block(Vector3(0.5, 0.3, 1.8), Transform3D(Basis(Vector3.UP, atan2(bis.x, bis.z)), saddle), _m_metal, false)
		_static(_cyl(0.18, 0.18, 0.3, 8), Transform3D(Basis.IDENTITY, tt + Vector3.UP * 0.5), _lamp_on)
		# развилка: табло стрелки — видно из кабины, что подъезжает
		for j in DEAD.size():
			if int(DEAD[j][0]) != i:
				continue
			var board := tt + Vector3.UP * 1.6
			var bb := Basis(Vector3.UP, atan2(-d0.x, -d0.z))
			_block(Vector3(2.4, 1.3, 0.12), Transform3D(bb, board), _m_dark, false)
			_label(self, "СТРЕЛКА %d" % (j + 1), board + Vector3.UP * 1.05, 40, Color(1.0, 0.85, 0.3))
			var ls: Array = []
			for k3 in 2:
				var lm := _mesh(self, SphereMesh.new(), Transform3D.IDENTITY, _lamp_off)
				(lm.mesh as SphereMesh).radius = 0.32
				(lm.mesh as SphereMesh).height = 0.64
				lm.global_transform = Transform3D(Basis.IDENTITY, board + bb * Vector3((k3 * 2 - 1) * 0.6, 0.05, 0.15))
				ls.append(lm)
				_label(self, "ЛЕВО" if k3 == 0 else "ПРАВО", board + bb * Vector3((k3 * 2 - 1) * 0.6, -0.5, 0.2), 26, Color(0.9, 0.9, 0.9))
			_sw_lamps.append(ls)
	# тупики: сломанная опора, буфер, табличка
	for j2 in DEAD.size():
		var L := track_len(j2 + 1)
		var end := cable_pt(j2 + 1, L)
		var tg := tangent(j2 + 1, L)
		var tb2 := end + Vector3.DOWN * 16.0 + _lat_axis(tg) * 5.0
		_spire(tb2 + Vector3.DOWN * 1.0, 3.2, 260.0)
		_beam(tb2, tb2 + Vector3(0.6, 9.0, 0.4), 0.12, _m_paint)
		_beam(tb2 + Vector3(0.6, 9.0, 0.4), tb2 + Vector3(2.6, 7.5, -1.2), 0.1, _m_paint)
		_block(Vector3(1.0, 0.9, 0.7), Transform3D(Basis(Vector3.UP, atan2(tg.x, tg.z)), end + Vector3.DOWN * 0.3), mtn.builder.mat("rw_stripe"), false)
		_label(self, "ТУПИК\nтрос оборван", end + Vector3.DOWN * 3.0, 44, Color(1.0, 0.35, 0.25))


## Скала-столб из пропасти (шейдер выступов): вершина в top
func _spire(top: Vector3, r: float, depth: float) -> void:
	# шаг 129: столб не должен торчать сквозь мост над пропастью
	var chn = mtn.get("chasm") if mtn else null
	if chn and chn.get("_a") != null:
		var a2 := Vector2((chn._a as Vector3).x, (chn._a as Vector3).z)
		var b2 := Vector2((chn._b as Vector3).x, (chn._b as Vector3).z)
		var t2 := Vector2(top.x, top.z)
		var ab := b2 - a2
		var q := a2 + ab * clampf((t2 - a2).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if q.distance_to(t2) < r * 1.5 + 6.0 and top.y - depth < maxf((chn._a as Vector3).y, (chn._b as Vector3).y) + 10.0:
			return
	_static(_cyl(r * 0.8, r * 1.5, depth, 9), Transform3D(Basis(Vector3.UP, top.x * 0.37), top + Vector3.DOWN * depth * 0.5), _m_rock)


## Шаг 114: первый меш из ассета (с его материалом)
func _first_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(RWA + path):
		return null
	var ps = load(RWA + path)
	if not (ps is PackedScene):
		return null
	var n: Node = (ps as PackedScene).instantiate()
	var mi: MeshInstance3D = n.find_child("*", true, false) as MeshInstance3D
	if mi == null:
		for m in n.find_children("*", "MeshInstance3D", true, false):
			mi = m
			break
	var mesh: Mesh = mi.mesh if mi else null
	n.free()
	return mesh


## Камень-скан в точке p размером sz — если не лезет в коридор кабины (вдоль троса: вбок ±3.6 м, по высоте от −20 м до троса)
func _dress_at(p: Vector3, sz: float, fr: Array, rng: RandomNumberGenerator) -> void:
	if _blobs.is_empty():
		return
	# шаг 145: глыба только НА скале (у верха столба/стены) — не висит в воздухе и не «прилипает» к отвесу
	var held := false
	var rr := sz * 0.45
	for e in _rock_boxes:
		var q: Vector3 = (e[0] as Transform3D).affine_inverse() * p
		var hx: Vector3 = e[1]
		if bool(e[2]):
			if Vector2(q.x, q.z).length() < hx.x + rr * 0.5 and q.y > hx.y - 2.5 and q.y < hx.y + rr:
				held = true
				break
		elif absf(q.x) < hx.x + rr * 0.5 and absf(q.z) < hx.z + rr * 0.5 and q.y > hx.y - 2.5 and q.y < hx.y + rr:
			held = true
			break
	if not held:
		rng.randf()
		rng.randf()
		rng.randf()
		rng.randf()
		rng.randi()
		return
	var c: Vector3 = fr[0]
	var lat: Vector3 = fr[2]
	var lo := (p - c).dot(lat)
	var r := sz * 0.62
	if absf(lo) < 3.6 + r and p.y > c.y - 20.5 - r and p.y < c.y + 1.4 + r:
		return
	var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)) * Basis.from_scale(Vector3(sz, sz * rng.randf_range(0.6, 1.1), sz * rng.randf_range(0.8, 1.2)))
	_dress.append([rng.randi() % _blobs.size(), Transform3D(b, p)])


## Глыба: сфера, искажённая шумом, приплюснутая, с плоским низом (размер ~1 м)
func _blob_mesh(seed_: int) -> ArrayMesh:
	var sp := SphereMesh.new()
	sp.radius = 0.5
	sp.height = 1.0
	sp.radial_segments = 16
	sp.rings = 9
	var arr := sp.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nz := FastNoiseLite.new()
	nz.seed = seed_
	nz.frequency = 1.0
	for i in vs.size():
		var d := vs[i].normalized()
		var k := 1.0 + 0.42 * nz.get_noise_3dv(d * 1.3) + 0.14 * nz.get_noise_3dv(d * 3.7 + Vector3(5, 1, 2))
		var q := d * 0.5 * k
		q.y *= 0.78
		if q.y < -0.18:
			q.y = -0.18 + (q.y + 0.18) * 0.25
		vs[i] = q
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_normals()
	return st.commit()


## Обставить препятствие камнями-сканами (снаружи коридора кабины) и выпустить их одним мультимешем
func _dress_obstacle(kind: int, fr: Array, s0: float, s1: float, p1: float, p2: float, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = fr[0]
	var tg: Vector3 = fr[1]
	var lat: Vector3 = fr[2]
	var half := (s1 - s0) * 0.5
	_dress.clear()
	match kind:
		RIDGE:
			for sx in [-1.0, 1.0]:
				for k in 5:
					var l: float = sx * rng.randf_range(6.0, 15.0)
					var p: Vector3 = c + lat * l + tg * rng.randf_range(-half - 2.0, half + 2.0)
					p.y = c.y - p1 + absf(l) * 0.45 - rng.randf_range(0.5, 2.5)
					_dress_at(p, rng.randf_range(2.5, 4.5), fr, rng)
		ICE:
			for k in 9:
				var p: Vector3 = c + lat * rng.randf_range(-12.0, 12.0) + tg * rng.randf_range(-half, half)
				p.y = c.y + 5.6 + rng.randf_range(-0.3, 0.6)
				_dress_at(p, rng.randf_range(3.0, 5.0), fr, rng)
		SLOT:
			for sx in [-1.0, 1.0]:
				for k in 3:
					var p: Vector3 = c + lat * sx * rng.randf_range(6.0, 9.0) + tg * rng.randf_range(-half - 3.0, half + 3.0)
					p.y = c.y + rng.randf_range(1.0, 4.0)
					_dress_at(p, rng.randf_range(2.5, 4.0), fr, rng)
		WIND:
			for sx in [-1.0, 1.0]:
				var n := int((s1 - s0) / 4.5)
				for k in n:
					var al := lerpf(-half - 1.0, half + 1.0, (k + rng.randf()) / float(n))
					var p: Vector3 = c + lat * sx * rng.randf_range(7.6, 9.5) + tg * al
					p.y = c.y + 4.3 + rng.randf_range(-0.4, 0.8)
					_dress_at(p, rng.randf_range(3.8, 6.5), fr, rng)
					var q: Vector3 = c + lat * sx * rng.randf_range(7.0, 7.6) + tg * (al + rng.randf_range(-1.5, 1.5))
					q.y = c.y - rng.randf_range(0.0, 30.0)
					_dress_at(q, rng.randf_range(3.0, 5.0), fr, rng)
		WINDOW:
			for sx in [-1.0, 1.0]:
				for k in 7:
					var p: Vector3 = c + lat * sx * rng.randf_range(2.5, 22.0) + tg * rng.randf_range(-half, half)
					p.y = c.y + 7.4 + rng.randf_range(-0.3, 0.7)
					_dress_at(p, rng.randf_range(4.0, 7.5), fr, rng)
				for k2 in 10:
					var fz: float = (1.0 if k2 % 2 == 0 else -1.0) * (half + rng.randf_range(0.2, 0.9))
					var p2_: Vector3 = c + lat * sx * rng.randf_range(5.0, 22.0) + tg * fz
					p2_.y = c.y + rng.randf_range(-30.0, 5.0)
					_dress_at(p2_, rng.randf_range(3.5, 6.0), fr, rng)
		CANYON:
			for sx in [-1.0, 1.0]:
				var n2 := int((s1 - s0) / 3.5)
				for k in n2:
					var al2 := lerpf(-half, half, (k + rng.randf()) / float(n2))
					var p: Vector3 = c + lat * sx * rng.randf_range(2.6, 6.0) + tg * al2
					p.y = c.y + 7.3 + rng.randf_range(-0.2, 0.9)
					_dress_at(p, rng.randf_range(2.2, 3.8), fr, rng)
			_canyon_cliffs(c, tg, lat, half)
		RGATE:
			for sx in [-1.0, 1.0]:
				var p: Vector3 = c + lat * sx * rng.randf_range(2.6, 3.4)
				p.y = c.y + 7.6
				_dress_at(p, rng.randf_range(2.0, 2.8), fr, rng)
		ROCK:
			var side := float((_rocks.back() as Dictionary)["side"]) if not _rocks.is_empty() else 1.0
			for k in 16:
				var p: Vector3 = c + lat * side * rng.randf_range(7.4, 8.4) + tg * rng.randf_range(-half - 7.0, half + 7.0)
				p.y = c.y + rng.randf_range(-30.0, 22.0)
				_dress_at(p, rng.randf_range(3.2, 6.0), fr, rng)
			for k2 in 6:
				var p3: Vector3 = c + lat * side * rng.randf_range(3.0, 10.0) + tg * rng.randf_range(-half - 3.0, half + 3.0)
				p3.y = c.y + 26.2 + rng.randf_range(-0.2, 0.6)
				_dress_at(p3, rng.randf_range(2.5, 4.0), fr, rng)
		MILL:
			for k in 5:
				var a := rng.randf() * TAU
				var mi: Dictionary = _mills.values().back() if not _mills.is_empty() else {}
				if mi.is_empty():
					break
				var hb: Vector3 = mi["hub"]
				var p: Vector3 = hb + tg * 3.4 + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(2.5, 3.5) + Vector3.DOWN * rng.randf_range(2.5, 4.5)
				_dress_at(p, rng.randf_range(2.0, 3.0), fr, rng)
	for bv in _blobs.size():
		var xs: Array = []
		for e in _dress:
			if int(e[0]) == bv:
				xs.append(e[1])
		if xs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _blobs[bv]
		mm.instance_count = xs.size()
		for k3 in xs.size():
			mm.set_instance_transform(k3, xs[k3])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _m_crag
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 420.0
		add_child(mmi)
	_dress.clear()


## Каньон: за стенами — настоящие береговые утёсы (скан coastal_cliff_01), вытянутые вдоль троса
func _canyon_cliffs(c: Vector3, tg: Vector3, lat: Vector3, half: float) -> void:
	var cm := _first_mesh("rocks/coastal_cliff_01_1k.gltf")
	if cm == null:
		return
	var bb := cm.get_aabb()
	for sx in [-1.0, 1.0]:
		# меш: длина по x, высота по y, «лицо» к −z
		var kx := (half * 2.0 + 16.0) / bb.size.x
		var ky := 3.2
		var kz := 1.6
		var b := Basis(tg * sx, Vector3.UP, lat * sx) * Basis.from_scale(Vector3(kx, ky, kz))
		var p: Vector3 = c + lat * sx * (GAP * 0.5 + 4.2 + bb.size.z * kz * 0.5)
		p.y = c.y + 10.0 - bb.size.y * ky
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		add_child(mi)
		mi.global_transform = Transform3D(b, p - b * Vector3(bb.get_center().x, bb.position.y, bb.get_center().z))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 450.0


## Шаг 114: сосулька — рифлёная, сужается книзу, чуть изогнута (высота 1, ось y, центр посередине)
func _icicle_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEG := 7
	const RINGS := 9
	var ring: Array = []
	for j in RINGS + 1:
		var t := j / float(RINGS)
		var y := 0.5 - t
		var r := 0.32 * pow(1.0 - t, 0.85) * (1.0 + 0.14 * sin(t * 23.0)) + (0.0 if j < RINGS else 0.0)
		var bend := Vector2(0.05 * t * t, 0.03 * t * t)
		var pts: Array = []
		for k in SEG:
			var a := TAU * k / float(SEG)
			pts.append(Vector3(cos(a) * r + bend.x, y, sin(a) * r + bend.y))
		ring.append(pts)
	for j2 in RINGS:
		for k2 in SEG:
			var a0: Vector3 = ring[j2][k2]
			var a1: Vector3 = ring[j2][(k2 + 1) % SEG]
			var b0: Vector3 = ring[j2 + 1][k2]
			var b1: Vector3 = ring[j2 + 1][(k2 + 1) % SEG]
			for q in [b0, b1, a1, b0, a1, a0]:
				var nq := Vector3(q.x, 0.0, q.z).normalized()
				st.set_normal(nq if nq != Vector3.ZERO else Vector3.DOWN)
				st.add_vertex(q)
	return st.commit()


func _obs_frame(s_: float) -> Array:
	var c := cable_pt(0, s_)
	var tg := tangent(0, s_)
	return [c, tg, _lat_axis(tg)]


func _build_obstacles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1091
	var rock_keep: Material = _m_rock
	_m_rock = _m_crag                  # шаг 114: всё скальное у препятствий — фотопорода
	_rock_mesh = null
	_blobs.clear()
	for bs in 3:
		_blobs.append(_blob_mesh(31 + bs * 17))
	_boulder_mesh = _first_mesh("rocks/boulder_01_1k.gltf")
	var drng := RandomNumberGenerator.new()
	drng.seed = 7114
	var rock_m := StandardMaterial3D.new()
	rock_m.albedo_color = Color(0.36, 0.33, 0.31)
	rock_m.roughness = 0.95
	for i in _obs.size():
		var o: Array = _obs[i]
		var s0: float = o[1]
		var s1: float = o[2]
		var p1: float = o[3]
		var p2: float = o[4]
		var half := (s1 - s0) * 0.5
		var sm := (s0 + s1) * 0.5
		var fr := _obs_frame(sm)
		var c: Vector3 = fr[0]
		var tg: Vector3 = fr[1]
		var lat: Vector3 = fr[2]
		var yb := Basis(Vector3.UP, atan2(tg.x, tg.z))
		match int(o[0]):
			RIDGE:
				# гребень: посередине — ниже (проходит только поднятая кабина), по краям — выше
				for k in 11:
					var l := (k - 5) * 2.8 + rng.randf_range(-0.5, 0.5)
					var r := rng.randf_range(2.0, 2.8)
					var lim := maxf(half - r * 0.85, 0.0)
					var along := rng.randf_range(-lim, lim)
					var top := c.y - p1 - 0.45 + (0.0 if absf(l) < 5.5 else absf(l) * 0.55)
					var p := c + lat * l + tg * along
					p.y = top
					_spire(p, r, 220.0)
			ICE:
				# каменная арка над тросом, с неё — частокол сосулек; посередине узкая щель для подвеса
				for sx in [-1.0, 1.0]:
					_spire(c + lat * sx * 10.0 + Vector3.UP * 6.0, 3.0, 240.0)
				_block(Vector3(24.0, 3.0, s1 - s0 - 1.0), Transform3D(yb, c + Vector3.UP * 3.9), _m_rock, false)
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = _icicle_mesh()
				var xs: Array = []
				for k in 170:
					var l2 := rng.randf_range(-10.0, 10.0)
					if absf(l2) < 0.45:
						continue
					var a2 := rng.randf_range(-(half - 0.5), half - 0.5)
					var tip := c.y - p1 + CTOP + 0.08 - (rng.randf_range(0.0, 1.5) if absf(l2) > 3.2 else 0.0) + (rng.randf_range(0.0, 3.5) if absf(l2) > 5.0 else 0.0)
					var top2 := c.y + 2.4
					var L2 := top2 - tip
					var w := rng.randf_range(0.6, 1.3)
					xs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(w, L2, w)), c + lat * l2 + tg * a2 + Vector3.UP * (tip + L2 * 0.5 - c.y)))
				mm.instance_count = xs.size()
				for k2 in xs.size():
					mm.set_instance_transform(k2, xs[k2])
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.material_override = _m_ice
				add_child(mmi)
			SLOT:
				# два ледяных столба: между ними щель GAP — пролезет только кабина ровно вдоль троса
				for sx2 in [-1.0, 1.0]:
					# шаг 114: гроздь шестигранных ледяных колонн (внутренний край — ровно по щели)
					for kc in 7:
						var rc := rng.randf_range(0.55, 1.05)
						var lo := GAP * 0.5 + rc + 0.06 + (0.0 if kc < 3 else rng.randf_range(0.4, 1.6))
						var al := lerpf(-(half - rc), half - rc, kc / 6.0) if kc < 3 else rng.randf_range(-half, half)
						if kc < 3:
							al = lerpf(-(half - rc), half - rc, kc / 2.0)
						var topc := c.y + rng.randf_range(2.5, 9.0)
						var hc := topc - (c.y - 26.0)        # шаг 145: не висят до дна — стоят на скальной полке
						var pcc: Vector3 = c + lat * sx2 * lo + tg * al
						pcc.y = topc - hc * 0.5
						_static(_cyl(rc, rc * 1.08, hc, 6), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pcc), _m_ice)
						var tip: Vector3 = c + lat * sx2 * lo + tg * al
						tip.y = topc + rc * 0.45
						_static(_cyl(0.0, rc, rc * 0.9, 6), Transform3D(Basis.IDENTITY, tip), _m_ice)
					_spire(c + lat * sx2 * (GAP * 0.5 + 4.6) + Vector3.UP * 3.0, 3.0, 240.0)
					# шаг 145: полка под ледяными колоннами — выступ от скального столба
					var shelf: Vector3 = c + lat * sx2 * (GAP * 0.5 + 3.4)
					shelf.y = c.y - 26.0 - 2.5
					_static(_bm(Vector3(6.4, 5.0, half * 2.0 + 2.0)), Transform3D(yb, shelf), _m_rock)
			WIND:
				# ущелье: скальные стены по бокам, в порыв — снежные струи поперёк
				for sx3 in [-1.0, 1.0]:
					var wc: Vector3 = c + lat * sx3 * 9.0
					wc.y = c.y + 4.0 - 120.0
					_static(_bm(Vector3(3.0, 240.0, s1 - s0 + 4.0)), Transform3D(yb, wc), _m_rock)
				for k3 in 3:
					var fx := FX.particles(Color(0.92, 0.95, 1.0, 0.55), 160, 1.6, 0.5, 14.0, 22.0, Vector3.ZERO, 8.0, false)
					var pm := fx.process_material as ParticleProcessMaterial
					pm.direction = Vector3(1, 0, 0)
					pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
					pm.emission_box_extents = Vector3(0.5, 7.0, (s1 - s0) * 0.16)
					fx.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
					add_child(fx)
					var fc := cable_pt(0, lerpf(s0, s1, (k3 + 0.5) / 3.0))
					var tg3 := tangent(0, lerpf(s0, s1, (k3 + 0.5) / 3.0))
					fx.global_transform = Transform3D(Basis(Vector3.UP, atan2(tg3.x, tg3.z) + PI * 0.5), fc - _lat_axis(tg3) * 7.5 + Vector3.DOWN * 12.0)
					_gust_fx.append(fx)
			WINDOW:
				# скальная стена поперёк троса: щель для подвеса сверху и окно для кабины
				var th := s1 - s0
				var wy0 := c.y - p2 - 0.4                  # низ окна (дно кабины при длинном подвесе)
				var wy1 := c.y - p1 + CTOP + 0.1           # верх окна (лебёдка при коротком)
				var top3 := c.y + 7.0
				var bot := c.y - 200.0
				for sx4 in [-1.0, 1.0]:
					var wcx: Vector3 = c + lat * sx4 * (GAP * 0.5 + 11.0)
					wcx.y = (top3 + bot) * 0.5
					_static(_bm(Vector3(22.0, top3 - bot, th)), Transform3D(yb, wcx), _m_rock)
					var u1: Vector3 = c + lat * sx4 * (GAP * 0.25 + 0.2)
					u1.y = (top3 + wy1) * 0.5
					_static(_bm(Vector3(GAP * 0.5 - 0.4, top3 - wy1, th)), Transform3D(yb, u1), _m_rock)
				var lo := c
				lo.y = (wy0 + bot) * 0.5
				_static(_bm(Vector3(GAP, wy0 - bot, th)), Transform3D(yb, lo), _m_rock)
			MILL:
				_build_mill(i, c, tg, lat)
			CANYON:
				# узкий каньон: скальные стены вплотную — кабина только вдоль; по пути ворота с окнами на разной высоте
				for sx5 in [-1.0, 1.0]:
					var cw: Vector3 = c + lat * sx5 * (GAP * 0.5 + 2.0)
					cw.y = c.y + 7.0 - 80.0
					_static(_bm(Vector3(4.0, 160.0, s1 - s0)), Transform3D(yb, cw), _m_rock)
					for k5 in 6:
						var sp5: Vector3 = c + lat * sx5 * (GAP * 0.5 + rng.randf_range(3.5, 6.0)) + tg * rng.randf_range(-half + 2.0, half - 2.0)
						sp5.y = c.y + rng.randf_range(8.0, 16.0)
						_spire(sp5, rng.randf_range(2.0, 3.2), 40.0)
				_label(self, "КАНЬОН\nтолько вдоль троса!", c - tg * (half + 1.0) + lat * (GAP * 0.5 + 0.2) + Vector3.UP * 2.0, 40, Color(1.0, 0.6, 0.2))
			RGATE:
				# скальные ворота поперёк каньона: окно на своей высоте (рыжие метки по краям — видно в камеру)
				var th6 := s1 - s0
				var wy0 := c.y - p2 - 0.4
				var wy1 := c.y - p1 + CTOP + 0.1
				var top6 := c.y + 7.0
				var lo6 := c
				lo6.y = (wy0 + c.y - 160.0) * 0.5
				_static(_bm(Vector3(GAP + 1.0, wy0 - (c.y - 160.0), th6)), Transform3D(yb, lo6), _m_rock)
				for sx6 in [-1.0, 1.0]:
					var u6: Vector3 = c + lat * sx6 * (GAP * 0.25 + 0.2)
					u6.y = (top6 + wy1) * 0.5
					_static(_bm(Vector3(GAP * 0.5 - 0.4 + 0.5, top6 - wy1, th6)), Transform3D(yb, u6 + lat * sx6 * 0.25), _m_rock)
				var mark: Material = mtn.builder.mat("rw_stripe")
				for yy in [wy0, wy1]:
					var mk6: Vector3 = c - tg * (th6 * 0.5 + 0.03)
					mk6.y = yy
					_static(_bm(Vector3(GAP, 0.14, 0.06)), Transform3D(yb, mk6), mark)
			ROCK:
				# утёс с козырьком над тросом: раз в 10 с с него сыплются камни (перед этим — гул и струйки щебня)
				var side := 1.0 if _rocks.size() % 2 == 0 else -1.0
				var wc2: Vector3 = c + lat * side * 11.0
				wc2.y = c.y - 45.0
				_static(_bm(Vector3(6.0, 150.0, s1 - s0 + 16.0)), Transform3D(yb, wc2), _m_rock)
				var ov: Vector3 = c + lat * side * 6.5
				ov.y = c.y + 24.0
				_static(_bm(Vector3(9.0, 4.0, s1 - s0 + 8.0)), Transform3D(yb, ov), _m_rock)
				_spire(c + lat * side * 9.0 + Vector3.UP * 34.0, 3.5, 30.0)
				_spire(c - lat * side * 11.0 + Vector3.UP * 2.0, 3.0, 220.0)
				var rk := Node3D.new()
				add_child(rk)
				var bl: Array = []
				for k4 in 7:
					var rr := rng.randf_range(0.6, 1.15)
					var bm: Node3D
					if _boulder_mesh:
						# шаг 114: валун-скан (центр меша — в центре узла, чтобы кувыркался вокруг себя)
						bm = Node3D.new()
						rk.add_child(bm)
						var bmi := MeshInstance3D.new()
						bmi.mesh = _boulder_mesh
						var bb := _boulder_mesh.get_aabb()
						var kb := rr * 2.0 / maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
						bmi.transform = Transform3D(Basis.from_scale(Vector3.ONE * kb), -bb.get_center() * kb)
						bm.add_child(bmi)
					else:
						var sp := SphereMesh.new()
						sp.radius = rr
						sp.height = rr * 1.7
						sp.radial_segments = 7
						sp.rings = 4
						bm = _mesh(rk, sp, Transform3D.IDENTITY, rock_m)
					bm.visible = false
					bl.append(bm)
				var warn := FX.particles(Color(0.5, 0.46, 0.42, 0.9), 50, 2.4, 0.18, 0.2, 1.5, Vector3(0, -16, 0), 25.0, false)
				var wpm := warn.process_material as ParticleProcessMaterial
				wpm.direction = Vector3.DOWN
				wpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
				wpm.emission_box_extents = Vector3(1.0, 0.2, half)
				warn.visibility_aabb = AABB(Vector3(-15, -60, -15), Vector3(30, 70, 30))
				add_child(warn)
				warn.global_transform = Transform3D(yb, c + lat * side * 2.5 + Vector3.UP * 21.8)
				var dust := FX.particles(Color(0.72, 0.68, 0.62, 0.42), 70, 2.6, 1.8, 1.5, 6.0, Vector3(0, -0.6, 0), 180.0, true)
				var dpm := dust.process_material as ParticleProcessMaterial
				dpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
				dpm.emission_box_extents = Vector3(2.0, 3.0, half + 1.0)
				dust.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
				add_child(dust)
				dust.global_transform = Transform3D(yb, c + Vector3.DOWN * 9.0)
				_rocks.append({"c": c, "tg": tg, "lat": lat, "side": side, "half": half, "b": bl, "warn": warn, "dust": dust,
					"seed": rng.randf_range(0.0, 10.0)})
		_dress_obstacle(int(o[0]), fr, s0, s1, p1, p2, drng)
	_m_rock = rock_keep
	_build_jlights()


# ---------------------------------------------------------------------------
#  Кабина
# ---------------------------------------------------------------------------
func _build_cabin() -> void:
	_cabin = AnimatableBody3D.new()
	_cabin.name = "Gondola"
	_cabin.sync_to_physics = true
	_cabin.add_to_group("safe_ground")
	add_child(_cabin)
	var body := _cmat(Color(0.8, 0.2, 0.1), 0.3, 0.35)
	body.clearcoat_enabled = true
	body.clearcoat = 0.7
	var cream := _cmat(Color(0.95, 0.91, 0.82), 0.4)
	var roof := _cmat(Color(0.18, 0.2, 0.23), 0.45, 0.5)
	var chrome := _cmat(Color(0.82, 0.84, 0.86), 0.18, 0.95)
	var panel := _cmat(Color(0.86, 0.8, 0.68), 0.75)
	var ceil_m := _cmat(Color(0.93, 0.9, 0.84), 0.8)
	var wood1 := _cmat(Color(0.47, 0.31, 0.18), 0.65)
	var wood2 := _cmat(Color(0.39, 0.25, 0.14), 0.7)
	var fabric := _cmat(Color(0.12, 0.36, 0.38), 0.95)
	var yellow := _cmat(Color(0.95, 0.75, 0.15), 0.4)
	var glass := _m_glass.duplicate() as StandardMaterial3D
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var fglass := _cmat(Color(0.55, 0.8, 0.95, 0.22), 0.05)
	fglass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fglass.metallic_specular = 1.0
	var strip := _glow(Color(1.0, 0.9, 0.72), 2.2)
	var head := _glow(Color(1.0, 0.92, 0.7), 3.5)
	var hw := CW * 0.5
	var hl := CL * 0.5
	# --- снаружи: красный низ с юбкой, кремовый пояс, панорамное стекло, тёмная крыша ---
	_mesh(_cabin, _hull_mesh([[-0.38, 0.24], [-0.22, 0.07], [0.0, 0.0], [WIN_Y.x, 0.0], [0.86, 0.0]], true, false), Transform3D.IDENTITY, body)
	_mesh(_cabin, _hull_mesh([[0.86, -0.02], [0.98, -0.02]], true, false), Transform3D.IDENTITY, cream)
	_mesh(_cabin, _hull_mesh([[0.98, -0.005], [1.04, -0.005]], true, false), Transform3D.IDENTITY, _m_dark)
	_mesh(_cabin, _hull_mesh([[1.04, 0.0], [2.28, 0.0]], true, false), Transform3D.IDENTITY, glass, false)
	_mesh(_cabin, _hull_mesh([[2.28, -0.01], [2.42, -0.01]], true, false), Transform3D.IDENTITY, cream)
	_mesh(_cabin, _hull_mesh([[2.42, -0.01], [2.62, 0.12], [2.8, 0.34]], false, false, 1), Transform3D.IDENTITY, roof)
	# дно: плита вокруг «колодца» стеклянного пола
	var bw := hw - 0.26
	var bl := hl - 0.26
	const GX := 0.5
	const GZ := 0.75
	_cbox(Vector3(bw - GX, 0.04, bl * 2.0), Vector3((bw + GX) * 0.5, -0.38, 0), _m_dark, false)
	_cbox(Vector3(bw - GX, 0.04, bl * 2.0), Vector3(-(bw + GX) * 0.5, -0.38, 0), _m_dark, false)
	_cbox(Vector3(GX * 2.0, 0.04, bl - GZ), Vector3(0, -0.38, (bl + GZ) * 0.5), _m_dark, false)
	_cbox(Vector3(GX * 2.0, 0.04, bl - GZ), Vector3(0, -0.38, -(bl + GZ) * 0.5), _m_dark, false)
	for sx in [-1.0, 1.0]:
		_cbox(Vector3(0.03, 0.38, GZ * 2.0), Vector3(sx * GX, -0.19, 0), _m_dark, false)
		_cbox(Vector3(GX * 2.0, 0.38, 0.03), Vector3(0, -0.19, sx * GZ), _m_dark, false)
	# фары на торцах, номер и надпись на бортах
	for sz in [-1.0, 1.0]:
		for fx in [-1.0, 1.0]:
			_mesh(_cabin, _cyl(0.13, 0.13, 0.05, 16), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(fx * 1.05, 0.52, sz * (hl + 0.01))), chrome)
			_mesh(_cabin, _cyl(0.1, 0.1, 0.06, 16), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(fx * 1.05, 0.52, sz * (hl + 0.02))), head)
		_mesh(_cabin, _bm(Vector3(1.3, 0.06, 0.04)), Transform3D(Basis.IDENTITY, Vector3(0, 0.25, sz * (hl + 0.01))), chrome)
	for sx2 in [-1.0, 1.0]:
		var lb := _label(_cabin, "КАНАТКА  № 7", Vector3(sx2 * (hw + 0.012), 0.3, -sx2 * 1.42), 40, Color(0.98, 0.94, 0.84), 0.0045, false)
		lb.rotation.y = sx2 * PI * 0.5
		lb.outline_size = 0
		lb.double_sided = false
	# --- рамы: стойки у дверей, в углах, на торцах; перемычки над дверями ---
	for sx3 in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			_cbox(Vector3(0.08, 2.44, 0.08), Vector3(sx3 * (hw - 0.035), 1.22, sz2 * (DOOR_HZ + 0.04)), _m_dark, false)
			var a := atan2(sz2, sx3)
			var cp := Vector3(sx3 * (hw - CR), 0, sz2 * (hl - CR)) + Vector3(cos(a), 0, sin(a)) * (CR - 0.02)
			_mesh(_cabin, _bm(Vector3(0.07, 1.26, 0.07)), Transform3D(Basis(Vector3.UP, -a), cp + Vector3.UP * 1.66), _m_dark)
			_cbox(Vector3(0.06, 1.26, 0.05), Vector3(sx3 * 0.62, 1.66, sz2 * (hl - 0.02)), _m_dark, false)
		_cbox(Vector3(0.08, 0.12, DOOR_HZ * 2.0 + 0.16), Vector3(sx3 * (hw - 0.035), 2.36, 0), _m_dark, false)
	# --- салон: обшивка, подоконник, потолок со световыми полосами ---
	_mesh(_cabin, _hull_mesh([[0.0, 0.07], [WIN_Y.x, 0.07], [0.98, 0.07]], true, true), Transform3D.IDENTITY, panel)
	_mesh(_cabin, _hull_mesh([[0.98, 0.07], [0.98, -0.005]], true, true), Transform3D.IDENTITY, wood1)
	_mesh(_cabin, _hull_mesh([[2.28, 0.04], [2.42, 0.1], [2.5, 0.3]], false, true, 1), Transform3D.IDENTITY, ceil_m)
	for sx4 in [-1.0, 1.0]:
		_cbox(Vector3(0.12, 0.03, CL - 1.4), Vector3(sx4 * 0.72, 2.485, 0), strip, false)
	# пол: доски в два тона, посередине — стеклянное окно в пропасть
	var nst := 16
	for k in nst:
		var x0 := -hw + 0.07 + (CW - 0.14) * k / float(nst)
		var x1 := -hw + 0.07 + (CW - 0.14) * (k + 1) / float(nst)
		var xc := (x0 + x1) * 0.5
		var zmax := hl - 0.07
		var ax := absf(xc) - (hw - CR)
		if ax > 0.0:
			zmax = hl - CR + sqrt(maxf(CR * CR - ax * ax, 0.0)) - 0.09
		var wm: Material = wood1 if k % 2 == 0 else wood2
		if absf(xc) < GX:
			for sz3 in [-1.0, 1.0]:
				var za := GZ + 0.02
				_cbox(Vector3(x1 - x0 - 0.008, 0.05, zmax - za), Vector3(xc, -0.025, sz3 * (za + zmax) * 0.5), wm, false)
		else:
			_cbox(Vector3(x1 - x0 - 0.008, 0.05, zmax * 2.0), Vector3(xc, -0.025, 0), wm, false)
	_ccol(Vector3(CW - 0.1, 0.24, CL - 0.1), Vector3(0, -0.12, 0))
	# стеклянное окно в полу и хромированная рамка
	_mesh(_cabin, _bm(Vector3(GX * 2.0, 0.02, GZ * 2.0)), Transform3D(Basis.IDENTITY, Vector3(0, -0.012, 0)), fglass, false)
	for sx5 in [-1.0, 1.0]:
		_cbox(Vector3(0.04, 0.02, GZ * 2.0 + 0.08), Vector3(sx5 * (GX + 0.02), 0.002, 0), chrome, false)
		_cbox(Vector3(GX * 2.0 + 0.08, 0.02, 0.04), Vector3(0, 0.002, sx5 * (GZ + 0.02)), chrome, false)
	# стены — коллизия (стекло тоже твёрдое)
	const WH := CHT - 0.25
	for sx6 in [-1.0, 1.0]:
		var wx: float = sx6 * (hw - 0.05)
		for sz4 in [-1.0, 1.0]:
			if true:
				var wz := (WIN_Z.x + WIN_Z.y) * 0.5
				var wl := WIN_Z.y - WIN_Z.x
				_ccol(Vector3(0.12, WH, WIN_Z.x - DOOR_HZ), Vector3(wx, WH * 0.5, sz4 * (DOOR_HZ + WIN_Z.x) * 0.5))
				_ccol(Vector3(0.12, WIN_Y.x, wl), Vector3(wx, WIN_Y.x * 0.5, sz4 * wz))
				_ccol(Vector3(0.12, WH - WIN_Y.y, wl), Vector3(wx, (WH + WIN_Y.y) * 0.5, sz4 * wz))
				_ccol(Vector3(0.12, WH, hl - WIN_Z.y), Vector3(wx, WH * 0.5, sz4 * (WIN_Z.y + hl) * 0.5))
		_ccol(Vector3(CW, WH, 0.12), Vector3(0, WH * 0.5, sx6 * (hl - 0.05)))
	# крыша: плоская часть (края скатом — с них соскальзывают)
	_ccol(Vector3(CW - 0.36, 0.2, CL - 0.36), Vector3(0, CHT - 0.05, 0))
	# шаг 113: открытые окна — рама, жёлтый подоконник, табличка
	for sxw in [-1.0, 1.0]:
		var wzc: float = sxw * (WIN_Z.x + WIN_Z.y) * 0.5
		var wln := WIN_Z.y - WIN_Z.x
		var wxx: float = sxw * (hw - 0.04)
		_cbox(Vector3(0.18, 0.05, wln), Vector3(wxx, WIN_Y.x, wzc), yellow, false)
		for kst in 5:
			_cbox(Vector3(0.185, 0.052, 0.07), Vector3(wxx, WIN_Y.x, wzc - wln * 0.4 + kst * wln * 0.2), _m_dark, false)
		_cbox(Vector3(0.14, 0.07, wln + 0.08), Vector3(wxx, WIN_Y.y, wzc), _m_dark, false)
		for ez2 in [-1.0, 1.0]:
			_cbox(Vector3(0.13, WIN_Y.y - WIN_Y.x, 0.07), Vector3(wxx, (WIN_Y.x + WIN_Y.y) * 0.5, wzc + ez2 * wln * 0.5), _m_dark, false)
		var wl2 := _label(_cabin, "ОКНО ОТКРЫТО!\nНЕ ВЫСОВЫВАТЬСЯ", Vector3(sxw * (hw - 0.08), 0.28, wzc), 26, Color(1.0, 0.3, 0.2), 0.0035, false)
		wl2.rotation.y = -sxw * PI * 0.5
		wl2.double_sided = false
	# шаг 115: глухие половины бортов — отдельные куски (целый / выбитый / заколоченный); рама вокруг
	_slots.clear()
	for k8 in 2:
		var sx9: float = 1.0 if k8 == 0 else -1.0
		var zc9: float = -sx9 * (WIN_Z.x + WIN_Z.y) * 0.5
		var wl9 := WIN_Z.y - WIN_Z.x
		var wx9: float = sx9 * (hw - 0.04)
		_cbox(Vector3(0.14, 0.07, wl9 + 0.08), Vector3(wx9, WIN_Y.y, zc9), _m_dark, false)
		_cbox(Vector3(0.16, 0.04, wl9), Vector3(wx9, WIN_Y.x, zc9), _m_dark, false)
		for ez9 in [-1.0, 1.0]:
			_cbox(Vector3(0.13, WIN_Y.y - WIN_Y.x, 0.07), Vector3(wx9, (WIN_Y.x + WIN_Y.y) * 0.5, zc9 + ez9 * wl9 * 0.5), _m_dark, false)
		_slots.append(_build_slot(sx9, zc9, wl9, body, cream, panel, wood1, glass))
	# шаг 116: молоток — на красном щитке у передней жёлтой стойки (лицом в салон)
	var hb := Node3D.new()
	_cabin.add_child(hb)
	hb.position = HAMMER_AT
	hb.rotation.y = PI
	var redb := _cmat(Color(0.78, 0.12, 0.08), 0.5)
	_mesh(hb, _bm(Vector3(0.34, 0.56, 0.03)), Transform3D.IDENTITY, redb)
	_mesh(hb, _bm(Vector3(0.36, 0.04, 0.035)), Transform3D(Basis.IDENTITY, Vector3(0, 0.29, 0)), _m_dark)
	for hk in [-1.0, 1.0]:
		_mesh(hb, _bm(Vector3(0.06, 0.03, 0.08)), Transform3D(Basis.IDENTITY, Vector3(0, 0.14 * hk, 0.04)), chrome)
	var th1 := _hammer_tool()
	hb.add_child(th1)
	th1.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3.ONE * 1.3), Vector3(0, -0.2, 0.07))
	var hbl := _label(hb, "МОЛОТОК — E", Vector3(0, -0.24, 0.02), 24, Color(1.0, 0.95, 0.8), 0.0032, false)
	hbl.double_sided = false
	_mesh(hb, _cyl(0.04, 0.04, 0.1, 10), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.03)), chrome)
	# шаг 116: сварка — в жёлтом ящике на крыше, рядом с люком
	var wb := Node3D.new()
	_cabin.add_child(wb)
	wb.position = WELD_BOX
	_mesh(wb, _bm(Vector3(0.56, 0.26, 0.36)), Transform3D(Basis.IDENTITY, Vector3(0, 0.13, 0)), yellow)
	_mesh(wb, _bm(Vector3(0.58, 0.03, 0.38)), Transform3D(Basis.IDENTITY, Vector3(0, 0.27, 0)), _m_dark)
	var th2 := _torch_tool()
	wb.add_child(th2)
	th2.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.1, 0.31, 0.0))
	var bot2 := _cyl(0.08, 0.08, 0.36, 12)
	_mesh(wb, bot2, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.05, 0.38, -0.08)), _cmat(Color(0.2, 0.35, 0.75), 0.4))
	var wbl := _label(wb, "СВАРКА — E", Vector3(0, 0.14, 0.185), 26, Color(0.1, 0.08, 0.05), 0.0032, false)
	wbl.double_sided = false
	# люк в потолке (у жёлтой стойки) и на крыше — откинутая крышка
	_cbox(Vector3(0.82, 0.03, 0.76), Vector3(HATCH.x, HATCH.y - 0.02, HATCH.z), yellow, false)
	_cbox(Vector3(0.7, 0.035, 0.64), Vector3(HATCH.x, HATCH.y - 0.03, HATCH.z), _m_dark, false)
	_cbox(Vector3(0.86, 0.08, 0.8), Vector3(HATCH.x, CHT + 0.07, HATCH.z), yellow, false)
	_cbox(Vector3(0.7, 0.085, 0.64), Vector3(HATCH.x, CHT + 0.075, HATCH.z), _m_dark, false)
	_mesh(_cabin, _bm(Vector3(0.7, 0.64, 0.04)), Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(HATCH.x, CHT + 0.42, HATCH.z + 0.43)), roof)
	var hl3 := _label(_cabin, "ЛЮК НА КРЫШУ\nподпрыгни под ним", Vector3(HATCH.x, 2.28, HATCH.z + 0.42), 26, Color(1.0, 0.85, 0.3), 0.0035, false)
	hl3.double_sided = false
	# крепления двух тросов подвеса на крыше
	for ak in 2:
		var ap: Vector3 = ANCH[ak]
		# шаг 115: крепление на стойке — сварщику на колене как раз у груди
		_cbox(Vector3(0.34, 0.06, 0.26), Vector3(ap.x, CHT + 0.07, ap.z), yellow, false)
		_cbox(Vector3(0.1, ap.y - CHT - 0.05, 0.1), Vector3(ap.x, (ap.y + CHT) * 0.5, ap.z), yellow, false)
		for bz in [-1.0, 1.0]:
			_mesh(_cabin, _bm(Vector3(0.05, 0.5, 0.05)), Transform3D(Basis(Vector3.RIGHT, bz * 0.5), Vector3(ap.x, CHT + 0.25, ap.z + bz * 0.11)), _m_dark)
		_cbox(Vector3(0.16, 0.08, 0.14), Vector3(ap.x, ap.y - 0.02, ap.z), _m_dark, false)
		_mesh(_cabin, _cyl(0.06, 0.06, 0.1, 12), Transform3D(Basis(Vector3.BACK, PI * 0.5), ap + Vector3.UP * 0.04), chrome)
	# лавки у торцов: мягкие сиденья и спинки, хромированные ножки (по три места)
	for sz5 in [-1.0, 1.0]:
		var zs: float = sz5 * (hl - 0.4)
		_cbox(Vector3(2.4, 0.12, 0.5), Vector3(0, 0.46, zs), fabric, true)
		_cbox(Vector3(2.44, 0.05, 0.54), Vector3(0, 0.38, zs), wood2, false)
		var back := Basis(Vector3.RIGHT, sz5 * 0.12)
		_mesh(_cabin, _bm(Vector3(2.4, 0.46, 0.1)), Transform3D(back, Vector3(0, 0.78, sz5 * (hl - 0.16))), fabric)
		for k2 in 2:
			_mesh(_cabin, _bm(Vector3(0.6, 0.38, 0.105)), Transform3D(back, Vector3(-0.4 + k2 * 0.8, 0.78, sz5 * (hl - 0.155))), wood2)
		for lx in [-1.05, 0.0, 1.05]:
			_cbar(Vector3(lx, 0.0, zs - 0.18 * sz5), Vector3(lx, 0.37, zs - 0.18 * sz5), chrome, 0.022)
	# поручни: вдоль бортов (за них держатся — E), стойки в середине, потолочные с петлями
	for sx7 in [-1.0, 1.0]:
		var rx: float = sx7 * (hw - 0.17)
		var rs: float = -sx7               # поручень — на глухой половине борта (на другой — открытое окно)
		_cbar(Vector3(rx, 1.05, rs * (hl - 0.7)), Vector3(rx, 1.05, rs * 0.75), chrome, 0.025)
		for zz in [rs * (hl - 0.7), rs * 0.75]:
			_cbar(Vector3(rx, 1.05, zz), Vector3(sx7 * (hw - 0.07), 1.05, zz), chrome, 0.018)
		var ox: float = sx7 * 0.78
		_cbar(Vector3(ox, 2.1, -1.75), Vector3(ox, 2.1, 1.75), chrome, 0.022)
		for zz2 in [-1.75, 1.75]:
			_cbar(Vector3(ox, 2.1, zz2), Vector3(ox, 2.48, zz2), chrome, 0.018)
		for k3 in 7:
			var zl2 := -1.35 + k3 * 0.45
			_cbox(Vector3(0.03, 0.16, 0.012), Vector3(ox, 2.0, zl2), _m_dark, false)
			var tor := TorusMesh.new()
			tor.inner_radius = 0.045
			tor.outer_radius = 0.062
			tor.rings = 12
			tor.ring_segments = 6
			_mesh(_cabin, tor, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(ox, 1.88, zl2)), yellow)
	for sz6 in [-1.0, 1.0]:
		_cbar(Vector3(0, 0.0, sz6 * 1.25), Vector3(0, 2.5, sz6 * 1.25), yellow, 0.03)
	# щиток сигналов (под потолком у одного торца) — кнопки 1–9
	var sigp := Node3D.new()
	_cabin.add_child(sigp)
	sigp.position = Vector3(0.0, 2.02, hl - 0.38)
	sigp.rotation = Vector3(0.22, PI, 0.0)
	_mesh(sigp, _bm(Vector3(1.6, 0.44, 0.05)), Transform3D.IDENTITY, _m_dark)
	_mesh(sigp, _bm(Vector3(1.66, 0.5, 0.03)), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.03)), chrome)
	_cbar(Vector3(-0.6, 2.2, hl - 0.4), Vector3(-0.6, 2.48, hl - 0.4), chrome, 0.015)
	_cbar(Vector3(0.6, 2.2, hl - 0.4), Vector3(0.6, 2.48, hl - 0.4), chrome, 0.015)
	for k4 in 9:
		var lm := _mesh(sigp, _cyl(0.045, 0.045, 0.03, 14), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.68 + k4 * 0.17, 0.07, 0.03)), _lamp_on)
		lm.name = "Btn%d" % k4
		var lb2 := _label(sigp, "%d\n%s" % [k4 + 1, SIG_SHORT[k4]], Vector3(-0.68 + k4 * 0.17, -0.1, 0.03), 22, Color.WHITE, 0.0008, false)
		lb2.name = "Lbl%d" % k4
	_label(sigp, "СИГНАЛЫ ОПЕРАТОРУ — клавиши 1…9", Vector3(0, 0.27, 0.03), 22, Color(1.0, 0.85, 0.4), 0.0008, false)
	# схема маршрута с огоньком кабины (под потолком у другого торца)
	_build_map(Vector3(0.0, 1.98, -hl + 0.42))
	# свет в салоне
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.62)
	lamp.light_energy = 1.0
	lamp.omni_range = 5.0
	lamp.position = Vector3(0, CHT - 0.45, 0)
	_cabin.add_child(lamp)
	_cab_light = lamp
	_strip_m = strip
	# зеркальный шар — для дискотеки
	_disco_ball = Node3D.new()
	_cabin.add_child(_disco_ball)
	_disco_ball.position = Vector3(0, 2.3, 0)
	var dball := SphereMesh.new()
	dball.radius = 0.13
	dball.height = 0.26
	dball.radial_segments = 10
	dball.rings = 6
	var dbm := _cmat(Color(0.9, 0.9, 0.95), 0.05, 1.0)
	dbm.emission_enabled = true
	dbm.emission = Color(0.5, 0.5, 0.6)
	_mesh(_disco_ball, dball, Transform3D.IDENTITY, dbm, false)
	_disco_ball.visible = false
	# крыша: лебёдка с барабаном, жёлто-чёрный кожух, антенна камеры с мигалкой
	_cbox(Vector3(1.1, 0.34, 1.5), Vector3(0, 2.97, 0), roof, true)
	_cbox(Vector3(1.14, 0.08, 1.54), Vector3(0, 2.84, 0), yellow, false)
	_mesh(_cabin, _cyl(0.17, 0.17, 0.9, 16), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 3.05, 0)), chrome)
	_cbar(Vector3(0.95, 2.8, -1.7), Vector3(0.95, 3.6, -1.7), chrome, 0.018)
	_cbox(Vector3(0.18, 0.12, 0.12), Vector3(0.95, 3.12, -1.7), _m_dark, false)
	_beacon_m = _glow(Color(1.0, 0.15, 0.1), 0.2)
	var bs := SphereMesh.new()
	bs.radius = 0.06
	bs.height = 0.12
	var beacon := _mesh(_cabin, bs, Transform3D(Basis.IDENTITY, Vector3(0.95, 3.64, -1.7)), _beacon_m)
	# двери (едут вбок по борту): внизу красная, сверху стекло в раме
	_door_nodes.clear()
	_door_cols.clear()
	for sx8 in [1.0, -1.0]:
		var door := Node3D.new()
		_cabin.add_child(door)
		door.position = Vector3(sx8 * (hw + 0.035), 0, 0)
		var dw := DOOR_HZ * 2.0 + 0.06
		_mesh(door, _bm(Vector3(0.05, 0.98, dw)), Transform3D(Basis.IDENTITY, Vector3(0, 0.49, 0)), body)
		_mesh(door, _bm(Vector3(0.06, 0.12, dw)), Transform3D(Basis.IDENTITY, Vector3(0, 0.92, 0)), cream)
		_mesh(door, _bm(Vector3(0.012, 0.96, dw - 0.04)), Transform3D(Basis.IDENTITY, Vector3(-sx8 * 0.032, 0.49, 0)), panel)
		var dg := _mesh(door, _bm(Vector3(0.03, 1.28, dw - 0.1)), Transform3D(Basis.IDENTITY, Vector3(0, 1.64, 0)), glass, false)
		dg.name = "Glass"
		_mesh(door, _bm(Vector3(0.06, 0.06, dw)), Transform3D(Basis.IDENTITY, Vector3(0, 2.3, 0)), _m_dark)
		for ez in [-1.0, 1.0]:
			_mesh(door, _bm(Vector3(0.06, 1.34, 0.05)), Transform3D(Basis.IDENTITY, Vector3(0, 1.64, ez * (dw * 0.5 - 0.025))), _m_dark)
		_mesh(door, _bm(Vector3(0.04, 0.4, 0.03)), Transform3D(Basis.IDENTITY, Vector3(sx8 * 0.04, 1.1, dw * 0.5 - 0.12)), chrome)
		_door_nodes.append(door)
		var dc := CollisionShape3D.new()
		var dbs := BoxShape3D.new()
		dbs.size = Vector3(0.12, 2.4, dw)
		dc.shape = dbs
		dc.position = Vector3(sx8 * (hw - 0.02), 1.2, 0)
		_cabin.add_child(dc)
		_door_cols.append(dc)
	# по мешу на материал (двери, огонёк схемы и мигалка — отдельно: они двигаются/мигают)
	var keep9: Array = _door_nodes + [_map_dot, beacon, _disco_ball, hb, wb]
	for sl9 in _slots:
		keep9.append_array([sl9["in"], sl9["br"], sl9["bd"]])
	_merge_children(_cabin, keep9)
	for sl8 in _slots:
		_merge_children(sl8["in"] as Node3D, [])
		_merge_children(sl8["br"] as Node3D, [])
	for dn in _door_nodes:
		_merge_children(dn as Node3D, [])
	for lb3 in _cabin.find_children("*", "Label3D", true, false):
		(lb3 as Label3D).visibility_range_end = 16.0
	lamp.distance_fade_enabled = true
	lamp.distance_fade_begin = 70.0
	lamp.distance_fade_length = 10.0
	# тележка на тросе и трос подвеса (отдельно — двигаются сами)
	_carriage = Node3D.new()
	add_child(_carriage)
	_mesh(_carriage, _bm(Vector3(0.55, 0.5, 1.9)), Transform3D(Basis.IDENTITY, Vector3(0, -0.15, 0)), _m_paint)
	for wz in [-0.65, 0.65]:
		_mesh(_carriage, _cyl(0.24, 0.24, 0.12, 16), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.12, wz)), _m_dark)
	_mesh(_carriage, _cyl(0.22, 0.22, 0.6, 16), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, -0.47, 0)), _m_metal)
	_mesh(_carriage, _cyl(0.1, 0.1, 0.12, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -0.3, 0.98)), _lamp_on, false)
	_merge_children(_carriage, [])
	_ropes_m.clear()
	for rk in 2:
		_ropes_m.append(_mesh(self, _cyl(0.035, 0.035, 1.0, 8), Transform3D.IDENTITY, _m_dark, false))
	_smoke = FX.particles(Color(0.3, 0.3, 0.32, 0.55), 40, 1.8, 0.45, 0.6, 1.8, Vector3(0, 1.2, 0), 30.0, false)
	_carriage.add_child(_smoke)
	_smoke.position = Vector3(0, 0.3, 0)
	_hum = SFX.loop(_carriage, "whirr", -10.0, 45.0)


## Склеить неподвижные меши под root (кроме keep и того, что внутри них) — по одному на материал
func _merge_children(root: Node3D, keep: Array) -> void:
	var groups := {}
	var mats := {}
	var victims: Array = []
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var skip := false
		var q: Node = mi
		while q != null and q != root:
			if keep.has(q):
				skip = true
				break
			q = q.get_parent()
		if skip or mi.mesh == null or mi.material_override == null:
			continue
		var m: Material = mi.material_override
		var k := m.get_instance_id()
		if not groups.has(k):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[k] = st
			mats[k] = m
		var rel := inv * mi.global_transform if root.is_inside_tree() else _rel_xf(root, mi)
		(groups[k] as SurfaceTool).append_from(mi.mesh, 0, rel)
		victims.append(mi)
	for v2 in victims:
		(v2 as Node).get_parent().remove_child(v2)
		(v2 as Node).queue_free()
	for k2 in groups:
		var mi2 := MeshInstance3D.new()
		mi2.mesh = (groups[k2] as SurfaceTool).commit()
		mi2.material_override = mats[k2]
		root.add_child(mi2)


func _rel_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var q: Node = n
	while q != null and q != root:
		xf = (q as Node3D).transform * xf
		q = q.get_parent()
	return xf


func _cbox(size: Vector3, pos: Vector3, mat: Material, solid: bool) -> void:
	_mesh(_cabin, _bm(size), Transform3D(Basis.IDENTITY, pos), mat)
	if solid:
		_ccol(size, pos)


func _ccol(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	_cabin.add_child(cs)


func _cbar(a: Vector3, b: Vector3, mat: Material = null, r := 0.025) -> void:
	var d := b - a
	var L := d.length()
	var up := d / L
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	_mesh(_cabin, _cyl(r, r, L, 8), Transform3D(Basis(x, up, x.cross(up)), (a + b) * 0.5), mat if mat else _m_metal)


func in_cabin(p: Vector3) -> bool:
	if _cabin == null:
		return false
	var l := _cabin.global_transform.affine_inverse() * p
	if absf(l.x) < CW * 0.5 and absf(l.z) < CL * 0.5 and l.y > -0.4 and l.y < CHT:
		return true
	for b in _booths:
		var bl: Vector3 = (b[1] as Basis).inverse() * (p - (b[0] as Vector3))
		if absf(bl.x) < 1.6 and absf(bl.z) < 1.5 and bl.y > -0.5 and bl.y < 2.7:
			return true
	return false


func _in_gondola(p: Vector3) -> bool:
	var l := _cabin.global_transform.affine_inverse() * p
	return absf(l.x) < CW * 0.5 + 0.1 and absf(l.z) < CL * 0.5 + 0.1 and l.y > -0.5 and l.y < CHT + 2.0


## Бот/игрок едет в кабине (для ботов: не бежать за хозяином с обрыва)
func riding(p: Vector3) -> bool:
	return _cabin != null and _in_gondola(p)


func niche_taken() -> bool:
	return true


# ---------------------------------------------------------------------------
#  Хост: движение, удары, ветер, автоматика, боты
# ---------------------------------------------------------------------------
func server(delta: float) -> void:
	_riders = 0
	var bot_in := false
	for d in get_tree().get_nodes_in_group("player"):
		if bool(d.get("is_dead")):
			continue
		if _in_gondola(d.global_position):
			_riders += 1
			if bool(d.get("is_bot")):
				bot_in = true
	# шаг 115: пустую кабину на станции чинят станционные — новые листы, двери и тросы
	if docked >= 0 and _riders == 0 and (dmg != 0 or brd != 0 or (ropes != 3 and ropes != 0)):
		for k in SLOT_N:
			if (dmg & (1 << k)) != 0:
				_rpc_all("_ev_dmg", [1, k])
		dmg = 0
		brd = 0
		for b2 in [1, 2]:
			if (ropes & b2) == 0 and ropes != 0:
				ropes |= b2
				_rpc_all("_ev_rope", [1, b2])
	# оператор ушёл от пульта / погиб
	if op_pid >= 0:
		var od: Node3D = mtn.drone_by_id(op_pid)
		var P: Dictionary = _panels[op_panel]
		if od == null or bool(od.get("is_dead")) or od.global_position.distance_to(P["stand"]) > 2.6:
			_rpc_all("_set_op", [-1, -1])
	_horn_cd = maxf(_horn_cd - delta, 0.0)
	_srv_fun_tick(delta)
	_srv_gust(delta)
	_srv_bots(delta, bot_in)
	_srv_auto()
	_srv_move(delta)
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 0.05
		if mtn._online():
			_st.rpc(tr, s, v, H, yaw, gear, sw[0], sw[1], sw[2], docked, doors, gust_ph, rock_ph, hits, auto_to, _clk, Vector3(_xtra, _heat, _ovh_t), ropes, dmg | (brd << 8))


func _srv_gust(delta: float) -> void:
	_gust_t += delta
	var ph := fposmod(_gust_t, 10.0)
	gust_ph = 0 if ph < 6.0 else (1 if ph < 7.6 else 2)
	_rock_t += delta
	_clk += delta
	var rc := _rock_c()
	rock_ph = 0 if rc < float(ROCK_T[0]) else (1 if rc < float(ROCK_T[1]) else 2)


func _srv_move(delta: float) -> void:
	_scrape_t = maxf(_scrape_t - delta, 0.0)
	if ropes == 0:
		_srv_fall(delta)
		return
	_srv_turbo(delta)
	if _hit_t > 0.0:
		_hit_t -= delta
		if _hit_t <= 0.0 and docked < 0:
			doors = 0
	if docked >= 0 and gear != GEAR_N:
		# у Плато под выходом — край тропы: на отправлении лебёдка сама подтягивает кабину повыше
		var lift := docked == 0 and gear > GEAR_N
		docked = -1
		doors = 0
		_close_t = 1.2
		if lift:
			_h_tgt = 9.0
			hdir = 0
		_rpc_all("_ev", [0, 1 if lift else 0])
	var tgt_v: float = GEARS[gear]
	if _close_t > 0.0:
		_close_t -= delta
		tgt_v = 0.0
	# шаг 113: ТУРБО — ползунок добавляет до +10 м/с к ходу (по ходу), разгон резче; отпустил — сбрасывает
	var acc := ACC
	var wreck := _dmg_n() >= 2              # шаг 115: разбитая кабина — тише ход, слабее турбо
	if wreck:
		tgt_v *= 0.7
	if _xtra > 0.02 and absf(tgt_v) > 0.1:
		tgt_v += signf(tgt_v) * XTRA_V * _xtra * (0.5 if wreck else 1.0)
		acc = ACC + 4.0 * _xtra
	if absf(v) > absf(tgt_v) + 0.1 and absf(v) > 5.6:
		acc = maxf(acc, 2.6)
	v = move_toward(v, tgt_v, acc * delta)
	# на одном тросе лебёдка и поворот — вполсилы
	var hr := H_RATE * (0.5 if ropes != 3 else 1.0) * (0.8 if _dmg_n() >= 2 else 1.0)
	var yr := YAW_RATE * (0.6 if ropes != 3 else 1.0)
	# лебёдка и поворот: к цели, с разгоном и торможением (у причала — нельзя)
	if docked < 0:
		if hdir != 0:
			_hv = hdir * hr
		elif not is_nan(_h_tgt):
			var dh := clampf(_h_tgt, H_MIN, H_MAX) - H
			var wh := clampf(dh * 3.0, -hr, hr)
			if absf(dh) > 0.004 and absf(wh) < 0.08:
				wh = 0.08 * signf(dh)
			_hv = move_toward(_hv, wh, 6.0 * delta)
			if absf(dh) < 0.01 and absf(_hv) < 0.08:
				_hv = 0.0
				H = clampf(_h_tgt, H_MIN, H_MAX)
		else:
			_hv = move_toward(_hv, 0.0, 6.0 * delta)
		if rdir != 0:
			_yv = rdir * yr
		elif not is_nan(_y_tgt):
			var dy := wrapf(_y_tgt - yaw, -PI, PI)
			var wy := clampf(dy * 3.0, -yr, yr)
			if absf(dy) > 0.002 and absf(wy) < 0.05:
				wy = 0.05 * signf(dy)
			_yv = move_toward(_yv, wy, 3.0 * delta)
			if absf(dy) < 0.004 and absf(_yv) < 0.05:
				_yv = 0.0
				yaw = wrapf(_y_tgt, -PI, PI)
		else:
			_yv = move_toward(_yv, 0.0, 3.0 * delta)
		var nh := clampf(H + _hv * delta, H_MIN, maxf(H_MAX, H))
		var ny := wrapf(yaw + _yv * delta, -PI, PI)
		if _jolt != 0.0:
			# удар / оборванный трос — кабину крутанёт (если есть куда)
			var jy := wrapf(ny + _jolt, -PI, PI)
			_jolt = 0.0
			if _blocked(tr, s, nh, jy) < 0:
				ny = jy
				if _jolt_keep and not is_nan(_y_tgt):
					_y_tgt = jy
		if _spin_left > 0.0:
			# КАРУСЕЛЬ: полный оборот вокруг троса
			var stp := minf(1.8 * delta, _spin_left)
			_spin_left -= stp
			ny = wrapf(yaw + stp, -PI, PI)
			_yv = 0.0
		if _drop_left > 0.0:
			# СБРОС: лебёдку отпустило — кабина падает метров на 7 (с ускорением), потом рывок, и лебёдка тянет обратно
			_drop_v = minf(_drop_v + 18.0 * delta, 16.0)
			var stp2 := minf(_drop_v * delta, _drop_left)
			_drop_left -= stp2
			nh = minf(H + stp2, H_DROP)
			_hv = 0.0
			if _drop_left <= 0.0:
				_hv = -1.0
				_rpc_all("_ev_fun", [2, 1])
		if nh != H or ny != yaw:
			if _blocked(tr, s, nh, ny) >= 0:
				_hv = 0.0
				_yv = 0.0
				if _drop_left > 0.0:
					_drop_left = 0.0
					_rpc_all("_ev_fun", [2, 1])
				_spin_left = 0.0
				if _scrape_t <= 0.0:
					_scrape_t = 0.9
					_rpc_all("_ev", [1, 0])
			else:
				H = nh
				yaw = ny
	# камнепад: кабина под утёсом, когда камни долетели
	if docked < 0 and tr == 0 and _rock_c() >= ROCK_HIT and _hit_t <= 0.0:
		var ri := _rock_at(s, yaw)
		if ri >= 0:
			var o: Array = _obs[ri]
			var rmax := 0.5 * Vector2(CL, CW).length() + 0.5
			_hit(ri, true)
			v = 0.0
			s = float(o[1]) - rmax if s - float(o[1]) < float(o[2]) - s else float(o[2]) + rmax
			return
	# ветряк: лопасть задела кабину (или кабина въехала под лопасть)
	if docked < 0 and tr == 0 and _hit_t <= 0.0:
		for mi in _mills:
			if _mill_hit(int(mi), s, H, yaw, _clk):
				var om: Array = _obs[int(mi)]
				var rm := 0.5 * Vector2(CL, CW).length() + 0.6
				var back := v > 0.05 or (absf(v) <= 0.05 and s < (float(om[1]) + float(om[2])) * 0.5)
				_hit(int(mi), true)
				v = 0.0
				s = float(om[1]) - rm if back else float(om[2]) + rm
				return
	if absf(v) < 0.0005:
		return
	var ns := s + v * delta
	var ntr := tr
	if tr == 0 and v > 0.0:
		for j in _sj.size():
			if s < float(_sj[j]) and ns >= float(_sj[j]) and bool(sw[j]) != bool(_swok[j]):
				ntr = j + 1
				ns -= float(_sj[j])
				break
	elif tr > 0 and ns < 0.0:
		ns = float(_sj[tr - 1]) + ns
		ntr = 0
	# станции и тупики
	if ntr == 0 and (ns >= track_len(0) or ns <= 0.0):
		var at := 1 if ns >= track_len(0) else 0
		var ok := absf(v) <= DOCK_V and absf(H - H_DOCK) <= 0.8 and absf(cos(yaw)) <= 0.3
		if ok:
			s = track_len(0) if at == 1 else 0.0
			tr = 0
			v = 0.0
			gear = GEAR_N
			H = H_DOCK
			yaw = PI * 0.5 if wrapf(yaw, -PI, PI) > 0.0 else -PI * 0.5
			_h_tgt = NAN
			_y_tgt = NAN
			_hv = 0.0
			_yv = 0.0
			docked = at
			doors = _platform_door(at)
			if auto_to == at:
				auto_to = -1
			_rpc_all("_ev", [2, at])
		else:
			var e := _ext(yaw)
			_hit(-2, absf(v) >= STRONG_V)
			s = track_len(0) - e.x - 1.2 if at == 1 else e.x + 1.2
			tr = 0
		return
	if ntr > 0 and ns >= track_len(ntr) - 2.6:
		var strong := absf(v) >= STRONG_V
		if absf(v) > DOCK_V:
			_hit(-3, strong)
		else:
			v = 0.0
			gear = GEAR_N
			_rpc_all("_ev", [3, 0])
		tr = ntr
		s = track_len(ntr) - 3.4
		return
	var ob := _blocked(ntr, ns, H, yaw)
	if ob >= 0:
		var o2: Array = _obs[ob]
		var fwd := v > 0.0
		_hit(ob, absf(v) >= STRONG_V)
		tr = ntr
		# отбросило так, чтобы можно было повернуть кабину на месте
		var rmax2 := 0.5 * Vector2(CL, CW).length() + 0.5
		s = float(o2[1]) - rmax2 if fwd else float(o2[2]) + rmax2
		return
	tr = ntr
	s = ns
	if gust_ph == 2 and _in_wind(tr, s, yaw) and absf(v) > WIND_V:
		_hit(-4, absf(v) >= STRONG_V)


## Шаг 113: турбо работает только на ходу и у оператора; греется, перегрелось — 10 с отдыха
func _srv_turbo(delta: float) -> void:
	var ok := op_pid >= 0 and docked < 0 and gear != GEAR_N and _close_t <= 0.0
	_turbo_msg_t = maxf(_turbo_msg_t - delta, 0.0)
	if _ovh_t > 0.0:
		_ovh_t = maxf(_ovh_t - delta, 0.0)
		_xtra = 0.0
		_heat = 0.35 + 0.65 * _ovh_t / 10.0
		return
	_xtra = _xtra_in if ok else 0.0
	_heat = clampf(_heat + (_xtra * 0.2 - 0.07) * delta, 0.0, 1.0)
	if _xtra > 0.5 and _turbo_msg_t <= 0.0:
		_turbo_msg_t = 8.0
		_rpc_all("_ev_fun", [0, 0])
	if _heat >= 1.0:
		_ovh_t = 10.0
		_xtra = 0.0
		_xtra_in = 0.0
		_rpc_all("_ev_fun", [0, 5])


## Оба троса оборваны: кабина падает, через 7 с у Плато — новая
func _srv_fall(delta: float) -> void:
	_fall_t += delta
	_fall_v = minf(_fall_v + 14.0 * delta, 40.0)
	H += _fall_v * delta
	v = move_toward(v, 0.0, 3.0 * delta)
	s = clampf(s + v * delta, 0.0, track_len(tr))
	_hv = 0.0
	_yv = 0.0
	_xtra = 0.0
	gear = GEAR_N
	if _fall_t >= 7.0:
		tr = 0
		s = 0.0
		v = 0.0
		H = H_DOCK
		yaw = PI * 0.5
		_h_tgt = NAN
		_y_tgt = NAN
		hdir = 0
		rdir = 0
		docked = 0
		doors = _platform_door(0)
		auto_to = -1
		ropes = 3
		dmg = 0
		brd = 0
		_fall_t = -1.0
		_fall_v = 0.0
		_xtra_in = 0.0
		_heat = 0.0
		_ovh_t = 0.0
		_spin_left = 0.0
		_drop_left = 0.0
		_commit = -1
		_hit_t = 0.0
		_rpc_all("_ev_rope", [3, 0])


@rpc("any_peer", "call_remote", "reliable")
func _req_fix(pid: int, bit: int) -> void:
	if not multiplayer.is_server():
		return
	if ropes == 0 or (bit != 1 and bit != 2) or (ropes & bit) != 0:
		return
	var d: Node3D = mtn.drone_by_id(pid)
	if d == null:
		return
	var lp := _cabin.global_transform.affine_inverse() * d.global_position
	var a: Vector3 = ANCH[0 if bit == 1 else 1]
	if lp.y < CHT - 0.4 or Vector2(lp.x - a.x, lp.z - a.z).length() > 1.4 or int(_tool.get(pid, 0)) != 2:
		return
	ropes |= bit
	_rpc_all("_ev_rope", [1, bit])


func _dmg_n() -> int:
	var n := 0
	for k in SLOT_N:
		if (dmg & (1 << k)) != 0:
			n += 1
	return n


## Шаг 115: заколотил пробоину / вправил дверь
@rpc("any_peer", "call_remote", "reliable")
func _req_mend(pid: int, k: int) -> void:
	if not multiplayer.is_server():
		return
	if k < 0 or k >= SLOT_N or (dmg & (1 << k)) == 0 or int(_tool.get(pid, 0)) != 1:
		return
	var d: Node3D = mtn.drone_by_id(pid)
	if d == null or d.global_position.distance_to(_slot_target(k)) > 2.2:
		return
	dmg &= ~(1 << k)
	if k < 2:
		brd |= 1 << k
	_rpc_all("_ev_dmg", [1, k])


## Инструмент в руке: на хосте запомнить и всем показать
@rpc("any_peer", "call_remote", "reliable")
func _req_tool(pid: int, t: int) -> void:
	if not multiplayer.is_server():
		return
	_rpc_all("_set_tool", [pid, clampi(t, 0, 2)])


@rpc("authority", "call_local", "reliable")
func _set_tool(pid: int, t: int) -> void:
	_tool[pid] = t


## Какая дверь смотрит на платформу станции at
func _platform_door(at: int) -> int:
	var xf := cabin_xf(0, track_len(0) if at == 1 else 0.0, H, yaw, 0.0, 0.0)
	var to := _dir if at == 1 else -_dir
	return 1 if xf.basis.x.dot(to) > 0.0 else 2


func _hit(kind: int, strong: bool) -> void:
	var imp := absf(v)
	var sg := signf(v) if v != 0.0 else 1.0
	# шаг 113: чем сильнее врезались — тем дальше отбросило
	v = -sg * (clampf(0.6 + imp * 0.25, 0.9, 3.5) if strong else 0.45)
	gear = GEAR_N
	hits += 1
	_commit = -1
	_hv = 0.0
	_yv = 0.0
	_xtra_in = 0.0
	_xtra = 0.0
	_spin_left = 0.0
	_drop_left = 0.0
	if not is_nan(_h_tgt):
		_h_tgt = H
	if not is_nan(_y_tgt):
		_y_tgt = yaw
	if strong:
		_hit_t = 3.0
		doors = 3
		_jolt = randf_range(-1.0, 1.0) * clampf(imp * 0.035, 0.04, 0.3)
		_jolt_keep = false
	_rpc_all("_ev_hit", [kind, strong, sg * maxf(imp, 0.5)])
	if strong:
		# трос: удар на большом ходу рвёт его; камни и лопасть — как повезёт (но не второй)
		var hard := imp >= SNAP_V
		var lucky := kind >= 0 and kind < _obs.size() and (int(_obs[kind][0]) == ROCK or int(_obs[kind][0]) == MILL) and randf() < 0.5
		if ropes == 3 and (hard or lucky):
			var bit := 1 if randf() < 0.5 else 2
			ropes = 3 & ~bit
			_jolt = 0.26 if bit == 1 else -0.26
			_jolt_keep = true
			_rpc_all("_ev_rope", [0, bit])
		elif ropes != 3 and hard:
			ropes = 0
			_fall_t = 0.0
			_fall_v = 0.0
			_rpc_all("_ev_rope", [2, 0])
	# шаг 115: обшивку выбивает — сильный удар (на большом ходу — два куска), слабый — как повезёт
	var nb := (2 if imp >= 6.0 else 1) if strong else (1 if randf() < 0.25 else 0)
	for q in nb:
		var cand: Array = []
		for k in SLOT_N:
			if (dmg & (1 << k)) == 0:
				cand.append(k)
		if cand.is_empty():
			break
		var kb: int = cand[randi() % cand.size()]
		dmg |= 1 << kb
		brd &= ~(1 << kb)
		_rpc_all("_ev_dmg", [0, kb])


## Решение «проскочить» снимается, когда кабина миновала препятствие
func _commit_check() -> void:
	if _commit < 0 or _commit >= _obs.size():
		_commit = -1
		return
	var o: Array = _obs[_commit]
	var e := _ext(yaw)
	if tr != 0 or s - e.x > float(o[2]) + 0.5 or s + e.x < float(o[1]) - 12.0:
		_commit = -1


func _srv_auto() -> void:
	_commit_check()
	if auto_to < 0:
		return
	if _riders > 0:
		auto_to = -1
		return
	if docked == auto_to:
		auto_to = -1
		return
	var dirv := 1.0 if auto_to == 1 else -1.0
	if tr > 0:
		gear = 1                     # попала в тупик — назад
		return
	for j in _sj.size():
		sw[j] = _swok[j]
	# что впереди: то, внутри чего кабина, — главнее того, к чему подъезжает
	var e := _ext(yaw)
	var need_h := H_DOCK
	var need_y := PI * 0.5
	var lock_h := false
	var lock_y := false
	var wait := false
	var fast := false
	var slow := false
	# по очереди: сначала то, внутри чего кабина, потом — что ближе по ходу
	var order: Array = []
	var dist := {}
	for i in _obs.size():
		var o: Array = _obs[i]
		var inside := s + e.x >= float(o[1]) - 0.5 and s - e.x <= float(o[2]) + 0.5
		dist[i] = -1000.0 if inside else ((float(o[1]) - (s + e.x)) if dirv > 0.0 else (s - e.x - float(o[2])))
		order.append(i)
	order.sort_custom(func(a, b): return float(dist[a]) < float(dist[b]))
	for i2 in order:
		var o2: Array = _obs[i2]
		var kind: int = o2[0]
		var d0: float = (float(o2[1]) - (s + e.x)) if dirv > 0.0 else (s - e.x - float(o2[2]))
		var inside2 := s + e.x >= float(o2[1]) - 0.5 and s - e.x <= float(o2[2]) + 0.5
		if not inside2 and (d0 < -0.5 or d0 >= 16.0):
			continue
		var nh := NAN
		var nyv := NAN
		match kind:
			RIDGE:
				nh = float(o2[3]) - 0.6
			ICE:
				nh = float(o2[3]) + 0.8
			SLOT:
				nyv = 0.0
			CANYON:
				nyv = 0.0
				if inside2:
					slow = true
			WINDOW, RGATE:
				nh = (float(o2[3]) + float(o2[4])) * 0.5
				nyv = 0.0
			MILL:
				# решился проскочить — уже не тормозит посреди (иначе встанет под лопасть)
				nh = 7.0
				if not inside2 and _commit != i2:
					if _mill_pass_ok(i2, dirv, 3.0, 0.3 if absf(v) < 0.2 else 0.0):
						if d0 < 9.0:
							_commit = i2
					elif d0 < 9.0:
						wait = true
			WIND:
				if gust_ph >= 1:
					wait = wait or not inside2
			ROCK:
				if inside2 or _commit == i2:
					fast = true
				elif _rock_safe(d0, float(o2[2]) - float(o2[1]), e.x, absf(v), 5.5 if dirv > 0.0 else 3.0, 0.4):
					fast = true
					if d0 < 9.0:
						_commit = i2
				elif d0 < 9.0:
					wait = true
		if not is_nan(nh) and not lock_h:
			need_h = nh
			lock_h = true
		if not is_nan(nyv) and not lock_y:
			need_y = nyv
			lock_y = true
		# стоять и подстраиваться — только выбравшись из предыдущего (в каньоне ворота почти вплотную)
		if not inside2 and d0 < 6.0 and (not _inside_lock() or d0 < 0.6) and ((not is_nan(nh) and absf(H - nh) > 0.3) or (not is_nan(nyv) and absf(wrapf(yaw - nyv, -PI * 0.5, PI * 0.5)) > 0.03)):
			wait = true
	_h_tgt = need_h
	_y_tgt = yaw + wrapf(need_y - yaw, -PI * 0.5, PI * 0.5)
	var to_end := (track_len(0) - s) if dirv > 0.0 else s
	var g := 4 if dirv > 0.0 else 0
	if fast and dirv > 0.0:
		g = 5
	if to_end < 14.0 or slow or (_in_wind(tr, s, yaw) and gust_ph >= 1):
		g = 3 if dirv > 0.0 else 1
	if wait:
		g = GEAR_N
	gear = g


func _is_bot(pid: int) -> bool:
	var d: Node3D = mtn.drone_by_id(pid)
	return d != null and bool(d.get("is_bot"))


func _srv_bots(delta: float, bot_in: bool) -> void:
	var me = Network.local_player
	# бот за пультом: хозяин в кабине, пульт свободен
	if op_pid < 0 and me != null and _in_gondola(me.global_position):
		for d in get_tree().get_nodes_in_group("player"):
			if not bool(d.get("is_bot")) or bool(d.get("is_dead")):
				continue
			for i in _panels.size():
				var P: Dictionary = _panels[i]
				if (d as Node3D).global_position.distance_to(P["stand"]) < 1.3:
					_rpc_all("_set_op", [int(d.peer_id), i])
					break
	elif op_pid >= 0 and _is_bot(op_pid) and me != null and not _in_gondola(me.global_position) and docked >= 0:
		_rpc_all("_set_op", [-1, -1])
	# бот за пультом выполняет сигналы
	if op_pid >= 0 and _is_bot(op_pid):
		var now: float = mtn.now()
		while not _sigq.is_empty() and float(_sigq[0][0]) <= now:
			var sg: int = _sigq.pop_front()[1]
			_bot_apply(sg)
	# бот в кабине подсказывает человеку за пультом
	_bot_sig_t -= delta
	if bot_in and op_pid >= 0 and not _is_bot(op_pid) and _bot_sig_t <= 0.0:
		var sgn := _bot_need()
		if sgn >= 0 and (sgn != _bot_last or _bot_sig_t < -3.0):
			_bot_sig_t = 2.6
			_bot_last = sgn
			var bp := -1
			for d2 in get_tree().get_nodes_in_group("player"):
				if bool(d2.get("is_bot")) and _in_gondola(d2.global_position):
					bp = int(d2.peer_id)
			_rpc_all("_ev_sig", [sgn, bp])


func _bot_apply(sg: int) -> void:
	match sg:
		0:
			gear = maxi(gear, 3)
		1:
			gear = 1
		2:
			if gear == GEAR_N:
				gear = 4                 # «быстрее» с места — сразу обычный ход
			else:
				gear = mini(gear + 1, 5) if gear > GEAR_N else maxi(gear - 1, 0)
		3:
			gear = gear - 1 if gear > GEAR_N else (gear + 1 if gear < GEAR_N else GEAR_N)
		4:
			gear = GEAR_N
		5:
			_h_tgt = clampf(H - 2.0, H_MIN, H_MAX)
			if H > H_DOCK and _h_tgt < H_DOCK + 0.5 and track_len(0) - s < 30.0:
				_h_tgt = H_DOCK          # у причала — ровно на уровень платформы
		6:
			_h_tgt = clampf(H + 2.0, H_MIN, H_MAX)
			if H < H_DOCK and _h_tgt > H_DOCK - 0.5 and track_len(0) - s < 30.0:
				_h_tgt = H_DOCK
		7:
			# поворачивает на четверть: поперёк ↔ вдоль троса (пока крутится — повтор не сбивает)
			if not is_nan(_y_tgt) and absf(wrapf(_y_tgt - yaw, -PI, PI)) > 0.03:
				return
			# шаг 115: кабину перекосило ударом — сперва выровнять (к ближней четверти)
			var q7 := roundf(yaw / (PI * 0.5)) * PI * 0.5
			if absf(wrapf(yaw - q7, -PI, PI)) > 0.05:
				_y_tgt = wrapf(q7, -PI, PI)
				return
			if absf(cos(yaw)) < 0.7:
				_y_tgt = 0.0 if cos(yaw) >= 0.0 else PI
			else:
				_y_tgt = PI * 0.5 if sin(yaw) >= 0.0 else -PI * 0.5
		8:
			for j in _sj.size():
				if tr == 0 and s < float(_sj[j]):
					sw[j] = not bool(sw[j])
					break


## Что подсказать оператору (бот в кабине видит дорогу)
func _bot_need() -> int:
	if tr > 0:
		return 1 if gear >= GEAR_N else -1
	var e := _ext(yaw)
	for j in _sj.size():
		var dj := float(_sj[j]) - s
		if dj > 0.0 and dj < 30.0 and bool(sw[j]) != bool(_swok[j]):
			return 4 if dj < 8.0 and v > 0.5 else 8
	var to_end := track_len(0) - s
	if to_end < 30.0:
		if v > 1.25:
			return 3
		if absf(cos(yaw)) > 0.3:
			return 4 if v > 0.1 and to_end < 8.0 else 7
		if absf(H - H_DOCK) > 0.7:
			return 4 if v > 0.1 and to_end < 6.0 else (6 if H < H_DOCK else 5)
		return 0 if gear == GEAR_N else -1
	# шаг 115: кабину перекосило ударом — выровнять, если есть где
	var q8 := roundf(yaw / (PI * 0.5)) * PI * 0.5
	if absf(wrapf(yaw - q8, -PI, PI)) > 0.06 and _blocked(tr, s, H, wrapf(q8, -PI, PI)) < 0:
		return 7
	var clear := true
	var h_claim := false             # высоту «занимает» ближайшее препятствие — дальние ждут своей очереди
	var y_claim := false
	for i in _obs.size():
		var o: Array = _obs[i]
		var kind: int = o[0]
		var p1: float = o[3]
		var p2: float = o[4]
		var d0 := float(o[1]) - (s + e.x)
		var inside := s + e.x >= float(o[1]) and s - e.x <= float(o[2])
		if d0 < 30.0 and s - e.x <= float(o[2]):
			clear = false
		if not inside and (d0 > (18.0 if v < 2.0 else 26.0) or d0 < 0.0):
			continue
		if inside and kind == CANYON:
			if absf(v) > 1.25:
				return 3             # в каньоне — тихий ход
			continue
		if inside and kind != WIND and kind != ROCK and kind != MILL:
			# внутри — не задеть уже нельзя; высоту/поворот, которые оно держит, не трогаем, пока не выберемся
			if kind == RIDGE or kind == ICE or kind == WINDOW or kind == RGATE:
				h_claim = true
			if kind == SLOT or kind == WINDOW or kind == RGATE:
				y_claim = true
			continue
		var want := -1
		var uses_h := kind == RIDGE or kind == ICE or kind == WINDOW or kind == RGATE
		var uses_y := kind == SLOT or kind == CANYON or kind == WINDOW or kind == RGATE
		var skip_h := uses_h and h_claim
		var skip_y := uses_y and y_claim
		h_claim = h_claim or uses_h
		y_claim = y_claim or uses_y
		match kind:
			RIDGE:
				if H > p1 - 0.2 and not skip_h:
					want = 5
			ICE:
				if H < p1 + 0.2 and not skip_h:
					want = 6
			SLOT, CANYON:
				if e.y * 2.0 > GAP - 0.25 and not skip_y:
					want = 7
			MILL:
				if inside:
					if v < 2.5 and gear < 4:
						return 2
					continue
				if H > 8.5:
					want = 5
				elif absf(cos(yaw)) > 0.3 and _commit != i:
					want = 7                 # поперёк троса кабина короче — проскочить легче
				elif _commit == i:
					if gear < 4:
						return 2         # решились — только полным ходом
					continue
				elif d0 > 7.0:
					continue
				elif _mill_pass_ok(i, 1.0, 3.0, 1.0 if absf(v) < 0.2 else 0.3):
					_commit = i
					if gear <= GEAR_N:
						return 2
					continue
				else:
					return 4 if v > 0.2 else -1
			WINDOW, RGATE:
				if H < p1 + 0.3 and not skip_h:
					want = 6
				elif H > p2 - 0.3 and not skip_h:
					want = 5
				elif e.y * 2.0 > GAP - 0.25 and not skip_y:
					want = 7
			WIND:
				if absf(v) > WIND_V - 0.3:
					return 3
			ROCK:
				# видно утёс: под ним — только сразу после обвала и бегом
				if inside:
					if v < 2.5 and gear < 4:
						return 2
					continue
				if d0 > 7.0:
					continue
				if not _rock_safe(d0, float(o[2]) - float(o[1]), e.x, maxf(v, 0.0), 3.0, 0.6):
					return 4 if v > 0.2 else -1
				if gear <= GEAR_N:
					return 2
				continue
		if want == 7 and (_blocked(tr, s, H, yaw + 0.35) >= 0 or _blocked(tr, s, H, yaw - 0.35) >= 0):
			return 1 if gear >= GEAR_N else -1          # вплотную — не развернуться: сдать назад
		if want == 5 or want == 6:
			if _inside_lock():
				return -1            # ещё в прошлых воротах — сначала выбраться
		if want >= 0:
			if v < -0.1:
				return 4
			return 4 if v > 0.3 and d0 < v * v / (2.0 * ACC) + v + 1.5 else want
	if gear == GEAR_N and docked != 1:
		return 0
	if gear == 3 and clear:
		return 2
	return -1


# ---------------------------------------------------------------------------
#  Сеть
# ---------------------------------------------------------------------------
func _ask(fn: String, args: Array) -> void:
	if multiplayer.is_server():
		callv(fn, args)
	else:
		callv("rpc_id", [1, fn] + args)


func _rpc_all(fn: String, args: Array) -> void:
	if mtn._online():
		callv("rpc", [fn] + args)
	else:
		callv(fn, args)


@rpc("authority", "call_remote", "unreliable_ordered")
func _st(t_: int, s_: float, v_: float, h_: float, y_: float, g_: int, s0: bool, s1: bool, s2: bool, dk: int, dr: int, gp: int, rp: int, hi: int, au: int, ck: float, xh: Vector3, rb: int, dm: int) -> void:
	_clk = ck
	dmg = dm & 255
	brd = (dm >> 8) & 255
	_xtra = xh.x
	_heat = xh.y
	_ovh_t = xh.z
	ropes = rb
	if t_ != tr:
		_ds = s_
	tr = t_
	s = s_
	v = v_
	H = h_
	yaw = y_
	gear = g_
	sw = [s0, s1, s2]
	docked = dk
	doors = dr
	gust_ph = gp
	rock_ph = rp
	hits = hi
	auto_to = au


@rpc("any_peer", "call_remote", "reliable")
func _req_op(pid: int, panel: int, on: bool) -> void:
	if not multiplayer.is_server():
		return
	if on and op_pid < 0:
		auto_to = -1
		_rpc_all("_set_op", [pid, panel])
	elif not on and op_pid == pid:
		_rpc_all("_set_op", [-1, -1])


@rpc("authority", "call_local", "reliable")
func _set_op(pid: int, panel: int) -> void:
	var me = Network.local_player
	var mine := int(me.peer_id) if me else -99
	var was := op_pid
	op_pid = pid
	op_panel = panel
	hdir = 0
	rdir = 0
	_xtra_in = 0.0
	if pid < 0:
		_sigq.clear()
	if was == mine and pid != mine:
		_exit_panel()
	if pid == mine and pid >= 0:
		_enter_panel(panel)
	if pid >= 0 and panel >= 0:
		SFX.play(self, (_panels[panel]["face"] as Node3D).global_position, "click", -6.0, 0.9)


@rpc("any_peer", "call_remote", "reliable")
func _req_ctl(pid: int, what: int, val: int) -> void:
	if not multiplayer.is_server() or pid != op_pid:
		return
	match what:
		0:
			gear = clampi(val, 0, GEARS.size() - 1)
			auto_to = -1
		1:
			hdir = clampi(val, -1, 1)
			_h_tgt = NAN
		2:
			rdir = clampi(val, -1, 1)
			_y_tgt = NAN
		3:
			if val >= 0 and val < sw.size():
				sw[val] = not bool(sw[val])
				_rpc_all("_ev", [4, val])
		4:
			gear = GEAR_N
			auto_to = -1
			_xtra_in = 0.0
			_rpc_all("_ev", [5, 0])
		5:
			if _riders > 0:
				_rpc_all("_ev", [6, 1])
			elif docked != op_panel:
				auto_to = op_panel
				_rpc_all("_ev", [6, 0])
		6:
			hdir = 0
			_h_tgt = clampf(val / 100.0, H_MIN, H_MAX)
		7:
			rdir = 0
			var y := wrapf(val / 1000.0, -PI, PI)
			# фиксатор штурвала: почти вдоль/поперёк — ровно вдоль/поперёк
			var q := roundf(y / (PI * 0.5)) * PI * 0.5
			if absf(y - q) < 0.04:
				y = wrapf(q, -PI, PI)
			_y_tgt = y
		8:
			if _horn_cd <= 0.0:
				_horn_cd = 1.2
				_rpc_all("_ev", [7, randi() % 3])
		9:
			_srv_fun(val)
		10:
			# стрелка ближайшей развилки впереди: 0 — перекинуть, 1 — влево, 2 — вправо
			var j := _next_junction()
			if j >= 0:
				var nv := not bool(sw[j]) if val == 0 else val == 2
				if nv != bool(sw[j]):
					sw[j] = nv
					_rpc_all("_ev", [4, j])
		11:
			# турбо-ползунок, 0…100
			_xtra_in = clampf(val / 100.0, 0.0, 1.0)


@rpc("any_peer", "call_remote", "reliable")
func _req_sig(pid: int, id: int) -> void:
	if not multiplayer.is_server():
		return
	var now: float = mtn.now()
	if now - float(_sig_t.get(pid, -9.0)) < 0.35:
		return
	_sig_t[pid] = now
	_rpc_all("_ev_sig", [id, pid])


@rpc("authority", "call_local", "reliable")
func _ev_sig(id: int, pid: int) -> void:
	var now: float = mtn.now()
	_sig_on[id] = now + 4.0
	_sig_last = id
	var d: Node3D = mtn.drone_by_id(pid)
	_sig_from = String(d.get("display_name")) if d != null and d.get("display_name") else "кабина"
	if op_panel >= 0:
		SFX.play(self, (_panels[op_panel]["face"] as Node3D).global_position, "ding", -4.0, 1.25 + 0.06 * id)
	SFX.play(self, _cabin.global_position + Vector3.UP * 1.3, "click", -10.0, 1.4)
	if multiplayer.is_server() and op_pid >= 0 and _is_bot(op_pid):
		_sigq.append([now + 0.8, id])


## События: 0 — двери закрываются, 1 — лебёдка/поворот упёрлись, 2 — причалила (val — станция),
## 3 — упёрлась в тупик, 4 — стрелка (j), 5 — СТОП, 6 — вызов (1 — в кабине люди), 7 — гудок
@rpc("authority", "call_local", "reliable")
func _ev(kind: int, val: int) -> void:
	var cp := _cabin.global_position + Vector3.UP * 1.2
	match kind:
		0:
			SFX.play(self, cp, "latch", -4.0, 0.8)
			SFX.play(self, cp, "slide", -6.0, 0.7)
			if val == 1:
				_loc_h = 9.0
				SFX.play(self, cp + Vector3.UP * 2.5, "chain", -6.0, 0.9)
		1:
			SFX.play(self, cp, "grind", -6.0, 1.3)
			_say_riders("Упёрлись! Так не пройти — сначала проедьте препятствие или отойдите от него")
		2:
			SFX.play(self, cp, "ding", -2.0)
			SFX.play(self, cp, "latch", -4.0, 0.9)
			at_b = val == 1
			_loc_h = H_DOCK
			_loc_y = PI * 0.5 if wrapf(yaw, -PI, PI) > 0.0 else -PI * 0.5
			_say_riders("Причалили: %s! Двери открыты" % ("Плечо" if val == 1 else "Плато"))
		3:
			SFX.play(self, cp, "clank", -4.0, 0.8)
			_say_riders("Тупик — трос оборван. Назад и переключить стрелку!")
		4:
			SFX.play(self, (_panels[maxi(op_panel, 0)]["face"] as Node3D).global_position, "click", -2.0, 0.7)
		5:
			SFX.play(self, cp, "grind", -4.0, 0.6)
		6:
			var me = Network.local_player
			if me and op_pid == int(me.peer_id):
				_glitch = 0.4
				if val == 1:
					mtn.say("В кабине люди — сама не поедет")
		7:
			var hp: float = [0.42, 0.6, 0.33][clampi(val, 0, 2)]
			SFX.play(self, cp, "whistle", 2.0, hp, 120.0)
			SFX.play(self, cp + Vector3.UP * 0.4, "whistle", -2.0, hp * 1.3, 120.0)
			if op_panel >= 0:
				SFX.play(self, (_panels[op_panel]["face"] as Node3D).global_position, "whistle", -10.0, 0.45, 8.0)


@rpc("authority", "call_local", "reliable")
func _ev_hit(kind: int, strong: bool, sgi: float) -> void:
	var imp := absf(sgi)
	var sg := signf(sgi) if sgi != 0.0 else 1.0
	var cp := _cabin.global_position + Vector3.UP * 1.3
	SFX.play(self, cp, "clank", (2.0 + minf(imp, 10.0) * 0.6) if strong else -2.0, 0.6 if strong else 0.9)
	SFX.play(self, cp, "crunch", (0.0 + minf(imp, 10.0) * 0.5) if strong else -6.0, 0.8)
	if strong:
		SFX.play(self, cp, "snowslide", -4.0, 1.3)
	_glitch = 1.0 if strong else 0.6
	# шаг 113: кабину раскачивает и подкидывает тем сильнее, чем сильнее удар
	var kick := clampf(0.3 + imp * 0.09, 0.3, 1.2) if strong else 0.25
	_sw_av += sg * kick
	_sw_lv += randf_range(-1.0, 1.0) * kick * 0.9
	_bnc_v -= kick * 1.6
	_loc_h = H
	_loc_y = yaw
	var sp := FX.particles(Color(1.0, 0.75, 0.3), (26 + int(minf(imp, 10.0) * 4.0)) if strong else 12, 0.5, 0.06, 3.0, 8.0 + imp, Vector3(0, -9, 0), 120.0, true, true)
	add_child(sp)
	var tg := tangent(tr, s)
	sp.global_position = cp + tg * sg * 2.0
	sp.emitting = true
	get_tree().create_timer(1.5).timeout.connect(sp.queue_free)
	var what := "причал"
	if kind >= 0 and kind < _obs.size():
		what = OBS_NAMES[int(_obs[kind][0])]
	elif kind == -3:
		what = "буфер тупика"
	elif kind == -4:
		what = OBS_NAMES[WIND]
	var me = Network.local_player
	if me == null:
		return
	if _in_gondola(me.global_position):
		me.add_shake(clampf(0.5 + imp * 0.1, 0.5, 1.5) if strong else 0.4)
		var held: bool = me._held("interact")
		var fwd := tg * sg
		var roof: bool = (_cabin.global_transform.affine_inverse() * me.global_position).y > CHT - 0.2
		var heavy := kind >= 0 and kind < _obs.size() and (int(_obs[kind][0]) == ROCK or int(_obs[kind][0]) == MILL)
		if not bool(me.get("is_bot")) and not held:
			# не держался — швыряет по салону по ходу
			me.wind_shove(fwd, 2.0 + imp * 0.7)
			me.launch(1.0 + imp * 0.35)
		if strong:
			get_tree().call_group("level", "show_banner", "УДАР о %s!" % what if kind < 0 or int(_obs[kind][0]) != ROCK else "КАМНИ ПО КРЫШЕ!", "Двери распахнуло — держитесь (E)!")
			if not bool(me.get("is_bot")) and not held and (imp >= 4.0 or heavy or roof):
				_eject_me(me, fwd)
		else:
			_say_riders("Задели %s — аварийный тормоз" % what)


## Шаг 113: тросы. kind 0 — оборвался (bit), 1 — починили, 2 — оборвался второй (кабина падает), 3 — новая кабина у Плато
@rpc("authority", "call_local", "reliable")
func _ev_rope(kind: int, bit: int) -> void:
	var me = Network.local_player
	var aboard: bool = me != null and _in_gondola(me.global_position)
	var is_op: bool = me != null and op_pid == int(me.peer_id)
	var ap := _cabin.global_transform * (ANCH[0 if bit == 1 else 1] as Vector3)
	match kind:
		0:
			SFX.play(self, ap, "rope", 6.0, 0.5, 140.0)
			SFX.play(self, ap, "clank", 6.0, 0.45, 120.0)
			SFX.play(self, ap, "spark", 2.0, 1.0, 60.0)
			var sp := FX.particles(Color(1.0, 0.8, 0.35), 40, 0.6, 0.05, 3.0, 9.0, Vector3(0, -9, 0), 180.0, true, true)
			add_child(sp)
			sp.global_position = ap
			sp.emitting = true
			get_tree().create_timer(1.5).timeout.connect(sp.queue_free)
			_sw_av += 0.5 * (1.0 if bit == 1 else -1.0)
			_bnc_v -= 2.5
			if aboard:
				me.add_shake(1.3)
				get_tree().call_group("level", "show_banner", "ОБОРВАЛСЯ ТРОС!", "Кабину перекосило. Чините на крыше: подпрыгни под люком, возьми сварку из ящика и держи ЛКМ у крепления")
			if is_op:
				mtn.say("Оборвался трос! Лебёдка и поворот — вполсилы. Ещё удар на ходу — кабина рухнет")
		1:
			SFX.play(self, ap, "latch", 2.0, 0.8, 60.0)
			SFX.play(self, ap, "clank", 0.0, 1.1, 60.0)
			if aboard:
				get_tree().call_group("level", "show_banner", "ТРОС ПОЧИНИЛИ!", "Кабина снова висит ровно")
			if is_op:
				mtn.say("Трос починили — кабина в порядке")
		2:
			SFX.play(self, ap, "rope", 8.0, 0.45, 160.0)
			SFX.play(self, ap, "fail", 4.0, 0.5, 160.0)
			if aboard:
				get_tree().call_group("level", "show_banner", "ОБОРВАЛСЯ ВТОРОЙ ТРОС!!!", "Кабина падает…")
			if is_op:
				mtn.say("Второй трос оборвался — кабина упала! Новую подадут к Плато")
			# кто был внутри — разбился (боты — на хосте)
			for d in get_tree().get_nodes_in_group("player"):
				if _in_gondola(d.global_position) and (d == me or (multiplayer.is_server() and bool(d.get("is_bot")))):
					var dd: Node3D = d
					get_tree().create_timer(1.6).timeout.connect(func():
						if is_instance_valid(dd):
							dd.kill("Оборвались оба троса — кабина рухнула в пропасть.\nНе гоните на полном ходу в препятствия, чините трос сразу"))
		3:
			if is_op or (me != null and me.global_position.distance_to(M.RW_A) < 60.0):
				mtn.say("У Плато подали новую кабину")


## Шаг 115: kind 0 — выбило кусок k (стекло, обшивка, дверь), 1 — починили
@rpc("authority", "call_local", "reliable")
func _ev_dmg(kind: int, k: int) -> void:
	var me = Network.local_player
	var aboard: bool = me != null and _in_gondola(me.global_position)
	var at := _slot_target(k)
	if kind == 0:
		SFX.play(self, at, "crunch", 6.0, 0.7, 90.0)
		SFX.play(self, at, "ding", -2.0, 2.6, 60.0)
		SFX.play(self, at, "ding", -6.0, 3.1, 60.0)
		var out: Vector3 = (_cabin.global_transform.basis * Vector3(1.0 if k % 2 == 0 else -1.0, 0.0, 0.0)).normalized()
		var gl := FX.particles(Color(0.75, 0.9, 1.0, 0.85), 34, 1.2, 0.035, 2.0, 6.0, Vector3(0, -9, 0), 55.0, true, true)
		add_child(gl)
		gl.global_position = at
		gl.global_transform.basis = Basis.looking_at(out, Vector3.UP)
		gl.emitting = true
		get_tree().create_timer(2.0).timeout.connect(gl.queue_free)
		if aboard:
			get_tree().call_group("level", "show_banner", "ВЫБИЛО ОКНО!" if k < 2 else "СОРВАЛО ДВЕРЬ!", "Пробоина — не подходи близко! Молоток — на щитке у передней стойки")
	else:
		SFX.play(self, at, "latch", 0.0, 0.8, 50.0)
		SFX.play(self, at, "thunk", 0.0, 1.0, 50.0)
		if aboard:
			get_tree().call_group("level", "show_banner", "ПРОБОИНУ ЗАКОЛОТИЛИ" if k < 2 else "ДВЕРЬ НА МЕСТЕ", "")


func _say_riders(msg: String) -> void:
	var me = Network.local_player
	if me and _in_gondola(me.global_position):
		get_tree().call_group("level", "show_banner", msg, "")


## Вылетел из кабины (не держался): из двери, что ближе к ходу
func _eject_me(me: Node3D, fwd: Vector3) -> void:
	var xf := _cabin.global_transform
	var dx: Vector3 = xf.basis.x.normalized()
	var out := dx if dx.dot(fwd) > 0.0 else -dx
	if me.snow.busy():
		me.snow.end_scripted()
	me.global_position = xf.origin + out * (CW * 0.5 + 0.7) + Vector3.UP * 0.9
	me.velocity = out * 6.0 + fwd * 3.0 + Vector3.UP * 2.5
	_eject[int(me.peer_id)] = xf.origin.y
	get_tree().call_group("level", "show_banner", "Вылетел из кабины!", "Надо было держаться за поручень (E)")


# ---------------------------------------------------------------------------
#  Показ: кабина, тележка, двери, пульты (у всех)
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if _cabin == null:
		return
	if not multiplayer.is_server():
		s += v * delta
		_clk += delta
	_apply_visual(delta)


func _apply_visual(delta: float) -> void:
	if _dtr != tr or absf(_ds - s) > 6.0 or delta == 0.0:
		_ds = s
		_dtr = tr
		_dh = H
		_dy = yaw
	else:
		_ds = lerpf(_ds, s, clampf(delta * 12.0, 0.0, 1.0))
		_dh = lerpf(_dh, H, clampf(delta * 10.0, 0.0, 1.0))
		_dy = _dy + wrapf(yaw - _dy, -PI, PI) * clampf(delta * 10.0, 0.0, 1.0)
	# раскачка: разгон/торможение — вдоль, порыв — поперёк
	if delta > 0.0:
		var acc := (v - _pv) / delta
		_pv = v
		var L := maxf(_dh - 1.3, 4.0)
		var w2 := 9.8 / L
		_sw_av += (-w2 * _sw_a - 1.1 * _sw_av - clampf(acc, -6.0, 6.0) / L * 0.6) * delta
		_sw_a = clampf(_sw_a + _sw_av * delta, -0.12, 0.12)
		var gf := 0.0
		if gust_ph == 2 and _in_wind(tr, s, yaw):
			gf = 0.9 * sin(mtn.now() * 2.3) + 0.6
		elif gust_ph == 1 and _in_wind(tr, s, yaw):
			gf = 0.25
		_sw_lv += (-w2 * _sw_l - 1.0 * _sw_lv + gf * (1.0 + absf(v))) * delta
		var lim_l := 0.34 if _swing_t > 0.0 or absf(_sw_l) > 0.14 else 0.14
		_sw_l = clampf(_sw_l + _sw_lv * delta, -lim_l, lim_l)
	var xf := cabin_xf(_dtr, _ds, _dh, _dy, _sw_a, _sw_l)
	xf.origin += Vector3.UP * _bnc
	# шаг 113: на одном тросе кабина висит на одном креплении — перекошена и чуть гуляет
	var one := ropes == 1 or ropes == 2
	if one:
		_tilt_z = float((ANCH[0] if ropes == 1 else ANCH[1]).z)
	_tilt = move_toward(_tilt, -TILT * signf(_tilt_z) if one else 0.0, delta * (0.9 if one else 0.4))
	if absf(_tilt) > 0.0005:
		var pvt := Vector3(0.0, float(ANCH[0].y), _tilt_z)
		var wob := 0.04 * sin(mtn.now() * 0.9) * absf(_tilt) / TILT
		xf = xf * Transform3D(Basis(Vector3.UP, wob) * Basis(Vector3.RIGHT, _tilt), pvt - Basis(Vector3.UP, wob) * Basis(Vector3.RIGHT, _tilt) * pvt)
	# оба оборваны — кувыркается вниз, потом пропадает (новая — у Плато)
	if ropes == 0:
		if _fall_vis < 0.0:
			_fall_vis = 0.0
		_fall_vis += delta
		xf.basis = xf.basis * Basis(Vector3.RIGHT, minf(_fall_vis * 0.7, 1.3)) * Basis(Vector3.BACK, minf(_fall_vis * 0.3, 0.5))
		if _fall_vis > 2.6 and _cabin.visible:
			_cabin.visible = false
			SFX.play(self, _cabin.global_position, "crunch", 8.0, 0.4, 160.0)
	elif _fall_vis >= 0.0:
		_fall_vis = -1.0
		_cabin.visible = true
	_cabin.global_transform = xf
	var c := cable_pt(_dtr, _ds)
	var tg := tangent(_dtr, _ds)
	_carriage.global_transform = Transform3D(Basis(Vector3.UP, atan2(tg.x, tg.z)), c)
	var bot := c + Vector3.DOWN * 0.6
	var tnow: float = mtn.now()
	for rk in 2:
		var ra := bot + tg * (0.14 if rk == 0 else -0.14)
		var rb: Vector3
		if (ropes & (1 << rk)) != 0:
			rb = xf * (ANCH[rk] as Vector3)
		else:
			# оборванный конец болтается под тележкой
			rb = ra + Vector3(sin(tnow * 1.3 + rk * 2.0) * 0.8, -4.2, cos(tnow * 1.1 + rk) * 0.6)
			# шаг 116: варю — конец троса подтягивается к креплению, потом шов раскаляется
			if _weld_bi == rk:
				rb = rb.lerp(xf * (ANCH[rk] as Vector3), smoothstep(0.0, 0.45, clampf(_fix_t / FIX_T, 0.0, 1.0)))
		_place_rope(_ropes_m[rk], ra, rb)
	if _beads.is_empty():
		for bk2 in 2:
			var bm2 := SphereMesh.new()
			bm2.radius = 0.06
			bm2.height = 0.09
			var bmat := _glow(Color(1.0, 0.45, 0.1), 3.0)
			var bmi := _mesh(_cabin, bm2, Transform3D(Basis.IDENTITY, (ANCH[bk2] as Vector3) + Vector3.UP * 0.05), bmat, false)
			bmi.visible = false
			_beads.append(bmi)
	for bk3 in 2:
		var bmi2: MeshInstance3D = _beads[bk3]
		var on3 := _weld_bi == bk3 and ropes != 0
		bmi2.visible = on3
		if on3:
			var pr3 := clampf(_fix_t / FIX_T, 0.0, 1.0)
			var g3 := smoothstep(0.3, 1.0, pr3)
			bmi2.scale = Vector3.ONE * (0.25 + 0.9 * g3)
			var m3 := bmi2.material_override as StandardMaterial3D
			m3.emission = Color(1.0, 0.45, 0.1).lerp(Color(1.0, 0.95, 0.8), g3)
			m3.emission_energy_multiplier = 2.0 + 6.0 * g3 * (0.8 + 0.2 * sin(tnow * 40.0))
	_smoke.emitting = _ovh_t > 0.0
	_update_slots()
	_update_jlights(tnow)
	# двери
	for i in 2:
		var want := 1.0 if (doors & (1 << i)) != 0 else 0.0
		_door_k[i] = move_toward(float(_door_k[i]), want, delta * 1.6)
		var dn: Node3D = _door_nodes[i]
		dn.position.z = -1.38 * float(_door_k[i])
		var gone := (dmg & (1 << (2 + i))) != 0
		dn.visible = not gone
		(_door_cols[i] as CollisionShape3D).disabled = float(_door_k[i]) > 0.5 or gone
	# звук хода, колёса станций
	if _hum:
		_hum.volume_db = lerpf(-40.0, -8.0, clampf(absf(v) / 4.0, 0.0, 1.0))
	for w in _wheels:
		(w as Node3D).rotate_object_local(Vector3.UP, delta * v * 0.6)
	# табло стрелок на опорах
	for j in _sw_lamps.size():
		var ls: Array = _sw_lamps[j]
		_lamp(ls[0], not bool(sw[j]))
		_lamp(ls[1], bool(sw[j]))
	for fx in _gust_fx:
		(fx as GPUParticles3D).emitting = gust_ph == 2
	var now: float = mtn.now()
	# мигалка на антенне, огонёк на схеме
	var bon := fmod(now, 1.0) < 0.25
	if bon != _beacon_on:
		_beacon_on = bon
		_beacon_m.emission_energy_multiplier = 6.0 if bon else 0.2
	_map_dot.position = _map_pt(_al(c))
	_map_dot.scale = Vector3.ONE * (1.0 + 0.35 * sin(now * 6.0))
	var me = Network.local_player
	_update_rocks(delta, me)
	_update_mills(me)
	_update_cabin_fx(delta, me)
	_rider_fx(delta, me)
	_update_tools()
	# разбитая кабина скрипит и дрожит
	if _dmg_n() >= 2 and ropes != 0:
		_dmg_t -= delta
		if _dmg_t <= 0.0:
			_dmg_t = randf_range(0.6, 1.6)
			_sw_lv += randf_range(-0.12, 0.12)
			_bnc_v -= randf_range(0.2, 0.6)
			SFX.play(self, _cabin.global_position + Vector3.UP * 1.5, "creak", -6.0, randf_range(0.7, 1.0), 40.0)
			if me != null and _in_gondola(me.global_position):
				me.add_shake(0.15)
	# «ворота» для ботов — рядом с хозяином, пока он у канатки
	if me != null and (me.global_position.distance_to(_cabin.global_position) < 60.0 or _in_panel_zone(me.global_position)):
		_gate.global_position = me.global_position
	else:
		_gate.global_position = M.RW_A
	if me != null and me.global_position.distance_to(_cabin.global_position) < 20.0:
		_update_cab_display()
	_glitch = maxf(_glitch - delta * 0.7, 0.0)
	for P in _panels:
		if _my_panel == int(P["st"]) or (me != null and me.global_position.distance_to(P["stand"]) < 14.0):
			_update_panel(P, delta)


## Шаг 115: кусок борта (глухая половина): целый — обшивка+стекло; выбитый — осколки по краям, оторванный
## лист наружу, стекло на полу; заколоченный — доски на гвоздях. Коллизия — пока не выбит.
func _build_slot(sx: float, zc: float, wl: float, body: Material, cream: Material, panel: Material, wood: Material, glass: Material) -> Dictionary:
	var hw := CW * 0.5
	var ni := Node3D.new()
	_cabin.add_child(ni)
	_mesh(ni, _bm(Vector3(0.014, 0.36, wl)), Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.004), 0.68, zc)), body)
	_mesh(ni, _bm(Vector3(0.03, 0.12, wl)), Transform3D(Basis.IDENTITY, Vector3(sx * hw, 0.92, zc)), cream)
	_mesh(ni, _bm(Vector3(0.02, 0.06, wl)), Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.005), 1.01, zc)), _m_dark)
	_mesh(ni, _bm(Vector3(0.02, 1.24, wl)), Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.03), 1.66, zc)), glass, false)
	_mesh(ni, _bm(Vector3(0.02, 0.14, wl)), Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.01), 2.35, zc)), cream)
	_mesh(ni, _bm(Vector3(0.012, 0.48, wl)), Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.075), 0.74, zc)), panel)
	_mesh(ni, _bm(Vector3(0.1, 0.03, wl)), Transform3D(Basis.IDENTITY, Vector3(sx * (hw - 0.065), 0.985, zc)), wood)
	# выбит
	var nb := Node3D.new()
	_cabin.add_child(nb)
	nb.visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + int(sx * 10.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gx := sx * (hw - 0.03)
	var y0 := 1.04
	var y1 := 2.28
	var z0 := zc - wl * 0.5
	var z1 := zc + wl * 0.5
	for e in 4:
		var n := 7 if e % 2 == 0 else 5
		for q in n:
			var t0 := float(q) / n
			var t1 := float(q + 1) / n
			var dep := rng.randf_range(0.04, 0.26)
			var a: Vector3
			var b: Vector3
			var c: Vector3
			match e:
				0:
					a = Vector3(gx, y0, lerpf(z0, z1, t0)); b = Vector3(gx, y0, lerpf(z0, z1, t1)); c = Vector3(gx, y0 + dep, lerpf(z0, z1, (t0 + t1) * 0.5 + rng.randf_range(-0.04, 0.04)))
				1:
					a = Vector3(gx, lerpf(y0, y1, t0), z1); b = Vector3(gx, lerpf(y0, y1, t1), z1); c = Vector3(gx, lerpf(y0, y1, (t0 + t1) * 0.5), z1 - dep)
				2:
					a = Vector3(gx, y1, lerpf(z1, z0, t0)); b = Vector3(gx, y1, lerpf(z1, z0, t1)); c = Vector3(gx, y1 - dep, lerpf(z1, z0, (t0 + t1) * 0.5))
				_:
					a = Vector3(gx, lerpf(y1, y0, t0), z0); b = Vector3(gx, lerpf(y1, y0, t1), z0); c = Vector3(gx, lerpf(y1, y0, (t0 + t1) * 0.5), z0 + dep)
			for v3 in [a, b, c]:
				st.set_normal(Vector3(sx, 0.0, 0.0))
				st.add_vertex(v3)
	_mesh(nb, st.commit(), Transform3D.IDENTITY, glass, false)
	# оторванный лист обшивки — висит наружу на нижней кромке
	var piv := Vector3(sx * (hw - 0.004), WIN_Y.x, zc - wl * 0.22)
	var rb := Basis(Vector3(0, 0, 1), -sx * 1.05) * Basis(Vector3(0, 1, 0), 0.12 * sx)
	_mesh(nb, _bm(Vector3(0.014, 0.38, wl * 0.5)), Transform3D(rb, piv + rb * Vector3(0, 0.19, 0)), body)
	_mesh(nb, _bm(Vector3(0.012, 0.16, wl * 0.4)), Transform3D(Basis(Vector3(0, 0, 1), 0.2 * sx), Vector3(sx * (hw - 0.075), 0.6, zc + wl * 0.25)), panel)
	for g in 8:
		_mesh(nb, _bm(Vector3(rng.randf_range(0.03, 0.09), 0.006, rng.randf_range(0.03, 0.08))), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(sx * (hw - rng.randf_range(0.25, 0.75)), 0.012, zc + rng.randf_range(-0.5, 0.5))), glass, false)
	# заколочено
	var nd := Node3D.new()
	_cabin.add_child(nd)
	nd.visible = false
	var bx := sx * (hw - 0.1)
	var nail := _cmat(Color(0.2, 0.2, 0.21), 0.4, 0.8)
	var ys := [0.95, 1.3, 1.65, 2.0]
	for q2 in ys.size():
		var pl := Node3D.new()
		nd.add_child(pl)
		pl.position = Vector3(bx, float(ys[q2]), zc)
		pl.rotation.x = rng.randf_range(-0.06, 0.06)
		_mesh(pl, _bm(Vector3(0.035, 0.17, wl + 0.16)), Transform3D.IDENTITY, wood)
		for ez in [-1.0, 1.0]:
			_mesh(pl, _cyl(0.012, 0.012, 0.012, 6), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-sx * 0.02, 0.0, ez * (wl * 0.5 + 0.02))), nail)
	var dg := Node3D.new()
	nd.add_child(dg)
	dg.position = Vector3(bx - sx * 0.04, 1.45, zc)
	dg.rotation.x = 0.95
	_mesh(dg, _bm(Vector3(0.035, 0.16, 2.0)), Transform3D.IDENTITY, wood)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.12, WIN_Y.y - WIN_Y.x, wl)
	col.shape = bs
	col.position = Vector3(sx * (hw - 0.05), (WIN_Y.x + WIN_Y.y) * 0.5, zc)
	_cabin.add_child(col)
	return {"in": ni, "br": nb, "bd": nd, "col": col}


## Показать состояние бортов (и доски, которые я уже прибил, пока стучу)
func _update_slots() -> void:
	var key := dmg | (brd << 8) | ((_mend_k + 1) << 16) | (int(_mend_t / MEND_T * 4.0) << 20)
	if key == _slot_seen or _slots.is_empty():
		return
	_slot_seen = key
	for k in 2:
		var S: Dictionary = _slots[k]
		var br := (dmg & (1 << k)) != 0
		var bd := (brd & (1 << k)) != 0
		(S["in"] as Node3D).visible = not br and not bd
		(S["br"] as Node3D).visible = br
		var nd: Node3D = S["bd"]
		var part := br and _mend_k == k
		nd.visible = bd or part
		# пока стучу — видна и та доска, которую сейчас прибиваю (порядок: 2-я, 3-я, 1-я, 4-я, косая)
		var np := int(_mend_t / MEND_T * 5.0) + 1 if part else 99
		var order := [2, 0, 1, 3, 4]
		for q in nd.get_child_count():
			(nd.get_child(q) as Node3D).visible = int(order[q]) < np
		(S["col"] as CollisionShape3D).disabled = br


## Молоток: рукоять вдоль +z от кулака, боёк — на конце, ударная сторона к −y, гвоздодёр — к +y
func _hammer_tool() -> Node3D:
	var n := Node3D.new()
	var woodh := _cmat(Color(0.62, 0.42, 0.22), 0.6)
	var steel := _cmat(Color(0.55, 0.57, 0.6), 0.3, 0.9)
	var rub := _cmat(Color(0.08, 0.08, 0.08), 0.9)
	_mesh(n, _cyl(0.0165, 0.019, 0.36, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.1)), woodh, false)
	_mesh(n, _cyl(0.021, 0.021, 0.12, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.01)), rub, false)
	_mesh(n, _bm(Vector3(0.032, 0.07, 0.04)), Transform3D(Basis.IDENTITY, Vector3(0, -0.01, 0.285)), steel, false)
	_mesh(n, _cyl(0.021, 0.021, 0.045, 12), Transform3D(Basis.IDENTITY, Vector3(0, -0.062, 0.285)), steel, false)
	for cx2 in [-1.0, 1.0]:
		_mesh(n, _bm(Vector3(0.011, 0.075, 0.03)), Transform3D(Basis(Vector3.RIGHT, -0.45), Vector3(cx2 * 0.009, 0.055, 0.273)), steel, false)
	return n


## Сварочная горелка: рукоять с вентилями, трубка, сопло на +z; пламя/искры/свет — пока варю
func _torch_tool() -> Node3D:
	# шаг 117: сварочный пистолет: чёрная рукоять с курком, корпус, изогнутая стальная шейка, медное сопло, толстый кабель назад
	var n := Node3D.new()
	var blk := _cmat(Color(0.08, 0.08, 0.09), 0.6)
	var orn := _cmat(Color(0.95, 0.45, 0.08), 0.5)
	var steel := _cmat(Color(0.62, 0.64, 0.68), 0.25, 0.9)
	var copper := _cmat(Color(0.78, 0.42, 0.22), 0.3, 0.85)
	# рукоять (в кулаке, вдоль z) с рифлением
	_mesh(n, _cyl(0.021, 0.019, 0.13, 12), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.0)), blk, false)
	for rk in 4:
		_mesh(n, _cyl(0.0225, 0.0225, 0.008, 12), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.045 + rk * 0.025)), _m_dark, false)
	# корпус пистолета спереди с оранжевой вставкой и курок
	_mesh(n, _bm(Vector3(0.05, 0.06, 0.07)), Transform3D(Basis.IDENTITY, Vector3(0, 0.008, 0.095)), blk, false)
	_mesh(n, _bm(Vector3(0.052, 0.022, 0.05)), Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0.095)), orn, false)
	_mesh(n, _bm(Vector3(0.014, 0.03, 0.016)), Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, -0.03, 0.065)), orn, false)
	_mesh(n, _bm(Vector3(0.008, 0.008, 0.06)), Transform3D(Basis.IDENTITY, Vector3(0, -0.045, 0.08)), blk, false)
	# шейка: прямо, потом вниз (две трубки) и сопло
	_mesh(n, _cyl(0.011, 0.011, 0.09, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.0, 0.175)), steel, false)
	_mesh(n, _cyl(0.011, 0.011, 0.08, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + 0.55), Vector3(0, -0.018, 0.25)), steel, false)
	_mesh(n, _cyl(0.013, 0.017, 0.045, 12), Transform3D(Basis(Vector3.RIGHT, PI * 0.5 + 0.55), Vector3(0, -0.04, 0.29)), copper, false)
	# кабель: из рукояти назад и вниз (к ранцу)
	_mesh(n, _cyl(0.013, 0.013, 0.05, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.09)), _m_dark, false)
	_mesh(n, _cyl(0.011, 0.011, 0.3, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.9), Vector3(0, -0.11, -0.2)), _m_dark, false)
	var fl := Node3D.new()
	fl.name = "Flame"
	n.add_child(fl)
	fl.position = Vector3(0, -0.055, 0.315)
	fl.rotation.x = 0.55
	fl.visible = false
	var core := _glow(Color(0.55, 0.75, 1.0), 6.0)
	_mesh(fl, _cyl(0.0, 0.008, 0.05, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.025)), core, false)
	var outer := _glow(Color(0.35, 0.5, 1.0), 2.0)
	outer.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer.albedo_color = Color(0.35, 0.5, 1.0, 0.35)
	_mesh(fl, _cyl(0.0, 0.016, 0.09, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.045)), outer, false)
	var hot := SphereMesh.new()
	hot.radius = 0.028
	hot.height = 0.05
	_mesh(fl, hot, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.1)), _glow(Color(1.0, 0.75, 0.35), 9.0), false)
	var lt := OmniLight3D.new()
	lt.name = "Light"
	lt.light_color = Color(0.7, 0.82, 1.0)
	lt.omni_range = 4.5
	lt.light_energy = 3.0
	lt.position = Vector3(0, 0, 0.09)
	fl.add_child(lt)
	var sp := FX.particles(Color(1.0, 0.6, 0.15), 90, 0.6, 0.006, 1.4, 4.5, Vector3(0, -9, 0), 85.0, false, true)
	sp.name = "Sparks"
	sp.position = Vector3(0, 0, 0.1)
	fl.add_child(sp)
	return n


## Инструменты в руках у всех: крепятся к правой кисти; у сварки — пламя, искры и свет, пока варит
func _update_tools() -> void:
	var now: float = mtn.now()
	for d in get_tree().get_nodes_in_group("player"):
		var pid := int(d.peer_id)
		var t := int(_tool.get(pid, 0))
		var tv: Node3D = _tool_vis.get(pid)
		var ok: bool = t != 0 and not bool(d.get("is_dead")) and d.get("suit") != null and d.suit.has_method("hand_node")
		if not ok:
			if tv and is_instance_valid(tv):
				tv.queue_free()
			_tool_vis.erase(pid)
			continue
		if tv == null or not is_instance_valid(tv) or int(tv.get_meta("t", 0)) != t:
			if tv and is_instance_valid(tv):
				tv.queue_free()
			tv = _hammer_tool() if t == 1 else _torch_tool()
			tv.set_meta("t", t)
			(d.suit.hand_node(1) as Node3D).add_child(tv)
			tv.transform = d.suit.grip_local(1)
			_tool_vis[pid] = tv
		if t == 2:
			var fl: Node3D = tv.get_node("Flame")
			var on := int(d.snow.mpose) == 29
			fl.visible = on
			if on:
				(fl.get_node("Light") as OmniLight3D).light_energy = 2.4 + 2.6 * absf(sin(now * 37.0)) * randf()
				fl.scale = Vector3.ONE * (0.9 + 0.2 * randf())
			(fl.get_node("Sparks") as GPUParticles3D).emitting = on


## Шаг 115: огни развилок — гирлянды вдоль троса (по обе стороны) за 60 м до развилки и по 40 м на каждую ветку.
## Бегущие зелёные огни ведут туда, куда стоит стрелка; закрытая ветка горит тускло-красным.
func _build_jlights() -> void:
	_jl.clear()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	sm.material = mat
	for j in _sj.size():
		var pts: Array = []
		var sj := float(_sj[j])
		for q in 24:
			pts.append([0, sj - 60.0 + q * 2.5])
		for q2 in 16:
			pts.append([0, sj + 1.5 + q2 * 2.5])
		for q3 in 16:
			pts.append([j + 1, 1.5 + q3 * 2.5])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = sm
		mm.instance_count = pts.size() * 2
		for i in pts.size():
			var t_: int = pts[i][0]
			var s_: float = pts[i][1]
			var c := cable_pt(t_, s_)
			var lat := _lat_axis(tangent(t_, s_))
			for sd in 2:
				mm.set_instance_transform(i * 2 + sd, Transform3D(Basis.IDENTITY, c + lat * (0.5 if sd == 0 else -0.5) + Vector3.DOWN * 0.05))
				mm.set_instance_color(i * 2 + sd, Color(0.1, 0.1, 0.1))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_jl.append({"mm": mm, "c": cable_pt(0, sj), "ar": _fork_sign(j, sj)})


## Шаг 115: щит на мачте развилки — «РАЗВИЛКА N», стрелки ← → (куда стоит стрелка — горит зелёным)
func _fork_sign(j: int, sj: float) -> Array:
	var c := cable_pt(0, sj)
	var tin := tangent(0, sj - 6.0)
	tin.y = 0.0
	tin = tin.normalized()
	var wi := int(DEAD[j][0])
	var bp: Vector3 = _pyl_base.get(wi, c + _lat_axis(tin) * 8.0)
	var n := Node3D.new()
	add_child(n)
	n.global_transform = Transform3D(Basis.looking_at(tin, Vector3.UP) * Basis.from_scale(Vector3.ONE * 1.5), Vector3(bp.x, c.y + 6.4, bp.z))
	var yel := _cmat(Color(0.95, 0.75, 0.1), 0.5)
	_mesh(n, _bm(Vector3(4.6, 2.5, 0.12)), Transform3D.IDENTITY, yel, false)
	_mesh(n, _bm(Vector3(4.3, 2.2, 0.14)), Transform3D.IDENTITY, _m_dark, false)
	_beam(n.global_position + Vector3.DOWN * 1.8, Vector3(bp.x, c.y + 2.4, bp.z), 0.08, _m_paint)
	var lb := _label(n, "РАЗВИЛКА %d" % (j + 1), Vector3(0, 0.65, 0.09), 96, Color(1.0, 0.9, 0.55), 0.012, false)
	lb.double_sided = false
	var mats: Array = []
	for k in 2:
		var sg := -1.0 if k == 0 else 1.0
		var ar := PrismMesh.new()
		ar.size = Vector3(0.9, 0.8, 0.06)
		var am := _glow(Color(0.25, 1.0, 0.4), 0.2)
		_mesh(n, ar, Transform3D(Basis(Vector3.BACK, -sg * PI * 0.5), Vector3(sg * 1.25, -0.35, 0.1)), am, false)
		_mesh(n, _bm(Vector3(0.7, 0.3, 0.06)), Transform3D(Basis.IDENTITY, Vector3(sg * 0.55, -0.35, 0.1)), am, false)
		mats.append(am)
	return mats


func _update_jlights(now: float) -> void:
	var me = Network.local_player
	for j in _jl.size():
		var J: Dictionary = _jl[j]
		var c: Vector3 = J["c"]
		var near: bool = _cabin.global_position.distance_to(c) < 260.0 or (me != null and me.global_position.distance_to(c) < 420.0)
		if not near:
			continue
		var mm: MultiMesh = J["mm"]
		var to_main := bool(sw[j]) == bool(_swok[j])
		var ars: Array = J.get("ar", [])
		for k5 in ars.size():
			var on5 := bool(sw[j]) == (k5 == 1)
			var m5 := ars[k5] as StandardMaterial3D
			var col5 := Color(0.25, 1.0, 0.4) if on5 else Color(1.0, 0.15, 0.08)
			var e5 := (3.0 if fmod(now * 1.6, 1.0) < 0.75 else 1.6) if on5 else 0.35
			if m5.emission != col5 or absf(m5.emission_energy_multiplier - e5) > 0.01:
				m5.emission = col5
				m5.albedo_color = col5 * 0.5
				m5.emission_energy_multiplier = e5
		var n := mm.instance_count / 2
		for i in n:
			var col: Color
			var lit := i < 24 or (to_main and i < 40) or (not to_main and i >= 40)
			if lit:
				var idx := i if i < 40 else 24 + (i - 40)
				var ph := fposmod(float(idx) * 0.42 - now * 7.0, 3.4)
				col = Color(0.4, 2.6, 0.7) if ph < 1.0 else Color(0.06, 0.35, 0.12)
			else:
				col = Color(0.9, 0.08, 0.05) if fmod(now, 1.2) < 0.6 else Color(0.35, 0.03, 0.02)
			mm.set_instance_color(i * 2, col)
			mm.set_instance_color(i * 2 + 1, col)


func _place_rope(rm: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := a - b
	var L2 := d.length()
	var upv := d / maxf(L2, 0.01)
	var xa := upv.cross(Vector3.FORWARD if absf(upv.z) < 0.9 else Vector3.RIGHT).normalized()
	rm.global_transform = Transform3D(Basis(xa, upv, xa.cross(upv)).scaled(Vector3(1.0, L2, 1.0)), (a + b) * 0.5)


## Шаг 113: что чувствуют те, кто в кабине (и на крыше). Держишься (E) — слабо, нет — сильно.
##   карусель: прижимает к стенам и мир плывёт; раскачка/перекос: сносит под уклон, камера кренится;
##   разгон (турбо) — откидывает назад, торможение — кидает вперёд; на крыше на ходу — сдувает
func _rider_fx(delta: float, me: Node3D) -> void:
	if me == null or delta <= 0.0 or bool(me.get("is_bot")):
		return
	var xf := _cabin.global_transform
	var nz := Vector3(xf.basis.z.x, 0.0, xf.basis.z.z).normalized()
	var w := 0.0
	if _pcz != Vector3.ZERO and nz != Vector3.ZERO:
		w = _pcz.signed_angle_to(nz, Vector3.UP) / delta
	_pcz = nz
	_acc_s = lerpf(_acc_s, clampf((v - _pvr) / delta, -15.0, 15.0), clampf(delta * 8.0, 0.0, 1.0))
	_pvr = v
	var pid := int(me.peer_id)
	var pv: Node3D = me.get("camera_pivot")
	var aboard := _in_gondola(me.global_position) and op_pid != pid and not bool(me.get("is_dead")) and ropes != 0
	if not aboard:
		if _roll_on:
			_roll_on = false
			me.set("fp_roll", 0.0)
			if pv:
				pv.rotation.z = 0.0
		return
	_roll_on = true
	var held := bool(_hold.get(pid, false))
	var lp := xf.affine_inverse() * me.global_position
	var roof := lp.y > CHT - 0.2
	var k := 0.25 if held else (1.5 if roof else 1.0)
	var kp := 0.0 if held else k          # держится — не сносит (только трясёт и кренит)
	var push := Vector3.ZERO
	if absf(w) > 0.25 and absf(w) < 8.0:
		var r := me.global_position - xf.origin
		r.y = 0.0
		push += r * w * w * 0.85 * kp
		if pv:
			pv.rotation.y += w * delta * (1.0 if held else 0.8)
	var up := xf.basis.y.normalized()
	push += Vector3(up.x, 0.0, up.z) * 5.0 * kp
	var tg := tangent(_dtr, _ds)
	push -= tg * _acc_s * 0.45 * kp
	if roof and not held:
		push -= tg * v * 0.2
	if push.length() > 0.05:
		me.apply_wind(push)
	var roll := 0.0
	var cam := get_viewport().get_camera_3d()
	if cam:
		roll = -asin(clampf(up.dot(cam.global_basis.x.normalized()), -0.8, 0.8))
	roll += sin(mtn.now() * 2.3) * (0.05 if held else 0.09) * clampf(absf(w) / 1.8, 0.0, 1.0)
	var a := clampf(delta * 6.0, 0.0, 1.0)
	if bool(me.get("fp_view")):
		me.set("fp_roll", lerpf(float(me.get("fp_roll")), roll, a))
		if pv:
			pv.rotation.z = 0.0
	elif pv:
		pv.rotation.z = lerpf(pv.rotation.z, roll, a)


func _update_cab_display() -> void:
	var gtxt: String = GEAR_NAMES[gear]
	var op := "пульт: никого" if op_pid < 0 else ("пульт: %s" % ("Плато" if op_panel == 0 else "Плечо"))
	if auto_to >= 0:
		op = "едет сама к станции %s" % ("Плато" if auto_to == 0 else "Плечо")
	var tx := "ХОД %s · %.1f м/с · ПОДВЕС %.0f м · %d из %d м · %s" % [gtxt, absf(v), H, int(_main_s()), int(track_len(0)), op]
	if _announce_t > 0.0:
		tx = "ГРОМКАЯ СВЯЗЬ: " + _announce
	if _cab_disp.text != tx:
		_cab_disp.text = tx


func _update_panel(P: Dictionary, delta: float) -> void:
	var now: float = mtn.now()
	var mine := op_panel == int(P["st"]) and op_pid >= 0
	var me_op := mine and _my_panel == int(P["st"])
	var lv: Node3D = P["lever"]
	if me_op and _drag == "lever":
		lv.position.y = _lever_v
	else:
		lv.position.y = move_toward(lv.position.y, _gear_v(gear), delta * 1.6)
	var lfr := inverse_lerp(_gear_v(0), _gear_v(GEARS.size() - 1), lv.position.y)
	_lever_set(P["lever_a"], lerpf(-LEVA, LEVA, clampf(lfr, -0.05, 1.05)))
	var av := absf(v)
	(P["spd"] as Node3D).rotation.z = -lerpf(-2.36, 2.36, clampf(av / 20.0, 0.0, 1.05))
	var sd := "%.1f м/с" % av
	if (P["spd_d"] as Label3D).text != sd:
		(P["spd_d"] as Label3D).text = sd
	(P["tlamp"] as Label3D).visible = av > 10.5 and fmod(now * 4.0, 1.0) < 0.6
	var odo := "ПРОЙДЕНО %03d м" % int(_main_s())
	if (P["odo"] as Label3D).text != odo:
		(P["odo"] as Label3D).text = odo
	(P["hmark"] as Node3D).position.y = _h_v(minf(H, H_MAX + 0.6))
	var ht := _loc_h if me_op else (H if is_nan(_h_tgt) else _h_tgt)
	var hs: Node3D = P["hw"]
	hs.position.y = move_toward(hs.position.y, _h_v(ht), delta * 2.0) if not (me_op and _drag == "hw") else _h_v(ht)
	var hr := "%.1f м" % H
	if (P["hread"] as Label3D).text != hr:
		(P["hread"] as Label3D).text = hr
	var yt := _loc_y if me_op else (yaw if is_nan(_y_tgt) else _y_tgt)
	(P["steer"] as Node3D).rotation.z = yt
	(P["icon"] as Node3D).rotation.z = yaw
	# развилка
	var j := _next_junction()
	var stx := "РАЗВИЛОК НЕТ"
	var caps: Array = P["fork_caps"]
	for k in 2:
		var on := j >= 0 and bool(sw[j]) == (k == 1)
		var m := caps[k] as StandardMaterial3D
		var col := Color(0.15, 1.0, 0.35) if on else Color(0.25, 0.27, 0.28)
		var e := (2.2 if fmod(now * 2.0, 1.0) < 0.75 else 1.4) if on else 0.1
		if m.emission != col or absf(m.emission_energy_multiplier - e) > 0.01:
			m.emission = col
			m.albedo_color = col * 0.6
			m.emission_energy_multiplier = e
	if j >= 0:
		stx = "СТРЕЛКА %d · %s (X)" % [j + 1, "ВПРАВО" if bool(sw[j]) else "ВЛЕВО"]
	if (P["sw_txt"] as Label3D).text != stx:
		(P["sw_txt"] as Label3D).text = stx
	var sgl: Array = P["sig"]
	for k2 in 9:
		_lamp(sgl[k2], float(_sig_on.get(k2, -1.0)) > now and fmod(now * 3.0, 1.0) < 0.6)
	# приколы: огонёк готовности и механизмы
	var leds: Array = P["fun_led"]
	for k3 in FUN_NAMES.size():
		_lamp(leds[k3], _fun_ready(k3))
	_update_fun_devices(P, delta, me_op, now)
	(P["hum"] as AudioStreamPlayer3D).volume_db = -16.0 if mine else -60.0
	# монитор
	var mm: ShaderMaterial = P["mon"]
	var pr := progress()
	var nz := clampf((pr - 0.3) / (MON_LOSE - 0.3), 0.0, 1.0)
	# шаг 115: разбитая кабина — камера трясётся, картинка рябит
	var dn := _dmg_n()
	var dgl := 0.0 if dn == 0 else 0.1 * dn + (0.35 if fmod(now * (0.7 + 0.3 * dn), 2.3) < 0.18 * dn else 0.0)
	mm.set_shader_parameter("noise", clampf(nz * nz * 0.8 + _glitch * 0.5 + dgl, 0.0, 1.0))
	mm.set_shader_parameter("lost", _mon_lost if me_op else 1.0)
	mm.set_shader_parameter("alarm", 1.0 if _hit_t > 0.0 and me_op else 0.0)
	var big := ""
	var top := ""
	var bot := ""
	if not mine:
		big = "ПУЛЬТ СВОБОДЕН\nE — встать за пульт"
		if op_pid >= 0:
			big = "УПРАВЛЯЮТ С\nДРУГОЙ СТАНЦИИ"
	elif not me_op:
		big = "ИДЁТ УПРАВЛЕНИЕ"
	else:
		if _mon_lost > 0.6:
			big = "НЕТ СИГНАЛА" if fmod(now, 1.2) < 0.85 else ""
			big += "\n\nслушайте тех, кто в кабине"
		else:
			top = "КАМ %d · %s%s" % [_cam_mode + 1, CAM_NAMES[_cam_mode], "   СЛАБЫЙ СИГНАЛ" if nz > 0.25 else ""]
		var st_txt := "В ПУТИ"
		if docked >= 0:
			st_txt = "У ПРИЧАЛА: %s" % ("ПЛАТО" if docked == 0 else "ПЛЕЧО")
		if auto_to >= 0:
			st_txt = "ЕДЕТ САМА"
		var sig := ""
		if _sig_last >= 0 and float(_sig_on.get(_sig_last, -1.0)) > now:
			sig = ">> %s <<\n" % SIGNALS[_sig_last]
		bot = "%s%s · ЛЮДЕЙ: %d · УДАРОВ: %d" % [sig, st_txt, _riders_vis(), hits]
		if _hit_t > 0.0:
			bot = sig + "!!! УДАР — ДВЕРИ НАСТЕЖЬ !!!"
	# шаг 115: развилка впереди — крупно, со стрелкой; ближе 40 м — мигает
	var fk := ""
	var fcol := Color(0.4, 1.0, 0.5)
	if me_op and tr == 0 and docked < 0:
		for j9 in _sj.size():
			var dj := float(_sj[j9]) - s
			if dj > 0.0 and dj < 170.0:
				var right := bool(sw[j9])
				if dj > 40.0 or fmod(now * 3.0, 1.0) < 0.65:
					fk = "РАЗВИЛКА %d · %d м · %s" % [j9 + 1, int(dj), "ВПРАВО →" if right else "← ВЛЕВО"]
				fcol = Color(1.0, 0.85, 0.3) if dj < 40.0 else Color(0.4, 1.0, 0.5)
				break
	var fl9: Label3D = P["osd_fork"]
	if fl9.modulate != fcol:
		fl9.modulate = fcol
	for e2 in [["mon_txt", big], ["osd_top", top], ["osd_bot", bot], ["osd_fork", fk]]:
		var lb: Label3D = P[e2[0]]
		if lb.text != String(e2[1]):
			lb.text = e2[1]
	(P["mon_txt"] as Label3D).position.x = MON_C.x + (randf_range(-0.004, 0.004) if _glitch > 0.2 else 0.0)


## Лампа: менять материал только когда изменилось
func _lamp(mi: MeshInstance3D, on: bool) -> void:
	if _lamp_state.get(mi, not on) == on:
		return
	_lamp_state[mi] = on
	mi.material_override = _lamp_on if on else _lamp_off


func _riders_vis() -> int:
	var n := 0
	for d in get_tree().get_nodes_in_group("player"):
		if not bool(d.get("is_dead")) and _in_gondola(d.global_position):
			n += 1
	return n


# ---------------------------------------------------------------------------
#  Игрок: E у пульта, сигналы, поручни, вылет
# ---------------------------------------------------------------------------
func try_socket(d: Node3D) -> bool:
	if d != Network.local_player or bool(d.get("is_bot")):
		return false
	for i in _panels.size():
		var P: Dictionary = _panels[i]
		if d.global_position.distance_to(P["stand"]) < 1.4:
			if op_pid == int(d.peer_id):
				_ask("_req_op", [int(d.peer_id), i, false])
			elif op_pid >= 0:
				mtn.say("Пультом уже управляют")
			else:
				_ask("_req_op", [int(d.peer_id), i, true])
			return true
	return false


func local(d: Node3D, _hp: String, holding: bool, _delta: float) -> void:
	var pid := int(d.peer_id)
	d.set_meta("rw_tool", int(_tool.get(pid, 0)))
	var p := d.global_position
	# временная точка возрождения — у станции
	for st in 2:
		var base: Vector3 = M.RW_A if st == 0 else M.RW_B
		if p.distance_to(base) < 12.0 and int(_cp_set.get(pid, -1)) != st and d.has_method("set_checkpoint"):
			_cp_set[pid] = st
			var bk := -_dir if st == 0 else _dir
			d.set_checkpoint(base + bk * 4.4 + Vector3.UP * 0.6)
	# за пультом
	if op_pid == pid and op_panel >= 0:
		var P: Dictionary = _panels[op_panel]
		var stand: Vector3 = P["stand"]
		d.global_position = Vector3(stand.x, p.y, stand.z)
		d.velocity = Vector3.ZERO
		var face: Node3D = P["face"]
		var to := face.global_position - stand
		d.visual.rotation.y = atan2(-to.x, -to.z)
		d.snow.set_mpose(26, 0.0, face.global_position + face.global_basis.y * -0.25 + face.global_basis.z * 0.1, face.global_basis.x)
		return
	if int(d.snow.mpose) == 26 and _in_panel_zone(p):
		d.snow.set_mpose(0)
	# в кабине: держусь за поручень
	var pressed := holding and not bool(_prev_e.get(pid, false))
	_prev_e[pid] = holding
	_hatch_cd = maxf(_hatch_cd - _delta, 0.0)
	if _in_gondola(p):
		_hold[pid] = holding
		_aboard[pid] = true
		var cx := _cabin.global_transform
		var lp := cx.affine_inverse() * p
		if lp.y <= CHT - 0.2:
			_roof_pin.erase(pid)
		if lp.y > CHT - 0.2:
			# шаг 113: на крыше
			_grip.erase(pid)
			_eject.erase(pid)
			_roof_local(d, lp, holding, pressed, _delta)
			return
		# люк: подпрыгнул под ним — вылез на крышу
		if not holding and _hatch_cd <= 0.0 and d.velocity.y > 1.5 and lp.y > 0.2 and absf(lp.x - HATCH.x) < 0.5 and absf(lp.z - HATCH.z) < 0.45 and not bool(d.get("is_bot")) and ropes != 0:
			_hatch_cd = 0.8
			d.global_position = cx * Vector3(HATCH.x, CHT + 0.15, HATCH.z)
			d.velocity = Vector3.ZERO
			SFX.play(self, d.global_position, "latch", -2.0, 0.9)
			return
		# шаг 116: молоток на щитке у передней стойки — E: взять / повесить
		if not holding:
			_e_used.erase(pid)
		var tlp := Vector2(lp.x - HAMMER_AT.x, lp.z - HAMMER_AT.z).length()
		if pressed and tlp < 0.8 and not bool(d.get("is_bot")):
			_e_used[pid] = true
			var nt := 0 if int(_tool.get(pid, 0)) == 1 else 1
			_tool[pid] = nt
			_ask("_req_tool", [pid, nt])
			SFX.play(self, cx * HAMMER_AT, "clank" if nt != 0 else "latch", -6.0, 1.4)
		if holding and bool(_e_used.get(pid, false)):
			holding = false
		# шаг 116: инструмент в руке — ЛКМ: у пробоины / сорванной двери чиню, иначе просто стучу / варю
		var lmb9: bool = not bool(d.get("is_bot")) and d._held("use_item")
		var t9 := int(_tool.get(pid, 0))
		d.set_meta("rw_tool", t9)
		if lmb9 and t9 == 1:
			var mk9 := _mend_slot(p)
			_grip.erase(pid)
			if mk9 >= 0:
				_mend_local(d, mk9, _delta)
			else:
				_mend_k = -1
				_free_tool(d, 1, _delta)
			return
		if lmb9 and t9 == 2:
			_grip.erase(pid)
			_free_tool(d, 2, _delta)
			return
		if int(d.snow.mpose) == 29:
			d.snow.set_mpose(0)
		if not lmb9 or _mend_k >= 0:
			if int(d.snow.mpose) == 28:
				d.snow.set_mpose(0)
			_mend_k = -1
			_mend_t = maxf(_mend_t - _delta * 0.5, 0.0)
		if holding:
			# шаг 110: шагнул к ближайшему поручню / стойке / петле и взялся за неё руками (кулаки на трубе)
			if not _grip.has(pid):
				_grip[pid] = _grip_choice(lp)
			var G: Dictionary = _grip[pid]
			var sl: Vector3 = G["stand"]
			var tgt := cx * Vector3(sl.x, lp.y, sl.z)
			var np := p.lerp(tgt, clampf(_delta * 7.0, 0.0, 1.0))
			d.global_position = Vector3(np.x, p.y, np.z)
			d.velocity.x = 0.0
			d.velocity.z = 0.0
			var fd: Vector3 = cx.basis * (G["face"] as Vector3)
			d.visual.rotation.y = atan2(-fd.x, -fd.z)
			var vb: Transform3D = d.visual.global_transform
			var gw := cx * (G["pt"] as Vector3)
			var aw := cx.basis * (G["ax"] as Vector3)
			d.snow.set_mpose(27, float(G["k"]), vb.affine_inverse() * gw, (vb.basis.inverse() * aw).normalized())
		else:
			_grip.erase(pid)
			if int(d.snow.mpose) == 27 or int(d.snow.mpose) == 26 or int(d.snow.mpose) == 28:
				d.snow.set_mpose(0)
		_eject.erase(pid)
	else:
		if int(_tool.get(pid, 0)) != 0 and (p.distance_to(_cabin.global_position) > 14.0 or bool(d.get("is_dead"))) and not bool(d.get("is_bot")):
			_tool[pid] = 0
			_ask("_req_tool", [pid, 0])
		if (int(d.snow.mpose) == 26 or int(d.snow.mpose) == 27 or int(d.snow.mpose) == 28 or int(d.snow.mpose) == 29) and p.distance_to(_cabin.global_position) < 8.0:
			_grip.erase(pid)
			d.snow.set_mpose(0)
		# шаг 113: был в кабине на ходу и оказался снаружи — вывалился (в окно, с крыши)
		if _aboard.has(pid):
			_aboard.erase(pid)
			if docked < 0 and not _eject.has(pid):
				_eject[pid] = minf(p.y, _cabin.global_position.y)
		elif _eject.has(pid) and d.is_on_floor() and p.y > float(_eject[pid]) - 20.0 and p.distance_to(_cabin.global_position) > 7.0:
			_eject.erase(pid)       # упал на уступ — повезло
	# вылетел — разбился внизу
	if _eject.has(pid) and p.y < float(_eject[pid]) - 22.0:
		_eject.erase(pid)
		d.kill("Выпал из кабины канатки!\nНа ходу держитесь за поручень (E), не стойте у открытых окон и на краю крыши.\nУ скал, под камнепадом и в ветер — тихий ход")


## Шаг 113: на крыше. E над люком — обратно в салон; держать E — вцепиться (не сдует);
## у оборванного крепления держать E — чинить трос (4 с)
func _roof_local(d: Node3D, lp: Vector3, holding: bool, pressed: bool, delta: float) -> void:
	var cx := _cabin.global_transform
	var pid := int(d.peer_id)
	var bi := _roof_anchor(lp)
	var hz := Vector2(lp.x - HATCH.x, lp.z - HATCH.z).length()
	# шаг 116: ящик со сваркой на крыше — E: взять / положить
	if pressed and Vector2(lp.x - WELD_BOX.x, lp.z - WELD_BOX.z).length() < 0.7 and not bool(d.get("is_bot")):
		var nt2 := 0 if int(_tool.get(pid, 0)) == 2 else 2
		_tool[pid] = nt2
		_ask("_req_tool", [pid, nt2])
		SFX.play(self, cx * WELD_BOX, "clank" if nt2 != 0 else "latch", -6.0, 1.3)
		return
	if pressed and hz < 0.55 and bi < 0 and _hatch_cd <= 0.0:
		_hatch_cd = 0.8
		d.global_position = cx * Vector3(HATCH.x, 0.15, HATCH.z + 0.55)
		d.velocity = Vector3.ZERO
		_fix_t = 0.0
		if int(d.snow.mpose) == 26:
			d.snow.set_mpose(0)
		SFX.play(self, d.global_position, "latch", -2.0, 0.9)
		return
	var lmb: bool = not bool(d.get("is_bot")) and d._held("use_item")
	var t2 := int(_tool.get(pid, 0))
	d.set_meta("rw_tool", t2)
	if holding or (lmb and t2 == 2):
		# вцепился в крышу — держит на месте (и на перекосе не съезжает)
		if not _roof_pin.has(pid):
			_roof_pin[pid] = Vector2(lp.x, lp.z)
		var pn: Vector2 = _roof_pin[pid]
		var pw := cx * Vector3(pn.x, lp.y, pn.y)
		d.global_position = Vector3(pw.x, d.global_position.y, pw.z)
		d.velocity.x = 0.0
		d.velocity.z = 0.0
		if lmb and bi >= 0 and t2 == 2:
			# шаг 115: на колене варю крепление троса горелкой (шаг 116 — ЛКМ)
			var aw := cx * (ANCH[bi] as Vector3)
			# подсел вплотную к креплению (в 0.42 м), с той стороны, откуда подошёл
			var al: Vector3 = ANCH[bi]
			var dl := Vector2(lp.x - al.x, lp.z - al.z)
			if dl.length() < 0.05:
				dl = Vector2(1, 0)
			dl = dl.normalized() * 0.55
			var sw2 := cx * Vector3(al.x + dl.x, lp.y, al.z + dl.y)
			var np2 := d.global_position.lerp(sw2, clampf(delta * 6.0, 0.0, 1.0))
			d.global_position = Vector3(np2.x, d.global_position.y, np2.z)
			var nl2 := cx.affine_inverse() * d.global_position
			_roof_pin[pid] = Vector2(nl2.x, nl2.z)
			var to := aw - d.global_position
			to.y = 0.0
			d.visual.rotation.y = atan2(-to.x, -to.z)
			var vb := (d.visual as Node3D).global_transform
			var seam := aw + cx.basis.y * 0.02
			var bk := (-to.normalized() * 0.45 + cx.basis.y.normalized() * 0.5 + (d.visual as Node3D).global_basis.x.normalized() * 0.65).normalized()
			d.snow.set_mpose(29, _weld_ph, vb.affine_inverse() * seam, (vb.basis.inverse() * bk).normalized())
			_weld_ph += delta
			_fix_t += delta
			_fix_snd -= delta
			if _fix_snd <= 0.0:
				_fix_snd = 0.22
				SFX.play(self, seam, "spark", -6.0, randf_range(0.9, 1.3), 30.0)
				if randf() < 0.3:
					SFX.play(self, seam, "hiss", -10.0, randf_range(1.4, 1.8), 30.0)
			_weld_bi = bi
			if _fix_t >= FIX_T:
				_fix_t = 0.0
				_ask("_req_fix", [pid, 1 << bi])
			return
		if lmb and t2 == 2:
			_free_tool(d, 2, delta)
			return
	else:
		_roof_pin.erase(pid)
	if not lmb:
		_fix_t = maxf(_fix_t - delta * 0.5, 0.0)
	_weld_bi = -1
	if int(d.snow.mpose) == 26 or int(d.snow.mpose) == 27 or int(d.snow.mpose) == 29:
		d.snow.set_mpose(0)


## Шаг 116: ЛКМ с инструментом, когда чинить нечего: молотком — стучу перед собой, горелкой — на колене варю пол
func _free_tool(d: Node3D, t: int, delta: float) -> void:
	var vb := (d.visual as Node3D).global_transform
	var fwd := -vb.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	d.velocity.x = 0.0
	d.velocity.z = 0.0
	var cam: Camera3D = d.get("camera")
	if t == 1:
		var hit := d.global_position + fwd * 0.62 + Vector3.UP * 1.25
		var pph := _mend_ph
		_mend_ph += delta * 1.25
		d.snow.set_mpose(28, _mend_ph, vb.affine_inverse() * hit, (vb.basis.inverse() * -fwd).normalized() * 1.5)
		if fposmod(pph, 1.0) < 0.62 and fposmod(_mend_ph, 1.0) >= 0.62:
			SFX.play(self, hit, "swish" if randf() < 0.5 else "thunk", -10.0, randf_range(0.9, 1.2), 20.0)
			d.add_shake(0.04)
	else:
		var seam := d.global_position + fwd * 0.55 + Vector3.UP * 0.06
		var bk := (-fwd * 0.45 + Vector3.UP * 0.5 + vb.basis.x.normalized() * 0.65).normalized()
		d.snow.set_mpose(29, _weld_ph, vb.affine_inverse() * seam, (vb.basis.inverse() * bk).normalized())
		_weld_ph += delta
		_fix_snd -= delta
		if _fix_snd <= 0.0:
			_fix_snd = 0.25
			SFX.play(self, seam, "spark", -8.0, randf_range(0.9, 1.3), 25.0)


## Шаг 115: точка удара молотком у куска k (в мире) и нормаль стены (внутрь)
func _slot_target(k: int) -> Vector3:
	var cx := _cabin.global_transform
	var sx := 1.0 if k % 2 == 0 else -1.0
	var hw := CW * 0.5
	if k < 2:
		return cx * Vector3(sx * (hw - 0.07), 1.35, -sx * (WIN_Z.x + WIN_Z.y) * 0.5)
	return cx * Vector3(sx * (hw - 0.07), 1.3, 0.0)


## Ближайший разбитый кусок, до которого достаю (−1 — нет)
func _mend_slot(p: Vector3) -> int:
	var best := -1
	var bd := 1.25
	for k in SLOT_N:
		if (dmg & (1 << k)) == 0:
			continue
		var t := _slot_target(k)
		var dd := Vector2(p.x - t.x, p.z - t.z).length()
		if dd < bd:
			bd = dd
			best = k
	return best


## Стучу молотком: встал лицом к стене (в 0.62 м), правая бьёт, левая держит доску; 5 с — готово
func _mend_local(d: Node3D, k: int, delta: float) -> void:
	var cx := _cabin.global_transform
	var sx := 1.0 if k % 2 == 0 else -1.0
	var hw := CW * 0.5
	var zc := -sx * (WIN_Z.x + WIN_Z.y) * 0.5 if k < 2 else 0.0
	var tgt := _slot_target(k)
	var nin: Vector3 = (cx.basis * Vector3(-sx, 0.0, 0.0)).normalized()
	var lp := cx.affine_inverse() * d.global_position
	var stand := cx * Vector3(sx * (hw - 0.85), lp.y, zc)
	var np := d.global_position.lerp(stand, clampf(delta * 6.0, 0.0, 1.0))
	d.global_position = Vector3(np.x, d.global_position.y, np.z)
	d.velocity.x = 0.0
	d.velocity.z = 0.0
	d.visual.rotation.y = atan2(nin.x, nin.z)
	# гвоздь: доски прибиваю по очереди (1.3 → 1.65 → 0.95 → 2.0 м, потом косую) — к раме справа от себя
	var hit := tgt
	var left_off := 0.6
	if k < 2:
		var q := clampi(int(_mend_t / MEND_T * 5.0), 0, 4)
		var wl := WIN_Z.y - WIN_Z.x
		var hy: float = [1.3, 1.65, 0.95, 2.0, 1.45][q]
		var hz := zc + (sx * (wl * 0.5 - 0.07) if q < 4 else 0.0)
		hit = cx * Vector3(sx * (hw - 0.135), hy, hz)
		left_off = (wl - 0.14) if q < 4 else (wl * 0.5 - 0.07)
	# левая держится за раму слева (сколько до неё от гвоздя — в длине mdir сверх 1)
	# взгляд — на гвоздь, чуть ближе к себе (чтобы в кадре был и боёк в замахе)
	var mid := cx * Vector3(sx * (hw - 0.135), (cx.affine_inverse() * hit).y, zc)
	var vb := (d.visual as Node3D).global_transform
	if _mend_k != k:
		_mend_k = k
		_mend_ph = 0.0
	var pph := _mend_ph
	_mend_ph += delta * 1.25
	d.snow.set_mpose(28, _mend_ph, vb.affine_inverse() * hit, (vb.basis.inverse() * nin).normalized() * (1.0 + left_off))
	if fposmod(pph, 1.0) < 0.62 and fposmod(_mend_ph, 1.0) >= 0.62:
		# удар!
		SFX.play(self, hit, "clank" if k >= 2 else "thunk", -2.0, randf_range(0.95, 1.2), 30.0)
		if k < 2:
			SFX.play(self, hit, "clank", -12.0, 2.2, 20.0)
		var chips := FX.particles(Color(0.62, 0.45, 0.26) if k < 2 else Color(1.0, 0.75, 0.3), 10, 0.45, 0.025, 1.2, 3.0, Vector3(0, -9, 0), 70.0, true, true)
		add_child(chips)
		chips.global_position = hit
		chips.emitting = true
		get_tree().create_timer(1.0).timeout.connect(chips.queue_free)
		d.add_shake(0.07)
	_mend_t += delta
	if _mend_t >= MEND_T:
		_mend_t = 0.0
		_ask("_req_mend", [int(d.peer_id), k])


## Своя камера плавно поворачивается к делу (лицом к стене / к шву): от 1-го лица не смотрю себе в плечо
func _look_at_work(d: Node3D, at: Vector3, delta: float) -> void:
	if d != Network.local_player:
		return
	var pv: Node3D = d.get("camera_pivot")
	if pv == null:
		return
	# смотрю прямо на то, что делаю (от глаза — где сейчас камера)
	var cam: Camera3D = d.get("camera")
	var eye: Vector3 = cam.global_position if cam else d.global_position + Vector3.UP * 1.6
	var to := at - eye
	var k := clampf(delta * 5.0, 0.0, 1.0)
	pv.rotation.y = lerp_angle(pv.rotation.y, atan2(-to.x, -to.z), k)
	pv.rotation.x = lerpf(pv.rotation.x, clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.35, 0.8), k * 0.7)


## Оборванное крепление рядом (на крыше) — его номер, иначе −1
func _roof_anchor(lp: Vector3) -> int:
	if ropes == 0 or ropes == 3:
		return -1
	for k in 2:
		if (ropes & (1 << k)) == 0:
			var a: Vector3 = ANCH[k]
			if Vector2(lp.x - a.x, lp.z - a.z).length() < 0.85:
				return k
	return -1


func _in_panel_zone(p: Vector3) -> bool:
	for P in _panels:
		if p.distance_to(P["stand"]) < 3.0:
			return true
	return false


## Шаг 110: за что взяться в салоне (в осях кабины): поручни вдоль бортов, две стойки, петли под потолком.
## Возвращает: k (0 — горизонтальный поручень, 1 — стойка, 2 — петля), pt — середина хвата, ax — ось трубы,
## stand — где встать, face — куда смотреть
func _grip_choice(lp: Vector3) -> Dictionary:
	var hw := CW * 0.5
	var best := {}
	var bd := INF
	var cands: Array = []
	for sx in [-1.0, 1.0]:
		for seg in ([[-CL * 0.5 + 0.95, -0.95]] if sx > 0.0 else [[0.95, CL * 0.5 - 0.95]]):
			var z := clampf(lp.z, float(seg[0]), float(seg[1]))
			cands.append({"k": 0, "pt": Vector3(sx * (hw - 0.17), 1.05, z), "ax": Vector3(0, 0, 1),
				"stand": Vector3(sx * (hw - 0.62), 0.0, z), "face": Vector3(sx, 0, 0)})
	for sz in [-1.0, 1.0]:
		var pc := Vector3(0.0, 0.0, sz * 1.25)
		var dv := Vector3(lp.x, 0.0, lp.z) - pc
		if dv.length() < 0.05:
			dv = Vector3(0, 0, -sz)
		dv = dv.normalized()
		cands.append({"k": 1, "pt": pc + Vector3.UP * 1.22, "ax": Vector3.UP, "stand": pc + dv * 0.4, "face": -dv})
	for sx2 in [-1.0, 1.0]:
		for k in 7:
			var zl := -1.35 + k * 0.45
			# петля — над правым плечом: лицом туда, где правая рука смотрит на петлю
			cands.append({"k": 2, "pt": Vector3(sx2 * 0.78, 1.835, zl), "ax": Vector3(0, 0, 1),
				"stand": Vector3(sx2 * 0.56, 0.0, zl + sx2 * 0.1), "face": Vector3(0, 0, -sx2)})
	for c in cands:
		var st: Vector3 = c["stand"]
		var dd := Vector2(st.x - lp.x, st.z - lp.z).length() + (0.15 if int(c["k"]) == 2 else 0.0)
		if dd < bd:
			bd = dd
			best = c
	return best


func hint(me: Node3D) -> String:
	var p := me.global_position
	var pid := int(me.peer_id)
	if op_pid == pid:
		return ""
	if _in_gondola(p):
		var lp := _cabin.global_transform.affine_inverse() * p
		var tl9 := int(_tool.get(pid, 0))
		if lp.y > CHT - 0.2:
			if _roof_anchor(lp) >= 0:
				if tl9 != 2:
					return "Оборванный трос! Нужна сварка — она в жёлтом ящике в переднем конце крыши (E у ящика)"
				return "Держи ЛКМ — варить крепление троса: %d%%" % int(_fix_t / FIX_T * 100.0)
			if Vector2(lp.x - WELD_BOX.x, lp.z - WELD_BOX.z).length() < 0.7:
				return "E — положить сварку" if tl9 == 2 else "E — взять сварку (варить оборванный трос)"
			if Vector2(lp.x - HATCH.x, lp.z - HATCH.z).length() < 0.55:
				return "E — спуститься в салон через люк"
			if ropes == 1 or ropes == 2:
				return "Крыша! Оборванное крепление — у %s конца лебёдки. Держи E — вцепиться (на ходу сдувает)" % ("переднего" if ropes == 2 else "заднего")
			return "Крыша! Держи E — вцепиться: на ходу сдувает, края скользкие. Над люком E — вниз"
		var uh := absf(lp.x - HATCH.x) < 0.5 and absf(lp.z - HATCH.z) < 0.45
		if Vector2(lp.x - HAMMER_AT.x, lp.z - HAMMER_AT.z).length() < 0.8:
			return "E — повесить молоток" if tl9 == 1 else "E — взять молоток (заколачивать пробоины)"
		if dmg != 0:
			var mk9 := _mend_slot(p)
			if tl9 == 1 and mk9 >= 0:
				return "Держи ЛКМ — %s: %d%%" % ["заколотить пробоину" if mk9 < 2 else "вправить дверь", int(_mend_t / MEND_T * 100.0)]
			if tl9 == 1:
				return "Молоток в руке — подойди к пробоине или сорванной двери и держи ЛКМ"
			if ropes == 3:
				return "ПРОБОИНА — можно выпасть! Молоток — на красном щитке у передней жёлтой стойки (E)"
		if ropes == 1 or ropes == 2:
			if uh:
				return "Подпрыгни (пробел) — вылезти через люк на крышу и починить трос"
			return "ОБОРВАН ТРОС — кабину перекосило! Почините: под люком у жёлтой стойки подпрыгни, на крыше сварка в жёлтом ящике в переднем конце — держи ЛКМ у крепления"
		if uh:
			return "Подпрыгни под люком — вылезти на крышу (осторожно, на ходу сдувает)"
		if v != 0.0 or docked < 0:
			return "1–9 — сигналы оператору (1 вперёд · 2 назад · 3 быстрее · 4 медленнее · 5 СТОП · 6 выше · 7 ниже · 8 поворот · 9 стрелка). Держи E — держаться за поручень"
		return "Кабина у причала. Кто-то — за пульт в будке (E), остальные подсказывают отсюда (1–9 и голосом)"
	for i in _panels.size():
		var P: Dictionary = _panels[i]
		if p.distance_to(P["stand"]) < 1.6:
			if op_pid >= 0:
				return "Пультом управляют (%s)" % ("здесь" if op_panel == i else "с другой станции")
			return "E — встать за пульт: управлять кабиной (до середины пути её видно на мониторе, дальше — только подсказки из кабины)"
	for st in 2:
		var base: Vector3 = M.RW_A if st == 0 else M.RW_B
		if p.distance_to(base) < 9.0 and docked != st and _riders_vis() == 0 and auto_to < 0:
			return "Кабины нет у станции. Вызовите её с пульта в будке (E, потом C)"
	return ""


func _unhandled_input(_e: InputEvent) -> void:
	pass


func _input(event: InputEvent) -> void:
	var me = Network.local_player
	if me == null or bool(me.get("is_dead")):
		return
	if _my_panel >= 0:
		_panel_input(event)
		return
	var ke := event as InputEventKey
	if ke == null or not ke.pressed or ke.echo:
		return
	var k: int = ke.physical_keycode
	if k >= KEY_1 and k <= KEY_9 and _cabin != null and _in_gondola(me.global_position):
		_ask("_req_sig", [int(me.peer_id), k - KEY_1])
		mtn.say("Сигнал оператору: %s" % SIGNALS[k - KEY_1])
		get_viewport().set_input_as_handled()


func _panel_input(event: InputEvent) -> void:
	var me = Network.local_player
	var pid := int(me.peer_id)
	if event is InputEventKey:
		var ke := event as InputEventKey
		var k := ke.physical_keycode
		get_viewport().set_input_as_handled()
		if ke.echo or not ke.pressed:
			if not ke.pressed and (k == KEY_A or k == KEY_D or k == KEY_LEFT or k == KEY_RIGHT):
				_snap_yaw()
			return
		match k:
			KEY_E, KEY_ESCAPE:
				_ask("_req_op", [pid, _my_panel, false])
			KEY_W, KEY_UP:
				_ctl(0, mini(gear + 1, GEARS.size() - 1))
			KEY_S, KEY_DOWN:
				_ctl(0, maxi(gear - 1, 0))
			KEY_SPACE:
				_ctl(4, 0)
			KEY_X:
				_ctl(10, 0)
			KEY_V:
				_next_cam()
			KEY_C:
				_ctl(5, 0)
			KEY_1:
				pass                    # турбо: держать 1 (см. _process)
			KEY_2:
				_crank_acc = CRANK_FULL
				_fire(1)
			KEY_3:
				if _fun_ready(2):
					_brk = 1.0
				_fire(2)
			KEY_4:
				_fire(3)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		get_viewport().set_input_as_handled()
		var u := _face_uv(mb.position)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.pressed:
				return
			var sg := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			match _pick(u):
				"hw":
					_set_hw(_loc_h - sg * 0.5)
				"steer":
					_turn_steer(sg * 0.06)
					_snap_yaw()
				"lever":
					_ctl(0, clampi(gear + int(sg), 0, GEARS.size() - 1))
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			var id := _pick(u)
			_drag = ""
			match id:
				"lever":
					_drag = "lever"
					_drag_g = gear
					_lever_v = clampf(u.y, _gear_v(0), _gear_v(GEARS.size() - 1))
					_drag_lever(u.y)
				"hw":
					_drag = "hw"
					_set_hw(_h_from_v(u.y))
				"steer":
					_drag = "steer"
					_drag_a = atan2(u.y - ST_C.y, u.x - ST_C.x)
				"f0":
					# ТУРБО: тянуть ползунок вверх
					_drag = "turbo"
					_xt_loc = _xt_from(u.y)
				"f1":
					_drag = "crank"
					_drag_a = atan2(u.y - FUN_Y, u.x - FUN_X[1])
				"f2":
					_drag = "breaker"
					_drag_y0 = u.y + _brk * 0.13
				"f3":
					_fire(3)
				_:
					_click(id)
		else:
			if _drag == "steer":
				_snap_yaw()
			if _drag == "lever":
				SFX.play(self, (_panels[_my_panel]["face"] as Node3D).global_position, "latch", -8.0, 1.4)
			_drag = ""
	elif event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
		var mmo := event as InputEventMouseMotion
		var u2 := _face_uv(mmo.position)
		if _drag == "":
			var hov := _pick(u2)
			Input.set_default_cursor_shape(Input.CURSOR_ARROW if hov == "" else (Input.CURSOR_DRAG if hov in ["lever", "hw", "steer", "f0", "f1", "f2"] else Input.CURSOR_POINTING_HAND))
			return
		var at: Vector3 = (_panels[_my_panel]["face"] as Node3D).global_position
		match _drag:
			"lever":
				_lever_v = clampf(u2.y, _gear_v(0) - 0.01, _gear_v(GEARS.size() - 1) + 0.01)
				_drag_lever(u2.y)
			"hw":
				_set_hw(_h_from_v(u2.y))
			"steer":
				if u2.distance_to(ST_C) < 0.025:
					return
				var a := atan2(u2.y - ST_C.y, u2.x - ST_C.x)
				var da := wrapf(a - _drag_a, -PI, PI)
				_drag_a = a
				_turn_steer(da)
			"turbo":
				var nx := _xt_from(u2.y)
				if nx > _xt_loc + 0.08:
					SFX.play(self, at, "ratchet", -14.0, 1.6)
				_xt_loc = nx
			"crank":
				var c1 := Vector2(FUN_X[1], FUN_Y)
				if u2.distance_to(c1) < 0.015:
					return
				var a2 := atan2(u2.y - c1.y, u2.x - c1.x)
				var da2 := wrapf(a2 - _drag_a, -PI, PI)
				_drag_a = a2
				_crank_a += da2
				if _fun_ready(1):
					_crank_acc += absf(da2)
					_crank_sound()
					if _crank_acc >= CRANK_FULL:
						_crank_acc = CRANK_FULL
						_drag = ""
						_fire(1)
			"breaker":
				var nb := clampf((_drag_y0 - u2.y) / 0.13, 0.0, 1.0)
				if not _fun_ready(2):
					nb = minf(nb, _brk)
				if nb > _brk + 0.05:
					SFX.play(self, at, "ratchet", -12.0, 0.8)
				_brk = nb
				if _brk >= 0.95 and _fun_ready(2):
					_drag = ""
					SFX.play(self, at, "thunk", 0.0, 0.6)
					_fire(2)


func _ctl(what: int, val: int) -> void:
	var me = Network.local_player
	_ask("_req_ctl", [int(me.peer_id), what, val])
	var P: Dictionary = _panels[_my_panel]
	var at: Vector3 = (P["face"] as Node3D).global_position
	match what:
		0:
			SFX.play(self, at, "ratchet", -6.0, 1.3)
		3, 10:
			SFX.play(self, at, "latch", -4.0, 1.2)
		4:
			SFX.play(self, at, "thunk", -2.0, 0.8)
			_press(P["stop"])
		5:
			SFX.play(self, at, "click", -4.0, 0.9)
			_press(P["call"])


## Что под мышью на пульте
func _pick(u: Vector2) -> String:
	if absf(u.x - LEV_X) < 0.09 and u.y > _gear_v(0) - 0.07 and u.y < _gear_v(GEARS.size() - 1) + 0.07:
		return "lever"
	if absf(u.x - HS_X) < 0.1 and u.y > _h_v(H_MAX) - 0.05 and u.y < _h_v(H_MIN) + 0.05:
		return "hw"
	if u.distance_to(ST_C) < WHEEL_R + 0.045:
		return "steer"
	if absf(u.x - FORK_C.x) < 0.16 and absf(u.y - FORK_C.y) < 0.09:
		return "swl" if u.x < FORK_C.x else "swr"
	var spots := {"stop": [STOP_C, 0.1], "call": [CALL_C, 0.065], "cam": [CAM_C, 0.065]}
	for k4 in FUN_NAMES.size():
		spots["f%d" % k4] = [Vector2(FUN_X[k4], FUN_Y), 0.1]
	for k in spots:
		if u.distance_to(spots[k][0]) < float(spots[k][1]):
			return String(k)
	return ""


func _click(id: String) -> void:
	match id:
		"stop":
			_ctl(4, 0)
		"swl", "swr":
			_ctl(10, 1 if id == "swl" else 2)
			if _my_panel >= 0:
				_press((_panels[_my_panel]["fork_btns"] as Array)[0 if id == "swl" else 1])
		"call":
			_ctl(5, 0)
		"cam":
			_next_cam()


func _process(delta: float) -> void:
	if Engine.get_process_frames() > 30:
		_low_view()
	if _my_panel < 0:
		return
	var me = Network.local_player
	if me == null:
		return
	var pid := int(me.peer_id)
	_crank_snd = maxf(_crank_snd - delta, 0.0)
	if get_viewport().scaling_3d_scale < 1.0:
		get_viewport().scaling_3d_scale = 1.0
	# клавиши крутят штурвалы так же, как мышь
	var hd := 0.0
	var rd := 0.0
	if Input.is_physical_key_pressed(KEY_R):
		hd -= 1.0
	if Input.is_physical_key_pressed(KEY_F):
		hd += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		rd += 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		rd -= 1.0
	# турбо: держу 1 — ползунок вверх; отпустил — пружинит вниз; на хост — 0…100
	if Input.is_physical_key_pressed(KEY_1) and _ovh_t <= 0.0 and docked < 0:
		_xt_loc = move_toward(_xt_loc, 1.0, delta * 2.0)
	elif _drag != "turbo" or _ovh_t > 0.0:
		_xt_loc = move_toward(_xt_loc, 0.0, delta * (6.0 if _ovh_t > 0.0 else 2.5))
	_xt_send_t -= delta
	var xi := int(round(_xt_loc * 100.0))
	if _xt_send_t <= 0.0 and (xi != _xt_sent or (xi > 0 and _xt_send_t <= -0.3)):
		_xt_send_t = 0.08
		_xt_sent = xi
		_ask("_req_ctl", [pid, 11, xi])
	if hd != 0.0:
		_set_hw(_loc_h + hd * H_RATE * delta)
	if rd != 0.0:
		_turn_steer(rd * YAW_RATE * delta)
	_send_tgt_t -= delta
	if _tgt_dirty and _send_tgt_t <= 0.0:
		_send_tgt_t = 0.05
		_tgt_dirty = false
		_ask("_req_ctl", [pid, 6, int(round(_loc_h * 100.0))])
		_ask("_req_ctl", [pid, 7, int(round(_loc_y * 1000.0))])
	# монитор: камера на тросе за кабиной; к середине пути — помехи, потом нет сигнала
	_mon_lost = move_toward(_mon_lost, 1.0 if progress() >= MON_LOSE else 0.0, delta * 0.5)
	if _mon_lost < 0.98:
		_update_mon(delta)
		_mon_frame += 1
		if _mon_frame % 2 == 0:
			_mon_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _make_ui() -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.layer = 50
	cl.visible = false
	add_child(cl)
	var lb := Label.new()
	lb.text = "Мышью: ручка хода, рукоять лебёдки, штурвал поворота, механизмы приколов (колёсико тоже работает)\nW/S ход · R/F выше/ниже · A/D поворот · X стрелка · V камера · пробел СТОП · C вызвать · 1–4 приколы · E отойти"
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.add_theme_font_size_override("font_size", 16)
	lb.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	lb.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lb.add_theme_constant_override("outline_size", 6)
	lb.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	lb.offset_top = -52.0
	lb.offset_bottom = -6.0
	cl.add_child(lb)
	return cl




func _enter_panel(i: int) -> void:
	var me = Network.local_player
	if me == null:
		return
	_my_panel = i
	me.input_blocked = true
	me.velocity = Vector3.ZERO
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_panels[i]["cam"] as Camera3D).make_current()
	for c in (me.visual as Node3D).get_children():
		if c is Node3D and c.visible:
			(c as Node3D).visible = false
			_hid_body.append(c)
	_hidden.clear()
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if cl != _ui and cl.visible:
			_hidden.append(cl)
			cl.visible = false
	_ui.visible = true
	_drag = ""
	_loc_h = H if is_nan(_h_tgt) else _h_tgt
	_loc_y = yaw
	_tgt_dirty = false
	_mon_pos = Vector3.INF
	_mon_lost = 1.0 if progress() >= MON_LOSE else 0.0
	_prev_scale = get_viewport().scaling_3d_scale
	get_viewport().scaling_3d_scale = 1.0


func _exit_panel() -> void:
	var me = Network.local_player
	_ui.visible = false
	for n in _hidden:
		if is_instance_valid(n):
			(n as CanvasLayer).visible = true
	_hidden.clear()
	_my_panel = -1
	_drag = ""
	if _prev_scale > 0.0:
		get_viewport().scaling_3d_scale = _prev_scale
		_prev_scale = -1.0
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if me == null:
		return
	me.input_blocked = false
	for c in _hid_body:
		if is_instance_valid(c):
			(c as Node3D).visible = true
	_hid_body.clear()
	if me.camera:
		(me.camera as Camera3D).make_current()
	Input.mouse_mode = _prev_mouse if _prev_mouse != Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_CAPTURED
	me.snow.set_mpose(0)


# ---------------------------------------------------------------------------
#  Боты
# ---------------------------------------------------------------------------
func bot_target(bot: Node3D, owner_node: Node3D) -> Vector3:
	var o := owner_node.global_position
	var b := bot.global_position
	# хозяин в кабине у причала, пульт свободен — бот к пульту своей станции
	if _in_gondola(o) and docked >= 0:
		if op_pid >= 0 and op_pid != int(bot.peer_id):
			return Vector3.INF
		var P: Dictionary = _panels[docked]
		if b.distance_to(P["stand"]) < 60.0:
			return P["stand"]
		return Vector3.INF
	if op_pid == int(bot.peer_id):
		return (_panels[op_panel]["stand"] as Vector3)
	# хозяин за пультом — бот садится в кабину (если она у этой станции) и едет
	if op_pid == int(owner_node.peer_id) and _in_gondola(b):
		return b
	if op_pid == int(owner_node.peer_id) and docked == op_panel and not _in_gondola(b):
		if b.distance_to(_cabin.global_position) < 9.0 and multiplayer.is_server():
			bot.teleport_to(_cabin.global_position + _cabin.global_basis.z * 1.2 + Vector3.UP * 0.4)
			return Vector3.INF
		return _cabin.global_position
	return Vector3.INF


func bot_crank(bot: Node3D, owner_node: Node3D) -> bool:
	if op_pid == int(bot.peer_id):
		return true
	var t := bot_target(bot, owner_node)
	if t == Vector3.INF:
		return false
	var b := bot.global_position
	for P in _panels:
		if t.distance_to(P["stand"]) < 0.1:
			return Vector2(t.x - b.x, t.z - b.z).length() < 0.9
	return false




## Точка маршрута (a — вдоль, l — вбок) на высоте троса: k — доля пути (0 — Плато, 1 — Плечо)
func _wy(a: float, l: float, k: float) -> Vector3:
	var p := M.RW_A + _dir * a + _side * l
	p.y = lerpf(M.RW_A.y, M.RW_B.y, clampf(k, 0.0, 1.0)) + H_DOCK
	return p


## Мировая точка → (вдоль, вбок) в системе маршрута
func _al(p: Vector3) -> Vector2:
	var d := p - M.RW_A
	return Vector2(d.dot(_dir), d.dot(_side))


## Кабина под камнепадом (индекс препятствия или −1)
func _rock_at(s_: float, yw: float) -> int:
	if tr != 0:
		return -1
	var e := _ext(yw)
	for i in _obs.size():
		var o: Array = _obs[i]
		if int(o[0]) == ROCK and s_ + e.x >= float(o[1]) and s_ - e.x <= float(o[2]):
			return i
	return -1


func _rock_c() -> float:
	return fposmod(_rock_t, float(ROCK_T[2]))


## Успеет ли кабина проскочить камнепад до следующего обвала: d — до начала, ln — длина, разгон с vv до vmax
func _rock_safe(d: float, ln: float, ex: float, vv: float, vmax: float, react: float) -> bool:
	if rock_ph != 0:
		return false
	var left := ROCK_HIT - _rock_c()
	var dist := maxf(d, 0.0) + ln + 2.0 * ex + 0.6
	var v0 := clampf(vv, 0.0, vmax)
	var ta := (vmax - v0) / ACC
	var da := v0 * ta + 0.5 * ACC * ta * ta
	var t := (sqrt(v0 * v0 + 2.0 * ACC * dist) - v0) / ACC
	if dist > da:
		t = ta + (dist - da) / vmax
	return left > t + react


## Сколько метров пройдено по главному тросу (в тупике — от развилки)
func _main_s() -> float:
	return s if tr == 0 else float(_sj[tr - 1]) + s


## Доля пути (для монитора: с середины — нет сигнала)
func progress() -> float:
	return clampf(_main_s() / maxf(track_len(0), 1.0), 0.0, 1.0)


## Монитор пульта: своя маленькая «камера на тросе», рисует только у того, кто за пультом
func _make_monitor() -> void:
	_mon_vp = SubViewport.new()
	_mon_vp.size = Vector2i(480, 296)
	_mon_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mon_vp.msaa_3d = Viewport.MSAA_DISABLED
	_mon_vp.positional_shadow_atlas_size = 0
	_mon_vp.audio_listener_enable_3d = false
	add_child(_mon_vp)
	_mon_cam = Camera3D.new()
	_mon_cam.fov = 62.0
	_mon_cam.near = 0.3
	_mon_cam.far = 320.0
	_mon_vp.add_child(_mon_cam)
	_mon_cam.current = true


## Штурвал на пульте: обод, спицы, ступица и ручка — крутится целиком
func _wheel(face: Node3D, c: Vector2, col: Color, spokes: int) -> Node3D:
	var n := Node3D.new()
	face.add_child(n)
	n.position = Vector3(c.x, c.y, 0.0)
	_mesh(face, _cyl(0.022, 0.022, 0.06, 12), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c.x, c.y, 0.03)), _m_metal)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = col
	rm.roughness = 0.35
	rm.metallic = 0.2
	var tor := TorusMesh.new()
	tor.inner_radius = WHEEL_R - 0.016
	tor.outer_radius = WHEEL_R + 0.008
	tor.rings = 32
	tor.ring_segments = 8
	_mesh(n, tor, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.065)), rm)
	for k in spokes:
		var a := PI * 0.5 + TAU * k / float(spokes)
		var mid := Vector3(cos(a), sin(a), 0.0) * (WHEEL_R * 0.5)
		_mesh(n, _bm(Vector3(0.016, WHEEL_R - 0.01, 0.012)), Transform3D(Basis(Vector3.BACK, a - PI * 0.5), mid + Vector3(0, 0, 0.065)), _m_metal)
	_mesh(n, _cyl(0.034, 0.034, 0.03, 16), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.07)), _m_dark)
	# ручка на ободе (и метка «вдоль троса» сверху)
	_mesh(n, _cyl(0.011, 0.011, 0.07, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, WHEEL_R - 0.004, 0.1)), _m_metal)
	var hs := SphereMesh.new()
	hs.radius = 0.02
	hs.height = 0.04
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.95, 0.85, 0.2)
	hm.roughness = 0.3
	_mesh(n, hs, Transform3D(Basis.IDENTITY, Vector3(0, WHEEL_R - 0.004, 0.14)), hm)
	return n


## Обвод корпуса (скруглённый прямоугольник в плане): [точка (x, z), наружная нормаль]; у дверей — точки краёв проёма
func _perim() -> Array:
	var hw := CW * 0.5
	var hl := CL * 0.5
	var r := CR
	var cs := [Vector2(hw - r, hl - r), Vector2(-hw + r, hl - r), Vector2(-hw + r, -hl + r), Vector2(hw - r, -hl + r)]
	var P: Array = []
	for c in 4:
		for k in 7:
			var a := PI * 0.5 * c + PI * 0.5 * k / 6.0
			var n := Vector2(cos(a), sin(a))
			P.append([(cs[c] as Vector2) + n * r, n])
		if c == 1:
			for zz in [WIN_Z.y, WIN_Z.x, DOOR_HZ, -DOOR_HZ, -WIN_Z.x, -WIN_Z.y]:
				P.append([Vector2(-hw, zz), Vector2(-1, 0)])
		elif c == 3:
			for zz2 in [-WIN_Z.y, -WIN_Z.x, -DOOR_HZ, DOOR_HZ, WIN_Z.x, WIN_Z.y]:
				P.append([Vector2(hw, zz2), Vector2(1, 0)])
	return P


## Шаг 113: точка обвода (x, z) — в проёме открытого окна
func _win_at(m: Vector2) -> bool:
	var hw := CW * 0.5
	return absf(m.x) > hw - 0.01 and absf(m.y) > WIN_Z.x and absf(m.y) < WIN_Z.y


func _hn(n: Vector2, dd: float, dy: float) -> Vector3:
	return Vector3(n.x * dy, dd, n.y * dy).normalized()


## Обшивка: «труба» по обводу через кольца [высота, отступ внутрь]; gap — пропустить дверные проёмы;
## flip — смотрит внутрь (обшивка салона); cap — закрыть верх (1) / низ (−1) последнего/первого кольца
func _hull_mesh(rings: Array, gap: bool, flip: bool, cap := 0) -> ArrayMesh:
	var P := _perim()
	var hw := CW * 0.5
	var n := P.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in rings.size() - 1:
		var y0: float = rings[k][0]
		var d0: float = rings[k][1]
		var y1: float = rings[k + 1][0]
		var d1: float = rings[k + 1][1]
		for i in n:
			var A: Array = P[i]
			var B: Array = P[(i + 1) % n]
			var pa: Vector2 = A[0]
			var pb: Vector2 = B[0]
			var na: Vector2 = A[1]
			var nb: Vector2 = B[1]
			if gap:
				var mid := (pa + pb) * 0.5
				if absf(mid.x) > hw - 0.01 and absf(mid.y) < DOOR_HZ:
					continue
				# шаг 113: открытые окна — без стекла и обшивки выше подоконника
				if minf(y0, y1) >= WIN_Y.x - 0.001 and maxf(y0, y1) <= WIN_Y.y + 0.001 and _win_at(mid):
					continue
			var q0 := Vector3(pa.x - na.x * d0, y0, pa.y - na.y * d0)
			var q1 := Vector3(pb.x - nb.x * d0, y0, pb.y - nb.y * d0)
			var q2 := Vector3(pb.x - nb.x * d1, y1, pb.y - nb.y * d1)
			var q3 := Vector3(pa.x - na.x * d1, y1, pa.y - na.y * d1)
			var NA := _hn(na, d1 - d0, y1 - y0)
			var NB := _hn(nb, d1 - d0, y1 - y0)
			var tri: Array = [[q0, NA], [q1, NB], [q2, NB], [q0, NA], [q2, NB], [q3, NA]]
			if flip:
				tri = [[q0, -NA], [q2, -NB], [q1, -NB], [q0, -NA], [q3, -NA], [q2, -NB]]
			for t in tri:
				st.set_normal(t[1])
				st.add_vertex(t[0])
	if cap != 0:
		var rr: Array = rings[rings.size() - 1] if cap > 0 else rings[0]
		var y: float = rr[0]
		var d: float = rr[1]
		var up := (cap > 0) != flip
		var nn := Vector3.UP if up else Vector3.DOWN
		var cc := Vector3(0, y, 0)
		for i2 in n:
			var A2: Array = P[i2]
			var B2: Array = P[(i2 + 1) % n]
			var qa := Vector3((A2[0] as Vector2).x - (A2[1] as Vector2).x * d, y, (A2[0] as Vector2).y - (A2[1] as Vector2).y * d)
			var qb := Vector3((B2[0] as Vector2).x - (B2[1] as Vector2).x * d, y, (B2[0] as Vector2).y - (B2[1] as Vector2).y * d)
			# шаг 113: крышка — с обеих сторон (крыша сверху раньше не рисовалась); нормаль — куда смотрит
			for q in [cc, qa, qb, cc, qb, qa]:
				st.set_normal(nn)
				st.add_vertex(q)
	return st.commit()


func _cmat(col: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _glow(col: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = e
	return m


## Схема маршрута в кабине: зелёный трос, красные тупики, оранжевые препятствия, огонёк — где мы
func _build_map(pos: Vector3) -> void:
	var mp := Node3D.new()
	_cabin.add_child(mp)
	mp.position = pos
	mp.rotation = Vector3(0.2, 0.0, 0.0)
	_mesh(mp, _bm(Vector3(1.16, 0.7, 0.05)), Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.03)), _m_dark)
	var bg := StandardMaterial3D.new()
	bg.albedo_color = Color(0.03, 0.07, 0.1)
	bg.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var q := QuadMesh.new()
	q.size = Vector2(1.08, 0.62)
	_mesh(mp, q, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.003)), bg, false)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for T in _tr:
		for p in (T["p"] as PackedVector3Array):
			var a := _al(p)
			lo = Vector2(minf(lo.x, a.x), minf(lo.y, a.y))
			hi = Vector2(maxf(hi.x, a.x), maxf(hi.y, a.y))
	_map_k = minf(0.92 / (hi.x - lo.x), 0.44 / (hi.y - lo.y))
	_map_mid = (lo + hi) * 0.5
	var green := _glow(Color(0.35, 1.0, 0.5), 1.6)
	var redm := _glow(Color(1.0, 0.25, 0.2), 1.4)
	var orange := _glow(Color(1.0, 0.6, 0.15), 1.8)
	var whitem := _glow(Color(0.95, 0.95, 0.9), 1.2)
	for t_ in _tr.size():
		var pv: PackedVector3Array = (_tr[t_] as Dictionary)["p"]
		for i in pv.size() - 1:
			var a0 := _map_pt(_al(pv[i]))
			var a1 := _map_pt(_al(pv[i + 1]))
			var d := a1 - a0
			_mesh(mp, _bm(Vector3(d.length() + 0.008, 0.008 if t_ == 0 else 0.006, 0.004)),
				Transform3D(Basis(Vector3.BACK, atan2(d.y, d.x)), (a0 + a1) * 0.5), green if t_ == 0 else redm)
	for o in _obs:
		var c := _map_pt(_al(cable_pt(0, (float(o[1]) + float(o[2])) * 0.5)))
		_mesh(mp, _bm(Vector3(0.018, 0.018, 0.006)), Transform3D(Basis(Vector3.BACK, PI * 0.25), c), orange)
	for st in 2:
		var c2 := _map_pt(_al(cable_pt(0, 0.0 if st == 0 else track_len(0))))
		_mesh(mp, _bm(Vector3(0.03, 0.03, 0.006)), Transform3D(Basis.IDENTITY, c2), whitem)
		_label(mp, "ПЛАТО" if st == 0 else "ПЛЕЧО", c2 + Vector3(0, -0.04, 0.004), 18, Color(0.9, 0.95, 0.9), 0.0008, false)
	for j in _sj.size():
		var c3 := _map_pt(_al(cable_pt(0, float(_sj[j]))))
		_label(mp, "%d" % (j + 1), c3 + Vector3(0.03, 0.03, 0.004), 20, Color(1.0, 0.85, 0.3), 0.0008, false)
	var cm := _map_pt(_al(cable_pt(0, track_len(0) * MON_LOSE)))
	_label(mp, "x", cm + Vector3(0, 0, 0.004), 22, Color(1.0, 0.4, 0.3), 0.0008, false)
	_label(mp, "СХЕМА: зелёное — путь, красное — тупики, рыжее — опасно, x — дальше камера не ловит", Vector3(0, 0.335, 0.004), 15, Color(0.85, 0.9, 0.85), 0.0007, false)
	var ds := SphereMesh.new()
	ds.radius = 0.016
	ds.height = 0.032
	var dot := MeshInstance3D.new()
	dot.mesh = ds
	dot.material_override = _glow(Color(1.0, 1.0, 0.4), 4.0)
	mp.add_child(dot)
	_map_dot = dot
	_cab_disp = _label(mp, "", Vector3(0, -0.385, 0.004), 24, Color(0.6, 1.0, 0.7), 0.0009, false)


func _map_pt(a: Vector2) -> Vector3:
	return Vector3((a.x - _map_mid.x) * _map_k, -(a.y - _map_mid.y) * _map_k - 0.02, 0.004)


## Камнепады: гул и струйки щебня, потом камни летят сквозь трос (у всех, если рядом)
func _update_rocks(delta: float, me: Node3D) -> void:
	if rock_ph != _rp_last:
		var was := _rp_last
		_rp_last = rock_ph
		_rp_t = 0.0
		for R in _rocks:
			var near: bool = me != null and me.global_position.distance_to(R["c"]) < 160.0
			(R["warn"] as GPUParticles3D).emitting = rock_ph >= 1 and near
			if not near:
				continue
			if rock_ph == 1:
				SFX.play(self, (R["c"] as Vector3) + Vector3.UP * 20.0, "snowslide", 2.0, 0.45, 160.0)
			elif rock_ph == 2:
				SFX.play(self, (R["c"] as Vector3) + Vector3.UP * 10.0, "snowslide", 4.0, 0.35, 160.0)
			elif was == 2:
				SFX.play(self, (R["c"] as Vector3) + Vector3.DOWN * 10.0, "crunch", 4.0, 0.5, 160.0)
	else:
		_rp_t += delta
	for R2 in _rocks:
		var bl: Array = R2["b"]
		var show := rock_ph == 2 and me != null and me.global_position.distance_to(R2["c"]) < 200.0
		if not show:
			if (bl[0] as Node3D).visible:
				for b in bl:
					(b as Node3D).visible = false
			continue
		var c: Vector3 = R2["c"]
		var tg: Vector3 = R2["tg"]
		var lat: Vector3 = R2["lat"]
		var side: float = R2["side"]
		var half: float = R2["half"]
		for k in bl.size():
			var t := _rp_t - k * 0.12
			var b2: Node3D = bl[k]
			b2.visible = t > 0.0
			if t <= 0.0:
				continue
			var y := 14.0 - 17.0 * t * t
			var lp := side * (3.0 - 2.6 * t)
			var al := (k / float(bl.size() - 1) - 0.5) * 1.7 * half + sin(float(R2["seed"]) + k * 1.7) * 0.6
			b2.global_position = c + lat * lp + tg * al + Vector3.UP * y
			b2.rotation = Vector3(t * 5.0 + k, t * 3.0, k * 0.7)
		if _rp_t > 1.0 and _rp_t - delta <= 1.0:
			var dust: GPUParticles3D = R2["dust"]
			dust.restart()
			dust.emitting = true
			SFX.play(self, c + Vector3.DOWN * 10.0, "crunch", 6.0, 0.4, 160.0)
			SFX.play(self, c + Vector3.DOWN * 10.0, "clank", 0.0, 0.35, 160.0)




## Поворот: штурвал = куда повернуть кабину (метка сверху — вдоль троса)
func _turn_steer(da: float) -> void:
	_loc_y = wrapf(_loc_y + da, -PI, PI)
	_tgt_dirty = true
	_crank_sound()


func _crank_sound() -> void:
	if _crank_snd > 0.0 or _my_panel < 0:
		return
	_crank_snd = 0.16
	SFX.play(self, (_panels[_my_panel]["face"] as Node3D).global_position, "ratchet", -14.0, 1.7 + randf() * 0.2)


## Фиксатор штурвала поворота: почти вдоль/поперёк — щёлк, ровно
func _snap_yaw() -> void:
	var q := roundf(_loc_y / (PI * 0.5)) * PI * 0.5
	if absf(_loc_y - q) < 0.07 and absf(_loc_y - q) > 0.0001:
		_loc_y = wrapf(q, -PI, PI)
		_tgt_dirty = true
		if _my_panel >= 0:
			SFX.play(self, (_panels[_my_panel]["face"] as Node3D).global_position, "latch", -6.0, 1.6)


func _drag_lever(y: float) -> void:
	var best := 0
	for g in GEARS.size():
		if absf(_gear_v(g) - y) < absf(_gear_v(best) - y):
			best = g
	if best != _drag_g:
		_drag_g = best
		_ctl(0, best)


func _press(n: Node3D) -> void:
	n.position.z = -0.02
	get_tree().create_timer(0.25).timeout.connect(func(): n.position.z = 0.0)


## Куда на лицевой панели пульта показывает мышь (метры от центра панели)
func _face_uv(mpos: Vector2) -> Vector2:
	var P: Dictionary = _panels[_my_panel]
	var cam: Camera3D = P["cam"]
	var face: Node3D = P["face"]
	var ro := cam.project_ray_origin(mpos)
	var rd := cam.project_ray_normal(mpos)
	var fx := face.global_transform
	var n := fx.basis.z.normalized()
	var den := rd.dot(n)
	if absf(den) < 0.0001:
		return Vector2(99, 99)
	var t := (fx.origin - ro).dot(n) / den
	var l := fx.affine_inverse() * (ro + rd * t)
	return Vector2(l.x, l.y)


func _update_mon(delta: float) -> void:
	var xf := _cabin.global_transform
	var c := xf.origin + Vector3.UP * 1.2
	var tg := tangent(tr, s)
	var sg := 1.0 if v >= -0.05 else -1.0
	_mon_dir = _mon_dir.lerp(tg * sg, clampf(delta * 1.5, 0.0, 1.0)).normalized()
	var lat := _lat_axis(_mon_dir)
	var want := Vector3.ZERO
	var look := Vector3.ZERO
	var upv := Vector3.UP
	match _cam_mode:
		0:
			want = c - _mon_dir * 8.0 + Vector3.UP * 3.4 + lat * 1.6
			look = c + _mon_dir * 5.0 + Vector3.DOWN * 0.3
			_mon_cam.fov = 64.0
		1:
			want = c + Vector3.UP * 17.0 - _mon_dir * 1.5
			look = c + _mon_dir * 3.0
			upv = _mon_dir
			_mon_cam.fov = 58.0
		2:
			want = c + lat * 11.0 + Vector3.UP * 0.8 - _mon_dir * 1.0
			look = c + _mon_dir * 1.5 + Vector3.UP * 0.4
			_mon_cam.fov = 60.0
		4:
			# в салоне: угол под потолком — видно всех, кто внутри
			want = xf * Vector3(CW * 0.5 - 0.5, CHT - 0.5, CL * 0.5 - 0.75)
			look = xf * Vector3(-0.6, 1.25, -1.5)
			upv = xf.basis.y
			_mon_cam.fov = 80.0
		3:
			# камера на носу кабины (впереди по ходу): видно, что надвигается
			want = xf * Vector3(0.0, CTOP + 0.2, 0.0) + _mon_dir * 3.2
			look = want + _mon_dir * 10.0 + Vector3.DOWN * 3.0
			_mon_cam.fov = 78.0
	_mon_cam.near = 0.05 if _cam_mode == 4 else 0.3
	if _mon_pos == Vector3.INF or _mon_pos.distance_to(want) > 40.0 or _cam_mode >= 3:
		_mon_pos = want
	else:
		_mon_pos = _mon_pos.lerp(want, clampf(delta * 3.5, 0.0, 1.0))
	_mon_cam.look_at_from_position(_mon_pos, look, upv)


# ---------------------------------------------------------------------------
#  Шаг 110: ветряк — три лопасти крутятся поперёк троса; проскочить между ними
# ---------------------------------------------------------------------------
func _build_mill(i: int, c: Vector3, tg: Vector3, lat: Vector3) -> void:
	var side := 1.0 if _mills.size() % 2 == 0 else -1.0
	var hub := c + lat * side * MILL_HUB.x + Vector3.UP * MILL_HUB.y
	var yb := Basis(Vector3.UP, atan2(tg.x, tg.z))
	# каменная башня с деревянной будкой: стоит за плоскостью лопастей
	var back := tg * 3.4
	_spire(hub + back + Vector3.DOWN * 2.6, 3.0, 230.0)
	var wood := _cmat(Color(0.45, 0.3, 0.17), 0.8)
	var wood2 := _cmat(Color(0.3, 0.19, 0.1), 0.85)
	var roofm := _cmat(Color(0.5, 0.16, 0.1), 0.7)
	var iron := _cmat(Color(0.16, 0.16, 0.17), 0.45, 0.7)
	var glow := _glow(Color(1.0, 0.75, 0.35), 1.6)
	var house := Node3D.new()
	add_child(house)
	house.global_transform = Transform3D(yb, hub + back + Vector3.UP * 0.4)
	# шаг 114: каменный цоколь, сруб из досок с угловыми стойками, окна с огоньком, крыша с коньком и свесами
	_mesh(house, _cyl(2.9, 3.3, 2.2, 14), Transform3D(Basis.IDENTITY, Vector3(0, -2.9, 0)), _m_crag)
	_mesh(house, _bm(Vector3(4.2, 3.6, 4.6)), Transform3D.IDENTITY, wood)
	for ky in 8:
		var yy := -1.6 + ky * 0.45
		_mesh(house, _bm(Vector3(4.26, 0.05, 4.66)), Transform3D(Basis.IDENTITY, Vector3(0, yy, 0)), wood2)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_mesh(house, _bm(Vector3(0.28, 3.7, 0.28)), Transform3D(Basis.IDENTITY, Vector3(cx * 2.1, 0, cz * 2.3)), wood2)
	for wz in [-1.0, 1.0]:
		for wx in [-1.0, 1.0]:
			_mesh(house, _bm(Vector3(0.06, 0.8, 0.7)), Transform3D(Basis.IDENTITY, Vector3(wx * 2.13, 0.5, wz * 1.1)), glow)
			_mesh(house, _bm(Vector3(0.1, 0.95, 0.12)), Transform3D(Basis.IDENTITY, Vector3(wx * 2.15, 0.5, wz * 1.1)), wood2)
			_mesh(house, _bm(Vector3(0.1, 0.1, 0.85)), Transform3D(Basis.IDENTITY, Vector3(wx * 2.15, 0.5, wz * 1.1)), wood2)
	_mesh(house, _bm(Vector3(1.0, 1.9, 0.08)), Transform3D(Basis.IDENTITY, Vector3(0, -0.85, 2.33)), wood2)
	_mesh(house, _bm(Vector3(5.2, 0.3, 5.6)), Transform3D(Basis(Vector3.BACK, 0.38), Vector3(-1.15, 2.35, 0)), roofm)
	_mesh(house, _bm(Vector3(5.2, 0.3, 5.6)), Transform3D(Basis(Vector3.BACK, -0.38), Vector3(1.15, 2.35, 0)), roofm)
	_mesh(house, _bm(Vector3(0.3, 0.3, 5.8)), Transform3D(Basis.IDENTITY, Vector3(0, 3.27, 0)), wood2)
	for gz in [-1.0, 1.0]:
		var gab := PrismMesh.new()
		gab.size = Vector3(4.2, 1.5, 0.1)
		_mesh(house, gab, Transform3D(Basis.IDENTITY, Vector3(0, 2.55, gz * 2.28)), wood)
	_mesh(house, _bm(Vector3(0.5, 1.2, 0.5)), Transform3D(Basis.IDENTITY, Vector3(1.2, 3.1, 1.4)), _m_crag)
	_mesh(house, _cyl(0.35, 0.35, 3.6, 12), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -0.4, -2.6)), _m_metal)
	_mesh(house, _cyl(0.5, 0.5, 0.25, 14), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, -0.4, -2.35)), iron)
	var hl := _label(house, "ВЕТРЯК\nне зевай!", Vector3(0, 1.3, -2.36), 40, Color(1.0, 0.85, 0.4), 0.006, false)
	hl.rotation.y = PI
	_merge_children(house, [])
	# ротор: колпак с железным обручем, лопасти — лонжерон, раскосы, решётка и парус (к концу шире), конец красный
	var rotor := Node3D.new()
	add_child(rotor)
	var canvas := _cmat(Color(0.92, 0.88, 0.78), 0.9)
	canvas.cull_mode = BaseMaterial3D.CULL_DISABLED
	var redc := _cmat(Color(0.75, 0.15, 0.1), 0.8)
	redc.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(rotor, _cyl(0.9, 0.3, 1.4, 14), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, 0.2)), _m_dark)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.82
	ring.outer_radius = 0.98
	ring.rings = 20
	ring.ring_segments = 6
	_mesh(rotor, ring, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.35)), iron)
	_mesh(rotor, _cyl(0.0, 0.4, 0.5, 12), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 1.15)), iron)
	for b in 3:
		var bl := Node3D.new()
		rotor.add_child(bl)
		bl.rotation.z = TAU * b / 3.0
		_mesh(bl, _bm(Vector3(MILL_R, 0.34, 0.34)), Transform3D(Basis.IDENTITY, Vector3(MILL_R * 0.5, 0, 0)), wood)
		for k in 5:
			var x0 := 2.4 + k * 2.1
			var wk := lerpf(1.1, MILL_BW * 2.0 - 0.02, k / 4.0)
			var tw := Basis(Vector3.RIGHT, 0.14 - k * 0.025)
			_mesh(bl, _bm(Vector3(1.9, wk - 0.12, 0.04)), Transform3D(tw, Vector3(x0 + 0.95, 0.0, 0.12)), redc if k == 4 or k % 2 == 0 else canvas)
			_mesh(bl, _bm(Vector3(0.08, wk, 0.12)), Transform3D(tw, Vector3(x0, 0, 0.1)), wood)
			for ey in [-1.0, 1.0]:
				_mesh(bl, _bm(Vector3(2.1, 0.08, 0.1)), Transform3D(tw, Vector3(x0 + 1.05, ey * (wk * 0.5 - 0.04), 0.1)), wood)
			_mesh(bl, _bm(Vector3(2.25, 0.05, 0.05)), Transform3D(tw * Basis(Vector3.BACK, atan2(wk - 0.1, 1.9)), Vector3(x0 + 0.95, 0, 0.16)), wood2)
	_merge_children(rotor, [])
	var snd := SFX.loop(rotor, "whirr", -14.0, 70.0)
	snd.pitch_scale = 0.35
	_mills[i] = {"rotor": rotor, "hub": hub, "basis": Basis(lat, Vector3.UP, -tg), "side": side, "ph": float(i) * 0.7, "last": -1}


## Угол ротора (лопасть 0) в момент часов t
func _mill_ang(i: int, t: float) -> float:
	return t * MILL_W + float((_mills[i] as Dictionary)["ph"])


## Задевает ли лопасть кабину (кабина на s_, подвес h_, поворот yw; часы t)
func _mill_hit(i: int, s_: float, h_: float, yw: float, t: float, mg := 0.0) -> bool:
	var o: Array = _obs[i]
	var e := _ext(yw) + Vector2(mg, mg)
	if s_ + e.x < float(o[1]) or s_ - e.x > float(o[2]):
		return false
	var side: float = (_mills[i] as Dictionary)["side"]
	var hub := Vector2(side * MILL_HUB.x, MILL_HUB.y)
	var x0 := -e.y - MILL_BW
	var x1 := e.y + MILL_BW
	var y0 := -h_ - 0.4 - MILL_BW
	var y1 := -h_ + CTOP + MILL_BW
	var a0 := _mill_ang(i, t)
	for b in 3:
		var a := a0 + TAU * b / 3.0
		var d := Vector2(cos(a) * side, sin(a))
		for k in 16:
			var p := hub + d * (1.5 + (MILL_R - 1.5) * k / 15.0)
			if p.x > x0 and p.x < x1 and p.y > y0 and p.y < y1:
				return true
	return false


## Успеет ли кабина проскочить ветряк: стоит / едет сейчас, через react с — разгон до vmax (направление dirv)
func _mill_pass_ok(i: int, dirv: float, vmax: float, react: float) -> bool:
	# надёжно при любой задержке исполнения от 0 до react
	for rr in [0.0, react * 0.5, react]:
		if not _mill_pass_one(i, dirv, vmax, rr):
			return false
	return true


func _mill_pass_one(i: int, dirv: float, vmax: float, react: float) -> bool:
	var o: Array = _obs[i]
	var e := _ext(yaw)
	var v0 := maxf(v * dirv, 0.0)
	var vv := v0
	var ss := s
	var t := 0.0
	while t < 14.0:
		# с запасом: кабина «толще» на 0.4 м — проскакиваем не впритирку
		if _mill_hit(i, ss, H, yaw, _clk + t, 0.4) or _mill_hit(i, ss, H, yaw, _clk + t + 0.05, 0.4):
			return false
		if (dirv > 0.0 and ss - e.x > float(o[2]) + 0.7) or (dirv < 0.0 and ss + e.x < float(o[1]) - 0.7):
			return true
		if t >= react:
			vv = minf(vv + ACC * 0.1, vmax)
		ss += dirv * vv * 0.1
		t += 0.1
	return false


## Лопасти крутятся; когда лопасть проходит у троса — свист (если я рядом)
func _update_mills(me: Node3D) -> void:
	for mi in _mills:
		var M2: Dictionary = _mills[mi]
		var hub: Vector3 = M2["hub"]
		var near: bool = me != null and me.global_position.distance_to(hub) < 260.0
		var rotor: Node3D = M2["rotor"]
		rotor.visible = near
		if not near:
			continue
		var side: float = M2["side"]
		var a := _mill_ang(int(mi), _clk)
		# ротор в плоскости (вбок, вверх); лопасть 0 при угле 0 смотрит «от троса» на этой стороне
		var b: Basis = M2["basis"]
		var rb := b * Basis(Vector3.BACK, a if side > 0.0 else PI - a)
		if side < 0.0:
			rb = b * Basis(Vector3.BACK, PI - a)
		rotor.global_transform = Transform3D(rb, hub)
		# лопасть смотрит на трос (угол к тросу — PI для стороны +, 0 для −): свист
		var k := int(floor((a - PI * 0.5) / (TAU / 3.0)))
		if k != int(M2["last"]):
			M2["last"] = k
			if me.global_position.distance_to(hub) < 90.0:
				SFX.play(self, hub + (b.x * -side) * 9.0, "swish", 4.0, 0.35, 90.0)



## Ближайшая развилка впереди по главному тросу (−1 — нет)
func _next_junction() -> int:
	if tr != 0:
		return -1
	for j in _sj.size():
		if s < float(_sj[j]) + 0.5:
			return j
	return -1


## Шаг 110: «приколы» с пульта — для тех, кто в кабине
func _srv_fun(id: int) -> void:
	if id < 0 or id >= FUN_NAMES.size() or float(_fun_cd[id]) > 0.0:
		return
	if id == 0:
		return                       # турбо теперь — ползунок (код 11)
	var moving_only := id <= 2
	if moving_only and docked >= 0:
		_rpc_all("_ev_fun", [id, -1])
		return
	var arg := 0
	match id:
		0:
			_turbo_t = 3.0
			_turbo_dir = -1.0 if v < -0.1 or gear < GEAR_N else 1.0
		1:
			_spin_left = TAU
		2:
			var ms := _main_s()
			_drop_left = minf(7.0, H_DROP - H)
			if _drop_left < 1.0 or ms < 40.0 or ms > track_len(0) - 40.0:
				_rpc_all("_ev_fun", [id, -2])
				return
			_drop_v = 0.0
			if is_nan(_h_tgt):
				_h_tgt = H
	_fun_cd[id] = float(FUN_CD[id])
	_rpc_all("_ev_fun", [id, arg])


func _srv_fun_tick(delta: float) -> void:
	for k in _fun_cd.size():
		_fun_cd[k] = maxf(float(_fun_cd[k]) - delta, 0.0)


@rpc("authority", "call_local", "reliable")
func _ev_fun(id: int, arg: int) -> void:
	var cp := _cabin.global_position + Vector3.UP * 1.4
	var me = Network.local_player
	var in_cab: bool = me != null and _in_gondola(me.global_position)
	if arg < 0:
		if me != null and op_pid == int(me.peer_id):
			mtn.say("Кабина у причала — сначала отправьте её" if arg == -1 else "Здесь сбрасывать нельзя: рядом станция или кабина и так внизу")
		return
	var held: bool = in_cab and me._held("interact")
	var human: bool = in_cab and not bool(me.get("is_bot"))
	if id == 2 and arg == 1:
		# конец сброса: лебёдка схватила — рывок; кто не держался — подбрасывает к потолку и кидает вбок
		SFX.play(self, cp + Vector3.UP * 1.6, "clank", 6.0, 0.45, 90.0)
		SFX.play(self, cp + Vector3.UP * 3.0, "chain", 4.0, 0.6, 90.0)
		SFX.play(self, cp, "crunch", 2.0, 0.6)
		_bnc_v = -3.8
		_sw_av += 0.45 * (1.0 if randf() < 0.5 else -1.0)
		_sw_lv += 0.6 * (1.0 if randf() < 0.5 else -1.0)
		if in_cab:
			me.add_shake(1.6)
		if human:
			if held:
				me.launch(1.2)
			else:
				me.launch(6.5)
				var ra := randf() * TAU
				me.wind_shove(Vector3(cos(ra), 0.0, sin(ra)), 3.5)
		return
	if id == 0:
		if arg == 5:
			# перегрев турбо
			SFX.play(self, _carriage.global_position, "hiss", 6.0, 0.7, 90.0)
			SFX.play(self, _carriage.global_position, "fail", 0.0, 0.6, 60.0)
			if me != null and op_pid == int(me.peer_id):
				mtn.say("ТУРБО ПЕРЕГРЕЛОСЬ — 10 секунд отдыха")
			if in_cab:
				get_tree().call_group("level", "show_banner", "Турбо перегрелось!", "Дымит лебёдка — сбрасываем ход")
			return
		SFX.play(self, cp, "whistle", 4.0, 1.6, 90.0)
		SFX.play(self, cp, "gust", 2.0, 1.4, 90.0)
		_sw_av -= 0.35 * (1.0 if v >= 0.0 else -1.0)
		if in_cab:
			get_tree().call_group("level", "show_banner", "ТУРБО!", "Оператор жмёт газ — держитесь (E)!")
			me.add_shake(0.6)
		return
	_fun_until[id] = mtn.now() + float(FUN_CD[id])
	var title := ""
	var sub := ""
	match id:
		0:
			SFX.play(self, cp, "whistle", 4.0, 1.6, 90.0)
			SFX.play(self, cp, "gust", 2.0, 1.4, 90.0)
			_sw_av -= 0.35 * (1.0 if v >= 0.0 else -1.0)
			title = "ТУРБО!"
			sub = "Оператор врубил турбо — держитесь (E)!"
		1:
			SFX.play(self, cp + Vector3.UP * 1.6, "chain", 2.0, 1.3, 60.0)
			SFX.play(self, cp, "whistle", -2.0, 2.2, 60.0)
			title = "КАРУСЕЛЬ!"
			sub = "Кабину крутит вокруг троса"
		2:
			SFX.play(self, cp + Vector3.UP * 1.6, "chain", 6.0, 1.8, 80.0)
			SFX.play(self, cp, "fail", 0.0, 0.8, 60.0)
			title = "ПАДАЕМ!!!"
			sub = "Лебёдку сорвало — держитесь!"
			if in_cab:
				me.add_shake(0.9)
			if human and not held:
				me.launch(3.0)        # невесомость: оторвало от пола
		3:
			_disco_t = 12.0
			title = "ДИСКОТЕКА!"
			sub = "Танцуют все!"
	if in_cab:
		get_tree().call_group("level", "show_banner", title, sub)
		if id == 0 or id == 2:
			me.add_shake(0.6)


## Свет в салоне: обычный, дискотека (цвета бегут), тьма (только красный аварийный огонёк)
func _update_cabin_fx(delta: float, me: Node3D) -> void:
	_disco_t = maxf(_disco_t - delta, 0.0)
	_dark_t = maxf(_dark_t - delta, 0.0)
	_swing_t = maxf(_swing_t - delta, 0.0)
	_announce_t = maxf(_announce_t - delta, 0.0)
	var now: float = mtn.now()
	var mode := 2 if _dark_t > 0.0 else (1 if _disco_t > 0.0 else 0)
	if mode == 1:
		var col := Color.from_hsv(fmod(now * 0.9, 1.0), 0.85, 1.0)
		_cab_light.light_color = col
		_cab_light.light_energy = 1.6 + 0.8 * sin(now * 14.0)
		_strip_m.emission = Color.from_hsv(fmod(now * 0.9 + 0.5, 1.0), 0.9, 1.0)
		_strip_m.emission_energy_multiplier = 2.5 if fmod(now * 4.0, 1.0) < 0.5 else 0.4
		_disco_ball.visible = true
		_disco_ball.rotate_y(delta * 2.5)
	elif mode == 2:
		_cab_light.light_color = Color(1.0, 0.1, 0.05)
		_cab_light.light_energy = 0.6 if fmod(now, 1.0) < 0.3 else 0.05
		_strip_m.emission_energy_multiplier = 0.0
		_disco_ball.visible = false
		if randf() < delta * 0.8 and me != null and _in_gondola(me.global_position):
			SFX.play(self, _cabin.global_position + Vector3.UP * 2.6, "creak", -4.0, randf_range(0.4, 0.7), 20.0)
	elif _fx_mode != 0:
		_cab_light.light_color = Color(1.0, 0.86, 0.62)
		_cab_light.light_energy = 1.0
		_strip_m.emission = Color(1.0, 0.9, 0.72)
		_strip_m.emission_energy_multiplier = 2.2
		_disco_ball.visible = false
	_fx_mode = mode
	# качели: подталкиваю раскачку в такт
	if _swing_t > 0.0:
		var L := maxf(_dh - 1.3, 4.0)
		var w := sqrt(9.8 / L)
		_sw_lv += cos(now * w) * 2.6 * delta
		_sw_av += sin(now * w * 0.9) * 0.6 * delta
		if randf() < delta * 1.5:
			SFX.play(self, _cabin.global_position + Vector3.UP * 3.0, "creak", -2.0, randf_range(0.6, 0.9), 50.0)
	# пружинит после сброса
	_bnc_v += (-_bnc * 30.0 - _bnc_v * 3.0) * delta
	_bnc += _bnc_v * delta




func _button_n(face: Node3D, c: Vector2, mat: Material, r: float, asset := "") -> Node3D:
	_mesh(face, _cyl(r + 0.012, r + 0.012, 0.015, 18), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c.x, c.y, 0.008)), _m_metal)
	var n := Node3D.new()
	face.add_child(n)
	n.position = Vector3(c.x, c.y, 0.0)
	if asset == "" or _asset(asset, n, Vector3(0, 0, 0.014), _face_up(), r * 2.3) == null:
		_mesh(n, _cyl(r * 0.92, r, 0.035, 18), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.022)), mat)
	return n


## Шаг 114: модель из ассетов — вписать в size (по большей стороне), повернуть b, поставить в pos (в осях parent)
func _asset(path: String, parent: Node3D, pos: Vector3, b: Basis, size: float, mat: Material = null) -> Node3D:
	var ps = load(RWA + path) if ResourceLoader.exists(RWA + path) else null
	if not (ps is PackedScene):
		return null
	var n: Node3D = (ps as PackedScene).instantiate()
	for ap in n.find_children("*", "AnimationPlayer", true, false):
		ap.get_parent().remove_child(ap)
		ap.queue_free()
	var bb := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mat:
			mi.material_override = mat
		var b2: AABB = _rel_xf(n, mi) * mi.get_aabb()
		bb = b2 if first else bb.merge(b2)
		first = false
	var k := size / maxf(maxf(bb.size.x, bb.size.y), maxf(bb.size.z, 0.0001))
	parent.add_child(n)
	n.transform = Transform3D(b * Basis.from_scale(Vector3.ONE * k), pos)
	return n


## Модель «смотрит вверх» (её y) — из лицевой панели к оператору (z панели)
func _face_up() -> Basis:
	return Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))


## Рычаг Levers&Switches на панели: основание лежит на панели вдоль её y, ручка качается вверх-вниз
func _lever_asset(path: String, face: Node3D, pos: Vector3, size: float) -> Dictionary:
	if _grad_m == null:
		_grad_m = StandardMaterial3D.new()
		_grad_m.albedo_texture = load(RWA + "lev/Gradients.jpg") if ResourceLoader.exists(RWA + "lev/Gradients.jpg") else null
		_grad_m.roughness = 0.55
	var n := _asset(path, face, pos, Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)), size, _grad_m)
	if n == null:
		return {}
	var sk: Skeleton3D = n.find_child("Skeleton3D", true, false)
	if sk == null or sk.find_bone("DEFLever") < 0:
		return {"n": n}
	return {"n": n, "sk": sk, "bi": sk.find_bone("DEFLever")}


## Наклон ручки рычага: a (град) от среднего, + — вверх по панели
func _lever_set(la: Dictionary, a: float) -> void:
	if not la.has("sk"):
		return
	(la["sk"] as Skeleton3D).set_bone_pose_rotation(int(la["bi"]), Quaternion(Vector3(0, 0, 1), deg_to_rad(94.4 - a)))


func _next_cam() -> void:
	_cam_mode = (_cam_mode + 1) % CAM_NAMES.size()
	_glitch = maxf(_glitch, 0.5)
	_mon_pos = Vector3.INF
	if _my_panel >= 0:
		var P: Dictionary = _panels[_my_panel]
		SFX.play(self, (P["face"] as Node3D).global_position, "click", -4.0, 1.3)
		_press(P["cam_b"])


## Кабина сейчас внутри препятствия, которое держит высоту (гребень, сосульки, окно, ворота)
func _inside_lock() -> bool:
	if tr != 0:
		return false
	var e := _ext(yaw)
	for o in _obs:
		var k: int = o[0]
		if k == RIDGE or k == ICE or k == WINDOW or k == RGATE:
			if s + e.x >= float(o[1]) - 0.05 and s - e.x <= float(o[2]) + 0.05:
				return true
	return false



## Надпись на пульте: высота букв h (м), крупный шрифт — резкая; left — от точки вправо
func _pl(face: Node3D, text: String, c: Vector2, h: float, col: Color, z := 0.004, left := false) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = 64
	lb.pixel_size = h / 64.0
	lb.outline_size = 12
	lb.modulate = col
	lb.visibility_range_end = 12.0
	lb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if left:
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	face.add_child(lb)
	lb.position = Vector3(c.x, c.y, z)
	return lb


## Развилка: схема пути (ствол и две ветки), выбранная ветка горит зелёным; рычажок смотрит в её сторону
func _build_fork(face: Node3D, P: Dictionary, trim: Material) -> void:
	# шаг 116: две большие кнопки — ◄ ВЛЕВО и ВПРАВО ►; куда стоит стрелка — та горит зелёным
	var c := FORK_C
	var root := Node3D.new()
	face.add_child(root)
	var caps: Array = []
	var btns: Array = []
	for k in 2:
		var sg := -1.0 if k == 0 else 1.0
		# шаг 116: круглая жёлтая кнопка (Interactables), над ней — горящая стрелка
		var bc := Vector2(c.x + sg * 0.07, c.y - 0.02)
		_mesh(face, _cyl(0.04, 0.04, 0.012, 20), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(bc.x, bc.y, 0.008)), _m_metal)
		var bn := Node3D.new()
		root.add_child(bn)
		bn.position = Vector3(bc.x, bc.y, 0.0)
		if _asset("ctl/YellowButton.glb", bn, Vector3(0, 0, 0.012), _face_up(), 0.07) == null:
			_mesh(bn, _cyl(0.03, 0.033, 0.03, 18), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.022)), _cmat(Color(0.95, 0.8, 0.1), 0.4))
		var cm := _glow(Color(0.25, 0.27, 0.28), 0.1)
		var ar := PrismMesh.new()
		ar.size = Vector3(0.036, 0.03, 0.008)
		_mesh(face, ar, Transform3D(Basis(Vector3.BACK, -sg * PI * 0.5), Vector3(bc.x + sg * 0.008, bc.y + 0.058, 0.014)), cm)
		_mesh(face, _bm(Vector3(0.024, 0.01, 0.008)), Transform3D(Basis.IDENTITY, Vector3(bc.x - sg * 0.014, bc.y + 0.058, 0.014)), cm)
		_pl(face, "ВЛЕВО" if k == 0 else "ВПРАВО", Vector2(bc.x, bc.y - 0.052), 0.024, Color(0.95, 0.95, 0.9))
		caps.append(cm)
		btns.append(bn)
	P["fork_caps"] = caps
	P["fork_btns"] = btns
	P["fork_lv"] = root
	P["fork_la"] = {}
	P["fork_lamps"] = []
	P["sw_txt"] = _pl(face, "", Vector2(c.x, c.y - 0.1), 0.028, Color(1.0, 0.8, 0.35))


## Механизмы приколов: ТУРБО — откидная крышка и рычаг; КАРУСЕЛЬ — ручка-мельница; СБРОС — рубильник; ДИСКО — тумблер
func _build_fun_devices(face: Node3D, P: Dictionary, trim: Material) -> void:
	var nodes: Array = []
	var redm := _cmat(Color(0.9, 0.1, 0.06), 0.3)
	# ТУРБО (шаг 113): ползунок в прорези — выше = быстрее (+0…+10 м/с), сам пружинит вниз; рядом шкала нагрева
	var c0 := Vector2(FUN_X[0], FUN_Y)
	_mesh(face, _bm(Vector3(0.1, 0.2, 0.012)), Transform3D(Basis.IDENTITY, Vector3(c0.x, c0.y, 0.008)), _cmat(Color(0.1, 0.1, 0.11), 0.5))
	_mesh(face, _bm(Vector3(0.018, 0.165, 0.016)), Transform3D(Basis.IDENTITY, Vector3(c0.x, c0.y, 0.012)), _cmat(Color(0.02, 0.02, 0.02), 0.8))
	for k in 6:
		var ty := c0.y - 0.075 + k * 0.03
		_mesh(face, _bm(Vector3(0.022, 0.005, 0.004)), Transform3D(Basis.IDENTITY, Vector3(c0.x - 0.034, ty, 0.016)), _cmat(Color(0.95, 0.75, 0.08)) if k < 5 else redm)
		_mesh(face, _bm(Vector3(0.022, 0.005, 0.004)), Transform3D(Basis.IDENTITY, Vector3(c0.x + 0.034, ty, 0.016)), _cmat(Color(0.95, 0.75, 0.08)) if k < 5 else redm)
	var tk2 := Node3D.new()
	face.add_child(tk2)
	tk2.position = Vector3(c0.x, c0.y - 0.075, 0.0)
	_mesh(tk2, _bm(Vector3(0.016, 0.02, 0.045)), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.035)), _m_metal)
	_mesh(tk2, _bm(Vector3(0.085, 0.028, 0.03)), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.065)), redm)
	_mesh(tk2, _bm(Vector3(0.087, 0.006, 0.031)), Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0.066)), _cmat(Color(0.95, 0.95, 0.9), 0.4))
	P["turbo_kn"] = tk2
	nodes.append(tk2)
	var hl: Array = []
	for k5 in 10:
		var hc := Color(0.2, 1.0, 0.3).lerp(Color(1.0, 0.85, 0.1), clampf(k5 / 5.0, 0.0, 1.0)).lerp(Color(1.0, 0.15, 0.08), clampf((k5 - 5) / 4.0, 0.0, 1.0))
		var hm := _glow(hc, 0.15)
		var seg := _mesh(face, _bm(Vector3(0.026, 0.02, 0.008)), Transform3D(Basis.IDENTITY, Vector3(c0.x + 0.12 + k5 * 0.032, FUN_Y - 0.09, 0.014)), hm)
		hl.append(hm)
		nodes.append(seg)
	P["heat_m"] = hl
	P["turbo_txt"] = _pl(face, "", Vector2(c0.x + 0.33, FUN_Y + 0.02), 0.034, Color(1.0, 0.6, 0.3), 0.012, true)
	# КАРУСЕЛЬ: ручка-мельница и 8 огоньков «заряда» по кругу
	var c1 := Vector2(FUN_X[1], FUN_Y)
	_mesh(face, _cyl(0.07, 0.07, 0.014, 24), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c1.x, c1.y, 0.008)), trim)
	var cl: Array = []
	for k2 in 8:
		var a := TAU * k2 / 8.0
		var lm := _mesh(face, _cyl(0.011, 0.011, 0.014, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c1.x + cos(a) * 0.085, c1.y + sin(a) * 0.085, 0.012)), _lamp_off)
		cl.append(lm)
		nodes.append(lm)
	P["crank_l"] = cl
	var cr := Node3D.new()
	face.add_child(cr)
	cr.position = Vector3(c1.x, c1.y, 0.0)
	_mesh(cr, _bm(Vector3(0.07, 0.018, 0.012)), Transform3D(Basis.IDENTITY, Vector3(0.03, 0, 0.022)), _m_metal)
	_mesh(cr, _cyl(0.016, 0.016, 0.02, 12), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.022)), _m_dark)
	_mesh(cr, _cyl(0.013, 0.013, 0.06, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.058, 0, 0.055)), _cmat(Color(0.95, 0.25, 0.85), 0.35))
	P["crank"] = cr
	nodes.append(cr)
	# СБРОС: рубильник в прорези, тянуть вниз
	var c2 := Vector2(FUN_X[2], FUN_Y)
	_mesh(face, _bm(Vector3(0.1, 0.19, 0.012)), Transform3D(Basis.IDENTITY, Vector3(c2.x, c2.y, 0.008)), _cmat(Color(0.95, 0.75, 0.08), 0.5))
	for k3 in 4:
		_mesh(face, _bm(Vector3(0.1, 0.012, 0.004)), Transform3D(Basis(Vector3.BACK, 0.5), Vector3(c2.x, c2.y - 0.07 + k3 * 0.045, 0.015)), _cmat(Color(0.05, 0.05, 0.05)))
	_mesh(face, _bm(Vector3(0.024, 0.17, 0.02)), Transform3D(Basis.IDENTITY, Vector3(c2.x, c2.y, 0.014)), _m_dark)
	var br := Node3D.new()
	face.add_child(br)
	br.position = Vector3(c2.x, c2.y + 0.065, 0.0)
	var bla := _lever_asset("lev/Lever9.fbx", face, Vector3(c2.x, c2.y, 0.014), 0.2)
	if bla.is_empty():
		_mesh(br, _bm(Vector3(0.016, 0.016, 0.05)), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.035)), _m_metal)
		_mesh(br, _bm(Vector3(0.11, 0.03, 0.03)), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.065)), redm)
	else:
		nodes.append(bla["n"])
	P["breaker"] = br
	P["breaker_a"] = bla
	nodes.append(br)
	# ДИСКО: хромированный тумблер и три цветных огонька
	var c3 := Vector2(FUN_X[3], FUN_Y)
	_mesh(face, _cyl(0.045, 0.045, 0.014, 6), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c3.x, c3.y, 0.008)), trim)
	var tg := Node3D.new()
	face.add_child(tg)
	tg.position = Vector3(c3.x, c3.y, 0.02)
	_mesh(tg, _cyl(0.008, 0.014, 0.075, 10), Transform3D(Basis.IDENTITY, Vector3(0, 0.0375, 0)), _m_metal)
	var tk := SphereMesh.new()
	tk.radius = 0.016
	tk.height = 0.032
	_mesh(tg, tk, Transform3D(Basis.IDENTITY, Vector3(0, 0.078, 0)), _m_metal)
	tg.rotation.x = -0.9
	P["disco_sw"] = tg
	nodes.append(tg)
	var dl: Array = []
	for k4 in 3:
		var dm := _glow([Color(1, 0.2, 0.3), Color(0.2, 1, 0.4), Color(0.3, 0.5, 1)][k4], 0.2)
		var lm2 := _mesh(face, _cyl(0.012, 0.012, 0.014, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c3.x - 0.04 + k4 * 0.04, c3.y - 0.07, 0.012)), dm)
		dl.append(dm)
		nodes.append(lm2)
	P["disco_l"] = dl
	P["fun_nodes"] = nodes


func _fun_ready(k: int) -> bool:
	if k == 0:
		return _ovh_t <= 0.0 and docked < 0
	return float(_fun_until.get(k, -1.0)) <= mtn.now() and (k > 2 or docked < 0)


func _update_fun_devices(P: Dictionary, delta: float, me_op: bool, now: float) -> void:
	# ТУРБО: ползунок (мой — сразу, чужой — как на хосте), шкала нагрева, перегрев мигает
	var shown := _xt_loc if me_op else _xtra
	(P["turbo_kn"] as Node3D).position.y = FUN_Y - 0.075 + 0.15 * shown
	var hm: Array = P["heat_m"]
	var nh := int(_heat * 10.0 + 0.5)
	var blink := _ovh_t > 0.0 and fmod(now * 3.0, 1.0) < 0.5
	for k5 in 10:
		var m5 := hm[k5] as StandardMaterial3D
		var e5 := (3.0 if blink else 0.08) if _ovh_t > 0.0 else (2.6 if k5 < nh else 0.12)
		if absf(m5.emission_energy_multiplier - e5) > 0.01:
			m5.emission_energy_multiplier = e5
	var ttx := ""
	if _ovh_t > 0.0:
		ttx = "ПЕРЕГРЕВ %d с" % int(ceil(_ovh_t))
	elif shown > 0.02:
		ttx = "+%d м/с" % int(round(shown * XTRA_V))
	var tl3: Label3D = P["turbo_txt"]
	if tl3.text != ttx:
		tl3.text = ttx
	# КАРУСЕЛЬ: ручка, огоньки заряда
	(P["crank"] as Node3D).rotation.z = _crank_a
	if not (me_op and _drag == "crank"):
		_crank_acc = maxf(_crank_acc - delta * 2.0, 0.0)
	var cl: Array = P["crank_l"]
	var n := int(_crank_acc / CRANK_FULL * 8.0 + 0.001)
	for k in 8:
		_lamp(cl[k], k < n or (not _fun_ready(1) and fmod(now * 2.0, 1.0) < 0.15))
	# СБРОС: рубильник; после срабатывания медленно возвращается вверх
	if not (me_op and _drag == "breaker"):
		var back := 0.0 if _fun_ready(2) else 1.0 - clampf((float(_fun_until.get(2, 0.0)) - now) / float(FUN_CD[2]), 0.0, 1.0)
		_brk = move_toward(_brk, 0.0 if _fun_ready(2) else 1.0 - back, delta * 2.5)
	(P["breaker"] as Node3D).position.y = FUN_Y + 0.065 - 0.13 * _brk
	_lever_set(P["breaker_a"], lerpf(50.0, -50.0, _brk))
	# ДИСКО: тумблер вниз, пока идёт; огоньки мигают
	var on := _disco_t > 0.0
	var sw_n: Node3D = P["disco_sw"]
	sw_n.rotation.x = move_toward(sw_n.rotation.x, 0.9 if on else -0.9, delta * 10.0)
	var dl: Array = P["disco_l"]
	for k2 in 3:
		var m := dl[k2] as StandardMaterial3D
		var e := 3.0 if on and int(now * 6.0) % 3 == k2 else 0.2
		if absf(m.emission_energy_multiplier - e) > 0.01:
			m.emission_energy_multiplier = e


## Прикол сработал (если готов): на хост; щелчок механизма
func _fire(k: int) -> void:
	if _my_panel < 0:
		return
	var at: Vector3 = (_panels[_my_panel]["face"] as Node3D).global_position
	if not _fun_ready(k):
		SFX.play(self, at, "fail", -10.0, 1.4)
		return
	SFX.play(self, at, "click", -2.0, 0.7)
	_ctl(9, k)


## Лебёдка: Т-рукоять в прорези — где рукоять, такой и подвес
func _set_hw(h: float) -> void:
	var nh := clampf(h, H_MIN, H_MAX)
	if absf(nh - _loc_h) > 0.001:
		_loc_h = nh
		_tgt_dirty = true
		_crank_sound()


func _xt_from(y: float) -> float:
	if _ovh_t > 0.0 or docked >= 0:
		return 0.0
	return clampf((y - (FUN_Y - 0.075)) / 0.15, 0.0, 1.0)


func _h_from_v(y: float) -> float:
	return lerpf(H_MIN, H_MAX, clampf((0.27 - y) / 0.42, 0.0, 1.0))
