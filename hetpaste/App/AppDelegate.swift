import AppKit
import SwiftUI
import Combine
@MainActor
private final class ClipboardStripPanel: NSPanel {
    var handleKeyEvent: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if handleKeyEvent?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = ClipboardHistoryViewModel()
    let stripController = QuickClipboardStripController()
    var statusItem: NSStatusItem?
    private var stripPanel: NSPanel?
    private var hudPanel: NSPanel?
    private var statusPopover: NSPopover?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var psychoCopyModeObserver: NSObjectProtocol?
    private var hudCancellables = Set<AnyCancellable>()
    private var visibleStripItems: [ClipboardItem] {
        var result = viewModel.items
        if let folderID = stripController.selectedFolderID {
            result = result.filter { $0.folderID == folderID }
        }
        if let type = stripController.selectedContentType {
            result = result.filter { $0.contentType == type }
        }
        return result
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "hetpaste")
            button.action = #selector(toggleClipboardStrip(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        psychoCopyModeObserver = NotificationCenter.default.addObserver(
            forName: PsychoCopyManager.modeChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusBarIcon()
            self?.toggleHUD()
        }
        NotificationCenter.default.addObserver(
            forName: PsychoCopyManager.queueChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusBarIcon()
        }
        NotificationCenter.default.addObserver(
            forName: PsychoCopyManager.secureInputBlockedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stripController.showToast("Secure field — press ⌘V manually", isError: false)
        }
    }
    @objc func toggleClipboardStrip(_ sender: AnyObject?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            closeClipboardStrip()
            showStatusPopover()
            return
        }
        if stripPanel?.isVisible == true {
            closeClipboardStrip()
        } else {
            showClipboardStrip()
        }
    }
    private func showStatusPopover() {
        guard let button = statusItem?.button else { return }
        if statusPopover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            let popoverView = MenuBarPopoverView(
                manager: viewModel.psychoCopyManager,
                onOpenSettings: { [weak self] in
                    self?.statusPopover?.performClose(nil)
                    self?.openMainApp()
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
            popover.contentViewController = NSHostingController(rootView: popoverView)
            self.statusPopover = popover
        }
        if let popover = statusPopover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    @objc private func openMainAppFromStatusMenu() {
        closeClipboardStrip()
        openMainApp()
    }
    private func showClipboardStrip() {
        let panel = stripPanel ?? makeClipboardStripPanel()
        stripPanel = panel
        stripController.syncFocus(itemCount: visibleStripItems.count)
        positionStripPanel(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(panel)
        if let stripPanel = panel as? ClipboardStripPanel {
            stripPanel.handleKeyEvent = { [weak self] event in
                self?.handleStripKeyEvent(event) ?? false
            }
        }
        installEventMonitors()
    }
    private func makeClipboardStripPanel() -> NSPanel {
        let panel = ClipboardStripPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentViewController = NSHostingController(
            rootView: QuickClipboardStripView(
                viewModel: viewModel,
                controller: stripController,
                onClose: { [weak self] in
                    self?.closeClipboardStrip()
                },
                onOpenFullApp: { [weak self] item in
                    self?.openFullApp(focusedOn: item)
                },
                onExpandFullApp: { [weak self] item in
                    self?.expandFullApp(item: item)
                }
            )
        )
        return panel
    }
    private func positionStripPanel(_ panel: NSPanel) {
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let width = max(visibleFrame.width - 24, 900)
        let isMultiCopy = viewModel.psychoCopyManager.isMultiCopyModeActive
        let height: CGFloat = isMultiCopy ? 436 : 380
        let x = visibleFrame.midX - (width / 2)
        let y = visibleFrame.minY
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
    }
    private func closeClipboardStrip() {
        stripController.hidePreview()
        stripPanel?.orderOut(nil)
        removeEventMonitors()
    }
    private func restoreItem(at index: Int, asPlainText: Bool = false, closesStrip: Bool) {
        guard visibleStripItems.indices.contains(index) else { return }
        let item = visibleStripItems[index]
        stripController.focusItem(at: index, itemCount: visibleStripItems.count)
        Task {
            let result = await viewModel.restoreToPasteboard(item, asPlainText: asPlainText)
            stripController.showToast(result.message, isError: !result.didCopy)
            if result.didCopy && closesStrip {
                try? await Task.sleep(nanoseconds: 220_000_000)
                await MainActor.run {
                    closeClipboardStrip()
                }
            }
        }
    }
    private func restoreFocusedItem() {
        restoreItem(at: stripController.focusedIndex, closesStrip: false)
    }
    private func previewFocusedItem() {
        guard visibleStripItems.indices.contains(stripController.focusedIndex) else { return }
        let item = visibleStripItems[stripController.focusedIndex]
        if let url = item.revealableFileURL {
            QuickLookPreviewer.shared.preview(url: url)
            return
        }
        switch item.contentType {
        case .image:
            if let data = item.localData {
                QuickLookPreviewer.shared.previewImage(data: data, fileName: item.fileName)
            }
        default:
            stripController.showPreview(item)
        }
    }
    private func deleteFocusedItem() {
        guard visibleStripItems.indices.contains(stripController.focusedIndex) else { return }
        let oldIndex = stripController.focusedIndex
        let item = visibleStripItems[stripController.focusedIndex]
        viewModel.deleteItem(item)
        stripController.focusItem(at: min(oldIndex, max(visibleStripItems.count - 1, 0)), itemCount: visibleStripItems.count)
        stripController.showToast("Deleted", isError: false)
    }
    private func toggleFavoriteFocusedItem() {
        guard visibleStripItems.indices.contains(stripController.focusedIndex) else { return }
        let item = visibleStripItems[stripController.focusedIndex]
        viewModel.toggleFavorite(item)
    }
    private func openFullApp(focusedOn item: ClipboardItem) {
        closeClipboardStrip()
        viewModel.focusInFullApp(item)
        openMainApp()
    }
    private func expandFullApp(item: ClipboardItem) {
        closeClipboardStrip()
        viewModel.expandInFullApp(item)
        openMainApp()
    }
    func openMainApp() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window !== stripPanel {
            guard !(window is NSPanel) else { continue }
            window.makeKeyAndOrderFront(nil)
            break
        }
    }
    private func installEventMonitors() {
        removeEventMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.stripPanel, event.type == .leftMouseDown || event.type == .rightMouseDown {
                self.closeClipboardStrip()
            }
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closeClipboardStrip()
            }
        }
    }
    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }
    func applicationDidResignActive(_ notification: Notification) {
        closeClipboardStrip()
    }
    func applicationWillTerminate(_ notification: Notification) {
        removeEventMonitors()
        if let psychoCopyModeObserver {
            NotificationCenter.default.removeObserver(psychoCopyModeObserver)
        }
    }
    private func updateStatusBarIcon() {
        let isActive = viewModel.psychoCopyManager.isMultiCopyModeActive
        let queueCount = viewModel.psychoCopyManager.copyQueue.count
        if let button = statusItem?.button {
            if isActive {
                let symbol = queueCount > 0
                    ? "square.3.layers.3d.down.forward.badge.plus"
                    : "square.3.layers.3d.down.forward"
                button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PsychoCopy Active")
                button.contentTintColor = NSColor(Theme.accent)
                button.title = queueCount > 0 ? " \(queueCount)" : ""
            } else {
                button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "hetpaste")
                button.contentTintColor = nil
                button.title = ""
            }
        }
    }
    private func toggleHUD() {
        let manager = viewModel.psychoCopyManager
        let isActive = manager.isMultiCopyModeActive
        if isActive {
            if hudPanel == nil {
                let hudView = PsychoCopyHUDView(manager: manager)
                let hostingView = NSHostingView(rootView: hudView)
                hostingView.wantsLayer = true
                hostingView.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
                let panel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.level = .floating
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.ignoresMouseEvents = false
                panel.contentView = hostingView
                self.hudPanel = panel
            }
            if let panel = hudPanel, panel.frame.origin == .zero {
                let screen = statusItem?.button?.window?.screen ?? NSScreen.main
                if let screenRect = screen?.visibleFrame {
                    let x = screenRect.midX - panel.frame.width / 2
                    let y = screenRect.minY + 8
                    panel.setFrameOrigin(NSPoint(x: x, y: y))
                }
            }
            hudPanel?.orderFrontRegardless()
        } else {
            hudPanel?.orderOut(nil)
            manager.isHUDExpanded = false
        }
    }
    private func handleStripKeyEvent(_ event: NSEvent) -> Bool {
        if let numberShortcut = numberShortcut(from: event) {
            stripController.hidePreview()
            restoreItem(
                at: numberShortcut.index,
                asPlainText: numberShortcut.asPlainText,
                closesStrip: false
            )
            return true
        }
        switch event.keyCode {
        case 53 where allowsPlainShortcut(event):
            stripController.hidePreview()
            closeClipboardStrip()
            return true
        case 123 where allowsPlainShortcut(event):
            stripController.hidePreview()
            stripController.moveLeft(itemCount: visibleStripItems.count)
            return true
        case 124 where allowsPlainShortcut(event):
            stripController.hidePreview()
            stripController.moveRight(itemCount: visibleStripItems.count)
            return true
        case 36 where allowsPlainShortcut(event), 76 where allowsPlainShortcut(event):
            stripController.hidePreview()
            restoreFocusedItem()
            return true
        case 49 where allowsPlainShortcut(event):
            previewFocusedItem()
            return true
        case 51 where allowsPlainShortcut(event), 117 where allowsPlainShortcut(event):
            stripController.hidePreview()
            deleteFocusedItem()
            return true
        case 3 where allowsPlainLetterShortcut(event):  
            stripController.hidePreview()
            toggleFavoriteFocusedItem()
            return true
        case 35 where allowsPlainLetterShortcut(event):  
            if viewModel.psychoCopyManager.isMultiCopyModeActive {
                stripController.hidePreview()
                Task {
                    let result = await viewModel.psychoCopyManager.performSequentialPaste(viewModel: viewModel)
                    stripController.showToast(result.message, isError: !result.didCopy)
                    if result.didCopy {
                        try? await Task.sleep(nanoseconds: 220_000_000)
                        await MainActor.run {
                            self.closeClipboardStrip()
                        }
                    } else {
                        if let panel = self.stripPanel {
                            self.positionStripPanel(panel)
                        }
                    }
                }
                return true
            }
            return false
        default:
            return false
        }
    }
    private func numberShortcut(from event: NSEvent) -> (index: Int, asPlainText: Bool)? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let forbidden: NSEvent.ModifierFlags = [.command, .control, .shift]
        guard flags.intersection(forbidden).isEmpty else { return nil }
        guard
            let shortcut = event.charactersIgnoringModifiers,
            shortcut.count == 1,
            let value = Int(shortcut),
            (1...9).contains(value)
        else {
            return nil
        }
        return (value - 1, flags.contains(.option))
    }
    private func allowsPlainLetterShortcut(_ event: NSEvent) -> Bool {
        allowsPlainShortcut(event)
    }
    private func allowsPlainShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let forbidden: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        return flags.intersection(forbidden).isEmpty
    }
}