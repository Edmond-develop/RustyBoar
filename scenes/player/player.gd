extends CharacterBody3D
## Курьер в полярном экзоскафандре (с поддержкой сети).
## Модель, походка, руки и следы повреждений — в exo_suit.gd, верёвка — rope_tool.gd.
##
## Друзья (и боты-курьеры):
##  * E рядом с другом — поднять над головой (для смеха), Q — кинуть, E — поставить;
##    поднятый вырывается, если жмёт Пробел/WASD;
##  * друг барахтается в полынье рядом — E: встаёшь на колено у края и тянешь за руку;
##  * I — инвентарь; верёвка: ЛКМ — раскрутить и бросить, ПКМ — тянуть, ЛКМ — отвязать.
## Грузы держат по-разному: лёгкий — под мышкой, обычный — перед собой,
## тяжёлый — в обнимку (медленно, без прыжков и бега), ящик вдвоём — за ручки.
##
## У каждого дрона есть «хозяин» — игрок, чей номер записан в имени узла.
## Хозяин управляет дроном сам и 30 раз в секунду рассылает его состояние.
## На остальных компьютерах этот дрон — «копия»: плавно повторяет присланное.
##
## Механики (только у хозяина): бег и выносливость, переноска и устойчивость
## посылки, удары, здоровье, шум (для лавин), ветер.
##
## Вода и холод:
##  * упал в полынью — дрон тяжёлый и тонет; вверх плывёт, только пока держишь Пробел;
##  * подо льдом всплыть нельзя — течение может утащить от полыньи, выход ищут
##    по столбам света; глубже pressure_depth вода давит и бьёт по корпусу;
##  * в воде дрон обледеневает (под водой и на глубине — быстрее), а вылезшего
##    мокрого дрона ещё несколько секунд прихватывает морозом;
##  * лёд виден: корка на корпусе и ногах, сосульки, скованная походка;
##    тает долго (~минута), у жаровни — быстро; R — стряхнуть лёд за выносливость;
##  * обледенение дошло до предела — дрон вмерзает в глыбу. Жми кнопки, чтобы
##    расколоть её; друг может помочь (E рядом). В воде глыба всплывает.

signal health_changed(health: float, max_health: float)
signal died
signal respawned
signal landed(fall_speed: float)

@export_group("Движение")
@export var walk_speed := 6.0
@export var sprint_speed := 11.5
@export var quiet_speed := 2.5
@export var acceleration := 40.0
@export var deceleration := 50.0
@export var air_control := 0.35
@export var turn_speed := 12.0
@export var min_grip := 0.04
@export var ice_slide := 1.0           ## Как сильно ледяной склон тянет вниз
@export var skate_push := 0.16         ## Каток: как быстро разгоняешься (доля от обычного разгона)
@export var skate_glide := 0.02        ## Каток: как быстро тормозишь без кнопок (меньше — дольше катишься)
@export var skate_speed_mult := 1.3    ## Каток: насколько быстрее можно разогнаться

@export_group("Выносливость")
@export var sprint_hold_time := 0.12
@export var stamina_max := 100.0
@export var stamina_drain := 22.0
@export var stamina_regen := 28.0
@export var stamina_regen_delay := 0.7
@export var carry_stamina_mult := 1.3
@export var exhausted_duration := 2.4
@export var exhausted_pause := 0.6
@export var exhausted_speed_mult := 0.45

@export_group("Здоровье")
@export var max_health := 100.0
@export var hazard_damage := 4.0
@export var wall_damage := 3.0
@export var fall_damage_speed := 12.0
@export var fall_damage := 6.0
@export var respawn_delay := 1.8
@export var invulnerable_time := 1.5

@export_group("Вода")
@export var swim_speed := 2.4           ## Скорость плавания на поверхности
@export var float_depth := 1.1          ## Насколько ноги ниже воды (корпус наполовину в воде)
@export var climb_reach := 1.4          ## С какого расстояния до края можно выбраться
@export var sink_speed := 1.7           ## Как быстро тонет (м/с); обледеневший — быстрее
@export var rise_speed := 2.1           ## Как быстро всплывает, пока держишь Пробел
@export var dive_speed := 2.0           ## Скорость под водой
@export var pressure_depth := 9.0       ## Глубже этого (м) вода давит на корпус
@export var pressure_damage := 1.5      ## Урон в секунду за каждый метр глубже
@export var parcel_soak := 2.5          ## % цены посылки за секунду, пока её держат в воде

@export_group("Холод")
@export var freeze_rate := 0.4          ## Обледенение в секунду на поверхности воды
@export var dive_freeze_rate := 0.6     ## ...под водой
@export var dive_freeze_per_m := 0.05   ## ...и ещё столько за каждый метр глубины
@export var wet_time := 5.0             ## Сколько секунд после воды мокрый корпус обмерзает
@export var wet_freeze := 0.5           ## ...и как быстро
@export var frost_max := 12.0           ## Дошло до этого — дрон вмерзает в глыбу
@export var frost_full := 8.0           ## При таком обледенении — самая медленная ходьба
@export var thaw_rate := 0.03           ## Таяние в секунду вдали от огня (очень медленно — иди к жаровне)
@export var fire_thaw_rate := 1.3       ## Таяние в секунду у жаровни
@export var heat_thaw_mult := 6.0       ## Во сколько раз быстрее раскалывается глыба у жаровни
@export var doom_frost := 0.7           ## Обледенение (доля) после которого вмёрзнешь в любом случае
@export var doom_rate := 0.45           ## Как быстро лёд дорастает до глыбы после этой черты (в секунду)
@export var frost_min_speed := 0.35     ## Скорость при полном обледенении (доля от обычной)
@export var shake_stamina := 30.0       ## R — стряхнуть лёд: сколько стоит выносливости
@export var shake_amount := 1.3         ## ...и сколько льда стряхивает
@export var break_presses := 28         ## (не используется: изнутри глыбу не разбить)
@export var self_thaw := 1.0 / 120.0    ## Глыба на суше без помощи тает за ~2 минуты
@export var bed_crush := 2.6            ## Глыба на дне: урон корпусу в секунду
@export var plunge_speed := 5.5         ## С какой скоростью уходишь под воду, когда падаешь
@export var water_tire_time := 25.0     ## За сколько секунд в воде всплывать становится тяжелее всего
@export var buddy_chip := 0.15          ## Сколько раскалывает один удар друга (E)

@export_group("Прыжок")
@export var jump_velocity := 6.5
@export var rise_gravity_mult := 1.6
@export var fall_gravity_mult := 2.2
@export var jump_cut := 0.5
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12

@export_group("Переноска")
@export var carry_speed_mult := 0.8
@export var carry_accel_mult := 0.75
@export var carry_jump_mult := 0.85
@export var heavy_speed_mult := 0.6     ## Скорость, когда несёте тяжёлый груз вдвоём
@export var drag_speed_mult := 0.35     ## Скорость, когда тянешь тяжёлый груз один
@export var heavy_warn_distance := 2.9  ## С какого расстояния предупреждать «держитесь ближе»
@export var throw_speed := 6.0
@export var sprint_instability := 0.16
@export var turn_instability := 0.05
@export var jump_instability := 0.12
@export var landing_instability := 0.15
@export var safe_landing_speed := 7.0
@export var hit_instability := 0.14
@export var stability_recovery := 0.45
@export var fumble_damage := 10.0
@export var hit_damage := 3.0

@export_group("Столкновения")
@export var hit_threshold := 7.0
@export var wall_knockback := 0.6
@export var hazard_knockback := 1.0
@export var light_object_mass := 20.0
@export var kick_strength := 0.8
@export var push_force := 40.0

@export_group("Шум и ветер")
@export var walk_noise := 0.3
@export var run_noise := 1.0
@export var quiet_noise := 0.05
@export var wind_instability := 0.04

@export_group("Анимация и камера")
@export var stride_frequency := 1.9
@export var leg_swing := 0.6
@export var base_fov := 70.0
@export var sprint_fov := 84.0
@export var mouse_sensitivity := 0.0025
@export var joy_look_speed := 3.0
@export var min_pitch_deg := -70.0
@export var max_pitch_deg := 35.0
@export var start_pitch_deg := -18.0

@export_group("Прочее")
@export var fall_limit_y := -20.0

const BODY_HEIGHT := 1.15        ## Середина корпуса (грудь) над ногами
const BLOCK_HEIGHT := 0.95       ## Центр ледяной глыбы, когда вмёрз
const SUIT := preload("res://scenes/player/exo_suit.gd")
const ROPE := preload("res://scenes/player/rope_tool.gd")
const INVENTORY_UI := preload("res://scenes/ui/inventory_ui.gd")
const THROW_METER := preload("res://scenes/ui/throw_meter.gd")
const LIMB_PARTS := preload("res://scenes/props/limb_parts.gd")
const BODY_STATUS := preload("res://scenes/ui/body_status.gd")
const GAUGES := preload("res://scenes/ui/gauge_panel.gd")
const REPAIR_TIME := 3.4         ## Сколько держать E, чтобы прикрутить деталь другу (вставить, 4 болта, провода, проверка)
const RIP_TIME := 2.6            ## Сколько держать F, чтобы оторвать другу руку/ногу (4 болта вылетают по одному)
const FLOP_TIME := 1.7           ## Бросили — плюхнулся на спину: сколько лежу и встаю
const RIP_BOLTS := [0.3, 0.47, 0.63, 0.79]   ## на каком прогрессе вылетает очередной болт
const VISOR_SHADER := preload("res://shaders/visor_frost.gdshader")
const THROW_CHARGE_TIME := 1.1   ## Сколько держать Q для броска в полную силу
const FROST_SHADER := preload("res://shaders/drone_frost.gdshader")
const BLOCK_SHADER := preload("res://shaders/ice_block.gdshader")
const ICE_CHUNK := preload("res://scenes/player/ice_chunk.gd")
const BREAK_KEYS := ["jump", "move_forward", "move_back", "move_left", "move_right", "interact", "shake_ice", "sprint"]
const SEND_INTERVAL := 1.0 / 30.0

# Флаги состояния, которые рассылаются по сети
const F_FLOOR := 1
const F_SPRINT := 2
const F_EXHAUSTED := 4
const F_STAGGER := 8
const F_DEAD := 16
const F_SAFE := 32
const F_ICE := 64
const F_CARRY := 128
const F_SWIM := 256
const F_FROZEN := 512
const F_DIVE := 1024
const F_TUMBLE := 2048
const F_FLOP := 65536            ## (биты 12–15 — руки/ноги, 17–20 — что из них вмёрзло)
const ICE_STAGES := [0.25, 0.5, 0.75]   ## обледенение: 1-я нога, 2-я нога, рука (100% — глыба)

@onready var visual: Node3D = $Visual
@onready var body: Node3D = $Visual/Body
@onready var pickup_zone: Area3D = $Visual/PickupZone
@onready var sprint_trail: GPUParticles3D = $Visual/Body/SprintTrail
@onready var steam: GPUParticles3D = $Visual/Body/Steam
@onready var sparks: GPUParticles3D = $Sparks
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var carry_hud: CanvasLayer = $CarryHUD
@onready var prompt_label: Label = $CarryHUD/Panel/Prompt
@onready var parcel_label: Label = $CarryHUD/Panel/ParcelInfo
@onready var stability_row: Control = $CarryHUD/Panel/StabilityRow
@onready var stability_bar: ProgressBar = $CarryHUD/Panel/StabilityRow/Bar
@onready var stamina_row: Control = $CarryHUD/Panel/StaminaRow
@onready var stamina_caption: Label = $CarryHUD/Panel/StaminaRow/Caption
@onready var stamina_bar: ProgressBar = $CarryHUD/Panel/StaminaRow/Bar
@onready var health_bar: ProgressBar = $CarryHUD/Panel/HealthRow/Bar
@onready var damage_flash: ColorRect = $CarryHUD/DamageFlash
@onready var death_label: Label = $CarryHUD/DeathLabel

var peer_id := 1
var is_local := true
var player_name := "Курьер"
var player_color := Color(0.86, 0.45, 0.17)

var surface_grip := 1.0
var held_parcel: Parcel = null
var instability := 0.0
var stamina := 100.0
var is_sprinting := false
var health := 100.0
var is_dead := false
var noise := 0.0
var is_swimming := false        ## Плывёт на поверхности полыньи
var is_diving := false          ## Под водой
var is_frozen := false          ## Вмёрз в глыбу льда
var frost := 0.0                ## Обледенение: растёт в воде, медленно тает на суше

var _time := 0.0
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _pickup_cooldown := 0.0
var _regen_timer := 0.0
var _sprint_hold := 0.0
var _exhausted_timer := 0.0
var _stagger_timer := 0.0
var _stagger_total := 1.0
var _stagger_strength := 0.0
var _hit_cooldown := 0.0
var _dead_timer := 0.0
var _invuln_timer := 0.0
var _shake := 0.0
var _brace := false             ## стойка со щитом (квест с лучом): стоит на месте, смотрит туда же, куда камера
var _speed_fx := 0.0            ## 0..1 — «ощущение скорости» (горка): шире обзор, дальше камера, тряска
var _spawn_position := Vector3.ZERO
var _prev_velocity := Vector3.ZERO
var _was_on_floor := true
var _stride_phase := 0.0
var _wobble_time := 0.0
var _parcel_offset := Vector3.ZERO
var _carry_basis := Basis.IDENTITY
var _thruster_power := 0.3
var _noise_burst := 0.0
var _wind := Vector3.ZERO
var _last_wind := Vector3.ZERO
var _floor_collider: Object = null
var _default_death_text := ""
var _releasing := false
var _soft_landing := false     ## После подброса гейзером — без урона от падения
var _release_timer := 0.0

# Сеть: последнее присланное состояние (для копий)
var _send_timer := 0.0
var _net_pos := Vector3.ZERO
var _net_vel := Vector3.ZERO
var _net_prev_vy := 0.0
var _net_yaw := 0.0
var _net_flags := F_FLOOR
var _net_was_floor := true
var _net_frost := 0.0
var _net_aux := 0.0
var _net_hp := 1.0

var _lake: Node = null
var _swim_anchor := Vector3.ZERO
var _edge_point := Vector3.INF
var _edge_timer := 0.0
var _soak_timer := 0.0
var _frost_sparkles: GPUParticles3D
var _splash_fx: GPUParticles3D
var _drips: GPUParticles3D
var _frost_row: Control
var _frost_mark: Control
var _frost_bar: ProgressBar
var _frost_caption: Label

# Холод и глубина
var _break_progress := 0.0      ## Насколько расколота глыба (0..1)
var _wet_timer := 0.0
var _freeze_immunity := 0.0
var _pressure_timer := 0.0
var _heat := 1.0                ## 1 — обычно, больше — рядом жаровня
var _heat_timer := 0.0
var _heavy_timer := 0.0
var _water_time := 0.0           ## сколько уже в воде (чем дольше — тем тяжелее всплывать)
var _plunge_t := 0.0             ## только что упал в воду — по инерции уходит вглубь
var _crush_timer := 0.0
var _in_stream := false          ## несёт сильное подводное течение
var doomed := false              ## обледенение перешло черту — вмёрзнет в любом случае
var rolled_by: Node3D = null     ## я — глыба, меня катит этот дрон
var rolling_block: Node3D = null ## я качу эту глыбу (вмёрзшего друга)
var _frozen_yaw := 0.0
var _roll_basis := Basis.IDENTITY
var _roll_last := Vector3.ZERO
var _body_shape: Shape3D = null
var _push_point := Vector3.ZERO  ## куда упираюсь руками (толкаю/качу глыбу)
var _push_send_t := 0.0
var _vis_frozen := false
var _ice_warn_t := 0.0           ## лёд под ногами трещит паутиной — балансирую
var limb_mask := 15              ## руки/ноги на месте: 1 — левая рука, 2 — правая, 4 — левая нога, 8 — правая
var ice_mask := 0                ## какие из них вмёрзли (холод 25% — нога, 50% — вторая, 75% — рука)
var _ice_order: Array[String] = []
var _throw_speed := 0.0          ## с какой скоростью меня бросили (урон при приземлении)
var held_limb: Node3D = null     ## чужая (или своя) оторванная деталь в руке
var _repair_t := 0.0
var _repair_target: Node3D = null
var _rip_t := 0.0
var _rip_target: Node3D = null
var _rip_kind := ""
var ripped_info := {}            ## меня сейчас тянут за руку/ногу: {kind, to, by, k}
## Что я сейчас делаю с другом (видно у всех): 0 — ничего, 1 — прикручиваю, 2 — отрываю
var act_mode := 0
var act_target: Node3D = null
var act_kind := ""
var act_k := 0.0                 ## прогресс 0..1
var _net_act_k := 0.0
var _act_prev_mode := 0
var _act_prev_k := 0.0
var _act_bolts := 0              ## сколько болтов уже вылетело у того, кого отрываю
var _act_tail := 0               ## сколько раз ещё отправить «ничего не делаю»
var _flop_t := 0.0               ## лежу на спине после броска
var _flail_pitch := 0.0
var _lock_t := 0.0               ## короткая блокировка управления (отлетел после рывка)
var body_status: Control
var _visor: ColorRect            ## иней и капли на стекле визора (свой экран)
var _visor_mat: ShaderMaterial
var _visor_wet := 0.0
var _visor_splash := 0.0
var _shake_anim := 0.0
var _block_jolt := 0.0
var _block_grow := 0.0
var _last_frost_step := 0
var _frost_mat: ShaderMaterial
var _icicles: Array[MeshInstance3D] = []
var _icicle_info: Array[Vector3] = []   ## (с какого льда появляется, длина, высота крепления)
var _ice_block: MeshInstance3D
var _block_mat: ShaderMaterial
var _chunks_fx: GPUParticles3D
var _shatter_fx: GPUParticles3D
var _bubbles: GPUParticles3D
var _uw: Node = null

# Скафандр и следы
var suit: Node3D                ## exo_suit.gd
var _icicle_base: Array[Vector3] = []
var _burn_timer := 0.0
var _vis_parcel: Node3D = null  ## посылка в руках (и у копий — ищем сами)
var _vis_mode := 0
var _vis_parcel_t := 0.0
var _no_sprint := false

# Боты-курьеры (тот же дрон, но управляет «мозг» courier_brain.gd, только у хоста)
var is_bot := false
var bot_held := {}              ## действие -> зажато
var bot_tap := {}               ## действие -> кадр нажатия
var bot_move := Vector2.ZERO    ## «стик» бота (вперёд = (0, -1))
var input_blocked := false      ## открыто окно (инвентарь) — управление выключено
var controlled := false         ## этим дроном сейчас управляет человек за этим компьютером
var downed := false             ## лежит без сил (команда боту — чтобы поднимать «тушку»)
var _claimed_slot := -1         ## для Ледяного вала (куда встать боту)

# Инвентарь и верёвка
var items: Array[String] = ["rope"]
var rope: Node3D                ## rope_tool.gd (узел "Rope")
var throw_meter: Control         ## шкала силы броска (только свой дрон)
var _charge := -1.0              ## держу Q: 0..1 (−1 — не замахиваюсь)
var _throw_dots: MultiMeshInstance3D
var _throw_ring: MeshInstance3D
var _throw_land := Vector3.INF
var inventory_ui: CanvasLayer

# Друзья: поднять над головой и кинуть, вытащить из полыньи рукой
var carried_by: Node3D = null   ## кто держит меня над головой
var held_friend: Node3D = null  ## кого держу я
var _tumble := false            ## кувыркаюсь после броска
var _struggle := 0
var _held_t := 0.0
var rescue_role := 0            ## 1 — тяну друга из воды рукой, 2 — меня тянут
var rescue_t := 0.0
var rescue_partner: Node3D = null
var _rescue_kneel := Vector3.ZERO
var _rescue_land := Vector3.ZERO
var _rescue_from := Vector3.ZERO


