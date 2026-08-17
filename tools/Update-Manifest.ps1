[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$clientRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'client'))
$manifestPath = Join-Path $repoRoot 'manifest.json'
$deletedPathFile = Join-Path $repoRoot 'deleted-paths.txt'
$bootstrapPath = Join-Path $repoRoot 'launcher\Gamnina2000Launcher.exe'
$coreLauncherPath = Join-Path $repoRoot 'launcher\Gamnina2000Core.exe'
$launcherChannelPath = Join-Path $repoRoot 'launcher\channel.txt'
$launcherChecksumsPath = Join-Path $repoRoot 'launcher\SHA256SUMS.txt'
$allowedDirectoryRoots = @(
    'mods', 'config', 'defaultconfigs', 'resourcepacks', 'shaderpacks',
    'kubejs', 'resources', 'oresources', 'fontfiles'
)
$allowedRootFiles = @('servers.dat')
$githubHardFileLimit = 100MB
$githubWarningFileLimit = 50MB

if (-not (Test-Path -LiteralPath $clientRoot -PathType Container)) {
    throw "Client folder was not found: $clientRoot"
}

$previousPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$previousDeletedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $previous = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in @($previous.files)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.path)) {
            $null = $previousPaths.Add(([string]$entry.path).Replace('\', '/'))
        }
    }
    foreach ($oldPath in @($previous.deletedPaths)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$oldPath)) {
            $null = $previousDeletedPaths.Add(([string]$oldPath).Replace('\', '/'))
        }
    }
}

$files = [Collections.Generic.List[object]]::new()
$currentPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$clientPrefix = $clientRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$warnings = [Collections.Generic.List[string]]::new()

