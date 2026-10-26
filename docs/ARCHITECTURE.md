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

HP and stamina share one text row whether armed or unarmed. Energy charge uses
the right inner arc; the outer arc shows cooling readiness. Ammunition settings,
rate-of-fire settings and reserve count have independent presentation anchors.

For animation-driven reloads, the held weapon's animation state gates a valid
local-body animation layer. Animation elapsed time and clip/tail/base values
supply the normalized progress. A short rendering-only interpolation smooths
samples without replacing them with a fixed reload timer. The fill is white.

## Lifecycle and performance

- Invalidate engine handles and related visual state on world or character changes.
- Hide stale or unavailable channels instead of inventing values.
- Treat zero health, empty magazines and zero reserves as valid samples when fresh.
- Bound new-type discovery by a count limit and a soft time budget.
- Reuse per-sample reads and drawing containers; interpolation does not call the engine.
- Never own or destroy private native GUI handles.

The public product is **HUD Lite by Alpha F. Bloodfallen**. The active addon
identifier is `mods/alpha_f_bloodfallen/hud_lite`; embedded fragment paths share
that namespace and the log is `hud_lite.log`. Option keys remain `hud.lite.*`.
A read-only check honors Chef's own skip and suspect records for this resource
before every native call; no Loader file is ever written or cleared.
