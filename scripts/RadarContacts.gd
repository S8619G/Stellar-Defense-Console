extends Control
## Independent overlay: never changes the ambient dome or its animation clock.
## Coordinates are normalized to the dome; +Z is farther away from the viewer.

signal contact_spawned(contact_id: String, kind: String, faction: String)
signal arrival_beep_played(contact_id: String, kind: String)
signal interceptor_launch_played(count: int)
signal hostile_intercepted(interceptor_id: String, hostile_id: String)
signal ship_damaged(amount: float, hull_remaining: float)
## 1.0.8: a nuke hit the ship (full = direct hit; false = Defense Shield partial hit). Visual cue only.
signal nuke_hit_ship(full: bool)
signal jump_completed
## 1.08: a Breacher breach took JUMP offline (true) or the hack ended (false).
signal jump_offline_changed(offline: bool)
signal carrier_identified(contact_id: String)
signal carrier_destroyed(contact_id: String)
signal wave_changed(wave_number: int)
## 1.2.0: a defined wave's Enemy force was destroyed.
signal wave_cleared(wave_number: int)
signal siege_arrived(contact_id: String)
signal siege_destroyed(contact_id: String)
## 1.09: Stealth Interceptor events for the session log (ready, launched, fired, lost, recovered).
signal stealth_event(message: String)
## 1.1.0: other battle events for the session log (nuke speed bonus, recovery pauses).
signal battle_event(message: String)
## 0.1.2: both missile bonuses are earned; the console asks the player to keep
## Current or take Other ("RAPID" / "DOUBLE"). Set Offer = the after-set offer.
signal missile_bonus_offer(current: String, other: String, set_offer: bool)

## 1.07: kinds a ship or Gunship missile may attack (also when it changes target).
const MISSILE_TARGET_KINDS := ["carrier", "breacher", "siege_ship", "nuke"]
const Icons = preload("res://scripts/RadarContactIcons.gd")
const BattleAudio = preload("res://scripts/BattleAudio.gd")
const FirewallAudio = preload("res://scripts/FirewallAudio.gd")
const ScopeShape = preload("res://scripts/ScopeShape.gd")
const ProtectAudio = preload("res://scripts/ProtectAudio.gd")
const LegacyNames = preload("res://scripts/LegacyNames.gd")
const ACTIVE_KINDS := ["interceptor", "gunship", "drone", "breacher", "unknown", "carrier", "missile"]
const CAPITAL_KINDS := ["carrier", "siege_ship"]
const SMALL_HOSTILE_KINDS := ["drone"]

@export_group("Contacts")
@export var auto_spawn: bool = true
## Raised from 14 so later waves have room for up to four Enemy Carriers and a Siege Ship.
@export_range(1, 40) var max_contacts: int = 20
@export_range(3.0, 30.0) var wave_interval_seconds: float = 9.0
@export_range(0.5, 3.0) var arrival_gap_seconds: float = 0.85
@export_range(0.25, 3.0) var movement_speed: float = 1.0
## Overall contact icon size (1.0 was the Returning Flights size).
@export_range(0.4, 2.5) var icon_size: float = 1.3
@export var show_labels: bool = true
## 1.07: off = short tags (ATTACK DRONE, INTERCEPTOR, GUNSHIP, INTERCEPTORS x3; no tags on missiles).
## Tick to bring back the full tags with IDs, RTB and strength (for testing).
@export var show_full_tags: bool = false
## Contact name text size in design pixels (capital ships use 2 more).
@export_range(10, 32) var label_font_size: int = 16
## How much lighter than the icon color the name text is drawn.
@export_range(0.0, 0.6) var label_brighten: float = 0.15
## Thin dark outline behind the name text, in pixels. 0 turns it off.
@export_range(0, 8) var label_outline_size: int = 4
@export var label_outline_color := Color(0.0, 0.0, 0.0, 0.85)
@export var random_seed: int = 0

@export_group("Ship Sizes")
@export_range(0.4, 1.5) var small_ship_icon_scale: float = 0.75
@export_range(0.8, 2.0) var carrier_icon_scale: float = 1.35
@export_range(0.6, 2.5) var civilian_icon_scale: float = 1.6
@export_range(0.8, 3.0) var civilian_capital_icon_scale: float = 2.1

@export_group("Ship Speeds")
## Speeds are scope-radius units per second, then multiplied by Movement Speed.
@export_range(0.01, 0.15) var normal_ship_speed: float = 0.035
@export_range(0.02, 0.25) var small_hostile_speed: float = 0.05
@export_range(0.06, 0.6) var interceptor_speed: float = 0.14
@export_range(0.03, 0.6) var fighter_acceleration: float = 0.12

@export_group("Battlefield")
## Unseen own ship; +Y is up the scope and +Z is farther away.
@export var own_ship_position := Vector3(0.0, -1.05, -0.15)
@export_range(1, 3) var max_carriers: int = 2
@export_range(1, 16) var max_drones: int = 8
@export_range(1, 8) var max_drones_per_carrier: int = 4
@export_range(1, 20) var max_missiles: int = 10
@export var carrier_weapons_enabled: bool = true
@export_range(2.0, 30.0) var drone_launch_interval: float = 7.0
@export_range(3.0, 40.0) var missile_launch_interval: float = 11.0
@export_range(0.08, 0.5) var missile_speed: float = 0.12
@export_range(0.06, 0.2) var carrier_emission_radius: float = 0.10

@export_group("Identification and Ship Weapons")
@export_range(1.0, 8.0) var identification_seconds: float = 3.0
@export var klaxon_enabled: bool = true
@export_range(-40.0, 0.0) var klaxon_volume_db: float = -5.0
@export var own_weapons_enabled: bool = true
@export_range(2.0, 20.0) var own_missile_interval: float = 8.0
@export_range(0.1, 0.6) var own_missile_speed: float = 0.28
@export_range(2, 30) var carrier_hits_to_destroy: int = 11
@export_range(1, 8) var max_own_missiles: int = 4
## 0.1.2 spread targeting (Normal and Hard only): each ship missile goes to the weakest
## Enemy Carrier counting missiles already flying at it, so a Enemy Carrier that is already
## covered is skipped; with Double Missile the two missiles of a volley go to two
## different Enemy Carriers when more than one is on the scope. Off = the 1.2.9 choice.
@export var ship_missiles_spread_carriers: bool = false
## 0.1.2 Double Missile quick pair: the second missile of a Double Missile volley
## launches Pair Seconds after the first, so two missiles can be seen. Off = both at once.
@export var double_missile_quick_pair: bool = false
@export_range(0.05, 1.5) var double_missile_pair_seconds: float = 0.3
## 1.05: ship missiles also go after a nuclear missile once it has flown past
## Ship Nuke Target Fraction of the way to the ship (0.5 = halfway). Nukes then come
## first, ahead of close Breachers. Each ship missile counts as one nuke hit.
@export var ship_missiles_target_nukes: bool = true
@export_range(0.0, 1.0) var ship_nuke_target_fraction: float = 0.75

@export_group("Ship Defense")
@export_range(10.0, 500.0) var max_hull: float = 100.0
@export_range(1.0, 100.0) var missile_damage: float = 10.0
@export_range(0.001, 0.02) var missile_impact_radius: float = 0.004
@export_range(-30.0, 0.0) var impact_volume_db: float = -10.0
@export_range(0.15, 1.0) var hit_flash_seconds: float = 0.45
## Defense Shield kill zone: distance from the ship (scope radii). Missile paths cross
## the flak arc at about 0.06 to 0.10, so 0.12 destroys missiles on or just above the arc.
@export_range(0.05, 0.7) var prox_defense_radius: float = 0.12
## 1.2.8: chance that the firing Defense Shield shoots down a nuke in the kill zone.
## One chance per nuke (0.35 = about 1 nuke in 3). Same on every level.
@export_range(0.0, 1.0) var battery_nuke_chance: float = 0.35
## 1.2.8: splash damage when the battery shoots down a nuke, as a share of a direct
## nuke hit (0.33 = one third: about 15 hull on Easy, 20 on Normal, 25 on Hard).
@export_range(0.0, 1.0) var battery_nuke_splash: float = 0.33
## 1.2.8: the Auto Defense Shield also starts firing when a nuke comes close.
@export var auto_battery_for_nukes: bool = true
## Auto Defense Shield starts firing when a missile is this close, a moment before
## it reaches the kill zone, so the arc is already active when it arrives.
@export_range(0.05, 0.7) var auto_battery_lead_radius: float = 0.22
## Chance that each battery shot destroys a missile in the defense zone. Capped at 95%.
@export_range(0.0, 0.95) var prox_success_chance: float = 0.45
## Seconds between battery shots at each missile while firing.
@export_range(0.05, 1.0) var battery_shot_interval: float = 0.1
## Seconds of continuous fire from a full battery to empty.
@export_range(2.0, 15.0) var prox_burst_seconds: float = 6.0
## Seconds to recharge from empty to full once firing stops, on NORMAL.
## 1.03: slower than the earlier 18 seconds; Easy and Hard scale it (Difficulty group).
@export_range(5.0, 60.0) var battery_recharge_seconds: float = 24.0
## Short pause after firing stops before recharging begins.
@export_range(0.0, 5.0) var battery_recharge_delay: float = 1.0
## Minimum charge needed to start firing again after the battery runs dry.
@export_range(0.0, 50.0) var battery_restart_percent: float = 15.0
@export_range(-40.0, 0.0) var battery_volume_db: float = -9.0
@export_range(1.0, 5.0) var battery_sound_speed: float = 3.0
## Repairs one percentage point per tick, after a quiet period without a hit.
@export_range(0.0, 120.0) var repair_delay_seconds: float = 20.0
@export_range(1.0, 60.0) var repair_tick_seconds: float = 8.0

@export_group("Score and Rapid Repair")
@export_range(0, 10000) var fighter_points: int = 100
@export_range(0, 10000) var nuclear_points: int = 500
@export_range(0, 10000) var carrier_points: int = 1000
@export_range(0, 10000) var breacher_points: int = 300
@export_range(0, 10000) var jump_score_cost: int = 3000
## 1.1.0: a JUMP during a wave costs Jump Score Cost or this percent of the current score,
## whichever is bigger (0 = always Jump Score Cost, as in 1.0.9).
@export_range(0.0, 50.0) var jump_score_percent: float = 10.0
## Cost of the latest JUMP (for its status messages).
var last_jump_cost: int = 3000
@export_range(1000, 100000) var bonus_repair_points: int = 10000
## Later bonus charges are spaced out: 10,000, then 25,000, 50,000, then every 50,000 more.
@export_range(1000, 500000) var second_bonus_points: int = 25000
@export_range(1000, 500000) var third_bonus_points: int = 50000
@export_range(1000, 500000) var later_bonus_step: int = 50000
@export_range(1.0, 100.0) var rapid_repair_percent: float = 25.0
## 1.1.0: most Rapid Repair charges held, on Easy and on Normal and Hard (0 = no limit,
## as in 1.0.9). A charge earned at the limit is lost. Once the limit is reached, no
## charges are earned until the player is down to Repair Resume Charges; earning then
## starts again at the next point total still ahead.
@export_range(0, 20) var rapid_repair_limit_easy: int = 2
@export_range(0, 20) var rapid_repair_limit: int = 4
@export_range(0, 20) var repair_resume_charges: int = 1
@export_range(1.0, 20.0) var rapid_repair_seconds: float = 5.0
## 0.1.2 fix: Rapid Repair is live only while the hull readout shows below 100%, so a
## charge is never spent on a hull that reads full (the readout rounds up). Off = 1.2.9.
@export var rapid_repair_needs_shown_damage: bool = false
## 1.05: base points for each enemy missile the Defense Shield destroys (all levels).
## The score multiplier applies, and the points count toward bonus repairs.
@export_range(0, 1000) var battery_kill_points: int = 10

@export_group("JUMP")
@export_range(5.0, 180.0) var jump_recharge_seconds: float = 45.0
@export_range(2.0, 30.0) var post_jump_safe_seconds: float = 8.0
@export var jump_starts_ready: bool = true
## 1.08: while any Breacher has broken through (hull drain), JUMP is OFFLINE and
## cannot be used, manual or AUTO. When the hack ends, the charge restarts from 0%.
@export var jump_offline_on_breach: bool = true
## Seconds the JUMP takes to rebuild from 0% after a breach ends (normal recharge is
## Jump Recharge Seconds; a faster rebuild keeps JUMP a usable escape between breaches).
@export_range(5.0, 180.0) var jump_breach_recharge_seconds: float = 45.0
@export_range(-40.0, 0.0) var jump_volume_db: float = -8.0

@export_group("Nuclear Threat")
@export var nuclear_weapons_enabled: bool = true
@export_range(5.0, 90.0) var nuclear_launch_delay: float = 18.0
@export_range(0.02, 0.10) var nuclear_speed: float = 0.058
@export_range(20.0, 100.0) var nuclear_damage: float = 60.0
## 0.1.2 second nuke: a Enemy Carrier can fire a second nuke on Normal and Hard.
## Each Enemy Carrier picks its own cool-down at random between Min and Max seconds after
## its first nuke (halved by the Nuclear Strike trait). Easy: one nuke, as before.
@export var carrier_second_nuke: bool = false
@export_range(10.0, 600.0) var normal_second_nuke_min_seconds: float = 75.0
@export_range(10.0, 600.0) var normal_second_nuke_max_seconds: float = 120.0
@export_range(10.0, 600.0) var hard_second_nuke_min_seconds: float = 180.0
@export_range(10.0, 600.0) var hard_second_nuke_max_seconds: float = 300.0
@export_range(-40.0, 0.0) var nuclear_alert_volume_db: float = -7.0
@export_range(1.0, 3.0) var nuclear_alert_speed: float = 1.5
@export_range(-40.0, 0.0) var nuclear_beep_volume_db: float = -12.0
@export_range(0.5, 3.0) var nuclear_beep_far_seconds: float = 1.2
@export_range(0.10, 0.4) var nuclear_beep_near_seconds: float = 0.15
## 1.1.0: each Enemy Carrier nuke flies up to this much faster than usual, picked at
## launch (0.08 = 0% to 8% faster). 0 turns the random bonus off.
@export_range(0.0, 0.3) var nuke_speed_random_max: float = 0.08
## 1.1.0: on Hard, each nuke's bonus leans to the top of the range (the larger of
## two random picks, about 5.3% on average instead of 4%).
@export var hard_nuke_speed_lean: bool = true

@export_group("Gunships")
@export_range(1, 4) var max_gunships: int = 2
@export_range(0.03, 0.13) var gunship_speed: float = 0.10
## 1.0.5: after a launch, Gunships that were already ready wait this long before the
## next launch (ships still counting down keep their own countdown).
@export_range(2.0, 30.0) var gunship_launch_cooldown: float = 8.0
## 1.0.5: after a Gunship lands, that Gunship waits this long before it is ready again.
## Each Gunship has its own wait; a landing never restarts another Gunship's wait.
@export_range(0.0, 20.0) var gunship_recovery_seconds: float = 5.0
@export_range(30.0, 180.0) var gunship_sortie_seconds: float = 70.0
@export_range(3.0, 20.0) var gunship_fire_interval: float = 8.0
@export_range(0.1, 0.9) var gunship_missile_damage: float = 0.5
@export_range(0.0, 0.95) var gunship_evasion_chance: float = 0.75
@export_range(2.0, 15.0) var carrier_flak_interval: float = 4.0
@export_range(0.3, 1.5) var carrier_flak_range: float = 0.85

@export_group("Breachers")
@export var breachers_enabled: bool = true
@export_range(1, 4) var max_breachers: int = 2
@export_range(1, 2) var max_heavy_per_carrier: int = 1
@export_range(5.0, 90.0) var heavy_launch_interval: float = 28.0
@export_range(0.03, 0.12) var breacher_speed: float = 0.075
@export_range(2.0, 20.0) var hacking_seconds: float = 6.0
@export_range(0.5, 8.0) var hack_drain_percent_per_second: float = 1.5
@export_range(0.27, 0.5) var hacking_range: float = 0.30
## Where Breachers park beside the ship: X to each side, Y above the hull.
@export var hack_park_offset := Vector2(0.16, 0.10)
@export_range(1, 10) var breacher_hit_points: int = 5
## Ship missiles target Breachers parked within this distance of the ship before Enemy Carriers.
@export_range(0.05, 2.0) var ship_missile_heavy_range: float = 0.15
## 1.2.3: ship missiles go after a Breacher that is hacking or draining the ship
## at any distance, right after incoming nukes (hacking Breachers park about
## 0.16 to 0.19 from the ship, outside Ship Missile Heavy Range).
@export var ship_missiles_target_hacking: bool = true

@export_group("Waves")
## The wave number rises every Wave Seconds of battle; later waves are harder.
@export var waves_enabled: bool = true
@export_range(30.0, 600.0) var wave_seconds: float = 120.0
## Enemy Carriers allowed at once grows from Max Enemy Carriers (2) up to this number.
@export_range(1, 6) var wave_max_carriers: int = 4
## One more Enemy Carrier is allowed every this many waves (wave 3, wave 5 ...).
@export_range(1, 10) var extra_carrier_every_waves: int = 2
## Attack Drone and missile launch intervals shrink by this fraction each wave...
@export_range(0.0, 0.3) var wave_interval_step: float = 0.1
## ...but never below this fraction of their normal value.
@export_range(0.3, 1.0) var wave_interval_floor: float = 0.6
## From this wave on, up to Wave Max Breachers may be on screen.
@export_range(1, 10) var extra_heavy_from_wave: int = 4
@export_range(1, 4) var wave_max_breachers: int = 3

@export_group("Defined Waves")
## 1.2.0: each wave is one Enemy attack with a set force of Enemy Carriers. It ends
## when that force is destroyed, then a short rest. Off = the 1.1.1 timer waves.
## Used only while contacts arrive on their own (Auto Spawn).
@export var defined_waves: bool = true
## Waves in a set: Probe, Strike, Assault, Pressure, Major engagement.
@export_range(2, 10) var wave_set_size: int = 5
@export var wave_names: Array[String] = ["PROBE", "STRIKE", "ASSAULT", "PRESSURE", "MAJOR ENGAGEMENT"]
## Enemy Carriers in each wave of a set, per difficulty.
@export var easy_wave_force: Array[int] = [2, 2, 2, 2, 2]
@export var normal_wave_force: Array[int] = [2, 3, 2, 3, 3]
@export var hard_wave_force: Array[int] = [2, 3, 3, 3, 3]
## Enemy Carriers allowed on the scope at once in each wave of a set.
@export var wave_onscreen_carriers: Array[int] = [2, 2, 3, 3, 4]
## Breachers allowed on the scope at once in each wave of a set.
@export var wave_heavy_caps: Array[int] = [1, 2, 2, 2, 3]
## Attack Drone and missile launch intervals in each wave of a set (1.0 = normal).
@export var wave_launch_factors: Array[float] = [1.0, 0.95, 0.9, 0.85, 0.8]
## The Major engagement brings the Siege Ship this many seconds in.
@export var major_siege: bool = true
@export_range(0.0, 120.0) var major_siege_delay: float = 20.0
## Safety: after this long no more Enemy Carriers arrive in the wave.
@export_range(60.0, 900.0) var wave_safety_seconds: float = 300.0
## Rest between waves (seconds).
@export_range(2.0, 30.0) var easy_rest_seconds: float = 10.0
@export_range(2.0, 30.0) var normal_rest_seconds: float = 7.0
@export_range(2.0, 30.0) var hard_rest_seconds: float = 5.0
## The last part of the rest shows WAVE n INBOUND.
@export_range(1.0, 6.0) var inbound_seconds: float = 3.0
## Wave tally: points for clearing, plus points per hull percent kept.
@export_range(0, 5000) var wave_clear_points: int = 500
@export_range(0, 50) var wave_hull_points: int = 10
## Extra points for surviving the Major engagement.
@export_range(0, 20000) var set_clear_points: int = 2500
## Score multiplier gained per completed set, and its cap.
@export_range(0.0, 1.0) var set_score_step: float = 0.25
@export_range(1.0, 6.0) var set_score_cap: float = 3.0
## Waves 3-4 of a set get one announced trait (Hard: waves 2-4; Easy: from set 2).
@export var traits_enabled: bool = true
## Each new set adds one permanent announced Enemy tactic.
@export var set_modifiers_enabled: bool = true
## 1.2.2: the round after each Major engagement. Protect the fleet (civilian ships
## under Attack Drone attack, Interceptors only), the 1.2.0 bonus Attack Drone sweep, or none.
@export_enum("Protect the convoy", "Bonus sweep", "None") var set_end_round: int = 0
## 1.2.0 bonus sweep settings (used when Set End Round is Bonus sweep).
@export_range(3, 24) var sweep_drones: int = 12
@export_range(1, 6) var sweep_group_size: int = 3
@export_range(0.5, 10.0) var sweep_group_gap: float = 3.0
@export_range(0.03, 0.3) var sweep_speed: float = 0.10
@export_range(0, 20000) var sweep_perfect_points: int = 3000
## JUMP jump during the rest: free, starts the next wave early, small bonus.
@export_range(0, 5000) var jump_rest_jump_points: int = 250
@export_range(0.5, 8.0) var rest_jump_safe_seconds: float = 2.0
## Random Systems Bonus for waves survived. Remove a name to turn it off.
@export var systems_bonus_enabled: bool = true
@export var systems_bonuses: Array[String] = ["REPAIR", "EMP", "INTERCEPTORS", "GUNSHIP", "SPEED", "AUTO SHIELD", "RAPID FIRE", "STEALTH"]
## 1.2.2: first wave that can give a Systems Bonus (set 1 gives none).
@export_range(1, 50) var bonus_start_wave: int = 6
## 1.2.2: chance of a bonus for each cleared wave. The end of a set always gives one.
@export_range(0.0, 1.0) var bonus_wave_chance: float = 0.4
## 1.2.2: tiers by set. A tier is unlocked from its set on; the bonus comes from the
## highest unlocked tier. Repeat a name in a tier to make it more likely.
@export var bonus_low_tier: Array[String] = ["EMP", "SPEED"]
@export var bonus_medium_tier: Array[String] = ["REPAIR", "GUNSHIP", "RAPID FIRE"]
@export var bonus_high_tier: Array[String] = ["INTERCEPTORS", "AUTO SHIELD", "STEALTH"]
@export_range(1, 20) var bonus_low_tier_set: int = 2
@export_range(1, 20) var bonus_medium_tier_set: int = 3
@export_range(1, 20) var bonus_high_tier_set: int = 5
## 1.2.2: once a higher tier is unlocked, chance that a bonus comes from a lower one.
@export_range(0.0, 1.0) var bonus_lower_tier_chance: float = 0.3333
## 1.2.2: Hard starts bonuses this many sets later (every tier shifts too) and
## multiplies the per-wave chance by Hard Bonus Chance Factor.
@export_range(0, 5) var hard_bonus_set_delay: int = 1
@export_range(0.0, 1.0) var hard_bonus_chance_factor: float = 0.5
## 1.2.2: the wave tally reads NO SYSTEMS BONUS after a wave without one.
@export var show_no_systems_bonus: bool = true
@export_range(1, 5) var bonus_repair_cap: int = 3
@export_range(1, 6) var bonus_extra_interceptors: int = 2
@export_range(1, 3) var bonus_extra_gunships: int = 1
@export_range(1.0, 2.0) var bonus_speed_factor: float = 1.15
@export_range(0.3, 1.0) var bonus_fire_factor: float = 0.75
@export var wave_cues_enabled: bool = true
@export_range(-40.0, 6.0) var action_stations_volume_db: float = -14.0
@export_range(-40.0, 6.0) var all_clear_volume_db: float = -14.0
## Rest tally panel top, in scope radii below the centre.
@export_range(-0.8, 0.8) var rest_tally_offset: float = 0.22
## 1.2.2: border width of the wave tally panel, in pixels (1.2.1 was 1).
@export_range(1.0, 8.0) var rest_tally_border_width: float = 3.0
## 1.0.9: every round box (wave cleared, set complete, Bonus Sweep result and the Protect
## the convoy result) shares one size, place and see-through look. Off = the 1.0.8 boxes.
@export var shared_score_boxes: bool = false
## Width of the shared round box in pixels (600 = the Game Over score screen width).
@export_range(300.0, 900.0) var score_box_width: float = 600.0
## Top of the shared round box, in scope radii from the centre (negative = above the
## centre). -0.48 = the place the Protect the convoy result used in 1.0.8.
@export_range(-0.95, 0.8) var score_box_offset: float = -0.48
## How solid the shared round box background is (1 = fully solid; 1.0.8 used 0.9).
@export_range(0.2, 1.0) var score_box_opacity: float = 0.65
## Dark outline around the round box text so it reads through the see-through box (0 = none).
@export_range(0, 12) var score_box_text_outline: int = 5

@export_group("Protect the Fleet")
## 1.2.2: after each Major engagement the scope is reset and 2 to 4 random civilian
## ships come under Attack Drone attack. Interceptors only; the auto options pause for the round.
@export_range(1, 5) var protect_civilians_min: int = 2
@export_range(1, 5) var protect_civilians_max: int = 4
## Attack Drones in the round: First Attack Drones after set 1, plus Attack Drones Step per later set,
## up to Attack Drones Cap. Easy and Hard add these (Easy never below 2).
@export_range(1, 24) var protect_first_drones: int = 4
@export_range(0, 8) var protect_drones_step: int = 2
@export_range(2, 24) var protect_drones_cap: int = 12
@export_range(-6, 0) var easy_protect_drone_change: int = -2
@export_range(0, 6) var hard_protect_drone_change: int = 2
## Seconds one Attack Drone takes to destroy a civilian ship (two take half as long).
@export_range(4.0, 120.0) var easy_civilian_kill_seconds: float = 26.0
@export_range(4.0, 120.0) var normal_civilian_kill_seconds: float = 20.0
@export_range(4.0, 120.0) var hard_civilian_kill_seconds: float = 14.0
## 1.2.3: each later set shortens the kill time by Kill Time Step of the difficulty
## value (0.1 = Normal 20 s, 18 s, 16 s ...), never below Kill Time Floor.
@export_range(0.0, 0.5) var protect_kill_time_step: float = 0.1
@export_range(1.0, 60.0) var protect_kill_time_floor: float = 10.0
## The round ends when every Attack Drone is destroyed, every civilian ship is lost, or
## after this many seconds (Attack Drones still on the scope jump away).
@export_range(10.0, 300.0) var protect_round_seconds: float = 60.0
## Bonus: Ship Points x the hull each surviving ship kept, plus Full Fleet Points
## when every ship survives. The score multiplier applies.
@export_range(0, 10000) var protect_ship_points: int = 500
@export_range(0, 20000) var protect_full_fleet_points: int = 1000
## Attack Drone flying speed in the round, attack distance, and arrivals.
## 1.2.5 fleet defense. All switches off = the 1.2.4 round; the console scene turns them on.
## Size toughness: a civilian ship lasts this many times the kill time, by size
## (large: C; medium: A and D; small: B and E).
@export var civilian_size_toughness: bool = false
@export_range(0.5, 4.0) var civilian_large_toughness: float = 2.0
@export_range(0.5, 4.0) var civilian_medium_toughness: float = 1.2
@export_range(0.5, 4.0) var civilian_small_toughness: float = 1.0
## Evasion: medium and small ships move away from Attack Drones within 0.2 scope radii, weaving,
## bent toward Aegis, and always staying inside the scope outline. Large ships do not move.
@export var civilian_evasion: bool = false
@export_range(0.0, 0.1) var civilian_small_evade_speed: float = 0.035
@export_range(0.0, 0.1) var civilian_medium_evade_speed: float = 0.02
## Damage taken while evading (1 = no cut; evasion only buys time by moving).
@export_range(0.2, 1.0) var civilian_small_evade_damage: float = 1.0
@export_range(0.2, 1.0) var civilian_medium_evade_damage: float = 1.0
## How strongly the escape path bends toward Aegis (0 = straight away from the Attack Drones).
@export_range(0.0, 2.0) var civilian_evade_bias_home: float = 0.5
## Ships never move lower than this (scope radii below centre), clear of Aegis's outline.
@export_range(-0.9, 0.0) var civilian_evade_floor_y: float = -0.5
## Interceptors already on patrol by the fleet when the round starts (0 = none).
@export_range(0, 4) var protect_patrol_interceptors: int = 0
## Seconds each Attack Drone holds at its jump-in point, fading in, before it attacks (0 = none).
@export_range(0.0, 5.0) var protect_jump_in_hold: float = 0.0
## Most Attack Drones that can damage one civilian ship at once (0 = no limit).
@export_range(0, 6) var protect_damage_stack_cap: int = 0
## Counters for the checks: outline corrections, lowest y reached, and times outside the outline.
var evade_corrections := 0
var evade_min_y := 9.0
var evade_outside := 0
@export_range(0.02, 0.3) var protect_drone_speed: float = 0.07
@export_range(0.02, 0.2) var protect_attack_range: float = 0.07
@export_range(1, 6) var protect_drone_group_size: int = 3
@export_range(0.2, 10.0) var protect_drone_group_gap: float = 1.0
## 1.2.3: Interceptor hits a Attack Drone takes in this round: Attack Drone Interceptor Hits after set 1,
## plus Hits Step per later set, up to Hits Cap. Normal waves keep Attack Drone Interceptor Hits.
@export_range(1, 10) var protect_drone_interceptor_hits: int = 4
@export_range(0, 3) var protect_drone_hits_step: int = 1
@export_range(1, 12) var protect_drone_hits_cap: int = 6
## 1.2.3: Attack Drones in this round fire back. When a Interceptor first engages a Attack Drone, that
## Interceptor is lost with this chance (rolled once per Attack Drone; 0 = off).
@export_range(0.0, 1.0) var protect_return_fire_chance: float = 0.1667
## 1.2.7: JUMP is always held during the round (the 1.2.2 Protect Allow Jump option is removed);
## the ship stays to protect the civilian ships.
## 1.2.7: extra seconds the result stays on screen after the round (added to the rest).
@export_range(0.0, 20.0) var protect_result_extra_seconds: float = 5.0
## 1.2.7: seconds the bonus and the panel border flash (twice a second) before staying steady.
@export_range(0.0, 10.0) var protect_result_flash_seconds: float = 3.0
## 1.2.7: a sound when the round ends: all saved, some saved (neutral) or all lost.
@export var protect_result_sounds: bool = true
@export_range(-40.0, 6.0) var fleet_saved_volume_db: float = -14.0
@export_range(-40.0, 6.0) var fleet_partial_volume_db: float = -14.0
@export_range(-40.0, 6.0) var fleet_lost_volume_db: float = -14.0
## Civilian ship colors: blue, dimming toward Damaged Color with lost hull, and
## blinking at or below Critical Percent.
@export var civilian_color := Color(0.32, 0.58, 1.0)
@export var civilian_damaged_color := Color(0.28, 0.32, 0.46)
@export_range(0.0, 100.0) var civilian_critical_percent: float = 25.0
@export_range(0.5, 10.0) var civilian_blink_hz: float = 3.0
## 1.2.9: every switch below off = the 1.2.8 round; the console scene turns them on.
## Nothing here changes the main game.
@export_subgroup("Round Sounds 1.2.9")
## Battle sounds for the round only: a tick on each Interceptor hit, a louder Attack Drone
## explosion, a warning when a ship is first attacked and when it reaches Critical
## Percent, a boom sized by the civilian ship lost, and the fighter-lost boom for a
## Interceptor downed by a Attack Drone.
@export var protect_round_sounds: bool = false
@export_range(-40.0, 0.0) var protect_interceptor_hit_volume_db: float = -22.0
@export_range(-40.0, 0.0) var protect_drone_kill_volume_db: float = -13.0
@export_range(-40.0, 0.0) var protect_ship_attacked_volume_db: float = -14.0
@export_range(-40.0, 0.0) var protect_ship_critical_volume_db: float = -12.0
@export_range(-40.0, 0.0) var protect_small_ship_lost_volume_db: float = -14.0
@export_range(-40.0, 0.0) var protect_medium_ship_lost_volume_db: float = -11.0
@export_range(-40.0, 0.0) var protect_large_ship_lost_volume_db: float = -8.0
@export_range(-40.0, 0.0) var protect_interceptor_lost_volume_db: float = -15.0
@export_subgroup("Damaged Ships 1.2.9")
## On = a damaged ship keeps Civilian Color (no fade to Damaged Color), shows a hull
## bar under its label and flashes white briefly each time a Attack Drone hits it.
@export var civilian_hull_bar: bool = false
@export_range(10.0, 80.0) var civilian_hull_bar_width: float = 38.0
@export_range(0.0, 0.6) var civilian_hit_flash_seconds: float = 0.15
@export_subgroup("Round Counter 1.2.9")
## On = during the round the alert box shows SHIPS n OF m, ATTACK DRONES n LEFT and TIME m:ss.
@export var protect_round_counter: bool = false
@export_subgroup("Challenge Mix 1.2.9")
## On = each round picks some challenges at random: overlapping Attack Drone waves, fewer
## Interceptors, and Attack Drones ganging up. How many: the set number, Easy one fewer, Hard one
## more, from 0 up to Challenge Max.
@export var protect_challenge_mix: bool = false
@export_range(0, 3) var protect_challenge_max: int = 3
@export_range(-3, 0) var easy_protect_challenge_change: int = -1
@export_range(0, 3) var hard_protect_challenge_change: int = 1
## Waves: the Attack Drones arrive in this many groups; the next group jumps in this many
## seconds after the last one, without waiting for the scope to clear.
@export_range(2, 4) var protect_wave_groups_min: int = 2
@export_range(2, 4) var protect_wave_groups_max: int = 3
@export_range(2.0, 30.0) var protect_wave_gap_min: float = 6.0
@export_range(2.0, 30.0) var protect_wave_gap_max: float = 10.0
## Fewer Interceptors: this many fewer launches than Attack Drones, never more than a third of them.
@export_range(0, 4) var protect_fewer_interceptors_min: int = 1
@export_range(0, 4) var protect_fewer_interceptors_max: int = 2
## Gang up: Attack Drones prefer a ship already under attack (Claim Pull per Attack Drone on it)
## and the most damaged ship (Damage Pull x hull lost), against plain distance.
@export_range(0.0, 2.0) var protect_gang_claim_pull: float = 0.5
@export_range(0.0, 2.0) var protect_gang_damage_pull: float = 0.3
## "A bit more danger" (1.2.9), on Normal from Extra Attack Drones From Set on: this many
## extra Attack Drones (within Attack Drones Cap), and the civilian kill time multiplied by Later
## Kill Time Factor (below 1 = Attack Drones destroy ships faster; 1 = as in 1.2.8).
## Tick More Danger On Hard to add the same on Hard. Easy never gets it.
@export_range(1, 20) var protect_extra_drones_from_set: int = 3
@export_range(0, 6) var protect_extra_drones: int = 0
@export_range(0.3, 1.0) var protect_later_kill_time_factor: float = 1.0
@export var protect_more_danger_on_hard: bool = false
@export_subgroup("Dogfights 1.2.9")
## On = Attack Drones and Interceptors dogfight: a Attack Drone engaged by a Interceptor may break off to
## fight it, hits land only from behind, and a Attack Drone behind a Interceptor can shoot it
## down (this replaces the one return-fire roll per Attack Drone).
@export var protect_dogfights: bool = false
## Share of Attack Drones that break off when a Interceptor engages them (the rest keep attacking the ship).
@export_range(0.0, 1.0) var protect_breakoff_chance: float = 0.6
## A Interceptor this close (scope radii) that is chasing a Attack Drone counts as engaging it.
@export_range(0.02, 0.5) var protect_engage_radius: float = 0.14
## Wingman help, both sides: once a second, a free fighter within Help Range may go
## after the attacker of a nearby friend with this chance.
@export_range(0.0, 1.0) var protect_help_chance: float = 0.3
@export_range(0.02, 0.6) var protect_help_range: float = 0.28
## "Behind": within Tail Range of the target and inside its tail cone (Tail Cos,
## 1 = straight behind only, 0 = anywhere in the rear half).
@export_range(0.02, 0.3) var protect_tail_range: float = 0.07
@export_range(-1.0, 1.0) var protect_tail_cos: float = 0.35
## A Attack Drone behind a Interceptor fires every Shot Gap seconds; each shot downs the Interceptor
## with this chance.
@export_range(0.0, 1.0) var protect_interceptor_loss_chance: float = 0.07
@export_range(0.1, 5.0) var protect_drone_shot_gap: float = 0.7
## Interceptors ignore their sortie time in the round and fly home when it ends.
@export var protect_interceptors_stay_out: bool = false
## Labels that would sit on top of another label move down a line (or are left out),
## so bunched-up dogfights stay readable. Civilian ship labels always show.
@export var protect_label_declutter: bool = false
@export_subgroup("Smarter Ships 1.2.9")
## How fast large civilian ships drift away from attackers (0 = they stay put).
@export_range(0.0, 0.1) var civilian_large_evade_speed: float = 0.0
## Self-repair: after Repair Delay seconds with no Attack Drone attacking, a ship regains
## Repair Rate of its hull per second, up to Repair Cap.
@export var civilian_self_repair: bool = false
@export_range(0.0, 20.0) var civilian_repair_delay: float = 3.0
## 1.0.7.2: the console scene sets 0.02 (half the 1.2.9 speed).
@export_range(0.0, 0.5) var civilian_repair_rate: float = 0.04
@export_range(0.0, 1.0) var civilian_repair_cap: float = 0.75
@export_subgroup("Repair Tender 1.2.9")
## A bonus Gunship that flies to the most damaged ship and repairs it (up to 100%),
## then the next. From Gunship Set on (any set on Hard), in rounds with at least
## Gunship Challenges challenges, with Gunship Chance.
@export var protect_repair_tender: bool = false
@export_range(1, 20) var protect_gunship_from_set: int = 3
@export_range(0, 3) var protect_gunship_min_challenges: int = 2
@export_range(0.0, 1.0) var protect_gunship_chance: float = 0.5
## 0.1.2: the chance on Hard (any set, with enough challenges). 1.0 = every such round.
@export_range(0.0, 1.0) var protect_hard_gunship_chance: float = 1.0
@export_range(0.0, 0.5) var protect_gunship_repair_rate: float = 0.08
## 0.1.2 (Normal only). Normal Interceptor Share: total Interceptor launches in the round as a
## share of the Attack Drones, rounded up; the patrol Interceptor and lost Interceptors count
## (1.0 = one per Attack Drone, as 1.2.9).
@export_range(0.1, 1.0) var protect_normal_interceptor_share: float = 0.5
## When on, the Fewer Interceptors challenge still holds back launches on top of the share.
## Off (0.1.2): the challenge can still be drawn but has no effect on Normal.
@export var protect_normal_fewer_on_top: bool = false
## Normal Gunship Patch: the repair Gunship gives each ship one patch of this much hull
## (0.25 = +25%), then moves on. 0 = repair to 100% as in 1.2.9.
@export_range(0.0, 1.0) var protect_normal_gunship_patch: float = 0.25
## 0.1.2 (Hard): the same three rules for Hard. Hard Interceptor Share 0.5 = half as many
## Interceptor launches as Attack Drones (1.0 = one per Attack Drone, as before).
@export_range(0.1, 1.0) var protect_hard_interceptor_share: float = 0.5
## When on, the Fewer Interceptors challenge still holds back launches on top of the share.
@export var protect_hard_fewer_on_top: bool = false
## Hard Gunship Patch: one patch of this much hull per ship (0 = repair to 100%).
@export_range(0.0, 1.0) var protect_hard_gunship_patch: float = 0.25
## 0.1.2 (all difficulties): how far the civilian ships start from the centre of the
## scope, as a multiple of the 1.2.9 layout (1.0 = as before; ships always stay inside
## the scope outline).
@export_range(0.5, 2.0) var protect_fleet_spread: float = 1.6
@export_subgroup("Smart Drones 1.0.7")
## 1.0.7 Protect the convoy: Attack Drones jump in spread out and each goes after its own
## support ship. When an Interceptor chases one, it weaves, speeds up, switches to a ship
## away from the chaser and fires rapid bursts back, while still hurting ships in range.
## Off = the 1.0.6 round (Dogfights rules). The console scene turns it on.
@export var protect_smart_drones: bool = false
## How strongly a drone avoids a ship another drone already attacks (bigger = more spread).
@export_range(0.0, 3.0) var protect_split_claim_pull: float = 1.4
## Drones keep at least this far apart (scope radii; 0 = no spacing).
@export_range(0.0, 0.4) var protect_drone_separation: float = 0.13
## A chased drone flies this much faster and weaves this wide.
@export_range(1.0, 2.0) var protect_evade_speed_factor: float = 1.25
@export_range(0.0, 0.2) var protect_evade_weave: float = 0.06
## Share of normal ship damage a chased drone still does while it evades.
@export_range(0.0, 1.0) var protect_evade_damage_factor: float = 0.75
## A chased drone fires a burst at the chaser when it is this close, every Burst Gap
## seconds; each burst downs the Interceptor with Burst Loss Chance.
@export_range(0.05, 0.4) var protect_return_fire_range: float = 0.16
@export_range(0.3, 5.0) var protect_burst_gap: float = 1.5
@export_range(1, 8) var protect_burst_rounds: int = 5
@export_range(0.0, 1.0) var protect_burst_loss_chance: float = 0.06
## Seconds between new-ship choices while chased.
@export_range(0.5, 10.0) var protect_retarget_seconds: float = 2.5
## Short gunfire lines for drone bursts and Interceptor hits in the round.
@export var protect_tracers: bool = false
@export var protect_tracer_color := Color(1.0, 0.86, 0.45)
@export var protect_drone_tracer_color := Color(1.0, 0.42, 0.36)
@export_subgroup("Smart Repair Tender 1.0.7")
## 1.0.7: the repair tender flies faster and every Retarget seconds re-picks the ship that
## needs it most: ships under attack (or with a Breacher on them) and low on hull first,
## skipping ships it cannot reach before they are lost. It switches only when the new ship
## is clearly more urgent (Switch Margin), so it does not flip back and forth.
@export var protect_tender_smart: bool = false
## Flying speed in scope radii per second (Attack Drones fly 0.07).
@export_range(0.02, 0.3) var protect_tender_speed: float = 0.07
@export_range(0.2, 5.0) var protect_tender_retarget_seconds: float = 0.75
@export_range(0.0, 1.0) var protect_tender_switch_margin: float = 0.25
## Where the tender starts: 0 = beside your ship (as before), 1 = jumps in beside the convoy.
@export var protect_tender_jump_in: bool = false
## Ships above this hull that are not under attack are left alone (no long trips for a scratch).
@export_range(0.5, 1.0) var protect_tender_ignore_above: float = 0.9
@export_subgroup("Repair Tender 1.0.7.2")
## 1.0.7.2: in a round that has a tender, it waits on your ship and launches the first
## time any support ship has lost more than Launch Damage of its hull.
@export var protect_tender_launch_when_hit: bool = false
@export_range(0.0, 0.5) var protect_tender_launch_damage: float = 0.04
## 1.0.7.2: with no ship to repair, the tender waits near the convoy and the fight
## instead of flying back to your ship.
@export var protect_tender_stay_near: bool = false
## 1.0.7.2: Attack Drones attacking close to the tender damage it as fast as they damage
## the biggest support ship. Destroyed = gone for the rest of the round.
@export var protect_tender_hull: bool = false
## 1.0.7.2: after the round a surviving tender flies home and lands on your ship.
@export var protect_tender_lands: bool = false
## 1.0.7.2: top of the Protect the convoy result box, in scope radii from the centre
## (negative = above the centre). 0.22 = the 1.0.7.1 position.
@export_range(-0.95, 0.8) var protect_result_offset: float = 0.22

@export_subgroup("Convoy Round End 1.0.7")
## 1.0.7: off = no time limit. The round ends when every Attack Drone and Breacher is
## destroyed, every support ship is lost, or (below) every Interceptor is lost.
@export var protect_timer_end: bool = true
## With the time limit off, a hidden safety limit still ends a stuck round (seconds).
@export_range(60.0, 900.0) var protect_safety_seconds: float = 300.0
## 1.0.7: when every Interceptor is lost and none are left to launch, the convoy has no
## defense: the round ends as a total loss (every support ship lost, no bonus).
@export var protect_interceptors_lost_end: bool = false
@export_subgroup("Convoy Breacher 1.0.7")
## 1.0.7: Breachers join the round. Each jumps in partway through, flies to a support ship,
## latches on and drains its hull until an Interceptor destroys it. Off = no Breacher.
@export var protect_breachers: bool = false
## Breachers per round (Hard adds Hard Extra from set 2 on).
@export_range(0, 3) var protect_breacher_count: int = 1
@export_range(0, 3) var hard_protect_breacher_extra: int = 1
## Seconds into the round before each Breacher jumps in (random in this range).
@export_range(0.0, 60.0) var protect_breacher_delay_min: float = 8.0
@export_range(0.0, 60.0) var protect_breacher_delay_max: float = 16.0
@export_range(0.01, 0.2) var protect_breacher_speed: float = 0.085
## Seconds one latched Breacher alone takes to drain a full-hull ship on Normal
## (Easy x1.3, Hard x0.75; ship toughness applies).
@export_range(4.0, 120.0) var protect_breacher_drain_seconds: float = 26.0
## Interceptor hits a Breacher takes before it is destroyed.
@export_range(1, 20) var protect_breacher_hits: int = 6
@export_subgroup("Convoy Sounds 1.0.7")
## Rapid-fire burst for drone bursts and Interceptor hits, a clamp when a Breacher latches
## on, and a pulsing drain hum while one is attached. Round only.
@export var protect_convoy_sounds: bool = false
@export_range(-40.0, 0.0) var protect_rapid_fire_volume_db: float = -20.0
@export_range(-40.0, 0.0) var protect_breacher_latch_volume_db: float = -12.0
@export_range(-40.0, 0.0) var protect_breacher_drain_volume_db: float = -18.0

@export_group("Siege Ship")
@export var siege_enabled: bool = true
## Never appears before this wave. Only one can be on screen at a time.
@export_range(1, 10) var siege_first_wave: int = 2
## Every this many seconds there is a Spawn Chance that one arrives.
@export_range(5.0, 120.0) var siege_check_seconds: float = 20.0
@export_range(0.0, 1.0) var siege_spawn_chance: float = 0.25
## Quiet period after one is destroyed before another can arrive.
@export_range(0.0, 600.0) var siege_cooldown_seconds: float = 90.0
## Hit points in ship-missile hits (a Enemy Carrier has 6). Gunship missiles do half.
## Lowered from 16 now that it crosses the scope and can escape.
@export_range(4, 60) var siege_hit_points: int = 10
@export_range(0, 20000) var siege_points: int = 2500
@export_range(1, 8) var siege_barrage_missiles: int = 3
## Seconds between missiles inside one barrage (timed, not all at once).
@export_range(0.1, 3.0) var siege_barrage_spacing: float = 1.0
## Seconds from the start of one barrage to the start of the next. Shortened by
## the wave like Enemy Carrier launches, and always shorter than the Enemy Carrier interval.
@export_range(3.0, 60.0) var siege_barrage_interval: float = 8.0
@export_range(1.0, 30.0) var siege_first_barrage_delay: float = 3.0
## How far apart (scope radii, left/right) barrage missiles fan out on the way in.
@export_range(0.0, 1.0) var siege_missile_spread: float = 0.6
## Hull damage per Siege Ship missile (a Enemy Carrier missile does Missile Damage, 10).
@export_range(1.0, 50.0) var siege_missile_damage: float = 5.0
## Crossing speed in scope radii per second (about 65 seconds edge to edge).
@export_range(0.01, 0.15) var siege_speed: float = 0.03
## Height band of its crossing path (scope radii above the center).
@export var siege_lane := Vector2(0.05, 0.22)
## Later waves: chance per check rises by this much each wave, up to Max Chance...
@export_range(0.0, 0.3) var siege_chance_step: float = 0.05
@export_range(0.0, 1.0) var siege_max_chance: float = 0.6
## ...and the quiet period shrinks by this many seconds each wave, down to Min Cooldown.
@export_range(0.0, 60.0) var siege_cooldown_step: float = 10.0
@export_range(0.0, 300.0) var siege_min_cooldown: float = 40.0
## Interceptors may attack the Siege Ship (never Enemy Carriers): damage per hit and seconds between hits per Interceptor.
@export_range(0.05, 1.0) var interceptor_siege_damage: float = 0.5
@export_range(0.5, 6.0) var interceptor_siege_hit_interval: float = 2.0
@export_range(0.8, 2.0) var siege_icon_scale: float = 1.45
## Its arrival alert is the approved alert played twice, slower and deeper.
@export_range(-40.0, 0.0) var siege_alert_volume_db: float = -5.0
@export_range(0.5, 1.0) var siege_alert_speed: float = 0.8

@export_group("Firewall")
## FIREWALL slows a Breacher hack (and its hull drain) while deployed.
## It can be deployed only while a Breacher is hacking or draining.
@export var firewall_enabled: bool = true
## Hack runs at this fraction of normal speed while the firewall is up (0.25 = four times slower).
@export_range(0.0, 1.0) var firewall_slow_factor: float = 0.25
## Seconds of use from full to empty (used up quickly).
@export_range(1.0, 15.0) var firewall_seconds: float = 4.0
## Seconds to recharge from empty to full (faster than the Defense Shield's 18).
@export_range(2.0, 60.0) var firewall_recharge_seconds: float = 8.0
@export_range(0.0, 5.0) var firewall_recharge_delay: float = 0.5
## Minimum charge needed to deploy it again after it runs dry.
@export_range(0.0, 80.0) var firewall_restart_percent: float = 25.0
@export_range(-40.0, 0.0) var firewall_volume_db: float = -12.0

@export_group("Difficulty")
## Chosen in the gear Settings panel. A change starts with the next battle (Retry / New Battle).
## Normal plays exactly as before; Easy and Hard multiply the values below.
@export_enum("Easy", "Normal", "Hard") var difficulty: int = 1
## Enemy toughness: Breacher, Enemy Carrier and Siege Ship hits to destroy (Attack Drones stay 1 hit).
@export_range(0.3, 1.0) var easy_toughness: float = 0.67
@export_range(1.0, 3.0) var hard_toughness: float = 1.34
## Attack frequency: Attack Drone launches, missiles, nukes, flak, Breachers and barrages.
@export_range(0.3, 1.0) var easy_attack_rate: float = 0.75
@export_range(1.0, 3.0) var hard_attack_rate: float = 1.3
## Damage from enemy missiles and nukes.
@export_range(0.3, 1.0) var easy_damage: float = 0.75
@export_range(1.0, 3.0) var hard_damage: float = 1.25
## How fast a Breacher hack completes and drains the hull.
@export_range(0.3, 1.0) var easy_hack_speed: float = 0.7
@export_range(1.0, 3.0) var hard_hack_speed: float = 1.3
## Wave length: longer waves escalate more slowly.
@export_range(1.0, 3.0) var easy_wave_length: float = 1.25
@export_range(0.3, 1.0) var hard_wave_length: float = 0.8
## Defense Shield recharge time: Easy recharges faster, Hard slower (24 s on Normal).
@export_range(0.3, 1.0) var easy_battery_recharge: float = 0.8
@export_range(1.0, 3.0) var hard_battery_recharge: float = 1.3
## Enemy missile speed on each level (1.0 = the 1.03 speed). Easy keeps the old speed.
@export_range(0.5, 3.0) var easy_missile_speed: float = 1.0
@export_range(0.5, 3.0) var normal_missile_speed: float = 1.1
@export_range(0.5, 3.0) var hard_missile_speed: float = 1.6
## Nuclear missile speed on each level (1.0 = the 1.03 speed).
## 1.2.7: Easy 1.0 -> 1.1, Normal 1.1 -> 1.25, Hard 1.6 -> 1.45 (field-tested).
@export_range(0.5, 3.0) var easy_nuke_speed: float = 1.1
@export_range(0.5, 3.0) var normal_nuke_speed: float = 1.25
@export_range(0.5, 3.0) var hard_nuke_speed: float = 1.45
## 1.2.7: Attack Drone and Breacher movement speed on Hard (1.0 = the same as Easy and Normal).
## Attack Drones: approach, patrol, chase and return. Breachers: the run to the ship and the
## way home. Protect the fleet Attack Drones keep Protect Attack Drone Speed.
@export_range(1.0, 2.0) var hard_drone_speed: float = 1.1
@export_range(1.0, 2.0) var hard_breacher_speed: float = 1.1
## Score multiplier for each difficulty.
@export_range(0.1, 1.0) var easy_score_multiplier: float = 0.75
@export_range(1.0, 5.0) var hard_score_multiplier: float = 1.5

@export_group("Automation")
## Fires the Defense Shield by itself when standard missiles enter its zone.
@export var auto_defense_battery: bool = false
## Raises the Firewall by itself when a Breacher starts hacking.
@export var auto_firewall: bool = false
## Score reduction for each auto option that is on (0.10 = 10% fewer points).
@export_range(0.0, 0.5) var auto_score_penalty: float = 0.10
## Once an auto option switches on, it stays on at least this long (no quick flicker).
@export_range(0.0, 3.0) var auto_min_engage_seconds: float = 0.5
## Launches Interceptors by itself while enemy fighters are on the scope.
@export var auto_launch_interceptors: bool = false
## Launches Gunships by itself for nukes, and keeps one Gunship out against Enemy Carriers.
@export var auto_launch_gunships: bool = false
## 1.1.0: with Auto Launch Gunships on and at least this many nukes on screen, every
## available Gunship launches at once (the launch cooldown is skipped; the landing
## pause still applies). 0 turns this off.
@export_range(0, 6) var auto_all_gunships_nukes: int = 2
## Jumps by itself when the hull falls below the level below (costs the usual JUMP points).
@export var auto_jump: bool = false
@export_range(1.0, 50.0) var auto_jump_hull_percent: float = 10.0
## Uses a Rapid Repair charge by itself when the hull is at or below this level.
@export var auto_rapid_repair: bool = false
@export_range(10.0, 90.0) var auto_repair_hull_percent: float = 50.0

@export_group("JUMP Flash")
## Blue-white wipe across the RADAR scope and a brief screen flash when JUMP engages.
@export var jump_flash_enabled: bool = true
@export_range(0.3, 3.0) var jump_flash_seconds: float = 1.1
## Strength of the full-screen blue-white flash (0 = wipe only). Screen Flash Enabled also applies.
@export_range(0.0, 0.6) var jump_screen_flash_strength: float = 0.35

@export_group("Explosions")
## Small flash and boom when a missile is destroyed; larger explosion for a nuke.
@export var explosion_effects_enabled: bool = true
@export_range(0.1, 1.0) var missile_flash_seconds: float = 0.3
@export_range(0.3, 3.0) var missile_flash_size: float = 1.0
@export_range(0.3, 2.0) var nuke_explosion_seconds: float = 0.8
@export_range(0.3, 3.0) var nuke_explosion_size: float = 1.0
## Brief full-screen flash when a nuke explodes (one flash, no strobing).
@export var screen_flash_enabled: bool = true
## Flash strength when a Gunship destroys a nuke in flight (0 = off, 0.6 = strongest).
@export_range(0.0, 0.6) var nuke_screen_flash_strength: float = 0.28
## Flash strength when a nuke hits the ship.
@export_range(0.0, 0.6) var nuke_impact_flash_strength: float = 0.42
@export_range(0.1, 1.0) var screen_flash_seconds: float = 0.35
## Destruction sounds (Effects bus, below the alert levels).
@export_range(-40.0, 0.0) var missile_boom_volume_db: float = -15.0
@export_range(-40.0, 0.0) var nuke_boom_volume_db: float = -9.0
## Several destructions inside this time make only one boom (no loud stacking).
@export_range(0.0, 0.5) var boom_min_gap_seconds: float = 0.12
## Destroyed Attack Drones, Breachers, Interceptors and Gunships: a small burst and short boom, no screen flash.
@export var craft_explosions_enabled: bool = true
@export_range(0.1, 1.0) var craft_explosion_seconds: float = 0.4
@export_range(0.3, 3.0) var craft_explosion_size: float = 1.0
## Breachers are this much bigger than Attack Drones.
@export_range(1.0, 2.5) var heavy_explosion_scale: float = 1.4
@export var enemy_craft_color := Color(1.0, 0.62, 0.22)
## Lost Interceptors and Gunships burst in this colour so own losses are easy to spot.
@export var own_craft_color := Color(0.62, 1.0, 0.78)
@export_range(-40.0, 0.0) var craft_boom_volume_db: float = -19.0
@export_range(-40.0, 0.0) var heavy_boom_volume_db: float = -16.0
## Destroyed Enemy Carriers and Siege Ships: a large explosion, deep boom and one screen flash.
@export_range(0.5, 3.0) var capital_explosion_seconds: float = 1.4
@export_range(0.3, 3.0) var capital_explosion_size: float = 1.0
@export_range(0.0, 0.6) var capital_screen_flash_strength: float = 0.32
@export_range(-40.0, 0.0) var capital_boom_volume_db: float = -7.0

@export_group("Nuclear Interception")
## Gunship hits needed to destroy a nuclear missile (difficulty toughness applies).
@export_range(1, 12) var nuclear_hit_points: int = 6
## Time between a Gunship's hits on a nuke, so it has to chase it.
@export_range(0.1, 2.0) var gunship_nuke_hit_interval: float = 0.7
## 1.2.1: Interceptor hits needed to destroy a Attack Drone (1 = the pre-1.2.1 one-pass kill).
@export_range(1, 5) var drone_interceptor_hits: int = 2
## 1.2.1: time between one Interceptor's hits on the same Attack Drone.
@export_range(0.1, 2.0) var drone_interceptor_hit_interval: float = 0.5

@export_group("Bonus Features")
## 1.05: two ship missiles per volley once enough points are earned in a battle.
## JUMP costs do not take it away; Retry or a new battle starts over.
@export var double_missile_bonus: bool = true
@export_range(1000, 200000, 500) var easy_double_missile_points: int = 15000
@export_range(1000, 200000, 500) var normal_double_missile_points: int = 17500
@export_range(1000, 200000, 500) var hard_double_missile_points: int = 20000
## Short rising chime when the bonus unlocks (Effects bus, below the alerts).
@export_range(-40.0, 0.0) var bonus_chime_volume_db: float = -14.0
## 0.1.2 Rapid Missile bonus on Normal and Hard. Ship missiles fire with a shorter gap
## once enough points are earned. It is never active together with Double Missile:
## when both are earned the player picks one (the console shows the pick prompt).
@export var rapid_missile_bonus: bool = false
@export_range(1000, 200000, 500) var normal_rapid_missile_points: int = 10000
@export_range(1000, 200000, 500) var hard_rapid_missile_points: int = 6000
@export_range(2.0, 20.0) var normal_rapid_missile_interval: float = 6.0
@export_range(2.0, 20.0) var hard_rapid_missile_interval: float = 5.0
## 1.0.9: while Rapid Missile is in use, the ship's own missiles fly this much faster
## (1.2 = 20% faster). 1.0 = the 1.0.8 speed. Double Missile and Gunship missiles unchanged.
@export_range(1.0, 2.0) var rapid_missile_speed_factor: float = 1.0
## 0.1.2: once both missile bonuses are earned, the pick is offered again after each
## set of five waves. Off = offered only once, when the second bonus is earned.
@export var missile_bonus_offer_each_set: bool = true
## 0.1.2: when the second missile bonus is earned during a fight, the current bonus
## stays in use and the pick prompt waits until the wave (or Protect the fleet round)
## is cleared. Off = the prompt opens at once, mid-fight. 1.0.6: on by default, and it
## also covers the Bonus Sweep, so the pick is never offered during a battle round.
@export var missile_bonus_pick_after_wave: bool = true
## Status line shown when the pick is held for the end of the round. 1.0.6: names the
## bonus just earned (1.0.5 and earlier named the one already in use).
@export var missile_bonus_wait_line: String = "%s MISSILE EARNED | PICK YOUR BONUS AFTER THIS ROUND"

@export_group("EMP Defense")
## 1.06: USE EMP appears in the middle of the ship while a Breacher hacks and
## a charge is ready. It overloads every hacking Breacher: they shimmer blue,
## stop hacking and fly back to their Enemy Carrier for repairs (not destroyed, no points).
@export var emp_enabled: bool = true
## One EMP charge per this many earned points (JUMP costs do not take it away).
@export_range(1000, 50000, 500) var emp_points_per_charge: int = 5000
## Most charges held at once.
@export_range(1, 5) var emp_max_charges: int = 2
## How long overloaded Breachers shimmer before they turn for home.
@export_range(0.2, 4.0) var emp_shimmer_seconds: float = 1.0
@export var emp_color := Color(0.35, 0.78, 1.0)
## Electric zap when the EMP fires (Effects bus).
@export_range(-40.0, 0.0) var emp_zap_volume_db: float = -10.0
## 1.07: the EMP is offered only this many seconds after the Firewall has run out
## (or cannot be raised) during a hack. The Firewall is always the first answer.
@export_range(0.0, 10.0) var emp_delay_after_firewall: float = 2.0

@export_group("Rapid Repair Feedback")
## 1.06: a rising recharge sound plays while a Rapid Repair runs.
@export var repair_sound_enabled: bool = true
@export_range(-40.0, 0.0) var repair_sound_volume_db: float = -16.0
## The ship outline pulses brighter green while a Rapid Repair runs.
@export var repair_flash_enabled: bool = true
@export_range(0.5, 6.0) var repair_flash_hz: float = 2.0

@export_group("Interceptor Squadrons")
## Interceptors flying close together show as one Interceptor Squadron icon (display only).
@export var interceptor_squadrons_enabled: bool = true
## Interceptors closer than this join a squadron.
@export_range(0.02, 0.2) var squadron_join_distance: float = 0.075
## A Interceptor further than this from its squadron's centre splits off (larger = steadier).
## 1.07: 0.06 (was 0.12), so Interceptors that break off to fight show as separate icons.
@export_range(0.04, 0.3) var squadron_split_distance: float = 0.06
## 1.07: with several enemies about, Interceptors spread over different targets, then fly
## back and rejoin one patrol formation when the area is clear.
@export var squadrons_split_to_engage: bool = true
## Interceptors allowed on one tough target (Breacher, Siege Ship) before the rest look elsewhere.
@export_range(1, 6) var max_interceptors_per_tough_target: int = 2
## 1.1.0 (Stephen 2026-10-24): while no Gunship is out (a returning Gunship does not
## count), a Breacher hacking or draining the ship is a priority target for Interceptors,
## ahead of Attack Drones and missiles (and of frozen drones after a PULSE BOMB). Up to
## Max Interceptors Per Tough Target go after each one. Off = the 1.0.9 rule.
@export var interceptors_hacking_breachers_first: bool = true
## How strongly a Interceptor avoids a Attack Drone or missile a squadron mate already chases (1 = no spreading).
@export_range(1.0, 10.0) var squadron_spread_penalty: float = 3.0
## Gap between Interceptors in the shared patrol formation (keep under the join distance).
@export_range(0.01, 0.07) var formation_spacing: float = 0.02
## 1.08: while a Siege Ship is on the scope, this many Interceptors break off from the
## squadron to attack it (0 = the 1.07 behavior, only when nothing else is left).
## If one is lost or returns, another takes its place.
@export_range(0, 6) var interceptors_on_siege_ship: int = 1

@export_group("Missile Visibility")
## 1.07: enemy missiles pulse so the eye picks them out; they never fully vanish.
@export var enemy_missile_pulse: bool = true
@export_range(0.5, 4.0) var enemy_missile_pulse_hz: float = 2.0
## Lowest brightness of the pulse (1.0 = no pulse).
@export_range(0.1, 1.0) var enemy_missile_pulse_min: float = 0.35

@export_group("Fighter Losses")
## Interceptors and Gunships can be shot down in battle. They are tougher than Attack Drones (1) and Breachers (3).
@export var fighter_losses_enabled: bool = true
## Interceptors are lighter (fewer hit points) but nimble: Interceptor Evasion Chance dodges some hits.
## Gunships are armored: more hit points, plus Gunship Evasion Chance against fire.
@export_range(1, 10) var interceptor_hit_points: int = 2
@export_range(1, 12) var gunship_hit_points: int = 7
@export_range(0.0, 0.95) var interceptor_evasion_chance: float = 0.2
## Chance each Attack Drone attack on an active Interceptor or Gunship scores a hit (before evasion).
@export_range(0.0, 1.0) var drone_hit_chance: float = 0.5
## Points lost when one of our fighters is destroyed (score never drops below zero;
## earned progress toward bonus repairs is kept).
@export_range(0, 5000) var interceptor_loss_points: int = 200
@export_range(0, 5000) var gunship_loss_points: int = 400

@export_group("Interceptor Launch")
@export_range(1, 12) var max_interceptors: int = 6
@export_range(1, 4) var interceptors_per_launch: int = 2
## 1.0.5: after a launch, Interceptors that were already ready wait this long before the
## next launch (ships still counting down keep their own countdown).
@export_range(1.0, 15.0) var launch_cooldown_seconds: float = 4.0
## 1.0.5: after an Interceptor lands, that Interceptor waits this long before it is ready
## again. Each Interceptor has its own wait; a landing never restarts another one's wait.
@export_range(0.0, 20.0) var interceptor_recovery_seconds: float = 3.0
@export_range(10.0, 120.0) var sortie_seconds: float = 45.0

@export_group("Returning Flights")
## Attack Drones return to their Enemy Carrier to refuel and rearm after this long.
@export_range(15.0, 120.0) var drone_sortie_seconds: float = 40.0
## Returning ships fly at this fraction of normal speed (low on fuel).
@export_range(0.4, 1.0) var returning_speed_factor: float = 0.8
## Lighter tint and slow flash for returning ships.
@export_range(0.0, 0.8) var returning_lighten: float = 0.45
@export_range(0.2, 3.0) var returning_flash_hz: float = 0.8
## Attack Drones hunt returning Interceptors within this range.
@export_range(0.1, 0.6) var drone_attack_range: float = 0.30
## Chance a Attack Drone reaching a returning Interceptor destroys it (each attack).
@export_range(0.0, 1.0) var returning_interceptor_loss_chance: float = 0.5
@export_range(0.5, 5.0) var drone_attack_cooldown: float = 1.5
## Returning Gunships evade Enemy Carrier flak less often.
@export_range(0.0, 0.95) var returning_gunship_evasion_chance: float = 0.35
## Breachers flash this fast while hacking or draining.
@export_range(2.0, 12.0) var hacking_flash_hz: float = 6.0
@export var launch_sound_enabled: bool = true
@export_range(-40.0, 0.0) var launch_volume_db: float = -12.0

@export_group("Depth")
@export_range(2.0, 6.0) var perspective_distance: float = 2.8
@export_range(0.0, 1.0) var depth_strength: float = 0.25

@export_group("Keep Play In Wedge")
## 1.2.4: contacts are kept inside the scope outline drawn by the console frame
## (the arc over the top and the V down to the button bar). Off = the 1.2.3 open scope.
## A contact that starts outside the outline flies in as before and is kept in once inside.
@export var keep_play_in_wedge: bool = false
## How far inside the outline contact centres stay, in sphere radii (0.06 is about 19 px).
@export_range(0.0, 0.2) var wedge_margin: float = 0.06

@export_group("Contact Colors")
@export var friendly_color := Color(0.3, 1.0, 0.55)
@export var hostile_color := Color(1.0, 0.22, 0.28)
@export var unknown_color := Color(1.0, 0.73, 0.22)

@export_group("Arrival Audio")
@export var arrival_sound_enabled: bool = true
@export_range(-40.0, 0.0) var arrival_volume_db: float = -8.0

@export_group("Stealth Interceptor")
## 1.09: a special Interceptor with two nuclear missiles, launched by the STEALTH WEAPON
## button on the top nacelle. Never offered on Easy.
@export var stealth_interceptor_enabled: bool = true
## Large ships (Enemy Carriers plus the Siege Ship) needed on screen to offer it.
@export_range(1, 6) var stealth_min_large_ships: int = 3
## Flight speed compared with a normal Interceptor.
@export_range(1.0, 4.0) var stealth_speed_factor: float = 2.2
@export_range(1, 4) var stealth_nukes: int = 2
## Share of a large ship's full strength each nuke removes (0.5 = 3 of a Enemy Carrier's 6 hits).
@export_range(0.1, 1.0) var stealth_nuke_strength: float = 0.5
## Seconds between its two shots.
@export_range(1.0, 15.0) var stealth_shot_seconds: float = 4.0
## Distance from the target where it fires.
@export_range(0.1, 0.8) var stealth_fire_range: float = 0.35
@export_range(0.1, 1.5) var stealth_nuke_speed: float = 0.5
## Rearm time after it lands safely, and the rebuild time after it is destroyed
## (no message or countdown is shown for either).
@export_range(10.0, 600.0) var stealth_rearm_seconds: float = 60.0
@export_range(30.0, 900.0) var stealth_rebuild_normal_seconds: float = 180.0
@export_range(30.0, 900.0) var stealth_rebuild_hard_seconds: float = 240.0
## Its RADAR tag blinks this fast until it fires (then enemies can see it).
@export_range(2.0, 12.0) var stealth_blink_hz: float = 6.0
@export var stealth_ready_sound_enabled: bool = true
@export_range(-40.0, 0.0) var stealth_ready_volume_db: float = -12.0
## 1.1.0: once it has fired, every Attack Drone within this distance turns on it.
@export_range(0.1, 1.0) var stealth_focus_range: float = 0.40
## How far each Attack Drone chases it before giving up and going back to its job.
@export_range(0.05, 1.0) var stealth_pursuit_distance: float = 0.25
## Attack Drones shoot at it from this distance, once every Stealth Shot Interval each.
@export_range(0.05, 0.6) var stealth_shot_range: float = 0.30
@export_range(0.3, 5.0) var stealth_shot_interval: float = 1.5
## Chance each Attack Drone shot destroys it (one hit is enough). Tuned so about one run
## in four is lost in typical Normal and Hard battles.
@export_range(0.0, 1.0) var stealth_hit_chance: float = 0.045

@export_group("Pulse Bomb")
## 1.1.0: the Stealth Interceptor can carry one PULSE BOMB instead of its 2 nukes, while a
## charge earned by score is held (off = the 1.0.9 Stealth Interceptor).
@export var pulse_bomb_enabled: bool = true
## Stephen 2026-10-25: one PULSE BOMB charge per score level (earned points), Normal
## every 40,000 and Hard every 50,000 (never on Easy). At most 1 held; a charge earned
## while one is held is lost. While a charge is held, the next Stealth launch carries it.
@export_range(1000, 500000, 1000) var pulse_bomb_normal_points: int = 40000
@export_range(1000, 500000, 1000) var pulse_bomb_hard_points: int = 50000
@export_range(1, 3) var pulse_bomb_max_charges: int = 1
## Stephen 2026-10-25: frozen enemies also lose this share of their CURRENT strength
## each second (Attack Drones and Breachers too). It never destroys a ship by itself.
@export_range(0.0, 0.5) var pulse_drain_per_second: float = 0.05
## Stephen 2026-10-25: frozen Attack Drones instead lose this share of their FULL
## strength each second, and the drain can destroy them (normal points). At 10% a
## drone left alone is destroyed at the end of the 10-second freeze; one already hit
## goes sooner. Breachers keep the drain above and are never destroyed by it.
@export_range(0.0, 0.5) var pulse_drone_drain_per_second: float = 0.10
var pulse_drain_kills: int = 0
## Frozen enemies take this many times the normal damage.
@export_range(1.0, 4.0) var pulse_frozen_damage_factor: float = 2.0
## Stephen 2026-10-25: Interceptors fly 1.5 times faster while
## chasing a frozen target, and each one goes after a different frozen drone (they
## double up only when there are more Interceptors than frozen drones). Frozen
## drones stay ahead of incoming missiles (missiles first = off).
@export_range(1.0, 3.0) var pulse_chase_speed_factor: float = 1.5
@export var pulse_chase_spread: bool = true
@export var pulse_chase_missiles_first: bool = false
@export_range(1.0, 30.0) var pulse_freeze_seconds: float = 10.0
## Area size, in scope units (Stephen 2026-10-25: the large area, 0.60).
@export_range(0.1, 1.0) var pulse_radius: float = 0.60
## Aim: 0 = nearest Enemy Carrier, 1 = the spot that catches the most large ships
## (Stephen 2026-10-25: the most large ships).
@export_range(0, 1) var pulse_aim: int = 1
## Seconds the bomb sits armed (blinking) before it goes off.
@export_range(0.0, 4.0) var pulse_fuse_seconds: float = 1.0
@export var pulse_color := Color(0.62, 0.9, 1.0)
## Stephen 2026-10-25: a nuclear missile inside the area when the bomb goes off is not
## frozen but flies at this share of its normal speed until it hits or is destroyed
## (0.6 = 40% slower; 1 = not slowed). It shimmers ice-blue like frozen enemies.
@export_range(0.1, 1.0) var pulse_nuke_speed_factor: float = 0.6
## Stephen 2026-10-25: Interceptors go after a hacking or draining Breacher before
## frozen Attack Drones (with the Hacking Breachers First rule on).

var pulse_charges: int = 0
var pulse_drained: float = 0.0
var pulse_awards_earned: int = 0
var pulse_charges_lost: int = 0
var pulse_bombs: Array[Dictionary] = []
var pulse_fields: Array[Dictionary] = []
var pulse_detonations: int = 0
var pulse_frozen_large: int = 0
var pulse_frozen_fighters: int = 0
var pulse_breachers_sent_home: int = 0
## Nuclear missiles slowed by a PULSE BOMB, and seconds left of the latest freeze.
var pulse_nukes_slowed: int = 0
var pulse_freeze_left: float = 0.0

var contacts: Array[Dictionary] = []
var pending: Array[Dictionary] = []
var next_id: int = 1
var beep_count: int = 0
var spawn_count: int = 0
var rng := RandomNumberGenerator.new()
var arrival_player: AudioStreamPlayer
var spawn_countdown: float = 0.8
var wave_countdown: float = 9.0
var launch_player: AudioStreamPlayer
var launch_sound_count: int = 0
var intercepted_count: int = 0
var impacts: Array[Dictionary] = []
var hull: float = 100.0
var prox_active: bool = false
var jump_recharge_remaining: float = 0.0
var safe_remaining: float = 0.0
var missile_hits: int = 0
var prox_kills: int = 0
var missile_intercepts: int = 0
var jumps_used: int = 0
var status_message: String = "DEFEND THE AEGIS | LAUNCH INTERCEPTORS WHEN ATTACK DRONES APPEAR"
var status_remaining: float = 0.0
var repair_delay_remaining: float = 0.0
var repair_elapsed: float = 0.0
var own_fire_remaining: float = 0.0
var carriers_destroyed: int = 0
var own_missile_hits: int = 0
var identification_count: int = 0
var klaxon_count: int = 0
var klaxon_player: AudioStreamPlayer
## Difficulty used by the current battle (set from difficulty at each new battle).
var active_difficulty: int = 1
var auto_battery_started: bool = false
var auto_battery_since: float = 0.0
var auto_firewall_started: bool = false
var auto_firewall_since: float = 0.0
var explosions: Array[Dictionary] = []
var explosions_made: int = 0
var screen_flash_remaining: float = 0.0
var screen_flash_peak: float = 0.0
var last_boom := {"missile": -INF, "nuke": -INF, "craft": -INF, "heavy": -INF, "capital": -INF}
var booms_played := {"missile": 0, "nuke": 0, "craft": 0, "heavy": 0, "capital": 0}
var nuke_hits_landed: int = 0
## 1.2.8: nukes the battery shot down, nukes it missed, and the splash damage taken.
var battery_nuke_kills: int = 0
var battery_nuke_misses: int = 0
var battery_splash_damage: float = 0.0
var interceptor_squadrons: Array = []
## 1.07: targets claimed by Interceptors this frame, the shared patrol angle and missile retargets.
var interceptor_claims := {}
var squadron_patrol_angle := 0.0
var missile_retargets := 0
## 1.08: JUMP taken offline by a Breacher breach.
var jump_offline: bool = false
## 1.08: enemies destroyed this battle, by kind (saved with a new high score).
var kills: Dictionary = {}
const KILL_KINDS := ["drone", "breacher", "missile", "nuke", "carrier", "siege_ship"]
var jump_offline_count: int = 0
## 1.08: the current recharge is the rebuild after a breach (its own length).
var jump_rebuilding_after_breach: bool = false
var jump_breach_rebuild_total: float = 45.0
## 1.07: when the Firewall became unusable during the current hack (-1 = not), and
## whether the EMP is now offered for this hack.
var firewall_out_since := -1.0
var emp_offer_open := false
var missile_boom_player: AudioStreamPlayer
var nuke_boom_player: AudioStreamPlayer
var craft_boom_player: AudioStreamPlayer
var heavy_boom_player: AudioStreamPlayer
var capital_boom_player: AudioStreamPlayer
var auto_repairs: int = 0
var craft_explosions: int = 0
var capital_explosions: int = 0
var auto_battery_starts: int = 0
var auto_firewall_starts: int = 0
var auto_interceptor_launches: int = 0
var auto_gunship_launches: int = 0
var auto_jumps: int = 0
var jump_flash_remaining: float = 0.0
var klaxon_queue: Array[String] = []
var battery_player: AudioStreamPlayer
var jump_player: AudioStreamPlayer
var nuclear_player: AudioStreamPlayer
var nuclear_beep_player: AudioStreamPlayer
var nuclear_alert_queue: Array[String] = []
var nuclear_alert_contact_id: String = ""
var nuclear_alert_count: int = 0
var nuclear_beep_count: int = 0
var prox_burst_remaining: float = 0.0
var prox_cooldown_remaining: float = 0.0
var nuclear_alarm_remaining: float = 0.0
var battle_time: float = 0.0
## 1.2.4: how many times Keep Play In Wedge moved a contact back inside.
var wedge_corrections: int = 0
var nuclear_launches: int = 0
var nuclear_intercepts: int = 0
var nuclear_hits: int = 0
var gunship_evades: int = 0
var gunships_lost: int = 0
var gunships_returned: int = 0
var interceptors_returned: int = 0
var interceptors_lost: int = 0
var drones_docked: int = 0
var battery_idle: float = 0.0
var gunship_missile_hits: int = 0
var score: int = 0
var scored_contacts: Dictionary = {}
var rapid_repair_used: bool = false
var rapid_repair_remaining: float = 0.0
var rapid_repair_rate: float = 0.0
var repair_charges: int = 1
## 1.1.0: true while Rapid Repair earning is paused at the limit.
var repair_earning_paused: bool = false
## 1.1.0: charges earned at the limit and lost (for the session log and tests).
var repair_charges_lost: int = 0
var earned_points: int = 0
## 1.05 bonus state. Battle time when Double Missile unlocked (-1 = not yet).
var double_missile_unlocked_at: float = -1.0
var rapid_missile_unlocked_at: float = -1.0
## "", "RAPID" or "DOUBLE": the bonus in use once both are earned.
var missile_bonus_pick: String = ""
## 0.1.2: a missile bonus pick prompt is open (the console pauses the battle).
var missile_bonus_offer_open: bool = false
var missile_bonus_offers: int = 0
var missile_bonus_set_offers: int = 0
## 0.1.2: a just-earned pick held for the end of the wave, and how often that happened.
var missile_bonus_offer_waiting: bool = false
var missile_bonus_waits: int = 0
var missile_bonus_switches: int = 0
## Enemy Carriers already picked in the current volley (spread targeting).
var _volley_carrier_ids: Array[String] = []
## 0.1.2 quick pair: seconds until the second missile of the volley (0 = none waiting).
var own_pair_remaining: float = 0.0
var own_pair_launches: int = 0
var bonus_chimes: int = 0
var battery_kill_score: int = 0
var ship_nuke_hits: int = 0
var ship_nuke_kills: int = 0
var bonus_chime_player: AudioStreamPlayer
## 1.06 EMP and repair feedback state.
var emp_charges: int = 0
var emp_awards_earned: int = 0
var emp_uses: int = 0
var emp_heavies_overloaded: int = 0
var emp_heavies_docked: int = 0
var emp_player: AudioStreamPlayer
var repair_sound_player: AudioStreamPlayer
var repair_sounds: int = 0
var repair_bonuses_earned: int = 0
var hit_flash_remaining: float = 0.0
var impact_player: AudioStreamPlayer
var impact_sound_count: int = 0
var breachers_destroyed: int = 0
var wave: int = 1
var siege_alert_player: AudioStreamPlayer
var siege_alert_pending: bool = false
var siege_alert_count: int = 0
var siege_check_remaining: float = 20.0
var siege_cooldown_remaining: float = 0.0
var siege_spawns: int = 0
var sieges_destroyed: int = 0
var siege_barrages: int = 0
var siege_missiles_fired: int = 0
var siege_hits_by: Dictionary = {"ship": 0, "gunship": 0, "interceptor": 0}
var own_volley_count: int = 0
var firewall_active: bool = false
var firewall_charge: float = 4.0
var firewall_idle: float = 0.0
var firewall_uses: int = 0
var firewall_player: AudioStreamPlayer
var sieges_escaped: int = 0
var fighter_points_lost: int = 0
var interceptor_evades: int = 0
var fighter_losses_by := {"drone": 0, "flak": 0, "returning": 0}
## 1.09 Stealth Interceptor state. The cooldown covers both rearming and rebuilding.
var stealth_cooldown_remaining: float = 0.0
var stealth_was_ready: bool = false
var stealth_ready_player: AudioStreamPlayer
var stealth_ready_sounds: int = 0
var stealth_launches: int = 0
var stealth_nukes_fired: int = 0
var stealth_nuke_hits: int = 0
var stealth_lost: int = 0
var stealth_recovered: int = 0
## 1.1.0 state: Attack Drone shots at the Stealth Interceptor, landing pauses and nuke speeds.
var stealth_shots_taken: int = 0
var stealth_pursuits: int = 0
## 1.0.5: one entry per Interceptor / Gunship in the hangar that is not ready yet:
## {"left": seconds, "why": "landing" or "launch"}. Ships in the hangar without an
## entry are ready. (Replaces the shared launch cooldown and landing pause.)
var interceptor_waits: Array[Dictionary] = []
var gunship_waits: Array[Dictionary] = []
var interceptor_recovery_holds: int = 0
var gunship_recovery_holds: int = 0
var auto_all_gunship_launches: int = 0
var nuke_speed_bonuses: Array[float] = []
## 1.2.0 defined-wave state.
var wave_phase: String = "assault"
var wave_next_phase: String = "assault"
var wave_force_spawned: int = 0
var wave_assault_time: float = 0.0
var wave_siege_spawned: bool = false
var wave_rest_remaining: float = 0.0
var wave_inbound_announced: bool = false
var wave_trait: String = ""
var upcoming_trait: String = ""
var set_traits_used: Array[String] = []
var sets_completed: int = 0
var waves_cleared: int = 0
var waves_escaped: int = 0
var wave_bonus_points: int = 0
var last_wave_bonus: int = 0
var last_cleared_wave: int = 0
var last_systems_bonus: String = ""
var last_bonus_label: String = ""
var systems_bonus_counts: Dictionary = {}
var active_boosts: Dictionary = {}
var fighters_jumped_out: int = 0
var rest_jumps: int = 0
var sweep_spawned: int = 0
var sweep_destroyed: int = 0
var sweep_escaped: int = 0
var sweep_timer: float = 0.0
var sweep_groups: int = 0
var sweeps_flown: int = 0
var sweeps_perfect: int = 0
var last_sweep_result: String = ""
var rest_after_sweep: bool = false
## 1.2.2 Protect the fleet state.
var protect_civilians_total: int = 0
var protect_drones_total: int = 0
var protect_drones_spawned: int = 0
var protect_drones_destroyed: int = 0
var protect_drones_escaped: int = 0
var protect_interceptors_launched: int = 0
var protect_elapsed: float = 0.0
var protect_spawn_timer: float = 0.0
var protect_rounds: int = 0
var protect_full_fleets: int = 0
var protect_saved: int = 0
var protect_lost: int = 0
var protect_hull_kept: int = 0
var protect_end_reason: String = ""
var last_protect_bonus: int = 0
var rest_after_protect: bool = false
## 1.2.7: Protect the fleet result (time it appeared, sounds played, auto Interceptor launches in the round).
var protect_result_started: float = -100.0
var protect_result_sound_count: int = 0
var last_protect_result_sound: String = ""
var protect_auto_interceptor_launches: int = 0
var fleet_saved_player: AudioStreamPlayer
var fleet_partial_player: AudioStreamPlayer
var fleet_lost_player: AudioStreamPlayer
var protect_civilian_kinds: Array[String] = []
## 1.2.3: Interceptors lost to Attack Drone return fire this round.
var protect_interceptors_lost_to_fire: int = 0
## 1.2.9 round state: challenges picked, wave groups, Interceptors held back, dogfight and
## repair counters, and sound counters (for the checks).
var protect_challenges: Array[String] = []
var protect_wave_groups: int = 1
var protect_wave_gap: float = 0.0
var protect_group_index: int = 0
var protect_next_group_at: float = 0.0
var protect_short_interceptors: int = 0
var protect_help_timer: float = 0.0
var protect_breakoffs: int = 0
var protect_dogfight_hits: int = 0
var protect_dogfight_interceptors_lost: int = 0
var protect_helps: int = 0
var protect_repaired: float = 0.0
var protect_gunship_repaired: float = 0.0
var protect_gunship_rounds: int = 0
var protect_sound_counts: Dictionary = {}
var protect_boom_size: String = ""
var protect_tick_player: AudioStreamPlayer
var protect_attacked_player: AudioStreamPlayer
var protect_critical_player: AudioStreamPlayer
var protect_medium_boom_player: AudioStreamPlayer
## 1.0.7 Protect the convoy state.
var protect_rng := RandomNumberGenerator.new()
var protect_breachers_total: int = 0
var protect_breachers_spawned: int = 0
var protect_breachers_destroyed: int = 0
var protect_breacher_times: Array[float] = []
var protect_breacher_latches: int = 0
var protect_bursts: int = 0
var protect_burst_losses: int = 0
var protect_evasions: int = 0
var tracers: Array = []
var protect_rapid_player: AudioStreamPlayer
var protect_latch_player: AudioStreamPlayer
var protect_drain_player: AudioStreamPlayer
var protect_last_rapid_at: float = -100.0
var protect_tender_switches: int = 0
## 1.0.7.2: a tender is due this round and waits for the first damaged ship.
var protect_tender_waiting: bool = false
var protect_tender_launches: int = 0
var protect_tenders_lost: int = 0
var protect_tenders_landed: int = 0
## 1.0.7.2: points scored for Attack Drone and Breacher kills this round (kept whatever the outcome).
var protect_kill_points: int = 0
var _protect_label_rects: Array[Rect2] = []
## Extra Interceptors or Gunships still out when their boost ends; the limit tapers as they land.
var interceptor_limit_hold: int = 0
var gunship_limit_hold: int = 0
var action_stations_player: AudioStreamPlayer
var all_clear_player: AudioStreamPlayer
var action_stations_count: int = 0
var all_clear_count: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if random_seed == 0:
		rng.randomize()
	else:
		rng.seed = random_seed
	arrival_player = AudioStreamPlayer.new()
	arrival_player.name = "ContactArrivalAudio"
	arrival_player.stream = make_arrival_sound()
	arrival_player.volume_db = arrival_volume_db
	add_child(arrival_player)
	launch_player = AudioStreamPlayer.new()
	launch_player.name = "InterceptorLaunchAudio"
	launch_player.stream = make_launch_sound()
	launch_player.volume_db = launch_volume_db
	add_child(launch_player)
	klaxon_player = AudioStreamPlayer.new()
	klaxon_player.name = "IdentificationKlaxon"
	klaxon_player.stream = make_klaxon_sound()
	add_child(klaxon_player)
	battery_player = _effect_player("DefenseShieldAudio", "battery", battery_volume_db)
	battery_player.pitch_scale = battery_sound_speed
	jump_player = _effect_player("JumpAudio", "jump", jump_volume_db)
	nuclear_player = _effect_player("NuclearAlertAudio", "nuclear", nuclear_alert_volume_db)
	nuclear_player.stream = make_alert_sequence(2)
	nuclear_player.pitch_scale = nuclear_alert_speed
	nuclear_beep_player = AudioStreamPlayer.new()
	nuclear_beep_player.name = "NuclearApproachBeep"
	nuclear_beep_player.stream = BattleAudio.make_approach_beep()
	nuclear_beep_player.volume_db = nuclear_beep_volume_db
	add_child(nuclear_beep_player)
	impact_player = AudioStreamPlayer.new()
	impact_player.name = "HullImpactAudio"
	impact_player.stream = BattleAudio.make_hull_impact()
	impact_player.volume_db = impact_volume_db
	add_child(impact_player)
	siege_alert_player = AudioStreamPlayer.new()
	siege_alert_player.name = "SiegeAlert"
	siege_alert_player.stream = make_alert_sequence(2)
	siege_alert_player.volume_db = siege_alert_volume_db
	siege_alert_player.pitch_scale = siege_alert_speed
	add_child(siege_alert_player)
	firewall_player = AudioStreamPlayer.new()
	firewall_player.name = "FirewallAudio"
	firewall_player.stream = FirewallAudio.make_firewall_loop()
	firewall_player.volume_db = firewall_volume_db
	add_child(firewall_player)
	missile_boom_player = AudioStreamPlayer.new()
	missile_boom_player.name = "MissileBoomAudio"
	missile_boom_player.stream = BattleAudio.make_missile_boom()
	missile_boom_player.volume_db = missile_boom_volume_db
	missile_boom_player.max_polyphony = 2
	add_child(missile_boom_player)
	nuke_boom_player = AudioStreamPlayer.new()
	nuke_boom_player.name = "NukeBoomAudio"
	nuke_boom_player.stream = BattleAudio.make_nuke_boom()
	nuke_boom_player.volume_db = nuke_boom_volume_db
	nuke_boom_player.max_polyphony = 2
	add_child(nuke_boom_player)
	craft_boom_player = _boom_player("CraftBoomAudio", BattleAudio.make_craft_boom(), craft_boom_volume_db)
	heavy_boom_player = _boom_player("HeavyBoomAudio", BattleAudio.make_heavy_boom(), heavy_boom_volume_db)
	capital_boom_player = _boom_player("CapitalBoomAudio", BattleAudio.make_capital_boom(), capital_boom_volume_db)
	bonus_chime_player = _boom_player("BonusChimeAudio", BattleAudio.make_bonus_chime(), bonus_chime_volume_db)
	bonus_chime_player.max_polyphony = 1
	emp_player = _boom_player("EmpZapAudio", BattleAudio.make_emp_zap(), emp_zap_volume_db)
	emp_player.max_polyphony = 1
	repair_sound_player = _boom_player("RepairChargeAudio", BattleAudio.make_repair_charge(rapid_repair_seconds), repair_sound_volume_db)
	repair_sound_player.max_polyphony = 1
	stealth_ready_player = _boom_player("StealthReadyAudio", make_stealth_ready_sound(), stealth_ready_volume_db)
	stealth_ready_player.max_polyphony = 1
	action_stations_player = _boom_player("ActionStationsAudio", BattleAudio.make_action_stations(), action_stations_volume_db)
	action_stations_player.max_polyphony = 1
	all_clear_player = _boom_player("AllClearAudio", BattleAudio.make_all_clear(), all_clear_volume_db)
	all_clear_player.max_polyphony = 1
	fleet_saved_player = _boom_player("FleetSavedAudio", BattleAudio.make_fleet_saved(), fleet_saved_volume_db)
	fleet_saved_player.max_polyphony = 1
	fleet_partial_player = _boom_player("FleetPartialAudio", BattleAudio.make_fleet_partial(), fleet_partial_volume_db)
	fleet_partial_player.max_polyphony = 1
	fleet_lost_player = _boom_player("FleetLostAudio", BattleAudio.make_fleet_lost(), fleet_lost_volume_db)
	fleet_lost_player.max_polyphony = 1
	reset_battle()

func _process(delta: float) -> void:
	hit_flash_remaining = maxf(0.0, hit_flash_remaining - delta)
	if rapid_repair_remaining <= 0.0 and is_instance_valid(repair_sound_player) and repair_sound_player.playing:
		repair_sound_player.stop()
	_age_explosions(delta)
	for index in range(impacts.size() - 1, -1, -1):
		impacts[index].age += delta
		if impacts[index].age >= 0.45:
			impacts.remove_at(index)
	if is_defeated():
		queue_redraw()
		return
	battle_time += delta
	_update_wave()
	_update_wave_system(delta)
	_update_battery(delta)
	_update_firewall(delta)
	_update_emp_offer()
	_update_automation()
	_update_interceptor_squadrons()
	_tick_waits(gunship_waits, gunships_in_hangar(), delta)
	_tick_waits(interceptor_waits, interceptors_in_hangar(), delta)
	_update_repair(delta)
	_update_rapid_repair(delta)
	_update_klaxon()
	jump_recharge_remaining = maxf(0.0, jump_recharge_remaining - delta)
	safe_remaining = maxf(0.0, safe_remaining - delta)
	status_remaining = maxf(0.0, status_remaining - delta)
	if status_remaining <= 0.0:
		status_message = "DEFEND THE AEGIS | INTERCEPTORS ENGAGE ATTACK DRONES AND MISSILES"
	for index in range(contacts.size() - 1, -1, -1):
		var contact: Dictionary = contacts[index]
		contact.age += delta
		if Icons.is_interceptor(contact.kind):
			continue
		if float(contact.get("frozen", 0.0)) > 0.0:
			# 1.1.0 PULSE BOMB: frozen enemies do not move, fire or launch.
			contact.frozen = maxf(0.0, float(contact.frozen) - delta)
			if _pulse_drain_step(contact, delta):
				# The drain destroyed this Attack Drone (points already given).
				contacts.remove_at(index)
				continue
			if contact.has("velocity"):
				contact.velocity = Vector3.ZERO
			if contact.kind in ["carrier", "siege_ship", "drone"]:
				continue
		if contact.kind == "carrier":
			_update_carrier(contact, delta)
			continue
		if contact.kind == "siege_ship":
			_update_siege(contact, delta)
			continue
		if contact.kind == "drone":
			_update_drone(contact, delta)
			continue
		if contact.kind == "missile":
			var aim := own_ship_position
			if contact.has("spread"):
				# Siege barrage: fan out sideways across the flight path,
				# closing in on the ship near the end.
				var far: float = clampf((contact.position.distance_to(own_ship_position) - 0.35) / 0.9, 0.0, 1.0)
				aim += contact.get("side", Vector3.RIGHT) * contact.spread * far
			contact.position = contact.position.move_toward(aim,
				delta * movement_speed * missile_speed * missile_speed_factor())
			continue
		if contact.kind == "unknown" and contact.age >= identification_seconds:
			_identify_carrier(contact)
	_update_interceptors(delta)
	_update_gunships(delta)
	_update_stealth(delta)
	_update_pulse(delta)
	_resolve_missiles()
	if not is_defeated():
		_update_own_weapons(delta)
		_update_special_projectiles(delta)
	if not is_defeated():
		_update_nuclear_alarm(delta)
		_update_breachers(delta)
		_update_siege_spawning(delta)
		_update_siege_alert()
	_update_jump_offline()
	_keep_play_in_wedge()
	if auto_spawn and safe_remaining <= 0.0 and not is_defeated():
		spawn_countdown -= delta
		wave_countdown -= delta
		if pending.is_empty() and wave_countdown <= 0.0:
			_queue_wave()
			wave_countdown = maxf(3.0, wave_interval_seconds) * capital_arrival_factor()
	# Emitter and distant-contact arrivals share one queue, preventing beep overlap.
	if not pending.is_empty() and safe_remaining <= 0.0 and not is_defeated():
		spawn_countdown -= delta if not auto_spawn else 0.0
		if spawn_countdown <= 0.0:
			var request: Dictionary = pending.pop_front()
			if request.has("origin_id"):
				spawn_from_carrier(request.kind, request.origin_id)
			else:
				spawn_contact(request.kind, request.faction)
			spawn_countdown = maxf(0.5, arrival_gap_seconds)
	arrival_player.volume_db = arrival_volume_db
	launch_player.volume_db = launch_volume_db
	queue_redraw()

func _queue_wave() -> void:
	if pending.size() >= 10:
		return
	# 1.2.0: a defined wave sends only its Enemy force, and only during the assault.
	if wave_system_active() and not wave_wants_carrier():
		return
	if count_kind("carrier") + count_kind("unknown") < carrier_cap() and count_tracks() < max_contacts:
		pending.append({"kind": "unknown", "faction": "unknown"})

func spawn_contact(kind: String, faction: String) -> String:
	if not ACTIVE_KINDS.has(kind):
		return ""
	if is_defeated() or safe_remaining > 0.0:
		return ""
	if faction not in ["friendly", "hostile", "unknown"]:
		return ""
	if Icons.is_interceptor(kind):
		return _spawn_interceptor(kind, true) if faction == "friendly" else ""
	if kind == "gunship":
		return _spawn_gunship() if faction == "friendly" else ""
	# Attack Drones and missiles have no independent/random spawn path.
	if kind in ["drone", "breacher", "missile"]:
		return ""
	if faction != ("unknown" if kind == "unknown" else "hostile"):
		return ""
	if count_tracks() >= max_contacts:
		return ""
	if count_kind("carrier") + count_kind("unknown") >= carrier_cap():
		return ""
	# Every distant arrival is unidentified, including requests for a capital ship.
	kind = "unknown"
	faction = "unknown"
	var start := _place_capital()
	if start == Vector3.INF:
		return ""
	var finish := start
	var contact_id := _new_id("U")
	contacts.append({
		"id": contact_id, "kind": kind, "faction": faction,
		"start": start, "finish": finish, "position": start,
		"progress": 0.0, "age": 0.0,
		"duration": 45.0,
		"drone_timer": rng.randf_range(4.0, 6.0),
		"missile_timer": rng.randf_range(8.0, 11.0)
	})
	if wave_system_active():
		wave_force_spawned += 1
	_announce_contact(contact_id, kind, faction)
	return contact_id

func _new_id(prefix: String) -> String:
	var id := "%s-%03d" % [prefix, next_id]
	next_id += 1
	return id

func _announce_contact(contact_id: String, kind: String, faction: String) -> void:
	spawn_count += 1
	contact_spawned.emit(contact_id, kind, faction)
	if arrival_sound_enabled and not Icons.is_interceptor(kind):
		arrival_player.volume_db = arrival_volume_db
		arrival_player.play()
		beep_count += 1
		arrival_beep_played.emit(contact_id, kind)
	queue_redraw()

func find_contact(id: String) -> Dictionary:
	for contact in contacts:
		if contact.id == id:
			return contact
	return {}

func count_kind(kind: String) -> int:
	var count := 0
	for contact in contacts:
		if contact.kind == kind:
			count += 1
	return count

func spawn_from_carrier(kind: String, origin_id: String) -> String:
	if kind not in ["drone", "breacher", "missile"] or is_defeated() or safe_remaining > 0.0:
		return ""
	var base := find_contact(origin_id)
	if base.is_empty() or base.kind not in ["carrier", "siege_ship"]:
		return ""
	if float(base.get("frozen", 0.0)) > 0.0:
		return ""
	# A Siege Ship launches missiles only, never fighters.
	if base.kind == "siege_ship" and kind != "missile":
		return ""
	if kind == "drone" and (count_kind("drone") >= max_drones or count_tracks() >= max_contacts or count_base_drones(origin_id) >= max_drones_per_carrier):
		return ""
	if kind == "missile" and count_kind("missile") >= missile_cap():
		return ""
	if kind == "breacher" and (not breachers_enabled or count_kind("breacher") >= breacher_cap() or count_tracks() >= max_contacts or count_base_heavies(origin_id) >= max_heavy_per_carrier):
		return ""
	var direction: Vector3 = base.position.direction_to(own_ship_position)
	var origin: Vector3 = base.position + direction * carrier_emission_radius
	var id := _new_id("M" if kind == "missile" else ("HR" if kind == "breacher" else "H"))
	contacts.append({
		"id": id, "kind": kind, "faction": "hostile", "position": origin,
		"start": origin, "finish": own_ship_position, "age": 0.0, "progress": 0.0,
		"origin_id": origin_id, "origin_position": base.position,
		"target_position": own_ship_position, "defense_checked": false,
		"phase": "approach", "patrol_angle": rng.randf_range(0.0, TAU),
		"approach_point": Vector3(rng.randf_range(-0.3, 0.3), -0.10, 0.05),
		"velocity": Vector3.ZERO,
		"health": scaled_hits(breacher_hit_points) if kind == "breacher" else 1,
		"hack_remaining": maxf(0.1, hacking_seconds / hack_speed()),
		"hack_point": _hack_point_for(next_id % 2 == 0) if kind == "breacher" else own_ship_position + Vector3(-hack_park_offset.x if next_id % 2 == 0 else hack_park_offset.x, hack_park_offset.y, 0.0),
		"next_battery_shot": 0.0
	})
	_announce_contact(id, kind, "hostile")
	return id

func _update_carrier(base: Dictionary, delta: float) -> void:
	# Stationary until destroyed or left behind by an JUMP jump.
	if not carrier_weapons_enabled or safe_remaining > 0.0:
		return
	if breachers_enabled:
		base.heavy_timer -= delta
		if base.heavy_timer <= 0.0:
			if pending.size() < 12 and count_kind("breacher") + pending_heavies() < breacher_cap() and count_base_heavies(base.id, true) < max_heavy_per_carrier:
				pending.append({"kind": "breacher", "origin_id": base.id})
			base.heavy_timer = maxf(5.0, heavy_launch_interval) * heavy_interval_factor() / attack_rate()
	if nuclear_weapons_enabled and not base.get("nuclear_launched", false):
		base.nuclear_timer -= delta
		if base.nuclear_timer <= 0.0:
			_launch_nuclear(base)
	base.flak_timer -= delta
	if base.flak_timer <= 0.0:
		_fire_flak(base)
		base.flak_timer = maxf(2.0, carrier_flak_interval) / attack_rate()
	base.drone_timer -= delta
	base.missile_timer -= delta
	if base.drone_timer <= 0.0:
		if pending.size() < 12 and count_kind("drone") < max_drones and count_base_drones(base.id, true) < max_drones_per_carrier:
			pending.append({"kind": "drone", "origin_id": base.id})
		base.drone_timer = maxf(2.0, drone_launch_interval) * drone_interval_factor() * rng.randf_range(0.85, 1.15) / attack_rate()
	if base.missile_timer <= 0.0:
		if pending.size() < 12 and count_kind("missile") < max_missiles:
			pending.append({"kind": "missile", "origin_id": base.id})
		base.missile_timer = maxf(3.0, missile_launch_interval) * missile_interval_factor() * rng.randf_range(0.85, 1.15) / attack_rate()

func _update_drone(drone: Dictionary, delta: float) -> void:
	# 1.2.2 Protect the fleet: Attack Drones attack the civilian ships only.
	if drone.get("phase", "") == "protect":
		_update_protect_drone(drone, delta)
		return
	# 1.2.0 bonus sweep: fly straight across, never attack, leave at the far edge.
	if drone.get("phase", "") == "sweep":
		_steer(drone, drone.sweep_exit, sweep_speed, delta)
		if drone.position.distance_to(drone.sweep_exit) <= 0.04:
			sweep_escaped += 1
			_remove_contact(drone.id)
		return
	drone.attack_cooldown = maxf(0.0, drone.get("attack_cooldown", 0.0) - delta)
	if drone.phase != "return" and drone.age >= drone_sortie_seconds:
		var home := _drone_home(drone)
		if not home.is_empty():
			drone.phase = "return"
			drone.home_id = home.id
	if drone.phase == "return":
		var home := _drone_home(drone)
		if home.is_empty():
			# No Enemy Carrier left to refuel at: keep fighting.
			drone.phase = "harass"
			drone.age = 0.0
			return
		drone.home_id = home.id
		_steer(drone, home.position, drone_speed() * returning_speed_factor, delta)
		if drone.position.distance_to(home.position) <= 0.05:
			drones_docked += 1
			_remove_contact(drone.id)
		return
	# 1.1.0: once the Stealth Interceptor has fired, nearby Attack Drones turn on it first.
	if drone.phase in ["harass", "approach"] and _drone_focus_stealth(drone, delta):
		return
	# Hunt returning Interceptors (low on fuel and ammunition) first; with Fighter
	# Losses on, Attack Drones also attack active Interceptors and Gunships nearby.
	var prey: Dictionary = {}
	var nearest := drone_attack_range
	var best := INF
	for other in contacts:
		var returning_interceptor: bool = Icons.is_interceptor(other.kind) and other.get("phase", "") == "return"
		var fighter: bool = fighter_losses_enabled and (Icons.is_interceptor(other.kind) or (other.kind == "gunship" and not is_tender(other))) and other.get("phase", "") != "launch"
		# 1.1.0: a revealed Stealth Interceptor is hunted by _drone_focus_stealth (above).
		if returning_interceptor or fighter:
			var gap: float = drone.position.distance_to(other.position)
			var rank := gap * (0.5 if returning_interceptor else 1.0)
			if gap < drone_attack_range and rank < best:
				best = rank
				nearest = gap
				prey = other
	if not prey.is_empty() and drone.phase == "harass":
		_steer(drone, prey.position, drone_speed() * 1.3, delta)
		if nearest <= 0.05 and drone.attack_cooldown <= 0.0:
			drone.attack_cooldown = maxf(0.5, drone_attack_cooldown)
			if Icons.is_interceptor(prey.kind) and prey.get("phase", "") == "return":
				if rng.randf() < clampf(returning_interceptor_loss_chance, 0.0, 1.0):
					fighter_losses_by["returning"] += 1
					_lose_fighter(prey, "INTERCEPTOR LOST ON RETURN | ATTACK DRONES HUNTING RETURNING FLIGHTS")
			elif rng.randf() < clampf(drone_hit_chance, 0.0, 1.0):
				if prey.kind == "gunship" and rng.randf() < clampf(gunship_evasion_chance, 0.0, 0.95):
					gunship_evades += 1
				elif prey.kind != "gunship" and rng.randf() < clampf(interceptor_evasion_chance, 0.0, 0.95):
					interceptor_evades += 1
				else:
					_damage_fighter(prey, "ATTACK DRONE FIRE")
		return
	if drone.phase == "approach":
		_steer(drone, drone.approach_point, drone_speed(), delta)
		if drone.position.distance_to(drone.approach_point) < 0.03:
			drone.phase = "harass"
			drone.patrol_angle = atan2((drone.position.y + 0.10) / 0.22, drone.position.x / 0.40)
	else:
		drone.patrol_angle += delta * 0.11
		var patrol := Vector3(cos(drone.patrol_angle) * 0.40,
			-0.10 + sin(drone.patrol_angle) * 0.22, 0.08)
		_steer(drone, patrol, drone_speed(), delta)

func _drone_home(drone: Dictionary) -> Dictionary:
	# Prefer the launching Enemy Carrier; otherwise the nearest surviving one.
	# origin_id is never changed, so per-Enemy Carrier launch caps stay exact.
	for key in ["home_id", "origin_id"]:
		var preferred := find_contact(drone.get(key, ""))
		if not preferred.is_empty() and preferred.kind == "carrier":
			return preferred
	var home: Dictionary = {}
	var best := INF
	for contact in contacts:
		if contact.kind == "carrier":
			var gap: float = drone.position.distance_to(contact.position)
			if gap < best:
				best = gap
				home = contact
	return home

func is_returning(contact: Dictionary) -> bool:
	return contact.get("phase", "") == "return" and (Icons.is_interceptor(contact.kind) or contact.kind in ["drone", "gunship"])

func display_color(contact: Dictionary) -> Color:
	if contact.get("faction", "") == "civilian":
		return civilian_display_color(contact)
	if float(contact.get("frozen", 0.0)) > 0.0 or contact.get("pulse_slowed", false):
		# 1.1.0 PULSE BOMB: frozen enemies and slowed nuclear missiles shimmer ice-blue.
		var glint := 0.5 + 0.5 * sin(TAU * 5.0 * battle_time + float(String(contact.id).hash() % 7))
		var ice := pulse_color.lerp(Color.WHITE, glint * 0.45)
		ice.a = 0.7 + 0.3 * glint
		var hurt := clampf(float(contact.get("drain_flash", 0.0)) / 0.3, 0.0, 1.0)
		if hurt > 0.0:
			# Red flicker each time the drain takes health.
			ice = ice.lerp(Color(1.0, 0.22, 0.25), hurt * 0.85)
			ice.a = 1.0
		return ice
	var color := unknown_color
	if contact.faction == "friendly":
		color = friendly_color
	elif contact.faction == "hostile":
		color = hostile_color
	if contact.get("phase", "") == "protect" and float(contact.get("hold", 0.0)) > 0.0 and protect_jump_in_hold > 0.0:
		# 1.2.5: a Attack Drone jumping in fades up from dim while it holds.
		color.a = lerpf(1.0, 0.3, clampf(float(contact.hold) / protect_jump_in_hold, 0.0, 1.0))
	elif contact.kind == "stealth_interceptor" and contact.get("phase", "") == "return":
		# 1.1.0 (Stephen 2026-10-25): heading home after either weapon it keeps its
		# normal green (only the blink), so it never looks like a frozen enemy.
		color.a = 0.55 + 0.45 * (0.5 + 0.5 * cos(TAU * returning_flash_hz * battle_time))
	elif is_returning(contact):
		color = color.lerp(Color.WHITE, clampf(returning_lighten, 0.0, 0.8))
		color.a = 0.55 + 0.45 * (0.5 + 0.5 * cos(TAU * returning_flash_hz * battle_time))
	elif contact.kind == "convoy_breacher" and contact.get("breach_state", "") == "latched":
		color.a = 1.0 if int(battle_time * hacking_flash_hz * 2.0) % 2 == 0 else 0.22
	elif contact.kind == "breacher" and contact.get("phase", "") in ["hacking", "draining"]:
		color.a = 1.0 if int(battle_time * hacking_flash_hz * 2.0) % 2 == 0 else 0.22
	elif contact.kind == "breacher" and contact.get("phase", "") == "emp":
		# Electric-blue shimmer while overloaded.
		var shimmer := 0.5 + 0.5 * sin(TAU * 9.0 * battle_time + float(String(contact.id).hash() % 7))
		color = emp_color.lerp(Color(0.85, 0.96, 1.0), shimmer * 0.6)
		color.a = 0.65 + 0.35 * shimmer
	elif contact.kind == "stealth_interceptor" and contact.get("phase", "") == "return":
		color = color.lerp(Color.WHITE, clampf(returning_lighten, 0.0, 0.8))
		color.a = 0.55 + 0.45 * (0.5 + 0.5 * cos(TAU * returning_flash_hz * battle_time))
	elif contact.kind == "stealth_interceptor" and not contact.get("revealed", false):
		# Rapid blink while still hidden from the enemy.
		color.a = 1.0 if int(battle_time * stealth_blink_hz * 2.0) % 2 == 0 else 0.3
	elif contact.kind == "breacher" and contact.get("phase", "") == "emp_return":
		color = color.lerp(Color.WHITE, clampf(returning_lighten, 0.0, 0.8))
		color.a = 0.55 + 0.45 * (0.5 + 0.5 * cos(TAU * returning_flash_hz * battle_time))
	elif contact.kind == "missile" and enemy_missile_pulse:
		color = _pulse_dim(color, missile_pulse_level())
	return color

## 1.07: enemy missile brightness, from enemy_missile_pulse_min up to 1.0.
func missile_pulse_level() -> float:
	if not enemy_missile_pulse:
		return 1.0
	var low := clampf(enemy_missile_pulse_min, 0.0, 1.0)
	return lerpf(low, 1.0, 0.5 + 0.5 * cos(TAU * enemy_missile_pulse_hz * battle_time))

func _pulse_dim(color: Color, level: float) -> Color:
	return Color(color.r * level, color.g * level, color.b * level, color.a)

func _steer(ship: Dictionary, destination: Vector3, speed: float, delta: float) -> void:
	# Acceleration-limited velocity avoids instantaneous reversals and target jitter.
	var offset: Vector3 = destination - ship.position
	var limit := maxf(0.0, speed * movement_speed)
	var desired := offset.normalized() * minf(limit, offset.length() * 2.0)
	var velocity: Vector3 = ship.get("velocity", Vector3.ZERO)
	velocity = velocity.move_toward(desired, fighter_acceleration * movement_speed * delta)
	ship.velocity = velocity.limit_length(limit)
	ship.position += ship.velocity * delta

func _resolve_missiles() -> void:
	for index in range(contacts.size() - 1, -1, -1):
		var missile: Dictionary = contacts[index]
		if missile.kind != "missile":
			continue
		var distance: float = missile.position.distance_to(own_ship_position)
		if prox_active and distance <= prox_defense_radius and battle_time >= missile.get("next_battery_shot", 0.0):
			# Continuous fire: each missile in the zone draws a shot every interval.
			missile.defense_checked = true
			missile.next_battery_shot = battle_time + maxf(0.1, battery_shot_interval)
			if rng.randf() < clampf(prox_success_chance, 0.0, 0.95):
				prox_kills += 1
				_count_kill("missile")
				var battery_points := points_for(battery_kill_points)
				battery_kill_score += battery_points
				_add_points(battery_points)
				impacts.append({"position": missile.position, "age": 0.0, "battery": true})
				_explode(missile.position, "missile")
				contacts.remove_at(index)
				_set_status("DEFENSE SHIELD: MISSILE DESTROYED", 2.0)
				continue
		if distance <= missile_impact_radius:
			contacts.remove_at(index)
			missile_hits += 1
			impacts.append({"position": own_ship_position, "age": 0.0})
			apply_damage(missile.get("damage", missile_damage) * damage_factor())
			if is_defeated():
				break

func is_defeated() -> bool:
	return hull <= 0.0

func apply_damage(amount: float, missile_impact: bool = true) -> void:
	if is_defeated() or amount <= 0.0:
		return
	hull = maxf(0.0, hull - amount)
	repair_delay_remaining = repair_delay_seconds
	repair_elapsed = 0.0
	ship_damaged.emit(amount, hull)
	_set_status(("MISSILE HIT" if missile_impact else "COMPUTER HACK: HULL DRAIN") + " | HULL %d / %d" % [ceili(hull), ceili(max_hull)], 3.0)
	if is_defeated():
		pending.clear()
		arrival_player.stop()
		launch_player.stop()
		klaxon_player.stop()
		klaxon_queue.clear()
		_stop_special_audio()
		prox_active = false
		prox_burst_remaining = 0.0
		rapid_repair_remaining = 0.0
		status_message = "SHIP LOST | GAME OVER"
	if missile_impact:
		# Play after defeat cleanup so the final impact is also audible.
		hit_flash_remaining = hit_flash_seconds
		impact_player.volume_db = impact_volume_db
		impact_player.play()
		impact_sound_count += 1

func set_prox_defense(enabled: bool) -> void:
	if is_defeated():
		return
	if not enabled:
		if prox_active:
			_end_battery_burst()
		return
	if prox_active or not can_fire_battery():
		return
	prox_active = true
	battery_player.volume_db = battery_volume_db
	battery_player.pitch_scale = battery_sound_speed
	battery_player.play()
	_set_status("DEFENSE SHIELD FIRING | STANDARD MISSILES ONLY", 3.0)

func can_jump() -> bool:
	if protect_active():
		return false
	return not is_defeated() and not jump_offline and jump_recharge_remaining <= 0.0

## 1.08: a breach (any Breacher draining the hull) holds JUMP offline with its charge
## at 0%. Once no Breacher is draining (EMP, destroyed, out of range), it recharges.
func _update_jump_offline() -> void:
	var offline := jump_offline_on_breach and not is_defeated() and active_hackers() > 0
	if offline:
		jump_breach_rebuild_total = maxf(1.0, jump_breach_recharge_seconds)
		jump_recharge_remaining = jump_breach_rebuild_total
		jump_rebuilding_after_breach = true
	elif jump_rebuilding_after_breach and jump_recharge_remaining <= 0.0:
		jump_rebuilding_after_breach = false
	if offline == jump_offline:
		return
	jump_offline = offline
	if offline:
		jump_offline_count += 1
		_set_status("HACK BREACH | JUMP OFFLINE | EMP OR DESTROY THE BREACHER", 4.0)
	else:
		_set_status("JUMP BACK ONLINE | RECHARGING", 3.0)
	jump_offline_changed.emit(offline)

## 1.1.0: what a JUMP during a wave costs right now: Jump Score Cost or Jump Score Percent
## of the current score, whichever is bigger.
func jump_cost_now() -> int:
	return maxi(jump_score_cost, roundi(float(score) * maxf(0.0, jump_score_percent) / 100.0))

func request_jump() -> bool:
	if not can_jump():
		return false
	# 1.2.0: jumping during the rest is free and brings the next wave on early.
	var rest_jump := wave_system_active() and wave_phase == "rest"
	last_jump_cost = jump_cost_now()
	if not rest_jump:
		score = maxi(0, score - last_jump_cost)
	var left_siege := count_kind("siege_ship") > 0
	# 1.09: a Stealth Interceptor out on its run jumps with the fleet and starts rearming.
	if count_kind("stealth_interceptor") > 0:
		stealth_recovered += 1
		stealth_cooldown_remaining = maxf(1.0, stealth_rearm_seconds)
		stealth_event.emit("Stealth Interceptor recovered at JUMP jump | rearming %ds" % int(stealth_cooldown_remaining))
	contacts.clear()
	pending.clear()
	impacts.clear()
	arrival_player.stop()
	launch_player.stop()
	klaxon_player.stop()
	klaxon_queue.clear()
	if prox_active:
		_end_battery_burst()
	nuclear_player.stop()
	nuclear_beep_player.stop()
	nuclear_alert_queue.clear()
	nuclear_alert_contact_id = ""
	nuclear_alarm_remaining = 0.0
	impact_player.stop()
	hit_flash_remaining = 0.0
	# Any Siege Ship is left behind; after the quiet period another may find the fleet.
	if left_siege:
		siege_cooldown_remaining = siege_cooldown_now()
	siege_alert_player.stop()
	siege_alert_pending = false
	siege_check_remaining = maxf(5.0, siege_check_seconds)
	jump_player.volume_db = jump_volume_db
	jump_player.play()
	own_fire_remaining = own_missile_interval
	_clear_waits(interceptor_waits, "launch")
	jump_recharge_remaining = maxf(1.0, jump_recharge_seconds)
	jump_rebuilding_after_breach = false
	safe_remaining = maxf(1.0, post_jump_safe_seconds)
	spawn_countdown = 0.8
	wave_countdown = 0.0
	jumps_used += 1
	_set_status("JUMP COMPLETE | -%d POINTS | DAMAGE RETAINED" % last_jump_cost, safe_remaining)
	if wave_system_active():
		_wave_after_jump(rest_jump)
	if jump_flash_enabled:
		jump_flash_remaining = maxf(0.3, jump_flash_seconds)
	jump_completed.emit()
	return true

func _set_status(message: String, seconds: float) -> void:
	status_message = message
	status_remaining = seconds

func reset_battle() -> void:
	active_difficulty = clampi(difficulty, 0, 2)
	pulse_charges = 0
	pulse_drained = 0.0
	pulse_drain_kills = 0
	pulse_awards_earned = 0
	pulse_charges_lost = 0
	pulse_bombs.clear()
	pulse_fields.clear()
	pulse_detonations = 0
	pulse_frozen_large = 0
	pulse_frozen_fighters = 0
	pulse_breachers_sent_home = 0
	pulse_nukes_slowed = 0
	pulse_freeze_left = 0.0
	stealth_cooldown_remaining = 0.0
	stealth_was_ready = false
	stealth_launches = 0
	stealth_nukes_fired = 0
	stealth_nuke_hits = 0
	stealth_lost = 0
	stealth_recovered = 0
	stealth_shots_taken = 0
	stealth_pursuits = 0
	interceptor_waits.clear()
	gunship_waits.clear()
	interceptor_recovery_holds = 0
	gunship_recovery_holds = 0
	auto_all_gunship_launches = 0
	nuke_speed_bonuses.clear()
	auto_battery_started = false
	auto_firewall_started = false
	explosions.clear()
	screen_flash_remaining = 0.0
	screen_flash_peak = 0.0
	last_boom = {"missile": -INF, "nuke": -INF, "craft": -INF, "heavy": -INF, "capital": -INF}
	booms_played = {"missile": 0, "nuke": 0, "craft": 0, "heavy": 0, "capital": 0}
	nuke_hits_landed = 0
	battery_nuke_kills = 0
	battery_nuke_misses = 0
	battery_splash_damage = 0.0
	interceptor_squadrons.clear()
	auto_battery_starts = 0
	auto_firewall_starts = 0
	auto_interceptor_launches = 0
	auto_gunship_launches = 0
	auto_jumps = 0
	auto_repairs = 0
	craft_explosions = 0
	capital_explosions = 0
	jump_flash_remaining = 0.0
	contacts.clear()
	pending.clear()
	impacts.clear()
	next_id = 1
	hull = max_hull
	repair_delay_remaining = 0.0
	repair_elapsed = 0.0
	own_fire_remaining = own_missile_interval
	carriers_destroyed = 0
	own_missile_hits = 0
	identification_count = 0
	double_missile_unlocked_at = -1.0
	rapid_missile_unlocked_at = -1.0
	missile_bonus_pick = ""
	missile_bonus_offer_open = false
	missile_bonus_offers = 0
	missile_bonus_set_offers = 0
	missile_bonus_offer_waiting = false
	missile_bonus_waits = 0
	missile_bonus_switches = 0
	own_pair_remaining = 0.0
	own_pair_launches = 0
	bonus_chimes = 0
	emp_charges = 0
	firewall_out_since = -1.0
	emp_offer_open = false
	interceptor_claims.clear()
	squadron_patrol_angle = 0.0
	missile_retargets = 0
	jump_offline = false
	jump_offline_count = 0
	jump_rebuilding_after_breach = false
	kills = {}
	for kind in KILL_KINDS:
		kills[kind] = 0
	emp_awards_earned = 0
	emp_uses = 0
	emp_heavies_overloaded = 0
	emp_heavies_docked = 0
	repair_sounds = 0
	if is_instance_valid(repair_sound_player):
		repair_sound_player.stop()
	battery_kill_score = 0
	ship_nuke_hits = 0
	ship_nuke_kills = 0
	klaxon_count = 0
	klaxon_queue.clear()
	klaxon_player.stop()
	_stop_special_audio()
	prox_burst_remaining = maxf(0.1, prox_burst_seconds)
	prox_cooldown_remaining = 0.0
	battery_idle = 0.0
	interceptors_lost = 0
	drones_docked = 0
	nuclear_alarm_remaining = 0.0
	battle_time = 0.0
	nuclear_alert_count = 0
	nuclear_beep_count = 0
	nuclear_launches = 0
	nuclear_intercepts = 0
	nuclear_hits = 0
	gunship_evades = 0
	gunships_lost = 0
	gunships_returned = 0
	interceptors_returned = 0
	gunship_missile_hits = 0
	score = 0
	earned_points = 0
	repair_bonuses_earned = 0
	repair_charges = 1
	repair_earning_paused = false
	repair_charges_lost = 0
	breachers_destroyed = 0
	wave = 1
	_reset_wave_system()
	siege_alert_pending = false
	siege_alert_count = 0
	siege_check_remaining = maxf(5.0, siege_check_seconds)
	siege_cooldown_remaining = 0.0
	siege_spawns = 0
	sieges_destroyed = 0
	siege_barrages = 0
	siege_missiles_fired = 0
	siege_hits_by = {"ship": 0, "gunship": 0, "interceptor": 0}
	own_volley_count = 0
	firewall_active = false
	firewall_charge = maxf(1.0, firewall_seconds)
	firewall_idle = 0.0
	firewall_uses = 0
	sieges_escaped = 0
	fighter_points_lost = 0
	interceptor_evades = 0
	fighter_losses_by = {"drone": 0, "flak": 0, "returning": 0}
	hit_flash_remaining = 0.0
	impact_sound_count = 0
	impact_player.stop()
	scored_contacts.clear()
	rapid_repair_used = false
	rapid_repair_remaining = 0.0
	rapid_repair_rate = 0.0
	prox_active = false
	jump_recharge_remaining = 0.0 if jump_starts_ready else jump_recharge_seconds
	safe_remaining = 0.0
	missile_hits = 0
	prox_kills = 0
	missile_intercepts = 0
	jumps_used = 0
	intercepted_count = 0
	spawn_count = 0
	beep_count = 0
	launch_sound_count = 0
	spawn_countdown = 0.8
	wave_countdown = wave_interval_seconds
	arrival_player.stop()
	launch_player.stop()
	_set_status("DEFEND THE AEGIS | JUMP IS YOUR ESCAPE", 4.0)
	if auto_spawn:
		pending.append({"kind": "unknown", "faction": "unknown"})

func speed_for_kind(kind: String) -> float:
	if Icons.is_interceptor(kind):
		return maxf(0.001, interceptor_speed) * fighter_speed_factor()
	if kind in CAPITAL_KINDS:
		return 0.0
	if kind == "missile":
		return missile_speed
	if kind == "breacher":
		return heavy_speed()
	if kind in SMALL_HOSTILE_KINDS:
		return drone_speed()
	return maxf(0.001, normal_ship_speed)

func size_for_kind(kind: String) -> float:
	if kind == "civilian_c":
		return civilian_capital_icon_scale
	if kind.begins_with("civilian_"):
		return civilian_icon_scale
	if kind == "carrier":
		return carrier_icon_scale
	if kind == "siege_ship":
		return siege_icon_scale
	if kind == "breacher" or kind == "convoy_breacher":
		return small_ship_icon_scale * 1.20
	if kind == "interceptor" or kind == "drone" or kind == "stealth_interceptor":
		return small_ship_icon_scale
	return 1.0

func count_interceptors() -> int:
	var count := 0
	for contact in contacts:
		if Icons.is_interceptor(contact.kind):
			count += 1
	return count

func count_tracks() -> int:
	return count_kind("carrier") + count_kind("unknown") + count_kind("drone") + count_kind("breacher") + count_kind("siege_ship")

## 1.0.5: launches the Interceptors that are ready, up to Interceptors Per Launch. If only
## one is ready it goes alone. Ready ships left behind wait the launch cooldown; ships
## still counting down keep their own countdown.
func launch_interceptors() -> int:
	if is_defeated() or safe_remaining > 0.0:
		return 0
	var ready := interceptors_ready()
	if ready <= 0:
		return 0
	var launched := 0
	for index in range(mini(interceptors_per_launch, ready)):
		if not _spawn_interceptor("interceptor", false).is_empty():
			launched += 1
	if launched > 0:
		_hold_ready(interceptor_waits, interceptors_ready(), launch_cooldown_seconds)
		_play_launch(launched)
	return launched

func launch_origin(lane: float = 0.0) -> Vector3:
	# The latest field model places the unseen ship at the lower scope edge.
	return own_ship_position + Vector3(lane / 640.0, 0.0, 0.0)

func _spawn_interceptor(kind: String, play_sound: bool) -> String:
	if kind != "interceptor" or count_interceptors() >= interceptor_limit() or is_defeated() or safe_remaining > 0.0:
		return ""
	var contact_id := "F-%03d" % next_id
	next_id += 1
	if protect_active():
		protect_interceptors_launched += 1
	var lane := -22.0 if next_id % 2 == 0 else 22.0
	var origin := launch_origin(lane)
	contacts.append({
		"id": contact_id, "kind": kind, "faction": "friendly",
		"start": origin, "finish": Vector3.ZERO, "position": origin,
		"progress": 0.0, "age": 0.0, "duration": sortie_seconds,
		"phase": "launch", "target_id": "", "lane": lane,
		"patrol_angle": rng.randf_range(0.0, TAU), "velocity": Vector3.ZERO,
		"health": maxi(1, interceptor_hit_points), "max_health": maxi(1, interceptor_hit_points)
	})
	spawn_count += 1
	contact_spawned.emit(contact_id, kind, "friendly")
	if play_sound:
		_play_launch(1)
	queue_redraw()
	return contact_id

func _play_launch(count: int) -> void:
	if not launch_sound_enabled:
		return
	launch_player.volume_db = launch_volume_db
	launch_player.play()
	launch_sound_count += 1
	interceptor_launch_played.emit(count)

func _hostile_target(interceptor: Dictionary, excluded: Array[String]) -> Dictionary:
	# 1.1.0: a hacking or draining Breacher first while no Gunship is out.
	var hacker := _hacking_breacher_target(interceptor, excluded)
	if not hacker.is_empty():
		return hacker
	# 1.1.0 PULSE BOMB: frozen Attack Drones first (anywhere on the scope), then frozen
	# Enemy Carriers once no frozen drones are left.
	if pulse_chase_missiles_first:
		var close_missile := _interceptor_target_of(interceptor, excluded, ["missile"])
		if not close_missile.is_empty() and close_missile.position.distance_to(own_ship_position) < 0.65:
			return close_missile
	var frozen_excluded: Array[String] = excluded.duplicate()
	if pulse_chase_spread:
		for other in contacts:
			if other.id != interceptor.id and Icons.is_interceptor(other.kind) and not is_returning(other):
				var claimed: String = other.get("target_id", "")
				if not claimed.is_empty() and claimed != interceptor.get("target_id", ""):
					frozen_excluded.append(claimed)
	var frozen_drone := _nearest_frozen(interceptor.position, ["drone"], frozen_excluded)
	if frozen_drone.is_empty() and pulse_chase_spread:
		frozen_drone = _nearest_frozen(interceptor.position, ["drone"], excluded)
	if not frozen_drone.is_empty():
		return frozen_drone
	var frozen_carrier := _nearest_frozen(interceptor.position, ["carrier"], excluded)
	if not frozen_carrier.is_empty():
		return frozen_carrier
	# 1.08: a set number of Interceptors is assigned to a Siege Ship on the scope.
	var siege := _siege_assignment(interceptor, excluded)
	if not siege.is_empty():
		return siege
	# Attack Drones and missiles keep Interceptors busy; they break away for Breachers only when clear.
	var primary_kinds := ["drone", "missile"]
	if protect_active() and protect_breachers:
		primary_kinds.append("convoy_breacher")
	var primary := _interceptor_target_of(interceptor, excluded, primary_kinds)
	if not primary.is_empty():
		return primary
	var heavy := _interceptor_target_of(interceptor, excluded, ["breacher"])
	if not heavy.is_empty():
		return heavy
	# Last: the Siege Ship, the only capital ship Interceptors will attack.
	return _interceptor_target_of(interceptor, excluded, ["siege_ship"])

## 1.1.0: true while a Gunship (not a Repair Tender) is out and not flying back.
func gunship_out_attacking() -> bool:
	for contact in contacts:
		if contact.kind == "gunship" and not is_tender(contact) and contact.get("phase", "") != "return":
			return true
	return false

## 1.1.0: the nearest hacking or draining Breacher this Interceptor may go after: it is
## already on it, or fewer than Max Interceptors Per Tough Target are. Interceptors on
## the Siege Ship stay there, and the Protect the convoy round keeps its own rules.
func _hacking_breacher_target(interceptor: Dictionary, excluded: Array[String]) -> Dictionary:
	if not interceptors_hacking_breachers_first or protect_active() or gunship_out_attacking():
		return {}
	var mine: String = interceptor.get("target_id", "")
	var ship := siege_ship()
	if not ship.is_empty() and mine == ship.id:
		return {}
	var chosen: Dictionary = {}
	var best := INF
	for other in contacts:
		if other.kind != "breacher" or other.get("faction", "") != "hostile" or other.id in excluded or other.get("phase", "") not in ["hacking", "draining"]:
			continue
		if other.id != mine:
			var chasing := 0
			for mate in contacts:
				if mate.id != interceptor.id and Icons.is_interceptor(mate.kind) and not is_returning(mate) and mate.get("target_id", "") == other.id:
					chasing += 1
			if chasing >= max_interceptors_per_tough_target:
				continue
		var gap: float = interceptor.position.distance_to(other.position) * (0.5 if other.id == mine else 1.0)
		if gap < best:
			best = gap
			chosen = other
	return chosen

## 1.08: the Siege Ship, if this Interceptor already attacks it or a place is free.
func _siege_assignment(interceptor: Dictionary, excluded: Array[String]) -> Dictionary:
	if interceptors_on_siege_ship <= 0:
		return {}
	var ship := siege_ship()
	if ship.is_empty() or excluded.has(ship.id):
		return {}
	if interceptor.get("target_id", "") == ship.id:
		return ship
	var assigned := 0
	for other in contacts:
		if other.id != interceptor.id and Icons.is_interceptor(other.kind) and not is_returning(other) and other.get("target_id", "") == ship.id:
			assigned += 1
	return ship if assigned < interceptors_on_siege_ship else {}

## 1.07: slot position in the shared Interceptor patrol formation (a shallow V).
func formation_point(slot: int, count: int) -> Vector3:
	var centre := Vector3(cos(squadron_patrol_angle) * 0.30, -0.10 + sin(squadron_patrol_angle) * 0.20, 0.0)
	var spread := float(slot) - 0.5 * float(maxi(1, count) - 1)
	return centre + Vector3(spread * formation_spacing, -absf(spread) * formation_spacing * 0.45, 0.0)

func _interceptor_target_of(interceptor: Dictionary, excluded: Array[String], kinds: Array) -> Dictionary:
	var closest: Dictionary = {}
	var distance := INF
	for other in contacts:
		if other.faction != "hostile" or other.kind not in kinds or other.id in excluded:
			continue
		var candidate: float = interceptor.position.distance_to(other.position)
		# Hold a central defensive screen instead of chasing freshly launched
		# fighters beside the distant Enemy Carriers.
		if other.kind == "drone" and protect_smart_drones and other.get("phase", "") == "protect":
			# 1.0.7: in the round, Interceptors defend every support ship, even high on the scope.
			pass
		elif other.kind == "drone":
			if other.position.y > 0.42 and other.get("phase", "") != "return":
				continue
			candidate += Vector2(other.position.x, other.position.y).length() * 1.5
			# Returning Attack Drones are low on fuel and ammunition: easier prey.
			if other.get("phase", "") == "return":
				candidate *= 0.5
		if other.kind == "convoy_breacher":
			# 1.0.7: a latched Breacher is the top job; one on its way comes next.
			candidate *= 0.25 if other.get("breach_state", "") == "latched" else 0.6
		if other.kind == "breacher":
			if other.position.y > 0.42:
				continue
			candidate *= 0.08 if other.phase in ["hacking", "draining"] else 0.5
		# Nearby incoming missiles take priority, but still require physical pursuit.
		if other.kind == "missile" and other.position.distance_to(own_ship_position) < 0.65:
			candidate *= 0.35
		if other.id == interceptor.target_id:
			candidate *= 0.55
		elif squadrons_split_to_engage:
			# 1.07: spread out over targets squadron mates are not already chasing.
			var claims: int = interceptor_claims.get(other.id, 0)
			if other.kind in ["breacher", "siege_ship", "convoy_breacher"]:
				if claims >= max_interceptors_per_tough_target:
					candidate *= squadron_spread_penalty
			elif claims >= 1:
				candidate *= squadron_spread_penalty
		if candidate < distance:
			distance = candidate
			closest = other
	return closest

func _update_interceptors(delta: float) -> void:
	var removed: Array[String] = []
	# 1.07: who is chasing what, and the shared patrol formation for idle Interceptors.
	interceptor_claims.clear()
	var patrol_slots: Array[String] = []
	if squadrons_split_to_engage:
		squadron_patrol_angle += delta * 0.16
		for other in contacts:
			if Icons.is_interceptor(other.kind) and other.get("phase", "") != "return":
				var claimed: String = other.get("target_id", "")
				if not claimed.is_empty():
					interceptor_claims[claimed] = int(interceptor_claims.get(claimed, 0)) + 1
				elif other.get("phase", "") == "patrol":
					patrol_slots.append(other.id)
		patrol_slots.sort()
	for interceptor in contacts.duplicate():
		if not Icons.is_interceptor(interceptor.kind):
			continue
		interceptor.heavy_fire_remaining = maxf(0.0, interceptor.get("heavy_fire_remaining", 0.0) - delta)
		interceptor.drone_fire_remaining = maxf(0.0, interceptor.get("drone_fire_remaining", 0.0) - delta)
		interceptor.res_fire_remaining = maxf(0.0, interceptor.get("res_fire_remaining", 0.0) - delta)
		# 1.2.9: in Protect the fleet Interceptors can stay out all round (Interceptors Stay Out).
		if interceptor.age >= sortie_seconds and not (protect_interceptors_stay_out and protect_active()):
			interceptor.phase = "return"
			interceptor.target_id = ""
		if interceptor.phase == "return":
			var home := launch_origin(interceptor.lane)
			_steer(interceptor, home, interceptor_speed * fighter_speed_factor(), delta)
			if interceptor.position.distance_to(home) < 0.025:
				removed.append(interceptor.id)
				interceptors_returned += 1
				_hold_after_landing("interceptor")
				_set_status("INTERCEPTOR RECOVERED | SORTIE COMPLETE, NOT DESTROYED", 3.0)
			continue
		if interceptor.phase == "launch":
			var entry := Vector3(interceptor.lane / 320.0, -0.68, -0.35)
			_steer(interceptor, entry, interceptor_speed * fighter_speed_factor(), delta)
			if interceptor.position.distance_to(entry) < 0.025:
				interceptor.phase = "intercept"
			continue
		var old_claim: String = interceptor.get("target_id", "")
		if squadrons_split_to_engage and not old_claim.is_empty():
			interceptor_claims[old_claim] = maxi(0, int(interceptor_claims.get(old_claim, 0)) - 1)
		var target := _hostile_target(interceptor, removed)
		if not target.is_empty():
			interceptor.phase = "intercept"
			interceptor.target_id = target.id
			if squadrons_split_to_engage:
				interceptor_claims[target.id] = int(interceptor_claims.get(target.id, 0)) + 1
			# 1.2.9: Protect the fleet dogfights (round Attack Drones only).
			if protect_dogfights and target.get("phase", "") == "protect":
				_protect_interceptor_dogfight(interceptor, target, delta, removed)
				continue
			var chase := pulse_chase_speed_factor if float(target.get("frozen", 0.0)) > 0.0 else 1.0
			_steer(interceptor, target.position, interceptor_speed * fighter_speed_factor() * chase, delta)
			if target.kind == "carrier":
				# 1.1.0 PULSE BOMB: Interceptors attack frozen Enemy Carriers (Siege Ship hit rate).
				if interceptor.position.distance_to(target.position) <= 0.08 and interceptor.res_fire_remaining <= 0.0:
					_hit_carrier(target, interceptor_siege_damage)
					interceptor.res_fire_remaining = maxf(0.5, interceptor_siege_hit_interval) * fire_interval_factor()
				continue
			if target.kind == "siege_ship":
				if interceptor.position.distance_to(target.position) <= 0.08 and interceptor.res_fire_remaining <= 0.0:
					_hit_siege(target, interceptor_siege_damage, "interceptor")
					interceptor.res_fire_remaining = maxf(0.5, interceptor_siege_hit_interval) * fire_interval_factor()
				continue
			if interceptor.position.distance_to(target.position) <= 0.05:
				if target.kind == "convoy_breacher":
					if interceptor.heavy_fire_remaining <= 0.0:
						interceptor.heavy_fire_remaining = 0.7 * fire_interval_factor()
						if _hit_convoy_breacher(interceptor, target):
							removed.append(target.id)
							interceptor.target_id = ""
					continue
				if target.kind == "breacher":
					if interceptor.heavy_fire_remaining <= 0.0:
						_hit_breacher(target)
						interceptor.heavy_fire_remaining = 0.8 * fire_interval_factor()
					continue
				# 1.2.3 Protect the fleet: the Attack Drone fires back once at each Interceptor that engages it.
				if target.get("phase", "") == "protect" and _protect_return_fire(interceptor, target):
					continue
				# 1.2.1: a Attack Drone takes Attack Drone Interceptor Hits before it is destroyed.
				# 1.2.3: Protect the fleet Attack Drones carry their own (larger) hit count.
				if target.kind == "drone" and (drone_interceptor_hits > 1 or target.get("phase", "") == "protect"):
					if interceptor.drone_fire_remaining > 0.0:
						continue
					interceptor.drone_fire_remaining = maxf(0.1, drone_interceptor_hit_interval) * fire_interval_factor()
					target.interceptor_hits = int(target.get("interceptor_hits", drone_interceptor_hits)) - roundi(pulse_damage_factor(target))
					if target.interceptor_hits > 0:
						impacts.append({"position": target.position, "age": 0.0})
						if target.get("phase", "") == "protect":
							_play_protect_sound("interceptor_hit")
						continue
				# Prototype outcome: reaching a hostile clears that contact.
				removed.append(target.id)
				_award_destroyed(target)
				impacts.append({"position": target.position, "age": 0.0})
				intercepted_count += 1
				if target.kind == "missile":
					missile_intercepts += 1
					_explode(target.position, "missile")
				hostile_intercepted.emit(interceptor.id, target.id)
				interceptor.target_id = ""
		else:
			interceptor.phase = "patrol"
			interceptor.target_id = ""
			if squadrons_split_to_engage:
				# 1.07: idle Interceptors fly back and rejoin one shared patrol formation.
				if interceptor.id not in patrol_slots:
					patrol_slots.append(interceptor.id)
					patrol_slots.sort()
				_steer(interceptor, formation_point(patrol_slots.find(interceptor.id), patrol_slots.size()), interceptor_speed * fighter_speed_factor(), delta)
				continue
			interceptor.patrol_angle += delta * 0.16
			var patrol := Vector3(cos(interceptor.patrol_angle) * 0.30,
				-0.10 + sin(interceptor.patrol_angle) * 0.20, 0.0)
			_steer(interceptor, patrol, interceptor_speed * fighter_speed_factor(), delta)
	for index in range(contacts.size() - 1, -1, -1):
		if contacts[index].id in removed:
			contacts.remove_at(index)

## 1.2.4: where a contact sits on the scope, in sphere radii from the dome centre (y down).
func scope_point(world: Vector3) -> Vector2:
	var focal := maxf(2.0, perspective_distance)
	return Vector2(world.x, -world.y) * (focal / (focal + world.z * depth_strength))

## 1.2.4 Keep Play In Wedge: a contact that has been inside the scope outline and
## drifts out is moved back to the nearest point inside, and stops moving outward.
func _keep_play_in_wedge() -> void:
	if not keep_play_in_wedge:
		return
	var focal := maxf(2.0, perspective_distance)
	for contact in contacts:
		var world: Vector3 = contact.position
		var depth_scale := focal / (focal + world.z * depth_strength)
		var point := Vector2(world.x, -world.y) * depth_scale
		var inside := ScopeShape.clamp_inside(point, wedge_margin)
		if point.distance_to(inside) <= 0.000001:
			contact.in_scope = true
			continue
		if not contact.get("in_scope", false):
			continue
		var fixed := Vector3(inside.x / depth_scale, -inside.y / depth_scale, world.z)
		var outward := (world - fixed).normalized()
		contact.position = fixed
		wedge_corrections += 1
		if contact.has("velocity"):
			var velocity: Vector3 = contact.velocity
			var along := velocity.dot(outward)
			if along > 0.0:
				contact.velocity = velocity - outward * along

func projection(world: Vector3) -> Dictionary:
	var dome := get_parent()
	var radius: float = dome.sphere_radius
	var focal := maxf(2.0, perspective_distance)
	var depth_scale := focal / (focal + world.z * depth_strength)
	return {
		"point": size * 0.5 + Vector2(world.x, -world.y) * radius * depth_scale,
		"scale": depth_scale * (radius / 320.0) * icon_size
	}

func _draw() -> void:
	for impact in impacts:
		var point: Vector2 = projection(impact.position).point
		var color := Color(1.0, 0.45, 0.3, (1.0 - impact.age / 0.45) * 0.8)
		if impact.get("battery", false):
			color = Color(1.0, 0.89, 0.42, (1.0 - impact.age / 0.45) * 0.95)
			draw_arc(point, 5.0 + impact.age * 40.0, 0.0, TAU, 24, color, 2.0, true)
			draw_circle(point, 4.0 * (1.0 - impact.age / 0.45), color)
			continue
		draw_arc(point, 7.0 + impact.age * 20.0, 0.0, TAU, 24, color, 1.0, true)
	var ordered := contacts.duplicate()
	# Paint far contacts first; near contacts remain on top.
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.position.z > b.position.z)
	var font := ThemeDB.fallback_font
	_protect_reserve_labels(font)
	# 1.06: ships first, then explosions, then every missile, nuke and flak shot
	# on top so they are never hidden on a crowded scope.
	var projectiles: Array = []
	for contact in ordered:
		if contact.kind in PROJECTILE_KINDS:
			projectiles.append(contact)
			continue
		_draw_contact(contact, font)
	_draw_interceptor_squadrons(font)
	_draw_convoy_effects()
	_draw_explosions()
	_draw_pulse(font)
	# 1.2.0: rest tally above the rings and ships, below missiles still in flight.
	_draw_rest_tally(font)
	for contact in projectiles:
		_draw_contact(contact, font)
	_draw_jump_flash()

## Missiles, nukes and flak: drawn after (on top of) everything else (1.06).
const PROJECTILE_KINDS := ["missile", "own_missile", "gunship_missile", "nuke", "flak"]

## 1.07: the tag shown under a contact ("" = none). Short tags unless Show Full Tags.
func contact_tag(contact: Dictionary) -> String:
	var text: String = contact.id
	if contact.get("faction", "") == "civilian":
		text = "SUPPORT %d%%" % ceili(100.0 * clampf(float(contact.get("hull", 1.0)), 0.0, 1.0))
	elif contact.kind == "unknown":
		text = "IDENTIFYING"
	elif contact.kind == "carrier":
		text = "ENEMY CARRIER %d%%" % ceili(100.0 * contact.hits_remaining / contact.max_hits)
	elif contact.kind == "siege_ship":
		text = "SIEGE SHIP %d%%" % ceili(100.0 * contact.hits_remaining / contact.max_hits)
	elif contact.kind == "nuke":
		text = "NUCLEAR"
		if contact.has("nuke_hits") and contact.nuke_hits < contact.nuke_max_hits:
			text += " %d%%" % ceili(100.0 * contact.nuke_hits / contact.nuke_max_hits)
	elif contact.kind == "convoy_breacher":
		text = "HULL DRAIN" if contact.get("breach_state", "") == "latched" else "BREACHER"
	elif contact.kind == "breacher":
		text = "BREACHER"
		if contact.phase == "hacking":
			text = "HACKING %ds" % ceili(contact.hack_remaining)
		elif contact.phase == "draining":
			text = "HULL DRAIN"
		elif contact.phase == "emp":
			text = "EMP OVERLOAD"
	elif contact.kind in ["interceptor", "drone", "gunship"] and not show_full_tags:
		text = public_craft_name(contact)
	elif contact.kind in ["missile", "own_missile", "gunship_missile"] and not show_full_tags:
		text = ""
	elif contact.kind in ["interceptor", "drone", "gunship"]:
		text = public_craft_name(contact) + " " + contact.id
		if contact.get("phase", "") == "return":
			text += " RTB"
		# Damaged Interceptors and Gunships show their remaining strength.
		if contact.kind in ["interceptor", "gunship"] and int(contact.get("health", 1)) < int(contact.get("max_health", 1)):
			text += " %d%%" % fighter_health_percent(contact)
	elif contact.kind in ["flak", "stealth_nuke"]:
		text = ""
	elif contact.kind == "stealth_interceptor":
		text = "STEALTH"
	return text

func public_craft_name(contact: Dictionary) -> String:
	if is_tender(contact):
		if protect_tender_hull and float(contact.get("hull", 1.0)) < 0.995:
			return "REPAIR TENDER %d%%" % ceili(100.0 * clampf(float(contact.hull), 0.0, 1.0))
		return "REPAIR TENDER"
	return {"interceptor": "INTERCEPTOR", "drone": "ATTACK DRONE",
		"gunship": "GUNSHIP"}.get(contact.kind, "CONTACT")

func contact_font_size(kind: String) -> int:
	var result := label_font_size + (2 if kind in ["carrier", "siege_ship", "unknown"] else 0)
	if kind in ["carrier", "siege_ship", "unknown"]:
		# Fit the longer original names in the unchanged capital-label footprint.
		var text := "SIEGE SHIP 100%" if kind == "siege_ship" else "ENEMY CARRIER 100%"
		var legacy_key := LegacyNames.footprint_text(kind)
		var room := ThemeDB.fallback_font.get_string_size(legacy_key + " 100%", HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size + 2).x
		while result > 14 and ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, result).x > room:
			result -= 1
	return result

func _draw_contact(contact: Dictionary, font: Font) -> void:
	if contact.kind == "interceptor" and squadron_of(contact.id) != -1:
		return  # drawn once as a squadron
	var projected := projection(contact.position)
	var point: Vector2 = projected.point
	var marker_scale: float = projected.scale * size_for_kind(contact.kind)
	var color := display_color(contact)
	var state_alpha: float = color.a
	if contact.kind == "nuke":
		color = nuke_marker_color(contact)
		draw_arc(point, 16.0 * marker_scale, 0.0, TAU, 32, color, 2.0, true)
	# A short arrival flash, not a repeated spawn or repeated sound.
	var flash := maxf(0.0, 1.0 - contact.age / 0.7)
	color.a = (0.88 + 0.12 * flash) * state_alpha
	if flash > 0.0:
		var halo := color
		halo.a = flash * 0.38
		draw_arc(point, (18.0 + (1.0 - flash) * 9.0) * marker_scale, 0.0, TAU, 40, halo, 1.0, true)
	if contact.kind in ["missile", "own_missile", "gunship_missile", "nuke", "flak", "stealth_nuke"]:
		var aim: Vector2 = projection(contact.get("target_position", own_ship_position)).point
		var direction := point.direction_to(aim)
		var side := Vector2(-direction.y, direction.x)
		var length_scale := 1.8 if contact.kind in ["nuke", "stealth_nuke"] else (0.65 if contact.kind in ["gunship_missile", "flak"] else 1.0)
		var arrow := PackedVector2Array([
			point + direction * 6.0 * length_scale,
			point - direction * 4.0 * length_scale + side * 2.5 * length_scale,
			point - direction * 4.0 * length_scale - side * 2.5 * length_scale])
		draw_colored_polygon(arrow, color)
		# Smoothing: an anti-aliased edge softens the filled triangle's jagged sides.
		arrow.append(arrow[0])
		draw_polyline(arrow, color, 1.0, true)
		draw_line(point - direction * 5.0, point - direction * 12.0, Color(color, 0.45), 1.0, true)
	else:
		var icon_kind: String = "repair_tender" if is_tender(contact) else contact.kind
		Icons.draw_icon(self, icon_kind, point, marker_scale, color)
	if show_labels:
		var font_size := contact_font_size(contact.kind)
		var text: String = contact_tag(contact)
		if text.is_empty():
			return
		var label_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var label_point := point + Vector2(-label_size.x * 0.5, 29.0 * marker_scale)
		if String(contact.kind).begins_with("civilian_"):
			label_point = point + Vector2(-label_size.x * 0.5, 22.0 * marker_scale)
		if contact.kind == "nuke":
			# Above the warhead, so it stays clear of a Gunship chasing it from below.
			label_point = point + Vector2(-label_size.x * 0.5, -22.0 * marker_scale)
		elif contact.kind == "breacher" and contact.get("phase", "") in ["hacking", "draining", "emp"]:
			# 1.09: above a parked Breacher, clear of the ship console below it.
			label_point = point + Vector2(-label_size.x * 0.5, -24.0 * marker_scale)
		# 1.2.9: Protect the fleet labels move clear of each other (civilian labels stay put).
		if protect_label_declutter and protect_active() and contact.get("faction", "") != "civilian":
			label_point = _protect_place_label(label_point, label_size)
		if label_point.is_finite():
			draw_string_outline_and_text(font, label_point, text, font_size, label_color(color))
		if civilian_hull_bar and contact.get("faction", "") == "civilian":
			_draw_civilian_hull_bar(contact, marker_scale, label_point, label_size)
	if contact.kind == "breacher" and contact.get("phase", "") == "emp":
		_draw_emp_sparks(point, marker_scale, contact)

func label_color(icon_color: Color) -> Color:
	# Slightly lighter than the icon, at full strength unless the ship is flashing.
	var lighter := Color(icon_color.r, icon_color.g, icon_color.b).lerp(Color.WHITE, clampf(label_brighten, 0.0, 0.6))
	lighter.a = clampf(icon_color.a / 0.88, 0.0, 1.0)
	return lighter

func draw_string_outline_and_text(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	if label_outline_size > 0:
		var edge := label_outline_color
		edge.a *= color.a
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_outline_size, edge)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func hull_percent() -> int:
	if is_defeated():
		return 0
	return clampi(ceili(hull / maxf(1.0, max_hull) * 100.0), 1, 100)

func jump_percent() -> int:
	if jump_recharge_remaining <= 0.0:
		return 100
	# 1.08: measured against the recharge in progress (normal, or the rebuild after a breach).
	var total := jump_breach_rebuild_total if jump_rebuilding_after_breach else jump_recharge_seconds
	return clampi(1 + floori(99.0 * (1.0 - jump_recharge_remaining / maxf(1.0, total))), 1, 99)

func _update_repair(delta: float) -> void:
	if is_defeated() or hull >= max_hull:
		return
	var available := maxf(0.0, delta - repair_delay_remaining)
	repair_delay_remaining = maxf(0.0, repair_delay_remaining - delta)
	repair_elapsed += available
	while repair_elapsed >= maxf(1.0, repair_tick_seconds):
		repair_elapsed -= maxf(1.0, repair_tick_seconds)
		hull = minf(max_hull, hull + max_hull * 0.01)
		if hull >= max_hull:
			repair_elapsed = 0.0
			break

func count_base_drones(id: String, include_pending: bool = false) -> int:
	var total := 0
	for contact in contacts:
		if contact.kind == "drone" and contact.get("origin_id", "") == id:
			total += 1
	if include_pending:
		for request in pending:
			if request.kind == "drone" and request.get("origin_id", "") == id:
				total += 1
	return total

func _identify_carrier(contact: Dictionary) -> void:
	if contact.kind != "unknown":
		return
	# Preserve track ID and exact position; only classification changes.
	contact.kind = "carrier"
	contact.faction = "hostile"
	contact.hits_remaining = float(maxi(2, scaled_hits(carrier_hits_to_destroy)) + set_carrier_hits_bonus())
	contact.max_hits = contact.hits_remaining
	contact.nuclear_launched = false
	contact.nuclear_timer = maxf(1.0, nuclear_launch_delay) * nuclear_delay_factor() / attack_rate()
	contact.flak_timer = maxf(2.0, carrier_flak_interval) / attack_rate()
	contact.heavy_timer = maxf(5.0, heavy_launch_interval) * heavy_interval_factor() / attack_rate()
	identification_count += 1
	if klaxon_enabled:
		klaxon_queue.append(contact.id)
	_set_status("HOSTILE ENEMY CARRIER IDENTIFIED | AUTOMATIC MISSILES ARMED", 3.0)
	carrier_identified.emit(contact.id)
	_update_klaxon()

func _update_klaxon() -> void:
	klaxon_player.volume_db = klaxon_volume_db
	if not klaxon_enabled:
		klaxon_queue.clear()
		return
	if count_kind("nuke") > 0:
		return
	# Wait while the Siege Ship alert plays so the two never overlap.
	if not klaxon_player.playing and (siege_alert_player == null or not siege_alert_player.playing):
		while not klaxon_queue.is_empty():
			var id: String = klaxon_queue.pop_front()
			if not find_contact(id).is_empty():
				klaxon_player.play()
				klaxon_count += 1
				break

func _update_own_weapons(delta: float) -> void:
	if is_defeated() or safe_remaining > 0.0 or protect_active():
		return
	# Work from IDs: a hit may remove its target and other missiles safely.
	var missile_ids: Array[String] = []
	for contact in contacts:
		if contact.kind in ["own_missile", "gunship_missile"]:
			missile_ids.append(contact.id)
	for id in missile_ids:
		var missile := find_contact(id)
		if missile.is_empty():
			continue
		var target := find_contact(missile.target_id)
		if target.is_empty() or target.kind not in MISSILE_TARGET_KINDS:
			# 1.07: turn toward the nearest valid enemy instead of being wasted.
			target = missile_retarget(missile)
			if target.is_empty():
				_remove_contact(id)
				continue
			missile.target_id = target.id
			missile_retargets += 1
		missile.target_position = target.position
		missile.position = missile.position.move_toward(target.position, delta * movement_speed * missile_flight_speed(missile))
		if missile.position.distance_to(target.position) <= 0.025:
			_remove_contact(id)
			if target.kind == "nuke":
				_ship_hit_nuke(target)
			elif target.kind == "breacher":
				_hit_breacher(target)
			elif target.kind == "siege_ship":
				_hit_siege(target, missile.get("damage", 1.0), "gunship" if missile.kind == "gunship_missile" else "ship")
			else:
				_hit_carrier(target, missile.get("damage", 1.0), missile.kind == "gunship_missile")
	# 0.1.2 quick pair: the second missile of a Double Missile volley, a moment later.
	if own_pair_remaining > 0.0:
		own_pair_remaining = maxf(0.0, own_pair_remaining - delta)
		if own_pair_remaining <= 0.0 and own_weapons_enabled and double_missile_active() and count_kind("own_missile") < max_own_missiles:
			if _fire_ship_missile():
				own_pair_launches += 1
	own_fire_remaining = maxf(0.0, own_fire_remaining - delta)
	if not own_weapons_enabled or own_fire_remaining > 0.0 or count_kind("own_missile") >= max_own_missiles:
		return
	# One missile per volley, or two with the Double Missile bonus.
	var fired := 0
	_volley_carrier_ids.clear()
	var shots := missiles_per_volley()
	var pair_later := double_missile_quick_pair and shots > 1
	if pair_later:
		shots = 1
	for shot in range(shots):
		if count_kind("own_missile") >= max_own_missiles or not _fire_ship_missile():
			break
		fired += 1
	if fired > 0:
		own_fire_remaining = maxf(2.0, ship_missile_gap()) * fire_interval_factor()
		if pair_later:
			own_pair_remaining = maxf(0.01, double_missile_pair_seconds)
	# Own weapons are not newly detected contacts: no arrival beep.

## 1.05: ship missiles per volley (2 once the Double Missile bonus is active).
func missiles_per_volley() -> int:
	return 2 if double_missile_active() else 1

## Picks one target and launches one ship missile. Returns false when nothing is in reach.
## 1.07: the nearest enemy a ship or Gunship missile may attack. A nuke is skipped when
## enough ship missiles are already flying at it for the hits it still needs.
func missile_retarget(missile: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var closest := INF
	for contact in contacts:
		if contact.get("faction", "") != "hostile" or contact.kind not in MISSILE_TARGET_KINDS:
			continue
		if contact.kind == "nuke" and missile.kind == "own_missile" and _missiles_at(contact.id) >= nuke_hits_left(contact):
			continue
		var gap: float = missile.position.distance_to(contact.position)
		if gap < closest:
			closest = gap
			best = contact
	return best

func _fire_ship_missile() -> bool:
	var target := ship_nuke_target()
	if not target.is_empty():
		_launch_ship_missile(target)
		return true
	# 1.2.3: Breachers hacking or draining the ship come next (draining first,
	# then the one closest to finishing its hack); one missile per remaining hit point.
	if ship_missiles_target_hacking:
		var urgency := INF
		for contact in contacts:
			if contact.kind != "breacher" or contact.get("phase", "") not in ["hacking", "draining"]:
				continue
			if _missiles_at(contact.id) >= contact.health:
				continue
			var left: float = -1.0 if contact.phase == "draining" else float(contact.get("hack_remaining", 0.0))
			if left < urgency:
				urgency = left
				target = contact
		if not target.is_empty():
			_launch_ship_missile(target)
			return true
	# Close Breachers come next; one missile in flight per remaining hit point.
	var nearest := INF
	for contact in contacts:
		if contact.kind != "breacher":
			continue
		var gap: float = contact.position.distance_to(own_ship_position)
		if gap <= ship_missile_heavy_range and gap < nearest and _missiles_at(contact.id) < contact.health:
			nearest = gap
			target = contact
	if target.is_empty():
		if ship_missiles_spread_carriers and active_difficulty >= 1:
			target = _spread_carrier_target()
		else:
			for contact in contacts:
				if contact.kind == "carrier" and (target.is_empty() or contact.hits_remaining < target.hits_remaining):
					target = contact
		# With a Siege Ship present, every second missile goes to it
		# (all of them when no Enemy Carrier remains).
		for contact in contacts:
			if contact.kind == "siege_ship" and (target.is_empty() or own_volley_count % 2 == 1):
				target = contact
	if target.is_empty():
		return false
	if target.kind in ["carrier", "siege_ship"]:
		own_volley_count += 1
	_launch_ship_missile(target)
	return true

## 0.1.2 spread targeting: weakest Enemy Carrier after the missiles already flying at it; one
## not yet picked in this volley first; fully covered Enemy Carriers only when nothing else is left.
func _spread_carrier_target() -> Dictionary:
	var best: Dictionary = {}
	var best_key := INF
	for contact in contacts:
		if contact.kind != "carrier":
			continue
		var left: float = float(contact.hits_remaining) - _missiles_at(contact.id)
		var key := left
		if left <= 0.0:
			key += 1000.0
		if contact.id in _volley_carrier_ids:
			key += 500.0
		if key < best_key:
			best_key = key
			best = contact
	if not best.is_empty():
		_volley_carrier_ids.append(best.id)
	return best

func _launch_ship_missile(target: Dictionary) -> void:
	var id := _new_id("P")
	contacts.append({"id": id, "kind": "own_missile", "faction": "friendly",
		"position": own_ship_position, "age": 0.0, "target_id": target.id,
		"target_position": target.position})

## Hits a nuke still needs (difficulty toughness applies), the same count Gunships use.
func nuke_hits_left(nuke: Dictionary) -> int:
	return int(nuke.get("nuke_hits", scaled_hits(nuclear_hit_points)))

## 1.05: share of its flight a nuke has covered (0 at launch, 1 at the ship).
func nuke_progress(nuke: Dictionary) -> float:
	var gap: float = nuke.position.distance_to(own_ship_position)
	var total: float = nuke.get("launch_distance", gap)
	if total <= 0.0:
		return 0.0
	return clampf(1.0 - gap / total, 0.0, 1.0)

## 1.05: the closest nuke past the target point that still needs more ship missiles
## than are already flying at it (never sends more missiles than hits left).
func ship_nuke_target() -> Dictionary:
	var target: Dictionary = {}
	if not ship_missiles_target_nukes:
		return target
	var closest := INF
	for contact in contacts:
		if contact.kind != "nuke":
			continue
		var gap: float = contact.position.distance_to(own_ship_position)
		if nuke_progress(contact) > ship_nuke_target_fraction and gap < closest and _missiles_at(contact.id) < nuke_hits_left(contact):
			closest = gap
			target = contact
	return target

## 1.05: a ship missile reaches a nuke. One hit, the same as a Gunship hit.
func _ship_hit_nuke(target: Dictionary) -> void:
	if target.is_empty() or find_contact(target.id).is_empty():
		return
	if not target.has("nuke_hits"):
		target.nuke_hits = scaled_hits(nuclear_hit_points)
		target.nuke_max_hits = target.nuke_hits
	target.nuke_hits -= 1
	nuke_hits_landed += 1
	ship_nuke_hits += 1
	impacts.append({"position": target.position, "age": 0.0})
	if target.nuke_hits > 0:
		_set_status("SHIP MISSILE HIT NUCLEAR MISSILE | %d MORE TO DESTROY" % target.nuke_hits, 2.0)
		return
	_award_destroyed(target)
	nuclear_intercepts += 1
	ship_nuke_kills += 1
	_explode(target.position, "nuke")
	_remove_contact(target.id)
	_set_status("SHIP MISSILE DESTROYED NUCLEAR MISSILE", 4.0)

func _missiles_at(target_id: String) -> int:
	var total := 0
	for contact in contacts:
		if contact.kind == "own_missile" and contact.get("target_id", "") == target_id:
			total += 1
	return total

func _hit_carrier(base: Dictionary, damage: float = 1.0, from_gunship: bool = false) -> void:
	if base.is_empty() or base.kind != "carrier" or find_contact(base.id).is_empty():
		return
	base.hits_remaining -= maxf(0.0, damage) * pulse_damage_factor(base)
	if from_gunship:
		gunship_missile_hits += 1
	else:
		own_missile_hits += 1
	impacts.append({"position": base.position, "age": 0.0})
	if base.hits_remaining > 0:
		return
	var id: String = base.id
	_award_destroyed(base)
	_remove_contact(id)
	for index in range(pending.size() - 1, -1, -1):
		if pending[index].get("origin_id", "") == id:
			pending.remove_at(index)
	for index in range(contacts.size() - 1, -1, -1):
		if contacts[index].kind in ["own_missile", "gunship_missile"] and contacts[index].target_id == id:
			contacts[index].target_id = ""
	klaxon_queue.erase(id)
	carriers_destroyed += 1
	_set_status("ENEMY CARRIER DESTROYED | REMAINING ATTACK DRONES STILL ACTIVE", 3.0)
	carrier_destroyed.emit(id)

func _remove_contact(id: String) -> void:
	for index in range(contacts.size() - 1, -1, -1):
		if contacts[index].id == id:
			contacts.remove_at(index)
			return

func _effect_player(node_name: String, effect: String, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = BattleAudio.synth(effect)
	player.volume_db = volume
	add_child(player)
	return player

func _stop_special_audio() -> void:
	for player in [battery_player, jump_player, nuclear_player, nuclear_beep_player, impact_player, siege_alert_player, firewall_player]:
		if is_instance_valid(player):
			player.stop()
	nuclear_alert_queue.clear()
	nuclear_alert_contact_id = ""
	nuclear_alarm_remaining = 0.0

func _update_battery(delta: float) -> void:
	# Use meter: drains quickly while firing, recharges slowly whenever idle.
	prox_cooldown_remaining = 0.0
	battery_player.volume_db = battery_volume_db
	battery_player.pitch_scale = battery_sound_speed
	var full := maxf(0.1, prox_burst_seconds)
	if prox_active:
		battery_idle = 0.0
		prox_burst_remaining = maxf(0.0, prox_burst_remaining - delta)
		if prox_burst_remaining <= 0.0:
			_end_battery_burst()
		return
	if prox_burst_remaining >= full:
		prox_burst_remaining = full
		return
	var wait := maxf(0.0, battery_recharge_delay - battery_idle)
	battery_idle += delta
	var charging := maxf(0.0, delta - wait)
	if charging > 0.0:
		var was_full := prox_burst_remaining >= full
		prox_burst_remaining = minf(full, prox_burst_remaining + charging * full / battery_recharge_time())
		if not was_full and prox_burst_remaining >= full:
			_set_status("DEFENSE SHIELD FULLY CHARGED", 2.0)

## Full recharge time for the current battle's difficulty (Normal 24 s, Easy 19.2 s, Hard 31.2 s).
func battery_recharge_time() -> float:
	return maxf(1.0, battery_recharge_seconds * difficulty_factor(easy_battery_recharge, hard_battery_recharge))

func battery_percent() -> float:
	return 100.0 * clampf(prox_burst_remaining / maxf(0.1, prox_burst_seconds), 0.0, 1.0)

func can_fire_battery() -> bool:
	return not protect_active() and not is_defeated() and safe_remaining <= 0.0 and (prox_active or battery_percent() >= maxf(1.0, battery_restart_percent))

func _end_battery_burst() -> void:
	prox_active = false
	battery_idle = 0.0
	battery_player.stop()
	if prox_burst_remaining <= 0.0:
		prox_burst_remaining = 0.0
		_set_status("DEFENSE SHIELD EMPTY | RECHARGING", 2.0)
	else:
		_set_status("DEFENSE SHIELD STOPPED | RECHARGING FROM %d%%" % int(battery_percent()), 2.0)

func count_returning(kind: String) -> int:
	var count := 0
	for contact in contacts:
		if contact.kind == kind and contact.get("phase", "") == "return":
			count += 1
	return count

func _launch_nuclear(base: Dictionary) -> String:
	if is_defeated() or safe_remaining > 0.0 or base.is_empty() or base.kind != "carrier":
		return ""
	if find_contact(base.id).is_empty() or base.get("nuclear_launched", false):
		return ""
	base.nuclear_launched = true  # Lifetime latch; never replenished on this track.
	var origin: Vector3 = base.position + base.position.direction_to(own_ship_position) * carrier_emission_radius
	var id := _new_id("N")
	contacts.append({"id": id, "kind": "nuke", "faction": "hostile",
		"position": origin, "age": 0.0, "origin_id": base.id, "target_position": own_ship_position,
		"launch_distance": origin.distance_to(own_ship_position), "speed_bonus": nuke_speed_bonus()})
	nuclear_launches += 1
	base.nukes_fired = int(base.get("nukes_fired", 0)) + 1
	if carrier_second_nuke and active_difficulty >= 1 and base.nukes_fired < 2:
		# 0.1.2: re-arm once, after this Enemy Carrier's own random cool-down.
		var low := normal_second_nuke_min_seconds if active_difficulty == 1 else hard_second_nuke_min_seconds
		var high := normal_second_nuke_max_seconds if active_difficulty == 1 else hard_second_nuke_max_seconds
		base.nuclear_launched = false
		base.nuclear_timer = rng.randf_range(minf(low, high), maxf(low, high)) * nuclear_delay_factor()
	var bonus: float = contacts[-1].speed_bonus
	nuke_speed_bonuses.append(bonus)
	battle_event.emit("nuke %s launched | speed bonus +%.1f%%" % [id, bonus * 100.0])
	nuclear_alert_queue.append(id)
	_set_status("NUCLEAR LAUNCH DETECTED | LAUNCH GUNSHIP OR JUMP", 6.0)
	return id

func _update_nuclear_alarm(delta: float) -> void:
	nuclear_player.volume_db = nuclear_alert_volume_db
	nuclear_player.pitch_scale = nuclear_alert_speed
	nuclear_beep_player.volume_db = nuclear_beep_volume_db
	if count_kind("nuke") == 0:
		nuclear_player.stop()
		nuclear_beep_player.stop()
		nuclear_alert_queue.clear()
		nuclear_alert_contact_id = ""
		nuclear_alarm_remaining = 0.0
		return
	# A threat that was intercepted or hit no longer owns an active warning.
	if not nuclear_alert_contact_id.is_empty() and find_contact(nuclear_alert_contact_id).is_empty():
		nuclear_player.stop()
		nuclear_alert_contact_id = ""
	if nuclear_player.playing:
		return
	while not nuclear_alert_queue.is_empty():
		var id: String = nuclear_alert_queue.pop_front()
		if find_contact(id).is_empty():
			continue
		nuclear_alert_contact_id = id
		klaxon_player.stop()
		nuclear_beep_player.stop()
		nuclear_player.play()
		nuclear_alert_count += 1
		nuclear_alarm_remaining = 0.0
		return
	# Only one approach-beep train, following the physically nearest nuke.
	var interval := nuclear_beep_interval()
	nuclear_alarm_remaining = minf(nuclear_alarm_remaining, interval) - delta
	if nuclear_alarm_remaining <= 0.0:
		nuclear_beep_player.play()
		nuclear_beep_count += 1
		nuclear_alarm_remaining = interval

func nuclear_beep_interval() -> float:
	var nearest: Dictionary = {}
	var distance := INF
	for contact in contacts:
		if contact.kind == "nuke":
			var candidate: float = contact.position.distance_to(own_ship_position)
			if candidate < distance:
				distance = candidate
				nearest = contact
	if nearest.is_empty():
		return nuclear_beep_far_seconds
	var fraction := clampf(distance / maxf(0.01, nearest.get("launch_distance", distance)), 0.0, 1.0)
	return lerpf(nuclear_beep_near_seconds, maxf(nuclear_beep_near_seconds, nuclear_beep_far_seconds), fraction)

## 1.0.5: launches one ready Gunship. Other ready Gunships then wait the launch cooldown;
## Gunships still counting down keep their own countdown.
func launch_gunship() -> int:
	if gunships_ready() <= 0:
		return 0
	var id := _spawn_gunship()
	if id.is_empty():
		return 0
	_hold_ready(gunship_waits, gunships_ready(), maxf(1.0, gunship_launch_cooldown))
	return 1

func _spawn_gunship() -> String:
	if is_defeated() or safe_remaining > 0.0 or count_kind("gunship") >= gunship_limit():
		return ""
	var id := _new_id("R")
	var lane := -35.0 if next_id % 2 == 0 else 35.0
	var origin := launch_origin(lane)
	contacts.append({"id": id, "kind": "gunship", "faction": "friendly",
		"position": origin, "age": 0.0, "phase": "launch", "lane": lane,
		"velocity": Vector3.ZERO, "target_id": "", "fire_timer": 2.0,
		"health": maxi(1, gunship_hit_points), "max_health": maxi(1, gunship_hit_points),
		"patrol_angle": rng.randf_range(0.0, TAU)})
	spawn_count += 1
	contact_spawned.emit(id, "gunship", "friendly")
	_play_launch(1)
	_set_status("GUNSHIP LAUNCHED | NUCLEAR INTERCEPTION PRIORITY", 3.0)
	return id

func _gunship_target(gunship: Dictionary, removed: Array[String]) -> Dictionary:
	var chosen: Dictionary = {}
	var best := INF
	# Nukes outrank capital attacks regardless of current task.
	for contact in contacts:
		if contact.kind != "nuke" or contact.id in removed:
			continue
		var score: float = contact.position.distance_to(own_ship_position)
		if contact.id == gunship.target_id:
			score *= 0.8
		if score < best:
			best = score
			chosen = contact
	if not chosen.is_empty():
		return chosen
	# 1.1.0 PULSE BOMB: after nukes, frozen Enemy Carriers come first.
	var frozen_carrier := _nearest_frozen(gunship.position, ["carrier"], removed)
	if not frozen_carrier.is_empty():
		return frozen_carrier
	# After nuclear defense, stop computer hackers before attacking capitals,
	# unless this Gunship is currently under Enemy Carrier flak attack.
	var under_fire := false
	for bolt in contacts:
		if bolt.kind == "flak" and bolt.get("target_id", "") == gunship.id:
			under_fire = true
	for contact in contacts:
		if under_fire or contact.kind != "breacher" or contact.id in removed:
			continue
		var priority: float = gunship.position.distance_to(contact.position)
		if contact.phase in ["hacking", "draining"]:
			priority *= 0.1
		if priority < best:
			best = priority
			chosen = contact
	if not chosen.is_empty():
		return chosen
	for contact in contacts:
		if contact.kind in ["carrier", "siege_ship"]:
			var score: float = gunship.position.distance_to(contact.position)
			# Gunships prefer the Siege Ship over Enemy Carriers.
			if contact.kind == "siege_ship":
				score *= 0.6
			if contact.id == gunship.target_id:
				score *= 0.7
			if score < best:
				best = score
				chosen = contact
	return chosen

func _update_gunships(delta: float) -> void:
	_update_tender_return(delta)
	var removed: Array[String] = []
	for gunship in contacts.duplicate():
		if gunship.kind != "gunship":
			continue
		# 1.2.9: the Protect the fleet repair Gunship flies its own route.
		if is_tender(gunship):
			continue
		gunship.fire_timer = maxf(0.0, gunship.fire_timer - delta)
		gunship.heavy_fire_remaining = maxf(0.0, gunship.get("heavy_fire_remaining", 0.0) - delta)
		gunship.nuke_fire_remaining = maxf(0.0, gunship.get("nuke_fire_remaining", 0.0) - delta)
		var speed := minf(gunship_speed, interceptor_speed * 0.9) * fighter_speed_factor()
		if gunship.age >= gunship_sortie_seconds:
			gunship.phase = "return"
		if gunship.phase == "return":
			_steer(gunship, launch_origin(gunship.lane), speed, delta)
			if gunship.position.distance_to(launch_origin(gunship.lane)) <= 0.03:
				removed.append(gunship.id)
				gunships_returned += 1
				_hold_after_landing("gunship")
				_set_status("GUNSHIP RECOVERED | SORTIE COMPLETE", 3.0)
			continue
		if gunship.phase == "launch":
			var entry := Vector3(gunship.lane / 320.0, -0.66, -0.15)
			_steer(gunship, entry, speed, delta)
			if gunship.position.distance_to(entry) <= 0.03:
				gunship.phase = "patrol"
			continue
		var target := _gunship_target(gunship, removed)
		var destination := Vector3(sin(battle_time * 0.1 + gunship.lane) * 0.25, -0.2, 0.05)
		if not target.is_empty():
			gunship.target_id = target.id
			if target.kind in ["nuke", "breacher"]:
				gunship.phase = "intercept"
				destination = target.position
			else:
				gunship.phase = "attack"
				destination = target.position + target.position.direction_to(own_ship_position) * 0.38
				if gunship.position.distance_to(target.position) < 0.85 and gunship.fire_timer <= 0.0 and count_kind("gunship_missile") < 4:
					var id := _new_id("RM")
					contacts.append({"id": id, "kind": "gunship_missile", "faction": "friendly",
						"position": gunship.position, "age": 0.0, "target_id": target.id,
						"target_position": target.position, "damage": clampf(gunship_missile_damage, 0.1, 0.9)})
					gunship.fire_timer = maxf(1.0, gunship_fire_interval) * fire_interval_factor()
		else:
			gunship.phase = "patrol"
			gunship.target_id = ""
		for bolt in contacts:
			if bolt.kind == "flak" and bolt.target_id == gunship.id and bolt.position.distance_to(gunship.position) < 0.28:
				# Small lateral evasive movement, still acceleration limited.
				destination += Vector3(sin(battle_time * 2.0 + gunship.lane) * 0.16, 0.04, 0.0)
				break
		_steer(gunship, destination, speed, delta)
		if not target.is_empty() and target.kind == "breacher" and gunship.position.distance_to(target.position) <= 0.08 and gunship.heavy_fire_remaining <= 0.0:
			_hit_breacher(target)
			gunship.heavy_fire_remaining = 1.2
		if not target.is_empty() and target.kind == "nuke" and gunship.position.distance_to(target.position) <= 0.08 and gunship.nuke_fire_remaining <= 0.0:
			# Nukes take several hits, so the Gunship has to stay with it.
			if not target.has("nuke_hits"):
				target.nuke_hits = scaled_hits(nuclear_hit_points)
				target.nuke_max_hits = target.nuke_hits
			target.nuke_hits -= 1
			nuke_hits_landed += 1
			gunship.nuke_fire_remaining = maxf(0.1, gunship_nuke_hit_interval)
			impacts.append({"position": target.position, "age": 0.0})
			if target.nuke_hits > 0:
				_set_status("GUNSHIP HIT NUCLEAR MISSILE | %d MORE TO DESTROY" % target.nuke_hits, 2.0)
				continue
			removed.append(target.id)
			_award_destroyed(target)
			nuclear_intercepts += 1
			_explode(target.position, "nuke")
			_set_status("GUNSHIP DESTROYED NUCLEAR MISSILE", 4.0)
	for id in removed:
		_remove_contact(id)

func _fire_flak(base: Dictionary) -> String:
	if count_kind("flak") >= 8:
		return ""
	var target: Dictionary = {}
	var nearest := carrier_flak_range
	for contact in contacts:
		if contact.kind == "gunship" and not is_tender(contact):
			var distance: float = base.position.distance_to(contact.position)
			if distance < nearest:
				nearest = distance
				target = contact
	if target.is_empty():
		return ""
	var id := _new_id("FL")
	var origin: Vector3 = base.position + base.position.direction_to(target.position) * carrier_emission_radius
	contacts.append({"id": id, "kind": "flak", "faction": "hostile", "position": origin,
		"age": 0.0, "target_id": target.id, "target_position": target.position})
	return id

## Colour of a nuclear missile marker: the yellow and red flash, or (1.1.0) the
## ice-blue shimmer while a PULSE BOMB has slowed it.
func nuke_marker_color(contact: Dictionary) -> Color:
	if contact.get("pulse_slowed", false):
		return display_color(contact)
	return Color(1.0, 0.85, 0.2) if int(battle_time * 5.0) % 2 == 0 else Color(1.0, 0.12, 0.15)

func _update_special_projectiles(delta: float) -> void:
	for projectile in contacts.duplicate():
		if projectile.kind == "nuke":
			# 1.1.0: a nuclear missile caught by a PULSE BOMB flies slower until it hits.
			var slowed := pulse_nuke_speed_factor if projectile.get("pulse_slowed", false) else 1.0
			projectile.position = projectile.position.move_toward(own_ship_position, nuclear_speed * nuke_speed_factor() * (1.0 + float(projectile.get("speed_bonus", 0.0))) * slowed * movement_speed * delta)
			if _battery_try_nuke(projectile):
				if is_defeated():
					return
				continue
			if projectile.position.distance_to(own_ship_position) <= missile_impact_radius:
				_remove_contact(projectile.id)
				nuclear_hits += 1
				impacts.append({"position": own_ship_position, "age": 0.0})
				_explode(own_ship_position, "nuke_impact")
				nuke_hit_ship.emit(true)
				apply_damage(nuclear_damage * damage_factor())
				if is_defeated():
					return
				_set_status("NUCLEAR IMPACT | HULL SEVERELY DAMAGED", 4.0)
		elif projectile.kind == "flak":
			var target := find_contact(projectile.target_id)
			if target.is_empty() or target.kind != "gunship" or projectile.age > 12.0:
				_remove_contact(projectile.id)
				continue
			projectile.target_position = target.position
			projectile.position = projectile.position.move_toward(target.position, 0.18 * movement_speed * delta)
			if projectile.position.distance_to(target.position) <= 0.025:
				_remove_contact(projectile.id)
				var evasion := returning_gunship_evasion_chance if target.get("phase", "") == "return" else gunship_evasion_chance
				if rng.randf() < clampf(evasion, 0.0, 0.95):
					gunship_evades += 1
					_set_status("GUNSHIP EVADED ENEMY CARRIER FIRE", 2.0)
				else:
					_damage_fighter(target, "ENEMY CARRIER FIRE")

func _award_destroyed(contact: Dictionary) -> void:
	if is_defeated() or contact.is_empty() or scored_contacts.has(contact.id) or find_contact(contact.id).is_empty():
		return
	_count_kill(contact.kind)
	var points := 0
	match contact.kind:
		"drone": points = fighter_points
		"breacher": points = breacher_points
		"convoy_breacher": points = breacher_points
		"nuke": points = nuclear_points
		"carrier": points = carrier_points
		"siege_ship": points = siege_points
		_: return
	scored_contacts[contact.id] = true
	if contact.get("phase", "") == "sweep":
		sweep_destroyed += 1
	if contact.get("phase", "") == "protect":
		protect_drones_destroyed += 1
	_destruction_effect(contact)
	if contact.get("phase", "") in ["protect", "protect_breacher"]:
		protect_kill_points += points_for(points)
	_add_points(points_for(points))

## 1.08: counts one destroyed enemy for the battle stats.
func _count_kill(kind: String) -> void:
	if kind == "convoy_breacher":
		kind = "breacher"
	if kind in KILL_KINDS:
		kills[kind] = int(kills.get(kind, 0)) + 1

## 1.08: a copy of the battle stats for the high-score table.
func battle_stats() -> Dictionary:
	var stats := {}
	for kind in KILL_KINDS:
		stats[kind] = int(kills.get(kind, 0))
	if wave_system_active():
		stats["waves_cleared"] = waves_cleared
		stats["sets"] = sets_completed
	return stats

## Adds already-multiplied points to the score and earned total, then checks the
## bonus repairs and (1.05) the Double Missile bonus.
func _add_points(points: int) -> void:
	if is_defeated():
		return
	score += maxi(0, points)
	earned_points += maxi(0, points)
	var entitled := repair_bonuses_for(earned_points)
	if entitled > repair_bonuses_earned:
		var bonus := entitled - repair_bonuses_earned
		repair_bonuses_earned = entitled
		_give_repair_charges(bonus)
	_check_emp_award()
	_check_pulse_award()
	_check_rapid_missile_bonus()
	_check_double_missile_bonus()

# ------------------------------------------------------------------
# Bonus features (1.05): Double Missile
# ------------------------------------------------------------------
## Earned points needed for Double Missile on the level being played.
func double_missile_threshold() -> int:
	return [easy_double_missile_points, normal_double_missile_points, hard_double_missile_points][clampi(active_difficulty, 0, 2)]

func double_missile_active() -> bool:
	if not (double_missile_bonus and double_missile_unlocked_at >= 0.0):
		return false
	return missile_bonus_pick != "RAPID"

func rapid_missile_allowed() -> bool:
	return rapid_missile_bonus and active_difficulty >= 1

func rapid_missile_active() -> bool:
	if not rapid_missile_allowed() or rapid_missile_unlocked_at < 0.0:
		return false
	if double_missile_bonus and double_missile_unlocked_at >= 0.0:
		return missile_bonus_pick == "RAPID"
	return true

## Gap between ship missiles for the level being played.
func ship_missile_gap() -> float:
	if rapid_missile_active():
		return rapid_missile_interval()
	return own_missile_interval

## 1.0.9: flight speed of one of our missiles: the ship's own missiles fly faster while
## Rapid Missile is in use; Gunship missiles always use the normal speed.
func missile_flight_speed(missile: Dictionary) -> float:
	if missile.get("kind", "") == "own_missile" and rapid_missile_active():
		return own_missile_speed * rapid_missile_speed_factor
	return own_missile_speed

## Seconds between ship missiles with the Rapid Missile bonus at this difficulty.
func rapid_missile_interval() -> float:
	return normal_rapid_missile_interval if active_difficulty == 1 else hard_rapid_missile_interval

func _check_rapid_missile_bonus() -> void:
	if not rapid_missile_allowed() or rapid_missile_unlocked_at >= 0.0:
		return
	var need := normal_rapid_missile_points if active_difficulty == 1 else hard_rapid_missile_points
	if earned_points < need:
		return
	rapid_missile_unlocked_at = battle_time
	bonus_chimes += 1
	if is_instance_valid(bonus_chime_player):
		bonus_chime_player.volume_db = bonus_chime_volume_db
		bonus_chime_player.play()
	if double_missile_bonus and double_missile_unlocked_at >= 0.0:
		_offer_missile_bonus("DOUBLE", false)
		return
	_set_status("RAPID MISSILE BONUS ACTIVE", 4.0)
	call_deferred("_set_status", "RAPID MISSILE BONUS ACTIVE", 4.0)

## 0.1.2: true once both missile bonuses are earned (the player has one of them).
func both_missile_bonuses_earned() -> bool:
	return rapid_missile_allowed() and rapid_missile_unlocked_at >= 0.0 and double_missile_bonus and double_missile_unlocked_at >= 0.0

## 0.1.2: ask the player to keep Current or take the other bonus. Current stays in use
## until a pick is made. With no console listening (computer tests), Current is kept,
## just as when the prompt times out.
func _offer_missile_bonus(current: String, set_offer: bool) -> void:
	missile_bonus_pick = current
	if missile_bonus_offer_open:
		return
	var other := "DOUBLE" if current == "RAPID" else "RAPID"
	if not set_offer and missile_bonus_pick_after_wave and wave_system_active() and wave_phase in ["assault", "protect", "sweep"]:
		# Mid-fight: keep the current bonus and ask once the round is over.
		missile_bonus_offer_waiting = true
		missile_bonus_waits += 1
		var line := (missile_bonus_wait_line % other) if missile_bonus_wait_line.contains("%s") else missile_bonus_wait_line
		_set_status(line, 4.0)
		call_deferred("_set_status", line, 4.0)
		battle_event.emit("missile bonus pick held for the end of the round | has %s, earned %s" % [current, other])
		return
	missile_bonus_offers += 1
	if set_offer:
		missile_bonus_set_offers += 1
	battle_event.emit("missile bonus pick offered (%s) | has %s, can take %s" % ["after set" if set_offer else "just earned", current, other])
	if missile_bonus_offer.get_connections().is_empty():
		return
	missile_bonus_offer_open = true
	missile_bonus_offer.emit(current, other, set_offer)

## 0.1.2: the player's answer to the pick prompt ("RAPID" or "DOUBLE"). Timed Out = no
## pick in time; the current bonus is kept.
func choose_missile_bonus(pick: String, timed_out: bool = false) -> void:
	missile_bonus_offer_open = false
	if pick not in ["RAPID", "DOUBLE"] or timed_out:
		pick = missile_bonus_pick
	var switched := pick != missile_bonus_pick
	if switched:
		missile_bonus_switches += 1
	missile_bonus_pick = pick
	var line := "%s MISSILE BONUS ACTIVE" % pick
	_set_status(line, 4.0)
	battle_event.emit("missile bonus %s | %s" % [pick, "kept (no pick in time)" if timed_out else ("switched" if switched else "kept")])

## Bonus lines shown under SCORE while active (room for more bonuses later).
func active_bonus_names() -> Array[String]:
	var names: Array[String] = []
	if double_missile_active():
		names.append("DOUBLE MISSILE BONUS")
	if rapid_missile_active():
		names.append("RAPID MISSILE BONUS")
	# 1.2.0: Systems Bonus boosts that last until the next wave is cleared.
	for key in active_boosts.keys():
		names.append(str(BOOST_LINES.get(key, key)))
	return names

func _check_double_missile_bonus() -> void:
	if not double_missile_bonus or double_missile_unlocked_at >= 0.0 or earned_points < double_missile_threshold():
		return
	var had_rapid := rapid_missile_active()
	double_missile_unlocked_at = battle_time
	bonus_chimes += 1
	if is_instance_valid(bonus_chime_player):
		bonus_chime_player.volume_db = bonus_chime_volume_db
		bonus_chime_player.play()
	if had_rapid:
		# 0.1.2: Rapid Missile is in use; the player picks which one to keep.
		_offer_missile_bonus("RAPID", false)
		return
	_set_status("DOUBLE MISSILE BONUS ACTIVE", 4.0)
	# Shown again after this frame, so the kill message that unlocked it does not hide it.
	call_deferred("_set_status", "DOUBLE MISSILE BONUS ACTIVE", 4.0)

# ------------------------------------------------------------------
# Difficulty and automation (gear Settings panel)
# ------------------------------------------------------------------
func difficulty_factor(easy: float, hard: float) -> float:
	match active_difficulty:
		0: return easy
		2: return hard
	return 1.0

## 1.2.7: Attack Drone speed for the level being played (Hard Attack Drone Speed on Hard only).
func drone_speed() -> float:
	return maxf(0.001, small_hostile_speed) * (maxf(1.0, hard_drone_speed) if active_difficulty == 2 else 1.0)

## 1.2.7: Breacher speed for the level being played (Hard Breacher Speed on Hard only).
func heavy_speed() -> float:
	return breacher_speed * (maxf(1.0, hard_breacher_speed) if active_difficulty == 2 else 1.0)

## Missile and nuke speed for the level being played (Easy keeps the 1.03 speed).
func missile_speed_factor() -> float:
	return maxf(0.1, [easy_missile_speed, normal_missile_speed, hard_missile_speed][clampi(active_difficulty, 0, 2)]) * set_warhead_factor()

func nuke_speed_factor() -> float:
	return maxf(0.1, [easy_nuke_speed, normal_nuke_speed, hard_nuke_speed][clampi(active_difficulty, 0, 2)]) * set_warhead_factor()

func scaled_hits(hits: int) -> int:
	return maxi(1, roundi(hits * difficulty_factor(easy_toughness, hard_toughness)))

func attack_rate() -> float:
	return maxf(0.1, difficulty_factor(easy_attack_rate, hard_attack_rate))

func damage_factor() -> float:
	return difficulty_factor(easy_damage, hard_damage)

func hack_speed() -> float:
	return maxf(0.1, difficulty_factor(easy_hack_speed, hard_hack_speed)) * set_hack_factor()

func wave_length() -> float:
	return maxf(1.0, wave_seconds * difficulty_factor(easy_wave_length, hard_wave_length))

func auto_options_on() -> int:
	return int(auto_defense_battery) + int(auto_firewall) + int(auto_launch_interceptors) + int(auto_launch_gunships) + int(auto_jump) + int(auto_rapid_repair)

func score_multiplier_for(level: int, autos: int) -> float:
	var base: float = [easy_score_multiplier, 1.0, hard_score_multiplier][clampi(level, 0, 2)]
	return maxf(0.0, base * (1.0 - auto_score_penalty * autos))

func score_multiplier() -> float:
	return score_multiplier_for(active_difficulty, auto_options_on()) * set_score_multiplier()

func points_for(base_points: int) -> int:
	return roundi(maxi(0, base_points) * score_multiplier())

func difficulty_letter() -> String:
	return ["E", "N", "H"][clampi(active_difficulty, 0, 2)]

func missiles_in_defense_zone(radius: float = -1.0) -> int:
	var reach := prox_defense_radius if radius < 0.0 else radius
	var total := 0
	for contact in contacts:
		if contact.kind == "missile" and contact.position.distance_to(own_ship_position) <= reach:
			total += 1
	return total

## 1.2.8: nukes within the radius that the battery has not had its chance at yet.
func nukes_for_battery(radius: float = -1.0) -> int:
	var reach := prox_defense_radius if radius < 0.0 else radius
	var total := 0
	for contact in contacts:
		if contact.kind == "nuke" and not contact.get("battery_rolled", false) and contact.position.distance_to(own_ship_position) <= reach:
			total += 1
	return total

## 1.2.8: while the Defense Shield fires, a nuke in the kill zone gets one chance
## (Battery Nuke Chance) to be shot down. It explodes close to the ship and does
## splash damage (Battery Nuke Splash x a direct hit) and scores full nuke points.
## Returns true when the nuke was destroyed.
func _battery_try_nuke(projectile: Dictionary) -> bool:
	if not prox_active or projectile.get("battery_rolled", false):
		return false
	if projectile.position.distance_to(own_ship_position) > prox_defense_radius:
		return false
	projectile.battery_rolled = true
	if rng.randf() >= battery_nuke_chance:
		battery_nuke_misses += 1
		return false
	battery_nuke_kills += 1
	_award_destroyed(projectile)
	nuclear_intercepts += 1
	impacts.append({"position": projectile.position, "age": 0.0})
	_explode(projectile.position, "nuke")
	_remove_contact(projectile.id)
	var splash := nuclear_damage * damage_factor() * battery_nuke_splash
	battery_splash_damage += splash
	nuke_hit_ship.emit(false)
	apply_damage(splash)
	if not is_defeated():
		_set_status("DEFENSE SHIELD: NUKE DESTROYED | SPLASH DAMAGE", 4.0)
	return true

func _update_automation() -> void:
	# 1.2.2: Protect the fleet is manual play; every auto option pauses for the round.
	# 1.2.7: except Auto Launch Interceptors, which carries through (within the round's
	# one-Interceptor-per-Attack Drone launch limit).
	if protect_active():
		auto_battery_started = false
		auto_firewall_started = false
		if auto_launch_interceptors:
			_auto_launch_interceptors()
		return
	_update_auto_repair()
	if _update_auto_jump():
		return
	_update_auto_launch()
	if not firewall_active:
		auto_firewall_started = false
	if auto_firewall and not firewall_active and firewall_needed() and can_deploy_firewall():
		set_firewall(true)
		if firewall_active:
			auto_firewall_starts += 1
			auto_firewall_started = true
			auto_firewall_since = battle_time
	if not battery_auto_on():
		auto_battery_started = false
		return
	if not prox_active:
		auto_battery_started = false
	var threats := missiles_in_defense_zone(maxf(prox_defense_radius, auto_battery_lead_radius))
	if auto_battery_for_nukes:
		threats += nukes_for_battery(maxf(prox_defense_radius, auto_battery_lead_radius))
	if threats > 0 and not prox_active and can_fire_battery():
		set_prox_defense(true)
		if prox_active:
			auto_battery_started = true
			auto_battery_since = battle_time
			auto_battery_starts += 1
	elif threats == 0 and prox_active and auto_battery_started and battle_time - auto_battery_since >= auto_min_engage_seconds:
		# Zone is clear and the minimum time has passed: stop the burst the
		# automation started and keep the rest of the charge.
		set_prox_defense(false)
		auto_battery_started = false

## Auto Rapid Repair: use one charge when the hull is at or below the set level.
func _update_auto_repair() -> bool:
	if not auto_rapid_repair or hull > max_hull * auto_repair_hull_percent / 100.0 or not can_rapid_repair():
		return false
	if not request_rapid_repair():
		return false
	auto_repairs += 1
	_set_status("AUTO RAPID REPAIR | HULL AT %d%% | %d CHARGE%s LEFT" % [roundi(100.0 * hull / maxf(1.0, max_hull)), repair_charges, "" if repair_charges == 1 else "S"], 3.0)
	return true

## Auto JUMP: jump as soon as the hull is below the set level and JUMP is charged.
func _update_auto_jump() -> bool:
	if not auto_jump or is_defeated() or hull >= max_hull * auto_jump_hull_percent / 100.0 or not can_jump():
		return false
	if not request_jump():
		return false
	auto_jumps += 1
	_set_status("AUTO JUMP | HULL BELOW %d%% | -%d POINTS" % [roundi(auto_jump_hull_percent), last_jump_cost], safe_remaining)
	return true

func enemy_fighters() -> int:
	return count_kind("drone") + count_kind("breacher")

func interceptors_on_patrol() -> int:
	var total := 0
	for contact in contacts:
		if Icons.is_interceptor(contact.kind) and not is_returning(contact):
			total += 1
	return total

## Auto launch: Interceptors while enemy fighters are present (at least 2 out, one per
## fighter up to the limit); Gunships for each nuke, and one against Enemy Carriers.
## Uses the normal launch rules, so cooldowns and limits still apply.
func _auto_launch_interceptors() -> void:
	if is_defeated() or safe_remaining > 0.0:
		return
	var fighters := enemy_fighters()
	if fighters > 0 and interceptors_on_patrol() < clampi(fighters, 2, interceptor_limit()):
		if launch_interceptors() > 0:
			auto_interceptor_launches += 1
			if protect_active():
				protect_auto_interceptor_launches += 1

func _update_auto_launch() -> void:
	if is_defeated() or safe_remaining > 0.0:
		return
	if auto_launch_interceptors:
		_auto_launch_interceptors()
	if auto_launch_gunships:
		var gunships := count_kind("gunship")
		var nukes := count_kind("nuke")
		var wanted := mini(gunship_limit(), nukes) if nukes > 0 else (1 if count_kind("carrier") > 0 else 0)
		if auto_all_gunships_nukes > 0 and nukes >= auto_all_gunships_nukes and gunships < gunship_limit():
			# 1.1.0: several nukes on screen: every available Gunship launches at once.
			# The launch cooldown is skipped; the landing pause still applies. 1.0.5: each
			# Gunship's own landing wait still applies, so ones that just landed stay behind.
			_clear_waits(gunship_waits, "launch")
			var ready := gunships_ready()
			if ready > 0:
				var sent := 0
				while sent < ready and not _spawn_gunship().is_empty():
					sent += 1
				if sent > 0:
					_hold_ready(gunship_waits, gunships_ready(), maxf(1.0, gunship_launch_cooldown))
					auto_gunship_launches += sent
					auto_all_gunship_launches += 1
					battle_event.emit("auto launch: all Gunships (%d) for %d nukes" % [sent, nukes])
		elif gunships < wanted and launch_gunship() > 0:
			auto_gunship_launches += 1

func auto_firewall_holding() -> bool:
	return firewall_active and auto_firewall_started and battle_time - auto_firewall_since < auto_min_engage_seconds

# ------------------------------------------------------------------
# Explosions: missile flash and boom, nuke explosion, screen flash
# ------------------------------------------------------------------
func _explode(at: Vector3, kind: String) -> void:
	if kind in ["craft", "heavy", "own_craft"]:
		if not craft_explosions_enabled:
			return
		craft_explosions += 1
	if explosion_effects_enabled:
		explosions.append({"position": at, "age": 0.0, "kind": kind, "seed": explosions_made})
	explosions_made += 1
	if kind == "missile":
		_play_boom(missile_boom_player, "missile", missile_boom_volume_db)
	elif kind == "craft" or kind == "own_craft":
		# 1.2.9: Protect the fleet plays its own volumes and ship-sized booms.
		if not _play_protect_boom(kind):
			_play_boom(craft_boom_player, "craft", craft_boom_volume_db)
	elif kind == "heavy":
		_play_boom(heavy_boom_player, "heavy", heavy_boom_volume_db)
	elif kind == "capital":
		capital_explosions += 1
		_play_boom(capital_boom_player, "capital", capital_boom_volume_db)
		_screen_flash(capital_screen_flash_strength)
	else:
		_play_boom(nuke_boom_player, "nuke", nuke_boom_volume_db)
		_screen_flash(nuke_impact_flash_strength if kind == "nuke_impact" else nuke_screen_flash_strength)

## Explosion for a destroyed enemy craft (missiles and nukes have their own).
func _destruction_effect(contact: Dictionary) -> void:
	match contact.kind:
		"drone": _explode(contact.position, "craft")
		"breacher": _explode(contact.position, "heavy")
		"carrier", "siege_ship": _explode(contact.position, "capital")

func _boom_player(node_name: String, stream: AudioStream, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = volume
	player.max_polyphony = 2
	add_child(player)
	return player

func _play_boom(player: AudioStreamPlayer, which: String, volume: float) -> void:
	if not is_instance_valid(player) or battle_time - float(last_boom.get(which, -INF)) < boom_min_gap_seconds:
		return
	last_boom[which] = battle_time
	booms_played[which] = int(booms_played.get(which, 0)) + 1
	player.volume_db = volume
	player.play()

func _screen_flash(strength: float) -> void:
	if not screen_flash_enabled or strength <= 0.0:
		return
	screen_flash_peak = maxf(screen_flash_alpha(), clampf(strength, 0.0, 0.6))
	screen_flash_remaining = maxf(0.1, screen_flash_seconds)

func screen_flash_alpha() -> float:
	if screen_flash_remaining <= 0.0:
		return 0.0
	var f := clampf(screen_flash_remaining / maxf(0.1, screen_flash_seconds), 0.0, 1.0)
	return screen_flash_peak * f * f

# ------------------------------------------------------------------
# JUMP flash: a blue-white band wipes across the scope, with a brief screen flash
# ------------------------------------------------------------------
## 0 at the start of the flash, 1 at the end (or -1 when no flash is running).
func jump_flash_progress() -> float:
	if jump_flash_remaining <= 0.0:
		return -1.0
	return clampf(1.0 - jump_flash_remaining / maxf(0.3, jump_flash_seconds), 0.0, 1.0)

## Full-screen flash strength: instant on at the jump, fading over the first 45%.
func jump_screen_alpha() -> float:
	var t := jump_flash_progress()
	if t < 0.0 or not screen_flash_enabled:
		return 0.0
	var f := clampf(1.0 - t / 0.45, 0.0, 1.0)
	return clampf(jump_screen_flash_strength, 0.0, 0.6) * f * f

## Where the wipe band is, from -1 (left edge of the scope) to +1 (right edge).
func jump_band_position() -> float:
	var t := jump_flash_progress()
	if t < 0.0:
		return -2.0
	return lerpf(-1.25, 1.25, 1.0 - pow(1.0 - t, 2.0))

func _draw_jump_flash() -> void:
	var t := jump_flash_progress()
	if t < 0.0:
		return
	var radius: float = get_parent().sphere_radius
	var centre := size * 0.5
	var fade := 1.0 - t
	var band := jump_band_position()
	var width := 0.28
	# Vertical strokes inside the scope circle, brightest at the band centre.
	var steps := 160
	for index in range(steps + 1):
		var x := band - width + 2.0 * width * index / steps
		if absf(x) >= 1.0:
			continue
		var closeness := 1.0 - absf(x - band) / width
		var half := sqrt(1.0 - x * x) * radius
		var px := centre.x + x * radius
		var color := Color(0.72, 0.88, 1.0).lerp(Color(1.0, 1.0, 1.0), closeness * closeness * closeness)
		color.a = 0.85 * closeness * closeness * fade
		draw_line(Vector2(px, centre.y - half), Vector2(px, centre.y + half), color, radius * 2.0 * width / steps + 0.75, true)
	# Horizontal streaks trailing the band, like the jump stretching space.
	for line in range(9):
		var y := -0.8 + 1.6 * line / 8.0
		var half_w := sqrt(maxf(0.0, 1.0 - y * y))
		var tail := maxf(-half_w, band - 0.9)
		var head := minf(half_w, band)
		if head <= tail:
			continue
		draw_line(centre + Vector2(tail, y) * radius, centre + Vector2(head, y) * radius, Color(0.75, 0.9, 1.0, 0.45 * fade), 1.5, true)

func explosion_life(kind: String) -> float:
	match kind:
		"missile": return maxf(0.1, missile_flash_seconds)
		"craft", "heavy", "own_craft": return maxf(0.1, craft_explosion_seconds * (1.25 if kind == "heavy" else 1.0))
		"capital": return maxf(0.3, capital_explosion_seconds)
	return maxf(0.1, nuke_explosion_seconds)

func _age_explosions(delta: float) -> void:
	screen_flash_remaining = maxf(0.0, screen_flash_remaining - delta)
	jump_flash_remaining = maxf(0.0, jump_flash_remaining - delta)
	for index in range(explosions.size() - 1, -1, -1):
		explosions[index].age += delta
		if explosions[index].age >= explosion_life(explosions[index].kind):
			explosions.remove_at(index)

func _draw_explosions() -> void:
	for blast in explosions:
		var projected := projection(blast.position)
		var point: Vector2 = projected.point
		var k: float = projected.scale
		var t: float = clampf(blast.age / explosion_life(blast.kind), 0.0, 1.0)
		var fade := 1.0 - t
		if blast.kind == "missile":
			k *= missile_flash_size
			draw_circle(point, maxf(0.5, 5.0 * fade * k), Color(1.0, 0.97, 0.86, fade))
			draw_arc(point, (4.0 + 13.0 * t) * k, 0.0, TAU, 24, Color(1.0, 0.62, 0.25, fade * 0.9), 1.5, true)
			continue
		if blast.kind in ["craft", "heavy", "own_craft"]:
			_draw_craft_burst(blast, point, k, t, fade)
			continue
		if blast.kind == "capital":
			_draw_capital_burst(blast, point, k, t, fade)
			continue
		k *= nuke_explosion_size * (1.35 if blast.kind == "nuke_impact" else 1.0)
		var radius: float = (10.0 + 30.0 * sqrt(t)) * k
		var heat := Color(1.0, lerpf(0.95, 0.55, t), lerpf(0.78, 0.2, t), 0.9 * pow(fade, 2.6))
		draw_circle(point, radius, heat)
		draw_circle(point, radius * 0.5 * fade, Color(1.0, 1.0, 0.95, fade))
		draw_arc(point, (14.0 + 72.0 * t) * k, 0.0, TAU, 48, Color(1.0, 0.78, 0.45, 0.7 * fade), 2.0, true)
		for spark in range(8):
			var angle := TAU * spark / 8.0 + float(blast.seed) * 0.7
			var direction := Vector2(cos(angle), sin(angle))
			draw_line(point + direction * radius * 0.9, point + direction * (radius * 0.9 + 16.0 * k * fade + 6.0 * k),
				Color(1.0, 0.85, 0.4, fade), 1.5, true)

## Small fiery burst for a destroyed fighter: hot core, expanding ring and a few sparks.
func _draw_craft_burst(blast: Dictionary, point: Vector2, k: float, t: float, fade: float) -> void:
	k *= craft_explosion_size * (heavy_explosion_scale if blast.kind == "heavy" else 1.0)
	var tint: Color = own_craft_color if blast.kind == "own_craft" else enemy_craft_color
	var radius: float = (4.0 + 9.0 * sqrt(t)) * k
	draw_circle(point, radius, Color(tint, 0.75 * pow(fade, 2.2)))
	draw_circle(point, maxf(0.5, radius * 0.45 * fade), Color(1.0, 1.0, 0.94, fade))
	draw_arc(point, (5.0 + 18.0 * t) * k, 0.0, TAU, 24, Color(tint.lightened(0.25), 0.8 * fade), 1.5, true)
	for spark in range(5):
		var angle := TAU * spark / 5.0 + float(blast.seed) * 1.3
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(point + direction * radius * 0.8, point + direction * (radius * 0.8 + 7.0 * k * fade + 2.0 * k),
			Color(tint.lightened(0.4), fade), 1.2, true)

## Large explosion for a destroyed Enemy Carrier or Siege Ship: bright core, two shock rings and debris.
func _draw_capital_burst(blast: Dictionary, point: Vector2, k: float, t: float, fade: float) -> void:
	k *= capital_explosion_size
	var radius: float = (16.0 + 46.0 * sqrt(t)) * k
	var heat := Color(1.0, lerpf(0.96, 0.5, t), lerpf(0.82, 0.18, t), 0.85 * pow(fade, 2.0))
	draw_circle(point, radius, heat)
	draw_circle(point, radius * 0.55 * fade, Color(1.0, 1.0, 0.96, fade))
	draw_arc(point, (20.0 + 110.0 * t) * k, 0.0, TAU, 64, Color(1.0, 0.8, 0.5, 0.75 * fade), 2.5, true)
	var late := clampf((t - 0.15) / 0.85, 0.0, 1.0)
	if late > 0.0:
		draw_arc(point, (16.0 + 80.0 * late) * k, 0.0, TAU, 64, Color(1.0, 0.62, 0.3, 0.6 * (1.0 - late)), 1.5, true)
	for piece in range(12):
		var angle := TAU * piece / 12.0 + float(blast.seed) * 0.9
		var direction := Vector2(cos(angle), sin(angle))
		var reach := radius * (0.9 + 0.25 * float((piece * 7 + int(blast.seed)) % 5) / 4.0)
		draw_line(point + direction * reach, point + direction * (reach + 22.0 * k * fade + 6.0 * k),
			Color(1.0, 0.86, 0.45, fade), 1.8, true)

# ------------------------------------------------------------------
# Interceptor squadrons (display only; every Interceptor keeps its own health and losses)
# ------------------------------------------------------------------
func _squadron_centre(members: Array, by_id: Dictionary) -> Vector3:
	var total := Vector3.ZERO
	for id in members:
		total += by_id[id].position
	return total / maxf(1.0, members.size())

func _update_interceptor_squadrons() -> void:
	if not interceptor_squadrons_enabled:
		interceptor_squadrons.clear()
		return
	var by_id := {}
	var order: Array[String] = []
	for contact in contacts:
		if contact.kind == "interceptor" and contact.get("phase", "") != "return":
			by_id[contact.id] = contact
			order.append(contact.id)
	var groups: Array = []
	var used := {}
	# Existing squadrons hold together until a member passes the split distance.
	for group in interceptor_squadrons:
		var members: Array = []
		for id in group:
			if by_id.has(id) and not used.has(id):
				members.append(id)
		if members.size() < 2:
			continue
		var centre := _squadron_centre(members, by_id)
		var kept: Array = []
		for id in members:
			if by_id[id].position.distance_to(centre) <= squadron_split_distance:
				kept.append(id)
		if kept.size() >= 2:
			for id in kept:
				used[id] = true
			groups.append(kept)
	# Loose Interceptors join a nearby squadron or pair up within the join distance.
	for id in order:
		if used.has(id):
			continue
		var joined := false
		for group in groups:
			if by_id[id].position.distance_to(_squadron_centre(group, by_id)) <= squadron_join_distance:
				group.append(id)
				used[id] = true
				joined = true
				break
		if joined:
			continue
		for other in order:
			if other != id and not used.has(other) and by_id[id].position.distance_to(by_id[other].position) <= squadron_join_distance:
				groups.append([id, other])
				used[id] = true
				used[other] = true
				break
	interceptor_squadrons = groups

func squadron_of(id: String) -> int:
	for index in range(interceptor_squadrons.size()):
		if id in interceptor_squadrons[index]:
			return index
	return -1

func _draw_interceptor_squadrons(font: Font) -> void:
	for group in interceptor_squadrons:
		var members: Array = []
		for id in group:
			var interceptor := find_contact(id)
			if not interceptor.is_empty():
				members.append(interceptor)
		if members.size() < 2:
			continue
		var centre := Vector3.ZERO
		var weakest := 100
		for interceptor in members:
			centre += interceptor.position
			weakest = mini(weakest, fighter_health_percent(interceptor))
		centre /= members.size()
		var projected := projection(centre)
		var point: Vector2 = projected.point
		var marker_scale: float = projected.scale * small_ship_icon_scale
		var color := display_color(members[0])
		Icons.draw_icon(self, "interceptor_squadron", point, marker_scale, color)
		if show_labels:
			var text := "INTERCEPTORS x%d" % members.size()
			if show_full_tags:
				text = "INTERCEPTOR SQUADRON x%d" % members.size()
			if show_full_tags and weakest < 100:
				text += " %d%%" % weakest
			var label_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size)
			var label_point := point + Vector2(-label_size.x * 0.5, 29.0 * marker_scale)
			# 1.2.9: Protect the fleet labels move clear of each other.
			if protect_label_declutter and protect_active():
				label_point = _protect_place_label(label_point, label_size)
			if label_point.is_finite():
				draw_string_outline_and_text(font, label_point, text, label_font_size, label_color(color))

func pending_heavies() -> int:
	var total := 0
	for request in pending:
		if request.kind == "breacher":
			total += 1
	return total

func count_base_heavies(base_id: String, include_pending: bool = false) -> int:
	var total := 0
	for contact in contacts:
		if contact.kind == "breacher" and contact.get("origin_id", "") == base_id:
			total += 1
	if include_pending:
		for request in pending:
			if request.kind == "breacher" and request.get("origin_id", "") == base_id:
				total += 1
	return total

func _update_breachers(delta: float) -> void:
	if is_defeated() or safe_remaining > 0.0:
		return
	for heavy in contacts.duplicate():
		if heavy.kind != "breacher":
			continue
		if float(heavy.get("frozen", 0.0)) > 0.0:
			continue
		if heavy.phase in ["emp", "emp_return"]:
			_update_emp_heavy(heavy, delta)
			continue
		if heavy.phase == "approach":
			_steer(heavy, heavy.hack_point, heavy_speed(), delta)
			if heavy.position.distance_to(heavy.hack_point) <= 0.025 and heavy.position.distance_to(own_ship_position) <= hacking_range:
				heavy.phase = "hacking"
				heavy.velocity = Vector3.ZERO
				heavy.hack_remaining = maxf(0.1, hacking_seconds / hack_speed())
				_set_status("BREACHER HACKING | SHIP MISSILES, INTERCEPTORS OR GUNSHIPS", 4.0)
			# Arrival never retroactively consumes an entire frame's hack time.
			continue
		if heavy.position.distance_to(own_ship_position) > hacking_range:
			heavy.phase = "approach"
			heavy.hack_remaining = maxf(0.1, hacking_seconds / hack_speed())
			continue
		# FIREWALL: while deployed, the hack and its drain run slower.
		var drain_time := maxf(0.0, delta) * (clampf(firewall_slow_factor, 0.0, 1.0) if firewall_active else 1.0)
		if heavy.phase == "hacking":
			var step := minf(drain_time, heavy.hack_remaining)
			heavy.hack_remaining = maxf(0.0, heavy.hack_remaining - step)
			drain_time -= step
			if heavy.hack_remaining <= 0.0:
				heavy.phase = "draining"
		if heavy.phase == "draining" and drain_time > 0.0:
			apply_damage(max_hull * hack_drain_percent_per_second * hack_speed() * 0.01 * drain_time, false)
			if is_defeated():
				return

func active_hackers() -> int:
	var total := 0
	for contact in contacts:
		if contact.kind == "breacher" and contact.phase == "draining":
			total += 1
	return total

func hacking_count() -> int:
	var total := 0
	for contact in contacts:
		if contact.kind == "breacher" and contact.phase == "hacking":
			total += 1
	return total

func hack_breach_seconds() -> float:
	# Time until the next hacking Breacher breaks through; INF when none.
	var soonest := INF
	for contact in contacts:
		if contact.kind == "breacher" and contact.phase == "hacking":
			soonest = minf(soonest, contact.hack_remaining)
	return soonest

func hack_state() -> String:
	if is_defeated():
		return ""
	if active_hackers() > 0:
		return "draining"
	if hacking_count() > 0:
		return "hacking"
	if count_kind("breacher") - emp_heavies_present() > 0:
		return "approach"
	return ""

func hacking_warning() -> String:
	var state := hack_state()
	if state == "":
		return ""
	if state == "approach":
		return "BREACHER APPROACHING\nPREPARE FIREWALL DEFENSE"
	var lines: Array[String] = []
	var active := active_hackers()
	if active > 0:
		lines.append("COMPUTERS BREACHED")
		lines.append("HULL DRAIN %.1f%% / SEC" % (hack_drain_percent_per_second * hack_speed() * active))
	var hacking := hacking_count()
	if hacking > 0:
		if active == 0:
			lines.append("BREACHER%s HACKING SHIP" % ("S" if hacking > 1 else ""))
			lines.append("FIREWALL UP | HACK SLOWED" if firewall_active else "PENETRATING DEFENSES")
			lines.append("BREACH IN %.1f s" % hack_breach_seconds())
		else:
			lines.append("NEXT BREACH IN %.1f s" % hack_breach_seconds())
	if firewall_active and active > 0:
		lines.append("FIREWALL UP | DRAIN SLOWED")
	lines.append("SHIP MISSILES / INTERCEPTORS / GUNSHIPS")
	return "\n".join(lines)

func _hit_breacher(heavy: Dictionary) -> void:
	if is_defeated() or heavy.is_empty() or heavy.kind != "breacher" or find_contact(heavy.id).is_empty():
		return
	heavy.health -= roundi(pulse_damage_factor(heavy))
	impacts.append({"position": heavy.position, "age": 0.0})
	if heavy.health > 0:
		return
	_award_destroyed(heavy)
	_remove_contact(heavy.id)
	breachers_destroyed += 1
	_set_status("BREACHER DESTROYED | HACKING LINK TERMINATED", 3.0)

func can_rapid_repair() -> bool:
	if rapid_repair_needs_shown_damage and hull_percent() >= 100:
		# 0.1.2: the hull readout shows 100%, so the button stays grey and no charge is spent.
		return false
	return not is_defeated() and repair_charges > 0 and rapid_repair_remaining <= 0.0 and hull < max_hull

func request_rapid_repair() -> bool:
	if not can_rapid_repair():
		return false
	rapid_repair_used = true
	repair_charges -= 1
	_check_repair_resume()
	rapid_repair_remaining = maxf(0.1, rapid_repair_seconds)
	rapid_repair_rate = max_hull * clampf(rapid_repair_percent, 0.0, 100.0) / 100.0 / rapid_repair_remaining
	_set_status("RAPID REPAIR ENGAGED | %d CHARGE%s LEFT" % [repair_charges, "" if repair_charges == 1 else "S"], rapid_repair_remaining)
	if repair_sound_enabled and is_instance_valid(repair_sound_player):
		repair_sound_player.volume_db = repair_sound_volume_db
		repair_sound_player.play()
		repair_sounds += 1
	return true

func _update_rapid_repair(delta: float) -> void:
	if is_defeated() or rapid_repair_remaining <= 0.0:
		return
	var step := minf(maxf(0.0, delta), rapid_repair_remaining)
	hull = minf(max_hull, hull + rapid_repair_rate * step)
	rapid_repair_remaining = maxf(0.0, rapid_repair_remaining - step)

## 0 to 1 pulse for the ship outline while a Rapid Repair runs (0 when idle).
func repair_flash_level() -> float:
	if not repair_flash_enabled or rapid_repair_remaining <= 0.0 or is_defeated():
		return 0.0
	return 0.5 - 0.5 * cos(TAU * repair_flash_hz * battle_time)

# ------------------------------------------------------------------
# EMP defense (1.06): overloads hacking Breachers and sends them home.
# ------------------------------------------------------------------
func _check_emp_award() -> void:
	if not emp_enabled:
		return
	var entitled := earned_points / maxi(1, emp_points_per_charge)
	if entitled <= emp_awards_earned:
		return
	var before := emp_charges
	emp_charges = mini(maxi(1, emp_max_charges), emp_charges + entitled - emp_awards_earned)
	emp_awards_earned = entitled
	if emp_charges > before and status_remaining <= 0.0:
		_set_status("EMP CHARGE READY | %d HELD" % emp_charges, 3.0)

## Breachers currently hacking or draining the ship's computers.
func emp_targets() -> Array:
	var found: Array = []
	for contact in contacts:
		if contact.kind == "breacher" and contact.get("phase", "") in ["hacking", "draining"]:
			found.append(contact)
	return found

## Breachers overloaded by the EMP (shimmering or flying home).
func emp_heavies_present() -> int:
	var total := 0
	for contact in contacts:
		if contact.kind == "breacher" and contact.get("phase", "") in ["emp", "emp_return"]:
			total += 1
	return total

## USE EMP is offered only while being hacked, with a charge ready, and (1.07) only
## once the Firewall has run out for emp_delay_after_firewall seconds.
func can_use_emp() -> bool:
	return emp_enabled and not is_defeated() and emp_charges > 0 and not emp_targets().is_empty() and (emp_offer_open or not firewall_enabled)

func _update_emp_offer() -> void:
	if emp_targets().is_empty():
		firewall_out_since = -1.0
		emp_offer_open = false
		return
	if emp_offer_open:
		return
	if not firewall_enabled:
		emp_offer_open = true
		return
	if firewall_active or can_deploy_firewall():
		firewall_out_since = -1.0
		return
	if firewall_out_since < 0.0:
		firewall_out_since = battle_time
	if battle_time - firewall_out_since >= maxf(0.0, emp_delay_after_firewall):
		emp_offer_open = true

func request_emp() -> bool:
	if not can_use_emp():
		return false
	var targets := emp_targets()
	emp_charges -= 1
	emp_uses += 1
	for heavy in targets:
		heavy.phase = "emp"
		heavy.emp_remaining = maxf(0.1, emp_shimmer_seconds)
		heavy.velocity = Vector3.ZERO
		emp_heavies_overloaded += 1
	if is_instance_valid(emp_player):
		emp_player.volume_db = emp_zap_volume_db
		emp_player.play()
	_set_status("EMP DISCHARGED | %d BREACHER%s OVERLOADED, RETURNING FOR REPAIRS" % [targets.size(), "" if targets.size() == 1 else "S"], 4.0)
	return true

func _update_emp_heavy(heavy: Dictionary, delta: float) -> void:
	if heavy.phase == "emp":
		heavy.emp_remaining = maxf(0.0, float(heavy.get("emp_remaining", 0.0)) - delta)
		if heavy.emp_remaining <= 0.0:
			heavy.phase = "emp_return"
			heavy.emp_return_age = 0.0
		return
	heavy.emp_return_age = float(heavy.get("emp_return_age", 0.0)) + delta
	var home := find_contact(heavy.get("origin_id", ""))
	if home.is_empty() or home.kind != "carrier":
		home = {}
		var best := INF
		for contact in contacts:
			if contact.kind == "carrier" and heavy.position.distance_to(contact.position) < best:
				best = heavy.position.distance_to(contact.position)
				home = contact
	if home.is_empty():
		# No Enemy Carrier left: fly away from the ship and leave the scope.
		var away: Vector3 = heavy.position + (heavy.position - own_ship_position).normalized()
		_steer(heavy, away, heavy_speed(), delta)
		if heavy.emp_return_age >= 8.0:
			emp_heavies_docked += 1
			_remove_contact(heavy.id)
		return
	_steer(heavy, home.position, heavy_speed(), delta)
	if heavy.position.distance_to(home.position) <= 0.05:
		emp_heavies_docked += 1
		_remove_contact(heavy.id)

## Small jagged electric arcs around an overloaded Breacher.
func _draw_emp_sparks(point: Vector2, marker_scale: float, contact: Dictionary) -> void:
	var tick := int(battle_time * 18.0)
	var seed_base: int = String(contact.id).hash()
	for arc in range(4):
		var angle := TAU * _spark01(seed_base + arc, tick)
		var radius := (14.0 + 8.0 * _spark01(seed_base + arc * 3, tick + 1)) * maxf(0.6, marker_scale)
		var bolt := PackedVector2Array()
		for step in range(5):
			var a := angle + step * 0.32
			var r := radius + (_spark01(seed_base + arc * 11 + step, tick) - 0.5) * 8.0
			bolt.append(point + Vector2(cos(a), sin(a)) * r)
		draw_polyline(bolt, Color(emp_color.lerp(Color.WHITE, 0.35), 0.85), 1.5, true)

static func _spark01(a: int, b: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h >> 8) & 0xFFFF) / 65535.0

# ------------------------------------------------------------------
# Waves: difficulty rises every Wave Seconds of battle time.
# ------------------------------------------------------------------
func current_wave() -> int:
	if not waves_enabled:
		return 1
	return 1 + int(battle_time / wave_length())

func seconds_to_next_wave() -> float:
	var length := wave_length()
	return length - fmod(battle_time, length)

func _update_wave() -> void:
	if wave_system_active():
		return
	var now := current_wave()
	if now == wave:
		return
	wave = now
	_set_status("WAVE %d | ENEMY ACTIVITY INCREASING" % wave, 4.0)
	wave_changed.emit(wave)

func carrier_cap() -> int:
	if wave_system_active():
		return mini(maxi(1, int(_set_value(wave_onscreen_carriers, 2))), maxi(max_carriers, wave_max_carriers))
	var extra := int(float(wave - 1) / float(maxi(1, extra_carrier_every_waves)))
	return mini(maxi(max_carriers, wave_max_carriers), max_carriers + extra)

func breacher_cap() -> int:
	if wave_system_active():
		return maxi(0, int(_set_value(wave_heavy_caps, max_breachers)))
	if wave >= extra_heavy_from_wave:
		return maxi(max_breachers, wave_max_breachers)
	return max_breachers

func missile_cap() -> int:
	# Room for a Siege Ship barrage on top of the normal limit, including
	# barrage missiles still in flight after the ship has gone.
	var extra := 0
	if not siege_ship().is_empty():
		extra = maxi(1, siege_barrage_missiles)
	var in_flight := 0
	for contact in contacts:
		if contact.kind == "missile" and contact.has("spread"):
			in_flight += 1
	return max_missiles + maxi(extra, in_flight)

func wave_interval_multiplier() -> float:
	if wave_system_active():
		return maxf(0.5, float(_set_value(wave_launch_factors, 1.0)) * set_launch_factor())
	return maxf(clampf(wave_interval_floor, 0.1, 1.0), 1.0 - maxf(0.0, wave_interval_step) * float(wave - 1))

func _capital_boxes(spot: Vector3, kind: String) -> Array:
	# Approximate space a capital ship's icon and name label take on the scope
	# (scope-radius units, +Y up): icon around the center, label just below.
	var icon_scale := 0.95 * icon_size * size_for_kind("siege_ship" if kind == "siege_ship" else "carrier")
	var icon_half := Vector2(13.0, 16.0) * 1.5 * icon_scale / 320.0
	var font := float(label_font_size + 2)
	# Labels are drawn in fixed screen pixels, so convert them by the scope radius.
	var radius := 320.0
	var dome := get_parent()
	if dome != null and "sphere_radius" in dome:
		radius = maxf(1.0, float(dome.sphere_radius))
	# Compatibility footprint only, never rendered. Preserve the original
	# placement geometry so a longer public name cannot change enemy positions.
	var legacy_key := LegacyNames.footprint_text(kind)
	var text := legacy_key + " 100%"
	var label_half := 0.5 * ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font)).x / radius + 0.02
	var baseline := 29.0 * icon_scale / 320.0
	return [Rect2(spot.x - icon_half.x, spot.y - icon_half.y, icon_half.x * 2.0, icon_half.y * 2.0),
		Rect2(spot.x - label_half, spot.y - baseline - 0.012, label_half * 2.0, font / radius + 0.012)]

func _capital_spot_free(spot: Vector3, kind: String = "carrier") -> bool:
	# Capital ships, and their name labels, must not overlap one another.
	var mine := _capital_boxes(spot, kind)
	for other in contacts:
		if other.kind in ["carrier", "unknown"]:
			for theirs in _capital_boxes(other.position, other.kind):
				for box in mine:
					if box.grow(0.012).intersects(theirs):
						return false
	return true

func _place_capital(kind: String = "carrier") -> Vector3:
	# Far upper row first (three places, like the original far band); later-wave
	# extras use a nearer second row. Small random offsets keep it from looking fixed.
	var upper := [Vector2(-0.56, 0.715), Vector2(0.0, 0.715), Vector2(0.56, 0.715)]
	var lower := [Vector2(-0.56, 0.395), Vector2(0.0, 0.395), Vector2(0.56, 0.395)]
	for row in [upper, lower]:
		var order: Array = row.duplicate()
		for index in range(order.size() - 1, 0, -1):
			var swap := rng.randi_range(0, index)
			var held: Vector2 = order[index]
			order[index] = order[swap]
			order[swap] = held
		for slot in order:
			for attempt in range(7):
				var jitter := Vector2(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.005, 0.005)) if attempt < 6 else Vector2.ZERO
				var spot := Vector3(slot.x + jitter.x, slot.y + jitter.y, rng.randf_range(0.50, 0.60))
				if _capital_spot_free(spot, kind):
					return spot
	# Last resort: sweep the two rows in small steps so a free place is never missed.
	for y in [0.715, 0.395]:
		for step in range(34):
			var spot := Vector3(-0.66 + 0.04 * step, y, 0.55)
			if _capital_spot_free(spot, kind):
				return spot
	return Vector3.INF

func _hack_point_for(left_preferred: bool) -> Vector3:
	# Park beside the ship on a free side; a third Breacher parks above the center.
	var left := own_ship_position + Vector3(-hack_park_offset.x, hack_park_offset.y, 0.0)
	var right := own_ship_position + Vector3(hack_park_offset.x, hack_park_offset.y, 0.0)
	var center := own_ship_position + Vector3(0.0, hack_park_offset.y + 0.06, 0.0)
	var taken: Array = []
	for contact in contacts:
		if contact.kind == "breacher":
			taken.append(contact.hack_point)
	for spot in ([left, right] if left_preferred else [right, left]) + [center]:
		if spot not in taken:
			return spot
	return left if left_preferred else right

# ------------------------------------------------------------------
# Spaced-out bonus repairs: 10,000, 25,000, 50,000, then every 50,000 more.
# ------------------------------------------------------------------
func repair_bonus_threshold(number: int) -> int:
	var first := maxi(1, bonus_repair_points)
	var second := maxi(first + 1, second_bonus_points)
	var third := maxi(second + 1, third_bonus_points)
	if number <= 1:
		return first
	if number == 2:
		return second
	if number == 3:
		return third
	return third + (number - 3) * maxi(1, later_bonus_step)

func repair_bonuses_for(points: int) -> int:
	var total := 0
	while total < 1000 and repair_bonus_threshold(total + 1) <= points:
		total += 1
	return total

## 1.1.0: most Rapid Repair charges that can be held on this level (0 = no limit).
func repair_limit() -> int:
	return maxi(0, rapid_repair_limit_easy if active_difficulty <= 0 else rapid_repair_limit)

## 1.1.0: adds earned Rapid Repair charges up to the limit; the rest are lost. While
## earning is paused at the limit, every earned charge is lost.
func _give_repair_charges(bonus: int) -> void:
	var limit := repair_limit()
	var added := bonus
	if limit > 0:
		added = 0 if repair_earning_paused else clampi(limit - repair_charges, 0, bonus)
	var lost := bonus - added
	repair_charges += added
	if lost > 0:
		repair_charges_lost += lost
		battle_event.emit("rapid repair charge%s lost at the limit (%d held) at %d points" % ["" if lost == 1 else "s", repair_charges, earned_points])
	if limit > 0 and repair_charges >= limit and not repair_earning_paused:
		repair_earning_paused = true
		battle_event.emit("rapid repair limit reached (%d) | earning paused until %d left" % [limit, repair_resume_charges])
	if added > 0:
		var line := "BONUS RAPID REPAIR +%d | %d CHARGE%s" % [added, repair_charges, "" if repair_charges == 1 else "S"]
		if repair_earning_paused:
			line += " | EARNING AT %d CHARGE%s" % [repair_resume_charges, "" if repair_resume_charges == 1 else "S"]
		_set_status(line, 4.0)

## 1.1.0: when a charge is used and the player is down to Repair Resume Charges, earning
## starts again at the next point total still ahead (totals passed while paused are lost).
func _check_repair_resume() -> void:
	if repair_earning_paused and repair_charges <= repair_resume_charges:
		repair_earning_paused = false
		repair_bonuses_earned = repair_bonuses_for(earned_points)
		battle_event.emit("rapid repair earning resumed at %d charge%s" % [repair_charges, "" if repair_charges == 1 else "S"])

func points_to_next_bonus() -> int:
	return repair_bonus_threshold(repair_bonuses_for(earned_points) + 1) - earned_points

# ------------------------------------------------------------------
# Siege Ship: rare, stationary, hard to kill, fires missile barrages.
# ------------------------------------------------------------------
func siege_ship() -> Dictionary:
	for contact in contacts:
		if contact.kind == "siege_ship":
			return contact
	return {}

func _update_siege_spawning(delta: float) -> void:
	if not siege_enabled or is_defeated() or safe_remaining > 0.0:
		return
	if wave < siege_first_wave or not siege_ship().is_empty():
		return
	# 1.2.0: with defined waves the Siege Ship comes in the Major engagement.
	if wave_system_active():
		return
	if siege_cooldown_remaining > 0.0:
		siege_cooldown_remaining = maxf(0.0, siege_cooldown_remaining - delta)
		return
	siege_check_remaining -= delta
	if siege_check_remaining > 0.0:
		return
	siege_check_remaining = maxf(5.0, siege_check_seconds)
	if rng.randf() < siege_chance_now():
		spawn_siege_ship()

func spawn_siege_ship() -> String:
	if is_defeated() or safe_remaining > 0.0 or not siege_ship().is_empty():
		return ""
	if count_tracks() >= max_contacts:
		return ""
	# Crosses the scope from one side to the other, chosen at random.
	var from_left := rng.randf() < 0.5
	var lane_low := minf(siege_lane.x, siege_lane.y)
	var lane_high := maxf(siege_lane.x, siege_lane.y)
	var y := rng.randf_range(lane_low, lane_high)
	var edge := sqrt(maxf(0.0, 1.0 - y * y))
	var spot := Vector3(-edge if from_left else edge, y, 0.3)
	var finish := Vector3(edge if from_left else -edge, y, 0.3)
	var id := _new_id("RS")
	contacts.append({
		"id": id, "kind": "siege_ship", "faction": "hostile",
		"start": spot, "finish": finish, "position": spot, "age": 0.0, "progress": 0.0,
		"direction": 1.0 if from_left else -1.0,
		"hits_remaining": float(scaled_hits(siege_hit_points)),
		"max_hits": float(scaled_hits(siege_hit_points)),
		"barrage_timer": maxf(0.5, siege_first_barrage_delay),
		"barrage_left": 0, "barrage_gap": 0.0, "barrage_index": 0
	})
	siege_spawns += 1
	siege_alert_pending = true
	_announce_contact(id, "siege_ship", "hostile")
	_set_status("SIEGE SHIP CROSSING %s | MISSILE BARRAGES | INTERCEPTORS, GUNSHIPS, SHIP MISSILES" % ("LEFT TO RIGHT" if from_left else "RIGHT TO LEFT"), 5.0)
	siege_arrived.emit(id)
	_update_siege_alert()
	return id

func siege_chance_now() -> float:
	# Rarer early, more frequent as the waves get tougher.
	var steps := maxi(0, wave - siege_first_wave)
	return clampf(siege_spawn_chance + siege_chance_step * steps, 0.0, maxf(siege_spawn_chance, siege_max_chance))

func siege_cooldown_now() -> float:
	var steps := maxi(0, wave - siege_first_wave)
	return maxf(minf(siege_cooldown_seconds, siege_min_cooldown), siege_cooldown_seconds - siege_cooldown_step * steps)

func siege_barrage_interval_now() -> float:
	return maxf(1.0, siege_barrage_interval) * wave_interval_multiplier() / attack_rate()

func _update_siege(ship: Dictionary, delta: float) -> void:
	# Crosses the scope, firing timed barrages, until destroyed or it reaches the far side.
	if safe_remaining > 0.0 or is_defeated():
		return
	var travel: float = ship.start.distance_to(ship.finish)
	ship.position = ship.position.move_toward(ship.finish, maxf(0.0, siege_speed) * movement_speed * delta)
	ship.progress = 1.0 if travel <= 0.0 else clampf(ship.start.distance_to(ship.position) / travel, 0.0, 1.0)
	if ship.position.distance_to(ship.finish) <= 0.002:
		_siege_escaped(ship)
		return
	ship.barrage_timer -= delta
	if ship.barrage_timer <= 0.0:
		ship.barrage_timer += siege_barrage_interval_now()
		ship.barrage_left = maxi(1, siege_barrage_missiles)
		ship.barrage_index = 0
		ship.barrage_gap = 0.0
		siege_barrages += 1
		_set_status("MISSILE BARRAGE x%d | SIEGE SHIP | FIRE DEFENSE SHIELD" % ship.barrage_left, 3.0)
	if ship.barrage_left <= 0:
		return
	ship.barrage_gap -= delta
	while ship.barrage_left > 0 and ship.barrage_gap <= 0.0:
		ship.barrage_left -= 1
		ship.barrage_gap += maxf(0.1, siege_barrage_spacing)
		var count := maxi(1, siege_barrage_missiles)
		var spread := 0.0
		if count > 1:
			spread = lerpf(-siege_missile_spread, siege_missile_spread, float(ship.barrage_index) / float(count - 1))
		ship.barrage_index += 1
		var missile_id := spawn_from_carrier("missile", ship.id)
		if not missile_id.is_empty():
			var missile := find_contact(missile_id)
			missile.spread = spread
			var path: Vector3 = own_ship_position - missile.position
			missile.side = Vector3(-path.y, path.x, 0.0).normalized() if Vector2(path.x, path.y).length() > 0.01 else Vector3.RIGHT
			missile.damage = siege_missile_damage
			siege_missiles_fired += 1

func _siege_escaped(ship: Dictionary) -> void:
	var id: String = ship.id
	_remove_contact(id)
	for index in range(contacts.size() - 1, -1, -1):
		if contacts[index].kind in ["own_missile", "gunship_missile"] and contacts[index].target_id == id:
			contacts[index].target_id = ""
	sieges_escaped += 1
	siege_cooldown_remaining = siege_cooldown_now()
	siege_check_remaining = maxf(5.0, siege_check_seconds)
	siege_alert_pending = false
	_set_status("SIEGE SHIP LEFT THE SCOPE", 3.0)

func _hit_siege(ship: Dictionary, damage: float, source: String) -> void:
	if is_defeated() or ship.is_empty() or ship.kind != "siege_ship" or find_contact(ship.id).is_empty():
		return
	ship.hits_remaining -= maxf(0.0, damage) * pulse_damage_factor(ship)
	siege_hits_by[source] = siege_hits_by.get(source, 0) + 1
	impacts.append({"position": ship.position, "age": 0.0})
	if ship.hits_remaining > 0.0:
		return
	var id: String = ship.id
	_award_destroyed(ship)
	_remove_contact(id)
	for index in range(contacts.size() - 1, -1, -1):
		if contacts[index].kind in ["own_missile", "gunship_missile"] and contacts[index].target_id == id:
			contacts[index].target_id = ""
	sieges_destroyed += 1
	siege_cooldown_remaining = siege_cooldown_now()
	siege_check_remaining = maxf(5.0, siege_check_seconds)
	siege_alert_pending = false
	_set_status("SIEGE SHIP DESTROYED | +%d POINTS" % siege_points, 4.0)
	siege_destroyed.emit(id)

func _update_siege_alert() -> void:
	if siege_alert_player == null:
		return
	siege_alert_player.volume_db = siege_alert_volume_db
	siege_alert_player.pitch_scale = siege_alert_speed
	# Nuclear warnings always take priority.
	if count_kind("nuke") > 0:
		if nuclear_player.playing or not nuclear_alert_queue.is_empty():
			siege_alert_player.stop()
		return
	if not siege_alert_pending:
		return
	if siege_ship().is_empty():
		siege_alert_pending = false
		return
	if klaxon_enabled and not klaxon_player.playing and not siege_alert_player.playing:
		siege_alert_pending = false
		siege_alert_player.play()
		siege_alert_count += 1

static func make_klaxon_sound() -> AudioStreamWAV:
	# Approved overlapping double tone, three sets with one-second rests.
	# Dedicated asset: nuclear and Siege Ship alerts keep make_alert_sequence().
	var alert := load("res://assets/audio/arrival_alert_regular.wav") as AudioStreamWAV
	if alert == null or alert.format != AudioStreamWAV.FORMAT_16_BITS or alert.stereo or alert.mix_rate != 48000 or alert.data.size() != 600540:
		push_error("Regular arrival alert must be the approved mono 48kHz PCM preview")
		return null
	# Use a fresh finite stream, as the existing special-alert loaders do.
	# The mixer must not retain the imported resource during app shutdown.
	return alert_sequence_from_pcm(alert.data, 1)

static func make_alert_sequence(repetitions: int) -> AudioStreamWAV:
	# Read the approved PCM directly, independent of Godot's WAV importer.
	# Three exact copies in one finite stream avoid runaway loop/callback state.
	var path := "res://assets/audio/radar_alert_loop.wav"
	if not FileAccess.file_exists(path):
		# Exported game: use Godot's uncompressed imported copy (same samples).
		return alert_sequence_from_pcm(exported_alert_pcm(path), repetitions)
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		push_error("Identification alert is missing or not a WAV file")
		return null
	var offset := 12
	var valid_format := false
	var pcm := PackedByteArray()
	while offset + 8 <= bytes.size():
		var tag := bytes.slice(offset, offset + 4).get_string_from_ascii()
		var length := int(bytes.decode_u32(offset + 4))
		var start := offset + 8
		if start + length > bytes.size():
			push_error("Identification alert contains a truncated WAV chunk")
			return null
		if tag == "fmt " and length >= 16:
			valid_format = bytes.decode_u16(start) == 1 and bytes.decode_u16(start + 2) == 1 and bytes.decode_u32(start + 4) == 48000 and bytes.decode_u16(start + 14) == 16
		elif tag == "data":
			pcm = bytes.slice(start, start + length)
		offset = start + length + (length & 1)
	if not valid_format or pcm.size() != 134400:
		push_error("Identification alert must be the approved 67200-frame mono 48kHz PCM loop")
		return null
	return alert_sequence_from_pcm(pcm, repetitions)

static func exported_alert_pcm(path: String) -> PackedByteArray:
	var imported := load(path) as AudioStreamWAV
	if imported == null or imported.format != AudioStreamWAV.FORMAT_16_BITS or imported.stereo or imported.mix_rate != 48000 or imported.data.size() != 134400:
		push_error("Identification alert export copy must be the approved 67200-frame mono 48kHz PCM loop")
		return PackedByteArray()
	return imported.data

static func alert_sequence_from_pcm(pcm: PackedByteArray, repetitions: int) -> AudioStreamWAV:
	if pcm.is_empty():
		return null
	var sequence := PackedByteArray()
	for repeat in range(repetitions):
		sequence.append_array(pcm)
	var stream := AudioStreamWAV.new()
	stream.mix_rate = 48000
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = sequence
	return stream

static func make_arrival_sound() -> AudioStreamWAV:
	# Original two-tone electronic beep pair. Generated as PCM, no external asset.
	var sample_rate := 48000
	var frame_total := 16800  # 0.35 seconds
	var data := PackedByteArray()
	data.resize(frame_total * 2)
	for index in range(frame_total):
		var time := float(index) / float(sample_rate)
		var value := 0.0
		for onset in [0.0, 0.19]:
			var local_time: float = time - onset
			if local_time >= 0.0 and local_time < 0.12:
				var envelope := minf(local_time / 0.007, (0.12 - local_time) / 0.018)
				envelope = clampf(envelope, 0.0, 1.0)
				value += envelope * (0.27 * sin(TAU * 1320.0 * local_time)
					+ 0.07 * sin(TAU * 1760.0 * local_time))
		data.encode_s16(index * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream

static func make_launch_sound() -> AudioStreamWAV:
	# Original short filtered-noise whoosh, with soft attack and release.
	var noise := RandomNumberGenerator.new()
	noise.seed = 10472026
	var sample_rate := 48000
	var frame_total := 26400  # 0.55 seconds
	var data := PackedByteArray()
	data.resize(frame_total * 2)
	var filtered := 0.0
	var phase := 0.0
	for index in range(frame_total):
		var t := float(index) / float(frame_total)
		var filter_amount := lerpf(0.18, 0.035, t)
		filtered = lerpf(filtered, noise.randf_range(-1.0, 1.0), filter_amount)
		var envelope := pow(sin(PI * t), 1.6)
		phase += TAU * lerpf(310.0, 95.0, t) / float(sample_rate)
		var value := envelope * (filtered * 0.9 + sin(phase) * 0.055)
		data.encode_s16(index * 2, int(clampf(value, -0.8, 0.8) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream


# ------------------------------------------------------------------
# FIREWALL: an electronic countermeasure against Breacher hacking.
# ------------------------------------------------------------------
func firewall_needed() -> bool:
	return hack_state() in ["hacking", "draining"]

func firewall_percent() -> float:
	return 100.0 * clampf(firewall_charge / maxf(0.1, firewall_seconds), 0.0, 1.0)

func can_deploy_firewall() -> bool:
	if not firewall_enabled or is_defeated() or safe_remaining > 0.0:
		return false
	if firewall_active:
		return true
	return firewall_needed() and firewall_percent() >= maxf(1.0, firewall_restart_percent)

func set_firewall(enabled: bool) -> void:
	if enabled and not firewall_active:
		if not can_deploy_firewall():
			return
		firewall_active = true
		firewall_idle = 0.0
		firewall_uses += 1
		firewall_player.volume_db = firewall_volume_db
		firewall_player.play()
		_set_status("FIREWALL UP | BREACHER HACK SLOWED", 3.0)
	elif not enabled and firewall_active:
		_end_firewall()

func _end_firewall() -> void:
	firewall_active = false
	firewall_idle = 0.0
	firewall_player.stop()
	if firewall_charge <= 0.0:
		firewall_charge = 0.0
		_set_status("FIREWALL SPENT | RECHARGING", 2.0)
	else:
		_set_status("FIREWALL DOWN | RECHARGING FROM %d%%" % int(firewall_percent()), 2.0)

func _update_firewall(delta: float) -> void:
	var full := maxf(0.1, firewall_seconds)
	firewall_player.volume_db = firewall_volume_db
	if firewall_active:
		if not firewall_needed() and not auto_firewall_holding():
			# The hack is over: lower the firewall and keep the remaining charge.
			_end_firewall()
			return
		firewall_charge = maxf(0.0, firewall_charge - delta)
		if firewall_charge <= 0.0:
			_end_firewall()
		return
	if firewall_charge >= full:
		firewall_charge = full
		return
	var wait := maxf(0.0, firewall_recharge_delay - firewall_idle)
	firewall_idle += delta
	var charging := maxf(0.0, delta - wait)
	if charging > 0.0:
		firewall_charge = minf(full, firewall_charge + charging * full / maxf(1.0, firewall_recharge_seconds))

# ------------------------------------------------------------------
# Fighter losses: Interceptors and Gunships can be shot down in battle.
# ------------------------------------------------------------------
func _damage_fighter(fighter: Dictionary, source: String) -> void:
	if fighter.is_empty() or find_contact(fighter.id).is_empty() or is_defeated():
		return
	fighter.health = int(fighter.get("health", 1)) - 1
	impacts.append({"position": fighter.position, "age": 0.0})
	var craft := "GUNSHIP" if fighter.kind == "gunship" else "INTERCEPTOR"
	if fighter.health <= 0:
		fighter_losses_by["flak" if source == "ENEMY CARRIER FIRE" else "drone"] += 1
		_lose_fighter(fighter, "%s LOST TO %s" % [craft, source])
	else:
		_set_status("%s HIT BY %s | %d%% LEFT" % [craft, source, fighter_health_percent(fighter)], 2.5)

func fighter_health_percent(fighter: Dictionary) -> int:
	return ceili(100.0 * float(fighter.get("health", 1)) / maxf(1.0, float(fighter.get("max_health", 1))))

func _lose_fighter(fighter: Dictionary, message: String) -> void:
	if fighter.is_empty() or find_contact(fighter.id).is_empty():
		return
	var penalty := gunship_loss_points if fighter.kind == "gunship" else interceptor_loss_points
	if fighter.kind == "gunship":
		gunships_lost += 1
	else:
		interceptors_lost += 1
	impacts.append({"position": fighter.position, "age": 0.0})
	_explode(fighter.position, "own_craft")
	_remove_contact(fighter.id)
	var taken := mini(score, maxi(0, penalty))
	score -= taken
	fighter_points_lost += taken
	_set_status("%s | -%d POINTS" % [message, maxi(0, penalty)], 3.0)


# ------------------------------------------------------------------
# 1.09 STEALTH INTERCEPTOR: a fast special Interceptor carrying two nuclear missiles.
# Offered on Normal and Hard when enough large ships are on screen. Hidden from
# the enemy until it fires; one hit destroys it. Rearm and rebuild are silent.
# ------------------------------------------------------------------
func large_ship_count() -> int:
	return count_kind("carrier") + count_kind("siege_ship")

func stealth_out() -> bool:
	return count_kind("stealth_interceptor") > 0

func can_launch_stealth() -> bool:
	return (stealth_interceptor_enabled and active_difficulty >= 1 and not is_defeated()
		and safe_remaining <= 0.0 and not stealth_out() and stealth_cooldown_remaining <= 0.0
		and large_ship_count() >= maxi(1, stealth_min_large_ships))

func stealth_rebuild_seconds() -> float:
	return stealth_rebuild_hard_seconds if active_difficulty >= 2 else stealth_rebuild_normal_seconds

func launch_stealth(use_pulse: bool = true) -> bool:
	if not can_launch_stealth():
		return false
	var id := _new_id("SV")
	var pulse_run := pulse_charges > 0 and use_pulse
	contacts.append({"id": id, "kind": "stealth_interceptor", "faction": "friendly",
		"position": launch_origin(0.0), "age": 0.0, "phase": "attack", "velocity": Vector3.ZERO,
		"target_id": "", "nukes_left": 1 if pulse_run else maxi(1, stealth_nukes), "shot_timer": 0.0, "revealed": false,
		"weapon": "PULSE" if pulse_run else "NUKES"})
	stealth_launches += 1
	stealth_was_ready = false
	_play_launch(1)
	if pulse_run:
		_set_status("STEALTH INTERCEPTOR LAUNCHED | PULSE BOMB STRIKE ON ENEMY CARRIERS", 3.0)
	else:
		_set_status("STEALTH INTERCEPTOR LAUNCHED | NUCLEAR STRIKE ON CAPITAL SHIPS", 3.0)
	stealth_event.emit("Stealth Interceptor launched | %d large ships on screen" % large_ship_count())
	return true

func _stealth_target(ship: Dictionary) -> Dictionary:
	var current := find_contact(ship.get("target_id", ""))
	if not current.is_empty() and current.kind in CAPITAL_KINDS:
		return current
	var chosen: Dictionary = {}
	var best := INF
	for contact in contacts:
		if contact.kind in CAPITAL_KINDS:
			var gap: float = ship.position.distance_to(contact.position)
			if gap < best:
				best = gap
				chosen = contact
	return chosen

func _update_stealth(delta: float) -> void:
	if not stealth_out():
		stealth_cooldown_remaining = maxf(0.0, stealth_cooldown_remaining - delta)
	var ready := can_launch_stealth()
	if ready and not stealth_was_ready:
		if stealth_ready_sound_enabled:
			stealth_ready_player.volume_db = stealth_ready_volume_db
			stealth_ready_player.play()
			stealth_ready_sounds += 1
		stealth_event.emit("Stealth Weapon available | %d large ships" % large_ship_count())
	stealth_was_ready = ready
	var speed := maxf(0.001, interceptor_speed) * stealth_speed_factor
	for ship in contacts.duplicate():
		if ship.kind == "stealth_nuke":
			_update_stealth_nuke(ship, delta)
			continue
		if ship.kind != "stealth_interceptor":
			continue
		ship.shot_timer = maxf(0.0, ship.shot_timer - delta)
		if ship.phase == "attack" and ship.get("weapon", "NUKES") == "PULSE":
			var aim := _pulse_aim(ship.position)
			if aim.is_empty():
				ship.phase = "return"
			else:
				var spot: Vector3 = aim.point
				var standoff: Vector3 = spot + spot.direction_to(own_ship_position) * stealth_fire_range * 0.85
				_steer(ship, standoff, speed, delta)
				if ship.position.distance_to(spot) <= stealth_fire_range:
					_drop_pulse_bomb(ship, aim)
		if ship.phase == "attack" and ship.get("weapon", "NUKES") != "PULSE":
			var target := _stealth_target(ship)
			if target.is_empty():
				# Nothing left to strike: bring the remaining nukes home.
				ship.phase = "return"
			else:
				ship.target_id = target.id
				var standoff: Vector3 = target.position + target.position.direction_to(own_ship_position) * stealth_fire_range * 0.85
				_steer(ship, standoff, speed, delta)
				if ship.position.distance_to(target.position) <= stealth_fire_range and ship.shot_timer <= 0.0:
					_fire_stealth_nuke(ship, target)
		if ship.phase == "return":
			_steer(ship, launch_origin(0.0), speed, delta)
			if ship.position.distance_to(launch_origin(0.0)) <= 0.03:
				_remove_contact(ship.id)
				stealth_recovered += 1
				stealth_cooldown_remaining = maxf(1.0, stealth_rearm_seconds)
				stealth_event.emit("Stealth Interceptor recovered | rearming %ds" % int(stealth_cooldown_remaining))

func _fire_stealth_nuke(ship: Dictionary, target: Dictionary) -> void:
	var id := _new_id("SN")
	contacts.append({"id": id, "kind": "stealth_nuke", "faction": "friendly",
		"position": ship.position, "age": 0.0, "target_id": target.id, "target_position": target.position})
	ship.nukes_left -= 1
	ship.revealed = true
	ship.shot_timer = maxf(1.0, stealth_shot_seconds)
	stealth_nukes_fired += 1
	_set_status("STEALTH INTERCEPTOR NUKE AWAY | %s TARGETED" % ("SIEGE SHIP" if target.kind == "siege_ship" else "ENEMY CARRIER"), 2.5)
	stealth_event.emit("Stealth Interceptor fired a nuke at %s | %d left" % [target.id, ship.nukes_left])
	if ship.nukes_left <= 0:
		ship.phase = "return"

func _update_stealth_nuke(nuke: Dictionary, delta: float) -> void:
	var target := find_contact(nuke.target_id)
	if target.is_empty() or target.kind not in CAPITAL_KINDS:
		# Its target is gone: turn toward the nearest other large ship.
		target = _stealth_target({"position": nuke.position, "target_id": ""})
		if target.is_empty() or nuke.age > 20.0:
			_remove_contact(nuke.id)
			return
		nuke.target_id = target.id
	nuke.target_position = target.position
	nuke.position = nuke.position.move_toward(target.position, delta * movement_speed * stealth_nuke_speed)
	if nuke.position.distance_to(target.position) > 0.025:
		return
	_remove_contact(nuke.id)
	stealth_nuke_hits += 1
	var damage := float(target.max_hits) * clampf(stealth_nuke_strength, 0.1, 1.0)
	_explode(target.position, "missile")
	if target.kind == "siege_ship":
		_hit_siege(target, damage, "stealth")
	else:
		_hit_carrier(target, damage)

func _lose_stealth(ship: Dictionary) -> void:
	if ship.is_empty() or find_contact(ship.id).is_empty():
		return
	stealth_lost += 1
	impacts.append({"position": ship.position, "age": 0.0})
	_explode(ship.position, "own_craft")
	_remove_contact(ship.id)
	stealth_cooldown_remaining = stealth_rebuild_seconds()
	_set_status("STEALTH INTERCEPTOR LOST TO ATTACK DRONE FIRE", 3.0)
	stealth_event.emit("Stealth Interceptor destroyed | rebuilding %ds" % int(stealth_cooldown_remaining))

static func make_stealth_ready_sound() -> AudioStreamWAV:
	# Original bright three-note rising chime with a soft shimmer. Generated PCM.
	var sample_rate := 48000
	var frame_total := 33600  # 0.7 seconds
	var data := PackedByteArray()
	data.resize(frame_total * 2)
	var notes := [[0.0, 1318.5], [0.11, 1661.2], [0.22, 1975.5]]
	for index in range(frame_total):
		var time := float(index) / float(sample_rate)
		var value := 0.0
		for note in notes:
			var local_time: float = time - float(note[0])
			if local_time >= 0.0:
				var envelope := minf(local_time / 0.006, 1.0) * exp(-local_time * 5.5)
				var freq: float = note[1]
				value += envelope * (0.20 * sin(TAU * freq * local_time)
					+ 0.06 * sin(TAU * freq * 2.0 * local_time)
					+ 0.03 * sin(TAU * freq * 3.01 * local_time))
		var tail := clampf((0.7 - time) / 0.08, 0.0, 1.0)
		data.encode_s16(index * 2, int(clampf(value * tail, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream

# 1.0.5 PER-SHIP READINESS (was the 1.1.0 shared landing pause) AND NUKE SPEED -------

## Interceptors not out on the scope (ready or counting down).
func interceptors_in_hangar() -> int:
	return maxi(0, interceptor_limit() - count_interceptors())

## Gunships not out on the scope (ready or counting down).
func gunships_in_hangar() -> int:
	return maxi(0, gunship_limit() - count_kind("gunship"))

## Interceptors that can launch right now.
func interceptors_ready() -> int:
	return maxi(0, interceptors_in_hangar() - interceptor_waits.size())

## Gunships that can launch right now.
func gunships_ready() -> int:
	return maxi(0, gunships_in_hangar() - gunship_waits.size())

## 1.0.6: how many Interceptors the next LAUNCH press sends (at most
## interceptors_per_launch, normally 2). The button shows this, not the whole hangar.
func interceptors_next_launch() -> int:
	return mini(maxi(1, interceptors_per_launch), interceptors_ready())

## 1.0.6: how many Gunships the next LAUNCH press sends (one at a time).
func gunships_next_launch() -> int:
	return mini(1, gunships_ready())

## Seconds until the next Interceptor is ready. 0 when one is ready now, or when none
## are in the hangar (all deployed: nothing to wait for).
func interceptor_ready_in() -> float:
	return _next_ready_in(interceptor_waits, interceptors_ready(), interceptors_in_hangar())

## Seconds until the next Gunship is ready (0 when one is ready or all are deployed).
func gunship_ready_in() -> float:
	return _next_ready_in(gunship_waits, gunships_ready(), gunships_in_hangar())

func _next_ready_in(waits: Array[Dictionary], ready: int, hangar: int) -> float:
	if ready > 0 or hangar <= 0 or waits.is_empty():
		return 0.0
	var soonest := INF
	for wait in waits:
		soonest = minf(soonest, float(wait.left))
	return maxf(0.0, soonest)

## Count down each waiting ship; a ship whose wait ends is ready. If the hangar got
## smaller (a boost ended), the longest waits go first.
func _tick_waits(waits: Array[Dictionary], hangar: int, delta: float) -> void:
	for index in range(waits.size() - 1, -1, -1):
		waits[index].left = float(waits[index].left) - delta
		if waits[index].left <= 0.0:
			waits.remove_at(index)
	while waits.size() > maxi(0, hangar):
		var longest := 0
		for index in range(waits.size()):
			if waits[index].left > waits[longest].left:
				longest = index
		waits.remove_at(longest)

## After a launch: the given number of ready ships wait Seconds before the next launch.
func _hold_ready(waits: Array[Dictionary], count: int, seconds: float) -> void:
	if seconds <= 0.0:
		return
	for index in range(maxi(0, count)):
		waits.append({"left": seconds, "why": "launch"})

## Remove waits of one kind ("launch" or "landing"), or all with "".
func _clear_waits(waits: Array[Dictionary], why: String = "") -> void:
	for index in range(waits.size() - 1, -1, -1):
		if why == "" or waits[index].why == why:
			waits.remove_at(index)

## An Interceptor or Gunship has landed: that ship waits its recovery time before it is
## ready again. Other ships keep their own countdowns (1.0.5).
func _hold_after_landing(kind: String) -> void:
	if kind == "interceptor" and interceptor_recovery_seconds > 0.0:
		interceptor_waits.append({"left": interceptor_recovery_seconds, "why": "landing"})
		interceptor_recovery_holds += 1
	elif kind == "gunship" and gunship_recovery_seconds > 0.0:
		gunship_waits.append({"left": gunship_recovery_seconds, "why": "landing"})
		gunship_recovery_holds += 1

## Speed bonus for a new Enemy Carrier nuke: 0 to Nuke Speed Random Max, even on Easy and
## Normal; on Hard the larger of two picks (leans to the top end).
func nuke_speed_bonus() -> float:
	var top := maxf(0.0, nuke_speed_random_max)
	if top <= 0.0:
		return 0.0
	var pick := rng.randf()
	if active_difficulty >= 2 and hard_nuke_speed_lean:
		pick = maxf(pick, rng.randf())
	return pick * top

# 1.1.0 ATTACK DRONES FOCUS FIRE ON A REVEALED STEALTH INTERCEPTOR -------------------------

## The Stealth Interceptor once it has fired (empty while hidden or not out).
func revealed_stealth() -> Dictionary:
	for contact in contacts:
		if contact.kind == "stealth_interceptor" and contact.get("revealed", false):
			return contact
	return {}

## Returns true when this Attack Drone is busy with the Stealth Interceptor this frame. Each
## Attack Drone within Stealth Focus Range chases it for Stealth Pursuit Distance only,
## shooting from Stealth Shot Range, then gives up and goes back to its job.
func _drone_focus_stealth(drone: Dictionary, delta: float) -> bool:
	var stealth := revealed_stealth()
	if stealth.is_empty() or drone.get("stealth_done", "") == stealth.id:
		return false
	var gap: float = drone.position.distance_to(stealth.position)
	if drone.get("stealth_chasing", "") != stealth.id:
		if gap > stealth_focus_range:
			return false
		drone.stealth_chasing = stealth.id
		drone.stealth_chased = 0.0
		stealth_pursuits += 1
	drone.stealth_shot_cooldown = maxf(0.0, drone.get("stealth_shot_cooldown", 0.0) - delta)
	if gap <= stealth_shot_range and drone.stealth_shot_cooldown <= 0.0:
		drone.stealth_shot_cooldown = maxf(0.3, stealth_shot_interval)
		stealth_shots_taken += 1
		if rng.randf() < clampf(stealth_hit_chance, 0.0, 1.0):
			_lose_stealth(stealth)
			drone.stealth_done = stealth.id
			return true
	var before: Vector3 = drone.position
	_steer(drone, stealth.position, drone_speed() * 1.3, delta)
	drone.stealth_chased += before.distance_to(drone.position)
	if drone.stealth_chased >= stealth_pursuit_distance or gap > stealth_focus_range * 1.5:
		drone.stealth_done = stealth.id
	return true

# ------------------------------------------------------------------
# 1.2.0 Defined waves: CONTACT/ASSAULT -> CLEARED -> REST, sets of five,
# traits, set tactics, bonus sweep, tally, set multiplier, Systems Bonus.
# ------------------------------------------------------------------
const WAVE_TRAITS: Array[String] = ["ATTACK DRONE SWARM", "MISSILE BARRAGE", "NUCLEAR STRIKE", "HEAVY ASSAULT", "ESCORT"]
const TRAIT_LINES := {
	"ATTACK DRONE SWARM": "MORE ATTACK DRONES, FEWER MISSILES",
	"MISSILE BARRAGE": "MISSILES LAUNCH MORE OFTEN",
	"NUCLEAR STRIKE": "ENEMY CARRIERS LAUNCH NUKES EARLY",
	"HEAVY ASSAULT": "BREACHERS LAUNCH MORE OFTEN",
	"ESCORT": "ENEMY CARRIERS ARRIVE CLOSE TOGETHER"}
const SET_MODIFIERS: Array[String] = ["QUICKER LAUNCHES", "HARDENED ENEMY CARRIERS", "FASTER HACKING", "FASTER WARHEADS"]
const BONUS_LABELS := {
	"REPAIR": "EXTRA RAPID REPAIR", "EMP": "EXTRA EMP CHARGE", "INTERCEPTORS": "EXTRA INTERCEPTOR SQUADRON",
	"GUNSHIP": "EXTRA GUNSHIP", "SPEED": "FIGHTER SPEED +15%", "AUTO SHIELD": "FREE AUTO SHIELD",
	"RAPID FIRE": "RAPID FIRE", "STEALTH": "STEALTH INTERCEPTOR READY"}
const BOOST_LINES := {
	"INTERCEPTORS": "BONUS: +2 INTERCEPTORS", "GUNSHIP": "BONUS: +1 GUNSHIP", "SPEED": "BONUS: FIGHTER SPEED",
	"AUTO SHIELD": "BONUS: FREE AUTO SHIELD", "RAPID FIRE": "BONUS: RAPID FIRE"}

func wave_system_active() -> bool:
	return waves_enabled and defined_waves and auto_spawn

func _reset_wave_system() -> void:
	wave_phase = "assault"
	wave_next_phase = "assault"
	wave_force_spawned = 0
	wave_assault_time = 0.0
	wave_siege_spawned = false
	wave_rest_remaining = 0.0
	wave_inbound_announced = false
	wave_trait = ""
	upcoming_trait = ""
	set_traits_used.clear()
	sets_completed = 0
	waves_cleared = 0
	waves_escaped = 0
	wave_bonus_points = 0
	last_wave_bonus = 0
	last_cleared_wave = 0
	last_systems_bonus = ""
	last_bonus_label = ""
	systems_bonus_counts = {}
	active_boosts = {}
	fighters_jumped_out = 0
	rest_jumps = 0
	sweep_spawned = 0
	sweep_destroyed = 0
	sweep_escaped = 0
	sweep_timer = 0.0
	sweep_groups = 0
	sweeps_flown = 0
	sweeps_perfect = 0
	last_sweep_result = ""
	rest_after_sweep = false
	_reset_protect_state()
	protect_rounds = 0
	protect_result_started = -100.0
	protect_result_sound_count = 0
	last_protect_result_sound = ""
	protect_full_fleets = 0
	interceptor_limit_hold = 0
	gunship_limit_hold = 0
	action_stations_count = 0
	all_clear_count = 0

## Place of the current wave in its set: 1 (Probe) .. set size (Major engagement).
func wave_position() -> int:
	return ((maxi(1, wave) - 1) % maxi(1, wave_set_size)) + 1

func wave_set_number() -> int:
	return int((maxi(1, wave) - 1) / maxi(1, wave_set_size)) + 1

func is_major_wave() -> bool:
	return wave_position() == maxi(1, wave_set_size)

func _set_value(values: Array, fallback: Variant, position: int = -1) -> Variant:
	if values.is_empty():
		return fallback
	var index := (wave_position() if position < 0 else position) - 1
	return values[clampi(index, 0, values.size() - 1)]

func wave_name(number: int = -1) -> String:
	var position := wave_position() if number < 0 else ((maxi(1, number) - 1) % maxi(1, wave_set_size)) + 1
	return str(_set_value(wave_names, "WAVE", position))

func wave_force_quota() -> int:
	var table: Array[int] = [easy_wave_force, normal_wave_force, hard_wave_force][clampi(active_difficulty, 0, 2)]
	return maxi(1, int(_set_value(table, 2)))

func rest_seconds() -> float:
	return maxf(1.0, [easy_rest_seconds, normal_rest_seconds, hard_rest_seconds][clampi(active_difficulty, 0, 2)])

func set_score_multiplier() -> float:
	return minf(maxf(1.0, set_score_cap), 1.0 + maxf(0.0, set_score_step) * sets_completed)

## Times a set tactic has been added, and its effect with full first steps
## and half steps later (Easy: always half).
func set_modifier_count(name: String) -> int:
	if not set_modifiers_enabled:
		return 0
	var count := 0
	for k in range(1, sets_completed + 1):
		if SET_MODIFIERS[(k - 1) % SET_MODIFIERS.size()] == name:
			count += 1
	return count

func _modifier_product(name: String, full: float, half: float) -> float:
	var value := 1.0
	for j in range(set_modifier_count(name)):
		value *= half if (j > 0 or active_difficulty == 0) else full
	return value

func set_launch_factor() -> float:
	return maxf(0.5, _modifier_product("QUICKER LAUNCHES", 0.85, 0.925))

func set_carrier_hits_bonus() -> int:
	return mini(2 if active_difficulty == 0 else 3, set_modifier_count("HARDENED ENEMY CARRIERS"))

## Hack speed multiplier (hack time shrinks to no less than 60%).
func set_hack_factor() -> float:
	return 1.0 / maxf(0.6, _modifier_product("FASTER HACKING", 0.85, 0.925))

func set_warhead_factor() -> float:
	return minf(1.3, _modifier_product("FASTER WARHEADS", 1.08, 1.04))

func newest_set_modifier() -> String:
	if not set_modifiers_enabled or sets_completed <= 0:
		return ""
	return SET_MODIFIERS[(sets_completed - 1) % SET_MODIFIERS.size()]

func trait_active(name: String) -> bool:
	return wave_system_active() and wave_phase == "assault" and wave_trait == name

func drone_interval_factor() -> float:
	return wave_interval_multiplier() * (0.7 if trait_active("ATTACK DRONE SWARM") else 1.0)

func missile_interval_factor() -> float:
	var trait_factor := 1.0
	if trait_active("MISSILE BARRAGE"):
		trait_factor = 0.7
	elif trait_active("ATTACK DRONE SWARM"):
		trait_factor = 1.3
	return wave_interval_multiplier() * trait_factor

func heavy_interval_factor() -> float:
	return 0.6 if trait_active("HEAVY ASSAULT") else 1.0

func nuclear_delay_factor() -> float:
	return 0.5 if trait_active("NUCLEAR STRIKE") else 1.0

func capital_arrival_factor() -> float:
	return 0.4 if trait_active("ESCORT") else 1.0

func boost_active(name: String) -> bool:
	return active_boosts.has(name)

func interceptor_limit() -> int:
	# 1.2.2: in Protect the fleet, Interceptor launches can't exceed the Attack Drone count.
	if protect_active():
		# 1.2.9 Fewer Interceptors: the round can hold back a few launches.
		return count_interceptors() + maxi(0, protect_interceptor_total() - protect_interceptors_launched)
	var limit := max_interceptors + (bonus_extra_interceptors if boost_active("INTERCEPTORS") else 0)
	return maxi(limit, mini(interceptor_limit_hold, count_interceptors()))

## Total Interceptor launches allowed this round (0.1.2: Normal Interceptor Share).
func protect_interceptor_total() -> int:
	if active_difficulty == 1 and protect_normal_interceptor_share < 1.0:
		var share := maxi(1, ceili(float(protect_drones_total) * protect_normal_interceptor_share))
		return maxi(1, share - (protect_short_interceptors if protect_normal_fewer_on_top else 0))
	if active_difficulty == 2 and protect_hard_interceptor_share < 1.0:
		var hard_share := maxi(1, ceili(float(protect_drones_total) * protect_hard_interceptor_share))
		return maxi(1, hard_share - (protect_short_interceptors if protect_hard_fewer_on_top else 0))
	return protect_drones_total - protect_short_interceptors

func _gunship_patch() -> float:
	if active_difficulty == 2:
		return protect_hard_gunship_patch
	return protect_normal_gunship_patch if active_difficulty == 1 else 0.0

func _patch_used_up(ship: Dictionary) -> bool:
	return _gunship_patch() > 0.0 and float(ship.get("patched", 0.0)) >= _gunship_patch() - 0.0001

func gunship_limit() -> int:
	if protect_active():
		return 0
	var limit := max_gunships + (bonus_extra_gunships if boost_active("GUNSHIP") else 0)
	return maxi(limit, mini(gunship_limit_hold, count_kind("gunship")))

func fighter_speed_factor() -> float:
	return bonus_speed_factor if boost_active("SPEED") else 1.0

func fire_interval_factor() -> float:
	return clampf(bonus_fire_factor, 0.3, 1.0) if boost_active("RAPID FIRE") else 1.0

## Auto shield from Settings, or free (no score penalty) from the Systems Bonus.
func battery_auto_on() -> bool:
	return auto_defense_battery or boost_active("AUTO SHIELD")

func capitals_on_scope() -> int:
	return count_kind("carrier") + count_kind("unknown") + count_kind("siege_ship")

func pending_capitals() -> int:
	var total := 0
	for request in pending:
		if request.kind == "unknown":
			total += 1
	return total

## Enemy Carriers of this wave still to destroy (arrived or still coming).
func wave_force_left() -> int:
	return maxi(0, wave_force_quota() - wave_force_spawned) + count_kind("carrier") + count_kind("unknown")

func wave_wants_carrier() -> bool:
	if wave_phase != "assault" or wave_assault_time >= wave_safety_seconds:
		return false
	return wave_force_spawned + pending_capitals() < wave_force_quota()

func _wave_force_done() -> bool:
	if wave_force_spawned < wave_force_quota() and wave_assault_time < wave_safety_seconds:
		return false
	if capitals_on_scope() > 0 or pending_capitals() > 0:
		return false
	if _major_needs_siege() and wave_assault_time < wave_safety_seconds:
		return false
	return true

func _major_needs_siege() -> bool:
	return is_major_wave() and major_siege and siege_enabled and not wave_siege_spawned

func _update_wave_system(delta: float) -> void:
	if not wave_system_active() or is_defeated():
		return
	match wave_phase:
		"assault":
			if safe_remaining > 0.0:
				return
			wave_assault_time += delta
			if _major_needs_siege() and wave_assault_time >= major_siege_delay:
				if not spawn_siege_ship().is_empty():
					wave_siege_spawned = true
			if _wave_force_done():
				_clear_wave()
		"rest":
			wave_rest_remaining = maxf(0.0, wave_rest_remaining - delta)
			if not wave_inbound_announced and wave_rest_remaining <= inbound_seconds:
				wave_inbound_announced = true
				_set_status(inbound_message(), inbound_seconds + 3.0)
				_play_wave_cue(action_stations_player)
				action_stations_count += 1
			if wave_rest_remaining <= 0.0 and safe_remaining <= 0.0:
				if wave_next_phase == "protect":
					_start_protect()
				elif wave_next_phase == "sweep":
					_start_sweep()
				else:
					_start_wave(wave + 1)
		"sweep":
			if safe_remaining <= 0.0:
				_update_sweep(delta)
		"protect":
			if safe_remaining <= 0.0:
				_update_protect(delta)

func next_wave_number() -> int:
	return wave if wave_next_phase in ["sweep", "protect"] else wave + 1

func inbound_message() -> String:
	if wave_next_phase == "protect":
		return "PROTECT THE CONVOY INBOUND | SUPPORT SHIPS UNDER ATTACK DRONE ATTACK | INTERCEPTORS ONLY"
	if wave_next_phase == "sweep":
		return "BONUS SWEEP INBOUND | ATTACK DRONES CROSSING | NO MISSILES"
	var number := wave + 1
	var text := "WAVE %d INBOUND | %s" % [number, wave_name(number)]
	if not upcoming_trait.is_empty():
		text += " | " + upcoming_trait
	var position := ((number - 1) % maxi(1, wave_set_size)) + 1
	if position == 1 and not newest_set_modifier().is_empty():
		text += " | NEW ENEMY TACTIC: %s | SCORE x%.2f" % [newest_set_modifier(), set_score_multiplier()]
	return text

func _clear_wave() -> void:
	waves_cleared += 1
	last_cleared_wave = wave
	rest_after_sweep = false
	rest_after_protect = false
	var set_done := is_major_wave()
	var tally := wave_clear_points + wave_hull_points * hull_percent() + (set_clear_points if set_done else 0)
	last_wave_bonus = points_for(tally)
	_add_points(last_wave_bonus)
	wave_bonus_points += last_wave_bonus
	var jumped := 0
	for index in range(contacts.size() - 1, -1, -1):
		if contacts[index].kind in ["drone", "breacher"]:
			jumped += 1
			contacts.remove_at(index)
	fighters_jumped_out += jumped
	last_bonus_label = _award_systems_bonus()
	if set_done:
		sets_completed += 1
	wave_next_phase = "assault"
	if set_done and set_end_round == 0:
		wave_next_phase = "protect"
	elif set_done and set_end_round == 1:
		wave_next_phase = "sweep"
	upcoming_trait = "" if wave_next_phase != "assault" else _draw_trait(wave + 1)
	_begin_rest()
	var line := "WAVE %d CLEARED | +%d" % [wave, last_wave_bonus]
	if not last_bonus_label.is_empty():
		line += " | SYSTEMS BONUS: " + last_bonus_label
	_set_status(line, maxf(2.0, wave_rest_remaining - inbound_seconds))
	_play_wave_cue(all_clear_player)
	all_clear_count += 1
	battle_event.emit("wave %d cleared (%s) | bonus %d | hull %d%% | systems bonus %s | Enemy fighters jumped out %d" % [
		wave, wave_name(), last_wave_bonus, hull_percent(), last_bonus_label if not last_bonus_label.is_empty() else "none", jumped])
	if set_done:
		battle_event.emit("set %d complete | score x%.2f" % [sets_completed, set_score_multiplier()])
	wave_cleared.emit(wave)
	# 0.1.2: a pick held during the wave is offered now; otherwise, with both missile
	# bonuses earned, the pick is offered again after each set.
	if _offer_waiting_missile_bonus():
		return
	if set_done and missile_bonus_offer_each_set and both_missile_bonuses_earned() and not missile_bonus_offer_open:
		_offer_missile_bonus(missile_bonus_pick, true)

## 0.1.2: offers a pick held for the end of the round. True when one was offered.
func _offer_waiting_missile_bonus() -> bool:
	if not missile_bonus_offer_waiting:
		return false
	missile_bonus_offer_waiting = false
	_offer_missile_bonus(missile_bonus_pick, false)
	return true

func _begin_rest() -> void:
	wave_phase = "rest"
	wave_rest_remaining = rest_seconds()
	wave_inbound_announced = false

func _draw_trait(number: int) -> String:
	if not traits_enabled:
		return ""
	var position := ((maxi(1, number) - 1) % maxi(1, wave_set_size)) + 1
	var set_number := int((maxi(1, number) - 1) / maxi(1, wave_set_size)) + 1
	var positions := [3, 4]
	if active_difficulty == 2:
		positions = [2, 3, 4]
	elif active_difficulty == 0 and set_number < 2:
		positions = []
	if position not in positions:
		return ""
	if position == positions[0]:
		set_traits_used.clear()
	var choices: Array[String] = []
	for name in WAVE_TRAITS:
		if name not in set_traits_used:
			choices.append(name)
	if choices.is_empty():
		return ""
	var picked: String = choices[rng.randi_range(0, choices.size() - 1)]
	set_traits_used.append(picked)
	return picked

func _start_wave(number: int) -> void:
	wave = maxi(1, number)
	wave_phase = "assault"
	wave_force_spawned = 0
	wave_assault_time = 0.0
	wave_siege_spawned = false
	wave_trait = upcoming_trait
	upcoming_trait = ""
	wave_countdown = 0.0
	var line := "WAVE %d | %s | %d ENEMY CARRIERS" % [wave, wave_name(), wave_force_quota()]
	if is_major_wave() and major_siege and siege_enabled:
		line += " + SIEGE SHIP"
	if not wave_trait.is_empty():
		line += " | %s: %s" % [wave_trait, TRAIT_LINES.get(wave_trait, "")]
	_set_status(line, 5.0)
	battle_event.emit("wave %d start (%s, set %d) | force %d | trait %s | score x%.2f" % [
		wave, wave_name(), wave_set_number(), wave_force_quota(), wave_trait if not wave_trait.is_empty() else "none", set_score_multiplier()])
	wave_changed.emit(wave)

## 1.2.2: Systems Bonus schedule. None before Bonus Start Wave (Hard: one set later);
## then a Bonus Wave Chance per cleared wave (Hard: halved), always at the end of a
## set. Tiers by set (low, medium, high), sometimes from a lower unlocked tier.
## Skips bonuses that cannot help now and never the same twice running.
func _award_systems_bonus() -> String:
	if boost_active("INTERCEPTORS"):
		interceptor_limit_hold = count_interceptors()
	if boost_active("GUNSHIP"):
		gunship_limit_hold = count_kind("gunship")
	active_boosts = {}
	if not systems_bonus_enabled or not systems_bonus_due():
		return ""
	var tiers := unlocked_bonus_tiers()
	if tiers.is_empty():
		return ""
	var top: int = tiers[-1]
	var first := top
	if tiers.size() > 1 and rng.randf() < clampf(bonus_lower_tier_chance, 0.0, 1.0):
		first = tiers[rng.randi_range(0, tiers.size() - 2)]
	# Draw from the chosen tier; when nothing there can help, fall back to lower tiers.
	var picked := ""
	for tier in range(first, -1, -1):
		if tier not in tiers:
			continue
		picked = _pick_bonus_from(bonus_tier_names(tier))
		if not picked.is_empty():
			break
	if picked.is_empty():
		return ""
	match picked:
		"REPAIR": _give_repair_charges(1)
		"EMP": emp_charges += 1
		"STEALTH": stealth_cooldown_remaining = 0.0
		_: active_boosts[picked] = true
	last_systems_bonus = picked
	systems_bonus_counts[picked] = int(systems_bonus_counts.get(picked, 0)) + 1
	return str(BONUS_LABELS.get(picked, picked))

## Set number used for the bonus schedule (Hard counts one set later).
func bonus_schedule_set() -> int:
	return wave_set_number() - (maxi(0, hard_bonus_set_delay) if active_difficulty == 2 else 0)

func bonus_first_wave() -> int:
	return maxi(1, bonus_start_wave) + (maxi(0, hard_bonus_set_delay) * maxi(1, wave_set_size) if active_difficulty == 2 else 0)

func bonus_chance() -> float:
	return clampf(bonus_wave_chance * (hard_bonus_chance_factor if active_difficulty == 2 else 1.0), 0.0, 1.0)

## Whether the wave just cleared gives a Systems Bonus (rolls the chance).
func systems_bonus_due() -> bool:
	if wave < bonus_first_wave():
		return false
	if is_major_wave():
		return true
	return rng.randf() < bonus_chance()

## Tier numbers unlocked for the current set: 0 low, 1 medium, 2 high.
func unlocked_bonus_tiers() -> Array[int]:
	var tiers: Array[int] = []
	var number := bonus_schedule_set()
	for tier in range(3):
		if number >= [bonus_low_tier_set, bonus_medium_tier_set, bonus_high_tier_set][tier]:
			tiers.append(tier)
	return tiers

func bonus_tier_names(tier: int) -> Array[String]:
	var names: Array[String] = []
	names.assign([bonus_low_tier, bonus_medium_tier, bonus_high_tier][clampi(tier, 0, 2)])
	return names

func _pick_bonus_from(names: Array[String]) -> String:
	var eligible: Array[String] = []
	for name in names:
		if name in systems_bonuses and _bonus_applies(name):
			eligible.append(name)
	if eligible.size() > 1:
		var others: Array[String] = []
		for name in eligible:
			if name != last_systems_bonus:
				others.append(name)
		if not others.is_empty():
			eligible = others
	if eligible.is_empty():
		return ""
	return eligible[rng.randi_range(0, eligible.size() - 1)]

func _bonus_applies(name: String) -> bool:
	match name:
		# 1.1.0: with a Rapid Repair limit, offered only while earning is not paused.
		"REPAIR": return (not repair_earning_paused and repair_charges < repair_limit()) if repair_limit() > 0 else repair_charges < bonus_repair_cap
		"EMP": return emp_enabled and emp_charges < maxi(1, emp_max_charges)
		"STEALTH": return stealth_interceptor_enabled and active_difficulty > 0 and not stealth_out() and stealth_cooldown_remaining > 0.0
		# 1.2.2: a free auto shield is wasted when AUTO DEFENSE SHIELD is already on.
		"AUTO SHIELD": return not auto_defense_battery
		"INTERCEPTORS", "GUNSHIP", "SPEED", "RAPID FIRE": return true
	return false

## After an JUMP jump: from the rest it is free and starts the next wave early;
## mid-wave the wave counts as escaped and starts again.
func _wave_after_jump(rest_jump: bool) -> void:
	if rest_jump:
		rest_jumps += 1
		safe_remaining = maxf(0.5, rest_jump_safe_seconds)
		_add_points(points_for(jump_rest_jump_points))
		wave_rest_remaining = 0.0
		wave_inbound_announced = true
		_set_status("JUMP DURING REST | NO COST | +%d | %s" % [points_for(jump_rest_jump_points), inbound_message()], safe_remaining + 3.0)
		battle_event.emit("JUMP jump during rest | no cost | next wave early")
		return
	if wave_phase == "sweep":
		_end_sweep()
		return
	if wave_phase == "protect":
		_end_protect("JUMP", true)
		return
	if wave_phase == "assault":
		waves_escaped += 1
		wave_force_spawned = 0
		wave_assault_time = 0.0
		wave_siege_spawned = false
		battle_event.emit("wave %d escaped by JUMP | the wave starts again" % wave)
		_set_status("JUMP COMPLETE | -%d POINTS | WAVE %d STARTS AGAIN" % [last_jump_cost, wave], safe_remaining)

func _start_sweep() -> void:
	wave_phase = "sweep"
	sweep_spawned = 0
	sweep_destroyed = 0
	sweep_escaped = 0
	sweep_groups = 0
	sweep_timer = 0.0
	sweeps_flown += 1
	_set_status("BONUS SWEEP | ATTACK DRONES CROSSING | DESTROY THEM ALL FOR A PERFECT BONUS", 5.0)
	battle_event.emit("bonus sweep start | %d Attack Drones" % sweep_drones)

func sweep_left() -> int:
	var total := 0
	for contact in contacts:
		if contact.get("phase", "") == "sweep":
			total += 1
	return total

func _update_sweep(delta: float) -> void:
	sweep_timer -= delta
	# The usual Attack Drone and track limits still apply; a group waits for room.
	var room := mini(max_drones - count_kind("drone"), max_contacts - count_tracks())
	if sweep_spawned < sweep_drones and sweep_timer <= 0.0 and room > 0:
		_spawn_sweep_group(room)
		sweep_timer = maxf(0.5, sweep_group_gap)
	if sweep_spawned >= sweep_drones and sweep_left() == 0:
		_end_sweep()

func _spawn_sweep_group(room: int = 99) -> void:
	var from_left := sweep_groups % 2 == 0
	sweep_groups += 1
	var lane := rng.randf_range(-0.35, 0.25)
	for slot in range(mini(mini(maxi(1, sweep_group_size), room), sweep_drones - sweep_spawned)):
		var y := lane + 0.06 * slot
		var edge := sqrt(maxf(0.0, 1.0 - y * y))
		var back := 0.08 * slot
		var start := Vector3((-edge - back) if from_left else (edge + back), y, 0.1)
		var exit := Vector3(edge if from_left else -edge, y, 0.1)
		var id := _new_id("H")
		contacts.append({
			"id": id, "kind": "drone", "faction": "hostile", "position": start,
			"start": start, "finish": exit, "sweep_exit": exit, "age": 0.0, "progress": 0.0,
			"origin_id": "", "origin_position": start, "target_position": exit,
			"defense_checked": false, "phase": "sweep", "patrol_angle": 0.0,
			"approach_point": exit, "velocity": Vector3.ZERO, "health": 1,
			"attack_cooldown": 0.0, "next_battery_shot": 0.0})
		sweep_spawned += 1
		if slot == 0:
			_announce_contact(id, "drone", "hostile")

func _end_sweep() -> void:
	var perfect := sweep_spawned > 0 and sweep_destroyed >= sweep_spawned
	var bonus := 0
	if perfect and wave_phase == "sweep":
		sweeps_perfect += 1
		bonus = points_for(sweep_perfect_points)
		_add_points(bonus)
		wave_bonus_points += bonus
	for index in range(contacts.size() - 1, -1, -1):
		if contacts[index].get("phase", "") == "sweep":
			contacts.remove_at(index)
	last_sweep_result = "%d OF %d%s" % [sweep_destroyed, sweep_spawned, ("  PERFECT +%d" % bonus) if perfect else ""]
	wave_next_phase = "assault"
	rest_after_sweep = true
	upcoming_trait = _draw_trait(wave + 1)
	_begin_rest()
	_set_status("BONUS SWEEP COMPLETE | %s" % last_sweep_result, maxf(2.0, wave_rest_remaining - inbound_seconds))
	battle_event.emit("bonus sweep complete | %d of %d destroyed | perfect %s | bonus %d" % [sweep_destroyed, sweep_spawned, str(perfect), bonus])
	# 1.0.6: a missile bonus pick held during the sweep is offered now.
	_offer_waiting_missile_bonus()

# ------------------------------------------------------------------
# 1.2.2 Protect the fleet: after each Major engagement the scope is reset and
# 2 to 4 civilian ships come under Attack Drone attack. Interceptors only.
# ------------------------------------------------------------------
const CIVILIAN_KINDS: Array[String] = ["civilian_a", "civilian_b", "civilian_c", "civilian_d", "civilian_e"]
## Civilian ship places (x, y on the scope); a few are picked and nudged at random.
const PROTECT_SLOTS: Array[Vector2] = [Vector2(-0.50, 0.10), Vector2(-0.24, 0.32), Vector2(0.02, 0.06),
	Vector2(0.30, 0.26), Vector2(0.52, 0.04), Vector2(-0.30, -0.22), Vector2(0.28, -0.20)]

func protect_active() -> bool:
	return wave_system_active() and wave_phase == "protect"

func next_round_name() -> String:
	match wave_next_phase:
		"protect": return "PROTECT THE CONVOY"
		"sweep": return "BONUS SWEEP"
	return wave_name(wave + 1)

## Attack Drones in the round for the sets completed so far and the difficulty.
func protect_drone_count() -> int:
	var cap := maxi(2, protect_drones_cap)
	var base := protect_first_drones + protect_drones_step * (maxi(1, sets_completed) - 1)
	# 1.2.9: a few extra Attack Drones from Extra Attack Drones From Set on (Normal; Hard if ticked).
	if protect_extra_drones > 0 and _protect_more_danger():
		base += protect_extra_drones
	match clampi(active_difficulty, 0, 2):
		0: return clampi(mini(cap, base) + easy_protect_drone_change, 2, cap)
		2: return clampi(base + hard_protect_drone_change, 2, cap)
	return clampi(base, 2, cap)

## 1.2.9: true when the "a bit more danger" values apply to this round.
func _protect_more_danger() -> bool:
	var level_ok := active_difficulty == 1 or (active_difficulty == 2 and protect_more_danger_on_hard)
	return level_ok and maxi(1, sets_completed) >= protect_extra_drones_from_set

func civilian_kill_seconds() -> float:
	var base: float = [easy_civilian_kill_seconds, normal_civilian_kill_seconds, hard_civilian_kill_seconds][clampi(active_difficulty, 0, 2)]
	# 1.2.3: shorter by Kill Time Step of the base per set after set 1, down to the floor.
	var later_sets := maxi(1, sets_completed) - 1
	var shortened := base * (1.0 - maxf(0.0, protect_kill_time_step) * later_sets)
	var seconds := maxf(1.0, maxf(minf(base, protect_kill_time_floor), shortened))
	if protect_later_kill_time_factor < 1.0 and _protect_more_danger():
		seconds = maxf(1.0, seconds * protect_later_kill_time_factor)
	return seconds

## 1.2.3: Interceptor hits a Attack Drone takes in Protect the fleet, growing by set.
func protect_drone_hits() -> int:
	var later_sets := maxi(1, sets_completed) - 1
	var cap := maxi(1, protect_drone_hits_cap)
	return clampi(protect_drone_interceptor_hits + maxi(0, protect_drone_hits_step) * later_sets, 1, maxi(cap, protect_drone_interceptor_hits))

func civilian_display_color(contact: Dictionary) -> Color:
	var left := clampf(float(contact.get("hull", 1.0)), 0.0, 1.0)
	var color := civilian_damaged_color.lerp(civilian_color, left)
	# 1.2.9: with the hull bar the ship keeps its colour and flashes white when hit.
	if civilian_hull_bar:
		var flash := 0.0
		if civilian_hit_flash_seconds > 0.0:
			flash = clampf(float(contact.get("flash_t", 0.0)) / civilian_hit_flash_seconds, 0.0, 1.0)
		color = civilian_color.lerp(Color.WHITE, 0.85 * flash)
	if left * 100.0 <= civilian_critical_percent:
		color.a = 1.0 if int(battle_time * civilian_blink_hz * 2.0) % 2 == 0 else 0.3
	return color

func civilians_left() -> int:
	var total := 0
	for contact in contacts:
		if contact.get("faction", "") == "civilian":
			total += 1
	return total

## Attack Drones still to come plus those on the scope.
func protect_drones_left() -> int:
	var total := maxi(0, protect_drones_total - protect_drones_spawned)
	for contact in contacts:
		if contact.get("phase", "") == "protect":
			total += 1
	return total

func protect_time_left() -> float:
	return maxf(0.0, protect_round_seconds - protect_elapsed)

## 1.0.7: Interceptors on the scope plus launches still allowed this round.
func protect_interceptors_left() -> int:
	return count_interceptors() + maxi(0, protect_interceptor_total() - protect_interceptors_launched)

func _reset_protect_state() -> void:
	protect_tender_waiting = false
	protect_auto_interceptor_launches = 0
	protect_civilians_total = 0
	protect_drones_total = 0
	protect_drones_spawned = 0
	protect_drones_destroyed = 0
	protect_drones_escaped = 0
	protect_interceptors_launched = 0
	protect_elapsed = 0.0
	protect_spawn_timer = 0.0
	protect_saved = 0
	protect_lost = 0
	protect_hull_kept = 0
	protect_end_reason = ""
	last_protect_bonus = 0
	rest_after_protect = false
	protect_civilian_kinds.clear()
	protect_interceptors_lost_to_fire = 0
	protect_challenges.clear()
	protect_wave_groups = 1
	protect_wave_gap = 0.0
	protect_group_index = 0
	protect_next_group_at = 0.0
	protect_short_interceptors = 0
	protect_help_timer = 0.0
	protect_breakoffs = 0
	protect_dogfight_hits = 0
	protect_dogfight_interceptors_lost = 0
	protect_helps = 0
	protect_repaired = 0.0
	protect_kill_points = 0
	protect_gunship_repaired = 0.0
	protect_boom_size = ""
	protect_breachers_total = 0
	protect_breachers_spawned = 0
	protect_breachers_destroyed = 0
	protect_breacher_times.clear()
	protect_breacher_latches = 0
	protect_bursts = 0
	protect_burst_losses = 0
	protect_evasions = 0
	tracers.clear()

func _shuffled(values: Array) -> Array:
	var items := values.duplicate()
	for index in range(items.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var held: Variant = items[index]
		items[index] = items[other]
		items[other] = held
	return items

func _start_protect() -> void:
	_reset_protect_state()
	wave_phase = "protect"
	protect_rounds += 1
	# Reset the scope: no Enemy Carriers, missiles or leftover fighters.
	if count_kind("stealth_interceptor") > 0:
		stealth_recovered += 1
		stealth_cooldown_remaining = maxf(1.0, stealth_rearm_seconds)
		stealth_event.emit("Stealth Interceptor recovered for Protect the fleet | rearming %ds" % int(stealth_cooldown_remaining))
	contacts.clear()
	pending.clear()
	impacts.clear()
	if prox_active:
		_end_battery_burst()
	klaxon_player.stop()
	klaxon_queue.clear()
	nuclear_player.stop()
	nuclear_beep_player.stop()
	nuclear_alert_queue.clear()
	nuclear_alert_contact_id = ""
	nuclear_alarm_remaining = 0.0
	interceptor_waits.clear()
	protect_drones_total = protect_drone_count()
	var low := clampi(protect_civilians_min, 1, CIVILIAN_KINDS.size())
	var high := clampi(protect_civilians_max, low, CIVILIAN_KINDS.size())
	protect_civilians_total = rng.randi_range(low, high)
	var kinds := _shuffled(CIVILIAN_KINDS)
	var slots := _shuffled(PROTECT_SLOTS)
	for index in range(protect_civilians_total):
		var slot: Vector2 = slots[index % slots.size()]
		var at := Vector3(slot.x + rng.randf_range(-0.04, 0.04), slot.y + rng.randf_range(-0.03, 0.03), 0.0)
		if not is_equal_approx(protect_fleet_spread, 1.0):
			var spread_at := ScopeShape.clamp_inside(Vector2(at.x, -at.y) * protect_fleet_spread, 0.14)
			at = Vector3(spread_at.x, -spread_at.y, 0.0)
		protect_civilian_kinds.append(kinds[index])
		contacts.append({"id": _new_id("C"), "kind": kinds[index], "faction": "civilian",
			"position": at, "start": at, "finish": at, "age": 0.0, "progress": 0.0,
			"phase": "", "velocity": Vector3.ZERO, "hull": 1.0})
	protect_spawn_timer = 0.0
	_roll_protect_challenges()
	_ensure_protect_audio()
	_ensure_convoy_audio()
	# 1.0.7: the new round behaviour draws from its own generator, seeded per round.
	protect_rng.seed = hash([rng.seed, protect_rounds, sets_completed, active_difficulty])
	if protect_breachers:
		var breacher_n := protect_breacher_count
		if clampi(active_difficulty, 0, 2) == 2 and sets_completed >= 2:
			breacher_n += hard_protect_breacher_extra
		protect_breachers_total = maxi(0, breacher_n)
		var lo := minf(protect_breacher_delay_min, protect_breacher_delay_max)
		var hi := maxf(protect_breacher_delay_min, protect_breacher_delay_max)
		for index in range(protect_breachers_total):
			protect_breacher_times.append(protect_rng.randf_range(lo, hi) + index * 8.0)
	_set_status("PROTECT THE CONVOY | %d SUPPORT SHIPS | %d ATTACK DRONES | INTERCEPTORS ONLY" % [protect_civilians_total, protect_drones_total], 5.0)
	battle_event.emit("protect the fleet start | %d civilian ships (%s) | %d Attack Drones | kill time %ds" % [
		protect_civilians_total, ", ".join(protect_civilian_kinds), protect_drones_total, int(civilian_kill_seconds())])

func _update_protect(delta: float) -> void:
	if protect_elapsed == 0.0 and protect_patrol_interceptors > 0:
		_spawn_protect_patrol()
	protect_elapsed += delta
	_update_civilian_evasion(delta)
	_update_protect_extras(delta)
	protect_spawn_timer -= delta
	if protect_wave_groups > 1:
		# 1.2.9 Waves: groups jump in every Wave Gap seconds, scope clear or not.
		if protect_drones_spawned < protect_drones_total and protect_elapsed >= protect_next_group_at and protect_spawn_timer <= 0.0:
			var group_end := _protect_group_end(protect_group_index)
			for slot in range(mini(maxi(1, protect_drone_group_size), group_end - protect_drones_spawned)):
				_spawn_protect_drone(slot == 0)
			if protect_drones_spawned >= group_end:
				protect_group_index += 1
				protect_next_group_at = protect_elapsed + protect_wave_gap
			protect_spawn_timer = maxf(0.2, protect_drone_group_gap)
	elif protect_drones_spawned < protect_drones_total and protect_spawn_timer <= 0.0:
		for slot in range(mini(maxi(1, protect_drone_group_size), protect_drones_total - protect_drones_spawned)):
			_spawn_protect_drone(slot == 0)
		protect_spawn_timer = maxf(0.2, protect_drone_group_gap)
	# 1.0.7: Breachers jump in on their time, or at once when every drone is gone.
	if protect_breachers_spawned < protect_breachers_total:
		var drones_done := protect_drones_spawned >= protect_drones_total and protect_drones_left() == 0
		if protect_elapsed >= protect_breacher_times[protect_breachers_spawned] or drones_done:
			_spawn_convoy_breacher()
	_update_convoy_breachers(delta)
	_update_tracers(delta)
	if civilians_left() == 0:
		_end_protect("SUPPORT FLEET LOST")
	elif protect_drones_spawned >= protect_drones_total and protect_drones_left() == 0 and protect_breachers_spawned >= protect_breachers_total and convoy_breachers_left() == 0:
		_end_protect("ATTACK DRONES DESTROYED")
	elif protect_interceptors_lost_end and protect_interceptors_launched > 0 and protect_interceptors_left() == 0:
		_end_protect("INTERCEPTORS LOST")
	elif protect_timer_end and protect_elapsed >= protect_round_seconds:
		_end_protect("TIME")
	elif not protect_timer_end and protect_elapsed >= protect_safety_seconds:
		_end_protect("TIME")

func _spawn_protect_drone(announce: bool) -> void:
	# From the upper edge and the sides of the scope.
	var angle := rng.randf_range(-0.25, PI + 0.25)
	if protect_smart_drones:
		angle = _protect_spread_angle()
	var start := Vector3(cos(angle) * 0.97, sin(angle) * 0.97, 0.1)
	var id := _new_id("H")
	contacts.append({
		"id": id, "kind": "drone", "faction": "hostile", "position": start,
		"start": start, "finish": start, "age": 0.0, "progress": 0.0,
		"origin_id": "", "origin_position": start, "target_position": start,
		"defense_checked": false, "phase": "protect", "patrol_angle": rng.randf_range(0.0, TAU),
		"approach_point": start, "velocity": Vector3.ZERO, "health": 1,
		"attack_cooldown": 0.0, "next_battery_shot": 0.0, "civ_target": "",
		"interceptor_hits": protect_drone_hits(), "max_interceptor_hits": protect_drone_hits(), "return_fire_done": false,
		"hold": protect_jump_in_hold, "dog_target": "", "dog_decided": false, "presses": false, "shot_timer": 0.0})
	protect_drones_spawned += 1
	if announce:
		_announce_contact(id, "drone", "hostile")

## 1.2.3: one roll per Attack Drone, against the first Interceptor that engages it. True when the Interceptor is lost.
func _protect_return_fire(interceptor: Dictionary, drone: Dictionary) -> bool:
	if drone.get("return_fire_done", false):
		return false
	drone.return_fire_done = true
	if rng.randf() >= clampf(protect_return_fire_chance, 0.0, 1.0):
		return false
	protect_interceptors_lost_to_fire += 1
	fighter_losses_by["drone"] += 1
	battle_event.emit("interceptor lost to Attack Drone return fire in Protect the fleet")
	_lose_fighter(interceptor, "INTERCEPTOR LOST TO ATTACK DRONE RETURN FIRE")
	return true

## The civilian ship fewest Attack Drones are attacking, nearest first.
func _protect_pick_civilian(drone: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for ship in contacts:
		if ship.get("faction", "") != "civilian":
			continue
		var claims := 0
		for other in contacts:
			if other.id != drone.id and other.get("civ_target", "") == ship.id:
				claims += 1
		var rank: float = drone.position.distance_to(ship.position) + 0.6 * claims
		# 1.2.9 Gang up: prefer the ship already under attack and the most damaged one.
		if protect_challenges.has("gang"):
			rank = drone.position.distance_to(ship.position) - protect_gang_claim_pull * claims - protect_gang_damage_pull * (1.0 - float(ship.get("hull", 1.0)))
		if rank < best_score:
			best_score = rank
			best = ship
	return best

func civilian_size_class(kind: String) -> String:
	if kind == "civilian_c":
		return "large"
	if kind in ["civilian_a", "civilian_d"]:
		return "medium"
	return "small"

func civilian_damage_factor(ship: Dictionary) -> float:
	var f := 1.0
	var size_class := civilian_size_class(ship.kind)
	if civilian_size_toughness:
		f /= {"large": civilian_large_toughness, "medium": civilian_medium_toughness, "small": civilian_small_toughness}[size_class]
	if civilian_evasion and ship.get("evading", false):
		f *= {"large": 1.0, "medium": civilian_medium_evade_damage, "small": civilian_small_evade_damage}[size_class]
	return f

func _update_civilian_evasion(delta: float) -> void:
	if not civilian_evasion:
		return
	for ship in contacts:
		if ship.get("faction", "") != "civilian":
			continue
		var size_class := civilian_size_class(ship.kind)
		var speed: float = {"large": civilian_large_evade_speed, "medium": civilian_medium_evade_speed, "small": civilian_small_evade_speed}[size_class]
		var threat := Vector3.ZERO
		var near := 0
		for drone in contacts:
			if drone.get("phase", "") == "protect" and drone.kind == "drone" and drone.position.distance_to(ship.position) < 0.2:
				threat += drone.position
				near += 1
		ship.evading = near > 0 and speed > 0.0
		if not ship.evading:
			continue
		ship.evade_t = float(ship.get("evade_t", 0.0)) + delta
		var away: Vector3 = ship.position - threat / float(near)
		away.z = 0.0
		away = away.normalized()
		var home: Vector3 = own_ship_position - ship.position
		home.z = 0.0
		home = home.normalized()
		var dir: Vector3 = (away + home * civilian_evade_bias_home).normalized()
		# Jink side to side.
		var side := Vector3(-dir.y, dir.x, 0.0) * sin(ship.evade_t * 2.2) * 0.8
		ship.position += (dir + side).normalized() * speed * delta
		ship.position.y = maxf(ship.position.y, civilian_evade_floor_y)
		var point := Vector2(ship.position.x, -ship.position.y)
		var inside := ScopeShape.clamp_inside(point, 0.12)
		if point.distance_to(inside) > 0.000001:
			evade_corrections += 1
			ship.position = Vector3(inside.x, -inside.y, ship.position.z)
		evade_min_y = minf(evade_min_y, ship.position.y)
		if not ScopeShape.contains(Vector2(ship.position.x, -ship.position.y), 0.0):
			evade_outside += 1

func _spawn_protect_patrol() -> void:
	var centre := Vector3.ZERO
	var n := 0
	for ship in contacts:
		if ship.get("faction", "") == "civilian":
			centre += ship.position
			n += 1
	if n > 0:
		centre /= n
	for i in range(protect_patrol_interceptors):
		var id := _spawn_interceptor("interceptor", false)
		if id.is_empty():
			return
		var interceptor := find_contact(id)
		interceptor.position = centre + Vector3(-0.12 if i % 2 == 0 else 0.12, -0.1, 0.0)
		interceptor.phase = "intercept"

func _update_protect_drone(drone: Dictionary, delta: float) -> void:
	# 1.2.5: hold at the jump-in point (fading in) before attacking.
	if float(drone.get("hold", 0.0)) > 0.0:
		drone.hold = float(drone.hold) - delta
		if drone.hold > 0.0:
			return
	# 1.0.7 Smart drones replace the 1.2.9 break-off rules.
	if protect_smart_drones:
		_update_smart_drone(drone, delta)
		return
	# 1.2.9 Dogfights: a Attack Drone fighting a Interceptor leaves the ships alone.
	if protect_dogfights and _protect_drone_dogfight(drone, delta):
		return
	var target := find_contact(drone.get("civ_target", ""))
	if target.is_empty() or target.get("faction", "") != "civilian":
		target = _protect_pick_civilian(drone)
		drone.civ_target = "" if target.is_empty() else target.id
		if target.is_empty():
			return
	var gap: float = drone.position.distance_to(target.position)
	drone.patrol_angle += delta * 1.2
	var aim: Vector3 = target.position
	if gap < 0.15:
		# Circle the ship while attacking it.
		aim += Vector3(cos(drone.patrol_angle), sin(drone.patrol_angle), 0.0) * 0.05
	_steer(drone, aim, protect_drone_speed, delta)
	if gap <= protect_attack_range:
		drone.attack_cooldown = maxf(0.0, drone.get("attack_cooldown", 0.0) - delta)
		if drone.attack_cooldown <= 0.0:
			drone.attack_cooldown = 0.6
			impacts.append({"position": target.position, "age": 0.0})
			# 1.2.9: a brief white flash on each hit, and a warning on the first attack.
			target.flash_t = civilian_hit_flash_seconds
			if not target.get("attack_warned", false):
				target.attack_warned = true
				_play_protect_sound("ship_attacked")
		if protect_damage_stack_cap > 0:
			if float(target.get("stack_key", -1.0)) != protect_elapsed:
				target.stack_key = protect_elapsed
				target.stack_n = 0
			target.stack_n = int(target.stack_n) + 1
			if target.stack_n > protect_damage_stack_cap:
				return
		_damage_civilian(target, delta / civilian_kill_seconds() * civilian_damage_factor(target))

func _damage_civilian(ship: Dictionary, amount: float) -> void:
	ship.hull = maxf(0.0, float(ship.get("hull", 1.0)) - amount)
	if ship.hull > 0.0:
		# 1.2.9: one warning when the ship first reaches Critical Percent.
		if ship.hull * 100.0 <= civilian_critical_percent and not ship.get("critical_warned", false):
			ship.critical_warned = true
			_play_protect_sound("ship_critical")
		return
	protect_lost += 1
	protect_boom_size = civilian_size_class(ship.kind)
	_explode(ship.position, "own_craft")
	protect_boom_size = ""
	_remove_contact(ship.id)
	_set_status("SUPPORT SHIP LOST | %d OF %d LEFT" % [civilians_left(), protect_civilians_total], 3.0)
	battle_event.emit("civilian ship lost (%s) | %d of %d left" % [ship.kind, civilians_left(), protect_civilians_total])

func _end_protect(reason: String, jumped: bool = false) -> void:
	if wave_phase != "protect":
		return
	protect_end_reason = reason
	# 1.0.7: no Interceptors left = no defense; the whole convoy counts as lost, no bonus.
	var total_loss := reason == "INTERCEPTORS LOST"
	var hull_sum := 0.0
	var survivors := 0
	for contact in contacts:
		if contact.get("faction", "") == "civilian":
			survivors += 1
			hull_sum += clampf(float(contact.get("hull", 1.0)), 0.0, 1.0)
	protect_saved = 0 if jumped or total_loss else survivors
	protect_lost = protect_civilians_total - protect_saved
	protect_hull_kept = roundi(100.0 * hull_sum / survivors) if survivors > 0 and not jumped and not total_loss else 0
	var full := not jumped and protect_saved > 0 and protect_saved == protect_civilians_total
	var base := 0.0 if jumped or total_loss else protect_ship_points * hull_sum + (protect_full_fleet_points if full else 0)
	last_protect_bonus = points_for(roundi(base))
	_add_points(last_protect_bonus)
	wave_bonus_points += last_protect_bonus
	if full:
		protect_full_fleets += 1
	# Attack Drones still here jump away; civilian ships leave; Interceptors head home.
	for index in range(contacts.size() - 1, -1, -1):
		var contact: Dictionary = contacts[index]
		if contact.get("phase", "") == "protect":
			protect_drones_escaped += 1
			contacts.remove_at(index)
		elif contact.get("faction", "") == "civilian":
			if total_loss:
				_explode(contact.position, "own_craft")
			contacts.remove_at(index)
		elif contact.get("phase", "") == "protect_repair":
			if protect_tender_lands and not jumped:
				# 1.0.7.2: it flies home and lands on your ship.
				contact.phase = "tender_return"
				contact.target_id = ""
			else:
				# 1.2.9: the repair Gunship leaves with the civilian ships.
				contacts.remove_at(index)
		elif contact.get("phase", "") == "protect_breacher":
			# 1.0.7: a Breacher still here jumps away.
			contacts.remove_at(index)
		elif Icons.is_interceptor(contact.kind):
			contact.phase = "return"
			contact.target_id = ""
	tracers.clear()
	if is_instance_valid(protect_drain_player):
		protect_drain_player.stop()
	wave_next_phase = "assault"
	rest_after_protect = true
	upcoming_trait = _draw_trait(wave + 1)
	_begin_rest()
	# 1.2.7: the result stays up longer after this round, and a sound marks the outcome.
	wave_rest_remaining += maxf(0.0, protect_result_extra_seconds)
	protect_result_started = battle_time
	_play_protect_result_sound()
	if total_loss:
		_set_status("ALL INTERCEPTORS LOST | SUPPORT FLEET LOST | NO CONVOY BONUS", maxf(2.0, wave_rest_remaining - inbound_seconds))
	else:
		_set_status("PROTECT THE CONVOY COMPLETE | %d OF %d SAVED | +%d" % [protect_saved, protect_civilians_total, last_protect_bonus], maxf(2.0, wave_rest_remaining - inbound_seconds))
	battle_event.emit("protect the fleet complete (%s) | saved %d of %d | hull %d%% | Attack Drones destroyed %d of %d, jumped away %d | Interceptors launched %d | bonus %d" % [
		reason, protect_saved, protect_civilians_total, protect_hull_kept, protect_drones_destroyed, protect_drones_spawned,
		protect_drones_escaped, protect_interceptors_launched, last_protect_bonus])
	# 0.1.2: a missile bonus pick held during the round is offered now.
	_offer_waiting_missile_bonus()

# ------------------------------------------------------------------
# 1.2.9 Protect the fleet: challenge mix, dogfights, smarter ships, repair Gunship,
# round sounds, damaged-ship bars and label spacing. Used in the round only.
# ------------------------------------------------------------------

## Challenges this round: the set number, Easy one fewer, Hard one more (0 to Challenge Max).
func protect_challenge_count() -> int:
	var count := maxi(1, sets_completed)
	match clampi(active_difficulty, 0, 2):
		0: count += easy_protect_challenge_change
		2: count += hard_protect_challenge_change
	return clampi(count, 0, clampi(protect_challenge_max, 0, 3))

## Plain names of this round's challenges, for the log and the checks.
func protect_challenge_names() -> String:
	if protect_challenges.is_empty():
		return "none"
	var names: Array[String] = []
	for item in protect_challenges:
		names.append({"waves": "Attack Drones in %d waves %ds apart" % [protect_wave_groups, roundi(protect_wave_gap)],
			"fewer": "%d fewer Interceptors" % protect_short_interceptors, "gang": "Attack Drones gang up"}[item])
	return ", ".join(names)

func _roll_protect_challenges() -> void:
	if protect_challenge_mix:
		var picks := _shuffled(["waves", "fewer", "gang"])
		for index in range(protect_challenge_count()):
			protect_challenges.append(picks[index])
		if protect_challenges.has("waves"):
			var low := clampi(mini(protect_wave_groups_min, protect_wave_groups_max), 2, 4)
			var high := clampi(maxi(protect_wave_groups_min, protect_wave_groups_max), low, 4)
			protect_wave_groups = clampi(rng.randi_range(low, high), 1, maxi(1, protect_drones_total))
			protect_wave_gap = rng.randf_range(minf(protect_wave_gap_min, protect_wave_gap_max), maxf(protect_wave_gap_min, protect_wave_gap_max))
		if protect_challenges.has("fewer"):
			var fewest := mini(protect_fewer_interceptors_min, protect_fewer_interceptors_max)
			var most := maxi(protect_fewer_interceptors_min, protect_fewer_interceptors_max)
			protect_short_interceptors = mini(rng.randi_range(fewest, most), floori(protect_drones_total / 3.0))
	var gunship := false
	if protect_repair_tender and protect_challenges.size() >= protect_gunship_min_challenges \
			and (maxi(1, sets_completed) >= protect_gunship_from_set or active_difficulty == 2):
		var chance := protect_hard_gunship_chance if active_difficulty == 2 else protect_gunship_chance
		gunship = rng.randf() < clampf(chance, 0.0, 1.0)
	if gunship and protect_tender_launch_when_hit:
		protect_tender_waiting = true
	elif gunship:
		_spawn_repair_tender()
	battle_event.emit("protect the fleet challenges | %s%s" % [protect_challenge_names(), " | repair Gunship" if gunship else ""])

## Last Attack Drone number (1-based count) in wave group index.
func _protect_group_end(index: int) -> int:
	if protect_wave_groups <= 1:
		return protect_drones_total
	return mini(protect_drones_total, ceili(float(protect_drones_total) * float(index + 1) / float(protect_wave_groups)))

func _spawn_repair_tender(from_ship: bool = false) -> void:
	var at := own_ship_position + Vector3(0.0, 0.1, 0.0)
	if from_ship:
		# 1.0.7.2: launches from your ship like a Gunship.
		at = launch_origin(0.0)
	elif protect_tender_jump_in:
		# 1.0.7 option: jumps in beside the convoy, at the middle of the ships.
		var centre := Vector3.ZERO
		var n := 0
		for ship in contacts:
			if ship.get("faction", "") == "civilian":
				centre += ship.position
				n += 1
		if n > 0:
			at = centre / n
	contacts.append({"id": _new_id("R"), "kind": "gunship", "faction": "friendly", "position": at,
		"start": at, "finish": at, "age": 0.0, "progress": 0.0, "phase": "protect_repair",
		"velocity": Vector3.ZERO, "lane": 0.0, "fire_timer": 0.0, "target_id": "",
		"health": 1, "max_health": 1, "patrol_angle": 0.0, "hull": 1.0})
	protect_gunship_rounds += 1
	if from_ship:
		protect_tender_launches += 1
	_set_status("REPAIR TENDER LAUNCHED | FIXING DAMAGED SHIPS", 3.0)
	battle_event.emit("repair tender launched%s" % (" from your ship" if from_ship else ""))

## 1.0.7.2: the repair tender, during the round or flying home after it.
func is_tender(contact: Dictionary) -> bool:
	return contact.get("phase", "") in ["protect_repair", "tender_return"]

## 1.0.7.2: where an idle tender waits: by the support ships, leaning toward the drones.
func _tender_wait_point(gunship: Dictionary) -> Vector3:
	var ships := Vector3.ZERO
	var n := 0
	var drones := Vector3.ZERO
	var d := 0
	for contact in contacts:
		if contact.get("faction", "") == "civilian":
			ships += contact.position
			n += 1
		elif contact.get("phase", "") == "protect" and contact.kind == "drone":
			drones += contact.position
			d += 1
	if n == 0:
		return own_ship_position + Vector3(0.0, 0.12, 0.0)
	var at := ships / n
	if d > 0:
		at = at.lerp(drones / d, 0.25)
	var turn := float(gunship.get("age", 0.0)) * 0.5
	at += Vector3(cos(turn), sin(turn), 0.0) * 0.05
	at.z = 0.03
	return at

## 1.0.7.2: Attack Drones attacking close to the tender wear down its hull like the
## biggest support ship's. True when it is destroyed.
func _damage_tender(gunship: Dictionary, delta: float) -> bool:
	if not protect_tender_hull:
		return false
	var hits := 0
	for drone in contacts:
		if drone.get("phase", "") == "protect" and drone.kind == "drone" and str(drone.get("dog_target", "")) == "" \
				and drone.position.distance_to(gunship.position) <= protect_attack_range:
			hits += 1
	if hits == 0:
		return false
	var rate := delta / civilian_kill_seconds() * civilian_damage_factor({"kind": "civilian_c"})
	gunship.hull = float(gunship.get("hull", 1.0)) - rate * hits
	gunship.flash_t = 0.25
	if float(gunship.hull) > 0.0:
		return false
	_explode(gunship.position, "own_craft")
	contacts.erase(gunship)
	protect_tenders_lost += 1
	_set_status("REPAIR TENDER LOST | NO MORE REPAIRS THIS ROUND", 3.0)
	battle_event.emit("repair tender destroyed")
	return true

## 1.0.7.2: a tender that survived the round flies home and lands.
func _update_tender_return(delta: float) -> void:
	for gunship in contacts.duplicate():
		if gunship.get("phase", "") != "tender_return":
			continue
		var home := launch_origin(0.0)
		_steer(gunship, home, protect_tender_speed, delta)
		if gunship.position.distance_to(home) <= 0.03:
			contacts.erase(gunship)
			protect_tenders_landed += 1
			_set_status("REPAIR TENDER RECOVERED", 3.0)

## Gunships the player launched (the Protect the fleet repair Gunship is not one).
func player_gunship_count() -> int:
	var total := 0
	for contact in contacts:
		if contact.kind == "gunship" and not is_tender(contact):
			total += 1
	return total

func repair_tender() -> Dictionary:
	for contact in contacts:
		if contact.get("phase", "") == "protect_repair":
			return contact
	return {}

## A Attack Drone is attacking this ship right now (not busy in a dogfight).
func _protect_ship_attacked(ship: Dictionary) -> bool:
	for drone in contacts:
		if drone.get("phase", "") == "protect" and drone.kind == "drone" and drone.get("civ_target", "") == ship.id \
				and drone.get("dog_target", "") == "" and drone.position.distance_to(ship.position) <= protect_attack_range + 0.03:
			return true
	return false

## Hit flashes, self-repair and the repair Gunship, every frame of the round.
func _update_protect_extras(delta: float) -> void:
	var worst: Dictionary = {}
	for ship in contacts:
		if ship.get("faction", "") != "civilian":
			continue
		ship.flash_t = maxf(0.0, float(ship.get("flash_t", 0.0)) - delta)
		if civilian_self_repair:
			if _protect_ship_attacked(ship):
				ship.calm = 0.0
			else:
				ship.calm = float(ship.get("calm", 0.0)) + delta
				if ship.calm >= civilian_repair_delay and float(ship.hull) < civilian_repair_cap:
					var gain := minf(civilian_repair_rate * delta, civilian_repair_cap - float(ship.hull))
					ship.hull = float(ship.hull) + gain
					protect_repaired += gain
		if float(ship.hull) < 0.98 and not _patch_used_up(ship) and (worst.is_empty() or float(ship.hull) < float(worst.hull)):
			worst = ship
	if protect_tender_waiting:
		for ship in contacts:
			if ship.get("faction", "") == "civilian" and float(ship.hull) < 1.0 - protect_tender_launch_damage - 0.0001:
				protect_tender_waiting = false
				_spawn_repair_tender(true)
				break
	var gunship := repair_tender()
	if gunship.is_empty():
		return
	gunship.age = float(gunship.get("age", 0.0)) + delta
	gunship.flash_t = maxf(0.0, float(gunship.get("flash_t", 0.0)) - delta)
	if _damage_tender(gunship, delta):
		return
	var target := find_contact(gunship.get("target_id", ""))
	var fly_speed := protect_drone_speed * 0.7
	if protect_tender_smart:
		fly_speed = protect_tender_speed
		gunship.retarget_t = float(gunship.get("retarget_t", 0.0)) - delta
		var invalid: bool = target.is_empty() or target.get("faction", "") != "civilian" or float(target.hull) >= 0.98 or _patch_used_up(target)
		if invalid or gunship.retarget_t <= 0.0:
			gunship.retarget_t = protect_tender_retarget_seconds
			var pick := _tender_pick(gunship, {} if invalid else target)
			if not pick.is_empty() and str(pick.get("id", "")) != str(gunship.get("target_id", "")):
				protect_tender_switches += 0 if invalid else 1
			target = pick
			gunship.target_id = "" if target.is_empty() else target.id
	elif target.is_empty() or target.get("faction", "") != "civilian" or float(target.hull) >= 0.98 or _patch_used_up(target):
		target = worst
		gunship.target_id = "" if target.is_empty() else target.id
	if target.is_empty():
		if protect_tender_stay_near:
			_steer(gunship, _tender_wait_point(gunship), minf(fly_speed, protect_drone_speed * 0.8), delta)
		else:
			_steer(gunship, own_ship_position + Vector3(0.0, 0.12, 0.0), protect_drone_speed * 0.6, delta)
		return
	_steer(gunship, target.position + Vector3(0.04, 0.03, 0.0), fly_speed, delta)
	if gunship.position.distance_to(target.position) < 0.08:
		var fix := minf(protect_gunship_repair_rate * delta, 1.0 - float(target.hull))
		if _gunship_patch() > 0.0:
			fix = minf(fix, maxf(0.0, _gunship_patch() - float(target.get("patched", 0.0))))
			target.patched = float(target.get("patched", 0.0)) + fix
		target.hull = float(target.hull) + fix
		protect_gunship_repaired += fix

## The nearest Interceptor within Engage Radius that is chasing this Attack Drone.
func _protect_chaser(drone: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var nearest := protect_engage_radius
	for interceptor in contacts:
		if Icons.is_interceptor(interceptor.kind) and interceptor.get("target_id", "") == drone.id:
			var gap: float = interceptor.position.distance_to(drone.position)
			if gap < nearest:
				nearest = gap
				best = interceptor
	return best

## True when a is behind b: within Tail Range and inside b's tail cone.
func _protect_on_tail(a: Dictionary, b: Dictionary) -> bool:
	var gap: Vector3 = b.position - a.position
	if gap.length() > protect_tail_range:
		return false
	var heading: Vector3 = b.get("velocity", Vector3.ZERO)
	if heading.length() < 0.0001:
		return true
	return heading.normalized().dot(gap.normalized()) >= protect_tail_cos

## A Interceptor chasing a round Attack Drone: helps a wingman, weaves when a Attack Drone is on its
## tail, and scores hits only from behind.
func _protect_interceptor_dogfight(interceptor: Dictionary, target: Dictionary, delta: float, removed: Array[String]) -> void:
	interceptor.help_t = float(interceptor.get("help_t", 0.0)) - delta
	if interceptor.help_t <= 0.0:
		interceptor.help_t = 1.0
		for drone in contacts:
			if drone.get("phase", "") != "protect" or drone.kind != "drone" or drone.id == target.id or drone.id in removed:
				continue
			var prey := find_contact(drone.get("dog_target", ""))
			if prey.is_empty() or prey.id == interceptor.id:
				continue
			if prey.position.distance_to(interceptor.position) <= protect_help_range and rng.randf() < protect_help_chance:
				interceptor.target_id = drone.id
				target = drone
				protect_helps += 1
				break
	var threatened := false
	for drone in contacts:
		if drone.get("dog_target", "") == interceptor.id and _protect_on_tail(drone, interceptor):
			threatened = true
	interceptor.patrol_angle = float(interceptor.get("patrol_angle", 0.0)) + delta * 3.0
	var heading: Vector3 = target.get("velocity", Vector3.ZERO)
	var aim: Vector3 = target.position - (heading.normalized() * 0.03 if heading.length() > 0.0001 else Vector3.ZERO)
	if threatened:
		aim += Vector3(-heading.y, heading.x, 0.0).normalized() * sin(interceptor.patrol_angle) * 0.05
	_steer(interceptor, aim, interceptor_speed * fighter_speed_factor(), delta)
	if interceptor.drone_fire_remaining > 0.0 or not _protect_on_tail(interceptor, target):
		return
	interceptor.drone_fire_remaining = maxf(0.1, drone_interceptor_hit_interval) * fire_interval_factor()
	protect_dogfight_hits += 1
	_protect_tracer_burst(interceptor.position, target.position, false)
	target.interceptor_hits = int(target.get("interceptor_hits", 1)) - 1
	impacts.append({"position": target.position, "age": 0.0})
	if target.interceptor_hits > 0:
		_play_protect_sound("interceptor_hit")
		return
	removed.append(target.id)
	_award_destroyed(target)
	intercepted_count += 1
	hostile_intercepted.emit(interceptor.id, target.id)
	interceptor.target_id = ""

## A round Attack Drone: breaks off (or not) when a Interceptor engages it, helps a nearby Attack Drone,
## and fights from behind. True while it is dogfighting (not attacking a ship).
func _protect_drone_dogfight(drone: Dictionary, delta: float) -> bool:
	var foe := find_contact(drone.get("dog_target", ""))
	if foe.is_empty() or not Icons.is_interceptor(foe.kind) or foe.get("phase", "") == "return":
		drone.dog_target = ""
		var chaser := _protect_chaser(drone)
		if chaser.is_empty():
			drone.help_t = float(drone.get("help_t", 0.0)) - delta
			if drone.help_t <= 0.0:
				drone.help_t = 1.0
				for other in contacts:
					if other.id == drone.id or other.get("phase", "") != "protect" or other.kind != "drone":
						continue
					if other.position.distance_to(drone.position) > protect_help_range:
						continue
					var other_chaser := _protect_chaser(other)
					if not other_chaser.is_empty() and rng.randf() < protect_help_chance:
						drone.dog_target = other_chaser.id
						protect_helps += 1
						break
		else:
			if not drone.get("dog_decided", false):
				drone.dog_decided = true
				drone.presses = rng.randf() >= clampf(protect_breakoff_chance, 0.0, 1.0)
			if drone.presses:
				return false
			drone.dog_target = chaser.id
			protect_breakoffs += 1
		foe = find_contact(drone.get("dog_target", ""))
		if foe.is_empty():
			return false
	# Chase the Interceptor's tail, weaving.
	drone.patrol_angle += delta * 2.4
	var heading: Vector3 = foe.get("velocity", Vector3.ZERO)
	var behind: Vector3 = foe.position - (heading.normalized() * 0.04 if heading.length() > 0.0001 else Vector3.ZERO)
	var weave := Vector3(cos(drone.patrol_angle), sin(drone.patrol_angle), 0.0) * 0.035
	_steer(drone, behind + weave, protect_drone_speed * 1.05, delta)
	drone.shot_timer = float(drone.get("shot_timer", 0.0)) - delta
	if drone.shot_timer <= 0.0 and _protect_on_tail(drone, foe):
		drone.shot_timer = maxf(0.1, protect_drone_shot_gap)
		impacts.append({"position": foe.position, "age": 0.0})
		if rng.randf() < clampf(protect_interceptor_loss_chance, 0.0, 1.0):
			protect_dogfight_interceptors_lost += 1
			protect_interceptors_lost_to_fire += 1
			fighter_losses_by["drone"] += 1
			battle_event.emit("interceptor lost in a dogfight in Protect the fleet")
			_lose_fighter(foe, "INTERCEPTOR LOST IN DOGFIGHT")
			drone.dog_target = ""
	return true

## Round sounds (made once, on the first round).
func _ensure_protect_audio() -> void:
	if is_instance_valid(protect_tick_player):
		return
	protect_tick_player = _boom_player("ProtectHitTickAudio", ProtectAudio.make_interceptor_hit_tick(), protect_interceptor_hit_volume_db)
	protect_tick_player.max_polyphony = 3
	protect_attacked_player = _boom_player("ProtectShipAttackedAudio", ProtectAudio.make_ship_attacked(), protect_ship_attacked_volume_db)
	protect_critical_player = _boom_player("ProtectShipCriticalAudio", ProtectAudio.make_ship_critical(), protect_ship_critical_volume_db)
	protect_medium_boom_player = _boom_player("ProtectMediumBoomAudio", ProtectAudio.make_medium_ship_boom(), protect_medium_ship_lost_volume_db)

func _play_protect_sound(which: String) -> void:
	if not protect_round_sounds or not protect_active():
		return
	if which in ["rapid_fire", "breacher_latch"]:
		_play_convoy_sound(which)
		return
	var player: AudioStreamPlayer = {"interceptor_hit": protect_tick_player, "ship_attacked": protect_attacked_player,
		"ship_critical": protect_critical_player}.get(which, null)
	if not is_instance_valid(player):
		return
	player.volume_db = {"interceptor_hit": protect_interceptor_hit_volume_db, "ship_attacked": protect_ship_attacked_volume_db,
		"ship_critical": protect_ship_critical_volume_db}[which]
	player.play()
	protect_sound_counts[which] = int(protect_sound_counts.get(which, 0)) + 1

## Explosion sound in the round: Attack Drone and Interceptor booms at their own volume, civilian
## ships by size. False outside the round (the normal boom plays).
func _play_protect_boom(kind: String) -> bool:
	if not protect_round_sounds or not protect_active():
		return false
	var which := "drone_kill" if kind == "craft" else "interceptor_lost"
	var player := craft_boom_player
	var volume := protect_drone_kill_volume_db if kind == "craft" else protect_interceptor_lost_volume_db
	match protect_boom_size:
		"small":
			which = "small_ship_lost"
			player = heavy_boom_player
			volume = protect_small_ship_lost_volume_db
		"medium":
			which = "medium_ship_lost"
			player = protect_medium_boom_player
			volume = protect_medium_ship_lost_volume_db
		"large":
			which = "large_ship_lost"
			player = capital_boom_player
			volume = protect_large_ship_lost_volume_db
	_play_boom(player, which, volume)
	protect_sound_counts[which] = int(protect_sound_counts.get(which, 0)) + 1
	return true

## Hull bar under a civilian ship's label (Civilian Color; the filled part is the hull left).
func _draw_civilian_hull_bar(ship: Dictionary, marker_scale: float, label_point: Vector2, label_size: Vector2) -> void:
	var bar := _civilian_hull_bar_rect(marker_scale, label_point, label_size)
	var hull := clampf(float(ship.get("hull", 1.0)), 0.0, 1.0)
	draw_rect(bar, Color(0.0, 0.0, 0.0, 0.85), true)
	draw_rect(bar, Color(civilian_color, 0.30), true)
	draw_rect(Rect2(bar.position - Vector2(1, 1), bar.size + Vector2(2, 2)), Color(civilian_color, 0.55), false, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * hull, bar.size.y)), civilian_color.lerp(Color.WHITE, 0.15), true)

func _civilian_hull_bar_rect(marker_scale: float, label_point: Vector2, label_size: Vector2) -> Rect2:
	var width := civilian_hull_bar_width * marker_scale
	return Rect2(label_point + Vector2((label_size.x - width) * 0.5, 5.0 * marker_scale), Vector2(width, maxf(2.0, 3.0 * marker_scale)))

## At the start of each draw in the round: civilian labels and hull bars take their
## places first, so fighter labels move around them.
func _protect_reserve_labels(font: Font) -> void:
	_protect_label_rects.clear()
	if not protect_label_declutter or not protect_active() or not show_labels:
		return
	for ship in contacts:
		if ship.get("faction", "") != "civilian":
			continue
		var projected := projection(ship.position)
		var text := contact_tag(ship)
		var label_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size)
		var marker_scale: float = projected.scale * size_for_kind(ship.kind)
		var label_point: Vector2 = projected.point + Vector2(-label_size.x * 0.5, 22.0 * marker_scale)
		var rect := _protect_label_rect(label_point, label_size)
		if civilian_hull_bar:
			rect = rect.merge(_civilian_hull_bar_rect(marker_scale, label_point, label_size).grow(1.0))
		_protect_label_rects.append(rect)

func _protect_label_rect(label_point: Vector2, label_size: Vector2) -> Rect2:
	return Rect2(label_point + Vector2(-1.0, -label_size.y * 0.78), label_size + Vector2(2.0, 1.0))

## Where a fighter label goes: as is, or one or two lines lower, or left out
## (Vector2.INF) when every place overlaps a label already drawn.
func _protect_place_label(label_point: Vector2, label_size: Vector2) -> Vector2:
	for step in range(3):
		var at := label_point + Vector2(0.0, label_size.y * 0.9 * step)
		var rect := _protect_label_rect(at, label_size)
		var clear := true
		for other in _protect_label_rects:
			if rect.intersects(other):
				clear = false
				break
		if clear:
			_protect_label_rects.append(rect)
			return at
	return Vector2.INF

## 1.2.7: "saved" (every ship), "partial" (some lost) or "lost" (none saved).
func protect_outcome() -> String:
	if protect_saved <= 0:
		return "lost"
	return "saved" if protect_saved >= protect_civilians_total else "partial"

func protect_result_title() -> String:
	if protect_end_reason == "INTERCEPTORS LOST":
		# 1.0.7.2: say why the convoy was lost.
		return "ALL INTERCEPTORS LOST"
	match protect_outcome():
		"saved": return "SUPPORT FLEET SAVED"
		"lost": return "SUPPORT FLEET LOST"
	return "%d OF %d SHIPS SAVED" % [protect_saved, protect_civilians_total]

## True while the bonus and border are in the bright half of the flash (always after the flash time).
func protect_result_flash_on() -> bool:
	var elapsed := battle_time - protect_result_started
	if elapsed < 0.0 or elapsed >= protect_result_flash_seconds:
		return true
	return int(elapsed * 4.0) % 2 == 0

func _play_protect_result_sound() -> void:
	var outcome := protect_outcome()
	last_protect_result_sound = outcome
	if not protect_result_sounds:
		return
	var player: AudioStreamPlayer = {"saved": fleet_saved_player, "partial": fleet_partial_player, "lost": fleet_lost_player}[outcome]
	if not is_instance_valid(player):
		return
	player.volume_db = {"saved": fleet_saved_volume_db, "partial": fleet_partial_volume_db, "lost": fleet_lost_volume_db}[outcome]
	player.play()
	protect_result_sound_count += 1

func _play_wave_cue(player: AudioStreamPlayer) -> void:
	if not wave_cues_enabled or not is_instance_valid(player):
		return
	player.volume_db = action_stations_volume_db if player == action_stations_player else all_clear_volume_db
	player.play()

## Lines for the right panel under WAVE n.
func wave_phase_line() -> String:
	if not wave_system_active():
		return ""
	match wave_phase:
		"rest":
			return "SET %d  |  REST %ds" % [wave_set_number(), ceili(wave_rest_remaining)]
		"sweep":
			return "BONUS SWEEP  |  %d LEFT" % (sweep_drones - sweep_spawned + sweep_left())
		"protect":
			if not protect_timer_end:
				return "ATTACK DRONES LEFT %d  |  INTERCEPTORS %d" % [protect_drones_left(), protect_interceptors_left()]
			return "ATTACK DRONES LEFT %d  |  %ds" % [protect_drones_left(), ceili(protect_time_left())]
	return "SET %d  |  ENEMY CARRIERS LEFT %d" % [wave_set_number(), wave_force_left()]

func wave_detail_line() -> String:
	if not wave_system_active():
		return ""
	var parts: Array[String] = []
	if wave_phase == "assault":
		parts.append(wave_name())
		if not wave_trait.is_empty():
			parts.append(wave_trait)
	elif wave_phase == "rest":
		parts.append("NEXT  " + next_round_name())
	elif wave_phase == "protect":
		parts.append("SUPPORT SHIPS %d / %d" % [civilians_left(), protect_civilians_total])
	return "  |  ".join(parts)

## 1.2.7: the set score multiplier on its own line under the wave detail line.
func wave_score_line() -> String:
	if not wave_system_active() or set_score_multiplier() <= 1.0:
		return ""
	return "SCORE MULTIPLIER  x%.2f" % set_score_multiplier()

## Tally lines shown in the lower scope during the rest.
func rest_tally_lines() -> Array[String]:
	var lines: Array[String] = []
	if not wave_system_active() or wave_phase != "rest":
		return lines
	if rest_after_protect:
		# 1.2.7: result title, details, the bonus on its own large line, then its label.
		lines.append(protect_result_title())
		if protect_end_reason == "INTERCEPTORS LOST":
			lines.append("SUPPORT FLEET LOST  |  ATTACK DRONES DOWN %d OF %d" % [protect_drones_destroyed, protect_drones_spawned])
		else:
			lines.append("SUPPORT HULL %d%%  |  ATTACK DRONES DOWN %d OF %d" % [protect_hull_kept, protect_drones_destroyed, protect_drones_spawned])
		if last_protect_bonus > 0:
			lines.append("+%d" % last_protect_bonus)
			lines.append("CONVOY BONUS%s" % ("  |  FULL CONVOY" if protect_outcome() == "saved" and protect_end_reason != "JUMP" else ""))
		elif protect_kill_points > 0:
			# 1.0.7.2: no bonus, but the kill points earned in the round are kept; say so.
			lines.append("ENEMY KILLS +%d  |  NO CONVOY BONUS" % protect_kill_points)
		else:
			lines.append("NO CONVOY BONUS")
	elif rest_after_sweep:
		lines.append("BONUS SWEEP  %s" % last_sweep_result)
		if not last_bonus_label.is_empty():
			lines.append("SYSTEMS BONUS  " + last_bonus_label)
	else:
		lines.append("WAVE %d CLEARED  +%d" % [last_cleared_wave, last_wave_bonus])
		if not last_bonus_label.is_empty():
			lines.append("SYSTEMS BONUS  " + last_bonus_label)
		elif systems_bonus_enabled and show_no_systems_bonus:
			lines.append("NO SYSTEMS BONUS")
	if wave_next_phase in ["sweep", "protect"]:
		lines.append("SET %d COMPLETE  |  SCORE x%.2f" % [sets_completed, set_score_multiplier()])
		lines.append("NEXT  %s  IN %d" % [next_round_name(), ceili(wave_rest_remaining)])
	else:
		var next_line := "NEXT  WAVE %d %s" % [wave + 1, wave_name(wave + 1)]
		if not upcoming_trait.is_empty():
			next_line += "  |  " + upcoming_trait
		lines.append(next_line + "  IN %d" % ceili(wave_rest_remaining))
	return lines

## 1.2.0: a quiet tally panel in the lower scope during the rest between waves.
func _draw_rest_tally(font: Font) -> void:
	var lines: Array[String] = rest_tally_lines()
	if lines.is_empty():
		return
	if shared_score_boxes:
		_draw_score_box(font, lines)
		return
	if rest_after_protect:
		_draw_protect_result(font, lines)
		return
	var radius: float = get_parent().sphere_radius
	var top := size.y * 0.5 + radius * rest_tally_offset
	var step := 26.0
	var width := 560.0
	var r := Rect2(size.x * 0.5 - width * 0.5, top, width, 16.0 + step * lines.size())
	draw_rect(r, Color(0.0, 0.0, 0.0, 0.9))
	draw_rect(r, Color("#77324f"), false, maxf(1.0, rest_tally_border_width))
	for index in range(lines.size()):
		var font_size := 21 if index == 0 else 17
		var color := Color("#ede0e8") if index == 0 else (Color("#ffe28b") if index == lines.size() - 1 else Color("#b9a8b2"))
		var text_width := font.get_string_size(lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(size.x * 0.5 - text_width * 0.5, top + 28.0 + step * index), lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## 1.2.7: the Protect the fleet result panel. A green (saved, partial) or red (lost) title,
## one detail line, the bonus large in yellow, its label, then the usual NEXT line.
## The bonus and the border flash for Protect Result Flash Seconds, then stay steady.
func protect_result_rows(lines: Array[String]) -> Array:
	var title_color := Color(1.0, 0.3, 0.35) if protect_outcome() == "lost" else Color(0.45, 1.0, 0.6)
	var rows := [[lines[0], 26, title_color, 34.0], [lines[1], 16, Color("#b9a8b2"), 26.0]]
	if last_protect_bonus > 0:
		rows.append([lines[2], 40, Color("#ffe28b"), 50.0])
		rows.append([lines[3], 16, Color("#ffe28b"), 26.0])
	else:
		rows.append([lines[2], 22, Color("#b9a8b2"), 36.0])
	rows.append([lines[lines.size() - 1], 16, Color("#b9a8b2"), 28.0])
	return rows

func protect_result_rect(rows: Array) -> Rect2:
	if shared_score_boxes:
		return score_box_rect(rows)
	var radius: float = get_parent().sphere_radius
	var height := 24.0
	for row in rows:
		height += float(row[3])
	return Rect2(size.x * 0.5 - 280.0, size.y * 0.5 + radius * protect_result_offset - 30.0, 560.0, height)

func _draw_protect_result(font: Font, lines: Array[String]) -> void:
	var rows := protect_result_rows(lines)
	var r := protect_result_rect(rows)
	var flash_on := protect_result_flash_on()
	var title_color: Color = rows[0][2]
	draw_rect(r, Color(0.0, 0.0, 0.0, 0.9))
	draw_rect(r, title_color if flash_on else Color("#77324f"), false, maxf(1.0, rest_tally_border_width) + 1.0)
	var y := r.position.y + 6.0
	for i in range(rows.size()):
		y += float(rows[i][3])
		var color: Color = rows[i][2]
		if i == 2 and last_protect_bonus > 0 and not flash_on:
			color = Color(color, 0.35)
		var fs: int = rows[i][1]
		var text: String = rows[i][0]
		while fs > 10 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x - 24.0:
			fs -= 1
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(size.x * 0.5 - tw * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

## 1.0.9: rows of the shared round box, each [text, font size, colour, line height].
## The convoy result keeps its own rows (green or red title, large yellow bonus); the
## other boxes get a title, detail lines and the yellow NEXT line.
func score_box_rows(lines: Array[String]) -> Array:
	if rest_after_protect:
		return protect_result_rows(lines)
	var rows := [[lines[0], 26, Color("#ede0e8"), 34.0]]
	for i in range(1, lines.size()):
		rows.append([lines[i], 16, Color("#ffe28b") if i == lines.size() - 1 else Color("#b9a8b2"), 26.0])
	return rows

## 1.0.9: the shared round box: Score Box Width wide, centred, its top at Score Box Offset.
func score_box_rect(rows: Array) -> Rect2:
	var radius: float = get_parent().sphere_radius
	var height := 24.0
	for row in rows:
		height += float(row[3])
	return Rect2(size.x * 0.5 - score_box_width * 0.5, size.y * 0.5 + radius * score_box_offset - 30.0, score_box_width, height)

## 1.0.9: background colour of the shared round box (black at Score Box Opacity).
func score_box_background() -> Color:
	return Color(0.0, 0.0, 0.0, score_box_opacity)

func _draw_score_box(font: Font, lines: Array[String]) -> void:
	var rows := score_box_rows(lines)
	var r := score_box_rect(rows)
	var flash_on := rest_after_protect and protect_result_flash_on()
	draw_rect(r, score_box_background())
	draw_rect(r, rows[0][2] if flash_on else Color("#77324f"), false, maxf(1.0, rest_tally_border_width))
	var y := r.position.y + 6.0
	for i in range(rows.size()):
		y += float(rows[i][3])
		var color: Color = rows[i][2]
		if rest_after_protect and i == 2 and last_protect_bonus > 0 and not flash_on:
			color = Color(color, 0.35)
		var fs: int = rows[i][1]
		var text: String = rows[i][0]
		while fs > 10 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x - 24.0:
			fs -= 1
		var pos := Vector2(size.x * 0.5 - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, y)
		if score_box_text_outline > 0:
			draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, score_box_text_outline, Color(0.0, 0.0, 0.0, 0.85))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

## 1.2.7: threats inbound to the ship for the alert box, most dangerous first. Each entry is
## [count, label, colour]; a line is listed only while its count is above 0. Attack Drones, the
## Siege Ship itself and the player's stealth nukes are not listed.
func inbound_threats() -> Array:
	var rows := []
	if is_defeated():
		return rows
	var nukes := count_kind("nuke")
	var missiles := count_kind("missile")
	var heavies := maxi(0, count_kind("breacher") - emp_heavies_present())
	if nukes > 0:
		rows.append([nukes, "NUKE INBOUND" if nukes == 1 else "NUKES INBOUND", Color(1.0, 0.25, 0.3)])
	if missiles > 0:
		rows.append([missiles, "MISSILE INBOUND" if missiles == 1 else "MISSILES INBOUND", Color(1.0, 0.78, 0.25)])
	if heavies > 0:
		rows.append([heavies, "BREACHER INBOUND" if heavies == 1 else "BREACHERS INBOUND", Color(1.0, 0.78, 0.25)])
	return rows

# ------------------------------------------------------------------
# 1.0.7 Protect the convoy: smart drones, the convoy Breacher, gunfire lines and sounds.
# Used in the round only; every switch off = the 1.0.6 round.
# ------------------------------------------------------------------

## Jump-in angle for a smart drone: of six tries, the one farthest from the drones already here.
func _protect_spread_angle() -> float:
	var best_angle := protect_rng.randf_range(-0.25, PI + 0.25)
	var best_gap := -1.0
	for attempt in range(6):
		var angle := protect_rng.randf_range(-0.25, PI + 0.25)
		var point := Vector2(cos(angle), sin(angle)) * 0.97
		var nearest := INF
		for other in contacts:
			if other.kind == "drone" and other.get("phase", "") == "protect":
				nearest = minf(nearest, point.distance_to(Vector2(other.position.x, other.position.y)))
		if nearest > best_gap:
			best_gap = nearest
			best_angle = angle
	return best_angle

## Smart drone ship choice: nearest ship, strongly avoiding ships other drones attack
## and (when chased) ships near the chaser.
func _protect_smart_pick(drone: Dictionary, chaser: Dictionary) -> Dictionary:
	# Gang Up rounds: drones still spread, but less, and lean toward damaged ships.
	var gang := protect_challenges.has("gang")
	var pull := protect_split_claim_pull * (0.35 if gang else 1.0)
	var best: Dictionary = {}
	var best_score := INF
	for ship in contacts:
		if ship.get("faction", "") != "civilian":
			continue
		var claims := 0
		for other in contacts:
			if other.id != drone.id and other.kind == "drone" and other.get("civ_target", "") == ship.id:
				claims += 1
		var rank: float = drone.position.distance_to(ship.position) + pull * claims
		if gang:
			rank -= protect_gang_damage_pull * (1.0 - float(ship.get("hull", 1.0)))
		if not chaser.is_empty():
			rank -= 0.8 * chaser.position.distance_to(ship.position)
		if rank < best_score:
			best_score = rank
			best = ship
	return best

func _update_smart_drone(drone: Dictionary, delta: float) -> void:
	var chaser := _protect_chaser(drone)
	var chased := not chaser.is_empty()
	if chased and not drone.get("evading", false):
		protect_evasions += 1
		drone.retarget_t = 0.0
	drone.evading = chased
	drone.retarget_t = float(drone.get("retarget_t", 0.0)) - delta
	var target := find_contact(drone.get("civ_target", ""))
	if target.is_empty() or target.get("faction", "") != "civilian" or (chased and drone.retarget_t <= 0.0):
		target = _protect_smart_pick(drone, chaser)
		drone.civ_target = "" if target.is_empty() else target.id
		drone.retarget_t = protect_retarget_seconds
		if target.is_empty():
			return
	var gap: float = drone.position.distance_to(target.position)
	drone.patrol_angle = float(drone.get("patrol_angle", 0.0)) + delta * 1.2
	var aim: Vector3 = target.position
	if gap < 0.15:
		aim += Vector3(cos(drone.patrol_angle), sin(drone.patrol_angle), 0.0) * 0.05
	# Spacing: push away from drones that come too close.
	if protect_drone_separation > 0.0:
		var push := Vector3.ZERO
		for other in contacts:
			if other.id == drone.id or other.kind != "drone" or other.get("phase", "") != "protect":
				continue
			var away: Vector3 = drone.position - other.position
			away.z = 0.0
			var d := away.length()
			if d < protect_drone_separation and d > 0.0001:
				push += away.normalized() * (protect_drone_separation - d) / protect_drone_separation
		aim += push * 0.25
	var speed := protect_drone_speed
	if chased:
		# Evade: weave across the chaser's line, pull a little away from it, fly faster.
		drone.weave_t = float(drone.get("weave_t", 0.0)) + delta * 5.0
		var line: Vector3 = drone.position - chaser.position
		line.z = 0.0
		if line.length() > 0.0001:
			var side := Vector3(-line.y, line.x, 0.0).normalized()
			aim += side * sin(drone.weave_t) * protect_evade_weave + line.normalized() * 0.04
		speed *= protect_evade_speed_factor
		# Rapid bursts back at the chaser.
		drone.burst_t = float(drone.get("burst_t", protect_burst_gap * 0.5)) - delta
		if drone.burst_t <= 0.0 and chaser.position.distance_to(drone.position) <= protect_return_fire_range:
			drone.burst_t = protect_burst_gap
			_protect_drone_burst(drone, chaser)
	_steer(drone, aim, speed, delta)
	if gap <= protect_attack_range:
		drone.attack_cooldown = maxf(0.0, drone.get("attack_cooldown", 0.0) - delta)
		if drone.attack_cooldown <= 0.0:
			drone.attack_cooldown = 0.6
			impacts.append({"position": target.position, "age": 0.0})
			target.flash_t = civilian_hit_flash_seconds
			_protect_tracer_burst(drone.position, target.position, true, 3)
			if not target.get("attack_warned", false):
				target.attack_warned = true
				_play_protect_sound("ship_attacked")
		if protect_damage_stack_cap > 0:
			if float(target.get("stack_key", -1.0)) != protect_elapsed:
				target.stack_key = protect_elapsed
				target.stack_n = 0
			target.stack_n = int(target.stack_n) + 1
			if target.stack_n > protect_damage_stack_cap:
				return
		var factor := protect_evade_damage_factor if chased else 1.0
		_damage_civilian(target, delta / civilian_kill_seconds() * civilian_damage_factor(target) * factor)

## A drone's burst at the Interceptor chasing it: gunfire lines, the rapid-fire sound and
## one roll to down the Interceptor.
func _protect_drone_burst(drone: Dictionary, chaser: Dictionary) -> void:
	protect_bursts += 1
	_protect_tracer_burst(drone.position, chaser.position, true)
	_play_protect_sound("rapid_fire")
	if protect_rng.randf() < clampf(protect_burst_loss_chance, 0.0, 1.0):
		protect_burst_losses += 1
		protect_dogfight_interceptors_lost += 1
		fighter_losses_by["drone"] += 1
		battle_event.emit("interceptor lost to an Attack Drone burst in Protect the convoy")
		_lose_fighter(chaser, "INTERCEPTOR LOST TO ATTACK DRONE FIRE")

## Short gunfire lines from one point toward another (spread slightly, a few rounds).
func _protect_tracer_burst(from: Vector3, to: Vector3, hostile: bool, rounds: int = -1) -> void:
	if not protect_tracers:
		return
	var n := protect_burst_rounds if rounds < 0 else rounds
	for index in range(maxi(1, n)):
		var spread := Vector3(protect_rng.randf_range(-0.006, 0.006), protect_rng.randf_range(-0.006, 0.006), 0.0)
		tracers.append({"from": from, "to": to + spread, "age": -0.05 * index, "hostile": hostile})
	if not hostile:
		_play_protect_sound("rapid_fire")
	while tracers.size() > 80:
		tracers.pop_front()

func _update_tracers(delta: float) -> void:
	for index in range(tracers.size() - 1, -1, -1):
		tracers[index].age = float(tracers[index].age) + delta
		if tracers[index].age > 0.18:
			tracers.remove_at(index)

## Breachers on the scope or still to come.
func convoy_breachers_left() -> int:
	var n := 0
	for contact in contacts:
		if contact.get("phase", "") == "protect_breacher":
			n += 1
	return n

func convoy_breachers_latched() -> int:
	var n := 0
	for contact in contacts:
		if contact.get("phase", "") == "protect_breacher" and contact.get("breach_state", "") == "latched":
			n += 1
	return n

func convoy_breacher_drain_seconds() -> float:
	var seconds := protect_breacher_drain_seconds
	match clampi(active_difficulty, 0, 2):
		0: seconds *= 1.3
		2: seconds *= 0.75
	return maxf(1.0, seconds)

func _spawn_convoy_breacher() -> void:
	var angle := protect_rng.randf_range(-0.25, PI + 0.25)
	var start := Vector3(cos(angle) * 0.97, sin(angle) * 0.97, 0.1)
	var id := _new_id("H")
	var hits := maxi(1, protect_breacher_hits)
	contacts.append({
		"id": id, "kind": "convoy_breacher", "faction": "hostile", "position": start,
		"start": start, "finish": start, "age": 0.0, "progress": 0.0,
		"origin_id": "", "origin_position": start, "target_position": start,
		"defense_checked": false, "phase": "protect_breacher", "breach_state": "approach",
		"approach_point": start, "velocity": Vector3.ZERO, "health": hits, "max_health": hits,
		"civ_target": "", "patrol_angle": 0.0, "hold": protect_jump_in_hold})
	protect_breachers_spawned += 1
	_announce_contact(id, "convoy_breacher", "hostile")
	_set_status("BREACHER INBOUND | IT WILL LATCH ON A SUPPORT SHIP | INTERCEPTORS ENGAGE", 3.0)
	battle_event.emit("Breacher jumped in to Protect the convoy (%d of %d)" % [protect_breachers_spawned, protect_breachers_total])

## The ship a Breacher goes for: the healthiest one no other Breacher holds, nearest on a tie.
func _convoy_breacher_pick(breacher: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for ship in contacts:
		if ship.get("faction", "") != "civilian":
			continue
		var held := 0
		for other in contacts:
			if other.id != breacher.id and other.get("phase", "") == "protect_breacher" and other.get("civ_target", "") == ship.id:
				held += 1
		var rank: float = -float(ship.get("hull", 1.0)) + 0.4 * breacher.position.distance_to(ship.position) + 2.0 * held
		if rank < best_score:
			best_score = rank
			best = ship
	return best

func _update_convoy_breachers(delta: float) -> void:
	var draining := 0
	for breacher in contacts.duplicate():
		if breacher.get("phase", "") != "protect_breacher" or find_contact(breacher.id).is_empty():
			continue
		if float(breacher.get("hold", 0.0)) > 0.0:
			breacher.hold = float(breacher.hold) - delta
			continue
		var ship := find_contact(breacher.get("civ_target", ""))
		if ship.is_empty() or ship.get("faction", "") != "civilian":
			ship = _convoy_breacher_pick(breacher)
			breacher.civ_target = "" if ship.is_empty() else ship.id
			breacher.breach_state = "approach"
			if ship.is_empty():
				continue
		var dock: Vector3 = ship.position + Vector3(0.026, -0.026, 0.0)
		if breacher.breach_state == "approach":
			_steer(breacher, dock, protect_breacher_speed, delta)
			if breacher.position.distance_to(dock) <= 0.02:
				breacher.breach_state = "latched"
				protect_breacher_latches += 1
				_play_protect_sound("breacher_latch")
				_set_status("BREACHER LATCHED ON A SUPPORT SHIP | HULL DRAINING | SEND INTERCEPTORS", 3.5)
				battle_event.emit("Breacher latched on a support ship (%s)" % ship.kind)
			continue
		breacher.position = dock
		breacher.velocity = ship.get("velocity", Vector3.ZERO)
		draining += 1
		ship.drain_t = float(ship.get("drain_t", 0.0)) + delta
		_damage_civilian(ship, delta / convoy_breacher_drain_seconds() * civilian_damage_factor(ship))
	_set_drain_sound(draining > 0)

## An Interceptor hit on a convoy Breacher. True when it is destroyed.
func _hit_convoy_breacher(interceptor: Dictionary, breacher: Dictionary) -> bool:
	_protect_tracer_burst(interceptor.position, breacher.position, false)
	breacher.health = int(breacher.get("health", 1)) - 1
	impacts.append({"position": breacher.position, "age": 0.0})
	if breacher.health > 0:
		_play_protect_sound("interceptor_hit")
		return false
	_award_destroyed(breacher)
	protect_breachers_destroyed += 1
	intercepted_count += 1
	hostile_intercepted.emit(interceptor.id, breacher.id)
	_set_status("BREACHER DESTROYED | SUPPORT SHIP FREED", 2.5)
	battle_event.emit("Breacher destroyed in Protect the convoy")
	return true

func _ensure_convoy_audio() -> void:
	if is_instance_valid(protect_rapid_player):
		return
	protect_rapid_player = _boom_player("ConvoyRapidFireAudio", ProtectAudio.make_rapid_fire(), protect_rapid_fire_volume_db)
	protect_rapid_player.max_polyphony = 3
	protect_latch_player = _boom_player("ConvoyBreacherLatchAudio", ProtectAudio.make_breacher_latch(), protect_breacher_latch_volume_db)
	protect_drain_player = _boom_player("ConvoyBreacherDrainAudio", ProtectAudio.make_breacher_drain(), protect_breacher_drain_volume_db)

func _play_convoy_sound(which: String) -> void:
	if not protect_convoy_sounds:
		return
	if which == "rapid_fire":
		# At most about four bursts a second, so a big fight does not become a wall of noise.
		if battle_time - protect_last_rapid_at < 0.25 or not is_instance_valid(protect_rapid_player):
			return
		protect_last_rapid_at = battle_time
		protect_rapid_player.volume_db = protect_rapid_fire_volume_db
		protect_rapid_player.play()
	elif which == "breacher_latch":
		if not is_instance_valid(protect_latch_player):
			return
		protect_latch_player.volume_db = protect_breacher_latch_volume_db
		protect_latch_player.play()
	protect_sound_counts[which] = int(protect_sound_counts.get(which, 0)) + 1

func _set_drain_sound(on: bool) -> void:
	if not is_instance_valid(protect_drain_player):
		return
	on = on and protect_convoy_sounds and protect_round_sounds and protect_active()
	if on and not protect_drain_player.playing:
		protect_drain_player.volume_db = protect_breacher_drain_volume_db
		protect_drain_player.play()
		protect_sound_counts["breacher_drain"] = int(protect_sound_counts.get("breacher_drain", 0)) + 1
	elif not on and protect_drain_player.playing:
		protect_drain_player.stop()

## 1.0.7: gunfire lines and the pulsing drain link from each latched Breacher to its ship.
func _draw_convoy_effects() -> void:
	for breacher in contacts:
		if breacher.get("phase", "") != "protect_breacher" or breacher.get("breach_state", "") != "latched":
			continue
		var ship := find_contact(breacher.get("civ_target", ""))
		if ship.is_empty():
			continue
		var a: Vector2 = projection(breacher.position).point
		var b: Vector2 = projection(ship.position).point
		var pulse := 0.5 + 0.5 * sin(battle_time * 9.0)
		draw_line(a, b, Color(hostile_color, 0.35 + 0.45 * pulse), 2.0, true)
		draw_arc(b, 9.0 + 5.0 * pulse, 0.0, TAU, 28, Color(hostile_color, 0.25 + 0.35 * (1.0 - pulse)), 1.0, true)
	for tracer in tracers:
		var age := float(tracer.age)
		if age < 0.0:
			continue
		var t := clampf(age / 0.14, 0.0, 1.0)
		var from: Vector2 = projection(tracer.from).point
		var to: Vector2 = projection(tracer.to).point
		var head := from.lerp(to, t)
		var tail := from.lerp(to, maxf(0.0, t - 0.35))
		var color: Color = protect_drone_tracer_color if tracer.hostile else protect_tracer_color
		color.a = 0.95 * (1.0 - 0.5 * t)
		draw_line(tail, head, color, 1.5, true)

## 1.0.7 Smart Repair Tender: how urgently a ship needs the tender. Ships losing hull now
## (Attack Drones on them or a latched Breacher) and low on hull come first; ships it cannot
## reach before they are lost score nothing. Returns {} when no ship needs it.
func _tender_need(gunship: Dictionary, ship: Dictionary) -> float:
	if float(ship.hull) >= 0.98 or _patch_used_up(ship):
		return -1.0
	var gap: float = maxf(0.0, gunship.position.distance_to(ship.position) - 0.08)
	var eta := gap / maxf(0.01, protect_tender_speed)
	var drain := 0.0
	for other in contacts:
		if other.kind == "drone" and other.get("phase", "") == "protect" and other.get("civ_target", "") == ship.id \
				and other.position.distance_to(ship.position) <= protect_attack_range + 0.03:
			drain += 1.0 / civilian_kill_seconds() * civilian_damage_factor(ship)
		elif other.get("phase", "") == "protect_breacher" and other.get("breach_state", "") == "latched" and other.get("civ_target", "") == ship.id:
			drain += 1.0 / convoy_breacher_drain_seconds() * civilian_damage_factor(ship)
	if drain <= 0.0 and float(ship.hull) > protect_tender_ignore_above:
		return -1.0
	var need := 1.0 - float(ship.hull)
	if drain > 0.0:
		var seconds_left := float(ship.hull) / drain
		if seconds_left < eta * 0.9:
			return -1.0
		need += 0.6 + 0.4 * clampf(1.0 - seconds_left / 20.0, 0.0, 1.0)
	return need - 0.04 * eta

func _tender_pick(gunship: Dictionary, current: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 0.0
	for ship in contacts:
		if ship.get("faction", "") != "civilian":
			continue
		var score := _tender_need(gunship, ship)
		if score > best_score:
			best_score = score
			best = ship
	if not current.is_empty() and not best.is_empty() and best.id != current.id:
		var keep := _tender_need(gunship, current)
		if keep > 0.0 and best_score < keep + protect_tender_switch_margin:
			return current
	if best.is_empty() and not current.is_empty() and _tender_need(gunship, current) > -1.0:
		return current
	return best


# ------------------------------------------------------------------
# 1.1.0 PULSE BOMB. The Stealth Interceptor carries NUKES (as in
# 1.0.9) or, while a score-earned charge is held, one PULSE BOMB (Normal every 40,000
# points, Hard every 50,000, never on Easy, at most 1 held). The bomb freezes Enemy
# Carriers, enemy fighters and the Siege Ship inside its area for 10 seconds (double damage while frozen); hacking
# or draining Breachers break off and fly home as with USE EMP. Enemy missiles in
# flight are not frozen; nuclear missiles in the area fly slower. Our ships are not
# affected and keep fighting. Frozen enemies give normal points.
# ------------------------------------------------------------------
func _pulse_large_ships() -> Array:
	var found: Array = []
	for contact in contacts:
		if contact.kind in CAPITAL_KINDS:
			found.append(contact)
	return found

func _pulse_catches(spot: Vector3) -> int:
	var count := 0
	for contact in contacts:
		if contact.kind in CAPITAL_KINDS and _pulse_gap(spot, contact.position) <= pulse_radius:
			count += 1
	return count

func _pulse_gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()

## Where the bomb is aimed: the nearest Enemy Carrier, or (Most) the spot that catches
## the most large ships (each large ship, and halfway between each pair).
func _pulse_aim(from: Vector3) -> Dictionary:
	var ships := _pulse_large_ships()
	var carriers: Array = ships.filter(func(c: Dictionary) -> bool: return c.kind == "carrier")
	if carriers.is_empty():
		return {}
	var best_spot := Vector3.INF
	var best_count := -1
	var best_gap := INF
	var candidates: Array = []
	if pulse_aim == 0:
		for c in carriers:
			candidates.append(c.position)
	else:
		for i in range(ships.size()):
			candidates.append(ships[i].position)
			for j in range(i + 1, ships.size()):
				candidates.append((ships[i].position + ships[j].position) * 0.5)
	for spot in candidates:
		var count := 1 if pulse_aim == 0 else _pulse_catches(spot)
		var gap: float = from.distance_to(spot)
		if count > best_count or (count == best_count and gap < best_gap):
			best_count = count
			best_gap = gap
			best_spot = spot
	return {"point": best_spot, "count": best_count}

func _drop_pulse_bomb(ship: Dictionary, aim: Dictionary) -> void:
	pulse_bombs.append({"position": ship.position, "target": aim.point, "phase": "fly", "age": 0.0, "fuse": 0.0})
	ship.nukes_left = 0
	ship.revealed = true
	ship.phase = "return"
	pulse_charges = maxi(0, pulse_charges - 1)
	stealth_nukes_fired += 1
	_set_status("STEALTH INTERCEPTOR | PULSE BOMB AWAY", 2.5)
	stealth_event.emit("Stealth Interceptor dropped a PULSE BOMB")

func _update_pulse(delta: float) -> void:
	if pulse_freeze_left > 0.0:
		pulse_freeze_left -= delta
		if pulse_freeze_left <= 0.0:
			pulse_freeze_left = 0.0
			_set_status(PULSE_ENDED_TEXT, 2.5)
			battle_event.emit("pulse bomb freeze ended")
	for index in range(pulse_fields.size() - 1, -1, -1):
		var field: Dictionary = pulse_fields[index]
		field.age += delta
		field.remaining -= delta
		if field.remaining <= 0.0:
			pulse_fields.remove_at(index)
	for index in range(pulse_bombs.size() - 1, -1, -1):
		var bomb: Dictionary = pulse_bombs[index]
		bomb.age += delta
		if bomb.phase == "fly":
			bomb.position = bomb.position.move_toward(bomb.target, delta * movement_speed * stealth_nuke_speed)
			if bomb.position.distance_to(bomb.target) <= 0.01:
				bomb.phase = "fuse"
		elif bomb.phase == "fuse":
			bomb.fuse += delta
			if bomb.fuse >= pulse_fuse_seconds:
				pulse_bombs.remove_at(index)
				_detonate_pulse(bomb.target)

func _detonate_pulse(spot: Vector3) -> void:
	pulse_detonations += 1
	var large := 0
	var fighters := 0
	var home := 0
	for contact in contacts:
		if contact.get("faction", "") != "hostile" or _pulse_gap(spot, contact.position) > pulse_radius:
			continue
		if contact.kind == "nuke":
			# Not frozen: slowed until it hits or is destroyed.
			if pulse_nuke_speed_factor < 1.0 and not contact.get("pulse_slowed", false):
				contact.pulse_slowed = true
				pulse_nukes_slowed += 1
			continue
		if contact.kind == "breacher" and contact.get("phase", "") in ["hacking", "draining"]:
			contact.phase = "emp"
			contact.emp_remaining = maxf(0.1, emp_shimmer_seconds)
			contact.velocity = Vector3.ZERO
			home += 1
			continue
		if contact.kind in ["carrier", "siege_ship", "drone", "breacher"]:
			contact.frozen = pulse_freeze_seconds
			if contact.kind in CAPITAL_KINDS:
				large += 1
			else:
				fighters += 1
	pulse_frozen_large += large
	pulse_frozen_fighters += fighters
	pulse_breachers_sent_home += home
	pulse_fields.append({"position": spot, "radius": pulse_radius, "remaining": 0.5, "age": 0.0})
	if large + fighters > 0:
		pulse_freeze_left = pulse_freeze_seconds
	if is_instance_valid(emp_player):
		emp_player.volume_db = emp_zap_volume_db
		emp_player.play()
	var line := "PULSE BOMB | %d LARGE SHIP%s AND %d FIGHTER%s FROZEN FOR %d S" % [large, "" if large == 1 else "S", fighters, "" if fighters == 1 else "S", int(pulse_freeze_seconds)]
	if home > 0:
		line += " | %d BREACHER%s SENT HOME" % [home, "" if home == 1 else "S"]
	_set_status(line, 4.0)
	stealth_event.emit(line)

func _draw_pulse(_font: Font) -> void:
	# Stephen 2026-10-25: no area ring; a short white flash where the bomb goes off.
	for field in pulse_fields:
		var life := clampf(float(field.age) / 0.45, 0.0, 1.0)
		var point: Vector2 = projection(field.position).point
		var fade := 1.0 - life
		draw_circle(point, 12.0 + 36.0 * life, Color(1, 1, 1, 0.85 * fade * fade))
		draw_arc(point, 14.0 + 40.0 * life, 0.0, TAU, 40, Color(pulse_color.lerp(Color.WHITE, 0.6), fade), 3.0, true)
		draw_circle(point, 8.0 * fade + 2.0, Color(1, 1, 1, fade))
	for bomb in pulse_bombs:
		var point: Vector2 = projection(bomb.position).point
		var lit := true
		if bomb.phase == "fuse":
			lit = int(float(bomb.fuse) * 8.0) % 2 == 0
		var size := 5.0
		var diamond := PackedVector2Array([point + Vector2(0, -size), point + Vector2(size, 0), point + Vector2(0, size), point + Vector2(-size, 0)])
		draw_colored_polygon(diamond, Color.WHITE if lit else pulse_color)
		draw_arc(point, size + 3.0, 0.0, TAU, 20, Color(pulse_color, 0.8), 1.0, true)

## Drain: every whole second frozen, take pulse_drain_per_second of the current strength.
## Attack Drones: pulse_drone_drain_per_second of their full strength, and the drain
## can destroy them. Returns true when it destroyed the contact (caller removes it).
func _pulse_drain_step(contact: Dictionary, delta: float) -> bool:
	contact.drain_flash = maxf(0.0, float(contact.get("drain_flash", 0.0)) - delta)
	if contact.get("faction", "") != "hostile":
		return false
	contact.drain_tick = float(contact.get("drain_tick", 0.0)) + delta
	# The last whole second can land on the same frame the freeze ends.
	var last_tick: bool = float(contact.get("frozen", 0.0)) <= 0.0 and contact.drain_tick >= 0.9
	if contact.drain_tick < 1.0 and not last_tick:
		return false
	contact.drain_tick = maxf(0.0, contact.drain_tick - 1.0)
	if contact.kind == "drone" and pulse_drone_drain_per_second > 0.0:
		var hits := int(contact.get("interceptor_hits", drone_interceptor_hits))
		if not contact.has("drain_full"):
			contact.drain_full = maxi(1, hits)
		var carry := float(contact.get("drain_carry", 0.0)) + float(contact.drain_full) * pulse_drone_drain_per_second
		while carry >= 0.9999 and hits > 0:
			hits -= 1
			carry -= 1.0
		contact.interceptor_hits = hits
		contact.drain_carry = maxf(0.0, carry)
		pulse_drained += float(contact.drain_full) * pulse_drone_drain_per_second
		contact.drain_flash = 0.3
		impacts.append({"position": contact.position, "age": 0.0})
		if hits <= 0:
			pulse_drain_kills += 1
			_award_destroyed(contact)
			return true
		return false
	if pulse_drain_per_second <= 0.0:
		return false
	var lost := 0.0
	if contact.kind in ["carrier", "siege_ship"]:
		lost = float(contact.hits_remaining) * pulse_drain_per_second
		contact.hits_remaining = float(contact.hits_remaining) - lost
	elif contact.kind == "breacher":
		# Whole-hit enemies: keep the fraction and take a hit when it adds up to one.
		var key := "health"
		var current := float(contact.get(key, 1))
		var carry := float(contact.get("drain_carry", 0.0)) + current * pulse_drain_per_second
		if carry >= 1.0 and current > 1.0:
			contact[key] = int(current) - 1
			carry -= 1.0
		contact.drain_carry = carry
		lost = current * pulse_drain_per_second
	else:
		return false
	pulse_drained += lost
	contact.drain_flash = 0.3
	impacts.append({"position": contact.position, "age": 0.0})
	return false

func pulse_damage_factor(contact: Dictionary) -> float:
	return maxf(1.0, pulse_frozen_damage_factor) if float(contact.get("frozen", 0.0)) > 0.0 else 1.0

func _nearest_frozen(from: Vector3, kinds: Array, excluded: Array[String]) -> Dictionary:
	var chosen: Dictionary = {}
	var best := INF
	for contact in contacts:
		if contact.kind not in kinds or contact.id in excluded or float(contact.get("frozen", 0.0)) <= 0.0:
			continue
		var gap: float = from.distance_to(contact.position)
		if gap < best:
			best = gap
			chosen = contact
	return chosen

const PULSE_EARNED_TEXT := "PULSE BOMB EARNED | READY ON THE STEALTH WEAPON BUTTON"
const PULSE_HELD_TEXT := "PULSE BOMB ALREADY HELD | ONLY 1 CAN BE CARRIED"
const PULSE_ENDED_TEXT := "PULSE BOMB FREEZE ENDED"

func pulse_step_points() -> int:
	return pulse_bomb_hard_points if active_difficulty >= 2 else pulse_bomb_normal_points

func _check_pulse_award() -> void:
	if not pulse_bomb_enabled or not stealth_interceptor_enabled or active_difficulty < 1:
		return
	var entitled := int(earned_points / maxi(1, pulse_step_points()))
	if entitled <= pulse_awards_earned:
		return
	var new_awards := entitled - pulse_awards_earned
	pulse_awards_earned = entitled
	var room := maxi(0, pulse_bomb_max_charges - pulse_charges)
	pulse_charges += mini(room, new_awards)
	pulse_charges_lost += maxi(0, new_awards - room)
	if room > 0:
		bonus_chimes += 1
		if is_instance_valid(bonus_chime_player):
			bonus_chime_player.volume_db = bonus_chime_volume_db
			bonus_chime_player.play()
		_set_status(PULSE_EARNED_TEXT, 4.0)
		# A kill's own status line can come later in the same frame; show this one after it.
		call_deferred("_set_status", PULSE_EARNED_TEXT, 4.0)
		battle_event.emit("pulse bomb charge earned at %d points" % earned_points)
	else:
		_set_status(PULSE_HELD_TEXT, 4.0)
		call_deferred("_set_status", PULSE_HELD_TEXT, 4.0)
		battle_event.emit("pulse bomb charge lost (already holding %d) at %d points" % [pulse_charges, earned_points])
