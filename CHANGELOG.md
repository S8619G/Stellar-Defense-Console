# Stellar Defense Console changelog

## 1.1.0

### Top message bar

- The message bar along the top of the scope says DEFEND THE AEGIS where it said DEFEND THE LOWER SCOPE. The text after the divider is unchanged.

### JUMP cost

- A JUMP during a wave costs 3,000 points or 10% of the current score, whichever is bigger (for example 4,600 points at a score of 46,000). Below 30,000 points nothing changes.
- Every JUMP costs the same way; repeat jumps do not cost more. Auto jump pays the same cost.
- The JUMP button, the side panel and the JUMP messages show the cost at that moment.
- A JUMP during the rest between waves stays free. The score never goes below zero, and bonuses and EMP charges still count earned points.

### Rapid Repair limit

- At most 2 Rapid Repair charges on Easy and 4 on Normal and Hard.
- Once the limit is reached, no charges are earned until 1 charge is left. A charge earned at the limit is lost. Earning then starts again at the next point total still ahead.
- While earning is paused, the left panel shows EARNING AT 1 CHARGE in place of NEXT BONUS IN.
- The end-of-set EXTRA RAPID REPAIR reward is offered only while earning is not paused and below the limit.

### Idle screens

- On the Game Over screen, the Settings screen and while the game is paused, the game draws at 10 frames a second. The screens look the same.
- After 5 minutes with no key, mouse or controller input on these screens, the game no longer keeps the computer awake, so the computer's own sleep and screen-off settings apply.
- Any input restarts the 5 minutes. Closing Settings, Retry or a new battle brings back the full frame rate. During a running battle the computer is still kept awake.

### FRAME RATE setting

- New FRAME RATE row on the Settings panel, under SCREEN EFFECTS, with one button that switches between STANDARD and SMOOTH. The Settings panel is one row taller.
- STANDARD (the default, also for existing settings files): at most 60 frames a second.
- SMOOTH: matches the screen's refresh rate, never above it.
- The choice is saved with the other settings.

### Graphics chip on Windows

- The Windows builds no longer ask Nvidia and AMD drivers for the powerful graphics card. Windows chooses the graphics chip, usually the low-power one. The powerful card can still be chosen in Windows Settings > System > Display > Graphics, or in the Nvidia or AMD control panel.

### Interceptors and hacking Breachers

- While no Gunship is out attacking, a Breacher that is hacking or draining the ship is the first target for Interceptors, ahead of Attack Drones and missiles. Up to 2 Interceptors go after each one; the others keep defending.
- Breachers that are only approaching are chased as before. A Gunship that is out attacking switches this off; a Gunship flying back to the ship does not.

### PULSE BOMB

- On Normal and Hard, a PULSE BOMB charge is earned every 40,000 points on Normal and every 50,000 on Hard. At most 1 is held; a charge earned while one is held is lost. Not on Easy.
- While a charge is held, the STEALTH WEAPON button shows two buttons of the same size, NUKES and PULSE. NUKES launches the 2 nukes and keeps the charge; PULSE launches the PULSE BOMB. On a controller, a short press fires NUKES and a 1-second hold fires the PULSE BOMB (the PULSE button fills while held).
- The STEALTH WEAPON button still lights up only while 3 or more large ships are on the scope.
- The bomb goes off over the spot that catches the most large ships, with a short white flash. Every Enemy Carrier, Siege Ship and enemy fighter in its large area is frozen for 10 seconds: no moving, firing or launching. Frozen enemies show an ice-blue look and take double damage.
- Frozen Enemy Carriers, the Siege Ship and Breachers also lose 5% of their current strength each second; this never destroys them on its own. Frozen Attack Drones lose 10% of their full strength each second and can be destroyed by it. All give normal points.
- Hacking or draining Breachers in the area break off and fly home to their Enemy Carrier, as with USE EMP.
- A nuclear missile heading for the ship inside the area is slowed to 60% of its speed until it hits or is destroyed, and shows an ice-blue shimmer. Other missiles in flight are not affected.
- While enemies are frozen, Interceptors go after frozen Attack Drones first, each one a different drone, then frozen Enemy Carriers, and fly 1.5 times faster while chasing a frozen target. Gunships deal with nukes first, then attack frozen Enemy Carriers.
- The left panel shows PULSE BOMB 0 or 1 under EMP CHARGES on Normal and Hard. New status messages tell when a PULSE BOMB is earned, already held, launched, dropped, what it froze, and when the freeze ends.
- The Stealth Interceptor keeps its green colour on the way home after either weapon (it only blinks); it no longer fades toward white.

### Breach alert

- While a Breacher is hacking or draining, the whole ship fill flashes red and black stripes; the outline keeps the hull colour. The STEALTH WEAPON button (or the NUKES and PULSE buttons) stays on top and can always be clicked.
- The NAV DATA window is set aside and flashes INTRUSION DETECTION. The same NAV DATA returns when the breach ends. The left panel still shows the breach details.

### NAV DATA

- One of the nearest-body names in the NAV DATA list is now HELIUM-3 FIELD.

### Drawing

- The console frame is redrawn only when something on it changes (and at least once a second), and the ship panel only while an effect plays or something changes. The picture is the same; the processor does less work each frame.

## 1.0.9

### Score and round boxes

- Every round box (wave cleared, set complete, Bonus Sweep result and the Protect the convoy result) now has the same size and place: 600 pixels wide, the same width as the Game Over screen, centred in the top part of the scope.
- The round boxes are see-through (65% solid), so the radar shows behind them. Titles are larger (size 26) and detail lines size 16. All text has a dark outline so it stays easy to read.
- The Protect the convoy result keeps its green or red border and its large yellow bonus. The other boxes keep their yellow NEXT line.
- The Game Over screen and the high score stats box are 80% solid (they were almost fully solid), with the same dark outline on the text.

### SYSTEMS OFFLINE list

- When the ship is destroyed, the list on the red SYSTEMS OFFLINE screen now types out one line at a time, left to right, with a block cursor: a new line about every 0.9 seconds (it was 0.38 seconds).
- When the red panel is full, the list steps up one line at a time and keeps cycling.
- Statuses are still picked at random each time. Timing of the red screen and the score screen is unchanged.

### Low hull warning

- When the hull drops below 6%, the HULL bar flashes bright red and dark red (about 2.5 times a second), and the console gives a light screen flicker (about a quarter of a second, about every 1.5 to 3 seconds).
- The warning stops when the hull is repaired to 6% or more, and when the ship is destroyed (SYSTEMS OFFLINE takes over).
- A nuke hit's own scramble takes over while it plays.
- With SCREEN EFFECTS off there is no flicker, but the HULL bar still flashes.
- No new sounds.

### Rapid Missile balance

- Rapid Missile now fires 1 missile every 5 seconds on Normal (was 6) and every 4 seconds on Hard (was 5), and its missiles fly 20% faster.
- Double Missile, the points needed to earn each bonus, and Gunship missiles are unchanged.
- The bonus pick cards have a third line: RAPID MISSILE "Missiles fly 20% faster", DOUBLE MISSILE "Can hit two targets at once".

## 1.0.8

1.0.8 brings the new Protect the convoy round and new damage effects. It also includes all changes from 1.0.2 to 1.0.6, which were not released separately.

### Damage effects

- Nuke hit: when a nuke hits the ship directly, the inner console (radar, side columns and readouts) scrambles for about 0.8 seconds, as if the screen lost its signal. A nuke that is destroyed close to the ship by the Defense Shield, but still causes splash damage, gives a weaker scramble (about half strength, about 0.4 seconds).
- Ship destroyed:
  - The radar sound stops at once (with a very short fade, so it does not click).
  - The inner console scrambles hard for 0.7 seconds, flickers, then turns red and shows SYSTEMS OFFLINE.
  - Below the title, a list of ship systems (MAIN POWER, AUXILIARY POWER, RADAR, TRACKING, TARGETING, DEFENSE SHIELD, JUMP DRIVE, NAVIGATION, COMMUNICATIONS, DATA LINK, INTERCEPTOR LAUNCH BAY, GUNSHIP BAY, FIREWALL, RAPID REPAIR, DAMAGE CONTROL, LIFE SUPPORT) appears one line at a time. Each one reads OFFLINE, DESTROYED or DAMAGED, picked at random every time. The list scrolls and keeps cycling.
  - A light scramble passes over the red screen every 2.5 to 4 seconds.
  - Two seconds after the red screen appears, the score screen comes up in front. The score screen is never scrambled.
- The top header, the side panels and the bottom button bar are never scrambled.
- Retry starts a clean battle: the effects clear and the radar sound starts again.

### New setting: SCREEN EFFECTS

- Settings has a new SCREEN EFFECTS ON/OFF switch, on by default.
- With it off, nothing scrambles. When the ship is destroyed, the radar sound still stops and the red SYSTEMS OFFLINE screen shows straight away, and the score screen comes up in front 2 seconds later.
- The choice is saved, even with REMEMBER SETTINGS off, like the display settings.
- The Settings panel is one row taller (988 pixels) to make room for the new row.

### Protect the convoy round

The round between sets (called Protect the fleet in 1.0.6) is now Protect the convoy.

- Names: the round is PROTECT THE CONVOY, and the ships are the Support Fleet. Ship labels read SUPPORT n%, and the result reads SUPPORT FLEET SAVED or SUPPORT FLEET LOST, with CONVOY BONUS.
- Round box (lower left): rows are SHIPS, DRONES, INTERCEPTORS and BREACHER. The values start after the widest label, so labels never run into values.
- Smarter Attack Drones: they jump in at points spread around the scope edge, and each one goes after its own ship. When an Interceptor chases one, it weaves, speeds up, switches to a ship away from the chaser, keeps damaging ships in range (at 75%) and fires rapid bursts back. Each burst has a 6% chance to destroy the chasing Interceptor.
- Breacher: jumps in 8 to 16 seconds into the round (at once if every drone is gone), flies to the healthiest ship, latches on and drains its hull (label HULL DRAIN, with a pulsing link line). A full ship lasts about 26 seconds on Normal, 34 on Easy and 20 on Hard. Interceptors treat it as a top target, and it takes 6 hits. The round does not end while a Breacher is still on the scope.
- Gunfire lines: short red lines for drone bursts and gold lines for Interceptor hits.
- New sounds: a rapid-fire burst, a clank when the Breacher latches on, and a pulsing hum while it drains a ship.
- How the round ends: there is no 60-second time limit any more. The round ends when every Attack Drone and Breacher is destroyed (convoy bonus paid), when every support ship is lost (no bonus), or when every Interceptor is lost and none are left to launch.
  - Every Interceptor lost means the convoy has no defense left. The round is a total loss, the remaining support ships are lost and no bonus is paid. The result title reads ALL INTERCEPTORS LOST, with SUPPORT FLEET LOST | ATTACK DRONES DOWN n OF n below it.
  - Points for Attack Drone and Breacher kills are kept even when the round is lost. With no convoy bonus, the box shows ENEMY KILLS +n | NO CONVOY BONUS.
  - A hidden 5-minute safety limit ends a round that gets stuck. It should never come up in normal play.
- The result box now sits in the top part of the scope.
- Repair tender:
  - It waits on the player's ship and launches, like a Gunship, the first time any support ship has taken more than 4% damage. Rounds that have a tender are the same as before (Normal from set 3 at a 50% chance, Hard every round).
  - It flies at Attack Drone speed and repairs 25% faster (0.10 of a ship's hull a second).
  - About once a second it checks every support ship again. Ships under attack, or with a Breacher latched on, come first, then the most damaged. It switches ships when another one clearly needs it more, skips a ship it cannot reach in time, and leaves ships above 90% hull alone when they are not under attack.
  - When no ship needs repairs, it stays near the convoy and the fight.
  - It has a hull as thick as the biggest support ship's, and Attack Drones close to it wear it down. Its label shows its hull once damaged (REPAIR TENDER 67%). If it is destroyed, the status line reads REPAIR TENDER LOST | NO MORE REPAIRS THIS ROUND. It does not count as a lost Gunship and costs no points.
  - If it survives the round, it flies home and lands (REPAIR TENDER RECOVERED).
  - Enemy Carrier flak no longer aims at it.
  - Easy: repairs ships to 100%. Normal and Hard: one 25% patch per ship.
- Support ships repair themselves at half the old speed (0.02 of a ship's hull a second), still starting after 3 seconds without attack and up to 75%.

### Unchanged

- Waves, sets, enemies, scoring, launches, controls, art and the radar sound are unchanged outside the Protect the convoy round. Seeded test battles play out exactly as in 1.0.6.

## 1.0.6

- The launch buttons now show how many ships the next press sends: at most 2 READY for Interceptors and 1 READY for Gunships. After a press the button counts down, then shows the next ships.
- The missile bonus pick pop-up never opens during a battle round. A bonus earned during a wave, a Protect the fleet round or a Bonus Sweep is offered when that round ends (the Bonus Sweep is new in 1.0.6).
- The status line shown while the pick waits now names the bonus just earned.
- Waiting times, ships per press, the pop-up itself, enemies, scoring, controls, art and sound are unchanged.

## 1.0.5

- Each Interceptor and Gunship now has its own ready timer. The launch button shows how many are ready (for example 2 READY), and one press launches whatever is ready, up to 2 Interceptors or 1 Gunship.
- ALL DEPLOYED shows straight away when every ship is out.
- A landing only makes the ship that landed wait (3 s for an Interceptor, 5 s for a Gunship). Ships already ready, or already counting down, are not held back. Auto Launch works the same way.
- The missile bonus pick pop-up now counts down from 20 seconds. Moving the mouse, pressing an arrow key or using a controller stops the countdown, and the pop-up waits for a pick.
- In the pop-up, the two bonus cards are now the buttons. The KEEP and TAKE buttons are gone, and the current bonus is highlighted when the pop-up opens.
- Waiting times, ships per press, enemies, scoring, controls, art and sound are unchanged.

## 1.0.4

- Controller panel: the table now has one row per controller button (A, B, X, Y, LB, RB, LT, RT), showing what each one does.
- CHANGE opens a list of every battle action. Pick one with the mouse, touch or the controller, and the list closes and the row updates. The button's current action is marked CURRENT, and actions on other buttons show which button has them.
- If the picked action is already on another button, the game asks what to do: swap the two buttons, use both buttons, move it here (the other button becomes not set), or cancel.
- Launch Stealth Interceptor and Use EMP are now actions that can be put on any button. By default, LT launches the Stealth Interceptor and RT uses the EMP.
- Saved controller setups from earlier versions keep their buttons; a blank LT or RT gets the new Stealth Interceptor or EMP default.
- The old "press the new button now" step and the SET buttons are gone. TEST BUTTONS, DEFAULTS, CLOSE and the small "!" work as before.
- Gameplay, keyboard, mouse and touch controls are unchanged.

## 1.0.3

- The radar's two orbital rings now overlap: the right ring starts its sweep when the left ring is 56% of the way through its own, so the two rings are seen crossing each other. Each sweep still takes 1.2 seconds and the whole cycle still lasts 3.25 seconds.
- The second tone of the radar sound now starts with the right ring, so the two-tone sound matches the rings again.
- The controller check is now a small round "!" in the top-right corner of the Controller panel, instead of a full-size COPY CONTROLLER CHECK button. It works the same way.
- Gameplay, controls, button assignments, ring colors and the sound's volume are unchanged.

## 1.0.2

- The Controller panel shows whether a controller is connected, its name, whether it is compatible and, where it can tell, how it is connected (USB, Bluetooth, XInput or Steam Input). The line updates by itself while the panel is open.
- When no controller is found, the panel explains how to connect one by Bluetooth, USB cable or Xbox Wireless Adapter. If the controller system itself did not start, it says so.
- New TEST BUTTONS mode in the Controller panel: every controller button, trigger, D-pad direction and the stick lights up its assigned action and its label on the controller drawing, with a short note saying what it does. MENU, Esc or STOP TEST ends the test.
- Pressing a controller button in the Controller panel lights up its action, and in battle the console button it used lights up briefly.
- New COPY CONTROLLER CHECK button: copies a short report of what the game sees (system, controller system, controllers found, connection, events received) so it can be pasted into a message. The same report is written to the session log at start, three seconds later and whenever it is copied.
- Gameplay, button assignments, keyboard, mouse and touch are unchanged.

## 1.0.1

First public release.

- Exports no longer need the S3TC/BPTC texture setting turned on by hand; it is saved in the project.
- "Export With Debug" starts unchecked, so exports are release builds by default.
- Internal names in the code, saved settings and high-score stats now match the game's own names. Settings and high scores from earlier versions are converted automatically when loaded.
- Gameplay, controls, audio, art and balance are unchanged.

## 1.0.0

- Added game controller support for Xbox-style and PlayStation-style controllers: battle actions, a one-second hold for Jump, MENU for Settings, and highlight navigation with the D-pad or left stick.
- Added a Controller panel in Settings with a controller drawing, the current button for each action, CHANGE, SET for spare buttons, and a two-step DEFAULTS. Controller buttons are saved separately from other settings.
- Controllers can be used in Settings, the missile bonus pick, initials entry and game over, and to press the center special weapon and the EMP.
- Stick drift is ignored, held directions repeat at a steady rate, and connecting or disconnecting a controller during play is handled safely.
- The hull bar's fill now meets its border, and the hull percentage is shown below the bar.
- Full version number in all export file names, including `Stellar_Defense_Console_1.0.0_Linux.x86_64`.
- Keyboard, mouse and touch controls, audio, alerts and combat balance are unchanged.

## 0.1.2

- Widened the active vertical hull indicator and adjusted its ruler clearance.
- Matched its fill colour to Aegis's live hull condition, damage flash and repair pulse.
- Renamed the defense to Defense Shield throughout player-visible text, including automatic-operation bonuses.
- Preserved defense behaviour, saved settings, combat balance, the center weapon button and all approved audio.
