# Build Guide

[简体中文](BUILD.zh-CN.md) · [Documentation index](INDEX.md)

## Prerequisites

- Python 3.11 or newer, Node.js 20 or newer.
- Python packages from `requirements-dev.txt` and Node packages from the lockfile.
- Redistribution permission appropriate to any material you intend to publish.

## Inputs

A normal build needs no downloaded inputs. The runtime, layout data and icon
pack are all part of the repository:

| Path | Contents |
|---|---|
| `src/` | Runtime modules composed into the single Lua addon |
| `config/` | Layout, fragment, mapping and default-value data |
| `assets/icon-pack/` | Textures, resources, magazine symbol and preview image |

Local inputs are only needed when you rebuild the icon pack from a resource
archive you own:

| Configuration key | Build role |
|---|---|
| `runtime_package` | Resource archive the pack is extracted from |
| `icon_package` | Icon definitions used to verify the booster mapping |
| `quantity_icon_svg` | Vector artwork for the reserve-count symbol |
| `preview_image` | Mod-manager preview image |

```powershell
# Optional: import the packages you own into the ignored external/ directory.
Copy-Item local.config.example.json local.config.json   # then edit the paths
.venv\Scripts\python tools/import_inputs.py --config local.config.json

# Rebuild the icon pack from an imported archive.
.venv\Scripts\python tools/extract_assets.py --package external/lite/<imported resource archive>
```

Archives are extracted to ignored local directories and the importer rejects
entries that escape their destination. It does not edit installed game files,
access a game process or upload anything. Never commit `local.config.json`.

## Build phases

1. `project.json` supplies display metadata and version **1.0.0**.
2. Image preparation validates mappings and renders the quantity symbol.
3. `src/` modules, generated layout data and feature fragments are composed into
   `build/hud_lite.lua`.
4. `tools/build.py --source-only` writes the native patch, preview and manifest.
5. Run the Lua, image, benchmark, release and documentation checks listed in the README.
6. `tools/build.py` checks report hashes and creates `dist/HUD-Lite-1.0.0-Chef.zip`.
7. Run the Lua and release checks against the ZIP to verify the actual packaged output.

The manager manifest's `Version: 1` is its **schema version**, not the mod's
semantic version. The product, Lua module and archive name carry **1.0.0**.

## Published defaults

`config/published_visual_defaults.json` is an approved 1920×1080 design preset.
It changes option registration defaults only. Builds do not capture live user
preferences, and startup does not reset saved settings.

## Preview and image preparation

The preview is converted to RGBA PNG without cropping, drawing text over it or
changing its dimensions. The manager receives it as `icon.png`.
The quantity symbol is rasterized during the build, not during gameplay.

## Source export and CI

```powershell
.venv\Scripts\python tools/check_repository.py
.venv\Scripts\python tests/verify_docs.py
.venv\Scripts\python tools/export_source.py
```

The exporter includes only the source allowlist and both documentation languages.
It excludes generated output, test reports and dependency installations. The icon
pack is distributed with the repository but stays out of the source ZIP; review
the resulting archive before uploading it.

CI runs the repository, documentation and Lua checks, and builds the addon from
the committed sources. It does not upload or publish an installation package.
