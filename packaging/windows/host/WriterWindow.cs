using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace Inkrail.Windows;

internal sealed class WriterWindow : Form
{
    private const string DeskHost = "inkrail.invalid";
    private readonly string token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    private string DeskUri => "https://" + DeskHost + "/index.html#" + token;
    private readonly WebView2 browser = new() { Dock = DockStyle.Fill, AllowExternalDrop = false };
    private readonly Library library;
    private readonly string cache;
    private readonly int? debugPort;
    private readonly System.Windows.Forms.Timer closeTimer = new() { Interval = 12000 };
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private bool ready, closePending, canClose;
    private bool pdfExportActive, closeAfterPdfExport;
    public int ExitCode { get; private set; }

    public WriterWindow(Library library, string cache, int? debugPort)
    {
        this.library = library;
        this.cache = cache;
        this.debugPort = debugPort;
        Text = "Inkrail";
        Icon = System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(1080, 760);
        MinimumSize = new Size(640, 480);
        Controls.Add(browser);
        Shown += OpenDesk;
        closeTimer.Tick += (_, _) => CloseFailed();
        FormClosed += (_, _) => closeTimer.Dispose();
    }

    private async void OpenDesk(object? sender, EventArgs e)
    {
        try
        {
            string ui = Path.Combine(AppContext.BaseDirectory, "ui");
            if (!File.Exists(Path.Combine(ui, "index.html")))
                throw new FileNotFoundException("Extract the entire Inkrail ZIP and keep Inkrail.exe and its ui folder together.");
            var options = new CoreWebView2EnvironmentOptions();
            if (debugPort.HasValue)
                options.AdditionalBrowserArguments = $"--remote-debugging-address=127.0.0.1 --remote-debugging-port={debugPort}";
            var environment = await CoreWebView2Environment.CreateAsync(null, cache, options);
            if (IsDisposed) return;
            await browser.EnsureCoreWebView2Async(environment);
            var core = browser.CoreWebView2;
            core.Settings.AreDevToolsEnabled = debugPort.HasValue;
            core.Settings.AreBrowserAcceleratorKeysEnabled = false;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.IsZoomControlEnabled = false;
            core.Settings.IsGeneralAutofillEnabled = false;
            core.Settings.IsPasswordAutosaveEnabled = false;
            core.Settings.AreHostObjectsAllowed = false;
            core.SetVirtualHostNameToFolderMapping(DeskHost, ui, CoreWebView2HostResourceAccessKind.Deny);
            core.NavigationStarting += (_, args) => args.Cancel = !IsDesk(args.Uri);
            core.FrameNavigationStarting += (_, args) => args.Cancel = true;
            core.NewWindowRequested += (_, args) => args.Handled = true;
            core.DownloadStarting += (_, args) => args.Cancel = true;
            core.PermissionRequested += (_, args) => args.State = CoreWebView2PermissionState.Deny;
            core.ContextMenuRequested += (_, args) =>
            {
                // Keep the native editing commands, including clipboard actions, in the editor.
                for (int i = args.MenuItems.Count - 1; i >= 0; i--)
                    if (args.MenuItems[i].Name is not ("undo" or "redo" or "cut" or "copy" or
                        "paste" or "pasteAndMatchStyle" or "selectAll" or "delete"))
                        args.MenuItems.RemoveAt(i);
                args.Handled = args.MenuItems.Count == 0;
            };
            core.ProcessFailed += (_, args) =>
            {
                if (!IsDisposed && !Disposing && (args.ProcessFailedKind is
                    CoreWebView2ProcessFailedKind.RenderProcessExited or CoreWebView2ProcessFailedKind.BrowserProcessExited))
                    BeginInvoke(new Action(RendererExited));
            };
            core.WebMessageReceived += Receive;
            core.Navigate(DeskUri);
        }
        catch (Exception error)
        {
            if (IsDisposed) return;
            ExitCode = 1;
            string message = error is WebView2RuntimeNotFoundException
                ? "Install Microsoft Edge WebView2 Evergreen Runtime, then open Inkrail again." : error.Message;
            MessageBox.Show(this, message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            canClose = true;
            Close();
        }
    }

    private void RendererExited()
    {
        if (canClose || IsDisposed || Disposing) return;
        canClose = true;
        ExitCode = 1;
        closeTimer.Stop();
        MessageBox.Show(this, "The writing window stopped unexpectedly. Reopen Inkrail to return to your last saved letter.",
            Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
        Close();
    }

    private bool IsDesk(string address)
    {
        // WebView2 may omit the fragment from the message source. The message
        // itself must additionally carry the secret supplied to this window.
        return Uri.TryCreate(address, UriKind.Absolute, out var uri) &&
            uri.Scheme == Uri.UriSchemeHttps && uri.Host == DeskHost && uri.IsDefaultPort &&
            uri.UserInfo == "" && uri.AbsolutePath == "/index.html" && uri.Query == "";
    }

    private sealed record Request(long Id, string Token, string Op, JsonElement Args);

    private void Receive(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        if (!IsDesk(e.Source)) return;
        Request? request;
        try { request = JsonSerializer.Deserialize<Request>(e.TryGetWebMessageAsString(), Json); }
        catch (JsonException) { return; }
        catch (ArgumentException) { return; }
        if (request is null || request.Token != token) return;
        // Native dialogs run a modal message loop. Open them after the
        // WebView2 callback has returned so its dispatcher is free to run.
        BeginInvoke(new Action(() => HandleRequest(request)));
    }

    private async void HandleRequest(Request request)
    {
        if (IsDisposed) return;
        object? value = null;
        string? error = null;
        bool finishClose = false;
        bool resumeClose = false;
        try
        {
            switch (request.Op)
            {
                case "boot": value = library.Boot(); break;
                case "import": value = FileDialogs.Import(this); break;
                case "export": value = FileDialogs.Export(this, request.Args); break;
                case "exportInteractive": value = FileDialogs.ExportInteractive(this, request.Args); break;
                case "beginPdfExport":
                    bool granted = !closePending && !canClose && !pdfExportActive;
                    if (granted) pdfExportActive = true;
                    value = granted;
                    break;
                case "exportPDF":
                    if (!pdfExportActive) throw new InvalidOperationException("PDF export has not started.");
                    value = await FileDialogs.ExportPdf(this, browser.CoreWebView2, request.Args);
                    break;
                case "endPdfExport":
                    resumeClose = closeAfterPdfExport && request.Args.GetBoolean();
                    pdfExportActive = false;
                    closeAfterPdfExport = false;
                    break;
                case "changeStorage": value = FileDialogs.ChangeLocation(this, library); break;
                case "revealStorage":
                    if (!Directory.Exists(library.Location)) throw new DirectoryNotFoundException(library.Location);
                    Process.Start(new ProcessStartInfo(library.Location) { UseShellExecute = true });
                    break;
                case "windowDirty": break; // Always flush on close, even with pending preference changes alone.
                case "windowReady": ready = true; browser.Focus(); break;
                case "windowClosed": finishClose = closePending; break;
                case "windowCloseFailed": if (closePending) CloseFailed(); break;
                default: value = library.Dispatch(request.Op, request.Args); break;
            }
        }
        catch (Exception ex) { error = ex.Message; }
        if (IsDisposed) return;
        string response = JsonSerializer.Serialize(new { request.Id, value, error }, Json);
        try { await browser.ExecuteScriptAsync($"window.__inkrailReply({response})"); }
        catch (Exception) when (IsDisposed || Disposing) { return; }
        catch (Exception ex)
        {
            // If the renderer never receives its reply it cannot send endPdfExport.
            if (request.Op == "exportPDF" || (request.Op == "beginPdfExport" && value is true))
            {
                pdfExportActive = false;
                closeAfterPdfExport = false;
            }
            MessageBox.Show(this, ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }
        if (finishClose && closePending)
        {
            canClose = true;
            Close();
        }
        else if (resumeClose) Close(); // Re-enter the normal save-before-close path.
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        base.OnFormClosing(e);
        if (canClose || !ready) return;
        e.Cancel = true;
        // Preparing the print layout, choosing a destination and writing the PDF
        // all precede the close-time autosave and its watchdog.
        if (pdfExportActive)
        {
            closeAfterPdfExport = true;
            return;
        }
        if (closePending) return;
        closePending = true;
        browser.Enabled = false;
        closeTimer.Start();
        RequestFlushAndClose();
    }

    private async void RequestFlushAndClose()
    {
        try { await browser.ExecuteScriptAsync("window.dispatchEvent(new Event('inkrail-close-request'))"); }
        catch (Exception) { if (!IsDisposed && !Disposing) CloseFailed(); }
    }

    private void CloseFailed()
    {
        closeTimer.Stop();
        if (!closePending || IsDisposed) return;
        closePending = false;
        browser.Enabled = true;
        var answer = MessageBox.Show(this,
            "Inkrail could not confirm that your writing was saved. Close anyway and lose any unsaved changes?",
            Text, MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
        if (answer == DialogResult.Yes) { canClose = true; Close(); }
        else browser.Focus();
    }
}
