using System.Collections.Concurrent;
using System.Runtime.InteropServices;

namespace Inkrail.Linux;

// Minimal GLib, GTK 3 and WebKitGTK 4.1 bindings. Only the calls the desk uses.
internal static unsafe partial class Native
{
    private const string GLib = "libglib-2.0.so.0";
    private const string GObject = "libgobject-2.0.so.0";
    private const string Gio = "libgio-2.0.so.0";
    private const string Gtk = "libgtk-3.so.0";
    private const string WebKit = "libwebkit2gtk-4.1.so.0";
    private const string Jsc = "libjavascriptcoregtk-4.1.so.0";

    // GLib
    [LibraryImport(GLib)] public static partial uint g_idle_add(delegate* unmanaged<nint, int> function, nint data);
    [LibraryImport(GLib)] public static partial uint g_timeout_add(uint interval, delegate* unmanaged<nint, int> function, nint data);
    [LibraryImport(GLib)] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool g_source_remove(uint id);
    [LibraryImport(GLib)] public static partial nint g_malloc(nuint size);
    [LibraryImport(GLib)] public static partial void g_free(nint memory);
    public static readonly nint GFree = NativeLibrary.GetExport(NativeLibrary.Load(GLib), "g_free");
    [LibraryImport(GLib, StringMarshalling = StringMarshalling.Utf8)] public static partial nint g_markup_escape_text(string text, nint length);
    [LibraryImport(GLib, StringMarshalling = StringMarshalling.Utf8)] public static partial uint g_quark_from_string(string text);
    [LibraryImport(GLib, StringMarshalling = StringMarshalling.Utf8)] public static partial nint g_error_new_literal(uint domain, int code, string message);
    [LibraryImport(GLib)] public static partial void g_error_free(nint error);
    [LibraryImport(GLib, StringMarshalling = StringMarshalling.Utf8)] public static partial void g_set_prgname(string name);
    [LibraryImport(GLib, StringMarshalling = StringMarshalling.Utf8)] public static partial void g_set_application_name(string name);
    [LibraryImport(GLib, StringMarshalling = StringMarshalling.Utf8)] public static partial nint g_filename_to_uri(string filename, nint hostname, nint error);

    // libc: the native environment, which WebKit reads (Environment.SetEnvironmentVariable does not reach it).
    [LibraryImport("libc", StringMarshalling = StringMarshalling.Utf8)] public static partial int setenv(string name, string value, int overwrite);

    // GObject
    [LibraryImport(GObject, StringMarshalling = StringMarshalling.Utf8)]
    public static partial ulong g_signal_connect_data(nint instance, string signal, nint handler, nint data, nint destroy, int flags);
    [LibraryImport(GObject)] public static partial void g_object_unref(nint instance);

    // GIO
    [LibraryImport(Gio)] public static partial nint g_memory_input_stream_new_from_data(nint data, nint length, nint destroy);

    // GTK
    [LibraryImport(Gtk)] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool gtk_init_check(nint argc, nint argv);
    [LibraryImport(Gtk)] public static partial void gtk_main();
    [LibraryImport(Gtk)] public static partial void gtk_main_quit();
    [LibraryImport(Gtk)] public static partial nint gtk_window_new(int type);
    [LibraryImport(Gtk, StringMarshalling = StringMarshalling.Utf8)] public static partial void gtk_window_set_title(nint window, string title);
    [LibraryImport(Gtk)] public static partial void gtk_window_set_default_size(nint window, int width, int height);
    [LibraryImport(Gtk)] public static partial void gtk_window_set_position(nint window, int position);
    [LibraryImport(Gtk, StringMarshalling = StringMarshalling.Utf8)]
    [return: MarshalAs(UnmanagedType.Bool)] public static partial bool gtk_window_set_icon_from_file(nint window, string file, nint error);
    [LibraryImport(Gtk)] public static partial void gtk_window_close(nint window);
    [LibraryImport(Gtk)] public static partial void gtk_window_present(nint window);
    [LibraryImport(Gtk)] public static partial void gtk_widget_set_size_request(nint widget, int width, int height);
    [LibraryImport(Gtk)] public static partial void gtk_container_add(nint container, nint widget);
    [LibraryImport(Gtk)] public static partial void gtk_widget_show_all(nint widget);
    [LibraryImport(Gtk)] public static partial void gtk_widget_destroy(nint widget);
    [LibraryImport(Gtk)] public static partial void gtk_widget_grab_focus(nint widget);
    [LibraryImport(Gtk)] public static partial void gtk_widget_set_sensitive(nint widget, [MarshalAs(UnmanagedType.Bool)] bool sensitive);
    [LibraryImport(Gtk, StringMarshalling = StringMarshalling.Utf8)]
    [return: MarshalAs(UnmanagedType.Bool)] public static partial bool gtk_show_uri_on_window(nint parent, string uri, uint timestamp, nint error);

