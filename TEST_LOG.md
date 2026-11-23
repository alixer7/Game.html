# TEST_LOG — real runs

_Version 0.3.0 · Date: 2026-11-23 · Engine: official Godot 4.7.2-stable (Linux x86_64) · Container: 4 CPU cores, no GPU, no phone._

Everything below was produced by actually running the code in this container. **Nothing here was run on an Android device.**

## ملخص بالعربية
- الاختبارات الآلية: **84 فحصاً، 84 نجاح، 0 فشل**.
- مجموعتا اختبار جديدتان لمشاكل اللاعب: **drive** (الحواف والدرجات بين الطرق والأرض، وعدم المرور عبر الأشجار والصخور والمباني) و**ui** (كل زر وكل عنصر داخل المنطقة الآمنة للشاشة على 8 أشكال شاشات × 3 حالات نتوء كاميرا، وكل زر يستجيب للمس).
- عدد المضلعات في المشهد انخفض من 0.85–2.0 مليون إلى 0.27–0.59 مليون (إعداد Medium الافتراضي للهواتف)، وأوامر الرسم من 364–768 إلى 230–461.
- APK بالإصدار 0.3.0 مبني وتوقيعه سليم وبنفس مفتاح الإصدار السابق (يُثبَّت فوقه). **لم يُجرَّب على هاتف**.

## 1. Automated suites
Command: `tools/build.sh test physics track jumps drive ui ai routes` (headless, fixed 60 Hz). Raw output: `tests/results/*.json`.

| Suite | Checks | Result | What it covers |
|---|---|---|---|
| physics | 33 | 33 ✓ | speed, acceleration, steering, slides, 3 spark stages, reserve/tiers, hops, air boost, impact grading, hook turn, current, slopes, determinism |
| track | 14 | 14 ✓ | world builds, grid on road, continuous surface on every route, width/radius variety |
| jumps | 3 (40 attempts) | 3 ✓ | Giant's Log, Flume, Shelf Rock behave as designed |
| **drive** (new) | 4 | 4 ✓ | **step scan:** 49 832 adjacent height pairs across every road and its shoulders, 0 steps above the 0.36 m climbable limit. **edges:** 72 drives onto/off road edges at 40°, 0 blocked by a road or the ground. **junctions:** 14 branch entries/exits, 0 blocked. **colliders:** 2 300 reachable trees/rocks/stumps/logs + 253 sampled points on solid structures, all solid. |
| **ui** (new) | 2 | 2 ✓ | 8 screen shapes (19.5:9 FHD+/QHD+, 20:9, 16:9, 21:9, 16:10, 4:3) × 3 cut-out cases (none, punch-hole, notch + nav bar): 2 502 widgets inside the safe area, 885 buttons tapped through the real input path, 0 failures; Android back gesture + app backgrounding (pause, step back, never quit by accident) |
| ai | 2 | 2 ✓ | 8-kart fields, Normal and Expert: all 8 finish |
| routes | 26 | 26 ✓ | Expert AI forced through 10 route combinations; every forced shortcut driven to its end |
| **Total** | **84** | **84 ✓, 0 ✗** | |

Route lap 2 times (one run each, Expert AI; run-to-run spread is several seconds): baseline 63.97 s · left bank 57.12 · right bank 61.52 · Giant's Log 59.22 · log + shelf 57.17 · cave 61.12 · flume 62.87 · gate + flume 60.78 · log + shelf + flume 53.57 · right bank + log + cave 61.07.

### Do the new tests catch the reported bugs?
- The **ui** suite was run against the previous pause/results code: it reported **116 failures** (panels placed off-screen top-left). With the fix: 0.
- The **drive** step scan found **90** blocking steps on the first run (roads floating 0.8 m above carved ground, the flume chute 1 m above the road edge, river bank lips, a merge kerb on a banked road …). All were fixed in the track builder; now 0.
- The **collider audit** found trunk faces without collision; fixed; now 0 misses.

## 2. Rendering (Xvfb + lavapipe Vulkan, Mobile renderer, 1600×720)
Command: `tools/build.sh shots` with `WK_QUALITY=1` (Medium = new phone default) → `tests/results/shots/*.png`, `tests/results/render.json`.

| View | Draw calls (before → now) | Primitives (before → now) |
|---|---|---|
| start_grid | 768 → 461 | 1.60 M → 0.59 M |
| roof_lip | 572 → 274 | 1.67 M → 0.42 M |
| portal_river | 602 → 330 | 1.56 M → 0.41 M |
| river_rocks | 466 → 260 | 1.09 M → 0.32 M |
| moss_arch | 487 → 237 | 1.10 M → 0.29 M |
| lower_falls | 490 → 317 | 1.10 M → 0.36 M |
| fernway | 475 → 230 | 1.15 M → 0.28 M |
| giants_log | 487 → 265 | 1.29 M → 0.32 M |
| ruins_owl | 530 → 293 | 1.24 M → 0.37 M |
| millrace | 580 → 303 | 1.72 M → 0.37 M |
| hairpin | 409 → 230 | 0.86 M → 0.27 M |
| elder_tree | 538 → 331 | 1.36 M → 0.42 M |
| race (8 karts) | 644–755 → 360–389 | 1.28–1.65 M → 0.39–0.48 M |

"Before" = previous build at High (the old phone default); "now" = Medium (new phone default). Video memory 238 → 183 MB. The software renderer's frame time fell from 0.8–1.2 s to 0.27–0.44 s at the same resolution (it is a CPU rasterizer: a relative measure only, **not** phone FPS). On a phone the automatic 3D resolution (720 px tall on Medium, FSR upscaling) cuts pixel work further.

CPU per frame for the full 8-kart race simulation (headless, desktop CPU): 2.4 ms average, 3.7 ms p95, 7.9 ms worst.

## 3. Android package
- `tools/build.sh apk` → `export/WildsparkKart.apk`: package `com.wildspark.kart`, **version 0.3.0 (code 3)**, arm64-v8a, minSdk 24, targetSdk 36, landscape (sensor), immersive + edge-to-edge.
- `apksigner verify`: valid; signer certificate SHA-256 `00d8dbeb…524a` = same as the previous build, so it installs as an update.
- Exported pack smoke test (`--smoke-race` on the desktop engine): menu → race built (2.9 s, staged with a progress bar) → racing with 8 karts after 25 s, no script errors.

## 4. Not tested
- **Any real phone**: FPS, frame pacing on a 120 Hz screen, heat, load time, touch feel, cut-out handling on real hardware (simulated only).
- Audio output (no sound device here).
- Item balance (items run in AI races; no dedicated item suite).
- Human play-testing of handling and route balance.
