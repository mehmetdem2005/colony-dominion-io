# Phase 04.5.1 — Godot 4.6.3 Compile Hotfix

## Fixed

- Corrected the missing indentation under `if is_instance_valid(camera_anchor)` in `match_controller.gd`.
- Changed `WorldStreamManager` from `Node` to `Node2D`, so world-space physics access is valid and stale Phase 04.4 copies cannot fail on `get_world_2d()`.
- Added an explicit enabled V-Sync project setting for mobile devices that reject disabled V-Sync.
- Added `phase_04_5_1_compile_smoke_test.gd`, which loads the critical gameplay scripts, HUD, minimap, and both match scenes.

## Clean installation

Do not extract this archive into the old project with “skip existing files” enabled. Delete the old project directory first, or select overwrite/replace for every existing file.

## Engine validation

```bash
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/phase_04_5_1_compile_smoke_test.gd
```