    // Message dialogs (message_format is NULL; the text is set as escaped markup).
    [LibraryImport(Gtk)] public static partial nint gtk_message_dialog_new(nint parent, int flags, int type, int buttons, nint format);
    [LibraryImport(Gtk)] public static partial void gtk_message_dialog_set_markup(nint dialog, nint markup);
    [LibraryImport(Gtk)] public static partial int gtk_dialog_run(nint dialog);
    [LibraryImport(Gtk)] public static partial void gtk_dialog_set_default_response(nint dialog, int response);

    // File choosers
    [LibraryImport(Gtk, StringMarshalling = StringMarshalling.Utf8)]
    public static partial nint gtk_file_chooser_native_new(string title, nint parent, int action, string accept, string cancel);
    [LibraryImport(Gtk)] public static partial int gtk_native_dialog_run(nint dialog);
    [LibraryImport(Gtk)] public static partial nint gtk_file_chooser_get_filename(nint chooser);
    [LibraryImport(Gtk, StringMarshalling = StringMarshalling.Utf8)] public static partial void gtk_file_chooser_set_current_name(nint chooser, string name);
    [LibraryImport(Gtk)] public static partial void gtk_file_chooser_set_do_overwrite_confirmation(nint chooser, [MarshalAs(UnmanagedType.Bool)] bool confirm);
    [LibraryImport(Gtk)] public static partial void gtk_file_chooser_set_create_folders(nint chooser, [MarshalAs(UnmanagedType.Bool)] bool create);
    [LibraryImport(Gtk)] public static partial void gtk_file_chooser_add_filter(nint chooser, nint filter);
    [LibraryImport(Gtk)] public static partial nint gtk_file_filter_new();
    [LibraryImport(Gtk, StringMarshalling = StringMarshalling.Utf8)] public static partial void gtk_file_filter_set_name(nint filter, string name);
    [LibraryImport(Gtk, StringMarshalling = StringMarshalling.Utf8)] public static partial void gtk_file_filter_add_pattern(nint filter, string pattern);

    // Printing
    [LibraryImport(Gtk)] public static partial nint gtk_print_settings_new();
    [LibraryImport(Gtk, StringMarshalling = StringMarshalling.Utf8)] public static partial void gtk_print_settings_set(nint settings, string key, string value);
    [LibraryImport(Gtk, StringMarshalling = StringMarshalling.Utf8)] public static partial void gtk_print_settings_set_printer(nint settings, string printer);
    [LibraryImport(Gtk)] public static partial void gtk_print_settings_set_paper_size(nint settings, nint paper);
    [LibraryImport(Gtk)] public static partial void gtk_print_settings_set_orientation(nint settings, int orientation);
    [LibraryImport(Gtk)] public static partial nint gtk_page_setup_new();
    [LibraryImport(Gtk)] public static partial void gtk_page_setup_set_paper_size(nint setup, nint paper);
    [LibraryImport(Gtk)] public static partial void gtk_page_setup_set_orientation(nint setup, int orientation);
    [LibraryImport(Gtk)] public static partial void gtk_page_setup_set_top_margin(nint setup, double margin, int unit);
    [LibraryImport(Gtk)] public static partial void gtk_page_setup_set_bottom_margin(nint setup, double margin, int unit);
    [LibraryImport(Gtk)] public static partial void gtk_page_setup_set_left_margin(nint setup, double margin, int unit);
    [LibraryImport(Gtk)] public static partial void gtk_page_setup_set_right_margin(nint setup, double margin, int unit);
    [LibraryImport(Gtk, StringMarshalling = StringMarshalling.Utf8)]
    public static partial nint gtk_paper_size_new_custom(string name, string displayName, double width, double height, int unit);
    [LibraryImport(Gtk)] public static partial void gtk_paper_size_free(nint paper);

