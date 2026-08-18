import Foundation

enum EmbeddingError: LocalizedError {
    case notConfigured, paymentRequired, rateLimited(retryAfter: TimeInterval?), invalidResponse(Int), emptyResponse, invalidDimensions
    var errorDescription: String? {
        switch self { case .notConfigured: return "Search unavailable — add OPENROUTER_API_KEY in Config.xcconfig."
        case .paymentRequired: return "Search unavailable — your OpenRouter account needs credits to use text-embedding-3-large."
        case .rateLimited: return "Search is temporarily rate-limited; it will retry automatically."
        case .invalidResponse(let code): return "Search unavailable (embedding request \(code))."
        case .emptyResponse, .invalidDimensions: return "Search unavailable — the embedding service returned no usable vector." }
    }
}

actor EmbeddingService {
    static let shared = EmbeddingService()
    // text-embedding-3-large returns 3072 dimensions by default.
    static let dimensions = 3072
    private let model = "openai/text-embedding-3-large"
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/embeddings")!
    /// Reserve request slots inside this actor. Actor calls can otherwise overlap
    /// at the network await and trigger OpenRouter 429s during a backfill.
    private var nextRequestStart = Date.distantPast

    private var apiKey: String { SecureCredentialStore.openRouterAPIKey }
    var isConfigured: Bool { !apiKey.isEmpty }

    func embed(_ text: String, interactive: Bool = false) async throws -> [Double] {
        guard isConfigured else { throw EmbeddingError.notConfigured }
        // A typed search must never sit behind a long background backfill. It
        // gets an immediate slot; backfill continues using the paced queue.
        let scheduledStart = interactive ? Date() : max(Date(), nextRequestStart)
        if !interactive { nextRequestStart = scheduledStart.addingTimeInterval(1.25) }
        let delay = scheduledStart.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "input": String(text.prefix(2000))])
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            let statusCode = http?.statusCode ?? -1
            if statusCode == 402 { throw EmbeddingError.paymentRequired }
            if statusCode == 429 {
                let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                let wait = retryAfter ?? 5
                nextRequestStart = max(nextRequestStart, Date().addingTimeInterval(wait))
                throw EmbeddingError.rateLimited(retryAfter: retryAfter)
            }
            throw EmbeddingError.invalidResponse(statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]], let vector = rows.first?["embedding"] as? [Double], !vector.isEmpty
        else { throw EmbeddingError.emptyResponse }
        guard vector.count == Self.dimensions else { throw EmbeddingError.invalidDimensions }
        #if DEBUG
        let actualModel = (root["model"] as? String) ?? "not returned"
        print("[Clipboard Search] embedding | requested_model=\(model) | response_model=\(actualModel) | dimensions=\(vector.count)")
        #endif
        return vector
    }

    func embedWithRetry(_ text: String, attempts: Int = 6, interactive: Bool = false) async throws -> [Double] {
        var lastError: Error?
        for attempt in 0..<attempts {
            do { return try await embed(text, interactive: interactive) }
            catch is CancellationError { throw CancellationError() }
            catch EmbeddingError.paymentRequired { throw EmbeddingError.paymentRequired }
            catch EmbeddingError.rateLimited(let retryAfter) {
                lastError = EmbeddingError.rateLimited(retryAfter: retryAfter)
                if attempt < attempts - 1 {
                    let wait = retryAfter ?? min(pow(2, Double(attempt + 1)), 30)
                    #if DEBUG
                    print("[Clipboard Search] embedding rate-limited; retrying in \(Int(wait))s")
                    #endif
                    try await Task.sleep(for: .seconds(wait))
                }
            }
            catch { lastError = error; if attempt < attempts - 1 { try await Task.sleep(for: .seconds(Double(attempt + 1))) } }
        }
        throw lastError ?? EmbeddingError.emptyResponse
    }
}

func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot = 0.0, aa = 0.0, bb = 0.0
    for index in a.indices { dot += a[index] * b[index]; aa += a[index] * a[index]; bb += b[index] * b[index] }
    guard aa > 0, bb > 0 else { return 0 }
    return dot / (sqrt(aa) * sqrt(bb))
}
