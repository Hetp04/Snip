import AppKit
import UniformTypeIdentifiers

protocol MenuBarDropViewDelegate: AnyObject {
    func menuBarDropView(_ view: MenuBarDropView, didReceiveDropWithProviders providers: [NSItemProvider], sourceApp: NSRunningApplication?)
    func menuBarDropViewDidBeginHover(_ view: MenuBarDropView)
    func menuBarDropViewDidEndHover(_ view: MenuBarDropView)
}

class MenuBarDropView: NSView {
    static let acceptedDropTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .string, .rtf, .html, .png, .tiff,
        NSPasteboard.PasteboardType(rawValue: "public.data")
    ]

    weak var delegate: MenuBarDropViewDelegate?
    
    private var sourceAppAtDragStart: NSRunningApplication?
    private var isCompletingDrop = false
    private var isHovered = false {
        didSet {
            if isHovered != oldValue {
                if isHovered {
                    delegate?.menuBarDropViewDidBeginHover(self)
                } else if !isCompletingDrop {
                    delegate?.menuBarDropViewDidEndHover(self)
                }
            }
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Accept ALL types - fileURL catches files/folders, others catch content
        registerForDraggedTypes(Self.acceptedDropTypes)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(Self.acceptedDropTypes)
    }
    
    // MARK: - NSDraggingDestination
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Capture frontmost app at the moment drag enters our zone
        // This works reliably because status items don't steal focus
        sourceAppAtDragStart = NSWorkspace.shared.frontmostApplication
        
        // Accept everything - let the view model figure out what to do with it
        isHovered = true
        return .copy
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        isCompletingDrop = false
        isHovered = false
        sourceAppAtDragStart = nil
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // Keep the hover preview visible while the drop is being saved. The
        // delegate replaces it with the success state when saving completes.
        isCompletingDrop = true
        isHovered = false
        
        let capturedSourceApp = sourceAppAtDragStart
        
        // Clear for next drag
        sourceAppAtDragStart = nil
        
        let providers = Self.itemProviders(from: sender.draggingPasteboard)
        
        guard !providers.isEmpty else {
            isCompletingDrop = false
            delegate?.menuBarDropViewDidEndHover(self)
            return false
        }
        
        delegate?.menuBarDropView(self, didReceiveDropWithProviders: providers, sourceApp: capturedSourceApp)
        isCompletingDrop = false
        return true
    }

    static func itemProviders(from pasteboard: NSPasteboard) -> [NSItemProvider] {
        var providers: [NSItemProvider] = []

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            providers.append(contentsOf: urls.map { NSItemProvider(object: $0 as NSURL) })
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            for image in images where image.tiffRepresentation != nil {
                let data = image.tiffRepresentation!
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
                providers.append(provider)
            }
        }

        if let strings = pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String] {
            providers.append(contentsOf: strings.map { string in
                if let url = URL(string: string), url.scheme != nil {
                    return NSItemProvider(object: url as NSURL)
                }
                return NSItemProvider(object: string as NSString)
            })
        }

        if let rtfData = pasteboard.data(forType: .rtf) {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.rtf.identifier, visibility: .all) { completion in
                completion(rtfData, nil)
                return nil
            }
            providers.append(provider)
        }

        return providers
    }
}
