import Foundation

struct SearchIntentAnalysis: Sendable {
    let semanticQuery: String
    let matchMode: String
    let retrievalQueries: [String]
    let logic: String
    let requiredConstraints: [String]
    let exclusions: [String]
    let relatedConcepts: [String]
    let searchPhrases: [String]

    var retrievalText: String {
        (["Matching mode: \(matchMode)", "Logic: \(logic)", semanticQuery] + requiredConstraints + exclusions.map { "Exclude: \($0)" } + relatedConcepts + searchPhrases)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// Converts a person's imperfect memory into a faithful retrieval intent. This
/// is domain-neutral: it does not contain rules for colours, games, code, etc.
actor SearchIntentService {
    static let shared = SearchIntentService()
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let model = "qwen/qwen3-32b"

    private var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "OPENROUTER_API_KEY") as? String) ?? ""
    }

    func analyze(_ query: String) async throws -> SearchIntentAnalysis {
        guard !apiKey.isEmpty, !apiKey.contains("YOUR_") else { throw EmbeddingError.notConfigured }
        let prompt = """
        Interpret a clipboard-search request. Preserve every explicit constraint. Do not assume facts about the user's clipboard and do not turn a broad request into a narrow one. Expand implied meaning into neutral retrieval language and likely paraphrases.

        Return only JSON: {"semantic_query":"...","match_mode":"any_of or all_in_one","logic":"...","retrieval_queries":["..."],"required_constraints":["..."],"exclusions":["..."],"related_concepts":["..."],"search_phrases":["..."]}

        Use any_of when the user is listing separate examples/categories they would be happy to find individually. Use all_in_one only when they explicitly need a single card to combine every requested condition.

        retrieval_queries must be the independent semantic paths worth searching. For a request with alternatives, include one focused query for each alternative. For a compound request, include focused paths that preserve the mandatory constraints. logic must plainly state how the candidate paths combine (for example, "one result may match either X or Y" or "a result must match X and Y together"). This works for any subject; do not use domain-specific rules.

        User request: \(query)
        """
        let body: [String: Any] = [
            "model": model,
            "reasoning": ["enabled": false],
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": prompt]]
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
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
              let json = content.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        else { throw EmbeddingError.emptyResponse }

        let analysis = SearchIntentAnalysis(
            semanticQuery: object["semantic_query"] as? String ?? query,
            matchMode: object["match_mode"] as? String ?? "all_in_one",
            retrievalQueries: object["retrieval_queries"] as? [String] ?? [object["semantic_query"] as? String ?? query],
            logic: object["logic"] as? String ?? "A result must match the complete request.",
            requiredConstraints: object["required_constraints"] as? [String] ?? [],
            exclusions: object["exclusions"] as? [String] ?? [],
            relatedConcepts: object["related_concepts"] as? [String] ?? [],
            searchPhrases: object["search_phrases"] as? [String] ?? []
        )
        #if DEBUG
        print("[Clipboard Search] intent analysis | provider=OpenRouter | model=\(model) | semantic_query=\(analysis.semanticQuery.debugDescription) | constraints=\(analysis.requiredConstraints)")
        #endif
        return analysis
    }
}
