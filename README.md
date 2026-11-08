# CFH File Checker

CFH File Checker is a Windows desktop app for checking public files and working with limited file types through a private GitHub repository and GitHub Actions. It can scan a public HTTPS download, edit UTF-8 text, inspect or edit ZIP entries, and screen a public GitHub source revision. See [README.txt](README.txt) for details and limits.

## Set up

Download the Windows setup executable from this repository's releases and run it. Setup installs for the current Windows user and creates desktop and Start menu shortcuts. The installer is unsigned, so Windows may ask you to confirm that you want to run it.

You also need Windows PowerShell, .NET Framework, GitHub CLI and a GitHub account. Open the app, install GitHub CLI if needed, sign in and create a private workspace. GitHub Actions must be enabled; account usage and billing limits may apply. Use a public HTTPS link to begin a scan, then use **Check result** or open the Actions run to see what happened.

## Security and privacy

The GitHub-hosted runner downloads submitted files; the app does not intentionally save those files to your PC. It does not execute downloaded source or serve as a general-purpose sandbox. Antivirus and dependency scans have limited coverage and cannot prove a file is safe. A failed scan has an unknown result.

Repository collaborators and GitHub can see workflow inputs and logs. Do not submit private links or secrets. Text workspace changes are stored in the private repository and remain in its Git history after removal. ZIP results are temporary Actions artifacts. GitHub's storage, retention and service policies apply. See [README.txt](README.txt) for supported formats, size limits and the details of each operation.

## Build from source

On Windows with .NET Framework and Windows PowerShell, run `powershell -NoProfile -ExecutionPolicy Bypass -File setup/Build-Setup.ps1`. The executable is written to `dist/CFH-File-Checker-Setup.exe`. The source package can also be installed with `Install.cmd`.

To remove the app, use **Uninstall CFH File Checker** in the Start menu. Modified files are retained; the GitHub repository, run logs and app settings are not deleted.

## License

The source in this repository is available under the [MIT License](LICENSE). GitHub, GitHub CLI, ClamAV, OSV-Scanner and other independently distributed tools and services have their own licenses and terms.
