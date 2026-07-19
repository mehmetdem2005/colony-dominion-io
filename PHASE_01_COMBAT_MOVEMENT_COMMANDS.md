# Phase 01 — Combat, movement and command stabilization

Godot target: 4.6.3 stable / Mobile renderer

## Fixed

- Acid projectile ownership is stored as an ObjectID and resolved only at impact. A projectile no longer passes a freed attacker object into `take_damage`.
- Units now collide with enemy units and cannot walk through opposing armies.
- Allied units receive pairwise physics collision exceptions, so they do not block or slide the player commander.
- Commander movement no longer receives follower separation steering.
- Resource collection is now an explicit command. `KAYNAK` activates workers and assigns live resource targets.
- `TOPLAN` cancels worker gathering and recalls the whole army to the commander.
- `BÖL`, `DAĞIT/SIKILAŞ`, and `BİRLEŞ` are separate formation commands.
- Mobile command buttons were repositioned so they do not overlap the production panel or attack control.

## Map expansion programme

The current map remains at the validated size in this phase. Expanding the area by 100× means 10× width and 10× height. It will be implemented with streamed world chunks, deterministic chunk seeds, pooled props/resources, and AI simulation tiers. A single enlarged background image is explicitly avoided because it would cause memory spikes, blur, and visible repetition on mobile.
