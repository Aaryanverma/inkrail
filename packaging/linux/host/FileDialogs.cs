using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Inkrail.Windows;
using static Inkrail.Linux.Native;

namespace Inkrail.Linux;

// Same import/export contract as the Windows host, with GTK (portal-aware) choosers.
internal static class FileDialogs
{
    private const int ActionOpen = 0, ActionSave = 1, ActionSelectFolder = 2;
    private static readonly UTF8Encoding Utf8Strict = new(false, true);

    private static string? Choose(nint owner, string title, int action, string accept,
        (string Name, string[] Patterns)[] filters, string? suggestedName = null)
    {
        nint dialog = gtk_file_chooser_native_new(title, owner, action, accept, "_Cancel");
        try
        {
            foreach (var (name, patterns) in filters)
            {
                nint filter = gtk_file_filter_new();
                gtk_file_filter_set_name(filter, name);
                foreach (string pattern in patterns) gtk_file_filter_add_pattern(filter, pattern);
                gtk_file_chooser_add_filter(dialog, filter);
            }
            if (action == ActionSave)
            {
                gtk_file_chooser_set_do_overwrite_confirmation(dialog, true);
                if (suggestedName != null) gtk_file_chooser_set_current_name(dialog, suggestedName);
            }
            if (action != ActionOpen) gtk_file_chooser_set_create_folders(dialog, true);
            if (gtk_native_dialog_run(dialog) != ResponseAccept) return null;
            string? path = TakeUtf8(gtk_file_chooser_get_filename(dialog));
            return path == null ? null : Path.GetFullPath(path);
        }
        finally { g_object_unref(dialog); }
    }

    internal static object? Import(nint owner)
    {
        string? path = Choose(owner, "Import a letter", ActionOpen, "_Import", [
            ("Text and Markdown files", ["*.txt", "*.md", "*.markdown", "*.mdown", "*.mkd",
                                         "*.TXT", "*.MD", "*.MARKDOWN", "*.MDOWN", "*.MKD"]),
            ("All files", ["*"])
        ]);
        if (path is null) return null;
        string text;
        byte[] bytes = File.ReadAllBytes(path);
        ReadOnlySpan<byte> content = bytes;
        try
        {
            if (content.StartsWith(Encoding.Unicode.Preamble))
                text = new UnicodeEncoding(false, false, true).GetString(content[2..]);
            else if (content.StartsWith(Encoding.BigEndianUnicode.Preamble))
                text = new UnicodeEncoding(true, false, true).GetString(content[2..]);
            else
                text = Utf8Strict.GetString(content.StartsWith(Encoding.UTF8.Preamble) ? content[3..] : content);
        }
        catch (DecoderFallbackException error)
        {
            throw new IOException("Save a copy in UTF-8 or in UTF-16 with a byte order mark and try again.", error);
        }
        string extension = Path.GetExtension(path).ToLowerInvariant();
        return new { text, markdown = extension is ".md" or ".markdown" or ".mdown" or ".mkd" };
    }

    private static string ExportName(string body)
    {
        string first = Regex.Split(body, @"\r\n|[\r\n\v\f\u0085  ]")
            .Select(s => s.Trim()).FirstOrDefault(s => s.Length != 0) ?? "Untitled letter";
        var elements = StringInfo.GetTextElementEnumerator(first);
        var title = new StringBuilder();
        for (int i = 0; i < 64 && elements.MoveNext(); i++) title.Append(elements.GetTextElement());
        // Keep names portable to Windows and FAT/exFAT drives as well.
        const string invalid = "\0/\\:*?\"<>|%";
        string safe = string.Concat(title.ToString().Select(c => char.IsControl(c) || invalid.Contains(c) ? '-' : c))
            .Trim().Trim('.').Trim();
        return safe.Length == 0 ? "Untitled letter" : safe;
    }

    private static string? ChooseExportPath(nint owner, JsonElement args, string extension, string filterName)
    {
        string? path = Choose(owner, "Keep a copy of your letter", ActionSave, "_Save",
            [(filterName, ["*." + extension, "*." + extension.ToUpperInvariant()])],
            ExportName(args.GetProperty("body").GetString() ?? "") + "." + extension);
        if (path == null) return null;
        // GTK does not append the extension for us.
        if (!path.EndsWith("." + extension, StringComparison.OrdinalIgnoreCase)) path += "." + extension;
        return path;
    }

