import AppKit
import Vision

// MARK: - Data Models

struct OCRBox: Codable, Equatable {
    let text: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// MARK: - Service

actor OCRService {
    static let shared = OCRService()
    private init() {}

    /// Recognize text in an image following Apple's Vision docs exactly.
    func recognizeText(in image: NSImage) async throws -> [OCRBox] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }
        let imageWidth  = cgImage.width
        let imageHeight = cgImage.height

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let boxes: [OCRBox] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first,
                          !candidate.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else { return nil }

                    // Per Apple docs: use candidate.boundingBox(for: stringRange)
                    let stringRange = candidate.string.startIndex..<candidate.string.endIndex
                    let boxObservation = try? candidate.boundingBox(for: stringRange)
                    let normalizedBox = boxObservation?.boundingBox ?? observation.boundingBox

                    // Validate using VNImageRectForNormalizedRect
                    let pixelRect = VNImageRectForNormalizedRect(normalizedBox, imageWidth, imageHeight)
                    guard pixelRect.width > 0, pixelRect.height > 0 else { return nil }

                    return OCRBox(
                        text: candidate.string,
                        x: normalizedBox.origin.x,
                        y: normalizedBox.origin.y,
                        width: normalizedBox.width,
                        height: normalizedBox.height
                    )
                }
                continuation.resume(returning: boxes)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum OCRError: LocalizedError {
    case invalidImage
    var errorDescription: String? { "Could not extract a CGImage." }
}
