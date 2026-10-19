extends SceneTree
## Run against both imported source and an exported PCK with the editor binary.
const Contacts = preload("res://scripts/RadarContacts.gd")
const ARRIVAL_HASH := "5c66be7867e7dcfa6a8216e69724c5fe71be4257c6b32123263ce6962a4a0798"
const ORIGINAL_HASH := "74daf4b7f7ba697997bd7a8c4b6277f81a25ed2db4de22818ee24094c0daa4ca"
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var arrival: AudioStreamWAV = Contacts.make_klaxon_sound()
	var nuclear: AudioStreamWAV = Contacts.make_alert_sequence(2)
	var siege: AudioStreamWAV = Contacts.make_alert_sequence(2)
	var original: PackedByteArray = Contacts.exported_alert_pcm("res://assets/audio/radar_alert_loop.wav")
	check(arrival != null and nuclear != null and siege != null, "All three alert paths load")
	check(digest(arrival.data) == ARRIVAL_HASH, "Arrival samples match approved preview 04 exactly")
	check(arrival.data.size() == 600540 and is_equal_approx(arrival.get_length(), 6.255625), "Arrival has three overlapping sets with their pauses")
	check(arrival.format == AudioStreamWAV.FORMAT_16_BITS and arrival.mix_rate == 48000 and not arrival.stereo, "Arrival remains uncompressed mono PCM")
	check(arrival.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Arrival stops after three sets")
	check(digest(original) == ORIGINAL_HASH, "Original special-alert PCM remains byte-identical")
	check(nuclear.data == original + original, "Nuclear keeps original two cycles")
	check(siege.data == original + original, "Siege Ship keeps original two cycles")
	check(arrival.data != nuclear.data, "New regular arrival is isolated from special alerts")
	var set_bytes: int = arrival.data.size() / 3
	for i in range(3):
		check(arrival.data.slice((i + 1) * set_bytes - 96000, (i + 1) * set_bytes) == silence(), "Arrival set %d retains one-second silent pause" % (i + 1))
	print("ARRIVAL_SCOPE_RESULT checks=%d failures=%d" % [checks, failures])
	arrival = null
	nuclear = null
	siege = null
	quit(1 if failures else 0)

func silence() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(96000)
	data.fill(0)
	return data
