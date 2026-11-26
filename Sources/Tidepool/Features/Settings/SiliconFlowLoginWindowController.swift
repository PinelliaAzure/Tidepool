import AppKit
import WebKit

/// Tidepool 内置的硅基流动登录窗口：登录完成后直接读取 WKWebView 的会话 Cookie。
/// 不需要读取 Safari/Chrome 的数据，也不会要求「完全磁盘访问权限」。
@MainActor
final class SiliconFlowLoginWindowController: NSObject, WKNavigationDelegate, NSWindowDelegate {
    static let shared = SiliconFlowLoginWindowController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var statusLabel: NSTextField?
    private var finishButton: NSButton?
    private var completion: ((SiliconFlowSession) -> Void)?

    private let loginURL = URL(string: "https://cloud.siliconflow.cn/me/expensebill")!

    func show(completion: @escaping (SiliconFlowSession) -> Void) {
        self.completion = completion

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        let status = NSTextField(labelWithString: T("请在窗口中登录硅基流动", "Sign in to SiliconFlow in this window"))
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        statusLabel = status

        let cancel = NSButton(title: T("取消", "Cancel"), target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded

        let finish = NSButton(title: T("完成", "Done"), target: self, action: #selector(finishTapped))
        finish.bezelStyle = .rounded
        finish.keyEquivalent = "\r"
        finish.isEnabled = false
        finishButton = finish

        let bar = NSStackView(views: [status, NSView(), cancel, finish])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        bar.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(webView)
        content.addSubview(bar)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: content.topAnchor),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 48)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = T("登录硅基流动", "Sign in to SiliconFlow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = content
        window.minSize = NSSize(width: 720, height: 560)
        window.center()
        self.window = window
#if DEBUG
        print("TIDEPOOL_LOGIN_WINDOW_ID \(window.windowNumber)")
#endif
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.load(URLRequest(url: loginURL))
    }

    static func clearWebSession() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast) {}
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        close()
    }

    @objc private func finishTapped() {
        guard let webView else { return }
        finishButton?.isEnabled = false
        setStatus(T("正在读取登录态…", "Reading session…"), color: .secondaryLabelColor)

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let relevant = cookies.filter { $0.domain.contains("siliconflow.cn") }
            let header = HTTPCookie.requestHeaderFields(with: relevant)["Cookie"] ?? ""
            let authenticated = relevant.contains {
                $0.name == "__SF_auth.session-token" && !$0.value.isEmpty
            }

            guard authenticated, !header.isEmpty else {
                self.finishButton?.isEnabled = true
                self.setStatus(
                    T("还没有检测到登录态，请先在窗口中完成登录。", "No session yet — finish signing in first."),
                    color: .systemRed
                )
                return
            }

            let session = SiliconFlowSession(
                cookie: header,
                subjectID: nil,
                source: T("Tidepool 登录", "Tidepool sign-in"),
                savedAt: Date(),
                userAgent: nil
            )

            Task { @MainActor in
                do {
                    _ = try await SiliconFlowConsoleClient().fetch(session: session)
                    self.completion?(session)
                    self.close()
                } catch {
                    self.finishButton?.isEnabled = true
                    let message = (error as? ProviderError)?.errorDescription ?? error.localizedDescription
                    self.setStatus(message, color: .systemRed)
                }
            }
        }
    }

    private func close() {
        window?.close()
        window = nil
        webView = nil
        statusLabel = nil
        finishButton = nil
    }

    private func setStatus(_ text: String, color: NSColor) {
        statusLabel?.stringValue = text
        statusLabel?.textColor = color
    }

    private func refreshLoginState() {
        guard let webView else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let authenticated = cookies.contains {
                $0.domain.contains("siliconflow.cn")
                    && $0.name == "__SF_auth.session-token"
                    && !$0.value.isEmpty
            }
            if authenticated {
                self.finishButton?.isEnabled = true
                self.setStatus(T("已登录，点击「完成」。", "Signed in — click Done."), color: .secondaryLabelColor)
            } else {
                self.finishButton?.isEnabled = false
                self.setStatus(T("请在窗口中登录硅基流动", "Sign in to SiliconFlow in this window"), color: .secondaryLabelColor)
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshLoginState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        setStatus(error.localizedDescription, color: .systemRed)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        setStatus(error.localizedDescription, color: .systemRed)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
        webView = nil
        statusLabel = nil
        finishButton = nil
    }
}
