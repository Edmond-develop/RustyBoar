extends RefCounted
## Шаг 74: звуки механизмов без файлов — каждый собирается из синусов и шума при первом запуске
## (щелчок, лязг металла, трещотка ключа, глухой стук камня, шипение пара, гул шестерён, скрип, цепь, колокольчик…).
## SFX.play(узел, точка, "clank") — звук в мире (3D), гаснет сам. SFX.loop(узел, "hiss") — зацикленный (пар, гул).

const RATE := 22050
static var _cache := {}


static func prewarm() -> void:
	for n in ["click", "clank", "ratchet", "thunk", "hiss", "puff", "grind", "whirr", "creak", "chain", "ding", "spark", "whistle", "pump", "slide", "latch", "fail", "swish", "crunch", "snowslide", "rope", "gust", "creak"]:
		stream(n)


static func stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var s := _make(name)
	_cache[name] = s
	return s


## Разовый звук в точке мира
static func play(where: Node, pos: Vector3, name: String, vol_db := 0.0, pitch := 1.0, range_m := 40.0) -> void:
	if where == null or not where.is_inside_tree():
		return
	var pl := AudioStreamPlayer3D.new()
	pl.stream = stream(name)
	pl.volume_db = vol_db
	pl.pitch_scale = pitch * randf_range(0.96, 1.04)
	pl.unit_size = 5.0
	pl.max_distance = range_m
	pl.attenuation_filter_cutoff_hz = 9000.0
	where.get_tree().current_scene.add_child(pl)
	pl.global_position = pos
	pl.finished.connect(pl.queue_free)
	pl.play()
	# шаг 96: зацикленный звук разово — не даю ему гудеть вечно
	if (pl.stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED:
		var tw := pl.create_tween()
		tw.tween_interval(0.6)
		tw.tween_callback(pl.queue_free)


## Зацикленный звук (сам решай, когда play/stop и какая громкость)
static func loop(parent: Node3D, name: String, vol_db := 0.0, range_m := 35.0) -> AudioStreamPlayer3D:
	var pl := AudioStreamPlayer3D.new()
	pl.stream = stream(name)
	pl.volume_db = vol_db
	pl.unit_size = 5.0
	pl.max_distance = range_m
	parent.add_child(pl)
	return pl


# ---------------------------------------------------------------------------

static func _make(name: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var dur := 0.5
	var looped := false
	match name:
		"click": dur = 0.07
		"clank": dur = 0.75
		"ratchet": dur = 0.42
		"thunk": dur = 0.4
		"hiss": dur = 1.0; looped = true
		"puff": dur = 0.6
		"grind": dur = 0.8
		"whirr": dur = 1.0; looped = true
		"creak": dur = 0.9
		"chain": dur = 0.7
		"ding": dur = 1.4
		"spark": dur = 0.35
		"whistle": dur = 1.1
		"pump": dur = 0.45
		"slide": dur = 0.35
		"latch": dur = 0.18
		"fail": dur = 0.6
		"swish": dur = 0.3
		"crunch": dur = 0.5
		"snowslide": dur = 0.9
		"rope": dur = 0.45
		"gust": dur = 3.2
		"creak": dur = 0.7
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0          # фильтры шума
	var lp2 := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var nz := rng.randf_range(-1.0, 1.0)
		var v := 0.0
		match name:
			"click":
				v = nz * exp(-t * 160.0) * 0.8 + sin(TAU * 3100.0 * t) * exp(-t * 90.0) * 0.5
			"latch":
				v = nz * exp(-t * 120.0) * 0.6 + sin(TAU * 1900.0 * t) * exp(-t * 60.0) * 0.5
				var t2 := t - 0.07
				if t2 > 0.0:
					v += (rng.randf_range(-1.0, 1.0) * exp(-t2 * 140.0) * 0.7 + sin(TAU * 2600.0 * t2) * exp(-t2 * 70.0) * 0.6)
			"clank":
				# металл: негармонические обертоны с разным затуханием + удар
				var f0 := 410.0
				v = sin(TAU * f0 * t) * exp(-t * 7.0) * 0.45 + sin(TAU * f0 * 2.76 * t) * exp(-t * 11.0) * 0.3 \
					+ sin(TAU * f0 * 5.4 * t) * exp(-t * 18.0) * 0.2 + sin(TAU * f0 * 8.93 * t) * exp(-t * 30.0) * 0.12
				v += nz * exp(-t * 90.0) * 0.6
			"ratchet":
				# трещотка ключа: 8 щелчков
				var k := fmod(t, 0.05)
				v = rng.randf_range(-1.0, 1.0) * exp(-k * 260.0) * 0.7 + sin(TAU * 2400.0 * k) * exp(-k * 140.0) * 0.4
			"thunk":
				lp = lerpf(lp, nz, 0.08)
				v = sin(TAU * (95.0 - t * 60.0) * t) * exp(-t * 11.0) * 0.8 + lp * exp(-t * 25.0) * 2.2
			"hiss":
				lp = lerpf(lp, nz, 0.5)
				v = (nz - lp) * 0.55
				var fade := minf(minf(t, dur - t) / 0.05, 1.0)
				v *= lerpf(0.7, 1.0, fade)
			"puff":
				lp = lerpf(lp, nz, 0.45)
				v = (nz - lp) * 0.6 * sin(PI * clampf(t / dur, 0.0, 1.0)) * exp(-t * 2.0)
			"grind":
				lp = lerpf(lp, nz, 0.3)
				var mod := 0.5 + 0.5 * sin(TAU * 38.0 * t)
				v = lp * 1.6 * mod + signf(sin(TAU * 112.0 * t)) * 0.18 * mod
				v *= minf(t / 0.03, 1.0) * minf((dur - t) / 0.15, 1.0)
			"whirr":
				# гул шестерён: пила + стук зубьев (частоты кратны 1 Гц — петля без щелчка)
				ph = fmod(t * 74.0, 1.0)
				v = (ph * 2.0 - 1.0) * 0.22 + sin(TAU * 148.0 * t) * 0.12
				var tk := fmod(t, 1.0 / 24.0)
				v += rng.randf_range(-1.0, 1.0) * exp(-tk * 400.0) * 0.25
			"creak":
				var fr := 160.0 + 40.0 * sin(TAU * 1.3 * t) + 25.0 * sin(TAU * 7.0 * t)
				ph = fmod(ph + fr / RATE, 1.0)
				var grain := 0.5 + 0.5 * sin(TAU * 23.0 * t + sin(TAU * 3.0 * t) * 2.0)
				v = (ph * 2.0 - 1.0) * 0.4 * grain * sin(PI * t / dur)
			"chain":
				var k2 := fmod(t, 0.037 + 0.01 * sin(t * 40.0))
				v = rng.randf_range(-1.0, 1.0) * exp(-k2 * 300.0) * 0.5 + sin(TAU * 3300.0 * k2) * exp(-k2 * 200.0) * 0.3
				v *= minf((dur - t) / 0.2, 1.0)
			"ding":
				v = sin(TAU * 880.0 * t) * exp(-t * 2.5) * 0.4 + sin(TAU * 1760.0 * t) * exp(-t * 4.0) * 0.2 \
					+ sin(TAU * 2640.0 * t) * exp(-t * 6.0) * 0.12 + sin(TAU * 1318.5 * t) * exp(-t * 3.0) * 0.2 * float(t > 0.12)
			"spark":
				var crack := 1.0 if rng.randf() < 0.012 else 0.0
				lp = lerpf(lp, crack * rng.randf_range(-1.0, 1.0), 0.6)
				v = (nz * 0.15 + lp * 3.0) * exp(-t * 6.0)
			"whistle":
				lp = lerpf(lp, nz, 0.4)
				var env := minf(t / 0.08, 1.0) * minf((dur - t) / 0.3, 1.0)
				v = (sin(TAU * 620.0 * t) * 0.3 + sin(TAU * 930.0 * t) * 0.2 + (nz - lp) * 0.25) * env
			"pump":
				lp = lerpf(lp, nz, 0.06)
				lp2 = lerpf(lp2, lp, 0.2)
				v = lp2 * 4.0 * sin(PI * t / dur) + sin(TAU * 70.0 * t) * 0.1 * sin(PI * t / dur)
			"slide":
				lp = lerpf(lp, nz, 0.25)
				v = lp * 1.4 * sin(PI * t / dur) + sin(TAU * (300.0 + 500.0 * t) * t) * 0.06
			"swish":
				# взмах ледорубом: воздух — шум, полоса частот уходит вверх и гаснет
				var cf := lerpf(0.06, 0.45, clampf(t / 0.18, 0.0, 1.0))
				lp = lerpf(lp, nz, cf)
				lp2 = lerpf(lp2, lp, cf)
				v = (lp - lp2) * 3.2 * pow(sin(PI * clampf(t / dur, 0.0, 1.0)), 1.6)
			"crunch":
				# снег ломается: россыпь мелких хрустов + глухой низ
				lp = lerpf(lp, nz, 0.35)
				var gr := 1.0 if rng.randf() < 0.04 * exp(-t * 4.0) + 0.004 else 0.0
				lp2 = lerpf(lp2, gr * rng.randf_range(-1.0, 1.0), 0.5)
				v = lp2 * 2.6 + lp * 0.5 * exp(-t * 6.0) + sin(TAU * 70.0 * t) * exp(-t * 14.0) * 0.35
			"snowslide":
				# тело волочёт по снегу: шорох с неровной силой, без тона
				lp = lerpf(lp, nz, 0.12)
				lp2 = lerpf(lp2, nz, 0.5)
				var am := (0.6 + 0.4 * sin(TAU * 5.0 * t + sin(TAU * 1.7 * t) * 2.0)) * minf(t / 0.06, 1.0) * minf((dur - t) / 0.3, 1.0)
				v = (lp * 1.7 + (lp2 - lp) * 0.35) * am
			"gust":
				# порыв ветра: шум через резонанс, тон гуляет 260…620 Гц, нарастает и спадает
				var env := sin(PI * clampf(t / dur, 0.0, 1.0))
				env = env * env
				var fc := 260.0 + 360.0 * (0.5 + 0.5 * sin(TAU * 0.35 * t + 1.3)) * env
				var w := TAU * fc / RATE
				var q := 0.985
				var y := 2.0 * q * cos(w) * lp - q * q * lp2 + nz * 0.06
				lp2 = lp
				lp = y
				v = clampf(y * 1.6, -1.0, 1.0) * env * 0.8
			"creak":
				# скрип дерева/каната: тон «трётся» рывками 140…220 Гц
				var stick := 0.5 + 0.5 * sin(TAU * 23.0 * t + sin(TAU * 7.0 * t) * 3.0)
				ph = fmod(ph + (140.0 + 80.0 * stick) / RATE, 1.0)
				v = (ph * 2.0 - 1.0) * 0.35 * stick * sin(PI * clampf(t / dur, 0.0, 1.0)) + (nz - lp) * 0.08
				lp = lerpf(lp, nz, 0.2)
			"rope":
				# верёвка натянулась: шуршание оплётки и короткий скрип волокон
				lp = lerpf(lp, nz, 0.3)
				var ck := fmod(t, 0.031)
				v = (nz - lp) * 0.35 * exp(-t * 5.0) + rng.randf_range(-1.0, 1.0) * exp(-ck * 500.0) * 0.25 * exp(-t * 7.0) + lp * 0.6 * exp(-t * 9.0)
			"fail":
				ph = fmod(ph + (180.0 - t * 90.0) / RATE, 1.0)
				v = (1.0 if ph < 0.5 else -1.0) * 0.18 * exp(-t * 3.0) + nz * 0.15 * exp(-t * 12.0)
		buf[i] = clampf(v, -1.0, 1.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(buf[i] * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w
