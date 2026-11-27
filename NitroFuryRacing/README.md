# NITRO FURY RACING (نيترو فيوري ريسينغ)

A mobile-first 3D arcade kart racing game built in **Godot Engine 4.4.1**, crafted around the physics philosophy, visual vibrancy, interconnected track zones, and high-skill aerial shortcuts of **Crash Team Racing (CTR)**.

## Core CTR Physics & Mechanics
- **Power-Slide 3-Stage Drift Boost**: Hold **HOP/DRIFT** while steering to lock into an adjustable power-slide arc (steer inward to hug apexes, steer outward to snake down straights). Tap **BOOST!** when the charge meter enters the green (**GOOD!**) or glowing red-gold (**PERFECT!!**) zone up to **3 times per slide**!
- **Hidden Reserves & 5 Fire Tiers**:
  - **No Fire** (Base speed, `+8%` Juiced bonus at 10 Nitro Fruits)
  - **Red Fire** (Small hop / early start launch)
  - **Orange Fire** (Drift boosts / medium-large Hang-Time Turbo / Nitro Canister)
  - **Sacred Fire (SF)** (Orange Turbo Pads — elevated top speed maintained as long as Reserves > 0!)
  - **Ultimate Sacred Fire / Blue Fire (USF)** (Electric Cyan Super Turbo Pads — blistering supersonic speed maintained across the entire lap via drift-chaining Reserves!)
- **Hang-Time Turbo**: Hop off ramps, crests, and kickers — longer airtime yields bigger landing boosts and Reserves!
- **Mobile-Perfected Air-Brake & U-Turn**: Tap **HOP**, then hold **U-TURN + Left/Right** in mid-air to pivot sharply on a dime **without losing Blue Fire or Reserves**! Essential for Blue Fire hairpins and curved aerial shortcuts.
- **Off-Road Hop Preservation**: Grounded off-road (sand/deep snow) slows your kart and drains Reserves rapidly — bunny-hopping across off-road cuts preserves your Reserves!
- **Ticking TNT Shake-Off**: Hit a TNT crate? Rapidly tap **HOP** 5 times to fling it off before it detonates!

## v8 — Rebuilt CTR:NF-style Tracks (see `docs/TRACK_DESIGN_V8.md`, Arabic)
All three tracks were redesigned from scratch with a new track designer (`tools/trackgen/`) and are verified with
**real physics** (`tests/VerifyV8.tscn`): an autopilot laps every track with zero stalls/falls, every shortcut is
actually driven at 5 speed tiers, and a 6-kart AI race keeps every kart racing.

| Track | Length | Highlights |
|---|---|---|
| **Emerald Temple Circuit** | 2.54 km | jungle village, river-gorge jump, INSIDE the stepped pyramid, open summit U-turn, canopy trestle crossing 14 m over the gorge, drive behind a waterfall, lagoon beach, ruins |
| **Bio-Lab Hydro Speedway** | 2.36 km | reactor atrium & crusher hall (indoor), 4x90-degree acid catwalks, hydro half-pipes on stilts, 7.5 m drop out of the lab, snow switchbacks over a crevasse with an avalanche gallery, frozen lake, ice cave, 22 m return climb |
| **Cosmic Citadel Starway** | 2.42 km | neon city on a floating asteroid, skyline highway, launch tube into space, floating glass orbital ring with gap jumps & a void U-turn, asteroid mine, lava causeways, plasma half-pipe |

**9 jump-only shortcuts** (no side roads, no bridges): elevated corner leaps, floating stepping stones, a ruin-wall
vault, a straight leap across the acid pool detour, a drop over the avalanche gallery roof, a skyscraper rooftop hop,
a Blue-Fire void leap and a lava-lake leap. Each kicker is placed by a ballistic solver so base speed falls short and
the required fire tier + hop makes it.

**Surfaces matter** (`scripts/physics/Surfaces.gd`): stone, cobble, dirt, wood, wet stone, metal, grating, asphalt,
neon, glass, basalt, packed snow, ice; off-road grass / sand / mud / snow / ash / gravel bleed speed and Reserves;
lava / acid / deep water respawn you.

**Collisions**: every prop, tree, wall, pillar and the terrain itself is solid, with soft / medium / heavy impact tiers;
the whole road + shoulders is one seamless collider so nothing on the floor can stop a kart.

Rebuild track data after editing a track: `cd tools/trackgen && python3 build_all.py` (numpy, scipy, matplotlib).

## Opening the Project in Godot
1. Extract `NitroFuryRacing_GodotProject.zip`.
2. Open `project.godot` in **Godot 4.4.1-stable** (or newer 4.4.x).
3. Press **F5** to play on Desktop (Keyboard: `WASD`/Arrows steer, `Space`/`J` Hop & Drift, `Shift`/`K` Boost!, `S`/`Down` Air-Brake U-Turn, `E`/`L` Item, `Esc` Pause) OR export directly to Android via `Project -> Export -> Android`.

## Installing the APK on Android
1. Copy `NitroFuryRacing.apk` to your Android phone.
2. Tap the APK to install (enable "Install unknown apps" if prompted; signed with debug keystore for direct sideloading).
3. Supports **ARM64 (`arm64-v8a`)** and **ARMv7 (`armeabi-v7a`)**, immersive landscape full-screen, multi-touch controls, and bilingual **Arabic / English (`عربي / EN`)** UI!