func _enter_tree() -> void:
	if has_meta("bot_id"):
		is_bot = true
		peer_id = int(get_meta("bot_id"))
		set_multiplayer_authority(multiplayer.get_unique_id())
		return
	peer_id = name.to_int() if name.is_valid_int() else 1
	set_multiplayer_authority(peer_id)


# ---------------------------------------------------------------------------
#  Ввод: у человека — клавиатура, у бота — команды «мозга»
# ---------------------------------------------------------------------------
func _ai_driven() -> bool:
	return is_bot and not controlled


func _held(a: StringName) -> bool:
	if _ai_driven():
		return bool(bot_held.get(a, false))
	if not controlled or input_blocked:
		return false
	return Input.is_action_pressed(a)


func _just(a: StringName) -> bool:
	if _ai_driven():
		return int(bot_tap.get(a, -10)) == Engine.get_physics_frames() - 1
	if not controlled or input_blocked:
		return false
	return Input.is_action_just_pressed(a)


func _released(a: StringName) -> bool:
	if not controlled or input_blocked:
		return false
	return Input.is_action_just_released(a)


func _move_vec() -> Vector2:
	if _ai_driven():
		return bot_move
	if not controlled or input_blocked:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


## Взять / отдать управление этим дроном (G — переселиться в бота и обратно)
func set_controlled(on: bool) -> void:
	controlled = on
	input_blocked = false
	carry_hud.visible = on
	bot_held.clear()
	bot_move = Vector2.ZERO
	if on:
		Network.local_player = self
		spring_arm.add_excluded_object(get_rid())
		camera.fov = base_fov
		camera.make_current()


## Бот «нажал» кнопку (сработает в следующем кадре)
func bot_press(a: StringName) -> void:
	bot_tap[a] = Engine.get_physics_frames()


## Можно ли слать по сети (боты есть только у хоста — им нельзя)
func _online() -> bool:
	return Network.in_game and Network.is_online() and not is_bot


## Человек за этим компьютером управляет этим дроном
func is_human_local() -> bool:
	return is_local and not is_bot


func _ready() -> void:
	is_local = is_multiplayer_authority()
	add_to_group("player")
	process_physics_priority = -10   # раньше посылок: они берут положение рук уже за этот кадр
	_spawn_position = global_position
	_net_pos = global_position
	stamina = stamina_max
	health = max_health
	_default_death_text = death_label.text
	_apply_identity()
	_make_water_fx()
	_make_throw_aim()
	(func(): LIMB_PARTS.get_manager(get_tree())).call_deferred()
	body_status = Control.new()
	body_status.set_script(BODY_STATUS)
	body_status.set("player", self)
	carry_hud.add_child(body_status)
	_setup_dashboard.call_deferred()
	throw_meter = Control.new()
	throw_meter.set_script(THROW_METER)
	carry_hud.add_child(throw_meter)
	_visor = ColorRect.new()
	_visor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_visor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visor_mat = ShaderMaterial.new()
	_visor_mat.shader = VISOR_SHADER
	_visor.material = _visor_mat
	carry_hud.add_child(_visor)
	carry_hud.move_child(_visor, 0)
	rope = Node3D.new()
	rope.set_script(ROPE)
	rope.name = "Rope"
	add_child(rope)
	rope.setup(self)
	if is_local and not is_bot:
		inventory_ui = CanvasLayer.new()
		inventory_ui.set_script(INVENTORY_UI)
		inventory_ui.set("player", self)
		add_child(inventory_ui)

	if is_local and not is_bot:
		controlled = true
		Network.local_player = self
		spring_arm.add_excluded_object(get_rid())
		camera_pivot.rotation.x = deg_to_rad(start_pitch_deg)
		camera.fov = base_fov
		camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.current = false
		carry_hud.visible = false
		_make_name_tag()
	if is_bot:
		collision_layer = 1


func _apply_identity() -> void:
	var info: Dictionary = Network.players.get(peer_id, {})
	if is_bot:
		info = {"name": get_meta("bot_name", "Бот"), "color": int(get_meta("bot_color", 3))}
	player_name = info.get("name", "Курьер")
	player_color = Network.COLORS[int(info.get("color", 0)) % Network.COLORS.size()]
	suit = Node3D.new()
	suit.set_script(SUIT)
	suit.name = "Suit"
	visual.add_child(suit)
	suit.build(body, player_color)
	suit.set_number(("Б%d" % (peer_id - 1000)) if is_bot else ("%02d" % (peer_id % 100)))
	sprint_trail.reparent(suit.trail_mount, false)
	sprint_trail.position = Vector3.ZERO
	steam.reparent(suit.steam_mount, false)
	steam.position = Vector3.ZERO


func _make_water_fx() -> void:
	_splash_fx = FX.particles(Color(0.8, 0.93, 1.0, 0.9), 70, 1.1, 0.1, 2.5, 6.0, Vector3(0, -12, 0), 40.0)
	_splash_fx.top_level = true
	add_child(_splash_fx)
	_drips = FX.particles(Color(0.75, 0.9, 1.0, 0.8), 30, 0.7, 0.04, 0.2, 0.6, Vector3(0, -9, 0), 60.0, false)
	FX.set_box(_drips, Vector3(0.35, 0.2, 0.35))
	_drips.position.y = 0.25
	body.add_child(_drips)
	_frost_sparkles = FX.particles(Color(0.9, 0.97, 1.0, 0.9), 24, 1.2, 0.035, 0.1, 0.4, Vector3(0, -1.5, 0), 180.0, false, true)
	FX.set_box(_frost_sparkles, Vector3(0.4, 0.75, 0.35))
	_frost_sparkles.position.y = 0.05
	body.add_child(_frost_sparkles)
	# Пузыри под водой
	_bubbles = FX.particles(Color(0.85, 0.95, 1.0, 0.55), 18, 1.3, 0.045, 0.3, 0.9, Vector3(0, 2.5, 0), 35.0, false)
	FX.set_box(_bubbles, Vector3(0.3, 0.2, 0.3))
	_bubbles.position.y = 0.3
	body.add_child(_bubbles)
	# Куски льда, отваливающиеся при таянии
	_chunks_fx = FX.particles(Color(0.85, 0.94, 1.0, 0.95), 12, 1.0, 0.06, 0.6, 1.8, Vector3(0, -12, 0), 80.0)
	FX.set_box(_chunks_fx, Vector3(0.35, 0.5, 0.3))
	_chunks_fx.position.y = 0.2
	body.add_child(_chunks_fx)
	# Осколки расколотой глыбы
	_shatter_fx = FX.particles(Color(0.8, 0.93, 1.0, 0.95), 60, 1.5, 0.1, 2.5, 6.5, Vector3(0, -14, 0), 180.0)
	FX.set_box(_shatter_fx, Vector3(0.7, 1.0, 0.7))
	_shatter_fx.top_level = true
	add_child(_shatter_fx)
	_make_frost_visuals()
	if is_local:
		var row := HBoxContainer.new()
		row.visible = false
		var cap := Label.new()
		cap.text = "Обледенение"
		_frost_caption = cap
		cap.custom_minimum_size = Vector2(130, 0)
		cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		cap.add_theme_constant_override("outline_size", 6)
		row.add_child(cap)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.step = 0.001
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.modulate = Color(0.6, 0.85, 1.0)
		row.add_child(bar)
		# черта «назад пути нет»: перешёл её — вмёрзнешь
		var mark := ColorRect.new()
		mark.color = Color(1.0, 0.35, 0.25, 0.95)
		mark.anchor_left = doom_frost
		mark.anchor_right = doom_frost
		mark.anchor_top = 0.0
		mark.anchor_bottom = 1.0
		mark.offset_left = -1.5
		mark.offset_right = 1.5
		mark.offset_top = -3.0
		mark.offset_bottom = 3.0
		bar.add_child(mark)
		_frost_mark = mark
		$CarryHUD/Panel.add_child(row)
		_frost_row = row
		_frost_bar = bar


## Приборная панель вместо полосок: старые строки прячем (их значения больше не видны)
func _setup_dashboard() -> void:
	var legacy := Control.new()
	legacy.name = "LegacyBars"
	legacy.visible = false
	carry_hud.add_child(legacy)
	for r in [stability_row, stamina_row, health_bar.get_parent(), _frost_row]:
		if r != null and is_instance_valid(r):
			(r as Node).reparent(legacy)
	var panel := $CarryHUD/Panel as Control
	panel.offset_top -= 150.0
	panel.offset_bottom = -174.0
	var g := Control.new()
	g.name = "Gauges"
	g.set_script(GAUGES)
	g.set("player", self)
	carry_hud.add_child(g)
	carry_hud.move_child(g, 1)


## Ледяная корка (поверх всех деталей дрона), сосульки и глыба для полной заморозки
func _make_frost_visuals() -> void:
	_frost_mat = ShaderMaterial.new()
	_frost_mat.shader = FROST_SHADER
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		if not suit.no_frost.has(node):
			(node as MeshInstance3D).material_overlay = _frost_mat

	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color(0.82, 0.93, 1.0, 0.8)
	ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ice.roughness = 0.08
	ice.metallic_specular = 0.9
	ice.rim_enabled = true
	ice.rim = 0.7
	var cone := CylinderMesh.new()
	cone.top_radius = 0.045
	cone.bottom_radius = 0.003
	cone.height = 1.0
	cone.radial_segments = 5
	cone.rings = 1
	cone.material = ice
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# сосульки под нагрудником, наплечниками, шлемом и котлом
	for m in suit.icicle_mounts:
		var ic := MeshInstance3D.new()
		ic.mesh = cone
		ic.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ic.position = m[1]
		ic.visible = false
		(m[0] as Node3D).add_child(ic)
		_icicles.append(ic)
		_icicle_base.append(m[1])
		_icicle_info.append(Vector3(rng.randf_range(0.2, 0.85), rng.randf_range(0.14, 0.32) * float(m[2]), 0.0))

	_block_mat = ShaderMaterial.new()
	_block_mat.shader = BLOCK_SHADER
	_ice_block = MeshInstance3D.new()
	_ice_block.mesh = ICE_CHUNK.build(int(peer_id) * 7919 + 13, _block_mat)
	_ice_block.position.y = BLOCK_HEIGHT
	_ice_block.rotation.y = 0.4
	_ice_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ice_block.visible = false
	add_child(_ice_block)


func _make_name_tag() -> void:
	var tag := Label3D.new()
	tag.text = player_name
	tag.modulate = player_color.lightened(0.3)
	tag.font_size = 40
	tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.25, 0)
	add_child(tag)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or not controlled or input_blocked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_rotate_camera(-motion.relative.x * mouse_sensitivity, -motion.relative.y * mouse_sensitivity)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------------------
