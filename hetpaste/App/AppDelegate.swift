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
    let wardrobeViewModel = WardrobeViewModel()
    var statusItem: NSStatusItem?
    private var stripPanel: NSPanel?
    private var hudPanel: NSPanel?
    private var statusPopover: NSPopover?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var psychoCopyModeObserver: NSObjectProtocol?
    private var hudCancellables = Set<AnyCancellable>()
    private var menuBarDropView: MenuBarDropView?
    private var dropPreviewPopover: NSPopover?
    private var dropPreviewController: MenuBarDropPreviewViewController?
    private var dropPreviewCloseWorkItem: DispatchWorkItem?
    private var dropPreviewSourceApp: NSRunningApplication?
    private var isProcessingMenuBarDrop = false
    private var originalButtonImage: NSImage?
    private var feedbackTimer: Timer?
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
            
            // Set up drop view for menu bar icon
            setupMenuBarDropTarget(button: button)
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
    
    private func setupMenuBarDropTarget(button: NSButton) {
        let dropView = MenuBarDropView(frame: button.bounds)
        dropView.delegate = self
        dropView.autoresizingMask = [.width, .height]
        button.addSubview(dropView)
        self.menuBarDropView = dropView
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
                wardrobeViewModel: wardrobeViewModel,
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

@MainActor
private final class MenuBarDropPreviewViewController: NSViewController {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "Drop to save to Wardrobe")
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    var onDrop: (([NSItemProvider]) -> Bool)?

    override func loadView() {
        let contentView = MenuBarDropPreviewContentView(frame: NSRect(x: 0, y: 0, width: 238, height: 76))
        contentView.onDragEntered = { [weak self] in self?.onDragEntered?() }
        contentView.onDragExited = { [weak self] in self?.onDragExited?() }
        contentView.onDrop = { [weak self] providers in self?.onDrop?(providers) ?? false }
        view = contentView

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail

        contentView.addSubview(iconView)
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 21),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 25),
            iconView.heightAnchor.constraint(equalToConstant: 25),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 11),
            label.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        showReady()
    }

    func showReady() {
        guard isViewLoaded else { return }
        iconView.image = NSImage(systemSymbolName: "hanger", accessibilityDescription: "Wardrobe drop target")
        iconView.contentTintColor = .systemPurple
        label.stringValue = "Drop to save to Wardrobe"
        (view as? MenuBarDropPreviewContentView)?.accentColor = .systemPurple
    }

    func showSuccess() {
        guard isViewLoaded else { return }
        iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Saved to Wardrobe")
        iconView.contentTintColor = .systemGreen
        label.stringValue = "Saved to Wardrobe"
        (view as? MenuBarDropPreviewContentView)?.accentColor = .systemGreen
    }
}

private final class MenuBarDropPreviewContentView: NSView {
    private let borderLayer = CAShapeLayer()
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    var onDrop: (([NSItemProvider]) -> Bool)?
    var accentColor: NSColor = .systemPurple {
        didSet {
            borderLayer.strokeColor = accentColor.withAlphaComponent(0.8).cgColor
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.cornerRadius = 11
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = accentColor.withAlphaComponent(0.8).cgColor
        borderLayer.lineWidth = 1.5
        borderLayer.lineDashPattern = [5, 4]
        layer?.addSublayer(borderLayer)
        registerForDraggedTypes(MenuBarDropView.acceptedDropTypes)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let borderBounds = bounds.insetBy(dx: 8, dy: 8)
        borderLayer.frame = bounds
        borderLayer.path = CGPath(roundedRect: borderBounds, cornerWidth: 8, cornerHeight: 8, transform: nil)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let providers = MenuBarDropView.itemProviders(from: sender.draggingPasteboard)
        guard !providers.isEmpty else { return false }
        return onDrop?(providers) ?? false
    }
}


// MARK: - MenuBarDropViewDelegate

extension AppDelegate: MenuBarDropViewDelegate {
    func menuBarDropView(_ view: MenuBarDropView, didReceiveDropWithProviders providers: [NSItemProvider], sourceApp: NSRunningApplication?) {
        processMenuBarDrop(providers: providers, sourceApp: sourceApp)
    }

    private func processMenuBarDrop(providers: [NSItemProvider], sourceApp: NSRunningApplication?) {
        dropPreviewCloseWorkItem?.cancel()
        isProcessingMenuBarDrop = true
        Task {
            // Filter out if source is our own app (edge case)
            let validSourceApp: NSRunningApplication?
            if let app = sourceApp, app.bundleIdentifier != Bundle.main.bundleIdentifier {
                validSourceApp = app
            } else {
                validSourceApp = nil
            }
            
            await wardrobeViewModel.addFromDrop(providers: providers, sourceApp: validSourceApp)
            // Success feedback
            await showSuccessFeedback()
        }
    }
    
    func menuBarDropViewDidBeginHover(_ view: MenuBarDropView) {
        guard let button = statusItem?.button else { return }
        
        // Save original image if not already saved
        if originalButtonImage == nil {
            originalButtonImage = button.image
        }
        
        // Change to highlighted state - purple tint to indicate wardrobe
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            button.contentTintColor = NSColor.systemPurple
            
            // Slight scale animation
            button.animator().alphaValue = 1.0
        }
        
