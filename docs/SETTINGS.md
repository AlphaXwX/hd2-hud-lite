# Settings Guide

[简体中文](SETTINGS.zh-CN.md) · [Documentation index](INDEX.md)

Open Chef's **F9** menu and select **HUD Lite 1.0.3**.

## Menu sections

Options register once, in order, under eleven section headings. Chef 1.4 draws
them as foldable headings above the first row of each section; loaders without
that capability fall back to searchable `[01 Display]`-style label prefixes, so
the menu stays navigable everywhere. No fake heading controls and no loader
modifications are used.

| Heading | Settings |
|---|---|
| DISPLAY | HUD visibility, opacity, scale and idle brightness |
| RING LAYOUT | Ring position, radii, widths, span, tracks and smoothing, including backpack |
| VITALS | Health/stamina rings and combined text |
| AMMUNITION | Ammo ring and center number format, size and offsets |
| WEAPON ROW | Unlock, anchor, extra X offset, vertical placement and gap |
| FIRE AND AMMO ICONS | Visibility, sizes and unlocked positions |
| ZEROING AND RPM | Visibility, sizes and unlocked positions |
| RESERVES | Count position, size, magazine symbol and internal spacing |
| STIMS AND GRENADES | Visibility, unlocked positions and shared sizes |
| SQUAD | Own and teammate boosters |
| ANIMATION | Reload visibility and smoothing |

## Language

The mod follows the loader's language. When Chef's language is set to Simplified
Chinese, the mod ships a supplementary language pack (`lang/zh_cn.lua`) that is
merged with the official Chinese pack, so option labels and section headings
appear in Chinese. With any other loader language the labels stay as authored;
no separate in-mod language switch is needed.

Original option IDs and saved values are retained. The former separate
consumables-row X/Y settings are ignored, not deleted. Coordinates use a
1920×1080 design space.

## Compact weapon row

The row is **locked by default**. Visible items flow left to right in a fixed
priority: **stims → grenades → zeroing → ammo/function → RPM → reserve magazines
→ fire mode**. Hidden, unavailable or unmapped icons leave no
hole; one item starts at the row's left edge. The gap is measured between visible
icon/count edges, not the square texture tiles. Transparent atlas/SVG padding is
excluded with build-time UV bounds; the original art and natural apparent size
are preserved. Quantity text uses the loader's measured width and actual pixel
height. Backpack reserve is one item, not a duplicate.

`hud.lite.row_x`, `hud.lite.fire_y` and `hud.lite.row_gap` adjust the whole row.
`hud.lite.row_x` offsets the row's left edge from the fixed approved origin.
It no longer adds the live `hud.lite.info_x`, which now moves only HP/stamina text.
The approved default origin remains -84 design units from the cluster center,
or the game-HUD anchor when selected. The saved row X offset remains additive
and is not overwritten or reinterpreted. `hud.lite.fire_y` moves the
information row vertically without moving the vitals row.
While locked, individual X/Y values do not affect placement; icon sizes and
row spacing still apply. Enable **Unlock information row** (`hud.lite.row_unlock`)
to place each item independently. In unlocked mode, each item's X/Y is measured
directly from the common row origin, not from a dynamic slot. Missing items,
visibility changes and wider quantities cannot shift another item's position.
Relocking restores compaction without deleting manual positions. Saved X/Y
values are reused only while unlocked. Both modes support the crosshair and
game-HUD anchors.

Stims use `cura`, grenades use the supplied grenade art, both within this row
and available while unarmed. Fresh zero counts display; invalid/unavailable
readings hide. Zeroing uses authored weapon data or a recognized scope attachment
when available. If attachment metadata is unavailable, a defined non-default
live zeroing selection can establish support for the current weapon object.
Returning that object to the lowest setting keeps the icon; a missing selection,
explicit scope removal, conflicting metadata, weapon change or lifecycle reset
does not retain a stale icon. Zero bits alone never establish support.
Nonreloadable/supply-only equipment is excluded from this selection-only fallback.
If capability metadata and a non-default selection are both unavailable, the
initial lowest-setting icon remains hidden rather than being guessed.

## Backpack ring

The default remains the third right-hand ring. Its controls are now in **02 Ring
layout**, using the same direct design-unit sliders as the other rings:
`backpack_x`, `backpack_y`, `backpack_radius`, `backpack_thickness` and
`backpack_span`, prefixed with `hud.lite.`. X is relative to screen center; Y uses
the same design-coordinate origin as the main ring's Y slider (not a relative
offset from that ring). Radius, width and span are actual values, not zero/auto
modes. Defaults are X **0**, Y **538**, radius **168.5**, width **3.5**, span **73**.
Scaling, opacity and background-track visibility use the shared controls.
There is no separate backpack category, rotation, opacity multiplier or track
switch. Old values for those removed controls are ignored, not erased. Existing
backpack position/radius values use the new direct-slider meaning; adjust them
in Ring layout if they came from the old relative/automatic setup.
Changing backpack geometry does not change health, ammo or reload geometry.

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

Right outer ring: ammo/cooling. Right inner ring: actual reload or known charge
progress. Third right ring: backpack resources. Cooldown-only charge/heat weapons
and declared nonreloadable weapons hide spare magazines, including a shared
counter reporting zero. Loaded ammunition remains visible. Single-shot weapons
with a real reload stage/rig and reloadable heat weapons retain true zero reserves.
Unknown heat maxima
are not assumed to be 100: an actual overheat can establish an object-scoped
reference. Missing heat ranges or unknown charge durations stay hidden.

Removing development controls does not remove Chef's native-read protection.
Errors or unavailable channels hide dependent displays. The mod keeps concise
safety/error messages in its log, not a player-facing diagnostic overlay.

## Single-player and multiplayer equipment

Large combat object lists are processed in rotating discovery windows. Already
identified, currently relevant equipment is freshly type/ownership-validated
before new-type discovery, so leaving that rotating window does not remove a
valid weapon from the current candidate list. Known same-grip rivals are included
too; unresolved ambiguity is not converted into a guessed selection. New-type
checks retain their count/time budget. Loaded ammo is read live, never restored
from an old ammunition snapshot. This applies in single-player as well as co-op.

A retained hand is freshly checked for type, carry/binding, owner when readable,
and attachment to the local body's wield node. Unrelated object-list changes,
temporary list failures and missing backpack updates no longer force full hand
rediscovery while that independent proof remains valid. Actual ammo is still
read each poll; previous counts are not frozen to hide read failures.

On a client, host-owned equipment is considered through bounded candidate scans.
Its declared owner must match the local peer. The host's player/avatar is never
used as a local substitute. Ambiguous or unavailable ownership proof, missing
engine reads and unknown types can still hide dependent displays. These paths
need in-game verification; mock tests are not a multiplayer guarantee.
