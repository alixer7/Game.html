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

## 3 Interconnected Tracks & 6 Semi-Hidden Aerial Shortcuts
Every track is engineered as interlocking zones where your exit speed, fire tier, and drift angle dictate your attack on the next zone. None of the shortcuts can be casually driven into at base speed — every one requires CTR fire speed, timed hops, and mid-air alignment or U-Turns:

1. **Tiki Cove Canyon (خليج تيكي الصخري)** — Tropical beach, lagoon split, over-under wooden Tiki overpass, waterfall tunnel.
   - *Lagoon Kicker Leap*: Carry Sacred Fire from the lagoon pad, spot the angled coral/stone kicker on the inside curve, Hop & air-steer left over turquoise ocean onto the Temple Plateau.
   - *Tiki Cliff Cut*: Carrying Sacred Fire off the Tiki Overpass, launch off the broken canyon parapet and execute a Mid-Air Right U-Turn across the gorge onto Pirate Ridge.
2. **Glacier Peak Pass (ممر القمة الجليدية)** — Alpine lodge hairpins, slippery Aurora Ice Cavern with **Blue Fire**, figure-8 ice overpass, snowbank rollers.
   - *Ice Wall Chasm Vault*: Exit the Ice Cavern with **Blue Fire**, Hop off the tilted crystal snowbank kicker to vault diagonals across the frozen chasm onto the figure-8 bridge.
   - *Aurora Fence-Hop*: Catch the second snow roller crest at Sacred/Blue Fire speed, Hop over the fence break and pull a Mid-Air Left U-Turn onto the alpine cliff bridge.
3. **Volcano Sky Temple (معبد السماء البركاني)** — Technical obsidian spiral climb, open cloud skybridges, **drivable curved volcanic half-pipe**, and **Ultra Blue Fire** hairpins.
   - *Half-Pipe Sky Tube*: Climb high up the curved left magma half-pipe wall at Sacred/Blue Fire speed and Hop at the apex lip to launch onto the hanging ancient Sky-Arch bridge!
   - *Cloud Abyss U-Turn*: Carry **Blue Fire** to the high cloud spire edge, launch off the angled obsidian lip out over empty clouds, and carve a 115° Mid-Air Left U-Turn onto the far Temple Plunge deck!

## Opening the Project in Godot
1. Extract `NitroFuryRacing_GodotProject.zip`.
2. Open `project.godot` in **Godot 4.4.1-stable** (or newer 4.4.x).
3. Press **F5** to play on Desktop (Keyboard: `WASD`/Arrows steer, `Space`/`J` Hop & Drift, `Shift`/`K` Boost!, `S`/`Down` Air-Brake U-Turn, `E`/`L` Item, `Esc` Pause) OR export directly to Android via `Project -> Export -> Android`.

## Installing the APK on Android
1. Copy `NitroFuryRacing.apk` to your Android phone.
2. Tap the APK to install (enable "Install unknown apps" if prompted; signed with debug keystore for direct sideloading).
3. Supports **ARM64 (`arm64-v8a`)** and **ARMv7 (`armeabi-v7a`)**, immersive landscape full-screen, multi-touch controls, and bilingual **Arabic / English (`عربي / EN`)** UI!
