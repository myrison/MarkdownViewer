import AppKit
import Combine
import CoreGraphics
import Foundation
import Markdown
import SwiftUI
import WebKit

class DocumentState: ObservableObject {
    @Published var htmlContent: String = ""
    @Published var title: String = "Markdown Viewer"
    @Published var fileChanged: Bool = false
    @Published var outlineItems: [OutlineItem] = []
    @Published var reloadToken: UUID?
    @Published var zoomLevel: CGFloat = 1.0
    @Published var isShowingFindBar: Bool = false
    @Published var findQuery: String = ""
    @Published var findRequest: FindRequest?
    @Published var findFocusToken: UUID = UUID()
    @Published var wordCount: Int = 0
    @Published var characterCount: Int = 0
    @Published var readingTimeMinutes: Int = 0
    var currentURL: URL?
    weak var webView: WKWebView?
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var lastModificationDate: Date?
    private let recentFilesStore: RecentFilesStore

    private static let zoomLevelKey = "zoomLevel"

    init(recentFilesStore: RecentFilesStore = .shared) {
        self.recentFilesStore = recentFilesStore
        let saved = UserDefaults.standard.double(forKey: DocumentState.zoomLevelKey)
        if saved >= 0.5 && saved <= 3.0 {
            zoomLevel = saved
        }
    }

    deinit {
        stopMonitoring()
    }

