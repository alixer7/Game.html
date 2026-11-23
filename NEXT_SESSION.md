# NEXT_SESSION

## ملخص بالعربية
الأولوية التالية: تثبيت الـ APK على هاتف حقيقي (Galaxy S24 Ultra) وقياس معدل الإطارات ودرجة الحرارة وزمن تحميل المسار، ثم خفض عدد المضلّعات إن لزم، ثم تجربة اللمس يدوياً وضبط التوازن بين الطرق والاختصارات بعدة جولات لكل طريق.

## Last done (session 2)
- Got the official Godot 4.7.2 + export templates (SHA-512 verified) and the Android SDK; fixed every compile error.
- Physics rewritten onto a floating CharacterBody3D with its own ground snap; 33 physics tests pass.
- Measured every jump and retuned geometry; jump suite passes.
- Redesigned the Millrace Flume (big-air kicker, run-out, curved channel, chute exit), the Rootway Cave (tunnel with a tight U-turn inside the hairpin) and the river-bank merges after tests and traces exposed real defects.
- AI: racing-line lanes with lead-ins onto every shortcut, slide decisions, stuck/lost/progress watchdogs → all 8 AI finish (Normal and Expert).
- Rendered landmarks, races and menus with lavapipe; fixed touch-control and settings-panel layout bugs and the main menu overflow.
- Built and verified the APK; smoke-ran the exported pack on desktop.

## Exact next steps
1. **Device test (S24 Ultra):** `adb install -r export/WildsparkKart.apk`; Settings → Show FPS. Record FPS on the start grid, river, Millrace and in a full 8-kart race at High/Medium/Low, plus load time and temperature after 10 minutes. Put the numbers in PROJECT_STATE.md.
2. If FPS < 60: lower scatter density for Medium/High (`scripts/track/scatter.gd` specs), shorten LOD1 ranges, cut far tree share; target < 800 k primitives on High.
3. If load time is long on the phone: bake the generated world into `res://generated/*.scn` at export time.
4. Touch play-test: stick dead-zone, drift re-tap window (`RETAP_WINDOW`), button sizes; adjust defaults in `scripts/ui/touch_controls.gd`.
5. Balance: run `tools/build.sh test routes` 5× and average per route; target river ≈ banks ± 1 s, log/shelf/flume/cave each a clear but risky gain.
6. Items: add a test suite (hit rates, shield timing, trap placement) and tune.
7. Time-trial ghost, second track.

## Useful commands
```bash
tools/build.sh test physics track jumps ai routes     # headless suites (~6 min total)
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
