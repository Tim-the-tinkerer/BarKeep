import AppKit
import WebKit

/// Shows the bundled BarKeep help book in an in-app window (reliable for ad-hoc signed builds).
@MainActor
enum HelpPresenter {
    private static var windowController: HelpWindowController?

    static func showHelp() {
        if windowController == nil {
            windowController = HelpWindowController()
        }
        windowController?.showWindow()
    }

    static func helpHTMLURL() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let candidates = [
            resources.appendingPathComponent("BarKeep.help/Contents/Resources/English.lproj/index.html"),
            resources.appendingPathComponent("BarKeep.help/Contents/Resources/en.lproj/index.html"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    fileprivate static func resetWindowController() {
        windowController = nil
    }
}

@MainActor
private final class HelpWindowController: NSWindowController, NSWindowDelegate {
    private let helpWebView: WKWebView

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BarKeep Help"
        window.minSize = NSSize(width: 560, height: 400)
        window.center()
        window.setFrameAutosaveName("BarKeepHelpWindow")

        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        self.helpWebView = webView

        super.init(window: window)
        window.delegate = self
        window.contentView = webView

        if #available(macOS 10.14, *) {
            webView.appearance = NSApp.effectiveAppearance
        }

        if let url = HelpPresenter.helpHTMLURL() {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            let html = """
            <html><body style="font: -apple-system-body; padding: 24px; color: CanvasText; background: Canvas;">
            <h1>Help unavailable</h1>
            <p>The help book could not be found in the app bundle.</p>
            <p>Rebuild with <code>./build-app.sh</code> to restore it.</p>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        if #available(macOS 10.14, *) {
            helpWebView.appearance = NSApp.effectiveAppearance
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === window {
            HelpPresenter.resetWindowController()
        }
    }
}
