import Foundation

struct SettingsStore {
    private let settingsKey = "videoResume.settings.v1"
    private let historyKey = "videoResume.history.v1"
    private let processedVideoIDsKey = "videoResume.processedVideoIDs.v1"
    private let defaults = UserDefaults.standard

    func loadSettings() -> AppSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let value = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return value
    }

    func saveSettings(_ settings: AppSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: settingsKey)
    }

    func loadHistory() -> [SummaryRecord] {
        guard let data = defaults.data(forKey: historyKey),
              let value = try? JSONDecoder().decode([SummaryRecord].self, from: data) else {
            return []
        }
        return value.sorted { $0.createdAt > $1.createdAt }
    }

    func saveHistory(_ records: [SummaryRecord]) throws {
        defaults.set(try JSONEncoder().encode(records), forKey: historyKey)
    }

    func loadProcessedVideoIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: processedVideoIDsKey) ?? [])
    }

    func saveProcessedVideoIDs(_ ids: Set<String>) {
        defaults.set(ids.sorted(), forKey: processedVideoIDsKey)
    }
}
