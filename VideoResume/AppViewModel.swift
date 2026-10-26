import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var settings = AppSettings()
    @Published var youtubeAPIKey = ""
    @Published var openRouterAPIKey = ""
    @Published private(set) var history: [SummaryRecord] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var status = "Listo"
    @Published var errorMessage: String?
    @Published var emailDraft: EmailDraft?

    private let settingsStore = SettingsStore()
    private let keychain = KeychainStore()
    private let youtube = YouTubeService()
    private let openRouter = OpenRouterService()

    func load() async {
        settings = settingsStore.loadSettings()
        youtubeAPIKey = keychain.read(.youtubeAPIKey)
        openRouterAPIKey = keychain.read(.openRouterAPIKey)
        history = settingsStore.loadHistory()
    }

    func saveSettings() {
        do {
            try settingsStore.saveSettings(settings)
            try keychain.write(youtubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), for: .youtubeAPIKey)
            try keychain.write(openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), for: .openRouterAPIKey)
            status = "Ajustes guardados"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func processNewVideos() async {
        guard !isProcessing else { return }
        do {
            try validateSettings()
            isProcessing = true
            status = "Consultando la playlist…"
            let videos = try await youtube.latestVideos(settings: settings, apiKey: youtubeAPIKey)
            let processed = Set(history.map(\.id))
            let pending = videos.filter { !processed.contains($0.id) }.prefix(max(1, settings.maximumVideos))
            guard !pending.isEmpty else {
                status = "No hay vídeos nuevos"
                isProcessing = false
                return
            }

            var newRecords: [SummaryRecord] = []
            var failures: [String] = []
            for (index, video) in pending.enumerated() {
                status = "Resumiendo \(index + 1) de \(pending.count): \(video.title)"
                do {
                    let transcript = await youtube.transcript(for: video)
                    let fallback = "Título: \(video.title)\n\nDescripción:\n\(video.description)"
                    let summary = try await openRouter.summarize(
                        video: video,
                        content: transcript ?? fallback,
                        settings: settings,
                        apiKey: openRouterAPIKey
                    )
                    let record = SummaryRecord(
                        id: video.id,
                        title: video.title,
                        summary: summary,
                        videoURL: video.url,
                        createdAt: .now
                    )
                    newRecords.append(record)
                    history.insert(record, at: 0)
                    try settingsStore.saveHistory(history)
                } catch {
                    failures.append("\(video.title): \(error.localizedDescription)")
                }
            }

            if !newRecords.isEmpty {
                emailDraft = makeEmail(records: newRecords)
            }
            if failures.isEmpty {
                status = "\(newRecords.count) vídeo(s) resumido(s)"
            } else {
                status = "\(newRecords.count) resumido(s), \(failures.count) con error"
                errorMessage = failures.joined(separator: "\n\n")
            }
        } catch {
            errorMessage = error.localizedDescription
            status = "No se pudo completar"
        }
        isProcessing = false
    }

    func prepareEmail(for record: SummaryRecord) {
        emailDraft = makeEmail(records: [record])
    }

    private func validateSettings() throws {
        if youtubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw VideoResumeError.missingSettings("API key de YouTube")
        }
        if settings.playlistID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            settings.channelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw VideoResumeError.missingSettings("canal o ID de playlist")
        }
        if openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw VideoResumeError.missingSettings("API key de OpenRouter")
        }
        if settings.openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw VideoResumeError.missingSettings("modelo de OpenRouter")
        }
        if settings.recipientEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw VideoResumeError.missingSettings("email destinatario")
        }
    }

    private func makeEmail(records: [SummaryRecord]) -> EmailDraft {
        let body = records.map { record in
            """
            \(record.title)
            \(record.videoURL?.absoluteString ?? "")

            \(record.summary)
            """
        }.joined(separator: "\n\n────────────\n\n")
        return EmailDraft(
            recipient: settings.recipientEmail,
            subject: records.count == 1 ? "VideoResume: \(records[0].title)" : "VideoResume: \(records.count) vídeos nuevos",
            body: body
        )
    }
}