    // WebKitGTK
    [LibraryImport(WebKit)] public static partial nint webkit_web_context_get_default();
    [LibraryImport(WebKit, StringMarshalling = StringMarshalling.Utf8)]
    public static partial void webkit_web_context_register_uri_scheme(nint context, string scheme, delegate* unmanaged<nint, nint, void> callback, nint data, nint destroy);
    [LibraryImport(WebKit)] public static partial nint webkit_web_context_get_security_manager(nint context);
    [LibraryImport(WebKit, StringMarshalling = StringMarshalling.Utf8)] public static partial void webkit_security_manager_register_uri_scheme_as_secure(nint manager, string scheme);
    [LibraryImport(WebKit, StringMarshalling = StringMarshalling.Utf8)] public static partial void webkit_security_manager_register_uri_scheme_as_cors_enabled(nint manager, string scheme);
    [LibraryImport(WebKit)] public static partial nint webkit_user_content_manager_new();
    [LibraryImport(WebKit, StringMarshalling = StringMarshalling.Utf8)]
    [return: MarshalAs(UnmanagedType.Bool)] public static partial bool webkit_user_content_manager_register_script_message_handler(nint manager, string name);
    [LibraryImport(WebKit)] public static partial nint webkit_web_view_new_with_user_content_manager(nint manager);
    [LibraryImport(WebKit)] public static partial nint webkit_web_view_get_settings(nint view);
    [LibraryImport(WebKit, StringMarshalling = StringMarshalling.Utf8)] public static partial void webkit_web_view_load_uri(nint view, string uri);
    [LibraryImport(WebKit)] public static partial nint webkit_web_view_get_uri(nint view);
    [LibraryImport(WebKit, StringMarshalling = StringMarshalling.Utf8)]
    public static partial void webkit_web_view_run_javascript(nint view, string script, nint cancellable, delegate* unmanaged<nint, nint, nint, void> callback, nint data);
    [LibraryImport(WebKit)] public static partial nint webkit_web_view_run_javascript_finish(nint view, nint result, nint* error);
    [LibraryImport(WebKit)] public static partial void webkit_javascript_result_unref(nint result);
    [LibraryImport(WebKit)] public static partial nint webkit_javascript_result_get_js_value(nint result);
    [LibraryImport(Jsc)] public static partial nint jsc_value_to_string(nint value);
    [LibraryImport(Jsc)] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool jsc_value_is_string(nint value);
    [LibraryImport(WebKit)] public static partial void webkit_settings_set_enable_developer_extras(nint settings, [MarshalAs(UnmanagedType.Bool)] bool enabled);
    [LibraryImport(WebKit)] public static partial void webkit_settings_set_javascript_can_open_windows_automatically(nint settings, [MarshalAs(UnmanagedType.Bool)] bool enabled);
    [LibraryImport(WebKit)] public static partial void webkit_settings_set_enable_back_forward_navigation_gestures(nint settings, [MarshalAs(UnmanagedType.Bool)] bool enabled);
    [LibraryImport(WebKit)] public static partial void webkit_settings_set_print_backgrounds(nint settings, [MarshalAs(UnmanagedType.Bool)] bool enabled);
    [LibraryImport(WebKit)] public static partial void webkit_settings_set_enable_write_console_messages_to_stdout(nint settings, [MarshalAs(UnmanagedType.Bool)] bool enabled);
    [LibraryImport(WebKit)] public static partial nint webkit_uri_scheme_request_get_uri(nint request);
    [LibraryImport(WebKit)] public static partial nint webkit_uri_scheme_request_get_path(nint request);
    [LibraryImport(WebKit, StringMarshalling = StringMarshalling.Utf8)]
    public static partial void webkit_uri_scheme_request_finish(nint request, nint stream, long length, string contentType);
    [LibraryImport(WebKit)] public static partial void webkit_uri_scheme_request_finish_error(nint request, nint error);
    [LibraryImport(WebKit)] public static partial void webkit_policy_decision_ignore(nint decision);
    [LibraryImport(WebKit)] public static partial nint webkit_navigation_policy_decision_get_navigation_action(nint decision);
    [LibraryImport(WebKit)] public static partial nint webkit_navigation_action_get_request(nint action);
    [LibraryImport(WebKit)] public static partial nint webkit_uri_request_get_uri(nint request);
    [LibraryImport(WebKit)] [return: MarshalAs(UnmanagedType.Bool)] public static partial bool webkit_response_policy_decision_is_mime_type_supported(nint decision);
    [LibraryImport(WebKit)] public static partial void webkit_permission_request_deny(nint request);
    [LibraryImport(WebKit)] public static partial uint webkit_context_menu_get_n_items(nint menu);
    [LibraryImport(WebKit)] public static partial nint webkit_context_menu_get_item_at_position(nint menu, uint position);
    [LibraryImport(WebKit)] public static partial void webkit_context_menu_remove(nint menu, nint item);
    [LibraryImport(WebKit)] public static partial int webkit_context_menu_item_get_stock_action(nint item);
    [LibraryImport(WebKit)] public static partial nint webkit_print_operation_new(nint view);
    [LibraryImport(WebKit)] public static partial void webkit_print_operation_set_print_settings(nint operation, nint settings);
    [LibraryImport(WebKit)] public static partial void webkit_print_operation_set_page_setup(nint operation, nint setup);
    [LibraryImport(WebKit)] public static partial void webkit_print_operation_print(nint operation);

