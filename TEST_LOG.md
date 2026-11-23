# TEST_LOG — real runs

_Date: 2026-11-23 · Engine: official Godot 4.7.2-stable (Linux x86_64, SHA-512 verified) · Container: 4 CPU cores, no GPU, no phone._

Everything below was produced by actually running the code in this container. Nothing here was run on an Android device.

## ملخص بالعربية
- الاختبارات الآلية: **78 فحصاً، 78 نجاح، 0 فشل** (فيزياء 33، مسار 14، قفزات 3 تضم 40 محاولة، ذكاء اصطناعي 2، طرق 26).
- كل المتسابقين الثمانية أنهوا اللفة في مستويي Normal وExpert.
- APK مبني وتوقيعه سليم، وحزمة التصدير نفسها شُغِّلت بنجاح على محرك سطح المكتب.
- أرقام الرسم مقاسة على مُصيِّر برمجي (lavapipe)؛ **ليست مؤشراً لأداء الهاتف**. لم يُقس FPS على أي هاتف.

## 1. Automated suites
Command: `tools/build.sh test physics track jumps ai routes` (headless, fixed 60 Hz). Raw output: `tests/results/*.json`.

| Suite | Checks | Result | What it covers |
|---|---|---|---|
| physics | 33 | 33 ✓ | top speed, acceleration, steering radius, slide slip/radius, 3 spark stages, fizzle/backfire, reserve drain, Boost/Overdrive caps, chained slides, hop, ramp air boost, impact grading, hook turn, current, uphill/downhill speed, determinism |
| track | 14 | 14 ✓ | world builds (2.6 s desktop), 8 grid slots on road, drivable surface along main + each branch, width/radius variety |
| jumps | 3 (40 attempts) | 3 ✓ | Giant's Log, Flume and Shelf Rock behave as designed (table in TRACK_DESIGN.md §10) |
| ai | 2 | 2 ✓ | full 8-kart fields: Normal 8/8 finish (63.2–74.1 s lap 1), Expert 8/8 finish (54.0–79.3 s lap 1) |
| routes | 26 | 26 ✓ | Expert AI forced through 10 route combinations: each completes 2 laps and drives each forced shortcut to its end |
| **Total** | **78** | **78 ✓, 0 ✗** | |

Bugs these suites found and that were fixed this session (each one re-tested):
- kart lost speed on descents / rolled back (CharacterBody3D floor heuristics) → own ground snap;
- karts stalled on steep ramps (level capsule dug in) → capsule tilts with the ground;
- Flume: run-up had a 58° swerve at the ramp foot, the ramp foot was a 0.3 m step, the exit sat 1 m *below* the road it should drop onto, Overdrive+hop overshot the curving channel → redesigned;
- Rootway Cave: 12 m long, 29° climb, looping; shell and terrain holes started on the main road → rebuilt;
- river banks rejoined the road on crossing diagonals (karts trapped in the wedge) → shallow merges;
- mill house placed on the main road after the flume moved → placed by road clearance;
- AI never drifted / hit gates / missed entrances / got stuck → lane lead-ins, slide logic, watchdogs.

## 2. Rendering (Xvfb + lavapipe Vulkan, Mobile renderer, 1600×720, quality High)
Command: `tools/build.sh shots` → `tests/results/shots/*.png`, `tests/results/render.json`.

| View | Draw calls | Primitives | Objects |
|---|---|---|---|
| start_grid | 768 | 1.60 M | 973 |
| roof_lip | 572 | 1.67 M | 693 |
| portal_river | 602 | 1.56 M | 723 |
| river_rocks | 466 | 1.09 M | 585 |
| moss_arch | 487 | 1.10 M | 606 |
| lower_falls | 490 | 1.10 M | 609 |
| fernway | 475 | 1.15 M | 595 |
| giants_log | 487 | 1.29 M | 607 |
| ruins_owl | 530 | 1.24 M | 642 |
| millrace | 580 | 1.72 M | 723 |
| hairpin | 409 | 0.86 M | 526 |
| elder_tree | 538 | 1.36 M | 657 |
| race_0 / 1 / 2 (8 karts) | 676 / 755 / 644 | 1.42 / 1.65 / 1.28 M | 869 / 956 / 815 |

- Video memory ≈ 238–243 MB. World build (race scene) 2.6–3.7 s on this CPU.
- Frame time on lavapipe is 0.7–1.2 **seconds** — a CPU software rasterizer; it says nothing about phone FPS.
- The race_* images were re-rendered after moving the BRAKE button (it overlapped the minimap); the metrics in the table come from the full run just before.
- Menus rendered with `tests/debug/menu_shots.tscn` (menu_main, menu_setup, menu_garage, menu_settings*). Found and fixed: touch controls and settings panel had size 0, main menu overflowed 720 px.

## 3. Android package
- `tools/build.sh apk` → `export/WildsparkKart.apk`: 48.1 MB, package `com.wildspark.kart` 0.1.0, arm64-v8a, minSdk 24, targetSdk 36.
- `apksigner verify --print-certs`: valid, signer "CN=Android Debug" (debug keystore).
- Exported pack smoke test: `godot --export-pack "Android" android.pck`, then `godot --headless --main-pack android.pck -- --smoke-race` → menu → race scene built in 2.9 s → after 25 s: state "racing", 8 karts, no script errors. This proves the export filters include everything the race needs.
- **Not done:** installing/running on a phone or emulator, FPS, touch input, thermals, ASTC/ETC2 texture appearance on device.

## 4. Not tested at all
- Real-device performance (Galaxy S24 Ultra) and battery/heat.
- Touch controls with fingers; haptics.
- Audio output (no sound device in the container).
- Items balance (items are used by AI during races, but there is no dedicated item test).
- Human play-testing of handling feel and route balance (route lap times vary up to ~8 s between runs).
