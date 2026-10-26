import AppKit
import XCTest
@testable import MarkdownViewer

final class TabBarHitTesterTests: XCTestCase {

    private final class PlusTabWindow: NSWindow {
        override func newWindowForTab(_ sender: Any?) {}
    }

    private typealias Layout = TabBarHitTester.Layout

    private let layoutTimeout: TimeInterval = 3

    // MARK: - Pure hit testing

    private let measuredLayout = Layout(tabs: [
        Layout.Tab(frame: NSRect(x: 10, y: 406, width: 169, height: 24), stackingOrder: 0),
        Layout.Tab(frame: NSRect(x: 180, y: 406, width: 169, height: 24), stackingOrder: 1),
        Layout.Tab(frame: NSRect(x: 350, y: 406, width: 154, height: 24), stackingOrder: 2),
        Layout.Tab(frame: NSRect(x: 505, y: 406, width: 153, height: 24), stackingOrder: 3)
    ])

    func testTabIndexFindsEachTabAtCenterAndBothEdges() {
        for (index, tab) in measuredLayout.tabs.enumerated() {
            let rect = tab.frame
            XCTAssertEqual(measuredLayout.tabIndex(at: NSPoint(x: rect.midX, y: rect.midY)), index)
            XCTAssertEqual(measuredLayout.tabIndex(at: NSPoint(x: rect.minX + 3, y: rect.midY)), index)
            XCTAssertEqual(measuredLayout.tabIndex(at: NSPoint(x: rect.maxX - 3, y: rect.midY)), index)
        }
    }

    func testTabIndexIsNilInGapsAndOutsideTheBar() {
        XCTAssertNil(measuredLayout.tabIndex(at: NSPoint(x: 179.5, y: 418)))
        XCTAssertNil(measuredLayout.tabIndex(at: NSPoint(x: 678, y: 418)))
        XCTAssertNil(measuredLayout.tabIndex(at: NSPoint(x: 100, y: 450)))
        XCTAssertNil(measuredLayout.tabIndex(at: NSPoint(x: 100, y: 200)))
    }

    func testTabIndexIgnoresEmptyFrames() {
        let layout = Layout(tabs: [
            Layout.Tab(frame: NSRect(x: 10, y: 406, width: 100, height: 24), stackingOrder: 0),
            Layout.Tab(frame: NSRect(x: 50, y: 406, width: 0, height: 24), stackingOrder: 1),
            Layout.Tab(frame: .null, stackingOrder: 2)
        ])
        XCTAssertEqual(layout.tabIndex(at: NSPoint(x: 50, y: 418)), 0)
        XCTAssertNil(layout.tabIndex(at: .zero))
    }

    func testTabIndexPrefersTheTabDrawnOnTop() {
        let layout = Layout(tabs: [
            Layout.Tab(frame: NSRect(x: 10, y: 406, width: 120, height: 24), stackingOrder: 5),
            Layout.Tab(frame: NSRect(x: 100, y: 406, width: 20, height: 24), stackingOrder: 1),
            Layout.Tab(frame: NSRect(x: 120, y: 406, width: 30, height: 24), stackingOrder: 2)
        ])
        XCTAssertEqual(layout.tabIndex(at: NSPoint(x: 110, y: 418)), 0)
        XCTAssertEqual(layout.tabIndex(at: NSPoint(x: 125, y: 418)), 0)
        XCTAssertEqual(layout.tabIndex(at: NSPoint(x: 140, y: 418)), 2)
    }

    // MARK: - Real tab bar

    func testLayoutMatchesTabGroupOrderIncludingAfterReorder() throws {
        let first = try makeTabGroup(titles: ["A", "Bxxx", "Cxxxxxx", "Dxxxxxxxxx"])
        let window = try XCTUnwrap(first.tabGroup?.selectedWindow)
        let tabs = try XCTUnwrap(window.tabGroup?.windows)
        let layout = try XCTUnwrap(TabBarHitTester.layout(in: window))
        XCTAssertEqual(layout.tabs.count, tabs.count)
        XCTAssertEqual(buttonTitles(in: window), tabs.map(\.title))

        for (index, tab) in layout.tabs.enumerated() {
            let rect = tab.frame
            XCTAssertEqual(layout.tabIndex(at: NSPoint(x: rect.midX, y: rect.midY)), index)
            XCTAssertEqual(layout.tabIndex(at: NSPoint(x: rect.minX + 3, y: rect.midY)), index)
            XCTAssertEqual(layout.tabIndex(at: NSPoint(x: rect.maxX - 3, y: rect.midY)), index)
        }
        assertLayoutAgreesWithAppKitHitTesting(in: window)

        let plusRect = try newTabButtonRect(in: window)
        XCTAssertNil(layout.tabIndex(at: NSPoint(x: plusRect.midX, y: plusRect.midY)))
        XCTAssertNil(layout.tabIndex(at: NSPoint(x: 350, y: window.frame.height - 10)))
        XCTAssertNil(layout.tabIndex(at: NSPoint(x: 350, y: 100)))

        let group = try XCTUnwrap(window.tabGroup)
        let moved = tabs[3]
        group.removeWindow(moved)
        group.insertWindow(moved, at: 0)
        let expectedTitles = [tabs[3], tabs[0], tabs[1], tabs[2]].map(\.title)
        pumpRunLoop { self.buttonTitles(in: group.selectedWindow) == expectedTitles }
        XCTAssertEqual(group.windows.map(\.title), expectedTitles)
        XCTAssertEqual(buttonTitles(in: group.selectedWindow), expectedTitles)

        let middle = group.windows[2]
        middle.makeKeyAndOrderFront(nil)
        pumpRunLoop { group.selectedWindow === middle && TabBarHitTester.layout(in: middle)?.tabs.count == 4 }
        XCTAssertTrue(group.selectedWindow === middle)
        XCTAssertEqual(buttonTitles(in: middle), expectedTitles)
        assertLayoutAgreesWithAppKitHitTesting(in: middle)
    }

