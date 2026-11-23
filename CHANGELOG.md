# CHANGELOG

## 0.3.0 — 2026-11-23 (fixes from the first phone test)
### Screen & menus
- UI kept inside the device safe area (punch-hole/notch, rounded corners, nav bars), re-applied after the window rotates to landscape; adjustable "Screen edge margin".
- Pause and results panels were placed off-screen (top-left) — now centred in the safe area and scroll if too tall.
- Main menu, race setup and garage use responsive containers (16:9 … 21:9 phones, 16:10/4:3 tablets); touch controls laid out inside the safe area and sized so they never overlap on tall screens.
- Scroll areas tolerate small finger movement (taps no longer swallowed); touch-to-mouse emulation on.
- Android back gesture: steps back / closes settings / pauses — never quits mid-race; leaving the app pauses the race.
### Collisions & ground
- Kart collider rides 0.30 m above the ground with a step-up (≤ 0.36 m): seams, kerbs and merge lips are climbed, not walls.
- Roads blend into the terrain: skirts follow the ground (and collide where gentle), terrain fitted under and around every ground-level road, road aprons never carved, each road owns the ground under it, river bank lips follow the bank.
- Branch merges seated on the main road's real surface and bank; flume exit chute, shelf run-out and cave merge reworked so no raised layer overlaps a road.
- Every reachable tree, rock (sized from its mesh), stump and fallen log is solid; solid set pieces get exact colliders (except parts inside a road's driving corridor).
### Performance
- Trees 3–4× lighter at mid/far range, shorter LOD and shadow distances per preset, terrain/small props cast no shadows, larger terrain chunks and vegetation cells, all amber pickups in one shader-animated MultiMesh, wheels one draw each.
- Automatic 3D render resolution (600/720/900 px tall for Low/Medium/High) with FSR upscaling; MSAA and glow only on High; sky lighting only on High; phones default to Medium (old saved graphics settings reset once); FPS cap 30/60 with Android frame pacing.
- World built in stages with a progress bar (no frozen screen / "app not responding").
### Tests
- New `drive` suite (step scan, edge driving, junctions, collider audit) and `ui` suite (8 screen shapes × 3 cut-outs, every widget in the safe area, every button tapped; back gesture/backgrounding). All 84 checks pass.

## 0.2.0 — 2026-11-23 (session 2, first compiled & tested build)
### Toolchain
- Official Godot 4.7.2 + export templates (SHA-512 verified), Android SDK, debug keystore; all GDScript compile errors fixed.
### Physics
- Floating CharacterBody3D with its own ground ray/snap (no downhill speed bleed), hop clears the contact push, drag only when coasting.
- Collision capsule tilts with the ground normal (karts no longer stall on steep ramps).
### Track
- Jumps measured at 4 speeds × hop/no-hop and tuned (Giant's Log, Shelf Rock, Lower Falls, Tunnel Leap).
- Millrace Flume rebuilt: big-air kicker 20° off the road with a straight run-up, foot stamped into the ground, 22 m run-out, curved channel, earth chute onto the road (old exit was below the road).
- Rootway Cave rebuilt: tunnel inside the hairpin with a tight U-turn (hook-turn test); shell, terrain holes, stalagmites start at the real mouth; outer rock skin.
- River banks rejoin the road at shallow angles; mill house placed by road clearance.
- Terrain carve under elevated paths also clears road shoulders; road skirts have no collision (except in the cave).
- Lead-in guide paths from the road onto every side entrance.
### AI
- Lane graph with lead-ins, slide decisions by turn-ahead, hook when needed, lip-hops, stuck/lost/progress watchdogs with respawn → all 8 AI finish (Normal, Expert).
### UI
- Fixed: touch controls and settings panel had size 0 when anchored inside `_ready`; main menu buttons overflowed 720 px; garage stat bars coloured.
### Tests & tools
- Suites: physics 33, track 14, jumps 3 (40 attempts), ai 2, routes 26 — all pass. Route test checks each forced shortcut is driven to its end.
- Screenshot harness with render metrics, touch UI, view filter; menu screenshots; AI trace with forced routes; jump trace; `--smoke-race` for exported packs.
- APK exported and verified with apksigner.

## 0.1.0 — 2026-11-23 (session 1, unverified build)
### Added
- Project setup for Godot 4.7 (Mobile renderer, Jolt physics, 60 Hz physics, landscape, ETC2/ASTC).
- Kart physics core: heading/velocity split, momentum-conserving grip, power slides with 3 spark stages, boost reserve with Boost/Overdrive tiers, hook turn + hook boost, hop / lip-hop, air control, air boosts, landing quality, graded wall impacts, 12-surface table, flowing-water current.
- Track authoring tool (`tools/track_timberfall.py`) and the Timberfall Rapids layout: 1.5 km loop, 7 zones, river with 3 lanes, Lower Falls jump, Giant's Log + Ridge + Shelf Rock multi-stage shortcut, Woodcutter's Gate lane, Millrace Flume, Rootway Cave; map + elevation diagrams.
- Runtime world builder: spline roads with per-style cross-sections and walls, sculpted heightfield terrain with LOD chunks and holes, flowing water, set pieces and landmarks, gameplay objects, MultiMesh vegetation with LODs, environmental life.
- Procedural model library (trees, rocks, plants, props), karts and 8 original animal drivers.
- Stylized shaders: terrain splat, road, water, foliage (blob & card), triplanar rock/bark/stone, sky, boost pad, birds.
- Procedural texture library and synthesized audio + music.
- Racing lines, lane-graph AI with 4 difficulties, race manager, items, HUD, touch controls with layout editor, menus, settings, results.
- Headless test suites (physics, track, AI field, route timing) and a rendered screenshot/metrics harness.
- Android export preset; toolchain + build scripts; design documentation.

### Known
- Nothing has been compiled or run in Godot yet (engine download blocked in the build session).
