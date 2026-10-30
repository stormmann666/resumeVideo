import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var settings = AppSettings()
    @Published var youtubeAPIKey = ""
    @Published var openRouterAPIKey = ""
    @Published private(set) var history: [SummaryRecord] = []
    @Published private(set) var textHistory: [TextSummaryRecord] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var isTextProcessing = false
    @Published private(set) var status = "Listo"
    @Published var errorMessage: String?
    @Published private(set) var readVideoIDs: Set<String> = []
    @Published private(set) var readTextIDs: Set<UUID> = []
    @Published private(set) var favoriteVideoIDs: Set<String> = []

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
        textHistory = settingsStore.loadTextHistory()
        readVideoIDs = settingsStore.loadReadVideoIDs()
        readTextIDs = settingsStore.loadReadTextIDs()
        favoriteVideoIDs = settingsStore.loadFavoriteVideoIDs()
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
        let removedIDs = offsets.map { history[$0].id }
        for offset in offsets.sorted(by: >) {
            history.remove(at: offset)
        }
        readVideoIDs.subtract(removedIDs)
        settingsStore.saveReadVideoIDs(readVideoIDs)
        favoriteVideoIDs.subtract(removedIDs)
        settingsStore.saveFavoriteVideoIDs(favoriteVideoIDs)
        persistHistoryAfterDeletion()
    }

    func deleteSummary(_ record: SummaryRecord) {
        history.removeAll { $0.id == record.id }
        readVideoIDs.remove(record.id)
        settingsStore.saveReadVideoIDs(readVideoIDs)
        favoriteVideoIDs.remove(record.id)
        settingsStore.saveFavoriteVideoIDs(favoriteVideoIDs)
        persistHistoryAfterDeletion()
    }

    func discardSummary(_ record: SummaryRecord) {
        history.removeAll { $0.id == record.id }
        processedVideoIDs.remove(record.id)
        readVideoIDs.remove(record.id)
        favoriteVideoIDs.remove(record.id)
        do {
            try settingsStore.saveHistory(history)
            settingsStore.saveProcessedVideoIDs(processedVideoIDs)
            settingsStore.saveReadVideoIDs(readVideoIDs)
            settingsStore.saveFavoriteVideoIDs(favoriteVideoIDs)
            status = "Resumen descartado; se procesará de nuevo al refrescar"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createTextSummary(title: String, text: String, source: TextSummarySource) async -> Bool {
        guard !isTextProcessing else { return false }
        do {
            try validateOpenRouterSettings()
            let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty else { throw VideoResumeError.noContent(title) }
            isTextProcessing = true
            status = "Resumiendo texto…"
            let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "\(source.title) – \(Date.now.formatted(date: .abbreviated, time: .shortened))"
                : title.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = try await openRouter.summarizeText(
                title: resolvedTitle,
                content: cleanText,
                settings: settings,
                apiKey: openRouterAPIKey
            )
            let record = TextSummaryRecord(
                id: UUID(),
                title: resolvedTitle,
                source: source,
                originalText: cleanText,
                summary: summary,
                createdAt: .now
            )
            textHistory.insert(record, at: 0)
            try settingsStore.saveTextHistory(textHistory)
            status = "Resumen de texto guardado"
            isTextProcessing = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            status = "No se pudo resumir el texto"
            isTextProcessing = false
            return false
        }
    }

    func deleteTextSummaries(at offsets: IndexSet) {
        let removedIDs = offsets.map { textHistory[$0].id }
        for offset in offsets.sorted(by: >) {
            textHistory.remove(at: offset)
        }
        readTextIDs.subtract(removedIDs)
        settingsStore.saveReadTextIDs(readTextIDs)
        persistTextHistory()
    }

    func deleteTextSummary(_ record: TextSummaryRecord) {
        textHistory.removeAll { $0.id == record.id }
        readTextIDs.remove(record.id)
        settingsStore.saveReadTextIDs(readTextIDs)
        persistTextHistory()
    }

    func isVideoSummaryRead(_ record: SummaryRecord) -> Bool {
        readVideoIDs.contains(record.id)
    }

    func markVideoSummaryRead(_ record: SummaryRecord) {
        guard readVideoIDs.insert(record.id).inserted else { return }
        settingsStore.saveReadVideoIDs(readVideoIDs)
    }

    func isFavorite(_ record: SummaryRecord) -> Bool {
        favoriteVideoIDs.contains(record.id)
    }

    func toggleFavorite(_ record: SummaryRecord) {
        if favoriteVideoIDs.contains(record.id) {
            favoriteVideoIDs.remove(record.id)
            status = "Eliminado de favoritos"
        } else {
            favoriteVideoIDs.insert(record.id)
            status = "Añadido a favoritos"
        }
        settingsStore.saveFavoriteVideoIDs(favoriteVideoIDs)
    }

    var favoriteHistory: [SummaryRecord] {
        history.filter { favoriteVideoIDs.contains($0.id) }
    }

    func isTextSummaryRead(_ record: TextSummaryRecord) -> Bool {
        readTextIDs.contains(record.id)
    }

    func markTextSummaryRead(_ record: TextSummaryRecord) {
        guard readTextIDs.insert(record.id).inserted else { return }
        settingsStore.saveReadTextIDs(readTextIDs)
    }

    var unreadVideoCount: Int {
        history.reduce(into: 0) { count, record in
            if !readVideoIDs.contains(record.id) { count += 1 }
        }
    }

    var unreadTextCount: Int {
        textHistory.reduce(into: 0) { count, record in
            if !readTextIDs.contains(record.id) { count += 1 }
        }
    }

    private func validateSettings() throws {
        if youtubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw VideoResumeError.missingSettings("API key de YouTube")
        }
        if settings.playlistID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            settings.channelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw VideoResumeError.missingSettings("canal o ID de playlist")
        }
        try validateOpenRouterSettings()
    }

    private func validateOpenRouterSettings() throws {
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

    private func persistTextHistory() {
        do {
            try settingsStore.saveTextHistory(textHistory)
            status = "Resumen de texto eliminado"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
