import Foundation

struct MarkdownHTMLTemplate {
    static let shared = MarkdownHTMLTemplate()

    private static let titleToken = "__MARKDOWN_VIEWER_TITLE__"
    private static let bodyToken = "__MARKDOWN_VIEWER_BODY__"
    private static let styleToken = "__MARKDOWN_VIEWER_STYLE_BLOCKS__"
    private static let scriptToken = "__MARKDOWN_VIEWER_SCRIPT_BLOCKS__"

    private let template: String
    private let styleBlocks: String
    private let scriptBlocks: String

    private init() {
        if let url = Bundle.module.url(forResource: "markdown", withExtension: "html"),
           let data = try? Data(contentsOf: url),
           let string = String(data: data, encoding: .utf8) {
            template = string
        } else {
            template = Self.fallbackTemplate
        }
        styleBlocks = Self.buildStyleBlocks()
        scriptBlocks = Self.buildScriptBlocks()
    }

    func render(body: String, title: String) -> String {
        template
            .replacingOccurrences(of: Self.titleToken, with: title)
            .replacingOccurrences(of: Self.bodyToken, with: body)
            .replacingOccurrences(of: Self.styleToken, with: styleBlocks)
            .replacingOccurrences(of: Self.scriptToken, with: scriptBlocks)
    }

    // Use external file references instead of inlining JS/CSS content.
    // highlight.min.js (119KB) + dagre.min.js (95KB) + beautiful-mermaid.js (185KB)
    // would otherwise be duplicated in every tab's htmlContent string.
    // The baseURL in WebView is set to Bundle.module.resourceURL so relative paths resolve correctly.
    private static func buildStyleBlocks() -> String {
        return """
        <link rel="stylesheet" media="(prefers-color-scheme: light)" href="github.min.css">
        <link rel="stylesheet" media="(prefers-color-scheme: dark)" href="github-dark.min.css">
        <link rel="stylesheet" href="markdown.css">
        """
    }

    private static func buildScriptBlocks() -> String {
        return """
        <script src="highlight.min.js"></script>
        <script src="find.js"></script>
        <script src="dagre.min.js"></script>
        <script src="beautiful-mermaid.js"></script>
        <script src="beautiful-mermaid-init.js"></script>
        <script src="toc.js"></script>
        <script src="copy-code.js"></script>
        """
    }

    private static let fallbackTemplate = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset=\"UTF-8\">
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
        <title>\(titleToken)</title>
        \(styleToken)
    </head>
    <body>
        \(bodyToken)
        \(scriptToken)
    </body>
    </html>
    """
}
