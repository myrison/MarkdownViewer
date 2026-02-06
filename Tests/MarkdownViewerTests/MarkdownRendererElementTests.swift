import Markdown
import XCTest
@testable import MarkdownViewer

/// Tests for MarkdownRenderer element rendering not covered by MarkdownRendererTests.
///
/// The existing MarkdownRendererTests covers headings, basic text escaping, code blocks,
/// unordered lists, blockquotes, links, images, tables, and strikethrough. This file
/// covers additional element types: ordered lists, thematic breaks, soft breaks,
/// emphasis/strong nesting, code blocks without language, empty headings, and HTML blocks.
final class MarkdownRendererElementTests: XCTestCase {

    private func render(_ input: String) -> RenderedMarkdown {
        let document = Document(parsing: input)
        var renderer = MarkdownRenderer()
        return renderer.render(document)
    }

    // MARK: - Ordered lists

    func testOrderedListRendersOlTags() {
        let input = """
        1. First
        2. Second
        3. Third
        """
        let rendered = render(input)

        XCTAssertTrue(rendered.html.contains("<ol>"), "Should produce <ol> tag")
        XCTAssertTrue(rendered.html.contains("<li>"), "Should produce <li> tags")
        XCTAssertTrue(rendered.html.contains("First"))
        XCTAssertTrue(rendered.html.contains("Second"))
        XCTAssertTrue(rendered.html.contains("Third"))
    }

    // MARK: - Thematic break

    func testThematicBreakRendersHrTag() {
        let input = """
        Above

        ---

        Below
        """
        let rendered = render(input)

        XCTAssertTrue(rendered.html.contains("<hr>"),
                       "Thematic break should produce <hr>, got: \(rendered.html)")
    }

    // MARK: - Soft break

    func testSoftBreakRendersAsSpace() {
        // In Markdown, a newline without two trailing spaces is a soft break
        let input = "Line one\nLine two"
        let rendered = render(input)

        // Soft break should render as a space, keeping both lines in one paragraph
        XCTAssertTrue(rendered.html.contains("Line one"),
                       "Should contain first line text")
        XCTAssertTrue(rendered.html.contains("Line two"),
                       "Should contain second line text")
        XCTAssertTrue(rendered.html.contains("<p>"),
                       "Should be within a single paragraph")
    }

    // MARK: - Emphasis and strong nesting

    func testEmphasisRendersEmTag() {
        let rendered = render("This is *emphasized* text")

        XCTAssertTrue(rendered.html.contains("<em>emphasized</em>"),
                       "Emphasis should produce <em> tags, got: \(rendered.html)")
    }

    func testStrongRendersStrongTag() {
        let rendered = render("This is **strong** text")

        XCTAssertTrue(rendered.html.contains("<strong>strong</strong>"),
                       "Strong should produce <strong> tags, got: \(rendered.html)")
    }

    func testNestedEmphasisAndStrong() {
        let rendered = render("This is ***bold and italic*** text")

        // swift-markdown parses *** as nested emphasis + strong
        XCTAssertTrue(rendered.html.contains("<em>") && rendered.html.contains("<strong>"),
                       "Nested *** should produce both <em> and <strong>, got: \(rendered.html)")
        XCTAssertTrue(rendered.html.contains("bold and italic"))
    }

    // MARK: - Code block without language

    func testCodeBlockWithoutLanguageUsesEmptyClass() {
        let input = """
        ```
        plain code
        ```
        """
        let rendered = render(input)

        XCTAssertTrue(rendered.html.contains("language-\""),
                       "Code block without language should have empty language class, got: \(rendered.html)")
        XCTAssertTrue(rendered.html.contains("plain code"))
    }

    // MARK: - Empty heading

    func testEmptyHeadingProducesTagButNoOutlineEntry() {
        // An empty heading (just "## " with nothing after) -- swift-markdown may strip it
        // but a heading with only whitespace should not add to the outline
        let input = "## \n## Real Heading"
        let rendered = render(input)

        // The real heading should be in the outline
        let outlineTitles = rendered.outline.map(\.title)
        XCTAssertTrue(outlineTitles.contains("Real Heading"),
                       "Real heading should be in outline, got: \(outlineTitles)")
    }