        // Change icon to hanger to indicate wardrobe drop
        button.image = NSImage(systemSymbolName: "hanger", accessibilityDescription: "Drop to Wardrobe")
        showDropPreview(relativeTo: view)
        setDropTargetRing(on: view, active: true)
    }
    
    func menuBarDropViewDidEndHover(_ view: MenuBarDropView) {
        scheduleDropPreviewClose()
    }

    private func restoreMenuBarDropAppearance() {
        guard let button = statusItem?.button else { return }

        hideDropPreview()
        if let dropView = menuBarDropView {
            setDropTargetRing(on: dropView, active: false)
        }
        
        // Restore original appearance
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            button.contentTintColor = nil
        }
        
        // Restore original icon
        if let original = originalButtonImage {
            button.image = original
        } else {
            updateStatusBarIcon() // Fallback to regular update
        }
    }
    
    private func showSuccessFeedback() async {
        guard let button = statusItem?.button else { return }
        
        // Cancel any existing feedback
        feedbackTimer?.invalidate()
        
        // Quick bounce animation and checkmark
        await MainActor.run {
            dropPreviewController?.showSuccess()
            let originalFrame = button.frame
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                button.animator().frame = originalFrame.insetBy(dx: -2, dy: -2)
            }, completionHandler: {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.12
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    button.animator().frame = originalFrame
                })
            })
            
            // Show checkmark briefly
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Added to Wardrobe")
            button.contentTintColor = NSColor.systemGreen
        }
        
        // Wait a moment
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Restore icon
        await MainActor.run {
            hideDropPreview()
            isProcessingMenuBarDrop = false
            if let dropView = menuBarDropView {
                setDropTargetRing(on: dropView, active: false)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                button.contentTintColor = nil
            }
            
            if let original = originalButtonImage {
                button.image = original
                originalButtonImage = nil
            } else {
                updateStatusBarIcon()
            }
        }
    }

    private func showDropPreview(relativeTo dropView: NSView) {
        dropPreviewCloseWorkItem?.cancel()
        dropPreviewSourceApp = NSWorkspace.shared.frontmostApplication
        let controller = dropPreviewController ?? MenuBarDropPreviewViewController()
        controller.onDragEntered = { [weak self] in
            self?.dropPreviewCloseWorkItem?.cancel()
        }
        controller.onDragExited = { [weak self] in
            self?.scheduleDropPreviewClose()
        }
        controller.onDrop = { [weak self] providers in
            guard let self else { return false }
            self.dropPreviewCloseWorkItem?.cancel()
            self.processMenuBarDrop(providers: providers, sourceApp: self.dropPreviewSourceApp)
            return true
        }
        controller.showReady()
        dropPreviewController = controller

        let popover = dropPreviewPopover ?? {
            let popover = NSPopover()
            popover.behavior = .applicationDefined
            popover.animates = true
            popover.contentSize = NSSize(width: 238, height: 76)
            dropPreviewPopover = popover
            return popover
        }()
        popover.contentViewController = controller

        if !popover.isShown {
            popover.show(relativeTo: dropView.bounds, of: dropView, preferredEdge: .minY)
        }
    }

    private func hideDropPreview() {
        dropPreviewCloseWorkItem?.cancel()
        dropPreviewCloseWorkItem = nil
        dropPreviewSourceApp = nil
        dropPreviewPopover?.performClose(nil)
        dropPreviewController?.showReady()
    }

    private func scheduleDropPreviewClose() {
        guard !isProcessingMenuBarDrop else { return }
        dropPreviewCloseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.restoreMenuBarDropAppearance()
        }
        dropPreviewCloseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func setDropTargetRing(on view: NSView, active: Bool, color: NSColor = .systemPurple) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        layer.cornerRadius = max(5, min(view.bounds.width, view.bounds.height) / 2)
        layer.borderWidth = active ? 1.5 : 0
        layer.borderColor = color.cgColor
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = active ? 0.75 : 0
        layer.shadowRadius = active ? 5 : 0
        layer.shadowOffset = .zero
        CATransaction.commit()
    }
    
    private func showErrorFeedback() async {
        guard let button = statusItem?.button else { return }
        
        // Cancel any existing feedback
        feedbackTimer?.invalidate()
        
        // Shake animation
        await MainActor.run {
            let originalFrame = button.frame
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.08
                button.animator().frame = originalFrame.offsetBy(dx: -3, dy: 0)
            }, completionHandler: {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.08
                    button.animator().frame = originalFrame.offsetBy(dx: 3, dy: 0)
                }, completionHandler: {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.08
                        button.animator().frame = originalFrame
                    })
                })
            })
            
            // Show error icon briefly
            button.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Failed")
            button.contentTintColor = NSColor.systemRed
            
            // Play error sound
            NSSound.beep()
        }
        
        // Wait a moment
        try? await Task.sleep(nanoseconds: 800_000_000)
        
        // Restore icon
        await MainActor.run {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                button.contentTintColor = nil
            }
            
            if let original = originalButtonImage {
                button.image = original
                originalButtonImage = nil
            } else {
                updateStatusBarIcon()
            }
        }
    }
}
