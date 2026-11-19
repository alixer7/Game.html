# NOVA BOT — PROGRESS / HANDOFF (v0.2)

Astro-Bot-style 3D platformer for phones. Godot 4.4+ (tested on 4.7 + Jolt), GDScript only, everything procedural
(meshes + shaders + generated WAVs). Landscape 1920x1080 base, Arabic UI.

## Status
- v0.2 was run in Godot 4.7 (headless import + Xvfb/lavapipe Vulkan rendering). All 5 levels load with no script or
  shader errors in Forward+, Mobile and Compatibility renderers.
- Exercised in-engine with scripted inputs / dev hooks: punch combo on crates (physics debris + gem spray + collection),
  enemy wrecks, battery drain -> reserve -> shutdown -> respawn, battery pickup swap sequence, turntable / lift / drum
  carrying the player, pylon puzzle solve -> switch bridge, push block sliding, toggles, boss phases.
- NOT verified: a full human play-through of every level start-to-finish, feel on a real phone, mobile performance.
  Hop distances are validated statically by tools/build_levels.py; timing-heavy spots may need tuning after play-tests.

## What changed since v0.1
- Robot: `robot_model.gd` rewritten (Geo meshes, spring-driven joints, LED face shader, back battery with clamps).
- Player: punch combo / air spin / charged spin / hover lasers / debris kicking / ice friction / wind; battery system
  (drain table at the top of player.gd), reserve + shutdown, `frozen` state for cutscenes.
- `battery_swap.gd`: cinematic swap timeline; `CameraRig.cinematic()` blends to a fixed shot.
- `debris.gd`: rigid-body chunks (layer 5 "debris"), box shatter, crate break, shards, mesh->parts, physical pickups,
  Carcass wreck for enemy deaths. Capped by quality (36 / 80 / 140 live pieces).
- Enemies rewritten (+ hopper, shield bot, spider, snowbot); projectiles can be punched back at the shooter.
- New objects: turn, retract, pend, drum, toggle, lift, crusher, sweep, icicle, wind, geyser, meteors, elec, swing,
  pylons, block, plate, gate, targets, wall, battery. See `level_loader.gd::_make` and the DSL in `tools/leveldsl.py`.
- Environment: `env_builder.gd` rewritten (5 themes incl. new "ice"), surface / rock / clouds / disk shaders, landmarks,
  floating-island undersides, breakable props (`EnvBuilder.Prop`), aurora + black hole in `sky_space.gdshader`.
- Levels: 5 levels (new L4 Ice Comet), each ~5.1-5.5 min estimated main route for a skilled player, 13-16 checkpoints,
  3 friends, 3 spare batteries. Estimator constants are in `Level.HOP_T` / `tm()` calls in leveldsl.py.
- Boss: 4 HP, armour plates break off physically, phase 2+ sweeping lasers, phase 3+ meteor summons.
- Audio: 37 new SFX + music_world4 / music_world5 (tools/make_audio.py --only=...).
- Menu: 5 level cards. Project: Forward+ on desktop, Mobile renderer on phones; physics layer 5 = debris.

## Conventions (unchanged + new)
- Tabs. No lambdas. Avoid `:=` with Variant RHS. Objects hold `var world: Node` and call it dynamically.
- Heading convention: JSON `yaw`/`dir`/`heading` in degrees, 0 = -Z, 90 = +X. `ry` = Godot rotation.y degrees.
- "hittable" group: `hit_radius`, optional `hit_offset`, `hit(by, kind) -> bool`; kinds: punch, punch3, spin,
  spin_big, dash, stomp, laser, reflect.
- Switch ids connect puzzles: `world.activate_switch(id, dur)` (0 = permanent) / `world.is_switch_on(id)`.
- `world.toggle_state` flips on every player jump (jump-switch platforms).
- Floor metadata `ice` on a collider makes the player slide.

## Next steps (suggested)
1. Full play-test of each level on a phone; tune timings (retract on/off, crusher per, meteor rate) and battery drain.
2. Performance pass on low-end phones (quality 0 already drops landmarks/props/particles; consider HLOD for dressing).
3. Robot skins unlocked by rescued friends; a hub world.