#  Главный цикл
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	if not is_local:
		_puppet_process(delta)
		return

	if controlled and not input_blocked:
		_handle_gamepad_look(delta)
	_update_surface_grip()
	_pickup_cooldown -= delta
	_hit_cooldown -= delta
	_stagger_timer = maxf(_stagger_timer - delta, 0.0)
	_invuln_timer -= delta
	_lock_t = maxf(_lock_t - delta, 0.0)
	_flop_t = maxf(_flop_t - delta, 0.0)
	act_mode = 0                     # _limb_actions ниже снова выставит, если я всё ещё занят
	if _releasing:
		_release_timer -= delta
		if _release_timer <= 0.0:
			_releasing = false

	if is_dead:
		_dead_timer -= delta
		if _dead_timer <= 0.0:
			respawn()
			return

	# --- Друзья: меня держат / спасают / я спасаю ---
	if carried_by != null:
		_carried_process(delta)
		return
	if rescue_role == 2:
		_rescued_process(delta)
		return
	if rescue_role == 1:
		_rescuer_process(delta)
		return

	# --- Вода и холод ---
	if _lake == null:
		_lake = get_tree().get_first_node_in_group("ice_lake")
		if _lake:
			_uw = _lake.get_node_or_null("Underwater")
	_update_heat(delta)
	_shake_anim = maxf(_shake_anim - delta, 0.0)
	if not is_swimming and not is_diving and _lake and _lake.is_open_water(global_position):
		_enter_water()
	if is_frozen:
		_frozen_process(delta)
		return
	if is_diving:
		_dive_process(delta)
		return
	if is_swimming:
		_swim_process(delta)
		return
	_frost_tick(delta, -1.0)
	if _just("shake_ice") and not is_dead:
		if not _try_chip_buddy():       # R рядом с вмёрзшим другом — бьём по его льду
			_shake_off_ice()

	var on_floor := is_on_floor()
	var exhausted := _exhausted_timer > 0.0
	var paused := exhausted and _exhausted_timer > exhausted_duration - exhausted_pause
	var staggered := _stagger_timer > 0.0 or _lock_t > 0.0 or _flop_t > 0.0
	var mode := _carry_mode()

	# --- Гравитация ---
	if on_floor:
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta
		var mult := rise_gravity_mult if velocity.y > 0.0 else fall_gravity_mult
		velocity += get_gravity() * mult * delta

	# --- Прыжок (с тяжёлым грузом прыгать нельзя) ---
	if _just("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer -= delta

	var heavy_single := mode == 1 and held_parcel != null and held_parcel.carry_weight() >= 3
	var can_jump := not paused and not staggered and not is_dead and mode < 2 and not heavy_single and held_friend == null and not downed \
		and legs_count() > 0
	if can_jump and _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity * (carry_jump_mult if mode == 1 else 1.0) * lerpf(1.0, 0.65, _frost_ratio()) * (0.75 if legs_count() == 1 else 1.0)
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_thruster_power = 6.0
		_noise_burst += 0.5
		if mode == 1:
			instability += jump_instability

	if _released("jump") and velocity.y > 0.0 and not _soft_landing:
		velocity.y *= jump_cut

	# --- Верёвка ---
	rope.local_update(delta)

	# --- Взять / положить / бросить ---
	if not is_dead and not _releasing:
		if _just("interact"):
			if rolling_block:
				_roll_call(rolling_block, false, Vector3(velocity.x, 0.0, velocity.z) * 1.1)
			elif held_friend:
				_put_friend_down()
			elif held_parcel:
				_put_down()
			elif held_limb != null:
				# деталь в руке: рядом её хозяин без неё — прикручиваю (держать E), иначе кладу
				var rt := _repair_candidate()
				if rt != null:
					_repair_target = rt
					_repair_t = 0.0
				else:
					_drop_limb(Vector3(velocity.x, 0.5, velocity.z))
			elif _try_grab_block():
				pass
			elif _try_hand_rescue():
				pass
			elif _try_pick_limb():
				pass
			elif _try_pick_up():
				pass
			else:
				_try_lift_friend()
		elif _just("rip") and _rip_target == null and arms_count() > 0 and held_limb == null \
				and held_parcel == null and held_friend == null:
			var rv := _rip_candidate()
			if rv != null:
				_rip_target = rv
				_rip_kind = _rip_pick_kind(rv)
				_rip_t = 0.0
		elif _just("throw") and _charge < 0.0 and _can_throw():
			if _ai_driven():
				_do_throw(0.85)          # бот бросает сразу
			else:
				_charge = 0.0            # замах: чем дольше держу Q, тем сильнее
	_limb_actions(delta)
	_ripped_process(delta)
	if _charge >= 0.0:
		if not _can_throw() or is_dead:
			_charge = -1.0
		elif _held("throw"):
			_charge = minf(_charge + delta / THROW_CHARGE_TIME, 1.0)
			var aim := _throw_aim_dir()
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-aim.x, -aim.z), clampf(delta * 10.0, 0.0, 1.0))
		else:
			_do_throw(_throw_power(_charge))
			_charge = -1.0
	mode = _carry_mode()

	# --- Ввод относительно камеры ---
	var input_dir := _move_vec()
	if paused or staggered or is_dead or _brace or downed:
		input_dir = Vector2.ZERO
	var cam_basis := camera_pivot.global_transform.basis
	var forward := -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := cam_basis.x
	right.y = 0.0
	right = right.normalized()
	var direction := right * input_dir.x - forward * input_dir.y
	var has_input := direction.length() > 0.1

	# --- Выносливость и скорость ---
	_no_sprint = held_friend != null or (mode == 1 and held_parcel != null and held_parcel.carry_weight() >= 3) or legs_count() < 2
	_update_stamina(delta, has_input, mode > 0)
	exhausted = _exhausted_timer > 0.0

	var target_speed := walk_speed
	if is_sprinting:
		target_speed = sprint_speed
	elif _held("quiet"):
		target_speed = quiet_speed
	if exhausted:
		target_speed *= exhausted_speed_mult
	target_speed *= _frost_mult()
	match mode:
		1: target_speed *= [0.95, carry_speed_mult, 0.52][clampi(held_parcel.carry_weight(), 1, 3) - 1] if held_parcel else carry_speed_mult
		2: target_speed *= drag_speed_mult
		3: target_speed *= heavy_speed_mult
	if held_friend != null:
		target_speed *= 0.62          # друг над головой тяжёлый
	if rolling_block != null:
		target_speed *= 0.72          # качу глыбу с другом
	target_speed *= _limb_speed_mult()
	if _repair_target != null or _rip_target != null:
		target_speed *= 0.2           # занят: прикручиваю / отрываю

	# Каток (у пола есть метка "skate"): разгон медленный, торможение почти нулевое — катимся
	var skating := on_floor and _floor_collider is Object and is_instance_valid(_floor_collider) \
		and (_floor_collider as Object).has_meta("skate")
	if skating:
		target_speed *= skate_speed_mult

	var target_velocity := direction * target_speed
	_update_push(direction, target_speed, has_input, delta)
	_last_wind = Vector3(_wind.x, 0.0, _wind.z)
	if _brace:
		_last_wind *= 0.55     # в стойке дрон упирается — сносит слабее
	_wind = Vector3.ZERO
	target_velocity += _last_wind
	if act_mode != 0 and act_target != null and is_instance_valid(act_target):
		# встаю на удобное расстояние: упереться ногой / дотянуться до гнезда
		var away := global_position - act_target.global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.05 else visual.global_basis.z
		var spot: Vector3 = act_target.global_position + away * (1.05 if act_mode == 2 else 0.95)
		var to_spot := spot - global_position
		to_spot.y = 0.0
		target_velocity = (to_spot * 6.0).limit_length(2.5)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if (has_input or _last_wind.length() > 0.1) else deceleration
	if mode > 0:
		rate *= carry_accel_mult
	if skating:
		rate = acceleration * skate_push if has_input else deceleration * skate_glide
	elif not on_floor and _soft_landing:
		rate = acceleration * 0.04   # подбросило трамплином/гейзером — летим по инерции
	else:
		rate *= surface_grip if on_floor else air_control
	if staggered:
		rate *= 0.15
	horizontal = horizontal.move_toward(target_velocity, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# На скользком склоне дрон съезжает вниз (и разгоняется на ледяных спусках)
	if on_floor and surface_grip < 0.5:
		var n := get_floor_normal()
		velocity.x += n.x * 9.8 * ice_slide * delta
		velocity.z += n.z * 9.8 * ice_slide * delta

	# Верёвка: держу груз или друга / меня держат
	velocity = rope.adjust_velocity(velocity, delta)

	# --- Движение и столкновения ---
	var pre_move_velocity := velocity
	move_and_slide()
	_handle_collisions(pre_move_velocity, delta)

	var now_on_floor := is_on_floor()
	var just_landed := now_on_floor and not _was_on_floor
	if just_landed and _soft_landing:
		_soft_landing = false
		pre_move_velocity.y = maxf(pre_move_velocity.y, -safe_landing_speed)
	if just_landed and _tumble:
		# плюх на спину: лежу, звёздочки, потом встаю
		_tumble = false
		_flop_t = FLOP_TIME
		body.scale = Vector3(1.25, 0.75, 1.25)
		if _throw_speed > 3.0:
			# шмякнулся: чем сильнее бросили, тем больнее (4–10% корпуса)
			var k := clampf((_throw_speed - 4.0) / 6.0, 0.0, 1.0)
			take_damage(max_health * lerpf(0.04, 0.1, k), "thrown")
		_throw_speed = 0.0
		_shake = maxf(_shake, 0.3)
		velocity.x *= 0.3
		velocity.z *= 0.3
		suit.emote(SUIT.Mood.DIZZY, FLOP_TIME)
	if just_landed:
		landed.emit(-pre_move_velocity.y)
		_noise_burst += clampf(-pre_move_velocity.y * 0.08, 0.0, 1.5)
		if -pre_move_velocity.y > fall_damage_speed:
			take_damage((-pre_move_velocity.y - fall_damage_speed) * fall_damage, "fall")

	_update_carry(delta, just_landed, pre_move_velocity)
	_update_throw_aim()
	_update_noise(delta, has_input)
	_update_visual(delta, direction, target_speed, just_landed)
	_update_camera(delta)
	_update_hud()

	_was_on_floor = now_on_floor
	_prev_velocity = velocity

	if global_position.y < fall_limit_y:
		velocity = Vector3.ZERO
		if not is_dead:
			_die()

	_send_state(delta)


# ---------------------------------------------------------------------------
#  Сеть
# ---------------------------------------------------------------------------

func _send_state(delta: float) -> void:
	if not _online():
		return
	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer = SEND_INTERVAL
	var flags := 0
	if is_on_floor(): flags |= F_FLOOR
	if is_sprinting: flags |= F_SPRINT
	if _exhausted_timer > 0.0: flags |= F_EXHAUSTED
	if _stagger_timer > 0.0: flags |= F_STAGGER
	if is_dead: flags |= F_DEAD
	if is_on_safe_ground(): flags |= F_SAFE
	if surface_grip < 0.5: flags |= F_ICE
	if held_parcel != null: flags |= F_CARRY
	if is_swimming: flags |= F_SWIM
	if is_frozen: flags |= F_FROZEN
	if is_diving: flags |= F_DIVE
	if _tumble: flags |= F_TUMBLE
	if _flop_t > 0.0: flags |= F_FLOP
	flags |= limb_mask << 12
	flags |= ice_mask << 17
	if act_mode != 0:
		_act_tail = 8
	if act_mode != 0 or _act_tail > 0:
		_act_tail -= 1
		var tid: int = int(act_target.peer_id) if act_target != null and is_instance_valid(act_target) else 0
		_net_act.rpc(act_mode, tid, SUIT.LIMBS.find(act_kind), act_k)
	_net_state.rpc(global_position, velocity, visual.rotation.y, flags, noise, frost, _break_progress, health / max_health)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(pos: Vector3, vel: Vector3, yaw: float, flags: int, net_noise: float, net_frost: float, aux: float, hp: float) -> void:
	_net_pos = pos
	_net_prev_vy = _net_vel.y
	_net_vel = vel
	_net_yaw = yaw
	_net_flags = flags
	noise = net_noise
	_net_frost = net_frost
	_net_aux = aux
	_net_hp = hp


## Что делает с другом (копия повторяет позу и эффекты)
@rpc("authority", "call_remote", "unreliable_ordered")
func _net_act(m: int, tid: int, ki: int, k: float) -> void:
	if m != 0 and act_mode == 0:
		act_k = k
	act_mode = m
	act_target = Network.find_player(tid) if tid != 0 else null
	act_kind = SUIT.LIMBS[ki] if ki >= 0 and ki < 4 else ""
	_net_act_k = k
	if m == 0:
		act_target = null


## Друг ударил по моей глыбе (E рядом) — она трескается сильнее
@rpc("any_peer", "call_remote", "reliable")
func _rpc_chip_ice() -> void:
	if is_local and is_frozen:
		_break_progress += buddy_chip
		_block_jolt = 1.0


@rpc("authority", "call_remote", "reliable")
func _net_splash_fx(pos: Vector3) -> void:
	_splash_fx.global_position = pos
	_splash_fx.restart()


@rpc("authority", "call_remote", "reliable")
func _net_hit_fx(pos: Vector3) -> void:
	sparks.global_position = pos
	sparks.restart()


## Копия чужого дрона: плавно повторяем присланное состояние.
func _puppet_process(delta: float) -> void:
	if global_position.distance_to(_net_pos) > 6.0:
		global_position = _net_pos
	else:
		global_position = global_position.lerp(_net_pos, clampf(delta * 15.0, 0.0, 1.0))
	velocity = _net_vel
	is_sprinting = (_net_flags & F_SPRINT) != 0
	is_dead = (_net_flags & F_DEAD) != 0
	_exhausted_timer = 1.0 if (_net_flags & F_EXHAUSTED) != 0 else 0.0
	if (_net_flags & F_STAGGER) != 0:
		if _stagger_timer <= 0.0:
			_stagger_total = 0.6
			_stagger_timer = 0.6
			_stagger_strength = 0.7
		_stagger_timer = maxf(_stagger_timer - delta, 0.05)
	else:
		_stagger_timer = 0.0
	surface_grip = 0.1 if (_net_flags & F_ICE) != 0 else 1.0
	is_swimming = (_net_flags & F_SWIM) != 0
	is_diving = (_net_flags & F_DIVE) != 0
	frost = _net_frost
	var was_frozen := is_frozen
	is_frozen = (_net_flags & F_FROZEN) != 0
	var nm := (_net_flags >> 12) & 15
	if nm != limb_mask:
		limb_mask = nm               # подключился позже — вид рук/ног как у хозяина
		suit.set_limbs(nm)
	var im := (_net_flags >> 17) & 15
	if im != ice_mask:
		ice_mask = im
		suit.set_ice(im)
	if is_frozen and not was_frozen:
		_block_grow = 0.0
		_chunks_fx.restart()
	elif was_frozen and not is_frozen:
		_play_shatter()
	if _net_aux > _break_progress + 0.01:
		_block_jolt = 1.0
	_break_progress = _net_aux

	var grounded := is_grounded()
	var just_landed := grounded and not _net_was_floor
	if just_landed:
		landed.emit(-_net_prev_vy)
	_net_was_floor = grounded

	_tumble = (_net_flags & F_TUMBLE) != 0
	if (_net_flags & F_FLOP) != 0:
		_flop_t = FLOP_TIME if _flop_t <= 0.0 else maxf(_flop_t - delta, 0.02)
	else:
		_flop_t = 0.0
	if carried_by != null and is_instance_valid(carried_by):
		global_position = carried_by.global_position + Vector3.UP * 1.95
	_update_visual(delta, Vector3.ZERO, walk_speed, just_landed)
	if carried_by == null and not _tumble and rescue_role == 0:
		visual.rotation.y = lerp_angle(visual.rotation.y, _net_yaw, clampf(delta * 15.0, 0.0, 1.0))


# ---------------------------------------------------------------------------
#  Публичные функции (для уровня, опасностей и посылок)
# ---------------------------------------------------------------------------

func is_grounded() -> bool:
	return is_on_floor() if is_local else (_net_flags & F_FLOOR) != 0


func is_carrying() -> bool:
	return held_parcel != null if is_local else (_net_flags & F_CARRY) != 0


func is_on_safe_ground() -> bool:
	if not is_local:
		return (_net_flags & F_SAFE) != 0
	return is_on_floor() and _floor_collider != null and is_instance_valid(_floor_collider) \
		and (_floor_collider as Node).is_in_group("safe_ground")


func get_floor_body() -> Object:
	return _floor_collider


func get_noise() -> float:
	return noise


func get_held_parcel() -> Parcel:
	return held_parcel


## Где держать обычную посылку (у хозяина — с покачиванием)
func get_carry_transform() -> Transform3D:
	var p: Parcel = held_parcel if held_parcel != null else _vis_parcel as Parcel
	var w := p.carry_weight() if p else 2
	return suit.carry_transform(_carry_basis, _parcel_offset, w, suit.extents(p))


## Точка захвата тяжёлого груза (груз висит между носильщиками на уровне рук)
func get_heavy_hold_point() -> Vector3:
	return global_position + Vector3.UP * 0.95


## Куда тянуть тяжёлый груз волоком
func get_drag_point() -> Vector3:
	return global_position + (-visual.global_basis.z) * 1.3 + Vector3.UP * 0.45


## Посылка сообщает, что список носильщиков изменился
func on_parcel_holders_changed(p: Parcel) -> void:
	var mine := p.holders.has(peer_id)
	if mine and held_parcel != p:
		held_parcel = p
		instability = 0.0
		_parcel_offset = Vector3.ZERO
		_carry_basis = Basis.IDENTITY
		_releasing = false
	elif not mine and held_parcel == p:
		held_parcel = null
		instability = 0.0
		_releasing = false
		_pickup_cooldown = 0.4


## Урон корпусу. kind — чем ударило (для следов на броне):
## "burn" — луч, "hit" — удар, "pierce" — шипы, "scald" — пар/кипяток,
## "fall" — падение, "pressure" — давление на глубине. point — куда пришёлся удар.
func take_damage(amount: float, kind: String = "", point: Vector3 = Vector3.INF) -> void:
	if not is_local or is_dead or _invuln_timer > 0.0 or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	damage_flash.color.a = clampf(0.15 + amount * 0.01, 0.15, 0.45)
	_damage_marks(amount, kind, point)
	_maybe_lose_limb(amount, kind, point)
	if health <= 0.0:
		_die()


## Следы на броне (у себя и — по сети — у копий)
func _damage_marks(amount: float, kind: String, point: Vector3) -> void:
	var center := global_position + Vector3.UP * BODY_HEIGHT
	var r := clampf(0.05 + amount * 0.006, 0.05, 0.14)
	match kind:
		"burn":
			_burn_timer -= get_physics_process_delta_time()
			if _burn_timer > 0.0:
				return
			_burn_timer = 0.3
			_mark(SUIT.Mark.BURN, point if point != Vector3.INF else center, 0.08, 1.0)
			if randf() < 0.3:
				suit.emote(SUIT.Mood.HURT, 0.4)
			return
		"pierce":
			_mark(SUIT.Mark.PIERCE, point if point != Vector3.INF else center, 0.05, 0.0)
			_mark(SUIT.Mark.DENT, point if point != Vector3.INF else center, r, 0.0)
		"scald":
			for k in 3:
				var off := Vector3(randf_range(-0.3, 0.3), randf_range(-0.9, 0.2), randf_range(-0.25, 0.25))
				_mark(SUIT.Mark.SCALD, center + visual.global_basis * off, 0.14, 0.0)
		"fall":
			for k in 2:
				var off := Vector3(randf_range(-0.2, 0.2), randf_range(-1.05, -0.6), randf_range(-0.25, 0.1))
				_mark(SUIT.Mark.DENT, center + visual.global_basis * off, r, 0.0)
				_mark(SUIT.Mark.SCRATCH, center + visual.global_basis * (off + Vector3(0, 0.15, -0.05)), r * 1.3, 0.0)
		"pressure":
			# давление: корпус сминается складками
			var off := Vector3(randf_range(-0.3, 0.3), randf_range(-0.6, 0.5), randf_range(-0.25, 0.25))
			_mark(SUIT.Mark.CRUMPLE, center + visual.global_basis * off, 0.1, 0.0)
			_mark(10, center, 0.06, 0.0)   # трещины на визоре
		"hit":
			# столкновение: царапины вдоль удара, сильное — ещё и вмятина
			var at := point if point != Vector3.INF else center
			_mark(SUIT.Mark.SCRATCH, at, r * 2.0, 0.0)
			if amount >= 6.0:
				_mark(SUIT.Mark.DENT, at, r, 0.0)
			if point != Vector3.INF and point.y > global_position.y + 1.4:
				_mark(10, center, 0.12, 0.0)
		"thrown":
			# плюхнулся спиной: царапины на ранце и спине
			for k in 2:
				var off := Vector3(randf_range(-0.25, 0.25), randf_range(-0.3, 0.4), 0.3)
				_mark(SUIT.Mark.SCRATCH, center + visual.global_basis * off, r * 1.6, 0.0)
		_:
			if amount >= 3.0:
				_mark(SUIT.Mark.DENT, center + visual.global_basis * Vector3(randf_range(-0.3, 0.3), randf_range(-0.5, 0.4), -0.2), r, 0.0)
	if amount >= 3.0:
		suit.emote(SUIT.Mood.HURT, 0.6)


func _mark(kind: int, point: Vector3, radius: float, heat: float) -> void:
	_apply_mark(kind, point, radius, heat)
	if _online():
		_net_mark.rpc(kind, visual.global_transform.affine_inverse() * point, radius, heat)


func _apply_mark(kind: int, point: Vector3, radius: float, heat: float) -> void:
	if kind == 10:
		suit.crack_visor(radius * 2.0)
		return
	if kind == SUIT.Mark.BURN:
		heat = 1.0
	suit.add_mark(kind, point, radius, 1.0 if kind != SUIT.Mark.BURN else 0.45, heat)


@rpc("authority", "call_remote", "reliable")
func _net_mark(kind: int, local_point: Vector3, radius: float, heat: float) -> void:
	_apply_mark(kind, visual.global_transform * local_point, radius, heat)


@rpc("authority", "call_remote", "reliable")
func _net_respawned() -> void:
	suit.clear_marks()


func receive_hit(direction: Vector3, strength: float, contact: Vector3, kind: String = "hit") -> void:
	if not is_local or is_dead or _invuln_timer > 0.0:
		return
	var spark_point := (global_position + Vector3.UP * BODY_HEIGHT).lerp(contact, 0.5)
	_take_impact(direction, strength, spark_point, hazard_knockback, strength * hazard_damage, kind)


func receive_avalanche(push_dir: Vector3) -> void:
	if not is_local or is_dead or _invuln_timer > 0.0:
		return
	if held_parcel != null:
		_fumble()
	_hit_cooldown = 0.0
	_take_impact(push_dir, 13.0, global_position + Vector3.UP * BODY_HEIGHT, 1.1, 35.0)
	suit.set("_snow", 0.85)    # засыпало снегом
	_stagger_total = 1.4
	_stagger_timer = 1.4
	_shake = 0.5


func kill(reason: String = "") -> void:
	if not is_local or is_dead:
		return
	if reason != "":
		death_label.text = reason + "\nВозвращаемся в лагерь..."
	_die()


## Подбросить вверх (трамплин, гейзер). Можно добавить урон и раскачку посылки.
func launch(up_speed: float, damage: float = 0.0, parcel_shake: float = 0.0, parcel_damage: float = 0.0, soft_landing: bool = false, damage_kind: String = "hit") -> void:
	if not is_local or is_dead:
		return
	velocity.y = maxf(velocity.y, up_speed)
	if soft_landing:
		_soft_landing = true
	_coyote_timer = 0.0
	_thruster_power = 5.0
	_noise_burst += 0.6
	body.scale = Vector3(0.85, 1.15, 0.85)
	if damage > 0.0:
		take_damage(damage, damage_kind)
		_shake = maxf(_shake, 0.2)
	if held_parcel != null:
		if parcel_shake > 0.0 and _carry_mode() != 2:
			instability += parcel_shake
		if parcel_damage > 0.0:
			held_parcel.take_damage(parcel_damage)


## Резкий удар ветра: дрона толкает вбок и чуть подбрасывает, на миг он теряет опору
## (управление слабое), корпус качает. Урона нет.
func wind_shove(dir: Vector3, speed: float) -> void:
	if not is_local or is_dead or is_swimming or is_diving or is_frozen:
		return
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x += dir.x * speed
	velocity.z += dir.z * speed
	velocity.y = maxf(velocity.y, 2.2)
	_stagger_total = 0.45
	_stagger_timer = 0.45
	_stagger_strength = 0.5
	_shake = maxf(_shake, 0.25)


func apply_wind(wind_velocity: Vector3) -> void:
	if is_local:
		_wind += wind_velocity


## Контрольная точка: после поломки дрон появится здесь
func set_checkpoint(pos: Vector3) -> void:
	_spawn_position = pos


## Стойка со щитом (квест «Живые зеркала»)
func set_brace(on: bool) -> void:
	if is_local:
		_brace = on and not is_dead


## Горка и т.п.: «ощущение скорости» (0..1), держится, пока его подают каждый кадр
func set_speed_fx(amount: float) -> void:
	if is_local:
		_speed_fx = maxf(_speed_fx, clampf(amount, 0.0, 1.0))


func add_shake(amount: float) -> void:
	if is_local:
		_shake = maxf(_shake, amount)


func respawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_prev_velocity = Vector3.ZERO
	is_dead = false
	health = max_health
	stamina = stamina_max
	_exhausted_timer = 0.0
	_stagger_timer = 0.0
	_invuln_timer = invulnerable_time
	body.rotation = Vector3.ZERO
	frost = 0.0
	_update_ice_mask()
	_leave_water_state()
	is_frozen = false
	doomed = false
	_set_block_shape(false)
	_end_rolls()
	_break_progress = 0.0
	_block_grow = 0.0
	_wet_timer = 0.0
	_freeze_immunity = 0.0
	death_label.text = _default_death_text
	health_changed.emit(health, max_health)
	suit.clear_marks()
	if _online():
		_net_respawned.rpc()
	respawned.emit()


func _die() -> void:
	is_dead = true
	_dead_timer = respawn_delay
	is_sprinting = false
	_shake = 0.4
	sparks.global_position = global_position + Vector3.UP * BODY_HEIGHT
	sparks.restart()
	if held_parcel != null:
		_release_held(held_parcel.global_transform, Vector3(velocity.x, 1.5, velocity.z))
	died.emit()


# ---------------------------------------------------------------------------
#  Вода: плавание, выход на лёд, обледенение
# ---------------------------------------------------------------------------

func _frost_ratio() -> float:
	return clampf(frost / frost_full, 0.0, 1.0)


func _frost_mult() -> float:
	if ice_mask != 0:
		return lerpf(1.0, 0.75, _frost_ratio())    # и так волоку ногу / ползу
	return lerpf(1.0, frost_min_speed, _frost_ratio())


## Направление ввода относительно камеры (по горизонтали)
func _camera_direction() -> Vector3:
	var input_dir := _move_vec()
	var cam_basis := camera_pivot.global_transform.basis
	var forward := -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := cam_basis.x
	right.y = 0.0
	right = right.normalized()
	return right * input_dir.x - forward * input_dir.y


## Обледенение за кадр. water_depth: глубина в воде (м) или -1 — на воздухе.
func _frost_tick(delta: float, water_depth: float) -> void:
	_freeze_immunity -= delta
	doomed = frost >= frost_max * doom_frost and _freeze_immunity <= 0.0 and not is_frozen
	if water_depth >= 0.0:
		var rate := freeze_rate
		if is_diving:
			rate = dive_freeze_rate + dive_freeze_per_m * water_depth
		frost += rate * delta
	elif doomed:
		# за чертой: лёд сам дорастает до глыбы — даже на суше и у огня
		frost += doom_rate * delta
		if _wet_timer > 0.0:
			_wet_timer -= delta
	elif _wet_timer > 0.0 and _heat <= 1.0:
		_wet_timer -= delta          # мокрый корпус на морозе ещё обмерзает
		frost += wet_freeze * delta
	else:
		_wet_timer = 0.0
		frost -= (fire_thaw_rate if _heat > 1.0 else thaw_rate) * delta
	frost = clampf(frost, 0.0, frost_max)
	_update_ice_mask()
	if frost >= frost_max:
		if _freeze_immunity > 0.0:
			frost = frost_max - 0.01   # только что вырвался из глыбы — даём время
		elif not is_frozen and not is_dead:
			_freeze_solid()


## Холод сковывает по очереди: 25% — нога, 50% — вторая, 75% — рука (тает в обратном порядке)
func _update_ice_mask() -> void:
	var fv := clampf(frost / frost_max, 0.0, 1.0)
	if fv < ICE_STAGES[0] - 0.05 and ice_mask == 0:
		_ice_order.clear()
	if _ice_order.is_empty() and fv >= ICE_STAGES[0] - 0.05:
		var legs: Array[String] = ["leg_l", "leg_r"]
		legs.shuffle()
		_ice_order = [legs[0], legs[1], "arm_l" if randf() < 0.5 else "arm_r"]
	var m := 0
	for k in _ice_order.size():
		var kind: String = _ice_order[k]
		var b := _limb_bit(kind)
		var th: float = ICE_STAGES[k]
		var was := (ice_mask & b) != 0
		if has_limb(kind) and (fv >= th or (was and fv >= th - 0.03)):
			m |= b
	if m != ice_mask:
		_set_ice(m)


func _set_ice(m: int) -> void:
	var newly := m & ~ice_mask
	ice_mask = m
	suit.set_ice(m)
	if newly != 0 and is_local:
		_shake = maxf(_shake, 0.25)
	_after_limb_change()


## Есть ли рядом жаровня (проверяем пару раз в секунду)
func _update_heat(delta: float) -> void:
	_heat_timer -= delta
	if _heat_timer > 0.0:
		return
	_heat_timer = 0.4
	_heat = 1.0
	for h in get_tree().get_nodes_in_group("heat_source"):
		var r: float = h.get("heat_radius") if h.get("heat_radius") != null else 6.0
		if (h as Node3D).global_position.distance_to(global_position) < r:
			_heat = heat_thaw_mult
			return


## R — стряхнуть лёд (стоит выносливости)
func _shake_off_ice() -> void:
	if frost < 0.3 or _shake_anim > 0.0 or stamina < shake_stamina * 0.5:
		return
	if doomed:
		# лёд уже слишком толстый — не стряхнуть, только трясёт
		_shake_anim = 0.45
		_shake = maxf(_shake, 0.15)
		return
	stamina = maxf(stamina - shake_stamina, 0.0)
	_regen_timer = stamina_regen_delay
	frost = maxf(frost - shake_amount, 0.0)
	_shake_anim = 0.45
	_chunks_fx.restart()
	_noise_burst += 0.3


## Вмёрз в глыбу
func _freeze_solid() -> void:
	_tumble = false
	_flop_t = 0.0
	is_frozen = true
	doomed = false
	_break_progress = 0.0
	_block_grow = 0.0
	is_sprinting = false
	_wet_timer = 0.0
	_charge = -1.0
	_shake = maxf(_shake, 0.35)
	_noise_burst += 0.8
	_chunks_fx.restart()
	if held_parcel != null:
		_release_held(held_parcel.global_transform, Vector3(velocity.x * 0.5, 1.0, velocity.z * 0.5))
	if held_friend != null:
		_lift_call(held_friend, false, Vector3.ZERO)
	if rolling_block != null:
		_roll_call(rolling_block, false, Vector3.ZERO)
	_crush_timer = 0.0
	_frozen_yaw = visual.rotation.y
	_roll_basis = Basis.IDENTITY
	_roll_last = global_position
	_set_block_shape(true)
	if is_swimming:
		is_swimming = false
		is_diving = true      # в воде глыба тонет и ложится на дно (это делает _frozen_process)


## Глыба: на суше скользит и катится (её можно толкать и катить), в воде тонет на дно
## и там медленно ломает корпус. Жмёшь кнопки — раскалываешь. Верёвкой — вытаскивают.
func _frozen_process(delta: float) -> void:
	# изнутри лёд не разбить — только дёргаешься (глыба чуть вздрагивает).
	# Раскалывают друзья (R рядом), боты и жаровня.
	for a in BREAK_KEYS:
		if _just(a):
			_block_jolt = maxf(_block_jolt, 0.35)
	var roped: Node = rope.roped_by(self)

	if is_diving:
		var water: float = _lake.water_y(global_position.z)
		var p := global_position
		var in_hole: bool = _lake.is_hole(p.x, p.z, -0.4)
		var hauled: bool = roped != null and roped.pulling
		var hv := Vector3(velocity.x, 0.0, velocity.z)
		if hauled:
			# тянут верёвкой: подо льдом — к ближайшей полынье; в полынье — вверх,
			# а у поверхности — по воде к спасателю, к краю льда (там выволакивают)
			var goal: Vector3 = roped.p.global_position
			var float_lvl := water - 1.0
			if not in_hole:
				var hole := _nearest_hole()
				if hole != Vector3.INF:
					goal = hole
			elif p.y < float_lvl - 1.2:
				goal = p                     # сначала поднимаем со дна
			var to := Vector3(goal.x - p.x, 0.0, goal.z - p.z)
			var want := to.normalized() * minf(to.length() * 1.5, 2.6) if to.length() > 0.3 else Vector3.ZERO
			hv = hv.move_toward(want, 6.0 * delta)
			velocity.y = move_toward(velocity.y, 2.0 if in_hole else 0.5, 4.0 * delta)
			_block_jolt = maxf(_block_jolt, 0.25)
		else:
			# глыба со скафандром тяжелее воды — тонет и ложится на дно (течение тащит её и по дну)
			# тяжёлую глыбу на дне течение не сдвигает (её всегда можно найти и вытащить)
			var stw := IceRiver.stream_at(p.x, p.z) * (0.0 if is_on_floor() else 0.2)
			hv = hv.move_toward(stw, 1.5 * delta)
			velocity.y = move_toward(velocity.y, -2.6, 3.0 * delta)
		velocity.x = hv.x
		velocity.z = hv.z
		move_and_slide()
		if hauled:
			# упёрлась в тонкий лёд над полыньёй — глыба пробивает его
			for i in get_slide_collision_count():
				var col := get_slide_collision(i)
				var thin := _thin_ice_of(col.get_collider())
				if thin:
					thin.request_break_at(col.get_position())
					_block_jolt = 1.0
		p = global_position
		if in_hole:
			var float_y := water - 1.0
			if p.y > float_y:
				global_position.y = float_y
				velocity.y = 0.0
			# у поверхности и тянут — у края выволакивают на лёд (в сторону спасателя)
			if hauled and p.y > float_y - 0.4:
				var to_owner: Vector3 = roped.p.global_position - p
				to_owner.y = 0.0
				var edge: Vector3 = _lake.nearest_ice(p, 2.3, to_owner.normalized())
				if edge != Vector3.INF:
					_haul_block_out(edge, to_owner.normalized())
					return
		elif p.y > water - 2.3:
			global_position.y = water - 2.3
			velocity.y = minf(velocity.y, 0.0)
		# на дне корпус медленно ломается
		if is_on_floor() and not hauled:
			_crush_timer -= delta
			if _crush_timer <= 0.0:
				_crush_timer = 0.5
				take_damage(bed_crush * 0.5, "pressure")
				_block_jolt = maxf(_block_jolt, 0.35)
				if _uw:
					_uw.set("hurt", 0.6)
	else:
		# на суше лёд очень медленно подтаивает (≈2 минуты), у жаровни — быстро
		_break_progress += (0.35 if _heat > 1.0 else self_thaw) * delta
		if rolled_by != null and is_instance_valid(rolled_by):
			# меня катят: глыба перед катящим, у самой земли
			var r := rolled_by
			var fwd: Vector3 = -r.visual.global_basis.z
			fwd.y = 0.0
			var goal: Vector3 = r.global_position + fwd.normalized() * 1.4
			var to := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
			var want := to * 9.0
			if want.length() > 9.0:
				want = want.normalized() * 9.0
			velocity.x = want.x
			velocity.z = want.z
			if not is_on_floor():
				velocity += get_gravity() * fall_gravity_mult * delta
			move_and_slide()
		else:
			if rolled_by != null:
				rolled_by = null
			# глыба падает, скользит по льду и катится; её тянут верёвкой, толкают
			if not is_on_floor():
				velocity += get_gravity() * fall_gravity_mult * delta
			var grip := surface_grip if is_on_floor() else 0.05
			var h := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, 4.0 * grip * delta)
			velocity.x = h.x
			velocity.z = h.z
			velocity = rope.adjust_velocity(velocity, delta)
			# на склоне сама катится вниз
			if is_on_floor():
				var n := get_floor_normal()
				velocity.x += n.x * 9.8 * 0.8 * delta
				velocity.z += n.z * 9.8 * 0.8 * delta
			move_and_slide()
		if global_position.y < fall_limit_y and not is_dead:
			velocity = Vector3.ZERO
			is_frozen = false
			_set_block_shape(false)
			_die()

	if _break_progress >= 1.0:
		_break_free()

	_update_noise(delta, false)
	_update_visual(delta, Vector3.ZERO, 0.0, false)
	_update_camera(delta)
	_update_hud()
	_prev_velocity = velocity
	_send_state(delta)