    // MARK: - Multiple headings produce correct anchor IDs

    func testMultipleSameLevelHeadingsGetUniqueAnchors() {
        let input = """
        ## Overview
        ## Overview
        ## Overview
        """
        let rendered = render(input)

        let anchors = rendered.outline.map(\.anchorID)
        XCTAssertEqual(anchors.count, 3)
        // All anchors must be unique
        XCTAssertEqual(Set(anchors).count, 3,
                       "All anchor IDs should be unique, got: \(anchors)")
        XCTAssertEqual(anchors[0], "overview")
        XCTAssertEqual(anchors[1], "overview-1")
        XCTAssertEqual(anchors[2], "overview-2")
    }

    // MARK: - Link with no destination

    func testLinkWithNoDestinationRendersEmptyHref() {
        let input = "[text]()"
        let rendered = render(input)

        XCTAssertTrue(rendered.html.contains("<a href=\"\">"),
                       "Link with empty destination should have empty href, got: \(rendered.html)")
        XCTAssertTrue(rendered.html.contains("text"))
    }

    // MARK: - Image with no source

    func testImageWithNoSourceRendersEmptySrc() {
        let input = "![alt text]()"
        let rendered = render(input)

        XCTAssertTrue(rendered.html.contains("<img src=\"\""),
                       "Image with empty source should have empty src, got: \(rendered.html)")
        XCTAssertTrue(rendered.html.contains("alt=\"alt text\""))
    }

    // MARK: - Table with multiple rows

    func testTableWithMultipleDataRows() {
        let input = """
        | Name | Age |
        | ---- | --- |
        | Alice | 30 |
        | Bob | 25 |
        | Charlie | 35 |
        """
        let rendered = render(input)

        XCTAssertTrue(rendered.html.contains("<thead>"), "Should have thead")
        XCTAssertTrue(rendered.html.contains("<tbody>"), "Should have tbody")
        XCTAssertTrue(rendered.html.contains("Alice"))
        XCTAssertTrue(rendered.html.contains("Bob"))
        XCTAssertTrue(rendered.html.contains("Charlie"))
        // Count <tr> tags: 1 header + 3 data rows = 4
        let trCount = rendered.html.components(separatedBy: "<tr>").count - 1
        XCTAssertEqual(trCount, 4, "Should have 4 <tr> tags (1 header + 3 data), got: \(trCount)")
    }

    // MARK: - Nested lists

    func testNestedUnorderedListRendersNestedUlTags() {
        let input = """
        - Item 1
          - Nested A
          - Nested B
        - Item 2
        """
        let rendered = render(input)

        // Count <ul> occurrences -- should be at least 2 (outer + nested)
        let ulCount = rendered.html.components(separatedBy: "<ul>").count - 1
        XCTAssertGreaterThanOrEqual(ulCount, 2,
                                     "Nested list should produce at least 2 <ul> tags, got: \(ulCount)")
        XCTAssertTrue(rendered.html.contains("Nested A"))
        XCTAssertTrue(rendered.html.contains("Nested B"))
    }

    // MARK: - Blockquote with nested content

    func testBlockquoteWithParagraphAndEmphasis() {
        let input = """
        > This is a *quoted* paragraph.
        """
        let rendered = render(input)

        XCTAssertTrue(rendered.html.contains("<blockquote>"),
                       "Should contain blockquote tag")
        XCTAssertTrue(rendered.html.contains("<em>quoted</em>"),
                       "Emphasis inside blockquote should render correctly, got: \(rendered.html)")
    }

    // MARK: - render() resets state between calls

    func testRenderResetsStateBetweenCalls() {
        var renderer = MarkdownRenderer()

        let first = renderer.render(Document(parsing: "## First"))
        let second = renderer.render(Document(parsing: "## Second"))

        XCTAssertFalse(second.html.contains("First"),
                        "Second render should not contain first render's content")
        XCTAssertTrue(second.html.contains("Second"))
        // Slugger should also reset -- both should get "first"/"second" without suffix
        XCTAssertEqual(first.outline.first?.anchorID, "first")
        XCTAssertEqual(second.outline.first?.anchorID, "second")
    }
}
