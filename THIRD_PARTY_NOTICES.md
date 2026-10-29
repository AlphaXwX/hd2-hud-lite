# Third-Party Notices

[简体中文](THIRD_PARTY_NOTICES.zh-CN.md) · [Documentation index](docs/INDEX.md)

**HUD Lite 1.0.3** is maintained by **Alpha F. Bloodfallen**.
That credit covers HUD Lite's own work, not third-party contributions.

## NarrowHUD compatibility catalog

**Based on NarrowHUD by luka189.** Reviewed release:
https://github.com/luka189/NarrowHUD/releases/tag/v1.0.6

The compatibility catalog in `config/weapon_catalog.json` is adapted from that
project's network-type/field data and shipped observations. HUD Lite keeps its
own rendering and implements the integration in `src/compatibility.lua` and
`src/runtime.lua`. Its runtime modules, editor and artwork are not transplanted.

The complete applicable license is retained in
[third_party/COMPATIBILITY-LICENSE.txt](third_party/COMPATIBILITY-LICENSE.txt).
It permits free reuse and adaptation, requires credit and license retention,
and prohibits selling or paywalling the work or derivatives. Donations and
mod-site reward programs are allowed by that notice. These conditions apply
to a distribution containing this catalog; HUD Lite's MIT license does not
remove them. Do not describe the catalog as exclusively original code/data.

Other shared game-derived data remains subject to the game-content terms below.

## Artwork credit

The user-supplied `cura.svg` stim symbol and `Grenade_Currency_Icon.svg` grenade
symbol carry the credit **Traced by Dogo314**. Paths/viewBoxes are unchanged;
description metadata is centralized here. Attachment and asset hashes are in
`third_party/CONSUMABLE-ICONS-SOURCE.json`. These local inputs do not establish
additional redistribution rights beyond applicable artwork/game-content terms.

The quantity symbol and the icon/texture pack come from the community Helldivers 2
wiki and are credited **Dogo314**. Preserve that credit and confirm appropriate
redistribution permission. The pack lives in `assets/icon-pack/`, ships with the
repository, and stays out of the source export. User-supplied images and other
artwork remain subject to their respective rights holders' terms.

## Game content

Game-derived content belongs to Arrowhead Game Studios and its respective
rights holders. It is not relicensed by HUD Lite's MIT license and is excluded
from the public source export.

## Loader and development dependencies

- **Chef Shared Loader**, by Th3chef, is required separately:
  https://github.com/Th3chef/Chef-Shared-Loader
- **@resvg/resvg-js**: MPL-2.0; installed through the package manager.
- **luaparse**: MIT; installed through the package manager.
- **Pillow** and **lupa**: installed separately under their own licenses.

The loader and dependency implementations are not vendored into the source export.
