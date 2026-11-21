extends "res://scenes/world/waste_storm.gd"
## Погода на Пике (снег, порывы, защита, мороз, звук — как в метели пустоши), сила — по высоте:
##  * внизу тихо (лёгкое начало); выше 60 м поднимается ветер, к плато — порывы сносят с полки.
##    Между порывами ветер с полки не сносит — только прижимает к скале; порыв слышно заранее (гул).
##    Защита: держаться за леер / вешку-фонарь, присесть (вбить ледоруб), держать E у крюка, висеть на стене;
##  * мороз — выше 150 м; рядом с другом — вдвое медленнее; в приютах — тепло;
##  * облака — слой на 200–340 м (внутри — туман, выше — ясно, «над облаками»);
##  * на главной вершине — ветер и мороз сильнее к вершине;
##  * ночь и буран на Плече (mountain_night.gd): темно, метёт, мороз жжёт.

const M := preload("res://scenes/world/mountain_layout.gd")
const M_GUST := 12.0
const M_COLD := 0.04
const M_FOG := 0.075
const NIGHT_FOG := 0.11
const BASE := Vector2(-0.6, 0.8)

var u_now := -1.0                  ## где на тропе мой дрон (−1 — не на тропе)
var alt := 0.0
var _fk := 0.0
var _nk := 0.0                     ## ночь (0…1)
var _ak := 0.0                     ## высота (0…1): воздух прозрачнее
var _rk := 0.0                     ## у Пика (0…1)
var _base_bg := 1.0
var _base_amb := 1.0
var _sun_sh_off := false            ## шаг 120: ночью выключил тени солнца — вернуть днём


func _ready() -> void:
	super._ready()
	process_physics_priority = 50
	process_priority = 25
	if _env:
		_base_bg = _env.background_energy_multiplier
		_base_amb = _env.ambient_light_energy


## Сила погоды по месту
func _strength(p: Vector3) -> float:
	var st := 0.0
	if M.on_block(p) and p.y > M.H_SP + 60.0:
		st = 0.55 + 0.35 * smoothstep(M.SH_Y, M.PEAK, p.y)
		if p.y > M.PEAK - 3.0:
			st *= 0.6
	else:
		st = 0.85 * smoothstep(60.0, 330.0, p.y)
		if p.y > M.H_SP - 4.0:
			st = 0.6                    # на плато
	var nt: Node = waste.get("night") if waste else null
	if nt and nt.has_method("storm_k"):
		var sk: float = nt.storm_k()
		if sk > 0.0 and nt._near_shoulder(p):
			st = lerpf(st, maxf(sk, 0.3), clampf(nt.dark_k(), 0.0, 1.0))     # шаг 119: ночью — тихий снежок
	return st


func _physics_process(delta: float) -> void:
	_player = Network.local_player
	if _player == null or not is_instance_valid(_player):
		return
	_local_t += delta
	var t: float = Network.game_time if Network.in_game else _local_t
	var p := _player.global_position
	var on := M.on_mountain(p)
	u_now = M.u_at(p) if on else -1.0
	alt = p.y
	var st := _strength(p) if on else 0.0
	intensity = move_toward(intensity, st, 0.35 * delta)
	var g: Array = gust_at(t, p.z)
	var live := intensity > 0.3 and not calm and on
	gust_phase = int(g[0]) if live else 0
	var gs: float = float(g[1]) if live else 0.0
	var off := (g[2] as Vector2).angle() - W.wind_dir(p.z).angle()
	gust_dir = BASE.normalized().rotated(off)
	gust = move_toward(gust, gs, delta * 3.0)
	var bd := BASE.normalized()
	var wb := Vector3(bd.x, 0, bd.y) * (0.4 + 1.6 * intensity)
	# ровный ветер (между порывами) с полки не сносит — только чуть прижимает к скале
	var wb_push := Vector3.ZERO
	if on and u_now >= 0.0 and u_now < 1.0:
		wb_push = -M.outward(u_now) * 0.3 * intensity
	var wg := Vector3(gust_dir.x, 0, gust_dir.y) * M_GUST * gust * intensity
	var wind := wb.lerp(Vector3.ZERO, gust * 0.5) + wg
	var push := wb_push.lerp(Vector3.ZERO, gust * 0.5) + wg
	var cab = waste.get("cabin") if waste else null
	var indoor: bool = cab != null and cab.in_cabin(p)
	if on and intensity > 0.02 and not _player.is_dead and not _player.snow.busy() and not indoor:
		var prot: Array = shelter_factor(_player, wind)
		protection = prot[0]
		protect_why = prot[1]
		if _player.get("sitting"):
			protection *= 0.1                # присел и вбил ледоруб в наст — в порыв сносит на 1–2 м, не больше
			_player.set("_wind_hold", (_player.get("_wind_hold") as Vector3) * 0.85)
		if waste and waste.has_method("gripping") and waste.gripping(_player):
			protection = 0.0
			_player.set("_wind_hold", Vector3.ZERO)
		wind_now = push * protection
		if wind_now.length() > 0.02:
			_player.apply_wind(wind_now)
		if gust_phase == 2 and int(g[3]) != _last_cycle:
			_last_cycle = int(g[3])
			if protection > 0.2:
				_player.wind_shove(Vector3(gust_dir.x, 0, gust_dir.y), 3.0 * protection * intensity)
		if gust_phase == 2:
			_player.add_shake(0.05 * protection + 0.02)
	else:
		wind_now = Vector3.ZERO
		protection = 1.0
		protect_why = ""
		sheltered = false
	_cold_and_hail(delta)
	if on or intensity > 0.01:
		_update_look(delta, p, wind)
	else:
		_streaks.emitting = false
		_hail.emitting = false
		_haze.visible = false
		for e in _fx:
			(e[0] as GPUParticles3D).emitting = false
		_vol = move_toward(_vol, 0.0, delta)


