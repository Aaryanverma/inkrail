using System.Security.Cryptography;
using System.Text;
using Inkrail.Windows;
using static Inkrail.Linux.Native;

namespace Inkrail.Linux;

internal static class Program
{
    private static int Main(string[] args)
    {
        // The NVIDIA driver's explicit sync breaks WebKitGTK's DMA-BUF renderer on
        // Wayland ("Error 71 (Protocol error) dispatching to Wayland display").
        // Turning off explicit sync keeps GPU rendering; disabling the DMA-BUF
        // renderer instead also avoids the error but makes typing visibly laggy.
        if (File.Exists("/proc/driver/nvidia/version"))
            setenv("__NV_DISABLE_EXPLICIT_SYNC", "1", 0);
        g_set_prgname("inkrail");
        g_set_application_name("Inkrail");
        if (!gtk_init_check(0, 0))
        {
            Console.Error.WriteLine("Inkrail needs a graphical session (Wayland or X11).");
            return 1;
        }
        SynchronizationContext.SetSynchronizationContext(new GLibContext());
        try
        {
            // Letters are user data, not configuration: $XDG_DATA_HOME/Inkrail.
            string defaultProfile = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData,
                    Environment.SpecialFolderOption.DoNotVerify), "Inkrail");
            string? profileOverride = null;
            bool devTools = false, smoke = false;
            for (int i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "-data" or "--data" when i + 1 < args.Length:
                        profileOverride = Path.GetFullPath(args[++i]);
                        break;
                    case "-devtools" or "--devtools":
                        devTools = true;
                        break;
                    case "-smoke" or "--smoke":
                        smoke = true;
                        break;
                    default:
                        throw new ArgumentException("Unrecognized or incomplete argument: " + args[i]);
                }
            }

            if ((devTools || smoke) && (profileOverride == null ||
                Path.GetRelativePath(defaultProfile, profileOverride) == "."))
                throw new ArgumentException("Use a separate -data folder with -devtools or -smoke.");

            string profile = profileOverride ?? defaultProfile;
            Directory.CreateDirectory(profile);
            using var instance = AcquireInstance(profile);
            if (instance == null)
            {
                MessageBox(0, "Inkrail is already open for this library profile. Switch to its existing window.",
                    MessageInfo, ButtonsOk);
                return 0;
            }
            var window = new WriterWindow(new Library(profile), Path.Combine(AppContext.BaseDirectory, "ui"), devTools, smoke);
            window.Run();
            return window.ExitCode;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("Inkrail: " + error.Message);
            MessageBox(0, error.Message, MessageError, ButtonsOk);
            return 1;
        }
    }

    // One desk per profile. The lock is advisory (flock) and released if the process dies.
    private static FileStream? AcquireInstance(string profile)
    {
        string runtime = Environment.GetEnvironmentVariable("XDG_RUNTIME_DIR") is { Length: > 0 } dir && Directory.Exists(dir)
            ? dir : Path.GetTempPath();
        string key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
            Path.TrimEndingDirectorySeparator(Path.GetFullPath(profile)))))[..32];
        try
        {
            return new FileStream(Path.Combine(runtime, "inkrail-" + key + ".lock"),
                FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        }
        catch (IOException) { return null; }
    }
}
