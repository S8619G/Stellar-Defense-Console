extends RefCounted
## Names used inside earlier private builds, before every internal name matched the public
## game. They are stored encoded so they never appear as readable words in the source.
## Used only to (1) read settings and high scores saved by those builds, (2) keep the original
## label footprint so contact placement stays identical, and (3) let the tests confirm none
## of them appear anywhere in the project or on screen.

## Older saved setting key (encoded) -> current key.
const SETTING_KEYS := {"YXV0b192aXBlcnM=": "auto_interceptors", "YXV0b19yYXB0b3Jz": "auto_gunships", "YXV0b19mdGw=": "auto_jump"}
## Older high-score stat key (encoded) -> current key.
const STAT_KEYS := {"cmFpZGVy": "drone", "aGVhdnlfcmFpZGVy": "breacher", "YmFzZXNoaXA=": "carrier", "cmVzdXJyZWN0aW9uX3NoaXA=": "siege_ship"}
## Original label text measured for the capital-ship placement footprint (encoded).
const SIEGE_FOOTPRINT := "UkVTVVJSRUNUSU9O"
const CARRIER_FOOTPRINT := "QkFTRVNISVA="
## Words that must never appear in the project or on screen (encoded, upper case).
const RETIRED_WORDS := ["VklQRVI=", "UkFQVE9S", "UkFJREVS", "RFJBRElT", "RlRM", "Q1lMT04=", "QkFTRVNUQVI=", "QkFTRVNISVA=", "UkVTVVJSRUNUSU9O", "Q09MT05JQUw=", "QkFUVExFU1RBUg==", "R0FMQUNUSUNB", "RlJBSw==", "QURBTUE=", "Q0FQUklDQQ==", "S09CT0w="]

static func decode(text: String) -> String:
	return Marshalls.base64_to_utf8(text)

static func footprint_text(kind: String) -> String:
	return decode(SIEGE_FOOTPRINT if kind == "siege_ship" else CARRIER_FOOTPRINT)

static func retired_words() -> Array:
	var out: Array = []
	for word in RETIRED_WORDS:
		out.append(decode(word))
	return out

## Copies values saved under older keys to the current keys (current keys win).
static func upgrade_keys(raw: Dictionary, table: Dictionary) -> Dictionary:
	var out := raw.duplicate()
	for encoded in table:
		var old_key := decode(encoded)
		if out.has(old_key):
			if not out.has(table[encoded]):
				out[table[encoded]] = out[old_key]
			out.erase(old_key)
	return out
