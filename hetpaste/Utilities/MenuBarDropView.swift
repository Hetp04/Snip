import AppKit
import UniformTypeIdentifiers

protocol MenuBarDropViewDelegate: AnyObject {
    func menuBarDropView(_ view: MenuBarDropView, didReceiveDropWithProviders providers: [NSItemProvider], sourceApp: NSRunningApplication?)
    func menuBarDropViewDidBeginHover(_ view: MenuBarDropView)
    func menuBarDropViewDidEndHover(_ view: MenuBarDropView)
}

class MenuBarDropView: NSView {
    weak var delegate: MenuBarDropViewDelegate?
    
    private var sourceAppAtDragStart: NSRunningApplication?
    private var isHovered = false {
        didSet {
            if isHovered != oldValue {
                if isHovered {
                    delegate?.menuBarDropViewDidBeginHover(self)
                } else {
                    delegate?.menuBarDropViewDidEndHover(self)
                }
            }
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Accept ALL types - fileURL catches files/folders, others catch content
        registerForDraggedTypes([
            .fileURL,      // Files, folders, anything from Finder
            .URL,          // Web links
            .string,       // Text content
            .rtf,          // Rich text
            .html,         // HTML content
            .png,          // Images
            .tiff,         // Images
            NSPasteboard.PasteboardType(rawValue: "public.data")  // Generic data fallback
        ])
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([
            .fileURL,
            .URL,
            .string,
            .rtf,
            .html,
            .png,
            .tiff,
            NSPasteboard.PasteboardType(rawValue: "public.data")
        ])
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
        isHovered = false
        sourceAppAtDragStart = nil
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHovered = false
        
        let pasteboard = sender.draggingPasteboard
        let capturedSourceApp = sourceAppAtDragStart
        
        // Clear for next drag
        sourceAppAtDragStart = nil
        
        // Convert pasteboard items to NSItemProviders
        var providers: [NSItemProvider] = []
        
        // Handle file URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                providers.append(NSItemProvider(object: url as NSURL))
            }
        }
        
        // Handle images
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            for image in images {
                if let tiffData = image.tiffRepresentation {
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                        completion(tiffData, nil)
                        return nil
                    }
                    providers.append(provider)
                }
            }
        }
        
        // Handle strings (text, URLs)
        if let strings = pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String] {
            for string in strings {
                // Check if it's a URL
                if let url = URL(string: string), url.scheme != nil {
                    providers.append(NSItemProvider(object: url as NSURL))
                } else {
                    providers.append(NSItemProvider(object: string as NSString))
                }
            }
        }
        
        // Handle RTF
        if let rtfData = pasteboard.data(forType: .rtf) {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.rtf.identifier, visibility: .all) { completion in
                completion(rtfData, nil)
                return nil
            }
            providers.append(provider)
        }
        
        guard !providers.isEmpty else {
            return false
        }
        
        delegate?.menuBarDropView(self, didReceiveDropWithProviders: providers, sourceApp: capturedSourceApp)
        return true
    }
}
