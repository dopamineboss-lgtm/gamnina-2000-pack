[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$clientRoot = Join-Path $repoRoot 'client'
$manifestPath = Join-Path $repoRoot 'manifest.json'
$launcherPath = Join-Path $repoRoot 'launcher\Gamnina2000Launcher.exe'
$coreLauncherPath = Join-Path $repoRoot 'launcher\Gamnina2000Core.exe'
$launcherChannelPath = Join-Path $repoRoot 'launcher\channel.txt'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'manifest.json was not found.' }
if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) { throw 'launcher/Gamnina2000Launcher.exe was not found.' }
if (-not (Test-Path -LiteralPath $coreLauncherPath -PathType Leaf)) { throw 'launcher/Gamnina2000Core.exe was not found.' }
if (-not (Test-Path -LiteralPath $launcherChannelPath -PathType Leaf)) { throw 'launcher/channel.txt was not found.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$manifest.schemaVersion -ne 2) { throw 'schemaVersion must be 2.' }
if (@($manifest.files).Count -eq 0) { throw 'Manifest contains no files.' }

$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$clientPrefix = [IO.Path]::GetFullPath($clientRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
foreach ($entry in @($manifest.files)) {
    $relative = ([string]$entry.path).Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not $seen.Add($relative)) { throw "Duplicate manifest path: $relative" }
    $target = [IO.Path]::GetFullPath((Join-Path $clientRoot $relative))
    if (-not $target.StartsWith($clientPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes client/: $relative" }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "File is missing: $relative" }
    $item = Get-Item -LiteralPath $target
    if ($item.Length -ne [long]$entry.size) { throw "Incorrect size: $relative" }
    $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne ([string]$entry.sha256).ToLowerInvariant()) { throw "Incorrect SHA-256: $relative" }
    if ($item.Length -ge 100MB) { throw "File exceeds GitHub's 100 MiB limit: $relative" }
}

$actualFiles = @(Get-ChildItem -LiteralPath $clientRoot -Recurse -File)
if ($actualFiles.Count -ne $seen.Count) {
    throw "File count differs: client=$($actualFiles.Count), manifest=$($seen.Count). Run the manifest update command."
}

$modernClientRoot = Join-Path $repoRoot 'profiles\forge-1.20.1\client'
$modernManifestPath = Join-Path $repoRoot 'profiles\forge-1.20.1\manifest.json'
if (-not (Test-Path -LiteralPath $modernClientRoot -PathType Container)) { throw 'Forge 1.20.1 client folder was not found.' }
if (-not (Test-Path -LiteralPath $modernManifestPath -PathType Leaf)) { throw 'Forge 1.20.1 manifest was not found.' }
$modernManifest = Get-Content -LiteralPath $modernManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$modernManifest.schemaVersion -ne 2) { throw 'Forge 1.20.1 schemaVersion must be 2.' }
$modernSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$modernPrefix = [IO.Path]::GetFullPath($modernClientRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
foreach ($entry in @($modernManifest.files)) {
    $relative = ([string]$entry.path).Replace('/', [IO.Path]::DirectorySeparatorChar)
    if (-not $modernSeen.Add($relative)) { throw "Duplicate Forge 1.20.1 manifest path: $relative" }
    $target = [IO.Path]::GetFullPath((Join-Path $modernClientRoot $relative))
    if (-not $target.StartsWith($modernPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Forge 1.20.1 path escapes client/: $relative" }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Forge 1.20.1 file is missing: $relative" }
    $item = Get-Item -LiteralPath $target
    if ($item.Length -ne [long]$entry.size) { throw "Incorrect Forge 1.20.1 size: $relative" }
    $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne ([string]$entry.sha256).ToLowerInvariant()) { throw "Incorrect Forge 1.20.1 SHA-256: $relative" }
    if ($item.Length -ge 100MB) { throw "Forge 1.20.1 file exceeds GitHub's limit: $relative" }
}
$modernActualFiles = @(Get-ChildItem -LiteralPath $modernClientRoot -Recurse -File | Where-Object { $_.Name -ne '.gitkeep' })
if ($modernActualFiles.Count -ne $modernSeen.Count) {
    throw "Forge 1.20.1 file count differs: client=$($modernActualFiles.Count), manifest=$($modernSeen.Count)."
}
$launcher = Get-Item -LiteralPath $launcherPath
$coreLauncher = Get-Item -LiteralPath $coreLauncherPath
if ($launcher.Length -ge 100MB -or $coreLauncher.Length -ge 100MB) { throw 'A launcher executable exceeds GitHub hard file limit.' }
$channel = @{}
foreach ($line in Get-Content -LiteralPath $launcherChannelPath -Encoding UTF8) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
    $separator = $line.IndexOf('=')
    if ($separator -le 0) { throw 'Invalid launcher/channel.txt line.' }
    $channel[$line.Substring(0, $separator)] = $line.Substring($separator + 1)
}
if ($channel['schema'] -ne '1') { throw 'Invalid launcher channel schema.' }
if ([long]$channel['size'] -ne $coreLauncher.Length) { throw 'Core launcher channel size mismatch.' }
$coreHash = (Get-FileHash -LiteralPath $coreLauncherPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($channel['sha256'] -ne $coreHash) { throw 'Core launcher channel SHA-256 mismatch.' }
if ($channel['url'] -ne 'https://raw.githubusercontent.com/dopamineboss-lgtm/gamnina-2000-pack/main/launcher/Gamnina2000Core.exe') {
    throw 'Unexpected core launcher URL.'
}

Write-Host 'VERIFICATION PASSED' -ForegroundColor Green
Write-Host "Version: $($manifest.version)"
Write-Host "Client files: $($seen.Count)"
Write-Host "Forge 1.20.1 files: $($modernSeen.Count)"
Write-Host "Bootstrap: $([math]::Round($launcher.Length / 1KB, 1)) KiB"
Write-Host "Core launcher: $([math]::Round($coreLauncher.Length / 1MB, 1)) MiB"