## Плитка тонкого льда (frozen_lake.gd), в которую упёрлись
func _thin_ice_of(obj: Object) -> Node:
	var n := obj as Node
	for k in 3:
		if n == null:
			return null
		if n.has_method("request_break_at"):
			return n
		n = n.get_parent()
	return null


## Глыбу вытянули верёвкой из полыньи на лёд
func _haul_block_out(edge: Vector3, dir: Vector3) -> void:
	_leave_water_state()
	_wet_timer = 0.0
	global_position = edge + Vector3.UP * 0.25
	velocity = dir * 2.5 + Vector3.UP * 2.5
	_was_on_floor = false
	_block_jolt = 1.0
	_shake = maxf(_shake, 0.25)
	var splash_pos := Vector3(edge.x, _lake.water_y(edge.z) + 0.2, edge.z)
	_splash_fx.global_position = splash_pos
	_splash_fx.restart()
	if _online():
		_net_splash_fx.rpc(splash_pos)


## Глыба раскололась
func _break_free() -> void:
	# мороз оставил следы: краска потрескалась сеткой и побелела
	var c0 := global_position + Vector3.UP * BODY_HEIGHT
	for k in 6:
		var off := Vector3(randf_range(-0.35, 0.35), randf_range(-0.95, 0.55), randf_range(-0.3, 0.3))
		_mark(SUIT.Mark.FROSTBITE, c0 + visual.global_basis * off, randf_range(0.09, 0.15), 0.0)
	is_frozen = false
	_break_progress = 0.0
	frost = frost_max * 0.35      # корка ещё осталась, но ниже черты
	doomed = false
	_update_ice_mask()
	_freeze_immunity = 6.0
	_set_block_shape(false)
	if rolled_by != null and is_instance_valid(rolled_by):
		rolled_by._roll_call(self, false, Vector3.ZERO)
	rolled_by = null
	_play_shatter()
	_shake = maxf(_shake, 0.3)
	body.scale = Vector3(1.15, 0.85, 1.15)
	_noise_burst += 1.0
	if is_diving:
		velocity.y = 0.6
	else:
		velocity.y = 2.5


## Пока во льду — тело шире (шар), чтобы глыбу было удобно толкать и катить
func _set_block_shape(on: bool) -> void:
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null:
		return
	if on:
		if _body_shape == null:
			_body_shape = cs.shape
		var sp := SphereShape3D.new()
		sp.radius = 0.86
		cs.shape = sp
		cs.position.y = 0.88
	elif _body_shape != null:
		cs.shape = _body_shape
		cs.position.y = 0.875


func _play_shatter() -> void:
	_block_grow = 0.0
	_ice_block.visible = false
	_shatter_fx.global_position = global_position + Vector3.UP * BLOCK_HEIGHT
	_shatter_fx.restart()


## Друг рядом вмёрз — E раскалывает его глыбу
func _find_frozen_buddy() -> Node:
	for d in get_tree().get_nodes_in_group("player"):
		if d == self or not d.is_frozen:
			continue
		var to: Vector3 = (d as Node3D).global_position - global_position
		if Vector2(to.x, to.z).length() < 2.4 and absf(to.y) < 2.6:
			return d
	return null


func _try_chip_buddy() -> bool:
	if arms_count() == 0:
		return false
	var buddy = _find_frozen_buddy()
	if buddy == null:
		return false
	buddy._block_jolt = 1.0
	if buddy.is_local:
		buddy._rpc_chip_ice()
	elif _online():
		buddy._rpc_chip_ice.rpc_id(buddy.peer_id)
	suit.punch()
	_noise_burst += 0.3
	return true


# ---------------------------------------------------------------------------
#  Глыба с другом: упрись — толкаешь (катится и скользит по льду),
#  E — взять и катить перед собой, E — отпустить (катится дальше), Q — разогнать и толкнуть.
# ---------------------------------------------------------------------------
func _block_near(max_dist: float) -> Node3D:
	var best: Node3D = null
	var bd := max_dist
	for d in get_tree().get_nodes_in_group("player"):
		if d == self or not d.is_frozen or d.is_diving or d.is_swimming or d.is_dead:
			continue
		var to: Vector3 = (d as Node3D).global_position - global_position
		var dist := Vector2(to.x, to.z).length()
		if dist < bd and absf(to.y) < 1.5:
			bd = dist
			best = d
	return best


func _try_grab_block() -> bool:
	if held_parcel != null or held_friend != null or rolling_block != null or not is_on_floor():
		return false
	if arms_count() == 0 or held_limb != null:
		return false
	var b := _block_near(2.1)
	if b == null or b.rolled_by != null:
		return false
	_roll_call(b, true, Vector3.ZERO)
	return true


func _roll_call(block: Node3D, on: bool, vel: Vector3) -> void:
	if is_bot or block.get("is_bot") or not (Network.in_game and Network.is_online()):
		_rpc_roll(int(block.peer_id), on, vel)
	else:
		_rpc_roll.rpc(int(block.peer_id), on, vel)


@rpc("any_peer", "call_local", "reliable")
func _rpc_roll(block_id: int, on: bool, vel: Vector3) -> void:
	var b = Network.find_player(block_id)
	if b == null:
		return
	if on:
		if rolling_block != null or b.rolled_by != null:
			return
		rolling_block = b
		b.rolled_by = self
		add_collision_exception_with(b)
		b.add_collision_exception_with(self)
		suit.reach()
	else:
		if rolling_block == b:
			rolling_block = null
		if b.rolled_by == self:
			b.rolled_by = null
			if b.is_local and vel != Vector3.ZERO:
				b.velocity = Vector3(vel.x, maxf(b.velocity.y, 0.0), vel.z)
		var me := self
		get_tree().create_timer(0.5).timeout.connect(func():
			if is_instance_valid(me) and is_instance_valid(b):
				me.remove_collision_exception_with(b)
				b.remove_collision_exception_with(me))


## Сбросить все «катания» (телепорт, возрождение)
func _end_rolls() -> void:
	if rolling_block != null and is_instance_valid(rolling_block):
		_roll_call(rolling_block, false, Vector3.ZERO)
	rolling_block = null
	if rolled_by != null and is_instance_valid(rolled_by):
		rolled_by._roll_call(self, false, Vector3.ZERO)
	rolled_by = null


## Иду в глыбу — толкаю её. Качу — руки упираются в лёд.
func _update_push(direction: Vector3, target_speed: float, has_input: bool, delta: float) -> void:
	_push_point = Vector3.ZERO
	_push_send_t -= delta
	if rolling_block != null:
		if not is_instance_valid(rolling_block) or not rolling_block.is_frozen:
			rolling_block = null
			return
		var to := rolling_block.global_position - global_position
		to.y = 0.0
		_push_point = rolling_block.global_position + Vector3.UP * 0.95 - to.normalized() * 0.82
		return
	if not has_input or held_parcel != null or held_friend != null:
		return
	var b := _block_near(1.85)
	if b == null or b.rolled_by != null:
		return
	var to := b.global_position - global_position
	to.y = 0.0
	var n := to.normalized()
	if direction.normalized().dot(n) < 0.45:
		return
	_push_point = b.global_position + Vector3.UP * 0.95 - n * 0.82
	if _push_send_t <= 0.0:
		_push_send_t = 0.1
		b.push_block(n * target_speed * 0.95)


## Меня (глыбу) толкнули
func push_block(v: Vector3) -> void:
	if is_local:
		_apply_push(v)
	elif _online():
		_rpc_push.rpc_id(get_multiplayer_authority(), v)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_push(v: Vector3) -> void:
	_apply_push(v)


func _apply_push(v: Vector3) -> void:
	if not is_frozen or is_diving or rolled_by != null:
		return
	var sp := v.length()
	if sp < 0.01:
		return
	var n := v / sp
	var along := velocity.x * n.x + velocity.z * n.z
	if along < sp:
		velocity.x += n.x * (sp - along)
		velocity.z += n.z * (sp - along)
	_block_jolt = maxf(_block_jolt, 0.2)


func _enter_water() -> void:
	_tumble = false
	_flop_t = 0.0
	is_diving = true          # дрон тяжёлый — сразу уходит под воду
	is_swimming = false
	_swim_anchor = global_position
	_edge_point = Vector3.INF
	_edge_timer = 0.0
	_wet_timer = 0.0
	_heavy_timer = 0.0
	if _lake is PhysicsBody3D:
		add_collision_exception_with(_lake)
	# тяжёлый скафандр по инерции уходит вглубь — сразу не вынырнуть
	velocity.y = -minf(plunge_speed + maxf(-velocity.y, 0.0) * 0.15, 7.0)
	_plunge_t = 0.65
	_water_time = 0.0
	_charge = -1.0
	is_sprinting = false
	_exhausted_timer = 0.0
	_stagger_timer = 0.0
	_noise_burst += 1.0
	_shake = maxf(_shake, 0.2)
	var splash_pos := Vector3(global_position.x, _lake.water_y(global_position.z) + 0.2, global_position.z)
	_splash_fx.global_position = splash_pos
	_splash_fx.restart()
	if _online():
		_net_splash_fx.rpc(splash_pos)
	# Посылка выскальзывает из рук и плавает рядом
	if held_parcel != null:
		held_parcel.take_damage(5.0)
		_release_held(held_parcel.global_transform, Vector3(velocity.x * 0.3, 0.5, velocity.z * 0.3))


func _leave_water_state() -> void:
	_in_stream = false
	_water_time = 0.0
	_plunge_t = 0.0
	if (is_swimming or is_diving) and _lake is PhysicsBody3D:
		remove_collision_exception_with(_lake)
	if (is_swimming or is_diving) and frost > 1.0:
		_wet_timer = wet_time
	is_swimming = false
	is_diving = false
	_edge_point = Vector3.INF


## Вынырнул в полынье
func _surface() -> void:
	_in_stream = false
	is_diving = false
	is_swimming = true
	_heavy_timer = 0.0
	_swim_anchor = global_position
	velocity.y = 0.0
	var splash_pos := Vector3(global_position.x, _lake.water_y(global_position.z) + 0.2, global_position.z)
	_splash_fx.global_position = splash_pos
	_splash_fx.restart()
	if _online():
		_net_splash_fx.rpc(splash_pos)


func _start_dive() -> void:
	is_swimming = false
	is_diving = true
	_heavy_timer = 0.0
	velocity.y = -1.0


