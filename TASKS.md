# TASKS

Legend: ✅ done & verified · 🟡 written, unverified (needs Godot) · ⬜ not started · ⛔ blocked

## P0 — Toolchain
- ⛔ Download official Godot 4.7.2 editor + export templates (blocked: github.com/godotengine scope in the cloud session)
- ✅ Android SDK (cmdline-tools, platform-tools, build-tools 35.0.1, android-35) in the session
- 🟡 tools/setup_toolchain.sh, tools/build.sh

## P1 — Handling (phase 1)
- 🟡 Arcade kart controller with heading/velocity split, momentum-conserving grip
- 🟡 3-stage spark slides, fizzle/backfire, boost reserve, Boost/Overdrive tiers
- 🟡 Hook turn + hook boost; hop, lip-hop, air control, air boost, landing quality
- 🟡 Graded impacts; surface table; river current
- 🟡 Physics test suite (14 checks)
- ⬜ Tune against measured results

## P2 — Track (phases 2–3)
- ✅ Turtle authoring tool, closed 1.5 km loop, 7 zones, 7 branches, diagrams
- 🟡 Road mesher (styles, walls, collision per surface), terrain sculpting, water
- 🟡 Gameplay layer (rocks, pads, crates, amber, swinging log, flytraps, gate, chevrons, grid)
- ⬜ Blockout play-test + iteration with measured route times

## P3 — Environment (phase 4)
- ✅ Procedural texture library
- 🟡 Set pieces: aqueduct + portal, start gantry, Lower Falls, Moss Arch, Giant's Log, ridge, ruins + Guardian Owl, mill + flume + wheel, cave, Elder Tree, mountains, Skyveil Falls, watchtower
- 🟡 Scatter (6 tree types × 2 LODs, bushes, ferns, grass, flowers, mushrooms, reeds, lilies, rocks, stumps, logs), colliders near track
- 🟡 Life: birds, butterflies, leaves, fireflies, fish, mist, smoke, wind
- ⬜ Visual review via screenshots; density/perf tuning per quality preset

## P4 — Racing (phase 5)
- 🟡 Racing lines + speed profiles, lane graph, AI (4 difficulties), mild catch-up
- 🟡 Race manager: countdown + start boost, laps/sectors, positions, respawn, bumps, results
- ⬜ AI tuning with test data

## P5 — Items & UI (phase 6)
- 🟡 5 items + charged versions, projectiles, explosions
- 🟡 HUD (gauge, reserve, drift meter, minimap, item slot, messages)
- 🟡 Touch controls (floating stick, drift re-tap boost, layout editor), settings, main menu, garage, pause, results
- ✅ Audio library + music

## P6 — Polish & ship (phase 7)
- ⬜ Screenshots & render metrics (lavapipe) — harness 🟡 written
- ⬜ APK export + device test (S24 Ultra)
- ⬜ Bake generated world if load time is too long
- ⬜ Ghost replays for time trial
- ⬜ Second track (after the first is proven)
