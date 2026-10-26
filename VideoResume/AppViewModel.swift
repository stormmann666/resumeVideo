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

    private let settingsStore = SettingsStore()
    private let keychain = KeychainStore()
    private let youtube = YouTubeService()
    private let openRouter = OpenRouterService()
    private var processedVideoIDs: Set<String> = []

    func load() async {
        settings = settingsStore.loadSettings()
        youtubeAPIKey = keychain.read(.youtubeAPIKey)
        openRouterAPIKey = keychain.read(.openRouterAPIKey)
        history = settingsStore.loadHistory()
        // Migra instalaciones anteriores, donde el historial también hacía de registro.
        processedVideoIDs = settingsStore.loadProcessedVideoIDs().union(history.map(\.id))
        settingsStore.saveProcessedVideoIDs(processedVideoIDs)
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
            let pending = videos.filter { !processedVideoIDs.contains($0.id) }.prefix(max(1, settings.maximumVideos))
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
                    processedVideoIDs.insert(video.id)
                    settingsStore.saveProcessedVideoIDs(processedVideoIDs)
                } catch {
                    failures.append("\(video.title): \(error.localizedDescription)")
                }
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

    func deleteSummaries(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            history.remove(at: offset)
        }
        persistHistoryAfterDeletion()
    }

    func deleteSummary(_ record: SummaryRecord) {
        history.removeAll { $0.id == record.id }
        persistHistoryAfterDeletion()
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
    }

    private func persistHistoryAfterDeletion() {
        do {
            try settingsStore.saveHistory(history)
            status = "Resumen eliminado"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
