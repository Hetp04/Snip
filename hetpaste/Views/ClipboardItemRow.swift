import SwiftUI
import AppKit
import LinkPresentation
struct ClipboardItemRow: View {
    let item: ClipboardItem
    var isSelected: Bool = false
    var isMostRecent: Bool = false
    var stripMode: Bool = false
    var onToggleFavorite: () -> Void = {}
    var onRetrySync: () -> Void = {}
    var onCopy: () -> Void = {}
    var onDelete: () -> Void = {}   
    var onTrash: () -> Void = {}    
    var isTrashMode: Bool = false
    var isExpanded: Bool = false
    var onRestore: () -> Void = {}
    var onPermanentDelete: () -> Void = {}
    var onExpand: () -> Void = {}
    var onPrimaryTap: (() -> Void)? = nil
    var onDoubleTap: (() -> Void)? = nil
    /// Opens the OCR live-text viewer. If nil falls back to QuickLook.
    var onOpenOCRViewer: (() -> Void)? = nil
    @State private var isHovered: Bool = false
    @State private var isCopyHovered: Bool = false
    @State private var isStarHovered: Bool = false
    @State private var isExpandHovered: Bool = false
    private var headerIcon: NSImage? {
        if let bid = item.sourceAppBundleID, !bid.isEmpty {
            if let img = IconCache.shared.cachedAppIcon(bundleID: bid) {
                return img
            }
            return IconCache.shared.resolveAppIcon(bundleID: bid)
        }
        return nil
    }
    @ViewBuilder
    private var appBadge: some View {
        SoftNeumorphicIconCompact(
            image: headerIcon,
            fallbackSystemName: appIconName,
            fallbackColor: appIconColor,
            size: 20
        )
    }
    private var appIconName: String {
        switch item.sourceAppName.lowercased() {
        case "terminal": return "terminal"
        case "safari": return "safari"
        case "slack": return "number.square"
        case "xcode": return "hammer"
        case "tableplus": return "cylinder.split.1x2"
        case "figma": return "paintbrush.pointed"
        case "chrome": return "globe"
        case "notes": return "note.text"
        case "screenshot": return "camera"
        case "design spec.pdf": return "doc.text"
        case "image": return "photo"
        default: return "app.fill"
        }
    }
    private var appIconColor: Color {
        switch item.sourceAppName.lowercased() {
        case "terminal": return Color(hex: "#1A1A1A")
        case "safari": return Color(hex: "#006CFF")
        case "slack": return Color(hex: "#E01E5A")
        case "xcode": return Color(hex: "#147EFB")
        case "tableplus": return Color(hex: "#F5A623")
        case "figma": return Color(hex: "#A259FF")
        case "chrome": return Color(hex: "#4285F4")
        case "notes": return Color(hex: "#FFCC02")
        case "screenshot": return Color(hex: "#6C7A89")
        case "design spec.pdf": return Color(hex: "#D32F2F")
        case "image": return Color(hex: "#05C46B")
        default: return Theme.textSecondary
        }
    }
    private var isCodeContent: Bool {
        return item.detectedLanguage != nil
    }
    private var resolvedFileURL: URL? {
        item.revealableFileURL
    }
    private func quickViewFile() {
        guard let url = resolvedFileURL else { return }
        QuickLookPreviewer.shared.preview(url: url)
    }
    private func quickViewImage() {
        guard let data = item.localData else { return }
        QuickLookPreviewer.shared.previewImage(data: data, fileName: item.fileName)
    }
    /// Opens the OCR viewer if wired, otherwise falls back to QuickLook.
    private func openOCRViewer() {
        if let onOpenOCRViewer {
            onOpenOCRViewer()
        } else {
            quickViewImage()
        }
    }
    private func openFileInDefaultApp() {
        FileAccessStore.shared.openFile(for: item.id, fallback: item.originalFileURL)
    }
    private func revealFileInFinder() {
        FileAccessStore.shared.revealInFinder(for: item.id, fallback: item.originalFileURL)
    }
    @ViewBuilder
    private var fileActionsContextMenu: some View {
        if resolvedFileURL != nil {
            Button(action: openFileInDefaultApp) {
                Label("Open", systemImage: "arrow.up.forward.app")
            }
            Button(action: quickViewFile) {
                Label("Quick Look", systemImage: "eye")
            }
            Button(action: revealFileInFinder) {
                Label("Reveal in Finder", systemImage: "folder")
            }
        } else if item.contentType == .image {
            Button(action: quickViewImage) {
                Label("Quick Look", systemImage: "eye")
            }
            .disabled(item.localData == nil)
        }
    }
    private var borderColor: Color {
        if isSelected { return Theme.accent }
        if isHovered { return Theme.accent.opacity(0.65) }
        return Theme.border
    }
    private var borderWidth: CGFloat {
        if stripMode { return isSelected || isHovered ? 1 : 0.75 }
        return isSelected || isHovered ? 1.5 : 1
    }
    private var cardFill: Color {
        Theme.card
    }
    private var pasteTypeLabel: String {
        if let lang = item.detectedLanguage { return lang }
        if item.contentType == .file, isPDFFile { return "PDF" }
        switch item.contentType {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .video: return "Video"
        case .file: return "File"
        case .url: return "Link"
        }
    }
    private var pasteHeaderColor: Color {
        if let iconColor = headerIcon?.dominantAccentColor() {
            return iconColor
        }
        return appIconColor
    }
    private var isPDFFile: Bool {
        let name = (item.fileName ?? item.contentText ?? "").lowercased()
        return name.hasSuffix(".pdf") || item.mimeType == "application/pdf"
    }
    private var pasteMetadata: String {
        if item.contentType == .image {
            if let data = item.localData, let image = NSImage(data: data) {
                return "\(Int(image.size.width)) x \(Int(image.size.height))"
            }
            return item.fileSize.map(Formatters.fileSize) ?? "Image"
        }
        if item.contentType == .file || item.contentType == .video {
            if let size = item.fileSize {
                return Formatters.fileSize(size)
            }
            let ext = URL(fileURLWithPath: item.fileName ?? item.contentText ?? "").pathExtension.uppercased()
            return ext.isEmpty ? pasteTypeLabel : ext
        }
        if let text = item.contentText {
            if item.detectedLanguage != nil {
                return "Code"
            }
            return "\(text.count) characters"
        }
        return item.sourceAppName
    }
    private var pasteFooterMetadata: String {
        pasteMetadata
    }
    private var pasteSourceName: String {
        let source = item.sourceAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.isEmpty ? "Unknown App" : source
    }
    private var parsedColor: Color? {
        guard item.contentType == .text || item.contentType == .richText, let text = item.contentText else { return nil }
        return Color.parseColor(from: text)
    }
    @ViewBuilder
    private var largeHeaderAppIcon: some View {
        SoftNeumorphicIcon(
            image: headerIcon,
            fallbackSystemName: appIconName,
            fallbackColor: appIconColor,
            size: 48,
            elevation: .medium
        )
    }
    @ViewBuilder
    private var pasteStyleCard: some View {
        ZStack {
            if let color = parsedColor {
                Theme.card
                VStack(spacing: 0) {
                    ZStack {
                        color
                        Text(item.contentText ?? "")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(color.isLight ? Color.black.opacity(0.75) : Color.white.opacity(0.88))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                    )
                    .padding(14)
                    HStack {
                        Text("Colors")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                        if isTrashMode {
                            Button(action: { onRestore() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.uturn.left")
                                        .font(.system(size: 10, weight: .medium))
                                    Text("Restore")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(Theme.accent)
                            }
                            .buttonStyle(.plain)
                            .help("Restore to history")
                            Button(action: { onPermanentDelete() }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Delete permanently")
                        } else {
                            Button(action: { onCopy() }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.textSecondary)
                                    .opacity(isCopyHovered ? 1.0 : 0.4)
                            }
                            .buttonStyle(.plain)
                            .onHover { isCopyHovered = $0 }
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Theme.card)
                }
            } else {
                VStack(spacing: 0) {
                    pasteHeader
                    pasteContent
                    pasteFooter
                }
            }
        }
        .frame(maxWidth: isExpanded ? 800 : .infinity)
        .frame(height: isExpanded ? 600 : nil)
        .background(Theme.neoBase)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        // Subtle light grey border, or accent border if selected
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(isSelected ? Theme.accent : Color(hex: "#E5E5E5"), lineWidth: isSelected ? 2.5 : 1)
        )
        // Neumorphic Soft Outer Shadow using the library
        .softOuterShadow(
            darkShadow: Color(hex: "#A3B1C6").opacity(0.35),
            lightShadow: Color.white,
            offset: 6,
            radius: 8
        )
        .contentShape(RoundedRectangle(cornerRadius: 24))
        // Double-tap MUST come before single-tap so SwiftUI waits for a possible 2nd tap
        .onTapGesture(count: 2) {
            if let onDoubleTap {
                onDoubleTap()
            } else if resolvedFileURL != nil {
                revealFileInFinder()
            } else if item.contentType == .image {
                openOCRViewer()
            }
        }
        .onTapGesture {
            onPrimaryTap?()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrag {
            let provider = NSItemProvider(object: item.id.uuidString as NSString)
            return provider
        }
        .contextMenu {
            fileActionsContextMenu
        }
    }
    private var pasteHeader: some View {
        let gradients = Theme.appHeaderGradient(for: item.sourceAppName, fallbackColor: pasteHeaderColor)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pasteSourceName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(pasteTypeLabel) · \(item.createdAt.relativeString())")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            largeHeaderAppIcon
                .allowsHitTesting(false)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [gradients.0, gradients.1],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .padding([.horizontal, .top], 10) // inset relative to outer card
    }
    @ViewBuilder
    private var pasteContent: some View {
        ZStack {
            Theme.neoContent
                .softInnerShadow(
                    RoundedRectangle(cornerRadius: 16),
                    darkShadow: Color(hex: "#A3B1C6").opacity(0.35),
                    lightShadow: Color.white,
                    spread: 0.04,
                    radius: 4
                )
            switch item.contentType {
            case .image:
                PasteImagePreview(data: item.localData)
            case .video:
                MiniVideoMockup()
                    .padding(12)
            case .file:
                pasteFilePreview
            case .url:
                pasteURLPreview
            case .text, .richText:
                pasteTextPreview
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isExpanded ? nil : 100)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    @ViewBuilder
    private var pasteTextPreview: some View {
        Group {
            if isCodeContent {
                RichTextCodeView(item: item, lineLimit: isExpanded ? nil : 5, fontSize: 12)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                Text(item.contentText ?? "")
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(isExpanded ? nil : 4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .modifier(OptionalScrollModifier(isScrollable: isExpanded))
    }
    @ViewBuilder
    private var pasteFilePreview: some View {
        HStack(spacing: 12) {
            if let url = resolvedFileURL ?? item.originalFileURL {
                Image(nsImage: IconCache.shared.fileIcon(for: url))
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: isPDFFile ? "doc.richtext.fill" : "doc.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(pasteHeaderColor)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.fileName ?? item.contentText ?? "File")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(2)
            Text(pasteMetadata)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
    }
    @ViewBuilder
    private var pasteURLPreview: some View {
        if let text = item.contentText, let url = URL(string: text), let host = url.host {
            LinkCardPreview(url: url, host: host, accentColor: pasteHeaderColor)
        } else {
            Text(item.contentText ?? "")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
        }
    }
    private var pasteFooter: some View {
        HStack(spacing: 8) {
            Text(pasteFooterMetadata)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            syncBadge
            HStack(spacing: 10) {
                if isTrashMode {
                    Button(action: { onRestore() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.left")
                                .font(.system(size: 10, weight: .light))
                            Text("Restore")
                                .font(.system(size: 10, weight: .light))
                        }
                        .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Restore to history")
                    Button(action: { onPermanentDelete() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .light))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Delete permanently")
                } else {
                    neoIconButton(
                        systemName: "doc.on.doc",
                        isHovered: isCopyHovered,
                        action: { onCopy() }
                    )
                    .onHover { isCopyHovered = $0 }
                    .help("Copy")
                }
                if !isTrashMode {
                    neoIconButton(
                        systemName: item.isPinned ? "star.fill" : "star",
                        isHovered: isStarHovered,
                        isAccent: item.isPinned,
                        accentColor: Theme.starActive,
                        action: { onToggleFavorite() }
                    )
                    .onHover { isStarHovered = $0 }
                    .help("Favorite")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(Theme.neoBase)
    }

    @ViewBuilder
    private func neoIconButton(
        systemName: String,
        isHovered: Bool,
        isAccent: Bool = false,
        accentColor: Color = Theme.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.neoBase)
                    .softInnerShadow(
                        RoundedRectangle(cornerRadius: 8),
                        darkShadow: Color(hex: "#A0AED0").opacity(isHovered ? 0.62 : 0.48),
                        lightShadow: Color.white.opacity(0.92),
                        spread: 0.16,
                        radius: isHovered ? 4.0 : 3.8
                    )
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isAccent ? accentColor : (isHovered ? Theme.textPrimary : Theme.textSecondary))
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
    @ViewBuilder
    private var tappableCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.horizontal, 10)
                .padding(.top, 12)
            Spacer(minLength: 4)
            contentPreviewSection
                .padding(.horizontal, 14)
                .onTapGesture(count: 2) {
                    if let onDoubleTap {
                        onDoubleTap()
                    } else if resolvedFileURL != nil {
                        revealFileInFinder()
                    } else if item.contentType == .image {
                        quickViewImage()
                    }
                }
                .onAppear {
                    if resolvedFileURL != nil || item.originalFileURL != nil,
                       IconCache.shared.cachedFileIcon(forItemId: item.id) == nil,
                       let url = resolvedFileURL ?? item.originalFileURL {
                        let icon = IconCache.shared.fileIcon(for: url)
                        IconCache.shared.saveFileIcon(icon, forItemId: item.id)
                    }
                }
            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onPrimaryTap?()
        }
    }
    @ViewBuilder
    private var headerRow: some View {
        HStack(alignment: .center, spacing: 6) {
            appBadge
            HStack(spacing: 5) {
                Text(item.sourceAppName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isMostRecent {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                        .help("Currently Active Clipboard")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Text(item.createdAt.relativeString())
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "#F7F7F5"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border.opacity(0.65), lineWidth: 0.5)
        )
    }
    @ViewBuilder
    private var contentPreviewSection: some View {
        if item.contentType == .image || item.contentType == .video {
            ZStack {
                if item.contentType == .video {
                    MiniVideoMockup()
                } else {
                    MiniImagePreview(data: item.localData, fitImage: stripMode)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        } else if item.contentType == .file {
            let name = item.fileName ?? item.contentText ?? "File"
            let rawExt = URL(fileURLWithPath: name).pathExtension
            let extUpper = rawExt.uppercased()
            let badge = extUpper.isEmpty ? "FILE" : extUpper
            MiniFileMockup(name: name, size: Formatters.fileSize(item.fileSize), badge: badge, fileTypeExt: rawExt.lowercased(), fileURL: resolvedFileURL ?? item.originalFileURL)
        } else if item.contentType == .url {
            HStack(alignment: .top, spacing: 6) {
                if let t = item.contentText, let u = URL(string: t), let host = u.host {
                    if let icon = IconCache.shared.cachedFavicon(host: host) {
                        Image(nsImage: icon)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .frame(width: 14, height: 14)
                            .cornerRadius(3)
                            .padding(.top, 1)
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.accent)
                            .padding(.top, 2)
                            .onAppear {
                                if let t = item.contentText, let u = URL(string: t), let host = u.host {
                                    IconCache.shared.fetchFavicon(forHost: host) { _ in }
                                }
                            }
                    }
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.accent)
                        .padding(.top, 2)
                }
                Text(item.contentText ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.accent)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        } else {
            Group {
                if isCodeContent {
                    VStack(alignment: .leading, spacing: 0) {
                        RichTextCodeView(item: item, lineLimit: isExpanded ? nil : 6)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.codeBlock)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
                } else {
                    Text(item.contentText ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(isExpanded ? nil : 4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .modifier(OptionalScrollModifier(isScrollable: isExpanded))
        }
    }
    @ViewBuilder
    private var footerRow: some View {
        HStack {
            if item.contentType == .image || item.contentType == .video {
                HStack(spacing: 4) {
                    if item.contentType == .video {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                        Text("0:12")
                            .font(.system(size: 9, weight: .bold))
                    } else {
                        Text("PNG")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hex: "#F1F1EF"))
                .foregroundColor(Theme.textPrimary)
                .cornerRadius(4)
            } else if let lang = item.detectedLanguage {
                HStack(spacing: 6) {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 9, weight: .bold))
                    Text(lang)
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hex: "#F1F1EF"))
                .foregroundColor(Theme.accent)
                .cornerRadius(4)
            } else if item.contentType == .richText {
                HStack(spacing: 6) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 9))
                    Text("Rich Text")
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hex: "#F1F1EF"))
                .foregroundColor(Theme.textPrimary)
                .cornerRadius(4)
            }
            syncBadge
            Spacer()
            HStack(spacing: 9) {
                if isTrashMode {
                    Button(action: { onRestore() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.left")
                                .font(.system(size: 10, weight: .medium))
                            Text("Restore")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Restore to history")
                    Button(action: { onPermanentDelete() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Delete permanently")
                } else {
                    neoIconButton(
                        systemName: "doc.on.doc",
                        isHovered: isCopyHovered,
                        action: { onCopy() }
                    )
                    .onHover { isCopyHovered = $0 }
                    .help("Copy")
                }
                if !isTrashMode {
                    neoIconButton(
                        systemName: item.isPinned ? "star.fill" : "star",
                        isHovered: isStarHovered,
                        isAccent: item.isPinned,
                        accentColor: Theme.starActive,
                        action: { onToggleFavorite() }
                    )
                    .onHover { isStarHovered = $0 }
                    .help("Favorite")
                }
            }
        }
    }
    var body: some View {
        pasteStyleCard
    }
    @ViewBuilder
    private var syncBadge: some View {
        switch item.syncStatus {
        case .pending:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                Text("Syncing")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
            }
        case .failed:
            Button(action: { onRetrySync() }) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.arrow.circlepath")
                        .font(.system(size: 9, weight: .bold))
                    Text("Retry")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(Color(hex: "#D32F2F"))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hex: "#FFEBEB"))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Sync failed — tap to retry")
        case .synced:
            EmptyView()
        }
    }
}
struct MiniImagePreview: View {
    let data: Data?
    var fitImage: Bool = false
    var body: some View {
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .aspectRatio(contentMode: fitImage ? .fit : .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .clipped()
        } else {
            ZStack {
                Theme.codeBlock
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundColor(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
    }
}
struct PasteImagePreview: View {
    let data: Data?
    var body: some View {
        ZStack {
            Color(hex: "#F7F7F5")
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
private struct LinkCardPreview: View {
    let url: URL
    let host: String
    let accentColor: Color
    @State private var title: String?
    @State private var image: NSImage?
    @State private var didRequestMetadata = false
    private var displayHost: String {
        host.replacingOccurrences(of: "www.", with: "")
    }
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .renderingMode(.original)
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [accentColor.opacity(0.88), accentColor.opacity(0.48)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    HStack(spacing: 10) {
                        favicon
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayHost)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(url.absoluteString)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.78))
                                .lineLimit(2)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
            .frame(height: 60)
            .clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(title ?? displayHost)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(displayHost)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.card)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            await loadMetadataIfNeeded()
        }
    }
    @ViewBuilder
    private var favicon: some View {
        if let icon = IconCache.shared.cachedFavicon(host: host) {
            Image(nsImage: icon)
                .resizable()
                .renderingMode(.original)
                .frame(width: 28, height: 28)
                .cornerRadius(6)
        } else {
            Image(systemName: "link")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.18)))
                .onAppear {
                    IconCache.shared.fetchFavicon(forHost: host) { _ in }
                }
        }
    }
    @MainActor
    private func loadMetadataIfNeeded() async {
        guard !didRequestMetadata else { return }
        didRequestMetadata = true
        do {
            let metadata = try await fetchMetadata(for: url)
            title = metadata.title
            if let provider = metadata.imageProvider ?? metadata.iconProvider,
               provider.canLoadObject(ofClass: NSImage.self),
               let loadedImage = try await loadImage(from: provider) {
                image = loadedImage
            }
        } catch {
            title = nil
        }
    }
    private func fetchMetadata(for url: URL) async throws -> LPLinkMetadata {
        try await withCheckedThrowingContinuation { continuation in
            LPMetadataProvider().startFetchingMetadata(for: url) { metadata, error in
                if let metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
        }
    }
    private func loadImage(from provider: NSItemProvider) async throws -> NSImage? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: NSImage.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: object as? NSImage)
                }
            }
        }
    }
}
struct MiniWindowMockup: View {
    var body: some View {
        HStack(spacing: 3) {
            VStack(spacing: 2) {
                Spacer().frame(height: 3)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color(hex: "#E8E8E5"))
                    .frame(width: 8, height: 1.5)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color(hex: "#E8E8E5"))
                    .frame(width: 8, height: 1.5)
                Spacer()
            }
            .frame(width: 14)
            .background(Color(hex: "#F7F7F5"))
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(height: 6)
            }
            .padding(2)
            .background(Color(hex: "#F1F1EF"))
            VStack(spacing: 1.5) {
                Spacer().frame(height: 3)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color(hex: "#E8E8E5"))
                    .frame(width: 12, height: 1.5)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color(hex: "#E8E8E5"))
                    .frame(width: 12, height: 1.5)
                Spacer()
            }
            .frame(width: 18)
            .background(Color.white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 1, y: 1)
    }
}
struct MiniLandscapeMockup: View {
    var body: some View {
        LinearGradient(
            colors: [Color(hex: "#FF7B90"), Color(hex: "#7B90FF"), Color(hex: "#50BFFF")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }
}
struct MiniVideoMockup: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#191919"), Color(hex: "#37352F")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "play.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .cornerRadius(6)
    }
}
struct MiniFileMockup: View {
    let name: String
    let size: String
    let badge: String
    let fileTypeExt: String?
    var fileURL: URL? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let url = fileURL {
                Image(nsImage: IconCache.shared.fileIcon(for: url))
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .frame(width: 28, height: 28)
                    .cornerRadius(4)
            } else if let ext = fileTypeExt, !ext.isEmpty {
                Image(nsImage: NSWorkspace.shared.icon(forFileType: ext))
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .frame(width: 28, height: 28)
                    .cornerRadius(4)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Theme.textPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#F1F1EF"))
                            .cornerRadius(3)
                    }
                    Text(size)
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.codeBlock)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }
}
#Preview {
    VStack(spacing: 8) {
        ClipboardItemRow(
            item: ClipboardItem(
                contentType: .text,
                contentText: "git commit -m \"feat: add supabase integration\"",
                sourceAppName: "Terminal"
            ),
            isMostRecent: true
        )
        ClipboardItemRow(
            item: ClipboardItem(
                contentType: .url,
                contentText: "https://notion.so/workspace/design-system",
                sourceAppName: "Safari"
            )
        )
        ClipboardItemRow(
            item: ClipboardItem(
                contentType: .file,
                contentText: "Design Spec.pdf",
                sourceAppName: "Design Spec.pdf"
            )
        )
    }
    .padding(16)
    .background(Theme.bg)
    .frame(width: 340)
}