## Под водой: тонем, пока не держишь Пробел. Подо льдом всплыть нельзя.
func _dive_process(delta: float) -> void:
	var water: float = _lake.water_y(global_position.z)
	var depth := maxf(water - (global_position.y + BODY_HEIGHT), 0.0)
	_frost_tick(delta, depth)
	if is_frozen:
		return
	if held_parcel != null:
		_release_held(held_parcel.global_transform, Vector3(0, 0.5, 0))

	var fr := _frost_ratio()
	var roped: Node = rope.roped_by(self)
	rope.local_update(delta)
	_water_time += delta
	_plunge_t = maxf(_plunge_t - delta, 0.0)
	# чем дольше в ледяной воде — тем тяжелее всплывать
	var tired := clampf(_water_time / water_tire_time, 0.0, 1.0)
	var rising := (_held("jump") and _plunge_t <= 0.0) or roped != null
	var target_vy := -sink_speed * (1.0 + 0.6 * fr)
	if rising:
		target_vy = rise_speed * lerpf(1.0, 0.5, fr) * lerpf(1.0, 0.35, tired)
		if roped != null:
			target_vy = rise_speed * 1.2
	var acc := 4.0 if target_vy > velocity.y else 2.5
	if _plunge_t > 0.0:
		acc = 9.0           # всплеск: вода быстро гасит скорость падения (уходишь на ~2 м)
	velocity.y = move_toward(velocity.y, target_vy, acc * delta)

	var direction := _camera_direction()
	var current := IceRiver.current_at(global_position.x, global_position.z) * smoothstep(0.8, 2.5, depth)
	if is_on_floor():
		current *= 0.15   # стоящего на дне течение почти не сдвигает
	# сильное течение-«река» подо льдом: утаскивает почти сразу, даже у поверхности
	var stream := IceRiver.stream_at(global_position.x, global_position.z) * smoothstep(0.15, 0.8, depth)
	if is_on_floor():
		stream *= 0.5
	current += stream
	_in_stream = stream.length() > 0.8
	var speed := dive_speed * maxf(_frost_mult(), 0.5)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(direction * speed + current, (7.0 if _in_stream else 4.0) * delta)
	if roped != null:
		# держусь за верёвку: плыву к ближайшей полынье (подо льдом наверх не выйти)
		var hole := _nearest_hole()
		if hole != Vector3.INF:
			var th := Vector3(hole.x - global_position.x, 0.0, hole.z - global_position.z)
			if th.length() > 0.4:
				horizontal = horizontal.move_toward(th.normalized() * 2.4, 8.0 * delta)
			else:
				horizontal = horizontal.move_toward(Vector3.ZERO, 8.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	# В полынье — выныриваем; подо льдом упираемся в лёд
	var p := global_position
	var in_hole: bool = _lake.is_hole(p.x, p.z, -0.35)
	if in_hole and velocity.y > 0.0 and p.y >= water - float_depth - 0.05:
		_surface()   # выныриваем, только когда гребём вверх
	else:
		var ceiling := water - 1.85
		if not in_hole and p.y > ceiling:
			if velocity.y > 1.0:
				_shake = maxf(_shake, 0.12)          # стукнулся о лёд снизу
				body.scale = Vector3(1.15, 0.85, 1.15)
			global_position.y = ceiling
			velocity.y = minf(velocity.y, 0.0)

	# Давление на глубине
	if depth > pressure_depth:
		_pressure_timer -= delta
		if _pressure_timer <= 0.0:
			_pressure_timer = 0.5
			take_damage((depth - pressure_depth) * pressure_damage * 0.5, "pressure")
			_shake = maxf(_shake, 0.1)
			if _uw:
				_uw.set("hurt", 1.0)
	else:
		_pressure_timer = 0.0

	_pickup_cooldown -= delta
	_update_noise(delta, false)
	_update_visual(delta, direction, speed, false)
	_update_camera(delta)
	_update_hud()
	_prev_velocity = velocity
	_send_state(delta)


func _swim_process(delta: float) -> void:
	_frost_tick(delta, 0.0)
	_water_time += delta
	if is_frozen:
		return

	# Держимся на плаву
	var water: float = _lake.water_y(global_position.z)
	var target_y := water - float_depth + sin(_time * 2.2) * 0.05
	velocity.y = lerpf(velocity.y, (target_y - global_position.y) * 5.0, clampf(6.0 * delta, 0.0, 1.0))

	var roped: Node = rope.roped_by(self)
	rope.local_update(delta)
	# Обледеневший дрон тяжёлый: без Пробела снова уходит под воду. Ctrl — нырнуть.
	if roped != null:
		_heavy_timer = 0.0        # держусь за верёвку — не тону
	elif _frost_ratio() > 0.6 and not _held("jump"):
		_heavy_timer += delta
	else:
		_heavy_timer = maxf(_heavy_timer - delta * 2.0, 0.0)
	if _heavy_timer > 1.2 or _just("quiet"):
		_start_dive()
		return

	# Гребём относительно камеры
	var direction := _camera_direction()
	var speed := swim_speed * maxf(_frost_mult(), 0.55)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(direction * speed, 8.0 * delta)

	# течение тянет и на поверхности полыньи (к краю, под который оно уходит)
	horizontal += IceRiver.stream_at(global_position.x, global_position.z) * 0.3
	# По поверхности под лёд не заплыть: впереди лёд — останавливаемся у края
	var here := global_position
	if roped != null:
		horizontal = rope.adjust_velocity(horizontal, delta)
		horizontal.y = 0.0
	if horizontal.length() > 0.05:
		var ahead := here + horizontal.normalized() * 0.55
		if not _lake.is_hole(ahead.x, ahead.z):
			horizontal = Vector3.ZERO
	# Если над головой оказался лёд (полынья затянулась/сдвинулись) — уходим под воду
	if not _lake.is_hole(here.x, here.z):
		_start_dive()
		return
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	# Посылка в руках мокнет
	if held_parcel != null:
		_soak_timer += delta
		if _soak_timer >= 1.0:
			_soak_timer = 0.0
			held_parcel.take_damage(parcel_soak)

	# Где ближайший край льда (проверяем не каждый кадр)
	_edge_timer -= delta
	if _edge_timer <= 0.0:
		_edge_timer = 0.12
		var prefer := -visual.global_basis.z
		if direction.length() > 0.1:
			prefer = direction.normalized()
		_edge_point = _lake.nearest_ice(global_position, climb_reach, prefer)

	# Посылку можно выловить из воды (E) или отпустить; E рядом с вмёрзшим другом — разбить лёд
	if not _releasing and _just("interact"):
		if held_parcel:
			_release_held(held_parcel.global_transform, Vector3.ZERO)
		else:
			_try_pick_up()
	if _releasing:
		_release_timer -= delta
		if _release_timer <= 0.0:
			_releasing = false
	_pickup_cooldown -= delta

	if _edge_point != Vector3.INF and _just("jump"):
		_climb_out()
		return
	# тянут за верёвку — у края выползаем на лёд сами
	if roped != null and roped.pulling:
		var to_owner: Vector3 = roped.p.global_position - global_position
		to_owner.y = 0.0
		var edge: Vector3 = _lake.nearest_ice(global_position, climb_reach + 0.6, to_owner.normalized())
		if edge != Vector3.INF:
			_edge_point = edge
			_climb_out()
			suit.emote(SUIT.Mood.HAPPY, 1.5)
			return

	_update_noise(delta, false)
	_update_visual(delta, direction, speed, false)
	_update_camera(delta)
	_update_hud()
	_prev_velocity = velocity
	_send_state(delta)


func _climb_out() -> void:
	if _edge_point == Vector3.INF:
		return
	var target := _edge_point
	var to := target - global_position
	to.y = 0.0
	_leave_water_state()
	global_position = target
	velocity = to.normalized() * 1.5 + Vector3.UP * 2.0
	_was_on_floor = false
	body.scale = Vector3(0.85, 1.2, 0.85)
	_thruster_power = 4.0
	if to.length() > 0.05:
		visual.rotation.y = atan2(-to.x, -to.z)


# ---------------------------------------------------------------------------
#  Камера
# ---------------------------------------------------------------------------

func _rotate_camera(yaw: float, pitch: float) -> void:
	camera_pivot.rotation.y += yaw
	camera_pivot.rotation.x = clampf(
		camera_pivot.rotation.x + pitch,
		deg_to_rad(min_pitch_deg),
		deg_to_rad(max_pitch_deg)
	)


func _handle_gamepad_look(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.0:
		_rotate_camera(-look.x * joy_look_speed * delta, -look.y * joy_look_speed * delta)


func _update_camera(delta: float) -> void:
	if not controlled:
		return
	var running := is_sprinting and Vector3(velocity.x, 0.0, velocity.z).length() > walk_speed
	_speed_fx = maxf(_speed_fx - delta * 1.5, 0.0)
	var fov_target := lerpf(sprint_fov if running else base_fov, 102.0, _speed_fx)
	camera.fov = lerpf(camera.fov, fov_target, 6.0 * delta)
	var arm := lerpf(5.3 if running else 4.7, 7.0, _speed_fx)
	if is_diving:
		arm = 3.4    # под водой мутно — камера ближе к дрону
	spring_arm.spring_length = lerpf(spring_arm.spring_length, arm, 4.0 * delta)
	_shake = maxf(_shake - delta * 1.2, 0.0)
	var shake := _shake + _speed_fx * 0.035
	if running and is_on_floor():
		shake += 0.012
	camera.h_offset = randf_range(-1.0, 1.0) * shake
	camera.v_offset = randf_range(-1.0, 1.0) * shake


# ---------------------------------------------------------------------------
#  Выносливость, шум
# ---------------------------------------------------------------------------

func _update_stamina(delta: float, has_input: bool, carrying: bool) -> void:
	if _exhausted_timer > 0.0:
		_exhausted_timer -= delta
		is_sprinting = false
		stamina = minf(stamina + stamina_regen * 0.5 * delta, stamina_max)
		return

	if _held("sprint"):
		_sprint_hold += delta
	else:
		_sprint_hold = 0.0
	var wants_sprint := _sprint_hold >= sprint_hold_time and has_input and stamina > 0.0 \
		and _frost_ratio() < 0.25 and not _no_sprint
	if wants_sprint and not is_sprinting:
		_thruster_power = 4.0
		body.scale = Vector3(0.88, 1.12, 0.88)
	is_sprinting = wants_sprint

	if is_sprinting:
		stamina -= stamina_drain * (carry_stamina_mult if carrying else 1.0) * delta
		_regen_timer = stamina_regen_delay
		if stamina <= 0.0:
			stamina = 0.0
			is_sprinting = false
			_exhausted_timer = exhausted_duration
			body.scale = Vector3(1.15, 0.85, 1.15)
			if held_parcel:
				instability += 0.2
	else:
		_regen_timer -= delta
		if _regen_timer <= 0.0:
			stamina = minf(stamina + stamina_regen * delta, stamina_max)


func _update_noise(delta: float, has_input: bool) -> void:
	var base := 0.0
	var moving := is_on_floor() and Vector3(velocity.x, 0.0, velocity.z).length() > 0.5
	if moving and has_input:
		if is_sprinting:
			base = run_noise
		elif _held("quiet"):
			base = quiet_noise
		else:
			base = walk_noise
	_noise_burst = maxf(_noise_burst - delta * 1.5, 0.0)
	noise = clampf(base + _noise_burst, 0.0, 2.0)


# ---------------------------------------------------------------------------
#  Поверхность и столкновения
# ---------------------------------------------------------------------------

func _update_surface_grip() -> void:
	surface_grip = 1.0
	_floor_collider = null
	if not is_on_floor():
		return
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.3,
		global_position + Vector3.DOWN * 0.3
	)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	_floor_collider = collider
	var mat: PhysicsMaterial = null
	if collider is StaticBody3D:
		mat = (collider as StaticBody3D).physics_material_override
	elif collider is RigidBody3D:
		mat = (collider as RigidBody3D).physics_material_override
	if mat:
		surface_grip = clampf(mat.friction, min_grip, 1.0)


func _handle_collisions(pre_velocity: Vector3, delta: float) -> void:
	var strongest := 0.0
	var hit_normal := Vector3.ZERO
	var hit_point := Vector3.ZERO
	var pre_h := Vector3(pre_velocity.x, 0.0, pre_velocity.z)

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) > 0.6:
			continue
		var into := -pre_h.dot(n)
		var rb := col.get_collider() as RigidBody3D
		if rb != null:
			# Физику предметов считает хост — пинать их может только он
			if multiplayer.is_server():
				var push_dir := Vector3(-n.x, 0.0, -n.z).normalized()
				var kick := 0.0
				if into > hit_threshold:
					kick = into * minf(rb.mass, 5.0) * kick_strength
				rb.apply_impulse(push_dir * (push_force * delta + kick), col.get_position() - rb.global_position)
			into *= clampf(rb.mass / light_object_mass, 0.0, 1.0)
		if into > strongest:
			strongest = into
			hit_normal = n
			hit_point = col.get_position()

	if strongest > hit_threshold:
		var dmg := (strongest - hit_threshold + 2.0) * wall_damage
		_take_impact(hit_normal, strongest, hit_point, wall_knockback, dmg, "hit")


func _take_impact(push_dir: Vector3, strength: float, contact: Vector3, knock_mult: float, health_damage: float, kind: String = "hit") -> void:
	if _hit_cooldown > 0.0:
		return
	_hit_cooldown = 0.3
	_noise_burst += 1.2

	push_dir.y = 0.0
	push_dir = push_dir.normalized()
	velocity.x = push_dir.x * strength * knock_mult
	velocity.z = push_dir.z * strength * knock_mult
	velocity.y = maxf(velocity.y, minf(1.5 + strength * 0.25, 5.0))

	_stagger_total = clampf(0.2 + strength * 0.06, 0.25, 0.9)
	_stagger_timer = _stagger_total
	_stagger_strength = clampf(strength / 8.0, 0.3, 1.0)
	_shake = clampf(strength * 0.03, 0.05, 0.35)
	body.scale = Vector3(1.1, 0.88, 1.1)
	sparks.global_position = contact
	sparks.restart()
	if _online():
		_net_hit_fx.rpc(contact)

	take_damage(health_damage, kind, contact)

	if held_parcel != null:
		held_parcel.take_damage(strength * hit_damage)
		if _carry_mode() != 2:
			instability += strength * hit_instability


# ---------------------------------------------------------------------------
#  Переноска
# ---------------------------------------------------------------------------

## 0 — ничего, 1 — обычная посылка, 2 — тяну тяжёлый груз один, 3 — несём тяжёлый вдвоём
func _carry_mode() -> int:
	if held_parcel == null:
		return 0
	if held_parcel.required_carriers <= 1:
		return 1
	return 3 if held_parcel.is_lifted() else 2


func _find_nearest_parcel() -> Parcel:
	var best: Parcel = null
	var best_dist := INF
	for node in pickup_zone.get_overlapping_bodies():
		var p := node as Parcel
		if p == null or not p.can_be_grabbed_by(peer_id):
			continue
		var d := global_position.distance_squared_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best


func _try_pick_up() -> bool:
	if _pickup_cooldown > 0.0 or _stagger_timer > 0.0 or is_dead or held_parcel != null or held_limb != null:
		return false
	if arms_count() < 2:
		return false              # одной рукой груз не поднять
	var p := _find_nearest_parcel()
	if p == null:
		return false
	grab_parcel(p)
	return true


## Взять конкретную посылку (подтянул верёвкой, бот и т.п.)
func grab_parcel(p: Parcel) -> void:
	if p == null or not p.can_be_grabbed_by(peer_id):
		return
	_pickup_cooldown = 0.3
	suit.reach()
	suit.emote(SUIT.Mood.HAPPY, 1.2)
	p.request_pickup(peer_id)   # хост решит и сообщит всем


func _put_down() -> void:
	if held_parcel == null:
		return
	suit.reach()
	if _carry_mode() == 1:
		var forward := -visual.global_basis.z
		var pos := global_position + forward * 0.9 + Vector3.UP * 0.35
		_release_held(Transform3D(Basis(Vector3.UP, visual.global_rotation.y), pos),
			Vector3(velocity.x, 0.0, velocity.z) * 0.5)
	else:
		_release_held(held_parcel.global_transform, Vector3(velocity.x, 0.0, velocity.z) * 0.5)


func _throw(power := 0.8) -> void:
	suit.throw_anim()
	_release_held(held_parcel.global_transform, _parcel_throw_vel(power))


# ---------------------------------------------------------------------------
#  Бросок с замахом: держишь Q — шкала растёт, отпускаешь — летит.
#  Пунктир показывает, куда упадёт.
# ---------------------------------------------------------------------------
func _can_throw() -> bool:
	return held_friend != null or rolling_block != null or held_limb != null or (held_parcel != null and _carry_mode() == 1 and not _releasing)


func _throw_power(c: float) -> float:
	return lerpf(0.35, 1.4, clampf(c, 0.0, 1.0))


func _do_throw(power: float) -> void:
	if held_limb != null and _repair_target == null:
		suit.throw_anim()
		_drop_limb(_throw_aim_dir() * (2.5 + 6.0 * power) + Vector3.UP * (1.5 + 2.0 * power) + Vector3(velocity.x, 0.0, velocity.z) * 0.5)
	elif rolling_block:
		# разогнать глыбу и толкнуть — покатится дальше сама
		suit.throw_anim()
		_roll_call(rolling_block, false, _throw_aim_dir() * (3.0 + 6.5 * power) + Vector3(velocity.x, 0.0, velocity.z) * 0.5)
	elif held_friend:
		_throw_friend(power)
	elif held_parcel != null and _carry_mode() == 1:
		_throw(power)
	_throw_land = Vector3.INF


## Куда бросаю: у человека — куда смотрит камера, у бота — куда смотрит сам
func _throw_aim_dir() -> Vector3:
	var fwd := -visual.global_basis.z
	var aim := -camera.global_basis.z if controlled else fwd
	aim.y = 0.0
	if aim.length() < 0.1:
		aim = fwd
		aim.y = 0.0
	return aim.normalized()


func _parcel_throw_vel(power: float) -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z) + _throw_aim_dir() * throw_speed * 1.25 * power \
		+ Vector3.UP * (1.8 + 2.2 * power)


func _friend_throw_vel(power: float) -> Vector3:
	return _throw_aim_dir() * 8.5 * power + Vector3.UP * (4.0 + 3.0 * power) + Vector3(velocity.x, 0.0, velocity.z) * 0.5


func _make_throw_aim() -> void:
	_throw_dots = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = 26
	var dot := SphereMesh.new()
	dot.radius = 0.03
	dot.height = 0.06
	dot.radial_segments = 8
	dot.rings = 4
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.vertex_color_use_as_albedo = true
	dm.no_depth_test = true
	dot.material = dm
	mm.mesh = dot
	_throw_dots.multimesh = mm
	_throw_dots.top_level = true
	_throw_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_throw_dots.visible = false
	add_child(_throw_dots)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.52
	tm.rings = 28
	tm.ring_segments = 4
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.no_depth_test = true
	rm.albedo_color = Color(1.0, 0.85, 0.3, 0.85)
	tm.material = rm
	_throw_ring = MeshInstance3D.new()
	_throw_ring.mesh = tm
	_throw_ring.top_level = true
	_throw_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_throw_ring.visible = false
	add_child(_throw_ring)


