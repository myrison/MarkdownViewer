import Markdown
import XCTest
@testable import MarkdownViewer

/// Tests for the HTML entity-aware escaping in MarkdownRenderer.
///
/// The renderer's escapeHTML method preserves valid HTML entities (named entities
/// like &amp;, &lt;, &quot;) while escaping bare `&`, `<`, `>`, and `"` characters.
/// This is security-relevant: bare special characters must be escaped to prevent
/// injection, but legitimate entities in the source text should pass through.
///
/// Note: The swift-markdown parser resolves numeric entities (&#38;, &#x26;) and
/// some named entities (&nbsp;) to their character equivalents before the renderer
/// sees them. These tests focus on what the renderer actually receives and processes.
final class MarkdownRendererHTMLEscapingTests: XCTestCase {

    // MARK: - Helpers

    /// Renders a plain text Markdown paragraph and returns the full HTML output.
    private func renderPlainText(_ input: String) -> String {
        let document = Document(parsing: input)
        var renderer = MarkdownRenderer()
        let rendered = renderer.render(document)
        return rendered.html
    }

    // MARK: - Named HTML entities are preserved by the renderer

    func testPreservesNamedEntityAmp() {
        let html = renderPlainText("Tom &amp; Jerry")
        XCTAssertTrue(html.contains("Tom &amp; Jerry"),
                       "Named entity &amp; should be preserved, got: \(html)")
    }

    func testPreservesNamedEntityLt() {
        let html = renderPlainText("a &lt; b")
        XCTAssertTrue(html.contains("a &lt; b"),
                       "Named entity &lt; should be preserved, got: \(html)")
    }

    func testPreservesNamedEntityQuot() {
        let html = renderPlainText("say &quot;hello&quot;")
        XCTAssertTrue(html.contains("say &quot;hello&quot;"),
                       "Named entity &quot; should be preserved, got: \(html)")
    }

    func testPreservesNamedEntityGt() {
        let html = renderPlainText("a &gt; b")
        XCTAssertTrue(html.contains("a &gt; b"),
                       "Named entity &gt; should be preserved, got: \(html)")
    }

    // MARK: - Bare special characters are escaped

    func testEscapesBareAmpersand() {
        let html = renderPlainText("Tom & Jerry")
        XCTAssertTrue(html.contains("Tom &amp; Jerry"),
                       "Bare & should be escaped to &amp;, got: \(html)")
    }

    func testEscapesBareAngleBrackets() {
        let html = renderPlainText("a < b > c")
        XCTAssertTrue(html.contains("&lt;"), "< should be escaped to &lt;, got: \(html)")
        XCTAssertTrue(html.contains("&gt;"), "> should be escaped to &gt;, got: \(html)")
    }

    // MARK: - Invalid entity patterns are escaped

    func testEscapesEmptyEntity() {
        // &; with nothing between & and ; is invalid
        let html = renderPlainText("a &; b")
        XCTAssertTrue(html.contains("&amp;;"),
                       "Empty entity &; should have its & escaped, got: \(html)")
    }

    func testEscapesAmpersandWithNoSemicolon() {
        let html = renderPlainText("AT&T is great")
        XCTAssertTrue(html.contains("AT&amp;T"),
                       "Ampersand without trailing ; should be escaped, got: \(html)")
    }

    // MARK: - Mixed content

    func testMixedEntitiesAndBareCharacters() {
        // The Markdown parser resolves &amp; -> & and &lt; -> <, so the renderer
        // receives four special characters that all need escaping. The output should
        // contain exactly four escaped entities in the paragraph.
        let html = renderPlainText("&amp; and & and &lt; and <")
        XCTAssertEqual(html, "<p>&amp; and &amp; and &lt; and &lt;</p>\n",
                        "All special characters should be escaped, got: \(html)")
    }

    // MARK: - Entity at boundaries

    func testEntityAtEndOfString() {
        let html = renderPlainText("end with &amp;")
        XCTAssertTrue(html.contains("end with &amp;"),
                       "Entity at end of string should be preserved, got: \(html)")
    }

    func testAmpersandAtEndOfString() {
        let html = renderPlainText("trailing &")
        XCTAssertTrue(html.contains("trailing &amp;"),
                       "Bare & at end should be escaped, got: \(html)")
    }

    // MARK: - Code blocks escape all entities (no entity preservation inside code)

    func testCodeBlockEscapesAngleBracketsAndPreservesEntities() {
        // In code blocks, the source text is literal: &amp; stays as &amp; (not resolved),
        // and <tag> stays as <tag>. The renderer's escapeHTML should preserve the valid
        // &amp; entity and escape the bare < and > in <tag>.
        let input = """
        ```
        &amp; and <tag>
        ```
        """
        let html = renderPlainText(input)
        XCTAssertTrue(html.contains("&amp;"),
                       "Code block should preserve &amp; entity, got: \(html)")
        XCTAssertTrue(html.contains("&lt;tag&gt;"),
                       "Code block should escape angle brackets in <tag>, got: \(html)")
        XCTAssertFalse(html.contains("<tag>"),
                        "Raw <tag> should not appear in output, got: \(html)")
    }

    func testInlineCodeEscapesAngleBrackets() {
        let html = renderPlainText("use `<div>` tag")
        XCTAssertTrue(html.contains("&lt;div&gt;"),
                       "Inline code should escape angle brackets, got: \(html)")
    }
}
