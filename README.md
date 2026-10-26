# HUD Lite

**1.0.0 · Alpha F. Bloodfallen**

[简体中文](README.zh-CN.md) · [Documentation index](docs/INDEX.md)

A configurable in-game HUD mod for Helldivers 2. Requires **Chef Shared Loader
1.2.3 or newer**, installed separately.

## Features

- HP and stamina remain visible with or without a held weapon.
- Ammo, magazine capacity, reserve ammunition and supported backpack gauges.
- Energy charge on the right inner arc and cooling readiness on the outer arc.
- A smooth white reload arc driven by sampled animation progress.
- Independent fire mode, ammunition setting, zeroing and rate-of-fire icons.
- Booster and death icons for the local player and up to three teammates.
- A magazine symbol beside the reserve count, with independent size and spacing.
- Author-tuned 1080p defaults, resolution scaling and editable F9 options.
- Existing saved preferences take priority over release defaults.

## Install

1. Install **Chef Shared Loader 1.2.3+**.
2. Disable other installations of this mod and conflicting HUD mods.
3. Import and deploy `HUD-Lite-1.0.0-Chef.zip` with your mod manager.
4. Open Chef's **F9** menu and select **HUD Lite 1.0.0**.

The active loader identifier, performance-monitor name and native-call
protection are described in the [identity notes](docs/IDENTITY.md).
Re-deploy and restart the game; an already loaded mod cannot change its monitor ID in place.

Do not delete Chef's safety-state file to force a refused engine read to run.

## Configure

The F9 menu controls arc geometry, text placement, opacity, independent setting
icons, reserve count and symbol, booster display and animation smoothing.
Positions and sizes use a **1920×1080 design coordinate system** and scale to
other resolutions. This does not change the game's display resolution.

If a data channel is unavailable or stale, its dependent display is hidden
rather than replaced with a fabricated value. Known empty ammunition and zero
reserves remain valid readings.

## Build and test

Requirements: **Python 3.11+** and **Node.js 20+**. The build needs no downloaded
inputs; see [the build guide](docs/BUILD.md) for rebuilding the icon pack.

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements-dev.txt
npm ci
.venv\Scripts\python tools/build.py --source-only
.venv\Scripts\python tests/verify.py
.venv\Scripts\python tests/verify_icon_assets.py
.venv\Scripts\python tests/benchmark.py
.venv\Scripts\python tests/verify_release.py
.venv\Scripts\python tests/verify_docs.py
.venv\Scripts\python tools/build.py
.venv\Scripts\python tests/verify.py dist/HUD-Lite-1.0.0-Chef.zip
.venv\Scripts\python tests/verify_release.py dist/HUD-Lite-1.0.0-Chef.zip
```

On Linux or macOS use `.venv/bin/python`. Do not commit `local.config.json`.

## Repository layout

| Path | Purpose |
|---|---|
| `project.json` | Product name, version, author and manager description |
| `src/` | Runtime, native access, options and drawing modules |
| `tools/` | Local import, assembly, validation and packaging tools |
| `tests/` | Lua regression, image, package and documentation checks |
| `config/` | Published visual defaults and verified field/icon mappings |
| `docs/` | English and Simplified Chinese documentation |
| `external/` | Ignored landing area for optional local package imports |
| `assets/` | Icon pack, magazine symbol and preview image, shipped with the sources |
| `build/` | Ignored generated code, patch files and manager metadata |
| `reports/` | Ignored test, benchmark and verification reports |
| `dist/` | Ignored installation and source packages |

## Source export

```powershell
.venv\Scripts\python tools/check_repository.py
.venv\Scripts\python tools/export_source.py
```

The source ZIP uses an explicit allowlist. It excludes local input files,
artwork, generated code, game-derived material, dependency installations,
personal paths, local settings and test logs. The tools do not upload to GitHub,
run `git push` or publish releases.

## Validation and safety

- The test harness runs real Lua 5.1 with a mocked game engine.
- Mock timing results are **not game FPS or real native-call timings**.
- No game-session validation was performed for this release.
- Native engine calls can still crash the game. Lua `pcall` cannot contain a
  native access violation.
- Engine reads occur at a bounded sampling rate; drawing interpolation does
  not perform extra native reads.
- The active Loader identifier is `mods/alpha_f_bloodfallen/hud_lite`; Chef's
  performance monitor therefore lists **hud_lite**. Saved player values take
  priority over the release defaults. See the [identity notes](docs/IDENTITY.md).
- There is no FFI, arbitrary memory access or modification of game data files.

## License and notices

HUD Lite's own implementation and build code are covered by [LICENSE](LICENSE).
Other included or locally imported material retains its own terms. Required
credits and distribution boundaries are centralized in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
