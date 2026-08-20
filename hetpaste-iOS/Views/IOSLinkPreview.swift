import CryptoKit
import LinkPresentation
import SwiftUI
import UIKit

private struct IOSCachedLinkPreview {
    let title: String?
    let image: UIImage?
}

@MainActor
private final class IOSLinkPreviewCache {
    static let shared = IOSLinkPreviewCache()
    private var memory: [String: IOSCachedLinkPreview] = [:]
    private let fileManager = FileManager.default

    private func key(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func directory() -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("hetpaste/LinkPreviews", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func cached(for url: URL) -> IOSCachedLinkPreview? {
        let key = key(for: url)
        if let cached = memory[key] { return cached }
        let root = directory()
        let title = try? String(contentsOf: root.appendingPathComponent(key).appendingPathExtension("txt"), encoding: .utf8)
        let image = UIImage(contentsOfFile: root.appendingPathComponent(key).appendingPathExtension("png").path)
        guard title != nil || image != nil else { return nil }
        let result = IOSCachedLinkPreview(title: title, image: image)
        memory[key] = result
        return result
    }

    func fetchIfNeeded(for url: URL) async -> IOSCachedLinkPreview? {
        if let cached = cached(for: url) { return cached }
        guard let metadata = try? await metadata(for: url) else { return nil }
        let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryImage = await loadImage(from: metadata.imageProvider)
        let image: UIImage?
        if let primaryImage {
            image = primaryImage
        } else {
            image = await loadImage(from: metadata.iconProvider)
        }
        guard title?.isEmpty == false || image != nil else { return nil }
        let result = IOSCachedLinkPreview(title: title, image: image)
        let key = key(for: url)
        memory[key] = result
        let root = directory()
        if let title { try? title.write(to: root.appendingPathComponent(key).appendingPathExtension("txt"), atomically: true, encoding: .utf8) }
        if let image, let data = image.pngData() { try? data.write(to: root.appendingPathComponent(key).appendingPathExtension("png"), options: .atomic) }
        return result
    }

    private func metadata(for url: URL) async throws -> LPLinkMetadata {
        try await withCheckedThrowingContinuation { continuation in
            LPMetadataProvider().startFetchingMetadata(for: url) { metadata, error in
                if let metadata { continuation.resume(returning: metadata) }
                else { continuation.resume(throwing: error ?? URLError(.badServerResponse)) }
            }
        }
    }

    private func loadImage(from provider: NSItemProvider?) async -> UIImage? {
        guard let provider, provider.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }
}

struct IOSLinkPreview: View {
    let url: URL
    @State private var preview: IOSCachedLinkPreview?

    private var host: String { (url.host ?? url.absoluteString).replacingOccurrences(of: "www.", with: "") }

    var body: some View {
        HStack(spacing: 10) {
            if let image = preview?.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(Image(systemName: "link").foregroundStyle(Color.accentColor))
                    .frame(width: 54, height: 54)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(preview?.title?.isEmpty == false ? preview!.title! : host)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IOSTheme.textPrimary)
                    .lineLimit(2)
                Text(host)
                    .font(.system(size: 10))
                    .foregroundStyle(IOSTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(IOSTheme.neoContent)
        .task(id: url) {
            preview = IOSLinkPreviewCache.shared.cached(for: url)
            if preview == nil { preview = await IOSLinkPreviewCache.shared.fetchIfNeeded(for: url) }
        }
    }
}
