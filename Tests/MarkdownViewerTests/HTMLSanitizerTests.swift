import Markdown
import XCTest
@testable import MarkdownViewer

/// Tests for HTMLSanitizer and its integration with MarkdownRenderer.
///
/// Raw HTML in a Markdown source used to be emitted verbatim. A literal `<select>`
/// placeholder in prose then opened a real element and hid every following line of
/// the document, while unknown tags such as `<id>` silently vanished. The sanitizer
/// escapes tags outside the allow list so they render as the text the author wrote.
final class HTMLSanitizerTests: XCTestCase {

    private func render(_ input: String) -> String {
        let document = Document(parsing: input)
        var renderer = MarkdownRenderer()
        return renderer.render(document).html
    }

    // MARK: - Disallowed tags become literal text

    func testEscapesSelectPlaceholder() {
        let html = HTMLSanitizer.sanitize("<select>")
        XCTAssertEqual(html, "&lt;select&gt;")
    }

    func testEscapesUnknownPlaceholderTags() {
        XCTAssertEqual(HTMLSanitizer.sanitize("<id>"), "&lt;id&gt;")
        XCTAssertEqual(HTMLSanitizer.sanitize("<Department>"), "&lt;Department&gt;")
        XCTAssertEqual(HTMLSanitizer.sanitize("</scratchpad>"), "&lt;/scratchpad&gt;")
    }

    func testEscapesScriptAndStyleTags() {
        // Quotes need no escaping in text content, only the angle brackets do.
        XCTAssertEqual(HTMLSanitizer.sanitize("<script src=\"x.js\">"), "&lt;script src=\"x.js\"&gt;")
        XCTAssertEqual(HTMLSanitizer.sanitize("<style>"), "&lt;style&gt;")
        XCTAssertEqual(HTMLSanitizer.sanitize("<iframe src=\"http://a\">"), "&lt;iframe src=\"http://a\"&gt;")
    }

    func testEscapesUnterminatedTag() {
        XCTAssertEqual(HTMLSanitizer.sanitize("<select"), "&lt;select")
    }

    func testEscapesBareAngleBracket() {
        XCTAssertEqual(HTMLSanitizer.sanitize("a < b"), "a &lt; b")
    }

    // MARK: - Allowed tags pass through

    func testKeepsFormattingTags() {
        XCTAssertEqual(HTMLSanitizer.sanitize("<b>"), "<b>")
        XCTAssertEqual(HTMLSanitizer.sanitize("</b>"), "</b>")
        XCTAssertEqual(HTMLSanitizer.sanitize("<br>"), "<br>")
        XCTAssertEqual(HTMLSanitizer.sanitize("<br />"), "<br />")
    }

    func testKeepsAllowedAttributes() {
        XCTAssertEqual(
            HTMLSanitizer.sanitize("<a href=\"https://example.com\" title=\"Example\">"),
            "<a href=\"https://example.com\" title=\"Example\">"
        )
        XCTAssertEqual(
            HTMLSanitizer.sanitize("<img src=\"image.png\" alt=\"An image\">"),
            "<img src=\"image.png\" alt=\"An image\">"
        )
    }

    func testKeepsRelativeAndAnchorURLs() {
        XCTAssertEqual(HTMLSanitizer.sanitize("<a href=\"#section\">"), "<a href=\"#section\">")
        XCTAssertEqual(HTMLSanitizer.sanitize("<a href=\"./docs/page.md\">"), "<a href=\"./docs/page.md\">")
    }

    func testKeepsDataImageURI() {
        let uri = "data:image/png;base64,AAAA"
        XCTAssertEqual(HTMLSanitizer.sanitize("<img src=\"\(uri)\">"), "<img src=\"\(uri)\">")
    }

    func testKeepsTextBetweenTags() {
        XCTAssertEqual(HTMLSanitizer.sanitize("<b>bold</b>"), "<b>bold</b>")
    }

    // MARK: - Attribute filtering

    func testDropsEventHandlerAttributes() {
        XCTAssertEqual(HTMLSanitizer.sanitize("<div onclick=\"steal()\" class=\"note\">"),
                        "<div class=\"note\">")
    }

    func testDropsJavaScriptURLs() {
        XCTAssertEqual(HTMLSanitizer.sanitize("<a href=\"javascript:alert(1)\">"), "<a>")
    }

    func testDropsNonImageDataURI() {
        XCTAssertEqual(HTMLSanitizer.sanitize("<a href=\"data:text/html,<b>x\">"), "<a>")
    }

    func testEscapesQuotesInAttributeValues() {
        XCTAssertEqual(HTMLSanitizer.sanitize("<div title='say \"hi\"'>"),
                        "<div title=\"say &quot;hi&quot;\">")
    }

    // MARK: - Comments

    func testDropsComments() {
        XCTAssertEqual(HTMLSanitizer.sanitize("a<!-- hidden -->b"), "ab")
    }

    func testDropsUnterminatedComment() {
        XCTAssertEqual(HTMLSanitizer.sanitize("a<!-- never closed"), "a")
    }

    // MARK: - Renderer integration

    func testContentAfterSelectPlaceholderStillRenders() {
        let input = """
        - re-parent commits on a <select> change, T8 unreachable

        ### D25: later section
        Still visible.
        """
        let html = render(input)
        XCTAssertTrue(html.contains("&lt;select&gt;"),
                       "The <select> placeholder should render as text, got: \(html)")
        XCTAssertFalse(html.contains("<select>"),
                        "No real select element should reach the page, got: \(html)")
        XCTAssertTrue(html.contains("D25: later section"),
                       "Content after the placeholder must still render, got: \(html)")
        XCTAssertTrue(html.contains("Still visible."),
                       "Content after the placeholder must still render, got: \(html)")
    }

    func testHTMLBlockIsSanitized() {
        let html = render("<select>\n<option>one</option>\n</select>")
        XCTAssertFalse(html.contains("<select>"), "HTML blocks should be sanitized too, got: \(html)")
        XCTAssertTrue(html.contains("&lt;select&gt;"), "Expected escaped block, got: \(html)")
        XCTAssertTrue(html.contains("one"), "Block text content should survive, got: \(html)")
    }

    func testAllowedInlineHTMLStillWorks() {
        let html = render("This is <b>bold</b> and <br> a break.")
        XCTAssertTrue(html.contains("<b>bold</b>"), "Allowed inline HTML should pass through, got: \(html)")
        XCTAssertTrue(html.contains("<br>"), "Allowed void elements should pass through, got: \(html)")
    }

    func testDetailsBlockStillWorks() {
        let html = render("<details>\n<summary>More</summary>\n\nBody text\n\n</details>")
        XCTAssertTrue(html.contains("<details>"), "details should be allowed, got: \(html)")
        XCTAssertTrue(html.contains("<summary>"), "summary should be allowed, got: \(html)")
    }
}