    private static string TemporaryExport(string path) => Path.Combine(Path.GetDirectoryName(path)!,
        ".inkrail-export-" + Guid.NewGuid().ToString("N") + Path.GetExtension(path));

    internal static bool Export(nint owner, JsonElement args)
    {
        bool markdown = args.GetProperty("markdown").GetBoolean();
        string? path = ChooseExportPath(owner, args, markdown ? "md" : "txt",
            markdown ? "Markdown file" : "Text file");
        if (path is null) return false;
        string temporary = TemporaryExport(path);
        try
        {
            File.WriteAllText(temporary, args.GetProperty("text").GetString() ?? "", Utf8Strict);
            File.Move(temporary, path, true);
            return true;
        }
        finally { File.Delete(temporary); }
    }

    private sealed class PrintJob
    {
        // Resume after the signal emission returns, not inside it.
        public readonly TaskCompletionSource<string?> Done = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public string? Error;
    }

    internal static async Task<bool> ExportPdf(nint owner, nint webView, JsonElement args, string? destination = null)
    {
        string? path = destination ?? ChooseExportPath(owner, args, "pdf", "PDF document");
        if (path is null) return false;
        double width = args.GetProperty("width").GetDouble() / 96;
        double height = args.GetProperty("height").GetDouble() / 96;
        string temporary = TemporaryExport(path);
        nint settings = gtk_print_settings_new();
        nint setup = gtk_page_setup_new();
        nint paper = gtk_paper_size_new_custom("inkrail-letter", "Inkrail letter", width, height, UnitInch);
        nint operation = 0;
        var job = new PrintJob();
        var handle = GCHandle.Alloc(job);
        try
        {
            gtk_page_setup_set_paper_size(setup, paper);
            gtk_page_setup_set_orientation(setup, 0);
            gtk_page_setup_set_top_margin(setup, 0, UnitInch);
            gtk_page_setup_set_bottom_margin(setup, 0, UnitInch);
            gtk_page_setup_set_left_margin(setup, 0, UnitInch);
            gtk_page_setup_set_right_margin(setup, 0, UnitInch);
            gtk_print_settings_set_printer(settings, "Print to File");
            gtk_print_settings_set(settings, "output-file-format", "pdf");
            gtk_print_settings_set(settings, "output-uri", FileUri(temporary));
            gtk_print_settings_set_paper_size(settings, paper);
            gtk_print_settings_set_orientation(settings, 0);

            operation = webkit_print_operation_new(webView);
            webkit_print_operation_set_page_setup(operation, setup);
            webkit_print_operation_set_print_settings(operation, settings);
            WatchPrint(operation, GCHandle.ToIntPtr(handle));
            webkit_print_operation_print(operation);
            string? error = await job.Done.Task;
            if (error != null || !File.Exists(temporary) || new FileInfo(temporary).Length == 0)
                throw new IOException("The letter could not be exported as a PDF." + (error == null ? "" : " " + error));
            File.Move(temporary, path, true);
            return true;
        }
        finally
        {
            if (operation != 0) g_object_unref(operation);
            gtk_paper_size_free(paper);
            g_object_unref(setup);
            g_object_unref(settings);
            handle.Free();
            File.Delete(temporary);
        }
    }

    private static unsafe void WatchPrint(nint operation, nint data)
    {
        Connect(operation, "failed", (nint)(delegate* unmanaged<nint, nint, nint, void>)&PrintFailed, data);
        Connect(operation, "finished", (nint)(delegate* unmanaged<nint, nint, void>)&PrintFinished, data);
    }

    [UnmanagedCallersOnly]
    private static void PrintFailed(nint operation, nint error, nint data)
    {
        var job = (PrintJob)GCHandle.FromIntPtr(data).Target!;
        // GError: { GQuark domain; gint code; gchar *message; }
        job.Error = error == 0 ? "Printing failed." : Utf8(Marshal.ReadIntPtr(error, 8)) ?? "Printing failed.";
    }

    [UnmanagedCallersOnly]
    private static void PrintFinished(nint operation, nint data)
    {
        var job = (PrintJob)GCHandle.FromIntPtr(data).Target!;
        job.Done.TrySetResult(job.Error);
    }

    internal static string? ChangeLocation(nint owner, Library library)
    {
        string? path = Choose(owner, "Choose an empty folder for your Inkrail library", ActionSelectFolder, "_Select", []);
        if (path is null) return null;
        library.Relocate(path);
        return library.Location;
    }
}
