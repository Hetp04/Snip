import Foundation
import AppKit

// MARK: - OpenAI Vision OCR Fallback
//
// Uses GPT-4o-mini vision to extract text from images that Apple Vision
// couldn't read (complex layouts, stylized text, mixed image+text, etc.)
// Get your API key at: https://platform.openai.com/api-keys
// Paste it into Config.xcconfig as OPENAI_API_KEY = sk-...

actor OpenAIOCRService {
    static let shared = OpenAIOCRService()
    private init() {}

    // Read from Info.plist (injected by Config.xcconfig → INFOPLIST_KEY_OPENAI_API_KEY)
    private var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String) ?? ""
    }

    var isConfigured: Bool {
        !apiKey.isEmpty && apiKey != "YOUR_OPENAI_API_KEY_HERE"
    }

    // gpt-4o-mini: multimodal, cheap (~$0.001/image), great for OCR tasks
    private let model = "gpt-4o-mini"

    /// Extract text from an NSImage via OpenAI GPT-4o vision.
    func extractText(from image: NSImage) async throws -> String {
        guard isConfigured else { throw OpenAIError.notConfigured }
        guard let tiff   = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png    = bitmap.representation(using: .png, properties: [:])
        else { throw OpenAIError.imageEncodingFailed }
        return try await callOpenAI(imageData: png, mimeType: "image/png")
    }

    /// Overload accepting raw Data — avoids re-decoding from NSImage.
    func extractText(fromData data: Data) async throws -> String {
        guard isConfigured else { throw OpenAIError.notConfigured }
        // Detect PNG vs JPEG from magic bytes
        let mimeType = data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
        return try await callOpenAI(imageData: data, mimeType: mimeType)
    }

    // MARK: - Private

    private func callOpenAI(imageData: Data, mimeType: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        let base64 = imageData.base64EncodedString()
        let dataURI = "data:\(mimeType);base64,\(base64)"

        // OpenAI vision multimodal message format
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2000,
            "messages": [[
                "role": "user",
                "content": [
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": dataURI,
                            "detail": "high"   // high-res mode: more tokens but better accuracy
                        ]
                    ],
                    [
                        "type": "text",
                        "text": """
                        Extract every piece of visible text from this image exactly as it appears. \
                        Include text in UI elements, logos, watermarks, charts, captions, \
                        handwriting, and image overlays. \
                        Return only the extracted text — no commentary, no markdown, no extra formatting.
                        """
                    ]
                ]
            ]]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.networkError }

        print("[OpenAI-OCR] HTTP \(http.statusCode) from \(model)")

        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "<unreadable>"
            print("[OpenAI-OCR] Error body: \(body)")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw OpenAIError.apiError(http.statusCode, message)
            }
            throw OpenAIError.apiError(http.statusCode, "Unknown error")
        }

        // Parse: choices[0].message.content
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first   = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            let raw = String(data: data, encoding: .utf8) ?? "<unreadable>"
            print("[OpenAI-OCR] Parse failed. Raw: \(raw)")
            throw OpenAIError.parseError
        }

        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[OpenAI-OCR] Extracted \(result.count) chars: \(result.prefix(80))...")
        return result
    }
}

// MARK: - Errors

enum OpenAIError: LocalizedError {
    case notConfigured
    case imageEncodingFailed
    case networkError
    case apiError(Int, String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .notConfigured:       return "OpenAI API key not set. Add OPENAI_API_KEY to Config.xcconfig."
        case .imageEncodingFailed: return "Could not encode image for OpenAI."
        case .networkError:        return "Network error contacting OpenAI."
        case .apiError(let c, let m): return "OpenAI API error \(c): \(m)"
        case .parseError:          return "Could not parse OpenAI response."
        }
    }
}
