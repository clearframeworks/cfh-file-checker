param([switch]$NoPrompt, [switch]$NoShortcuts)
$ErrorActionPreference = 'Stop'
function Get-Sha256([string]$path) {
    $stream = [IO.File]::OpenRead($path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '') }
    finally { $algorithm.Dispose(); $stream.Dispose() }
}
if (-not $NoPrompt) {
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [Windows.Forms.MessageBox]::Show('Remove CFH File Checker from this PC? Your settings, GitHub repository and run history will be kept.', 'Uninstall CFH File Checker', 'YesNo', 'Question')
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { exit 0 }
}
$destinationPath = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs\CFH File Checker')).TrimEnd('\')
$manifestPath = Join-Path $destinationPath 'install-manifest.json'
function Assert-NoReparsePoint([string]$path) {
    $current = [IO.Path]::GetFullPath($path)
    while ($current) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Uninstall cannot use a redirected installation path: $current" }
        $parent = Split-Path -Parent $current
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
}
Assert-NoReparsePoint $manifestPath
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'The installation record is missing. No files were removed.' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.version -ne 1 -or -not $manifest.files) { throw 'The installation record is invalid. No files were removed.' }
$retained = New-Object System.Collections.Generic.List[string]
$targets = @()
foreach ($item in $manifest.files) {
    $relative = [string]$item.path
    if (-not $relative -or [IO.Path]::IsPathRooted($relative)) { throw 'The installation record contains an invalid path. Stopped without removing further files.' }
    $target = [IO.Path]::GetFullPath((Join-Path $destinationPath $relative))
    if (-not $target.StartsWith($destinationPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'The installation record contains an invalid path. Stopped without removing further files.' }
    Assert-NoReparsePoint $target
    $targets += [pscustomobject]@{ relative=$relative; target=$target; sha256=$item.sha256 }
}
foreach ($item in $targets) {
    $target = $item.target
    if ((Test-Path -LiteralPath $target -PathType Leaf) -and (Get-Sha256 $target) -ne $item.sha256) { $retained.Add($item.relative) }
}
foreach ($item in $targets) {
    if ($retained.Count -and $item.relative -in @('Uninstall.ps1','Uninstall.cmd')) { continue }
    if ((Test-Path -LiteralPath $item.target -PathType Leaf) -and (Get-Sha256 $item.target) -eq $item.sha256) { Remove-Item -LiteralPath $item.target -Force }
}
if (-not $NoShortcuts) {
    $shell = New-Object -ComObject WScript.Shell
    $menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'CFH File Checker'
    foreach ($shortcutPath in @((Join-Path ([Environment]::GetFolderPath('Desktop')) 'CFH File Checker.lnk'), (Join-Path $menu 'CFH File Checker.lnk'), (Join-Path $menu 'Uninstall CFH File Checker.lnk'))) {
        if ($retained.Count -and $shortcutPath -eq (Join-Path $menu 'Uninstall CFH File Checker.lnk')) { continue }
        if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) {
            $target = $shell.CreateShortcut($shortcutPath).TargetPath
            if ($target -eq (Join-Path $destinationPath 'Launch.cmd') -or $target -eq (Join-Path $destinationPath 'Uninstall.cmd')) { Remove-Item -LiteralPath $shortcutPath -Force }
        }
    }
    if ((Test-Path -LiteralPath $menu -PathType Container) -and -not (Get-ChildItem -LiteralPath $menu -Force)) { Remove-Item -LiteralPath $menu }
}
if (-not $retained.Count) { Remove-Item -LiteralPath $manifestPath -Force }
@('remote\.github\workflows','remote\.github','remote\scripts','remote') | ForEach-Object {
    $directory = Join-Path $destinationPath $_
    if ((Test-Path -LiteralPath $directory -PathType Container) -and -not (Get-ChildItem -LiteralPath $directory -Force)) { Remove-Item -LiteralPath $directory }
}
if (-not (Get-ChildItem -LiteralPath $destinationPath -Force)) { Remove-Item -LiteralPath $destinationPath }
$message = 'CFH File Checker files were removed. Your settings and GitHub workspace were kept.'
if ($retained.Count) { $message += "`r`nChanged files and the uninstall record were kept in the installation folder: " + ($retained -join ', ') }
Write-Output $message
if (-not $NoPrompt) { [Windows.Forms.MessageBox]::Show($message, 'CFH File Checker') | Out-Null }
