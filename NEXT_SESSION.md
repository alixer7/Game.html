# NEXT_SESSION

## ملخص بالعربية
الخطوة التالية الإلزامية: الحصول على Godot 4.7.2 الرسمي وقوالب التصدير، ثم تشغيل الاستيراد والاختبارات، وإصلاح أخطاء الترجمة (متوقعة في كود كبير لم يُشغَّل بعد)، ثم ضبط الفيزياء والمسار بالأرقام الفعلية، ثم اللقطات وبناء APK.

## Last done (session 1)
Wrote the whole game in code (see PROJECT_STATE.md). Generated textures, audio, track data and design diagrams. Installed the Android SDK in the session container. Commits on branch `ccr-4cebcfbd-f8qfva`.

## Exact next steps
1. **Get Godot 4.7.2-stable + export templates.** Either:
   - allow this cloud session to attach `godotengine/godot` read-only (so `github.com/godotengine/godot/releases/...` is reachable), then run `tools/setup_toolchain.sh /home/user/tools`; or
   - run `tools/setup_toolchain.sh` on your own Linux machine (needs github.com + dl.google.com).
2. `tools/build.sh import` — imports textures/audio (creates `.godot/`). Watch the output for script parse errors and fix them first; ~10 k lines of GDScript have never been compiled.
3. `tools/build.sh test physics` → tune `kart_params.gd` until every handling target passes.
4. `tools/build.sh test track` → fix any holes/discontinuities in roads or set pieces.
5. `tools/build.sh test ai` then `routes` → balance shortcuts/lanes (TRACK_DESIGN §4–5) using the measured lap times.
6. `tools/build.sh shots` (Xvfb + lavapipe) → check shaders compile, inspect every landmark view, fix visuals, record draw calls/primitives in `tests/results/render.json`.
7. Measure build time of the track (`[race] world built in … ms`). If > ~4 s on desktop, bake the generated world to `res://generated/*.scn` at export time.
8. `tools/build.sh apk` → `export/WildsparkKart.apk`; `tools/build.sh zip` → project ZIP.
9. Real-device test on Galaxy S24 Ultra: FPS (enable Settings → Show FPS), touch feel, safe areas, heat.

## Known risks / likely issues
- GDScript static-typing errors (unverified code). Most likely spots: lambdas inside call arguments, Variant→typed assignments, dictionary-dot access.
- Shader compile errors (unverified): `shaders/*.gdshader` (common include, `BACKLIGHT`, `CAMERA_POSITION_WORLD`).
- Winding of procedural meshes was reasoned by hand (MeshBuilder `tri()/quad()` take CCW-from-front and store CW). If a mesh appears inside-out, flip its quad order.
- Runtime world generation time on phones (GDScript). Plan B: bake.
- `Jolt Physics` + `CharacterBody3D` interplay with rotating the body each tick (yaw only) — verify floor snapping on the rollers/crests.

## Files changed this session
Everything (initial build). See CHANGELOG.md.
