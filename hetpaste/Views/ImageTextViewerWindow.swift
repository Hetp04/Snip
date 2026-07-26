import AppKit
import Vision
import VisionKit
import Combine

// MARK: - Window Controller

final class ImageTextViewerWindowController: NSWindowController {

    private let item: ClipboardItem
    private weak var viewModel: ClipboardHistoryViewModel?

    init(item: ClipboardItem, viewModel: ClipboardHistoryViewModel) {
        self.item      = item
        self.viewModel = viewModel

        let vc = ImageTextViewerVC(item: item, viewModel: viewModel)
        let window = NSWindow(contentViewController: vc)
        window.title           = "Image — \(item.sourceAppName)"
        window.styleMask       = [.titled, .closable, .resizable, .fullSizeContentView, .miniaturizable]
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent  = true
        window.setContentSize(CGSize(width: 800, height: 600))
        window.minSize = CGSize(width: 400, height: 300)
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(item:viewModel:)") }
}

extension ImageTextViewerWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        ImageTextViewerWindowManager.shared.remove(itemID: item.id)
    }
}

// MARK: - View Controller

private final class ImageTextViewerVC: NSViewController {

    // MARK: Properties

    private let item: ClipboardItem
    private weak var viewModel: ClipboardHistoryViewModel?
    private var cancellables = Set<AnyCancellable>()

    // UI
    private let scrollView      = NSScrollView()
    private let imageView       = NSImageView()
    private let overlayView     = ImageAnalysisOverlayView()
    private let spinner         = NSProgressIndicator()
    private let statusLabel     = NSTextField(labelWithString: "")
    private let instructionLabel = NSTextField(labelWithString: "Click and drag to select text  ·  ⌘C to copy")

    // VisionKit
    private let analyzer        = ImageAnalyzer()
    private var currentImage: NSImage?

    // MARK: Init

    init(item: ClipboardItem, viewModel: ClipboardHistoryViewModel) {
        self.item      = item
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor

        // Image view — fills root
        imageView.imageScaling  = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer    = true
        root.addSubview(imageView)

        // VisionKit overlay — pinned to image view, same frame
        // ImageAnalysisOverlayView handles transparency, selection highlight and multi-line
        // selection natively — this is what Preview.app uses for Live Text
        overlayView.preferredInteractionTypes = .textSelection
        overlayView.isHidden = true
        root.addSubview(overlayView)

        // Spinner
        spinner.style           = .spinning
        spinner.controlSize     = .regular
        spinner.isIndeterminate = true
        spinner.isHidden        = true
        root.addSubview(spinner)

        // Status label (no-text / failed state)
        statusLabel.isHidden      = true
        statusLabel.font          = .systemFont(ofSize: 14, weight: .regular)
        statusLabel.textColor     = NSColor.secondaryLabelColor
        statusLabel.alignment     = .center
        statusLabel.isBordered    = false
        statusLabel.drawsBackground = false
        root.addSubview(statusLabel)

        // Instruction bar at the bottom
        instructionLabel.font         = .systemFont(ofSize: 11)
        instructionLabel.textColor    = NSColor.tertiaryLabelColor
        instructionLabel.alignment    = .center
        instructionLabel.isBordered   = false
        instructionLabel.drawsBackground = false
        instructionLabel.isHidden     = true
        root.addSubview(instructionLabel)

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyLayout()

        // Load image from item's local data
        if let data = item.localData, let img = NSImage(data: data) {
            currentImage = img
            imageView.image = img
        }

        // Run VisionKit analysis (replaces our manual OCR pipeline for the viewer)
        runAnalysis()

        // Also observe item mutations in case background OCR updates ocrStatus
        // (used only for the card badge — the viewer drives its own analysis via VisionKit)
        viewModel?.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // No-op: viewer uses its own ImageAnalyzer, not stored OCRBoxes
            }
            .store(in: &cancellables)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyLayout()
    }

    // MARK: - Analysis

    private func runAnalysis() {
        guard let image = currentImage else {
            showStatus("No image data")
            return
        }

        guard ImageAnalyzer.isSupported else {
            showStatus("Live Text not supported on this Mac")
            return
        }

        showSpinner(true)

        Task { @MainActor in
            do {
                let configuration = ImageAnalyzer.Configuration([.text])
                let analysis = try await analyzer.analyze(image, orientation: .up, configuration: configuration)

                showSpinner(false)

                if analysis.hasResults(for: .text) {
                    overlayView.analysis = analysis
                    overlayView.isHidden = false
                    instructionLabel.isHidden = false
                    statusLabel.isHidden = true
                } else {
                    showStatus("No text detected in this image")
                }
            } catch {
                showSpinner(false)
                showStatus("Text recognition failed")
            }
        }
    }

    // MARK: - Layout

    private func applyLayout() {
        let b = view.bounds

        imageView.frame   = b
        // Overlay must exactly match the imageView frame so VisionKit
        // correctly maps its internal coordinate system to screen pixels
        overlayView.frame = b
        overlayView.trackingImageView = imageView

        let sz: CGFloat = 32
        spinner.frame = CGRect(
            x: (b.width  - sz) / 2,
            y: (b.height - sz) / 2,
            width: sz, height: sz
        )

        statusLabel.frame = CGRect(x: 20, y: b.height / 2 - 20, width: b.width - 40, height: 40)
        instructionLabel.frame = CGRect(x: 0, y: 10, width: b.width, height: 20)
    }

    // MARK: - Helpers

    private func showSpinner(_ visible: Bool) {
        spinner.isHidden = !visible
        if visible { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        overlayView.isHidden = true
        statusLabel.isHidden = true
        instructionLabel.isHidden = true
    }

    private func showStatus(_ message: String) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        overlayView.isHidden = true
        instructionLabel.isHidden = true
        statusLabel.stringValue = message
        statusLabel.isHidden = false
    }
}

// MARK: - Window Manager

@MainActor
final class ImageTextViewerWindowManager {
    static let shared = ImageTextViewerWindowManager()
    private init() {}

    private var controllers: [UUID: ImageTextViewerWindowController] = [:]

    func open(item: ClipboardItem, viewModel: ClipboardHistoryViewModel) {
        if let existing = controllers[item.id] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = ImageTextViewerWindowController(item: item, viewModel: viewModel)
        controllers[item.id] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func remove(itemID: UUID) {
        controllers.removeValue(forKey: itemID)
    }
}
