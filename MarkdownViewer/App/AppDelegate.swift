import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowControllers: [ViewerWindowController] = []
    private let openFilesStore = OpenFilesStore.shared
    private var windowCloseObserver: Any?
    private var keyDownMonitor: Any?
    private var rightClickMonitor: Any?
    private var editorMenuItem: NSMenuItem?
    private var settingsCancellable: AnyCancellable?
    private var didRestoreOpenFiles = false
    private var isTerminating = false

    func application(_ application: NSApplication, open urls: [URL]) {
        let valid = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        for url in valid {
            openFile(at: url)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApplication.shared.activate(ignoringOtherApps: true)
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            self?.handleWindowWillClose(window)
        }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // External editor shortcut (configurable, only when a document window is active)
            if self.eventMatchesEditorShortcut(flags: flags, event: event) {
                guard self.activeDocumentWindow() != nil else { return event }
                self.openInExternalEditor()
                return nil
            }

            // Ctrl+Tab / Ctrl+Shift+Tab for tab switching
            guard flags.contains(.control) else { return event }
            guard !flags.contains(.command), !flags.contains(.option) else { return event }
            guard event.keyCode == 48 else { return event }
            guard self.activeDocumentWindow() != nil else { return event }
            if flags.contains(.shift) {
                self.selectPreviousTab()
            } else {
                self.selectNextTab()
            }
            return nil
        }
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }
            return self.handleTabBarRightClick(event)
        }
        DispatchQueue.main.async { [weak self] in
            self?.restoreOpenFilesIfNeeded()
        }
        // After SwiftUI builds the menu, find the editor menu item and set its keyEquivalent for display
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.syncEditorMenuItemShortcut()
        }
        settingsCancellable = ExternalEditorSettings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.syncEditorMenuItemShortcut()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openEmptyTab()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminating = true
        persistOpenFilesFromWindows()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !isTerminating {
            persistOpenFilesFromWindows()
        }
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
        }
        settingsCancellable?.cancel()
    }

    func openFileFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md")!,
            UTType(filenameExtension: "markdown")!
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            openFile(at: url)
        }
    }

    func openFile(at url: URL) {
        if let documentState = reusableEmptyDocumentState() {
            documentState.loadFile(at: url)
            focusWindow(for: documentState)
            return
        }

        openInNewTab(url: url)
    }

    func openEmptyTab() {
        openInNewTab(url: nil)
    }

    func reloadActiveDocument() {
        activeDocumentState()?.reload()
    }

    func zoomIn() {
        activeDocumentState()?.zoomIn()
    }

    func zoomOut() {
        activeDocumentState()?.zoomOut()
    }

    func resetZoom() {
        activeDocumentState()?.resetZoom()
    }

    func showFindBar() {
        activeDocumentState()?.showFindBar()
    }

    func findNext() {
        activeDocumentState()?.findNext()
    }

    func findPrevious() {
        activeDocumentState()?.findPrevious()
    }

    func openInExternalEditor() {
        guard let url = activeDocumentState()?.currentURL else {
            NSSound.beep()
            return
        }
        let settings = ExternalEditorSettings.shared
        if let editorURL = settings.editorAppURL {
            if FileManager.default.fileExists(atPath: editorURL.path) {
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: editorURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
            } else {
                let alert = NSAlert()
                alert.messageText = "Editor Not Found"
                alert.informativeText = "\(settings.editorDisplayName) could not be found at \(editorURL.path)."
                alert.addButton(withTitle: "Choose Editor\u{2026}")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .warning
                if alert.runModal() == .alertFirstButtonReturn {
                    promptForEditor(thenOpen: url)
                }
            }
        } else {
            promptForEditor(thenOpen: url)
        }
    }

    func eventMatchesEditorShortcut(flags: NSEvent.ModifierFlags, event: NSEvent) -> Bool {
        let settings = ExternalEditorSettings.shared
        guard !settings.shortcutKey.isEmpty else { return false }
        let editorMods = NSEvent.ModifierFlags(rawValue: settings.shortcutModifiers)
            .intersection(.deviceIndependentFlagsMask)
        guard flags == editorMods else { return false }
        guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return false }
        return chars == settings.shortcutKey
    }

    private func syncEditorMenuItemShortcut() {
        let settings = ExternalEditorSettings.shared
        if editorMenuItem == nil || editorMenuItem?.menu == nil {
            editorMenuItem = findMenuItem(withTitlePrefix: "Open in ")
        }
        guard let item = editorMenuItem else { return }
        if settings.shortcutKey.isEmpty {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
        } else {
            item.keyEquivalent = settings.shortcutKey
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: settings.shortcutModifiers)
        }
    }

    private func findMenuItem(withTitlePrefix prefix: String) -> NSMenuItem? {
        guard let mainMenu = NSApp.mainMenu else { return nil }
        for menuBarItem in mainMenu.items {
            guard let submenu = menuBarItem.submenu else { continue }
            for item in submenu.items {
                if item.title.hasPrefix(prefix) { return item }
            }
        }
        return nil
    }

    private func promptForEditor(thenOpen fileURL: URL) {
        guard let editorURL = ExternalEditorSettings.presentEditorChooserPanel(
            message: "Choose an editor application for Markdown files"
        ) else { return }
        ExternalEditorSettings.shared.setEditor(url: editorURL)
        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: editorURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    // MARK: - Tab context menu

    private func handleTabBarRightClick(_ event: NSEvent) -> NSEvent? {
        guard let window = event.window, window.documentState != nil else { return event }

        let locationInWindow = event.locationInWindow
        let contentRect = window.contentLayoutRect

        // Only handle clicks above the content area (title bar / tab bar)
        guard locationInWindow.y > contentRect.maxY else { return event }

        let tabs = window.tabbedWindows ?? [window]

        let targetWindow: NSWindow
        if tabs.count > 1 {
            // Estimate which tab was clicked based on horizontal position.
            // The traffic-light buttons occupy ~80px on the left; the
            // "new tab" button takes ~40px on the right.
            let tabBarLeft: CGFloat = 80
            let tabBarRight = window.frame.width - 40
            let tabBarWidth = max(tabBarRight - tabBarLeft, 1)
            let tabWidth = tabBarWidth / CGFloat(tabs.count)
            let relativeX = locationInWindow.x - tabBarLeft
            let tabIndex = max(0, min(Int(relativeX / tabWidth), tabs.count - 1))
            targetWindow = tabs[tabIndex]
        } else {
            targetWindow = window
        }

        showTabContextMenu(for: targetWindow, in: tabs, with: event)
        return nil
    }

    private func showTabContextMenu(for targetWindow: NSWindow, in tabs: [NSWindow], with event: NSEvent) {
        guard let tabIndex = tabs.firstIndex(of: targetWindow) else { return }

        let menu = NSMenu()

        let closeItem = NSMenuItem(title: "Close Tab", action: #selector(contextCloseTab(_:)), keyEquivalent: "")
        closeItem.target = self
        closeItem.representedObject = targetWindow
        menu.addItem(closeItem)

        menu.addItem(.separator())

        let closeOthers = NSMenuItem(title: "Close Other Tabs", action: #selector(contextCloseOtherTabs(_:)), keyEquivalent: "")
        closeOthers.target = self
        closeOthers.representedObject = targetWindow
        closeOthers.isEnabled = tabs.count > 1
        menu.addItem(closeOthers)

        let closeRight = NSMenuItem(title: "Close Tabs to the Right", action: #selector(contextCloseTabsToRight(_:)), keyEquivalent: "")
        closeRight.target = self
        closeRight.representedObject = targetWindow
        closeRight.isEnabled = tabIndex < tabs.count - 1
        menu.addItem(closeRight)

        let closeLeft = NSMenuItem(title: "Close Tabs to the Left", action: #selector(contextCloseTabsToLeft(_:)), keyEquivalent: "")
        closeLeft.target = self
        closeLeft.representedObject = targetWindow
        closeLeft.isEnabled = tabIndex > 0
        menu.addItem(closeLeft)

        let hasFile = targetWindow.documentState?.currentURL != nil

        menu.addItem(.separator())

        let copyPath = NSMenuItem(title: "Copy File Path", action: #selector(contextCopyFilePath(_:)), keyEquivalent: "")
        copyPath.target = self
        copyPath.representedObject = targetWindow
        copyPath.isEnabled = hasFile
        menu.addItem(copyPath)

        let openInFinder = NSMenuItem(title: "Open in Finder", action: #selector(contextOpenInFinder(_:)), keyEquivalent: "")
        openInFinder.target = self
        openInFinder.representedObject = targetWindow
        openInFinder.isEnabled = hasFile
        menu.addItem(openInFinder)

        guard let contentView = event.window?.contentView else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
    }

    @objc private func contextCloseTab(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? NSWindow else { return }
        window.close()
    }

    @objc private func contextCloseOtherTabs(_ sender: NSMenuItem) {
        guard let targetWindow = sender.representedObject as? NSWindow else { return }
        let tabs = targetWindow.tabbedWindows ?? [targetWindow]
        for tab in tabs where tab !== targetWindow {
            tab.close()
        }
    }

    @objc private func contextCloseTabsToRight(_ sender: NSMenuItem) {
        guard let targetWindow = sender.representedObject as? NSWindow else { return }
        let tabs = targetWindow.tabbedWindows ?? [targetWindow]
        guard let index = tabs.firstIndex(of: targetWindow) else { return }
        for tab in tabs[(index + 1)...] {
            tab.close()
        }
    }

    @objc private func contextCloseTabsToLeft(_ sender: NSMenuItem) {
        guard let targetWindow = sender.representedObject as? NSWindow else { return }
        let tabs = targetWindow.tabbedWindows ?? [targetWindow]
        guard let index = tabs.firstIndex(of: targetWindow) else { return }
        for tab in tabs[..<index] {
            tab.close()
        }
    }

    @objc private func contextCopyFilePath(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? NSWindow,
              let url = window.documentState?.currentURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    @objc private func contextOpenInFinder(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? NSWindow,
              let url = window.documentState?.currentURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func selectNextTab() {
        activeDocumentWindow()?.selectNextTab(nil)
    }

    func selectPreviousTab() {
        activeDocumentWindow()?.selectPreviousTab(nil)
    }

    func selectTab(at index: Int) {
        guard let window = activeDocumentWindow() else { return }
        let tabs = tabGroupWindows(for: window)
        guard tabs.indices.contains(index) else { return }
        tabs[index].makeKeyAndOrderFront(nil)
    }

    private func activeDocumentState() -> DocumentState? {
        if let state = NSApplication.shared.keyWindow?.documentState {
            return state
        }
        if let state = NSApplication.shared.mainWindow?.documentState {
            return state
        }
        return NSApplication.shared.windows.compactMap(\.documentState).first
    }

    private func activeDocumentWindow() -> NSWindow? {
        if let window = NSApplication.shared.keyWindow, window.documentState != nil {
            return window
        }
        if let window = NSApplication.shared.mainWindow, window.documentState != nil {
            return window
        }
        return NSApplication.shared.windows.first { $0.documentState != nil }
    }

    private func reusableEmptyDocumentState() -> DocumentState? {
        if let active = activeDocumentState(), active.currentURL == nil {
            return active
        }
        return NSApplication.shared.windows
            .compactMap(\.documentState)
            .first { $0.currentURL == nil }
    }

    private func focusWindow(for documentState: DocumentState) {
        if let window = NSApplication.shared.windows.first(where: { $0.documentState === documentState }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func tabGroupWindows(for window: NSWindow) -> [NSWindow] {
        let tabs = window.tabbedWindows ?? []
        return tabs.isEmpty ? [window] : tabs
    }

    private func restoreOpenFilesIfNeeded() {
        guard !didRestoreOpenFiles else { return }
        let urls = openFilesStore.openFiles
        guard !urls.isEmpty else { return }
        guard NSApplication.shared.windows.contains(where: { $0.documentState != nil }) else {
            DispatchQueue.main.async { [weak self] in
                self?.restoreOpenFilesIfNeeded()
            }
            return
        }
        didRestoreOpenFiles = true
        let existing = Set(currentOpenFileURLs().map { $0.path })
        for url in urls where !existing.contains(url.path) {
            openFile(at: url)
        }
    }

    private func handleWindowWillClose(_ window: NSWindow) {
        guard window.documentState != nil else { return }
        if isTerminating { return }
        let documentWindows = NSApplication.shared.windows.filter { $0.documentState != nil }
        if documentWindows.count == 1 && documentWindows.first === window {
            openFilesStore.set(currentOpenFileURLs())
            return
        }
        let remaining = documentWindows
            .filter { $0 !== window }
            .compactMap { $0.documentState?.currentURL }
        openFilesStore.set(remaining)
    }

    private func persistOpenFilesFromWindows() {
        openFilesStore.set(currentOpenFileURLs())
    }

    private func currentOpenFileURLs() -> [URL] {
        NSApplication.shared.windows.compactMap { $0.documentState?.currentURL }
    }

    private func openInNewTab(url: URL?) {
        let documentState = DocumentState()
        if let url {
            documentState.loadFile(at: url)
        }

        openWindow(with: documentState)
    }

    private func openWindow(with documentState: DocumentState) {
        let contentView = ContentView(documentState: documentState)
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 600, height: 400))
        window.tabbingMode = .preferred
        window.title = documentState.title
        window.documentState = documentState

        let windowController = ViewerWindowController(window: window)
        window.delegate = windowController
        windowController.onClose = { [weak self, weak windowController] in
            guard let windowController else { return }
            self?.windowControllers.removeAll { $0 === windowController }
        }
        if let tabGroupWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            tabGroupWindow.addTabbedWindow(window, ordered: .above)
        }
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        windowControllers.append(windowController)
    }
}

final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
