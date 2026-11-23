# PROJECT_STATE

_Last updated: 2026-11-23 (session 2)_

## ملخص بالعربية
اللعبة **Wildspark Kart** تعمل الآن فعلياً داخل **Godot 4.7.2 الرسمي** (تم تنزيله والتحقق منه بـ SHA-512). كل الكود يُترجم، وكل الاختبارات الآلية تنجح (**78 فحصاً، 0 فشل**: فيزياء 33، مسار 14، قفزات 3 تضم 40 محاولة مقاسة، ذكاء اصطناعي 2، طرق 26). المسار **Timberfall Rapids** مكتمل بكل اختصاراته، وقد أُعيد تصميم قناة الطاحونة (Flume) وكهف الجذور (Rootway Cave) ونقاط التقاء ضفّتي النهر بعد أن كشفت الاختبارات عيوباً حقيقية فيها. كل المتسابقين الثمانية بالذكاء الاصطناعي يُنهون اللفة في مستويي Normal وExpert.
تم بناء **APK** (arm64، موقّع بمفتاح debug، تم التحقق من التوقيع بـ apksigner)، وتم تشغيل حزمة التصدير نفسها على محرك سطح المكتب بنجاح (السباق يُبنى ويعمل). **لم يُشغَّل الـ APK على هاتف أو محاكي**، ولم يُقس معدل الإطارات على Galaxy S24 Ultra. أرقام الرسم (draw calls / primitives) مقاسة فعلياً لكن على مُصيِّر برمجي (lavapipe) وليست مؤشراً لأداء الهاتف.

## Status by system

| System | Files | State |
|---|---|---|
| Kart physics | scripts/kart/kart.gd, kart_params.gd, surfaces.gd | **Runs; 33/33 physics tests pass** (accel, top speed, grip, slides, 3 spark stages, reserve tiers, hook turn, hops, air boost, impacts, surfaces, slopes up/down). Collision capsule now tilts with the ground (no nose-dig on steep ramps). |
| Kart model & visuals | scripts/gen/kart_model.gd, scripts/kart/kart_visual.gd | **Rendered** (menus, grid, race shots). 8 original animal drivers. |
| Camera | scripts/kart/chase_camera.gd | Runs (race screenshots). |
| Track authoring | tools/track_timberfall.py → data/timberfall.json | Runs; regenerates map/profile diagrams. |
| Track builder | scripts/track/*.gd | **Runs; 14/14 track tests** (continuous drivable surface on main + every branch, grid on road, width/radius variety). Build ≈ 2.6–2.9 s on the desktop CPU. |
| Jumps | (geometry in the authoring tool) | **Measured**: 5 jumps × 4 speeds × hop/no-hop (tests/results/jumps.json). |
| Set pieces & landmarks | scripts/track/set_pieces.gd | Rendered and reviewed in screenshots. |
| Gameplay objects | scripts/track/track_gameplay.gd, scripts/env/*.gd | Run in races (pads, crates, amber, swinging log, flytraps, gate, stalagmites). |
| Vegetation scatter (LOD) | scripts/track/scatter.gd, scripts/gen/mesh_lib.gd | Rendered; 3 LOD levels + far shared meshes. |
| Environmental life | scripts/track/env_life.gd, scripts/env/* | Runs (birds, leaves, fireflies, fish, smoke). |
| Shaders | shaders/*.gdshader | **Compile and render** (Vulkan/lavapipe). Not yet seen on a Mali/Adreno GPU. |
| Racing lines + AI | scripts/race/racing_line.gd, scripts/drivers/ai_driver.gd | **Runs; all 8 AI finish** in Normal and Expert fields; every shortcut is driven end-to-end when forced. |
| Race manager | scripts/race/race_manager.gd | Runs (countdown, laps, positions, respawn, results). |
| Items | scripts/race/item_system.gd, scripts/items/*.gd | Run during AI races (no dedicated item test suite yet). |
| HUD / touch / menus / settings | scripts/ui/*.gd | **Rendered** (tests/results/shots/menu_*.png, race_*.png). Two layout bugs found and fixed this session (touch controls and settings panel had size 0). Touch input not tested on a real screen. |
| Audio | audio/ | Loads (no audio device in the container; not listened to). |
| Android export | export_presets.cfg, tools/build.sh | **APK built** (`export/WildsparkKart.apk`, 48 MB, arm64-v8a, targetSdk 36, debug-signed, `apksigner verify` OK). The exported pack was smoke-run on desktop Godot (`--smoke-race`): world built, race running with 8 karts. **Not installed on any phone or emulator.** |

## Measured numbers (real runs, this container)
- Tests: physics 33 ✓, track 14 ✓, jumps 3 ✓ (40 attempts), ai 2 ✓, routes 26 ✓ → **78/78**.
- Route lap times (Expert AI, lap 2, single run each): see TRACK_DESIGN.md §10. Run-to-run spread is up to ~8 s because AI collisions vary; the numbers show every route works, not a precise balance.
- Render (lavapipe software Vulkan, 1600×720, quality High): 364–768 draw calls, 0.85–2.0 M primitives per view, ~236–241 MB video memory. Frame times on lavapipe (~0.8–1.2 s) are **not** an indication of phone FPS.

## Not verified / known gaps
- No run on a real Android device or emulator; **FPS on the S24 Ultra is unknown**.
- Touch controls never driven by real fingers.
- Primitive count (up to ~2 M/frame at High) is likely too high for a steady 60 fps on a phone; Medium/Low presets exist but were not profiled on hardware.
- Item balance, rubber-banding feel and AI aggression not play-tested by a human.
- Audio mix not listened to.