## Пунктир полёта и метка, куда упадёт (видно только тому, кто бросает)
func _update_throw_aim() -> void:
	var show := _charge >= 0.0 and controlled and rolling_block == null
	_throw_dots.visible = show
	_throw_ring.visible = show
	if not show:
		return
	var pw := _throw_power(_charge)
	var from: Vector3
	var vel: Vector3
	var g_up := 9.8
	var g_down := 9.8
	if held_friend:
		from = held_friend.global_position + Vector3.UP * 0.5
		vel = _friend_throw_vel(pw)
		g_up = 9.8 * rise_gravity_mult
		g_down = 9.8 * fall_gravity_mult
	elif held_limb != null:
		from = held_limb.global_position
		vel = _throw_aim_dir() * (4.0 + 8.0 * pw) + Vector3.UP * (2.0 + 2.5 * pw) + Vector3(velocity.x, 0.0, velocity.z) * 0.5
	else:
		from = held_parcel.global_position
		vel = _parcel_throw_vel(pw)
	# летим по шагам, пока не упрёмся в землю
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = [get_rid()]
	if held_friend:
		ex.append((held_friend as CollisionObject3D).get_rid())
	if held_parcel:
		ex.append(held_parcel.get_rid())
	if held_limb:
		ex.append((held_limb as CollisionObject3D).get_rid())
	var pts: Array[Vector3] = [from]
	var q := from
	var v := vel
	var land := Vector3.INF
	for k in 60:
		var dt := 0.05
		v.y -= (g_up if v.y > 0.0 else g_down) * dt
		var nq := q + v * dt
		var rq := PhysicsRayQueryParameters3D.create(q, nq, 1)
		rq.exclude = ex
		var hit := space.intersect_ray(rq)
		if not hit.is_empty():
			land = hit["position"]
			pts.append(land)
			break
		pts.append(nq)
		q = nq
		if q.y < global_position.y - 30.0:
			break
	_throw_land = land
	var mm := _throw_dots.multimesh
	var n := mm.instance_count
	var total := pts.size() - 1
	var flow := fmod(_time * 1.6, 1.0)
	var col := Color(0.35, 0.9, 1.0).lerp(Color(1.0, 0.55, 0.2), _charge)
	for i in n:
		var u := (float(i) + flow) / n
		var f := u * total
		var i0 := mini(int(f), total - 1)
		var pt: Vector3 = pts[i0].lerp(pts[i0 + 1], f - i0) if total > 0 else from
		var sc := lerpf(0.6, 1.15, u)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * sc), pt))
		mm.set_instance_color(i, Color(col.r, col.g, col.b, lerpf(0.3, 0.95, u)))
	if land != Vector3.INF:
		var pulse := 1.0 + sin(_time * 9.0) * 0.08
		_throw_ring.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(pulse, 1.0, pulse)), land + Vector3.UP * 0.05)
		(_throw_ring.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, 0.85)
	else:
		_throw_ring.visible = false


func _fumble() -> void:
	var forward := -visual.global_basis.z
	var side := visual.global_basis.x * randf_range(-1.5, 1.5)
	var speed := Vector3(velocity.x, 0.0, velocity.z).length()
	held_parcel.take_damage(fumble_damage + speed * 1.5)
	_release_held(held_parcel.global_transform, velocity + forward * 1.5 + side + Vector3.UP * 2.5)


func _release_held(xform: Transform3D, vel: Vector3) -> void:
	if held_parcel == null:
		return
	_releasing = true
	_release_timer = 1.0
	_pickup_cooldown = 0.4
	instability = 0.0
	held_parcel.request_release(peer_id, xform, vel)


func _update_carry(delta: float, just_landed: bool, pre_move_velocity: Vector3) -> void:
	if held_parcel == null or _releasing:
		return
	var mode := _carry_mode()
	if mode == 2:
		instability = 0.0
		return

	var h_vel := Vector3(velocity.x, 0.0, velocity.z)
	var prev_h := Vector3(_prev_velocity.x, 0.0, _prev_velocity.z)
	var accel_vec := (h_vel - prev_h) / delta
	var speed_mult := carry_speed_mult if mode == 1 else heavy_speed_mult
	var carry_walk := walk_speed * speed_mult
	var carry_sprint := sprint_speed * speed_mult

	if is_sprinting and h_vel.length() > carry_walk * 0.9:
		instability += sprint_instability * delta
	var speed_over := clampf((prev_h.length() - carry_walk) / maxf(carry_sprint - carry_walk, 0.01), 0.0, 1.0)
	if _stagger_timer <= 0.0:
		instability += accel_vec.length() * speed_over * turn_instability * delta
	instability += _last_wind.length() * wind_instability * delta
	if just_landed:
		instability += maxf(0.0, -pre_move_velocity.y - safe_landing_speed) * landing_instability
	if not is_sprinting:
		var rec := stability_recovery * (1.0 if h_vel.length() < 0.5 else 0.6)
		instability = maxf(0.0, instability - rec * delta)

	if instability >= 1.0:
		_fumble()
		return

	var target_offset := (-accel_vec * 0.012).limit_length(0.25)
	if _charge > 0.0:
		# замах: посылка уходит назад и вверх
		target_offset += (visual.global_basis.z * 0.26 + Vector3.UP * 0.22) * _charge
	_parcel_offset = _parcel_offset.lerp(target_offset, 10.0 * delta)
	_wobble_time += delta
	var w := instability * 0.4
	_carry_basis = Basis.from_euler(Vector3(
		sin(_wobble_time * 17.0) * w, 0.0, sin(_wobble_time * 13.0 + 1.3) * w))


# ---------------------------------------------------------------------------
#  Анимация (работает и для своего дрона, и для копий)
# ---------------------------------------------------------------------------

## Лёд подо мной вот-вот провалится (зовёт ice_river.gd у всех игроков)
func ice_warning(_center: Vector3) -> void:
	_ice_warn_t = 0.6
	if suit:
		suit.emote(SUIT.Mood.HURT, 1.2)


func _update_visual(delta: float, direction: Vector3, target_speed: float, just_landed: bool) -> void:
	_ice_warn_t = maxf(_ice_warn_t - delta, 0.0)
	_update_ripped()
	_act_visuals(delta)
	var on_floor := is_grounded()
	var h_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var has_input := direction.length() > 0.1
	var exhausted := _exhausted_timer > 0.0
	var running := is_sprinting and on_floor and h_speed > walk_speed * 0.8
	var in_water := is_swimming or is_diving

	_update_frost_visual(delta)

	if carried_by != null and is_instance_valid(carried_by):
		# лежу на поднятых руках друга: голова вправо от него, лицом в небо
		var h := carried_by
		var hb := Basis(Vector3.UP, h.visual.global_rotation.y)
		var y_axis := hb.x
		var z_axis := Vector3.DOWN
		var x_axis := y_axis.cross(z_axis)
		var center := h.global_position + Vector3.UP * (2.12 + sin(_time * 9.0) * 0.025)
		visual.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), center - y_axis * 0.95)
	elif _tumble:
		# лечу в панике: корпус ровно, чуть откидывает назад к земле, покачивает
		var back := clampf(0.12 - velocity.y * 0.06, 0.05, 0.6)
		_flail_pitch = lerpf(_flail_pitch, back, clampf(delta * 5.0, 0.0, 1.0))
		visual.position = Vector3.ZERO
		visual.rotation = Vector3(_flail_pitch, visual.rotation.y, sin(_time * 7.0) * 0.14)
	elif _flop_t > 0.0:
		# плюхнулся на спину, полежал, встаю
		var fp := 1.0 - _flop_t / FLOP_TIME
		var lie := 1.45
		var pitch := 0.0
		if fp < 0.1:
			pitch = lerpf(_flail_pitch, lie, smoothstep(0.0, 1.0, fp / 0.1))
		elif fp < 0.58:
			var u := (fp - 0.1) / 0.48
			pitch = lie - 0.08 * absf(sin(u * PI * 3.0)) * (1.0 - u)
		else:
			pitch = lerpf(lie, 0.0, smoothstep(0.0, 1.0, (fp - 0.58) / 0.42))
		var wl := clampf(pitch / lie, 0.0, 1.0)
		var yaw := visual.rotation.y
		visual.rotation = Vector3(pitch, yaw, 0.0)
		visual.position = Basis(Vector3.UP, yaw) * Vector3(0.0, 0.17 * wl, -0.8 * wl)
	elif not is_frozen:
		if absf(visual.rotation.x) > 0.001 or absf(visual.rotation.z) > 0.001 or visual.position.length() > 0.001:
			visual.transform = Transform3D(Basis(Vector3.UP, visual.global_rotation.y), Vector3.ZERO)
		if _brace and is_local:
			var cam_yaw := camera_pivot.global_rotation.y
			visual.rotation.y = lerp_angle(visual.rotation.y, cam_yaw, 18.0 * delta)
		elif _vis_mode == 3 and is_instance_valid(_vis_parcel):
			# несём вдвоём — смотрю на ящик, ногами иду куда надо (боком, задом)
			var tp := _vis_parcel.global_position - global_position
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-tp.x, -tp.z), 10.0 * delta)
		elif _towed_dir() != Vector3.ZERO and is_on_floor():
			# волокут на верёвке — разворачивает лицом к тянущему
			var td := _towed_dir()
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-td.x, -td.z), 8.0 * delta)
		elif has_input:
			var target_yaw := atan2(-direction.x, -direction.z)
			visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, turn_speed * delta)

	var thrust_target := 0.3
	if not on_floor:
		thrust_target = 1.5
	if in_water:
		thrust_target = 0.0
	if running:
		thrust_target = 2.5
	_thruster_power = lerpf(_thruster_power, thrust_target, 10.0 * delta)
	sprint_trail.emitting = running
	steam.emitting = exhausted or is_dead or (_heat > 1.0 and frost > 0.5)

	suit.animate(delta, _suit_state(direction, target_speed, just_landed, has_input, running))
	visual.visible = not (_invuln_timer > 0.0 and fmod(_time, 0.2) < 0.07)


## Посылка в руках этого дрона и как её держат (у копий ищем по списку носильщиков)
func _update_vis_parcel(delta: float) -> void:
	if is_local:
		_vis_parcel = held_parcel
		_vis_mode = _carry_mode()
		return
	_vis_parcel_t -= delta
	if _vis_parcel_t > 0.0 and (_vis_parcel == null or is_instance_valid(_vis_parcel)):
		return
	_vis_parcel_t = 0.25
	_vis_parcel = null
	_vis_mode = 0
	if (_net_flags & F_CARRY) == 0:
		return
	for p in get_tree().get_nodes_in_group("parcel"):
		var pc := p as Parcel
		if pc and pc.holders.has(peer_id):
			_vis_parcel = pc
			if pc.required_carriers <= 1:
				_vis_mode = 1
			else:
				_vis_mode = 3 if pc.is_lifted() else 2
			return


## Всё, что нужно скафандру для анимации в этом кадре
func _suit_state(direction: Vector3, target_speed: float, just_landed: bool, has_input: bool, running: bool) -> Dictionary:
	_update_vis_parcel(get_physics_process_delta_time())
	var on_floor := is_grounded()
	var h_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var skating := is_local and on_floor and _floor_collider is Object and is_instance_valid(_floor_collider) \
		and (_floor_collider as Object).has_meta("skate")
	var icy := on_floor and surface_grip < 0.5 and not skating
	var look_yaw := 0.0
	var look_pitch := 0.0
	if is_local:
		look_yaw = wrapf(camera_pivot.global_rotation.y - visual.global_rotation.y, -PI, PI)
		if absf(look_yaw) > 2.0:
			look_yaw = 0.0          # камера спереди — смотрим вперёд, а не за спину
		look_pitch = camera_pivot.rotation.x + 0.3
	var stg := 0.0
	if _stagger_timer > 0.0:
		stg = clampf(_stagger_timer / maxf(_stagger_total, 0.01), 0.0, 1.0) * _stagger_strength
	var stick: Node3D = visual.get_node_or_null("HockeyStick") as Node3D
	return {
		"vel": velocity,
		"on_floor": on_floor,
		"running": running,
		"quiet": is_local and _held("quiet") and on_floor and not is_sprinting,
		"exhausted": _exhausted_timer > 0.0,
		"stagger": stg,
		"dead": is_dead,
		"downed": downed,
		"swim": is_swimming,
		"dive": is_diving,
		"rising": velocity.y > 0.2,
		"frozen": is_frozen,
		"frost": clampf(frost / frost_full, 0.0, 1.0),
		"wind": _last_wind,
		"shake": clampf(_shake_anim / 0.45, 0.0, 1.0),
		"carry": _vis_mode,
		"parcel": _vis_parcel,
		"carry_basis": _carry_basis,
		"carry_offset": _parcel_offset,
		"stick": stick,
		"skating": skating,
		"slipping": icy and has_input and is_local,
		"sliding": icy and not has_input and h_speed > 2.5,
		"target_speed": target_speed,
		"just_landed": just_landed,
		"land_speed": -_prev_velocity.y if is_local else -_net_prev_vy,
		"thrust": _thruster_power,
		"hp": clampf(health / max_health, 0.0, 1.0) if is_local else _net_hp,
		"look_yaw": look_yaw,
		"look_pitch": look_pitch,
		"stamina": clampf(stamina / stamina_max, 0.0, 1.0),
		"heat": _heat > 1.0,
		"wet": _wet_timer > 0.0,
		"rid": get_rid(),
		"weight": _vis_parcel.carry_weight() if _vis_parcel is Parcel else 2,
		"lift": held_friend if is_instance_valid(held_friend) else null,
		"carried": carried_by != null,
		"tumble": _tumble,
		"rescue_role": rescue_role,
		"rescue_t": rescue_t,
		"clasp": rescue_clasp() if rescue_role != 0 else Vector3.ZERO,
		"rope": rope.pose() if rope else {},
		"throw_charge": maxf(_charge, 0.0),
		"push_point": _push_point,
		"balance": _ice_warn_t > 0.0,
		"repair": _repair_pose(),
		"rip": _rip_pose(),
		"ripped": ripped_info,
		"flop": (1.0 - _flop_t / FLOP_TIME) if _flop_t > 0.0 else -1.0,
		"carry_limb": held_limb if held_limb != null and is_instance_valid(held_limb) and act_mode != 1 else null,
		"carry_limb_end": held_limb.get("_end") if held_limb != null and is_instance_valid(held_limb) else Vector3(0, -0.7, 0),
		"carry_limb_kind": String(held_limb.kind) if held_limb != null and is_instance_valid(held_limb) else "",
		"plunge": _plunge_t > 0.0 and is_diving,
		"rope_grip": _rope_grip_dir(),
		"wave": is_bot and has_node("Brain") and bool(get_node("Brain").get("calling_help")),
		"self": self,
	}


## Меня вытаскивают верёвкой-петлёй: куда тянуть руки (к спасателю)
## Волокут ли меня на верёвке по суше (направление к тянущему)
func _towed_dir() -> Vector3:
	if is_swimming or is_diving or is_frozen or rope == null:
		return Vector3.ZERO
	var g := _rope_grip_dir()
	g.y = 0.0
	return g.normalized() if g.length() > 0.01 else Vector3.ZERO


func _rope_grip_dir() -> Vector3:
	if rope == null:
		return Vector3.ZERO
	var r = rope.roped_by(self)
	if r == null:
		return Vector3.ZERO
	# 1 = M.RESCUE (в воде держусь за трос), 2 = M.TETHER (на суше — меня волокут)
	var towed: bool = r.mode == 2 and r.pulling and Vector2(r.p.global_position.x - global_position.x, r.p.global_position.z - global_position.z).length() > r.length - 0.3
	if r.mode != 1 and not towed:
		return Vector3.ZERO
	var d: Vector3 = (r.hand_point() - (global_position + Vector3.UP * 1.0))
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO


## Лёд на дроне: корка, сосульки, отваливающиеся куски, глыба
func _update_frost_visual(delta: float) -> void:
	var vis := clampf(frost / frost_max, 0.0, 1.0)
	if is_frozen:
		vis = 1.0
	# корпус покрывается инеем мягче — главное видно по вмёрзшим рукам/ногам
	_frost_mat.set_shader_parameter("amount", vis if is_frozen else vis * 0.6)

	# Сосульки отрастают по одной и покачиваются
	for i in _icicles.size():
		var info := _icicle_info[i]
		var length := info.y * clampf((vis - info.x) / 0.2, 0.0, 1.0)
		var ic := _icicles[i]
		ic.visible = length > 0.01
		if ic.visible:
			ic.scale = Vector3(1.0, length, 1.0)
			ic.position = _icicle_base[i] - Vector3(0, length * 0.5, 0)
			ic.rotation.z = sin(_time * 3.0 + i) * 0.06

	# При таянии и стряхивании лёд отваливается кусками
	var step := int(frost)
	if step < _last_frost_step and not is_swimming and not is_diving and not is_frozen:
		_chunks_fx.restart()
	_last_frost_step = step

	var in_water := is_swimming or is_diving
	_frost_sparkles.emitting = vis > 0.15 and not in_water and not is_frozen
	_drips.emitting = (is_swimming or (vis > 0.25 and _heat > 1.0) or _wet_timer > 0.0) and not is_diving
	_bubbles.emitting = is_diving

	# Глыба: быстро нарастает, трясётся от ударов, трещины растут, катится
	if is_frozen != _vis_frozen:
		_vis_frozen = is_frozen
		_set_block_shape(is_frozen)
		if is_frozen:
			_frozen_yaw = visual.rotation.y
			_roll_basis = Basis.IDENTITY
			_roll_last = global_position
	_block_grow = move_toward(_block_grow, 1.0 if is_frozen else 0.0, delta * 3.0)
	_ice_block.visible = is_frozen and _block_grow > 0.01
	if is_frozen:
		# катится: поворот по пройденному пути (радиус глыбы ~0.9 м)
		var dp := global_position - _roll_last
		dp.y = 0.0
		var dl := dp.length()
		if dl > 0.0005 and dl < 2.0:
			_roll_basis = (Basis(Vector3.UP.cross(dp / dl).normalized(), dl / 0.9) * _roll_basis).orthonormalized()
		_roll_last = global_position
		var c := Vector3(0.0, BLOCK_HEIGHT, 0.0)
		visual.transform = Transform3D(_roll_basis, c) * Transform3D(Basis(Vector3.UP, _frozen_yaw), -c)
	if _ice_block.visible:
		_block_jolt = move_toward(_block_jolt, 0.0, delta * 4.0)
		var j := _block_jolt * 0.07
		var g := 1.0 - pow(1.0 - _block_grow, 3.0)
		var jit := Vector3(randf_range(-j, j), BLOCK_HEIGHT + randf_range(-j, j) * 0.5, randf_range(-j, j))
		_ice_block.transform = Transform3D((_roll_basis * Basis(Vector3.UP, 0.4)).scaled(Vector3(g, g, g)), jit)
		_block_mat.set_shader_parameter("cracks", _break_progress)
		_block_mat.set_shader_parameter("crush", 1.0 - clampf(health / max_health, 0.0, 1.0) if is_diving else 0.0)


# ---------------------------------------------------------------------------
#  Интерфейс (только свой дрон)
# ---------------------------------------------------------------------------

