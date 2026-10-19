extends RefCounted
## Original, code-generated electronic defense sound for the FIREWALL.
## A seamless one-second loop: a fast digital arpeggio over a pulsing low hum.

const RATE := 22050

static func make_firewall_loop() -> AudioStreamWAV:
	var frames := RATE  # exactly one second, so every part below loops cleanly
	var data := PackedByteArray()
	data.resize(frames * 2)
	var notes := [880.0, 1320.0, 1760.0, 1320.0, 990.0, 1480.0, 1980.0, 1480.0]
	var steps := 16  # 16 blips per second
	var step_frames := frames / steps
	for i in range(frames):
		var t := float(i) / RATE
		var step := i / step_frames
		var local := float(i % step_frames) / float(step_frames)
		var freq: float = notes[step % notes.size()]
		# Soft-edged square-ish blip: rises and falls to zero inside each step.
		var envelope := sin(PI * clampf(local / 0.7, 0.0, 1.0)) if local < 0.7 else 0.0
		var phase := fmod(t * freq, 1.0)
		var blip := (1.0 if phase < 0.5 else -1.0) * 0.55 + sin(TAU * freq * t) * 0.45
		# Low electronic hum, 110 Hz, pulsing 8 times per second.
		var hum := sin(TAU * 110.0 * t) * (0.55 + 0.45 * sin(TAU * 8.0 * t))
		var value := blip * envelope * 0.22 + hum * 0.18
		var sample := int(clampf(value, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream
