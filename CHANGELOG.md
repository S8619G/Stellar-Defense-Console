# Stellar Defense Console changelog

## 1.0.1

First public release.

- Exports no longer need the S3TC/BPTC texture setting turned on by hand; it is saved in the project.
- "Export With Debug" starts unchecked, so exports are release builds by default.
- Internal names in the code, saved settings and high-score stats now match the game's own names. Settings and high scores from earlier versions are converted automatically when loaded.
- Gameplay, controls, audio, art and balance are unchanged.

## 1.0.0

- Game controller support for Xbox-style and PlayStation-style controllers: battle actions, a one-second hold for Jump, MENU for Settings, and highlight navigation with the D-pad or left stick.
- A Controller panel in Settings with a controller drawing, the current button for each action, CHANGE, SET for spare buttons, and a two-step DEFAULTS. Controller buttons are saved separately from other settings.
- Controllers work in Settings, the missile bonus pick, initials entry and game over, and can press the center special weapon and the EMP.
- Stick drift is ignored, held directions repeat at a steady rate, and connecting or disconnecting a controller during play is handled safely.
- The hull bar's fill meets its border, and the hull percentage is shown below the bar.
- Full version number in all export file names, including `Stellar_Defense_Console_1.0.0_Linux.x86_64`.
