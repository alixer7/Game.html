#!/usr/bin/env bash
# Headless verification with the REAL game code (TrackBuilder, KartController, AIDriver, ObstacleManager, KartMeshes...)
# compiled against Tools/HeadlessShim/UnityShim.cs - no Unity needed, only the .NET 8 SDK (dotnet).
#
#   Tools/HeadlessShim/run_sim.sh sim <track> [laps] [skills] [seed] [trace.csv]   race CPUs, lap times / falls / bonks
#   Tools/HeadlessShim/run_sim.sh shortcuts <track>                                 drive every shortcut with the real physics
#   Tools/HeadlessShim/run_sim.sh export <outdir>                                    OBJ export of all tracks + karts
#   Tools/HeadlessShim/run_sim.sh ray <track> x z [x z ...]                          what surfaces are under a point
#
# tracks: tiki_island | dustbowl_canyon | glacier_peak.  Renders: Tools/webgl_render.py, Tools/render_karts.py,
# scene QA: Tools/check_scene.py (props floating / intruding into roads).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(cd "$HERE/../.." && pwd)"
BUILD="${TT_SIM_DIR:-${TMPDIR:-/tmp}/turbotribe_headless}"
mkdir -p "$BUILD"
S="$PROJ/Assets/TurboTribe/Scripts"
cat > "$BUILD/HeadlessSim.csproj" <<EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <LangVersion>latest</LangVersion>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
    <Nullable>disable</Nullable>
    <Optimize>true</Optimize>
    <InvariantGlobalization>true</InvariantGlobalization>
    <NoWarn>CS0649;CS0169;CS0414;CS8019;CS0162;CS0219;CS0168</NoWarn>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="$HERE/UnityShim.cs;$HERE/SettingsStub.cs;$HERE/ExportTracks.cs;$HERE/SimRunner.cs" />
    <Compile Include="$S/Core/Util.cs;$S/Core/Sculpt.cs;$S/Core/MeshBuilder.cs;$S/Core/Art.cs;$S/UI/Painter.cs" />
    <Compile Include="$S/Kart/Characters.cs;$S/Kart/KartMeshes.cs;$S/Kart/KartController.cs;$S/Kart/AIDriver.cs;$S/Race/Obstacles.cs;$S/Track/*.cs" />
    <Compile Include="Program.cs" />
  </ItemGroup>
</Project>
EOF
cp "$HERE/Program.cs.txt" "$BUILD/Program.cs"
( cd "$BUILD" && dotnet build -nologo -v q -c Release | grep -E " error |rror\(s\)" || true )
exec dotnet "$BUILD/bin/Release/net8.0/HeadlessSim.dll" "$PROJ" "$@"
