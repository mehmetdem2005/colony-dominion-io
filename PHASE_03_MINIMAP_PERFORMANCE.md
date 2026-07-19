# Phase 03 — Minimap and Large-Army Performance

## Root causes found

The slowdown was not caused by the ant PNG files. It came from per-unit CPU work that grew rapidly as the army expanded:

1. `get_formation_position()` rebuilt same-role arrays by scanning the whole colony for every unit on every physics tick.
2. Friendly separation scanned the whole colony for every follower on every physics tick.
3. Every target refresh scanned every unit in every enemy colony.
4. Friendly units used pairwise physics collision exceptions, creating thousands of exception relationships at high population.
5. Stationary units still called `move_and_slide()` every physics tick.
6. The leaderboard recreated Label nodes repeatedly, match time emitted every frame, and AI nests emitted production progress every frame.
7. World streaming could retain up to 49 decorated chunks around the player.
8. Acid projectiles were allocated and freed continuously.

## Production fixes

- Added `UnitSpatialIndex`, rebuilt at 8.3 Hz with 256 px cells.
- Enemy target lookup now checks only nearby spatial cells.
- Friendly separation is spatially queried and cached per unit for 120–200 ms.
- Formation slots are cached and rebuilt only when units spawn, die, split, merge, or change spacing.
- Each colony uses a dedicated physics layer. Friendly units no longer need collision exceptions and cannot push the commander.
- Enemy colonies remain mutually collidable.
- Stationary units skip physics movement calls.
- Reduced simulation units update at 8.3 Hz and use explicit delta movement.
- Dormant enemy colonies remain macro-simulated without active unit physics.
- Active streaming radius is 3×3 chunks; Faz 04.1 ile yön tahminli WARM önbellek dâhil toplam resident sınırı 18 chunk olarak uygulanır.
- Acid projectiles use an object pool.
- Match timer updates once per second.
- Leaderboard rows are reused instead of destroyed and recreated.
- Only the player's nest emits production progress UI events, throttled to 10 Hz.

## Minimap

The minimap is a lightweight `Control._draw()` implementation. It does not create a second camera or SubViewport and therefore does not render the world twice.

It updates at 5 Hz and displays:

- full 36,000×24,000 world bounds,
- loaded streaming chunks,
- every active colony nest,
- every active commander and army-size marker,
- the player's current camera rectangle.

## Main new files

- `gameplay/performance/unit_spatial_index.gd`
- `ui/minimap.gd`

## Modified systems

- `gameplay/match/match_controller.gd`
- `gameplay/units/unit.gd`
- `gameplay/colony/colony_controller.gd`
- `gameplay/colony/nest.gd`
- `gameplay/combat/projectile.gd`
- `gameplay/world/world_stream_manager.gd`
- `gameplay/world/streamed_world_prop.gd`
- `gameplay/economy/resource_node.gd`
- `gameplay/world/camera_controller.gd`
- `ui/hud.gd`
- `project.godot`
