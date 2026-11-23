# CHANGELOG

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