func _update_hud() -> void:
	if not controlled:
		return
	_update_meter()
	_update_visor()
	var mode := _carry_mode()
	if _frost_row:
		_frost_row.visible = frost > 0.05 or is_frozen
		if _frost_mark:
			_frost_mark.visible = not is_frozen
		if is_frozen:
			_frost_caption.text = "Лёд трескается"
			_frost_bar.value = _break_progress
			_frost_bar.modulate = Color(1.0, 1.0, 1.0)
		else:
			_frost_caption.text = "Обледенение"
			var fv := clampf(frost / frost_max, 0.0, 1.0)
			_frost_bar.value = fv
			var col := Color(0.6, 0.85, 1.0)
			if doomed:
				col = Color(1.0, 0.45, 0.35)
			if fv > 0.75 or doomed:   # вот-вот вмёрзнет — полоска мигает
				col = col.lerp(Color(1, 1, 1), (sin(_time * 14.0) + 1.0) * 0.5)
			_frost_bar.modulate = col
	if is_frozen or is_diving:
		if is_frozen:
			var pct := roundi(_break_progress * 100.0)
			if is_diving and rope.roped_by(self) != null:
				prompt_label.text = "Тебя тянут крюком из воды!  Держись…"
			elif is_diving:
				prompt_label.text = "ГЛЫБА НА ДНЕ! Корпус трещит — изнутри лёд не разбить.\nЖди, пока друг вытащит тебя верёвкой с крюком!"
			else:
				prompt_label.text = "ЗАМЁРЗ В ГЛЫБУ! Изнутри не разбить — нужен друг (R по льду) или жаровня (%d%%)" % pct
				if rolled_by != null:
					prompt_label.text += "\nТебя катят!"
				elif _heat > 1.0:
					prompt_label.text += "\nЖаровня рядом — лёд тает"
				else:
					prompt_label.text += "\nСам лёд тает очень долго (~2 мин)"
		else:
			var p := global_position
			var depth := maxf(_lake.water_y(p.z) - (p.y + BODY_HEIGHT), 0.0)
			if _in_stream:
				prompt_label.text = "ТЕЧЕНИЕ! Тебя несёт подо льдом — плыви поперёк струи (вбок), ищи столбы света!"
			elif _plunge_t > 0.0:
				prompt_label.text = "Плюх! Тяжёлый скафандр тянет на глубину…"
			elif _lake.is_hole(p.x, p.z):
				prompt_label.text = "Глубина %.1f м — держи Пробел, чтобы всплыть" % depth
				if _water_time > water_tire_time * 0.4:
					prompt_label.text += "\nЛедяная вода сковывает — всплывать всё тяжелее!"
			else:
				prompt_label.text = "Ты подо льдом! Плыви к столбам света — там полынья.  Пробел — вверх"
			if depth > pressure_depth:
				prompt_label.text += "\nДАВЛЕНИЕ! Корпус трещит — поднимайся!"
		parcel_label.visible = false
		stability_row.visible = false
		stamina_row.visible = false
		var hp0 := health / max_health
		health_bar.value = hp0
		health_bar.modulate = Color(1, 0.3, 0.25).lerp(Color(0.45, 1, 0.5), hp0)
		death_label.visible = is_dead
		damage_flash.color.a = move_toward(damage_flash.color.a, 0.0, get_physics_process_delta_time() * 0.8)
		return
	if is_swimming:
		prompt_label.text = "Пробел — выбраться на лёд" if _edge_point != Vector3.INF else "Ты в воде! Плыви к краю полыньи"
		if _frost_ratio() > 0.6:
			prompt_label.text += "\nТяжёлый ото льда — держи Пробел, иначе утонешь"
		parcel_label.visible = held_parcel != null
		if held_parcel != null:
			parcel_label.text = "%s мокнет — %d кр" % [held_parcel.display_name, held_parcel.price]
		stability_row.visible = false
		stamina_row.visible = false
		health_bar.value = health / max_health
		death_label.visible = false
		damage_flash.color.a = move_toward(damage_flash.color.a, 0.0, get_physics_process_delta_time() * 0.8)
		return
	if held_parcel != null:
		parcel_label.visible = true
		parcel_label.text = "%s — %d кр" % [held_parcel.display_name, held_parcel.price]
		match mode:
			1:
				var w := held_parcel.carry_weight()
				prompt_label.text = ["Лёгкая — под мышкой.  ", "", "Тяжёлая — несёшь в обнимку, медленно.  "][clampi(w, 1, 3) - 1] + "E — положить     Q (держать) — замах и бросок"
			2:
				prompt_label.text = "Тяжело! Нужен второй курьер — пока тянешь волоком.  E — отпустить"
			3:
				var partner_far := false
				for d in held_parcel._holder_drones():
					if d != self and d.global_position.distance_to(global_position) > heavy_warn_distance:
						partner_far = true
				prompt_label.text = "Держитесь ближе друг к другу!" if partner_far else "Несёте вдвоём.  E — поставить"
		stability_row.visible = mode != 2
		var s := 1.0 - instability
		stability_bar.value = s
		var col := Color(1, 0.3, 0.25).lerp(Color(0.45, 1, 0.5), s)
		if s < 0.3:
			col = col.lerp(Color.WHITE, (sin(_time * 20.0) + 1.0) * 0.25)
		stability_bar.modulate = col
	elif carried_by != null:
		prompt_label.text = "Тебя подняли над головой!  Жми Пробел / WASD — вырваться (%d/10)" % _struggle
		parcel_label.visible = false
		stability_row.visible = false
	elif held_friend != null:
		prompt_label.text = "Друг над головой!  Q (держать) — замах, отпусти — бросок     E — поставить"
		parcel_label.visible = false
		stability_row.visible = false
	elif rescue_role != 0:
		prompt_label.text = "Тяну из воды!" if rescue_role == 1 else "Тебя вытаскивают!"
		parcel_label.visible = false
		stability_row.visible = false
	else:
		var p := _find_nearest_parcel()
		var rh: String = rope.hint() if rope else ""
		var lp_near := _limb_near(1.7) if held_limb == null and arms_count() > 0 else null
		if not ripped_info.is_empty():
			prompt_label.text = "Тебе отрывают %s!  Жми Пробел / WASD — вырывайся!" % limb_name(String(ripped_info.get("kind", "")), true)
		elif _repair_target != null and held_limb != null:
			prompt_label.text = "%s  держи E  (%d%%)" % [_repair_stage_text(), roundi(_repair_t / REPAIR_TIME * 100.0)]
		elif _rip_target != null:
			var left := RIP_BOLTS.size() - _act_bolts
			prompt_label.text = ("Упёрся ногой, тяну %s… болтов держится: %d  — держи F" % [limb_name(_rip_kind, true), left]) if left > 0 \
				else "Последний рывок!  держи F"

		elif held_limb != null:
			var rc := _repair_candidate()
			var who = Network.find_player(int(held_limb.owner_id))
			var whose: String = (" (%s)" % who.player_name) if who != null and who != self else (" (твоя)" if who == self else "")
			if rc != null:
				prompt_label.text = "Держи E — прикрутить %s другу%s" % [limb_name(held_limb.kind, true), whose]
			else:
				prompt_label.text = "В руке %s%s.  Q (держать) — кинуть     E — положить" % [limb_name(held_limb.kind), whose]
		elif lp_near != null:
			var ow = Network.find_player(int(lp_near.owner_id))
			prompt_label.text = "E — поднять оторванную %s%s" % [limb_name(lp_near.kind, true), (" (" + ow.player_name + ")") if ow != null and ow != self else " (твою)"]
		elif doomed:
			prompt_label.text = "ЛЁД СКОВЫВАЕТ КОРПУС — сейчас вмёрзнешь в глыбу!\nУ жаровни глыба растает быстро"
		elif rolling_block != null:
			prompt_label.text = "Катишь глыбу с другом!  E — отпустить (покатится дальше)     Q (держать) — разогнать и толкнуть"
		elif _block_near(2.1) != null:
			prompt_label.text = "E — взять глыбу и катить     Иди в неё — толкать     R — бить по льду"
		elif _find_frozen_buddy() != null:
			prompt_label.text = "R — бить по льду вокруг друга"
		elif _find_rescue_target() != null:
			prompt_label.text = "E — вытащить друга из воды за руку"
		elif rh != "" and rope.state != ROPE.S.NONE:
			prompt_label.text = rh
		elif p == null and _friend_in_front(1.9) != null and is_on_floor():
			prompt_label.text = "E — поднять друга над головой (для смеха)" + ("\n" + rh if rh != "" else "")
		elif p == null and rh != "":
			prompt_label.text = rh
		elif p == null:
			prompt_label.text = ""
			if _wet_timer > 0.0:
				prompt_label.text = "Мокрый корпус замерзает на морозе!"
			elif frost > 2.0:
				prompt_label.text = "R — стряхнуть лёд" + ("  (у жаровни тает быстро)" if _heat <= 1.0 else "  — жаровня греет")
		elif arms_count() < 2:
			prompt_label.text = "Одной рукой груз не поднять — пусть друг прикрутит руку"
		elif p.required_carriers > 1:
			prompt_label.text = "E — взяться за тяжёлый груз (нужно двое)"
		else:
			prompt_label.text = "E — взять груз"
		parcel_label.visible = false
		stability_row.visible = false

	var exhausted := _exhausted_timer > 0.0
	stamina_row.visible = exhausted or is_sprinting or stamina < stamina_max - 0.5
	stamina_bar.value = stamina / stamina_max
	if exhausted:
		stamina_caption.text = "Выдохся!"
		stamina_bar.modulate = Color(1, 0.35, 0.3)
	else:
		stamina_caption.text = "Выносливость"
		stamina_bar.modulate = Color(1, 0.85, 0.35)

	var hp := health / max_health
	health_bar.value = hp
	health_bar.modulate = Color(1, 0.3, 0.25).lerp(Color(0.45, 1, 0.5), hp)
	damage_flash.color.a = move_toward(damage_flash.color.a, 0.0, get_physics_process_delta_time() * 0.8)
	death_label.visible = is_dead


## Стекло визора: иней с краёв (обледенение), капли после воды, всплеск при падении
func _update_visor() -> void:
	if _visor_mat == null:
		return
	var dt := get_physics_process_delta_time()
	var fr := 1.0 if is_frozen else clampf(frost / frost_max, 0.0, 1.0)
	if is_swimming or is_diving:
		_visor_wet = 1.0
	else:
		_visor_wet = move_toward(_visor_wet, 0.0, dt / 9.0)
	if _plunge_t > 0.5:
		_visor_splash = 1.0
	_visor_splash = move_toward(_visor_splash, 0.0, dt * 1.8)
	var vs := get_viewport().get_visible_rect().size
	_visor_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	_visor_mat.set_shader_parameter("frost", fr)
	_visor_mat.set_shader_parameter("wet", _visor_wet if not is_diving else 0.0)
	_visor_mat.set_shader_parameter("splash", _visor_splash)
	_visor.visible = fr > 0.01 or _visor_wet > 0.01 or _visor_splash > 0.01


## Шкала силы: замах Q или раскрутка лассо
func _update_meter() -> void:
	if throw_meter == null:
		return
	if _charge >= 0.0:
		throw_meter.value = maxf(_charge, 0.02)
		throw_meter.distance = Vector2(_throw_land.x - global_position.x, _throw_land.z - global_position.z).length() if _throw_land != Vector3.INF else 0.0
		throw_meter.caption = "Сила броска — отпусти Q" if held_parcel == null else "Сила броска — отпусти Q"
	elif rope and rope.state == ROPE.S.SWING:
		throw_meter.value = maxf(rope.charge(), 0.02)
		throw_meter.distance = rope.range_now()
		throw_meter.caption = "Дальность броска крюка — отпусти ЛКМ"
	else:
		throw_meter.value = 0.0


# ---------------------------------------------------------------------------
#  Инвентарь
# ---------------------------------------------------------------------------
func has_item(id: String) -> bool:
	return items.has(id)


## Кто-то привязал меня верёвкой (или отвязал: owner == null)
func on_roped(owner: Node, rope_mode: int) -> void:
	if owner == null:
		return
	if rope_mode == ROPE.M.RESCUE:
		suit.emote(SUIT.Mood.HAPPY, 2.0)
	if is_bot and has_node("Brain"):
		get_node("Brain").call("on_roped", owner, rope_mode)


# ---------------------------------------------------------------------------
#  Друг над головой: поднять (E), кинуть (Q), поставить (E).
#  Поднятый может вырваться — жми Пробел/WASD.
# ---------------------------------------------------------------------------
func _friend_in_front(max_dist: float) -> Node3D:
	var fwd := -visual.global_basis.z
	var best: Node3D = null
	var best_d := max_dist
	for d in get_tree().get_nodes_in_group("player"):
		if d == self or d.is_dead or d.is_frozen or d.is_swimming or d.is_diving:
			continue
		if d.carried_by != null or d.held_friend != null or d.rescue_role != 0 or d.is_carrying():
			continue
		var to: Vector3 = (d as Node3D).global_position - global_position
		var dist := Vector2(to.x, to.z).length()
		if dist < best_d and absf(to.y) < 1.0 and fwd.dot(Vector3(to.x, 0, to.z).normalized()) > 0.1:
			best_d = dist
			best = d
	return best


func _try_lift_friend() -> bool:
	if held_parcel != null or held_friend != null or not is_on_floor() or _stagger_timer > 0.0:
		return false
	if arms_count() < 2 or legs_count() < 2 or held_limb != null:
		return false              # нужны обе руки и обе ноги
	var f := _friend_in_front(1.9)
	if f == null:
		return false
	_lift_call(f, true, Vector3.ZERO)
	return true


func _put_friend_down() -> void:
	if held_friend:
		suit.reach()
		_lift_call(held_friend, false, Vector3.ZERO)


func _throw_friend(power := 1.0) -> void:
	if held_friend == null:
		return
	var aim := _throw_aim_dir()
	visual.rotation.y = atan2(-aim.x, -aim.z)
	var vel := _friend_throw_vel(power)
	_noise_burst += 0.6
	_lift_call(held_friend, false, vel)


## Поднять/отпустить/кинуть — у всех игроков сразу (боты — только у хоста, без сети)
func _lift_call(friend: Node3D, on: bool, vel: Vector3) -> void:
	if is_bot or friend.get("is_bot") or not (Network.in_game and Network.is_online()):
		_rpc_lift(int(friend.peer_id), on, vel)
	else:
		_rpc_lift.rpc(int(friend.peer_id), on, vel)


@rpc("any_peer", "call_local", "reliable")
func _rpc_lift(friend_id: int, on: bool, vel: Vector3) -> void:
	var f = Network.find_player(friend_id)
	if f == null:
		return
	if on:
		if held_friend != null or f.carried_by != null:
			return
		held_friend = f
		f.carried_by = self
		f._struggle = 0
		f._held_t = 0.0
		add_collision_exception_with(f)
		f.add_collision_exception_with(self)
		suit.emote(SUIT.Mood.HAPPY, 1.5)
		f.suit.emote(SUIT.Mood.HURT, 0.8)
		if f.is_bot and f.has_node("Brain"):
			f.get_node("Brain").call("on_lifted", self)
	else:
		if held_friend == f:
			held_friend = null
		if f.carried_by == self:
			f.carried_by = null
			if vel != Vector3.ZERO:
				suit.throw_anim()
			if f.is_local:
				f._after_lift(self, vel)
		var me := self
		get_tree().create_timer(0.7).timeout.connect(func():
			if is_instance_valid(me) and is_instance_valid(f):
				me.remove_collision_exception_with(f)
				f.remove_collision_exception_with(me))


## Меня отпустили: поставили перед собой или бросили
func _after_lift(holder: Node3D, vel: Vector3) -> void:
	var yaw: float = holder.visual.global_rotation.y + PI
	visual.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
	if vel != Vector3.ZERO:
		velocity = vel
		_tumble = true
		_throw_speed = vel.length()
		_flail_pitch = 0.0
		_soft_landing = true
		_was_on_floor = false
		_coyote_timer = 0.0
		suit.emote(SUIT.Mood.PANIC, 3.0)
	else:
		var fwd: Vector3 = -holder.visual.global_basis.z
		global_position = holder.global_position + fwd * 1.1 + Vector3.UP * 0.4
		velocity = Vector3.ZERO


## Меня держат над головой: еду вместе с держащим, можно вырваться
func _carried_process(delta: float) -> void:
	var h := carried_by
	if not is_instance_valid(h) or bool(h.get("is_dead")):
		carried_by = null
		_after_lift(self if not is_instance_valid(h) else h, Vector3.UP * 2.0)
		return
	_held_t += delta
	_flop_t = 0.0
	velocity = h.velocity
	global_position = h.global_position + Vector3.UP * 1.95
	for a in BREAK_KEYS:
		if _just(a):
			_struggle += 1
			_noise_burst += 0.1
	if is_bot and _held_t > 8.0:
		_struggle = 99
	if _struggle >= 10:
		var back: Vector3 = h.visual.global_basis.z
		h._lift_call(self, false, back * 2.5 + Vector3.UP * 4.0)
		return
	_update_noise(delta, false)
	_update_visual(delta, Vector3.ZERO, 0.0, false)
	_update_camera(delta)
	_update_hud()
	_prev_velocity = velocity
	_send_state(delta)


# ---------------------------------------------------------------------------
#  Вытащить друга из полыньи рукой: подойди к краю, друг на поверхности рядом — E.
#  Спасатель встаёт на колено и тянет за руку, друг выползает на лёд рядом с ним.
# ---------------------------------------------------------------------------
const RESCUE_TIME := 1.8

func _find_rescue_target() -> Node3D:
	if not is_on_floor() or held_parcel != null or held_friend != null or _lake == null:
		return null
	for d in get_tree().get_nodes_in_group("player"):
		if d == self or not d.is_swimming or d.rescue_role != 0 or d.carried_by != null:
			continue
		var to: Vector3 = (d as Node3D).global_position - global_position
		if Vector2(to.x, to.z).length() < 5.0:
			return d
	return null


func _try_hand_rescue() -> bool:
	if arms_count() == 0 or held_limb != null:
		return false
	var s := _find_rescue_target()
	if s == null:
		return false
	var to := s.global_position - global_position
	to.y = 0.0
	var dir := to.normalized()
	# встаём на колено у самого края (на льду)
	var kneel := global_position
	for k in 16:
		var next := kneel + dir * 0.15
		if _lake.is_hole(next.x, next.z, 0.35):
			break
		kneel = next
	kneel.y = global_position.y
	var side := Vector3(-dir.z, 0.0, dir.x)
	var land := kneel + side * 1.0
	if _lake.is_hole(land.x, land.z, 0.2):
		land = kneel - side * 1.0
		if _lake.is_hole(land.x, land.z, 0.2):
			land = kneel - dir * 1.1
	land.y = global_position.y + 0.1
	if is_bot or s.is_bot or not (Network.in_game and Network.is_online()):
		_rpc_hand_rescue(int(s.peer_id), kneel, land)
	else:
		_rpc_hand_rescue.rpc(int(s.peer_id), kneel, land)
	return true


@rpc("any_peer", "call_local", "reliable")
func _rpc_hand_rescue(swimmer_id: int, kneel: Vector3, land: Vector3) -> void:
	var s = Network.find_player(swimmer_id)
	if s == null:
		return
	rescue_role = 1
	rescue_t = 0.0
	rescue_partner = s
	_rescue_kneel = kneel
	_rescue_land = land
	s.rescue_role = 2
	s.rescue_t = 0.0
	s.rescue_partner = self
	s._rescue_kneel = kneel
	s._rescue_land = land
	s._rescue_from = s.global_position
	suit.emote(SUIT.Mood.NORMAL, 0.1)


func _rescuer_process(delta: float) -> void:
	rescue_t += delta
	velocity = Vector3.ZERO
	global_position = global_position.lerp(_rescue_kneel, clampf(delta * 8.0, 0.0, 1.0))
	if is_instance_valid(rescue_partner):
		var to := rescue_partner.global_position - global_position
		if Vector2(to.x, to.z).length() > 0.2:
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-to.x, -to.z), clampf(delta * 10.0, 0.0, 1.0))
	if rescue_t >= RESCUE_TIME or not is_instance_valid(rescue_partner):
		rescue_role = 0
		rescue_partner = null
	_update_noise(delta, false)
	_update_visual(delta, Vector3.ZERO, 0.0, false)
	_update_camera(delta)
	_update_hud()
	_prev_velocity = velocity
	_send_state(delta)


## Где сомкнутся руки (над головой спасаемого, к спасателю)
func rescue_clasp() -> Vector3:
	var s: Node3D = self if rescue_role == 2 else rescue_partner
	var r: Node3D = rescue_partner if rescue_role == 2 else self
	if not is_instance_valid(s) or not is_instance_valid(r):
		return global_position + Vector3.UP * 1.5
	var to := r.global_position - s.global_position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.01 else Vector3.FORWARD
	return s.global_position + Vector3.UP * 1.62 + dir * 0.32