    func testOverflowedTabsResolveCorrectlyWhenTheLastTabIsSelected() throws {
        let first = try makeTabGroup(titles: (0..<25).map { "Tab \($0)" })
        let window = try XCTUnwrap(first.tabGroup?.selectedWindow)
        XCTAssertTrue(window === window.tabGroup?.windows.last)
        try assertOverflowHitTesting(in: window)
    }

    func testOverflowedTabsResolveCorrectlyWhenTheFirstTabIsSelected() throws {
        let first = try makeTabGroup(titles: (0..<25).map { "Tab \($0)" })
        first.makeKeyAndOrderFront(nil)
        pumpRunLoop { first.tabGroup?.selectedWindow === first && TabBarHitTester.layout(in: first)?.tabs.count == 25 }
        XCTAssertTrue(first.tabGroup?.selectedWindow === first)
        try assertOverflowHitTesting(in: first)
    }

    func testSingleTabHasNoLayoutUntilTheTabBarIsShown() throws {
        let window = try makeTabGroup(titles: ["Only"])
        try hideTabBar(of: window)
        XCTAssertNil(TabBarHitTester.layout(in: window))

        window.toggleTabBar(nil)
        addTeardownBlock { window.toggleTabBar(nil) }
        pumpRunLoop { TabBarHitTester.layout(in: window)?.tabs.count == 1 }
        XCTAssertEqual(TabBarHitTester.layout(in: window)?.tabs.count, 1)
    }

    // MARK: - Event resolution

    func testRightClickEventResolvesToTheTabUnderThePointer() throws {
        let first = try makeTabGroup(titles: ["A", "Bxxx", "Cxxxxxx", "Dxxxxxxxxx"])
        let window = try XCTUnwrap(first.tabGroup?.selectedWindow)
        let tabs = try XCTUnwrap(window.tabGroup?.windows)
        let layout = try XCTUnwrap(TabBarHitTester.layout(in: window))
        let delegate = AppDelegate()

        for (index, tab) in layout.tabs.enumerated() {
            let event = try rightClick(at: NSPoint(x: tab.frame.minX + 3, y: tab.frame.midY), in: window)
            XCTAssertTrue(event.window === window)
            let target = try XCTUnwrap(delegate.tabTarget(for: event))
            XCTAssertTrue(target.window === tabs[index], "tab \(index) resolved to \(target.window.title)")
            XCTAssertEqual(target.tabs, tabs)
        }

        let plusRect = try newTabButtonRect(in: window)
        XCTAssertNil(delegate.tabTarget(for: try rightClick(at: NSPoint(x: plusRect.midX, y: plusRect.midY), in: window)))
        XCTAssertNil(delegate.tabTarget(for: try rightClick(at: NSPoint(x: 350, y: 100), in: window)))
    }

    func testRightClickOnSingleTabWithHiddenBarIsNotClaimed() throws {
        let window = try makeTabGroup(titles: ["Only"])
        try hideTabBar(of: window)

        let titleBarPoint = NSPoint(x: window.frame.width / 2, y: window.frame.height - 10)
        XCTAssertNil(AppDelegate().tabTarget(for: try rightClick(at: titleBarPoint, in: window)))
    }

    // MARK: - Assertions