## Сильный порыв прямо сейчас (для тех, кто лезет по стене)
func gust_hard() -> bool:
	return gust_phase == 2 and gust > 0.45 and intensity > 0.3


## Гул — порыв вот-вот
func gust_warn() -> bool:
	return gust_phase == 1 and intensity > 0.3


func _cold_and_hail(_delta: float) -> void:
	if not M.on_mountain(_player.global_position):
		return                       # не на горе — мороз ставит метель пустоши
	if _player.is_dead or no_cold:
		_player.air_cold = 0.0
		return
	var p := _player.global_position
	var c := 0.0
	if M.on_block(p) and p.y > M.H_SP + 60.0:
		c = M_COLD * (0.8 + 0.5 * smoothstep(M.SH_Y, M.PEAK, p.y))
	else:
		c = M_COLD * smoothstep(150.0, 360.0, p.y)
	for o in get_tree().get_nodes_in_group("player"):
		if o != _player and not o.get("is_dead") and (o as Node3D).global_position.distance_to(p) < 3.0:
			c *= 0.5                 # греемся друг о друга
			break
	if gust_phase == 2:
		c *= 1.4
	if waste and waste.has_method("warm_at") and waste.warm_at(p):
		c = 0.0
	var nt: Node = waste.get("night") if waste else null
	if nt and nt.has_method("cold_at"):
		var nc: float = nt.cold_at(p)
		if nc >= 0.0:
			c = nc
	_player.air_cold = c


func _apply_air() -> void:
	var p := _player.global_position if _player and is_instance_valid(_player) else Vector3.ZERO
	var want := 0.0
	var on := M.on_mountain(p)
	if on and not M.on_block(p):
		# шаг 147–148: туман — внутри облачного слоя (peak_clouds: 228–290 м)
		want = smoothstep(208.0, 228.0, p.y) * (1.0 - smoothstep(300.0, 325.0, p.y))
	var nt: Node = waste.get("night") if waste else null
	var nk := 0.0
	var sk := 0.0
	if nt and nt.has_method("dark_k") and on:
		nk = nt.dark_k()
		if nt._near_shoulder(p):
			sk = nt.storm_k()
	var cab = waste.get("cabin") if waste else null
	var inside: bool = cab != null and cab.in_cabin(p)
	if inside:
		want *= 0.1
		sk *= 0.1
	var dt := get_process_delta_time()
	_fk = move_toward(_fk, maxf(want, sk), dt * 0.4)
	_nk = move_toward(_nk, nk, dt * 0.25)
	# чем выше — тем прозрачнее воздух: с вершины видно далеко
	var cam := get_viewport().get_camera_3d()
	var cy := cam.global_position.y if cam else p.y
	_ak = move_toward(_ak, smoothstep(80.0, 520.0, cy) if on else 0.0, dt * 0.5)
	# у Пика воздух чище, чем в долине: гору видно издалека
	_rk = move_toward(_rk, smoothstep(-2600.0, -2700.0, p.z), dt * 0.3)
	if _env and (_fk > 0.001 or _nk > 0.001 or _ak > 0.001 or _rk > 0.001 or _fog_active):
		var base := _base_fog * lerpf(1.0, 0.42, _rk) * lerpf(1.0, 0.3, _ak)
		var dens := lerpf(base, M_FOG if sk <= 0.0 else NIGHT_FOG, _fk) + GUST_FOG * gust * _fk
		_env.fog_density = dens
		var fc := _base_fog_color.lerp(Color(0.66, 0.71, 0.78), clampf(_fk * 1.3, 0.0, 1.0))
		_env.fog_light_color = fc.lerp(Color(0.1, 0.13, 0.2), _nk)
		_env.fog_sky_affect = lerpf(_base_sky_affect, 1.0, clampf(maxf(_fk * 1.5, _nk), 0.0, 1.0))
		_env.background_energy_multiplier = _base_bg * lerpf(1.0, 0.018, _nk)
		_env.ambient_light_energy = _base_amb * lerpf(1.0, 0.022, _nk)
		if _sun:
			_sun.light_energy = _base_sun * lerpf(1.0, 0.5, _fk) * lerpf(1.0, 0.03, _nk)
			# шаг 120: ночью солнца нет — и тени от него не считаем (самое дорогое в кадре)
			if _nk > 0.7 and _sun.shadow_enabled:
				_sun.shadow_enabled = false
				_sun_sh_off = true
			elif _nk < 0.6 and _sun_sh_off:
				_sun.shadow_enabled = true
				_sun_sh_off = false
	_fog_active = _fk > 0.001 or _nk > 0.001 or _ak > 0.001 or _rk > 0.001
