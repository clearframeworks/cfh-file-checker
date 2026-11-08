using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

internal static class Setup
{
    private const string Product = "CFH File Checker";
    [STAThread]
    private static int Main(string[] args)
    {
        bool silent = Array.IndexOf(args, "--silent") >= 0;
        bool noShortcuts = Array.IndexOf(args, "--no-shortcuts") >= 0;
        if (noShortcuts && !silent) return 2;
        if (!silent)
        {
            Application.EnableVisualStyles();
            var choice = MessageBox.Show(
                "Install CFH File Checker for your Windows account?\n\n" +
                "Setup creates desktop and Start menu shortcuts. GitHub CLI and a GitHub account " +
                "are needed to connect a remote workspace. Existing GitHub files and settings are kept.\n\n" +
                "This installer is unsigned. A scan cannot prove that a file is safe.",
                Product + " Setup", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (choice != DialogResult.Yes) return 0;
        }
        string temporary = Path.Combine(Path.GetTempPath(), "cfh-file-checker-setup-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(temporary);
            string root = Path.GetFullPath(temporary).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            {
                if (input == null) throw new InvalidDataException("The setup package is incomplete.");
                using (var zip = new ZipArchive(input, ZipArchiveMode.Read))
                {
                    foreach (var entry in zip.Entries)
                    {
                        string target = Path.GetFullPath(Path.Combine(root, entry.FullName.Replace('/', Path.DirectorySeparatorChar)));
                        if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase) || entry.Length > 10 * 1024 * 1024)
                            throw new InvalidDataException("The setup package contains an invalid file.");
                    }
                    zip.ExtractToDirectory(temporary);
                }
            }
            string script = Path.Combine(temporary, "Install.ps1");
            if (!File.Exists(script)) throw new InvalidDataException("The setup package is incomplete.");
            var start = new ProcessStartInfo();
            start.FileName = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
            start.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -NoLaunch" + (noShortcuts ? " -NoShortcuts" : "");
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.RedirectStandardOutput = true;
            start.RedirectStandardError = true;
            using (var process = Process.Start(start))
            {
                if (process == null) throw new InvalidOperationException("Windows could not start setup.");
                // Drain both redirected streams concurrently. Either pipe can fill
                // while setup is still writing to the other one.
                var outputRead = process.StandardOutput.ReadToEndAsync();
                var errorRead = process.StandardError.ReadToEndAsync();
                process.WaitForExit();
                System.Threading.Tasks.Task.WaitAll(outputRead, errorRead);
                string output = outputRead.Result;
                string error = errorRead.Result;
                if (process.ExitCode != 0) throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? "Installation did not finish." : error.Trim());
                if (silent) { Console.WriteLine(output); return 0; }
            }
            var open = MessageBox.Show(
                "CFH File Checker is installed. Open it now?\n\n" +
                "If GitHub CLI is not installed, use the Install GitHub CLI button in the app. " +
                "Sign in and create or select your private workspace to begin.",
                Product + " Setup", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (open == DialogResult.Yes)
                Process.Start(new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", Product, "Launch.cmd")) { UseShellExecute = true });
            return 0;
        }
        catch (Exception ex)
        {
            if (silent) Console.Error.WriteLine(ex.Message);
            else MessageBox.Show("Setup could not finish.\n\n" + ex.Message + "\n\nYour GitHub workspace was not removed.", Product + " Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            try { if (Directory.Exists(temporary)) Directory.Delete(temporary, true); }
            catch { /* A locked setup file may be left in the temporary folder. */ }
        }
    }
}
