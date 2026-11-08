Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$ErrorActionPreference = 'Stop'
$configDir = Join-Path $env:LOCALAPPDATA 'CFH File Checker'
$configFile = Join-Path $configDir 'settings.json'
New-Item -ItemType Directory -Force $configDir | Out-Null

function Invoke-Gh([string[]]$arguments, [string]$inputText = $null) {
    $gh = Get-Command gh.exe -ErrorAction SilentlyContinue
    if (-not $gh) { throw 'GitHub CLI is not installed. Use Install GitHub CLI below, then restart the app.' }
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($null -ne $inputText) { $output = $inputText | & $gh.Source @arguments 2>&1 }
        else { $output = & $gh.Source @arguments 2>&1 }
    } finally { $ErrorActionPreference = $previousPreference }
    if ($LASTEXITCODE -ne 0) { throw (($output | Out-String).Trim()) }
    return (($output | Out-String).Trim())
}
function Add-Text($parent, $text, $x, $y, $width, $height) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text; $label.SetBounds($x,$y,$width,$height); $parent.Controls.Add($label); return $label
}
function Add-Button($parent, $text, $x, $y, $width, $handler) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text; $button.SetBounds($x,$y,$width,34); $button.Add_Click($handler); $parent.Controls.Add($button)
}
function Show-Status([string]$message) { $status.Text = $message; $status.Refresh() }
function Show-Failure($err) { Show-Status ('Could not finish: ' + $err.Exception.Message) }
$form = New-Object System.Windows.Forms.Form
$form.Text = 'CFH File Checker'; $form.ClientSize = New-Object System.Drawing.Size(720,625)
$form.StartPosition = 'CenterScreen'; $form.MinimumSize = New-Object System.Drawing.Size(736,619)
$form.Font = New-Object System.Drawing.Font('Segoe UI',10)
$title = Add-Text $form 'Check a file without downloading it to this PC' 22 18 670 32
$title.Font = New-Object System.Drawing.Font('Segoe UI',15,[System.Drawing.FontStyle]::Bold)
$null = Add-Text $form 'Files are downloaded to a temporary GitHub-hosted runner and scanned with ClamAV. This does not prove a file is safe. Only public HTTPS links are supported.' 24 57 670 56
$null = Add-Text $form 'Private GitHub repository' 24 126 220 25
$repo = New-Object System.Windows.Forms.TextBox; $repo.SetBounds(24,151,410,28); $form.Controls.Add($repo)
if (Test-Path $configFile) { try { $repo.Text = (Get-Content -Raw $configFile | ConvertFrom-Json).repository } catch {} }
Add-Button $form 'Create private workspace' 448 148 244 {
    try {
        if ($repo.Text -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Enter a repository as account/name, for example my-account/cfh-file-checker.' }
        Show-Status 'Setting up the private GitHub repository. Please wait...'
        $exists = $true
        try { $null = Invoke-Gh @('repo','view',$repo.Text,'--json','name') } catch { $exists = $false }
        if (-not $exists) { $null = Invoke-Gh @('repo','create',$repo.Text,'--private') }
        $visibility = Invoke-Gh @('repo','view',$repo.Text,'--json','visibility','--jq','.visibility')
        if ($visibility -ne 'PRIVATE') { throw 'The repository is not private. No files were uploaded.' }
        $markerPath = '.cfh-file-checker-workspace'
        $markerBytes = [Text.Encoding]::UTF8.GetBytes('CFH File Checker workspace version 1')
        if ($exists) {
            try { $marker = Invoke-Gh @('api',("repos/{0}/contents/{1}" -f $repo.Text,$markerPath),'--jq','.content') } catch { throw 'Existing repository is not marked as a File Checker workspace. Choose a new repository name.' }
            if ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($marker)) -ne 'CFH File Checker workspace version 1') { throw 'Existing workspace marker does not match.' }
        } else {
            $payload = @{message='Initialize CFH File Checker';content=[Convert]::ToBase64String($markerBytes)} | ConvertTo-Json -Compress
            $null = Invoke-Gh @('api','--method','PUT',("repos/{0}/contents/{1}" -f $repo.Text,$markerPath),'--input','-') $payload
        }
        foreach ($item in @(@('.github/workflows/check.yml','remote/.github/workflows/check.yml'),@('scripts/download.py','remote/scripts/download.py'),@('.github/workflows/workspace.yml','remote/.github/workflows/workspace.yml'),@('scripts/workspace.py','remote/scripts/workspace.py'),@('.github/workflows/archive.yml','remote/.github/workflows/archive.yml'),@('scripts/archive.py','remote/scripts/archive.py'),@('scripts/test_archive.py','remote/scripts/test_archive.py'),@('.github/workflows/source-scan.yml','remote/.github/workflows/source-scan.yml'),@('scripts/source_download.py','remote/scripts/source_download.py'),@('scripts/source_prepare.py','remote/scripts/source_prepare.py'),@('scripts/source_report.py','remote/scripts/source_report.py'),@('scripts/test_source_prepare.py','remote/scripts/test_source_prepare.py'),@('scripts/test_source_report.py','remote/scripts/test_source_report.py'))) {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $item[1]))
            $existingContent = $null
            try { $existingContent = Invoke-Gh @('api',("repos/{0}/contents/{1}" -f $repo.Text,$item[0]),'--jq','.content') } catch {}
            if ($existingContent) {
                if ([Convert]::ToBase64String([Convert]::FromBase64String($existingContent)) -ne [Convert]::ToBase64String($bytes)) {
                    $existingSha = Invoke-Gh @('api',("repos/{0}/contents/{1}" -f $repo.Text,$item[0]),'--jq','.sha')
                    if ($item[0] -ne 'scripts/download.py' -or $existingSha -ne '6daf334f25e18f8b6e0ea2854aacac39fdb1235f') { throw ('Existing file differs: ' + $item[0] + '. No files were overwritten.') }
                    $payload = @{message='Update bounded downloader';sha=$existingSha;content=[Convert]::ToBase64String($bytes)} | ConvertTo-Json -Compress
                    $null = Invoke-Gh @('api','--method','PUT',("repos/{0}/contents/{1}" -f $repo.Text,$item[0]),'--input','-') $payload
                }
                continue
            }
            $payload = @{ message = 'Add remote file checking'; content = [Convert]::ToBase64String($bytes) } | ConvertTo-Json -Compress
            $null = Invoke-Gh @('api','--method','PUT',("repos/{0}/contents/{1}" -f $repo.Text,$item[0]),'--input','-') $payload
        }
        @{repository=$repo.Text} | ConvertTo-Json | Set-Content -Encoding UTF8 $configFile
        Show-Status 'Private workspace created. Enter a public download link below.'
    } catch { Show-Failure $_; $status.AppendText("`r`nRetry setup to resume a marked workspace. If creation failed before its marker was added, choose a new repository name.") }
}
$null = Add-Text $form 'Public HTTPS file link' 24 207 300 25
$url = New-Object System.Windows.Forms.TextBox; $url.SetBounds(24,232,668,28); $form.Controls.Add($url)
$null = Add-Text $form 'Links and scan logs are visible to people with access to your repository. Avoid links containing passwords or private tokens.' 24 268 670 42
Add-Button $form 'Start remote check' 24 316 205 {
    try {
        if ($repo.Text -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Enter your private repository as account/name.' }
        $parsed = $null
        if (-not [Uri]::TryCreate($url.Text,[UriKind]::Absolute,[ref]$parsed) -or $parsed.Scheme -ne 'https' -or $parsed.UserInfo -or -not $parsed.IsDefaultPort) { throw 'Enter a public HTTPS link without credentials or a custom port.' }
        Show-Status 'Checking workspace and starting the remote job...'
        $visibility = Invoke-Gh @('repo','view',$repo.Text,'--json','visibility','--jq','.visibility')
        if ($visibility -ne 'PRIVATE') { throw 'The workspace must be private.' }
        $requestId = [guid]::NewGuid().ToString('N')
        $null = Invoke-Gh @('workflow','run','check.yml','--repo',$repo.Text,'-f',('url='+$url.Text),'-f',('request_id='+$requestId))
        $script:lastRequest = $requestId; $script:lastWorkflow = 'check.yml'; $script:lastPrefix = 'Check '
        Show-Status ('Check submitted. Request ' + $requestId + '. Select Check result in about a minute.')
    } catch { Show-Failure $_ }
}
Add-Button $form 'Check result' 243 316 160 {
    try {
        if (-not $script:lastRequest) { throw 'Start a check first in this session. Older checks are available on GitHub.' }
        Show-Status 'Getting the remote result...'
        $raw = Invoke-Gh @('run','list','--repo',$repo.Text,'--workflow',$script:lastWorkflow,'--limit','30','--json','databaseId,displayTitle,status,conclusion,url')
        $runs = ConvertFrom-Json -InputObject $raw
        $run = @($runs) | Where-Object { $_.displayTitle -eq ($script:lastPrefix + $script:lastRequest) } | Select-Object -First 1
        if (-not $run) { Show-Status 'GitHub has not listed this check yet. Try again shortly.'; return }
        if ($run.status -ne 'completed') { Show-Status ('Check is ' + $run.status + '. Try again shortly. ' + $run.url); return }
        if ($script:lastWorkflow -eq 'archive.yml' -and $run.conclusion -eq 'success') { $script:lastArchiveRun = [string]$run.databaseId; $script:lastArchiveRequest = $script:lastRequest; $script:lastArchiveRepo = $repo.Text }
        $logs = Invoke-Gh @('run','view',[string]$run.databaseId,'--repo',$repo.Text,'--log')
        $result = ($logs -split "`n" | Where-Object { $_ -match 'Z RESULT: ' } | Select-Object -Last 1)
        if ($result -match 'Z RESULT: (.*)$') { $result = $Matches[1] } else { $result = 'No scan result was produced. Open the run on GitHub to inspect the failure.' }
        Show-Status ($result + "`r`n" + $run.url)
    } catch { Show-Failure $_ }
}
Add-Button $form 'Open GitHub runs' 417 316 170 {
    if ($repo.Text -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { Start-Process ('https://github.com/' + $repo.Text + '/actions') }
}
$null = Add-Text $form 'Status' 24 372 300 25
$status = New-Object System.Windows.Forms.TextBox; $status.SetBounds(24,399,668,92); $status.Multiline=$true; $status.ReadOnly=$true; $status.ScrollBars='Vertical'; $form.Controls.Add($status)
if ($repo.Text) { Show-Status ('Workspace: ' + $repo.Text + '. Enter a public file link to start a remote check.') } else { Show-Status 'Sign in to GitHub CLI, enter account/name, then create your private workspace.' }
Add-Button $form 'Sign in to GitHub' 24 510 180 { Start-Process powershell.exe -ArgumentList '-NoExit','-Command','gh auth login --web' }
Add-Button $form 'Install GitHub CLI' 215 510 180 { Start-Process 'https://cli.github.com/' }
Add-Button $form 'Help' 406 510 100 { Start-Process (Join-Path $PSScriptRoot 'README.txt') }
function Start-WorkspaceAction([string]$operation) {
    try {
        if ($repo.Text -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Enter your private repository as account/name.' }
        if ($script:workspaceName.Text -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$') { throw 'Enter a simple filename using letters, numbers, dots, hyphens or underscores.' }
        if ($operation -eq 'import') {
            $parsed = $null
            if (-not [Uri]::TryCreate($script:workspaceUrl.Text,[UriKind]::Absolute,[ref]$parsed) -or $parsed.Scheme -ne 'https' -or $parsed.UserInfo -or -not $parsed.IsDefaultPort) { throw 'Enter a public HTTPS link without credentials or a custom port.' }
        }
        if ($operation -eq 'replace' -and -not $script:workspaceFind.Text) { throw 'Enter text to find.' }
        if ($operation -eq 'append' -and -not $script:workspaceReplacement.Text) { throw 'Enter text to append.' }
        Show-Status 'Starting the remote workspace operation...'
        if ((Invoke-Gh @('repo','view',$repo.Text,'--json','visibility','--jq','.visibility')) -ne 'PRIVATE') { throw 'The workspace must be private.' }
        $requestId = [guid]::NewGuid().ToString('N')
        $argsList = @('workflow','run','workspace.yml','--repo',$repo.Text,'-f',('operation='+$operation),'-f',('filename='+$script:workspaceName.Text),'-f',('request_id='+$requestId))
        if ($operation -eq 'import') { $argsList += @('-f',('url='+$script:workspaceUrl.Text)) }
        if ($operation -eq 'replace') { $argsList += @('-f',('find='+$script:workspaceFind.Text),'-f',('replacement='+$script:workspaceReplacement.Text)) }
        if ($operation -eq 'append') { $argsList += @('-f',('replacement='+$script:workspaceReplacement.Text)) }
        $null = Invoke-Gh $argsList
        $script:lastRequest = $requestId; $script:lastWorkflow = 'workspace.yml'; $script:lastPrefix = 'Workspace '
        $script:workspaceForm.Close()
        Show-Status 'Workspace operation submitted. Choose Check result to see its outcome.'
    } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Could not start operation') | Out-Null }
}
Add-Button $form 'Text workspace' 520 510 172 {
    $script:workspaceForm = New-Object System.Windows.Forms.Form
    $script:workspaceForm.Text = 'Remote text workspace'; $script:workspaceForm.ClientSize = New-Object System.Drawing.Size(690,490)
    $script:workspaceForm.StartPosition = 'CenterParent'; $script:workspaceForm.Font = $form.Font
    $null = Add-Text $script:workspaceForm 'Files stay in your private GitHub repository. Text changes and removed files remain in Git history. Do not use for secrets.' 20 15 650 52
    $null = Add-Text $script:workspaceForm 'Filename (UTF-8 text, up to 1 MiB)' 20 73 600 25
    $script:workspaceName = New-Object System.Windows.Forms.TextBox; $script:workspaceName.SetBounds(20,98,650,28); $script:workspaceForm.Controls.Add($script:workspaceName)
    $null = Add-Text $script:workspaceForm 'Public HTTPS file URL, for import' 20 135 600 25
    $script:workspaceUrl = New-Object System.Windows.Forms.TextBox; $script:workspaceUrl.SetBounds(20,160,650,28); $script:workspaceForm.Controls.Add($script:workspaceUrl)
    Add-Button $script:workspaceForm 'Import and scan' 20 200 185 { Start-WorkspaceAction 'import' }
    $null = Add-Text $script:workspaceForm 'Find text' 20 246 300 25
    $script:workspaceFind = New-Object System.Windows.Forms.TextBox; $script:workspaceFind.SetBounds(20,272,310,28); $script:workspaceForm.Controls.Add($script:workspaceFind)
    $null = Add-Text $script:workspaceForm 'Replace with / append text' 350 246 300 25
    $script:workspaceReplacement = New-Object System.Windows.Forms.TextBox; $script:workspaceReplacement.SetBounds(350,272,320,28); $script:workspaceForm.Controls.Add($script:workspaceReplacement)
    $null = Add-Text $script:workspaceForm 'Find and replacement text are visible in GitHub Actions history. All matches are replaced.' 20 307 650 42
    Add-Button $script:workspaceForm 'Replace text' 20 360 145 { Start-WorkspaceAction 'replace' }
    Add-Button $script:workspaceForm 'Append text' 175 360 145 { Start-WorkspaceAction 'append' }
    Add-Button $script:workspaceForm 'Remove file' 330 360 145 {
        if ([System.Windows.Forms.MessageBox]::Show('Remove this file from the current workspace? Old versions remain in Git history.', 'Remove file', 'YesNo') -eq 'Yes') { Start-WorkspaceAction 'delete' }
    }
    Add-Button $script:workspaceForm 'View files on GitHub' 485 360 185 {
        if ($repo.Text -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { Start-Process ('https://github.com/' + $repo.Text + '/tree/main/workspace') }
    }
    $null = Add-Text $script:workspaceForm 'After an operation, use Check result on the main window. GitHub offers viewing and downloading files.' 20 410 650 50
    [void]$script:workspaceForm.ShowDialog($form)
}
function Get-SourceEvidence([string]$source) {
    if ($source -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Enter a GitHub project as owner/repository.' }
    $project = ConvertFrom-Json -InputObject (Invoke-Gh @('api',('repos/' + $source)))
    if ($project.private -or $project.archived -or $project.disabled) { throw 'Only active public GitHub projects can be reviewed here.' }
    if (-not $project.license.spdx_id -or $project.license.spdx_id -eq 'NOASSERTION') { throw 'GitHub does not identify a license for this project. Review its licensing before continuing.' }
    $pushed = [DateTimeOffset]::Parse($project.pushed_at)
    if ($pushed -lt [DateTimeOffset]::UtcNow.AddYears(-2)) { throw 'This project has not had a repository update in two years. It needs separate maintenance review.' }
    $revision = Invoke-Gh @('api',('repos/' + $project.full_name + '/commits/' + [Uri]::EscapeDataString($project.default_branch)),'--jq','.sha')
    if ($revision -notmatch '^[0-9a-f]{40}$') { throw 'GitHub did not return a valid source revision.' }
    try { $community = ConvertFrom-Json -InputObject (Invoke-Gh @('api',('repos/' + $project.full_name + '/community/profile'))) }
    catch { if ($_.Exception.Message -match 'HTTP 404') { $community = $null } else { throw } }
    $security = $community.files.security_policy.html_url
    if (-not $security) {
        foreach ($path in @('SECURITY.md','.github/SECURITY.md','docs/SECURITY.md')) {
            try { $security = Invoke-Gh @('api',('repos/' + $project.full_name + '/contents/' + $path),'--jq','.html_url'); break } catch { if ($_.Exception.Message -notmatch 'HTTP 404') { throw } }
        }
    }
    if (-not $security) { $security = 'No SECURITY.md identified by GitHub; investigate reporting and advisories before forking.' }
    $contributing = $community.files.contributing.html_url
    if (-not $contributing) { $contributing = 'No contributing guide identified by GitHub.' }
    return [pscustomobject]@{ Source=$project.full_name; Url=$project.html_url; Revision=$revision; License=$project.license.spdx_id; Pushed=$project.pushed_at; Security=$security; Contributing=$contributing; Reviewed=[DateTimeOffset]::UtcNow.ToString('u') }
}
function Start-RemoteFork {
    if (-not $script:sourceEvidence -or $script:sourceEvidence.Source -ne $script:sourceName.Text.Trim()) { throw 'Review this project first.' }
    $name = $script:forkName.Text.Trim()
    if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$') { throw 'Enter a simple fork name using letters, numbers, dots, hyphens or underscores.' }
    $login = Invoke-Gh @('api','user','--jq','.login')
    $destination = $login + '/' + $name
    try { $null = Invoke-Gh @('api',('repos/' + $destination)); throw 'That repository already exists. Choose a different name.' } catch { if ($_.Exception.Message -notmatch 'HTTP 404') { throw } }
    $review = Get-SourceEvidence $script:sourceEvidence.Source
    if ($review.Revision -ne $script:sourceEvidence.Revision -or $review.Pushed -ne $script:sourceEvidence.Pushed -or $review.License -ne $script:sourceEvidence.License -or $review.Security -ne $script:sourceEvidence.Security) { throw 'Project evidence changed. Review it again before forking.' }
    try {
        $null = Invoke-Gh @('repo','fork',$review.Source,'--clone=false','--fork-name',$name,'--default-branch-only')
        $fork = ConvertFrom-Json -InputObject (Invoke-Gh @('api',('repos/' + $destination)))
    } catch { throw ('Fork outcome could not be confirmed. Inspect https://github.com/' + $destination + ' before retrying. ' + $_.Exception.Message) }
    if ($fork.private -or $fork.parent.full_name -ne $review.Source) { throw ('Fork request completed but GitHub did not return the expected public fork. Inspect ' + $destination + ' before retrying.') }
    $forkRevision = Invoke-Gh @('api',('repos/' + $destination + '/commits/' + [Uri]::EscapeDataString($fork.default_branch)),'--jq','.sha')
    if ($forkRevision -ne $review.Revision) { throw ('The public fork ' + $destination + ' was created, but its revision differs from the reviewed source. Inspect it and review again; do not retry creation.') }
    return $fork.html_url
}
function Start-SourceScan {
    if (-not $script:sourceEvidence -or $script:sourceEvidence.Source -ne $script:sourceName.Text.Trim()) { throw 'Review this project first.' }
    if ($repo.Text -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or (Invoke-Gh @('repo','view',$repo.Text,'--json','visibility','--jq','.visibility')) -ne 'PRIVATE') { throw 'Select a private File Checker workspace first.' }
    $requestId = [guid]::NewGuid().ToString('N')
    $null = Invoke-Gh @('workflow','run','source-scan.yml','--repo',$repo.Text,'-f',('repository='+$script:sourceEvidence.Source),'-f',('revision='+$script:sourceEvidence.Revision),'-f',('request_id='+$requestId))
    $script:lastRequest=$requestId; $script:lastWorkflow='source-scan.yml'; $script:lastPrefix='Source '
    $script:sourceForm.Close()
    Show-Status 'Source scan submitted. Choose Check result; open the run to inspect coverage and findings.'
}
Add-Button $form 'Review GitHub source' 24 555 240 {
    $dialog = New-Object System.Windows.Forms.Form
    $script:sourceForm = $dialog
    $dialog.Text = 'Review and fork GitHub source'; $dialog.ClientSize = New-Object System.Drawing.Size(690,480)
    $dialog.StartPosition = 'CenterParent'; $dialog.Font = $form.Font
    $null = Add-Text $dialog 'Review the upstream before creating a public fork. No source is downloaded to this PC.' 20 14 650 48
    $null = Add-Text $dialog 'GitHub project (owner/repository)' 20 65 400 25
    $script:sourceName = New-Object System.Windows.Forms.TextBox; $script:sourceName.SetBounds(20,90,430,28); $dialog.Controls.Add($script:sourceName)
    $script:sourceEvidence = $null
    $details = New-Object System.Windows.Forms.TextBox; $details.SetBounds(20,175,650,158); $details.Multiline=$true; $details.ReadOnly=$true; $details.ScrollBars='Vertical'; $dialog.Controls.Add($details)
    Add-Button $dialog 'Review project' 465 87 205 {
        try { $script:sourceEvidence = $null; $script:sourceEvidence = Get-SourceEvidence $script:sourceName.Text.Trim(); $script:sourceName.Text = $script:sourceEvidence.Source; $details.Text = "Reviewed (UTC): $($script:sourceEvidence.Reviewed)`r`nProject: $($script:sourceEvidence.Url)`r`nDefault branch commit: $($script:sourceEvidence.Revision)`r`nLast repository update: $($script:sourceEvidence.Pushed)`r`nLicense identified by GitHub: $($script:sourceEvidence.License)`r`nSecurity policy: $($script:sourceEvidence.Security)`r`nContributing guide: $($script:sourceEvidence.Contributing)`r`n`r`nThese facts do not establish safety or confirm open-source licensing. Independently verify identity, license, maintainers, advisories, dependencies and the exact revision. The scan may miss cross-folder workspace references, submodules and unsupported formats." } catch { $details.Text = 'Review failed: ' + $_.Exception.Message }
    }
    Add-Button $dialog 'Scan reviewed commit' 20 132 240 {
        try { Start-SourceScan } catch { $details.Text = 'Could not start scan: ' + $_.Exception.Message }
    }
    $null = Add-Text $dialog 'Dependency metadata is sent to OSV.dev; the scanner has network access. Results do not prove safety.' 275 128 395 43
    $null = Add-Text $dialog 'New public fork name' 20 342 400 25
    $script:forkName = New-Object System.Windows.Forms.TextBox; $script:forkName.SetBounds(20,368,430,28); $dialog.Controls.Add($script:forkName)
    Add-Button $dialog 'Create public fork' 465 365 205 {
        try {
            if (-not $script:sourceEvidence) { throw 'Review the project first.' }
            if ([System.Windows.Forms.MessageBox]::Show('Create a PUBLIC fork in your signed-in GitHub account? Anyone can see it. Only continue after reviewing the project and its license.', 'Create public fork', 'YesNo') -ne 'Yes') { return }
            $url = Start-RemoteFork
            $details.Text = 'Public fork created: ' + $url + "`r`nNo source was downloaded to this PC. Forks do not inherit a safety review; scan and inspect the exact revision before offering it."
        } catch { $details.Text = 'Could not create fork: ' + $_.Exception.Message }
    }
    $null = Add-Text $dialog 'A public fork is not a completed security review or a ready-to-publish product.' 20 415 650 42
    [void]$dialog.ShowDialog($form)
}
function Start-ArchiveAction([string]$operation) {
    try {
        if ($repo.Text -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Enter your private repository as account/name.' }
        $parsed = $null
        if (-not [Uri]::TryCreate($script:archiveUrl.Text,[UriKind]::Absolute,[ref]$parsed) -or $parsed.Scheme -ne 'https' -or $parsed.UserInfo -or -not $parsed.IsDefaultPort) { throw 'Enter a public HTTPS link without credentials or a custom port.' }
        if ($operation -in @('remove','extract') -and -not $script:archiveEntry.Text) { throw 'Enter the exact archive file name to remove or copy.' }
        if ((Invoke-Gh @('repo','view',$repo.Text,'--json','visibility','--jq','.visibility')) -ne 'PRIVATE') { throw 'The workspace must be private.' }
        $requestId = [guid]::NewGuid().ToString('N')
        $argsList = @('workflow','run','archive.yml','--repo',$repo.Text,'-f',('operation='+$operation),'-f',('url='+$script:archiveUrl.Text),'-f',('request_id='+$requestId))
        if ($operation -in @('remove','extract')) { $argsList += @('-f',('entry='+$script:archiveEntry.Text)) }
        $null = Invoke-Gh $argsList
        $script:lastRequest=$requestId; $script:lastWorkflow='archive.yml'; $script:lastPrefix='Archive '
        $script:archiveForm.Close()
        Show-Status 'ZIP operation submitted. Choose Check result; open the run on GitHub to view or download output.'
    } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Could not start ZIP operation') | Out-Null }
}
function Remove-LastArchiveArtifact {
    if (-not $script:lastArchiveRun -or $script:lastArchiveRepo -ne $repo.Text) { throw 'Check the result of a ZIP operation in this workspace first.' }
    $raw = Invoke-Gh @('api',('repos/' + $repo.Text + '/actions/runs/' + $script:lastArchiveRun + '/artifacts'))
    $artifacts = (ConvertFrom-Json -InputObject $raw).artifacts
    $found = @($artifacts | Where-Object { $_.name -eq ('cfh-archive-' + $script:lastArchiveRequest) })
    if ($found.Count -ne 1) { throw 'The output was not found or has already expired. Check the GitHub run.' }
    $null = Invoke-Gh @('api','--method','DELETE',('repos/' + $repo.Text + '/actions/artifacts/' + $found[0].id))
}
function Get-LastArchiveInventory {
    if (-not $script:lastArchiveRun -or $script:lastArchiveRepo -ne $repo.Text) { throw 'Check the successful result of a ZIP operation in this workspace first.' }
    $logs = Invoke-Gh @('run','view',$script:lastArchiveRun,'--repo',$repo.Text,'--log')
    $entries = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($logs -split "`n")) {
        if ($line.TrimEnd("`r") -match 'Z ZIP_ENTRY: (\{.*\})$') {
            $entry = ConvertFrom-Json -InputObject $Matches[1]
            $entries.Add(([string]$entry.name + ' (' + [string]$entry.size + ' bytes)'))
        }
    }
    if ($entries.Count -eq 0) { return 'No entries were listed; the archive may be empty or the logs may be unavailable.' }
    return ($entries -join "`r`n")
}
Add-Button $form 'ZIP workspace' 280 555 180 {
    $script:archiveForm = New-Object System.Windows.Forms.Form
    $script:archiveForm.Text = 'Remote ZIP workspace'; $script:archiveForm.ClientSize = New-Object System.Drawing.Size(690,520)
    $script:archiveForm.StartPosition = 'CenterParent'; $script:archiveForm.Font = $form.Font
    $null = Add-Text $script:archiveForm 'Inspect a ZIP, remove a file or copy one file to remote output. Files are never run. Output stays in GitHub for one day unless downloaded.' 20 15 650 58
    $null = Add-Text $script:archiveForm 'Public HTTPS ZIP link' 20 82 500 25
    $script:archiveUrl = New-Object System.Windows.Forms.TextBox; $script:archiveUrl.SetBounds(20,108,650,28); $script:archiveForm.Controls.Add($script:archiveUrl)
    $null = Add-Text $script:archiveForm 'Links and entry names are visible in GitHub Actions history. Do not use secrets.' 20 146 650 42
    Add-Button $script:archiveForm 'Inspect ZIP' 20 195 180 { Start-ArchiveAction 'inspect' }
    $null = Add-Text $script:archiveForm 'Exact file name in ZIP, for removal or copying' 20 244 600 25
    $script:archiveEntry = New-Object System.Windows.Forms.TextBox; $script:archiveEntry.SetBounds(20,270,650,28); $script:archiveForm.Controls.Add($script:archiveEntry)
    Add-Button $script:archiveForm 'Remove file and make ZIP' 20 312 240 { Start-ArchiveAction 'remove' }
    Add-Button $script:archiveForm 'Copy file from ZIP' 275 312 220 { Start-ArchiveAction 'extract' }
    $null = Add-Text $script:archiveForm 'ZIP limit: 10 MiB, 1,000 entries, 25 MiB per entry and 100 MiB expanded. Scans may miss threats. Downloading output places possibly unsafe files on your PC.' 20 365 650 66
    Add-Button $script:archiveForm 'Delete last ZIP output' 20 448 240 {
        try {
            if (-not $script:lastArchiveRun -or $script:lastArchiveRepo -ne $repo.Text) { throw 'Check the result of a ZIP operation in this workspace first.' }
            if ([System.Windows.Forms.MessageBox]::Show('Delete the ZIP output artifact for the last checked run? GitHub retains run logs and applies its own deletion policies.', 'Delete ZIP output', 'YesNo') -ne 'Yes') { return }
            Remove-LastArchiveArtifact
            [System.Windows.Forms.MessageBox]::Show('Output artifact deleted. GitHub may retain run logs.', 'ZIP output') | Out-Null
        } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Could not delete ZIP output') | Out-Null }
    }
    Add-Button $script:archiveForm 'View last ZIP inventory' 275 448 240 {
        try {
            $inventoryText = Get-LastArchiveInventory
            $inventory = New-Object System.Windows.Forms.Form
            $inventory.Text = 'ZIP inventory'; $inventory.ClientSize = New-Object System.Drawing.Size(690,480); $inventory.StartPosition='CenterParent'
            $view = New-Object System.Windows.Forms.TextBox; $view.Multiline=$true; $view.ReadOnly=$true; $view.ScrollBars='Both'; $view.WordWrap=$false; $view.Dock='Fill'; $view.Text=$inventoryText; $inventory.Controls.Add($view)
            [void]$inventory.ShowDialog($script:archiveForm)
        } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Could not show ZIP inventory') | Out-Null }
    }
    [void]$script:archiveForm.ShowDialog($form)
}
[void]$form.ShowDialog()
