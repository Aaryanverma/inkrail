using Microsoft.Web.WebView2.Core;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Inkrail.Windows;

internal static class FileDialogs
{
    private static readonly UTF8Encoding Utf8 = new(false, true);

    internal static object? Import(IWin32Window owner)
    {
        using var dialog = new OpenFileDialog {
            Title = "Import a letter", CheckFileExists = true, RestoreDirectory = true,
            Filter = "Text and Markdown files|*.txt;*.md;*.markdown;*.mdown;*.mkd|All files|*.*"
        };
        if (dialog.ShowDialog(owner) != DialogResult.OK) return null;
        string text;
        byte[] bytes = File.ReadAllBytes(dialog.FileName);
        ReadOnlySpan<byte> content = bytes;
        try
        {
            if (content.StartsWith(Encoding.Unicode.Preamble))
                text = new UnicodeEncoding(false, false, true).GetString(content[2..]);
            else if (content.StartsWith(Encoding.BigEndianUnicode.Preamble))
                text = new UnicodeEncoding(true, false, true).GetString(content[2..]);
            else
                text = Utf8.GetString(content.StartsWith(Encoding.UTF8.Preamble) ? content[3..] : content);
        }
        catch (DecoderFallbackException error)
        {
            throw new IOException("Save a copy in UTF-8 or in UTF-16 with a byte order mark and try again.", error);
        }
        string extension = Path.GetExtension(dialog.FileName).ToLowerInvariant();
        return new { text, markdown = extension is ".md" or ".markdown" or ".mdown" or ".mkd" };
    }

    private static string ExportName(string body)
    {
        string first = Regex.Split(body, @"\r\n|[\r\n\v\f\u0085\u2028\u2029]")
            .Select(s => s.Trim()).FirstOrDefault(s => s.Length != 0) ?? "Untitled letter";
        var elements = StringInfo.GetTextElementEnumerator(first);
        var title = new StringBuilder();
        for (int i = 0; i < 64 && elements.MoveNext(); i++) title.Append(elements.GetTextElement());
        var invalid = Path.GetInvalidFileNameChars();
        string safe = string.Concat(title.ToString().Select(c => c == '%' || invalid.Contains(c) ? '-' : c))
            .Trim().Trim('.').Trim();
        if (safe.Length == 0) return "Untitled letter";
        if (Regex.IsMatch(safe, @"^(?:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)) safe = "_" + safe;
        return safe;
    }

    private static string? ChooseExportPath(IWin32Window owner, string name, string extension, string filter)
    {
        using var dialog = new SaveFileDialog {
            Title = "Keep a copy of your letter", DefaultExt = extension,
            FileName = name + "." + extension,
            Filter = filter, OverwritePrompt = true, RestoreDirectory = true
        };
        return dialog.ShowDialog(owner) == DialogResult.OK ? Path.GetFullPath(dialog.FileName) : null;
    }

    private static string TemporaryExport(string path) => Path.Combine(Path.GetDirectoryName(path)!,
        ".inkrail-export-" + Guid.NewGuid().ToString("N") + Path.GetExtension(path));

    internal static bool Export(IWin32Window owner, JsonElement args)
    {
        bool markdown = args.GetProperty("markdown").GetBoolean();
        string name = ExportName(args.GetProperty("body").GetString() ?? "");
        string? path = ChooseExportPath(owner, name, markdown ? "md" : "txt",
            markdown ? "Markdown file|*.md" : "Text file|*.txt");
        if (path is null) return false;
        WriteTextExport(path, args.GetProperty("text").GetString() ?? "");
        return true;
    }

    internal static bool ExportInteractive(IWin32Window owner, JsonElement args)
    {
        string? path = ChooseExportPath(owner, "A letter for you", "html", "Interactive letter|*.html");
        if (path is null) return false;
        WriteTextExport(path, args.GetProperty("html").GetString() ?? throw new InvalidDataException("The letter is missing."));
        return true;
    }

    private static void WriteTextExport(string path, string text)
    {
        string temporary = TemporaryExport(path);
        try
        {
            File.WriteAllText(temporary, text, Utf8);
            File.Move(temporary, path, true);
        }
        finally { File.Delete(temporary); }
    }

    internal static async Task<bool> ExportPdf(IWin32Window owner, CoreWebView2 webView, JsonElement args)
    {
        string name = ExportName(args.GetProperty("body").GetString() ?? "");
        string? path = ChooseExportPath(owner, name, "pdf", "PDF document|*.pdf");
        if (path is null) return false;
        var settings = webView.Environment.CreatePrintSettings();
        settings.PageWidth = args.GetProperty("width").GetDouble() / 96;
        settings.PageHeight = args.GetProperty("height").GetDouble() / 96;
        settings.MarginLeft = settings.MarginRight = settings.MarginTop = settings.MarginBottom = 0;
        settings.ShouldPrintBackgrounds = true;
        settings.ShouldPrintHeaderAndFooter = false;
        string temporary = TemporaryExport(path);
        try
        {
            if (!await webView.PrintToPdfAsync(temporary, settings))
                throw new IOException("The letter could not be exported as a PDF.");
            File.Move(temporary, path, true);
            return true;
        }
        finally { File.Delete(temporary); }
    }

    internal static string? ChangeLocation(IWin32Window owner, Library library)
    {
        using var dialog = new FolderBrowserDialog {
            Description = "Choose an empty folder for your Inkrail library", UseDescriptionForTitle = true,
            ShowNewFolderButton = true
        };
        if (dialog.ShowDialog(owner) != DialogResult.OK) return null;
        library.Relocate(dialog.SelectedPath);
        return library.Location;
    }
}
