using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using Inkrail.Windows;
using static Inkrail.Linux.Native;

namespace Inkrail.Linux;

// GTK/WebKitGTK counterpart of the Windows WriterWindow. The desk is served from
// the private inkrail://desk/ scheme; nothing listens on the network.
internal sealed class WriterWindow
{
    private const string Scheme = "inkrail";
    private const string DeskHost = "desk";
    private const string Handler = "inkrail";
    private static WriterWindow? current;

    private readonly string token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    private string DeskUri => Scheme + "://" + DeskHost + "/index.html#" + token;
    private readonly Library library;
    private readonly string ui;
    private readonly bool devTools, smoke;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private nint window, browser;
    private uint closeTimer, smokeTimer;
    private bool ready, closePending, canClose, destroyed;
    private bool pdfExportActive, closeAfterPdfExport;
    public int ExitCode { get; private set; }

    public WriterWindow(Library library, string ui, bool devTools, bool smoke)
    {
        this.library = library;
        this.ui = Path.TrimEndingDirectorySeparator(Path.GetFullPath(ui));
        this.devTools = devTools;
        this.smoke = smoke;
    }

    public unsafe void Run()
    {
        if (current != null) throw new InvalidOperationException("Only one desk window is supported.");
        current = this;
        if (!File.Exists(Path.Combine(ui, "index.html")))
            throw new FileNotFoundException("Extract the entire Inkrail archive and keep the inkrail program and its ui folder together.");

        nint context = webkit_web_context_get_default();
        webkit_web_context_register_uri_scheme(context, Scheme, &ServeDesk, 0, 0);
        nint security = webkit_web_context_get_security_manager(context);
        webkit_security_manager_register_uri_scheme_as_secure(security, Scheme);
        webkit_security_manager_register_uri_scheme_as_cors_enabled(security, Scheme);

        nint content = webkit_user_content_manager_new();
        if (!webkit_user_content_manager_register_script_message_handler(content, Handler))
            throw new InvalidOperationException("Could not connect the writing desk.");
        Connect(content, "script-message-received::" + Handler, (nint)(delegate* unmanaged<nint, nint, nint, void>)&Receive);

        browser = webkit_web_view_new_with_user_content_manager(content);
        g_object_unref(content);
        nint settings = webkit_web_view_get_settings(browser);
        webkit_settings_set_enable_developer_extras(settings, devTools);
        webkit_settings_set_enable_write_console_messages_to_stdout(settings, devTools || smoke);
        webkit_settings_set_javascript_can_open_windows_automatically(settings, false);
        webkit_settings_set_enable_back_forward_navigation_gestures(settings, false);
        webkit_settings_set_print_backgrounds(settings, true);
        Connect(browser, "decide-policy", (nint)(delegate* unmanaged<nint, nint, int, nint, int>)&DecidePolicy);
        Connect(browser, "permission-request", (nint)(delegate* unmanaged<nint, nint, nint, int>)&DenyPermission);
        Connect(browser, "context-menu", (nint)(delegate* unmanaged<nint, nint, nint, nint, nint, int>)&ContextMenu);
        Connect(browser, "web-process-terminated", (nint)(delegate* unmanaged<nint, int, nint, void>)&ProcessTerminated);

        window = gtk_window_new(0);
        gtk_window_set_title(window, "Inkrail");
        gtk_window_set_default_size(window, 1080, 760);
        gtk_widget_set_size_request(window, 640, 480);
        gtk_window_set_position(window, 1); // GTK_WIN_POS_CENTER
        string icon = Path.Combine(ui, "assets", "AppIcon.png");
        if (File.Exists(icon)) gtk_window_set_icon_from_file(window, icon, 0);
        gtk_container_add(window, browser);
        Connect(window, "delete-event", (nint)(delegate* unmanaged<nint, nint, nint, int>)&DeleteEvent);
        Connect(window, "destroy", (nint)(delegate* unmanaged<nint, nint, void>)&Destroyed);
        gtk_widget_show_all(window);
        webkit_web_view_load_uri(browser, DeskUri);
        if (smoke) smokeTimer = g_timeout_add(30000, &SmokeTimeout, 0);
        gtk_main();
    }

    // ----- Desk files -------------------------------------------------------

