# Settings Guide

[简体中文](SETTINGS.zh-CN.md) · [Documentation index](INDEX.md)

Open Chef's **F9** menu and select **HUD Lite 1.0.0**.

## Player-facing settings

- **Display:** HUD visibility, center ammunition format, arc tracks, health,
  stamina, backpack, reserves and squad icons.
- **Layout:** position, radius, arc span, thickness, scale, text size, alignment
  and opacity. Coordinates use a 1920×1080 design space.
- **Weapon settings:** independent fire-mode, ammunition, zeroing and rate-of-fire
  icons, with position and size controls.
- **Reserve row:** quantity-symbol visibility, size, spacing and count placement.
- **HP and stamina row:** combined row visibility, text height and placement.
- **Animation:** reload-progress visibility and visual smoothing. Reload visibility
  remains available as a normal display/safety control.

## Release-menu cleanup

Development diagnostics, channel probes, internal status display, manual data
overrides, scan-budget tuning, body-search tuning and automatic-reader test
switches are not registered in the player menu. Fixed internal limits replace
the development tuning controls. Saved values for removed controls are ignored;
the mod does not erase or rewrite the player's settings file.

The combined HP/stamina row has a single visibility control; an old information
overlay toggle cannot force it back on. Unknown magazine capacity is not supplied
from a hidden manual override.

## Safety

Removing development controls does not remove Chef's native-read protection.
Errors or unavailable channels hide dependent displays. The mod keeps concise
safety/error messages in its log, not a player-facing diagnostic overlay.
