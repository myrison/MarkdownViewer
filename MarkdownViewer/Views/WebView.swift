import Foundation
import SwiftUI
import WebKit

private struct FindPayload: Encodable {
    let query: String
    let direction: String
    let reset: Bool
}

// WKUserContentController retains its message handlers strongly, which prevents
// the WKWebView from deallocating. This proxy breaks that retain cycle.
private class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(_ delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

struct WebView: NSViewRepresentable {
    let htmlContent: String
    let scrollRequest: ScrollRequest?
    let reloadToken: UUID?
    let zoomLevel: CGFloat
    let findRequest: FindRequest?
    let onActiveAnchorChange: ((String?) -> Void)?
    let documentState: DocumentState?

    func makeCoordinator() -> Coordinator {
        Coordinator(onActiveAnchorChange: onActiveAnchorChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(WeakScriptMessageHandler(context.coordinator), name: "outlinePosition")
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.pageZoom = zoomLevel
        context.coordinator.lastZoomLevel = zoomLevel
        documentState?.webView = webView
        return webView
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "outlinePosition")
        coordinator.cleanUpTempFile()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if htmlContent != context.coordinator.lastHTML {
            let shouldPreserveScroll = reloadToken != nil && reloadToken != context.coordinator.lastReloadToken
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.lastHTML = htmlContent
            context.coordinator.isLoading = true
            context.coordinator.lastActiveAnchorID = nil

            if shouldPreserveScroll {
                let coordinator = context.coordinator
                webView.evaluateJavaScript("window.scrollY") { result, _ in
                    coordinator.savedScrollY = (result as? CGFloat) ?? 0
                    coordinator.loadHTML(htmlContent, in: webView)
                }
            } else {
                context.coordinator.loadHTML(htmlContent, in: webView)
            }
        }

        if let request = scrollRequest {
            context.coordinator.requestScroll(request, in: webView)
        }

        if zoomLevel != context.coordinator.lastZoomLevel {
            context.coordinator.lastZoomLevel = zoomLevel
            webView.pageZoom = zoomLevel
        }

        if let request = findRequest {
            context.coordinator.requestFind(request, in: webView)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML: String?
        var pendingAnchor: String?
        var pendingToken: UUID?
        var lastHandledToken: UUID?
        var isLoading = false
        var lastReloadToken: UUID?
        var savedScrollY: CGFloat = 0
        var lastZoomLevel: CGFloat = 1.0
        var pendingFindRequest: FindRequest?
        var lastFindToken: UUID?
        var lastActiveAnchorID: String?
        private var currentTempFile: URL?
        private let onActiveAnchorChange: ((String?) -> Void)?

        // Resources URL used as the base for scripts/styles and for granting
        // content-process read access. Resolved once at init time.
        private static let resourcesURL: URL? = Bundle.module.resourceURL ?? Bundle.main.resourceURL

        init(onActiveAnchorChange: ((String?) -> Void)?) {
            self.onActiveAnchorChange = onActiveAnchorChange
        }

        // MARK: - HTML loading

        /// Loads HTML using a temporary file written into the resources bundle
        /// directory so that loadFileURL can grant the WKWebView content process
        /// explicit read access to that directory. loadHTMLString with a file://
        /// base URL does NOT reliably grant the sandboxed content process access
        /// to load external scripts, which caused find.js (and all other scripts)
        /// to silently fail after the memory-leak fix switched from inlining to
        /// external <script src="..."> references.
        ///
        /// The temp HTML file lives inside resourcesURL so that the
        /// allowingReadAccessTo parameter is valid (it must be at or above the
        /// file being loaded). Relative <script src> and <link href> paths in the
        /// HTML resolve against resourcesURL because the HTML is in the same dir.
        func loadHTML(_ html: String, in webView: WKWebView) {
            guard let resourcesURL = Self.resourcesURL else {
                webView.loadHTMLString(html, baseURL: nil)
                return
            }

            // Write the HTML as a temp file inside the resources bundle so that
            // allowingReadAccessTo covers both the HTML file and the scripts/CSS.
            let tmpFile = resourcesURL.appendingPathComponent("mv_\(UUID().uuidString).html")

            do {
                try html.write(to: tmpFile, atomically: true, encoding: .utf8)
            } catch {
                // Bundle not writable (e.g. signed/read-only); fall back to
                // loadHTMLString which shows content but scripts may not load.
                webView.loadHTMLString(html, baseURL: resourcesURL)
                return
            }

            cleanUpTempFile()
            currentTempFile = tmpFile

            // allowingReadAccessTo: resourcesURL is valid because tmpFile is
            // inside resourcesURL, and it also grants access to all scripts/CSS
            // in the same directory.
            webView.loadFileURL(tmpFile, allowingReadAccessTo: resourcesURL)
        }

        func cleanUpTempFile() {
            if let url = currentTempFile {
                try? FileManager.default.removeItem(at: url)
                currentTempFile = nil
            }
        }

        // MARK: - Scrolling

        func requestScroll(_ request: ScrollRequest, in webView: WKWebView) {
            guard request.token != lastHandledToken else { return }
            pendingAnchor = request.id
            pendingToken = request.token
            if !isLoading {
                performScroll(in: webView)
            }
        }

        // MARK: - Navigation delegate

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false

            if lastZoomLevel != 1.0 {
                webView.pageZoom = lastZoomLevel
            }

            if savedScrollY > 0 {
                let scrollY = savedScrollY
                savedScrollY = 0
                webView.evaluateJavaScript("window.scrollTo(0, \(scrollY))", completionHandler: nil)
            }

            performScroll(in: webView)
            performFind(in: webView)
        }

        private func performScroll(in webView: WKWebView) {
            guard let anchor = pendingAnchor, let token = pendingToken else { return }
            pendingAnchor = nil
            pendingToken = nil
            lastHandledToken = token

            let escaped = anchor
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let script = "var el = document.getElementById('\(escaped)'); if (el) { el.scrollIntoView(); }"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        // MARK: - Find

        func requestFind(_ request: FindRequest, in webView: WKWebView) {
            guard request.token != lastFindToken else { return }
            lastFindToken = request.token
            pendingFindRequest = request
            if !isLoading {
                performFind(in: webView)
            }
        }

        private func performFind(in webView: WKWebView) {
            guard let request = pendingFindRequest else { return }
            pendingFindRequest = nil
            let payload = FindPayload(
                query: request.query,
                direction: request.direction == .backward ? "backward" : "forward",
                reset: request.reset
            )
            guard let data = try? JSONEncoder().encode(payload),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }
            webView.evaluateJavaScript("window.__markdownViewerFind(\(json));", completionHandler: nil)
        }

        // MARK: - Script message handler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "outlinePosition" else { return }
            var anchorID: String?
            if let body = message.body as? [String: Any] {
                anchorID = body["id"] as? String
            } else if let body = message.body as? String {
                anchorID = body
            }
            if anchorID?.isEmpty == true {
                anchorID = nil
            }
            guard anchorID != lastActiveAnchorID else { return }
            lastActiveAnchorID = anchorID
            DispatchQueue.main.async { [onActiveAnchorChange] in
                onActiveAnchorChange?(anchorID)
            }
        }
    }
}
