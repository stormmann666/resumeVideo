import Foundation

struct AppSettings: Codable, Equatable {
    var channelIdentifier = ""
    var playlistName = "resume"
    var playlistID = ""
    var recipientEmail = ""
    var openRouterModel = "openai/gpt-4.1-mini"
    var summaryPrompt = """
    Resume el vídeo en español. Empieza con una síntesis de 3 a 5 líneas, continúa con las ideas clave en viñetas y termina con acciones o conclusiones útiles. No inventes datos que no aparezcan en el contenido.
    """
    var maximumVideos = 5
}

struct VideoItem: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let addedAt: Date?

    var url: URL? { URL(string: "https://www.youtube.com/watch?v=\(id)") }
}

struct SummaryRecord: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let summary: String
    let videoURL: URL?
    let createdAt: Date
}

struct EmailDraft: Identifiable {
    let id = UUID()
    let recipient: String
    let subject: String
    let body: String
}

enum VideoResumeError: LocalizedError {
    case missingSettings(String)
    case invalidResponse
    case api(String)
    case playlistNotFound(String)
    case noContent(String)

    var errorDescription: String? {
        switch self {
        case .missingSettings(let field): "Falta configurar: \(field)."
        case .invalidResponse: "El servicio devolvió una respuesta no válida."
        case .api(let message): message
        case .playlistNotFound(let name): "No se encontró la playlist pública “\(name)”."
        case .noContent(let title): "No hay contenido suficiente para resumir “\(title)”."
        }
    }
}
