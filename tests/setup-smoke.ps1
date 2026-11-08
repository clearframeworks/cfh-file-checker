$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot ('setup-test-' + [guid]::NewGuid().ToString('N'))
$oldLocalAppData = $env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA = $root
    $destination = Join-Path $root 'Programs\CFH File Checker'
    $package = Split-Path -Parent $PSScriptRoot
    & (Join-Path $package 'Install.ps1') -NoLaunch -NoShortcuts
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'remote\.github\workflows\source-scan.yml'))) { throw 'Workflow missing from installation.' }
    $manifest = Get-Content -LiteralPath (Join-Path $destination 'install-manifest.json') -Raw | ConvertFrom-Json
    if (@($manifest.files).Count -lt 18) { throw 'Install manifest is incomplete.' }
    # Recreate the previous package's README exactly and exercise a manifestless upgrade.
    $readme = [IO.File]::ReadAllText((Join-Path $package 'README.txt'))
    $readme = [regex]::Replace($readme, '(?m)^Run CFH-File-Checker-Setup\.exe[^\r\n]*', 'Run Install.cmd on Windows. It installs the application in your user profile and creates a desktop shortcut. Install GitHub CLI from https://cli.github.com/ and sign in using the button. Enter a new repository name in account/name format and choose Create private workspace. GitHub Actions must be enabled on that account and may have usage or billing limits.')
    $readme = [regex]::Replace($readme, '(?m)^To uninstall, choose Uninstall CFH File Checker[^\r\n]*', 'To uninstall, delete the CFH File Checker desktop shortcut and the folder %LOCALAPPDATA%\Programs\CFH File Checker. Settings remain in %LOCALAPPDATA%\CFH File Checker; delete that folder if no longer needed. The GitHub repository and its run logs remain in your account until you remove them separately.')
    $readmePath = Join-Path $destination 'README.txt'
    [IO.File]::WriteAllText($readmePath, $readme, (New-Object Text.UTF8Encoding($false)))
    if ((Get-FileHash -LiteralPath $readmePath -Algorithm SHA256).Hash -ne '32E99A6C9879C6573EA91D713AE139FC649937B138082A467293A0B74B4FA28E') { throw 'Legacy README fixture differs from the previous package.' }
    Remove-Item -LiteralPath (Join-Path $destination 'install-manifest.json')
    & (Join-Path $package 'Install.ps1') -NoLaunch -NoShortcuts
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'install-manifest.json'))) { throw 'Legacy upgrade did not create an installation record.' }
    Remove-Item -LiteralPath (Join-Path $destination 'install-manifest.json')
    Set-Content -LiteralPath (Join-Path $destination 'README.txt') -Value 'user change'
    $blocked = $false
    try { & (Join-Path $package 'Install.ps1') -NoLaunch -NoShortcuts } catch { $blocked = $_.Exception.Message -like '*will not overwrite a changed file*' }
    if (-not $blocked) { throw 'Modified installation file was not protected.' }
    # Restore a legitimate record before testing retention on uninstall.
    Copy-Item -LiteralPath (Join-Path $package 'README.txt') -Destination $readmePath -Force
    & (Join-Path $package 'Install.ps1') -NoLaunch -NoShortcuts
    Set-Content -LiteralPath $readmePath -Value 'user change'
    Set-Content -LiteralPath (Join-Path $destination 'user-file.txt') -Value 'keep me'
    $output = & (Join-Path $destination 'Uninstall.ps1') -NoPrompt -NoShortcuts
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'README.txt'))) { throw 'Changed file was removed.' }
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'user-file.txt'))) { throw 'Unrelated file was removed.' }
    if (Test-Path -LiteralPath (Join-Path $destination 'FileChecker.ps1')) { throw 'Unchanged app file was not removed.' }
    if (($output | Out-String) -notmatch 'Changed files and the uninstall record were kept') { throw 'Retained files were not reported.' }
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'install-manifest.json')) -or -not (Test-Path -LiteralPath (Join-Path $destination 'Uninstall.ps1'))) { throw 'Recovery record or uninstaller missing.' }
    $incomplete = Join-Path $root 'incomplete-package'
    New-Item -ItemType Directory -Force -Path $incomplete | Out-Null
    Copy-Item -LiteralPath (Join-Path $package 'Install.ps1') -Destination $incomplete
    $env:LOCALAPPDATA = Join-Path $root 'other-profile'
    $badDestination = Join-Path $env:LOCALAPPDATA 'Programs\CFH File Checker'
    $blockedMissing = $false
    try { & (Join-Path $incomplete 'Install.ps1') -NoLaunch -NoShortcuts } catch { $blockedMissing = $_.Exception.Message -like 'Setup is incomplete:*' }
    if (-not $blockedMissing -or (Test-Path -LiteralPath $badDestination)) { throw 'Incomplete package was not stopped before installation.' }
    $redirectedProfile = Join-Path $root 'redirected-profile'
    $redirectTarget = Join-Path $root 'redirect-target'
    New-Item -ItemType Directory -Force -Path $redirectedProfile,$redirectTarget | Out-Null
    $junction = Join-Path $redirectedProfile 'Programs'
    New-Item -ItemType Junction -Path $junction -Target $redirectTarget | Out-Null
    $env:LOCALAPPDATA = $redirectedProfile
    $blockedRedirect = $false
    try { & (Join-Path $package 'Install.ps1') -NoLaunch -NoShortcuts } catch { $blockedRedirect = $_.Exception.Message -like '*redirected installation path*' }
    if (-not $blockedRedirect -or (Test-Path -LiteralPath (Join-Path $redirectTarget 'CFH File Checker'))) { throw 'Redirected installation path was not stopped before writing.' }
    Remove-Item -LiteralPath $junction -Force
    # Test the installer's actual shortcut validator using only a temporary .lnk.
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $package 'Install.ps1'), [ref]$null, [ref]$null)
    $func = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-ShortcutTargets' }, $true)
    if (-not $func) { throw 'Shortcut validator not found.' }
    Invoke-Expression $func.Extent.Text
    $shortcutPath = Join-Path $root 'collision.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath); $shortcut.TargetPath = 'C:\Windows\notepad.exe'; $shortcut.Save()
    $blockedShortcut = $false
    try { Assert-ShortcutTargets $shell @(@{path=$shortcutPath;target='Launch.cmd'}) $destination } catch { $blockedShortcut = $_.Exception.Message -like '*will not overwrite an existing shortcut*' }
    if (-not $blockedShortcut -or $shell.CreateShortcut($shortcutPath).TargetPath -ne 'C:\Windows\notepad.exe') { throw 'Unrelated shortcut was not preserved.' }
    Write-Output 'PASS: isolated install, missing/modified-file protection and safe uninstall'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
