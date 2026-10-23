extends RefCounted
## 1.2.9 Protect the fleet sounds: original PCM made in code (deterministic, royalty-safe).
## The round also reuses main-game booms from BattleAudio.gd.
const BA := preload("res://scripts/BattleAudio.gd")

## Interceptor hit on a Attack Drone: a 45 ms dry tick (filtered click and a soft 2.2 kHz ping).
static func make_interceptor_hit_tick() -> AudioStreamWAV:
	var rate := 48000
	var frames := int(0.045 * rate)
	var out := PackedFloat32Array(); out.resize(frames)
	var rng := RandomNumberGenerator.new(); rng.seed = 51207
	var f := 0.0
	for i in range(frames):
		var t := float(i) / rate
		f = lerpf(f, rng.randf_range(-1.0, 1.0), 0.45)
		var env := minf(1.0, t / 0.001) * exp(-t * 95.0)
		out[i] = env * (0.35 * f + 0.30 * sin(TAU * 2200.0 * t) + 0.12 * sin(TAU * 3300.0 * t))
	return BA._pcm16(out, rate)

## Civilian ship under attack (first attack): two short falling tones, E5 then B4, about 0.32 s.
static func make_ship_attacked() -> AudioStreamWAV:
	return BA._pcm16(_beeps([[0.0, 659.3], [0.16, 493.9]], 0.12, 0.34), 48000)

## Civilian ship critical (25% hull or less): three fast B5 pips, about 0.42 s.
static func make_ship_critical() -> AudioStreamWAV:
	return BA._pcm16(_beeps([[0.0, 987.8], [0.13, 987.8], [0.26, 987.8]], 0.08, 0.42), 48000)

static func _beeps(notes: Array, each: float, length: float) -> PackedFloat32Array:
	var rate := 48000
	var frames := int(length * rate)
	var out := PackedFloat32Array(); out.resize(frames)
	for i in range(frames):
		var t := float(i) / rate
		var s := 0.0
		for n in notes:
			var u: float = t - float(n[0])
			if u < 0.0 or u > each:
				continue
			var env := clampf(minf(u / 0.006, (each - u) / 0.02), 0.0, 1.0)
			s += env * (0.30 * sin(TAU * float(n[1]) * u) + 0.07 * sin(TAU * float(n[1]) * 2.0 * u))
		out[i] = s
	return out

## Medium civilian ship lost: between the Breacher boom and the capital boom, about 1.0 s.
static func make_medium_ship_boom() -> AudioStreamWAV:
	var rate := 48000
	var length := 1.0
	var frames := int(length * rate)
	var out := PackedFloat32Array(); out.resize(frames)
	var rng := RandomNumberGenerator.new(); rng.seed = 88123
	var phase := 0.0
	var f := 0.0
	var rumble := 0.0
	for i in range(frames):
		var t := float(i) / rate
		phase += TAU * lerpf(96.0, 34.0, minf(1.0, t / 0.5)) / rate
		f = lerpf(f, rng.randf_range(-1.0, 1.0), 0.26)
		rumble = lerpf(rumble, f, 0.04)
		var attack := minf(1.0, t / 0.004)
		var body := attack * exp(-t * 4.2) * 0.55 * sin(phase)
		var roll := attack * exp(-t * 3.0) * rumble * 2.2
		var crack := exp(-t * 60.0) * f * 0.35
		out[i] = 0.8 * tanh(1.3 * (body + roll + crack)) * clampf((length - t) / 0.2, 0.0, 1.0)
	return BA._pcm16(out, rate)

## 1.0.7 Protect the convoy: rapid-fire burst, five dry cannon cracks 55 ms apart, about 0.34 s.
static func make_rapid_fire() -> AudioStreamWAV:
	var rate := 48000
	var length := 0.34
	var frames := int(length * rate)
	var out := PackedFloat32Array(); out.resize(frames)
	var rng := RandomNumberGenerator.new(); rng.seed = 70107
	var f := 0.0
	var low := 0.0
	for i in range(frames):
		var t := float(i) / rate
		f = lerpf(f, rng.randf_range(-1.0, 1.0), 0.55)
		low = lerpf(low, f, 0.12)
		var s := 0.0
		for shot in range(5):
			var u := t - shot * 0.055
			if u < 0.0 or u > 0.07:
				continue
			var env := minf(1.0, u / 0.0008) * exp(-u * 70.0)
			var pitch := 1.0 - 0.04 * shot
			s += env * (0.42 * f + 0.30 * low + 0.22 * sin(TAU * 180.0 * pitch * u) * exp(-u * 40.0))
		out[i] = s * 0.9
	return BA._pcm16(out, rate)

## 1.0.7: Breacher latches on a support ship: a metal clamp clank and a falling electric whine, about 0.6 s.
static func make_breacher_latch() -> AudioStreamWAV:
	var rate := 48000
	var length := 0.6
	var frames := int(length * rate)
	var out := PackedFloat32Array(); out.resize(frames)
	var rng := RandomNumberGenerator.new(); rng.seed = 70211
	var f := 0.0
	var phase := 0.0
	for i in range(frames):
		var t := float(i) / rate
		f = lerpf(f, rng.randf_range(-1.0, 1.0), 0.35)
		var clank := minf(1.0, t / 0.001) * exp(-t * 30.0) * (0.35 * f + 0.25 * sin(TAU * 410.0 * t) + 0.18 * sin(TAU * 1130.0 * t))
		var u := t - 0.06
		var whine := 0.0
		if u > 0.0:
			phase += TAU * lerpf(1500.0, 300.0, minf(1.0, u / 0.5)) / rate
			var env := minf(1.0, u / 0.02) * clampf((0.54 - u) / 0.12, 0.0, 1.0)
			whine = env * 0.16 * signf(sin(phase)) * (0.6 + 0.4 * sin(TAU * 34.0 * u))
		out[i] = clank + whine
	return BA._pcm16(out, rate)

## 1.0.7: Breacher draining a ship: a 1.0 s loop of a low pulsing hum with electric crackle.
static func make_breacher_drain() -> AudioStreamWAV:
	var rate := 48000
	var length := 1.0
	var frames := int(length * rate)
	var out := PackedFloat32Array(); out.resize(frames)
	var rng := RandomNumberGenerator.new(); rng.seed = 70313
	var f := 0.0
	for i in range(frames):
		var t := float(i) / rate
		f = lerpf(f, rng.randf_range(-1.0, 1.0), 0.6)
		# Whole cycles in 1.0 s so the loop joins cleanly: 55 Hz, 110 Hz, 4 pulses a second.
		var pulse := 0.55 + 0.45 * sin(TAU * 4.0 * t)
		var hum := 0.30 * sin(TAU * 55.0 * t) + 0.16 * sin(TAU * 110.0 * t) + 0.06 * sin(TAU * 330.0 * t)
		var crackle := 0.0
		if rng.randf() < 0.004:
			crackle = rng.randf_range(-0.5, 0.5)
		out[i] = pulse * hum + 0.10 * f * pulse * pulse + crackle
	var wav := BA._pcm16(out, rate)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames
	return wav