    public const int ResponseAccept = -3, ResponseYes = -8, ResponseNo = -9;
    public const int MessageInfo = 0, MessageWarning = 1, MessageError = 3;
    public const int ButtonsOk = 1, ButtonsYesNo = 4;
    public const int DialogModal = 1, DialogDestroyWithParent = 2;
    public const int UnitInch = 2;

    public static string? Utf8(nint text) => text == 0 ? null : Marshal.PtrToStringUTF8(text);

    public static string? TakeUtf8(nint text)
    {
        try { return Utf8(text); }
        finally { if (text != 0) g_free(text); }
    }

    public static string FileUri(string path) =>
        TakeUtf8(g_filename_to_uri(path, 0, 0)) ?? throw new IOException("Could not open " + path);

    public static ulong Connect(nint instance, string signal, nint handler, nint data = 0) =>
        g_signal_connect_data(instance, signal, handler, data, 0, 0);

    public static int MessageBox(nint parent, string text, int type, int buttons, int defaultResponse = 0)
    {
        nint dialog = gtk_message_dialog_new(parent, DialogModal | DialogDestroyWithParent, type, buttons, 0);
        nint markup = g_markup_escape_text(text, -1);
        try { gtk_message_dialog_set_markup(dialog, markup); }
        finally { g_free(markup); }
        gtk_window_set_title(dialog, "Inkrail");
        if (defaultResponse != 0) gtk_dialog_set_default_response(dialog, defaultResponse);
        int answer = gtk_dialog_run(dialog);
        gtk_widget_destroy(dialog);
        return answer;
    }
}

// Runs async continuations on the GTK main loop, like WinForms' BeginInvoke.
internal sealed unsafe class GLibContext : SynchronizationContext
{
    private static readonly ConcurrentQueue<(SendOrPostCallback, object?)> Work = new();

    public override void Post(SendOrPostCallback callback, object? state)
    {
        Work.Enqueue((callback, state));
        Native.g_idle_add(&Run, 0);
    }

    public override void Send(SendOrPostCallback callback, object? state) => throw new NotSupportedException();
    public override SynchronizationContext CreateCopy() => this;

    [UnmanagedCallersOnly]
    private static int Run(nint _)
    {
        if (Work.TryDequeue(out var item))
        {
            try { item.Item1(item.Item2); }
            catch (Exception error) { Console.Error.WriteLine("Inkrail: " + error); }
        }
        return 0; // G_SOURCE_REMOVE
    }
}
