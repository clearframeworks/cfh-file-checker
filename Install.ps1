param([switch]$NoLaunch, [switch]$NoShortcuts)
$ErrorActionPreference = 'Stop'
function Get-Sha256([string]$path) {
    $stream = [IO.File]::OpenRead($path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '') }
    finally { $algorithm.Dispose(); $stream.Dispose() }
}
$required = @('FileChecker.ps1','Launch.cmd','README.txt','LICENSE','Uninstall.ps1','Uninstall.cmd',
    'remote\.github\workflows\check.yml','remote\.github\workflows\workspace.yml',
    'remote\.github\workflows\archive.yml','remote\.github\workflows\source-scan.yml',
    'remote\scripts\download.py','remote\scripts\workspace.py','remote\scripts\archive.py',
    'remote\scripts\test_archive.py','remote\scripts\source_download.py',
    'remote\scripts\source_prepare.py','remote\scripts\source_report.py',
    'remote\scripts\test_source_prepare.py','remote\scripts\test_source_report.py')
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $relative) -PathType Leaf)) {
        throw "Setup is incomplete: $relative is missing. Obtain the complete File Checker package and try again."
    }
}
$destinationPath = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs\CFH File Checker')).TrimEnd('\')
if ([string]::Equals($destinationPath, [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Run setup from the downloaded package, not from its installation folder.'
}
function Assert-NoReparsePoint([string]$path) {
    $current = [IO.Path]::GetFullPath($path)
    while ($current) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Setup cannot use a redirected installation path: $current" }
        $parent = Split-Path -Parent $current
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
}
Assert-NoReparsePoint $destinationPath
foreach ($relative in $required) { Assert-NoReparsePoint (Join-Path $destinationPath $relative) }
$oldManifestPath = Join-Path $destinationPath 'install-manifest.json'
Assert-NoReparsePoint $oldManifestPath
New-Item -ItemType Directory -Force -Path $destinationPath | Out-Null
Assert-NoReparsePoint $destinationPath
foreach ($relative in $required) { Assert-NoReparsePoint (Join-Path $destinationPath $relative) }
$oldHashes = @{}
if (Test-Path -LiteralPath $oldManifestPath -PathType Leaf) {
    $oldManifest = Get-Content -LiteralPath $oldManifestPath -Raw | ConvertFrom-Json
    if ($oldManifest.version -ne 1) { throw 'The existing installation record is invalid. No files were replaced.' }
    foreach ($item in $oldManifest.files) { $oldHashes[[string]$item.path] = [string]$item.sha256 }
}
# Recognize the documented README from the previous package, which did not
# record a manifest. Any other untracked or modified file remains protected.
$legacyReadmeHash = '32E99A6C9879C6573EA91D713AE139FC649937B138082A467293A0B74B4FA28E'
foreach ($relative in $required) {
    $target = Join-Path $destinationPath $relative
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        $currentHash = Get-Sha256 $target
        $incomingHash = Get-Sha256 (Join-Path $PSScriptRoot $relative)
        $knownLegacyReadme = -not (Test-Path -LiteralPath $oldManifestPath) -and $relative -eq 'README.txt' -and $currentHash -eq $legacyReadmeHash
        if ($currentHash -ne $incomingHash -and -not $knownLegacyReadme -and (-not $oldHashes.ContainsKey($relative) -or $currentHash -ne $oldHashes[$relative])) {
            throw "Setup will not overwrite a changed file: $target. Preserve it elsewhere before retrying."
        }
    }
}
function Assert-ShortcutTargets($shell, $entries, [string]$installDirectory) {
    foreach ($entry in $entries) {
        if ((Test-Path -LiteralPath $entry.path -PathType Leaf) -and $shell.CreateShortcut($entry.path).TargetPath -ne (Join-Path $installDirectory $entry.target)) {
            throw "Setup will not overwrite an existing shortcut: $($entry.path)"
        }
    }
}
if (-not $NoShortcuts) {
    $shell = New-Object -ComObject WScript.Shell
    $menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'CFH File Checker'
    $entries = @(
        @{ path=(Join-Path ([Environment]::GetFolderPath('Desktop')) 'CFH File Checker.lnk'); target='Launch.cmd' },
        @{ path=(Join-Path $menu 'CFH File Checker.lnk'); target='Launch.cmd' },
        @{ path=(Join-Path $menu 'Uninstall CFH File Checker.lnk'); target='Uninstall.cmd' }
    )
    Assert-ShortcutTargets $shell $entries $destinationPath
}
$installed = @()
foreach ($relative in $required) {
    $target = Join-Path $destinationPath $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $relative) -Destination $target -Force
    $installed += [pscustomobject]@{ path=$relative; sha256=(Get-Sha256 $target) }
}
@{ version=1; files=$installed } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $destinationPath 'install-manifest.json') -Encoding UTF8
if (-not $NoShortcuts) {
    New-Item -ItemType Directory -Force -Path $menu | Out-Null
    foreach ($entry in $entries) {
        $shortcut = $shell.CreateShortcut($entry.path)
        $shortcut.TargetPath = Join-Path $destinationPath $entry.target
        $shortcut.WorkingDirectory = $destinationPath
        $shortcut.Save()
    }
}
Write-Output "CFH File Checker installed in $destinationPath"
if (-not (Get-Command gh.exe -ErrorAction SilentlyContinue)) { Write-Output 'GitHub CLI is needed to connect a workspace. Open File Checker and choose Install GitHub CLI.' }
if (-not $NoLaunch) { Start-Process (Join-Path $destinationPath 'Launch.cmd') }
