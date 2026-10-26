import Foundation

struct OpenRouterService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func summarize(video: VideoItem, content: String, settings: AppSettings, apiKey: String) async throws -> String {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VideoResumeError.noContent(video.title)
        }
        let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("VideoResume", forHTTPHeaderField: "X-Title")
        let clipped = String(content.prefix(80_000))
        let body = OpenRouterRequest(
            model: settings.openRouterModel,
            messages: [
                .init(role: "system", content: settings.summaryPrompt),
                .init(role: "user", content: "Título: \(video.title)\nURL: \(video.url?.absoluteString ?? "")\n\nContenido:\n\(clipped)")
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VideoResumeError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenRouterErrorEnvelope.self, from: data)
            throw VideoResumeError.api(apiError?.error.message ?? "OpenRouter devolvió el error HTTP \(http.statusCode).")
        }
        let decoded = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        guard let summary = decoded.choices.first?.message.content,
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VideoResumeError.invalidResponse
        }
        return summary
    }
}

private struct OpenRouterRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
}
private struct OpenRouterResponse: Decodable {
    struct Choice: Decodable { let message: Message }
    struct Message: Decodable { let content: String }
    let choices: [Choice]
}
private struct OpenRouterErrorEnvelope: Decodable { let error: APIError }
private struct APIError: Decodable { let message: String }
