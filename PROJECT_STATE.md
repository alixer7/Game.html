# PROJECT_STATE

_Last updated: 2026-11-23 (0.3.0)_

## ملخص بالعربية
الإصدار **0.3.0** يعالج المشاكل التي ظهرت عند تجربة اللعبة على الهاتف: أبعاد الشاشة والقوائم المخفية خلف حواف الشاشة (لوحتا الإيقاف والنتائج كانتا خارج الشاشة فعلاً)، والأزرار التي لا تستجيب، والأداء الثقيل، ومرور المركبة عبر الأشجار والصخور والمباني، والأرضيات المرتفعة قليلاً التي كانت توقف المركبة كأنها جدار. كل الاختبارات الآلية تنجح (**84 فحصاً**) بما فيها مجموعتان جديدتان تختبران هذه المشاكل تحديداً. **ما زال لم يُجرَّب على هاتف حقيقي من طرفنا**؛ أرقام الأداء مقاسة على مُصيِّر برمجي وتُظهر انخفاضاً كبيراً في كلفة الرسم، لكن معدل الإطارات الفعلي على الهاتف يجب قياسه.

## Status by system

| System | Files | State |
|---|---|---|
| Kart physics | scripts/kart/kart.gd, kart_params.gd, surfaces.gd | **Runs; 33/33 physics tests pass.** Collider rides 0.30 m above the ground with a 0.36 m step-up (seams/kerbs/lips are climbed, not walls); tilts with the ground. |
| Kart model & visuals | scripts/gen/kart_model.gd, scripts/kart/kart_visual.gd | **Rendered** (menus, grid, race shots). 8 original animal drivers. |
| Camera | scripts/kart/chase_camera.gd | Runs (race screenshots). |
| Track authoring | tools/track_timberfall.py → data/timberfall.json | Runs; regenerates map/profile diagrams. |
| Track builder | scripts/track/*.gd | **Runs; 14/14 track + 4/4 drive tests.** Roads blend into the ground (fitted terrain, terrain-following skirts), merges seated on the main road, every reachable prop solid. Built in stages with a progress bar (≈ 3–4 s on the desktop CPU). |
| Jumps | (geometry in the authoring tool) | **Measured**: 5 jumps × 4 speeds × hop/no-hop (tests/results/jumps.json). |
| Set pieces & landmarks | scripts/track/set_pieces.gd | Rendered and reviewed in screenshots. |
| Gameplay objects | scripts/track/track_gameplay.gd, scripts/env/*.gd | Run in races (pads, crates, amber, swinging log, flytraps, gate, stalagmites). |
| Vegetation scatter (LOD) | scripts/track/scatter.gd, scripts/gen/mesh_lib.gd | Rendered; 3 LOD levels per quality preset (trees 858/130/76 tris), colliders for every reachable tree/rock/stump/log. |
| Environmental life | scripts/track/env_life.gd, scripts/env/* | Runs (birds, leaves, fireflies, fish, smoke). |
| Shaders | shaders/*.gdshader | **Compile and render** (Vulkan/lavapipe). Not yet seen on a Mali/Adreno GPU. |
| Racing lines + AI | scripts/race/racing_line.gd, scripts/drivers/ai_driver.gd | **Runs; all 8 AI finish** in Normal and Expert fields; every shortcut is driven end-to-end when forced. |
| Race manager | scripts/race/race_manager.gd | Runs (countdown, laps, positions, respawn, results). |
| Items | scripts/race/item_system.gd, scripts/items/*.gd | Run during AI races (no dedicated item test suite yet). |
| HUD / touch / menus / settings | scripts/ui/*.gd | **2/2 UI tests**: 8 screen shapes × 3 cut-out cases, every widget inside the safe area, every button tapped; back gesture / backgrounding handled. Not yet touched by real fingers. |
| Audio | audio/ | Loads (no audio device in the container; not listened to). |
| Android export | export_presets.cfg, tools/build.sh | **APK 0.3.0 built** (`export/WildsparkKart.apk`, arm64-v8a, targetSdk 36, immersive + edge-to-edge, same debug key as before, `apksigner verify` OK). Exported pack smoke-run on desktop. **Not installed on a phone by us.** |

## Measured numbers (real runs, this container)
- Tests: physics 33 ✓, track 14 ✓, jumps 3 ✓, drive 4 ✓, ui 2 ✓, ai 2 ✓, routes 26 ✓ → **84/84** (details in TEST_LOG.md).
- Route lap times (Expert AI, lap 2, single run each): see TRACK_DESIGN.md §10. Run-to-run spread is up to ~8 s because AI collisions vary; the numbers show every route works, not a precise balance.
- Render (lavapipe software Vulkan, 1600×720, Medium = phone default): 230–461 draw calls, 0.27–0.59 M primitives per view (was 364–768 / 0.85–2.0 M at the old High default), 183 MB video memory. Lavapipe frame times are **not** phone FPS.

## Not verified / known gaps
- No run on a real Android device or emulator; **FPS on the S24 Ultra is unknown**.
- Touch controls never driven by real fingers.
- Rendering cost cut ~3× but not profiled on phone hardware; if a phone still struggles, lower the preset to Low or the render scale in Settings → Graphics.
- Item balance, rubber-banding feel and AI aggression not play-tested by a human.
- Audio mix not listened to.
