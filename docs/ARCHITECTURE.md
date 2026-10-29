# Architecture

[简体中文](ARCHITECTURE.zh-CN.md) · [Documentation index](INDEX.md)

## Runtime flow

```text
Chef update -> bounded native sampling -> identity -> signal provider -> model
            -> reusable drawing commands -> Chef render
```

Native sampling normally runs at up to approximately 20 Hz. Model evaluation
and visual interpolation use the latest cached samples between native reads.

## Modules

| Module | Responsibility |
|---|---|
| `src/native.lua` | Guarded engine calls, per-sample caches and lifecycle reset |
| `src/runtime.lua` | Identity, signal integration, capacity bounds and animation samples |
| `src/draw.lua` | Arcs, independent icons, reserve row and rendering interpolation |
| `src/options.lua` | Editable controls; existing saved settings take priority |
| `src/main.lua` | Update/render/shutdown separation |
| `config/published_visual_defaults.json` | Approved 1920×1080 option defaults |

## Display behavior

Consumables use declared scalar fields on the typed local avatar within the
existing 20 Hz poll. Counts clear on lifecycle changes; SVGs become textures at
build time, with no runtime SVG parsing or new object scan.

Known reload rigs keep precedence. Without a rig, a declared positive reload
stage gates the validated local-body layer 11; runtime elapsed/length supplies
progress. Charge candidates no longer depend on heat candidates. Missing heat
maxima stay hidden until an actual overheat supplies an object-scoped reference.
Only reviewed charge/heat types without reload stages or rigs are cooldown-only.

HP and stamina share one text row whether armed or unarmed. Energy charge uses
the right inner arc; the outer arc shows cooling readiness. Ammunition settings,
rate-of-fire settings, reserves, stims and grenades share a left-anchored compact
row. Locked mode uses fixed priority (stims, grenades, zeroing, ammo, RPM,
magazines, fire mode) with vacant items removed. Unlocked mode anchors each item
to its own stored X/Y, independent of other items. Zeroing uses authored/scope
capability and live selection. Missing metadata may be supplemented by a defined
non-default selection as object-scoped proof; zero bits alone cannot. Explicit
scope removal or conflicting metadata invalidates the proof. Backpack geometry uses direct Ring layout controls and
shared opacity/track behavior, rather than automatic-zero or multiplier modes.

Information-row geometry uses build-generated alpha bounds to crop UV padding
without changing the source textures or the natural visible glyph scale. Row
advance and draw width use the same bounds. Text aligns by its quantized pixel
height. The row's horizontal anchor is independent of HP/stamina text placement.

For animation-driven reloads, the held weapon's animation state gates a valid
local-body animation layer. Animation elapsed time and clip/tail/base values
supply the normalized progress. A short rendering-only interpolation smooths
samples without replacing them with a fixed reload timer. The fill is white.

## Lifecycle and performance

- Invalidate engine handles and related visual state on world or character changes.
- Revalidate the held object's type, carry/binding and hand attachment independently
  of ownership-list churn or temporary list failures. Pack loss does not clear a valid hand.
- Client host-owned equipment requires a declared matching local owner and stays
  inside the discovery budget; player/avatar identification remains local.
- Hide stale or unavailable channels instead of inventing values.
- Treat zero health, empty magazines and zero reserves as valid samples when fresh.
- Nonreloadable weapon declarations suppress inapplicable reserve commands without
  suppressing loaded ammo; zero reserve remains valid for reloadable weapons.
- Bound new-type discovery by a count limit and a soft time budget.
- Retain freshly validated known relevant candidates independently from the rotating
  discovery slice; prioritize the previous hand/pack, include known competitors,
  and cap additional known-candidate validation at 64 per pass. Only identities
  are retained: dynamic ammo values are always freshly sampled.
- Reuse per-sample reads and drawing containers; interpolation does not call the engine.
- Static graphs rebuild only on new native samples; active heat/charge evaluation
  remains per-frame and reload smoothing remains in rendering.
- Cache row geometry until input/settings changes; text widths use a bounded
  256-entry cache with a one-second lifetime to recover after loader font changes.
  Consumable and layout tables are reused; no image analysis runs in-game.
- Never own or destroy private native GUI handles.

The public product is **HUD Lite by Alpha F. Bloodfallen**. The active addon
identifier is `mods/alpha_f_bloodfallen/hud_lite`; embedded fragment paths share
that namespace and the log is `hud_lite.log`. Option keys remain `hud.lite.*`.
A read-only check honors Chef's own skip and suspect records for this resource
before every native call; no Loader file is ever written or cleared.

Options register once in eleven sections. Chef 1.4 draws each section as a
foldable heading (spec.heading); older loaders fall back to searchable label
prefixes. Saved keys remain unchanged; no fake headings or unsupported menu APIs
are used. Language follows the loader: a supplementary lang/zh_cn.lua pack
merges into the official Simplified Chinese pack, so labels and headings switch
with the loader language.
