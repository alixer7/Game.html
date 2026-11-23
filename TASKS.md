# TASKS

Legend: ✅ done & verified by a real run · 🟡 runs, needs tuning/human play-test · ⬜ not started · 📱 needs a real phone

## P0 — Toolchain
- ✅ Official Godot 4.7.2 editor + export templates (SHA-512 verified) — `tools/setup_toolchain.sh`
- ✅ Android SDK (build-tools 35.0.1, platform 35) + debug keystore
- ✅ `tools/build.sh` import / test / shots / apk / zip

## P1 — Handling
- ✅ Arcade controller (floating CharacterBody3D, own ground snap, heading/velocity split, momentum-conserving grip)
- ✅ 3-stage spark slides, boost reserve, Boost/Overdrive tiers, hook turn, hop/lip-hop, air boost, graded impacts, surfaces, current
- ✅ 33 physics tests incl. slopes; collider tilts with the ground
- 🟡 Feel tuning with a human on a phone 📱

## P2 — Track
- ✅ Authoring tool, closed ~1.5 km loop, 7 zones, 7 branches, diagrams
- ✅ Road mesher, terrain sculpt/carve/holes, water, end caps, lead-ins
- ✅ Jumps measured and tuned (tunnel, falls, log, shelf, flume)
- ✅ Flume, cave and bank merges redesigned after test failures
- 🟡 Route balance: needs averaged multi-run timings (single runs vary ±8 s)

## P3 — Environment
- ✅ Textures, set pieces, landmarks, scatter with LODs, life — rendered and reviewed
- 🟡 Performance budget: 0.85–2.0 M primitives/view at High (lavapipe) — likely too high for 60 fps 📱
- ⬜ Bake generated world if phone load time is long 📱

## P4 — Racing
- ✅ Racing lines, lane graph, lead-ins, AI with 4 difficulties; 8/8 finish in Normal and Expert
- ✅ Race manager (countdown, laps, positions, respawn, results)
- 🟡 AI collisions/variance; spark usage is low on some AI

## P5 — Items & UI
- 🟡 5 items + charged versions (run in AI races; no dedicated tests yet)
- ✅ HUD, menus, garage, settings rendered; layout bugs fixed
- 🟡 Touch controls drawn correctly; never used with real fingers 📱

## P6 — Ship
- ✅ APK export (arm64, debug-signed, verified); exported pack smoke-run on desktop
- ⬜ Install and profile on Galaxy S24 Ultra 📱
- ⬜ Time-trial ghosts
- ⬜ Second track
