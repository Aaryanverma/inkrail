import AppKit
import WebKit

// Exercise the same local HTML file a recipient opens, with a temporary WebKit data store.
@MainActor private final class ReaderCheck: NSObject, WKNavigationDelegate {
    let view: WKWebView
    let window: NSWindow
    private enum Stage { case loading, opening, reloading }
    private var stage = Stage.loading

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 390, height: 760), configuration: configuration)
        window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.contentView = view
        view.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        switch stage {
        case .loading:
            stage = .opening
            view.callAsyncJavaScript(Self.openLetter, arguments: [:], in: nil, in: .page) { result in
                if case .failure(let error) = result { print("Protected reader: \(error)"); exit(1) }
                self.stage = .reloading
                self.view.reload()
            }
        case .opening:
            break
        case .reloading:
            view.evaluateJavaScript("""
                document.querySelector('#open-envelope') instanceof HTMLButtonElement &&
                !document.querySelector('#password-dialog').open &&
                !document.querySelector('#letter-body')
                """) { value, error in
                    guard value as? Bool == true else {
                        print("Reload did not restore the locked envelope. \(String(describing: error))"); exit(1)
                    }
                    print("Protected reader prompts at the seal, keeps it intact on a wrong password, unfolds on authentication, and relocks on reload.")
                    exit(0)
                }
        }
    }

    private static let openLetter = """
        const get = id => document.getElementById(id);
        function check(condition, message) { if (!condition) throw new Error(message); }
        async function waitFor(condition, message) {
            const end = performance.now() + 8000;
            while (!condition() && performance.now() < end) await new Promise(resolve => setTimeout(resolve, 30));
            check(condition(), message);
        }
        const envelope = get('open-envelope'), dialog = get('password-dialog'), password = get('letter-password');
        check(envelope instanceof HTMLButtonElement && !envelope.disabled && envelope.getBoundingClientRect().width > 0,
              'The sealed envelope must be an available, keyboard-accessible button.');
        check(!dialog.open && !get('letter-body'), 'The recipient should see only the envelope.');
        get('sound-toggle').click();
        envelope.focus();
        envelope.click();
        check(dialog.open && document.activeElement === password, 'Activating the envelope must focus the password field.');
        password.value = 'canceled input';
        get('cancel-unlock').click();
        await waitFor(() => !dialog.open && document.activeElement === envelope && password.value === '',
                      'Cancel must clear the password and return focus to the envelope.');
        envelope.click();
        const cover = get('cover');
        const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
        let sawSealedFeedback = false;
        const feedback = new MutationObserver(() => {
            if (cover.dataset.sealState === 'resisting') {
                sawSealedFeedback = !dialog.open && !get('letter-body') && get('seal-art').isConnected;
            }
        });
        feedback.observe(cover, {attributes:true, attributeFilter:['data-seal-state']});
        password.value = 'wrong password';
        get('show-password').click();
        get('unlock-form').requestSubmit();
        await waitFor(() => dialog.open && password.getAttribute('aria-invalid') === 'true',
                      'A wrong password must return to the prompt.');
        feedback.disconnect();
        check(reducedMotion || sawSealedFeedback, 'The seal must visibly resist before the retry prompt appears.');
        check(cover.dataset.sealState !== 'resisting' && !get('letter-body'), 'The letter must remain closed for retry.');
        check(document.activeElement === password && password.value === '' && password.type === 'password' &&
              !password.readOnly && !get('unlock-letter').disabled && get('unlock-status').textContent.trim(),
              'Retry must explain the failure and focus a fresh masked password field.');
        password.value = 'little blue cup at dawn';
        password.dispatchEvent(new Event('input', {bubbles:true}));
        get('unlock-form').requestSubmit();
        await waitFor(() => document.documentElement.dataset.phase === 'open',
                      'Authenticating must unfold the letter without a second envelope click.');
        check(get('letter-body').textContent.includes('Dear Mira') && document.activeElement === get('letter'),
              'The revealed letter should contain the writing and receive reading focus.');
        check(get('sound-toggle').getAttribute('aria-pressed') === 'false', 'Muting the envelope must carry through the reveal.');
        check(!performance.getEntriesByType('resource').some(entry => /^https?:/.test(entry.name)),
              'Opening the exported file must work without remote resources.');
        """
}

@main private enum RunReaderCheck {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let check = ReaderCheck()
        let file = URL(fileURLWithPath: CommandLine.arguments[1])
        check.view.loadFileURL(file, allowingReadAccessTo: file)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { print("Protected reader check timed out."); exit(1) }
        withExtendedLifetime(check) { app.run() }
    }
}