    func loadFile(at url: URL) {
        currentURL = url
        fileChanged = false
        startMonitoring(url: url)
        recentFilesStore.add(url)
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let (frontMatter, content) = MarkdownDocumentParser.parseFrontMatter(markdown)
            let document = Document(parsing: content)
            var renderer = MarkdownRenderer()
            let rendered = renderer.render(document)
            let frontMatterHTML = renderFrontMatter(frontMatter)
            let bodyHTML = resolveRelativeImagePaths(frontMatterHTML + rendered.html, relativeTo: url.deletingLastPathComponent())
            htmlContent = wrapInHTML(bodyHTML, title: url.lastPathComponent)
            title = url.lastPathComponent
            outlineItems = MarkdownDocumentParser.normalizedOutline(rendered.outline)
            updateStatistics(content)
        } catch {
            htmlContent = wrapInHTML("<p>Error loading file: \(error.localizedDescription)</p>", title: "Error")
            title = "Error"
            outlineItems = []
            wordCount = 0
            characterCount = 0
            readingTimeMinutes = 0
        }
    }

    private func renderFrontMatter(_ frontMatter: [(String, String)]) -> String {
        guard !frontMatter.isEmpty else { return "" }

        var html = """
        <div class=\"front-matter\">
        <table class=\"front-matter-table\">
        """
        for (key, value) in frontMatter {
            let displayKey = key.replacingOccurrences(of: "_", with: " ").capitalized
            html += "<tr><td class=\"fm-key\">\(escapeHTML(displayKey))</td><td class=\"fm-value\">\(escapeHTML(value))</td></tr>\n"
        }
        html += "</table></div>\n"
        return html
    }

    /// Rewrites local `src` values in `<img>` tags to base64 data URIs so WKWebView
    /// can display them without file-system access restrictions.
    /// Remote URLs (http/https) and existing data URIs are left unchanged.
    private func resolveRelativeImagePaths(_ html: String, relativeTo dir: URL) -> String {
        var result = html
        let pattern = #"(<img\b[^>]*?\bsrc=)(["'])([^"']*)(["'])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return html
        }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        // Process in reverse so replacements don't shift string offsets
        for match in matches.reversed() {
            let srcRange = match.range(at: 3)
            let src = nsHTML.substring(with: srcRange)
            // Leave remote and already-embedded images alone
            if src.hasPrefix("http://") || src.hasPrefix("https://") || src.hasPrefix("data:") || src.hasPrefix("//") {
                continue
            }
            // Resolve path: support relative paths and file:// URLs
            let fileURL: URL
            if src.hasPrefix("file://") {
                guard let u = URL(string: src) else { continue }
                fileURL = u
            } else {
                fileURL = dir.appendingPathComponent(src)
            }
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            let mime = mimeType(for: fileURL.pathExtension)
            let dataURI = "data:\(mime);base64,\(data.base64EncodedString())"
            let fullMatchRange = match.range
            let fullMatch = nsHTML.substring(with: fullMatchRange)
            let quote2Range = match.range(at: 4)
            let before = (fullMatch as NSString).substring(to: srcRange.location - fullMatchRange.location)
            let after = (fullMatch as NSString).substring(from: quote2Range.location - fullMatchRange.location)
            let resultRange = Range(fullMatchRange, in: result)!
            result = result.replacingCharacters(in: resultRange, with: before + dataURI + after)
        }
        return result
    }

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "png":  return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":  return "image/gif"
        case "webp": return "image/webp"
        case "svg":  return "image/svg+xml"
        case "ico":  return "image/x-icon"
        default:     return "image/png"
        }
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    func printDocument() {
        guard let webView = webView, let window = webView.window else {
            NSSound.beep()
            return
        }
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        if let filename = currentURL?.deletingPathExtension().lastPathComponent {
            printInfo.jobDisposition = .spool
            printInfo.dictionary().setObject(filename, forKey: NSPrintInfo.AttributeKey.jobSavingURL as NSCopying)
        }
        let op = webView.printOperation(with: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    private func updateStatistics(_ markdown: String) {
        let words = markdown.split { $0.isWhitespace || $0.isNewline }
        wordCount = words.count
        characterCount = markdown.count
        if wordCount == 0 {
            readingTimeMinutes = 0
        } else {
            readingTimeMinutes = max(1, Int(ceil(Double(wordCount) / 265.0)))
        }
    }

    func reload() {
        guard let url = currentURL else { return }
        reloadToken = UUID()
        loadFile(at: url)
    }

    func zoomIn() {
        zoomLevel = min(zoomLevel + 0.1, 3.0)
        saveZoomLevel()
    }

    func zoomOut() {
        zoomLevel = max(zoomLevel - 0.1, 0.5)
        saveZoomLevel()
    }

    func resetZoom() {
        zoomLevel = 1.0
        saveZoomLevel()
    }

    private func saveZoomLevel() {
        UserDefaults.standard.set(Double(zoomLevel), forKey: DocumentState.zoomLevelKey)
    }

    func showFindBar() {
        let wasShowing = isShowingFindBar
        isShowingFindBar = true
        findFocusToken = UUID()
        if !wasShowing {
            updateFindResults()
        }
    }

    func hideFindBar() {
        isShowingFindBar = false
        clearFindHighlights()
    }

    func updateFindResults() {
        requestFind(direction: .forward, reset: true)
    }

    func findNext() {
        requestFind(direction: .forward, reset: false)
    }

    func findPrevious() {
        requestFind(direction: .backward, reset: false)
    }

    private func startMonitoring(url: URL) {
        stopMonitoring()

        let fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        lastModificationDate = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        fileMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        fileMonitor?.setEventHandler { [weak self] in
            guard let self = self else { return }
            let newModDate = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            if newModDate != self.lastModificationDate {
                self.lastModificationDate = newModDate
                self.reload()
                withAnimation(.easeInOut(duration: 0.2)) { self.fileChanged = true }
                if UserDefaults.standard.bool(forKey: "autoRaiseOnFileChange") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
        }

        fileMonitor?.setCancelHandler {
            close(fileDescriptor)
        }

        fileMonitor?.resume()
    }

    private func stopMonitoring() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    private func requestFind(direction: FindDirection, reset: Bool) {
        let trimmed = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            findRequest = FindRequest(query: "", direction: .forward, token: UUID(), reset: true)
            return
        }
        findRequest = FindRequest(query: trimmed, direction: direction, token: UUID(), reset: reset)
    }

    private func clearFindHighlights() {
        findRequest = FindRequest(query: "", direction: .forward, token: UUID(), reset: true)
    }

    private func wrapInHTML(_ body: String, title: String) -> String {
        MarkdownHTMLTemplate.shared.render(body: body, title: title)
    }
}
