$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot ('single-setup-test-' + [guid]::NewGuid().ToString('N'))
$oldLocalAppData = $env:LOCALAPPDATA
try {
    New-Item -ItemType Directory -Path $root | Out-Null
    $env:LOCALAPPDATA = $root
    $package = Split-Path -Parent $PSScriptRoot
    $setup = Join-Path $package 'dist\CFH-File-Checker-Setup.exe'
    $process = Start-Process -FilePath $setup -ArgumentList '--silent','--no-shortcuts' -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Single-file setup failed with exit code $($process.ExitCode)." }
    $installed = Join-Path $root 'Programs\CFH File Checker'
    $expected = Get-FileHash -LiteralPath (Join-Path $package 'FileChecker.ps1') -Algorithm SHA256
    $actual = Get-FileHash -LiteralPath (Join-Path $installed 'FileChecker.ps1') -Algorithm SHA256
    if ($expected.Hash -ne $actual.Hash -or -not (Test-Path -LiteralPath (Join-Path $installed 'remote\.github\workflows\source-scan.yml'))) { throw 'Installed payload does not match package.' }
    Set-Content -LiteralPath (Join-Path $installed 'README.txt') -Value 'keep my edit'
    $retry = Start-Process -FilePath $setup -ArgumentList '--silent','--no-shortcuts' -WindowStyle Hidden -Wait -PassThru
    if ($retry.ExitCode -eq 0 -or (Get-Content -LiteralPath (Join-Path $installed 'README.txt') -Raw) -notmatch 'keep my edit') { throw 'Setup overwrote a changed file or failed to report the conflict.' }
    Copy-Item -LiteralPath (Join-Path $package 'README.txt') -Destination (Join-Path $installed 'README.txt') -Force
    & (Join-Path $installed 'Uninstall.ps1') -NoPrompt -NoShortcuts | Out-Null
    if (Test-Path -LiteralPath $installed) { throw 'Uninstall did not remove the unchanged installation.' }
    Write-Output 'PASS: single-file setup installs exact payload and uninstalls headlessly'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
