# Phase 04.5.3 — North World Depth Fix

## Root cause confirmed from the recording

The disappearance was not camera culling, chunk unloading, HUD occlusion, or unit pooling.
Units used a world-Y-derived Z value while the streaming ground lived at an effective Z of
approximately -210. Moving north reduced the unit Z until the full ground polygon rendered
in front of the colony. This occurred near the same world-Y boundary for every unit, which
is why the colony vanished together around the fifteenth second.

## Production correction

A single `WorldDepthPolicy` now owns all world-space render ordering:

- Ground root: reserved fixed bottom band.
- Flat decals: above ground, below gameplay actors.
- Props, resources, nests, units, and projectiles: one monotonic Y-depth domain.
- Stable unit sublayers: deterministic ordering without alpha flicker.
- Projectiles: same scale as units instead of the old incompatible `Y / 8` formula.
- Streaming and legacy world generation: identical depth rules.

The new regression test samples the entire playable north-south range and the recorded old
failure boundary to ensure no actor can cross behind the ground again.
