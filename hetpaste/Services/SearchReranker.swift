import Foundation

enum SearchRerankerError: LocalizedError {
    case notConfigured, requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI reranking is unavailable — add OPENROUTER_API_KEY in Config.xcconfig."
        case .requestFailed(let statusCode):
            return "AI reranking request failed (HTTP \(statusCode))."
        }
    }
}

struct SearchRerankCandidate: Sendable {
    let id: UUID
    /// Source content is authoritative. AI-generated context is deliberately
    /// separate so it can help discovery without being mistaken for proof.
    let rawContent: String
    let derivedContext: String?
    let sourceApp: String
    let createdAt: Date
}

struct SearchRerankDecision: Sendable {
    let id: UUID
    let verdict: String
    /// Short, card-specific support for the result. Requiring it prevents the
    /// model from selecting a card on a vague association alone.
    let evidence: String
    let confidence: Double
}

/// Second-stage retrieval: an LLM judges a small semantic candidate set against
/// the user's complete request. It is intentionally topic-agnostic.
actor SearchReranker {
    static let shared = SearchReranker()
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let model = "qwen/qwen3-32b"

    private var apiKey: String {
        SecureCredentialStore.openRouterAPIKey
    }

    func rerank(query: String, candidates: [SearchRerankCandidate]) async throws -> [SearchRerankDecision] {
        guard !apiKey.isEmpty else { throw SearchRerankerError.notConfigured }
        guard !candidates.isEmpty else { return [] }
        let encoder = ISO8601DateFormatter()
        let candidateText = candidates.map { candidate in
            "ID: \(candidate.id.uuidString)\nSource: \(candidate.sourceApp)\nCreated: \(encoder.string(from: candidate.createdAt))\nAUTHORITATIVE CARD CONTENT:\n\(candidate.rawContent.prefix(1_200))\n\nDERIVED SEARCH MEMORY (discovery aid only, not proof):\n\(candidate.derivedContext?.prefix(900) ?? "none")"
        }.joined(separator: "\n\n---\n\n")

        let instructions = """
        You are the verification stage of a clipboard search system, not a suggestion engine. Select a card only when it actually satisfies the user's complete request: meaning, relationships, constraints, quantities, exclusions, and time qualifiers—not merely a shared topic or broad category.

        AUTHORITATIVE CARD CONTENT is the source of truth. DERIVED SEARCH MEMORY was generated earlier and may be generic, incomplete, or wrong. It may help you notice a candidate, but you must independently verify it against the authoritative content. Never select a card solely because its derived memory says it belongs to a broad class.

        For any_of, a card may satisfy one independent requested alternative, but must clearly satisfy that alternative. For all_in_one, it must satisfy every requested condition together. Reject partial matches, tangential associations, debug/log/configuration text, copied queries, and ambiguous cards. It is correct to return no results.

        Every accepted result needs concise evidence grounded in a concrete fact from AUTHORITATIVE CARD CONTENT. Only use verdict "accept" when that fact proves the match. Return the strongest 3 by default; return more only if every additional card independently passes this test.

        User request: \(query)

        Candidates:
        \(candidateText)
        """
        let body: [String: Any] = [
            "model": model,
            // Semantic retrieval has already narrowed the set. Fast direct
            // judgment is better UX than generating a long reasoning trace.
            "reasoning": ["enabled": false],
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": "You are a precise retrieval verifier. Return only JSON in the form {\\\"results\\\":[{\\\"id\\\":\\\"UUID\\\",\\\"verdict\\\":\\\"accept\\\",\\\"evidence\\\":\\\"specific source-supported fact\\\",\\\"confidence\\\":0.0}]}.\n\n\(instructions)"]]
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SearchRerankerError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let jsonData = cleanJSON(content).data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let entries = result["results"] as? [[String: Any]]
        else { throw EmbeddingError.emptyResponse }

        #if DEBUG
        let actualModel = (root["model"] as? String) ?? "not returned"
        let responseID = (root["id"] as? String) ?? "not returned"
        print("[Clipboard Search] AI reranker | provider=OpenRouter | requested_model=\(model) | response_model=\(actualModel) | response_id=\(responseID)")
        #endif

        let allowed = Set(candidates.map(\.id))
        return entries.compactMap { entry in
            guard let idString = entry["id"] as? String,
                  let id = UUID(uuidString: idString),
                  allowed.contains(id),
                  let verdict = entry["verdict"] as? String,
                  verdict.lowercased() == "accept",
                  let evidence = entry["evidence"] as? String,
                  !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            let confidence = (entry["confidence"] as? NSNumber)?.doubleValue ?? 0.5
            return SearchRerankDecision(id: id, verdict: verdict, evidence: evidence, confidence: confidence)
        }
    }

    private func cleanJSON(_ content: String) -> String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
