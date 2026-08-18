import Foundation
import CryptoKit

enum CardUnderstandingError: LocalizedError {
    case notConfigured, rateLimited(retryAfter: TimeInterval?), requestFailed(Int), emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Card understanding is unavailable — add OPENROUTER_API_KEY in Config.xcconfig."
        case .rateLimited: return "Card understanding is temporarily rate-limited; it will retry automatically."
        case .requestFailed(let statusCode): return "Card understanding request failed (HTTP \(statusCode))."
        case .emptyResponse: return "Card understanding returned no context."
        }
    }
}

/// Converts a clipboard card into factual retrieval context. This is deliberately
/// general-purpose: it describes what a card contains, rather than trying to
/// recognize a fixed list of subjects such as colours or games.
actor CardUnderstandingService {
    static let shared = CardUnderstandingService()
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let model = "qwen/qwen3-32b"
    private var nextRequestStart = Date.distantPast

    private var apiKey: String {
        SecureCredentialStore.openRouterAPIKey
    }

    nonisolated func sourceHash(for item: ClipboardItem) -> String {
        let source = [item.contentType.rawValue, item.contentText ?? item.ocrText ?? item.fileName ?? ""]
            .joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func understand(_ item: ClipboardItem) async throws -> String {
        guard !apiKey.isEmpty else { throw CardUnderstandingError.notConfigured }
        // Reserve a slot before the network await. This prevents the three
        // backfill workers from simultaneously hitting the Responses API.
        let scheduledStart = max(Date(), nextRequestStart)
        nextRequestStart = scheduledStart.addingTimeInterval(2)
        let delay = scheduledStart.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        let rawContent = item.contentText ?? item.ocrText ?? item.fileName ?? ""
        let input = """
        Build a structured memory representation for one private clipboard card. Do not answer the card and do not invent facts. Capture both literal content and meaning a person may remember later. Infer properties only when they are strongly supported by the card's content. Preserve significant exact tokens such as values, URLs, filenames, identifiers, languages, dates, and product names.

        Return only JSON with this exact shape:
        {"summary":"...","concepts":["..."],"attributes":["..."],"aliases":["..."],"likely_queries":["..."]}

        - summary: factual description of the card and its purpose.
        - concepts: main topics, entities, and relationships.
        - attributes: supported qualities, constraints, formats, or concrete properties. For a standard structured notation or value, translate it into the human concepts and qualitative properties it represents whenever that interpretation is well established. Preserve uncertainty rather than guessing when it is not.
        - aliases: alternative natural-language descriptions of the same content.
        - likely_queries: realistic ways a person could describe what they are trying to find later.

        Card type: \(item.contentType.rawValue)
        Source application: \(item.sourceAppName)
        Detected language: \(item.detectedLanguage ?? "unknown")
        Filename: \(item.fileName ?? "none")
        Content:\n\(rawContent)
        """
        let body: [String: Any] = [
            "model": model,
            // The 32B model is capable of reasoning, but routine card extraction
            // stays non-thinking to keep one-time indexing affordable.
            "reasoning": ["enabled": false],
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": input]]
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            let statusCode = http?.statusCode ?? -1
            if statusCode == 429 {
                let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                nextRequestStart = max(nextRequestStart, Date().addingTimeInterval(retryAfter ?? 10))
                throw CardUnderstandingError.rateLimited(retryAfter: retryAfter)
            }
            throw CardUnderstandingError.requestFailed(statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let context = message["content"] as? String,
              !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw CardUnderstandingError.emptyResponse }

        #if DEBUG
        let actualModel = (root["model"] as? String) ?? "not returned"
        print("[Clipboard Search] card understanding | provider=OpenRouter | requested_model=\(model) | response_model=\(actualModel) | input_chars=\(rawContent.count) | context_chars=\(context.count)")
        #endif
        return normalizedContext(from: context)
    }

    func understandWithRetry(_ item: ClipboardItem, attempts: Int = 6) async throws -> String {
        var lastError: Error?
        for attempt in 0..<attempts {
            do { return try await understand(item) }
            catch is CancellationError { throw CancellationError() }
            catch CardUnderstandingError.rateLimited(let retryAfter) {
                lastError = CardUnderstandingError.rateLimited(retryAfter: retryAfter)
                if attempt < attempts - 1 {
                    let wait = retryAfter ?? min(pow(2, Double(attempt + 1)), 30)
                    #if DEBUG
                    print("[Clipboard Search] card understanding rate-limited; retrying in \(Int(wait))s")
                    #endif
                    try await Task.sleep(for: .seconds(wait))
                }
            }
            catch { throw error }
        }
        throw lastError ?? CardUnderstandingError.emptyResponse
    }

    private func normalizedContext(from json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return json }
        let fields = ["summary", "concepts", "attributes", "aliases", "likely_queries"]
        return fields.compactMap { field in
            if let value = object[field] as? String { return "\(field): \(value)" }
            if let values = object[field] as? [String], !values.isEmpty { return "\(field): \(values.joined(separator: "; "))" }
            return nil
        }.joined(separator: "\n")
    }
}
