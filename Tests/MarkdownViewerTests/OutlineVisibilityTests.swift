import XCTest
@testable import MarkdownViewer

/// Tests for the outline sidebar visibility logic from ContentView.
///
/// ContentView has three computed properties that control when the outline sidebar
/// is visible and in what mode (pinned vs. floating). Since ContentView depends on
/// SwiftUI framework bindings and cannot be render-tested in a unit test environment,
/// we use behavioral extraction to test the decision logic directly.
///
/// The three properties being tested:
/// - canShowOutline: true when htmlContent is non-empty
/// - showPinnedOutline: canShowOutline AND isOutlinePinned
/// - showFloatingOutline: canShowOutline AND NOT isOutlinePinned AND (isHoveringEdge OR isHoveringSidebar)
final class OutlineVisibilityTests: XCTestCase {

    // MARK: - Extracted logic mirroring ContentView computed properties

    /// Mirrors ContentView.canShowOutline (line 17-19)
    private func canShowOutline(htmlContent: String) -> Bool {
        !htmlContent.isEmpty
    }

    /// Mirrors ContentView.showPinnedOutline (line 21-23)
    private func showPinnedOutline(htmlContent: String, isOutlinePinned: Bool) -> Bool {
        canShowOutline(htmlContent: htmlContent) && isOutlinePinned
    }

    /// Mirrors ContentView.showFloatingOutline (line 25-27)
    private func showFloatingOutline(
        htmlContent: String,
        isOutlinePinned: Bool,
        isHoveringEdge: Bool,
        isHoveringSidebar: Bool
    ) -> Bool {
        canShowOutline(htmlContent: htmlContent) && !isOutlinePinned && (isHoveringEdge || isHoveringSidebar)
    }

    // MARK: - canShowOutline tests

    func testCanShowOutlineIsFalseWithEmptyContent() {
        XCTAssertFalse(canShowOutline(htmlContent: ""))
    }

    func testCanShowOutlineIsTrueWithContent() {
        XCTAssertTrue(canShowOutline(htmlContent: "<p>Hello</p>"))
    }

    // MARK: - showPinnedOutline tests

    func testPinnedOutlineVisibleWhenContentAndPinned() {
        XCTAssertTrue(showPinnedOutline(htmlContent: "<p>Content</p>", isOutlinePinned: true))
    }

    func testPinnedOutlineHiddenWhenNoContent() {
        XCTAssertFalse(showPinnedOutline(htmlContent: "", isOutlinePinned: true))
    }

    func testPinnedOutlineHiddenWhenNotPinned() {
        XCTAssertFalse(showPinnedOutline(htmlContent: "<p>Content</p>", isOutlinePinned: false))
    }

    // MARK: - showFloatingOutline tests

    func testFloatingOutlineVisibleWhenHoveringEdge() {
        XCTAssertTrue(showFloatingOutline(
            htmlContent: "<p>Content</p>",
            isOutlinePinned: false,
            isHoveringEdge: true,
            isHoveringSidebar: false
        ))
    }

    func testFloatingOutlineVisibleWhenHoveringSidebar() {
        XCTAssertTrue(showFloatingOutline(
            htmlContent: "<p>Content</p>",
            isOutlinePinned: false,
            isHoveringEdge: false,
            isHoveringSidebar: true
        ))
    }

    func testFloatingOutlineVisibleWhenHoveringBoth() {
        XCTAssertTrue(showFloatingOutline(
            htmlContent: "<p>Content</p>",
            isOutlinePinned: false,
            isHoveringEdge: true,
            isHoveringSidebar: true
        ))
    }

    func testFloatingOutlineHiddenWhenNotHovering() {
        XCTAssertFalse(showFloatingOutline(
            htmlContent: "<p>Content</p>",
            isOutlinePinned: false,
            isHoveringEdge: false,
            isHoveringSidebar: false
        ))
    }

    func testFloatingOutlineHiddenWhenPinned() {
        // Even if hovering, floating should not show when pinned
        XCTAssertFalse(showFloatingOutline(
            htmlContent: "<p>Content</p>",
            isOutlinePinned: true,
            isHoveringEdge: true,
            isHoveringSidebar: true
        ))
    }

    func testFloatingOutlineHiddenWhenNoContent() {
        XCTAssertFalse(showFloatingOutline(
            htmlContent: "",
            isOutlinePinned: false,
            isHoveringEdge: true,
            isHoveringSidebar: true
        ))
    }

    // MARK: - Pinned and floating are mutually exclusive

    func testPinnedAndFloatingAreMutuallyExclusive() {
        let content = "<p>Content</p>"

        // When pinned, pinned should show but floating should not
        let pinned = showPinnedOutline(htmlContent: content, isOutlinePinned: true)
        let floating = showFloatingOutline(
            htmlContent: content, isOutlinePinned: true,
            isHoveringEdge: true, isHoveringSidebar: true
        )
        XCTAssertTrue(pinned)
        XCTAssertFalse(floating)

        // When not pinned but hovering, floating should show but pinned should not
        let pinned2 = showPinnedOutline(htmlContent: content, isOutlinePinned: false)
        let floating2 = showFloatingOutline(
            htmlContent: content, isOutlinePinned: false,
            isHoveringEdge: true, isHoveringSidebar: false
        )
        XCTAssertFalse(pinned2)
        XCTAssertTrue(floating2)
    }
}
