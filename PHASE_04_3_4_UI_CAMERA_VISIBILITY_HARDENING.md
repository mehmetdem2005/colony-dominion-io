# Phase 04.3.4 — UI, Camera and Swarm Visibility Hardening

## Video findings

Two Android editor recordings were reviewed frame-by-frame:

- `Screenrecorder-2026-07-18-22-52-28-810.mp4` — 16.308 seconds.
- `Screenrecorder-2026-07-18-22-52-48-653.mp4` — 7.110 seconds.

The disappearance and fog-like flash were separate faults.

### 1. Swarm disappearance while moving north

The old camera moved its center **ahead** of commander velocity. When the commander moved north, the commander and the trailing formation were pushed toward the bottom of the screen. The units remained alive and in FULL simulation, but the opaque production dock covered them. Camera smoothing made the transition look sudden.

### 2. Blue/grey fog and flicker in dense formations

Every non-commander ant drew two complete circles. Although the ring colors were nominally opaque, anti-aliased edge pixels were translucent. When units overlapped and their depth order changed, hundreds of edge pixels accumulated and produced a fog/moire flash.

Two additional time-dependent visual sources were found during the broader UI audit:

- The minimap player marker used a stepped sine pulse while the map only redrew at 8 Hz.
- Minimap chunk tiles changed large-area alpha between warm and active states, and disappeared when unloaded.
- Resource focus markers used a translucent sine pulse.

## Production fixes

### HUD-aware formation camera

`PlayerCameraController` now uses a HUD-safe gameplay rectangle supplied by `ColonyHUD`.

- The commander is biased **toward the movement direction on screen**, leaving room behind it for the following swarm.
- Framing direction is low-pass filtered to avoid steering jitter.
- The camera reads the actual rendered center through `get_screen_center_position()` when producing the minimap view rectangle and when checking smoothing drift.
- Camera limits now match the authored world bounds directly instead of being expanded by half a viewport.
- Limit smoothing is disabled; position smoothing remains enabled.
- Zoom and viewport changes immediately recompute the safe framing solution.

### Stable low-overdraw unit markers

- Normal units use four short opaque segments instead of two complete circles.
- Anti-aliasing is disabled on dense world-space markers.
- Only commanders retain a complete ring.
- Commander ticks and squad markers are static and fully opaque.
- Damaged-unit health bars are fully opaque.

This reduces marker coverage by roughly sixty percent before overlap and removes order-dependent alpha accumulation.

### Stable minimap

- Discovered chunks remain cached for the duration of the match.
- Active/warm state uses a border change rather than a large fill-alpha jump.
- The player marker no longer pulses.
- The camera viewport is outline-only; the former translucent white fill was removed.
- The minimap uses the camera's actual rendered center instead of its smoothing destination.

### Responsive mobile HUD

- Resource dock, minimap, audio control, timer, leaderboard, production dock, joystick, commands and modal panels are laid out from the current logical safe area.
- Android/iOS display cutouts are converted into logical viewport coordinates.
- UI scales down to a controlled minimum for smaller landscape viewports.
- `canvas_items` stretch is retained and stretch aspect is set to `expand`.
- Production and right-side command controls are explicitly separated.
- The camera bottom inset is derived from the production dock's actual layout.

### Modal and multi-touch isolation

- A fully transparent, full-screen input blocker is enabled for audio settings and game-over states. It does not draw a fog overlay.
- Joystick, command buttons and production cards have a separate interaction gate.
- Opening a modal releases captured touches and emits zero joystick movement.
- Custom controls reject already-handled input and preserve ownership only for touches they captured.
- Audio settings now have an explicit close button.

### Resource focus marker

The time-driven translucent focus pulse was replaced by static opaque segments, removing another source of temporal alpha flicker.

## Changed runtime files

- `gameplay/world/camera_controller.gd`
- `gameplay/units/unit_visual.gd`
- `gameplay/economy/resource_node.gd`
- `gameplay/match/match_controller.gd`
- `ui/hud.gd`
- `ui/minimap.gd`
- `ui/virtual_stick.gd`
- `ui/touch_action_button.gd`
- `ui/production_touch_card.gd`
- `project.godot`

## Regression test

```bash
godot --headless --path . --script res://tests/ui_camera_visibility_regression_test.gd
```

The test checks camera movement-direction framing, safe-frame containment, resource/minimap separation, production/command separation, modal joystick release, and audio panel state.

## Device acceptance sequence

1. Move north continuously for at least 20 seconds with a full formation. Commander and followers must remain above the production dock.
2. Reverse north/south direction repeatedly. Camera framing must transition without a one-frame jump.
3. Stack at least 40 friendly units. Team markers must not form a blue/grey fog or blink as units cross.
4. Cross several chunk boundaries while watching the minimap. Previously discovered terrain must not disappear or flash in opacity.
5. Open audio settings while holding the joystick. Movement must stop immediately and no command behind the panel may fire.
6. Repeat at minimum zoom, maximum zoom, 16:9, 18:9 and a notched Android safe area.
