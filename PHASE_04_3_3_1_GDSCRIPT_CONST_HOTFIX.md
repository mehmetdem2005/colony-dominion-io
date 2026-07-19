# Phase 04.3.3.1 — Godot 4.6.3 GDScript Constant Hotfix

## Root cause

Godot 4.6.3 requires constant values to be valid compile-time expressions. The audio event catalog and regression test used `PackedStringArray([...])` constructor calls in `const` declarations. Those constructor calls were rejected as non-constant expressions, preventing `AudioEventLibrary` and its dependent `AudioSystem` autoload from compiling.

## Fix

- Replaced `AudioEventLibrary.EVENT_PATHS` with a typed array literal: `const EVENT_PATHS: Array[String] = [...]`.
- Replaced `REQUIRED_MUSIC` and `REQUIRED_AMBIENCE` in the audio regression test with typed array literals.
- Preserved all 27 audio event paths, 51 SFX references, 6 music stems, and 5 ambience stems.
- Re-ran static parsing/lint checks across all 48 GDScript files.

## Validation result

- Reported constant-expression parse errors: resolved.
- External class member `AudioEventLibrary.EVENT_PATHS`: resolvable after the source class compiles.
- Missing audio event resources: 0.
- Missing SFX stream references: 0.
- Blocking parser/linter findings: 0.
- Existing non-blocking line-budget findings: 2 (`colony_controller.gd`, `world_stream_manager.gd`).

The Godot executable was unavailable in the build container, so the included headless test was not executed here.