foreach ($file in Get-ChildItem -LiteralPath $clientRoot -Recurse -File | Sort-Object FullName) {
    $relative = $file.FullName.Substring($clientPrefix.Length).Replace('\', '/')
    $segments = $relative.Split('/')
    $root = $segments[0]
    $isAllowed = ($segments.Count -eq 1 -and $root -in $allowedRootFiles) -or
                 ($segments.Count -gt 1 -and $root -in $allowedDirectoryRoots)
    if (-not $isAllowed) {
        throw "Unsupported file in client/: $relative"
    }
    if ($file.Length -ge $githubHardFileLimit) {
        throw "GitHub rejects files of 100 MiB or larger: $relative"
    }
    if ($file.Length -ge $githubWarningFileLimit) {
        $warnings.Add("Large file (GitHub will show a warning): $relative - $([math]::Round($file.Length / 1MB, 1)) MiB")
    }

    $null = $currentPaths.Add($relative)
    $escapedRelative = ($segments | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $files.Add([ordered]@{
        path = $relative
        url = "client/$escapedRelative"
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        size = [long]$file.Length
    })
}

$deleted = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($oldPath in $previousDeletedPaths) {
    if (-not $currentPaths.Contains($oldPath)) {
        $null = $deleted.Add($oldPath)
    }
}
foreach ($oldPath in $previousPaths) {
    if (-not $currentPaths.Contains($oldPath)) {
        $null = $deleted.Add($oldPath)
    }
}
if (Test-Path -LiteralPath $deletedPathFile -PathType Leaf) {
    foreach ($line in Get-Content -LiteralPath $deletedPathFile -Encoding UTF8) {
        $value = $line.Trim().Replace('\', '/')
        if ($value.Length -eq 0 -or $value.StartsWith('#')) { continue }
        if ($currentPaths.Contains($value)) {
            throw "Path is present in both client/ and deleted-paths.txt: $value"
        }
        $null = $deleted.Add($value)
    }
}

$version = 'gamnina-2000-' + [DateTime]::UtcNow.ToString('yyyy.MM.dd-HHmmss')
$manifest = [ordered]@{
    schemaVersion = 2
    version = $version
    bundleResource = ''
    files = @($files)
    deletedPaths = @($deleted | Sort-Object)
}
$json = $manifest | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($manifestPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

# The 1.20.1 porting lab is a completely separate launcher profile. Generate
# its manifest in the same one-click operation so old and modern mods can
# never be mixed in one game directory.
$modernProfileRoot = Join-Path $repoRoot 'profiles\forge-1.20.1'
$modernClientRoot = Join-Path $modernProfileRoot 'client'
$modernManifestPath = Join-Path $modernProfileRoot 'manifest.json'
if (-not (Test-Path -LiteralPath $modernClientRoot -PathType Container)) {
    throw "Forge 1.20.1 client folder was not found: $modernClientRoot"
}

$modernPreviousPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$modernPreviousDeleted = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if (Test-Path -LiteralPath $modernManifestPath -PathType Leaf) {
    $modernPrevious = Get-Content -LiteralPath $modernManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in @($modernPrevious.files)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.path)) {
            $null = $modernPreviousPaths.Add(([string]$entry.path).Replace('\', '/'))
        }
    }
    foreach ($oldPath in @($modernPrevious.deletedPaths)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$oldPath)) {
            $null = $modernPreviousDeleted.Add(([string]$oldPath).Replace('\', '/'))
        }
    }
}

$modernFiles = [Collections.Generic.List[object]]::new()
$modernCurrentPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$modernPrefix = $modernClientRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
foreach ($file in Get-ChildItem -LiteralPath $modernClientRoot -Recurse -File | Sort-Object FullName) {
    if ($file.Name -eq '.gitkeep') { continue }
    $relative = $file.FullName.Substring($modernPrefix.Length).Replace('\', '/')
    $segments = $relative.Split('/')
    $root = $segments[0]
    $isAllowed = ($segments.Count -eq 1 -and $root -in $allowedRootFiles) -or
                 ($segments.Count -gt 1 -and $root -in $allowedDirectoryRoots)
    if (-not $isAllowed) { throw "Unsupported file in Forge 1.20.1 client/: $relative" }
    if ($file.Length -ge $githubHardFileLimit) { throw "GitHub rejects files of 100 MiB or larger: $relative" }
    if ($file.Length -ge $githubWarningFileLimit) {
        $warnings.Add("Large Forge 1.20.1 file: $relative - $([math]::Round($file.Length / 1MB, 1)) MiB")
    }

    $null = $modernCurrentPaths.Add($relative)
    $escapedRelative = ($segments | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $modernFiles.Add([ordered]@{
        path = $relative
        url = "profiles/forge-1.20.1/client/$escapedRelative"
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        size = [long]$file.Length
    })
}

$modernDeleted = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($oldPath in $modernPreviousDeleted) {
    if (-not $modernCurrentPaths.Contains($oldPath)) { $null = $modernDeleted.Add($oldPath) }
}
foreach ($oldPath in $modernPreviousPaths) {
    if (-not $modernCurrentPaths.Contains($oldPath)) { $null = $modernDeleted.Add($oldPath) }
}
$modernVersion = 'gamnina-portlab-1.20.1-' + [DateTime]::UtcNow.ToString('yyyy.MM.dd-HHmmss')
$modernManifest = [ordered]@{
    schemaVersion = 2
    version = $modernVersion
    bundleResource = ''
    files = @($modernFiles)
    deletedPaths = @($modernDeleted | Sort-Object)
}
$modernJson = $modernManifest | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($modernManifestPath, $modernJson + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) {
    throw "Bootstrap launcher was not found: $bootstrapPath"
}
if (-not (Test-Path -LiteralPath $coreLauncherPath -PathType Leaf)) {
    throw "Core launcher was not found: $coreLauncherPath"
}
$bootstrapItem = Get-Item -LiteralPath $bootstrapPath
$coreLauncherItem = Get-Item -LiteralPath $coreLauncherPath
if ($bootstrapItem.Length -ge $githubHardFileLimit -or $coreLauncherItem.Length -ge $githubHardFileLimit) {
    throw 'A launcher executable exceeds the GitHub 100 MiB file limit.'
}
$bootstrapHash = (Get-FileHash -LiteralPath $bootstrapPath -Algorithm SHA256).Hash.ToLowerInvariant()
$coreLauncherHash = (Get-FileHash -LiteralPath $coreLauncherPath -Algorithm SHA256).Hash.ToLowerInvariant()
$coreLauncherVersion = $coreLauncherItem.VersionInfo.FileVersion
$channelText = @(
    'schema=1'
    "version=$coreLauncherVersion"
    'url=https://raw.githubusercontent.com/dopamineboss-lgtm/gamnina-2000-pack/main/launcher/Gamnina2000Core.exe'
    "sha256=$coreLauncherHash"
    "size=$($coreLauncherItem.Length)"
) -join "`n"
[IO.File]::WriteAllText($launcherChannelPath, $channelText + "`n", [Text.UTF8Encoding]::new($false))
$launcherChecksums = @(
    "$bootstrapHash  Gamnina2000Launcher.exe"
    "$coreLauncherHash  Gamnina2000Core.exe"
) -join "`n"
[IO.File]::WriteAllText($launcherChecksumsPath, $launcherChecksums + "`n", [Text.UTF8Encoding]::new($false))

$totalBytes = ($files | ForEach-Object { [long]$_['size'] } | Measure-Object -Sum).Sum
Write-Host "Manifest updated: $version" -ForegroundColor Green
Write-Host "Files: $($files.Count); deletions: $($deleted.Count); size: $([math]::Round($totalBytes / 1MB, 1)) MiB"
Write-Host "Forge 1.20.1 manifest: $modernVersion; files: $($modernFiles.Count); deletions: $($modernDeleted.Count)" -ForegroundColor Cyan
Write-Host "Bootstrap: $([math]::Round($bootstrapItem.Length / 1KB, 1)) KiB; core launcher: $([math]::Round($coreLauncherItem.Length / 1MB, 1)) MiB"
foreach ($warning in $warnings) { Write-Warning $warning }
