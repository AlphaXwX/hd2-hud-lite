# Identity

[简体中文](IDENTITY.zh-CN.md) · [Documentation index](INDEX.md)

## Active identity

- Product and F9 menu: **HUD Lite 1.0.0**.
- Author: **Alpha F. Bloodfallen**.
- Addon resource: `mods/alpha_f_bloodfallen/hud_lite`.
- Chef performance-monitor entry: **hud_lite**.
- Log: `hud_lite.log`.
- Option keys: `hud.lite.*`.

Chef derives the monitor name from the final resource-path segment, not the F9
title. The resource declaration and its archive hash are published together, and
embedded rule-fragment references use the same namespace.

## Installation

1. Install Chef Shared Loader 1.2.3 or newer.
2. Disable other HUD mods that draw the same elements.
3. Import and deploy `HUD-Lite-1.0.0-Chef.zip`.
4. Open the F9 menu and select **HUD Lite 1.0.0**.

This is the first public release of the addon, so no earlier installation of this
resource exists to convert. Remove any other HUD mod before deploying, and
restart the game after a package change.

## Saved settings

Option keys are stable, so saved values keep working between versions. The
author-tuned 1080p preset in `config/published_visual_defaults.json` only fills
option defaults at registration; a saved player value always wins over it.

## Native-call protection

Before every engine call the mod checks Chef's own skip and suspect records for
this resource, read-only. If the record file cannot be read at all, the risky
batch and animation channels fail closed instead of being retried. The mod never
writes Loader files and never clears a record; do not delete safety records just
to make a display appear.
