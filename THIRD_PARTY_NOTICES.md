# Third-Party Notices

[简体中文](THIRD_PARTY_NOTICES.zh-CN.md) · [Documentation index](docs/INDEX.md)

**HUD Lite 1.0.0** is maintained by **Alpha F. Bloodfallen**.
That credit covers HUD Lite's own work, not third-party contributions.

## Independence

HUD Lite's implementation, drawing code and build tools were written
independently for this release. Other HUD mods for the same game informed the
feature set and the interface conventions only; they are not part of this
codebase and no attribution for their implementation is claimed or required.
Shared, game-derived data (object hashes, field names and icon indices) is
recorded in `config/` and remains game content under the terms below.

## Artwork credit

The quantity symbol and the icon/texture pack used by local builds come from the
community Helldivers 2 wiki and are credited **Dogo314**. Preserve that credit
and confirm appropriate redistribution permission. The extracted pack lives in
`assets/icon-pack/`, is a local build input, and is excluded from the public
source export. User-supplied images and other artwork remain subject to their
respective rights holders' terms.

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
