param([string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'))
$ErrorActionPreference = 'Stop'
$package = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw '.NET Framework C# compiler not found.' }
$files = @('Install.ps1','FileChecker.ps1','Launch.cmd','README.txt','LICENSE','Uninstall.ps1','Uninstall.cmd',
    'remote\.github\workflows\check.yml','remote\.github\workflows\workspace.yml',
    'remote\.github\workflows\archive.yml','remote\.github\workflows\source-scan.yml',
    'remote\scripts\download.py','remote\scripts\workspace.py','remote\scripts\archive.py',
    'remote\scripts\test_archive.py','remote\scripts\source_download.py',
    'remote\scripts\source_prepare.py','remote\scripts\source_report.py',
    'remote\scripts\test_source_prepare.py','remote\scripts\test_source_report.py')
foreach ($file in $files) { if (-not (Test-Path -LiteralPath (Join-Path $package $file) -PathType Leaf)) { throw "Missing package file: $file" } }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$zipPath = Join-Path $OutputDirectory ('payload-' + [guid]::NewGuid().ToString('N') + '.zip')
try {
    $archive = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try { foreach ($file in $files) { [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $package $file), $file.Replace('\','/')) | Out-Null } }
    finally { $archive.Dispose() }
    $exe = Join-Path $OutputDirectory 'CFH-File-Checker-Setup.exe'
    & $compiler /nologo /target:winexe /platform:anycpu /optimize+ "/out:$exe" "/resource:$zipPath,payload.zip" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll (Join-Path $PSScriptRoot 'Setup.cs')
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Setup compilation failed.' }
    Get-FileHash -LiteralPath $exe -Algorithm SHA256
} finally { if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force } }
