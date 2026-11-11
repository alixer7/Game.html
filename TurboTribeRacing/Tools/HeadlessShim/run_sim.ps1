param([string]$Proj, [string]$Track = "tiki_island", [int]$Laps = 2, [string]$Skills = "0.3,0.6,0.9", [int]$Seed = 1, [int]$Obstacles = 1, [string]$Trace = "", [string]$Mode = "sim", [string]$OutDir = "/tmp")
$refs = New-Object 'System.Collections.Generic.List[Microsoft.CodeAnalysis.MetadataReference]'
foreach ($r in (Get-ChildItem /tmp/dl/ref/*.dll)) { $refs.Add([Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile($r.FullName)) }
$S = "$Proj/Assets/TurboTribe/Scripts"
$files = @("$Proj/Tools/HeadlessShim/UnityShim.cs", "$Proj/Tools/HeadlessShim/SettingsStub.cs", "$Proj/Tools/HeadlessShim/ExportTracks.cs", "$Proj/Tools/HeadlessShim/SimRunner.cs",
  "$S/Core/Util.cs", "$S/Core/MeshBuilder.cs", "$S/Core/Art.cs", "$S/UI/Painter.cs",
  "$S/Kart/Characters.cs", "$S/Kart/KartMeshes.cs", "$S/Kart/KartController.cs", "$S/Kart/AIDriver.cs", "$S/Race/Obstacles.cs") + (Get-ChildItem "$S/Track/*.cs" | ForEach-Object { $_.FullName })
$trees = New-Object 'System.Collections.Generic.List[Microsoft.CodeAnalysis.SyntaxTree]'
foreach ($f in $files) { $trees.Add([Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([System.IO.File]::ReadAllText($f), $null, $f)) }
$opts = [Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions]::new([Microsoft.CodeAnalysis.OutputKind]::DynamicallyLinkedLibrary).WithOptimizationLevel([Microsoft.CodeAnalysis.OptimizationLevel]::Release)
$comp = [Microsoft.CodeAnalysis.CSharp.CSharpCompilation]::Create("Headless", $trees, $refs, $opts)
$ms = New-Object System.IO.MemoryStream
$res = $comp.Emit($ms)
foreach ($d in $res.Diagnostics) { if ($d.Severity -eq 'Error') { Write-Output $d.ToString() } }
if (-not $res.Success) { exit 1 }
$asm = [System.Reflection.Assembly]::Load($ms.ToArray())
if ($Mode -eq "export") {
  $t = $asm.GetType("TurboTribe.Headless.ExportTracks")
  Write-Output ($t.GetMethod("Run").Invoke($null, @("$Proj/Assets/Resources/TurboTribe/Tracks", $OutDir)))
  $k = $asm.GetType("TurboTribe.Headless.ExportKarts")
  Write-Output ($k.GetMethod("Run").Invoke($null, @($OutDir)))
} else {
  $t = $asm.GetType("TurboTribe.Headless.SimRunner")
  $tr = $null; if ($Trace -ne "") { $tr = $Trace }
  Write-Output ($t.GetMethod("Run").Invoke($null, @("$Proj/Assets/Resources/TurboTribe/Tracks", $Track, $Laps, $Skills, $Seed, [bool]$Obstacles, $tr)))
}
