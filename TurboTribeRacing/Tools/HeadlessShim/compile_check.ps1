param([string]$OutName, [string]$RefList, [string]$SrcList, [string]$Defines = "UNITY_ANDROID;UNITY_2022_3_OR_NEWER;UNITY_6000_0_OR_NEWER;UNITY_5_3_OR_NEWER;UNITY_2017_1_OR_NEWER;UNITY_2019_1_OR_NEWER;UNITY_2020_1_OR_NEWER;UNITY_2021_1_OR_NEWER;UNITY_2022_1_OR_NEWER;UNITY_2023_1_OR_NEWER;PACKAGE_PHYSICS;PACKAGE_ANIMATION;PACKAGE_INPUTSYSTEM_DISABLED")
$ErrorActionPreference = "Stop"
$refs = New-Object 'System.Collections.Generic.List[Microsoft.CodeAnalysis.MetadataReference]'
foreach ($r in (Get-Content $RefList)) { if ($r.Trim()) { $refs.Add([Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile($r.Trim())) } }
$opts = [Microsoft.CodeAnalysis.CSharp.CSharpParseOptions]::new([Microsoft.CodeAnalysis.CSharp.LanguageVersion]::CSharp9, [Microsoft.CodeAnalysis.DocumentationMode]::None, [Microsoft.CodeAnalysis.SourceCodeKind]::Regular, [string[]]($Defines.Split(';')))
$trees = New-Object 'System.Collections.Generic.List[Microsoft.CodeAnalysis.SyntaxTree]'
foreach ($f in (Get-Content $SrcList)) { if ($f.Trim()) { $txt = [System.IO.File]::ReadAllText($f.Trim()); $trees.Add([Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText($txt, $opts, $f.Trim())) } }
$copts = [Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions]::new([Microsoft.CodeAnalysis.OutputKind]::DynamicallyLinkedLibrary).WithAllowUnsafe($true).WithNullableContextOptions([Microsoft.CodeAnalysis.NullableContextOptions]::Disable)
$comp = [Microsoft.CodeAnalysis.CSharp.CSharpCompilation]::Create($OutName, $trees, $refs, $copts)
$ms = New-Object System.IO.MemoryStream
$res = $comp.Emit($ms)
$errs = 0; $warns = 0
foreach ($d in $res.Diagnostics) {
  if ($d.Severity -eq [Microsoft.CodeAnalysis.DiagnosticSeverity]::Error) { $errs++; Write-Output ("ERR " + $d.ToString()) }
  elseif ($d.Severity -eq [Microsoft.CodeAnalysis.DiagnosticSeverity]::Warning -and $d.Id -notin @('CS0649','CS0169','CS0414','CS8019','CS1701','CS1702')) { $warns++; if ($env:SHOWWARN) { Write-Output ("WRN " + $d.ToString()) } }
}
if ($res.Success) { [System.IO.File]::WriteAllBytes("/tmp/build_$OutName.dll", $ms.ToArray()) }
Write-Output "RESULT success=$($res.Success) errors=$errs warnings=$warns"