func _rescued_process(delta: float) -> void:
	rescue_t += delta
	velocity = Vector3.ZERO
	var to_k := _rescue_kneel - _rescue_from
	to_k.y = 0.0
	var dir := to_k.normalized() if to_k.length() > 0.01 else Vector3.FORWARD
	# сначала подплываю к краю, к руке спасателя
	var near := _rescue_kneel - dir * 1.05
	near.y = _rescue_from.y
	if rescue_t < 0.5:
		global_position = global_position.lerp(near, clampf(delta * 7.0, 0.0, 1.0))
	elif rescue_t < 1.3:
		var u := (rescue_t - 0.5) / 0.8
		var e := u * u * (3.0 - 2.0 * u)
		global_position = near.lerp(_rescue_land, e) + Vector3.UP * sin(u * PI) * 0.75
		if u > 0.1 and (is_swimming or is_diving):
			_splash_fx.global_position = global_position + Vector3.UP * 0.6
			_splash_fx.restart()
			_leave_water_state()
	else:
		if is_swimming or is_diving:
			_leave_water_state()
		global_position = global_position.lerp(_rescue_land, clampf(delta * 12.0, 0.0, 1.0))
	if is_instance_valid(rescue_partner):
		var to := rescue_partner.global_position - global_position
		if Vector2(to.x, to.z).length() > 0.2:
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-to.x, -to.z), clampf(delta * 10.0, 0.0, 1.0))
	if rescue_t >= RESCUE_TIME:
		rescue_role = 0
		rescue_partner = null
		_was_on_floor = false
		suit.emote(SUIT.Mood.HAPPY, 2.0)
	_update_noise(delta, false)
	_update_visual(delta, Vector3.ZERO, 0.0, false)
	_update_camera(delta)
	_update_hud()
	_prev_velocity = velocity
	_send_state(delta)


## Центр ближайшей полыньи (для спасения подо льдом)
func _nearest_hole() -> Vector3:
	if _lake == null:
		return Vector3.INF
	var best := Vector3.INF
	var bd := 60.0
	for c in _lake.get("circles"):
		var cv: Vector3 = c
		var d := Vector2(cv.x - global_position.x, cv.y - global_position.z).length()
		if d < bd:
			bd = d
			best = Vector3(cv.x, global_position.y, cv.y)
	# широкие разводья-прямоугольники: ближайшая точка внутри (с отступом от края)
	for r in _lake.get("rects"):
		var rv: Vector4 = r
		var qx := clampf(global_position.x, rv.x + 1.5, rv.y - 1.5)
		var qz := clampf(global_position.z, rv.z + 1.5, rv.w - 1.5)
		var d2 := Vector2(qx - global_position.x, qz - global_position.z).length()
		if d2 < bd:
			bd = d2
			best = Vector3(qx, global_position.y, qz)
	return best


## Перенести (инструменты проверки): выйти из воды, отпустить всё
func teleport_to(pos: Vector3) -> void:
	if is_swimming or is_diving:
		_leave_water_state()
	if is_frozen:
		is_frozen = false
		_ice_block.visible = false
		_set_block_shape(false)
	doomed = false
	_end_rolls()
	if held_friend:
		_lift_call(held_friend, false, Vector3.ZERO)
	if held_parcel:
		_release_held(held_parcel.global_transform, Vector3.ZERO)
	rescue_role = 0
	frost = 0.0
	_wet_timer = 0.0
	velocity = Vector3.ZERO
	global_position = pos
	_was_on_floor = false


# ---------------------------------------------------------------------------
#  Руки и ноги: отлетают от сильных ударов, друг может оторвать (держать F)
#  и прикрутить обратно (поднять деталь E, подойти, держать E). Детали после
#  поломки корпуса не возвращаются — нужен друг или бот.
# ---------------------------------------------------------------------------
static func _limb_bit(kind: String) -> int:
	return 1 << SUIT.LIMBS.find(kind)


func has_limb(kind: String) -> bool:
	return (limb_mask & _limb_bit(kind)) != 0


## Сколько рук/ног работает (на месте и не вмёрзли)
func arms_count() -> int:
	var w := limb_mask & ~ice_mask
	return int((w & 1) != 0) + int((w & 2) != 0)


func legs_count() -> int:
	var w := limb_mask & ~ice_mask
	return int((w & 4) != 0) + int((w & 8) != 0)


## Одна нога вмёрзла, вторая живая — волоку ледяную
func dragging_leg() -> bool:
	return legs_count() == 1 and (limb_mask & 12) == 12


static func limb_name(kind: String, acc := false) -> String:
	match kind:
		"arm_l":
			return "левую руку" if acc else "левая рука"
		"arm_r":
			return "правую руку" if acc else "правая рука"
		"leg_l":
			return "левую ногу" if acc else "левая нога"
	return "правую ногу" if acc else "правая нога"


## Насколько быстро могу двигаться без рук/ног
func _limb_speed_mult() -> float:
	match legs_count():
		2:
			return 1.0
		1:
			return 0.5 if dragging_leg() else 0.55   # волоку ледяную ногу / прыгаю на одной
	return 0.3 if arms_count() > 0 else 0.08    # ползу на руках / извиваюсь


## Сильный удар может оторвать руку или ногу
func _maybe_lose_limb(amount: float, kind: String, point: Vector3) -> void:
	if kind in ["burn", "scald", "pressure", "thrown"] or limb_mask == 0 or is_frozen:
		return
	# сильный удар — почти всегда что-то отлетает; корпус еле живой — хватает и среднего
	var chance := 0.0
	if amount >= 10.0:
		chance = 0.55
	if amount >= 15.0:
		chance = 0.75
	if amount >= 25.0:
		chance = 0.9
	if health < max_health * 0.35 and amount >= 6.0:
		chance = maxf(chance, 0.55)
	if randf() >= chance:
		return
	var have: Array[String] = []
	for k in SUIT.LIMBS:
		if has_limb(k):
			have.append(k)
	if have.is_empty():
		return
	# очень сильный удар — сразу две детали (обе ноги, рука и нога или обе руки)
	var n := 1
	if amount >= 22.0 and have.size() >= 2 and randf() < 0.5:
		n = 2
	var picks: Array[String] = []
	for j in n:
		var pick := ""
		if kind == "fall" and j == 0:
			for k in ["leg_l", "leg_r"]:
				if have.has(k) and (pick == "" or randf() < 0.5):
					pick = k
		if pick == "":
			# куда пришёлся удар — та сторона чаще; руки и ноги — поровну
			var w := []
			var total := 0.0
			var lp := Vector3.ZERO
			if point != Vector3.INF:
				lp = visual.global_basis.inverse() * (point - global_position)
			for k in have:
				var wk := 1.0
				if point != Vector3.INF:
					var on_side: bool = (lp.x < 0.0) == String(k).ends_with("_l")
					wk *= 1.6 if on_side else 0.8
				w.append(wk)
				total += wk
			var r := randf() * total
			for idx in have.size():
				r -= float(w[idx])
				if r <= 0.0:
					pick = have[idx]
					break
			if pick == "":
				pick = have[have.size() - 1]
		picks.append(pick)
		have.erase(pick)
		if have.is_empty():
			break
	for pick in picks:
		var out: Vector3 = suit.socket_point(pick) - (global_position + Vector3.UP * BODY_HEIGHT)
		out.y = 0.0
		out = out.normalized() if out.length() > 0.01 else -visual.global_basis.z
		lose_limb(pick, out * 3.0 + Vector3.UP * randf_range(3.0, 4.5) + Vector3(velocity.x, 0, velocity.z) * 0.5)


## Потерять руку/ногу (только у хозяина). holder_id — деталь сразу в руке у того, кто оторвал.
func lose_limb(kind: String, vel := Vector3.ZERO, holder_id := 0) -> void:
	if not is_local or not has_limb(kind):
		return
	if vel == Vector3.ZERO and holder_id == 0:
		vel = Vector3.UP * 3.0
	LIMB_PARTS.get_manager(get_tree()).spawn(peer_id, kind, vel, holder_id)
	_set_limbs_net(limb_mask & ~_limb_bit(kind))
	if holder_id != 0:
		# оторвали рывком — меня отбрасывает от того, кто тянул
		var r = Network.find_player(holder_id)
		if r != null:
			var away: Vector3 = global_position - (r as Node3D).global_position
			away.y = 0.0
			away = away.normalized() if away.length() > 0.01 else visual.global_basis.z
			velocity += away * 3.5 + Vector3.UP * 2.5
			_shake = maxf(_shake, 0.45)


## Друг прикрутил деталь (зовёт тот, кто крутил)
func restore_limb(kind: String) -> void:
	if is_local:
		_set_limbs_net(limb_mask | _limb_bit(kind))
	elif _online():
		_rpc_restore.rpc_id(get_multiplayer_authority(), kind)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_restore(kind: String) -> void:
	if is_local:
		_set_limbs_net(limb_mask | _limb_bit(kind))


## Оторвать у меня деталь (зовёт тот, кто тянул) — она окажется у него в руке
func request_rip(kind: String, ripper_id: int) -> void:
	if is_local:
		lose_limb(kind, Vector3.ZERO, ripper_id)
	elif _online():
		_rpc_rip.rpc_id(get_multiplayer_authority(), kind, ripper_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_rip(kind: String, ripper_id: int) -> void:
	if is_local:
		lose_limb(kind, Vector3.ZERO, ripper_id)


func _set_limbs_net(mask: int) -> void:
	if _online():
		_rpc_limbs.rpc(mask)
	else:
		_rpc_limbs(mask)


@rpc("any_peer", "call_local", "reliable")
func _rpc_limbs(mask: int) -> void:
	var old := limb_mask
	limb_mask = mask
	suit.set_limbs(mask)
	for i in 4:
		var b := 1 << i
		if (old & b) != 0 and (mask & b) == 0:
			suit.limb_burst(SUIT.LIMBS[i])
			if is_local:
				_shake = maxf(_shake, 0.4)
				_stagger_total = 0.6
				_stagger_timer = 0.6
				_stagger_strength = 0.8
				body.scale = Vector3(1.15, 0.85, 1.15)
		elif (old & b) == 0 and (mask & b) != 0:
			suit.limb_clunk(SUIT.LIMBS[i])
	if is_local:
		_after_limb_change()


## Без рук многое нельзя: роняю то, что держал
func _after_limb_change() -> void:
	if arms_count() < 2:
		if held_parcel != null:
			_release_held(held_parcel.global_transform, Vector3(velocity.x, 1.0, velocity.z))
		if held_friend != null:
			_lift_call(held_friend, false, Vector3.ZERO)
		if rope and rope.state != ROPE.S.NONE:
			rope._set_state(ROPE.S.NONE)
	if arms_count() == 0:
		if held_limb != null:
			_drop_limb(Vector3(velocity.x, 1.0, velocity.z))
		if rolling_block != null:
			_roll_call(rolling_block, false, Vector3.ZERO)
	_repair_target = null
	_rip_target = null


func _limb_manager() -> Node:
	return LIMB_PARTS.get_manager(get_tree())


## Лежащая рядом деталь, которую можно поднять
func _limb_near(max_d: float) -> Node3D:
	var best: Node3D = null
	var bd := max_d
	for p in get_tree().get_nodes_in_group("limb_part"):
		if p.holder != null and is_instance_valid(p.holder):
			continue
		var d := (p as Node3D).global_position.distance_to(global_position + Vector3.UP * 0.5)
		if d < bd:
			bd = d
			best = p
	return best


func _try_pick_limb() -> bool:
	if arms_count() == 0 or held_limb != null or held_parcel != null or held_friend != null:
		return false
	var p := _limb_near(1.7)
	if p == null:
		return false
	suit.reach()
	_limb_manager().pick(p, peer_id)
	return true


func _drop_limb(vel: Vector3) -> void:
	if held_limb == null:
		return
	_limb_manager().release(held_limb, vel)
	held_limb = null


## Кому можно прикрутить деталь, что у меня в руке
func _repair_candidate() -> Node3D:
	if held_limb == null:
		return null
	var o = Network.find_player(int(held_limb.owner_id))
	if o == null or o == self or o.is_dead or o.has_limb(held_limb.kind):
		return null
	var d := (o as Node3D).global_position.distance_to(global_position)
	return o if d < 2.4 else null


## У кого можно оторвать руку/ногу
func _rip_candidate() -> Node3D:
	var best: Node3D = null
	var bd := 1.9
	for d in get_tree().get_nodes_in_group("player"):
		if d == self or d.is_dead or d.is_frozen or d.limb_mask == 0 or d.carried_by != null:
			continue
		var dist := (d as Node3D).global_position.distance_to(global_position)
		if dist < bd:
			bd = dist
			best = d
	return best


## Какую деталь у него хватаю: ближайшую к моим рукам (руки — охотнее)
func _rip_pick_kind(v: Node3D) -> String:
	var grip := global_position + Vector3.UP * 1.0 - visual.global_basis.z * 0.5
	var best := ""
	var bd := INF
	for k in SUIT.LIMBS:
		if not v.has_limb(k):
			continue
		var d: float = (v.suit.socket_point(k) as Vector3).distance_to(grip) + (0.0 if String(k).begins_with("arm") else 0.25)
		if d < bd:
			bd = d
			best = k
	return best


func _rip_dir() -> Vector3:
	var to := Vector3.ZERO
	if act_target != null and is_instance_valid(act_target):
		to = act_target.global_position - global_position
		to.y = 0.0
	return to.normalized() if to.length() > 0.01 else -visual.global_basis.z


## Куда тяну руку/ногу друга (там мои руки)
func _rip_grip_point() -> Vector3:
	var h := 0.95 if act_kind.begins_with("arm") else 0.6
	return global_position + Vector3.UP * h + _rip_dir() * 0.5


## Куда упираюсь ногой: другу в живот
func _rip_brace_point() -> Vector3:
	if act_target == null or not is_instance_valid(act_target):
		return global_position
	return act_target.global_position + Vector3.UP * 0.78 - _rip_dir() * 0.27


## Рывки: чем ближе к концу — тем чаще и сильнее (одинаково у всех по прогрессу)
func _rip_pulse() -> float:
	var k := act_k
	return pow(maxf(sin(k * k * 30.0 + k * 12.0), 0.0), 2.0) * (0.4 + 0.6 * k)


func _rip_pose() -> Dictionary:
	if act_mode != 2 or act_target == null or not is_instance_valid(act_target):
		return {}
	return {"grip": _rip_grip_point(), "brace": _rip_brace_point(), "k": act_k, "pulse": _rip_pulse()}


func _repair_pose() -> Dictionary:
	if act_mode != 1 or act_target == null or not is_instance_valid(act_target) \
			or held_limb == null or not is_instance_valid(held_limb):
		return {}
	return {"k": act_k, "part": held_limb, "target": act_target, "kind": act_kind,
		"socket": act_target.suit.socket_point(act_kind)}


func _repair_stage_text() -> String:
	var k := clampf(_repair_t / REPAIR_TIME, 0.0, 1.0)
	var nm := limb_name(held_limb.kind, true) if held_limb != null else ""
	if k < 0.24:
		return "Вставляю %s в гнездо…" % nm
	if k < 0.74:
		return "Закручиваю болт %d из 4…" % (clampi(int((k - SUIT.BOLT_K0) / SUIT.BOLT_DK), 0, 3) + 1)
	if k < 0.86:
		return "Соединяю провода…"
	return "Проверяю крепление…"


## Ремонт и «оторвать» — каждый кадр (свой дрон)
func _limb_actions(delta: float) -> void:
	# прикручиваю
	if _repair_target != null:
		var ok: bool = is_instance_valid(_repair_target) and held_limb != null and _held("interact") \
			and _repair_target.global_position.distance_to(global_position) < 2.6 and not _repair_target.has_limb(held_limb.kind)
		if not ok:
			if held_limb != null:
				held_limb.repair_target = null
			_repair_target = null
			_repair_t = 0.0
		else:
			_repair_t += delta
			held_limb.repair_target = _repair_target
			held_limb.repair_k = clampf(_repair_t / REPAIR_TIME, 0.0, 1.0)
			var to := _repair_target.global_position - global_position
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-to.x, -to.z), clampf(delta * 8.0, 0.0, 1.0))
			if _repair_t >= REPAIR_TIME:
				var part := held_limb
				var who := _repair_target
				_repair_target = null
				_repair_t = 0.0
				who.restore_limb(part.kind)
				_limb_manager().consume(part)
				held_limb = null
				suit.emote(SUIT.Mood.HAPPY, 1.8)
	# отрываю
	if _rip_target != null:
		var ok2: bool = is_instance_valid(_rip_target) and _held("rip") and arms_count() > 0 \
			and _rip_target.global_position.distance_to(global_position) < 2.4 and _rip_target.has_limb(_rip_kind) \
			and not _rip_target.is_frozen and not _rip_target.is_dead
		if not ok2:
			_rip_target = null
			_rip_t = 0.0
		else:
			_rip_t += delta
			var to2 := _rip_target.global_position - global_position
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-to2.x, -to2.z), clampf(delta * 8.0, 0.0, 1.0))
			if _rip_target.is_bot and not _rip_target.controlled and randf() < delta * 1.2:
				_rip_t = maxf(_rip_t - 0.08, 0.0)        # бот брыкается
			if _rip_t >= RIP_TIME:
				var v := _rip_target
				var kind := _rip_kind
				_rip_target = null
				_rip_t = 0.0
				v.request_rip(kind, peer_id)
				# последний рывок: оторвал — и отлетаю назад
				var back := global_position - v.global_position
				back.y = 0.0
				back = back.normalized() if back.length() > 0.01 else visual.global_basis.z
				velocity = back * 4.5 + Vector3.UP * 2.6
				_lock_t = 0.55
				_was_on_floor = false
				body.scale = Vector3(0.88, 1.12, 0.88)
				_shake = maxf(_shake, 0.35)
	# что делаю — для поз и эффектов (и по сети)
	if _repair_target != null and is_instance_valid(_repair_target) and held_limb != null:
		act_mode = 1
		act_target = _repair_target
		act_kind = String(held_limb.kind)
		act_k = clampf(_repair_t / REPAIR_TIME, 0.0, 1.0)
	elif _rip_target != null and is_instance_valid(_rip_target):
		act_mode = 2
		act_target = _rip_target
		act_kind = _rip_kind
		act_k = clampf(_rip_t / RIP_TIME, 0.0, 1.0)
	else:
		act_mode = 0
		act_target = null
		act_k = 0.0


## Тянет ли кто-то мою руку/ногу прямо сейчас (у всех копий одинаково — по act_* тянущего)
func _update_ripped() -> void:
	ripped_info = {}
	for d in get_tree().get_nodes_in_group("player"):
		if d != self and is_instance_valid(d) and int(d.act_mode) == 2 and d.act_target == self:
			ripped_info = {"kind": String(d.act_kind), "to": d._rip_grip_point(), "by": int(d.peer_id), "k": float(d.act_k)}
			return


## Вырываюсь: жму кнопки — тянущему труднее
func _ripped_process(_delta: float) -> void:
	if ripped_info.is_empty() or not is_local or _ai_driven():
		return
	for a in BREAK_KEYS:
		if _just(a):
			var r = Network.find_player(int(ripped_info.get("by", 0)))
			if r != null:
				r.rip_resist()


## Эффекты моего действия у всех: болты вылетают, рука отходит от гнезда, отдача после рывка
func _act_visuals(delta: float) -> void:
	if not is_local:
		act_k = move_toward(act_k, _net_act_k, delta * 2.5) if act_mode != 0 else 0.0
	var tgt: Node3D = act_target if act_target != null and is_instance_valid(act_target) else null
	if act_mode == 2 and tgt != null:
		var n := _rip_dir()
		var gk := smoothstep(0.25, 1.0, act_k)
		tgt.suit.set_strain(act_kind, -n * (gk * 0.11 + _rip_pulse() * 0.03 * gk), act_k)
		var want := 0
		for th in RIP_BOLTS:
			if act_k >= float(th):
				want += 1
		while _act_bolts < want:
			_act_bolts += 1
			tgt.suit.pop_bolt(act_kind, -n)
			suit.jolt(0.4)
			if tgt.is_local:
				tgt._shake = maxf(tgt._shake, 0.25)
	else:
		_act_bolts = 0
	if _act_prev_mode == 2 and act_mode == 0 and _act_prev_k > 0.85:
		suit.recoil()
	_act_prev_mode = act_mode
	_act_prev_k = act_k


func rip_resist() -> void:
	if is_local:
		_rip_t = maxf(_rip_t - 0.14, 0.0)
	elif _online():
		_rpc_resist.rpc_id(get_multiplayer_authority())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_resist() -> void:
	rip_resist()
