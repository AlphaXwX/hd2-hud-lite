# Changelog

[简体中文](CHANGELOG.zh-CN.md) · [Documentation index](docs/INDEX.md)

## 1.0.2

- Fixed single-player ammo loss when rotating discovery windows omitted already identified weapons in large object lists.
- Revalidate retained equipment before new-type discovery; include known competing guns rather than inventing uniqueness.
- Added large-list catalog/ADS regressions with changing live ammo, drop/removal checks and bounded-search stress cases.
- Added 400-object catalog and ADS benchmark scenarios to the timing report.

## 1.0.1

- Revalidate held weapons independently from unrelated ownership-list churn and delayed backpack updates.
- Added bounded client host-equipment discovery with declared local-owner validation, never a host-player substitute.
- Hide inapplicable magazine reserves on declared nonreloadable weapons, retaining loaded ammo and reloadable zero reserves.
- Restore valid live zeroing when scope metadata is unavailable; distinguish missing metadata from explicit removal.

- Corrected information-row spacing using visible icon UV bounds rather than transparent tile sizes.
- Decoupled the information-row X anchor from HP/stamina text and aligned counts by actual pixel height.
- Kept source artwork and natural glyph sizes unchanged; font-width cache refreshes after loader font changes.

- Default row priority is stims, grenades, zeroing, ammo type, RPM, magazines, then fire mode; absent items compact forward.
- Added information-row unlock: per-item X/Y positions no longer depend on missing icons.
- Zeroing now requires confirmed weapon/scope support, preventing false icons on unsupported weapons.
- Moved backpack controls into Ring layout using direct values and shared opacity/track settings.
- Categorized settings in eleven contiguous blocks; retained applicable saved keys and manual positions.
- Reduced static graph rebuilds, cached layout/text metrics and reused containers.

- Added actual body-animation reload fallback for catalog weapons without authored rigs.
- Separated charge progress from heat/cooling; a valid charge can render without a heat sample.
- Added supplied stim/grenade textures, declared quantity reads and display controls.
- Moved backpack resources to the third right ring; cooldown-only energy hides reserves.
- Hybrid heat weapons retain reload/reserves; unknown heat ranges require an observed overheat reference.

- Added reviewed weapon/field compatibility data.
- Fixed direct-backpack supply and backpack reserve reads with declared scalar fallbacks.
- Enabled nine additional verified-pose types and supplemental pose/type-name mappings.
- Added cold-adjusted authored RPM matching and catalog-supported static-heat charge timing.
- The NarrowHUD compatibility catalog is credited in the third-party notices; its license is retained in `third_party/`.

## 1.0.0

- Product name: **HUD Lite**; author: **Alpha F. Bloodfallen**.
- Requires Chef Shared Loader 1.2.3+; Chinese and English manager descriptions.
- Always-visible HP beside stamina and author-tuned 1080p visual defaults.
- Ammo, capacity, reserves, backpack gauges and energy charge/cooling display.
- Smooth white animation-driven reload arc.
- Independent weapon-setting icons and squad booster/death display.
- Quantity symbol beside reserves and a configured manager preview.
- Portable build tools, locked Node dependencies and source-only export.
- Functional, image, metadata, documentation and repository validation.
- Complete English and Simplified Chinese documentation with a paired index.
- Technical guides describe the current product without migration history.
- Player menu excludes development diagnostics, probes, manual overrides and internal tuning controls.
- Unified addon/fragment identity and performance-monitor name; native-call protection honors Chef's existing records.
- Required third-party notices remain centralized; public source export excludes private inputs.

No new in-game validation was performed for this release. Mock benchmarks are
not a claim about game FPS or native engine-call performance.