    private func assertOverflowHitTesting(in window: NSWindow, file: StaticString = #filePath, line: UInt = #line) throws {
        let tabs = try XCTUnwrap(window.tabGroup?.windows)
        let layout = try XCTUnwrap(TabBarHitTester.layout(in: window))
        XCTAssertEqual(layout.tabs.count, 25, file: file, line: line)
        XCTAssertEqual(buttonTitles(in: window), tabs.map(\.title), file: file, line: line)

        let tabBar = try XCTUnwrap(views(named: "NSTabBar", in: window).first)
        let tabBarRect = tabBar.convert(tabBar.bounds, to: nil)
        let visibleCount = layout.tabs.filter { !$0.frame.isEmpty }.count
        XCTAssertGreaterThan(visibleCount, 0, file: file, line: line)
        for tab in layout.tabs where !tab.frame.isEmpty {
            XCTAssertTrue(tabBarRect.contains(tab.frame), "\(tab.frame) is outside the tab bar", file: file, line: line)
        }

        let selectedIndex = try XCTUnwrap(tabs.firstIndex(of: window))
        let selectedFrame = layout.tabs[selectedIndex].frame
        XCTAssertEqual(layout.tabIndex(at: NSPoint(x: selectedFrame.midX, y: selectedFrame.midY)), selectedIndex, file: file, line: line)

        let plusRect = try newTabButtonRect(in: window)
        XCTAssertNil(layout.tabIndex(at: NSPoint(x: plusRect.midX, y: plusRect.midY)), file: file, line: line)
        assertLayoutAgreesWithAppKitHitTesting(in: window, file: file, line: line)
    }

    /// Sweeps the tab row and compares every point against AppKit's own
    /// hitTest, run on the buttons' container because `NSTabBar` swallows it.
    private func assertLayoutAgreesWithAppKitHitTesting(in window: NSWindow, file: StaticString = #filePath, line: UInt = #line) {
        guard let layout = TabBarHitTester.layout(in: window),
              let rowY = layout.tabs.first(where: { !$0.frame.isEmpty })?.frame.midY else {
            return XCTFail("no tab layout", file: file, line: line)
        }
        let buttons = TabBarHitTester.tabButtons(in: window)
        var checkedHits = 0
        for x in stride(from: CGFloat(0.5), to: window.frame.width, by: 1) {
            let point = NSPoint(x: x, y: rowY)
            let expected = appKitHitButton(at: point, among: buttons).flatMap { buttons.firstIndex(of: $0) }
            XCTAssertEqual(layout.tabIndex(at: point), expected, "x = \(x)", file: file, line: line)
            if expected != nil { checkedHits += 1 }
        }
        XCTAssertGreaterThan(checkedHits, 100, file: file, line: line)
    }

    // MARK: - Helpers

    private func makeTabGroup(titles: [String]) throws -> NSWindow {
        guard NSScreen.main != nil else {
            throw XCTSkip("No screen available; the tab bar cannot be laid out")
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        NSWindow.allowsAutomaticWindowTabbing = true
        let identifier = NSWindow.TabbingIdentifier(UUID().uuidString)

        let windows = titles.map { title -> NSWindow in
            let window = PlusTabWindow(
                contentRect: NSRect(x: 100, y: 100, width: 700, height: 400),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.tabbingMode = .preferred
            window.tabbingIdentifier = identifier
            window.isReleasedWhenClosed = false
            return window
        }
        addTeardownBlock {
            windows.forEach { $0.close() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let first = windows[0]
        first.makeKeyAndOrderFront(nil)
        for (previous, window) in zip(windows, windows.dropFirst()) {
            previous.addTabbedWindow(window, ordered: .above)
        }
        windows.last?.makeKeyAndOrderFront(nil)

        if windows.count > 1 {
            pumpRunLoop {
                guard let selected = first.tabGroup?.selectedWindow,
                      let layout = TabBarHitTester.layout(in: selected) else { return false }
                return layout.tabs.count == windows.count
            }
        } else {
            pumpRunLoop { first.isVisible }
        }
        return first
    }

    private func hideTabBar(of window: NSWindow) throws {
        let group = try XCTUnwrap(window.tabGroup)
        if group.isTabBarVisible {
            window.toggleTabBar(nil)
            addTeardownBlock { window.toggleTabBar(nil) }
        }
        pumpRunLoop { TabBarHitTester.layout(in: window) == nil }
    }

    private func pumpRunLoop(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(layoutTimeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    private func buttonTitles(in window: NSWindow?) -> [String] {
        guard let window else { return [] }
        return TabBarHitTester.tabButtons(in: window).compactMap { $0.accessibilityTitle() }
    }

    private func appKitHitButton(at point: NSPoint, among buttons: [NSView]) -> NSView? {
        let containers = buttons.compactMap(\.superview).reduce(into: [NSView]()) { result, view in
            if !result.contains(view) { result.append(view) }
        }
        for container in containers.reversed() {
            guard let parent = container.superview else { continue }
            var hit = container.hitTest(parent.convert(point, from: nil))
            while let view = hit, !buttons.contains(view) {
                hit = view.superview
            }
            if let hit { return hit }
        }
        return nil
    }

    private func newTabButtonRect(in window: NSWindow) throws -> NSRect {
        let button = try XCTUnwrap(views(named: "NSTabBarNewTabButton", in: window).first)
        return button.convert(button.bounds, to: nil)
    }

    private func views(named className: String, in window: NSWindow) -> [NSView] {
        guard let root = window.contentView?.superview else { return [] }
        func walk(_ view: NSView) -> [NSView] {
            let match = NSStringFromClass(type(of: view)) == className ? [view] : []
            return match + view.subviews.flatMap(walk)
        }
        return walk(root)
    }

    private func rightClick(at point: NSPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}
