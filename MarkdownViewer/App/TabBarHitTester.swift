import AppKit

/// Maps a point in a window's tab bar to the tab under it by measuring
/// AppKit's private tab button views. On macOS 26 `NSTabBar` swallows hitTest.
/// Once tabs overflow, the buttons overlap and the selected one is stacked on
/// top, and neither subview order nor x order matches tab order. Tab order is
/// read from the tab bar's accessibility children, which VoiceOver relies on,
/// and overlaps are settled by drawing order.
enum TabBarHitTester {
    struct Layout: Equatable {
        struct Tab: Equatable {
            let frame: NSRect
            let stackingOrder: Int
        }

        let tabs: [Tab]

        func tabIndex(at point: NSPoint) -> Int? {
            tabs.indices
                .filter { !tabs[$0].frame.isEmpty && tabs[$0].frame.contains(point) }
                .max { tabs[$0].stackingOrder < tabs[$1].stackingOrder }
        }
    }

    private static let tabBarClassName = "NSTabBar"
    private static let tabButtonClassName = "NSTabButton"

    static func layout(in window: NSWindow) -> Layout? {
        guard let tabBar = tabBar(in: window) else { return nil }
        let orderedButtons = tabButtons(of: tabBar)
        let drawingOrder = views(named: tabButtonClassName, in: tabBar)
        guard !orderedButtons.isEmpty else { return nil }

        var tabs: [Layout.Tab] = []
        for button in orderedButtons {
            guard let stackingOrder = drawingOrder.firstIndex(of: button) else { return nil }
            tabs.append(Layout.Tab(frame: visibleFrame(of: button), stackingOrder: stackingOrder))
        }
        return Layout(tabs: tabs)
    }

    static func tabButtons(in window: NSWindow) -> [NSView] {
        tabBar(in: window).map(tabButtons(of:)) ?? []
    }

    private static func tabBar(in window: NSWindow) -> NSView? {
        guard let root = window.contentView?.superview else { return nil }
        return root.subviews
            .filter { $0 !== window.contentView }
            .lazy
            .compactMap { views(named: tabBarClassName, in: $0).first }
            .first
    }

    private static func tabButtons(of tabBar: NSView) -> [NSView] {
        (tabBar.accessibilityChildren() ?? [])
            .compactMap { $0 as? NSView }
            .filter { isView($0, named: tabButtonClassName) }
    }

    private static func visibleFrame(of view: NSView) -> NSRect {
        guard !view.isHiddenOrHasHiddenAncestor, view.alphaValue > 0 else { return .null }
        var visible = view.convert(view.bounds, to: nil)
        var ancestor = view.superview
        while let current = ancestor {
            visible = visible.intersection(current.convert(current.bounds, to: nil))
            ancestor = current.superview
        }
        return visible
    }

    private static func views(named className: String, in view: NSView) -> [NSView] {
        if isView(view, named: className) { return [view] }
        return view.subviews.flatMap { views(named: className, in: $0) }
    }

    private static func isView(_ view: NSView, named className: String) -> Bool {
        NSStringFromClass(type(of: view)) == className
    }
}
