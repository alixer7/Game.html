# NEXT_SESSION

## ملخص بالعربية
الأولوية التالية: إعادة تجربة الإصدار 0.3.0 على الهاتف (القوائم مع نتوء الكاميرا، كل الأزرار، إيماءة الرجوع، القيادة على حواف الطرق وباتجاه الأشجار والصخور)، ثم قياس معدل الإطارات وزمن التحميل والحرارة، ثم الضبط حسب النتائج.

## Last done (0.3.0 — fixes from the first phone test)
- Screen: safe-area layout everywhere (cut-outs, rounded corners, nav bars, re-applied on rotation), pause/results panels were off-screen → centred; responsive menus; touch controls inside the safe area; back gesture handled; auto-pause when the app is left.
- Collisions: raised kart collider + step-up; roads blended into the ground; merges seated; every reachable prop solid.
- Performance: ~3× lower scene cost (tree LODs, shadows, cells, MultiMesh pickups), automatic 3D resolution + FSR, Medium default on phones, staged loading.
- New test suites `drive` and `ui`; all 84 checks pass.

## Exact next steps
1. **Device re-test of 0.3.0 (S24 Ultra):** check the menus/HUD with the punch-hole camera on both sides (rotate the phone), every button, the back gesture, and drive along road edges / into trees and rocks.
2. **Device performance:** `adb install -r export/WildsparkKart.apk`; Settings → Show FPS. Record FPS on the start grid, river, Millrace and in a full 8-kart race at High/Medium/Low, plus load time and temperature after 10 minutes. Put the numbers in PROJECT_STATE.md.
3. If FPS < 60 on Medium: lower `Game.RENDER_HEIGHT`, scatter density/LOD ranges (`scripts/track/scatter.gd`), or the set-piece meshes; `tests/debug/render_breakdown.tscn` shows what each category costs.
4. If load time is long on the phone: bake the generated world into `res://generated/*.scn` at export time.
5. Touch play-test: stick dead-zone, drift re-tap window (`RETAP_WINDOW`), button sizes; adjust defaults in `scripts/ui/touch_controls.gd`.
6. Balance: run `tools/build.sh test routes` 5× and average per route.
7. Items: add a test suite (hit rates, shield timing, trap placement) and tune.
8. Time-trial ghost, second track.

## Useful commands
```bash
tools/build.sh test physics track jumps drive ui ai routes   # headless suites (~8 min total)
tools/build.sh shots                                  # screenshots + render metrics (lavapipe, ~12 min)
godot --path . res://tests/debug/menu_shots.tscn       # menu screenshots
godot --headless --path . res://tests/debug/ai_trace.tscn -- 3 90 rootway_cave   # trace one AI on a forced route
godot --headless --path . res://tests/debug/jump_trace.tscn -- millrace_flume flume_kick_lip 31 0
tools/build.sh apk && tools/build.sh zip
```

## Known risks
- GPU differences (Mali/Adreno vs lavapipe) in the custom shaders.
- GDScript world generation time on phones (~2.9 s on a desktop CPU).
- AI lap times vary run-to-run by several seconds (collision-driven).