    private static readonly Dictionary<string, string> Types = new(StringComparer.OrdinalIgnoreCase)
    {
        [".html"] = "text/html", [".js"] = "text/javascript", [".css"] = "text/css",
        [".png"] = "image/png", [".wav"] = "audio/wav", [".ttf"] = "font/ttf",
        [".json"] = "application/json", [".svg"] = "image/svg+xml", [".woff2"] = "font/woff2"
    };

    [UnmanagedCallersOnly]
    private static void ServeDesk(nint request, nint data)
    {
        var self = current!;
        try
        {
            if (!Uri.TryCreate(Utf8(webkit_uri_scheme_request_get_uri(request)), UriKind.Absolute, out var uri) ||
                uri.Host != DeskHost || uri.UserInfo != "" || !uri.IsDefaultPort)
                throw new FileNotFoundException();
            string relative = Uri.UnescapeDataString(uri.AbsolutePath).TrimStart('/');
            string file = Path.GetFullPath(Path.Combine(self.ui, relative));
            if (!file.StartsWith(self.ui + Path.DirectorySeparatorChar, StringComparison.Ordinal) ||
                !Types.TryGetValue(Path.GetExtension(file), out string? type) ||
                (File.GetAttributes(file) & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
                throw new FileNotFoundException();
            byte[] bytes = File.ReadAllBytes(file);
            nint buffer = g_malloc((nuint)Math.Max(bytes.Length, 1));
            Marshal.Copy(bytes, 0, buffer, bytes.Length);
            nint stream = g_memory_input_stream_new_from_data(buffer, bytes.Length, GFree);
            webkit_uri_scheme_request_finish(request, stream, bytes.Length, type);
            g_object_unref(stream);
        }
        catch (Exception)
        {
            nint error = g_error_new_literal(g_quark_from_string("inkrail-desk"), 404, "Not part of the writing desk.");
            webkit_uri_scheme_request_finish_error(request, error);
            g_error_free(error);
        }
    }

    private static bool IsDesk(string? address)
    {
        return Uri.TryCreate(address, UriKind.Absolute, out var uri) &&
            uri.Scheme == Scheme && uri.Host == DeskHost && uri.IsDefaultPort &&
            uri.UserInfo == "" && uri.AbsolutePath == "/index.html" && uri.Query == "";
    }

    // ----- Browser policy ---------------------------------------------------

    [UnmanagedCallersOnly]
    private static int DecidePolicy(nint view, nint decision, int type, nint data)
    {
        switch (type)
        {
            case 0: // Navigation: only the desk itself, in the main frame.
                nint action = webkit_navigation_policy_decision_get_navigation_action(decision);
                string? target = Utf8(webkit_uri_request_get_uri(webkit_navigation_action_get_request(action)));
                if (IsDesk(target)) return 0;
                webkit_policy_decision_ignore(decision);
                return 1;
            case 1: // New windows
                webkit_policy_decision_ignore(decision);
                return 1;
            default: // Responses: never download.
                if (webkit_response_policy_decision_is_mime_type_supported(decision)) return 0;
                webkit_policy_decision_ignore(decision);
                return 1;
        }
    }

    [UnmanagedCallersOnly]
    private static int DenyPermission(nint view, nint request, nint data)
    {
        webkit_permission_request_deny(request);
        return 1;
    }

    [UnmanagedCallersOnly]
    private static int ContextMenu(nint view, nint menu, nint e, nint hit, nint data)
    {
        // Keep the native editing commands, including clipboard actions.
        for (int i = (int)webkit_context_menu_get_n_items(menu) - 1; i >= 0; i--)
        {
            nint item = webkit_context_menu_get_item_at_position(menu, (uint)i);
            int stock = webkit_context_menu_item_get_stock_action(item);
            // COPY 14, CUT 15, PASTE 16, DELETE 17, SELECT_ALL 18, INSERT_EMOJI 44, PASTE_AS_PLAIN_TEXT 45
            if (stock is not (14 or 15 or 16 or 17 or 18 or 44 or 45)) webkit_context_menu_remove(menu, item);
        }
        return webkit_context_menu_get_n_items(menu) == 0 ? 1 : 0;
    }

    [UnmanagedCallersOnly]
    private static void ProcessTerminated(nint view, int reason, nint data) =>
        SynchronizationContext.Current!.Post(_ => current?.RendererExited(), null);

    private void RendererExited()
    {
        if (canClose || destroyed) return;
        canClose = true;
        ExitCode = 1;
        StopCloseTimer();
        MessageBox(window, "The writing window stopped unexpectedly. Reopen Inkrail to return to your last saved letter.",
            MessageError, ButtonsOk);
        Close();
    }

    // ----- Messages from the desk ------------------------------------------

    private sealed record Request(long Id, string Token, string Op, JsonElement Args);

    [UnmanagedCallersOnly]
    private static void Receive(nint manager, nint result, nint data)
    {
        var self = current!;
        if (!IsDesk(Utf8(webkit_web_view_get_uri(self.browser)))) return;
        nint value = webkit_javascript_result_get_js_value(result);
        if (!jsc_value_is_string(value)) return;
        string? text = TakeUtf8(jsc_value_to_string(value));
        Request? request;
        try { request = JsonSerializer.Deserialize<Request>(text ?? "", Json); }
        catch (JsonException) { return; }
        if (request is null || request.Token != self.token) return;
        // Native dialogs run a nested loop; open them after this callback returns.
        SynchronizationContext.Current!.Post(_ => self.HandleRequest(request), null);
    }

    private async void HandleRequest(Request request)
    {
        if (destroyed) return;
        object? value = null;
        string? error = null;
        bool finishClose = false;
        bool resumeClose = false;
        try
        {
            switch (request.Op)
            {
                case "boot": value = library.Boot(); break;
                case "import": value = FileDialogs.Import(window); break;
                case "export": value = FileDialogs.Export(window, request.Args); break;
                case "beginPdfExport":
                    bool granted = !closePending && !canClose && !pdfExportActive;
                    if (granted) pdfExportActive = true;
                    value = granted;
                    break;
                case "exportPDF":
                    if (!pdfExportActive) throw new InvalidOperationException("PDF export has not started.");
                    value = await FileDialogs.ExportPdf(window, browser, request.Args, smoke ? SmokePdf : null);
                    break;
                case "endPdfExport":
                    resumeClose = closeAfterPdfExport && request.Args.GetBoolean();
                    pdfExportActive = false;
                    closeAfterPdfExport = false;
                    if (smoke) SynchronizationContext.Current!.Post(_ => SmokeCheckPdf(), null);
                    break;
                case "changeStorage": value = FileDialogs.ChangeLocation(window, library); break;
                case "revealStorage":
                    if (!Directory.Exists(library.Location)) throw new DirectoryNotFoundException(library.Location);
                    if (!gtk_show_uri_on_window(window, FileUri(library.Location), 0, 0))
                        throw new IOException("No file manager could open " + library.Location);
                    break;
                case "windowDirty": break; // Always flush on close, even with pending preference changes alone.
                case "windowReady":
                    ready = true;
                    gtk_widget_grab_focus(browser);
                    if (smoke) SynchronizationContext.Current!.Post(_ => SmokeExportPdf(), null);
                    break;
                case "windowClosed": finishClose = closePending; break;
                case "windowCloseFailed": if (closePending) CloseFailed(); break;
                default: value = library.Dispatch(request.Op, request.Args); break;
            }
        }
        catch (Exception ex) { error = ex.Message; }
        if (destroyed) return;
        string response = JsonSerializer.Serialize(new { request.Id, value, error }, Json);
        if (!await RunScript($"window.__inkrailReply({response})"))
        {
            if (destroyed) return;
            // If the renderer never receives its reply it cannot send endPdfExport.
            if (request.Op == "exportPDF" || (request.Op == "beginPdfExport" && value is true))
            {
                pdfExportActive = false;
                closeAfterPdfExport = false;
            }
            MessageBox(window, "The writing desk did not receive Inkrail's reply.", MessageError, ButtonsOk);
            return;
        }
        if (finishClose && closePending)
        {
            canClose = true;
            Close();
        }
        else if (resumeClose) Close(); // Re-enter the normal save-before-close path.
    }

    private unsafe Task<bool> RunScript(string script)
    {
        var done = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var handle = GCHandle.Alloc(done);
        webkit_web_view_run_javascript(browser, script, 0, &ScriptFinished, GCHandle.ToIntPtr(handle));
        return done.Task;
    }

    [UnmanagedCallersOnly]
    private static unsafe void ScriptFinished(nint view, nint result, nint data)
    {
        var handle = GCHandle.FromIntPtr(data);
        var done = (TaskCompletionSource<bool>)handle.Target!;
        handle.Free();
        nint error = 0;
        nint value = webkit_web_view_run_javascript_finish(view, result, &error);
        if (value != 0) webkit_javascript_result_unref(value);
        if (error != 0) g_error_free(error);
        done.TrySetResult(error == 0);
    }

    // ----- Closing ----------------------------------------------------------

    private void Close()
    {
        if (!destroyed) gtk_window_close(window);
    }

    [UnmanagedCallersOnly]
    private static int DeleteEvent(nint widget, nint e, nint data) => current!.OnClosing() ? 1 : 0;

    // Returns true to keep the window open for now.
    private unsafe bool OnClosing()
    {
        if (canClose || !ready) return false;
        // Preparing the print layout, choosing a destination and writing the PDF
        // all precede the close-time autosave and its watchdog.
        if (pdfExportActive)
        {
            closeAfterPdfExport = true;
            return true;
        }
        if (closePending) return true;
        closePending = true;
        gtk_widget_set_sensitive(browser, false);
        closeTimer = g_timeout_add(12000, &CloseTimeout, 0);
        RequestFlushAndClose();
        return true;
    }

    private async void RequestFlushAndClose()
    {
        if (!await RunScript("window.dispatchEvent(new Event('inkrail-close-request'))") && !destroyed)
            CloseFailed();
    }

    [UnmanagedCallersOnly]
    private static int CloseTimeout(nint data)
    {
        var self = current!;
        self.closeTimer = 0;
        self.CloseFailed();
        return 0;
    }

    private void StopCloseTimer()
    {
        if (closeTimer != 0) g_source_remove(closeTimer);
        closeTimer = 0;
    }

    private void CloseFailed()
    {
        StopCloseTimer();
        if (!closePending || destroyed) return;
        closePending = false;
        gtk_widget_set_sensitive(browser, true);
        int answer = MessageBox(window,
            "Inkrail could not confirm that your writing was saved. Close anyway and lose any unsaved changes?",
            MessageWarning, ButtonsYesNo, ResponseNo);
        if (answer == ResponseYes) { canClose = true; Close(); }
        else gtk_widget_grab_focus(browser);
    }

    [UnmanagedCallersOnly]
    private static void Destroyed(nint widget, nint data)
    {
        var self = current!;
        self.destroyed = true;
        self.StopCloseTimer();
        if (self.smokeTimer != 0) g_source_remove(self.smokeTimer);
        self.smokeTimer = 0;
        gtk_main_quit();
    }

    // ----- Smoke test (-smoke): the desk booted and talked to the host -------

    private string SmokePdf => Path.Combine(Path.GetDirectoryName(library.Location)!, "smoke.pdf");

    private async void SmokeExportPdf()
    {
        Console.WriteLine("Inkrail smoke test: desk ready at " + library.Location);
        // Drive the real menu command: print layout, WebKit print-to-file, install.
        if (!await RunScript("document.querySelector('#commands [data-command=exportPDF]').click()"))
            SmokeFailed("could not start the PDF export.");
    }

    private void SmokeCheckPdf()
    {
        byte[] head = File.Exists(SmokePdf) ? File.ReadAllBytes(SmokePdf)[..Math.Min(5, (int)new FileInfo(SmokePdf).Length)] : [];
        if (System.Text.Encoding.ASCII.GetString(head) != "%PDF-") { SmokeFailed("no PDF was written."); return; }
        Console.WriteLine($"Inkrail smoke test: exported {SmokePdf} ({new FileInfo(SmokePdf).Length} bytes)");
        Close(); // Exercises the save-before-close round trip as well.
    }

    private void SmokeFailed(string reason)
    {
        Console.Error.WriteLine("Inkrail smoke test failed: " + reason);
        ExitCode = 1;
        canClose = true;
        Close();
    }

    [UnmanagedCallersOnly]
    private static int SmokeTimeout(nint data)
    {
        var self = current!;
        self.smokeTimer = 0;
        Console.Error.WriteLine("Inkrail smoke test: the desk did not become ready within 30 seconds.");
        self.ExitCode = 1;
        self.canClose = true;
        self.Close();
        return 0;
    }
}
